-- A small WAV reader, so the cue sounds never depend on anything else reading
-- them for us.
--
-- JSFX resolves its filename: declarations against its own Effects folder, so
-- an absolute path to somebody's sounds folder simply never opens - which looks
-- from the outside exactly like a file that will not play. Reading the file
-- here and handing the samples over through gmem removes the question: no
-- paths cross the boundary, only numbers.
--
-- Mono, because a cue is a tick and stereo doubles the transfer for nothing.

local Wav = {}

local function read_all(path)
  local file = io.open(path, "rb")
  if not file then return nil, "could not open the file" end
  local body = file:read("*a")
  file:close()
  return body
end

-- Returns { rate, frames, samples = { ... } } or nil plus a reason. Frames are
-- floats in -1..1, already mixed down to one channel.
--
-- opts.max_frames stops the read early: a cue is a tick, and someone will drop
-- a four minute bounce in that folder eventually.
function Wav.read(path, opts)
  opts = opts or {}
  local body, err = read_all(path)
  if not body then return nil, err end
  if #body < 44 then return nil, "too short to be a wav" end
  if body:sub(1, 4) ~= "RIFF" or body:sub(9, 12) ~= "WAVE" then
    return nil, "not a RIFF wav file"
  end

  local format, channels, rate, bits
  local data_start, data_len
  local pos = 13
  while pos + 8 <= #body do
    local id = body:sub(pos, pos + 3)
    local size = string.unpack("<I4", body, pos + 4)
    local payload = pos + 8
    if id == "fmt " and size >= 16 then
      format, channels, rate = string.unpack("<I2<I2<I4", body, payload)
      bits = string.unpack("<I2", body, payload + 14)
    elseif id == "data" then
      data_start = payload
      data_len = math.min(size, #body - payload + 1)
    end
    -- RIFF chunks are padded to even lengths, and a reader that forgets that
    -- lands one byte into the next chunk header and sees nothing but rubbish.
    pos = payload + size + (size % 2)
  end

  if not format or not data_start then return nil, "no fmt or data chunk" end
  if channels < 1 then return nil, "no channels" end
  if format ~= 1 and format ~= 3 and format ~= 0xFFFE then
    return nil, "compressed wav files are not supported"
  end
  if format == 3 and bits ~= 32 then return nil, "only 32 bit float wav is supported" end
  if format ~= 3 and bits ~= 8 and bits ~= 16 and bits ~= 24 and bits ~= 32 then
    return nil, tostring(bits) .. " bit wav is not supported"
  end

  local bytes = bits // 8
  local frame_bytes = bytes * channels
  local frames = math.floor(data_len / frame_bytes)
  local limit = tonumber(opts.max_frames)
  if limit and frames > limit then frames = math.floor(limit) end

  local samples = {}
  local scale
  if format == 3 then scale = 1
  elseif bits == 8 then scale = 128
  elseif bits == 16 then scale = 32768
  elseif bits == 24 then scale = 8388608
  else scale = 2147483648 end

  local offset = data_start
  for frame = 1, frames do
    local total = 0
    for channel = 1, channels do
      local at = offset + (channel - 1) * bytes
      local value
      if format == 3 then
        value = string.unpack("<f", body, at)
      elseif bits == 8 then
        -- 8 bit wav is unsigned, which is the one place this format still
        -- surprises people.
        value = (string.unpack("<I1", body, at) - 128) / scale
      elseif bits == 16 then
        value = string.unpack("<i2", body, at) / scale
      elseif bits == 24 then
        value = string.unpack("<i3", body, at) / scale
      else
        value = string.unpack("<i4", body, at) / scale
      end
      total = total + value
    end
    samples[frame] = total / channels
    offset = offset + frame_bytes
  end

  return { rate = rate, frames = frames, samples = samples }
end

return Wav
