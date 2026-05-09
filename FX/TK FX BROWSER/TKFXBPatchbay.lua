local r = reaper

local PB = {}

local NODE_W = 180
local NODE_H = 60
local PIN_R = 6
local COL_W = 240
local ROW_H = 80
local GRID = 40
local MASTER_GUID = "__MASTER__"

local function IsMasterEntry(tr) return tr and tr.is_master end

local node_positions = {}
local canvas_offset_x = 0
local canvas_offset_y = 0
local canvas_zoom = 1.0
local MIN_ZOOM = 0.3
local MAX_ZOOM = 2.5
local dragging_node_guid = nil
local pending_connection = nil
local right_click_send = nil
local layout_dirty = false
local layout_loaded_project = nil
local last_save_time = 0
local hovered_input_guid = nil
local pending_auto_layout = false
local pending_center_view = false
local pb_press_guid = nil
local pb_press_dragged = false
local pb_open_fx_for = nil
local fx_popup_track = nil
local pb_selected_set = {}
local pb_rubber_active = false
local pb_rubber_start_x = 0
local pb_rubber_start_y = 0

local function GetCtx()
    return _G.ctx
end

local function GetConfig()
    return _G.config
end

local function HasGuid(guid)
    return guid ~= nil and node_positions[guid] ~= nil
end

local function EncodeLayout()
    local lines = {}
    for guid, p in pairs(node_positions) do
        lines[#lines + 1] = string.format("%s|%.1f|%.1f", guid, p.x, p.y)
    end
    lines[#lines + 1] = string.format("__off__|%.1f|%.1f", canvas_offset_x, canvas_offset_y)
    lines[#lines + 1] = string.format("__zoom__|%.4f|0", canvas_zoom)
    return table.concat(lines, "\n")
end

local function DecodeLayout(s)
    local out = {}
    local off_x, off_y = 0, 0
    local zoom = 1.0
    if not s or s == "" then return out, off_x, off_y, zoom end
    for line in s:gmatch("([^\n]+)") do
        local g, xs, ys = line:match("^([^|]+)|([^|]+)|(.+)$")
        if g and xs and ys then
            local x = tonumber(xs)
            local y = tonumber(ys)
            if x and y then
                if g == "__off__" then
                    off_x, off_y = x, y
                elseif g == "__zoom__" then
                    zoom = math.max(MIN_ZOOM, math.min(MAX_ZOOM, x))
                else
                    out[g] = { x = x, y = y }
                end
            end
        end
    end
    return out, off_x, off_y, zoom
end

local function SaveLayout()
    local s = EncodeLayout()
    r.SetProjExtState(0, "TK_FXB_PATCHBAY", "layout", s)
    layout_dirty = false
    last_save_time = r.time_precise()
end

local function LoadLayout()
    local _, s = r.GetProjExtState(0, "TK_FXB_PATCHBAY", "layout")
    local positions, ox, oy, zm = DecodeLayout(s or "")
    node_positions = positions
    canvas_offset_x = ox
    canvas_offset_y = oy
    canvas_zoom = zm or 1.0
    layout_dirty = false
end

local function GetCurrentProjectKey()
    local _, fn = r.EnumProjects(-1)
    return fn or ""
end

local function CollectVisibleTracks()
    local filter = ((GetConfig().routing_filter_text or "")):lower()
    local only_selected = GetConfig().routing_only_selected
    local TRACK_SEL = _G.TRACK
    local n = r.CountTracks(0)
    local list = {}
    local any_mainsend = false
    for i = 0, n - 1 do
        local t = r.GetTrack(0, i)
        local _, name = r.GetTrackName(t)
        local nrec = r.GetTrackNumSends(t, -1)
        local nsnd = r.GetTrackNumSends(t, 0)
        local mainsend = r.GetMediaTrackInfo_Value(t, "B_MAINSEND") == 1
        if mainsend then any_mainsend = true end
        local has_routing = (nrec > 0 or nsnd > 0 or mainsend)
        local match_filter = filter == "" or name:lower():find(filter, 1, true) ~= nil
        local match_sel = true
        if only_selected and TRACK_SEL and r.ValidatePtr(TRACK_SEL, "MediaTrack*") then
            match_sel = (t == TRACK_SEL)
        end
        if has_routing and match_filter and match_sel then
            list[#list + 1] = { track = t, idx = i, name = name, guid = r.GetTrackGUID(t) }
        end
    end
    local master = r.GetMasterTrack(0)
    local master_match_filter = filter == "" or ("master"):find(filter, 1, true) ~= nil
    local master_match_sel = true
    if only_selected and TRACK_SEL and r.ValidatePtr(TRACK_SEL, "MediaTrack*") then
        master_match_sel = (TRACK_SEL == master)
    end
    local nmsnd = r.GetTrackNumSends(master, 0)
    local nmrec = r.GetTrackNumSends(master, -1)
    local master_has_routing = any_mainsend or nmsnd > 0 or nmrec > 0
    local show_master = GetConfig().patchbay_show_master ~= false
    if show_master and master_has_routing and master_match_filter and master_match_sel then
        list[#list + 1] = { track = master, idx = -1, name = "MASTER", guid = MASTER_GUID, is_master = true }
    end
    return list
end

local function AutoLayout(tracks)
    local guid_to = {}
    local master_entry = nil
    local regular = {}
    for i = 1, #tracks do
        if tracks[i].is_master then
            master_entry = tracks[i]
        else
            regular[#regular + 1] = tracks[i]
            guid_to[tracks[i].guid] = tracks[i]
        end
    end

    local placed = {}
    local columns = {}
    local remaining = {}
    for i = 1, #regular do remaining[regular[i].guid] = regular[i] end

    local col = 0
    while next(remaining) ~= nil do
        local current = {}
        for g, tr in pairs(remaining) do
            local t = tr.track
            local nrec = r.GetTrackNumSends(t, -1)
            local unmet = false
            for k = 0, nrec - 1 do
                local src = r.GetTrackSendInfo_Value(t, -1, k, "P_SRCTRACK")
                if src and r.ValidatePtr(src, "MediaTrack*") then
                    local sg = r.GetTrackGUID(src)
                    if guid_to[sg] and not placed[sg] then
                        unmet = true
                        break
                    end
                end
            end
            if not unmet then current[#current + 1] = tr end
        end
        if #current == 0 then
            for g, tr in pairs(remaining) do current[#current + 1] = tr end
        end
        table.sort(current, function(a, b) return a.idx < b.idx end)
        columns[col] = current
        for i = 1, #current do
            placed[current[i].guid] = true
            remaining[current[i].guid] = nil
        end
        col = col + 1
        if col > 200 then break end
    end

    node_positions = {}
    local max_rows = 1
    for ci = 0, col - 1 do
        local cl = columns[ci] or {}
        if #cl > max_rows then max_rows = #cl end
        for ri = 1, #cl do
            node_positions[cl[ri].guid] = { x = ci * COL_W + 40, y = (ri - 1) * ROW_H + 40 }
        end
    end
    if master_entry then
        local mx = col * COL_W + 40
        local my = math.max(40, ((max_rows - 1) * ROW_H) * 0.5 + 40)
        node_positions[MASTER_GUID] = { x = mx, y = my }
    end
    canvas_offset_x = 0
    canvas_offset_y = 0
    canvas_zoom = 1.0
    layout_dirty = true
end

local function EnsurePositions(tracks)
    local need_layout = false
    if next(node_positions) == nil then need_layout = true end
    if pending_auto_layout then need_layout = true; pending_auto_layout = false end
    if need_layout then
        AutoLayout(tracks)
        return
    end
    local max_x = 0
    for _, p in pairs(node_positions) do if p.x > max_x then max_x = p.x end end
    local next_y = 40
    for i = 1, #tracks do
        local g = tracks[i].guid
        if not node_positions[g] then
            node_positions[g] = { x = max_x + COL_W, y = next_y }
            next_y = next_y + ROW_H
            layout_dirty = true
        end
    end
end

local function GetSendIndexLocal(src, dst)
    local n = r.GetTrackNumSends(src, 0)
    for i = 0, n - 1 do
        local d = r.GetTrackSendInfo_Value(src, 0, i, "P_DESTTRACK")
        if d == dst then return i end
    end
    return -1
end

local function ModeColors(mode, muted)
    if muted then return 0x666666AA, 0x888888FF end
    if mode == 1 then return 0xB070D0FF, 0xC890E0FF end
    if mode == 3 then return 0xDDA050FF, 0xF0C070FF end
    return 0x4FB0C8FF, 0x70D0E0FF
end

local function PointSegDist(px, py, ax, ay, bx, by)
    local dx, dy = bx - ax, by - ay
    local len2 = dx * dx + dy * dy
    if len2 < 0.0001 then
        local ddx, ddy = px - ax, py - ay
        return math.sqrt(ddx * ddx + ddy * ddy)
    end
    local t = ((px - ax) * dx + (py - ay) * dy) / len2
    if t < 0 then t = 0 elseif t > 1 then t = 1 end
    local cx, cy = ax + t * dx, ay + t * dy
    local ex, ey = px - cx, py - cy
    return math.sqrt(ex * ex + ey * ey)
end

local function BezierPoint(t, x0, y0, x1, y1, x2, y2, x3, y3)
    local u = 1 - t
    local b0 = u * u * u
    local b1 = 3 * u * u * t
    local b2 = 3 * u * t * t
    local b3 = t * t * t
    return b0 * x0 + b1 * x1 + b2 * x2 + b3 * x3,
           b0 * y0 + b1 * y1 + b2 * y2 + b3 * y3
end

local function BezierHit(mx, my, x0, y0, x1, y1, x2, y2, x3, y3, threshold)
    local prev_x, prev_y = x0, y0
    local steps = 16
    for i = 1, steps do
        local t = i / steps
        local nx, ny = BezierPoint(t, x0, y0, x1, y1, x2, y2, x3, y3)
        if PointSegDist(mx, my, prev_x, prev_y, nx, ny) <= threshold then
            return true
        end
        prev_x, prev_y = nx, ny
    end
    return false
end

local function TruncateText(ctx, s, max_w)
    if max_w <= 0 then return "" end
    local w = r.ImGui_CalcTextSize(ctx, s)
    if w <= max_w then return s end
    local lo, hi = 1, #s
    while lo < hi do
        local mid = (lo + hi) // 2
        local cand = s:sub(1, mid) .. "..."
        if r.ImGui_CalcTextSize(ctx, cand) <= max_w then lo = mid + 1 else hi = mid end
    end
    return s:sub(1, math.max(0, lo - 1)) .. "..."
end

local function RenderRightClickPopup()
    local ctx = GetCtx()
    if not right_click_send then return end
    if r.ImGui_BeginPopup(ctx, "PatchbaySendPopup") then
        local s = right_click_send
        local src = s.src
        local dst = s.dst
        if s.is_main then
            if r.GetMediaTrackInfo_Value(src, "B_MAINSEND") ~= 1 then
                r.ImGui_TextDisabled(ctx, "Main send no longer active.")
                if r.ImGui_Button(ctx, "Close") then r.ImGui_CloseCurrentPopup(ctx); right_click_send = nil end
                r.ImGui_EndPopup(ctx)
                return
            end
            local _, sname = r.GetTrackName(src)
            r.ImGui_Text(ctx, sname .. " \xE2\x86\x92 MASTER")
            r.ImGui_Separator(ctx)
            local vol = r.GetMediaTrackInfo_Value(src, "D_VOL")
            local vol_db = vol > 0 and (20 * math.log(vol, 10)) or -150
            r.ImGui_PushItemWidth(ctx, 200)
            local cv, ndb = r.ImGui_SliderDouble(ctx, "Vol", vol_db, -60, 12, "%.1f dB")
            if cv then
                local nv = math.exp(ndb * math.log(10) / 20)
                r.SetMediaTrackInfo_Value(src, "D_VOL", nv)
            end
            local pan = r.GetMediaTrackInfo_Value(src, "D_PAN")
            local cp, np = r.ImGui_SliderDouble(ctx, "Pan", pan, -1, 1, "%.2f")
            if cp then r.SetMediaTrackInfo_Value(src, "D_PAN", np) end
            r.ImGui_PopItemWidth(ctx)
            r.ImGui_TextDisabled(ctx, "Main send is post-fader.")
            r.ImGui_Separator(ctx)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x802020FF)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0xA03030FF)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0x601010FF)
            if r.ImGui_Button(ctx, "Disable main send") then
                r.Undo_BeginBlock()
                r.SetMediaTrackInfo_Value(src, "B_MAINSEND", 0)
                r.Undo_EndBlock("Patchbay: disable main send", -1)
                r.ImGui_CloseCurrentPopup(ctx)
                right_click_send = nil
            end
            r.ImGui_PopStyleColor(ctx, 3)
            r.ImGui_EndPopup(ctx)
            return
        end
        local idx = GetSendIndexLocal(src, dst)
        if idx < 0 then
            r.ImGui_TextDisabled(ctx, "Connection no longer exists.")
            if r.ImGui_Button(ctx, "Close") then r.ImGui_CloseCurrentPopup(ctx); right_click_send = nil end
            r.ImGui_EndPopup(ctx)
            return
        end
        local _, sname = r.GetTrackName(src)
        local _, dname = r.GetTrackName(dst)
        r.ImGui_Text(ctx, sname .. " \xE2\x86\x92 " .. dname)
        r.ImGui_Separator(ctx)

        local vol = r.GetTrackSendInfo_Value(src, 0, idx, "D_VOL")
        local vol_db = vol > 0 and (20 * math.log(vol, 10)) or -150
        r.ImGui_PushItemWidth(ctx, 200)
        local cv, ndb = r.ImGui_SliderDouble(ctx, "Vol", vol_db, -60, 12, "%.1f dB")
        if cv then
            local nv = math.exp(ndb * math.log(10) / 20)
            r.SetTrackSendInfo_Value(src, 0, idx, "D_VOL", nv)
        end
        local pan = r.GetTrackSendInfo_Value(src, 0, idx, "D_PAN")
        local cp, np = r.ImGui_SliderDouble(ctx, "Pan", pan, -1, 1, "%.2f")
        if cp then r.SetTrackSendInfo_Value(src, 0, idx, "D_PAN", np) end
        r.ImGui_PopItemWidth(ctx)

        local mute = r.GetTrackSendInfo_Value(src, 0, idx, "B_MUTE") == 1
        local cm, vm = r.ImGui_Checkbox(ctx, "Mute", mute)
        if cm then r.SetTrackSendInfo_Value(src, 0, idx, "B_MUTE", vm and 1 or 0) end
        r.ImGui_SameLine(ctx)
        local phase = r.GetTrackSendInfo_Value(src, 0, idx, "B_PHASE") == 1
        local cph, vph = r.ImGui_Checkbox(ctx, "Phase", phase)
        if cph then r.SetTrackSendInfo_Value(src, 0, idx, "B_PHASE", vph and 1 or 0) end
        r.ImGui_SameLine(ctx)
        local mono = r.GetTrackSendInfo_Value(src, 0, idx, "B_MONO") == 1
        local cmo, vmo = r.ImGui_Checkbox(ctx, "Mono", mono)
        if cmo then r.SetTrackSendInfo_Value(src, 0, idx, "B_MONO", vmo and 1 or 0) end

        local mode = r.GetTrackSendInfo_Value(src, 0, idx, "I_SENDMODE")
        local mode_names = { "Post-Fader", "Pre-Fader (Post-FX)", "Pre-FX" }
        local mode_values = { 0, 3, 1 }
        local label = "Post-Fader"
        for k = 1, #mode_values do if mode_values[k] == mode then label = mode_names[k]; break end end
        r.ImGui_PushItemWidth(ctx, 200)
        if r.ImGui_BeginCombo(ctx, "Mode", label) then
            for k = 1, #mode_names do
                if r.ImGui_Selectable(ctx, mode_names[k], mode == mode_values[k]) then
                    r.SetTrackSendInfo_Value(src, 0, idx, "I_SENDMODE", mode_values[k])
                end
            end
            r.ImGui_EndCombo(ctx)
        end
        r.ImGui_PopItemWidth(ctx)

        r.ImGui_Separator(ctx)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x802020FF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0xA03030FF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0x601010FF)
        if r.ImGui_Button(ctx, "Delete connection") then
            r.RemoveTrackSend(src, 0, idx)
            r.ImGui_CloseCurrentPopup(ctx)
            right_click_send = nil
        end
        r.ImGui_PopStyleColor(ctx, 3)

        r.ImGui_EndPopup(ctx)
    else
        right_click_send = nil
    end
end

local function RenderFXListPopup()
    local ctx = GetCtx()
    if not fx_popup_track then return end
    if not r.ValidatePtr(fx_popup_track, "MediaTrack*") then
        fx_popup_track = nil
        return
    end
    if r.ImGui_BeginPopup(ctx, "PatchbayFXListPopup") then
        local tr = fx_popup_track
        local _, tname = r.GetTrackName(tr)
        local tnum = math.floor(r.GetMediaTrackInfo_Value(tr, "IP_TRACKNUMBER") or 0)
        r.ImGui_Text(ctx, string.format("#%d  %s", tnum, tname))
        r.ImGui_Separator(ctx)
        local count = r.TrackFX_GetCount(tr)
        if count == 0 then
            r.ImGui_TextDisabled(ctx, "No FX on this track.")
        else
            for i = 0, count - 1 do
                local _, fxname = r.TrackFX_GetFXName(tr, i, "")
                local enabled = r.TrackFX_GetEnabled(tr, i)
                local offline = r.TrackFX_GetOffline(tr, i)
                local floating = r.TrackFX_GetFloatingWindow(tr, i) ~= nil
                local prefix = floating and "* " or "  "
                local suffix = ""
                if not enabled then suffix = suffix .. "  [bypass]" end
                if offline then suffix = suffix .. "  [offline]" end
                local label = string.format("%s%d: %s%s", prefix, i + 1, fxname or "", suffix)
                if r.ImGui_Selectable(ctx, label) then
                    if floating then
                        r.TrackFX_Show(tr, i, 2)
                    else
                        r.TrackFX_Show(tr, i, 3)
                    end
                    r.ImGui_CloseCurrentPopup(ctx)
                end
            end
        end
        r.ImGui_Separator(ctx)
        if r.ImGui_Selectable(ctx, "Open FX Chain") then
            r.TrackFX_Show(tr, 0, 1)
            r.ImGui_CloseCurrentPopup(ctx)
        end
        r.ImGui_EndPopup(ctx)
    else
        fx_popup_track = nil
    end
end

function ShowRoutingPatchbay()
    local ctx = GetCtx()
    DrawRoutingFilterBar(false)

    local proj_key = GetCurrentProjectKey()
    if proj_key ~= layout_loaded_project then
        if layout_loaded_project ~= nil and layout_dirty then SaveLayout() end
        layout_loaded_project = proj_key
        LoadLayout()
    end

    if r.ImGui_Button(ctx, "Auto Layout") then
        pending_auto_layout = true
        layout_dirty = true
    end
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Re-run automatic layout") end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Center View") then
        pending_center_view = true
    end
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Pan canvas so all nodes are centered in view") end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "-") then
        canvas_zoom = math.max(MIN_ZOOM, canvas_zoom / 1.2)
        layout_dirty = true
    end
    r.ImGui_SameLine(ctx)
    r.ImGui_Text(ctx, string.format("%d%%", math.floor(canvas_zoom * 100 + 0.5)))
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "+") then
        canvas_zoom = math.min(MAX_ZOOM, canvas_zoom * 1.2)
        layout_dirty = true
    end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "1:1") then
        canvas_zoom = 1.0
        layout_dirty = true
    end
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Reset zoom to 100%%") end
    r.ImGui_SameLine(ctx)
    do
        local cfg = GetConfig()
        local show_master = cfg.patchbay_show_master ~= false
        local changed, new_val = r.ImGui_Checkbox(ctx, "Show Master", show_master)
        if changed then
            cfg.patchbay_show_master = new_val
            if _G.SaveConfig then _G.SaveConfig() end
        end
    end
    local flags = r.ImGui_WindowFlags_NoScrollbar() | r.ImGui_WindowFlags_NoScrollWithMouse()
    local hint_h = 22
    if not r.ImGui_BeginChild(ctx, "PatchbayCanvas", 0, -hint_h, 1, flags) then
        r.ImGui_EndChild(ctx)
        return
    end

    local draw_list = r.ImGui_GetWindowDrawList(ctx)
    local origin_x, origin_y = r.ImGui_GetCursorScreenPos(ctx)
    local avail_w, avail_h = r.ImGui_GetContentRegionAvail(ctx)
    if avail_w < 50 then avail_w = 50 end
    if avail_h < 50 then avail_h = 50 end

    r.ImGui_DrawList_AddRectFilled(draw_list, origin_x, origin_y, origin_x + avail_w, origin_y + avail_h, 0x1A1A1AFF)

    local g_step = GRID
    local gx0 = origin_x + ((canvas_offset_x % g_step) + g_step) % g_step
    local gy0 = origin_y + ((canvas_offset_y % g_step) + g_step) % g_step
    local x = gx0
    while x < origin_x + avail_w do
        local y = gy0
        while y < origin_y + avail_h do
            r.ImGui_DrawList_AddRectFilled(draw_list, x - 1, y - 1, x + 1, y + 1, 0x2A2A2AFF)
            y = y + g_step
        end
        x = x + g_step
    end

    r.ImGui_SetCursorScreenPos(ctx, origin_x, origin_y)
    if r.ImGui_SetNextItemAllowOverlap then r.ImGui_SetNextItemAllowOverlap(ctx) end
    r.ImGui_InvisibleButton(ctx, "##patchbay_bg", avail_w, avail_h)
    local bg_active = r.ImGui_IsItemActive(ctx)
    local bg_hovered = r.ImGui_IsItemHovered(ctx)

    if bg_active and dragging_node_guid == nil and pending_connection == nil then
        local dx, dy = r.ImGui_GetMouseDragDelta(ctx, 0, 0, 0)
        if dx ~= 0 or dy ~= 0 then
            canvas_offset_x = canvas_offset_x + dx
            canvas_offset_y = canvas_offset_y + dy
            r.ImGui_ResetMouseDragDelta(ctx, 0)
            layout_dirty = true
        end
    end

    if r.ImGui_IsWindowHovered(ctx) and r.ImGui_IsMouseDragging(ctx, 2) then
        local dx, dy = r.ImGui_GetMouseDragDelta(ctx, 2, 0, 0)
        if dx ~= 0 or dy ~= 0 then
            canvas_offset_x = canvas_offset_x + dx
            canvas_offset_y = canvas_offset_y + dy
            r.ImGui_ResetMouseDragDelta(ctx, 2)
            layout_dirty = true
        end
    end

    if r.ImGui_IsWindowHovered(ctx) then
        local wheel = r.ImGui_GetMouseWheel(ctx)
        if wheel ~= 0 then
            local mxw, myw = r.ImGui_GetMousePos(ctx)
            local wx = (mxw - origin_x - canvas_offset_x) / canvas_zoom
            local wy = (myw - origin_y - canvas_offset_y) / canvas_zoom
            local factor = (wheel > 0) and 1.1 or (1 / 1.1)
            local new_zoom = math.max(MIN_ZOOM, math.min(MAX_ZOOM, canvas_zoom * factor))
            if new_zoom ~= canvas_zoom then
                canvas_zoom = new_zoom
                canvas_offset_x = mxw - origin_x - wx * canvas_zoom
                canvas_offset_y = myw - origin_y - wy * canvas_zoom
                layout_dirty = true
            end
        end
    end

    local tracks = CollectVisibleTracks()
    if #tracks == 0 then
        r.ImGui_DrawList_AddText(draw_list, origin_x + 12, origin_y + 12, 0xAAAAAAFF, "No tracks match filter.")
        r.ImGui_EndChild(ctx)
        RenderRightClickPopup()
        return
    end

    EnsurePositions(tracks)

    if pending_center_view then
        pending_center_view = false
        local min_x, min_y, max_x, max_y
        for i = 1, #tracks do
            local p = node_positions[tracks[i].guid]
            if p then
                local x1, y1 = p.x, p.y
                local x2, y2 = p.x + NODE_W, p.y + NODE_H
                if not min_x then
                    min_x, min_y, max_x, max_y = x1, y1, x2, y2
                else
                    if x1 < min_x then min_x = x1 end
                    if y1 < min_y then min_y = y1 end
                    if x2 > max_x then max_x = x2 end
                    if y2 > max_y then max_y = y2 end
                end
            end
        end
        if min_x then
            local bw = (max_x - min_x) * canvas_zoom
            local bh = (max_y - min_y) * canvas_zoom
            canvas_offset_x = (avail_w - bw) * 0.5 - min_x * canvas_zoom
            canvas_offset_y = (avail_h - bh) * 0.5 - min_y * canvas_zoom
            layout_dirty = true
        end
    end

    local guid_to = {}
    for i = 1, #tracks do guid_to[tracks[i].guid] = tracks[i] end

    local function NodeRect(g)
        local p = node_positions[g]
        if not p then return nil end
        local x1 = origin_x + canvas_offset_x + p.x * canvas_zoom
        local y1 = origin_y + canvas_offset_y + p.y * canvas_zoom
        return x1, y1, x1 + NODE_W * canvas_zoom, y1 + NODE_H * canvas_zoom
    end

    local function PinPos(g, side)
        local x1, y1, x2, y2 = NodeRect(g)
        if not x1 then return nil end
        if side == "out" then
            return x2, (y1 + y2) * 0.5
        else
            return x1, (y1 + y2) * 0.5
        end
    end

    hovered_input_guid = nil
    local mx, my = r.ImGui_GetMousePos(ctx)
    local cables = {}
    local master_in_view = guid_to[MASTER_GUID] ~= nil
    local master_track = master_in_view and guid_to[MASTER_GUID].track or nil
    for i = 1, #tracks do
        local src = tracks[i].track
        local sg = tracks[i].guid
        if not tracks[i].is_master then
            local nsnd = r.GetTrackNumSends(src, 0)
            for k = 0, nsnd - 1 do
                local dst = r.GetTrackSendInfo_Value(src, 0, k, "P_DESTTRACK")
                if dst and r.ValidatePtr(dst, "MediaTrack*") then
                    local dg = r.GetTrackGUID(dst)
                    if guid_to[dg] then
                        cables[#cables + 1] = { src = src, dst = dst, sg = sg, dg = dg, idx = k }
                    end
                end
            end
            if master_in_view and r.GetMediaTrackInfo_Value(src, "B_MAINSEND") == 1 then
                cables[#cables + 1] = { src = src, dst = master_track, sg = sg, dg = MASTER_GUID, idx = -1, is_main = true }
            end
        end
    end

    local hovered_cable = nil
    local cp_dist = 80 * canvas_zoom
    for ci = 1, #cables do
        local c = cables[ci]
        local sx, sy = PinPos(c.sg, "out")
        local dx, dy = PinPos(c.dg, "in")
        if sx and dx then
            local cx1 = sx + cp_dist
            local cy1 = sy
            local cx2 = dx - cp_dist
            local cy2 = dy
            if not hovered_cable and BezierHit(mx, my, sx, sy, cx1, cy1, cx2, cy2, dx, dy, 6) then
                hovered_cable = c
            end
        end
    end

    for ci = 1, #cables do
        local c = cables[ci]
        local sx, sy = PinPos(c.sg, "out")
        local dx, dy = PinPos(c.dg, "in")
        if sx and dx then
            local mode, muted, phase, vol
            if c.is_main then
                mode = 0
                muted = false
                phase = false
                vol = r.GetMediaTrackInfo_Value(c.src, "D_VOL")
            else
                mode = r.GetTrackSendInfo_Value(c.src, 0, c.idx, "I_SENDMODE")
                muted = r.GetTrackSendInfo_Value(c.src, 0, c.idx, "B_MUTE") == 1
                phase = r.GetTrackSendInfo_Value(c.src, 0, c.idx, "B_PHASE") == 1
                vol = r.GetTrackSendInfo_Value(c.src, 0, c.idx, "D_VOL")
            end
            local thickness = 1.5 + math.min(2.5, math.max(0, (vol - 0.5)) * 1.5)
            if hovered_cable == c then thickness = thickness + 1 end
            local col, hcol = ModeColors(mode, muted)
            local use_col = (hovered_cable == c) and hcol or col
            r.ImGui_DrawList_AddBezierCubic(draw_list, sx, sy, sx + cp_dist, sy, dx - cp_dist, dy, dx, dy, use_col, thickness)
            if phase and not muted then
                r.ImGui_DrawList_AddBezierCubic(draw_list, sx, sy, sx + cp_dist, sy, dx - cp_dist, dy, dx, dy, 0xFF4040FF, 1)
            end
        end
    end

    local request_open_popup = false
    if hovered_cable then
        local _, sname = r.GetTrackName(hovered_cable.src)
        local dname
        local mlabel
        local vol
        if hovered_cable.is_main then
            dname = "MASTER"
            mlabel = "Main send (post-fader)"
            vol = r.GetMediaTrackInfo_Value(hovered_cable.src, "D_VOL")
        else
            local _, dn = r.GetTrackName(hovered_cable.dst)
            dname = dn
            local mode = r.GetTrackSendInfo_Value(hovered_cable.src, 0, hovered_cable.idx, "I_SENDMODE")
            vol = r.GetTrackSendInfo_Value(hovered_cable.src, 0, hovered_cable.idx, "D_VOL")
            mlabel = "Post-Fader"
            if mode == 1 then mlabel = "Pre-FX" elseif mode == 3 then mlabel = "Pre-Fader (Post-FX)" end
        end
        local vol_db = vol > 0 and (20 * math.log(vol, 10)) or -150
        r.ImGui_SetTooltip(ctx, string.format("%s \xE2\x86\x92 %s\n%s, %.1f dB", sname, dname, mlabel, vol_db))
        if r.ImGui_IsMouseClicked(ctx, 1) then
            right_click_send = { src = hovered_cable.src, dst = hovered_cable.dst, is_main = hovered_cable.is_main }
            request_open_popup = true
        end
    end

    if not hovered_cable and bg_hovered and not pb_rubber_active and pending_connection == nil and r.ImGui_IsMouseClicked(ctx, 1) then
        local mods = r.ImGui_GetKeyMods and r.ImGui_GetKeyMods(ctx) or 0
        local mod_shift = r.ImGui_Mod_Shift and r.ImGui_Mod_Shift() or 0
        local shift_held = (mods & mod_shift) ~= 0
        if not shift_held then pb_selected_set = {} end
        pb_rubber_active = true
        pb_rubber_start_x, pb_rubber_start_y = r.ImGui_GetMousePos(ctx)
    end

    for i = 1, #tracks do
        local tr = tracks[i]
        local g = tr.guid
        local x1, y1, x2, y2 = NodeRect(g)
        if x1 then
            local is_selected = (_G.TRACK == tr.track)
            local is_master_node = tr.is_master
            local is_multi = pb_selected_set[g] == true

            local bar_col
            if is_master_node then
                bar_col = 0xD4AF37FF
            else
                local tcol = r.GetTrackColor(tr.track)
                local r8, g8, b8 = 96, 96, 96
                if tcol and tcol ~= 0 then r8, g8, b8 = r.ColorFromNative(tcol) end
                bar_col = ((r8 & 0xFF) << 24) | ((g8 & 0xFF) << 16) | ((b8 & 0xFF) << 8) | 0xFF
            end

            local body_col
            if is_master_node then
                body_col = is_selected and 0x3A3024FF or 0x2A2620FF
            else
                body_col = is_selected and 0x3A3F4AFF or (is_multi and 0x2A3340FF or 0x222428FF)
            end
            r.ImGui_DrawList_AddRectFilled(draw_list, x1, y1, x2, y2, body_col, 6)
            r.ImGui_DrawList_AddRectFilled(draw_list, x1, y1, x1 + 5, y2, bar_col, 6)
            local border
            if is_master_node then
                border = (is_selected and 0xFFD060FF) or (is_multi and 0xCCFF88FF) or 0x886633FF
            else
                border = (is_selected and 0x88BBFFFF) or (is_multi and 0xCCFF88FF) or 0x3A3A3AFF
            end
            r.ImGui_DrawList_AddRect(draw_list, x1, y1, x2, y2, border, 6, nil, (is_selected or is_multi) and 2 or 1)

            local label
            if is_master_node then
                label = "MASTER"
            else
                label = string.format("#%d  %s", tr.idx + 1, tr.name)
            end
            local trunc = TruncateText(ctx, label, NODE_W * canvas_zoom - 14)
            r.ImGui_DrawList_AddText(draw_list, x1 + 10, y1 + 6, is_master_node and 0xFFE090FF or 0xEEEEEEFF, trunc)

            local stats
            if is_master_node then
                local cnt = 0
                local n = r.CountTracks(0)
                for ti = 0, n - 1 do
                    local tt = r.GetTrack(0, ti)
                    if r.GetMediaTrackInfo_Value(tt, "B_MAINSEND") == 1 then cnt = cnt + 1 end
                end
                stats = string.format("%d main sends in", cnt)
            else
                local nrec = r.GetTrackNumSends(tr.track, -1)
                local nsnd = r.GetTrackNumSends(tr.track, 0)
                stats = string.format("%d in / %d out", nrec, nsnd)
            end
            local stats_max_w = (NODE_W * canvas_zoom) - 24
            if not is_master_node then stats_max_w = stats_max_w - (2 * (14 * canvas_zoom) + 10) end
            local stats_trunc = TruncateText(ctx, stats, stats_max_w)
            r.ImGui_DrawList_AddText(draw_list, x1 + 10, y2 - 18, 0xAAAAAAFF, stats_trunc)

            local in_x, in_y = PinPos(g, "in")
            local out_x, out_y = PinPos(g, "out")
            local pin_r = PIN_R * canvas_zoom
            if pin_r < 4 then pin_r = 4 end

            r.ImGui_PushID(ctx, "node_" .. g)

            r.ImGui_SetCursorScreenPos(ctx, x1, y1)
            if r.ImGui_SetNextItemAllowOverlap then r.ImGui_SetNextItemAllowOverlap(ctx) end
            r.ImGui_InvisibleButton(ctx, "##body", NODE_W * canvas_zoom, NODE_H * canvas_zoom)
            local body_active = r.ImGui_IsItemActive(ctx)
            local body_hovered = r.ImGui_IsItemHovered(ctx)
            if body_hovered and r.ImGui_IsMouseClicked(ctx, 1) then
                if is_master_node then
                    local nt = r.CountTracks(0)
                    for ti = 0, nt - 1 do
                        r.SetMediaTrackInfo_Value(r.GetTrack(0, ti), "I_SELECTED", 0)
                    end
                    r.SetMediaTrackInfo_Value(tr.track, "I_SELECTED", 1)
                    r.UpdateArrange()
                else
                    r.SetOnlyTrackSelected(tr.track)
                    if r.SetMixerScroll then r.SetMixerScroll(tr.track) end
                    r.UpdateArrange()
                end
            end
            if body_hovered and r.ImGui_IsMouseClicked(ctx, 0) then
                local pin_r_hit = PIN_R * canvas_zoom
                if pin_r_hit < 4 then pin_r_hit = 4 end
                local hit_r = pin_r_hit + 4
                local hit_out = nil
                for hi = 1, #tracks do
                    if not tracks[hi].is_master then
                        local ox, oy = PinPos(tracks[hi].guid, "out")
                        if ox then
                            local ddx = mx - ox
                            local ddy = my - oy
                            if ddx * ddx + ddy * ddy <= hit_r * hit_r then
                                hit_out = tracks[hi]
                                break
                            end
                        end
                    end
                end
                if hit_out then
                    pending_connection = { src = hit_out.track, src_guid = hit_out.guid }
                else
                    pb_press_guid = g
                    pb_press_dragged = false
                end
            end
            if body_active and pending_connection == nil then
                local ddx, ddy = r.ImGui_GetMouseDragDelta(ctx, 0, 0, 0)
                if ddx ~= 0 or ddy ~= 0 then
                    dragging_node_guid = g
                    pb_press_dragged = true
                    local dwx = ddx / canvas_zoom
                    local dwy = ddy / canvas_zoom
                    if pb_selected_set[g] then
                        for sg, _ in pairs(pb_selected_set) do
                            if node_positions[sg] then
                                node_positions[sg].x = node_positions[sg].x + dwx
                                node_positions[sg].y = node_positions[sg].y + dwy
                            end
                        end
                    else
                        node_positions[g].x = node_positions[g].x + dwx
                        node_positions[g].y = node_positions[g].y + dwy
                    end
                    r.ImGui_ResetMouseDragDelta(ctx, 0)
                    layout_dirty = true
                end
            end
            if pb_press_guid == g and r.ImGui_IsMouseReleased(ctx, 0) then
                if not pb_press_dragged and body_hovered and not is_master_node then
                    pb_open_fx_for = tr.track
                end
                pb_press_guid = nil
                pb_press_dragged = false
            end

            if not is_master_node then
                local btn_size = 14 * canvas_zoom
                if btn_size < 10 then btn_size = 10 end
                local btn_y1 = y2 - btn_size - 3
                local btn_y2 = btn_y1 + btn_size
                local s_x2 = x2 - 6
                local s_x1 = s_x2 - btn_size
                local m_x2 = s_x1 - 4
                local m_x1 = m_x2 - btn_size

                local mute_on = r.GetMediaTrackInfo_Value(tr.track, "B_MUTE") == 1
                local solo_on = r.GetMediaTrackInfo_Value(tr.track, "I_SOLO") ~= 0
                local m_col = mute_on and 0xCC3333FF or 0x4A4A4AFF
                local s_col = solo_on and 0xCCBB33FF or 0x4A4A4AFF
                r.ImGui_DrawList_AddRectFilled(draw_list, m_x1, btn_y1, m_x2, btn_y2, m_col, 3)
                r.ImGui_DrawList_AddRect(draw_list, m_x1, btn_y1, m_x2, btn_y2, 0x000000AA, 3)
                r.ImGui_DrawList_AddRectFilled(draw_list, s_x1, btn_y1, s_x2, btn_y2, s_col, 3)
                r.ImGui_DrawList_AddRect(draw_list, s_x1, btn_y1, s_x2, btn_y2, 0x000000AA, 3)
                local tw_m = r.ImGui_CalcTextSize(ctx, "M")
                local tw_s = r.ImGui_CalcTextSize(ctx, "S")
                r.ImGui_DrawList_AddText(draw_list, m_x1 + (btn_size - tw_m) * 0.5, btn_y1 + (btn_size - 12) * 0.5, 0xFFFFFFFF, "M")
                r.ImGui_DrawList_AddText(draw_list, s_x1 + (btn_size - tw_s) * 0.5, btn_y1 + (btn_size - 12) * 0.5, 0xFFFFFFFF, "S")

                if r.ImGui_SetNextItemAllowOverlap then r.ImGui_SetNextItemAllowOverlap(ctx) end
                r.ImGui_SetCursorScreenPos(ctx, m_x1, btn_y1)
                r.ImGui_InvisibleButton(ctx, "##mute_btn", btn_size, btn_size)
                if r.ImGui_IsItemClicked(ctx, 0) then
                    r.Undo_BeginBlock()
                    r.SetMediaTrackInfo_Value(tr.track, "B_MUTE", mute_on and 0 or 1)
                    r.Undo_EndBlock("Patchbay: toggle mute", -1)
                end

                if r.ImGui_SetNextItemAllowOverlap then r.ImGui_SetNextItemAllowOverlap(ctx) end
                r.ImGui_SetCursorScreenPos(ctx, s_x1, btn_y1)
                r.ImGui_InvisibleButton(ctx, "##solo_btn", btn_size, btn_size)
                if r.ImGui_IsItemClicked(ctx, 0) then
                    r.Undo_BeginBlock()
                    r.SetMediaTrackInfo_Value(tr.track, "I_SOLO", solo_on and 0 or 2)
                    r.Undo_EndBlock("Patchbay: toggle solo", -1)
                end
            end

            r.ImGui_PopID(ctx)
        end
    end

    for i = 1, #tracks do
        local tr = tracks[i]
        local g = tr.guid
        local x1, y1, x2, y2 = NodeRect(g)
        if x1 then
            local is_master_node = tr.is_master
            local in_x, in_y = PinPos(g, "in")
            local out_x, out_y = PinPos(g, "out")
            local pin_r = PIN_R * canvas_zoom
            if pin_r < 4 then pin_r = 4 end

            r.ImGui_DrawList_AddCircleFilled(draw_list, in_x, in_y, pin_r, 0x88CCFFFF)
            r.ImGui_DrawList_AddCircle(draw_list, in_x, in_y, pin_r, 0x000000FF, nil, 1)
            if not is_master_node then
                r.ImGui_DrawList_AddCircleFilled(draw_list, out_x, out_y, pin_r, 0xFFCC88FF)
                r.ImGui_DrawList_AddCircle(draw_list, out_x, out_y, pin_r, 0x000000FF, nil, 1)
            end

            r.ImGui_PushID(ctx, "pins_" .. g)

            r.ImGui_SetCursorScreenPos(ctx, in_x - pin_r, in_y - pin_r)
            r.ImGui_InvisibleButton(ctx, "##pin_in", pin_r * 2, pin_r * 2)
            if r.ImGui_IsItemHovered(ctx) then
                hovered_input_guid = g
                r.ImGui_DrawList_AddCircle(draw_list, in_x, in_y, pin_r + 2, 0xFFFFFFFF, nil, 2)
            end

            if not is_master_node then
                r.ImGui_SetCursorScreenPos(ctx, out_x - pin_r, out_y - pin_r)
                r.ImGui_InvisibleButton(ctx, "##pin_out", pin_r * 2, pin_r * 2)
                if r.ImGui_IsItemHovered(ctx) then
                    r.ImGui_DrawList_AddCircle(draw_list, out_x, out_y, pin_r + 2, 0xFFFFFFFF, nil, 2)
                end
                if r.ImGui_IsItemActive(ctx) then
                    if not pending_connection then
                        pending_connection = { src = tr.track, src_guid = g }
                    end
                end
            end

            r.ImGui_PopID(ctx)
        end
    end

    if pending_connection then
        local sx, sy = PinPos(pending_connection.src_guid, "out")
        do
            local pin_r = PIN_R * canvas_zoom
            if pin_r < 4 then pin_r = 4 end
            local hit_r = pin_r + 6
            local best_g = nil
            local best_d2 = hit_r * hit_r
            for i = 1, #tracks do
                local tg = tracks[i].guid
                if tg ~= pending_connection.src_guid then
                    local ix, iy = PinPos(tg, "in")
                    if ix then
                        local ddx = mx - ix
                        local ddy = my - iy
                        local d2 = ddx * ddx + ddy * ddy
                        if d2 <= best_d2 then
                            best_d2 = d2
                            best_g = tg
                        end
                    end
                end
            end
            if best_g then
                hovered_input_guid = best_g
                local hx, hy = PinPos(best_g, "in")
                if hx then
                    r.ImGui_DrawList_AddCircle(draw_list, hx, hy, pin_r + 2, 0xFFFFFFFF, nil, 2)
                end
            end
        end
        if sx then
            local target_x, target_y = mx, my
            local color = 0xFFCC88FF
            if hovered_input_guid and hovered_input_guid ~= pending_connection.src_guid then
                local hx, hy = PinPos(hovered_input_guid, "in")
                if hx then target_x, target_y = hx, hy; color = 0x88FF88FF end
            end
            r.ImGui_DrawList_AddBezierCubic(draw_list, sx, sy, sx + cp_dist, sy, target_x - cp_dist, target_y, target_x, target_y, color, 2)
        end
        if r.ImGui_IsMouseReleased(ctx, 0) then
            if hovered_input_guid and hovered_input_guid ~= pending_connection.src_guid then
                if hovered_input_guid == MASTER_GUID then
                    if r.GetMediaTrackInfo_Value(pending_connection.src, "B_MAINSEND") ~= 1 then
                        r.Undo_BeginBlock()
                        r.SetMediaTrackInfo_Value(pending_connection.src, "B_MAINSEND", 1)
                        r.Undo_EndBlock("Patchbay: enable main send", -1)
                    end
                else
                    local dst_track = nil
                    for i = 1, #tracks do
                        if tracks[i].guid == hovered_input_guid then dst_track = tracks[i].track; break end
                    end
                    if dst_track and GetSendIndexLocal(pending_connection.src, dst_track) < 0 then
                        r.Undo_BeginBlock()
                        r.CreateTrackSend(pending_connection.src, dst_track)
                        r.Undo_EndBlock("Patchbay: create send", -1)
                    end
                end
            end
            pending_connection = nil
        end
    end

    if pb_rubber_active then
        local cmx, cmy = r.ImGui_GetMousePos(ctx)
        local rx1 = math.min(pb_rubber_start_x, cmx)
        local ry1 = math.min(pb_rubber_start_y, cmy)
        local rx2 = math.max(pb_rubber_start_x, cmx)
        local ry2 = math.max(pb_rubber_start_y, cmy)
        r.ImGui_DrawList_AddRectFilled(draw_list, rx1, ry1, rx2, ry2, 0x88BBFF22)
        r.ImGui_DrawList_AddRect(draw_list, rx1, ry1, rx2, ry2, 0x88BBFFCC, 0, nil, 1)
        if r.ImGui_IsMouseReleased(ctx, 1) then
            for i = 1, #tracks do
                local g2 = tracks[i].guid
                local nx1, ny1, nx2, ny2 = NodeRect(g2)
                if nx1 and not (nx2 < rx1 or nx1 > rx2 or ny2 < ry1 or ny1 > ry2) then
                    pb_selected_set[g2] = true
                end
            end
            pb_rubber_active = false
        end
    end

    if r.ImGui_IsMouseReleased(ctx, 0) then
        if dragging_node_guid then
            dragging_node_guid = nil
            SaveLayout()
        end
    end

    if layout_dirty and (r.time_precise() - last_save_time) > 2.0 and dragging_node_guid == nil then
        SaveLayout()
    end

    r.ImGui_EndChild(ctx)
    do
        local hint = "Drag node = move  |  Drag pin = connect  |  Left-drag empty = pan  |  Right-drag empty = select (Shift = add)  |  Wheel = zoom  |  Right-click cable = options"
        local tw = r.ImGui_CalcTextSize(ctx, hint)
        local fw = r.ImGui_GetContentRegionAvail(ctx)
        local off = (fw - tw) * 0.5
        if off < 0 then off = 0 end
        local cx, cy = r.ImGui_GetCursorPos(ctx)
        r.ImGui_SetCursorPos(ctx, cx + off, cy)
        r.ImGui_TextDisabled(ctx, hint)
    end
    if request_open_popup then
        r.ImGui_OpenPopup(ctx, "PatchbaySendPopup")
    end
    if pb_open_fx_for and r.ValidatePtr(pb_open_fx_for, "MediaTrack*") then
        fx_popup_track = pb_open_fx_for
        r.ImGui_OpenPopup(ctx, "PatchbayFXListPopup")
    end
    pb_open_fx_for = nil
    RenderRightClickPopup()
    RenderFXListPopup()
end
