-- @description TK Patchbay Viewer (Standalone)
-- @author TouristKiller
-- @version 1.1.5
-- @changelog:
--   v1.1.5:
--       + Added a read-only FX-chain schema popover per node, with compact container/nested-container visualization.
--       + Added Paranormal FX launch integration from the FX-chain schema popover without duplicating Paranormal editing features.
--       + Added node-level pin, FX-chain schema, mute and solo controls, with pin/schema aligned left and mute/solo aligned right.
--       + Reworked node folder visuals: removed folder-name text badges, added wider colored sidebars with F/C role markers, and moved routing in/out counts under the node title.
--       + Added subtle milkglass transparency to the FX-chain schema panel with separate light/dark theme tuning.
--       + Improved zoom behavior so node in/out counts remain visible longer.
--       + Synced Patchbay multi-select state to REAPER/TCP selection for ctrl-click and rubberband selection.
--       + Added Del-key removal for multi-selected Patchbay nodes via the existing confirmation popup.
--       + Added Alt+left-click removal for folder-structure links to extract child tracks from parent folders.
--   v1.1.3:
--       + Added Rename Track to the node context menu.
--       + Added Alt+left-click cable deletion for sends and master-send cables.
--       + Added multi-select drag routing for selected sources and selected targets.
--   v1.1.1:
--       + Added View > Hide child master flow to visually reduce folder child master cable clutter.
--       + Added View > View options help window with English explanations for Patchbay view modes.
--   v1.1.0:
--       + Added Patchbay track template insertion with default/custom template folders, recursive subfolder scan, browse and refresh actions.
--       + Added Patchbay folder parent-child assignment via dedicated bottom pins and context menu actions, including existing folder append and simple nested folder support.
--       + Added Patchbay Remove from parent action for extracting folder children while preserving simple folder-depth balance.
--       + Added Patchbay audio, sidechain and MIDI send identification with badges, filters and type presets.
--       + Added Patchbay Cable shop for mode colors, folder connections, sidechain/MIDI overlays, stripes, user presets, thickness and visibility.
--       + Added distinct folder relationship visuals, split child/folder node coloring and a View > Folder links toggle.
--       + Added Explicit view master-flow option and Only isolated view for tracks without routing or main send.
--   v1.0.0:
--       + Initial public release - fully-featured standalone Patchbay viewer
--       + Core Features:
--         • Advanced route auditing with conflict detection, duplicate route highlighting, and visual cable marking (red/orange for issues)
--         • Bulk route editor: apply routing settings (destination, mode, volume, pan, mute, phase, mono) to multiple selected tracks simultaneously
--         • Lock modes: "Layout locked" (freeze patchbay layout/zoom), "All locked" (lock layout + routing changes)
--         • Fit zoom: auto-fit patchbay to viewport
--         • Multi-select Focus: improved filtering for routing focus on multiple selected tracks
--       + Patchbay Visualization & Workflow:
--         • Node pin/collapse workflow with persistent node state
--         • Folder-aware visuals: folder badges, parent/child collapsed indicators (F/C), folder-color tinting
--         • Project snapshots and layout presets for quick workspace recall
--         • Master-route clearer coloring and group context routing actions
--         • Align Grid for organized node positioning
--       + Themes & Persistence:
--         • Six built-in themes: Gray, Light, Dark, Ocean, Forest, Sand
--         • Persistent config storage to patchbay_standalone_config.json
--         • Automatic settings load on startup, save on window close
--       + UI Refinements:
--         • Compact bulk actions with unified context menus
--         • Improved focus behavior and filter naming clarity
--         • Standalone window independent of TK FX BROWSER

local r = reaper

-- Get script path
local script_path = debug.getinfo(1, "S").source:match("@?(.*[/\\])")

-- Verify TKFXBPatchbay_Standalone exists (same folder)
local patchbay_path = script_path .. "TKFXBPatchbay_Standalone.lua"
if not r.file_exists(patchbay_path) then
    r.ShowMessageBox(
        "Cannot find TKFXBPatchbay_Standalone.lua in:\n" .. patchbay_path .. "\n\n" ..
        "Please ensure the Patchbay module is in the same folder.",
        "TK Patchbay Viewer - Missing Dependency",
        0
    )
    return
end

-- Config file path (separate from TK FX BROWSER config)
local patchbay_config_path = script_path .. "patchbay_standalone_config.json"

-- Initialize ImGui context (standalone, isolated from TK FX BROWSER)
_G.ctx = r.ImGui_CreateContext("TK Patchbay Viewer")

-- Initialize config with defaults (isolated from TK FX BROWSER)
_G.config = {
    patchbay_node_width = 180,
    patchbay_show_master = true,
    patchbay_hide_child_master_flow = false,
    patchbay_only_explicit_routing = false,
    patchbay_show_flow = true,
    patchbay_show_folder_links = true,
    patchbay_show_send_type_badges = true,
    patchbay_cable_shop_post_fader_color = 0x4FB0C8FF,
    patchbay_cable_shop_post_fader_hover = 0x70D0E0FF,
    patchbay_cable_shop_post_fader_thickness = 1.5,
    patchbay_cable_shop_post_fader_visible = true,
    patchbay_cable_shop_pre_fader_color = 0xDDA050FF,
    patchbay_cable_shop_pre_fader_hover = 0xF0C070FF,
    patchbay_cable_shop_pre_fader_thickness = 1.7,
    patchbay_cable_shop_pre_fader_visible = true,
    patchbay_cable_shop_pre_fx_color = 0xB070D0FF,
    patchbay_cable_shop_pre_fx_hover = 0xC890E0FF,
    patchbay_cable_shop_pre_fx_thickness = 1.7,
    patchbay_cable_shop_pre_fx_visible = true,
    patchbay_cable_shop_muted_color = 0x666666AA,
    patchbay_cable_shop_muted_hover = 0x888888FF,
    patchbay_cable_shop_muted_thickness = 1.2,
    patchbay_cable_shop_muted_visible = true,
    patchbay_cable_shop_main_color = 0xC69A42CC,
    patchbay_cable_shop_main_hover = 0xDBB35AE0,
    patchbay_cable_shop_main_thickness = 1.8,
    patchbay_cable_shop_main_visible = true,
    patchbay_cable_shop_folder_links_color = 0x66CC88AA,
    patchbay_cable_shop_folder_links_hover = 0x88FFAAFF,
    patchbay_cable_shop_folder_links_thickness = 1.6,
    patchbay_cable_shop_folder_links_visible = true,
    patchbay_cable_shop_sidechain_color = 0x65B872FF,
    patchbay_cable_shop_sidechain_hover = 0x88D894FF,
    patchbay_cable_shop_sidechain_thickness = 2.0,
    patchbay_cable_shop_sidechain_visible = true,
    patchbay_cable_shop_midi_color = 0x4F8FD8FF,
    patchbay_cable_shop_midi_hover = 0x76AAE8FF,
    patchbay_cable_shop_midi_thickness = 1.6,
    patchbay_cable_shop_midi_visible = true,
    patchbay_cable_shop_phase_color = 0xFF4040FF,
    patchbay_cable_shop_phase_hover = 0xFF7070FF,
    patchbay_cable_shop_phase_thickness = 1.0,
    patchbay_cable_shop_phase_visible = true,
    patchbay_cable_shop_user_presets = "",
    routing_filter_text = "",
    routing_only_selected = false,
    window_alpha = 1.0,
    patchbay_standalone_theme = "gray"
}

-- Track selection tracking
_G.TRACK = nil
_G.patchbay_hide_top_filter_divider = true

local function DrawRoutingFilterArrowButton(ctx, id, is_redo, enabled)
    local h = r.ImGui_GetFrameHeight(ctx)
    local w = h
    local clicked = r.ImGui_InvisibleButton(ctx, id, w, h) and enabled
    local dl = r.ImGui_GetWindowDrawList(ctx)
    local x1, y1 = r.ImGui_GetItemRectMin(ctx)
    local x2, y2 = r.ImGui_GetItemRectMax(ctx)
    local hovered = enabled and r.ImGui_IsItemHovered(ctx)
    local active = enabled and r.ImGui_IsItemActive(ctx)
    local bg_base = r.ImGui_GetColor(ctx, r.ImGui_Col_Button())
    local bg_hover = r.ImGui_GetColor(ctx, r.ImGui_Col_ButtonHovered())
    local bg_active = r.ImGui_GetColor(ctx, r.ImGui_Col_ButtonActive())
    local border_base = r.ImGui_GetColor(ctx, r.ImGui_Col_Border())
    local text_disabled = r.ImGui_GetColor(ctx, r.ImGui_Col_TextDisabled())
    local bg = active and bg_active or (hovered and bg_hover or bg_base)
    local border = hovered and bg_active or border_base
    local col = enabled and 0xFFFFFFFF or text_disabled
    local cx = (x1 + x2) * 0.5
    local cy = (y1 + y2) * 0.5
    local s = h * 0.34
    local m = is_redo and 1 or -1
    r.ImGui_DrawList_AddRectFilled(dl, x1, y1, x2, y2, bg, 4)
    r.ImGui_DrawList_AddRect(dl, x1, y1, x2, y2, border, 4, nil, 1)
    local ax = cx + m * s
    local bx = cx - m * s
    local ay = cy
    local bw = s * 0.58
    local thick = math.max(2.2, h * 0.13)
    r.ImGui_DrawList_AddLine(dl, ax, ay, bx, ay, col, thick)
    r.ImGui_DrawList_AddLine(dl, ax, ay, ax - m * bw, ay - bw, col, thick)
    r.ImGui_DrawList_AddLine(dl, ax, ay, ax - m * bw, ay + bw, col, thick)
    if hovered then r.ImGui_SetTooltip(ctx, is_redo and "Redo" or "Undo") end
    return clicked
end

local function CanNativeUndoRedo(is_redo)
    local fn = is_redo and r.Undo_CanRedo2 or r.Undo_CanUndo2
    if not fn then return true end
    local text = fn(0)
    return text ~= nil and text ~= ""
end

local function RunNativeUndoRedo(is_redo)
    r.Main_OnCommand(is_redo and 40030 or 40029, 0)
end

-- JSON encode/decode helpers (simple implementation)
local function json_encode(tbl)
    local json_str = "{"
    local first = true
    for k, v in pairs(tbl) do
        if not first then json_str = json_str .. "," end
        first = false
        json_str = json_str .. '"' .. k .. '":'
        if type(v) == "string" then
            json_str = json_str .. '"' .. v:gsub('"', '\\"') .. '"'
        elseif type(v) == "boolean" then
            json_str = json_str .. (v and "true" or "false")
        elseif type(v) == "number" then
            json_str = json_str .. tostring(v)
        end
    end
    json_str = json_str .. "}"
    return json_str
end

local function json_decode(json_str)
    local tbl = {}
    for k, v in json_str:gmatch('"([^"]+)":([^,}]+)') do
        v = v:match("^%s*(.-)%s*$")
        if v == "true" then
            tbl[k] = true
        elseif v == "false" then
            tbl[k] = false
        elseif v:match("^[0-9.]+$") then
            tbl[k] = tonumber(v)
        else
            tbl[k] = v:match('"(.-)\"$') or v
        end
    end
    return tbl
end

-- Load config from JSON file
function _G.LoadConfig()
    if r.file_exists(patchbay_config_path) then
        local f = io.open(patchbay_config_path, "r")
        if f then
            local json_str = f:read("*a")
            f:close()
            if json_str and json_str ~= "" then
                local loaded = json_decode(json_str)
                for k, v in pairs(loaded) do
                    if _G.config[k] ~= nil then
                        _G.config[k] = v
                    end
                end
            end
        end
    end
end

-- Save config to JSON file
function _G.SaveConfig()
    local f = io.open(patchbay_config_path, "w")
    if f then
        f:write(json_encode(_G.config))
        f:close()
    end
end

-- Load config from file at startup
_G.LoadConfig()

-- Load the TKFXBPatchbay module
dofile(patchbay_path)

-- Provide stub functions that TKFXBPatchbay expects from main browser
if not _G.DrawRoutingFilterBar then
    function _G.DrawRoutingFilterBar(arg)
        local ctx = _G.ctx
        local function RoutingTextButton(id, label, w)
            local h = r.ImGui_GetFrameHeight(ctx)
            local clicked = r.ImGui_InvisibleButton(ctx, id, w, h)
            local dl = r.ImGui_GetWindowDrawList(ctx)
            local x1, y1 = r.ImGui_GetItemRectMin(ctx)
            local _, y2 = r.ImGui_GetItemRectMax(ctx)
            local hovered = r.ImGui_IsItemHovered(ctx)
            local active = r.ImGui_IsItemActive(ctx)
            local col = _G.patchbay_toolbar_text_col or 0xD0D0D0FF
            if hovered then col = _G.patchbay_toolbar_text_hover_col or 0x7AA2F7FF end
            if active then col = _G.patchbay_toolbar_text_active_col or 0x9CB6F9FF end
            local th = r.ImGui_GetTextLineHeight(ctx)
            r.ImGui_DrawList_AddText(dl, x1 + 4, y1 + ((y2 - y1 - th) * 0.5), col, label)
            return clicked
        end

        local control_w = 130
    if DrawRoutingFilterArrowButton(ctx, "##routing_filter_undo", false, CanNativeUndoRedo(false)) then RunNativeUndoRedo(false) end
    r.ImGui_SameLine(ctx, 0, 2)
    if DrawRoutingFilterArrowButton(ctx, "##routing_filter_redo", true, CanNativeUndoRedo(true)) then RunNativeUndoRedo(true) end
    r.ImGui_SameLine(ctx, 0, 5)
        r.ImGui_PushItemWidth(ctx, control_w)
        local changed, new_filter = r.ImGui_InputTextWithHint(ctx, "##routing_filter", "Filter tracks...", _G.config.routing_filter_text or "")
        if changed then
            _G.config.routing_filter_text = new_filter or ""
        end
        if r.ImGui_IsItemDeactivatedAfterEdit and r.ImGui_IsItemDeactivatedAfterEdit(ctx) then
            if _G.SaveConfig then _G.SaveConfig() end
        end
        r.ImGui_PopItemWidth(ctx)
        r.ImGui_SameLine(ctx)
        r.ImGui_SetNextItemWidth(ctx, control_w)
        local changed_w, new_w = r.ImGui_SliderInt(ctx, "##pb_node_width_filter", _G.config.patchbay_node_width or 180, 80, 400)
        if changed_w then
            _G.config.patchbay_node_width = new_w
        end
        r.ImGui_SameLine(ctx)
        if RoutingTextButton("##pb_zoom_out", "-", 16) and _G.PatchbayZoomStep then
            _G.PatchbayZoomStep(1 / 1.2)
        end
        r.ImGui_SameLine(ctx)
        local zoom_label = _G.PatchbayZoomPercent and string.format("%d%%", _G.PatchbayZoomPercent()) or "100%"
        r.ImGui_Text(ctx, zoom_label)
        r.ImGui_SameLine(ctx)
        if RoutingTextButton("##pb_zoom_in", "+", 16) and _G.PatchbayZoomStep then
            _G.PatchbayZoomStep(1.2)
        end
        r.ImGui_SameLine(ctx)
        if RoutingTextButton("##pb_zoom_reset", "1:1", 28) and _G.PatchbayZoomReset then
            _G.PatchbayZoomReset()
        end
        r.ImGui_SameLine(ctx)
        if RoutingTextButton("##pb_zoom_fit", "Fit", 22) and _G.PatchbayZoomFit then
            _G.PatchbayZoomFit()
        end
        r.ImGui_SameLine(ctx)
        local lock_mode = (_G.config and _G.config.patchbay_lock_mode) or "none"
        local lock_text = "Lock: Off"
        local lock_col = 0x9AA0A6FF
        if lock_mode == "layout" then
            lock_text = "Lock: Layout"
            lock_col = 0xE3C06FFF
        elseif lock_mode == "all" then
            lock_text = "Lock: All"
            lock_col = 0xE36D6DFF
        end
        r.ImGui_TextColored(ctx, lock_col, lock_text)
        r.ImGui_SameLine(ctx)
        local avail_w = r.ImGui_GetContentRegionAvail(ctx)
        r.ImGui_SetCursorPosX(ctx, r.ImGui_GetCursorPosX(ctx) + math.max(0, avail_w - 36))
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0xF2F2F2FF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0xFFFFFFFF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0xD8D8D8FF)
        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), 99)
        if r.ImGui_Button(ctx, "##settings_dot", 14, 14) then
            r.ImGui_OpenPopup(ctx, "PatchbayStandaloneSettingsDummy")
        end
        r.ImGui_PopStyleVar(ctx, 1)
        r.ImGui_PopStyleColor(ctx, 3)
        if r.ImGui_BeginPopup(ctx, "PatchbayStandaloneSettingsDummy") then
            r.ImGui_Text(ctx, "Settings")
            r.ImGui_Separator(ctx)
            local cur_theme = _G.config.patchbay_standalone_theme or "gray"
            if r.ImGui_Selectable(ctx, "Gray", cur_theme == "gray") then
                _G.config.patchbay_standalone_theme = "gray"
                _G.SaveConfig()
            end
            if r.ImGui_Selectable(ctx, "Light", cur_theme == "light") then
                _G.config.patchbay_standalone_theme = "light"
                _G.SaveConfig()
            end
            if r.ImGui_Selectable(ctx, "Dark", cur_theme == "dark") then
                _G.config.patchbay_standalone_theme = "dark"
                _G.SaveConfig()
            end
            if r.ImGui_Selectable(ctx, "Ocean", cur_theme == "ocean") then
                _G.config.patchbay_standalone_theme = "ocean"
                _G.SaveConfig()
            end
            if r.ImGui_Selectable(ctx, "Forest", cur_theme == "forest") then
                _G.config.patchbay_standalone_theme = "forest"
                _G.SaveConfig()
            end
            if r.ImGui_Selectable(ctx, "Sand", cur_theme == "sand") then
                _G.config.patchbay_standalone_theme = "sand"
                _G.SaveConfig()
            end
            r.ImGui_EndPopup(ctx)
        end
        r.ImGui_SameLine(ctx)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0xD94A4AFF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0xE05A5AFF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0xB93D3DFF)
        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), 99)
        if r.ImGui_Button(ctx, "##close_dot", 14, 14) then
            _G.__tk_patchbay_standalone_close = true
        end
        r.ImGui_PopStyleVar(ctx, 1)
        r.ImGui_PopStyleColor(ctx, 3)
        r.ImGui_Separator(ctx)
    end
end

-- Window state
local window_x, window_y = 100, 100
local window_w, window_h = 1200, 700
local is_open = true
local ctx = _G.ctx
local MIN_WINDOW_W = 600
local MIN_WINDOW_H = 400
local frame_count = 0

-- Styling
local function SetupStyle()
    local theme = _G.config.patchbay_standalone_theme or "gray"
    if theme == "light" then
        _G.patchbay_toolbar_text_col = 0x233041FF
        _G.patchbay_toolbar_text_hover_col = 0x2B6BAEFF
        _G.patchbay_toolbar_text_active_col = 0x1C4D83FF
        _G.patchbay_snapshot_save_btn_col = 0xE2E8EFFF
        _G.patchbay_snapshot_save_btn_hover_col = 0xD8E0E9FF
        _G.patchbay_snapshot_save_btn_active_col = 0xCBD6E2FF
        _G.patchbay_grid_bg_col = 0xCDD5DEFF
        _G.patchbay_grid_dot_col = 0xA3AFBCFF
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0x1E2630FF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_TextDisabled(), 0x5D6978FF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_WindowBg(), 0xDCE2E9FF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ChildBg(), 0xD2DAE3FF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_PopupBg(), 0xE6EBF2FF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Border(), 0x8C99AAFF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0xB3BFCCFF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0xA1B0C0FF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0x8E9FB2FF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), 0xE2E8EFFF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgHovered(), 0xD8E0E9FF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgActive(), 0xCBD6E2FF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Header(), 0xB4C0CDFF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderHovered(), 0xA1B0C0FF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderActive(), 0x8E9FB2FF)
    elseif theme == "dark" then
        _G.patchbay_toolbar_text_col = 0xD0D0D0FF
        _G.patchbay_toolbar_text_hover_col = 0x7AA2F7FF
        _G.patchbay_toolbar_text_active_col = 0x9CB6F9FF
        _G.patchbay_snapshot_save_btn_col = 0x20262CFF
        _G.patchbay_snapshot_save_btn_hover_col = 0x29323AFF
        _G.patchbay_snapshot_save_btn_active_col = 0x313C46FF
        _G.patchbay_grid_bg_col = 0x111315FF
        _G.patchbay_grid_dot_col = 0x1F252BFF
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0xD7DEE7FF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_TextDisabled(), 0x7E8894FF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_WindowBg(), 0x15181BFF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ChildBg(), 0x1B1F23FF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_PopupBg(), 0x1E2328FF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Border(), 0x313841FF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x2A3138FF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0x35404AFF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0x263039FF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), 0x20262CFF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgHovered(), 0x29323AFF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgActive(), 0x313C46FF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Header(), 0x2D3741FF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderHovered(), 0x394553FF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderActive(), 0x455367FF)
    elseif theme == "ocean" then
        _G.patchbay_toolbar_text_col = 0xCFE1F5FF
        _G.patchbay_toolbar_text_hover_col = 0x82B8EDFF
        _G.patchbay_toolbar_text_active_col = 0xA5CEEFFF
        _G.patchbay_snapshot_save_btn_col = 0x203750FF
        _G.patchbay_snapshot_save_btn_hover_col = 0x2A4A6AFF
        _G.patchbay_snapshot_save_btn_active_col = 0x345D86FF
        _G.patchbay_grid_bg_col = 0x132334FF
        _G.patchbay_grid_dot_col = 0x2A4662FF
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0xD7E6F7FF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_TextDisabled(), 0x8298B3FF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_WindowBg(), 0x16283BFF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ChildBg(), 0x1A3048FF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_PopupBg(), 0x1D3550FF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Border(), 0x2E4B68FF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x294462FF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0x355A80FF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0x24445FFF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), 0x203750FF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgHovered(), 0x2A4A6AFF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgActive(), 0x345D86FF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Header(), 0x2E4D6CFF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderHovered(), 0x3A6188FF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderActive(), 0x4973A0FF)
    elseif theme == "forest" then
        _G.patchbay_toolbar_text_col = 0xD7E8DAFF
        _G.patchbay_toolbar_text_hover_col = 0x8CC89BFF
        _G.patchbay_toolbar_text_active_col = 0xA7D8B2FF
        _G.patchbay_snapshot_save_btn_col = 0x2C4533FF
        _G.patchbay_snapshot_save_btn_hover_col = 0x395A42FF
        _G.patchbay_snapshot_save_btn_active_col = 0x497258FF
        _G.patchbay_grid_bg_col = 0x1B2A1FFF
        _G.patchbay_grid_dot_col = 0x334A37FF
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0xDBEADBFF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_TextDisabled(), 0x8A9D8CFF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_WindowBg(), 0x1F3124FF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ChildBg(), 0x253A2BFF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_PopupBg(), 0x2A4231FF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Border(), 0x426248FF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x36533DFF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0x466A4EFF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0x2F4A36FF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), 0x2C4533FF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgHovered(), 0x395A42FF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgActive(), 0x497258FF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Header(), 0x3D5F45FF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderHovered(), 0x4D7858FF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderActive(), 0x5E8F6BFF)
    elseif theme == "sand" then
        _G.patchbay_toolbar_text_col = 0x413528FF
        _G.patchbay_toolbar_text_hover_col = 0x8B633CFF
        _G.patchbay_toolbar_text_active_col = 0x6E4F31FF
        _G.patchbay_snapshot_save_btn_col = 0xE4D8C8FF
        _G.patchbay_snapshot_save_btn_hover_col = 0xDACCB9FF
        _G.patchbay_snapshot_save_btn_active_col = 0xCFC0ABFF
        _G.patchbay_grid_bg_col = 0xCFC1ACFF
        _G.patchbay_grid_dot_col = 0xA99578FF
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0x3C3025FF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_TextDisabled(), 0x6E6155FF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_WindowBg(), 0xD7C9B4FF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ChildBg(), 0xCEBFA9FF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_PopupBg(), 0xE1D6C6FF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Border(), 0x9E8A70FF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0xB79E80FF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0xA88D6DFF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0x967C5DFF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), 0xE4D8C8FF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgHovered(), 0xDACCB9FF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgActive(), 0xCFC0ABFF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Header(), 0xBFA689FF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderHovered(), 0xAF936FFF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderActive(), 0x9D805DFF)
    else
        _G.patchbay_toolbar_text_col = 0xD0D0D0FF
        _G.patchbay_toolbar_text_hover_col = 0x7AA2F7FF
        _G.patchbay_toolbar_text_active_col = 0x9CB6F9FF
        _G.patchbay_snapshot_save_btn_col = 0x2A2A2AFF
        _G.patchbay_snapshot_save_btn_hover_col = 0x353535FF
        _G.patchbay_snapshot_save_btn_active_col = 0x3D3D3DFF
        _G.patchbay_grid_bg_col = 0x1A1A1AFF
        _G.patchbay_grid_dot_col = 0x2A2A2AFF
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0xD8D8D8FF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_TextDisabled(), 0x7D7D7DFF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_WindowBg(), 0x1E1E1EFF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ChildBg(), 0x252525FF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_PopupBg(), 0x252525FF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Border(), 0x404040FF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x4A4A4AFF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0x5B5B5BFF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0x3A3A3AFF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), 0x2A2A2AFF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgHovered(), 0x353535FF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgActive(), 0x3D3D3DFF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Header(), 0x414141FF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderHovered(), 0x545454FF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderActive(), 0x666666FF)
    end
end

local function CleanupStyle()
    r.ImGui_PopStyleColor(ctx, 15)
end

-- Main loop
function Loop()
    if not is_open then
        return false
    end
    
    -- Update track selection
    _G.TRACK = r.GetSelectedTrack(0, 0)
    
    SetupStyle()
    
    -- Draw window
    r.ImGui_SetNextWindowPos(ctx, window_x, window_y, r.ImGui_Cond_FirstUseEver())
    r.ImGui_SetNextWindowSize(ctx, window_w, window_h, r.ImGui_Cond_FirstUseEver())
    
    -- Set minimum window size constraints
    if r.ImGui_SetNextWindowSizeConstraints then
        r.ImGui_SetNextWindowSizeConstraints(ctx, MIN_WINDOW_W, MIN_WINDOW_H, 10000, 10000)
    end
    
    local window_flags = r.ImGui_WindowFlags_NoTitleBar()
    local window_open, is_open_new = r.ImGui_Begin(ctx, "##TK_Patchbay_Viewer", is_open, window_flags)
    if window_open then
        if not r.ImGui_IsAnyItemActive(ctx) and r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_Escape()) then
            is_open_new = false
            _G.SaveConfig()
        end

        if ShowRoutingPatchbay then
            ShowRoutingPatchbay()
        else
            r.ImGui_TextWrapped(ctx, "ERROR: ShowRoutingPatchbay not found. Module may not have loaded correctly.")
        end

        if _G.__tk_patchbay_standalone_close then
            is_open_new = false
            _G.__tk_patchbay_standalone_close = nil
            _G.SaveConfig()
        end

        r.ImGui_End(ctx)
    end

    is_open = is_open_new

    frame_count = frame_count + 1
    if frame_count % 30 == 0 then
        _G.SaveConfig()
    end

    CleanupStyle()

    if is_open then
        r.defer(Loop)
    end
end

-- Start the loop
r.defer(Loop)
