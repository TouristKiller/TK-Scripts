-- TK Theme Bit - Inspector: Bitwig's inspector panel for REAPER, meant to be docked at the
-- left. It shows what you touched last: a track (name, colour, volume, pan, mute / solo /
-- arm / monitoring, input, output, sends, FX) or a clip (name, colour, position, gain,
-- pan, fades, pitch, rate, mute / loop / reverse, source). TRACK | CLIP at the top picks
-- one by hand; it follows the selection again when you click elsewhere.
--
-- Values: drag a bar left / right (Shift = fine), double-click it for its default.
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

-- Bitwig's inspector: a grey panel, black fields, the fader's brown with an orange edge
local C = {
  bg = 0x1E1E1EFF, field = 0x0E0E0EFF, line = 0x2F2F2FFF, accent = 0xFF6000FF,
  accent_hi = 0xFF7A26FF, fill = 0x562202FF, text = 0xE6E6E6FF, dim = 0x8A8A8AFF,
  head = 0x6E6E6EFF, seg = 0x3A3A3AFF, seg_hi = 0x484848FF,
}
-- Bitwig-like clip / track colours, then "no colour"
local PALETTE = {
  0xD92E24, 0xFF5706, 0xD99D10, 0xC8C81E, 0x739814, 0x009D47, 0x00A694, 0x0099D9,
  0x3E6FD9, 0x5761C6, 0x8D5ACC, 0xC653C3, 0xD9365F, 0xA16E3A, 0x7F7F7F, 0xB8B8B8,
}

local mode = "track"      -- "track" or "clip"
local last_context        -- REAPER's cursor context the last time it changed
local edit_name = {}      -- name fields being typed in, by id
local dock_to             -- set by the dock key: applied before the next Begin

---------------------------------------------------------------- helpers
local function text_col(col, s)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), col)
  r.ImGui_Text(ctx, s)
  r.ImGui_PopStyleColor(ctx)
end

local function header(s)
  r.ImGui_Dummy(ctx, 0, 4)
  local dl = r.ImGui_GetWindowDrawList(ctx)
  local x, y = r.ImGui_GetCursorScreenPos(ctx)
  local w = r.ImGui_GetContentRegionAvail(ctx)
  r.ImGui_DrawList_AddLine(dl, x, y, x + w, y, C.line, 1)
  r.ImGui_Dummy(ctx, 0, 3)
  r.ImGui_PushFont(ctx, font, 11)
  text_col(C.head, s)
  r.ImGui_PopFont(ctx)
end

local function label(s) text_col(C.dim, s) end

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

-- a value bar: dark field, brown fill with an orange edge (from the left, or from the
-- middle when centred), the value as text in it. Drag left / right to change it (Shift
-- fine), double-click for the default. Returns the new t (0..1), moved, done.
local function bar(id, t, text, default, centred)
  local w = r.ImGui_GetContentRegionAvail(ctx)
  local h = 20
  local x, y = r.ImGui_GetCursorScreenPos(ctx)
  r.ImGui_InvisibleButton(ctx, "##" .. id, w, h)
  local new, moved = t, false
  if r.ImGui_IsItemActive(ctx) then
    local dx = r.ImGui_GetMouseDelta(ctx)
    if dx ~= 0 then
      local fine = (r.ImGui_GetKeyMods(ctx) & r.ImGui_Mod_Shift()) ~= 0
      new = math.max(0, math.min(1, t + dx / w * (fine and 0.1 or 1)))
      moved = new ~= t
    end
  end
  local reset = r.ImGui_IsItemHovered(ctx) and r.ImGui_IsMouseDoubleClicked(ctx, 0)
  if reset and default then new, moved = default, true end
  local done = reset or r.ImGui_IsItemDeactivated(ctx)
  local dl = r.ImGui_GetWindowDrawList(ctx)
  r.ImGui_DrawList_AddRectFilled(dl, x, y, x + w, y + h, C.field, 2)
  local a, b = x + 1, x + 1 + new * (w - 2)
  if centred then a, b = math.min(x + w / 2, b), math.max(x + w / 2, b) end
  -- the fader's look: a brown fill with a 2 px orange edge where the value is (for a
  -- centred bar on the side away from the middle)
  local v = x + 1 + new * (w - 2)
  if b - a > 2 then r.ImGui_DrawList_AddRectFilled(dl, a, y + 1, b, y + h - 1, C.fill) end
  local e = (centred and v < x + w / 2) and v or v - 2
  e = math.max(x + 1, math.min(x + w - 3, e))
  r.ImGui_DrawList_AddRectFilled(dl, e, y + 1, e + 2, y + h - 1, C.accent)
  local tw, th = r.ImGui_CalcTextSize(ctx, text)
  r.ImGui_DrawList_AddText(dl, x + w - 6 - tw, y + (h - th) / 2, C.text, text)
  return new, moved, done
end

-- joined buttons, the active one orange; returns the index clicked
local function segmented(id, labels, current, width)
  local picked
  local avail = width or r.ImGui_GetContentRegionAvail(ctx)
  local each = (avail - (#labels - 1)) / #labels
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing(), 1, 0)
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), 2)
  for i, l in ipairs(labels) do
    if i > 1 then r.ImGui_SameLine(ctx) end
    local on = current == i
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), on and C.accent or C.seg)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), on and C.accent_hi or C.seg_hi)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), on and C.accent or C.field)
    if r.ImGui_Button(ctx, l .. "##" .. id .. i, each, 20) then picked = i end
    r.ImGui_PopStyleColor(ctx, 3)
  end
  r.ImGui_PopStyleVar(ctx, 2)
  return picked
end

-- on / off keys side by side (mute, solo, ...): each its own state
local function toggles(id, list)
  local avail = r.ImGui_GetContentRegionAvail(ctx)
  local each = (avail - (#list - 1) * 2) / #list
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing(), 2, 0)
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), 2)
  local clicked
  for i, t in ipairs(list) do
    if i > 1 then r.ImGui_SameLine(ctx) end
    local on_col = t.col or C.accent
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), t.on and on_col or C.seg)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), t.on and on_col or C.seg_hi)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), C.field)
    if r.ImGui_Button(ctx, t.label .. "##" .. id .. i, each, 20) then clicked = i end
    r.ImGui_PopStyleColor(ctx, 3)
  end
  r.ImGui_PopStyleVar(ctx, 2)
  return clicked
end

-- a name field: typing is kept until Enter or leaving the field
local function name_field(id, current, apply)
  local w = r.ImGui_GetContentRegionAvail(ctx)
  r.ImGui_SetNextItemWidth(ctx, w)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), C.field)
  local buf = edit_name[id] or current
  local _, s = r.ImGui_InputText(ctx, "##" .. id, buf)
  if r.ImGui_IsItemActive(ctx) then edit_name[id] = s end
  if r.ImGui_IsItemDeactivatedAfterEdit(ctx) then
    apply(s)
    edit_name[id] = nil
  elseif not r.ImGui_IsItemActive(ctx) then
    edit_name[id] = nil
  end
  r.ImGui_PopStyleColor(ctx)
end

-- colour swatches; the current one outlined. Returns a 0xRRGGBB, false for "none", or nil
local function swatches(current)
  local dl = r.ImGui_GetWindowDrawList(ctx)
  local avail = r.ImGui_GetContentRegionAvail(ctx)
  local per_row = 9
  local s = math.floor((avail - (per_row - 1) * 3) / per_row)
  local picked
  for i = 1, #PALETTE + 1 do
    if (i - 1) % per_row ~= 0 then r.ImGui_SameLine(ctx, 0, 3) end
    local x, y = r.ImGui_GetCursorScreenPos(ctx)
    if r.ImGui_InvisibleButton(ctx, "##sw" .. i, s, s) then
      picked = PALETTE[i] or false
    end
    local col = PALETTE[i]
    if col then
      r.ImGui_DrawList_AddRectFilled(dl, x, y, x + s, y + s, (col << 8) | 0xFF, 2)
    else
      r.ImGui_DrawList_AddRect(dl, x, y, x + s, y + s, C.dim, 2)
      r.ImGui_DrawList_AddLine(dl, x + 3, y + s - 3, x + s - 3, y + 3, C.dim, 1)
    end
    if (col and col == current) or (not col and current == nil) then
      r.ImGui_DrawList_AddRect(dl, x - 1.5, y - 1.5, x + s + 1.5, y + s + 1.5, 0xFFFFFFFF, 2, 0, 1.5)
    end
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, col and "Colour" or "No colour") end
  end
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
    local d = dev == 63 and "All MIDI inputs" or (select(2, r.GetMIDIInputName(dev, "")) or ("MIDI " .. dev))
    return d .. (chan == 0 and "" or (" ch " .. chan))
  end
  local stereo = v & 1024 ~= 0
  local ch = v & 1023
  local a = r.GetInputChannelName(ch) or ("In " .. (ch + 1))
  if stereo then return a .. " / " .. (r.GetInputChannelName(ch + 1) or ("In " .. (ch + 2))) end
  return a
end

local function input_combo(tr)
  local cur = math.floor(r.GetMediaTrackInfo_Value(tr, "I_RECINPUT"))
  r.ImGui_SetNextItemWidth(ctx, (r.ImGui_GetContentRegionAvail(ctx)))
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), C.field)
  -- the arrow box is a button: grey, as everything else here
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), C.seg)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), C.seg_hi)
  local combo_open = r.ImGui_BeginCombo(ctx, "##input", input_name(cur))
  r.ImGui_PopStyleColor(ctx, 2)
  if combo_open then
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
    r.ImGui_EndCombo(ctx)
  end
  r.ImGui_PopStyleColor(ctx)
end

local function draw_track(tr)
  local master = tr == r.GetMasterTrack(0)
  local _, name = r.GetSetMediaTrackInfo_String(tr, "P_NAME", "", false)
  local num = math.floor(r.GetMediaTrackInfo_Value(tr, "IP_TRACKNUMBER"))

  header(master and "MASTER" or ("TRACK " .. num))
  if not master then
    name_field("tname", name, function(s)
      r.GetSetMediaTrackInfo_String(tr, "P_NAME", s, true)
      undo("track name")
    end)
    r.ImGui_Dummy(ctx, 0, 2)
    local pick = swatches(native_rgb(r.GetTrackColor(tr)))
    if pick ~= nil then
      r.SetTrackColor(tr, pick and rgb_native(pick) or 0)
      undo("track colour")
    end
  end

  header("MIX")
  label("Volume")
  local vol = r.GetMediaTrackInfo_Value(tr, "D_VOL")
  local t, moved, done = bar("vol", amp_to_t(vol), amp_db(vol), amp_to_t(1))
  if moved then r.SetMediaTrackInfo_Value(tr, "D_VOL", t_to_amp(t)) end
  if done then undo("track volume") end
  label("Pan")
  local pan = r.GetMediaTrackInfo_Value(tr, "D_PAN")
  local ptxt = math.abs(pan) < 0.005 and "C" or string.format("%d%s", math.floor(math.abs(pan) * 100 + 0.5), pan < 0 and "L" or "R")
  t, moved, done = bar("pan", (pan + 1) / 2, ptxt, 0.5, true)
  if moved then r.SetMediaTrackInfo_Value(tr, "D_PAN", t * 2 - 1) end
  if done then undo("track pan") end
  r.ImGui_Dummy(ctx, 0, 2)
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
    header("ROUTING")
    label("Input")
    input_combo(tr)
    label("Monitoring")
    local mon = math.floor(r.GetMediaTrackInfo_Value(tr, "I_RECMON"))
    local p = segmented("mon", { "Off", "On", "Auto" }, mon + 1)
    if p then r.SetMediaTrackInfo_Value(tr, "I_RECMON", p - 1); undo("monitoring") end
    label("Output")
    local main = r.GetMediaTrackInfo_Value(tr, "B_MAINSEND") ~= 0
    local parent = r.GetParentTrack(tr)
    local out_name = "Master"
    if parent then
      local _, pn = r.GetSetMediaTrackInfo_String(parent, "P_NAME", "", false)
      out_name = (pn ~= "" and pn or "Folder") .. " (parent)"
    end
    p = segmented("out", { out_name, "None" }, main and 1 or 2)
    if p then r.SetMediaTrackInfo_Value(tr, "B_MAINSEND", p == 1 and 1 or 0); undo("output") end
  end

  local sends = r.GetTrackNumSends(tr, 0)
  if sends > 0 then
    header("SENDS")
    for i = 0, sends - 1 do
      local _, sname = r.GetTrackSendName(tr, i, "")
      label(sname)
      local sv = r.GetTrackSendInfo_Value(tr, 0, i, "D_VOL")
      local st, smoved, sdone = bar("send" .. i, amp_to_t(sv), amp_db(sv), amp_to_t(1))
      if smoved then r.SetTrackSendInfo_Value(tr, 0, i, "D_VOL", t_to_amp(st)) end
      if sdone then undo("send level") end
    end
  end

  header("FX")
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
  if n == 0 then label("No FX") end
  r.ImGui_Dummy(ctx, 0, 2)
  if r.ImGui_Button(ctx, "FX chain##fxchain", (r.ImGui_GetContentRegionAvail(ctx)), 20) then
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

local function draw_clip(item)
  local take = r.GetActiveTake(item)
  local count = r.CountSelectedMediaItems(0)
  local midi = take and r.TakeIsMIDI(take)

  header(count > 1 and ("CLIP (" .. count .. " selected)") or (midi and "MIDI CLIP" or "AUDIO CLIP"))
  if take then
    local _, name = r.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)
    name_field("cname", name, function(s)
      for_items(function(_, tk) if tk then r.GetSetMediaItemTakeInfo_String(tk, "P_NAME", s, true) end end)
      undo("clip name")
    end)
  end
  r.ImGui_Dummy(ctx, 0, 2)
  local pick = swatches(native_rgb(math.floor(r.GetMediaItemInfo_Value(item, "I_CUSTOMCOLOR"))))
  if pick ~= nil then
    for_items(function(it) r.SetMediaItemInfo_Value(it, "I_CUSTOMCOLOR", pick and rgb_native(pick) or 0) end)
    undo("clip colour")
  end
  local pos = r.GetMediaItemInfo_Value(item, "D_POSITION")
  local len = r.GetMediaItemInfo_Value(item, "D_LENGTH")
  r.ImGui_Dummy(ctx, 0, 2)
  label("Start  " .. r.format_timestr_pos(pos, "", -1))
  label("Length " .. r.format_timestr_len(len, "", pos, -1))

  if take then
    header("GAIN")
    label("Gain")
    local vol = r.GetMediaItemTakeInfo_Value(take, "D_VOL")
    local t, moved, done = bar("cgain", amp_to_t(math.abs(vol)), amp_db(math.abs(vol)), amp_to_t(1))
    if moved then
      local a = t_to_amp(t)
      for_items(function(_, tk) if tk then r.SetMediaItemTakeInfo_Value(tk, "D_VOL", a) end end)
    end
    if done then undo("clip gain") end
    label("Pan")
    local pan = r.GetMediaItemTakeInfo_Value(take, "D_PAN")
    local ptxt = math.abs(pan) < 0.005 and "C" or string.format("%d%s", math.floor(math.abs(pan) * 100 + 0.5), pan < 0 and "L" or "R")
    t, moved, done = bar("cpan", (pan + 1) / 2, ptxt, 0.5, true)
    if moved then for_items(function(_, tk) if tk then r.SetMediaItemTakeInfo_Value(tk, "D_PAN", t * 2 - 1) end end) end
    if done then undo("clip pan") end
  end

  header("FADES")
  local fmax = math.max(0.001, math.min(len, 10))
  for _, f in ipairs({ { "Fade in", "D_FADEINLEN", "fin" }, { "Fade out", "D_FADEOUTLEN", "fout" } }) do
    label(f[1])
    local v = r.GetMediaItemInfo_Value(item, f[2])
    local t, moved, done = bar(f[3], math.min(1, v / fmax), string.format("%.0f ms", v * 1000), 0)
    if moved then for_items(function(it) r.SetMediaItemInfo_Value(it, f[2], t * fmax) end) end
    if done then undo(f[1]:lower()) end
  end

  if take and not midi then
    header("PITCH & RATE")
    label("Pitch")
    local pitch = r.GetMediaItemTakeInfo_Value(take, "D_PITCH")
    local t, moved, done = bar("pitch", (pitch + 24) / 48, string.format("%+.2f st", pitch), 0.5, true)
    if moved then
      local st = t * 48 - 24
      if (r.ImGui_GetKeyMods(ctx) & r.ImGui_Mod_Shift()) == 0 then st = math.floor(st + 0.5) end
      for_items(function(_, tk) if tk then r.SetMediaItemTakeInfo_Value(tk, "D_PITCH", st) end end)
    end
    if done then undo("clip pitch") end
    label("Rate")
    local rate = r.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE")
    local LO, SPAN = 0.25, math.log(16)
    t, moved, done = bar("rate", math.log(rate / LO) / SPAN, string.format("%.3fx", rate), math.log(1 / LO) / SPAN)
    if moved then
      local nr = LO * math.exp(t * SPAN)
      for_items(function(it, tk)
        if tk then
          -- REAPER keeps the source's span: the item gets shorter / longer with the rate
          local old = r.GetMediaItemTakeInfo_Value(tk, "D_PLAYRATE")
          local l = r.GetMediaItemInfo_Value(it, "D_LENGTH")
          r.SetMediaItemTakeInfo_Value(tk, "D_PLAYRATE", nr)
          r.SetMediaItemInfo_Value(it, "D_LENGTH", l * old / nr)
        end
      end)
    end
    if done then undo("clip rate") end
    local pp = r.GetMediaItemTakeInfo_Value(take, "B_PPITCH") ~= 0
    local p = segmented("ppitch", { "Rate changes pitch", "Keep pitch" }, pp and 2 or 1)
    if p then
      for_items(function(_, tk) if tk then r.SetMediaItemTakeInfo_Value(tk, "B_PPITCH", p == 2 and 1 or 0) end end)
      undo("preserve pitch")
    end
  end

  header("CLIP")
  local mute = r.GetMediaItemInfo_Value(item, "B_MUTE") ~= 0
  local loop = r.GetMediaItemInfo_Value(item, "B_LOOPSRC") ~= 0
  local lock = (math.floor(r.GetMediaItemInfo_Value(item, "C_LOCK")) & 1) ~= 0
  local list = { { label = "Mute", on = mute, col = 0xE0A000FF }, { label = "Loop", on = loop }, { label = "Lock", on = lock } }
  local c = toggles("cflags", list)
  if c == 1 then for_items(function(it) r.SetMediaItemInfo_Value(it, "B_MUTE", mute and 0 or 1) end); undo("clip mute") end
  if c == 2 then for_items(function(it) r.SetMediaItemInfo_Value(it, "B_LOOPSRC", loop and 0 or 1) end); undo("clip loop") end
  if c == 3 then for_items(function(it) r.SetMediaItemInfo_Value(it, "C_LOCK", lock and 0 or 1) end); undo("clip lock") end
  r.ImGui_Dummy(ctx, 0, 2)
  local bw = (r.ImGui_GetContentRegionAvail(ctx) - 2) / 2
  if midi then
    if r.ImGui_Button(ctx, "Open in editor", -1, 20) then r.Main_OnCommand(40153, 0) end
  else
    if r.ImGui_Button(ctx, "Reverse", bw, 20) then r.Main_OnCommand(41051, 0) end   -- Item properties: Toggle take reverse
    r.ImGui_SameLine(ctx, 0, 2)
    if r.ImGui_Button(ctx, "Properties", bw, 20) then r.Main_OnCommand(40009, 0) end -- Item properties
  end

  if take then
    local src = r.GetMediaItemTake_Source(take)
    if src then
      header("SOURCE")
      local file = r.GetMediaSourceFileName(src, "")
      if file ~= "" then
        label(file:match("([^\\/]+)$") or file)
        if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, file) end
      end
      if not midi then
        local sr = r.GetMediaSourceSampleRate(src)
        local ch = r.GetMediaSourceNumChannels(src)
        label(string.format("%.1f kHz, %d ch", sr / 1000, ch))
      end
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
  { r.ImGui_Col_WindowBg, C.bg }, { r.ImGui_Col_Text, C.text }, { r.ImGui_Col_Border, C.line },
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
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), 10, 8)
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
    local p = segmented("mode", { "TRACK", "CLIP" }, mode == "track" and 1 or 2,
      r.ImGui_GetContentRegionAvail(ctx) - 52)
    if p then mode = p == 1 and "track" or "clip" end
    -- dock / float: a small panel icon (its left part filled when docked)
    r.ImGui_SameLine(ctx, 0, 4)
    local docked = r.ImGui_IsWindowDocked(ctx)
    local x, y = r.ImGui_GetCursorScreenPos(ctx)
    if r.ImGui_InvisibleButton(ctx, "##dock", 22, 20) then dock_to = docked and 0 or -1 end
    local dl = r.ImGui_GetWindowDrawList(ctx)
    local hov = r.ImGui_IsItemHovered(ctx)
    r.ImGui_DrawList_AddRectFilled(dl, x, y, x + 22, y + 20, hov and C.seg_hi or C.seg, 2)
    r.ImGui_DrawList_AddRect(dl, x + 5, y + 5, x + 17, y + 15, C.text, 1)
    if docked then r.ImGui_DrawList_AddRectFilled(dl, x + 5, y + 5, x + 9, y + 15, C.accent) end
    if hov then
      r.ImGui_SetTooltip(ctx, docked and "Float the inspector"
        or "Dock the inspector (in REAPER's first docker; set that docker to the left for Bitwig's place)")
    end
    -- close
    r.ImGui_SameLine(ctx, 0, 4)
    x, y = r.ImGui_GetCursorScreenPos(ctx)
    if r.ImGui_InvisibleButton(ctx, "##close", 22, 20) then open = false end
    hov = r.ImGui_IsItemHovered(ctx)
    r.ImGui_DrawList_AddRectFilled(dl, x, y, x + 22, y + 20, hov and C.seg_hi or C.seg, 2)
    r.ImGui_DrawList_AddLine(dl, x + 7, y + 6, x + 15, y + 14, C.text, 1.5)
    r.ImGui_DrawList_AddLine(dl, x + 15, y + 6, x + 7, y + 14, C.text, 1.5)
    if hov then r.ImGui_SetTooltip(ctx, "Close the inspector") end
    if mode == "clip" then
      local item = r.GetSelectedMediaItem(0, 0)
      if item then draw_clip(item) else r.ImGui_Dummy(ctx, 0, 6) label("No clip selected.") end
    else
      local tr = current_track()
      if tr then draw_track(tr) else r.ImGui_Dummy(ctx, 0, 6) label("No track selected.") end
    end
    r.ImGui_End(ctx)
  end
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
