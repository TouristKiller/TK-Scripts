-- Reading cue points out of a WAV.
--
-- Cutting a file into equal pieces assumes the pieces ARE equal, which is true
-- of a drum loop and false of almost anything else. A stitched kit is the clear
-- case: sixteen one-shots end to end, a 400 ms kick beside an 80 ms hat. Sliced
-- into sixteen equal parts, not one cut lands on a boundary.
--
-- But those boundaries are not a guess -- they are written into the file. Kit
-- Maker's own stitcher puts a cue at the start of every slice, and so do most
-- sliced-loop packs and anything exported from a slicer. Reading them back
-- makes the round trip exact: stitch a kit into one file, slice it back onto
-- the pads, and every pad holds what it held before.
--
-- Only the chunks that matter are read. Everything else in a RIFF file is
-- skipped by its declared length, which is what makes this safe on formats
-- that have grown chunks nobody here has heard of.

local M = {}

local function u32(s, p)
  local a, b, c, d = s:byte(p, p + 3)
  if not d then return nil end
  return a + b * 256 + c * 65536 + d * 16777216   -- RIFF is little-endian
end

local function u16(s, p)
  local a, b = s:byte(p, p + 1)
  if not b then return nil end
  return a + b * 256
end

-- Reads only the header and chunk table, never the audio: a stitched kit can be
-- tens of megabytes and none of it is needed to find where the cuts are.
--
-- Chunks are walked rather than assumed to be in any order, because they are
-- not: the cue chunk is written after the audio by some tools and before it by
-- others, and 'fmt ' is only conventionally first.
function M.read(path)
  local f = io.open(path, "rb")
  if not f then return nil, "cannot open the file" end

  local head = f:read(12) or ""
  if #head < 12 or head:sub(1, 4) ~= "RIFF" or head:sub(9, 12) ~= "WAVE" then
    f:close()
    return nil, "not a WAV file"
  end

  local rate, channels, bits, data_bytes
  local cues = {}
  local labels = {}

  while true do
    local hdr = f:read(8)
    if not hdr or #hdr < 8 then break end
    local id = hdr:sub(1, 4)
    local size = u32(hdr, 5)
    if not size then break end
    -- RIFF chunks are padded to an even length, and forgetting that puts every
    -- later chunk one byte out.
    local padded = size + (size % 2)

    if id == "fmt " then
      local body = f:read(size) or ""
      channels = u16(body, 3)
      rate = u32(body, 5)
      bits = u16(body, 15)
    elseif id == "data" then
      data_bytes = size
      f:seek("cur", padded)
    elseif id == "cue " then
      local body = f:read(size) or ""
      local n = u32(body, 1) or 0
      for i = 1, n do
        -- Each cue point is 24 bytes; the play-order position sits at the end
        -- and is the one that means "this many frames into the audio".
        local base = 5 + (i - 1) * 24
        local id_num = u32(body, base)
        local pos = u32(body, base + 20)
        if pos then cues[#cues + 1] = { id = id_num, frame = pos } end
      end
      if size % 2 == 1 then f:seek("cur", 1) end
    elseif id == "LIST" then
      local body = f:read(size) or ""
      if body:sub(1, 4) == "adtl" then
        local p = 5
        while p + 8 <= #body do
          local sub = body:sub(p, p + 3)
          local ssize = u32(body, p + 4) or 0
          if sub == "labl" then
            local cue_id = u32(body, p + 8)
            local text = body:sub(p + 12, p + 8 + ssize - 1):gsub("%z.*$", "")
            if cue_id then labels[cue_id] = text end
          end
          p = p + 8 + ssize + (ssize % 2)
        end
      end
      if size % 2 == 1 then f:seek("cur", 1) end
    else
      f:seek("cur", padded)
    end
  end
  f:close()

  if not rate or rate <= 0 then return nil, "the WAV header is unreadable" end
  if #cues == 0 then return nil, "this file has no cue points" end

  local frames = nil
  if data_bytes and channels and bits and channels > 0 and bits > 0 then
    frames = math.floor(data_bytes / (channels * (bits / 8)))
  end

  for _, c in ipairs(cues) do c.label = labels[c.id] end
  table.sort(cues, function(a, b) return a.frame < b.frame end)

  return {
    rate = rate,
    channels = channels,
    frames = frames,
    duration = frames and (frames / rate) or nil,
    cues = cues,
  }
end

-- Just the answer to "is this worth offering", without keeping anything.
function M.count(path)
  local info = M.read(path)
  return info and #info.cues or 0
end

return M
