-- TK Theme Bit - Inspector: Bitwig's inspector panel for REAPER, meant to be docked at the
-- left. It shows what you touched last: a track (name, colour, volume, pan, mute / solo /
-- arm / monitoring, input, output, sends, FX) or a clip (name, colour, position, gain,
-- pan, fades, pitch, rate, mute / loop / reverse, source). TRACK | CLIP at the top picks
-- one by hand; it follows the selection again when you click elsewhere.
--
-- Laid out as Bitwig's: a header bar per selection, the colour chip and name over a 3 x 8
-- palette, rows with a grey label and a black value box with orange figures.
-- Values: drag a box up / right (Shift = fine), double-click to type, right-click for the
-- default.
-- Clip edits go to every selected clip. Run the action again to close the panel.

local r = reaper
if not r.ImGui_CreateContext then
  r.ShowMessageBox("The inspector needs ReaImGui (install it through ReaPack).", "TK Theme Bit", 0)
  return
end
do
  local _, _, version = r.ImGui_GetVersion()
  local major, minor = tostring(version):match("^(%d+)%.(%d+)")
  if not major or (tonumber(major) == 0 and tonumber(minor) < 10) then
    r.ShowMessageBox("The inspector needs ReaImGui 0.10 or newer.", "TK Theme Bit", 0)
    return
  end
end

-- run again: close (toggle state on while open, for a toolbar button)
if r.set_action_options then r.set_action_options(1 | 4) end
local _, _, section_id, cmd_id = r.get_action_context()

local ctx = r.ImGui_CreateContext("TK Theme Bit inspector")
local font = r.ImGui_CreateFont("Inter")
r.ImGui_Attach(ctx, font)
-- the header bars' bold face
local font_bold = r.ImGui_CreateFont("Inter", r.ImGui_FontFlags_Bold and r.ImGui_FontFlags_Bold() or 0)
r.ImGui_Attach(ctx, font_bold)

local mode = "track"      -- "track" or "clip"
local last_context        -- REAPER's cursor context the last time it changed
local edit_name = {}      -- name fields being typed in, by id
local dock_to             -- set by the dock key: applied before the next Begin
local bottom_h            -- the bottom block's height, measured the frame before

local function undo(desc) r.Undo_OnStateChangeEx2(0, "Inspector: " .. desc, -1, -1) end

local function amp_db(a)
  if a < 0.0000001 then return "-inf dB" end
  return string.format("%.1f dB", 20 * math.log(a, 10))
end

-- the fader mapping REAPER uses itself (0 .. 1000 over -inf .. +12 dB)
local function amp_to_t(a)
  if a < 0.0000001 then return 0 end
  return math.max(0, math.min(1, r.DB2SLIDER(20 * math.log(a, 10)) / 1000))
end
local function t_to_amp(t)
  if t <= 0 then return 0 end
  return 10 ^ (r.SLIDER2DB(t * 1000) / 20)
end

-- typed values: the first number in what was typed, read for each kind of field
local function num(s) return tonumber((s or ""):match("[%-%+]?%d*%.?%d+")) end
local function parse_db(s)
  local v = num(s)
  return v and amp_to_t(10 ^ (v / 20))
end
local function parse_pan(s)      -- 50 = 50 % right, -50 = left; also "50L" / "50R"
  local v = num(s)
  if not v then return nil end
  if (s or ""):upper():find("L") then v = -math.abs(v) end
  return (math.max(-100, math.min(100, v)) / 100 + 1) / 2
end
local function pan_text(p)
  if math.abs(p) < 0.005 then return "C" end
  return string.format("%d%% %s", math.floor(math.abs(p) * 100 + 0.5), p < 0 and "L" or "R")
end

-- Bitwig's inspector, measured from its panel: a header bar with the selection type, the
-- colour chip with the name beside it over a 3 x 8 palette, then rows with a right-aligned
-- grey label and a black value box with orange figures; groups apart by thin lines;
-- on / off keys grey, orange when on
-- colours measured from Bitwig's inspector (2026-11-24): panel 18, the empty part under it
-- 10, value boxes 4, lines and header bars 36, labels a warm grey 185/180/180, figures
-- 247/93/7, keys a gradient 54 -> 41 (orange 255/96/0 -> 248/93/0)
local C = {
  bg = 0x121212FF, empty = 0x0A0A0AFF, field = 0x040404FF, line = 0x242424FF, accent = 0xFF6000FF,
  accent_hi = 0xFF7A26FF, fill = 0x3E1A04FF, text = 0xE6E6E6FF, dim = 0x8A8A8AFF,
  label = 0xB9B4B4FF, value = 0xF75D07FF, headbar = 0x242424FF, headtext = 0xCFCFCFFF,
  seg = 0x363636FF, seg_hi = 0x444444FF, key_top = 0x363636FF, key_bot = 0x292929FF,
  key_edge = 0x0A0A0AFF, on_top = 0xFF6000FF, on_bot = 0xF85D00FF,
}
-- a Bitwig-like palette, 3 rows of 8 (row 1 muted, row 2 strong, row 3 light); the last
-- cell is "no colour"
local PALETTE = {
  0x3A3A3A, 0x5A5A5A, 0x7E7E7E, 0x5C6B8A, 0x8A6A4A, 0xB08A5A, 0x5450B0, 0x7B5AD0,
  0xD12E2E, 0xE8451C, 0xF07A1A, 0xD99D10, 0x7A8A1C, 0x2A8A3E, 0x1AA28C, 0x2E7FD1,
  0xE0606A, 0xF08A70, 0xF5A850, 0xE8C34A, 0xA6C040, 0x5CC05C, 0x4CC8C0, false,
}
local ROW_H = 18
local edit = {}           -- the value box being typed in: id, buffer, first frame

local function col_w()    -- the label column: about 40 % of the panel
  local w = r.ImGui_GetContentRegionAvail(ctx)
  return math.max(68, math.floor(w * 0.43))
end

local function text_col(col, s)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), col)
  r.ImGui_Text(ctx, s)
  r.ImGui_PopStyleColor(ctx)
end

local function label(s) text_col(C.dim, s) end

-- the header bar across the panel: "AUDIO CLIP", "TRACK 3", "NOTES (8)", ... The first
-- one (main) is Bitwig's single bar that changes with the selection; it carries the dock
-- and close icons at its right end.
local want_close = false
local function head(title, main)
  if not main then r.ImGui_Dummy(ctx, 0, 4) end
  local dl = r.ImGui_GetWindowDrawList(ctx)
  local x, y = r.ImGui_GetCursorScreenPos(ctx)
  local w = r.ImGui_GetContentRegionAvail(ctx)
  r.ImGui_DrawList_AddRectFilled(dl, x - 6, y, x + w + 6, y + 20, C.headbar)
  r.ImGui_PushFont(ctx, font_bold, 11)
  local tw, th = r.ImGui_CalcTextSize(ctx, title)
  local room = main and w - 40 or w
  r.ImGui_DrawList_AddText(dl, x + math.max(0, (room - tw) / 2), y + (20 - th) / 2, C.headtext, title)
  r.ImGui_PopFont(ctx)
  if main then
    -- dock / float (a panel, its left part filled when docked), then close
    local docked = r.ImGui_IsWindowDocked(ctx)
    r.ImGui_SetCursorScreenPos(ctx, x + w - 38, y + 2)
    if r.ImGui_InvisibleButton(ctx, "##dock", 16, 16) then dock_to = docked and 0 or -1 end
    local hov = r.ImGui_IsItemHovered(ctx)
    local ic = hov and C.text or C.dim
    r.ImGui_DrawList_AddRect(dl, x + w - 35, y + 5, x + w - 25, y + 14, ic, 1)
    if docked then r.ImGui_DrawList_AddRectFilled(dl, x + w - 35, y + 5, x + w - 32, y + 14, C.accent) end
    if hov then
      r.ImGui_SetTooltip(ctx, docked and "Float the inspector"
        or "Dock the inspector (in REAPER's first docker; set that docker to the left for Bitwig's place)")
    end
    r.ImGui_SetCursorScreenPos(ctx, x + w - 19, y + 2)
    if r.ImGui_InvisibleButton(ctx, "##close", 16, 16) then want_close = true end
    hov = r.ImGui_IsItemHovered(ctx)
    ic = hov and C.text or C.dim
    r.ImGui_DrawList_AddLine(dl, x + w - 15, y + 6, x + w - 8, y + 13, ic, 1.4)
    r.ImGui_DrawList_AddLine(dl, x + w - 8, y + 6, x + w - 15, y + 13, ic, 1.4)
    if hov then r.ImGui_SetTooltip(ctx, "Close the inspector") end
    r.ImGui_SetCursorScreenPos(ctx, x, y)
  end
  r.ImGui_Dummy(ctx, w, 22)
end

-- a thin line between groups
local function sep()
  r.ImGui_Dummy(ctx, 0, 2)
  local dl = r.ImGui_GetWindowDrawList(ctx)
  local x, y = r.ImGui_GetCursorScreenPos(ctx)
  local w = r.ImGui_GetContentRegionAvail(ctx)
  r.ImGui_DrawList_AddRectFilled(dl, x - 10, y, x + w + 10, y + 2, C.line)
  r.ImGui_Dummy(ctx, 0, 4)
end

-- one row: the label right-aligned in the left column, then draw(width) in the right one
local function row(text, draw)
  local cw = col_w()
  local x0 = r.ImGui_GetCursorPosX(ctx)
  r.ImGui_PushFont(ctx, font_bold, 12)
  local tw = r.ImGui_CalcTextSize(ctx, text)
  r.ImGui_SetCursorPosX(ctx, x0 + cw - 6 - tw)
  r.ImGui_AlignTextToFramePadding(ctx)
  text_col(C.label, text)
  r.ImGui_PopFont(ctx)
  r.ImGui_SameLine(ctx)
  r.ImGui_SetCursorPosX(ctx, x0 + cw)
  local w = r.ImGui_GetContentRegionAvail(ctx)
  draw(w)
end

-- a value box: black, the value in orange on the right; for a value with a range a dark
-- fill up to it with a thin orange edge (from the middle when centred). Drag up / right to
-- raise it (Shift: fine), double-click to type a value, right-click for the default.
-- opts: default (t), centred, parse (typed text -> t or nil), plain (no fill), w.
-- Returns the new t (0..1), moved, done.
local function vbox(id, t, text, opts)
  opts = opts or {}
  local w = opts.w or r.ImGui_GetContentRegionAvail(ctx)
  local x, y = r.ImGui_GetCursorScreenPos(ctx)
  local dl = r.ImGui_GetWindowDrawList(ctx)
  local new, moved, done = t, false, false

  if edit.id == id then
    -- typing: an input field over the box until Enter or leaving it
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
      if v then new, moved, done = math.max(0, math.min(1, v)), true, true end
      edit.id = nil
    end
    return new, moved, done
  end

  r.ImGui_InvisibleButton(ctx, "##" .. id, w, ROW_H)
  if r.ImGui_IsItemActive(ctx) then
    local dx, dy = r.ImGui_GetMouseDelta(ctx)
    local d = dx - dy
    if d ~= 0 then
      local fine = (r.ImGui_GetKeyMods(ctx) & r.ImGui_Mod_Shift()) ~= 0
      new = math.max(0, math.min(1, t + d / 200 * (fine and 0.1 or 1)))
      moved = new ~= t
    end
  end
  if r.ImGui_IsItemHovered(ctx) and r.ImGui_IsMouseDoubleClicked(ctx, 0) and opts.parse then
    edit = { id = id, buf = (text:gsub("[^%d%.%-%+]", "")), first = true }
  end
  if r.ImGui_IsItemClicked(ctx, 1) and opts.default then new, moved, done = opts.default, true, true end
  if r.ImGui_IsItemDeactivated(ctx) then done = true end

  r.ImGui_DrawList_AddRectFilled(dl, x, y, x + w, y + ROW_H, C.field, 2)
  if not opts.plain then
    -- as Bitwig: no fill, a short orange tick at the left marks a value you can drag
    r.ImGui_DrawList_AddRectFilled(dl, x + 3, y + 4, x + 5, y + ROW_H - 4, C.accent)
  end
  local tw, th = r.ImGui_CalcTextSize(ctx, text)
  r.ImGui_DrawList_PushClipRect(dl, x + 2, y, x + w - 2, y + ROW_H, true)
  r.ImGui_DrawList_AddText(dl, math.max(x + 4, x + w - 6 - tw), y + (ROW_H - th) / 2, C.value, text)
  r.ImGui_DrawList_PopClipRect(dl)
  return new, moved, done
end

-- a read-only value box (white text): signature, position, sample rate, ...
local function tbox(text, col)
  local w = r.ImGui_GetContentRegionAvail(ctx)
  local x, y = r.ImGui_GetCursorScreenPos(ctx)
  local dl = r.ImGui_GetWindowDrawList(ctx)
  r.ImGui_Dummy(ctx, w, ROW_H)
  r.ImGui_DrawList_AddRectFilled(dl, x, y, x + w, y + ROW_H, C.field, 2)
  local tw, th = r.ImGui_CalcTextSize(ctx, text)
  r.ImGui_DrawList_PushClipRect(dl, x + 2, y, x + w - 2, y + ROW_H, true)
  r.ImGui_DrawList_AddText(dl, math.max(x + 4, x + w - 6 - tw), y + (ROW_H - th) / 2, col or C.value, text)
  r.ImGui_DrawList_PopClipRect(dl)
end

-- a key as Bitwig draws them (and Bit's transport keys): a dark edge, a face running
-- lighter to darker from the top, orange when on. Returns true when clicked.
local function key(id, text, on, w, h, on_col)
  local x, y = r.ImGui_GetCursorScreenPos(ctx)
  local hit = r.ImGui_InvisibleButton(ctx, "##k" .. id, w, h)
  local hov, act = r.ImGui_IsItemHovered(ctx), r.ImGui_IsItemActive(ctx)
  local dl = r.ImGui_GetWindowDrawList(ctx)
  local top, bot = C.key_top, C.key_bot
  if on then top, bot = on_col or C.on_top, on_col or C.on_bot end
  if hov and not on then top, bot = C.seg_hi, 0x333333FF end
  if act then top, bot = bot, top end
  r.ImGui_DrawList_AddRectFilled(dl, x, y, x + w, y + h, C.key_edge, 3)
  r.ImGui_DrawList_AddRectFilledMultiColor(dl, x + 1, y + 1, x + w - 1, y + h - 1, top, top, bot, bot)
  local ink = on and 0x141414FF or C.text      -- as Bitwig: dark on an orange (on) key
  if type(text) == "function" then
    text(dl, x + w / 2, y + h / 2, ink)          -- a drawn icon, centred
  else
    local tw, th = r.ImGui_CalcTextSize(ctx, text)
    r.ImGui_DrawList_AddText(dl, x + (w - tw) / 2, y + (h - th) / 2, ink, text)
  end
  return hit
end

-- Bitwig's loop icon: a lying loop with an arrowhead at its top left
local function loop_icon(dl, cx, cy, col)
  r.ImGui_DrawList_AddRect(dl, cx - 6.5, cy - 3.5, cx + 6.5, cy + 3.5, col, 3.5, 0, 1.5)
  r.ImGui_DrawList_AddTriangleFilled(dl, cx - 4.8, cy - 3.5, cx - 1.6, cy - 6.2, cx - 1.6, cy - 0.8, col)
end

-- an on / off key across the value column (Bitwig's Looping / Muted / Shuffle keys)
local function tkey(id, text, on, on_col)
  local w = r.ImGui_GetContentRegionAvail(ctx)
  return key(id, text, on, w, ROW_H, on_col)
end

-- joined keys, the active one orange; returns the index clicked
local function segmented(id, labels, current, width)
  local picked
  local avail = width or r.ImGui_GetContentRegionAvail(ctx)
  local each = (avail - (#labels - 1)) / #labels
  for i, l in ipairs(labels) do
    if i > 1 then r.ImGui_SameLine(ctx, 0, 1) end
    if key(id .. i, l, current == i, each, ROW_H) then picked = i end
  end
  return picked
end

-- keys side by side across the panel (mute, solo, ...): each its own state
local function toggles(id, list)
  local avail = r.ImGui_GetContentRegionAvail(ctx)
  local each = (avail - (#list - 1) * 2) / #list
  local clicked
  for i, t in ipairs(list) do
    if i > 1 then r.ImGui_SameLine(ctx, 0, 2) end
    if key(id .. i, t.label, t.on, each, ROW_H + 2, t.col) then clicked = i end
  end
  return clicked
end

-- a plain action key across the panel
local function button(id, text, w)
  w = w or r.ImGui_GetContentRegionAvail(ctx)
  return key(id, text, false, w, ROW_H)
end

-- a value box moved in steps (time, length, key): drag up / right adds a step every
-- step_px pixels, double-click types, right-click resets. Plain boxes (no tick) as
-- Bitwig's for musical time. Returns steps, typed text (or nil), reset, done.
local drag_acc = {}
local function dragbox(id, text, opts)
  opts = opts or {}
  local w = opts.w or r.ImGui_GetContentRegionAvail(ctx)
  local x, y = r.ImGui_GetCursorScreenPos(ctx)
  local dl = r.ImGui_GetWindowDrawList(ctx)
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
      edit.id = nil
      return 0, s, false, true
    end
    return 0, nil, false, false
  end
  r.ImGui_InvisibleButton(ctx, "##" .. id, w, ROW_H)
  local steps, reset, done = 0, false, false
  if r.ImGui_IsItemActive(ctx) then
    local dx, dy = r.ImGui_GetMouseDelta(ctx)
    local acc = (drag_acc[id] or 0) + dx - dy
    local step = opts.step_px or 6
    steps = acc >= 0 and math.floor(acc / step) or -math.floor(-acc / step)
    drag_acc[id] = acc - steps * step
  else
    drag_acc[id] = 0
  end
  if r.ImGui_IsItemHovered(ctx) and r.ImGui_IsMouseDoubleClicked(ctx, 0) then
    edit = { id = id, buf = opts.edit_text or text, first = true }
  end
  if r.ImGui_IsItemClicked(ctx, 1) and opts.can_reset then reset, done = true, true end
  if r.ImGui_IsItemDeactivated(ctx) then done = true end
  r.ImGui_DrawList_AddRectFilled(dl, x, y, x + w, y + ROW_H, C.field, 2)
  if opts.tick then r.ImGui_DrawList_AddRectFilled(dl, x + 3, y + 4, x + 5, y + ROW_H - 4, C.accent) end
  local tw, th = r.ImGui_CalcTextSize(ctx, text)
  r.ImGui_DrawList_PushClipRect(dl, x + 2, y, x + w - 2, y + ROW_H, true)
  r.ImGui_DrawList_AddText(dl, math.max(x + 4, x + w - 6 - tw), y + (ROW_H - th) / 2, opts.col or C.value, text)
  r.ImGui_DrawList_PopClipRect(dl)
  return steps, nil, reset, done
end

-- a drop-down in a black box with a grey arrow, as Bitwig's (fill() lists the choices)
local function combo_box(id, preview, w, fill)
  local dl = r.ImGui_GetWindowDrawList(ctx)
  local x, y = r.ImGui_GetCursorScreenPos(ctx)
  r.ImGui_SetNextItemWidth(ctx, w)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), C.field)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgHovered(), 0x141414FF)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), C.value)
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FramePadding(), 6, 2)
  local open = r.ImGui_BeginCombo(ctx, "##" .. id, preview, r.ImGui_ComboFlags_NoArrowButton())
  r.ImGui_PopStyleVar(ctx)
  r.ImGui_PopStyleColor(ctx, 3)
  r.ImGui_DrawList_AddTriangleFilled(dl, x + w - 12, y + 7, x + w - 5, y + 7, x + w - 8.5, y + 11, 0x9A9A9AFF)
  if open then
    fill()
    r.ImGui_EndCombo(ctx)
  end
end

-- a block: Bitwig's sections stand as panels on the darker ground (sized to their contents)
local function block(id, draw)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ChildBg(), C.bg)
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), 6, 5)
  local flags = r.ImGui_ChildFlags_AutoResizeY() | r.ImGui_ChildFlags_AlwaysUseWindowPadding()
  local vis = r.ImGui_BeginChild(ctx, id, 0, 0, flags)
  r.ImGui_PopStyleVar(ctx)
  r.ImGui_PopStyleColor(ctx)
  if vis then
    draw()
    r.ImGui_EndChild(ctx)
  end
end

-- the colour block: a chip in the current colour with the name beside it, then the
-- palette. Returns the colour picked (0xRRGGBB, or false for none) or nil.
-- the chip's dark glyph for the kind of selection: a note (note clip), a little wave
-- (audio clip) or level bars (track), as Bitwig's clip-type glyph on its colour chip
local function kind_glyph(dl, kind, x, y, col)
  if kind == "midi" then
    r.ImGui_DrawList_AddCircleFilled(dl, x + 3.5, y + 11, 2.4, col)
    r.ImGui_DrawList_AddLine(dl, x + 5.6, y + 11, x + 5.6, y + 3.5, col, 1.4)
    r.ImGui_DrawList_AddLine(dl, x + 5.6, y + 3.8, x + 8.5, y + 5.6, col, 1.4)
  elseif kind == "audio" then
    for k, hgt in ipairs({ 3, 7, 10, 6, 3 }) do
      local cx = x + k * 1.8
      r.ImGui_DrawList_AddLine(dl, cx, y + 8 - hgt / 2, cx, y + 8 + hgt / 2, col, 1.2)
    end
  else
    for k, hgt in ipairs({ 5, 9, 7 }) do
      r.ImGui_DrawList_AddRectFilled(dl, x + k * 2.6, y + 13 - hgt, x + k * 2.6 + 1.6, y + 13, col)
    end
  end
end

-- current: the selection's own colour (nil when it has none); shown: what REAPER draws it
-- in (a clip without its own colour takes its track's); kind: "midi", "audio" or "track"
local function colour_block(id, current, name, apply_name, shown, kind)
  local dl = r.ImGui_GetWindowDrawList(ctx)
  local x, y = r.ImGui_GetCursorScreenPos(ctx)
  local w = r.ImGui_GetContentRegionAvail(ctx)
  local CW = 30
  r.ImGui_Dummy(ctx, CW, ROW_H)
  local fill = shown or current or 0x7F7F7F
  r.ImGui_DrawList_AddRectFilled(dl, x, y, x + CW, y + ROW_H, (fill << 8) | 0xFF, 3)
  -- as Bitwig's: a dark glyph for the kind, and a dark menu arrow
  local dark = 0x141414E6
  kind_glyph(dl, kind, x + 3, y + 1, dark)
  r.ImGui_DrawList_AddTriangleFilled(dl, x + CW - 10, y + 8, x + CW - 4, y + 8, x + CW - 7, y + 12, dark)
  if apply_name then
    r.ImGui_SameLine(ctx, 0, 4)
    r.ImGui_SetNextItemWidth(ctx, w - CW - 4)
    local buf = edit_name[id] or name
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), C.field)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), C.label)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameBorderSize(), 0)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FramePadding(), 6, 2)
    local _, s = r.ImGui_InputText(ctx, "##" .. id, buf)
    r.ImGui_PopStyleVar(ctx, 2)
    r.ImGui_PopStyleColor(ctx, 2)
    if r.ImGui_IsItemActive(ctx) then edit_name[id] = s end
    if r.ImGui_IsItemDeactivatedAfterEdit(ctx) then
      apply_name(s)
      edit_name[id] = nil
    elseif not r.ImGui_IsItemActive(ctx) then
      edit_name[id] = nil
    end
  end
  r.ImGui_Dummy(ctx, 0, 1)
  local gap = 1
  local s = math.floor((w - 7 * gap) / 8)
  local picked
  -- rows as close as the columns: a 1 px seam both ways
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing(), gap, gap)
  for i, col in ipairs(PALETTE) do
    if (i - 1) % 8 ~= 0 then r.ImGui_SameLine(ctx, 0, gap) end
    local cx, cy = r.ImGui_GetCursorScreenPos(ctx)
    if r.ImGui_InvisibleButton(ctx, "##pal" .. id .. i, s, s * 0.8) then picked = col end
    local h = s * 0.8
    if col then
      r.ImGui_DrawList_AddRectFilled(dl, cx, cy, cx + s, cy + h, (col << 8) | 0xFF)
    else
      r.ImGui_DrawList_AddRectFilled(dl, cx, cy, cx + s, cy + h, C.field)
      r.ImGui_DrawList_AddLine(dl, cx + 2, cy + h - 2, cx + s - 2, cy + 2, C.dim, 1)
    end
    if (col and col == current) or (not col and current == nil) then
      r.ImGui_DrawList_AddRect(dl, cx, cy, cx + s, cy + h, 0xFFFFFFFF, 0, 0, 1.5)
    end
    if r.ImGui_IsItemHovered(ctx) and not col then r.ImGui_SetTooltip(ctx, "No colour") end
  end
  r.ImGui_PopStyleVar(ctx)
  return picked
end

local function native_rgb(c)
  if not c or c & 0x1000000 == 0 then return nil end
  local R, G, B = r.ColorFromNative(c & 0xFFFFFF)
  return (R << 16) | (G << 8) | B
end

local function rgb_native(rgb)
  return r.ColorToNative((rgb >> 16) & 255, (rgb >> 8) & 255, rgb & 255) | 0x1000000
end

---------------------------------------------------------------- track
local function input_name(v)
  if v < 0 then return "None" end
  if v & 4096 ~= 0 then
    local dev, chan = (v >> 5) & 63, v & 31
    local d = dev == 63 and "All MIDI" or (select(2, r.GetMIDIInputName(dev, "")) or ("MIDI " .. dev))
    return d .. (chan == 0 and "" or (" ch " .. chan))
  end
  local stereo = v & 1024 ~= 0
  local ch = v & 1023
  local a = r.GetInputChannelName(ch) or ("In " .. (ch + 1))
  if stereo then return a .. " / " .. (r.GetInputChannelName(ch + 1) or ("In " .. (ch + 2))) end
  return a
end

local function input_combo(tr, w)
  local cur = math.floor(r.GetMediaTrackInfo_Value(tr, "I_RECINPUT"))
  combo_box("input", input_name(cur), w, function()
    local function item(v)
      if r.ImGui_Selectable(ctx, input_name(v) .. "##in" .. v, v == cur) then
        r.SetMediaTrackInfo_Value(tr, "I_RECINPUT", v)
        undo("track input")
      end
    end
    item(-1)
    item(4096 + (63 << 5))
    local n = r.GetNumAudioInputs()
    r.ImGui_Separator(ctx)
    for i = 0, n - 1 do item(i) end
    r.ImGui_Separator(ctx)
    for i = 0, n - 2, 2 do item(1024 + i) end
  end)
end

local function draw_track(tr)
  local master = tr == r.GetMasterTrack(0)
  local _, name = r.GetSetMediaTrackInfo_String(tr, "P_NAME", "", false)
  local num_ = math.floor(r.GetMediaTrackInfo_Value(tr, "IP_TRACKNUMBER"))

  head(master and "MASTER TRACK" or ("TRACK " .. num_), true)
  if not master then
    local tcol = native_rgb(r.GetTrackColor(tr))
    local pick = colour_block("tname", tcol, name, function(s)
      r.GetSetMediaTrackInfo_String(tr, "P_NAME", s, true)
      undo("track name")
    end, tcol, "track")
    if pick ~= nil then
      r.SetTrackColor(tr, pick and rgb_native(pick) or 0)
      undo("track colour")
    end
  end

  sep()
  row("Volume", function()
    local vol = r.GetMediaTrackInfo_Value(tr, "D_VOL")
    local t, moved, done = vbox("vol", amp_to_t(vol), amp_db(vol), { default = amp_to_t(1), parse = parse_db })
    if moved then r.SetMediaTrackInfo_Value(tr, "D_VOL", t_to_amp(t)) end
    if done then undo("track volume") end
  end)
  row("Pan", function()
    local pan = r.GetMediaTrackInfo_Value(tr, "D_PAN")
    local t, moved, done = vbox("pan", (pan + 1) / 2, pan_text(pan), { default = 0.5, centred = true, parse = parse_pan })
    if moved then r.SetMediaTrackInfo_Value(tr, "D_PAN", t * 2 - 1) end
    if done then undo("track pan") end
  end)
  r.ImGui_Dummy(ctx, 0, 1)
  local mute = r.GetMediaTrackInfo_Value(tr, "B_MUTE") ~= 0
  local solo = r.GetMediaTrackInfo_Value(tr, "I_SOLO") ~= 0
  local list = { { label = "M", on = mute, col = 0xE0A000FF }, { label = "S", on = solo, col = 0x2FA8E0FF } }
  if not master then
    list[#list + 1] = { label = "\u{25CF}", on = r.GetMediaTrackInfo_Value(tr, "I_RECARM") ~= 0, col = 0xE0302AFF }
    list[#list + 1] = { label = "\u{00D8}", on = r.GetMediaTrackInfo_Value(tr, "B_PHASE") ~= 0 }
  end
  local c = toggles("tmix", list)
  if c == 1 then r.SetMediaTrackInfo_Value(tr, "B_MUTE", mute and 0 or 1); undo("mute") end
  if c == 2 then r.SetMediaTrackInfo_Value(tr, "I_SOLO", solo and 0 or 2); undo("solo") end
  if c == 3 then r.SetMediaTrackInfo_Value(tr, "I_RECARM", list[3].on and 0 or 1); undo("record arm") end
  if c == 4 then r.SetMediaTrackInfo_Value(tr, "B_PHASE", list[4].on and 0 or 1); undo("phase") end

  if not master then
    sep()
    row("Input", function(w) input_combo(tr, w) end)
    row("Monitor", function()
      local mon = math.floor(r.GetMediaTrackInfo_Value(tr, "I_RECMON"))
      local p = segmented("mon", { "Off", "On", "Auto" }, mon + 1)
      if p then r.SetMediaTrackInfo_Value(tr, "I_RECMON", p - 1); undo("monitoring") end
    end)
    row("Output", function()
      local main = r.GetMediaTrackInfo_Value(tr, "B_MAINSEND") ~= 0
      local parent = r.GetParentTrack(tr)
      local out_name = "Master"
      if parent then
        local _, pn = r.GetSetMediaTrackInfo_String(parent, "P_NAME", "", false)
        out_name = pn ~= "" and pn or "Parent"
      end
      local p = segmented("out", { out_name, "None" }, main and 1 or 2)
      if p then r.SetMediaTrackInfo_Value(tr, "B_MAINSEND", p == 1 and 1 or 0); undo("output") end
    end)
  end

  local sends = r.GetTrackNumSends(tr, 0)
  if sends > 0 then
    sep()
    for i = 0, sends - 1 do
      local _, sname = r.GetTrackSendName(tr, i, "")
      row(sname, function()
        local sv = r.GetTrackSendInfo_Value(tr, 0, i, "D_VOL")
        local st, smoved, sdone = vbox("send" .. i, amp_to_t(sv), amp_db(sv), { default = amp_to_t(1), parse = parse_db })
        if smoved then r.SetTrackSendInfo_Value(tr, 0, i, "D_VOL", t_to_amp(st)) end
        if sdone then undo("send level") end
      end)
    end
  end

  head("DEVICES")
  local n = r.TrackFX_GetCount(tr)
  local dl = r.ImGui_GetWindowDrawList(ctx)
  for i = 0, n - 1 do
    local _, fx = r.TrackFX_GetFXName(tr, i, "")
    fx = fx:gsub("^%w+:%s*", ""):gsub("%s*%(.-%)$", "")
    local on = r.TrackFX_GetEnabled(tr, i)
    local x, y = r.ImGui_GetCursorScreenPos(ctx)
    if r.ImGui_InvisibleButton(ctx, "##fxon" .. i, 14, 18) then
      r.TrackFX_SetEnabled(tr, i, not on)
      undo("FX bypass")
    end
    if on then
      r.ImGui_DrawList_AddCircleFilled(dl, x + 6, y + 9, 4, C.accent)
    else
      r.ImGui_DrawList_AddCircle(dl, x + 6, y + 9, 4, C.dim, 0, 1)
    end
    r.ImGui_SameLine(ctx, 0, 4)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), on and C.text or C.dim)
    if r.ImGui_Selectable(ctx, fx .. "##fx" .. i, false) then
      r.TrackFX_Show(tr, i, r.TrackFX_GetOpen(tr, i) and 2 or 3)
    end
    r.ImGui_PopStyleColor(ctx)
  end
  if n == 0 then label("No devices") end
  r.ImGui_Dummy(ctx, 0, 2)
  if button("fxchain", "FX chain") then
    r.TrackFX_Show(tr, 0, 1)
  end
end

---------------------------------------------------------------- clip
local function for_items(fn)
  for i = 0, r.CountSelectedMediaItems(0) - 1 do
    local it = r.GetSelectedMediaItem(0, i)
    fn(it, r.GetActiveTake(it))
  end
  r.UpdateArrange()
end

local function shift_down() return (r.ImGui_GetKeyMods(ctx) & r.ImGui_Mod_Shift()) ~= 0 end

-- a time moved by a number of beats (along the project's tempo map)
local function move_beats(t, db)
  local _, _, _, fb = r.TimeMap2_timeToBeats(0, t)
  return r.TimeMap2_beatsToTime(0, fb + db)
end

-- the source's length (loop length) in seconds at the clip's position
local function source_len(take, pos)
  local src = r.GetMediaItemTake_Source(take)
  if not src then return 0 end
  local l, qn = r.GetMediaSourceLength(src)
  if qn then return r.TimeMap2_QNToTime(0, r.TimeMap2_timeToQN(0, pos) + l) - pos end
  return l / r.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE")
end

-- a fade: its length box, then Bitwig's two shape keys (linear / S-curve)
local function fade_row(item, label_, key_len, key_shape, id, len)
  row(label_, function(w)
    local fmax = math.max(0.001, math.min(len, 10))
    local v = r.GetMediaItemInfo_Value(item, key_len)
    local text = v < 1 and string.format("%.0f ms", v * 1000) or string.format("%.2f s", v)
    local t, moved, done = vbox(id, math.min(1, v / fmax), text, {
      w = w - 46, plain = true, default = 0,
      parse = function(s)
        local n = num(s)
        if not n then return nil end
        local secs = (s:lower():find("ms") or not s:lower():find("s")) and n / 1000 or n
        return secs / fmax
      end })
    if moved then for_items(function(it) r.SetMediaItemInfo_Value(it, key_len, t * fmax) end) end
    if done then undo(label_:lower()) end
    local shape = math.floor(r.GetMediaItemInfo_Value(item, key_shape))
    r.ImGui_SameLine(ctx, 0, 2)
    if key(id .. "lin", "/", shape == 0, 21, ROW_H) then
      for_items(function(it) r.SetMediaItemInfo_Value(it, key_shape, 0) end); undo("fade shape")
    end
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Linear") end
    r.ImGui_SameLine(ctx, 0, 1)
    if key(id .. "s", "S", shape == 5, 21, ROW_H) then
      for_items(function(it) r.SetMediaItemInfo_Value(it, key_shape, 5) end); undo("fade shape")
    end
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "S-curve") end
  end)
end

-- Bitwig's ARRANGER CLIP: Signature | Position, Length, Offset | Looping, Start, Length |
-- Fades | Muted (and REAPER's Locked)
local function draw_clip(item)
  local take = r.GetActiveTake(item)
  local count = r.CountSelectedMediaItems(0)
  local midi = take and r.TakeIsMIDI(take)

  head(count > 1 and ("ARRANGER CLIPS (" .. count .. ")") or "ARRANGER CLIP", true)
  local name = ""
  if take then name = select(2, r.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)) end
  -- a clip without its own colour is drawn in its track's: the chip shows that
  local own = native_rgb(math.floor(r.GetMediaItemInfo_Value(item, "I_CUSTOMCOLOR")))
  local shown = own or native_rgb(r.GetTrackColor(r.GetMediaItem_Track(item)))
  local pick = colour_block("cname", own, name,
    take and function(s)
      for_items(function(_, tk) if tk then r.GetSetMediaItemTakeInfo_String(tk, "P_NAME", s, true) end end)
      undo("clip name")
    end, shown, midi and "midi" or "audio")
  if pick ~= nil then
    for_items(function(it) r.SetMediaItemInfo_Value(it, "I_CUSTOMCOLOR", pick and rgb_native(pick) or 0) end)
    undo("clip colour")
  end

  local pos = r.GetMediaItemInfo_Value(item, "D_POSITION")
  local len = r.GetMediaItemInfo_Value(item, "D_LENGTH")
  sep()
  row("Signature", function()
    -- REAPER has no signature per clip: the project's, where the clip starts
    local n, d = r.TimeMap_GetTimeSigAtTime(0, pos)
    tbox(string.format("%d/%d", n, d), C.text)
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "The project's time signature at the clip") end
  end)

  sep()
  local step = function() return shift_down() and 0.0625 or 0.25 end     -- 1/16 or 1/4 beat
  row("Position", function()
    local steps, typed, _, done = dragbox("cpos", r.format_timestr_pos(pos, "", 2))
    if steps ~= 0 then
      local db = steps * step()
      for_items(function(it)
        local p = r.GetMediaItemInfo_Value(it, "D_POSITION")
        r.SetMediaItemInfo_Value(it, "D_POSITION", math.max(0, move_beats(p, db)))
      end)
    end
    local t = typed and r.parse_timestr_pos(typed, 2)
    if t then
      local d = t - pos
      for_items(function(it)
        r.SetMediaItemInfo_Value(it, "D_POSITION", math.max(0, r.GetMediaItemInfo_Value(it, "D_POSITION") + d))
      end)
    end
    if done then undo("clip position") end
  end)
  row("Length", function()
    local steps, typed, _, done = dragbox("clen", r.format_timestr_len(len, "", pos, 2))
    if steps ~= 0 then
      local db = steps * step()
      for_items(function(it)
        local p = r.GetMediaItemInfo_Value(it, "D_POSITION")
        local l = r.GetMediaItemInfo_Value(it, "D_LENGTH")
        r.SetMediaItemInfo_Value(it, "D_LENGTH", math.max(0.01, move_beats(p + l, db) - p))
      end)
    end
    local l = typed and r.parse_timestr_len(typed, pos, 2)
    if l and l > 0 then for_items(function(it) r.SetMediaItemInfo_Value(it, "D_LENGTH", l) end) end
    if done then undo("clip length") end
  end)
  if take then
    row("Offset", function()
      local off = r.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS")
      local rate = r.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE")
      local steps, typed, _, done = dragbox("coff", r.format_timestr_len(off / rate, "", pos, 2))
      if steps ~= 0 then
        local dt = move_beats(pos, steps * step()) - pos
        for_items(function(_, tk)
          if tk then
            local rt = r.GetMediaItemTakeInfo_Value(tk, "D_PLAYRATE")
            r.SetMediaItemTakeInfo_Value(tk, "D_STARTOFFS", r.GetMediaItemTakeInfo_Value(tk, "D_STARTOFFS") + dt * rt)
          end
        end)
      end
      local o = typed and r.parse_timestr_len(typed, pos, 2)
      if o then for_items(function(_, tk) if tk then r.SetMediaItemTakeInfo_Value(tk, "D_STARTOFFS", o * rate) end end) end
      if done then undo("clip offset") end
    end)
  end

  sep()
  local loop = r.GetMediaItemInfo_Value(item, "B_LOOPSRC") ~= 0
  row("Looping", function()
    if tkey("loop", loop_icon, loop) then
      for_items(function(it) r.SetMediaItemInfo_Value(it, "B_LOOPSRC", loop and 0 or 1) end); undo("clip loop")
    end
  end)
  if take then
    -- the loop is the source from the offset, as long as the source: shown, dim when off
    local dimcol = loop and C.value or 0x6A3A1AFF
    local off = r.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS") / r.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE")
    row("Start", function() tbox(r.format_timestr_len(off, "", pos, 2), dimcol) end)
    row("Length", function() tbox(r.format_timestr_len(source_len(take, pos), "", pos, 2), dimcol) end)
  end

  sep()
  fade_row(item, "Fade In", "D_FADEINLEN", "C_FADEINSHAPE", "fin", len)
  fade_row(item, "Fade Out", "D_FADEOUTLEN", "C_FADEOUTSHAPE", "fout", len)

  sep()
  local mute = r.GetMediaItemInfo_Value(item, "B_MUTE") ~= 0
  local lock = (math.floor(r.GetMediaItemInfo_Value(item, "C_LOCK")) & 1) ~= 0
  row("Muted", function()
    if tkey("mute", "M", mute, 0xE0A000FF) then
      for_items(function(it) r.SetMediaItemInfo_Value(it, "B_MUTE", mute and 0 or 1) end); undo("clip mute")
    end
  end)
  row("Locked", function()
    if tkey("lock", lock and "On" or "Off", lock) then
      for_items(function(it) r.SetMediaItemInfo_Value(it, "C_LOCK", lock and 0 or 1) end); undo("clip lock")
    end
  end)
  if midi then
    r.ImGui_Dummy(ctx, 0, 2)
    if button("openmidi", "Open in editor") then r.Main_OnCommand(40153, 0) end
  end
end

---------------------------------------------------------------- audio event
-- Bitwig's AUDIO EVENT, at the bottom for an audio clip: Stretch (REAPER's pitch-shift /
-- stretch algorithms and their variants), Timebase, Rate, the expressions Gain / Pan /
-- Pitch, Reverse, the source
local shifters, submode_cache = nil, {}
local function pitch_shifters()
  if not shifters then
    shifters = {}
    for m = 0, 63 do
      local ok, name = r.EnumPitchShiftModes(m)
      if not ok then break end
      if name and name ~= "" then shifters[#shifters + 1] = { m, name } end
    end
  end
  return shifters
end
local function submodes(m)
  if not submode_cache[m] then
    local out = {}
    for sm = 0, 511 do
      local name = r.EnumPitchShiftSubModes(m, sm)
      if not name or name == "" then break end
      out[#out + 1] = name
    end
    submode_cache[m] = out
  end
  return submode_cache[m]
end
local TIMEBASES = { { -1, "Project default" }, { 0, "Time" }, { 1, "Beats" }, { 2, "Beats (position only)" } }

local function draw_audio_event(item, take)
  head("AUDIO EVENT")
  local pm = math.floor(r.GetMediaItemTakeInfo_Value(take, "I_PITCHMODE"))
  local shifter, sub = pm >= 0 and (pm >> 16) or -1, pm >= 0 and (pm & 0xFFFF) or 0
  row("Stretch", function(w)
    local cur = "Project default"
    for _, s in ipairs(pitch_shifters()) do if s[1] == shifter then cur = s[2] end end
    combo_box("pmode", cur, w, function()
      if r.ImGui_Selectable(ctx, "Project default", shifter < 0) then
        for_items(function(_, tk) if tk then r.SetMediaItemTakeInfo_Value(tk, "I_PITCHMODE", -1) end end); undo("stretch mode")
      end
      for _, s in ipairs(pitch_shifters()) do
        if r.ImGui_Selectable(ctx, s[2] .. "##pm" .. s[1], s[1] == shifter) then
          for_items(function(_, tk) if tk then r.SetMediaItemTakeInfo_Value(tk, "I_PITCHMODE", s[1] << 16) end end)
          undo("stretch mode")
        end
      end
    end)
  end)
  if shifter >= 0 then
    local subs = submodes(shifter)
    if #subs > 1 then
      row("Mode", function(w)
        combo_box("psub", subs[sub + 1] or "?", w, function()
          for i, name in ipairs(subs) do
            if r.ImGui_Selectable(ctx, name .. "##ps" .. i, i - 1 == sub) then
              for_items(function(_, tk) if tk then r.SetMediaItemTakeInfo_Value(tk, "I_PITCHMODE", (shifter << 16) | (i - 1)) end end)
              undo("stretch mode")
            end
          end
        end)
      end)
    end
  end
  row("Timebase", function(w)
    local tb = math.floor(r.GetMediaItemInfo_Value(item, "C_BEATATTACHMODE"))
    local cur = "Project default"
    for _, t in ipairs(TIMEBASES) do if t[1] == tb then cur = t[2] end end
    combo_box("tbase", cur, w, function()
      for _, t in ipairs(TIMEBASES) do
        if r.ImGui_Selectable(ctx, t[2] .. "##tb" .. t[1], t[1] == tb) then
          for_items(function(it) r.SetMediaItemInfo_Value(it, "C_BEATATTACHMODE", t[1]) end); undo("timebase")
        end
      end
    end)
  end)
  row("Rate", function()
    local rate = r.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE")
    local LO, SPAN = 0.25, math.log(16)
    local t, moved, done = vbox("rate", math.log(rate / LO) / SPAN, string.format("%.3fx", rate), {
      default = math.log(1 / LO) / SPAN,
      parse = function(s) local v = num(s); return v and v > 0 and math.log(v / LO) / SPAN end })
    if moved then
      local nr = LO * math.exp(t * SPAN)
      for_items(function(it, tk)
        if tk then
          -- REAPER keeps the source's span: the clip gets shorter / longer with the rate
          local old = r.GetMediaItemTakeInfo_Value(tk, "D_PLAYRATE")
          local l = r.GetMediaItemInfo_Value(it, "D_LENGTH")
          r.SetMediaItemTakeInfo_Value(tk, "D_PLAYRATE", nr)
          r.SetMediaItemInfo_Value(it, "D_LENGTH", l * old / nr)
        end
      end)
    end
    if done then undo("clip rate") end
  end)
  row("Keep Pitch", function()
    local pp = r.GetMediaItemTakeInfo_Value(take, "B_PPITCH") ~= 0
    if tkey("ppitch", pp and "On" or "Off", pp) then
      for_items(function(_, tk) if tk then r.SetMediaItemTakeInfo_Value(tk, "B_PPITCH", pp and 0 or 1) end end)
      undo("preserve pitch")
    end
  end)

  sep()
  row("Gain", function()
    local vol = r.GetMediaItemTakeInfo_Value(take, "D_VOL")
    local t, moved, done = vbox("cgain", amp_to_t(math.abs(vol)), amp_db(math.abs(vol)), { default = amp_to_t(1), parse = parse_db })
    if moved then
      local a = t_to_amp(t)
      for_items(function(_, tk) if tk then r.SetMediaItemTakeInfo_Value(tk, "D_VOL", a) end end)
    end
    if done then undo("clip gain") end
  end)
  row("Pan", function()
    local pan = r.GetMediaItemTakeInfo_Value(take, "D_PAN")
    local t, moved, done = vbox("cpan", (pan + 1) / 2, pan_text(pan), { default = 0.5, centred = true, parse = parse_pan })
    if moved then for_items(function(_, tk) if tk then r.SetMediaItemTakeInfo_Value(tk, "D_PAN", t * 2 - 1) end end) end
    if done then undo("clip pan") end
  end)
  row("Pitch", function()
    local pitch = r.GetMediaItemTakeInfo_Value(take, "D_PITCH")
    local t, moved, done = vbox("pitch", (pitch + 24) / 48, string.format("%+.2f st", pitch), {
      default = 0.5, centred = true, parse = function(s) local v = num(s); return v and (v + 24) / 48 end })
    if moved then
      local st = t * 48 - 24
      if not shift_down() and not done then st = math.floor(st + 0.5) end
      for_items(function(_, tk) if tk then r.SetMediaItemTakeInfo_Value(tk, "D_PITCH", st) end end)
    end
    if done then undo("clip pitch") end
  end)

  sep()
  local src = r.GetMediaItemTake_Source(take)
  local rev = false
  if src then rev = select(4, r.PCM_Source_GetSectionInfo(src)) == true end
  row("Reverse", function()
    if tkey("reverse", "\u{21C4}", rev) then r.Main_OnCommand(41051, 0) end   -- Item properties: Toggle take reverse
  end)
  if src then
    local file = r.GetMediaSourceFileName(src, "")
    if file ~= "" then
      row("File", function()
        tbox(file:match("([^\\/]+)$") or file, C.text)
        if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, file) end
      end)
    end
    row("Format", function()
      tbox(string.format("%.1f kHz, %d ch", r.GetMediaSourceSampleRate(src) / 1000, r.GetMediaSourceNumChannels(src)), C.text)
    end)
  end
  r.ImGui_Dummy(ctx, 0, 2)
  if button("props", "Properties") then r.Main_OnCommand(40009, 0) end   -- Item properties
end

---------------------------------------------------------------- notes
-- Bitwig's NOTES (n) section: the notes selected in the open MIDI editor. Length and the
-- key range as Bitwig shows them; Muted, Channel; Key and Velocity drag the whole
-- selection (transpose / shift the velocities together). Release velocity, spread and
-- per-note expressions have no REAPER counterpart, so they are left out.
local NOTE_NAMES = { "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B" }
local function note_name(pitch) return NOTE_NAMES[pitch % 12 + 1] .. (pitch // 12 - 2) end   -- Bitwig: C3 = 60

-- the clip's notes, as Bitwig counts them: the ones selected in the MIDI editor when it
-- shows this clip and has a selection, otherwise all of the clip's notes
local function clip_notes(take)
  local function get(i)
    local _, sel, muted, sppq, eppq, chan, pitch, vel = r.MIDI_GetNote(take, i)
    return { i = i, sel = sel, muted = muted, s = sppq, e = eppq, chan = chan, pitch = pitch, vel = vel }
  end
  local ed = r.MIDIEditor_GetActive()
  if ed and r.MIDIEditor_GetTake(ed) == take then
    local out = {}
    local i = r.MIDI_EnumSelNotes(take, -1)
    while i ~= -1 do
      out[#out + 1] = get(i)
      i = r.MIDI_EnumSelNotes(take, i)
    end
    if #out > 0 then return out end
  end
  local out = {}
  local _, count = r.MIDI_CountEvts(take)
  for i = 0, count - 1 do out[#out + 1] = get(i) end
  return out
end

local function set_notes(take, notes, change)
  for _, n in ipairs(notes) do
    change(n)
    r.MIDI_SetNote(take, n.i, n.sel, n.muted, n.s, n.e, n.chan, n.pitch, n.vel, true)
  end
  r.MIDI_Sort(take)
end

local function notes_undo(take, desc)
  r.Undo_OnStateChange_Item(0, "Inspector: " .. desc, r.GetMediaItemTake_Item(take))
end

local function draw_notes(take)
  local notes = clip_notes(take)
  if #notes == 0 then return end
  head("NOTES (" .. #notes .. ")")

  local n1 = notes[1]
  local same_len, all_muted, any_muted, chan = true, true, false, n1.chan
  local lo, hi, vsum = 127, 0, 0
  for _, n in ipairs(notes) do
    if n.e - n.s ~= n1.e - n1.s then same_len = false end
    if n.muted then any_muted = true else all_muted = false end
    if n.chan ~= chan then chan = nil end
    lo, hi, vsum = math.min(lo, n.pitch), math.max(hi, n.pitch), vsum + n.vel
  end
  local t0 = r.MIDI_GetProjTimeFromPPQPos(take, n1.s)
  local len = r.MIDI_GetProjTimeFromPPQPos(take, n1.e) - t0
  -- one beat (quarter note) in this take's ticks
  local qn0 = r.MIDI_GetProjQNFromPPQPos(take, n1.s)
  local ppq_qn = r.MIDI_GetPPQPosFromProjQN(take, qn0 + 1) - n1.s

  -- Length: drag lengthens / shortens every note by 1/16 (Shift: 1/64), typed sets them all
  row("Length", function()
    local steps, typed, _, done = dragbox("nlen", (same_len and "" or "~ ") .. r.format_timestr_len(len, "", t0, 2),
      { edit_text = r.format_timestr_len(len, "", t0, 2) })
    if steps ~= 0 then
      local d = steps * ppq_qn * ((r.ImGui_GetKeyMods(ctx) & r.ImGui_Mod_Shift()) ~= 0 and 0.0625 or 0.25)
      set_notes(take, notes, function(n) n.e = math.max(n.s + 1, n.e + d) end)
    end
    local l = typed and r.parse_timestr_len(typed, t0, 2)
    if l and l > 0 then
      set_notes(take, notes, function(n)
        local ts = r.MIDI_GetProjTimeFromPPQPos(take, n.s)
        n.e = math.max(n.s + 1, r.MIDI_GetPPQPosFromProjTime(take, ts + l))
      end)
    end
    if done then notes_undo(take, "note length") end
  end)
  row("Muted", function()
    if tkey("nmute", any_muted and not all_muted and "M  (mixed)" or "M", all_muted, 0xE0A000FF) then
      set_notes(take, notes, function(n) n.muted = not all_muted end)
      notes_undo(take, "note mute")
    end
  end)

  sep()
  row("Channel", function(w)
    combo_box("nchan", chan and tostring(chan + 1) or "(mixed)", w, function()
      for c = 0, 15 do
        if r.ImGui_Selectable(ctx, tostring(c + 1) .. "##ch" .. c, c == chan) then
          set_notes(take, notes, function(n) n.chan = c end)
          notes_undo(take, "note channel")
        end
      end
    end)
  end)
  -- Key: the lowest and highest note in two boxes, as Bitwig's; dragging either moves the
  -- notes by semitones, typing a name moves the low (or high) one there
  local function parse_note(sx)
    local name, oct = (sx or ""):upper():match("^%s*([A-G]#?)%s*(%-?%d+)")
    if not name then return nil end
    for k, nn in ipairs(NOTE_NAMES) do
      if nn == name then return (tonumber(oct) + 2) * 12 + k - 1 end
    end
  end
  local function transpose(d)
    d = math.max(-lo, math.min(127 - hi, d))
    if d ~= 0 then set_notes(take, notes, function(n) n.pitch = n.pitch + d end) end
  end
  row("Key", function(w)
    local half = (w - 4) / 2
    local s1, typed1, _, done1 = dragbox("nklo", note_name(lo), { w = half, step_px = 8 })
    r.ImGui_SameLine(ctx, 0, 4)
    local s2, typed2, _, done2 = dragbox("nkhi", note_name(hi), { w = half, step_px = 8 })
    if s1 + s2 ~= 0 then transpose(s1 + s2) end
    local p1, p2 = parse_note(typed1), parse_note(typed2)
    if p1 then transpose(p1 - lo) elseif p2 then transpose(p2 - hi) end
    if done1 or done2 then notes_undo(take, "transpose notes") end
  end)
  row("Velocity", function()
    local avg = vsum / #notes
    local t, moved, done = vbox("nvel", avg / 127, string.format("%.1f %%", avg / 127 * 100), {
      default = 100 / 127,
      parse = function(sx) local v = num(sx); return v and v / 100 end })
    if moved then
      local d = t * 127 - avg
      set_notes(take, notes, function(n) n.vel = math.max(1, math.min(127, math.floor(n.vel + d + 0.5))) end)
    end
    if done then notes_undo(take, "note velocity") end
  end)
end

---------------------------------------------------------------- expressions
-- Bitwig's EXPRESSIONS block, with the one REAPER has per note: Pressure = polyphonic
-- aftertouch (0xA0, its own lane in the MIDI editor). A note's pressure is the first poly
-- aftertouch event for its key and channel from its start to its end; none counts as 0.
-- Dragging moves every note's pressure by the same amount (a note without one gets an
-- event at its start). Only instruments that respond to poly aftertouch will be heard.
local function pressure_map(take)
  local map = {}
  local _, _, ccs = r.MIDI_CountEvts(take)
  for i = 0, ccs - 1 do
    local _, _, _, ppq, chanmsg, chan, msg2, msg3 = r.MIDI_GetCC(take, i)
    if chanmsg == 0xA0 then
      local k = chan * 128 + msg2
      map[k] = map[k] or {}
      map[k][#map[k] + 1] = { i = i, ppq = ppq, val = msg3 }
    end
  end
  return map
end

local function note_pressure(map, n)
  local best
  for _, e in ipairs(map[n.chan * 128 + n.pitch] or {}) do
    if e.ppq >= n.s and e.ppq < n.e and (not best or e.ppq < best.ppq) then best = e end
  end
  return best
end

local function draw_expressions(take)
  local notes = clip_notes(take)
  if #notes == 0 then return end
  head("EXPRESSIONS")
  local map = pressure_map(take)
  local sum = 0
  for _, n in ipairs(notes) do
    local e = note_pressure(map, n)
    sum = sum + (e and e.val or 0)
  end
  local avg = sum / #notes
  row("Pressure", function()
    local t, moved, done = vbox("npress", avg / 127, string.format("%.2f %%", avg / 127 * 100), {
      default = 0, parse = function(sx) local v = num(sx); return v and v / 100 end })
    if moved then
      local d = t * 127 - avg
      local inserts = {}
      for _, n in ipairs(notes) do
        local e = note_pressure(map, n)
        local v = math.max(0, math.min(127, math.floor((e and e.val or 0) + d + 0.5)))
        if e then
          local _, sel, mute, ppq, chanmsg, chan, msg2 = r.MIDI_GetCC(take, e.i)
          r.MIDI_SetCC(take, e.i, sel, mute, ppq, chanmsg, chan, msg2, v, true)
        elseif v > 0 then
          inserts[#inserts + 1] = { n.s, n.chan, n.pitch, v }
        end
      end
      -- new events last, so the indices above stayed valid while setting
      for _, ins in ipairs(inserts) do r.MIDI_InsertCC(take, false, false, ins[1], 0xA0, ins[2], ins[3], ins[4]) end
      r.MIDI_Sort(take)
    end
    if done then notes_undo(take, "note pressure") end
    if r.ImGui_IsItemHovered(ctx) then
      r.ImGui_SetTooltip(ctx, "Polyphonic aftertouch per note; heard only with instruments that respond to it")
    end
  end)
end

---------------------------------------------------------------- footer
-- Bitwig's window footer keys, here at the foot of the inspector: browser, project, studio
-- I/O, keyboard. Each opens REAPER's nearest window and is orange while that is open.
local FOOT_H = 30
local FOOTER = {
  { "browser", 50124, "Browser (Media Explorer)" },           -- Media explorer: Show/hide
  { "project", 40021, "Project settings" },                   -- File: Project settings
  { "studio", 40251, "Studio I/O (routing matrix)" },         -- View: Show routing matrix
  { "hand", nil, "(not used yet)" },
  { "sep" },
  { "keys", 40377, "Keyboard (virtual MIDI keyboard)" },      -- View: Show virtual MIDI keyboard
}

-- Bitwig's footer icons: light and filled, 16 px
local function foot_icon(dl, kind, x, y, col)
  local bg = C.empty
  if kind == "browser" then
    r.ImGui_DrawList_AddCircle(dl, x + 6.5, y + 6.5, 4.5, col, 0, 2)
    r.ImGui_DrawList_AddLine(dl, x + 10, y + 10, x + 14.5, y + 14.5, col, 2.4)
  elseif kind == "project" then
    -- a page with its top-right corner folded
    r.ImGui_DrawList_AddRectFilled(dl, x + 3, y + 1, x + 13, y + 15, col, 1)
    r.ImGui_DrawList_AddTriangleFilled(dl, x + 9, y + 1, x + 13.5, y + 0.5, x + 13.5, y + 5, bg)
    r.ImGui_DrawList_AddTriangleFilled(dl, x + 9, y + 1, x + 9, y + 5, x + 13, y + 5, 0x9A9A9AFF)
  elseif kind == "studio" then
    -- a speaker: body, tweeter, woofer
    r.ImGui_DrawList_AddRectFilled(dl, x + 3, y + 0.5, x + 13, y + 15.5, col, 2)
    r.ImGui_DrawList_AddCircleFilled(dl, x + 8, y + 4.2, 1.6, bg)
    r.ImGui_DrawList_AddCircleFilled(dl, x + 8, y + 10.2, 3.6, bg)
    r.ImGui_DrawList_AddCircleFilled(dl, x + 8, y + 10.2, 1.4, col)
  elseif kind == "hand" then
    -- a pointing hand: finger up, palm, knuckles, thumb
    r.ImGui_DrawList_AddRectFilled(dl, x + 6, y + 0.5, x + 8.6, y + 9, col, 1.3)
    r.ImGui_DrawList_AddRectFilled(dl, x + 8.8, y + 5.5, x + 10.8, y + 9, col, 1)
    r.ImGui_DrawList_AddRectFilled(dl, x + 11, y + 6.5, x + 13, y + 9.5, col, 1)
    r.ImGui_DrawList_AddRectFilled(dl, x + 3.2, y + 8.5, x + 6, y + 12, col, 1.2)
    r.ImGui_DrawList_AddRectFilled(dl, x + 5, y + 8, x + 13, y + 15.5, col, 2.5)
  elseif kind == "keys" then
    -- a keyboard: white keys with seams, black keys on top
    r.ImGui_DrawList_AddRectFilled(dl, x + 1, y + 1, x + 15, y + 15, col, 1)
    for k = 1, 3 do r.ImGui_DrawList_AddLine(dl, x + 1 + k * 3.5, y + 1, x + 1 + k * 3.5, y + 15, bg, 1) end
    for k = 1, 3 do
      local cx = x + 1 + k * 3.5
      r.ImGui_DrawList_AddRectFilled(dl, cx - 1.2, y + 1, cx + 1.2, y + 9, bg)
    end
  end
end

local function footer()
  local dl = r.ImGui_GetWindowDrawList(ctx)
  local x, y = r.ImGui_GetCursorScreenPos(ctx)
  local w = r.ImGui_GetContentRegionAvail(ctx)
  r.ImGui_DrawList_AddLine(dl, x - 10, y, x + w + 10, y, C.line, 1)
  r.ImGui_SetCursorScreenPos(ctx, x, y + 5)
  for i, f in ipairs(FOOTER) do
    if i > 1 then r.ImGui_SameLine(ctx, 0, 6) end
    local bx, by = r.ImGui_GetCursorScreenPos(ctx)
    if f[1] == "sep" then
      r.ImGui_Dummy(ctx, 2, 20)
      r.ImGui_DrawList_AddLine(dl, bx + 1, by + 3, bx + 1, by + 17, 0x5A5A5AFF, 1)
    else
      if r.ImGui_InvisibleButton(ctx, "##foot" .. i, 20, 20) and f[2] then r.Main_OnCommand(f[2], 0) end
      local hov = r.ImGui_IsItemHovered(ctx)
      local on = f[2] and r.GetToggleCommandState(f[2]) == 1
      foot_icon(dl, f[1], bx + 2, by + 2, on and C.accent or (hov and 0xFFFFFFFF or 0xC4C4C4FF))
      if hov then r.ImGui_SetTooltip(ctx, f[3]) end
    end
  end
end

---------------------------------------------------------------- what to show
local function current_track()
  return r.GetSelectedTrack2(0, 0, true) or r.GetLastTouchedTrack()
end

local function follow_selection()
  local c = r.GetCursorContext2(true)
  if c ~= last_context then
    last_context = c
    if c == 1 and r.CountSelectedMediaItems(0) > 0 then mode = "clip"
    elseif c == 0 then mode = "track" end
  end
end

-- every colour ImGui would otherwise draw in its own blue: the floating window's title
-- bar, the resize corner, field hovers, text selection, scrollbars, separators
local STYLE = {
  { r.ImGui_Col_WindowBg, C.empty }, { r.ImGui_Col_ChildBg, 0x00000000 }, { r.ImGui_Col_Text, C.text }, { r.ImGui_Col_Border, C.line },
  { r.ImGui_Col_TitleBg, 0x161616FF }, { r.ImGui_Col_TitleBgActive, 0x262626FF },
  { r.ImGui_Col_TitleBgCollapsed, 0x161616FF },
  { r.ImGui_Col_Button, C.seg }, { r.ImGui_Col_ButtonHovered, C.seg_hi }, { r.ImGui_Col_ButtonActive, C.field },
  { r.ImGui_Col_FrameBg, C.field }, { r.ImGui_Col_FrameBgHovered, 0x1A1A1AFF }, { r.ImGui_Col_FrameBgActive, 0x222222FF },
  { r.ImGui_Col_Header, C.fill }, { r.ImGui_Col_HeaderHovered, 0x2A2A2AFF }, { r.ImGui_Col_HeaderActive, 0x333333FF },
  { r.ImGui_Col_PopupBg, C.field }, { r.ImGui_Col_TextSelectedBg, 0x56220299 },
  { r.ImGui_Col_ResizeGrip, 0x00000000 }, { r.ImGui_Col_ResizeGripHovered, C.accent },
  { r.ImGui_Col_ResizeGripActive, C.accent },
  { r.ImGui_Col_ScrollbarBg, 0x00000000 }, { r.ImGui_Col_ScrollbarGrab, 0x3A3A3AFF },
  { r.ImGui_Col_ScrollbarGrabHovered, 0x4A4A4AFF }, { r.ImGui_Col_ScrollbarGrabActive, C.accent },
  { r.ImGui_Col_Separator, C.line }, { r.ImGui_Col_CheckMark, C.accent },
  { r.ImGui_Col_NavHighlight or r.ImGui_Col_NavCursor, C.accent },   -- renamed in ReaImGui 0.10
}
for i = #STYLE, 1, -1 do                 -- only what this ReaImGui has
  if not STYLE[i][1] then table.remove(STYLE, i) end
end

local function loop()
  follow_selection()
  r.ImGui_PushFont(ctx, font, 13)
  for _, c in ipairs(STYLE) do r.ImGui_PushStyleColor(ctx, c[1](), c[2]) end
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), 3, 3)
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), 2)
  r.ImGui_SetNextWindowSize(ctx, 240, 640, r.ImGui_Cond_FirstUseEver())
  if dock_to then
    r.ImGui_SetNextWindowDockID(ctx, dock_to)
    dock_to = nil
  end
  -- no ImGui title bar (its blue): docked, REAPER's docker tab names it; floating, it moves
  -- by any empty spot, and the cross at the top right closes it
  local flags = r.ImGui_WindowFlags_NoCollapse() | r.ImGui_WindowFlags_NoTitleBar()
  local visible, open = r.ImGui_Begin(ctx, "Inspector", true, flags)
  if visible then
    -- the panel scrolls; the footer stays at the bottom. As Bitwig: the selection's block
    -- at the top, its contents (NOTES / AUDIO EVENT) as a block at the bottom
    if r.ImGui_BeginChild(ctx, "##body", 0, -FOOT_H) then
      local item = mode == "clip" and r.GetSelectedMediaItem(0, 0)
      local tr = mode ~= "clip" and current_track()
      block("##main", function()
        if mode == "clip" then
          if item then draw_clip(item) else label("No clip selected.") end
        else
          if tr then draw_track(tr) else label("No track selected.") end
        end
      end)
      local take = item and r.GetActiveTake(item)
      local midi = take and r.TakeIsMIDI(take)
      if take and (not midi or select(2, r.MIDI_CountEvts(take)) > 0) then
        local _, avail_h = r.ImGui_GetContentRegionAvail(ctx)
        if bottom_h and avail_h > bottom_h then r.ImGui_Dummy(ctx, 0, avail_h - bottom_h) end
        local y0 = r.ImGui_GetCursorPosY(ctx)
        block("##bottom", function()
          if midi then draw_notes(take) else draw_audio_event(item, take) end
        end)
        if midi then block("##expr", function() draw_expressions(take) end) end
        bottom_h = r.ImGui_GetCursorPosY(ctx) - y0
      end
      r.ImGui_EndChild(ctx)
    end
    footer()
    r.ImGui_End(ctx)
  end
  if want_close then open = false end
  r.ImGui_PopStyleVar(ctx, 2)
  r.ImGui_PopStyleColor(ctx, #STYLE)
  r.ImGui_PopFont(ctx)
  if open then r.defer(loop) end
end

-- the inspector key in the transport is orange while this runs: theme parameter bitInspOn
local function theme_says_open(v)
  local i = 0
  while true do
    local name, _, value = r.ThemeLayout_GetParameter(i)
    if not name then return end
    if name == "bitInspOn" then
      if value ~= v then
        r.ThemeLayout_SetParameter(i, v, false)
        r.ThemeLayout_RefreshAll()
      end
      return
    end
    i = i + 1
  end
end
theme_says_open(1)

r.atexit(function()
  theme_says_open(0)
  if cmd_id and cmd_id ~= 0 then
    r.SetToggleCommandState(section_id, cmd_id, 0)
    r.RefreshToolbar2(section_id, cmd_id)
  end
end)
r.defer(loop)
