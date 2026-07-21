local r = reaper
local EngineJSFX = require("data.seq_engine_jsfx")

local M = {}

local GMEM_NAME = "TKKitMakerSeq"
local ENGINE_ID_KEY = "P_EXT:TK_KIT_MAKER_SEQ_ENGINE_ID"
local BUS_MARKER = "P_EXT:TK_KIT_MAKER_SEQ_BUS"
local G_AUD_TARGET = 10
local G_AUD_NOTE = 11
local G_AUD_VEL = 12
local G_AUD_GATE = 13
local G_AUD_OBEY = 14
local G_AUD_TOKEN = 15
local G_AUD_CH = 19
local OWNER_PARAM_MAX = 100000000

local engine_attached = false
local engine_installed = false
local audition_token = 0

local function clamp(v, mn, mx)
  return math.max(mn, math.min(mx, v))
end

local function track_guid(track)
  if not track or not r.GetTrackGUID then return nil end
  return r.GetTrackGUID(track)
end

local function get_track_index0(track)
  return math.floor((r.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER") or 1) - 1)
end

local function midi_flags_for_lane(lane)
  return 0
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

function M.track_is_seq_bus(track)
  if not track or not r.GetSetMediaTrackInfo_String then return false end
  local ok, v = r.GetSetMediaTrackInfo_String(track, BUS_MARKER, "", false)
  return ok and v ~= nil and v ~= ""
end

function M.ensure_installed()
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
  end
  engine_installed = true
  return true
end

function M.ensure_attached()
  if engine_attached then return true end
  if not r.gmem_attach then return false end
  r.gmem_attach(GMEM_NAME)
  engine_attached = true
  return true
end

function M.engine_id_for(parent)
  if not parent then return 0 end
  local ok, val = r.GetSetMediaTrackInfo_String(parent, ENGINE_ID_KEY, "", false)
  local id = ok and math.floor(tonumber(val) or 0) or 0
  if id <= 0 then
    id = math.random(1, OWNER_PARAM_MAX)
    r.GetSetMediaTrackInfo_String(parent, ENGINE_ID_KEY, tostring(id), true)
  end
  return id
end

function M.find_engine_fx(track)
  if not track or not r.TrackFX_GetCount then return -1 end
  local function normalize_name(name)
    local lower = (name or ""):lower()
    return lower:gsub("[^a-z0-9]", "")
  end

  local count = r.TrackFX_GetCount(track)
  for i = 0, count - 1 do
    local ok, name = r.TrackFX_GetFXName(track, i, "")
    if ok and name then
      local lower = name:lower()
      if lower:find("tk kit maker sequencer", 1, true) then
        return i
      end
      local normalized = normalize_name(name)
      if normalized:find("tkkitmakersequencer", 1, true) then
        return i
      end
    end
  end
  return -1
end

function M.find_bus(parent)
  if not parent then return nil end
  local parent_depth = r.GetTrackDepth(parent)
  local parent_idx = get_track_index0(parent)
  local count = r.CountTracks(0)
  for i = parent_idx + 1, count - 1 do
    local tr = r.GetTrack(0, i)
    if r.GetTrackDepth(tr) <= parent_depth then break end
    if M.track_is_seq_bus(tr) then return tr end
  end
  return nil
end

function M.create_bus(parent)
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
  r.SetMediaTrackInfo_Value(bus, "I_RECARM", 0)
  r.SetMediaTrackInfo_Value(bus, "I_RECMON", 0)
  r.SetMediaTrackInfo_Value(bus, "I_RECMODE", 0)
  if r.SetMediaTrackInfo_Value then
    r.SetMediaTrackInfo_Value(bus, "I_MIDIHWOUT", -1)
    r.SetMediaTrackInfo_Value(bus, "B_MAINSEND", 0)
  end
  if r.TrackList_AdjustWindows then r.TrackList_AdjustWindows(false) end
  return bus
end

function M.ensure_bus_sends(bus, lane_tracks)
  if not bus or not lane_tracks or not r.GetTrackNumSends then return 0 end
  local have = {}
  local num = r.GetTrackNumSends(bus, 0)
  for i = 0, num - 1 do
    local dest = r.GetTrackSendInfo_Value(bus, 0, i, "P_DESTTRACK")
    for lane = 1, #lane_tracks do
      if lane_tracks[lane] and dest == lane_tracks[lane] then
        have[lane] = true
        r.SetTrackSendInfo_Value(bus, 0, i, "I_SRCCHAN", -1)
        r.SetTrackSendInfo_Value(bus, 0, i, "I_MIDIFLAGS", midi_flags_for_lane(lane))
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
          r.SetTrackSendInfo_Value(bus, 0, idx, "I_MIDIFLAGS", midi_flags_for_lane(lane))
          count = count + 1
        end
      else
        count = count + 1
      end
    end
  end
  return count
end

function M.set_bus_owner(track, fx, owner_id)
  if not track or fx == nil or fx < 0 or not r.TrackFX_SetParamNormalized then return false end
  local normalized = clamp((tonumber(owner_id) or 0) / OWNER_PARAM_MAX, 0, 1)
  r.TrackFX_SetParamNormalized(track, fx, 0, normalized)
  return true
end

function M.add_fx_end(track, owner_id)
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
  if fx and fx >= 0 then
    M.set_bus_owner(track, fx, owner_id)
    if r.TrackFX_Show then
      r.TrackFX_Show(track, fx, 2)
    end
  end
  return fx or -1
end

function M.ensure_bus(parent, lane_tracks, owner_id)
  if not parent then return nil, 0 end
  M.ensure_installed()
  local bus = M.find_bus(parent)
  if not bus then
    bus = M.create_bus(parent)
  end
  if not bus then return nil, 0 end
  local fx = M.find_engine_fx(bus)
  if fx < 0 then
    fx = M.add_fx_end(bus, owner_id)
  else
    M.set_bus_owner(bus, fx, owner_id)
  end
  local sends = M.ensure_bus_sends(bus, lane_tracks)
  return bus, sends
end

function M.audition_on(parent, lane_tracks, note, vel, gate_seconds, obey, target_track, fast_path)
  if not parent then return false end
  if not M.ensure_attached() then return false end
  local owner_id = M.engine_id_for(parent)
  local bus = nil
  if fast_path == true then
    bus = M.find_bus(parent)
    if bus then
      local fx = M.find_engine_fx(bus)
      if fx >= 0 then
        M.set_bus_owner(bus, fx, owner_id)
      else
        bus = nil
      end
    end
  end
  if not bus then
    bus = M.ensure_bus(parent, lane_tracks, owner_id)
  end
  if not bus or not r.gmem_write then return false end
  local lane = lane_index_for_track(lane_tracks, target_track)
  local ch = math.max(0, math.min(15, (lane and lane > 0) and (lane - 1) or 0))
  audition_token = audition_token + 1
  r.gmem_write(G_AUD_TARGET, owner_id)
  r.gmem_write(G_AUD_NOTE, clamp(math.floor(tonumber(note) or 0), 0, 127))
  r.gmem_write(G_AUD_VEL, clamp(math.floor(tonumber(vel) or 100), 1, 127))
  r.gmem_write(G_AUD_GATE, math.max(0, tonumber(gate_seconds) or 0))
  r.gmem_write(G_AUD_OBEY, obey == true and 1 or 0)
  r.gmem_write(G_AUD_TOKEN, audition_token)
  r.gmem_write(G_AUD_CH, ch)
  return true
end

function M.audition_off(parent, lane_tracks, fast_path)
  if not parent then return false end
  if not M.ensure_attached() then return false end
  local owner_id = M.engine_id_for(parent)
  local bus = nil
  if fast_path == true then
    bus = M.find_bus(parent)
    if bus then
      local fx = M.find_engine_fx(bus)
      if fx >= 0 then
        M.set_bus_owner(bus, fx, owner_id)
      else
        bus = nil
      end
    end
  end
  if not bus then
    bus = M.ensure_bus(parent, lane_tracks, owner_id)
  end
  if not bus or not r.gmem_write then return false end
  audition_token = audition_token + 1
  r.gmem_write(G_AUD_TARGET, owner_id)
  r.gmem_write(G_AUD_NOTE, 0)
  r.gmem_write(G_AUD_VEL, 0)
  r.gmem_write(G_AUD_GATE, 0)
  r.gmem_write(G_AUD_OBEY, 1)
  r.gmem_write(G_AUD_TOKEN, audition_token)
  return true
end

return M