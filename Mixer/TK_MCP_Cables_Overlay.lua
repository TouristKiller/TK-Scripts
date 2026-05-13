-- @description TK MCP Cables Overlay
-- @author TouristKiller
-- @version 1.0.0
-- @about Overlay script that draws send/receive cables over REAPER's native MCP
-- @changelog:
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
local ok_json, json = pcall(require, "json")
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
local mixer_hwnd = nil
local mixer_search_t = 0
local settings_visible = false
local save_timer = 0

local function UpdateMixerRect(force)
 if not mixer_hwnd or not r.JS_Window_IsWindow(mixer_hwnd) then
  local now = r.time_precise()
  if now - mixer_search_t > 0.5 then
   mixer_search_t = now
   mixer_hwnd = GetMixerHWND()
  end
  if not mixer_hwnd then return false end
 end
 local ok, l, t, ri, b = r.JS_Window_GetRect(mixer_hwnd)
 if not ok then return false end
 local val = l + t + ri + b
 if val ~= LAST_RECT_VAL or force then
  LAST_RECT_VAL = val
  LEFT, TOP = r.ImGui_PointConvertNative(ctx, l, t)
  RIGHT, BOT = r.ImGui_PointConvertNative(ctx, ri, b)
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
 local x = LEFT + (mcpx + mcpw * 0.5 + x_offset) / screen_scale
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
 do
  local mx = r.GetMediaTrackInfo_Value(master, "I_MCPX")
  local my = r.GetMediaTrackInfo_Value(master, "I_MCPY")
  local mw = r.GetMediaTrackInfo_Value(master, "I_MCPW")
  local mh = r.GetMediaTrackInfo_Value(master, "I_MCPH")
  local x, y = ComputeAnchorXY(mx, my, mw, mh)
  if x then anchors[master] = { x = x, y = y } end
 end

 for i = 0, num_tracks - 1 do
  local tr = r.GetTrack(0, i)
  if tr and r.GetMediaTrackInfo_Value(tr, "B_SHOWINMIXER") == 1 then
   local mcpx = r.GetMediaTrackInfo_Value(tr, "I_MCPX")
   local mcpy = r.GetMediaTrackInfo_Value(tr, "I_MCPY")
   local mcpw = r.GetMediaTrackInfo_Value(tr, "I_MCPW")
   local mcph = r.GetMediaTrackInfo_Value(tr, "I_MCPH")
   local x, y = ComputeAnchorXY(mcpx, mcpy, mcpw, mcph)
   if x and x >= LEFT and x <= RIGHT and y >= TOP and y <= BOT then
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

 local now = r.time_precise()

 for src_track, src_anchor in pairs(anchors) do
  if src_track ~= master then
   local send_count = r.GetTrackNumSends(src_track, 0)
   for i = 0, send_count - 1 do
    local dst_track = r.GetTrackSendInfo_Value(src_track, 0, i, "P_DESTTRACK")
    if dst_track and dst_track ~= src_track then
     local dst_anchor = anchors[dst_track]
     if dst_anchor then
      local skip = false
      if selected_only and not (r.IsTrackSelected(src_track) or r.IsTrackSelected(dst_track)) then
       skip = true
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
        local dot_color = color_u32(color_track, math.min(1, cable_alpha + 0.25))
        r.ImGui_DrawList_AddCircleFilled(draw_list, fx, fy, thickness * 1.4, dot_color, 12)
       end
      end
     end
    end
   end
  end
 end

 r.ImGui_DrawList_PopClipRect(draw_list)
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

  r.ImGui_Separator(ctx)
  if r.ImGui_Button(ctx, "Close") then settings_visible = false end
 end
 r.ImGui_End(ctx)
 if not open then settings_visible = false end
end

local _, _, sectionID, cmdID = r.get_action_context()
if sectionID ~= -1 then
 r.SetToggleCommandState(sectionID, cmdID, 1)
 r.RefreshToolbar2(sectionID, cmdID)
end

r.atexit(function()
 if settings_dirty then SaveSettings() end
 if sectionID ~= -1 then
  r.SetToggleCommandState(sectionID, cmdID, 0)
  r.RefreshToolbar2(sectionID, cmdID)
 end
end)

local function Loop()
 UpdateScreenScale()
 if settings_dirty then
  save_timer = save_timer + 1
  if save_timer > 30 then SaveSettings(); save_timer = 0 end
 end

 if r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_F2(), false) then
  settings_visible = not settings_visible
 end

 if settings_visible then DrawSettingsWindow() end

 if settings.enabled and UpdateMixerRect(false) then
  local w = (RIGHT - LEFT)
  local h = (BOT - TOP)
  if w > 4 and h > 4 then
   r.ImGui_SetNextWindowPos(ctx, LEFT, TOP)
   r.ImGui_SetNextWindowSize(ctx, w, h)
   local visible = r.ImGui_Begin(ctx, "TK MCP Cables Overlay", false, overlay_flags)
   if visible then
    local draw_list = r.ImGui_GetWindowDrawList(ctx)
    DrawCables(draw_list)
   end
   r.ImGui_End(ctx)
  end
 end

 r.defer(Loop)
end

settings_visible = true
r.defer(Loop)