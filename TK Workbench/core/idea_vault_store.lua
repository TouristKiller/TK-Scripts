local r = reaper

local json = require("core.json")

-- Every idea in the vault is three files that share one basename:
--
--   <name>.RTrackTemplate   the track chunk, items and envelopes included
--   <name>.<ext>            a rendered preview, whatever format the render made
--   <name>.tkidea           JSON: description, tempo, key, what the pair is
--
-- The sidecar is the authoritative record, not the audio file's own metadata.
-- Whether a given format carries a readable tempo tag varies per format and per
-- REAPER build, and a preview that plays back at the wrong rate is worse than
-- no preview at all, so the tempo that matters is written where it cannot be
-- lost. Anything reading this vault gets its play rate from the sidecar.
--
-- No ImGui, no Workbench app table: this is the half of Idea Vault that a
-- standalone action script can require and use without opening a window.
local Store = {}

local sep = package.config:sub(1, 1)
local EXT_SECTION = "TK_IDEA_VAULT"
local CONFIG_KEY = "config"
local SIDECAR_EXT = ".tkidea"
local TEMPLATE_EXT = ".RTrackTemplate"
local SCHEMA = 1

-- "File: Render project, using the most recent render settings, auto-close
-- render window" - the only render action that does not need a click.
local RENDER_COMMAND = 42230

local RENDER_STRINGS = { "RENDER_FILE", "RENDER_PATTERN", "RENDER_FORMAT" }
local RENDER_NUMBERS = {
  "RENDER_SETTINGS", "RENDER_BOUNDSFLAG", "RENDER_CHANNELS", "RENDER_SRATE",
  "RENDER_STARTPOS", "RENDER_ENDPOS", "RENDER_TAILFLAG", "RENDER_TAILMS",
  "RENDER_ADDTOPROJ", "RENDER_DITHER"
}

-- REAPER stores the sink type as a little-endian fourcc, so a decoded render
-- format config starts with the code spelled backwards. Only used to label the
-- configured format in a UI: the actual extension of a preview is discovered by
-- looking at what the render put on disk.
local FORMAT_NAMES = {
  evaw = "WAV", ffia = "AIFF", l3pm = "MP3", calf = "FLAC",
  vggo = "OGG", supO = "Opus", supo = "Opus", kpvw = "WavPack"
}

-- Every captured item is stamped "Beats (auto-stretch at tempo changes)", which
-- REAPER writes as BEAT 1 with IMPLIEDWARP beside it. Read off REAPER rather
-- than guessed, and not offered as a choice: the loading side already fits an
-- idea to whatever project it lands in, so this only governs what happens on
-- tempo changes afterwards - and there auto-stretch is simply what you want.
-- The alternatives are the behaviours that made a saved idea land wrong in the
-- first place, so there is nothing to gain by keeping them reachable.
local TIMEBASE = { beat = 1, warp = true }

local defaults = {
  root = "",
  render_format = "",
  channels = 2,
  samplerate = 0,
  tail_ms = 1200,
  include_folder_children = true,
  bounds = "auto"
}

local config = nil

--------------------------------------------------------------------------------
-- paths and small helpers
--------------------------------------------------------------------------------

local function with_slash(path)
  path = tostring(path or "")
  if path == "" then return path end
  if path:sub(-1) ~= sep and path:sub(-1) ~= "/" and path:sub(-1) ~= "\\" then
    path = path .. sep
  end
  return path
end

local function split_path(path)
  local dir, file = tostring(path or ""):match("^(.*[\\/])([^\\/]+)$")
  if not dir then return "", tostring(path or "") end
  return dir, file
end

local function split_ext(filename)
  local stem, ext = tostring(filename or ""):match("^(.*)%.([^%.]+)$")
  if not stem then return tostring(filename or ""), "" end
  return stem, ext
end

-- Windows, macOS and Linux disagree about what is legal in a filename, so this
-- takes the strictest set. Names come from a text field the user types in a
-- hurry, and a capture that fails on a colon is a lost idea.
local function sanitize(name)
  name = tostring(name or ""):gsub("[%c]", " ")
  name = name:gsub('[<>:"/\\|%?%*]', "-")
  name = name:gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
  name = name:gsub("%.+$", "")
  if name == "" then name = "Idea" end
  return name:sub(1, 120)
end

local function read_file(path)
  local file = io.open(path, "rb")
  if not file then return nil end
  local body = file:read("*a")
  file:close()
  return body
end

local function write_file(path, body)
  local file = io.open(path, "wb")
  if not file then return false end
  file:write(body)
  file:close()
  return true
end

--------------------------------------------------------------------------------
-- config
--------------------------------------------------------------------------------

local function default_root()
  return with_slash(r.GetResourcePath() .. sep .. "TrackTemplates" .. sep .. "Idea Vault")
end

-- The vault lives under REAPER's own TrackTemplates tree by default, which
-- means the FX Browser's template panel lists these ideas with no extra work.
function Store.get_config()
  if config then return config end
  config = {}
  for key, value in pairs(defaults) do config[key] = value end
  local raw = r.GetExtState(EXT_SECTION, CONFIG_KEY)
  if raw and raw ~= "" then
    local ok, decoded = pcall(json.decode, raw)
    if ok and type(decoded) == "table" then
      for key in pairs(defaults) do
        if decoded[key] ~= nil and type(decoded[key]) == type(defaults[key]) then
          config[key] = decoded[key]
        end
      end
    end
  end
  return config
end

function Store.save_config()
  local ok, encoded = pcall(json.encode, Store.get_config())
  if not ok then return false end
  r.SetExtState(EXT_SECTION, CONFIG_KEY, encoded, true)
  return true
end

function Store.set(key, value)
  local cfg = Store.get_config()
  if defaults[key] == nil then return false end
  cfg[key] = value
  return Store.save_config()
end

function Store.root()
  local cfg = Store.get_config()
  local root = cfg.root
  if not root or root == "" then root = default_root() end
  return with_slash(root)
end

-- RecursiveCreateDirectory is idempotent, and there is no reliable "does this
-- directory exist" call in the API: EnumerateFiles with -1 clears the cache
-- rather than reporting anything, and an empty folder looks exactly like a
-- missing one. So the vault creates unconditionally and lets the first real
-- write be the thing that reports a bad path.
function Store.ensure_root()
  local root = Store.root()
  r.RecursiveCreateDirectory(root, 0)
  return root
end

--------------------------------------------------------------------------------
-- format label
--------------------------------------------------------------------------------

local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

local function b64_head(data, bytes)
  data = tostring(data or ""):gsub("[^%w%+/=]", "")
  local out, bits, count = {}, 0, 0
  for i = 1, #data do
    local index = B64:find(data:sub(i, i), 1, true)
    if index then
      bits = bits * 64 + (index - 1)
      count = count + 1
      if count == 4 then
        out[#out + 1] = string.char(math.floor(bits / 65536) % 256,
                                    math.floor(bits / 256) % 256,
                                    bits % 256)
        bits, count = 0, 0
        if #out * 3 >= bytes then break end
      end
    end
  end
  return table.concat(out):sub(1, bytes)
end

local function format_label(blob)
  if not blob or blob == "" then return nil end
  return FORMAT_NAMES[b64_head(blob, 4)] or "Custom"
end

-- Returns a human label for the pinned preview format, or nil when the vault is
-- set to simply follow the project's own render format.
function Store.format_name()
  return format_label(Store.get_config().render_format)
end

-- What a capture would render to right now if nothing is pinned. Shown next to
-- the pin button so the choice is not made blind.
function Store.project_format_name()
  if not r.GetSetProjectInfo_String then return nil end
  local ok, value = r.GetSetProjectInfo_String(0, "RENDER_FORMAT", "", false)
  if not ok then return nil end
  return format_label(value)
end

function Store.follow_project_format()
  return Store.set("render_format", "")
end

-- Picks up the render format the project is currently set to. Building a format
-- config blob by hand is guesswork per codec, so the vault never invents one:
-- the user dials the format in once in the render dialog or Render Hub and
-- stores it here.
function Store.capture_format_from_project()
  if not r.GetSetProjectInfo_String then return false, "This REAPER build has no GetSetProjectInfo_String" end
  local ok, value = r.GetSetProjectInfo_String(0, "RENDER_FORMAT", "", false)
  if not ok or not value or value == "" then return false, "The project has no render format set yet" end
  Store.set("render_format", value)
  return true
end

--------------------------------------------------------------------------------
-- track collection and template writing
--------------------------------------------------------------------------------

-- A folder track on its own is an empty shell: the instrument, the MIDI and the
-- FX all live on its children. Selecting the folder and getting only the folder
-- back is never what the user meant, so children come along by default.
function Store.collect_tracks(include_children)
  local tracks = {}
  local total = r.CountTracks(0)
  local i = 0
  while i < total do
    local track = r.GetTrack(0, i)
    if r.IsTrackSelected(track) then
      tracks[#tracks + 1] = track
      local depth = r.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")
      if include_children and depth == 1 then
        local level, j = 1, i + 1
        while j < total and level > 0 do
          local child = r.GetTrack(0, j)
          tracks[#tracks + 1] = child
          level = level + r.GetMediaTrackInfo_Value(child, "I_FOLDERDEPTH")
          j = j + 1
        end
        i = j - 1
      end
    end
    i = i + 1
  end
  return tracks
end

-- Stamps every item in a track chunk with an explicit timebase, replacing
-- whatever it had. A freshly read chunk says BEAT -1, which means "ask the
-- project" - and that is exactly why a saved idea used to land differently
-- depending on where you loaded it. Only the item's own top level is touched:
-- the SOURCE and TAKE blocks nested inside it are left alone.
local function apply_item_timebase(chunk)
  local spec = TIMEBASE
  local out = {}
  local depth, item_depth = 0, nil
  for line in (chunk .. "\n"):gmatch("([^\n]*)\n") do
    local trimmed = line:match("^%s*(.-)%s*$")
    local opening = trimmed:sub(1, 1) == "<"
    local closing = trimmed == ">"
    local drop = false
    if item_depth and depth == item_depth and not opening and not closing then
      local key = trimmed:match("^(%u+)")
      drop = key == "BEAT" or key == "IMPLIEDWARP"
    end
    if not drop then out[#out + 1] = line end
    if opening then
      depth = depth + 1
      if not item_depth and trimmed:match("^<ITEM") then
        item_depth = depth
        local indent = line:match("^(%s*)") or ""
        out[#out + 1] = indent .. "BEAT " .. tostring(spec.beat)
        if spec.warp then out[#out + 1] = indent .. "IMPLIEDWARP 1" end
      end
    elseif closing then
      if item_depth and depth == item_depth then item_depth = nil end
      depth = depth - 1
    end
  end
  return table.concat(out, "\n")
end

-- An .RTrackTemplate is literally the track state chunk, one <TRACK ...> block
-- per track, so writing one is writing what GetTrackStateChunk already returns.
-- Items and envelopes are part of that chunk, which is the whole reason this
-- can carry a MIDI performance where an .RfxChain cannot.
function Store.write_template(tracks, path)
  if not tracks or #tracks == 0 then return false, "No tracks to save" end
  local chunks = {}
  for _, track in ipairs(tracks) do
    local ok, chunk = r.GetTrackStateChunk(track, "", false)
    if not ok then return false, "Could not read the track chunk" end
    chunks[#chunks + 1] = apply_item_timebase(chunk)
  end
  if not write_file(path, table.concat(chunks, "\n") .. "\n") then
    return false, "Could not write " .. path
  end
  return true
end

--------------------------------------------------------------------------------
-- render
--------------------------------------------------------------------------------

local function get_string(key)
  if not r.GetSetProjectInfo_String then return "" end
  local ok, value = r.GetSetProjectInfo_String(0, key, "", false)
  return ok and value or ""
end

local function set_string(key, value)
  if not r.GetSetProjectInfo_String then return end
  r.GetSetProjectInfo_String(0, key, tostring(value or ""), true)
end

local function get_number(key)
  return tonumber(r.GetSetProjectInfo(0, key, 0, false)) or 0
end

local function set_number(key, value)
  r.GetSetProjectInfo(0, key, tonumber(value) or 0, true)
end

local function snapshot_render()
  local snap = { strings = {}, numbers = {} }
  for _, key in ipairs(RENDER_STRINGS) do snap.strings[key] = get_string(key) end
  for _, key in ipairs(RENDER_NUMBERS) do snap.numbers[key] = get_number(key) end
  return snap
end

local function restore_render(snap)
  for _, key in ipairs(RENDER_STRINGS) do set_string(key, snap.strings[key]) end
  for _, key in ipairs(RENDER_NUMBERS) do set_number(key, snap.numbers[key]) end
end

local function snapshot_solo()
  local snap = {}
  for i = 0, r.CountTracks(0) - 1 do
    local track = r.GetTrack(0, i)
    snap[#snap + 1] = { track = track, solo = r.GetMediaTrackInfo_Value(track, "I_SOLO") }
  end
  return snap
end

local function restore_solo(snap)
  for _, entry in ipairs(snap) do
    if r.ValidatePtr2(0, entry.track, "MediaTrack*") then
      r.SetMediaTrackInfo_Value(entry.track, "I_SOLO", entry.solo)
    end
  end
end

local function items_extent(tracks)
  local first, last
  for _, track in ipairs(tracks) do
    for i = 0, r.CountTrackMediaItems(track) - 1 do
      local item = r.GetTrackMediaItem(track, i)
      local pos = r.GetMediaItemInfo_Value(item, "D_POSITION")
      local stop = pos + r.GetMediaItemInfo_Value(item, "D_LENGTH")
      if not first or pos < first then first = pos end
      if not last or stop > last then last = stop end
    end
  end
  return first, last
end

-- Rendering into an existing folder and then asking what appeared is more
-- reliable than predicting the extension: the extension follows from the render
-- format config, and that is a binary blob the vault deliberately does not parse.
local function find_rendered(dir, base)
  r.EnumerateFiles(dir, -1)
  local i = 0
  while true do
    local filename = r.EnumerateFiles(dir, i)
    if not filename then break end
    local stem, ext = split_ext(filename)
    local lower = ext:lower()
    if stem == base and lower ~= "rtracktemplate" and lower ~= "tkidea" then
      return dir .. filename
    end
    i = i + 1
  end
  return nil
end

-- Master mix with only these tracks audible, never stems. Stems mode writes one
-- file per selected track, which is right for a multitrack bounce and wrong
-- here: the point of the preview is that it plays the idea back as one thing,
-- and a sidecar that names one preview file cannot describe five of them.
local function apply_render_settings(base, dir, cfg, bounds)
  set_string("RENDER_FILE", dir)
  set_string("RENDER_PATTERN", base)
  if cfg.render_format and cfg.render_format ~= "" then
    set_string("RENDER_FORMAT", cfg.render_format)
  end
  set_number("RENDER_SETTINGS", 0)
  set_number("RENDER_CHANNELS", cfg.channels or 2)
  set_number("RENDER_SRATE", cfg.samplerate or 0)
  set_number("RENDER_ADDTOPROJ", 0)
  set_number("RENDER_DITHER", 0)
  set_number("RENDER_BOUNDSFLAG", bounds.flag)
  if bounds.flag == 0 then
    set_number("RENDER_STARTPOS", bounds.start_pos or 0)
    set_number("RENDER_ENDPOS", bounds.end_pos or 0)
  end
  local tail = tonumber(cfg.tail_ms) or 0
  set_number("RENDER_TAILMS", tail)
  -- The tail flag is a bitmask over bounds modes rather than a plain on/off,
  -- so every mode gets the tail and the bounds choice above stays free.
  set_number("RENDER_TAILFLAG", tail > 0 and 15 or 0)
end

local function resolve_bounds(cfg, tracks)
  local mode = cfg.bounds or "auto"
  if mode == "project" then return { flag = 1 } end
  local sel_start, sel_end = r.GetSet_LoopTimeRange(false, false, 0, 0, false)
  if (mode == "auto" or mode == "timesel") and sel_end and sel_end > sel_start then
    return { flag = 2 }
  end
  if mode == "auto" then
    local first, last = items_extent(tracks)
    if first and last and last > first then
      return { flag = 0, start_pos = first, end_pos = last }
    end
  end
  return { flag = 1 }
end

-- Solo is exclusive: everything that is not soloed goes quiet, and that
-- includes the buses the idea's own tracks route through. Master/parent send
-- off plus an explicit send into a sub-bus is a routing style REAPER is
-- perfectly happy with, but the solo cut the path and the render came out
-- silent. So follow the signal downstream from every track in the idea and
-- solo whatever it passes through on its way to the master.
local function routing_chain(tracks)
  local in_idea, seen, queue, buses = {}, {}, {}, {}
  local reaches_master = false
  for _, track in ipairs(tracks) do
    in_idea[track] = true
    if not seen[track] then seen[track] = true; queue[#queue + 1] = track end
  end
  local function push(dest)
    if not dest or seen[dest] then return end
    seen[dest] = true
    queue[#queue + 1] = dest
    if not in_idea[dest] then buses[#buses + 1] = dest end
  end
  local head = 1
  while head <= #queue do
    local track = queue[head]
    head = head + 1
    if r.GetMediaTrackInfo_Value(track, "B_MAINSEND") == 1 then
      -- No parent folder means this send lands on the master itself.
      local parent = r.GetParentTrack(track)
      if parent then push(parent) else reaches_master = true end
    end
    for i = 0, (r.GetTrackNumSends(track, 0) or 0) - 1 do
      local muted = r.GetTrackSendInfo_Value(track, 0, i, "B_MUTE")
      if muted == nil or muted == 0 then
        push(r.GetTrackSendInfo_Value(track, 0, i, "P_DESTTRACK"))
      end
    end
  end
  return buses, reaches_master
end

local function folder_children(track)
  local out = {}
  if r.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH") ~= 1 then return out end
  local total = r.CountTracks(0)
  -- IP_TRACKNUMBER is 1-based, so it is already the 0-based index of the track
  -- after this one - the first child.
  local level = 1
  local j = math.floor(r.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER"))
  while j < total and level > 0 do
    local child = r.GetTrack(0, j)
    out[#out + 1] = child
    level = level + r.GetMediaTrackInfo_Value(child, "I_FOLDERDEPTH")
    j = j + 1
  end
  return out
end

-- Soloing a folder track plays the whole folder, so a sub-bus that doubles as a
-- folder parent would drag its other children into the preview. Those get muted
-- for the length of the render - only the ones that are neither part of the
-- idea nor carrying its signal.
local function folder_bystanders(tracks, buses)
  local keep = {}
  for _, track in ipairs(tracks) do keep[track] = true end
  for _, track in ipairs(buses) do keep[track] = true end
  local out, added = {}, {}
  for _, bus in ipairs(buses) do
    for _, child in ipairs(folder_children(bus)) do
      if not keep[child] and not added[child] then
        added[child] = true
        out[#out + 1] = child
      end
    end
  end
  return out
end

local function snapshot_mute(tracks)
  local snap = {}
  for _, track in ipairs(tracks) do
    snap[#snap + 1] = { track = track, mute = r.GetMediaTrackInfo_Value(track, "B_MUTE") }
  end
  return snap
end

local function restore_mute(snap)
  for _, entry in ipairs(snap) do
    if r.ValidatePtr2(0, entry.track, "MediaTrack*") then
      r.SetMediaTrackInfo_Value(entry.track, "B_MUTE", entry.mute)
    end
  end
end

-- Renders the given tracks to one preview file and puts every project setting
-- it touched back the way it found it, including the solo states.
function Store.render_preview(tracks, base, dir, cfg)
  cfg = cfg or Store.get_config()
  if not tracks or #tracks == 0 then return nil, "No tracks to render" end
  if not r.GetSetProjectInfo_String then return nil, "This REAPER build has no GetSetProjectInfo_String" end

  local render_snapshot = snapshot_render()
  local solo_snapshot = snapshot_solo()
  local bounds = resolve_bounds(cfg, tracks)
  local buses, reaches_master = routing_chain(tracks)
  local mute_snapshot = snapshot_mute(folder_bystanders(tracks, buses))

  r.PreventUIRefresh(1)
  for _, entry in ipairs(solo_snapshot) do
    r.SetMediaTrackInfo_Value(entry.track, "I_SOLO", 0)
  end
  for _, track in ipairs(tracks) do
    r.SetMediaTrackInfo_Value(track, "I_SOLO", 1)
  end
  for _, track in ipairs(buses) do
    r.SetMediaTrackInfo_Value(track, "I_SOLO", 1)
  end
  for _, entry in ipairs(mute_snapshot) do
    r.SetMediaTrackInfo_Value(entry.track, "B_MUTE", 1)
  end
  apply_render_settings(base, dir, cfg, bounds)

  local ok, err = pcall(r.Main_OnCommand, RENDER_COMMAND, 0)

  restore_render(render_snapshot)
  restore_solo(solo_snapshot)
  restore_mute(mute_snapshot)
  r.PreventUIRefresh(-1)
  r.UpdateArrange()

  if not ok then return nil, tostring(err) end
  local path = find_rendered(dir, base)
  if not path then return nil, "The render produced no file - check the render format settings" end
  if not reaches_master then
    return path, "Nothing on these tracks reaches the master, so the preview is silent - check the master/parent send and the sends out of them"
  end
  return path
end

--------------------------------------------------------------------------------
-- sidecar
--------------------------------------------------------------------------------

local function media_length(path)
  if not path or not r.PCM_Source_CreateFromFile then return nil end
  local source = r.PCM_Source_CreateFromFile(path)
  if not source then return nil end
  local length = r.GetMediaSourceLength(source)
  r.PCM_Source_Destroy(source)
  return length
end

local function track_names(tracks)
  local names = {}
  for _, track in ipairs(tracks) do
    local _, name = r.GetTrackName(track)
    names[#names + 1] = name or ""
  end
  return names
end

local function unique_base(root, base)
  local candidate, n = base, 2
  while r.file_exists(root .. candidate .. TEMPLATE_EXT)
     or r.file_exists(root .. candidate .. SIDECAR_EXT) do
    candidate = base .. " (" .. n .. ")"
    n = n + 1
    if n > 999 then break end
  end
  return candidate
end

-- Paths are rebuilt from the vault root on every read, so they are deliberately
-- not written out: a sidecar carrying absolute paths turns the whole vault into
-- something that breaks the moment the folder moves or lands on another machine.
local PERSISTED = {
  "schema", "name", "description", "tags", "bpm", "timesig_num", "timesig_den",
  "created", "tracks", "track_count", "template", "preview", "duration",
  "source_project"
}

local function serialize(idea)
  local out = {}
  for _, key in ipairs(PERSISTED) do out[key] = idea[key] end
  return out
end

function Store.write_sidecar(idea)
  local ok, encoded = pcall(json.encode, serialize(idea))
  if not ok then return false, "Could not encode the sidecar" end
  if not write_file(idea.sidecar_path or "", encoded) then
    return false, "Could not write " .. tostring(idea.sidecar_path)
  end
  return true
end

function Store.read_sidecar(path)
  local body = read_file(path)
  if not body then return nil end
  local ok, decoded = pcall(json.decode, body)
  if not ok or type(decoded) ~= "table" then return nil end
  return decoded
end

--------------------------------------------------------------------------------
-- capture
--------------------------------------------------------------------------------

-- opts: name, description, tags (array), render (bool, default true)
--
-- Returns the idea table, or nil plus a message. A failed render is not a failed
-- capture: the template is on disk either way, and losing the performance
-- because a codec was misconfigured would defeat the point.
function Store.capture(opts)
  opts = opts or {}
  local cfg = Store.get_config()
  local tracks = Store.collect_tracks(cfg.include_folder_children)
  if #tracks == 0 then return nil, "Select the track you want to keep first" end

  local root = Store.ensure_root()
  local base = unique_base(root, sanitize(opts.name ~= "" and opts.name or nil))
  local template_path = root .. base .. TEMPLATE_EXT

  local ok, err = Store.write_template(tracks, template_path)
  if not ok then return nil, err end

  local position = r.GetCursorPosition()
  -- Returns num, denom, tempo - no leading retval, unlike most of the API.
  local timesig_num, timesig_den = r.TimeMap_GetTimeSigAtTime(0, position)
  local idea = {
    schema = SCHEMA,
    name = base,
    description = tostring(opts.description or ""),
    tags = type(opts.tags) == "table" and opts.tags or {},
    bpm = r.Master_GetTempo(),
    timesig_num = timesig_num,
    timesig_den = timesig_den,
    created = os.date("!%Y-%m-%dT%H:%M:%SZ"),
    tracks = track_names(tracks),
    track_count = #tracks,
    template = base .. TEMPLATE_EXT,
    preview = "",
    duration = 0,
    source_project = select(2, r.EnumProjects(-1, "")) or "",
    template_path = template_path,
    sidecar_path = root .. base .. SIDECAR_EXT
  }

  local warning = nil
  if opts.render ~= false then
    local preview_path, render_note = Store.render_preview(tracks, base, root, cfg)
    warning = render_note
    if preview_path then
      idea.preview = select(2, split_path(preview_path))
      idea.preview_path = preview_path
      idea.duration = media_length(preview_path) or 0
      -- A file that carries no audio at all is worth saying out loud: the
      -- capture looks like it worked and the preview plays back nothing.
      if idea.duration <= 0 and not warning then
        warning = "The preview rendered empty - check the routing and the render settings"
      end
    end
  end

  local written, write_err = Store.write_sidecar(idea)
  if not written then return nil, write_err or "Could not write the sidecar" end
  return idea, warning
end

--------------------------------------------------------------------------------
-- reading the vault back
--------------------------------------------------------------------------------

local function hydrate(idea, root)
  idea.template_path = root .. (idea.template or "")
  idea.sidecar_path = root .. (idea.name or "") .. SIDECAR_EXT
  idea.preview_path = idea.preview ~= "" and (root .. idea.preview) or nil
  idea.has_template = idea.template_path ~= root and r.file_exists(idea.template_path)
  idea.has_preview = idea.preview_path ~= nil and r.file_exists(idea.preview_path)
  return idea
end

function Store.list()
  local root = Store.root()
  local ideas = {}
  r.EnumerateFiles(root, -1)
  local i = 0
  while true do
    local filename = r.EnumerateFiles(root, i)
    if not filename then break end
    if filename:sub(-#SIDECAR_EXT):lower() == SIDECAR_EXT then
      local idea = Store.read_sidecar(root .. filename)
      if idea then ideas[#ideas + 1] = hydrate(idea, root) end
    end
    i = i + 1
  end
  -- Newest first, name as tiebreaker: two ideas captured in the same second
  -- would otherwise shuffle between refreshes.
  table.sort(ideas, function(a, b)
    local a_time, b_time = tostring(a.created or ""), tostring(b.created or "")
    if a_time ~= b_time then return a_time > b_time end
    return tostring(a.name or "") < tostring(b.name or "")
  end)
  return ideas
end

-- The play rate that makes a preview sit in the current project's grid. The
-- tempo comes from the sidecar, so this works for any format the render made.
function Store.preview_rate(idea, project_bpm)
  local recorded = tonumber(idea and idea.bpm)
  project_bpm = tonumber(project_bpm) or r.Master_GetTempo()
  if not recorded or recorded <= 0 or not project_bpm or project_bpm <= 0 then return 1.0 end
  return project_bpm / recorded
end

function Store.tempo_differs(idea, project_bpm)
  local recorded = tonumber(idea and idea.bpm)
  project_bpm = tonumber(project_bpm) or r.Master_GetTempo()
  if not recorded or recorded <= 0 or not project_bpm or project_bpm <= 0 then return false end
  return math.abs(recorded - project_bpm) > 0.01
end

-- A track template carries no tempo of its own - there is not a single TEMPO
-- line in one. Item positions and lengths are stored in seconds and read
-- against whatever tempo map is in place when the tracks arrive, and the MIDI
-- inside follows that map too. So the tempo has to be set before the template
-- lands, not after, or the items sit at second-positions that no longer line up
-- with the phrase they were played as.
function Store.apply_tempo(idea)
  local bpm = tonumber(idea and idea.bpm)
  if not bpm or bpm <= 0 or not r.SetCurrentBPM then return false end
  r.SetCurrentBPM(0, bpm, false)
  return true
end

function Store.matches(idea, query)
  query = tostring(query or ""):lower()
  if query == "" then return true end
  local haystack = table.concat({
    tostring(idea.name or ""),
    tostring(idea.description or ""),
    table.concat(idea.tags or {}, " "),
    table.concat(idea.tracks or {}, " ")
  }, " "):lower()
  for word in query:gmatch("%S+") do
    if not haystack:find(word, 1, true) then return false end
  end
  return true
end

--------------------------------------------------------------------------------
-- acting on an idea
--------------------------------------------------------------------------------

local SCALED_ITEM_KEYS = { "D_POSITION", "D_LENGTH", "D_FADEINLEN", "D_FADEOUTLEN", "D_SNAPOFFSET" }

-- A track template records no tempo of its own - not one TEMPO line, no stretch
-- markers - so its items arrive as raw seconds and REAPER has nothing to
-- convert them from. The item timebase only governs what happens on tempo
-- changes after they are in; at the moment of import it can do nothing.
--
-- The sidecar is the only thing that knows, so the fitting happens here.
-- Positions and lengths scale by the tempo ratio, and audio takes get the
-- matching playrate so the sound still fills the new length - with the take's
-- preserve-pitch flag holding the pitch. Source offsets are deliberately left
-- alone: length times rate is unchanged, so the same piece of audio is used.
-- MIDI takes keep their rate, because their notes are ticks and already play at
-- the project tempo; only their item boundaries need moving.
local function fit_items_to_tempo(first_track, ratio)
  local count = 0
  for i = first_track, r.CountTracks(0) - 1 do
    local track = r.GetTrack(0, i)
    for j = 0, r.CountTrackMediaItems(track) - 1 do
      local item = r.GetTrackMediaItem(track, j)
      for _, key in ipairs(SCALED_ITEM_KEYS) do
        local value = r.GetMediaItemInfo_Value(item, key)
        if value and value ~= 0 then r.SetMediaItemInfo_Value(item, key, value * ratio) end
      end
      for k = 0, r.CountTakes(item) - 1 do
        local take = r.GetTake(item, k)
        if take and not r.TakeIsMIDI(take) then
          local rate = r.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE")
          if rate and rate > 0 then
            r.SetMediaItemTakeInfo_Value(take, "D_PLAYRATE", rate / ratio)
          end
        end
      end
      count = count + 1
    end
  end
  return count
end

-- Track envelope points sit on the project timeline in plain seconds - the same
-- timeline the items were just moved along - so automation would otherwise stay
-- behind where the performance used to be. This covers FX parameter envelopes
-- too, since those are track envelopes as far as the API is concerned.
--
-- Take envelopes are deliberately not touched: their points live in take time,
-- and length times rate came out unchanged, so they still line up with the
-- audio they were drawn against.
local function fit_envelopes_to_tempo(first_track, ratio)
  local count = 0
  for i = first_track, r.CountTracks(0) - 1 do
    local track = r.GetTrack(0, i)
    for e = 0, r.CountTrackEnvelopes(track) - 1 do
      local env = r.GetTrackEnvelope(track, e)
      local points = r.CountEnvelopePoints(env)
      for p = 0, points - 1 do
        local ok, time, value, shape, tension, selected = r.GetEnvelopePoint(env, p)
        -- Sorting is held off until the whole lane is scaled, or a point moved
        -- past its neighbour would renumber the ones still to be read.
        if ok then
          r.SetEnvelopePoint(env, p, time * ratio, value, shape, tension, selected, true)
        end
      end
      if points > 0 then
        r.Envelope_SortPoints(env)
        count = count + 1
      end
    end
  end
  return count
end

-- opts.match_tempo sets the project tempo to the idea's before the tracks land,
-- inside the same undo block so one press of Ctrl+Z takes both back. Otherwise
-- the items are fitted to the project instead, unless opts.fit_tempo is false.
function Store.load(idea, opts)
  if not idea or not idea.template_path or not r.file_exists(idea.template_path) then
    return false, "The template file is missing"
  end
  local before = r.CountTracks(0)
  local matching = opts and opts.match_tempo
  local recorded = tonumber(idea.bpm)
  local project_bpm = r.Master_GetTempo()
  local ratio = nil
  if not matching and (not opts or opts.fit_tempo ~= false)
     and recorded and recorded > 0 and project_bpm and project_bpm > 0 then
    ratio = recorded / project_bpm
    if math.abs(ratio - 1) < 0.0001 then ratio = nil end
  end

  r.PreventUIRefresh(1)
  r.Undo_BeginBlock()
  if matching then Store.apply_tempo(idea) end
  r.Main_openProject(idea.template_path)
  if ratio then
    fit_items_to_tempo(before, ratio)
    fit_envelopes_to_tempo(before, ratio)
  end
  local first_new = r.GetTrack(0, before)
  if first_new then r.SetOnlyTrackSelected(first_new) end
  r.Undo_EndBlock("Load idea: " .. tostring(idea.name or ""), -1)
  r.PreventUIRefresh(-1)
  r.TrackList_AdjustWindows(false)
  r.UpdateArrange()
  return true
end

function Store.rename(idea, new_name)
  local root = Store.root()
  -- Settling on the wanted name before uniquifying, because unique_base sees
  -- this idea's own files: renaming something to the name it already has would
  -- otherwise silently turn it into "name (2)".
  local wanted = sanitize(new_name)
  if wanted == idea.name then return true end
  local base = unique_base(root, wanted)
  local _, preview_file = split_path(idea.preview_path or "")
  local _, preview_ext = split_ext(preview_file)

  if idea.has_template then os.rename(idea.template_path, root .. base .. TEMPLATE_EXT) end
  if idea.has_preview and preview_ext ~= "" then
    os.rename(idea.preview_path, root .. base .. "." .. preview_ext)
  end
  os.remove(idea.sidecar_path)

  idea.name = base
  idea.template = base .. TEMPLATE_EXT
  idea.preview = preview_ext ~= "" and (base .. "." .. preview_ext) or ""
  idea.sidecar_path = root .. base .. SIDECAR_EXT
  hydrate(idea, root)
  return Store.write_sidecar(idea)
end

function Store.update(idea)
  return Store.write_sidecar(idea)
end

function Store.delete(idea)
  if not idea then return false end
  if idea.has_template then os.remove(idea.template_path) end
  if idea.has_preview then os.remove(idea.preview_path) end
  if idea.sidecar_path then os.remove(idea.sidecar_path) end
  return true
end

return Store
