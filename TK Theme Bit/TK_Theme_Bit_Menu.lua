-- TK Theme Bit - shared popup menu for the transport's FILE / ADD / EDIT buttons, drawn as
-- Bitwig's menus: a dark panel, an icon per entry, the name, the shortcut on the right (read
-- live from REAPER, so your own key bindings show), thin separators, a light bar under the
-- mouse. It closes on a choice, a click elsewhere, Escape, or another click on its button.
-- Without ReaImGui it falls back to a plain system menu.
--
-- An item is { command id, icon, label } (the label may be left out: REAPER's own name is
-- used then), a bare command id, or 0 for a separator.

local r = reaper
local M = {}

local function reaper_label(id)
  local name = r.kbd_getTextFromCmd(id, 0) or ""
  name = name:gsub("^[^:]+:%s*", "")          -- "File: Save project" -> "Save project"
  if name == "" then name = "Command " .. id end
  return name
end

local function norm(item)
  if item == 0 then return nil end
  if type(item) == "number" then return { id = item, label = reaper_label(item) } end
  return { id = item[1], icon = item[2], label = item[3] or reaper_label(item[1]) }
end

-- the shortcut REAPER has for an action now (the first one), or ""
local main_section = r.SectionFromUniqueID and r.SectionFromUniqueID(0)
local function shortcut(id)
  if not (main_section and r.CountActionShortcuts) then return "" end
  for i = 0, r.CountActionShortcuts(main_section, id) - 1 do
    local ok, desc = r.GetActionShortcutDesc(main_section, id, i, "")
    if ok and desc and desc ~= "" then return desc end
  end
  return ""
end

-- greyed out when it can do nothing (as Bitwig's menus)
local function enabled(id)
  if id == 40029 then return r.Undo_CanUndo2(0) ~= nil end
  if id == 40030 then return r.Undo_CanRedo2(0) ~= nil end
  return true
end

---------------------------------------------------------------- the old menu
local function system_menu(items)
  local parts, ids = {}, {}
  for _, it in ipairs(items) do
    local n = norm(it)
    if not n then
      parts[#parts + 1] = ""
    else
      parts[#parts + 1] = n.label:gsub("[|#!<>&]", "")
      ids[#ids + 1] = n.id
    end
  end
  local x, y = r.GetMousePosition()
  gfx.init("TK Theme Bit menu", 0, 0, 0, x, y)
  gfx.x, gfx.y = 0, 0
  local choice = gfx.showmenu(table.concat(parts, "|"))
  gfx.quit()
  if choice > 0 and ids[choice] then r.Main_OnCommand(ids[choice], 0) end
end

---------------------------------------------------------------- icons
-- 14 x 14, drawn in col with its top left at x, y
local function rect(dl, x1, y1, x2, y2, col, w) r.ImGui_DrawList_AddRect(dl, x1, y1, x2, y2, col, 1, 0, w or 1.3) end
local function fill(dl, x1, y1, x2, y2, col) r.ImGui_DrawList_AddRectFilled(dl, x1, y1, x2, y2, col, 1) end
local function line(dl, x1, y1, x2, y2, col, w) r.ImGui_DrawList_AddLine(dl, x1, y1, x2, y2, col, w or 1.3) end
local function tri(dl, x1, y1, x2, y2, x3, y3, col) r.ImGui_DrawList_AddTriangleFilled(dl, x1, y1, x2, y2, x3, y3, col) end

local function page(dl, x, y, col)              -- a page with a folded corner
  rect(dl, x + 3, y + 1, x + 11, y + 13, col)
  tri(dl, x + 8, y + 1, x + 11, y + 1, x + 11, y + 4, col)
end

local ICONS = {
  new = function(dl, x, y, col)
    page(dl, x, y, col)
    line(dl, x + 7, y + 6, x + 7, y + 11, col); line(dl, x + 4.5, y + 8.5, x + 9.5, y + 8.5, col)
  end,
  open = function(dl, x, y, col)                 -- a folder
    fill(dl, x + 1, y + 3, x + 6, y + 5, col)
    rect(dl, x + 1, y + 4, x + 13, y + 12, col)
  end,
  save = function(dl, x, y, col)                 -- a disk
    rect(dl, x + 1.5, y + 1.5, x + 12.5, y + 12.5, col)
    fill(dl, x + 4, y + 1.5, x + 10, y + 5, col)
    fill(dl, x + 4, y + 8, x + 10, y + 12.5, col)
  end,
  saveas = function(dl, x, y, col)               -- a disk with a pencil
    rect(dl, x + 1.5, y + 1.5, x + 10.5, y + 10.5, col)
    fill(dl, x + 3.5, y + 1.5, x + 8.5, y + 4.5, col)
    line(dl, x + 7, y + 13, x + 13, y + 7, col, 2)
  end,
  render = function(dl, x, y, col)               -- out of a box
    rect(dl, x + 1.5, y + 6, x + 12.5, y + 13, col)
    line(dl, x + 7, y + 1, x + 7, y + 9, col, 1.6)
    tri(dl, x + 3.5, y + 4, x + 10.5, y + 4, x + 7, y + 0.5, col)
  end,
  settings = function(dl, x, y, col)             -- three sliders
    for k = 0, 2 do
      local yy = y + 3 + k * 4
      line(dl, x + 1, yy, x + 13, yy, col, 1.1)
      fill(dl, x + 3 + k * 3, yy - 1.5, x + 6 + k * 3, yy + 1.5, col)
    end
  end,
  prefs = function(dl, x, y, col)                -- a gear
    r.ImGui_DrawList_AddCircle(dl, x + 7, y + 7, 3.2, col, 0, 1.6)
    for k = 0, 7 do
      local a = k * math.pi / 4
      line(dl, x + 7 + math.cos(a) * 4.2, y + 7 + math.sin(a) * 4.2, x + 7 + math.cos(a) * 6.2, y + 7 + math.sin(a) * 6.2, col, 2)
    end
  end,
  track = function(dl, x, y, col)                -- Bitwig's audio track glyph: a wave on a bar
    line(dl, x + 2, y + 2, x + 2, y + 12, col, 1.6)
    for k, h in ipairs({ 4, 8, 5, 10, 6, 3 }) do
      line(dl, x + 3.5 + k * 1.6, y + 7 - h / 2, x + 3.5 + k * 1.6, y + 7 + h / 2, col, 1)
    end
  end,
  instrument = function(dl, x, y, col)           -- Bitwig's instrument glyph: keys
    rect(dl, x + 1, y + 2, x + 13, y + 12, col)
    for k = 1, 3 do line(dl, x + 1 + k * 3, y + 2, x + 1 + k * 3, y + 12, col, 1) end
    for k = 1, 3 do fill(dl, x + k * 3 - 0.2, y + 2, x + k * 3 + 2.2, y + 7.5, col) end
  end,
  media = function(dl, x, y, col)                -- a page with a wave
    page(dl, x, y, col)
    for k, h in ipairs({ 2, 5, 3, 4 }) do line(dl, x + 4 + k * 1.3, y + 8 - h / 2, x + 4 + k * 1.3, y + 8 + h / 2, col, 1) end
  end,
  marker = function(dl, x, y, col)               -- Bitwig's cue marker flag
    line(dl, x + 3, y + 1, x + 3, y + 13, col, 1.6)
    tri(dl, x + 3, y + 1.5, x + 11, y + 4.5, x + 3, y + 7.5, col)
  end,
  region = function(dl, x, y, col)               -- a range with ends
    line(dl, x + 1.5, y + 3, x + 1.5, y + 11, col, 1.6)
    line(dl, x + 12.5, y + 3, x + 12.5, y + 11, col, 1.6)
    fill(dl, x + 3, y + 5.5, x + 11, y + 8.5, col)
  end,
  undo = function(dl, x, y, col)
    r.ImGui_DrawList_PathArcTo(dl, x + 7.5, y + 8, 4.5, math.pi * 1.1, math.pi * 2.2)
    r.ImGui_DrawList_PathStroke(dl, col, 0, 1.6)
    tri(dl, x + 0.5, y + 7, x + 6, y + 7, x + 3, y + 2.5, col)
  end,
  redo = function(dl, x, y, col)
    r.ImGui_DrawList_PathArcTo(dl, x + 6.5, y + 8, 4.5, math.pi * 0.8, math.pi * 1.9)
    r.ImGui_DrawList_PathStroke(dl, col, 0, 1.6)
    tri(dl, x + 8, y + 7, x + 13.5, y + 7, x + 11, y + 2.5, col)
  end,
  cut = function(dl, x, y, col)                  -- scissors
    r.ImGui_DrawList_AddCircle(dl, x + 3.5, y + 10.5, 2.2, col, 0, 1.3)
    r.ImGui_DrawList_AddCircle(dl, x + 10.5, y + 10.5, 2.2, col, 0, 1.3)
    line(dl, x + 5, y + 9, x + 11, y + 1, col); line(dl, x + 9, y + 9, x + 3, y + 1, col)
  end,
  copy = function(dl, x, y, col)                 -- two pages
    rect(dl, x + 1.5, y + 1.5, x + 9, y + 9.5, col)
    fill(dl, x + 5, y + 4.5, x + 12.5, y + 12.5, col)
  end,
  paste = function(dl, x, y, col)                -- a clipboard
    rect(dl, x + 2, y + 2.5, x + 12, y + 13, col)
    fill(dl, x + 4.5, y + 1, x + 9.5, y + 4, col)
  end,
  delete = function(dl, x, y, col)               -- a cross in a circle, as Bitwig's
    r.ImGui_DrawList_AddCircle(dl, x + 7, y + 7, 6, col, 0, 1.4)
    line(dl, x + 4.5, y + 4.5, x + 9.5, y + 9.5, col, 1.5); line(dl, x + 9.5, y + 4.5, x + 4.5, y + 9.5, col, 1.5)
  end,
  selclips = function(dl, x, y, col)             -- clips in a dashed frame
    for k = 0, 3 do
      line(dl, x + 1 + k * 3.4, y + 1, x + 2.8 + k * 3.4, y + 1, col, 1)
      line(dl, x + 1 + k * 3.4, y + 13, x + 2.8 + k * 3.4, y + 13, col, 1)
    end
    fill(dl, x + 2, y + 4, x + 7, y + 10, col); fill(dl, x + 8, y + 4, x + 12, y + 10, col)
  end,
  seltracks = function(dl, x, y, col)            -- stacked track rows
    for k = 0, 2 do fill(dl, x + 1, y + 1.5 + k * 4, x + 13, y + 4 + k * 4, col) end
  end,
  split = function(dl, x, y, col)                -- a clip cut in two
    fill(dl, x + 1, y + 4, x + 6, y + 10, col); fill(dl, x + 8, y + 4, x + 13, y + 10, col)
    line(dl, x + 7, y + 0.5, x + 7, y + 13.5, col, 1.2)
  end,
  duplicate = function(dl, x, y, col)            -- a clip and its copy with a plus
    fill(dl, x + 1, y + 3, x + 7, y + 11, col)
    rect(dl, x + 8, y + 3, x + 13, y + 11, col)
    line(dl, x + 10.5, y + 5, x + 10.5, y + 9, col, 1.1); line(dl, x + 8.5, y + 7, x + 12.5, y + 7, col, 1.1)
  end,
}

---------------------------------------------------------------- the Bitwig menu
-- colours measured from Bitwig's menus: panel 30, the bar under the mouse 70, separators
-- 58, text white, shortcuts grey, icons light grey
local C = {
  bg = 0x1E1E1EFF, border = 0x3A3A3AFF, hover = 0x464646FF, sep = 0x3A3A3AFF,
  text = 0xEEEEEEFF, dim = 0x6E6E6EFF, keys = 0x9E9E9EFF, icon = 0xC4C4C4FF,
}
local ROW, SEP_H = 24, 9

local function imgui_ok()
  if not r.ImGui_CreateContext or not r.ImGui_GetVersion then return false end
  local _, _, version = r.ImGui_GetVersion()
  local major, minor = tostring(version):match("^(%d+)%.(%d+)")
  return major and (tonumber(major) > 0 or tonumber(minor) >= 10)    -- PushFont with a size: 0.10+
end

function M.show(items)
  if not imgui_ok() then return system_menu(items) end
  if r.set_action_options then r.set_action_options(1) end   -- a click on the button again closes it

  local list = {}
  for _, it in ipairs(items) do
    local n = norm(it)
    if n then
      n.keys = shortcut(n.id)
      n.on = enabled(n.id)
    end
    list[#list + 1] = n or false
  end

  local ctx = r.ImGui_CreateContext("TK Theme Bit menu")
  local font = r.ImGui_CreateFont("Inter")
  r.ImGui_Attach(ctx, font)
  local mx, my = r.GetMousePosition()
  mx, my = r.ImGui_PointConvertNative(ctx, mx, my)
  local frame = 0

  local function loop()
    frame = frame + 1
    r.ImGui_PushFont(ctx, font, 13)
    -- width: the longest name and shortcut
    local lw, kw = 0, 0
    for _, n in ipairs(list) do
      if n then
        lw = math.max(lw, (r.ImGui_CalcTextSize(ctx, n.label)))
        kw = math.max(kw, (r.ImGui_CalcTextSize(ctx, n.keys)))
      end
    end
    local w = math.max(200, 34 + lw + 36 + kw + 14)
    local h = 8
    for _, n in ipairs(list) do h = h + (n and ROW or SEP_H) end

    r.ImGui_SetNextWindowPos(ctx, mx, my + 2, r.ImGui_Cond_Appearing())
    r.ImGui_SetNextWindowSize(ctx, w, h, r.ImGui_Cond_Always())
    if frame == 1 then r.ImGui_SetNextWindowFocus(ctx) end
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_WindowBg(), C.bg)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Border(), C.border)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), 0, 4)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowRounding(), 3)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowBorderSize(), 1)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing(), 0, 0)
    local flags = r.ImGui_WindowFlags_NoTitleBar() | r.ImGui_WindowFlags_NoResize() | r.ImGui_WindowFlags_NoMove()
      | r.ImGui_WindowFlags_NoScrollbar() | r.ImGui_WindowFlags_NoSavedSettings() | r.ImGui_WindowFlags_NoDocking()
      | r.ImGui_WindowFlags_TopMost()
    local visible, open = r.ImGui_Begin(ctx, "TK Theme Bit menu", true, flags)
    local run
    if visible then
      local dl = r.ImGui_GetWindowDrawList(ctx)
      for i, n in ipairs(list) do
        local x, y = r.ImGui_GetCursorScreenPos(ctx)
        if not n then
          r.ImGui_Dummy(ctx, w, SEP_H)
          r.ImGui_DrawList_AddLine(dl, x + 8, y + SEP_H / 2, x + w - 8, y + SEP_H / 2, C.sep, 1)
        else
          local hit = r.ImGui_InvisibleButton(ctx, "##m" .. i, w, ROW)
          local hov = r.ImGui_IsItemHovered(ctx) and n.on
          if hov then r.ImGui_DrawList_AddRectFilled(dl, x + 3, y + 1, x + w - 3, y + ROW - 1, C.hover, 2) end
          local tc = n.on and C.text or C.dim
          if n.icon and ICONS[n.icon] then ICONS[n.icon](dl, x + 10, y + 5, n.on and C.icon or C.dim) end
          local _, th = r.ImGui_CalcTextSize(ctx, n.label)
          r.ImGui_DrawList_AddText(dl, x + 34, y + (ROW - th) / 2, tc, n.label)
          if n.keys ~= "" then
            local kw2 = r.ImGui_CalcTextSize(ctx, n.keys)
            r.ImGui_DrawList_AddText(dl, x + w - 14 - kw2, y + (ROW - th) / 2, n.on and C.keys or C.dim, n.keys)
          end
          if hit and n.on then run = n.id end
        end
      end
      if r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_Escape()) then open = false end
      -- a click elsewhere (focus gone) closes it, as a menu
      if frame > 2 and not r.ImGui_IsWindowFocused(ctx, r.ImGui_FocusedFlags_RootAndChildWindows()) then open = false end
      r.ImGui_End(ctx)
    end
    r.ImGui_PopStyleVar(ctx, 4)
    r.ImGui_PopStyleColor(ctx, 2)
    r.ImGui_PopFont(ctx)
    if run then
      r.Main_OnCommand(run, 0)
      return
    end
    if open then r.defer(loop) end
  end
  r.defer(loop)
end

return M
