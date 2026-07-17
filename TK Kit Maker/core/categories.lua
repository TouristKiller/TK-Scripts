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
-- The haystack is parentfolder/filename (without extension), lowercased --
-- so "Kicks/001.wav" matches Kick, but junk higher up the path is ignored.

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

local function tokens_of(haystack)
  local tokens = {}
  for token in haystack:gmatch("[%w]+") do
    tokens[token] = true
    local no_trail = token:gsub("%d+$", "")
    if no_trail ~= "" then tokens[no_trail] = true end
    local no_lead = token:gsub("^%d+", "")
    if no_lead ~= "" then tokens[no_lead] = true end
    local stripped = token:gsub("^%d+", ""):gsub("%d+$", "")
    if stripped ~= "" then tokens[stripped] = true end
  end
  return tokens
end

local function collapse(haystack)
  return (haystack:gsub("[^%w]", ""))
end

-- spec: { category = "hihat" } or { keyword = "vinyl" } (keyword wins upstream)
function M.matches(path, spec)
  if not spec then return true end
  local haystack = haystack_of(path)

  if spec.keyword and spec.keyword ~= "" then
    local needle = collapse(spec.keyword:lower())
    return needle == "" or collapse(haystack):find(needle, 1, true) ~= nil
  end

  local cat = spec.category and by_id[spec.category]
  if not cat then return true end

  local collapsed = collapse(haystack)
  for _, s in ipairs(cat.subs) do
    if collapsed:find(s, 1, true) then return true end
  end

  local tokens = tokens_of(haystack)
  for _, t in ipairs(cat.toks) do
    if tokens[t] then return true end
  end
  return false
end

function M.match_count(files, spec)
  local n = 0
  for _, f in ipairs(files or {}) do
    if M.matches(f, spec) then n = n + 1 end
  end
  return n
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
