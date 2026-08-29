local Engine = {}

local SHARP_NAMES = { "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B" }
local FLAT_NAMES = { "C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B" }

local FORMS = {
  { id = "major", suffix = "", tones = { 0, 4, 7 }, anchors = { 0, 4 }, order = 10 },
  { id = "minor", suffix = "m", tones = { 0, 3, 7 }, anchors = { 0, 3 }, order = 11 },
  { id = "power", suffix = "5", tones = { 0, 7 }, anchors = { 0, 7 }, order = 80 },
  { id = "sus2", suffix = "sus2", tones = { 0, 2, 7 }, anchors = { 0, 2 }, order = 30 },
  { id = "sus4", suffix = "sus4", tones = { 0, 5, 7 }, anchors = { 0, 5 }, order = 31 },
  { id = "diminished", suffix = "dim", tones = { 0, 3, 6 }, anchors = { 0, 3, 6 }, order = 20 },
  { id = "augmented", suffix = "aug", tones = { 0, 4, 8 }, anchors = { 0, 4, 8 }, order = 21 },
  { id = "sixth", suffix = "6", tones = { 0, 4, 7, 9 }, anchors = { 0, 4, 9 }, order = 40 },
  { id = "minor_sixth", suffix = "m6", tones = { 0, 3, 7, 9 }, anchors = { 0, 3, 9 }, order = 41 },
  { id = "dominant_seventh", suffix = "7", tones = { 0, 4, 7, 10 }, anchors = { 0, 4, 10 }, order = 42 },
  { id = "major_seventh", suffix = "maj7", tones = { 0, 4, 7, 11 }, anchors = { 0, 4, 11 }, order = 43 },
  { id = "minor_seventh", suffix = "m7", tones = { 0, 3, 7, 10 }, anchors = { 0, 3, 10 }, order = 44 },
  { id = "minor_major_seventh", suffix = "m(maj7)", tones = { 0, 3, 7, 11 }, anchors = { 0, 3, 11 }, order = 45 },
  { id = "half_diminished", suffix = "m7b5", tones = { 0, 3, 6, 10 }, anchors = { 0, 3, 6, 10 }, order = 46 },
  { id = "diminished_seventh", suffix = "dim7", tones = { 0, 3, 6, 9 }, anchors = { 0, 3, 6 }, order = 47 },
  { id = "augmented_seventh", suffix = "aug7", tones = { 0, 4, 8, 10 }, anchors = { 0, 4, 8, 10 }, order = 48 },
  { id = "augmented_major_seventh", suffix = "aug(maj7)", tones = { 0, 4, 8, 11 }, anchors = { 0, 4, 8, 11 }, order = 49 },
  { id = "add_ninth", suffix = "add9", tones = { 0, 2, 4, 7 }, anchors = { 0, 2, 4 }, order = 50 },
  { id = "minor_add_ninth", suffix = "m(add9)", tones = { 0, 2, 3, 7 }, anchors = { 0, 2, 3 }, order = 51 },
  { id = "six_nine", suffix = "6/9", tones = { 0, 2, 4, 7, 9 }, anchors = { 0, 4, 9 }, order = 52 },
  { id = "minor_six_nine", suffix = "m6/9", tones = { 0, 2, 3, 7, 9 }, anchors = { 0, 3, 9 }, order = 53 },
  { id = "dominant_ninth", suffix = "9", tones = { 0, 2, 4, 7, 10 }, anchors = { 0, 4, 10 }, order = 54 },
  { id = "major_ninth", suffix = "maj9", tones = { 0, 2, 4, 7, 11 }, anchors = { 0, 4, 11 }, order = 55 },
  { id = "minor_ninth", suffix = "m9", tones = { 0, 2, 3, 7, 10 }, anchors = { 0, 3, 10 }, order = 56 },
  { id = "dominant_flat_ninth", suffix = "7b9", tones = { 0, 1, 4, 7, 10 }, anchors = { 0, 1, 4, 10 }, order = 57 },
  { id = "dominant_sharp_ninth", suffix = "7#9", tones = { 0, 3, 4, 7, 10 }, anchors = { 0, 3, 4, 10 }, order = 58 },
  { id = "dominant_sharp_eleventh", suffix = "7#11", tones = { 0, 4, 6, 7, 10 }, anchors = { 0, 4, 6, 10 }, order = 59 },
  { id = "dominant_nine_sharp_eleventh", suffix = "9#11", tones = { 0, 2, 4, 6, 7, 10 }, anchors = { 0, 4, 6, 10 }, order = 60 },
  { id = "dominant_eleventh", suffix = "11", tones = { 0, 2, 4, 5, 7, 10 }, anchors = { 0, 4, 5, 10 }, order = 61 },
  { id = "minor_eleventh", suffix = "m11", tones = { 0, 2, 3, 5, 7, 10 }, anchors = { 0, 3, 5, 10 }, order = 62 },
  { id = "major_nine_sharp_eleventh", suffix = "maj9#11", tones = { 0, 2, 4, 6, 7, 11 }, anchors = { 0, 4, 6, 11 }, order = 63 },
  { id = "dominant_thirteenth", suffix = "13", tones = { 0, 2, 4, 7, 9, 10 }, anchors = { 0, 4, 9, 10 }, order = 64 },
  { id = "major_thirteenth", suffix = "maj13", tones = { 0, 2, 4, 7, 9, 11 }, anchors = { 0, 4, 9, 11 }, order = 65 },
  { id = "minor_thirteenth", suffix = "m13", tones = { 0, 2, 3, 7, 9, 10 }, anchors = { 0, 3, 9, 10 }, order = 66 },
  { id = "thirteen_flat_nine", suffix = "13b9", tones = { 0, 1, 4, 7, 9, 10 }, anchors = { 0, 1, 4, 9, 10 }, order = 67 },
  { id = "thirteen_sharp_nine", suffix = "13#9", tones = { 0, 3, 4, 7, 9, 10 }, anchors = { 0, 3, 4, 9, 10 }, order = 68 },
  { id = "thirteen_sharp_eleven", suffix = "13#11", tones = { 0, 2, 4, 6, 7, 9, 10 }, anchors = { 0, 4, 6, 9, 10 }, order = 69 },
  { id = "seven_sus_four", suffix = "7sus4", tones = { 0, 5, 7, 10 }, anchors = { 0, 5, 10 }, order = 70 },
  { id = "major_seven_no_five", suffix = "maj7(no5)", tones = { 0, 4, 11 }, anchors = { 0, 4, 11 }, order = 90 },
  { id = "minor_seven_no_five", suffix = "m7(no5)", tones = { 0, 3, 10 }, anchors = { 0, 3, 10 }, order = 91 },
  { id = "dominant_seven_no_five", suffix = "7(no5)", tones = { 0, 4, 10 }, anchors = { 0, 4, 10 }, order = 92 },
  { id = "major_nine_no_five", suffix = "maj9(no5)", tones = { 0, 2, 4, 11 }, anchors = { 0, 4, 11 }, order = 93 },
  { id = "minor_nine_no_five", suffix = "m9(no5)", tones = { 0, 2, 3, 10 }, anchors = { 0, 3, 10 }, order = 94 },
  { id = "dominant_nine_no_five", suffix = "9(no5)", tones = { 0, 2, 4, 10 }, anchors = { 0, 4, 10 }, order = 95 }
}

local function pitch_value(value)
  if type(value) == "table" then value = value.pitch or value.note end
  value = tonumber(value)
  if not value then return nil end
  return math.floor(value + 0.5)
end

local function prepare_input(values)
  local pitches = {}
  for _, value in ipairs(type(values) == "table" and values or {}) do
    local pitch = pitch_value(value)
    if pitch then pitches[#pitches + 1] = pitch end
  end
  table.sort(pitches)
  if #pitches == 0 then return nil end
  local classes, present = {}, {}
  for _, pitch in ipairs(pitches) do
    local class = pitch % 12
    if not present[class] then
      present[class] = true
      classes[#classes + 1] = class
    end
  end
  return { pitches = pitches, classes = classes, present = present, bass = pitches[1] % 12 }
end

local function shifted_set(form, root)
  local result = {}
  for _, interval in ipairs(form.tones) do result[(root + interval) % 12] = true end
  return result
end

local function set_size(values)
  local count = 0
  for _ in pairs(values) do count = count + 1 end
  return count
end

local function exact_fit(input, form, root)
  local wanted = shifted_set(form, root)
  if set_size(wanted) ~= #input.classes then return false end
  for _, class in ipairs(input.classes) do
    if not wanted[class] then return false end
  end
  return true
end

local function weigh_fit(input, form, root)
  local wanted = shifted_set(form, root)
  local matched, extra = 0, 0
  for _, class in ipairs(input.classes) do
    if wanted[class] then matched = matched + 1 else extra = extra + 1 end
  end
  local missing = #form.tones - matched
  local anchor_missing = 0
  for _, interval in ipairs(form.anchors) do
    if not input.present[(root + interval) % 12] then anchor_missing = anchor_missing + 1 end
  end
  local score = matched * 3 - missing * 1.5 - extra * 4 - anchor_missing * 4
  if input.bass == root then score = score + 2 end
  if input.present[root] then score = score + 1 end
  local confidence = matched / math.max(1, #form.tones + extra + anchor_missing * 1.5)
  return score, confidence, missing, extra, anchor_missing
end

local function note_name(class, options)
  local names = options.prefer_flats and FLAT_NAMES or SHARP_NAMES
  return names[class + 1]
end

local function make_result(input, form, root, exact, confidence, missing, extra)
  local options = input.options
  local name = note_name(root, options) .. form.suffix
  local tones = {}
  for _, interval in ipairs(form.tones) do tones[#tones + 1] = (root + interval) % 12 end
  if options.include_bass ~= false and input.bass ~= root then
    name = name .. "/" .. note_name(input.bass, options)
  end
  return {
    name = name,
    root = root,
    bass = input.bass,
    quality = form.id,
    confidence = exact and 1 or math.max(0, math.min(1, confidence)),
    exact = exact,
    missing = missing or 0,
    extra = extra or 0,
    tones = tones,
    key_root = tonumber(options.key_root),
    key_mode = options.key_mode
  }
end

local function context_bonus(root, options)
  local key_root = tonumber(options.key_root)
  local mode = tostring(options.key_mode or "")
  if not key_root or (mode ~= "major" and mode ~= "minor") then return 0 end
  local interval = (root - math.floor(key_root + 0.5)) % 12
  local weights = mode == "major"
    and { [0] = 4, [5] = 1.5, [7] = 2, [9] = 1 }
    or { [0] = 4, [3] = 1, [5] = 1.5, [7] = 2 }
  return weights[interval] or 0
end

local function better(candidate, current)
  if not current then return true end
  if candidate.score ~= current.score then return candidate.score > current.score end
  if candidate.bass_root ~= current.bass_root then return candidate.bass_root end
  if candidate.form.order ~= current.form.order then return candidate.form.order < current.form.order end
  return candidate.root < current.root
end

local function candidate_result(input, candidate)
  return make_result(input, candidate.form, candidate.root, candidate.exact,
    candidate.confidence, candidate.missing, candidate.extra)
end

local function finish(input, candidates)
  table.sort(candidates, function(left, right) return better(left, right) end)
  local best = candidates[1]
  if not best then return nil end
  local result = candidate_result(input, best)
  result.alternatives = {}
  local seen = { [result.name] = true }
  for index = 2, #candidates do
    local candidate = candidates[index]
    if candidate.exact ~= best.exact or (not best.exact and candidate.score < best.score - 2) then break end
    local alternative = candidate_result(input, candidate)
    if not seen[alternative.name] then
      seen[alternative.name] = true
      result.alternatives[#result.alternatives + 1] = {
        name = alternative.name,
        confidence = alternative.confidence
      }
      if #result.alternatives >= 3 then break end
    end
  end
  return result
end

function Engine.resolve(values, options)
  local input = prepare_input(values)
  if not input or #input.classes < 2 then return nil end
  input.options = options or {}
  local roots = {}
  local root_hint = tonumber(input.options.root_hint)
  if root_hint then
    roots[1] = math.floor(root_hint + 0.5) % 12
  elseif input.options.allow_rootless then
    for root = 0, 11 do roots[#roots + 1] = root end
  else
    for _, root in ipairs(input.classes) do roots[#roots + 1] = root end
  end

  local candidates = {}
  for _, root in ipairs(roots) do
    for _, form in ipairs(FORMS) do
      if exact_fit(input, form, root) then
        candidates[#candidates + 1] = {
          score = 1000 + context_bonus(root, input.options),
          bass_root = input.bass == root,
          form = form,
          root = root,
          exact = true,
          confidence = 1,
          missing = 0,
          extra = 0
        }
      end
    end
  end
  if #candidates > 0 then return finish(input, candidates) end

  for _, root in ipairs(roots) do
    for _, form in ipairs(FORMS) do
      local score, confidence, missing, extra, anchor_missing = weigh_fit(input, form, root)
      if anchor_missing <= (input.options.allow_rootless and 1 or 0) then
        candidates[#candidates + 1] = {
          score = score + context_bonus(root, input.options),
          bass_root = input.bass == root,
          form = form,
          root = root,
          exact = false,
          confidence = confidence,
          missing = missing,
          extra = extra
        }
      end
    end
  end
  table.sort(candidates, function(left, right) return better(left, right) end)
  local best = candidates[1]
  if not best or best.confidence < (tonumber(input.options.minimum_confidence) or 0.55) then return nil end
  local accepted = {}
  local minimum = tonumber(input.options.minimum_confidence) or 0.55
  for _, candidate in ipairs(candidates) do
    if candidate.confidence >= minimum then accepted[#accepted + 1] = candidate end
  end
  return finish(input, accepted)
end

function Engine.forms()
  local result = {}
  for index, form in ipairs(FORMS) do
    result[index] = { id = form.id, suffix = form.suffix, tones = { table.unpack(form.tones) } }
  end
  return result
end

return Engine