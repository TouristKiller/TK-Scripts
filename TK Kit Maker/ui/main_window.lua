local r = reaper
local Theme         = require("core.theme")
local Store         = require("core.browser_store")
local ExplosionView = require("ui.explosion_view")
local BuilderView   = require("ui.builder_view")
local BrowserView   = require("ui.browser_view")
local ExportDialog  = require("ui.export_dialog")
local RS5KManagerView = require("ui.rs5k_manager_view")
local SequencerView = require("ui.sequencer_view")

local M = {}

function M.init(app)
  local loaded = Store.load()
  app.view = loaded.view or "browser"
  ExplosionView.init(app)
  BuilderView.init(app)
  BrowserView.init(app)
  ExportDialog.init(app)
  RS5KManagerView.init(app)
  SequencerView.init(app)
end

local function save(app)
  if app.browser then
    app.browser.view = app.view
    Store.save(app.browser)
  end
end

local function set_view(app, view)
  if app.view == view then return end
  app.view = view
  save(app)
end

local function tab_button(ctx, label, tip, active, width)
  local c = Theme.colors
  if active then
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), c.accent_soft)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), c.accent_soft)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), c.accent_soft)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Border(), c.accent)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0xFFFFFFFF)
  else
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x00000000)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), c.frame_bg)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), c.frame_hover)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Border(), c.border)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), c.text_dim)
  end
  local clicked = r.ImGui_Button(ctx, label, width, 34)
  if tip and r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, tip) end
  r.ImGui_PopStyleColor(ctx, 5)
  return clicked
end

local function close_button(ctx, size)
  local dl = r.ImGui_GetWindowDrawList(ctx)
  local x, y = r.ImGui_GetCursorScreenPos(ctx)
  local clicked = r.ImGui_InvisibleButton(ctx, "##tk_close", size, size)
  local hovered = r.ImGui_IsItemHovered(ctx)
  local cx, cy = x + size * 0.5, y + size * 0.5
  local rad = size * 0.5
  local col = hovered and Theme.colors.danger or 0xC85A60FF
  r.ImGui_DrawList_AddCircleFilled(dl, cx, cy, rad, col)
  if hovered and r.ImGui_SetTooltip then r.ImGui_SetTooltip(ctx, "Close") end
  return clicked
end

local function draw_header(app)
  local ctx = app.ctx
  local pushed = Theme.push_h1(ctx)
  r.ImGui_TextColored(ctx, Theme.colors.accent, "Kit Maker")
  local title_x, _ = r.ImGui_GetItemRectMin(ctx)
  local _, title_bottom_y = r.ImGui_GetItemRectMax(ctx)
  Theme.pop_font(ctx, pushed)
  local dl = r.ImGui_GetWindowDrawList(ctx)
  local pushed_small = Theme.push_small(ctx)
  r.ImGui_DrawList_AddText(dl, title_x + 1, title_bottom_y - 2, Theme.colors.text_dim, "by TK & Flurmechanik")
  Theme.pop_font(ctx, pushed_small)

  local theme_w = 108
  local manager_w = 108
  local close_size = 16
  local gap = 10
  r.ImGui_SameLine(ctx)
  local avail = select(1, r.ImGui_GetContentRegionAvail(ctx))
  local cluster_w = theme_w + gap + manager_w + gap + close_size
  r.ImGui_SetCursorPosX(ctx, r.ImGui_GetCursorPosX(ctx) + math.max(0, avail - cluster_w))
  r.ImGui_AlignTextToFramePadding(ctx)
  Theme.theme_combo(ctx, theme_w)

  r.ImGui_SameLine(ctx, 0, gap)
  if tab_button(ctx, "Kit Manager", "Open the kit manager window", app.browser and app.browser.manager_visible == true, manager_w) then
    app.browser.manager_visible = app.browser.manager_visible ~= true
    save(app)
  end

  r.ImGui_SameLine(ctx, 0, gap)
  local fh = r.ImGui_GetFrameHeight(ctx)
  r.ImGui_SetCursorPosY(ctx, r.ImGui_GetCursorPosY(ctx) + (fh - close_size) * 0.5 - 4)
  if close_button(ctx, close_size) then
    app.request_close = true
  end

  r.ImGui_Spacing(ctx)

  local avail_w = select(1, r.ImGui_GetContentRegionAvail(ctx))
  local spacing = 8
  local fifth = (avail_w - spacing * 4) / 5
  if tab_button(ctx, "Browser", "Manage folders and send them to Explosion/Builder", app.view == "browser", fifth) then
    set_view(app, "browser")
  end
  r.ImGui_SameLine(ctx, 0, spacing)
  if tab_button(ctx, "Explosion", "Surprise me with a folder", app.view == "explosion", fifth) then
    set_view(app, "explosion")
  end
  r.ImGui_SameLine(ctx, 0, spacing)
  if tab_button(ctx, "Builder", "I define the structure, surprise me with the contents", app.view == "builder", fifth) then
    set_view(app, "builder")
  end
  r.ImGui_SameLine(ctx, 0, spacing)
  if tab_button(ctx, "Step", "Step sequencer linked to kit slots 1-16", app.view == "step", fifth) then
    set_view(app, "step")
  end
  r.ImGui_SameLine(ctx, 0, spacing)
  if tab_button(ctx, "Euclid", "Euclidean sequencer linked to kit slots 1-16", app.view == "euclid", fifth) then
    set_view(app, "euclid")
  end

  -- r.ImGui_Dummy(ctx, 0, 2)
  r.ImGui_Separator(ctx)
  -- r.ImGui_Dummy(ctx, 0, 4)
end

function M.frame(app)
  local ctx = app.ctx
  Theme.init(ctx)

  r.ImGui_SetNextWindowSize(ctx, 900, 780, r.ImGui_Cond_FirstUseEver())
  if r.ImGui_SetNextWindowSizeConstraints then
    r.ImGui_SetNextWindowSizeConstraints(ctx, 410, 480, 100000, 100000)
  end

  local theme_stack = Theme.push(ctx)
  local window_flags = r.ImGui_WindowFlags_NoTitleBar() | r.ImGui_WindowFlags_NoScrollbar() | r.ImGui_WindowFlags_NoScrollWithMouse()
  local visible, open = r.ImGui_Begin(ctx, app.script_name, true, window_flags)

  if visible then
    local body_pushed = Theme.push_body(ctx)
    draw_header(app)

    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ChildBg(), 0x00000000)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), 0, 0)
    local body_flags = 0
    if app.view == "browser" or app.view == "step" or app.view == "euclid" then
      if r.ImGui_WindowFlags_NoScrollbar then
        body_flags = body_flags | r.ImGui_WindowFlags_NoScrollbar()
      end
      if r.ImGui_WindowFlags_NoScrollWithMouse then
        body_flags = body_flags | r.ImGui_WindowFlags_NoScrollWithMouse()
      end
    end
    local body_visible = r.ImGui_BeginChild(ctx, "##tk_body", 0, 0, 0, body_flags)
    r.ImGui_PopStyleVar(ctx)
    if body_visible then
      if app.view ~= "browser" then
        BrowserView.ensure_stopped(app)
      end
      if app.view ~= "step" and app.view ~= "euclid" then
        SequencerView.ensure_stopped(app)
      end
      if app.view == "explosion" then
        ExplosionView.draw(app)
      elseif app.view == "builder" then
        BuilderView.draw(app)
        if app.kitdef then
          ExportDialog.draw(app)
        end
      elseif app.view == "step" or app.view == "euclid" then
        SequencerView.draw(app)
      else
        BrowserView.draw(app)
      end
      BrowserView.update_drag_drop(app)
      r.ImGui_EndChild(ctx)
    end
    r.ImGui_PopStyleColor(ctx)

    if r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_Escape()) then
      app.request_close = true
    end

    Theme.pop_font(ctx, body_pushed)
    r.ImGui_End(ctx)
  end

  RS5KManagerView.draw(app)
  BrowserView.commit_track_drop(app)

  Theme.pop(ctx, theme_stack)

  if app.request_close then
    BrowserView.ensure_stopped(app)
    SequencerView.ensure_stopped(app)
    open = false
  end
  return open
end

return M
