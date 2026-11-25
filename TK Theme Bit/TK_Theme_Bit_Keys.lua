-- TK Theme Bit - Bitwig shortcuts (library for Settings > Shortcuts; also run from REAPER's
-- Scripts/__startup.lua). Found in REAPER 7.86, 2026-11-25 (probes TK_Bit_Keymap_Probe*):
--
--   * No API adds a shortcut, and a script can't make REAPER import a .ReaperKeyMap. What
--     works: write the KEY lines into reaper-kb.ini and restart REAPER (it doesn't rewrite
--     the file on exit, only when the action list changes).
--   * REAPER has 16 alternative lists for the main section, "Main (alt-1)".."(alt-16)" =
--     section 1..16 in reaper-kb.ini. "Main action section: Toggle override to alt-N"
--     (24802 + N) puts one in front of Main at once, no restart. A key missing from it
--     falls through to REAPER's DEFAULT keys, not to the user's own ones.
--   * The override is cleared at every start, so __startup.lua switches it on again.
--
-- So the Bitwig keys go into one alt list of the user's choice; Main is never touched, and
-- "REAPER" is simply that list switched off. Single keys are added, changed and removed
-- in the list through REAPER's own shortcut dialog and DeleteActionShortcut: no restart.

local r = reaper
local K = {}
local EXT = "TK Theme Bit"
local HERE = debug.getinfo(1, "S").source:match("^@?(.*)[\\/]") or "."
local TOGGLE0 = 24802                  -- + N = Main action section: Toggle override to alt-N
local MARK = "TK Theme Bit: Bitwig shortcuts"

-- the Bitwig set. Keys from Bitwig's defaults (muted.io / tutorialtactic.com lists, checked
-- 2026-11-25); tools 1-5 left out (REAPER has no tool modes). Actions by their exact names
-- in REAPER's action list (the first one found wins; "~" = a search pattern), Bit's own
-- scripts by file name. Not found in REAPER 7.86 under the exact names: Glue, Quantize.
K.SET = {
  -- editing
  { "Ctrl+E", "Split", { "Item: Split items at edit cursor (no change selection)", "Item: Split items at edit or play cursor" } },
  { "Ctrl+D", "Duplicate", { "Item: Duplicate items" } },
  { "Ctrl+J", "Consolidate", { "Item: Glue items", "Item: Glue items, ignoring time selection", "~^item: glue items" } },
  { "Ctrl+B", "Bounce in place", { "Item: Apply track/take FX to items" } },
  { "Ctrl+G", "Group", { "Item grouping: Group items" } },
  { "Ctrl+Shift+G", "Ungroup", { "Item grouping: Remove items from group" } },
  { "Ctrl+L", "Loop selection", { "Loop points: Set loop points to items" } },
  { "Q", "Quantize", { "Item: Quantize item positions to grid", "Item: Quantize items...",
    "~^item: quantize item positions to grid", "~^item: quantize" } },
  { "S", "Snap on/off", { "Options: Toggle snapping" } },
  { "Z", "Zoom to fit", { "View: Zoom out project" } },
  { "Backspace", "Delete", { "Remove items/tracks/envelope points (depending on focus)" } },
  { "Ctrl+Shift+X", "Cut time", { "Time selection: Remove contents of time selection (moving later items)" } },
  { "Ctrl+Shift+D", "Duplicate time", { "Item: Duplicate selected area of items" } },
  { "Ctrl+Shift+P", "Insert silence", { "Time selection: Insert empty space at time selection (moving later items)" } },
  -- panels: Bit's own panel icons, so they light up
  { "M", "Mixer", nil, "TK_Theme_Bit_View_Mix.lua" },
  { "E", "Editor", nil, "TK_Theme_Bit_Editor.lua", "TK_Theme_Bit_View_Edit.lua" },
  { "O", "Arranger", nil, "TK_Theme_Bit_View_Arrange.lua" },
  { "D", "Devices", nil, "TK_Theme_Bit_Devices.lua" },
  { "I", "Inspector", nil, "TK_Theme_Bit_Inspector.lua" },
  { "A", "Automation", { "Envelope: Toggle show all envelopes for all tracks", "Track: Toggle show all envelopes for all tracks" } },
  { "Alt+B", "Browser", { "Media explorer: Show/hide media explorer", "View: Toggle media explorer window" } },
  -- transport (looked up in Bitwig 5 by the user, 2026-11-25)
  { "F9", "Record", { "Transport: Record" } },
  { "C", "Metronome", { "Options: Toggle metronome" } },
  { "Shift+L", "Arranger loop", { "Transport: Toggle repeat" } },
  { "Shift+F", "Follow playhead", { "View: Toggle auto-view-scroll during playback", "~auto%-view%-scroll" } },
  -- tracks and the rest
  { "Ctrl+T", "New instrument track", { "Insert virtual instrument on new track..." } },
  { "Ctrl+Shift+T", "New audio track", { "Track: Insert new track" } },
  { "Ctrl+Enter", "Commander", { "Show action list" } },
  { "Ctrl+,", "Settings", { "Options: Preferences...", "Options: Show REAPER preferences" } },
}

---------------------------------------------------------------- keys
local VK = { Space = 32, Backspace = 8, Enter = 13, Delete = 46, Tab = 9, [","] = 188, ["."] = 190 }

-- "Ctrl+Shift+X" -> the two numbers of a KEY line (1 = virtual key, 4 Shift, 8 Ctrl, 16 Alt)
function K.code(spec)
  local parts = {}
  for p in spec:gmatch("[^+]+") do parts[#parts + 1] = p end
  local key, flags = parts[#parts], 1
  for i = 1, #parts - 1 do
    local m = parts[i]
    flags = flags | (m == "Shift" and 4 or m == "Ctrl" and 8 or m == "Alt" and 16 or 0)
  end
  local f = key:match("^F(%d+)$")
  local vk = VK[key] or (f and 111 + tonumber(f)) or (#key == 1 and key:upper():byte())
  return flags, vk
end

-- the way REAPER writes it (Ctrl, Alt, Shift, key), to recognise the set's keys in a list
function K.desc(spec)
  local flags, _ = K.code(spec)
  local key = spec:match("([^+]+)$")
  local s = ""
  if flags & 8 ~= 0 then s = s .. "Ctrl+" end
  if flags & 16 ~= 0 then s = s .. "Alt+" end
  if flags & 4 ~= 0 then s = s .. "Shift+" end
  return s .. key
end

-- the other way round: a KEY line's two numbers -> REAPER's text, or nil for a key this
-- doesn't name (a MIDI or mouse wheel line, an odd key)
local VK_NAME = {}
for name, vk in pairs(VK) do VK_NAME[vk] = name end
function K.name(flags, vk)
  if flags & 1 == 0 or flags > 31 then return nil end
  local key = VK_NAME[vk]
  if not key then
    if (vk >= 48 and vk <= 57) or (vk >= 65 and vk <= 90) then key = string.char(vk)
    elseif vk >= 112 and vk <= 135 then key = "F" .. (vk - 111) end
  end
  if not key then return nil end
  local s = ""
  if flags & 8 ~= 0 then s = s .. "Ctrl+" end
  if flags & 16 ~= 0 then s = s .. "Alt+" end
  if flags & 4 ~= 0 then s = s .. "Shift+" end
  return s .. key
end

---------------------------------------------------------------- files
local function kb_path() return r.GetResourcePath() .. "/reaper-kb.ini" end

local function read_all(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local s = f:read("a")
  f:close()
  return s
end

local function write_all(path, s)
  local f = io.open(path, "wb")
  if not f then return false end
  f:write(s)
  f:close()
  return true
end

local function lines(s)
  local t = {}
  if s:sub(-1) ~= "\n" then s = s .. "\n" end
  for l in s:gmatch("([^\r\n]*)\r?\n") do t[#t + 1] = l end
  return t
end

-- registered scripts: file name -> "_RS..." (from the SCR lines)
local function script_ids(text)
  local ids = {}
  for l in text:gmatch("[^\r\n]+") do
    local id, path = l:match('^SCR %d+ %d+ (%S+) ".-" "(.-)"')
    if id then ids[path:match("([^/\\]+)$")] = "_" .. id end
  end
  return ids
end

-- every action of the main section: list of { cmd, name } and name -> cmd
function K.actions()
  if not K.all then
    local list, by_name = {}, {}
    local sec = r.SectionFromUniqueID(0)
    local i = 0
    while true do
      local cmd, name = r.kbd_enumerateActions(sec, i)
      if not cmd or cmd == 0 then break end
      list[#list + 1] = { cmd = cmd, name = name }
      if not by_name[name] then by_name[name] = cmd end
      i = i + 1
    end
    table.sort(list, function(a, b) return a.name:lower() < b.name:lower() end)
    K.all, K.by_name = list, by_name
  end
  return K.all, K.by_name
end

-- the set with its actions found: each { spec, what, cmd, id (as in reaper-kb.ini) };
-- and the entries not found
function K.resolve()
  local _, by_name = K.actions()
  local ids = script_ids(read_all(kb_path()) or "")
  local found, missing = {}, {}
  for _, e in ipairs(K.SET) do
    local cmd, id
    if e[4] then
      -- Bit's scripts: the first registered one (a newer script may not be yet)
      for j = 4, #e do
        id = ids[e[j]]
        if id then cmd = r.NamedCommandLookup(id) if cmd == 0 then cmd = nil end end
        if cmd then break end
      end
    else
      -- exact names first; "~pattern" searches the names (lower case), shortest match wins
      for _, name in ipairs(e[3]) do
        if name:sub(1, 1) == "~" then
          local best
          for _, a in ipairs(K.all) do
            if a.name:lower():find(name:sub(2)) and (not best or #a.name < #best.name) then best = a end
          end
          if best then cmd = best.cmd id = tostring(cmd) break end
        elseif by_name[name] then
          cmd = by_name[name] id = tostring(cmd) break
        end
      end
    end
    if cmd then
      found[#found + 1] = { spec = e[1], what = e[2], cmd = cmd, id = id }
    else
      missing[#missing + 1] = e[1] .. " (" .. e[2] .. ")"
    end
  end
  return found, missing
end

-- explicit keys per alt list in reaper-kb.ini: counts[N] and lines[N] = { {cmd id, flags, vk} }
function K.alt_lists()
  local counts, keys = {}, {}
  for n = 1, 16 do counts[n] = 0 keys[n] = {} end
  for l in (read_all(kb_path()) or ""):gmatch("[^\r\n]+") do
    local f, v, c, s = l:match("^KEY (%d+) (%d+) (%S+) (%d+)")
    s = tonumber(s)
    if s and s >= 1 and s <= 16 then
      counts[s] = counts[s] + 1
      keys[s][#keys[s] + 1] = { c, tonumber(f), tonumber(v) }
    end
  end
  return counts, keys
end

-- the highest empty list, to suggest
function K.suggest()
  local counts = K.alt_lists()
  for n = 16, 1, -1 do if counts[n] == 0 then return n end end
  return 16
end

---------------------------------------------------------------- state
function K.alt() return tonumber(r.GetExtState(EXT, "keys_alt")) end
function K.installed() return r.GetExtState(EXT, "keys_installed") == "1" and K.alt() ~= nil end
function K.active()
  local n = K.alt()
  return n ~= nil and r.GetToggleCommandState(TOGGLE0 + n) == 1
end

-- are the set's lines in reaper-kb.ini? (gone when REAPER rewrote the file before the restart)
function K.arrived()
  local n = K.alt()
  if not n then return false end
  local _, keys = K.alt_lists()
  return #keys[n] > 0
end

function K.set_on(on)
  local n = K.alt()
  if not n then return end
  if K.active() ~= on then r.Main_OnCommand(TOGGLE0 + n, 0) end
  r.SetExtState(EXT, "keys_on", on and "1" or "0", true)
end

---------------------------------------------------------------- REAPER's start
local function startup_path() return r.GetResourcePath() .. "/Scripts/__startup.lua" end

function K.startup_line(add)
  local p = startup_path()
  local s = read_all(p) or ""
  local out = {}
  for _, l in ipairs(lines(s)) do
    if not l:find(MARK, 1, true) then out[#out + 1] = l end
  end
  while #out > 0 and out[#out] == "" do out[#out] = nil end
  if add then
    local me = (HERE .. "/TK_Theme_Bit_Keys.lua"):gsub("\\", "/")
    out[#out + 1] = "-- " .. MARK .. ": switches the chosen list on at start (Settings > Shortcuts)"
    out[#out + 1] = "do local f = [[" .. me .. "]] if reaper.file_exists(f) then TK_BIT_KEYS_STARTUP = true "
      .. "dofile(f) TK_BIT_KEYS_STARTUP = nil end end -- " .. MARK
  end
  return write_all(p, table.concat(out, "\n") .. "\n")
end

function K.startup()
  if K.installed() and r.GetExtState(EXT, "keys_on") ~= "0" and not K.active() then
    r.Main_OnCommand(TOGGLE0 + K.alt(), 0)
  end
end

---------------------------------------------------------------- install / remove
-- writes the set into alt list n of reaper-kb.ini (a key of the set already in that list
-- is replaced; everything else stays), then REAPER must restart to read it
function K.install(n)
  local found, missing = K.resolve()
  local taken = {}
  for _, e in ipairs(found) do
    local f, v = K.code(e.spec)
    taken[f .. " " .. v] = true
  end
  local s = read_all(kb_path())
  if not s then return false, "Could not read reaper-kb.ini." end
  local out = {}
  for _, l in ipairs(lines(s)) do
    local f, v, _, sec = l:match("^KEY (%d+) (%d+) (%S+) (%d+)")
    if not (sec and tonumber(sec) == n and taken[f .. " " .. v]) then out[#out + 1] = l end
  end
  while #out > 0 and out[#out] == "" do out[#out] = nil end
  for _, e in ipairs(found) do
    local f, v = K.code(e.spec)
    out[#out + 1] = ("KEY %d %d %s %d\t\t # Main alt %d : %s : Bitwig %s"):format(f, v, e.id, n, n, K.desc(e.spec), e.what)
  end
  if not write_all(kb_path(), table.concat(out, "\r\n") .. "\r\n") then
    return false, "Could not write reaper-kb.ini."
  end
  r.SetExtState(EXT, "keys_alt", tostring(n), true)
  r.SetExtState(EXT, "keys_installed", "1", true)
  r.SetExtState(EXT, "keys_on", "1", true)
  K.startup_line(true)
  return true, missing
end

-- takes the set's keys out of the list again (at once, through the API), switches the
-- list off and REAPER's start no longer touches it. Keys you added yourself stay.
function K.remove()
  local n = K.alt()
  if not n then return end
  if K.active() then r.Main_OnCommand(TOGGLE0 + n, 0) end
  -- per action of the set: its keys in the list that aren't its keys in Main
  local sec, main = r.SectionFromUniqueID(n), r.SectionFromUniqueID(0)
  local found = K.resolve()
  for _, e in ipairs(found) do
    local in_main = {}
    for i = 0, r.CountActionShortcuts(main, e.cmd) - 1 do
      local _, d = r.GetActionShortcutDesc(main, e.cmd, i)
      in_main[d] = true
    end
    for i = r.CountActionShortcuts(sec, e.cmd) - 1, 0, -1 do
      local _, d = r.GetActionShortcutDesc(sec, e.cmd, i)
      if not in_main[d] then r.DeleteActionShortcut(sec, e.cmd, i) end
    end
  end
  r.DeleteExtState(EXT, "keys_installed", true)
  r.DeleteExtState(EXT, "keys_on", true)
  K.startup_line(false)
end

---------------------------------------------------------------- the list
-- per action: the keys that work with the Bitwig list on, and the user's own Main keys
-- that don't. A key's kind:
--   bitwig   in the list, one of the set     (orange)
--   own      in the list, added by the user   (white)
--   default  REAPER's default, falls through  (grey)
--   hidden   a default another key of the list took over
--   lost     the user's own Main key, not working with the list on (can be taken over)
-- what the rows are built from: the two sections, the list's own lines in reaper-kb.ini
-- per action by key text (an action with a line whose key isn't named here falls back to
-- "not one of its Main keys"), and the set's keys
function K.context()
  local n = K.alt()
  if not n then return nil end
  local _, keys = K.alt_lists()
  local explicit, unnamed = {}, {}
  for _, k in ipairs(keys[n]) do
    local c = tonumber(k[1]) or r.NamedCommandLookup(k[1])
    if c and c ~= 0 then
      local d = K.name(k[2], k[3])
      if d then
        explicit[c] = explicit[c] or {}
        explicit[c][d] = true
      else
        unnamed[c] = true
      end
    end
  end
  local set = {}
  for _, e in ipairs(K.SET) do set[K.desc(e[1])] = true end
  return { alt = r.SectionFromUniqueID(n), main = r.SectionFromUniqueID(0),
           explicit = explicit, unnamed = unnamed, set = set }
end

-- one action's keys, each with its base kind (bitwig / own / default / lost)
function K.fill_row(c, row)
  local ak, mk = {}, {}
  for i = 0, r.CountActionShortcuts(c.alt, row.cmd) - 1 do
    local _, d = r.GetActionShortcutDesc(c.alt, row.cmd, i)
    ak[#ak + 1] = { desc = d, idx = i }
  end
  for i = 0, r.CountActionShortcuts(c.main, row.cmd) - 1 do
    local _, d = r.GetActionShortcutDesc(c.main, row.cmd, i)
    mk[d] = true
  end
  row.keys = {}
  local in_alt = {}
  for _, k in ipairs(ak) do
    in_alt[k.desc] = true
    local ex = c.explicit[row.cmd]
    local own = (ex and ex[k.desc]) or (c.unnamed[row.cmd] and not mk[k.desc])
    k.base = own and (c.set[k.desc] and "bitwig" or "own") or "default"
    row.keys[#row.keys + 1] = k
  end
  for d in pairs(mk) do
    if not in_alt[d] then row.keys[#row.keys + 1] = { desc = d, base = "lost" } end
  end
  return row
end

-- the kinds to show: a default or own Main key whose key the list gave to another
-- action is "hidden" (no API calls: cheap to run over all rows after every change)
function K.mark(rows)
  local used = {}
  for _, row in ipairs(rows) do
    for _, k in ipairs(row.keys) do
      if k.base == "bitwig" or k.base == "own" then used[k.desc] = true end
    end
  end
  for _, row in ipairs(rows) do
    for _, k in ipairs(row.keys) do
      k.kind = ((k.base == "default" or k.base == "lost") and used[k.desc]) and "hidden" or k.base
    end
  end
end

function K.model()
  local c = K.context()
  if not c then return {} end
  local rows = {}
  for _, a in ipairs(K.actions()) do
    rows[#rows + 1] = K.fill_row(c, { cmd = a.cmd, name = a.name })
  end
  K.mark(rows)
  return rows
end

-- after one action changed: that row again, and the rows that share one of its keys
-- (REAPER's dialog may have taken the key from another action)
function K.refresh(rows, cmd)
  local c = K.context()
  if not c then return end
  local touched = {}
  for _, row in ipairs(rows) do
    if row.cmd == cmd then
      for _, k in ipairs(row.keys) do touched[k.desc] = true end
      K.fill_row(c, row)
      for _, k in ipairs(row.keys) do touched[k.desc] = true end
    end
  end
  for _, row in ipairs(rows) do
    if row.cmd ~= cmd then
      for _, k in ipairs(row.keys) do
        if touched[k.desc] then K.fill_row(c, row) break end
      end
    end
  end
  K.mark(rows)
end

if TK_BIT_KEYS_STARTUP then K.startup() end
return K
