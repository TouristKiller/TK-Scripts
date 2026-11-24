-- TK Theme Bit - settings window (opened from the gear beside the transport display).
-- Laid out like Bitwig's own settings window: large thin tab titles across the top with a
-- close cross, a sidebar of pages (the active one marked with an orange bar), and per page
-- sections: a bold label on the left, rows with their control on the right, segmented
-- pairs of buttons with the active half in orange. Colours measured in Bitwig's window.
--
-- Theme switches are WALTER parameters (ThemeLayout_*); REAPER preferences that belong to
-- the Bitwig look are set through SWS (SNM_*ConfigVar), as REAPER itself can only read them.

local r = reaper
local dir = ({r.get_action_context()})[2]:match("^(.*)[\\/]")

if not r.ImGui_CreateContext then
  r.ShowMessageBox("This window needs ReaImGui (install it through ReaPack).", "TK Theme Bit", 0)
  return
end
do  -- PushFont takes a size since ReaImGui 0.10
  local _, _, version = r.ImGui_GetVersion()
  local major, minor = tostring(version):match("^(%d+)%.(%d+)")
  if not major or (tonumber(major) == 0 and tonumber(minor) < 10) then
    r.ShowMessageBox("This window needs ReaImGui 0.10 or newer (found " .. tostring(version) .. ").",
      "TK Theme Bit", 0)
    return
  end
end
local has_sws = r.SNM_GetIntConfigVar ~= nil

local ctx = r.ImGui_CreateContext("TK Theme Bit settings")
local font = r.ImGui_CreateFont("Inter")
r.ImGui_Attach(ctx, font)

-- Bitwig's settings window, measured: background 19, lines 47, orange 255/96/0,
-- inactive text 130, dropdown / field 45, value box 187
local C = {
  bg = 0x131313FF, line = 0x2F2F2FFF, accent = 0xFF6000FF, accent_hi = 0xFF7A26FF,
  text = 0xF2F2F2FF, dim = 0x828282FF, seg = 0x3A3A3AFF, seg_hi = 0x484848FF,
  field = 0x2D2D2DFF, valuebox = 0xBBBBBBFF, dark = 0x131313FF,
}
local W, H = 760, 520
local SIDEBAR = 170
local LABEL_COL = 110      -- section labels; the rows start here
local ROW_LABEL_W = 135    -- the rows' own labels; the controls start after them

---------------------------------------------------------------- theme parameters
local function theme_param(name)
  local i = 0
  while true do
    local retval, _, value = r.ThemeLayout_GetParameter(i)
    if not retval then return nil end
    if retval == name then return i, value end
    i = i + 1
  end
end

local function set_theme_param(name, value)
  local idx = theme_param(name)
  if not idx then return false end
  r.ThemeLayout_SetParameter(idx, value, true)
  r.ThemeLayout_RefreshAll()
  return true
end

---------------------------------------------------------------- REAPER preferences
-- labelitems2: flag 8 = draw item labels ABOVE items (from the user's reaper.ini:
-- 1039 with it on, 1031 after switching it off in Preferences)
local LABEL_ABOVE = 8

local function labels_above()
  return (r.SNM_GetIntConfigVar("labelitems2", 0) & LABEL_ABOVE) ~= 0
end

local function set_labels_above(on)
  local v = r.SNM_GetIntConfigVar("labelitems2", 0)
  v = on and (v | LABEL_ABOVE) or (v & ~LABEL_ABOVE)
  r.SNM_SetIntConfigVar("labelitems2", v)
  r.UpdateArrange()
end

-- deftrackvol: the default fader gain for new tracks, as amplitude (0.316 = -10 dB)
local function default_volume_db()
  local amp = r.SNM_GetDoubleConfigVar("deftrackvol", 1)
  if amp <= 0 then return -150 end
  return 20 * math.log(amp, 10)
end

local function set_default_volume_db(db)
  r.SNM_SetDoubleConfigVar("deftrackvol", 10 ^ (db / 20))
end

---------------------------------------------------------------- contrast (REAPER's colour controls)
-- REAPER's own colour processing for the whole theme, images included (as TK Theme's
-- Colour processing page): parameters below zero, on Default 7's -100..100 scale. Bitwig's
-- sliders start at 0, so they use the upper half: 0 = untouched.
local MIDTONES, SHADOWS = -1002, -1001
local PROCESSING = {
  { -1000, "Gamma", 25, 200 }, { -1003, "Highlights", -100, 100 },
  { -1004, "Saturation", 0, 200 }, { -1005, "Tint", -180, 180 },
}
local PROCESS_CUSTOM = -1006    -- also affect the project's track colours

---------------------------------------------------------------- REAPER view / layout
-- Bitwig's "Playhead follow mode": REAPER's continuous scrolling (found by its name, so a
-- renumbered action still works); off = scroll by pages
local CONTINUOUS_NAME = "View: Continuous scrolling during playback"
local continuous_cmd
local function continuous_command()
  if continuous_cmd == nil then
    continuous_cmd = false
    if r.kbd_getTextFromCmd(41817, 0) == CONTINUOUS_NAME then
      continuous_cmd = 41817
    else
      for id = 40000, 43999 do
        if r.kbd_getTextFromCmd(id, 0) == CONTINUOUS_NAME then continuous_cmd = id break end
      end
    end
  end
  return continuous_cmd
end

-- Bitwig's "Scaling": the theme's layout for every section. Auto lets REAPER pick by the
-- screen's scaling (layout_dpi_translate); 150 / 200 force the larger image sets
local SCALE_LAYOUTS = { "", "150%_A", "200%_A" }
local LAYOUT_SECTIONS = { "tcp", "mcp", "envcp", "trans", "master_tcp", "master_mcp" }

local function theme_scale()
  local _, name = r.ThemeLayout_GetLayout("tcp", -1)
  for i, l in ipairs(SCALE_LAYOUTS) do if l ~= "" and l == name then return i end end
  return 1
end

local function set_theme_scale(i)
  for _, sec in ipairs(LAYOUT_SECTIONS) do r.ThemeLayout_SetLayout(sec, SCALE_LAYOUTS[i]) end
  r.ThemeLayout_RefreshAll()
  r.TrackList_AdjustWindows(false)
end

local function contrast_get(id)
  local name, _, value, _, min, max = r.ThemeLayout_GetParameter(id)
  if not name or max == min then return nil end
  local shown = math.floor(-100 + (value - min) / (max - min) * 200 + 0.5)
  return math.max(0, math.min(100, shown))
end

local function contrast_set(id, shown, persist)
  local name, _, _, _, min, max = r.ThemeLayout_GetParameter(id)
  if not name or max == min then return end
  r.ThemeLayout_SetParameter(id, math.floor(min + (shown + 100) / 200 * (max - min) + 0.5), persist)
  r.ThemeLayout_RefreshAll()
end

---------------------------------------------------------------- arrange colours and clip font
-- Timeline background, beat grid colour / lines and the clip header size are colours and a
-- font in the theme's colour file. They show at once (SetThemeColor) and are written to the
-- loose .ReaperTheme next to the zip, as TK Theme does; a zip can't be written, so the loose
-- file becomes the loaded one. The choices are also kept in an ExtState, so they come back
-- when a theme update or rebuild replaces that file (checked when this window opens).
local EXT = "TK Theme Bit"
local LOOK_DEFAULT = { timeline = 100, grid_white = 0, grid_lines = 100, headers = 0 }
-- mi_font, Inter: small 10 px / 500 as the theme ships, large 13 px / 600 (LOGFONT hex)
local MI_FONT = {
  [0] = "F6FFFFFF000000000000000000000000F40100000000000003020102496E746572000000000000000000000000000000000000000000000000000000F2",
  [1] = "F3FFFFFF000000000000000000000000580200000000000003020102496E74657200000000000000000000000000000000000000000000000000000054",
}

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

local function bit_active()
  return (r.GetLastColorThemeFile() or ""):find("TK Theme Bit", 1, true) ~= nil
end

-- the theme's loose colour file (the zip's sibling)
local function loose_file()
  local path = (r.GetLastColorThemeFile() or ""):gsub("Zip$", "")
  if path:match("%.ReaperTheme$") and read_all(path) then return path end
  return nil
end

local function look_load()
  local s = {}
  for k, v in pairs(LOOK_DEFAULT) do
    s[k] = tonumber(r.GetExtState(EXT, "look_" .. k)) or v
  end
  return s
end

local function look_store(s)
  for k in pairs(LOOK_DEFAULT) do r.SetExtState(EXT, "look_" .. k, tostring(s[k]), true) end
end

local function clamp(v) return math.max(0, math.min(255, math.floor(v + 0.5))) end

-- the colours, worked out from the choices: the lanes' grey from Timeline background; the
-- grid lines from that grey towards black (the shipped ratios: measures 4, beats 14, between
-- 20 on a lane of 26) or towards white, by Beat grid lines
local function look_colours(s)
  local bg = 2 + s.timeline * 0.24
  local target
  if s.grid_white == 1 then
    target = { bg + 40, bg + 24, bg + 14 }
  else
    target = { bg * 0.15, bg * 0.54, bg * 0.77 }
  end
  local t = s.grid_lines / 100
  local function line(i) return clamp(bg + (target[i] - bg) * t) end
  return {
    col_tr1_bg = clamp(bg), col_tr2_bg = clamp(bg),
    selcol_tr1_bg = clamp(bg + 6), selcol_tr2_bg = clamp(bg + 6),
    col_gridlines2 = line(1), col_gridlines3 = line(2), col_gridlines = line(3),
  }
end

-- live: REAPER redraws the arrange in the new colours (lost on a restart unless saved)
local function look_show(s)
  for key, g in pairs(look_colours(s)) do r.SetThemeColor(key, r.ColorToNative(g, g, g), 0) end
  r.UpdateArrange()
  r.UpdateTimeline()
end

-- the colour file with the choices in it (the file holds red in its low byte; greys don't care)
local function look_text(text, s)
  for key, g in pairs(look_colours(s)) do
    text = text:gsub("([\r\n]" .. key .. "=)(-?%d+)", function(head, old)
      local v = (tonumber(old) & 0xFF000000) | g | (g << 8) | (g << 16)
      if v >= 0x80000000 then v = v - 0x100000000 end
      return head .. v
    end, 1)
  end
  text = text:gsub("([\r\n]mi_font=)%x+", "%1" .. MI_FONT[s.headers], 1)
  return text
end

-- write the file and make it the loaded theme when it changed or a reload is wanted
-- (a new font only shows after one); returns false when the file can't be found / written
local function look_save(s, reload)
  look_store(s)
  local path = loose_file()
  local text = path and read_all(path)
  if not text then return false end
  local new = look_text(text, s)
  if new ~= text and not write_all(path, new) then return false end
  local zip_loaded = (r.GetLastColorThemeFile() or ""):match("Zip$") ~= nil
  if reload or zip_loaded then r.OpenColorThemeFile(path) end
  return true
end

-- after a theme update or rebuild the file is back to the shipped look: bring the choices back
local function look_restore()
  if not bit_active() then return end
  local stored = false
  for k in pairs(LOOK_DEFAULT) do
    if r.HasExtState(EXT, "look_" .. k) then stored = true end
  end
  if not stored then return end
  local s = look_load()
  local path = loose_file()
  local text = path and read_all(path)
  if text and look_text(text, s) ~= text then look_save(s, true) end
end

---------------------------------------------------------------- meters
-- I_VUMODE per track: &30 picks the meter (0 stereo peaks, 8 combined RMS = peak with RMS,
-- 12 LUFS-M); &1 (meter off) and &32 (LUFS on 1+2) are left alone
local METER_MODES = { 0, 8, 12 }

local function meter_mode()
  local m = math.floor(r.GetMediaTrackInfo_Value(r.GetMasterTrack(0), "I_VUMODE")) & 30
  for i, v in ipairs(METER_MODES) do if v == m then return i end end
  return 0
end

local function set_meter_mode(i)
  local mode = METER_MODES[i]
  r.Undo_BeginBlock()
  local function set(tr)
    local v = math.floor(r.GetMediaTrackInfo_Value(tr, "I_VUMODE"))
    r.SetMediaTrackInfo_Value(tr, "I_VUMODE", (v & ~30) | mode)
  end
  set(r.GetMasterTrack(0))
  for t = 0, r.CountTracks(0) - 1 do set(r.GetTrack(0, t)) end
  r.Undo_EndBlock("TK Theme Bit: set all meters", -1)
end

---------------------------------------------------------------- widgets
local function text_col(col, s, wrap)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), col)
  if wrap then r.ImGui_TextWrapped(ctx, s) else r.ImGui_Text(ctx, s) end
  r.ImGui_PopStyleColor(ctx)
end

local function hline()
  local dl = r.ImGui_GetWindowDrawList(ctx)
  local x, y = r.ImGui_GetCursorScreenPos(ctx)
  local w = r.ImGui_GetContentRegionAvail(ctx)
  r.ImGui_DrawList_AddLine(dl, x, y, x + w, y, C.line, 1)
  r.ImGui_Dummy(ctx, w, 1)
end

-- a segmented pair (or more): joined buttons, the active one orange; every part as wide
-- as the widest label needs, so no text is cut off
local function segmented(id, labels, current)
  local picked
  local each = 0
  for _, label in ipairs(labels) do
    each = math.max(each, r.ImGui_CalcTextSize(ctx, label) + 28)
  end
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing(), 1, 0)
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), 2)
  for i, label in ipairs(labels) do
    if i > 1 then r.ImGui_SameLine(ctx) end
    local on = (current == i)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), on and C.accent or C.seg)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), on and C.accent_hi or C.seg_hi)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), on and C.accent or C.field)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), C.text)
    if r.ImGui_Button(ctx, label .. "##" .. id .. i, each, 22) then picked = i end
    r.ImGui_PopStyleColor(ctx, 4)
  end
  r.ImGui_PopStyleVar(ctx, 2)
  return picked
end

-- a plain grey action button
local function action_button(label, width)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), C.seg)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), C.seg_hi)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), C.field)
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), 2)
  local hit = r.ImGui_Button(ctx, label, width or 0, 22)
  r.ImGui_PopStyleVar(ctx)
  r.ImGui_PopStyleColor(ctx, 3)
  return hit
end

-- Bitwig's value slider: a black bar filled brown up to the value with an orange outline
-- (at 0 only its orange left edge), then a light grey box with the number. Drag or click
-- to set, right-click for the default. Returns the value, whether it moved, and whether
-- the edit ended (release or reset), for the expensive part to happen only then.
local BAR_W, BAR_H, BOX_W = 140, 20, 40
local function bar_slider(id, value, lo, hi, default)
  local x, y = r.ImGui_GetCursorScreenPos(ctx)
  r.ImGui_InvisibleButton(ctx, "##" .. id, BAR_W, BAR_H)
  local new = value
  if r.ImGui_IsItemActive(ctx) then
    local mx = r.ImGui_GetMousePos(ctx)
    local t = math.max(0, math.min(1, (mx - x) / BAR_W))
    new = math.floor(lo + t * (hi - lo) + 0.5)
  end
  local reset = r.ImGui_IsItemClicked(ctx, 1)
  if reset then new = default end
  local done = reset or r.ImGui_IsItemDeactivated(ctx)
  local dl = r.ImGui_GetWindowDrawList(ctx)
  r.ImGui_DrawList_AddRectFilled(dl, x, y, x + BAR_W, y + BAR_H, 0x0A0A0AFF, 2)
  local fx = x + 1 + (new - lo) / (hi - lo) * (BAR_W - 2)
  -- the fader's look: a brown fill with a 2 px orange edge where the value is
  if fx > x + 3 then
    r.ImGui_DrawList_AddRectFilled(dl, x + 1, y + 1, fx, y + BAR_H - 1, 0x562202FF)
    r.ImGui_DrawList_AddRectFilled(dl, fx - 2, y + 1, fx, y + BAR_H - 1, C.accent)
  else
    r.ImGui_DrawList_AddRectFilled(dl, x + 1, y + 1, x + 3, y + BAR_H - 1, C.accent)
  end
  r.ImGui_SameLine(ctx, 0, 6)
  local bx, by = r.ImGui_GetCursorScreenPos(ctx)
  r.ImGui_Dummy(ctx, BOX_W, BAR_H)
  r.ImGui_DrawList_AddRectFilled(dl, bx, by, bx + BOX_W, by + BAR_H, C.valuebox, 2)
  local label = tostring(new)
  local tw, th = r.ImGui_CalcTextSize(ctx, label)
  r.ImGui_DrawList_AddText(dl, bx + BOX_W - 6 - tw, by + (BAR_H - th) / 2, C.dark, label)
  return new, new ~= value, done
end

-- one row: its label in the row column, its control in the column after it
local function row(label, draw_control)
  local x0 = r.ImGui_GetCursorPosX(ctx)
  r.ImGui_SetCursorPosX(ctx, x0 + LABEL_COL)
  r.ImGui_AlignTextToFramePadding(ctx)
  text_col(C.text, label)
  r.ImGui_SameLine(ctx)
  r.ImGui_SetCursorPosX(ctx, x0 + LABEL_COL + ROW_LABEL_W)
  draw_control()
end

-- a section: its label in the left column, then its rows, then a line
local function section(title, rows)
  local y = r.ImGui_GetCursorPosY(ctx)
  r.ImGui_AlignTextToFramePadding(ctx)
  r.ImGui_PushFont(ctx, font, 13)
  text_col(C.text, title)
  r.ImGui_PopFont(ctx)
  r.ImGui_SetCursorPosY(ctx, y)
  rows()
  r.ImGui_Spacing(ctx)
  hline()
  r.ImGui_Spacing(ctx)
end

local function note(s)
  r.ImGui_SetCursorPosX(ctx, r.ImGui_GetCursorPosX(ctx) + LABEL_COL + ROW_LABEL_W)
  r.ImGui_PushTextWrapPos(ctx, 0)
  text_col(C.dim, s, true)
  r.ImGui_PopTextWrapPos(ctx)
end

---------------------------------------------------------------- Saxmand's device panel
-- the DEVICES key opens Saxmand's FX Modulator Linking; whether it is installed is read
-- once from REAPER's action list. Not installed: the key is switched off once, so a new
-- user doesn't get a key that only says "not installed" (switching it on stays possible)
local saxmand
-- a registered script's command, found by its file name in REAPER's action list (read once
-- per file: reaper-kb.ini is large and pages draw every frame)
local script_cmds = {}
local function script_command(file)
  if script_cmds[file] == nil then
    script_cmds[file] = false
    for line in (read_all(r.GetResourcePath() .. "/reaper-kb.ini") or ""):gmatch("[^\r\n]+") do
      local id = line:match("^SCR %d+ %d+ (%S+) ")
      if id and line:find(file, 1, true) then
        local cmd = r.NamedCommandLookup("_" .. id)
        if cmd ~= 0 then script_cmds[file] = cmd break end
      end
    end
  end
  return script_cmds[file] or nil
end

local function saxmand_found()
  if saxmand == nil then
    saxmand = ((read_all(r.GetResourcePath() .. "/reaper-kb.ini") or "")
      :find("Saxmand_FX Modulator Linking.lua", 1, true)) ~= nil
  end
  return saxmand
end

local function devices_first_run()
  if r.GetExtState(EXT, "devices_checked") == "1" or not bit_active() then return end
  r.SetExtState(EXT, "devices_checked", "1", true)
  if not saxmand_found() and r.GetExtState(EXT, "devices_action") == "" then
    set_theme_param("bitTransDevices", 0)
  end
end
-- the Other action choice before an ID is typed, and the ID being typed
local devices_other, devices_typed

---------------------------------------------------------------- pages
local function page_transport()
  section("Transport", function()
    local idx, value = theme_param("bitTransReaper")
    if idx then
      row("Transport keys", function()
        local p = segmented("trans", { "Bitwig", "+ REAPER keys" }, value == 0 and 1 or 2)
        if p then set_theme_param("bitTransReaper", p == 1 and 0 or 1) end
      end)
      note("Bitwig: play, stop, record. With REAPER keys: rewind, pause and forward as well.")
      local ridx, rvalue = theme_param("bitTransRate")
      if ridx then
        r.ImGui_Spacing(ctx)
        row("Play rate", function()
          local p = segmented("rate", { "Off", "In the display" }, rvalue == 0 and 1 or 2)
          if p then set_theme_param("bitTransRate", p == 1 and 0 or 1) end
        end)
        note("Bitwig has no play rate; this adds its value and a small slider to the display.")
      end
      local cidx, cvalue = theme_param("bitTransCenter")
      if cidx then
        r.ImGui_Spacing(ctx)
        row("Display", function()
          local p = segmented("center", { "After the keys", "Centred" }, cvalue == 0 and 1 or 2)
          if p then set_theme_param("bitTransCenter", p == 1 and 0 or 1) end
        end)
      end
      local lidx, lvalue = theme_param("bitTransLogo")
      if lidx then
        r.ImGui_Spacing(ctx)
        row("Logo", function()
          local p = segmented("logo", { "Off", "Over the display" }, lvalue == 0 and 1 or 2)
          if p then set_theme_param("bitTransLogo", p == 1 and 0 or 1) end
        end)
        note("Bit's dot mark over the display, in the style of Bitwig's logo. The bar grows a little to make room.")
      end
      local vidx, vvalue = theme_param("bitTransViews")
      if vidx then
        r.ImGui_Spacing(ctx)
        row("View keys", function()
          local p = segmented("views", { "Off", "Arrange / Mix / Edit" }, vvalue == 0 and 1 or 2)
          if p then set_theme_param("bitTransViews", p == 1 and 0 or 1) end
        end)
        note("At the right end of the bar: ARRANGE closes the mixer and MIDI editor, MIX shows the mixer, "
          .. "EDIT opens the selected MIDI item. They hide on a bar too narrow for them.")
      end
      -- the inspector: its key in the transport, and a button to open / close it here
      local iidx, ivalue = theme_param("bitTransInsp")
      if iidx then
        r.ImGui_Spacing(ctx)
        row("Inspector key", function()
          local p = segmented("insp", { "Off", "Shown" }, ivalue == 0 and 1 or 2)
          if p then set_theme_param("bitTransInsp", p == 1 and 0 or 1) end
        end)
        local cmd = script_command("TK_Theme_Bit_Inspector.lua")
        if cmd then
          local open = r.GetToggleCommandState(cmd) == 1
          row("Inspector", function()
            if action_button(open and "Close inspector" or "Open inspector", 140) then r.Main_OnCommand(cmd, 0) end
          end)
        end
        note("The track or clip you touched last, like Bitwig's inspector. Dock it with the icon at its top.")
      end
      local didx, dvalue = theme_param("bitTransDevices")
      if didx then
        r.ImGui_Spacing(ctx)
        row("Devices key", function()
          local p = segmented("devices", { "Off", "Shown" }, dvalue == 0 and 1 or 2)
          if p then set_theme_param("bitTransDevices", p == 1 and 0 or 1) end
        end)
        -- what it opens: Saxmand's script, or any action (ExtState devices_action)
        local own = r.GetExtState(EXT, "devices_action")
        local other = own ~= "" or devices_other
        r.ImGui_Spacing(ctx)
        row("Devices key opens", function()
          local p = segmented("devwhat", { "Saxmand", "Other action" }, other and 2 or 1)
          if p == 1 then
            r.DeleteExtState(EXT, "devices_action", true)
            devices_other = false
          elseif p == 2 then
            devices_other = true
          end
        end)
        if other then
          row("Action ID", function()
            r.ImGui_SetNextItemWidth(ctx, 260)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), C.field)
            local _, s = r.ImGui_InputTextWithHint(ctx, "##devid", "_RS... or a number", devices_typed or own)
            if r.ImGui_IsItemActive(ctx) then devices_typed = s end
            if r.ImGui_IsItemDeactivatedAfterEdit(ctx) then
              s = s:gsub("^%s+", ""):gsub("%s+$", "")
              if s == "" then r.DeleteExtState(EXT, "devices_action", true)
              else r.SetExtState(EXT, "devices_action", s, true) end
              devices_typed = nil
            end
            r.ImGui_PopStyleColor(ctx)
          end)
          local id = r.GetExtState(EXT, "devices_action")
          local cmd = id ~= "" and (tonumber(id) or r.NamedCommandLookup(id)) or 0
          if id == "" then
            note("Paste an action's command ID (Actions list: right-click > Copy selected action command ID).")
          elseif cmd and cmd > 0 then
            note("Opens: " .. r.kbd_getTextFromCmd(math.floor(cmd), 0))
          else
            note("REAPER doesn't know this action.")
          end
        else
          note(saxmand_found()
            and "DEVICES opens Saxmand's FX Modulator Linking, a device panel like Bitwig's."
            or "DEVICES opens Saxmand's FX Modulator Linking, which isn't installed: get it from Saxmand's ReaPack repository, or choose Other action.")
        end
      end
    else
      note("TK Theme Bit is not the active theme.")
    end
  end)
end

local look = look_load()
local look_msg

local function look_changed(moved, done)
  if moved then look_show(look) end
  if done and not look_save(look, false) then
    look_msg = "The theme's .ReaperTheme file was not found next to its zip, so this lasts until REAPER restarts."
  end
end

local function page_display()
  if not bit_active() then
    section("Contrast", function() note("TK Theme Bit is not the active theme.") end)
    return
  end
  section("Contrast", function()
    for _, c in ipairs({ { "Midtones", MIDTONES }, { "Black level", SHADOWS } }) do
      local v = contrast_get(c[2])
      if v then
        row(c[1], function()
          local new, moved, done = bar_slider("c" .. c[2], v, 0, 100, 0)
          if moved or done then contrast_set(c[2], new, done) end
        end)
      end
    end
    row("Timeline Background", function()
      local new, moved, done = bar_slider("tl", look.timeline, 0, 100, LOOK_DEFAULT.timeline)
      look.timeline = new
      look_changed(moved, done)
    end)
    row("Beat Grid Color", function()
      local p = segmented("gridcol", { "Black", "White" }, look.grid_white + 1)
      if p then
        look.grid_white = p - 1
        look_changed(true, true)
      end
    end)
    row("Beat Grid Lines", function()
      local new, moved, done = bar_slider("gl", look.grid_lines, 0, 100, LOOK_DEFAULT.grid_lines)
      look.grid_lines = new
      look_changed(moved, done)
    end)
    note("Midtones and Black level are REAPER's own colour controls and work on the whole theme. "
      .. "Right-click a slider for its default.")
    if look_msg then note(look_msg) end
  end)
  section("Colour", function()
    -- the rest of REAPER's colour processing, as TK Theme's Colour processing page,
    -- on Default 7's scales
    for _, c in ipairs(PROCESSING) do
      local id, label, lo, hi = c[1], c[2], c[3], c[4]
      local name, _, value, def, min, max = r.ThemeLayout_GetParameter(id)
      if name and max ~= min then
        local function shown(raw) return math.floor(lo + (raw - min) / (max - min) * (hi - lo) + 0.5) end
        row(label, function()
          local new, moved, done = bar_slider("p" .. id, shown(value), lo, hi, shown(def))
          if moved or done then
            r.ThemeLayout_SetParameter(id, math.floor(min + (new - lo) / (hi - lo) * (max - min) + 0.5), done)
            r.ThemeLayout_RefreshAll()
          end
        end)
      end
    end
    local name, _, value = r.ThemeLayout_GetParameter(PROCESS_CUSTOM)
    if name then
      row("Track colours", function()
        local p = segmented("pcustom", { "Untouched", "Processed too" }, value ~= 0 and 2 or 1)
        if p and (p == 2) ~= (value ~= 0) then
          r.ThemeLayout_SetParameter(PROCESS_CUSTOM, p == 2 and 1 or 0, true)
          r.ThemeLayout_RefreshAll()
        end
      end)
    end
  end)
end

local function page_arrange()
  section("Clips", function()
    if has_sws then
      row("Item names", function()
        local p = segmented("labels", { "In the item", "Above" }, labels_above() and 2 or 1)
        if p then set_labels_above(p == 2) end
      end)
      note("In the item, the name sits in the clip's header row on the clip colour, as in Bitwig.")
    else
      note("Needs SWS. In REAPER: Preferences > Appearance > Media item labels.")
    end
    if bit_active() then
      r.ImGui_Spacing(ctx)
      row("Clip Headers", function()
        local p = segmented("headers", { "Small", "Large" }, look.headers + 1)
        if p and p - 1 ~= look.headers then
          look.headers = p - 1
          if not look_save(look, true) then
            look_msg = "The theme's .ReaperTheme file was not found next to its zip."
          end
        end
      end)
      note("The item name's size; the theme reloads for a moment to change it.")
    end
  end)
  section("Playback", function()
    local cmd = continuous_command()
    if cmd then
      local on = r.GetToggleCommandState(cmd) == 1
      row("Playhead follow mode", function()
        local p = segmented("follow", { "Scroll by pages", "Continuous" }, on and 2 or 1)
        if p and (p == 2) ~= on then r.Main_OnCommand(cmd, 0) end
      end)
      note("How the view follows the playhead while the follow key in the display is on.")
    else
      note("REAPER's continuous scrolling action was not found.")
    end
  end)
end

local function page_tracks()
  section("Volume", function()
    if has_sws then
      local db = default_volume_db()
      local cur = math.abs(db + 10) < 0.05 and 2 or (math.abs(db) < 0.05 and 1 or 0)
      row("New tracks", function()
        local p = segmented("vol", { "0 dB", "-10 dB" }, cur)
        if p then set_default_volume_db(p == 1 and 0 or -10) end
      end)
      note(string.format("Now %.1f dB. Bitwig starts tracks at -10 dB, to keep headroom on the master.", db))
    else
      note("Needs SWS. In REAPER: Preferences > Project > Track/send defaults.")
    end
    r.ImGui_Spacing(ctx)
    row("Selected tracks", function()
      if action_button("Set to -10 dB") then dofile(dir .. "/TK_Theme_Bit_Tracks_Minus10.lua") end
    end)
    note("A double click on a fader resets it to 0 dB; REAPER has no setting for that.")
    local vidx, vvalue = theme_param("bitTcpVol")
    if vidx then
      r.ImGui_Spacing(ctx)
      row("Track list volume", function()
        local p = segmented("tcpvol", { "Numeric", "Slider" }, vvalue == 0 and 1 or 2)
        if p then set_theme_param("bitTcpVol", p == 1 and 0 or 1) end
      end)
    end
  end)
  section("Meters", function()
    row("Meter mode", function()
      local p = segmented("meter", { "Peak", "Peak/RMS", "LUFS-M" }, meter_mode())
      if p then set_meter_mode(p) end
    end)
    note("Sets every track and the master in this project. REAPER has no K-20 meter; "
      .. "new tracks start with peaks.")
  end)
  section("Numbers", function()
    local idx, value = theme_param("bitMcpNum")
    if idx then
      row("Mixer", function()
        local p = segmented("mcpnum", { "Off", "In the name block" }, value == 0 and 1 or 2)
        if p then set_theme_param("bitMcpNum", p == 1 and 0 or 1) end
      end)
      note("Bitwig shows no track numbers; these add small ones (mixer: top left of the name block, track list: in the colour strip).")
    end
    local tidx, tvalue = theme_param("bitTcpNum")
    if tidx then
      r.ImGui_Spacing(ctx)
      row("Track list", function()
        local p = segmented("tcpnum", { "Off", "In the colour strip" }, tvalue == 0 and 1 or 2)
        if p then set_theme_param("bitTcpNum", p == 1 and 0 or 1) end
      end)
    else
      note("TK Theme Bit is not the active theme.")
    end
  end)
end

local IS_WINDOWS = r.GetOS():find("Win", 1, true) ~= nil

-- Windows dark mode: REAPER draws its own windows (Media Explorer, FX chain, actions,
-- routing, menus) in 23 colours from reaper.ini, win32_darkmode_colors, for every theme
-- (TK Theme's dark mode page writes them too). Slots as TK Theme names them: menu bar
-- bg / hover / text / disabled, title bar, main, list bg, edit fields, list text, disabled
-- text, window border, borders, group boxes, column header bg / text, selected text,
-- tab bg / selected, system windows, selected row, selected inactive, grid lines, focus.
-- Bitwig's: greys, black lists and fields, selection in the fader's brown, orange focus.
-- REAPER reads them at start-up, so a change needs a restart.
local DARK = {}
-- Slot 7 is "Dark mode color child": what Windows paints behind child windows. The docked
-- mixer only draws its strips, so its empty part shows this, not col_mixerbg (proven with
-- a probe that painted col_mixerbg magenta: the area stayed as it was). So it is the
-- theme's own mixer / track list black, 020202; lists in REAPER's windows share it.
DARK.BIT = "1e1e1e 3a3a3a d2d2d2 6e6e6e 1e1e1e 242424 020202 0e0e0e c8c8c8 6e6e6e 0a0a0a "
  .. "3a3a3a 3a3a3a 262626 a0a0a0 ffffff 1e1e1e 3a3a3a 242424 562202 333333 202020 ff8000"
-- earlier Bitwig sets: still "Bitwig" (switching from one doesn't make it the Previous)
DARK.OLD = {
  "1e1e1e 3a3a3a d2d2d2 6e6e6e 1e1e1e 242424 161616 0e0e0e c8c8c8 6e6e6e 0a0a0a "
    .. "3a3a3a 3a3a3a 262626 a0a0a0 ffffff 1e1e1e 3a3a3a 242424 562202 333333 202020 ff8000",
}

-- reaper.ini is large and the notice asks every frame: its text is kept for a second
function DARK.ini_get(key)
  local now = r.time_precise()
  if not DARK.text or now - DARK.read_at > 1 then
    DARK.text, DARK.read_at = read_all(r.get_ini_file()) or "", now
  end
  return DARK.text:match("[\r\n]" .. key .. "=([^\r\n]*)")
end

function DARK.ini_set(key, value)
  local path = r.get_ini_file()
  local s = read_all(path)
  if not s then return false end
  local found
  s, found = s:gsub("([\r\n])" .. key .. "=[^\r\n]*", "%1" .. key .. "=" .. value, 1)
  if found == 0 then
    local eol = s:match("\r\n") and "\r\n" or "\n"
    local _, stop = s:lower():find("%[reaper%][\r\n]+")
    if not stop then return false end
    s = s:sub(1, stop) .. key .. "=" .. value .. eol .. s:sub(stop + 1)
  end
  DARK.text = nil                  -- read it fresh next time
  return write_all(path, s)
end

function DARK.norm(v) return ((v or ""):lower():gsub("%s+", " "):gsub("^ ", ""):gsub(" $", "")) end

function DARK.is_bit() return DARK.norm(DARK.ini_get("win32_darkmode_colors")) == DARK.norm(DARK.BIT) end

function DARK.is_old_bit()
  local cur = DARK.norm(DARK.ini_get("win32_darkmode_colors"))
  for _, v in ipairs(DARK.OLD) do if cur == DARK.norm(v) then return true end end
  return false
end

-- to Bitwig's: the colours in use now are kept, so "Previous" can bring them back
-- (unless they are an earlier Bitwig set: the Previous from then stays)
function DARK.use_bit()
  local cur = DARK.ini_get("win32_darkmode_colors")
  local mode = DARK.ini_get("win32_darkmode") or "0"
  if not DARK.is_bit() and not DARK.is_old_bit() then
    -- what to go back to: the colours and whether dark mode was on at all
    if cur then r.SetExtState(EXT, "prev_darkmode", cur, true) end
    r.SetExtState(EXT, "prev_darkmode_on", mode, true)
  end
  local ok = DARK.ini_set("win32_darkmode_colors", DARK.BIT)
  -- the colours only work with Windows dark mode on, so Bitwig switches it on
  if ok and mode == "0" then ok = DARK.ini_set("win32_darkmode", "1") end
  -- for TK Theme's settings: they recognise this set and offer their own back
  if ok then r.SetExtState(EXT, "applied_darkmode", DARK.BIT, true) end
  DARK.written = ok
  DARK.msg = ok and "Written. Restart REAPER to see it." or "Could not write reaper.ini."
end

-- the notice at the top of SETTINGS: REAPER's window colours aren't Bit's (another theme's
-- set, or dark mode off). "Keep as is" hides it until the colours change again.
function DARK.state_key()
  return DARK.norm(DARK.ini_get("win32_darkmode_colors")) .. "|" .. (DARK.ini_get("win32_darkmode") or "0")
end

function DARK.mismatch()
  if not IS_WINDOWS or not bit_active() or DARK.msg then return false end
  -- dark mode off: REAPER uses this theme's own colours (col_main_bg's override flag), fine
  if (DARK.ini_get("win32_darkmode") or "0") == "0" or DARK.is_bit() then return false end
  return r.GetExtState(EXT, "dark_keep") ~= DARK.state_key()
end

-- Restart REAPER (Windows: the dark mode colours only exist there). REAPER has no restart
-- action, so a hidden PowerShell waits until REAPER has closed and starts it again; then
-- "File: Quit REAPER" (40004), which asks to save as always. Cancelled there, REAPER stays
-- open: the helper gives up after 2 minutes and starts nothing.
function DARK.restart()
  local exe = (r.GetExePath() .. "\\reaper.exe"):gsub("'", "''")
  local ps = "$p = Get-Process -Name reaper -ErrorAction SilentlyContinue; "
    .. "if ($p) { $p | Wait-Process -Timeout 120 -ErrorAction SilentlyContinue }; "
    .. "Start-Sleep -Milliseconds 500; "
    .. "if (-not (Get-Process -Name reaper -ErrorAction SilentlyContinue)) { Start-Process -FilePath '" .. exe .. "' }"
  r.ExecProcess('powershell.exe -NoProfile -NonInteractive -WindowStyle Hidden -Command "' .. ps .. '"', -2)
  r.Main_OnCommand(40004, 0)          -- File: Quit REAPER
end

-- a bar at the top of SETTINGS: a restart once colours are written, or the colours of
-- another theme found
local function bar(text, buttons)
  local dl = r.ImGui_GetWindowDrawList(ctx)
  local x, y = r.ImGui_GetCursorScreenPos(ctx)
  local w = r.ImGui_GetContentRegionAvail(ctx)
  r.ImGui_DrawList_AddRectFilled(dl, x, y, x + w, y + 34, 0x2A1A0EFF, 3)
  r.ImGui_DrawList_AddRectFilled(dl, x, y, x + 3, y + 34, C.accent)
  r.ImGui_SetCursorScreenPos(ctx, x + 12, y + 9)
  text_col(C.text, text)
  local bw = 0
  for _, b in ipairs(buttons) do bw = bw + b[2] + 4 end
  r.ImGui_SetCursorScreenPos(ctx, x + w - bw - 2, y + 6)
  for i, b in ipairs(buttons) do
    if i > 1 then r.ImGui_SameLine(ctx, 0, 4) end
    if action_button(b[1], b[2]) then b[3]() end
  end
  r.ImGui_SetCursorScreenPos(ctx, x, y + 42)
  r.ImGui_Dummy(ctx, 1, 0)
end

function DARK.notice()
  if DARK.written then
    bar("Window colours written: REAPER shows them after a restart.", {
      { "Restart REAPER now", 140, DARK.restart },
      { "Later", 60, function() DARK.written = false end },
    })
    return
  end
  if not DARK.mismatch() then return end
  bar("REAPER's dark mode colours belong to another theme.", {
    { "Switch to Bitwig", 120, DARK.use_bit },
    { "Keep as is", 76, function() r.SetExtState(EXT, "dark_keep", DARK.state_key(), true) end },
  })
end

function DARK.use_previous()
  local prev = r.GetExtState(EXT, "prev_darkmode")
  if prev == "" then return end
  local ok = DARK.ini_set("win32_darkmode_colors", prev)
  -- dark mode back off if it was off before Bitwig
  local on = r.GetExtState(EXT, "prev_darkmode_on")
  if ok and on ~= "" then ok = DARK.ini_set("win32_darkmode", on) end
  DARK.written = ok
  DARK.msg = ok and "Written. Restart REAPER to see it." or "Could not write reaper.ini."
end

-- TK's own toolbar icons (TK_*): a separate ReaPack package (TK Toolbar Icons) holds them
-- in more than one look and copies the chosen one over the TK_ names. Bit follows with
-- its own look unless you pick another.
local ICONS = {}
function ICONS.lib()
  if ICONS.m == nil then
    ICONS.m = false
    local p = r.GetResourcePath() .. "/Scripts/TK Scripts/TK Toolbar Icons/TK_Toolbar_Icons.lua"
    if r.file_exists(p) then
      TK_TOOLBAR_ICONS_LIB = true
      local ok, m = pcall(dofile, p)
      TK_TOOLBAR_ICONS_LIB = nil
      if ok and type(m) == "table" and m.installed() then ICONS.m = m end
    end
  end
  return ICONS.m
end
function ICONS.follow() return r.GetExtState(EXT, "icons_follow") ~= "0" end
-- at the window's start: Bit's look back in place (a TK Theme update puts its own back)
function ICONS.startup()
  local m = ICONS.lib()
  if m and bit_active() and ICONS.follow() and not m.in_place("Bit") then m.apply("Bit") end
end
function ICONS.section()
  section("Toolbar icons", function()
    local m = ICONS.lib()
    if not m then
      row("TK icons", function()
        if action_button("Get them through ReaPack", 200) then
          if r.ReaPack_BrowsePackages then r.ReaPack_BrowsePackages("TK Toolbar Icons")
          else r.ShowMessageBox("Install ReaPack first (reapack.com).", "TK Theme Bit", 0) end
        end
      end)
      note("TK's own toolbar icons (TK_...) in Bit's look come as a separate ReaPack package, "
        .. "TK Toolbar Icons. REAPER's own icons follow this theme already.")
      return
    end
    local styles = m.styles()
    local cur = m.current()
    local idx = 1
    for i, s in ipairs(styles) do if s == cur then idx = i end end
    row("TK icons", function()
      local p = segmented("icons", styles, idx)
      if p and styles[p] ~= cur then
        m.apply(styles[p], true)
        r.SetExtState(EXT, "icons_follow", styles[p] == "Bit" and "1" or "0", true)
      end
    end)
    note("The look of TK's own toolbar icons (TK_...). Bit keeps them in its look each time this window "
      .. "opens, unless you pick another here. A window shows the new icons the next time it opens.")
  end)
end

local function page_window()
  if bit_active() then
    section("Scaling", function()
      row("Theme size", function()
        local p = segmented("scale", { "Auto", "150%", "200%" }, theme_scale())
        if p then set_theme_scale(p) end
      end)
      note("Auto follows the screen's scaling. 150% and 200% use the larger images on any screen.")
    end)
  end
  if IS_WINDOWS then
    section("Windows", function()
      local bit = DARK.is_bit()
      local has_prev = r.GetExtState(EXT, "prev_darkmode") ~= ""
      row("Window colours", function()
        local labels = has_prev and { "Previous", "Bitwig" } or { "Other", "Bitwig" }
        local p = segmented("dark", labels, bit and 2 or 1)
        if p == 2 and not bit then DARK.use_bit()
        elseif p == 1 and bit and has_prev then DARK.use_previous() end
      end)
      note("REAPER's own windows (Media Explorer, FX chain, actions, routing, menus) in Bitwig's greys. "
        .. "These are Windows dark mode colours, so Bitwig also switches dark mode on; Previous puts back "
        .. "the colours and dark mode as they were. A REAPER setting for every theme; it shows after a restart. "
        .. "With dark mode off, REAPER uses this theme's own colours inside its windows (only the window frames stay light).")
      if DARK.msg then note(DARK.msg) end
      if DARK.written then
        row("", function()
          if action_button("Restart REAPER now", 160) then DARK.restart() end
        end)
      end
    end)
  end
  ICONS.section()
  section("REAPER", function()
    if not IS_WINDOWS then
      note("Hiding REAPER's menu bar works on Windows only.")
    elseif r.TK_SetMainMenuVisible then
      local shown = r.TK_IsMainMenuVisible()
      row("Menu bar", function()
        local p = segmented("menubar", { "Shown", "Hidden" }, shown and 1 or 2)
        if p and (p == 1) ~= shown then r.TK_SetMainMenuVisible(p == 1) end
      end)
      note("Bitwig has no menu bar: FILE, ADD and EDIT in the transport hold what you need most.")
    else
      note("Hiding the menu bar needs TK Native Helper 1.1.0 or newer (install it with ReaPack, then restart REAPER).")
    end
  end)
end

local PAGES = {
  { "Transport", page_transport },
  { "Display", page_display },
  { "Arrange", page_arrange },
  { "Tracks & Mixer", page_tracks },
  { "Window", page_window },
}
local page = 1
local tab = 2          -- 1 USER, 2 SETTINGS, 3 HELP
if r.GetExtState(EXT, "open_tab") == "user" then  -- another script can ask for the USER tab
  tab = 1
  r.DeleteExtState(EXT, "open_tab", false)
end

---------------------------------------------------------------- USER: projects
-- Bitwig's dashboard USER tab: Quick Start, Recent Projects, My Projects, My Templates,
-- a search field over the list, an Open button per project, and New Project / Open File
-- under the pages. Kept in one table (U) so the main chunk stays far from Lua's local limit.
local U = { page = 2, search = "", lists = {}, close = false }
local SEP = package.config:sub(1, 1)

function U.exists(path)
  local f = io.open(path, "rb")
  if f then f:close() return true end
  return false
end

function U.item(path)
  local name = path:match("([^\\/]+)$") or path
  local it = { path = path, name = name:gsub("%.[Rr][Pp][Pp]$", ""), time = "" }
  if r.JS_File_Stat then
    local ok, _, _, modified = r.JS_File_Stat(path)
    if ok == 0 and modified then it.time = modified end
  end
  return it
end

-- REAPER's recent list (reaper.ini [Recent], recent01 the newest), files that still exist
function U.recent()
  local text = read_all(r.get_ini_file()) or ""
  local found, in_recent = {}, false
  for line in text:gmatch("[^\r\n]+") do
    local sec = line:match("^%[(.-)%]")
    if sec then
      in_recent = sec:lower() == "recent"
    elseif in_recent then
      local n, path = line:match("^recent(%d+)=(.-)%s*$")
      if n and path ~= "" then found[#found + 1] = { n = tonumber(n), path = path } end
    end
  end
  -- REAPER appends: the HIGHEST number is the newest. The same project can be in it twice
  -- (once with / and once with \), so each is taken once; the newest 10 that still exist
  table.sort(found, function(a, b) return a.n > b.n end)
  local out, seen = {}, {}
  for _, e in ipairs(found) do
    local key = e.path:gsub("/", "\\"):lower()
    if not seen[key] and U.exists(e.path) then
      seen[key] = true
      out[#out + 1] = U.item(e.path)
      if #out == 10 then break end
    end
  end
  return out
end

-- every .rpp in a folder and its subfolders (depth levels down), backups skipped
function U.scan(dir, depth, out)
  r.EnumerateFiles(dir, -1)          -- drop REAPER's cached listing, so a rescan is fresh
  local i = 0
  while true do
    local f = r.EnumerateFiles(dir, i)
    if not f then break end
    if f:lower():match("%.rpp$") then out[#out + 1] = U.item(dir .. SEP .. f) end
    i = i + 1
  end
  if depth > 0 then
    i = 0
    while true do
      local d = r.EnumerateSubdirectories(dir, i)
      if not d then break end
      local l = d:lower()
      if l ~= "backups" and l ~= "autosaves" and not d:match("^%.") then U.scan(dir .. SEP .. d, depth - 1, out) end
      i = i + 1
    end
  end
  return out
end

-- newest first when js_ReaScriptAPI gives file times, otherwise by name
function U.sorted(list)
  table.sort(list, function(a, b)
    if a.time ~= b.time then return a.time > b.time end
    return a.name:lower() < b.name:lower()
  end)
  return list
end

function U.project_dir()
  local dir = ""
  if r.get_config_var_string then
    local ok, v = r.get_config_var_string("defsavepath")
    if ok then dir = v end
  end
  if dir == "" then dir = r.GetProjectPath("") end
  return (dir:gsub("[\\/]+$", ""))
end

function U.template_dir()
  return r.GetResourcePath() .. SEP .. "ProjectTemplates"
end

-- the lists are read once and kept; Refresh reads them again
function U.list(which)
  if not U.lists[which] then
    if which == "recent" then
      U.lists.recent = U.recent()
    elseif which == "projects" then
      U.lists.projects = U.sorted(U.scan(U.project_dir(), 2, {}))
    else
      U.lists.templates = U.sorted(U.scan(U.template_dir(), 1, {}))
    end
  end
  return U.lists[which]
end

-- where a project opens: "new" = its own project tab (the current one is reused while it
-- is still empty and untitled), "this" = in place of the current project (REAPER asks to
-- save it first). Remembered; the right-click menu can do the other one for one project.
U.mode = r.GetExtState(EXT, "open_in") == "this" and "this" or "new"

function U.current_in_use()
  local _, path = r.EnumProjects(-1)
  return (path or "") ~= "" or r.IsProjectDirty(0) ~= 0 or r.CountTracks(0) > 0
end

function U.new_tab_if_needed(mode)
  if (mode or U.mode) == "new" and U.current_in_use() then
    r.Main_OnCommand(40859, 0)        -- File: New project tab
    return true
  end
  return false
end

-- a project, a template (as_template), or with an empty path a new empty project
function U.open(path, as_template, mode)
  mode = mode or U.mode
  if path == "" then
    if not U.new_tab_if_needed(mode) then r.Main_OnCommand(40023, 0) end   -- File: New project
  else
    local fresh = U.new_tab_if_needed(mode)
    -- in a fresh tab there is nothing to save; in this tab REAPER may ask to save first
    local prefix = as_template and "template:" or (fresh and "noprompt:" or "")
    r.Main_openProject(prefix .. path)
  end
  U.close = true
end

function U.open_file()
  U.new_tab_if_needed()
  r.Main_OnCommand(40025, 0)          -- File: Open project
  U.close = true
end

function U.reveal(path)
  if r.CF_LocateInExplorer then
    r.CF_LocateInExplorer(path)
  elseif r.GetOS():find("Win", 1, true) then
    r.ExecProcess('explorer.exe /select,"' .. path .. '"', -1)
  elseif r.CF_ShellExecute then
    r.CF_ShellExecute(path:match("^(.*)[\\/]") or path)
  end
end

function U.doc_icon(dl, x, y)
  local c = 0xB4B4B4FF
  r.ImGui_DrawList_AddRectFilled(dl, x, y, x + 11, y + 14, c, 1)
  r.ImGui_DrawList_AddTriangleFilled(dl, x + 7, y - 0.5, x + 11.5, y - 0.5, x + 11.5, y + 4, C.bg)
  for k = 0, 2 do
    r.ImGui_DrawList_AddLine(dl, x + 2.5, y + 6.5 + k * 2.5, x + 8.5, y + 6.5 + k * 2.5, 0x5A5A5AFF, 1)
  end
end

-- one project row: icon, name (double-click opens), the date in grey, an Open button;
-- a right-click anywhere on the row opens its menu (U.popup draws it)
function U.row(it, i, button, as_template)
  local dl = r.ImGui_GetWindowDrawList(ctx)
  local x, y = r.ImGui_GetCursorScreenPos(ctx)
  local w = r.ImGui_GetContentRegionAvail(ctx)
  if r.ImGui_IsWindowHovered(ctx) and r.ImGui_IsMouseHoveringRect(ctx, x, y, x + w, y + 32) then
    r.ImGui_DrawList_AddRectFilled(dl, x, y, x + w, y + 32, 0x1E1E1EFF, 2)
    if r.ImGui_IsMouseClicked(ctx, 1) then
      U.menu = { it = it, as_template = as_template }
      r.ImGui_OpenPopup(ctx, "##umenu")
    end
  end
  U.doc_icon(dl, x + 6, y + 9)
  r.ImGui_SetCursorScreenPos(ctx, x + 26, y + 8)
  r.ImGui_Text(ctx, it.name)
  if r.ImGui_IsItemHovered(ctx) then
    if it.path ~= "" then r.ImGui_SetTooltip(ctx, it.path) end
    if r.ImGui_IsMouseDoubleClicked(ctx, 0) then U.open(it.path, as_template) end
  end
  if it.time ~= "" then
    local date = it.time:sub(1, 10):gsub("%.", "-")
    local tw = r.ImGui_CalcTextSize(ctx, date)
    r.ImGui_SetCursorScreenPos(ctx, x + w - 110 - tw, y + 8)
    text_col(C.dim, date)
  end
  r.ImGui_SetCursorScreenPos(ctx, x + w - 100, y + 5)
  if action_button((button or "Open") .. "##u" .. i, 98) then U.open(it.path, as_template) end
  r.ImGui_SetCursorScreenPos(ctx, x, y + 34)
  r.ImGui_Dummy(ctx, 1, 0)
end

-- the row menu: open the other way than the chosen default, or show the file
function U.popup()
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_PopupBg(), C.field)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderHovered(), C.accent)
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), 6, 6)
  if r.ImGui_BeginPopup(ctx, "##umenu") then
    local m = U.menu
    if m then
      local verb = m.as_template and "Create" or "Open"
      if r.ImGui_Selectable(ctx, verb .. " in new tab") then U.open(m.it.path, m.as_template, "new") end
      if r.ImGui_Selectable(ctx, verb .. " in this tab") then U.open(m.it.path, m.as_template, "this") end
      if m.it.path ~= "" then
        r.ImGui_Separator(ctx)
        if r.ImGui_Selectable(ctx, "Show in Explorer") then U.reveal(m.it.path) end
      end
    end
    r.ImGui_EndPopup(ctx)
  end
  r.ImGui_PopStyleVar(ctx)
  r.ImGui_PopStyleColor(ctx, 2)
end

function U.search_box()
  local w = r.ImGui_GetContentRegionAvail(ctx)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), 0x000000FF)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_TextDisabled(), C.dim)
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FramePadding(), 8, 6)
  r.ImGui_SetNextItemWidth(ctx, w - (U.search ~= "" and 30 or 0))
  local _, s = r.ImGui_InputTextWithHint(ctx, "##search", "Type to search...", U.search)
  U.search = s
  r.ImGui_PopStyleVar(ctx)
  r.ImGui_PopStyleColor(ctx, 2)
  if U.search ~= "" then
    r.ImGui_SameLine(ctx, 0, 4)
    if action_button("\u{00D7}##clear", 26) then U.search = "" end
  end
  r.ImGui_Spacing(ctx)
end

function U.matches(it)
  if U.search == "" then return true end
  local q = U.search:lower()
  return it.name:lower():find(q, 1, true) or it.path:lower():find(q, 1, true)
end

-- the bottom line of a page: "Open in" New tab | This tab, then the page's own extras
function U.footer(extra)
  r.ImGui_AlignTextToFramePadding(ctx)
  text_col(C.dim, "Open in")
  r.ImGui_SameLine(ctx)
  local p = segmented("openin", { "New tab", "This tab" }, U.mode == "new" and 1 or 2)
  if p then
    U.mode = p == 1 and "new" or "this"
    r.SetExtState(EXT, "open_in", U.mode, true)
  end
  if extra then
    r.ImGui_SameLine(ctx, 0, 16)
    extra()
  end
end

function U.list_page(which, empty, button, as_template)
  U.search_box()
  if r.ImGui_BeginChild(ctx, "##list" .. which, 0, -30) then
    local shown = 0
    for i, it in ipairs(U.list(which)) do
      if U.matches(it) then
        U.row(it, i, button, as_template)
        shown = shown + 1
      end
    end
    if shown == 0 then text_col(C.dim, U.search ~= "" and "Nothing matches." or empty, true) end
    U.popup()
    r.ImGui_EndChild(ctx)
  end
  U.footer(function()
    if action_button("Refresh") then U.lists[which] = nil end
    if which == "projects" then
      r.ImGui_SameLine(ctx)
      r.ImGui_AlignTextToFramePadding(ctx)
      text_col(C.dim, U.project_dir())
    end
  end)
end

function U.quick_start()
  if r.ImGui_BeginChild(ctx, "##quick", 0, -30) then
    text_col(C.dim, "START")
    r.ImGui_Spacing(ctx)
    U.row({ name = "Empty project", path = "", time = "" }, 0, "Create")
    for i, it in ipairs(U.list("templates")) do
      if i > 4 then break end
      U.row(it, 1000 + i, "Create", true)
    end
    r.ImGui_Spacing(ctx)
    text_col(C.dim, "CONTINUE")
    r.ImGui_Spacing(ctx)
    for i, it in ipairs(U.list("recent")) do
      if i > 4 then break end
      U.row(it, 2000 + i)
    end
    U.popup()
    r.ImGui_EndChild(ctx)
  end
  U.footer()
end

-- the projects open in tabs now: the active one marked with an orange dot, unsaved
-- changes with a *; Switch brings a tab to the front, the cross closes it (REAPER asks
-- to save when needed)
function U.open_projects()
  local active = r.EnumProjects(-1)
  local close
  if r.ImGui_BeginChild(ctx, "##tabs", 0, -30) then
    local i = 0
    while true do
      local proj, path = r.EnumProjects(i)
      if not proj then break end
      local dl = r.ImGui_GetWindowDrawList(ctx)
      local x, y = r.ImGui_GetCursorScreenPos(ctx)
      local w = r.ImGui_GetContentRegionAvail(ctx)
      local is_active = proj == active
      if is_active then
        r.ImGui_DrawList_AddRectFilled(dl, x, y, x + w, y + 32, 0x1E1E1EFF, 2)
        r.ImGui_DrawList_AddCircleFilled(dl, x + 11, y + 16, 4, C.accent)
      else
        r.ImGui_DrawList_AddCircle(dl, x + 11, y + 16, 4, 0x5A5A5AFF, 0, 1)
      end
      local name = r.GetProjectName(proj, "")
      if name == "" then name = "(unsaved project)" end
      name = name:gsub("%.[Rr][Pp][Pp]$", "")
      if r.IsProjectDirty(proj) ~= 0 then name = name .. " *" end
      r.ImGui_SetCursorScreenPos(ctx, x + 26, y + 8)
      text_col(is_active and C.text or C.dim, name)
      if r.ImGui_IsItemHovered(ctx) and (path or "") ~= "" then r.ImGui_SetTooltip(ctx, path) end
      if not is_active then
        r.ImGui_SetCursorScreenPos(ctx, x + w - 132, y + 5)
        if action_button("Switch##t" .. i, 98) then
          r.SelectProjectInstance(proj)
          U.close = true
        end
      end
      r.ImGui_SetCursorScreenPos(ctx, x + w - 28, y + 5)
      if action_button("\u{00D7}##tc" .. i, 26) then close = proj end
      r.ImGui_SetCursorScreenPos(ctx, x, y + 34)
      r.ImGui_Dummy(ctx, 1, 0)
      i = i + 1
    end
    r.ImGui_EndChild(ctx)
  end
  if close then
    -- REAPER closes only the current tab: bring this one forward, close it, then go back
    r.SelectProjectInstance(close)
    r.Main_OnCommand(40860, 0)          -- File: Close current project tab
    if active ~= close then
      local j = 0
      while true do
        local p = r.EnumProjects(j)
        if not p then break end
        if p == active then r.SelectProjectInstance(active) break end
        j = j + 1
      end
    end
  end
  if action_button("New tab") then
    r.Main_OnCommand(40859, 0)
    U.close = true
  end
end

U.PAGES = {
  { "Open Projects", function() U.open_projects() end },
  { "Quick Start", function() U.quick_start() end },
  { "Recent Projects", function() U.list_page("recent", "No recent projects.") end },
  { "My Projects", function() U.list_page("projects", "No projects found in the project folder.") end },
  { "My Templates", function() U.list_page("templates", "No templates in REAPER's ProjectTemplates folder.", "Create", true) end },
}
U.page = 3

local function page_help()
  r.ImGui_PushTextWrapPos(ctx, 0)
  text_col(C.text, "TK Theme Bit", false)
  r.ImGui_Spacing(ctx)
  text_col(C.dim, "A REAPER theme in the style of a modern flat DAW. These settings switch the theme's own options "
    .. "and a few REAPER preferences that belong to the look (through SWS).", true)
  r.ImGui_Spacing(ctx)
  text_col(C.dim, "The FILE / ADD / EDIT buttons and this gear are small scripts, registered once by "
    .. "TK_Theme_Bit_Setup.lua.", true)
  r.ImGui_PopTextWrapPos(ctx)
end

---------------------------------------------------------------- window
local function header(open)
  -- large thin titles across the top, the active one white; a close cross on the right
  r.ImGui_PushFont(ctx, font, 26)
  local titles = { "USER", "SETTINGS", "HELP" }
  for i, t in ipairs(titles) do
    if i > 1 then r.ImGui_SameLine(ctx, 0, 70) end
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), tab == i and C.text or C.dim)
    r.ImGui_Text(ctx, t)
    r.ImGui_PopStyleColor(ctx)
    if r.ImGui_IsItemClicked(ctx) then tab = i end
  end
  r.ImGui_PopFont(ctx)
  r.ImGui_SameLine(ctx)
  r.ImGui_SetCursorPosX(ctx, W - 50)
  r.ImGui_PushFont(ctx, font, 22)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), C.dim)
  r.ImGui_Text(ctx, "\u{00D7}")
  r.ImGui_PopStyleColor(ctx)
  r.ImGui_PopFont(ctx)
  if r.ImGui_IsItemClicked(ctx) then open = false end
  r.ImGui_Spacing(ctx)
  hline()
  r.ImGui_Spacing(ctx)
  return open
end

local function sidebar(pages, current)
  local dl = r.ImGui_GetWindowDrawList(ctx)
  for i, p in ipairs(pages) do
    local x, y = r.ImGui_GetCursorScreenPos(ctx)
    local on = (current == i)
    if on then r.ImGui_DrawList_AddRectFilled(dl, x, y + 2, x + 2, y + 18, C.accent) end
    r.ImGui_SetCursorPosX(ctx, r.ImGui_GetCursorPosX(ctx) + 10)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), on and C.text or C.dim)
    if r.ImGui_Selectable(ctx, p[1] .. "##page" .. i, false, 0, SIDEBAR - 20, 20) then current = i end
    r.ImGui_PopStyleColor(ctx)
    r.ImGui_Dummy(ctx, 1, 10)
  end
  return current
end

-- USER's sidebar: the pages, then Bitwig's buttons under them
local function user_sidebar()
  U.page = sidebar(U.PAGES, U.page)
  r.ImGui_Dummy(ctx, 1, 30)
  local bw = SIDEBAR - 20
  if action_button("New Project", bw) then U.open("") end
  r.ImGui_Dummy(ctx, 1, 2)
  if action_button("New Tab", bw) then        -- always a new empty tab, whatever Open in says
    r.Main_OnCommand(40859, 0)        -- File: New project tab
    U.close = true
  end
  r.ImGui_Dummy(ctx, 1, 2)
  if action_button("Open File...", bw) then U.open_file() end
  r.ImGui_Dummy(ctx, 1, 2)
  if action_button("Project Settings...", bw) then
    r.Main_OnCommand(40021, 0)       -- File: Project settings
  end
end

local function loop()
  r.ImGui_PushFont(ctx, font, 13)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_WindowBg(), C.bg)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Border(), C.line)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), C.text)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderHovered(), 0x00000000)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderActive(), 0x00000000)
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowRounding(), 10)
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), 30, 22)
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowBorderSize(), 1)
  r.ImGui_SetNextWindowSize(ctx, W, H, r.ImGui_Cond_Always())
  local flags = r.ImGui_WindowFlags_NoTitleBar() | r.ImGui_WindowFlags_NoResize() | r.ImGui_WindowFlags_NoCollapse()
  local visible, open = r.ImGui_Begin(ctx, "TK Theme Bit settings", true, flags)
  if visible then
    open = header(open)
    if tab == 1 then
      if r.ImGui_BeginChild(ctx, "##uside", SIDEBAR, 0) then
        user_sidebar()
        r.ImGui_EndChild(ctx)
      end
      r.ImGui_SameLine(ctx)
      if r.ImGui_BeginChild(ctx, "##upage", 0, 0) then
        U.PAGES[U.page][2]()
        r.ImGui_EndChild(ctx)
      end
    elseif tab == 2 then
      DARK.notice()
      if r.ImGui_BeginChild(ctx, "##side", SIDEBAR, 0) then
        page = sidebar(PAGES, page)
        r.ImGui_EndChild(ctx)
      end
      r.ImGui_SameLine(ctx)
      if r.ImGui_BeginChild(ctx, "##page", 0, 0) then
        PAGES[page][2]()
        r.ImGui_EndChild(ctx)
      end
    else
      page_help()
    end
    r.ImGui_End(ctx)
  end
  r.ImGui_PopStyleVar(ctx, 3)
  r.ImGui_PopStyleColor(ctx, 5)
  r.ImGui_PopFont(ctx)
  if U.close then open = false end   -- a project was opened: off, as Bitwig's dashboard
  if open then r.defer(loop) end
end

look_restore()
devices_first_run()
ICONS.startup()
r.defer(loop)
