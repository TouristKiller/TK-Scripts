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

-- Read off the script's own @version header rather than kept as a constant
-- here: that header is what ReaPack installs and upgrades against, so this is
-- the one number that cannot drift out of step with what the user actually has.
local function read_version(script_path)
  local f = io.open((script_path or "") .. "TK_Kit_Maker.lua", "r")
  if not f then return nil end
  local head = f:read(2048) or ""
  f:close()
  return head:match("@version%s+([%w%.%-]+)")
end

function M.init(app)
  app.version = read_version(app.script_path)
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

local function file_exists(path)
  local f = io.open(path, "r")
  if not f then return false end
  f:close()
  return true
end

-- Right-click menu on the title. It lives here rather than as a button because
-- the header row is the one place in the program that runs out of width first,
-- and these are read-once things: where the manual is, where the presets and
-- the tag cache are kept.
local function draw_header_menu(app)
  local ctx = app.ctx
  if not r.ImGui_BeginPopup(ctx, "##header_menu") then return end

  local shell = r.CF_ShellExecute
  local manual = (app.script_path or "") .. "USER_GUIDE.pdf"
  if not file_exists(manual) then manual = (app.script_path or "") .. "USER_GUIDE.md" end

  r.ImGui_BeginDisabled(ctx, not shell or not file_exists(manual))
  if r.ImGui_MenuItem(ctx, "Open manual") then shell(manual) end
  r.ImGui_EndDisabled(ctx)

  r.ImGui_Separator(ctx)

  r.ImGui_BeginDisabled(ctx, not shell)
  if r.ImGui_MenuItem(ctx, "Show script folder") then shell(app.script_path) end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, app.script_path or "") end

  -- Not the same folder: the script is installed under Scripts, while anything
  -- Kit Maker writes lives beside REAPER's own data.
  local data_dir = r.GetResourcePath() .. "/TK_Kit_Maker"
  if r.ImGui_MenuItem(ctx, "Show presets and cache folder") then
    r.RecursiveCreateDirectory(data_dir, 0)
    shell(data_dir)
  end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, data_dir) end
  r.ImGui_EndDisabled(ctx)

  r.ImGui_EndPopup(ctx)
end

-- The wordmark, decoded once and then a texture: drawing it costs less per
-- frame than laying out the text it replaces. ReaImGui collects images that are
-- not attached, so the pointer is revalidated the same way the Browser does it
-- for cover art, and a file that cannot be read is remembered as `false` rather
-- than retried sixty times a second.
--
-- Everything here falls back to the words "Kit Maker" if the image is missing,
-- which is what a user gets if the PNG was not installed alongside the script.
local LOGO_FILE = "ui/Kitmaker_logo.png"

-- The dials for the header. Nothing else needs touching to resize it: the
-- byline, the version number and the row of buttons beside the logo all measure
-- themselves against whatever the logo turns out to be.
--
--   SCALE   how much taller than the heading it replaces
--   LIFT    pixels to raise it, to take up the slack above a wide, short mark
--   GAP     pixels between the logo's bottom edge and the byline
--   INDENT  byline indent, as a fraction of the logo's width
--
-- GAP is negative on purpose, and the reason is worth knowing before anyone
-- "corrects" it. Text is drawn from the top of its line box, and a line box
-- carries about four pixels of empty space above the letters. At GAP 0 the
-- letters therefore sit four pixels lower than they look like they should. The
-- logo has no transparent margin of its own -- its ink runs to all four edges
-- -- so the negative value is buying back the font's padding, not overlapping
-- the picture. Around -3 the two just clear each other.
local LOGO_SCALE = 1.4
local LOGO_LIFT = 8
local BYLINE_GAP = -3
local BYLINE_INDENT = 0.04

local function header_logo(app)
  local cached = app.logo
  if cached and r.ImGui_ValidatePtr then
    local ok, valid = pcall(r.ImGui_ValidatePtr, cached.tex, "ImGui_Image*")
    if not ok or not valid then cached = nil end
  end
  if cached ~= nil then return cached or nil end
  if not r.ImGui_CreateImage or not r.ImGui_Image then
    app.logo = false
    return nil
  end

  local ok, tex = pcall(r.ImGui_CreateImage, (app.script_path or "") .. LOGO_FILE)
  if not ok or not tex then
    app.logo = false
    return nil
  end

  local w, h = 250, 86
  if r.ImGui_Image_GetSize then
    local ok_size, iw, ih = pcall(r.ImGui_Image_GetSize, tex)
    if ok_size and tonumber(iw) and tonumber(ih) and tonumber(ih) > 0 then
      w, h = tonumber(iw), tonumber(ih)
    end
  end
  app.logo = { tex = tex, w = w, h = h }
  return app.logo
end

local function draw_header(app)
  local ctx = app.ctx

  -- Measured against the heading it replaces, then scaled. The two numbers to
  -- turn are the four at the top of this file.
  local pushed = Theme.push_h1(ctx)
  local line_h = select(2, r.ImGui_CalcTextSize(ctx, "Kit Maker"))
  Theme.pop_font(ctx, pushed)
  line_h = tonumber(line_h) or 24

  local logo = header_logo(app)
  local logo_h = logo and math.floor(line_h * LOGO_SCALE + 0.5) or line_h
  local logo_w = logo and (logo_h * (logo.w / logo.h)) or 0
  if logo then
    -- A wide, short mark leaves slack above it that a line of text would have
    -- filled. Raising the item rather than the picture keeps everything that
    -- measures itself against the logo -- byline, version, buttons -- in step.
    if LOGO_LIFT ~= 0 then
      r.ImGui_SetCursorPosY(ctx, r.ImGui_GetCursorPosY(ctx) - LOGO_LIFT)
    end
    r.ImGui_Image(ctx, logo.tex, logo_w, logo_h)
  else
    local p = Theme.push_h1(ctx)
    r.ImGui_TextColored(ctx, Theme.colors.accent, "Kit Maker")
    Theme.pop_font(ctx, p)
  end

  local title_x, title_top_y = r.ImGui_GetItemRectMin(ctx)
  local title_x2, title_bottom_y = r.ImGui_GetItemRectMax(ctx)
  -- Opened here, drawn further down: the popup has to be built once the title's
  -- font is off the stack, or the menu renders in the heading face.
  if r.ImGui_IsItemClicked(ctx, 1) then r.ImGui_OpenPopup(ctx, "##header_menu") end
  local title_hovered = r.ImGui_IsItemHovered(ctx)
  local dl = r.ImGui_GetWindowDrawList(ctx)
  local pushed_small = Theme.push_small(ctx)

  -- Under the mark, clear of it. Overlapping was tried and does not work with
  -- this wordmark: its swash runs the full width along the bottom, so any
  -- overlap draws a line straight through the text.
  --
  -- Drawn rather than laid out, so it costs no vertical space of its own -- it
  -- hangs in the gap the header already has.
  local sub_y = title_bottom_y + (logo and BYLINE_GAP or -2)
  r.ImGui_DrawList_AddText(dl, title_x + (logo and logo_w * BYLINE_INDENT or 1),
    sub_y, Theme.colors.text_dim, "by TK & Flurmechanik")

  Theme.pop_font(ctx, pushed_small)

  -- Off the mark's top-right shoulder, a size down from the byline: it labels
  -- the logo rather than saying anything, so it should not compete with it.
  --
  -- Drawn rather than laid out, because an ordinary item would sit at the top
  -- of the line -- but its width is reserved immediately after, so the buttons
  -- on the right cannot run into it however narrow the window gets. They are
  -- right-aligned within whatever is left.
  local version_w = 0
  if app.version then
    local pushed_tiny = Theme.push_tiny(ctx)
    local label = app.version
    local w, h = r.ImGui_CalcTextSize(ctx, label)
    h = tonumber(h) or 10
    version_w = (tonumber(w) or 0) + 8
    local y = logo and (title_top_y + 1) or (title_bottom_y - h - 4)
    r.ImGui_DrawList_AddText(dl, title_x2 + 6, y, Theme.colors.text_faint, label)
    Theme.pop_font(ctx, pushed_tiny)
  end

  if title_hovered then
    r.ImGui_SetTooltip(ctx, "Right-click for the manual and Kit Maker's folders")
  end
  draw_header_menu(app)

  if version_w > 0 then
    r.ImGui_SameLine(ctx, 0, 0)
    r.ImGui_Dummy(ctx, version_w, 0)
  end

  local theme_w = 108
  local manager_w = 108
  local close_size = 16
  local gap = 10
  local fh = r.ImGui_GetFrameHeight(ctx)

  -- The logo is taller than a button, so the row beside it has to be centred
  -- against the logo rather than left at the top of the line. SameLine resets
  -- the Y each time, which is why this is applied per widget instead of once.
  local row_lift = math.max(0, ((logo and logo_h or line_h) - fh) * 0.5)
  local function centre_on_logo()
    if row_lift > 0 then
      r.ImGui_SetCursorPosY(ctx, r.ImGui_GetCursorPosY(ctx) + row_lift)
    end
  end

  r.ImGui_SameLine(ctx)
  local avail = select(1, r.ImGui_GetContentRegionAvail(ctx))
  local cluster_w = theme_w + gap + manager_w + gap + close_size
  r.ImGui_SetCursorPosX(ctx, r.ImGui_GetCursorPosX(ctx) + math.max(0, avail - cluster_w))
  centre_on_logo()
  r.ImGui_AlignTextToFramePadding(ctx)
  Theme.theme_combo(ctx, theme_w)

  r.ImGui_SameLine(ctx, 0, gap)
  centre_on_logo()
  if tab_button(ctx, "Kit Manager", "Open the kit manager window", app.browser and app.browser.manager_visible == true, manager_w) then
    app.browser.manager_visible = app.browser.manager_visible ~= true
    save(app)
  end

  r.ImGui_SameLine(ctx, 0, gap)
  centre_on_logo()
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
