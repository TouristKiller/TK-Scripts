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
PB.paranormal_command_id = nil
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

-- Two nodes joined by a cable: the view's own vocabulary, so it does not read
-- as a second version of the schema strip beside it.
function PatchbayDrawFxNodeSymbol(draw_list, x1, y1, x2, y2, col)
    local w, h = x2 - x1, y2 - y1
    local rad = math.max(1.6, w * 0.15)
    local lx = x1 + w * 0.26
    local rx = x1 + w * 0.74
    local ty = y1 + h * 0.32
    local by = y1 + h * 0.68
    r.ImGui_DrawList_AddLine(draw_list, lx + rad, ty, rx - rad, ty, col, 1.2)
    r.ImGui_DrawList_AddLine(draw_list, lx + rad, by, rx - rad, by, col, 1.2)
    r.ImGui_DrawList_AddCircleFilled(draw_list, lx, ty, rad, col)
    r.ImGui_DrawList_AddCircle(draw_list, rx, ty, rad, col, 0, 1.2)
    r.ImGui_DrawList_AddCircle(draw_list, lx, by, rad, col, 0, 1.2)
    r.ImGui_DrawList_AddCircleFilled(draw_list, rx, by, rad, col)
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

-- TK Notes and the Workbench Notes module share one store now: a per-track
-- P_EXT blob holding the whole note document. The two legacy namespaces read
-- above are only still written by older installs, so a note edited today lives
-- here and nowhere else.
local NOTES_SHARED_TRACK_PEXT = "TK_NOTES_SHARED"
local NOTES_B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

function NotesBase64Decode(s)
    if not s or s == "" then return "" end
    s = s:gsub("[^" .. NOTES_B64 .. "=]", ""):gsub("=+$", "")
    local out, acc, bits = {}, 0, 0
    for i = 1, #s do
        local idx = NOTES_B64:find(s:sub(i, i), 1, true)
        if idx then
            acc = acc * 64 + (idx - 1)
            bits = bits + 6
            if bits >= 8 then
                bits = bits - 8
                out[#out + 1] = string.char(math.floor(acc / (2 ^ bits)) % 256)
                acc = acc % (2 ^ bits)
            end
        end
    end
    return table.concat(out)
end

function NotesReadShared(track)
    if not track or not r.ValidatePtr(track, "MediaTrack*") then return "" end
    if type(r.GetSetMediaTrackInfo_String) ~= "function" then return "" end
    local ok, value = r.GetSetMediaTrackInfo_String(track, "P_EXT:" .. NOTES_SHARED_TRACK_PEXT, "", false)
    if not ok or not value or value == "" then return "" end
    local first = value:sub(1, 1)
    if first == "{" or first == "[" then return value end
    return NotesBase64Decode(value)
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

function NotesBlocksText(blocks)
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

function NotesWorkbenchText(guid)
    local raw = NotesReadWorkbench(guid .. "::blocks")
    if raw == "" then return "" end
    local blocks = NotesJsonDecode(raw)
    if type(blocks) ~= "table" then return "" end
    return NotesBlocksText(blocks)
end

function NotesSharedText(track)
    local raw = NotesReadShared(track)
    if raw == "" then return "" end
    local doc = NotesJsonDecode(raw)
    if type(doc) ~= "table" then return "" end
    local blocks = doc.blocks
    if type(blocks) ~= "table" then return "" end
    return NotesBlocksText(blocks)
end

function NotesStripMarkup(s)
    if not s or s == "" then return s end
    s = s:gsub("%*%*(.-)%*%*", "%1")
    s = s:gsub("__(.-)__", "%1")
    return s
end

function NotesGetText(target, source)
    local guid = type(target) == "table" and target.guid or target
    local track = type(target) == "table" and target.track or nil
    if not guid or guid == "" then return "" end
    -- The shared store is where both apps write today, so it answers first and
    -- the source buttons only pick which legacy namespace to fall back on, for a
    -- note that was never reopened after the two stores were joined.
    local shared = NotesSharedText(track)
    if shared ~= "" then return NotesStripMarkup(shared) end
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
        local text = NotesGetText(target, source)
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
    local para_text_w = PatchbayFxSchemaTextWidth(ctx, "Para")
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
    local para_tw = PatchbayFxSchemaTextWidth(ctx, "Para")
    r.ImGui_DrawList_AddText(draw_list, btn_x + ((btn_w - para_tw) * 0.5),
        btn_y + ((btn_h - text_h) * 0.5), btn_text, "Para")
    r.ImGui_PushID(ctx, "fx_schema_popover")
    if r.ImGui_SetNextItemAllowOverlap then r.ImGui_SetNextItemAllowOverlap(ctx) end
    r.ImGui_SetCursorScreenPos(ctx, layout.x, layout.y)
    r.ImGui_InvisibleButton(ctx, "##fx_schema_panel", layout.w, layout.h)
    -- The PFX button overlaps this panel and is submitted after it, so its own
    -- region is excluded by hand rather than relying on ImGui to resolve two
    -- overlapping items within the same frame.
    local pmx, pmy = r.ImGui_GetMousePos(ctx)
    local on_para = pmx >= btn_x and pmx <= btn_x + btn_w and pmy >= btn_y and pmy <= btn_y + btn_h
    if r.ImGui_IsItemHovered(ctx) and not on_para then
        r.ImGui_SetTooltip(ctx, "Open the FX node view for this track")
    end
    if r.ImGui_IsItemClicked(ctx, 0) and not on_para and layout.track
        and r.ValidatePtr(layout.track, "MediaTrack*") then
        PatchbayFxNodeEnter(r.GetTrackGUID(layout.track))
    end
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


function RemovePatchbayCableTargetNoUndo(cable)
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

function RemovePatchbayCable(cable)
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

function RemoveSelectedPatchbayCableRelations(cable)
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

-- ===========================================================================
-- FX NODE VIEW
--
-- Dive into one track and see its FX chain the way Patchbay sees everything
-- else: nodes with pins, joined by cables. Deliberately NOT a horizontal strip
-- of boxes with bus bars for parallel -- that is Paranormal FX's vormtaal, and
-- the abandoned TKFXBPatchbay_FXCHAIN prototype looked like a copy of it.
--
-- What a cable means here is the point. TK_Probe_FX_Pin_Mappings established on
-- REAPER 7.75 that GetIOSize and GetPinMappings answer for FX inside containers
-- at depth 1 and 2, and that pin mappings are one flat channel space, so a node
-- can show its real channel layout -- a ReaComp's detector inputs sitting on
-- channels 3 and 4 are visible here without opening anything.
--
-- This is the first increment: read-only. Moving, adding and deleting FX is the
-- next one, and the mutation layer it needs already exists in the prototype
-- (PatchbayMoveFxSerial and friends) untouched by anything visual.
--
-- All state lives on PB. The file sits a handful of locals under Lua's 200-per-
-- chunk ceiling, so nothing here may introduce a top-level local.
-- ===========================================================================

PB.fx_view_guid = nil        -- track we are inside; nil means the track graph
PB.fx_view_off_x = 0
PB.fx_view_off_y = 0
PB.fx_view_zoom = 1.0
PB.fx_view_sel_api = nil
PB.fx_view_fit_pending = false
PB.fx_view_ctx_api = nil
PB.fx_view_ctx_name = nil
PB.fx_view_ctx_open = false
PB.fx_view_rename_api = nil
PB.fx_view_rename_text = ""
PB.fx_view_cache = nil
PB.fx_view_cache_key = nil
PB.fx_view_cache_time = 0
PB.fx_view_drag = nil
PB.fx_view_ctx_is_container = false

-- Reading the chain costs a GetIOSize plus a GetPinMappings per pin per FX, so
-- a twenty-plugin track is a few hundred API calls -- too many to pay sixty
-- times a second for a picture that changes when the user does something. The
-- cache is dropped outright by every mutation below, and otherwise refreshes on
-- a short timer so a change made in REAPER's own FX window still shows up.
function PatchbayFxNodeInvalidate()
    PB.fx_view_cache = nil
    PB.fx_view_cache_key = nil
end

-- Custom folders are edited in TK FX BROWSER while this window is open, so the
-- browse data is dropped whenever the add popup is opened afresh rather than
-- being held for the life of the session.
function PatchbayFxNodeInvalidateBrowse()
    PB.fx_view_cat_groups = nil
    PB.fx_view_custom_folders = nil
end

function PatchbayFxNodeCached(track, dims)
    local key = string.format("%s|%d|%.3f", tostring(PB.fx_view_guid),
        r.TrackFX_GetCount(track) or 0, dims.zoom)
    local now = r.time_precise()
    if PB.fx_view_cache and PB.fx_view_cache_key == key and (now - PB.fx_view_cache_time) < 0.25 then
        return PB.fx_view_cache
    end
    PB.fx_view_cache = PatchbayFxNodeBuild(track, dims)
    PB.fx_view_cache_key = key
    PB.fx_view_cache_time = now
    return PB.fx_view_cache
end

-- ---------------------------------------------------------------------------
-- Folding a container shut
--
-- Not a global "show containers inline / dive into them" switch: which way you
-- want it differs per container, not per session. The rack with twelve plugins
-- is in the way; the one with two you want to see. So it folds per container
-- and the choice is remembered.
--
-- Keyed on the FX GUID, never on the address. An api_id changes the moment
-- anything before it moves, so a fold remembered by address would reappear on
-- whichever plugin happened to slide into that slot.
--
-- Stored in its own project key rather than in the Patchbay layout string.
-- That layout is read by every project that has ever been opened with this
-- script, and a mistake in its encoder would take node positions with it; a
-- mistake here costs a few folded containers.
-- ---------------------------------------------------------------------------

PB.fx_view_collapsed = nil
PB.fx_view_collapsed_guid = nil

function PatchbayFxNodeFoldKey(track)
    if not track or not r.ValidatePtr(track, "MediaTrack*") then return nil end
    return r.GetTrackGUID(track)
end

function PatchbayFxNodeLoadFolds(track)
    local guid = PatchbayFxNodeFoldKey(track)
    if not guid then return {} end
    if PB.fx_view_collapsed and PB.fx_view_collapsed_guid == guid then
        return PB.fx_view_collapsed
    end
    local folds = {}
    local _, raw = r.GetProjExtState(0, "TK_FXB_PATCHBAY", "fxfold::" .. guid)
    for line in tostring(raw or ""):gmatch("([^\n]+)") do
        if line ~= "" then folds[line] = true end
    end
    PB.fx_view_collapsed = folds
    PB.fx_view_collapsed_guid = guid
    return folds
end

function PatchbayFxNodeSaveFolds(track)
    local guid = PatchbayFxNodeFoldKey(track)
    if not guid or not PB.fx_view_collapsed then return end
    local lines = {}
    for fxguid, folded in pairs(PB.fx_view_collapsed) do
        if folded then lines[#lines + 1] = fxguid end
    end
    table.sort(lines)
    r.SetProjExtState(0, "TK_FXB_PATCHBAY", "fxfold::" .. guid, table.concat(lines, "\n"))
end

function PatchbayFxNodeIsFolded(track, fxguid)
    if not fxguid or fxguid == "" then return false end
    local folds = PatchbayFxNodeLoadFolds(track)
    return folds[fxguid] == true
end

function PatchbayFxNodeToggleFold(track, fxguid)
    if not fxguid or fxguid == "" then return end
    local folds = PatchbayFxNodeLoadFolds(track)
    folds[fxguid] = not folds[fxguid] or nil
    PatchbayFxNodeSaveFolds(track)
    PatchbayFxNodeInvalidate()
end

-- The triangle in a container's header. Sized off the header so it stays
-- clickable when zoomed out.
function PatchbayFxNodeFoldSpot(fx, dims)
    local size = math.max(4, dims.head_h * 0.34)
    return fx.x + dims.text_pad * 0.6 + size * 0.5, fx.y + dims.head_h * 0.5, size
end

function PatchbayFxNodeDrawFold(dl, fx, dims, col)
    local cx, cy, size = PatchbayFxNodeFoldSpot(fx, dims)
    if fx.folded then
        -- pointing right: there is more behind this
        r.ImGui_DrawList_AddTriangleFilled(dl,
            cx - size * 0.4, cy - size * 0.6,
            cx - size * 0.4, cy + size * 0.6,
            cx + size * 0.6, cy, col)
    else
        r.ImGui_DrawList_AddTriangleFilled(dl,
            cx - size * 0.6, cy - size * 0.4,
            cx + size * 0.6, cy - size * 0.4,
            cx, cy + size * 0.6, col)
    end
end

-- ---------------------------------------------------------------------------
-- How a node looks
--
-- Three things, all of them reading from data that is already here:
--
--  1. Colour comes from the plugin's CATEGORY in Sexan's own category file.
--     Blue-blue-amber-teal reads as EQ, EQ, compressor, reverb without a single
--     label being read. Colour that carries meaning, not colour as decoration.
--  2. A node is a coloured header with the clean name, over a darker body that
--     holds the pins and a small format badge. "VST3: FabFilter Pro-Q 3"
--     becomes Pro-Q 3 with a VST3 chip, which is both prettier and shorter.
--  3. Cables say something: dimmed and thin into a bypassed plugin, heavier
--     when more than two channels run through them.
--
-- The old look came from PatchbayFxSchemaPalette, which is built for the schema
-- popover: it forces monochrome and assumes it is drawing on its own light
-- panel. That is why everything was a white box with near-black text.
-- ---------------------------------------------------------------------------

PB.fx_view_cat_of = nil

-- Global on purpose: this file sits a few slots under Lua's 200-local ceiling
-- per chunk, and a helper does not need to spend one of them.
function PatchbayFxNodeHsv(h, s, v, a)
    h = (h % 360) / 60
    local i = math.floor(h)
    local f = h - i
    local p, q, t = v * (1 - s), v * (1 - s * f), v * (1 - s * (1 - f))
    local rr, gg, bb
    if i == 0 then rr, gg, bb = v, t, p
    elseif i == 1 then rr, gg, bb = q, v, p
    elseif i == 2 then rr, gg, bb = p, v, t
    elseif i == 3 then rr, gg, bb = p, q, v
    elseif i == 4 then rr, gg, bb = t, p, v
    else rr, gg, bb = v, p, q end
    return (math.floor(rr * 255) << 24) | (math.floor(gg * 255) << 16)
        | (math.floor(bb * 255) << 8) | math.floor((a or 1) * 255)
end

-- Deliberate hues for the families you actually reach for; anything else is
-- hashed to a stable hue so an unknown category still looks like itself every
-- time rather than falling back to grey.
function PatchbayFxNodeCatKnown(cat)
    return PatchbayFxNodeCatHue(cat, true) ~= nil
end

-- `strict` asks only about the deliberate hues, not the hashed fallback: that
-- is what lets a folder called "FX REVERB" outrank one called "Z_SAIKE".
function PatchbayFxNodeCatHue(cat, strict)
    if not cat or cat == "" then return nil end
    local key = cat:lower()
    local known = {
        eq = 205, filter = 192, dynamics = 40, compressor = 38, ["channel strip"] = 48,
        limiter = 25, gate = 55, expander = 55, reverb = 175, delay = 160, echo = 160,
        modulation = 282, chorus = 272, flanger = 262, phaser = 292, tremolo = 300,
        distortion = 12, saturation = 28, ["bit crusher"] = 8, amp = 18,
        pitch = 322, harmony = 330, vocal = 340, ["de-esser"] = 348,
        analyzer = 218, meter = 212, utility = 208, tools = 208,
        -- Added after counting what the real collection actually produces:
        -- these came back as hashed colours while plainly being categories.
        sidechain = 135, duck = 135, ducking = 135,
        spatial = 152, spacial = 152, pan = 152, panner = 152, width = 152,
        clipper = 22, clip = 22, gain = 200, trim = 200,
        ringmod = 300, vocoder = 310, spectrum = 218, tuner = 232,
        generator = 266, keys = 118, piano = 112, organ = 124,
        orchestral = 100, strings = 96, brass = 88, theory = 250,
        rack = 208, multiband = 42, transient = 36, exciter = 26,
        mastering = 45, imaging = 152, stereo = 152, surround = 142,
        instrument = 118, synth = 128, sampler = 108, bass = 62,
        -- Both spellings: the match is substring, so a label "Drum" never
        -- finds the word "drums" -- it only works the other way round.
        drum = 6, drums = 6,
        guitar = 20, tape = 33, lofi = 14, noise = 200, restoration = 186,
    }
    if known[key] then return known[key] end
    for word, hue in pairs(known) do
        if key:find(word, 1, true) then return hue end
    end
    if strict then return nil end
    local hash = 0
    for i = 1, #key do hash = (hash * 31 + key:byte(i)) % 360 end
    return hash
end

-- "03 FX" -> "FX", "FX REVERB" -> "REVERB", "Z_SAIKE" -> "SAIKE". Folder names
-- carry ordering prefixes and grouping words that are not part of what the
-- plugin IS.
-- Sexan's CATEGORY buckets are written "Reverb"; folder names are shouted
-- "REVERB". Both resolve to the same hue -- the lookup lowercases -- but they
-- printed as two different chips on adjacent nodes. Twelve pairs in this
-- collection differed by nothing but case.
--
-- Acronyms are spelled out rather than detected: a rule like "keep short
-- all-caps runs" would preserve U-HE and title-case u-he, leaving the very
-- duplicate this is meant to remove.
function PatchbayFxNodeTitleCat(name)
    local acronyms = {
        EQ = true, FX = true, JS = true, MIDI = true, LFO = true, VU = true,
        RMS = true, DI = true, AM = true, FM = true, MS = true, IR = true,
        AI = true, IK = true
    }
    local out = tostring(name or ""):gsub("%a+", function(word)
        local up = word:upper()
        if acronyms[up] then return up end
        return word:sub(1, 1):upper() .. word:sub(2):lower()
    end)
    return out
end

function PatchbayFxNodeCleanCat(name)
    local out = tostring(name or "")
    out = out:gsub("^%s*%d+[%s_%-]*", "")
    out = out:gsub("^[Zz]_", "")
    out = out:gsub("^FX%s+", "")
    out = out:gsub("^%s*(.-)%s*$", "%1")
    if out == "" then out = tostring(name or "") end
    return PatchbayFxNodeTitleCat(out)
end

-- Sexan's CATEGORY group is filled from plugin metadata, which JS effects do
-- not carry -- "JS: Abyss Reverb (Saike)" is in FOLDERS / FX REVERB and in the
-- user's own folders, but nowhere in CATEGORY. So three sources are consulted
-- in order of authority, and a plugin already placed is never re-placed:
--
--   1. CATEGORY          -- what the plugin says about itself
--   2. the user's own custom folders  -- what THEY decided it is
--   3. Sexan's FOLDERS   -- the browser's folders, same idea
--
-- Within 2 and 3, a folder whose name maps to a hue we know beats one that does
-- not: "FX REVERB" is worth more than "Z_SAIKE", and both contain this plugin.
function PatchbayFxNodeCategoryMap()
    if PB.fx_view_cat_of then return PB.fx_view_cat_of end
    local map = {}
    local groups = PatchbayFxNodeLoadCategories(false)

    local function place(fxname, label)
        if not fxname or fxname == "" or not label or label == "" then return end
        local clean = PatchbayFxNodeCleanCat(label)
        local have = map[fxname]
        if have == nil then map[fxname] = clean return end
        -- Already placed by a weaker source: upgrade only from unknown to known.
        if PatchbayFxNodeCatKnown(have) then return end
        if PatchbayFxNodeCatKnown(clean) then map[fxname] = clean end
    end

    if groups then
        for _, group in ipairs(groups) do
            if group.name == "CATEGORY" then
                for _, bucket in ipairs(group.buckets) do
                    for _, fxname in ipairs(bucket.fx) do
                        if map[fxname] == nil then
                            map[fxname] = PatchbayFxNodeTitleCat(bucket.name)
                        end
                    end
                end
            end
        end
    end

    local function walk_folders(list)
        for _, entry in ipairs(list or {}) do
            for _, fxname in ipairs(entry.fx or {}) do place(fxname, entry.name) end
            if entry.subs then walk_folders(entry.subs) end
        end
    end
    walk_folders(PatchbayFxNodeLoadCustomFolders(false))

    if groups then
        for _, group in ipairs(groups) do
            if group.name == "FOLDERS" then
                for _, bucket in ipairs(group.buckets) do
                    for _, fxname in ipairs(bucket.fx) do place(fxname, bucket.name) end
                end
            end
        end
    end

    PB.fx_view_cat_of = map
    return map
end

-- An instrument is the most important thing a node can be, and REAPER spells it
-- out in the prefix: VST3i, CLAPi, AUi. Sexan files them under INSTRUMENTS
-- rather than in CATEGORY, so without this they would fall through to a hashed
-- hue and read as "some effect".
function PatchbayFxNodeIsInstrument(full_name)
    if not full_name then return false end
    local prefix = full_name:match("^(%a[%w]*):")
    return prefix ~= nil and prefix:sub(-1) == "i"
end

function PatchbayFxNodeCategoryOf(full_name)
    if not full_name or full_name == "" then return nil end
    local hit = PatchbayFxNodeCategoryMap()[full_name]
    if hit then return hit end
    if PatchbayFxNodeIsInstrument(full_name) then return "Instrument" end
    return nil
end

-- "VST3: FabFilter Pro-Q 3 (FabFilter)" -> "VST3"
function PatchbayFxNodeFormatBadge(full_name)
    if not full_name then return nil end
    local prefix = full_name:match("^(%a[%w]*):")
    if not prefix then return nil end
    return prefix:upper()
end

-- bg, border, text for the header; bg for the body.
function PatchbayFxNodeSkin(fx)
    local light = PatchbayFxSchemaThemeIsLight()
    local hue = PatchbayFxNodeCatHue(fx and fx.category)
    local is_container = fx and fx.fx_type == "Container"
    if is_container and not hue then hue = 150 end
    if not hue then hue = 210 end

    local sat = is_container and 0.30 or 0.52
    if fx and fx.offline then
        hue, sat = 0, 0.62
    elseif fx and not fx.enabled then
        sat = 0.05
    end

    if light then
        return PatchbayFxNodeHsv(hue, sat * 0.75, 0.86, 1.0),   -- header
               PatchbayFxNodeHsv(hue, sat * 0.20, 0.97, 1.0),   -- body
               PatchbayFxNodeHsv(hue, sat * 0.85, 0.55, 1.0),   -- border
               0x1A1A1AFF                                       -- text
    end
    return PatchbayFxNodeHsv(hue, sat, 0.46, 1.0),
           PatchbayFxNodeHsv(hue, sat * 0.45, 0.14, 0.98),
           PatchbayFxNodeHsv(hue, sat * 0.80, 0.72, 1.0),
           (fx and not fx.enabled) and 0x9AA0A8FF or 0xF0F3F7FF
end

-- Cables. A run into a bypassed plugin is thin and faint -- the signal goes
-- through untouched, and the picture should say so. More than two channels
-- makes it heavier.
function PatchbayFxNodeCableStyle(target_fx, base_col)
    local thickness = 1.7
    local col = base_col
    if target_fx then
        local ch = math.max(target_fx.pins and target_fx.pins.nin or 2, 2)
        if ch > 2 then thickness = thickness + math.min(1.6, (ch - 2) * 0.45) end
        if not target_fx.enabled or target_fx.offline then
            thickness = 1.1
            col = (col & 0xFFFFFF00) | 0x50
        end
    end
    return col, thickness
end

-- ---------------------------------------------------------------------------
-- Putting a node where you want it
--
-- One gesture, two outcomes, decided by where you let go:
--
--   released over a drop target  -> the chain is reordered (as before), and any
--                                   position this node had is dropped, because
--                                   the layout it was pinned against no longer
--                                   exists
--   released anywhere else       -> the node simply stays there
--
-- No modifier key, no second gesture to learn: the drop pads are lit while you
-- drag, so "in the chain" and "just somewhere" are visibly different targets.
--
-- Positions are stored per FX GUID, in content space divided by the zoom, so
-- they survive panning, zooming, and anything that renumbers the chain. They
-- live in their own project key -- never in the Patchbay layout string, which
-- every project depends on.
-- ---------------------------------------------------------------------------

PB.fx_view_pos = nil
PB.fx_view_pos_guid = nil

function PatchbayFxNodeLoadPositions(track)
    local guid = PatchbayFxNodeFoldKey(track)
    if not guid then return {} end
    if PB.fx_view_pos and PB.fx_view_pos_guid == guid then return PB.fx_view_pos end
    local out = {}
    local _, raw = r.GetProjExtState(0, "TK_FXB_PATCHBAY", "fxpos::" .. guid)
    for line in tostring(raw or ""):gmatch("([^\n]+)") do
        local fxguid, xs, ys = line:match("^(.-)|([^|]+)|([^|]+)$")
        local x, y = tonumber(xs or ""), tonumber(ys or "")
        if fxguid and fxguid ~= "" and x and y then out[fxguid] = { x = x, y = y } end
    end
    PB.fx_view_pos = out
    PB.fx_view_pos_guid = guid
    return out
end

function PatchbayFxNodeSavePositions(track)
    local guid = PatchbayFxNodeFoldKey(track)
    if not guid or not PB.fx_view_pos then return end
    local lines = {}
    for fxguid, p in pairs(PB.fx_view_pos) do
        if p and p.x and p.y then
            lines[#lines + 1] = string.format("%s|%.1f|%.1f", fxguid, p.x, p.y)
        end
    end
    table.sort(lines)
    r.SetProjExtState(0, "TK_FXB_PATCHBAY", "fxpos::" .. guid, table.concat(lines, "\n"))
end

function PatchbayFxNodeSetPosition(track, fxguid, x, y)
    if not fxguid or fxguid == "" then return end
    local positions = PatchbayFxNodeLoadPositions(track)
    positions[fxguid] = { x = x, y = y }
    PatchbayFxNodeSavePositions(track)
end

function PatchbayFxNodeClearPosition(track, fxguid)
    if not fxguid or fxguid == "" then return end
    local positions = PatchbayFxNodeLoadPositions(track)
    if positions[fxguid] == nil then return end
    positions[fxguid] = nil
    PatchbayFxNodeSavePositions(track)
end

function PatchbayFxNodeClearAllPositions(track)
    PB.fx_view_pos = {}
    PB.fx_view_pos_guid = PatchbayFxNodeFoldKey(track)
    PatchbayFxNodeSavePositions(track)
end

function PatchbayFxNodeHasPositions(track)
    local positions = PatchbayFxNodeLoadPositions(track)
    return next(positions) ~= nil
end

-- The IN and OUT boxes are part of the picture rather than furniture: on a
-- wide chain the useful place for the track's own connector is rarely hard
-- left and hard right of everything. They pin through the very same store the
-- nodes use, under two keys no FX can collide with -- REAPER's GUIDs are
-- always braced, so nothing beginning with an underscore can ever be one.
PATCHBAY_FX_EDGE_IN = "__edge_in__"
PATCHBAY_FX_EDGE_OUT = "__edge_out__"
PB.fx_view_edge_drag = nil

function PatchbayFxNodeEdgeRect(layout, which)
    if which == "in" then
        if not layout.edge_in_x then return nil end
        return layout.edge_in_x, layout.edge_in_y, layout.edge_w, layout.edge_h
    end
    if not layout.edge_out_x then return nil end
    return layout.edge_out_x, layout.edge_out_y, layout.edge_w, layout.edge_h
end

-- OUT first: if the two are dragged on top of each other, the one you grab is
-- the one drawn last, which is the one you can see.
function PatchbayFxNodeEdgeAt(layout, mx, my)
    for _, which in ipairs({ "out", "in" }) do
        local x, y, w, h = PatchbayFxNodeEdgeRect(layout, which)
        if x and y and mx >= x and mx <= x + w and my >= y and my <= y + h then
            return which
        end
    end
    return nil
end

-- Nothing may be pinned on top of something else. Same switch as the track
-- graph (Prevent overlap), same outward ring search, same step -- you learn
-- the behaviour once and it holds in both views.
--
-- It runs when you let go, not every frame: resolving continuously would make
-- a layout creep about on its own, and a node you put somewhere on purpose
-- has to stay there.
-- Its own setting, deliberately not the track graph's. Sharing one switch
-- read well on paper and was wrong in practice: turning overlap off for the
-- track canvas -- where tracks are arranged by hand and free placement is the
-- point -- silently turned it off in here too, with no way to have one without
-- the other. Default on, because a chain read left to right has an order and
-- boxes on top of each other hide it.
function PatchbayFxNodePreventOverlap()
    local cfg = GetConfig()
    return cfg == nil or cfg.patchbay_fx_node_overlap ~= false
end

function PatchbayFxNodePreventOverlapToggle()
    local cfg = GetConfig()
    if not cfg then return end
    cfg.patchbay_fx_node_overlap = not PatchbayFxNodePreventOverlap()
    if _G.SaveConfig then _G.SaveConfig() end
end

-- Own rect test rather than the track graph's: this block is loaded on its
-- own by the tests, and reaching outside it for two comparisons would tie the
-- two together for no gain.
function PatchbayFxNodeRectsHit(ax1, ay1, ax2, ay2, b, pad)
    return ax1 < b.x2 + pad and ax2 > b.x1 - pad and ay1 < b.y2 + pad and ay2 > b.y1 - pad
end

-- What a dropped thing has to stay clear of: every top-level node and both
-- edge boxes. Children are not listed -- a container's own box already covers
-- them, and they cannot be pinned separately anyway.
function PatchbayFxNodeObstacles(layout, skip_api, skip_edge)
    local out = {}
    for _, st in ipairs(layout.stages or {}) do
        for _, fx in ipairs(st) do
            if skip_api == nil or fx.api_id ~= skip_api then
                out[#out + 1] = { x1 = fx.x, y1 = fx.y, x2 = fx.x + fx.w, y2 = fx.y + fx.h }
            end
        end
    end
    for _, which in ipairs({ "in", "out" }) do
        if which ~= skip_edge then
            local x, y, w, h = PatchbayFxNodeEdgeRect(layout, which)
            if x and y then out[#out + 1] = { x1 = x, y1 = y, x2 = x + w, y2 = y + h } end
        end
    end
    return out
end

-- The nearest free spot, searched outwards a ring at a time so the answer is
-- the smallest nudge that works rather than the first one found. Returns the
-- original position unchanged when it was already clear, and also when nothing
-- within reach is free -- refusing the drop outright would be worse than a
-- slight overlap in a canvas packed solid.
function PatchbayFxNodeFreeSpot(obstacles, x, y, w, h, step)
    local pad = 8
    local function clear(dx, dy)
        local ax1, ay1 = x + dx, y + dy
        local ax2, ay2 = ax1 + w, ay1 + h
        for _, b in ipairs(obstacles) do
            if PatchbayFxNodeRectsHit(ax1, ay1, ax2, ay2, b, pad) then return false end
        end
        return true
    end
    if clear(0, 0) then return x, y, false end
    step = math.max(4, step or 20)
    for ring = 1, 40 do
        local best_dx, best_dy, best_d2
        for gx = -ring, ring do
            for gy = -ring, ring do
                if math.abs(gx) == ring or math.abs(gy) == ring then
                    local dx, dy = gx * step, gy * step
                    if clear(dx, dy) then
                        local d2 = dx * dx + dy * dy
                        if not best_d2 or d2 < best_d2 then
                            best_dx, best_dy, best_d2 = dx, dy, d2
                        end
                    end
                end
            end
        end
        if best_dx then return x + best_dx, y + best_dy, true end
    end
    return x, y, false
end

-- The step the search moves in, in screen pixels, so the same gesture behaves
-- the same however far the canvas is zoomed.
function PatchbayFxNodeFreeStep(zoom)
    local cfg = GetConfig()
    local base = (cfg and cfg.patchbay_snap_to_grid == true) and (GRID or 40) or 20
    return base * (zoom or 1)
end

-- Overlaps are settled where things are DRAWN, not only where they were let
-- go. Resolving on drop alone was not enough, and the reason is that a drop is
-- judged against the layout of that moment: pin a node in a gap, add one FX,
-- and the flow slides straight under it again. Nothing was watching after the
-- fact, and a layout saved before any of this existed was never looked at at
-- all.
--
-- Doing it here is stable rather than creeping: the outcome is a function of
-- the layout, so it comes out the same every frame, and what you stored stays
-- exactly as you stored it.
--
-- Who gives way: a node still flowing with the chain never moves -- it is
-- where the chain says it is, and nudging it would be the layout arguing with
-- itself. The IN and OUT boxes settle first, then the pinned nodes, each in a
-- fixed order so the picture never depends on which one was looked at first.
function PatchbayFxNodeResolveOverlaps(layout, dims, skip_api, skip_edge)
    local in_x, in_y = layout.edge_in_x, layout.edge_in_y
    local out_x, out_y = layout.edge_out_x, layout.edge_out_y
    if not PatchbayFxNodePreventOverlap() then return in_x, in_y, out_x, out_y end

    local step = PatchbayFxNodeFreeStep(dims.zoom)
    local function rect(x, y, w, h) return { x1 = x, y1 = y, x2 = x + w, y2 = y + h } end

    local fixed, movers = {}, {}
    for _, st in ipairs(layout.stages or {}) do
        for _, fx in ipairs(st) do
            if fx.pinned and fx.api_id ~= skip_api then
                movers[#movers + 1] = fx
            elseif fx.api_id ~= skip_api then
                fixed[#fixed + 1] = rect(fx.x, fx.y, fx.w, fx.h)
            end
        end
    end
    table.sort(movers, function(a, b)
        return tostring(a.fxguid) .. tostring(a.api_id) < tostring(b.fxguid) .. tostring(b.api_id)
    end)

    local ew, eh = layout.edge_w or 0, layout.edge_h or 0
    if in_x and skip_edge ~= "in" then
        in_x, in_y = PatchbayFxNodeFreeSpot(fixed, in_x, in_y, ew, eh, step)
        fixed[#fixed + 1] = rect(in_x, in_y, ew, eh)
    end
    if out_x and skip_edge ~= "out" then
        out_x, out_y = PatchbayFxNodeFreeSpot(fixed, out_x, out_y, ew, eh, step)
        fixed[#fixed + 1] = rect(out_x, out_y, ew, eh)
    end

    for _, fx in ipairs(movers) do
        local nx, ny = PatchbayFxNodeFreeSpot(fixed, fx.x, fx.y, fx.w, fx.h, step)
        if nx ~= fx.x or ny ~= fx.y then PatchbayFxNodeShiftOne(fx, nx - fx.x, ny - fx.y) end
        fixed[#fixed + 1] = rect(fx.x, fx.y, fx.w, fx.h)
    end

    layout.edge_in_x, layout.edge_in_y = in_x, in_y
    layout.edge_out_x, layout.edge_out_y = out_x, out_y
    return in_x, in_y, out_x, out_y
end

-- Applied after the automatic pass, so a node without a stored position keeps
-- flowing with the chain and only the ones you moved stand still. Children move
-- with their container: a container's contents are laid out inside it, and
-- pinning a child to absolute coordinates would tear it out of its own box.
function PatchbayFxNodeApplyPositions(track, stages, base_x, base_y, zoom)
    local positions = PatchbayFxNodeLoadPositions(track)
    if next(positions) == nil then return end
    for _, st in ipairs(stages) do
        for _, fx in ipairs(st) do
            local p = fx.fxguid and positions[fx.fxguid]
            if p then
                local nx = base_x + p.x * zoom
                local ny = base_y + p.y * zoom
                local dx, dy = nx - fx.x, ny - fx.y
                fx.x, fx.y = nx, ny
                fx.pinned = true
                if fx.child_stages then
                    PatchbayFxNodeShiftStages(fx.child_stages, dx, dy)
                end
            end
        end
    end
end

function PatchbayFxNodeShiftStages(stages, dx, dy)
    for _, st in ipairs(stages) do
        st.x, st.y = (st.x or 0) + dx, (st.y or 0) + dy
        for _, fx in ipairs(st) do
            fx.x, fx.y = fx.x + dx, fx.y + dy
            if fx.child_stages then PatchbayFxNodeShiftStages(fx.child_stages, dx, dy) end
        end
    end
end

-- Where a stage's cables actually attach. The old code read this off the
-- stage's computed slot, which stops being true the moment a node is pinned
-- somewhere else -- so it is measured from the nodes themselves instead.
-- Moves a node and its contents. Used while dragging, so the thing under the
-- cursor is the node itself rather than a label floating beside a node that
-- has not budged -- which is how a Patchbay track node behaves, and the reason
-- this view did not feel like one.
function PatchbayFxNodeShiftOne(fx, dx, dy)
    fx.x, fx.y = fx.x + dx, fx.y + dy
    if fx.child_stages then PatchbayFxNodeShiftStages(fx.child_stages, dx, dy) end
end

function PatchbayFxNodeStageBounds(st, skip_api)
    local left, right = math.huge, -math.huge
    local top, bottom = math.huge, -math.huge
    for _, fx in ipairs(st) do
        if skip_api == nil or fx.api_id ~= skip_api then
            if fx.x < left then left = fx.x end
            if fx.x + fx.w > right then right = fx.x + fx.w end
            if fx.y < top then top = fx.y end
            if fx.y + fx.h > bottom then bottom = fx.y + fx.h end
        end
    end
    if left == math.huge then
        -- Skipping emptied the stage: fall back to where the dragged node sat
        -- in the layout, so its gap stays put instead of vanishing.
        local drag = PB.fx_view_drag
        if drag and drag.layout_x then
            return drag.layout_x, drag.layout_x + (drag.layout_w or 0),
                   (drag.layout_y or 0) + (drag.layout_h or 0) * 0.5
        end
        return 0, 0, 0
    end
    return left, right, (top + bottom) * 0.5
end

-- ---------------------------------------------------------------------------
-- Plugin screenshots in the nodes
--
-- Off by default; a button in the header turns it on, and the choice is kept in
-- the config so the standalone remembers it too.
--
-- TK FX BROWSER's changelog records what happens if this is done naively: first
-- "ImGui_CreateImage: excessive creation of short-lived resources", then an
-- outright crash with "ImGui_Attach: exceeded maximum object attachment limit".
-- Three rules keep this out of that hole:
--
--   1. a texture is created once and kept, keyed on its file
--   2. at most a couple of new textures per frame, so a fast zoom or a chain
--      that suddenly grows cannot burst the limit
--   3. a hard cap with least-recently-used eviction, and nothing drawn in the
--      current frame is ever evicted
--
-- The saving grace over the browser's grid is scale: a chain is a handful of
-- plugins, not a scrolling wall of three thousand.
-- ---------------------------------------------------------------------------

PB.fx_view_shot_tex = nil     -- path -> { tex = , used = frame }
PB.fx_view_shot_path = nil    -- fx name -> path, or false when there is none
PB.fx_view_shot_count = 0
PB.fx_view_shot_frame = 0
PB.fx_view_shot_budget = 0

function PatchbayFxNodeShotsOn()
    local cfg = GetConfig()
    return cfg ~= nil and cfg.patchbay_fx_node_screenshots == true
end

function PatchbayFxNodeShotsToggle()
    local cfg = GetConfig()
    if not cfg then return end
    cfg.patchbay_fx_node_screenshots = not (cfg.patchbay_fx_node_screenshots == true)
    if _G.SaveConfig then _G.SaveConfig() end
    PatchbayFxNodeInvalidate()
end

-- TK FX BROWSER files its screenshots under the plugin's full name with
-- everything but letters, digits, spaces and hyphens turned into underscores,
-- so "VST: ReaEQ (Cockos)" is "VST_ ReaEQ _Cockos_.png".
function PatchbayFxNodeShotFile(name)
    return (tostring(name or ""):gsub("[^%w%s-]", "_"))
end

function PatchbayFxNodeShotLookup(full_name)
    if not full_name or full_name == "" then return nil end
    PB.fx_view_shot_path = PB.fx_view_shot_path or {}
    local hit = PB.fx_view_shot_path[full_name]
    if hit ~= nil then return hit or nil end

    local dir = (r.GetResourcePath() .. "/Scripts/TK Scripts/FX/Screenshots/"):gsub("\\", "/")
    -- Full name first, then the cleaned one: a plugin whose shot was filed
    -- under its bare title still gets found.
    local tries = { PatchbayFxNodeShotFile(full_name) }
    local clean = PatchbayFxSchemaCleanName(full_name, "")
    if clean ~= "" then tries[#tries + 1] = PatchbayFxNodeShotFile(clean) end
    for _, base in ipairs(tries) do
        if base ~= "" then
            for _, ext in ipairs({ ".png", ".jpg" }) do
                local path = dir .. base .. ext
                if FileExists(path) then
                    PB.fx_view_shot_path[full_name] = path
                    return path
                end
            end
        end
    end
    PB.fx_view_shot_path[full_name] = false
    return nil
end

function PatchbayFxNodeShotBeginFrame()
    PB.fx_view_shot_frame = (PB.fx_view_shot_frame or 0) + 1
    PB.fx_view_shot_budget = 2
end

function PatchbayFxNodeShotEvict(ctx)
    local cache = PB.fx_view_shot_tex
    if not cache then return end
    local oldest_key, oldest_used = nil, math.huge
    for path, entry in pairs(cache) do
        -- Never evict something the frame being built is using: that is the
        -- "load it, drop it, load it again" loop that produced the browser's
        -- short-lived-resource error.
        if entry.used < PB.fx_view_shot_frame and entry.used < oldest_used then
            oldest_key, oldest_used = path, entry.used
        end
    end
    if not oldest_key then return end
    local entry = cache[oldest_key]
    if entry and entry.tex and r.ImGui_Detach then
        pcall(r.ImGui_Detach, ctx, entry.tex)
    end
    cache[oldest_key] = nil
    PB.fx_view_shot_count = math.max(0, (PB.fx_view_shot_count or 0) - 1)
end

function PatchbayFxNodeShotTexture(ctx, path)
    if not path or not r.ImGui_CreateImage then return nil end
    PB.fx_view_shot_tex = PB.fx_view_shot_tex or {}
    local entry = PB.fx_view_shot_tex[path]
    if entry then
        if r.ImGui_ValidatePtr and r.ImGui_ValidatePtr(entry.tex, "ImGui_Image*") then
            entry.used = PB.fx_view_shot_frame
            return entry.tex
        end
        PB.fx_view_shot_tex[path] = nil
        PB.fx_view_shot_count = math.max(0, (PB.fx_view_shot_count or 0) - 1)
    end
    -- Out of budget: nothing is drawn for this node this frame and it is picked
    -- up on a later one. A node without its picture for two frames is nothing;
    -- exceeding the attachment limit is a crash.
    if (PB.fx_view_shot_budget or 0) <= 0 then return nil end
    while (PB.fx_view_shot_count or 0) >= 24 do
        local before = PB.fx_view_shot_count
        PatchbayFxNodeShotEvict(ctx)
        if PB.fx_view_shot_count >= before then return nil end
    end
    local ok, tex = pcall(r.ImGui_CreateImage, path)
    if not ok or not tex then
        PB.fx_view_shot_budget = PB.fx_view_shot_budget - 1
        return nil
    end
    if r.ImGui_ValidatePtr and not r.ImGui_ValidatePtr(tex, "ImGui_Image*") then return nil end
    pcall(r.ImGui_Attach, ctx, tex)
    PB.fx_view_shot_tex[path] = { tex = tex, used = PB.fx_view_shot_frame }
    PB.fx_view_shot_count = (PB.fx_view_shot_count or 0) + 1
    PB.fx_view_shot_budget = PB.fx_view_shot_budget - 1
    return tex
end

-- Fills the body, cropped to it rather than squashed: a plugin UI stretched to
-- a different aspect ratio is unrecognisable, which defeats the point.
function PatchbayFxNodeDrawShot(ctx, dl, fx, dims, x, y, w, h)
    if w < 12 or h < 10 then return false end
    local path = PatchbayFxNodeShotLookup(fx.full_name)
    if not path then return false end
    local tex = PatchbayFxNodeShotTexture(ctx, path)
    if not tex then return false end
    local iw, ih = 0, 0
    if r.ImGui_Image_GetSize then iw, ih = r.ImGui_Image_GetSize(tex) end
    local u0, v0, u1, v1 = 0, 0, 1, 1
    if iw and ih and iw > 0 and ih > 0 then
        local want, have = w / h, iw / ih
        if have > want then
            local keep = want / have
            u0, u1 = (1 - keep) * 0.5, 1 - (1 - keep) * 0.5
        else
            local keep = have / want
            v0, v1 = (1 - keep) * 0.5, 1 - (1 - keep) * 0.5
        end
    end
    if r.ImGui_DrawList_AddImage then
        r.ImGui_DrawList_AddImage(dl, tex, x, y, x + w, y + h, u0, v0, u1, v1, 0xFFFFFFFF)
        -- Veiled, so the badge and category text over it stay readable.
        r.ImGui_DrawList_AddRectFilled(dl, x, y, x + w, y + h, 0x00000060)
        return true
    end
    return false
end

-- ---------------------------------------------------------------------------
-- Following REAPER's track selection
--
-- Reads the selection straight from REAPER rather than from _G.TRACK: only the
-- standalone maintains that global, and even there not every frame.
--
-- It switches on a CHANGE of selection, not on a difference from what is being
-- shown. That distinction is the whole design: diving into a track deliberately
-- -- by double-click, by the node icon, by the schema panel -- would otherwise
-- be undone on the very next frame, because the view would differ from whatever
-- happened to be selected and would jump straight back. Now an explicit choice
-- stays put until you actually select something else, and nothing has to reach
-- into REAPER and change its selection as a side effect.
-- ---------------------------------------------------------------------------

PB.fx_view_last_sel = nil

function PatchbayFxNodeFollowOn()
    local cfg = GetConfig()
    return cfg == nil or cfg.patchbay_fx_node_follow ~= false
end

function PatchbayFxNodeFollowToggle()
    local cfg = GetConfig()
    if not cfg then return end
    cfg.patchbay_fx_node_follow = not PatchbayFxNodeFollowOn()
    if _G.SaveConfig then _G.SaveConfig() end
end

-- Returns the guid to switch to, or nil to stay where we are.
function PatchbayFxNodeFollowPoll()
    local sel = r.GetSelectedTrack and r.GetSelectedTrack(0, 0) or nil
    local guid = nil
    if sel and r.ValidatePtr(sel, "MediaTrack*") then guid = r.GetTrackGUID(sel) end
    local changed = (guid ~= nil) and (guid ~= PB.fx_view_last_sel)
    -- Recorded even while following is off, so switching it on does not then
    -- act on a selection made minutes ago.
    PB.fx_view_last_sel = guid
    if not changed then return nil end
    if not PatchbayFxNodeFollowOn() then return nil end
    if guid == PB.fx_view_guid then return nil end
    return guid
end

-- ---------------------------------------------------------------------------
-- Patching by pin
--
-- What a cable between two pins MEANS here needs stating, because REAPER has no
-- FX-to-FX connection to make. Every FX maps its pins onto the track's channel
-- bus, and that is the only wiring there is. So dragging from A's output pin to
-- B's input pin is read as:
--
--     make B's input pin listen to the channels A's output pin writes to
--
-- which is exactly the sidechain gesture: pull from whatever feeds channels 3/4
-- to a compressor's detector input, and it is wired. TK_Probe_FX_Pin_Mappings
-- established that SetPinMappings works for FX inside containers too, so this
-- reaches everywhere the view does.
--
-- The IN node carries one pin per track channel, so the source of a cable can
-- be the track itself rather than another plugin -- without that, there is
-- nothing to drag FROM when the sidechain comes straight off the track.
--
-- Replacing, not adding: a detector input that is meant to hear channel 3
-- should hear channel 3, not channels 1, 2 and 3. Right-click a pin to clear it.
-- ---------------------------------------------------------------------------

PB.fx_view_pin_drag = nil

-- Drawn versus followed. A node shows at most twelve pins and the IN/OUT boxes
-- at most sixteen channels, but the routing walk follows every pin and channel
-- a 64-bit mask can name; anything past the drawn ones collapses onto the last
-- drawn pin, which carries a "+N".
PATCHBAY_FX_PIN_DRAW_MAX = 12
PATCHBAY_FX_PIN_READ_MAX = 64
PATCHBAY_FX_EDGE_DRAW_MAX = 16

function PatchbayFxNodeTrackChannelsAll(track)
    if not track or not r.ValidatePtr(track, "MediaTrack*") then return 2 end
    local n = math.floor(r.GetMediaTrackInfo_Value(track, "I_NCHAN") or 2)
    if n < 2 then n = 2 end
    if n > PATCHBAY_FX_PIN_READ_MAX then n = PATCHBAY_FX_PIN_READ_MAX end
    return n
end

function PatchbayFxNodeTrackChannels(track)
    return math.min(PatchbayFxNodeTrackChannelsAll(track), PATCHBAY_FX_EDGE_DRAW_MAX)
end

-- A bypassed or offline FX hands its input through untouched, so for the
-- signal path it writes nothing -- whatever its output pins say. Same for every
-- top-level FX while the track's whole chain is switched off.
function PatchbayFxNodePasses(fx, chain_on)
    return (not fx.enabled) or fx.offline or (chain_on == false and (fx.depth or 0) == 0)
end

function PatchbayFxNodeChainOn(track)
    if not track or not r.ValidatePtr(track, "MediaTrack*") then return true end
    return r.GetMediaTrackInfo_Value(track, "I_FXEN") ~= 0
end

-- Pins on the IN and OUT boxes, one per track channel, laid out the same way a
-- node's own pins are so a cable meets them at the same kind of point.
function PatchbayFxNodeEdgePinY(y, h, index, total, dims)
    if total <= 1 then return y + h * 0.5 end
    local step = dims.pin_step
    local reach = (total - 1) * step
    if reach > h - dims.pin_r * 2 then
        reach = math.max(0, h - dims.pin_r * 2)
        step = reach / (total - 1)
    end
    return y + (h - reach) * 0.5 + step * (index - 1)
end

-- Every pin also records WHERE it sits in the signal path: `scope` is the
-- container whose channel space it lives in (nil for the track), `stage` its
-- position in that scope's run, and `stages` the run itself. A container's own
-- pins belong to the scope around it -- they map the outer channels -- while
-- its children get the container as their scope. PatchbayFxNodePinDropOk needs
-- all three to refuse a cable that REAPER would wire differently from how it
-- was drawn.
function PatchbayFxNodeCollectPins(layout, dims, track)
    local out = {}
    local function walk(stages, scope)
        for si, st in ipairs(stages) do
            for _, fx in ipairs(st) do
                local nin = math.min(fx.pins.nin, PATCHBAY_FX_PIN_DRAW_MAX)
                for i = 1, nin do
                    out[#out + 1] = { fx = fx, side = "in", index = i,
                        x = fx.x, y = PatchbayFxNodePinY(fx, i, nin, dims),
                        scope = scope, stage = si, stages = stages }
                end
                local nout = math.min(fx.pins.nout, PATCHBAY_FX_PIN_DRAW_MAX)
                for i = 1, nout do
                    out[#out + 1] = { fx = fx, side = "out", index = i,
                        x = fx.x + fx.w, y = PatchbayFxNodePinY(fx, i, nout, dims),
                        scope = scope, stage = si, stages = stages }
                end
                if fx.child_stages then walk(fx.child_stages, fx.api_id) end
            end
        end
    end
    walk(layout.stages, nil)
    -- The track's own channels. The IN box's pins are outputs -- a cable can
    -- start there. The OUT box's are inputs and stay display-only: dropping on
    -- one would mean rewriting the SOURCE plugin's output, which is a different
    -- operation from everything else here and is better left until it is asked
    -- for. PatchbayFxNodePinDropOk already refuses any edge pin as a target.
    local chans = PatchbayFxNodeTrackChannels(track)
    for i = 1, chans do
        -- One y per box. The two can be dragged apart, so a single shared row
        -- would leave one set of pins floating beside a box it no longer
        -- belongs to.
        if layout.edge_in_x then
            out[#out + 1] = { edge = "in", side = "out", index = i,
                x = layout.edge_in_x + layout.edge_w,
                y = PatchbayFxNodeEdgePinY(layout.edge_in_y, layout.edge_h, i, chans, dims),
                scope = nil, stage = 0, stages = layout.stages }
        end
        if layout.edge_out_x then
            out[#out + 1] = { edge = "out", side = "in", index = i,
                x = layout.edge_out_x,
                y = PatchbayFxNodeEdgePinY(layout.edge_out_y, layout.edge_h, i, chans, dims),
                scope = nil, stage = #layout.stages + 1, stages = layout.stages }
        end
    end
    return out
end

function PatchbayFxNodePinAt(pins, mx, my, dims)
    local reach = math.max(6, dims.pin_r + 5)
    local best, best_d = nil, reach * reach
    for _, p in ipairs(pins) do
        local dx, dy = mx - p.x, my - p.y
        local d = dx * dx + dy * dy
        if d <= best_d then best, best_d = p, d end
    end
    return best
end

-- The channels a pin is wired to, as a mask. An edge pin IS a channel.
function PatchbayFxNodePinMask(track, pin)
    if pin.edge then
        local bit = pin.index - 1
        if bit < 32 then return (1 << bit), 0 end
        return 0, (1 << (bit - 32))
    end
    local isout = (pin.side == "out") and 1 or 0
    local low, high = r.TrackFX_GetPinMappings(track, pin.fx.api_id, isout, pin.index - 1)
    return math.floor(tonumber(low) or 0), math.floor(tonumber(high) or 0)
end

-- The channels a source pin writes, from what the model already read -- this
-- runs for every candidate pin on every frame of a drag, so no API calls.
function PatchbayFxNodePinWrites(pin)
    if pin.edge then return { pin.index } end
    local info = pin.fx and pin.fx.pins and pin.fx.pins.outs[pin.index]
    return (info and info.chans) or {}
end

-- Only out -> in, never onto the plugin the cable came from, and only where
-- REAPER would end up wiring exactly what was drawn. A connection is stored as
-- "the input reads the channels the output writes", so it holds only if:
--
--   * both pins live in the same channel space. Inside a container, channel 3
--     is the container's channel 3, not the track's -- a cable across the
--     container wall would wire the right number in the wrong space.
--   * the source runs strictly BEFORE the target. Earlier, the target reads
--     the channel before the source has written it; in the same parallel stage
--     both read the same input, so neither sees the other's output.
--   * nothing in between overwrites those channels, and the source is not
--     bypassed. Otherwise the target hears something else, and the cable that
--     appears afterwards starts somewhere the user never dragged from.
--
-- Returns ok plus a reason; the reason is only for the cases worth explaining.
function PatchbayFxNodePinDropOk(src, dst)
    if not src or not dst then return false end
    if src.side ~= "out" or dst.side ~= "in" then return false end
    if dst.edge then return false end
    if src.fx and dst.fx and src.fx.api_id == dst.fx.api_id then return false end
    if src.scope ~= dst.scope then
        return false, "Those two pins are on different sides of a container wall.\n\n" ..
            "Inside a container the channels are the container's own, so wire " ..
            "through the container's input or output pins instead."
    end
    if (src.stage or 0) >= (dst.stage or 0) then
        return false, "That input is processed before (or alongside) this output, " ..
            "so it can never hear it."
    end
    if src.fx and PatchbayFxNodePasses(src.fx) then
        return false, string.format("%s is bypassed or offline, so it writes nothing.",
            src.fx.name or "That FX")
    end
    local writes = PatchbayFxNodePinWrites(src)
    if #writes == 0 then return false end
    local want = {}
    for _, ch in ipairs(writes) do want[ch] = true end
    local stages = src.stages or {}
    for si = (src.stage or 0) + 1, (dst.stage or 0) - 1 do
        for _, fx in ipairs(stages[si] or {}) do
            if not PatchbayFxNodePasses(fx) then
                for _, info in pairs(fx.pins.outs or {}) do
                    for _, ch in ipairs(info.chans or {}) do
                        if want[ch] then
                            return false, string.format(
                                "Channel %d is overwritten by %s before it reaches that input.",
                                ch, fx.name or "another FX")
                        end
                    end
                end
            end
        end
    end
    return true
end

-- REAPER does not see a pin change as a change. TrackFX_SetPinMappings moves
-- the pin but leaves the FX state unmarked, so the undo block around it closed
-- with nothing to record: no undo point at all, and Undo went straight past it
-- to whatever came before (TK_Probe_Pin_Undo, REAPER 7.75 -- Begin/EndBlock,
-- Undo_OnStateChangeEx2 with the FX flag and Undo_OnStateChange all failed).
--
-- Writing the FX's own name back, unchanged, inside the same block marks the
-- state dirty and the point appears; Undo then restores the pin, since pins
-- are part of the FX state REAPER snapshots. Measured with no plugin reload.
-- The name rather than a parameter: a parameter write can land in an
-- automation lane on a track in Write or Latch mode, and not every plugin has
-- a parameter to write.
function PatchbayFxNodeMarkPinsChanged(track, api_id)
    if not r.TrackFX_GetNamedConfigParm or not r.TrackFX_SetNamedConfigParm then return end
    local ok, name = r.TrackFX_GetNamedConfigParm(track, api_id, "renamed_name")
    r.TrackFX_SetNamedConfigParm(track, api_id, "renamed_name", ok and tostring(name or "") or "")
end

function PatchbayFxNodeConnectPins(track, src, dst)
    if IsAllLockedCfg(GetConfig()) then return false, "FX actions locked." end
    if not r.TrackFX_SetPinMappings then return false, "This REAPER cannot set pin mappings." end
    if not PatchbayFxNodePinDropOk(src, dst) then return false, nil end
    local low, high = PatchbayFxNodePinMask(track, src)
    if low == 0 and high == 0 then
        return false, "That output is not connected to any channel."
    end
    r.Undo_BeginBlock()
    local ok = r.TrackFX_SetPinMappings(track, dst.fx.api_id, 0, dst.index - 1, low, high)
    PatchbayFxNodeMarkPinsChanged(track, dst.fx.api_id)
    r.Undo_EndBlock("Patchbay: connect FX pin", -1)
    PatchbayFxNodeInvalidate()
    if ok == false then return false, "REAPER refused that connection." end
    return true, nil
end

-- Puts a plugin's pins back where REAPER starts them: pin k on channel k, both
-- sides. Clearing a pin sets it to nothing, which is not the same as putting it
-- right -- so until now a mis-drag could only be undone in REAPER's own pin
-- connector. Dragging is easy to get wrong; there has to be a way back.
function PatchbayFxNodeResetPins(track, api_id)
    if IsAllLockedCfg(GetConfig()) then return false, "FX actions locked." end
    if not track or not r.ValidatePtr(track, "MediaTrack*") then return false, "Track is gone." end
    if not r.TrackFX_SetPinMappings or not r.TrackFX_GetIOSize then
        return false, "This REAPER cannot set pin mappings."
    end
    local _, nin, nout = r.TrackFX_GetIOSize(track, api_id)
    nin = math.floor(tonumber(nin) or 0)
    nout = math.floor(tonumber(nout) or 0)
    if nin <= 0 and nout <= 0 then return false, "That FX has no pins." end
    r.Undo_BeginBlock()
    for p = 0, nin - 1 do
        local low = (p < 32) and (1 << p) or 0
        local high = (p >= 32) and (1 << (p - 32)) or 0
        r.TrackFX_SetPinMappings(track, api_id, 0, p, low, high)
    end
    for p = 0, nout - 1 do
        local low = (p < 32) and (1 << p) or 0
        local high = (p >= 32) and (1 << (p - 32)) or 0
        r.TrackFX_SetPinMappings(track, api_id, 1, p, low, high)
    end
    PatchbayFxNodeMarkPinsChanged(track, api_id)
    r.Undo_EndBlock("Patchbay: reset FX pin routing", -1)
    PatchbayFxNodeInvalidate()
    return true, nil
end

function PatchbayFxNodeClearPin(track, pin)
    if IsAllLockedCfg(GetConfig()) then return false end
    if not pin or pin.edge or not r.TrackFX_SetPinMappings then return false end
    local isout = (pin.side == "out") and 1 or 0
    r.Undo_BeginBlock()
    r.TrackFX_SetPinMappings(track, pin.fx.api_id, isout, pin.index - 1, 0, 0)
    PatchbayFxNodeMarkPinsChanged(track, pin.fx.api_id)
    r.Undo_EndBlock("Patchbay: disconnect FX pin", -1)
    PatchbayFxNodeInvalidate()
    return true
end

function PatchbayFxNodeDrawPinDrag(ctx, dl, pins, drag, mx, my, dims, track)
    local hot = PatchbayFxNodePinAt(pins, mx, my, dims)
    -- Every pin that could take this cable, so the possibilities are visible
    -- rather than discovered by trial.
    for _, p in ipairs(pins) do
        if PatchbayFxNodePinDropOk(drag, p) then
            local on = (hot == p)
            r.ImGui_DrawList_AddCircle(dl, p.x, p.y,
                dims.pin_r + (on and 5 or 3), on and 0xFFD36BFF or 0xFFD36B80, 0, on and 2.4 or 1.4)
        end
    end
    local col = (hot and PatchbayFxNodePinDropOk(drag, hot)) and 0xFFD36BFF or 0xFFFFFF99
    PatchbayFxNodeCable(dl, drag.x, drag.y, mx, my, col, 2.2)
    r.ImGui_DrawList_AddCircleFilled(dl, drag.x, drag.y, dims.pin_r + 1.5, col)
    return hot
end

function PatchbayFxNodeDrawEdgePins(ctx, dl, layout, dims, track, ink)
    local chans = PatchbayFxNodeTrackChannels(track)
    local extra = PatchbayFxNodeTrackChannelsAll(track) - chans
    local show = dims.zoom >= 0.75
    local text_h = r.ImGui_GetTextLineHeight(ctx)
    for i = 1, chans do
        -- The last drawn channel also stands for the ones past it.
        local label = tostring(i)
        if i == chans and extra > 0 then label = label .. " +" .. extra end
        if layout.edge_in_x then
            local py = PatchbayFxNodeEdgePinY(layout.edge_in_y, layout.edge_h, i, chans, dims)
            local px = layout.edge_in_x + layout.edge_w
            r.ImGui_DrawList_AddCircleFilled(dl, px, py, dims.pin_r, ink)
            if show and chans > 2 then
                r.ImGui_DrawList_AddText(dl, px + dims.pin_r + 4, py - text_h * 0.5, ink, label)
            end
        end
        -- The OUT box takes the chain's channels back in, on its left edge.
        if layout.edge_out_x then
            local py = PatchbayFxNodeEdgePinY(layout.edge_out_y, layout.edge_h, i, chans, dims)
            local px = layout.edge_out_x
            r.ImGui_DrawList_AddCircleFilled(dl, px, py, dims.pin_r, ink)
            if show and chans > 2 then
                local tw = r.ImGui_CalcTextSize(ctx, label)
                r.ImGui_DrawList_AddText(dl, px - dims.pin_r - 4 - tw, py - text_h * 0.5,
                    ink, label)
            end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Drawing the routing that is actually there
--
-- Until now a cable only said "this plugin comes after that one". The real
-- wiring -- which channel feeds which pin -- was readable from a label and a
-- tooltip, and nowhere else. That is half of what the pin work was for: being
-- able to change a mapping is worth little while you cannot see it.
--
-- The model is a walk of the chain carrying a source per channel. A run starts
-- with the track's channels at its left edge; each output pin becomes the new
-- source for the channels it writes; each input pin draws back to whatever
-- currently feeds the channel it reads. That is the signal path.
--
-- WHAT COUNTS AS TRIVIAL: pin 1 on channel 1 and pin 2 on channel 2 -- the
-- plain stereo path every plugin has. Everything else is drawn by default: a
-- detector input on channel 3, an output pushed somewhere unusual, a crossed
-- pair. Those are the ones worth seeing, and drawing the boring pair alongside
-- would bury them. The button shows the lot regardless.
-- ---------------------------------------------------------------------------

function PatchbayFxNodeRoutingOn()
    local cfg = GetConfig()
    return cfg ~= nil and cfg.patchbay_fx_node_routing == true
end

function PatchbayFxNodeRoutingToggle()
    local cfg = GetConfig()
    if not cfg then return end
    cfg.patchbay_fx_node_routing = not PatchbayFxNodeRoutingOn()
    if _G.SaveConfig then _G.SaveConfig() end
    PatchbayFxNodeInvalidate()
end

function PatchbayFxNodeChannelsOf(low, high)
    local out = {}
    low = math.floor(tonumber(low) or 0)
    high = math.floor(tonumber(high) or 0)
    for bit = 0, 31 do
        if low & (1 << bit) ~= 0 then out[#out + 1] = bit + 1 end
    end
    for bit = 0, 31 do
        if high & (1 << bit) ~= 0 then out[#out + 1] = bit + 33 end
    end
    return out
end

-- The main stereo path, and nothing else.
function PatchbayFxNodePinIsTrivial(index, chans)
    return index <= 2 and #chans == 1 and chans[1] == index
end

function PatchbayFxNodeLum(col)
    return (((col >> 24) & 0xFF) * 0.299) + (((col >> 16) & 0xFF) * 0.587)
         + (((col >> 8) & 0xFF) * 0.114)
end

-- One hue per channel, so two crossing cables are told apart at a glance -- but
-- a hue alone will not do. Red carries 0.299 of the luminance that green
-- carries at the same value, so channel 1 at a fixed brightness came out at an
-- effective contrast of about 23 against the canvas while channel 3 sat at 154.
-- The quiet cables were being drawn and simply could not be seen.
--
-- So the value is lifted (or dropped, on a light theme) until the cable clears
-- a contrast floor, desaturating toward white or black once value alone has run
-- out. Quiet cables stay quieter than loud ones -- they just stay visible.
-- One appearance per channel, whatever a cable says about the routing. A
-- deviating cable used to be brighter as well as differently coloured; with
-- the width already levelled, the hue does the work on its own and a second
-- axis only made the picture noisier. Every cable now gets what used to be
-- the readable setting, so nothing became harder to see.
--
-- The contrast loop stays, because a hue is no guarantee of visibility: pure
-- red carries a third of green's luminance at the same value, which is how a
-- channel-1 cable once ended up drawn and invisible on a dark canvas.
function PatchbayFxNodeChannelColor(ch)
    local hue = ((ch - 1) * 47) % 360
    local light = PatchbayFxSchemaThemeIsLight()
    local bg_l = PatchbayFxNodeLum(_G.patchbay_grid_bg_col or 0x1A1A1AFF)
    local floor = 105
    local alpha = 0.95
    local sat = 0.62
    local v = light and 0.42 or 0.98
    local col = PatchbayFxNodeHsv(hue, sat, v, alpha)
    for _ = 1, 16 do
        if math.abs(PatchbayFxNodeLum(col) - bg_l) * alpha >= floor then return col end
        if light then
            if v > 0.12 then v = v - 0.06 else sat = math.min(1, sat + 0.06) end
        else
            if v < 1 then v = math.min(1, v + 0.06) else sat = math.max(0.12, sat - 0.07) end
        end
        col = PatchbayFxNodeHsv(hue, sat, v, alpha)
    end
    return col
end

-- Reads the masks already collected onto each node, so the walk costs no extra
-- API calls per frame.
function PatchbayFxNodeRoutingCables(layout, dims, track, show_all)
    local out = {}
    local nchan = PatchbayFxNodeTrackChannels(track)
    local nchan_all = PatchbayFxNodeTrackChannelsAll(track)
    local chain_on = PatchbayFxNodeChainOn(track)

    -- `scope` is the container this part of the walk is running inside, and it
    -- travels with every cable born here. A container fills its whole body when
    -- it is drawn, so a cable that ends inside one has to be drawn a second
    -- time, after that body -- and it can only be found again if it says where
    -- it belongs.
    local function walk(stages, sources, scope)
        for _, st in ipairs(stages) do
            -- Reads first, then writes: everything in one parallel stage sees
            -- the same input, which is what parallel means.
            local writes = {}
            for _, fx in ipairs(st) do
                -- Pin positions use the full count: PatchbayFxNodePinY lays out
                -- the drawn ones and stacks the rest on the last drawn pin.
                local nin = fx.pins.nin
                local nin_drawn = math.min(nin, PATCHBAY_FX_PIN_DRAW_MAX)
                for i = 1, nin_drawn do
                    local info = fx.pins.ins[i]
                    if info and info.chans and #info.chans > 0 then
                        local trivial = PatchbayFxNodePinIsTrivial(i, info.chans)
                        if show_all or not trivial then
                            local py = PatchbayFxNodePinY(fx, i, nin, dims)
                            for _, ch in ipairs(info.chans) do
                                for _, src in ipairs(sources[ch] or {}) do
                                    out[#out + 1] = { x1 = src.x, y1 = src.y,
                                        x2 = fx.x, y2 = py, ch = ch, trivial = trivial,
                                        scope = scope }
                                end
                            end
                        end
                    end
                end
                -- Inside an open container the signal comes from the
                -- container's OWN input pins, not from whatever fed it. A
                -- container remaps the channels it is handed onto its own --
                -- it is two channels wide until container_nch_in says
                -- otherwise -- so a plugin in there reads the pin, not the
                -- track. Drawing it that way also makes the two sides match:
                -- outside -> pin -> inside, and inside -> pin -> outside.
                -- Seeding from the outer sources instead short-circuited the
                -- input pin and let the insides leak sideways onto anything
                -- running parallel to the container.
                local inner = nil
                if fx.child_stages and #fx.children > 0 and not fx.folded then
                    inner = {}
                    for i = 1, #fx.pins.ins do
                        inner[i] = { { x = fx.x, y = PatchbayFxNodePinY(fx, i, nin, dims) } }
                    end
                    walk(fx.child_stages, inner, fx.api_id)
                end
                local nout = fx.pins.nout
                local passes = PatchbayFxNodePasses(fx, chain_on)
                for i = 1, #fx.pins.outs do
                    local info = fx.pins.outs[i]
                    if info and info.chans then
                        local py = PatchbayFxNodePinY(fx, i, nout, dims)
                        local out_trivial = PatchbayFxNodePinIsTrivial(i, info.chans)
                        -- An open container's own output pin k is fed from the
                        -- container's internal channel k -- the PIN number, not
                        -- the outer channel the pin happens to write. Looking
                        -- it up by the outer channel was only right while pin
                        -- k sat on channel k; remap container out 1 to channel
                        -- 3 and the wrong insides were drawn into it. Once per
                        -- pin, too, however many outer channels it feeds.
                        if inner and #info.chans > 0 and (show_all or not out_trivial) then
                            for _, src in ipairs(inner[i] or {}) do
                                out[#out + 1] = { x1 = src.x, y1 = src.y,
                                    x2 = fx.x + fx.w, y2 = py, ch = info.chans[1],
                                    trivial = out_trivial, scope = fx.api_id }
                            end
                        end
                        -- A bypassed or offline FX writes nothing: its input
                        -- carries on as it was, so the next reader draws back
                        -- past it to whatever fed it.
                        if not passes then
                            for _, ch in ipairs(info.chans) do
                                -- Appended, not assigned: parallel lanes are summed,
                                -- so a channel written by two of them has two
                                -- sources. Overwriting made every lane but the last
                                -- a dead end on screen -- a reverb feeding nothing.
                                local w = writes[ch]
                                if not w then w = {}; writes[ch] = w end
                                w[#w + 1] = { x = fx.x + fx.w, y = py }
                            end
                        end
                    end
                end
            end
            for ch, list in pairs(writes) do sources[ch] = list end
        end
    end

    -- Every track channel is followed; the ones past the drawn sixteen start
    -- from (and end on) the last drawn edge pin, which carries a "+N".
    local sources = {}
    if layout.edge_in_x then
        for ch = 1, nchan_all do
            sources[ch] = { { x = layout.edge_in_x + layout.edge_w,
                              y = PatchbayFxNodeEdgePinY(layout.edge_in_y, layout.edge_h,
                                  math.min(ch, nchan), nchan, dims) } }
        end
    end
    walk(layout.stages, sources, nil)

    -- And out of the chain again: whatever writes a channel last is what the
    -- OUT box receives. Without this the picture simply stopped at the final
    -- plugin, as if the signal went nowhere.
    if layout.edge_out_x then
        for ch = 1, nchan_all do
            local trivial = ch <= 2
            if show_all or not trivial then
                for _, src in ipairs(sources[ch] or {}) do
                    out[#out + 1] = { x1 = src.x, y1 = src.y,
                        x2 = layout.edge_out_x,
                        y2 = PatchbayFxNodeEdgePinY(layout.edge_out_y, layout.edge_h,
                            math.min(ch, nchan), nchan, dims),
                        ch = ch, trivial = trivial }
                end
            end
        end
    end
    return out
end

PATCHBAY_FX_ROUTE_W = 1.2

-- ---------------------------------------------------------------------------
-- MIDI
--
-- The cables above are audio pins only, so a synth that declares no audio
-- inputs (Traveler: "2 out", nothing in) stood in the chain with nothing
-- running into it, as if it played on its own. Its signal is the track's MIDI,
-- and that gets a cable of its own: dashed and neutral grey, so it never reads
-- as one more audio channel. Drawn whatever the Routing toggle says -- it is
-- the only cable such a plugin has.
--
-- MIDI runs through the whole chain, so every instrument is fed from the
-- track. Inside a container it arrives through the container: one cable from
-- IN to the container, then on from the container's wall to the instrument.
-- ---------------------------------------------------------------------------

function PatchbayFxNodeHasInstrument(fx)
    if fx.is_instrument then return true end
    for _, c in ipairs(fx.children or {}) do
        if PatchbayFxNodeHasInstrument(c) then return true end
    end
    return false
end

-- Where MIDI enters a node: on its left edge, level with the header, clear of
-- the audio pins that sit around the middle of the body. A container takes it
-- just under its header, which is also where the inner cables leave from.
function PatchbayFxNodeMidiPoint(fx, dims)
    if fx.fx_type == "Container" and fx.child_stages then
        return fx.x, fx.y + dims.head_h
    end
    return fx.x, fx.y + dims.head_h * 0.5
end

function PatchbayFxNodeMidiCables(layout, dims)
    local out = {}
    local function walk(stages, sx, sy, scope)
        for _, st in ipairs(stages) do
            for _, fx in ipairs(st) do
                if fx.is_instrument or (fx.fx_type == "Container" and PatchbayFxNodeHasInstrument(fx)) then
                    local tx, ty = PatchbayFxNodeMidiPoint(fx, dims)
                    out[#out + 1] = { x1 = sx, y1 = sy, x2 = tx, y2 = ty, scope = scope,
                        faint = (not fx.enabled) or fx.offline }
                    if fx.child_stages and not fx.folded then
                        walk(fx.child_stages, tx, ty, fx.api_id)
                    end
                end
            end
        end
    end
    if layout.edge_in_x then
        walk(layout.stages, layout.edge_in_x + layout.edge_w,
            layout.edge_in_y + layout.edge_h - dims.pin_r * 2, nil)
    end
    return out
end

-- A bezier cut into dashes. Sampled by parameter, which bunches the dashes a
-- little on the bends; at these lengths that is not visible.
function PatchbayFxNodeDashedCable(dl, x1, y1, x2, y2, col, thick)
    local cp = math.max(18, math.abs(x2 - x1) * 0.45)
    local ax, ay, bx, by = x1 + cp, y1, x2 - cp, y2
    local len = math.sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2) + cp
    local n = math.max(8, math.floor(len / 5))
    local function at(t)
        local u = 1 - t
        return u * u * u * x1 + 3 * u * u * t * ax + 3 * u * t * t * bx + t * t * t * x2,
               u * u * u * y1 + 3 * u * u * t * ay + 3 * u * t * t * by + t * t * t * y2
    end
    local px, py = x1, y1
    for i = 1, n do
        local qx, qy = at(i / n)
        if i % 2 == 1 then r.ImGui_DrawList_AddLine(dl, px, py, qx, qy, col, thick) end
        px, py = qx, qy
    end
end

function PatchbayFxNodeMidiColor(faint)
    local col = PatchbayFxNodeCanvasInk(false)
    if faint then col = (col & 0xFFFFFF00) | 0x50 end
    return col
end

function PatchbayFxNodeDrawMidi(ctx, dl, layout, dims)
    local cables = PatchbayFxNodeMidiCables(layout, dims)
    PB.fx_view_midi = cables
    if #cables == 0 then return 0 end
    for _, c in ipairs(cables) do
        PatchbayFxNodeDashedCable(dl, c.x1, c.y1, c.x2, c.y2,
            PatchbayFxNodeMidiColor(c.faint), PATCHBAY_FX_ROUTE_W + 0.3)
    end
    -- Where it comes from, so the dashes do not seem to start out of nothing.
    if layout.edge_in_x and dims.zoom >= 0.75 then
        local x = layout.edge_in_x + layout.edge_w + dims.pin_r + 4
        local y = layout.edge_in_y + layout.edge_h - dims.pin_r * 2
        r.ImGui_DrawList_AddText(dl, x, y - r.ImGui_GetTextLineHeight(ctx) * 0.5,
            PatchbayFxNodeMidiColor(false), "MIDI")
    end
    return #cables
end

function PatchbayFxNodeDrawRouting(ctx, dl, layout, dims, track)
    local show_all = PatchbayFxNodeRoutingOn()
    local cables = PatchbayFxNodeRoutingCables(layout, dims, track, show_all)
    PB.fx_view_routing = cables
    -- One width for all of them. A deviating cable used to be drawn heavier as
    -- well as brighter, which said the same thing twice and read as clutter
    -- rather than as emphasis. The channel colour carries it on its own.
    for _, c in ipairs(cables) do
        PatchbayFxNodeCable(dl, c.x1, c.y1, c.x2, c.y2,
            PatchbayFxNodeChannelColor(c.ch), PATCHBAY_FX_ROUTE_W)
    end
    PatchbayFxNodeDrawMidi(ctx, dl, layout, dims)
    return #cables
end

-- The cables that live inside this container, drawn again on top of its body.
-- One pass under everything is not enough: a container is a node like any
-- other and fills its whole box, children included, so turning Routing on made
-- a container look emptier rather than fuller -- every cable in it was painted
-- over the moment the box went down.
--
-- Clipped to the box, so the stretch that runs in from outside keeps the place
-- the first pass gave it instead of being stamped across the nodes in between.
function PatchbayFxNodeDrawRoutingInside(dl, fx)
    local cables = PB.fx_view_routing
    if not cables or fx.api_id == nil then return 0 end
    local clip = r.ImGui_DrawList_PushClipRect ~= nil and r.ImGui_DrawList_PopClipRect ~= nil
    if clip then
        r.ImGui_DrawList_PushClipRect(dl, fx.x, fx.y, fx.x + fx.w, fx.y + fx.h, true)
    end
    local n = 0
    for _, c in ipairs(cables) do
        if c.scope == fx.api_id then
            n = n + 1
            PatchbayFxNodeCable(dl, c.x1, c.y1, c.x2, c.y2,
                PatchbayFxNodeChannelColor(c.ch), PATCHBAY_FX_ROUTE_W)
        end
    end
    for _, c in ipairs(PB.fx_view_midi or {}) do
        if c.scope == fx.api_id then
            n = n + 1
            PatchbayFxNodeDashedCable(dl, c.x1, c.y1, c.x2, c.y2,
                PatchbayFxNodeMidiColor(c.faint), PATCHBAY_FX_ROUTE_W + 0.3)
        end
    end
    if clip then r.ImGui_DrawList_PopClipRect(dl) end
    return n
end

function PatchbayFxNodeDims(zoom)
    local z = math.max(0.35, math.min(2.5, zoom or 1))
    return {
        zoom = z,
        node_w = math.floor(150 * z + 0.5),
        node_h = math.floor(44 * z + 0.5),
        pin_r = math.max(2, 4 * z),
        pin_step = math.max(7, 13 * z),
        col_gap = math.floor(76 * z + 0.5),
        row_gap = math.floor(28 * z + 0.5),
        pad = math.floor(16 * z + 0.5),
        head_h = math.floor(20 * z + 0.5),
        badge_h = math.floor(11 * z + 0.5),
        text_pad = math.floor(9 * z + 0.5),
        edge_w = math.floor(54 * z + 0.5)
    }
end

-- ---------------------------------------------------------------------------
-- Model
-- ---------------------------------------------------------------------------

function PatchbayFxNodeParm(track, addr, key)
    if not r.TrackFX_GetNamedConfigParm then return nil end
    local ok, v = r.TrackFX_GetNamedConfigParm(track, addr, key)
    if not ok then return nil end
    return tostring(v or "")
end

-- "1", "1,2", "3..8" or "-" for a pin that is connected to nothing. Kept short
-- on purpose: this label sits next to a 4 px dot.
function PatchbayFxNodeChannelLabel(low, high)
    low = math.floor(tonumber(low) or 0)
    high = math.floor(tonumber(high) or 0)
    local chans = {}
    for bit = 0, 31 do
        if low & (1 << bit) ~= 0 then chans[#chans + 1] = bit + 1 end
    end
    for bit = 0, 31 do
        if high & (1 << bit) ~= 0 then chans[#chans + 1] = bit + 33 end
    end
    if #chans == 0 then return "-", 0 end
    if #chans > 2 then return chans[1] .. ".." .. chans[#chans], #chans end
    return table.concat(chans, ","), #chans
end

function PatchbayFxNodePinInfo(track, addr)
    local info = { nin = 2, nout = 2, ins = {}, outs = {}, known = false }
    if not r.TrackFX_GetIOSize then return info end
    local _, nin, nout = r.TrackFX_GetIOSize(track, addr)
    if nin == nil and nout == nil then return info end
    info.known = true
    info.nin = math.max(0, math.floor(tonumber(nin) or 0))
    info.nout = math.max(0, math.floor(tonumber(nout) or 0))
    if not r.TrackFX_GetPinMappings then return info end
    -- Every pin is READ, up to the 64 channels a mask can name; only drawing is
    -- capped (PATCHBAY_FX_PIN_DRAW_MAX). Reading just the first twelve made a
    -- 32-out Kontakt look as if pins 13+ wrote nothing, so the channels they
    -- really write stayed hanging off their old source on screen. The cost is
    -- paid once per cache refresh, not per frame.
    -- The channel list is kept beside the label: the routing walk needs the
    -- numbers, and asking REAPER again per frame would be the same question
    -- twice.
    for pin = 0, math.min(info.nin, PATCHBAY_FX_PIN_READ_MAX) - 1 do
        local low, high = r.TrackFX_GetPinMappings(track, addr, 0, pin)
        local label, count = PatchbayFxNodeChannelLabel(low, high)
        info.ins[pin + 1] = { label = label, count = count,
                              chans = PatchbayFxNodeChannelsOf(low, high) }
    end
    for pin = 0, math.min(info.nout, PATCHBAY_FX_PIN_READ_MAX) - 1 do
        local low, high = r.TrackFX_GetPinMappings(track, addr, 1, pin)
        local label, count = PatchbayFxNodeChannelLabel(low, high)
        info.outs[pin + 1] = { label = label, count = count,
                               chans = PatchbayFxNodeChannelsOf(low, high) }
    end
    return info
end

-- The container address arithmetic, same as PatchbayFxSchemaCollectContainer
-- and the shipped Patchbay everywhere else: an address is an expression built
-- from counts that shift whenever the chain changes, so it is resolved on every
-- rebuild and never cached across frames.
function PatchbayFxNodeMake(track, api, fx_id, sibling_count, diff, depth)
    local _, raw_name = r.TrackFX_GetFXName(track, api, "")
    local fx_type = PatchbayFxNodeParm(track, api, "fx_type") or ""
    local node = {
        api_id = api,
        name = PatchbayFxSchemaCleanName(raw_name, "FX"),
        full_name = tostring(raw_name or ""),
        fx_type = fx_type,
        enabled = r.TrackFX_GetEnabled(track, api),
        offline = r.TrackFX_GetOffline and r.TrackFX_GetOffline(track, api) or false,
        parallel = (PatchbayFxNodeParm(track, api, "parallel") or "0") ~= "0",
        depth = depth,
        fxguid = r.TrackFX_GetFXGUID and r.TrackFX_GetFXGUID(track, api) or nil,
        category = PatchbayFxNodeCategoryOf(tostring(raw_name or "")),
        badge = PatchbayFxNodeFormatBadge(tostring(raw_name or "")),
        is_instrument = PatchbayFxNodeIsInstrument(tostring(raw_name or "")),
        container_id = (fx_type == "Container") and fx_id or nil,
        parent_fx_count = sibling_count,
        previous_diff = (depth == 0) and 0 or diff,
        stride = (depth == 0) and 1 or diff,
        pins = PatchbayFxNodePinInfo(track, api),
        children = {}
    }
    if fx_type == "Container" and depth < 4 then
        node.children = PatchbayFxNodeCollectContainer(track, fx_id, sibling_count, diff, depth)
    end
    return node
end

function PatchbayFxNodeCollectContainer(track, container_id, parent_count, prev_diff, depth)
    local out = {}
    if not r.TrackFX_GetNamedConfigParm then return out end
    local count = math.floor(tonumber(PatchbayFxNodeParm(track, 0x2000000 + container_id, "container_count")) or 0)
    if count <= 0 then return out end
    local diff = (depth == 0) and (parent_count + 1) or ((parent_count + 1) * prev_diff)
    for i = 1, count do
        local fx_id = container_id + diff * i
        out[#out + 1] = PatchbayFxNodeMake(track, 0x2000000 + fx_id, fx_id, count, diff, depth + 1)
    end
    return out
end

function PatchbayFxNodeMarkFolds(track, list)
    for _, fx in ipairs(list) do
        fx.folded = (fx.fx_type == "Container") and #fx.children > 0
            and PatchbayFxNodeIsFolded(track, fx.fxguid) or false
        if #fx.children > 0 then PatchbayFxNodeMarkFolds(track, fx.children) end
    end
end

function PatchbayFxNodeChain(track)
    local out = {}
    if not track or not r.ValidatePtr(track, "MediaTrack*") then return out end
    local count = r.TrackFX_GetCount(track) or 0
    for i = 0, count - 1 do
        out[#out + 1] = PatchbayFxNodeMake(track, i, i + 1, count, count + 1, 0)
    end
    PatchbayFxNodeMarkFolds(track, out)
    return out
end

-- A parallel FX joins the stage before it: same input, outputs summed. That is
-- the one piece of chain structure REAPER does not hand over as a tree.
function PatchbayFxNodeStages(list)
    local stages = {}
    for i = 1, #(list or {}) do
        local fx = list[i]
        if fx.parallel and #stages > 0 then
            local st = stages[#stages]
            st[#st + 1] = fx
        else
            stages[#stages + 1] = { fx }
        end
    end
    return stages
end

-- ---------------------------------------------------------------------------
-- Layout: measure bottom-up, then place top-down
-- ---------------------------------------------------------------------------

function PatchbayFxNodeMeasureOne(fx, dims)
    if fx.fx_type == "Container" and #fx.children > 0 and not fx.folded then
        local cw, ch, cstages = PatchbayFxNodeMeasure(fx.children, dims)
        fx.child_stages = cstages
        fx.child_w, fx.child_h = cw, ch
        fx.w = cw + dims.pad * 2
        fx.h = ch + dims.pad * 2 + dims.head_h
    else
        fx.w = dims.node_w
        -- Rounded: a node on a half pixel renders its 1 px border blurred.
        local body = PatchbayFxNodeShotsOn() and (dims.node_h * 1.45) or (dims.node_h * 0.55)
        fx.h = math.floor(math.max(dims.node_h, dims.head_h + body) + 0.5)
    end
    -- A node has to be tall enough for its own pins, or a ReaComp's four inputs
    -- pile up outside the box they belong to.
    local rows = math.max(math.min(fx.pins.nin, PATCHBAY_FX_PIN_DRAW_MAX), math.min(fx.pins.nout, PATCHBAY_FX_PIN_DRAW_MAX), 2)
    local needed = rows * dims.pin_step + dims.text_pad * 2
    if fx.h < needed then fx.h = needed end
end

function PatchbayFxNodeMeasure(list, dims)
    local stages = PatchbayFxNodeStages(list)
    local total_w, total_h = 0, 0
    for si = 1, #stages do
        local st = stages[si]
        local sw, sh = 0, 0
        for i = 1, #st do
            PatchbayFxNodeMeasureOne(st[i], dims)
            if st[i].w > sw then sw = st[i].w end
            sh = sh + st[i].h
        end
        sh = sh + dims.row_gap * (#st - 1)
        st.w, st.h = sw, sh
        total_w = total_w + sw
        if sh > total_h then total_h = sh end
    end
    total_w = total_w + dims.col_gap * math.max(0, #stages - 1)
    return total_w, total_h, stages
end

function PatchbayFxNodePlace(stages, x, y, band_h, dims)
    local cx = x
    for si = 1, #stages do
        local st = stages[si]
        st.x = cx
        st.y = y + (band_h - st.h) * 0.5
        local row_y = st.y
        for i = 1, #st do
            local fx = st[i]
            fx.x = cx + (st.w - fx.w) * 0.5
            fx.y = row_y
            row_y = row_y + fx.h + dims.row_gap
            if fx.child_stages then
                PatchbayFxNodePlace(fx.child_stages, fx.x + dims.pad,
                    fx.y + dims.head_h + dims.pad, fx.child_h, dims)
            end
        end
        cx = cx + st.w + dims.col_gap
    end
end

function PatchbayFxNodeBuild(track, dims)
    local chain = PatchbayFxNodeChain(track)
    local w, h, stages = PatchbayFxNodeMeasure(chain, dims)
    return { chain = chain, stages = stages, w = w, h = h }
end

-- ---------------------------------------------------------------------------
-- Drawing
-- ---------------------------------------------------------------------------

function PatchbayFxNodeCable(dl, x1, y1, x2, y2, col, thick)
    local cp = math.max(18, math.abs(x2 - x1) * 0.45)
    r.ImGui_DrawList_AddBezierCubic(dl, x1, y1, x1 + cp, y1, x2 - cp, y2, x2, y2, col, thick or 1.6)
end

-- Pins sit at a fixed spacing around the middle of the node, NOT spread across
-- its full height. Stretching them to fill the box put a stereo pair hard
-- against the top and bottom edges, where they read as corner decorations
-- rather than as an in and an out belonging to that plugin.
--
-- A container is measured by its contents, so it can be hundreds of pixels
-- tall; its pins belong to the header band, level with the name, or they float
-- somewhere in the middle of its children.
function PatchbayFxNodePinY(fx, index, total, dims)
    local band_top = fx.y
    local band_h = fx.h
    if fx.fx_type == "Container" and #fx.children > 0 then band_h = dims.head_h end
    if total <= 1 then return band_top + band_h * 0.5 end
    local span = math.min(total, PATCHBAY_FX_PIN_DRAW_MAX)
    local step = dims.pin_step
    -- Many pins on a short header would overflow it, so the spacing gives way
    -- before the band does.
    local reach = (span - 1) * step
    if reach > band_h - dims.pin_r * 2 then
        reach = math.max(0, band_h - dims.pin_r * 2)
        step = (span > 1) and (reach / (span - 1)) or 0
    end
    local top = band_top + (band_h - reach) * 0.5
    return top + step * math.min(index - 1, span - 1)
end

-- Anything drawn OUTSIDE a node body -- pins, their channel labels, the cables
-- between nodes -- sits on the canvas, not on the node. The schema palette is
-- no use for that: it is built for drawing on the schema panel's own light
-- background, so in monochrome on a dark theme it hands back near-black
-- (0x1B1B1B) for a canvas that is 0x1A1A1A. The pins were being drawn all
-- along; they were one step of grey away from the background.
--
-- A node inside a container is the exception: there the backdrop IS the
-- container's fill, so the container passes its own colours down to its
-- children instead of these.
function PatchbayFxNodeCanvasInk(strong)
    if PatchbayFxSchemaThemeIsLight() then
        return strong and 0x1C1C1CFF or 0x5A5A5ADD
    end
    return strong and 0xE4E8EEFF or 0x99A0AACC
end

function PatchbayFxNodeDrawPins(ctx, dl, fx, dims, line_col, text_col)
    local show_labels = dims.zoom >= 0.75
    local nin = math.min(fx.pins.nin, PATCHBAY_FX_PIN_DRAW_MAX)
    for i = 1, nin do
        local py = PatchbayFxNodePinY(fx, i, nin, dims)
        local info = fx.pins.ins[i]
        -- A pin mapped to nothing is drawn hollow: an unfed sidechain input is
        -- exactly the kind of thing a strip view cannot show.
        local dead = (not info) or info.count == 0
        if dead then
            r.ImGui_DrawList_AddCircle(dl, fx.x, py, dims.pin_r, line_col, 0, 1.3)
        else
            r.ImGui_DrawList_AddCircleFilled(dl, fx.x, py, dims.pin_r, line_col)
        end
        if show_labels and info and nin > 2 then
            local label = info.label
            -- The last drawn pin stands for every pin past it as well.
            if i == nin and fx.pins.nin > nin then
                label = "+" .. (fx.pins.nin - nin) .. "  " .. label
            end
            local tw = r.ImGui_CalcTextSize(ctx, label)
            r.ImGui_DrawList_AddText(dl, fx.x - dims.pin_r - 4 - tw,
                py - r.ImGui_GetTextLineHeight(ctx) * 0.5, text_col, label)
        end
    end
    local nout = math.min(fx.pins.nout, PATCHBAY_FX_PIN_DRAW_MAX)
    for i = 1, nout do
        local py = PatchbayFxNodePinY(fx, i, nout, dims)
        local info = fx.pins.outs[i]
        local dead = (not info) or info.count == 0
        if dead then
            r.ImGui_DrawList_AddCircle(dl, fx.x + fx.w, py, dims.pin_r, line_col, 0, 1.3)
        else
            r.ImGui_DrawList_AddCircleFilled(dl, fx.x + fx.w, py, dims.pin_r, line_col)
        end
        if show_labels and info and nout > 2 then
            local label = info.label
            if i == nout and fx.pins.nout > nout then
                label = label .. "  +" .. (fx.pins.nout - nout)
            end
            r.ImGui_DrawList_AddText(dl, fx.x + fx.w + dims.pin_r + 4,
                py - r.ImGui_GetTextLineHeight(ctx) * 0.5, text_col, label)
        end
    end
end

-- Chips are readable against ANYTHING behind them -- the body colour, a
-- container's fill, a screenshot -- so their plate and ink are fixed to the
-- theme rather than derived from the node's own colours. The format badge used
-- the border for its plate and the header colour for its text, two values that
-- can land a few luminance steps apart, and the category was bare text laid
-- straight over a plugin screenshot.
-- An instrument keeps whatever category its folder gives it -- "KEYS" says
-- more than "Instrument" -- so the fact that it IS one is carried by the format
-- chip instead. 429 of the 3030 plugins here are instruments and all but 23 of
-- them already have a better label; overwriting that would have thrown the
-- useful half away.
function PatchbayFxNodeChipColors(instrument)
    if instrument then
        if PatchbayFxSchemaThemeIsLight() then return 0x1E7A3CFF, 0xF2FFF6FF end
        return 0x6FDA92FF, 0x04180AFF
    end
    if PatchbayFxSchemaThemeIsLight() then
        return 0xFFFFFFE0, 0x1A1A1AFF
    end
    return 0x000000C8, 0xF2F4F7FF
end

-- Draws at x when right_edge is nil, otherwise ending at right_edge. Returns
-- the width it took, so the caller can see what room is left.
function PatchbayFxNodeDrawChip(ctx, dl, text, x, y, dims, right_edge, instrument)
    if not text or text == "" then return 0 end
    local plate, ink = PatchbayFxNodeChipColors(instrument)
    local text_h = r.ImGui_GetTextLineHeight(ctx)
    local tw = r.ImGui_CalcTextSize(ctx, text)
    local pad = math.max(2, 3 * dims.zoom)
    local w = tw + pad * 2
    local tx = right_edge and (right_edge - w + pad) or x
    r.ImGui_DrawList_AddRectFilled(dl, tx - pad, y - 1, tx + tw + pad, y + text_h + 1,
        plate, math.max(2, 3 * dims.zoom))
    r.ImGui_DrawList_AddText(dl, tx, y, ink, text)
    return w
end

function PatchbayFxNodeDrawOne(ctx, dl, fx, dims, ink_pin, ink_label)
    local head_bg, body_bg, border, text_col = PatchbayFxNodeSkin(fx)
    local selected = PB.fx_view_sel_api ~= nil and PB.fx_view_sel_api == fx.api_id
    local is_container = fx.fx_type == "Container" and #fx.children > 0 and not fx.folded
    local round = math.max(3, 6 * dims.zoom)
    local label_h = math.min(dims.head_h, fx.h)

    -- A shadow costs one rect and does more for depth than any gradient would.
    -- Derived, not stored: the layout table is cached between frames, so a
    -- flag set during a drag would still be on it after the drag ended.
    local dragging = PB.fx_view_drag ~= nil and PB.fx_view_drag.active
        and PB.fx_view_drag.api_id == fx.api_id
    local shadow = math.max(1, (dragging and 6 or 2) * dims.zoom)
    r.ImGui_DrawList_AddRectFilled(dl, fx.x + shadow, fx.y + shadow,
        fx.x + fx.w + shadow, fx.y + fx.h + shadow, 0x00000055, round)

    r.ImGui_DrawList_AddRectFilled(dl, fx.x, fx.y, fx.x + fx.w, fx.y + fx.h, body_bg, round)
    local top_flags = r.ImGui_DrawFlags_RoundCornersTop and r.ImGui_DrawFlags_RoundCornersTop() or nil
    r.ImGui_DrawList_AddRectFilled(dl, fx.x, fx.y, fx.x + fx.w, fx.y + label_h,
        head_bg, round, top_flags)
    local outline = border
    local weight = 1.2
    if dragging then outline, weight = 0xFFFFFFFF, 2.4
    elseif selected then outline, weight = 0xFFD36BFF, 2.2 end
    r.ImGui_DrawList_AddRect(dl, fx.x, fx.y, fx.x + fx.w, fx.y + fx.h, outline, round, nil, weight)
    -- Straight after the body, so the routing inside is under the children and
    -- over the box, exactly like the cables outside are under the nodes.
    if is_container then PatchbayFxNodeDrawRoutingInside(dl, fx) end

    local text_h = r.ImGui_GetTextLineHeight(ctx)
    local dot_room = math.max(3, 5 * dims.zoom) * 2 + 6
    local fold_room = 0
    if fx.fx_type == "Container" and #fx.children > 0 then
        fold_room = math.max(4, dims.head_h * 0.34) + dims.text_pad * 0.6
    end
    local label = TruncateText(ctx, fx.name, fx.w - dims.text_pad * 2 - dot_room - fold_room)
    r.ImGui_DrawList_AddText(dl, fx.x + dims.text_pad + fold_room,
        fx.y + (label_h - text_h) * 0.5, text_col, label)

    -- No screenshot on a container: its body is its children, and a plugin
    -- picture behind them would only be noise.
    if PatchbayFxNodeShotsOn() and fx.h > label_h + 8 and fx.fx_type ~= "Container" then
        PatchbayFxNodeDrawShot(ctx, dl, fx, dims,
            fx.x + 1, fx.y + label_h, fx.w - 2, fx.h - label_h - 1)
    end

    -- Format chip left, category chip right, both on the bottom edge of the
    -- body. The prefix is stripped from the name above, so the badge is where
    -- "which VST3" gets answered, and the category is what colour alone cannot
    -- spell out.
    if dims.zoom >= 0.7 and fx.h > label_h + text_h then
        local chip_y = fx.y + fx.h - text_h - dims.text_pad * 0.35
        local used = 0
        if fx.badge then
            used = PatchbayFxNodeDrawChip(ctx, dl, fx.badge,
                fx.x + dims.text_pad, chip_y, dims, nil, fx.is_instrument)
        end
        if fx.category and dims.zoom >= 0.85 then
            local room = fx.w - used - dims.text_pad * 3
            if r.ImGui_CalcTextSize(ctx, fx.category) < room then
                PatchbayFxNodeDrawChip(ctx, dl, fx.category, nil, chip_y, dims,
                    fx.x + fx.w - dims.text_pad)
            end
        end
    end
    PatchbayFxNodeDrawBypass(dl, fx, dims, text_col)
    PatchbayFxNodeDrawPins(ctx, dl, fx, dims, ink_pin, ink_label)
    if is_container then
        PatchbayFxNodeDrawStages(ctx, dl, fx.child_stages, dims,
            fx.x + dims.pad, fx.y + dims.head_h + dims.pad + fx.child_h * 0.5,
            fx.x + fx.w - dims.pad, border, text_col)
    end
    if fx.fx_type == "Container" and #fx.children > 0 then
        PatchbayFxNodeDrawFold(dl, fx, dims, text_col)
        if fx.folded then
            local note = string.format("%d FX", #fx.children)
            local nw = r.ImGui_CalcTextSize(ctx, note)
            r.ImGui_DrawList_AddText(dl, fx.x + fx.w - dims.text_pad - nw,
                fx.y + fx.h - text_h - dims.text_pad * 0.4, text_col, note)
        end
    end
end

-- Cables run stage to stage. A parallel stage gets a junction dot at each end:
-- the split that feeds every lane, and the merge that sums them. That is the
-- honest picture of what REAPER does, and it is a junction in a cable run
-- rather than a bus bar drawn beside a strip.
-- The serial links of a chain, worked out ONCE and used by both the drawing
-- and the drop targets.
--
-- They used to be computed separately in two places, which is why the drop
-- lines never sat where the cables ran: two bits of geometry drifting apart.
-- A drop target now IS a cable -- you drop onto the connection you want to be
-- part of, marked at its midpoint.
--
-- `skip_api` leaves out the node currently being carried, so the links describe
-- the chain you are dropping into rather than the one your hand is in.
-- `left_y` and `right_y` are where the run actually starts and ends, which is
-- no longer the same height as its middle: the IN and OUT boxes can be moved.
-- They default to mid_y, so a run inside a container is unaffected.
function PatchbayFxNodeLinks(stages, dims, left_x, mid_y, right_x, skip_api, left_y, right_y)
    local links = {}
    local prev_x, prev_y = left_x, left_y or mid_y
    for si = 1, #stages do
        local st = stages[si]
        local l, rr, m = PatchbayFxNodeStageBounds(st, skip_api)
        local ax, bx = l, rr
        if #st > 1 then
            -- A parallel stage attaches at its split and merge junctions, not
            -- at the boxes themselves.
            ax = l - dims.col_gap * 0.35
            bx = rr + dims.col_gap * 0.35
        end
        links[#links + 1] = { x1 = prev_x, y1 = prev_y, x2 = ax, y2 = m,
                              dest = st[1].api_id, at_end = false, stage = st,
                              jx = ax, jy = m }
        prev_x, prev_y = bx, m
    end
    links[#links + 1] = { x1 = prev_x, y1 = prev_y, x2 = right_x, y2 = right_y or mid_y,
                          dest = nil, at_end = true }
    return links
end

function PatchbayFxNodeDrawStages(ctx, dl, stages, dims, left_x, mid_y, right_x, ink_line, ink_label,
                                  left_y, right_y)
    local line_col = ink_line or PatchbayFxNodeCanvasInk(false)
    ink_label = ink_label or PatchbayFxNodeCanvasInk(true)
    local links = PatchbayFxNodeLinks(stages, dims, left_x, mid_y, right_x, nil, left_y, right_y)

    -- With the real routing on screen the symbolic cable is not just redundant,
    -- it hides them: on a stereo node the two channel cables sit a few pixels
    -- either side of it, and all three read as one thick line. So the
    -- abstraction stands down for the thing it was standing in for.
    local symbolic = not PatchbayFxNodeRoutingOn()
    if symbolic then
        for _, link in ipairs(links) do
            local target = link.stage and link.stage[1] or nil
            local col, thick = PatchbayFxNodeCableStyle(
                (link.stage and #link.stage == 1) and target or nil, line_col)
            PatchbayFxNodeCable(dl, link.x1, link.y1, link.x2, link.y2, col, thick)
        end
    end

    for si = 1, #stages do
        local st = stages[si]
        -- The split and merge junctions belong to the symbolic picture too: with
        -- real cables on, every lane is visibly fed from the same source
        -- already, which is what the junction was drawing.
        if symbolic and #st > 1 then
            local l, rr, m = PatchbayFxNodeStageBounds(st, nil)
            local jx = l - dims.col_gap * 0.35
            local jx2 = rr + dims.col_gap * 0.35
            r.ImGui_DrawList_AddCircleFilled(dl, jx, m, math.max(2, dims.pin_r * 0.8), line_col)
            r.ImGui_DrawList_AddCircleFilled(dl, jx2, m, math.max(2, dims.pin_r * 0.8), line_col)
            for i = 1, #st do
                local fx = st[i]
                local col, thick = PatchbayFxNodeCableStyle(fx, line_col)
                PatchbayFxNodeCable(dl, jx, m, fx.x, fx.y + fx.h * 0.5, col, thick)
                PatchbayFxNodeCable(dl, fx.x + fx.w, fx.y + fx.h * 0.5, jx2, m, line_col)
            end
        end
        for i = 1, #st do
            PatchbayFxNodeDrawOne(ctx, dl, st[i], dims, ink_label, ink_label)
        end
    end
end

function PatchbayFxNodeDrawEdge(ctx, dl, x, y, w, h, label, dims)
    local bg, border, text_col = PatchbayFxSchemaPalette("panel")
    r.ImGui_DrawList_AddRectFilled(dl, x, y, x + w, y + h, bg, math.max(3, 6 * dims.zoom))
    r.ImGui_DrawList_AddRect(dl, x, y, x + w, y + h, border, math.max(3, 6 * dims.zoom), nil, 1.2)
    local text_h = r.ImGui_GetTextLineHeight(ctx)
    local tw = r.ImGui_CalcTextSize(ctx, label)
    r.ImGui_DrawList_AddText(dl, x + (w - tw) * 0.5, y + (h - text_h) * 0.5, text_col, label)
end

-- ---------------------------------------------------------------------------
-- Hit testing (read-only for now: selection and the container a click lands in)
-- ---------------------------------------------------------------------------

function PatchbayFxNodeHit(stages, mx, my)
    local found = nil
    for si = 1, #stages do
        local st = stages[si]
        for i = 1, #st do
            local fx = st[i]
            if mx >= fx.x and mx <= fx.x + fx.w and my >= fx.y and my <= fx.y + fx.h then
                found = fx
                if fx.child_stages then
                    -- Innermost wins, so clicking a child does not select the
                    -- container that happens to be drawn under it.
                    local deeper = PatchbayFxNodeHit(fx.child_stages, mx, my)
                    if deeper then found = deeper end
                end
            end
        end
    end
    return found
end

-- ---------------------------------------------------------------------------
-- The view
-- ---------------------------------------------------------------------------

function PatchbayFxNodeEnter(guid)
    PB.fx_view_guid = guid
    PB.fx_view_sel_api = nil
    PB.fx_view_fit_pending = true
end

function PatchbayFxNodeExit()
    PB.fx_view_guid = nil
    PB.fx_view_sel_api = nil
end

function PatchbayFxNodeResolveTrack()
    if not PB.fx_view_guid then return nil end
    local n = r.CountTracks(0)
    for i = 0, n - 1 do
        local tr = r.GetTrack(0, i)
        if r.GetTrackGUID(tr) == PB.fx_view_guid then return tr end
    end
    return nil
end

-- ---------------------------------------------------------------------------
-- Acting on an FX from the node view
--
-- The six functions below are lifted from the abandoned TKFXBPatchbay_FXCHAIN
-- prototype with only their selection bookkeeping changed. They were always
-- visual-agnostic -- they talk to REAPER, not to a layout -- which is exactly
-- why replacing the prototype's strip drawing with nodes costs nothing here.
-- ---------------------------------------------------------------------------

function PatchbayFxNodeTarget(track, fx)
    if not fx then return nil end
    return { track = track, track_guid = PB.fx_view_guid, api_id = fx.api_id, name = fx.name }
end

function PatchbayFxNodeRename(target, name)
    if IsAllLockedCfg(GetConfig()) then return false end
    if not target or not target.track or target.api_id == nil or not r.ValidatePtr(target.track, "MediaTrack*") then return false end
    if not r.TrackFX_SetNamedConfigParm then return false end
    name = tostring(name or ""):gsub("^%s*(.-)%s*$", "%1")
    if name == "" then return false end
    r.Undo_BeginBlock()
    local ok = r.TrackFX_SetNamedConfigParm(target.track, target.api_id, "renamed_name", name)
    r.Undo_EndBlock("Patchbay: rename FX", -1)
    PatchbayFxNodeInvalidate()
    return ok
end

-- Three ways to reach a wet parameter, because which one exists depends on the
-- plugin: a real ":wet" parameter, the named config value, or the old
-- wet/dry mix call. The second return says whether any of them answered.
function PatchbayFxNodeGetWet(target)
    if not target or not target.track or target.api_id == nil or not r.ValidatePtr(target.track, "MediaTrack*") then return 1.0, false end
    if r.TrackFX_GetParamFromIdent and r.TrackFX_GetParam then
        local wet_param = r.TrackFX_GetParamFromIdent(target.track, target.api_id, ":wet")
        if wet_param and wet_param >= 0 then
            local val = r.TrackFX_GetParam(target.track, target.api_id, wet_param)
            if type(val) == "number" then return math.max(0, math.min(1, val)), true end
        end
    end
    if r.TrackFX_GetNamedConfigParm then
        local ok, val = r.TrackFX_GetNamedConfigParm(target.track, target.api_id, "wet")
        if ok and val and val ~= "" then
            local wet = tonumber(val)
            if wet then return math.max(0, math.min(1, wet)), true end
        end
    end
    if r.TrackFX_GetWetDryMix then
        local ok, wet = pcall(function() return r.TrackFX_GetWetDryMix(target.track, target.api_id) end)
        if ok and type(wet) == "number" then return math.max(0, math.min(1, wet)), true end
    end
    return 1.0, false
end

function PatchbayFxNodeSetWet(target, wet)
    if IsAllLockedCfg(GetConfig()) then return false end
    if not target or not target.track or target.api_id == nil or not r.ValidatePtr(target.track, "MediaTrack*") then return false end
    wet = math.max(0, math.min(1, tonumber(wet) or 0))
    r.Undo_BeginBlock()
    local ok = false
    if r.TrackFX_GetParamFromIdent and r.TrackFX_SetParam then
        local wet_param = r.TrackFX_GetParamFromIdent(target.track, target.api_id, ":wet")
        if wet_param and wet_param >= 0 then
            r.TrackFX_SetParam(target.track, target.api_id, wet_param, wet)
            ok = true
        end
    end
    if not ok and r.TrackFX_SetNamedConfigParm then
        local called = pcall(function() r.TrackFX_SetNamedConfigParm(target.track, target.api_id, "wet", string.format("%.6f", wet)) end)
        if called then ok = true end
    end
    if not ok and r.TrackFX_SetWetDryMix then
        local called = pcall(function() r.TrackFX_SetWetDryMix(target.track, target.api_id, wet, 1 - wet) end)
        if called then ok = true end
    end
    r.Undo_EndBlock("Patchbay: set FX wet/dry", -1)
    return ok
end

function PatchbayFxNodeSetBypass(target, bypassed)
    if IsAllLockedCfg(GetConfig()) then return false end
    if not target or not target.track or target.api_id == nil or not r.ValidatePtr(target.track, "MediaTrack*") then return false end
    if not r.TrackFX_SetEnabled then return false end
    r.Undo_BeginBlock()
    r.TrackFX_SetEnabled(target.track, target.api_id, not bypassed)
    r.Undo_EndBlock("Patchbay: set FX bypass", -1)
    PatchbayFxNodeInvalidate()
    return true
end

function PatchbayFxNodeSetOffline(target, offline)
    if IsAllLockedCfg(GetConfig()) then return false end
    if not target or not target.track or target.api_id == nil or not r.ValidatePtr(target.track, "MediaTrack*") then return false end
    if not r.TrackFX_SetOffline then return false end
    r.Undo_BeginBlock()
    r.TrackFX_SetOffline(target.track, target.api_id, offline)
    r.Undo_EndBlock("Patchbay: set FX offline", -1)
    PatchbayFxNodeInvalidate()
    return true
end

function PatchbayFxNodeDelete(target)
    if IsAllLockedCfg(GetConfig()) then return false end
    if not target or not target.track or target.api_id == nil or not r.ValidatePtr(target.track, "MediaTrack*") then return false end
    if not r.TrackFX_Delete then return false end
    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)
    local ok = r.TrackFX_Delete(target.track, target.api_id)
    r.PreventUIRefresh(-1)
    r.TrackList_AdjustWindows(false)
    r.UpdateArrange()
    r.Undo_EndBlock("Patchbay: delete FX", -1)
    -- Every address after the deleted one has just shifted, so a selection kept
    -- by api_id now points at the wrong plugin. Drop it rather than move it.
    PB.fx_view_sel_api = nil
    PatchbayFxNodeInvalidate()
    return ok ~= false
end

-- ---------------------------------------------------------------------------
-- The bypass dot, and the popup behind a right-click
-- ---------------------------------------------------------------------------

function PatchbayFxNodeBypassSpot(fx, dims)
    local rad = math.max(3, 5 * dims.zoom)
    local head = math.min(dims.head_h, fx.h)
    return fx.x + fx.w - dims.text_pad - rad, fx.y + head * 0.5, rad
end

function PatchbayFxNodeDrawBypass(dl, fx, dims, border)
    local cx, cy, rad = PatchbayFxNodeBypassSpot(fx, dims)
    if fx.enabled then
        r.ImGui_DrawList_AddCircleFilled(dl, cx, cy, rad, 0x6FD88AFF)
    else
        r.ImGui_DrawList_AddCircle(dl, cx, cy, rad, border, 0, 1.4)
    end
end

function PatchbayFxNodePopups(ctx, track)
    if PB.fx_view_ctx_open then
        r.ImGui_OpenPopup(ctx, "PatchbayFxNodeCtx")
        PB.fx_view_ctx_open = false
    end
    if PB.fx_view_ctx_api and r.ImGui_BeginPopup(ctx, "PatchbayFxNodeCtx") then
        local target = { track = track, track_guid = PB.fx_view_guid, api_id = PB.fx_view_ctx_api }
        if not r.ValidatePtr(track, "MediaTrack*") then
            r.ImGui_TextDisabled(ctx, "Track is gone")
            r.ImGui_EndPopup(ctx)
            PB.fx_view_ctx_api = nil
            return
        end
        r.ImGui_Text(ctx, tostring(PB.fx_view_ctx_name or "FX"))
        r.ImGui_Separator(ctx)
        if IsAllLockedCfg(GetConfig()) then
            r.ImGui_TextDisabled(ctx, "FX actions locked")
        else
            local wet, wet_ok = PatchbayFxNodeGetWet(target)
            if wet_ok then
                r.ImGui_PushItemWidth(ctx, 190)
                local changed, pct = r.ImGui_SliderDouble(ctx, "Wet", wet * 100, 0, 100, "%.0f%%")
                r.ImGui_PopItemWidth(ctx)
                if changed then PatchbayFxNodeSetWet(target, pct / 100) end
            else
                r.ImGui_TextDisabled(ctx, "Wet/Dry unavailable")
            end
            local bypassed = not r.TrackFX_GetEnabled(track, target.api_id)
            local ch_b, new_b = r.ImGui_Checkbox(ctx, "Bypass", bypassed)
            if ch_b then PatchbayFxNodeSetBypass(target, new_b) end
            local offline = r.TrackFX_GetOffline and r.TrackFX_GetOffline(track, target.api_id) or false
            local ch_o, new_o = r.ImGui_Checkbox(ctx, "Offline", offline)
            if ch_o then PatchbayFxNodeSetOffline(target, new_o) end
            r.ImGui_Separator(ctx)
            if r.ImGui_Selectable(ctx, "Open FX window") then
                if r.TrackFX_Show then r.TrackFX_Show(track, target.api_id, 3) end
                r.ImGui_CloseCurrentPopup(ctx)
            end
            if r.ImGui_Selectable(ctx, "Rename FX...") then
                PB.fx_view_rename_api = target.api_id
                local _, raw = r.TrackFX_GetFXName(track, target.api_id, "")
                PB.fx_view_rename_text = tostring(raw or "")
                PB.fx_view_rename_open = true
                r.ImGui_CloseCurrentPopup(ctx)
            end
            if r.ImGui_Selectable(ctx, "Reset pin routing") then
                local ok, err = PatchbayFxNodeResetPins(track, PB.fx_view_ctx_api)
                if not ok and err then r.ShowMessageBox(tostring(err), "Patchbay", 0) end
                r.ImGui_CloseCurrentPopup(ctx)
            end
            if r.ImGui_IsItemHovered and r.ImGui_IsItemHovered(ctx) then
                r.ImGui_SetTooltip(ctx, "Put every pin back on its own channel")
            end
            r.ImGui_Separator(ctx)

            -- Both are top-level only, so they are simply absent on a
            -- plugin inside a container rather than offered and then refused.
            local top_level = PB.fx_view_ctx_api ~= nil and PB.fx_view_ctx_api < 0x2000000
            if top_level and not PB.fx_view_ctx_is_container
                and r.ImGui_Selectable(ctx, "Wrap in new container") then
                local ok, err = PatchbayFxNodeWrapInContainer(track, PB.fx_view_ctx_api)
                if not ok and err then r.ShowMessageBox(tostring(err), "Patchbay", 0) end
                PB.fx_view_ctx_api = nil
                r.ImGui_CloseCurrentPopup(ctx)
            end
            if top_level and PB.fx_view_ctx_is_container
                and r.ImGui_Selectable(ctx, "Unpack container") then
                local ok, err = PatchbayFxNodeUnpackContainer(track, PB.fx_view_ctx_api)
                if not ok and err then r.ShowMessageBox(tostring(err), "Patchbay", 0) end
                PB.fx_view_ctx_api = nil
                r.ImGui_CloseCurrentPopup(ctx)
            end
            r.ImGui_Separator(ctx)
            if r.ImGui_Selectable(ctx, "Add FX after this...") then
                local node = PB.fx_view_cache
                    and PatchbayFxNodeFindByApi(PB.fx_view_cache.stages, target.api_id)
                if node then
                    PatchbayFxNodeOpenAdd("after", track, node, "after " .. tostring(node.name))
                end
                r.ImGui_CloseCurrentPopup(ctx)
            end
            if PB.fx_view_ctx_is_container and r.ImGui_Selectable(ctx, "Add FX inside this container...") then
                local node = PB.fx_view_cache
                    and PatchbayFxNodeFindByApi(PB.fx_view_cache.stages, target.api_id)
                if node then
                    PatchbayFxNodeOpenAdd("inside", track, node, "inside " .. tostring(node.name))
                end
                r.ImGui_CloseCurrentPopup(ctx)
            end
            r.ImGui_Separator(ctx)
            if r.ImGui_Selectable(ctx, "Delete FX") then
                PatchbayFxNodeDelete(target)
                PB.fx_view_ctx_api = nil
                r.ImGui_CloseCurrentPopup(ctx)
            end
        end
        r.ImGui_EndPopup(ctx)
    end

    if PB.fx_view_rename_open then
        r.ImGui_OpenPopup(ctx, "PatchbayFxNodeRename")
        PB.fx_view_rename_open = false
    end
    if PB.fx_view_rename_api and r.ImGui_BeginPopup(ctx, "PatchbayFxNodeRename") then
        if not r.ValidatePtr(track, "MediaTrack*") then
            r.ImGui_TextDisabled(ctx, "Track is gone")
            PB.fx_view_rename_api = nil
        else
            local changed, txt = r.ImGui_InputText(ctx, "Name", PB.fx_view_rename_text or "")
            if changed then PB.fx_view_rename_text = txt end
            if r.ImGui_Button(ctx, "Rename") then
                PatchbayFxNodeRename({ track = track, track_guid = PB.fx_view_guid,
                    api_id = PB.fx_view_rename_api }, PB.fx_view_rename_text)
                PB.fx_view_rename_api = nil
                r.ImGui_CloseCurrentPopup(ctx)
            end
            r.ImGui_SameLine(ctx)
            if r.ImGui_Button(ctx, "Cancel") then
                PB.fx_view_rename_api = nil
                r.ImGui_CloseCurrentPopup(ctx)
            end
        end
        r.ImGui_EndPopup(ctx)
    end
end

-- ---------------------------------------------------------------------------
-- Moving an FX by dragging it
--
-- The four move functions are the prototype's, unchanged in substance. They are
-- the reason this whole rewrite was cheap: reordering a REAPER chain is fiddly
-- address arithmetic plus parallel-flag bookkeeping, and none of it cares what
-- the chain looks like on screen.
--
-- Three kinds of drop, and no more for now:
--   serial     -- into a gap between stages, or at either end
--   parallel   -- onto an existing node, joining its stage
--   container  -- onto a container's header, appended at the end of it
-- ---------------------------------------------------------------------------

function PatchbayFxNodeSwapParallelInfo(track, src_api, dst_api)
    if not r.TrackFX_GetNamedConfigParm or not r.TrackFX_SetNamedConfigParm then return end
    local ok_src, src_par = r.TrackFX_GetNamedConfigParm(track, src_api, "parallel")
    local ok_dst, dst_par = r.TrackFX_GetNamedConfigParm(track, dst_api, "parallel")
    if ok_src and ok_dst then
        r.TrackFX_SetNamedConfigParm(track, src_api, "parallel", tostring(dst_par or "0"))
        r.TrackFX_SetNamedConfigParm(track, dst_api, "parallel", tostring(src_par or "0"))
    end
end

-- Pulling an FX out from under a parallel neighbour would orphan that
-- neighbour's flag, so the flag moves with the slot rather than with the plugin.
function PatchbayFxNodeCheckNextParallel(track, source_api, next_api)
    if not r.TrackFX_GetNamedConfigParm or not next_api then return end
    if source_api < 0x2000000 then
        local count = r.TrackFX_GetCount(track) or 0
        if next_api >= count then return end
    end
    local ok, parallel = r.TrackFX_GetNamedConfigParm(track, next_api, "parallel")
    local val = tostring(parallel or "0")
    if ok and (val == "1" or val == "2") then
        PatchbayFxNodeSwapParallelInfo(track, source_api, next_api)
    end
end

function PatchbayFxNodeMoveSerial(track, source_api, dest_index, source_next_api)
    if IsAllLockedCfg(GetConfig()) then return false end
    if not track or not r.ValidatePtr(track, "MediaTrack*") then return false end
    if not r.TrackFX_CopyToTrack then return false end
    source_api = math.floor(tonumber(source_api) or -1)
    dest_index = math.floor(tonumber(dest_index) or -1)
    if source_api < 0 or dest_index < 0 then return false end
    local count = r.TrackFX_GetCount(track) or 0
    if source_api < 0x2000000 and source_api >= count then return false end
    if dest_index < 0x2000000 and dest_index > count then dest_index = count end
    -- A destination inside a container is passed through untouched: it is an
    -- address, not a position in the top-level list.
    -- Dropping a plugin back where it already sits is not a move.
    local no_move_next = source_next_api or (source_api < 0x2000000 and source_api + 1 or nil)
    if dest_index == source_api or dest_index == no_move_next then return false end
    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)
    PatchbayFxNodeCheckNextParallel(track, source_api, no_move_next)
    if r.TrackFX_SetNamedConfigParm then
        r.TrackFX_SetNamedConfigParm(track, source_api, "parallel", "0")
    end
    local ok = r.TrackFX_CopyToTrack(track, source_api, track, dest_index, true)
    r.PreventUIRefresh(-1)
    if ok ~= false then
        r.TrackList_AdjustWindows(false)
        r.UpdateArrange()
    end
    r.Undo_EndBlock("Patchbay: move FX", -1)
    PatchbayFxNodeInvalidate()
    return ok ~= false
end

function PatchbayFxNodeMoveParallel(track, source_api, target_api, target_next_api, source_next_api)
    if IsAllLockedCfg(GetConfig()) then return false end
    if not track or not r.ValidatePtr(track, "MediaTrack*") then return false end
    if not r.TrackFX_CopyToTrack or not r.TrackFX_SetNamedConfigParm then return false end
    source_api = math.floor(tonumber(source_api) or -1)
    target_api = math.floor(tonumber(target_api) or -1)
    if source_api < 0 or target_api < 0 or source_api == target_api then return false end
    local dest_index = (target_api < 0x2000000) and (target_api + 1) or target_next_api
    if not dest_index or dest_index < 0 then return false end
    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)
    PatchbayFxNodeCheckNextParallel(track, source_api,
        source_next_api or (source_api < 0x2000000 and source_api + 1 or nil))
    -- "2" is REAPER's flag for "runs alongside the one before me".
    r.TrackFX_SetNamedConfigParm(track, source_api, "parallel", "2")
    local ok = r.TrackFX_CopyToTrack(track, source_api, track, dest_index, true)
    r.PreventUIRefresh(-1)
    if ok ~= false then
        r.TrackList_AdjustWindows(false)
        r.UpdateArrange()
    end
    r.Undo_EndBlock("Patchbay: move FX to parallel", -1)
    PatchbayFxNodeInvalidate()
    return ok ~= false
end

-- The slot one past a container's last child. Rebuilt from live counts, never
-- from anything remembered: adding to the chain moves every one of these.
function PatchbayFxNodeApplyStageFlags(track, first_api, lane_count, stride)
    if not r.TrackFX_SetNamedConfigParm then return end
    first_api = math.floor(tonumber(first_api) or -1)
    lane_count = math.floor(tonumber(lane_count) or 0)
    stride = math.floor(tonumber(stride) or 1)
    if first_api < 0 or lane_count < 2 then return end
    if stride <= 0 then stride = 1 end
    for i = 0, lane_count - 1 do
        r.TrackFX_SetNamedConfigParm(track, first_api + (i * stride), "parallel",
            (i == 0) and "0" or "2")
    end
end

-- Reordering WITHIN a parallel stage. The lanes keep the same run of slots, so
-- only their order changes -- which is why the flags are simply re-stamped over
-- the same range afterwards rather than worked out per plugin.
function PatchbayFxNodeReorderParallel(track, source_api, dest_index, first_api, lane_count, stride)
    if IsAllLockedCfg(GetConfig()) then return false end
    if not track or not r.ValidatePtr(track, "MediaTrack*") then return false end
    if not r.TrackFX_CopyToTrack or not r.TrackFX_SetNamedConfigParm then return false end
    source_api = math.floor(tonumber(source_api) or -1)
    dest_index = math.floor(tonumber(dest_index) or -1)
    stride = math.floor(tonumber(stride) or 1)
    if stride <= 0 then stride = 1 end
    if source_api < 0 or dest_index < 0 or lane_count < 2 then return false end
    if dest_index == source_api or dest_index == source_api + stride then return false end
    local count = r.TrackFX_GetCount(track) or 0
    if source_api < 0x2000000 then
        if source_api >= count then return false end
        if dest_index > count then dest_index = count end
    end
    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)
    local ok = r.TrackFX_CopyToTrack(track, source_api, track, dest_index, true)
    if ok ~= false then
        PatchbayFxNodeApplyStageFlags(track, first_api, lane_count, stride)
    end
    r.PreventUIRefresh(-1)
    if ok ~= false then
        r.TrackList_AdjustWindows(false)
        r.UpdateArrange()
    end
    r.Undo_EndBlock("Patchbay: reorder parallel FX", -1)
    PatchbayFxNodeInvalidate()
    return ok ~= false
end

function PatchbayFxNodeContainerEndSlot(track, node)
    if not node or not node.container_id then return nil end
    if not r.TrackFX_GetNamedConfigParm then return nil end
    local ok, raw = r.TrackFX_GetNamedConfigParm(track, 0x2000000 + node.container_id, "container_count")
    local child_count = ok and math.floor(tonumber(raw) or 0) or 0
    local parent_count = tonumber(node.parent_fx_count) or r.TrackFX_GetCount(track) or 0
    local depth = tonumber(node.depth) or 0
    local previous_diff = tonumber(node.previous_diff) or 0
    local diff = (depth == 0) and (parent_count + 1) or ((parent_count + 1) * previous_diff)
    if diff <= 0 then return nil end
    return 0x2000000 + node.container_id + (diff * (child_count + 1))
end

function PatchbayFxNodeMoveIntoContainer(track, source_api, container_node, source_next_api)
    if IsAllLockedCfg(GetConfig()) then return false end
    if not track or not r.ValidatePtr(track, "MediaTrack*") then return false end
    if not r.TrackFX_CopyToTrack or not r.TrackFX_SetNamedConfigParm then return false end
    if source_api == container_node.api_id then return false end
    local slot = PatchbayFxNodeContainerEndSlot(track, container_node)
    if not slot then return false end
    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)
    PatchbayFxNodeCheckNextParallel(track, source_api,
        source_next_api or (source_api < 0x2000000 and source_api + 1 or nil))
    r.TrackFX_SetNamedConfigParm(track, source_api, "parallel", "0")
    local ok = r.TrackFX_CopyToTrack(track, source_api, track, slot, true)
    r.PreventUIRefresh(-1)
    if ok ~= false then
        r.TrackList_AdjustWindows(false)
        r.UpdateArrange()
    end
    r.Undo_EndBlock("Patchbay: move FX into container", -1)
    PatchbayFxNodeInvalidate()
    return ok ~= false
end

-- ---------------------------------------------------------------------------
-- Where you may drop
-- ---------------------------------------------------------------------------

-- A node may not be dropped into itself or into anything it contains, or the
-- move would try to reparent a container under its own child.
-- ---------------------------------------------------------------------------
-- Wrapping an FX in a container, and unpacking one
--
-- Both are the prototype's, with its selection bookkeeping swapped for this
-- view's and the container slot taken from PatchbayFxNodeContainerEndSlot
-- rather than a second copy of the same arithmetic.
--
-- Note which call takes which form of address: TrackFX_AddByName wants
-- -1000 minus the slot, TrackFX_CopyToTrack wants the raw container address.
-- Mixing those up is silent -- the FX simply lands somewhere else.
--
-- Both are top-level only for now. Wrapping an FX that already sits inside a
-- container would need the parent's stride threaded through every step, and
-- guessing at that is how addresses end up pointing at the wrong plugin.
-- ---------------------------------------------------------------------------

function PatchbayFxNodeWrapInContainer(track, api_id)
    if IsAllLockedCfg(GetConfig()) then return false, "FX actions locked." end
    if not track or not r.ValidatePtr(track, "MediaTrack*") then return false, "Track is gone." end
    if not r.TrackFX_AddByName or not r.TrackFX_CopyToTrack or not r.TrackFX_SetNamedConfigParm then
        return false, "Container actions are unavailable in this REAPER."
    end
    api_id = math.floor(tonumber(api_id) or -1)
    if api_id < 0 or api_id >= 0x2000000 then
        return false, "Wrapping is only available for top-level FX."
    end
    local count = r.TrackFX_GetCount(track) or 0
    if api_id >= count then return false, "That FX no longer exists." end

    -- The container inherits the plugin's place in any parallel stage, and the
    -- plugin itself becomes serial inside it.
    local _, source_parallel = r.TrackFX_GetNamedConfigParm(track, api_id, "parallel")
    source_parallel = tostring(source_parallel or "0")

    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)
    local new_api = r.TrackFX_AddByName(track, "Container", false, -1000 - api_id)
    local ok = new_api ~= nil and new_api >= 0
    local container_api = api_id
    if ok then
        container_api = (new_api < 0x2000000) and new_api or api_id
        -- Inserting ahead of the source pushes it one slot along.
        local source_now = (container_api <= api_id) and (api_id + 1) or api_id
        r.TrackFX_SetNamedConfigParm(track, container_api, "parallel", source_parallel)
        r.TrackFX_SetNamedConfigParm(track, source_now, "parallel", "0")
        local slot = PatchbayFxNodeContainerEndSlot(track, {
            container_id = container_api + 1,
            parent_fx_count = r.TrackFX_GetCount(track) or (count + 1),
            previous_diff = 0,
            depth = 0
        })
        ok = slot ~= nil and r.TrackFX_CopyToTrack(track, source_now, track, slot, true) ~= false
    end
    r.PreventUIRefresh(-1)
    if ok then
        r.TrackList_AdjustWindows(false)
        r.UpdateArrange()
        PB.fx_view_sel_api = container_api
    end
    r.Undo_EndBlock("Patchbay: wrap FX in container", -1)
    PatchbayFxNodeInvalidate()
    if not ok then return false, "That FX could not be wrapped." end
    return true, nil
end

function PatchbayFxNodeUnpackContainer(track, api_id)
    if IsAllLockedCfg(GetConfig()) then return false, "FX actions locked." end
    if not track or not r.ValidatePtr(track, "MediaTrack*") then return false, "Track is gone." end
    if not r.TrackFX_CopyToTrack or not r.TrackFX_Delete or not r.TrackFX_SetNamedConfigParm then
        return false, "Container actions are unavailable in this REAPER."
    end
    api_id = math.floor(tonumber(api_id) or -1)
    if api_id < 0 or api_id >= 0x2000000 then
        return false, "Unpacking is only available for top-level containers."
    end
    local _, fx_type = r.TrackFX_GetNamedConfigParm(track, api_id, "fx_type")
    if tostring(fx_type or "") ~= "Container" then return false, "That is not a container." end

    local container_id = api_id + 1
    local _, raw_count = r.TrackFX_GetNamedConfigParm(track, 0x2000000 + container_id, "container_count")
    local child_count = math.floor(tonumber(raw_count) or 0)
    local _, container_parallel = r.TrackFX_GetNamedConfigParm(track, api_id, "parallel")
    container_parallel = tostring(container_parallel or "0")

    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)
    local ok, moved = true, 0
    while ok and moved < child_count do
        -- Always the FIRST remaining child, resolved against a LIVE count: each
        -- move changes the top-level total, and with it every address inside
        -- the container. Working from a list captured up front would move the
        -- wrong plugins after the first one.
        local parent_count = r.TrackFX_GetCount(track) or 0
        local child_api = 0x2000000 + container_id + (parent_count + 1)
        if not r.TrackFX_GetFXName(track, child_api, "") then ok = false break end
        local _, child_parallel = r.TrackFX_GetNamedConfigParm(track, child_api, "parallel")
        child_parallel = tostring(child_parallel or "0")
        local dest = api_id + moved + 1
        ok = r.TrackFX_CopyToTrack(track, child_api, track, dest, true) ~= false
        if ok then
            -- The first one out takes over the container's own parallel state;
            -- the rest keep whatever they had inside it.
            r.TrackFX_SetNamedConfigParm(track, dest, "parallel",
                (moved == 0) and container_parallel or child_parallel)
            moved = moved + 1
        end
    end
    if ok then ok = r.TrackFX_Delete(track, api_id) ~= false end
    r.PreventUIRefresh(-1)
    if ok then
        r.TrackList_AdjustWindows(false)
        r.UpdateArrange()
        PB.fx_view_sel_api = (moved > 0) and api_id or nil
    end
    r.Undo_EndBlock("Patchbay: unpack container", -1)
    PatchbayFxNodeInvalidate()
    if not ok then return false, "That container could not be unpacked." end
    return true, nil
end

function PatchbayFxNodeContains(node, api)
    if not node or not node.children then return false end
    for _, child in ipairs(node.children) do
        if child.api_id == api then return true end
        if PatchbayFxNodeContains(child, api) then return true end
    end
    return false
end

-- Would dropping here actually move anything?
--
-- The same arithmetic PatchbayFxNodeMoveSerial uses to refuse a move, asked
-- before the target is offered rather than after it is taken. The cable just
-- before and just after the plugin you are carrying both put it back exactly
-- where it came from, so showing a mark there promises something that will not
-- happen.
--
-- The check is purely numeric on purpose: a container child's address is
-- nowhere near a top-level index, so dragging one OUT of a container never
-- looks like a no-op, which is right -- that is a real move.
function PatchbayFxNodeDropIsNoOp(track, source, dest)
    if not source or dest == nil then return false end
    local src = source.api_id
    return dest == src or dest == src + (source.stride or 1)
end

function PatchbayFxNodeCollectDropTargets(layout, dims, source, track)
    local out = {}
    local stages = layout.stages
    local grab = math.max(11, 15 * dims.zoom)

    -- One target per cable, centred on it. Dropping on a connection is the
    -- thing you are actually asking for -- "put this plugin in here" -- and a
    -- mark on the cable says where "here" is.
    local skip = source and source.api_id or nil

    -- Marks for one run of cables. `tail_dest` is the slot the last cable of
    -- that run inserts into: the end of the track for the top level, the end of
    -- the container for a run inside one.
    local function add_serial(run, left_x, mid_y, right_x, tail_dest, left_y, right_y)
        for _, link in ipairs(PatchbayFxNodeLinks(run, dims, left_x, mid_y, right_x, skip,
                                                  left_y, right_y)) do
            local dest = link.at_end and tail_dest or link.dest
            if dest ~= nil and not PatchbayFxNodeDropIsNoOp(track, source, dest) then
                local cx = (link.x1 + link.x2) * 0.5
                local cy = (link.y1 + link.y2) * 0.5
                out[#out + 1] = {
                    kind = "serial", dest = dest,
                    cx = cx, cy = cy,
                    x = cx - grab, y = cy - grab, w = grab * 2, h = grab * 2
                }
            end
        end
    end

    add_serial(stages, layout.link_left or 0, layout.link_mid or 0, layout.link_right or 0,
        r.TrackFX_GetCount and (r.TrackFX_GetCount(track) or 0) or nil,
        layout.link_left_y, layout.link_right_y)

    -- The same again for the inside of every open container, on the anchors its
    -- own cables are drawn from. Without this you could only ever append to a
    -- container, never order what is already in it.
    local function inner_serial(list)
        for _, st in ipairs(list) do
            for _, fx in ipairs(st) do
                -- Never offer the insides of the container you are carrying, nor
                -- of anything within it: that would be dropping a container into
                -- its own belly. The node targets already refuse this; the serial
                -- marks have to refuse it as well.
                local carrying_it = source ~= nil
                    and (fx.api_id == source.api_id or PatchbayFxNodeContains(source, fx.api_id))
                if fx.child_stages and #fx.children > 0 and not fx.folded and not carrying_it then
                    add_serial(fx.child_stages,
                        fx.x + dims.pad,
                        fx.y + dims.head_h + dims.pad + (fx.child_h or 0) * 0.5,
                        fx.x + fx.w - dims.pad,
                        PatchbayFxNodeContainerEndSlot(track, fx))
                    inner_serial(fx.child_stages)
                end
            end
        end
    end
    inner_serial(stages)

    -- Onto a node: join its stage in parallel. Onto a container's header: move
    -- inside it. Both walk the tree, so a nested container is a target too.
    -- Order matters: PatchbayFxNodeFindDrop scans backwards, so whatever is
    -- added LAST wins where regions overlap. A container therefore offers
    --
    --   its whole box   -> parallel with the container   (added first)
    --   its header      -> inside the container          (added second)
    --   its children    -> whatever each child offers    (added last)
    --
    -- which leaves the ring of padding around the children as the place to drop
    -- something alongside a container. Without the box entry there was no way
    -- to put anything parallel to a container at all: the header claimed the
    -- only region a container had.
    local function walk(list)
        for _, st in ipairs(list) do
            for _, fx in ipairs(st) do
                local self_or_child = (source ~= nil) and
                    (fx.api_id == source.api_id or PatchbayFxNodeContains(source, fx.api_id))
                if not self_or_child then
                    out[#out + 1] = { kind = "parallel", node = fx, stage = st,
                        x = fx.x, y = fx.y, w = fx.w, h = fx.h }
                    if fx.fx_type == "Container" and #fx.children > 0 then
                        out[#out + 1] = { kind = "container", node = fx,
                            x = fx.x, y = fx.y, w = fx.w, h = dims.head_h }
                    end
                end
                if fx.child_stages then walk(fx.child_stages) end
            end
        end
    end
    walk(stages)
    return out
end

function PatchbayFxNodeFindDrop(targets, mx, my)
    -- Later entries are the deeper ones, so scanning backwards puts a nested
    -- container ahead of the container drawn around it.
    for i = #targets, 1, -1 do
        local t = targets[i]
        if mx >= t.x and mx <= t.x + t.w and my >= t.y and my <= t.y + t.h then return t end
    end
    return nil
end

function PatchbayFxNodeApplyDrop(track, source, target)
    if not source or not target then return false end
    local src_next = source.api_id + (source.stride or 1)
    if target.kind == "serial" then
        return PatchbayFxNodeMoveSerial(track, source.api_id, target.dest, src_next)
    elseif target.kind == "parallel" then
        local tgt = target.node
        local stage = target.stage
        local same_stage = false
        if stage then
            for _, fx in ipairs(stage) do
                if fx.api_id == source.api_id then same_stage = true break end
            end
        end
        if same_stage and #stage > 1 then
            local stride = stage[1].stride or 1
            -- Insert BEFORE the target when coming from below it, AFTER when
            -- coming from above. Always using "after" is what broke dragging a
            -- lane upwards: the slot after the lane above is the source's own.
            local dest = (source.api_id > tgt.api_id) and tgt.api_id
                or (tgt.api_id + stride)
            return PatchbayFxNodeReorderParallel(track, source.api_id, dest,
                stage[1].api_id, #stage, stride)
        end
        return PatchbayFxNodeMoveParallel(track, source.api_id, tgt.api_id,
            tgt.api_id + (tgt.stride or 1), src_next)
    elseif target.kind == "container" then
        return PatchbayFxNodeMoveIntoContainer(track, source.api_id, target.node, src_next)
    end
    return false
end

-- A drop mark you have to hunt for is no better than none. These only appear
-- while something is being dragged, so there is nothing to be shy about: solid
-- amber, dark ring for contrast against both a light and a dark canvas, and a
-- plus sign saying what dropping there does -- insert here.
-- Amber reads beautifully on a dark canvas and vanishes on a light one, where
-- it sits only 28 luminance steps from the background. So the mark follows the
-- theme: bright amber on dark, deep amber on light, and the hovered state moves
-- further from the background either way rather than simply getting brighter.
function PatchbayFxNodeDropMarkColors(hot)
    if PatchbayFxSchemaThemeIsLight() then
        if hot then return 0x8F5200FF, 0xFFF2D8FF end
        return 0xC77A00E8, 0xFFF2D8FF
    end
    if hot then return 0xFFE9A8FF, 0x1A1200FF end
    return 0xFFD36BE8, 0x241A00DD
end

function PatchbayFxNodeDrawDropMark(dl, cx, cy, rad, hot)
    local fill, ink = PatchbayFxNodeDropMarkColors(hot)
    if hot then
        -- A halo, so the one under the cursor is unmistakable among the rest.
        r.ImGui_DrawList_AddCircle(dl, cx, cy, rad * 1.9, 0xFFD36B70, 0, math.max(2, rad * 0.35))
    end
    r.ImGui_DrawList_AddCircleFilled(dl, cx, cy, rad + 1.5, 0x00000090)
    r.ImGui_DrawList_AddCircleFilled(dl, cx, cy, rad, fill)
    local arm = rad * 0.52
    local thick = math.max(1.6, rad * 0.26)
    r.ImGui_DrawList_AddLine(dl, cx - arm, cy, cx + arm, cy, ink, thick)
    r.ImGui_DrawList_AddLine(dl, cx, cy - arm, cx, cy + arm, ink, thick)
end

-- One source for the size, so the grab area can be checked against what is
-- actually drawn: a mark you can see but cannot hit is a lie.
function PatchbayFxNodeDropMarkRadius(dims, hot)
    local rad = math.max(6, 9 * dims.zoom)
    return hot and rad * 1.35 or rad
end

function PatchbayFxNodeDrawDropTargets(dl, targets, hovered, dims)
    for _, t in ipairs(targets) do
        local on = rawequal(t, hovered)
        if t.kind == "serial" then
            local cx, cy = t.cx or (t.x + t.w * 0.5), t.cy or (t.y + t.h * 0.5)
            PatchbayFxNodeDrawDropMark(dl, cx, cy,
                PatchbayFxNodeDropMarkRadius(dims, on), on)
        elseif on then
            local col = (t.kind == "container") and 0x6FD88AFF or 0xFFD36BFF
            r.ImGui_DrawList_AddRect(dl, t.x, t.y, t.x + t.w, t.y + t.h, col,
                math.max(3, 6 * dims.zoom), nil, 2.5)
        end
    end
end

-- The dragged node is re-found by address every frame rather than held onto:
-- the layout is rebuilt whenever the chain changes, and a kept reference would
-- go on describing a plugin that has already moved.
function PatchbayFxNodeFindByApi(stages, api)
    for _, st in ipairs(stages) do
        for _, fx in ipairs(st) do
            if fx.api_id == api then return fx end
            if fx.child_stages then
                local deeper = PatchbayFxNodeFindByApi(fx.child_stages, api)
                if deeper then return deeper end
            end
        end
    end
    return nil
end

function PatchbayFxNodeDrawDragGhost(ctx, dl, mx, my, name)
    local text_h = r.ImGui_GetTextLineHeight(ctx)
    local tw = r.ImGui_CalcTextSize(ctx, name)
    local pad = 6
    local x, y = mx + 14, my + 10
    r.ImGui_DrawList_AddRectFilled(dl, x, y, x + tw + pad * 2, y + text_h + pad, 0x000000C0, 4)
    r.ImGui_DrawList_AddRect(dl, x, y, x + tw + pad * 2, y + text_h + pad, 0xFFD36BFF, 4, nil, 1.2)
    r.ImGui_DrawList_AddText(dl, x + pad, y + pad * 0.5, 0xFFFFFFFF, name)
end

-- ---------------------------------------------------------------------------
-- Adding an FX from the node view
--
-- The plugin list comes from Sexan's FX Browser parser, which TK FX BROWSER
-- already loads: running as its module, ReadFXFile is simply a global that is
-- there. The standalone has no such host, so it loads the parser itself. Both
-- paths end at the same flat, searchable list.
--
-- Deliberately a search box rather than the prototype's cascading category
-- menus: in a graph you are pointing at a spot and want a plugin in it, and
-- typing three letters beats walking a folder tree. The category structure is
-- still in the prototype if that turns out to be wrong.
-- ---------------------------------------------------------------------------

PB.fx_view_add_open = false
PB.fx_view_add_focus = false
PB.fx_view_add_filter = ""
PB.fx_view_add_slot = nil
PB.fx_view_add_label = ""
PB.fx_view_add_items = nil
PB.fx_view_add_error = nil

local function PatchbayFxNodeStr(value)
    if type(value) == "string" and value ~= "" then return value end
    return nil
end

-- Only strings count, and only NAMED fields. The positional entry[1]/entry[2]
-- fallback the prototype used is what made the real list unreadable: Sexan's
-- FX_LIST is a flat array of ~3000 plugin strings, so entry[1]/entry[2] made
-- the whole list look like one plugin called "Container" whose addname was
-- "Video processor". Array members are entries in their own right and are
-- walked, never read as this table's own fields.
function PatchbayFxNodeAddEntry(entry)
    if type(entry) == "string" then return entry, entry end
    if type(entry) ~= "table" then return nil, nil end
    local name = PatchbayFxNodeStr(entry.name) or PatchbayFxNodeStr(entry.fxname)
        or PatchbayFxNodeStr(entry.fxName) or PatchbayFxNodeStr(entry.fname)
        or PatchbayFxNodeStr(entry.FX_NAME)
    local add = PatchbayFxNodeStr(entry.addname) or PatchbayFxNodeStr(entry.fullname) or name
    if not name and not add then return nil, nil end
    return (name or add), (add or name)
end

-- Sexan's list is a nest of category tables whose exact shape has changed
-- across versions, so this walks whatever it is and keeps every leaf that looks
-- like a plugin, de-duplicated by the name REAPER will be asked to add.
-- Sexan's FX_LIST is a flat array of plugin strings; the category files have
-- structure. This copes with both: an array part means "these are entries",
-- named string fields describe the table itself and are never added.
function PatchbayFxNodeFlatten(obj, items, seen, depth)
    if depth > 8 then return end
    if type(obj) == "string" then
        if obj ~= "" and not seen[obj] then
            items[#items + 1] = { display = obj, addname = obj }
            seen[obj] = true
        end
        return
    end
    if type(obj) ~= "table" then return end

    if #obj == 0 then
        -- No array part, so this table can only be describing itself.
        local display, addname = PatchbayFxNodeAddEntry(obj)
        if display and addname and not seen[addname] then
            items[#items + 1] = { display = display, addname = addname }
            seen[addname] = true
        end
    else
        for i = 1, #obj do
            PatchbayFxNodeFlatten(obj[i], items, seen, depth + 1)
        end
    end

    -- Sub-tables filed under a name (category-by-key structures) still count.
    for key, value in pairs(obj) do
        if type(key) ~= "number" and type(value) == "table" then
            PatchbayFxNodeFlatten(value, items, seen, depth + 1)
        end
    end
end

function PatchbayFxNodeLoadAddItems(force)
    if PB.fx_view_add_items and not force then return PB.fx_view_add_items end
    if type(ReadFXFile) ~= "function" then
        local parser = r.GetResourcePath() .. "/Scripts/Sexan_Scripts/FX/Sexan_FX_Browser_ParserV7.lua"
        if not FileExists(parser) then
            PB.fx_view_add_error = "Sexan FX Browser Parser V7 not found."
            return nil
        end
        local ok, err = pcall(dofile, parser)
        if not ok then
            PB.fx_view_add_error = "Sexan parser error: " .. tostring(err)
            return nil
        end
    end
    local list
    if type(ReadFXFile) == "function" then
        local ok, res = pcall(ReadFXFile)
        if ok then list = res end
    end
    -- MakeFXFiles rescans and is slow, so it is only reached when the cached
    -- file is missing or unreadable.
    if not list and type(MakeFXFiles) == "function" then
        local ok, res = pcall(MakeFXFiles)
        if ok then list = res end
    end
    if not list then
        PB.fx_view_add_error = "Could not load the FX list."
        return nil
    end
    local items, seen = {}, {}
    PatchbayFxNodeFlatten(list, items, seen, 0)
    table.sort(items, function(a, b)
        return (a.display or ""):lower() < (b.display or ""):lower()
    end)
    PB.fx_view_add_items = items
    PB.fx_view_add_error = nil
    return items
end

-- Every whitespace-separated token must appear somewhere, so "fab pro q" finds
-- FabFilter Pro-Q without caring about order or punctuation.
function PatchbayFxNodeFilterAddItems(filter, max_items)
    local items = PatchbayFxNodeLoadAddItems(false)
    if not items then return {} end
    filter = tostring(filter or ""):lower():gsub("^%s*(.-)%s*$", "%1")
    max_items = max_items or 40
    local out = {}
    for i = 1, #items do
        local item = items[i]
        local hay = ((item.display or "") .. " " .. (item.addname or "")):lower()
        local match = true
        if filter ~= "" then
            for token in filter:gmatch("%S+") do
                if not hay:find(token, 1, true) then match = false break end
            end
        end
        if match then
            out[#out + 1] = item
            if #out >= max_items then break end
        end
    end
    return out
end

-- TrackFX_AddByName takes an insert position as -1000 minus the slot. The
-- negative form is used for container slots too: TK_Probe_Container_Rack
-- confirmed that on REAPER 7.75, and it is what the shipped Kit Maker relies
-- on. (The old prototype passed a bare positive container address here, which
-- is a different call entirely.)
function PatchbayFxNodeAddSlot(kind, track, node)
    if kind == "end" then
        return -1000 - (r.TrackFX_GetCount(track) or 0)
    elseif kind == "after" and node then
        return -1000 - (node.api_id + (node.stride or 1))
    elseif kind == "inside" and node then
        local slot = PatchbayFxNodeContainerEndSlot(track, node)
        if not slot then return nil end
        return -1000 - slot
    end
    return nil
end

function PatchbayFxNodeAddFx(track, slot, addname)
    if IsAllLockedCfg(GetConfig()) then return false, "FX actions locked." end
    if not track or not r.ValidatePtr(track, "MediaTrack*") then return false, "Track is gone." end
    addname = tostring(addname or "")
    if addname == "" then return false, "No FX chosen." end
    if slot == nil then return false, "Could not work out where to insert." end
    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)
    local new_index = r.TrackFX_AddByName(track, addname, false, slot)
    r.PreventUIRefresh(-1)
    r.TrackList_AdjustWindows(false)
    r.UpdateArrange()
    r.Undo_EndBlock("Patchbay: add FX", -1)
    PatchbayFxNodeInvalidate()
    if not new_index or new_index < 0 then return false, "REAPER would not add that FX." end
    return true, nil
end

-- ---------------------------------------------------------------------------
-- Browsing instead of searching
--
-- Sexan's category file already carries four of the five groupings: ALL
-- PLUGINS, CATEGORY, DEVELOPER and FOLDERS, each a list of named buckets with
-- an `fx` array. The fifth, TK FX BROWSER's own custom folders, lives in
-- custom_folders.json next to this script in a different shape entirely --
-- { name = { plugins = {...}, subfolders = { ... } } } -- and nests without
-- limit, so it is normalised into the same node the others use.
--
-- The search box stays: typing filters the whole list flat and the menus step
-- aside. Browsing is for when you do not know the name, searching for when you
-- do, and neither is a good substitute for the other.
-- ---------------------------------------------------------------------------

PB.fx_view_cat_groups = nil
PB.fx_view_custom_folders = nil

function PatchbayFxNodeLoadCategories(force)
    if PB.fx_view_cat_groups and not force then return PB.fx_view_cat_groups end
    -- Loading the parser is the add-list's job; this only wants its second
    -- return value, so it goes through the same function to avoid a second
    -- dofile of Sexan's parser.
    PatchbayFxNodeLoadAddItems(force)
    if type(ReadFXFile) ~= "function" then return nil end
    local ok, _, cat = pcall(ReadFXFile)
    if not ok or type(cat) ~= "table" then return nil end
    local groups = {}
    for _, group in ipairs(cat) do
        local gname = PatchbayFxNodeStr(group.name)
        if gname and type(group.list) == "table" then
            local buckets = {}
            for _, bucket in ipairs(group.list) do
                local bname = PatchbayFxNodeStr(bucket.name)
                if bname and type(bucket.fx) == "table" and #bucket.fx > 0 then
                    buckets[#buckets + 1] = { name = bname, fx = bucket.fx }
                end
            end
            -- FX CHAINS and TRACK TEMPLATES come back with unnamed buckets and
            -- no fx arrays; they are not plugins and are dropped here.
            if #buckets > 0 then
                groups[#groups + 1] = { name = gname, buckets = buckets }
            end
        end
    end
    PB.fx_view_cat_groups = groups
    return groups
end

-- { name = { plugins = {..}, subfolders = { ... } } } into
-- { name = ..., fx = {..}, subs = { ...same... } }
function PatchbayFxNodeNormaliseFolders(node, depth)
    if type(node) ~= "table" or depth > 6 then return {} end
    local out = {}
    for key, value in pairs(node) do
        if type(key) == "string" and type(value) == "table" then
            local entry = { name = key, fx = {}, subs = {} }
            local plugins = value.plugins
            if type(plugins) == "table" then
                for _, p in ipairs(plugins) do
                    if PatchbayFxNodeStr(p) then entry.fx[#entry.fx + 1] = p end
                end
            end
            -- Older saves put plugin names straight in the array part.
            for _, p in ipairs(value) do
                if PatchbayFxNodeStr(p) then entry.fx[#entry.fx + 1] = p end
            end
            if type(value.subfolders) == "table" then
                entry.subs = PatchbayFxNodeNormaliseFolders(value.subfolders, depth + 1)
            end
            if #entry.fx > 0 or #entry.subs > 0 then out[#out + 1] = entry end
        end
    end
    table.sort(out, function(a, b) return a.name:lower() < b.name:lower() end)
    return out
end

function PatchbayFxNodeLoadCustomFolders(force)
    if PB.fx_view_custom_folders and not force then return PB.fx_view_custom_folders end
    local path = (r.GetResourcePath() .. "/Scripts/TK Scripts/FX/custom_folders.json"):gsub("\\", "/")
    if not FileExists(path) then
        PB.fx_view_custom_folders = {}
        return PB.fx_view_custom_folders
    end
    local file = io.open(path, "r")
    if not file then
        PB.fx_view_custom_folders = {}
        return PB.fx_view_custom_folders
    end
    local raw = file:read("*a")
    file:close()
    local decoded = NotesJsonDecode(raw)
    PB.fx_view_custom_folders = PatchbayFxNodeNormaliseFolders(decoded, 0)
    return PB.fx_view_custom_folders
end

-- ---------------------------------------------------------------------------
-- Menu rendering
-- ---------------------------------------------------------------------------

function PatchbayFxNodeMenuPick(ctx, track, addname, label)
    if not r.ImGui_MenuItem(ctx, label) then return false end
    local ok, err = PatchbayFxNodeAddFx(track, PB.fx_view_add_slot, addname)
    if not ok and err then r.ShowMessageBox(tostring(err), "Patchbay", 0) end
    return true
end

-- Every plugin in the bucket, however many. An earlier version capped these at
-- 250 to keep a 1299-entry menu from being built, which was solving a problem
-- nobody has: ImGui only walks the contents of a menu that is actually open,
-- and scrolls it when it outgrows the screen. TK FX BROWSER and Sexan's own
-- menus list the lot, and a cap here would only make this one worse than both.
function PatchbayFxNodeMenuList(ctx, track, fx_list)
    local picked = false
    for i = 1, #fx_list do
        local name = fx_list[i]
        if PatchbayFxNodeStr(name) then
            -- ## keeps duplicate labels from sharing an ID; a plugin can sit in
            -- more than one folder.
            if PatchbayFxNodeMenuPick(ctx, track, name, name .. "##m" .. i) then picked = true end
        end
    end
    return picked
end

function PatchbayFxNodeMenuFolders(ctx, track, folders, depth)
    local picked = false
    for _, entry in ipairs(folders) do
        local count = #entry.fx + #entry.subs
        if count > 0 and r.ImGui_BeginMenu(ctx, entry.name .. "##f" .. depth .. entry.name) then
            if #entry.subs > 0 and depth < 5 then
                if PatchbayFxNodeMenuFolders(ctx, track, entry.subs, depth + 1) then picked = true end
                if #entry.fx > 0 then r.ImGui_Separator(ctx) end
            end
            if PatchbayFxNodeMenuList(ctx, track, entry.fx) then picked = true end
            r.ImGui_EndMenu(ctx)
        end
    end
    return picked
end

function PatchbayFxNodeMenuBrowse(ctx, track)
    local picked = false
    local groups = PatchbayFxNodeLoadCategories(false)
    if groups then
        for _, group in ipairs(groups) do
            if r.ImGui_BeginMenu(ctx, group.name .. "##g" .. group.name) then
                for _, bucket in ipairs(group.buckets) do
                    if r.ImGui_BeginMenu(ctx, string.format("%s (%d)##b%s", bucket.name, #bucket.fx, bucket.name)) then
                        if PatchbayFxNodeMenuList(ctx, track, bucket.fx) then picked = true end
                        r.ImGui_EndMenu(ctx)
                    end
                end
                r.ImGui_EndMenu(ctx)
            end
        end
    else
        r.ImGui_TextDisabled(ctx, "No category data")
    end

    local custom = PatchbayFxNodeLoadCustomFolders(false)
    if custom and #custom > 0 then
        r.ImGui_Separator(ctx)
        if r.ImGui_BeginMenu(ctx, "MY FOLDERS##custom") then
            if PatchbayFxNodeMenuFolders(ctx, track, custom, 0) then picked = true end
            r.ImGui_EndMenu(ctx)
        end
    end
    return picked
end

function PatchbayFxNodeOpenAdd(kind, track, node, label)
    local slot = PatchbayFxNodeAddSlot(kind, track, node)
    PB.fx_view_add_slot = slot
    PB.fx_view_add_label = label or "chain"
    PB.fx_view_add_filter = ""
    PB.fx_view_add_open = true
    PB.fx_view_add_focus = true
    PatchbayFxNodeInvalidateBrowse()
end

function PatchbayFxNodeAddPopup(ctx, track)
    if PB.fx_view_add_open then
        r.ImGui_OpenPopup(ctx, "PatchbayFxNodeAdd")
        PB.fx_view_add_open = false
    end
    if not r.ImGui_BeginPopup(ctx, "PatchbayFxNodeAdd") then return end
    r.ImGui_Text(ctx, "Add FX -- " .. tostring(PB.fx_view_add_label or ""))
    r.ImGui_Separator(ctx)
    if PB.fx_view_add_focus and r.ImGui_SetKeyboardFocusHere then
        r.ImGui_SetKeyboardFocusHere(ctx)
        PB.fx_view_add_focus = false
    end
    r.ImGui_PushItemWidth(ctx, 300)
    local changed, txt = r.ImGui_InputText(ctx, "##fx_add_filter", PB.fx_view_add_filter or "")
    r.ImGui_PopItemWidth(ctx)
    if changed then PB.fx_view_add_filter = txt end

    local filter = tostring(PB.fx_view_add_filter or ""):gsub("^%s*(.-)%s*$", "%1")
    if PB.fx_view_add_error then
        r.ImGui_TextDisabled(ctx, PB.fx_view_add_error)
    elseif filter == "" then
        -- Nothing typed: browse.
        r.ImGui_Separator(ctx)
        if PatchbayFxNodeMenuBrowse(ctx, track) then r.ImGui_CloseCurrentPopup(ctx) end
    else
        local matches = PatchbayFxNodeFilterAddItems(filter, 60)
        if #matches == 0 then
            r.ImGui_TextDisabled(ctx, "Nothing matches")
        elseif r.ImGui_BeginChild then
            if r.ImGui_BeginChild(ctx, "##fx_add_list", 320, 300) then
                for i = 1, #matches do
                    if r.ImGui_Selectable(ctx, matches[i].display .. "##add" .. i) then
                        local ok, err = PatchbayFxNodeAddFx(track, PB.fx_view_add_slot, matches[i].addname)
                        if not ok and err then
                            r.ShowMessageBox(tostring(err), "Patchbay", 0)
                        end
                        r.ImGui_CloseCurrentPopup(ctx)
                    end
                end
                r.ImGui_EndChild(ctx)
            end
        end
    end
    r.ImGui_EndPopup(ctx)
end

function PatchbayFxNodeFrame(ctx, origin_x, origin_y, avail_w, avail_h)
    if not PB.fx_view_guid then return false end
    local follow_to = PatchbayFxNodeFollowPoll()
    if follow_to then PatchbayFxNodeEnter(follow_to) end
    local track = PatchbayFxNodeResolveTrack()
    -- The track can be deleted while we are inside it. Fall back rather than
    -- render a view of nothing.
    if not track then PatchbayFxNodeExit() return false end

    local dl = r.ImGui_GetWindowDrawList(ctx)
    local panel_bg, panel_border, panel_text = PatchbayFxSchemaPalette("panel")
    local grid_bg = _G.patchbay_grid_bg_col or 0x1A1A1AFF
    -- Bled past every edge: the canvas child is drawn with a border, so its
    -- content region begins just inside the frame and a rect starting exactly
    -- at origin_y leaves a hairline where the track graph below shows through.
    local bleed = 8
    r.ImGui_DrawList_AddRectFilled(dl, origin_x - bleed, origin_y - bleed,
        origin_x + avail_w + bleed, origin_y + avail_h + bleed, grid_bg)

    -- The same dotted grid the track canvas draws, stepped by the same GRID and
    -- carried by this view's own pan. Left unscaled by zoom, exactly as the
    -- track canvas leaves it, so the two read as one surface.
    local grid_dot = _G.patchbay_grid_dot_col or 0x2A2A2AFF
    local gx = origin_x + ((PB.fx_view_off_x % GRID) + GRID) % GRID
    while gx < origin_x + avail_w do
        local gy = origin_y + ((PB.fx_view_off_y % GRID) + GRID) % GRID
        while gy < origin_y + avail_h do
            r.ImGui_DrawList_AddRectFilled(dl, gx - 1, gy - 1, gx + 1, gy + 1, grid_dot)
            gy = gy + GRID
        end
        gx = gx + GRID
    end

    PatchbayFxNodeShotBeginFrame()
    local dims = PatchbayFxNodeDims(PB.fx_view_zoom)
    local layout = PatchbayFxNodeCached(track, dims)

    local content_w = layout.w + dims.edge_w * 2 + dims.col_gap * 2
    local content_h = math.max(layout.h, dims.node_h)
    if PB.fx_view_fit_pending then
        PB.fx_view_off_x = (avail_w - content_w) * 0.5
        PB.fx_view_off_y = (avail_h - content_h) * 0.5
        PB.fx_view_fit_pending = false
    end

    local base_x = origin_x + PB.fx_view_off_x
    local base_y = origin_y + PB.fx_view_off_y
    local mid_y = base_y + content_h * 0.5

    PatchbayFxNodePlace(layout.stages, base_x + dims.edge_w + dims.col_gap, base_y, content_h, dims)
    PatchbayFxNodeApplyPositions(track, layout.stages, base_x, base_y, dims.zoom)
    layout.band_top = base_y
    layout.band_h = content_h

    -- The edge boxes are worked out here, ahead of the overlap pass, because
    -- they are obstacles like any node and it has to be able to see them.
    local in_x = base_x
    local out_x = base_x + content_w - dims.edge_w
    local edge_h = math.max(dims.node_h, 34 * dims.zoom)
    local in_y, out_y = mid_y - edge_h * 0.5, mid_y - edge_h * 0.5
    local edge_pos = PatchbayFxNodeLoadPositions(track)
    local pin_in = edge_pos[PATCHBAY_FX_EDGE_IN]
    if pin_in then in_x, in_y = base_x + pin_in.x * dims.zoom, base_y + pin_in.y * dims.zoom end
    local pin_out = edge_pos[PATCHBAY_FX_EDGE_OUT]
    if pin_out then out_x, out_y = base_x + pin_out.x * dims.zoom, base_y + pin_out.y * dims.zoom end
    layout.edge_w = dims.edge_w
    layout.edge_h = edge_h
    layout.edge_in_x, layout.edge_in_y = in_x, in_y
    layout.edge_out_x, layout.edge_out_y = out_x, out_y

    -- Nothing that is currently in your hand takes part: it belongs under the
    -- cursor, and both drags are applied after this.
    local edrag = PB.fx_view_edge_drag
    in_x, in_y, out_x, out_y = PatchbayFxNodeResolveOverlaps(layout, dims,
        (PB.fx_view_drag and PB.fx_view_drag.active) and PB.fx_view_drag.api_id or nil,
        (edrag and edrag.active) and edrag.which or nil)

    -- A drag in progress moves the node now, before the frame is drawn. Cables
    -- read their ends off the node rectangles, so they stretch along with it
    -- for free.
    if PB.fx_view_drag and PB.fx_view_drag.active then
        local dmx, dmy = r.ImGui_GetMousePos(ctx)
        local dragged = PatchbayFxNodeFindByApi(layout.stages, PB.fx_view_drag.api_id)
        if dragged then
            PB.fx_view_drag.layout_x = dragged.x
            PB.fx_view_drag.layout_y = dragged.y
            PB.fx_view_drag.layout_w = dragged.w
            PB.fx_view_drag.layout_h = dragged.h
            PatchbayFxNodeShiftOne(dragged,
                (dmx - (PB.fx_view_drag.grab_x or 0)) - dragged.x,
                (dmy - (PB.fx_view_drag.grab_y or 0)) - dragged.y)
        end
    end

    -- And the box being dragged, last of all, so it sits under the cursor
    -- rather than where the resolver would rather have it.
    if edrag and edrag.active then
        local emx, emy = r.ImGui_GetMousePos(ctx)
        local ex, ey = emx - (edrag.grab_x or 0), emy - (edrag.grab_y or 0)
        if edrag.which == "in" then in_x, in_y = ex, ey else out_x, out_y = ex, ey end
    end

    PatchbayFxNodeDrawEdge(ctx, dl, in_x, in_y, dims.edge_w, edge_h, "IN", dims)
    PatchbayFxNodeDrawEdge(ctx, dl, out_x, out_y, dims.edge_w, edge_h, "OUT", dims)
    layout.edge_in_x = in_x
    layout.edge_out_x = out_x
    layout.edge_in_y = in_y
    layout.edge_out_y = out_y
    layout.edge_h = edge_h
    layout.edge_w = dims.edge_w
    PatchbayFxNodeDrawEdgePins(ctx, dl, layout, dims, track, PatchbayFxNodeCanvasInk(true))

    -- Set before the branch: an empty chain still has one cable, from IN
    -- straight to OUT, and it is a perfectly good place to drop the first FX.
    layout.link_left = in_x + dims.edge_w
    layout.link_right = out_x
    layout.link_mid = mid_y
    layout.link_left_y = in_y + edge_h * 0.5
    layout.link_right_y = out_y + edge_h * 0.5

    if #layout.stages == 0 then
        local msg = "No FX on this track"
        local tw = r.ImGui_CalcTextSize(ctx, msg)
        PatchbayFxNodeCable(dl, in_x + dims.edge_w, in_y + edge_h * 0.5,
            out_x, out_y + edge_h * 0.5, PatchbayFxNodeCanvasInk(false))
        r.ImGui_DrawList_AddText(dl, base_x + (content_w - tw) * 0.5,
            mid_y - 26 * dims.zoom, PatchbayFxNodeCanvasInk(true), msg)
    else
        PatchbayFxNodeDrawRouting(ctx, dl, layout, dims, track)
        PatchbayFxNodeDrawStages(ctx, dl, layout.stages, dims,
            in_x + dims.edge_w, mid_y, out_x,
            PatchbayFxNodeCanvasInk(false), PatchbayFxNodeCanvasInk(true),
            in_y + edge_h * 0.5, out_y + edge_h * 0.5)
    end

    -- Header strip: which track, and the way back out.
    local _, track_name = r.GetTrackName(track)
    local head = "FX  ·  " .. tostring(track_name or "Track")
    local head_h = 26
    r.ImGui_DrawList_AddRectFilled(dl, origin_x - bleed, origin_y - bleed,
        origin_x + avail_w + bleed, origin_y + head_h, panel_bg)
    r.ImGui_DrawList_AddLine(dl, origin_x - bleed, origin_y + head_h,
        origin_x + avail_w + bleed, origin_y + head_h, panel_border, 1)
    local head_x = (PB.fx_view_head_x or (origin_x + 78)) + 6
    r.ImGui_DrawList_AddText(dl, head_x, origin_y + (head_h - r.ImGui_GetTextLineHeight(ctx)) * 0.5,
        panel_text, head)

    r.ImGui_PushID(ctx, "fx_node_view")
    r.ImGui_SetCursorScreenPos(ctx, origin_x + 6, origin_y + 3)
    if r.ImGui_Button(ctx, "< Tracks", 62, head_h - 6) then
        PatchbayFxNodeExit()
        r.ImGui_PopID(ctx)
        return true
    end
    local btn_x = origin_x + 74
    if PatchbayFxNodeHasPositions(track) then
        r.ImGui_SetCursorScreenPos(ctx, btn_x, origin_y + 3)
        if r.ImGui_Button(ctx, "Auto layout", 78, head_h - 6) then
            PatchbayFxNodeClearAllPositions(track)
            PatchbayFxNodeInvalidate()
        end
        if r.ImGui_IsItemHovered(ctx) then
            r.ImGui_SetTooltip(ctx, "Put every node back where the chain puts it")
        end
        btn_x = btn_x + 84
    end
    if r.ImGui_CreateImage then
        r.ImGui_SetCursorScreenPos(ctx, btn_x, origin_y + 3)
        local on = PatchbayFxNodeShotsOn()
        if on then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x3A6EA5FF) end
        if r.ImGui_Button(ctx, "Shots", 46, head_h - 6) then PatchbayFxNodeShotsToggle() end
        if on then r.ImGui_PopStyleColor(ctx, 1) end
        if r.ImGui_IsItemHovered(ctx) then
            r.ImGui_SetTooltip(ctx, "Show TK FX BROWSER screenshots in the nodes")
        end
        btn_x = btn_x + 52
    end
    r.ImGui_SetCursorScreenPos(ctx, btn_x, origin_y + 3)
    local routing = PatchbayFxNodeRoutingOn()
    if routing then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x3A6EA5FF) end
    if r.ImGui_Button(ctx, "Routing", 56, head_h - 6) then PatchbayFxNodeRoutingToggle() end
    if routing then r.ImGui_PopStyleColor(ctx, 1) end
    if r.ImGui_IsItemHovered(ctx) then
        r.ImGui_SetTooltip(ctx, "Show every channel cable, including the plain stereo pair")
    end
    btn_x = btn_x + 62

    r.ImGui_SetCursorScreenPos(ctx, btn_x, origin_y + 3)
    local tidy = PatchbayFxNodePreventOverlap()
    if tidy then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x3A6EA5FF) end
    if r.ImGui_Button(ctx, "No overlap", 74, head_h - 6) then
        PatchbayFxNodePreventOverlapToggle()
    end
    if tidy then r.ImGui_PopStyleColor(ctx, 1) end
    if r.ImGui_IsItemHovered(ctx) then
        r.ImGui_SetTooltip(ctx, "Keep nodes and the IN/OUT boxes clear of each other"
            .. "\nseparate from the track graph's own setting")
    end
    btn_x = btn_x + 80

    r.ImGui_SetCursorScreenPos(ctx, btn_x, origin_y + 3)
    local following = PatchbayFxNodeFollowOn()
    if following then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x3A6EA5FF) end
    if r.ImGui_Button(ctx, "Follow", 50, head_h - 6) then PatchbayFxNodeFollowToggle() end
    if following then r.ImGui_PopStyleColor(ctx, 1) end
    if r.ImGui_IsItemHovered(ctx) then
        r.ImGui_SetTooltip(ctx, "Show whichever track you select in REAPER")
    end
    btn_x = btn_x + 56
    PB.fx_view_head_x = btn_x

    -- The canvas itself: pan on left or middle drag, zoom on the wheel, both
    -- kept in PB so leaving the view does not disturb the track graph's own
    -- pan and zoom.
    r.ImGui_SetCursorScreenPos(ctx, origin_x, origin_y + head_h)
    if r.ImGui_SetNextItemAllowOverlap then r.ImGui_SetNextItemAllowOverlap(ctx) end
    r.ImGui_InvisibleButton(ctx, "##fx_node_bg", avail_w, math.max(1, avail_h - head_h))
    local bg_active = r.ImGui_IsItemActive(ctx)
    local bg_hovered = r.ImGui_IsItemHovered(ctx)
    local mx, my = r.ImGui_GetMousePos(ctx)

    if bg_active and not PB.fx_view_drag and not PB.fx_view_pin_drag
        and not PB.fx_view_edge_drag then
        local dx, dy = r.ImGui_GetMouseDragDelta(ctx, 0, 0, 0)
        if dx ~= 0 or dy ~= 0 then
            PB.fx_view_off_x = PB.fx_view_off_x + dx
            PB.fx_view_off_y = PB.fx_view_off_y + dy
            r.ImGui_ResetMouseDragDelta(ctx, 0)
        end
    end
    if r.ImGui_IsWindowHovered(ctx) and r.ImGui_IsMouseDragging(ctx, 2) then
        local dx, dy = r.ImGui_GetMouseDragDelta(ctx, 2, 0, 0)
        if dx ~= 0 or dy ~= 0 then
            PB.fx_view_off_x = PB.fx_view_off_x + dx
            PB.fx_view_off_y = PB.fx_view_off_y + dy
            r.ImGui_ResetMouseDragDelta(ctx, 2)
        end
    end
    if r.ImGui_IsWindowHovered(ctx) then
        local wheel = r.ImGui_GetMouseWheel(ctx)
        if wheel ~= 0 then
            local wx = (mx - origin_x - PB.fx_view_off_x) / PB.fx_view_zoom
            local wy = (my - origin_y - PB.fx_view_off_y) / PB.fx_view_zoom
            local factor = (wheel > 0) and 1.1 or (1 / 1.1)
            local new_zoom = math.max(0.35, math.min(2.5, PB.fx_view_zoom * factor))
            if new_zoom ~= PB.fx_view_zoom then
                PB.fx_view_zoom = new_zoom
                PB.fx_view_off_x = mx - origin_x - wx * new_zoom
                PB.fx_view_off_y = my - origin_y - wy * new_zoom
            end
        end
    end

    -- Pins first: they sit ON the node's edge, so the body rectangle contains
    -- them and a plain hit test would always win.
    local pins = PatchbayFxNodeCollectPins(layout, dims, track)
    local on_pin = PatchbayFxNodePinAt(pins, mx, my, dims)

    if PB.fx_view_pin_drag then
        local drag = PB.fx_view_pin_drag
        local hot = PatchbayFxNodeDrawPinDrag(ctx, dl, pins, drag, mx, my, dims, track)
        if r.ImGui_IsMouseReleased(ctx, 0) then
            local drop_ok, why = PatchbayFxNodePinDropOk(drag, hot)
            if hot and drop_ok then
                local ok, err = PatchbayFxNodeConnectPins(track, drag, hot)
                if not ok and err then r.ShowMessageBox(tostring(err), "Patchbay", 0) end
            elseif hot and why then
                r.ShowMessageBox(tostring(why), "Patchbay", 0)
            end
            PB.fx_view_pin_drag = nil
        elseif not r.ImGui_IsMouseDown(ctx, 0) then
            PB.fx_view_pin_drag = nil
        end
    elseif bg_hovered and on_pin and on_pin.side == "out" and r.ImGui_IsMouseClicked(ctx, 0)
        and not IsAllLockedCfg(GetConfig()) then
        PB.fx_view_pin_drag = on_pin
    end

    if on_pin and bg_hovered and not PB.fx_view_pin_drag then
        local low, high = PatchbayFxNodePinMask(track, on_pin)
        local label, _ = PatchbayFxNodeChannelLabel(low, high)
        r.ImGui_SetTooltip(ctx, string.format("%s pin %d  ->  ch %s%s",
            on_pin.side == "out" and "Output" or "Input", on_pin.index, label,
            on_pin.side == "out" and "\ndrag to an input pin to wire it"
                or "\nright-click to disconnect"))
    end
    if on_pin and bg_hovered and not on_pin.edge and r.ImGui_IsMouseClicked(ctx, 1) then
        PatchbayFxNodeClearPin(track, on_pin)
    end

    -- Moving the IN and OUT boxes. Checked after the pins, which sit on their
    -- edges: grabbing a pin starts a cable, and the box must not swallow that.
    local on_edge = (not on_pin) and PatchbayFxNodeEdgeAt(layout, mx, my) or nil
    if on_edge and bg_hovered and not PB.fx_view_pin_drag and not PB.fx_view_edge_drag
        and r.ImGui_IsMouseClicked(ctx, 0) then
        local ex, ey = PatchbayFxNodeEdgeRect(layout, on_edge)
        PB.fx_view_edge_drag = { which = on_edge, x0 = mx, y0 = my, active = false,
                                 grab_x = mx - ex, grab_y = my - ey }
    end
    if PB.fx_view_edge_drag then
        local ed = PB.fx_view_edge_drag
        if not ed.active then
            local dx, dy = mx - ed.x0, my - ed.y0
            -- Armed, not yet dragging: a plain click stays a plain click.
            if (dx * dx + dy * dy) > 25 then ed.active = true end
        end
        if r.ImGui_IsMouseReleased(ctx, 0) or not r.ImGui_IsMouseDown(ctx, 0) then
            if ed.active then
                local key = (ed.which == "in") and PATCHBAY_FX_EDGE_IN or PATCHBAY_FX_EDGE_OUT
                local ex = mx - (ed.grab_x or 0)
                local ey = my - (ed.grab_y or 0)
                if PatchbayFxNodePreventOverlap() then
                    ex, ey = PatchbayFxNodeFreeSpot(
                        PatchbayFxNodeObstacles(layout, nil, ed.which),
                        ex, ey, layout.edge_w, layout.edge_h,
                        PatchbayFxNodeFreeStep(dims.zoom))
                end
                PatchbayFxNodeSetPosition(track, key,
                    (ex - base_x) / dims.zoom, (ey - base_y) / dims.zoom)
            end
            PB.fx_view_edge_drag = nil
        end
    end
    if on_edge and bg_hovered and not PB.fx_view_edge_drag then
        r.ImGui_SetTooltip(ctx, (on_edge == "in" and "Track input" or "Track output")
            .. "\ndrag to move  ·  right-click to put it back")
    end
    if on_edge and bg_hovered and r.ImGui_IsMouseClicked(ctx, 1) then
        PatchbayFxNodeClearPosition(track,
            (on_edge == "in") and PATCHBAY_FX_EDGE_IN or PATCHBAY_FX_EDGE_OUT)
    end

    local hit = (not on_pin) and (not on_edge)
        and PatchbayFxNodeHit(layout.stages, mx, my) or nil
    -- The bypass dot is hit-tested by hand rather than given its own ImGui
    -- item: the whole view runs off one invisible background button, and a
    -- widget per node would fight it for the mouse.
    local on_bypass = false
    local on_fold = false
    if hit then
        local bx, by, brad = PatchbayFxNodeBypassSpot(hit, dims)
        local dx, dy = mx - bx, my - by
        on_bypass = (dx * dx + dy * dy) <= (brad + 2) * (brad + 2)
        if hit.fx_type == "Container" and #hit.children > 0 then
            local fxx, fxy, fsize = PatchbayFxNodeFoldSpot(hit, dims)
            on_fold = math.abs(mx - fxx) <= fsize and math.abs(my - fxy) <= fsize
        end
    end
    if hit and bg_hovered then
        r.ImGui_SetTooltip(ctx, on_fold and (hit.folded and "Unfold container" or "Fold container")
            or on_bypass and (hit.enabled and "Bypass" or "Un-bypass")
            or (hit.full_name ~= "" and hit.full_name or hit.name))
    end
    if bg_hovered and r.ImGui_IsMouseClicked(ctx, 0) then
        if on_fold then
            PatchbayFxNodeToggleFold(track, hit.fxguid)
        elseif on_bypass then
            PatchbayFxNodeSetBypass(PatchbayFxNodeTarget(track, hit), hit.enabled)
        else
            PB.fx_view_sel_api = hit and hit.api_id or nil
            -- Armed, not yet dragging: a plain click must stay a plain click,
            -- so nothing happens until the mouse has actually travelled.
            if hit and not IsAllLockedCfg(GetConfig()) then
                PB.fx_view_drag = { api_id = hit.api_id, name = hit.name,
                                    x0 = mx, y0 = my, active = false,
                                    grab_x = mx - hit.x, grab_y = my - hit.y }
            end
        end
    end

    if PB.fx_view_drag then
        local drag = PB.fx_view_drag
        local source = PatchbayFxNodeFindByApi(layout.stages, drag.api_id)
        if not source then
            PB.fx_view_drag = nil
        else
            if not drag.active then
                local dx, dy = mx - drag.x0, my - drag.y0
                if (dx * dx + dy * dy) > 25 then drag.active = true end
            end
            if drag.active then
                local targets = PatchbayFxNodeCollectDropTargets(layout, dims, source, track)
                local over = PatchbayFxNodeFindDrop(targets, mx, my)
                PatchbayFxNodeDrawDropTargets(dl, targets, over, dims)
                if r.ImGui_IsMouseReleased(ctx, 0) then
                    if over then
                        -- Into the chain: the automatic layout is about to
                        -- change under it, so a pinned spot would be nonsense.
                        PatchbayFxNodeApplyDrop(track, source, over)
                        PatchbayFxNodeClearPosition(track, source.fxguid)
                    else
                        local nx = mx - (drag.grab_x or 0)
                        local ny = my - (drag.grab_y or 0)
                        if PatchbayFxNodePreventOverlap() then
                            nx, ny = PatchbayFxNodeFreeSpot(
                                PatchbayFxNodeObstacles(layout, source.api_id, nil),
                                nx, ny, source.w, source.h,
                                PatchbayFxNodeFreeStep(dims.zoom))
                        end
                        PatchbayFxNodeSetPosition(track, source.fxguid,
                            (nx - base_x) / dims.zoom, (ny - base_y) / dims.zoom)
                        PatchbayFxNodeInvalidate()
                    end
                    PB.fx_view_drag = nil
                end
            elseif r.ImGui_IsMouseReleased(ctx, 0) then
                PB.fx_view_drag = nil
            end
        end
    end
    if hit and bg_hovered and not on_bypass and not on_fold and r.ImGui_IsMouseDoubleClicked(ctx, 0) and r.TrackFX_Show then
        r.TrackFX_Show(track, hit.api_id, 3)
    end
    if bg_hovered and not on_edge and r.ImGui_IsMouseClicked(ctx, 1) then
        if hit then
            PB.fx_view_ctx_api = hit.api_id
            PB.fx_view_ctx_name = hit.name
            PB.fx_view_ctx_is_container = (hit.fx_type == "Container")
            PB.fx_view_ctx_open = true
        elseif not IsAllLockedCfg(GetConfig()) then
            PatchbayFxNodeOpenAdd("end", track, nil, "at the end of the chain")
        end
    end
    if PB.fx_view_drag and not r.ImGui_IsMouseDown(ctx, 0) then PB.fx_view_drag = nil end
    PatchbayFxNodePopups(ctx, track)
    PatchbayFxNodeAddPopup(ctx, track)
    if r.ImGui_IsKeyPressed and r.ImGui_Key_Escape and r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_Escape()) then
        PatchbayFxNodeExit()
    end
    r.ImGui_PopID(ctx)
    return true
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
        -- Ctrl+Z / Ctrl+Shift+Z / Ctrl+Y: while this window has focus the keys
        -- reach the script, not REAPER, so they did nothing at all -- only the
        -- arrow buttons could undo. They run the same native commands.
        local shift_held = r.ImGui_GetKeyMods and r.ImGui_Mod_Shift
            and (r.ImGui_GetKeyMods(ctx) & r.ImGui_Mod_Shift()) ~= 0
        if r.ImGui_Key_Z and PatchbayCtrlShortcutPressed(ctx, r.ImGui_Key_Z) then
            r.Main_OnCommand(shift_held and 40030 or 40029, 0)
        elseif r.ImGui_Key_Y and PatchbayCtrlShortcutPressed(ctx, r.ImGui_Key_Y) then
            r.Main_OnCommand(40030, 0)
        elseif #selected_tracks > 0 and PatchbayCtrlShortcutPressed(ctx, r.ImGui_Key_C) then
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
    -- Two things can take the mouse away from the track graph: the FX schema
    -- panel, which covers a corner of it, and the FX node view, which covers
    -- the whole thing. They were kept apart, and only the panel reached the
    -- handlers below -- so a right-click on an FX node opened the track graph's
    -- own menus behind the view as well. One flag, so a guard cannot cover one
    -- case and miss the other.
    local fx_schema_blocks_mouse = (fx_schema_layout ~= nil
        and mx >= fx_schema_layout.x and mx <= fx_schema_layout.x + fx_schema_layout.w
        and my >= fx_schema_layout.y and my <= fx_schema_layout.y + fx_schema_layout.h)
        or PB.fx_view_guid ~= nil
    PB.fx_schema_mouse_block = fx_schema_blocks_mouse

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
            -- A track-graph cable under the cursor is only interesting when
            -- the track graph has the mouse. It did not check, so with the FX
            -- node view open a cable behind it still counted as hovered -- and
            -- a right-click meant for an FX node opened that cable's send
            -- popup, over a view that has nothing to do with it.
            if not fx_schema_blocks_mouse and not hovered_cable
                and BezierHit(mx, my, sx, sy, cx1, cy1, cx2, cy2, dx, dy, 6) then
                hovered_cable = c
            end
        end
    end

    -- Zero iterations while the FX node view owns the canvas. The view is drawn
    -- over the top of all this, so every cable, node and pin below was being
    -- built and then hidden -- about 88 lines of drawing per frame for nothing.
    --
    -- Written as a bound rather than an `if` around the body on purpose: the
    -- node loop alone is 368 lines, and re-indenting it would turn a change
    -- that can be read in one line into a diff nobody can check.

    for ci = 1, (PB.fx_view_guid and 0 or #cables) do
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
            local inherited_muted, inherited_mute_name, inherited_mute_side = PatchbayCableInheritedMuteInfo(hovered_cable, guid_to)
            local inherited_tip = ""
            if inherited_muted then
                inherited_tip = inherited_mute_side == "destination" and ("\nDestination in muted folder: " .. tostring(inherited_mute_name or "Folder")) or ("\nMuted by folder ancestor: " .. tostring(inherited_mute_name or "Folder"))
            end
            r.ImGui_SetTooltip(ctx, string.format("%s \xE2\x86\x92 %s\n%s, %.1f dB\n%s%s", sname, dname, mlabel, vol_db, type_details, inherited_tip))
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

    -- Zero iterations while the FX node view owns the canvas. The view is drawn
    -- over the top of all this, so every cable, node and pin below was being
    -- built and then hidden -- about 368 lines of drawing per frame for nothing.
    --
    -- Written as a bound rather than an `if` around the body on purpose: the
    -- node loop alone is 368 lines, and re-indenting it would turn a change
    -- that can be read in one line into a diff nobody can check.

    for i = 1, (PB.fx_view_guid and 0 or #tracks) do
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
            -- Three now: pin, schema, FX node view. This width also decides
            -- whether a node is wide enough to show its controls at all, and
            -- bounds their hit region, so it has to grow with them.
            local control_left_group_w = (control_size * 3) + (control_gap * 2)
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
            if not fx_schema_blocks_mouse and body_hovered and not node_control_hit
                and not is_master_node and r.ValidatePtr(tr.track, "MediaTrack*")
                and r.ImGui_IsMouseDoubleClicked(ctx, 0) then
                PatchbayFxNodeEnter(g)
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
                    { id = "##fxnode_btn", action = "fxnode", icon = "fxnode", width = control_size, x = control_left_x + (control_size + control_gap) * 2, active = false, on = 0x6FD88AFF, off = 0x4A4A4AFF, tip = "Open the FX node view" },
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
                    elseif ctrl.icon == "fxnode" then
                        PatchbayDrawFxNodeSymbol(draw_list, bx1, by1, bx2, by2, 0xFFFFFFFF)
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
                        elseif ctrl.action == "fxnode" then
                            PatchbayFxNodeEnter(g)
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

    -- Zero iterations while the FX node view owns the canvas. The view is drawn
    -- over the top of all this, so every cable, node and pin below was being
    -- built and then hidden -- about 63 lines of drawing per frame for nothing.
    --
    -- Written as a bound rather than an `if` around the body on purpose: the
    -- node loop alone is 368 lines, and re-indenting it would turn a change
    -- that can be read in one line into a diff nobody can check.

    for i = 1, (PB.fx_view_guid and 0 or #tracks) do
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
            if r.ImGui_IsItemHovered(ctx) then
                hovered_input_guid = g
                r.ImGui_DrawList_AddCircle(draw_list, in_x, in_y, pin_r + 2, 0xFFFFFFFF, nil, 2)
                r.ImGui_SetTooltip(ctx, PatchbayBuildPinTooltip(tr, "in", tracks, guid_to) .. "\nRight-click: route settings")
            end

            if not is_master_node then
                r.ImGui_SetCursorScreenPos(ctx, out_x - pin_r, out_y - pin_r)
                r.ImGui_InvisibleButton(ctx, "##pin_out", pin_r * 2, pin_r * 2)
                if r.ImGui_IsItemHovered(ctx) then
                    r.ImGui_DrawList_AddCircle(draw_list, out_x, out_y, pin_r + 2, 0xFFFFFFFF, nil, 2)
                    r.ImGui_SetTooltip(ctx, PatchbayBuildPinTooltip(tr, "out", tracks, guid_to) .. "\nRight-click: route settings")
                end
                if r.ImGui_IsItemActive(ctx) and not all_locked then
                    if not pending_connection and not pending_folder_connection then
                        pending_connection = { src = tr.track, src_guid = g }
                    end
                end

                r.ImGui_SetCursorScreenPos(ctx, folder_x - pin_r, folder_y - pin_r)
                r.ImGui_InvisibleButton(ctx, "##pin_folder", pin_r * 2, pin_r * 2)
                if r.ImGui_IsItemHovered(ctx) then
                    local folder_pin_enabled = CanStartFolderPin(tr)
                    local hcol = folder_pin_enabled and 0xD8FFE0FF or 0x777777FF
                    r.ImGui_DrawList_AddCircle(draw_list, folder_x, folder_y, pin_r + 2, hcol, nil, 2)
                    r.ImGui_SetTooltip(ctx, PatchbayBuildPinTooltip(tr, "folder", tracks, guid_to, folder_pin_enabled, all_locked))
                end
                if r.ImGui_IsItemActive(ctx) and CanStartFolderPin(tr) then
                    if not pending_folder_connection and not pending_connection then
                        pending_folder_connection = { parent = tr.track, parent_guid = g }
                    end
                end
            end

            r.ImGui_PopID(ctx)
        end
    end

    if fx_schema_layout then PatchbayFxSchemaRender(ctx, draw_list, fx_schema_layout) end
    PatchbayFxNodeFrame(ctx, origin_x, origin_y, avail_w, avail_h)

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
