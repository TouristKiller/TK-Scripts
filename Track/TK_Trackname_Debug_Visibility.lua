-- @description TK_Trackname_Debug_Visibility
-- @author TouristKiller
-- @version 1.0
-- @about
--   Standalone diagnostic overlay for the "labels/values disappear below the
--   middle of the screen" issue (Mac/Retina). Replicates the exact visible-range
--   math from TK_Trackname_in_Arrange.lua and draws the values on screen plus a
--   red marker line where "view_bottom" lands. Take a screenshot and send it.

local r = reaper

if not r.ImGui_GetBuiltinPath then
    r.ShowMessageBox("ReaImGui is required.", "TK Debug", 0)
    return
end

local OS        = r.GetOS()
local IS_WIN    = OS:find("Win") ~= nil

package.path    = r.ImGui_GetBuiltinPath() .. '/?.lua;' .. package.path
local im        = require 'imgui' '0.9.3'
local ctx       = im.CreateContext('TK Debug Visibility')

local main      = r.GetMainHwnd()
local arrange   = r.JS_Window_FindChildByID(main, 0x3E8)

local screen_scale = 1
local scroll_size  = 0
local LEFT, TOP, RIGHT, BOT = 0, 0, 0, 0
local OLD_VAL = 0

local overlay_flags = r.ImGui_WindowFlags_NoTitleBar() |
                      r.ImGui_WindowFlags_NoResize() |
                      r.ImGui_WindowFlags_NoNav() |
                      r.ImGui_WindowFlags_NoScrollbar() |
                      r.ImGui_WindowFlags_NoDecoration() |
                      r.ImGui_WindowFlags_NoDocking() |
                      r.ImGui_WindowFlags_NoBackground() |
                      r.ImGui_WindowFlags_NoInputs() |
                      r.ImGui_WindowFlags_TopMost()

local function SetWindowScale(ImGuiScale)
    if IS_WIN then
        screen_scale = ImGuiScale
    else
        screen_scale = 1
    end
end

local function DrawOverArrange()
    local _, DPI_RPR = r.get_config_var_string("uiscale")
    scroll_size = 15 * DPI_RPR

    local _, orig_LEFT, orig_TOP, orig_RIGHT, orig_BOT = r.JS_Window_GetRect(arrange)
    local current_val = orig_TOP + orig_BOT + orig_LEFT + orig_RIGHT

    if current_val ~= OLD_VAL then
        OLD_VAL = current_val
        LEFT, TOP = im.PointConvertNative(ctx, orig_LEFT, orig_TOP)
        RIGHT, BOT = im.PointConvertNative(ctx, orig_RIGHT, orig_BOT)
    end
    r.ImGui_SetNextWindowPos(ctx, LEFT, TOP)
    r.ImGui_SetNextWindowSize(ctx, (RIGHT - LEFT) - scroll_size, (BOT - TOP) - scroll_size)
end

local function GetArrangeViewBounds()
    local _, _, _, _, view_height = r.JS_Window_GetClientRect(arrange)
    return view_height
end

local function FindFirstVisibleTrack(track_count, view_bottom)
    if track_count == 0 then return -1 end
    local low, high = 0, track_count - 1
    local result = -1
    while low <= high do
        local mid = math.floor((low + high) / 2)
        local track = r.GetTrack(0, mid)
        local track_y = r.GetMediaTrackInfo_Value(track, "I_TCPY") / screen_scale
        local track_height = r.GetMediaTrackInfo_Value(track, "I_TCPH") / screen_scale
        local track_bottom = track_y + track_height
        if track_bottom >= 0 and track_y < view_bottom then
            result = mid
            high = mid - 1
        elseif track_bottom < 0 then
            low = mid + 1
        else
            high = mid - 1
        end
    end
    if result > 0 then result = result - 1 end
    return result
end

local function FindLastVisibleTrack(track_count, view_bottom)
    if track_count == 0 then return -1 end
    local low, high = 0, track_count - 1
    local result = -1
    while low <= high do
        local mid = math.floor((low + high) / 2)
        local track = r.GetTrack(0, mid)
        local track_y = r.GetMediaTrackInfo_Value(track, "I_TCPY") / screen_scale
        if track_y <= view_bottom then
            result = mid
            low = mid + 1
        else
            high = mid - 1
        end
    end
    if result >= 0 and result < track_count - 1 then result = result + 1 end
    return result
end

local function loop()
    local ImGuiScale = r.ImGui_GetWindowDpiScale(ctx)
    SetWindowScale(ImGuiScale)

    DrawOverArrange()

    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_WindowBg(), 0x00000000)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowBorderSize(), 0.0)

    local visible = r.ImGui_Begin(ctx, 'TK Debug Visibility Overlay', true, overlay_flags)
    if visible then
        local draw_list = r.ImGui_GetForegroundDrawList(ctx)
        local WX, WY = r.ImGui_GetWindowPos(ctx)

        local track_count = r.CountTracks(0)
        local view_height = GetArrangeViewBounds()
        local view_bottom = view_height / screen_scale
        local overlay_h = BOT - TOP
        local first_idx = FindFirstVisibleTrack(track_count, view_bottom)
        local last_idx  = FindLastVisibleTrack(track_count, view_bottom)

        local ratio = (view_bottom ~= 0) and (overlay_h / view_bottom) or 0

        -- Last track coordinates (the ones most likely to be culled)
        local last_track_y, last_track_h = -1, -1
        if track_count > 0 then
            local t = r.GetTrack(0, track_count - 1)
            last_track_y = r.GetMediaTrackInfo_Value(t, "I_TCPY") / screen_scale
            last_track_h = r.GetMediaTrackInfo_Value(t, "I_TCPH") / screen_scale
        end

        local lines = {
            string.format("TK DEBUG  OS=%s", OS),
            string.format("ImGuiScale (DpiScale) = %.3f", ImGuiScale),
            string.format("screen_scale          = %.3f", screen_scale),
            string.format("view_height (JS rect) = %.1f", view_height),
            string.format("view_bottom           = %.1f", view_bottom),
            string.format("BOT - TOP (overlay h) = %.1f", overlay_h),
            string.format(">> ratio (BOT-TOP)/view_bottom = %.3f", ratio),
            string.format("track_count           = %d", track_count),
            string.format("first_visible_idx     = %d", first_idx),
            string.format("last_visible_idx      = %d  (van %d)", last_idx, track_count - 1),
            string.format("last track  I_TCPY=%.1f  I_TCPH=%.1f", last_track_y, last_track_h),
        }

        local pad = 10
        local line_h = 18
        local box_w = 430
        local box_h = (#lines * line_h) + (pad * 2)
        r.ImGui_DrawList_AddRectFilled(draw_list, WX + 8, WY + 8, WX + 8 + box_w, WY + 8 + box_h, 0xCC000000, 6)
        for i, txt in ipairs(lines) do
            local col = 0xFFFF00FF
            if i == 7 then col = 0x66FFFFFF end
            r.ImGui_DrawList_AddText(draw_list, WX + 8 + pad, WY + 8 + pad + (i - 1) * line_h, col, txt)
        end

        -- Red marker line at view_bottom (same space as drawn tracks: WY + track_y)
        local marker_y = WY + view_bottom
        r.ImGui_DrawList_AddLine(draw_list, WX, marker_y, WX + (RIGHT - LEFT), marker_y, 0xFF3030FF, 2)
        r.ImGui_DrawList_AddText(draw_list, WX + 12, marker_y + 2, 0xFF3030FF, "<-- view_bottom (cull-grens)")

        -- Green line at actual overlay bottom for reference
        local bottom_y = WY + overlay_h
        r.ImGui_DrawList_AddLine(draw_list, WX, bottom_y - 2, WX + (RIGHT - LEFT), bottom_y - 2, 0x30FF30FF, 2)
        r.ImGui_DrawList_AddText(draw_list, WX + 12, bottom_y - 18, 0x30FF30FF, "<-- echte onderkant arrange (BOT-TOP)")
    end
    r.ImGui_End(ctx)
    r.ImGui_PopStyleVar(ctx)
    r.ImGui_PopStyleColor(ctx)

    r.defer(loop)
end

r.defer(loop)
