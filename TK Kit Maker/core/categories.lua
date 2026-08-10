-- Sample category matching for slot filters. Pure Lua (no reaper calls) so it
-- can be tested standalone, like core/stitcher.lua.
--
-- Each category matches filenames through two explicit synonym lists:
--   subs -- substring match against the "collapsed" haystack (all
--           non-alphanumerics removed): catches "Kickdrum01", "hi-hat closed".
--   toks -- whole-token match (haystack split on non-alphanumerics, tokens
--           also tried with leading/trailing digits stripped: "hh1" -> "hh",
--           "808kick" -> "kick"): safe for short codes like bd/hh/sd without
--           false positives ("hat" does not match "that", "tom" not "custom",
--           "ride" not "override", "clap" not "Claptone").
--
-- The haystack is the filename (without extension), lowercased, and the parent
-- folder is added ONLY when the filename names no category at all. See
-- category_haystack() below for why.

local M = {}

M.list = {
  { id = "kick",   label = "Kick",   subs = { "kick", "kickdrum", "bassdrum" },                          toks = { "bd", "kik", "kck" } },
  { id = "snare",  label = "Snare",  subs = { "snare" },                                                 toks = { "sd", "sn", "snr" } },
  -- "Hihat" matches any hat; the open/closed variants below are subsets that
  -- key on the usual naming conventions (OH/OHH/Open Hat vs CH/CHH/Closed Hat).
  -- In parse_pattern, shared synonyms resolve to the most specific category
  -- (later entries win), so "ohh" in a pattern means Open hihat.
  { id = "hihat",        label = "Hihat",        subs = { "hihat", "openhat", "closedhat" },                              toks = { "hh", "chh", "ohh", "hat", "hats", "ch", "oh" } },
  { id = "hihat_open",   label = "Open hihat",   subs = { "openhat", "openhihat", "openhh", "hhopen", "hatopen" },        toks = { "ohh", "oh", "ohat" } },
  { id = "hihat_closed", label = "Closed hihat", subs = { "closedhat", "closedhihat", "closedhh", "hhclosed", "hatclosed" }, toks = { "chh", "ch", "chat" } },
  { id = "clap",   label = "Clap",   subs = { "handclap" },                                              toks = { "clap", "clp" } },
  { id = "rim",    label = "Rim",    subs = { "rimshot" },                                               toks = { "rim", "rs" } },
  { id = "tom",    label = "Tom",    subs = {},                                                          toks = { "tom", "toms" } },
  { id = "crash",  label = "Crash",  subs = { "crash" },                                                 toks = {} },
  { id = "ride",   label = "Ride",   subs = {},                                                          toks = { "ride", "rd" } },
  { id = "cymbal", label = "Cymbal", subs = { "cymbal" },                                                toks = { "cym" } },
  { id = "perc",   label = "Perc",   subs = { "percussion", "conga", "bongo", "tambourine", "cowbell" }, toks = { "perc" } },
  { id = "shaker", label = "Shaker", subs = { "shaker" },                                                toks = {} },
  { id = "808",    label = "808",    subs = { "808" },                                                   toks = {} },
  { id = "bass",   label = "Bass",   subs = { "bass" },                                                  toks = {} },
  { id = "vocal",  label = "Vocal",  subs = { "vocal" },                                                 toks = { "vox" } },
  { id = "fx",     label = "FX",     subs = { "riser", "sweep", "impact" },                              toks = { "fx", "sfx" } },
}

local by_id = {}
for _, cat in ipairs(M.list) do by_id[cat.id] = cat end

-- Synonym -> category lookup for parse_pattern (ids, labels and all synonyms).
local synonym_to_id = {}
for _, cat in ipairs(M.list) do
  synonym_to_id[cat.id] = cat.id
  synonym_to_id[cat.label:lower()] = cat.id
  for _, s in ipairs(cat.subs) do synonym_to_id[s] = cat.id end
  for _, t in ipairs(cat.toks) do synonym_to_id[t] = cat.id end
end

function M.by_id(id)
  return by_id[id]
end

-- parentfolder/filename without extension, lowercased
local function haystack_of(path)
  path = tostring(path or ""):gsub("\\", "/"):lower()
  local parent, name = path:match("([^/]+)/([^/]+)$")
  if not name then name = path:match("([^/]+)$") or path end
  name = name:gsub("%.[%w]+$", "")
  return (parent and (parent .. "/") or "") .. name
end

-- The filename alone, without extension, lowercased.
local function name_of(path)
  path = tostring(path or ""):gsub("\\", "/"):lower()
  local name = path:match("([^/]+)$") or path
  return (name:gsub("%.[%w]+$", ""))
end

-- A plural counts as its singular, so a folder called Claps or Rims answers
-- Clap and Rim.
--
-- Without it the categories behaved differently from each other for no reason
-- the user could see: Kicks and Snares matched, because "kick" and "snare" are
-- substrings and are looked for as substrings, while Claps and Rims did not,
-- because "clap" and "rim" are short enough to have to be whole tokens ("clap"
-- must not match Claptone, "rim" must not match trimmed). The token test is the
-- right one; it was simply refusing the one ending every folder of them has.
--
-- Only a trailing s, and only as an ADDITIONAL token -- the original is kept.
-- So "bass" still reads as bass and merely also offers "bas", which no category
-- claims.
local function add_token(tokens, token)
  if token == "" then return end
  tokens[token] = true
  if #token > 3 and token:sub(-1) == "s" then
    tokens[token:sub(1, -2)] = true
  end
end

local function tokens_of(haystack)
  local tokens = {}
  for token in haystack:gmatch("[%w]+") do
    add_token(tokens, token)
    add_token(tokens, (token:gsub("%d+$", "")))
    add_token(tokens, (token:gsub("^%d+", "")))
    add_token(tokens, (token:gsub("^%d+", ""):gsub("%d+$", "")))
  end
  return tokens
end

local function collapse(haystack)
  return (haystack:gsub("[^%w]", ""))
end

local function hits_category(cat, collapsed, tokens)
  for _, s in ipairs(cat.subs) do
    if collapsed:find(s, 1, true) then return true end
  end
  for _, t in ipairs(cat.toks) do
    if tokens[t] then return true end
  end
  return false
end

-- What a CATEGORY question is asked of: the filename, and the parent folder as
-- well only when the filename names no category at all.
--
-- The folder used to count always, and for a folder of one instrument that is
-- exactly right: "Kicks/001.wav" has nothing else to go on, and a pack that
-- numbers its files is not unusual. But a folder called "WA Snares & Claps"
-- says two things at once, and every file in it then answered Snare -- so a
-- slot asking for snares got the claps too, and the filter looked broken while
-- doing precisely what it was told.
--
-- The rule that fixes it without giving up the numbered-folder case: a file
-- that names itself is described by its own name. wa_snare_01 says snare, so
-- nothing above it can add clap; 001.wav says nothing, so the folder is all
-- there is and is used. The two cases never overlap, because the test is
-- whether the filename hits ANY category rather than the one being asked for --
-- otherwise a clap in a Snares folder would still answer Snare, which is the
-- same bug one level down.
--
-- A keyword spec is deliberately NOT narrowed this way. That is free text, and
-- what it looks for is routinely only in the path: "vinyl" over Vinyl Drums/
-- kick.wav has to keep working, and kick.wav names itself, so the same rule
-- would have quietly emptied it.
local function category_haystack(path)
  local name = name_of(path)
  local collapsed = collapse(name)
  local tokens = tokens_of(name)

  for _, cat in ipairs(M.list) do
    if hits_category(cat, collapsed, tokens) then return collapsed, tokens end
  end

  local full = haystack_of(path)
  return collapse(full), tokens_of(full)
end

-- spec: { category = "hihat" } or { keyword = "vinyl" } (keyword wins upstream)
function M.matches(path, spec)
  if not spec then return true end

  if spec.keyword and spec.keyword ~= "" then
    local needle = collapse(spec.keyword:lower())
    return needle == "" or collapse(haystack_of(path)):find(needle, 1, true) ~= nil
  end

  local cat = spec.category and by_id[spec.category]
  if not cat then return true end

  local collapsed, tokens = category_haystack(path)
  return hits_category(cat, collapsed, tokens)
end

function M.match_count(files, spec)
  local n = 0
  for _, f in ipairs(files or {}) do
    if M.matches(f, spec) then n = n + 1 end
  end
  return n
end

-- True when no category recognises the name at all. Worth being able to ask:
-- these are the files whose naming nothing here understands, and they are
-- exactly the ones a user would want to find and rename.
function M.matches_none(path)
  local collapsed, tokens = category_haystack(path)
  for _, cat in ipairs(M.list) do
    if hits_category(cat, collapsed, tokens) then return false end
  end
  return true
end

-- Counts every category in ONE pass over the file list: each filename is
-- collapsed/tokenised once instead of once per category. Returns id -> count,
-- plus how many files matched nothing at all.
function M.count_all(files)
  local counts = {}
  for _, cat in ipairs(M.list) do counts[cat.id] = 0 end
  local none = 0

  for _, path in ipairs(files or {}) do
    local collapsed, tokens = category_haystack(path)
    local any = false
    for _, cat in ipairs(M.list) do
      if hits_category(cat, collapsed, tokens) then
        counts[cat.id] = counts[cat.id] + 1
        any = true
      end
    end
    if not any then none = none + 1 end
  end
  return counts, none
end

-- Builds the spec for a slot (keyword beats category). Returns nil = no filter.
function M.spec_for_slot(slot)
  if slot.keyword and slot.keyword ~= "" then return { keyword = slot.keyword } end
  if slot.category and by_id[slot.category] then return { category = slot.category } end
  return nil
end

-- Display name for a spec ("Hihat" or "vinyl"), used in errors and filenames.
function M.spec_label(spec)
  if not spec then return nil end
  if spec.keyword and spec.keyword ~= "" then return spec.keyword end
  local cat = spec.category and by_id[spec.category]
  return cat and cat.label or nil
end

-- Parses "Kick, Snare, hh, vinyl" into an ordered list of specs. Known
-- ids/labels/synonyms become category specs, anything else a keyword spec.
-- Returns specs plus a parallel list of display labels for UI previews.
function M.parse_pattern(str)
  local specs, labels = {}, {}
  for part in tostring(str or ""):gmatch("[^,]+") do
    local word = part:match("^%s*(.-)%s*$")
    if word ~= "" then
      local id = synonym_to_id[word:lower()]
      if id then
        specs[#specs + 1] = { category = id }
        labels[#labels + 1] = by_id[id].label
      else
        specs[#specs + 1] = { keyword = word }
        labels[#labels + 1] = '"' .. word .. '"'
      end
    end
  end
  return specs, labels
end

return M
