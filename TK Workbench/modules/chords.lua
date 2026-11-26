-- Chords: the chords a project uses, in slots, ready to insert; and progressions to try.
-- Slots live in the project (ProjExtState), the options in REAPER's ExtState. Chord types and
-- their notes come from core/chord_engine (the same the Cue module reads chords with). The
-- layout follows the panel's width: cards and an editor beside them when wide, a list whose
-- rows fold open on a keyboard when the module sits in a narrow docker.
local r = reaper
local Theme = require("core.theme")
local UI = require("core.ui")
local UIScale = require("core.ui_scale")
local Engine = require("core.chord_engine")
local json = require("core.json")

local M = {
  id = "chords",
  title = "Chords",
  icon = "CHD",
  version = "0.1.0"
}

local EXT = "TK_Workbench_Chords"
local SLOT_COUNT = 8
local WIDE_FROM = 600
local NOTES = { "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B" }
local TYPE_ORDER = { "", "m", "7", "maj7", "m7", "sus2", "sus4", "dim", "aug", "add9", "6", "m6", "9", "m9", "m7b5", "5" }
local LENGTHS = { "1 beat", "2 beats", "1 bar", "2 bars", "4 bars" }
local VOICES = { "Close", "Open", "Drop 2" }
local INVERSIONS = { "Root", "1st", "2nd", "3rd" }
local SCALES = {
  Major = { 0, 2, 4, 5, 7, 9, 11 },
  Minor = { 0, 2, 3, 5, 7, 8, 10 },
  Dorian = { 0, 2, 3, 5, 7, 9, 10 },
  Mixolydian = { 0, 2, 4, 5, 7, 9, 10 }
}
local MODES = { "Major", "Minor", "Dorian", "Mixolydian" }
local ROMAN = { "I", "II", "III", "IV", "V", "VI", "VII" }
-- progressions per style, as scale degrees (0 = I): common patterns, so every idea sounds like music
local STYLES = { "Pop", "Ballad", "Epic", "Jazz", "Lo-fi" }
local PATTERNS = {
  Pop = { { 0, 4, 5, 3 }, { 0, 5, 3, 4 }, { 5, 3, 0, 4 }, { 0, 3, 4, 3 }, { 0, 4, 5, 2 }, { 3, 0, 4, 5 } },
  Ballad = { { 0, 2, 3, 4 }, { 0, 5, 1, 4 }, { 0, 4, 5, 2 }, { 3, 4, 2, 5 }, { 0, 3, 1, 4 } },
  Epic = { { 5, 3, 0, 4 }, { 0, 6, 3, 4 }, { 5, 4, 3, 4 }, { 0, 3, 5, 4 }, { 5, 6, 0, 4 } },
  Jazz = { { 1, 4, 0, 0 }, { 0, 5, 1, 4 }, { 2, 5, 1, 4 }, { 0, 3, 1, 4 } },
  ["Lo-fi"] = { { 3, 2, 1, 0 }, { 0, 5, 3, 4 }, { 1, 4, 0, 5 }, { 3, 4, 2, 5 } }
}
local COLOURS = { "Triads", "Some 7ths", "Rich" }

local TYPES = {}
for _, form in ipairs(Engine.forms()) do TYPES[form.suffix] = form.tones end

local state = {
  tab = "slots",
  project = nil,
  slots = {},
  sel = 1,
  view = "list",          -- narrow: "list" or "edit"
  open = {},              -- narrow: rows folded open on their keyboard
  key = 0,
  mode = "Major",
  gear = false,
  status = nil,
  last_end = nil,
  off_at = nil,
  sounding = nil,
  queue = nil,
  insp = { key = 0, mode = "Major", style = 1, count = 4, colour = 2, prog = {}, locked = {}, history = {} },
  opt = { target = 1, where = 1, follow = true, audition = true, markers = false, velocity = 96, strum = 0, humanize = 10, fill = 1 }
}

-- ------------------------------------------------------------------ storage

local store = {}

function store.load_options()
  local s = r.GetExtState(EXT, "options")
  if s ~= "" then
    local ok, t = pcall(json.decode, s)
    if ok and type(t) == "table" then
      for k, v in pairs(t) do if state.opt[k] ~= nil then state.opt[k] = v end end
    end
  end
end

function store.save_options()
  r.SetExtState(EXT, "options", json.encode(state.opt), true)
end

function store.load_project(project)
  state.project = project
  state.slots, state.open, state.sel, state.view = {}, {}, 1, "list"
  state.key, state.mode = 0, "Major"
  local _, s = r.GetProjExtState(project, EXT, "slots")
  if s and s ~= "" then
    local ok, t = pcall(json.decode, s)
    if ok and type(t) == "table" then
      for i = 1, SLOT_COUNT do
        local slot = t.slots and t.slots[i]
        state.slots[i] = type(slot) == "table" and slot or false
      end
      state.key = tonumber(t.key) or 0
      state.mode = SCALES[t.mode] and t.mode or "Major"
    end
  end
  for i = 1, SLOT_COUNT do if state.slots[i] == nil then state.slots[i] = false end end
end

function store.save_project()
  if not state.project then return end
  local t = { key = state.key, mode = state.mode, slots = {} }
  for i = 1, SLOT_COUNT do t.slots[i] = state.slots[i] or false end
  r.SetProjExtState(state.project, EXT, "slots", json.encode(t))
  r.MarkProjectDirty(state.project)
end

-- chord sets: the slots under a name, kept in REAPER (so any project can load them)
function store.sets()
  local s = r.GetExtState(EXT, "sets")
  local ok, t = pcall(json.decode, s ~= "" and s or "{}")
  return (ok and type(t) == "table") and t or {}
end

function store.save_set(name)
  local sets = store.sets()
  local slots = {}
  for i = 1, SLOT_COUNT do slots[i] = state.slots[i] or false end
  sets[name] = { key = state.key, mode = state.mode, slots = slots }
  r.SetExtState(EXT, "sets", json.encode(sets), true)
end

function store.load_set(name)
  local set = store.sets()[name]
  if type(set) ~= "table" then return false end
  for i = 1, SLOT_COUNT do
    local slot = set.slots and set.slots[i]
    state.slots[i] = type(slot) == "table" and slot or false
  end
  state.key = tonumber(set.key) or state.key
  state.mode = SCALES[set.mode] and set.mode or state.mode
  state.sel, state.open, state.view = 1, {}, "list"
  store.save_project()
  return true
end

function store.delete_set(name)
  local sets = store.sets()
  sets[name] = nil
  r.SetExtState(EXT, "sets", json.encode(sets), true)
end

-- ------------------------------------------------------------------ music

local music = {}

function music.new_slot(root)
  return { root = root or state.key, type = "", inv = 0, voice = "Close", oct = 4, len = "1 bar" }
end

function music.notes(s)
  local tones = TYPES[s.type] or TYPES[""]
  local n = {}
  for i, t in ipairs(tones) do n[i] = s.root + t + 12 * ((s.oct or 4) + 1) end
  local inv = math.min(s.inv or 0, #n - 1)
  for _ = 1, inv do
    local low = table.remove(n, 1)     -- (taken out first: n[#n + 1] would count before it)
    n[#n + 1] = low + 12
  end
  table.sort(n)
  if s.voice == "Open" and #n >= 3 then n[2] = n[2] + 12; table.sort(n)
  elseif s.voice == "Drop 2" and #n >= 4 then n[#n - 1] = n[#n - 1] - 12; table.sort(n) end
  return n
end

function music.name(s)
  local name = NOTES[s.root + 1] .. s.type
  if (s.inv or 0) > 0 then name = name .. "/" .. NOTES[music.notes(s)[1] % 12 + 1] end
  return name
end

function music.roman(s, key, mode)
  local scale = SCALES[mode or state.mode]
  key = key or state.key
  local degree
  for i, step in ipairs(scale) do if (step + key) % 12 == s.root then degree = i end end
  if not degree then return "" end
  local numeral = ROMAN[degree]
  if s.type == "dim" or s.type == "m7b5" then return numeral:lower() .. "°" .. (s.type == "m7b5" and "7" or "") end
  -- minor (an m that isn't maj): the numeral in lower case, the m left out of what follows
  if s.type:sub(1, 1) == "m" and s.type:sub(1, 3) ~= "maj" then return numeral:lower() .. s.type:sub(2) end
  return numeral .. s.type
end

-- a chord on a scale degree, coloured as asked: triads, some sevenths, or rich (9ths, sus)
function music.on_degree(degree, key, mode, colour, index)
  local scale = SCALES[mode]
  local root = (scale[degree % 7 + 1] + key) % 12
  local function step(n) return (scale[(degree + n) % 7 + 1] - scale[degree % 7 + 1] + 12) % 12 end
  local third, fifth, seventh = step(2), step(4), step(6)
  local t = third == 3 and (fifth == 6 and "dim" or "m") or ""
  local rich = colour == 3
  if colour == 3 or (colour == 2 and index % 2 == 0) then
    if t == "dim" then t = "m7b5"
    elseif t == "m" then t = rich and "m9" or "m7"
    else t = seventh == 11 and (rich and "add9" or "maj7") or "7" end
  end
  if rich and index == 4 and t == "7" then t = "sus4" end
  return { root = root, type = t, inv = 0, voice = "Close", oct = 3, len = "1 bar", deg = degree % 7 }
end

function music.length_qn(len, pos)
  local num, denom = 4, 4
  if r.TimeMap_GetTimeSigAtTime then
    local n, d = r.TimeMap_GetTimeSigAtTime(0, pos)
    if (tonumber(n) or 0) > 0 then num = n end
    if (tonumber(d) or 0) > 0 then denom = d end
  end
  local beat = 4 / denom
  if len == "1 beat" then return beat end
  if len == "2 beats" then return beat * 2 end
  if len == "2 bars" then return beat * num * 2 end
  if len == "4 bars" then return beat * num * 4 end
  return beat * num
end

-- ------------------------------------------------------------------ REAPER

local act = {}

function act.target_track()
  if state.opt.target == 2 then return r.GetLastTouchedTrack() end
  return r.GetSelectedTrack(0, 0)
end

-- one MIDI item holding the chords one after another; returns its end, or nil and why
function act.insert(list)
  local track = act.target_track()
  if not track then return nil, state.opt.target == 2 and "Touch a track first." or "Select a track first." end
  if #list == 0 then return nil, "Nothing to insert." end
  local pos = r.GetCursorPosition()
  if state.opt.where == 2 and state.last_end then pos = state.last_end end
  local start_qn = r.TimeMap2_timeToQN(0, pos)
  local spans, qn = {}, start_qn
  for i, s in ipairs(list) do
    local len = music.length_qn(s.len, r.TimeMap2_QNToTime(0, qn))
    spans[i] = { qn, qn + len }
    qn = qn + len
  end
  local end_time = r.TimeMap2_QNToTime(0, qn)
  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)
  local item = r.CreateNewMIDIItemInProj(track, pos, end_time, false)
  local take = item and r.GetActiveTake(item)
  if not take then
    r.PreventUIRefresh(-1)
    r.Undo_EndBlock("Chords: insert", -1)
    return nil, "Could not make a MIDI item there."
  end
  local names = {}
  local o = state.opt
  for i, s in ipairs(list) do
    local notes = music.notes(s)
    local t0, t1 = r.TimeMap2_QNToTime(0, spans[i][1]), r.TimeMap2_QNToTime(0, spans[i][2])
    local end_ppq = r.MIDI_GetPPQPosFromProjTime(take, t1)
    for k, note in ipairs(notes) do
      local start_ppq = r.MIDI_GetPPQPosFromProjTime(take, t0 + (k - 1) * (o.strum or 0) / 1000)
      local vel = act.velocity()
      r.MIDI_InsertNote(take, false, false, start_ppq, end_ppq, 0, math.max(0, math.min(127, note)), vel, true)
    end
    names[#names + 1] = music.name(s)
    if o.markers then r.AddProjectMarker2(0, false, t0, 0, music.name(s), -1, 0) end
  end
  r.MIDI_Sort(take)
  r.GetSetMediaItemTakeInfo_String(take, "P_NAME", table.concat(names, " "), true)
  r.PreventUIRefresh(-1)
  r.UpdateArrange()
  r.Undo_EndBlock("Chords: insert " .. table.concat(names, " "), -1)
  if o.follow then r.SetEditCurPos(end_time, true, false) end
  state.last_end = end_time
  return end_time
end

function act.insert_slots(indices)
  local list = {}
  for _, i in ipairs(indices) do if state.slots[i] then list[#list + 1] = state.slots[i] end end
  local ok, why = act.insert(list)
  state.status = ok and ("Inserted " .. #list .. (#list == 1 and " chord" or " chords") .. ".") or why
end

-- hear a chord through REAPER's virtual keyboard input (a track armed and monitoring it plays it)
-- the velocity a note gets: the set one, humanized by up to the set share either way
function act.velocity()
  local o = state.opt
  local base = o.velocity or 96
  local spread = math.floor(base * (o.humanize or 0) / 100)
  return math.max(1, math.min(127, base + (spread > 0 and math.random(-spread, spread) or 0)))
end

-- id: the button that plays it (it turns into Stop); hold: sound until stopped. The notes come
-- in one after another by the strum (as close as the defer loop's ~30 per second allows)
function act.sound(notes, id, hold)
  act.silence()
  state.return_at = nil            -- still in use: no putting back now
  act.borrow_track()
  local now, strum = r.time_precise(), (state.opt.strum or 0) / 1000
  state.note_queue = {}
  for k, n in ipairs(notes) do
    if strum <= 0 or k == 1 then
      r.StuffMIDIMessage(0, 0x90, n, act.velocity())
    else
      state.note_queue[#state.note_queue + 1] = { at = now + (k - 1) * strum, note = n }
    end
  end
  if #state.note_queue == 0 then state.note_queue = nil end
  state.sounding, state.sounding_id = notes, id
  state.off_at = not hold and (now + 0.8 + (#notes - 1) * strum) or nil
  act.watch()
end

-- a Play button that is Stop while its chord sounds
function act.play_button(ctx, id, notes, label_id)
  local playing = state.sounding_id == id
  if playing then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), Theme.colors.warning) end
  local clicked = r.ImGui_Button(ctx, (playing and "Stop" or "Play") .. "##" .. label_id)
  if playing then r.ImGui_PopStyleColor(ctx) end
  if clicked then
    if playing then act.stop() else act.sound(notes, id, true) end
  end
end

-- REAPER only sounds the virtual keyboard on a track armed to hear it. Unless it already does,
-- the target track is armed for the moment, on the virtual keyboard, and put back afterwards.
-- Never while recording
local VKB_INPUT = 4096 + (62 << 5)
function act.borrow_track()
  if state.borrowed then return end
  local track = act.target_track()
  if not track or (r.GetPlayState() & 4) == 4 then return end
  local armed = r.GetMediaTrackInfo_Value(track, "I_RECARM")
  local input = math.floor(r.GetMediaTrackInfo_Value(track, "I_RECINPUT"))
  local mon = r.GetMediaTrackInfo_Value(track, "I_RECMON")
  local device = input >= 4096 and ((input >> 5) & 63) or -1
  if armed == 1 and mon > 0 and (device == 62 or device == 63) then return end
  state.borrowed = { track = track, armed = armed, input = input, mon = mon }
  r.SetMediaTrackInfo_Value(track, "I_RECINPUT", VKB_INPUT)
  r.SetMediaTrackInfo_Value(track, "I_RECMON", 1)
  r.SetMediaTrackInfo_Value(track, "I_RECARM", 1)
end

function act.return_track()
  local b = state.borrowed
  state.borrowed = nil
  if not b or not r.ValidatePtr(b.track, "MediaTrack*") then return end
  r.SetMediaTrackInfo_Value(b.track, "I_RECARM", b.armed)
  r.SetMediaTrackInfo_Value(b.track, "I_RECINPUT", b.input)
  r.SetMediaTrackInfo_Value(b.track, "I_RECMON", b.mon)
end

-- the note-offs go out while the track still hears them; it is put back a moment later
-- (put back at once, the offs reached a track no longer listening and the chord hung on)
function act.silence()
  state.note_queue = nil
  for _, n in ipairs(state.sounding or {}) do r.StuffMIDIMessage(0, 0x80, n, 0) end
  state.sounding, state.sounding_id, state.off_at = nil, nil, nil
  if not state.queue and state.borrowed then state.return_at = r.time_precise() + 0.3 end
end

-- Stop: the queue gone, the chord off, and REAPER's "all notes off" for whatever else hangs
function act.stop()
  state.queue = nil
  act.silence()
  r.Main_OnCommand(40345, 0)       -- Send all-notes-off and all-sounds-off to all MIDI outputs/plug-ins
  act.watch()
end

function act.audition(notes)
  if state.opt.audition then act.sound(notes) end
end

function act.play_list(list)
  state.queue = {}
  local t0 = r.time_precise()
  for i, s in ipairs(list) do state.queue[i] = { at = t0 + (i - 1) * 0.75, notes = music.notes(s) } end
  act.watch()
end

function act.tick()
  local now = r.time_precise()
  if state.note_queue then
    while state.note_queue[1] and now >= state.note_queue[1].at do
      r.StuffMIDIMessage(0, 0x90, table.remove(state.note_queue, 1).note, act.velocity())
    end
    if not state.note_queue[1] then state.note_queue = nil end
  end
  if state.queue and state.queue[1] and now >= state.queue[1].at then
    local nxt = table.remove(state.queue, 1)
    if #state.queue == 0 then state.queue = nil end
    act.sound(nxt.notes)
  end
  if state.off_at and now >= state.off_at then act.silence() end
  if state.return_at and now >= state.return_at then
    state.return_at = nil
    act.return_track()
  end
end

-- its own deferred loop, so the notes stop and the track is put back even when another
-- module is shown before the chord has ended
function act.watch()
  if state.watching then return end
  state.watching = true
  local function loop()
    act.tick()
    if state.sounding or state.queue or state.return_at then r.defer(loop) else state.watching = false end
  end
  r.defer(loop)
end

-- ------------------------------------------------------------------ drawing helpers

local draw = {}

function draw.keys(ctx, notes, w, h)
  local dl = r.ImGui_GetWindowDrawList(ctx)
  local x, y = r.ImGui_GetCursorScreenPos(ctx)
  local lo = math.floor((notes[1] or 60) / 12) * 12
  local span = ((notes[#notes] or 60) - lo >= 24) and 36 or 24
  local whites = {}
  for p = lo, lo + span - 1 do
    local c = p % 12
    if not (c == 1 or c == 3 or c == 6 or c == 8 or c == 10) then whites[#whites + 1] = p end
  end
  local on = {}
  for _, n in ipairs(notes) do on[n] = true end
  local ww = w / #whites
  for i, p in ipairs(whites) do
    r.ImGui_DrawList_AddRectFilled(dl, x + (i - 1) * ww, y, x + i * ww - 1, y + h, on[p] and Theme.colors.accent or 0xD9DEE6FF, 1.5)
  end
  for p = lo, lo + span - 1 do
    local c = p % 12
    if c == 1 or c == 3 or c == 6 or c == 8 or c == 10 then
      local before = 0
      for _, wp in ipairs(whites) do if wp < p then before = before + 1 end end
      local bx = x + before * ww - ww * 0.3
      r.ImGui_DrawList_AddRectFilled(dl, bx, y, bx + ww * 0.6, y + h * 0.6, on[p] and Theme.colors.accent or 0x1A1D22FF, 1)
    end
  end
  r.ImGui_Dummy(ctx, w, h)
end

function draw.tab(ctx, label, id)
  local active = state.tab == id
  if active then
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), Theme.colors.accent)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), Theme.colors.accent)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), Theme.text_for_backgrounds({ Theme.colors.accent }, Theme.colors.text, nil, 4.5))
  end
  local clicked = r.ImGui_Button(ctx, label .. "##chords_tab_" .. id, UIScale.text_button_w(ctx, label, 80), 0)
  if active then r.ImGui_PopStyleColor(ctx, 3) end
  if clicked then state.tab = id end
end

-- a row of choice buttons, wrapping; returns the index clicked or nil
function draw.choices(ctx, id, labels, current, width, columns)
  local picked
  local avail = width or select(1, r.ImGui_GetContentRegionAvail(ctx))
  local gap = UIScale.round(4)
  local w = columns and math.floor((avail - gap * (columns - 1)) / columns) or nil
  local x0 = r.ImGui_GetCursorPosX(ctx)
  local used = 0
  for i, label in ipairs(labels) do
    local bw = w or UIScale.text_button_w(ctx, label, UIScale.round(34), UIScale.round(10))
    if i > 1 then
      if used + gap + bw > avail then used = 0 else r.ImGui_SameLine(ctx, 0, gap); used = used + gap end
    end
    if used == 0 then r.ImGui_SetCursorPosX(ctx, x0) end
    local active = i == current
    if active then
      r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), Theme.colors.accent)
      r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), Theme.text_for_backgrounds({ Theme.colors.accent }, Theme.colors.text, nil, 4.5))
    end
    r.ImGui_PushID(ctx, id .. i)
    if r.ImGui_Button(ctx, label, bw, 0) then picked = i end
    r.ImGui_PopID(ctx)
    if active then r.ImGui_PopStyleColor(ctx, 2) end
    used = used + bw
  end
  return picked
end

function draw.combo(ctx, id, labels, current, width)
  r.ImGui_SetNextItemWidth(ctx, math.max(UIScale.round(40), math.floor(width)))
  local changed, idx = r.ImGui_Combo(ctx, id, current - 1, table.concat(labels, "\0") .. "\0")
  if changed then return idx + 1 end
end

-- key and mode in the width given: the key a third of it, the mode the rest
function draw.key_mode(ctx, key, mode, id, modes, width)
  local gap = UIScale.round(4)
  local kw = math.floor((width - gap) * 0.36)
  local k = draw.combo(ctx, "##key" .. id, NOTES, key + 1, kw)
  r.ImGui_SameLine(ctx, 0, gap)
  local mi = 1
  for i, m in ipairs(modes) do if m == mode then mi = i end end
  local m = draw.combo(ctx, "##mode" .. id, modes, mi, width - kw - gap)
  return k and k - 1 or key, m and modes[m] or mode, (k ~= nil or m ~= nil)
end

-- ------------------------------------------------------------------ slots tab

local slots_ui = {}

-- Dragging a slot to another place, with the mouse itself (not ImGui's drag and drop): picked
-- up once the mouse moves with the button down on a filled slot; the slot under the mouse is
-- the place; let go there to move it (the others shift up or down)
function slots_ui.drag_item(ctx, i, x, y, w, h)
  local dl = r.ImGui_GetWindowDrawList(ctx)
  if state.slots[i] and r.ImGui_IsItemActive(ctx) and r.ImGui_IsMouseDragging(ctx, 0, UIScale.round(6)) then
    state.drag_from = state.drag_from or i
  end
  if state.drag_from then
    local over = r.ImGui_IsItemHovered(ctx, r.ImGui_HoveredFlags_AllowWhenBlockedByActiveItem())
    if over then state.drag_to = i end
    if state.drag_to == i and i ~= state.drag_from then
      r.ImGui_DrawList_AddRect(dl, x - 1, y - 1, x + w + 1, y + h + 1, Theme.colors.accent, UIScale.round(5), 0, 2.5)
    end
    if i == state.drag_from then
      r.ImGui_DrawList_AddRectFilled(dl, x, y, x + w, y + h, 0x00000066, UIScale.round(5))
    end
  end
end

-- after the slots are drawn: the name follows the mouse, and letting go moves the slot
function slots_ui.drag_end(ctx)
  local from = state.drag_from
  if not from then return end
  local s = state.slots[from]
  if s then
    local mx, my = r.ImGui_GetMousePos(ctx)
    r.ImGui_DrawList_AddText(r.ImGui_GetForegroundDrawList(ctx), mx + UIScale.round(12), my, Theme.colors.accent, music.name(s))
  end
  if r.ImGui_IsMouseReleased(ctx, 0) then
    local to = state.drag_to
    state.drag_from, state.drag_to = nil, nil
    if s and to and to ~= from then
      table.remove(state.slots, from)
      table.insert(state.slots, to, s)
      state.sel, state.open = to, {}
      store.save_project()
      state.status = music.name(s) .. " moved to slot " .. to .. "."
    end
  end
end

-- Save set / Load set: popups under the slots
function slots_ui.sets(ctx)
  if r.ImGui_Button(ctx, "Save set##chords_saveset") then
    state.set_name = state.set_name or ""
    r.ImGui_OpenPopup(ctx, "chords_save_set")
  end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "Load set##chords_loadset") then r.ImGui_OpenPopup(ctx, "chords_load_set") end
  if r.ImGui_BeginPopup(ctx, "chords_save_set") then
    r.ImGui_Text(ctx, "Save the slots as a set")
    if r.ImGui_IsWindowAppearing(ctx) then r.ImGui_SetKeyboardFocusHere(ctx) end
    r.ImGui_SetNextItemWidth(ctx, UIScale.round(200))
    local changed, name = r.ImGui_InputText(ctx, "##chords_set_name", state.set_name or "")
    if changed then state.set_name = name end
    local clean = (state.set_name or ""):match("^%s*(.-)%s*$")
    local enter = r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_Enter(), false)
    if (r.ImGui_Button(ctx, "Save##chords_set_save") or enter) and clean ~= "" then
      local existed = store.sets()[clean] ~= nil
      store.save_set(clean)
      state.status = existed and ("Set \"" .. clean .. "\" updated.") or ("Saved as \"" .. clean .. "\".")
      r.ImGui_CloseCurrentPopup(ctx)
    end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Cancel##chords_set_cancel") then r.ImGui_CloseCurrentPopup(ctx) end
    if store.sets()[clean] then r.ImGui_TextColored(ctx, Theme.colors.warning, "A set by this name is replaced.") end
    r.ImGui_EndPopup(ctx)
  end
  if r.ImGui_BeginPopup(ctx, "chords_load_set") then
    local names = {}
    for name in pairs(store.sets()) do names[#names + 1] = name end
    table.sort(names, function(a, b) return a:lower() < b:lower() end)
    if #names == 0 then
      r.ImGui_TextColored(ctx, Theme.colors.text_dim, "No sets yet: Save set keeps the slots under a name.")
    end
    for _, name in ipairs(names) do
      local set = store.sets()[name]
      local list = {}
      for i = 1, SLOT_COUNT do
        local slot = set.slots and set.slots[i]
        if type(slot) == "table" then list[#list + 1] = music.name(slot) end
      end
      if r.ImGui_Selectable(ctx, name .. "   " .. table.concat(list, " ") .. "##chords_set_" .. name, false, 0, UIScale.round(320), 0) then
        store.load_set(name)
        state.status = "Loaded \"" .. name .. "\"."
        r.ImGui_CloseCurrentPopup(ctx)
      end
      r.ImGui_SameLine(ctx)
      if r.ImGui_SmallButton(ctx, "Delete##chords_set_del_" .. name) then
        store.delete_set(name)
        state.status = "Deleted \"" .. name .. "\"."
      end
    end
    r.ImGui_EndPopup(ctx)
  end
end

function slots_ui.options(ctx, wide)
  local o, changed = state.opt, false
  local function check(label, key)
    local c, v = r.ImGui_Checkbox(ctx, label, o[key])
    if c then o[key] = v; changed = true end
  end
  local avail = select(1, r.ImGui_GetContentRegionAvail(ctx))
  local gap = UIScale.round(6)
  if wide then
    -- one row: two choices sharing what the labels leave
    local labels_w = r.ImGui_CalcTextSize(ctx, "Insert on") + r.ImGui_CalcTextSize(ctx, "at") + gap * 4
    local cw = math.floor((avail - labels_w) / 2)
    r.ImGui_Text(ctx, "Insert on")
    r.ImGui_SameLine(ctx, 0, gap)
    local t = draw.combo(ctx, "##target", { "Selected track", "Last touched track" }, o.target, cw)
    if t then o.target = t; changed = true end
    r.ImGui_SameLine(ctx, 0, gap)
    r.ImGui_Text(ctx, "at")
    r.ImGui_SameLine(ctx, 0, gap)
    local w = draw.combo(ctx, "##where", { "Edit cursor", "After the last chord" }, o.where, cw)
    if w then o.where = w; changed = true end
  else
    -- each on a line of its own, the whole width
    r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Insert on")
    local t = draw.combo(ctx, "##target", { "Selected track", "Last touched track" }, o.target, avail)
    if t then o.target = t; changed = true end
    r.ImGui_TextColored(ctx, Theme.colors.text_dim, "at")
    local w = draw.combo(ctx, "##where", { "Edit cursor", "After the last chord" }, o.where, avail)
    if w then o.where = w; changed = true end
  end
  -- the ticks one after another, onto a next line when the next one doesn't fit
  local row_x0 = r.ImGui_GetCursorPosX(ctx)
  local used = 0
  local spacing = UIScale.round(10)
  local function tick(label, key, tip)
    local w = r.ImGui_GetFrameHeight(ctx) + UIScale.round(4) + r.ImGui_CalcTextSize(ctx, label)
    if used > 0 and used + spacing + w <= avail then
      r.ImGui_SameLine(ctx, 0, spacing)
      used = used + spacing + w
    else
      r.ImGui_SetCursorPosX(ctx, row_x0)
      used = w
    end
    check(label, key)
    if tip then UI.tooltip_when(state.app, r.ImGui_IsItemHovered(ctx), tip) end
  end
  tick("Cursor follows", "follow")
  tick("Audition", "audition", "Hear a chord as you pick it. The target track is armed for a moment to sound it, and put back after.")
  tick("Markers", "markers", "A project marker with the chord's name at each inserted chord.")
  if changed then store.save_options() end
end

function slots_ui.header(ctx, wide)
  local avail = select(1, r.ImGui_GetContentRegionAvail(ctx))
  local gap = UIScale.round(6)
  local label_w = r.ImGui_CalcTextSize(ctx, "Key") + gap
  local opt_label = state.gear and "Options ^" or "Options v"
  local opt_w = wide and 0 or (UIScale.text_button_w(ctx, opt_label, UIScale.round(70)) + gap)
  local km_w = wide and math.min(UIScale.round(220), avail - label_w) or (avail - label_w - opt_w)
  r.ImGui_Text(ctx, "Key")
  r.ImGui_SameLine(ctx, 0, gap)
  local key, mode, changed = draw.key_mode(ctx, state.key, state.mode, "slots", { "Major", "Minor" }, km_w)
  if changed then state.key, state.mode = key, mode; store.save_project() end
  if wide then
    slots_ui.options(ctx, true)
  else
    r.ImGui_SameLine(ctx, 0, gap)
    if r.ImGui_Button(ctx, opt_label .. "##chords_gear", opt_w - gap, 0) then state.gear = not state.gear end
    if state.gear then slots_ui.options(ctx, false) end
  end
end

function slots_ui.editor(ctx, wide)
  local s = state.slots[state.sel]
  if not s then return end
  local avail = select(1, r.ImGui_GetContentRegionAvail(ctx))
  local col_w = wide and math.floor(avail * 0.52) or avail
  local changed = false
  r.ImGui_BeginGroup(ctx)
  r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Root")
  local scale, roots = SCALES[state.mode], {}
  for i = 1, 12 do roots[i] = NOTES[i] end
  local pick = draw.choices(ctx, "chord_root", roots, s.root + 1, col_w, wide and nil or 6)
  if pick then s.root = pick - 1; changed = true end
  local in_key = {}
  for _, step in ipairs(scale) do in_key[#in_key + 1] = NOTES[(step + state.key) % 12 + 1] end
  r.ImGui_TextColored(ctx, Theme.colors.text_dim, "In " .. NOTES[state.key + 1] .. " " .. state.mode:lower() .. ": " .. table.concat(in_key, " "))
  r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Type")
  local labels, current = {}, 1
  for i, t in ipairs(TYPE_ORDER) do
    labels[i] = t == "" and "maj" or t
    if t == s.type then current = i end
  end
  pick = draw.choices(ctx, "chord_type", labels, current, col_w, wide and nil or 4)
  if pick then
    s.type = TYPE_ORDER[pick]
    s.inv = math.min(s.inv or 0, #(TYPES[s.type] or TYPES[""]) - 1)
    changed = true
  end
  r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Voicing")
  local vi = 1
  for i, v in ipairs(VOICES) do if v == s.voice then vi = i end end
  pick = draw.choices(ctx, "chord_voice", VOICES, vi, col_w)
  if pick then s.voice = VOICES[pick]; changed = true end
  r.ImGui_EndGroup(ctx)
  if wide then r.ImGui_SameLine(ctx, 0, UIScale.round(14)) end
  r.ImGui_BeginGroup(ctx)
  local right_w = wide and (avail - col_w - UIScale.round(14)) or avail
  local roman = music.roman(s)
  r.ImGui_Text(ctx, "Slot " .. state.sel .. ": " .. music.name(s))
  if roman ~= "" then r.ImGui_SameLine(ctx); r.ImGui_TextColored(ctx, Theme.colors.accent, roman) end
  draw.keys(ctx, music.notes(s), math.min(right_w, UIScale.round(320)), UIScale.round(48))
  r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Inversion")
  local tones = #(TYPES[s.type] or TYPES[""])
  local invs = {}
  for i = 1, math.min(#INVERSIONS, tones) do invs[i] = INVERSIONS[i] end
  pick = draw.choices(ctx, "chord_inv", invs, (s.inv or 0) + 1, right_w)
  if pick then s.inv = pick - 1; changed = true end
  r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Octave")
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "-##chord_oct_down") and s.oct > 1 then s.oct = s.oct - 1; changed = true end
  r.ImGui_SameLine(ctx)
  r.ImGui_Text(ctx, "C" .. s.oct)
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "+##chord_oct_up") and s.oct < 7 then s.oct = s.oct + 1; changed = true end
  r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Length")
  local li = 3
  for i, l in ipairs(LENGTHS) do if l == s.len then li = i end end
  pick = draw.choices(ctx, "chord_len", LENGTHS, li, right_w)
  if pick then s.len = LENGTHS[pick]; changed = true end
  r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Feel (all slots)")
  local o, fc = state.opt, false
  local half = math.floor((right_w - UIScale.round(8)) / 3)
  r.ImGui_SetNextItemWidth(ctx, half)
  local c1, v1 = r.ImGui_SliderInt(ctx, "##chord_vel", o.velocity, 1, 127, "Vel %d")
  if c1 then o.velocity = v1; fc = true end
  r.ImGui_SameLine(ctx, 0, UIScale.round(4))
  r.ImGui_SetNextItemWidth(ctx, half)
  local c2, v2 = r.ImGui_SliderInt(ctx, "##chord_strum", o.strum, 0, 80, "Strum %d ms")
  if c2 then o.strum = v2; fc = true end
  r.ImGui_SameLine(ctx, 0, UIScale.round(4))
  r.ImGui_SetNextItemWidth(ctx, half)
  local c3, v3 = r.ImGui_SliderInt(ctx, "##chord_hum", o.humanize, 0, 40, "Human %d%%")
  if c3 then o.humanize = v3; fc = true end
  if fc then store.save_options() end
  r.ImGui_EndGroup(ctx)
  if changed then
    store.save_project()
    act.audition(music.notes(s))
  end
end

function slots_ui.cards(ctx)
  local avail = select(1, r.ImGui_GetContentRegionAvail(ctx))
  local gap = UIScale.round(6)
  local cw = math.floor((avail - gap * (SLOT_COUNT - 1)) / SLOT_COUNT)
  local ch = UIScale.round(92)
  for i = 1, SLOT_COUNT do
    if i > 1 then r.ImGui_SameLine(ctx, 0, gap) end
    local s = state.slots[i]
    local x, y = r.ImGui_GetCursorScreenPos(ctx)
    local dl = r.ImGui_GetWindowDrawList(ctx)
    local clicked = r.ImGui_InvisibleButton(ctx, "##chord_card" .. i, cw, ch)
    local hovered = r.ImGui_IsItemHovered(ctx)
    if state.drag_from then clicked = false end
    local double = hovered and r.ImGui_IsMouseDoubleClicked(ctx, 0)
    local bg = hovered and Theme.colors.frame_hover or Theme.colors.frame_bg
    r.ImGui_DrawList_AddRectFilled(dl, x, y, x + cw, y + ch, bg, UIScale.round(5))
    if i == state.sel and s then r.ImGui_DrawList_AddRect(dl, x, y, x + cw, y + ch, Theme.colors.accent, UIScale.round(5), 0, 2) end
    r.ImGui_DrawList_AddText(dl, x + UIScale.round(5), y + UIScale.round(3), Theme.colors.text_dim, tostring(i))
    if s then
      local name = music.name(s)
      local tw = r.ImGui_CalcTextSize(ctx, name)
      r.ImGui_DrawList_AddText(dl, x + (cw - tw) / 2, y + UIScale.round(14), Theme.colors.text, name)
      local roman = music.roman(s)
      local rw = r.ImGui_CalcTextSize(ctx, roman)
      r.ImGui_DrawList_AddText(dl, x + (cw - rw) / 2, y + UIScale.round(30), Theme.colors.accent, roman)
      local keep = { r.ImGui_GetCursorScreenPos(ctx) }
      r.ImGui_SetCursorScreenPos(ctx, x + UIScale.round(5), y + UIScale.round(50))
      draw.keys(ctx, music.notes(s), cw - UIScale.round(10), UIScale.round(20))
      r.ImGui_SetCursorScreenPos(ctx, keep[1], keep[2])
      r.ImGui_DrawList_AddText(dl, x + UIScale.round(5), y + ch - UIScale.round(16), Theme.colors.text_dim, (INVERSIONS[(s.inv or 0) + 1] or ""):lower())
      local lw = r.ImGui_CalcTextSize(ctx, s.len)
      r.ImGui_DrawList_AddText(dl, x + cw - lw - UIScale.round(5), y + ch - UIScale.round(16), Theme.colors.text_dim, s.len)
    else
      local tw = r.ImGui_CalcTextSize(ctx, "+")
      r.ImGui_DrawList_AddText(dl, x + (cw - tw) / 2, y + ch / 2 - UIScale.round(7), Theme.colors.text_dim, "+")
    end
    slots_ui.drag_item(ctx, i, x, y, cw, ch)
    UI.tooltip_when(state.app, hovered and not state.drag_from, s and "Click: edit. Double-click: insert. Drag: move. Key " .. i .. " inserts it too." or "Empty slot: click to fill it")
    if clicked then
      if not s then state.slots[i] = music.new_slot(); store.save_project() end
      state.sel = i
      if state.slots[i] then act.audition(music.notes(state.slots[i])) end
    end
    if double and s then act.insert_slots({ i }) end
  end
end

function slots_ui.rows(ctx)
  local avail = select(1, r.ImGui_GetContentRegionAvail(ctx))
  local row_h = r.ImGui_GetFrameHeight(ctx)
  for i = 1, SLOT_COUNT do
    local s = state.slots[i]
    local open = s and state.open[i]
    local x, y = r.ImGui_GetCursorScreenPos(ctx)
    local dl = r.ImGui_GetWindowDrawList(ctx)
    local insert_w = UIScale.round(26)
    local row_w = avail - insert_w - UIScale.round(4)
    local clicked = r.ImGui_InvisibleButton(ctx, "##chord_row" .. i, row_w, row_h)
    local hovered = r.ImGui_IsItemHovered(ctx)
    if state.drag_from then clicked = false end
    slots_ui.drag_item(ctx, i, x, y, row_w, row_h)
    r.ImGui_DrawList_AddRectFilled(dl, x, y, x + avail, y + row_h, hovered and Theme.colors.frame_hover or Theme.colors.frame_bg, UIScale.round(4))
    local ty = y + (row_h - r.ImGui_GetTextLineHeight(ctx)) / 2
    r.ImGui_DrawList_AddText(dl, x + UIScale.round(6), ty, Theme.colors.text_dim, (open and "v " or "> ") .. i)
    if s then
      r.ImGui_DrawList_AddText(dl, x + UIScale.round(34), ty, Theme.colors.text, music.name(s))
      r.ImGui_DrawList_AddText(dl, x + UIScale.round(110), ty, Theme.colors.accent, music.roman(s))
      local lw = r.ImGui_CalcTextSize(ctx, s.len)
      r.ImGui_DrawList_AddText(dl, x + avail - insert_w - lw - UIScale.round(10), ty, Theme.colors.text_dim, s.len)
    else
      r.ImGui_DrawList_AddText(dl, x + UIScale.round(34), ty, Theme.colors.text_dim, "+ empty slot")
    end
    if clicked then
      if s then
        state.open[i] = not state.open[i]
        if state.open[i] then act.audition(music.notes(s)) end
      else
        state.slots[i] = music.new_slot()
        state.sel, state.view = i, "edit"
        store.save_project()
      end
    end
    r.ImGui_SameLine(ctx, 0, UIScale.round(4))
    if s then
      if r.ImGui_Button(ctx, "Ins##chord_ins" .. i, insert_w, row_h) then act.insert_slots({ i }) end
      UI.tooltip_when(state.app, r.ImGui_IsItemHovered(ctx), "Insert " .. music.name(s))
    else
      r.ImGui_Dummy(ctx, insert_w, row_h)
    end
    if open then
      r.ImGui_Indent(ctx, UIScale.round(10))
      draw.keys(ctx, music.notes(s), avail - UIScale.round(20), UIScale.round(34))
      if r.ImGui_Button(ctx, "Edit##chord_edit" .. i) then state.sel, state.view = i, "edit" end
      r.ImGui_SameLine(ctx)
      act.play_button(ctx, "slot" .. i, music.notes(s), "chord_play" .. i)
      r.ImGui_SameLine(ctx)
      if r.ImGui_Button(ctx, "Clear##chord_clear" .. i) then
        state.slots[i], state.open[i] = false, nil
        store.save_project()
      end
      r.ImGui_Unindent(ctx, UIScale.round(10))
      r.ImGui_Dummy(ctx, 0, UIScale.round(2))
    end
  end
end

function slots_ui.actions(ctx, wide)
  local filled = {}
  for i = 1, SLOT_COUNT do if state.slots[i] then filled[#filled + 1] = i end end
  if r.ImGui_Button(ctx, "Insert all in order##chords_all") then act.insert_slots(filled) end
  UI.tooltip_when(state.app, r.ImGui_IsItemHovered(ctx), "Slots 1-8 one after another, in one MIDI item.")
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "Play all##chords_playall") then
    local list = {}
    for _, i in ipairs(filled) do list[#list + 1] = state.slots[i] end
    act.play_list(list)
  end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "Stop##chords_stop") then act.stop() end
  UI.tooltip_when(state.app, r.ImGui_IsItemHovered(ctx), "All notes and sounds off (Esc)")
  if wide and state.slots[state.sel] then
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Clear slot " .. state.sel .. "##chords_clear") then
      state.slots[state.sel] = false
      store.save_project()
    end
  end
  if wide then r.ImGui_SameLine(ctx, 0, UIScale.round(14)) end
  slots_ui.sets(ctx)
end

function slots_ui.draw(ctx, wide)
  slots_ui.header(ctx, wide)
  r.ImGui_Separator(ctx)
  if wide then
    slots_ui.cards(ctx)
    slots_ui.drag_end(ctx)
    r.ImGui_Dummy(ctx, 0, UIScale.round(4))
    if state.slots[state.sel] then slots_ui.editor(ctx, true) end
    r.ImGui_Dummy(ctx, 0, UIScale.round(4))
    slots_ui.actions(ctx, true)
  elseif state.view == "edit" and state.slots[state.sel] then
    if r.ImGui_Button(ctx, "< Slots##chords_back") then state.view = "list" end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Insert##chords_ins_sel") then act.insert_slots({ state.sel }) end
    slots_ui.editor(ctx, false)
  else
    slots_ui.rows(ctx)
    slots_ui.drag_end(ctx)
    r.ImGui_Dummy(ctx, 0, UIScale.round(4))
    slots_ui.actions(ctx, false)
  end
end

-- ------------------------------------------------------------------ inspiration tab

local insp_ui = {}

function insp_ui.roll()
  local p = state.insp
  local pats = PATTERNS[STYLES[p.style]]
  local degrees = {}
  local first = pats[math.random(#pats)]
  for _, d in ipairs(first) do degrees[#degrees + 1] = d end
  if p.count == 8 then for _, d in ipairs(pats[math.random(#pats)]) do degrees[#degrees + 1] = d end end
  if #p.prog > 0 then
    local names = {}
    for _, c in ipairs(p.prog) do names[#names + 1] = music.name(c) end
    table.insert(p.history, 1, { names = table.concat(names, "  "), prog = p.prog })
    while #p.history > 6 do table.remove(p.history) end
  end
  local prog = {}
  for i, d in ipairs(degrees) do
    prog[i] = (p.locked[i] and p.prog[i]) or music.on_degree(d, p.key, p.mode, p.colour, i)
  end
  p.prog = prog
end

function insp_ui.draw(ctx, wide)
  local p = state.insp
  local bar = select(1, r.ImGui_GetContentRegionAvail(ctx))
  local gap = UIScale.round(4)
  local label_w = r.ImGui_CalcTextSize(ctx, "Key") + UIScale.round(6)
  -- wide: key and mode take two fifths of the row, style, count and colour the rest;
  -- narrow: key and mode on one line, the three below it, each a third
  local km_w = wide and math.floor(bar * 0.4) - label_w or bar - label_w
  r.ImGui_Text(ctx, "Key")
  r.ImGui_SameLine(ctx, 0, UIScale.round(6))
  local key, mode, changed = draw.key_mode(ctx, p.key, p.mode, "insp", MODES, km_w)
  p.key, p.mode = key, mode
  local rest = wide and (bar - label_w - km_w - gap) or bar
  local third = math.floor((rest - gap * 2) / 3)
  if wide then r.ImGui_SameLine(ctx, 0, gap) end
  local st = draw.combo(ctx, "##style", STYLES, p.style, third)
  if st then p.style = st; changed = true end
  r.ImGui_SameLine(ctx, 0, gap)
  local ct = draw.combo(ctx, "##count", { "4 chords", "8 chords" }, p.count == 8 and 2 or 1, third)
  if ct then p.count = ct == 2 and 8 or 4; changed = true end
  r.ImGui_SameLine(ctx, 0, gap)
  local cl = draw.combo(ctx, "##colour", COLOURS, p.colour, third)
  if cl then p.colour = cl; changed = true end
  if changed or #p.prog == 0 then p.locked = {}; insp_ui.roll() end
  r.ImGui_Separator(ctx)

  local avail = select(1, r.ImGui_GetContentRegionAvail(ctx))
  if wide then
    local per_row = math.min(#p.prog, 4)
    local gap = UIScale.round(6)
    local cw = math.floor((avail - gap * (per_row - 1)) / per_row)
    for i, c in ipairs(p.prog) do
      if (i - 1) % per_row ~= 0 then r.ImGui_SameLine(ctx, 0, gap) end
      r.ImGui_BeginGroup(ctx)
      local x, y = r.ImGui_GetCursorScreenPos(ctx)
      local dl = r.ImGui_GetWindowDrawList(ctx)
      local ch = UIScale.round(104)
      r.ImGui_DrawList_AddRectFilled(dl, x, y, x + cw, y + ch, Theme.colors.frame_bg, UIScale.round(5))
      if p.locked[i] then r.ImGui_DrawList_AddRect(dl, x, y, x + cw, y + ch, Theme.colors.warning, UIScale.round(5), 0, 2) end
      local name, roman = music.name(c), music.roman(c, p.key, p.mode)
      local tw, rw = r.ImGui_CalcTextSize(ctx, name), r.ImGui_CalcTextSize(ctx, roman)
      r.ImGui_DrawList_AddText(dl, x + (cw - tw) / 2, y + UIScale.round(6), Theme.colors.text, name)
      r.ImGui_DrawList_AddText(dl, x + (cw - rw) / 2, y + UIScale.round(22), Theme.colors.accent, roman)
      r.ImGui_SetCursorScreenPos(ctx, x + UIScale.round(6), y + UIScale.round(40))
      draw.keys(ctx, music.notes(c), cw - UIScale.round(12), UIScale.round(24))
      r.ImGui_SetCursorScreenPos(ctx, x + UIScale.round(6), y + UIScale.round(72))
      insp_ui.card_tools(ctx, i, c)
      r.ImGui_SetCursorScreenPos(ctx, x, y + ch)
      r.ImGui_Dummy(ctx, cw, 0)
      r.ImGui_EndGroup(ctx)
    end
  else
    for i, c in ipairs(p.prog) do
      local name = music.name(c)
      r.ImGui_Text(ctx, name)
      r.ImGui_SameLine(ctx, UIScale.round(70))
      r.ImGui_TextColored(ctx, Theme.colors.accent, music.roman(c, p.key, p.mode))
      r.ImGui_SameLine(ctx, math.max(UIScale.round(130), avail - UIScale.round(150)))
      insp_ui.card_tools(ctx, i, c)
      draw.keys(ctx, music.notes(c), avail, UIScale.round(22))
      r.ImGui_Dummy(ctx, 0, UIScale.round(3))
    end
  end
  r.ImGui_Dummy(ctx, 0, UIScale.round(4))
  if r.ImGui_Button(ctx, "New idea##chords_roll") then insp_ui.roll() end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "Play##chords_insp_play") then act.play_list(p.prog) end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "Stop##chords_insp_stop") then act.stop() end
  UI.tooltip_when(state.app, r.ImGui_IsItemHovered(ctx), "All notes and sounds off (Esc)")
  if wide then r.ImGui_SameLine(ctx) end
  if r.ImGui_Button(ctx, "To the slots##chords_to_slots") then insp_ui.to_slots() end
  r.ImGui_SameLine(ctx, 0, UIScale.round(4))
  local fill = draw.combo(ctx, "##chords_fill", { "into empty slots", "over slot 1-" .. #p.prog }, state.opt.fill, UIScale.round(130))
  if fill then state.opt.fill = fill; store.save_options() end
  if wide then r.ImGui_SameLine(ctx) end
  if r.ImGui_Button(ctx, "Insert as MIDI##chords_insp_ins") then
    local ok, why = act.insert(p.prog)
    state.status = ok and "Inserted the progression." or why
  end
  if #p.history > 0 then
    r.ImGui_Dummy(ctx, 0, UIScale.round(4))
    r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Earlier ideas")
    for i, h in ipairs(p.history) do
      if r.ImGui_Selectable(ctx, h.names .. "##chords_hist" .. i) then
        p.prog, p.locked = h.prog, {}
        table.remove(p.history, i)
        break
      end
    end
  end
end

-- the idea into the slots: into the empty ones (the others stay), or over slots 1.. as long as
-- the idea is (the rest stay; only then the slots take the idea's key too)
function insp_ui.to_slots()
  local p = state.insp
  local function slot(c) return { root = c.root, type = c.type, inv = 0, voice = "Close", oct = 3, len = "1 bar" } end
  local first, placed = nil, 0
  if state.opt.fill == 2 then
    for i, c in ipairs(p.prog) do
      if i <= SLOT_COUNT then state.slots[i] = slot(c); placed = placed + 1 end
    end
    first = 1
    state.key = p.key
    state.mode = (p.mode == "Minor" or p.mode == "Dorian") and "Minor" or "Major"
  else
    local at = 1
    for _, c in ipairs(p.prog) do
      while at <= SLOT_COUNT and state.slots[at] do at = at + 1 end
      if at > SLOT_COUNT then break end
      state.slots[at] = slot(c)
      first = first or at
      placed = placed + 1
    end
  end
  local left = #p.prog - placed
  if placed == 0 then
    state.status = "No empty slots left: clear some, or choose \"over slot 1\"."
    return
  end
  state.sel, state.tab, state.view, state.open = first, "slots", "list", {}
  store.save_project()
  state.status = placed .. " chords in the slots" .. (left > 0 and (", " .. left .. " didn't fit") or "") .. "."
end

function insp_ui.card_tools(ctx, i, c)
  local p = state.insp
  local locked = p.locked[i]
  if locked then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), Theme.colors.warning) end
  if r.ImGui_Button(ctx, "Keep##chords_lock" .. i) then p.locked[i] = not locked end
  if locked then r.ImGui_PopStyleColor(ctx) end
  UI.tooltip_when(state.app, r.ImGui_IsItemHovered(ctx), "Keep this chord when you roll a new idea")
  r.ImGui_SameLine(ctx, 0, UIScale.round(3))
  if r.ImGui_Button(ctx, "Roll##chords_reroll" .. i) then
    p.prog[i] = music.on_degree(math.random(0, 5), p.key, p.mode, p.colour, i)
  end
  r.ImGui_SameLine(ctx, 0, UIScale.round(3))
  act.play_button(ctx, "insp" .. i, music.notes(c), "chords_cplay" .. i)
end

-- ------------------------------------------------------------------ module

function M.init(app)
  math.randomseed(math.floor(r.time_precise() * 1000) % 2147483647)
  store.load_options()
end

function M.draw(app)
  local ctx = app.ctx
  state.app = app
  local project = r.EnumProjects(-1)
  if project ~= state.project then store.load_project(project) end
  act.tick()

  draw.tab(ctx, "Slots", "slots")
  r.ImGui_SameLine(ctx)
  draw.tab(ctx, "Inspiration", "insp")
  r.ImGui_Separator(ctx)

  local avail_w, avail_h = r.ImGui_GetContentRegionAvail(ctx)
  local wide = (avail_w or 0) >= UIScale.round(WIDE_FROM)
  local content_h = math.max(UIScale.round(60), (avail_h or 240) - UI.info_line_height(ctx))
  if r.ImGui_BeginChild(ctx, "##chords_content", 0, content_h, 0) then
    -- (an error in here must still close the child: left open, Workbench's own ID stack breaks)
    local ok, err = pcall(function()
      if state.tab == "insp" then insp_ui.draw(ctx, wide) else slots_ui.draw(ctx, wide) end
    end)
    if not ok then
      state.status = "Chords: " .. tostring(err)
      if state.app and state.app.record_module_error then state.app.record_module_error("chords.draw", err) end
    end
    -- keys 1-8 insert a slot while this module has the focus and nothing is being typed
    local focused = r.ImGui_IsWindowFocused(ctx, r.ImGui_FocusedFlags_RootAndChildWindows())
    if focused and r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_Escape(), false) then act.stop() end
    if state.tab == "slots" and focused and not r.ImGui_IsAnyItemActive(ctx) then
      for i = 1, SLOT_COUNT do
        local key = r["ImGui_Key_" .. i]
        if key and r.ImGui_IsKeyPressed(ctx, key(), false) and state.slots[i] then act.insert_slots({ i }) end
      end
    end
    r.ImGui_EndChild(ctx)
  end
  local count = 0
  for i = 1, SLOT_COUNT do if state.slots[i] then count = count + 1 end end
  local track = act.target_track()
  local tname = track and select(2, r.GetTrackName(track)) or "no track"
  UI.draw_info_line(ctx, state.status or (count .. " slots | " .. NOTES[state.key + 1] .. " " .. state.mode:lower() .. " | to " .. tname))
end

return M
