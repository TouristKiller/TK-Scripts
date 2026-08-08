-- Shared Navigator: the bird's-eye map of the arrange, drawn either as a card
-- inside Transport or as a module of its own. It lives here rather than in
-- either of them so the two cannot drift apart - one of them getting a fix the
-- other does not is exactly the kind of thing nobody notices for months.
--
-- The only difference between the two is height: the card asks for a fixed
-- strip, the module fills whatever pane it is given.

local r = reaper
local Theme = require("core.theme")
local UIScale = require("core.ui_scale")

local M = {}

-- Map cache and drag state. One project, one arrange, so a single table serves
-- both callers - and two of them on screen at once stay in step for free.
local state = { map = nil, map_change = -1, map_track_count = -1, last_build = nil, drag = nil }

local function text_chip(ctx, id, label, active, w, h)
  local dl = r.ImGui_GetWindowDrawList(ctx)
  r.ImGui_PushID(ctx, id)
  local clicked = r.ImGui_InvisibleButton(ctx, "##chip", w, h)
  local hovered = r.ImGui_IsItemHovered(ctx)
  local x1, y1 = r.ImGui_GetItemRectMin(ctx)
  local x2, y2 = r.ImGui_GetItemRectMax(ctx)
  local bg = active and Theme.colors.accent_soft or (hovered and Theme.colors.frame_hover or Theme.colors.frame_bg)
  local border = (active or hovered) and Theme.colors.accent or Theme.colors.border
  local fg = active and Theme.colors.accent or Theme.text_for_background(bg, Theme.colors.text, nil, 3)
  r.ImGui_DrawList_AddRectFilled(dl, x1, y1, x2, y2, bg, UIScale.px(4))
  r.ImGui_DrawList_AddRect(dl, x1, y1, x2, y2, border, UIScale.px(4), 0, UIScale.px(1))
  local tw, th = r.ImGui_CalcTextSize(ctx, label)
  r.ImGui_DrawList_AddText(dl, (x1 + x2 - tw) * 0.5, (y1 + y2 - th) * 0.5, fg, label)
  r.ImGui_PopID(ctx)
  return clicked, hovered
end
-- Navigator helpers: a cached bird's-eye map of the arrange (tracks x time).
-- ---------------------------------------------------------------------------
local function nav_clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

local function nav_color(native, fallback)
  if not native or native == 0 or not r.ColorFromNative then return fallback end
  local rr, gg, bb = r.ColorFromNative(native)
  return (rr << 24) | (gg << 16) | (bb << 8) | 0xFF
end

local function nav_build_map()
  local map = { tracks = {}, len = 0 }
  local maxend = 0
  local ntr = r.CountTracks(0)
  local default_item = Theme.colors.accent_soft or 0x2B4B78FF
  for i = 0, ntr - 1 do
    local tr = r.GetTrack(0, i)
    local tcol = r.GetTrackColor and r.GetTrackColor(tr) or 0
    local row = {
      color = nav_color(tcol, Theme.colors.frame_hover),
      tcpy = r.GetMediaTrackInfo_Value(tr, "I_TCPY") or 0,
      tcph = r.GetMediaTrackInfo_Value(tr, "I_TCPH") or 0,
      items = {},
    }
    local nit = r.CountTrackMediaItems(tr)
    for j = 0, nit - 1 do
      local it = r.GetTrackMediaItem(tr, j)
      local pos = r.GetMediaItemInfo_Value(it, "D_POSITION")
      local ilen = r.GetMediaItemInfo_Value(it, "D_LENGTH")
      local icol = r.GetDisplayedMediaItemColor and r.GetDisplayedMediaItemColor(it) or 0
      row.items[#row.items + 1] = { pos = pos, len = ilen, color = nav_color(icol, default_item) }
      if pos + ilen > maxend then maxend = pos + ilen end
    end
    map.tracks[#map.tracks + 1] = row
  end
  local plen = r.GetProjectLength and r.GetProjectLength(0) or 0
  map.len = math.max(1.0, plen, maxend)
  return map
end

local function nav_get_map()
  local nav = state
  local change = r.GetProjectStateChangeCount and r.GetProjectStateChangeCount(0) or 0
  local ntr = r.CountTracks(0)
  if nav.map and change == nav.map_change and ntr == nav.map_track_count then return nav.map end
  local now = os.clock()
  if nav.map and nav.last_build and (now - nav.last_build) < 0.2 then return nav.map end
  nav.map = nav_build_map()
  nav.map_change = change
  nav.map_track_count = ntr
  nav.last_build = now
  return nav.map
end

local function nav_refresh_positions(map)
  for i, row in ipairs(map.tracks) do
    local tr = r.GetTrack(0, i - 1)
    if tr then
      row.tcpy = r.GetMediaTrackInfo_Value(tr, "I_TCPY") or 0
      row.tcph = r.GetMediaTrackInfo_Value(tr, "I_TCPH") or 0
    end
  end
end

local function nav_arrange_height()
  if r.JS_Window_FindChildByID and r.JS_Window_GetClientSize and r.GetMainHwnd then
    local a = r.JS_Window_FindChildByID(r.GetMainHwnd(), 0x3E8)
    if a then
      local ok, _, hgt = r.JS_Window_GetClientSize(a)
      if ok and hgt and hgt > 0 then return hgt end
    end
  end
  return nil
end

-- Horizontal arrange view via the core GetSet_ArrangeView2 (BR_* as fallback).
local function nav_get_view()
  if r.GetSet_ArrangeView2 then
    local s, e = r.GetSet_ArrangeView2(0, false, 0, 0, 0, 0)
    if s and e and e > s then return s, e end
  end
  if r.BR_GetArrangeView then return r.BR_GetArrangeView(0) end
  return nil, nil
end

local function nav_set_view(s, e)
  if r.GetSet_ArrangeView2 then
    r.GetSet_ArrangeView2(0, true, 0, 0, s, e)
  elseif r.BR_SetArrangeView then
    r.BR_SetArrangeView(0, s, e)
  end
end

local function nav_available()
  return (r.GetSet_ArrangeView2 ~= nil) or (r.BR_GetArrangeView ~= nil and r.BR_SetArrangeView ~= nil)
end

-- ---------------------------------------------------------------------------
-- Navigator zoom presets: a fit-project button plus three save/recall slots.
-- Slots live in project ext-state (zoom positions only make sense within the
-- project they were saved in) and keep the arrange time range, per-track
-- heights (keyed by GUID, so track reordering doesn't break them) and the
-- vertical scroll offset.
-- ---------------------------------------------------------------------------
local ZOOM_EXT_SECTION = "TK_WORKBENCH_TRANSPORT"

local function zoom_slot_key(i) return "zoom_slot_" .. i end

local function zoom_slot_exists(i)
  if not r.GetProjExtState then return false end
  local _, blob = r.GetProjExtState(0, ZOOM_EXT_SECTION, zoom_slot_key(i))
  return blob ~= nil and blob ~= ""
end

-- Vertical scroll offset in pixels (how far the top of track 1 sits above the
-- arrange top). CSurf_OnScroll moves in 8px steps, hence the /8 when applying.
local function zoom_vscroll()
  local tr = r.GetTrack(0, 0)
  if not tr then return 0 end
  return -(r.GetMediaTrackInfo_Value(tr, "I_TCPY") or 0)
end

local function zoom_scroll_to(target)
  if not r.CSurf_OnScroll then return end
  local amt = (target - zoom_vscroll()) / 8
  amt = amt >= 0 and math.floor(amt + 0.5) or math.ceil(amt - 0.5)
  if amt ~= 0 then r.CSurf_OnScroll(0, amt) end
end

local function zoom_slot_save(i)
  if not r.SetProjExtState then return false end
  local vs, ve = nav_get_view()
  if not vs then return false end
  local parts = {}
  for t = 0, r.CountTracks(0) - 1 do
    local tr = r.GetTrack(0, t)
    local guid = r.GetTrackGUID and r.GetTrackGUID(tr)
    if guid then
      parts[#parts + 1] = guid .. "=" .. math.floor(r.GetMediaTrackInfo_Value(tr, "I_TCPH") or 0)
    end
  end
  local blob = string.format("%.9f;%.9f;%d|%s", vs, ve, math.floor(zoom_vscroll()), table.concat(parts, ","))
  r.SetProjExtState(0, ZOOM_EXT_SECTION, zoom_slot_key(i), blob)
  return true
end

local function zoom_slot_recall(i)
  if not r.GetProjExtState then return false end
  local _, blob = r.GetProjExtState(0, ZOOM_EXT_SECTION, zoom_slot_key(i))
  if not blob or blob == "" then return false end
  local head, tracks_str = blob:match("^([^|]*)|(.*)$")
  if not head then head, tracks_str = blob, "" end
  local vs, ve, scroll = head:match("^([-%.%d]+);([-%.%d]+);([-%d]+)$")
  vs, ve, scroll = tonumber(vs), tonumber(ve), tonumber(scroll) or 0
  local heights = {}
  for guid, hgt in tracks_str:gmatch("([^=,]+)=([-%d]+)") do heights[guid] = tonumber(hgt) end
  if r.Undo_BeginBlock then r.Undo_BeginBlock() end
  for t = 0, r.CountTracks(0) - 1 do
    local tr = r.GetTrack(0, t)
    local guid = r.GetTrackGUID and r.GetTrackGUID(tr)
    local hgt = guid and heights[guid]
    if hgt and hgt > 0 then r.SetMediaTrackInfo_Value(tr, "I_HEIGHTOVERRIDE", hgt) end
  end
  if r.TrackList_AdjustWindows then r.TrackList_AdjustWindows(false) end
  if vs and ve and ve > vs then nav_set_view(vs, ve) end
  zoom_scroll_to(scroll)
  if r.UpdateArrange then r.UpdateArrange() end
  if r.Undo_EndBlock then r.Undo_EndBlock("Transport: recall zoom slot " .. i, -1) end
  return true
end

-- Fit the whole project: full time range horizontally, and all TCP-visible
-- tracks squeezed into the arrange height vertically (REAPER clamps each track
-- at its theme minimum, so with many tracks this gets as close as it can).
-- The vertical part needs js_ReaScriptAPI for the arrange height; without it
-- only the horizontal fit happens.
local function zoom_fit_project()
  local plen = r.GetProjectLength and r.GetProjectLength(0) or 0
  if r.Undo_BeginBlock then r.Undo_BeginBlock() end
  nav_set_view(0, math.max(1.0, plen) * 1.03)
  local ah = nav_arrange_height()
  local vis = {}
  for t = 0, r.CountTracks(0) - 1 do
    local tr = r.GetTrack(0, t)
    local shown = true
    if r.IsTrackVisible then shown = r.IsTrackVisible(tr, false) end
    if shown then vis[#vis + 1] = tr end
  end
  if ah and ah > 0 and #vis > 0 then
    local hgt = math.max(1, math.floor(ah / #vis))
    for _, tr in ipairs(vis) do r.SetMediaTrackInfo_Value(tr, "I_HEIGHTOVERRIDE", hgt) end
    if r.TrackList_AdjustWindows then r.TrackList_AdjustWindows(false) end
  end
  zoom_scroll_to(0)
  if r.UpdateArrange then r.UpdateArrange() end
  if r.Undo_EndBlock then r.Undo_EndBlock("Transport: zoom to whole project", -1) end
end

function M.draw(ctx, app, width, height, label)
  local dl = r.ImGui_GetWindowDrawList(ctx)
  local prefix = label or "Navigator"
  if not nav_available() then
    r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Navigator needs GetSet_ArrangeView2 (REAPER) or SWS.")
    return
  end
  local ox, oy = r.ImGui_GetCursorScreenPos(ctx)
  ox, oy = math.floor(ox), math.floor(oy)
  local zgap = UIScale.gap(4)
  local zbtn_w = UIScale.round(20)
  local w = math.max(UIScale.round(60), width - zbtn_w - zgap)
  local h = math.max(UIScale.round(60), math.floor(tonumber(height) or UIScale.round(120)))

  local map = nav_get_map()
  nav_refresh_positions(map)
  local content_len = map.len
  local vs, ve = nav_get_view()
  vs, ve = vs or 0, ve or content_len
  -- Display range: project content (or current view, whichever is larger) plus
  -- headroom, so you can zoom/scroll past the project end into empty timeline
  -- like REAPER's own navigator.
  local len = math.max(content_len, ve) * 1.25
  local ruler_h = UIScale.round(11)
  local tracks_top = oy + ruler_h
  local tracks_h = h - ruler_h
  local function t2x(t) return ox + nav_clamp(t / len, 0, 1) * w end
  local function x2t(x) return nav_clamp((x - ox) / w, 0, 1) * len end

  r.ImGui_DrawList_AddRectFilled(dl, ox, oy, ox + w, oy + h, Theme.colors.window_bg, UIScale.px(4))

  -- Tracks (flattened rows) + items.
  local ntr = #map.tracks
  local row_h = ntr > 0 and (tracks_h / ntr) or tracks_h
  for i, row in ipairs(map.tracks) do
    local ry = tracks_top + (i - 1) * row_h
    if i % 2 == 0 then r.ImGui_DrawList_AddRectFilled(dl, ox, ry, ox + w, ry + row_h, Theme.colors.child_bg) end
    local iy1 = ry + math.max(0, row_h * 0.12)
    local iy2 = ry + row_h - math.max(0, row_h * 0.12)
    for _, it in ipairs(row.items) do
      local ix1 = t2x(it.pos)
      local ix2 = math.max(ix1 + 1, t2x(it.pos + it.len))
      r.ImGui_DrawList_AddRectFilled(dl, ix1, iy1, ix2, iy2, it.color)
    end
  end

  -- Markers / regions.
  if r.CountProjectMarkers then
    local total = select(1, r.CountProjectMarkers(0)) or 0
    for idx = 0, total - 1 do
      local okm, isrgn, pos, rgnend, _, _, mcol = r.EnumProjectMarkers3(0, idx)
      if okm then
        local c = nav_color(mcol, isrgn and Theme.colors.accent_soft or Theme.colors.accent)
        if isrgn then
          r.ImGui_DrawList_AddRectFilled(dl, t2x(pos), oy, t2x(rgnend), oy + ruler_h, (c & 0xFFFFFF00) | 0x66)
        else
          local mkx = t2x(pos)
          r.ImGui_DrawList_AddLine(dl, mkx, oy, mkx, oy + ruler_h, c, UIScale.px(1))
          r.ImGui_DrawList_AddTriangleFilled(dl, mkx - UIScale.round(3), oy, mkx + UIScale.round(3), oy, mkx, oy + UIScale.round(4), c)
        end
      end
    end
    r.ImGui_DrawList_AddLine(dl, ox, tracks_top, ox + w, tracks_top, Theme.colors.border, UIScale.px(1))
  end

  -- Edit cursor + play position.
  local edit_x = t2x(r.GetCursorPosition and r.GetCursorPosition() or 0)
  r.ImGui_DrawList_AddLine(dl, edit_x, oy, edit_x, oy + h, Theme.colors.text, UIScale.px(1))
  local ps = r.GetPlayState and r.GetPlayState() or 0
  if (ps & 1) == 1 or (ps & 2) == 2 then
    local play_x = t2x(r.GetPlayPosition and r.GetPlayPosition() or 0)
    r.ImGui_DrawList_AddLine(dl, play_x, oy, play_x, oy + h, 0x39D98AFF, UIScale.px(1))
  end

  -- Viewport rectangle.
  local vx1, vx2 = t2x(vs), t2x(ve)
  local total_px, scroll_px = 0, 0
  for _, row in ipairs(map.tracks) do total_px = total_px + (row.tcph or 0) end
  if ntr > 0 then scroll_px = math.max(0, -(map.tracks[1].tcpy or 0)) end
  local ah = nav_arrange_height()
  local vy1, vy2 = tracks_top, tracks_top + tracks_h
  if ah and total_px > ah + 1 then
    vy1 = tracks_top + nav_clamp(scroll_px / total_px, 0, 1) * tracks_h
    vy2 = tracks_top + nav_clamp((scroll_px + ah) / total_px, 0, 1) * tracks_h
  end
  r.ImGui_DrawList_AddRectFilled(dl, vx1, vy1, vx2, vy2, (Theme.colors.accent & 0xFFFFFF00) | 0x22)
  r.ImGui_DrawList_AddRect(dl, vx1, vy1, vx2, vy2, Theme.colors.accent, UIScale.px(2), 0, UIScale.px(1.4))
  r.ImGui_DrawList_AddRect(dl, ox, oy, ox + w, oy + h, Theme.colors.border, UIScale.px(4), 0, UIScale.px(1))

  -- Interaction.
  r.ImGui_SetCursorScreenPos(ctx, ox, oy)
  r.ImGui_InvisibleButton(ctx, "##nav_canvas", w, h)
  local hovered = r.ImGui_IsItemHovered(ctx)
  local mx = r.ImGui_GetMousePos(ctx)
  local edge = UIScale.round(4)
  local min_dur = math.max(0.05, len * 0.002)
  local dur = math.max(min_dur, ve - vs)
  local nav = state

  if r.ImGui_IsItemActivated(ctx) then
    if mx >= vx1 - edge and mx <= vx1 + edge then
      nav.drag = { mode = "l" }
    elseif mx >= vx2 - edge and mx <= vx2 + edge then
      nav.drag = { mode = "r" }
    elseif mx > vx1 and mx < vx2 then
      nav.drag = { mode = "pan", grab = x2t(mx) - vs }
    else
      local ns = nav_clamp(x2t(mx) - dur * 0.5, 0, math.max(0, len - dur))
      nav_set_view(ns, ns + dur)
      nav.drag = { mode = "pan", grab = x2t(mx) - ns }
    end
  end

  if r.ImGui_IsItemActive(ctx) and nav.drag then
    local m = nav.drag.mode
    if m == "pan" then
      local ns = nav_clamp(x2t(mx) - (nav.drag.grab or 0), 0, math.max(0, len - dur))
      nav_set_view(ns, ns + dur)
      -- Vertical pan (no js needed): scale the drag by the total/visible track
      -- height ratio and feed it to CSurf_OnScroll.
      if r.CSurf_OnScroll and r.ImGui_GetMouseDelta and total_px > 0 and tracks_h > 0 then
        local _, dy = r.ImGui_GetMouseDelta(ctx)
        if dy and dy ~= 0 then
          local amt = (dy * (total_px / tracks_h)) / 8
          amt = amt >= 0 and math.floor(amt + 0.5) or math.ceil(amt - 0.5)
          if amt ~= 0 then r.CSurf_OnScroll(0, amt) end
        end
      end
    elseif m == "l" then
      nav_set_view(nav_clamp(x2t(mx), 0, ve - min_dur), ve)
    elseif m == "r" then
      nav_set_view(vs, nav_clamp(x2t(mx), vs + min_dur, len))
    end
  end

  if r.ImGui_IsItemDeactivated(ctx) then nav.drag = nil end

  if hovered and r.ImGui_GetMouseWheel then
    local wheel = r.ImGui_GetMouseWheel(ctx)
    if wheel and wheel ~= 0 then
      local ctrl = false
      if r.ImGui_GetKeyMods and r.ImGui_Mod_Ctrl then
        local mods = r.ImGui_GetKeyMods(ctx)
        ctrl = type(mods) == "number" and (mods & r.ImGui_Mod_Ctrl()) ~= 0
      end
      if ctrl and r.CSurf_OnZoom then
        r.CSurf_OnZoom(0, wheel > 0 and 2 or -2) -- vertical zoom (track heights)
      else
        local center = x2t(mx)
        local factor = wheel > 0 and 0.82 or 1.22
        local ndur = nav_clamp(dur * factor, min_dur, len)
        local ns = nav_clamp(center - (center - vs) * (ndur / dur), 0, math.max(0, len - ndur))
        nav_set_view(ns, ns + ndur)
      end
    end
  end

  if hovered and not nav.drag then
    r.ImGui_SetTooltip(ctx, "Drag = pan (x/y), edges = zoom time, wheel = zoom time, Ctrl+wheel = zoom tracks")
  end

  -- Zoom preset column on the right: fit project + three save/recall slots.
  local bx = ox + w + zgap
  local bh = math.floor((h - 3 * zgap) / 4)
  r.ImGui_SetCursorScreenPos(ctx, bx, oy)
  local fit_clicked, fit_hovered = text_chip(ctx, "nav_zoom_fit", "P", false, zbtn_w, bh)
  if fit_clicked then
    zoom_fit_project()
    app.status = prefix .. ": zoomed to whole project"
  end
  if fit_hovered then r.ImGui_SetTooltip(ctx, "Zoom out to whole project (time + tracks)") end
  for slot = 1, 3 do
    r.ImGui_SetCursorScreenPos(ctx, bx, oy + slot * (bh + zgap))
    local filled = zoom_slot_exists(slot)
    local clicked, shov = text_chip(ctx, "nav_zoom_slot_" .. slot, tostring(slot), filled, zbtn_w, bh)
    local rclicked = r.ImGui_IsItemClicked and r.ImGui_IsItemClicked(ctx, 1)
    if rclicked then
      if zoom_slot_save(slot) then app.status = prefix .. ": zoom slot " .. slot .. " saved" end
    elseif clicked then
      if zoom_slot_recall(slot) then
        app.status = prefix .. ": zoom slot " .. slot .. " recalled"
      else
        app.status = prefix .. ": zoom slot " .. slot .. " is empty (right-click to save)"
      end
    end
    if shov then
      r.ImGui_SetTooltip(ctx, filled
        and ("Zoom slot " .. slot .. " — click: recall, right-click: overwrite with current zoom")
        or ("Zoom slot " .. slot .. " (empty) — right-click: save current zoom"))
    end
  end
end

function M.available()
  return nav_available()
end

return M
