local r = reaper
local Theme = require("core.theme")
local UIScale = require("core.ui_scale")

local M = {
  id = "send_studio",
  title = "Send Studio",
  icon = "SND",
  version = "0.1.0"
}

local defaults = {
  min_db = -60,
  max_db = 12,
  view_mode = "cards",        -- "cards" | "list"
  pinned_guid = "",
  show_sends = true,
  show_receives = true,
  default_send_mode = 0,      -- 0 = Post, 1 = Pre-FX, 3 = Pre-Fader
  meter_smoothing = 0.35
}

local state = {
  meters = {},
  drag = nil,                 -- { id = lane_id, kind = "vol" | "pan" }
  picker_open = false,
  picker_mode = nil,          -- "send" | "receive"
  picker_filter = "",
  bus_open = false,
  bus_name = "FX Bus",
  clipboard = nil             -- copied sends: list of routing snapshots
}

-- I_SENDMODE: 0 = Post-Fader (Post-Pan), 1 = Pre-FX, 3 = Post-FX (Pre-Fader)
local SEND_MODES = { 0, 1, 3 }
local SEND_MODE_LABELS = { [0] = "Post", [1] = "Pre-FX", [3] = "Pre-Fader" }

local function send_mode_label(mode)
  return SEND_MODE_LABELS[tonumber(mode) or 0] or "Post"
end

local function next_send_mode(mode)
  mode = tonumber(mode) or 0
  for index, value in ipairs(SEND_MODES) do
    if value == mode then return SEND_MODES[(index % #SEND_MODES) + 1] end
  end
  return SEND_MODES[1]
end

-- ---------------------------------------------------------------------------
-- Small utilities (mirrors Control Room conventions)
-- ---------------------------------------------------------------------------

local function clamp(value, minimum, maximum)
  value = tonumber(value) or minimum
  if value < minimum then return minimum end
  if value > maximum then return maximum end
  return value
end

local function linear_to_db(value, minimum_db)
  value = tonumber(value) or 0
  if value <= 0.000001 then return minimum_db end
  return math.max(minimum_db, math.log(value) / math.log(10) * 20)
end

local function db_to_linear(value, minimum_db, maximum_db)
  value = clamp(value, minimum_db, maximum_db)
  if value <= minimum_db then return 0 end
  return 10 ^ (value / 20)
end

local function format_db(value, settings)
  local db = linear_to_db(value, settings.min_db or defaults.min_db)
  if db <= (settings.min_db or defaults.min_db) + 0.05 then return "-inf" end
  return string.format("%+.1f dB", db)
end

local function format_pan(pan)
  pan = tonumber(pan) or 0
  if math.abs(pan) < 0.005 then return "C" end
  local pct = math.floor(math.abs(pan) * 100 + 0.5)
  return (pan < 0 and "L" or "R") .. tostring(pct)
end

local function calc_text_width(ctx, value)
  if r.ImGui_CalcTextSize then
    local width = r.ImGui_CalcTextSize(ctx, tostring(value or ""))
    return tonumber(width) or 0
  end
  return #(tostring(value or "")) * 7
end

local function ellipsize_text(ctx, value, max_width)
  value = tostring(value or "")
  if value == "" or calc_text_width(ctx, value) <= max_width then return value end
  while #value > 1 and calc_text_width(ctx, value .. "...") > max_width do value = value:sub(1, -2) end
  return value .. "..."
end

local function color_with_alpha(color, alpha)
  color = tonumber(color) or 0xFFFFFFFF
  return (color & 0xFFFFFF00) | ((tonumber(alpha) or 0xFF) & 0xFF)
end

local function valid_track(track)
  return track and r.ValidatePtr2(0, track, "MediaTrack*") == true
end

local function track_guid(track)
  if not valid_track(track) or not r.GetTrackGUID then return nil end
  local ok, guid = pcall(r.GetTrackGUID, track)
  return ok and guid and guid ~= "" and guid or nil
end

local function track_by_guid(guid)
  if not guid or guid == "" or not r.CountTracks or not r.GetTrackGUID then return nil end
  for index = 0, (r.CountTracks(0) or 0) - 1 do
    local track = r.GetTrack(0, index)
    if valid_track(track) and track_guid(track) == guid then return track end
  end
  return nil
end

local function track_name(track)
  if not valid_track(track) then return "Track" end
  local ok, name = r.GetTrackName(track)
  if ok and name and name ~= "" then return name end
  local number = math.floor(tonumber(r.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER")) or 0)
  return "Track " .. tostring(number)
end

local function track_index_label(track)
  if not valid_track(track) then return "" end
  local number = math.floor(tonumber(r.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER")) or 0)
  if number <= 0 then return "" end
  return tostring(number)
end

local function native_color_to_u32(native, alpha)
  native = tonumber(native) or 0
  if native == 0 then return nil end
  alpha = alpha or 0xFF
  if r.ColorFromNative then
    local ok, red, green, blue = pcall(r.ColorFromNative, native & 0xFFFFFF)
    if ok and red and green and blue then return ((red & 0xFF) << 24) | ((green & 0xFF) << 16) | ((blue & 0xFF) << 8) | (alpha & 0xFF) end
  end
  local red = native & 0xFF
  local green = (native >> 8) & 0xFF
  local blue = (native >> 16) & 0xFF
  return (red << 24) | (green << 16) | (blue << 8) | (alpha & 0xFF)
end

local function track_color(track)
  if not valid_track(track) or not r.GetTrackColor then return nil end
  return native_color_to_u32(r.GetTrackColor(track), 0xFF)
end

local function write_with_undo(label, callback)
  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)
  local ok, result = pcall(callback)
  r.PreventUIRefresh(-1)
  r.UpdateArrange()
  r.Undo_EndBlock(label, -1)
  return ok and result ~= false
end

local function read_track_peak(track)
  if not valid_track(track) or not r.Track_GetPeakInfo then return 0 end
  local left_ok, left_peak = pcall(r.Track_GetPeakInfo, track, 0)
  local right_ok, right_peak = pcall(r.Track_GetPeakInfo, track, 1)
  left_peak = left_ok and tonumber(left_peak) or 0
  right_peak = right_ok and tonumber(right_peak) or 0
  return math.max(math.abs(left_peak or 0), math.abs(right_peak or 0))
end

local function smoothed_meter(id, raw_value, settings)
  local previous = state.meters[id] or 0
  local smoothing = clamp(settings.meter_smoothing or defaults.meter_smoothing, 0.05, 0.95)
  local next_value = raw_value > previous and raw_value or previous + (raw_value - previous) * smoothing
  if next_value < 0.0001 then next_value = 0 end
  state.meters[id] = next_value
  return next_value
end

local function meter_color(value)
  if value >= 0.98 then return Theme.colors.danger end
  if value >= 0.75 then return Theme.colors.warning end
  return Theme.colors.accent
end

local function mouse_wheel_delta(ctx)
  if not r.ImGui_GetMouseWheel then return 0 end
  local ok, value = pcall(r.ImGui_GetMouseWheel, ctx)
  return ok and tonumber(value) or 0
end

local function shift_key_down(ctx)
  if r.ImGui_IsKeyDown and r.ImGui_Key_LeftShift and r.ImGui_Key_RightShift then
    return r.ImGui_IsKeyDown(ctx, r.ImGui_Key_LeftShift()) or r.ImGui_IsKeyDown(ctx, r.ImGui_Key_RightShift())
  end
  return false
end

-- ---------------------------------------------------------------------------
-- Settings
-- ---------------------------------------------------------------------------

local function ensure_settings(app)
  app.settings.send_studio = app.settings.send_studio or {}
  local settings = app.settings.send_studio
  local changed = false
  for key, value in pairs(defaults) do
    if settings[key] == nil then
      settings[key] = value
      changed = true
    end
  end
  settings.min_db = tonumber(settings.min_db) or defaults.min_db
  settings.max_db = tonumber(settings.max_db) or defaults.max_db
  if settings.max_db <= settings.min_db then settings.max_db = settings.min_db + 12 end
  if changed and app.save_settings then app.save_settings() end
  return settings
end

-- ---------------------------------------------------------------------------
-- Target track (selection + pin)
-- ---------------------------------------------------------------------------

local function selected_track(app)
  local track = app.selection and app.selection.track and app.selection.track.pointer
  if valid_track(track) then return track end
  track = r.GetSelectedTrack(0, 0)
  if valid_track(track) then return track end
  return nil
end

local function target_track(app, settings)
  local guid = settings.pinned_guid
  if guid and guid ~= "" then
    local track = track_by_guid(guid)
    if valid_track(track) then return track, true end
    settings.pinned_guid = ""
    if app.save_settings then app.save_settings() end
  end
  return selected_track(app), false
end

local function set_pin(app, settings, track)
  local guid = track and track_guid(track) or nil
  settings.pinned_guid = guid or ""
  if app.save_settings then app.save_settings() end
end

-- ---------------------------------------------------------------------------
-- Send / receive read + write helpers
-- ---------------------------------------------------------------------------

local function send_value(track, category, index, param)
  if not valid_track(track) or not index or not r.GetTrackSendInfo_Value then return nil end
  local ok, value = pcall(r.GetTrackSendInfo_Value, track, category, index, param)
  if ok and type(value) == "number" then return value end
  return nil
end

local function send_other_track(track, category, index)
  local param = category == -1 and "P_SRCTRACK" or "P_DESTTRACK"
  if not valid_track(track) or not r.GetTrackSendInfo_Value then return nil end
  local ok, other = pcall(r.GetTrackSendInfo_Value, track, category, index, param)
  if ok and valid_track(other) then return other end
  return nil
end

local function write_send_volume(track, category, index, value)
  if not valid_track(track) or not r.SetTrackSendInfo_Value then return false end
  value = clamp(value, 0, 4)
  return write_with_undo("Send Studio: Volume", function()
    return r.SetTrackSendInfo_Value(track, category, index, "D_VOL", value)
  end)
end

local function write_send_pan(track, category, index, value)
  if not valid_track(track) or not r.SetTrackSendInfo_Value then return false end
  value = clamp(value, -1, 1)
  return write_with_undo("Send Studio: Pan", function()
    return r.SetTrackSendInfo_Value(track, category, index, "D_PAN", value)
  end)
end

local function write_send_mute(track, category, index, muted)
  if not valid_track(track) or not r.SetTrackSendInfo_Value then return false end
  return write_with_undo("Send Studio: Mute", function()
    return r.SetTrackSendInfo_Value(track, category, index, "B_MUTE", muted and 1 or 0)
  end)
end

local function write_send_mode(track, category, index, mode)
  if not valid_track(track) or not r.SetTrackSendInfo_Value then return false end
  return write_with_undo("Send Studio: Send mode", function()
    return r.SetTrackSendInfo_Value(track, category, index, "I_SENDMODE", tonumber(mode) or 0)
  end)
end

local function write_send_phase(track, category, index, inverted)
  if not valid_track(track) or not r.SetTrackSendInfo_Value then return false end
  return write_with_undo("Send Studio: Phase", function()
    return r.SetTrackSendInfo_Value(track, category, index, "B_PHASE", inverted and 1 or 0)
  end)
end

local function write_send_mono(track, category, index, mono)
  if not valid_track(track) or not r.SetTrackSendInfo_Value then return false end
  return write_with_undo("Send Studio: Mono", function()
    return r.SetTrackSendInfo_Value(track, category, index, "B_MONO", mono and 1 or 0)
  end)
end

-- Audio channel routing (I_SRCCHAN / I_DSTCHAN). Encoding: channel index in the
-- low bits, bit 1024 = mono, -1 (source only) = MIDI / no audio.
local function chan_parse(raw)
  raw = math.floor(tonumber(raw) or 0)
  if raw < 0 then return { none = true } end
  return { channel = raw & 0x1FF, mono = (raw & 1024) ~= 0 }
end

local function chan_label(raw)
  local parsed = chan_parse(raw)
  if parsed.none then return "MIDI" end
  if parsed.mono then return tostring(parsed.channel + 1) end
  return tostring(parsed.channel + 1) .. "/" .. tostring(parsed.channel + 2)
end

local function track_channel_count(track)
  if not valid_track(track) or not r.GetMediaTrackInfo_Value then return 2 end
  local ok, value = pcall(r.GetMediaTrackInfo_Value, track, "I_NCHAN")
  return ok and math.max(2, math.floor(tonumber(value) or 2)) or 2
end

local function channel_options(track, include_midi)
  local options = {}
  if include_midi then options[#options + 1] = { value = -1, label = "MIDI (no audio)" } end
  local count = track_channel_count(track)
  for channel = 0, count - 2, 2 do
    options[#options + 1] = { value = channel, label = tostring(channel + 1) .. "/" .. tostring(channel + 2) }
  end
  for channel = 0, count - 1 do
    options[#options + 1] = { value = channel | 1024, label = "Mono " .. tostring(channel + 1) }
  end
  return options
end

local function write_send_srcchan(track, category, index, value)
  if not valid_track(track) or not r.SetTrackSendInfo_Value then return false end
  return write_with_undo("Send Studio: Source channel", function()
    return r.SetTrackSendInfo_Value(track, category, index, "I_SRCCHAN", math.floor(tonumber(value) or 0))
  end)
end

local function write_send_dstchan(track, category, index, value)
  if not valid_track(track) or not r.SetTrackSendInfo_Value then return false end
  return write_with_undo("Send Studio: Destination channel", function()
    return r.SetTrackSendInfo_Value(track, category, index, "I_DSTCHAN", math.floor(tonumber(value) or 0))
  end)
end

local function remove_send(track, category, index)
  if not valid_track(track) or not r.RemoveTrackSend then return false end
  return write_with_undo("Send Studio: Remove", function()
    return r.RemoveTrackSend(track, category, index)
  end)
end

local function select_track(track)
  if valid_track(track) and r.SetOnlyTrackSelected then
    r.SetOnlyTrackSelected(track)
    if r.TrackList_AdjustWindows then r.TrackList_AdjustWindows(false) end
    r.UpdateArrange()
    return true
  end
  return false
end

-- Solo/listen: isolate one send by muting its siblings, remember previous mutes.
local function listen_key(track, category)
  return tostring(category) .. ":" .. tostring(track_guid(track) or "")
end

local function restore_send_listen_raw()
  local entry = state.listen
  if not entry then return true end
  local target = track_by_guid(entry.target_guid)
  if valid_track(target) and r.SetTrackSendInfo_Value then
    for send_index, previous in pairs(entry.mutes) do
      r.SetTrackSendInfo_Value(target, entry.category, send_index, "B_MUTE", previous and 1 or 0)
    end
  end
  state.listen = nil
  return true
end

local function restore_send_listen()
  if not state.listen then return false end
  return write_with_undo("Send Studio: Listen off", restore_send_listen_raw)
end

local function send_listen_active(track, category, index)
  local entry = state.listen
  return entry ~= nil and entry.key == listen_key(track, category) and entry.active_index == index
end

local function toggle_send_listen(track, category, index)
  if not valid_track(track) or not r.GetTrackNumSends or not r.SetTrackSendInfo_Value then return false end
  if send_listen_active(track, category, index) then return restore_send_listen() end
  return write_with_undo("Send Studio: Listen", function()
    if state.listen then restore_send_listen_raw() end
    local mutes = {}
    local count = r.GetTrackNumSends(track, category) or 0
    for send_index = 0, count - 1 do
      mutes[send_index] = (send_value(track, category, send_index, "B_MUTE") or 0) == 1
      r.SetTrackSendInfo_Value(track, category, send_index, "B_MUTE", send_index == index and 0 or 1)
    end
    state.listen = { key = listen_key(track, category), category = category, target_guid = track_guid(track), mutes = mutes, active_index = index }
    return true
  end)
end

-- Audition ("listen to return and original tracks only"): solo just the source
-- (original) and destination (return) track, remember previous solo states.
local function audition_key(src, dst)
  return tostring(track_guid(src) or "") .. ">" .. tostring(track_guid(dst) or "")
end

local function restore_audition_raw()
  local entry = state.audition
  if not entry then return true end
  for guid, previous in pairs(entry.solos) do
    local track = track_by_guid(guid)
    if valid_track(track) then r.SetMediaTrackInfo_Value(track, "I_SOLO", previous) end
  end
  state.audition = nil
  return true
end

local function restore_audition()
  if not state.audition then return false end
  return write_with_undo("Send Studio: Listen off", restore_audition_raw)
end

local function audition_active(src, dst)
  local entry = state.audition
  return entry ~= nil and entry.key == audition_key(src, dst)
end

local function toggle_audition(src, dst)
  if not valid_track(src) or not valid_track(dst) or not r.CountTracks or not r.SetMediaTrackInfo_Value then return false end
  if audition_active(src, dst) then return restore_audition() end
  return write_with_undo("Send Studio: Listen (return + original)", function()
    if state.audition then restore_audition_raw() end
    local solos = {}
    local src_guid = track_guid(src)
    local dst_guid = track_guid(dst)
    for track_index = 0, (r.CountTracks(0) or 0) - 1 do
      local track = r.GetTrack(0, track_index)
      local guid = track_guid(track)
      if valid_track(track) and guid then
        solos[guid] = r.GetMediaTrackInfo_Value(track, "I_SOLO") or 0
        r.SetMediaTrackInfo_Value(track, "I_SOLO", (guid == src_guid or guid == dst_guid) and 1 or 0)
      end
    end
    state.audition = { key = audition_key(src, dst), solos = solos }
    return true
  end)
end

-- Build lane descriptors for a given category (0 = sends, -1 = receives).
local function build_rows(track, category, settings)
  local rows = {}
  if not valid_track(track) or not r.GetTrackNumSends then return rows end
  local count = r.GetTrackNumSends(track, category) or 0
  for index = 0, count - 1 do
    local other = send_other_track(track, category, index)
    local volume = send_value(track, category, index, "D_VOL") or 1
    local pan = send_value(track, category, index, "D_PAN") or 0
    local muted = (send_value(track, category, index, "B_MUTE") or 0) == 1
    local mode = math.floor(send_value(track, category, index, "I_SENDMODE") or 0)
    local phase = (send_value(track, category, index, "B_PHASE") or 0) == 1
    local src_raw = math.floor(send_value(track, category, index, "I_SRCCHAN") or 0)
    local dst_raw = math.floor(send_value(track, category, index, "I_DSTCHAN") or 0)
    local src_track = category == -1 and other or track
    local dst_track = category == -1 and track or other
    local other_name = valid_track(other) and track_name(other) or "Missing track"
    local prefix = category == -1 and "recv" or "send"
    local lane_id = prefix .. "_" .. tostring(index) .. "_" .. tostring(track_guid(other) or index)
    rows[#rows + 1] = {
      id = lane_id,
      category = category,
      index = index,
      label = other_name,
      other = other,
      subtitle = (category == -1 and "Receive" or "Send") .. " | " .. send_mode_label(mode),
      value = volume,
      pan = pan,
      muted = muted,
      mode = mode,
      phase = phase,
      mono = (send_value(track, category, index, "B_MONO") or 0) == 1,
      src_raw = src_raw,
      dst_raw = dst_raw,
      src_track = src_track,
      dst_track = dst_track,
      handle_color = track_color(other),
      meter = smoothed_meter(lane_id, read_track_peak(other), settings),
      enabled = valid_track(other),
      listen_active = send_listen_active(track, category, index),
      audition_active = audition_active(src_track, dst_track),
      write_volume = function(v) return write_send_volume(track, category, index, v) end,
      write_pan = function(v) return write_send_pan(track, category, index, v) end,
      write_mute = function(v) return write_send_mute(track, category, index, v) end,
      write_mode = function(v) return write_send_mode(track, category, index, v) end,
      write_phase = function(v) return write_send_phase(track, category, index, v) end,
      write_mono = function(v) return write_send_mono(track, category, index, v) end,
      write_srcchan = function(v) return write_send_srcchan(track, category, index, v) end,
      write_dstchan = function(v) return write_send_dstchan(track, category, index, v) end,
      toggle_listen = function() return toggle_send_listen(track, category, index) end,
      toggle_audition = function() return toggle_audition(src_track, dst_track) end,
      select_other = function() return select_track(other) end,
      remove = function() return remove_send(track, category, index) end
    }
  end
  return rows
end

-- ---------------------------------------------------------------------------
-- Track picker for adding sends / receives
-- ---------------------------------------------------------------------------

local function guid_set(tracks)
  local set = {}
  for _, track in ipairs(tracks or {}) do
    local guid = track_guid(track)
    if guid then set[guid] = true end
  end
  return set
end

local function candidate_tracks(exclude_guids)
  exclude_guids = exclude_guids or {}
  local list = {}
  if not r.CountTracks or not r.GetTrack then return list end
  local depth = 0
  for index = 0, (r.CountTracks(0) or 0) - 1 do
    local track = r.GetTrack(0, index)
    if valid_track(track) then
      local folder_delta = math.floor(tonumber(r.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")) or 0)
      local guid = track_guid(track)
      if not (guid and exclude_guids[guid]) then
        list[#list + 1] = {
          track = track,
          name = track_name(track),
          number = track_index_label(track),
          depth = depth,
          color = track_color(track)
        }
      end
      depth = math.max(0, depth + folder_delta)
    end
  end
  return list
end

-- All currently selected tracks (used when not pinned, for multi-track actions).
local function selected_track_list(app)
  local list = {}
  local count = r.CountSelectedTracks and r.CountSelectedTracks(0) or 0
  for index = 0, count - 1 do
    local track = r.GetSelectedTrack(0, index)
    if valid_track(track) then list[#list + 1] = track end
  end
  return list
end

-- Create sends/receives from a set of source tracks to/from one other track.
local function apply_routes(app, settings, sources, other, mode)
  if not valid_track(other) or not r.CreateTrackSend then return false end
  local is_receive = mode == "receive"
  local created = false
  write_with_undo(is_receive and "Send Studio: Add receive" or "Send Studio: Add send", function()
    for _, track in ipairs(sources or {}) do
      local source = is_receive and other or track
      local destination = is_receive and track or other
      if valid_track(source) and valid_track(destination) and source ~= destination then
        local index = r.CreateTrackSend(source, destination)
        if index and index >= 0 then
          r.SetTrackSendInfo_Value(source, 0, index, "I_SENDMODE", tonumber(settings.default_send_mode) or 0)
          r.SetTrackSendInfo_Value(source, 0, index, "D_VOL", 1)
          r.SetTrackSendInfo_Value(source, 0, index, "B_MUTE", 0)
          created = true
        end
      end
    end
    return true
  end)
  return created
end

-- Copy all sends of a track into the module clipboard.
local function copy_sends(track)
  local clip = {}
  if not valid_track(track) or not r.GetTrackNumSends then return clip end
  for index = 0, (r.GetTrackNumSends(track, 0) or 0) - 1 do
    local dest = send_other_track(track, 0, index)
    if valid_track(dest) then
      clip[#clip + 1] = {
        dest_guid = track_guid(dest),
        vol = send_value(track, 0, index, "D_VOL") or 1,
        pan = send_value(track, 0, index, "D_PAN") or 0,
        mute = (send_value(track, 0, index, "B_MUTE") or 0) == 1,
        mode = math.floor(send_value(track, 0, index, "I_SENDMODE") or 0),
        phase = (send_value(track, 0, index, "B_PHASE") or 0) == 1,
        mono = (send_value(track, 0, index, "B_MONO") or 0) == 1,
        src_raw = math.floor(send_value(track, 0, index, "I_SRCCHAN") or 0),
        dst_raw = math.floor(send_value(track, 0, index, "I_DSTCHAN") or 0)
      }
    end
  end
  return clip
end

-- Paste clipboard sends onto a set of tracks.
local function paste_sends(sources, clip)
  if not clip or #clip == 0 or not r.CreateTrackSend then return false end
  local pasted = false
  write_with_undo("Send Studio: Paste sends", function()
    for _, track in ipairs(sources or {}) do
      if valid_track(track) then
        for _, entry in ipairs(clip) do
          local dest = track_by_guid(entry.dest_guid)
          if valid_track(dest) and dest ~= track then
            local index = r.CreateTrackSend(track, dest)
            if index and index >= 0 then
              r.SetTrackSendInfo_Value(track, 0, index, "D_VOL", entry.vol)
              r.SetTrackSendInfo_Value(track, 0, index, "D_PAN", entry.pan)
              r.SetTrackSendInfo_Value(track, 0, index, "B_MUTE", entry.mute and 1 or 0)
              r.SetTrackSendInfo_Value(track, 0, index, "I_SENDMODE", entry.mode)
              r.SetTrackSendInfo_Value(track, 0, index, "B_PHASE", entry.phase and 1 or 0)
              r.SetTrackSendInfo_Value(track, 0, index, "B_MONO", entry.mono and 1 or 0)
              r.SetTrackSendInfo_Value(track, 0, index, "I_SRCCHAN", entry.src_raw)
              r.SetTrackSendInfo_Value(track, 0, index, "I_DSTCHAN", entry.dst_raw)
              pasted = true
            end
          end
        end
      end
    end
    return true
  end)
  return pasted
end

-- Create a new bus track and send the given source tracks to it.
local function create_bus_and_send(app, settings, sources, name)
  if not r.InsertTrackAtIndex or not r.CountTracks or not r.GetTrack then return false end
  name = (name and name ~= "") and name or "FX Bus"
  return write_with_undo("Send Studio: New bus", function()
    local track_index = r.CountTracks(0) or 0
    r.InsertTrackAtIndex(track_index, true)
    local bus = r.GetTrack(0, track_index)
    if not valid_track(bus) then return false end
    if r.GetSetMediaTrackInfo_String then r.GetSetMediaTrackInfo_String(bus, "P_NAME", name, true) end
    for _, track in ipairs(sources or {}) do
      if valid_track(track) and track ~= bus then
        local index = r.CreateTrackSend(track, bus)
        if index and index >= 0 then
          r.SetTrackSendInfo_Value(track, 0, index, "I_SENDMODE", tonumber(settings.default_send_mode) or 0)
        end
      end
    end
    if r.SetOnlyTrackSelected then r.SetOnlyTrackSelected(bus) end
    return true
  end)
end

-- Clear any active send-solo and audition, restoring saved states.
local function reset_all_listen()
  local did = false
  if state.audition then restore_audition(); did = true end
  if state.listen then restore_send_listen(); did = true end
  return did
end

local function open_picker(mode)
  state.picker_open = true
  state.picker_mode = mode
  state.picker_filter = ""
end

local function draw_picker_popup(app, settings, target)
  local ctx = app.ctx
  local title = "Add Route##send_studio_picker"
  if state.picker_open then
    state.picker_open = false
    r.ImGui_OpenPopup(ctx, title)
  end
  local flags = r.ImGui_WindowFlags_AlwaysAutoResize and r.ImGui_WindowFlags_AlwaysAutoResize() or 0
  if not r.ImGui_BeginPopup or not r.ImGui_BeginPopup(ctx, title, flags) then return end
  local is_receive = state.picker_mode == "receive"
  local sources = (state.apply_tracks and #state.apply_tracks > 0) and state.apply_tracks or { target }
  r.ImGui_TextColored(ctx, Theme.colors.accent, is_receive and "Add receive from track" or "Add send to track")
  r.ImGui_SameLine(ctx)
  if #sources > 1 then
    r.ImGui_TextColored(ctx, Theme.colors.text_dim, (is_receive and "for " or "from ") .. tostring(#sources) .. " selected tracks")
  elseif valid_track(target) then
    r.ImGui_TextColored(ctx, Theme.colors.text_dim, "-> " .. ellipsize_text(ctx, track_name(target), UIScale.round(180)))
  end
  r.ImGui_SetNextItemWidth(ctx, UIScale.round(280))
  local changed, value = r.ImGui_InputTextWithHint(ctx, "##send_studio_picker_filter", "Filter tracks...", state.picker_filter or "")
  if changed then state.picker_filter = value end
  local filter = tostring(state.picker_filter or ""):lower()
  if r.ImGui_BeginChild(ctx, "##send_studio_picker_list", UIScale.round(280), UIScale.round(300)) then
    local candidates = candidate_tracks(guid_set(sources))
    local shown = 0
    for _, item in ipairs(candidates) do
      local haystack = (item.number .. " " .. item.name):lower()
      if filter == "" or haystack:find(filter, 1, true) then
        shown = shown + 1
        r.ImGui_PushID(ctx, "pick_" .. tostring(track_guid(item.track) or shown))
        if item.color then
          local cx, cy = r.ImGui_GetCursorScreenPos(ctx)
          local draw_list = r.ImGui_GetWindowDrawList(ctx)
          local h = r.ImGui_GetTextLineHeight(ctx)
          r.ImGui_DrawList_AddRectFilled(draw_list, cx, cy + UIScale.round(2), cx + UIScale.round(4), cy + h - UIScale.round(1), item.color, UIScale.px(2))
        end
        local indent = UIScale.round(8) + item.depth * UIScale.round(12)
        r.ImGui_Dummy(ctx, indent, 1)
        r.ImGui_SameLine(ctx, 0, 0)
        local label = (item.number ~= "" and (item.number .. "  ") or "") .. item.name
        if r.ImGui_Selectable(ctx, label .. "##pick") then
          apply_routes(app, settings, sources, item.track, state.picker_mode)
          r.ImGui_CloseCurrentPopup(ctx)
        end
        r.ImGui_PopID(ctx)
      end
    end
    if shown == 0 then r.ImGui_TextColored(ctx, Theme.colors.text_dim, "No matching tracks") end
    r.ImGui_EndChild(ctx)
  end
  r.ImGui_EndPopup(ctx)
end

-- Popup to name a new bus and send the active tracks to it.
local function draw_bus_popup(app, settings)
  local ctx = app.ctx
  local title = "New Bus##send_studio_bus"
  if state.bus_open then
    state.bus_open = false
    r.ImGui_OpenPopup(ctx, title)
  end
  local flags = r.ImGui_WindowFlags_AlwaysAutoResize and r.ImGui_WindowFlags_AlwaysAutoResize() or 0
  if not r.ImGui_BeginPopup or not r.ImGui_BeginPopup(ctx, title, flags) then return end
  local sources = (state.apply_tracks and #state.apply_tracks > 0) and state.apply_tracks or {}
  r.ImGui_TextColored(ctx, Theme.colors.accent, "Create bus and send")
  r.ImGui_TextColored(ctx, Theme.colors.text_dim, (#sources > 1 and tostring(#sources) .. " tracks" or "1 track") .. " will send to it")
  r.ImGui_SetNextItemWidth(ctx, UIScale.round(220))
  local changed, value = r.ImGui_InputTextWithHint(ctx, "##send_studio_bus_name", "Bus name", state.bus_name or "FX Bus")
  if changed then state.bus_name = value end
  local create = r.ImGui_Button(ctx, "Create##send_studio_bus_create", UIScale.text_button_w(ctx, "Create", 80, 8), 0)
  if r.ImGui_IsKeyPressed and r.ImGui_Key_Enter and r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_Enter()) then create = true end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "Cancel##send_studio_bus_cancel", UIScale.text_button_w(ctx, "Cancel", 80, 8), 0) then r.ImGui_CloseCurrentPopup(ctx) end
  if create and #sources > 0 then
    create_bus_and_send(app, settings, sources, state.bus_name)
    r.ImGui_CloseCurrentPopup(ctx)
  end
  r.ImGui_EndPopup(ctx)
end

-- ---------------------------------------------------------------------------
-- Card lane drawing (Control Room style)
-- ---------------------------------------------------------------------------

-- A compact text button drawn directly into the draw list (mixer-strip style).
local function strip_button(ctx, draw_list, x0, y0, x1, y1, label, active, active_color, mouse_x, mouse_y)
  local hovered = mouse_x >= x0 and mouse_x <= x1 and mouse_y >= y0 and mouse_y <= y1
  local bg = active and (active_color or Theme.colors.accent) or (hovered and Theme.colors.frame_hover or Theme.colors.frame_bg)
  r.ImGui_DrawList_AddRectFilled(draw_list, x0, y0, x1, y1, bg, UIScale.px(3))
  r.ImGui_DrawList_AddRect(draw_list, x0, y0, x1, y1, hovered and Theme.colors.text or Theme.colors.border, UIScale.px(3), 0, UIScale.px(1))
  local text_color = Theme.text_for_background(bg, active and Theme.colors.badge_text or Theme.colors.text, Theme.colors.text, 3)
  local shown = ellipsize_text(ctx, label, (x1 - x0) - UIScale.round(3))
  local text_w = calc_text_width(ctx, shown)
  local text_h = r.ImGui_GetTextLineHeight(ctx)
  r.ImGui_DrawList_AddText(draw_list, (x0 + x1 - text_w) * 0.5, (y0 + y1 - text_h) * 0.5, text_color, shown)
  local clicked = hovered and r.ImGui_IsMouseClicked(ctx, 0)
  local right_clicked = hovered and r.ImGui_IsMouseClicked(ctx, 1)
  return clicked, hovered, right_clicked
end

-- A phase-invert icon button (circle with a slash) drawn into the draw list.
local function strip_phase_button(ctx, draw_list, x0, y0, x1, y1, active, mouse_x, mouse_y)
  local hovered = mouse_x >= x0 and mouse_x <= x1 and mouse_y >= y0 and mouse_y <= y1
  local bg = active and Theme.colors.warning or (hovered and Theme.colors.frame_hover or Theme.colors.frame_bg)
  r.ImGui_DrawList_AddRectFilled(draw_list, x0, y0, x1, y1, bg, UIScale.px(3))
  r.ImGui_DrawList_AddRect(draw_list, x0, y0, x1, y1, hovered and Theme.colors.text or Theme.colors.border, UIScale.px(3), 0, UIScale.px(1))
  local glyph = Theme.text_for_background(bg, active and Theme.colors.badge_text or Theme.colors.text, Theme.colors.text, 3)
  local cx = (x0 + x1) * 0.5
  local cy = (y0 + y1) * 0.5
  local rad = math.min(x1 - x0, y1 - y0) * 0.28
  r.ImGui_DrawList_AddCircle(draw_list, cx, cy, rad, glyph, 16, UIScale.px(1.4))
  r.ImGui_DrawList_AddLine(draw_list, cx - rad * 0.95, cy + rad * 0.95, cx + rad * 0.95, cy - rad * 0.95, glyph, UIScale.px(1.4))
  local clicked = hovered and r.ImGui_IsMouseClicked(ctx, 0)
  return clicked, hovered
end

-- A mono/stereo icon button: one dot = mono (summed), two dots = stereo.
local function strip_mono_button(ctx, draw_list, x0, y0, x1, y1, mono, mouse_x, mouse_y)
  local hovered = mouse_x >= x0 and mouse_x <= x1 and mouse_y >= y0 and mouse_y <= y1
  local bg = mono and Theme.colors.accent or (hovered and Theme.colors.frame_hover or Theme.colors.frame_bg)
  r.ImGui_DrawList_AddRectFilled(draw_list, x0, y0, x1, y1, bg, UIScale.px(3))
  r.ImGui_DrawList_AddRect(draw_list, x0, y0, x1, y1, hovered and Theme.colors.text or Theme.colors.border, UIScale.px(3), 0, UIScale.px(1))
  local glyph = Theme.text_for_background(bg, mono and Theme.colors.badge_text or Theme.colors.text, Theme.colors.text, 3)
  local cy = (y0 + y1) * 0.5
  local dot = UIScale.px(2)
  if mono then
    r.ImGui_DrawList_AddCircleFilled(draw_list, (x0 + x1) * 0.5, cy, dot, glyph, 12)
  else
    local cx = (x0 + x1) * 0.5
    r.ImGui_DrawList_AddCircleFilled(draw_list, cx - UIScale.round(4), cy, dot, glyph, 12)
    r.ImGui_DrawList_AddCircleFilled(draw_list, cx + UIScale.round(4), cy, dot, glyph, 12)
  end
  local clicked = hovered and r.ImGui_IsMouseClicked(ctx, 0)
  return clicked, hovered
end

-- Popup with source + destination audio channel pickers for one send/receive.
local function draw_channel_popup(app, lane, popup_id)
  local ctx = app.ctx
  if not r.ImGui_BeginPopup or not r.ImGui_BeginPopup(ctx, popup_id) then return end
  r.ImGui_TextColored(ctx, Theme.colors.accent, "Audio routing")
  local label_w = UIScale.round(78)
  local combo_w = UIScale.round(150)

  r.ImGui_AlignTextToFramePadding(ctx)
  r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Source")
  r.ImGui_SameLine(ctx, label_w)
  r.ImGui_SetNextItemWidth(ctx, combo_w)
  if r.ImGui_BeginCombo(ctx, "##send_studio_srcchan", chan_label(lane.src_raw)) then
    for _, option in ipairs(channel_options(lane.src_track, true)) do
      if r.ImGui_Selectable(ctx, option.label, option.value == math.floor(lane.src_raw)) then lane.write_srcchan(option.value) end
    end
    r.ImGui_EndCombo(ctx)
  end

  r.ImGui_AlignTextToFramePadding(ctx)
  r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Destination")
  r.ImGui_SameLine(ctx, label_w)
  r.ImGui_SetNextItemWidth(ctx, combo_w)
  if r.ImGui_BeginCombo(ctx, "##send_studio_dstchan", chan_label(lane.dst_raw)) then
    for _, option in ipairs(channel_options(lane.dst_track, false)) do
      if r.ImGui_Selectable(ctx, option.label, option.value == math.floor(lane.dst_raw)) then lane.write_dstchan(option.value) end
    end
    r.ImGui_EndCombo(ctx)
  end
  r.ImGui_EndPopup(ctx)
end

local function draw_strip(app, lane, settings, width, height)
  local ctx = app.ctx
  local draw_list = r.ImGui_GetWindowDrawList(ctx)
  local enabled = lane.enabled == true
  r.ImGui_PushID(ctx, lane.id)
  local left_x, top_y = r.ImGui_GetCursorScreenPos(ctx)
  r.ImGui_Dummy(ctx, width, height)
  if r.ImGui_BeginPopupContextItem and r.ImGui_BeginPopupContextItem(ctx, "##send_studio_strip_menu") then
    r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Send Mode")
    for _, mode in ipairs(SEND_MODES) do
      if r.ImGui_Selectable(ctx, send_mode_label(mode), lane.mode == mode) then lane.write_mode(mode) end
    end
    r.ImGui_Separator(ctx)
    local phase_changed, phase_value = r.ImGui_Checkbox(ctx, "Invert phase", lane.phase == true)
    if phase_changed then lane.write_phase(phase_value) end
    local mono_changed, mono_value = r.ImGui_Checkbox(ctx, "Mono sum", lane.mono == true)
    if mono_changed then lane.write_mono(mono_value) end
    r.ImGui_Separator(ctx)
    if r.ImGui_Selectable(ctx, "Select destination track") then lane.select_other() end
    if r.ImGui_Selectable(ctx, lane.category == -1 and "Remove receive" or "Remove send") then lane.remove() end
    r.ImGui_EndPopup(ctx)
  end
  local right_x = left_x + width
  local bottom_y = top_y + height
  local mouse_x, mouse_y = r.ImGui_GetMousePos(ctx)
  local hovered = mouse_x >= left_x and mouse_x <= right_x and mouse_y >= top_y and mouse_y <= bottom_y

  -- When any popup/combo is open, our custom-drawn buttons must not react to
  -- clicks meant for that popup (they bypass ImGui's input capture).
  local popup_open = false
  if r.ImGui_IsPopupOpen and r.ImGui_PopupFlags_AnyPopup then
    local ok, result = pcall(r.ImGui_IsPopupOpen, ctx, "", r.ImGui_PopupFlags_AnyPopup())
    popup_open = ok and result == true
  end
  local interact = enabled and not popup_open

  -- Strip background (darker than the buttons for contrast)
  local corner = UIScale.px(5)
  r.ImGui_DrawList_AddRectFilled(draw_list, left_x, top_y, right_x, bottom_y, Theme.colors.child_bg, corner)
  r.ImGui_DrawList_AddRect(draw_list, left_x, top_y, right_x, bottom_y, enabled and Theme.colors.border or 0xFFFFFF22, corner, 0, hovered and UIScale.px(1.3) or UIScale.px(0.8))

  local pad = UIScale.round(4)
  local gap = UIScale.round(3)
  local x0 = left_x + pad
  local x1 = right_x - pad
  local mid_x = (x0 + x1) * 0.5
  local button_h = UIScale.round(15)

  -- Row 1: Mute / Solo send / Listen (original + return)
  local r1t = top_y + pad
  local r1b = r1t + button_h
  local third = (x1 - x0) / 3
  local mute_clicked, mute_hov = strip_button(ctx, draw_list, x0, r1t, x0 + third - UIScale.px(1), r1b, "M", lane.muted, Theme.colors.warning, mouse_x, mouse_y)
  if mute_clicked and interact then lane.write_mute(not lane.muted) end
  local solo_clicked, solo_hov = strip_button(ctx, draw_list, x0 + third + UIScale.px(1), r1t, x0 + 2 * third - UIScale.px(1), r1b, "S", lane.listen_active, Theme.colors.accent, mouse_x, mouse_y)
  if solo_clicked and interact then lane.toggle_listen() end
  local listen_clicked, listen_hov = strip_button(ctx, draw_list, x0 + 2 * third + UIScale.px(1), r1t, x1, r1b, "L", lane.audition_active, Theme.colors.accent, mouse_x, mouse_y)
  if listen_clicked and interact then lane.toggle_audition() end
  if mute_hov then r.ImGui_SetTooltip(ctx, lane.muted and "Unmute send" or "Mute send")
  elseif solo_hov then r.ImGui_SetTooltip(ctx, "Solo send: isolate among sends to the same track")
  elseif listen_hov then r.ImGui_SetTooltip(ctx, "Listen: solo original + return track only\n(mutes everything else)") end

  -- Row 2: Phase / Mono
  local r2t = r1b + gap
  local r2b = r2t + button_h
  local phase_clicked, phase_hov = strip_phase_button(ctx, draw_list, x0, r2t, mid_x - UIScale.px(1), r2b, lane.phase, mouse_x, mouse_y)
  if phase_clicked and interact then lane.write_phase(not lane.phase) end
  local mono_clicked, mono_hov = strip_mono_button(ctx, draw_list, mid_x + UIScale.px(1), r2t, x1, r2b, lane.mono, mouse_x, mouse_y)
  if mono_clicked and interact then lane.write_mono(not lane.mono) end
  if phase_hov then r.ImGui_SetTooltip(ctx, lane.phase and "Phase inverted" or "Invert phase")
  elseif mono_hov then r.ImGui_SetTooltip(ctx, lane.mono and "Mono sum (on)" or "Sum to mono") end

  -- Row 3: Send mode (full label)
  local r3t = r2b + gap
  local r3b = r3t + button_h
  local mode_clicked, mode_hov = strip_button(ctx, draw_list, x0, r3t, x1, r3b, send_mode_label(lane.mode), false, nil, mouse_x, mouse_y)
  if mode_clicked and interact then lane.write_mode(next_send_mode(lane.mode)) end
  if mode_hov then r.ImGui_SetTooltip(ctx, "Send mode (click to cycle)") end

  -- Row 4: Audio channel routing (source -> destination)
  local r4t = r3b + gap
  local r4b = r4t + button_h
  local chan_text = chan_label(lane.src_raw) .. " > " .. chan_label(lane.dst_raw)
  local chan_clicked, chan_hov = strip_button(ctx, draw_list, x0, r4t, x1, r4b, chan_text, false, nil, mouse_x, mouse_y)
  if chan_clicked and interact then r.ImGui_OpenPopup(ctx, "##send_studio_chan") end
  if chan_hov then r.ImGui_SetTooltip(ctx, "Source > destination audio channel") end

  -- Name label (colour of destination track) at the bottom
  local name_h = UIScale.round(16)
  local name_y1 = bottom_y - pad
  local name_y0 = name_y1 - name_h
  local name_bg = enabled and (lane.handle_color or Theme.colors.accent) or Theme.colors.frame_bg
  r.ImGui_DrawList_AddRectFilled(draw_list, x0, name_y0, x1, name_y1, name_bg, UIScale.px(3))
  local name_text_color = Theme.text_for_background(name_bg, Theme.colors.badge_text, Theme.colors.text, 3)
  local name_label = ellipsize_text(ctx, lane.label, x1 - x0 - UIScale.round(4))
  local name_text_w = calc_text_width(ctx, name_label)
  local name_text_h = r.ImGui_GetTextLineHeight(ctx)
  r.ImGui_DrawList_AddText(draw_list, (x0 + x1 - name_text_w) * 0.5, (name_y0 + name_y1 - name_text_h) * 0.5, name_text_color, name_label)
  local name_hovered = mouse_x >= x0 and mouse_x <= x1 and mouse_y >= name_y0 and mouse_y <= name_y1
  if name_hovered and interact and r.ImGui_IsMouseClicked(ctx, 0) then lane.select_other() end

  -- dB value above the name label
  local value_text = enabled and format_db(lane.value, settings) or "--"
  local value_h = r.ImGui_GetTextLineHeight(ctx)
  local value_y = name_y0 - UIScale.round(3) - value_h
  local value_w = calc_text_width(ctx, value_text)
  r.ImGui_DrawList_AddText(draw_list, (x0 + x1 - value_w) * 0.5, value_y, enabled and Theme.colors.text or Theme.colors.text_dim, value_text)

  -- Pan strip below the button cluster
  local pan_y = r4b + gap + UIScale.round(7)
  local pan_left = x0 + UIScale.round(2)
  local pan_right = x1 - UIScale.round(2)
  local pan_range = math.max(1, pan_right - pan_left)
  local pan_mid = (pan_left + pan_right) * 0.5
  r.ImGui_DrawList_AddLine(draw_list, pan_left, pan_y, pan_right, pan_y, 0xFFFFFF22, UIScale.px(2))
  r.ImGui_DrawList_AddLine(draw_list, pan_mid, pan_y - UIScale.round(3), pan_mid, pan_y + UIScale.round(3), Theme.colors.border, UIScale.px(1))
  local pan_dot_x = pan_mid + (tonumber(lane.pan) or 0) * (pan_range * 0.5)
  if enabled then r.ImGui_DrawList_AddLine(draw_list, pan_mid, pan_y, pan_dot_x, pan_y, Theme.colors.accent, UIScale.px(2)) end
  r.ImGui_DrawList_AddCircleFilled(draw_list, pan_dot_x, pan_y, UIScale.px(3.5), enabled and (lane.handle_color or Theme.colors.accent) or Theme.colors.border, 16)
  local pan_hovered = enabled and mouse_x >= pan_left - UIScale.round(4) and mouse_x <= pan_right + UIScale.round(4) and mouse_y >= pan_y - UIScale.round(7) and mouse_y <= pan_y + UIScale.round(7)
  if pan_hovered and interact and r.ImGui_IsMouseDoubleClicked and r.ImGui_IsMouseDoubleClicked(ctx, 0) then
    lane.write_pan(0)
    state.drag = nil
  elseif pan_hovered and interact and r.ImGui_IsMouseClicked(ctx, 0) then
    state.drag = { id = lane.id, kind = "pan" }
  end
  if enabled and state.drag and state.drag.id == lane.id and state.drag.kind == "pan" then
    lane.write_pan(clamp((mouse_x - pan_mid) / (pan_range * 0.5), -1, 1))
  end

  -- Vertical fader between pan strip and the dB value
  local fader_top = pan_y + UIScale.round(12)
  local fader_bottom = value_y - UIScale.round(6)
  if fader_bottom > fader_top + UIScale.round(20) then
    local groove_w = UIScale.round(6)
    local groove_x = (x0 + x1) * 0.5
    local range = math.max(1, fader_bottom - fader_top)
    local current_db = linear_to_db(lane.value, settings.min_db)
    local normalized = clamp((current_db - settings.min_db) / (settings.max_db - settings.min_db), 0, 1)
    local thumb_y = fader_bottom - normalized * range
    r.ImGui_DrawList_AddRectFilled(draw_list, groove_x - groove_w * 0.5, fader_top, groove_x + groove_w * 0.5, fader_bottom, 0x00000055, UIScale.px(3))
    if enabled then r.ImGui_DrawList_AddRectFilled(draw_list, groove_x - groove_w * 0.5, thumb_y, groove_x + groove_w * 0.5, fader_bottom, Theme.colors.accent_soft, UIScale.px(3)) end
    local zero_normalized = clamp((0 - settings.min_db) / (settings.max_db - settings.min_db), 0, 1)
    local zero_y = fader_bottom - zero_normalized * range
    local handle_half = math.min(UIScale.round(16), (x1 - x0) * 0.5 - UIScale.round(2))
    r.ImGui_DrawList_AddLine(draw_list, groove_x - handle_half, zero_y, groove_x + handle_half, zero_y, Theme.colors.border, UIScale.px(1))
    -- Compact handle centred on the groove (like Control Room)
    local handle_color = enabled and (lane.handle_color or Theme.colors.accent) or Theme.colors.border
    local handle_left = groove_x - handle_half
    local handle_right = groove_x + handle_half
    r.ImGui_DrawList_AddRectFilled(draw_list, handle_left, thumb_y - UIScale.round(5), handle_right, thumb_y + UIScale.round(5), handle_color, UIScale.px(3))
    r.ImGui_DrawList_AddRect(draw_list, handle_left, thumb_y - UIScale.round(5), handle_right, thumb_y + UIScale.round(5), 0x00000066, UIScale.px(3), 0, UIScale.px(1))
    local handle_hovered = enabled and mouse_x >= handle_left and mouse_x <= handle_right and mouse_y >= thumb_y - UIScale.round(8) and mouse_y <= thumb_y + UIScale.round(8)
    local fader_hovered = enabled and mouse_x >= x0 and mouse_x <= x1 and mouse_y >= fader_top - UIScale.round(4) and mouse_y <= fader_bottom + UIScale.round(4)
    if handle_hovered and interact and r.ImGui_IsMouseDoubleClicked and r.ImGui_IsMouseDoubleClicked(ctx, 0) then
      lane.write_volume(1)
      state.drag = nil
    elseif fader_hovered and interact and r.ImGui_IsMouseClicked(ctx, 0) and not pan_hovered then
      state.drag = { id = lane.id, kind = "vol" }
    end
    local wheel = fader_hovered and shift_key_down(ctx) and mouse_wheel_delta(ctx) or 0
    if enabled and math.abs(wheel) > 0.0001 then
      lane.write_volume(db_to_linear(clamp(current_db + wheel * 0.1, settings.min_db, settings.max_db), settings.min_db, settings.max_db))
    end
    if enabled and state.drag and state.drag.id == lane.id and state.drag.kind == "vol" then
      local next_normalized = clamp((fader_bottom - mouse_y) / range, 0, 1)
      lane.write_volume(db_to_linear(settings.min_db + next_normalized * (settings.max_db - settings.min_db), settings.min_db, settings.max_db))
    end
    if handle_hovered then r.ImGui_SetTooltip(ctx, "Drag: volume | Shift+scroll: fine | Double-click: 0 dB") end
  end

  -- Release drag
  if not r.ImGui_IsMouseDown(ctx, 0) and state.drag and state.drag.id == lane.id then state.drag = nil end

  if not enabled and hovered then r.ImGui_SetTooltip(ctx, "Destination track missing") end
  draw_channel_popup(app, lane, "##send_studio_chan")
  r.ImGui_PopID(ctx)
end

-- ---------------------------------------------------------------------------
-- List row drawing (compact)
-- ---------------------------------------------------------------------------

local function push_slider_theme(ctx)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), 0x00000044)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrab(), Theme.colors.accent)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrabActive(), Theme.colors.accent)
  return 3
end

local function draw_list_row(app, lane, settings, name_width)
  local ctx = app.ctx
  local enabled = lane.enabled == true
  r.ImGui_PushID(ctx, lane.id)

  -- Colour swatch + name
  local cx, cy = r.ImGui_GetCursorScreenPos(ctx)
  local draw_list = r.ImGui_GetWindowDrawList(ctx)
  local line_h = r.ImGui_GetFrameHeight(ctx)
  r.ImGui_DrawList_AddRectFilled(draw_list, cx, cy + UIScale.round(3), cx + UIScale.round(4), cy + line_h - UIScale.round(3), lane.handle_color or Theme.colors.border, UIScale.px(2))
  r.ImGui_Dummy(ctx, UIScale.round(8), line_h)
  r.ImGui_SameLine(ctx, 0, 0)
  local name_color = enabled and Theme.colors.text or Theme.colors.text_dim
  r.ImGui_AlignTextToFramePadding(ctx)
  r.ImGui_TextColored(ctx, name_color, ellipsize_text(ctx, lane.label, name_width))
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, lane.label) end
  r.ImGui_SameLine(ctx, UIScale.round(8) + name_width + UIScale.round(10))

  -- Mute
  local mute_w = UIScale.text_button_w(ctx, "M", 30, 6)
  if lane.muted then
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), Theme.colors.warning)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), Theme.colors.warning)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), Theme.text_for_background(Theme.colors.warning, nil, nil, 4.5))
  end
  if r.ImGui_Button(ctx, "M##mute", mute_w, 0) and enabled then lane.write_mute(not lane.muted) end
  if lane.muted then r.ImGui_PopStyleColor(ctx, 3) end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, lane.muted and "Unmute" or "Mute") end
  r.ImGui_SameLine(ctx)

  -- Solo send (isolate among sends to the same track)
  local toggle_w = UIScale.text_button_w(ctx, "S", 26, 6)
  if lane.listen_active then
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), Theme.colors.accent)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), Theme.colors.accent)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), Theme.text_for_background(Theme.colors.accent, nil, nil, 4.5))
  end
  if r.ImGui_Button(ctx, "S##solo", toggle_w, 0) and enabled then lane.toggle_listen() end
  if lane.listen_active then r.ImGui_PopStyleColor(ctx, 3) end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Solo send: isolate among sends to the same track") end
  r.ImGui_SameLine(ctx)

  -- Listen: solo original + return track only
  if lane.audition_active then
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), Theme.colors.accent)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), Theme.colors.accent)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), Theme.text_for_background(Theme.colors.accent, nil, nil, 4.5))
  end
  if r.ImGui_Button(ctx, "L##listen", toggle_w, 0) and enabled then lane.toggle_audition() end
  if lane.audition_active then r.ImGui_PopStyleColor(ctx, 3) end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Listen: solo original + return track only") end
  r.ImGui_SameLine(ctx)

  -- Volume slider (dB)
  local shown_db = linear_to_db(lane.value, settings.min_db)
  r.ImGui_SetNextItemWidth(ctx, UIScale.round(150))
  local slider_count = push_slider_theme(ctx)
  local vol_changed, next_db = r.ImGui_SliderDouble(ctx, "##vol", shown_db, settings.min_db, settings.max_db, "%.1f dB")
  r.ImGui_PopStyleColor(ctx, slider_count)
  if r.ImGui_IsItemHovered(ctx) and r.ImGui_IsMouseClicked(ctx, 1) then lane.write_volume(1) elseif vol_changed then lane.write_volume(db_to_linear(next_db, settings.min_db, settings.max_db)) end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Right-click to reset to 0 dB") end
  r.ImGui_SameLine(ctx)

  -- Pan slider
  r.ImGui_SetNextItemWidth(ctx, UIScale.round(110))
  slider_count = push_slider_theme(ctx)
  local pan_changed, next_pan = r.ImGui_SliderDouble(ctx, "##pan", tonumber(lane.pan) or 0, -1, 1, format_pan(lane.pan))
  r.ImGui_PopStyleColor(ctx, slider_count)
  if r.ImGui_IsItemHovered(ctx) and r.ImGui_IsMouseClicked(ctx, 1) then lane.write_pan(0) elseif pan_changed then lane.write_pan(next_pan) end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Right-click to center") end
  r.ImGui_SameLine(ctx)

  -- Send mode (cycles on click)
  local mode_w = UIScale.text_button_w(ctx, "Pre-Fader", 74, 6)
  if r.ImGui_Button(ctx, send_mode_label(lane.mode) .. "##mode", mode_w, 0) then lane.write_mode(next_send_mode(lane.mode)) end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Send mode (click to cycle)") end
  r.ImGui_SameLine(ctx)

  -- Audio channel routing (source -> destination)
  local chan_text = chan_label(lane.src_raw) .. " > " .. chan_label(lane.dst_raw)
  if r.ImGui_Button(ctx, chan_text .. "##chan", UIScale.text_button_w(ctx, "MIDI > Mono 1", 90, 6), 0) then r.ImGui_OpenPopup(ctx, "##send_studio_chan") end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Source > destination audio channel") end
  draw_channel_popup(app, lane, "##send_studio_chan")
  r.ImGui_SameLine(ctx)

  -- Remove
  if r.ImGui_Button(ctx, "x##remove", UIScale.text_button_w(ctx, "x", 26, 6), 0) then lane.remove() end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, lane.category == -1 and "Remove receive" or "Remove send") end

  r.ImGui_PopID(ctx)
end

-- ---------------------------------------------------------------------------
-- Section drawing
-- ---------------------------------------------------------------------------

local STRIP_MIN_WIDTH = 88
local STRIP_MAX_WIDTH = 200
local STRIP_HEIGHT = 242

-- Lay out the strips in a wrapping grid that flexes to fill the width and
-- wraps to the next row when the window gets too narrow (like Control Room).
-- Strips grow with the window up to STRIP_MAX_WIDTH, then stop widening.
local function draw_section_strips(app, settings, rows)
  local ctx = app.ctx
  local avail_width = r.ImGui_GetContentRegionAvail(ctx)
  local spacing = UIScale.round(6)
  local min_w = UIScale.round(STRIP_MIN_WIDTH)
  local max_w = UIScale.round(STRIP_MAX_WIDTH)
  local columns = math.max(1, math.floor((avail_width + spacing) / (min_w + spacing)))
  columns = math.min(columns, #rows)
  local strip_w = math.max(min_w, (avail_width - spacing * (columns - 1)) / columns)
  strip_w = math.min(strip_w, max_w)
  local strip_h = UIScale.round(STRIP_HEIGHT)
  for index, lane in ipairs(rows) do
    draw_strip(app, lane, settings, strip_w, strip_h)
    if index % columns ~= 0 and index < #rows then r.ImGui_SameLine(ctx, 0, spacing) end
  end
end

local function draw_section_list(app, settings, rows)
  local ctx = app.ctx
  local name_width = UIScale.round(150)
  for _, lane in ipairs(rows) do
    draw_list_row(app, lane, settings, name_width)
  end
end

local function draw_section(app, settings, title, rows, add_mode)
  local ctx = app.ctx
  r.ImGui_TextColored(ctx, Theme.colors.accent, title)
  r.ImGui_SameLine(ctx)
  r.ImGui_TextColored(ctx, Theme.colors.text_dim, "(" .. tostring(#rows) .. ")")
  r.ImGui_SameLine(ctx)
  if r.ImGui_SmallButton(ctx, "+ Add##add_" .. add_mode) then open_picker(add_mode) end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, add_mode == "receive" and "Add a receive from another track" or "Add a send to another track") end
  if #rows == 0 then
    r.ImGui_TextColored(ctx, Theme.colors.text_dim, add_mode == "receive" and "No receives on this track." or "No sends on this track.")
  elseif settings.view_mode == "list" then
    draw_section_list(app, settings, rows)
  else
    draw_section_strips(app, settings, rows)
  end
  r.ImGui_Dummy(ctx, 1, UIScale.round(6))
end

-- ---------------------------------------------------------------------------
-- Header + footer
-- ---------------------------------------------------------------------------

local function draw_header(app, settings, target, pinned, source_count)
  local ctx = app.ctx
  r.ImGui_TextColored(ctx, Theme.colors.accent, "Send Studio")
  r.ImGui_SameLine(ctx)
  if valid_track(target) then
    local number = track_index_label(target)
    local label = (number ~= "" and (number .. "  ") or "") .. track_name(target)
    r.ImGui_TextColored(ctx, Theme.colors.text, ellipsize_text(ctx, label, UIScale.round(220)))
    if not pinned and (source_count or 0) > 1 then
      r.ImGui_SameLine(ctx)
      r.ImGui_TextColored(ctx, Theme.colors.warning, "+" .. tostring(source_count - 1))
      if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, tostring(source_count) .. " tracks selected - new sends apply to all") end
    end
  else
    r.ImGui_TextColored(ctx, Theme.colors.text_dim, "No track selected")
  end

  -- Pin toggle on the right
  local pin_label = pinned and "Pinned" or "Pin"
  local pin_w = UIScale.text_button_w(ctx, "Pinned", 64, 8)
  r.ImGui_SameLine(ctx)
  local avail_x = r.ImGui_GetContentRegionAvail(ctx)
  if avail_x > pin_w then r.ImGui_SetCursorPosX(ctx, r.ImGui_GetCursorPosX(ctx) + (avail_x - pin_w)) end
  if pinned then
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), Theme.colors.accent)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), Theme.colors.accent)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), Theme.text_for_background(Theme.colors.accent, nil, nil, 4.5))
  end
  if r.ImGui_Button(ctx, pin_label .. "##send_studio_pin", pin_w, 0) then
    if pinned then set_pin(app, settings, nil) else set_pin(app, settings, target) end
  end
  if pinned then r.ImGui_PopStyleColor(ctx, 3) end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, pinned and "Unpin - follow selection again" or "Pin this track (stop following selection)") end
end

-- Toolbar with global actions: new bus, copy/paste sends, reset solo/listen.
local function draw_toolbar(app, settings, target, sources)
  local ctx = app.ctx
  local has_target = valid_track(target)
  local clip_count = state.clipboard and #state.clipboard or 0

  if r.ImGui_SmallButton(ctx, "+ Bus##send_studio_newbus") and has_target then state.bus_open = true end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Create a new bus track and send the active track(s) to it") end
  r.ImGui_SameLine(ctx)

  if r.ImGui_SmallButton(ctx, "Copy##send_studio_copy") and has_target then
    state.clipboard = copy_sends(target)
    app.status = "Send Studio: copied " .. tostring(#state.clipboard) .. " sends"
  end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Copy this track's sends to the clipboard") end
  r.ImGui_SameLine(ctx)

  local can_paste = clip_count > 0
  if not can_paste and r.ImGui_BeginDisabled then r.ImGui_BeginDisabled(ctx) end
  if r.ImGui_SmallButton(ctx, (can_paste and ("Paste (" .. clip_count .. ")") or "Paste") .. "##send_studio_paste") and can_paste then
    paste_sends(sources, state.clipboard)
  end
  if not can_paste and r.ImGui_EndDisabled then r.ImGui_EndDisabled(ctx) end
  if can_paste and r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Paste copied sends onto the active track(s)") end

  if state.listen or state.audition then
    r.ImGui_SameLine(ctx)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), Theme.colors.warning)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), Theme.colors.warning)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), Theme.text_for_background(Theme.colors.warning, nil, nil, 4.5))
    local reset = r.ImGui_SmallButton(ctx, "Reset Solo##send_studio_reset")
    r.ImGui_PopStyleColor(ctx, 3)
    if reset then reset_all_listen() end
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Clear active solo/listen and restore the previous state") end
  end
end

local function draw_footer(app, settings)
  local ctx = app.ctx
  local draw_list = r.ImGui_GetWindowDrawList(ctx)
  local left_x, top_y = r.ImGui_GetCursorScreenPos(ctx)
  local width = r.ImGui_GetContentRegionAvail(ctx)
  local footer_h = r.ImGui_GetFrameHeight(ctx) + UIScale.round(14)
  r.ImGui_DrawList_AddRectFilled(draw_list, left_x, top_y, left_x + width, top_y + footer_h, 0x00000033, UIScale.px(4))
  r.ImGui_DrawList_AddRect(draw_list, left_x, top_y, left_x + width, top_y + footer_h, Theme.colors.border, UIScale.px(4), 0, UIScale.px(0.8))
  r.ImGui_SetCursorScreenPos(ctx, left_x + UIScale.round(8), top_y + UIScale.round(7))

  -- View toggle
  local function view_button(label, value)
    local active = settings.view_mode == value
    if active then
      r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), Theme.colors.accent)
      r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), Theme.colors.accent)
      r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), Theme.text_for_background(Theme.colors.accent, nil, nil, 4.5))
    end
    local clicked = r.ImGui_Button(ctx, label .. "##send_studio_view_" .. value, UIScale.text_button_w(ctx, label, 58, 8), 0)
    if active then r.ImGui_PopStyleColor(ctx, 3) end
    if clicked and not active then
      settings.view_mode = value
      if app.save_settings then app.save_settings() end
    end
  end
  view_button("Cards", "cards")
  r.ImGui_SameLine(ctx, 0, UIScale.round(4))
  view_button("List", "list")

  -- Default send mode selector
  r.ImGui_SameLine(ctx, 0, UIScale.round(16))
  r.ImGui_AlignTextToFramePadding(ctx)
  r.ImGui_TextColored(ctx, Theme.colors.text_dim, "New:")
  r.ImGui_SameLine(ctx)
  local combo_avail = r.ImGui_GetContentRegionAvail(ctx)
  r.ImGui_SetNextItemWidth(ctx, math.max(UIScale.round(110), combo_avail - UIScale.round(8)))
  if r.ImGui_BeginCombo(ctx, "##send_studio_default_mode", send_mode_label(settings.default_send_mode)) then
    for _, mode in ipairs(SEND_MODES) do
      if r.ImGui_Selectable(ctx, send_mode_label(mode), settings.default_send_mode == mode) then
        settings.default_send_mode = mode
        if app.save_settings then app.save_settings() end
      end
    end
    r.ImGui_EndCombo(ctx)
  end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Send mode applied to newly created sends/receives") end
end

-- ---------------------------------------------------------------------------
-- Module entry points
-- ---------------------------------------------------------------------------

function M.init(app)
  ensure_settings(app)
end

function M.draw(app)
  local ctx = app.ctx
  local settings = ensure_settings(app)
  local target, pinned = target_track(app, settings)

  -- Resolve which tracks new/pasted routing applies to (multi-track when not pinned).
  local sources
  if pinned then
    sources = valid_track(target) and { target } or {}
  else
    sources = selected_track_list(app)
  end
  if #sources == 0 and valid_track(target) then sources = { target } end
  state.apply_tracks = sources

  draw_header(app, settings, target, pinned, #sources)
  draw_toolbar(app, settings, target, sources)
  r.ImGui_Dummy(ctx, 1, UIScale.round(4))

  local footer_h = r.ImGui_GetFrameHeight(ctx) + UIScale.round(22)
  if r.ImGui_BeginChild(ctx, "##send_studio_body", 0, -footer_h) then
    if not valid_track(target) then
      r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Select a track to manage its sends and receives.")
      r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Tip: use Pin to keep a track in view while selecting others.")
    else
      local sends = build_rows(target, 0, settings)
      local receives = build_rows(target, -1, settings)
      draw_section(app, settings, "Sends", sends, "send")
      r.ImGui_Separator(ctx)
      r.ImGui_Dummy(ctx, 1, UIScale.round(4))
      draw_section(app, settings, "Receives", receives, "receive")
    end
    r.ImGui_EndChild(ctx)
  end

  draw_footer(app, settings)
  draw_picker_popup(app, settings, target)
  draw_bus_popup(app, settings)
end

return M
