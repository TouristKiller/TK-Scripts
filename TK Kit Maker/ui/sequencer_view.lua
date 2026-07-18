local r = reaper
local Theme = require("core.theme")
local Naming = require("core.naming")
local json = require("core.json")
local EngineJSFX = require("data.seq_engine_jsfx")

local M = {}

local GRID_SLOTS = 16
local BASE_NOTE = 36
local STEPS_PER_BAR = 16
local PATTERN_SLOTS = 4
local EXT_KEY = "P_EXT:TK_KIT_MAKER_SEQ"
local ENGINE_ID_KEY = "P_EXT:TK_KIT_MAKER_SEQ_ENGINE_ID"
local BUS_MARKER = "P_EXT:TK_KIT_MAKER_SEQ_BUS"
local GLOBAL_PATTERN_SECTION = "TK_KIT_MAKER_SEQ"
local GLOBAL_PATTERN_KEY = "GLOBAL_PATTERNS"
local SUBSTEP_LOOKAHEAD_MIN = 0.001
local SUBSTEP_LOOKAHEAD_MAX = 0.004
local table_step_value
local find_param_index
local collect_lane_tracks
local rs5k_pitch_param_cache = {}
local rs5k_pan_param_cache = {}
local rs5k_volume_param_cache = {}

local GMEM_NAME = "TKKitMakerSeq"
local G_EPOCH, G_RUN, G_SYNC, G_TEMPO, G_TOTAL, G_SOLO, G_RESTART, G_NLANES, G_BASE, G_ACTIVE = 0, 1, 2, 3, 4, 5, 6, 7, 8, 9
local G_ALIVE, G_PH, G_LANEPH = 16, 17, 32
local G_NOTES = 18
local LANE_BASE, LANE_STRIDE = 128, 128
local L_CYCLE, L_SPEED, L_SOLO, L_MODE, L_RETRIG, L_NOTE, L_OBEY = 0, 1, 2, 3, 4, 5, 6
local L_ON, L_VEL, L_GATE, L_LEN, L_SUB, L_PROB = 16, 32, 48, 64, 80, 96
local engine_attached = false
local engine_installed = false
local engine_reinstalled = false
local engine_parent_cleaned = false
local engine_restart_seq = 0
local engine_epoch = 0

local function clamp(v, mn, mx)
  return math.max(mn, math.min(mx, v))
end

local function linear_to_db(v)
  local n = tonumber(v) or 1
  if n <= 0.000001 then
    return -60
  end
  return 20 * (math.log(n) / math.log(10))
end

local function db_to_linear(db)
  local n = tonumber(db) or 0
  return 10 ^ (n / 20)
end

local function normalize_lane_speed(value)
  local n = tonumber(value) or 1
  if n == 0.5 or n == 2 then
    return n
  end
  return 1
end

local function next_lane_speed(value)
  local n = normalize_lane_speed(value)
  if n == 1 then
    return 0.5
  end
  if n == 0.5 then
    return 2
  end
  return 1
end

local function lane_speed_label(value)
  local n = normalize_lane_speed(value)
  if n == 0.5 then
    return "0.5x"
  end
  if n == 2 then
    return "2x"
  end
  return "1x"
end

local function clamp_byte(v)
  return clamp(math.floor((tonumber(v) or 0) + 0.5), 0, 255)
end

local function parse_param_display_number(text)
  local s = tostring(text or ""):lower()
  if s:find("inf", 1, true) then
    if s:find("-", 1, true) then
      return -150
    end
    return 150
  end
  return tonumber(s:match("[-+]?%d+%.?%d*"))
end

local function unpack_rgb(c)
  local n = math.floor(tonumber(c) or 0)
  return (n >> 24) & 0xFF, (n >> 16) & 0xFF, (n >> 8) & 0xFF
end

local function pack_rgb(r8, g8, b8)
  return ((clamp_byte(r8) & 0xFF) << 24) | ((clamp_byte(g8) & 0xFF) << 16) | ((clamp_byte(b8) & 0xFF) << 8) | 0xFF
end

local function blend_rgb(a, b, t)
  local k = clamp(tonumber(t) or 0, 0, 1)
  local ar, ag, ab = unpack_rgb(a)
  local br, bg, bb = unpack_rgb(b)
  return pack_rgb(ar + (br - ar) * k, ag + (bg - ag) * k, ab + (bb - ab) * k)
end

local function lane_color(lane)
  local h = ((lane - 1) / GRID_SLOTS)
  local s = 0.72
  local v = 0.94
  local i = math.floor(h * 6)
  local f = (h * 6) - i
  local p = v * (1 - s)
  local q = v * (1 - f * s)
  local t = v * (1 - (1 - f) * s)
  local rr, gg, bb
  local m = i % 6
  if m == 0 then rr, gg, bb = v, t, p
  elseif m == 1 then rr, gg, bb = q, v, p
  elseif m == 2 then rr, gg, bb = p, v, t
  elseif m == 3 then rr, gg, bb = p, q, v
  elseif m == 4 then rr, gg, bb = t, p, v
  else rr, gg, bb = v, p, q end
  return pack_rgb(rr * 255, gg * 255, bb * 255)
end

local function truncate_to_width(ctx, text, max_w)
  local s = tostring(text or "")
  local w = select(1, r.ImGui_CalcTextSize(ctx, s)) or 0
  if w <= max_w then return s end
  local ellipsis = "..."
  local ellipsis_w = select(1, r.ImGui_CalcTextSize(ctx, ellipsis)) or 0
  local target = math.max(0, max_w - ellipsis_w)
  local low = 0
  local high = #s
  while low < high do
    local mid = math.floor((low + high + 1) / 2)
    local test = s:sub(1, mid)
    local test_w = select(1, r.ImGui_CalcTextSize(ctx, test)) or 0
    if test_w <= target then
      low = mid
    else
      high = mid - 1
    end
  end
  return s:sub(1, low) .. ellipsis
end

local function track_guid(track)
  if not track or not r.GetTrackGUID then return nil end
  return r.GetTrackGUID(track)
end

local function clone_table(value)
  if type(value) ~= "table" then return value end
  local out = {}
  for k, v in pairs(value) do
    out[k] = clone_table(v)
  end
  return out
end

local function get_track_index0(track)
  return math.floor((r.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER") or 1) - 1)
end

local function track_is_seq_bus(track)
  if not track or not r.GetSetMediaTrackInfo_String then return false end
  local ok, v = r.GetSetMediaTrackInfo_String(track, BUS_MARKER, "", false)
  return ok and v ~= nil and v ~= ""
end

local function each_child_track(parent, fn)
  if not parent then return end
  local parent_depth = r.GetTrackDepth(parent)
  local parent_idx = get_track_index0(parent)
  local track_count = r.CountTracks(0)
  for i = parent_idx + 1, track_count - 1 do
    local tr = r.GetTrack(0, i)
    if r.GetTrackDepth(tr) <= parent_depth then
      break
    end
    if not track_is_seq_bus(tr) then
      fn(tr, i)
    end
  end
end

local function find_rs5k_fx(track)
  if not track then return -1 end
  local count = r.TrackFX_GetCount(track)
  for i = 0, count - 1 do
    local ok, name = r.TrackFX_GetFXName(track, i, "")
    local lower_name = ok and name and name:lower() or ""
    if lower_name:find("reasamplomatic", 1, true) or lower_name:find("rs5k", 1, true) then
      return i
    end
    if r.TrackFX_GetNamedConfigParm then
      local ok_file = r.TrackFX_GetNamedConfigParm(track, i, "FILE0")
      if ok_file then
        return i
      end
    end
  end
  return -1
end

local function get_rs5k_file(track, fx)
  if not track or fx == nil or fx < 0 then return nil end
  if not r.TrackFX_GetNamedConfigParm then return nil end
  local ok, path = r.TrackFX_GetNamedConfigParm(track, fx, "FILE0")
  if not ok or not path or path == "" then return nil end
  return tostring(path)
end

local function track_name(track)
  if not track or not r.GetSetMediaTrackInfo_String then return "" end
  local ok, name = r.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
  if ok and name and name ~= "" then
    return tostring(name)
  end
  return ""
end

local function file_leaf(path)
  return tostring(path or ""):match("([^/\\]+)$") or tostring(path or "")
end

local function file_stem(path)
  return file_leaf(path):gsub("%.[%w]+$", "")
end

local function detect_lane_role_name(text)
  local raw = tostring(text or ""):lower()
  local compact = raw:gsub("[^%w]+", "")
  local words = " " .. raw:gsub("[^%w]+", " ") .. " "
  local function has_word(token)
    return words:find(" " .. token .. " ", 1, true) ~= nil
  end
  local function has_any_word(tokens)
    for i = 1, #tokens do
      if has_word(tokens[i]) then return true end
    end
    return false
  end
  local function has_any_compact(tokens)
    for i = 1, #tokens do
      if compact:find(tokens[i], 1, true) then return true end
    end
    return false
  end

  local has_hh_core = has_any_compact({ "hihat", "hat", "hh" }) or has_any_word({ "hihat", "hat", "hats", "hh" })
  local has_hh_open = has_any_compact({ "openhihat", "openhat", "hihatopen", "hhopen", "ohh" }) or has_any_word({ "openhihat", "openhat", "openhh", "ohh" })
  local has_hh_closed = has_any_compact({ "closedhihat", "closedhat", "hihatclosed", "hhclosed", "chh" }) or has_any_word({ "closedhihat", "closedhat", "closedhh", "chh" })
  if has_hh_open or ((has_word("open") or has_word("opened")) and has_hh_core) then
    return "Hihat(o)"
  end
  if has_hh_closed or ((has_word("closed") or has_word("close")) and has_hh_core) then
    return "Hihat(c)"
  end
  if has_hh_core then
    return "Hihat(c)"
  end
  if has_any_compact({ "808", "tr808" }) or has_any_word({ "808" }) then
    return "808"
  end
  if has_any_compact({ "kick", "bassdrum", "bassdr", "808kick", "909kick" }) or has_any_word({ "kick", "bd", "kik", "kck" }) then
    return "Kick"
  end
  if has_any_compact({ "snare", "rimsnare" }) or has_any_word({ "snare", "snr", "sd", "rim" }) then
    return "Snare"
  end
  if has_any_compact({ "clap" }) or has_any_word({ "clap", "handclap" }) then
    return "Clap"
  end
  if has_any_compact({ "tom", "floor", "hightom", "lowtom" }) or has_any_word({ "tom", "toms" }) then
    return "Tom"
  end
  if has_any_compact({ "pad", "ambientpad", "atmospad", "texturepad" }) or has_any_word({ "pad", "pads" }) then
    return "Pad"
  end
  if has_any_compact({ "bass", "subbass", "reese", "bassline", "sub" }) or has_any_word({ "bass", "sub", "reese" }) then
    return "Bass"
  end
  if has_any_compact({ "guitar", "gtr" }) or has_any_word({ "guitar", "gtr", "gt" }) then
    return "Guitar"
  end
  if has_any_compact({ "synth", "poly", "lead", "pluck" }) or has_any_word({ "synth", "poly", "lead", "pluck" }) then
    return "Synth"
  end
  if has_any_compact({ "perc", "percussion", "shaker", "tamb", "conga", "bongo", "cowbell" }) or has_any_word({ "perc", "percussion", "shaker", "tamb", "conga", "bongo", "cowbell" }) then
    return "Perc"
  end
  if has_any_compact({ "crash" }) or has_any_word({ "crash" }) then
    return "Crash"
  end
  if has_any_compact({ "splash" }) or has_any_word({ "splash" }) then
    return "Splash"
  end
  if has_any_compact({ "ride" }) or has_any_word({ "ride" }) then
    return "Ride"
  end
  if has_any_compact({ "china" }) or has_any_word({ "china" }) then
    return "China"
  end
  if has_any_compact({ "cymbal" }) or has_any_word({ "cym", "cymbal" }) then
    return "Cymbal"
  end
  if has_any_compact({ "fx", "sfx", "impact", "noise", "sweep" }) or has_any_word({ "fx", "sfx", "impact", "noise", "sweep" }) then
    return "FX"
  end
  return "Other"
end

local function build_lane_auto_names(lane_tracks)
  local out = {}
  for lane = 1, GRID_SLOTS do
    local lane_track = lane_tracks and lane_tracks[lane] or nil
    local source = ""
    if lane_track then
      local lane_fx = find_rs5k_fx(lane_track)
      local sample_file = lane_fx >= 0 and get_rs5k_file(lane_track, lane_fx) or nil
      if sample_file and sample_file ~= "" then
        source = file_stem(sample_file)
      end
      if source == "" then
        source = track_name(lane_track)
      end
    end
    out[lane] = string.format("%02d %s", lane, detect_lane_role_name(source))
  end
  return out
end

local function rs5k_obeys_note_off(track, fx)
  if not track or fx == nil or fx < 0 then return false end
  if not r.TrackFX_GetParamNormalized then return false end
  local value = r.TrackFX_GetParamNormalized(track, fx, 11)
  return (tonumber(value) or 0) > 0.5
end

local function set_rs5k_obey_note_off(track, fx, enabled)
  if not track or fx == nil or fx < 0 then return false end
  if not r.TrackFX_SetParamNormalized then return false end
  r.TrackFX_SetParamNormalized(track, fx, 11, enabled and 1 or 0)
  return true
end

local function set_rs5k_pitch_semitones(track, fx, semitones)
  if not track or fx == nil or fx < 0 then return false end
  if not r.TrackFX_SetParamNormalized or not r.TrackFX_GetParamEx then return false end
  local key = (track_guid(track) or tostring(track)) .. "#" .. tostring(fx)
  local pitch_idx = rs5k_pitch_param_cache[key]
  if pitch_idx == nil then
    pitch_idx = -1
    if r.TrackFX_GetNumParams and r.TrackFX_GetParamName then
      local pcount = r.TrackFX_GetNumParams(track, fx)
      for pi = 0, (pcount or 0) - 1 do
        local ok, pname = r.TrackFX_GetParamName(track, fx, pi, "")
        local lower = ok and pname and tostring(pname):lower() or ""
        if lower:find("pitch adjust", 1, true) or lower:find("pitch offset", 1, true) then
          pitch_idx = pi
          break
        end
      end
      if pitch_idx < 0 then
        for pi = 0, (pcount or 0) - 1 do
          local ok, pname = r.TrackFX_GetParamName(track, fx, pi, "")
          local lower = ok and pname and tostring(pname):lower() or ""
          if lower == "pitch" or lower:find("coarse", 1, true) then
            pitch_idx = pi
            break
          end
        end
      end
    end
    rs5k_pitch_param_cache[key] = pitch_idx
  end
  if pitch_idx < 0 then return false end
  local semis = tonumber(semitones) or 0

  local display_min, display_max = nil, nil
  if r.TrackFX_FormatParamValueNormalized then
    local ok0, txt0 = r.TrackFX_FormatParamValueNormalized(track, fx, pitch_idx, 0, "")
    local ok1, txt1 = r.TrackFX_FormatParamValueNormalized(track, fx, pitch_idx, 1, "")
    local n0 = ok0 and parse_param_display_number(txt0) or nil
    local n1 = ok1 and parse_param_display_number(txt1) or nil
    if n0 and n1 and n1 > n0 + 0.000001 then
      display_min, display_max = n0, n1
    end
  end

  local norm
  if display_min and display_max then
    local target = clamp(semis, display_min, display_max)
    norm = (target - display_min) / (display_max - display_min)
  else
    local _, min_v, max_v = r.TrackFX_GetParamEx(track, fx, pitch_idx)
    local min_num = tonumber(min_v)
    local max_num = tonumber(max_v)
    if not min_num or not max_num or max_num <= min_num then return false end
    local target = clamp(semis, min_num, max_num)
    norm = (target - min_num) / (max_num - min_num)
  end

  r.TrackFX_SetParamNormalized(track, fx, pitch_idx, clamp(norm, 0, 1))
  return true
end

local function set_rs5k_pan_percent(track, fx, pan_percent)
  if not track or fx == nil or fx < 0 then return false end
  if not r.TrackFX_SetParamNormalized or not r.TrackFX_GetParamEx then return false end
  local key = (track_guid(track) or tostring(track)) .. "#" .. tostring(fx)
  local pan_idx = rs5k_pan_param_cache[key]
  if pan_idx == nil then
    pan_idx = -1
    if r.TrackFX_GetNumParams and r.TrackFX_GetParamName then
      local pcount = r.TrackFX_GetNumParams(track, fx)
      for pi = 0, (pcount or 0) - 1 do
        local ok, pname = r.TrackFX_GetParamName(track, fx, pi, "")
        local lower = ok and pname and tostring(pname):lower() or ""
        if lower == "pan" or lower:find("pan adjust", 1, true) then
          pan_idx = pi
          break
        end
      end
      if pan_idx < 0 then
        for pi = 0, (pcount or 0) - 1 do
          local ok, pname = r.TrackFX_GetParamName(track, fx, pi, "")
          local lower = ok and pname and tostring(pname):lower() or ""
          if lower:find("pan", 1, true) or lower:find("balance", 1, true) then
            pan_idx = pi
            break
          end
        end
      end
    end
    rs5k_pan_param_cache[key] = pan_idx
  end
  if pan_idx < 0 then return false end
  local value = tonumber(pan_percent) or 0

  local display_min, display_max = nil, nil
  if r.TrackFX_FormatParamValueNormalized then
    local ok0, txt0 = r.TrackFX_FormatParamValueNormalized(track, fx, pan_idx, 0, "")
    local ok1, txt1 = r.TrackFX_FormatParamValueNormalized(track, fx, pan_idx, 1, "")
    local n0 = ok0 and parse_param_display_number(txt0) or nil
    local n1 = ok1 and parse_param_display_number(txt1) or nil
    if n0 and n1 and n1 > n0 + 0.000001 then
      display_min, display_max = n0, n1
    end
  end

  local norm
  if display_min and display_max then
    local target = value
    if display_min >= -0.001 and display_max <= 1.001 then
      target = (clamp(value, -100, 100) + 100) / 200
    end
    target = clamp(target, display_min, display_max)
    norm = (target - display_min) / (display_max - display_min)
  else
    local _, min_v, max_v = r.TrackFX_GetParamEx(track, fx, pan_idx)
    local min_num = tonumber(min_v)
    local max_num = tonumber(max_v)
    if not min_num or not max_num or max_num <= min_num then return false end
    local target = value
    if min_num >= -0.001 and max_num <= 1.001 then
      target = (clamp(value, -100, 100) + 100) / 200
    end
    target = clamp(target, min_num, max_num)
    norm = (target - min_num) / (max_num - min_num)
  end

  r.TrackFX_SetParamNormalized(track, fx, pan_idx, clamp(norm, 0, 1))
  return true
end

local function set_rs5k_volume_db(track, fx, volume_db)
  if not track or fx == nil or fx < 0 then return false end
  if not r.TrackFX_SetParamNormalized or not r.TrackFX_GetParamEx then return false end
  local key = (track_guid(track) or tostring(track)) .. "#" .. tostring(fx)
  local volume_idx = rs5k_volume_param_cache[key]

  local function get_display_range(idx)
    if not r.TrackFX_FormatParamValueNormalized then return nil, nil end
    local ok0, txt0 = r.TrackFX_FormatParamValueNormalized(track, fx, idx, 0, "")
    local ok1, txt1 = r.TrackFX_FormatParamValueNormalized(track, fx, idx, 1, "")
    local n0 = ok0 and parse_param_display_number(txt0) or nil
    local n1 = ok1 and parse_param_display_number(txt1) or nil
    if n0 and n1 and n1 > n0 + 0.000001 then
      return n0, n1
    end
    return nil, nil
  end

  local function looks_like_volume_db(min_v, max_v)
    if not min_v or not max_v then return false end
    local span = max_v - min_v
    if span < 10 then return false end
    if max_v < 1 or max_v > 18 then return false end
    if min_v > -12 then return false end
    return true
  end

  if volume_idx ~= nil and volume_idx >= 0 then
    local cmin, cmax = get_display_range(volume_idx)
    if not looks_like_volume_db(cmin, cmax) then
      volume_idx = -1
      rs5k_volume_param_cache[key] = -1
    end
  end

  if volume_idx == nil then
    volume_idx = -1
  end
  if volume_idx < 0 and r.TrackFX_GetNumParams and r.TrackFX_GetParamName then
    local best_idx = -1
    local best_span = -1
    local pcount = r.TrackFX_GetNumParams(track, fx)
    for pi = 0, (pcount or 0) - 1 do
      local ok, pname = r.TrackFX_GetParamName(track, fx, pi, "")
      local lower = ok and pname and tostring(pname):lower() or ""
      if (lower == "volume" or lower:find("volume", 1, true) or lower:find("gain", 1, true) or lower:find("trim", 1, true)) and not lower:find("velocity", 1, true) then
        local dmin, dmax = get_display_range(pi)
        if looks_like_volume_db(dmin, dmax) then
          local span = dmax - dmin
          if span > best_span then
            best_span = span
            best_idx = pi
          end
        end
      end
    end
    volume_idx = best_idx
    rs5k_volume_param_cache[key] = volume_idx
  end

  if volume_idx < 0 and r.TrackFX_GetNumParams and r.TrackFX_GetParamName then
    local best_idx = -1
    local best_span = -1
    local pcount = r.TrackFX_GetNumParams(track, fx)
    for pi = 0, (pcount or 0) - 1 do
      local ok, pname = r.TrackFX_GetParamName(track, fx, pi, "")
      local lower = ok and pname and tostring(pname):lower() or ""
      if (not lower:find("velocity", 1, true)) and (lower:find("db", 1, true) or lower:find("gain", 1, true) or lower:find("volume", 1, true)) then
        local dmin, dmax = get_display_range(pi)
        if looks_like_volume_db(dmin, dmax) then
          local span = dmax - dmin
          if span > best_span then
            best_span = span
            best_idx = pi
          end
        end
      end
    end
    if best_idx >= 0 then
      volume_idx = best_idx
      rs5k_volume_param_cache[key] = volume_idx
    end
  end

  if volume_idx == nil then
    volume_idx = -1
  end
  if volume_idx < 0 then return false end

  local value = tonumber(volume_db) or 0

  local function get_display_at_norm(idx, norm)
    if not r.TrackFX_FormatParamValueNormalized then return nil end
    local ok, txt = r.TrackFX_FormatParamValueNormalized(track, fx, idx, clamp(norm, 0, 1), "")
    if not ok then return nil end
    return parse_param_display_number(txt)
  end

  local display_min, display_max = get_display_range(volume_idx)
  local norm
  if display_min and display_max and looks_like_volume_db(display_min, display_max) then
    local target = clamp(value, display_min, display_max)
    local lo = 0.0
    local hi = 1.0
    local ascending = display_max >= display_min
    local found = nil
    for _ = 1, 20 do
      local mid = (lo + hi) * 0.5
      local cur = get_display_at_norm(volume_idx, mid)
      if not cur then break end
      found = mid
      if ascending then
        if cur < target then
          lo = mid
        else
          hi = mid
        end
      else
        if cur > target then
          lo = mid
        else
          hi = mid
        end
      end
    end
    norm = found or ((target - display_min) / (display_max - display_min))
  else
    local _, min_v, max_v = r.TrackFX_GetParamEx(track, fx, volume_idx)
    local min_num = tonumber(min_v)
    local max_num = tonumber(max_v)
    if not min_num or not max_num or max_num <= min_num then return false end
    local target = clamp(value, min_num, max_num)
    norm = (target - min_num) / (max_num - min_num)
  end

  r.TrackFX_SetParamNormalized(track, fx, volume_idx, clamp(norm, 0, 1))
  return true
end

find_param_index = function(track, fx, patterns)
  if not r.TrackFX_GetNumParams or not r.TrackFX_GetParamName then return -1 end
  local pcount = r.TrackFX_GetNumParams(track, fx)
  for pi = 0, (pcount or 0) - 1 do
    local ok, pname = r.TrackFX_GetParamName(track, fx, pi, "")
    local lower = ok and pname and tostring(pname):lower() or ""
    for _, pattern in ipairs(patterns or {}) do
      if lower:find(pattern, 1, true) then
        return pi
      end
    end
  end
  return -1
end

local function ensure_rack_velocity_response(parent)
  if not parent then return end
  if not r.TrackFX_SetParamNormalized or not r.TrackFX_GetParamNormalized then return end
  each_child_track(parent, function(track)
    local fx = find_rs5k_fx(track)
    if fx < 0 then return end

    local min_gain_idx = find_param_index(track, fx, {
      "minimum velocity",
      "min velocity",
      "velocity minimum",
      "velocity min",
    })
    if min_gain_idx < 0 then
      min_gain_idx = 0
    end

    local min_vel_idx = find_param_index(track, fx, {
      "minimum velocity",
      "min velocity",
      "velocity min",
    })
    local max_vel_idx = find_param_index(track, fx, {
      "maximum velocity",
      "max velocity",
      "velocity max",
    })

    local current = r.TrackFX_GetParamNormalized(track, fx, min_gain_idx)
    if current ~= nil and (tonumber(current) or 0) > 0.98 then
      r.TrackFX_SetParamNormalized(track, fx, min_gain_idx, 0.0)
    end

    if min_vel_idx >= 0 then
      local min_now = r.TrackFX_GetParamNormalized(track, fx, min_vel_idx)
      if min_now ~= nil and (tonumber(min_now) or 0) > 0.01 then
        r.TrackFX_SetParamNormalized(track, fx, min_vel_idx, 0.0)
      end
    end
    if max_vel_idx >= 0 then
      local max_now = r.TrackFX_GetParamNormalized(track, fx, max_vel_idx)
      if max_now ~= nil and (tonumber(max_now) or 0) < 0.99 then
        r.TrackFX_SetParamNormalized(track, fx, max_vel_idx, 1.0)
      end
    end
  end)
end

local function get_selected_rack_parent_track()
  local selected = r.GetSelectedTrack(0, 0)
  if not selected then return nil end
  local current = selected
  while current do
    if (r.GetMediaTrackInfo_Value(current, "I_FOLDERDEPTH") or 0) > 0 then
      return current
    end
    if not r.GetParentTrack then break end
    current = r.GetParentTrack(current)
  end
  return nil
end

local function new_sequence()
  local data = {
    steps = 16,
    velocity = 100,
    host_transport = false,
    repeat_enabled = true,
    lane_auto_name_enabled = false,
    selected_pattern_index = 0,
    pattern = {},
    lane_settings = {},
    song_slots = {},
  }
  for lane = 1, GRID_SLOTS do
    data.pattern[lane] = {}
    for step = 1, STEPS_PER_BAR do
      data.pattern[lane][step] = 0
    end
    local vel_steps = {}
    local gate_steps = {}
    local len_steps = {}
    local sub_steps = {}
    local pitch_steps = {}
    local pan_steps = {}
    local volume_steps = {}
    local prob_steps = {}
    for step = 1, STEPS_PER_BAR do
      vel_steps[step] = 100
      gate_steps[step] = 100
      len_steps[step] = 1
      sub_steps[step] = 1
      pitch_steps[step] = 0
      pan_steps[step] = 0
      volume_steps[step] = 0
      prob_steps[step] = 100
    end
    data.lane_settings[lane] = {
      mode = "gate",
      note_off_mode = "follow",
      cycle_steps = 16,
      speed = 1,
      retrigger = true,
      param_mode = "velocity",
      step_velocity = vel_steps,
      step_gate = gate_steps,
      step_length = len_steps,
      step_substeps = sub_steps,
      step_pitch = pitch_steps,
      step_pan = pan_steps,
      step_volume = volume_steps,
      step_probability = prob_steps,
    }
  end
  for slot = 1, 8 do
    data.song_slots[slot] = {
      page = slot == 1 and 1 or 0,
      repeats = 1,
    }
  end
  return data
end

local function sanitize_sequence(data)
  if type(data) ~= "table" then
    return new_sequence()
  end
  local out = new_sequence()
  out.steps = STEPS_PER_BAR
  out.velocity = 100
  out.host_transport = data.host_transport == true
  out.repeat_enabled = data.repeat_enabled ~= false
  out.lane_auto_name_enabled = data.lane_auto_name_enabled == true
  out.selected_pattern_index = math.max(0, math.floor(tonumber(data.selected_pattern_index) or 0))
  local total = STEPS_PER_BAR
  if type(data.pattern) == "table" then
    for lane = 1, GRID_SLOTS do
      local src_lane = data.pattern[lane]
      if type(src_lane) == "table" then
        out.pattern[lane] = {}
        for step = 1, total do
          local v = src_lane[step]
          out.pattern[lane][step] = (v == 1 or v == true) and 1 or 0
        end
      else
        out.pattern[lane] = {}
        for step = 1, total do
          out.pattern[lane][step] = 0
        end
      end
    end
  else
    for lane = 1, GRID_SLOTS do
      out.pattern[lane] = {}
      for step = 1, total do
        out.pattern[lane][step] = 0
      end
    end
  end

  if type(data.lane_settings) == "table" then
    for lane = 1, GRID_SLOTS do
      local src = data.lane_settings[lane]
      if type(src) == "table" then
        local mode = tostring(src.mode or "gate")
        if mode ~= "gate" and mode ~= "oneshot" then
          mode = "gate"
        end
        out.lane_settings[lane] = {
          mode = mode,
          note_off_mode = (src.note_off_mode == "none" or src.note_off_mode == "length") and src.note_off_mode or "follow",
          cycle_steps = clamp(math.floor(tonumber(src.cycle_steps) or total), 1, total),
          speed = normalize_lane_speed(src.speed),
          retrigger = src.retrigger ~= false,
          param_mode = (src.param_mode == "substeps" or src.param_mode == "gate" or src.param_mode == "length" or src.param_mode == "pitch" or src.param_mode == "pan" or src.param_mode == "volume") and src.param_mode or "velocity",
          step_velocity = {},
          step_gate = {},
          step_length = {},
          step_substeps = {},
          step_pitch = {},
          step_pan = {},
          step_volume = {},
          step_probability = {},
        }
        for step = 1, total do
          local raw_vel = table_step_value(src.step_velocity, step, 100)
          local raw_gate = table_step_value(src.step_gate, step, 100)
          local raw_len = table_step_value(src.step_length, step, 1)
          local raw_sub = table_step_value(src.step_substeps, step, 1)
          local raw_pitch = table_step_value(src.step_pitch, step, 0)
          local raw_pan = table_step_value(src.step_pan, step, 0)
          local raw_volume = table_step_value(src.step_volume, step, 0)
          local raw_prob = table_step_value(src.step_probability, step, 100)
          out.lane_settings[lane].step_velocity[step] = clamp(math.floor(tonumber(raw_vel) or 100), 1, 127)
          out.lane_settings[lane].step_gate[step] = clamp(math.floor(tonumber(raw_gate) or 100), 1, 100)
          out.lane_settings[lane].step_length[step] = clamp(math.floor(tonumber(raw_len) or 1), 1, total)
          out.lane_settings[lane].step_substeps[step] = clamp(math.floor(tonumber(raw_sub) or 1), 1, 8)
          out.lane_settings[lane].step_pitch[step] = clamp(math.floor(tonumber(raw_pitch) or 0), -24, 24)
          out.lane_settings[lane].step_pan[step] = clamp(math.floor(tonumber(raw_pan) or 0), -100, 100)
          out.lane_settings[lane].step_volume[step] = clamp(math.floor(tonumber(raw_volume) or 0), -24, 6)
          out.lane_settings[lane].step_probability[step] = clamp(math.floor(tonumber(raw_prob) or 100), 0, 100)
        end
      else
        local vel_steps = {}
        local gate_steps = {}
        local len_steps = {}
        local sub_steps = {}
        local pitch_steps = {}
        local pan_steps = {}
        local volume_steps = {}
        local prob_steps = {}
        for step = 1, total do
          vel_steps[step] = 100
          gate_steps[step] = 100
          len_steps[step] = 1
          sub_steps[step] = 1
          pitch_steps[step] = 0
          pan_steps[step] = 0
          volume_steps[step] = 0
          prob_steps[step] = 100
        end
        out.lane_settings[lane] = {
          mode = "gate",
          note_off_mode = "follow",
          cycle_steps = total,
          speed = 1,
          retrigger = true,
          param_mode = "velocity",
          step_velocity = vel_steps,
          step_gate = gate_steps,
          step_length = len_steps,
          step_substeps = sub_steps,
          step_pitch = pitch_steps,
          step_pan = pan_steps,
          step_volume = volume_steps,
          step_probability = prob_steps,
        }
      end
    end
  end

  out.song_slots = {}
  local source_slots = type(data.song_slots) == "table" and data.song_slots or nil
  for slot = 1, 8 do
    local src = source_slots and source_slots[slot] or nil
    local page = slot == 1 and 1 or 0
    local repeats = 1
    if type(src) == "table" then
      page = clamp(math.floor(tonumber(src.page) or page), 0, PATTERN_SLOTS)
      repeats = clamp(math.floor(tonumber(src.repeats) or repeats), 1, 8)
    end
    out.song_slots[slot] = {
      page = page,
      repeats = repeats,
    }
  end

  return out
end

local function load_sequence(track)
  if not track then return new_sequence() end
  local ok, raw = r.GetSetMediaTrackInfo_String(track, EXT_KEY, "", false)
  if not ok or not raw or raw == "" then
    return new_sequence()
  end
  local decoded_ok, decoded = pcall(json.decode, raw)
  if not decoded_ok then
    return new_sequence()
  end
  return sanitize_sequence(decoded)
end

local function save_sequence(track, seq)
  if not track then return false end
  local payload = sanitize_sequence(seq)
  local ok, encoded = pcall(json.encode, payload)
  if not ok or not encoded then return false end
  r.GetSetMediaTrackInfo_String(track, EXT_KEY, encoded, true)
  return true
end

local function sequence_snapshot(seq)
  local clean = sanitize_sequence({
    steps = seq.steps,
    host_transport = seq.host_transport,
    repeat_enabled = seq.repeat_enabled,
    lane_auto_name_enabled = seq.lane_auto_name_enabled,
    selected_pattern_index = seq.selected_pattern_index,
    pattern = seq.pattern,
    lane_settings = seq.lane_settings,
    song_slots = seq.song_slots,
  })
  return {
    steps = clean.steps,
    host_transport = clean.host_transport,
    repeat_enabled = clean.repeat_enabled,
    lane_auto_name_enabled = clean.lane_auto_name_enabled,
    selected_pattern_index = clean.selected_pattern_index,
    pattern = clean.pattern,
    lane_settings = clean.lane_settings,
    song_slots = clean.song_slots,
  }
end

local function normalize_pattern_name(name, idx)
  local n = tostring(name or "")
  n = n:gsub("^%s+", ""):gsub("%s+$", "")
  if n == "" then
    n = "Preset " .. tostring(idx)
  end
  return n
end

local function preset_number_from_name(name)
  local value = tonumber(tostring(name or ""):match("^Preset%s+(%d+)$"))
  return value
end

local function next_preset_number(patterns)
  local used = {}
  for i = 1, #(patterns or {}) do
    local num = preset_number_from_name(patterns[i] and patterns[i].name)
    if num and num >= 1 then
      used[num] = true
    end
  end
  for num = 1, #(patterns or {}) + 1 do
    if not used[num] then
      return num
    end
  end
  return #(patterns or {}) + 1
end

local function blank_pattern_snapshot()
  return sequence_snapshot(new_sequence())
end

local function normalize_preset_entry(item, idx)
  local out = {
    name = normalize_pattern_name(type(item) == "table" and item.name or nil, idx),
    patterns = {},
  }
  local source_patterns = type(item) == "table" and type(item.patterns) == "table" and item.patterns or nil
  if source_patterns then
    for slot = 1, PATTERN_SLOTS do
      local src = source_patterns[slot]
      if type(src) == "table" then
        out.patterns[slot] = sanitize_sequence(src)
      else
        out.patterns[slot] = blank_pattern_snapshot()
      end
    end
  else
    local snap = type(item) == "table" and type(item.snapshot) == "table" and sanitize_sequence(item.snapshot) or blank_pattern_snapshot()
    out.patterns[1] = snap
    for slot = 2, PATTERN_SLOTS do
      out.patterns[slot] = blank_pattern_snapshot()
    end
  end
  return out
end

local function normalize_global_patterns(raw)
  local out = {}
  if type(raw) ~= "table" then return out end
  for _, item in ipairs(raw) do
    if type(item) == "table" then
      out[#out + 1] = normalize_preset_entry(item, #out + 1)
    end
  end
  return out
end

local function load_global_patterns()
  if not r.GetExtState then return {} end
  local raw = r.GetExtState(GLOBAL_PATTERN_SECTION, GLOBAL_PATTERN_KEY)
  if not raw or raw == "" then return {} end
  local ok, decoded = pcall(json.decode, raw)
  if not ok or type(decoded) ~= "table" then return {} end
  local source = type(decoded.presets) == "table" and decoded.presets or (type(decoded.patterns) == "table" and decoded.patterns or decoded)
  return normalize_global_patterns(source)
end

local function save_global_patterns(patterns)
  if not r.SetExtState then return false end
  local payload = { presets = normalize_global_patterns(patterns) }
  local ok, encoded = pcall(json.encode, payload)
  if not ok or not encoded then return false end
  r.SetExtState(GLOBAL_PATTERN_SECTION, GLOBAL_PATTERN_KEY, encoded, true)
  return true
end

local resolve_pattern_slot_for_save

local function save_pattern_to_library(patterns, selected_idx, seq, as_new, slot_idx, state, guid)
  local lib = normalize_global_patterns(patterns)
  local idx = math.floor(tonumber(selected_idx) or 0)
  local current_slot = clamp(math.floor(tonumber(slot_idx) or 1), 1, PATTERN_SLOTS)
  if as_new or idx < 1 or idx > #lib then
    idx = next_preset_number(lib)
    lib[idx] = {
      name = "Preset " .. tostring(idx),
      patterns = {},
    }
  end
  lib[idx] = lib[idx] or { name = "Preset " .. tostring(idx), patterns = {} }
  lib[idx].name = normalize_pattern_name(lib[idx].name, idx)
  lib[idx].patterns = type(lib[idx].patterns) == "table" and lib[idx].patterns or {}
  local shared_song = clone_table(seq.song_slots or {})
  local shared_auto = seq.lane_auto_name_enabled == true
  local shared_repeat = seq.repeat_enabled ~= false
  for slot = 1, PATTERN_SLOTS do
    local slot_seq = resolve_pattern_slot_for_save(state, guid, lib, idx, slot, current_slot, seq)
    local snap = sequence_snapshot(slot_seq)
    snap.song_slots = clone_table(shared_song)
    snap.lane_auto_name_enabled = shared_auto
    snap.repeat_enabled = shared_repeat
    lib[idx].patterns[slot] = snap
  end
  return lib, idx
end

local function load_pattern_from_library(patterns, selected_idx, seq, slot_idx)
  local lib = normalize_global_patterns(patterns)
  local idx = math.floor(tonumber(selected_idx) or 0)
  if idx < 1 or idx > #lib then return false end
  local item = lib[idx]
  if type(item) ~= "table" then return false end
  local slot = clamp(math.floor(tonumber(slot_idx) or 1), 1, PATTERN_SLOTS)
  local src = type(item.patterns) == "table" and item.patterns[slot] or nil
  if type(src) ~= "table" then src = blank_pattern_snapshot() end
  local clean = sanitize_sequence(src)
  seq.steps = clean.steps
  seq.host_transport = clean.host_transport == true
  seq.repeat_enabled = clean.repeat_enabled ~= false
  seq.lane_auto_name_enabled = clean.lane_auto_name_enabled == true
  seq.pattern = clone_table(clean.pattern)
  seq.lane_settings = clone_table(clean.lane_settings)
  seq.song_slots = clone_table(clean.song_slots)
  return true
end

local function stash_working_pattern(state, guid, selected_idx, slot_idx, seq)
  local idx = math.floor(tonumber(selected_idx) or 0)
  if idx < 1 then return end
  local slot = clamp(math.floor(tonumber(slot_idx) or 1), 1, PATTERN_SLOTS)
  state.working_patterns_by_guid = state.working_patterns_by_guid or {}
  state.working_patterns_by_guid[guid] = state.working_patterns_by_guid[guid] or {}
  state.working_patterns_by_guid[guid][idx] = state.working_patterns_by_guid[guid][idx] or {}
  state.working_patterns_by_guid[guid][idx][slot] = sequence_snapshot(seq)
end

local function load_working_pattern(state, guid, selected_idx, seq, slot_idx)
  local idx = math.floor(tonumber(selected_idx) or 0)
  if idx < 1 then return false end
  local slot = clamp(math.floor(tonumber(slot_idx) or 1), 1, PATTERN_SLOTS)
  local by_guid = state.working_patterns_by_guid and state.working_patterns_by_guid[guid]
  local by_idx = by_guid and by_guid[idx]
  local snap = by_idx and by_idx[slot]
  if type(snap) ~= "table" then return false end
  local clean = sanitize_sequence(snap)
  seq.steps = clean.steps
  seq.host_transport = clean.host_transport == true
  seq.repeat_enabled = clean.repeat_enabled ~= false
  seq.lane_auto_name_enabled = clean.lane_auto_name_enabled == true
  seq.pattern = clone_table(clean.pattern)
  seq.lane_settings = clone_table(clean.lane_settings)
  seq.song_slots = clone_table(clean.song_slots)
  return true
end

local function clear_working_preset(state, guid, selected_idx)
  local idx = math.floor(tonumber(selected_idx) or 0)
  if idx < 1 then return end
  local by_guid = state.working_patterns_by_guid and state.working_patterns_by_guid[guid]
  if not by_guid then return end
  by_guid[idx] = nil
end

local function clear_working_preset_everywhere(state, selected_idx)
  local idx = math.floor(tonumber(selected_idx) or 0)
  if idx < 1 then return end
  local all = state.working_patterns_by_guid or {}
  for _, by_guid in pairs(all) do
    if type(by_guid) == "table" then
      by_guid[idx] = nil
    end
  end
end

local function load_pattern_for_editing(state, guid, patterns, selected_idx, seq, slot_idx)
  local shared_song = seq.song_slots
  local shared_auto = seq.lane_auto_name_enabled
  local shared_repeat = seq.repeat_enabled
  local ok
  if load_working_pattern(state, guid, selected_idx, seq, slot_idx) then
    ok = true
  else
    ok = load_pattern_from_library(patterns, selected_idx, seq, slot_idx)
  end
  seq.song_slots = shared_song
  seq.lane_auto_name_enabled = shared_auto
  seq.repeat_enabled = shared_repeat
  return ok
end

resolve_pattern_slot_for_save = function(state, guid, patterns, selected_idx, slot_idx, current_slot, current_seq)
  local slot = clamp(math.floor(tonumber(slot_idx) or 1), 1, PATTERN_SLOTS)
  local current = clamp(math.floor(tonumber(current_slot) or 1), 1, PATTERN_SLOTS)
  if current_seq and slot == current then
    return sanitize_sequence(current_seq)
  end

  local idx = math.floor(tonumber(selected_idx) or 0)
  local by_guid = state and state.working_patterns_by_guid and state.working_patterns_by_guid[guid]
  local by_idx = by_guid and by_guid[idx]
  local snap = by_idx and by_idx[slot]
  if type(snap) == "table" then
    return sanitize_sequence(snap)
  end

  local lib = normalize_global_patterns(patterns)
  local item = idx >= 1 and idx <= #lib and lib[idx] or nil
  local src = item and type(item.patterns) == "table" and item.patterns[slot] or nil
  if type(src) == "table" then
    return sanitize_sequence(src)
  end

  return blank_pattern_snapshot()
end

local function resolve_slot_sequence_for_export(state, guid, patterns, selected_idx, slot_idx, fallback_seq, current_slot, current_seq)
  local slot = clamp(math.floor(tonumber(slot_idx) or 1), 1, PATTERN_SLOTS)
  local idx = math.floor(tonumber(selected_idx) or 0)
  local snap = nil

  if current_seq and slot == clamp(math.floor(tonumber(current_slot) or 1), 1, PATTERN_SLOTS) then
    return sanitize_sequence(current_seq)
  end

  local by_guid = state and state.working_patterns_by_guid and state.working_patterns_by_guid[guid]
  local by_idx = by_guid and by_guid[idx]
  if by_idx and type(by_idx[slot]) == "table" then
    snap = by_idx[slot]
  end

  if not snap and idx >= 1 and type(patterns) == "table" and type(patterns[idx]) == "table" and type(patterns[idx].patterns) == "table" and type(patterns[idx].patterns[slot]) == "table" then
    snap = patterns[idx].patterns[slot]
  end

  if type(snap) == "table" then
    return sanitize_sequence(snap)
  end
  return sanitize_sequence(fallback_seq)
end

local function send_note_off(note)
  if not r.StuffMIDIMessage then return false end
  local ok1 = pcall(r.StuffMIDIMessage, 0, 0x80, note, 0)
  local ok2 = pcall(r.StuffMIDIMessage, 0, 0x90, note, 0)
  return ok1 or ok2
end

local function send_note_on(note, vel)
  if not r.StuffMIDIMessage then return false end
  local ok = pcall(r.StuffMIDIMessage, 0, 0x90, note, vel)
  return ok == true
end

local function stop_notes(state)
  if not r.StuffMIDIMessage then return end
  for _, entry in pairs(state.active_notes or {}) do
    if entry and entry.note then
      send_note_off(entry.note)
    end
  end
  for note, _ in pairs(state.preview_note_offs or {}) do
    send_note_off(note)
  end
  state.active_notes = {}
  state.preview_note_offs = {}
end

local function ensure_lane_step_params(cfg, total_steps, default_vel)
  cfg.speed = normalize_lane_speed(cfg.speed)
  cfg.step_velocity = type(cfg.step_velocity) == "table" and cfg.step_velocity or {}
  cfg.step_gate = type(cfg.step_gate) == "table" and cfg.step_gate or {}
  cfg.step_length = type(cfg.step_length) == "table" and cfg.step_length or {}
  cfg.step_substeps = type(cfg.step_substeps) == "table" and cfg.step_substeps or {}
  cfg.step_pitch = type(cfg.step_pitch) == "table" and cfg.step_pitch or {}
  cfg.step_pan = type(cfg.step_pan) == "table" and cfg.step_pan or {}
  cfg.step_volume = type(cfg.step_volume) == "table" and cfg.step_volume or {}
  cfg.step_probability = type(cfg.step_probability) == "table" and cfg.step_probability or {}
  for step = 1, total_steps do
    local raw_vel = table_step_value(cfg.step_velocity, step, default_vel)
    local raw_gate = table_step_value(cfg.step_gate, step, 100)
    local raw_len = table_step_value(cfg.step_length, step, 1)
    local raw_sub = table_step_value(cfg.step_substeps, step, 1)
    local raw_pitch = table_step_value(cfg.step_pitch, step, 0)
    local raw_pan = table_step_value(cfg.step_pan, step, 0)
    local raw_volume = table_step_value(cfg.step_volume, step, 0)
    local raw_prob = table_step_value(cfg.step_probability, step, 100)
    cfg.step_velocity[step] = clamp(math.floor(tonumber(raw_vel) or default_vel), 1, 127)
    cfg.step_gate[step] = clamp(math.floor(tonumber(raw_gate) or 100), 1, 100)
    cfg.step_length[step] = clamp(math.floor(tonumber(raw_len) or 1), 1, total_steps)
    cfg.step_substeps[step] = clamp(math.floor(tonumber(raw_sub) or 1), 1, 8)
    cfg.step_pitch[step] = clamp(math.floor(tonumber(raw_pitch) or 0), -24, 24)
    cfg.step_pan[step] = clamp(math.floor(tonumber(raw_pan) or 0), -100, 100)
    cfg.step_volume[step] = clamp(math.floor(tonumber(raw_volume) or 0), -24, 6)
    cfg.step_probability[step] = clamp(math.floor(tonumber(raw_prob) or 100), 0, 100)
  end
  for step = total_steps + 1, STEPS_PER_BAR * 4 do
    cfg.step_velocity[step] = nil
    cfg.step_gate[step] = nil
    cfg.step_length[step] = nil
    cfg.step_substeps[step] = nil
    cfg.step_pitch[step] = nil
    cfg.step_pan[step] = nil
    cfg.step_volume[step] = nil
    cfg.step_probability[step] = nil
  end
  if cfg.param_mode ~= "substeps" and cfg.param_mode ~= "gate" and cfg.param_mode ~= "length" and cfg.param_mode ~= "pitch" and cfg.param_mode ~= "pan" and cfg.param_mode ~= "volume" and cfg.param_mode ~= "probability" then
    cfg.param_mode = "velocity"
  end
end

local function trigger_lane_note(state, lane, note, vel, mode, retrigger, off_at_time)
  local active = state.active_notes[lane]
  local force_retrigger = false
  if active and active.note and active.vel and active.vel ~= vel then
    force_retrigger = true
  end

  if force_retrigger then
    retrigger = true
  end

  if active and active.note and retrigger then
    send_note_off(active.note)
    state.active_notes[lane] = nil
    active = nil
  end

  if (not active) or retrigger then
    local ok = send_note_on(note, vel)
    if ok then
      local off_time = nil
      if mode == "gate" then
        off_time = off_at_time
      end
      state.active_notes[lane] = {
        note = note,
        vel = vel,
        off_at_time = off_time,
      }
    end
  elseif active and mode == "gate" then
    local new_off = off_at_time
    if not active.off_at_time or (new_off and new_off > active.off_at_time) then
      active.off_at_time = new_off
      active.vel = vel
      state.active_notes[lane] = active
    end
  end
end

local function run_pending_substep_events(state, elapsed)
  local pending = state.pending_events or {}
  if #pending == 0 then return end
  if #pending > 1 then
    table.sort(pending, function(a, b)
      return (tonumber(a and a.at) or 0) < (tonumber(b and b.at) or 0)
    end)
  end
  local i = 1
  while i <= #pending do
    local ev = pending[i]
    local lookahead = clamp(tonumber(ev and ev.lookahead) or SUBSTEP_LOOKAHEAD_MAX, SUBSTEP_LOOKAHEAD_MIN, SUBSTEP_LOOKAHEAD_MAX)
    local horizon = elapsed + lookahead
    if ev and horizon + 0.0000001 >= (ev.at or 0) then
      if ev.track and ev.fx and ev.fx >= 0 then
        set_rs5k_pitch_semitones(ev.track, ev.fx, ev.pitch or 0)
        set_rs5k_pan_percent(ev.track, ev.fx, ev.pan or 0)
        set_rs5k_volume_db(ev.track, ev.fx, ev.volume or 0)
      end
      trigger_lane_note(state, ev.lane, ev.note, ev.vel, ev.mode, ev.retrigger, ev.off_at_time)
      table.remove(pending, i)
    else
      break
    end
  end
  state.pending_events = pending
end

local function engine_ensure_installed()
  if engine_installed then return true end
  local res = r.GetResourcePath and r.GetResourcePath() or nil
  if not res then return false end
  local path = res .. "/Effects/" .. EngineJSFX.filename
  local marker = "TK_ENGINE_VERSION:" .. tostring(EngineJSFX.version)
  local up_to_date = false
  local existing = io.open(path, "rb")
  if existing then
    local content = existing:read("*a") or ""
    existing:close()
    if content:find(marker, 1, true) then
      up_to_date = true
    end
  end
  if not up_to_date then
    local f = io.open(path, "wb")
    if not f then return false end
    f:write(EngineJSFX.source)
    f:close()
    engine_reinstalled = true
  end
  engine_installed = true
  return true
end

local function engine_ensure_attached()
  if engine_attached then return true end
  if not r.gmem_attach then return false end
  r.gmem_attach(GMEM_NAME)
  engine_attached = true
  return true
end

local function engine_id_for(parent)
  if not parent then return 0 end
  local ok, val = r.GetSetMediaTrackInfo_String(parent, ENGINE_ID_KEY, "", false)
  local id = ok and math.floor(tonumber(val) or 0) or 0
  if id <= 0 then
    id = math.random(1, 100000000)
    r.GetSetMediaTrackInfo_String(parent, ENGINE_ID_KEY, tostring(id), true)
  end
  return id
end

local function engine_find_fx(track)
  if not track or not r.TrackFX_GetCount then return -1 end
  local count = r.TrackFX_GetCount(track)
  for i = 0, count - 1 do
    local ok, name = r.TrackFX_GetFXName(track, i, "")
    if ok and name and name:lower():find("tk kit maker sequencer", 1, true) then
      return i
    end
  end
  return -1
end

local function engine_cleanup_parent(parent, lane_tracks)
  if not parent then return end
  local guard = 0
  local fx = engine_find_fx(parent)
  while fx >= 0 and r.TrackFX_Delete and guard < 8 do
    r.TrackFX_Delete(parent, fx)
    fx = engine_find_fx(parent)
    guard = guard + 1
  end
  if r.GetTrackNumSends and r.RemoveTrackSend then
    local num = r.GetTrackNumSends(parent, 0)
    for i = num - 1, 0, -1 do
      local dest = r.GetTrackSendInfo_Value(parent, 0, i, "P_DESTTRACK")
      local srcchan = math.floor((r.GetTrackSendInfo_Value(parent, 0, i, "I_SRCCHAN") or 0) + 0.5)
      local is_lane = false
      for lane = 1, #lane_tracks do
        if lane_tracks[lane] and dest == lane_tracks[lane] then
          is_lane = true
          break
        end
      end
      if is_lane and srcchan == -1 then
        r.RemoveTrackSend(parent, 0, i)
      end
    end
  end
end

local function engine_add_fx_end(track)
  if not track or not r.TrackFX_AddByName then return -1 end
  local candidates = {
    EngineJSFX.add_name,
    "JS: TK Kit Maker Sequencer",
    "TK Kit Maker Sequencer",
  }
  local fx = -1
  for _, name in ipairs(candidates) do
    fx = r.TrackFX_AddByName(track, name, false, -1)
    if fx and fx >= 0 then break end
  end
  if fx and fx >= 0 and r.TrackFX_Show then
    r.TrackFX_Show(track, fx, 2)
  end
  return fx or -1
end

local function engine_cleanup_lane_fx(lane_tracks)
  if not lane_tracks then return end
  for lane = 1, #lane_tracks do
    local tr = lane_tracks[lane]
    if tr then
      local guard = 0
      local fx = engine_find_fx(tr)
      while fx >= 0 and r.TrackFX_Delete and guard < 8 do
        r.TrackFX_Delete(tr, fx)
        fx = engine_find_fx(tr)
        guard = guard + 1
      end
    end
  end
end

local function engine_find_bus(parent)
  if not parent then return nil end
  local parent_depth = r.GetTrackDepth(parent)
  local parent_idx = get_track_index0(parent)
  local count = r.CountTracks(0)
  for i = parent_idx + 1, count - 1 do
    local tr = r.GetTrack(0, i)
    if r.GetTrackDepth(tr) <= parent_depth then break end
    if track_is_seq_bus(tr) then return tr end
  end
  return nil
end

local function engine_create_bus(parent)
  if not parent or not r.InsertTrackAtIndex then return nil end
  local parent_idx = get_track_index0(parent)
  r.InsertTrackAtIndex(parent_idx + 1, false)
  local bus = r.GetTrack(0, parent_idx + 1)
  if not bus then return nil end
  r.GetSetMediaTrackInfo_String(bus, "P_NAME", "TK Seq Engine", true)
  r.GetSetMediaTrackInfo_String(bus, BUS_MARKER, track_guid(parent) or "1", true)
  r.SetMediaTrackInfo_Value(bus, "I_FOLDERDEPTH", 0)
  if (r.GetMediaTrackInfo_Value(parent, "I_FOLDERDEPTH") or 0) < 1 then
    r.SetMediaTrackInfo_Value(parent, "I_FOLDERDEPTH", 1)
  end
  if r.SetMediaTrackInfo_Value then
    r.SetMediaTrackInfo_Value(bus, "I_MIDIHWOUT", -1)
    r.SetMediaTrackInfo_Value(bus, "B_MAINSEND", 0)
  end
  if r.TrackList_AdjustWindows then r.TrackList_AdjustWindows(false) end
  return bus
end

local function engine_ensure_bus_sends(bus, lane_tracks)
  if not bus or not lane_tracks or not r.GetTrackNumSends then return 0 end
  local have = {}
  local num = r.GetTrackNumSends(bus, 0)
  for i = 0, num - 1 do
    local dest = r.GetTrackSendInfo_Value(bus, 0, i, "P_DESTTRACK")
    for lane = 1, #lane_tracks do
      if lane_tracks[lane] and dest == lane_tracks[lane] then
        have[lane] = true
        r.SetTrackSendInfo_Value(bus, 0, i, "I_SRCCHAN", -1)
        r.SetTrackSendInfo_Value(bus, 0, i, "I_MIDIFLAGS", 0)
      end
    end
  end
  local count = 0
  for lane = 1, #lane_tracks do
    local lt = lane_tracks[lane]
    if lt then
      if not have[lane] and r.CreateTrackSend then
        local idx = r.CreateTrackSend(bus, lt)
        if idx and idx >= 0 then
          r.SetTrackSendInfo_Value(bus, 0, idx, "I_SRCCHAN", -1)
          r.SetTrackSendInfo_Value(bus, 0, idx, "I_MIDIFLAGS", 0)
          count = count + 1
        end
      else
        count = count + 1
      end
    end
  end
  return count
end

local function engine_ensure_bus(parent, lane_tracks)
  engine_ensure_installed()
  if not engine_parent_cleaned then
    engine_cleanup_parent(parent, lane_tracks)
    engine_cleanup_lane_fx(lane_tracks)
    engine_parent_cleaned = true
  end
  local bus = engine_find_bus(parent)
  if not bus then
    bus = engine_create_bus(parent)
  end
  if not bus then return nil, 0 end
  local fx = engine_find_fx(bus)
  if fx >= 0 and engine_reinstalled and r.TrackFX_Delete then
    r.TrackFX_Delete(bus, fx)
    fx = -1
  end
  if fx < 0 then
    fx = engine_add_fx_end(bus)
  end
  if fx and fx >= 0 then
    engine_reinstalled = false
  end
  local sends = engine_ensure_bus_sends(bus, lane_tracks)
  return bus, sends
end

local function engine_write_globals(sync_mode, running, total_steps, any_solo, tempo, active_id)
  if not r.gmem_write then return end
  r.gmem_write(G_SYNC, sync_mode or 0)
  r.gmem_write(G_RUN, running and 1 or 0)
  r.gmem_write(G_TOTAL, total_steps or STEPS_PER_BAR)
  r.gmem_write(G_SOLO, any_solo and 1 or 0)
  r.gmem_write(G_TEMPO, tempo or 0)
  r.gmem_write(G_NLANES, GRID_SLOTS)
  r.gmem_write(G_BASE, BASE_NOTE)
  r.gmem_write(G_ACTIVE, active_id or 0)
  engine_epoch = engine_epoch + 1
  r.gmem_write(G_EPOCH, engine_epoch)
end

local function engine_bump_restart()
  if not r.gmem_write then return end
  engine_restart_seq = engine_restart_seq + 1
  r.gmem_write(G_RESTART, engine_restart_seq)
end

local function engine_write_pattern(seq, solo_map, total_steps, lane_tracks, lane_fx_list)
  if not r.gmem_write then return end
  local lane_settings = seq.lane_settings or {}
  for lane = 1, GRID_SLOTS do
    local LB = LANE_BASE + (lane - 1) * LANE_STRIDE
    local cfg = lane_settings[lane] or {}
    local cycle = clamp(math.floor(tonumber(cfg.cycle_steps) or total_steps), 1, total_steps)
    local speed = normalize_lane_speed(cfg.speed)
    local mode = (cfg.mode == "gate") and 1 or 0
    local retrig = (cfg.retrigger ~= false) and 1 or 0
    local note = clamp(BASE_NOTE + (lane - 1), 0, 127)
    local lane_track = lane_tracks and lane_tracks[lane] or nil
    local lane_fx = lane_fx_list and lane_fx_list[lane] or -1
    local obey = 1
    if lane_track and lane_fx >= 0 then
      obey = rs5k_obeys_note_off(lane_track, lane_fx) and 1 or 0
    end
    local solo = (solo_map and solo_map[lane] == true) and 1 or 0
    r.gmem_write(LB + L_CYCLE, cycle)
    r.gmem_write(LB + L_SPEED, speed)
    r.gmem_write(LB + L_SOLO, solo)
    r.gmem_write(LB + L_MODE, mode)
    r.gmem_write(LB + L_RETRIG, retrig)
    r.gmem_write(LB + L_NOTE, note)
    r.gmem_write(LB + L_OBEY, obey)
    local pattern_lane = seq.pattern and seq.pattern[lane] or nil
    for step = 1, STEPS_PER_BAR do
      local on = (pattern_lane and pattern_lane[step] == 1) and 1 or 0
      r.gmem_write(LB + L_ON + (step - 1), on)
      r.gmem_write(LB + L_VEL + (step - 1), clamp(math.floor(tonumber(table_step_value(cfg.step_velocity, step, 100)) or 100), 1, 127))
      r.gmem_write(LB + L_GATE + (step - 1), clamp(math.floor(tonumber(table_step_value(cfg.step_gate, step, 100)) or 100), 1, 100))
      r.gmem_write(LB + L_LEN + (step - 1), clamp(math.floor(tonumber(table_step_value(cfg.step_length, step, 1)) or 1), 1, total_steps))
      r.gmem_write(LB + L_SUB + (step - 1), clamp(math.floor(tonumber(table_step_value(cfg.step_substeps, step, 1)) or 1), 1, 8))
      r.gmem_write(LB + L_PROB + (step - 1), clamp(math.floor(tonumber(table_step_value(cfg.step_probability, step, 100)) or 100), 0, 100))
    end
  end
end

local function engine_read_lane_step(lane)
  if not r.gmem_read then return nil end
  local v = math.floor((tonumber(r.gmem_read(G_LANEPH + (lane - 1))) or 0) + 0.5)
  if v < 1 then return nil end
  return v
end

local function engine_deactivate()
  if not r.gmem_write then return end
  r.gmem_write(G_RUN, 0)
  r.gmem_write(G_ACTIVE, 0)
end

local function start_playback(state, guid, song_mode)
  state.playing = true
  state.song_mode = song_mode == true
  state.current_guid = guid
  state.last_step = nil
  state.lane_clocks = {}
  state.pending_events = {}
  state.lane_play_steps = {}
  state.lane_applied_step = {}
  state.engine_restart_pending = true
  state.started_at = r.time_precise and r.time_precise() or os.clock()
end

local function stop_playback(state, parent)
  state.playing = false
  state.song_mode = false
  state.song_playhead = nil
  state.last_step = nil
  state.lane_clocks = {}
  state.pending_events = {}
  state.lane_play_steps = {}
  state.lane_applied_step = {}
  engine_deactivate()
  stop_notes(state)
  if parent then
    local lane_tracks = collect_lane_tracks(parent)
    for lane = 1, #lane_tracks do
      local lane_track = lane_tracks[lane]
      local lane_fx = lane_track and find_rs5k_fx(lane_track) or -1
      if lane_track and lane_fx >= 0 then
        set_rs5k_pitch_semitones(lane_track, lane_fx, 0)
        set_rs5k_pan_percent(lane_track, lane_fx, 0)
        set_rs5k_volume_db(lane_track, lane_fx, 0)
      end
    end
  end
end

local function resolve_song_playhead(state, seq, total_steps)
  local slots = type(seq and seq.song_slots) == "table" and seq.song_slots or {}
  local tempo = tonumber(r.Master_GetTempo and r.Master_GetTempo() or 120) or 120
  local step_duration = (60 / tempo) / 4
  if step_duration <= 0 then step_duration = 0.125 end
  local page_duration = total_steps * step_duration
  if page_duration <= 0 then page_duration = step_duration * 16 end
  local elapsed = (r.time_precise and r.time_precise() or os.clock()) - (state.started_at or 0)
  if elapsed < 0 then elapsed = 0 end

  local total_pages = 0
  for slot = 1, 8 do
    local item = slots[slot]
    local page = type(item) == "table" and clamp(math.floor(tonumber(item.page) or 0), 0, PATTERN_SLOTS) or 0
    local repeats = type(item) == "table" and clamp(math.floor(tonumber(item.repeats) or 1), 1, 8) or 1
    if page > 0 then
      total_pages = total_pages + repeats
    end
  end

  if total_pages <= 0 then
    return {
      active = true,
      slot = 1,
      page = 1,
      repeat_index = 1,
      elapsed = elapsed,
      total_pages = 1,
    }
  end

  local page_index = math.floor(elapsed / page_duration)
  if page_index >= total_pages then
    if seq and seq.repeat_enabled ~= false then
      page_index = page_index % total_pages
    else
      return {
        active = false,
        ended = true,
        elapsed = elapsed,
        total_pages = total_pages,
      }
    end
  end

  if seq and seq.repeat_enabled ~= false and total_pages > 0 then
    page_index = page_index % total_pages
  end

  local remain = page_index
  for slot = 1, 8 do
    local item = slots[slot]
    local page = type(item) == "table" and clamp(math.floor(tonumber(item.page) or 0), 0, PATTERN_SLOTS) or 0
    local repeats = type(item) == "table" and clamp(math.floor(tonumber(item.repeats) or 1), 1, 8) or 1
    if page > 0 then
      if remain < repeats then
        return {
          active = true,
          slot = slot,
          page = page,
          repeat_index = remain + 1,
          elapsed = elapsed,
          total_pages = total_pages,
        }
      end
      remain = remain - repeats
    end
  end

  return {
    active = false,
    ended = true,
    elapsed = elapsed,
    total_pages = total_pages,
  }
end

local function restart_playback_synced(state, guid)
  if not state.playing then return end
  stop_notes(state)
  state.lane_applied_step = {}
  state.engine_restart_pending = true
end

local function release_scheduled_notes(state, elapsed)
  for lane, entry in pairs(state.active_notes or {}) do
    if entry and entry.note and entry.off_at_time and elapsed >= entry.off_at_time then
      send_note_off(entry.note)
      state.active_notes[lane] = nil
    end
  end
end

local function process_preview_note_offs(state)
  local pending = state.preview_note_offs or {}
  if not next(pending) then return end
  local now = r.time_precise and r.time_precise() or os.clock()
  for note, off_at in pairs(pending) do
    if (tonumber(off_at) or 0) <= now then
      send_note_off(note)
      pending[note] = nil
    end
  end
  state.preview_note_offs = pending
end

local function trigger_step_preview(state, lane, lane_step, lane_cfg, lane_track, lane_fx, rs5k_note_off, total_steps)
  if not r.StuffMIDIMessage then return end
  local base_note = BASE_NOTE + (lane - 1)
  local step_pitch = clamp(math.floor(tonumber(table_step_value(lane_cfg.step_pitch, lane_step, 0)) or 0), -24, 24)
  local step_pan = clamp(math.floor(tonumber(table_step_value(lane_cfg.step_pan, lane_step, 0)) or 0), -100, 100)
  local step_volume = clamp(math.floor(tonumber(table_step_value(lane_cfg.step_volume, lane_step, 0)) or 0), -24, 24)
  local note = clamp(base_note, 0, 127)
  local default_vel = 100
  local step_vel = clamp(math.floor(tonumber(table_step_value(lane_cfg.step_velocity, lane_step, default_vel)) or default_vel), 1, 127)
  local step_gate = clamp(math.floor(tonumber(table_step_value(lane_cfg.step_gate, lane_step, 100)) or 100), 1, 100)
  local step_len = clamp(math.floor(tonumber(table_step_value(lane_cfg.step_length, lane_step, 1)) or 1), 1, total_steps)
  local tempo = tonumber(r.Master_GetTempo and r.Master_GetTempo() or 120) or 120
  local step_duration = (60 / tempo) / 4
  if step_duration <= 0 then step_duration = 0.125 end
  local length_time = step_len * step_duration
  local gate_time = length_time * (step_gate / 100)
  if gate_time <= 0 then gate_time = step_duration * 0.5 end

  if lane_track and lane_fx and lane_fx >= 0 then
    set_rs5k_pitch_semitones(lane_track, lane_fx, step_pitch)
    set_rs5k_pan_percent(lane_track, lane_fx, step_pan)
    set_rs5k_volume_db(lane_track, lane_fx, step_volume)
  end

  send_note_off(note)
  if not send_note_on(note, step_vel) then return end

  state.preview_note_offs = state.preview_note_offs or {}
  if rs5k_note_off and (lane_cfg.mode or "gate") == "gate" then
    local now = r.time_precise and r.time_precise() or os.clock()
    state.preview_note_offs[note] = now + gate_time
  else
    state.preview_note_offs[note] = nil
  end
end

local function process_lane_events(state, seq, total_steps, solo_map, any_solo, lane_tracks)
  if not state.playing or not r.StuffMIDIMessage then return end
  local now = r.time_precise and r.time_precise() or os.clock()
  local elapsed = now - (state.started_at or now)
  if elapsed < 0 then elapsed = 0 end

  local tempo = tonumber(r.Master_GetTempo and r.Master_GetTempo() or 120) or 120
  local step_duration = (60 / tempo) / 4
  if step_duration <= 0 then step_duration = 0.125 end
  local cycle_duration = total_steps * step_duration
  local default_vel = 100
  local lane_settings = seq.lane_settings or {}

  run_pending_substep_events(state, elapsed)
  release_scheduled_notes(state, elapsed)

  for lane = 1, GRID_SLOTS do
    local lane_is_solo = solo_map and solo_map[lane] == true
    if any_solo and not lane_is_solo then
      local active = state.active_notes[lane]
      if active and active.note then
        send_note_off(active.note)
        state.active_notes[lane] = nil
      end
      goto continue_lane
    end

    local cfg = lane_settings[lane] or { mode = "gate", cycle_steps = total_steps, speed = 1, retrigger = true }
    ensure_lane_step_params(cfg, total_steps, default_vel)
    lane_settings[lane] = cfg
    local cycle_steps = clamp(math.floor(tonumber(cfg.cycle_steps) or total_steps), 1, total_steps)
    local lane_speed = normalize_lane_speed(cfg.speed)
    local lane_track = lane_tracks and lane_tracks[lane] or nil
    local lane_fx = lane_track and find_rs5k_fx(lane_track) or -1
    local rs5k_note_off = lane_fx >= 0 and rs5k_obeys_note_off(lane_track, lane_fx) or true
    local lane_period = cycle_duration / (cycle_steps * lane_speed)
    if lane_period <= 0 then lane_period = step_duration end

    local clock = state.lane_clocks[lane]
    if not clock then
      clock = { next_time = 0, step_index = 1 }
      state.lane_clocks[lane] = clock
    end

    while elapsed + 0.0000001 >= clock.next_time do
      local event_time = clock.next_time
      local lane_step = clock.step_index
      if seq.pattern[lane] and seq.pattern[lane][lane_step] == 1 then
        local base_note = BASE_NOTE + (lane - 1)
        local step_pitch = clamp(math.floor(tonumber(table_step_value(cfg.step_pitch, lane_step, 0)) or 0), -24, 24)
        local step_pan = clamp(math.floor(tonumber(table_step_value(cfg.step_pan, lane_step, 0)) or 0), -100, 100)
        local step_volume = clamp(math.floor(tonumber(table_step_value(cfg.step_volume, lane_step, 0)) or 0), -24, 24)
        local note = clamp(base_note, 0, 127)
        local mode = cfg.mode or "gate"
        local retrigger = cfg.retrigger ~= false
        local step_vel = clamp(math.floor(tonumber(table_step_value(cfg.step_velocity, lane_step, default_vel)) or default_vel), 1, 127)
        local step_gate = clamp(math.floor(tonumber(table_step_value(cfg.step_gate, lane_step, 100)) or 100), 1, 100)
        local step_len = clamp(math.floor(tonumber(table_step_value(cfg.step_length, lane_step, 1)) or 1), 1, total_steps)
        local step_substeps = clamp(math.floor(tonumber(table_step_value(cfg.step_substeps, lane_step, 1)) or 1), 1, 8)
        local step_prob = clamp(math.floor(tonumber(table_step_value(cfg.step_probability, lane_step, 100)) or 100), 0, 100)
        local chance_ok = step_prob >= 100 or (step_prob > 0 and (math.random() * 100) <= step_prob)
        if chance_ok then
          local sub_period = lane_period / step_substeps
          if sub_period <= 0 then sub_period = step_duration end
          local length_time = step_len * step_duration
          local gate_time = length_time * (step_gate / 100)
          if gate_time <= 0 then gate_time = math.min(step_duration, sub_period) end

          local off_at_time = nil
          if rs5k_note_off and mode == "gate" then
            off_at_time = event_time + gate_time
          end
          if lane_track and lane_fx >= 0 then
            set_rs5k_pitch_semitones(lane_track, lane_fx, step_pitch)
            set_rs5k_pan_percent(lane_track, lane_fx, step_pan)
            set_rs5k_volume_db(lane_track, lane_fx, step_volume)
          end
          trigger_lane_note(state, lane, note, step_vel, mode, retrigger, off_at_time)

          if step_substeps > 1 then
            for sub_idx = 2, step_substeps do
              local at_time = event_time + ((sub_idx - 1) * sub_period)
              local sub_lookahead = clamp(sub_period * 0.14, SUBSTEP_LOOKAHEAD_MIN, SUBSTEP_LOOKAHEAD_MAX)
              local ev_off = nil
              if rs5k_note_off and mode == "gate" then
                ev_off = at_time + gate_time
              end
              if at_time <= (elapsed + sub_lookahead) + 0.0000001 then
                if lane_track and lane_fx >= 0 then
                  set_rs5k_pitch_semitones(lane_track, lane_fx, step_pitch)
                  set_rs5k_pan_percent(lane_track, lane_fx, step_pan)
                  set_rs5k_volume_db(lane_track, lane_fx, step_volume)
                end
                trigger_lane_note(state, lane, note, step_vel, mode, true, ev_off)
              else
                state.pending_events = state.pending_events or {}
                state.pending_events[#state.pending_events + 1] = {
                  at = at_time,
                  lookahead = sub_lookahead,
                  track = lane_track,
                  fx = lane_fx,
                  pitch = step_pitch,
                  pan = step_pan,
                  volume = step_volume,
                  lane = lane,
                  note = note,
                  vel = step_vel,
                  mode = mode,
                  retrigger = true,
                  off_at_time = ev_off,
                }
              end
            end
          end
        end
      end

      clock.last_step = lane_step
      clock.step_index = (clock.step_index % cycle_steps) + 1
      clock.next_time = clock.next_time + lane_period
    end
    ::continue_lane::
  end
end

local function engine_sync(state, seq, parent, solo_map, any_solo, total_steps, lane_tracks, host_enabled)
  if not parent then return end
  engine_ensure_attached()

  local id = engine_id_for(parent)
  if state.engine_setup_id ~= id or state.engine_restart_pending then
    if r.PreventUIRefresh then r.PreventUIRefresh(1) end
    local bus, sends = engine_ensure_bus(parent, lane_tracks)
    if r.PreventUIRefresh then r.PreventUIRefresh(-1) end
    state.engine_bus_ok = bus ~= nil
    state.engine_send_count = sends or 0
    if bus then
      state.engine_setup_id = id
    end
  end
  state.engine_fx_present = state.engine_bus_ok == true

  local tempo = tonumber(r.Master_GetTempo and r.Master_GetTempo() or 120) or 120
  if tempo <= 0 then tempo = 120 end
  local sync_mode = host_enabled and 1 or 0
  local running = state.playing == true

  local lane_fx_list = {}
  for lane = 1, GRID_SLOTS do
    local lane_track = lane_tracks and lane_tracks[lane] or nil
    lane_fx_list[lane] = lane_track and find_rs5k_fx(lane_track) or -1
  end

  engine_write_pattern(seq, solo_map, total_steps, lane_tracks, lane_fx_list)
  engine_write_globals(sync_mode, running, total_steps, any_solo, tempo, id)

  if state.engine_restart_pending then
    engine_bump_restart()
    state.engine_restart_pending = false
  end

  state.lane_play_steps = state.lane_play_steps or {}
  state.lane_applied_step = state.lane_applied_step or {}
  local lane_settings = seq.lane_settings or {}
  for lane = 1, GRID_SLOTS do
    local cur = engine_read_lane_step(lane)
    state.lane_play_steps[lane] = cur
    if cur then
      local cfg = lane_settings[lane]
      local pattern_lane = seq.pattern and seq.pattern[lane]
      local is_on = pattern_lane and pattern_lane[cur] == 1
      if cfg and is_on and state.lane_applied_step[lane] ~= cur then
        state.lane_applied_step[lane] = cur
        local lane_track = lane_tracks and lane_tracks[lane] or nil
        local lane_fx = lane_fx_list[lane] or -1
        if lane_track and lane_fx >= 0 then
          local step_pitch = clamp(math.floor(tonumber(table_step_value(cfg.step_pitch, cur, 0)) or 0), -24, 24)
          local step_pan = clamp(math.floor(tonumber(table_step_value(cfg.step_pan, cur, 0)) or 0), -100, 100)
          local step_volume = clamp(math.floor(tonumber(table_step_value(cfg.step_volume, cur, 0)) or 0), -24, 24)
          set_rs5k_pitch_semitones(lane_track, lane_fx, step_pitch)
          set_rs5k_pan_percent(lane_track, lane_fx, step_pan)
          set_rs5k_volume_db(lane_track, lane_fx, step_volume)
        end
      end
    end
  end

  local alive_now = (r.gmem_read and math.floor((tonumber(r.gmem_read(G_ALIVE)) or 0) + 0.5)) or 0
  if alive_now ~= (state.engine_alive_last or -1) then
    state.engine_alive_last = alive_now
    state.engine_dead_frames = 0
  else
    state.engine_dead_frames = (state.engine_dead_frames or 0) + 1
  end

  local on_steps = 0
  for lane = 1, GRID_SLOTS do
    local pl = seq.pattern and seq.pattern[lane]
    if pl then
      for step = 1, STEPS_PER_BAR do
        if pl[step] == 1 then on_steps = on_steps + 1 end
      end
    end
  end
  state.dbg = {
    bus = state.engine_bus_ok and 1 or 0,
    snd = state.engine_send_count or 0,
    alive = alive_now,
    live = (state.engine_dead_frames or 0) < 3,
    run = running and 1 or 0,
    sync = sync_mode,
    ph = math.floor(((r.gmem_read and tonumber(r.gmem_read(G_PH))) or 0) + 0.5),
    on = on_steps,
    solo = any_solo and 1 or 0,
    nt = math.floor(((r.gmem_read and tonumber(r.gmem_read(G_NOTES))) or 0) + 0.5),
  }
end

local function current_step_index(state, seq)
  local total_steps = clamp(math.floor(tonumber(seq.steps) or STEPS_PER_BAR), 4, STEPS_PER_BAR * 4)
  local tempo = tonumber(r.Master_GetTempo and r.Master_GetTempo() or 120) or 120
  local step_duration = (60 / tempo) / 4
  if step_duration <= 0 then step_duration = 0.125 end
  local elapsed = (r.time_precise and r.time_precise() or os.clock()) - (state.started_at or 0)
  if elapsed < 0 then elapsed = 0 end
  local idx = math.floor(elapsed / step_duration) % total_steps
  return idx + 1
end

local function lane_step_for_global_step(global_step, cycle_steps, total_steps)
  local gs = clamp(math.floor(tonumber(global_step) or 1), 1, total_steps)
  local cs = clamp(math.floor(tonumber(cycle_steps) or total_steps), 1, total_steps)
  local idx = math.floor(((gs - 1) * cs) / total_steps) + 1
  return clamp(idx, 1, cs)
end

local function time_to_qn(t)
  if r.TimeMap2_timeToQN then
    return r.TimeMap2_timeToQN(0, t)
  end
  if r.TimeMap_timeToQN then
    return r.TimeMap_timeToQN(t)
  end
  local tempo = tonumber(r.Master_GetTempo and r.Master_GetTempo() or 120) or 120
  return (t * tempo) / 60
end

local function qn_to_time(qn)
  if r.TimeMap2_QNToTime then
    return r.TimeMap2_QNToTime(0, qn)
  end
  if r.TimeMap_QNToTime then
    return r.TimeMap_QNToTime(qn)
  end
  local tempo = tonumber(r.Master_GetTempo and r.Master_GetTempo() or 120) or 120
  return (qn * 60) / tempo
end

table_step_value = function(tbl, idx, default)
  if type(tbl) ~= "table" then return default end
  local v = tbl[idx]
  if v == nil then
    v = tbl[tostring(idx)]
  end
  if v == nil then
    return default
  end
  return v
end

collect_lane_tracks = function(parent)
  local out = {}
  if not parent then return out end
  local parent_depth = r.GetTrackDepth(parent)
  local direct_depth = parent_depth + 1
  local parent_idx = get_track_index0(parent)
  local track_count = r.CountTracks(0)
  for i = parent_idx + 1, track_count - 1 do
    local tr = r.GetTrack(0, i)
    local depth = r.GetTrackDepth(tr)
    if depth <= parent_depth then
      break
    end
    if depth == direct_depth then
      if not track_is_seq_bus(tr) then
        out[#out + 1] = tr
        if #out >= GRID_SLOTS then
          break
        end
      end
    end
  end
  return out
end

local function lane_index_for_track(lane_tracks, track)
  if not lane_tracks or not track then return nil end
  for lane = 1, #lane_tracks do
    if lane_tracks[lane] == track then
      return lane
    end
  end
  return nil
end

local function rs5k_note_for_track(track, fallback_note)
  local fallback = clamp(math.floor(tonumber(fallback_note) or BASE_NOTE), 0, 127)
  local fx = find_rs5k_fx(track)
  if fx < 0 or not r.TrackFX_GetParamNormalized then
    return fallback
  end
  local n = r.TrackFX_GetParamNormalized(track, fx, 3)
  if n == nil then
    return fallback
  end
  return clamp(math.floor((n * 127) + 0.5), 0, 127)
end

local function export_sequence_to_midi(track, seq, opts)
  if not track then return false, 0 end
  opts = type(opts) == "table" and opts or nil
  local song_mode = opts and opts.song_mode == true
  local current_slot = clamp(math.floor(tonumber(opts and opts.current_slot) or 1), 1, PATTERN_SLOTS)
  local section_plan = {}

  local function build_lane_events(section_seq, lane, section_steps, rs5k_note_off, base_pitch)
    local cfg = section_seq.lane_settings and section_seq.lane_settings[lane] or { mode = "gate", cycle_steps = section_steps, speed = 1, retrigger = true }
    ensure_lane_step_params(cfg, section_steps, 100)
    local mode = tostring(cfg.mode or "gate")
    if mode ~= "gate" and mode ~= "oneshot" then
      mode = "gate"
    end
    local retrigger = cfg.retrigger ~= false
    local cycle_steps = clamp(math.floor(tonumber(cfg.cycle_steps) or section_steps), 1, section_steps)
    local lane_speed = normalize_lane_speed(cfg.speed)
    local lane_period_steps = (section_steps / cycle_steps) / lane_speed
    local events = {}
    local triggers = {}

    local lane_step = 1
    local lane_step_start = 0
    while lane_step_start < section_steps do
      if section_seq.pattern and section_seq.pattern[lane] and section_seq.pattern[lane][lane_step] == 1 then
        local step_vel = clamp(math.floor(tonumber(table_step_value(cfg.step_velocity, lane_step, 100)) or 100), 1, 127)
        local step_gate = clamp(math.floor(tonumber(table_step_value(cfg.step_gate, lane_step, 100)) or 100), 1, 100)
        local step_len = clamp(math.floor(tonumber(table_step_value(cfg.step_length, lane_step, 1)) or 1), 1, section_steps)
        local step_substeps = clamp(math.floor(tonumber(table_step_value(cfg.step_substeps, lane_step, 1)) or 1), 1, 8)
        local step_prob = clamp(math.floor(tonumber(table_step_value(cfg.step_probability, lane_step, 100)) or 100), 0, 100)
        local chance_ok = step_prob >= 100 or (step_prob > 0 and (math.random() * 100) <= step_prob)
        if chance_ok then
          local sub_period_steps = lane_period_steps / step_substeps
          local gate_steps = step_len * (step_gate / 100)
          if gate_steps <= 0 then
            gate_steps = math.min(1, sub_period_steps)
          end

          for sub_idx = 1, step_substeps do
            local start_steps = lane_step_start + ((sub_idx - 1) * sub_period_steps)
            if start_steps < section_steps then
              if (not rs5k_note_off) or mode == "oneshot" then
                triggers[#triggers + 1] = {
                  start_steps = start_steps,
                  vel = step_vel,
                  pitch = clamp(base_pitch + clamp(math.floor(tonumber(table_step_value(cfg.step_pitch, lane_step, 0)) or 0), -24, 24), 0, 127),
                }
              else
                local end_steps = start_steps + gate_steps
                if end_steps > section_steps then end_steps = section_steps end
                events[#events + 1] = {
                  start_steps = start_steps,
                  end_steps = end_steps,
                  vel = step_vel,
                  pitch = clamp(base_pitch + clamp(math.floor(tonumber(table_step_value(cfg.step_pitch, lane_step, 0)) or 0), -24, 24), 0, 127),
                }
              end
            end
          end
        end
      end
      lane_step = (lane_step % cycle_steps) + 1
      lane_step_start = lane_step_start + lane_period_steps
    end

    if #triggers > 0 then
      if retrigger then
        for i = 1, #triggers do
          local cur = triggers[i]
          local nxt = triggers[i + 1]
          local end_steps = nxt and nxt.start_steps or section_steps
          if end_steps <= cur.start_steps then
            end_steps = cur.start_steps + (1 / 64)
          end
          events[#events + 1] = {
            start_steps = cur.start_steps,
            end_steps = math.min(end_steps, section_steps),
            vel = cur.vel,
            pitch = cur.pitch,
          }
        end
      else
        local first = triggers[1]
        events[#events + 1] = {
          start_steps = first.start_steps,
          end_steps = section_steps,
          vel = first.vel,
          pitch = first.pitch,
        }
      end
    end

    if (not retrigger) and mode ~= "oneshot" and #events > 1 then
      local merged = {}
      local current = events[1]
      for i = 2, #events do
        local ev = events[i]
        if ev.start_steps <= current.end_steps and ev.pitch == current.pitch then
          if ev.end_steps > current.end_steps then
            current.end_steps = ev.end_steps
          end
        else
          merged[#merged + 1] = current
          current = ev
        end
      end
      merged[#merged + 1] = current
      events = merged
    end

    return events
  end

  if song_mode then
    local slots = type(seq.song_slots) == "table" and seq.song_slots or {}
    for song_slot = 1, 8 do
      local entry = slots[song_slot]
      local page = type(entry) == "table" and clamp(math.floor(tonumber(entry.page) or 0), 0, PATTERN_SLOTS) or 0
      local repeats = type(entry) == "table" and clamp(math.floor(tonumber(entry.repeats) or 1), 1, 8) or 1
      if page > 0 then
        local page_seq = resolve_slot_sequence_for_export(opts and opts.state, opts and opts.guid, opts and opts.patterns, opts and opts.selected_pattern_index, page, seq, current_slot, seq)
        local page_steps = clamp(math.floor(tonumber(page_seq.steps) or STEPS_PER_BAR), 4, STEPS_PER_BAR * 4)
        for _ = 1, repeats do
          section_plan[#section_plan + 1] = {
            seq = page_seq,
            steps = page_steps,
          }
        end
      end
    end
  end

  if #section_plan == 0 then
    local fallback_seq = song_mode
      and resolve_slot_sequence_for_export(opts and opts.state, opts and opts.guid, opts and opts.patterns, opts and opts.selected_pattern_index, current_slot, seq, current_slot, seq)
      or sanitize_sequence(seq)
    section_plan[1] = {
      seq = fallback_seq,
      steps = clamp(math.floor(tonumber(fallback_seq.steps) or STEPS_PER_BAR), 4, STEPS_PER_BAR * 4),
    }
  end

  local total_steps = 0
  for i = 1, #section_plan do
    total_steps = total_steps + section_plan[i].steps
  end
  if total_steps <= 0 then
    total_steps = STEPS_PER_BAR
  end

  local step_cursor = 0
  for i = 1, #section_plan do
    section_plan[i].start_steps = step_cursor
    step_cursor = step_cursor + section_plan[i].steps
  end

  local lane_tracks = collect_lane_tracks(track)
  if #lane_tracks == 0 then return false, 0 end
  local cursor_time = (r.GetCursorPositionEx and r.GetCursorPositionEx(0)) or r.GetCursorPosition()
  local start_qn = time_to_qn(cursor_time)

  local inserted = 0
  for lane = 1, GRID_SLOTS do
    local lane_track = lane_tracks[lane]
    if lane_track then
      local base_pitch = rs5k_note_for_track(lane_track, BASE_NOTE + (lane - 1))
      local lane_fx = find_rs5k_fx(lane_track)
      local rs5k_note_off = lane_track and lane_fx >= 0 and rs5k_obeys_note_off(lane_track, lane_fx) or true

      for section_idx = 1, #section_plan do
        local section = section_plan[section_idx]
        local section_start_qn = start_qn + ((section.start_steps or 0) / 4)
        local section_end_qn = section_start_qn + (section.steps / 4)
        local section_start_time = qn_to_time(section_start_qn)
        local section_end_time = qn_to_time(section_end_qn)
        if not section_start_time then section_start_time = cursor_time end
        if not section_end_time or section_end_time <= section_start_time then
          section_end_time = section_start_time + 1.0
        end

        local sec_item = r.CreateNewMIDIItemInProj(lane_track, section_start_time, section_end_time, false)
        if sec_item then
          local take = r.GetActiveTake(sec_item)
          if take and r.TakeIsMIDI(take) then
            local events = build_lane_events(section.seq, lane, section.steps, rs5k_note_off, base_pitch)
            local inserted_lane = 0
            for _, ev in ipairs(events) do
              local note_start_qn = section_start_qn + (ev.start_steps / 4)
              local note_end_qn = section_start_qn + (ev.end_steps / 4)
              if note_end_qn <= note_start_qn then
                note_end_qn = note_start_qn + (1 / 64)
              end
              local note_start_time = qn_to_time(note_start_qn)
              local note_end_time = qn_to_time(note_end_qn)
              local start_ppq = r.MIDI_GetPPQPosFromProjTime(take, note_start_time)
              local end_ppq = r.MIDI_GetPPQPosFromProjTime(take, note_end_time)
              if end_ppq <= start_ppq then
                end_ppq = start_ppq + 1
              end
              local ok = r.MIDI_InsertNote(take, false, false, start_ppq, end_ppq, 0, ev.pitch or base_pitch, ev.vel, true)
              if ok then
                inserted_lane = inserted_lane + 1
                inserted = inserted + 1
              end
            end
            if inserted_lane > 0 then
              r.MIDI_Sort(take)
            else
              r.DeleteTrackMediaItem(lane_track, sec_item)
            end
          else
            r.DeleteTrackMediaItem(lane_track, sec_item)
          end
        end
      end
    end
  end

  return true, inserted
end

local function transport_icon_button(ctx, id, kind, w, h, active)
  local clicked = r.ImGui_InvisibleButton(ctx, "##" .. id, w, h)
  local hovered = r.ImGui_IsItemHovered(ctx)
  local held = r.ImGui_IsItemActive(ctx)
  local min_x, min_y = r.ImGui_GetItemRectMin(ctx)
  local max_x, max_y = r.ImGui_GetItemRectMax(ctx)
  local dl = r.ImGui_GetWindowDrawList(ctx)

  local bg = Theme.colors.frame_bg
  local border = Theme.colors.border
  if active then
    bg = Theme.colors.accent
    border = Theme.colors.accent_hover
  elseif held then
    bg = Theme.colors.frame_hover
    border = Theme.colors.accent
  elseif hovered then
    bg = Theme.colors.frame_hover
    border = Theme.colors.border
  end

  local icon_col = active and 0x0E1117FF or Theme.colors.text
  r.ImGui_DrawList_AddRectFilled(dl, min_x, min_y, max_x, max_y, bg, 5)
  r.ImGui_DrawList_AddRect(dl, min_x, min_y, max_x, max_y, border, 5, 0, 1)

  local cx = (min_x + max_x) * 0.5
  local cy = (min_y + max_y) * 0.5
  local size = math.min(w, h) * 0.45
  if kind == "play" then
    local p1x = cx - (size * 0.30)
    local p1y = cy - (size * 0.55)
    local p2x = cx - (size * 0.30)
    local p2y = cy + (size * 0.55)
    local p3x = cx + (size * 0.60)
    local p3y = cy
    r.ImGui_DrawList_AddTriangleFilled(dl, p1x, p1y, p2x, p2y, p3x, p3y, icon_col)
  elseif kind == "repeat" then
    local left_x = cx - (size * 0.42)
    local right_x = cx + (size * 0.42)
    local top_y = cy - (size * 0.22)
    local bottom_y = cy + (size * 0.22)
    local mid_top_x = cx + (size * 0.18)
    local mid_bottom_x = cx - (size * 0.18)

    r.ImGui_DrawList_AddLine(dl, left_x, top_y, mid_top_x, top_y, icon_col, 2)
    r.ImGui_DrawList_AddLine(dl, mid_top_x, top_y, mid_top_x, top_y - (size * 0.18), icon_col, 2)
    r.ImGui_DrawList_AddTriangleFilled(dl, mid_top_x, top_y - (size * 0.18), mid_top_x - (size * 0.10), top_y - (size * 0.08), mid_top_x + (size * 0.10), top_y - (size * 0.08), icon_col)

    r.ImGui_DrawList_AddLine(dl, right_x, bottom_y, mid_bottom_x, bottom_y, icon_col, 2)
    r.ImGui_DrawList_AddLine(dl, mid_bottom_x, bottom_y, mid_bottom_x, bottom_y + (size * 0.18), icon_col, 2)
    r.ImGui_DrawList_AddTriangleFilled(dl, mid_bottom_x, bottom_y + (size * 0.18), mid_bottom_x - (size * 0.10), bottom_y + (size * 0.08), mid_bottom_x + (size * 0.10), bottom_y + (size * 0.08), icon_col)
  else
    local half = size * 0.46
    r.ImGui_DrawList_AddRectFilled(dl, cx - half, cy - half, cx + half, cy + half, icon_col, 2)
  end

  return clicked
end

local function transport_text_button(ctx, id, text, w, h)
  local clicked = r.ImGui_InvisibleButton(ctx, "##" .. id, w, h)
  local hovered = r.ImGui_IsItemHovered(ctx)
  local held = r.ImGui_IsItemActive(ctx)
  local min_x, min_y = r.ImGui_GetItemRectMin(ctx)
  local max_x, max_y = r.ImGui_GetItemRectMax(ctx)
  local dl = r.ImGui_GetWindowDrawList(ctx)

  local bg = Theme.colors.frame_bg
  local border = Theme.colors.border
  if held then
    bg = Theme.colors.frame_hover
    border = Theme.colors.accent
  elseif hovered then
    bg = Theme.colors.frame_hover
    border = Theme.colors.border
  end

  r.ImGui_DrawList_AddRectFilled(dl, min_x, min_y, max_x, max_y, bg, 5)
  r.ImGui_DrawList_AddRect(dl, min_x, min_y, max_x, max_y, border, 5, 0, 1)

  local tw, th = r.ImGui_CalcTextSize(ctx, text)
  local tx = min_x + math.floor(((max_x - min_x) - tw) * 0.5)
  local ty = min_y + math.floor(((max_y - min_y) - th) * 0.5)
  r.ImGui_DrawList_AddText(dl, tx, ty, Theme.colors.text, text)

  return clicked
end

local function lane_toggle_button(ctx, id, text, w, h, active)
  local clicked = r.ImGui_InvisibleButton(ctx, "##" .. id, w, h)
  local hovered = r.ImGui_IsItemHovered(ctx)
  local held = r.ImGui_IsItemActive(ctx)
  local min_x, min_y = r.ImGui_GetItemRectMin(ctx)
  local max_x, max_y = r.ImGui_GetItemRectMax(ctx)
  local dl = r.ImGui_GetWindowDrawList(ctx)

  local bg = active and Theme.colors.accent or Theme.colors.frame_bg
  local border = active and Theme.colors.accent_hover or Theme.colors.border
  if held then
    bg = active and Theme.colors.accent_hover or Theme.colors.frame_hover
    border = Theme.colors.accent
  elseif hovered then
    bg = active and Theme.colors.accent_hover or Theme.colors.frame_hover
  end

  local text_col = active and 0x0E1117FF or Theme.colors.text
  r.ImGui_DrawList_AddRectFilled(dl, min_x, min_y, max_x, max_y, bg, 5)
  r.ImGui_DrawList_AddRect(dl, min_x, min_y, max_x, max_y, border, 5, 0, 1)

  local tw, th = r.ImGui_CalcTextSize(ctx, text)
  local tx = min_x + math.floor(((max_x - min_x) - tw) * 0.5)
  local ty = min_y + math.floor(((max_y - min_y) - th) * 0.5)
  r.ImGui_DrawList_AddText(dl, tx, ty, text_col, text)

  return clicked
end

function M.ensure_stopped(app)
  if not app or not app.sequencer then return end
  stop_playback(app.sequencer, get_selected_rack_parent_track())
end

function M.init(app)
  app.sequencer = {
    cache = {},
    cache_guid = nil,
    playing = false,
    current_guid = nil,
    last_step = nil,
    lane_clocks = {},
    started_at = 0,
    active_notes = {},
    lane_play_steps = {},
    lane_applied_step = {},
    engine_setup_id = nil,
    engine_restart_pending = false,
    solo_by_guid = {},
    lane_params_open_by_guid = {},
    pattern_library = nil,
    selected_pattern_index = 0,
    pattern_name_edit = "",
    pattern_name_target = 0,
    pattern_name_popup_open = false,
    pattern_delete_target = 0,
    pattern_delete_name = "",
    pattern_delete_popup_open = false,
    pattern_slot_by_guid = {},
    working_patterns_by_guid = {},
    step_handle_drag = {},
    pending_events = {},
    preview_note_offs = {},
    song_mode = false,
    song_playhead = nil,
    repeat_enabled = true,
    velocity_ready_by_guid = {},
    selected_lane_by_guid = {},
    lane_auto_names_by_guid = {},
    lane_clipboard = nil,
    page_clipboard = nil,
    euclid_cache = {},
    euclid_cache_guid = nil,
    euclid_library = nil,
    euclid_pattern_name_edit = "",
    euclid_pattern_name_target = 0,
    euclid_pattern_name_popup_open = false,
    euclid_pattern_delete_target = 0,
    euclid_pattern_delete_name = "",
    euclid_pattern_delete_popup_open = false,
    active_mode = nil,
    knob_drag = nil,
  }
end

local function draw_step(app)
  local ctx = app.ctx
  local state = app.sequencer
  process_preview_note_offs(state)
  local parent = get_selected_rack_parent_track()
  if not parent then
    if state.playing then
      stop_playback(state, nil)
    end
    r.ImGui_TextColored(ctx, Theme.colors.warning, "Select a kit folder track to use the sequencer.")
    return
  end

  local guid = track_guid(parent)
  if state.cache_guid ~= guid then
    state.cache_guid = guid
    state.cache[guid] = load_sequence(parent)
    if state.playing and state.current_guid ~= guid then
      stop_playback(state, parent)
    end
  end

  state.velocity_ready_by_guid = state.velocity_ready_by_guid or {}
  if not state.velocity_ready_by_guid[guid] then
    ensure_rack_velocity_response(parent)
    state.velocity_ready_by_guid[guid] = true
  end

  local seq = state.cache[guid] or new_sequence()
  state.cache[guid] = seq
  if seq.repeat_enabled == nil then
    seq.repeat_enabled = true
  end
  state.repeat_enabled = seq.repeat_enabled ~= false
  state.selected_lane_by_guid = state.selected_lane_by_guid or {}
  local selected_lane = clamp(math.floor(tonumber(state.selected_lane_by_guid[guid]) or 1), 1, GRID_SLOTS)
  state.selected_lane_by_guid[guid] = selected_lane
  state.lane_auto_names_by_guid = state.lane_auto_names_by_guid or {}
  local lane_auto_names = state.lane_auto_names_by_guid[guid]
  if type(lane_auto_names) ~= "table" then
    lane_auto_names = {}
    state.lane_auto_names_by_guid[guid] = lane_auto_names
  end
  local lane_auto_mode = seq.lane_auto_name_enabled == true
  state.solo_by_guid = state.solo_by_guid or {}
  local solo_map = state.solo_by_guid[guid] or {}
  state.solo_by_guid[guid] = solo_map
  state.lane_params_open_by_guid = state.lane_params_open_by_guid or {}
  local lane_params_open = state.lane_params_open_by_guid[guid] or {}
  state.lane_params_open_by_guid[guid] = lane_params_open
  if state.pattern_library == nil then
    state.pattern_library = load_global_patterns()
  end
  state.pattern_library = normalize_global_patterns(state.pattern_library)
  local selected_pattern_index = math.floor(tonumber(seq.selected_pattern_index) or 0)
  if #state.pattern_library == 0 then
    selected_pattern_index = 0
  else
    selected_pattern_index = clamp(selected_pattern_index, 1, #state.pattern_library)
  end
  seq.selected_pattern_index = selected_pattern_index
  state.selected_pattern_index = selected_pattern_index
  if state.pattern_name_target ~= selected_pattern_index then
    local selected_name = selected_pattern_index > 0 and normalize_pattern_name(state.pattern_library[selected_pattern_index] and state.pattern_library[selected_pattern_index].name, selected_pattern_index) or ""
    state.pattern_name_edit = selected_name
    state.pattern_name_target = selected_pattern_index
  end
  local any_solo = false
  for _, v in pairs(solo_map) do
    if v == true then
      any_solo = true
      break
    end
  end
  local total_steps = STEPS_PER_BAR
  local host_enabled = seq.host_transport == true
  local lane_tracks = collect_lane_tracks(parent)
  local selected_track = r.GetSelectedTrack(0, 0)
  local selected_track_lane = lane_index_for_track(lane_tracks, selected_track)
  if selected_track_lane and selected_track_lane ~= selected_lane then
    selected_lane = selected_track_lane
    state.selected_lane_by_guid[guid] = selected_lane
  end
  if lane_auto_mode and not next(lane_auto_names) then
    lane_auto_names = build_lane_auto_names(lane_tracks)
    state.lane_auto_names_by_guid[guid] = lane_auto_names
  end
  state.pattern_slot_by_guid = state.pattern_slot_by_guid or {}
  local current_slot = clamp(math.floor(tonumber(state.pattern_slot_by_guid[guid]) or 1), 1, PATTERN_SLOTS)
  state.pattern_slot_by_guid[guid] = current_slot

  state.preset_rev = state.preset_rev or {}
  state.preset_rev_seen_by_guid = state.preset_rev_seen_by_guid or {}
  local preset_rev_seen = state.preset_rev_seen_by_guid[guid] or {}
  state.preset_rev_seen_by_guid[guid] = preset_rev_seen
  if selected_pattern_index > 0 then
    local global_rev = state.preset_rev[selected_pattern_index] or 0
    local seen_rev = preset_rev_seen[selected_pattern_index]
    if seen_rev == nil then
      preset_rev_seen[selected_pattern_index] = global_rev
    elseif seen_rev ~= global_rev then
      preset_rev_seen[selected_pattern_index] = global_rev
      if load_pattern_from_library(state.pattern_library or {}, selected_pattern_index, seq, current_slot) then
        save_sequence(parent, seq)
        state.cache[guid] = seq
        if state.playing and state.current_guid == guid then
          restart_playback_synced(state, guid)
        end
      end
    end
  end

  state.song_playhead = nil
  if state.playing and state.song_mode then
    local song_info = resolve_song_playhead(state, seq, total_steps)
    state.song_playhead = song_info
    if song_info and song_info.ended then
      stop_playback(state, parent)
    elseif song_info and song_info.active and song_info.page and song_info.page ~= current_slot then
      stash_working_pattern(state, guid, selected_pattern_index, current_slot, seq)
      current_slot = clamp(math.floor(tonumber(song_info.page) or current_slot), 1, PATTERN_SLOTS)
      state.pattern_slot_by_guid[guid] = current_slot
      if load_pattern_for_editing(state, guid, state.pattern_library or {}, selected_pattern_index, seq, current_slot) then
        state.cache[guid] = seq
        restart_playback_synced(state, guid)
      end
    end
  end

  if state.playing and not host_enabled and not state.song_mode and not state.repeat_enabled then
    local tempo = tonumber(r.Master_GetTempo and r.Master_GetTempo() or 120) or 120
    local step_duration = (60 / tempo) / 4
    if step_duration <= 0 then step_duration = 0.125 end
    local cycle_duration = total_steps * step_duration
    local elapsed = (r.time_precise and r.time_precise() or os.clock()) - (state.started_at or 0)
    if elapsed >= cycle_duration then
      stop_playback(state, parent)
    end
  end

  if host_enabled then
    local play_state = math.floor(tonumber((r.GetPlayState and r.GetPlayState()) or 0) or 0)
    local host_playing = (play_state & 1) == 1
    if host_playing then
      if (not state.playing) or state.current_guid ~= guid then
        start_playback(state, guid)
      end
    elseif state.playing then
      stop_playback(state, parent)
    end
  end

  local clear_w = 56
  local top_button_h = 22
  local top_group_gap = 15
  local pattern_btn_w = 26
  local pattern_btn_gap = 4
  local page_action_w = 56
  local lane_action_w = clear_w
  local top_section_h = 70
  local top_section_flags = r.ImGui_WindowFlags_NoScrollbar() | r.ImGui_WindowFlags_NoScrollWithMouse()
  local top_x = r.ImGui_GetCursorPosX(ctx)
  if r.ImGui_BeginChild(ctx, "##tk_seq_top_rows", 0, top_section_h, 1, top_section_flags) then
    local top_row_y = r.ImGui_GetCursorPosY(ctx) - 2
    local top_rows_x = top_x + 16
    local pattern_label_y = top_row_y - 5
    local pattern_buttons_y = top_row_y
    r.ImGui_SetCursorPosX(ctx, top_rows_x)
    r.ImGui_SetCursorPosY(ctx, pattern_label_y)
    r.ImGui_AlignTextToFramePadding(ctx)
    r.ImGui_Text(ctx, "Pattern")
    local pattern_label_w = select(1, r.ImGui_CalcTextSize(ctx, "Pattern")) or 0
    local top_controls_x = top_rows_x + pattern_label_w + top_group_gap
    r.ImGui_SetCursorPosX(ctx, top_controls_x)
    r.ImGui_SetCursorPosY(ctx, pattern_buttons_y)
    for slot = 1, PATTERN_SLOTS do
      if slot > 1 then
        r.ImGui_SameLine(ctx, 0, pattern_btn_gap)
      end
      local active_slot = slot == current_slot
      if lane_toggle_button(ctx, "tk_seq_pattern_slot_" .. tostring(slot), tostring(slot), pattern_btn_w, top_button_h, active_slot) then
        stash_working_pattern(state, guid, selected_pattern_index, current_slot, seq)
        current_slot = slot
        state.pattern_slot_by_guid[guid] = current_slot
        if load_pattern_for_editing(state, guid, state.pattern_library or {}, selected_pattern_index, seq, current_slot) then
          save_sequence(parent, seq)
          restart_playback_synced(state, guid)
        end
      end
    end
    r.ImGui_SameLine(ctx, 0, pattern_btn_gap)
    if transport_text_button(ctx, "tk_seq_page_copy", "Copy", page_action_w, top_button_h) then
      state.page_clipboard = {
        pattern = clone_table(seq.pattern),
        lane_settings = clone_table(seq.lane_settings),
      }
    end
    if r.ImGui_IsItemHovered(ctx) then
      r.ImGui_SetTooltip(ctx, "Copy current page")
    end
    r.ImGui_SameLine(ctx, 0, pattern_btn_gap)
    if transport_text_button(ctx, "tk_seq_page_paste", "Paste", page_action_w, top_button_h) then
      local clip = state.page_clipboard
      if clip and type(clip.pattern) == "table" and type(clip.lane_settings) == "table" then
        local pasted = sanitize_sequence({
          host_transport = seq.host_transport == true,
          pattern = clip.pattern,
          lane_settings = clip.lane_settings,
        })
        seq.pattern = clone_table(pasted.pattern)
        seq.lane_settings = clone_table(pasted.lane_settings)
        save_sequence(parent, seq)
        stash_working_pattern(state, guid, selected_pattern_index, current_slot, seq)
      end
    end
    if r.ImGui_IsItemHovered(ctx) then
      r.ImGui_SetTooltip(ctx, "Paste into current page")
    end
    r.ImGui_SameLine(ctx, 0, pattern_btn_gap)
    if transport_text_button(ctx, "tk_seq_clear", "Clear", clear_w, top_button_h) then
      for lane = 1, GRID_SLOTS do
        seq.pattern[lane] = seq.pattern[lane] or {}
        for step = 1, STEPS_PER_BAR do
          seq.pattern[lane][step] = 0
        end
      end
      save_sequence(parent, seq)
      if state.playing then
        stop_notes(state)
      end
    end

    local lane_row_y = top_row_y + top_button_h + 4
    local lane_label = string.format("Lane %02d", selected_lane)
    r.ImGui_SetCursorPosX(ctx, top_rows_x)
    r.ImGui_SetCursorPosY(ctx, lane_row_y + 4)
    r.ImGui_Text(ctx, lane_label)
    r.ImGui_SetCursorPosX(ctx, top_controls_x)
    r.ImGui_SetCursorPosY(ctx, lane_row_y)
    if transport_text_button(ctx, "tk_seq_lane_speed", lane_speed_label(seq.lane_settings[selected_lane] and seq.lane_settings[selected_lane].speed), lane_action_w, top_button_h) then
      local lane_cfg = seq.lane_settings[selected_lane] or new_sequence().lane_settings[selected_lane]
      seq.lane_settings[selected_lane] = lane_cfg
      lane_cfg.speed = next_lane_speed(lane_cfg.speed)
      ensure_lane_step_params(lane_cfg, total_steps, 100)
      save_sequence(parent, seq)
      if state.playing then
        restart_playback_synced(state, guid)
      end
    end
    if r.ImGui_IsItemHovered(ctx) then
      r.ImGui_SetTooltip(ctx, "Lane speed: 1x -> 0.5x -> 2x")
    end
    r.ImGui_SameLine(ctx, 0, pattern_btn_gap)
    if transport_text_button(ctx, "tk_seq_lane_rs5k", "RS5k", lane_action_w, top_button_h) then
      local lane_track = lane_tracks[selected_lane]
      local lane_fx = lane_track and find_rs5k_fx(lane_track) or -1
      if lane_track and lane_fx >= 0 and r.TrackFX_Show then
        r.TrackFX_Show(lane_track, lane_fx, 3)
      end
    end
    if r.ImGui_IsItemHovered(ctx) then
      r.ImGui_SetTooltip(ctx, "Open RS5k for selected lane")
    end
    r.ImGui_SameLine(ctx, 0, pattern_btn_gap)
    if transport_text_button(ctx, "tk_seq_lane_copy", "Copy", lane_action_w, top_button_h) then
      local clip_pattern = clone_table(seq.pattern and seq.pattern[selected_lane] or {})
      local clip_settings = clone_table(seq.lane_settings and seq.lane_settings[selected_lane] or {})
      state.lane_clipboard = {
        pattern = clip_pattern,
        settings = clip_settings,
      }
    end
    if r.ImGui_IsItemHovered(ctx) then
      r.ImGui_SetTooltip(ctx, "Copy selected lane")
    end
    r.ImGui_SameLine(ctx, 0, pattern_btn_gap)
    if transport_text_button(ctx, "tk_seq_lane_paste", "Paste", lane_action_w, top_button_h) then
      local clip = state.lane_clipboard
      if clip and type(clip.pattern) == "table" and type(clip.settings) == "table" then
        seq.pattern[selected_lane] = clone_table(clip.pattern)
        seq.lane_settings[selected_lane] = clone_table(clip.settings)
        ensure_lane_step_params(seq.lane_settings[selected_lane], total_steps, 100)
        save_sequence(parent, seq)
      end
    end
    if r.ImGui_IsItemHovered(ctx) then
      r.ImGui_SetTooltip(ctx, "Paste to selected lane")
    end
    r.ImGui_SameLine(ctx, 0, pattern_btn_gap)
    if transport_text_button(ctx, "tk_seq_lane_clear", "Clear", lane_action_w, top_button_h) then
      local blank_seq = new_sequence()
      seq.pattern[selected_lane] = clone_table(blank_seq.pattern[selected_lane])
      seq.lane_settings[selected_lane] = clone_table(blank_seq.lane_settings[selected_lane])
      save_sequence(parent, seq)
      if state.playing then
        stop_notes(state)
      end
    end
    if r.ImGui_IsItemHovered(ctx) then
      r.ImGui_SetTooltip(ctx, "Clear selected lane")
    end
    r.ImGui_EndChild(ctx)
  end

  local transport_h = 70
  local transport_gap = 6
  local avail_h_after_steps = select(2, r.ImGui_GetContentRegionAvail(ctx)) or 0
  local layout_top_y = r.ImGui_GetCursorPosY(ctx)
  local song_lane_h = 64
  local transport_y = layout_top_y + math.max(0, avail_h_after_steps - transport_h)
  local grid_h = math.max(140, transport_y - layout_top_y - transport_gap)
  grid_h = math.max(140, grid_h - song_lane_h - transport_gap)
  if r.ImGui_BeginChild(ctx, "##tk_seq_grid", 0, grid_h, 1) then
    local row_x = r.ImGui_GetCursorPosX(ctx)
    local label_w = 92
    local row_gap = 3
    local avail_w = select(1, r.ImGui_GetContentRegionAvail(ctx)) or 0
    local solo_w = 18
    local step_marker_w = 8
    local steps_to_solo_gap = 12
    local marker_right_padding = 5
    local lane_grid_w = math.max(120, avail_w - label_w - 2)
    local steps_area_w = math.max(80, lane_grid_w - solo_w - steps_to_solo_gap)
    local cell_h = 18
    if host_enabled or (state.playing and state.current_guid == guid) then
      engine_sync(state, seq, parent, solo_map, any_solo, total_steps, lane_tracks, host_enabled)
    end
    if state.playing and (state.engine_dead_frames or 0) > 45 then
      if not state.engine_fx_present then
        r.ImGui_TextColored(ctx, Theme.colors.warning, "Sequencer engine (JSFX) kon niet laden op de kit-track.")
      else
        r.ImGui_TextColored(ctx, Theme.colors.warning, "Sequencer engine draait niet (controleer FX-bypass op de kit-track).")
      end
    end

    for lane = 1, GRID_SLOTS do
      local row_y = r.ImGui_GetCursorPosY(ctx)
      local lane_cfg = seq.lane_settings[lane] or { mode = "gate", cycle_steps = total_steps, retrigger = true }
      seq.lane_settings[lane] = lane_cfg
      ensure_lane_step_params(lane_cfg, total_steps, 100)
      local lane_track = lane_tracks[lane]
      local lane_fx = lane_track and find_rs5k_fx(lane_track) or -1
      local rs5k_note_off = lane_fx >= 0 and rs5k_obeys_note_off(lane_track, lane_fx) or false
      local cycle_steps = clamp(math.floor(tonumber(lane_cfg.cycle_steps) or total_steps), 1, total_steps)
      local is_solo = solo_map[lane] == true
      local lane_open = lane_params_open[lane] == true
      local note_label = lane_auto_mode and lane_auto_names[lane] or string.format("%02d %s", lane, Naming.note_name(BASE_NOTE + lane - 1))
      local note_max_w = math.max(20, label_w - 4)
      note_label = truncate_to_width(ctx, note_label, note_max_w)
      r.ImGui_SetCursorPosX(ctx, row_x)
      r.ImGui_SetCursorPosY(ctx, row_y)
      r.ImGui_InvisibleButton(ctx, "##tk_seq_lane_toggle_" .. tostring(lane), label_w, cell_h)
      local left_clicked = r.ImGui_IsItemClicked(ctx, 0)
      local right_clicked = r.ImGui_IsItemClicked(ctx, 1)
      if right_clicked then
        lane_params_open[lane] = not lane_open
        lane_open = lane_params_open[lane] == true
      elseif left_clicked then
        selected_lane = lane
        state.selected_lane_by_guid[guid] = lane
        if lane_track then
          r.SetOnlyTrackSelected(lane_track)
        end
      end
      if r.ImGui_IsItemHovered(ctx) then
        r.ImGui_SetTooltip(ctx, "Left click: select lane | Right click: lane parameters")
      end
      r.ImGui_SetCursorPosX(ctx, row_x)
      r.ImGui_SetCursorPosY(ctx, row_y + 1)
      if selected_lane == lane then
        r.ImGui_TextColored(ctx, Theme.colors.accent, note_label)
      else
        r.ImGui_Text(ctx, note_label)
      end
      r.ImGui_SetCursorPosX(ctx, row_x + label_w)
      r.ImGui_SetCursorPosY(ctx, row_y)
      local step_gap = 2
      local lane_play_step = (state.playing and state.lane_play_steps) and state.lane_play_steps[lane] or nil
      local visible_start = 1
      local visible_end = STEPS_PER_BAR
      local gap_total = (STEPS_PER_BAR - 1) * step_gap
      local usable_w = math.max(STEPS_PER_BAR, steps_area_w - gap_total)
      local base_w = math.floor(usable_w / STEPS_PER_BAR)
      local remainder = usable_w - (base_w * STEPS_PER_BAR)
      local steps_x = row_x + label_w
      local filled_w = (base_w * cycle_steps) + math.min(cycle_steps, remainder) + (math.max(0, cycle_steps - 1) * step_gap)
      local marker_right_limit = steps_x + steps_area_w + steps_to_solo_gap + marker_right_padding
      local marker_center_x = steps_x + clamp(filled_w + marker_right_padding, 1, steps_area_w + steps_to_solo_gap + marker_right_padding)
      local marker_hit_w = math.max(step_marker_w + 16, 24)
      local marker_left_limit = steps_x
      if cycle_steps >= total_steps then
        marker_left_limit = steps_x + steps_area_w + 1
      end
      local marker_button_x = clamp(marker_center_x - math.floor(marker_hit_w * 0.5), marker_left_limit, marker_right_limit - marker_hit_w)
      local win_x, win_y = r.ImGui_GetWindowPos(ctx)
      local mouse_x, mouse_y = 0, 0
      if r.ImGui_GetMousePos then
        mouse_x, mouse_y = r.ImGui_GetMousePos(ctx)
      end
      local marker_min_x = win_x + marker_button_x
      local marker_max_x = marker_min_x + marker_hit_w
      local marker_min_y = win_y + row_y
      local marker_max_y = marker_min_y + cell_h
      local marker_pointer_in_zone = mouse_x >= marker_min_x and mouse_x <= marker_max_x and mouse_y >= marker_min_y and mouse_y <= marker_max_y
      r.ImGui_SetCursorPosX(ctx, marker_button_x)
      r.ImGui_SetCursorPosY(ctx, row_y)
      r.ImGui_InvisibleButton(ctx, "##tk_seq_lane_steps_handle_" .. tostring(lane), marker_hit_w, cell_h)
      local handle_hovered = r.ImGui_IsItemHovered(ctx)
      local handle_active = r.ImGui_IsItemActive(ctx)
      local marker_draw_center_x = win_x + marker_center_x
      if handle_active and r.ImGui_GetMousePos then
        local drag_mouse_x = select(1, r.ImGui_GetMousePos(ctx))
        local clamped_mouse_x = clamp(drag_mouse_x or marker_draw_center_x, win_x + steps_x, win_x + steps_x + steps_area_w)
        marker_draw_center_x = clamped_mouse_x
        local rel_x = clamp(clamped_mouse_x - (win_x + steps_x), 0, steps_area_w)
        local next_cycle = clamp(math.floor((rel_x / math.max(1, steps_area_w)) * (total_steps - 1) + 1.5), 1, total_steps)
        if next_cycle ~= cycle_steps then
          cycle_steps = next_cycle
          lane_cfg.cycle_steps = next_cycle
          save_sequence(parent, seq)
        end
      end
      r.ImGui_SetCursorPosX(ctx, steps_x)
      r.ImGui_SetCursorPosY(ctx, row_y)
      for lane_step = visible_start, visible_end do
        local lane_cell_w = base_w + (((lane_step - visible_start + 1) <= remainder) and 1 or 0)
        local on = lane_step <= cycle_steps and seq.pattern[lane] and seq.pattern[lane][lane_step] == 1
        local is_active = lane_step <= cycle_steps
        local is_play = lane_play_step == lane_step
        local lane_col = lane_color(lane)
        local base_col = is_active and (on and blend_rgb(lane_col, 0xFFFFFFFF, 0.10) or blend_rgb(Theme.colors.frame_bg, lane_col, 0.20)) or blend_rgb(Theme.colors.frame_bg, 0xFFFFFFFF, 0.02)
        local hover_col = is_active and (on and blend_rgb(lane_col, 0xFFFFFFFF, 0.28) or blend_rgb(Theme.colors.frame_hover, lane_col, 0.30)) or Theme.colors.frame_bg
        local active_col = is_active and (on and blend_rgb(lane_col, 0xFFFFFFFF, 0.38) or blend_rgb(Theme.colors.border, lane_col, 0.42)) or Theme.colors.frame_bg
        if is_play then
          if on then
            base_col = blend_rgb(base_col, 0xFFFFFFFF, 0.48)
            hover_col = blend_rgb(hover_col, 0xFFFFFFFF, 0.56)
            active_col = blend_rgb(active_col, 0xFFFFFFFF, 0.64)
          else
            base_col = blend_rgb(base_col, 0xFFFFFFFF, 0.30)
            hover_col = blend_rgb(hover_col, 0xFFFFFFFF, 0.36)
            active_col = blend_rgb(active_col, 0xFFFFFFFF, 0.42)
          end
        end
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), base_col)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), hover_col)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), active_col)
        if is_active then
          local step_pressed = r.ImGui_Button(ctx, "##tk_seq_" .. tostring(lane) .. "_" .. tostring(lane_step), lane_cell_w, cell_h)
          if step_pressed and not marker_pointer_in_zone and not handle_active then
            local next_on = on and 0 or 1
            seq.pattern[lane][lane_step] = next_on
            save_sequence(parent, seq)
            if next_on == 1 then
              trigger_step_preview(state, lane, lane_step, lane_cfg, lane_track, lane_fx, rs5k_note_off, total_steps)
            end
          end
        elseif not is_active then
          r.ImGui_Button(ctx, "##tk_seq_" .. tostring(lane) .. "_" .. tostring(lane_step), lane_cell_w, cell_h)
        end
        if is_play then
          local step_min_x, step_min_y = r.ImGui_GetItemRectMin(ctx)
          local step_max_x, step_max_y = r.ImGui_GetItemRectMax(ctx)
          local step_dl = r.ImGui_GetWindowDrawList(ctx)
          if on then
            local glow_col = blend_rgb(lane_col, 0xFFFFFFFF, 0.62)
            r.ImGui_DrawList_AddRect(step_dl, step_min_x, step_min_y, step_max_x, step_max_y, glow_col, 3, 0, 2)
            r.ImGui_DrawList_AddRect(step_dl, step_min_x + 1, step_min_y + 1, step_max_x - 1, step_max_y - 1, 0xFFFFFFFF, 3, 0, 1)
          else
            local pulse_col = blend_rgb(Theme.colors.accent, 0xFFFFFFFF, 0.30)
            r.ImGui_DrawList_AddRect(step_dl, step_min_x, step_min_y, step_max_x, step_max_y, pulse_col, 3, 0, 2)
          end
        end
        r.ImGui_PopStyleColor(ctx, 3)
        if lane_step < visible_end then
          r.ImGui_SameLine(ctx, 0, step_gap)
        end
      end
      if handle_hovered then
        r.ImGui_SetTooltip(ctx, "Stop: " .. tostring(cycle_steps) .. " steps (drag)")
      end
      local marker_draw_min_x = win_x + steps_x
      if cycle_steps >= total_steps then
        marker_draw_min_x = win_x + steps_x + steps_area_w + 1
      end
      local draw_marker_x = clamp(marker_draw_center_x - math.floor(step_marker_w * 0.5), marker_draw_min_x, (win_x + marker_right_limit) - step_marker_w)
      local hmin_x, hmin_y = draw_marker_x, win_y + row_y
      local hmax_x, hmax_y = hmin_x + step_marker_w, hmin_y + cell_h
      local hdl = r.ImGui_GetWindowDrawList(ctx)
      local handle_col = handle_active and Theme.colors.accent or (handle_hovered and Theme.colors.accent_hover or Theme.colors.border)
      r.ImGui_DrawList_AddRectFilled(hdl, hmin_x, hmin_y, hmax_x, hmax_y, handle_col, 3)
      r.ImGui_DrawList_AddLine(hdl, marker_draw_center_x, hmin_y, marker_draw_center_x, hmax_y, 0xFFFFFFFF, 2)
      if cycle_steps < total_steps then
        local step_text = tostring(cycle_steps)
        local tw, th = r.ImGui_CalcTextSize(ctx, step_text)
        local label_x = marker_draw_center_x + 6
        local right_limit = (win_x + steps_x + steps_area_w) - tw - 2
        if label_x > right_limit then
          label_x = marker_draw_center_x - tw - 6
        end
        local label_y = hmin_y + math.floor((cell_h - th) * 0.5)
        r.ImGui_DrawList_AddText(hdl, label_x, label_y, Theme.colors.text_dim, step_text)
      end

      r.ImGui_SetCursorPosX(ctx, steps_x + steps_area_w + steps_to_solo_gap)
      r.ImGui_SetCursorPosY(ctx, row_y)
      if is_solo then
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), Theme.colors.accent)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), Theme.colors.accent_hover)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), Theme.colors.accent_hover)
      else
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), Theme.colors.frame_bg)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), Theme.colors.frame_hover)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), Theme.colors.border)
      end
      if r.ImGui_Button(ctx, "##tk_seq_solo_" .. tostring(lane), solo_w, cell_h) then
        solo_map[lane] = not is_solo
        stop_notes(state)
        any_solo = false
        for _, v in pairs(solo_map) do
          if v == true then
            any_solo = true
            break
          end
        end
      end
      if r.ImGui_IsItemHovered(ctx) then
        r.ImGui_SetTooltip(ctx, "Solo")
      end
      r.ImGui_PopStyleColor(ctx, 3)
      local extra_h = 0
      if lane_open then
        local top_pad = 6
        local divider_gap = 12
        local bottom_controls_h = 22
        local slider_h = 92
        local param_y = row_y + cell_h + 1
        local pmode = lane_cfg.param_mode or "velocity"
        local mode_value = lane_cfg.mode or "gate"
        local oneshot_enabled = mode_value == "oneshot"
        if oneshot_enabled and (pmode == "gate" or pmode == "length") then
          lane_cfg.param_mode = "velocity"
          pmode = "velocity"
          save_sequence(parent, seq)
        end
        local param_label = pmode == "substeps" and "Substeps" or (pmode == "length" and "Length" or (pmode == "pitch" and "Pitch" or (pmode == "pan" and "Pan" or (pmode == "volume" and "Volume" or (pmode == "probability" and "Probability" or ((pmode == "gate" and not oneshot_enabled) and "Gate" or "Velocity"))))))

        r.ImGui_SetCursorPosX(ctx, row_x)
        r.ImGui_SetCursorPosY(ctx, param_y + top_pad)
        r.ImGui_SetNextItemWidth(ctx, label_w - 2)
        if r.ImGui_BeginCombo(ctx, "##tk_seq_param_mode_" .. tostring(lane), param_label) then
          if r.ImGui_Selectable(ctx, "Velocity##tk_seq_param_vel_" .. tostring(lane), pmode == "velocity") then
            lane_cfg.param_mode = "velocity"
            save_sequence(parent, seq)
            pmode = "velocity"
          end
          if (not oneshot_enabled) and r.ImGui_Selectable(ctx, "Gate##tk_seq_param_gate_" .. tostring(lane), pmode == "gate") then
            lane_cfg.param_mode = "gate"
            save_sequence(parent, seq)
            pmode = "gate"
          end
          if (not oneshot_enabled) and r.ImGui_Selectable(ctx, "Length##tk_seq_param_len_" .. tostring(lane), pmode == "length") then
            lane_cfg.param_mode = "length"
            save_sequence(parent, seq)
            pmode = "length"
          end
          if r.ImGui_Selectable(ctx, "Substeps##tk_seq_param_sub_" .. tostring(lane), pmode == "substeps") then
            lane_cfg.param_mode = "substeps"
            save_sequence(parent, seq)
            pmode = "substeps"
          end
          if r.ImGui_Selectable(ctx, "Pitch##tk_seq_param_pitch_" .. tostring(lane), pmode == "pitch") then
            lane_cfg.param_mode = "pitch"
            save_sequence(parent, seq)
            pmode = "pitch"
          end
          if r.ImGui_Selectable(ctx, "Pan##tk_seq_param_pan_" .. tostring(lane), pmode == "pan") then
            lane_cfg.param_mode = "pan"
            save_sequence(parent, seq)
            pmode = "pan"
          end
          if r.ImGui_Selectable(ctx, "Volume##tk_seq_param_volume_" .. tostring(lane), pmode == "volume") then
            lane_cfg.param_mode = "volume"
            save_sequence(parent, seq)
            pmode = "volume"
          end
          if r.ImGui_Selectable(ctx, "Probability##tk_seq_param_probability_" .. tostring(lane), pmode == "probability") then
            lane_cfg.param_mode = "probability"
            save_sequence(parent, seq)
            pmode = "probability"
          end
          r.ImGui_EndCombo(ctx)
        end

        r.ImGui_SetCursorPosX(ctx, row_x + label_w)
        r.ImGui_SetCursorPosY(ctx, param_y + top_pad)
        local step_gap = 2
        local visible_start = 1
        local visible_end = STEPS_PER_BAR
        local visible_count = STEPS_PER_BAR
        local gap_total = (visible_count - 1) * step_gap
        local usable_w = math.max(visible_count, steps_area_w - gap_total)
        local base_w = math.floor(usable_w / visible_count)
        local remainder = usable_w - (base_w * visible_count)

        local lane_edit_x1 = row_x
        local lane_edit_x2 = row_x + label_w + steps_area_w
        local dl = r.ImGui_GetWindowDrawList(ctx)
        local win_x, win_y = r.ImGui_GetWindowPos(ctx)
        local divider_col = blend_rgb(Theme.colors.border, 0xFFFFFFFF, 0.18)
        local top_divider_y = param_y + 2
        r.ImGui_DrawList_AddLine(dl, win_x + lane_edit_x1, win_y + top_divider_y, win_x + lane_edit_x2, win_y + top_divider_y, divider_col, 1)

        for lane_step = visible_start, visible_end do
          local lane_cell_w = base_w + (((lane_step - visible_start + 1) <= remainder) and 1 or 0)
          local current_mode = lane_cfg.param_mode or "velocity"
          local is_velocity = current_mode == "velocity"
          local is_gate = (not oneshot_enabled) and current_mode == "gate"
          local is_length = (not oneshot_enabled) and current_mode == "length"
          local is_pitch = current_mode == "pitch"
          local is_pan = current_mode == "pan"
          local is_volume = current_mode == "volume"
          local is_probability = current_mode == "probability"
          local min_v = (is_pitch and -24) or (is_pan and -100) or (is_volume and -24) or (is_probability and 0) or 1
          local max_v = is_velocity and 127 or (is_gate and 100 or (is_length and total_steps or (is_pitch and 24 or (is_pan and 100 or (is_volume and 6 or (is_probability and 100 or 8))))) )
          local now_v = table_step_value(lane_cfg.step_substeps, lane_step, 1)
          if is_velocity then
            now_v = table_step_value(lane_cfg.step_velocity, lane_step, 100)
          elseif is_gate then
            now_v = table_step_value(lane_cfg.step_gate, lane_step, 100)
          elseif is_length then
            now_v = table_step_value(lane_cfg.step_length, lane_step, 1)
          elseif is_pitch then
            now_v = table_step_value(lane_cfg.step_pitch, lane_step, 0)
          elseif is_pan then
            now_v = table_step_value(lane_cfg.step_pan, lane_step, 0)
          elseif is_volume then
            now_v = table_step_value(lane_cfg.step_volume, lane_step, 0)
          elseif is_probability then
            now_v = table_step_value(lane_cfg.step_probability, lane_step, 100)
          end
          local is_active = lane_step <= cycle_steps
          now_v = clamp(math.floor(tonumber(now_v) or min_v), min_v, max_v)
          local k = (now_v - min_v) / math.max(1, (max_v - min_v))
          local lane_col = lane_color(lane)
          local frame_col = is_active and blend_rgb(Theme.colors.frame_bg, lane_col, 0.12 + (0.26 * k)) or Theme.colors.frame_bg
          local frame_hover = is_active and blend_rgb(Theme.colors.frame_hover, lane_col, 0.20 + (0.30 * k)) or Theme.colors.frame_hover
          local grab_col = is_active and blend_rgb(Theme.colors.border, lane_col, 0.34 + (0.42 * k)) or Theme.colors.border
          local grab_active = blend_rgb(grab_col, 0xFFFFFFFF, 0.22)
          r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), frame_col)
          r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgHovered(), frame_hover)
          r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrab(), grab_col)
          r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrabActive(), grab_active)
          local changed, next_v = false, now_v
          if is_active then
            changed, next_v = r.ImGui_VSliderInt(ctx, "##tk_seq_param_" .. tostring(lane) .. "_" .. tostring(lane_step), lane_cell_w, slider_h, now_v, min_v, max_v)
          else
            r.ImGui_Dummy(ctx, lane_cell_w, slider_h)
          end
          if changed then
            next_v = clamp(math.floor(tonumber(next_v) or now_v), min_v, max_v)
            if is_velocity then
              lane_cfg.step_velocity[lane_step] = next_v
            elseif is_gate then
              lane_cfg.step_gate[lane_step] = next_v
            elseif is_length then
              lane_cfg.step_length[lane_step] = next_v
            elseif is_pitch then
              lane_cfg.step_pitch[lane_step] = next_v
            elseif is_pan then
              lane_cfg.step_pan[lane_step] = next_v
            elseif is_volume then
              lane_cfg.step_volume[lane_step] = next_v
            elseif is_probability then
              lane_cfg.step_probability[lane_step] = next_v
            else
              lane_cfg.step_substeps[lane_step] = next_v
            end
            save_sequence(parent, seq)
          end
          if r.ImGui_IsItemHovered(ctx) then
            if not is_active then
              r.ImGui_SetTooltip(ctx, "No lane step on this page")
            elseif is_velocity then
              r.ImGui_SetTooltip(ctx, "Velocity: " .. tostring(now_v) .. " | Lane step: " .. tostring(lane_step))
            elseif is_gate then
              r.ImGui_SetTooltip(ctx, "Gate: " .. tostring(now_v) .. "% | Lane step: " .. tostring(lane_step))
            elseif is_length then
              r.ImGui_SetTooltip(ctx, "Length: " .. tostring(now_v) .. " step(s) | Lane step: " .. tostring(lane_step))
            elseif is_pitch then
              local sign = now_v > 0 and "+" or ""
              r.ImGui_SetTooltip(ctx, "Pitch: " .. sign .. tostring(now_v) .. " st | Lane step: " .. tostring(lane_step))
            elseif is_pan then
              local pan_label = "C"
              if now_v < 0 then
                pan_label = tostring(math.abs(now_v)) .. "%L"
              elseif now_v > 0 then
                pan_label = tostring(math.abs(now_v)) .. "%R"
              end
              r.ImGui_SetTooltip(ctx, "Pan: " .. pan_label .. " | Lane step: " .. tostring(lane_step))
            elseif is_volume then
              local sign = now_v > 0 and "+" or ""
              r.ImGui_SetTooltip(ctx, "Volume: " .. sign .. tostring(now_v) .. " dB | Lane step: " .. tostring(lane_step))
            elseif is_probability then
              r.ImGui_SetTooltip(ctx, "Probability: " .. tostring(now_v) .. "% | Lane step: " .. tostring(lane_step))
            else
              r.ImGui_SetTooltip(ctx, "Substeps: " .. tostring(now_v) .. " | Lane step: " .. tostring(lane_step))
            end
          end
          r.ImGui_PopStyleColor(ctx, 4)
          if lane_step < visible_end then
            r.ImGui_SameLine(ctx, 0, step_gap)
          end
        end

        local btn_h = 20
        local btn_gap = 6
        local btn1_w = 78
        local btn2_w = 64
        local btn3_w = 72
        local controls_w = btn1_w + btn2_w + btn3_w + (btn_gap * 2)
        local controls_y = (param_y + top_pad) + slider_h + 4

        r.ImGui_SetCursorPosX(ctx, row_x + label_w)
        r.ImGui_SetCursorPosY(ctx, controls_y)
        if lane_toggle_button(ctx, "tk_seq_lane_oneshot_" .. tostring(lane), "One-shot", btn1_w, btn_h, oneshot_enabled) then
          oneshot_enabled = not oneshot_enabled
          lane_cfg.mode = oneshot_enabled and "oneshot" or "gate"
          if oneshot_enabled and (lane_cfg.param_mode == "gate" or lane_cfg.param_mode == "length") then
            lane_cfg.param_mode = "velocity"
          end
          save_sequence(parent, seq)
        end

        r.ImGui_SameLine(ctx, 0, btn_gap)
        local retrig_enabled = lane_cfg.retrigger ~= false
        if lane_toggle_button(ctx, "tk_seq_lane_retrig_" .. tostring(lane), "Retrig", btn2_w, btn_h, retrig_enabled) then
          lane_cfg.retrigger = not retrig_enabled
          save_sequence(parent, seq)
        end

        r.ImGui_SameLine(ctx, 0, btn_gap)
        if lane_toggle_button(ctx, "tk_seq_lane_obey_" .. tostring(lane), "Note-off", btn3_w, btn_h, rs5k_note_off) and lane_track and lane_fx >= 0 then
          local next_value = not rs5k_note_off
          set_rs5k_obey_note_off(lane_track, lane_fx, next_value)
          rs5k_note_off = next_value
        end

        local controls_bottom = controls_y + btn_h
        local bottom_divider_y = controls_bottom + 10
        r.ImGui_DrawList_AddLine(dl, win_x + lane_edit_x1, win_y + bottom_divider_y, win_x + lane_edit_x2, win_y + bottom_divider_y, divider_col, 1)

        extra_h = (bottom_divider_y - param_y) + 8
      end
      r.ImGui_SetCursorPosX(ctx, row_x)
      r.ImGui_SetCursorPosY(ctx, row_y + cell_h + row_gap + extra_h)
    end

    local auto_sep_x, auto_sep_y = r.ImGui_GetCursorScreenPos(ctx)
    local auto_sep_col = blend_rgb(Theme.colors.border, 0xFFFFFFFF, 0.18)
    local auto_dl = r.ImGui_GetWindowDrawList(ctx)
    if auto_dl then
      local auto_sep_left = auto_sep_x
      local auto_sep_right = auto_sep_x + math.max(0, avail_w - 2)
      r.ImGui_DrawList_AddLine(auto_dl, auto_sep_left, auto_sep_y - 1, auto_sep_right, auto_sep_y - 1, auto_sep_col, 1)
    end
    r.ImGui_SetCursorPosY(ctx, r.ImGui_GetCursorPosY(ctx) + 6)

    if lane_toggle_button(ctx, "tk_seq_lane_auto_name", "Auto Name", label_w, 20, lane_auto_mode) then
      lane_auto_mode = not lane_auto_mode
      seq.lane_auto_name_enabled = lane_auto_mode
      if lane_auto_mode then
        lane_auto_names = build_lane_auto_names(lane_tracks)
        state.lane_auto_names_by_guid[guid] = lane_auto_names
      end
      save_sequence(parent, seq)
    end
    if r.ImGui_IsItemHovered(ctx) then
      r.ImGui_SetTooltip(ctx, "Klik: Auto Name aan/uit")
    end
    local rack_label = "Rack: " .. track_name(parent)
    r.ImGui_SameLine(ctx, 0, 10)
    r.ImGui_TextColored(ctx, Theme.colors.text_dim, rack_label)

    r.ImGui_EndChild(ctx)
  end

  local song_flags = r.ImGui_WindowFlags_NoScrollbar() | r.ImGui_WindowFlags_NoScrollWithMouse()
  if r.ImGui_BeginChild(ctx, "##tk_seq_song", 0, song_lane_h, 1, song_flags) then
    local song_slots = seq.song_slots or {}
    local song_row_x = r.ImGui_GetCursorPosX(ctx)
    local song_row_y = r.ImGui_GetCursorPosY(ctx)
    local song_dl = r.ImGui_GetWindowDrawList(ctx)
    local song_label_w = 92
    local song_avail_w = select(1, r.ImGui_GetContentRegionAvail(ctx)) or 0
    local song_solo_w = 18
    local song_steps_to_solo_gap = 12
    local song_steps_area_w = math.max(80, song_avail_w - song_label_w - song_solo_w - song_steps_to_solo_gap - 2)
    local song_step_gap = 2
    local song_visible_count = 8
    local song_gap_total = (song_visible_count - 1) * song_step_gap
    local song_usable_w = math.max(song_visible_count, song_steps_area_w - song_gap_total)
    local song_base_w = math.floor(song_usable_w / song_visible_count)
    local song_remainder = song_usable_w - (song_base_w * song_visible_count)
    local song_steps_x = song_row_x + song_label_w
    local song_slot_h = 40
    local song_content_h = song_slot_h
    local song_row_offset_y = math.max(0, math.floor(math.max(0, song_lane_h - song_content_h) * 0.5) - 32)
    local song_cells_y = song_row_y + song_row_offset_y
    r.ImGui_SetCursorPosX(ctx, song_row_x)
    r.ImGui_SetCursorPosY(ctx, song_cells_y + 8)
    r.ImGui_TextColored(ctx, Theme.colors.accent, "Song")
    r.ImGui_SetCursorPosX(ctx, song_steps_x)
    r.ImGui_SetCursorPosY(ctx, song_cells_y)
    for song_slot = 1, 8 do
      local song_cell_w = song_base_w + (((song_slot - 1 + 1) <= song_remainder) and 1 or 0)
      local song_entry = song_slots[song_slot] or { page = 0, repeats = 1 }
      local song_page = clamp(math.floor(tonumber(song_entry.page) or 0), 0, PATTERN_SLOTS)
      local song_repeats = clamp(math.floor(tonumber(song_entry.repeats) or 1), 1, 8)
      local song_active = state.song_playhead and state.song_playhead.active and state.song_playhead.slot == song_slot
      local slot_bg = song_page > 0 and blend_rgb(Theme.colors.frame_bg, Theme.colors.accent, 0.12) or Theme.colors.frame_bg
      local slot_hover = song_page > 0 and blend_rgb(Theme.colors.frame_hover, Theme.colors.accent, 0.18) or Theme.colors.frame_hover
      local slot_border = song_page > 0 and blend_rgb(Theme.colors.border, Theme.colors.accent, 0.30) or Theme.colors.border
      if song_active then
        slot_bg = blend_rgb(Theme.colors.accent, 0xFFFFFFFF, 0.16)
        slot_hover = blend_rgb(Theme.colors.accent_hover, 0xFFFFFFFF, 0.18)
        slot_border = Theme.colors.accent_hover
      end
      r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), slot_bg)
      r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), slot_hover)
      r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), slot_border)
      r.ImGui_InvisibleButton(ctx, "##tk_seq_song_" .. tostring(song_slot), song_cell_w, song_slot_h)
      local song_clicked = r.ImGui_IsItemClicked(ctx, 0)
      local song_right_clicked = r.ImGui_IsItemClicked(ctx, 1)
      local song_hovered = r.ImGui_IsItemHovered(ctx)
      local song_min_x, song_min_y = r.ImGui_GetItemRectMin(ctx)
      local song_max_x, song_max_y = r.ImGui_GetItemRectMax(ctx)
      local song_draw = r.ImGui_GetWindowDrawList(ctx)
      r.ImGui_DrawList_AddRectFilled(song_draw, song_min_x, song_min_y, song_max_x, song_max_y, slot_bg, 5)
      r.ImGui_DrawList_AddRect(song_draw, song_min_x, song_min_y, song_max_x, song_max_y, slot_border, 5, 0, 1)
      local page_text = song_page > 0 and tostring(song_page) or "--"
      local rep_text = "x" .. tostring(song_repeats)
      local p_tw = select(1, r.ImGui_CalcTextSize(ctx, page_text)) or 0
      local r_tw = select(1, r.ImGui_CalcTextSize(ctx, rep_text)) or 0
      r.ImGui_DrawList_AddText(song_draw, song_min_x + math.floor(((song_max_x - song_min_x) - p_tw) * 0.5), song_min_y + 2, song_page > 0 and Theme.colors.text or Theme.colors.text_dim, page_text)
      r.ImGui_DrawList_AddText(song_draw, song_min_x + math.floor(((song_max_x - song_min_x) - r_tw) * 0.5), song_min_y + 18, Theme.colors.text_dim, rep_text)
      if song_clicked then
        local mouse_x, mouse_y = 0, 0
        if r.ImGui_GetMousePos then
          mouse_x, mouse_y = r.ImGui_GetMousePos(ctx)
        end
        if mouse_y <= (song_min_y + (song_slot_h * 0.5)) then
          song_page = (song_page + 1) % (PATTERN_SLOTS + 1)
          if song_page == 0 then
            song_repeats = 1
          end
        else
          song_repeats = (song_repeats % 8) + 1
        end
      elseif song_right_clicked then
        song_page = 0
        song_repeats = 1
      end
      if song_clicked or song_right_clicked then
        seq.song_slots = seq.song_slots or {}
        seq.song_slots[song_slot] = {
          page = song_page,
          repeats = song_repeats,
        }
        save_sequence(parent, seq)
      end
      if song_hovered then
        r.ImGui_SetTooltip(ctx, "Boven: page | Onder: repeats | Rechtsklik: leegmaken")
      end
      r.ImGui_PopStyleColor(ctx, 3)
      if song_slot < 8 then
        r.ImGui_SameLine(ctx, 0, song_step_gap)
      end
    end
    r.ImGui_SetCursorPosX(ctx, song_row_x)
    r.ImGui_SetCursorPosY(ctx, song_cells_y + song_slot_h + 8)
    r.ImGui_Dummy(ctx, 0, 0)
    r.ImGui_EndChild(ctx)
  end

  r.ImGui_SetCursorPosX(ctx, top_x)
  r.ImGui_SetCursorPosY(ctx, transport_y)
  local transport_flags = r.ImGui_WindowFlags_NoScrollbar() | r.ImGui_WindowFlags_NoScrollWithMouse()
  if r.ImGui_BeginChild(ctx, "##tk_seq_transport", 0, transport_h, 1, transport_flags) then
    local button_h = 24
    local button_w = 32
    local host_w = 60
    local export_w = 60
    local bar_gap = 6
    local row_gap_y = 4
    local row_start_x = r.ImGui_GetCursorPosX(ctx)
    local child_start_y = r.ImGui_GetCursorPosY(ctx)
    local preset_pad_y = 2
    local row2_h = button_h + (preset_pad_y * 2)
    local transport_content_h = button_h + row_gap_y + row2_h
    local transport_center_nudge_y = -12
    local y = child_start_y + math.floor(math.max(0, transport_h - transport_content_h) * 0.5) + transport_center_nudge_y
    local pattern_y = y + button_h + row_gap_y
    local preset_gap = 4
    local transport_gap_x = preset_gap
    local preset_w = 60
    local preset_x = row_start_x
    local preset_combo_w = 100
    local transport_reserved = (button_w * 2) + host_w + export_w + (transport_gap_x * 4)
    local slider_w = 120
    r.ImGui_SetCursorPosY(ctx, y)
    if transport_icon_button(ctx, "tk_seq_transport_play", "play", button_w, button_h, state.playing) then
      if not host_enabled and not state.playing then
        start_playback(state, guid)
      end
    end
    local play_right_clicked = r.ImGui_IsItemClicked(ctx, 1)
    if play_right_clicked then
      if not host_enabled then
        if state.playing then
          stop_playback(state, parent)
        end
        start_playback(state, guid, true)
      end
    end
    if r.ImGui_IsItemHovered(ctx) then
      if host_enabled then
        r.ImGui_SetTooltip(ctx, "Host transport active")
      else
        r.ImGui_SetTooltip(ctx, "Linksklik: pattern mode | Rechtsklik: song mode")
      end
    end

    r.ImGui_SameLine(ctx, 0, transport_gap_x)
    r.ImGui_SetCursorPosY(ctx, y)
    local repeat_enabled = seq.repeat_enabled ~= false
    if transport_icon_button(ctx, "tk_seq_transport_repeat", "repeat", button_w, button_h, repeat_enabled) then
      repeat_enabled = not repeat_enabled
      seq.repeat_enabled = repeat_enabled
      state.repeat_enabled = repeat_enabled
      save_sequence(parent, seq)
    end
    if r.ImGui_IsItemHovered(ctx) then
      r.ImGui_SetTooltip(ctx, repeat_enabled and "Repeat on" or "Repeat off")
    end

    r.ImGui_SameLine(ctx, 0, transport_gap_x)
    r.ImGui_SetCursorPosY(ctx, y)
    if transport_icon_button(ctx, "tk_seq_transport_stop", "stop", button_w, button_h, false) then
      if not host_enabled then
        if state.playing then
          stop_playback(state, parent)
        else
          stop_notes(state)
          local lane_tracks = collect_lane_tracks(parent)
          for lane = 1, #lane_tracks do
            local lane_track = lane_tracks[lane]
            local lane_fx = lane_track and find_rs5k_fx(lane_track) or -1
            if lane_track and lane_fx >= 0 then
              set_rs5k_pitch_semitones(lane_track, lane_fx, 0)
              set_rs5k_pan_percent(lane_track, lane_fx, 0)
              set_rs5k_volume_db(lane_track, lane_fx, 0)
            end
          end
        end
      end
    end
    if r.ImGui_IsItemHovered(ctx) then
      if host_enabled then
        r.ImGui_SetTooltip(ctx, "Host transport active")
      else
        r.ImGui_SetTooltip(ctx, "Stop")
      end
    end

    r.ImGui_SameLine(ctx, 0, transport_gap_x)
    r.ImGui_SetCursorPosY(ctx, y)
    local rack_vol = tonumber(r.GetMediaTrackInfo_Value(parent, "D_VOL") or 1) or 1
    local rack_db = clamp(linear_to_db(rack_vol), -60, 12)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FramePadding(), 8, 2)
    r.ImGui_SetNextItemWidth(ctx, slider_w)
    local vol_changed, next_db = r.ImGui_SliderDouble(ctx, "##tk_seq_rack_volume", rack_db, -60, 12, "Rack %.1f dB")
    r.ImGui_PopStyleVar(ctx, 1)
    if vol_changed then
      r.SetMediaTrackInfo_Value(parent, "D_VOL", db_to_linear(next_db))
    end
    if r.ImGui_IsItemHovered(ctx) then
      r.ImGui_SetTooltip(ctx, "Rack master volume")
    end

    r.ImGui_SameLine(ctx, 0, transport_gap_x)
    r.ImGui_SetCursorPosY(ctx, y)
    if lane_toggle_button(ctx, "tk_seq_host", "Host", host_w, button_h, host_enabled) then
      host_enabled = not host_enabled
      seq.host_transport = host_enabled
      save_sequence(parent, seq)
      if host_enabled then
        local play_state = math.floor(tonumber((r.GetPlayState and r.GetPlayState()) or 0) or 0)
        if (play_state & 1) ~= 1 and state.playing then
          stop_playback(state, parent)
        end
      end
    end
    if r.ImGui_IsItemHovered(ctx) then
      r.ImGui_SetTooltip(ctx, "Playback follows host transport")
    end

    r.ImGui_SameLine(ctx, 0, transport_gap_x)
    r.ImGui_SetCursorPosY(ctx, y)
    local function run_export(song_mode)
      stash_working_pattern(state, guid, selected_pattern_index, current_slot, seq)
      r.Undo_BeginBlock()
      r.PreventUIRefresh(1)
      local ok = select(1, export_sequence_to_midi(parent, seq, {
        song_mode = song_mode == true,
        state = state,
        guid = guid,
        patterns = state.pattern_library,
        selected_pattern_index = selected_pattern_index,
        current_slot = current_slot,
      }))
      r.PreventUIRefresh(-1)
      r.UpdateArrange()
      if ok then
        if song_mode then
          r.Undo_EndBlock("TK Kit Maker: Export sequencer song to lane tracks", -1)
        else
          r.Undo_EndBlock("TK Kit Maker: Export sequencer pattern to lane tracks", -1)
        end
      else
        if song_mode then
          r.Undo_EndBlock("TK Kit Maker: Export sequencer song to lane tracks (failed)", -1)
        else
          r.Undo_EndBlock("TK Kit Maker: Export sequencer pattern to lane tracks (failed)", -1)
        end
      end
    end
    if transport_text_button(ctx, "tk_seq_export", "Export", export_w, button_h) then
      run_export(false)
    end
    if r.ImGui_IsItemClicked(ctx, 1) then
      run_export(true)
    end
    if r.ImGui_IsItemHovered(ctx) then
      r.ImGui_SetTooltip(ctx, "Linksklik: pattern export | Rechtsklik: song export")
    end

    local patterns = state.pattern_library or {}
    local preset_label = selected_pattern_index > 0 and normalize_pattern_name(patterns[selected_pattern_index] and patterns[selected_pattern_index].name, selected_pattern_index) or "No preset"
    r.ImGui_SetCursorPosX(ctx, preset_x)
    r.ImGui_SetCursorPosY(ctx, pattern_y)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FramePadding(), 8, preset_pad_y)
    r.ImGui_SetNextItemWidth(ctx, preset_combo_w)
    if r.ImGui_BeginCombo(ctx, "##tk_seq_preset_slot", preset_label) then
      if #patterns == 0 then
        r.ImGui_Selectable(ctx, "(no presets)", false)
      end
      for i = 1, #patterns do
        local n = normalize_pattern_name(patterns[i] and patterns[i].name, i)
        if r.ImGui_Selectable(ctx, n .. "##tk_seq_preset_slot_" .. tostring(i), selected_pattern_index == i) then
          stash_working_pattern(state, guid, selected_pattern_index, current_slot, seq)
          selected_pattern_index = i
          seq.selected_pattern_index = i
          state.selected_pattern_index = i
          clear_working_preset(state, guid, i)
          if load_pattern_from_library(patterns, i, seq, current_slot) then
            save_sequence(parent, seq)
            restart_playback_synced(state, guid)
          end
        end
      end
      r.ImGui_EndCombo(ctx)
    end
    r.ImGui_PopStyleVar(ctx, 1)

    r.ImGui_SameLine(ctx, 0, preset_gap)
    if transport_text_button(ctx, "tk_seq_pattern_save", "Save", preset_w, button_h) then
      local updated, saved_idx = save_pattern_to_library(patterns, selected_pattern_index, seq, false, current_slot, state, guid)
      state.pattern_library = updated
      seq.selected_pattern_index = saved_idx
      state.selected_pattern_index = saved_idx
      clear_working_preset_everywhere(state, saved_idx)
      state.preset_rev = state.preset_rev or {}
      state.preset_rev[saved_idx] = (state.preset_rev[saved_idx] or 0) + 1
      state.preset_rev_seen_by_guid = state.preset_rev_seen_by_guid or {}
      state.preset_rev_seen_by_guid[guid] = state.preset_rev_seen_by_guid[guid] or {}
      state.preset_rev_seen_by_guid[guid][saved_idx] = state.preset_rev[saved_idx]
      save_sequence(parent, seq)
      save_global_patterns(updated)
    end
    if r.ImGui_IsItemHovered(ctx) then
      r.ImGui_SetTooltip(ctx, "Save alle pattern pages naar de geselecteerde preset")
    end

    r.ImGui_SameLine(ctx, 0, preset_gap)
    if transport_text_button(ctx, "tk_seq_pattern_new", "New", preset_w, button_h) then
      stash_working_pattern(state, guid, selected_pattern_index, current_slot, seq)
      local updated = normalize_global_patterns(state.pattern_library)
      local new_idx = next_preset_number(updated)
      updated[new_idx] = {
        name = "Preset " .. tostring(new_idx),
        patterns = {},
      }
      for slot = 1, PATTERN_SLOTS do
        updated[new_idx].patterns[slot] = blank_pattern_snapshot()
      end
      state.pattern_library = updated
      seq.selected_pattern_index = new_idx
      state.selected_pattern_index = new_idx
      state.pattern_slot_by_guid[guid] = 1
      current_slot = 1
      if load_pattern_from_library(updated, new_idx, seq, current_slot) then
        save_sequence(parent, seq)
      end
      save_global_patterns(updated)
    end
    if r.ImGui_IsItemHovered(ctx) then
      r.ImGui_SetTooltip(ctx, "Create a new blank preset")
    end

    r.ImGui_SameLine(ctx, 0, preset_gap)
    if transport_text_button(ctx, "tk_seq_pattern_rename", "Rename", preset_w, button_h) then
      if selected_pattern_index > 0 and patterns[selected_pattern_index] then
        state.pattern_name_edit = normalize_pattern_name(patterns[selected_pattern_index].name, selected_pattern_index)
        state.pattern_name_target = selected_pattern_index
        state.pattern_name_popup_open = true
      end
    end
    if r.ImGui_IsItemHovered(ctx) then
      r.ImGui_SetTooltip(ctx, "Rename selected preset")
    end

    r.ImGui_SameLine(ctx, 0, preset_gap)
    if transport_text_button(ctx, "tk_seq_pattern_delete", "Delete", preset_w, button_h) then
      if selected_pattern_index > 0 and patterns[selected_pattern_index] then
        state.pattern_delete_target = selected_pattern_index
        state.pattern_delete_name = normalize_pattern_name(patterns[selected_pattern_index].name, selected_pattern_index)
        state.pattern_delete_popup_open = true
      end
    end
    if r.ImGui_IsItemHovered(ctx) then
      r.ImGui_SetTooltip(ctx, "Delete selected preset")
    end

    if state.pattern_name_popup_open then
      r.ImGui_OpenPopup(ctx, "Rename preset##tk_seq_pattern_name_popup")
      state.pattern_name_popup_open = false
    end
    if r.ImGui_BeginPopupModal(ctx, "Rename preset##tk_seq_pattern_name_popup", true, r.ImGui_WindowFlags_AlwaysAutoResize()) then
      r.ImGui_SetNextItemWidth(ctx, 240)
      local name_changed, next_name = r.ImGui_InputText(ctx, "Name##tk_seq_pattern_name_input", state.pattern_name_edit or "")
      if name_changed then
        state.pattern_name_edit = next_name
      end
      if r.ImGui_Button(ctx, "Cancel##tk_seq_pattern_name_cancel", 90, 0) then
        r.ImGui_CloseCurrentPopup(ctx)
      end
      r.ImGui_SameLine(ctx, 0, 6)
      if r.ImGui_Button(ctx, "Apply##tk_seq_pattern_name_apply", 90, 0) then
        local idx = math.floor(tonumber(state.pattern_name_target) or 0)
        local updated = normalize_global_patterns(state.pattern_library)
        if idx >= 1 and idx <= #updated then
          updated[idx].name = normalize_pattern_name(state.pattern_name_edit, idx)
          state.pattern_library = updated
          seq.selected_pattern_index = idx
          state.selected_pattern_index = idx
          save_sequence(parent, seq)
          save_global_patterns(updated)
        end
        r.ImGui_CloseCurrentPopup(ctx)
      end
      r.ImGui_EndPopup(ctx)
    end

    if state.pattern_delete_popup_open then
      r.ImGui_OpenPopup(ctx, "Delete preset##tk_seq_pattern_delete_popup")
      state.pattern_delete_popup_open = false
    end
    if r.ImGui_BeginPopupModal(ctx, "Delete preset##tk_seq_pattern_delete_popup", true, r.ImGui_WindowFlags_AlwaysAutoResize()) then
      local delete_name = tostring(state.pattern_delete_name or "")
      if delete_name == "" then
        delete_name = "this preset"
      end
      r.ImGui_Text(ctx, "Delete preset: " .. delete_name .. "?")
      if r.ImGui_Button(ctx, "Cancel##tk_seq_pattern_delete_cancel", 90, 0) then
        r.ImGui_CloseCurrentPopup(ctx)
      end
      r.ImGui_SameLine(ctx, 0, 6)
      if r.ImGui_Button(ctx, "Delete##tk_seq_pattern_delete_apply", 90, 0) then
        local idx = math.floor(tonumber(state.pattern_delete_target) or 0)
        local updated = normalize_global_patterns(state.pattern_library)
        if idx >= 1 and idx <= #updated then
          table.remove(updated, idx)
          state.pattern_library = updated
          if #updated == 0 then
            seq.selected_pattern_index = 0
            state.selected_pattern_index = 0
            state.pattern_name_edit = ""
            state.pattern_name_target = 0
          else
            local next_idx = clamp(idx, 1, #updated)
            seq.selected_pattern_index = next_idx
            state.selected_pattern_index = next_idx
            state.pattern_name_edit = normalize_pattern_name(updated[next_idx] and updated[next_idx].name, next_idx)
            state.pattern_name_target = next_idx
          end
          save_sequence(parent, seq)
          save_global_patterns(updated)
        end
        r.ImGui_CloseCurrentPopup(ctx)
      end
      r.ImGui_EndPopup(ctx)
    end
    r.ImGui_EndChild(ctx)
  end
end

local EUCLID_EXT_KEY = "P_EXT:TK_KIT_MAKER_EUCLID"
local EUCLID_PRESET_KEY = "EUCLID_PRESETS"
local EUCLID_SPEEDS = { 0.5, 1, 2 }

local function euclid_pattern(steps, pulses, rotation)
  steps = clamp(math.floor(tonumber(steps) or STEPS_PER_BAR), 1, STEPS_PER_BAR)
  pulses = clamp(math.floor(tonumber(pulses) or 0), 0, steps)
  local pat = {}
  for i = 1, steps do pat[i] = 0 end
  if pulses > 0 then
    local bucket = steps - pulses
    for i = 1, steps do
      bucket = bucket + pulses
      if bucket >= steps then
        bucket = bucket - steps
        pat[i] = 1
      end
    end
  end
  local rot = math.floor(tonumber(rotation) or 0) % steps
  if rot ~= 0 then
    local rotated = {}
    for i = 1, steps do
      rotated[i] = pat[((i - 1 - rot) % steps) + 1]
    end
    pat = rotated
  end
  return pat, steps
end

local function euclid_new()
  local d = { host_transport = false, repeat_enabled = true, lane_auto_name_enabled = false, selected_lane = 1, selected_preset = 0, lanes = {} }
  for lane = 1, GRID_SLOTS do
    d.lanes[lane] = { steps = 16, pulses = lane == 1 and 4 or 0, rotation = 0, speed = 1, substeps = 1, pitch = 0, volume = 0 }
  end
  return d
end

local function euclid_sanitize(data)
  local out = euclid_new()
  if type(data) ~= "table" then return out end
  out.host_transport = data.host_transport == true
  out.repeat_enabled = data.repeat_enabled ~= false
  out.lane_auto_name_enabled = data.lane_auto_name_enabled == true
  out.selected_lane = clamp(math.floor(tonumber(data.selected_lane) or 1), 1, GRID_SLOTS)
  out.selected_preset = math.max(0, math.floor(tonumber(data.selected_preset) or 0))
  if type(data.lanes) == "table" then
    for lane = 1, GRID_SLOTS do
      local s = data.lanes[lane]
      if type(s) == "table" then
        local steps = clamp(math.floor(tonumber(s.steps) or 16), 1, STEPS_PER_BAR)
        out.lanes[lane] = {
          steps = steps,
          pulses = clamp(math.floor(tonumber(s.pulses) or 0), 0, steps),
          rotation = clamp(math.floor(tonumber(s.rotation) or 0), 0, steps - 1),
          speed = normalize_lane_speed(s.speed),
          substeps = clamp(math.floor(tonumber(s.substeps) or 1), 1, 8),
          pitch = clamp(math.floor(tonumber(s.pitch) or 0), -24, 24),
          volume = clamp(math.floor(tonumber(s.volume) or 0), -24, 6),
        }
      end
    end
  end
  return out
end

local function euclid_load(track)
  if not track then return euclid_new() end
  local ok, raw = r.GetSetMediaTrackInfo_String(track, EUCLID_EXT_KEY, "", false)
  if not ok or not raw or raw == "" then return euclid_new() end
  local decoded_ok, decoded = pcall(json.decode, raw)
  if not decoded_ok then return euclid_new() end
  return euclid_sanitize(decoded)
end

local function euclid_save(track, data)
  if not track then return false end
  local payload = euclid_sanitize(data)
  local ok, encoded = pcall(json.encode, payload)
  if not ok or not encoded then return false end
  r.GetSetMediaTrackInfo_String(track, EUCLID_EXT_KEY, encoded, true)
  return true
end

local function euclid_build_seq(edata)
  local seq = new_sequence()
  seq.host_transport = edata.host_transport == true
  for lane = 1, GRID_SLOTS do
    local L = edata.lanes[lane] or { steps = 16, pulses = 0, rotation = 0, speed = 1, substeps = 1, pitch = 0, volume = 0 }
    local steps = clamp(math.floor(tonumber(L.steps) or 16), 1, STEPS_PER_BAR)
    local pulses = clamp(math.floor(tonumber(L.pulses) or 0), 0, steps)
    local substeps = clamp(math.floor(tonumber(L.substeps) or 1), 1, 8)
    local pitch = clamp(math.floor(tonumber(L.pitch) or 0), -24, 24)
    local volume = clamp(math.floor(tonumber(L.volume) or 0), -24, 6)
    local pat = euclid_pattern(steps, pulses, L.rotation)
    for step = 1, STEPS_PER_BAR do
      seq.pattern[lane][step] = (step <= steps and pat[step] == 1) and 1 or 0
      seq.lane_settings[lane].step_substeps[step] = substeps
      seq.lane_settings[lane].step_pitch[step] = pitch
      seq.lane_settings[lane].step_volume[step] = volume
    end
    seq.lane_settings[lane].cycle_steps = steps
    seq.lane_settings[lane].speed = normalize_lane_speed(L.speed)
  end
  return seq
end

local function euclid_pattern_snapshot(edata)
  local clean = euclid_sanitize({ lanes = edata and edata.lanes or nil })
  return {
    lanes = clean.lanes,
  }
end

local function euclid_normalize_entry(item, idx)
  local clean = euclid_sanitize({ lanes = type(item) == "table" and item.lanes or nil })
  return {
    name = normalize_pattern_name(type(item) == "table" and item.name or nil, idx),
    lanes = clean.lanes,
  }
end

local function euclid_normalize_library(raw)
  local out = {}
  if type(raw) ~= "table" then return out end
  for _, item in ipairs(raw) do
    if type(item) == "table" then
      out[#out + 1] = euclid_normalize_entry(item, #out + 1)
    end
  end
  return out
end

local function euclid_load_library()
  if not r.GetExtState then return {} end
  local raw = r.GetExtState(GLOBAL_PATTERN_SECTION, EUCLID_PRESET_KEY)
  if not raw or raw == "" then return out end
  local ok, dec = pcall(json.decode, raw)
  if not ok or type(dec) ~= "table" then return out end
  local src = type(dec.presets) == "table" and dec.presets or dec
  return euclid_normalize_library(src)
end

local function euclid_save_library(patterns)
  if not r.SetExtState then return false end
  local payload = { presets = euclid_normalize_library(patterns) }
  local ok, encoded = pcall(json.encode, payload)
  if not ok or not encoded then return false end
  r.SetExtState(GLOBAL_PATTERN_SECTION, EUCLID_PRESET_KEY, encoded, true)
  return true
end

local function euclid_speed_index(speed)
  local s = normalize_lane_speed(speed)
  if s == 0.5 then return 1 end
  if s == 2 then return 3 end
  return 2
end

local function euclid_ring_radius(lane, outer, inner)
  if GRID_SLOTS <= 1 then return outer end
  local stepr = (outer - inner) / (GRID_SLOTS - 1)
  return outer - (lane - 1) * stepr
end

local function euclid_knob(ctx, state, id, value, vmin, vmax, size, col, fmt)
  local dl = r.ImGui_GetWindowDrawList(ctx)
  local x, y = r.ImGui_GetCursorScreenPos(ctx)
  local cx, cy = x + size * 0.5, y + size * 0.5
  local radius = size * 0.5 - 2
  r.ImGui_InvisibleButton(ctx, "##" .. id, size, size)
  local hovered = r.ImGui_IsItemHovered(ctx)
  local active = r.ImGui_IsItemActive(ctx)
  local changed, newv = false, value
  local my = select(2, r.ImGui_GetMousePos(ctx))
  if r.ImGui_IsItemActivated(ctx) then
    state.knob_drag = { id = id, y0 = my, v0 = value }
  end
  if active and state.knob_drag and state.knob_drag.id == id then
    local dy = my - state.knob_drag.y0
    local raw = state.knob_drag.v0 - dy * 0.08
    newv = clamp(math.floor(raw + 0.5), vmin, vmax)
    if newv ~= value then changed = true end
  elseif (not active) and state.knob_drag and state.knob_drag.id == id then
    state.knob_drag = nil
  end
  local a0 = math.pi * 0.75
  local a1 = math.pi * 2.25
  local t = (value - vmin) / math.max(1, (vmax - vmin))
  local av = a0 + t * (a1 - a0)
  r.ImGui_DrawList_AddCircleFilled(dl, cx, cy, radius, Theme.colors.frame_bg, 32)
  r.ImGui_DrawList_PathArcTo(dl, cx, cy, radius - 2, a0, a1, 40)
  r.ImGui_DrawList_PathStroke(dl, blend_rgb(Theme.colors.border, 0xFFFFFFFF, 0.06), 0, 3)
  if av > a0 then
    r.ImGui_DrawList_PathArcTo(dl, cx, cy, radius - 2, a0, av, 40)
    r.ImGui_DrawList_PathStroke(dl, col, 0, 3)
  end
  local ix, iy = cx + math.cos(av) * (radius - 2), cy + math.sin(av) * (radius - 2)
  r.ImGui_DrawList_AddCircleFilled(dl, ix, iy, 3, 0xFFFFFFFF, 16)
  local text = fmt and fmt(newv) or tostring(newv)
  local tw, th = r.ImGui_CalcTextSize(ctx, text)
  local tx = cx - (tw * 0.5)
  local ty = cy - (th * 0.5)
  r.ImGui_DrawList_AddText(dl, tx, ty, Theme.colors.text, text)
  return changed, newv, hovered
end

local function euclid_lane_button(ctx, id, text, w, h, active)
  local clicked = r.ImGui_InvisibleButton(ctx, "##" .. id, w, h)
  local hovered = r.ImGui_IsItemHovered(ctx)
  local held = r.ImGui_IsItemActive(ctx)
  local min_x, min_y = r.ImGui_GetItemRectMin(ctx)
  local max_x, max_y = r.ImGui_GetItemRectMax(ctx)
  local dl = r.ImGui_GetWindowDrawList(ctx)

  local bg = active and Theme.colors.accent or Theme.colors.frame_bg
  local border = active and Theme.colors.accent_hover or Theme.colors.border
  if held then
    bg = active and Theme.colors.accent_hover or Theme.colors.frame_hover
    border = Theme.colors.accent
  elseif hovered then
    bg = active and Theme.colors.accent_hover or Theme.colors.frame_hover
  end

  local text_col = active and 0x0E1117FF or Theme.colors.text
  r.ImGui_DrawList_AddRectFilled(dl, min_x, min_y, max_x, max_y, bg, 5)
  r.ImGui_DrawList_AddRect(dl, min_x, min_y, max_x, max_y, border, 5, 0, 1)

  local _, th = r.ImGui_CalcTextSize(ctx, text)
  local tx = min_x + 8
  local ty = min_y + math.floor(((max_y - min_y) - th) * 0.5)
  r.ImGui_DrawList_AddText(dl, tx, ty, text_col, text)

  return clicked
end

local function draw_euclid(app)
  local ctx = app.ctx
  local state = app.sequencer
  process_preview_note_offs(state)
  local parent = get_selected_rack_parent_track()
  if not parent then
    if state.playing then stop_playback(state, nil) end
    r.ImGui_TextColored(ctx, Theme.colors.warning, "Select a kit folder track to use the sequencer.")
    return
  end

  local guid = track_guid(parent)
  if state.euclid_cache_guid ~= guid then
    state.euclid_cache_guid = guid
    state.euclid_cache[guid] = euclid_load(parent)
    if state.playing and state.current_guid ~= guid then
      stop_playback(state, parent)
    end
  end
  local edata = state.euclid_cache[guid] or euclid_new()
  state.euclid_cache[guid] = edata
  if state.euclid_library == nil then
    state.euclid_library = euclid_load_library()
  end
  state.euclid_library = euclid_normalize_library(state.euclid_library)
  local patterns = state.euclid_library
  local selected_pattern_index = math.floor(tonumber(edata.selected_preset) or 0)
  if #patterns == 0 then
    selected_pattern_index = 0
  else
    selected_pattern_index = clamp(selected_pattern_index, 1, #patterns)
  end
  edata.selected_preset = selected_pattern_index
  if state.euclid_pattern_name_target ~= selected_pattern_index then
    local selected_name = selected_pattern_index > 0 and normalize_pattern_name(patterns[selected_pattern_index] and patterns[selected_pattern_index].name, selected_pattern_index) or ""
    state.euclid_pattern_name_edit = selected_name
    state.euclid_pattern_name_target = selected_pattern_index
  end

  local lane_tracks = collect_lane_tracks(parent)
  local selected_lane = clamp(math.floor(tonumber(edata.selected_lane) or 1), 1, GRID_SLOTS)
  edata.selected_lane = selected_lane
  local selected_track = r.GetSelectedTrack(0, 0)
  local sel_lane_track = lane_index_for_track(lane_tracks, selected_track)
  if sel_lane_track and sel_lane_track ~= selected_lane then
    selected_lane = sel_lane_track
    edata.selected_lane = selected_lane
  end
  state.solo_by_guid = state.solo_by_guid or {}
  local solo_map = state.solo_by_guid[guid] or {}
  state.solo_by_guid[guid] = solo_map
  local any_solo = false
  for _, v in pairs(solo_map) do
    if v == true then
      any_solo = true
      break
    end
  end
  state.lane_auto_names_by_guid = state.lane_auto_names_by_guid or {}
  local lane_auto_names = state.lane_auto_names_by_guid[guid]
  if type(lane_auto_names) ~= "table" then
    lane_auto_names = {}
    state.lane_auto_names_by_guid[guid] = lane_auto_names
  end
  local lane_auto_mode = true
  edata.lane_auto_name_enabled = true
  lane_auto_names = build_lane_auto_names(lane_tracks)
  state.lane_auto_names_by_guid[guid] = lane_auto_names

  local total_steps = STEPS_PER_BAR
  local host_enabled = edata.host_transport == true
  local repeat_enabled = edata.repeat_enabled ~= false

  if state.playing and not host_enabled and not repeat_enabled then
    local tempo = tonumber(r.Master_GetTempo and r.Master_GetTempo() or 120) or 120
    local step_duration = (60 / tempo) / 4
    if step_duration <= 0 then step_duration = 0.125 end
    local cycle_duration = total_steps * step_duration
    local elapsed = (r.time_precise and r.time_precise() or os.clock()) - (state.started_at or 0)
    if elapsed >= cycle_duration then
      stop_playback(state, parent)
    end
  end

  if host_enabled then
    local play_state = math.floor(tonumber((r.GetPlayState and r.GetPlayState()) or 0) or 0)
    local host_playing = (play_state & 1) == 1
    if host_playing then
      if (not state.playing) or state.current_guid ~= guid then
        start_playback(state, guid)
      end
    elseif state.playing then
      stop_playback(state, parent)
    end
  end

  local seq = euclid_build_seq(edata)
  if host_enabled or (state.playing and state.current_guid == guid) then
    engine_sync(state, seq, parent, solo_map, any_solo, total_steps, lane_tracks, host_enabled)
  end

  local avail_w, avail_h = r.ImGui_GetContentRegionAvail(ctx)
  local transport_h = 70
  local main_h = math.max(160, avail_h - transport_h - 12)
  local main_flags = r.ImGui_WindowFlags_NoScrollbar() | r.ImGui_WindowFlags_NoScrollWithMouse()

  if r.ImGui_BeginChild(ctx, "##tk_euclid_main", 0, main_h, 1, main_flags) then
    local main_x = r.ImGui_GetCursorPosX(ctx)
    local main_y = r.ImGui_GetCursorPosY(ctx)

    local inner_w = select(1, r.ImGui_GetContentRegionAvail(ctx)) or 0
    local knob_size = 42
    local knob_gap = 8
    local knob_count = 7
    local knobs_total_w = (knob_size * knob_count) + (knob_gap * (knob_count - 1))
    local frame_pad = 8
    local clear_h = 22
    local right_w = knobs_total_w + (frame_pad * 2)
    local lane_gap = 4
    local lane_panel_w = knobs_total_w
    local lane_cols = 8
    local lane_rows = 2
    local lane_cell_size = math.floor((lane_panel_w - (lane_gap * (lane_cols - 1))) / lane_cols)
    local lane_grid_content_h = (lane_cell_size * lane_rows) + (lane_gap * (lane_rows - 1))
    local lane_panel_h = lane_grid_content_h + 20
    local right_h = frame_pad + (knob_size + 14) + 3 + (knob_size + 14) + 8 + 1 + 8 + lane_panel_h + 8 + clear_h + frame_pad
    local ring_gap = 12
    local ring_bottom_padding = 24
    local stack_gap = 8
    local stack_layout = inner_w < (right_w + ring_gap + 160)
    local ring_h_limit = stack_layout and (main_h - right_h - stack_gap) or (main_h - ring_bottom_padding)
    local ring_w_limit = stack_layout and (inner_w - (frame_pad * 2)) or (inner_w - right_w - ring_gap)
    local ring_fit = math.min(ring_h_limit, ring_w_limit)
    local ring_size = stack_layout and clamp(ring_fit, 96, 2000) or math.max(160, ring_fit)
    local ring_x = stack_layout and (main_x + math.max(0, (inner_w - ring_size) * 0.5)) or main_x
    local right_x = stack_layout and (main_x + math.max(0, (inner_w - right_w) * 0.5)) or (main_x + math.max(0, inner_w - right_w))

    r.ImGui_SetCursorPosX(ctx, ring_x)
    r.ImGui_SetCursorPosY(ctx, main_y)

    local rx, ry = r.ImGui_GetCursorScreenPos(ctx)
    r.ImGui_InvisibleButton(ctx, "##tk_euclid_ring", ring_size, ring_size)
    local ring_clicked = r.ImGui_IsItemClicked(ctx, 0)
    local dl = r.ImGui_GetWindowDrawList(ctx)
    local cx, cy = rx + ring_size * 0.5, ry + ring_size * 0.5
    local outer = ring_size * 0.5 - 6
    local inner = outer * 0.16
    local is_light_theme = Theme.current == "Light"
    local ring_border_col = is_light_theme and blend_rgb(Theme.colors.border, 0x000000FF, 0.48) or blend_rgb(Theme.colors.border, 0xFFFFFFFF, 0.20)
    local dot_outline_col = is_light_theme and blend_rgb(Theme.colors.border, 0x000000FF, 0.55) or nil
    r.ImGui_DrawList_AddCircleFilled(dl, cx, cy, outer + 4, blend_rgb(Theme.colors.frame_bg, 0x000000FF, 0.25), 48)
    r.ImGui_DrawList_AddCircle(dl, cx, cy, outer + 4, ring_border_col, 64, 1.5)

    if ring_clicked then
      local mx, my = r.ImGui_GetMousePos(ctx)
      local dx, dy = mx - cx, my - cy
      local dist = math.sqrt(dx * dx + dy * dy)
      local best, bestd = nil, 1e9
      for lane = 1, GRID_SLOTS do
        local d = math.abs(dist - euclid_ring_radius(lane, outer, inner))
        if d < bestd then bestd = d; best = lane end
      end
      local ring_step = (outer - inner) / math.max(1, (GRID_SLOTS - 1))
      if best and bestd <= ring_step * 0.6 then
        selected_lane = best
        edata.selected_lane = best
        if lane_tracks[best] then r.SetOnlyTrackSelected(lane_tracks[best]) end
        euclid_save(parent, edata)
      end
    end

    for lane = 1, GRID_SLOTS do
      local L = edata.lanes[lane]
      local steps = clamp(math.floor(tonumber(L.steps) or 16), 1, STEPS_PER_BAR)
      local pulses = clamp(math.floor(tonumber(L.pulses) or 0), 0, steps)
      local pat = euclid_pattern(steps, pulses, L.rotation)
      local rr = euclid_ring_radius(lane, outer, inner)
      local is_sel = lane == selected_lane
      local lane_col = lane_color(lane)
      local play_step = (state.playing and state.lane_play_steps) and state.lane_play_steps[lane] or nil
      if is_sel then
        r.ImGui_DrawList_AddCircle(dl, cx, cy, rr, blend_rgb(lane_col, 0xFFFFFFFF, 0.15), 64, 1.5)
      end
      for i = 1, steps do
        local ang = -math.pi * 0.5 + (i - 1) / steps * math.pi * 2
        local px = cx + math.cos(ang) * rr
        local py = cy + math.sin(ang) * rr
        local on = pat[i] == 1
        local active = play_step == i
        local dot_col, dot_r
        if on then
          dot_col = is_sel and blend_rgb(lane_col, 0xFFFFFFFF, 0.10) or blend_rgb(Theme.colors.frame_bg, lane_col, 0.70)
          dot_r = is_sel and 4.5 or 3.2
        else
          dot_col = is_sel and blend_rgb(Theme.colors.border, lane_col, 0.30) or blend_rgb(Theme.colors.frame_bg, 0xFFFFFFFF, 0.06)
          dot_r = is_sel and 2.2 or 1.5
        end
        if active and on then
          r.ImGui_DrawList_AddCircleFilled(dl, px, py, dot_r + 2.5, blend_rgb(lane_col, 0xFFFFFFFF, 0.50), 16)
          dot_col = 0xFFFFFFFF
        end
        r.ImGui_DrawList_AddCircleFilled(dl, px, py, dot_r, dot_col, 16)
        if dot_outline_col then
          r.ImGui_DrawList_AddCircle(dl, px, py, dot_r + 0.15, dot_outline_col, 16, 1.0)
        end
      end
    end
    if state.playing and state.lane_play_steps then
      local L = edata.lanes[selected_lane]
      local steps = clamp(math.floor(tonumber(L.steps) or 16), 1, STEPS_PER_BAR)
      local ps = state.lane_play_steps[selected_lane]
      if ps then
        local ang = -math.pi * 0.5 + (ps - 1) / steps * math.pi * 2
        local rr = euclid_ring_radius(selected_lane, outer, inner)
        r.ImGui_DrawList_AddLine(dl, cx, cy, cx + math.cos(ang) * rr, cy + math.sin(ang) * rr, blend_rgb(Theme.colors.accent, 0xFFFFFFFF, 0.20), 1.5)
      end
    end

    local right_y
    if stack_layout then
      local right_top_min = main_y + ring_size + stack_gap
      local right_bottom_safe_pad = 30
      local right_top_bottom_aligned = main_y + math.max(0, main_h - right_h - right_bottom_safe_pad)
      right_y = math.max(right_top_min, right_top_bottom_aligned)
    else
      right_y = main_y
    end

    r.ImGui_SetCursorPosX(ctx, right_x)
    r.ImGui_SetCursorPosY(ctx, right_y)
    if r.ImGui_BeginChild(ctx, "##tk_euclid_right", right_w, right_h, 1, main_flags) then
      local L = edata.lanes[selected_lane]
      local steps = clamp(math.floor(tonumber(L.steps) or 16), 1, STEPS_PER_BAR)
      local pulses = clamp(math.floor(tonumber(L.pulses) or 0), 0, steps)
      local rotation = clamp(math.floor(tonumber(L.rotation) or 0), 0, math.max(0, steps - 1))
      local substeps = clamp(math.floor(tonumber(L.substeps) or 1), 1, 8)
      local pitch = clamp(math.floor(tonumber(L.pitch) or 0), -24, 24)
      local volume = clamp(math.floor(tonumber(L.volume) or 0), -24, 6)
      local lane_col = lane_color(selected_lane)
      local changed_any = false
      local function draw_one(id, label, val, vmin, vmax, disp)
        r.ImGui_BeginGroup(ctx)
        local start_x = r.ImGui_GetCursorPosX(ctx)
        local start_y = r.ImGui_GetCursorPosY(ctx)
        local ch, nv = euclid_knob(ctx, state, id, val, vmin, vmax, knob_size, lane_col, disp)
        local label_y = start_y + knob_size - 1
        local lw = select(1, r.ImGui_CalcTextSize(ctx, label)) or 0
        r.ImGui_SetCursorPosX(ctx, start_x + math.max(0, (knob_size - lw) * 0.5))
        r.ImGui_SetCursorPosY(ctx, label_y)
        r.ImGui_TextColored(ctx, Theme.colors.text_dim, label)
        r.ImGui_EndGroup(ctx)
        return ch, nv
      end
      local int_disp = function(v) return tostring(v) end
      local speed_disp = function(v) return tostring(EUCLID_SPEEDS[clamp(v, 1, 3)]) .. "x" end
      local sub_disp = function(v) return tostring(v) .. "x" end
      local pitch_disp = function(v)
        if v > 0 then return "+" .. tostring(v) end
        return tostring(v)
      end
      local volume_disp = function(v)
        if v > 0 then return "+" .. tostring(v) .. "dB" end
        return tostring(v) .. "dB"
      end
      local content_x = math.floor(math.max(0, (right_w - knobs_total_w) * 0.5))

      r.ImGui_SetCursorPosX(ctx, content_x)

      local cs, ns = draw_one("euclid_steps_" .. selected_lane, "Steps", steps, 1, STEPS_PER_BAR, int_disp)
      r.ImGui_SameLine(ctx, 0, knob_gap)
      local cp, np = draw_one("euclid_pulse_" .. selected_lane, "Pulse", pulses, 0, steps, int_disp)
      r.ImGui_SameLine(ctx, 0, knob_gap)
      local cr, nr = draw_one("euclid_rot_" .. selected_lane, "Rotate", rotation, 0, math.max(0, steps - 1), int_disp)
      r.ImGui_SameLine(ctx, 0, knob_gap)
      local csp, nsp = draw_one("euclid_speed_" .. selected_lane, "Speed", euclid_speed_index(L.speed), 1, 3, speed_disp)
      r.ImGui_SameLine(ctx, 0, knob_gap)
      local csub, nsub = draw_one("euclid_substeps_" .. selected_lane, "Sub", substeps, 1, 8, sub_disp)
      r.ImGui_SameLine(ctx, 0, knob_gap)
      local cpi, npi = draw_one("euclid_pitch_" .. selected_lane, "Pitch", pitch, -24, 24, pitch_disp)
      r.ImGui_SameLine(ctx, 0, knob_gap)
      local cvol, nvol = draw_one("euclid_volume_" .. selected_lane, "Vol", volume, -24, 6, volume_disp)

      r.ImGui_Dummy(ctx, 0, 0)
      r.ImGui_SetCursorPosX(ctx, content_x)
      draw_one("euclid_dummy_1_" .. selected_lane, "D1", 0, 0, 100, int_disp)
      r.ImGui_SameLine(ctx, 0, knob_gap)
      draw_one("euclid_dummy_2_" .. selected_lane, "D2", 0, 0, 100, int_disp)
      r.ImGui_SameLine(ctx, 0, knob_gap)
      draw_one("euclid_dummy_3_" .. selected_lane, "D3", 0, 0, 100, int_disp)
      r.ImGui_SameLine(ctx, 0, knob_gap)
      draw_one("euclid_dummy_4_" .. selected_lane, "D4", 0, 0, 100, int_disp)
      r.ImGui_SameLine(ctx, 0, knob_gap)
      draw_one("euclid_dummy_5_" .. selected_lane, "D5", 0, 0, 100, int_disp)
      r.ImGui_SameLine(ctx, 0, knob_gap)
      draw_one("euclid_dummy_6_" .. selected_lane, "D6", 0, 0, 100, int_disp)
      r.ImGui_SameLine(ctx, 0, knob_gap)
      draw_one("euclid_dummy_7_" .. selected_lane, "D7", 0, 0, 100, int_disp)

      if cs then
        L.steps = ns
        L.pulses = clamp(math.floor(tonumber(L.pulses) or 0), 0, ns)
        L.rotation = clamp(math.floor(tonumber(L.rotation) or 0), 0, math.max(0, ns - 1))
        changed_any = true
      end
      if cp then L.pulses = clamp(np, 0, clamp(math.floor(tonumber(L.steps) or 16), 1, STEPS_PER_BAR)); changed_any = true end
      if cr then L.rotation = clamp(nr, 0, math.max(0, clamp(math.floor(tonumber(L.steps) or 16), 1, STEPS_PER_BAR) - 1)); changed_any = true end
      if csp then L.speed = EUCLID_SPEEDS[clamp(nsp, 1, 3)]; changed_any = true end
      if csub then L.substeps = clamp(nsub, 1, 8); changed_any = true end
      if cpi then L.pitch = clamp(npi, -24, 24); changed_any = true end
      if cvol then L.volume = clamp(nvol, -24, 6); changed_any = true end

      if changed_any then
        euclid_save(parent, edata)
        if state.playing and state.current_guid == guid then
          restart_playback_synced(state, guid)
        end
      end

      r.ImGui_Spacing(ctx)
      r.ImGui_Separator(ctx)
      r.ImGui_Spacing(ctx)
      r.ImGui_SetCursorPosX(ctx, content_x)
      if r.ImGui_BeginChild(ctx, "##tk_euclid_lanegrid", lane_panel_w, lane_panel_h, 0, main_flags) then
        local cols = lane_cols
        local rows = lane_rows
        local gap = lane_gap
        local cell_size = lane_cell_size
        for lane = 1, GRID_SLOTS do
          local is_sel = lane == selected_lane
          if is_sel then
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), Theme.colors.accent)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), Theme.colors.accent_hover)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), Theme.colors.accent_hover)
          else
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), Theme.colors.frame_bg)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), Theme.colors.frame_hover)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), Theme.colors.border)
          end
          if r.ImGui_Button(ctx, string.format("%02d##tk_euclid_lane_grid_%d", lane, lane), cell_size, cell_size) then
            selected_lane = lane
            edata.selected_lane = lane
            if lane_tracks[lane] then r.SetOnlyTrackSelected(lane_tracks[lane]) end
            euclid_save(parent, edata)
          end
          if r.ImGui_IsItemHovered(ctx) then
            local lane_name = tostring(lane_auto_names[lane] or Naming.note_name(BASE_NOTE + lane - 1))
            r.ImGui_SetTooltip(ctx, lane_name)
          end
          r.ImGui_PopStyleColor(ctx, 3)
          if (lane % cols) ~= 0 then
            r.ImGui_SameLine(ctx, 0, gap)
          end
        end
        r.ImGui_Dummy(ctx, 0, math.max(0, lane_panel_h - (rows * cell_size) - ((rows - 1) * gap)))
        r.ImGui_EndChild(ctx)
      end

      local clear_w = 56
      r.ImGui_Dummy(ctx, 0, 8)
      local clear_x = content_x + math.max(0, knobs_total_w - clear_w)
      r.ImGui_SetCursorPosX(ctx, clear_x)
      if transport_text_button(ctx, "tk_euclid_clear", "Clear", clear_w, clear_h) then
        local blank = euclid_new()
        edata.lanes = blank.lanes
        edata.selected_preset = 0
        selected_pattern_index = 0
        euclid_save(parent, edata)
        if state.playing then
          stop_notes(state)
          restart_playback_synced(state, guid)
        end
      end
      if r.ImGui_IsItemHovered(ctx) then
        r.ImGui_SetTooltip(ctx, "Alle lanes leegmaken")
      end

      r.ImGui_EndChild(ctx)
    end
    r.ImGui_EndChild(ctx)
  end

  local transport_gap = 6
  local avail_h_after_main = select(2, r.ImGui_GetContentRegionAvail(ctx)) or 0
  local euclid_layout_top_y = r.ImGui_GetCursorPosY(ctx)
  local euclid_transport_y = euclid_layout_top_y + math.max(0, avail_h_after_main - transport_h)
  r.ImGui_SetCursorPosY(ctx, euclid_transport_y)

  local tflags = r.ImGui_WindowFlags_NoScrollbar() | r.ImGui_WindowFlags_NoScrollWithMouse()
  if r.ImGui_BeginChild(ctx, "##tk_euclid_transport", 0, transport_h, 1, tflags) then
    local button_h = 24
    local button_w = 32
    local host_w = 60
    local export_w = 60
    local bar_gap = transport_gap
    local row_gap_y = 4
    local row_start_x = r.ImGui_GetCursorPosX(ctx)
    local child_start_y = r.ImGui_GetCursorPosY(ctx)
    local preset_pad_y = 2
    local row2_h = button_h + (preset_pad_y * 2)
    local transport_content_h = button_h + row_gap_y + row2_h
    local transport_center_nudge_y = -12
    local y = child_start_y + math.floor(math.max(0, transport_h - transport_content_h) * 0.5) + transport_center_nudge_y
    local pattern_y = y + button_h + row_gap_y
    local preset_gap = 4
    local transport_gap_x = preset_gap
    local preset_w = 60
    local preset_x = row_start_x
    local preset_combo_w = 100
    local transport_reserved = (button_w * 2) + host_w + export_w + (transport_gap_x * 4)
    local slider_w = 120

    r.ImGui_SetCursorPosY(ctx, y)
    if transport_icon_button(ctx, "tk_euclid_play", "play", button_w, button_h, state.playing) then
      if not host_enabled and not state.playing then start_playback(state, guid) end
    end
    if r.ImGui_IsItemHovered(ctx) then
      r.ImGui_SetTooltip(ctx, host_enabled and "Host transport active" or "Play")
    end

    r.ImGui_SameLine(ctx, 0, transport_gap_x)
    r.ImGui_SetCursorPosY(ctx, y)
    if transport_icon_button(ctx, "tk_euclid_repeat", "repeat", button_w, button_h, repeat_enabled) then
      repeat_enabled = not repeat_enabled
      edata.repeat_enabled = repeat_enabled
      euclid_save(parent, edata)
    end
    if r.ImGui_IsItemHovered(ctx) then
      r.ImGui_SetTooltip(ctx, repeat_enabled and "Repeat on" or "Repeat off")
    end

    r.ImGui_SameLine(ctx, 0, transport_gap_x)
    r.ImGui_SetCursorPosY(ctx, y)
    if transport_icon_button(ctx, "tk_euclid_stop", "stop", button_w, button_h, false) then
      if not host_enabled then
        if state.playing then
          stop_playback(state, parent)
        else
          stop_notes(state)
        end
      end
    end
    if r.ImGui_IsItemHovered(ctx) then
      r.ImGui_SetTooltip(ctx, host_enabled and "Host transport active" or "Stop")
    end

    r.ImGui_SameLine(ctx, 0, transport_gap_x)
    r.ImGui_SetCursorPosY(ctx, y)
    local rack_vol = tonumber(r.GetMediaTrackInfo_Value(parent, "D_VOL") or 1) or 1
    local rack_db = clamp(linear_to_db(rack_vol), -60, 12)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FramePadding(), 8, 2)
    r.ImGui_SetNextItemWidth(ctx, slider_w)
    local vol_changed, next_db = r.ImGui_SliderDouble(ctx, "##tk_euclid_rack_volume", rack_db, -60, 12, "Rack %.1f dB")
    r.ImGui_PopStyleVar(ctx, 1)
    if vol_changed then
      r.SetMediaTrackInfo_Value(parent, "D_VOL", db_to_linear(next_db))
    end
    if r.ImGui_IsItemHovered(ctx) then
      r.ImGui_SetTooltip(ctx, "Rack master volume")
    end

    r.ImGui_SameLine(ctx, 0, transport_gap_x)
    r.ImGui_SetCursorPosY(ctx, y)
    if lane_toggle_button(ctx, "tk_euclid_host", "Host", host_w, button_h, host_enabled) then
      host_enabled = not host_enabled
      edata.host_transport = host_enabled
      euclid_save(parent, edata)
      if host_enabled then
        local ps = math.floor(tonumber((r.GetPlayState and r.GetPlayState()) or 0) or 0)
        if (ps & 1) ~= 1 and state.playing then stop_playback(state, parent) end
      end
    end
    if r.ImGui_IsItemHovered(ctx) then
      r.ImGui_SetTooltip(ctx, "Playback follows host transport")
    end

    local function run_export()
      local seq_export = euclid_build_seq(edata)
      r.Undo_BeginBlock()
      r.PreventUIRefresh(1)
      local ok = select(1, export_sequence_to_midi(parent, seq_export, {
        song_mode = false,
        state = state,
        guid = guid,
      }))
      r.PreventUIRefresh(-1)
      r.UpdateArrange()
      if ok then
        r.Undo_EndBlock("TK Kit Maker: Export Euclid pattern to lane tracks", -1)
      else
        r.Undo_EndBlock("TK Kit Maker: Export Euclid pattern to lane tracks (failed)", -1)
      end
    end

    r.ImGui_SameLine(ctx, 0, transport_gap_x)
    r.ImGui_SetCursorPosY(ctx, y)
    if transport_text_button(ctx, "tk_euclid_export", "Export", export_w, button_h) then
      run_export()
    end
    if r.ImGui_IsItemHovered(ctx) then
      r.ImGui_SetTooltip(ctx, "Export pattern to lane tracks")
    end

    local preset_label = selected_pattern_index > 0 and normalize_pattern_name(patterns[selected_pattern_index] and patterns[selected_pattern_index].name, selected_pattern_index) or "No preset"
    r.ImGui_SetCursorPosX(ctx, preset_x)
    r.ImGui_SetCursorPosY(ctx, pattern_y)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FramePadding(), 8, preset_pad_y)
    r.ImGui_SetNextItemWidth(ctx, preset_combo_w)
    if r.ImGui_BeginCombo(ctx, "##tk_euclid_preset_slot", preset_label) then
      if #patterns == 0 then
        r.ImGui_Selectable(ctx, "(no presets)", false)
      end
      for i = 1, #patterns do
        local n = normalize_pattern_name(patterns[i] and patterns[i].name, i)
        if r.ImGui_Selectable(ctx, n .. "##tk_euclid_preset_slot_" .. tostring(i), selected_pattern_index == i) then
          selected_pattern_index = i
          edata.selected_preset = i
          local clean = euclid_sanitize({ lanes = patterns[i].lanes })
          edata.lanes = clean.lanes
          euclid_save(parent, edata)
          if state.playing and state.current_guid == guid then
            restart_playback_synced(state, guid)
          end
        end
      end
      r.ImGui_EndCombo(ctx)
    end
    r.ImGui_PopStyleVar(ctx, 1)

    r.ImGui_SameLine(ctx, 0, preset_gap)
    if transport_text_button(ctx, "tk_euclid_pattern_save", "Save", preset_w, button_h) then
      local updated = euclid_normalize_library(patterns)
      local idx = selected_pattern_index
      local snap = euclid_pattern_snapshot(edata)
      if idx <= 0 then
        idx = #updated + 1
      end
      local entry_name = updated[idx] and updated[idx].name or ("Preset " .. tostring(idx))
      updated[idx] = euclid_normalize_entry({
        name = entry_name,
        lanes = snap.lanes,
      }, idx)
      state.euclid_library = updated
      selected_pattern_index = idx
      edata.selected_preset = idx
      euclid_save(parent, edata)
      euclid_save_library(updated)
    end
    if r.ImGui_IsItemHovered(ctx) then
      r.ImGui_SetTooltip(ctx, "Save current Euclid pattern to selected preset")
    end

    r.ImGui_SameLine(ctx, 0, preset_gap)
    if transport_text_button(ctx, "tk_euclid_pattern_new", "New", preset_w, button_h) then
      local updated = euclid_normalize_library(patterns)
      local new_idx = #updated + 1
      local blank = euclid_new()
      updated[new_idx] = euclid_normalize_entry({
        name = "Preset " .. tostring(new_idx),
        lanes = blank.lanes,
      }, new_idx)
      state.euclid_library = updated
      selected_pattern_index = new_idx
      edata.selected_preset = new_idx
      edata.lanes = euclid_sanitize({ lanes = updated[new_idx].lanes }).lanes
      euclid_save(parent, edata)
      euclid_save_library(updated)
      if state.playing and state.current_guid == guid then
        restart_playback_synced(state, guid)
      end
    end
    if r.ImGui_IsItemHovered(ctx) then
      r.ImGui_SetTooltip(ctx, "Create a new blank Euclid preset")
    end

    r.ImGui_SameLine(ctx, 0, preset_gap)
    if transport_text_button(ctx, "tk_euclid_pattern_rename", "Rename", preset_w, button_h) then
      if selected_pattern_index > 0 and patterns[selected_pattern_index] then
        state.euclid_pattern_name_edit = normalize_pattern_name(patterns[selected_pattern_index].name, selected_pattern_index)
        state.euclid_pattern_name_target = selected_pattern_index
        state.euclid_pattern_name_popup_open = true
      end
    end
    if r.ImGui_IsItemHovered(ctx) then
      r.ImGui_SetTooltip(ctx, "Rename selected preset")
    end

    r.ImGui_SameLine(ctx, 0, preset_gap)
    if transport_text_button(ctx, "tk_euclid_pattern_delete", "Delete", preset_w, button_h) then
      if selected_pattern_index > 0 and patterns[selected_pattern_index] then
        state.euclid_pattern_delete_target = selected_pattern_index
        state.euclid_pattern_delete_name = normalize_pattern_name(patterns[selected_pattern_index].name, selected_pattern_index)
        state.euclid_pattern_delete_popup_open = true
      end
    end
    if r.ImGui_IsItemHovered(ctx) then
      r.ImGui_SetTooltip(ctx, "Delete selected preset")
    end

    if state.euclid_pattern_name_popup_open then
      r.ImGui_OpenPopup(ctx, "Rename Euclid preset##tk_euclid_pattern_name_popup")
      state.euclid_pattern_name_popup_open = false
    end
    if r.ImGui_BeginPopupModal(ctx, "Rename Euclid preset##tk_euclid_pattern_name_popup", true, r.ImGui_WindowFlags_AlwaysAutoResize()) then
      r.ImGui_SetNextItemWidth(ctx, 240)
      local name_changed, next_name = r.ImGui_InputText(ctx, "Name##tk_euclid_pattern_name_input", state.euclid_pattern_name_edit or "")
      if name_changed then
        state.euclid_pattern_name_edit = next_name
      end
      if r.ImGui_Button(ctx, "Cancel##tk_euclid_pattern_name_cancel", 90, 0) then
        r.ImGui_CloseCurrentPopup(ctx)
      end
      r.ImGui_SameLine(ctx, 0, 6)
      if r.ImGui_Button(ctx, "Apply##tk_euclid_pattern_name_apply", 90, 0) then
        local idx = math.floor(tonumber(state.euclid_pattern_name_target) or 0)
        local updated = euclid_normalize_library(state.euclid_library)
        if idx >= 1 and idx <= #updated then
          updated[idx].name = normalize_pattern_name(state.euclid_pattern_name_edit, idx)
          state.euclid_library = updated
          selected_pattern_index = idx
          edata.selected_preset = idx
          euclid_save(parent, edata)
          euclid_save_library(updated)
        end
        r.ImGui_CloseCurrentPopup(ctx)
      end
      r.ImGui_EndPopup(ctx)
    end

    if state.euclid_pattern_delete_popup_open then
      r.ImGui_OpenPopup(ctx, "Delete Euclid preset##tk_euclid_pattern_delete_popup")
      state.euclid_pattern_delete_popup_open = false
    end
    if r.ImGui_BeginPopupModal(ctx, "Delete Euclid preset##tk_euclid_pattern_delete_popup", true, r.ImGui_WindowFlags_AlwaysAutoResize()) then
      local delete_name = tostring(state.euclid_pattern_delete_name or "")
      if delete_name == "" then
        delete_name = "this preset"
      end
      r.ImGui_Text(ctx, "Delete preset: " .. delete_name .. "?")
      if r.ImGui_Button(ctx, "Cancel##tk_euclid_pattern_delete_cancel", 90, 0) then
        r.ImGui_CloseCurrentPopup(ctx)
      end
      r.ImGui_SameLine(ctx, 0, 6)
      if r.ImGui_Button(ctx, "Delete##tk_euclid_pattern_delete_apply", 90, 0) then
        local idx = math.floor(tonumber(state.euclid_pattern_delete_target) or 0)
        local updated = euclid_normalize_library(state.euclid_library)
        if idx >= 1 and idx <= #updated then
          table.remove(updated, idx)
          state.euclid_library = updated
          if #updated == 0 then
            selected_pattern_index = 0
            edata.selected_preset = 0
            state.euclid_pattern_name_edit = ""
            state.euclid_pattern_name_target = 0
          else
            local next_idx = clamp(idx, 1, #updated)
            selected_pattern_index = next_idx
            edata.selected_preset = next_idx
            state.euclid_pattern_name_edit = normalize_pattern_name(updated[next_idx] and updated[next_idx].name, next_idx)
            state.euclid_pattern_name_target = next_idx
          end
          euclid_save(parent, edata)
          euclid_save_library(updated)
        end
        r.ImGui_CloseCurrentPopup(ctx)
      end
      r.ImGui_EndPopup(ctx)
    end
    r.ImGui_EndChild(ctx)
  end
end

function M.draw(app)
  local state = app.sequencer
  local mode = app.view == "euclid" and "euclid" or "step"
  if state.active_mode ~= mode then
    if state.active_mode ~= nil then
      stop_playback(state, get_selected_rack_parent_track())
    end
    state.active_mode = mode
  end
  if mode == "euclid" then
    draw_euclid(app)
  else
    draw_step(app)
  end
end

return M