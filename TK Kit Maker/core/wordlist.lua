-- Random two-word kit name generator, used when a KitDef has no name_prefix.

local M = {}

local words = nil
local descriptors = nil
local nouns = nil
local first_words = nil
local second_words = nil
local third_words = nil

local KNOWN_DESCRIPTORS = {
  funky=true, blue=true, hot=true, wild=true, neon=true, broken=true, golden=true, dusty=true, electric=true, quiet=true,
  loud=true, crooked=true, smooth=true, rough=true, vintage=true, modern=true, analog=true, digital=true, midnight=true,
  frozen=true, burning=true, lazy=true, sharp=true, muddy=true, crispy=true, deep=true, shallow=true, purple=true,
  cosmic=true, lunar=true, solar=true, groovy=true, sleazy=true, swanky=true, snappy=true, bouncy=true, wobbly=true,
  jagged=true, silky=true, fuzzy=true, gritty=true, hazy=true, slick=true, bold=true, sour=true, bitter=true, sweet=true,
  salty=true, spicy=true,
}

local KNOWN_NOUNS = {
  bottle=true, lobster=true, summer=true, static=true, rust=true, velvet=true, sunday=true, copper=true, silver=true,
  iron=true, paper=true, neptune=true, meteor=true, nebula=true, orbit=true, galaxy=true, rocket=true, comet=true,
  tiger=true, panther=true, falcon=true, raven=true, cobra=true, mammoth=true, walrus=true, gecko=true, badger=true,
  octopus=true, panda=true, wolf=true, bison=true, heron=true, moth=true, firefly=true, cactus=true, bamboo=true,
  willow=true, clover=true, thorn=true, moss=true, fern=true, tundra=true, canyon=true, lagoon=true, glacier=true,
  volcano=true, monsoon=true, thunder=true, drizzle=true, fog=true, blizzard=true, ember=true, smoke=true, chrome=true,
  marble=true, concrete=true, plastic=true, rubber=true, denim=true, leather=true, satin=true, pixel=true, vector=true,
  laser=true, turbo=true, nitro=true, hyper=true, mango=true, papaya=true, guava=true, lychee=true, plum=true, cherry=true,
  melon=true, citrus=true, cocoa=true, espresso=true, caramel=true, butter=true, biscuit=true, waffle=true, noodle=true,
  pickle=true, pretzel=true, nugget=true, tofu=true, wasabi=true, disco=true, voodoo=true, mojo=true, bandit=true,
  maverick=true, nomad=true, pirate=true, samurai=true, ninja=true, wizard=true, goblin=true, yeti=true, phantom=true,
  mirage=true, echo=true, vertigo=true, zenith=true, quartz=true, onyx=true, jade=true, cobalt=true, crimson=true,
  indigo=true, scarlet=true, magenta=true, teal=true, ochre=true, ivory=true, obsidian=true,
}

local function default_words()
  return {
    "Funky", "Blue", "Bottle", "Lobster", "Hot", "Summer", "Wild", "Static",
    "Neon", "Rust", "Velvet", "Broken", "Golden", "Dusty", "Electric", "Quiet",
  }
end

local function load_list(path)
  local out = {}
  local f = io.open(path, "r")
  if not f then return out end
  for line in f:lines() do
    local word = line:gsub("%s+$", ""):gsub("^%s+", "")
    if #word > 0 then out[#out + 1] = word end
  end
  f:close()
  return out
end

local function load_words(script_path)
  if words then return words end
  words = {}
  local path = (script_path or "") .. "data/words.txt"
  local f = io.open(path, "r")
  if f then
    for line in f:lines() do
      local word = line:gsub("%s+$", ""):gsub("^%s+", "")
      if #word > 0 then words[#words + 1] = word end
    end
    f:close()
  end
  if #words == 0 then words = default_words() end
  return words
end

local function title_case(word)
  local w = tostring(word or "")
  if w == "" then return w end
  return w:sub(1, 1):upper() .. w:sub(2):lower()
end

local function is_descriptor(word)
  local w = tostring(word or ""):lower()
  if w == "" then return false end
  if KNOWN_DESCRIPTORS[w] then return true end
  if KNOWN_NOUNS[w] then return false end
  if w:match("y$") or w:match("ed$") or w:match("ing$") or w:match("ive$") or w:match("ous$") or w:match("al$") then
    return true
  end
  return false
end

local function build_buckets(script_path)
  if descriptors and nouns then return descriptors, nouns end
  local list = load_words(script_path)
  descriptors = {}
  nouns = {}
  for _, word in ipairs(list) do
    if is_descriptor(word) then
      descriptors[#descriptors + 1] = title_case(word)
    else
      nouns[#nouns + 1] = title_case(word)
    end
  end
  if #descriptors == 0 then
    for _, word in ipairs(list) do descriptors[#descriptors + 1] = title_case(word) end
  end
  if #nouns == 0 then
    for _, word in ipairs(list) do nouns[#nouns + 1] = title_case(word) end
  end
  return descriptors, nouns
end

local function load_role_buckets(script_path)
  if first_words and second_words and third_words then
    return first_words, second_words, third_words
  end

  local base = script_path or ""
  first_words = load_list(base .. "data/words_first.txt")
  second_words = load_list(base .. "data/words_second.txt")
  third_words = load_list(base .. "data/words_third.txt")

  if #first_words == 0 or #second_words == 0 then
    local dlist, nlist = build_buckets(script_path)
    if #first_words == 0 then
      first_words = dlist
    else
      for i = 1, #first_words do first_words[i] = title_case(first_words[i]) end
    end
    if #second_words == 0 then
      second_words = nlist
    else
      for i = 1, #second_words do second_words[i] = title_case(second_words[i]) end
    end
  else
    for i = 1, #first_words do first_words[i] = title_case(first_words[i]) end
    for i = 1, #second_words do second_words[i] = title_case(second_words[i]) end
  end

  if #third_words == 0 then
    third_words = second_words
  else
    for i = 1, #third_words do third_words[i] = title_case(third_words[i]) end
  end

  return first_words, second_words, third_words
end

local function tokenize(text, out)
  for token in tostring(text or ""):gmatch("[A-Za-z]+") do
    local t = token:lower()
    if #t > 1 then out[t] = true end
  end
end

local function build_context_set(context_words)
  local set = {}
  if type(context_words) == "table" then
    for _, w in ipairs(context_words) do tokenize(w, set) end
  end
  return set
end

local function pick_word(list, context_set, avoid)
  local best = nil
  local best_score = -1
  for _, w in ipairs(list) do
    local wl = w:lower()
    local score = math.random()
    if context_set[wl] then score = score + 3 end
    if avoid and wl == avoid:lower() then score = score - 100 end
    if score > best_score then
      best = w
      best_score = score
    end
  end
  return best or list[math.random(#list)]
end

function M.suggest_name(script_path, opts)
  opts = opts or {}
  local dlist, nlist, tlist = load_role_buckets(script_path)
  local context = build_context_set(opts.context_words)
  local seed = tostring(opts.seed_word or ""):gsub("^%s+", ""):gsub("%s+$", "")
  local prefer_three = opts.word_count == 3 or (opts.word_count == nil and math.random() < 0.38)

  local function split_seed(s)
    local out = {}
    for token in s:gmatch("[A-Za-z]+") do
      out[#out + 1] = title_case(token)
    end
    return out
  end

  local used = {}
  local function add_used(w)
    if w and w ~= "" then used[w:lower()] = true end
  end

  local function pick_not_used(list)
    local best = nil
    local best_score = -1
    for _, w in ipairs(list) do
      local wl = w:lower()
      if not used[wl] then
        local score = math.random()
        if context[wl] then score = score + 3 end
        if score > best_score then
          best = w
          best_score = score
        end
      end
    end
    if not best then
      best = list[math.random(#list)]
    end
    add_used(best)
    return best
  end

  local seed_tokens = split_seed(seed)
  local parts = {}
  for _, token in ipairs(seed_tokens) do
    parts[#parts + 1] = token
    add_used(token)
  end

  local target_count = prefer_three and 3 or 2
  if #parts >= target_count then
    local out = {}
    for i = 1, target_count do out[i] = parts[i] end
    return table.concat(out, " ")
  end

  if #parts == 0 then
    local first = pick_not_used(dlist)
    parts[#parts + 1] = first
    if target_count == 3 and math.random() < 0.52 then
      parts[#parts + 1] = pick_not_used(dlist)
    elseif target_count == 3 then
      parts[#parts + 1] = pick_not_used(nlist)
    end
    parts[#parts + 1] = pick_not_used(target_count == 3 and tlist or nlist)
  else
    local first_seed = parts[1]
    local first_is_descriptor = is_descriptor(first_seed)
    if first_is_descriptor then
      if target_count == 3 then
        parts[#parts + 1] = pick_not_used(dlist)
      end
      parts[#parts + 1] = pick_not_used(target_count == 3 and tlist or nlist)
    else
      local prefix = pick_not_used(dlist)
      local out = { prefix }
      if target_count == 3 then
        out[#out + 1] = pick_not_used(dlist)
      end
      for _, p in ipairs(parts) do out[#out + 1] = p end
      parts = out
    end
  end

  while #parts > target_count do
    table.remove(parts)
  end

  return table.concat(parts, " ")
end

function M.random_name(script_path)
  return M.suggest_name(script_path, nil)
end

-- Forces the word list to be re-read from disk on the next random_name() call.
function M.reload()
  words = nil
  descriptors = nil
  nouns = nil
  first_words = nil
  second_words = nil
  third_words = nil
end

return M
