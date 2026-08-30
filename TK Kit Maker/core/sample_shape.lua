local M = {}

local SHOT_WORDS = { "one shot", "oneshot", "one shots", "oneshots", "os", "hit", "hits", "stab", "stabs", "single", "shot", "shots" }
local LOOP_WORDS = { "loop", "loops", "looped", "break", "breaks", "breakbeat", "groove", "grooves", "riff", "riffs", "phrase", "phrases", "pattern", "patterns", "construction", "fill", "fills" }
local FX_WORDS = { "impact", "stinger", "riser", "uplifter", "downlifter", "whoosh", "sweep", "transition", "boom", "braam", "slam", "drop" }
local INSTRUMENTS = {
  { "kick", "kicks", "bd", "808", "808s", "bass", "sub", "subbass" },
  { "snare", "snares", "sd", "rimshot", "rimshots" },
  { "clap", "claps" },
  { "hihat", "hihats", "hat", "hats", "openhat", "closedhat", "hh" },
  { "tom", "toms" },
  { "crash", "ride", "cymbal", "cymbals" },
  { "rim", "clave", "claves", "cowbell", "shaker", "tambourine", "conga", "congas", "bongo", "bongos", "block" },
  { "perc", "percussion" },
  { "snap", "snaps", "stick", "sticks" },
}
local NO_SUBSTRING = { ride=true, hat=true, hats=true, tom=true, toms=true, sub=true, rim=true, sd=true, bd=true, os=true, block=true }

local function normalise(text)
  return " " .. tostring(text or ""):lower():gsub("[_%-%.%(%)%[%]/\\]", " "):gsub("%s+", " ") .. " "
end

local function has_word(text, words)
  for _, word in ipairs(words) do
    if text:find(" " .. word .. " ", 1, true) then return word end
  end
  return nil
end

local function has_part(text, words)
  for _, word in ipairs(words) do
    if text:find(" " .. word .. " ", 1, true) then return word end
    if #word >= 3 and not NO_SUBSTRING[word] then
      local numeric = word:match("^%d+$") ~= nil
      local from = 1
      while true do
        local starts, ends = text:find(word, from, true)
        if not starts then break end
        if not numeric then return word end
        local before = starts > 1 and text:sub(starts - 1, starts - 1) or " "
        local after = ends < #text and text:sub(ends + 1, ends + 1) or " "
        if before == " " and not after:match("%d") then return word end
        from = starts + 1
      end
    end
  end
  return nil
end

local function count_instruments(text)
  local found, first = 0, nil
  for _, group in ipairs(INSTRUMENTS) do
    local word = has_part(text, group)
    if word then
      found = found + 1
      first = first or word
    end
  end
  return found, first
end

local function has_tempo(text)
  if text:find("%d%s*bpm") then return true end
  local tokens = {}
  for token in text:gmatch("%S+") do tokens[#tokens + 1] = token end
  if #tokens == 0 then return false end
  local last = tokens[#tokens]
  local counting = last:match("^%a%a?%a?%a?$") and #tokens > 1 and (#tokens - 1) or #tokens
  for index, token in ipairs(tokens) do
    local value = tonumber(token)
    if value and #token >= 2 and value >= 60 and value <= 200 and index ~= counting then return true end
  end
  return false
end

function M.from_text(name, folder)
  local in_name = normalise(name)
  local in_folder = normalise(folder)
  local word = has_word(in_name, SHOT_WORDS)
  if word then return "oneshot", "name says " .. word end
  word = has_word(in_name, LOOP_WORDS)
  if word then return "loop", "name says " .. word end
  local instruments, instrument = count_instruments(in_name)
  if instruments >= 2 then return "loop", string.format("names %d instruments", instruments) end
  if has_tempo(in_name) then return "loop", "tempo in name" end
  word = has_word(in_folder, SHOT_WORDS)
  if word then return "oneshot", "folder says " .. word end
  word = has_word(in_folder, LOOP_WORDS)
  if word then return "loop", "folder says " .. word end
  if has_tempo(in_folder) then return "loop", "tempo in folder" end
  word = has_word(in_name, FX_WORDS)
  if word then return "oneshot", word .. " is a single gesture" end
  if instruments == 1 then return "oneshot", instrument .. " alone, no loop marking" end
  return nil
end

function M.from_bars(seconds, bpm)
  seconds = tonumber(seconds) or 0
  bpm = tonumber(bpm) or 0
  if seconds < 1 or bpm < 40 or bpm > 300 then return nil end
  local beats = seconds * bpm / 60
  if beats < 4 then return nil end
  local nearest = math.floor(beats + 0.5)
  if math.abs(beats - nearest) / nearest > 0.015 then return nil end
  return "loop", string.format("%d beats at %g BPM", nearest, bpm)
end

function M.measure_envelope(amps, rate, seconds, work, used)
  local count = math.min(#(amps or {}), tonumber(used) or math.huge)
  if count < 64 or not rate or rate <= 0 then return nil end
  work = work or {}
  local peak = 0
  for index = 1, count do
    local value = math.abs(amps[index] or 0)
    work[index] = value
    if value > peak then peak = value end
  end
  if peak <= 0.001 then return nil end
  local release_columns = math.max(2, math.min(count / 8, rate * 0.05))
  local release = math.exp(-1 / release_columns)
  local level = 0
  for index = 1, count do
    local value = work[index]
    level = value > level and value or level * release + value * (1 - release)
    work[index] = level
  end
  local window = math.max(4, math.floor(count / 48), math.floor(rate * 0.08))
  window = math.min(window, math.floor(count / 6))
  local onsets, last_onset, previous = 0, -count, nil
  local gaps, gap_total, gap_list = 0, 0, {}
  local opening = 0
  for index = 1, window do opening = math.max(opening, work[index]) end
  if opening >= peak * 0.5 then onsets, previous, last_onset = 1, 1, 1 end
  for index = 2, count do
    if work[index] > peak * 0.2 and work[index] - work[index - 1] > peak * 0.22 and index - last_onset > window then
      onsets = onsets + 1
      if previous then
        gaps = gaps + 1
        gap_list[gaps] = index - previous
        gap_total = gap_total + gap_list[gaps]
      end
      previous = index
      last_onset = index
    end
  end
  local quarter = math.max(1, math.floor(count / 4))
  local head, tail = 0, 0
  for index = 1, quarter do head = head + work[index] end
  for index = count - quarter + 1, count do tail = tail + work[index] end
  local sustain = head > 0 and (tail / quarter) / (head / quarter) or 0
  local regular = false
  if gaps >= 2 then
    local mean = gap_total / gaps
    local variance = 0
    for index = 1, gaps do variance = variance + (gap_list[index] - mean) ^ 2 end
    regular = mean > 0 and math.sqrt(variance / gaps) / mean <= 0.4
  end
  return { onsets = onsets, spread = last_onset >= count * 0.5, regular = regular, sustain = sustain, seconds = seconds }
end

function M.from_shape(shape)
  if not shape then return nil end
  local onsets = tonumber(shape.onsets) or 0
  local sustain = tonumber(shape.sustain) or 0
  if onsets == 1 and sustain <= 0.5 then return "oneshot", "one attack, however long it rings", true end
  if onsets == 1 then return "oneshot", "one attack, level held", false end
  if onsets >= 3 and shape.spread and (shape.regular or sustain >= 0.45) then
    return "loop", string.format("%d attacks%s", onsets, shape.regular and ", evenly spaced" or ""), true
  end
  if onsets >= 3 and not shape.spread then return "oneshot", string.format("%d attacks, all at the start", onsets), true end
  if onsets >= 3 then return "oneshot", string.format("%d ragged attacks, then gone", onsets), false end
  if onsets == 2 then
    if sustain >= 0.6 then return "loop", "two attacks, level held", false end
    return "oneshot", "two attacks, then gone", false
  end
  if sustain >= 0.6 then return "loop", "sustained to the end", false end
  if sustain <= 0.25 then return "oneshot", "fades away, no repeat", false end
  return nil
end

local function path_parts(path)
  local clean = tostring(path or ""):gsub("\\", "/")
  return clean:match("([^/]+)$") or clean, clean:match("([^/]+)/[^/]+$") or ""
end

function M.classify(path, metrics)
  local shape = metrics and metrics.shape or nil
  local shape_kind, shape_why, decisive = M.from_shape(shape)
  if shape_kind and decisive then return shape_kind, shape_why end
  local bar_kind, bar_why = M.from_bars(metrics and metrics.dur, metrics and metrics.bpm)
  if bar_kind then return bar_kind, bar_why end
  local name, folder = path_parts(path)
  local text_kind, text_why = M.from_text(name, folder)
  if text_kind then return text_kind, text_why end
  if shape_kind then return shape_kind, shape_why end
  return "unknown", "nothing to go on"
end

function M.matches(path, mode, metrics, include_unknown)
  if mode ~= "loop" and mode ~= "oneshot" then return true end
  local kind = M.classify(path, metrics)
  return kind == mode or (include_unknown == true and kind == "unknown")
end

return M
