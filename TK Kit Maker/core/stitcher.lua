-- Stitched export for slicers (the architecture doc's "bonus later" item):
-- concatenates all exported kit samples into one WAV with embedded cue points
-- (one at the start of each slice, readable by REAPER's "import media cues"
-- and most slicers) plus a plain-text cue sheet.
--
-- Pure Lua: WAV in (PCM 8/16/24/32-bit int and 32/64-bit float), 32-bit float
-- WAV out. Sources with different sample rates are linearly resampled to the
-- highest rate among them; mono/stereo is mixed to a common channel count.
-- Non-WAV sources (mp3/flac/ogg/aif) are skipped with a warning.

local M = {}

local UNPACK_BLOCK = 256

-- --------------------------------------------------------------------------
-- WAV reading
-- --------------------------------------------------------------------------

-- Reads the fmt chunk and raw data chunk from a WAV file.
local function read_wav(path)
  local f = io.open(path, "rb")
  if not f then return nil, "cannot open file" end

  local header = f:read(12)
  if not header or #header < 12 or header:sub(1, 4) ~= "RIFF" or header:sub(9, 12) ~= "WAVE" then
    f:close()
    return nil, "not a RIFF/WAVE file"
  end

  local fmt, data
  while true do
    local chunk_header = f:read(8)
    if not chunk_header or #chunk_header < 8 then break end
    local id = chunk_header:sub(1, 4)
    local size = string.unpack("<I4", chunk_header, 5)

    if id == "fmt " then
      local body = f:read(size)
      if not body or #body < 16 then break end
      local audio_format, channels, rate, _, _, bits = string.unpack("<I2I2I4I4I2I2", body)
      if audio_format == 0xFFFE and #body >= 26 then
        -- WAVE_FORMAT_EXTENSIBLE: real format tag = first 2 bytes of SubFormat GUID
        audio_format = string.unpack("<I2", body, 25)
      end
      fmt = { format = audio_format, channels = channels, rate = rate, bits = bits }
      if size % 2 == 1 then f:seek("cur", 1) end
    elseif id == "data" then
      data = f:read(size)
      if size % 2 == 1 then f:seek("cur", 1) end
    else
      f:seek("cur", size + (size % 2))
    end

    if fmt and data then break end
  end
  f:close()

  if not fmt then return nil, "no fmt chunk found" end
  if not data or #data == 0 then return nil, "no audio data found" end
  return fmt, data
end

local SAMPLE_SPECS = {
  -- [format] = { [bits] = { pack_char, scale } }; 8-bit PCM is unsigned
  [1] = { [8] = { "B", nil }, [16] = { "i2", 32768 }, [24] = { "i3", 8388608 }, [32] = { "i4", 2147483648 } },
  [3] = { [32] = { "f", 1 }, [64] = { "d", 1 } },
}

-- Decodes raw PCM data to per-channel float arrays (max 2 channels kept).
local function decode(data, fmt)
  local spec = SAMPLE_SPECS[fmt.format] and SAMPLE_SPECS[fmt.format][fmt.bits]
  if not spec then
    return nil, string.format("unsupported format (tag %d, %d-bit)", fmt.format, fmt.bits)
  end

  local pack_char, scale = spec[1], spec[2]
  local channels = fmt.channels
  if channels < 1 then return nil, "invalid channel count" end
  local bytes_per = fmt.bits // 8
  local frames = #data // (bytes_per * channels)
  if frames == 0 then return nil, "empty audio data" end

  local total = frames * channels
  local values = {}
  local pos = 1
  local vi = 0
  while vi < total do
    local n = math.min(UNPACK_BLOCK, total - vi)
    local block = { string.unpack("<" .. pack_char:rep(n), data, pos) }
    pos = block[n + 1]
    for i = 1, n do values[vi + i] = block[i] end
    vi = vi + n
  end

  local keep = math.min(channels, 2)
  local out = {}
  for c = 1, keep do
    local ch = {}
    if pack_char == "B" then
      for i = 1, frames do ch[i] = (values[(i - 1) * channels + c] - 128) / 128 end
    elseif scale == 1 then
      for i = 1, frames do ch[i] = values[(i - 1) * channels + c] end
    else
      for i = 1, frames do ch[i] = values[(i - 1) * channels + c] / scale end
    end
    out[c] = ch
  end
  return out
end

local function resample_linear(src, src_rate, dst_rate)
  if src_rate == dst_rate then return src end
  local n = #src
  local out_n = math.max(1, math.floor(n * dst_rate / src_rate + 0.5))
  local out = {}
  if out_n == 1 or n == 1 then
    for i = 1, out_n do out[i] = src[1] end
    return out
  end
  local ratio = (n - 1) / (out_n - 1)
  for i = 1, out_n do
    local p = 1 + (i - 1) * ratio
    local i0 = math.floor(p)
    local i1 = math.min(n, i0 + 1)
    local frac = p - i0
    out[i] = src[i0] * (1 - frac) + src[i1] * frac
  end
  return out
end

-- --------------------------------------------------------------------------
-- WAV writing (32-bit float, with cue + label chunks)
-- --------------------------------------------------------------------------

local function encode_float32(left, right)
  local pieces = {}
  local n = #left
  local i = 1
  if right then
    while i <= n do
      local count = math.min(UNPACK_BLOCK, n - i + 1)
      local block = {}
      for j = 0, count - 1 do
        block[j * 2 + 1] = left[i + j]
        block[j * 2 + 2] = right[i + j]
      end
      pieces[#pieces + 1] = string.pack("<" .. ("f"):rep(count * 2), table.unpack(block))
      i = i + count
    end
  else
    while i <= n do
      local count = math.min(UNPACK_BLOCK, n - i + 1)
      pieces[#pieces + 1] = string.pack("<" .. ("f"):rep(count), table.unpack(left, i, i + count - 1))
      i = i + count
    end
  end
  return table.concat(pieces)
end

local function build_cue_chunks(cues)
  local cue_body = { string.pack("<I4", #cues) }
  for i, cue in ipairs(cues) do
    cue_body[#cue_body + 1] = string.pack("<I4I4c4I4I4I4", i, cue.offset, "data", 0, 0, cue.offset)
  end
  local cue_chunk = "cue " .. string.pack("<I4", #cue_body[1] + 24 * #cues) .. table.concat(cue_body)

  local adtl = { "adtl" }
  for i, cue in ipairs(cues) do
    local label = cue.label .. "\0"
    if #label % 2 == 1 then label = label .. "\0" end
    adtl[#adtl + 1] = "labl" .. string.pack("<I4", 4 + #cue.label + 1) .. string.pack("<I4", i) .. label
  end
  local adtl_body = table.concat(adtl)
  local list_chunk = "LIST" .. string.pack("<I4", #adtl_body) .. adtl_body

  return cue_chunk .. list_chunk
end

local function write_wav(path, rate, channels, audio_data, frames, cues)
  local fmt_chunk = "fmt " .. string.pack("<I4I2I2I4I4I2I2", 16, 3, channels, rate, rate * channels * 4, channels * 4, 32)
  local fact_chunk = "fact" .. string.pack("<I4I4", 4, frames)
  local data_chunk = "data" .. string.pack("<I4", #audio_data) .. audio_data
  if #audio_data % 2 == 1 then data_chunk = data_chunk .. "\0" end
  local extra_chunks = build_cue_chunks(cues)

  local body = "WAVE" .. fmt_chunk .. fact_chunk .. data_chunk .. extra_chunks
  local f = io.open(path, "wb")
  if not f then return nil, "cannot write " .. path end
  f:write("RIFF" .. string.pack("<I4", #body) .. body)
  f:close()
  return true
end

local function write_cue_sheet(path, kit_name, rate, cues)
  local f = io.open(path, "w")
  if not f then return end
  f:write("Kit: " .. kit_name .. "\nSample rate: " .. rate .. "\n\n")
  f:write(string.format("%-4s %-12s %-12s %s\n", "#", "Start (smp)", "Start (sec)", "Slice"))
  for i, cue in ipairs(cues) do
    f:write(string.format("%-4d %-12d %-12.4f %s\n", i, cue.offset, cue.offset / rate, cue.label))
  end
  f:close()
end

-- --------------------------------------------------------------------------
-- Public API
-- --------------------------------------------------------------------------

-- Returns the duration in seconds from an fmt chunk + raw data size, without
-- decoding any audio (cheap length check for max_seconds).
local function wav_duration(fmt, data)
  local frame_bytes = (fmt.bits // 8) * fmt.channels
  if frame_bytes <= 0 or fmt.rate <= 0 then return 0 end
  return (#data // frame_bytes) / fmt.rate
end

-- Stitches the exported kit samples (results from Engine.generate_kit, in
-- slot order) into "<kit> - Stitched.wav" with embedded cue points, plus a
-- "<kit> - Cues.txt" sheet. Returns the stitched path and a warnings list.
-- max_seconds (optional): slices longer than this are left out (0/nil = no limit).
function M.stitch_kit(dest_dir, kit_name, results, max_seconds)
  local warnings = {}
  local decoded = {}
  local target_rate = 0
  local target_channels = 1
  local length_limit = (max_seconds and max_seconds > 0) and max_seconds or nil

  for _, res in ipairs(results) do
    local path = dest_dir .. "/" .. res.out_name
    if not res.out_name:lower():match("%.wav$") then
      warnings[#warnings + 1] = res.out_name .. ": skipped (only WAV supported for stitching)"
    else
      local fmt, data = read_wav(path)
      if not fmt then
        warnings[#warnings + 1] = res.out_name .. ": skipped (" .. data .. ")"
      elseif length_limit and wav_duration(fmt, data) > length_limit then
        warnings[#warnings + 1] = string.format("%s: skipped (too long: %.1fs > %.1fs)",
          res.out_name, wav_duration(fmt, data), length_limit)
      else
        local channels, err = decode(data, fmt)
        if not channels then
          warnings[#warnings + 1] = res.out_name .. ": skipped (" .. err .. ")"
        else
          decoded[#decoded + 1] = { name = res.out_name, rate = fmt.rate, channels = channels }
          if fmt.rate > target_rate then target_rate = fmt.rate end
          if #channels > 1 then target_channels = 2 end
        end
      end
    end
  end

  if #decoded == 0 then
    return nil, "no stitchable WAV files in kit", warnings
  end

  local left_parts, right_parts = {}, {}
  local cues = {}
  local offset = 0

  for _, item in ipairs(decoded) do
    local left = resample_linear(item.channels[1], item.rate, target_rate)
    local right
    if target_channels == 2 then
      right = item.channels[2] and resample_linear(item.channels[2], item.rate, target_rate) or left
    end

    cues[#cues + 1] = { offset = offset, label = (item.name:gsub("%.[%w]+$", "")) }
    left_parts[#left_parts + 1] = left
    if right then right_parts[#right_parts + 1] = right end
    offset = offset + #left
  end

  local left_all, right_all = {}, nil
  for _, part in ipairs(left_parts) do
    for i = 1, #part do left_all[#left_all + 1] = part[i] end
  end
  if target_channels == 2 then
    right_all = {}
    for _, part in ipairs(right_parts) do
      for i = 1, #part do right_all[#right_all + 1] = part[i] end
    end
  end

  local audio_data = encode_float32(left_all, right_all)
  local out_path = dest_dir .. "/" .. kit_name .. " - Stitched.wav"
  local ok, err = write_wav(out_path, target_rate, target_channels, audio_data, #left_all, cues)
  if not ok then return nil, err, warnings end

  write_cue_sheet(dest_dir .. "/" .. kit_name .. " - Cues.txt", kit_name, target_rate, cues)
  return out_path, nil, warnings
end

return M
