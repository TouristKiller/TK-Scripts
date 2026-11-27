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
local SCALE_LAYOUTS = { "", "125%_A", "150%_A", "200%_A" }
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
local AUD = {}          -- the audio editor row: "Other action" chosen, the ID being typed
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
  if not script_command("TK_Theme_Bit_Devices_Panel.lua") and not saxmand_found()
    and r.GetExtState(EXT, "devices_action") == "" then
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
        row("Mixer / editor icons", function()
          local p = segmented("views", { "Off", "Shown" }, vvalue == 0 and 1 or 2)
          if p then set_theme_param("bitTransViews", p == 1 and 0 or 1) end
        end)
        note("Icons at the right end of the bar, as Bitwig's panel icons: the mixer, and the selected MIDI "
          .. "item in the MIDI editor. One at a time, orange while open; click the orange one again to close it. "
          .. "They hide on a bar too narrow for them.")
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
        -- what it opens: TK Bit Devices (""), Saxmand's script ("saxmand"), or any action
        -- (ExtState devices_action)
        local own = r.GetExtState(EXT, "devices_action")
        local sax = own == "saxmand"
        local other = (own ~= "" and not sax) or devices_other
        r.ImGui_Spacing(ctx)
        row("Devices key opens", function()
          local p = segmented("devwhat", { "TK Devices", "Saxmand", "Other action" }, other and 3 or (sax and 2 or 1))
          if p == 1 then
            r.DeleteExtState(EXT, "devices_action", true)
            devices_other = false
          elseif p == 2 then
            r.SetExtState(EXT, "devices_action", "saxmand", true)
            devices_other = false
          elseif p == 3 then
            if sax then r.DeleteExtState(EXT, "devices_action", true) end
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
        elseif sax then
          note(saxmand_found()
            and "DEVICES opens Saxmand's FX Modulator Linking."
            or "DEVICES opens Saxmand's FX Modulator Linking, which isn't installed: get it from Saxmand's ReaPack repository, or choose TK Devices.")
        else
          note("DEVICES opens TK Bit Devices, this theme's device panel: the track's devices with their parameters, "
            .. "remote controls and Bitwig's modulators (LFO, Steps, ADSR, MIDI, Keytrack+, Macros and more).")
        end
      end
      -- the audio editor icon: SneakPeak, or any action (ExtState audio_action)
      local aidx, avalue = theme_param("bitTransAudio")
      if aidx then

        r.ImGui_Spacing(ctx)
        row("Audio editor icon", function()
          local p = segmented("audio", { "Off", "Shown" }, avalue == 0 and 1 or 2)
          if p then set_theme_param("bitTransAudio", p == 1 and 0 or 1) end
        end)
        -- Clip Edit (the theme's own, the default), SneakPeak, or another action; the action
        -- typed for "other" is kept when you switch away and back
        local own = r.GetExtState(EXT, "audio_action")
        local choice = r.GetExtState(EXT, "audio_choice")
        if choice == "" then choice = own ~= "" and "other" or "clipedit" end
        local CHOICES = { "clipedit", "sneakpeak", "other" }
        local cur = choice == "sneakpeak" and 2 or choice == "other" and 3 or 1
        r.ImGui_Spacing(ctx)
        row("Audio editor opens", function()
          local p = segmented("audwhat", { "Clip Edit", "SneakPeak", "Other action" }, cur)
          if p and p ~= cur then r.SetExtState(EXT, "audio_choice", CHOICES[p], true) end
        end)
        local other = choice == "other"
        if other then
          row("Action ID", function()
            r.ImGui_SetNextItemWidth(ctx, 260)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), C.field)
            local _, s = r.ImGui_InputTextWithHint(ctx, "##audid", "_RS... or a number", AUD.typed or own)
            if r.ImGui_IsItemActive(ctx) then AUD.typed = s end
            if r.ImGui_IsItemDeactivatedAfterEdit(ctx) then
              s = s:gsub("^%s+", ""):gsub("%s+$", "")
              if s == "" then r.DeleteExtState(EXT, "audio_action", true)
              else r.SetExtState(EXT, "audio_action", s, true) end
              AUD.typed = nil
            end
            r.ImGui_PopStyleColor(ctx)
          end)
          local id = r.GetExtState(EXT, "audio_action")
          local cmd = id ~= "" and (tonumber(id) or r.NamedCommandLookup(id)) or 0
          if id == "" then
            note("Paste an action's command ID, TK Audio Editor's for one (Actions list: right-click > Copy selected action command ID).")
          elseif cmd and cmd > 0 then
            note("Opens: " .. r.kbd_getTextFromCmd(math.floor(cmd), 0))
          else
            note("REAPER doesn't know this action.")
          end
        elseif choice == "sneakpeak" then
          note(r.NamedCommandLookup("_SneakPeak_Toggle") ~= 0
            and "Opens SneakPeak, a waveform editor for the selected audio clip. Dock it at the bottom from its right-click menu."
            or "Opens SneakPeak, which isn't installed: add its ReaPack repository "
              .. "(https://raw.githubusercontent.com/b451c/SneakPeak/main/index.xml), or choose Clip Edit.")
        else
          note("Opens TK Bit Clip Edit, this theme's own audio editor in Bitwig's style, for the selected audio clip. "
            .. "Dock it at the bottom, under the arrange, as Bitwig's.")
        end
      end
      -- the clip launcher: its icon in the transport, and a button to open / close it here
      local lidx, lvalue = theme_param("bitTransLaunch")
      if lidx then
        r.ImGui_Spacing(ctx)
        row("Clip launcher icon", function()
          local p = segmented("launch", { "Off", "Shown" }, lvalue == 0 and 1 or 2)
          if p then set_theme_param("bitTransLaunch", p == 1 and 0 or 1) end
        end)
        local cmd = script_command("TK_Theme_Bit_Launcher.lua")
        if cmd then
          local open = r.GetToggleCommandState(cmd) == 1
          row("Clip launcher", function()
            if action_button(open and "Close launcher" or "Open launcher", 140) then r.Main_OnCommand(cmd, 0) end
          end)
        end
        note("Bitwig's clip launcher: slots per track, scenes, launch quantize. Dock it at the left of the arrange.")
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

-- REAPER settings that make the arrange look like Bitwig's: grid lines through the clips
-- (SWS's grid Z order actions, found by name: SWS ids differ per install) and a ruler with
-- seconds over the bars. The ruler as it was is kept, so "Bars" puts it back.
local BW = {
  RULER_BITWIG = 41916, RULER_BITWIG2 = 43705,   -- Measures.Beats (minimal) / Minutes:Seconds (minimal)
  RULER = { 40365, 40366, 40367, 40368, 40369, 40370, 41916, 41918, 41973, 43204, 43205 },
  RULER2 = { 42360, 42361, 42362, 42363, 42364, 42365, 43705 },
}
function BW.sws_grid(which)       -- "Over items" / "Through items" / "Under items"
  BW.grid_ids = BW.grid_ids or {}
  if BW.grid_ids[which] == nil then
    BW.grid_ids[which] = false
    local i = 0
    while true do
      local id, name = r.kbd_enumerateActions(0, i)
      if not id or id == 0 then break end
      if name:find('Set grid line Z order to "' .. which .. '"', 1, true) then BW.grid_ids[which] = id break end
      i = i + 1
    end
  end
  return BW.grid_ids[which] or nil
end
function BW.first_on(list)
  for _, id in ipairs(list) do if r.GetToggleCommandState(id) == 1 then return id end end
end
function BW.ruler_bitwig()
  return r.GetToggleCommandState(BW.RULER_BITWIG) == 1 and r.GetToggleCommandState(BW.RULER_BITWIG2) == 1
end
function BW.set_ruler(bitwig)
  if bitwig then
    local a, b = BW.first_on(BW.RULER), BW.first_on(BW.RULER2)
    if a and a ~= BW.RULER_BITWIG then r.SetExtState(EXT, "ruler_prev", tostring(a), true) end
    if b and b ~= BW.RULER_BITWIG2 then r.SetExtState(EXT, "ruler_prev2", tostring(b), true) end
    r.Main_OnCommand(BW.RULER_BITWIG, 0)
    r.Main_OnCommand(BW.RULER_BITWIG2, 0)
  else
    r.Main_OnCommand(tonumber(r.GetExtState(EXT, "ruler_prev")) or 40367, 0)    -- Measures.Beats
    r.Main_OnCommand(tonumber(r.GetExtState(EXT, "ruler_prev2")) or 42360, 0)   -- no second line
  end
end
function BW.section()
  section("Grid and ruler", function()
    local through, under = BW.sws_grid("Through items"), BW.sws_grid("Under items")
    if through and under then
      local on = r.GetToggleCommandState(through) == 1
      row("Grid lines", function()
        local p = segmented("gridz", { "Behind clips", "Through clips" }, on and 2 or 1)
        if p then r.Main_OnCommand(p == 2 and through or under, 0) end
      end)
      note("Through clips: the beat lines run through the clips, so you see the bars inside them, as in Bitwig.")
    else
      note("Grid lines through the clips need SWS. In REAPER: Snap/Grid settings (Alt+L) > Grid line Z order.")
    end
    r.ImGui_Spacing(ctx)
    row("Ruler", function()
      local p = segmented("ruler", { "Bars", "Seconds + bars" }, BW.ruler_bitwig() and 2 or 1)
      if p then BW.set_ruler(p == 2) end
    end)
    note("Seconds + bars: two lines in the ruler, minutes:seconds over the bar numbers, as Bitwig's. "
      .. "Bars puts back the ruler you had.")
  end)
end

local function page_arrange()
  BW.section()
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
  section("Mixer strips", function()
    -- the strip widths are theme parameters (px at 100 %): the fields, keys and input row
    -- grow with them, the meter and fader stay as they are, centred in their box
    local shown = false
    for _, s in ipairs({ { "bitMcpW", "Tracks", "mcpw" }, { "bitMstW", "Master", "mstw" } }) do
      local idx = theme_param(s[1])
      if idx then
        local _, _, value, def, min, max = r.ThemeLayout_GetParameter(idx)
        if shown then r.ImGui_Spacing(ctx) end
        shown = true
        row(s[2] .. " width", function()
          local new, moved, done = bar_slider(s[3], value, min, max, def)
          if moved or done then
            -- live while dragging, stored in the theme's settings on release
            r.ThemeLayout_SetParameter(idx, new, done)
            if moved then r.ThemeLayout_RefreshAll() end
          end
        end)
      end
    end
    if shown then note("In pixels at 100 %. Right-click a slider for Bitwig's width (88).") end
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

-- the key gone from reaper.ini: REAPER's own dark mode colours again
function DARK.ini_remove(key)
  local path = r.get_ini_file()
  local s = read_all(path)
  if not s then return false end
  s = s:gsub("([\r\n])" .. key .. "=[^\r\n]*\r?\n", "%1", 1)
  DARK.text = nil
  return write_all(path, s)
end

-- reaper.ini had no colours of its own before Bitwig (REAPER's defaults): kept as this
-- word, so the way back removes Bitwig's instead of leaving them
DARK.NONE = "none"

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
    r.SetExtState(EXT, "prev_darkmode", cur or DARK.NONE, true)
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

-- back to the colours from before Bitwig; nothing kept (Bitwig's set from an older Bit, or
-- reaper.ini had none): REAPER's own, by removing the key
function DARK.use_previous()
  local prev = r.GetExtState(EXT, "prev_darkmode")
  local ok
  if prev == "" or prev == DARK.NONE then ok = DARK.ini_remove("win32_darkmode_colors")
  else ok = DARK.ini_set("win32_darkmode_colors", prev) end
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
        local p = segmented("scale", { "Auto", "125%", "150%", "200%" }, theme_scale())
        if p then set_theme_scale(p) end
      end)
      note("Auto follows the screen's scaling. 125%, 150% and 200% use the larger images on any screen.")
    end)
  end
  if IS_WINDOWS then
    section("Windows", function()
      local bit = DARK.is_bit()
      local prev = r.GetExtState(EXT, "prev_darkmode")
      local has_prev = prev ~= "" and prev ~= DARK.NONE
      row("Window colours", function()
        -- always clickable: with nothing kept, the first key gives REAPER's own colours back
        local labels = has_prev and { "Previous", "Bitwig" } or { "REAPER's", "Bitwig" }
        local p = segmented("dark", labels, bit and 2 or 1)
        if p == 2 and not bit then DARK.use_bit()
        elseif p == 1 and bit then DARK.use_previous() end
      end)
      note("REAPER's own windows (Media Explorer, FX chain, actions, routing, menus) in Bitwig's greys. "
        .. "These are Windows dark mode colours, so Bitwig also switches dark mode on; "
        .. (has_prev and "Previous" or "REAPER's") .. " puts back "
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

-- Bitwig shortcuts: one of REAPER's 16 alternative lists of the main section holds them,
-- switched on and off at once; Main stays untouched (TK_Theme_Bit_Keys.lua tells why).
-- The list below shows every action with the keys that work while the list is on.
local KEYS = { search = "", only_keys = true, pick = nil }
function KEYS.lib()
  if KEYS.m == nil then
    local ok, m = pcall(dofile, dir .. "/TK_Theme_Bit_Keys.lua")
    KEYS.m = ok and m or false
  end
  return KEYS.m
end
-- the list in the look of Bitwig's Settings > Shortcuts: two black filter fields (type to
-- filter actions / press a key to filter), the actions grouped under their category with
-- a fold arrow, each key a small grey pill with its cross, a plain + to add one
KEYS.TXT = { bitwig = C.accent, own = C.text, default = 0x8C8C8CFF, hidden = 0x4A4A4AFF, lost = 0x5E5E5EFF }
KEYS.TIP = {
  bitwig = "Bitwig key. Click to change it, the cross removes it.",
  own = "Your own key in the Bitwig list. Click to change it, the cross removes it.",
  default = "REAPER's default key, working while the Bitwig list is on. The cross takes it out of the list.",
  hidden = "Taken by another key in the Bitwig list.",
  lost = "Your own key in REAPER's main list: it doesn't work while the Bitwig list is on. Click to add a key.",
}
KEYS.LIST_BG, KEYS.PILL, KEYS.PILL_HI, KEYS.PILL_DIM = 0x0A0A0AFF, 0x343434FF, 0x484848FF, 0x1C1C1CFF
KEYS.closed, KEYS.ver = {}, 0
KEYS.keyfilter = ""

-- REAPER's shortcut dialog is modal and blocks this script, so it runs after the frame
function KEYS.later(f) KEYS.after = f end
function KEYS.dialog(cmd, idx)
  local m = KEYS.lib()
  KEYS.later(function()
    r.DoActionShortcutDialog(r.GetMainHwnd(), r.SectionFromUniqueID(m.alt()), cmd, idx)
    KEYS.refresh(cmd)
  end)
end

-- after a change: only the rows it touches are read again, not all actions
function KEYS.refresh(cmd)
  if not KEYS.rows then return end
  KEYS.lib().refresh(KEYS.rows, cmd)
  KEYS.key = nil                     -- filter again (a row may have gained or lost its keys)
end

-- the rows to draw: a header per category ("Item: Split..." -> Item; no colon -> General),
-- then its actions without the prefix, unless the category is folded
function KEYS.filtered()
  local key = table.concat({ KEYS.search, KEYS.keyfilter, tostring(KEYS.only_keys), KEYS.ver }, "\0")
  if KEYS.rows and KEYS.key == key and KEYS.list then return KEYS.list end
  if not KEYS.rows then KEYS.rows = KEYS.lib().model() end
  local q = KEYS.search:lower()
  local groups, names = {}, {}
  for _, row in ipairs(KEYS.rows) do
    local ok = (not KEYS.only_keys or #row.keys > 0) and (q == "" or row.name:lower():find(q, 1, true))
    if ok and KEYS.keyfilter ~= "" then
      ok = false
      for _, k in ipairs(row.keys) do if k.desc == KEYS.keyfilter then ok = true break end end
    end
    if ok then
      local g, short = row.name:match("^(.-):%s+(.+)$")
      if not g or #g > 40 then g, short = "General", row.name end
      -- thousands of scripts: one group per maker, by the file name's prefix (TK_, mpl_, X-Raym_)
      if g == "Script" or g == "Custom" then
        local maker = short:match("^([%w%-]+)_")
        g = "Script: " .. (maker or "other")
      end
      row.short = short
      if not groups[g] then groups[g] = {} names[#names + 1] = g end
      table.insert(groups[g], row)
    end
  end
  table.sort(names, function(a, b) return a:lower() < b:lower() end)
  local open_all = q ~= "" or KEYS.keyfilter ~= ""
  local list = {}
  for _, g in ipairs(names) do
    list[#list + 1] = { head = g, n = #groups[g] }
    if open_all or not KEYS.closed[g] then
      for _, row in ipairs(groups[g]) do list[#list + 1] = row end
    end
  end
  KEYS.key, KEYS.list = key, list
  return list
end

-- one key as a pill: grey, rounded, its text in the kind's colour, a cross when it can
-- go. Returns "change", "remove", "add" or nil.
function KEYS.chip(k, id)
  r.ImGui_PushFont(ctx, font, 11)
  local tw, th = r.ImGui_CalcTextSize(ctx, k.desc)
  local can_x = k.kind == "bitwig" or k.kind == "own" or k.kind == "default"
  local w = tw + 12 + (can_x and 11 or 0)
  local x, y = r.ImGui_GetCursorScreenPos(ctx)
  local hit = r.ImGui_InvisibleButton(ctx, "##chip" .. id, w, 17)
  local hover = r.ImGui_IsItemHovered(ctx)
  local mx = r.ImGui_GetMousePos(ctx)
  local on_x = can_x and hover and mx >= x + w - 13
  local dl = r.ImGui_GetWindowDrawList(ctx)
  local dim = k.kind == "hidden" or k.kind == "lost"
  local fill = dim and KEYS.PILL_DIM or ((hover and not on_x) and KEYS.PILL_HI or KEYS.PILL)
  r.ImGui_DrawList_AddRectFilled(dl, x, y + 1, x + w, y + 16, fill, 4)
  local col = KEYS.TXT[k.kind]
  r.ImGui_DrawList_AddText(dl, x + 6, y + (17 - th) / 2, col, k.desc)
  if dim then r.ImGui_DrawList_AddLine(dl, x + 4, y + 9, x + 8 + tw, y + 9, col, 1) end
  if can_x then
    local cx, cy, s = x + w - 8, y + 8.5, 2.5
    local xc = on_x and C.text or 0xA0A0A0FF
    r.ImGui_DrawList_AddLine(dl, cx - s, cy - s, cx + s, cy + s, xc, 1.2)
    r.ImGui_DrawList_AddLine(dl, cx - s, cy + s, cx + s, cy - s, xc, 1.2)
  end
  r.ImGui_PopFont(ctx)
  if hover then r.ImGui_SetTooltip(ctx, on_x and "Remove from the Bitwig list" or KEYS.TIP[k.kind]) end
  if not hit then return nil end
  if on_x then return "remove" end
  if k.kind == "lost" then return "add" end
  if k.kind ~= "hidden" then return "change" end
end

-- Bitwig's plain white plus
function KEYS.plus(id)
  local x, y = r.ImGui_GetCursorScreenPos(ctx)
  local hit = r.ImGui_InvisibleButton(ctx, "##plus" .. id, 16, 17)
  local col = r.ImGui_IsItemHovered(ctx) and C.accent or C.text
  local dl = r.ImGui_GetWindowDrawList(ctx)
  r.ImGui_DrawList_AddLine(dl, x + 3, y + 8.5, x + 13, y + 8.5, col, 1.2)
  r.ImGui_DrawList_AddLine(dl, x + 8, y + 3.5, x + 8, y + 13.5, col, 1.2)
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Add a key in the Bitwig list") end
  return hit
end

-- a black filter field with a cross on the right when it holds something
function KEYS.field_frame(x, y, w, h)
  r.ImGui_DrawList_AddRectFilled(r.ImGui_GetWindowDrawList(ctx), x, y, x + w, y + h, 0x000000FF)
end

function KEYS.clear_button(id, x, y)
  r.ImGui_SetCursorScreenPos(ctx, x, y)
  local hit = r.ImGui_InvisibleButton(ctx, "##clr" .. id, 18, 18)
  local col = r.ImGui_IsItemHovered(ctx) and C.text or 0xA0A0A0FF
  local dl = r.ImGui_GetWindowDrawList(ctx)
  local cx, cy, s = x + 9, y + 9, 3.5
  r.ImGui_DrawList_AddLine(dl, cx - s, cy - s, cx + s, cy + s, col, 1.4)
  r.ImGui_DrawList_AddLine(dl, cx - s, cy + s, cx + s, cy - s, col, 1.4)
  return hit
end

function KEYS.search_field(w)
  local x, y = r.ImGui_GetCursorScreenPos(ctx)
  KEYS.field_frame(x, y, w, 24)
  -- a small magnifier
  local dl = r.ImGui_GetWindowDrawList(ctx)
  r.ImGui_DrawList_AddCircle(dl, x + 11, y + 11, 4, 0xA0A0A0FF, 0, 1.2)
  r.ImGui_DrawList_AddLine(dl, x + 14, y + 14, x + 17, y + 17, 0xA0A0A0FF, 1.2)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), 0x00000000)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_TextDisabled(), 0x6E6E6EFF)
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FramePadding(), 4, 5)
  r.ImGui_SetCursorScreenPos(ctx, x + 22, y)
  r.ImGui_SetNextItemWidth(ctx, w - 44)
  local _, s = r.ImGui_InputTextWithHint(ctx, "##keysearch", "Type to filter actions", KEYS.search)
  KEYS.search = s
  r.ImGui_PopStyleVar(ctx)
  r.ImGui_PopStyleColor(ctx, 2)
  if KEYS.search ~= "" and KEYS.clear_button("s", x + w - 21, y + 3) then KEYS.search = "" end
  r.ImGui_SetCursorScreenPos(ctx, x, y + 24)
end

-- REAPER's names of the keys this field listens to (ImGui key -> text)
function KEYS.key_names()
  if not KEYS.knames then
    local t = {}
    local function add(imgui, name)
      local f = r["ImGui_Key_" .. imgui]
      if f then t[#t + 1] = { f(), name } end
    end
    for c in ("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"):gmatch(".") do add(c, c) end
    for i = 1, 12 do add("F" .. i, "F" .. i) end
    for _, p in ipairs({ { "Space", "Space" }, { "Backspace", "Backspace" }, { "Enter", "Enter" },
      { "Delete", "Delete" }, { "Tab", "Tab" }, { "Comma", "," }, { "Period", "." },
      { "UpArrow", "Up" }, { "DownArrow", "Down" }, { "LeftArrow", "Left" }, { "RightArrow", "Right" },
      { "Home", "Home" }, { "End", "End" }, { "Insert", "Insert" } }) do add(p[1], p[2]) end
    KEYS.knames = t
  end
  return KEYS.knames
end

function KEYS.read_key()
  for _, k in ipairs(KEYS.key_names()) do
    if r.ImGui_IsKeyPressed(ctx, k[1], false) then
      local s = ""
      if r.ImGui_IsKeyDown(ctx, r.ImGui_Mod_Ctrl()) then s = s .. "Ctrl+" end
      if r.ImGui_IsKeyDown(ctx, r.ImGui_Mod_Alt()) then s = s .. "Alt+" end
      if r.ImGui_IsKeyDown(ctx, r.ImGui_Mod_Shift()) then s = s .. "Shift+" end
      return s .. k[2]
    end
  end
end

-- "Press keyboard to filter": click it, press a key (with its modifiers), the list shows
-- the actions on that key
function KEYS.key_field(w)
  local x, y = r.ImGui_GetCursorScreenPos(ctx)
  KEYS.field_frame(x, y, w, 24)
  local clicked = r.ImGui_InvisibleButton(ctx, "##keyfield", w - 22, 24)
  local hovered = r.ImGui_IsItemHovered(ctx)
  if clicked then KEYS.capturing = true end
  if KEYS.capturing and r.ImGui_IsMouseClicked(ctx, 0) and not hovered then KEYS.capturing = false end
  local dl = r.ImGui_GetWindowDrawList(ctx)
  if KEYS.capturing then
    r.ImGui_DrawList_AddLine(dl, x + 6, y + 5, x + 6, y + 19, C.accent, 1.5)
    r.ImGui_SetNextFrameWantCaptureKeyboard(ctx, true)
    if r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_Escape(), false) then
      KEYS.capturing = false
    else
      local d = KEYS.read_key()
      if d then KEYS.keyfilter, KEYS.capturing = d, false end
    end
  end
  local text = KEYS.keyfilter ~= "" and KEYS.keyfilter or "Press keyboard to filter"
  r.ImGui_DrawList_AddText(dl, x + 10, y + 5, KEYS.keyfilter ~= "" and C.text or 0x6E6E6EFF, text)
  if KEYS.keyfilter ~= "" and KEYS.clear_button("k", x + w - 21, y + 3) then KEYS.keyfilter = "" end
  r.ImGui_SetCursorScreenPos(ctx, x, y + 24)
end

-- Bitwig's round orange tick box
function KEYS.tick(label, on)
  local x, y = r.ImGui_GetCursorScreenPos(ctx)
  local tw = r.ImGui_CalcTextSize(ctx, label)
  local hit = r.ImGui_InvisibleButton(ctx, "##tick" .. label, 26 + tw, 20)
  local dl = r.ImGui_GetWindowDrawList(ctx)
  if on then
    r.ImGui_DrawList_AddCircleFilled(dl, x + 9, y + 10, 8, C.accent)
    r.ImGui_DrawList_AddLine(dl, x + 5, y + 10, x + 8, y + 13, C.dark, 1.8)
    r.ImGui_DrawList_AddLine(dl, x + 8, y + 13, x + 13, y + 7, C.dark, 1.8)
  else
    r.ImGui_DrawList_AddCircle(dl, x + 9, y + 10, 8, 0x8C8C8CFF, 0, 1.2)
  end
  r.ImGui_DrawList_AddText(dl, x + 24, y + 3, C.text, label)
  return hit
end

function KEYS.table()
  local w = r.ImGui_GetContentRegionAvail(ctx)
  local half = math.floor((w - 8) / 2)
  local x0, y0 = r.ImGui_GetCursorScreenPos(ctx)
  KEYS.search_field(half)
  r.ImGui_SetCursorScreenPos(ctx, x0 + half + 8, y0)
  KEYS.key_field(w - half - 8)
  r.ImGui_SetCursorScreenPos(ctx, x0, y0 + 30)
  local list = KEYS.filtered()
  local _, avail_h = r.ImGui_GetContentRegionAvail(ctx)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ChildBg(), KEYS.LIST_BG)
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), 6, 4)
  local visible = r.ImGui_BeginChild(ctx, "##keylist", 0, math.max(160, avail_h - 32),
    r.ImGui_ChildFlags_AlwaysUseWindowPadding and r.ImGui_ChildFlags_AlwaysUseWindowPadding() or 0)
  r.ImGui_PopStyleVar(ctx)
  r.ImGui_PopStyleColor(ctx)
  if visible then
    if not r.ImGui_ValidatePtr(KEYS.clipper, "ImGui_ListClipper*") then
      KEYS.clipper = r.ImGui_CreateListClipper(ctx)
    end
    local cw = r.ImGui_GetContentRegionAvail(ctx)
    local name_w = math.floor(cw * 0.48)
    local dl = r.ImGui_GetWindowDrawList(ctx)
    local open_all = KEYS.search ~= "" or KEYS.keyfilter ~= ""
    r.ImGui_ListClipper_Begin(KEYS.clipper, #list, 23)
    while r.ImGui_ListClipper_Step(KEYS.clipper) do
      local a, b = r.ImGui_ListClipper_GetDisplayRange(KEYS.clipper)
      for i = a + 1, b do
        local row = list[i]
        local x, y = r.ImGui_GetCursorScreenPos(ctx)
        if row.head then
          -- the category: a fold arrow and its name in bold white
          if r.ImGui_InvisibleButton(ctx, "##head" .. i, cw, 23) and not open_all then
            KEYS.closed[row.head] = not KEYS.closed[row.head] or nil
            KEYS.ver = KEYS.ver + 1
          end
          local open = open_all or not KEYS.closed[row.head]
          local ax, ay = x + 8, y + 11.5
          if open then
            r.ImGui_DrawList_AddTriangleFilled(dl, ax - 3.5, ay - 2, ax + 3.5, ay - 2, ax, ay + 2.5, C.text)
          else
            r.ImGui_DrawList_AddTriangleFilled(dl, ax - 2, ay - 3.5, ax - 2, ay + 3.5, ax + 2.5, ay, C.text)
          end
          r.ImGui_PushFont(ctx, font, 13)
          r.ImGui_DrawList_AddText(dl, x + 20, y + 4, C.text, row.head)
          r.ImGui_PopFont(ctx)
        else
          local indent = 34
          r.ImGui_PushClipRect(ctx, x + indent, y, x + name_w - 6, y + 23, true)
          r.ImGui_DrawList_AddText(dl, x + indent, y + 4, #row.keys > 0 and C.text or 0xB4B4B4FF, row.short)
          r.ImGui_PopClipRect(ctx)
          r.ImGui_SetCursorScreenPos(ctx, x + indent, y)
          r.ImGui_InvisibleButton(ctx, "##name" .. i, name_w - indent - 6, 23)
          if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, row.name) end
          r.ImGui_SetCursorScreenPos(ctx, x + name_w, y + 3)
          for j, k in ipairs(row.keys) do
            if j > 1 then r.ImGui_SameLine(ctx, 0, 4) end
            local act = KEYS.chip(k, i .. "_" .. j)
            if act == "remove" then
              r.DeleteActionShortcut(r.SectionFromUniqueID(KEYS.lib().alt()), row.cmd, k.idx)
              KEYS.refresh(row.cmd)
            elseif act == "change" then
              KEYS.dialog(row.cmd, k.idx)
            elseif act == "add" then
              KEYS.dialog(row.cmd, -1)
            end
          end
          if #row.keys > 0 then r.ImGui_SameLine(ctx, 0, 8) end
          if KEYS.plus(i) then KEYS.dialog(row.cmd, -1) end
        end
        r.ImGui_SetCursorScreenPos(ctx, x, y + 23)
        r.ImGui_Dummy(ctx, 1, 0)
      end
    end
    if #list == 0 then
      r.ImGui_Dummy(ctx, 1, 6)
      text_col(C.dim, (KEYS.search ~= "" or KEYS.keyfilter ~= "") and "  Nothing matches." or "  No keys.")
    end
    r.ImGui_EndChild(ctx)
  end
  -- the bottom line: the tick box on the left, what the key colours mean on the right,
  -- both centred on the same 20 px row
  local bx, by = r.ImGui_GetCursorScreenPos(ctx)
  r.ImGui_SetCursorScreenPos(ctx, bx, by + 6)
  if KEYS.tick("Only actions with keys", KEYS.only_keys) then KEYS.only_keys = not KEYS.only_keys end
  r.ImGui_PushFont(ctx, font, 11)
  local legend = { { "bitwig", "Bitwig" }, { "own", "Yours" }, { "default", "REAPER default" }, { "lost", "Not active" } }
  local total = 0
  for i, l in ipairs(legend) do total = total + r.ImGui_CalcTextSize(ctx, l[2]) + (i > 1 and 14 or 0) end
  local _, th = r.ImGui_CalcTextSize(ctx, "Ay")
  local lx, ly = bx + w - total - 6, by + 6 + (20 - th) / 2
  local dl = r.ImGui_GetWindowDrawList(ctx)
  for _, l in ipairs(legend) do
    local tw = r.ImGui_CalcTextSize(ctx, l[2])
    r.ImGui_SetCursorScreenPos(ctx, lx, ly)
    text_col(KEYS.TXT[l[1]], l[2])
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, KEYS.TIP[l[1]]) end
    if l[1] == "lost" then r.ImGui_DrawList_AddLine(dl, lx, ly + th / 2 + 1, lx + tw, ly + th / 2 + 1, KEYS.TXT.lost, 1) end
    lx = lx + tw + 14
  end
  r.ImGui_PopFont(ctx)
  r.ImGui_SetCursorScreenPos(ctx, bx, by + 26)
  r.ImGui_Dummy(ctx, 1, 0)
end

local function page_shortcuts()
  local m = KEYS.lib()
  if not m then
    note("TK_Theme_Bit_Keys.lua is missing next to this script: update TK Theme Bit in ReaPack.")
    return
  end
  local installed = m.installed()
  if KEYS.restart then
    bar("Bitwig keys written: REAPER reads them after a restart.", {
      { "Restart REAPER now", 140, DARK.restart },
      { "Later", 60, function() KEYS.restart = false end },
    })
  elseif installed and KEYS.arrived == nil then
    KEYS.arrived = m.arrived()
  end
  if installed and KEYS.arrived == false and not KEYS.restart then
    bar("The Bitwig keys didn't arrive: REAPER rewrote its key file before the restart.", {
      { "Write them again", 140, function() m.install(m.alt()) KEYS.restart = true end },
    })
  end
  section("Shortcuts", function()
    row("Keyboard", function()
      local p = segmented("keys", { "REAPER", "Bitwig" }, (installed and m.active()) and 2 or 1)
      if p == 1 and installed then m.set_on(false)
      elseif p == 2 then
        if installed then m.set_on(true)
        else
          local ok, missing = m.install(KEYS.pick or m.suggest())
          if ok then
            KEYS.restart, KEYS.missing, KEYS.rows = true, missing, nil
          else
            KEYS.msg = missing
          end
        end
      end
    end)
    if installed then
      row("Bitwig list", function()
        r.ImGui_AlignTextToFramePadding(ctx)
        text_col(C.text, "alt-" .. m.alt())
        if r.ImGui_IsItemHovered(ctx) then
          r.ImGui_SetTooltip(ctx, "REAPER's alternative key list Main (alt-" .. m.alt() .. "), in front of your "
            .. "own keys while Bitwig is on.\nA key not in it works as in REAPER's defaults, not as your own keys: "
            .. "those are struck through below and can be added.")
        end
        r.ImGui_SameLine(ctx, 0, 12)
        if action_button("Defaults", 76) then
          local ok, missing = m.install(m.alt())
          if ok then KEYS.restart, KEYS.missing = true, missing else KEYS.msg = missing end
        end
        if r.ImGui_IsItemHovered(ctx) then
          r.ImGui_SetTooltip(ctx, "Put Bitwig's keys back as they came (needs a restart). Keys you added stay.")
        end
        r.ImGui_SameLine(ctx, 0, 4)
        if action_button("Remove", 70) then m.remove() KEYS.rows = nil KEYS.arrived = nil end
        if r.ImGui_IsItemHovered(ctx) then
          r.ImGui_SetTooltip(ctx, "Take the Bitwig keys out of the list and stop switching it on. Keys you added stay.")
        end
      end)
      note("Changes below work at once. Hover a key for what it is.")
    else
      local counts = m.alt_lists()
      KEYS.pick = KEYS.pick or m.suggest()
      row("Use list", function()
        r.ImGui_SetNextItemWidth(ctx, 180)
        local label = ("Main (alt-%d)"):format(KEYS.pick)
        if r.ImGui_BeginCombo(ctx, "##altlist", label) then
          for n = 1, 16 do
            local text = ("Main (alt-%d)   %s"):format(n, counts[n] == 0 and "empty" or counts[n] .. " keys")
            if r.ImGui_Selectable(ctx, text, n == KEYS.pick) then KEYS.pick = n end
          end
          r.ImGui_EndCombo(ctx)
        end
      end)
      if counts[KEYS.pick] > 0 then
        note(("This list holds %d keys already: the Bitwig keys are added to it and win where they clash.")
          :format(counts[KEYS.pick]))
      end
      note("Bitwig's keys go into one of REAPER's 16 alternative key lists; your own keys are never changed. "
        .. "The first time needs a restart.")
    end
    if KEYS.msg then note(KEYS.msg) end
    if KEYS.missing and #KEYS.missing > 0 then
      note("Not found in this REAPER, left out: " .. table.concat(KEYS.missing, ", "))
    end
  end)
  if installed and not KEYS.restart then
    KEYS.table()
  end
end

local PAGES = {
  { "Transport", page_transport },
  { "Display", page_display },
  { "Arrange", page_arrange },
  { "Tracks & Mixer", page_tracks },
  { "Window", page_window },
  { "Shortcuts", page_shortcuts },
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

-- HELP: chapters in the sidebar, as the SETTINGS pages. Each chapter is a list of blocks:
--   { "h", "Heading" }            a sub heading
--   { "p", "Text" }               a paragraph
--   { "k", "Key / mouse", "What" } a key or mouse action with what it does
--   { "i", "Name", "What" }        a named thing (icon, button, setting) with what it does
local HELP = { page = 1 }
HELP.CHAPTERS = {
  { "Getting started", {
    { "p", "TK Theme Bit is a REAPER theme in the style of a modern flat DAW, with a few scripts that add "
      .. "what the theme alone can't: menus, an inspector, an audio editor, Bitwig's keys." },
    { "h", "What you need" },
    { "i", "ReaImGui", "Draws the menus, the inspector, Clip Edit and this window. Required." },
    { "i", "SWS", "Lets the settings change REAPER preferences (labels, grid, default volume). Recommended." },
    { "i", "js_ReaScriptAPI", "Lets the audio editor icon close SneakPeak. Only needed for that." },
    { "p", "All three come through ReaPack. Install them, then restart REAPER." },
    { "h", "Opening this window" },
    { "p", "Click the gear next to the transport display, or the logo above it when it's shown. "
      .. "USER holds your projects, SETTINGS the theme's options, HELP this text." },
    { "h", "Closing a panel script" },
    { "p", "Panels (inspector, Clip Edit, devices) close when you run them again. The first time REAPER "
      .. "may ask whether to end the running script: tick \"Remember my answer\" and choose Terminate." },
  } },
  { "Transport", {
    { "i", "FILE  ADD  EDIT", "Menus with what you need most, each with its icon and your own shortcut. "
      .. "They replace REAPER's menu bar, which you can hide (Settings > Window)." },
    { "i", "Play  Stop  Record", "Bitwig's three keys. Settings > Transport adds rewind, pause and forward." },
    { "i", "Display", "Position, tempo and time signature. The time selection shows as Start, End and "
      .. "Length, stacked. Optional: play rate (Settings > Transport)." },
    { "i", "Follow", "The key in the display: the view follows the playhead. How it scrolls is set in "
      .. "Settings > Arrange." },
    { "i", "Logo", "Bit's dot mark over the display (optional). Click it for these settings." },
    { "h", "Panel icons (right)" },
    { "p", "Like Bitwig's panel icons. Orange means open; click an orange one again to close it." },
    { "i", "Devices", "Opens the device panel: TK Bit Devices, Saxmand's FX Modulator Linking, or an action you choose." },
    { "i", "Audio editor", "Opens Clip Edit for the selected audio clip (or SneakPeak, or an action you choose)." },
    { "i", "MIDI editor", "Opens the selected MIDI clip. One view at a time: it closes the mixer." },
    { "i", "Mixer", "Shows the mixer and closes the MIDI editor." },
    { "i", "Inspector", "Opens the inspector panel (after the line)." },
    { "i", "Clip launcher", "Opens the clip launcher (see that chapter)." },
    { "p", "Each icon can be switched off in Settings > Transport. They hide when the bar is too narrow." },
  } },
  { "Inspector", {
    { "p", "Like Bitwig's inspector: it shows what you touched last. Dock it at the left with the icon at its top." },
    { "i", "Track", "Name, colour, volume, pan, mute / solo / arm / monitoring, input, output, sends, FX." },
    { "i", "Clip", "Name, colour, position, gain, pan, fades, pitch, rate, mute / loop / reverse, source. "
      .. "Changes go to every selected clip." },
    { "i", "Envelope", "Select an envelope lane: the lane on top (active, visible, armed, shape) and the "
      .. "selected points below. Works in automation items too." },
    { "i", "Time range", "Nothing selected: the time selection's start, end and length." },
    { "i", "TRACK | CLIP", "At the top: pick one by hand. It follows the selection again when you click elsewhere." },
    { "h", "Changing a value" },
    { "k", "Drag up or right", "Change it. Hold Shift for fine steps." },
    { "k", "Double-click", "Type a value." },
    { "k", "Right-click", "Back to the default." },
  } },
  { "Clip Edit", {
    { "p", "The theme's own audio editor, like Bitwig's. It follows the selected audio clip; dock it at the "
      .. "bottom. Open it with the audio editor icon or the E key (Bitwig shortcuts)." },
    { "i", "Clip | Track", "Clip: the clips on that track that touch each other, each one an event. "
      .. "Track: all clips of the track." },
    { "h", "Tools (keys at the right)" },
    { "i", "Pointer", "Select and move events. Drag an event's edge to trim it; Alt+drag slips the audio inside." },
    { "i", "Time selection", "Drag a time selection." },
    { "i", "Draw", "Add volume envelope points." },
    { "i", "Erase", "Remove points and stretch markers." },
    { "i", "Knife", "Split an event." },
    { "i", "Stretch", "Add stretch markers. Dashed lines are transients: drag one to make it a marker." },
    { "h", "In the event" },
    { "i", "Fades", "Drag the white squares. Right-click one for the next shape." },
    { "i", "Gain", "Drag the dB box in the event's header. Double-click: 0 dB." },
    { "i", "Lanes", "Volume, pan and pitch under the waveform. Right-click a lane to choose. "
      .. "Hover or drag a point to see its value." },
    { "h", "Right-click menu" },
    { "p", "Trim to time selection, reverse, normalize, slice at transients, stretch markers on transients, "
      .. "transient sensitivity, quantize events or stretch markers (strength 25-100%, only inside a time "
      .. "selection when there is one), remove markers or points, fade shapes." },
    { "h", "Keys and mouse" },
    { "k", "Wheel", "Scroll." },
    { "k", "Ctrl+wheel", "Zoom." },
    { "k", "Alt+wheel", "A taller waveform." },
    { "k", "Shift", "No snap, fine steps." },
    { "k", "Alt- or right-click", "Delete a point or marker." },
    { "k", "Space / S / Ctrl+Z", "Play / split / undo, while the panel has focus." },
    { "k", "Delete / Ctrl+D", "Delete / duplicate the selected events." },
    { "p", "The grid button (1/16 and so on) sets the project grid; Snap is in its menu. The overview at the bottom scrolls." },
  } },
  { "Clip Launcher", {
    { "p", "Bitwig's clip launcher: clips wait in slots and play on the project's bars, together with the "
      .. "arrangement. Every track is a row, lined up with the arrange; every scene is a column." },
    { "h", "Opening it" },
    { "i", "Launcher icon", "The grid icon left of Devices opens and closes it. Orange while open. "
      .. "Settings > Transport can hide it." },
    { "i", "Docking", "Click the dock icon at its top, and put that docker left of the arrange. The rows then "
      .. "line up with the arrange's tracks (exactly with js_ReaScriptAPI)." },
    { "p", "While it's open, REAPER's own track panel is hidden: the launcher has its own track headers. "
      .. "Switch that off in the Q menu." },
    { "h", "The layout" },
    { "i", "Track header", "Name, rec / S / M, volume and a meter. Click selects the track (Ctrl adds, Shift "
      .. "selects a range), double-click renames it, right-click opens REAPER's track menu. Drag its bottom "
      .. "edge to change the height." },
    { "i", "Envelope rows", "An envelope with its own lane gets its own row, with a bar for its value. Click "
      .. "selects it, right-click opens REAPER's envelope menu, the bottom edge sets the height." },
    { "i", "Stop square", "Left of the slots. Stops the track's clip on the next line. The track stays with "
      .. "the launcher, silent, until you click its return arrow." },
    { "i", "Return arrow", "Right of the slots. Orange while the launcher plays the track instead of the "
      .. "arrangement. Click it to give the track back to the arrangement at once." },
    { "i", "Top row", "Stop all (left), the scene buttons, + to add a scene, and all back to the "
      .. "arrangement (right)." },
    { "i", "Master row", "When the master shows in the track panel: a launch button per scene, stop all and "
      .. "all back to the arrangement." },
    { "h", "Toolbar (top left)" },
    { "i", "Q", "Launch Q, the grid that launches, stops and recordings land on (shows e.g. 1 bar). Its "
      .. "menu also holds the project's defaults and switches." },
    { "i", "Track panel icon", "Shows or hides REAPER's own track panel." },
    { "i", "Red dot", "REC: writes what the launcher plays into the arrangement (see below)." },
    { "i", "H", "Full track headers, or names only." },
    { "i", "Eye", "Shows or hides the Bit Launcher tracks, where the clips are kept." },
    { "i", "Dock / close", "The dock icon docks or floats the launcher; the cross at the top right closes it." },
    { "h", "Launching and stopping" },
    { "i", "Triangle", "Click the small box with the triangle to launch the clip. It waits for the next "
      .. "Launch Q line: the box blinks while it waits, stays light while it plays, and a line runs "
      .. "through the clip." },
    { "p", "A launched clip takes its track from the arrangement: from that line the track's own items are "
      .. "muted. Stopping the transport gives every track back to the arrangement." },
    { "i", "Launch Q values", "Off (as soon as possible, about 0.3 s ahead), 1/16 to 1/2, or 1 to 8 bars. "
      .. "The Q menu sets it for the project; a clip can have its own (clip menu > Main)." },
    { "i", "Play mode", "Trigger from Start: from the beginning. Legato from Clip: from where the playing clip "
      .. "on that track is (or from the start / from the project's position when none plays). Legato from "
      .. "Project: from the position counted from the project's start." },
    { "i", "Release", "What happens when you let go of the triangle. Continue: nothing. Stop: silent at once. "
      .. "Return: back to the clip that played before, or to the arrangement. Next Action: runs it now." },
    { "i", "Alt-click", "Uses the clip's ALT settings instead. Defaults: Q Off, Legato from Clip, Release Return: "
      .. "hold the mouse on a variation, let go to return." },
    { "i", "Next Action", "Clip menu. After 1 to 16 loops: stop, back to the arrangement or the last clip, or "
      .. "play the next, previous, first, last, a random, another, or round-robin. A small arrow marks the clip." },
    { "h", "Scenes" },
    { "i", "Scene button", "Launches every clip in that column. Tracks without a clip there stop." },
    { "i", "Right-click", "Rename, insert a scene before it, or delete it with its clips." },
    { "k", "Shift+wheel", "Scroll the scenes when they don't all fit." },
    { "h", "Adding clips" },
    { "i", "+ in an empty slot", "Hover an empty slot: the + adds the arrange's selected items from here "
      .. "(several fill the next slots), or opens a file dialog when nothing is selected." },
    { "i", "Drop a file", "From Windows Explorer, REAPER's Media Explorer, or TK Media Browser / Workbench." },
    { "i", "Tempo", "Audio files follow the project tempo, read from the file, its name (\"120bpm\") or "
      .. "guessed. Per clip in its menu; for all files in the Q menu. Clips from the arrange keep their speed." },
    { "p", "A click on an empty slot stops the track, or starts recording when the track is armed." },
    { "h", "Recording into a slot" },
    { "p", "Arm the track and click an empty slot (it shows a dot). Recording starts on the next Launch Q "
      .. "line; a stopped transport starts. Click the slot again, or its stop square, to stop on the nearest "
      .. "line. The clip is cut from the take and plays at once; the take leaves the arrangement." },
    { "p", "REAPER records every armed track: other armed tracks record into the arrangement as usual." },
    { "h", "Editing a clip" },
    { "k", "Double-click a clip", "MIDI opens in the MIDI editor (changes are heard while it plays). Audio "
      .. "opens in Clip Edit (changes are heard from the next launch)." },
    { "i", "Inspector", "Click a clip and the inspector shows it; changes there go to the clip. Colours "
      .. "are shared: set in either place, they show in both." },
    { "i", "Clip menu", "Right-click: launch, launch with ALT, edit, rename, colour, Main and ALT settings, "
      .. "Next Action, tempo, copy to the arrangement at the edit cursor, delete." },
    { "h", "Automation clips" },
    { "p", "In an envelope row: select an automation item on that lane, or make a time selection, then "
      .. "click the + in an empty slot. Launching lays the curve over the envelope as a looping automation "
      .. "item; stopping gives the envelope its own points back." },
    { "p", "A track clip's launch also launches the automation clips in the same column. Right-click an "
      .. "automation clip to copy it into the arrangement." },
    { "h", "Into the arrangement" },
    { "i", "REC (red dot)", "While it's on, every clip and automation clip that plays is written onto its "
      .. "track when the transport stops or REC goes off. Existing items stay; the new ones lie on top." },
    { "i", "Copy to arrangement", "Clip menu: one pass of the clip at the edit cursor." },
    { "h", "Behind the scenes" },
    { "i", "Bit Launcher tracks", "One hidden track per track with clips. It holds the clips and sends into "
      .. "the real track, so you hear its effects. Show them with the eye; don't delete them." },
    { "i", "Gate", "A small effect (TK Bit Launcher Gate) on such a track, for a release that has to stop at "
      .. "once. It comes when needed and goes when no clip on that track uses Stop or Return. With the ALT "
      .. "release on Return (the default) it stays." },
    { "i", "Safety", "Muted arrange items come back when the launcher closes, when the transport stops, and "
      .. "after a crash the next time it opens." },
    { "i", "Undo", "Launcher changes are normal undo steps (\"Launcher: ...\")." },
    { "h", "Mouse and keys" },
    { "k", "Click the triangle", "Launch. Alt+click: with ALT settings." },
    { "k", "Click a clip", "Select it (inspector)." },
    { "k", "Drag a clip", "Move it to another slot. Hold Ctrl when you let go to copy it." },
    { "k", "Wheel", "Scroll the tracks. Shift+wheel: the scenes." },
    { "k", "Enter / Delete", "Launch / delete the selected clip." },
    { "k", "Space / Ctrl+Z / Ctrl+Y", "Play / undo / redo, while the launcher has focus." },
  } },
  { "Mixer & tracks", {
    { "i", "Input row", "Its icon is the monitoring switch." },
    { "i", "Phase  -10  Automation", "Small icons at the top of the sends area. -10 sets that track to "
      .. "-10 dB (the whole selection when the track is in it)." },
    { "i", "-10 dB", "Bitwig starts tracks at -10 dB for headroom. Settings > Tracks & Mixer sets it for "
      .. "new tracks, and has a button for the selected ones." },
    { "i", "Numbers", "Bitwig shows no track numbers; small ones can be added (Settings > Tracks & Mixer)." },
    { "i", "Meters", "Peak, Peak/RMS or LUFS-M for every track in the project." },
  } },
  { "Shortcuts", {
    { "p", "Settings > Shortcuts gives REAPER Bitwig's keys, and switches back at once." },
    { "h", "How it works" },
    { "p", "REAPER has 16 alternative key lists. The Bitwig keys go into the one you choose; Bitwig puts it "
      .. "in front of your own keys, REAPER takes it away. Your own key list is never changed." },
    { "p", "The first time needs a restart of REAPER. After that, switching and editing work at once." },
    { "p", "While Bitwig is on, a key that isn't in the list works as in REAPER's defaults, not as you set it "
      .. "yourself. Those keys show struck through: click one to add it to the Bitwig list." },
    { "h", "The list" },
    { "k", "Type to filter", "Find actions by name." },
    { "k", "Press keyboard to filter", "Click it, press a key: the actions on that key." },
    { "k", "Click a key", "Change it. The cross removes it." },
    { "k", "+", "Add a key." },
    { "i", "Colours", "Orange: Bitwig. White: yours. Grey: REAPER's default. Struck through: not active." },
    { "i", "Defaults", "Puts Bitwig's keys back as they came (restart). Keys you added stay." },
    { "i", "Remove", "Takes the Bitwig keys out. Keys you added stay." },
    { "h", "Some keys" },
    { "k", "M  E  D  I  O", "Mixer, editor, devices, inspector, arranger." },
    { "k", "Ctrl+E  Ctrl+D  Ctrl+J", "Split, duplicate, consolidate." },
    { "k", "F9  C  Shift+L  Shift+F", "Record, metronome, loop, follow." },
  } },
  { "Settings", {
    { "i", "Transport", "Which keys and icons the bar shows, the logo, and what Devices and Audio editor open." },
    { "i", "Clip launcher", "Settings > Transport: show or hide its icon, and open or close it. Its own "
      .. "settings are in the launcher's Q menu." },
    { "i", "Display", "Contrast (REAPER's own colour controls), timeline background, beat grid colour and lines." },
    { "i", "Arrange", "Grid lines through clips, the seconds-over-bars ruler, item names, clip header size, "
      .. "playhead follow." },
    { "i", "Tracks & Mixer", "Default volume, track list volume, mixer strip widths (tracks, master), meters, track numbers." },
    { "i", "Window", "Theme size, REAPER's window colours, TK icons, the menu bar." },
    { "i", "Shortcuts", "Bitwig's keys (see that chapter)." },
    { "p", "Right-click a slider for its default. A note under a setting says when it needs SWS or a restart." },
  } },
  { "Icons", {
    { "p", "REAPER's own toolbar icons follow the theme: white, orange when on, no frame." },
    { "p", "TK's own icons (TK_...) come as a separate ReaPack package, TK Toolbar Icons, in a TK and a "
      .. "Bit look. Bit keeps them in its look; choose another in Settings > Window. A window shows new "
      .. "icons the next time it opens." },
  } },
}

function HELP.sidebar()
  local pages = {}
  for i, c in ipairs(HELP.CHAPTERS) do pages[i] = { c[1] } end
  HELP.page = sidebar(pages, HELP.page)
end

-- a key or name in a small grey pill (as the shortcut list), its text after it
function HELP.pair(left, right, pill)
  local x0, y0 = r.ImGui_GetCursorScreenPos(ctx)
  local col_w = 150
  local dl = r.ImGui_GetWindowDrawList(ctx)
  if pill then
    r.ImGui_PushFont(ctx, font, 11)
    local tw, th = r.ImGui_CalcTextSize(ctx, left)
    r.ImGui_DrawList_AddRectFilled(dl, x0, y0 + 1, x0 + tw + 12, y0 + 17, KEYS.PILL, 4)
    r.ImGui_DrawList_AddText(dl, x0 + 6, y0 + (18 - th) / 2, C.text, left)
    r.ImGui_PopFont(ctx)
  else
    r.ImGui_DrawList_AddText(dl, x0, y0 + 1, C.text, left)
  end
  r.ImGui_SetCursorScreenPos(ctx, x0 + col_w, y0 + 1)
  r.ImGui_PushTextWrapPos(ctx, 0)
  text_col(C.dim, right, true)
  r.ImGui_PopTextWrapPos(ctx)
  r.ImGui_Dummy(ctx, 1, 4)
end

function HELP.page_draw()
  local c = HELP.CHAPTERS[HELP.page]
  r.ImGui_PushFont(ctx, font, 20)
  text_col(C.text, c[1])
  r.ImGui_PopFont(ctx)
  r.ImGui_Dummy(ctx, 1, 6)
  for _, b in ipairs(c[2]) do
    if b[1] == "h" then
      r.ImGui_Dummy(ctx, 1, 6)
      r.ImGui_PushFont(ctx, font, 13)
      text_col(C.accent, b[2]:upper())
      r.ImGui_PopFont(ctx)
      r.ImGui_Dummy(ctx, 1, 2)
    elseif b[1] == "p" then
      r.ImGui_PushTextWrapPos(ctx, 0)
      text_col(C.dim, b[2], true)
      r.ImGui_PopTextWrapPos(ctx)
      r.ImGui_Dummy(ctx, 1, 4)
    else
      HELP.pair(b[2], b[3], b[1] == "k")
    end
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
  -- the height can be dragged at the bottom edge (the width stays); the last one is kept
  if not KEYS.height then KEYS.height = tonumber(r.GetExtState(EXT, "settings_h")) or H end
  r.ImGui_SetNextWindowSize(ctx, W, KEYS.height, r.ImGui_Cond_Appearing())
  r.ImGui_SetNextWindowSizeConstraints(ctx, W, H, W, 3000)
  local flags = r.ImGui_WindowFlags_NoTitleBar() | r.ImGui_WindowFlags_NoCollapse()
  local visible, open = r.ImGui_Begin(ctx, "TK Theme Bit settings", true, flags)
  if visible then
    local _, h = r.ImGui_GetWindowSize(ctx)
    if math.abs(h - KEYS.height) >= 1 and not r.ImGui_IsMouseDown(ctx, 0) then
      KEYS.height = math.floor(h)
      r.SetExtState(EXT, "settings_h", tostring(KEYS.height), true)
    end
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
      if r.ImGui_BeginChild(ctx, "##hside", SIDEBAR, 0) then
        HELP.sidebar()
        r.ImGui_EndChild(ctx)
      end
      r.ImGui_SameLine(ctx)
      if r.ImGui_BeginChild(ctx, "##hpage", 0, 0) then
        HELP.page_draw()
        r.ImGui_EndChild(ctx)
      end
    end
    r.ImGui_End(ctx)
  end
  r.ImGui_PopStyleVar(ctx, 3)
  r.ImGui_PopStyleColor(ctx, 5)
  r.ImGui_PopFont(ctx)
  if U.close then open = false end   -- a project was opened: off, as Bitwig's dashboard
  -- REAPER's shortcut dialog (modal) runs here, between frames; a context left unused
  -- while it was open may be gone afterwards, so a new one takes over
  if KEYS.after then
    local f = KEYS.after
    KEYS.after = nil
    f()
    if not r.ImGui_ValidatePtr(ctx, "ImGui_Context*") then
      ctx = r.ImGui_CreateContext("TK Theme Bit settings")
      font = r.ImGui_CreateFont("Inter")
      r.ImGui_Attach(ctx, font)
      KEYS.clipper = nil
    end
  end
  if open then r.defer(loop) end
end

look_restore()
devices_first_run()
ICONS.startup()
r.defer(loop)
