-- Reading two saved .rpp files and describing what changed between them.
--
-- The parser only walks the structure a person would talk about: tracks,
-- their FX, items, envelopes and a handful of mixer lines, plus the project's
-- tempo, markers and master. Everything else is skipped without being read.
--
-- Skipping is what keeps this usable on big projects. A plugin's state is a
-- wall of base64 lines and a MIDI item is thousands of event lines, and none
-- of those lines contain "<" or ">". skip_block therefore jumps from one
-- structural line to the next with plain searches instead of looking at every
-- line in Lua: a 64 MB project parses in about 0.1 s.
--
-- A plugin's settings are only compared as a whole. VST, VST3 and CLAP state
-- is an opaque blob, so "the settings changed" is all a file can say; naming
-- the parameter needs the plugin itself to be loaded.
--
-- Blocks are remembered as byte ranges into the file text rather than copied
-- out, so a parsed project costs little more than the text it was read from.
-- No REAPER API is used here, which is what lets tests/rpp_diff_test.lua run
-- it outside REAPER.

local M = {}

local track_keys = {
  NAME = true,
  VOLPAN = true,
  MUTESOLO = true,
  IPHASE = true,
  ISBUS = true,
  PEAKCOL = true,
  NCHAN = true,
  MAINSEND = true,
  REC = true
}

local envelope_names = {
  VOLENV = "Volume (pre-FX) envelope",
  VOLENV2 = "Volume envelope",
  VOLENV3 = "Trim volume envelope",
  PANENV = "Pan (pre-FX) envelope",
  PANENV2 = "Pan envelope",
  WIDTHENV = "Width (pre-FX) envelope",
  WIDTHENV2 = "Width envelope",
  MUTEENV = "Mute envelope",
  AUXVOLENV = "Send volume envelope",
  AUXPANENV = "Send pan envelope",
  AUXMUTEENV = "Send mute envelope"
}

local fx_tags = { VST = true, JS = true, CLAP = true, AU = true, DX = true, LV2 = true, VIDEO_EFFECT = true, CONTAINER = true }

-- Line reading ---------------------------------------------------------------

-- Start of the line's content (after indentation), end of the line, and where
-- the next line begins.
local function read_line(text, pos)
  local line_end = text:find("\n", pos, true)
  local next_pos
  if line_end then next_pos = line_end + 1 else line_end = #text + 1; next_pos = #text + 1 end
  local stop = line_end - 1
  if stop >= pos and text:byte(stop) == 13 then stop = stop - 1 end
  local content = text:find("[^ \t]", pos)
  if not content or content > stop then content = stop + 1 end
  return content, stop, next_pos
end

-- True when only indentation sits between the line start and index.
local function at_line_start(text, index)
  local before = index - 1
  while before >= 1 do
    local byte = text:byte(before)
    if byte == 10 then return true end
    if byte ~= 32 and byte ~= 9 then return false end
    before = before - 1
  end
  return true
end

-- From just after a block's opening line, the position just after its closing
-- ">" line.
--
-- Plain searches for "<" and ">" run as memchr in C, and base64 and MIDI event
-- lines never contain either character, so a plugin blob of half a million
-- lines is crossed in one jump. A pattern such as "\n%s*[<>]" is tried at
-- every byte instead and was three times slower on a 64 MB project.
local function skip_block(text, pos)
  local depth = 1
  local next_open = text:find("<", pos, true)
  local next_close = text:find(">", pos, true)
  while true do
    local marker
    if next_open and (not next_close or next_open < next_close) then
      marker = next_open
      next_open = text:find("<", marker + 1, true)
    else
      marker = next_close
      if marker then next_close = text:find(">", marker + 1, true) end
    end
    if not marker then return #text + 1 end
    if not at_line_start(text, marker) then
      -- A "<" or ">" inside a line, such as in a name; not structure.
    elseif text:byte(marker) == 60 then
      depth = depth + 1
    else
      depth = depth - 1
      if depth == 0 then
        local line_end = text:find("\n", marker, true)
        return line_end and line_end + 1 or #text + 1
      end
    end
  end
end

local function line_key(text, content, stop)
  return text:match("^([%w_]+)", content)
end

local function line_rest(text, content, stop, key)
  return text:sub(content + #key + 1, stop)
end

local function tag_of(text, content, stop)
  return text:match("^<([%w_]+)", content)
end

-- Turning a line's arguments into values, honouring REAPER's quoting.
local function tokens(value)
  local result = {}
  local pos = 1
  value = value or ""
  while pos <= #value do
    local first = value:sub(pos, pos)
    if first == " " or first == "\t" then
      pos = pos + 1
    elseif first == "\"" or first == "'" or first == "`" then
      local close = value:find(first, pos + 1, true) or (#value + 1)
      result[#result + 1] = value:sub(pos + 1, close - 1)
      pos = close + 1
    else
      local close = value:find("[ \t]", pos) or (#value + 1)
      result[#result + 1] = value:sub(pos, close - 1)
      pos = close
    end
  end
  return result
end

M.tokens = tokens

-- Budget ------------------------------------------------------------------------

-- Called between tracks. Inside a coroutine it hands control back to REAPER
-- once the frame's budget is spent; outside one it does nothing.
local function make_budget(options)
  local budget = options and options.budget
  if not budget or not coroutine.isyieldable() then return function() end end
  local clock = os.clock
  local started = clock()
  return function(progress)
    if clock() - started >= budget then
      coroutine.yield(progress)
      started = clock()
    end
  end
end

-- Parsing ----------------------------------------------------------------------

-- Each FX also remembers its whole entry in the chain, from its BYPASS line
-- to the line before the next one (entry_start..entry_end), which is what a
-- restore lifts out and puts back: block, FXID, preset name and automation.
local function parse_fx_chain(text, pos)
  local chain = { list = {} }
  local pending_bypass = nil
  local pending_start = nil
  local current = nil
  while pos <= #text do
    local content, stop, next_pos = read_line(text, pos)
    local first = text:byte(content)
    if first == 62 then
      if current then current.entry_end = pos - 1 end
      chain.close_start = pos
      return chain, next_pos
    end
    if first == 60 then
      local tag = tag_of(text, content, stop)
      local block_end = skip_block(text, next_pos)
      if fx_tags[tag] then
        local args = tokens(text:sub(content + #tag + 2, stop))
        current = {
          tag = tag,
          name = args[1] or tag,
          bypass = pending_bypass or "0 0 0",
          block_start = content,
          block_end = block_end - 1,
          entry_start = pending_start or pos,
          envelopes = {}
        }
        chain.list[#chain.list + 1] = current
        pending_bypass = nil
        pending_start = nil
      elseif tag == "PARMENV" and current then
        current.envelopes[#current.envelopes + 1] = text:sub(content, block_end - 1)
      end
      pos = block_end
    else
      local key = line_key(text, content, stop)
      if key == "BYPASS" then
        if current and not current.entry_end then current.entry_end = pos - 1 end
        pending_bypass = line_rest(text, content, stop, key)
        pending_start = pos
      elseif current and key == "FXID" then
        current.id = line_rest(text, content, stop, key)
      elseif current and key == "PRESETNAME" then
        current.preset = tokens(line_rest(text, content, stop, key))[1]
      end
      pos = next_pos
    end
  end
  return chain, pos
end

local function parse_item(text, pos, block_start)
  local item = { block_start = block_start }
  while pos <= #text do
    local content, stop, next_pos = read_line(text, pos)
    local first = text:byte(content)
    if first == 62 then
      item.block_end = next_pos - 1
      return item, next_pos
    end
    if first == 60 then
      pos = skip_block(text, next_pos)
    else
      local key = line_key(text, content, stop)
      if key == "POSITION" then
        item.position = tonumber(line_rest(text, content, stop, key))
      elseif key == "LENGTH" then
        item.length = tonumber(line_rest(text, content, stop, key))
      elseif key == "IGUID" then
        item.id = line_rest(text, content, stop, key)
      elseif key == "MUTE" then
        item.mute = tokens(line_rest(text, content, stop, key))[1]
      elseif key == "NAME" and not item.name then
        item.name = tokens(line_rest(text, content, stop, key))[1]
      end
      pos = next_pos
    end
  end
  item.block_end = #text
  return item, pos
end

-- Counted inside the block's own text: searching the whole file for the next
-- "PT" line ran on to the end of the file for every envelope without points.
local function count_points(text, block_start, block_end)
  local _, count = text:sub(block_start, block_end):gsub("\n[ \t]*PT ", "")
  return count
end

local function parse_track(text, pos, content, stop)
  local track = {
    block_start = content,
    id = text:match("^<TRACK[ \t]+(%b{})", content),
    lines = {},
    receives = {},
    items = {},
    item_order = {},
    envelopes = {},
    other_blocks = {}
  }
  while pos <= #text do
    local line_content, line_stop, next_pos = read_line(text, pos)
    local first = text:byte(line_content)
    if first == 62 then
      track.block_end = next_pos - 1
      return track, next_pos
    end
    if first == 60 then
      local tag = tag_of(text, line_content, line_stop)
      if tag == "FXCHAIN" then
        track.fx, pos = parse_fx_chain(text, next_pos)
      elseif tag == "FXCHAIN_REC" then
        track.input_fx, pos = parse_fx_chain(text, next_pos)
      elseif tag == "ITEM" then
        local item
        item, pos = parse_item(text, next_pos, line_content)
        local key = item.id or ("#" .. tostring(#track.item_order + 1))
        item.key = key
        track.items[key] = item
        track.item_order[#track.item_order + 1] = key
      else
        local block_end = skip_block(text, next_pos)
        if envelope_names[tag] then
          track.envelopes[tag] = {
            text = text:sub(line_content, block_end - 1),
            points = count_points(text, line_content, block_end - 1)
          }
        else
          track.other_blocks[tag] = (track.other_blocks[tag] or "") .. text:sub(line_content, block_end - 1)
        end
        pos = block_end
      end
    else
      local key = line_key(text, line_content, line_stop)
      if key == "TRACKID" and not track.id then
        track.id = line_rest(text, line_content, line_stop, key)
      elseif key == "AUXRECV" then
        track.receives[#track.receives + 1] = line_rest(text, line_content, line_stop, key)
      elseif key == "HWOUT" then
        track.lines.HWOUT = (track.lines.HWOUT or "") .. line_rest(text, line_content, line_stop, key) .. "\n"
      elseif key and track_keys[key] then
        track.lines[key] = line_rest(text, line_content, line_stop, key)
      end
      pos = next_pos
    end
  end
  return track, pos
end

-- Parses a whole .rpp text. options.budget (seconds) lets a caller running
-- this inside a coroutine spread the work over frames; each yield passes the
-- fraction done.
function M.parse(text, options)
  local budget = make_budget(options)
  local project = {
    text = text,
    tracks = {},
    track_order = {},
    markers = {},
    lines = {},
    blocks = {}
  }
  local pos = 1
  local content, stop, next_pos = read_line(text, pos)
  if text:sub(content, content + 7) ~= "<REAPER_" then return nil, "Not a REAPER project file" end
  pos = next_pos
  local marker_seen = {}
  while pos <= #text do
    content, stop, next_pos = read_line(text, pos)
    local first = text:byte(content)
    if first == 62 then break end
    if first == 60 then
      local tag = tag_of(text, content, stop)
      if tag == "TRACK" then
        local track
        track, pos = parse_track(text, next_pos, content, stop)
        track.id = track.id or ("#" .. tostring(#project.track_order + 1))
        track.index = #project.track_order + 1
        project.tracks[track.id] = track
        project.track_order[#project.track_order + 1] = track.id
        budget(pos / #text)
      elseif tag == "MASTERFXLIST" then
        project.master_fx, pos = parse_fx_chain(text, next_pos)
      else
        local block_end = skip_block(text, next_pos)
        if tag then project.blocks[tag] = text:sub(content, block_end - 1) end
        pos = block_end
      end
    else
      local key = line_key(text, content, stop)
      if key == "MARKER" then
        local args = tokens(line_rest(text, content, stop, key))
        local flags = tonumber(args[4]) or 0
        local is_region = flags % 2 == 1
        local index = args[1] or "?"
        local id = (is_region and "R" or "M") .. index
        local marker = project.markers[id]
        if is_region and marker_seen[id] then
          marker.region_end = tonumber(args[2])
        else
          marker_seen[id] = true
          project.markers[id] = {
            id = id,
            index = index,
            region = is_region,
            position = tonumber(args[2]),
            name = args[3] or "",
            color = args[5]
          }
        end
      elseif key == "TEMPO" or key == "MASTER_VOLUME" or key == "MASTERMUTESOLO" or key == "SAMPLERATE" then
        project.lines[key] = line_rest(text, content, stop, key)
      end
      pos = next_pos
    end
  end
  return project
end

-- A single track chunk, as GetTrackStateChunk returns it or as cut out of a
-- .rpp. Block positions refer to the given text.
function M.parse_track_chunk(chunk)
  local content, stop, next_pos = read_line(chunk, 1)
  if chunk:sub(content, content + 5) ~= "<TRACK" then return nil end
  local track = parse_track(chunk, next_pos, content, stop)
  track.text = chunk
  return track
end

-- Describing values ------------------------------------------------------------

local function format_db(gain)
  gain = tonumber(gain)
  if not gain then return "?" end
  if gain <= 0.0000000298 then return "-inf dB" end
  local text = string.format("%+.1f dB", 20 * math.log(gain, 10))
  if text == "+0.0 dB" or text == "-0.0 dB" then text = "0.0 dB" end
  return text
end

local function format_pan(pan)
  pan = tonumber(pan)
  if not pan then return "?" end
  if math.abs(pan) < 0.005 then return "center" end
  local percent = math.floor(math.abs(pan) * 100 + 0.5)
  return tostring(percent) .. "% " .. (pan < 0 and "L" or "R")
end

local function format_time(seconds)
  seconds = tonumber(seconds)
  if not seconds then return "?" end
  local sign = seconds < 0 and "-" or ""
  seconds = math.abs(seconds)
  local minutes = math.floor(seconds / 60)
  return string.format("%s%d:%06.3f", sign, minutes, seconds - minutes * 60)
end

M.format_db = format_db
M.format_pan = format_pan
M.format_time = format_time

-- "VST3: Pro-Q 3 (FabFilter)" reads better as "Pro-Q 3".
local function fx_display_name(fx)
  local name = tostring(fx and fx.name or "?")
  name = name:gsub("^[%w_]+i?:%s*", "")
  -- Vendor and channel suffixes: "Reason Rack Plugin (Reason Studios) (4->32ch)".
  for _ = 1, 2 do name = name:gsub("%s*%([^%(%)]*%)%s*$", "") end
  if fx and fx.tag == "JS" then
    name = name:match("([^/\\]+)$") or name
    name = name:gsub("%.[Jj][Ss][Ff][Xx]$", "")
  end
  if name == "" then name = tostring(fx and fx.name or "?") end
  return name
end

M.fx_display_name = fx_display_name

-- Lines REAPER rewrites for reasons nobody would call an edit: selection, the
-- MIDI editor's view of a take, and data other scripts park in <EXT> blocks.
local item_noise = {
  SEL = true,
  IID = true,
  VELLANE = true,
  CFGEDIT = true,
  CFGEDITVIEW = true,
  TRACKSEL = true,
  EVTFILTER = true,
  KEYSNAP = true
}

local function item_without_noise(text)
  local kept = {}
  local skip_depth = 0
  for line in text:gmatch("[^\r\n]+") do
    local content = line:match("^[ \t]*(.*)$")
    local first = content:sub(1, 1)
    if skip_depth > 0 then
      if first == "<" then skip_depth = skip_depth + 1 elseif first == ">" then skip_depth = skip_depth - 1 end
    elseif content:match("^<EXT") then
      skip_depth = 1
    elseif not item_noise[content:match("^([%w_]+)") or ""] then
      kept[#kept + 1] = content
    end
  end
  return table.concat(kept, "\n")
end

M.item_without_noise = item_without_noise

-- Indentation is how a .rpp nests blocks; a chunk from the API has none.
-- Blocks only count as different when more than that differs. The cheap
-- byte compare runs first, so identical blocks never get copied.
local function unindent(text)
  text = tostring(text or ""):gsub("\r\n", "\n")
  return (text:gsub("^[ \t]+", ""):gsub("\n[ \t]+", "\n"))
end

-- Indentation of the first nested line, which tells a .rpp block (indented)
-- from an API chunk (not). When both sides are indented alike, differing
-- bytes are a real difference and the costly unindent is skipped: plugin
-- blobs run to megabytes, and between two saved versions this is the common
-- case.
local function inner_indent(text, from, to)
  from = from or 1
  local leading = text:match("^[ \t]*", from)
  local newline = text:find("\n", from, true)
  if not newline or (to and newline > to) then return leading end
  return leading .. "|" .. text:match("^[ \t]*", newline + 1)
end

local function same_text(a, b)
  if a == b then return true end
  a, b = tostring(a or ""), tostring(b or "")
  if inner_indent(a) == inner_indent(b) then return false end
  return unindent(a) == unindent(b)
end

local function same_range(text_a, start_a, end_a, text_b, start_b, end_b)
  if (end_a - start_a) == (end_b - start_b) and text_a:sub(start_a, end_a) == text_b:sub(start_b, end_b) then return true end
  if inner_indent(text_a, start_a, end_a) == inner_indent(text_b, start_b, end_b) then return false end
  return unindent(text_a:sub(start_a, end_a)) == unindent(text_b:sub(start_b, end_b))
end

local function nearly(a, b)
  if a == nil or b == nil then return a == b end
  return math.abs(a - b) < 0.0000005
end

-- Diffing --------------------------------------------------------------------

local function add(list, kind, text, extra)
  local entry = extra or {}
  entry.kind = kind
  entry.text = text
  list[#list + 1] = entry
  return entry
end

local function bump(counts, key, amount)
  counts[key] = (counts[key] or 0) + (amount or 1)
end

local function plural(count, singular, many)
  return tostring(count) .. " " .. (count == 1 and singular or (many or singular .. "s"))
end

-- FX identity: FXID when both sides have it, otherwise name plus position so
-- that an older file without FXIDs still pairs up sensibly.
local function fx_keys(chain)
  local keys, by_key, order = {}, {}, {}
  local seen = {}
  for index, fx in ipairs(chain and chain.list or {}) do
    local key = fx.id
    if not key then
      local base = "name:" .. tostring(fx.name)
      seen[base] = (seen[base] or 0) + 1
      key = base .. "#" .. tostring(seen[base])
    end
    keys[index] = key
    by_key[key] = { fx = fx, index = index }
    order[#order + 1] = key
  end
  return by_key, order
end

local function bypass_state(fx)
  local values = tokens(fx.bypass)
  return values[1] == "1", values[3] == "1"
end

-- JSFX ------------------------------------------------------------------------

-- Slider definitions from a .jsfx source: name, whether it is hidden (a "-"
-- before the name, which is how meters mark the readings they write back),
-- and the labels of a {Off,On} style list. Both the classic
-- "slider1:0<0,1,1>Name" and the "slider1:var=0<...>Name" forms are read.
function M.parse_jsfx_sliders(source)
  if type(source) ~= "string" then return nil end
  local sliders = {}
  for line in source:gmatch("[^\r\n]+") do
    if line:match("^@") then break end
    local index, rest = line:match("^slider(%d+):(.*)$")
    if index then
      local name = rest:match(">%s*(.-)%s*$") or rest:match("^[^%s]+%s+(.-)%s*$") or ""
      local hidden = name:sub(1, 1) == "-"
      if hidden then name = name:sub(2) end
      local enum = nil
      local list = rest:match("<[^>]-{(.-)}[^>]*>")
      if list then
        enum = {}
        for label in (list .. ","):gmatch("(.-),") do enum[#enum + 1] = label end
      end
      sliders[tonumber(index)] = { name = name ~= "" and name or ("Slider " .. index), hidden = hidden, enum = enum }
    end
  end
  return { sliders = sliders }
end

local function js_parts(text, fx)
  local block = text:sub(fx.block_start, fx.block_end)
  local header_end = block:find("\n", 1, true)
  if not header_end then return "", "" end
  local values_end = block:find("\n", header_end + 1, true) or (#block + 1)
  local values = block:sub(header_end + 1, values_end - 1):gsub("\r$", "")
  return values, block:sub(values_end + 1)
end

local function js_value(slider, value)
  local number = tonumber(value)
  if not number then return tostring(value or "-") end
  if slider and slider.enum then
    local label = slider.enum[math.floor(number + 0.5) + 1]
    if label then return label end
  end
  return (string.format("%.6g", number))
end

-- What changed in a JSFX, by slider name. Returns nil when only hidden
-- sliders moved: a meter writing its readings back is not an edit.
local function describe_js_change(old_text, new_text, old_fx, new_fx, name, options)
  local info = options and options.js_info and options.js_info(new_fx.name) or nil
  local old_values, old_rest = js_parts(old_text, old_fx)
  local new_values, new_rest = js_parts(new_text, new_fx)
  local old_tokens, new_tokens = tokens(old_values), tokens(new_values)
  local changes = {}
  for index = 1, math.max(#old_tokens, #new_tokens) do
    local a, b = old_tokens[index], new_tokens[index]
    if a ~= b and not nearly(tonumber(a), tonumber(b)) then
      local slider = info and info.sliders[index]
      if not (slider and slider.hidden) then
        changes[#changes + 1] = (slider and slider.name or ("Slider " .. index)) .. " " .. js_value(slider, a) .. " -> " .. js_value(slider, b)
      end
    end
  end
  if #changes > 0 then
    local shown = { changes[1], changes[2] }
    local text = name .. ": " .. table.concat(shown, ", ")
    if #changes > 2 then text = text .. ", +" .. tostring(#changes - 2) .. " more" end
    return text, changes
  end
  if not same_text(old_rest, new_rest) then return name .. " internal state changed", nil end
  return nil
end

local function diff_fx_chain(old_text, new_text, old_chain, new_chain, label, entries, counts, options)
  local first_entry = #entries + 1
  local old_by, old_order = fx_keys(old_chain)
  local new_by, new_order = fx_keys(new_chain)
  local prefix = label and (label .. ": ") or ""
  -- Two instances of the same plugin are told apart by their slot.
  local name_count = {}
  for _, by in ipairs({ old_by, new_by }) do
    local seen = {}
    for _, entry in pairs(by) do
      local base = fx_display_name(entry.fx)
      seen[base] = (seen[base] or 0) + 1
      name_count[base] = math.max(name_count[base] or 0, seen[base])
    end
  end
  local function label_of(entry)
    local base = fx_display_name(entry.fx)
    if (name_count[base] or 0) > 1 then return base .. " (slot " .. tostring(entry.index) .. ")" end
    return base
  end
  for _, key in ipairs(old_order) do
    if not new_by[key] then
      add(entries, "removed", prefix .. label_of(old_by[key]) .. " removed", { area = "fx", fx = old_by[key].fx, fx_key = key })
      bump(counts, "fx")
    end
  end
  for _, key in ipairs(new_order) do
    local new_entry = new_by[key]
    local old_entry = old_by[key]
    local name = label_of(new_entry)
    if not old_entry then
      add(entries, "added", prefix .. name .. " added", { area = "fx", fx = new_entry.fx, fx_key = key })
      bump(counts, "fx")
    else
      local old_fx, new_fx = old_entry.fx, new_entry.fx
      local changed = false
      local old_bypassed, old_offline = bypass_state(old_fx)
      local new_bypassed, new_offline = bypass_state(new_fx)
      if old_bypassed ~= new_bypassed then
        add(entries, "changed", prefix .. name .. (new_bypassed and " bypassed" or " enabled"), { area = "fx", fx = new_fx, old_fx = old_fx, fx_key = key })
        changed = true
      end
      if old_offline ~= new_offline then
        add(entries, "changed", prefix .. name .. (new_offline and " set offline" or " set online"), { area = "fx", fx = new_fx, old_fx = old_fx, fx_key = key })
        changed = true
      end
      local new_preset = new_fx.preset or ""
      if new_preset == "<empty>" then new_preset = "" end
      if (old_fx.preset or "") ~= (new_fx.preset or "") and new_preset ~= "" then
        add(entries, "changed", prefix .. name .. " preset: " .. tostring(new_fx.preset), { area = "fx", fx = new_fx, old_fx = old_fx, fx_key = key })
        changed = true
      elseif not same_range(old_text, old_fx.block_start, old_fx.block_end, new_text, new_fx.block_start, new_fx.block_end) then
        if new_fx.tag == "JS" and old_fx.tag == "JS" then
          local text, details = describe_js_change(old_text, new_text, old_fx, new_fx, prefix .. name, options)
          if text then
            add(entries, "changed", text, { area = "fx", fx = new_fx, old_fx = old_fx, fx_key = key, details = details })
            changed = true
          end
        else
          add(entries, "changed", prefix .. name .. " state changed", { area = "fx", fx = new_fx, old_fx = old_fx, fx_key = key })
          changed = true
        end
      end
      if not same_text(table.concat(old_fx.envelopes, "\n"), table.concat(new_fx.envelopes, "\n")) then
        add(entries, "changed", prefix .. name .. " automation changed", { area = "fx", fx = new_fx, old_fx = old_fx, fx_key = key })
        changed = true
      end
      if changed then bump(counts, "fx") end
    end
  end
  -- Order only matters among the FX both versions share.
  local old_shared, new_shared = {}, {}
  for _, key in ipairs(old_order) do if new_by[key] then old_shared[#old_shared + 1] = key end end
  for _, key in ipairs(new_order) do if old_by[key] then new_shared[#new_shared + 1] = key end end
  if table.concat(old_shared, "|") ~= table.concat(new_shared, "|") then
    add(entries, "changed", prefix .. "FX order changed", { area = "fx", order = true })
    bump(counts, "fx")
  end
  -- Which chain each entry is about: nil (the track's), "Input FX" or "Master".
  for index = first_entry, #entries do entries[index].chain = label end
end

local function diff_items(old_text, new_text, old_track, new_track, entries, counts)
  local added, removed, moved, resized, muted, edited = 0, 0, 0, 0, 0, 0
  local details = {}
  for _, key in ipairs(old_track.item_order) do
    if not new_track.items[key] then
      removed = removed + 1
      local item = old_track.items[key]
      details[#details + 1] = "removed " .. (item.name or "item") .. " at " .. format_time(item.position)
    end
  end
  for _, key in ipairs(new_track.item_order) do
    local new_item = new_track.items[key]
    local old_item = old_track.items[key]
    if not old_item then
      added = added + 1
      details[#details + 1] = "added " .. (new_item.name or "item") .. " at " .. format_time(new_item.position)
    elseif not same_range(old_text, old_item.block_start, old_item.block_end, new_text, new_item.block_start, new_item.block_end)
      and item_without_noise(old_text:sub(old_item.block_start, old_item.block_end)) ~= item_without_noise(new_text:sub(new_item.block_start, new_item.block_end)) then
      local known = false
      if not nearly(old_item.position, new_item.position) then
        moved = moved + 1
        known = true
        details[#details + 1] = (new_item.name or "item") .. " moved " .. format_time(old_item.position) .. " -> " .. format_time(new_item.position)
      end
      if not nearly(old_item.length, new_item.length) then
        resized = resized + 1
        known = true
      end
      if (old_item.mute or "0") ~= (new_item.mute or "0") then
        muted = muted + 1
        known = true
      end
      if not known then edited = edited + 1 end
    end
  end
  local parts = {}
  if added > 0 then parts[#parts + 1] = plural(added, "item") .. " added" end
  if removed > 0 then parts[#parts + 1] = plural(removed, "item") .. " removed" end
  if moved > 0 then parts[#parts + 1] = plural(moved, "item") .. " moved" end
  if resized > 0 then parts[#parts + 1] = plural(resized, "item") .. " resized" end
  if muted > 0 then parts[#parts + 1] = plural(muted, "item") .. " muted/unmuted" end
  if edited > 0 then parts[#parts + 1] = plural(edited, "item") .. " edited" end
  if #parts == 0 then return end
  local kind = (added > 0 and removed == 0 and moved + resized + muted + edited == 0) and "added"
    or ((removed > 0 and added == 0 and moved + resized + muted + edited == 0) and "removed" or "changed")
  add(entries, kind, table.concat(parts, ", "), { area = "items", details = details })
  bump(counts, "items", added + removed + moved + resized + muted + edited)
end

local function diff_envelopes(old_track, new_track, entries, counts)
  local seen = {}
  local keys = {}
  for key in pairs(old_track.envelopes) do if not seen[key] then seen[key] = true; keys[#keys + 1] = key end end
  for key in pairs(new_track.envelopes) do if not seen[key] then seen[key] = true; keys[#keys + 1] = key end end
  table.sort(keys)
  for _, key in ipairs(keys) do
    local old_env, new_env = old_track.envelopes[key], new_track.envelopes[key]
    local label = envelope_names[key] or key
    if not old_env then
      add(entries, "added", label .. " added", { area = "envelopes", envelope = key })
      bump(counts, "envelopes")
    elseif not new_env then
      add(entries, "removed", label .. " removed", { area = "envelopes", envelope = key })
      bump(counts, "envelopes")
    elseif not same_text(old_env.text, new_env.text) then
      local text = label .. " changed"
      if old_env.points ~= new_env.points then
        text = text .. " (" .. tostring(old_env.points) .. " -> " .. tostring(new_env.points) .. " points)"
      end
      add(entries, "changed", text, { area = "envelopes", envelope = key })
      bump(counts, "envelopes")
    end
  end
end

local function track_label(track)
  local name = track and track.lines.NAME and tokens(track.lines.NAME)[1] or ""
  if name == "" then return "Track " .. tostring(track and track.index or "?") end
  return name
end

M.track_label = track_label

local function diff_track_lines(old_track, new_track, entries, counts)
  local old_lines, new_lines = old_track.lines, new_track.lines
  local function changed(key) return (old_lines[key] or "") ~= (new_lines[key] or "") end
  local touched = false
  if changed("NAME") then
    add(entries, "changed", "Renamed from \"" .. track_label(old_track) .. "\"", { area = "misc", keys = { "NAME" } })
    touched = true
  end
  if changed("VOLPAN") then
    local old_values, new_values = tokens(old_lines.VOLPAN), tokens(new_lines.VOLPAN)
    if not nearly(tonumber(old_values[1]), tonumber(new_values[1])) then
      add(entries, "changed", "Volume " .. format_db(old_values[1]) .. " -> " .. format_db(new_values[1]), { area = "misc", param = "D_VOL", value = tonumber(old_values[1]) })
      touched = true
    end
    if not nearly(tonumber(old_values[2]), tonumber(new_values[2])) then
      add(entries, "changed", "Pan " .. format_pan(old_values[2]) .. " -> " .. format_pan(new_values[2]), { area = "misc", param = "D_PAN", value = tonumber(old_values[2]) })
      touched = true
    end
    if old_values[3] ~= new_values[3] or old_values[4] ~= new_values[4] or old_values[5] ~= new_values[5] then
      add(entries, "changed", "Pan mode or width changed", { area = "misc", keys = { "VOLPAN" } })
      touched = true
    end
  end
  if changed("MUTESOLO") then
    local old_values, new_values = tokens(old_lines.MUTESOLO), tokens(new_lines.MUTESOLO)
    if (old_values[1] or "0") ~= (new_values[1] or "0") then
      add(entries, "changed", new_values[1] == "1" and "Muted" or "Unmuted", { area = "misc", param = "B_MUTE", value = tonumber(old_values[1]) or 0 })
      touched = true
    end
    if (old_values[2] or "0") ~= (new_values[2] or "0") then
      add(entries, "changed", (tonumber(new_values[2]) or 0) > 0 and "Soloed" or "Unsoloed", { area = "misc", param = "I_SOLO", value = tonumber(old_values[2]) or 0 })
      touched = true
    end
  end
  if changed("IPHASE") then add(entries, "changed", "Phase flipped", { area = "misc", keys = { "IPHASE" } }); touched = true end
  if changed("ISBUS") then add(entries, "changed", "Folder structure changed", { area = "misc", keys = { "ISBUS" } }); touched = true end
  if changed("PEAKCOL") then add(entries, "changed", "Color changed", { area = "misc", keys = { "PEAKCOL" } }); touched = true end
  if changed("NCHAN") then
    add(entries, "changed", "Channels " .. tostring(old_lines.NCHAN or "2") .. " -> " .. tostring(new_lines.NCHAN or "2"), { area = "misc", keys = { "NCHAN" } })
    touched = true
  end
  if changed("MAINSEND") or changed("HWOUT") then add(entries, "changed", "Output routing changed", { area = "misc", keys = { "MAINSEND", "HWOUT" } }); touched = true end
  if changed("REC") then add(entries, "changed", "Record arm or input changed", { area = "misc", keys = { "REC" } }); touched = true end
  if table.concat(old_track.receives, "\n") ~= table.concat(new_track.receives, "\n") then
    local old_count, new_count = #old_track.receives, #new_track.receives
    local text = "Receives changed"
    if old_count ~= new_count then text = text .. " (" .. tostring(old_count) .. " -> " .. tostring(new_count) .. ")" end
    add(entries, "changed", text, { area = "misc", keys = { "AUXRECV" } })
    touched = true
  end
  if touched then bump(counts, "mixer") end
end

local function track_summary(track)
  local fx = track.fx and #track.fx.list or 0
  local items = #track.item_order
  local parts = {}
  if fx > 0 then parts[#parts + 1] = plural(fx, "FX", "FX") end
  if items > 0 then parts[#parts + 1] = plural(items, "item") end
  return #parts > 0 and table.concat(parts, ", ") or "empty"
end

-- Tracks whose neighbour among the shared tracks changed count as moved, so a
-- single drag reports one track rather than everything below it.
local function moved_tracks(old_project, new_project)
  local old_shared, new_shared = {}, {}
  for _, id in ipairs(old_project.track_order) do if new_project.tracks[id] then old_shared[#old_shared + 1] = id end end
  for _, id in ipairs(new_project.track_order) do if old_project.tracks[id] then new_shared[#new_shared + 1] = id end end
  local old_pos = {}
  for index, id in ipairs(old_shared) do old_pos[id] = index end
  -- Longest increasing run of old positions in new order = tracks that stayed.
  local sequence = {}
  for index, id in ipairs(new_shared) do sequence[index] = old_pos[id] end
  local tails, previous, tail_index = {}, {}, {}
  for index, value in ipairs(sequence) do
    local low, high = 1, #tails
    while low <= high do
      local mid = (low + high) // 2
      if sequence[tails[mid]] < value then low = mid + 1 else high = mid - 1 end
    end
    tails[low] = index
    previous[index] = low > 1 and tails[low - 1] or nil
    tail_index[low] = index
  end
  local stayed = {}
  local cursor = tails[#tails]
  while cursor do
    stayed[new_shared[cursor]] = true
    cursor = previous[cursor]
  end
  local moved = {}
  for _, id in ipairs(new_shared) do if not stayed[id] then moved[id] = true end end
  return moved
end

local function diff_markers(old_project, new_project, entries, counts)
  local ids = {}
  local seen = {}
  for id in pairs(old_project.markers) do if not seen[id] then seen[id] = true; ids[#ids + 1] = id end end
  for id in pairs(new_project.markers) do if not seen[id] then seen[id] = true; ids[#ids + 1] = id end end
  table.sort(ids, function(a, b)
    local ma = new_project.markers[a] or old_project.markers[a]
    local mb = new_project.markers[b] or old_project.markers[b]
    return (ma.position or 0) < (mb.position or 0)
  end)
  for _, id in ipairs(ids) do
    local old_marker, new_marker = old_project.markers[id], new_project.markers[id]
    local marker = new_marker or old_marker
    local noun = marker.region and "Region" or "Marker"
    local label = noun .. " " .. tostring(marker.index) .. (marker.name ~= "" and (" \"" .. marker.name .. "\"") or "")
    if not old_marker then
      add(entries, "added", label .. " added at " .. format_time(new_marker.position), { area = "markers", marker = id })
      bump(counts, "markers")
    elseif not new_marker then
      add(entries, "removed", label .. " removed", { area = "markers", marker = id })
      bump(counts, "markers")
    else
      local parts = {}
      if old_marker.name ~= new_marker.name then parts[#parts + 1] = "renamed from \"" .. old_marker.name .. "\"" end
      if not nearly(old_marker.position, new_marker.position) then
        parts[#parts + 1] = "moved " .. format_time(old_marker.position) .. " -> " .. format_time(new_marker.position)
      end
      if not nearly(old_marker.region_end, new_marker.region_end) then parts[#parts + 1] = "end changed" end
      if old_marker.color ~= new_marker.color then parts[#parts + 1] = "color changed" end
      if #parts > 0 then
        add(entries, "changed", label .. " " .. table.concat(parts, ", "), { area = "markers", marker = id })
        bump(counts, "markers")
      end
    end
  end
end

local function diff_project_level(old_project, new_project, entries, counts, options)
  local old_lines, new_lines = old_project.lines, new_project.lines
  local old_tempo, new_tempo = tokens(old_lines.TEMPO), tokens(new_lines.TEMPO)
  -- Newer REAPER versions append a fourth field; only BPM and signature count.
  if not nearly(tonumber(old_tempo[1]), tonumber(new_tempo[1])) or old_tempo[2] ~= new_tempo[2] or old_tempo[3] ~= new_tempo[3] then
    local old_values, new_values = old_tempo, new_tempo
    local text = "Tempo " .. tostring(old_values[1] or "?") .. " -> " .. tostring(new_values[1] or "?") .. " BPM"
    if old_values[2] ~= new_values[2] or old_values[3] ~= new_values[3] then
      text = text .. ", time signature " .. tostring(new_values[2]) .. "/" .. tostring(new_values[3])
    end
    add(entries, "changed", text, { area = "tempo" })
    bump(counts, "project")
  end
  if not same_text(old_project.blocks.TEMPOENVEX or "", new_project.blocks.TEMPOENVEX or "") then
    add(entries, "changed", "Tempo map changed", { area = "tempo" })
    bump(counts, "project")
  end
  if (old_lines.MASTER_VOLUME or "") ~= (new_lines.MASTER_VOLUME or "") then
    local old_values, new_values = tokens(old_lines.MASTER_VOLUME), tokens(new_lines.MASTER_VOLUME)
    if not nearly(tonumber(old_values[1]), tonumber(new_values[1])) then
      add(entries, "changed", "Master volume " .. format_db(old_values[1]) .. " -> " .. format_db(new_values[1]), { area = "master", param = "D_VOL", value = tonumber(old_values[1]) })
      bump(counts, "project")
    end
    if not nearly(tonumber(old_values[2]), tonumber(new_values[2])) then
      add(entries, "changed", "Master pan " .. format_pan(old_values[2]) .. " -> " .. format_pan(new_values[2]), { area = "master", param = "D_PAN", value = tonumber(old_values[2]) })
      bump(counts, "project")
    end
  end
  if (old_lines.MASTERMUTESOLO or "") ~= (new_lines.MASTERMUTESOLO or "") then
    add(entries, "changed", "Master mute/solo changed", { area = "master" })
    bump(counts, "project")
  end
  diff_fx_chain(old_project.text, new_project.text, old_project.master_fx, new_project.master_fx, "Master", entries, counts, options)
  if not same_text(old_project.blocks.NOTES or "", new_project.blocks.NOTES or "") then
    add(entries, "changed", "Project notes changed", { area = "notes" })
    bump(counts, "project")
  end
  diff_markers(old_project, new_project, entries, counts)
end

-- Compares two parsed projects. The result has project-level entries, one
-- group per track that differs (in the newer version's order, removed tracks
-- where they used to be), and counts for a one-line summary.
-- options.js_info(path) may return M.parse_jsfx_sliders() of that JSFX so
-- its changes can be named; without it sliders are reported by number.
function M.diff(old_project, new_project, options)
  local budget = make_budget(options)
  local result = { project = {}, tracks = {}, counts = {} }
  local counts = result.counts
  diff_project_level(old_project, new_project, result.project, counts, options)

  local moved = moved_tracks(old_project, new_project)
  local function track_group(id, status)
    local old_track, new_track = old_project.tracks[id], new_project.tracks[id]
    local track = new_track or old_track
    local group = { id = id, name = track_label(track), status = status, entries = {}, index = track.index }
    if status == "added" then
      add(group.entries, "added", "Track added (" .. track_summary(new_track) .. ")", { area = "track" })
      bump(counts, "tracks")
    elseif status == "removed" then
      add(group.entries, "removed", "Track removed (" .. track_summary(old_track) .. ")", { area = "track" })
      bump(counts, "tracks")
    else
      if moved[id] then
        add(group.entries, "changed", "Moved from position " .. tostring(old_track.index) .. " to " .. tostring(new_track.index), { area = "order" })
        bump(counts, "tracks")
      end
      diff_track_lines(old_track, new_track, group.entries, counts)
      diff_fx_chain(old_project.text, new_project.text, old_track.fx, new_track.fx, nil, group.entries, counts, options)
      diff_fx_chain(old_project.text, new_project.text, old_track.input_fx, new_track.input_fx, "Input FX", group.entries, counts, options)
      diff_items(old_project.text, new_project.text, old_track, new_track, group.entries, counts)
      diff_envelopes(old_track, new_track, group.entries, counts)
      local other_changed = false
      for key, value in pairs(old_track.other_blocks) do if not same_text(new_track.other_blocks[key], value) then other_changed = true end end
      for key in pairs(new_track.other_blocks) do if old_track.other_blocks[key] == nil then other_changed = true end end
      if other_changed and #group.entries == 0 then
        add(group.entries, "changed", "Other track settings changed", { area = "misc" })
      end
    end
    if #group.entries > 0 then result.tracks[#result.tracks + 1] = group end
  end

  -- Walk the new order, slotting each removed track in after the track that
  -- preceded it in the old version.
  local removed_after = {}
  local previous = "^"
  for _, id in ipairs(old_project.track_order) do
    if not new_project.tracks[id] then
      removed_after[previous] = removed_after[previous] or {}
      table.insert(removed_after[previous], id)
    else
      previous = id
    end
  end
  local function flush(anchor)
    for _, id in ipairs(removed_after[anchor] or {}) do track_group(id, "removed") end
  end
  flush("^")
  for index, id in ipairs(new_project.track_order) do
    track_group(id, old_project.tracks[id] and "changed" or "added")
    flush(id)
    budget(index / math.max(1, #new_project.track_order))
  end
  return result
end

-- One line such as "2 tracks · 5 FX · 3 items", or nil when nothing differs.
function M.summary(counts)
  local parts = {}
  local function part(key, singular, many)
    local value = counts and counts[key] or 0
    if value > 0 then parts[#parts + 1] = plural(value, singular, many) end
  end
  part("tracks", "track")
  part("fx", "FX", "FX")
  part("items", "item")
  part("envelopes", "envelope")
  part("mixer", "mixer change")
  part("markers", "marker")
  part("project", "project change")
  if #parts == 0 then return nil end
  return table.concat(parts, " · ")
end

function M.diff_texts(old_text, new_text, options)
  local old_project, old_err = M.parse(old_text, options)
  if not old_project then return nil, old_err end
  local new_project, new_err = M.parse(new_text, options)
  if not new_project then return nil, new_err end
  return M.diff(old_project, new_project, options)
end

return M
