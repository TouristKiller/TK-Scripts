-- TK Theme Bit - Clip Edit: Bitwig's audio editor for REAPER, meant for the bottom docker.
-- It follows the selected audio item. As Bitwig's clip holds events, the editor's clip is
-- the run of items on that track that touch each other (Track: all of the track's items);
-- each item is an event, with its own header. The selected event carries the handles: its
-- fades, gain, take volume envelope and stretch markers.
--
-- Tools (the keys at the right): Pointer (click an event to select it, drag to move it),
-- Time selection, Draw (volume envelope points), Erase (points, stretch markers), Knife
-- (split an event), Stretch (add stretch markers; the dashed lines are the transients:
-- drag one to make it a marker). Right-click: markers on all transients, sensitivity.
-- Mouse: wheel scrolls, Ctrl+wheel zooms, Alt+wheel makes the waveform taller. The ruler
-- and the clip bar make a time selection; the overview at the bottom scrolls.
-- Fades: drag the white squares, right-click one for the next shape. Gain: drag the dB box
-- in the event's header (double-click: 0 dB). Points and markers: drag; Alt- or right-click
-- deletes. Double-click the event's header for a stretch marker.
-- Shift: no snap / fine. Space plays, S splits, Ctrl+Z undoes while the panel has focus.
-- With the TK Bit inspector open, the value column folds away: the inspector has them.
-- Run the action again to close the panel.

local r = reaper
if not r.ImGui_CreateContext then
  r.ShowMessageBox("Clip Edit needs ReaImGui (install it through ReaPack).", "TK Theme Bit", 0)
  return
end
do
  local _, _, version = r.ImGui_GetVersion()
  local major, minor = tostring(version):match("^(%d+)%.(%d+)")
  if not major or (tonumber(major) == 0 and tonumber(minor) < 10) then
    r.ShowMessageBox("Clip Edit needs ReaImGui 0.10 or newer.", "TK Theme Bit", 0)
    return
  end
end

if r.set_action_options then r.set_action_options(1 | 4) end
local _, _, section_id, cmd_id = r.get_action_context()

local ctx = r.ImGui_CreateContext("TK Bit Clip Edit")
local font = r.ImGui_CreateFont("Inter")
r.ImGui_Attach(ctx, font)
local font_bold = r.ImGui_CreateFont("Inter", r.ImGui_FontFlags_Bold and r.ImGui_FontFlags_Bold() or 0)
r.ImGui_Attach(ctx, font_bold)

-- the Bit inspector's colours (measured from Bitwig), plus the editor's own few
local C = {
  bg = 0x121212FF, empty = 0x0A0A0AFF, field = 0x040404FF, line = 0x242424FF, accent = 0xFF6000FF,
  fill = 0x3E1A04FF, text = 0xE6E6E6FF, dim = 0x8A8A8AFF, label = 0xB9B4B4FF, value = 0xF75D07FF,
  headbar = 0x242424FF, headtext = 0xCFCFCFFF, seg = 0x363636FF, seg_hi = 0x444444FF,
  key_top = 0x363636FF, key_bot = 0x292929FF, key_edge = 0x0A0A0AFF, on_top = 0xFF6000FF,
  on_bot = 0xF85D00FF,
  canvas = 0x0B0B0BFF, active = 0x151515FF, ruler = 0x1A1A1AFF, bar = 0x262626FF, beat = 0x1A1A1AFF,
  sub = 0x131313FF, wave = 0xB4B4B4FF, wave_dim = 0x5A5A5AFF, mid = 0x3A3A3AFF, over = 0x4A4A4AFF,
  marker = 0xE8C34AFF, sel = 0xFF60001E, handle = 0xE6E6E6FF,
  icon = 0x7A7A7AFF, icon_hi = 0xC8C8C8FF, hover = 0x262626FF, tabbar = 0x1B1B1BFF, tab_on = 0x262626FF,
  split = 0x000000FF, env = 0xF2A33AFF, env_dim = 0xA7752EFF, env_fill = 0xF2A33A33, env_fill_dim = 0xA7752E1E,   -- Bitwig's amber
}
local ROW_H, RULER_H, OVER_H, BAR_H, HEAD_H, TOOLS_W = 18, 22, 22, 14, 13, 30
local EXT = "TK Bit Clip Edit"
local CMD = { remove = 40006, duplicate = 41295, split_sel = 40061, split_cur = 40757, trim = 40508, reverse = 41051, normalize = 40108,
  play = 40044, undo = 40029, redo = 40030, unselect = 40289, vol_env = 40693 }

-- what the panel shows and how: kept between runs
local function ext(k, def)
  local v = r.GetExtState(EXT, k)
  if v == "" then return def end
  return v
end
local S = {
  tool = ext("tool", "pointer"),
  scope = ext("scope", "clip"),           -- "clip" (the touching items) or "track" (all)
  snap = ext("snap", "1") ~= "0",
  show_env = ext("show_env", "1") ~= "0",
  show_sm = ext("show_sm", "1") ~= "0",
  sens = ext("sens", "mid"),                    -- transient sensitivity: low, mid, high
  qstr = tonumber(ext("qstr", "100")) or 100,   -- quantize strength, %
  lane = ext("lane", "1") ~= "0",           -- the envelope lanes under the clip
  lane_frac = tonumber(ext("lane_frac", "0.3")) or 0.3,
  lanes = ext("lanes", "vol"),             -- which lanes: "vol,pan,pitch"
  pfollow = ext("pfollow", "1") ~= "0",    -- the view pages along with the play cursor
  follow = true, vzoom = 1,
  item = nil, take = nil,  -- the selected event
  group = {},              -- the clip's events
  vs = 0, ve = 1,          -- the view, in project time
  dock_to = nil, close = false, edit = {},
}
local function save()
  r.SetExtState(EXT, "tool", S.tool, true)
  r.SetExtState(EXT, "scope", S.scope, true)
  r.SetExtState(EXT, "snap", S.snap and "1" or "0", true)
  r.SetExtState(EXT, "show_env", S.show_env and "1" or "0", true)
  r.SetExtState(EXT, "show_sm", S.show_sm and "1" or "0", true)
  r.SetExtState(EXT, "sens", S.sens, true)
  r.SetExtState(EXT, "qstr", tostring(S.qstr), true)
  r.SetExtState(EXT, "lane", S.lane and "1" or "0", true)
  r.SetExtState(EXT, "lane_frac", string.format("%.3f", S.lane_frac), true)
  r.SetExtState(EXT, "lanes", S.lanes, true)
  r.SetExtState(EXT, "pfollow", S.pfollow and "1" or "0", true)
end

---------------------------------------------------------------- helpers
local H = { tick = 0 }    -- tick: counts our own drags (see P.state)
function H.undo(desc) r.Undo_OnStateChangeEx2(0, "Clip Edit: " .. desc, -1, -1) end
function H.mods()
  local m = r.ImGui_GetKeyMods(ctx)
  return (m & r.ImGui_Mod_Shift()) ~= 0, (m & r.ImGui_Mod_Ctrl()) ~= 0, (m & r.ImGui_Mod_Alt()) ~= 0
end
function H.amp_db(a)
  if a < 0.0000001 then return "-inf dB" end
  return string.format("%+.1f dB", 20 * math.log(a, 10))
end
function H.clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end
function H.num(s) return tonumber((s or ""):match("[%-%+]?%d*%.?%d+")) end
function H.native_rgb(c)
  if not c or c & 0x1000000 == 0 then return nil end
  local R, G, B = r.ColorFromNative(c & 0xFFFFFF)
  return (R << 16) | (G << 8) | B
end
-- rgb mixed toward (k > 0) white or (k < 0) black, as RGBA
function H.shade(rgb, k, a)
  local out = 0
  for s = 16, 0, -8 do
    local v = (rgb >> s) & 255
    v = k >= 0 and v + (255 - v) * k or v * (1 + k)
    out = out | (math.floor(H.clamp(v, 0, 255)) << s)
  end
  return (out << 8) | (a or 255)
end
-- the fade shapes REAPER offers (0..6), close enough to see which one is set
H.FADE = {
  function(x) return x end, function(x) return 1 - (1 - x) ^ 2 end, function(x) return x * x end,
  function(x) return 1 - (1 - x) ^ 4 end, function(x) return x ^ 4 end,
  function(x) return x * x * (3 - 2 * x) end,
  function(x) x = x * x * (3 - 2 * x); return x * x * (3 - 2 * x) end,
}
H.FADE_NAMES = { "Linear", "Fast start", "Fast end", "Fast start (steep)", "Fast end (steep)",
  "Slow start and end", "Slow start and end (steep)" }
function H.fade_gain(shape, x) return (H.FADE[shape + 1] or H.FADE[1])(H.clamp(x, 0, 1)) end

-- the take volume envelope's scale as REAPER's faders: -inf .. +6 dB over 0 .. 1
local S6 = r.DB2SLIDER(20 * math.log(2, 10))
function H.amp_to_y(a)
  if a < 0.0000001 then return 0 end
  return H.clamp(r.DB2SLIDER(20 * math.log(a, 10)) / S6, 0, 1)
end
function H.y_to_amp(t)
  if t <= 0 then return 0 end
  return math.min(2, 10 ^ (r.SLIDER2DB(t * S6) / 20))
end

-- one item selected in REAPER: the event the editor works on
-- unselect every item through the API: the "Unselect all items" action leaves an undo step
function H.unselect_all()
  for i = r.CountSelectedMediaItems(0) - 1, 0, -1 do
    r.SetMediaItemSelected(r.GetSelectedMediaItem(0, i), false)
  end
end
function H.select(item)
  H.unselect_all()
  r.SetMediaItemSelected(item, true)
  r.UpdateArrange()
  S.item, S.take = item, r.GetActiveTake(item)
end
-- runs a REAPER action on the selected event: selects it alone first when it is not selected
-- REAPER actions on the event run at the end of the frame: split, trim and the like
-- can delete or replace the item, and this frame still draws with its take
function H.run(cmd) H.queued = cmd end
function H.run_queued()
  local cmd = H.queued
  H.queued = nil
  if not cmd or not S.item or not r.ValidatePtr2(0, S.item, "MediaItem*") then return end
  if not r.IsMediaItemSelected(S.item) then H.select(S.item) end
  r.Main_OnCommand(cmd, 0)
end

function H.time_sel()
  local a, b = r.GetSet_LoopTimeRange2(0, false, false, 0, 0, false)
  if b > a then return a, b end
end

-- the TK Bit inspector writes the time here every half second while it runs
function H.inspector_open()
  local t = tonumber(r.GetExtState("TK Theme Bit", "inspector_open"))
  return t ~= nil and r.time_precise() - t < 2
end

---------------------------------------------------------------- widgets (the inspector's)
local U = {}
function U.text_col(col, s)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), col)
  r.ImGui_Text(ctx, s)
  r.ImGui_PopStyleColor(ctx)
end

-- the header bar with the dock and close icons at its right end
function U.head(title)
  local dl = r.ImGui_GetWindowDrawList(ctx)
  local x, y = r.ImGui_GetCursorScreenPos(ctx)
  local w = r.ImGui_GetContentRegionAvail(ctx)
  r.ImGui_DrawList_AddRectFilled(dl, x - 6, y, x + w + 6, y + 20, C.headbar)
  r.ImGui_PushFont(ctx, font_bold, 11)
  local tw, th = r.ImGui_CalcTextSize(ctx, title)
  r.ImGui_DrawList_AddText(dl, x + math.max(0, (w - 40 - tw) / 2), y + (20 - th) / 2, C.headtext, title)
  r.ImGui_PopFont(ctx)
  local docked = r.ImGui_IsWindowDocked(ctx)
  r.ImGui_SetCursorScreenPos(ctx, x + w - 38, y + 2)
  if r.ImGui_InvisibleButton(ctx, "##dock", 16, 16) then S.dock_to = docked and 0 or -1 end
  local hov = r.ImGui_IsItemHovered(ctx)
  local ic = hov and C.text or C.dim
  r.ImGui_DrawList_AddRect(dl, x + w - 35, y + 5, x + w - 25, y + 14, ic, 1)
  if docked then r.ImGui_DrawList_AddRectFilled(dl, x + w - 35, y + 11, x + w - 25, y + 14, C.accent) end
  if hov then
    r.ImGui_SetTooltip(ctx, docked and "Float the editor"
      or "Dock the editor (in REAPER's first docker; set that docker to the bottom for Bitwig's place)")
  end
  r.ImGui_SetCursorScreenPos(ctx, x + w - 19, y + 2)
  if r.ImGui_InvisibleButton(ctx, "##close", 16, 16) then S.close = true end
  hov = r.ImGui_IsItemHovered(ctx)
  ic = hov and C.text or C.dim
  r.ImGui_DrawList_AddLine(dl, x + w - 15, y + 6, x + w - 8, y + 13, ic, 1.4)
  r.ImGui_DrawList_AddLine(dl, x + w - 8, y + 6, x + w - 15, y + 13, ic, 1.4)
  if hov then r.ImGui_SetTooltip(ctx, "Close the editor") end
  r.ImGui_SetCursorScreenPos(ctx, x, y)
  r.ImGui_Dummy(ctx, w, 22)
end

function U.sep()
  r.ImGui_Dummy(ctx, 0, 2)
  local dl = r.ImGui_GetWindowDrawList(ctx)
  local x, y = r.ImGui_GetCursorScreenPos(ctx)
  local w = r.ImGui_GetContentRegionAvail(ctx)
  r.ImGui_DrawList_AddRectFilled(dl, x - 10, y, x + w + 10, y + 2, C.line)
  r.ImGui_Dummy(ctx, 0, 4)
end

-- a row: the label right-aligned in the left column, then draw(width) in the right one
function U.row(text, draw)
  local cw = 70
  local x0 = r.ImGui_GetCursorPosX(ctx)
  r.ImGui_PushFont(ctx, font_bold, 12)
  local tw = r.ImGui_CalcTextSize(ctx, text)
  r.ImGui_SetCursorPosX(ctx, x0 + cw - 6 - tw)
  r.ImGui_AlignTextToFramePadding(ctx)
  U.text_col(C.label, text)
  r.ImGui_PopFont(ctx)
  r.ImGui_SameLine(ctx)
  r.ImGui_SetCursorPosX(ctx, x0 + cw)
  draw((r.ImGui_GetContentRegionAvail(ctx)))
end

-- a value box: black, the value in orange; drag up / right (Shift: fine), double-click to
-- type, right-click for the default. Returns the new t (0..1), moved, done.
function U.vbox(id, t, text, opts)
  local w = r.ImGui_GetContentRegionAvail(ctx)
  local x, y = r.ImGui_GetCursorScreenPos(ctx)
  local dl = r.ImGui_GetWindowDrawList(ctx)
  local new, moved, done = t, false, false
  local edit = S.edit
  if edit.id == id then
    r.ImGui_SetNextItemWidth(ctx, w)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), C.field)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), C.value)
    if edit.first then r.ImGui_SetKeyboardFocusHere(ctx) end
    local enter, s = r.ImGui_InputText(ctx, "##ed" .. id, edit.buf, r.ImGui_InputTextFlags_EnterReturnsTrue())
    edit.buf = s
    local left = not edit.first and not r.ImGui_IsItemActive(ctx)
    edit.first = false
    r.ImGui_PopStyleColor(ctx, 2)
    if enter or left then
      local v = opts.parse and opts.parse(s)
      if v then new, moved, done = H.clamp(v, 0, 1), true, true end
      S.edit = {}
    end
    return new, moved, done
  end
  r.ImGui_InvisibleButton(ctx, "##" .. id, w, ROW_H)
  if r.ImGui_IsItemActive(ctx) then
    local dx, dy = r.ImGui_GetMouseDelta(ctx)
    local d = dx - dy
    if d ~= 0 then
      local fine = H.mods()
      new = H.clamp(t + d / 200 * (fine and 0.1 or 1), 0, 1)
      moved = new ~= t
    end
  end
  if r.ImGui_IsItemHovered(ctx) and r.ImGui_IsMouseDoubleClicked(ctx, 0) and opts.parse then
    S.edit = { id = id, buf = (text:gsub("[^%d%.%-%+]", "")), first = true }
  end
  if r.ImGui_IsItemClicked(ctx, 1) and opts.default then new, moved, done = opts.default, true, true end
  if r.ImGui_IsItemDeactivated(ctx) then done = true end
  r.ImGui_DrawList_AddRectFilled(dl, x, y, x + w, y + ROW_H, C.field, 2)
  r.ImGui_DrawList_AddRectFilled(dl, x + 3, y + 4, x + 5, y + ROW_H - 4, C.accent)
  local tw, th = r.ImGui_CalcTextSize(ctx, text)
  r.ImGui_DrawList_AddText(dl, math.max(x + 8, x + w - 6 - tw), y + (ROW_H - th) / 2, C.value, text)
  if moved then H.tick = H.tick + 1 end
  return new, moved, done
end

-- a key as Bitwig draws them: grey, orange when on. text may be an icon function.
function U.key(id, text, on, w, h, tip)
  local x, y = r.ImGui_GetCursorScreenPos(ctx)
  local hit = r.ImGui_InvisibleButton(ctx, "##k" .. id, w, h)
  local hov, act = r.ImGui_IsItemHovered(ctx), r.ImGui_IsItemActive(ctx)
  local dl = r.ImGui_GetWindowDrawList(ctx)
  local top, bot = C.key_top, C.key_bot
  if on then top, bot = C.on_top, C.on_bot end
  if hov and not on then top, bot = C.seg_hi, 0x333333FF end
  if act then top, bot = bot, top end
  r.ImGui_DrawList_AddRectFilled(dl, x, y, x + w, y + h, C.key_edge, 3)
  r.ImGui_DrawList_AddRectFilledMultiColor(dl, x + 1, y + 1, x + w - 1, y + h - 1, top, top, bot, bot)
  local ink = on and 0x141414FF or C.text
  if type(text) == "function" then
    text(dl, x + w / 2, y + h / 2, ink)
  else
    local tw, th = r.ImGui_CalcTextSize(ctx, text)
    r.ImGui_DrawList_AddText(dl, x + (w - tw) / 2, y + (h - th) / 2, ink, text)
  end
  if hov and tip then r.ImGui_SetTooltip(ctx, tip) end
  return hit
end

-- a value box that opens a list (as the inspector's): fill() draws the choices
function U.combo(id, text, w, fill)
  local x, y = r.ImGui_GetCursorScreenPos(ctx)
  local dl = r.ImGui_GetWindowDrawList(ctx)
  if r.ImGui_InvisibleButton(ctx, "##cb" .. id, w, ROW_H) then r.ImGui_OpenPopup(ctx, "##cbp" .. id) end
  r.ImGui_DrawList_AddRectFilled(dl, x, y, x + w, y + ROW_H, C.field, 2)
  r.ImGui_DrawList_PushClipRect(dl, x, y, x + w - 14, y + ROW_H, true)
  local _, th = r.ImGui_CalcTextSize(ctx, text)
  r.ImGui_DrawList_AddText(dl, x + 6, y + (ROW_H - th) / 2, C.value, text)
  r.ImGui_DrawList_PopClipRect(dl)
  local ax, ay = x + w - 9, y + ROW_H / 2
  r.ImGui_DrawList_AddTriangleFilled(dl, ax - 3, ay - 2, ax + 3, ay - 2, ax, ay + 2, C.dim)
  if r.ImGui_BeginPopup(ctx, "##cbp" .. id) then
    fill()
    r.ImGui_EndPopup(ctx)
  end
end

-- REAPER's pitch-shift / stretch algorithms and their variants (asked once)
function H.shifters()
  if not H.shift_list then
    H.shift_list, H.sub_list = {}, {}
    for m = 0, 63 do
      local ok, name = r.EnumPitchShiftModes(m)
      if not ok then break end
      if name and name ~= "" then H.shift_list[#H.shift_list + 1] = { m, name } end
    end
  end
  return H.shift_list
end
function H.submodes(m)
  if not H.sub_list[m] then
    local out = {}
    for sm = 0, 511 do
      local name = r.EnumPitchShiftSubModes(m, sm)
      if not name or name == "" then break end
      out[#out + 1] = name
    end
    H.sub_list[m] = out
  end
  return H.sub_list[m]
end
-- set the selected events' (else this one's) stretch mode
function H.set_pitchmode(v)
  local n = r.CountSelectedMediaItems(0)
  if n == 0 then r.SetMediaItemTakeInfo_Value(S.take, "I_PITCHMODE", v) end
  for i = 0, n - 1 do
    local tk = r.GetActiveTake(r.GetSelectedMediaItem(0, i))
    if tk and not r.TakeIsMIDI(tk) then r.SetMediaItemTakeInfo_Value(tk, "I_PITCHMODE", v) end
  end
  H.undo("stretch mode")
end

-- Bitwig's tool keys: only the icon, grey; orange when on, a soft square under the mouse
function U.icon(id, icon, on, w, h, tip)
  local x, y = r.ImGui_GetCursorScreenPos(ctx)
  local hit = r.ImGui_InvisibleButton(ctx, "##i" .. id, w, h)
  local hov = r.ImGui_IsItemHovered(ctx)
  local dl = r.ImGui_GetWindowDrawList(ctx)
  if hov then r.ImGui_DrawList_AddRectFilled(dl, x, y, x + w, y + h, C.hover, 3) end
  icon(dl, x + w / 2, y + h / 2, on and C.accent or (hov and C.icon_hi or C.icon))
  if hov and tip then r.ImGui_SetTooltip(ctx, tip) end
  return hit
end

-- Bitwig's tabs: a dark bar, the open tab a shade lighter with orange text
function U.tabs(id, list, cur, w, h)
  local x, y = r.ImGui_GetCursorScreenPos(ctx)
  local dl = r.ImGui_GetWindowDrawList(ctx)
  r.ImGui_DrawList_AddRectFilled(dl, x, y, x + w, y + h, C.tabbar)
  local each, pick = w / #list, nil
  for i, t in ipairs(list) do
    local tx = x + (i - 1) * each
    r.ImGui_SetCursorScreenPos(ctx, tx, y)
    if r.ImGui_InvisibleButton(ctx, "##tab" .. id .. i, each, h) then pick = t[1] end
    local hov = r.ImGui_IsItemHovered(ctx)
    if t[1] == cur then r.ImGui_DrawList_AddRectFilled(dl, tx, y, tx + each, y + h, C.tab_on) end
    local tw, th = r.ImGui_CalcTextSize(ctx, t[2])
    local col = t[1] == cur and C.accent or (hov and C.icon_hi or C.dim)
    r.ImGui_DrawList_AddText(dl, tx + (each - tw) / 2, y + (h - th) / 2, col, t[2])
    if hov and t[3] then r.ImGui_SetTooltip(ctx, t[3]) end
  end
  r.ImGui_DrawList_AddLine(dl, x, y + h, x + w, y + h, C.empty)
  r.ImGui_SetCursorScreenPos(ctx, x, y + h + 1)
  return pick
end

-- the flat icons of the tool column
local ICON = {}
function ICON.pointer(dl, cx, cy, col)
  r.ImGui_DrawList_AddTriangleFilled(dl, cx - 4, cy - 6, cx - 4, cy + 5, cx + 4, cy + 1, col)
  r.ImGui_DrawList_AddLine(dl, cx, cy + 1, cx + 2.5, cy + 6, col, 2)
end
function ICON.time(dl, cx, cy, col)
  r.ImGui_DrawList_AddLine(dl, cx, cy - 6, cx, cy + 6, col, 2)
  r.ImGui_DrawList_AddLine(dl, cx - 3, cy - 6, cx + 3, cy - 6, col, 1)
  r.ImGui_DrawList_AddLine(dl, cx - 3, cy + 6, cx + 3, cy + 6, col, 1)
end
function ICON.draw(dl, cx, cy, col)
  r.ImGui_DrawList_AddLine(dl, cx - 4, cy + 4, cx + 4, cy - 4, col, 2.5)
  r.ImGui_DrawList_AddTriangleFilled(dl, cx - 6, cy + 6, cx - 5, cy + 2, cx - 2, cy + 5, col)
end
function ICON.erase(dl, cx, cy, col)
  r.ImGui_DrawList_AddQuad(dl, cx - 6, cy + 2, cx, cy - 5, cx + 6, cy + 1, cx, cy + 7, col, 1.5)
  r.ImGui_DrawList_AddLine(dl, cx - 3, cy - 1, cx + 3, cy + 4, col, 1.5)
end
function ICON.knife(dl, cx, cy, col)
  r.ImGui_DrawList_AddLine(dl, cx - 5, cy + 6, cx + 5, cy - 6, col, 2)
  r.ImGui_DrawList_AddLine(dl, cx + 1, cy - 2, cx + 5, cy - 6, col, 4)
end
function ICON.stretch(dl, cx, cy, col)
  r.ImGui_DrawList_AddLine(dl, cx, cy - 6, cx, cy + 6, col, 1.5)
  r.ImGui_DrawList_AddTriangleFilled(dl, cx - 7, cy, cx - 3, cy - 3.5, cx - 3, cy + 3.5, col)
  r.ImGui_DrawList_AddTriangleFilled(dl, cx + 7, cy, cx + 3, cy - 3.5, cx + 3, cy + 3.5, col)
end
function ICON.env(dl, cx, cy, col)
  r.ImGui_DrawList_AddLine(dl, cx - 7, cy + 4, cx - 2, cy - 3, col, 2)
  r.ImGui_DrawList_AddLine(dl, cx - 2, cy - 3, cx + 2, cy + 1, col, 2)
  r.ImGui_DrawList_AddLine(dl, cx + 2, cy + 1, cx + 7, cy - 5, col, 2)
end
function ICON.lane(dl, cx, cy, col)
  r.ImGui_DrawList_AddRect(dl, cx - 7, cy - 6, cx + 7, cy, col)
  r.ImGui_DrawList_AddLine(dl, cx - 7, cy + 5, cx - 2, cy + 2, col, 1.5)
  r.ImGui_DrawList_AddLine(dl, cx - 2, cy + 2, cx + 7, cy + 4, col, 1.5)
end
function ICON.markers(dl, cx, cy, col)
  r.ImGui_DrawList_AddTriangleFilled(dl, cx - 5, cy - 5, cx + 5, cy - 5, cx, cy + 2, col)
  r.ImGui_DrawList_AddLine(dl, cx, cy, cx, cy + 6, col, 1.5)
end
function ICON.snap(dl, cx, cy, col)
  r.ImGui_DrawList_PathArcTo(dl, cx, cy - 1, 5, 0, math.pi)
  r.ImGui_DrawList_PathStroke(dl, col, 0, 3)
  r.ImGui_DrawList_AddLine(dl, cx - 5, cy - 6, cx - 5, cy - 1, col, 3)
  r.ImGui_DrawList_AddLine(dl, cx + 5, cy - 6, cx + 5, cy - 1, col, 3)
end
function ICON.fit(dl, cx, cy, col)
  r.ImGui_DrawList_AddLine(dl, cx - 7, cy, cx + 7, cy, col, 1)
  r.ImGui_DrawList_AddLine(dl, cx - 7, cy - 5, cx - 7, cy + 5, col, 2)
  r.ImGui_DrawList_AddLine(dl, cx + 7, cy - 5, cx + 7, cy + 5, col, 2)
end
function ICON.follow(dl, cx, cy, col)
  r.ImGui_DrawList_AddCircle(dl, cx, cy, 5, col, 0, 2)
  r.ImGui_DrawList_AddCircleFilled(dl, cx, cy, 2, col)
end

function ICON.playfollow(dl, cx, cy, col)
  r.ImGui_DrawList_AddTriangleFilled(dl, cx - 6, cy - 6, cx, cy - 6, cx - 3, cy - 2, col)
  r.ImGui_DrawList_AddLine(dl, cx - 3, cy - 2, cx - 3, cy + 6, col, 1.5)
  r.ImGui_DrawList_AddLine(dl, cx, cy + 2, cx + 6, cy + 2, col, 1.5)
  r.ImGui_DrawList_AddTriangleFilled(dl, cx + 7, cy + 2, cx + 4, cy - 1, cx + 4, cy + 5, col)
end

---------------------------------------------------------------- the clip and its events
local K = {}   -- the selected event's values, read once per frame

-- one event (an item): what drawing it needs
function K.info(item)
  local take = r.GetActiveTake(item)
  if not take or r.TakeIsMIDI(take) then return nil end
  local e = { item = item, take = take }
  e.pos = r.GetMediaItemInfo_Value(item, "D_POSITION")
  e.len = r.GetMediaItemInfo_Value(item, "D_LENGTH")
  e.rate = r.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE")
  e.vol = r.GetMediaItemTakeInfo_Value(take, "D_VOL")
  e.mute = r.GetMediaItemInfo_Value(item, "B_MUTE") ~= 0
  e.fin = r.GetMediaItemInfo_Value(item, "D_FADEINLEN_AUTO")
  if e.fin <= 0 then e.fin = r.GetMediaItemInfo_Value(item, "D_FADEINLEN") end
  e.fout = r.GetMediaItemInfo_Value(item, "D_FADEOUTLEN_AUTO")
  if e.fout <= 0 then e.fout = r.GetMediaItemInfo_Value(item, "D_FADEOUTLEN") end
  e.fin_shape = math.floor(r.GetMediaItemInfo_Value(item, "C_FADEINSHAPE"))
  e.fout_shape = math.floor(r.GetMediaItemInfo_Value(item, "C_FADEOUTSHAPE"))
  local own = H.native_rgb(math.floor(r.GetMediaItemInfo_Value(item, "I_CUSTOMCOLOR")))
  e.rgb = own or H.native_rgb(r.GetTrackColor(r.GetMediaItem_Track(item))) or 0x8A8A8A
  e.name = select(2, r.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false))
  e.src = r.GetMediaItemTake_Source(take)
  e.nch = 1
  if e.src then
    e.nch = math.min(2, math.max(1, r.GetMediaSourceNumChannels(e.src)))
    if r.GetMediaItemTakeInfo_Value(take, "I_CHANMODE") >= 2 then e.nch = 1 end
  end
  return e
end

-- the selected event, copied into K (K.pos, K.len, ... as K.info gives them)
function K.read()
  local e = K.info(S.item)
  K.e = e
  for k, v in pairs(e) do K[k] = v end
  S.take = e.take
  K.env = r.GetTakeEnvelopeByName(S.take, "Volume")
end
-- take time (envelopes, stretch markers) <-> project time
function K.to_take(t) return (t - K.pos) * K.rate end
function K.from_take(tt) return K.pos + tt / K.rate end

-- the clip around the selected event: the touching items on its track (or all of them)
function K.group()
  local tr = r.GetMediaItem_Track(S.item)
  local all = {}
  for i = 0, r.CountTrackMediaItems(tr) - 1 do
    local e = K.info(r.GetTrackMediaItem(tr, i))
    if e then all[#all + 1] = e end
  end
  local at
  for i, e in ipairs(all) do if e.item == S.item then at = i end end
  if not at then return {} end
  if S.scope == "track" then return all end
  local first, last = at, at
  local stop = all[at].pos
  while first > 1 do
    local p = all[first - 1]
    if p.pos + p.len < stop - 0.0005 then break end
    first = first - 1
    stop = math.min(stop, p.pos)
  end
  local reach = all[at].pos + all[at].len
  while last < #all do
    local n = all[last + 1]
    if n.pos > reach + 0.0005 then break end
    last = last + 1
    reach = math.max(reach, n.pos + n.len)
  end
  local g = {}
  for i = first, last do g[#g + 1] = all[i] end
  return g
end
function K.group_cached()
  local key = table.concat({ r.GetProjectStateChangeCount(0), H.tick, tostring(S.item), S.scope }, "|")
  if key ~= K.gkey or not K.gcache then K.gkey, K.gcache = key, K.group() end
  return K.gcache
end
function K.span()
  local a, b = math.huge, -math.huge
  for _, e in ipairs(S.group) do a, b = math.min(a, e.pos), math.max(b, e.pos + e.len) end
  if a > b then return K.pos, K.pos + K.len end
  return a, b
end

-- the shown item: the first selected audio item (unless Follow is off)
function K.pick()
  local item = S.item
  if item and not r.ValidatePtr2(0, item, "MediaItem*") then item = nil end
  if S.follow or not item then item = r.GetSelectedMediaItem(0, 0) end
  local take = item and r.GetActiveTake(item)
  if take and r.TakeIsMIDI(take) then take = nil end
  S.item, S.take = take and item, take
  return take ~= nil
end

function K.fit()
  local a, b = K.span()
  local pad = math.max(0.01, (b - a) * 0.02)
  S.vs, S.ve = a - pad, b + pad
end

---------------------------------------------------------------- peaks
local P = { cache = {}, max = {} }
-- an event's peaks over a time range, one per pixel (REAPER's peak files: rate, stretch
-- markers, loops and reverse already applied). Cached until the view or the project changes.
function P.get(id, e, ta, tb, pps)
  local a, b = math.max(ta, e.pos), math.min(tb, e.pos + e.len)
  local c = P.cache[id]
  if b <= a then return nil end
  local tk = tostring(e.take)
  local key = table.concat({ tk, a, b, pps, e.nch, P.state }, "|")
  if c and c.key == key then return c end
  -- Above ~200 peaks/s REAPER answers in another output mode (bits 20-23 set) with an
  -- empty buffer (measured 2026-11-25). Ask at most 200/s, lower per take if a mode
  -- still comes back; the drawing spreads the peaks over the pixels.
  local rate = math.min(pps, P.max[tk] or 200)
  local buf, n, got
  while true do
    n = math.floor((b - a) * rate)
    if n < 1 then return nil end
    buf = r.new_array(n * e.nch * 2)
    local rv = math.floor(r.GetMediaItemTake_Peaks(e.take, rate, a, e.nch, n, 0, buf))
    got = rv & 0xFFFFF
    if (rv >> 20) & 0xF == 0 or rate <= 25 then break end
    rate = rate / 2
    P.max[tk] = rate
  end
  c = { key = got >= n - 2 and key or nil, buf = buf, n = got, req = n, t = a, rate = rate }
  P.cache[id] = c                    -- not all there yet (peaks being built): asked again next frame
  return c
end

---------------------------------------------------------------- fine peaks
-- REAPER's peaks stop at 200/s; zoomed in further, the editor reads the take's samples
-- (an audio accessor) into its own table of 1000 peaks/s, once per take and audio change,
-- a slice per frame so a long item never stalls. A scale factor matches it to REAPER's
-- peaks (take volume is drawn apart). Q.c: per take {key, rate, n, done, mx, mn, k}.
local Q = { c = {}, RATE = 1000, BUDGET = 131072 }

-- what changes the take's audio (not its envelopes): when it changes, read again
function Q.sig(e)
  local n, sm = r.GetTakeNumStretchMarkers(e.take), 0
  for i = 0, n - 1 do
    local _, pos, src = r.GetTakeStretchMarker(e.take, i)
    sm = sm + pos * 3 + src * 7
  end
  local loop = r.GetMediaItemInfo_Value(e.item, "B_LOOPSRC")
  return table.concat({ tostring(e.src), e.rate, e.len, e.nch, n, sm, loop,
    r.GetMediaItemTakeInfo_Value(e.take, "D_PITCH") }, "|"), n == 0 and loop == 0
end

function Q.fill(q)
  local nb = math.min(q.n - q.done, math.max(1, math.floor(Q.BUDGET / q.B)))
  local ns, nch, B = nb * q.B, q.nch, q.B
  local buf = r.new_array(ns * nch)
  local ok = r.GetAudioAccessorSamples(q.acc, q.sr, nch, q.done * B / q.sr, ns, buf)
  if ok ~= 1 then                    -- not readable (yet): again next frame, a while
    q.fails = (q.fails or 0) + 1
    if q.fails > 30 then q.failed = true end
    return
  end
  local t = buf.table()
  for b = 0, nb - 1 do
    local base = (q.done + b) * nch
    for c = 1, nch do
      local hi, lo = 0, 0
      for i = b * B, b * B + B - 1 do
        local v = t[i * nch + c] or 0
        if v > hi then hi = v elseif v < lo then lo = v end
      end
      q.mx[base + c], q.mn[base + c] = hi, lo
    end
  end
  q.done = q.done + nb
end

-- match the table to REAPER's own peaks (100/s over the whole item)
function Q.calibrate(q, e)
  local n = math.max(1, math.floor(e.len * 100))
  local buf = r.new_array(n * q.nch * 2)
  local got = math.floor(r.GetMediaItemTake_Peaks(e.take, 100, e.pos, q.nch, n, 0, buf)) & 0xFFFFF
  local pmax, hmax = 0, 0
  for i = 1, got * q.nch do pmax = math.max(pmax, math.abs(buf[i] or 0), math.abs(buf[n * q.nch + i] or 0)) end
  for i = 1, #q.mx do hmax = math.max(hmax, q.mx[i], -q.mn[i]) end
  if hmax == 0 and pmax > 0 then q.failed = true; return end    -- read silence: REAPER's peaks then
  if pmax == 0 and (q.tries or 0) < 60 then                     -- REAPER's peaks not ready: again
    q.tries = (q.tries or 0) + 1
    q.k = 1
    return false
  end
  -- no scaling: the samples come without take volume and its envelope, as REAPER's peaks
  -- leave out take volume; the envelope is drawn in (V.wave). A ratio would be skewed by it.
  q.k = 1
  return true
end

-- the fine table of an event, or nil while it is still being read
-- While a slip drags (Q.hold), a plain take (no stretch markers, no loop) keeps its table
-- and is drawn shifted (V.wave); on release the new offset is read again.
function Q.get(e)
  local id = tostring(e.take)
  local key, shiftable = Q.sig(e)
  local offs = r.GetMediaItemTakeInfo_Value(e.take, "D_STARTOFFS")
  local q = Q.c[id]
  if not q or q.key ~= key or (q.offs ~= offs and not (Q.hold and shiftable and q.done >= q.n)) then
    if q and q.acc then r.DestroyAudioAccessor(q.acc) end
    local src, sr = e.src, 44100
    if src then
      while r.GetMediaSourceParent(src) do src = r.GetMediaSourceParent(src) end
      sr = r.GetMediaSourceSampleRate(src)
      if not sr or sr <= 0 then sr = 44100 end
    end
    local B = math.max(1, math.floor(sr / Q.RATE + 0.5))
    q = { key = key, sr = sr, B = B, rate = sr / B, nch = e.nch, done = 0, mx = {}, mn = {}, k = 1,
      offs = offs, acc = r.CreateTakeAudioAccessor(e.take) }
    q.n = math.floor(e.len * q.rate)
    local count = 0
    for _ in pairs(Q.c) do count = count + 1 end
    if count >= 6 then Q.free() end      -- keep a few takes, not every one ever shown
    Q.c[id] = q
  end
  if q.failed then
    if q.acc then r.DestroyAudioAccessor(q.acc); q.acc = nil end
    return nil
  end
  if not q.acc and q.done < q.n then return nil end
  if q.done < q.n then
    Q.fill(q)
    if q.done < q.n then return nil end
  end
  if q.acc then
    r.DestroyAudioAccessor(q.acc)
    q.acc = nil
  end
  if not q.calibrated then q.calibrated = Q.calibrate(q, e) end
  if q.failed then return nil end
  return q
end

function Q.free()
  for _, q in pairs(Q.c) do if q.acc then r.DestroyAudioAccessor(q.acc) end end
  Q.c = {}
end

---------------------------------------------------------------- transients
-- Bitwig's onsets: where the hits start in the selected event, in project time. Found in
-- the peaks (200/s), then each one put on the sample where the attack begins. Shown with
-- the Stretch tool; dragging one makes it a stretch marker.
local O = { list = {}, sens = ({ low = 0.25, mid = 0.5, high = 0.75 })[S.sens] or 0.5 }

-- the attack start near t: read a few ms of samples and find where it rises
function O.refine(acc, e, t)
  local sr = 44100
  local w0, w1 = 0.015, 0.005
  local a = t - e.pos - w0
  if a < 0 then return t end
  local n = math.floor((w0 + w1) * sr)
  local buf = r.new_array(n * e.nch)
  if r.GetAudioAccessorSamples(acc, sr, e.nch, a, n, buf) ~= 1 then return t end
  local amp = {}
  for i = 1, n do
    local v = 0
    for c = 1, e.nch do v = math.max(v, math.abs(buf[(i - 1) * e.nch + c] or 0)) end
    amp[i] = v
  end
  local base, top = 0, 0
  for i = 1, math.floor(0.003 * sr) do base = math.max(base, amp[i]) end
  for i = 1, n do top = math.max(top, amp[i]) end
  if top <= base * 1.5 then return t end
  local lim = base + (top - base) * 0.3
  for i = 1, n do
    if amp[i] >= lim then
      local j = i      -- back to the zero crossing before it
      local s = buf[(i - 1) * e.nch + 1] or 0
      while j > 1 and ((buf[(j - 2) * e.nch + 1] or 0) > 0) == (s > 0) and i - j < sr * 0.002 do j = j - 1 end
      return e.pos + a + (j - 1) / sr
    end
  end
  return t
end

function O.find(e)
  local R = 200
  local n = math.floor(e.len * R)
  if n < 8 then return {}, true end
  local buf = r.new_array(n * 2)
  local rv = math.floor(r.GetMediaItemTake_Peaks(e.take, R, e.pos, 1, n, 0, buf))
  local got = rv & 0xFFFFF
  if got == 0 or (rv >> 20) & 0xF ~= 0 then return {}, false end
  local env, gmax = {}, 0
  for i = 1, got do
    env[i] = math.max(math.abs(buf[i] or 0), math.abs(buf[n + i] or 0))
    gmax = math.max(gmax, env[i])
  end
  if gmax <= 0 then return {}, true end
  local rise = {}
  for i = 1, got do
    local m = 0
    for j = math.max(1, i - 4), i - 1 do m = m + env[j] end
    m = i > 1 and m / math.min(4, i - 1) or 0
    rise[i] = math.max(0, env[i] - m)
  end
  local thr = (0.32 - 0.28 * O.sens) * gmax
  local acc = r.CreateTakeAudioAccessor(e.take)
  local list, last = {}, -1
  for i = 2, got do
    local d = rise[i]
    if d > thr and env[i] > gmax * 0.05 and (i - last) / R >= 0.06 then
      local peak = true
      for j = math.max(1, i - 3), math.min(got, i + 3) do
        if rise[j] > d then peak = false end
      end
      if peak then
        local t = e.pos + (i - 1) / R
        if acc then t = O.refine(acc, e, t) end
        if t > e.pos + 0.002 and t < e.pos + e.len - 0.002 then list[#list + 1] = t end
        last = i
      end
    end
  end
  if acc then r.DestroyAudioAccessor(acc) end
  return list, true
end

-- the selected event's onsets, found again when the project changes (not mid-drag)
function O.get()
  if O.hold then return O.list end           -- set by the canvas while a marker is dragged
  local key = table.concat({ tostring(S.take), K.pos, K.len, K.rate, P.state, O.sens }, "|")
  if key == O.key then return O.list end
  local ok
  O.list, ok = O.find(K)
  O.key = ok and key or nil
  return O.list
end

---------------------------------------------------------------- take envelopes
-- the kinds a lane can show; to / from map a raw envelope value to a 0..1 height
local E = { ORDER = { "vol", "pan", "pitch" } }
E.KINDS = {
  vol = { name = "Volume", env = "Volume", cmd = 40693, scale = { "+6 dB", "0 dB", "-inf" }, zero = function() return H.amp_to_y(1) end,
    to = function(v, mode) return H.amp_to_y(r.ScaleFromEnvelopeMode(mode, v)) end,
    from = function(f, mode) return r.ScaleToEnvelopeMode(mode, H.y_to_amp(f)) end,
    fmt = function(v, mode) return H.amp_db(r.ScaleFromEnvelopeMode(mode, v)) end },
  -- REAPER's pan envelope runs +1 (left, drawn at the top) to -1 (right)
  pan = { name = "Pan", env = "Pan", cmd = 40694, scale = { "L", "C", "R" }, zero = function() return 0.5 end, top = "L", bot = "R",
    to = function(v) return (H.clamp(v, -1, 1) + 1) / 2 end, from = function(f) return f * 2 - 1 end,
    fmt = function(v)
      if math.abs(v) < 0.005 then return "C" end
      return string.format("%d%% %s", math.floor(math.abs(v) * 100 + 0.5), v > 0 and "L" or "R")
    end },
  -- semitones, shown over +-12
  pitch = { name = "Pitch", env = "Pitch", cmd = 41612, scale = { "+12", "0", "-12" }, zero = function() return 0.5 end, top = "+12", bot = "-12",
    to = function(v) return (H.clamp(v, -12, 12) + 12) / 24 end, from = function(f) return f * 24 - 12 end,
    fmt = function(v) return string.format("%+.2f st", v) end },
}
function E.on(k) return ("," .. S.lanes .. ","):find("," .. k .. ",", 1, true) ~= nil end
function E.toggle(k)
  local list = {}
  for _, kk in ipairs(E.ORDER) do
    if (kk == k) ~= E.on(kk) then list[#list + 1] = kk end
  end
  S.lanes = table.concat(list, ",")
  S.lane = #list > 0
  if not S.lane then S.lanes = "vol" end
  save()
end
-- the take's envelope of a kind, made when there is none (for this item alone)
function E.ensure(L)
  if L.env then return L.env end
  local sel = {}
  for i = 0, r.CountSelectedMediaItems(0) - 1 do sel[#sel + 1] = r.GetSelectedMediaItem(0, i) end
  H.unselect_all()
  r.SetMediaItemSelected(L.e.item, true)
  r.Main_OnCommand(L.kind.cmd, 0)
  r.SetMediaItemSelected(L.e.item, false)
  for _, it in ipairs(sel) do r.SetMediaItemSelected(it, true) end
  L.env = r.GetTakeEnvelopeByName(L.e.take, L.kind.env)
  if L.k == "vol" and L.e.item == S.item then K.env = L.env end
  return L.env
end
-- a lane: {k, kind, env, y0, y1 (its rect), et, eb (the envelope's height)}
-- e: the event whose envelope it shows (the selected one when left out)
function E.lane(k, y0, y1, pad, e)
  e = e or K.e or K
  return { k = k, kind = E.KINDS[k], env = r.GetTakeEnvelopeByName(e.take, E.KINDS[k].env), e = e,
    y0 = y0, y1 = y1, et = y0 + pad, eb = y1 - pad }
end
-- an event's take time <-> project time
function E.to_take(L, t) return (t - L.e.pos) * L.e.rate end
function E.from_take(L, tt) return L.e.pos + tt / L.e.rate end
-- a lane's scale: the steps that fit (zero, top and bottom first, then the rest), as
-- {text, y}; the volume lane keeps REAPER's fader curve, so its dB steps lie unevenly
E.STEPS = {
  vol = { { "0 dB", 0 }, { "+6", 6 }, { "-inf", false }, { "-6", -6 }, { "-12", -12 }, { "-24", -24 }, { "-48", -48 },
    { "+3", 3 }, { "-3", -3 }, { "-18", -18 }, { "-36", -36 } },
  pan = { { "C", 0 }, { "L", 1 }, { "R", -1 }, { "50% L", 0.5 }, { "50% R", -0.5 } },
  pitch = { { "0", 0 }, { "+12", 12 }, { "-12", -12 }, { "+6", 6 }, { "-6", -6 }, { "+3", 3 }, { "-3", -3 } },
}
function E.ticks(L)
  local out, h = {}, L.eb - L.et
  for _, st in ipairs(E.STEPS[L.k]) do
    local f
    if L.k == "vol" then f = st[2] and H.amp_to_y(10 ^ (st[2] / 20)) or 0
    else f = L.kind.to(st[2]) end
    local y = L.eb - f * h
    local free = true
    for _, o in ipairs(out) do if math.abs(o.y - y) < 12 then free = false end end
    if free then out[#out + 1] = { text = st[1], y = y, zero = st[2] == 0 } end
  end
  return out
end
function E.y(L, v, mode) return L.eb - L.kind.to(v, mode) * (L.eb - L.et) end
function E.value(L, my, mode) return L.kind.from(H.clamp((L.eb - my) / (L.eb - L.et), 0, 1), mode) end

---------------------------------------------------------------- view
local V = {}   -- view mapping, set each frame: V.x, V.w, V.pps
function V.X(t) return V.x + (t - S.vs) * V.pps end
function V.T(x) return S.vs + (x - V.x) / V.pps end
function V.snap(t, shift)
  if S.snap and not shift then return r.SnapToGrid(0, t) end
  return t
end
function V.range()
  local a, b = K.span()
  local pad = math.max(0.01, (b - a) * 0.25)
  return a - pad, b + pad
end
function V.clamp()
  local lo, hi = V.range()
  local span = S.ve - S.vs
  if span > hi - lo then lo, hi = (lo + hi - span) / 2, (lo + hi + span) / 2 end
  if S.vs < lo then S.vs, S.ve = lo, lo + span end
  if S.ve > hi then S.vs, S.ve = hi - span, hi end
end
function V.zoom(factor, at)
  local lo, hi = V.range()
  local span = H.clamp((S.ve - S.vs) * factor, 0.005, hi - lo)
  local k = (at - S.vs) / (S.ve - S.vs)
  S.vs = at - span * k
  S.ve = S.vs + span
  V.clamp()
end
function V.scroll(dt)
  S.vs, S.ve = S.vs + dt, S.ve + dt
  V.clamp()
end

-- the ruler in bars and beats (1.1, 1.2, ...), from the project's tempo map, with the grid
-- carried down the canvas
function V.ruler(dl, x, y, w, wy0, wy1)
  r.ImGui_DrawList_AddRectFilled(dl, x, y, x + w, y + RULER_H, C.ruler)
  local _, m = r.TimeMap2_timeToBeats(0, S.vs)
  m = math.max(0, m)
  local guard, label_every = 0, 1
  while guard < 4000 do
    guard = guard + 1
    local ts, qs, qe, num = r.TimeMap_GetMeasureInfo(0, m)
    if ts > S.ve then break end
    num = math.max(1, num)
    local te = r.TimeMap2_QNToTime(0, qe)
    local bar_px = (te - ts) * V.pps
    if guard == 1 then while bar_px * label_every < 44 and label_every < 1024 do label_every = label_every * 2 end end
    local beat_px = bar_px / num
    local sub = beat_px >= 60 and 4 or beat_px >= 30 and 2 or 1
    local bar = r.format_timestr_pos(ts + 0.0000001, "", 2):match("^[^%.]+") or tostring(m + 1)
    local qpb = (qe - qs) / num
    for b = 0, num * sub - 1 do
      local on_bar, on_beat = b == 0, b % sub == 0
      if on_bar or beat_px >= 6 then
        local bt = on_bar and ts or r.TimeMap2_QNToTime(0, qs + b * qpb / sub)
        local xx = V.X(bt)
        if xx >= x - 1 and xx <= x + w then
          local line = on_bar and C.bar or on_beat and C.beat or C.sub
          r.ImGui_DrawList_AddLine(dl, xx, wy0, xx, wy1, line)
          if on_bar and m % label_every == 0 then
            r.ImGui_DrawList_AddLine(dl, xx, y + 5, xx, y + RULER_H, C.dim)
            r.ImGui_DrawList_AddText(dl, xx + 3, y + 1, C.text, bar .. ".1")
          elseif on_beat and beat_px >= 40 then
            r.ImGui_DrawList_AddLine(dl, xx, y + 9, xx, y + RULER_H, C.dim)
            r.ImGui_DrawList_AddText(dl, xx + 3, y + 1, C.dim, bar .. "." .. (b // sub + 1))
          else
            r.ImGui_DrawList_AddLine(dl, xx, (on_bar or on_beat) and y + 14 or y + 18, xx, y + RULER_H, C.line)
          end
        end
      end
    end
    m = m + 1
  end
end

-- one event's waveform (grey, as Bitwig) with its fades worked in, and the fade curves
-- Drawn shapes kept between frames: the waveform, envelope lines, the overview are built
-- once into point arrays and drawn with one call each, until the view or project changes
-- (hundreds of separate line calls per frame cost real CPU). V.pc[id] = {key, arrs}.
V.pc = {}
function V.cached(id, key, build)
  local c = V.pc[id]
  if c and c.key == key then return c.arrs end
  local arrs = build()
  V.pc[id] = { key = key, arrs = arrs }
  return arrs
end
-- columns (x, top y, bottom y) as one polyline: down one column, up the next
function V.zigzag(cols)
  local pts, n = {}, 0
  for k = 1, #cols, 3 do
    local x, a, b = cols[k] + 0.5, cols[k + 1], cols[k + 2]
    if (k // 3) % 2 == 1 then a, b = b, a end
    pts[n + 1], pts[n + 2], pts[n + 3], pts[n + 4] = x, a, x, b
    n = n + 4
  end
  return n >= 4 and r.new_array(pts) or nil
end

function V.wave(dl, id, e, top, bot, active)
  local x0, x1 = math.max(V.X(e.pos), V.x), math.min(V.X(e.pos + e.len), V.x + V.w)
  if x1 <= x0 then return end
  if active then r.ImGui_DrawList_AddRectFilled(dl, x0, top, x1, bot, C.active) end
  local lane = (bot - top) / e.nch
  for c = 0, e.nch - 1 do
    local mid = top + lane * (c + 0.5)
    r.ImGui_DrawList_AddLine(dl, x0, mid, x1, mid, C.mid)
  end
  local col = e.mute and C.wave_dim or C.wave
  local hh = lane / 2 - 1
  local gain = math.abs(e.vol) * S.vzoom
  local function g_at(t)
    local g = gain
    if e.fin > 0 and t < e.pos + e.fin then g = g * H.fade_gain(e.fin_shape, (t - e.pos) / e.fin) end
    if e.fout > 0 and t > e.pos + e.len - e.fout then g = g * H.fade_gain(e.fout_shape, (e.pos + e.len - t) / e.fout) end
    return g
  end
  -- zoomed in past REAPER's peaks: the editor's own fine table (REAPER's until it is read)
  local q = V.pps > 240 and e.len <= 900 and Q.get(e)
  local pk = not q and P.get(id, e, S.vs, S.ve, V.pps)
  if not q and not (pk and pk.n > 0) then return V.fades(dl, e, top, bot, active) end
  -- REAPER's peaks hold the take's volume envelope, the fine table does not: put it in
  local venv = q and r.GetTakeEnvelopeByName(e.take, "Volume")
  -- a slip being dragged: the audio drawn shifted inside the event (REAPER moves it on release)
  local shift = (V.slip and V.slip.item == e.item) and V.slip.dt * V.pps or 0
  local key = table.concat({ tostring(e.take), S.vs, S.ve, V.x, V.w, top, bot, S.vzoom, e.vol, e.fin, e.fout,
    e.fin_shape, e.fout_shape, shift, q and ("q" .. q.k .. q.key .. q.offs .. r.GetMediaItemTakeInfo_Value(e.take, "D_STARTOFFS") .. (venv and P.state or "")) or (tostring(pk.key) .. pk.n) }, "|")
  local arrs = V.cached("w" .. id, key, function()
    local cols = {}
    for c = 1, e.nch do cols[c] = {} end
    local function put(c, px, hi, lo, g)
      local mid = top + lane * (c - 0.5)
      local y1 = mid - H.clamp(hi * g, -1, 1) * hh
      local y2 = mid - H.clamp(lo * g, -1, 1) * hh
      if y2 - y1 < 1 then y2 = y1 + 1 end
      local t = cols[c]
      t[#t + 1], t[#t + 2], t[#t + 3] = px + shift, y1, y2
    end
    local sp = V.slip and V.slip.item == e.item and V.slip.sp
    if sp then
      -- the slip preview: every pixel of the event looks up its source time, shifted by the drag
      shift = 0
      local dt, b, n, nch, R = V.slip.dt, sp.buf, sp.n, sp.nch, sp.R
      for px = math.floor(x0), math.floor(x1) - 1 do
        local t = V.T(px)
        local s0 = sp.map((t - e.pos - dt) * e.rate)
        local s1 = sp.map((t + 1 / V.pps - e.pos - dt) * e.rate)
        if sp.loop then s0, s1 = s0 % sp.len, s0 % sp.len + (s1 - s0) end
        local i0 = math.floor(s0 * R)
        local i1 = math.max(i0, math.floor(s1 * R) - 1)
        if i1 >= 0 and i0 < sp.got then
          i0, i1 = math.max(0, i0), math.min(sp.got - 1, i1)
          local g = g_at(t)
          for c = 1, nch do
            local hi, lo = 0, 0
            for k = i0, i1 do
              local a, m = b[k * nch + c] or 0, b[n * nch + k * nch + c] or 0
              if a > hi then hi = a end
              if m < lo then lo = m end
            end
            put(c, px, hi, lo, g)
          end
        end
      end
    elseif q then
      local nch, mx, mn, rate = q.nch, q.mx, q.mn, q.rate
      local dt = (r.GetMediaItemTakeInfo_Value(e.take, "D_STARTOFFS") - q.offs) / e.rate   -- a slip in progress
      local vmode = venv and r.GetEnvelopeScalingMode(venv)
      for px = math.floor(x0), math.floor(x1) - 1 do
        local t = V.T(px)
        local i0 = math.max(0, math.floor((t - e.pos + dt) * rate))
        local i1 = math.min(q.n - 1, math.max(i0, math.floor((t + 1 / V.pps - e.pos + dt) * rate) - 1))
        if i0 <= i1 then
          local g = g_at(t) * q.k
          if venv then
            local _, v = r.Envelope_Evaluate(venv, (t - e.pos) * e.rate, 0, 0)
            g = g * r.ScaleFromEnvelopeMode(vmode, v)
          end
          for c = 1, nch do
            local hi, lo = 0, 0
            for k = i0, i1 do
              local a, b = mx[k * nch + c], mn[k * nch + c]
              if a > hi then hi = a end
              if b < lo then lo = b end
            end
            put(c, px, hi, lo, g)
          end
        end
      end
    else
      local buf, n, nch = pk.buf.table(), pk.req, e.nch
      local px0 = math.floor(V.X(pk.t))
      local step = pk.rate / V.pps         -- peaks per pixel (1 unless the rate was lowered)
      for k = 0, math.floor(pk.n / step) - 1 do
        local jj = math.min(pk.n - 1, math.floor(k * step))
        local g = g_at(pk.t + k / V.pps)
        for c = 1, nch do
          put(c, px0 + k, buf[jj * nch + c] or 0, buf[n * nch + jj * nch + c] or 0, g)
        end
      end
    end
    local arrs = {}
    for c = 1, e.nch do arrs[c] = V.zigzag(cols[c]) end
    return arrs
  end)
  for c = 1, e.nch do
    if arrs[c] then
      r.ImGui_DrawList_PushClipRect(dl, x0, top, x1, bot, true)
      r.ImGui_DrawList_AddPolyline(dl, arrs[c], col, 0, 1)
      r.ImGui_DrawList_PopClipRect(dl)
    end
  end
  V.fades(dl, e, top, bot, active)
end

-- the fade curves over an event
function V.fades(dl, e, top, bot, active)
  -- as Bitwig: the curve in the event's colour, the part it cuts away (above it) faintly
  -- tinted; built
  -- once per change (a zigzag of 2 px columns + the curve), drawn with two calls per fade
  local fh = bot - top
  local function fade(id, t0, t1, shape, out)
    local x0, x1 = V.X(t0), V.X(t1)
    if x1 < V.x or x0 > V.x + V.w then return end
    local key = table.concat({ t0, t1, shape, tostring(out), top, bot, S.vs, S.ve, V.x }, "|")
    local c = V.cached("f" .. id .. tostring(e.take), key, function()
      local line, cols = {}, {}
      local n = math.max(2, math.min(48, math.floor((x1 - x0) / 2)))
      for i = 0, n do
        local u = i / n
        local g = H.fade_gain(shape, out and 1 - u or u)
        local x, y = x0 + (x1 - x0) * u, top + (1 - g) * fh
        line[#line + 1], line[#line + 2] = x, y
      end
      for x = math.floor(x0), math.ceil(x1), 2 do
        local u = H.clamp((x - x0) / math.max(x1 - x0, 1), 0, 1)
        local g = H.fade_gain(shape, out and 1 - u or u)
        cols[#cols + 1], cols[#cols + 2], cols[#cols + 3] = x, top, top + (1 - g) * fh
      end
      return { line = r.new_array(line), fill = V.zigzag(cols) }
    end)
    if c.fill then r.ImGui_DrawList_AddPolyline(dl, c.fill, H.shade(e.rgb, 0, active and 0x38 or 0x22), 0, 2) end
    r.ImGui_DrawList_AddPolyline(dl, c.line, H.shade(e.rgb, active and 0.25 or -0.1), 0, active and 1.5 or 1)
  end
  if e.fin > 0 then fade("in", e.pos, e.pos + e.fin, e.fin_shape, false) end
  if e.fout > 0 then fade("out", e.pos + e.len - e.fout, e.pos + e.len, e.fout_shape, true) end
end

-- the clip: its bar, the events' headers and waveforms; the selected event's handles,
-- volume envelope and stretch markers
function V.clip(dl, top, bot)
  -- one bar per clip: a run of touching events (in Track scope the gaps stay empty)
  local runs, run = {}, nil
  for _, e in ipairs(#S.group > 0 and S.group or { K }) do
    if run and e.pos <= run.b + 0.0005 then
      run.b = math.max(run.b, e.pos + e.len)
    else
      run = { a = e.pos, b = e.pos + e.len, first = e, rgb = e.rgb }
      runs[#runs + 1] = run
    end
    if e.item == S.item then run.rgb = K.rgb end
  end
  r.ImGui_PushFont(ctx, font_bold, 11)
  for _, c in ipairs(runs) do
    local cx0, cx1 = V.X(c.a), V.X(c.b)
    if cx1 > V.x and cx0 < V.x + V.w then
      r.ImGui_DrawList_AddRectFilled(dl, cx0 + 1, top, cx1 - 1, top + BAR_H, H.shade(c.rgb, 0))
      r.ImGui_DrawList_PushClipRect(dl, math.max(cx0, V.x), top, math.min(cx1, V.x + V.w) - 2, top + BAR_H, true)
      r.ImGui_DrawList_AddText(dl, math.max(cx0, V.x) + 5, top + 1, 0x141414FF,
        c.first.name ~= "" and c.first.name or "Clip")
      r.ImGui_DrawList_PopClipRect(dl)
    end
  end
  r.ImGui_PopFont(ctx)

  local hy = top + BAR_H + 1
  local wt, wb = hy + HEAD_H + 1, bot
  V.bar_y1, V.head_y0, V.head_y1, V.wt, V.wb = top + BAR_H, hy, hy + HEAD_H, wt, wb
  V.events = {}
  for i, e in ipairs(S.group) do
    local active = e.item == S.item
    local picked = not active and r.IsMediaItemSelected(e.item)
    local ex0, ex1 = V.X(e.pos), V.X(e.pos + e.len)
    V.events[#V.events + 1] = { x0 = ex0, x1 = ex1, e = e }
    if ex1 > V.x and ex0 < V.x + V.w then
      r.ImGui_DrawList_AddRectFilled(dl, ex0 + 1, hy, ex1 - 1, hy + HEAD_H,
        active and H.shade(e.rgb, 0) or H.shade(e.rgb, picked and -0.15 or -0.45))
      r.ImGui_DrawList_PushClipRect(dl, math.max(ex0, V.x), hy, math.min(ex1, V.x + V.w) - 2, hy + HEAD_H, true)
      r.ImGui_DrawList_AddText(dl, math.max(ex0, V.x) + 4, hy - 1,
        (active or picked) and 0x141414FF or H.shade(e.rgb, 0.45), e.name ~= "" and e.name or "Event")
      r.ImGui_DrawList_PopClipRect(dl)
      r.ImGui_DrawList_AddLine(dl, ex0 + 1, hy, ex0 + 1, wb, H.shade(e.rgb, -0.3))
      V.wave(dl, i, e, wt, wb, active)
    end
  end

  -- the selected event: fade handles, gain box, envelope, stretch markers
  local ax0, ax1 = V.X(K.pos), V.X(K.pos + K.len)
  V.hfin, V.hfout = V.X(K.pos + K.fin), V.X(K.pos + K.len - K.fout)
  for _, hx in ipairs({ V.hfin, V.hfout }) do
    r.ImGui_DrawList_AddRectFilled(dl, hx - 4, wt, hx + 4, wt + 8, C.handle)
  end
  local gtext = H.amp_db(math.abs(K.vol))
  local gw = r.ImGui_CalcTextSize(ctx, gtext) + 10
  local gx1 = math.min(ax1, V.x + V.w) - 3
  V.gain = nil
  if gx1 - gw > math.max(ax0, V.x) + 50 then
    V.gain = { gx1 - gw, hy, gx1, hy + HEAD_H }
    r.ImGui_DrawList_AddRectFilled(dl, gx1 - gw, hy + 1, gx1, hy + HEAD_H - 1, C.field, 2)
    r.ImGui_DrawList_AddText(dl, gx1 - gw + 5, hy - 1, C.value, gtext)
  end

  -- without lanes the volume envelope lies on the clip
  V.cliplanes = nil
  if not S.lane and S.show_env then
    V.cliplanes = {}
    for _, ev in ipairs(S.group) do
      local Le = E.lane("vol", wt, wb, 0, ev)
      V.cliplanes[ev.item] = Le
      V.env(dl, Le, ev.item == S.item)
    end
  end

  V.sms = {}
  if S.show_sm then
    local prev
    for i = 0, r.GetTakeNumStretchMarkers(S.take) - 1 do
      local _, pos, srcpos = r.GetTakeStretchMarker(S.take, i)
      local x = V.X(K.from_take(pos))
      V.sms[#V.sms + 1] = { i = i, x = x, pos = pos, src = srcpos }
      r.ImGui_DrawList_AddLine(dl, x, hy + HEAD_H, x, wb, C.marker)
      r.ImGui_DrawList_AddTriangleFilled(dl, x - 5, hy, x + 5, hy, x, hy + HEAD_H - 1, C.marker)
      if prev and pos > prev.pos and x - prev.x > 56 then
        local k = (srcpos - prev.src) / (pos - prev.pos)
        if math.abs(k - 1) > 0.001 then
          local s = string.format("%.2fx", k)
          local tw = r.ImGui_CalcTextSize(ctx, s)
          r.ImGui_DrawList_AddText(dl, (prev.x + x - tw) / 2, wt + 2, C.marker, s)
        end
      end
      prev = V.sms[#V.sms]
    end
  end

  -- the Stretch tool shows the onsets: dashed lines, a hollow tick in the header
  V.onsets = {}
  if S.tool == "stretch" then
    local col = C.marker
    for _, t in ipairs(O.get()) do
      local x = V.X(t)
      local taken = false
      for _, sm in ipairs(V.sms) do if math.abs(sm.x - x) < 4 then taken = true end end
      if not taken and x >= V.x - 4 and x <= V.x + V.w + 4 then
        V.onsets[#V.onsets + 1] = { x = x, t = t }
        -- dashed yellow with a dark edge, so it shows on the grey wave; real markers are solid
        for yy = hy + HEAD_H, wb, 7 do
          local y2 = math.min(yy + 4, wb)
          r.ImGui_DrawList_AddLine(dl, x + 1, yy, x + 1, y2, 0x000000B0)
          r.ImGui_DrawList_AddLine(dl, x, yy, x, y2, col)
        end
        r.ImGui_DrawList_AddTriangle(dl, x - 4, hy + 1, x + 4, hy + 1, x, hy + HEAD_H - 2, C.marker, 1.5)
      end
    end
  end
end

-- a take envelope over the selected event: its line and points (V.env_pts, for the mouse)
function V.env(dl, L, active)
  if not L.env then return end
  local e = L.e
  local key = table.concat({ tostring(L.env), P.state, S.vs, S.ve, V.x, V.w, L.et, L.eb, e.pos, e.len, e.rate,
    tostring(S.lane) }, "|")
  local c = V.cached("e" .. L.k .. tostring(e.take), key, function()
    local ax0, ax1 = V.X(e.pos), V.X(e.pos + e.len)
    local mode = r.GetEnvelopeScalingMode(L.env)
    local xa, xb = math.max(ax0, V.x), math.min(ax1, V.x + V.w)
    local pts, cols = {}, {}
    -- the fill reaches the lane's bottom for volume, the zero line for pan and pitch
    local base = L.k == "vol" and L.eb or (L.eb - L.kind.zero() * (L.eb - L.et))
    for x = xa, xb + 2, 3 do
      local xx = math.min(x, xb)
      local _, v = r.Envelope_Evaluate(L.env, E.to_take(L, V.T(xx)), 0, 0)
      local y = E.y(L, v, mode)
      pts[#pts + 1], pts[#pts + 2] = xx, y
      if L.y0 then cols[#cols + 1], cols[#cols + 2], cols[#cols + 3] = xx - 0.5, y, base end
    end
    local dots = {}
    for i = 0, r.CountEnvelopePoints(L.env) - 1 do
      local _, tt, v = r.GetEnvelopePoint(L.env, i)
      dots[#dots + 1] = { i = i, x = V.X(E.from_take(L, tt)), y = E.y(L, v, mode) }
    end
    return { line = #pts >= 4 and r.new_array(pts) or nil, dots = dots, fill = S.lane and V.zigzag(cols) or nil }
  end)
  -- the area under the line, see-through (one cached zigzag of 3 px columns)
  if c.fill then r.ImGui_DrawList_AddPolyline(dl, c.fill, active and C.env_fill or C.env_fill_dim, 0, 3) end
  local col = active and C.env or C.env_dim
  if c.line then r.ImGui_DrawList_AddPolyline(dl, c.line, col, 0, active and 2 or 1.5) end
  for _, d in ipairs(c.dots) do
    V.env_pts[#V.env_pts + 1] = { i = d.i, x = d.x, y = d.y, L = L }
    if d.x >= V.x - 5 and d.x <= V.x + V.w + 5 then
      r.ImGui_DrawList_AddCircleFilled(dl, d.x, d.y, active and 4 or 3, col)
      r.ImGui_DrawList_AddCircle(dl, d.x, d.y, 4, 0x141414FF)
    end
  end
end

-- the overview under the canvas: the whole clip small, the view framed; it scrolls
function V.overview(dl, x, y, w, h)
  r.ImGui_DrawList_AddRectFilled(dl, x, y, x + w, y + h, C.field)
  local gw = w - 52
  local lo, hi = V.range()
  local full = math.max(hi - lo, S.ve - S.vs)
  local pps = gw / full
  local mid = y + h / 2
  for i, e in ipairs(S.group) do
    local pk = P.get("ov" .. i, { take = e.take, pos = e.pos, len = e.len, nch = 1 }, lo, lo + full, pps)
    if pk and pk.n > 0 then
      local key = table.concat({ tostring(pk.key), pk.n, x, y, h, lo, pps }, "|")
      local arr = V.cached("ov" .. i, key, function()
        local px0 = math.floor(x + (pk.t - lo) * pps)
        local step = pk.rate / pps
        local buf, cols = pk.buf.table(), {}
        for k = 0, math.floor(pk.n / step) - 1 do
          local j = math.min(pk.n - 1, math.floor(k * step))
          local a = math.max(math.abs(buf[j + 1] or 0), math.abs(buf[pk.req + j + 1] or 0)) * (h / 2 - 2)
          cols[#cols + 1], cols[#cols + 2], cols[#cols + 3] = px0 + k, mid - a, mid + a + 1
        end
        return { V.zigzag(cols) }
      end)
      if arr[1] then r.ImGui_DrawList_AddPolyline(dl, arr[1], C.over, 0, 1) end
    end
  end
  local ta = x + (S.vs - lo) / full * gw
  local tb = ta + (S.ve - S.vs) / full * gw
  r.ImGui_DrawList_AddRect(dl, math.max(x, ta), y + 1, math.min(x + gw, tb), y + h - 1, C.dim, 2)
  V.over = { x = x, w = gw, lo = lo, full = full }
  local _, div = r.GetSetProjectGrid(0, false)
  local inv = div > 0 and 1 / div or 0
  local s = string.format("[%.3g]", div)
  if math.abs(inv - math.floor(inv + 0.5)) < 0.001 then
    local d = math.floor(inv + 0.5)
    s = (d % 3 == 0 and d % 2 == 0) and string.format("[1/%dT]", d * 2 // 3) or string.format("[1/%d]", d)
  end
  r.ImGui_DrawList_AddText(dl, x + w - 46, y + (h - 13) / 2, C.dim, s)
end

---------------------------------------------------------------- mouse on the canvas
local M = {}   -- the drag in progress: M.kind and its data

-- what is under the mouse, in order: handles before lines before events
function M.hit(mx, my, ry1, oy0)
  if my < ry1 then return { kind = "ruler" } end
  if my > oy0 then
    if V.over and mx > V.over.x + V.over.w then return { kind = "grid" } end
    return { kind = "scroll" }
  end
  if not V.wt then return { kind = "time" } end
  if my <= V.bar_y1 then return { kind = "bar" } end
  local ltop = V.lane_top
  if ltop and math.abs(my - ltop) <= 3 then return { kind = "split" } end
  local in_lane = ltop and my > ltop
  local L
  local ev0
  for _, v in ipairs(V.events or {}) do
    if mx >= v.x0 and mx < v.x1 then ev0 = v.e end
  end
  if in_lane then
    for _, l in ipairs(V.lanes or {}) do
      if my >= l.y0 and my <= l.y1 then L = ev0 and l.events and l.events[ev0.item] end
    end
  elseif V.cliplanes and ev0 then
    L = V.cliplanes[ev0.item]
  end
  local ev
  for _, v in ipairs(V.events or {}) do
    if mx >= v.x0 and mx < v.x1 then ev = v.e end
  end
  local erase = S.tool == "erase"
  local active = ev and ev.item == S.item
  if active then
    local g = V.gain
    if g and mx >= g[1] and mx <= g[3] and my >= g[2] and my <= g[4] then return { kind = "gain" } end
  end
  if my >= V.wt - 2 and my <= V.wt + 10 then
    if math.abs(mx - V.hfin) <= 6 then return { kind = "fin" } end
    if math.abs(mx - V.hfout) <= 6 then return { kind = "fout" } end
  end
  -- an event's edges (Pointer): the side inside the event wins where two events touch
  if S.tool == "pointer" and not in_lane and my > V.head_y0 then
    for _, v in ipairs(V.events or {}) do
      if mx >= v.x1 - 5 and mx <= v.x1 + 1 then return { kind = "edge_r", e = v.e } end
    end
    for _, v in ipairs(V.events or {}) do
      if mx >= v.x0 - 1 and mx <= v.x0 + 5 then return { kind = "edge_l", e = v.e } end
    end
  end
  for _, s in ipairs(in_lane and {} or V.sms or {}) do
    if math.abs(mx - s.x) <= (my < V.head_y1 and 6 or 3) then return { kind = "sm", idx = s.i, erase = erase } end
  end
  for _, o in ipairs(in_lane and {} or V.onsets or {}) do
    if math.abs(mx - o.x) <= (my < V.head_y1 and 5 or 3) then return { kind = "onset", t = o.t } end
  end
  for _, p in ipairs(V.env_pts or {}) do
    if math.abs(mx - p.x) <= 6 and math.abs(my - p.y) <= 6 then return { kind = "pt", idx = p.i, erase = erase, L = p.L } end
  end
  if my <= V.head_y1 then return { kind = ev and "head" or "time", e = ev } end
  if L and L.env and S.tool ~= "knife" and (in_lane or active) then
    local tt = E.to_take(L, V.T(mx))
    local _, v = r.Envelope_Evaluate(L.env, tt, 0, 0)
    local d = math.abs(my - E.y(L, v, r.GetEnvelopeScalingMode(L.env)))
    if d <= 5 then return { kind = "line", L = L } end
    -- just above or below the line, between two points (in a lane): the part moves as one
    if in_lane and d <= 16 and S.tool ~= "erase" then
      local i = r.GetEnvelopePointByTime(L.env, tt)
      if i and i >= 0 and i < r.CountEnvelopePoints(L.env) - 1 then return { kind = "seg", L = L, idx = i } end
    end
  end
  if in_lane then return { kind = L and "lane" or "time", e = ev, L = L, in_lane = true } end
  return { kind = ev and "body" or "time", e = ev }
end

-- a point in lane L (its envelope made when there is none); the drag takes it on
function M.add_point(mx, my, shift, L)
  if not L then return end
  local env = E.ensure(L)
  if not env then return end
  local mode = r.GetEnvelopeScalingMode(env)
  local tt = E.to_take(L, V.snap(V.T(mx), shift))
  r.InsertEnvelopePoint(env, tt, E.value(L, my, mode), 0, 0, false, true)
  r.Envelope_SortPoints(env)
  local idx = r.GetEnvelopePointByTime(env, tt + 0.0000001)
  if idx then M.kind, M.idx, M.L = "pt", idx, L end
  return idx
end

function M.add_marker(mx, shift)
  local tt = K.to_take(V.snap(V.T(mx), shift))
  if tt <= 0 or tt >= K.len * K.rate then return end
  local idx = r.SetTakeStretchMarker(S.take, -1, tt)
  if idx and idx >= 0 then M.kind, M.idx = "sm", idx end
end

function M.delete(h)
  if h.kind == "pt" then
    r.DeleteEnvelopePointEx(h.L.env, -1, h.idx); r.Envelope_SortPoints(h.L.env); H.undo("delete point")
  elseif h.kind == "sm" then
    r.DeleteTakeStretchMarkers(S.take, h.idx); H.undo("delete stretch marker")
  end
end

-- For the slip preview: the whole source's peaks (200/s, read once when the drag starts)
-- and a map from take time to source time (stretch markers as pieces, else the offset),
-- so the audio that slides into the event can be drawn before REAPER moves it.
function M.slip_source(e)
  local src = e.src
  if not src then return nil end
  local len, qn = r.GetMediaSourceLength(src)
  if qn or not len or len <= 0 or len > 900 then return nil end
  local R = 200
  local n = math.max(1, math.floor(len * R))
  local buf = r.new_array(n * e.nch * 2)
  local rv = math.floor(r.PCM_Source_GetPeaks(src, R, 0, e.nch, n, 0, buf))
  local got = rv & 0xFFFFF
  if got == 0 or (rv >> 20) & 0xF ~= 0 then return nil end
  local sm = {}
  for i = 0, r.GetTakeNumStretchMarkers(e.take) - 1 do
    local _, pos, srcpos = r.GetTakeStretchMarker(e.take, i)
    sm[#sm + 1] = { pos, srcpos }
  end
  local offs = r.GetMediaItemTakeInfo_Value(e.take, "D_STARTOFFS")
  local function map(tt)              -- take time -> source time
    if #sm == 0 then return offs + tt end
    if tt <= sm[1][1] then return sm[1][2] + (tt - sm[1][1]) end
    for i = 1, #sm - 1 do
      local a, b = sm[i], sm[i + 1]
      if tt <= b[1] then return a[2] + (tt - a[1]) * (b[2] - a[2]) / math.max(b[1] - a[1], 0.000001) end
    end
    return sm[#sm][2] + (tt - sm[#sm][1])
  end
  return { buf = buf.table(), n = n, got = got, R = R, len = len, nch = e.nch, map = map,
    loop = r.GetMediaItemInfo_Value(e.item, "B_LOOPSRC") ~= 0 }
end

function M.press(h, mx, my, alt, shift, right, double)
  local k = h.kind
  M.x0, M.y0, M.moved, M.idx, M.L = mx, my, false, h.idx, h.L
  M.t0 = V.snap(V.T(mx), shift)
  if k == "seg" and not right and not alt then
    local L, env = h.L, h.L.env
    local mode = r.GetEnvelopeScalingMode(env)
    local _, _, va = r.GetEnvelopePoint(env, h.idx)
    local _, _, vb = r.GetEnvelopePoint(env, h.idx + 1)
    M.kind, M.idx, M.L = "seg", h.idx, L
    M.ya, M.yb = E.y(L, va, mode), E.y(L, vb, mode)
    return
  end
  -- Alt on an envelope line (as Bitwig): drag up / down bends that segment (REAPER's bezier
  -- shape and its tension); Alt+double-click makes it straight again
  if alt and not right and k == "line" and h.L and h.L.env then
    local L, env = h.L, h.L.env
    local n = r.CountEnvelopePoints(env)
    local i = r.GetEnvelopePointByTime(env, E.to_take(L, V.T(mx)))
    if i and i >= 0 and i < n - 1 then
      local _, t0, v0, shape, tension, sel = r.GetEnvelopePoint(env, i)
      local _, t1 = r.GetEnvelopePoint(env, i + 1)
      if double then
        r.SetEnvelopePoint(env, i, t0, v0, 0, 0, sel, true)
        H.undo("envelope curve")
        return
      end
      -- which way positive tension bends this segment on screen: try it at its middle
      local mode = r.GetEnvelopeScalingMode(env)
      local tm = (t0 + t1) / 2
      r.SetEnvelopePoint(env, i, t0, v0, 5, 0, sel, true)
      local _, flat = r.Envelope_Evaluate(env, tm, 0, 0)
      r.SetEnvelopePoint(env, i, t0, v0, 5, 0.5, sel, true)
      local _, bent = r.Envelope_Evaluate(env, tm, 0, 0)
      r.SetEnvelopePoint(env, i, t0, v0, shape, tension, sel, true)
      M.kind, M.idx, M.L = "curve", i, L
      M.tens0 = shape == 5 and tension or 0
      M.cdir = E.y(L, bent, mode) <= E.y(L, flat, mode) and 1 or -1
    end
    return
  end
  if not right and (k == "edge_l" or k == "edge_r") then
    if h.e.item ~= S.item then H.select(h.e.item) end
    M.kind, M.e, M.edge_t = k, h.e, nil
    return
  end
  if alt and not right and S.tool == "pointer" and (k == "body" or k == "head") and h.e then
    if h.e.item ~= S.item then H.select(h.e.item) end
    M.kind, M.e, M.dt = "slip", h.e, 0
    M.sp = M.slip_source(h.e)
    M.offs0 = r.GetMediaItemTakeInfo_Value(h.e.take, "D_STARTOFFS")
    return
  end
  if right or alt or h.erase then
    if k == "pt" or k == "sm" then M.delete(h)
    elseif right and (k == "fin" or k == "fout") then
      local key = k == "fin" and "C_FADEINSHAPE" or "C_FADEOUTSHAPE"
      r.SetMediaItemInfo_Value(S.item, key, (math.floor(r.GetMediaItemInfo_Value(S.item, key)) + 1) % 7)
      H.undo("fade shape")
    elseif right and h.in_lane then
      r.ImGui_OpenPopup(ctx, "##lanes")
    elseif right then
      if h.e and h.e.item ~= S.item then H.select(h.e.item) end
      r.ImGui_OpenPopup(ctx, "##menu")
    end
    return
  end
  if k == "grid" then r.ImGui_OpenPopup(ctx, "##grid"); return end
  if (k == "pt" or k == "line" or k == "lane") and h.L and h.L.e and h.L.e.item ~= S.item and not right then
    H.select(h.L.e.item)
  end
  -- Pointer on an event: Ctrl adds or removes it, Shift on a header takes the run from the
  -- selected one (Shift+drag on the audio stays a move without snap); a plain click on an
  -- unselected event selects it alone. A drag moves all selected events.
  local _, ctrl = H.mods()
  if (k == "head" or k == "body") and S.tool == "pointer" and (ctrl or (shift and k == "head")) then
    if ctrl then
      local on = not r.IsMediaItemSelected(h.e.item)
      r.SetMediaItemSelected(h.e.item, on)
      if on then S.item, S.take = h.e.item, h.e.take end
    else
      local a, b
      for i, e in ipairs(S.group) do
        if e.item == S.item then a = i end
        if e.item == h.e.item then b = i end
      end
      if a and b then
        for i = math.min(a, b), math.max(a, b) do r.SetMediaItemSelected(S.group[i].item, true) end
      end
      S.item, S.take = h.e.item, h.e.take
    end
    r.UpdateArrange()
    return
  end
  -- another event: the first click selects it (and moves the edit cursor there)
  if (k == "head" or k == "body") and h.e.item ~= S.item and S.tool ~= "knife" and S.tool ~= "time" then
    if not (S.tool == "pointer" and r.IsMediaItemSelected(h.e.item)) then H.select(h.e.item)
    else S.item, S.take = h.e.item, h.e.take end
    if S.tool == "pointer" then M.start_move(h.e) end
    return
  end
  if k == "gain" then
    if double then r.SetMediaItemTakeInfo_Value(S.take, "D_VOL", 1); H.undo("clip gain"); return end
    M.kind, M.vol0 = "gain", math.abs(K.vol)
    return
  end
  if k == "onset" then
    S.show_sm = true
    local tt = K.to_take(h.t)
    if tt > 0 and tt < K.len * K.rate then
      local idx = r.SetTakeStretchMarker(S.take, -1, tt)
      if idx and idx >= 0 then M.kind, M.idx = "sm", idx end
    end
    return
  end
  if double and k == "head" and S.show_sm then M.add_marker(mx, shift); return end
  if double and k == "bar" then K.fit(); return end
  if k == "body" or k == "head" then
    local t = V.snap(V.T(mx), shift)
    if S.tool == "knife" then
      if r.SplitMediaItem(h.e.item, t) then H.undo("split") end
      return
    elseif S.tool == "draw" and k == "body" and V.cliplanes and V.cliplanes[h.e.item] then
      M.add_point(mx, my, shift, V.cliplanes[h.e.item])
      return
    elseif S.tool == "stretch" and k == "body" then
      S.show_sm = true
      M.add_marker(mx, shift)
      return
    elseif S.tool == "pointer" then
      M.start_move(h.e)
      return
    end
    k = "time"
  end
  if k == "lane" then
    if S.tool == "erase" or S.tool == "knife" or S.tool == "time" then M.kind = "time"; return end
    k = "line"
  end
  if k == "split" then M.kind = "split"; return end
  if k == "line" then M.add_point(mx, my, shift, h.L); return end
  if k == "ruler" or k == "bar" then k = "time" end
  M.kind = k
  if k == "scroll" and V.over then           -- a click centres the view there, a drag moves it
    local o, span = V.over, S.ve - S.vs
    S.vs = o.lo + (mx - o.x) / o.w * o.full - span / 2
    S.ve = S.vs + span
    V.clamp()
    M.vs0 = S.vs
  end
end

function M.drag(mx, my, shift)
  H.tick = H.tick + 1               -- REAPER counts no change until the undo point: redraw now
  local k = M.kind
  if math.abs(mx - M.x0) > 3 or math.abs(my - M.y0) > 3 then M.moved = true end
  local t = V.snap(V.T(mx), shift)
  if k == "time" then
    if M.moved then r.GetSet_LoopTimeRange2(0, true, false, math.min(M.t0, t), math.max(M.t0, t), false) end
  elseif k == "scroll" then
    local o, span = V.over, S.ve - S.vs
    if not o then return end
    S.vs = M.vs0 + (mx - M.x0) / o.w * o.full
    S.ve = S.vs + span
    V.clamp()
  elseif k == "seg" and M.L and M.L.env then
    local L, env = M.L, M.L.env
    local mode = r.GetEnvelopeScalingMode(env)
    local dy = my - M.y0
    dy = H.clamp(dy, L.et - math.min(M.ya, M.yb), L.eb - math.max(M.ya, M.yb))    -- both stay in the lane
    for j, y in ipairs({ M.ya, M.yb }) do
      local i = M.idx + j - 1
      local _, t, _, shape, tension, sel = r.GetEnvelopePoint(env, i)
      r.SetEnvelopePoint(env, i, t, E.value(L, y + dy, mode), shape, tension, sel, true)
    end
  elseif k == "curve" and M.L and M.L.env then
    local env = M.L.env
    local _, t0, v0, _, _, sel = r.GetEnvelopePoint(env, M.idx)
    local tension = H.clamp(M.tens0 + (M.y0 - my) / 80 * M.cdir, -1, 1)
    r.SetEnvelopePoint(env, M.idx, t0, v0, 5, tension, sel, true)
  elseif k == "edge_l" then        -- shown while dragging, done by REAPER on release
    local e = M.e
    M.edge_t = H.clamp(t, 0, e.pos + e.len - 0.005)
  elseif k == "edge_r" then        -- the end: just the length, at once
    local e = M.e
    r.SetMediaItemInfo_Value(e.item, "D_LENGTH", math.max(0.005, t - e.pos))
  elseif k == "slip" then          -- the audio slides inside the event (no snap); shown only
    M.dt = V.T(mx) - V.T(M.x0)
  elseif k == "split" then
    local a = V.area
    if a then S.lane_frac = H.clamp((a[2] - my) / (a[2] - a[1]), 0.12, 0.75) end
  elseif k == "move" then
    if M.moved then
      local raw = M.pos0 + (V.T(mx) - V.T(M.x0))
      local d = V.snap(raw, shift) - M.pos0
      for _, m in ipairs(M.movers or {}) do d = math.max(d, -m[2]) end     -- none before 0
      for _, m in ipairs(M.movers or { { S.item, M.pos0 } }) do
        if r.ValidatePtr2(0, m[1], "MediaItem*") then r.SetMediaItemInfo_Value(m[1], "D_POSITION", m[2] + d) end
      end
    end
  elseif k == "fin" then
    r.SetMediaItemInfo_Value(S.item, "D_FADEINLEN_AUTO", 0)
    r.SetMediaItemInfo_Value(S.item, "D_FADEINLEN", H.clamp(t - K.pos, 0, K.len))
  elseif k == "fout" then
    r.SetMediaItemInfo_Value(S.item, "D_FADEOUTLEN_AUTO", 0)
    r.SetMediaItemInfo_Value(S.item, "D_FADEOUTLEN", H.clamp(K.pos + K.len - t, 0, K.len))
  elseif k == "gain" then
    local db0 = 20 * math.log(math.max(M.vol0, 0.0000001), 10)
    local db = H.clamp(db0 - (my - M.y0) * (shift and 0.02 or 0.1), -60, 24)
    r.SetMediaItemTakeInfo_Value(S.take, "D_VOL", 10 ^ (db / 20))
  elseif k == "pt" and M.L and M.L.env then
    local L, env = M.L, M.L.env
    local n = r.CountEnvelopePoints(env)
    local lo = M.idx > 0 and select(2, r.GetEnvelopePoint(env, M.idx - 1)) or 0
    local hi = M.idx < n - 1 and select(2, r.GetEnvelopePoint(env, M.idx + 1)) or L.e.len * L.e.rate
    local tt = H.clamp(E.to_take(L, t), lo, hi)
    local _, _, _, shape, tension, sel = r.GetEnvelopePoint(env, M.idx)
    r.SetEnvelopePoint(env, M.idx, tt, E.value(L, my, r.GetEnvelopeScalingMode(env)), shape, tension, sel, true)
    r.Envelope_SortPoints(env)
  elseif k == "sm" then
    local n = r.GetTakeNumStretchMarkers(S.take)
    local lo = M.idx > 0 and select(2, r.GetTakeStretchMarker(S.take, M.idx - 1)) + 0.001 or 0
    local hi = M.idx < n - 1 and select(2, r.GetTakeStretchMarker(S.take, M.idx + 1)) - 0.001 or K.len * K.rate
    r.SetTakeStretchMarker(S.take, M.idx, H.clamp(K.to_take(t), lo, hi))
  end
  r.UpdateArrange()
end

function M.release()
  local k = M.kind
  M.kind = nil
  if k == "time" and not M.moved then
    r.SetEditCurPos(M.t0, false, false)
    r.GetSet_LoopTimeRange2(0, true, false, 0, 0, false)
  elseif k == "move" then
    if M.moved then H.undo(#(M.movers or {}) > 1 and "move events" or "move event")
    else
      r.SetEditCurPos(M.t0, false, false)
      if #(M.movers or {}) > 1 and M.grab then H.select(M.grab) end    -- a click: that one alone
    end
  elseif k == "fin" or k == "fout" then H.undo("fade")
  elseif k == "gain" then H.undo("clip gain")
  elseif k == "pt" then H.undo((M.L and M.L.kind.name:lower() or "take") .. " envelope")
  elseif k == "sm" then H.undo("stretch marker")
  elseif k == "split" then save()
  elseif k == "curve" and M.moved then H.undo("envelope curve")
  elseif k == "seg" and M.moved then H.undo("envelope part")
  elseif k == "edge_l" and M.moved and M.edge_t then
    -- REAPER's own left trim (nudge the left edge to a time): it keeps fades, take
    -- envelopes and stretch markers with the audio
    H.select(M.e.item)
    r.Undo_BeginBlock2(0)              -- one named step, whatever the nudge records itself
    r.ApplyNudge(0, 1, 2, 1, M.edge_t, false, 0)
    r.Undo_EndBlock2(0, "Clip Edit: trim event start", -1)
    P.cache = {}
  elseif k == "edge_r" and M.moved then H.undo("trim event end")
  elseif k == "slip" and M.moved and M.dt and M.dt ~= 0 then
    -- REAPER's own content nudge, as its Alt+drag: it takes stretch markers along (setting
    -- the take's start offset alone does nothing once a take has stretch markers)
    H.select(M.e.item)
    r.Undo_BeginBlock2(0)
    r.ApplyNudge(0, 0, 4, 1, math.abs(M.dt), M.dt < 0, 0)
    r.Undo_EndBlock2(0, "Clip Edit: slip event", -1)
    P.cache = {}
  end
end

function M.wheel(mx)
  local v, hz = r.ImGui_GetMouseWheel(ctx)
  if v == 0 and hz == 0 then return end
  local _, ctrl, alt = H.mods()
  if ctrl and v ~= 0 then V.zoom(0.8 ^ v, V.T(mx))
  elseif alt and v ~= 0 then S.vzoom = H.clamp(S.vzoom * 1.25 ^ v, 0.25, 16)
  else V.scroll(-(v + hz) * (S.ve - S.vs) * 0.1) end
end

-- Slice: split the selected event at each of its transients (from the last one back, so
-- the item we hold stays the first slice). Slices closer than 20 ms to an edge are skipped.
function M.slice()
  local list = O.get()
  if #list == 0 then return end
  local item = S.item
  r.Undo_BeginBlock2(0)
  r.PreventUIRefresh(1)
  for i = #list, 1, -1 do
    local t = list[i]
    if t > K.pos + 0.02 and t < K.pos + K.len - 0.02 then r.SplitMediaItem(item, t) end
  end
  r.PreventUIRefresh(-1)
  r.Undo_EndBlock2(0, "Clip Edit: slice at transients", -1)
  r.UpdateArrange()
end

-- what quantize works on: the time selection when there is one, else everything
function M.in_range(t)
  local a, b = H.time_sel()
  return not a or (t >= a - 0.0001 and t < b)
end
function M.toward_grid(t)
  return t + (r.SnapToGrid(0, t) - t) * S.qstr / 100
end

-- Quantize the clip's events: each start moves toward the nearest grid line
function M.quantize_events()
  r.Undo_BeginBlock2(0)
  for _, e in ipairs(S.group) do
    if M.in_range(e.pos) then r.SetMediaItemInfo_Value(e.item, "D_POSITION", math.max(0, M.toward_grid(e.pos))) end
  end
  r.Undo_EndBlock2(0, "Clip Edit: quantize events", -1)
  r.UpdateArrange()
end

-- Quantize the selected event's stretch markers: each moves toward the grid and the audio
-- stretches along. A marker that would pass its neighbour stays where it is.
function M.quantize_markers()
  local take = S.take
  local n = r.GetTakeNumStretchMarkers(take)
  if n == 0 then return end
  local new = {}
  for i = 0, n - 1 do
    local _, pos = r.GetTakeStretchMarker(take, i)
    local t = K.from_take(pos)
    new[i] = { old = pos, pos = M.in_range(t) and K.to_take(M.toward_grid(t)) or pos }
  end
  r.Undo_BeginBlock2(0)
  for i = 0, n - 1 do
    local lo = i > 0 and new[i - 1].pos + 0.001 or -math.huge
    local hi = i < n - 1 and new[i + 1].pos - 0.001 or math.huge
    if new[i].pos < lo or new[i].pos > hi then new[i].pos = new[i].old end
    if new[i].pos ~= new[i].old then r.SetTakeStretchMarker(take, i, new[i].pos) end
  end
  r.Undo_EndBlock2(0, "Clip Edit: quantize stretch markers", -1)
  r.UpdateArrange()
end

-- a move: the grabbed event and every other selected event of the clip, by one distance
function M.start_move(e)
  M.kind, M.pos0, M.grab = "move", e.pos, e.item
  M.movers = {}
  for _, g in ipairs(S.group) do
    if g.item == e.item or r.IsMediaItemSelected(g.item) then M.movers[#M.movers + 1] = { g.item, g.pos } end
  end
end

-- right-click: the edits
function M.menu()
  if not r.ImGui_BeginPopup(ctx, "##menu") then return end
  local a = H.time_sel()
  if r.ImGui_MenuItem(ctx, a and "Split at time selection" or "Split at edit cursor", "S") then
    H.run(a and CMD.split_sel or CMD.split_cur)
  end
  if r.ImGui_MenuItem(ctx, "Trim to time selection", nil, false, a ~= nil) then H.run(CMD.trim) end
  if r.ImGui_MenuItem(ctx, "Reverse") then H.run(CMD.reverse) end
  if r.ImGui_MenuItem(ctx, "Normalize") then H.run(CMD.normalize) end
  r.ImGui_Separator(ctx)
  if r.ImGui_MenuItem(ctx, "Slice at transients") then M.slice() end
  if r.ImGui_MenuItem(ctx, "Stretch markers on transients") then
    O.get()
    local have = {}
    for i = 0, r.GetTakeNumStretchMarkers(S.take) - 1 do have[#have + 1] = select(2, r.GetTakeStretchMarker(S.take, i)) end
    for _, t in ipairs(O.list) do
      local tt, near = K.to_take(t), false
      for _, p in ipairs(have) do if math.abs(p - tt) < 0.01 then near = true end end
      if not near and tt > 0 and tt < K.len * K.rate then r.SetTakeStretchMarker(S.take, -1, tt) end
    end
    S.show_sm = true
    H.undo("stretch markers on transients")
  end
  if r.ImGui_BeginMenu(ctx, "Transient sensitivity") then
    for _, v in ipairs({ { "low", "Low" }, { "mid", "Medium" }, { "high", "High" } }) do
      if r.ImGui_MenuItem(ctx, v[2], nil, S.sens == v[1]) then
        S.sens = v[1]; O.sens = ({ low = 0.25, mid = 0.5, high = 0.75 })[v[1]]; save()
      end
    end
    r.ImGui_EndMenu(ctx)
  end
  r.ImGui_Separator(ctx)
  local where = a and " (time selection)" or ""
  if r.ImGui_MenuItem(ctx, "Quantize events" .. where, nil, false, #S.group > 0) then M.quantize_events() end
  if r.ImGui_MenuItem(ctx, "Quantize stretch markers" .. where, nil, false, r.GetTakeNumStretchMarkers(S.take) > 0) then
    M.quantize_markers()
  end
  if r.ImGui_BeginMenu(ctx, "Quantize strength: " .. S.qstr .. "%") then
    for _, v in ipairs({ 25, 50, 75, 100 }) do
      if r.ImGui_MenuItem(ctx, v .. "%", nil, S.qstr == v) then S.qstr = v; save() end
    end
    r.ImGui_EndMenu(ctx)
  end
  r.ImGui_Separator(ctx)
  if r.ImGui_MenuItem(ctx, "Remove all stretch markers", nil, false, r.GetTakeNumStretchMarkers(S.take) > 0) then
    r.DeleteTakeStretchMarkers(S.take, 0, r.GetTakeNumStretchMarkers(S.take))
    H.undo("remove stretch markers")
  end
  if r.ImGui_MenuItem(ctx, "Remove volume envelope points", nil, false, K.env ~= nil) then
    r.DeleteEnvelopePointRange(K.env, -1, K.len * K.rate + 1)
    H.undo("clear volume envelope")
  end
  r.ImGui_Separator(ctx)
  for i, name in ipairs(H.FADE_NAMES) do
    if r.ImGui_MenuItem(ctx, "Fades: " .. name, nil, K.fin_shape == i - 1 and K.fout_shape == i - 1) then
      r.SetMediaItemInfo_Value(S.item, "C_FADEINSHAPE", i - 1)
      r.SetMediaItemInfo_Value(S.item, "C_FADEOUTSHAPE", i - 1)
      H.undo("fade shape")
    end
  end
  r.ImGui_EndPopup(ctx)
end

---------------------------------------------------------------- the panel's parts
local D = {}
-- the selected event is read every frame (the inspector may be changing it): put that
-- fresh copy in the clip's cached list, so its waveform follows while dragging
function D.fresh_active()
  for i, e in ipairs(S.group) do
    if e.item == S.item and K.e and K.e.item == S.item then S.group[i] = K.e end
  end
end
D.TIPS = { fin = "Fade in: drag (right-click: next shape)", fout = "Fade out: drag (right-click: next shape)",
  gain = "Event gain: drag up / down (Shift: fine, double-click: 0 dB)",
  sm = "Stretch marker: drag to stretch (Alt / right-click: delete)",
  grid = "Click: the grid",
  edge_l = "Drag: trim the event's start (Shift: no snap)", edge_r = "Drag: trim the event's end (Shift: no snap)",
  onset = "Transient: drag to make it a stretch marker and stretch",
  pt = "Envelope point: drag (Alt / right-click: delete)", line = "Click to add a point (Alt+drag: bend the curve, Alt+double-click: straight)",
  split = "Drag: lane height", seg = "Drag: move this part up / down", lane = "Click to add a point (right-click: choose the lanes)",
  bar = "Drag: time selection, double-click: show the whole clip" }

-- an envelope point's value, in a small box above it (inside the canvas)
function D.point_label(dl, L, i, cx, cw)
  local ok, _, v = r.GetEnvelopePoint(L.env, i)
  if not ok then return end
  local px, py
  for _, p in ipairs(V.env_pts or {}) do if p.L.env == L.env and p.i == i then px, py = p.x, p.y end end
  if not px then return end
  local text = L.kind.fmt(v, r.GetEnvelopeScalingMode(L.env))
  local tw, th = r.ImGui_CalcTextSize(ctx, text)
  local bx = H.clamp(px - tw / 2 - 4, cx + 2, cx + cw - tw - 10)
  local by = py - th - 12
  if by < L.y0 then by = py + 8 end            -- no room above: below the point
  r.ImGui_DrawList_AddRectFilled(dl, bx, by, bx + tw + 8, by + th + 2, C.field, 3)
  r.ImGui_DrawList_AddRect(dl, bx, by, bx + tw + 8, by + th + 2, C.env, 3)
  r.ImGui_DrawList_AddText(dl, bx + 4, by + 1, C.text, text)
end

-- the canvas: ruler, clip, overview; the mouse
function D.canvas(w, h)
  local x, y = r.ImGui_GetCursorScreenPos(ctx)
  if w < 40 or h < RULER_H + OVER_H + 40 then r.ImGui_Dummy(ctx, w, h); return end
  V.x, V.w = x, w
  local gkey = tostring(r.GetMediaItem_Track(S.item)) .. S.scope .. tostring(S.group[1] and S.group[1].item)
  if gkey ~= S.gkey then
    S.gkey = gkey
    P.cache, P.max = {}, {}
    K.fit()
  end
  if S.fit then K.fit(); S.fit = false end
  V.pps = w / (S.ve - S.vs)
  local ry1 = y + RULER_H
  local oy0 = y + h - OVER_H
  local wy0, wy1 = ry1 + 1, oy0 - 2

  r.ImGui_InvisibleButton(ctx, "##canvas", w, h,
    r.ImGui_ButtonFlags_MouseButtonLeft() | r.ImGui_ButtonFlags_MouseButtonRight())
  local hov = r.ImGui_IsItemHovered(ctx)
  local mx, my = r.ImGui_GetMousePos(ctx)
  local shift, _, alt = H.mods()
  if hov then
    local left, right = r.ImGui_IsMouseClicked(ctx, 0), r.ImGui_IsMouseClicked(ctx, 1)
    if left or right then
      M.press(M.hit(mx, my, ry1, oy0), mx, my, alt, shift, right, r.ImGui_IsMouseDoubleClicked(ctx, 0))
    end
    M.wheel(mx)
  end
  if M.kind then
    if r.ImGui_IsMouseDown(ctx, 0) then M.drag(mx, my, shift) else M.release() end
  end
  if not r.ValidatePtr2(0, S.item, "MediaItem*") then return end
  K.read()
  if M.kind ~= "move" then S.group = K.group_cached()    -- while moving, the clip holds still,
  else                                                      -- but its moving events are read anew
    local moving = {}
    for _, m in ipairs(M.movers or {}) do moving[m[1]] = true end
    for i, e in ipairs(S.group) do
      if moving[e.item] and r.ValidatePtr2(0, e.item, "MediaItem*") then S.group[i] = K.info(e.item) or e end
    end
  end
  D.fresh_active()
  if #S.group == 0 then S.group = { K.info(S.item) } end
  -- playing: when the play cursor runs off the right (or jumps back before the left), the
  -- view pages so it stands near the left again. Not while dragging; only inside the clip.
  if S.pfollow and not M.kind and r.GetPlayState() & 1 == 1 then
    local pp, span = r.GetPlayPosition(), S.ve - S.vs
    local lo, hi = V.range()
    if pp >= lo and pp <= hi and (pp > S.ve - span * 0.02 or pp < S.vs) then
      S.vs = pp - span * 0.05
      S.ve = S.vs + span
      V.clamp()
    end
  end
  V.pps = w / (S.ve - S.vs)
  -- the project's change count, plus our own drags (REAPER counts those only at the undo point)
  P.state = r.GetProjectStateChangeCount(0) .. "." .. H.tick
  M.menu()
  if D.open_lanes then r.ImGui_OpenPopup(ctx, "##lanes"); D.open_lanes = false end
  if r.ImGui_BeginPopup(ctx, "##grid") then
    local _, div = r.GetSetProjectGrid(0, false)
    for _, g in ipairs({ { "1/1", 1 }, { "1/2", 1 / 2 }, { "1/4", 1 / 4 }, { "1/8", 1 / 8 }, { "1/16", 1 / 16 },
      { "1/32", 1 / 32 }, { "1/64", 1 / 64 }, { "1/4 T", 1 / 6 }, { "1/8 T", 1 / 12 }, { "1/16 T", 1 / 24 } }) do
      if r.ImGui_MenuItem(ctx, g[1], nil, math.abs(div - g[2]) < 0.00001) then r.GetSetProjectGrid(0, true, g[2]) end
    end
    r.ImGui_Separator(ctx)
    if r.ImGui_MenuItem(ctx, "Snap", nil, S.snap) then S.snap = not S.snap; save() end
    r.ImGui_EndPopup(ctx)
  end
  if r.ImGui_BeginPopup(ctx, "##lanes") then
    for _, k in ipairs(E.ORDER) do
      if r.ImGui_MenuItem(ctx, E.KINDS[k].name, nil, S.lane and E.on(k)) then
        if not S.lane then S.lane, S.lanes = true, k; save() else E.toggle(k) end
      end
    end
    r.ImGui_EndPopup(ctx)
  end

  local dl = r.ImGui_GetWindowDrawList(ctx)
  r.ImGui_DrawList_PushClipRect(dl, x, y, x + w, y + h, true)
  r.ImGui_DrawList_AddRectFilled(dl, x, wy0, x + w, wy1, C.canvas)
  V.ruler(dl, x, y, w, wy0, wy1)
  O.hold = M.kind == "sm"
  Q.hold = M.kind == "slip"
  V.slip = M.kind == "slip" and M.e and { item = M.e.item, dt = M.dt or 0, sp = M.sp } or nil
  -- the lanes under the clip (as Bitwig's expression lanes): volume, pan, pitch
  local cy1 = wy1
  V.lane_top, V.lanes, V.area, V.env_pts = nil, {}, { wy0, wy1 }, {}
  local kinds = {}
  for _, k in ipairs(E.ORDER) do if E.on(k) then kinds[#kinds + 1] = k end end
  if S.lane and #kinds > 0 then
    local lh = H.clamp(math.floor((wy1 - wy0) * S.lane_frac), 26 * #kinds, math.max(26, wy1 - wy0 - 70))
    local ly0 = wy1 - lh
    cy1 = ly0 - 2
    V.lane_top = ly0
    r.ImGui_DrawList_AddRectFilled(dl, x, ly0, x + w, wy1, C.sub)
    local each = lh / #kinds
    local named = not H.inspector_open()
    for i, k in ipairs(kinds) do
      local L = E.lane(k, ly0 + (i - 1) * each, ly0 + i * each, 5)
      V.lanes[i] = L
      if i > 1 then r.ImGui_DrawList_AddLine(dl, x, L.y0, x + w, L.y0, C.split, 1) end
      local yz = L.eb - L.kind.zero() * (L.eb - L.et)
      r.ImGui_DrawList_AddLine(dl, x, yz, x + w, yz, C.mid)
      L.events = {}
      for _, ev in ipairs(S.group) do
        local Le = E.lane(k, L.y0, L.y1, 5, ev)
        L.events[ev.item] = Le
        if not Le.env then     -- none yet: a flat line, a click makes the envelope
          r.ImGui_DrawList_AddLine(dl, math.max(V.X(ev.pos), x), yz, math.min(V.X(ev.pos + ev.len), x + w), yz, C.dim, 1)
        end
      end
      if named then r.ImGui_DrawList_AddText(dl, x + 4, L.y0 + 2, C.dim, L.kind.name) end
      L.ticks = E.ticks(L)
      for _, tk in ipairs(L.ticks) do
        if not tk.zero then r.ImGui_DrawList_AddLine(dl, x, tk.y, x + w, tk.y, C.line) end
        if named then
          local tw = r.ImGui_CalcTextSize(ctx, tk.text)
          r.ImGui_DrawList_AddText(dl, x + w - tw - 4, H.clamp(tk.y - 7, L.y0 + 1, L.y1 - 14), C.dim, tk.text)
        end
      end
      for _, ev in ipairs(S.group) do            -- the selected event's line last, on top
        if ev.item ~= S.item then V.env(dl, L.events[ev.item], false) end
      end
      if L.events[S.item] then V.env(dl, L.events[S.item], true) end
    end
    r.ImGui_DrawList_AddRectFilled(dl, x, ly0 - 2, x + w, ly0 + 1, C.split)
  end
  V.clip(dl, wy0 + 1, cy1)

  local a, b = H.time_sel()
  if a then
    local xa, xb = V.X(a), V.X(b)
    r.ImGui_DrawList_AddRectFilled(dl, xa, wy0, xb, wy1, C.sel)
    r.ImGui_DrawList_AddRectFilled(dl, xa, ry1 - 4, xb, ry1, C.accent)
    r.ImGui_DrawList_AddLine(dl, xa, wy0, xa, wy1, C.accent)
    r.ImGui_DrawList_AddLine(dl, xb, wy0, xb, wy1, C.accent)
  end
  local cur = V.X(r.GetCursorPosition())
  r.ImGui_DrawList_AddLine(dl, cur, y, cur, wy1, C.text)
  r.ImGui_DrawList_AddTriangleFilled(dl, cur - 5, y, cur + 5, y, cur, y + 6, C.text)
  if r.GetPlayState() & 1 == 1 then
    local pp = V.X(r.GetPlayPosition())
    r.ImGui_DrawList_AddLine(dl, pp, y, pp, wy1, C.accent, 1.5)
  end
  -- the left trim while dragging: the new start, the part that goes darkened
  if M.kind == "edge_l" and M.edge_t then
    local ex, sx = V.X(M.edge_t), V.X(M.e.pos)
    if ex > sx then r.ImGui_DrawList_AddRectFilled(dl, sx, wy0, ex, V.lane_top or wy1, 0x000000B0) end
    r.ImGui_DrawList_AddLine(dl, ex, wy0, ex, V.lane_top or wy1, C.accent, 2)
  end
  -- the knife's line where it would cut
  if hov and S.tool == "knife" and my > wy0 and my < wy1 then
    local kx = V.X(V.snap(V.T(mx), shift))
    r.ImGui_DrawList_AddLine(dl, kx, wy0, kx, wy1, C.accent, 1)
  end
  V.overview(dl, x, oy0, w, OVER_H)
  r.ImGui_DrawList_PopClipRect(dl)

  local hh = hov and not M.kind and M.hit(mx, my, ry1, oy0)
  -- the value of the point under the mouse or being dragged, in a label beside it
  local lab = M.kind == "pt" and M.L and { L = M.L, i = M.idx } or (hh and hh.kind == "pt" and { L = hh.L, i = hh.idx })
  if lab and lab.L and lab.L.env then D.point_label(dl, lab.L, lab.i, x, w) end
  -- a part about to move (or moving): drawn thick, its two values shown
  local sg = M.kind == "seg" and M.L and { L = M.L, i = M.idx } or (hh and hh.kind == "seg" and { L = hh.L, i = hh.idx })
  if sg and sg.L.env then
    local a, b
    for _, p in ipairs(V.env_pts or {}) do
      if p.L.env == sg.L.env and p.i == sg.i then a = p end
      if p.L.env == sg.L.env and p.i == sg.i + 1 then b = p end
    end
    if a and b then r.ImGui_DrawList_AddLine(dl, a.x, a.y, b.x, b.y, C.env, 4) end
    if M.kind == "seg" then
      D.point_label(dl, sg.L, sg.i, x, w)
      D.point_label(dl, sg.L, sg.i + 1, x, w)
    end
  end
  if hh then
    if D.TIPS[hh.kind] and hh.kind ~= "pt" then r.ImGui_SetTooltip(ctx, D.TIPS[hh.kind]) end
    local cursor
    if hh.kind == "fin" or hh.kind == "fout" or hh.kind == "sm" or hh.kind == "onset" or hh.kind == "edge_l"
      or hh.kind == "edge_r" then cursor = r.ImGui_MouseCursor_ResizeEW()
    elseif hh.kind == "gain" or hh.kind == "split" then cursor = r.ImGui_MouseCursor_ResizeNS()
    elseif (hh.kind == "line" and alt) or hh.kind == "seg" then cursor = r.ImGui_MouseCursor_ResizeNS()
    elseif hh.kind == "pt" or hh.kind == "line" then cursor = r.ImGui_MouseCursor_Hand()
    elseif (hh.kind == "body" or hh.kind == "head") and S.tool == "pointer" then cursor = r.ImGui_MouseCursor_ResizeAll()
    elseif S.tool == "time" or hh.kind == "time" or hh.kind == "ruler" then cursor = r.ImGui_MouseCursor_TextInput() end
    if cursor then r.ImGui_SetMouseCursor(ctx, cursor) end
  end
end

-- the tools, upright at the right of the canvas (as Bitwig)
D.TOOLS = {
  { "pointer", "Pointer: select and move events; drag an edge to trim, Alt+drag to slip the audio" }, { "time", "Time selection" },
  { "draw", "Draw: volume envelope points" }, { "erase", "Erase: envelope points and stretch markers" },
  { "knife", "Knife: split an event" }, false,
  { "stretch", "Stretch: add stretch markers; drag a transient (dashed line) to stretch from it" }, false,
}
function D.tools()
  local function gap() r.ImGui_Dummy(ctx, 0, 10) end
  for _, t in ipairs(D.TOOLS) do
    if not t then gap()
    elseif U.icon("t" .. t[1], ICON[t[1]], S.tool == t[1], 24, 22, t[2]) then S.tool = t[1]; save() end
  end
  if U.icon("senv", ICON.env, S.show_env, 24, 22, "Show the take volume envelope (on the clip when the lanes are off)") then S.show_env = not S.show_env; save() end
  if U.icon("ssm", ICON.markers, S.show_sm, 24, 22, "Show the stretch markers") then S.show_sm = not S.show_sm; save() end
  gap()
  if U.icon("snap", ICON.snap, S.snap, 24, 22, "Snap to REAPER's grid (hold Shift for free)") then S.snap = not S.snap; save() end
  if U.icon("follow", ICON.follow, S.follow, 24, 22, "Follow the selected item (off: keep this one)") then S.follow = not S.follow end
  if U.icon("pfollow", ICON.playfollow, S.pfollow, 24, 22, "Follow the play cursor: the view pages along while playing") then
    S.pfollow = not S.pfollow; save()
  end
  if U.icon("fit", ICON.fit, false, 24, 22, "Show the whole clip") then K.fit() end
end

-- Clip | Track: the touching items, or all of the track's
function D.scope_keys(w)
  local pick = U.tabs("scope", { { "clip", "Clip", "The clip: the items that touch this one" },
    { "track", "Track", "All audio items on the track" } }, S.scope, w, ROW_H + 2)
  if pick and pick ~= S.scope then S.scope = pick; save() end
end

-- the lane key at the foot of the left column (as Bitwig); in the strip, the lane's name
-- stands next to the lane
function D.lane_foot(strip)
  local wy = select(2, r.ImGui_GetWindowPos(ctx))
  local wh = r.ImGui_GetWindowHeight(ctx)
  local cy = r.ImGui_GetCursorPosY(ctx)
  local dl = r.ImGui_GetWindowDrawList(ctx)
  local x = r.ImGui_GetCursorScreenPos(ctx)
  -- each lane's name at its top left, its scale at the right (as Bitwig)
  local cw = r.ImGui_GetContentRegionAvail(ctx)
  for _, L in ipairs(strip and V.lanes or {}) do
    if L.y0 - wy > cy + 2 and L.y0 + 30 < wy + wh - 24 then
      r.ImGui_PushFont(ctx, font_bold, 12)
      r.ImGui_DrawList_AddText(dl, x + 2, L.y0 + 3, C.text, L.kind.name)
      r.ImGui_PopFont(ctx)
      r.ImGui_DrawList_AddText(dl, x + 2, L.y0 + 17, C.dim, "Take")
      for _, tk in ipairs(L.ticks or {}) do
        local tw = r.ImGui_CalcTextSize(ctx, tk.text)
        r.ImGui_DrawList_AddText(dl, x + cw - tw - 2, H.clamp(tk.y - 7, L.y0 + 1, L.y1 - 14), C.dim, tk.text)
      end
      r.ImGui_DrawList_AddLine(dl, x - 8, L.y0, x + cw + 8, L.y0, L == V.lanes[1] and C.split or C.line,
        L == V.lanes[1] and 3 or 1)
    end
  end
  r.ImGui_SetCursorPosY(ctx, math.max(cy + 4, wh - 24))
  if U.icon("lane", ICON.lane, S.lane, 26, 20, "Lanes under the clip (right-click: Volume, Pan, Pitch)") then
    S.lane = not S.lane; save()
  end
  if r.ImGui_IsItemClicked(ctx, 1) then D.open_lanes = true end
end

-- the narrow strip (with the inspector open): Clip | Track, the names
function D.strip()
  D.scope_keys((r.ImGui_GetContentRegionAvail(ctx)))
  r.ImGui_Dummy(ctx, 0, 3)
  local tr = r.GetMediaItem_Track(S.item)
  local first = S.group[1] or K
  r.ImGui_PushFont(ctx, font_bold, 12)
  r.ImGui_Text(ctx, first.name ~= "" and first.name or "Clip")
  r.ImGui_PopFont(ctx)
  U.text_col(C.dim, (select(2, r.GetTrackName(tr))):upper())
  local dl = r.ImGui_GetWindowDrawList(ctx)
  local x, y = r.ImGui_GetCursorScreenPos(ctx)
  local w = r.ImGui_GetContentRegionAvail(ctx)
  r.ImGui_DrawList_AddRectFilled(dl, x, y + 2, x + w, y + 5, H.shade(K.rgb, 0))
  r.ImGui_Dummy(ctx, w, 6)
  if #S.group > 1 then U.text_col(C.dim, #S.group .. " events") end
  D.lane_foot(true)
end

-- the full column (without the inspector): the selected event's values
function D.left()
  local item, take = S.item, S.take
  D.scope_keys((r.ImGui_GetContentRegionAvail(ctx)))
  local dl = r.ImGui_GetWindowDrawList(ctx)
  local x, y = r.ImGui_GetCursorScreenPos(ctx)
  r.ImGui_DrawList_AddRectFilled(dl, x + 2, y + 3, x + 14, y + 15, H.shade(K.rgb, 0))
  -- the lane key at the right of the name row (the column is too full for a foot)
  local cw = r.ImGui_GetContentRegionAvail(ctx)
  r.ImGui_SetCursorScreenPos(ctx, x + cw - 26, y)
  if U.icon("lane", ICON.lane, S.lane, 26, 18, "Lanes under the clip (right-click: Volume, Pan, Pitch)") then
    S.lane = not S.lane; save()
  end
  if r.ImGui_IsItemClicked(ctx, 1) then D.open_lanes = true end
  r.ImGui_SetCursorScreenPos(ctx, x + 20, y + 1)
  r.ImGui_PushClipRect(ctx, x + 20, y, x + cw - 30, y + 20, true)
  r.ImGui_Text(ctx, K.name ~= "" and K.name or "(no name)")
  r.ImGui_PopClipRect(ctx)
  U.sep()

  U.row("Gain", function()
    local a = math.abs(K.vol)
    local t0 = a < 0.0000001 and 0 or r.DB2SLIDER(20 * math.log(a, 10)) / 1000
    local t, moved, done = U.vbox("gain", t0, H.amp_db(a), { default = r.DB2SLIDER(0) / 1000,
      parse = function(s) local v = H.num(s); return v and r.DB2SLIDER(v) / 1000 end })
    if moved then r.SetMediaItemTakeInfo_Value(take, "D_VOL", t <= 0 and 0 or 10 ^ (r.SLIDER2DB(t * 1000) / 20)) end
    if done then H.undo("clip gain") end
  end)
  U.row("Pitch", function()
    local p = r.GetMediaItemTakeInfo_Value(take, "D_PITCH")
    local t, moved, done = U.vbox("pitch", (p + 24) / 48, string.format("%+.2f st", p), { default = 0.5,
      parse = function(s) local v = H.num(s); return v and (v + 24) / 48 end })
    if moved then
      local st = t * 48 - 24
      if not H.mods() and not done then st = math.floor(st + 0.5) end
      r.SetMediaItemTakeInfo_Value(take, "D_PITCH", st)
    end
    if done then H.undo("clip pitch") end
  end)
  U.row("Rate", function()
    local LO, SPAN = 0.25, math.log(16)
    local t, moved, done = U.vbox("rate", math.log(K.rate / LO) / SPAN, string.format("%.3fx", K.rate), {
      default = math.log(1 / LO) / SPAN,
      parse = function(s) local v = H.num(s); return v and v > 0 and math.log(v / LO) / SPAN end })
    if moved then
      -- as REAPER: the source's span stays, the item gets shorter / longer
      local nr = LO * math.exp(t * SPAN)
      r.SetMediaItemTakeInfo_Value(take, "D_PLAYRATE", nr)
      r.SetMediaItemInfo_Value(item, "D_LENGTH", K.len * K.rate / nr)
    end
    if done then H.undo("clip rate") end
  end)
  -- the stretch algorithm and its variant (as the inspector's Stretch / Mode)
  local pm = math.floor(r.GetMediaItemTakeInfo_Value(take, "I_PITCHMODE"))
  local shifter, sub = pm >= 0 and (pm >> 16) or -1, pm >= 0 and (pm & 0xFFFF) or 0
  U.row("Stretch", function(w)
    local cur = "Project default"
    for _, sh in ipairs(H.shifters()) do if sh[1] == shifter then cur = sh[2] end end
    U.combo("pmode", cur, w, function()
      if r.ImGui_Selectable(ctx, "Project default", shifter < 0) then H.set_pitchmode(-1) end
      for _, sh in ipairs(H.shifters()) do
        if r.ImGui_Selectable(ctx, sh[2] .. "##pm" .. sh[1], sh[1] == shifter) then H.set_pitchmode(sh[1] << 16) end
      end
    end)
  end)
  local subs = shifter >= 0 and H.submodes(shifter) or {}
  if #subs > 1 then
    U.row("Mode", function(w)
      U.combo("psub", subs[sub + 1] or "?", w, function()
        for i, name in ipairs(subs) do
          if r.ImGui_Selectable(ctx, name .. "##ps" .. i, i - 1 == sub) then H.set_pitchmode((shifter << 16) | (i - 1)) end
        end
      end)
    end)
  end
  local fmax = math.max(0.001, math.min(K.len, 10))
  for _, f in ipairs({ { "Fade in", "fin", "D_FADEINLEN" }, { "Fade out", "fout", "D_FADEOUTLEN" } }) do
    U.row(f[1], function()
      local v = K[f[2]]
      local text = v < 1 and string.format("%.0f ms", v * 1000) or string.format("%.2f s", v)
      local t, moved, done = U.vbox(f[2], math.min(1, v / fmax), text, { default = 0,
        parse = function(s)
          local n = H.num(s)
          if not n then return nil end
          return ((s:lower():find("ms") or not s:lower():find("s")) and n / 1000 or n) / fmax
        end })
      if moved then
        r.SetMediaItemInfo_Value(item, f[3] .. "_AUTO", 0)
        r.SetMediaItemInfo_Value(item, f[3], t * fmax)
      end
      if done then H.undo(f[1]:lower()) end
    end)
  end
  U.sep()

  local half = (r.ImGui_GetContentRegionAvail(ctx) - 2) / 2
  local loop = r.GetMediaItemInfo_Value(item, "B_LOOPSRC") ~= 0
  local pp = r.GetMediaItemTakeInfo_Value(take, "B_PPITCH") ~= 0
  if U.key("loop", "Loop", loop, half, ROW_H, "Loop the source") then
    r.SetMediaItemInfo_Value(item, "B_LOOPSRC", loop and 0 or 1); H.undo("clip loop")
  end
  r.ImGui_SameLine(ctx, 0, 2)
  if U.key("mute", "Mute", K.mute, half, ROW_H, "Mute the event") then
    r.SetMediaItemInfo_Value(item, "B_MUTE", K.mute and 0 or 1); H.undo("clip mute")
  end
  if U.key("ppitch", "Keep pitch", pp, half, ROW_H, "Keep the pitch when the rate changes") then
    r.SetMediaItemTakeInfo_Value(take, "B_PPITCH", pp and 0 or 1); H.undo("preserve pitch")
  end
  r.ImGui_SameLine(ctx, 0, 2)
  if U.key("lrev", "Reverse", K.reversed, half, ROW_H, "Reverse the event") then H.run(CMD.reverse) end
  U.sep()

  r.ImGui_PushFont(ctx, font_bold, 11)
  U.text_col(C.dim, "SOURCE")
  r.ImGui_PopFont(ctx)
  if K.src then
    local s = K.src
    while r.GetMediaSourceParent(s) do s = r.GetMediaSourceParent(s) end
    local file = r.GetMediaSourceFileName(s, "")
    U.text_col(C.dim, file:match("([^\\/]+)$") or file)
    if r.ImGui_IsItemHovered(ctx) and file ~= "" then r.ImGui_SetTooltip(ctx, file) end
    U.text_col(C.dim, string.format("%.1f kHz, %d ch", r.GetMediaSourceSampleRate(s) / 1000, r.GetMediaSourceNumChannels(s)))
  end
  U.text_col(C.dim, "Pos " .. r.format_timestr_pos(K.pos, "", 2) .. "   Len " .. r.format_timestr_len(K.len, "", K.pos, 2))
end

-- keys REAPER would get if the panel did not have the focus
function D.keys()
  if not r.ImGui_IsWindowFocused(ctx, r.ImGui_FocusedFlags_RootAndChildWindows()) then return end
  if S.edit.id or r.ImGui_IsAnyItemActive(ctx) then return end
  local shift, ctrl = H.mods()
  if r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_Space(), false) then r.Main_OnCommand(CMD.play, 0) end
  if S.take and not ctrl and r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_S(), false) then
    H.run(H.time_sel() and CMD.split_sel or CMD.split_cur)
  end
  if S.take and (r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_Delete(), false)
    or r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_Backspace(), false)) then H.run(CMD.remove) end
  if S.take and ctrl and r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_D(), false) then H.run(CMD.duplicate) end
  if ctrl and r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_Z(), false) then
    r.Main_OnCommand(shift and CMD.redo or CMD.undo, 0)
  end
end

function D.empty(text)
  local w, h = r.ImGui_GetContentRegionAvail(ctx)
  local tw, th = r.ImGui_CalcTextSize(ctx, text)
  local x, y = r.ImGui_GetCursorPos(ctx)
  r.ImGui_SetCursorPos(ctx, x + math.max(0, (w - tw) / 2), y + math.max(0, (h - th) / 2))
  U.text_col(C.label, text)
end

---------------------------------------------------------------- the window
local STYLE = {
  { r.ImGui_Col_WindowBg, C.bg }, { r.ImGui_Col_ChildBg, 0x00000000 }, { r.ImGui_Col_Text, C.text },
  { r.ImGui_Col_Border, C.line }, { r.ImGui_Col_TitleBg, 0x161616FF }, { r.ImGui_Col_TitleBgActive, 0x262626FF },
  { r.ImGui_Col_FrameBg, C.field }, { r.ImGui_Col_FrameBgHovered, 0x1A1A1AFF }, { r.ImGui_Col_FrameBgActive, 0x222222FF },
  { r.ImGui_Col_Header, C.fill }, { r.ImGui_Col_HeaderHovered, 0x2A2A2AFF }, { r.ImGui_Col_HeaderActive, 0x333333FF },
  { r.ImGui_Col_PopupBg, C.field }, { r.ImGui_Col_TextSelectedBg, 0x56220299 },
  { r.ImGui_Col_ResizeGrip, 0x00000000 }, { r.ImGui_Col_ResizeGripHovered, C.accent },
  { r.ImGui_Col_ResizeGripActive, C.accent }, { r.ImGui_Col_Separator, C.line }, { r.ImGui_Col_CheckMark, C.accent },
  { r.ImGui_Col_NavHighlight or r.ImGui_Col_NavCursor, C.accent },
}
for i = #STYLE, 1, -1 do
  if not STYLE[i][1] then table.remove(STYLE, i) end
end

local function frame()
  local has = K.pick()
  if has then
    K.read()
    if #S.group == 0 or S.group_item ~= S.item then S.group = K.group_cached(); S.group_item = S.item end
    D.fresh_active()
    local src = K.src
    K.reversed = src and r.ValidatePtr(src, "PCM_source*") and select(4, r.PCM_Source_GetSectionInfo(src)) == true
  end
  local title = "AUDIO CLIP"
  if has then
    local tr = r.GetMediaItem_Track(S.item)
    local _, tname = r.GetTrackName(tr)
    local first = S.group[1] or K
    title = "AUDIO CLIP  -  " .. (first.name ~= "" and first.name or "Clip")
      .. "   (" .. math.floor(r.GetMediaTrackInfo_Value(tr, "IP_TRACKNUMBER")) .. ": " .. tname .. ")"
  end
  U.head(title)
  if not has then
    local item = r.GetSelectedMediaItem(0, 0)
    local take = item and r.GetActiveTake(item)
    D.empty(take and r.TakeIsMIDI(take) and "A MIDI clip: open it in the MIDI editor" or "No audio clip selected")
    return
  end
  local narrow = H.inspector_open()
  local left_w = narrow and 112 or 206
  local nowin = r.ImGui_WindowFlags_NoScrollbar() | r.ImGui_WindowFlags_NoScrollWithMouse()
  if r.ImGui_BeginChild(ctx, "##left", left_w, 0, 0, nowin) then
    if narrow then D.strip() else D.left() end
    r.ImGui_EndChild(ctx)
  end
  r.ImGui_SameLine(ctx, 0, 0)
  local dl = r.ImGui_GetWindowDrawList(ctx)
  local lx, ly = r.ImGui_GetCursorScreenPos(ctx)
  local aw, ah = r.ImGui_GetContentRegionAvail(ctx)
  r.ImGui_DrawList_AddRectFilled(dl, lx, ly - 2, lx + 2, ly + ah, C.line)
  r.ImGui_SetCursorScreenPos(ctx, lx + 6, ly)
  if r.ImGui_BeginChild(ctx, "##edit", aw - 6 - TOOLS_W, 0, 0, nowin) then
    local cw, ch = r.ImGui_GetContentRegionAvail(ctx)
    D.canvas(cw, ch)
    r.ImGui_EndChild(ctx)
  end
  r.ImGui_SameLine(ctx, 0, 4)
  if r.ImGui_BeginChild(ctx, "##tools", TOOLS_W - 4, 0, 0, nowin) then
    D.tools()
    r.ImGui_EndChild(ctx)
  end
  -- queued actions (reverse swaps the source, trim and split replace items) run last
  if H.queued then H.run_queued(); P.cache = {}; S.group = {} end
end

local function loop()
  r.ImGui_PushFont(ctx, font, 13)
  for _, c in ipairs(STYLE) do r.ImGui_PushStyleColor(ctx, c[1](), c[2]) end
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), 6, 3)
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), 2)
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing(), 4, 2)
  r.ImGui_SetNextWindowSize(ctx, 1100, 340, r.ImGui_Cond_FirstUseEver())
  if S.dock_to then
    r.ImGui_SetNextWindowDockID(ctx, S.dock_to)
    S.dock_to = nil
  end
  local flags = r.ImGui_WindowFlags_NoCollapse() | r.ImGui_WindowFlags_NoTitleBar()
    | r.ImGui_WindowFlags_NoScrollbar() | r.ImGui_WindowFlags_NoScrollWithMouse()
  local visible, open = r.ImGui_Begin(ctx, "Clip Edit", true, flags)
  if visible then
    frame()
    D.keys()
    r.ImGui_End(ctx)
  end
  if S.close then open = false end
  r.ImGui_PopStyleVar(ctx, 3)
  r.ImGui_PopStyleColor(ctx, #STYLE)
  r.ImGui_PopFont(ctx)
  if open then r.defer(loop) end
end

r.atexit(function()
  Q.free()
  if cmd_id and cmd_id ~= 0 then
    r.SetToggleCommandState(section_id, cmd_id, 0)
    r.RefreshToolbar2(section_id, cmd_id)
  end
end)
r.defer(loop)
