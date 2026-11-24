-- TK Theme Bit - Clip Edit: Bitwig's audio editor for REAPER, meant for the bottom docker.
-- It follows the selected audio clip: the waveform in the clip's colour under a bar / beat
-- ruler, with the clip's fades, gain, take volume envelope and stretch markers on it.
--
-- Mouse: wheel scrolls, Ctrl+wheel zooms, Alt+wheel makes the waveform taller.
-- Drag in the ruler or the waveform for a time selection; click to move the edit cursor.
-- Fades: drag the white squares, right-click one for the next shape.
-- Gain: drag the dB box in the clip's top strip up / down (double-click: 0 dB).
-- Volume envelope: click the line to add a point, drag points, Alt- or right-click deletes.
-- Stretch markers: double-click the top strip to add one, drag to stretch, Alt- or
-- right-click deletes. Tools: Draw adds envelope points anywhere, Stretch adds markers.
-- Shift: no snap / fine. Space plays, S splits, Ctrl+Z undoes while the panel has focus.
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
  canvas = 0x0E0E0EFF, ruler = 0x1A1A1AFF, bar = 0x2C2C2CFF, beat = 0x1C1C1CFF,
  marker = 0xE8C34AFF, sel = 0xFF600024, handle = 0xE6E6E6FF,
}
local ROW_H, LEFT_W, RULER_H, SCROLL_H, STRIP_H = 18, 206, 22, 14, 15
local EXT = "TK Bit Clip Edit"
local CMD = { split_sel = 40061, split_cur = 40757, trim = 40508, reverse = 41051, normalize = 40108,
  play = 40044, undo = 40029, redo = 40030, unselect = 40289, vol_env = 40693 }

-- what the panel shows and how: kept between runs
local S = {
  tool = r.GetExtState(EXT, "tool") ~= "" and r.GetExtState(EXT, "tool") or "select",
  snap = r.GetExtState(EXT, "snap") ~= "0",
  show_env = r.GetExtState(EXT, "show_env") ~= "0",
  show_sm = r.GetExtState(EXT, "show_sm") ~= "0",
  follow = true,
  vzoom = 1,
  item = nil, take = nil,  -- the clip shown
  vs = 0, ve = 1,          -- the view, in project time
  dock_to = nil, close = false, edit = {},
}
local function save()
  r.SetExtState(EXT, "tool", S.tool, true)
  r.SetExtState(EXT, "snap", S.snap and "1" or "0", true)
  r.SetExtState(EXT, "show_env", S.show_env and "1" or "0", true)
  r.SetExtState(EXT, "show_sm", S.show_sm and "1" or "0", true)
end

---------------------------------------------------------------- helpers
local H = {}
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

-- runs a REAPER action on the shown clip: selects it alone first when it is not selected
function H.run(cmd)
  if not S.item then return end
  if not r.IsMediaItemSelected(S.item) then
    r.Main_OnCommand(CMD.unselect, 0)
    r.SetMediaItemSelected(S.item, true)
  end
  r.Main_OnCommand(cmd, 0)
end

function H.time_sel()
  local a, b = r.GetSet_LoopTimeRange2(0, false, false, 0, 0, false)
  if b > a then return a, b end
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
  local cw = 74
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
-- a text key as wide as its text
function U.tkey(id, text, on, tip)
  local tw = r.ImGui_CalcTextSize(ctx, text)
  local hit = U.key(id, text, on, tw + 18, ROW_H, tip)
  r.ImGui_SameLine(ctx, 0, 2)
  return hit
end
function U.gap() r.ImGui_SameLine(ctx, 0, 12) end

-- the tools' flat icons
local ICON = {}
function ICON.select(dl, cx, cy, col)
  r.ImGui_DrawList_AddTriangleFilled(dl, cx - 4, cy - 6, cx - 4, cy + 5, cx + 4, cy + 1, col)
  r.ImGui_DrawList_AddLine(dl, cx, cy + 1, cx + 2.5, cy + 6, col, 2)
end
function ICON.draw(dl, cx, cy, col)
  r.ImGui_DrawList_AddLine(dl, cx - 4, cy + 4, cx + 4, cy - 4, col, 2.5)
  r.ImGui_DrawList_AddTriangleFilled(dl, cx - 6, cy + 6, cx - 5, cy + 2, cx - 2, cy + 5, col)
end
function ICON.stretch(dl, cx, cy, col)
  r.ImGui_DrawList_AddLine(dl, cx, cy - 6, cx, cy + 6, col, 1.5)
  r.ImGui_DrawList_AddTriangleFilled(dl, cx - 7, cy, cx - 3, cy - 3.5, cx - 3, cy + 3.5, col)
  r.ImGui_DrawList_AddTriangleFilled(dl, cx + 7, cy, cx + 3, cy - 3.5, cx + 3, cy + 3.5, col)
end

---------------------------------------------------------------- the clip
local K = {}   -- the shown clip's values, read once per frame

function K.read()
  local item, take = S.item, S.take
  K.pos = r.GetMediaItemInfo_Value(item, "D_POSITION")
  K.len = r.GetMediaItemInfo_Value(item, "D_LENGTH")
  K.rate = r.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE")
  K.vol = r.GetMediaItemTakeInfo_Value(take, "D_VOL")
  K.fin = r.GetMediaItemInfo_Value(item, "D_FADEINLEN_AUTO")
  if K.fin <= 0 then K.fin = r.GetMediaItemInfo_Value(item, "D_FADEINLEN") end
  K.fout = r.GetMediaItemInfo_Value(item, "D_FADEOUTLEN_AUTO")
  if K.fout <= 0 then K.fout = r.GetMediaItemInfo_Value(item, "D_FADEOUTLEN") end
  K.fin_shape = math.floor(r.GetMediaItemInfo_Value(item, "C_FADEINSHAPE"))
  K.fout_shape = math.floor(r.GetMediaItemInfo_Value(item, "C_FADEOUTSHAPE"))
  local own = H.native_rgb(math.floor(r.GetMediaItemInfo_Value(item, "I_CUSTOMCOLOR")))
  K.rgb = own or H.native_rgb(r.GetTrackColor(r.GetMediaItem_Track(item))) or 0x8A8A8A
  K.name = select(2, r.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false))
  K.src = r.GetMediaItemTake_Source(take)
  K.nch = 1
  if K.src then
    K.nch = math.min(2, math.max(1, r.GetMediaSourceNumChannels(K.src)))
    if r.GetMediaItemTakeInfo_Value(take, "I_CHANMODE") >= 2 then K.nch = 1 end
  end
  K.env = r.GetTakeEnvelopeByName(take, "Volume")
end
-- take time (envelopes, stretch markers) <-> project time
function K.to_take(t) return (t - K.pos) * K.rate end
function K.from_take(tt) return K.pos + tt / K.rate end

-- the item the panel shows: the first selected audio clip (unless Follow is off)
function K.pick()
  local item = S.item
  if item and not r.ValidatePtr2(0, item, "MediaItem*") then item = nil end
  if S.follow or not item then item = r.GetSelectedMediaItem(0, 0) end
  local take = item and r.GetActiveTake(item)
  if take and r.TakeIsMIDI(take) then take = nil end
  if item ~= S.item then
    S.item = item
    S.fit = true
  end
  S.take = take
  return take ~= nil
end

function K.fit()
  local pad = math.max(0.01, K.len * 0.02)
  S.vs, S.ve = K.pos - pad, K.pos + K.len + pad
end

---------------------------------------------------------------- peaks
local P = { key = nil }
-- the take's peaks for the visible part, one per pixel (REAPER's peak files: rate,
-- stretch markers, loops and reverse already applied)
function P.get(x0, w)
  local pps = w / (S.ve - S.vs)
  local a, b = math.max(S.vs, K.pos), math.min(S.ve, K.pos + K.len)
  if b <= a then P.n = 0; return end
  local key = table.concat({ tostring(S.take), S.vs, S.ve, w, K.nch, r.GetProjectStateChangeCount(0) }, "|")
  if key == P.key then return end
  local n = math.floor((b - a) * pps)
  if n < 1 then P.n = 0; return end
  local buf = r.new_array(n * K.nch * 2)
  local rv = r.GetMediaItemTake_Peaks(S.take, pps, a, K.nch, n, 0, buf)
  local got = rv & 0xFFFFF
  P.buf, P.n, P.req, P.x = buf, got, n, x0 + (a - S.vs) * pps
  P.key = got > 0 and key or nil      -- peaks still being built: ask again next frame
end

---------------------------------------------------------------- the edit canvas
local V = {}   -- view mapping, set each frame: V.x, V.w, V.pps
function V.X(t) return V.x + (t - S.vs) * V.pps end
function V.T(x) return S.vs + (x - V.x) / V.pps end
function V.snap(t, shift)
  if S.snap and not shift then return r.SnapToGrid(0, t) end
  return t
end
function V.zoom(factor, at)
  local span = H.clamp((S.ve - S.vs) * factor, 0.005, math.max(1, K.len * 1.5))
  local k = (at - S.vs) / (S.ve - S.vs)
  S.vs = at - span * k
  S.ve = S.vs + span
  V.clamp()
end
function V.scroll(dt)
  S.vs, S.ve = S.vs + dt, S.ve + dt
  V.clamp()
end
function V.clamp()
  local pad = math.max(0.01, K.len * 0.25)
  local lo, hi = K.pos - pad, K.pos + K.len + pad
  local span = S.ve - S.vs
  if span > hi - lo then lo, hi = (lo + hi - span) / 2, (lo + hi + span) / 2 end
  if S.vs < lo then S.vs, S.ve = lo, lo + span end
  if S.ve > hi then S.vs, S.ve = hi - span, hi end
end

-- the ruler: bars and beats from the project's tempo map
function V.ruler(dl, x, y, w, wy0, wy1)
  r.ImGui_DrawList_AddRectFilled(dl, x, y, x + w, y + RULER_H, C.ruler)
  local _, m = r.TimeMap2_timeToBeats(0, S.vs)
  m = math.max(0, m)
  local guard = 0
  local label_every = 1
  while guard < 4000 do
    guard = guard + 1
    local ts, qs, qe, num = r.TimeMap_GetMeasureInfo(0, m)
    if ts > S.ve then break end
    local te = r.TimeMap2_QNToTime(0, qe)
    local bar_px = (te - ts) * V.pps
    if guard == 1 then while bar_px * label_every < 44 and label_every < 1024 do label_every = label_every * 2 end end
    local bx = V.X(ts)
    if bx >= x - 1 and bx <= x + w then
      r.ImGui_DrawList_AddLine(dl, bx, wy0, bx, wy1, C.bar)
      if m % label_every == 0 then
        r.ImGui_DrawList_AddLine(dl, bx, y + 5, bx, y + RULER_H, C.dim)
        local s = r.format_timestr_pos(ts + 0.0000001, "", 2):match("^[^%.]+") or tostring(m + 1)
        r.ImGui_DrawList_AddText(dl, bx + 3, y + 1, C.text, s)
      else
        r.ImGui_DrawList_AddLine(dl, bx, y + 12, bx, y + RULER_H, C.dim)
      end
    end
    local qpb = (qe - qs) / math.max(1, num)
    local beat_px = bar_px / math.max(1, num)
    local sub = beat_px >= 56 and 4 or beat_px >= 28 and 2 or 1
    if beat_px >= 6 then
      for b = 0, num * sub - 1 do
        if b > 0 then
          local bt = r.TimeMap2_QNToTime(0, qs + b * qpb / sub)
          local xx = V.X(bt)
          if xx > x and xx < x + w then
            local on_beat = b % sub == 0
            r.ImGui_DrawList_AddLine(dl, xx, on_beat and y + 15 or y + 18, xx, y + RULER_H, C.line)
            r.ImGui_DrawList_AddLine(dl, xx, wy0, xx, wy1, on_beat and C.beat or 0x161616FF)
          end
        end
      end
    end
    m = m + 1
  end
end

-- the clip: its colour, header strip, waveform, fades, envelope and stretch markers
function V.clip(dl, top, bot)
  local cx0, cx1 = V.X(K.pos), V.X(K.pos + K.len)
  local body = H.shade(K.rgb, -0.72)
  r.ImGui_DrawList_AddRectFilled(dl, cx0, top, cx1, bot, body)
  r.ImGui_DrawList_AddRectFilled(dl, cx0, top, cx1, top + STRIP_H, H.shade(K.rgb, 0))
  r.ImGui_DrawList_AddText(dl, math.max(cx0, V.x) + 4, top + 1, 0x141414FF, K.name)

  -- channels
  local wt, wb = top + STRIP_H + 2, bot - 2
  local lane = (wb - wt) / K.nch
  local wave = H.shade(K.rgb, 0.25)
  local mid_col = H.shade(K.rgb, -0.35)
  local gain = math.abs(K.vol) * S.vzoom
  for c = 0, K.nch - 1 do
    local mid = wt + lane * (c + 0.5)
    r.ImGui_DrawList_AddLine(dl, math.max(cx0, V.x), mid, math.min(cx1, V.x + V.w), mid, mid_col)
  end
  if P.n and P.n > 0 then
    local buf, n, nch = P.buf, P.req, K.nch
    local hh = lane / 2 - 1
    for i = 0, P.n - 1 do
      local px = P.x + i
      local t = V.T(px)
      local g = gain
      if K.fin > 0 and t < K.pos + K.fin then g = g * H.fade_gain(K.fin_shape, (t - K.pos) / K.fin) end
      if K.fout > 0 and t > K.pos + K.len - K.fout then
        g = g * H.fade_gain(K.fout_shape, (K.pos + K.len - t) / K.fout)
      end
      for c = 0, nch - 1 do
        local hi = buf[i * nch + c + 1] or 0
        local lo = buf[n * nch + i * nch + c + 1] or 0
        local mid = wt + lane * (c + 0.5)
        local y1 = mid - H.clamp(hi * g, -1, 1) * hh
        local y2 = mid - H.clamp(lo * g, -1, 1) * hh
        if y2 - y1 < 1 then y2 = y1 + 1 end
        r.ImGui_DrawList_AddLine(dl, px, y1, px, y2, wave)
      end
    end
  end

  -- fades: the curve and a square handle at the fade's end
  local fh = wb - wt
  local function fade_curve(t0, t1, shape, out)
    local px, py
    for i = 0, 24 do
      local u = i / 24
      local t = t0 + (t1 - t0) * u
      local g = H.fade_gain(shape, out and 1 - u or u)
      local x, y = V.X(t), wt + (1 - g) * fh
      if px then r.ImGui_DrawList_AddLine(dl, px, py, x, y, C.handle, 1) end
      px, py = x, y
    end
  end
  if K.fin > 0 then fade_curve(K.pos, K.pos + K.fin, K.fin_shape, false) end
  if K.fout > 0 then fade_curve(K.pos + K.len - K.fout, K.pos + K.len, K.fout_shape, true) end
  V.hfin, V.hfout = V.X(K.pos + K.fin), V.X(K.pos + K.len - K.fout)
  V.hy = wt
  for _, hx in ipairs({ V.hfin, V.hfout }) do
    r.ImGui_DrawList_AddRectFilled(dl, hx - 4, wt, hx + 4, wt + 8, C.handle)
  end

  -- gain: a dB box at the right of the strip
  local gtext = "Gain " .. H.amp_db(math.abs(K.vol))
  local gw = r.ImGui_CalcTextSize(ctx, gtext) + 10
  local gx1 = math.min(cx1, V.x + V.w) - 3
  V.gain = nil
  if gx1 - gw > math.max(cx0, V.x) + 40 then
    V.gain = { gx1 - gw, top + 1, gx1, top + STRIP_H - 1 }
    r.ImGui_DrawList_AddRectFilled(dl, gx1 - gw, top + 1, gx1, top + STRIP_H - 1, C.field, 2)
    r.ImGui_DrawList_AddText(dl, gx1 - gw + 5, top + 1, C.value, gtext)
  end

  -- volume envelope: the curve REAPER evaluates, and its points
  V.env_pts = {}
  V.wt, V.wb = wt, wb
  if S.show_env and K.env then
    local mode = r.GetEnvelopeScalingMode(K.env)
    local px, py
    local xa, xb = math.max(cx0, V.x), math.min(cx1, V.x + V.w)
    for x = xa, xb + 2, 3 do
      local xx = math.min(x, xb)
      local _, v = r.Envelope_Evaluate(K.env, K.to_take(V.T(xx)), 0, 0)
      local y = wb - H.amp_to_y(r.ScaleFromEnvelopeMode(mode, v)) * fh
      if px then r.ImGui_DrawList_AddLine(dl, px, py, xx, y, C.accent, 2) end
      px, py = xx, y
    end
    for i = 0, r.CountEnvelopePoints(K.env) - 1 do
      local _, tt, v = r.GetEnvelopePoint(K.env, i)
      local x = V.X(K.from_take(tt))
      local y = wb - H.amp_to_y(r.ScaleFromEnvelopeMode(mode, v)) * fh
      V.env_pts[#V.env_pts + 1] = { i = i, x = x, y = y }
      if x >= V.x - 5 and x <= V.x + V.w + 5 then
        r.ImGui_DrawList_AddCircleFilled(dl, x, y, 4, C.accent)
        r.ImGui_DrawList_AddCircle(dl, x, y, 4, 0x141414FF)
      end
    end
  end

  -- stretch markers: a line down the clip, a triangle in the strip, the rate between them
  V.sms = {}
  if S.show_sm then
    local n = r.GetTakeNumStretchMarkers(S.take)
    local prev
    for i = 0, n - 1 do
      local _, pos, srcpos = r.GetTakeStretchMarker(S.take, i)
      local x = V.X(K.from_take(pos))
      V.sms[#V.sms + 1] = { i = i, x = x, pos = pos, src = srcpos }
      r.ImGui_DrawList_AddLine(dl, x, top + STRIP_H, x, bot, C.marker)
      r.ImGui_DrawList_AddTriangleFilled(dl, x - 5, top + 1, x + 5, top + 1, x, top + STRIP_H - 2, C.marker)
      if prev and pos > prev.pos and x - prev.x > 56 then
        local k = (srcpos - prev.src) / (pos - prev.pos)
        if math.abs(k - 1) > 0.001 then
          local s = string.format("%.2fx", k)
          local tw = r.ImGui_CalcTextSize(ctx, s)
          r.ImGui_DrawList_AddText(dl, (prev.x + x - tw) / 2, top + STRIP_H + 2, C.marker, s)
        end
      end
      prev = V.sms[#V.sms]
    end
  end
end

---------------------------------------------------------------- mouse on the canvas
local M = {}   -- the drag in progress: M.kind and its data

-- what is under the mouse, in order: handles before lines before the wave
function M.hit(mx, my, ruler_y1, wy1)
  if my < ruler_y1 then return { kind = "ruler" } end
  if my > wy1 then return { kind = "scroll" } end
  local g = V.gain
  if g and mx >= g[1] and mx <= g[3] and my >= g[2] and my <= g[4] then return { kind = "gain" } end
  if V.hy and my >= V.hy - 3 and my <= V.hy + 11 then
    if math.abs(mx - V.hfin) <= 6 then return { kind = "fin" } end
    if math.abs(mx - V.hfout) <= 6 then return { kind = "fout" } end
  end
  for _, s in ipairs(V.sms or {}) do
    if math.abs(mx - s.x) <= (my < V.wt and 6 or 3) then return { kind = "sm", idx = s.i } end
  end
  for _, p in ipairs(V.env_pts or {}) do
    if math.abs(mx - p.x) <= 6 and math.abs(my - p.y) <= 6 then return { kind = "pt", idx = p.i } end
  end
  if my < V.wt then return { kind = "strip" } end
  if S.show_env and K.env and mx >= V.X(K.pos) and mx <= V.X(K.pos + K.len) then
    local _, v = r.Envelope_Evaluate(K.env, K.to_take(V.T(mx)), 0, 0)
    local y = V.wb - H.amp_to_y(r.ScaleFromEnvelopeMode(r.GetEnvelopeScalingMode(K.env), v)) * (V.wb - V.wt)
    if math.abs(my - y) <= 5 then return { kind = "line" } end
  end
  return { kind = "wave" }
end

-- the take volume envelope, made when there is none
function M.ensure_env()
  if K.env then return K.env end
  local sel = {}
  for i = 0, r.CountSelectedMediaItems(0) - 1 do sel[#sel + 1] = r.GetSelectedMediaItem(0, i) end
  r.Main_OnCommand(CMD.unselect, 0)
  r.SetMediaItemSelected(S.item, true)
  r.Main_OnCommand(CMD.vol_env, 0)
  r.SetMediaItemSelected(S.item, false)
  for _, it in ipairs(sel) do r.SetMediaItemSelected(it, true) end
  K.env = r.GetTakeEnvelopeByName(S.take, "Volume")
  return K.env
end

function M.add_point(mx, my, shift)
  local env = M.ensure_env()
  if not env then return end
  local mode = r.GetEnvelopeScalingMode(env)
  local tt = K.to_take(V.snap(V.T(mx), shift))
  local amp = H.y_to_amp(H.clamp((V.wb - my) / (V.wb - V.wt), 0, 1))
  r.InsertEnvelopePoint(env, tt, r.ScaleToEnvelopeMode(mode, amp), 0, 0, false, true)
  r.Envelope_SortPoints(env)
  return r.GetEnvelopePointByTime(env, tt + 0.0000001)
end

function M.add_marker(mx, shift)
  local tt = K.to_take(V.snap(V.T(mx), shift))
  if tt <= 0 or tt >= K.len * K.rate then return end
  return r.SetTakeStretchMarker(S.take, -1, tt)
end

function M.press(h, mx, my, alt, shift, right, double)
  local k = h.kind
  M.x0, M.y0, M.moved = mx, my, false
  if right or alt then
    if k == "pt" then r.DeleteEnvelopePointEx(K.env, -1, h.idx); r.Envelope_SortPoints(K.env); H.undo("delete point")
    elseif k == "sm" then r.DeleteTakeStretchMarkers(S.take, h.idx); H.undo("delete stretch marker")
    elseif right and (k == "fin" or k == "fout") then
      local key = k == "fin" and "C_FADEINSHAPE" or "C_FADEOUTSHAPE"
      local shape = (math.floor(r.GetMediaItemInfo_Value(S.item, key)) + 1) % 7
      r.SetMediaItemInfo_Value(S.item, key, shape)
      H.undo("fade shape")
    elseif right then r.ImGui_OpenPopup(ctx, "##menu") end
    return
  end
  if double and k == "gain" then
    r.SetMediaItemTakeInfo_Value(S.take, "D_VOL", 1); H.undo("clip gain"); return
  end
  if double and k == "strip" and S.show_sm then
    local idx = M.add_marker(mx, shift)
    if idx and idx >= 0 then M.kind, M.idx = "sm", idx end
    return
  end
  if k == "line" or (k == "wave" and S.tool == "draw") then
    local idx = M.add_point(mx, my, shift)
    if idx then M.kind, M.idx = "pt", idx end
    return
  end
  if k == "wave" and S.tool == "stretch" then
    S.show_sm = true
    local idx = M.add_marker(mx, shift)
    if idx and idx >= 0 then M.kind, M.idx = "sm", idx end
    return
  end
  M.kind, M.idx = k, h.idx
  M.t0 = V.snap(V.T(mx), shift)
  if k == "scroll" then M.vs0 = S.vs end
  if k == "gain" then M.vol0 = math.abs(K.vol) end
end

function M.drag(mx, my, shift)
  local k = M.kind
  if math.abs(mx - M.x0) > 2 or math.abs(my - M.y0) > 2 then M.moved = true end
  local t = V.snap(V.T(mx), shift)
  if k == "ruler" or k == "wave" or k == "strip" then
    if M.moved then
      local a, b = math.min(M.t0, t), math.max(M.t0, t)
      r.GetSet_LoopTimeRange2(0, true, false, a, b, false)
    end
  elseif k == "scroll" then
    local span = S.ve - S.vs
    local pad = math.max(0.01, K.len * 0.25)
    local full = K.len + 2 * pad
    S.vs = M.vs0 + (mx - M.x0) / V.w * math.max(full, span)
    S.ve = S.vs + span
    V.clamp()
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
  elseif k == "pt" and K.env then
    local env = K.env
    local n = r.CountEnvelopePoints(env)
    local lo = M.idx > 0 and select(2, r.GetEnvelopePoint(env, M.idx - 1)) or 0
    local hi = M.idx < n - 1 and select(2, r.GetEnvelopePoint(env, M.idx + 1)) or K.len * K.rate
    local tt = H.clamp(K.to_take(t), lo, hi)
    local amp = H.y_to_amp(H.clamp((V.wb - my) / (V.wb - V.wt), 0, 1))
    local _, _, _, shape, tension, sel = r.GetEnvelopePoint(env, M.idx)
    r.SetEnvelopePoint(env, M.idx, tt, r.ScaleToEnvelopeMode(r.GetEnvelopeScalingMode(env), amp),
      shape, tension, sel, true)
    r.Envelope_SortPoints(env)
  elseif k == "sm" then
    local n = r.GetTakeNumStretchMarkers(S.take)
    local lo = M.idx > 0 and select(2, r.GetTakeStretchMarker(S.take, M.idx - 1)) + 0.001 or 0
    local hi = M.idx < n - 1 and select(2, r.GetTakeStretchMarker(S.take, M.idx + 1)) - 0.001 or K.len * K.rate
    r.SetTakeStretchMarker(S.take, M.idx, H.clamp(K.to_take(t), lo, hi))
  end
  r.UpdateArrange()
end

function M.release(mx)
  local k = M.kind
  M.kind = nil
  if (k == "ruler" or k == "wave" or k == "strip") and not M.moved then
    r.SetEditCurPos(M.t0, false, false)
    r.GetSet_LoopTimeRange2(0, true, false, 0, 0, false)
  elseif k == "fin" or k == "fout" then H.undo("fade")
  elseif k == "gain" then H.undo("clip gain")
  elseif k == "pt" then H.undo("volume envelope")
  elseif k == "sm" then H.undo("stretch marker") end
end

function M.wheel(mx)
  local v, hz = r.ImGui_GetMouseWheel(ctx)
  if v == 0 and hz == 0 then return end
  local _, ctrl, alt = H.mods()
  local span = S.ve - S.vs
  if ctrl and v ~= 0 then V.zoom(0.8 ^ v, V.T(mx))
  elseif alt and v ~= 0 then S.vzoom = H.clamp(S.vzoom * 1.25 ^ v, 0.25, 16)
  else V.scroll(-(v + hz) * span * 0.1) end
end

-- right-click on an empty spot: the edits
function M.menu()
  if not r.ImGui_BeginPopup(ctx, "##menu") then return end
  local a = H.time_sel()
  if r.ImGui_MenuItem(ctx, a and "Split at time selection" or "Split at edit cursor") then
    H.run(a and CMD.split_sel or CMD.split_cur)
  end
  if r.ImGui_MenuItem(ctx, "Trim to time selection", nil, false, a ~= nil) then H.run(CMD.trim) end
  if r.ImGui_MenuItem(ctx, "Reverse") then H.run(CMD.reverse) end
  if r.ImGui_MenuItem(ctx, "Normalize") then H.run(CMD.normalize) end
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

-- the toolbar over the canvas
function D.toolbar()
  for _, t in ipairs({ { "select", "Select: time selection, edit cursor, handles" },
                       { "draw", "Draw: click anywhere to add volume envelope points" },
                       { "stretch", "Stretch: click the waveform to add stretch markers" } }) do
    if U.key("t" .. t[1], ICON[t[1]], S.tool == t[1], 28, ROW_H, t[2]) then S.tool = t[1]; save() end
    r.ImGui_SameLine(ctx, 0, 1)
  end
  U.gap()
  local a = H.time_sel()
  if U.tkey("split", "Split", false, a and "Split at the time selection (S)" or "Split at the edit cursor (S)") then
    H.run(a and CMD.split_sel or CMD.split_cur)
  end
  if U.tkey("trim", "Trim", false, "Trim the clip to the time selection") and a then H.run(CMD.trim) end
  if U.tkey("rev", "Reverse", K.reversed, "Reverse the clip") then D.want_reverse = true end
  if U.tkey("norm", "Normalize", false, "Normalize the clip") then H.run(CMD.normalize) end
  U.gap()
  if U.tkey("senv", "Volume", S.show_env, "Show the take volume envelope") then S.show_env = not S.show_env; save() end
  if U.tkey("ssm", "Markers", S.show_sm, "Show the stretch markers") then S.show_sm = not S.show_sm; save() end
  U.gap()
  if U.tkey("snap", "Snap", S.snap, "Snap to REAPER's grid (hold Shift for free)") then S.snap = not S.snap; save() end
  if U.tkey("follow", "Follow", S.follow, "Follow the selected clip (off: keep this one)") then S.follow = not S.follow end
  if U.tkey("fit", "Fit", false, "Show the whole clip") then K.fit() end
  local _, div = r.GetSetProjectGrid(0, false)
  local inv = div > 0 and 1 / div or 0
  local s = math.abs(inv - math.floor(inv + 0.5)) < 0.001 and string.format("Grid 1/%d", math.floor(inv + 0.5))
    or string.format("Grid %.3g", div)
  r.ImGui_SameLine(ctx, 0, 16)
  r.ImGui_AlignTextToFramePadding(ctx)
  U.text_col(C.dim, s)
end

-- the canvas: ruler, clip, scrollbar; the mouse
function D.canvas()
  local x, y = r.ImGui_GetCursorScreenPos(ctx)
  local w, h = r.ImGui_GetContentRegionAvail(ctx)
  if w < 40 or h < RULER_H + SCROLL_H + 30 then return end
  V.x, V.w = x, w
  if S.fit then K.fit(); S.fit = false end
  V.pps = w / (S.ve - S.vs)
  local ry1 = y + RULER_H
  local wy0, wy1 = ry1 + 1, y + h - SCROLL_H - 2

  r.ImGui_InvisibleButton(ctx, "##canvas", w, h,
    r.ImGui_ButtonFlags_MouseButtonLeft() | r.ImGui_ButtonFlags_MouseButtonRight())
  local hov = r.ImGui_IsItemHovered(ctx)
  local mx, my = r.ImGui_GetMousePos(ctx)
  local shift, _, alt = H.mods()
  if hov and V.wt then
    local left, right = r.ImGui_IsMouseClicked(ctx, 0), r.ImGui_IsMouseClicked(ctx, 1)
    if left or right then
      M.press(M.hit(mx, my, ry1, wy1), mx, my, alt, shift, right, r.ImGui_IsMouseDoubleClicked(ctx, 0))
    end
    M.wheel(mx)
  end
  if M.kind then
    if r.ImGui_IsMouseDown(ctx, 0) then M.drag(mx, my, shift) else M.release(mx) end
    K.read()
  end
  V.pps = w / (S.ve - S.vs)
  M.menu()

  local dl = r.ImGui_GetWindowDrawList(ctx)
  r.ImGui_DrawList_PushClipRect(dl, x, y, x + w, y + h, true)
  r.ImGui_DrawList_AddRectFilled(dl, x, wy0, x + w, wy1, C.canvas)
  V.ruler(dl, x, y, w, wy0, wy1)
  P.get(x, w)
  V.clip(dl, wy0 + 1, wy1 - 1)

  -- time selection, edit cursor, play position
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

  -- the scrollbar: the view within the clip and a bit around it
  local sy = wy1 + 2
  r.ImGui_DrawList_AddRectFilled(dl, x, sy, x + w, sy + SCROLL_H, C.field)
  local pad = math.max(0.01, K.len * 0.25)
  local lo, hi = K.pos - pad, K.pos + K.len + pad
  local full = math.max(hi - lo, S.ve - S.vs)
  local ta = x + (S.vs - lo) / full * w
  local tb = ta + (S.ve - S.vs) / full * w
  r.ImGui_DrawList_AddRectFilled(dl, math.max(x, ta), sy + 3, math.min(x + w, tb), sy + SCROLL_H - 3,
    M.kind == "scroll" and C.accent or C.seg, 3)
  r.ImGui_DrawList_PopClipRect(dl)

  if hov and not M.kind then
    local hh = M.hit(mx, my, ry1, wy1)
    local tips = { fin = "Fade in: drag (right-click: next shape)", fout = "Fade out: drag (right-click: next shape)",
      gain = "Clip gain: drag up / down (Shift: fine, double-click: 0 dB)",
      sm = "Stretch marker: drag to stretch (Alt / right-click: delete)",
      pt = "Envelope point: drag (Alt / right-click: delete)", line = "Click to add a point" }
    if tips[hh.kind] then r.ImGui_SetTooltip(ctx, tips[hh.kind]) end
    if hh.kind == "fin" or hh.kind == "fout" or hh.kind == "sm" then
      r.ImGui_SetMouseCursor(ctx, r.ImGui_MouseCursor_ResizeEW())
    elseif hh.kind == "gain" then r.ImGui_SetMouseCursor(ctx, r.ImGui_MouseCursor_ResizeNS())
    elseif hh.kind == "pt" or hh.kind == "line" then r.ImGui_SetMouseCursor(ctx, r.ImGui_MouseCursor_Hand()) end
  end
end

-- the left column: the clip's values, as the inspector shows them
function D.left()
  local item, take = S.item, S.take
  local dl = r.ImGui_GetWindowDrawList(ctx)
  local x, y = r.ImGui_GetCursorScreenPos(ctx)
  r.ImGui_DrawList_AddRectFilled(dl, x + 4, y + 2, x + 18, y + 16, H.shade(K.rgb, 0))
  r.ImGui_SetCursorScreenPos(ctx, x + 24, y + 1)
  r.ImGui_Text(ctx, K.name ~= "" and K.name or "(no name)")
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
      -- as REAPER: the source's span stays, the clip gets shorter / longer
      local nr = LO * math.exp(t * SPAN)
      r.SetMediaItemTakeInfo_Value(take, "D_PLAYRATE", nr)
      r.SetMediaItemInfo_Value(item, "D_LENGTH", K.len * K.rate / nr)
      S.fit = true
    end
    if done then H.undo("clip rate") end
  end)
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
  local mute = r.GetMediaItemInfo_Value(item, "B_MUTE") ~= 0
  local pp = r.GetMediaItemTakeInfo_Value(take, "B_PPITCH") ~= 0
  if U.key("loop", "Loop", loop, half, ROW_H, "Loop the source") then
    r.SetMediaItemInfo_Value(item, "B_LOOPSRC", loop and 0 or 1); H.undo("clip loop")
  end
  r.ImGui_SameLine(ctx, 0, 2)
  if U.key("mute", "Mute", mute, half, ROW_H, "Mute the clip") then
    r.SetMediaItemInfo_Value(item, "B_MUTE", mute and 0 or 1); H.undo("clip mute")
  end
  if U.key("ppitch", "Keep pitch", pp, half, ROW_H, "Keep the pitch when the rate changes") then
    r.SetMediaItemTakeInfo_Value(take, "B_PPITCH", pp and 0 or 1); H.undo("preserve pitch")
  end
  r.ImGui_SameLine(ctx, 0, 2)
  if U.key("lrev", "Reverse", K.reversed, half, ROW_H, "Reverse the clip") then D.want_reverse = true end
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
    local src = K.src
    K.reversed = src and r.ValidatePtr(src, "PCM_source*") and select(4, r.PCM_Source_GetSectionInfo(src)) == true
  end
  local title = "AUDIO CLIP"
  if has then
    local tr = r.GetMediaItem_Track(S.item)
    local _, tname = r.GetTrackName(tr)
    local n = r.CountSelectedMediaItems(0)
    title = (n > 1 and S.follow and ("AUDIO CLIPS (" .. n .. ")") or "AUDIO CLIP") .. "  -  " .. K.name
      .. "   (" .. math.floor(r.GetMediaTrackInfo_Value(tr, "IP_TRACKNUMBER")) .. ": " .. tname .. ")"
  end
  U.head(title)
  if not has then
    local item = r.GetSelectedMediaItem(0, 0)
    local take = item and r.GetActiveTake(item)
    D.empty(take and r.TakeIsMIDI(take) and "A MIDI clip: open it in the MIDI editor" or "No audio clip selected")
    return
  end
  D.want_reverse = false
  local nowin = r.ImGui_WindowFlags_NoScrollbar() | r.ImGui_WindowFlags_NoScrollWithMouse()
  if r.ImGui_BeginChild(ctx, "##left", LEFT_W, 0, 0, nowin) then
    D.left()
    r.ImGui_EndChild(ctx)
  end
  r.ImGui_SameLine(ctx, 0, 0)
  local dl = r.ImGui_GetWindowDrawList(ctx)
  local lx, ly = r.ImGui_GetCursorScreenPos(ctx)
  local _, lh = r.ImGui_GetContentRegionAvail(ctx)
  r.ImGui_DrawList_AddRectFilled(dl, lx, ly - 2, lx + 2, ly + lh, C.line)
  r.ImGui_SetCursorScreenPos(ctx, lx + 8, ly)
  if r.ImGui_BeginChild(ctx, "##edit", 0, 0, 0, nowin) then
    D.toolbar()
    r.ImGui_Dummy(ctx, 0, 1)
    D.canvas()
    r.ImGui_EndChild(ctx)
  end
  -- Reverse swaps the take's source: run it after everything that reads the source
  if D.want_reverse then H.run(CMD.reverse); P.key = nil end
end

local function loop()
  r.ImGui_PushFont(ctx, font, 13)
  for _, c in ipairs(STYLE) do r.ImGui_PushStyleColor(ctx, c[1](), c[2]) end
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), 6, 3)
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), 2)
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
  r.ImGui_PopStyleVar(ctx, 2)
  r.ImGui_PopStyleColor(ctx, #STYLE)
  r.ImGui_PopFont(ctx)
  if open then r.defer(loop) end
end

r.atexit(function()
  if cmd_id and cmd_id ~= 0 then
    r.SetToggleCommandState(section_id, cmd_id, 0)
    r.RefreshToolbar2(section_id, cmd_id)
  end
end)
r.defer(loop)
