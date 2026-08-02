-- Shared channel layout helpers for multichannel routing and metering.
--
-- REAPER encodes send width in I_SRCCHAN: the low 10 bits hold the first
-- channel, the higher bits hold a width code where 0 = stereo, 1 = mono,
-- 2 = 4 channels, 3 = 6 channels, 4 = 8 channels and so on.
-- I_DSTCHAN has no width field: the destination width follows the source.

local M = {}

M.channel_mask = 0x3FF
M.width_shift = 10

-- Power weights follow ITU-R BS.1770-4: 1.0 for front channels, 1.41 for
-- surround and back channels, LFE excluded from the loudness sum.
local SURROUND_WEIGHT = 1.41

-- Listed in the order the setup UI offers them.
M.layouts = {
  { id = "stereo", label = "Stereo", channels = 2, code = 0, speakers = { "L", "R" }, weights = { 1, 1 } },
  { id = "mono", label = "Mono", channels = 1, code = 1, speakers = { "M" }, weights = { 1 } },
  { id = "quad", label = "Quad", channels = 4, code = 2, speakers = { "L", "R", "Ls", "Rs" }, weights = { 1, 1, SURROUND_WEIGHT, SURROUND_WEIGHT } },
  { id = "surround_51", label = "5.1", channels = 6, code = 3, speakers = { "L", "R", "C", "LFE", "Ls", "Rs" }, weights = { 1, 1, 1, 0, SURROUND_WEIGHT, SURROUND_WEIGHT } },
  { id = "surround_71", label = "7.1", channels = 8, code = 4, speakers = { "L", "R", "C", "LFE", "Ls", "Rs", "Lb", "Rb" }, weights = { 1, 1, 1, 0, SURROUND_WEIGHT, SURROUND_WEIGHT, SURROUND_WEIGHT, SURROUND_WEIGHT } }
}

-- Index passed to the meter and downmix JSFX so they know which pin is LFE.
M.jsfx_layout_index = { mono = 0, stereo = 1, quad = 2, surround_51 = 3, surround_71 = 4 }

M.default_id = "stereo"

local by_id = {}
local by_code = {}
local by_channels = {}
for _, layout in ipairs(M.layouts) do
  by_id[layout.id] = layout
  by_code[layout.code] = layout
  by_channels[layout.channels] = layout
end

local function generic_layout(channels)
  channels = math.max(1, math.floor(tonumber(channels) or 2))
  local speakers = {}
  local weights = {}
  for index = 1, channels do
    speakers[index] = tostring(index)
    weights[index] = 1
  end
  return {
    id = "ch" .. tostring(channels),
    label = tostring(channels) .. " ch",
    channels = channels,
    code = channels == 1 and 1 or (channels == 2 and 0 or math.floor(channels / 2)),
    speakers = speakers,
    weights = weights,
    generic = true
  }
end

function M.by_id(id)
  return by_id[tostring(id or "")] or nil
end

function M.by_code(code)
  code = math.floor(tonumber(code) or 0)
  if by_code[code] then return by_code[code] end
  local channels = code == 0 and 2 or (code == 1 and 1 or code * 2)
  return generic_layout(channels)
end

function M.by_channels(channels)
  channels = math.floor(tonumber(channels) or 2)
  return by_channels[channels] or generic_layout(channels)
end

function M.speaker(layout, index)
  if type(layout) == "string" then layout = M.by_id(layout) end
  if not layout then return tostring((tonumber(index) or 0) + 1) end
  return layout.speakers[(tonumber(index) or 0) + 1] or tostring((tonumber(index) or 0) + 1)
end

-- Layouts that fit inside a track or device with `available` channels.
function M.fitting(available)
  available = math.max(1, math.floor(tonumber(available) or 2))
  local result = {}
  for _, layout in ipairs(M.layouts) do
    if layout.channels <= available then result[#result + 1] = layout end
  end
  if #result == 0 then result[#result + 1] = by_id["mono"] end
  return result
end

-- Base channel offsets a layout can start on. Mono can start anywhere, wider
-- layouts follow REAPER's routing dialog and step in pairs.
function M.offsets(available, layout)
  available = math.max(1, math.floor(tonumber(available) or 2))
  if type(layout) == "string" then layout = M.by_id(layout) end
  if not layout then return { 0 } end
  local step = layout.channels == 1 and 1 or 2
  local offsets = {}
  local channel = 0
  while channel + layout.channels <= available do
    offsets[#offsets + 1] = channel
    channel = channel + step
  end
  if #offsets == 0 then offsets[1] = 0 end
  return offsets
end

function M.encode_src(channel, layout)
  if type(layout) == "string" then layout = M.by_id(layout) end
  channel = math.max(0, math.floor(tonumber(channel) or 0)) & M.channel_mask
  local code = layout and layout.code or 0
  return channel | (code << M.width_shift)
end

-- Returns channel, layout. A raw value below zero means "no audio send".
function M.decode_src(raw)
  raw = math.floor(tonumber(raw) or 0)
  if raw < 0 then return -1, nil end
  return raw & M.channel_mask, M.by_code(raw >> M.width_shift)
end

-- Human readable channel span, e.g. "1 / 2" for stereo or "1-6" for 5.1.
function M.channel_span(channel, layout)
  if type(layout) == "string" then layout = M.by_id(layout) end
  channel = math.max(0, math.floor(tonumber(channel) or 0))
  local count = layout and layout.channels or 2
  if count <= 1 then return tostring(channel + 1) end
  if count == 2 then return tostring(channel + 1) .. " / " .. tostring(channel + 2) end
  return tostring(channel + 1) .. "-" .. tostring(channel + count)
end

return M
