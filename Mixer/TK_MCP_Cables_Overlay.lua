-- @description TK MCP Cables Overlay
-- @author TouristKiller
-- @version 1.3.0
-- @about Overlay script that draws send/receive cables over REAPER's native MCP
-- @changelog:
--   v1.3.0
--   + Hover labels now show audio channel routing (e.g. 1-2 -> 3-4) including mono and "none" states
--   + Hover labels now show MIDI channel routing with All/orig and "none" states
--   + Added companion action to toggle "Selected tracks only" mode
--   v1.2.3
--   + Added optional Natural curve mode using a catenary-style hyperbolic cosine shape
--   + Manual curve mode remains the default and keeps the existing adjustable Bezier behavior
--   + Hide the manual Curve slider while Natural curve mode is selected
--   v1.2.2
--   + Added optional hover labels with compact send and receive info
--   + Hover labels now show both send and receive direction
--   + Highlighted hovered cables and separated source and destination endpoint colors
--   v1.2.1
--   + Added manual below-mixer offset mode for floating mixer setups without topmost pinning
--   + Expanded below-mixer render area so cable curves are not clipped in the middle
--   + Offset below mixer now forces bottom anchors regardless of the anchor dropdown
--   + Hide the below-mixer offset slider until Offset below mixer is enabled
--   + Docked master offset handling now runs automatically when the mixer is floating
--   + Restyled the settings window with a dark rounded panel and red close button
--   + Removed the close icon cross and kept the settings close button out of auto-resize layout
--   v1.2.0
--   + Added small corner controls for pinning cables and opening settings
--   + Added optional pin mode to keep cables above a floating mixer when needed
--   + Default mode stays shortcut-safe, so REAPER shortcuts and menus keep working normally
--   + Selected tracks only now hides and restores cables more cleanly when changing selection
--   + Settings can now show or hide the corner controls
--   + Floating mixer note: with pin off and Selected tracks only off, cables may appear behind the mixer; enable pin mode for that situation
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
 curve_mode = "manual",
 glow = true,
 flow = false,
 show_cable_labels = false,
 selected_only = false,
 use_dest_color = false,
 anchor_position = "bottom",
 vertical_offset = 6,
 horizontal_offset = 0,
 hide_behind_master = true,
 master_side = "auto",
 debug_anchors = false,
 pin_on_top = false,
 offset_below_mixer = false,
 below_mixer_offset_y = 80,
 show_overlay_controls = true,
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

if r.ImGui_WindowFlags_NoBringToFrontOnFocus then
 overlay_flags = overlay_flags | r.ImGui_WindowFlags_NoBringToFrontOnFocus()
end

local settings_flags = r.ImGui_WindowFlags_NoTitleBar()
 | r.ImGui_WindowFlags_NoCollapse()
 | r.ImGui_WindowFlags_AlwaysAutoResize()
local pin_flags = r.ImGui_WindowFlags_NoTitleBar()
 | r.ImGui_WindowFlags_NoResize()
 | r.ImGui_WindowFlags_NoNav()
 | r.ImGui_WindowFlags_NoScrollbar()
 | r.ImGui_WindowFlags_NoDecoration()
 | r.ImGui_WindowFlags_NoDocking()
 | r.ImGui_WindowFlags_NoBackground()
 | r.ImGui_WindowFlags_NoMove()
 | r.ImGui_WindowFlags_NoSavedSettings()
 | r.ImGui_WindowFlags_NoFocusOnAppearing()

if r.ImGui_WindowFlags_NoBringToFrontOnFocus then
 pin_flags = pin_flags | r.ImGui_WindowFlags_NoBringToFrontOnFocus()
end

local LAST_RECT_VAL = 0
local LEFT, TOP, RIGHT, BOT = 0, 0, 0, 0
local RENDER_LEFT, RENDER_TOP, RENDER_RIGHT, RENDER_BOT = 0, 0, 0, 0
local track_x_offset_native = 0
local mixer_hwnd = nil
local mixer_visible_last = false
local mixer_open_last = nil
local mixer_search_t = 0
local settings_visible = false
local save_timer = 0
local last_project_change = -1
local overlay_hwnd = nil
local overlay_topmost_set = false
local overlay_shown_noactivate = false
local overlay_window_visible = false
local pin_hwnd = nil
local pin_topmost_set = false
local PARK_X, PARK_Y = -32000, -32000

local function EnsureImGuiContext()
 if r.ImGui_ValidatePtr and r.ImGui_ValidatePtr(ctx, "ImGui_Context*") then return true end
 if not r.ImGui_ValidatePtr then return true end
 ctx = r.ImGui_CreateContext('TK MCP Cables Overlay')
 overlay_hwnd = nil
 overlay_topmost_set = false
 overlay_shown_noactivate = false
 overlay_window_visible = false
 pin_hwnd = nil
 pin_topmost_set = false
 return r.ImGui_ValidatePtr(ctx, "ImGui_Context*")
end

local function ReleaseOverlayTopmost()
 if overlay_hwnd and r.JS_Window_IsWindow(overlay_hwnd) and r.JS_Window_SetZOrder then
    pcall(r.JS_Window_SetZOrder, overlay_hwnd, "NOTOPMOST")
 end
 overlay_topmost_set = false
end

local function EnsureOverlayTopmost()
 if not r.JS_Window_Find then return end
 if not overlay_hwnd or not r.JS_Window_IsWindow(overlay_hwnd) then
  overlay_hwnd = r.JS_Window_Find("TK MCP Cables Overlay", true)
  overlay_topmost_set = false
    overlay_shown_noactivate = false
 end
 if not overlay_hwnd then return end
 if settings.pin_on_top then
    if r.JS_Window_Show then r.JS_Window_Show(overlay_hwnd, "SHOWNOACTIVATE") end
    if r.JS_Window_SetZOrder then r.JS_Window_SetZOrder(overlay_hwnd, "TOPMOST") end
    overlay_topmost_set = true
    overlay_shown_noactivate = true
 else
    if overlay_topmost_set then ReleaseOverlayTopmost() end
    if not overlay_shown_noactivate and r.JS_Window_Show then
     r.JS_Window_Show(overlay_hwnd, "SHOWNOACTIVATE")
     overlay_shown_noactivate = true
    end
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
 if not ctx then return end
 if overlay_topmost_set then ReleaseOverlayTopmost() end
 r.ImGui_SetNextWindowPos(ctx, PARK_X, PARK_Y)
 r.ImGui_SetNextWindowSize(ctx, 1, 1)
 local visible = r.ImGui_Begin(ctx, "TK MCP Cables Overlay", false, overlay_flags)
 if visible then r.ImGui_End(ctx) end
 if not overlay_hwnd or not r.JS_Window_IsWindow(overlay_hwnd) then
  if r.JS_Window_Find then overlay_hwnd = r.JS_Window_Find("TK MCP Cables Overlay", true) end
 end
 if overlay_hwnd and r.JS_Window_IsWindow(overlay_hwnd) then
  if r.JS_Window_Show then r.JS_Window_Show(overlay_hwnd, "SHOWNOACTIVATE") end
 end
 overlay_topmost_set = false
 overlay_shown_noactivate = false
 overlay_window_visible = false
end

local function UpdateMixerRect(force)
 if not mixer_hwnd or not r.JS_Window_IsWindow(mixer_hwnd) then
  mixer_hwnd = GetMixerHWND()
  if not mixer_hwnd then
    mixer_visible_last = false
   local now = r.time_precise()
   if now - mixer_search_t > 0.2 then mixer_search_t = now end
   return false
  end
  force = true
 end
 if not mixer_visible_last then
   force = true
   overlay_shown_noactivate = false
   overlay_topmost_set = false
   pin_topmost_set = false
 end
 mixer_visible_last = true
 local ok, l, t, ri, b = r.JS_Window_GetRect(mixer_hwnd)
 if not ok then
  mixer_hwnd = nil
   mixer_visible_last = false
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
 end
 return true
end

local function IsNativeMixerOpen()
 local state = r.GetToggleCommandState(40078)
 if state == 0 then return false end
 return true
end

local function ResetMixerWindowState()
 mixer_hwnd = nil
 mixer_visible_last = false
 LAST_RECT_VAL = 0
 overlay_hwnd = nil
 overlay_topmost_set = false
 overlay_shown_noactivate = false
 overlay_window_visible = false
 pin_hwnd = nil
 pin_topmost_set = false
end

function TK_MCP_Cables_GetCurveMode()
 if settings.curve_mode == "natural" then return "natural" end
 return "manual"
end

function TK_MCP_Cables_GetManualDip(dist)
 local dip = math.max(24, dist * (settings.curve_amount or 0))
 if dip > 220 then dip = 220 end
 return dip
end

function TK_MCP_Cables_GetNaturalDip(dist)
 local dip = math.max(20, dist * 0.26)
 if dip > 190 then dip = 190 end
 return dip
end

function TK_MCP_Cables_GetCableDip(dist)
 if TK_MCP_Cables_GetCurveMode() == "natural" then return TK_MCP_Cables_GetNaturalDip(dist) end
 return TK_MCP_Cables_GetManualDip(dist)
end

local function UpdateRenderRect()
 local offset_y = 0
 local extra_h = 0
 if settings.offset_below_mixer and not settings.pin_on_top then
  offset_y = settings.below_mixer_offset_y or 0
  local max_dip = TK_MCP_Cables_GetCableDip(RIGHT - LEFT)
  extra_h = math.ceil(max_dip + (settings.thickness or 1) * 8 + 12)
 end
 RENDER_LEFT = LEFT
 RENDER_TOP = TOP + offset_y
 RENDER_RIGHT = RIGHT
 RENDER_BOT = BOT + offset_y + extra_h
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

local function muted_u32(alpha)
 return r.ImGui_ColorConvertDouble4ToU32(0.50, 0.52, 0.56, alpha)
end

local function TrackDisplayName(track)
 local ok, name = r.GetTrackName(track)
 if ok and name and name ~= "" then return name end
 if track == r.GetMasterTrack(0) then return "MASTER" end
 local idx = r.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER")
 if idx and idx > 0 then return "Track " .. math.floor(idx) end
 return "Track"
end

local function FormatDb(value)
 if not value or value <= 0.0000001 then return "-inf dB" end
 return string.format("%.1f dB", 20 * math.log(value) / math.log(10))
end

local function FormatPan(value)
 if not value or math.abs(value) < 0.005 then return "C" end
 local amount = math.floor(math.abs(value) * 100 + 0.5)
 if value < 0 then return "L" .. amount end
 return "R" .. amount
end

local function FormatChan(ch)
 local base = (ch & 1023) + 1
 if (ch & 1024) == 1024 then return tostring(base) end
 return string.format("%d-%d", base, base + 1)
end

local function FormatAudioRoute(track, send_idx)
 local src = r.GetTrackSendInfo_Value(track, 0, send_idx, "I_SRCCHAN")
 if not src or src == -1 then return "Audio: none" end
 local dst = r.GetTrackSendInfo_Value(track, 0, send_idx, "I_DSTCHAN")
 return "Audio " .. FormatChan(math.floor(src)) .. " -> " .. FormatChan(math.floor(dst))
end

local function FormatMidiRoute(track, send_idx)
 local flags = r.GetTrackSendInfo_Value(track, 0, send_idx, "I_MIDIFLAGS")
 if not flags then return "MIDI: none" end
 flags = math.floor(flags)
 local src = flags & 0x1F
 if src == 0x1F then return "MIDI: none" end
 local dst = (flags >> 5) & 0x1F
 local s = (src == 0) and "All" or tostring(src)
 local d = (dst == 0) and "orig" or tostring(dst)
 return "MIDI " .. s .. " -> " .. d
end

local function BezierPoint(sx, sy, c1x, c1y, c2x, c2y, dx, dy, t)
 local u = 1 - t
 local b0 = u * u * u
 local b1 = 3 * u * u * t
 local b2 = 3 * u * t * t
 local b3 = t * t * t
 return b0 * sx + b1 * c1x + b2 * c2x + b3 * dx, b0 * sy + b1 * c1y + b2 * c2y + b3 * dy
end

function TK_MCP_Cables_Cosh(value)
 local e = math.exp(value)
 return (e + 1 / e) * 0.5
end

function TK_MCP_Cables_CatenaryPoint(sx, sy, dx, dy, dip, shape, t)
 local x = sx + (dx - sx) * t
 local baseline_y = sy + (dy - sy) * t
 local u = t * 2 - 1
 local denom = TK_MCP_Cables_Cosh(shape) - 1
 local drop = dip * (TK_MCP_Cables_Cosh(shape) - TK_MCP_Cables_Cosh(shape * u)) / denom
 return x, baseline_y + drop
end

function TK_MCP_Cables_BuildCable(sx, sy, dx, dy)
 local dist = math.abs(dx - sx)
 local dip = TK_MCP_Cables_GetCableDip(dist)
 local cable = { sx = sx, sy = sy, dx = dx, dy = dy, mode = TK_MCP_Cables_GetCurveMode() }
 if cable.mode == "natural" then
  cable.dip = dip
  cable.shape = 2.15
 else
  cable.c1x, cable.c1y = sx, sy + dip
  cable.c2x, cable.c2y = dx, dy + dip
 end
 return cable
end

function TK_MCP_Cables_Point(cable, t)
 if cable.mode == "natural" then
  return TK_MCP_Cables_CatenaryPoint(cable.sx, cable.sy, cable.dx, cable.dy, cable.dip, cable.shape, t)
 end
 return BezierPoint(cable.sx, cable.sy, cable.c1x, cable.c1y, cable.c2x, cable.c2y, cable.dx, cable.dy, t)
end

function TK_MCP_Cables_FindHover(mx, my, cable)
 local best_dist = math.huge
 local best_x, best_y = cable.sx, cable.sy
 local span = math.max(math.abs(cable.dx - cable.sx), math.abs(cable.dy - cable.sy))
 local steps = math.floor(span / 18)
 if steps < 32 then steps = 32 elseif steps > 96 then steps = 96 end
 for step = 0, steps do
  local px, py = TK_MCP_Cables_Point(cable, step / steps)
  local x_dist = mx - px
  local y_dist = my - py
  local dist = x_dist * x_dist + y_dist * y_dist
  if dist < best_dist then
   best_dist = dist
   best_x, best_y = px, py
  end
 end
 return best_dist, best_x, best_y
end

function TK_MCP_Cables_DrawStroke(draw_list, cable, color, thickness)
 if cable.mode ~= "natural" then
  r.ImGui_DrawList_AddBezierCubic(draw_list, cable.sx, cable.sy, cable.c1x, cable.c1y, cable.c2x, cable.c2y, cable.dx, cable.dy, color, thickness, 32)
  return
 end
 local span = math.max(math.abs(cable.dx - cable.sx), math.abs(cable.dy - cable.sy))
 local steps = math.floor(span / 14)
 if steps < 32 then steps = 32 elseif steps > 112 then steps = 112 end
 local last_x, last_y = TK_MCP_Cables_Point(cable, 0)
 for step = 1, steps do
  local x, y = TK_MCP_Cables_Point(cable, step / steps)
  r.ImGui_DrawList_AddLine(draw_list, last_x, last_y, x, y, color, thickness)
  last_x, last_y = x, y
 end
end

local function GetOverlayMousePosition()
 if r.GetMousePosition then
  local mx, my = r.GetMousePosition()
  if mx and my then return r.ImGui_PointConvertNative(ctx, mx, my) end
 end
 if r.ImGui_GetMousePos then return r.ImGui_GetMousePos(ctx) end
 return nil, nil
end

local function BuildCableLabel(src_track, dst_track, send_idx, muted)
 local vol = r.GetTrackSendInfo_Value(src_track, 0, send_idx, "D_VOL")
 local pan = r.GetTrackSendInfo_Value(src_track, 0, send_idx, "D_PAN")
 local src_name = TrackDisplayName(src_track)
 local dst_name = TrackDisplayName(dst_track)
 local state = muted and "MUTED" or "ACTIVE"
 return {
  "SEND    " .. src_name .. " -> " .. dst_name,
  "RECEIVE " .. dst_name .. " <- " .. src_name,
  state .. " | " .. FormatDb(vol) .. " | " .. FormatPan(pan),
  FormatAudioRoute(src_track, send_idx) .. " | " .. FormatMidiRoute(src_track, send_idx),
 }
end

local function DrawCableLabel(draw_list, label)
 local lines = BuildCableLabel(label.src, label.dst, label.send_idx, label.muted)
 local tw, th = 0, 0
 local line_heights = {}
 local line_gap = 2
 for i, line in ipairs(lines) do
  local lw, lh
  if r.ImGui_CalcTextSize then
   lw, lh = r.ImGui_CalcTextSize(ctx, line)
  else
   lw, lh = #line * 7, 14
  end
  if lw > tw then tw = lw end
  line_heights[i] = lh
  th = th + lh
  if i < #lines then th = th + line_gap end
 end
 local pad_x, pad_y = 7, 4
 local x = label.x + 10
 local y = label.y - th - 12
 local w = tw + pad_x * 2
 local h = th + pad_y * 2
 if x + w > RENDER_RIGHT - 4 then x = RENDER_RIGHT - w - 4 end
 if x < RENDER_LEFT + 4 then x = RENDER_LEFT + 4 end
 if y < RENDER_TOP + 4 then y = label.y + 12 end
 if y + h > RENDER_BOT - 4 then y = RENDER_BOT - h - 4 end
 r.ImGui_DrawList_AddRectFilled(draw_list, x, y, x + w, y + h, 0x111216F0, 5)
 r.ImGui_DrawList_AddRect(draw_list, x, y, x + w, y + h, 0x4A4D55FF, 5, 0, 1)
 local text_y = y + pad_y
 for i, line in ipairs(lines) do
  local col = i == 1 and 0xF2F2F2FF or i == 2 and 0xBFC3CCFF or 0x9FA4AEFF
  r.ImGui_DrawList_AddText(draw_list, x + pad_x, text_y, col, line)
  text_y = text_y + line_heights[i] + line_gap
 end
end

local function DrawCableHighlight(draw_list, cable, clip_segments)
 for _, seg in ipairs(clip_segments) do
  r.ImGui_DrawList_PushClipRect(draw_list, seg[1], RENDER_TOP, seg[2], RENDER_BOT, 0)
  local halo = r.ImGui_ColorConvertDouble4ToU32(1, 1, 1, cable.muted and 0.18 or 0.32)
  local core = r.ImGui_ColorConvertDouble4ToU32(1, 1, 1, cable.muted and 0.45 or 0.75)
  local src_ring = cable.muted and muted_u32(0.85) or color_u32(cable.src, 0.95)
  local dst_ring = cable.muted and muted_u32(0.85) or color_u32(cable.dst, 0.95)
  TK_MCP_Cables_DrawStroke(draw_list, cable, halo, cable.thickness * 4.1)
  TK_MCP_Cables_DrawStroke(draw_list, cable, core, cable.thickness * 1.8)
  r.ImGui_DrawList_AddCircle(draw_list, cable.sx, cable.sy, cable.thickness * 3.2, src_ring, 18, 2)
  r.ImGui_DrawList_AddCircle(draw_list, cable.dx, cable.dy, cable.thickness * 3.2, dst_ring, 18, 2)
  r.ImGui_DrawList_PopClipRect(draw_list)
 end
end

local function GetAnchorPosition()
 if settings.offset_below_mixer then return "bottom" end
 return settings.anchor_position
end

local function GetMasterSide()
 local side = settings.master_side
 if side == "auto" then
  if r.GetToggleCommandState(40389) == 1 then side = "right" else side = "left" end
 end
 return side
end

local function IsMixerMasterVisible()
 return r.GetToggleCommandState(41209) == 1
end

local function IsMixerDocked()
 return r.GetToggleCommandState(40083) == 1
end

local function IsTcpMasterVisible()
 if r.GetMasterTrackVisibility then
  local visibility = r.GetMasterTrackVisibility()
  return visibility and (visibility & 1) == 1
 end
 return r.GetToggleCommandState(40075) == 1
end

local function ShouldIgnoreDockedMasterOffset(side)
 if side ~= "left" then return false end
 return IsTcpMasterVisible() and not IsMixerDocked()
end

local function ShouldApplyMasterOffset(side)
 if side ~= "left" then return false end
 if not IsMixerMasterVisible() then return false end
 if ShouldIgnoreDockedMasterOffset(side) then return false end
 return true
end

local function ComputeAnchorXY(mcpx, mcpy, mcpw, mcph)
 if mcpw <= 0 or mcph <= 0 then return nil end
 local x_offset = settings.horizontal_offset or 0
 local x = RENDER_LEFT + (mcpx + track_x_offset_native + mcpw * 0.5 + x_offset) / screen_scale
 local y_offset = settings.vertical_offset or 0
 local anchor_position = GetAnchorPosition()
 local y
 if anchor_position == "top" then
  y = RENDER_TOP + (mcpy + y_offset) / screen_scale
 elseif anchor_position == "center" then
  y = RENDER_TOP + (mcpy + mcph * 0.5 + y_offset) / screen_scale
 else
  y = RENDER_TOP + (mcpy + mcph - y_offset) / screen_scale
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

  local side = GetMasterSide()
  local use_master_offset = ShouldApplyMasterOffset(side)
  local show_master_anchor = IsMixerMasterVisible() and not ShouldIgnoreDockedMasterOffset(side)

  if mw > 0 and mh > 0 and show_master_anchor then
   master_mw_s = mw / screen_scale
   master_mh_s = mh / screen_scale
   master_my_s = my / screen_scale
   if side == "right" then
    master_screen_r = RENDER_RIGHT
    master_screen_l = RENDER_RIGHT - master_mw_s
    track_x_offset_native = 0
   else
    master_screen_l = RENDER_LEFT
    master_screen_r = RENDER_LEFT + master_mw_s
    track_x_offset_native = use_master_offset and mw or 0
   end
   local cx = (master_screen_l + master_screen_r) * 0.5
   local y_offset = settings.vertical_offset or 0
   local anchor_position = GetAnchorPosition()
   local cy
   if anchor_position == "top" then
    cy = RENDER_TOP + master_my_s + y_offset / screen_scale
   elseif anchor_position == "center" then
    cy = RENDER_TOP + master_my_s + master_mh_s * 0.5 + y_offset / screen_scale
   else
    cy = RENDER_TOP + master_my_s + master_mh_s - y_offset / screen_scale
   end
   anchors[master] = { x = cx, y = cy }
  else
   track_x_offset_native = 0
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
 local use_dest_color = settings.use_dest_color
 local glow = settings.glow
 local flow = settings.flow
 local selected_only = settings.selected_only
 local show_cable_labels = settings.show_cable_labels
 local mouse_x, mouse_y
 local hovered_label = nil
 local hovered_cable = nil
 local hovered_dist = math.huge
 if show_cable_labels then
  mouse_x, mouse_y = GetOverlayMousePosition()
 end

 r.ImGui_DrawList_PushClipRect(draw_list, RENDER_LEFT, RENDER_TOP, RENDER_RIGHT, RENDER_BOT, 0)

 local clip_segments = { { RENDER_LEFT, RENDER_RIGHT } }
 if settings.hide_behind_master and master_screen_l and master_screen_r
  and master_screen_r > RENDER_LEFT and master_screen_l < RENDER_RIGHT then
  local ml = math.max(RENDER_LEFT, master_screen_l)
  local mr = math.min(RENDER_RIGHT, master_screen_r)
  clip_segments = {}
  if ml > RENDER_LEFT then clip_segments[#clip_segments + 1] = { RENDER_LEFT, ml } end
  if mr < RENDER_RIGHT then clip_segments[#clip_segments + 1] = { mr, RENDER_RIGHT } end
 end

 local now = r.time_precise()

 local function DrawCablePass(seg_l, seg_r)
  r.ImGui_DrawList_PushClipRect(draw_list, seg_l, RENDER_TOP, seg_r, RENDER_BOT, 0)
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
        local color = muted and muted_u32(cable_alpha) or color_u32(color_track, cable_alpha)

        local sx, sy = src_anchor.x, src_anchor.y
        local dx, dy = dst_anchor.x, dst_anchor.y
    local cable = TK_MCP_Cables_BuildCable(sx, sy, dx, dy)
    cable.src = src_track
    cable.dst = dst_track
    cable.thickness = thickness
    cable.muted = muted

        if mouse_x and mouse_y and mouse_x >= seg_l and mouse_x <= seg_r and mouse_y >= RENDER_TOP and mouse_y <= RENDER_BOT then
     local dist_sq, label_x, label_y = TK_MCP_Cables_FindHover(mouse_x, mouse_y, cable)
         local threshold = math.max(16, thickness * 4 + 6)
         if dist_sq <= threshold * threshold and dist_sq < hovered_dist then
          hovered_dist = dist_sq
          hovered_label = { src = src_track, dst = dst_track, send_idx = i, muted = muted, x = label_x, y = label_y }
      hovered_cable = cable
         end
        end

        if glow then
         local glow_alpha = math.min(1, cable_alpha * 0.35)
         local glow_color = muted and muted_u32(glow_alpha) or color_u32(color_track, glow_alpha)
     TK_MCP_Cables_DrawStroke(draw_list, cable, glow_color, thickness * 2.6)
        end
    TK_MCP_Cables_DrawStroke(draw_list, cable, color, thickness)

        local plug_alpha = math.min(1, cable_alpha + 0.15)
        local src_plug_color = muted and muted_u32(plug_alpha) or color_u32(src_track, plug_alpha)
        local dst_plug_color = muted and muted_u32(plug_alpha) or color_u32(dst_track, plug_alpha)
        local outline_color = r.ImGui_ColorConvertDouble4ToU32(0, 0, 0, math.min(1, cable_alpha + 0.2))

        local out_size = thickness * 1.8
        r.ImGui_DrawList_AddRectFilled(draw_list, sx - out_size, sy - out_size, sx + out_size, sy + out_size, src_plug_color, 1)
        r.ImGui_DrawList_AddRect(draw_list, sx - out_size, sy - out_size, sx + out_size, sy + out_size, outline_color, 1, 0, 1)

        local arrow_size = thickness * 2.4
        r.ImGui_DrawList_AddTriangleFilled(draw_list, dx - arrow_size, dy + arrow_size, dx + arrow_size, dy + arrow_size, dx, dy, dst_plug_color)
        r.ImGui_DrawList_AddTriangle(draw_list, dx - arrow_size, dy + arrow_size, dx + arrow_size, dy + arrow_size, dx, dy, outline_color, 1)

        if flow and not muted then
         local cycle = 1.6
         local t = (now % cycle) / cycle
         local fx, fy = TK_MCP_Cables_Point(cable, t)
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

 if hovered_cable then DrawCableHighlight(draw_list, hovered_cable, clip_segments) end
 if hovered_label then DrawCableLabel(draw_list, hovered_label) end

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
 local side = GetMasterSide()
 local show_master_anchor = IsMixerMasterVisible() and not ShouldIgnoreDockedMasterOffset(side)
 if mw > 0 and mh > 0 and show_master_anchor then
  local mw_s = mw / screen_scale
  local mh_s = mh / screen_scale
  local my_s = my / screen_scale
  local l, ri
  if side == "right" then ri = RENDER_RIGHT; l = RENDER_RIGHT - mw_s else l = RENDER_LEFT; ri = RENDER_LEFT + mw_s end
  r.ImGui_DrawList_AddRect(draw_list, l, RENDER_TOP + my_s, ri, RENDER_TOP + my_s + mh_s, 0xFFFF00FF, 0, 0, 2)
  r.ImGui_DrawList_AddText(draw_list, l + 4, RENDER_TOP + my_s + 2, 0xFFFF00FF, "MASTER (" .. side .. ")")
 end
 local num = r.CountTracks(0)
 for i = 0, num - 1 do
  local tr = r.GetTrack(0, i)
  if tr and r.GetMediaTrackInfo_Value(tr, "B_SHOWINMIXER") == 1 then
   dot(tr, tostring(i + 1))
  end
 end
end

local function PushSettingsStyle()
 local vars = 0
 local colors = 0
 if r.ImGui_PushStyleVar then
  if r.ImGui_StyleVar_WindowRounding then r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowRounding(), 8); vars = vars + 1 end
  if r.ImGui_StyleVar_FrameRounding then r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), 5); vars = vars + 1 end
  if r.ImGui_StyleVar_GrabRounding then r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_GrabRounding(), 5); vars = vars + 1 end
  if r.ImGui_StyleVar_PopupRounding then r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_PopupRounding(), 6); vars = vars + 1 end
  if r.ImGui_StyleVar_WindowBorderSize then r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowBorderSize(), 1); vars = vars + 1 end
  if r.ImGui_StyleVar_WindowPadding then r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), 12, 10); vars = vars + 1 end
  if r.ImGui_StyleVar_FramePadding then r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FramePadding(), 7, 4); vars = vars + 1 end
  if r.ImGui_StyleVar_ItemSpacing then r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing(), 8, 7); vars = vars + 1 end
 end
 if r.ImGui_PushStyleColor then
  if r.ImGui_Col_WindowBg then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_WindowBg(), 0x121316F6); colors = colors + 1 end
  if r.ImGui_Col_Border then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Border(), 0x34363CFF); colors = colors + 1 end
  if r.ImGui_Col_Text then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0xE6E6E6FF); colors = colors + 1 end
  if r.ImGui_Col_FrameBg then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), 0x202226FF); colors = colors + 1 end
  if r.ImGui_Col_FrameBgHovered then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgHovered(), 0x2B2E34FF); colors = colors + 1 end
  if r.ImGui_Col_FrameBgActive then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgActive(), 0x383C44FF); colors = colors + 1 end
  if r.ImGui_Col_Button then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x2A2D33FF); colors = colors + 1 end
  if r.ImGui_Col_ButtonHovered then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0x383C44FF); colors = colors + 1 end
  if r.ImGui_Col_ButtonActive then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0x464B55FF); colors = colors + 1 end
  if r.ImGui_Col_Header then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Header(), 0x2A2D33FF); colors = colors + 1 end
  if r.ImGui_Col_HeaderHovered then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderHovered(), 0x383C44FF); colors = colors + 1 end
  if r.ImGui_Col_HeaderActive then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderActive(), 0x464B55FF); colors = colors + 1 end
  if r.ImGui_Col_CheckMark then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_CheckMark(), 0xE6E6E6FF); colors = colors + 1 end
  if r.ImGui_Col_SliderGrab then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrab(), 0x9A9EA8FF); colors = colors + 1 end
  if r.ImGui_Col_SliderGrabActive then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrabActive(), 0xC3C7D1FF); colors = colors + 1 end
  if r.ImGui_Col_PopupBg then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_PopupBg(), 0x15161AFF); colors = colors + 1 end
  if r.ImGui_Col_Separator then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Separator(), 0x3B3E45FF); colors = colors + 1 end
 end
 return vars, colors
end

local function PopSettingsStyle(vars, colors)
 if r.ImGui_PopStyleColor then
  for _ = 1, colors do r.ImGui_PopStyleColor(ctx) end
 end
 if r.ImGui_PopStyleVar then
  for _ = 1, vars do r.ImGui_PopStyleVar(ctx) end
 end
end

local function DrawSettingsCloseButton()
 if not (r.ImGui_GetWindowPos and r.ImGui_GetWindowWidth and r.ImGui_GetWindowDrawList) then return end
 local wx, wy = r.ImGui_GetWindowPos(ctx)
 local ww = r.ImGui_GetWindowWidth(ctx)
 local size = 14
 local x = wx + ww - size - 10
 local y = wy + 9
 local hovered = false
 local clicked = false
 if r.ImGui_GetMousePos then
  local mx, my = r.ImGui_GetMousePos(ctx)
  hovered = mx >= x and mx <= x + size and my >= y and my <= y + size
  clicked = hovered and r.ImGui_IsMouseClicked and r.ImGui_IsMouseClicked(ctx, 0)
 end
 local draw_list = r.ImGui_GetWindowDrawList(ctx)
 local fill = hovered and 0xFF4B4BFF or 0xD83B3BFF
 local cx = x + size * 0.5
 local cy = y + size * 0.5
 r.ImGui_DrawList_AddCircleFilled(draw_list, cx, cy, size * 0.5, fill, 18)
 if clicked then settings_visible = false end
end

local function DrawSettingsWindow()
 local vars, colors = PushSettingsStyle()
 r.ImGui_SetNextWindowSize(ctx, 320, 0, r.ImGui_Cond_FirstUseEver())
 local visible, open = r.ImGui_Begin(ctx, "TK MCP Cables Overlay - Settings", true, settings_flags)
 if visible then
  DrawSettingsCloseButton()
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
  if r.ImGui_BeginCombo(ctx, "Curve mode", TK_MCP_Cables_GetCurveMode() == "natural" and "Natural" or "Manual") then
   if r.ImGui_Selectable(ctx, "Manual", TK_MCP_Cables_GetCurveMode() == "manual") then
    settings.curve_mode = "manual"
    MarkDirty()
   end
   if r.ImGui_Selectable(ctx, "Natural", TK_MCP_Cables_GetCurveMode() == "natural") then
    settings.curve_mode = "natural"
    MarkDirty()
   end
   r.ImGui_EndCombo(ctx)
  end

  if TK_MCP_Cables_GetCurveMode() == "manual" then
   r.ImGui_SetNextItemWidth(ctx, 180)
   changed, settings.curve_amount = r.ImGui_SliderDouble(ctx, "Curve", settings.curve_amount, 0.0, 1.5, "%.2f")
   if changed then MarkDirty() end
  end

  r.ImGui_SetNextItemWidth(ctx, 180)
  changed, settings.vertical_offset = r.ImGui_SliderInt(ctx, "Vertical offset", settings.vertical_offset, 0, 80)
  if changed then MarkDirty() end

  r.ImGui_SetNextItemWidth(ctx, 180)
  changed, settings.horizontal_offset = r.ImGui_SliderInt(ctx, "Horizontal offset", settings.horizontal_offset, -80, 80)
  if changed then MarkDirty() end

  changed, settings.offset_below_mixer = r.ImGui_Checkbox(ctx, "Offset below mixer", settings.offset_below_mixer)
  if changed then
   if settings.offset_below_mixer then settings.anchor_position = "bottom" end
   MarkDirty()
  end

  if settings.offset_below_mixer then
   r.ImGui_SetNextItemWidth(ctx, 180)
   changed, settings.below_mixer_offset_y = r.ImGui_SliderInt(ctx, "Below mixer offset", settings.below_mixer_offset_y, 0, 400)
   if changed then MarkDirty() end
  end

  local pos_items = { "bottom", "center", "top" }
  r.ImGui_SetNextItemWidth(ctx, 180)
  if r.ImGui_BeginCombo(ctx, "Anchor", GetAnchorPosition()) then
   for _, v in ipairs(pos_items) do
    local sel = v == GetAnchorPosition()
    if r.ImGui_Selectable(ctx, v, sel) then
     settings.anchor_position = settings.offset_below_mixer and "bottom" or v
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

  changed, settings.show_cable_labels = r.ImGui_Checkbox(ctx, "Show cable labels", settings.show_cable_labels)
  if changed then MarkDirty() end

  changed, settings.selected_only = r.ImGui_Checkbox(ctx, "Selected tracks only", settings.selected_only)
  if changed then MarkDirty() end

  changed, settings.use_dest_color = r.ImGui_Checkbox(ctx, "Use destination color", settings.use_dest_color)
  if changed then MarkDirty() end

  changed, settings.hide_behind_master = r.ImGui_Checkbox(ctx, "Hide cables behind master", settings.hide_behind_master)
  if changed then MarkDirty() end

   changed, settings.pin_on_top = r.ImGui_Checkbox(ctx, "Pin cables on top", settings.pin_on_top)
   if changed then
    MarkDirty()
    if settings.pin_on_top then
      overlay_topmost_set = false
    else
      ReleaseOverlayTopmost()
    end
   end

   changed, settings.show_overlay_controls = r.ImGui_Checkbox(ctx, "Show corner controls", settings.show_overlay_controls)
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

  r.ImGui_End(ctx)
 end
 PopSettingsStyle(vars, colors)
 if not open then settings_visible = false end
end

local function EnsurePinWindowTopmost()
 if not r.JS_Window_Find then return end
 if not pin_hwnd or not r.JS_Window_IsWindow(pin_hwnd) then
  pin_hwnd = r.JS_Window_Find("TK MCP Cables Pin", true)
  pin_topmost_set = false
 end
 if pin_hwnd and not pin_topmost_set then
  if r.JS_Window_Show then r.JS_Window_Show(pin_hwnd, "SHOWNOACTIVATE") end
  if r.JS_Window_SetZOrder then r.JS_Window_SetZOrder(pin_hwnd, "TOPMOST") end
  pin_topmost_set = true
 end
end

local function HidePinWindow()
 if not ctx then return end
 r.ImGui_SetNextWindowPos(ctx, PARK_X, PARK_Y)
 r.ImGui_SetNextWindowSize(ctx, 1, 1)
 local visible = r.ImGui_Begin(ctx, "TK MCP Cables Pin", false, pin_flags)
 if visible then r.ImGui_End(ctx) end
 if not pin_hwnd or not r.JS_Window_IsWindow(pin_hwnd) then
  if r.JS_Window_Find then pin_hwnd = r.JS_Window_Find("TK MCP Cables Pin", true) end
 end
 if pin_hwnd and r.JS_Window_IsWindow(pin_hwnd) then
  if r.JS_Window_Show then r.JS_Window_Show(pin_hwnd, "SHOWNOACTIVATE") end
  pin_topmost_set = false
 end
end

local function DrawPinIcon(draw_list, x, y, size, hovered)
 local pinned = settings.pin_on_top
 local fill = pinned and r.ImGui_ColorConvertDouble4ToU32(0.95, 0.68, 0.16, 0.95)
  or r.ImGui_ColorConvertDouble4ToU32(0.90, 0.94, 1.0, hovered and 0.95 or 0.72)
 local ring = pinned and r.ImGui_ColorConvertDouble4ToU32(1.0, 0.92, 0.45, 1.0)
  or r.ImGui_ColorConvertDouble4ToU32(0.15, 0.18, 0.22, hovered and 0.95 or 0.72)
 local cx = x + size * 0.5
 local cy = y + size * 0.5
 r.ImGui_DrawList_AddCircleFilled(draw_list, cx, cy, size * 0.28, fill, 16)
 r.ImGui_DrawList_AddCircle(draw_list, cx, cy, size * 0.34, ring, 16, hovered and 2 or 1)
end

local function DrawSettingsIcon(draw_list, x, y, size, hovered)
 local fill = r.ImGui_ColorConvertDouble4ToU32(0.90, 0.94, 1.0, hovered and 1.0 or 0.78)
 local ring = r.ImGui_ColorConvertDouble4ToU32(0.15, 0.18, 0.22, hovered and 0.95 or 0.72)
 local cx = x + size * 0.5
 local cy = y + size * 0.5
 r.ImGui_DrawList_AddCircle(draw_list, cx, cy, size * 0.34, ring, 16, hovered and 2 or 1)
 r.ImGui_DrawList_AddTriangleFilled(draw_list, cx, cy - size * 0.26, cx - size * 0.24, cy + size * 0.18, cx + size * 0.24, cy + size * 0.18, fill)
end

local function DrawPinButton()
 if not ctx then return end
 local size = 18
 local gap = 2
 local margin = 1
 local controls_w = size
 local controls_h = size * 2 + gap
 r.ImGui_SetNextWindowPos(ctx, RIGHT - controls_w - margin, TOP + margin)
 r.ImGui_SetNextWindowSize(ctx, controls_w, controls_h)
 local pushed_padding = false
 if r.ImGui_PushStyleVar and r.ImGui_StyleVar_WindowPadding then
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), 0, 0)
  pushed_padding = true
 end
 EnsurePinWindowTopmost()
 local visible = r.ImGui_Begin(ctx, "TK MCP Cables Pin", false, pin_flags)
 if visible then
  local x, y = r.ImGui_GetCursorScreenPos(ctx)
  local clicked = false
  if r.ImGui_InvisibleButton then
   clicked = r.ImGui_InvisibleButton(ctx, "##pin", size, size)
  else
   clicked = r.ImGui_Button(ctx, settings.pin_on_top and "Pinned" or "Pin", size, size)
  end
  if clicked then
   settings.pin_on_top = not settings.pin_on_top
   MarkDirty()
   if settings.pin_on_top then
    overlay_topmost_set = false
   else
    ReleaseOverlayTopmost()
   end
   pin_topmost_set = false
  end
  local hovered = r.ImGui_IsItemHovered and r.ImGui_IsItemHovered(ctx)
  local draw_list = r.ImGui_GetWindowDrawList(ctx)
  DrawPinIcon(draw_list, x, y, size, hovered)
  if hovered and r.ImGui_BeginTooltip and r.ImGui_BeginTooltip(ctx) then
   if settings.pin_on_top then
    r.ImGui_Text(ctx, "Cables pinned on top")
    r.ImGui_Text(ctx, "REAPER shortcuts and menu focus may not work while this is enabled.")
    r.ImGui_Text(ctx, "Click to return to shortcut-safe mode.")
   else
    r.ImGui_Text(ctx, "Pin cables on top")
    r.ImGui_Text(ctx, "Keeps cables above the floating mixer.")
    r.ImGui_Text(ctx, "REAPER shortcuts and menu focus may not work while pinned.")
   end
   r.ImGui_EndTooltip(ctx)
  end

   local settings_y = y + size + gap
   if r.ImGui_SetCursorScreenPos then r.ImGui_SetCursorScreenPos(ctx, x, settings_y) end
   local settings_clicked = false
   if r.ImGui_InvisibleButton then
    settings_clicked = r.ImGui_InvisibleButton(ctx, "##settings", size, size)
   else
    settings_clicked = r.ImGui_Button(ctx, "Settings", size, size)
   end
   if settings_clicked then settings_visible = not settings_visible end
   local settings_hovered = r.ImGui_IsItemHovered and r.ImGui_IsItemHovered(ctx)
   DrawSettingsIcon(draw_list, x, settings_y, size, settings_hovered)
   if settings_hovered and r.ImGui_BeginTooltip and r.ImGui_BeginTooltip(ctx) then
    r.ImGui_Text(ctx, settings_visible and "Close cable settings" or "Open cable settings")
    r.ImGui_Text(ctx, "Adjust cable appearance and filtering.")
    r.ImGui_EndTooltip(ctx)
   end

  r.ImGui_End(ctx)
  EnsurePinWindowTopmost()
 end
 if pushed_padding then r.ImGui_PopStyleVar(ctx) end
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
 ReleaseOverlayTopmost()
 HidePinWindow()
 if sectionID ~= -1 then
  r.SetToggleCommandState(sectionID, cmdID, 0)
  r.RefreshToolbar2(sectionID, cmdID)
 end
 if ext_toggle_sec and ext_toggle_cmd then
  r.SetToggleCommandState(ext_toggle_sec, ext_toggle_cmd, 0)
  r.RefreshToolbar2(ext_toggle_sec, ext_toggle_cmd)
 end
end)

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
   if pin_hwnd and cur == pin_hwnd then return true end
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

 if r.GetExtState("TK_MCP_Cables_Overlay", "toggle_settings") ~= "" then
  r.DeleteExtState("TK_MCP_Cables_Overlay", "toggle_settings", false)
  settings_visible = not settings_visible
 end

 if r.GetExtState("TK_MCP_Cables_Overlay", "toggle_selected_only") ~= "" then
  r.DeleteExtState("TK_MCP_Cables_Overlay", "toggle_selected_only", false)
  settings.selected_only = not settings.selected_only
  MarkDirty()
 end

 UpdateExternalToggleState()

 if settings_visible then DrawSettingsWindow() end

 local pc = r.GetProjectStateChangeCount(0)
 local force_rect = false
 if pc ~= last_project_change then
  last_project_change = pc
  force_rect = true
 end

 local mixer_open = IsNativeMixerOpen()
 if mixer_open_last ~= nil and mixer_open ~= mixer_open_last then
  if not mixer_open and overlay_window_visible then HideOverlayWindow() end
  ResetMixerWindowState()
  force_rect = true
 end
 mixer_open_last = mixer_open

 local mixer_alive = settings.enabled and mixer_open and UpdateMixerRect(force_rect)
 local mixer_ready = mixer_alive and not IsMixerCovered()
 local cables_ready = mixer_ready and HasCablesToDraw()
 local overlay_drawn = false
 UpdateRenderRect()

 if cables_ready then
  local w = (RIGHT - LEFT)
  local h = (RENDER_BOT - RENDER_TOP)
  if w > 4 and h > 4 then
    EnsureOverlayTopmost()
   r.ImGui_SetNextWindowPos(ctx, RENDER_LEFT, RENDER_TOP)
   r.ImGui_SetNextWindowSize(ctx, w, h)
   local visible = r.ImGui_Begin(ctx, "TK MCP Cables Overlay", false, overlay_flags)
   if visible then
    local draw_list = r.ImGui_GetWindowDrawList(ctx)
    DrawCables(draw_list)
    if settings.debug_anchors then DrawDebugAnchors(draw_list) end
    r.ImGui_End(ctx)
    EnsureOverlayTopmost()
     overlay_window_visible = true
     overlay_drawn = true
   end
  end
   end

   if not overlay_drawn and overlay_window_visible then
  HideOverlayWindow()
 end

 if mixer_alive and settings.show_overlay_controls then DrawPinButton() else HidePinWindow() end

 r.defer(Loop)
end

r.defer(Loop)