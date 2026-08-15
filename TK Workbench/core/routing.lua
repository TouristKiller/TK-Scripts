-- Track channel and send routing helpers.
--
-- Lifted verbatim out of modules/send_studio.lua so a second module can route
-- audio without a second copy of the encoding rules. The behaviour is unchanged;
-- the only difference is that ensure_track_channels takes its undo label from
-- the caller instead of naming Send Studio.

local r = reaper

local M = {}

function M.valid_track(track)
  return track and r.ValidatePtr2(0, track, "MediaTrack*") == true
end

function M.track_guid(track)
  if not M.valid_track(track) or not r.GetTrackGUID then return nil end
  local ok, guid = pcall(r.GetTrackGUID, track)
  return ok and guid and guid ~= "" and guid or nil
end

function M.track_by_guid(guid)
  if not guid or guid == "" or not r.CountTracks or not r.GetTrackGUID then return nil end
  for index = 0, (r.CountTracks(0) or 0) - 1 do
    local track = r.GetTrack(0, index)
    if track and r.GetTrackGUID(track) == guid then return track end
  end
  return nil
end

function M.write_with_undo(label, callback)
  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)
  local ok, result = pcall(callback)
  r.PreventUIRefresh(-1)
  r.UpdateArrange()
  r.Undo_EndBlock(label, -1)
  return ok and result ~= false
end

-- Audio channel routing (I_SRCCHAN / I_DSTCHAN). Encoding: channel index in the
-- low bits, bit 1024 = mono, -1 (source only) = MIDI / no audio.
function M.chan_parse(raw)
  raw = math.floor(tonumber(raw) or 0)
  if raw < 0 then return { none = true } end
  return { channel = raw & 0x1FF, mono = (raw & 1024) ~= 0 }
end

function M.chan_label(raw)
  local parsed = M.chan_parse(raw)
  if parsed.none then return "MIDI" end
  if parsed.mono then return tostring(parsed.channel + 1) end
  return tostring(parsed.channel + 1) .. "/" .. tostring(parsed.channel + 2)
end

function M.track_channel_count(track)
  if not M.valid_track(track) or not r.GetMediaTrackInfo_Value then return 2 end
  local ok, value = pcall(r.GetMediaTrackInfo_Value, track, "I_NCHAN")
  return ok and math.max(2, math.floor(tonumber(value) or 2)) or 2
end

-- Grow a track's channel count (even, min 2) so a chosen channel pair exists.
-- Returns false when the track already has enough, so a caller can tell whether
-- it changed anything.
function M.set_track_channels(track, needed)
  if not M.valid_track(track) or not r.SetMediaTrackInfo_Value then return false end
  needed = math.max(2, math.floor(tonumber(needed) or 2))
  if needed % 2 == 1 then needed = needed + 1 end
  if M.track_channel_count(track) >= needed then return false end
  return r.SetMediaTrackInfo_Value(track, "I_NCHAN", needed)
end

-- The same, wrapped in its own undo block. Callers that already own an undo
-- block should use set_track_channels instead so the whole operation lands as
-- one undo step rather than two.
function M.ensure_track_channels(track, needed, undo_label)
  if not M.valid_track(track) or not r.SetMediaTrackInfo_Value then return false end
  needed = math.max(2, math.floor(tonumber(needed) or 2))
  if needed % 2 == 1 then needed = needed + 1 end
  if M.track_channel_count(track) >= needed then return false end
  return M.write_with_undo(undo_label or "Set track channels", function()
    return M.set_track_channels(track, needed)
  end)
end

-- Channel options up to at least 16 channels, so higher pairs (3/4, 5/6 ...) can
-- be picked even when the track does not have them yet (needs = channels required).
function M.channel_options(track, include_midi)
  local options = {}
  if include_midi then options[#options + 1] = { value = -1, label = "MIDI (no audio)", needs = 0 } end
  local count = math.max(M.track_channel_count(track), 16)
  for channel = 0, count - 2, 2 do
    options[#options + 1] = { value = channel, label = tostring(channel + 1) .. "/" .. tostring(channel + 2), needs = channel + 2 }
  end
  for channel = 0, count - 1 do
    options[#options + 1] = { value = channel | 1024, label = "Mono " .. tostring(channel + 1), needs = channel + 1 }
  end
  return options
end

-- FX input pins. A third party compressor takes its key input from whichever
-- track channels its pins are mapped to, so retargeting a captured sidechain to
-- a different channel pair means moving those pins rather than setting some
-- parameter. Channels 0-31 live in the low mask, 32 and up in the high one.
function M.pin_mask(channel)
  channel = math.floor(tonumber(channel) or 0)
  if channel < 0 then return 0, 0 end
  if channel < 32 then return 1 << channel, 0 end
  return 0, 1 << (channel - 32)
end

function M.mask_channels(low, high)
  local channels = {}
  low = math.floor(tonumber(low) or 0)
  high = math.floor(tonumber(high) or 0)
  for bit = 0, 31 do
    if (low >> bit) & 1 == 1 then channels[#channels + 1] = bit end
    if (high >> bit) & 1 == 1 then channels[#channels + 1] = bit + 32 end
  end
  return channels
end

-- Which input pins listen to which channel, lowest channel per pin.
function M.input_pin_channels(track, fx)
  local pins = {}
  if not r.TrackFX_GetPinMappings or not r.TrackFX_GetIOSize then return pins end
  local _, inputs = r.TrackFX_GetIOSize(track, fx)
  for pin = 0, math.max(0, (tonumber(inputs) or 0) - 1) do
    local low, high = r.TrackFX_GetPinMappings(track, fx, 0, pin)
    local channels = M.mask_channels(low, high)
    if channels[1] then pins[#pins + 1] = { pin = pin, channel = channels[1] } end
  end
  return pins
end

function M.set_input_pin_channel(track, fx, pin, channel)
  if not r.TrackFX_SetPinMappings then return false end
  local low, high = M.pin_mask(channel)
  return r.TrackFX_SetPinMappings(track, fx, 0, pin, low, high) ~= false
end

return M
