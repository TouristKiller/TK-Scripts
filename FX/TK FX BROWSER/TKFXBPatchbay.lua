local r = reaper

local PB = {}

local NODE_W_DEFAULT = 180
local NODE_H = 60
local NODE_H_COLLAPSED = 30
local PIN_R = 6
local ROW_H = 80
local GRID = 40
local MASTER_GUID = "__MASTER__"

local function IsMasterEntry(tr) return tr and tr.is_master end
local GetSendIndexLocal
local GetCtx
local GetConfig
local GetLockMode
local IsLayoutLockedCfg
local IsAllLockedCfg

local node_positions = {}
local pinned_nodes = {}
local collapsed_nodes = {}
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
local pending_fit_view = false
local pb_press_guid = nil
local pb_press_dragged = false
local node_popup_track = nil
local node_popup_guid = nil
local delete_selected_targets = nil
local pb_selected_set = {}
local pb_rubber_active = false
local pb_rubber_start_x = 0
local pb_rubber_start_y = 0
local pb_rubber_additive = false
local snapshot_names = {}
local snapshot_map = {}
local snapshot_selected_name = nil
local snapshot_name_input = ""
local route_audit_issues = {}
local route_audit_error_count = 0
local route_audit_warn_count = 0
local route_audit_cable_marks = {}
local route_audit_visual_active = false
local bulk_route_target_guid = nil
local bulk_route_create_missing = true
local bulk_route_mode = 0
local bulk_route_vol_db = 0.0
local bulk_route_pan = 0.0
local bulk_route_mute = false
local bulk_route_phase = false
local bulk_route_mono = false
local popup_auto_x = nil
local popup_auto_y = nil
local popup_view_x = nil
local popup_view_y = nil
local popup_route_x = nil
local popup_route_y = nil
local popup_actions_x = nil
local popup_actions_y = nil
local open_toolbar_popup_id = nil

local ROUTE_FILTER_ORDER = { "all", "post-fader", "pre-fader", "pre-fx", "muted" }
local ROUTE_FILTER_LABELS = {
    ["all"] = "All",
    ["post-fader"] = "Post-Fader",
    ["pre-fader"] = "Pre-Fader",
    ["pre-fx"] = "Pre-FX",
    ["muted"] = "Muted only"
}

local LAYOUT_PRESET_ORDER = { "compact", "hybrid", "wide" }
local LAYOUT_PRESET_LABELS = {
    compact = "Compact",
    hybrid = "Standard",
    wide = "Wide"
}
local LAYOUT_PRESET_GAPS = {
    compact = { col = 36, row = 64 },
    hybrid = { col = 60, row = 80 },
    wide = { col = 96, row = 108 }
}

local function NextRouteFilter(v)
    local cur = v or "all"
    for i = 1, #ROUTE_FILTER_ORDER do
        if ROUTE_FILTER_ORDER[i] == cur then
            return ROUTE_FILTER_ORDER[(i % #ROUTE_FILTER_ORDER) + 1]
        end
    end
    return "all"
end

local function RouteFilterLabel(v)
    return ROUTE_FILTER_LABELS[v or "all"] or "All"
end

local function TextMenuButton(ctx, id, label, w)
    local h = r.ImGui_GetFrameHeight(ctx)
    local clicked = r.ImGui_InvisibleButton(ctx, id, w, h)
    local draw_list = r.ImGui_GetWindowDrawList(ctx)
    local x1, y1 = r.ImGui_GetItemRectMin(ctx)
    local x2, y2 = r.ImGui_GetItemRectMax(ctx)
    local hovered = r.ImGui_IsItemHovered(ctx)
    local active = r.ImGui_IsItemActive(ctx)
    local text_col = _G.patchbay_toolbar_text_col or 0xD0D0D0FF
    if hovered then text_col = _G.patchbay_toolbar_text_hover_col or 0x7AA2F7FF end
    if active then text_col = _G.patchbay_toolbar_text_active_col or 0x9CB6F9FF end
    local text_h = r.ImGui_GetTextLineHeight(ctx)
    local tx = x1 + 4
    local ty = y1 + ((y2 - y1 - text_h) * 0.5)
    r.ImGui_DrawList_AddText(draw_list, tx, ty, text_col, label)
    return clicked
end

local function ToolbarMenuButton(ctx, id, label, w, popup_id)
    local clicked = TextMenuButton(ctx, id, label, w)
    if not clicked
        and open_toolbar_popup_id
        and open_toolbar_popup_id ~= popup_id
        and r.ImGui_IsMouseClicked
        and r.ImGui_GetMousePos
        and r.ImGui_GetItemRectMin
        and r.ImGui_GetItemRectMax
        and r.ImGui_IsMouseClicked(ctx, 0)
    then
        local x1, y1 = r.ImGui_GetItemRectMin(ctx)
        local x2, y2 = r.ImGui_GetItemRectMax(ctx)
        local mx, my = r.ImGui_GetMousePos(ctx)
        if mx >= x1 and mx <= x2 and my >= y1 and my <= y2 then
            clicked = true
        end
    end
    return clicked
end

local function OpenToolbarPopup(ctx, popup_id)
    if open_toolbar_popup_id and open_toolbar_popup_id ~= popup_id and r.ImGui_CloseCurrentPopup then
        r.ImGui_CloseCurrentPopup(ctx)
    end
    r.ImGui_OpenPopup(ctx, popup_id)
    open_toolbar_popup_id = popup_id
end

function _G.PatchbayZoomStep(factor)
    if not factor then return end
    canvas_zoom = math.max(MIN_ZOOM, math.min(MAX_ZOOM, canvas_zoom * factor))
    layout_dirty = true
end

function _G.PatchbayZoomReset()
    canvas_zoom = 1.0
    pending_center_view = true
    layout_dirty = true
end

function _G.PatchbayZoomFit()
    pending_fit_view = true
    layout_dirty = true
end

function _G.PatchbayZoomPercent()
    return math.floor(canvas_zoom * 100 + 0.5)
end

local function AddPatchbayTrack()
    if IsAllLockedCfg(GetConfig()) then return end
    local insert_idx = r.CountTracks(0)
    if _G.TRACK and r.ValidatePtr(_G.TRACK, "MediaTrack*") and _G.TRACK ~= r.GetMasterTrack(0) then
        local tnum = math.floor(r.GetMediaTrackInfo_Value(_G.TRACK, "IP_TRACKNUMBER") or 0)
        if tnum > 0 then insert_idx = tnum end
    end
    r.Undo_BeginBlock()
    r.InsertTrackAtIndex(insert_idx, true)
    local tr = r.GetTrack(0, insert_idx)
    if tr and r.ValidatePtr(tr, "MediaTrack*") then
        r.SetOnlyTrackSelected(tr)
        _G.TRACK = tr
    end
    r.TrackList_AdjustWindows(false)
    r.UpdateArrange()
    r.Undo_EndBlock("Patchbay: add track", -1)
    layout_dirty = true
end

local function DeletePatchbayTrack(tr, guid)
    if IsAllLockedCfg(GetConfig()) then return end
    if not tr or not r.ValidatePtr(tr, "MediaTrack*") then return end
    if tr == r.GetMasterTrack(0) then return end
    r.Undo_BeginBlock()
    r.DeleteTrack(tr)
    r.TrackList_AdjustWindows(false)
    r.UpdateArrange()
    r.Undo_EndBlock("Patchbay: delete track", -1)
    if guid then
        pb_selected_set[guid] = nil
        node_positions[guid] = nil
        pinned_nodes[guid] = nil
        collapsed_nodes[guid] = nil
    end
    _G.TRACK = r.GetSelectedTrack(0, 0)
    layout_dirty = true
end

local function GetSelectedPatchbayTracks()
    local out = {}
    local n = r.CountTracks(0)
    for i = 0, n - 1 do
        local tr = r.GetTrack(0, i)
        local g = r.GetTrackGUID(tr)
        if pb_selected_set[g] and r.ValidatePtr(tr, "MediaTrack*") then
            local _, name = r.GetTrackName(tr)
            out[#out + 1] = { track = tr, guid = g, name = name }
        end
    end
    return out
end

local function BatchSetMute(selected_tracks, muted)
    if IsAllLockedCfg(GetConfig()) then return end
    if not selected_tracks or #selected_tracks == 0 then return end
    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)
    for i = 1, #selected_tracks do
        r.SetMediaTrackInfo_Value(selected_tracks[i].track, "B_MUTE", muted and 1 or 0)
    end
    r.PreventUIRefresh(-1)
    r.TrackList_AdjustWindows(false)
    r.UpdateArrange()
    r.Undo_EndBlock(muted and "Patchbay: mute selected tracks" or "Patchbay: unmute selected tracks", -1)
end

local function BatchSetSolo(selected_tracks, solo_on)
    if IsAllLockedCfg(GetConfig()) then return end
    if not selected_tracks or #selected_tracks == 0 then return end
    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)
    for i = 1, #selected_tracks do
        r.SetMediaTrackInfo_Value(selected_tracks[i].track, "I_SOLO", solo_on and 2 or 0)
    end
    r.PreventUIRefresh(-1)
    r.TrackList_AdjustWindows(false)
    r.UpdateArrange()
    r.Undo_EndBlock(solo_on and "Patchbay: solo selected tracks" or "Patchbay: unsolo selected tracks", -1)
end

local function BatchSetPinned(selected_tracks, pin_on)
    if IsLayoutLockedCfg(GetConfig()) then return end
    if not selected_tracks or #selected_tracks == 0 then return end
    for i = 1, #selected_tracks do
        local g = selected_tracks[i].guid
        if pin_on then
            pinned_nodes[g] = true
        else
            pinned_nodes[g] = nil
        end
    end
    layout_dirty = true
end

local function BatchSetCollapsed(selected_tracks, collapse_on)
    if IsLayoutLockedCfg(GetConfig()) then return end
    if not selected_tracks or #selected_tracks == 0 then return end
    for i = 1, #selected_tracks do
        local g = selected_tracks[i].guid
        if collapse_on then
            collapsed_nodes[g] = true
        else
            collapsed_nodes[g] = nil
        end
    end
    layout_dirty = true
end

local function BatchDeleteTracks(selected_tracks)
    if IsAllLockedCfg(GetConfig()) then return end
    if not selected_tracks or #selected_tracks == 0 then return end
    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)
    for i = 1, #selected_tracks do
        local tr = selected_tracks[i].track
        if tr and r.ValidatePtr(tr, "MediaTrack*") then
            r.DeleteTrack(tr)
        end
        pb_selected_set[selected_tracks[i].guid] = nil
        node_positions[selected_tracks[i].guid] = nil
        pinned_nodes[selected_tracks[i].guid] = nil
        collapsed_nodes[selected_tracks[i].guid] = nil
    end
    r.PreventUIRefresh(-1)
    r.TrackList_AdjustWindows(false)
    r.UpdateArrange()
    r.Undo_EndBlock("Patchbay: delete selected tracks", -1)
    _G.TRACK = r.GetSelectedTrack(0, 0)
    layout_dirty = true
end

local function BatchConnectSelectedToTarget(selected_tracks, target)
    if IsAllLockedCfg(GetConfig()) then return end
    if not selected_tracks or #selected_tracks == 0 then return end
    if not target or not r.ValidatePtr(target, "MediaTrack*") then return end
    local changes = 0
    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)
    for i = 1, #selected_tracks do
        local src = selected_tracks[i].track
        if src and r.ValidatePtr(src, "MediaTrack*") and src ~= target then
            if GetSendIndexLocal(src, target) < 0 then
                r.CreateTrackSend(src, target)
                changes = changes + 1
            end
        end
    end
    r.PreventUIRefresh(-1)
    if changes > 0 then
        r.TrackList_AdjustWindows(false)
        r.UpdateArrange()
        r.Undo_EndBlock("Patchbay: connect selected to node", -1)
    else
        r.Undo_EndBlock("Patchbay: connect selected to node (no changes)", -1)
    end
end

local function BatchConnectTargetToSelected(target, selected_tracks)
    if IsAllLockedCfg(GetConfig()) then return end
    if not selected_tracks or #selected_tracks == 0 then return end
    if not target or not r.ValidatePtr(target, "MediaTrack*") then return end
    local changes = 0
    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)
    for i = 1, #selected_tracks do
        local dst = selected_tracks[i].track
        if dst and r.ValidatePtr(dst, "MediaTrack*") and dst ~= target then
            if GetSendIndexLocal(target, dst) < 0 then
                r.CreateTrackSend(target, dst)
                changes = changes + 1
            end
        end
    end
    r.PreventUIRefresh(-1)
    if changes > 0 then
        r.TrackList_AdjustWindows(false)
        r.UpdateArrange()
        r.Undo_EndBlock("Patchbay: connect node to selected", -1)
    else
        r.Undo_EndBlock("Patchbay: connect node to selected (no changes)", -1)
    end
end

local function BatchDisconnectSelectedToTarget(selected_tracks, target)
    if IsAllLockedCfg(GetConfig()) then return end
    if not selected_tracks or #selected_tracks == 0 then return end
    if not target or not r.ValidatePtr(target, "MediaTrack*") then return end
    local changes = 0
    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)
    for i = 1, #selected_tracks do
        local src = selected_tracks[i].track
        if src and r.ValidatePtr(src, "MediaTrack*") and src ~= target then
            local idx = GetSendIndexLocal(src, target)
            while idx >= 0 do
                r.RemoveTrackSend(src, 0, idx)
                changes = changes + 1
                idx = GetSendIndexLocal(src, target)
            end
        end
    end
    r.PreventUIRefresh(-1)
    if changes > 0 then
        r.TrackList_AdjustWindows(false)
        r.UpdateArrange()
        r.Undo_EndBlock("Patchbay: disconnect selected from node", -1)
    else
        r.Undo_EndBlock("Patchbay: disconnect selected from node (no changes)", -1)
    end
end

local function BatchDisconnectTargetToSelected(target, selected_tracks)
    if IsAllLockedCfg(GetConfig()) then return end
    if not selected_tracks or #selected_tracks == 0 then return end
    if not target or not r.ValidatePtr(target, "MediaTrack*") then return end
    local changes = 0
    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)
    for i = 1, #selected_tracks do
        local dst = selected_tracks[i].track
        if dst and r.ValidatePtr(dst, "MediaTrack*") and dst ~= target then
            local idx = GetSendIndexLocal(target, dst)
            while idx >= 0 do
                r.RemoveTrackSend(target, 0, idx)
                changes = changes + 1
                idx = GetSendIndexLocal(target, dst)
            end
        end
    end
    r.PreventUIRefresh(-1)
    if changes > 0 then
        r.TrackList_AdjustWindows(false)
        r.UpdateArrange()
        r.Undo_EndBlock("Patchbay: disconnect node from selected", -1)
    else
        r.Undo_EndBlock("Patchbay: disconnect node from selected (no changes)", -1)
    end
end

local function FindTrackByGuid(guid)
    if not guid or guid == "" then return nil end
    if guid == MASTER_GUID then
        local master = r.GetMasterTrack(0)
        if master and r.ValidatePtr(master, "MediaTrack*") then return master end
        return nil
    end
    local n = r.CountTracks(0)
    for i = 0, n - 1 do
        local tr = r.GetTrack(0, i)
        if tr and r.ValidatePtr(tr, "MediaTrack*") and r.GetTrackGUID(tr) == guid then
            return tr
        end
    end
    return nil
end

local function BatchConnectSelectedToDestination(selected_tracks, target)
    if IsAllLockedCfg(GetConfig()) then return 0 end
    if not selected_tracks or #selected_tracks == 0 then return 0 end
    if not target or not r.ValidatePtr(target, "MediaTrack*") then return 0 end
    local changes = 0
    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)
    for i = 1, #selected_tracks do
        local src = selected_tracks[i].track
        if src and r.ValidatePtr(src, "MediaTrack*") and src ~= target then
            if GetSendIndexLocal(src, target) < 0 then
                r.CreateTrackSend(src, target)
                changes = changes + 1
            end
        end
    end
    r.PreventUIRefresh(-1)
    if changes > 0 then
        r.TrackList_AdjustWindows(false)
        r.UpdateArrange()
        r.Undo_EndBlock("Patchbay: bulk connect selected to destination", -1)
    else
        r.Undo_EndBlock("Patchbay: bulk connect selected to destination (no changes)", -1)
    end
    return changes
end

local function BatchDisconnectSelectedFromDestination(selected_tracks, target)
    if IsAllLockedCfg(GetConfig()) then return 0 end
    if not selected_tracks or #selected_tracks == 0 then return 0 end
    if not target or not r.ValidatePtr(target, "MediaTrack*") then return 0 end
    local changes = 0
    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)
    for i = 1, #selected_tracks do
        local src = selected_tracks[i].track
        if src and r.ValidatePtr(src, "MediaTrack*") and src ~= target then
            local idx = GetSendIndexLocal(src, target)
            while idx >= 0 do
                r.RemoveTrackSend(src, 0, idx)
                changes = changes + 1
                idx = GetSendIndexLocal(src, target)
            end
        end
    end
    r.PreventUIRefresh(-1)
    if changes > 0 then
        r.TrackList_AdjustWindows(false)
        r.UpdateArrange()
        r.Undo_EndBlock("Patchbay: bulk disconnect selected from destination", -1)
    else
        r.Undo_EndBlock("Patchbay: bulk disconnect selected from destination (no changes)", -1)
    end
    return changes
end

local function BatchApplyBulkRouteSettings(selected_tracks, target, create_missing, mode, vol_db, pan, mute, phase, mono)
    if IsAllLockedCfg(GetConfig()) then return 0 end
    if not selected_tracks or #selected_tracks == 0 then return 0 end
    if not target or not r.ValidatePtr(target, "MediaTrack*") then return 0 end
    local changes = 0
    local vol = math.exp(vol_db * math.log(10) / 20)
    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)
    for i = 1, #selected_tracks do
        local src = selected_tracks[i].track
        if src and r.ValidatePtr(src, "MediaTrack*") and src ~= target then
            local idx = GetSendIndexLocal(src, target)
            if idx < 0 and create_missing then
                r.CreateTrackSend(src, target)
                idx = GetSendIndexLocal(src, target)
                if idx >= 0 then changes = changes + 1 end
            end
            if idx >= 0 then
                r.SetTrackSendInfo_Value(src, 0, idx, "I_SENDMODE", mode)
                r.SetTrackSendInfo_Value(src, 0, idx, "D_VOL", vol)
                r.SetTrackSendInfo_Value(src, 0, idx, "D_PAN", pan)
                r.SetTrackSendInfo_Value(src, 0, idx, "B_MUTE", mute and 1 or 0)
                r.SetTrackSendInfo_Value(src, 0, idx, "B_PHASE", phase and 1 or 0)
                r.SetTrackSendInfo_Value(src, 0, idx, "B_MONO", mono and 1 or 0)
                changes = changes + 1
            end
        end
    end
    r.PreventUIRefresh(-1)
    if changes > 0 then
        r.TrackList_AdjustWindows(false)
        r.UpdateArrange()
        r.Undo_EndBlock("Patchbay: bulk edit route settings", -1)
    else
        r.Undo_EndBlock("Patchbay: bulk edit route settings (no changes)", -1)
    end
    return changes
end

GetCtx = function()
    return _G.ctx
end

GetConfig = function()
    return _G.config
end

local function NodeW()
    local cfg = GetConfig()
    return (cfg and cfg.patchbay_node_width) or NODE_W_DEFAULT
end

local function ColW()
    return NodeW() + 60
end

local function GetLayoutPreset(cfg)
    local p = cfg and cfg.patchbay_layout_preset or "hybrid"
    if not LAYOUT_PRESET_GAPS[p] then p = "hybrid" end
    return p
end

local function LayoutPresetLabel(p)
    return LAYOUT_PRESET_LABELS[p] or "Hybrid"
end

local function LayoutColW(cfg)
    local g = LAYOUT_PRESET_GAPS[GetLayoutPreset(cfg)]
    return NodeW() + g.col
end

local function LayoutRowH(cfg)
    local g = LAYOUT_PRESET_GAPS[GetLayoutPreset(cfg)]
    return g.row
end

GetLockMode = function(cfg)
    local m = cfg and cfg.patchbay_lock_mode or "none"
    if m ~= "none" and m ~= "layout" and m ~= "all" then m = "none" end
    return m
end

IsLayoutLockedCfg = function(cfg)
    local m = GetLockMode(cfg)
    return m == "layout" or m == "all"
end

IsAllLockedCfg = function(cfg)
    return GetLockMode(cfg) == "all"
end

local function HasGuid(guid)
    return guid ~= nil and node_positions[guid] ~= nil
end

local function NodeH(guid)
    if guid and collapsed_nodes[guid] then return NODE_H_COLLAPSED end
    return NODE_H
end

local function EncodeLayout()
    local lines = {}
    for guid, p in pairs(node_positions) do
        lines[#lines + 1] = string.format("%s|%.1f|%.1f", guid, p.x, p.y)
    end
    for guid, is_pinned in pairs(pinned_nodes) do
        if is_pinned then
            lines[#lines + 1] = string.format("__pin__|%s|1", guid)
        end
    end
    for guid, is_collapsed in pairs(collapsed_nodes) do
        if is_collapsed then
            lines[#lines + 1] = string.format("__collapse__|%s|1", guid)
        end
    end
    lines[#lines + 1] = string.format("__off__|%.1f|%.1f", canvas_offset_x, canvas_offset_y)
    lines[#lines + 1] = string.format("__zoom__|%.4f|0", canvas_zoom)
    return table.concat(lines, "\n")
end

local function DecodeLayout(s)
    local out = {}
    local pins = {}
    local collapsed = {}
    local off_x, off_y = 0, 0
    local zoom = 1.0
    if not s or s == "" then return out, off_x, off_y, zoom, pins, collapsed end
    for line in s:gmatch("([^\n]+)") do
        local g, xs, ys = line:match("^([^|]+)|([^|]+)|(.+)$")
        if g and xs and ys then
            if g == "__pin__" then
                pins[xs] = ys == "1"
            elseif g == "__collapse__" then
                collapsed[xs] = ys == "1"
            else
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
    end
    return out, off_x, off_y, zoom, pins, collapsed
end

local function SaveLayout()
    local s = EncodeLayout()
    r.SetProjExtState(0, "TK_FXB_PATCHBAY", "layout", s)
    layout_dirty = false
    last_save_time = r.time_precise()
end

local function LoadLayout()
    local _, s = r.GetProjExtState(0, "TK_FXB_PATCHBAY", "layout")
    local positions, ox, oy, zm, pins, collapsed = DecodeLayout(s or "")
    node_positions = positions
    pinned_nodes = pins or {}
    collapsed_nodes = collapsed or {}
    canvas_offset_x = ox
    canvas_offset_y = oy
    canvas_zoom = zm or 1.0
    layout_dirty = false
end

local function UrlEncode(s)
    s = tostring(s or "")
    return (s:gsub("([^%w%-_%.~])", function(c)
        return string.format("%%%02X", string.byte(c))
    end))
end

local function UrlDecode(s)
    s = tostring(s or "")
    return (s:gsub("%%(%x%x)", function(h)
        return string.char(tonumber(h, 16) or 0)
    end))
end

local function Trim(s)
    return (tostring(s or ""):match("^%s*(.-)%s*$")) or ""
end

local function SaveSnapshotStore()
    local lines = {}
    for i = 1, #snapshot_names do
        local name = snapshot_names[i]
        local payload = snapshot_map[name]
        if name and name ~= "" and payload and payload ~= "" then
            lines[#lines + 1] = UrlEncode(name) .. "|" .. UrlEncode(payload)
        end
    end
    r.SetProjExtState(0, "TK_FXB_PATCHBAY_SNAPSHOTS", "items", table.concat(lines, "\n"))
end

local function LoadSnapshotStore()
    snapshot_names = {}
    snapshot_map = {}
    local _, raw = r.GetProjExtState(0, "TK_FXB_PATCHBAY_SNAPSHOTS", "items")
    if raw and raw ~= "" then
        for line in raw:gmatch("([^\n]+)") do
            local a, b = line:match("^([^|]+)|(.+)$")
            if a and b then
                local name = UrlDecode(a)
                local payload = UrlDecode(b)
                if name ~= "" and payload ~= "" then
                    snapshot_names[#snapshot_names + 1] = name
                    snapshot_map[name] = payload
                end
            end
        end
    end
    if snapshot_selected_name and not snapshot_map[snapshot_selected_name] then
        snapshot_selected_name = nil
    end
end

local function BuildSnapshotPayload(cfg)
    local lines = {}
    lines[#lines + 1] = "layout=" .. UrlEncode(EncodeLayout())
    lines[#lines + 1] = "routing_filter_text=" .. UrlEncode(cfg.routing_filter_text or "")
    lines[#lines + 1] = "routing_only_selected=" .. ((cfg.routing_only_selected and 1) or 0)
    lines[#lines + 1] = "patchbay_only_explicit_routing=" .. ((cfg.patchbay_only_explicit_routing and 1) or 0)
    lines[#lines + 1] = "patchbay_show_master=" .. (((cfg.patchbay_show_master ~= false) and 1) or 0)
    lines[#lines + 1] = "patchbay_show_flow=" .. (((cfg.patchbay_show_flow ~= false) and 1) or 0)
    lines[#lines + 1] = "patchbay_route_filter=" .. UrlEncode(cfg.patchbay_route_filter or "all")
    lines[#lines + 1] = "patchbay_solo_path=" .. ((cfg.patchbay_solo_path and 1) or 0)
    lines[#lines + 1] = "patchbay_layout_preset=" .. UrlEncode(GetLayoutPreset(cfg))
    lines[#lines + 1] = "patchbay_lock_mode=" .. UrlEncode(GetLockMode(cfg))
    return table.concat(lines, "\n")
end

local function ApplySnapshotPayload(payload, cfg)
    if not payload or payload == "" then return end
    local layout_blob = nil
    for line in payload:gmatch("([^\n]+)") do
        local k, v = line:match("^([^=]+)=(.*)$")
        if k and v then
            if k == "layout" then
                layout_blob = UrlDecode(v)
            elseif k == "routing_filter_text" then
                cfg.routing_filter_text = UrlDecode(v)
            elseif k == "routing_only_selected" then
                cfg.routing_only_selected = (v == "1")
            elseif k == "patchbay_only_explicit_routing" then
                cfg.patchbay_only_explicit_routing = (v == "1")
            elseif k == "patchbay_show_master" then
                cfg.patchbay_show_master = (v == "1")
            elseif k == "patchbay_show_flow" then
                cfg.patchbay_show_flow = (v == "1")
            elseif k == "patchbay_route_filter" then
                cfg.patchbay_route_filter = UrlDecode(v)
            elseif k == "patchbay_solo_path" then
                cfg.patchbay_solo_path = (v == "1")
            elseif k == "patchbay_layout_preset" then
                local p = UrlDecode(v)
                if LAYOUT_PRESET_GAPS[p] then cfg.patchbay_layout_preset = p end
            elseif k == "patchbay_lock_mode" then
                local m = UrlDecode(v)
                if m == "none" or m == "layout" or m == "all" then
                    cfg.patchbay_lock_mode = m
                end
            end
        end
    end
    if layout_blob and layout_blob ~= "" then
        local positions, ox, oy, zm, pins, collapsed = DecodeLayout(layout_blob)
        node_positions = positions or {}
        pinned_nodes = pins or {}
        collapsed_nodes = collapsed or {}
        canvas_offset_x = ox or 0
        canvas_offset_y = oy or 0
        canvas_zoom = zm or 1.0
    end
    if _G.SaveConfig then _G.SaveConfig() end
    layout_dirty = true
end

local function SaveSnapshotNamed(name, cfg)
    local n = Trim(name)
    if n == "" then return false end
    if not snapshot_map[n] then
        snapshot_names[#snapshot_names + 1] = n
    end
    snapshot_map[n] = BuildSnapshotPayload(cfg)
    snapshot_selected_name = n
    SaveSnapshotStore()
    return true
end

local function LoadSnapshotNamed(name, cfg)
    local n = Trim(name)
    local payload = snapshot_map[n]
    if not payload then return false end
    ApplySnapshotPayload(payload, cfg)
    snapshot_selected_name = n
    return true
end

local function DeleteSnapshotNamed(name)
    local n = Trim(name)
    if n == "" or not snapshot_map[n] then return false end
    snapshot_map[n] = nil
    for i = #snapshot_names, 1, -1 do
        if snapshot_names[i] == n then
            table.remove(snapshot_names, i)
            break
        end
    end
    if snapshot_selected_name == n then snapshot_selected_name = nil end
    SaveSnapshotStore()
    return true
end

local function GetCurrentProjectKey()
    local _, fn = r.EnumProjects(-1)
    return fn or ""
end

local function CollectVisibleTracks()
    local cfg = GetConfig()
    local filter = ((cfg.routing_filter_text or "")):lower()
    local only_selected = cfg.routing_only_selected
    local only_explicit = cfg.patchbay_only_explicit_routing == true
    local TRACK_SEL = _G.TRACK
    local master = r.GetMasterTrack(0)
    local folder_stack = {}
    local selected_tracks = {}
    local selected_set = {}

    if only_selected then
        local sel_count = r.CountSelectedTracks(0)
        for i = 0, sel_count - 1 do
            local st = r.GetSelectedTrack(0, i)
            if st and r.ValidatePtr(st, "MediaTrack*") and not selected_set[st] then
                selected_set[st] = true
                selected_tracks[#selected_tracks + 1] = st
            end
        end
        if r.IsTrackSelected and master and r.ValidatePtr(master, "MediaTrack*") and r.IsTrackSelected(master) and not selected_set[master] then
            selected_set[master] = true
            selected_tracks[#selected_tracks + 1] = master
        end
        if #selected_tracks == 0 and TRACK_SEL and r.ValidatePtr(TRACK_SEL, "MediaTrack*") then
            selected_set[TRACK_SEL] = true
            selected_tracks[#selected_tracks + 1] = TRACK_SEL
        end
    end

    local function TrackHasExplicitSend(src, dst)
        if not src or not dst then return false end
        if not r.ValidatePtr(src, "MediaTrack*") or not r.ValidatePtr(dst, "MediaTrack*") then return false end
        local ns = r.GetTrackNumSends(src, 0)
        for si = 0, ns - 1 do
            local d = r.GetTrackSendInfo_Value(src, 0, si, "P_DESTTRACK")
            if d == dst then return true end
        end
        return false
    end

    local n = r.CountTracks(0)
    local list = {}
    local any_mainsend = false
    for i = 0, n - 1 do
        local t = r.GetTrack(0, i)
        local _, name = r.GetTrackName(t)
        local guid = r.GetTrackGUID(t)
        local depth = math.floor(r.GetMediaTrackInfo_Value(t, "I_FOLDERDEPTH") or 0)
        local folder_top = folder_stack[#folder_stack]
        local folder_group_guid = nil
        local folder_group_name = nil
        local folder_group_r = nil
        local folder_group_g = nil
        local folder_group_b = nil
        local folder_is_parent = depth > 0
        if folder_is_parent then
            folder_group_guid = guid
            folder_group_name = name
            local tcol = r.GetTrackColor(t)
            if tcol and tcol ~= 0 then
                folder_group_r, folder_group_g, folder_group_b = r.ColorFromNative(tcol)
            end
        elseif folder_top then
            folder_group_guid = folder_top.guid
            folder_group_name = folder_top.name
            folder_group_r = folder_top.r
            folder_group_g = folder_top.g
            folder_group_b = folder_top.b
        end
        local nrec = r.GetTrackNumSends(t, -1)
        local nsnd = r.GetTrackNumSends(t, 0)
        local mainsend = r.GetMediaTrackInfo_Value(t, "B_MAINSEND") == 1
        if mainsend then any_mainsend = true end

        local has_explicit_receive = false
        for k = 0, nrec - 1 do
            local src = r.GetTrackSendInfo_Value(t, -1, k, "P_SRCTRACK")
            if src and r.ValidatePtr(src, "MediaTrack*") then
                local src_nsnd = r.GetTrackNumSends(src, 0)
                for si = 0, src_nsnd - 1 do
                    local sd = r.GetTrackSendInfo_Value(src, 0, si, "P_DESTTRACK")
                    if sd == t then
                        has_explicit_receive = true
                        break
                    end
                end
            end
            if has_explicit_receive then break end
        end

        local has_explicit = (nsnd > 0 or has_explicit_receive)
        local has_routing
        if only_explicit then
            has_routing = has_explicit
        else
            has_routing = (has_explicit or mainsend)
        end
        local match_filter = filter == "" or name:lower():find(filter, 1, true) ~= nil
        local match_sel = true
        if only_selected and #selected_tracks > 0 then
            if selected_set[t] then
                match_sel = true
            else
                match_sel = false
                for si = 1, #selected_tracks do
                    local sel = selected_tracks[si]
                    if sel == master then
                        if (r.GetMediaTrackInfo_Value(t, "B_MAINSEND") == 1)
                            or TrackHasExplicitSend(t, master)
                            or TrackHasExplicitSend(master, t)
                        then
                            match_sel = true
                            break
                        end
                    else
                        if TrackHasExplicitSend(t, sel) or TrackHasExplicitSend(sel, t) then
                            match_sel = true
                            break
                        end
                        if t == master and ((r.GetMediaTrackInfo_Value(sel, "B_MAINSEND") == 1)
                            or TrackHasExplicitSend(sel, master)
                            or TrackHasExplicitSend(master, sel))
                        then
                            match_sel = true
                            break
                        end
                    end
                end
            end
        end
        if has_routing and match_filter and match_sel then
            list[#list + 1] = {
                track = t,
                idx = i,
                name = name,
                guid = guid,
                folder_group_guid = folder_group_guid,
                folder_group_name = folder_group_name,
                folder_group_r = folder_group_r,
                folder_group_g = folder_group_g,
                folder_group_b = folder_group_b,
                folder_is_parent = folder_is_parent
            }
        end

        if depth > 0 then
            folder_stack[#folder_stack + 1] = { guid = guid, name = name, r = folder_group_r, g = folder_group_g, b = folder_group_b }
        elseif depth < 0 then
            for _ = 1, -depth do
                if #folder_stack > 0 then
                    table.remove(folder_stack)
                end
            end
        end
    end
    local master_match_filter = filter == "" or ("master"):find(filter, 1, true) ~= nil
    local master_match_sel = true
    if only_selected and #selected_tracks > 0 then
        if selected_set[master] then
            master_match_sel = true
        else
            master_match_sel = false
            for si = 1, #selected_tracks do
                local sel = selected_tracks[si]
                if sel ~= master and ((r.GetMediaTrackInfo_Value(sel, "B_MAINSEND") == 1)
                    or TrackHasExplicitSend(sel, master)
                    or TrackHasExplicitSend(master, sel))
                then
                    master_match_sel = true
                    break
                end
            end
        end
    end
    local nmsnd = r.GetTrackNumSends(master, 0)
    local nmrec = r.GetTrackNumSends(master, -1)
    local master_has_routing
    if only_explicit then
        master_has_routing = (nmsnd > 0 or nmrec > 0)
    else
        master_has_routing = (any_mainsend or nmsnd > 0 or nmrec > 0)
    end
    local show_master = cfg.patchbay_show_master ~= false
    if show_master and master_has_routing and master_match_filter and master_match_sel then
        list[#list + 1] = { track = master, idx = -1, name = "MASTER", guid = MASTER_GUID, is_master = true }
    end
    return list
end

local function TrackAuditLabel(tr)
    local master = r.GetMasterTrack(0)
    if tr == master then return "MASTER" end
    if not tr or not r.ValidatePtr(tr, "MediaTrack*") then return "<invalid track>" end
    local idx = math.floor(r.GetMediaTrackInfo_Value(tr, "IP_TRACKNUMBER") or 0)
    local _, name = r.GetTrackName(tr)
    return string.format("#%d %s", idx, name or "")
end

local function AddRouteAuditIssue(severity, text, src, dst)
    route_audit_issues[#route_audit_issues + 1] = {
        severity = severity,
        text = text,
        src = src,
        dst = dst
    }
    if severity == "error" then
        route_audit_error_count = route_audit_error_count + 1
    else
        route_audit_warn_count = route_audit_warn_count + 1
    end
end

local function MarkRouteAuditCable(sg, dg, severity)
    if not sg or not dg then return end
    local key = sg .. "->" .. dg
    local cur = route_audit_cable_marks[key]
    if cur == "error" then return end
    if severity == "error" or cur == nil then
        route_audit_cable_marks[key] = severity
    end
end

local function MarkRouteAuditTrackPair(src, dst, severity)
    if not src or not dst then return end
    if not r.ValidatePtr(src, "MediaTrack*") or not r.ValidatePtr(dst, "MediaTrack*") then return end
    local sg = r.GetTrackGUID(src)
    local dg = r.GetTrackGUID(dst)
    MarkRouteAuditCable(sg, dg, severity)
end

local function RunRouteAudit()
    route_audit_issues = {}
    route_audit_error_count = 0
    route_audit_warn_count = 0
    route_audit_cable_marks = {}
    route_audit_visual_active = true

    local tracks = {}
    local master = r.GetMasterTrack(0)
    local n = r.CountTracks(0)
    for i = 0, n - 1 do
        local tr = r.GetTrack(0, i)
        if tr and r.ValidatePtr(tr, "MediaTrack*") then
            tracks[#tracks + 1] = tr
        end
    end
    if master and r.ValidatePtr(master, "MediaTrack*") then
        tracks[#tracks + 1] = master
    end

    local pair_count = {}
    local pair_src = {}
    local pair_dst = {}
    local has_pair = {}

    for i = 1, #tracks do
        local src = tracks[i]
        local src_guid = r.GetTrackGUID(src)
        local ns = r.GetTrackNumSends(src, 0)
        for si = 0, ns - 1 do
            local dst = r.GetTrackSendInfo_Value(src, 0, si, "P_DESTTRACK")
            if not dst or not r.ValidatePtr(dst, "MediaTrack*") then
                AddRouteAuditIssue("error", string.format("Invalid destination in send from %s", TrackAuditLabel(src)), src, nil)
            else
                if dst == src then
                    AddRouteAuditIssue("error", string.format("Self-send on %s", TrackAuditLabel(src)), src, dst)
                    MarkRouteAuditTrackPair(src, dst, "error")
                end
                local dst_guid = r.GetTrackGUID(dst)
                local key = src_guid .. "->" .. dst_guid
                pair_count[key] = (pair_count[key] or 0) + 1
                pair_src[key] = src
                pair_dst[key] = dst
                has_pair[key] = true

                if src ~= master and dst == master and r.GetMediaTrackInfo_Value(src, "B_MAINSEND") == 1 then
                    AddRouteAuditIssue("warn", string.format("%s has main send ON and extra explicit send to MASTER", TrackAuditLabel(src)), src, dst)
                    MarkRouteAuditCable(src_guid, MASTER_GUID, "warn")
                end
            end
        end
    end

    for key, count in pairs(pair_count) do
        if count > 1 then
            local src = pair_src[key]
            local dst = pair_dst[key]
            AddRouteAuditIssue("warn", string.format("Duplicate sends: %s -> %s (%dx)", TrackAuditLabel(src), TrackAuditLabel(dst), count), src, dst)
            MarkRouteAuditTrackPair(src, dst, "warn")
        end
    end

    local seen_feedback = {}
    for key, _ in pairs(has_pair) do
        local sep = key:find("->", 1, true)
        if sep then
            local a = key:sub(1, sep - 1)
            local b = key:sub(sep + 2)
            local reverse = b .. "->" .. a
            if has_pair[reverse] then
                local canon = (a < b) and (a .. "|" .. b) or (b .. "|" .. a)
                if not seen_feedback[canon] then
                    seen_feedback[canon] = true
                    local src = pair_src[key]
                    local dst = pair_dst[key]
                    AddRouteAuditIssue("error", string.format("Feedback loop: %s <-> %s", TrackAuditLabel(src), TrackAuditLabel(dst)), src, dst)
                    MarkRouteAuditTrackPair(src, dst, "error")
                    MarkRouteAuditTrackPair(dst, src, "error")
                end
            end
        end
    end

    table.sort(route_audit_issues, function(a, b)
        local ap = (a.severity == "error") and 0 or 1
        local bp = (b.severity == "error") and 0 or 1
        if ap ~= bp then return ap < bp end
        return (a.text or "") < (b.text or "")
    end)
end

local function AutoLayout(tracks)
    local cfg = GetConfig()
    local col_w = LayoutColW(cfg)
    local row_h = LayoutRowH(cfg)
    local old_positions = node_positions
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
            local g = cl[ri].guid
            if pinned_nodes[g] and old_positions[g] then
                node_positions[g] = { x = old_positions[g].x, y = old_positions[g].y }
            else
                node_positions[g] = { x = ci * col_w + 40, y = (ri - 1) * row_h + 40 }
            end
        end
    end
    if master_entry then
        local mx = col * col_w + 40
        local my = math.max(40, ((max_rows - 1) * row_h) * 0.5 + 40)
        if pinned_nodes[MASTER_GUID] and old_positions[MASTER_GUID] then
            node_positions[MASTER_GUID] = { x = old_positions[MASTER_GUID].x, y = old_positions[MASTER_GUID].y }
        else
            node_positions[MASTER_GUID] = { x = mx, y = my }
        end
    end
    canvas_offset_x = 0
    canvas_offset_y = 0
    canvas_zoom = 1.0
    layout_dirty = true
end

local function EnsurePositions(tracks)
    local cfg = GetConfig()
    local col_w = LayoutColW(cfg)
    local row_h = LayoutRowH(cfg)
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
            node_positions[g] = { x = max_x + col_w, y = next_y }
            next_y = next_y + row_h
            layout_dirty = true
        end
    end
end

local function AlignVisibleNodesToGrid(tracks)
    if not tracks or #tracks == 0 then return end
    local moved = false
    for i = 1, #tracks do
        local g = tracks[i].guid
        local p = node_positions[g]
        if p and not pinned_nodes[g] then
            local nx = math.floor((p.x / GRID) + 0.5) * GRID
            local ny = math.floor((p.y / GRID) + 0.5) * GRID
            if nx ~= p.x or ny ~= p.y then
                p.x = nx
                p.y = ny
                moved = true
            end
        end
    end
    if moved then
        layout_dirty = true
    end
end

GetSendIndexLocal = function(src, dst)
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

local function FolderBodyColor(r8, g8, b8, dim)
    if not r8 or not g8 or not b8 then return nil end
    local rr = math.floor(r8 * 0.28 + 18)
    local gg = math.floor(g8 * 0.28 + 18)
    local bb = math.floor(b8 * 0.28 + 20)
    local aa = dim and 0xCC or 0xFF
    return ((rr & 0xFF) << 24) | ((gg & 0xFF) << 16) | ((bb & 0xFF) << 8) | aa
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
    local cfg = GetConfig()
    local all_locked = IsAllLockedCfg(cfg)
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
            if all_locked then
                r.ImGui_Separator(ctx)
                r.ImGui_TextDisabled(ctx, "All locked: routing is read-only.")
                if r.ImGui_Button(ctx, "Close") then r.ImGui_CloseCurrentPopup(ctx); right_click_send = nil end
                r.ImGui_EndPopup(ctx)
                return
            end
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
        if all_locked then
            r.ImGui_Separator(ctx)
            r.ImGui_TextDisabled(ctx, "All locked: routing is read-only.")
            if r.ImGui_Button(ctx, "Close") then r.ImGui_CloseCurrentPopup(ctx); right_click_send = nil end
            r.ImGui_EndPopup(ctx)
            return
        end
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

local function RenderNodePopup()
    local ctx = GetCtx()
    if not node_popup_track then return end
    if not r.ValidatePtr(node_popup_track, "MediaTrack*") then
        node_popup_track = nil
        node_popup_guid = nil
        return
    end
    if r.ImGui_BeginPopup(ctx, "PatchbayNodePopup") then
        local tr = node_popup_track
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
        if node_popup_guid and node_popup_guid ~= MASTER_GUID then
            local selected_tracks = GetSelectedPatchbayTracks()
            if #selected_tracks > 1 then
                r.ImGui_Separator(ctx)
                r.ImGui_TextDisabled(ctx, string.format("Group actions (%d selected)", #selected_tracks))
                if r.ImGui_Selectable(ctx, "Connect selected -> this") then
                    BatchConnectSelectedToTarget(selected_tracks, tr)
                    r.ImGui_CloseCurrentPopup(ctx)
                end
                if r.ImGui_Selectable(ctx, "Connect this -> selected") then
                    BatchConnectTargetToSelected(tr, selected_tracks)
                    r.ImGui_CloseCurrentPopup(ctx)
                end
                if r.ImGui_Selectable(ctx, "Disconnect selected -> this") then
                    BatchDisconnectSelectedToTarget(selected_tracks, tr)
                    r.ImGui_CloseCurrentPopup(ctx)
                end
                if r.ImGui_Selectable(ctx, "Disconnect this -> selected") then
                    BatchDisconnectTargetToSelected(tr, selected_tracks)
                    r.ImGui_CloseCurrentPopup(ctx)
                end
            end
            r.ImGui_Separator(ctx)
            local is_pinned = pinned_nodes[node_popup_guid] == true
            if r.ImGui_Selectable(ctx, is_pinned and "Unpin node" or "Pin node") then
                if is_pinned then
                    pinned_nodes[node_popup_guid] = nil
                else
                    pinned_nodes[node_popup_guid] = true
                end
                layout_dirty = true
                r.ImGui_CloseCurrentPopup(ctx)
            end
            local is_collapsed = collapsed_nodes[node_popup_guid] == true
            if r.ImGui_Selectable(ctx, is_collapsed and "Expand node" or "Collapse node") then
                if is_collapsed then
                    collapsed_nodes[node_popup_guid] = nil
                else
                    collapsed_nodes[node_popup_guid] = true
                end
                layout_dirty = true
                r.ImGui_CloseCurrentPopup(ctx)
            end
        end
        if r.ImGui_Selectable(ctx, "Remove Track...") then
            DeletePatchbayTrack(tr, node_popup_guid)
            node_popup_track = nil
            node_popup_guid = nil
            r.ImGui_CloseCurrentPopup(ctx)
        end
        r.ImGui_EndPopup(ctx)
    end
end

function ShowRoutingPatchbay()
    local ctx = GetCtx()
    local toolbar_popup_opened = false
    local open_bulk_editor_popup = false
    local popup_menu_offset_y = 4
    local menu_btn_w = 68
    local menu_btn_compact = true
    local menu_btn_text_pad = 10
    local layout_btn_w = menu_btn_w
    local view_btn_w = menu_btn_w
    local route_btn_w = menu_btn_w
    local audit_btn_w = menu_btn_w
    if menu_btn_compact and r.ImGui_CalcTextSize then
        layout_btn_w = (select(1, r.ImGui_CalcTextSize(ctx, "Layout")) or 0) + menu_btn_text_pad
        view_btn_w = (select(1, r.ImGui_CalcTextSize(ctx, "View")) or 0) + menu_btn_text_pad
        route_btn_w = (select(1, r.ImGui_CalcTextSize(ctx, "Route")) or 0) + menu_btn_text_pad
        audit_btn_w = (select(1, r.ImGui_CalcTextSize(ctx, "Audit")) or 0) + menu_btn_text_pad
    end
    local popup_menu_w = 160
    _G.TRACK = r.GetSelectedTrack(0, 0)
    if not _G.patchbay_hide_top_filter_divider then
        r.ImGui_Separator(ctx)
    end
    DrawRoutingFilterBar(false)
    local cfg = GetConfig()
    local lock_mode = GetLockMode(cfg)
    local layout_locked = IsLayoutLockedCfg(cfg)
    local all_locked = IsAllLockedCfg(cfg)

    local proj_key = GetCurrentProjectKey()
    if proj_key ~= layout_loaded_project then
        if layout_loaded_project ~= nil and layout_dirty then SaveLayout() end
        layout_loaded_project = proj_key
        LoadLayout()
        LoadSnapshotStore()
        pending_center_view = true
    end

    if ToolbarMenuButton(ctx, "##patchbay_menu_layout", "Layout", layout_btn_w, "auto") then
        if r.ImGui_GetItemRectMin and r.ImGui_GetItemRectMax then
            local x1, _ = r.ImGui_GetItemRectMin(ctx)
            local _, y2 = r.ImGui_GetItemRectMax(ctx)
            popup_auto_x = x1
            popup_auto_y = y2 + popup_menu_offset_y
        end
        OpenToolbarPopup(ctx, "auto")
    end
    if popup_auto_x and popup_auto_y and r.ImGui_SetNextWindowPos then
        local cond = r.ImGui_Cond_Appearing and r.ImGui_Cond_Appearing() or 0
        r.ImGui_SetNextWindowPos(ctx, popup_auto_x, popup_auto_y, cond)
    end
    if r.ImGui_SetNextWindowSizeConstraints then
        r.ImGui_SetNextWindowSizeConstraints(ctx, popup_menu_w, 0, popup_menu_w, 10000)
    elseif r.ImGui_SetNextWindowSize then
        local cond = r.ImGui_Cond_Appearing and r.ImGui_Cond_Appearing() or 0
        r.ImGui_SetNextWindowSize(ctx, popup_menu_w, 0, cond)
    end
    if r.ImGui_BeginPopup(ctx, "auto") then
        toolbar_popup_opened = true
        open_toolbar_popup_id = "auto"
        local cur_preset = GetLayoutPreset(cfg)
        for i = 1, #LAYOUT_PRESET_ORDER do
            local p = LAYOUT_PRESET_ORDER[i]
            if r.ImGui_Selectable(ctx, LayoutPresetLabel(p), cur_preset == p) then
                if not layout_locked then
                    cfg.patchbay_layout_preset = p
                    if _G.SaveConfig then _G.SaveConfig() end
                    pending_auto_layout = true
                    pending_center_view = true
                    layout_dirty = true
                end
            end
        end
        r.ImGui_Separator(ctx)
        r.ImGui_TextDisabled(ctx, "Lock mode")
        if r.ImGui_Selectable(ctx, "Unlocked", lock_mode == "none") then
            cfg.patchbay_lock_mode = "none"
            if _G.SaveConfig then _G.SaveConfig() end
        end
        if r.ImGui_Selectable(ctx, "Layout locked", lock_mode == "layout") then
            cfg.patchbay_lock_mode = "layout"
            if _G.SaveConfig then _G.SaveConfig() end
        end
        if r.ImGui_Selectable(ctx, "All locked", lock_mode == "all") then
            cfg.patchbay_lock_mode = "all"
            if _G.SaveConfig then _G.SaveConfig() end
        end
        r.ImGui_Separator(ctx)
        if r.ImGui_Selectable(ctx, "Center") then
            if not layout_locked then
                pending_center_view = true
            end
        end
        if r.ImGui_Selectable(ctx, "Grid") then
            if not layout_locked then
                local cur_tracks = CollectVisibleTracks()
                EnsurePositions(cur_tracks)
                AlignVisibleNodesToGrid(cur_tracks)
            end
        end
        r.ImGui_EndPopup(ctx)
    end
    r.ImGui_SameLine(ctx)
    if ToolbarMenuButton(ctx, "##patchbay_menu_view", "View", view_btn_w, "patchbay_view_menu") then
        if r.ImGui_GetItemRectMin and r.ImGui_GetItemRectMax then
            local x1, _ = r.ImGui_GetItemRectMin(ctx)
            local _, y2 = r.ImGui_GetItemRectMax(ctx)
            popup_view_x = x1
            popup_view_y = y2 + popup_menu_offset_y
        end
        OpenToolbarPopup(ctx, "patchbay_view_menu")
    end
    if popup_view_x and popup_view_y and r.ImGui_SetNextWindowPos then
        local cond = r.ImGui_Cond_Appearing and r.ImGui_Cond_Appearing() or 0
        r.ImGui_SetNextWindowPos(ctx, popup_view_x, popup_view_y, cond)
    end
    if r.ImGui_SetNextWindowSizeConstraints then
        r.ImGui_SetNextWindowSizeConstraints(ctx, popup_menu_w, 0, popup_menu_w, 10000)
    elseif r.ImGui_SetNextWindowSize then
        local cond = r.ImGui_Cond_Appearing and r.ImGui_Cond_Appearing() or 0
        r.ImGui_SetNextWindowSize(ctx, popup_menu_w, 0, cond)
    end
    if r.ImGui_BeginPopup(ctx, "patchbay_view_menu") then
        toolbar_popup_opened = true
        open_toolbar_popup_id = "patchbay_view_menu"
        local show_master = cfg.patchbay_show_master ~= false
        local changed, new_val = r.ImGui_Checkbox(ctx, "Master", show_master)
        if changed then
            cfg.patchbay_show_master = new_val
            if _G.SaveConfig then _G.SaveConfig() end
        end
        local only_explicit = cfg.patchbay_only_explicit_routing == true
        local changed_explicit, new_explicit = r.ImGui_Checkbox(ctx, "Explicit", only_explicit)
        if changed_explicit then
            cfg.patchbay_only_explicit_routing = new_explicit
            if _G.SaveConfig then _G.SaveConfig() end
        end
        local show_flow = cfg.patchbay_show_flow ~= false
        local changed_flow, new_flow = r.ImGui_Checkbox(ctx, "Flow", show_flow)
        if changed_flow then
            cfg.patchbay_show_flow = new_flow
            if _G.SaveConfig then _G.SaveConfig() end
        end
        local focus_selected = cfg.routing_only_selected == true
        local changed_focus_selected, new_focus_selected = r.ImGui_Checkbox(ctx, "Focus selected", focus_selected)
        if changed_focus_selected then
            cfg.routing_only_selected = new_focus_selected
            if _G.SaveConfig then _G.SaveConfig() end
        end
        local solo_path = cfg.patchbay_solo_path == true
        local changed_solo_path, new_solo_path = r.ImGui_Checkbox(ctx, "Solo path", solo_path)
        if changed_solo_path then
            cfg.patchbay_solo_path = new_solo_path
            if _G.SaveConfig then _G.SaveConfig() end
        end
        r.ImGui_EndPopup(ctx)
    end
    r.ImGui_SameLine(ctx)
    if ToolbarMenuButton(ctx, "##patchbay_menu_route", "Route", route_btn_w, "patchbay_route_menu") then
        if r.ImGui_GetItemRectMin and r.ImGui_GetItemRectMax then
            local x1, _ = r.ImGui_GetItemRectMin(ctx)
            local _, y2 = r.ImGui_GetItemRectMax(ctx)
            popup_route_x = x1
            popup_route_y = y2 + popup_menu_offset_y
        end
        OpenToolbarPopup(ctx, "patchbay_route_menu")
    end
    if popup_route_x and popup_route_y and r.ImGui_SetNextWindowPos then
        local cond = r.ImGui_Cond_Appearing and r.ImGui_Cond_Appearing() or 0
        r.ImGui_SetNextWindowPos(ctx, popup_route_x, popup_route_y, cond)
    end
    if r.ImGui_SetNextWindowSizeConstraints then
        r.ImGui_SetNextWindowSizeConstraints(ctx, popup_menu_w, 0, popup_menu_w, 10000)
    elseif r.ImGui_SetNextWindowSize then
        local cond = r.ImGui_Cond_Appearing and r.ImGui_Cond_Appearing() or 0
        r.ImGui_SetNextWindowSize(ctx, popup_menu_w, 0, cond)
    end
    if r.ImGui_BeginPopup(ctx, "patchbay_route_menu") then
        toolbar_popup_opened = true
        open_toolbar_popup_id = "patchbay_route_menu"
        local route_filter = cfg.patchbay_route_filter or "all"
        for i = 1, #ROUTE_FILTER_ORDER do
            local filter = ROUTE_FILTER_ORDER[i]
            if r.ImGui_Selectable(ctx, RouteFilterLabel(filter), route_filter == filter) then
                cfg.patchbay_route_filter = filter
                if _G.SaveConfig then _G.SaveConfig() end
            end
        end
        r.ImGui_Separator(ctx)
        local audit_label = string.format("Route audit...  E:%d W:%d", route_audit_error_count, route_audit_warn_count)
        if r.ImGui_Selectable(ctx, audit_label) then
            RunRouteAudit()
            r.ImGui_OpenPopup(ctx, "PatchbayRouteAudit")
        end
        r.ImGui_EndPopup(ctx)
    end

    r.ImGui_SameLine(ctx)
    if TextMenuButton(ctx, "##patchbay_menu_audit", "Audit", audit_btn_w) then
        RunRouteAudit()
        r.ImGui_OpenPopup(ctx, "PatchbayRouteAudit")
    end
    if r.ImGui_IsItemHovered(ctx) then
        r.ImGui_SetTooltip(ctx, string.format("Route audit\nErrors: %d\nWarnings: %d", route_audit_error_count, route_audit_warn_count))
    end

    local selected_tracks = GetSelectedPatchbayTracks()
    local actions_label = string.format("Actions (%d)", #selected_tracks)
    local actions_btn_w = menu_btn_w
    local add_btn_w = menu_btn_w
    if menu_btn_compact and r.ImGui_CalcTextSize then
        actions_btn_w = (select(1, r.ImGui_CalcTextSize(ctx, actions_label)) or 0) + menu_btn_text_pad
    end
    if _G.patchbay_hide_top_filter_divider then
        add_btn_w = 22
    end
    r.ImGui_SameLine(ctx)
    if ToolbarMenuButton(ctx, "##patchbay_menu_actions", actions_label, actions_btn_w, "patchbay_actions_menu") then
        if r.ImGui_GetItemRectMin and r.ImGui_GetItemRectMax then
            local x1, _ = r.ImGui_GetItemRectMin(ctx)
            local _, y2 = r.ImGui_GetItemRectMax(ctx)
            popup_actions_x = x1
            popup_actions_y = y2 + popup_menu_offset_y
        end
        OpenToolbarPopup(ctx, "patchbay_actions_menu")
    end
    if popup_actions_x and popup_actions_y and r.ImGui_SetNextWindowPos then
        local cond = r.ImGui_Cond_Appearing and r.ImGui_Cond_Appearing() or 0
        r.ImGui_SetNextWindowPos(ctx, popup_actions_x, popup_actions_y, cond)
    end
    if r.ImGui_SetNextWindowSizeConstraints then
        r.ImGui_SetNextWindowSizeConstraints(ctx, popup_menu_w, 0, popup_menu_w, 10000)
    elseif r.ImGui_SetNextWindowSize then
        local cond = r.ImGui_Cond_Appearing and r.ImGui_Cond_Appearing() or 0
        r.ImGui_SetNextWindowSize(ctx, popup_menu_w, 0, cond)
    end
    if r.ImGui_BeginPopup(ctx, "patchbay_actions_menu") then
        toolbar_popup_opened = true
        open_toolbar_popup_id = "patchbay_actions_menu"
        if r.ImGui_Selectable(ctx, "Mute selected") then
            BatchSetMute(selected_tracks, true)
        end
        if r.ImGui_Selectable(ctx, "Unmute selected") then
            BatchSetMute(selected_tracks, false)
        end
        if r.ImGui_Selectable(ctx, "Solo selected") then
            BatchSetSolo(selected_tracks, true)
        end
        if r.ImGui_Selectable(ctx, "Unsolo selected") then
            BatchSetSolo(selected_tracks, false)
        end
        r.ImGui_Separator(ctx)
        if r.ImGui_Selectable(ctx, "Pin selected") then
            BatchSetPinned(selected_tracks, true)
        end
        if r.ImGui_Selectable(ctx, "Unpin selected") then
            BatchSetPinned(selected_tracks, false)
        end
        if r.ImGui_Selectable(ctx, "Collapse selected") then
            BatchSetCollapsed(selected_tracks, true)
        end
        if r.ImGui_Selectable(ctx, "Expand selected") then
            BatchSetCollapsed(selected_tracks, false)
        end
        r.ImGui_Separator(ctx)
        if r.ImGui_Selectable(ctx, "Bulk route editor...") then
            if not bulk_route_target_guid then
                local ntracks = r.CountTracks(0)
                if ntracks > 0 then
                    local first = r.GetTrack(0, 0)
                    if first and r.ValidatePtr(first, "MediaTrack*") then
                        bulk_route_target_guid = r.GetTrackGUID(first)
                    end
                end
            end
            open_bulk_editor_popup = true
        end
        r.ImGui_Separator(ctx)
        if r.ImGui_Selectable(ctx, "Delete selected...") then
            delete_selected_targets = selected_tracks
            r.ImGui_OpenPopup(ctx, "PatchbayDeleteSelectedConfirm")
        end
        if r.ImGui_Selectable(ctx, "Clear selection") then
            pb_selected_set = {}
        end
        r.ImGui_EndPopup(ctx)
    end
    if not toolbar_popup_opened then
        open_toolbar_popup_id = nil
    end

    if open_bulk_editor_popup then
        r.ImGui_OpenPopup(ctx, "PatchbayBulkRouteEditor")
    end

    r.ImGui_SameLine(ctx)
    if not _G.patchbay_hide_top_filter_divider then
        r.ImGui_Dummy(ctx, 8, 0)
        r.ImGui_SameLine(ctx)
    end
    if TextMenuButton(ctx, "##patchbay_menu_add_track", "+", add_btn_w) then
        AddPatchbayTrack()
    end
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Add Track") end

    if r.ImGui_BeginPopup(ctx, "PatchbayDeleteSelectedConfirm") then
        local del_count = delete_selected_targets and #delete_selected_targets or 0
        r.ImGui_Text(ctx, string.format("Delete %d selected tracks?", del_count))
        if delete_selected_targets and del_count > 0 then
            local preview = delete_selected_targets[1].name or ""
            if del_count > 1 then
                preview = string.format("%s (+%d more)", preview, del_count - 1)
            end
            r.ImGui_TextDisabled(ctx, preview)
        end
        if r.ImGui_Button(ctx, "Cancel", 110, 0) then
            delete_selected_targets = nil
            r.ImGui_CloseCurrentPopup(ctx)
        end
        r.ImGui_SameLine(ctx)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x802020FF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0xA03030FF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0x601010FF)
        if r.ImGui_Button(ctx, "Delete", 110, 0) then
            BatchDeleteTracks(delete_selected_targets)
            delete_selected_targets = nil
            r.ImGui_CloseCurrentPopup(ctx)
        end
        r.ImGui_PopStyleColor(ctx, 3)
        r.ImGui_EndPopup(ctx)
    end

    if r.ImGui_BeginPopup(ctx, "PatchbayRouteAudit") then
        local total = #route_audit_issues
        r.ImGui_Text(ctx, string.format("Route audit: %d issues", total))
        r.ImGui_TextDisabled(ctx, string.format("Errors: %d   Warnings: %d", route_audit_error_count, route_audit_warn_count))
        local ch_hl, v_hl = r.ImGui_Checkbox(ctx, "Highlight conflicts", route_audit_visual_active)
        if ch_hl then route_audit_visual_active = v_hl end
        if r.ImGui_Button(ctx, "Rescan", 100, 0) then
            RunRouteAudit()
        end
        r.ImGui_SameLine(ctx)
        if r.ImGui_Button(ctx, "Close", 100, 0) then
            r.ImGui_CloseCurrentPopup(ctx)
        end
        r.ImGui_Separator(ctx)
        if total == 0 then
            r.ImGui_TextDisabled(ctx, "No conflicts found.")
        else
            local ch_flags = r.ImGui_WindowFlags_HorizontalScrollbar and r.ImGui_WindowFlags_HorizontalScrollbar() or 0
            if r.ImGui_BeginChild(ctx, "##patchbay_route_audit_list", 620, 300, 1, ch_flags) then
                for i = 1, total do
                    local issue = route_audit_issues[i]
                    local prefix = (issue.severity == "error") and "[E] " or "[W] "
                    if r.ImGui_Selectable(ctx, prefix .. issue.text, false) then
                        local focus = nil
                        if issue.src and r.ValidatePtr(issue.src, "MediaTrack*") and issue.src ~= r.GetMasterTrack(0) then
                            focus = issue.src
                        elseif issue.dst and r.ValidatePtr(issue.dst, "MediaTrack*") and issue.dst ~= r.GetMasterTrack(0) then
                            focus = issue.dst
                        end
                        if focus then
                            r.SetOnlyTrackSelected(focus)
                            _G.TRACK = focus
                            pending_center_view = true
                        end
                    end
                end
            end
            r.ImGui_EndChild(ctx)
        end
        r.ImGui_EndPopup(ctx)
    end

    if r.ImGui_BeginPopup(ctx, "PatchbayBulkRouteEditor") then
        local selected_tracks_now = GetSelectedPatchbayTracks()
        local target_track = FindTrackByGuid(bulk_route_target_guid)
        local target_label = "Select destination"
        if target_track then
            if bulk_route_target_guid == MASTER_GUID then
                target_label = "MASTER"
            else
                local idx = math.floor(r.GetMediaTrackInfo_Value(target_track, "IP_TRACKNUMBER") or 0)
                local _, nm = r.GetTrackName(target_track)
                target_label = string.format("#%d %s", idx, nm or "")
            end
        end

        r.ImGui_Text(ctx, string.format("Bulk route editor (%d selected)", #selected_tracks_now))
        if #selected_tracks_now == 0 then
            r.ImGui_TextDisabled(ctx, "Select one or more nodes first.")
        end

        if r.ImGui_BeginCombo(ctx, "Destination", target_label) then
            local ntracks = r.CountTracks(0)
            for i = 0, ntracks - 1 do
                local tr = r.GetTrack(0, i)
                if tr and r.ValidatePtr(tr, "MediaTrack*") then
                    local guid = r.GetTrackGUID(tr)
                    local idx = math.floor(r.GetMediaTrackInfo_Value(tr, "IP_TRACKNUMBER") or 0)
                    local _, nm = r.GetTrackName(tr)
                    local lab = string.format("#%d %s", idx, nm or "")
                    if r.ImGui_Selectable(ctx, lab, bulk_route_target_guid == guid) then
                        bulk_route_target_guid = guid
                    end
                end
            end
            if r.ImGui_Selectable(ctx, "MASTER", bulk_route_target_guid == MASTER_GUID) then
                bulk_route_target_guid = MASTER_GUID
            end
            r.ImGui_EndCombo(ctx)
        end

        local ch_cm, v_cm = r.ImGui_Checkbox(ctx, "Create missing sends", bulk_route_create_missing)
        if ch_cm then bulk_route_create_missing = v_cm end

        local mode_names = { "Post-Fader", "Pre-Fader (Post-FX)", "Pre-FX" }
        local mode_values = { 0, 3, 1 }
        local mode_label = mode_names[1]
        for i = 1, #mode_values do
            if mode_values[i] == bulk_route_mode then
                mode_label = mode_names[i]
                break
            end
        end
        if r.ImGui_BeginCombo(ctx, "Mode", mode_label) then
            for i = 1, #mode_names do
                if r.ImGui_Selectable(ctx, mode_names[i], bulk_route_mode == mode_values[i]) then
                    bulk_route_mode = mode_values[i]
                end
            end
            r.ImGui_EndCombo(ctx)
        end

        local cv, vv = r.ImGui_SliderDouble(ctx, "Vol", bulk_route_vol_db, -60, 12, "%.1f dB")
        if cv then bulk_route_vol_db = vv end
        local cp, vp = r.ImGui_SliderDouble(ctx, "Pan", bulk_route_pan, -1, 1, "%.2f")
        if cp then bulk_route_pan = vp end
        local cmu, vmu = r.ImGui_Checkbox(ctx, "Mute", bulk_route_mute)
        if cmu then bulk_route_mute = vmu end
        r.ImGui_SameLine(ctx)
        local cph, vph = r.ImGui_Checkbox(ctx, "Phase", bulk_route_phase)
        if cph then bulk_route_phase = vph end
        r.ImGui_SameLine(ctx)
        local cmo, vmo = r.ImGui_Checkbox(ctx, "Mono", bulk_route_mono)
        if cmo then bulk_route_mono = vmo end

        local can_apply = (#selected_tracks_now > 0) and target_track and r.ValidatePtr(target_track, "MediaTrack*")
        if can_apply then
            if r.ImGui_Button(ctx, "Apply settings", 120, 0) then
                BatchApplyBulkRouteSettings(
                    selected_tracks_now,
                    target_track,
                    bulk_route_create_missing,
                    bulk_route_mode,
                    bulk_route_vol_db,
                    bulk_route_pan,
                    bulk_route_mute,
                    bulk_route_phase,
                    bulk_route_mono
                )
            end
            r.ImGui_SameLine(ctx)
            if r.ImGui_Button(ctx, "Connect all", 100, 0) then
                BatchConnectSelectedToDestination(selected_tracks_now, target_track)
            end
            r.ImGui_SameLine(ctx)
            if r.ImGui_Button(ctx, "Disconnect all", 110, 0) then
                BatchDisconnectSelectedFromDestination(selected_tracks_now, target_track)
            end
        else
            r.ImGui_TextDisabled(ctx, "Choose destination track and keep selection active.")
        end

        if r.ImGui_Button(ctx, "Close", 100, 0) then
            r.ImGui_CloseCurrentPopup(ctx)
        end
        r.ImGui_EndPopup(ctx)
    end

    r.ImGui_SameLine(ctx)
    r.ImGui_PushItemWidth(ctx, 130)
    local ch_sn, v_sn = r.ImGui_InputTextWithHint(ctx, "##patchbay_snapshot_name", "Snapshot name", snapshot_name_input or "")
    if ch_sn then snapshot_name_input = v_sn end
    local snap_input_x2, snap_input_y1 = nil, nil
    if r.ImGui_GetItemRectMax and r.ImGui_GetItemRectMin then
        snap_input_x2 = select(1, r.ImGui_GetItemRectMax(ctx))
        snap_input_y1 = select(2, r.ImGui_GetItemRectMin(ctx))
    end
    r.ImGui_PopItemWidth(ctx)
    if snap_input_x2 and snap_input_y1 and r.ImGui_SetCursorScreenPos then
        r.ImGui_SetCursorScreenPos(ctx, snap_input_x2, snap_input_y1)
    else
        r.ImGui_SameLine(ctx)
    end
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), 2)
    local save_h = r.ImGui_GetFrameHeight(ctx)
    if r.ImGui_Button(ctx, "S##patchbay_snapshot_save", save_h, save_h) then
        local name = Trim(snapshot_name_input)
        if name ~= "" then
            SaveSnapshotNamed(name, cfg)
            snapshot_name_input = ""
        end
    end
    r.ImGui_PopStyleVar(ctx, 1)
    r.ImGui_SameLine(ctx)
    local snap_label = snapshot_selected_name or "Recall"
    r.ImGui_PushItemWidth(ctx, 130)
    local snap_flags = r.ImGui_ComboFlags_HeightLargest and r.ImGui_ComboFlags_HeightLargest() or 0
    if r.ImGui_GetCursorScreenPos and r.ImGui_GetFrameHeight and r.ImGui_SetNextWindowPos then
        local rx, ry = r.ImGui_GetCursorScreenPos(ctx)
        local cond = r.ImGui_Cond_Appearing and r.ImGui_Cond_Appearing() or 0
        r.ImGui_SetNextWindowPos(ctx, rx, ry + r.ImGui_GetFrameHeight(ctx) + 4, cond)
    end
    if r.ImGui_BeginCombo(ctx, "##patchbay_snapshot_recall", snap_label, snap_flags) then
        local delete_snapshot_name = nil
        if r.ImGui_BeginTable then
            if r.ImGui_BeginTable(ctx, "##patchbay_snapshot_recall_table", 2) then
                if r.ImGui_TableSetupColumn then
                    local stretch = r.ImGui_TableColumnFlags_WidthStretch and r.ImGui_TableColumnFlags_WidthStretch() or 0
                    local fixed = r.ImGui_TableColumnFlags_WidthFixed and r.ImGui_TableColumnFlags_WidthFixed() or 0
                    r.ImGui_TableSetupColumn(ctx, "Name", stretch)
                    r.ImGui_TableSetupColumn(ctx, "Del", fixed, 22)
                end
                for i = 1, #snapshot_names do
                    local nm = snapshot_names[i]
                    if r.ImGui_TableNextRow then r.ImGui_TableNextRow(ctx) end
                    if r.ImGui_TableSetColumnIndex then r.ImGui_TableSetColumnIndex(ctx, 0) end
                    if r.ImGui_Selectable(ctx, nm, snapshot_selected_name == nm) then
                        LoadSnapshotNamed(nm, cfg)
                    end
                    if r.ImGui_TableSetColumnIndex then r.ImGui_TableSetColumnIndex(ctx, 1) end
                    if r.ImGui_SmallButton and r.ImGui_SmallButton(ctx, "x##snapshot_del_" .. i) then
                        delete_snapshot_name = nm
                    end
                    if r.ImGui_IsItemHovered(ctx) then
                        r.ImGui_SetTooltip(ctx, "Delete snapshot")
                    end
                end
                r.ImGui_EndTable(ctx)
            end
        else
            for i = 1, #snapshot_names do
                local nm = snapshot_names[i]
                if r.ImGui_Selectable(ctx, nm, snapshot_selected_name == nm) then
                    LoadSnapshotNamed(nm, cfg)
                end
            end
        end
        if delete_snapshot_name then
            DeleteSnapshotNamed(delete_snapshot_name)
        end
        r.ImGui_EndCombo(ctx)
    end
    r.ImGui_PopItemWidth(ctx)
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

    local grid_bg_col = _G.patchbay_grid_bg_col or 0x1A1A1AFF
    local grid_dot_col = _G.patchbay_grid_dot_col or 0x2A2A2AFF
    r.ImGui_DrawList_AddRectFilled(draw_list, origin_x, origin_y, origin_x + avail_w, origin_y + avail_h, grid_bg_col)

    local g_step = GRID
    local gx0 = origin_x + ((canvas_offset_x % g_step) + g_step) % g_step
    local gy0 = origin_y + ((canvas_offset_y % g_step) + g_step) % g_step
    local x = gx0
    while x < origin_x + avail_w do
        local y = gy0
        while y < origin_y + avail_h do
            r.ImGui_DrawList_AddRectFilled(draw_list, x - 1, y - 1, x + 1, y + 1, grid_dot_col)
            y = y + g_step
        end
        x = x + g_step
    end

    r.ImGui_SetCursorScreenPos(ctx, origin_x, origin_y)
    if r.ImGui_SetNextItemAllowOverlap then r.ImGui_SetNextItemAllowOverlap(ctx) end
    r.ImGui_InvisibleButton(ctx, "##patchbay_bg", avail_w, avail_h)
    local bg_active = r.ImGui_IsItemActive(ctx)
    local bg_hovered = r.ImGui_IsItemHovered(ctx)

    if bg_active and dragging_node_guid == nil and pending_connection == nil and not layout_locked then
        local dx, dy = r.ImGui_GetMouseDragDelta(ctx, 0, 0, 0)
        if dx ~= 0 or dy ~= 0 then
            canvas_offset_x = canvas_offset_x + dx
            canvas_offset_y = canvas_offset_y + dy
            r.ImGui_ResetMouseDragDelta(ctx, 0)
            layout_dirty = true
        end
    end

    if r.ImGui_IsWindowHovered(ctx) and r.ImGui_IsMouseDragging(ctx, 2) and not layout_locked then
        local dx, dy = r.ImGui_GetMouseDragDelta(ctx, 2, 0, 0)
        if dx ~= 0 or dy ~= 0 then
            canvas_offset_x = canvas_offset_x + dx
            canvas_offset_y = canvas_offset_y + dy
            r.ImGui_ResetMouseDragDelta(ctx, 2)
            layout_dirty = true
        end
    end

    if r.ImGui_IsWindowHovered(ctx) and not layout_locked then
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

    if pending_fit_view then
        pending_fit_view = false
        if not layout_locked then
        local min_x, min_y, max_x, max_y
        for i = 1, #tracks do
            local p = node_positions[tracks[i].guid]
            if p then
                local x1, y1 = p.x, p.y
                local x2, y2 = p.x + NodeW(), p.y + NodeH(tracks[i].guid)
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
            local content_w = math.max(1, max_x - min_x)
            local content_h = math.max(1, max_y - min_y)
            local pad = 24
            local fit_w = math.max(1, avail_w - pad * 2)
            local fit_h = math.max(1, avail_h - pad * 2)
            local fit_zoom = math.min(fit_w / content_w, fit_h / content_h)
            if not fit_zoom or fit_zoom <= 0 then fit_zoom = 1.0 end
            canvas_zoom = math.max(MIN_ZOOM, math.min(MAX_ZOOM, fit_zoom))
            local bw = (max_x - min_x) * canvas_zoom
            local bh = (max_y - min_y) * canvas_zoom
            canvas_offset_x = (avail_w - bw) * 0.5 - min_x * canvas_zoom
            canvas_offset_y = (avail_h - bh) * 0.5 - min_y * canvas_zoom
            layout_dirty = true
        end
        end
    end

    if pending_center_view then
        pending_center_view = false
        if not layout_locked then
        local min_x, min_y, max_x, max_y
        for i = 1, #tracks do
            local p = node_positions[tracks[i].guid]
            if p then
                local x1, y1 = p.x, p.y
                local x2, y2 = p.x + NodeW(), p.y + NodeH(tracks[i].guid)
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
    end

    local guid_to = {}
    for i = 1, #tracks do guid_to[tracks[i].guid] = tracks[i] end

    local function NodeRect(g)
        local p = node_positions[g]
        if not p then return nil end
        local x1 = origin_x + canvas_offset_x + p.x * canvas_zoom
        local y1 = origin_y + canvas_offset_y + p.y * canvas_zoom
        return x1, y1, x1 + NodeW() * canvas_zoom, y1 + NodeH(g) * canvas_zoom
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
    local cfg = GetConfig()
    local cables = {}
    local master_in_view = guid_to[MASTER_GUID] ~= nil
    local master_track = master_in_view and guid_to[MASTER_GUID].track or nil
    local route_filter = cfg.patchbay_route_filter or "all"
    local selected_track = _G.TRACK
    local solo_path_enabled = (cfg.patchbay_solo_path == true) and selected_track and r.ValidatePtr(selected_track, "MediaTrack*")

    local function CablePassesFilter(is_main, mode, muted)
        if route_filter == "all" then return true end
        if route_filter == "muted" then return muted == true end
        if route_filter == "pre-fx" then return (not is_main) and mode == 1 end
        if route_filter == "pre-fader" then return (not is_main) and mode == 3 end
        if route_filter == "post-fader" then
            if is_main then return true end
            return mode == 0
        end
        return true
    end

    local function CablePassesSoloPath(src, dst)
        if not solo_path_enabled then return true end
        return src == selected_track or dst == selected_track
    end

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
                        local mode = r.GetTrackSendInfo_Value(src, 0, k, "I_SENDMODE")
                        local muted = r.GetTrackSendInfo_Value(src, 0, k, "B_MUTE") == 1
                        local phase = r.GetTrackSendInfo_Value(src, 0, k, "B_PHASE") == 1
                        local vol = r.GetTrackSendInfo_Value(src, 0, k, "D_VOL")
                        if CablePassesFilter(false, mode, muted) and CablePassesSoloPath(src, dst) then
                            cables[#cables + 1] = {
                                src = src, dst = dst, sg = sg, dg = dg, idx = k,
                                mode = mode, muted = muted, phase = phase, vol = vol
                            }
                        end
                    end
                end
            end
            if master_in_view and r.GetMediaTrackInfo_Value(src, "B_MAINSEND") == 1 then
                local mode = 0
                local muted = false
                local phase = false
                local vol = r.GetMediaTrackInfo_Value(src, "D_VOL")
                if CablePassesFilter(true, mode, muted) and CablePassesSoloPath(src, master_track) then
                    cables[#cables + 1] = {
                        src = src, dst = master_track, sg = sg, dg = MASTER_GUID, idx = -1, is_main = true,
                        mode = mode, muted = muted, phase = phase, vol = vol
                    }
                end
            end
        end
    end

    local solo_focus_guids = nil
    if solo_path_enabled then
        solo_focus_guids = {}
        for i = 1, #tracks do
            if tracks[i].track == selected_track then
                solo_focus_guids[tracks[i].guid] = true
                break
            end
        end
        for ci = 1, #cables do
            local c = cables[ci]
            if c.src == selected_track or c.dst == selected_track then
                solo_focus_guids[c.sg] = true
                solo_focus_guids[c.dg] = true
            end
        end
    end

    local hovered_cable = nil
    local cp_dist = 80 * canvas_zoom
    local show_flow = cfg.patchbay_show_flow ~= false
    local flow_time = r.time_precise()

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
            local mode = c.mode
            local muted = c.muted
            local phase = c.phase
            local vol = c.vol
            local thickness = 1.5 + math.min(2.5, math.max(0, (vol - 0.5)) * 1.5)
            if hovered_cable == c then thickness = thickness + 1 end
            local col, hcol = ModeColors(mode, muted)
            if c.is_main and not muted then
                col = 0xC69A42CC
                hcol = 0xDBB35AE0
            end
            local audit_sev = route_audit_visual_active and route_audit_cable_marks[c.sg .. "->" .. c.dg] or nil
            if audit_sev == "error" then
                col = 0xE34A4AE0
                hcol = 0xFF6E6EFF
                thickness = thickness + 1.5
            elseif audit_sev == "warn" then
                col = 0xE3A94AE0
                hcol = 0xFFC46EFF
                thickness = thickness + 0.8
            end
            local use_col = (hovered_cable == c) and hcol or col
            r.ImGui_DrawList_AddBezierCubic(draw_list, sx, sy, sx + cp_dist, sy, dx - cp_dist, dy, dx, dy, use_col, thickness)
            if show_flow then
                local t = (flow_time * 0.55 + ci * 0.137) % 1.0
                local fx, fy = BezierPoint(t, sx, sy, sx + cp_dist, sy, dx - cp_dist, dy, dx, dy)
                local dot_col
                if muted then
                    dot_col = 0x9A9A9AFF
                elseif hovered_cable == c then
                    dot_col = 0xFFFFFFFF
                else
                    dot_col = 0xE6E6E6FF
                end
                r.ImGui_DrawList_AddCircleFilled(draw_list, fx, fy, math.max(2.0, 2.8 * canvas_zoom), dot_col)
            end
            if phase and not muted then
                r.ImGui_DrawList_AddBezierCubic(draw_list, sx, sy, sx + cp_dist, sy, dx - cp_dist, dy, dx, dy, 0xFF4040FF, 1)
            end
        end
    end

    local request_open_popup = false
    local request_open_node_popup = false
    local node_right_click_consumed = false

    for i = 1, #tracks do
        local tr = tracks[i]
        local g = tr.guid
        local x1, y1, x2, y2 = NodeRect(g)
        if x1 then
            local node_w = NodeW() * canvas_zoom
            local node_h = NodeH(g) * canvas_zoom
            if mx >= x1 and mx < x1 + node_w and my >= y1 and my < y1 + node_h then
                if r.ImGui_IsMouseClicked(ctx, 1) then
                    node_right_click_consumed = true
                end
                break
            end
        end
    end
    
    if hovered_cable and not node_right_click_consumed then
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

    if not hovered_cable and not node_right_click_consumed and bg_hovered and not pb_rubber_active and pending_connection == nil and r.ImGui_IsMouseClicked(ctx, 1) then
        local mods = r.ImGui_GetKeyMods and r.ImGui_GetKeyMods(ctx) or 0
        local mod_shift = r.ImGui_Mod_Shift and r.ImGui_Mod_Shift() or 0
        local shift_held = (mods & mod_shift) ~= 0
        pb_rubber_additive = shift_held
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
            local in_solo_focus = (not solo_path_enabled) or (solo_focus_guids and solo_focus_guids[g] == true)
            local show_zoom_badge = canvas_zoom >= 0.75
            local show_zoom_stats = canvas_zoom >= 0.85
            local show_zoom_markers = canvas_zoom >= 0.70
            local show_zoom_ms = canvas_zoom >= 0.60

            local r8, g8, b8 = 96, 96, 96
            if not is_master_node then
                local tcol = r.GetTrackColor(tr.track)
                if tcol and tcol ~= 0 then r8, g8, b8 = r.ColorFromNative(tcol) end
            end

            local bar_col
            if is_master_node then
                bar_col = 0xD4AF37FF
            else
                bar_col = ((r8 & 0xFF) << 24) | ((g8 & 0xFF) << 16) | ((b8 & 0xFF) << 8) | 0xFF
            end
            if not in_solo_focus then
                if is_master_node then
                    bar_col = 0x6E5D37CC
                else
                    bar_col = ((r8 & 0xFF) << 24) | ((g8 & 0xFF) << 16) | ((b8 & 0xFF) << 8) | 0x66
                end
            end

            local body_col
            if is_master_node then
                body_col = is_selected and 0x3A3024FF or 0x2A2620FF
            else
                body_col = is_selected and 0x3A3F4AFF or (is_multi and 0x2A3340FF or 0x222428FF)
                if tr.folder_group_guid and tr.folder_group_guid ~= "" and (not is_selected) and (not is_multi) then
                    local fcol = FolderBodyColor(tr.folder_group_r, tr.folder_group_g, tr.folder_group_b, not in_solo_focus)
                    if fcol then body_col = fcol end
                end
            end
            if not in_solo_focus then
                body_col = is_master_node and 0x1F1D1BCC or 0x1A1B1ECC
                if (not is_master_node) and tr.folder_group_guid and tr.folder_group_guid ~= "" and (not is_selected) and (not is_multi) then
                    local fcol = FolderBodyColor(tr.folder_group_r, tr.folder_group_g, tr.folder_group_b, true)
                    if fcol then body_col = fcol end
                end
            end
            r.ImGui_DrawList_AddRectFilled(draw_list, x1, y1, x2, y2, body_col, 6)
            r.ImGui_DrawList_AddRectFilled(draw_list, x1, y1, x1 + 5, y2, bar_col, 6)
            local border
            if is_master_node then
                border = (is_selected and 0xFFD060FF) or (is_multi and 0xCCFF88FF) or 0x886633FF
            else
                border = (is_selected and 0x88BBFFFF) or (is_multi and 0xCCFF88FF) or 0x3A3A3AFF
            end
            if not in_solo_focus then
                border = 0x2C2C2CCC
            end
            r.ImGui_DrawList_AddRect(draw_list, x1, y1, x2, y2, border, 6, nil, (is_selected or is_multi) and 2 or 1)

            local label
            if is_master_node then
                label = "MASTER"
            else
                label = string.format("#%d  %s", tr.idx + 1, tr.name)
            end
            local trunc = TruncateText(ctx, label, NodeW() * canvas_zoom - 14)
            local label_col = is_master_node and 0xFFE090FF or 0xEEEEEEFF
            local node_is_pinned = pinned_nodes[g] == true
            local node_is_collapsed = collapsed_nodes[g] == true
            local folder_badge = nil
            if tr.folder_group_name and tr.folder_group_name ~= "" then
                folder_badge = tr.folder_group_name
            end
            if not in_solo_focus then
                label_col = 0x8A8A8ACC
            end
            r.ImGui_DrawList_AddText(draw_list, x1 + 10, y1 + 6, label_col, trunc)
            if node_is_pinned and show_zoom_markers then
                r.ImGui_DrawList_AddText(draw_list, x2 - 14, y1 + 6, 0xE0C050FF, "P")
            end
            if folder_badge and show_zoom_badge and not is_master_node and not node_is_collapsed then
                local bcol = in_solo_focus and 0x88D0FFFF or 0x5D7E8FCC
                local btxt = TruncateText(ctx, "[" .. folder_badge .. "]", NodeW() * canvas_zoom - 22)
                local by = y1 + 22
                r.ImGui_DrawList_AddText(draw_list, x1 + 10, by, bcol, btxt)
            end
            if folder_badge and show_zoom_markers and not is_master_node and node_is_collapsed then
                local bcol = in_solo_focus and 0x88D0FFFF or 0x5D7E8FCC
                local fx = node_is_pinned and (x2 - 30) or (x2 - 14)
                local ftxt = tr.folder_is_parent and "F" or "C"
                r.ImGui_DrawList_AddText(draw_list, fx, y1 + 6, bcol, ftxt)
            end

            if show_zoom_stats and not node_is_collapsed then
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
                local stats_max_w = (NodeW() * canvas_zoom) - 24
                if not is_master_node then stats_max_w = stats_max_w - (2 * (14 * canvas_zoom) + 10) end
                local stats_trunc = TruncateText(ctx, stats, stats_max_w)
                local stats_col = in_solo_focus and 0xAAAAAAFF or 0x676767CC
                r.ImGui_DrawList_AddText(draw_list, x1 + 10, y2 - 18, stats_col, stats_trunc)
            end

            local in_x, in_y = PinPos(g, "in")
            local out_x, out_y = PinPos(g, "out")
            local pin_r = PIN_R * canvas_zoom
            if pin_r < 4 then pin_r = 4 end

            r.ImGui_PushID(ctx, "node_" .. g)

            r.ImGui_SetCursorScreenPos(ctx, x1, y1)
            if r.ImGui_SetNextItemAllowOverlap then r.ImGui_SetNextItemAllowOverlap(ctx) end
            r.ImGui_InvisibleButton(ctx, "##body", NodeW() * canvas_zoom, NodeH(g) * canvas_zoom)
            local body_active = r.ImGui_IsItemActive(ctx)
            local body_hovered = r.ImGui_IsItemHovered(ctx)
            if body_hovered and r.ImGui_IsMouseClicked(ctx, 1) then
                node_right_click_consumed = true
                if not is_master_node then
                    node_popup_track = tr.track
                    node_popup_guid = g
                    request_open_node_popup = true
                end
            end
            if body_hovered and r.ImGui_IsMouseClicked(ctx, 0) then
                local mods = r.ImGui_GetKeyMods and r.ImGui_GetKeyMods(ctx) or 0
                local mod_ctrl = r.ImGui_Mod_Ctrl and r.ImGui_Mod_Ctrl() or 0
                local ctrl_held = (mods & mod_ctrl) ~= 0

                if is_master_node then
                    pb_selected_set = {}
                elseif ctrl_held then
                    if pb_selected_set[g] then
                        pb_selected_set[g] = nil
                    else
                        pb_selected_set[g] = true
                    end
                else
                    if not pb_selected_set[g] then
                        pb_selected_set = { [g] = true }
                    end
                end

                if is_master_node then
                    local nt = r.CountTracks(0)
                    for ti = 0, nt - 1 do
                        r.SetMediaTrackInfo_Value(r.GetTrack(0, ti), "I_SELECTED", 0)
                    end
                    r.SetMediaTrackInfo_Value(tr.track, "I_SELECTED", 1)
                    _G.TRACK = tr.track
                    r.UpdateArrange()
                else
                    r.SetOnlyTrackSelected(tr.track)
                    _G.TRACK = tr.track
                    if r.SetMixerScroll then r.SetMixerScroll(tr.track) end
                    r.UpdateArrange()
                end
                if not ctrl_held then
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
                    if hit_out and not all_locked then
                        pending_connection = { src = hit_out.track, src_guid = hit_out.guid }
                    else
                        pb_press_guid = g
                        pb_press_dragged = false
                    end
                end
            end
            if body_active and pending_connection == nil and not layout_locked then
                local ddx, ddy = r.ImGui_GetMouseDragDelta(ctx, 0, 0, 0)
                if ddx ~= 0 or ddy ~= 0 then
                    if not node_is_pinned then
                        dragging_node_guid = g
                        pb_press_dragged = true
                        local dwx = ddx / canvas_zoom
                        local dwy = ddy / canvas_zoom
                        if pb_selected_set[g] then
                            for sg, _ in pairs(pb_selected_set) do
                                if (not pinned_nodes[sg]) and node_positions[sg] then
                                    node_positions[sg].x = node_positions[sg].x + dwx
                                    node_positions[sg].y = node_positions[sg].y + dwy
                                end
                            end
                        else
                            node_positions[g].x = node_positions[g].x + dwx
                            node_positions[g].y = node_positions[g].y + dwy
                        end
                        layout_dirty = true
                    else
                        pb_press_dragged = false
                    end
                    r.ImGui_ResetMouseDragDelta(ctx, 0)
                end
            end
            if show_zoom_ms and not is_master_node and not node_is_collapsed then
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
                if r.ImGui_IsItemClicked(ctx, 0) and not all_locked then
                    r.Undo_BeginBlock()
                    r.SetMediaTrackInfo_Value(tr.track, "B_MUTE", mute_on and 0 or 1)
                    r.Undo_EndBlock("Patchbay: toggle mute", -1)
                end

                if r.ImGui_SetNextItemAllowOverlap then r.ImGui_SetNextItemAllowOverlap(ctx) end
                r.ImGui_SetCursorScreenPos(ctx, s_x1, btn_y1)
                r.ImGui_InvisibleButton(ctx, "##solo_btn", btn_size, btn_size)
                if r.ImGui_IsItemClicked(ctx, 0) and not all_locked then
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
                if r.ImGui_IsItemActive(ctx) and not all_locked then
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
                if hovered_input_guid == MASTER_GUID and not all_locked then
                    if r.GetMediaTrackInfo_Value(pending_connection.src, "B_MAINSEND") ~= 1 then
                        r.Undo_BeginBlock()
                        r.SetMediaTrackInfo_Value(pending_connection.src, "B_MAINSEND", 1)
                        r.Undo_EndBlock("Patchbay: enable main send", -1)
                    end
                elseif not all_locked then
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
            local is_click_only = math.abs(cmx - pb_rubber_start_x) < 3 and math.abs(cmy - pb_rubber_start_y) < 3
            if is_click_only and not pb_rubber_additive then
                pb_selected_set = {}
                local nt = r.CountTracks(0)
                for ti = 0, nt - 1 do
                    r.SetMediaTrackInfo_Value(r.GetTrack(0, ti), "I_SELECTED", 0)
                end
                _G.TRACK = nil
                r.UpdateArrange()
            else
                for i = 1, #tracks do
                    local g2 = tracks[i].guid
                    local nx1, ny1, nx2, ny2 = NodeRect(g2)
                    if nx1 and not (nx2 < rx1 or nx1 > rx2 or ny2 < ry1 or ny1 > ry2) then
                        pb_selected_set[g2] = true
                    end
                end
            end
            pb_rubber_additive = false
            pb_rubber_active = false
        end
    end

    if r.ImGui_IsMouseReleased(ctx, 0) then
        pb_press_guid = nil
        pb_press_dragged = false
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
        local hint = "Left-click node = select  |  Drag node = move  |  Drag pin = connect  |  Left-drag empty = pan  |  Right-drag empty = select (Shift = add)  |  Wheel = zoom  |  Right-click cable = options  |  Route filter + Solo path in toolbar"
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
    if request_open_node_popup then
        r.ImGui_OpenPopup(ctx, "PatchbayNodePopup")
    end
    RenderRightClickPopup()
    RenderNodePopup()
end
