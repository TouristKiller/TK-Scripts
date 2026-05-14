-- @description TK MCP Cables Overlay
-- @author TouristKiller
-- @version 1.1.8
-- @about Overlay script that draws send/receive cables over REAPER's native MCP
-- @changelog:
--   v1.1.8
--   + Fixed: TOPMOST handling no longer runs permanently every frame, preventing focus/menu/shortcut issues while still boosting the overlay after relevant mixer or selection changes
--   v1.1.7
--   + Fixed: added ReaImGui context validation and stricter Begin/End handling to prevent rare invalid context errors on some systems
--   v1.1.6
--   + Fixed: overlay still falling behind floating mixer on some systems after track selection - TOPMOST Z-order is now re-applied every frame (cheap no-op when already on top)
--   v1.1.5
--   + Fixed: "Hide cables behind master" clip rect was a few pixels off when the mixer was undocked (window border was included) - now uses the mixer client rect so the cut-off lands exactly on the master strip edge
--   v1.1.4
--   + Settings window no longer opens automatically on startup
--   + External toggle script support (TK_MCP_Cables_Overlay_Toggle_Settings.lua) with toolbar/menu toggle state
--   + Fixed: overlay disappearing behind floating (undocked) mixer after selecting another track - overlay is now forced to TOPMOST Z-order
--   + Fixed: ghost cables remaining visible after selection changes when "Selected tracks only" is on - overlay window is now hidden when there are no cables to draw
--   v1.1.3
--   + Fixed: cables disappearing after MCP changes (track delete, fader move, etc.) - overlay now refreshes on project state changes
--   v1.1.2
--   + Reliable F2 capture via JS_VKeys_Intercept (only while mouse is over the mixer, so REAPER's Rename Track still works elsewhere)
--   v1.1.1
--   + Settings hotkey F2 works globally, but only when mouse hovers over the mixer (no conflict with REAPER's Rename Track)
--   v1.1.0
--   + Master side detection (auto/left/right) with correct track offset when master is on the left
--   + Hide cables behind master option (clip rect split around master strip)
--   + Cables stay anchored to tracks while scrolling (horizontal + vertical)
--   + Cables remain visible when tracks scroll out of view (clipped to mixer)
--   + Horizontal offset slider; vertical offset now also applies to "center" anchor
--   + Bright yellow flow indicators (halo + dot + core) for better visibility
--   + Overlay is suppressed when another window covers the mixer
--   + Renamed bundled json helper to tk_mcp_cables_json.lua to avoid ReaPack conflicts
--   v1.0.0
--   + Initial release

local r = reaper

if not r.JS_Window_Find then
 r.MB("This script requires the js_ReaScriptAPI extension.", "TK MCP Cables Overlay", 0)
 return
end

local OS = r.GetOS()
local IS_WIN = OS:find("Win") ~= nil

local script_path = debug.getinfo(1, "S").source:match("@?(.*[/\\])")
local os_sep = package.config:sub(1, 1)
local settings_path = script_path .. "tk_mcp_overlay_settings" .. os_sep
r.RecursiveCreateDirectory(settings_path:sub(1, -2), 0)

package.path = script_path .. "?.lua;" .. package.path
local ok_json, json = pcall(require, "tk_mcp_cables_json")
if not ok_json then
 ok_json, json = pcall(require, "json")
end
if not ok_json then json = nil end

local ctx = r.ImGui_CreateContext('TK MCP Cables Overlay')
local settings_file = settings_path .. "settings.json"

local settings = {
 enabled = true,
 thickness = 2.5,
 alpha = 0.75,
 curve_amount = 0.55,
 glow = true,
 flow = false,
 selected_only = false,
 use_dest_color = false,
 anchor_position = "bottom",
 vertical_offset = 6,
 horizontal_offset = 0,
 hide_behind_master = true,
 master_side = "auto",
 debug_anchors = false,
}

local function LoadSettings()
 if not json then return end
 local f = io.open(settings_file, "r")
 if not f then return end
 local body = f:read("*a")
 f:close()
 local ok, data = pcall(json.decode, body)
 if ok and type(data) == "table" then
  for k, v in pairs(data) do settings[k] = v end
 end
end

local settings_dirty = false
local function SaveSettings()
 if not json then return end
 local f = io.open(settings_file, "w")
 if not f then return end
 f:write(json.encode(settings))
 f:close()
 settings_dirty = false
end
local function MarkDirty() settings_dirty = true end

LoadSettings()

local function GetMixerHWND()
 if r.BR_Win32_GetMixerHwnd then
  local hwnd = r.BR_Win32_GetMixerHwnd()
  if hwnd and r.JS_Window_IsWindow(hwnd) then return hwnd end
 end
 local hwnd = r.JS_Window_Find("Mixer", true)
 if hwnd then return hwnd end
 return r.JS_Window_Find("mixer", false)
end

local screen_scale = 1
local function UpdateScreenScale()
 if IS_WIN then
  local s = r.ImGui_GetWindowDpiScale(ctx)
  if s and s > 0 then screen_scale = s end
 else
  screen_scale = 1
 end
end

local overlay_flags = r.ImGui_WindowFlags_NoTitleBar()
 | r.ImGui_WindowFlags_NoResize()
 | r.ImGui_WindowFlags_NoNav()
 | r.ImGui_WindowFlags_NoScrollbar()
 | r.ImGui_WindowFlags_NoDecoration()
 | r.ImGui_WindowFlags_NoDocking()
 | r.ImGui_WindowFlags_NoBackground()
 | r.ImGui_WindowFlags_NoMove()
 | r.ImGui_WindowFlags_NoSavedSettings()
 | r.ImGui_WindowFlags_NoFocusOnAppearing()
 | r.ImGui_WindowFlags_NoInputs()
 | r.ImGui_WindowFlags_NoMouseInputs()
 | r.ImGui_WindowFlags_TopMost()

local settings_flags = r.ImGui_WindowFlags_NoCollapse() | r.ImGui_WindowFlags_AlwaysAutoResize()

local LAST_RECT_VAL = 0
local LEFT, TOP, RIGHT, BOT = 0, 0, 0, 0
local track_x_offset_native = 0
local mixer_hwnd = nil
local mixer_search_t = 0
local settings_visible = false
local save_timer = 0
local prev_f2_state = 0
local last_project_change = -1
local overlay_hwnd = nil
local overlay_topmost_set = false
local topmost_boost_frames = 0
local last_selection_key = ""

local function RequestOverlayTopmost(frames)
 frames = frames or 12
 if topmost_boost_frames < frames then topmost_boost_frames = frames end
end

local function EnsureImGuiContext()
 if r.ImGui_ValidatePtr and r.ImGui_ValidatePtr(ctx, "ImGui_Context*") then return true end
 if not r.ImGui_ValidatePtr then return true end
 ctx = r.ImGui_CreateContext('TK MCP Cables Overlay')
 overlay_hwnd = nil
 overlay_topmost_set = false
 RequestOverlayTopmost(12)
 return r.ImGui_ValidatePtr(ctx, "ImGui_Context*")
end

local function EnsureOverlayTopmost()
 if not r.JS_Window_SetZOrder or not r.JS_Window_Find then return end
 if not overlay_hwnd or not r.JS_Window_IsWindow(overlay_hwnd) then
  overlay_hwnd = r.JS_Window_Find("TK MCP Cables Overlay", true)
  overlay_topmost_set = false
  if overlay_hwnd then RequestOverlayTopmost(12) end
 end
 if not overlay_hwnd then return end
 if overlay_topmost_set and topmost_boost_frames <= 0 then return end
 if overlay_hwnd then
  r.JS_Window_SetZOrder(overlay_hwnd, "TOPMOST")
  overlay_topmost_set = true
  if topmost_boost_frames > 0 then topmost_boost_frames = topmost_boost_frames - 1 end
 end
end

local function HasCablesToDraw()
 if settings.selected_only then
  local sel = r.CountSelectedTracks(0)
  if sel == 0 then return false end
  for i = 0, sel - 1 do
   local t = r.GetSelectedTrack(0, i)
   if t and (r.GetTrackNumSends(t, 0) > 0 or r.GetTrackNumSends(t, -1) > 0) then
    return true
   end
  end
  return false
 end
 local num = r.CountTracks(0)
 for i = 0, num - 1 do
  local t = r.GetTrack(0, i)
  if r.GetTrackNumSends(t, 0) > 0 then return true end
 end
 return false
end

local function HideOverlayWindow()
 if not r.JS_Window_Show then return end
 if not overlay_hwnd or not r.JS_Window_IsWindow(overlay_hwnd) then
  if r.JS_Window_Find then overlay_hwnd = r.JS_Window_Find("TK MCP Cables Overlay", true) end
 end
 if overlay_hwnd and r.JS_Window_IsWindow(overlay_hwnd) then
  r.JS_Window_Show(overlay_hwnd, "HIDE")
  overlay_topmost_set = false
    topmost_boost_frames = 0
 end
end

local function UpdateMixerRect(force)
 if not mixer_hwnd or not r.JS_Window_IsWindow(mixer_hwnd) then
  mixer_hwnd = GetMixerHWND()
  if not mixer_hwnd then
   local now = r.time_precise()
   if now - mixer_search_t > 0.2 then mixer_search_t = now end
   return false
  end
  force = true
 end
 local ok, l, t, ri, b = r.JS_Window_GetRect(mixer_hwnd)
 if not ok then
  mixer_hwnd = nil
  return false
 end
 if r.JS_Window_GetClientRect then
  local cok, cl, ct, cr_, cb = r.JS_Window_GetClientRect(mixer_hwnd)
  if cok then l, t, ri, b = cl, ct, cr_, cb end
 end
 local val = l + t + ri + b
 if val ~= LAST_RECT_VAL or force then
  LAST_RECT_VAL = val
  LEFT, TOP = r.ImGui_PointConvertNative(ctx, l, t)
  RIGHT, BOT = r.ImGui_PointConvertNative(ctx, ri, b)
    RequestOverlayTopmost(12)
 end
 return true
end

local function color_u32(track, alpha)
 local c = r.GetTrackColor(track)
 local cr, cg, cb
 if c == 0 then
  cr, cg, cb = 0.5, 0.7, 1.0
 else
  local R, G, B = r.ColorFromNative(c)
  cr, cg, cb = R / 255, G / 255, B / 255
 end
 return r.ImGui_ColorConvertDouble4ToU32(cr, cg, cb, alpha)
end

local function ComputeAnchorXY(mcpx, mcpy, mcpw, mcph)
 if mcpw <= 0 or mcph <= 0 then return nil end
 local x_offset = settings.horizontal_offset or 0
 local x = LEFT + (mcpx + track_x_offset_native + mcpw * 0.5 + x_offset) / screen_scale
 local y_offset = settings.vertical_offset or 0
 local y
 if settings.anchor_position == "top" then
  y = TOP + (mcpy + y_offset) / screen_scale
 elseif settings.anchor_position == "center" then
  y = TOP + (mcpy + mcph * 0.5 + y_offset) / screen_scale
 else
  y = TOP + (mcpy + mcph - y_offset) / screen_scale
 end
 return x, y
end

local function DrawCables(draw_list)
 local num_tracks = r.CountTracks(0)
 local master = r.GetMasterTrack(0)

 local anchors = {}
 local master_screen_l, master_screen_r
 local master_mw_s, master_mh_s, master_my_s
 do
  local mx = r.GetMediaTrackInfo_Value(master, "I_MCPX")
  local my = r.GetMediaTrackInfo_Value(master, "I_MCPY")
  local mw = r.GetMediaTrackInfo_Value(master, "I_MCPW")
  local mh = r.GetMediaTrackInfo_Value(master, "I_MCPH")

  local side = settings.master_side
  if side == "auto" then
   if r.GetToggleCommandState(40389) == 1 then side = "right" else side = "left" end
  end

  if mw > 0 and mh > 0 then
   master_mw_s = mw / screen_scale
   master_mh_s = mh / screen_scale
   master_my_s = my / screen_scale
   if side == "right" then
    master_screen_r = RIGHT
    master_screen_l = RIGHT - master_mw_s
    track_x_offset_native = 0
   else
    master_screen_l = LEFT
    master_screen_r = LEFT + master_mw_s
    track_x_offset_native = mw
   end
   local cx = (master_screen_l + master_screen_r) * 0.5
   local y_offset = settings.vertical_offset or 0
   local cy
   if settings.anchor_position == "top" then
    cy = TOP + master_my_s + y_offset / screen_scale
   elseif settings.anchor_position == "center" then
    cy = TOP + master_my_s + master_mh_s * 0.5 + y_offset / screen_scale
   else
    cy = TOP + master_my_s + master_mh_s - y_offset / screen_scale
   end
   anchors[master] = { x = cx, y = cy }
  end
 end

 for i = 0, num_tracks - 1 do
  local tr = r.GetTrack(0, i)
  if tr and r.GetMediaTrackInfo_Value(tr, "B_SHOWINMIXER") == 1 then
   local mcpx = r.GetMediaTrackInfo_Value(tr, "I_MCPX")
   local mcpy = r.GetMediaTrackInfo_Value(tr, "I_MCPY")
   local mcpw = r.GetMediaTrackInfo_Value(tr, "I_MCPW")
   local mcph = r.GetMediaTrackInfo_Value(tr, "I_MCPH")
   local x, y = ComputeAnchorXY(mcpx, mcpy, mcpw, mcph)
   if x then
    anchors[tr] = { x = x, y = y }
   end
  end
 end

 local thickness = settings.thickness
 local alpha = settings.alpha
 if alpha < 0.05 then return end
 local curve_amount = settings.curve_amount
 local use_dest_color = settings.use_dest_color
 local glow = settings.glow
 local flow = settings.flow
 local selected_only = settings.selected_only

 r.ImGui_DrawList_PushClipRect(draw_list, LEFT, TOP, RIGHT, BOT, 0)

 local clip_segments = { { LEFT, RIGHT } }
 if settings.hide_behind_master and master_screen_l and master_screen_r
  and master_screen_r > LEFT and master_screen_l < RIGHT then
  local ml = math.max(LEFT, master_screen_l)
  local mr = math.min(RIGHT, master_screen_r)
  clip_segments = {}
  if ml > LEFT then clip_segments[#clip_segments + 1] = { LEFT, ml } end
  if mr < RIGHT then clip_segments[#clip_segments + 1] = { mr, RIGHT } end
 end

 local now = r.time_precise()

 local function DrawCablePass(seg_l, seg_r)
  r.ImGui_DrawList_PushClipRect(draw_list, seg_l, TOP, seg_r, BOT, 0)
  for src_track, src_anchor in pairs(anchors) do
   if src_track ~= master then
    local send_count = r.GetTrackNumSends(src_track, 0)
    for i = 0, send_count - 1 do
     local dst_track = r.GetTrackSendInfo_Value(src_track, 0, i, "P_DESTTRACK")
     if dst_track and dst_track ~= src_track then
      local dst_anchor = anchors[dst_track]
      if dst_anchor then
       local skip = false
       if selected_only then
        local src_sel = r.GetMediaTrackInfo_Value(src_track, "I_SELECTED") == 1
        local dst_sel = r.GetMediaTrackInfo_Value(dst_track, "I_SELECTED") == 1
        if not (src_sel or dst_sel) then skip = true end
       end
       if not skip then
        local muted = r.GetTrackSendInfo_Value(src_track, 0, i, "B_MUTE") == 1
        local color_track = use_dest_color and dst_track or src_track
        local cable_alpha = alpha * (muted and 0.35 or 1.0)
        if cable_alpha > 1 then cable_alpha = 1 end
        local color = color_u32(color_track, cable_alpha)

        local sx, sy = src_anchor.x, src_anchor.y
        local dx, dy = dst_anchor.x, dst_anchor.y
        local dist = math.abs(dx - sx)
        local dip = math.max(24, dist * curve_amount)
        if dip > 220 then dip = 220 end
        local c1x, c1y = sx, sy + dip
        local c2x, c2y = dx, dy + dip

        if glow then
         local glow_alpha = math.min(1, cable_alpha * 0.35)
         local glow_color = color_u32(color_track, glow_alpha)
         r.ImGui_DrawList_AddBezierCubic(draw_list, sx, sy, c1x, c1y, c2x, c2y, dx, dy, glow_color, thickness * 2.6, 32)
        end
        r.ImGui_DrawList_AddBezierCubic(draw_list, sx, sy, c1x, c1y, c2x, c2y, dx, dy, color, thickness, 32)

        local plug_alpha = math.min(1, cable_alpha + 0.15)
        local plug_color = color_u32(color_track, plug_alpha)
        local outline_color = r.ImGui_ColorConvertDouble4ToU32(0, 0, 0, math.min(1, cable_alpha + 0.2))

        local out_size = thickness * 1.8
        r.ImGui_DrawList_AddRectFilled(draw_list, sx - out_size, sy - out_size, sx + out_size, sy + out_size, plug_color, 1)
        r.ImGui_DrawList_AddRect(draw_list, sx - out_size, sy - out_size, sx + out_size, sy + out_size, outline_color, 1, 0, 1)

        local arrow_size = thickness * 2.4
        r.ImGui_DrawList_AddTriangleFilled(draw_list, dx - arrow_size, dy + arrow_size, dx + arrow_size, dy + arrow_size, dx, dy, plug_color)
        r.ImGui_DrawList_AddTriangle(draw_list, dx - arrow_size, dy + arrow_size, dx + arrow_size, dy + arrow_size, dx, dy, outline_color, 1)

        if flow and not muted then
         local cycle = 1.6
         local t = (now % cycle) / cycle
         local u = 1 - t
         local b0 = u * u * u
         local b1 = 3 * u * u * t
         local b2 = 3 * u * t * t
         local b3 = t * t * t
         local fx = b0 * sx + b1 * c1x + b2 * c2x + b3 * dx
         local fy = b0 * sy + b1 * c1y + b2 * c2y + b3 * dy
         local halo = r.ImGui_ColorConvertDouble4ToU32(1, 0.95, 0.2, math.min(1, cable_alpha * 0.45))
         local dot = r.ImGui_ColorConvertDouble4ToU32(1, 1, 0.3, 1)
         local core = r.ImGui_ColorConvertDouble4ToU32(1, 1, 0.9, 1)
         r.ImGui_DrawList_AddCircleFilled(draw_list, fx, fy, thickness * 2.6, halo, 16)
         r.ImGui_DrawList_AddCircleFilled(draw_list, fx, fy, thickness * 1.6, dot, 16)
         r.ImGui_DrawList_AddCircleFilled(draw_list, fx, fy, thickness * 0.7, core, 12)
        end
       end
      end
     end
    end
   end
  end
  r.ImGui_DrawList_PopClipRect(draw_list)
 end

 for _, seg in ipairs(clip_segments) do
  DrawCablePass(seg[1], seg[2])
 end

 r.ImGui_DrawList_PopClipRect(draw_list)
end

local function DrawDebugAnchors(draw_list)
 local master = r.GetMasterTrack(0)
 local function dot(tr, label)
  local mcpx = r.GetMediaTrackInfo_Value(tr, "I_MCPX")
  local mcpy = r.GetMediaTrackInfo_Value(tr, "I_MCPY")
  local mcpw = r.GetMediaTrackInfo_Value(tr, "I_MCPW")
  local mcph = r.GetMediaTrackInfo_Value(tr, "I_MCPH")
  local x, y = ComputeAnchorXY(mcpx, mcpy, mcpw, mcph)
  if not x then return end
  local col = 0xFF00FFFF
  r.ImGui_DrawList_AddCircleFilled(draw_list, x, y, 5, col, 16)
  local txt = string.format("%s mcpx=%d w=%d", label, mcpx, mcpw)
  r.ImGui_DrawList_AddText(draw_list, x + 6, y - 14, 0xFFFFFFFF, txt)
 end
 local mw = r.GetMediaTrackInfo_Value(master, "I_MCPW")
 local mh = r.GetMediaTrackInfo_Value(master, "I_MCPH")
 local my = r.GetMediaTrackInfo_Value(master, "I_MCPY")
 if mw > 0 and mh > 0 then
  local side = settings.master_side
  if side == "auto" then
   if r.GetToggleCommandState(40389) == 1 then side = "right" else side = "left" end
  end
  local mw_s = mw / screen_scale
  local mh_s = mh / screen_scale
  local my_s = my / screen_scale
  local l, ri
  if side == "right" then ri = RIGHT; l = RIGHT - mw_s else l = LEFT; ri = LEFT + mw_s end
  r.ImGui_DrawList_AddRect(draw_list, l, TOP + my_s, ri, TOP + my_s + mh_s, 0xFFFF00FF, 0, 0, 2)
  r.ImGui_DrawList_AddText(draw_list, l + 4, TOP + my_s + 2, 0xFFFF00FF, "MASTER (" .. side .. ")")
 end
 local num = r.CountTracks(0)
 for i = 0, num - 1 do
  local tr = r.GetTrack(0, i)
  if tr and r.GetMediaTrackInfo_Value(tr, "B_SHOWINMIXER") == 1 then
   dot(tr, tostring(i + 1))
  end
 end
end

local function DrawSettingsWindow()
 r.ImGui_SetNextWindowSize(ctx, 320, 0, r.ImGui_Cond_FirstUseEver())
 local visible, open = r.ImGui_Begin(ctx, "TK MCP Cables Overlay - Settings", true, settings_flags)
 if visible then
  local changed
  changed, settings.enabled = r.ImGui_Checkbox(ctx, "Enabled", settings.enabled)
  if changed then MarkDirty() end

  r.ImGui_Separator(ctx)

  r.ImGui_SetNextItemWidth(ctx, 180)
  changed, settings.thickness = r.ImGui_SliderDouble(ctx, "Thickness", settings.thickness, 0.5, 8.0, "%.2f")
  if changed then MarkDirty() end

  r.ImGui_SetNextItemWidth(ctx, 180)
  changed, settings.alpha = r.ImGui_SliderDouble(ctx, "Alpha", settings.alpha, 0.0, 1.0, "%.2f")
  if changed then MarkDirty() end

  r.ImGui_SetNextItemWidth(ctx, 180)
  changed, settings.curve_amount = r.ImGui_SliderDouble(ctx, "Curve", settings.curve_amount, 0.0, 1.5, "%.2f")
  if changed then MarkDirty() end

  r.ImGui_SetNextItemWidth(ctx, 180)
  changed, settings.vertical_offset = r.ImGui_SliderInt(ctx, "Vertical offset", settings.vertical_offset, 0, 80)
  if changed then MarkDirty() end

  r.ImGui_SetNextItemWidth(ctx, 180)
  changed, settings.horizontal_offset = r.ImGui_SliderInt(ctx, "Horizontal offset", settings.horizontal_offset, -80, 80)
  if changed then MarkDirty() end

  local pos_items = { "bottom", "center", "top" }
  r.ImGui_SetNextItemWidth(ctx, 180)
  if r.ImGui_BeginCombo(ctx, "Anchor", settings.anchor_position) then
   for _, v in ipairs(pos_items) do
    local sel = v == settings.anchor_position
    if r.ImGui_Selectable(ctx, v, sel) then
     settings.anchor_position = v
     MarkDirty()
    end
   end
   r.ImGui_EndCombo(ctx)
  end

  r.ImGui_Separator(ctx)

  changed, settings.glow = r.ImGui_Checkbox(ctx, "Glow", settings.glow)
  if changed then MarkDirty() end
  r.ImGui_SameLine(ctx)
  changed, settings.flow = r.ImGui_Checkbox(ctx, "Flow", settings.flow)
  if changed then MarkDirty() end

  changed, settings.selected_only = r.ImGui_Checkbox(ctx, "Selected tracks only", settings.selected_only)
  if changed then MarkDirty() end

  changed, settings.use_dest_color = r.ImGui_Checkbox(ctx, "Use destination color", settings.use_dest_color)
  if changed then MarkDirty() end

  changed, settings.hide_behind_master = r.ImGui_Checkbox(ctx, "Hide cables behind master", settings.hide_behind_master)
  if changed then MarkDirty() end

  local sides = { "auto", "left", "right" }
  r.ImGui_SetNextItemWidth(ctx, 180)
  if r.ImGui_BeginCombo(ctx, "Master side", settings.master_side) then
   for _, v in ipairs(sides) do
    if r.ImGui_Selectable(ctx, v, v == settings.master_side) then
     settings.master_side = v
     MarkDirty()
    end
   end
   r.ImGui_EndCombo(ctx)
  end

  changed, settings.debug_anchors = r.ImGui_Checkbox(ctx, "Debug: show anchors", settings.debug_anchors)
  if changed then MarkDirty() end

  r.ImGui_Separator(ctx)
  if r.ImGui_Button(ctx, "Close") then settings_visible = false end
  r.ImGui_End(ctx)
 end
 if not open then settings_visible = false end
end

local _, _, sectionID, cmdID = r.get_action_context()
if sectionID ~= -1 then
 r.SetToggleCommandState(sectionID, cmdID, 1)
 r.RefreshToolbar2(sectionID, cmdID)
end

local ext_toggle_sec, ext_toggle_cmd, ext_toggle_state = nil, nil, -1
local function UpdateExternalToggleState()
 local s = r.GetExtState("TK_MCP_Cables_Overlay", "toggle_cmd")
 if s == "" then
  ext_toggle_sec, ext_toggle_cmd = nil, nil
  return
 end
 local sec, cmd = s:match("^(-?%d+):(%d+)$")
 if not sec then return end
 sec, cmd = tonumber(sec), tonumber(cmd)
 if sec ~= ext_toggle_sec or cmd ~= ext_toggle_cmd then
  ext_toggle_sec, ext_toggle_cmd, ext_toggle_state = sec, cmd, -1
 end
 local desired = settings_visible and 1 or 0
 if desired ~= ext_toggle_state then
  r.SetToggleCommandState(sec, cmd, desired)
  r.RefreshToolbar2(sec, cmd)
  ext_toggle_state = desired
 end
end

r.atexit(function()
 if settings_dirty then SaveSettings() end
 if r.JS_VKeys_Intercept then r.JS_VKeys_Intercept(0x71, -1) end
 if sectionID ~= -1 then
  r.SetToggleCommandState(sectionID, cmdID, 0)
  r.RefreshToolbar2(sectionID, cmdID)
 end
 if ext_toggle_sec and ext_toggle_cmd then
  r.SetToggleCommandState(ext_toggle_sec, ext_toggle_cmd, 0)
  r.RefreshToolbar2(ext_toggle_sec, ext_toggle_cmd)
 end
end)

local function IsMouseOverMixer()
 if not mixer_hwnd or not r.JS_Window_FromPoint then return false end
 local mx, my = r.GetMousePosition()
 local hwnd = r.JS_Window_FromPoint(mx, my)
 local cur = hwnd
 while cur do
  if cur == mixer_hwnd then return true end
  cur = r.JS_Window_GetParent(cur)
 end
 return false
end

local f2_intercepted = false
local function UpdateF2Intercept(want)
 if not r.JS_VKeys_Intercept then return end
 if want and not f2_intercepted then
  r.JS_VKeys_Intercept(0x71, 1)
  f2_intercepted = true
 elseif not want and f2_intercepted then
  r.JS_VKeys_Intercept(0x71, -1)
  f2_intercepted = false
 end
end

local function CheckF2Toggle()
 local over = IsMouseOverMixer()
 UpdateF2Intercept(over)
 if not r.JS_VKeys_GetState then return end
 local state = r.JS_VKeys_GetState(0)
 if not state then return end
 local cur = state:byte(0x71) or 0
 if cur ~= 0 and prev_f2_state == 0 and over then
  settings_visible = not settings_visible
 end
 prev_f2_state = cur
end

local function UpdateSelectionTopmostBoost()
 local sel = r.CountSelectedTracks(0)
 local key = tostring(sel)
 for i = 0, sel - 1 do
  local t = r.GetSelectedTrack(0, i)
  if t then key = key .. ":" .. tostring(math.floor(r.GetMediaTrackInfo_Value(t, "IP_TRACKNUMBER") or 0)) end
 end
 if key ~= last_selection_key then
  last_selection_key = key
  RequestOverlayTopmost(12)
 end
end

local function IsMixerCovered()
 if not mixer_hwnd then return true end
 local ok, l, t, ri, b = r.JS_Window_GetRect(mixer_hwnd)
 if not ok then return true end
 local function hits(px, py)
  local hwnd = r.JS_Window_FromPoint(px, py)
  local cur = hwnd
  while cur do
   if cur == mixer_hwnd then return true end
   if overlay_hwnd and cur == overlay_hwnd then return true end
   cur = r.JS_Window_GetParent(cur)
  end
  return false
 end
 local cx = math.floor((l + ri) * 0.5)
 local cy = math.floor((t + b) * 0.5)
 if hits(cx, cy) then return false end
 if hits(l + 20, t + 20) then return false end
 if hits(ri - 20, t + 20) then return false end
 if hits(l + 20, b - 20) then return false end
 if hits(ri - 20, b - 20) then return false end
 return true
end

local function Loop()
 if not EnsureImGuiContext() then return end
 UpdateScreenScale()
 if settings_dirty then
  save_timer = save_timer + 1
  if save_timer > 30 then SaveSettings(); save_timer = 0 end
 end

 CheckF2Toggle()
 UpdateSelectionTopmostBoost()

 if r.GetExtState("TK_MCP_Cables_Overlay", "toggle_settings") ~= "" then
  r.DeleteExtState("TK_MCP_Cables_Overlay", "toggle_settings", false)
  settings_visible = not settings_visible
 end

 UpdateExternalToggleState()

 if settings_visible then DrawSettingsWindow() end

 local pc = r.GetProjectStateChangeCount(0)
 local force_rect = false
 if pc ~= last_project_change then
  last_project_change = pc
  force_rect = true
 end

 if settings.enabled and UpdateMixerRect(force_rect) and not IsMixerCovered() and HasCablesToDraw() then
  local w = (RIGHT - LEFT)
  local h = (BOT - TOP)
  if w > 4 and h > 4 then
   r.ImGui_SetNextWindowPos(ctx, LEFT, TOP)
   r.ImGui_SetNextWindowSize(ctx, w, h)
   local visible = r.ImGui_Begin(ctx, "TK MCP Cables Overlay", false, overlay_flags)
   if visible then
    local draw_list = r.ImGui_GetWindowDrawList(ctx)
    DrawCables(draw_list)
    if settings.debug_anchors then DrawDebugAnchors(draw_list) end
    r.ImGui_End(ctx)
    EnsureOverlayTopmost()
   end
  end
 else
  HideOverlayWindow()
 end

 r.defer(Loop)
end

r.defer(Loop)