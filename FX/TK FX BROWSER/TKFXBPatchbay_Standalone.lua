local r = reaper

local PB = {}

local NODE_W_DEFAULT = 180
local NODE_H = 72
local NODE_H_COLLAPSED = 30
local PIN_R = 6
local ROW_H = 92
local GRID = 40
local MASTER_GUID = "__MASTER__"

local function IsMasterEntry(tr) return tr and tr.is_master end
local GetSendIndexLocal
local GetCtx
local GetConfig
local GetLayoutPreset
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
local pending_folder_connection = nil
local right_click_send = nil
local layout_dirty = false
local layout_loaded_project = nil
local last_save_time = 0
local hovered_input_guid = nil
local pending_auto_layout = false
local pending_center_view = false
local pending_fit_view = false
local pending_spawn_nodes = nil
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
local group_names = {}
local group_map = {}
local active_group_name = nil
local group_name_input = ""
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
local popup_templates_x = nil
local popup_templates_y = nil
local open_toolbar_popup_id = nil
local patchbay_template_cache = nil
local patchbay_template_cache_root = nil
local patchbay_template_cache_exists = false
local patchbay_template_cache_dirty = true
local cable_shop_open = false
local view_help_open = false
local cable_shop_selected = "post_fader"
local cable_shop_user_slot = 1
local cable_shop_user_name = "Preset 1"
PB.fx_schema_open_guid = nil
PB.fx_schema_monochrome = true
PB.fx_schema_mouse_block = false
PB.tcp_mirror_enabled = false
PB.tcp_mirror_original = nil
PB.external_action_serial = ""
PB.open_route_audit_popup = false

local ROUTE_FILTER_ORDER = { "all", "post-fader", "pre-fader", "pre-fx", "muted", "audio", "sidechain", "midi" }
local ROUTE_FILTER_LABELS = {
    ["all"] = "All",
    ["post-fader"] = "Post-Fader",
    ["pre-fader"] = "Pre-Fader",
    ["pre-fx"] = "Pre-FX",
    ["muted"] = "Muted only",
    ["audio"] = "Audio 1/2",
    ["sidechain"] = "Sidechain",
    ["midi"] = "MIDI"
}

local CABLE_SHOP_ORDER = { "post_fader", "pre_fader", "pre_fx", "muted", "main", "folder_links", "sidechain", "midi", "phase" }
local CABLE_SHOP_LABELS = {
    post_fader = "Post-Fader",
    pre_fader = "Pre-Fader",
    pre_fx = "Pre-FX",
    muted = "Muted",
    main = "Main",
    folder_links = "Folder connections",
    sidechain = "Sidechain overlay",
    midi = "MIDI stripes",
    phase = "Phase overlay"
}
local CABLE_SHOP_DEFAULTS = {
    post_fader = { color = 0x4FB0C8FF, hover = 0x70D0E0FF, thickness = 1.5, visible = true },
    pre_fader = { color = 0xDDA050FF, hover = 0xF0C070FF, thickness = 1.7, visible = true },
    pre_fx = { color = 0xB070D0FF, hover = 0xC890E0FF, thickness = 1.7, visible = true },
    muted = { color = 0x666666AA, hover = 0x888888FF, thickness = 1.2, visible = true },
    main = { color = 0xC69A42CC, hover = 0xDBB35AE0, thickness = 1.8, visible = true },
    folder_links = { color = 0x66CC88AA, hover = 0x88FFAAFF, thickness = 1.6, visible = true },
    sidechain = { color = 0x65B872FF, hover = 0x88D894FF, thickness = 2.0, visible = true },
    midi = { color = 0x4F8FD8FF, hover = 0x76AAE8FF, thickness = 1.6, visible = true },
    phase = { color = 0xFF4040FF, hover = 0xFF7070FF, thickness = 1.0, visible = true }
}
local CABLE_SHOP_USER_PRESET_SLOTS = 6

local LAYOUT_PRESET_ORDER = { "compact", "hybrid", "wide", "folder_tree", "folder_tree_compact", "folder_tree_horizontal" }
local LAYOUT_PRESET_LABELS = {
    compact = "Compact",
    hybrid = "Standard",
    wide = "Wide",
    folder_tree = "Folder Tree",
    folder_tree_compact = "Folder Tree Compact",
    folder_tree_horizontal = "Folder Tree Horizontal"
}
local LAYOUT_PRESET_GAPS = {
    compact = { col = 36, row = 64 },
    hybrid = { col = 60, row = 80 },
    wide = { col = 96, row = 108 },
    folder_tree = { col = 72, row = 98 },
    folder_tree_compact = { col = 36, row = 72 },
    folder_tree_horizontal = { col = 128, row = 76 }
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

local function PathJoin(a, b)
    if not a or a == "" then return b or "" end
    if not b or b == "" then return a end
    if a:sub(-1) == "/" or a:sub(-1) == "\\" then return a .. b end
    return a .. "/" .. b
end

local function PathExists(path)
    if not path or path == "" then return false end
    local first_file = r.EnumerateFiles(path, 0)
    if first_file then return true end
    local first_sub = r.EnumerateSubdirectories(path, 0)
    if first_sub then return true end
    local ok, _, code = os.rename(path, path)
    return ok == true or code == 13
end

local function FileExists(path)
    if not path or path == "" then return false end
    if r.file_exists and r.file_exists(path) then return true end
    local f = io.open(path, "rb")
    if f then f:close(); return true end
    return false
end

local function ResolvePatchbayTrackTemplatesRoot()
    local cfg = GetConfig()
    if cfg and cfg.use_custom_template_dir == true and type(cfg.custom_template_dir) == "string" and cfg.custom_template_dir ~= "" then
        return cfg.custom_template_dir
    end
    return r.GetResourcePath() .. "/TrackTemplates"
end

local function BuildPatchbayTemplateList(root)
    local out = {}
    local ext = ".RTrackTemplate"
    local function scan(dir, rel)
        for i = 0, 999 do
            local sub = r.EnumerateSubdirectories(dir, i)
            if not sub or sub == "" then break end
            scan(PathJoin(dir, sub), rel == "" and sub or PathJoin(rel, sub))
        end
        for i = 0, 9999 do
            local file = r.EnumerateFiles(dir, i)
            if not file or file == "" then break end
            if file:sub(-#ext):lower() == ext:lower() then
                local name = file:sub(1, #file - #ext)
                local folder = rel or ""
                out[#out + 1] = {
                    name = name,
                    folder = folder,
                    label = folder ~= "" and (folder:gsub("\\", "/") .. " / " .. name) or name,
                    full_path = PathJoin(dir, file)
                }
            end
        end
    end
    if root and root ~= "" and PathExists(root) then scan(root, "") end
    table.sort(out, function(a, b) return (a.label or ""):lower() < (b.label or ""):lower() end)
    return out
end

local function GetPatchbayTemplateList(force)
    local root = ResolvePatchbayTrackTemplatesRoot()
    if force or patchbay_template_cache_dirty or patchbay_template_cache_root ~= root or not patchbay_template_cache then
        patchbay_template_cache_root = root
        patchbay_template_cache_exists = PathExists(root)
        patchbay_template_cache = patchbay_template_cache_exists and BuildPatchbayTemplateList(root) or {}
        patchbay_template_cache_dirty = false
    end
    return patchbay_template_cache or {}, patchbay_template_cache_root, patchbay_template_cache_exists
end

local function GetPatchbayInsertIndex()
    local insert_idx = r.CountTracks(0)
    if _G.TRACK and r.ValidatePtr(_G.TRACK, "MediaTrack*") and _G.TRACK ~= r.GetMasterTrack(0) then
        local tnum = math.floor(r.GetMediaTrackInfo_Value(_G.TRACK, "IP_TRACKNUMBER") or 0)
        if tnum > 0 then insert_idx = tnum end
    end
    return insert_idx
end

local function FindTrackByGuidLocal(guid)
    if not guid or guid == "" then return nil end
    local n = r.CountTracks(0)
    for i = 0, n - 1 do
        local tr = r.GetTrack(0, i)
        if tr and r.ValidatePtr(tr, "MediaTrack*") and r.GetTrackGUID(tr) == guid then return tr end
    end
    return nil
end

local function RegisterPatchbaySpawnNode(guid, spawn, order)
    if not guid or guid == "" then return end
    pending_spawn_nodes = pending_spawn_nodes or {}
    spawn = spawn or {}
    pending_spawn_nodes[guid] = {
        mode = spawn.mode or "visible",
        screen_x = spawn.screen_x,
        screen_y = spawn.screen_y,
        order = order or 1
    }
end

local function GetPatchbayMouseSpawn(ctx)
    if r.ImGui_GetMousePos then
        local x, y = r.ImGui_GetMousePos(ctx)
        if x and y then return { mode = "mouse", screen_x = x, screen_y = y } end
    end
    return { mode = "visible" }
end

local function InsertPatchbayTrackTemplate(full_path, spawn)
    if IsAllLockedCfg(GetConfig()) then return end
    if not FileExists(full_path) then
        r.ShowConsoleMsg("Track template not found: " .. tostring(full_path) .. "\n")
        return
    end
    local insert_idx = GetPatchbayInsertIndex()
    local old_count = r.CountTracks(0)
    local before = {}
    for i = 0, old_count - 1 do
        local tr = r.GetTrack(0, i)
        if tr and r.ValidatePtr(tr, "MediaTrack*") then before[r.GetTrackGUID(tr)] = true end
    end
    if old_count > 0 then
        local anchor_idx = math.max(0, math.min(old_count - 1, insert_idx - 1))
        local anchor = r.GetTrack(0, anchor_idx)
        if anchor and r.ValidatePtr(anchor, "MediaTrack*") then r.SetOnlyTrackSelected(anchor) end
    end
    r.PreventUIRefresh(1)
    r.Undo_BeginBlock()
    r.Main_openProject(full_path, 1)
    local new_guids = {}
    local first_new = nil
    local new_count = r.CountTracks(0)
    for i = 0, new_count - 1 do
        local tr = r.GetTrack(0, i)
        if tr and r.ValidatePtr(tr, "MediaTrack*") then
            local guid = r.GetTrackGUID(tr)
            if not before[guid] then
                new_guids[#new_guids + 1] = guid
                if not first_new then first_new = tr end
            end
        end
    end
    if #new_guids > 0 then
        for i = 0, r.CountTracks(0) - 1 do
            r.SetMediaTrackInfo_Value(r.GetTrack(0, i), "I_SELECTED", 0)
        end
        for i = 1, #new_guids do
            local tr = FindTrackByGuidLocal(new_guids[i])
            if tr and r.ValidatePtr(tr, "MediaTrack*") then r.SetMediaTrackInfo_Value(tr, "I_SELECTED", 1) end
        end
        if r.ReorderSelectedTracks and insert_idx < old_count then
            r.ReorderSelectedTracks(insert_idx, 0)
        end
        first_new = FindTrackByGuidLocal(new_guids[1]) or first_new
        if first_new and r.ValidatePtr(first_new, "MediaTrack*") then _G.TRACK = first_new end
        for i = 1, #new_guids do
            RegisterPatchbaySpawnNode(new_guids[i], spawn or { mode = "visible" }, i)
        end
    end
    r.Undo_EndBlock("Patchbay: insert track template", -1)
    r.PreventUIRefresh(-1)
    r.TrackList_AdjustWindows(false)
    r.UpdateArrange()
    layout_dirty = true
end

local function AddPatchbayTrack(spawn)
    if IsAllLockedCfg(GetConfig()) then return end
    local insert_idx = GetPatchbayInsertIndex()
    r.Undo_BeginBlock()
    r.InsertTrackAtIndex(insert_idx, true)
    local tr = r.GetTrack(0, insert_idx)
    if tr and r.ValidatePtr(tr, "MediaTrack*") then
        r.SetOnlyTrackSelected(tr)
        _G.TRACK = tr
        RegisterPatchbaySpawnNode(r.GetTrackGUID(tr), spawn or { mode = "visible" }, 1)
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

local function RenamePatchbayTrack(tr)
    if IsAllLockedCfg(GetConfig()) then return end
    if not tr or not r.ValidatePtr(tr, "MediaTrack*") then return end
    if tr == r.GetMasterTrack(0) then return end
    local _, name = r.GetTrackName(tr)
    local ok, new_name = r.GetUserInputs("Rename Track", 1, "Name:", name or "")
    if not ok then return end
    if new_name == name then return end
    r.Undo_BeginBlock()
    r.GetSetMediaTrackInfo_String(tr, "P_NAME", new_name, true)
    r.TrackList_AdjustWindows(false)
    r.UpdateArrange()
    r.Undo_EndBlock("Patchbay: rename track", -1)
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

local function GetPatchbayControlTargetTracks(track, guid, name)
    if guid and pb_selected_set[guid] then
        local selected_tracks = GetSelectedPatchbayTracks()
        if #selected_tracks > 0 then return selected_tracks end
    end
    return { { track = track, guid = guid, name = name } }
end

local function IsPatchbayTrackFrozen(track)
    if not track or not r.ValidatePtr(track, "MediaTrack*") then return false end
    return r.GetMediaTrackInfo_Value(track, "I_FREEZECOUNT") > 0
end

function PatchbaySyncSelectedSetToTCP(focus_track)
    local focus = nil
    local has_selection = false
    local n = r.CountTracks(0)
    for i = 0, n - 1 do
        local tr = r.GetTrack(0, i)
        if tr and r.ValidatePtr(tr, "MediaTrack*") then
            local g = r.GetTrackGUID(tr)
            local selected = pb_selected_set[g] == true
            r.SetMediaTrackInfo_Value(tr, "I_SELECTED", selected and 1 or 0)
            if selected then
                has_selection = true
                if focus_track == tr then focus = tr end
                if not focus then focus = tr end
            end
        end
    end
    local master = r.GetMasterTrack(0)
    if master and r.ValidatePtr(master, "MediaTrack*") then
        local selected = pb_selected_set[MASTER_GUID] == true
        r.SetMediaTrackInfo_Value(master, "I_SELECTED", selected and 1 or 0)
        if selected then
            has_selection = true
            if focus_track == master then focus = master end
            if not focus then focus = master end
        end
    end
    _G.TRACK = has_selection and focus or nil
    if _G.TRACK and _G.TRACK ~= master and r.SetMixerScroll then r.SetMixerScroll(_G.TRACK) end
    r.UpdateArrange()
end

function PatchbaySyncTCPSelectionToSelectedSet()
    pb_selected_set = {}
    local n = r.CountTracks(0)
    for i = 0, n - 1 do
        local tr = r.GetTrack(0, i)
        if tr and r.ValidatePtr(tr, "MediaTrack*") and r.GetMediaTrackInfo_Value(tr, "I_SELECTED") == 1 then
            pb_selected_set[r.GetTrackGUID(tr)] = true
        end
    end
    _G.TRACK = r.GetSelectedTrack(0, 0)
    layout_dirty = true
end

function PatchbayMarkSelectedTracksForVisiblePlacement()
    local pending = {}
    local count = 0
    for guid, selected in pairs(pb_selected_set) do
        if selected and guid ~= MASTER_GUID and not node_positions[guid] then
            pending[guid] = true
            count = count + 1
        end
    end
    PB.pending_paste_visible_guids = count > 0 and pending or nil
end

function PatchbayMarkSelectedTracksForSpawnPlacement(spawn)
    local selected_tracks = GetSelectedPatchbayTracks()
    local order = 0
    for i = 1, #selected_tracks do
        local guid = selected_tracks[i].guid
        if guid and guid ~= MASTER_GUID and not node_positions[guid] then
            order = order + 1
            RegisterPatchbaySpawnNode(guid, spawn, order)
        end
    end
end

function PatchbayFocusNativeTrackContext(track)
    if r.SetCursorContext then r.SetCursorContext(0, nil) end
    if track and r.ValidatePtr(track, "MediaTrack*") then _G.TRACK = track end
end

function PatchbayCopySelectedTracks()
    local selected_tracks = GetSelectedPatchbayTracks()
    if #selected_tracks == 0 then return false end
    PatchbaySyncSelectedSetToTCP(selected_tracks[1].track)
    PatchbayFocusNativeTrackContext(selected_tracks[1].track)
    r.Main_OnCommand(40210, 0)
    return true
end

function PatchbayCopyNodeTracks(track, guid)
    if guid and guid ~= MASTER_GUID and pb_selected_set[guid] ~= true then
        pb_selected_set = { [guid] = true }
    end
    return PatchbayCopySelectedTracks()
end

function PatchbayPasteTracks(spawn)
    if IsAllLockedCfg(GetConfig()) then return false end
    local selected_tracks = GetSelectedPatchbayTracks()
    if #selected_tracks > 0 then PatchbaySyncSelectedSetToTCP(selected_tracks[1].track) end
    PatchbayFocusNativeTrackContext(selected_tracks[1] and selected_tracks[1].track or _G.TRACK)
    r.Main_OnCommand(42398, 0)
    PatchbaySyncTCPSelectionToSelectedSet()
    if spawn then
        PatchbayMarkSelectedTracksForSpawnPlacement(spawn)
    else
        PatchbayMarkSelectedTracksForVisiblePlacement()
    end
    r.TrackList_AdjustWindows(false)
    r.UpdateArrange()
    return true
end

function PatchbayPasteTracksAtNode(track, guid, spawn)
    if guid and guid ~= MASTER_GUID and pb_selected_set[guid] ~= true then
        pb_selected_set = { [guid] = true }
    end
    return PatchbayPasteTracks(spawn)
end

local function GetTrackIndexLocal(tr)
    if not tr or not r.ValidatePtr(tr, "MediaTrack*") then return -1 end
    local n = r.CountTracks(0)
    for i = 0, n - 1 do
        if r.GetTrack(0, i) == tr then return i end
    end
    return -1
end

local function GetFolderNestingBeforeIndex(idx)
    local depth = 0
    for i = 0, idx - 1 do
        local tr = r.GetTrack(0, i)
        if tr and r.ValidatePtr(tr, "MediaTrack*") then
            depth = depth + math.floor(r.GetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH") or 0)
            if depth < 0 then depth = 0 end
        end
    end
    return depth
end

local function GetFolderRangeLocal(parent)
    local parent_idx = GetTrackIndexLocal(parent)
    if parent_idx < 0 then return nil, nil end
    local parent_depth = math.floor(r.GetMediaTrackInfo_Value(parent, "I_FOLDERDEPTH") or 0)
    if parent_depth <= 0 then return parent_idx, nil end
    local base_depth = GetFolderNestingBeforeIndex(parent_idx)
    local depth = base_depth
    local n = r.CountTracks(0)
    for i = parent_idx, n - 1 do
        local tr = r.GetTrack(0, i)
        if tr and r.ValidatePtr(tr, "MediaTrack*") then
            depth = depth + math.floor(r.GetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH") or 0)
            if i > parent_idx and depth <= base_depth then return parent_idx, i end
        end
    end
    return parent_idx, nil
end

local function GetDirectFolderParentLocal(tr)
    local idx = GetTrackIndexLocal(tr)
    if idx <= 0 then return nil, idx end
    local stack = {}
    for i = 0, idx - 1 do
        local cur = r.GetTrack(0, i)
        if cur and r.ValidatePtr(cur, "MediaTrack*") then
            local depth = math.floor(r.GetMediaTrackInfo_Value(cur, "I_FOLDERDEPTH") or 0)
            if depth > 0 then
                for _ = 1, depth do stack[#stack + 1] = cur end
            elseif depth < 0 then
                for _ = 1, -depth do
                    if #stack > 0 then table.remove(stack) end
                end
            end
        end
    end
    return stack[#stack], idx
end

local function MarkFolderLayoutChanged()
    layout_dirty = true
    local cfg = GetConfig and GetConfig() or _G.config
    if cfg and PatchbayLayoutKind(GetLayoutPreset(cfg)) == "folder" then
        pending_auto_layout = true
        pending_center_view = true
    end
end

local function PrepareSimpleFolderChildren(parent, selected_tracks)
    if not r.ReorderSelectedTracks then return nil, "ReorderSelectedTracks is not available." end
    if not parent or not r.ValidatePtr(parent, "MediaTrack*") then return nil, "Invalid parent track." end
    if parent == r.GetMasterTrack(0) then return nil, "MASTER cannot be a folder parent." end
    local parent_idx = GetTrackIndexLocal(parent)
    if parent_idx < 0 then return nil, "Parent track not found." end
    local parent_depth = math.floor(r.GetMediaTrackInfo_Value(parent, "I_FOLDERDEPTH") or 0)
    local append_existing = parent_depth > 0
    local folder_end_idx = nil
    if parent_depth > 1 then
        return nil, "This first version only supports simple folder parents."
    end
    if append_existing then
        _, folder_end_idx = GetFolderRangeLocal(parent)
        if not folder_end_idx then return nil, "Existing folder range could not be resolved." end
    end
    local parent_guid = r.GetTrackGUID(parent)
    local children = {}
    local seen = {}
    for i = 1, #(selected_tracks or {}) do
        local child = selected_tracks[i].track
        local guid = selected_tracks[i].guid
        if child and r.ValidatePtr(child, "MediaTrack*") and guid ~= parent_guid and not seen[guid] then
            local child_idx = GetTrackIndexLocal(child)
            local child_depth = math.floor(r.GetMediaTrackInfo_Value(child, "I_FOLDERDEPTH") or 0)
            if child == r.GetMasterTrack(0) then
                return nil, "MASTER cannot be assigned as a child."
            end
            if child_idx < 0 then
                return nil, "Selected child track not found."
            end
            if child_depth < 0 then
                return nil, "Selected child closes a folder. Select the folder parent instead."
            end
            local block_start_idx = child_idx
            local block_end_idx = child_idx
            if child_depth > 0 then
                _, block_end_idx = GetFolderRangeLocal(child)
                if not block_end_idx then return nil, "Selected folder range could not be resolved." end
            end
            if parent_idx >= block_start_idx and parent_idx <= block_end_idx then
                return nil, "Cannot assign a parent inside its own child folder."
            end
            if append_existing and folder_end_idx and child_idx > parent_idx and child_idx <= folder_end_idx then
                return nil, "Selected child is already inside this folder."
            end
            local block_guids = {}
            for j = block_start_idx, block_end_idx do
                local block_track = r.GetTrack(0, j)
                if block_track and r.ValidatePtr(block_track, "MediaTrack*") then
                    local block_guid = r.GetTrackGUID(block_track)
                    if seen[block_guid] then return nil, "Selected folder blocks overlap." end
                    seen[block_guid] = true
                    block_guids[#block_guids + 1] = block_guid
                end
            end
            children[#children + 1] = { guid = guid, track = child, block_guids = block_guids, block_last_guid = block_guids[#block_guids] }
        end
    end
    if #children == 0 then return nil, "Select one or more other nodes first." end
    return children, nil, append_existing, parent_depth
end

local function AssignSelectedTracksAsFolderChildren(parent, selected_tracks)
    if IsAllLockedCfg(GetConfig()) then return end
    local children, err, append_existing, parent_start_depth = PrepareSimpleFolderChildren(parent, selected_tracks)
    if not children then
        r.ShowMessageBox(err or "Could not assign folder children.", "Patchbay Folder", 0)
        return
    end
    local parent_guid = r.GetTrackGUID(parent)
    local move_guids = {}
    for i = 1, #children do
        for j = 1, #children[i].block_guids do
            move_guids[#move_guids + 1] = children[i].block_guids[j]
        end
    end
    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)
    for i = 0, r.CountTracks(0) - 1 do
        r.SetMediaTrackInfo_Value(r.GetTrack(0, i), "I_SELECTED", 0)
    end
    for i = 1, #move_guids do
        local child = FindTrackByGuidLocal(move_guids[i])
        if child and r.ValidatePtr(child, "MediaTrack*") then
            r.SetMediaTrackInfo_Value(child, "I_SELECTED", 1)
        end
    end
    local parent_now = FindTrackByGuidLocal(parent_guid)
    if append_existing then
        local _, folder_end_idx = GetFolderRangeLocal(parent_now)
        if folder_end_idx then r.ReorderSelectedTracks(folder_end_idx + 1, 0) end
        parent_now = FindTrackByGuidLocal(parent_guid)
        local _, refreshed_end_idx = GetFolderRangeLocal(parent_now)
        local ordered_children = {}
        for i = 1, #children do
            local child = FindTrackByGuidLocal(children[i].guid)
            local child_idx = GetTrackIndexLocal(child)
            if child and child_idx >= 0 then ordered_children[#ordered_children + 1] = { track = child, idx = child_idx, block_last_guid = children[i].block_last_guid } end
        end
        table.sort(ordered_children, function(a, b) return a.idx < b.idx end)
        local ordered_moved = {}
        for i = 1, #move_guids do
            local moved = FindTrackByGuidLocal(move_guids[i])
            local moved_idx = GetTrackIndexLocal(moved)
            if moved and moved_idx >= 0 then ordered_moved[#ordered_moved + 1] = { track = moved, idx = moved_idx } end
        end
        table.sort(ordered_moved, function(a, b) return a.idx < b.idx end)
        local contiguous = refreshed_end_idx ~= nil and #ordered_children == #children and #ordered_moved == #move_guids
        if contiguous then
            for i = 1, #ordered_moved do
                if ordered_moved[i].idx ~= refreshed_end_idx + i then contiguous = false; break end
            end
        end
        if not contiguous then
            r.PreventUIRefresh(-1)
            r.TrackList_AdjustWindows(false)
            r.UpdateArrange()
            r.Undo_EndBlock("Patchbay: move folder children", -1)
            r.ShowMessageBox("Selected tracks were moved, but the existing folder range could not be verified. Undo and try again.", "Patchbay Folder", 0)
            return
        end
        local closer = r.GetTrack(0, refreshed_end_idx)
        local closer_depth = closer and math.floor(r.GetMediaTrackInfo_Value(closer, "I_FOLDERDEPTH") or 0) or 0
        if not closer or not r.ValidatePtr(closer, "MediaTrack*") or closer_depth >= 0 then
            r.PreventUIRefresh(-1)
            r.TrackList_AdjustWindows(false)
            r.UpdateArrange()
            r.Undo_EndBlock("Patchbay: move folder children", -1)
            r.ShowMessageBox("Selected tracks were moved, but the folder closing track could not be verified. Undo and try again.", "Patchbay Folder", 0)
            return
        end
        if closer and r.ValidatePtr(closer, "MediaTrack*") then
            r.SetMediaTrackInfo_Value(closer, "I_FOLDERDEPTH", 0)
        end
        local last_child = ordered_children[#ordered_children]
        if last_child then
            local closer_child = FindTrackByGuidLocal(last_child.block_last_guid)
            if closer_child and r.ValidatePtr(closer_child, "MediaTrack*") then
                local depth = math.floor(r.GetMediaTrackInfo_Value(closer_child, "I_FOLDERDEPTH") or 0)
                r.SetMediaTrackInfo_Value(closer_child, "I_FOLDERDEPTH", depth + closer_depth)
            end
        end
        for i = 1, #move_guids do
            local child = FindTrackByGuidLocal(move_guids[i])
            if child and r.ValidatePtr(child, "MediaTrack*") then r.SetMediaTrackInfo_Value(child, "I_SELECTED", 1) end
        end
        r.PreventUIRefresh(-1)
        r.TrackList_AdjustWindows(false)
        r.UpdateArrange()
        r.Undo_EndBlock("Patchbay: add folder children", -1)
        _G.TRACK = FindTrackByGuidLocal(parent_guid) or _G.TRACK
        MarkFolderLayoutChanged()
        return
    end
    local parent_idx = GetTrackIndexLocal(parent_now)
    if parent_idx >= 0 then r.ReorderSelectedTracks(parent_idx + 1, 0) end
    parent_now = FindTrackByGuidLocal(parent_guid)
    parent_idx = GetTrackIndexLocal(parent_now)
    local ordered_children = {}
    for i = 1, #children do
        local child = FindTrackByGuidLocal(children[i].guid)
        local child_idx = GetTrackIndexLocal(child)
        if child and child_idx >= 0 then ordered_children[#ordered_children + 1] = { track = child, idx = child_idx, block_last_guid = children[i].block_last_guid } end
    end
    table.sort(ordered_children, function(a, b) return a.idx < b.idx end)
    local ordered_moved = {}
    for i = 1, #move_guids do
        local moved = FindTrackByGuidLocal(move_guids[i])
        local moved_idx = GetTrackIndexLocal(moved)
        if moved and moved_idx >= 0 then ordered_moved[#ordered_moved + 1] = { track = moved, idx = moved_idx } end
    end
    table.sort(ordered_moved, function(a, b) return a.idx < b.idx end)
    local contiguous = parent_idx >= 0 and #ordered_children == #children and #ordered_moved == #move_guids
    if contiguous then
        for i = 1, #ordered_moved do
            if ordered_moved[i].idx ~= parent_idx + i then contiguous = false; break end
        end
    end
    if not contiguous then
        r.PreventUIRefresh(-1)
        r.TrackList_AdjustWindows(false)
        r.UpdateArrange()
        r.Undo_EndBlock("Patchbay: move folder children", -1)
        r.ShowMessageBox("Selected tracks were moved, but the folder range could not be verified. Undo and try again.", "Patchbay Folder", 0)
        return
    end
    if parent_now and r.ValidatePtr(parent_now, "MediaTrack*") then
        r.SetMediaTrackInfo_Value(parent_now, "I_FOLDERDEPTH", 1)
    end
    local last_child = ordered_children[#ordered_children]
    if last_child then
        local closer_child = FindTrackByGuidLocal(last_child.block_last_guid)
        if closer_child and r.ValidatePtr(closer_child, "MediaTrack*") then
            local depth = math.floor(r.GetMediaTrackInfo_Value(closer_child, "I_FOLDERDEPTH") or 0)
            r.SetMediaTrackInfo_Value(closer_child, "I_FOLDERDEPTH", depth + ((parent_start_depth or 0) - 1))
        end
    end
    for i = 1, #move_guids do
        local child = FindTrackByGuidLocal(move_guids[i])
        if child and r.ValidatePtr(child, "MediaTrack*") then r.SetMediaTrackInfo_Value(child, "I_SELECTED", 1) end
    end
    r.PreventUIRefresh(-1)
    r.TrackList_AdjustWindows(false)
    r.UpdateArrange()
    r.Undo_EndBlock("Patchbay: assign folder children", -1)
    _G.TRACK = FindTrackByGuidLocal(parent_guid) or _G.TRACK
    MarkFolderLayoutChanged()
end

local function RemoveTrackFromFolderParent(tr)
    if IsAllLockedCfg(GetConfig()) then return end
    if not r.ReorderSelectedTracks then
        r.ShowMessageBox("ReorderSelectedTracks is not available.", "Patchbay Folder", 0)
        return
    end
    if not tr or not r.ValidatePtr(tr, "MediaTrack*") or tr == r.GetMasterTrack(0) then return end
    local parent, block_start_idx = GetDirectFolderParentLocal(tr)
    if not parent or not r.ValidatePtr(parent, "MediaTrack*") then
        r.ShowMessageBox("This track is not inside a folder.", "Patchbay Folder", 0)
        return
    end
    local parent_depth = math.floor(r.GetMediaTrackInfo_Value(parent, "I_FOLDERDEPTH") or 0)
    if parent_depth ~= 1 then
        r.ShowMessageBox("Remove from parent only supports simple folder parents.", "Patchbay Folder", 0)
        return
    end
    local parent_guid = r.GetTrackGUID(parent)
    local parent_idx, parent_end_idx = GetFolderRangeLocal(parent)
    if not parent_end_idx or block_start_idx <= parent_idx or block_start_idx > parent_end_idx then
        r.ShowMessageBox("Parent folder range could not be resolved.", "Patchbay Folder", 0)
        return
    end
    local block_depth = math.floor(r.GetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH") or 0)
    if block_depth > 1 then
        r.ShowMessageBox("Remove from parent only supports simple child folder starts.", "Patchbay Folder", 0)
        return
    end
    local _, block_end_idx = GetFolderRangeLocal(tr)
    if not block_end_idx then block_end_idx = block_start_idx end
    if block_end_idx > parent_end_idx then
        r.ShowMessageBox("Child folder range exceeds parent range.", "Patchbay Folder", 0)
        return
    end
    local block_guids = {}
    for i = block_start_idx, block_end_idx do
        local block_tr = r.GetTrack(0, i)
        if block_tr and r.ValidatePtr(block_tr, "MediaTrack*") then block_guids[#block_guids + 1] = r.GetTrackGUID(block_tr) end
    end
    if #block_guids == 0 then return end
    local parent_end_guid = r.GetTrackGUID(r.GetTrack(0, parent_end_idx))
    local closes_parent = block_end_idx == parent_end_idx
    local replacement_guid = nil
    local replacement_depth = nil
    if closes_parent and block_start_idx > parent_idx + 1 then
        local replacement = r.GetTrack(0, block_start_idx - 1)
        if replacement and r.ValidatePtr(replacement, "MediaTrack*") then
            replacement_guid = r.GetTrackGUID(replacement)
            replacement_depth = math.floor(r.GetMediaTrackInfo_Value(replacement, "I_FOLDERDEPTH") or 0)
        end
    end
    local block_end_guid = block_guids[#block_guids]
    local block_end_depth = math.floor(r.GetMediaTrackInfo_Value(r.GetTrack(0, block_end_idx), "I_FOLDERDEPTH") or 0)
    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)
    for i = 0, r.CountTracks(0) - 1 do
        r.SetMediaTrackInfo_Value(r.GetTrack(0, i), "I_SELECTED", 0)
    end
    for i = 1, #block_guids do
        local block_tr = FindTrackByGuidLocal(block_guids[i])
        if block_tr and r.ValidatePtr(block_tr, "MediaTrack*") then r.SetMediaTrackInfo_Value(block_tr, "I_SELECTED", 1) end
    end
    r.ReorderSelectedTracks(parent_end_idx + 1, 0)
    local ordered_block = {}
    for i = 1, #block_guids do
        local block_tr = FindTrackByGuidLocal(block_guids[i])
        local block_idx = GetTrackIndexLocal(block_tr)
        if block_tr and block_idx >= 0 then ordered_block[#ordered_block + 1] = { track = block_tr, idx = block_idx } end
    end
    table.sort(ordered_block, function(a, b) return a.idx < b.idx end)
    local contiguous = #ordered_block == #block_guids
    if contiguous then
        for i = 1, #ordered_block do
            if ordered_block[i].idx ~= ordered_block[1].idx + i - 1 then contiguous = false; break end
        end
    end
    local parent_now = FindTrackByGuidLocal(parent_guid)
    if contiguous and not closes_parent then
        local parent_end_now = FindTrackByGuidLocal(parent_end_guid)
        contiguous = parent_end_now and ordered_block[1].idx > GetTrackIndexLocal(parent_end_now)
    elseif contiguous and replacement_guid then
        local replacement_now = FindTrackByGuidLocal(replacement_guid)
        contiguous = replacement_now and ordered_block[1].idx > GetTrackIndexLocal(replacement_now)
    elseif contiguous then
        contiguous = parent_now and ordered_block[1].idx > GetTrackIndexLocal(parent_now)
    end
    if not contiguous then
        r.PreventUIRefresh(-1)
        r.TrackList_AdjustWindows(false)
        r.UpdateArrange()
        r.Undo_EndBlock("Patchbay: move folder block", -1)
        r.ShowMessageBox("Selected tracks were moved, but the removed folder block could not be verified. Undo and try again.", "Patchbay Folder", 0)
        return
    end
    if closes_parent then
        if replacement_guid and replacement_depth then
            local replacement_now = FindTrackByGuidLocal(replacement_guid)
            if replacement_now and r.ValidatePtr(replacement_now, "MediaTrack*") then
                r.SetMediaTrackInfo_Value(replacement_now, "I_FOLDERDEPTH", replacement_depth - 1)
            end
        elseif parent_now and r.ValidatePtr(parent_now, "MediaTrack*") then
            r.SetMediaTrackInfo_Value(parent_now, "I_FOLDERDEPTH", 0)
        end
        local block_end_now = FindTrackByGuidLocal(block_end_guid)
        if block_end_now and r.ValidatePtr(block_end_now, "MediaTrack*") then
            r.SetMediaTrackInfo_Value(block_end_now, "I_FOLDERDEPTH", block_end_depth + 1)
        end
    end
    for i = 1, #block_guids do
        local block_tr = FindTrackByGuidLocal(block_guids[i])
        if block_tr and r.ValidatePtr(block_tr, "MediaTrack*") then r.SetMediaTrackInfo_Value(block_tr, "I_SELECTED", 1) end
    end
    r.PreventUIRefresh(-1)
    r.TrackList_AdjustWindows(false)
    r.UpdateArrange()
    r.Undo_EndBlock("Patchbay: remove from parent", -1)
    _G.TRACK = FindTrackByGuidLocal(block_guids[1]) or _G.TRACK
    MarkFolderLayoutChanged()
end

function BatchSetMute(selected_tracks, muted)
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

function BatchSetSolo(selected_tracks, solo_on)
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

function BatchSetRecordArm(selected_tracks, arm_on)
    if IsAllLockedCfg(GetConfig()) then return end
    if not selected_tracks or #selected_tracks == 0 then return end
    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)
    for i = 1, #selected_tracks do
        local tr = selected_tracks[i].track
        if tr and r.ValidatePtr(tr, "MediaTrack*") and tr ~= r.GetMasterTrack(0) then
            r.SetMediaTrackInfo_Value(tr, "I_RECARM", arm_on and 1 or 0)
        end
    end
    r.PreventUIRefresh(-1)
    r.TrackList_AdjustWindows(false)
    r.UpdateArrange()
    r.Undo_EndBlock(arm_on and "Patchbay: arm selected tracks" or "Patchbay: unarm selected tracks", -1)
end

function BatchSetFreeze(selected_tracks, freeze_on)
    if IsAllLockedCfg(GetConfig()) then return end
    if not selected_tracks or #selected_tracks == 0 then return end
    local master = r.GetMasterTrack(0)
    local focus_before = _G.TRACK
    local targets = {}
    local selected_before = {}
    local master_selected = master and r.ValidatePtr(master, "MediaTrack*") and r.GetMediaTrackInfo_Value(master, "I_SELECTED") == 1
    local n = r.CountTracks(0)
    for i = 0, n - 1 do
        local tr = r.GetTrack(0, i)
        if tr and r.ValidatePtr(tr, "MediaTrack*") and r.GetMediaTrackInfo_Value(tr, "I_SELECTED") == 1 then
            selected_before[r.GetTrackGUID(tr)] = true
        end
    end
    for i = 1, #selected_tracks do
        local tr = selected_tracks[i].track
        if tr and r.ValidatePtr(tr, "MediaTrack*") and tr ~= master and IsPatchbayTrackFrozen(tr) ~= freeze_on then
            targets[#targets + 1] = tr
        end
    end
    if #targets == 0 then return end
    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)
    for i = 0, n - 1 do
        local tr = r.GetTrack(0, i)
        if tr and r.ValidatePtr(tr, "MediaTrack*") then r.SetMediaTrackInfo_Value(tr, "I_SELECTED", 0) end
    end
    if master and r.ValidatePtr(master, "MediaTrack*") then r.SetMediaTrackInfo_Value(master, "I_SELECTED", 0) end
    for i = 1, #targets do
        if targets[i] and r.ValidatePtr(targets[i], "MediaTrack*") then r.SetMediaTrackInfo_Value(targets[i], "I_SELECTED", 1) end
    end
    r.Main_OnCommand(freeze_on and 41223 or 41644, 0)
    n = r.CountTracks(0)
    for i = 0, n - 1 do
        local tr = r.GetTrack(0, i)
        if tr and r.ValidatePtr(tr, "MediaTrack*") then
            r.SetMediaTrackInfo_Value(tr, "I_SELECTED", selected_before[r.GetTrackGUID(tr)] and 1 or 0)
        end
    end
    master = r.GetMasterTrack(0)
    if master and r.ValidatePtr(master, "MediaTrack*") then r.SetMediaTrackInfo_Value(master, "I_SELECTED", master_selected and 1 or 0) end
    _G.TRACK = focus_before and r.ValidatePtr(focus_before, "MediaTrack*") and focus_before or r.GetSelectedTrack(0, 0)
    r.PreventUIRefresh(-1)
    r.TrackList_AdjustWindows(false)
    r.UpdateArrange()
    r.Undo_EndBlock(freeze_on and "Patchbay: freeze selected tracks" or "Patchbay: unfreeze selected tracks", -1)
end

function BatchSetPinned(selected_tracks, pin_on)
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

PB.paranormal_command_id = nil

function PatchbayNormalizePath(path)
    return tostring(path or ""):gsub("\\", "/"):lower()
end

function PatchbayFindParanormalScriptPath()
    local resource = r.GetResourcePath():gsub("\\", "/")
    local candidates = {
        resource .. "/Scripts/Sexan_Scripts/ParanormalFX/Sexan_ParaNormal_FX_Router.lua",
        resource .. "/Scripts/Sexan_Scripts/FX/Sexan_ParaNormal_FX_Router.lua"
    }
    for i = 1, #candidates do
        if r.file_exists(candidates[i]) then return candidates[i] end
    end
    if r.EnumerateFiles then
        local dir = resource .. "/Scripts/Sexan_Scripts/ParanormalFX"
        local idx = 0
        while true do
            local file = r.EnumerateFiles(dir, idx)
            if not file then break end
            local lower = file:lower()
            if lower:match("%.lua$") and lower:find("paranormal", 1, true) then
                return dir .. "/" .. file
            end
            idx = idx + 1
        end
    end
    return nil
end

function PatchbayFindRegisteredCommandForScript(script_path)
    local kb_path = r.GetResourcePath() .. "/reaper-kb.ini"
    local file = io.open(kb_path, "r")
    if not file then return nil end
    local target = PatchbayNormalizePath(script_path)
    local name = target:match("([^/]+)$") or target
    for line in file:lines() do
        local line_norm = PatchbayNormalizePath(line)
        if line_norm:find(target, 1, true) or line_norm:find(name, 1, true) then
            local cmd = line:match("(_RS[%w_]+)")
            if cmd then
                file:close()
                return cmd
            end
        end
    end
    file:close()
    return nil
end

function PatchbayResolveParanormalCommand()
    if PB.paranormal_command_id and PB.paranormal_command_id ~= 0 then return PB.paranormal_command_id end
    local script_path = PatchbayFindParanormalScriptPath()
    if not script_path then return nil, "Paranormal FX script not found." end
    local named = PatchbayFindRegisteredCommandForScript(script_path)
    if named and r.NamedCommandLookup then
        local cmd = r.NamedCommandLookup(named)
        if cmd and cmd ~= 0 then
            PB.paranormal_command_id = cmd
            return PB.paranormal_command_id
        end
    end
    if r.AddRemoveReaScript then
        local cmd = r.AddRemoveReaScript(true, 0, script_path, true)
        if cmd and cmd ~= 0 then
            PB.paranormal_command_id = cmd
            return PB.paranormal_command_id
        end
    end
    return nil, "Could not register or locate Paranormal FX action."
end

function PatchbayToggleParanormalForTrack(track)
    if not track or not r.ValidatePtr(track, "MediaTrack*") then return false, "Track not available." end
    local cmd, err = PatchbayResolveParanormalCommand()
    if not cmd then return false, err end
    r.SetOnlyTrackSelected(track)
    _G.TRACK = track
    if r.SetMixerScroll then r.SetMixerScroll(track) end
    r.UpdateArrange()
    r.Main_OnCommand(cmd, 0)
    return true
end

function PatchbayDrawPinSymbol(draw_list, x1, y1, x2, y2, col)
    local cx = (x1 + x2) * 0.5
    local cy = (y1 + y2) * 0.5
    local w = x2 - x1
    local h = y2 - y1
    local icon_w = w * 0.50
    local icon_h = h * 0.32
    local rect_y = cy - h * 0.24
    r.ImGui_DrawList_AddRect(draw_list, cx - icon_w * 0.5, rect_y, cx + icon_w * 0.5, rect_y + icon_h, col, 1, nil, 1.4)
    r.ImGui_DrawList_AddLine(draw_list, cx, rect_y + icon_h, cx, cy + h * 0.30, col, 1.4)
end

function PatchbayDrawSchemaSymbol(draw_list, x1, y1, x2, y2, col)
    local w = x2 - x1
    local h = y2 - y1
    local box_w = w * 0.24
    local box_h = h * 0.22
    local left_x = x1 + w * 0.20
    local mid_x = x1 + w * 0.50
    local right_x = x1 + w * 0.80
    local mid_y = y1 + h * 0.50
    local top_y = y1 + h * 0.30
    local bot_y = y1 + h * 0.70
    r.ImGui_DrawList_AddLine(draw_list, left_x + box_w * 0.5, mid_y, mid_x - box_w * 0.5, top_y, col, 1.2)
    r.ImGui_DrawList_AddLine(draw_list, left_x + box_w * 0.5, mid_y, mid_x - box_w * 0.5, bot_y, col, 1.2)
    r.ImGui_DrawList_AddLine(draw_list, mid_x + box_w * 0.5, top_y, right_x - box_w * 0.5, mid_y, col, 1.2)
    r.ImGui_DrawList_AddLine(draw_list, mid_x + box_w * 0.5, bot_y, right_x - box_w * 0.5, mid_y, col, 1.2)
    r.ImGui_DrawList_AddRect(draw_list, left_x - box_w * 0.5, mid_y - box_h * 0.5, left_x + box_w * 0.5, mid_y + box_h * 0.5, col, 1, nil, 1.2)
    r.ImGui_DrawList_AddRect(draw_list, mid_x - box_w * 0.5, top_y - box_h * 0.5, mid_x + box_w * 0.5, top_y + box_h * 0.5, col, 1, nil, 1.2)
    r.ImGui_DrawList_AddRect(draw_list, mid_x - box_w * 0.5, bot_y - box_h * 0.5, mid_x + box_w * 0.5, bot_y + box_h * 0.5, col, 1, nil, 1.2)
    r.ImGui_DrawList_AddRect(draw_list, right_x - box_w * 0.5, mid_y - box_h * 0.5, right_x + box_w * 0.5, mid_y + box_h * 0.5, col, 1, nil, 1.2)
end

function BatchSetCollapsed(selected_tracks, collapse_on)
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

function BatchDeleteTracks(selected_tracks)
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

function PatchbayDeleteSelectedShortcutPressed(ctx)
    if not r.ImGui_IsKeyPressed or not r.ImGui_Key_Delete then return false end
    if r.ImGui_IsAnyItemActive and r.ImGui_IsAnyItemActive(ctx) then return false end
    if r.ImGui_IsWindowFocused then
        local flags = r.ImGui_FocusedFlags_RootAndChildWindows and r.ImGui_FocusedFlags_RootAndChildWindows() or 0
        if not r.ImGui_IsWindowFocused(ctx, flags) then return false end
    end
    return r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_Delete())
end

function PatchbayCtrlShortcutPressed(ctx, key_func)
    if not r.ImGui_IsKeyPressed or not key_func then return false end
    if r.ImGui_IsAnyItemActive and r.ImGui_IsAnyItemActive(ctx) then return false end
    if r.ImGui_IsWindowFocused then
        local flags = r.ImGui_FocusedFlags_RootAndChildWindows and r.ImGui_FocusedFlags_RootAndChildWindows() or 0
        if not r.ImGui_IsWindowFocused(ctx, flags) then return false end
    end
    local mods = r.ImGui_GetKeyMods and r.ImGui_GetKeyMods(ctx) or 0
    local mod_ctrl = r.ImGui_Mod_Ctrl and r.ImGui_Mod_Ctrl() or 0
    if (mods & mod_ctrl) == 0 then return false end
    return r.ImGui_IsKeyPressed(ctx, key_func())
end

function BatchConnectSelectedToTarget(selected_tracks, target)
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

function BatchConnectTargetToSelected(target, selected_tracks)
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

function BatchDisconnectSelectedToTarget(selected_tracks, target)
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

function BatchDisconnectTargetToSelected(target, selected_tracks)
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

function PatchbayBatchSetMainSend(selected_tracks, enabled, undo_name)
    if IsAllLockedCfg(GetConfig()) then return 0 end
    if not selected_tracks or #selected_tracks == 0 then return 0 end
    local changes = 0
    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)
    for i = 1, #selected_tracks do
        local src = selected_tracks[i].track
        if src and r.ValidatePtr(src, "MediaTrack*") then
            local current = r.GetMediaTrackInfo_Value(src, "B_MAINSEND") == 1
            if current ~= enabled then
                r.SetMediaTrackInfo_Value(src, "B_MAINSEND", enabled and 1 or 0)
                changes = changes + 1
            end
        end
    end
    r.PreventUIRefresh(-1)
    if changes > 0 then
        r.TrackList_AdjustWindows(false)
        r.UpdateArrange()
        r.Undo_EndBlock(undo_name, -1)
    else
        r.Undo_EndBlock(undo_name .. " (no changes)", -1)
    end
    return changes
end

function BatchConnectSelectedToDestination(selected_tracks, target)
    if IsAllLockedCfg(GetConfig()) then return 0 end
    if not selected_tracks or #selected_tracks == 0 then return 0 end
    if not target or not r.ValidatePtr(target, "MediaTrack*") then return 0 end
    if target == r.GetMasterTrack(0) then
        return PatchbayBatchSetMainSend(selected_tracks, true, "Patchbay: bulk enable selected main sends")
    end
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

function BatchDisconnectSelectedFromDestination(selected_tracks, target)
    if IsAllLockedCfg(GetConfig()) then return 0 end
    if not selected_tracks or #selected_tracks == 0 then return 0 end
    if not target or not r.ValidatePtr(target, "MediaTrack*") then return 0 end
    if target == r.GetMasterTrack(0) then
        return PatchbayBatchSetMainSend(selected_tracks, false, "Patchbay: bulk disable selected main sends")
    end
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

function BatchApplyBulkRouteSettings(selected_tracks, target, create_missing, mode, vol_db, pan, mute, phase, mono)
    if IsAllLockedCfg(GetConfig()) then return 0 end
    if not selected_tracks or #selected_tracks == 0 then return 0 end
    if not target or not r.ValidatePtr(target, "MediaTrack*") then return 0 end
    if target == r.GetMasterTrack(0) then
        if create_missing then
            return PatchbayBatchSetMainSend(selected_tracks, true, "Patchbay: bulk enable selected main sends")
        end
        return 0
    end
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

GetLayoutPreset = function(cfg)
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

function PatchbayLayoutKind(preset)
    if preset == "folder_tree" or preset == "folder_tree_compact" or preset == "folder_tree_horizontal" then return "folder" end
    return "signal"
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

function PatchbayPlacePendingVisibleNodes(tracks, avail_w, avail_h)
    local pending = PB.pending_paste_visible_guids
    if not pending then return end
    local pasted = {}
    local remaining = false
    for i = 1, #tracks do
        local guid = tracks[i].guid
        if pending[guid] and node_positions[guid] then
            pasted[#pasted + 1] = guid
            pending[guid] = nil
        end
    end
    for _, _ in pairs(pending) do remaining = true break end
    if #pasted == 0 then
        if not remaining then PB.pending_paste_visible_guids = nil end
        return
    end
    table.sort(pasted, function(a, b)
        local ta = FindTrackByGuidLocal(a)
        local tb = FindTrackByGuidLocal(b)
        return GetTrackIndexLocal(ta) < GetTrackIndexLocal(tb)
    end)
    local cfg = GetConfig()
    local pad = 24
    local left = (-canvas_offset_x) / canvas_zoom
    local top = (-canvas_offset_y) / canvas_zoom
    local right = (avail_w - canvas_offset_x) / canvas_zoom
    local bottom = (avail_h - canvas_offset_y) / canvas_zoom
    local col_w = LayoutColW(cfg)
    local row_h = LayoutRowH(cfg)
    local visible_w = math.max(1, right - left - pad * 2)
    local max_cols = math.max(1, math.floor(visible_w / math.max(1, col_w)))
    local start_x = left + pad
    local start_y = top + pad
    if start_x + NodeW() > right - pad then start_x = left + math.max(0, (right - left - NodeW()) * 0.5) end
    for i = 1, #pasted do
        local guid = pasted[i]
        local col = (i - 1) % max_cols
        local row = math.floor((i - 1) / max_cols)
        local x = start_x + col * col_w
        local y = start_y + row * row_h
        x = math.floor((x / GRID) + 0.5) * GRID
        y = math.floor((y / GRID) + 0.5) * GRID
        local min_x = left + pad
        local max_x = right - pad - NodeW()
        local min_y = top + pad
        local max_y = bottom - pad - NodeH(guid)
        if max_x < min_x then
            x = left + math.max(0, (right - left - NodeW()) * 0.5)
        elseif x < min_x then
            x = min_x
        elseif x > max_x then
            x = max_x
        end
        if max_y < min_y then
            y = top + math.max(0, (bottom - top - NodeH(guid)) * 0.5)
        elseif y < min_y then
            y = min_y
        elseif y > max_y then
            y = max_y
        end
        node_positions[guid] = { x = x, y = y }
    end
    PB.pending_paste_visible_guids = remaining and pending or nil
    layout_dirty = true
end

local function ClampPatchbayNodeToVisible(guid, x, y, left, top, right, bottom, pad)
    x = math.floor((x / GRID) + 0.5) * GRID
    y = math.floor((y / GRID) + 0.5) * GRID
    local min_x = left + pad
    local max_x = right - pad - NodeW()
    local min_y = top + pad
    local max_y = bottom - pad - NodeH(guid)
    if max_x < min_x then
        x = left + math.max(0, (right - left - NodeW()) * 0.5)
    elseif x < min_x then
        x = min_x
    elseif x > max_x then
        x = max_x
    end
    if max_y < min_y then
        y = top + math.max(0, (bottom - top - NodeH(guid)) * 0.5)
    elseif y < min_y then
        y = min_y
    elseif y > max_y then
        y = max_y
    end
    return x, y
end

local function PatchbayPlacePendingSpawnNodes(tracks, origin_x, origin_y, avail_w, avail_h)
    if not pending_spawn_nodes then return end
    local spawned = {}
    local remaining = false
    for i = 1, #tracks do
        local guid = tracks[i].guid
        local spawn = pending_spawn_nodes[guid]
        if spawn and node_positions[guid] then
            spawned[#spawned + 1] = { guid = guid, spawn = spawn }
            pending_spawn_nodes[guid] = nil
        end
    end
    for _, _ in pairs(pending_spawn_nodes) do remaining = true break end
    if #spawned == 0 then
        if not remaining then pending_spawn_nodes = nil end
        return
    end
    table.sort(spawned, function(a, b)
        local ao = a.spawn.order or 1
        local bo = b.spawn.order or 1
        if ao ~= bo then return ao < bo end
        local ta = FindTrackByGuidLocal(a.guid)
        local tb = FindTrackByGuidLocal(b.guid)
        return GetTrackIndexLocal(ta) < GetTrackIndexLocal(tb)
    end)
    local cfg = GetConfig()
    local pad = 24
    local left = (-canvas_offset_x) / canvas_zoom
    local top = (-canvas_offset_y) / canvas_zoom
    local right = (avail_w - canvas_offset_x) / canvas_zoom
    local bottom = (avail_h - canvas_offset_y) / canvas_zoom
    local col_w = LayoutColW(cfg)
    local row_h = LayoutRowH(cfg)
    local visible_w = math.max(1, right - left - pad * 2)
    local max_cols = math.max(1, math.floor(visible_w / math.max(1, col_w)))
    local first = spawned[1]
    local base_x
    local base_y
    if first.spawn.mode == "mouse" and first.spawn.screen_x and first.spawn.screen_y then
        base_x = (first.spawn.screen_x - origin_x - canvas_offset_x) / canvas_zoom - NodeW() * 0.5
        base_y = (first.spawn.screen_y - origin_y - canvas_offset_y) / canvas_zoom - NodeH(first.guid) * 0.5
    else
        base_x = left + math.max(0, (right - left - NodeW()) * 0.5)
        base_y = top + math.max(0, (bottom - top - NodeH(first.guid)) * 0.5)
    end
    for i = 1, #spawned do
        local guid = spawned[i].guid
        local col = (i - 1) % max_cols
        local row = math.floor((i - 1) / max_cols)
        local x = base_x + col * col_w
        local y = base_y + row * row_h
        x, y = ClampPatchbayNodeToVisible(guid, x, y, left, top, right, bottom, pad)
        node_positions[guid] = { x = x, y = y }
    end
    if cfg.patchbay_prevent_overlap ~= false then
        for i = 1, #spawned do
            ResolveMovedNodesOverlap(spawned[i].guid, tracks)
        end
    end
    pending_spawn_nodes = remaining and pending_spawn_nodes or nil
    layout_dirty = true
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
    lines[#lines + 1] = "patchbay_selected_with_children=" .. ((cfg.patchbay_selected_with_children and 1) or 0)
    lines[#lines + 1] = "patchbay_selected_subtree=" .. ((cfg.patchbay_selected_subtree and 1) or 0)
    lines[#lines + 1] = "patchbay_only_explicit_routing=" .. ((cfg.patchbay_only_explicit_routing and 1) or 0)
    lines[#lines + 1] = "patchbay_explicit_show_mainsend=" .. ((cfg.patchbay_explicit_show_mainsend and 1) or 0)
    lines[#lines + 1] = "patchbay_show_unrouted=" .. ((cfg.patchbay_show_unrouted and 1) or 0)
    lines[#lines + 1] = "patchbay_show_master=" .. (((cfg.patchbay_show_master ~= false) and 1) or 0)
    lines[#lines + 1] = "patchbay_hide_child_master_flow=" .. ((cfg.patchbay_hide_child_master_flow and 1) or 0)
    lines[#lines + 1] = "patchbay_show_flow=" .. (((cfg.patchbay_show_flow ~= false) and 1) or 0)
    lines[#lines + 1] = "patchbay_show_folder_links=" .. (((cfg.patchbay_show_folder_links ~= false) and 1) or 0)
    lines[#lines + 1] = "patchbay_show_send_type_badges=" .. (((cfg.patchbay_show_send_type_badges ~= false) and 1) or 0)
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
            elseif k == "patchbay_selected_with_children" then
                cfg.patchbay_selected_with_children = (v == "1")
            elseif k == "patchbay_selected_subtree" then
                cfg.patchbay_selected_subtree = (v == "1")
            elseif k == "patchbay_only_explicit_routing" then
                cfg.patchbay_only_explicit_routing = (v == "1")
            elseif k == "patchbay_explicit_show_mainsend" then
                cfg.patchbay_explicit_show_mainsend = (v == "1")
            elseif k == "patchbay_show_unrouted" then
                cfg.patchbay_show_unrouted = (v == "1")
            elseif k == "patchbay_show_master" then
                cfg.patchbay_show_master = (v == "1")
            elseif k == "patchbay_hide_child_master_flow" then
                cfg.patchbay_hide_child_master_flow = (v == "1")
            elseif k == "patchbay_show_flow" then
                cfg.patchbay_show_flow = (v == "1")
            elseif k == "patchbay_show_folder_links" then
                cfg.patchbay_show_folder_links = (v == "1")
            elseif k == "patchbay_show_send_type_badges" then
                cfg.patchbay_show_send_type_badges = (v == "1")
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

function SaveGroupStore()
    local lines = {}
    for i = 1, #group_names do
        local name = group_names[i]
        local guids = group_map[name]
        if name and name ~= "" and guids and #guids > 0 then
            local parts = {}
            for j = 1, #guids do
                parts[#parts + 1] = UrlEncode(guids[j])
            end
            lines[#lines + 1] = UrlEncode(name) .. "|" .. table.concat(parts, ",")
        end
    end
    r.SetProjExtState(0, "TK_FXB_PATCHBAY_GROUPS", "items", table.concat(lines, "\n"))
    r.SetProjExtState(0, "TK_FXB_PATCHBAY_GROUPS", "active", active_group_name and UrlEncode(active_group_name) or "")
end

function LoadGroupStore()
    group_names = {}
    group_map = {}
    local _, raw = r.GetProjExtState(0, "TK_FXB_PATCHBAY_GROUPS", "items")
    if raw and raw ~= "" then
        for line in raw:gmatch("([^\n]+)") do
            local a, b = line:match("^([^|]+)|(.*)$")
            if a then
                local name = UrlDecode(a)
                if name ~= "" and not group_map[name] then
                    local guids = {}
                    if b and b ~= "" then
                        for tok in b:gmatch("([^,]+)") do
                            local g = UrlDecode(tok)
                            if g ~= "" then guids[#guids + 1] = g end
                        end
                    end
                    group_names[#group_names + 1] = name
                    group_map[name] = guids
                end
            end
        end
    end
    local _, act = r.GetProjExtState(0, "TK_FXB_PATCHBAY_GROUPS", "active")
    if act and act ~= "" then
        local nm = UrlDecode(act)
        active_group_name = group_map[nm] and nm or nil
    else
        active_group_name = nil
    end
end

function SaveGroupNamed(name)
    local n = Trim(name)
    if n == "" then return false end
    local guids = {}
    local seen = {}
    for guid, on in pairs(pb_selected_set) do
        if on and guid and not seen[guid] then
            seen[guid] = true
            guids[#guids + 1] = guid
        end
    end
    if #guids == 0 then return false end
    if not group_map[n] then
        group_names[#group_names + 1] = n
    end
    group_map[n] = guids
    SaveGroupStore()
    return true
end

function RecallGroup(name)
    local n = Trim(name)
    if not group_map[n] then return false end
    active_group_name = n
    local cfg = GetConfig()
    if cfg then
        cfg.routing_only_selected = false
        cfg.patchbay_selected_with_children = false
        cfg.patchbay_selected_subtree = false
        if _G.SaveConfig then _G.SaveConfig() end
    end
    SaveGroupStore()
    layout_dirty = true
    return true
end

function ClearActiveGroup()
    active_group_name = nil
    SaveGroupStore()
    layout_dirty = true
end

function DeleteGroupNamed(name)
    local n = Trim(name)
    if n == "" or not group_map[n] then return false end
    group_map[n] = nil
    for i = #group_names, 1, -1 do
        if group_names[i] == n then
            table.remove(group_names, i)
            break
        end
    end
    if active_group_name == n then active_group_name = nil end
    SaveGroupStore()
    return true
end

function AddGuidsToGroupNamed(name, guids)
    local n = Trim(name)
    if n == "" or not guids or #guids == 0 then return false end
    local list = group_map[n]
    if not list then
        list = {}
        group_map[n] = list
        group_names[#group_names + 1] = n
    end
    local seen = {}
    for i = 1, #list do seen[list[i]] = true end
    local added = false
    for i = 1, #guids do
        local g = guids[i]
        if g and not seen[g] then
            seen[g] = true
            list[#list + 1] = g
            added = true
        end
    end
    if added then SaveGroupStore() end
    return added
end

function PatchbayNodeGroupTargetGuids(guid)
    local guids = {}
    if guid and pb_selected_set[guid] then
        for g, on in pairs(pb_selected_set) do
            if on and g then guids[#guids + 1] = g end
        end
    elseif guid then
        guids[1] = guid
    end
    return guids
end

function RemoveGuidsFromGroupNamed(name, guids)
    local n = Trim(name)
    local list = group_map[n]
    if n == "" or not list or not guids or #guids == 0 then return false end
    local drop = {}
    for i = 1, #guids do drop[guids[i]] = true end
    local removed = false
    for i = #list, 1, -1 do
        if drop[list[i]] then
            table.remove(list, i)
            removed = true
        end
    end
    if removed then
        if #list == 0 then
            DeleteGroupNamed(n)
        else
            SaveGroupStore()
        end
        layout_dirty = true
    end
    return removed
end

function PatchbayNodeGroupsContaining(guids)
    local names = {}
    if not guids or #guids == 0 then return names end
    local want = {}
    for i = 1, #guids do want[guids[i]] = true end
    for gi = 1, #group_names do
        local nm = group_names[gi]
        local list = group_map[nm]
        if list then
            for i = 1, #list do
                if want[list[i]] then
                    names[#names + 1] = nm
                    break
                end
            end
        end
    end
    return names
end

function BuildActiveGroupVisibleSet()
    if not active_group_name then return nil end
    local guids = group_map[active_group_name]
    if not guids or #guids == 0 then return nil end
    local base = {}
    local set = {}
    for i = 1, #guids do
        base[guids[i]] = true
        set[guids[i]] = true
    end
    local cfg = GetConfig()
    local include_neighbors = not (cfg and cfg.patchbay_group_include_neighbors == false)
    if not include_neighbors then return set end
    local n = r.CountTracks(0)
    for i = 0, n - 1 do
        local t = r.GetTrack(0, i)
        if t and r.ValidatePtr(t, "MediaTrack*") then
            local guid = r.GetTrackGUID(t)
            if base[guid] then
                local nsnd = r.GetTrackNumSends(t, 0)
                for k = 0, nsnd - 1 do
                    local d = r.GetTrackSendInfo_Value(t, 0, k, "P_DESTTRACK")
                    if d and r.ValidatePtr(d, "MediaTrack*") then
                        set[r.GetTrackGUID(d)] = true
                    end
                end
                local nrec = r.GetTrackNumSends(t, -1)
                for k = 0, nrec - 1 do
                    local s = r.GetTrackSendInfo_Value(t, -1, k, "P_SRCTRACK")
                    if s and r.ValidatePtr(s, "MediaTrack*") then
                        set[r.GetTrackGUID(s)] = true
                    end
                end
                if r.GetMediaTrackInfo_Value(t, "B_MAINSEND") == 1 then
                    set[MASTER_GUID] = true
                end
            end
        end
    end
    return set
end

local function GetCurrentProjectKey()
    local _, fn = r.EnumProjects(-1)
    return fn or ""
end

function PatchbayCollectSelectedTreeSet(selected_set)
    local roots = {}
    if not selected_set then return {} end
    local folder_stack = {}
    local n = r.CountTracks(0)
    for i = 0, n - 1 do
        local tr = r.GetTrack(0, i)
        if tr and r.ValidatePtr(tr, "MediaTrack*") then
            local depth = math.floor(r.GetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH") or 0)
            if selected_set[tr] then
                roots[tr] = true
                for si = 1, #folder_stack do
                    if folder_stack[si] then roots[folder_stack[si]] = true end
                end
            end
            if depth > 0 then
                folder_stack[#folder_stack + 1] = tr
            elseif depth < 0 then
                for _ = 1, -depth do
                    if #folder_stack > 0 then table.remove(folder_stack) end
                end
            end
        end
    end
    local out = {}
    local active_child_depths = {}
    local depth_level = 0
    for i = 0, n - 1 do
        while #active_child_depths > 0 and depth_level < active_child_depths[#active_child_depths] do
            table.remove(active_child_depths)
        end
        local tr = r.GetTrack(0, i)
        if tr and r.ValidatePtr(tr, "MediaTrack*") then
            local depth = math.floor(r.GetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH") or 0)
            if roots[tr] or #active_child_depths > 0 then out[tr] = true end
            if roots[tr] and depth > 0 then active_child_depths[#active_child_depths + 1] = depth_level + 1 end
            depth_level = depth_level + depth
            if depth_level < 0 then depth_level = 0 end
        end
    end
    return out
end

function PatchbayCollectSelectedSubtreeSet(selected_set)
    if not selected_set then return {} end
    local out = {}
    local active_child_depths = {}
    local depth_level = 0
    local n = r.CountTracks(0)
    for i = 0, n - 1 do
        while #active_child_depths > 0 and depth_level < active_child_depths[#active_child_depths] do
            table.remove(active_child_depths)
        end
        local tr = r.GetTrack(0, i)
        if tr and r.ValidatePtr(tr, "MediaTrack*") then
            local depth = math.floor(r.GetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH") or 0)
            if selected_set[tr] or #active_child_depths > 0 then out[tr] = true end
            if selected_set[tr] and depth > 0 then active_child_depths[#active_child_depths + 1] = depth_level + 1 end
            depth_level = depth_level + depth
            if depth_level < 0 then depth_level = 0 end
        end
    end
    return out
end

function PatchbayFilterMatchesName(filter_text, name)
    local filter = ((filter_text or "")):lower()
    if filter == "" then return true end
    local lower_name = ((name or "")):lower()
    local has_token = false
    for group in filter:gmatch("[^,;]+") do
        local group_matches = true
        local group_has_token = false
        for token in group:gmatch("[^+]+") do
            token = token:match("^%s*(.-)%s*$")
            if token ~= "" then
                has_token = true
                group_has_token = true
                if lower_name:find(token, 1, true) == nil then
                    group_matches = false
                    break
                end
            end
        end
        if group_has_token and group_matches then return true end
    end
    return not has_token
end

function PatchbayBuildTcpMirrorVisibleSet(tracks)
    local visible = {}
    if tracks then
        for i = 1, #tracks do
            local tr = tracks[i]
            if tr and not tr.is_master and tr.guid then
                visible[tr.guid] = true
            end
        end
    end
    local stack = {}
    local total_tracks = r.CountTracks(0)
    for i = 0, total_tracks - 1 do
        local track = r.GetTrack(0, i)
        if track and r.ValidatePtr(track, "MediaTrack*") then
            local guid = r.GetTrackGUID(track)
            if visible[guid] then
                for si = 1, #stack do
                    visible[stack[si]] = true
                end
            end
            local depth = math.floor(r.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH") or 0)
            if depth > 0 then
                stack[#stack + 1] = guid
            elseif depth < 0 then
                for _ = 1, -depth do
                    if #stack > 0 then table.remove(stack) end
                end
            end
        end
    end
    return visible
end

function PatchbaySnapshotTcpMirrorTrack(track, guid)
    if not track or not guid or guid == MASTER_GUID then return end
    if not r.ValidatePtr(track, "MediaTrack*") then return end
    PB.tcp_mirror_original = PB.tcp_mirror_original or {}
    if PB.tcp_mirror_original[guid] == nil then
        PB.tcp_mirror_original[guid] = r.GetMediaTrackInfo_Value(track, "B_SHOWINTCP") == 1 and 1 or 0
    end
end

function PatchbayApplyTcpMirror(tracks)
    if PB.tcp_mirror_enabled ~= true then return end
    local visible = PatchbayBuildTcpMirrorVisibleSet(tracks)
    local changed = false
    r.PreventUIRefresh(1)
    local total_tracks = r.CountTracks(0)
    for i = 0, total_tracks - 1 do
        local track = r.GetTrack(0, i)
        if track and r.ValidatePtr(track, "MediaTrack*") then
            local guid = r.GetTrackGUID(track)
            PatchbaySnapshotTcpMirrorTrack(track, guid)
            local target = visible[guid] and 1 or 0
            if r.GetMediaTrackInfo_Value(track, "B_SHOWINTCP") ~= target then
                r.SetMediaTrackInfo_Value(track, "B_SHOWINTCP", target)
                changed = true
            end
        end
    end
    r.PreventUIRefresh(-1)
    if changed then
        r.TrackList_AdjustWindows(false)
        r.UpdateArrange()
    end
end

function PatchbayRestoreTcpMirror()
    if not PB.tcp_mirror_original then
        PB.tcp_mirror_enabled = false
        return
    end
    local changed = false
    r.PreventUIRefresh(1)
    local total_tracks = r.CountTracks(0)
    for i = 0, total_tracks - 1 do
        local track = r.GetTrack(0, i)
        if track and r.ValidatePtr(track, "MediaTrack*") then
            local guid = r.GetTrackGUID(track)
            local original = PB.tcp_mirror_original[guid]
            if original ~= nil and r.GetMediaTrackInfo_Value(track, "B_SHOWINTCP") ~= original then
                r.SetMediaTrackInfo_Value(track, "B_SHOWINTCP", original)
                changed = true
            end
        end
    end
    r.PreventUIRefresh(-1)
    PB.tcp_mirror_enabled = false
    PB.tcp_mirror_original = nil
    if changed then
        r.TrackList_AdjustWindows(false)
        r.UpdateArrange()
    end
end

function PatchbaySetTcpMirrorEnabled(enabled, tracks)
    if enabled then
        if PB.tcp_mirror_enabled ~= true then
            PB.tcp_mirror_enabled = true
            PB.tcp_mirror_original = {}
        end
        if tracks then PatchbayApplyTcpMirror(tracks) end
    else
        PatchbayRestoreTcpMirror()
    end
end

if r.atexit then r.atexit(PatchbayRestoreTcpMirror) end

local function CollectVisibleTracks()
    local cfg = GetConfig()
    local filter = cfg.routing_filter_text or ""
    local only_selected = cfg.routing_only_selected
    local selected_with_children = cfg.patchbay_selected_with_children == true
    local selected_subtree = cfg.patchbay_selected_subtree == true
    local only_explicit = cfg.patchbay_only_explicit_routing == true
    local explicit_show_mainsend = cfg.patchbay_explicit_show_mainsend == true
    local show_unrouted = cfg.patchbay_show_unrouted == true
    local TRACK_SEL = _G.TRACK
    local master = r.GetMasterTrack(0)
    local group_set = BuildActiveGroupVisibleSet()
    local folder_stack = {}
    local selected_tracks = {}
    local selected_set = {}
    local selected_child_set = nil

    if only_selected or selected_with_children or selected_subtree then
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
    if selected_with_children and #selected_tracks > 0 then
        selected_child_set = PatchbayCollectSelectedTreeSet(selected_set)
        if selected_set[master] then selected_child_set[master] = true end
        selected_set = selected_child_set
        selected_tracks = {}
        local total_tracks = r.CountTracks(0)
        for i = 0, total_tracks - 1 do
            local st = r.GetTrack(0, i)
            if st and selected_set[st] then selected_tracks[#selected_tracks + 1] = st end
        end
        if selected_set[master] then selected_tracks[#selected_tracks + 1] = master end
    elseif selected_subtree and #selected_tracks > 0 then
        selected_child_set = PatchbayCollectSelectedSubtreeSet(selected_set)
        if selected_set[master] then selected_child_set[master] = true end
        selected_set = selected_child_set
        selected_tracks = {}
        local total_tracks = r.CountTracks(0)
        for i = 0, total_tracks - 1 do
            local st = r.GetTrack(0, i)
            if st and selected_set[st] then selected_tracks[#selected_tracks + 1] = st end
        end
        if selected_set[master] then selected_tracks[#selected_tracks + 1] = master end
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
    local visible_mainsend = false
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
        local folder_depth = #folder_stack
        local folder_parent_guid = folder_top and folder_top.guid or nil
        local folder_parent_name = folder_top and folder_top.name or nil
        local folder_parent_r = folder_top and folder_top.r or nil
        local folder_parent_g = folder_top and folder_top.g or nil
        local folder_parent_b = folder_top and folder_top.b or nil
        local is_folder_child = folder_parent_guid ~= nil
        local track_muted = r.GetMediaTrackInfo_Value(t, "B_MUTE") == 1
        local track_soloed = r.GetMediaTrackInfo_Value(t, "I_SOLO") ~= 0
        local track_armed = r.GetMediaTrackInfo_Value(t, "I_RECARM") == 1
        local track_frozen = IsPatchbayTrackFrozen(t)
        local ancestor_muted = false
        local ancestor_muted_name = nil
        local ancestor_soloed = false
        local ancestor_soloed_name = nil
        for ancestor_index = #folder_stack, 1, -1 do
            local ancestor = folder_stack[ancestor_index]
            if ancestor.muted and not ancestor_muted then
                ancestor_muted = true
                ancestor_muted_name = ancestor.name
            end
            if ancestor.soloed and not ancestor_soloed then
                ancestor_soloed = true
                ancestor_soloed_name = ancestor.name
            end
            if ancestor_muted and ancestor_soloed then break end
        end
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
        if show_unrouted then
            has_routing = (not has_explicit and not mainsend)
        elseif only_explicit then
            has_routing = has_explicit
        else
            has_routing = (has_explicit or mainsend)
        end
        local match_filter = PatchbayFilterMatchesName(filter, name)
        local match_sel = true
        if (only_selected or selected_with_children or selected_subtree) and #selected_tracks > 0 then
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
        if (has_routing or ((selected_with_children or selected_subtree) and selected_child_set and selected_child_set[t] == true)) and match_filter and match_sel and (not group_set or group_set[guid]) then
            if mainsend then visible_mainsend = true end
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
                folder_is_parent = folder_is_parent,
                folder_depth = folder_depth,
                folder_parent_guid = folder_parent_guid,
                folder_parent_name = folder_parent_name,
                folder_parent_r = folder_parent_r,
                folder_parent_g = folder_parent_g,
                folder_parent_b = folder_parent_b,
                is_folder_child = is_folder_child,
                track_muted = track_muted,
                track_soloed = track_soloed,
                track_armed = track_armed,
                track_frozen = track_frozen,
                ancestor_muted = ancestor_muted,
                ancestor_muted_name = ancestor_muted_name,
                ancestor_soloed = ancestor_soloed,
                ancestor_soloed_name = ancestor_soloed_name
            }
        end

        if depth > 0 then
            folder_stack[#folder_stack + 1] = { guid = guid, name = name, r = folder_group_r, g = folder_group_g, b = folder_group_b, muted = track_muted, soloed = track_soloed }
        elseif depth < 0 then
            for _ = 1, -depth do
                if #folder_stack > 0 then
                    table.remove(folder_stack)
                end
            end
        end
    end
    local master_match_filter = PatchbayFilterMatchesName(filter, "master")
    local master_match_sel = true
    if (only_selected or selected_with_children or selected_subtree) and #selected_tracks > 0 then
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
                if sel ~= master and explicit_show_mainsend then
                    for ti = 0, n - 1 do
                        local mt = r.GetTrack(0, ti)
                        if mt and r.ValidatePtr(mt, "MediaTrack*") and r.GetMediaTrackInfo_Value(mt, "B_MAINSEND") == 1
                            and (TrackHasExplicitSend(sel, mt) or TrackHasExplicitSend(mt, sel))
                        then
                            master_match_sel = true
                            break
                        end
                    end
                    if master_match_sel then break end
                end
            end
        end
    end
    local nmsnd = r.GetTrackNumSends(master, 0)
    local nmrec = r.GetTrackNumSends(master, -1)
    local master_has_routing
    if show_unrouted then
        master_has_routing = false
    elseif only_explicit then
        master_has_routing = (nmsnd > 0 or nmrec > 0 or (explicit_show_mainsend and visible_mainsend))
    else
        master_has_routing = (any_mainsend or nmsnd > 0 or nmrec > 0)
    end
    if (selected_with_children or selected_subtree) and selected_set[master] then master_has_routing = true end
    local show_master = cfg.patchbay_show_master ~= false
    if show_master and master_has_routing and master_match_filter and master_match_sel and (not group_set or group_set[MASTER_GUID]) then
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

function HandlePatchbayExternalAction(cfg, layout_locked)
    local serial = r.GetExtState("TK_PATCHBAY_ACTIONS", "serial")
    local command = r.GetExtState("TK_PATCHBAY_ACTIONS", "command")
    if not command or command == "" or not serial or serial == "" or serial == PB.external_action_serial then return end
    PB.external_action_serial = serial
    r.DeleteExtState("TK_PATCHBAY_ACTIONS", "command", false)
    r.DeleteExtState("TK_PATCHBAY_ACTIONS", "serial", false)
    if command == "fit_view" then
        if not layout_locked then pending_fit_view = true end
    elseif command == "center_view" then
        if not layout_locked then pending_center_view = true end
    elseif command == "auto_layout" then
        if not layout_locked then
            pending_auto_layout = true
            pending_center_view = true
            layout_dirty = true
        end
    elseif command == "focus_selected_tree" then
        cfg.patchbay_selected_with_children = true
        cfg.routing_only_selected = false
        cfg.patchbay_selected_subtree = false
        if _G.SaveConfig then _G.SaveConfig() end
    elseif command == "focus_selected_subtree" then
        cfg.patchbay_selected_subtree = true
        cfg.routing_only_selected = false
        cfg.patchbay_selected_with_children = false
        if _G.SaveConfig then _G.SaveConfig() end
    elseif command == "show_all_tracks" then
        cfg.routing_only_selected = false
        cfg.patchbay_selected_with_children = false
        cfg.patchbay_selected_subtree = false
        cfg.patchbay_show_unrouted = false
        if _G.SaveConfig then _G.SaveConfig() end
    elseif command == "toggle_cable_shop" then
        cable_shop_open = not cable_shop_open
    elseif command == "toggle_route_audit" then
        RunRouteAudit()
        PB.open_route_audit_popup = true
    end
end

local function AutoLayout(tracks)
    local cfg = GetConfig()
    if PatchbayLayoutKind(GetLayoutPreset(cfg)) == "folder" then
        PatchbayAutoLayoutFolderTree(tracks, cfg)
        return
    end
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

function PatchbayAutoLayoutFolderTree(tracks, cfg)
    local col_w = LayoutColW(cfg)
    local row_h = LayoutRowH(cfg)
    local preset = GetLayoutPreset(cfg)
    local old_positions = node_positions
    local by_guid = {}
    local children = {}
    local roots = {}
    local master_entry = nil
    for i = 1, #tracks do
        local tr = tracks[i]
        if tr.is_master then
            master_entry = tr
        else
            by_guid[tr.guid] = tr
            children[tr.guid] = {}
        end
    end
    for i = 1, #tracks do
        local tr = tracks[i]
        if not tr.is_master then
            local parent_guid = tr.folder_parent_guid
            if parent_guid and by_guid[parent_guid] then
                children[parent_guid][#children[parent_guid] + 1] = tr
            else
                roots[#roots + 1] = tr
            end
        end
    end
    local function sort_by_track_index(a, b) return (a.idx or 0) < (b.idx or 0) end
    table.sort(roots, sort_by_track_index)
    for _, list in pairs(children) do table.sort(list, sort_by_track_index) end
    local folder_roots = {}
    local loose_roots = {}
    for i = 1, #roots do
        local tr = roots[i]
        local child_list = children[tr.guid] or {}
        if tr.folder_is_parent or #child_list > 0 then
            folder_roots[#folder_roots + 1] = tr
        else
            loose_roots[#loose_roots + 1] = tr
        end
    end
    local leaf_counts = {}
    local function count_leaves(tr)
        local list = children[tr.guid] or {}
        if #list == 0 then
            leaf_counts[tr.guid] = 1
            return 1
        end
        local total = 0
        for i = 1, #list do total = total + count_leaves(list[i]) end
        if total < 1 then total = 1 end
        leaf_counts[tr.guid] = total
        return total
    end
    for i = 1, #folder_roots do count_leaves(folder_roots[i]) end
    node_positions = {}
    local max_x = 40
    local max_y = 40
    local function place_node(tr, x, y)
        if pinned_nodes[tr.guid] and old_positions[tr.guid] then
            node_positions[tr.guid] = { x = old_positions[tr.guid].x, y = old_positions[tr.guid].y }
        else
            node_positions[tr.guid] = { x = x, y = y }
        end
        local p = node_positions[tr.guid]
        if p.x > max_x then max_x = p.x end
        if p.y > max_y then max_y = p.y end
    end
    if preset == "folder_tree_horizontal" then
        local function place_tree_horizontal(tr, depth, top_leaf)
            local leaves = leaf_counts[tr.guid] or 1
            local x = 40 + depth * col_w
            local y = 40 + (top_leaf + ((leaves - 1) * 0.5)) * row_h
            place_node(tr, x, y)
            local child_top = top_leaf
            local list = children[tr.guid] or {}
            for i = 1, #list do
                place_tree_horizontal(list[i], depth + 1, child_top)
                child_top = child_top + (leaf_counts[list[i].guid] or 1)
            end
        end
        local leaf_cursor = 0
        for i = 1, #folder_roots do
            place_tree_horizontal(folder_roots[i], 0, leaf_cursor)
            leaf_cursor = leaf_cursor + (leaf_counts[folder_roots[i].guid] or 1) + 1
        end
        local loose_x = (#folder_roots > 0) and (max_x + col_w) or 40
        for i = 1, #loose_roots do
            place_node(loose_roots[i], loose_x, 40 + (i - 1) * row_h)
        end
        if master_entry then
            local mx = max_x + col_w
            local my = math.max(40, ((max_y - 40) * 0.5) + 40)
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
        return
    end
    local function place_tree(tr, depth, left_leaf)
        local leaves = leaf_counts[tr.guid] or 1
        local x = 40 + (left_leaf + ((leaves - 1) * 0.5)) * col_w
        local y = 40 + depth * row_h
        place_node(tr, x, y)
        local child_left = left_leaf
        local list = children[tr.guid] or {}
        for i = 1, #list do
            place_tree(list[i], depth + 1, child_left)
            child_left = child_left + (leaf_counts[list[i].guid] or 1)
        end
    end
    local leaf_cursor = 0
    for i = 1, #folder_roots do
        place_tree(folder_roots[i], 0, leaf_cursor)
        leaf_cursor = leaf_cursor + (leaf_counts[folder_roots[i].guid] or 1) + 1
    end
    local tree_has_nodes = #folder_roots > 0
    local loose_x = 40
    if tree_has_nodes then
        local tree_span = math.max(1, leaf_cursor - 1)
        loose_x = 40 + math.max(0, (tree_span - 1) * col_w * 0.5)
    end
    local loose_y = tree_has_nodes and (max_y + row_h * 1.25) or 40
    for i = 1, #loose_roots do
        local tr = loose_roots[i]
        local y = loose_y + (i - 1) * row_h
        place_node(tr, loose_x, y)
    end
    if master_entry then
        local mx = max_x + col_w
        local my = math.max(40, ((max_y - 40) * 0.5) + 40)
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
    local master_pos = node_positions[MASTER_GUID]
    local next_x = master_pos and master_pos.x or (max_x + col_w)
    local next_y = master_pos and (master_pos.y + row_h) or 40
    if master_pos then
        for _, p in pairs(node_positions) do
            if math.abs((p.x or 0) - next_x) < GRID then
                local y = (p.y or 0) + row_h
                if y > next_y then next_y = y end
            end
        end
    end
    for i = 1, #tracks do
        local g = tracks[i].guid
        if not node_positions[g] then
            node_positions[g] = { x = next_x, y = next_y }
            next_y = next_y + row_h
            layout_dirty = true
        end
    end
end

function SnapNodeToGrid(guid)
    local p = node_positions[guid]
    if not p or pinned_nodes[guid] then return false end
    local nx = math.floor((p.x / GRID) + 0.5) * GRID
    local ny = math.floor((p.y / GRID) + 0.5) * GRID
    if nx == p.x and ny == p.y then return false end
    p.x = nx
    p.y = ny
    return true
end

local function AlignVisibleNodesToGrid(tracks)
    if not tracks or #tracks == 0 then return end
    local moved = false
    for i = 1, #tracks do
        local g = tracks[i].guid
        if SnapNodeToGrid(g) then moved = true end
    end
    if moved then
        layout_dirty = true
    end
end

function SnapMovedNodesToGrid(guid)
    if not guid then return false end
    local moved = false
    if pb_selected_set[guid] then
        for sg, _ in pairs(pb_selected_set) do
            if SnapNodeToGrid(sg) then moved = true end
        end
    else
        moved = SnapNodeToGrid(guid)
    end
    if moved then layout_dirty = true end
    return moved
end

function PatchbayMovedNodeGuids(guid)
    local guids = {}
    if not guid then return guids end
    if pb_selected_set[guid] then
        for sg, _ in pairs(pb_selected_set) do
            if node_positions[sg] and not pinned_nodes[sg] then
                guids[#guids + 1] = sg
            end
        end
    elseif node_positions[guid] and not pinned_nodes[guid] then
        guids[#guids + 1] = guid
    end
    return guids
end

function PatchbayNodeLayoutRect(guid, dx, dy)
    local p = node_positions[guid]
    if not p then return nil end
    dx = dx or 0
    dy = dy or 0
    local x1 = p.x + dx
    local y1 = p.y + dy
    return x1, y1, x1 + NodeW(), y1 + NodeH(guid)
end

function PatchbayMovedGroupRect(guids, dx, dy)
    local min_x, min_y, max_x, max_y = nil, nil, nil, nil
    for i = 1, #guids do
        local x1, y1, x2, y2 = PatchbayNodeLayoutRect(guids[i], dx, dy)
        if x1 then
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
    return min_x, min_y, max_x, max_y
end

function PatchbayRectsOverlap(ax1, ay1, ax2, ay2, bx1, by1, bx2, by2, pad)
    return ax1 < bx2 + pad and ax2 > bx1 - pad and ay1 < by2 + pad and ay2 > by1 - pad
end

function PatchbayOffsetHasOverlap(guids, moving_set, tracks, dx, dy, pad)
    local ax1, ay1, ax2, ay2 = PatchbayMovedGroupRect(guids, dx, dy)
    if not ax1 then return false end
    for i = 1, #tracks do
        local guid = tracks[i].guid
        if not moving_set[guid] then
            local bx1, by1, bx2, by2 = PatchbayNodeLayoutRect(guid, 0, 0)
            if bx1 and PatchbayRectsOverlap(ax1, ay1, ax2, ay2, bx1, by1, bx2, by2, pad) then
                return true
            end
        end
    end
    return false
end

function PatchbayCollectOverlapTracks(visible_tracks)
    local out = {}
    local seen = {}
    local function add_guid(guid)
        if guid and node_positions[guid] and not seen[guid] then
            seen[guid] = true
            out[#out + 1] = { guid = guid }
        end
    end
    if visible_tracks then
        for i = 1, #visible_tracks do add_guid(visible_tracks[i].guid) end
    end
    local n = r.CountTracks(0)
    for i = 0, n - 1 do
        local tr = r.GetTrack(0, i)
        if tr then add_guid(r.GetTrackGUID(tr)) end
    end
    add_guid(MASTER_GUID)
    return out
end

function ResolveMovedNodesOverlap(guid, tracks)
    if not guid or not tracks then return false end
    tracks = PatchbayCollectOverlapTracks(tracks)
    local guids = PatchbayMovedNodeGuids(guid)
    if #guids == 0 then return false end
    local moving_set = {}
    for i = 1, #guids do moving_set[guids[i]] = true end
    local pad = 8
    if not PatchbayOffsetHasOverlap(guids, moving_set, tracks, 0, 0, pad) then return false end
    local cfg = GetConfig()
    local step = ((cfg and cfg.patchbay_snap_to_grid == true) and GRID) or 20
    local best_dx, best_dy, best_d2 = nil, nil, nil
    for ring = 1, 40 do
        for gx = -ring, ring do
            for gy = -ring, ring do
                if math.abs(gx) == ring or math.abs(gy) == ring then
                    local dx = gx * step
                    local dy = gy * step
                    if not PatchbayOffsetHasOverlap(guids, moving_set, tracks, dx, dy, pad) then
                        local d2 = dx * dx + dy * dy
                        if not best_d2 or d2 < best_d2 then
                            best_dx, best_dy, best_d2 = dx, dy, d2
                        end
                    end
                end
            end
        end
        if best_dx then break end
    end
    if not best_dx then return false end
    for i = 1, #guids do
        local p = node_positions[guids[i]]
        if p then
            p.x = p.x + best_dx
            p.y = p.y + best_dy
        end
    end
    layout_dirty = true
    return true
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

local function CableShopKey(key, field)
    return "patchbay_cable_shop_" .. key .. "_" .. field
end

local function EnsureCableShopConfig(cfg)
    if not cfg then return end
    if cfg.patchbay_cable_shop_user_presets == nil then cfg.patchbay_cable_shop_user_presets = "" end
    for i = 1, #CABLE_SHOP_ORDER do
        local key = CABLE_SHOP_ORDER[i]
        local d = CABLE_SHOP_DEFAULTS[key]
        if cfg[CableShopKey(key, "color")] == nil then cfg[CableShopKey(key, "color")] = d.color end
        if cfg[CableShopKey(key, "hover")] == nil then cfg[CableShopKey(key, "hover")] = d.hover end
        if cfg[CableShopKey(key, "thickness")] == nil then cfg[CableShopKey(key, "thickness")] = d.thickness end
        if cfg[CableShopKey(key, "visible")] == nil then cfg[CableShopKey(key, "visible")] = d.visible end
    end
end

local function ResetCableShopType(cfg, key)
    local d = CABLE_SHOP_DEFAULTS[key]
    if not cfg or not d then return end
    cfg[CableShopKey(key, "color")] = d.color
    cfg[CableShopKey(key, "hover")] = d.hover
    cfg[CableShopKey(key, "thickness")] = d.thickness
    cfg[CableShopKey(key, "visible")] = d.visible
end

local function ApplyCableShopPresetData(cfg, preset)
    if not cfg or not preset or not preset.styles then return false end
    for i = 1, #CABLE_SHOP_ORDER do
        local key = CABLE_SHOP_ORDER[i]
        local style = preset.styles[key] or CABLE_SHOP_DEFAULTS[key]
        cfg[CableShopKey(key, "color")] = style.color
        cfg[CableShopKey(key, "hover")] = style.hover
        cfg[CableShopKey(key, "thickness")] = style.thickness
        cfg[CableShopKey(key, "visible")] = style.visible ~= false
    end
    return true
end

local function SanitizeCableShopPresetName(name, slot)
    name = tostring(name or ""):gsub("[|;,~\r\n\t]", " "):gsub("%s+", " "):match("^%s*(.-)%s*$") or ""
    if name == "" then name = "Preset " .. tostring(slot or 1) end
    return name
end

local function GetCableShopUserPresets(cfg)
    local presets = {}
    local raw = tostring((cfg and cfg.patchbay_cable_shop_user_presets) or "")
    for entry in raw:gmatch("[^;]+") do
        local slot_str, name, body = entry:match("^(%d+)|([^|]*)|(.+)$")
        local slot = tonumber(slot_str)
        if slot and slot >= 1 and slot <= CABLE_SHOP_USER_PRESET_SLOTS then
            local preset = { name = SanitizeCableShopPresetName(name, slot), styles = {} }
            for item in body:gmatch("[^~]+") do
                local key, color, hover, thickness, visible = item:match("^([^:]+):([^:]+):([^:]+):([^:]+):([^:]+)$")
                if CABLE_SHOP_DEFAULTS[key] then
                    preset.styles[key] = {
                        color = tonumber(color) or CABLE_SHOP_DEFAULTS[key].color,
                        hover = tonumber(hover) or CABLE_SHOP_DEFAULTS[key].hover,
                        thickness = tonumber(thickness) or CABLE_SHOP_DEFAULTS[key].thickness,
                        visible = visible == "1"
                    }
                end
            end
            presets[slot] = preset
        end
    end
    return presets
end

local function SerializeCableShopUserPresets(cfg, presets)
    local entries = {}
    for slot = 1, CABLE_SHOP_USER_PRESET_SLOTS do
        local preset = presets[slot]
        if preset and preset.styles then
            local items = {}
            for i = 1, #CABLE_SHOP_ORDER do
                local key = CABLE_SHOP_ORDER[i]
                local style = preset.styles[key] or CABLE_SHOP_DEFAULTS[key]
                items[#items + 1] = table.concat({ key, tostring(style.color), tostring(style.hover), tostring(style.thickness), style.visible ~= false and "1" or "0" }, ":")
            end
            entries[#entries + 1] = tostring(slot) .. "|" .. SanitizeCableShopPresetName(preset.name, slot) .. "|" .. table.concat(items, "~")
        end
    end
    cfg.patchbay_cable_shop_user_presets = table.concat(entries, ";")
end

local function CaptureCableShopPreset(cfg, name, slot)
    EnsureCableShopConfig(cfg)
    local preset = { name = SanitizeCableShopPresetName(name, slot), styles = {} }
    for i = 1, #CABLE_SHOP_ORDER do
        local key = CABLE_SHOP_ORDER[i]
        preset.styles[key] = {
            color = cfg[CableShopKey(key, "color")],
            hover = cfg[CableShopKey(key, "hover")],
            thickness = tonumber(cfg[CableShopKey(key, "thickness")]) or CABLE_SHOP_DEFAULTS[key].thickness,
            visible = cfg[CableShopKey(key, "visible")] ~= false
        }
    end
    return preset
end

local function CableShopUserSlotLabel(presets, slot)
    local preset = presets and presets[slot]
    if preset then return tostring(slot) .. ": " .. preset.name end
    return tostring(slot) .. ": Empty"
end

local function GetCableTypeKey(cable)
    if not cable then return "post_fader" end
    if cable.is_main then return "main" end
    if cable.muted then return "muted" end
    if cable.mode == 1 then return "pre_fx" end
    if cable.mode == 3 then return "pre_fader" end
    return "post_fader"
end

local function GetCableStyle(cable, cfg)
    EnsureCableShopConfig(cfg)
    local key = GetCableTypeKey(cable)
    return {
        key = key,
        color = cfg[CableShopKey(key, "color")],
        hover = cfg[CableShopKey(key, "hover")],
        thickness = tonumber(cfg[CableShopKey(key, "thickness")]) or CABLE_SHOP_DEFAULTS[key].thickness,
        visible = cfg[CableShopKey(key, "visible")] ~= false
    }
end

local function GetCableOverlayStyle(key, cfg)
    EnsureCableShopConfig(cfg)
    return {
        color = cfg[CableShopKey(key, "color")],
        hover = cfg[CableShopKey(key, "hover")],
        thickness = tonumber(cfg[CableShopKey(key, "thickness")]) or CABLE_SHOP_DEFAULTS[key].thickness,
        visible = cfg[CableShopKey(key, "visible")] ~= false
    }
end

local function AudioPairLabel(chan)
    chan = math.floor(tonumber(chan) or -1)
    if chan < 0 then return "off" end
    local mono = false
    if chan >= 1024 then
        mono = true
        chan = chan - 1024
    end
    local left = chan + 1
    if mono then return string.format("%d mono", left) end
    return string.format("%d/%d", left, left + 1)
end

local function MidiChannelLabel(chan, source)
    chan = math.floor(tonumber(chan) or 31)
    if chan == 31 then return "off" end
    if chan == 0 then return source and "all" or "original" end
    return tostring(chan)
end

local function GetSendTypeInfo(src, send_idx, is_main)
    if is_main then
        return { label = "Main audio", details = "Type: Main audio", badge = "", has_audio = true, has_midi = false, is_sidechain = false }
    end
    local src_chan = math.floor(r.GetTrackSendInfo_Value(src, 0, send_idx, "I_SRCCHAN") or -1)
    local dst_chan = math.floor(r.GetTrackSendInfo_Value(src, 0, send_idx, "I_DSTCHAN") or 0)
    local midi_flags = math.floor(r.GetTrackSendInfo_Value(src, 0, send_idx, "I_MIDIFLAGS") or 1024)
    local midi_src = midi_flags & 31
    local midi_dst = (midi_flags >> 5) & 31
    local has_audio = src_chan >= 0
    local is_sidechain = has_audio and dst_chan >= 2
    local has_midi = midi_flags >= 0 and (midi_flags & 1024) == 0 and midi_src ~= 31 and midi_dst ~= 31
    local label = "Disabled"
    local badge = ""
    local badge_col = 0x666666DD
    if is_sidechain and has_midi then
        label = "Sidechain + MIDI"
        badge = "SC+MIDI"
        badge_col = 0x6EBE7AFF
    elseif is_sidechain then
        label = "Sidechain"
        badge = "SC"
        badge_col = 0x65B872FF
    elseif has_audio and has_midi then
        label = "Audio + MIDI"
        badge = "A+MIDI"
        badge_col = 0x4F8FD8FF
    elseif has_midi then
        label = "MIDI only"
        badge = "MIDI"
        badge_col = 0x4F8FD8FF
    elseif has_audio then
        label = "Audio"
    end
    local parts = {}
    if has_audio then parts[#parts + 1] = "Audio " .. AudioPairLabel(src_chan) .. " -> " .. AudioPairLabel(dst_chan) end
    if has_midi then parts[#parts + 1] = "MIDI " .. MidiChannelLabel(midi_src, true) .. " -> " .. MidiChannelLabel(midi_dst, false) end
    if #parts == 0 then parts[#parts + 1] = "No audio or MIDI" end
    return {
        label = label,
        details = "Type: " .. table.concat(parts, " | "),
        badge = badge,
        badge_col = badge_col,
        has_audio = has_audio,
        has_midi = has_midi,
        is_sidechain = is_sidechain,
        src_chan = src_chan,
        dst_chan = dst_chan,
        midi_src = midi_src,
        midi_dst = midi_dst,
        midi_flags = midi_flags
    }
end

function PatchbayTrackDisplayName(track, fallback)
    if track and r.ValidatePtr(track, "MediaTrack*") then
        local _, name = r.GetTrackName(track)
        if name and name ~= "" then return name end
    end
    return fallback or "Track"
end

function PatchbayJoinLimitedNames(names, total_count)
    if not total_count or total_count <= 0 then return "None" end
    if not names or #names == 0 then return tostring(total_count) end
    local text = table.concat(names, ", ")
    local hidden = total_count - #names
    if hidden > 0 then text = text .. ", +" .. tostring(hidden) end
    return text
end

function PatchbayCollectRouteNames(track, category, max_count)
    local names = {}
    if not track or not r.ValidatePtr(track, "MediaTrack*") then return names, 0 end
    local total_count = r.GetTrackNumSends(track, category)
    local key = category == 0 and "P_DESTTRACK" or "P_SRCTRACK"
    local limit = math.min(total_count, max_count or 4)
    for send_index = 0, limit - 1 do
        local other_track = r.GetTrackSendInfo_Value(track, category, send_index, key)
        names[#names + 1] = PatchbayTrackDisplayName(other_track, category == 0 and "Destination" or "Source")
    end
    return names, total_count
end

function PatchbayCollectMasterSendNames(max_count)
    local names = {}
    local total_count = 0
    local track_count = r.CountTracks(0)
    for track_index = 0, track_count - 1 do
        local track = r.GetTrack(0, track_index)
        if r.GetMediaTrackInfo_Value(track, "B_MAINSEND") == 1 then
            total_count = total_count + 1
            if #names < (max_count or 4) then
                names[#names + 1] = PatchbayTrackDisplayName(track, "Track")
            end
        end
    end
    return names, total_count
end

function PatchbayCollectFolderChildNames(track_info, tracks, max_count)
    local names = {}
    local total_count = 0
    if not track_info or not tracks then return names, 0 end
    for track_index = 1, #tracks do
        local child = tracks[track_index]
        if child.folder_parent_guid == track_info.guid then
            total_count = total_count + 1
            if #names < (max_count or 4) then
                names[#names + 1] = child.name or "Child"
            end
        end
    end
    return names, total_count
end

function PatchbayBuildPinTooltip(track_info, side, tracks, guid_to, folder_pin_enabled, all_locked)
    if not track_info then return "" end
    local track_name = track_info.is_master and "MASTER" or string.format("#%d  %s", (track_info.idx or 0) + 1, track_info.name or "Track")
    if side == "in" then
        if track_info.is_master then
            local main_names, main_count = PatchbayCollectMasterSendNames(4)
            return string.format("Master input\nMain sends in: %d\nFrom: %s", main_count, PatchbayJoinLimitedNames(main_names, main_count))
        end
        local receive_names, receive_count = PatchbayCollectRouteNames(track_info.track, -1, 4)
        return string.format("Input / receives\n%s\nReceives: %d\nFrom: %s", track_name, receive_count, PatchbayJoinLimitedNames(receive_names, receive_count))
    elseif side == "out" then
        local send_names, send_count = PatchbayCollectRouteNames(track_info.track, 0, 4)
        local main_send = r.GetMediaTrackInfo_Value(track_info.track, "B_MAINSEND") == 1
        local main_text = main_send and "On" or "Off"
        return string.format("Output / sends\n%s\nExplicit sends: %d\nTo: %s\nMain send: %s", track_name, send_count, PatchbayJoinLimitedNames(send_names, send_count), main_text)
    elseif side == "folder" then
        local role = "Top-level"
        if track_info.folder_is_parent and track_info.is_folder_child then
            role = "Parent + child"
        elseif track_info.folder_is_parent then
            role = "Parent"
        elseif track_info.is_folder_child then
            role = "Child"
        end
        local parent_name = "None"
        if track_info.folder_parent_guid and guid_to and guid_to[track_info.folder_parent_guid] then
            parent_name = guid_to[track_info.folder_parent_guid].name or "Parent"
        end
        local child_names, child_count = PatchbayCollectFolderChildNames(track_info, tracks, 4)
        local status = "Drag to assign one child"
        if all_locked then
            status = "Folder assignment is locked"
        elseif not r.ReorderSelectedTracks then
            status = "Folder assignment unavailable"
        elseif not folder_pin_enabled then
            status = "Top-level tracks only"
        end
        return string.format("Folder connector\n%s\nRole: %s\nParent: %s\nChildren: %d (%s)\n%s", track_name, role, parent_name, child_count, PatchbayJoinLimitedNames(child_names, child_count), status)
    end
    return track_name
end

function PatchbayInheritedStatusText(track_info, prefix)
    local lines = {}
    if track_info then
        if track_info.ancestor_muted then
            lines[#lines + 1] = string.format("%s muted by folder ancestor: %s", prefix or "Track", track_info.ancestor_muted_name or "Parent")
        end
        if track_info.ancestor_soloed then
            lines[#lines + 1] = string.format("%s affected by soloed folder ancestor: %s", prefix or "Track", track_info.ancestor_soloed_name or "Parent")
        end
    end
    if #lines == 0 then return "" end
    return "\n" .. table.concat(lines, "\n")
end

function PatchbayCableInheritedMuteInfo(cable, guid_to)
    local src_info = guid_to and guid_to[cable.sg] or nil
    local dst_info = guid_to and guid_to[cable.dg] or nil
    if src_info and (src_info.track_muted or src_info.ancestor_muted) then
        return true, src_info.track_muted and (src_info.name or "Source") or (src_info.ancestor_muted_name or "Source ancestor"), "source"
    end
    if dst_info and (dst_info.track_muted or dst_info.ancestor_muted) then
        return true, dst_info.track_muted and (dst_info.name or "Destination") or (dst_info.ancestor_muted_name or "Destination ancestor"), "destination"
    end
    return false, nil, nil
end

local function ApplySendTypePreset(src, dst, send_idx, preset)
    if not src or not r.ValidatePtr(src, "MediaTrack*") then return end
    r.Undo_BeginBlock()
    if preset == "audio" then
        r.SetTrackSendInfo_Value(src, 0, send_idx, "I_SRCCHAN", 0)
        r.SetTrackSendInfo_Value(src, 0, send_idx, "I_DSTCHAN", 0)
        r.SetTrackSendInfo_Value(src, 0, send_idx, "I_MIDIFLAGS", 1024)
    elseif preset == "sidechain" then
        if dst and r.ValidatePtr(dst, "MediaTrack*") then
            local dst_channels = math.floor(r.GetMediaTrackInfo_Value(dst, "I_NCHAN") or 2)
            if dst_channels < 4 then r.SetMediaTrackInfo_Value(dst, "I_NCHAN", 4) end
        end
        r.SetTrackSendInfo_Value(src, 0, send_idx, "I_SRCCHAN", 0)
        r.SetTrackSendInfo_Value(src, 0, send_idx, "I_DSTCHAN", 2)
        r.SetTrackSendInfo_Value(src, 0, send_idx, "I_MIDIFLAGS", 1024)
    elseif preset == "midi" then
        r.SetTrackSendInfo_Value(src, 0, send_idx, "I_SRCCHAN", -1)
        r.SetTrackSendInfo_Value(src, 0, send_idx, "I_DSTCHAN", 0)
        r.SetTrackSendInfo_Value(src, 0, send_idx, "I_MIDIFLAGS", 0)
    elseif preset == "audio_midi" then
        r.SetTrackSendInfo_Value(src, 0, send_idx, "I_SRCCHAN", 0)
        r.SetTrackSendInfo_Value(src, 0, send_idx, "I_DSTCHAN", 0)
        r.SetTrackSendInfo_Value(src, 0, send_idx, "I_MIDIFLAGS", 0)
    end
    r.Undo_EndBlock("Patchbay: set send type", -1)
    r.TrackList_AdjustWindows(false)
    r.UpdateArrange()
end

function PatchbayMidiFlags(src_chan, dst_chan, enabled)
    if not enabled then return 1024 end
    src_chan = math.floor(tonumber(src_chan) or 0)
    dst_chan = math.floor(tonumber(dst_chan) or 0)
    if src_chan < 0 then src_chan = 31 elseif src_chan > 31 then src_chan = 31 end
    if dst_chan < 0 then dst_chan = 31 elseif dst_chan > 31 then dst_chan = 31 end
    return src_chan | (dst_chan << 5)
end

function PatchbayEnsureTrackChannels(track, needed)
    if not track or not r.ValidatePtr(track, "MediaTrack*") then return end
    needed = math.floor(tonumber(needed) or 2)
    if needed < 2 then needed = 2 end
    if (needed % 2) ~= 0 then needed = needed + 1 end
    local current = math.floor(r.GetMediaTrackInfo_Value(track, "I_NCHAN") or 2)
    if current < needed then r.SetMediaTrackInfo_Value(track, "I_NCHAN", needed) end
end

function PatchbaySetSendChannelIO(src, dst, send_idx, field, value)
    if not src or not r.ValidatePtr(src, "MediaTrack*") or send_idx < 0 then return end
    r.Undo_BeginBlock()
    if field == "I_DSTCHAN" then
        PatchbayEnsureTrackChannels(dst, math.floor(tonumber(value) or 0) + 2)
    elseif field == "I_SRCCHAN" and tonumber(value) and tonumber(value) >= 0 then
        local chan = math.floor(tonumber(value) or 0)
        local mono = chan >= 1024
        if mono then chan = chan - 1024 end
        PatchbayEnsureTrackChannels(src, chan + (mono and 1 or 2))
    end
    r.SetTrackSendInfo_Value(src, 0, send_idx, field, value)
    r.Undo_EndBlock("Patchbay: set channel I/O", -1)
    r.TrackList_AdjustWindows(false)
    r.UpdateArrange()
end

function RenderChannelIOControls(ctx, src, dst, idx)
    r.ImGui_Separator(ctx)
    local src_chan = math.floor(r.GetTrackSendInfo_Value(src, 0, idx, "I_SRCCHAN") or -1)
    local dst_chan = math.floor(r.GetTrackSendInfo_Value(src, 0, idx, "I_DSTCHAN") or 0)
    local midi_flags = math.floor(r.GetTrackSendInfo_Value(src, 0, idx, "I_MIDIFLAGS") or 1024)
    local midi_src = midi_flags & 31
    local midi_dst = (midi_flags >> 5) & 31
    local audio_enabled = src_chan >= 0
    local midi_enabled = midi_flags >= 0 and (midi_flags & 1024) == 0 and midi_src ~= 31 and midi_dst ~= 31
    local ca, va = r.ImGui_Checkbox(ctx, "Audio", audio_enabled)
    if ca then PatchbaySetSendChannelIO(src, dst, idx, "I_SRCCHAN", va and 0 or -1) end
    if audio_enabled then
        r.ImGui_PushItemWidth(ctx, 180)
        local src_channels = math.floor(r.GetMediaTrackInfo_Value(src, "I_NCHAN") or 2)
        local max_src = math.max(16, src_channels)
        if r.ImGui_BeginCombo(ctx, "Audio source", AudioPairLabel(src_chan)) then
            local ch = 0
            while ch < max_src do
                local value = ch
                if r.ImGui_Selectable(ctx, AudioPairLabel(value), src_chan == value) then PatchbaySetSendChannelIO(src, dst, idx, "I_SRCCHAN", value) end
                ch = ch + 2
            end
            ch = 0
            while ch < max_src do
                local value = 1024 + ch
                if r.ImGui_Selectable(ctx, AudioPairLabel(value), src_chan == value) then PatchbaySetSendChannelIO(src, dst, idx, "I_SRCCHAN", value) end
                ch = ch + 1
            end
            r.ImGui_EndCombo(ctx)
        end
        local dst_channels = math.floor(r.GetMediaTrackInfo_Value(dst, "I_NCHAN") or 2)
        local max_dst = math.max(16, dst_channels)
        if r.ImGui_BeginCombo(ctx, "Audio destination", AudioPairLabel(dst_chan)) then
            local ch = 0
            while ch < max_dst do
                if r.ImGui_Selectable(ctx, AudioPairLabel(ch), dst_chan == ch) then PatchbaySetSendChannelIO(src, dst, idx, "I_DSTCHAN", ch) end
                ch = ch + 2
            end
            r.ImGui_EndCombo(ctx)
        end
        r.ImGui_PopItemWidth(ctx)
    end
    r.ImGui_Separator(ctx)
    local cm, vm = r.ImGui_Checkbox(ctx, "MIDI", midi_enabled)
    if cm then PatchbaySetSendChannelIO(src, dst, idx, "I_MIDIFLAGS", PatchbayMidiFlags(vm and 0 or 31, vm and 0 or 31, vm)) end
    if midi_enabled then
        r.ImGui_PushItemWidth(ctx, 180)
        if r.ImGui_BeginCombo(ctx, "MIDI source", MidiChannelLabel(midi_src, true)) then
            if r.ImGui_Selectable(ctx, "all", midi_src == 0) then PatchbaySetSendChannelIO(src, dst, idx, "I_MIDIFLAGS", PatchbayMidiFlags(0, midi_dst, true)) end
            for ch = 1, 16 do
                if r.ImGui_Selectable(ctx, tostring(ch), midi_src == ch) then PatchbaySetSendChannelIO(src, dst, idx, "I_MIDIFLAGS", PatchbayMidiFlags(ch, midi_dst, true)) end
            end
            r.ImGui_EndCombo(ctx)
        end
        if r.ImGui_BeginCombo(ctx, "MIDI destination", MidiChannelLabel(midi_dst, false)) then
            if r.ImGui_Selectable(ctx, "original", midi_dst == 0) then PatchbaySetSendChannelIO(src, dst, idx, "I_MIDIFLAGS", PatchbayMidiFlags(midi_src, 0, true)) end
            for ch = 1, 16 do
                if r.ImGui_Selectable(ctx, tostring(ch), midi_dst == ch) then PatchbaySetSendChannelIO(src, dst, idx, "I_MIDIFLAGS", PatchbayMidiFlags(midi_src, ch, true)) end
            end
            r.ImGui_EndCombo(ctx)
        end
        r.ImGui_PopItemWidth(ctx)
    end
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

local function DrawBezierStripes(draw_list, x0, y0, x1, y1, x2, y2, x3, y3, color, stripe_thickness, cable_thickness, diagonal)
    local stripe_len = math.max(1, cable_thickness * 0.9)
    local stripe_thick = math.max(1, stripe_thickness)
    local stripe_gap = 32
    local chord = math.sqrt((x3 - x0) * (x3 - x0) + (y3 - y0) * (y3 - y0))
    local sample_count = math.max(32, math.min(240, math.floor(chord / 4)))
    local prev_x, prev_y = BezierPoint(0.08, x0, y0, x1, y1, x2, y2, x3, y3)
    local distance = 0
    local next_stripe = stripe_gap
    for i = 1, sample_count do
        local t = 0.08 + (0.84 * i / sample_count)
        local cx, cy = BezierPoint(t, x0, y0, x1, y1, x2, y2, x3, y3)
        local segment = math.sqrt((cx - prev_x) * (cx - prev_x) + (cy - prev_y) * (cy - prev_y))
        distance = distance + segment
        if distance >= next_stripe then
            local ax, ay = BezierPoint(math.max(0, t - 0.01), x0, y0, x1, y1, x2, y2, x3, y3)
            local bx, by = BezierPoint(math.min(1, t + 0.01), x0, y0, x1, y1, x2, y2, x3, y3)
            local dx = bx - ax
            local dy = by - ay
            local len = math.sqrt(dx * dx + dy * dy)
            if len > 0.001 then
                local tx = dx / len
                local ty = dy / len
                local nx = -ty
                local ny = tx
                if diagonal and r.ImGui_DrawList_AddQuadFilled then
                    local half_n = stripe_len * 0.5
                    local half_t = math.max(0.7, stripe_thick * 0.5)
                    local slant = cable_thickness * 0.95
                    local bottom_x = cx - nx * half_n - tx * slant
                    local bottom_y = cy - ny * half_n - ty * slant
                    local top_x = cx + nx * half_n + tx * slant
                    local top_y = cy + ny * half_n + ty * slant
                    r.ImGui_DrawList_AddQuadFilled(draw_list,
                        bottom_x - tx * half_t, bottom_y - ty * half_t,
                        bottom_x + tx * half_t, bottom_y + ty * half_t,
                        top_x + tx * half_t, top_y + ty * half_t,
                        top_x - tx * half_t, top_y - ty * half_t,
                        color)
                else
                    local vx = nx
                    local vy = ny
                    if diagonal then
                        vx = (tx * 1.15) + (nx * 0.5)
                        vy = (ty * 1.15) + (ny * 0.5)
                        local vlen = math.sqrt(vx * vx + vy * vy)
                        if vlen > 0.001 then
                            vx = vx / vlen
                            vy = vy / vlen
                        end
                    end
                    r.ImGui_DrawList_AddLine(draw_list, cx - vx * stripe_len * 0.5, cy - vy * stripe_len * 0.5, cx + vx * stripe_len * 0.5, cy + vy * stripe_len * 0.5, color, stripe_thick)
                end
            end
            next_stripe = next_stripe + stripe_gap
        end
        prev_x, prev_y = cx, cy
    end
end

local function RenderCableShopHeader(ctx)
    local draw_list = r.ImGui_GetWindowDrawList(ctx)
    local avail_w = r.ImGui_GetContentRegionAvail(ctx)
    local header_h = 30
    r.ImGui_InvisibleButton(ctx, "##cable_shop_header", avail_w, header_h)
    local x1, y1 = r.ImGui_GetItemRectMin(ctx)
    local x2, y2 = r.ImGui_GetItemRectMax(ctx)
    local close_x = x2 - 16
    local close_y = (y1 + y2) * 0.5
    local mx, my = r.ImGui_GetMousePos(ctx)
    local close_hovered = mx >= close_x - 9 and mx <= close_x + 9 and my >= close_y - 9 and my <= close_y + 9
    local close_col = close_hovered and 0xFF7474FF or 0xE94343FF
    r.ImGui_DrawList_AddRectFilled(draw_list, x1, y1, x2, y2, 0x15171BFF, 6)
    r.ImGui_DrawList_AddLine(draw_list, x1, y2, x2, y2, 0x2A2E36FF, 1)
    r.ImGui_DrawList_AddCircleFilled(draw_list, close_x, close_y, 5.5, close_col)
    local text_h = r.ImGui_GetTextLineHeight(ctx)
    r.ImGui_DrawList_AddText(draw_list, x1 + 12, y1 + ((header_h - text_h) * 0.5), 0xE8E8E8FF, "Cable shop")
    if close_hovered and r.ImGui_IsMouseClicked(ctx, 0) then
        cable_shop_open = false
        return true
    end
    return false
end

function NotesReadProjExt(key)
    if type(r.GetSetProjExtState) == "function" then
        local _, value = r.GetSetProjExtState(0, "TK_NOTES", key, "")
        if value and value ~= "" then return value end
    end
    if type(r.GetProjExtState) == "function" then
        local ok, value = r.GetProjExtState(0, "TK_NOTES", key)
        if (ok == true or ok == 1) and value and value ~= "" then return value end
    end
    return ""
end

function NotesReadWorkbench(key)
    if type(r.GetSetProjExtState) == "function" then
        local _, value = r.GetSetProjExtState(0, "TK_WORKBENCH_NOTES", key, "")
        if value and value ~= "" then return value end
    end
    if type(r.GetProjExtState) == "function" then
        local ok, value = r.GetProjExtState(0, "TK_WORKBENCH_NOTES", key)
        if (ok == true or ok == 1) and value and value ~= "" then return value end
    end
    return ""
end

function NotesJsonDecode(str)
    if type(str) ~= "string" or str == "" then return nil end
    local pos = 1
    local parse_value
    local function skip_ws()
        local _, e = str:find("^[ \t\r\n]*", pos)
        if e then pos = e + 1 end
    end
    local function parse_string()
        pos = pos + 1
        local buf = {}
        while pos <= #str do
            local c = str:sub(pos, pos)
            if c == '"' then
                pos = pos + 1
                return table.concat(buf)
            elseif c == "\\" then
                local n = str:sub(pos + 1, pos + 1)
                if n == "n" then buf[#buf + 1] = "\n"
                elseif n == "t" then buf[#buf + 1] = "\t"
                elseif n == "r" then buf[#buf + 1] = "\r"
                elseif n == "b" then buf[#buf + 1] = "\b"
                elseif n == "f" then buf[#buf + 1] = "\f"
                elseif n == "/" then buf[#buf + 1] = "/"
                elseif n == "u" then
                    local hex = str:sub(pos + 2, pos + 5)
                    local cp = tonumber(hex, 16)
                    if cp then
                        if cp < 0x80 then
                            buf[#buf + 1] = string.char(cp)
                        elseif cp < 0x800 then
                            buf[#buf + 1] = string.char(0xC0 + math.floor(cp / 0x40), 0x80 + (cp % 0x40))
                        else
                            buf[#buf + 1] = string.char(0xE0 + math.floor(cp / 0x1000), 0x80 + (math.floor(cp / 0x40) % 0x40), 0x80 + (cp % 0x40))
                        end
                    end
                    pos = pos + 4
                else
                    buf[#buf + 1] = n
                end
                pos = pos + 2
            else
                buf[#buf + 1] = c
                pos = pos + 1
            end
        end
        return table.concat(buf)
    end
    local function parse_array()
        pos = pos + 1
        local arr = {}
        skip_ws()
        if str:sub(pos, pos) == "]" then pos = pos + 1; return arr end
        while pos <= #str do
            skip_ws()
            arr[#arr + 1] = parse_value()
            skip_ws()
            local c = str:sub(pos, pos)
            if c == "," then pos = pos + 1
            elseif c == "]" then pos = pos + 1; return arr
            else return arr end
        end
        return arr
    end
    local function parse_object()
        pos = pos + 1
        local obj = {}
        skip_ws()
        if str:sub(pos, pos) == "}" then pos = pos + 1; return obj end
        while pos <= #str do
            skip_ws()
            if str:sub(pos, pos) ~= '"' then return obj end
            local key = parse_string()
            skip_ws()
            if str:sub(pos, pos) ~= ":" then return obj end
            pos = pos + 1
            skip_ws()
            obj[key] = parse_value()
            skip_ws()
            local c = str:sub(pos, pos)
            if c == "," then pos = pos + 1
            elseif c == "}" then pos = pos + 1; return obj
            else return obj end
        end
        return obj
    end
    parse_value = function()
        skip_ws()
        local c = str:sub(pos, pos)
        if c == '"' then return parse_string()
        elseif c == "{" then return parse_object()
        elseif c == "[" then return parse_array()
        elseif c == "t" then pos = pos + 4; return true
        elseif c == "f" then pos = pos + 5; return false
        elseif c == "n" then pos = pos + 4; return nil
        else
            local num = str:match("^%-?%d+%.?%d*[eE]?[%+%-]?%d*", pos)
            if num and num ~= "" then
                pos = pos + #num
                return tonumber(num)
            end
            pos = pos + 1
            return nil
        end
    end
    local ok, result = pcall(parse_value)
    if ok then return result end
    return nil
end

function NotesUnescapeTk(s)
    return (s:gsub("::", "\0"):gsub("||", "\1"):gsub("%z", ":"):gsub("\1", "|"))
end

function NotesTkText(guid)
    local tabs_enabled = NotesReadProjExt(guid .. "::tabs_enabled")
    if tabs_enabled == "true" then
        local data = NotesReadProjExt(guid .. "::tabs_data")
        if data ~= "" then
            local protected = data:gsub("||", "\1"):gsub("::", "\2")
            local parts = {}
            for piece in (protected .. "|"):gmatch("([^|]*)|") do
                parts[#parts + 1] = piece
            end
            local sections = {}
            for i = 3, #parts do
                local raw = parts[i]
                local name, text = raw:match("^(.-)\2(.*)$")
                if not name then name, text = raw:match("^(.-):(.*)$") end
                name = name or ""
                text = text or ""
                name = (name:gsub("\2", ":"):gsub("\1", "|"))
                text = (text:gsub("\2", ":"):gsub("\1", "|"))
                local block = {}
                if name ~= "" then block[#block + 1] = "[" .. name .. "]" end
                if text ~= "" then block[#block + 1] = text end
                if #block > 0 then sections[#sections + 1] = table.concat(block, "\n") end
            end
            return table.concat(sections, "\n\n")
        end
    end
    return NotesReadProjExt(guid)
end

function NotesWorkbenchText(guid)
    local raw = NotesReadWorkbench(guid .. "::blocks")
    if raw == "" then return "" end
    local blocks = NotesJsonDecode(raw)
    if type(blocks) ~= "table" then return "" end
    local sections = {}
    for _, block in ipairs(blocks) do
        if type(block) == "table" then
            local title = tostring(block.title or "")
            local body = tostring(block.body or "")
            local part = {}
            if title ~= "" and title ~= "Notes" then part[#part + 1] = "[" .. title .. "]" end
            if body ~= "" then part[#part + 1] = body end
            if #part > 0 then sections[#sections + 1] = table.concat(part, "\n") end
        end
    end
    return table.concat(sections, "\n\n")
end

function NotesStripMarkup(s)
    if not s or s == "" then return s end
    s = s:gsub("%*%*(.-)%*%*", "%1")
    s = s:gsub("__(.-)__", "%1")
    return s
end

function NotesGetText(guid, source)
    if not guid or guid == "" then return "" end
    if source == "workbench" then
        return NotesStripMarkup(NotesWorkbenchText(guid))
    end
    return NotesStripMarkup(NotesTkText(guid))
end

function NotesSourceScriptPath(source)
    local resource = r.GetResourcePath():gsub("\\", "/")
    if source == "workbench" then
        return resource .. "/Scripts/TK Scripts/TK Workbench/TK_Workbench.lua"
    end
    return resource .. "/Scripts/TK Scripts/FX/TK_NOTES.lua"
end

function NotesSourceScriptExists(source)
    local path = NotesSourceScriptPath(source)
    return r.file_exists and r.file_exists(path), path
end

function NotesOpenSource(source)
    local exists, path = NotesSourceScriptExists(source)
    if not exists then return false end
    local cmd
    local named = PatchbayFindRegisteredCommandForScript(path)
    if named and r.NamedCommandLookup then
        cmd = r.NamedCommandLookup(named)
    end
    if (not cmd or cmd == 0) and r.AddRemoveReaScript then
        cmd = r.AddRemoveReaScript(true, 0, path, true)
    end
    if cmd and cmd ~= 0 then
        r.Main_OnCommand(cmd, 0)
        return true
    end
    return false
end

function RenderNotesHeader(ctx, pinned)
    local draw_list = r.ImGui_GetWindowDrawList(ctx)
    local avail_w = r.ImGui_GetContentRegionAvail(ctx)
    local header_h = 30
    r.ImGui_InvisibleButton(ctx, "##patchbay_notes_header", avail_w, header_h)
    local x1, y1 = r.ImGui_GetItemRectMin(ctx)
    local x2, y2 = r.ImGui_GetItemRectMax(ctx)
    local mx, my = r.ImGui_GetMousePos(ctx)
    local close_x = x2 - 16
    local close_y = (y1 + y2) * 0.5
    local close_hovered = mx >= close_x - 9 and mx <= close_x + 9 and my >= close_y - 9 and my <= close_y + 9
    local close_col = close_hovered and 0xFF7474FF or 0xE94343FF
    r.ImGui_DrawList_AddRectFilled(draw_list, x1, y1, x2, y2, 0x15171BFF, 6)
    r.ImGui_DrawList_AddLine(draw_list, x1, y2, x2, y2, 0x2A2E36FF, 1)
    r.ImGui_DrawList_AddCircleFilled(draw_list, close_x, close_y, 5.5, close_col)
    local text_h = r.ImGui_GetTextLineHeight(ctx)
    r.ImGui_DrawList_AddText(draw_list, x1 + 12, y1 + ((header_h - text_h) * 0.5), 0xE8E8E8FF, "Track notes")
    local close_clicked = close_hovered and r.ImGui_IsMouseClicked(ctx, 0)
    return close_clicked
end

function NotesRenderBodyAndFooter(ctx, cfg, source)
    local selected = GetSelectedPatchbayTracks()
    local target = selected[1]
    local body_h = -36

    if target and target.guid and target.guid ~= MASTER_GUID then
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0x7AA2F7FF)
        r.ImGui_Text(ctx, target.name and target.name ~= "" and target.name or "Track")
        r.ImGui_PopStyleColor(ctx, 1)
        r.ImGui_Separator(ctx)
        local text = NotesGetText(target.guid, source)
        if r.ImGui_BeginChild(ctx, "##patchbay_notes_body", 0, body_h, 1) then
            if text and text ~= "" then
                r.ImGui_TextWrapped(ctx, text)
            else
                r.ImGui_TextDisabled(ctx, "No notes")
            end
            r.ImGui_EndChild(ctx)
        end
    else
        if r.ImGui_BeginChild(ctx, "##patchbay_notes_body", 0, body_h, 1) then
            r.ImGui_TextDisabled(ctx, "Select a track")
            r.ImGui_EndChild(ctx)
        end
    end

    r.ImGui_Separator(ctx)
    local avail_w = r.ImGui_GetContentRegionAvail(ctx)
    local spacing = 6
    local has_open = NotesSourceScriptExists(source)
    local btn_count = has_open and 3 or 2
    local btn_w = (avail_w - spacing * (btn_count - 1)) / btn_count
    local active_col = 0x3A6EA5FF
    local function NotesSourceButton(label, key)
        local is_active = source == key
        if is_active then
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), active_col)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), active_col)
        end
        local clicked = r.ImGui_Button(ctx, label, btn_w, 0)
        if is_active then r.ImGui_PopStyleColor(ctx, 2) end
        if clicked and not is_active then
            cfg.patchbay_notes_source = key
            if _G.SaveConfig then _G.SaveConfig() end
        end
    end
    NotesSourceButton("TK Notes", "tk_notes")
    r.ImGui_SameLine(ctx, 0, spacing)
    NotesSourceButton("Workbench", "workbench")
    if has_open then
        r.ImGui_SameLine(ctx, 0, spacing)
        if r.ImGui_Button(ctx, "Open", btn_w, 0) then
            NotesOpenSource(source)
        end
    end
end

function RenderNotesPinnedOverlay(ctx, origin_x, origin_y, avail_w, avail_h)
    local cfg = GetConfig()
    if not (cfg and cfg.patchbay_show_notes) then return end
    local source = cfg.patchbay_notes_source
    if source ~= "workbench" then source = "tk_notes" end

    local panel_w = tonumber(cfg.patchbay_notes_w) or 320
    local panel_h = tonumber(cfg.patchbay_notes_h) or 420
    panel_w = math.max(220, math.min(panel_w, avail_w - 8))
    panel_h = math.max(140, math.min(panel_h, avail_h - 8))

    local off_x = tonumber(cfg.patchbay_notes_off_x)
    local off_y = tonumber(cfg.patchbay_notes_off_y)
    if not off_x then off_x = avail_w - panel_w - 12 end
    if not off_y then off_y = 12 end
    off_x = math.max(0, math.min(off_x, avail_w - panel_w))
    off_y = math.max(0, math.min(off_y, avail_h - panel_h))

    local px = origin_x + off_x
    local py = origin_y + off_y

    local draw_list = r.ImGui_GetWindowDrawList(ctx)
    r.ImGui_DrawList_AddRectFilled(draw_list, px, py, px + panel_w, py + panel_h, 0x1A1A1AFF, 6)
    r.ImGui_DrawList_AddRect(draw_list, px, py, px + panel_w, py + panel_h, 0x3A3F49FF, 6, 0, 1)

    r.ImGui_SetCursorScreenPos(ctx, px, py)
    if r.ImGui_SetNextItemAllowOverlap then r.ImGui_SetNextItemAllowOverlap(ctx) end
    local child_flags = 0
    if r.ImGui_WindowFlags_NoScrollbar then child_flags = child_flags | r.ImGui_WindowFlags_NoScrollbar() end
    if r.ImGui_BeginChild(ctx, "##patchbay_notes_pinned", panel_w, panel_h, 0, child_flags) then
        local close_clicked = RenderNotesHeader(ctx, true)
        if r.ImGui_IsItemActive(ctx) and r.ImGui_IsMouseDragging(ctx, 0) then
            local dx, dy = r.ImGui_GetMouseDragDelta(ctx, 0, 0, 0)
            if dx ~= 0 or dy ~= 0 then
                cfg.patchbay_notes_off_x = off_x + dx
                cfg.patchbay_notes_off_y = off_y + dy
                r.ImGui_ResetMouseDragDelta(ctx, 0)
                if _G.SaveConfig then _G.SaveConfig() end
            end
        end
        if close_clicked then
            cfg.patchbay_show_notes = false
            if _G.SaveConfig then _G.SaveConfig() end
        end
        r.ImGui_Spacing(ctx)
        NotesRenderBodyAndFooter(ctx, cfg, source)

        local grip = 16
        r.ImGui_SetCursorScreenPos(ctx, px + panel_w - grip, py + panel_h - grip)
        if r.ImGui_SetNextItemAllowOverlap then r.ImGui_SetNextItemAllowOverlap(ctx) end
        r.ImGui_InvisibleButton(ctx, "##patchbay_notes_resize", grip, grip)
        local grip_hovered = r.ImGui_IsItemHovered(ctx)
        local grip_active = r.ImGui_IsItemActive(ctx)
        if (grip_hovered or grip_active) and r.ImGui_SetMouseCursor and r.ImGui_MouseCursor_ResizeNWSE then
            r.ImGui_SetMouseCursor(ctx, r.ImGui_MouseCursor_ResizeNWSE())
        end
        if grip_active and r.ImGui_IsMouseDragging(ctx, 0) then
            local dx, dy = r.ImGui_GetMouseDragDelta(ctx, 0, 0, 0)
            if dx ~= 0 or dy ~= 0 then
                cfg.patchbay_notes_w = math.max(220, math.min(panel_w + dx, avail_w - off_x))
                cfg.patchbay_notes_h = math.max(140, math.min(panel_h + dy, avail_h - off_y))
                r.ImGui_ResetMouseDragDelta(ctx, 0)
                if _G.SaveConfig then _G.SaveConfig() end
            end
        end
        local grip_col = (grip_hovered or grip_active) and 0xBFC7D2FF or 0x6A7280FF
        local gx = px + panel_w - 4
        local gy = py + panel_h - 4
        for i = 0, 2 do
            local o = i * 4
            r.ImGui_DrawList_AddLine(draw_list, gx - o, gy, gx, gy - o, grip_col, 1.5)
        end

        r.ImGui_EndChild(ctx)
    end
end

local function RenderCableShopWindow()
    if not cable_shop_open then return end
    local ctx = GetCtx()
    local cfg = GetConfig()
    EnsureCableShopConfig(cfg)
    if r.ImGui_SetNextWindowSize then
        local cond = r.ImGui_Cond_FirstUseEver and r.ImGui_Cond_FirstUseEver() or 0
        r.ImGui_SetNextWindowSize(ctx, 430, 430, cond)
    end
    local window_flags = 0
    if r.ImGui_WindowFlags_NoTitleBar then window_flags = window_flags | r.ImGui_WindowFlags_NoTitleBar() end
    if r.ImGui_WindowFlags_NoCollapse then window_flags = window_flags | r.ImGui_WindowFlags_NoCollapse() end
    local visible, open = r.ImGui_Begin(ctx, "Cable shop##patchbay_cable_shop", cable_shop_open, window_flags)
    cable_shop_open = open
    if visible then
        RenderCableShopHeader(ctx)
        r.ImGui_Spacing(ctx)
        local changed_any = false
        local user_presets = GetCableShopUserPresets(cfg)
        local current_label = CABLE_SHOP_LABELS[cable_shop_selected] or cable_shop_selected
        r.ImGui_PushItemWidth(ctx, 220)
        if r.ImGui_BeginCombo(ctx, "Cable type", current_label) then
            for i = 1, #CABLE_SHOP_ORDER do
                local key = CABLE_SHOP_ORDER[i]
                if r.ImGui_Selectable(ctx, CABLE_SHOP_LABELS[key], cable_shop_selected == key) then
                    cable_shop_selected = key
                end
            end
            r.ImGui_EndCombo(ctx)
        end
        r.ImGui_PopItemWidth(ctx)

        local key = cable_shop_selected
        local color_key = CableShopKey(key, "color")
        local hover_key = CableShopKey(key, "hover")
        local thickness_key = CableShopKey(key, "thickness")
        local visible_key = CableShopKey(key, "visible")
        local dl = r.ImGui_GetWindowDrawList(ctx)
        local px, py = r.ImGui_GetCursorScreenPos(ctx)
        local avail_w = r.ImGui_GetContentRegionAvail(ctx)
        local preview_w = math.min(360, avail_w)
        local preview_h = 72
        r.ImGui_InvisibleButton(ctx, "##cable_shop_preview", preview_w, preview_h)
        local sx = px + 18
        local sy = py + preview_h * 0.5
        local dx = px + preview_w - 18
        local dy = sy
        local cp = preview_w * 0.22
        local preview_col = cfg[color_key]
        local preview_thick = tonumber(cfg[thickness_key]) or 1.5
        r.ImGui_DrawList_AddRectFilled(dl, px, py, px + preview_w, py + preview_h, 0x15171BCC, 6)
        if cfg[visible_key] ~= false then
            if key == "sidechain" or key == "midi" then
                r.ImGui_DrawList_AddBezierCubic(dl, sx, sy, sx + cp, sy, dx - cp, dy, dx, dy, 0x4FB0C8AA, 2)
            end
            if key == "midi" then
                DrawBezierStripes(dl, sx, sy, sx + cp, sy, dx - cp, dy, dx, dy, preview_col, preview_thick, 2)
            elseif key == "sidechain" then
                DrawBezierStripes(dl, sx, sy, sx + cp, sy, dx - cp, dy, dx, dy, preview_col, preview_thick, 2, true)
            elseif key == "folder_links" then
                r.ImGui_DrawList_AddLine(dl, sx, sy, dx, dy, preview_col, preview_thick)
            else
                r.ImGui_DrawList_AddBezierCubic(dl, sx, sy, sx + cp, sy, dx - cp, dy, dx, dy, preview_col, preview_thick)
            end
            r.ImGui_DrawList_AddCircleFilled(dl, sx, sy, 4, preview_col)
            r.ImGui_DrawList_AddCircleFilled(dl, dx, dy, 4, preview_col)
        else
            r.ImGui_DrawList_AddText(dl, px + 18, py + 26, 0x888888FF, "Hidden")
        end

        local visible_changed, new_visible = r.ImGui_Checkbox(ctx, "Visible", cfg[visible_key] ~= false)
        if visible_changed then
            cfg[visible_key] = new_visible
            changed_any = true
        end
        local flags = r.ImGui_ColorEditFlags_NoInputs()
        if r.ImGui_ColorEditFlags_AlphaBar then flags = flags | r.ImGui_ColorEditFlags_AlphaBar() end
        local color_changed, new_color = r.ImGui_ColorEdit4(ctx, "Color", cfg[color_key], flags)
        if color_changed then
            cfg[color_key] = new_color
            changed_any = true
        end
        local hover_changed, new_hover = r.ImGui_ColorEdit4(ctx, "Hover", cfg[hover_key], flags)
        if hover_changed then
            cfg[hover_key] = new_hover
            changed_any = true
        end
        r.ImGui_PushItemWidth(ctx, 220)
        local thickness_label = key == "midi" and "Stripe width" or "Thickness"
        local thickness_max = key == "midi" and 32.0 or 8.0
        local thickness_changed, new_thickness = r.ImGui_SliderDouble(ctx, thickness_label, tonumber(cfg[thickness_key]) or 1.5, 0.5, thickness_max, "%.1f")
        r.ImGui_PopItemWidth(ctx)
        if thickness_changed then
            cfg[thickness_key] = new_thickness
            changed_any = true
        end
        if r.ImGui_Button(ctx, "Reset type") then
            ResetCableShopType(cfg, key)
            changed_any = true
        end
        r.ImGui_SameLine(ctx)
        if r.ImGui_Button(ctx, "Reset all") then
            for i = 1, #CABLE_SHOP_ORDER do ResetCableShopType(cfg, CABLE_SHOP_ORDER[i]) end
            changed_any = true
        end
        r.ImGui_Spacing(ctx)
        r.ImGui_Separator(ctx)
        r.ImGui_PushItemWidth(ctx, 220)
        if r.ImGui_BeginCombo(ctx, "User preset", CableShopUserSlotLabel(user_presets, cable_shop_user_slot)) then
            for slot = 1, CABLE_SHOP_USER_PRESET_SLOTS do
                if r.ImGui_Selectable(ctx, CableShopUserSlotLabel(user_presets, slot), cable_shop_user_slot == slot) then
                    cable_shop_user_slot = slot
                    cable_shop_user_name = user_presets[slot] and user_presets[slot].name or ("Preset " .. tostring(slot))
                end
            end
            r.ImGui_EndCombo(ctx)
        end
        r.ImGui_PopItemWidth(ctx)
        local name_changed, new_name = r.ImGui_InputText(ctx, "Preset name", cable_shop_user_name or "")
        if name_changed then cable_shop_user_name = new_name end
        if r.ImGui_Button(ctx, "Save current") then
            user_presets[cable_shop_user_slot] = CaptureCableShopPreset(cfg, cable_shop_user_name, cable_shop_user_slot)
            cable_shop_user_name = user_presets[cable_shop_user_slot].name
            SerializeCableShopUserPresets(cfg, user_presets)
            changed_any = true
        end
        r.ImGui_SameLine(ctx)
        if r.ImGui_Button(ctx, "Load") and user_presets[cable_shop_user_slot] then
            changed_any = ApplyCableShopPresetData(cfg, user_presets[cable_shop_user_slot]) or changed_any
        end
        r.ImGui_SameLine(ctx)
        if r.ImGui_Button(ctx, "Delete") and user_presets[cable_shop_user_slot] then
            user_presets[cable_shop_user_slot] = nil
            SerializeCableShopUserPresets(cfg, user_presets)
            changed_any = true
        end
        if changed_any and _G.SaveConfig then _G.SaveConfig() end
        r.ImGui_TextDisabled(ctx, "Audit colors stay on top.")
    end
    r.ImGui_End(ctx)
end

local function RenderViewHelpHeader(ctx)
    local draw_list = r.ImGui_GetWindowDrawList(ctx)
    local avail_w = r.ImGui_GetContentRegionAvail(ctx)
    local header_h = 30
    r.ImGui_InvisibleButton(ctx, "##view_help_header", avail_w, header_h)
    local x1, y1 = r.ImGui_GetItemRectMin(ctx)
    local x2, y2 = r.ImGui_GetItemRectMax(ctx)
    local close_x = x2 - 16
    local close_y = (y1 + y2) * 0.5
    local mx, my = r.ImGui_GetMousePos(ctx)
    local close_hovered = mx >= close_x - 9 and mx <= close_x + 9 and my >= close_y - 9 and my <= close_y + 9
    local close_col = close_hovered and 0xFF7474FF or 0xE94343FF
    r.ImGui_DrawList_AddRectFilled(draw_list, x1, y1, x2, y2, 0x15171BFF, 6)
    r.ImGui_DrawList_AddLine(draw_list, x1, y2, x2, y2, 0x2A2E36FF, 1)
    r.ImGui_DrawList_AddCircleFilled(draw_list, close_x, close_y, 5.5, close_col)
    local text_h = r.ImGui_GetTextLineHeight(ctx)
    r.ImGui_DrawList_AddText(draw_list, x1 + 12, y1 + ((header_h - text_h) * 0.5), 0xE8E8E8FF, "View options")
    if close_hovered and r.ImGui_IsMouseClicked(ctx, 0) then
        view_help_open = false
        return true
    end
    return false
end

local function RenderViewHelpItem(ctx, title, text)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0x7AA2F7FF)
    r.ImGui_Text(ctx, title)
    r.ImGui_PopStyleColor(ctx, 1)
    r.ImGui_TextWrapped(ctx, text)
    r.ImGui_Spacing(ctx)
end

local function RenderViewHelpWindow()
    if not view_help_open then return end
    local ctx = GetCtx()
    if r.ImGui_SetNextWindowSize then
        local cond = r.ImGui_Cond_FirstUseEver and r.ImGui_Cond_FirstUseEver() or 0
        r.ImGui_SetNextWindowSize(ctx, 470, 500, cond)
    end
    local window_flags = 0
    if r.ImGui_WindowFlags_NoTitleBar then window_flags = window_flags | r.ImGui_WindowFlags_NoTitleBar() end
    if r.ImGui_WindowFlags_NoCollapse then window_flags = window_flags | r.ImGui_WindowFlags_NoCollapse() end
    local visible, open = r.ImGui_Begin(ctx, "View options##patchbay_view_help", view_help_open, window_flags)
    view_help_open = open
    if visible then
        RenderViewHelpHeader(ctx)
        r.ImGui_Spacing(ctx)
        r.ImGui_TextWrapped(ctx, "These options only change what the patchbay displays. They do not change REAPER routing unless you use routing actions.")
        r.ImGui_Separator(ctx)
        r.ImGui_Spacing(ctx)
        RenderViewHelpItem(ctx, "Master", "Shows or hides the MASTER node and normal track-to-master flow.")
        RenderViewHelpItem(ctx, "Hide child master flow", "Hides visual master-flow cables from folder child tracks. Folder parents and normal top-level tracks can still show their master flow.")
        RenderViewHelpItem(ctx, "Explicit", "Shows only tracks that have explicit sends or receives. Normal master output is not counted as explicit routing.")
        RenderViewHelpItem(ctx, "Master flow in explicit", "Allows normal track-to-master flow to appear while Explicit mode is enabled.")
        RenderViewHelpItem(ctx, "Only isolated", "Shows tracks that have no explicit sends, no explicit receives, and no master output.")
        RenderViewHelpItem(ctx, "Flow", "Shows or hides the animated flow markers on visible cables.")
        RenderViewHelpItem(ctx, "Folder links", "Shows or hides the visual parent-to-child folder relationship lines.")
        RenderViewHelpItem(ctx, "Send type badges", "Shows audio, sidechain, and MIDI badges on send cables.")
        RenderViewHelpItem(ctx, "Focus selected", "Limits the view to selected tracks and their direct routing neighbors.")
        RenderViewHelpItem(ctx, "Focus selected tree", "Focuses the complete folder tree around selected tracks, plus routing neighbors.")
        RenderViewHelpItem(ctx, "Focus selected subtree", "Focuses selected tracks and their folder descendants without parent folders.")
        RenderViewHelpItem(ctx, "Mirror view to TCP", "Temporarily mirrors the Patchbay visible track set to the TCP. The original TCP visibility is restored when the option is disabled or the script exits.")
        RenderViewHelpItem(ctx, "Solo path", "Visually emphasizes the current selected track path and dims unrelated visible nodes and cables.")
    end
    r.ImGui_End(ctx)
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

function PatchbayFxSchemaPatternEscape(s)
    return tostring(s or ""):gsub("([^%w])", "%%%1")
end

function PatchbayFxSchemaTextWidth(ctx, text)
    local w = r.ImGui_CalcTextSize(ctx, tostring(text or ""))
    return w or 0
end

function PatchbayFxSchemaCleanName(name, fallback)
    name = tostring(name or ""):gsub("^%s*(.-)%s*$", "%1")
    name = name:gsub("^VST3i?:%s*", ""):gsub("^VSTi?:%s*", ""):gsub("^CLAPi?:%s*", ""):gsub("^JS:%s*", "")
    name = name:gsub("^AUi?:%s*", ""):gsub("^LV2i?:%s*", ""):gsub("^DXi?:%s*", ""):gsub("^ReWire:%s*", "")
    name = name:gsub("%s+%(x%d+%)%s*$", ""):gsub("%s+%[x%d+%]%s*$", "")
    name = name:gsub("%s+%(bridged%)%s*$", ""):gsub("%s+%[bridged%]%s*$", "")
    local publisher = name:match("%(([^()]*)%)%s*$")
    if publisher and publisher ~= "" then
        local publisher_lc = publisher:lower()
        if not publisher_lc:match("mono") and not publisher_lc:match("stereo") and not publisher_lc:match("out") and not publisher_lc:match("sidechain") then
            name = name:gsub("%s*%([^()]*%)%s*$", "")
            local head = publisher:match("^([%w%-]+)")
            if head and #head >= 3 then
                name = name:gsub("^" .. PatchbayFxSchemaPatternEscape(head) .. "%s+", "")
            end
        end
    end
    name = name:gsub("%s+by%s+[%w%p%s]+$", "")
    local dash_suffix = name:match("%s+%-%s+(.+)$")
    if dash_suffix then
        local suffix_lc = dash_suffix:lower()
        if suffix_lc:match("audio") or suffix_lc:match("dsp") or suffix_lc:match("inc") or suffix_lc:match("ltd") or suffix_lc:match("llc") or suffix_lc:match("fabfilter") or suffix_lc:match("izotope") or suffix_lc:match("softube") or suffix_lc:match("valhalla") or suffix_lc:match("waves") or suffix_lc:match("cockos") then
            name = name:gsub("%s+%-%s+.+$", "")
        end
    end
    name = name:gsub("^%s*(.-)%s*$", "%1")
    return name ~= "" and name or (fallback or "FX")
end

function PatchbayFxSchemaThemeIsLight()
    local bg = _G.patchbay_grid_bg_col or 0x1A1A1AFF
    local red = math.floor(bg / 0x1000000) % 0x100
    local green = math.floor(bg / 0x10000) % 0x100
    local blue = math.floor(bg / 0x100) % 0x100
    local luminance = (red * 0.299) + (green * 0.587) + (blue * 0.114)
    return luminance > 150
end

function PatchbayFxSchemaLineColor(compact)
    local light_theme = PatchbayFxSchemaThemeIsLight()
    if PB.fx_schema_monochrome then
        if light_theme then return compact and 0x3A3A3ADD or 0xD6D6D6EE end
        return compact and 0x202020CC or 0x252525E6
    end
    if light_theme then return compact and 0xE2ECF7F2 or 0x4F5C6AE6 end
    return compact and 0xB8BDC699 or 0xB8BDC6CC
end

function PatchbayFxSchemaPalette(kind, fx)
    local light_theme = PatchbayFxSchemaThemeIsLight()
    if PB.fx_schema_monochrome then
        if kind == "panel" then
            if light_theme then return 0x1A1A1A98, 0x777777DD, 0xE8E8E8FF end
            return 0xF1F1F1A8, 0x404040DD, 0x101010FF
        end
        if fx and fx.offline then
            if light_theme then return 0x303030F2, 0xE4E4E4DD, 0xF0F0F0FF end
            return 0x707070F2, 0x202020DD, 0xF7F7F7FF
        end
        if fx and not fx.enabled then
            if light_theme then return 0x606060F2, 0xBEBEBEDD, 0xD8D8D8FF end
            return 0xB8B8B8F2, 0x777777DD, 0x515151FF
        end
        if fx and fx.fx_type == "Container" then
            if light_theme then return 0xD7D7D7F4, 0xFFFFFFFF, 0x151515FF end
            return 0xE0E0E0F5, 0x111111E0, 0x111111FF
        end
        if light_theme then return 0xEEEEEEF4, 0xFFFFFFFF, 0x161616FF end
        return 0xFFFFFFF5, 0x1B1B1BE0, 0x101010FF
    end
    if kind == "panel" then return 0x111820B8, 0x5D728CCC, 0x8E98A6FF end
    if fx and fx.offline then return 0x332020E6, 0xB64A4ACC, 0xD08A8AFF end
    if fx and not fx.enabled then return 0x24262BE6, 0x5A5D66CC, 0x8E939CFF end
    if fx and fx.fx_type == "Container" then return 0x183225E6, 0x57C184CC, 0xD9F4E5FF end
    return 0x172231E6, 0x4F8FD8CC, 0xE6EAF0FF
end

function PatchbayFxSchemaGetParm(track, fx, key)
    if not r.TrackFX_GetNamedConfigParm then return false, "" end
    local ok, value = r.TrackFX_GetNamedConfigParm(track, fx, key)
    return ok, tostring(value or "")
end

function PatchbayFxSchemaCollectContainer(track, container_id, parent_fx_count, previous_diff, depth)
    local out = {}
    local ok_count, raw_count = PatchbayFxSchemaGetParm(track, 0x2000000 + container_id, "container_count")
    local count = ok_count and math.floor(tonumber(raw_count) or 0) or 0
    if count <= 0 then return out, 0 end
    local max_items = 8
    local limit = math.min(count, max_items)
    local diff = depth == 1 and parent_fx_count + 1 or (parent_fx_count + 1) * previous_diff
    for i = 1, limit do
        local fx_id = container_id + (diff * i)
        local api_id = 0x2000000 + fx_id
        local _, raw_name = r.TrackFX_GetFXName(track, api_id, "")
        local ok_type, fx_type = PatchbayFxSchemaGetParm(track, api_id, "fx_type")
        local ok_parallel, parallel = PatchbayFxSchemaGetParm(track, api_id, "parallel")
        local children, child_count = {}, 0
        if ok_type and fx_type == "Container" and depth < 2 then
            children, child_count = PatchbayFxSchemaCollectContainer(track, fx_id, count, diff, depth + 1)
        elseif ok_type and fx_type == "Container" then
            local ok_child_count, raw_child_count = PatchbayFxSchemaGetParm(track, 0x2000000 + fx_id, "container_count")
            child_count = ok_child_count and math.floor(tonumber(raw_child_count) or 0) or 0
        end
        out[#out + 1] = {
            name = PatchbayFxSchemaCleanName(raw_name, "FX " .. tostring(i)),
            full_name = tostring(raw_name or ""),
            enabled = r.TrackFX_GetEnabled(track, api_id),
            offline = r.TrackFX_GetOffline and r.TrackFX_GetOffline(track, api_id) or false,
            fx_type = ok_type and fx_type or "",
            parallel = ok_parallel and parallel ~= "0",
            children = children,
            child_count = child_count,
            api_id = api_id,
            depth = depth
        }
    end
    return out, count
end

function PatchbayFxSchemaCollect(track)
    local out = {}
    if not track or not r.ValidatePtr(track, "MediaTrack*") then return out, 0 end
    local count = r.TrackFX_GetCount(track) or 0
    local limit = math.min(count, 8)
    for i = 0, limit - 1 do
        local _, raw_name = r.TrackFX_GetFXName(track, i, "")
        local ok_type, fx_type = PatchbayFxSchemaGetParm(track, i, "fx_type")
        local ok_parallel, parallel = PatchbayFxSchemaGetParm(track, i, "parallel")
        local children, child_count = {}, 0
        if ok_type and fx_type == "Container" then
            children, child_count = PatchbayFxSchemaCollectContainer(track, i + 1, count, 0, 1)
        end
        out[#out + 1] = {
            name = PatchbayFxSchemaCleanName(raw_name, "FX " .. tostring(i + 1)),
            full_name = tostring(raw_name or ""),
            enabled = r.TrackFX_GetEnabled(track, i),
            offline = r.TrackFX_GetOffline and r.TrackFX_GetOffline(track, i) or false,
            fx_type = ok_type and fx_type or "",
            parallel = ok_parallel and parallel ~= "0",
            children = children,
            child_count = child_count,
            api_id = i,
            depth = 0
        }
    end
    return out, count
end

function PatchbayFxSchemaBuildStages(chain)
    local stages = {}
    for i = 1, #(chain or {}) do
        local fx = chain[i]
        if fx.parallel and #stages > 0 then
            local st = stages[#stages]
            st.items[#st.items + 1] = fx
        else
            stages[#stages + 1] = { items = { fx } }
        end
    end
    return stages
end

function PatchbayFxSchemaMakeDims(zoom)
    local scale = math.max(0.72, math.min(1.0, zoom or 1.0))
    return {
        scale = scale,
        item_h = math.floor(19 * scale + 0.5),
        child_h = math.floor(14 * scale + 0.5),
        gap = math.floor(24 * scale + 0.5),
        lane_gap = math.floor(10 * scale + 0.5),
        child_gap = math.floor(5 * scale + 0.5),
        pad_x = math.floor(8 * scale + 0.5),
        branch_pad = math.floor(20 * scale + 0.5),
        child_branch_pad = math.floor(13 * scale + 0.5),
        min_w = math.floor(52 * scale + 0.5),
        max_w = math.floor(130 * scale + 0.5),
        child_min_w = math.floor(42 * scale + 0.5),
        child_max_w = math.floor(95 * scale + 0.5),
        panel_pad = math.floor(10 * scale + 0.5),
        para_pad = math.floor(3 * scale + 0.5),
        para_gap = math.floor(5 * scale + 0.5)
    }
end

function PatchbayFxSchemaMeasureChildChain(ctx, fx, dims)
    local stages = PatchbayFxSchemaBuildStages(fx.children)
    local total_w = 0
    local max_lanes = 1
    for i = 1, #stages do
        local st = stages[i]
        st.width = 0
        st.widths = {}
        for j = 1, #st.items do
            local text_w = PatchbayFxSchemaTextWidth(ctx, st.items[j].name)
            local cw = math.min(dims.child_max_w, math.max(dims.child_min_w, math.floor(text_w + (dims.pad_x * 1.2) + 0.5)))
            st.widths[j] = cw
            if cw > st.width then st.width = cw end
        end
        if #st.items > 1 then st.width = st.width + (dims.child_branch_pad * 2) end
        total_w = total_w + st.width
        if #st.items > max_lanes then max_lanes = #st.items end
    end
    local extra = math.max(0, (fx.child_count or 0) - #(fx.children or {}))
    local extra_w = 0
    if extra > 0 then
        extra_w = math.min(dims.child_max_w, math.max(dims.child_min_w, math.floor(PatchbayFxSchemaTextWidth(ctx, "+" .. tostring(extra)) + (dims.pad_x * 1.2) + 0.5)))
        total_w = total_w + extra_w
    end
    total_w = total_w + math.max(0, #stages - 1) * dims.child_gap + (extra > 0 and dims.child_gap or 0)
    fx.schema_child_stages = stages
    fx.schema_child_extra = extra
    fx.schema_child_extra_w = extra_w
    fx.schema_child_w = math.max(dims.child_min_w, total_w)
    fx.schema_child_h = (max_lanes * dims.child_h) + ((max_lanes - 1) * dims.child_gap)
end

function PatchbayFxSchemaMeasureBox(ctx, fx, dims)
    local text_w = PatchbayFxSchemaTextWidth(ctx, fx.name)
    local w = math.min(dims.max_w, math.max(dims.min_w, math.floor(text_w + (dims.pad_x * 2) + 0.5)))
    local h = dims.item_h
    fx.schema_child_stages = nil
    fx.schema_child_extra = 0
    if fx.fx_type == "Container" then
        PatchbayFxSchemaMeasureChildChain(ctx, fx, dims)
        if (fx.schema_child_w or 0) > 0 then
            w = math.max(w, math.min(math.floor(220 * dims.scale + 0.5), math.floor((fx.schema_child_w or 0) + (dims.pad_x * 2) + 0.5)))
            h = dims.item_h + (fx.schema_child_h or dims.child_h) + dims.child_gap + 5
        end
    end
    fx.schema_w = w
    fx.schema_h = h
end

function PatchbayFxSchemaBuildLayout(ctx, track, track_name, node_x1, node_y1, node_x2, node_y2, canvas_x1, canvas_y1, canvas_x2, canvas_y2, zoom)
    local chain, count = PatchbayFxSchemaCollect(track)
    local dims = PatchbayFxSchemaMakeDims(zoom)
    local stages = PatchbayFxSchemaBuildStages(chain)
    local total_w = 0
    local total_h = dims.item_h
    for i = 1, #stages do
        local st = stages[i]
        st.width = 0
        st.widths = {}
        st.lane_h = dims.item_h
        for j = 1, #st.items do
            PatchbayFxSchemaMeasureBox(ctx, st.items[j], dims)
            st.widths[j] = st.items[j].schema_w
            if st.widths[j] > st.width then st.width = st.widths[j] end
            if st.items[j].schema_h > st.lane_h then st.lane_h = st.items[j].schema_h end
        end
        if #st.items > 1 then st.width = st.width + (dims.branch_pad * 2) end
        st.height = (#st.items * st.lane_h) + ((#st.items - 1) * dims.lane_gap)
        total_w = total_w + st.width
        if st.height > total_h then total_h = st.height end
    end
    local extra = math.max(0, count - #chain)
    local extra_w = 0
    if extra > 0 then
        extra_w = math.max(dims.min_w, math.floor(PatchbayFxSchemaTextWidth(ctx, "+" .. tostring(extra)) + (dims.pad_x * 2) + 0.5))
        total_w = total_w + extra_w
    end
    total_w = total_w + math.max(0, #stages - 1) * dims.gap + (extra > 0 and dims.gap or 0)
    if #stages == 0 and extra == 0 then
        total_w = math.floor(130 * dims.scale + 0.5)
        total_h = dims.item_h
    end
    local f_w = PatchbayFxSchemaTextWidth(ctx, "F")
    local x_w = PatchbayFxSchemaTextWidth(ctx, "X")
    local para_text_w = math.max(f_w, x_w)
    local para_w = math.max(12, math.floor(para_text_w + (dims.para_pad * 2) + 0.5))
    local panel_w = total_w + dims.para_gap + para_w + (dims.panel_pad * 2)
    local panel_h = total_h + (dims.panel_pad * 2)
    local margin = math.floor(18 * dims.scale + 0.5)
    local px = node_x2 + margin
    local py = node_y1 + ((node_y2 - node_y1 - panel_h) * 0.5)
    local anchor_x = node_x2
    local anchor_y = (node_y1 + node_y2) * 0.5
    local end_x = px
    local end_y = py + panel_h * 0.5
    if px + panel_w > canvas_x2 - 4 then
        if node_x1 - margin - panel_w >= canvas_x1 + 4 then
            px = node_x1 - margin - panel_w
            anchor_x = node_x1
            end_x = px + panel_w
        else
            px = math.max(canvas_x1 + 4, math.min(node_x1, canvas_x2 - panel_w - 4))
            py = node_y2 + margin
            anchor_x = (node_x1 + node_x2) * 0.5
            anchor_y = node_y2
            end_x = px + panel_w * 0.5
            end_y = py
        end
    end
    if py + panel_h > canvas_y2 - 4 then py = canvas_y2 - panel_h - 4 end
    if py < canvas_y1 + 4 then py = canvas_y1 + 4 end
    if px < canvas_x1 + 4 then px = canvas_x1 + 4 end
    if px + panel_w > canvas_x2 - 4 then px = canvas_x2 - panel_w - 4 end
    return { track = track, track_name = track_name, chain = chain, count = count, stages = stages, extra = extra, extra_w = extra_w, dims = dims, x = px, y = py, w = panel_w, h = panel_h, content_w = total_w, content_h = total_h, para_w = para_w, anchor_x = anchor_x, anchor_y = anchor_y, end_x = end_x, end_y = end_y }
end

function PatchbayFxSchemaDrawSmallBox(ctx, draw_list, fx, x, y, w, h, dims)
    local bg, border, text_col = PatchbayFxSchemaPalette("small", fx)
    r.ImGui_DrawList_AddRectFilled(draw_list, x, y, x + w, y + h, bg, 3)
    r.ImGui_DrawList_AddRect(draw_list, x, y, x + w, y + h, border, 3, nil, 1)
    local text_h = r.ImGui_GetTextLineHeight(ctx)
    local label = TruncateText(ctx, fx.name, w - dims.pad_x)
    r.ImGui_DrawList_AddText(draw_list, x + dims.pad_x * 0.5, y + ((h - text_h) * 0.5), text_col, label)
end

function PatchbayFxSchemaDrawChildChain(ctx, draw_list, fx, x, y, w, dims)
    local stages = fx.schema_child_stages or {}
    local line_col = PatchbayFxSchemaLineColor(true)
    local chain_w = fx.schema_child_w or 0
    local chain_h = fx.schema_child_h or dims.child_h
    local chain_x = x + ((w - chain_w) * 0.5)
    local chain_mid_y = y + chain_h * 0.5
    local cx = chain_x
    for i = 1, #stages do
        local st = stages[i]
        if #st.items > 1 then
            local left_x = cx
            local right_x = cx + st.width
            local first_mid_y = y + dims.child_h * 0.5
            local last_mid_y = y + ((#st.items - 1) * (dims.child_h + dims.child_gap)) + (dims.child_h * 0.5)
            r.ImGui_DrawList_AddLine(draw_list, left_x, first_mid_y, left_x, last_mid_y, line_col, 1.2)
            r.ImGui_DrawList_AddLine(draw_list, right_x, first_mid_y, right_x, last_mid_y, line_col, 1.2)
            for j = 1, #st.items do
                local lane_mid_y = y + ((j - 1) * (dims.child_h + dims.child_gap)) + (dims.child_h * 0.5)
                r.ImGui_DrawList_AddLine(draw_list, left_x, lane_mid_y, right_x, lane_mid_y, line_col, 1.2)
            end
        end
        for j = 1, #st.items do
            local item_w = st.widths[j]
            local bx = cx + ((st.width - item_w) * 0.5)
            local lane_mid_y = #st.items > 1 and (y + ((j - 1) * (dims.child_h + dims.child_gap)) + (dims.child_h * 0.5)) or chain_mid_y
            PatchbayFxSchemaDrawSmallBox(ctx, draw_list, st.items[j], bx, lane_mid_y - dims.child_h * 0.5, item_w, dims.child_h, dims)
        end
        if i < #stages or (fx.schema_child_extra or 0) > 0 then
            r.ImGui_DrawList_AddLine(draw_list, cx + st.width, chain_mid_y, cx + st.width + dims.child_gap, chain_mid_y, line_col, 1.2)
        end
        cx = cx + st.width + dims.child_gap
    end
    if (fx.schema_child_extra or 0) > 0 then
        local ew = fx.schema_child_extra_w or dims.child_min_w
        PatchbayFxSchemaDrawSmallBox(ctx, draw_list, { name = "+" .. tostring(fx.schema_child_extra), enabled = true, offline = false }, cx, chain_mid_y - dims.child_h * 0.5, ew, dims.child_h, dims)
    end
end

function PatchbayFxSchemaDrawBox(ctx, draw_list, fx, x, y, w, h, dims)
    local bg, border, text_col = PatchbayFxSchemaPalette("box", fx)
    r.ImGui_DrawList_AddRectFilled(draw_list, x, y, x + w, y + h, bg, 4)
    r.ImGui_DrawList_AddRect(draw_list, x, y, x + w, y + h, border, 4, nil, 1.1)
    local text_h = r.ImGui_GetTextLineHeight(ctx)
    local label = TruncateText(ctx, fx.name, w - dims.pad_x * 2)
    r.ImGui_DrawList_AddText(draw_list, x + dims.pad_x, y + ((dims.item_h - text_h) * 0.5), text_col, label)
    if fx.fx_type == "Container" and (fx.schema_child_stages or fx.schema_child_extra or 0) then
        PatchbayFxSchemaDrawChildChain(ctx, draw_list, fx, x, y + dims.item_h + dims.child_gap, w, dims)
    end
end

function PatchbayFxSchemaRender(ctx, draw_list, layout)
    if not layout then return end
    local dims = layout.dims
    local line_col = PatchbayFxSchemaLineColor(false)
    local panel_bg, panel_border, panel_text = PatchbayFxSchemaPalette("panel")
    r.ImGui_DrawList_AddLine(draw_list, layout.anchor_x, layout.anchor_y, layout.end_x, layout.end_y, line_col, 1.2)
    r.ImGui_DrawList_AddRectFilled(draw_list, layout.x, layout.y, layout.x + layout.w, layout.y + layout.h, panel_bg, 6)
    r.ImGui_DrawList_AddRect(draw_list, layout.x, layout.y, layout.x + layout.w, layout.y + layout.h, panel_border, 6, nil, 1.1)
    local text_h = r.ImGui_GetTextLineHeight(ctx)
    local chain_x = layout.x + dims.panel_pad
    local chain_y = layout.y + dims.panel_pad
    local chain_mid_y = chain_y + layout.content_h * 0.5
    local cx = chain_x
    if #layout.stages == 0 and layout.extra == 0 then
        local msg = "No FX"
        local tw = PatchbayFxSchemaTextWidth(ctx, msg)
        r.ImGui_DrawList_AddText(draw_list, chain_x + ((layout.content_w - tw) * 0.5), chain_mid_y - text_h * 0.5, panel_text, msg)
    end
    for i = 1, #layout.stages do
        local st = layout.stages[i]
        local stage_y = chain_y + ((layout.content_h - st.height) * 0.5)
        if #st.items > 1 then
            local left_x = cx
            local right_x = cx + st.width
            local first_mid_y = stage_y + st.lane_h * 0.5
            local last_mid_y = stage_y + ((#st.items - 1) * (st.lane_h + dims.lane_gap)) + (st.lane_h * 0.5)
            r.ImGui_DrawList_AddLine(draw_list, left_x, first_mid_y, left_x, last_mid_y, line_col, 1.2)
            r.ImGui_DrawList_AddLine(draw_list, right_x, first_mid_y, right_x, last_mid_y, line_col, 1.2)
            for j = 1, #st.items do
                local lane_mid_y = stage_y + ((j - 1) * (st.lane_h + dims.lane_gap)) + (st.lane_h * 0.5)
                r.ImGui_DrawList_AddLine(draw_list, left_x, lane_mid_y, right_x, lane_mid_y, line_col, 1.2)
            end
        end
        for j = 1, #st.items do
            local fx = st.items[j]
            local item_w = st.widths[j]
            local bx = cx + ((st.width - item_w) * 0.5)
            local lane_mid_y = #st.items > 1 and (stage_y + ((j - 1) * (st.lane_h + dims.lane_gap)) + (st.lane_h * 0.5)) or chain_mid_y
            local by = lane_mid_y - ((fx.schema_h or dims.item_h) * 0.5)
            PatchbayFxSchemaDrawBox(ctx, draw_list, fx, bx, by, item_w, fx.schema_h or dims.item_h, dims)
        end
        if i < #layout.stages or layout.extra > 0 then
            r.ImGui_DrawList_AddLine(draw_list, cx + st.width, chain_mid_y, cx + st.width + dims.gap, chain_mid_y, line_col, 1.2)
        end
        cx = cx + st.width + dims.gap
    end
    if layout.extra > 0 then
        PatchbayFxSchemaDrawBox(ctx, draw_list, { name = "+" .. tostring(layout.extra), enabled = true, offline = false }, cx, chain_mid_y - dims.item_h * 0.5, layout.extra_w, dims.item_h, dims)
    end
    local btn_w = layout.para_w or dims.para_w
    local btn_h = layout.content_h
    local btn_x = layout.x + dims.panel_pad + layout.content_w + dims.para_gap
    local btn_y = chain_y
    local divider_x = layout.x + dims.panel_pad + layout.content_w + (dims.para_gap * 0.5)
    local btn_text = panel_text
    r.ImGui_DrawList_AddLine(draw_list, divider_x, layout.y, divider_x, layout.y + layout.h, panel_border, 1.1)
    local f_tw = PatchbayFxSchemaTextWidth(ctx, "F")
    local x_tw = PatchbayFxSchemaTextWidth(ctx, "X")
    local glyph_gap = math.max(1, math.floor(1 * dims.scale + 0.5))
    local text_total_h = (text_h * 2) + glyph_gap
    local text_y = btn_y + ((btn_h - text_total_h) * 0.5)
    r.ImGui_DrawList_AddText(draw_list, btn_x + ((btn_w - f_tw) * 0.5), text_y, btn_text, "F")
    r.ImGui_DrawList_AddText(draw_list, btn_x + ((btn_w - x_tw) * 0.5), text_y + text_h + glyph_gap, btn_text, "X")
    r.ImGui_PushID(ctx, "fx_schema_popover")
    if r.ImGui_SetNextItemAllowOverlap then r.ImGui_SetNextItemAllowOverlap(ctx) end
    r.ImGui_SetCursorScreenPos(ctx, layout.x, layout.y)
    r.ImGui_InvisibleButton(ctx, "##fx_schema_panel", layout.w, layout.h)
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Read-only FX chain schema") end
    if r.ImGui_SetNextItemAllowOverlap then r.ImGui_SetNextItemAllowOverlap(ctx) end
    r.ImGui_SetCursorScreenPos(ctx, btn_x, btn_y)
    r.ImGui_InvisibleButton(ctx, "##schema_paranormal", btn_w, btn_h)
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Open Paranormal FX for this track") end
    if r.ImGui_IsItemClicked(ctx, 0) then
        local ok, err = PatchbayToggleParanormalForTrack(layout.track)
        if not ok then r.ShowMessageBox(tostring(err or "Could not open Paranormal FX."), "Patchbay: Paranormal FX", 0) end
    end
    r.ImGui_PopID(ctx)
end

local function RemovePatchbayCableTargetNoUndo(cable)
    if not cable or not cable.src or not r.ValidatePtr(cable.src, "MediaTrack*") then return false end
    if cable.is_main then
        if r.GetMediaTrackInfo_Value(cable.src, "B_MAINSEND") ~= 1 then return false end
        r.SetMediaTrackInfo_Value(cable.src, "B_MAINSEND", 0)
        return true
    end
    if not cable.dst or not r.ValidatePtr(cable.dst, "MediaTrack*") then return false end
    local idx = GetSendIndexLocal(cable.src, cable.dst)
    if idx < 0 then return false end
    r.RemoveTrackSend(cable.src, 0, idx)
    return true
end

local function RemovePatchbayCable(cable)
    if IsAllLockedCfg(GetConfig()) then return false end
    local action_name = cable and cable.is_main and "Patchbay: disable main send" or "Patchbay: delete connection"
    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)
    local changed = RemovePatchbayCableTargetNoUndo(cable)
    r.PreventUIRefresh(-1)
    r.TrackList_AdjustWindows(false)
    r.UpdateArrange()
    r.Undo_EndBlock(changed and action_name or (action_name .. " (no changes)"), -1)
    return changed
end

local function RemoveSelectedPatchbayCableRelations(cable)
    if IsAllLockedCfg(GetConfig()) then return false end
    if not cable or not cable.src or not r.ValidatePtr(cable.src, "MediaTrack*") then return false end
    local src_guid = r.GetTrackGUID(cable.src)
    local src_selected = pb_selected_set[src_guid] == true
    local dst_selected = false
    if cable.is_main then
        dst_selected = pb_selected_set[MASTER_GUID] == true
    elseif cable.dst and r.ValidatePtr(cable.dst, "MediaTrack*") then
        dst_selected = pb_selected_set[r.GetTrackGUID(cable.dst)] == true
    end
    if not src_selected and not dst_selected then return RemovePatchbayCable(cable) end
    local targets = {}
    local seen = {}
    local function add_target(src, dst, is_main)
        if not src or not r.ValidatePtr(src, "MediaTrack*") then return end
        if not is_main and (not dst or not r.ValidatePtr(dst, "MediaTrack*") or src == dst) then return end
        local sg = r.GetTrackGUID(src)
        local dg = is_main and MASTER_GUID or r.GetTrackGUID(dst)
        local key = sg .. "->" .. dg
        if seen[key] then return end
        seen[key] = true
        targets[#targets + 1] = { src = src, dst = dst, is_main = is_main }
    end
    local selected_tracks = GetSelectedPatchbayTracks()
    if cable.is_main then
        if src_selected then
            for i = 1, #selected_tracks do
                add_target(selected_tracks[i].track, nil, true)
            end
        else
            add_target(cable.src, nil, true)
        end
    elseif src_selected then
        for i = 1, #selected_tracks do
            add_target(selected_tracks[i].track, cable.dst, false)
        end
    elseif dst_selected then
        for i = 1, #selected_tracks do
            add_target(cable.src, selected_tracks[i].track, false)
        end
    else
        add_target(cable.src, cable.dst, cable.is_main)
    end
    if #targets == 0 then return false end
    local changes = 0
    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)
    for i = 1, #targets do
        if RemovePatchbayCableTargetNoUndo(targets[i]) then changes = changes + 1 end
    end
    r.PreventUIRefresh(-1)
    r.TrackList_AdjustWindows(false)
    r.UpdateArrange()
    r.Undo_EndBlock(changes > 1 and "Patchbay: delete selected connections" or "Patchbay: delete connection", -1)
    return changes > 0
end

local function RemoveSelectedFolderLinks(folder_link)
    if IsAllLockedCfg(GetConfig()) then return false end
    if not folder_link or not folder_link.track or not r.ValidatePtr(folder_link.track, "MediaTrack*") then return false end
    local parent_guid = folder_link.folder_parent_guid
    if not parent_guid then return false end
    local child_guids = {}
    local seen = {}
    local function add_child_guid(guid)
        if not guid or seen[guid] then return end
        seen[guid] = true
        child_guids[#child_guids + 1] = guid
    end
    if pb_selected_set[folder_link.guid] then
        local selected_tracks = GetSelectedPatchbayTracks()
        for i = 1, #selected_tracks do
            local parent = GetDirectFolderParentLocal(selected_tracks[i].track)
            if parent and r.ValidatePtr(parent, "MediaTrack*") and r.GetTrackGUID(parent) == parent_guid then
                add_child_guid(selected_tracks[i].guid)
            end
        end
    end
    if #child_guids == 0 then add_child_guid(folder_link.guid) end
    table.sort(child_guids, function(a, b)
        return GetTrackIndexLocal(FindTrackByGuidLocal(a)) > GetTrackIndexLocal(FindTrackByGuidLocal(b))
    end)
    local changed = false
    for i = 1, #child_guids do
        local child = FindTrackByGuidLocal(child_guids[i])
        if child and r.ValidatePtr(child, "MediaTrack*") then
            RemoveTrackFromFolderParent(child)
            changed = true
        end
    end
    return changed
end

function PatchbayPopupTrackLabel(track)
    if not track or not r.ValidatePtr(track, "MediaTrack*") then return "Track" end
    if track == r.GetMasterTrack(0) then return "MASTER" end
    local idx = math.floor(r.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER") or 0)
    local _, name = r.GetTrackName(track)
    if idx > 0 then return string.format("#%d %s", idx, name or "") end
    return name or "Track"
end

function PatchbayPinConnectionLabel(src, dst, is_main)
    local label = PatchbayPopupTrackLabel(src) .. " -> " .. PatchbayPopupTrackLabel(dst)
    if is_main then label = label .. " (main send)" end
    return label
end
function PatchbayRouteIndicatorBadges(src, idx, is_main)
    local parts = {}
    if is_main then
        parts[#parts + 1] = { label = "MAIN", color = 0xA8A8A8FF }
    else
        local mode = math.floor(r.GetTrackSendInfo_Value(src, 0, idx, "I_SENDMODE") or 0)
        if mode == 1 then
            parts[#parts + 1] = { label = "PFX", color = 0xC084FCFF }
        elseif mode == 3 then
            parts[#parts + 1] = { label = "PRE", color = 0xE0AF68FF }
        else
            parts[#parts + 1] = { label = "POST", color = 0x7AA2F7FF }
        end
        if r.GetTrackSendInfo_Value(src, 0, idx, "B_MUTE") == 1 then parts[#parts + 1] = { label = "MUTE", color = 0xF7768EFF } end
        if r.GetTrackSendInfo_Value(src, 0, idx, "B_PHASE") == 1 then parts[#parts + 1] = { label = "PH", color = 0xE0AF68FF } end
        if r.GetTrackSendInfo_Value(src, 0, idx, "B_MONO") == 1 then parts[#parts + 1] = { label = "MONO", color = 0x9ECE6AFF } end
        local type_info = GetSendTypeInfo(src, idx, false)
        if type_info and type_info.badge and type_info.badge ~= "" then parts[#parts + 1] = { label = type_info.badge, color = type_info.badge_col or 0xA8A8A8FF } end
    end
    return parts
end

function RenderPatchbayRouteBadges(ctx, badges)
    if not badges or #badges == 0 then return end
    for i = 1, #badges do
        r.ImGui_SameLine(ctx)
        r.ImGui_TextColored(ctx, badges[i].color, "[" .. badges[i].label .. "]")
    end
end

function CollectPinConnectionRoutes(track, guid, side)
    local routes = {}
    local master_track = r.GetMasterTrack(0)
    if side == "out" then
        if not track or not r.ValidatePtr(track, "MediaTrack*") then return routes end
        local nsnd = r.GetTrackNumSends(track, 0)
        for idx = 0, nsnd - 1 do
            local dst = r.GetTrackSendInfo_Value(track, 0, idx, "P_DESTTRACK")
            if dst and r.ValidatePtr(dst, "MediaTrack*") then
                routes[#routes + 1] = { src = track, dst = dst, idx = idx, is_main = false, label = PatchbayPinConnectionLabel(track, dst, false), badges = PatchbayRouteIndicatorBadges(track, idx, false) }
            end
        end
        if r.GetMediaTrackInfo_Value(track, "B_MAINSEND") == 1 then
            routes[#routes + 1] = { src = track, dst = master_track, idx = -1, is_main = true, label = PatchbayPinConnectionLabel(track, master_track, true), badges = PatchbayRouteIndicatorBadges(track, -1, true) }
        end
    elseif side == "in" then
        if guid == MASTER_GUID or track == master_track then
            local n = r.CountTracks(0)
            for i = 0, n - 1 do
                local src = r.GetTrack(0, i)
                if src and r.ValidatePtr(src, "MediaTrack*") and r.GetMediaTrackInfo_Value(src, "B_MAINSEND") == 1 then
                    routes[#routes + 1] = { src = src, dst = master_track, idx = -1, is_main = true, label = PatchbayPinConnectionLabel(src, master_track, true), badges = PatchbayRouteIndicatorBadges(src, -1, true) }
                end
            end
        else
            if not track or not r.ValidatePtr(track, "MediaTrack*") then return routes end
            local n = r.CountTracks(0)
            for i = 0, n - 1 do
                local src = r.GetTrack(0, i)
                if src and r.ValidatePtr(src, "MediaTrack*") then
                    local nsnd = r.GetTrackNumSends(src, 0)
                    for idx = 0, nsnd - 1 do
                        local dst = r.GetTrackSendInfo_Value(src, 0, idx, "P_DESTTRACK")
                        if dst == track then
                            routes[#routes + 1] = { src = src, dst = track, idx = idx, is_main = false, label = PatchbayPinConnectionLabel(src, track, false), badges = PatchbayRouteIndicatorBadges(src, idx, false) }
                        end
                    end
                end
            end
        end
    end
    return routes
end

function OpenPinRouteContext(track, guid, side)
    PB.pin_popup_track = track
    PB.pin_popup_guid = guid
    PB.pin_popup_side = side
    local routes = CollectPinConnectionRoutes(track, guid, side)
    if #routes == 1 then
        local route = routes[1]
        right_click_send = { src = route.src, dst = route.dst, idx = route.idx, is_main = route.is_main }
        PB.pin_popup_track = nil
        PB.pin_popup_guid = nil
        PB.pin_popup_side = nil
        return true
    end
    return false
end

function RenderPinConnectionPopup()
    local ctx = GetCtx()
    if not PB.pin_popup_guid or not PB.pin_popup_side then return end
    if r.ImGui_BeginPopup(ctx, "PatchbayPinPopup") then
        local routes = CollectPinConnectionRoutes(PB.pin_popup_track, PB.pin_popup_guid, PB.pin_popup_side)
        local title = PB.pin_popup_side == "out" and "Output connections" or "Input connections"
        r.ImGui_TextDisabled(ctx, title)
        if #routes > 0 then r.ImGui_TextDisabled(ctx, "Source -> Target") end
        r.ImGui_Separator(ctx)
        if #routes == 0 then
            r.ImGui_TextDisabled(ctx, PB.pin_popup_side == "out" and "No outgoing sends." or "No incoming sends.")
        else
            for i = 1, #routes do
                local route = routes[i]
                if r.ImGui_Selectable(ctx, route.label .. "##pin_route_" .. i) then
                    right_click_send = { src = route.src, dst = route.dst, idx = route.idx, is_main = route.is_main }
                    PB.pin_popup_track = nil
                    PB.pin_popup_guid = nil
                    PB.pin_popup_side = nil
                    PB.open_send_popup_from_pin = true
                    r.ImGui_CloseCurrentPopup(ctx)
                end
                RenderPatchbayRouteBadges(ctx, route.badges)
            end
        end
        r.ImGui_EndPopup(ctx)
    else
        PB.pin_popup_track = nil
        PB.pin_popup_guid = nil
        PB.pin_popup_side = nil
    end
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
            r.ImGui_Text(ctx, PatchbayPopupTrackLabel(src) .. " \xE2\x86\x92 MASTER")
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
                RemovePatchbayCable(s)
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
        r.ImGui_Text(ctx, PatchbayPopupTrackLabel(src) .. " \xE2\x86\x92 " .. PatchbayPopupTrackLabel(dst))
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

        local type_info = GetSendTypeInfo(src, idx, false)
        r.ImGui_TextDisabled(ctx, type_info.details)
        local preset_names = { "Audio 1/2", "Sidechain 3/4", "MIDI only", "Audio + MIDI" }
        local preset_values = { "audio", "sidechain", "midi", "audio_midi" }
        if r.ImGui_BeginCombo(ctx, "Type preset", type_info.label) then
            for k = 1, #preset_names do
                if r.ImGui_Selectable(ctx, preset_names[k], false) then
                    ApplySendTypePreset(src, dst, idx, preset_values[k])
                end
            end
            r.ImGui_EndCombo(ctx)
        end
        RenderChannelIOControls(ctx, src, dst, idx)
        r.ImGui_PopItemWidth(ctx)

        r.ImGui_Separator(ctx)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x802020FF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0xA03030FF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0x601010FF)
        if r.ImGui_Button(ctx, "Delete connection") then
                RemovePatchbayCable(s)
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
            if IsAllLockedCfg(GetConfig()) then
                r.ImGui_TextDisabled(ctx, "Rename Track")
            elseif r.ImGui_Selectable(ctx, "Rename Track...") then
                r.ImGui_CloseCurrentPopup(ctx)
                RenamePatchbayTrack(tr)
            end
            r.ImGui_Separator(ctx)
            if r.ImGui_Selectable(ctx, "Copy track selection   Ctrl+C") then
                PatchbayCopyNodeTracks(tr, node_popup_guid)
                r.ImGui_CloseCurrentPopup(ctx)
            end
            if IsAllLockedCfg(GetConfig()) then
                r.ImGui_TextDisabled(ctx, "Paste tracks")
            elseif r.ImGui_Selectable(ctx, "Paste tracks   Ctrl+V") then
                PatchbayPasteTracksAtNode(tr, node_popup_guid, GetPatchbayMouseSpawn(ctx))
                r.ImGui_CloseCurrentPopup(ctx)
            end
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
            if IsAllLockedCfg(GetConfig()) then
                r.ImGui_TextDisabled(ctx, "Connect to")
            elseif r.ImGui_BeginMenu(ctx, "Connect to") then
                local source = { { track = tr, guid = node_popup_guid, name = tname } }
                if r.ImGui_Selectable(ctx, "MASTER") then
                    PatchbayBatchSetMainSend(source, true, "Patchbay: enable main send")
                    r.ImGui_CloseCurrentPopup(ctx)
                end
                r.ImGui_Separator(ctx)
                local ntracks = r.CountTracks(0)
                for i = 0, ntracks - 1 do
                    local dst = r.GetTrack(0, i)
                    if dst and r.ValidatePtr(dst, "MediaTrack*") and dst ~= tr then
                        local idx = math.floor(r.GetMediaTrackInfo_Value(dst, "IP_TRACKNUMBER") or 0)
                        local _, name = r.GetTrackName(dst)
                        local label = string.format("#%d %s", idx, name or "")
                        if r.ImGui_Selectable(ctx, label, GetSendIndexLocal(tr, dst) >= 0) then
                            BatchConnectSelectedToDestination(source, dst)
                            r.ImGui_CloseCurrentPopup(ctx)
                        end
                    end
                end
                r.ImGui_EndMenu(ctx)
            end
            r.ImGui_Separator(ctx)
            if r.ImGui_BeginMenu(ctx, "Folder") then
                local selected_tracks_for_folder = GetSelectedPatchbayTracks()
                local child_count = 0
                for i = 1, #selected_tracks_for_folder do
                    if selected_tracks_for_folder[i].guid ~= node_popup_guid then child_count = child_count + 1 end
                end
                if IsAllLockedCfg(GetConfig()) then
                    r.ImGui_TextDisabled(ctx, "All locked")
                elseif child_count == 0 then
                    r.ImGui_TextDisabled(ctx, "Select child nodes first")
                elseif r.ImGui_Selectable(ctx, string.format("Add selected as children (%d)", child_count)) then
                    AssignSelectedTracksAsFolderChildren(tr, selected_tracks_for_folder)
                    r.ImGui_CloseCurrentPopup(ctx)
                end
                local folder_parent = GetDirectFolderParentLocal(tr)
                if folder_parent and r.ValidatePtr(folder_parent, "MediaTrack*") then
                    if IsAllLockedCfg(GetConfig()) then
                        r.ImGui_TextDisabled(ctx, "Remove from parent")
                    elseif r.ImGui_Selectable(ctx, "Remove from parent") then
                        RemoveTrackFromFolderParent(tr)
                        r.ImGui_CloseCurrentPopup(ctx)
                    end
                else
                    r.ImGui_TextDisabled(ctx, "Not inside a folder")
                end
                r.ImGui_TextDisabled(ctx, "Simple folder structures only")
                r.ImGui_EndMenu(ctx)
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
            r.ImGui_Separator(ctx)
            if r.ImGui_BeginMenu(ctx, "Add to group") then
                local group_target_guids = PatchbayNodeGroupTargetGuids(node_popup_guid)
                r.ImGui_TextDisabled(ctx, string.format("%d node(s)", #group_target_guids))
                r.ImGui_Separator(ctx)
                if r.ImGui_Selectable(ctx, "New group...") then
                    local ok, gname = r.GetUserInputs("Add to group", 1, "Group name:", "")
                    if ok and Trim(gname) ~= "" then
                        AddGuidsToGroupNamed(gname, group_target_guids)
                    end
                    r.ImGui_CloseCurrentPopup(ctx)
                end
                if #group_names > 0 then
                    r.ImGui_Separator(ctx)
                    for gi = 1, #group_names do
                        local gnm = group_names[gi]
                        if r.ImGui_Selectable(ctx, gnm) then
                            AddGuidsToGroupNamed(gnm, group_target_guids)
                            r.ImGui_CloseCurrentPopup(ctx)
                        end
                    end
                end
                r.ImGui_EndMenu(ctx)
            end
            local member_groups = PatchbayNodeGroupsContaining(PatchbayNodeGroupTargetGuids(node_popup_guid))
            if #member_groups > 0 and r.ImGui_BeginMenu(ctx, "Remove from group") then
                local remove_target_guids = PatchbayNodeGroupTargetGuids(node_popup_guid)
                for gi = 1, #member_groups do
                    local gnm = member_groups[gi]
                    if r.ImGui_Selectable(ctx, gnm) then
                        RemoveGuidsFromGroupNamed(gnm, remove_target_guids)
                        r.ImGui_CloseCurrentPopup(ctx)
                    end
                end
                r.ImGui_EndMenu(ctx)
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

    HandlePatchbayExternalAction(cfg, layout_locked)

    local proj_key = GetCurrentProjectKey()
    if proj_key ~= layout_loaded_project then
        if layout_loaded_project ~= nil and layout_dirty then SaveLayout() end
        layout_loaded_project = proj_key
        LoadLayout()
        LoadSnapshotStore()
        LoadGroupStore()
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
        r.ImGui_TextDisabled(ctx, "Spacing")
        for i = 1, #LAYOUT_PRESET_ORDER do
            local p = LAYOUT_PRESET_ORDER[i]
            if p == "folder_tree" then
                r.ImGui_Separator(ctx)
                r.ImGui_TextDisabled(ctx, "Structure")
            end
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
        local snap_to_grid = cfg.patchbay_snap_to_grid == true
        if r.ImGui_Selectable(ctx, "Snap", snap_to_grid) then
            cfg.patchbay_snap_to_grid = not snap_to_grid
            if _G.SaveConfig then _G.SaveConfig() end
        end
        if r.ImGui_Selectable(ctx, "Prevent overlap", cfg.patchbay_prevent_overlap ~= false) then
            cfg.patchbay_prevent_overlap = not (cfg.patchbay_prevent_overlap ~= false)
            if _G.SaveConfig then _G.SaveConfig() end
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
        local hide_child_master_flow = cfg.patchbay_hide_child_master_flow == true
        local changed_hide_child_master_flow, new_hide_child_master_flow = r.ImGui_Checkbox(ctx, "Hide child master flow", hide_child_master_flow)
        if changed_hide_child_master_flow then
            cfg.patchbay_hide_child_master_flow = new_hide_child_master_flow
            if _G.SaveConfig then _G.SaveConfig() end
        end
        local only_explicit = cfg.patchbay_only_explicit_routing == true
        local changed_explicit, new_explicit = r.ImGui_Checkbox(ctx, "Explicit", only_explicit)
        if changed_explicit then
            cfg.patchbay_only_explicit_routing = new_explicit
            if _G.SaveConfig then _G.SaveConfig() end
        end
        local explicit_show_mainsend = cfg.patchbay_explicit_show_mainsend == true
        local changed_explicit_master, new_explicit_master = r.ImGui_Checkbox(ctx, "Master flow in explicit", explicit_show_mainsend)
        if changed_explicit_master then
            cfg.patchbay_explicit_show_mainsend = new_explicit_master
            if _G.SaveConfig then _G.SaveConfig() end
        end
        local show_unrouted = cfg.patchbay_show_unrouted == true
        local changed_unrouted, new_unrouted = r.ImGui_Checkbox(ctx, "Only isolated", show_unrouted)
        if changed_unrouted then
            cfg.patchbay_show_unrouted = new_unrouted
            if _G.SaveConfig then _G.SaveConfig() end
        end
        local show_flow = cfg.patchbay_show_flow ~= false
        local changed_flow, new_flow = r.ImGui_Checkbox(ctx, "Flow", show_flow)
        if changed_flow then
            cfg.patchbay_show_flow = new_flow
            if _G.SaveConfig then _G.SaveConfig() end
        end
        local show_folder_links = cfg.patchbay_show_folder_links ~= false
        local changed_folder_links, new_folder_links = r.ImGui_Checkbox(ctx, "Folder links", show_folder_links)
        if changed_folder_links then
            cfg.patchbay_show_folder_links = new_folder_links
            if _G.SaveConfig then _G.SaveConfig() end
        end
        local show_send_type_badges = cfg.patchbay_show_send_type_badges ~= false
        local changed_send_type_badges, new_send_type_badges = r.ImGui_Checkbox(ctx, "Send type badges", show_send_type_badges)
        if changed_send_type_badges then
            cfg.patchbay_show_send_type_badges = new_send_type_badges
            if _G.SaveConfig then _G.SaveConfig() end
        end
        local focus_selected = cfg.routing_only_selected == true
        local changed_focus_selected, new_focus_selected = r.ImGui_Checkbox(ctx, "Focus selected", focus_selected)
        if changed_focus_selected then
            cfg.routing_only_selected = new_focus_selected
            if new_focus_selected then
                cfg.patchbay_selected_with_children = false
                cfg.patchbay_selected_subtree = false
            end
            if _G.SaveConfig then _G.SaveConfig() end
        end
        local selected_with_children = cfg.patchbay_selected_with_children == true
        local changed_selected_with_children, new_selected_with_children = r.ImGui_Checkbox(ctx, "Focus selected tree", selected_with_children)
        if changed_selected_with_children then
            cfg.patchbay_selected_with_children = new_selected_with_children
            if new_selected_with_children then
                cfg.routing_only_selected = false
                cfg.patchbay_selected_subtree = false
            end
            if _G.SaveConfig then _G.SaveConfig() end
        end
        local selected_subtree = cfg.patchbay_selected_subtree == true
        local changed_selected_subtree, new_selected_subtree = r.ImGui_Checkbox(ctx, "Focus selected subtree", selected_subtree)
        if changed_selected_subtree then
            cfg.patchbay_selected_subtree = new_selected_subtree
            if new_selected_subtree then
                cfg.routing_only_selected = false
                cfg.patchbay_selected_with_children = false
            end
            if _G.SaveConfig then _G.SaveConfig() end
        end
        local tcp_mirror = PB.tcp_mirror_enabled == true
        local changed_tcp_mirror, new_tcp_mirror = r.ImGui_Checkbox(ctx, "Mirror view to TCP", tcp_mirror)
        if changed_tcp_mirror then
            PatchbaySetTcpMirrorEnabled(new_tcp_mirror)
        end
        local solo_path = cfg.patchbay_solo_path == true
        local changed_solo_path, new_solo_path = r.ImGui_Checkbox(ctx, "Solo path", solo_path)
        if changed_solo_path then
            cfg.patchbay_solo_path = new_solo_path
            if _G.SaveConfig then _G.SaveConfig() end
        end
        local show_notes = cfg.patchbay_show_notes == true
        local changed_show_notes, new_show_notes = r.ImGui_Checkbox(ctx, "Show notes", show_notes)
        if changed_show_notes then
            cfg.patchbay_show_notes = new_show_notes
            if _G.SaveConfig then _G.SaveConfig() end
        end
        if r.ImGui_Selectable(ctx, "Cable shop...") then
            cable_shop_open = true
        end
        if r.ImGui_Selectable(ctx, "View options...") then
            view_help_open = true
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
        if r.ImGui_Selectable(ctx, "Arm selected") then
            BatchSetRecordArm(selected_tracks, true)
        end
        if r.ImGui_Selectable(ctx, "Unarm selected") then
            BatchSetRecordArm(selected_tracks, false)
        end
        if r.ImGui_Selectable(ctx, "Freeze selected") then
            BatchSetFreeze(selected_tracks, true)
        end
        if r.ImGui_Selectable(ctx, "Unfreeze selected") then
            BatchSetFreeze(selected_tracks, false)
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
        if r.ImGui_Selectable(ctx, "Copy selected tracks   Ctrl+C") then
            PatchbayCopySelectedTracks()
        end
        if r.ImGui_Selectable(ctx, "Paste tracks   Ctrl+V") then
            PatchbayPasteTracks(GetPatchbayMouseSpawn(ctx))
        end
        r.ImGui_Separator(ctx)
        if r.ImGui_Selectable(ctx, "Delete selected...   Del") then
            delete_selected_targets = selected_tracks
            r.ImGui_OpenPopup(ctx, "PatchbayDeleteSelectedConfirm")
        end
        if r.ImGui_Selectable(ctx, "Clear selection") then
            pb_selected_set = {}
        end
        r.ImGui_EndPopup(ctx)
    end
    r.ImGui_SameLine(ctx)
    local template_btn_w = menu_btn_w
    if menu_btn_compact and r.ImGui_CalcTextSize then
        template_btn_w = (select(1, r.ImGui_CalcTextSize(ctx, "Template")) or 0) + menu_btn_text_pad
    end
    if ToolbarMenuButton(ctx, "##patchbay_menu_templates", "Template", template_btn_w, "patchbay_template_menu") then
        if r.ImGui_GetItemRectMin and r.ImGui_GetItemRectMax then
            local x1, _ = r.ImGui_GetItemRectMin(ctx)
            local _, y2 = r.ImGui_GetItemRectMax(ctx)
            popup_templates_x = x1
            popup_templates_y = y2 + popup_menu_offset_y
        end
        OpenToolbarPopup(ctx, "patchbay_template_menu")
    end
    if popup_templates_x and popup_templates_y and r.ImGui_SetNextWindowPos then
        local cond = r.ImGui_Cond_Appearing and r.ImGui_Cond_Appearing() or 0
        r.ImGui_SetNextWindowPos(ctx, popup_templates_x, popup_templates_y, cond)
    end
    if r.ImGui_SetNextWindowSizeConstraints then
        r.ImGui_SetNextWindowSizeConstraints(ctx, 320, 0, 320, 10000)
    elseif r.ImGui_SetNextWindowSize then
        local cond = r.ImGui_Cond_Appearing and r.ImGui_Cond_Appearing() or 0
        r.ImGui_SetNextWindowSize(ctx, 320, 0, cond)
    end
    if r.ImGui_BeginPopup(ctx, "patchbay_template_menu") then
        toolbar_popup_opened = true
        open_toolbar_popup_id = "patchbay_template_menu"
        local templates, root, root_exists = GetPatchbayTemplateList(false)
        r.ImGui_TextDisabled(ctx, "Track templates")
        r.ImGui_TextWrapped(ctx, root or "")
        if root_exists then
            r.ImGui_TextColored(ctx, 0x66CC66FF, string.format("%d found", #templates))
        else
            r.ImGui_TextColored(ctx, 0xFF6666FF, "Folder not found")
        end
        if r.ImGui_Selectable(ctx, "Refresh") then
            GetPatchbayTemplateList(true)
        end
        if r.ImGui_Selectable(ctx, "Browse template...") then
            local ok, path = r.GetUserFileNameForRead((root or "") .. "/", "Select track template", ".RTrackTemplate")
            if ok and path and path ~= "" then
                InsertPatchbayTrackTemplate(path, { mode = "visible" })
                r.ImGui_CloseCurrentPopup(ctx)
            end
        end
        r.ImGui_Separator(ctx)
        local tpl_cfg = GetConfig()
        if tpl_cfg then
            local use_custom = tpl_cfg.use_custom_template_dir == true
            local ch_use, v_use = r.ImGui_Checkbox(ctx, "Custom folder", use_custom)
            if ch_use then
                tpl_cfg.use_custom_template_dir = v_use
                patchbay_template_cache_dirty = true
                if _G.SaveConfig then _G.SaveConfig() end
            end
            r.ImGui_PushItemWidth(ctx, 260)
            local ch_dir, v_dir = r.ImGui_InputText(ctx, "##patchbay_template_dir", tpl_cfg.custom_template_dir or "")
            if ch_dir then
                tpl_cfg.custom_template_dir = v_dir
                patchbay_template_cache_dirty = true
                if _G.SaveConfig then _G.SaveConfig() end
            end
            r.ImGui_PopItemWidth(ctx)
            if r.JS_Dialog_BrowseForFolder and r.ImGui_Button(ctx, "Browse folder...", 130, 0) then
                local rv, path = r.JS_Dialog_BrowseForFolder("Select Track Templates folder", ResolvePatchbayTrackTemplatesRoot())
                if rv == 1 and path and path ~= "" then
                    tpl_cfg.custom_template_dir = path
                    tpl_cfg.use_custom_template_dir = true
                    patchbay_template_cache_dirty = true
                    if _G.SaveConfig then _G.SaveConfig() end
                end
            end
            if r.JS_Dialog_BrowseForFolder then r.ImGui_SameLine(ctx) end
            if r.ImGui_Button(ctx, "Reset", 80, 0) then
                tpl_cfg.use_custom_template_dir = false
                tpl_cfg.custom_template_dir = ""
                patchbay_template_cache_dirty = true
                if _G.SaveConfig then _G.SaveConfig() end
            end
        end
        r.ImGui_Separator(ctx)
        if #templates == 0 then
            r.ImGui_TextDisabled(ctx, root_exists and "No templates found." or "Choose a valid template folder.")
        else
            for i = 1, #templates do
                local item = templates[i]
                if r.ImGui_Selectable(ctx, item.label .. "##patchbay_template_" .. i) then
                    InsertPatchbayTrackTemplate(item.full_path, { mode = "visible" })
                    r.ImGui_CloseCurrentPopup(ctx)
                end
                if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, item.full_path) end
            end
        end
        r.ImGui_EndPopup(ctx)
    end
    if not toolbar_popup_opened then
        open_toolbar_popup_id = nil
    end

    if #selected_tracks > 0 and not all_locked and open_toolbar_popup_id == nil and delete_selected_targets == nil and PatchbayDeleteSelectedShortcutPressed(ctx) then
        delete_selected_targets = selected_tracks
        r.ImGui_OpenPopup(ctx, "PatchbayDeleteSelectedConfirm")
    end

    if not all_locked and open_toolbar_popup_id == nil and delete_selected_targets == nil then
        if #selected_tracks > 0 and PatchbayCtrlShortcutPressed(ctx, r.ImGui_Key_C) then
            PatchbayCopySelectedTracks()
        elseif PatchbayCtrlShortcutPressed(ctx, r.ImGui_Key_V) then
            PatchbayPasteTracks(GetPatchbayMouseSpawn(ctx))
        elseif r.ImGui_Key_T and PatchbayCtrlShortcutPressed(ctx, r.ImGui_Key_T) then
            AddPatchbayTrack(GetPatchbayMouseSpawn(ctx))
        end
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
        AddPatchbayTrack({ mode = "visible" })
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

    if PB.open_route_audit_popup then
        PB.open_route_audit_popup = false
        r.ImGui_OpenPopup(ctx, "PatchbayRouteAudit")
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

    r.ImGui_SameLine(ctx)
    r.ImGui_PushItemWidth(ctx, 130)
    local ch_grp, v_grp = r.ImGui_InputTextWithHint(ctx, "##patchbay_group_name", "Group name", group_name_input or "")
    if ch_grp then group_name_input = v_grp end
    local grp_input_x2, grp_input_y1 = nil, nil
    if r.ImGui_GetItemRectMax and r.ImGui_GetItemRectMin then
        grp_input_x2 = select(1, r.ImGui_GetItemRectMax(ctx))
        grp_input_y1 = select(2, r.ImGui_GetItemRectMin(ctx))
    end
    r.ImGui_PopItemWidth(ctx)
    if grp_input_x2 and grp_input_y1 and r.ImGui_SetCursorScreenPos then
        r.ImGui_SetCursorScreenPos(ctx, grp_input_x2, grp_input_y1)
    else
        r.ImGui_SameLine(ctx)
    end
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), 2)
    local grp_save_h = r.ImGui_GetFrameHeight(ctx)
    if r.ImGui_Button(ctx, "G##patchbay_group_save", grp_save_h, grp_save_h) then
        local name = Trim(group_name_input)
        if name ~= "" and SaveGroupNamed(name) then
            group_name_input = ""
        end
    end
    if r.ImGui_IsItemHovered(ctx) then
        r.ImGui_SetTooltip(ctx, "Create group from selected nodes")
    end
    r.ImGui_PopStyleVar(ctx, 1)
    r.ImGui_SameLine(ctx)
    local grp_label = active_group_name or "Groups"
    r.ImGui_PushItemWidth(ctx, 130)
    local grp_flags = r.ImGui_ComboFlags_HeightLargest and r.ImGui_ComboFlags_HeightLargest() or 0
    if r.ImGui_GetCursorScreenPos and r.ImGui_GetFrameHeight and r.ImGui_SetNextWindowPos then
        local rx, ry = r.ImGui_GetCursorScreenPos(ctx)
        local cond = r.ImGui_Cond_Appearing and r.ImGui_Cond_Appearing() or 0
        r.ImGui_SetNextWindowPos(ctx, rx, ry + r.ImGui_GetFrameHeight(ctx) + 4, cond)
    end
    if r.ImGui_BeginCombo(ctx, "##patchbay_group_recall", grp_label, grp_flags) then
        local include_neighbors = not (cfg.patchbay_group_include_neighbors == false)
        local ch_nb, v_nb = r.ImGui_Checkbox(ctx, "Include neighbors", include_neighbors)
        if ch_nb then
            cfg.patchbay_group_include_neighbors = v_nb
            if _G.SaveConfig then _G.SaveConfig() end
            layout_dirty = true
        end
        r.ImGui_Separator(ctx)
        if r.ImGui_Selectable(ctx, "Show all", active_group_name == nil) then
            ClearActiveGroup()
        end
        r.ImGui_Separator(ctx)
        local delete_group_name = nil
        if r.ImGui_BeginTable then
            if r.ImGui_BeginTable(ctx, "##patchbay_group_recall_table", 2) then
                if r.ImGui_TableSetupColumn then
                    local stretch = r.ImGui_TableColumnFlags_WidthStretch and r.ImGui_TableColumnFlags_WidthStretch() or 0
                    local fixed = r.ImGui_TableColumnFlags_WidthFixed and r.ImGui_TableColumnFlags_WidthFixed() or 0
                    r.ImGui_TableSetupColumn(ctx, "Name", stretch)
                    r.ImGui_TableSetupColumn(ctx, "Del", fixed, 22)
                end
                for i = 1, #group_names do
                    local nm = group_names[i]
                    if r.ImGui_TableNextRow then r.ImGui_TableNextRow(ctx) end
                    if r.ImGui_TableSetColumnIndex then r.ImGui_TableSetColumnIndex(ctx, 0) end
                    if r.ImGui_Selectable(ctx, nm, active_group_name == nm) then
                        RecallGroup(nm)
                    end
                    if r.ImGui_TableSetColumnIndex then r.ImGui_TableSetColumnIndex(ctx, 1) end
                    if r.ImGui_SmallButton and r.ImGui_SmallButton(ctx, "x##group_del_" .. i) then
                        delete_group_name = nm
                    end
                    if r.ImGui_IsItemHovered(ctx) then
                        r.ImGui_SetTooltip(ctx, "Delete group")
                    end
                end
                r.ImGui_EndTable(ctx)
            end
        else
            for i = 1, #group_names do
                local nm = group_names[i]
                if r.ImGui_Selectable(ctx, nm, active_group_name == nm) then
                    RecallGroup(nm)
                end
            end
        end
        if delete_group_name then
            DeleteGroupNamed(delete_group_name)
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

    if bg_active and not PB.fx_schema_mouse_block and dragging_node_guid == nil and pending_connection == nil and not layout_locked then
        local dx, dy = r.ImGui_GetMouseDragDelta(ctx, 0, 0, 0)
        if dx ~= 0 or dy ~= 0 then
            canvas_offset_x = canvas_offset_x + dx
            canvas_offset_y = canvas_offset_y + dy
            r.ImGui_ResetMouseDragDelta(ctx, 0)
            layout_dirty = true
        end
    end

    if r.ImGui_IsWindowHovered(ctx) and not PB.fx_schema_mouse_block and r.ImGui_IsMouseDragging(ctx, 2) and not layout_locked then
        local dx, dy = r.ImGui_GetMouseDragDelta(ctx, 2, 0, 0)
        if dx ~= 0 or dy ~= 0 then
            canvas_offset_x = canvas_offset_x + dx
            canvas_offset_y = canvas_offset_y + dy
            r.ImGui_ResetMouseDragDelta(ctx, 2)
            layout_dirty = true
        end
    end

    if r.ImGui_IsWindowHovered(ctx) and not PB.fx_schema_mouse_block and not layout_locked then
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
    PatchbayApplyTcpMirror(tracks)
    if #tracks == 0 then
        r.ImGui_DrawList_AddText(draw_list, origin_x + 12, origin_y + 12, 0xAAAAAAFF, "No tracks match filter.")
        r.ImGui_EndChild(ctx)
        RenderRightClickPopup()
        return
    end

    EnsurePositions(tracks)
    PatchbayPlacePendingVisibleNodes(tracks, avail_w, avail_h)
    PatchbayPlacePendingSpawnNodes(tracks, origin_x, origin_y, avail_w, avail_h)

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
        elseif side == "bottom" then
            return (x1 + x2) * 0.5, y2
        else
            return x1, (y1 + y2) * 0.5
        end
    end

    local function CanStartFolderPin(tr)
        if all_locked or not r.ReorderSelectedTracks then return false end
        if not tr or tr.is_master or not tr.track or not r.ValidatePtr(tr.track, "MediaTrack*") then return false end
        local depth = math.floor(r.GetMediaTrackInfo_Value(tr.track, "I_FOLDERDEPTH") or 0)
        return depth <= 1
    end

    hovered_input_guid = nil
    local mx, my = r.ImGui_GetMousePos(ctx)
    local cfg = GetConfig()
    local cables = {}
    local master_in_view = guid_to[MASTER_GUID] ~= nil
    local master_track = master_in_view and guid_to[MASTER_GUID].track or nil
    local route_filter = cfg.patchbay_route_filter or "all"
    local selected_track = _G.TRACK
    local hide_child_master_flow = cfg.patchbay_hide_child_master_flow == true
    local solo_path_enabled = (cfg.patchbay_solo_path == true) and selected_track and r.ValidatePtr(selected_track, "MediaTrack*")
    local fx_schema_layout = nil
    local fx_schema_open_seen = false
    for i = 1, #tracks do
        local tr = tracks[i]
        if PB.fx_schema_open_guid == tr.guid then
            fx_schema_open_seen = true
            local x1, y1, x2, y2 = NodeRect(tr.guid)
            if x1 and not tr.is_master and not collapsed_nodes[tr.guid] and r.ValidatePtr(tr.track, "MediaTrack*") then
                fx_schema_layout = PatchbayFxSchemaBuildLayout(ctx, tr.track, tr.name, x1, y1, x2, y2, origin_x, origin_y, origin_x + avail_w, origin_y + avail_h, canvas_zoom)
            end
            break
        end
    end
    if PB.fx_schema_open_guid and not fx_schema_open_seen then PB.fx_schema_open_guid = nil end
    local fx_schema_blocks_mouse = fx_schema_layout and mx >= fx_schema_layout.x and mx <= fx_schema_layout.x + fx_schema_layout.w and my >= fx_schema_layout.y and my <= fx_schema_layout.y + fx_schema_layout.h
    PB.fx_schema_mouse_block = fx_schema_blocks_mouse == true

    local function CablePassesFilter(is_main, mode, muted, send_type_info)
        if route_filter == "all" then return true end
        if route_filter == "muted" then return muted == true end
        if route_filter == "pre-fx" then return (not is_main) and mode == 1 end
        if route_filter == "pre-fader" then return (not is_main) and mode == 3 end
        if route_filter == "post-fader" then
            if is_main then return true end
            return mode == 0
        end
        if route_filter == "audio" then return is_main or (send_type_info and send_type_info.has_audio and not send_type_info.is_sidechain) end
        if route_filter == "sidechain" then return send_type_info and send_type_info.is_sidechain end
        if route_filter == "midi" then return send_type_info and send_type_info.has_midi end
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
                        local send_type_info = GetSendTypeInfo(src, k, false)
                        if CablePassesFilter(false, mode, muted, send_type_info) and CablePassesSoloPath(src, dst) then
                            cables[#cables + 1] = {
                                src = src, dst = dst, sg = sg, dg = dg, idx = k,
                                mode = mode, muted = muted, phase = phase, vol = vol, send_type_info = send_type_info
                            }
                        end
                    end
                end
            end
            local child_master_hidden = hide_child_master_flow and tracks[i].is_folder_child
            if master_in_view and not child_master_hidden and r.GetMediaTrackInfo_Value(src, "B_MAINSEND") == 1 then
                local mode = 0
                local muted = false
                local phase = false
                local vol = r.GetMediaTrackInfo_Value(src, "D_VOL")
                local send_type_info = GetSendTypeInfo(src, -1, true)
                if CablePassesFilter(true, mode, muted, send_type_info) and CablePassesSoloPath(src, master_track) then
                    cables[#cables + 1] = {
                        src = src, dst = master_track, sg = sg, dg = MASTER_GUID, idx = -1, is_main = true,
                        mode = mode, muted = muted, phase = phase, vol = vol, send_type_info = send_type_info
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

    local hovered_folder_link = nil
    local folder_link_style = GetCableOverlayStyle("folder_links", cfg)
    if cfg.patchbay_show_folder_links ~= false and folder_link_style.visible then
        for i = 1, #tracks do
            local child = tracks[i]
            if child.folder_parent_guid and guid_to[child.folder_parent_guid] then
                local sx, sy = PinPos(child.folder_parent_guid, "bottom")
                local x1, y1, x2 = NodeRect(child.guid)
                if sx and x1 then
                    local dx = (x1 + x2) * 0.5
                    local dy = y1
                    if not fx_schema_blocks_mouse and not hovered_folder_link and PointSegDist(mx, my, sx, sy, dx, dy) <= math.max(6, 7 * canvas_zoom) then
                        hovered_folder_link = child
                    end
                    local parent_info = guid_to[child.folder_parent_guid]
                    local link_muted = (parent_info and (parent_info.track_muted or parent_info.ancestor_muted)) or child.ancestor_muted
                    local link_soloed = (parent_info and (parent_info.track_soloed or parent_info.ancestor_soloed)) or child.ancestor_soloed
                    local col = hovered_folder_link == child and folder_link_style.hover or folder_link_style.color
                    if link_muted then
                        col = hovered_folder_link == child and 0xFF7777DD or 0xCC5555AA
                    elseif link_soloed then
                        col = hovered_folder_link == child and 0xFFE080DD or 0xD8B94AAA
                    end
                    local thickness = math.max(1.0, folder_link_style.thickness * canvas_zoom)
                    if hovered_folder_link == child then thickness = thickness + 1 end
                    if link_muted or link_soloed then thickness = thickness + 0.5 end
                    r.ImGui_DrawList_AddLine(draw_list, sx, sy, dx, dy, col, thickness)
                    r.ImGui_DrawList_AddCircleFilled(draw_list, dx, dy, math.max(2.0, 2.5 * canvas_zoom), col)
                end
            end
        end
    end

    local hovered_cable = nil
    local cp_dist = 80 * canvas_zoom
    local show_flow = cfg.patchbay_show_flow ~= false
    local show_send_type_badges = cfg.patchbay_show_send_type_badges ~= false
    local flow_time = r.time_precise()

    for ci = 1, #cables do
        local c = cables[ci]
        local sx, sy = PinPos(c.sg, "out")
        local dx, dy = PinPos(c.dg, "in")
        local style = GetCableStyle(c, cfg)
        if sx and dx and style.visible then
            local cx1 = sx + cp_dist
            local cy1 = sy
            local cx2 = dx - cp_dist
            local cy2 = dy
            if not fx_schema_blocks_mouse and not hovered_cable and BezierHit(mx, my, sx, sy, cx1, cy1, cx2, cy2, dx, dy, 6) then
                hovered_cable = c
            end
        end
    end

    for ci = 1, #cables do
        local c = cables[ci]
        local sx, sy = PinPos(c.sg, "out")
        local dx, dy = PinPos(c.dg, "in")
        local style = GetCableStyle(c, cfg)
        if sx and dx and style.visible then
            local mode = c.mode
            local muted = c.muted
            local phase = c.phase
            local vol = c.vol
            local inherited_muted = false
            inherited_muted = PatchbayCableInheritedMuteInfo(c, guid_to)
            local thickness = style.thickness + math.min(2.5, math.max(0, (vol - 0.5)) * 1.5)
            if hovered_cable == c then thickness = thickness + 1 end
            local col, hcol = style.color, style.hover
            local audit_sev = route_audit_visual_active and route_audit_cable_marks[c.sg .. "->" .. c.dg] or nil
            if audit_sev == "error" then
                col = 0xE34A4AE0
                hcol = 0xFF6E6EFF
                thickness = thickness + 1.5
            elseif audit_sev == "warn" then
                col = 0xE3A94AE0
                hcol = 0xFFC46EFF
                thickness = thickness + 0.8
            elseif inherited_muted then
                col = 0x6A3434AA
                hcol = 0xB85A5ADD
                thickness = math.max(1.0, thickness - 0.4)
            end
            local use_col = (hovered_cable == c) and hcol or col
            r.ImGui_DrawList_AddBezierCubic(draw_list, sx, sy, sx + cp_dist, sy, dx - cp_dist, dy, dx, dy, use_col, thickness)
            local send_type_info = c.send_type_info
            if not audit_sev and send_type_info then
                if send_type_info.is_sidechain then
                    local sidechain_style = GetCableOverlayStyle("sidechain", cfg)
                    if sidechain_style.visible then
                        local sidechain_col = (hovered_cable == c) and sidechain_style.hover or sidechain_style.color
                        if inherited_muted then sidechain_col = 0x7A5A5AAA end
                        DrawBezierStripes(draw_list, sx, sy, sx + cp_dist, sy, dx - cp_dist, dy, dx, dy, sidechain_col, sidechain_style.thickness, thickness, true)
                    end
                end
                if send_type_info.has_midi then
                    local midi_style = GetCableOverlayStyle("midi", cfg)
                    if midi_style.visible then
                        local midi_col = (hovered_cable == c) and midi_style.hover or midi_style.color
                        if inherited_muted then midi_col = 0x7A5A5AAA end
                        DrawBezierStripes(draw_list, sx, sy, sx + cp_dist, sy, dx - cp_dist, dy, dx, dy, midi_col, midi_style.thickness, thickness)
                    end
                end
            end
            if show_flow then
                local t = (flow_time * 0.55 + ci * 0.137) % 1.0
                local fx, fy = BezierPoint(t, sx, sy, sx + cp_dist, sy, dx - cp_dist, dy, dx, dy)
                local dot_col
                if muted then
                    dot_col = 0x9A9A9AFF
                elseif inherited_muted then
                    dot_col = 0x7A5A5AFF
                elseif hovered_cable == c then
                    dot_col = 0xFFFFFFFF
                else
                    dot_col = 0xE6E6E6FF
                end
                r.ImGui_DrawList_AddCircleFilled(draw_list, fx, fy, math.max(2.0, 2.8 * canvas_zoom), dot_col)
            end
            if phase and not muted then
                local phase_style = {
                    color = cfg[CableShopKey("phase", "color")],
                    thickness = tonumber(cfg[CableShopKey("phase", "thickness")]) or 1.0,
                    visible = cfg[CableShopKey("phase", "visible")] ~= false
                }
                if phase_style.visible then
                    r.ImGui_DrawList_AddBezierCubic(draw_list, sx, sy, sx + cp_dist, sy, dx - cp_dist, dy, dx, dy, phase_style.color, phase_style.thickness)
                end
            end
            if show_send_type_badges and send_type_info and send_type_info.badge and send_type_info.badge ~= "" and canvas_zoom >= 0.55 then
                local bx, by = BezierPoint(0.53, sx, sy, sx + cp_dist, sy, dx - cp_dist, dy, dx, dy)
                local tw, th = r.ImGui_CalcTextSize(ctx, send_type_info.badge)
                local pad_x = 5
                local pad_y = 3
                local rx1 = bx - (tw * 0.5) - pad_x
                local ry1 = by - (th * 0.5) - pad_y
                local rx2 = bx + (tw * 0.5) + pad_x
                local ry2 = by + (th * 0.5) + pad_y
                r.ImGui_DrawList_AddRectFilled(draw_list, rx1, ry1, rx2, ry2, send_type_info.badge_col or 0x666666DD, 4)
                r.ImGui_DrawList_AddText(draw_list, bx - (tw * 0.5), by - (th * 0.5), 0xFFFFFFFF, send_type_info.badge)
            end
        end
    end

    local request_open_popup = false
    local request_open_node_popup = false
    local request_open_pin_popup = false
    local node_right_click_consumed = false
    local right_click_pin = nil

    if not fx_schema_blocks_mouse and r.ImGui_IsMouseClicked(ctx, 1) then
        local pin_r_hit = PIN_R * canvas_zoom
        if pin_r_hit < 4 then pin_r_hit = 4 end
        local hit_r = pin_r_hit + 4
        local hit_r2 = hit_r * hit_r
        for i = 1, #tracks do
            local tr = tracks[i]
            local ix, iy = PinPos(tr.guid, "in")
            if ix then
                local ddx = mx - ix
                local ddy = my - iy
                if ddx * ddx + ddy * ddy <= hit_r2 then
                    right_click_pin = { track = tr.track, guid = tr.guid, side = "in" }
                    break
                end
            end
            if not tr.is_master then
                local ox, oy = PinPos(tr.guid, "out")
                if ox then
                    local ddx = mx - ox
                    local ddy = my - oy
                    if ddx * ddx + ddy * ddy <= hit_r2 then
                        right_click_pin = { track = tr.track, guid = tr.guid, side = "out" }
                        break
                    end
                end
            end
        end
        if right_click_pin then
            if OpenPinRouteContext(right_click_pin.track, right_click_pin.guid, right_click_pin.side) then
                request_open_popup = true
            else
                request_open_pin_popup = true
            end
        end
    end

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
    
    local folder_link_click_consumed = false
    if hovered_folder_link and not node_right_click_consumed then
        local mods = r.ImGui_GetKeyMods and r.ImGui_GetKeyMods(ctx) or 0
        local mod_alt = r.ImGui_Mod_Alt and r.ImGui_Mod_Alt() or 0
        local alt_held = (mods & mod_alt) ~= 0
        if alt_held and r.ImGui_IsMouseClicked(ctx, 0) then
            RemoveSelectedFolderLinks(hovered_folder_link)
            folder_link_click_consumed = true
            hovered_folder_link = nil
        elseif hovered_folder_link then
            local parent = FindTrackByGuidLocal(hovered_folder_link.folder_parent_guid)
            local parent_name = "Parent"
            if parent and r.ValidatePtr(parent, "MediaTrack*") then
                local _, name = r.GetTrackName(parent)
                parent_name = name or parent_name
            end
            local child_name = hovered_folder_link.name or "Child"
            local folder_tip = pb_selected_set[hovered_folder_link.guid] and "Alt-click: remove selected children from this parent folder" or "Alt-click: remove from parent folder"
            local parent_info = hovered_folder_link.folder_parent_guid and guid_to[hovered_folder_link.folder_parent_guid] or nil
            local inherited_text = PatchbayInheritedStatusText(parent_info, "Parent") .. PatchbayInheritedStatusText(hovered_folder_link, "Child")
            if parent_info and parent_info.track_muted then inherited_text = inherited_text .. "\nParent muted: " .. (parent_info.name or parent_name) end
            if parent_info and parent_info.track_soloed then inherited_text = inherited_text .. "\nParent soloed: " .. (parent_info.name or parent_name) end
            r.ImGui_SetTooltip(ctx, string.format("%s \xE2\x86\x92 %s\n%s%s", parent_name, child_name, folder_tip, inherited_text))
        end
    end

    if hovered_cable and not hovered_folder_link and not folder_link_click_consumed and not node_right_click_consumed then
        local mods = r.ImGui_GetKeyMods and r.ImGui_GetKeyMods(ctx) or 0
        local mod_alt = r.ImGui_Mod_Alt and r.ImGui_Mod_Alt() or 0
        local alt_held = (mods & mod_alt) ~= 0
        if alt_held and r.ImGui_IsMouseClicked(ctx, 0) then
            if RemoveSelectedPatchbayCableRelations(hovered_cable) then hovered_cable = nil end
        end
        if hovered_cable then
            local _, sname = r.GetTrackName(hovered_cable.src)
            local dname
            local mlabel
            local vol
            local send_type_info
            if hovered_cable.is_main then
                dname = "MASTER"
                mlabel = "Main send (post-fader)"
                vol = r.GetMediaTrackInfo_Value(hovered_cable.src, "D_VOL")
                send_type_info = GetSendTypeInfo(hovered_cable.src, -1, true)
            else
                local _, dn = r.GetTrackName(hovered_cable.dst)
                dname = dn
                local mode = r.GetTrackSendInfo_Value(hovered_cable.src, 0, hovered_cable.idx, "I_SENDMODE")
                vol = r.GetTrackSendInfo_Value(hovered_cable.src, 0, hovered_cable.idx, "D_VOL")
                send_type_info = GetSendTypeInfo(hovered_cable.src, hovered_cable.idx, false)
                mlabel = "Post-Fader"
                if mode == 1 then mlabel = "Pre-FX" elseif mode == 3 then mlabel = "Pre-Fader (Post-FX)" end
            end
            local vol_db = vol > 0 and (20 * math.log(vol, 10)) or -150
            local type_details = send_type_info and send_type_info.details or "Type: Audio"
            local src_guid = r.GetTrackGUID(hovered_cable.src)
            local multi_remove = pb_selected_set[src_guid] == true
            if not multi_remove and not hovered_cable.is_main and hovered_cable.dst and r.ValidatePtr(hovered_cable.dst, "MediaTrack*") then
                multi_remove = pb_selected_set[r.GetTrackGUID(hovered_cable.dst)] == true
            elseif not multi_remove and hovered_cable.is_main then
                multi_remove = pb_selected_set[MASTER_GUID] == true
            end
            local remove_tip = multi_remove and "Alt-click: remove matching selected connections" or "Alt-click: remove connection"
            local inherited_muted, inherited_mute_name, inherited_mute_side = PatchbayCableInheritedMuteInfo(hovered_cable, guid_to)
            local inherited_tip = ""
            if inherited_muted then
                inherited_tip = inherited_mute_side == "destination" and ("\nDestination in muted folder: " .. tostring(inherited_mute_name or "Folder")) or ("\nMuted by folder ancestor: " .. tostring(inherited_mute_name or "Folder"))
            end
            r.ImGui_SetTooltip(ctx, string.format("%s \xE2\x86\x92 %s\n%s, %.1f dB\n%s%s\n%s", sname, dname, mlabel, vol_db, type_details, inherited_tip, remove_tip))
            if r.ImGui_IsMouseClicked(ctx, 1) then
                right_click_send = { src = hovered_cable.src, dst = hovered_cable.dst, idx = hovered_cable.idx, is_main = hovered_cable.is_main }
                request_open_popup = true
            end
        end
    end

    if not fx_schema_blocks_mouse and not hovered_cable and not hovered_folder_link and not node_right_click_consumed and bg_hovered and not pb_rubber_active and pending_connection == nil and pending_folder_connection == nil and r.ImGui_IsMouseClicked(ctx, 1) then
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
            local show_zoom_stats = canvas_zoom >= 0.70
            local show_zoom_markers = canvas_zoom >= 0.70

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
            local split_body_col = nil
            if (not is_master_node) and tr.is_folder_child and tr.folder_is_parent then
                local parent_body_col = FolderBodyColor(tr.folder_parent_r, tr.folder_parent_g, tr.folder_parent_b, not in_solo_focus)
                if parent_body_col then body_col = parent_body_col end
                split_body_col = FolderBodyColor(r8, g8, b8, not in_solo_focus)
            end
            r.ImGui_DrawList_AddRectFilled(draw_list, x1, y1, x2, y2, body_col, 6)
            if split_body_col then
                local split_x = x1 + ((x2 - x1) * 0.5)
                r.ImGui_DrawList_AddRectFilled(draw_list, split_x, y1 + 1, x2 - 1, y2 - 1, split_body_col, 0)
            end
            local bar_w = is_master_node and 7 or 14
            r.ImGui_DrawList_AddRectFilled(draw_list, x1, y1, x1 + bar_w, y2, bar_col, 6)
            local folder_role = nil
            if not is_master_node then
                if tr.folder_is_parent then
                    folder_role = "F"
                elseif tr.is_folder_child then
                    folder_role = "C"
                end
            end
            if folder_role and show_zoom_markers then
                local role_col = ((r8 * 0.299 + g8 * 0.587 + b8 * 0.114) > 150) and 0x111111DD or 0xFFFFFFFF
                if not in_solo_focus then role_col = 0xFFFFFF99 end
                local role_w, role_h = r.ImGui_CalcTextSize(ctx, folder_role)
                r.ImGui_DrawList_AddText(draw_list, x1 + ((bar_w - (role_w or 0)) * 0.5), y1 + 6, role_col, folder_role)
            end
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
            local label_x = x1 + bar_w + 6
            local trunc = TruncateText(ctx, label, NodeW() * canvas_zoom - (bar_w + 12))
            local label_col = is_master_node and 0xFFE090FF or 0xEEEEEEFF
            local node_is_pinned = pinned_nodes[g] == true
            local node_is_collapsed = collapsed_nodes[g] == true
            if not in_solo_focus then
                label_col = 0x8A8A8ACC
            end
            r.ImGui_DrawList_AddText(draw_list, label_x, y1 + 6, label_col, trunc)
            if node_is_pinned and show_zoom_markers and node_is_collapsed then
                r.ImGui_DrawList_AddText(draw_list, x2 - 14, y1 + 6, 0xE0C050FF, "P")
            end

            local node_screen_w = NodeW() * canvas_zoom
            local node_screen_h = NodeH(g) * canvas_zoom
            local control_size = math.max(10, math.min(14, math.floor(14 * canvas_zoom + 0.5)))
            local control_gap = math.max(2, math.floor(3 * canvas_zoom + 0.5))
            local control_pad_y = math.max(5, math.floor(6 * canvas_zoom + 0.5))
            local control_left_group_w = (control_size * 2) + control_gap
            local control_right_group_w = (control_size * 4) + (control_gap * 3)
            local show_node_controls = (not is_master_node) and (not node_is_collapsed) and canvas_zoom >= 0.50 and node_screen_w >= (control_left_group_w + control_right_group_w + bar_w + 21) and node_screen_h >= (control_size + 22)
            local control_left_x = x1 + bar_w + 5
            local control_right_x = x2 - 8 - control_right_group_w
            local control_y = y2 - control_size - control_pad_y
            local node_control_hit = show_node_controls and my >= control_y - 4 and my <= y2 and ((mx >= control_left_x - 4 and mx <= control_left_x + control_left_group_w + 4) or (mx >= control_right_x - 4 and mx <= control_right_x + control_right_group_w + 4))

            if (not is_master_node) and (not show_node_controls) then
                local st_mute = tr.track_muted == true
                local st_arm = tr.track_armed == true
                local st_solo = tr.track_soloed == true
                local st_freeze = tr.track_frozen == true
                if st_mute or st_arm or st_solo or st_freeze then
                    local strip_h = math.max(3, math.floor(4 * canvas_zoom + 0.5))
                    local sx1 = x1 + bar_w
                    local sx2 = x2 - 2
                    local sy2 = y2 - 2
                    local sy1 = sy2 - strip_h
                    local seg_w = (sx2 - sx1) / 4
                    r.ImGui_DrawList_AddRectFilled(draw_list, sx1, sy1, sx2, sy2, 0x000000AA, 0)
                    local state_segs = {
                        { on = st_mute, col = in_solo_focus and 0xC94FB0FF or 0xC94FB099 },
                        { on = st_arm, col = in_solo_focus and 0xE05050FF or 0xE0505099 },
                        { on = st_solo, col = in_solo_focus and 0xCCBB33FF or 0xCCBB3399 },
                        { on = st_freeze, col = in_solo_focus and 0x4488CCFF or 0x4488CC99 },
                    }
                    for si = 1, 4 do
                        if state_segs[si].on then
                            local gx1 = sx1 + seg_w * (si - 1)
                            local gx2 = (si == 4) and sx2 or (sx1 + seg_w * si)
                            r.ImGui_DrawList_AddRectFilled(draw_list, gx1, sy1, gx2, sy2, state_segs[si].col, 0)
                        end
                    end
                end
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
                local stats_max_w = (NodeW() * canvas_zoom) - (bar_w + 18)
                if not is_master_node then stats_max_w = stats_max_w - (2 * (14 * canvas_zoom) + 10) end
                local stats_trunc = TruncateText(ctx, stats, stats_max_w)
                local stats_col = in_solo_focus and 0xAAAAAAFF or 0x676767CC
                r.ImGui_DrawList_AddText(draw_list, label_x, y1 + 22, stats_col, stats_trunc)
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
            if canvas_zoom < 0.70 and not fx_schema_blocks_mouse and body_hovered and not node_control_hit then
                r.ImGui_SetTooltip(ctx, label)
            end
            if not fx_schema_blocks_mouse and not right_click_pin and body_hovered and not node_control_hit and r.ImGui_IsMouseClicked(ctx, 1) then
                node_right_click_consumed = true
                if not is_master_node then
                    node_popup_track = tr.track
                    node_popup_guid = g
                    request_open_node_popup = true
                end
            end
            if not fx_schema_blocks_mouse and body_hovered and not node_control_hit and r.ImGui_IsMouseClicked(ctx, 0) then
                local mods = r.ImGui_GetKeyMods and r.ImGui_GetKeyMods(ctx) or 0
                local mod_ctrl = r.ImGui_Mod_Ctrl and r.ImGui_Mod_Ctrl() or 0
                local ctrl_held = (mods & mod_ctrl) ~= 0
                local pin_r_hit = PIN_R * canvas_zoom
                if pin_r_hit < 4 then pin_r_hit = 4 end
                local hit_r = pin_r_hit + 4
                local hit_out = nil
                local hit_folder = nil

                if not ctrl_held then
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
                            local fx, fy = PinPos(tracks[hi].guid, "bottom")
                            if fx and CanStartFolderPin(tracks[hi]) then
                                local ddx = mx - fx
                                local ddy = my - fy
                                if ddx * ddx + ddy * ddy <= hit_r * hit_r then
                                    hit_folder = tracks[hi]
                                    break
                                end
                            end
                        end
                    end
                end

                if hit_folder and not all_locked then
                    pending_folder_connection = { parent = hit_folder.track, parent_guid = hit_folder.guid }
                elseif hit_out and not all_locked then
                    pending_connection = { src = hit_out.track, src_guid = hit_out.guid }
                elseif hit_folder or hit_out then
                    pb_press_guid = nil
                    pb_press_dragged = false
                else

                    if is_master_node then
                        pb_selected_set = { [g] = true }
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
                    PatchbaySyncSelectedSetToTCP(tr.track)
                    if not ctrl_held then
                        pb_press_guid = g
                        pb_press_dragged = false
                    end
                end
            end
            if not fx_schema_blocks_mouse and body_active and not node_control_hit and pending_connection == nil and pending_folder_connection == nil and not layout_locked then
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
            if show_node_controls then
                local mute_on = tr.track_muted == true
                local solo_on = tr.track_soloed == true
                local arm_on = tr.track_armed == true
                local freeze_on = tr.track_frozen == true
                local mute_tip = mute_on and "Unmute track" or "Mute track"
                local solo_tip = solo_on and "Unsolo track" or "Solo track"
                local arm_tip = arm_on and "Unarm track" or "Arm track"
                local freeze_tip = freeze_on and "Unfreeze track" or "Freeze track"
                if tr.ancestor_muted then mute_tip = mute_tip .. "\nMuted by folder ancestor: " .. tostring(tr.ancestor_muted_name or "Parent") end
                if tr.ancestor_soloed then solo_tip = solo_tip .. "\nSolo affected by folder ancestor: " .. tostring(tr.ancestor_soloed_name or "Parent") end
                local controls = {
                    { id = "##pin_btn", action = "pin", icon = "pin", width = control_size, x = control_left_x, active = node_is_pinned, on = 0xD7B95DFF, off = 0x4A4A4AFF, tip = node_is_pinned and "Unpin node" or "Pin node" },
                    { id = "##schema_btn", action = "schema", icon = "schema", width = control_size, x = control_left_x + control_size + control_gap, active = PB.fx_schema_open_guid == g, on = 0x6FB6D8FF, off = 0x4A4A4AFF, tip = PB.fx_schema_open_guid == g and "Hide FX chain schema" or "Show FX chain schema" },
                    { id = "##mute_btn", action = "mute", label = "M", width = control_size, x = control_right_x, active = mute_on, on = 0xC94FB0FF, off = 0x4A4A4AFF, tip = mute_tip, inherited_outline = tr.ancestor_muted and 0xFF5555FF or nil, inherited_outline2 = (tr.ancestor_muted and mute_on) and 0xFF9999FF or nil },
                    { id = "##solo_btn", action = "solo", label = "S", width = control_size, x = control_right_x + control_size + control_gap, active = solo_on, on = 0xCCBB33FF, off = 0x4A4A4AFF, tip = solo_tip, inherited_outline = tr.ancestor_soloed and 0xFFE066FF or nil, inherited_outline2 = (tr.ancestor_soloed and solo_on) and 0xFFF0AAFF or nil },
                    { id = "##arm_btn", action = "arm", label = "R", width = control_size, x = control_right_x + (control_size + control_gap) * 2, active = arm_on, on = 0xE05050FF, off = 0x4A4A4AFF, tip = arm_tip },
                    { id = "##freeze_btn", action = "freeze", label = "F", width = control_size, x = control_right_x + (control_size + control_gap) * 3, active = freeze_on, on = 0x4488CCFF, off = 0x4A4A4AFF, tip = freeze_tip }
                }
                for ci = 1, #controls do
                    local ctrl = controls[ci]
                    local ctrl_w = ctrl.width or control_size
                    local bx1 = ctrl.x
                    local by1 = control_y
                    local bx2 = bx1 + ctrl_w
                    local by2 = by1 + control_size
                    local bg_col = ctrl.active and ctrl.on or body_col
                    if not in_solo_focus then bg_col = ctrl.active and 0x777777CC or body_col end
                    r.ImGui_DrawList_AddRectFilled(draw_list, bx1, by1, bx2, by2, bg_col, 3)
                    r.ImGui_DrawList_AddRect(draw_list, bx1, by1, bx2, by2, 0x000000AA, 3)
                    if ctrl.inherited_outline then
                        r.ImGui_DrawList_AddRect(draw_list, bx1 - 1, by1 - 1, bx2 + 1, by2 + 1, ctrl.inherited_outline, 4, nil, 2)
                    end
                    if ctrl.inherited_outline2 then
                        r.ImGui_DrawList_AddRect(draw_list, bx1 - 3, by1 - 3, bx2 + 3, by2 + 3, ctrl.inherited_outline2, 5, nil, 1)
                    end
                    if ctrl.icon == "pin" then
                        PatchbayDrawPinSymbol(draw_list, bx1, by1, bx2, by2, ctrl.active and 0xFFE080FF or 0xFFFFFFFF)
                    elseif ctrl.icon == "schema" then
                        PatchbayDrawSchemaSymbol(draw_list, bx1, by1, bx2, by2, ctrl.active and 0xD7F4FFFF or 0xFFFFFFFF)
                    else
                        local tw = r.ImGui_CalcTextSize(ctx, ctrl.label)
                        r.ImGui_DrawList_AddText(draw_list, bx1 + ((ctrl_w - tw) * 0.5), by1 + ((control_size - 12) * 0.5), 0xFFFFFFFF, ctrl.label)
                    end
                    if r.ImGui_SetNextItemAllowOverlap then r.ImGui_SetNextItemAllowOverlap(ctx) end
                    r.ImGui_SetCursorScreenPos(ctx, bx1, by1)
                    r.ImGui_InvisibleButton(ctx, ctrl.id, ctrl_w, control_size)
                    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, ctrl.tip) end
                    if r.ImGui_IsItemClicked(ctx, 0) then
                        if ctrl.action == "pin" then
                            BatchSetPinned({ { track = tr.track, guid = g, name = tr.name } }, not node_is_pinned)
                        elseif ctrl.action == "schema" then
                            if PB.fx_schema_open_guid == g then
                                PB.fx_schema_open_guid = nil
                            else
                                PB.fx_schema_open_guid = g
                            end
                        elseif ctrl.action == "mute" and not all_locked then
                            BatchSetMute(GetPatchbayControlTargetTracks(tr.track, g, tr.name), not mute_on)
                        elseif ctrl.action == "solo" and not all_locked then
                            BatchSetSolo(GetPatchbayControlTargetTracks(tr.track, g, tr.name), not solo_on)
                        elseif ctrl.action == "arm" and not all_locked then
                            BatchSetRecordArm(GetPatchbayControlTargetTracks(tr.track, g, tr.name), not arm_on)
                        elseif ctrl.action == "freeze" and not all_locked then
                            BatchSetFreeze(GetPatchbayControlTargetTracks(tr.track, g, tr.name), not freeze_on)
                        end
                    end
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
            local folder_x, folder_y = PinPos(g, "bottom")
            local pin_r = PIN_R * canvas_zoom
            if pin_r < 4 then pin_r = 4 end

            r.ImGui_DrawList_AddCircleFilled(draw_list, in_x, in_y, pin_r, 0x88CCFFFF)
            r.ImGui_DrawList_AddCircle(draw_list, in_x, in_y, pin_r, 0x000000FF, nil, 1)
            if not is_master_node then
                r.ImGui_DrawList_AddCircleFilled(draw_list, out_x, out_y, pin_r, 0xFFCC88FF)
                r.ImGui_DrawList_AddCircle(draw_list, out_x, out_y, pin_r, 0x000000FF, nil, 1)
                local folder_pin_enabled = CanStartFolderPin(tr)
                local folder_pin_col = folder_pin_enabled and 0x66CC88FF or 0x3B5A46AA
                r.ImGui_DrawList_AddCircleFilled(draw_list, folder_x, folder_y, pin_r * 0.82, folder_pin_col)
                r.ImGui_DrawList_AddCircle(draw_list, folder_x, folder_y, pin_r * 0.82, 0x000000FF, nil, 1)
            end

            r.ImGui_PushID(ctx, "pins_" .. g)

            r.ImGui_SetCursorScreenPos(ctx, in_x - pin_r, in_y - pin_r)
            r.ImGui_InvisibleButton(ctx, "##pin_in", pin_r * 2, pin_r * 2)
            if not fx_schema_blocks_mouse and r.ImGui_IsItemHovered(ctx) then
                hovered_input_guid = g
                r.ImGui_DrawList_AddCircle(draw_list, in_x, in_y, pin_r + 2, 0xFFFFFFFF, nil, 2)
                r.ImGui_SetTooltip(ctx, PatchbayBuildPinTooltip(tr, "in", tracks, guid_to) .. "\nRight-click: route settings")
            end

            if not is_master_node then
                r.ImGui_SetCursorScreenPos(ctx, out_x - pin_r, out_y - pin_r)
                r.ImGui_InvisibleButton(ctx, "##pin_out", pin_r * 2, pin_r * 2)
                if not fx_schema_blocks_mouse and r.ImGui_IsItemHovered(ctx) then
                    r.ImGui_DrawList_AddCircle(draw_list, out_x, out_y, pin_r + 2, 0xFFFFFFFF, nil, 2)
                    r.ImGui_SetTooltip(ctx, PatchbayBuildPinTooltip(tr, "out", tracks, guid_to) .. "\nRight-click: route settings")
                end
                if not fx_schema_blocks_mouse and r.ImGui_IsItemActive(ctx) and not all_locked then
                    if not pending_connection and not pending_folder_connection then
                        pending_connection = { src = tr.track, src_guid = g }
                    end
                end

                r.ImGui_SetCursorScreenPos(ctx, folder_x - pin_r, folder_y - pin_r)
                r.ImGui_InvisibleButton(ctx, "##pin_folder", pin_r * 2, pin_r * 2)
                if not fx_schema_blocks_mouse and r.ImGui_IsItemHovered(ctx) then
                    local folder_pin_enabled = CanStartFolderPin(tr)
                    local hcol = folder_pin_enabled and 0xD8FFE0FF or 0x777777FF
                    r.ImGui_DrawList_AddCircle(draw_list, folder_x, folder_y, pin_r + 2, hcol, nil, 2)
                    r.ImGui_SetTooltip(ctx, PatchbayBuildPinTooltip(tr, "folder", tracks, guid_to, folder_pin_enabled, all_locked))
                end
                if not fx_schema_blocks_mouse and r.ImGui_IsItemActive(ctx) and CanStartFolderPin(tr) then
                    if not pending_folder_connection and not pending_connection then
                        pending_folder_connection = { parent = tr.track, parent_guid = g }
                    end
                end
            end

            r.ImGui_PopID(ctx)
        end
    end

    if fx_schema_layout then PatchbayFxSchemaRender(ctx, draw_list, fx_schema_layout) end

    if pending_folder_connection then
        local sx, sy = PinPos(pending_folder_connection.parent_guid, "bottom")
        local hovered_folder_target = nil
        local hovered_folder_valid = false
        local folder_drag_targets = nil
        local parent = FindTrackByGuidLocal(pending_folder_connection.parent_guid)
        for i = 1, #tracks do
            local target = tracks[i]
            if target.guid ~= pending_folder_connection.parent_guid and not target.is_master then
                local x1, y1, x2, y2 = NodeRect(target.guid)
                if x1 and mx >= x1 and mx <= x2 and my >= y1 and my <= y2 then
                    hovered_folder_target = target
                    if pb_selected_set[target.guid] then
                        folder_drag_targets = GetSelectedPatchbayTracks()
                    else
                        folder_drag_targets = { { track = target.track, guid = target.guid, name = target.name } }
                    end
                    local ok = PrepareSimpleFolderChildren(parent, folder_drag_targets)
                    hovered_folder_valid = ok ~= nil
                    break
                end
            end
        end
        local folder_link_style = GetCableOverlayStyle("folder_links", cfg)
        local target_x, target_y = mx, my
        local color = folder_link_style.color
        local thickness = math.max(1.0, folder_link_style.thickness * canvas_zoom)
        if hovered_folder_target then
            local x1, y1, x2, y2 = NodeRect(hovered_folder_target.guid)
            if x1 then
                target_x = (x1 + x2) * 0.5
                target_y = y1
                color = hovered_folder_valid and folder_link_style.hover or 0x777777AA
                r.ImGui_DrawList_AddRect(draw_list, x1, y1, x2, y2, hovered_folder_valid and 0x88FFAAFF or 0x777777AA, 6, nil, 2)
            end
        end
        if sx then
            r.ImGui_DrawList_AddLine(draw_list, sx, sy, target_x, target_y, color, thickness)
            r.ImGui_DrawList_AddCircleFilled(draw_list, target_x, target_y, math.max(2.5, 3.0 * canvas_zoom), color)
        end
        if r.ImGui_IsMouseReleased(ctx, 0) then
            if hovered_folder_target and hovered_folder_valid and parent and r.ValidatePtr(parent, "MediaTrack*") then
                AssignSelectedTracksAsFolderChildren(parent, folder_drag_targets)
            end
            pending_folder_connection = nil
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
                local selected_sources = nil
                if pb_selected_set[pending_connection.src_guid] then
                    selected_sources = GetSelectedPatchbayTracks()
                end
                if hovered_input_guid == MASTER_GUID and not all_locked then
                    if not selected_sources or #selected_sources == 0 then
                        selected_sources = { { track = pending_connection.src, guid = pending_connection.src_guid } }
                    end
                    local changes = 0
                    r.Undo_BeginBlock()
                    r.PreventUIRefresh(1)
                    for i = 1, #selected_sources do
                        local src = selected_sources[i].track
                        if src and r.ValidatePtr(src, "MediaTrack*") and r.GetMediaTrackInfo_Value(src, "B_MAINSEND") ~= 1 then
                            r.SetMediaTrackInfo_Value(src, "B_MAINSEND", 1)
                            changes = changes + 1
                        end
                    end
                    r.PreventUIRefresh(-1)
                    if changes > 0 then
                        r.TrackList_AdjustWindows(false)
                        r.UpdateArrange()
                        r.Undo_EndBlock("Patchbay: enable selected main sends", -1)
                    else
                        r.Undo_EndBlock("Patchbay: enable selected main sends (no changes)", -1)
                    end
                elseif not all_locked then
                    local dst_track = nil
                    for i = 1, #tracks do
                        if tracks[i].guid == hovered_input_guid then dst_track = tracks[i].track; break end
                    end
                    if dst_track then
                        if selected_sources and #selected_sources > 0 then
                            BatchConnectSelectedToDestination(selected_sources, dst_track)
                        elseif pb_selected_set[hovered_input_guid] then
                            BatchConnectTargetToSelected(pending_connection.src, GetSelectedPatchbayTracks())
                        else
                            BatchConnectSelectedToDestination({ { track = pending_connection.src, guid = pending_connection.src_guid } }, dst_track)
                        end
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
            else
                for i = 1, #tracks do
                    local g2 = tracks[i].guid
                    local nx1, ny1, nx2, ny2 = NodeRect(g2)
                    if nx1 and not (nx2 < rx1 or nx1 > rx2 or ny2 < ry1 or ny1 > ry2) then
                        pb_selected_set[g2] = true
                    end
                end
            end
            PatchbaySyncSelectedSetToTCP(nil)
            pb_rubber_additive = false
            pb_rubber_active = false
        end
    end

    if r.ImGui_IsMouseReleased(ctx, 0) then
        pb_press_guid = nil
        pb_press_dragged = false
        pending_folder_connection = nil
        if dragging_node_guid then
            if cfg.patchbay_snap_to_grid == true then
                SnapMovedNodesToGrid(dragging_node_guid)
            end
            if cfg.patchbay_prevent_overlap ~= false then
                ResolveMovedNodesOverlap(dragging_node_guid, tracks)
            end
            dragging_node_guid = nil
            SaveLayout()
        end
    end

    if layout_dirty and (r.time_precise() - last_save_time) > 2.0 and dragging_node_guid == nil then
        SaveLayout()
    end

    RenderNotesPinnedOverlay(ctx, origin_x, origin_y, avail_w, avail_h)

    r.ImGui_EndChild(ctx)
    do
        local hint = "Left-click node = select  |  Drag node = move  |  Drag side pin = connect  |  Drag bottom pin = folder child  |  Right-drag empty = select (Shift = add)  |  Wheel = zoom"
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
    if request_open_pin_popup then
        r.ImGui_OpenPopup(ctx, "PatchbayPinPopup")
    end
    if request_open_node_popup then
        r.ImGui_OpenPopup(ctx, "PatchbayNodePopup")
    end
    RenderPinConnectionPopup()
    if PB.open_send_popup_from_pin then
        r.ImGui_OpenPopup(ctx, "PatchbaySendPopup")
        PB.open_send_popup_from_pin = false
    end
    RenderRightClickPopup()
    RenderNodePopup()
    RenderCableShopWindow()
    RenderViewHelpWindow()
end
