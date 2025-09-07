-- TK RAW Audio Editor - Reaper Audio Workstation
-- Version: 0.0.3 ALPHA
-- Author: TouristKiller
----------------------------------------------------------------------------------
-- WORK AND TEST VERSION
-- Getting core functions done and worry about compatibility later
-- THANX TO: MPL!
----------------------------------------------------------------------------------

local r = reaper
if not r.ImGui_CreateContext then
    r.ShowMessageBox("ReaImGui extension is required for this script.\nPlease install ReaImGui via ReaPack.", "Missing Extension", 0)
    return
end

local ctx = r.ImGui_CreateContext('TK Audio Editor')
local function CreateFontWithFallback(size)
    local os_str = r.GetOS() or ""
    local names
    if os_str:find("Win") then
        names = { "Arial", "Segoe UI", "Tahoma", "sans-serif" }
    elseif os_str:find("OSX") then
        names = { "Arial", "Helvetica", "sans-serif" }
    else
        names = { "DejaVu Sans", "Noto Sans", "Liberation Sans", "Arial", "sans-serif" }
    end
    for _, name in ipairs(names) do
        local f = r.ImGui_CreateFont(name, size)
        if f then return f end
    end
    return r.ImGui_CreateFont('sans-serif', size)
end
local font = CreateFontWithFallback(14)
local font_big = CreateFontWithFallback(20)
r.ImGui_Attach(ctx, font)
r.ImGui_Attach(ctx, font_big)

-- VARIABELE TABELLEN-------------------------------------------------------------
CONST = {
        MIN_WINDOW_WIDTH = 600,
        MIN_WINDOW_HEIGHT = 200,
            
        -- Fade/volume geometry
        FADE_FILL_ALPHA = 0.10,
        FADE_HANDLE_RADIUS = 5.0,
        FADE_HANDLE_HOVER_PAD = 3.0,
        VOL_LINE_THICKNESS = 2.0,
        VOL_HIT_PAD_Y = 6.0,
        VOL_DB_MIN = -24.0,
        VOL_DB_MAX = 12.0,
            
        -- Layout
        LEFT_GUTTER_W = 52.0,
        DRAW_FADE_SEC = 2.0,
        DRAW_MIN_PX_STEP = 1.0,
        RMB_DRAG_THRESHOLD_PX = 3.0,

        -- Theme colors (RGBA 0xRRGGBBAA)
        COLOR_BACKGROUND       = 0x1E1E1EFF,
        COLOR_GRID_BASE        = 0x404040FF,
        COLOR_ZERO_LINE_BASE   = 0x808080FF,
        COLOR_RULER_BG         = 0x222222FF,
        COLOR_RULER_TICK       = 0x606060FF,
        COLOR_RULER_TEXT       = 0xCFCFCFFF,
        COLOR_WAVEFORM         = 0x66FF66FF, 
        COLOR_GUTTER_BG        = 0x252525FF,
        COLOR_SELECTION_FILL   = 0x66A3FFFF,
        COLOR_SELECTION_BORDER = 0x66CCFFFF,
        COLOR_CURSOR_LINE      = 0xFFAA00FF,
        COLOR_PLAY_CURSOR_LINE = 0x55FF55FF,
        COLOR_VOL_LINE         = 0x000000FF,
        COLOR_VOL_LINE_ACTIVE  = 0xFFD24DFF,
        -- Overlay colors (RGBA 0xRRGGBBAA)
        COLOR_ENV_VOL_OVERLAY  = 0x00FF00FF, 
        COLOR_ENV_PAN_OVERLAY  = 0xFF00FFFF, 
        COLOR_DC_OVERLAY       = 0xFF6699FF,
        COLOR_FADE_REGION      = 0xFFFFFFFF,
        COLOR_FADE_LINE        = 0x000000FF,
        COLOR_FADE_HANDLE_FILL = 0x333333FF,
        COLOR_FADE_HANDLE_BORDER = 0xA0A0A0FF,
        COLOR_FADE_ACTIVE      = 0xFFFFFFFF,

        -- UI styling for ImGui widgets
        UI_BTN         = 0x2A2A2AFF,
        UI_BTN_HOVER   = 0x343434FF,
        UI_BTN_ACTIVE  = 0x1E1E1EFF,
        UI_FRAME       = 0x202020FF,
        UI_FRAME_HOVER = 0x2A2A2AFF,
        UI_FRAME_ACTIVE= 0x151515FF,
        UI_CHECK       = 0xFFFFFFFF,
        UI_SLIDER_GRAB = 0xA0A0A0FF,
        UI_SLIDER_ACT  = 0xFFFFFFFF,
        UI_TEXT_HOVER  = 0xFFD24DFF,
        UI_ROUNDING    = 4.0,
}

SETTINGS = {
        show_grid = true,
        grid_alpha = 0.9,
        show_ruler = true,
        ruler_beats = false,
        show_edit_cursor = true,
        show_play_cursor = true,
        show_db_scale = true,
        show_footer = true,
        db_alpha = 0.55,
        db_labels_mirrored = true,
        draw_channels_separately = true,
        click_sets_edit_cursor = true,
        click_seeks_playback = false,
        snap_click_to_grid = true,
        require_shift_for_selection = true,
        show_tooltips = true,
        waveform_soft_edges = true,
        waveform_outline_paths = false,
        waveform_centerline_thickness = 1.5,
        waveform_fill_alpha = 0.18,
        view_detail_mode = "fixed",
        view_oversample = 4,
        spectral_peaks = false,
        spectral_lock_sr = true,
        spectral_max_zcr_hz = 8000,
        spectral_fixed_sr = 24000,
        spectral_sr_min = 8000,
        spectral_sr_max = 48000,
        spectral_samples_budget = 350000,
        sidebar_collapsed = false,
        ripple_item = false,
        glue_include_touching = false,
        glue_after_normalize_sel = false,
        prefer_sws_normalize = true,
        sws_norm_named_cmd = "",
        show_env_overlay = false,
        show_fades = true,
        show_dc_overlay = false,
        show_pan_overlay = false,
        show_vol_points = false,
        show_transport_overlay = true,
        transport_item_only = false,
        pencil_target = "dc_offset", 
        dc_link_lr = true, 
        draw_min_px_step = 1.0,
}

STATE = {
        peaks = {},
        current_item = nil,
        current_take = nil,
        current_src = nil,
        is_loaded = false,
        last_sel_guid = nil,
        last_sel_count = 0,
        pending_sel_reload = 0,
        sample_rate = 44100,
        channels = 1,
        filename = "",
        current_item_start = 0.0,
        current_item_len = 0.0,
        dragging_select = false,
        drag_start_t = nil,
        drag_cur_t = nil,
        sel_a = nil,
        sel_b = nil,
        drag_start_px = nil,
        DRAG_THRESHOLD_PX = 8,
        drag_start_time = nil,
        DRAG_DELAY_MS = 120,
        rmb_drawing = false,
        draw_points = nil,
        draw_lane_ch = nil, 
        draw_last_t = nil,
        draw_visible_until = 0.0,
        rmb_pending_start = false,
        rmb_press_x = nil,
        rmb_press_y = nil,
        view_start = 0.0,
        view_len = 0.0,
        amp_zoom = 1.0,
        panning = false,
        pan_start_x = nil,
        pan_start_view = nil,
        current_accessor = nil,
        pencil_mode = false,
        show_grid_slider = false,
        last_interaction_time = 0.0,
        is_interacting = false,
        fade_dragging = false,
        fade_drag_side = nil,
        fade_undo_open = false,
        fade_ctx_side = nil,
        pan_undo_open = false,
        vol_pt_hover_idx = nil,
        vol_pt_drag_idx = nil,
        vol_pt_drag_shape = 0,
        vol_pt_drag_tension = 0.0,
        vol_pt_undo_open = false,

        dbg_spectral_sr = nil,
        dbg_spectral_total = nil,
        dbg_spectral_capped = false,

        -- Mini-game state
        game_active = false,
        game_over = false,
        game_player_x = 0.0,
        game_player_y = 0.0,
        game_speed = 220.0,
        game_last_time = nil,
        game_obstacles = {},
        game_spawn_cooldown = 0.0,
        game_score = 0,
        game_elapsed = 0.0,
        game_packages = {},
        game_package_radius = 6.0,
        game_starfield = false,
        game_stars = {},
        game_starfield_w = 0,
        game_starfield_h = 0,

        ts_user_override = false,
}

local info_open = false
local info_stats = nil
local info_item_guid = nil
local info_range_key = nil
local info_last_calc = 0.0

CACHE = {
        view_cache_min = nil,
        view_cache_max = nil,
        view_cache_w = 0,
        view_cache_start = 0.0,
        view_cache_len = 0.0,
        view_cache_valid = false,
        view_cache_overs = 0,
        view_cache_z = nil,
        view_cache_cov = 0.0,
        view_cache_rms = nil,
        view_cache_min_ch = nil,
        view_cache_max_ch = nil,
}

setmetatable(_G, {
    __index = function(_, k)
        local v = CONST[k]; if v ~= nil then return v end
        v = SETTINGS[k]; if v ~= nil then return v end
        v = STATE[k]; if v ~= nil then return v end
        v = CACHE[k]; if v ~= nil then return v end
        return nil
    end,
    __newindex = function(_, k, v)
        if CONST[k] ~= nil then CONST[k] = v; return end
        if SETTINGS[k] ~= nil then SETTINGS[k] = v; return end
        if STATE[k] ~= nil then STATE[k] = v; return end
        if CACHE[k] ~= nil or (type(k)=="string" and k:match("^view_cache_")) then CACHE[k] = v; return end
        rawset(_G, k, v)
    end
})

local function ValidTake(t)
    if not t then return false end
    if reaper.ValidatePtr2 then return reaper.ValidatePtr2(0, t, 'MediaItem_Take*') end
    return true
end

local function ValidItem(it)
    if not it then return false end
    if reaper.ValidatePtr2 then return reaper.ValidatePtr2(0, it, 'MediaItem*') end
    return true
end

function RunCommandOnItemWithTemporarySelection(item, cmd)
    if not item or not cmd then return end
    local proj = 0
    local n = r.CountMediaItems(proj)
    local prev = {}
    local current_item = item
    for i = 0, n - 1 do
        local it = r.GetMediaItem(proj, i)
        prev[#prev+1] = { it = it, sel = r.IsMediaItemSelected(it) }
    end
    r.PreventUIRefresh(1)
    r.SelectAllMediaItems(proj, false)
    r.SetMediaItemSelected(item, true)
    r.Main_OnCommand(cmd, 0)
    r.SelectAllMediaItems(proj, false)
    for i = 1, #prev do
        if prev[i].sel then r.SetMediaItemSelected(prev[i].it, true) end
    end
    r.PreventUIRefresh(-1)
end

function EnsureTakeVolEnv(take, item)
    if not take or not item then return nil end
    local env = r.GetTakeEnvelopeByName(take, "Volume")
    if env then return env end
    local _, takeGUID = r.GetSetMediaItemTakeInfo_String(take, "GUID", "", false)
    if not takeGUID or takeGUID == "" then return nil end
    local ok, chunk = r.GetItemStateChunk(item, "", false)
    local current_item = item
    if not ok or not chunk then return nil end
    local lines = {}
    for ln in string.gmatch(chunk, "[^\n]+") do lines[#lines+1] = ln end
    local insertIdx, foundTake, search_take_end = nil, false, true
    local takeGUID_pat = takeGUID:gsub("-", "%%-")
    for i = 1, #lines do
        local line = lines[i]
        if not foundTake and line:find(takeGUID_pat) then foundTake = true end
        if foundTake and not insertIdx then
            if line:find("^<.-ENV$") then
                insertIdx = i
            elseif line == ">" and search_take_end then
                search_take_end = false
                insertIdx = i + 1
            end
        end
    end
    if not insertIdx then insertIdx = #lines + 1 end
    local vol_env = "\n<VOLENV\nEGUID " .. (r.genGuid and r.genGuid("") or ("{"..tostring(math.random()).."}")) ..
                   "\nACT 1 -1\nVIS 1 1 1\nLANEHEIGHT 0 0\nARM 1\nDEFSHAPE 0 -1 -1\nVOLTYPE 1\nPT 0 1 0\n>\n"
    table.insert(lines, insertIdx, vol_env)
    local newChunk = table.concat(lines, "\n")
    r.SetItemStateChunk(item, newChunk, true)
    return r.GetTakeEnvelopeByName(take, "Volume")
end

function VToEnvelopeValue(env, v)
    if not env then return nil end
    local vv = math.max(-1.0, math.min(1.0, v or 0))
    local db
    if vv >= 0 then db = vv * (VOL_DB_MAX or 12.0) else db = vv * math.abs(VOL_DB_MIN or -24.0) end
    local amp = db_to_amp(db)
    local mode = r.GetEnvelopeScalingMode and r.GetEnvelopeScalingMode(env) or 0
    if r.ScaleToEnvelopeMode then
        return r.ScaleToEnvelopeMode(mode, amp)
    else
        return amp
    end
end

function CommitStrokeToTakeVolEnv(take, item, points, item_pos, view_len_px, view_w_px)
    if not take or not item or not points or #points < 2 then return false end
    local env = EnsureTakeVolEnv(take, item)
    if not env then return false end
    local it_start = item_pos or 0
    local it_end = it_start + (current_item_len or 0)
    local t0, t1 = math.huge, -math.huge
    for i = 1, #points do
        local t = points[i].t or 0
        if t < t0 then t0 = t end
        if t > t1 then t1 = t end
    end
    if t0 == math.huge or t1 == -math.huge or t1 <= t0 then return false end
    if t0 < it_start then t0 = it_start end
    if t1 > it_end then t1 = it_end end

    local t0_in = t0 - it_start
    local t1_in = t1 - it_start

    local function eval_env(envh, t_in)
        if r.Envelope_Evaluate then
            local _, val = r.Envelope_Evaluate(envh, t_in, 0, 0)
            if val ~= nil then return val end
        end
        local cnt = r.CountEnvelopePoints(envh) or 0
        local prev_val, next_val = nil, nil
        local prev_time, next_time = -math.huge, math.huge
        for i = 0, cnt - 1 do
            local rv, time, val = r.GetEnvelopePoint(envh, i)
            if rv then
                if time <= t_in and time > prev_time then prev_time, prev_val = time, val end
                if time >= t_in and time < next_time then next_time, next_val = time, val end
            end
        end
        if prev_val ~= nil and next_val ~= nil then
            local tspan = (next_time - prev_time)
            if tspan > 0 then
                local a = (t_in - prev_time) / tspan
                return prev_val + (next_val - prev_val) * a
            else
                return prev_val
            end
        end
        return prev_val or next_val or 1.0 
    end
    local min_px = math.max(0.1, draw_min_px_step or DRAW_MIN_PX_STEP)
    local px_to_time = (view_len or 0) / math.max(1, view_w_px or 1)
    local eps_anchor = math.max(0.0005, (min_px * px_to_time) * 0.5)
    local eps_delete = math.max(1e-6, (min_px * px_to_time) * 0.25)

    local pre_time = math.max(0, t0_in - eps_anchor)
    local post_time = math.min((current_item_len or 0), t1_in + eps_anchor)

    local v_start = eval_env(env, t0_in)
    local v_end = eval_env(env, t1_in)
    local v_pre = eval_env(env, pre_time)
    local v_post = eval_env(env, post_time)

    if r.DeleteEnvelopePointRange and (t1_in - t0_in) > (2 * eps_delete) then
        r.DeleteEnvelopePointRange(env, t0_in + eps_delete, t1_in - eps_delete)
    end

    if v_pre ~= nil then r.InsertEnvelopePoint(env, pre_time, v_pre, 0, 0, 0, true) end
    if v_start ~= nil then r.InsertEnvelopePoint(env, t0_in, v_start, 0, 0, 0, true) end
    if v_end ~= nil then r.InsertEnvelopePoint(env, t1_in, v_end, 0, 0, 0, true) end
    if v_post ~= nil then r.InsertEnvelopePoint(env, post_time, v_post, 0, 0, 0, true) end

    local min_dt = min_px * px_to_time
    local last_t_in = nil
    local unsorted = true
    for i = 1, #points do
        local p = points[i]
        local t_in = (p.t or 0) - it_start
        if t_in >= t0_in and t_in <= t1_in then
            if (not last_t_in) or (t_in - last_t_in >= (min_dt or 0)) then
                local val = VToEnvelopeValue(env, p.v)
                if val ~= nil then r.InsertEnvelopePoint(env, t_in, val, 0, 0, 0, unsorted) end
                last_t_in = t_in
            end
        end
    end
    r.Envelope_SortPoints(env)
    return true
end

local function EnsureTakePanEnv(take, item)
    if not take or not item then return nil end
    local env = r.GetTakeEnvelopeByName(take, "Pan")
    if env then return env end
    local _, takeGUID = r.GetSetMediaItemTakeInfo_String(take, "GUID", "", false)
    if not takeGUID or takeGUID == "" then return nil end
    local ok, chunk = r.GetItemStateChunk(item, '', false)
    if not ok or not chunk or chunk == '' then return nil end
    local lines = {}
    for s in (chunk .. "\n"):gmatch("(.-)\n") do lines[#lines+1] = s end
    local insertIdx, foundTake, search_take_end = nil, false, true
    local takeGUID_pat = takeGUID:gsub("-", "%%-")
    for i = 1, #lines do
        local line = lines[i]
        if not foundTake and line:find(takeGUID_pat) then foundTake = true end
        if foundTake and not insertIdx then
            if line:find("^<.-ENV$") then
                insertIdx = i
            elseif line == ">" and search_take_end then
                search_take_end = false
                insertIdx = i + 1
            end
        end
    end
    if not insertIdx then insertIdx = #lines + 1 end
    local pan_env = "\n<PANENV\nEGUID " .. (r.genGuid and r.genGuid("") or ("{"..tostring(math.random()).."}")) ..
                   "\nACT 1 -1\nVIS 1 1 1\nLANEHEIGHT 0 0\nARM 1\nDEFSHAPE 0 -1 -1\nPT 0 0 0\n>\n"
    table.insert(lines, insertIdx, pan_env)
    local newChunk = table.concat(lines, "\n")
    r.SetItemStateChunk(item, newChunk, true)
    return r.GetTakeEnvelopeByName(take, "Pan")
end

local function PToEnvelopeValue(v)
    local vv = math.max(-1.0, math.min(1.0, v or 0))
    return vv
end

function CommitStrokeToTakePanEnv(take, item, points, item_pos, view_len_px, view_w_px)
    if not take or not item or not points or #points < 2 then return false end
    local env = EnsureTakePanEnv(take, item)
    if not env then return false end
    local it_start = item_pos or 0
    local it_end = it_start + (current_item_len or 0)
    local t0, t1 = math.huge, -math.huge
    for i = 1, #points do
        local t = points[i].t or 0
        if t < t0 then t0 = t end
        if t > t1 then t1 = t end
    end
    if t0 == math.huge or t1 == -math.huge or t1 <= t0 then return false end
    if t0 < it_start then t0 = it_start end
    if t1 > it_end then t1 = it_end end

    local t0_in = t0 - it_start
    local t1_in = t1 - it_start

    local function eval_env_raw(envh, t_in)
        local cnt = r.CountEnvelopePoints(envh) or 0
        if cnt == 0 then return 0.0 end 
        local prev_val, next_val = nil, nil
        local prev_time, next_time = -math.huge, math.huge
        for i = 0, cnt - 1 do
            local rv, time, val = r.GetEnvelopePoint(envh, i)
            if rv then
                if time <= t_in and time > prev_time then prev_time, prev_val = time, val end
                if time >= t_in and time < next_time then next_time, next_val = time, val end
            end
        end
        if prev_val ~= nil and next_val ~= nil then
            local tspan = (next_time - prev_time)
            if tspan > 0 then
                local a = (t_in - prev_time) / tspan
                return prev_val + (next_val - prev_val) * a
            else
                return prev_val
            end
        end
    return prev_val or next_val or 0.0 
    end

    local min_px = math.max(0.1, draw_min_px_step or DRAW_MIN_PX_STEP)
    local px_to_time = (view_len or 0) / math.max(1, view_w_px or 1)
    local eps_anchor = math.max(0.0005, (min_px * px_to_time) * 0.5)
    local eps_delete = math.max(1e-6, (min_px * px_to_time) * 0.25)

    local pre_time = math.max(0, t0_in - eps_anchor)
    local post_time = math.min((current_item_len or 0), t1_in + eps_anchor)

    local v_start = eval_env_raw(env, t0_in)
    local v_end   = eval_env_raw(env, t1_in)
    local v_pre   = eval_env_raw(env, pre_time)
    local v_post  = eval_env_raw(env, post_time)

    if r.DeleteEnvelopePointRange and (t1_in - t0_in) > (2 * eps_delete) then
        r.DeleteEnvelopePointRange(env, t0_in + eps_delete, t1_in - eps_delete)
    end

    if v_pre  ~= nil then r.InsertEnvelopePoint(env, pre_time,  v_pre,  0, 0, 0, true) end
    if v_start~= nil then r.InsertEnvelopePoint(env, t0_in,     v_start,0, 0, 0, true) end
    if v_end  ~= nil then r.InsertEnvelopePoint(env, t1_in,     v_end,  0, 0, 0, true) end
    if v_post ~= nil then r.InsertEnvelopePoint(env, post_time, v_post, 0, 0, 0, true) end

    local min_dt = min_px * px_to_time
    local last_t_in = nil
    local unsorted = true
    for i = 1, #points do
        local p = points[i]
        local t_in = (p.t or 0) - it_start
        if t_in >= t0_in and t_in <= t1_in then
            if (not last_t_in) or (t_in - last_t_in >= (min_dt or 0)) then
                local val = PToEnvelopeValue(p.v)
                r.InsertEnvelopePoint(env, t_in, val, 0, 0, 0, unsorted)
                last_t_in = t_in
            end
        end
    end
    r.Envelope_SortPoints(env)
    return true
end

local function EnsureActiveTakeEnvelopeVisible(target, take, item)
    if not take or not item then return end
    local env = nil
    if target == "item_pan" then
        env = EnsureTakePanEnv(take, item)
    else
        env = EnsureTakeVolEnv(take, item)
    end
    if env then
        if r.SetEnvelopeInfo_Value then
            r.SetEnvelopeInfo_Value(env, "VIS", 1.0)
            r.SetEnvelopeInfo_Value(env, "ACTIVE", 1.0)
            r.SetEnvelopeInfo_Value(env, "ARM", 1.0)
        end
        if r.Envelope_SortPoints then r.Envelope_SortPoints(env) end
        if r.UpdateItemInProject then r.UpdateItemInProject(item) end
        if r.UpdateArrange then r.UpdateArrange() end
    end
end

function CommitStrokeToMuteRange(take, item, points, item_pos, view_len_px, view_w_px)
    if not take or not item or not points or #points < 2 then return false end
    local env = EnsureTakeVolEnv(take, item)
    if not env then return false end
    local it_start = item_pos or 0
    local it_end = it_start + (current_item_len or 0)
    local t0, t1 = math.huge, -math.huge
    for i = 1, #points do
        local t = points[i].t or 0
        if t < t0 then t0 = t end
        if t > t1 then t1 = t end
    end
    if t0 == math.huge or t1 == -math.huge or t1 <= t0 then return false end
    if t0 < it_start then t0 = it_start end
    if t1 > it_end then t1 = it_end end

    local t0_in = t0 - it_start
    local t1_in = t1 - it_start

    local function eval_env(envh, t_in)
        if r.Envelope_Evaluate then
            local _, val = r.Envelope_Evaluate(envh, t_in, 0, 0)
            if val ~= nil then return val end
        end
        local cnt = r.CountEnvelopePoints(envh) or 0
        local prev_val, next_val = nil, nil
        local prev_time, next_time = -math.huge, math.huge
        for i = 0, cnt - 1 do
            local rv, time, val = r.GetEnvelopePoint(envh, i)
            if rv then
                if time <= t_in and time > prev_time then prev_time, prev_val = time, val end
                if time >= t_in and time < next_time then next_time, next_val = time, val end
            end
        end
        if prev_val ~= nil and next_val ~= nil then
            local tspan = (next_time - prev_time)
            if tspan > 0 then
                local a = (t_in - prev_time) / tspan
                return prev_val + (next_val - prev_val) * a
            else
                return prev_val
            end
        end
        return prev_val or next_val or 1.0 
    end

    local min_px = math.max(0.1, draw_min_px_step or DRAW_MIN_PX_STEP)
    local px_to_time = (view_len or 0) / math.max(1, view_w_px or 1)
    local eps_anchor = math.max(0.0005, (min_px * px_to_time) * 0.5)
    local eps_delete = math.max(1e-6, (min_px * px_to_time) * 0.25)

    local pre_time = math.max(0, t0_in - eps_anchor)
    local post_time = math.min((current_item_len or 0), t1_in + eps_anchor)

    local v_start = eval_env(env, t0_in)
    local v_end = eval_env(env, t1_in)
    local v_pre = eval_env(env, pre_time)
    local v_post = eval_env(env, post_time)

    if r.DeleteEnvelopePointRange and (t1_in - t0_in) > (2 * eps_delete) then
        r.DeleteEnvelopePointRange(env, t0_in + eps_delete, t1_in - eps_delete)
    end

    if v_pre ~= nil then r.InsertEnvelopePoint(env, pre_time, v_pre, 0, 0, 0, true) end
    if v_start ~= nil then r.InsertEnvelopePoint(env, t0_in, v_start, 0, 0, 0, true) end
    if v_end ~= nil then r.InsertEnvelopePoint(env, t1_in, v_end, 0, 0, 0, true) end
    if v_post ~= nil then r.InsertEnvelopePoint(env, post_time, v_post, 0, 0, 0, true) end

    local mode = r.GetEnvelopeScalingMode and r.GetEnvelopeScalingMode(env) or 0
    local zero_amp = 0.0
    local zero_val = r.ScaleToEnvelopeMode and r.ScaleToEnvelopeMode(mode, zero_amp) or zero_amp
    r.InsertEnvelopePoint(env, t0_in, zero_val, 0, 0, 0, true)
    r.InsertEnvelopePoint(env, t1_in, zero_val, 0, 0, 0, true)

    r.Envelope_SortPoints(env)
    return true
end

local function EnsureDCJSFXFile()
    local res = r.GetResourcePath()
    local dir = res .. r.GetOS():find("Win") and "\\Effects\\TK" or "/Effects/TK"
    if r.GetOS():find("Win") then dir = res .. "\\Effects\\TK" else dir = res .. "/Effects/TK" end
    if r.RecursiveCreateDirectory then r.RecursiveCreateDirectory(dir, 0) end
    local file = dir .. (r.GetOS():find("Win") and "\\DC_offset_sampleaccurate.jsfx" or "/DC_offset_sampleaccurate.jsfx")
    local fh = io.open(file, "r")
    if fh then fh:close(); return file end
    local code = [[
desc:TK DC Offset (sample-accurate)

slider1:0<-1,1,0.0001>DC L
slider2:0<-1,1,0.0001>DC R

@init
dcL = 0; dcR = 0;

@slider
dcL = slider1;
dcR = slider2;

@sample
spl0 += dcL;
spl1 += dcR;
]]
    fh = io.open(file, "w")
    if fh then fh:write(code); fh:close() end
    return file
end

local function EnsureTakeDCOffsetFX(take)
    if not take or not ValidTake(take) then return -1 end
    EnsureDCJSFXFile()
    local fxidx = r.TakeFX_AddByName(take, 'JS: DC_offset_sampleaccurate.jsfx', 0)
    if fxidx == -1 then
        fxidx = r.TakeFX_AddByName(take, 'JS: DC_offset_sampleaccurate.jsfx', 1)
        if fxidx ~= -1 then r.TakeFX_SetOpen(take, fxidx, false) end
    end
    return fxidx
end

local function GetDCOffsetEnvelopesForTake(take, fxidx, create)
    if not take or not ValidTake(take) or not fxidx or fxidx < 0 then return nil, nil end
    local make = create and true or false
    local envL = r.TakeFX_GetEnvelope(take, fxidx, 0, make)
    local envR = r.TakeFX_GetEnvelope(take, fxidx, 1, make)
    return envL, envR
end

-- MPL-based target method
function CommitStrokeToDCOffset(take, item, points, item_pos, view_len_px, view_w_px, link_lr, active_lane)
    if not take or not item or not points or #points < 2 then return false end
    if not ValidItem(item) or not ValidTake(take) then return false end
    local fxidx = EnsureTakeDCOffsetFX(take)
    if fxidx == -1 then return false end
    local envL, envR = GetDCOffsetEnvelopesForTake(take, fxidx, true)
    if not envL or not envR then return false end
    local function ConvertNormalizedToRawIfNeeded(env)
        if not env then return end
        local cnt = r.CountEnvelopePoints(env) or 0
        if cnt == 0 then return end
        local max_check = math.min(cnt, 64)
        local allInside01 = true
        local allZeroNorm = true
        for i = 0, max_check - 1 do
            local ok, _, v = r.GetEnvelopePoint(env, i)
            if ok then
                if v < 0.0 or v > 1.0 then allInside01 = false; break end
                if math.abs(v or 0.0) > 1e-12 then allZeroNorm = false end
            end
        end
        if allInside01 then
            for i = 0, cnt - 1 do
                local ok, t, v, sh, ten, sel = r.GetEnvelopePoint(env, i)
                if ok then
                    local raw
                    if allZeroNorm then
                        raw = 0.0
                    else
                        raw = (v * 2.0) - 1.0
                    end
                    if raw < -1.0 then raw = -1.0 elseif raw > 1.0 then raw = 1.0 end
                    r.SetEnvelopePoint(env, i, t, raw, sh, ten, sel, true)
                end
            end
            r.Envelope_SortPoints(env)
        end
    end
    ConvertNormalizedToRawIfNeeded(envL)
    ConvertNormalizedToRawIfNeeded(envR)

    local link = (link_lr ~= false) 
    local lane = active_lane -- 1=Left, 2=Right; only used when not linked

    local it_start = item_pos or 0
    local it_end = it_start + (current_item_len or 0)
    local t0, t1 = math.huge, -math.huge
    for i = 1, #points do
        local t = points[i].t or 0
        if t < t0 then t0 = t end
        if t > t1 then t1 = t end
    end
    if t0 == math.huge or t1 == -math.huge or t1 <= t0 then return false end
    if t0 < it_start then t0 = it_start end
    if t1 > it_end then t1 = it_end end

    local t0_in = t0 - it_start
    local t1_in = t1 - it_start
    local it_len_in = (current_item_len or 0)

    local function eval_env(envh, t_in)
        if r.Envelope_Evaluate then
            local _, val = r.Envelope_Evaluate(envh, t_in, 0, 0)
            if val ~= nil then return val end
        end
        local cnt = r.CountEnvelopePoints(envh) or 0
        local prev_val, next_val = nil, nil
        local prev_time, next_time = -math.huge, math.huge
        for i = 0, cnt - 1 do
            local rv, time, val = r.GetEnvelopePoint(envh, i)
            if rv then
                if time <= t_in and time > prev_time then prev_time, prev_val = time, val end
                if time >= t_in and time < next_time then next_time, next_val = time, val end
            end
        end
        if prev_val ~= nil and next_val ~= nil then
            local tspan = (next_time - prev_time)
            if tspan > 0 then
                local a = (t_in - prev_time) / tspan
                return prev_val + (next_val - prev_val) * a
            else
                return prev_val
            end
        end
        return prev_val or next_val or 0.0
    end

    local min_px = math.max(0.1, draw_min_px_step or DRAW_MIN_PX_STEP)
    local px_to_time = (view_len or 0) / math.max(1, view_w_px or 1)
    local eps_anchor = math.max(0.0005, (min_px * px_to_time) * 0.5)
    local eps_delete = math.max(1e-6, (min_px * px_to_time) * 0.25)

    local pre_time = math.max(0, t0_in - eps_anchor)
    local post_time = math.min((current_item_len or 0), t1_in + eps_anchor)

    local vL_start = eval_env(envL, t0_in)
    local vL_end   = eval_env(envL, t1_in)
    local vL_pre   = eval_env(envL, pre_time)
    local vL_post  = eval_env(envL, post_time)
    local vR_start = eval_env(envR, t0_in)
    local vR_end   = eval_env(envR, t1_in)
    local vR_pre   = eval_env(envR, pre_time)
    local vR_post  = eval_env(envR, post_time)

    local cntL = r.CountEnvelopePoints(envL) or 0
    local cntR = r.CountEnvelopePoints(envR) or 0
    if cntL == 0 then vL_start, vL_end, vL_pre, vL_post = 0.0, 0.0, 0.0, 0.0 end
    if cntR == 0 then vR_start, vR_end, vR_pre, vR_post = 0.0, 0.0, 0.0, 0.0 end

    if r.DeleteEnvelopePointRange and (t1_in - t0_in) > (2 * eps_delete) then
        if link or lane == 1 or not lane then r.DeleteEnvelopePointRange(envL, t0_in + eps_delete, t1_in - eps_delete) end
        if link or lane == 2 or not lane then r.DeleteEnvelopePointRange(envR, t0_in + eps_delete, t1_in - eps_delete) end
    end

    local function has_point_before(envh, t)
        local cnt = r.CountEnvelopePoints(envh) or 0
        for i = 0, cnt - 1 do
            local ok, ti = r.GetEnvelopePoint(envh, i)
            if ok and ti < (t - 1e-9) then return true end
        end
        return false
    end
    local function has_point_after(envh, t)
        local cnt = r.CountEnvelopePoints(envh) or 0
        for i = cnt - 1, 0, -1 do
            local ok, ti = r.GetEnvelopePoint(envh, i)
            if ok and ti > (t + 1e-9) then return true end
        end
        return false
    end
    if link or lane == 1 or not lane then
    if not has_point_before(envL, pre_time) then r.InsertEnvelopePoint(envL, 0.0, vL_pre, 0, 0, 0, true) end
    if it_len_in and it_len_in > 0 and not has_point_after(envL, post_time) then r.InsertEnvelopePoint(envL, it_len_in, vL_post, 0, 0, 0, true) end
    end
    if link or lane == 2 or not lane then
    if not has_point_before(envR, pre_time) then r.InsertEnvelopePoint(envR, 0.0, vR_pre, 0, 0, 0, true) end
    if it_len_in and it_len_in > 0 and not has_point_after(envR, post_time) then r.InsertEnvelopePoint(envR, it_len_in, vR_post, 0, 0, 0, true) end
    end

    if link or lane == 1 or not lane then
    r.InsertEnvelopePoint(envL, pre_time,  vL_pre,  0, 0, 0, true)
    r.InsertEnvelopePoint(envL, t0_in,     vL_start,0, 0, 0, true)
    r.InsertEnvelopePoint(envL, t1_in,     vL_end,  0, 0, 0, true)
    r.InsertEnvelopePoint(envL, post_time, vL_post, 0, 0, 0, true)
    end
    if link or lane == 2 or not lane then
    r.InsertEnvelopePoint(envR, pre_time,  vR_pre,  0, 0, 0, true)
    r.InsertEnvelopePoint(envR, t0_in,     vR_start,0, 0, 0, true)
    r.InsertEnvelopePoint(envR, t1_in,     vR_end,  0, 0, 0, true)
    r.InsertEnvelopePoint(envR, post_time, vR_post, 0, 0, 0, true)
    end

    local min_dt = min_px * px_to_time
    local last_t_in = nil
    local unsorted = true

    local function ensure_neutral_baseline(envh)
        if not envh then return end
        local cnt = r.CountEnvelopePoints(envh) or 0
        if cnt == 0 then
            r.InsertEnvelopePoint(envh, 0.0, 0.0, 0, 0, 0, true)
            if it_len_in and it_len_in > 0 then
                r.InsertEnvelopePoint(envh, it_len_in, 0.0, 0, 0, 0, true)
            end
        end
    end
    if link or lane == 1 or not lane then ensure_neutral_baseline(envL) end
    if link or lane == 2 or not lane then ensure_neutral_baseline(envR) end

    local temp_accessor = nil
    local acc = current_accessor
    if not acc then
        temp_accessor = r.CreateTakeAudioAccessor(take)
        acc = temp_accessor
    end
    local numch = math.max(1, channels or 1)
    local sr = math.max(2000, math.min(192000, sample_rate or 44100))
    local buf = r.new_array(numch)

    local function SampleStereoAtAbs(t_abs)
        if not acc then return 0.0, 0.0 end
        local acc_start = t_abs - (current_item_start or 0)
        if acc_start < 0 then acc_start = 0 end
        local ok = r.GetAudioAccessorSamples(acc, sr, numch, acc_start, 1, buf)
        if not ok then return 0.0, 0.0 end
        local L = buf[1] or 0.0
        local R = (numch >= 2) and (buf[2] or 0.0) or L
        return L, R
    end

    for i = 1, #points do
        local p = points[i]
        local t_abs = (p.t or 0)
        local t_in = t_abs - it_start
        if t_in >= t0_in and t_in <= t1_in then
            if (not last_t_in) or (t_in - last_t_in >= (min_dt or 0)) then
                local target = math.max(-1.0, math.min(1.0, p.v or 0))
                local sL, sR = SampleStereoAtAbs(t_abs)
                local vL = math.max(-1.0, math.min(1.0, target - (sL or 0.0)))
                local vR = math.max(-1.0, math.min(1.0, target - (sR or 0.0)))
                local outL = vL; if outL < -1.0 then outL = -1.0 elseif outL > 1.0 then outL = 1.0 end
                local outR = vR; if outR < -1.0 then outR = -1.0 elseif outR > 1.0 then outR = 1.0 end
                if link or lane == 1 or not lane then r.InsertEnvelopePoint(envL, t_in, outL, 0, 0, 0, unsorted) end
                if link or lane == 2 or not lane then r.InsertEnvelopePoint(envR, t_in, outR, 0, 0, 0, unsorted) end
                last_t_in = t_in
            end
        end
    end
    if temp_accessor then r.DestroyAudioAccessor(temp_accessor) end
    if link or lane == 1 or not lane then r.Envelope_SortPoints(envL) end
    if link or lane == 2 or not lane then r.Envelope_SortPoints(envR) end
    return true
end

local function ColorWithAlpha(color, alpha)
    local a = math.max(0, math.min(255, math.floor((alpha or 1.0) * 255 + 0.5)))
    return (color & 0xFFFFFF00) | a
end

local function clamp01(v)
    if v < 0 then return 0 elseif v > 1 then return 1 else return v end
end

local function MakeRGBColor(r, g, b)
    r = math.floor(math.max(0, math.min(255, r)) + 0.5)
    g = math.floor(math.max(0, math.min(255, g)) + 0.5)
    b = math.floor(math.max(0, math.min(255, b)) + 0.5)
    return (r << 24) | (g << 16) | (b << 8) | 0x00
end

local function LerpColor(c1, c2, t)
    local r1 = (c1 >> 24) & 0xFF; local g1 = (c1 >> 16) & 0xFF; local b1 = (c1 >> 8) & 0xFF
    local r2 = (c2 >> 24) & 0xFF; local g2 = (c2 >> 16) & 0xFF; local b2 = (c2 >> 8) & 0xFF
    local function lerp(a,b,p) return a + (b - a) * p end
    return MakeRGBColor(lerp(r1, r2, t), lerp(g1, g2, t), lerp(b1, b2, t))
end

local SPECTRAL_GRADIENT = {
    {0.00, MakeRGBColor(255, 51, 0)},
    {0.25, MakeRGBColor(255, 170, 0)},
    {0.50, MakeRGBColor(51, 204, 51)},
    {0.75, MakeRGBColor(51, 153, 255)},
    {1.00, MakeRGBColor(170, 51, 255)}
}

local function spectral_color(z)
    z = clamp01(z or 0)
    for i = 1, #SPECTRAL_GRADIENT - 1 do
        local a = SPECTRAL_GRADIENT[i]
        local b = SPECTRAL_GRADIENT[i + 1]
        if z >= a[1] and z <= b[1] then
            local t = (z - a[1]) / (b[1] - a[1] + 1e-12)
            return LerpColor(a[2], b[2], t)
        end
    end
    return SPECTRAL_GRADIENT[#SPECTRAL_GRADIENT][2]
end

local function apply_brightness(c, f)
    local r = ((c >> 24) & 0xFF) * f
    local g = ((c >> 16) & 0xFF) * f
    local b = ((c >> 8) & 0xFF) * f
    return MakeRGBColor(r, g, b)
end

local DB_TICKS = { -3, -6, -9, -12 }
local DB_LABEL_MIN_PX = 12.0

local function DrawDbOverlay(draw_list, x, y, w, h)
    if not show_db_scale or not current_item or (view_len or 0) <= 0 then return end
    local db_col = ColorWithAlpha(COLOR_GRID_BASE, db_alpha or 0.55)
    local label_col = ColorWithAlpha(COLOR_RULER_TEXT, 0.9)
    local gutter_x = x - LEFT_GUTTER_W
    local gutter_right = x
    local function right_aligned_label(text, y_label)
        local tw, _ = r.ImGui_CalcTextSize(ctx, text)
        local lx = gutter_right - 4.0 - (tw or 0)
        if lx < gutter_x + 2.0 then lx = gutter_x + 2.0 end
        r.ImGui_DrawList_AddText(draw_list, lx, y_label, label_col, text)
    end
    local function draw_db_lane(y0, yh)
        local lane_center = y0 + yh * 0.5
        local lane_scale = (yh * 0.5) * 0.9 * (amp_zoom or 1.0)
        local positions = {}
        local function add_pos(ypos, text)
            if ypos >= y0 and ypos <= (y0 + yh) then positions[#positions + 1] = { y = ypos, t = text } end
        end
        local y0db_top = lane_center - (1.0 * lane_scale)
        local y0db_bot = lane_center + (1.0 * lane_scale)
        add_pos(y0db_top, "0 dB"); add_pos(y0db_bot, "0 dB")
        if y0db_top >= y0 and y0db_top <= (y0 + yh) then
            r.ImGui_DrawList_AddLine(draw_list, x, y0db_top, x + w, y0db_top, db_col, 1.0)
        end
        if y0db_bot >= y0 and y0db_bot <= (y0 + yh) then
            r.ImGui_DrawList_AddLine(draw_list, x, y0db_bot, x + w, y0db_bot, db_col, 1.0)
        end
        add_pos(lane_center, "-∞ dB")
        for i = 1, #DB_TICKS do
            local dbv = DB_TICKS[i]
            local amp = 10 ^ (dbv / 20.0)
            local off = amp * lane_scale
            local yt = lane_center - off
            add_pos(yt, string.format("%d dB", dbv))
            if yt >= y0 and yt <= (y0 + yh) then r.ImGui_DrawList_AddLine(draw_list, x, yt, x + w, yt, db_col, 1.0) end
            local yb = lane_center + off
            if yb >= y0 and yb <= (y0 + yh) then
                r.ImGui_DrawList_AddLine(draw_list, x, yb, x + w, yb, db_col, 1.0)
                if db_labels_mirrored then add_pos(yb, string.format("%d dB", dbv)) end
            end
        end
        table.sort(positions, function(a,b) return a.y < b.y end)
        local last_label_y = -1e9
        for _,pos in ipairs(positions) do
            if (pos.y - last_label_y) >= DB_LABEL_MIN_PX then
                r.ImGui_DrawList_PushClipRect(draw_list, gutter_x, y0, x, y0 + yh, false)
                right_aligned_label(pos.t, pos.y - 10)
                r.ImGui_DrawList_PopClipRect(draw_list)
                last_label_y = pos.y
            end
        end
    end
    if draw_channels_separately and channels >= 2 then
        local lane_h = h * 0.5
        draw_db_lane(y, lane_h)
        draw_db_lane(y + lane_h, lane_h)
    else
        draw_db_lane(y, h)
    end
end

function amp_to_db(a)
    if not a or a <= 0 then return VOL_DB_MIN end
    return 20.0 * math.log(a, 10)
end

function db_to_amp(db)
    return 10 ^ ((db or 0) / 20.0)
end

local function vol_db_to_y(db, top_y, bot_y)
    local ty = top_y or 0
    local by = bot_y or 1
    if by < ty then ty, by = by, ty end
    local cy = (ty + by) * 0.5
    local d = math.max(VOL_DB_MIN, math.min(VOL_DB_MAX, db or 0))
    if d >= 0 then
        local k = (VOL_DB_MAX ~= 0) and (d / VOL_DB_MAX) or 0
        return cy - k * (cy - ty)
    else
        local k = (VOL_DB_MIN ~= 0) and (d / VOL_DB_MIN) or 0 
        return cy + k * (by - cy)
    end
end

local function vol_y_to_db(y, top_y, bot_y)
    local ty = top_y or 0
    local by = bot_y or 1
    if by < ty then ty, by = by, ty end
    local yy = math.max(ty, math.min(by, y or ty))
    local cy = (ty + by) * 0.5
    if yy <= cy then
        local k = (cy - ty) > 0 and ((cy - yy) / (cy - ty)) or 0
        return k * VOL_DB_MAX
    else
        local k = (by - cy) > 0 and ((yy - cy) / (by - cy)) or 0
        return -k * math.abs(VOL_DB_MIN)
    end
end

local function EvalFadeIn(shape, dir, t)
    if t <= 0 then return 0 end
    if t >= 1 then return 1 end
    local s0 = shape or 0
    local s = math.floor(s0 + 1) -- 1..7
    if s < 1 then s = 1 elseif s > 7 then s = 7 end

    -- Types (Fade In):
    -- 1 Linear
    -- 2 Parabolic slow start
    -- 3 Logarithmic slow start
    -- 4 Parabolic fast start
    -- 5 Logarithmic fast start
    -- 6 S-curve (cosine)
    -- 7 S-curve square (sharper center, flatter ends)
    if s == 1 then
        return t
    elseif s == 2 then
        return 1 - (1 - t) ^ 2
    elseif s == 3 then
        return t * t
    elseif s == 4 then
        return 1 - (1 - t) ^ 4
    elseif s == 5 then
        return t ^ 4
    elseif s == 6 then
        return 0.5 - 0.5 * math.cos(math.pi * t)
    else -- s == 7
        local s1 = 0.5 - 0.5 * math.cos(math.pi * t) 
        if s1 < 0.5 then
            local a = s1 * 2.0
            return 0.5 * (a * a)
        else
            local b = (1.0 - s1) * 2.0
            return 1.0 - 0.5 * (b * b)
        end
    end
end

local function EvalFadeOut(shape, dir, t)
  
    if t <= 0 then return 1 end
    if t >= 1 then return 0 end
    local s1 = math.floor((shape or 0) + 1) -- 1..7
    if s1 < 1 then s1 = 1 elseif s1 > 7 then s1 = 7 end
    local s = s1
    if s == 2 then s = 3
    elseif s == 3 then s = 2
    elseif s == 4 then s = 5
    elseif s == 5 then s = 4
    end
    return 1 - EvalFadeIn(s - 1, dir, t)
end

local function SpectralSRForWindow(win_len)
    local sr = spectral_fixed_sr
    if win_len and win_len > 0 then
        local cap = math.floor(spectral_samples_budget / math.max(1e-6, win_len))
        if cap > 0 then sr = math.min(sr, cap) end
    end
    if sr < spectral_sr_min then sr = spectral_sr_min end
    if sr > spectral_sr_max then sr = spectral_sr_max end
    return sr
end

local function ResetPeakPyramid()
    peak_pyr = { levels = {}, item_len = current_item_len or 0.0, item_start = current_item_start or 0.0, item_guid = nil, built = false }
end

local function ResetPeakPyramidCh()
    peak_pyr_ch = { levels = {}, item_len = current_item_len or 0.0, item_start = current_item_start or 0.0, item_guid = nil, built = false }
end

local function QuickStatsForRange(t_abs_a, t_abs_b)
    if not current_item or not current_accessor or not current_item_len or current_item_len <= 0 then return nil end
    local a = math.max(current_item_start or 0, math.min(t_abs_a or current_item_start, t_abs_b or (current_item_start + current_item_len)))
    local b = math.min((current_item_start or 0) + (current_item_len or 0), math.max(t_abs_a or current_item_start, t_abs_b or (current_item_start + current_item_len)))
    if b <= a then return nil end
    local numch = math.max(1, channels or 1)
    local win = b - a
    local MAX_SAMPLES = 380000
    local target_sr = math.max(8000, math.min(48000, math.floor(MAX_SAMPLES / math.max(1e-3, win))))
    local total = math.max(1, math.floor(target_sr * win + 0.5))
    local CHUNK = 65536
    local sums = {}; local sums2 = {}; local peaks = {}
    for ch = 1, numch do sums[ch], sums2[ch], peaks[ch] = 0.0, 0.0, 0.0 end
    local processed = 0
    while processed < total do
        local n = math.min(CHUNK, total - processed)
        local t0 = (processed / target_sr)
        local buf = r.new_array(n * numch)
        local ok = r.GetAudioAccessorSamples(current_accessor, target_sr, numch, (a - (current_item_start or 0)) + t0, n, buf)
        if not ok then break end
        local bi = 1
        for i = 1, n do
            for ch = 1, numch do
                local v = buf[bi] or 0.0
                sums[ch]  = sums[ch] + v
                sums2[ch] = sums2[ch] + v * v
                local av = v; if av < 0 then av = -av end
                if av > peaks[ch] then peaks[ch] = av end
                bi = bi + 1
            end
        end
        processed = processed + n
    end
    local N = math.max(1, total)
    local stats = { sr = target_sr, samples = N, t0 = a, t1 = b, ch = numch, dc = {}, rms = {}, peak = {} }
    for ch = 1, numch do
        stats.dc[ch]   = sums[ch] / N
        stats.rms[ch]  = math.sqrt(sums2[ch] / N)
        stats.peak[ch] = peaks[ch]
    end
    return stats
end

local function DbFS(a)
    if not a or a <= 0 then return -144.0 end
    return 20.0 * math.log(a, 10)
end

local function UpdateInfoStatsIfNeeded()
    if not info_open or not current_item or not current_accessor then return end
    local _, guid = r.GetSetMediaItemInfo_String(current_item, "GUID", "", false)
    local vt0 = view_start or 0
    local vt1 = (view_start or 0) + (view_len or 0)
    local key = string.format("%s|%.6f|%.6f|%d", tostring(guid or ""), vt0, vt1, channels or 1)
    local now = r.time_precise()
    local needs = (info_item_guid ~= guid) or (info_range_key ~= key) or ((now - (info_last_calc or 0)) > 0.50) or (not info_stats)
    if not needs then return end
    info_stats = QuickStatsForRange(vt0, vt1)
    info_item_guid = guid
    info_range_key = key
    info_last_calc = now
end

local function DrawItemInfoPanel(draw_list, x, y, w, h)
    if not info_open or not current_item then return end
    UpdateInfoStatsIfNeeded()
    local pad = 10.0
    local panel_w = 320.0
    local line_h = 17.0
    local lines = {}
    local take = current_take
    local rate = take and r.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE") or 1.0
    local offs = take and r.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS") or 0.0
    local amp  = r.GetMediaItemInfo_Value(current_item, "D_VOL") or 1.0
    local db   = DbFS(amp)
    local phase_on = IsItemPolarityInverted and IsItemPolarityInverted(current_item)
    local name = filename or "Unknown"
    local len  = current_item_len or 0
    local pos  = current_item_start or 0
    local s, e = GetSelectionRangeClamped()
    local sel_txt = (s and string.format("%.3f..%.3f (%.3fs)", s, e, e - s)) or "-"
    lines[#lines + 1] = "General"
    lines[#lines + 1] = string.format("  Name: %s", name)
    lines[#lines + 1] = string.format("  Pos: %.3f  Len: %.3f", pos, len)
    lines[#lines + 1] = string.format("  SR: %.0f  Ch: %d  Rate: %.3fx", sample_rate or 0, channels or 1, rate or 1)
    lines[#lines + 1] = string.format("  Offset: %.3f  Vol: %.1f dB  Phase: %s", offs or 0, db, phase_on and "On" or "Off")
    lines[#lines + 1] = "Selection"
    lines[#lines + 1] = string.format("  %s", sel_txt)
    if info_stats then
        local dcL = info_stats.dc[1] or 0
        local rmsL = info_stats.rms[1] or 0
        local pkL = info_stats.peak[1] or 0
        local dcR = (channels >= 2) and (info_stats.dc[2] or 0) or dcL
        local rmsR = (channels >= 2) and (info_stats.rms[2] or 0) or rmsL
        local pkR = (channels >= 2) and (info_stats.peak[2] or 0) or pkL
        lines[#lines + 1] = "Levels (view)"
        lines[#lines + 1] = string.format("  L: Peak %.1f dB  RMS %.1f dB  DC %+0.4f", DbFS(pkL), DbFS(rmsL), dcL)
        if channels >= 2 then
            lines[#lines + 1] = string.format("  R: Peak %.1f dB  RMS %.1f dB  DC %+0.4f", DbFS(pkR), DbFS(rmsR), dcR)
        end
    end
    local panel_h = pad * 2 + (#lines * line_h) + 6.0
    local px = x + w - panel_w - 10.0
    local py = y + h - panel_h - 10.0
    local dlp = r.ImGui_GetForegroundDrawList(ctx)
    local bg = 0x000000AA
    r.ImGui_DrawList_AddRectFilled(dlp, px, py, px + panel_w, py + panel_h, bg, 6.0)
    r.ImGui_DrawList_AddRect(dlp, px, py, px + panel_w, py + panel_h, 0xFFFFFFFF, 6.0, 0, 1.0)
    local tx = px + pad
    local ty = py + pad
    for i = 1, #lines do
        local sline = lines[i]
        local is_hdr = (sline == "General") or (sline == "Selection") or (sline == "Levels (view)")
        local col = is_hdr and 0xFFD24DFF or 0xFFFFFFFF
        if is_hdr then
            r.ImGui_DrawList_AddTextEx(dlp, font_big, 16, tx, ty, col, sline)
        else
            r.ImGui_DrawList_AddText(dlp, tx, ty, col, sline)
        end
        ty = ty + line_h
    end
    local close_label = "Close"
    local cw, ch = r.ImGui_CalcTextSize(ctx, close_label)
    local cx = px + panel_w - cw - pad
    local cy = py + pad * 0.4
    local mx, my = r.ImGui_GetMousePos(ctx)
    local hov = (mx >= cx and mx <= (cx + cw) and my >= cy and my <= (cy + ch))
    local tcol = hov and UI_TEXT_HOVER or 0xFFFFFFFF
    r.ImGui_DrawList_AddText(dlp, cx, cy, tcol, close_label)
    if hov and r.ImGui_IsMouseClicked(ctx, 0) then info_open = false end
end

local function BuildPeakLevel(bins, overs)
    if not current_accessor or not current_item or (current_item_len or 0) <= 0 then return nil end
    local numch = math.max(1, channels)
    local mins, maxs = {}, {}
    for i = 1, bins do mins[i] = 1e9; maxs[i] = -1e9 end

    local item_len = current_item_len
    local sr = math.min(192000, math.max(1000, math.ceil((bins * overs) / item_len)))
    local total = math.max(1, math.floor(sr * item_len + 0.5))
    local CHUNK = 65536
    local processed = 0
    while processed < total do
        local remain = total - processed
        local n = (remain > CHUNK) and CHUNK or remain
        local start_time = (processed / sr)
        local buf = r.new_array(n * numch)
        local ok = r.GetAudioAccessorSamples(current_accessor, sr, numch, start_time, n, buf)
        if not ok then break end
        local bi = 1
        for i = 1, n do
            local t = (processed + (i - 1)) / sr
            local rel = t / item_len -- 0..1
            local p = math.floor(rel * bins) + 1
            if p < 1 then p = 1 elseif p > bins then p = bins end
            local mn, mx = 1e9, -1e9
            local base = bi - 1
            for ch = 1, numch do
                local v = buf[base + ch] or 0.0
                if v < mn then mn = v end
                if v > mx then mx = v end
            end
            if mn < mins[p] then mins[p] = mn end
            if mx > maxs[p] then maxs[p] = mx end
            bi = bi + numch
        end
        processed = processed + n
    end
    local last = nil
    for i = 1, bins do
        if mins[i] == 1e9 or maxs[i] == -1e9 then
            if last then mins[i], maxs[i] = mins[last], maxs[last] end
        else
            last = i
        end
    end
    if last == nil then
        for i = 1, bins do mins[i], maxs[i] = 0.0, 0.0 end
    else
        for i = bins, 1, -1 do
            if mins[i] == 1e9 or maxs[i] == -1e9 then
                mins[i], maxs[i] = mins[last], maxs[last]
            else
                last = i
            end
        end
    end
    return { bins = bins, mins = mins, maxs = maxs }
end

local function BuildPeakLevelCh(bins, overs)
    if not current_accessor or not current_item or (current_item_len or 0) <= 0 then return nil end
    local numch = math.max(1, channels)
    local use_ch = math.min(2, numch)
    local mins_ch, maxs_ch = {}, {}
    for ch = 1, use_ch do
        mins_ch[ch], maxs_ch[ch] = {}, {}
        for i = 1, bins do mins_ch[ch][i] = 1e9; maxs_ch[ch][i] = -1e9 end
    end

    local item_len = current_item_len
    local sr = math.min(192000, math.max(1000, math.ceil((bins * overs) / item_len)))
    local total = math.max(1, math.floor(sr * item_len + 0.5))
    local CHUNK = 65536
    local processed = 0
    while processed < total do
        local remain = total - processed
        local n = (remain > CHUNK) and CHUNK or remain
        local start_time = (processed / sr)
        local buf = r.new_array(n * numch)
        local ok = r.GetAudioAccessorSamples(current_accessor, sr, numch, start_time, n, buf)
        if not ok then break end
        local bi = 1
        for i = 1, n do
            local t = (processed + (i - 1)) / sr
            local rel = t / item_len
            local p = math.floor(rel * bins) + 1
            if p < 1 then p = 1 elseif p > bins then p = bins end
            local base = bi - 1
            for ch = 1, use_ch do
                local v = buf[base + ch] or 0.0
                if v < mins_ch[ch][p] then mins_ch[ch][p] = v end
                if v > maxs_ch[ch][p] then maxs_ch[ch][p] = v end
            end
            bi = bi + numch
        end
        processed = processed + n
    end
    for ch = 1, use_ch do
        local mins, maxs = mins_ch[ch], maxs_ch[ch]
        local last = nil
        for i = 1, bins do
            if mins[i] == 1e9 or maxs[i] == -1e9 then
                if last then mins[i], maxs[i] = mins[last], maxs[last] end
            else
                last = i
            end
        end
        if last == nil then
            for i = 1, bins do mins[i], maxs[i] = 0.0, 0.0 end
        else
            for i = bins, 1, -1 do
                if mins[i] == 1e9 or maxs[i] == -1e9 then
                    mins[i], maxs[i] = mins[last], maxs[last]
                else
                    last = i
                end
            end
        end
    end
    return { bins = bins, mins_ch = mins_ch, maxs_ch = maxs_ch }
end

local function BuildPeakPyramid()
    ResetPeakPyramid()
    if not current_accessor or not current_item or (current_item_len or 0) <= 0 then return end
    
    local L0_BINS = 16384
   
    local L1_BINS = math.min(262144, L0_BINS * 4)
    
    local L2_BINS = math.min(524288, L1_BINS * 2)
    local lvl0 = BuildPeakLevel(L0_BINS, 8)
    local lvl1 = BuildPeakLevel(L1_BINS, 4)
    local lvl2 = BuildPeakLevel(L2_BINS, 2)
    peak_pyr.levels = {}
    if lvl0 then table.insert(peak_pyr.levels, lvl0) end
    if lvl1 then table.insert(peak_pyr.levels, lvl1) end
    if lvl2 then table.insert(peak_pyr.levels, lvl2) end
    peak_pyr.item_len = current_item_len
    peak_pyr.item_start = current_item_start
    local _, guid = r.GetSetMediaItemInfo_String(current_item, "GUID", "", false)
    peak_pyr.item_guid = guid
    peak_pyr.built = (#peak_pyr.levels > 0)
end

local function BuildPeakPyramidCh()
    ResetPeakPyramidCh()
    if not current_accessor or not current_item or (current_item_len or 0) <= 0 then return end
    local L0_BINS = 16384
    local L1_BINS = math.min(262144, L0_BINS * 4)
    local L2_BINS = math.min(524288, L1_BINS * 2)
    local lvl0 = BuildPeakLevelCh(L0_BINS, 8)
    local lvl1 = BuildPeakLevelCh(L1_BINS, 4)
    local lvl2 = BuildPeakLevelCh(L2_BINS, 2)
    peak_pyr_ch.levels = {}
    if lvl0 then table.insert(peak_pyr_ch.levels, lvl0) end
    if lvl1 then table.insert(peak_pyr_ch.levels, lvl1) end
    if lvl2 then table.insert(peak_pyr_ch.levels, lvl2) end
    peak_pyr_ch.item_len = current_item_len
    peak_pyr_ch.item_start = current_item_start
    local _, guid = r.GetSetMediaItemInfo_String(current_item, "GUID", "", false)
    peak_pyr_ch.item_guid = guid
    peak_pyr_ch.built = (#peak_pyr_ch.levels > 0)
end

local function ChoosePyrLevel(pixels)
    if not peak_pyr or not peak_pyr.built or not peak_pyr.levels or #peak_pyr.levels == 0 then return nil end
    local view_bins_needed = math.max(1, math.floor((pixels * (view_len / math.max(1e-12, peak_pyr.item_len))) + 0.5))
    dbg_view_bins_needed = view_bins_needed
    local best = peak_pyr.levels[#peak_pyr.levels]
    for i = 1, #peak_pyr.levels do
        local L = peak_pyr.levels[i]
        if L.bins >= view_bins_needed then best = L; break end
    end
    dbg_pyr_level_bins = best and best.bins or nil
    return best
end

local function ChoosePyrLevelCh(pixels)
    if not peak_pyr_ch or not peak_pyr_ch.built or not peak_pyr_ch.levels or #peak_pyr_ch.levels == 0 then return nil end
    local view_bins_needed = math.max(1, math.floor((pixels * (view_len / math.max(1e-12, peak_pyr_ch.item_len))) + 0.5))
    dbg_view_bins_needed = view_bins_needed
    local best = peak_pyr_ch.levels[#peak_pyr_ch.levels]
    for i = 1, #peak_pyr_ch.levels do
        local L = peak_pyr_ch.levels[i]
        if L.bins >= view_bins_needed then best = L; break end
    end
    dbg_pyr_level_bins = best and best.bins or nil
    return best
end

local INTERACTION_GRACE = 0.12
local MAX_SAMPLES_IDLE = 500000
local MAX_SAMPLES_INTERACTIVE = 300000

local EXT_SECTION = "TK_Audio_Editor"

local function SaveSettings()
    r.SetExtState(EXT_SECTION, "show_grid", show_grid and "1" or "0", true)
    r.SetExtState(EXT_SECTION, "show_ruler", show_ruler and "1" or "0", true)
    r.SetExtState(EXT_SECTION, "grid_alpha", tostring(grid_alpha or 0.9), true)
    r.SetExtState(EXT_SECTION, "db_alpha", tostring(db_alpha or 0.55), true)
    r.SetExtState(EXT_SECTION, "ruler_beats", ruler_beats and "1" or "0", true)
    r.SetExtState(EXT_SECTION, "show_edit_cursor", show_edit_cursor and "1" or "0", true)
    r.SetExtState(EXT_SECTION, "show_play_cursor", show_play_cursor and "1" or "0", true)
    r.SetExtState(EXT_SECTION, "click_sets_edit_cursor", click_sets_edit_cursor and "1" or "0", true)
    r.SetExtState(EXT_SECTION, "click_seeks_playback", click_seeks_playback and "1" or "0", true)
    r.SetExtState(EXT_SECTION, "snap_click_to_grid", snap_click_to_grid and "1" or "0", true)
    r.SetExtState(EXT_SECTION, "require_shift_for_selection", require_shift_for_selection and "1" or "0", true)
    r.SetExtState(EXT_SECTION, "show_tooltips", show_tooltips and "1" or "0", true)
    r.SetExtState(EXT_SECTION, "amp_zoom", tostring(amp_zoom or 1.0), true)
    r.SetExtState(EXT_SECTION, "view_oversample", tostring(view_oversample or 4), true)
    r.SetExtState(EXT_SECTION, "view_detail_mode", view_detail_mode or "fixed", true)
    r.SetExtState(EXT_SECTION, "waveform_soft_edges", waveform_soft_edges and "1" or "0", true)
    r.SetExtState(EXT_SECTION, "waveform_outline_paths", waveform_outline_paths and "1" or "0", true)
    r.SetExtState(EXT_SECTION, "waveform_centerline_thickness", tostring(waveform_centerline_thickness or 1.25), true)
    r.SetExtState(EXT_SECTION, "waveform_fill_alpha", tostring(waveform_fill_alpha or 0.18), true)
    r.SetExtState(EXT_SECTION, "transport_item_only", transport_item_only and "1" or "0", true)
    r.SetExtState(EXT_SECTION, "sidebar_collapsed", sidebar_collapsed and "1" or "0", true)
    r.SetExtState(EXT_SECTION, "ripple_item", ripple_item and "1" or "0", true)
    r.SetExtState(EXT_SECTION, "glue_include_touching", glue_include_touching and "1" or "0", true)
    r.SetExtState(EXT_SECTION, "spectral_peaks", spectral_peaks and "1" or "0", true)
    r.SetExtState(EXT_SECTION, "spectral_lock_sr", spectral_lock_sr and "1" or "0", true)
    r.SetExtState(EXT_SECTION, "spectral_max_zcr_hz", tostring(spectral_max_zcr_hz or 8000), true)
    r.SetExtState(EXT_SECTION, "draw_channels_separately", draw_channels_separately and "1" or "0", true)
    r.SetExtState(EXT_SECTION, "show_db_scale", show_db_scale and "1" or "0", true)
    r.SetExtState(EXT_SECTION, "show_footer", show_footer and "1" or "0", true)
    r.SetExtState(EXT_SECTION, "show_fades", show_fades and "1" or "0", true)
    r.SetExtState(EXT_SECTION, "show_env_overlay", show_env_overlay and "1" or "0", true)
    r.SetExtState(EXT_SECTION, "show_dc_overlay", show_dc_overlay and "1" or "0", true)
    r.SetExtState(EXT_SECTION, "show_pan_overlay", show_pan_overlay and "1" or "0", true)
    r.SetExtState(EXT_SECTION, "show_vol_points", show_vol_points and "1" or "0", true)
    r.SetExtState(EXT_SECTION, "show_transport_overlay", show_transport_overlay and "1" or "0", true)
    r.SetExtState(EXT_SECTION, "pan_color_overlay", pan_color_overlay and "1" or "0", true)
    r.SetExtState(EXT_SECTION, "pan_visual_waveform", pan_visual_waveform and "1" or "0", true)
    r.SetExtState(EXT_SECTION, "glue_after_normalize_sel", glue_after_normalize_sel and "1" or "0", true)
    r.SetExtState(EXT_SECTION, "prefer_sws_normalize", prefer_sws_normalize and "1" or "0", true)
    r.SetExtState(EXT_SECTION, "sws_norm_named_cmd", sws_norm_named_cmd or "", true)
    r.SetExtState(EXT_SECTION, "pencil_target", pencil_target or "dc_offset", true)
    r.SetExtState(EXT_SECTION, "draw_min_px_step", tostring(draw_min_px_step or 1.0), true)
    r.SetExtState(EXT_SECTION, "dc_link_lr", dc_link_lr and "1" or "0", true)
    r.SetExtState(EXT_SECTION, "game_starfield", game_starfield and "1" or "0", true)
end

local function LoadSettings()
    local sg = r.GetExtState(EXT_SECTION, "show_grid")
    if sg ~= nil and sg ~= "" then
        show_grid = (sg == "1" or sg == "true")
    end
    local sr = r.GetExtState(EXT_SECTION, "show_ruler")
    if sr ~= nil and sr ~= "" then
        show_ruler = (sr == "1" or sr == "true")
    end
    local ga = r.GetExtState(EXT_SECTION, "grid_alpha")
    local dba = r.GetExtState(EXT_SECTION, "db_alpha")
    if ga ~= nil and ga ~= "" then
        local v = tonumber(ga)
        if v then grid_alpha = math.max(0.05, math.min(1.0, v)) end
    end
    if dba ~= nil and dba ~= "" then
        local v = tonumber(dba)
        if v then db_alpha = math.max(0.05, math.min(1.0, v)) end
    end
    local rb = r.GetExtState(EXT_SECTION, "ruler_beats")
    if rb ~= nil and rb ~= "" then
        ruler_beats = (rb == "1" or rb == "true")
    end
    local sec = r.GetExtState(EXT_SECTION, "show_edit_cursor")
    if sec ~= nil and sec ~= "" then
        show_edit_cursor = (sec == "1" or sec == "true")
    end
    local spc = r.GetExtState(EXT_SECTION, "show_play_cursor")
    if spc ~= nil and spc ~= "" then
        show_play_cursor = (spc == "1" or spc == "true")
    end
    local csec = r.GetExtState(EXT_SECTION, "click_sets_edit_cursor")
    if csec ~= nil and csec ~= "" then
        click_sets_edit_cursor = (csec == "1" or csec == "true")
    end
    local csp = r.GetExtState(EXT_SECTION, "click_seeks_playback")
    if csp ~= nil and csp ~= "" then
        click_seeks_playback = (csp == "1" or csp == "true")
    end
    local scg = r.GetExtState(EXT_SECTION, "snap_click_to_grid")
    if scg ~= nil and scg ~= "" then
        snap_click_to_grid = (scg == "1" or scg == "true")
    end
    local rss = r.GetExtState(EXT_SECTION, "require_shift_for_selection")
    if rss ~= nil and rss ~= "" then
        require_shift_for_selection = (rss == "1" or rss == "true")
    end
    local stt = r.GetExtState(EXT_SECTION, "show_tooltips")
    if stt ~= nil and stt ~= "" then
        show_tooltips = (stt == "1" or stt == "true")
    end
    local az = r.GetExtState(EXT_SECTION, "amp_zoom")
    if az ~= nil and az ~= "" then
        local v = tonumber(az)
        if v then amp_zoom = math.max(0.1, math.min(10.0, v)) end
    end
    local vo = r.GetExtState(EXT_SECTION, "view_oversample")
    if vo ~= nil and vo ~= "" then
        local ov = tonumber(vo)
        if ov == 1 or ov == 2 or ov == 4 or ov == 8 or ov == 16 then view_oversample = ov end
    end
    local vdm = r.GetExtState(EXT_SECTION, "view_detail_mode")
    if vdm ~= nil and vdm ~= "" then
        if vdm == "auto" then view_detail_mode = "auto" else view_detail_mode = "fixed" end
    end
    local wse = r.GetExtState(EXT_SECTION, "waveform_soft_edges")
    if wse ~= nil and wse ~= "" then waveform_soft_edges = (wse == "1" or wse == "true") end
    local wop = r.GetExtState(EXT_SECTION, "waveform_outline_paths")
    if wop ~= nil and wop ~= "" then waveform_outline_paths = (wop == "1" or wop == "true") end
    local wct = r.GetExtState(EXT_SECTION, "waveform_centerline_thickness")
    if wct ~= nil and wct ~= "" then
        local v = tonumber(wct); if v then waveform_centerline_thickness = math.max(0.6, math.min(3.0, v)) end
    end
    local wfa = r.GetExtState(EXT_SECTION, "waveform_fill_alpha")
    if wfa ~= nil and wfa ~= "" then
        local v = tonumber(wfa); if v then waveform_fill_alpha = math.max(0.05, math.min(0.40, v)) end
    end
    local sc = r.GetExtState(EXT_SECTION, "sidebar_collapsed")
    if sc ~= nil and sc ~= "" then sidebar_collapsed = (sc == "1" or sc == "true") end
    local ri = r.GetExtState(EXT_SECTION, "ripple_item")
    if ri ~= nil and ri ~= "" then ripple_item = (ri == "1" or ri == "true") end
    local git = r.GetExtState(EXT_SECTION, "glue_include_touching")
    if git ~= nil and git ~= "" then glue_include_touching = (git == "1" or git == "true") end
    local sp = r.GetExtState(EXT_SECTION, "spectral_peaks")
    if sp ~= nil and sp ~= "" then spectral_peaks = (sp == "1" or sp == "true") end
    local sl = r.GetExtState(EXT_SECTION, "spectral_lock_sr")
    if sl ~= nil and sl ~= "" then spectral_lock_sr = (sl == "1" or sl == "true") end
    local mz = tonumber(r.GetExtState(EXT_SECTION, "spectral_max_zcr_hz"))
    if mz and mz > 1000 and mz < 20000 then spectral_max_zcr_hz = mz end
    local dcs = r.GetExtState(EXT_SECTION, "draw_channels_separately")
    if dcs ~= nil and dcs ~= "" then draw_channels_separately = (dcs == "1" or dcs == "true") end
    local sdb = r.GetExtState(EXT_SECTION, "show_db_scale")
    if sdb ~= nil and sdb ~= "" then show_db_scale = (sdb == "1" or sdb == "true") end
    local sft = r.GetExtState(EXT_SECTION, "show_footer")
    if sft ~= nil and sft ~= "" then show_footer = (sft == "1" or sft == "true") else show_footer = true end
    local sfd = r.GetExtState(EXT_SECTION, "show_fades")
    if sfd ~= nil and sfd ~= "" then show_fades = (sfd == "1" or sfd == "true") else show_fades = true end
    local seov = r.GetExtState(EXT_SECTION, "show_env_overlay")
    if seov ~= nil and seov ~= "" then show_env_overlay = (seov == "1" or seov == "true") end
    local sdcov = r.GetExtState(EXT_SECTION, "show_dc_overlay")
    if sdcov ~= nil and sdcov ~= "" then show_dc_overlay = (sdcov == "1" or sdcov == "true") end
    local span = r.GetExtState(EXT_SECTION, "show_pan_overlay")
    if span ~= nil and span ~= "" then show_pan_overlay = (span == "1" or span == "true") end
    local svp = r.GetExtState(EXT_SECTION, "show_vol_points")
    if svp ~= nil and svp ~= "" then show_vol_points = (svp == "1" or svp == "true") end
    local strov = r.GetExtState(EXT_SECTION, "show_transport_overlay")
    if strov ~= nil and strov ~= "" then show_transport_overlay = (strov == "1" or strov == "true") else show_transport_overlay = true end
    local pco = r.GetExtState(EXT_SECTION, "pan_color_overlay")
    if pco ~= nil and pco ~= "" then pan_color_overlay = (pco == "1" or pco == "true") else pan_color_overlay = true end
    local pvw = r.GetExtState(EXT_SECTION, "pan_visual_waveform")
    if pvw ~= nil and pvw ~= "" then pan_visual_waveform = (pvw == "1" or pvw == "true") else pan_visual_waveform = true end
    local gan = r.GetExtState(EXT_SECTION, "glue_after_normalize_sel")
    if gan ~= nil and gan ~= "" then glue_after_normalize_sel = (gan == "1" or gan == "true") end
    local psn = r.GetExtState(EXT_SECTION, "prefer_sws_normalize")
    if psn ~= nil and psn ~= "" then prefer_sws_normalize = (psn == "1" or psn == "true") end
    local snc = r.GetExtState(EXT_SECTION, "sws_norm_named_cmd")
    if snc ~= nil then sws_norm_named_cmd = snc end
    if not sws_norm_named_cmd or sws_norm_named_cmd == "" then
        sws_norm_named_cmd = "_BR_NORMALIZE_LOUDNESS_ITEMS" 
    end
    local ptg = r.GetExtState(EXT_SECTION, "pencil_target")
    if ptg ~= nil and ptg ~= "" then
        if ptg == "gum" then ptg = "eraser" end
    if ptg == "dc_offset" or ptg == "eraser" or ptg == "item_vol" or ptg == "item_pan" then pencil_target = ptg end
    end
    local dll = r.GetExtState(EXT_SECTION, "dc_link_lr")
    if dll ~= nil and dll ~= "" then dc_link_lr = (dll == "1" or dll == "true") end
    local tio = r.GetExtState(EXT_SECTION, "transport_item_only")
    if tio ~= nil and tio ~= "" then transport_item_only = (tio == "1" or tio == "true") end
    local dmps = r.GetExtState(EXT_SECTION, "draw_min_px_step")
    if dmps ~= nil and dmps ~= "" then
    local v = tonumber(dmps); if v then draw_min_px_step = math.max(0.1, math.min(20.0, v)) end
    end
    local gsf = r.GetExtState(EXT_SECTION, "game_starfield")
    if gsf ~= nil and gsf ~= "" then game_starfield = (gsf == "1" or gsf == "true") else game_starfield = false end
end

local function CurrentOversample()
    local overs
    if view_detail_mode == "auto" and current_item_len > 0 and view_len > 0 then
        local z = current_item_len / view_len
        if z <= 2 then overs = 2
        elseif z <= 8 then overs = 4
        elseif z <= 32 then overs = 8
        else overs = 16 end
    else
        overs = view_oversample or 4
    end
    if is_interacting then overs = math.min(overs, 4) end
    return overs
end

local function FillColumnsForView(col_a, col_b, pixels, mins, maxs, touched, zcr_counts, samps_counts, last_sign_map, energy_sum, frames_counts, time_sum)
    if not current_accessor or not current_item or view_len <= 0 then return end
    col_a = math.max(1, math.min(pixels, col_a or 1))
    col_b = math.max(1, math.min(pixels, col_b or pixels))
    if col_b < col_a then return end

    local numch = math.max(1, channels)
    local overs = CurrentOversample()
    if draw_channels_separately and channels >= 2 then
        overs = math.max(overs, 8)
    end
    if draw_channels_separately and channels >= 2 then
        overs = math.max(overs, 8)
    end

    local range_cols = (col_b - col_a + 1)
    local range_len = (range_cols / math.max(1, pixels)) * view_len
    if range_len <= 0 then return end

    local target_sr
    if spectral_peaks then
        target_sr = spectral_lock_sr and SpectralSRForWindow(range_len) or math.ceil((range_cols / range_len) * overs)
    else
        target_sr = math.ceil((range_cols / range_len) * overs)
        local zcr_window_hz = 4000
        if target_sr < zcr_window_hz then target_sr = zcr_window_hz end
    end
    local MIN_SR, MAX_SR = 1000, 192000
    if target_sr < MIN_SR then target_sr = MIN_SR end
    if target_sr > MAX_SR then target_sr = MAX_SR end

    local total = math.max(1, math.floor(target_sr * range_len + 0.5))
    local CHUNK = 32768
    local t0 = view_start + ((col_a - 1) / math.max(1, pixels)) * view_len
    local processed = 0
    local function flush_chunk(start_time, n_samps)
    local buf = r.new_array(n_samps * numch)
        local acc_start = (start_time or 0) - (current_item_start or 0)
        local ok = r.GetAudioAccessorSamples(current_accessor, target_sr, numch, acc_start, n_samps, buf)
        if not ok then return false end
        local dt = 1.0 / target_sr
        local t = start_time
        local bi = 1
        for i = 1, n_samps do
            local rel = (t - view_start) / view_len
            local p = math.floor(rel * pixels) + 1
            if p >= col_a and p <= col_b then
                local base = bi - 1
                local sum = 0.0
                if draw_channels_separately and numch >= 2 then
                    local vL = buf[base + 1] or 0.0
                    local vR = buf[base + 2] or 0.0
                    if not mins[1] then mins[1], maxs[1] = {}, {} end
                    if not mins[2] then mins[2], maxs[2] = {}, {} end
                    mins[1][p] = math.min(mins[1][p] or 1e9, vL)
                    maxs[1][p] = math.max(maxs[1][p] or -1e9, vL)
                    mins[2][p] = math.min(mins[2][p] or 1e9, vR)
                    maxs[2][p] = math.max(maxs[2][p] or -1e9, vR)
                    sum = (vL + vR) * 0.5
                else
                    local mn, mx = 1e9, -1e9
                    for ch = 1, numch do
                        local v = buf[base + ch] or 0.0
                        if v < mn then mn = v end
                        if v > mx then mx = v end
                        sum = sum + v
                    end
                    if mn < mins[p] then mins[p] = mn end
                    if mx > maxs[p] then maxs[p] = mx end
                end
                if touched then touched[p] = true end
                if zcr_counts and last_sign_map then
                    local m = sum / numch
                    local eps = 1e-5
                    local sgn = (m > eps) and 1 or ((m < -eps) and -1 or 0)
                    if sgn ~= 0 then
                        local last = last_sign_map[p]
                        if last and last ~= 0 and last ~= sgn then
                            zcr_counts[p] = (zcr_counts[p] or 0) + 1
                        end
                        last_sign_map[p] = sgn
                    end
                    if energy_sum then
                        local m2 = m * m
                        energy_sum[p] = (energy_sum[p] or 0) + m2
                    end
                    if frames_counts then frames_counts[p] = (frames_counts[p] or 0) + 1 end
                    if time_sum then time_sum[p] = (time_sum[p] or 0) + (1.0 / target_sr) end
                end
            end
            bi = bi + numch
            t = t + dt
        end
        return true
    end
    while processed < total do
        local remain = total - processed
        local n = (remain > CHUNK) and CHUNK or remain
        local start_time = t0 + (processed / target_sr)
        if not flush_chunk(start_time, n) then break end
        processed = processed + n
    end
end

local function EnsureViewPeaks(pixels)
    if not current_item or current_item_len <= 0 or not current_accessor or pixels <= 0 or view_len <= 0 then
        view_cache_valid = false
        return false
    end
    local overs = CurrentOversample()
    if view_cache_valid and view_cache_w == pixels and view_cache_overs == overs and math.abs(view_cache_start - view_start) < 1e-9 and math.abs(view_cache_len - view_len) < 1e-9 then
        return true
    end

    local numch = math.max(1, channels)
    local mins, maxs, touched
    if draw_channels_separately and channels >= 2 then
        mins, maxs, touched = { {}, {} }, { {}, {} }, {}
        for i = 1, pixels do
            mins[1][i] = 1e9; maxs[1][i] = -1e9
            mins[2][i] = 1e9; maxs[2][i] = -1e9
        end
    else
        mins, maxs, touched = {}, {}, {}
        for i = 1, pixels do mins[i] = 1e9; maxs[i] = -1e9 end
    end

    local overs = CurrentOversample()

    if view_cache_valid and view_cache_w == pixels and math.abs(view_cache_len - view_len) < 1e-12 and view_cache_overs == overs then
        local delta_t = view_start - view_cache_start
        local shift_px = math.floor((delta_t / view_len) * pixels + (delta_t >= 0 and 0.5 or -0.5))
        if shift_px ~= 0 and math.abs(shift_px) < pixels then
            if shift_px > 0 then
                if draw_channels_separately and channels >= 2 and view_cache_min_ch and view_cache_max_ch then
                    for p = 1, pixels - shift_px do
                        mins[1][p] = (view_cache_min_ch[1] and view_cache_min_ch[1][p + shift_px]) or 1e9
                        maxs[1][p] = (view_cache_max_ch[1] and view_cache_max_ch[1][p + shift_px]) or -1e9
                        mins[2][p] = (view_cache_min_ch[2] and view_cache_min_ch[2][p + shift_px]) or 1e9
                        maxs[2][p] = (view_cache_max_ch[2] and view_cache_max_ch[2][p + shift_px]) or -1e9
                    end
                else
                    for p = 1, pixels - shift_px do
                        mins[p] = view_cache_min[p + shift_px] or 1e9
                        maxs[p] = view_cache_max[p + shift_px] or -1e9
                    end
                end
                for p = pixels - shift_px + 1, pixels do
                    if draw_channels_separately and channels >= 2 then
                        mins[1][p], maxs[1][p] = 1e9, -1e9
                        mins[2][p], maxs[2][p] = 1e9, -1e9
                    else
                        mins[p], maxs[p] = 1e9, -1e9
                    end
                end
                local fill_a = pixels - shift_px + 1
                local fill_b = pixels
                if fill_a <= fill_b then
                    local zcr_counts = spectral_peaks and {} or nil
                    local last_sign_map = spectral_peaks and {} or nil
                    local energy_sum = spectral_peaks and {} or nil
                    local frames_counts = spectral_peaks and {} or nil
                    local time_sum = spectral_peaks and {} or nil
                    FillColumnsForView(fill_a, fill_b, pixels, mins, maxs, touched, zcr_counts, nil, last_sign_map, energy_sum, frames_counts, time_sum)
                    if spectral_peaks then
                        local z = {}
                        local rms = {}
                        if view_cache_z then
                            for i = 1, pixels - shift_px do z[i] = view_cache_z[i + shift_px] end
                        end
                        if view_cache_rms then
                            for i = 1, pixels - shift_px do rms[i] = view_cache_rms[i + shift_px] end
                        end
                        for i = pixels - shift_px + 1, pixels do z[i] = nil end
                        for i = pixels - shift_px + 1, pixels do rms[i] = nil end
                        for p = fill_a, fill_b do
                            local tm = (time_sum and time_sum[p]) or 0
                            if tm > 0 then
                                local zcr_hz = (zcr_counts[p] or 0) / tm
                                local v = math.min(1.0, zcr_hz / spectral_max_zcr_hz)
                                z[p] = math.sqrt(math.max(0.0, v))
                            end
                            if energy_sum and frames_counts and (frames_counts[p] or 0) > 0 then
                                rms[p] = math.sqrt((energy_sum[p] or 0) / math.max(1, frames_counts[p]))
                            end
                        end

                        local prev
                        for p = fill_a, fill_b do
                            if touched[p] then prev = p else
                                local q = p + 1
                                while q <= fill_b and not touched[q] do q = q + 1 end
                                if prev and q <= fill_b and touched[q] then
                                    local t = (p - prev) / (q - prev)
                                    local zv = (z[prev] or 0)
                                    local zv2 = (z[q] or zv)
                                    z[p] = zv + t * ((zv2 or zv) - zv)
                                    local rv = rms[prev]
                                    local rv2 = rms[q]
                                    if rv and rv2 then rms[p] = rv + t * (rv2 - rv) elseif rv then rms[p] = rv end
                                elseif prev then z[p] = z[prev] end
                            end
                        end
                        view_cache_z = z
                        view_cache_rms = rms
                        local cov = 0
                        for i = 1, pixels do if z[i] ~= nil then cov = cov + 1 end end
                        view_cache_cov = pixels > 0 and (cov / pixels) or 0
                    end
                    local function interp_range(a, b)
                        local prev
                        for p = a, b do
                            if touched[p] then prev = p else
                                local q = p + 1
                                while q <= b and not touched[q] do q = q + 1 end
                                if prev and q <= b and touched[q] then
                                    local t = (p - prev) / (q - prev)
                                    if draw_channels_separately and channels >= 2 then
                                        for ch = 1, 2 do
                                            mins[ch][p] = mins[ch][prev] + t * (mins[ch][q] - mins[ch][prev])
                                            maxs[ch][p] = maxs[ch][prev] + t * (maxs[ch][q] - maxs[ch][prev])
                                        end
                                    else
                                        mins[p] = mins[prev] + t * (mins[q] - mins[prev])
                                        maxs[p] = maxs[prev] + t * (maxs[q] - maxs[prev])
                                    end
                                elseif prev then
                                    if draw_channels_separately and channels >= 2 then
                                        for ch = 1, 2 do mins[ch][p], maxs[ch][p] = mins[ch][prev], maxs[ch][prev] end
                                    else
                                        mins[p], maxs[p] = mins[prev], maxs[prev]
                                    end
                                end
                            end
                        end
                    end
                    interp_range(fill_a, fill_b)
                end
            else
                local k = -shift_px
                if draw_channels_separately and channels >= 2 and view_cache_min_ch and view_cache_max_ch then
                    for p = k + 1, pixels do
                        mins[1][p] = (view_cache_min_ch[1] and view_cache_min_ch[1][p - k]) or 1e9
                        maxs[1][p] = (view_cache_max_ch[1] and view_cache_max_ch[1][p - k]) or -1e9
                        mins[2][p] = (view_cache_min_ch[2] and view_cache_min_ch[2][p - k]) or 1e9
                        maxs[2][p] = (view_cache_max_ch[2] and view_cache_max_ch[2][p - k]) or -1e9
                    end
                else
                    for p = k + 1, pixels do
                        mins[p] = view_cache_min[p - k] or 1e9
                        maxs[p] = view_cache_max[p - k] or -1e9
                    end
                end
                for p = 1, k do
                    if draw_channels_separately and channels >= 2 then
                        mins[1][p], maxs[1][p] = 1e9, -1e9
                        mins[2][p], maxs[2][p] = 1e9, -1e9
                    else
                        mins[p], maxs[p] = 1e9, -1e9
                    end
                end
                local fill_a = 1
                local fill_b = k
                if fill_a <= fill_b then
                    local zcr_counts = spectral_peaks and {} or nil
                    local last_sign_map = spectral_peaks and {} or nil
                    local energy_sum = spectral_peaks and {} or nil
                    local frames_counts = spectral_peaks and {} or nil
                    local time_sum = spectral_peaks and {} or nil
                    FillColumnsForView(fill_a, fill_b, pixels, mins, maxs, touched, zcr_counts, nil, last_sign_map, energy_sum, frames_counts, time_sum)
                    if spectral_peaks then
                        local z = {}
                        local rms = {}
                        if view_cache_z then
                            for i = k + 1, pixels do z[i] = view_cache_z[i - k] end
                        end
                        if view_cache_rms then
                            for i = k + 1, pixels do rms[i] = view_cache_rms[i - k] end
                        end
                        for i = 1, k do z[i] = nil end
                        for i = 1, k do rms[i] = nil end
                        for p = fill_a, fill_b do
                            local tm = (time_sum and time_sum[p]) or 0
                            if tm > 0 then
                                local zcr_hz = (zcr_counts[p] or 0) / tm
                                local v = math.min(1.0, zcr_hz / spectral_max_zcr_hz)
                                z[p] = math.sqrt(math.max(0.0, v))
                            end
                            if energy_sum and frames_counts and (frames_counts[p] or 0) > 0 then
                                rms[p] = math.sqrt((energy_sum[p] or 0) / math.max(1, frames_counts[p]))
                            end
                        end
                        local prev
                        for p = fill_a, fill_b do
                            if touched[p] then prev = p else
                                local q = p + 1
                                while q <= fill_b and not touched[q] do q = q + 1 end
                                if prev and q <= fill_b and touched[q] then
                                    local t = (p - prev) / (q - prev)
                                    local zv = (z[prev] or 0)
                                    local zv2 = (z[q] or zv)
                                    z[p] = zv + t * ((zv2 or zv) - zv)
                                    local rv = rms[prev]
                                    local rv2 = rms[q]
                                    if rv and rv2 then rms[p] = rv + t * (rv2 - rv) elseif rv then rms[p] = rv end
                                elseif prev then z[p] = z[prev] end
                            end
                        end
                        view_cache_z = z
                        view_cache_rms = rms
                        local cov = 0
                        for i = 1, pixels do if z[i] ~= nil then cov = cov + 1 end end
                        view_cache_cov = pixels > 0 and (cov / pixels) or 0
                    end
                    local function interp_range(a, b)
                        local prev
                        for p = a, b do
                            if touched[p] then prev = p else
                                local q = p + 1
                                while q <= b and not touched[q] do q = q + 1 end
                                if prev and q <= b and touched[q] then
                                    local t = (p - prev) / (q - prev)
                                    if draw_channels_separately and channels >= 2 then
                                        for ch = 1, 2 do
                                            mins[ch][p] = mins[ch][prev] + t * (mins[ch][q] - mins[ch][prev])
                                            maxs[ch][p] = maxs[ch][prev] + t * (maxs[ch][q] - maxs[ch][prev])
                                        end
                                    else
                                        mins[p] = mins[prev] + t * (mins[q] - mins[prev])
                                        maxs[p] = maxs[prev] + t * (maxs[q] - maxs[prev])
                                    end
                                elseif prev then
                                    if draw_channels_separately and channels >= 2 then
                                        for ch = 1, 2 do mins[ch][p], maxs[ch][p] = mins[ch][prev], maxs[ch][prev] end
                                    else
                                        mins[p], maxs[p] = mins[prev], maxs[prev]
                                    end
                                end
                            end
                        end
                    end
                    interp_range(fill_a, fill_b)
                end
            end
            view_cache_min = mins
            view_cache_max = maxs
            view_cache_w = pixels
            view_cache_start = view_start
            view_cache_len = view_len
            view_cache_overs = overs
            view_cache_valid = true
            return true
        end
    end

    local target_sr = math.ceil((pixels / view_len) * overs)
    if spectral_peaks then
        target_sr = spectral_lock_sr and SpectralSRForWindow(view_len) or math.ceil((pixels / view_len) * overs)
    end
    local MIN_SR = 1000
    local MAX_SR = 192000
    local MAX_TOTAL = is_interacting and (350000) or (650000)
    if target_sr < MIN_SR then target_sr = MIN_SR end
    if target_sr > MAX_SR then target_sr = MAX_SR end
    local estimated_total = target_sr * view_len
    if estimated_total > MAX_TOTAL then
        local desired = math.max(0.5, (pixels / view_len)) * overs
        local cap_sr = math.floor(math.max(MIN_SR, math.min(MAX_SR, MAX_TOTAL / view_len)))
        target_sr = math.max(math.min(cap_sr, target_sr), math.floor(desired))
    end

    local sr = math.max(1, math.min(MAX_SR, target_sr))
    local total = math.max(1, math.floor(sr * view_len + 0.5))
    dbg_spectral_sr = spectral_peaks and sr or nil
    dbg_spectral_total = spectral_peaks and total or nil
    dbg_spectral_capped = (estimated_total or 0) > (MAX_TOTAL or 0)
    local CHUNK = 32768
    local processed = 0
    local t0 = view_start
    local inv_view_len = 1.0 / view_len

    local zcr_counts = spectral_peaks and {} or nil
    local last_sign_map = spectral_peaks and {} or nil
    local energy_sum = spectral_peaks and {} or nil
    local frames_counts = spectral_peaks and {} or nil
    local time_sum = spectral_peaks and {} or nil
    local function flush_chunk(start_time, n_samps)
        local buf = r.new_array(n_samps * numch)
        local acc_start = (start_time or 0) - (current_item_start or 0)
        local ok = r.GetAudioAccessorSamples(current_accessor, sr, numch, acc_start, n_samps, buf)
        if not ok then return false end
        local t = start_time
        local dt = 1.0 / sr
        local bi = 1
        for i = 1, n_samps do
            local rel = (t - t0) * inv_view_len
            local p = math.floor(rel * pixels) + 1
            if p >= 1 and p <= pixels then
                local base = bi - 1
                local sum = 0.0
                if draw_channels_separately and numch >= 2 then
                    local vL = buf[base + 1] or 0.0
                    local vR = buf[base + 2] or 0.0
                    mins[1][p] = math.min(mins[1][p] or 1e9, vL)
                    maxs[1][p] = math.max(maxs[1][p] or -1e9, vL)
                    mins[2][p] = math.min(mins[2][p] or 1e9, vR)
                    maxs[2][p] = math.max(maxs[2][p] or -1e9, vR)
                    sum = (vL + vR) * 0.5
                else
                    local mn, mx = 1e9, -1e9
                    for ch = 1, numch do
                        local v = buf[base + ch] or 0.0
                        if v < mn then mn = v end
                        if v > mx then mx = v end
                        sum = sum + v
                    end
                    if mn < mins[p] then mins[p] = mn end
                    if mx > maxs[p] then maxs[p] = mx end
                end
                touched[p] = true
                if spectral_peaks then
                    local m = sum / numch
                    local eps = 1e-5
                    local sgn = (m > eps) and 1 or ((m < -eps) and -1 or 0)
                    if sgn ~= 0 then
                        local last = last_sign_map[p]
                        if last and last ~= 0 and last ~= sgn then
                            zcr_counts[p] = (zcr_counts[p] or 0) + 1
                        end
                        last_sign_map[p] = sgn
                    end
                    if energy_sum then energy_sum[p] = (energy_sum[p] or 0) + m * m end
                    if frames_counts then frames_counts[p] = (frames_counts[p] or 0) + 1 end
                    if time_sum then time_sum[p] = (time_sum[p] or 0) + (1.0 / sr) end
                end
            end
            t = t + dt
            bi = bi + numch
        end
        return true
    end

    while processed < total do
        local remain = total - processed
        local n = (remain > CHUNK) and CHUNK or remain
        local start_time = t0 + (processed / sr)
        if not flush_chunk(start_time, n) then
            break
        end
        processed = processed + n
    end

    local function fill_gaps()
        local prev_idx = nil
        for p = 1, pixels do
            if touched[p] then
                prev_idx = p
            else
                local q = p + 1
                while q <= pixels and not touched[q] do q = q + 1 end
                if prev_idx and q <= pixels and touched[q] then
                    local t = (p - prev_idx) / (q - prev_idx)
                    if draw_channels_separately and channels >= 2 then
                        for ch = 1, 2 do
                            mins[ch][p] = mins[ch][prev_idx] + t * (mins[ch][q] - mins[ch][prev_idx])
                            maxs[ch][p] = maxs[ch][prev_idx] + t * (maxs[ch][q] - maxs[ch][prev_idx])
                        end
                    else
                        mins[p] = mins[prev_idx] + t * (mins[q] - mins[prev_idx])
                        maxs[p] = maxs[prev_idx] + t * (maxs[q] - maxs[prev_idx])
                    end
                elseif prev_idx then
                    if draw_channels_separately and channels >= 2 then
                        for ch = 1, 2 do mins[ch][p], maxs[ch][p] = mins[ch][prev_idx], maxs[ch][prev_idx] end
                    else
                        mins[p], maxs[p] = mins[prev_idx], maxs[prev_idx]
                    end
                elseif q <= pixels and touched[q] then
                    if draw_channels_separately and channels >= 2 then
                        for ch = 1, 2 do mins[ch][p], maxs[ch][p] = mins[ch][q], maxs[ch][q] end
                    else
                        mins[p], maxs[p] = mins[q], maxs[q]
                    end
                else
                    if draw_channels_separately and channels >= 2 then
                        for ch = 1, 2 do mins[ch][p], maxs[ch][p] = 0.0, 0.0 end
                    else
                        mins[p], maxs[p] = 0.0, 0.0
                    end
                end
            end
        end
    end
    fill_gaps()

    local sec_per_px = view_len / math.max(1, pixels)
    if sec_per_px > 0.01 then 
        local function smooth_series(src_min, src_max)
            local smn, smx = {}, {}
            smn[1], smx[1] = src_min[1], src_max[1]
            for p = 2, pixels - 1 do
                smn[p] = 0.25 * src_min[p - 1] + 0.5 * src_min[p] + 0.25 * src_min[p + 1]
                smx[p] = 0.25 * src_max[p - 1] + 0.5 * src_max[p] + 0.25 * src_max[p + 1]
                if smn[p] > smx[p] then smn[p], smx[p] = smx[p], smn[p] end
            end
            smn[pixels], smx[pixels] = src_min[pixels], src_max[pixels]
            return smn, smx
        end
        if draw_channels_separately and channels >= 2 then
            local smn1, smx1 = smooth_series(mins[1], maxs[1])
            local smn2, smx2 = smooth_series(mins[2], maxs[2])
            mins = { smn1, smn2 }
            maxs = { smx1, smx2 }
        else
            local smn, smx = smooth_series(mins, maxs)
            mins, maxs = smn, smx
        end
    end

    if draw_channels_separately and channels >= 2 then
        view_cache_min_ch = mins
        view_cache_max_ch = maxs
        local mins_mix, maxs_mix = {}, {}
        for p = 1, pixels do
            local mn = math.min(mins[1][p] or 0, mins[2][p] or 0)
            local mx = math.max(maxs[1][p] or 0, maxs[2][p] or 0)
            mins_mix[p], maxs_mix[p] = mn, mx
        end
        view_cache_min = mins_mix
        view_cache_max = maxs_mix
    else
        view_cache_min = mins
        view_cache_max = maxs
        view_cache_min_ch = nil
        view_cache_max_ch = nil
    end
    view_cache_w = pixels
    view_cache_start = view_start
    view_cache_len = view_len
    view_cache_overs = overs
    view_cache_valid = true
    if spectral_peaks then
        local z = {}
        local rms = {}
        for p = 1, pixels do
            local tm = (time_sum and time_sum[p]) or 0
            if tm > 0 then
                local zcr_hz = (zcr_counts[p] or 0) / tm
                local v = math.min(1.0, zcr_hz / spectral_max_zcr_hz)
                z[p] = math.sqrt(math.max(0.0, v))
            end
            if energy_sum and frames_counts and (frames_counts[p] or 0) > 0 then
                rms[p] = math.sqrt((energy_sum[p] or 0) / math.max(1, frames_counts[p]))
            else
                rms[p] = nil
            end
        end
        local prev = nil
        for p = 1, pixels do
            if touched[p] then prev = p else
                local q = p + 1
                while q <= pixels and not touched[q] do q = q + 1 end
                if prev and q <= pixels and touched[q] then
                    local t = (p - prev) / (q - prev)
                    local zv = z[prev] or 0
                    local zv2 = z[q] or zv
                    z[p] = zv + t * (z[q] - zv)
                    local rv = rms[prev]
                    local rv2 = rms[q]
                    if rv and rv2 then rms[p] = rv + t * (rv2 - rv) elseif rv then rms[p] = rv end
                elseif prev then z[p] = z[prev] end
            end
        end
    view_cache_z = z
    view_cache_rms = rms
    local cov = 0
    for i = 1, pixels do if z[i] ~= nil then cov = cov + 1 end end
    view_cache_cov = pixels > 0 and (cov / pixels) or 0
    else
        view_cache_z = nil
    view_cache_rms = nil
    view_cache_cov = 0.0
    end
    return true
end

LoadSettings()

local function FormatTimeLabel(t, step)
    if step < 1.0 then
        local min = math.floor(t / 60)
        local sec = t - min * 60
        return string.format("%d:%05.2f", min, sec)
    else
        local min = math.floor(t / 60)
        local sec = math.floor(t - min * 60 + 0.5)
        return string.format("%d:%02d", min, sec)
    end
end

local function NiceStep(seconds)
    local steps = {0.1, 0.2, 0.5, 1, 2, 5, 10, 15, 30, 60, 120, 300, 600}
    for _, s in ipairs(steps) do
        if s >= seconds then return s end
    end
    return 600
end

local function DrawRuler(draw_list, x, y, w, h)
    if not current_item or current_item_len <= 0 or w <= 0 or h <= 0 then return end
    r.ImGui_DrawList_AddRectFilled(draw_list, x, y, x + w, y + h, COLOR_RULER_BG)

    local tick_col = ColorWithAlpha(COLOR_RULER_TICK, grid_alpha)
    local text_col = ColorWithAlpha(COLOR_RULER_TEXT, 1.0)

    if ruler_beats then
    local view_t0 = math.max(current_item_start, view_start)
    local view_t1 = math.min(current_item_start + current_item_len, view_start + view_len)
    if view_t1 <= view_t0 then return end
    local qn_start = r.TimeMap2_timeToQN(0, view_t0)
    local qn_end = r.TimeMap2_timeToQN(0, view_t1)

        local t_start = current_item_start
        local _, denom = r.TimeMap_GetTimeSigAtTime(0, t_start)
        denom = denom or 4
        local beat_qn = 4 / denom
        local _, meas_qn_start = r.TimeMap_QNToMeasures(0, qn_start)
        local first_qn = meas_qn_start + math.ceil((qn_start - meas_qn_start) / beat_qn - 1e-9) * beat_qn

        local qn = first_qn
        local count, max_lines = 0, 8192
        local prev_label_x = -1e9
        local label_min_px = 36
        while qn <= qn_end + 1e-9 do
            count = count + 1
            if count > max_lines then break end
            local t = r.TimeMap2_QNToTime(0, qn)
            if t >= view_t0 then
                local rel = (t - view_t0) / (view_t1 - view_t0)
                local gx = x + rel * w
                local num, dnm = r.TimeMap_GetTimeSigAtTime(0, t)
                num = num or 4; dnm = dnm or 4
                local cur_beat_qn = 4 / dnm
                local meas_idx, meas_qn_s, _ = r.TimeMap_QNToMeasures(0, qn)
                local major = math.abs(qn - meas_qn_s) < 1e-6
                local th = major and h or (h * 0.6)
                r.ImGui_DrawList_AddLine(draw_list, gx, y + h - th, gx, y + h, tick_col, 1.0)
                local bar_disp = meas_idx or 1
                if major then
                    local label = string.format("%d.1", bar_disp)
                    r.ImGui_DrawList_AddText(draw_list, gx + 2, y + 2, text_col, label)
                    prev_label_x = gx
                else
                    if gx - prev_label_x >= label_min_px then
                        local beat_idx = math.floor(((qn - meas_qn_s) / cur_beat_qn) + 0.5) + 1
                        if beat_idx < 1 then beat_idx = 1 end
                        if beat_idx > num then beat_idx = num end
                        local label = string.format("%d.%d", bar_disp, beat_idx)
                        r.ImGui_DrawList_AddText(draw_list, gx + 2, y + 2, text_col, label)
                        prev_label_x = gx
                    end
                end
                beat_qn = cur_beat_qn
            end
            qn = qn + beat_qn
        end
    else
        local view_t0 = math.max(current_item_start, view_start)
        local view_t1 = math.min(current_item_start + current_item_len, view_start + view_len)
        if view_t1 <= view_t0 then return end
        local qn_start = r.TimeMap2_timeToQN(0, view_t0)
        local qn_end = r.TimeMap2_timeToQN(0, view_t1)
        local meas_idx, meas_qn_s, meas_qn_e = r.TimeMap_QNToMeasures(0, qn_start)
        local count, max_lines = 0, 16384 
        while meas_qn_s and meas_qn_s <= qn_end + 1e-9 do
            count = count + 1
            if count > max_lines then break end
            local t_bar = r.TimeMap2_QNToTime(0, meas_qn_s)
            if t_bar >= view_t0 then
                local rel = (t_bar - view_t0) / (view_t1 - view_t0)
                local gx = x + rel * w
                r.ImGui_DrawList_AddLine(draw_list, gx, y, gx, y + h, tick_col, 1.0)
                local time_label = r.format_timestr_pos(t_bar, "", 0)
                r.ImGui_DrawList_AddText(draw_list, gx + 2, y + 2, text_col, time_label)
            end
            local num, denom = r.TimeMap_GetTimeSigAtTime(0, t_bar)
            num = num or 4; denom = denom or 4
            local beat_qn = 4 / denom
            for i = 1, (num - 1) do
                local qn_tick = meas_qn_s + i * beat_qn
                if qn_tick >= meas_qn_e - 1e-9 then break end
                if qn_tick > qn_end + 1e-9 then break end
                local t_tick = r.TimeMap2_QNToTime(0, qn_tick)
                if t_tick >= view_t0 then
                    local relb = (t_tick - view_t0) / (view_t1 - view_t0)
                    local gxb = x + relb * w
                    local th = h * 0.6
                    r.ImGui_DrawList_AddLine(draw_list, gxb, y + h - th, gxb, y + h, tick_col, 1.0)
                end
            end
            meas_idx, meas_qn_s, meas_qn_e = r.TimeMap_QNToMeasures(0, meas_qn_e + 1e-9)
        end
    end
end

local function HasNonEmptyTimeSelection()
    local s, e = r.GetSet_LoopTimeRange(false, false, 0, 0, false)
    return (e or 0) > (s or 0)
end

local function SnapTimeToProjectGrid(tt)
    if not tt then return tt end
    local qn = r.TimeMap2_timeToQN(0, tt)
    local num, denom = r.TimeMap_GetTimeSigAtTime(0, tt)
    num = num or 4; denom = denom or 4
    local bar_qn = num * (4.0 / denom)
    local _, gdiv = r.GetSetProjectGrid(0, false, 0, 0, 0)
    if not gdiv or gdiv <= 0 then gdiv = 0.25 end
    local step_qn = bar_qn * gdiv
    if step_qn <= 0 then return tt end
    local sqn = math.floor(qn / step_qn + 0.5) * step_qn
    return r.TimeMap2_QNToTime(0, sqn)
end

local function ApplyItemTimeSelection(force)
    if not transport_item_only then return end
    if not current_item or (current_item_len or 0) <= 0 then return end
    if (not force) and ts_user_override then return end
    r.GetSet_LoopTimeRange(true, false, current_item_start or 0.0, (current_item_start or 0.0) + (current_item_len or 0.0), false)
end

local function LoadPeaks(item_override, keep_view)
    local item = item_override
    local prev_item_ref = current_item
    local prev_item_start = current_item_start
    local prev_item_len = current_item_len
    local prev_view_start = view_start
    local prev_view_len = view_len
    if not item then
        local sel_count = r.CountSelectedMediaItems(0) or 0
        if sel_count > 0 then
            item = r.GetSelectedMediaItem(0, sel_count - 1)
        end
    end
    
    if not item then 
        current_item = nil
        is_loaded = false
        peaks = {}
    if current_accessor then r.DestroyAudioAccessor(current_accessor); current_accessor = nil end
    peak_pyr = nil
    peak_pyr_ch = nil
    view_cache_valid = false
    rmb_drawing = false
    draw_points = nil
    draw_last_t = nil
    draw_visible_until = 0
        return 
    end
    
    if item == current_item and is_loaded then
        local pos_now = r.GetMediaItemInfo_Value(item, "D_POSITION") or 0.0
        local len_now = r.GetMediaItemInfo_Value(item, "D_LENGTH") or 0.0
        local unchanged = (math.abs((pos_now or 0) - (current_item_start or 0)) < 1e-9)
                       and (math.abs((len_now or 0) - (current_item_len or 0)) < 1e-9)
        local _, guid_now = r.GetSetMediaItemInfo_String(item, "GUID", "", false)
        local guid_same = peak_pyr and peak_pyr.item_guid and (peak_pyr.item_guid == guid_now)
        if unchanged and guid_same and peak_pyr and peak_pyr.built then
            return
        end
    end
    
    current_item = item
    sel_a, sel_b = nil, nil
    dragging_select = false
    drag_start_t, drag_cur_t = nil, nil
    local take = r.GetActiveTake(item)
    
    if not take then 
        is_loaded = false
        peaks = {}
    if current_accessor then r.DestroyAudioAccessor(current_accessor); current_accessor = nil end
    peak_pyr = nil
    peak_pyr_ch = nil
    view_cache_valid = false
    rmb_drawing = false; draw_points = nil; draw_last_t = nil; draw_visible_until = 0
        return 
    end
    
    if r.TakeIsMIDI(take) then
        is_loaded = false
        peaks = {}
    if current_accessor then r.DestroyAudioAccessor(current_accessor); current_accessor = nil end
    peak_pyr = nil
    peak_pyr_ch = nil
    view_cache_valid = false
    rmb_drawing = false; draw_points = nil; draw_last_t = nil; draw_visible_until = 0
        return
    end
    
    current_take = take
    current_src = r.GetMediaItemTake_Source(take)
    
    if not current_src then 
        is_loaded = false
        peaks = {}
        return 
    end
    
    filename = r.GetMediaSourceFileName(current_src) or "Unknown"
    filename = filename:match("([^\\]+)$") or filename 
    sample_rate = r.GetMediaSourceSampleRate(current_src) or 44100
    channels = r.GetMediaSourceNumChannels(current_src) or 1
    
    current_item_start = r.GetMediaItemInfo_Value(current_item, "D_POSITION")
    current_item_len = r.GetMediaItemInfo_Value(current_item, "D_LENGTH")
    
    ApplyItemTimeSelection(false)
    view_start = current_item_start
    view_len = current_item_len
    if keep_view and prev_item_ref and item == prev_item_ref then
        local rel_start = (prev_view_start or current_item_start) - (prev_item_start or current_item_start)
        local use_len = math.max(0.0, math.min(prev_view_len or current_item_len or 0.0, current_item_len or 0.0))
        local max_rel_start = math.max(0.0, (current_item_len or 0.0) - use_len)
        rel_start = math.max(0.0, math.min(rel_start or 0.0, max_rel_start))
        view_start = (current_item_start or 0.0) + rel_start
        view_len = use_len
    end
    amp_zoom = math.max(0.1, math.min(10.0, amp_zoom or 1.0))
    local desired_points = 2048
    if current_item_len <= 0 then is_loaded = false; peaks = {}; return end

    peaks = {}
    local playstate = r.GetPlayState() or 0
    local is_playing = (playstate & 1) == 1
    local orig_item_mute = r.GetMediaItemInfo_Value(current_item, "B_MUTE") or 0
    local orig_take_mute = r.GetMediaItemTakeInfo_Value(current_take, "B_MUTE") or 0
    local did_temp_unmute = false
    if not is_playing and ((orig_item_mute or 0) > 0.5 or (orig_take_mute or 0) > 0.5) then
        r.PreventUIRefresh(1)
        if (orig_item_mute or 0) > 0.5 then r.SetMediaItemInfo_Value(current_item, "B_MUTE", 0) end
        if (orig_take_mute or 0) > 0.5 then r.SetMediaItemTakeInfo_Value(current_take, "B_MUTE", 0) end
        did_temp_unmute = true
        r.PreventUIRefresh(-1)
    end

    if current_accessor then r.DestroyAudioAccessor(current_accessor); current_accessor = nil end
    local accessor = r.CreateTakeAudioAccessor(current_take)
    if not accessor then is_loaded = false; return end

    local numch = math.max(1, channels)
    local buf = r.new_array(desired_points * numch)
    local out_sr = desired_points / current_item_len
    local out_sr_int = math.max(1, math.min(384000, math.floor(out_sr + 0.5)))
    local ok = r.GetAudioAccessorSamples(accessor, out_sr_int, numch, 0.0, desired_points, buf)

    if ok then
        for i = 0, desired_points - 1 do
            local sum = 0.0
            for ch = 0, numch - 1 do
                local idx = (i * numch) + ch + 1
                sum = sum + (buf[idx] or 0.0)
            end
            peaks[#peaks+1] = sum / numch
        end
        is_loaded = true
    else
        is_loaded = false
    end
    current_accessor = accessor
    if did_temp_unmute then
        r.PreventUIRefresh(1)
        if (orig_item_mute or 0) > 0.5 then r.SetMediaItemInfo_Value(current_item, "B_MUTE", 1) end
        if (orig_take_mute or 0) > 0.5 then r.SetMediaItemTakeInfo_Value(current_take, "B_MUTE", 1) end
        r.PreventUIRefresh(-1)
    end
    view_cache_valid = false
    BuildPeakPyramid()
    BuildPeakPyramidCh()
    rmb_drawing = false; draw_points = nil; draw_last_t = nil; draw_visible_until = 0
end

function GetSelectionRangeClamped()
    if not current_item then return nil end
    local a, b = sel_a, sel_b
    if not (a and b) then
        local ts, te = r.GetSet_LoopTimeRange(false, false, 0, 0, false)
        a, b = ts, te
    end
    if not (a and b) or b <= a then return nil end
    local ia = current_item_start
    local ib = current_item_start + current_item_len
    local s = math.max(ia, a)
    local e = math.min(ib, b)
    if e <= s then return nil end
    return s, e
end

local function SplitAtTime(t)
    if not current_item or not t then return end
    r.SplitMediaItem(current_item, t)
end

local function SplitAtSelectionEdges()
    local s, e = GetSelectionRangeClamped()
    if not s then return end
    r.SplitMediaItem(current_item, e)
    r.SplitMediaItem(current_item, s)
end

local function TrimItemToSelection()
    if not current_item then return end
    local s, e = GetSelectionRangeClamped()
    if not s then return end
    local pos = r.GetMediaItemInfo_Value(current_item, "D_POSITION")
    local len = r.GetMediaItemInfo_Value(current_item, "D_LENGTH")
    local take = r.GetActiveTake(current_item)
    local pr = take and r.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE") or 1.0
    local offs = take and r.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS") or 0.0
    local new_pos = s
    local new_len = math.max(0, e - s)
    local delta = new_pos - pos
    local new_offs = offs + delta * (pr or 1.0)
    r.SetMediaItemInfo_Value(current_item, "D_POSITION", new_pos)
    r.SetMediaItemInfo_Value(current_item, "D_LENGTH", new_len)
    if take then r.SetMediaItemTakeInfo_Value(take, "D_STARTOFFS", new_offs) end
    r.UpdateItemInProject(current_item)
    r.SelectAllMediaItems(0, false)
    r.SetMediaItemSelected(current_item, true)
    r.UpdateArrange()
    return current_item
end

local function CutSelectionWithinItem(close_gap)
    if not current_item then return end
    local s, e = GetSelectionRangeClamped()
    if not s then return end
    local track = r.GetMediaItem_Track(current_item)
    local right_item = r.SplitMediaItem(current_item, e)
    local left_item = r.SplitMediaItem(current_item, s)
    if left_item and track then
        r.DeleteTrackMediaItem(track, left_item)
        if close_gap and right_item then
            r.SetMediaItemInfo_Value(right_item, "D_POSITION", s)
            r.UpdateItemInProject(right_item)
        end
        r.SelectAllMediaItems(0, false)
        local target = right_item or current_item
        if target then r.SetMediaItemSelected(target, true) end
        r.UpdateItemInProject(target)
        r.UpdateArrange()
        return target
    end
end

-- FW
local ItemsJoinable
local function CollectTouchingChain(item)
    if not item then return { } end
    local tr = r.GetMediaItem_Track(item)
    if not tr then return { item } end
    local tol = 1e-6
    local chain = { item }
    local pos = r.GetMediaItemInfo_Value(item, "D_POSITION") or 0.0
    local len = r.GetMediaItemInfo_Value(item, "D_LENGTH") or 0.0
    local start_pos = pos
    local end_pos = pos + len
    local n = r.CountTrackMediaItems(tr) or 0
    while true do
        local best, best_end = nil, -1e12
        for i = 0, n - 1 do
            local it = r.GetTrackMediaItem(tr, i)
            if it ~= item then
                local p = r.GetMediaItemInfo_Value(it, "D_POSITION") or 0.0
                local l = r.GetMediaItemInfo_Value(it, "D_LENGTH") or 0.0
                local e = p + l
                if math.abs(e - start_pos) <= tol and ItemsJoinable(it, chain[1], tol) then
                    if e > best_end then best, best_end = it, e end
                end
            end
        end
        if best then
            table.insert(chain, 1, best)
            start_pos = r.GetMediaItemInfo_Value(best, "D_POSITION") or start_pos
        else
            break
        end
    end
    while true do
        local best, best_pos = nil, 1e12
        for i = 0, n - 1 do
            local it = r.GetTrackMediaItem(tr, i)
            if it ~= item then
                local p = r.GetMediaItemInfo_Value(it, "D_POSITION") or 0.0
                local l = r.GetMediaItemInfo_Value(it, "D_LENGTH") or 0.0
                if math.abs(p - end_pos) <= tol and ItemsJoinable(chain[#chain], it, tol) then
                    if p < best_pos then best, best_pos = it, p end
                end
            end
        end
        if best then
            table.insert(chain, best)
            end_pos = (r.GetMediaItemInfo_Value(best, "D_POSITION") or end_pos) + (r.GetMediaItemInfo_Value(best, "D_LENGTH") or 0.0)
        else
            break
        end
    end
    return chain
end

local function CollectGlueChain(item)
    if not item then return {} end
    local tr = r.GetMediaItem_Track(item)
    if not tr then return { item } end
    local tol = 1e-6
    local sel = {}
    local set = {}
    local function add(it)
        if not set[it] then set[it] = true; table.insert(sel, it) end
    end
    add(item)
    local start_pos = r.GetMediaItemInfo_Value(item, "D_POSITION") or 0.0
    local end_pos = start_pos + (r.GetMediaItemInfo_Value(item, "D_LENGTH") or 0.0)
    local n = r.CountTrackMediaItems(tr) or 0
    local expanded = true
    while expanded do
        expanded = false
        for i = 0, n - 1 do
            local it = r.GetTrackMediaItem(tr, i)
            if not set[it] then
                local p = r.GetMediaItemInfo_Value(it, "D_POSITION") or 0.0
                local e = p + (r.GetMediaItemInfo_Value(it, "D_LENGTH") or 0.0)
                if (p <= end_pos + tol) and (e >= start_pos - tol) then
                    add(it)
                    if p < start_pos then start_pos = p end
                    if e > end_pos then end_pos = e end
                    expanded = true
                end
            end
        end
    end
    return sel
end

local function GlueExecute()
    if not current_item then return nil end
    r.SelectAllMediaItems(0, false)
    if glue_include_touching then
        for _, it in ipairs(CollectGlueChain(current_item)) do
            r.SetMediaItemSelected(it, true)
        end
    else
        r.SetMediaItemSelected(current_item, true)
    end
    r.Undo_BeginBlock()
    r.Main_OnCommand(41588, 0)
    r.Undo_EndBlock("RAW: Glue items", -1)
    local cnt = r.CountSelectedMediaItems(0) or 0
    local target = cnt > 0 and r.GetSelectedMediaItem(0, cnt - 1) or nil
    return target
end

ItemsJoinable = function(a, b, tol)
    tol = tol or 1e-6
    if not a or not b then return false end
    local ta = r.GetActiveTake(a)
    local tb = r.GetActiveTake(b)
    if not ta or not tb then return false end
    if r.TakeIsMIDI(ta) or r.TakeIsMIDI(tb) then return false end
    local sa = r.GetMediaItemTake_Source(ta)
    local sb = r.GetMediaItemTake_Source(tb)
    if not sa or not sb then return false end
    local fa = r.GetMediaSourceFileName(sa) or ""
    local fb = r.GetMediaSourceFileName(sb) or ""
    if fa ~= fb then return false end
    local pra = r.GetMediaItemTakeInfo_Value(ta, "D_PLAYRATE") or 1.0
    local prb = r.GetMediaItemTakeInfo_Value(tb, "D_PLAYRATE") or 1.0
    if math.abs(pra - prb) > 1e-9 then return false end
    return true
end

local function TryJoinOnce()
    if not current_item then return false end
    local tr = r.GetMediaItem_Track(current_item)
    if not tr then return false end
    local pos = r.GetMediaItemInfo_Value(current_item, "D_POSITION") or 0.0
    local len = r.GetMediaItemInfo_Value(current_item, "D_LENGTH") or 0.0
    local endpos = pos + len
    local n = r.CountTrackMediaItems(tr) or 0
    local tol = 1e-6
    local best_left, best_left_end = nil, -1e12
    local best_right, best_right_pos = nil, 1e12
    for i = 0, n - 1 do
        local it = r.GetTrackMediaItem(tr, i)
        if it ~= current_item then
            local p = r.GetMediaItemInfo_Value(it, "D_POSITION") or 0.0
            local l = r.GetMediaItemInfo_Value(it, "D_LENGTH") or 0.0
            local e = p + l
            if math.abs(e - pos) <= tol and ItemsJoinable(it, current_item, tol) then
                if e > best_left_end then best_left, best_left_end = it, e end
            end
            if math.abs(p - endpos) <= tol and ItemsJoinable(current_item, it, tol) then
                if p < best_right_pos then best_right, best_right_pos = it, p end
            end
        end
    end
    if best_left then
        local ta = r.GetActiveTake(current_item)
        local tl = r.GetActiveTake(best_left)
        if ta and tl then
            local offsL = r.GetMediaItemTakeInfo_Value(tl, "D_STARTOFFS") or 0.0
            local new_pos = r.GetMediaItemInfo_Value(best_left, "D_POSITION") or pos
            local new_end = endpos
            local new_len = math.max(0.0, new_end - new_pos)
            r.SetMediaItemInfo_Value(current_item, "D_POSITION", new_pos)
            r.SetMediaItemInfo_Value(current_item, "D_LENGTH", new_len)
            r.SetMediaItemTakeInfo_Value(ta, "D_STARTOFFS", offsL)
            r.UpdateItemInProject(current_item)
            local trk = r.GetMediaItem_Track(best_left)
            if trk then r.DeleteTrackMediaItem(trk, best_left) end
            r.UpdateArrange()
            return true
        end
    elseif best_right then
        local ta = r.GetActiveTake(current_item)
        local trt = r.GetActiveTake(best_right)
        if ta and trt then
            local new_pos = pos
            local new_end = (r.GetMediaItemInfo_Value(best_right, "D_POSITION") or endpos) + (r.GetMediaItemInfo_Value(best_right, "D_LENGTH") or 0.0)
            local new_len = math.max(0.0, new_end - new_pos)
            r.SetMediaItemInfo_Value(current_item, "D_LENGTH", new_len)
            r.UpdateItemInProject(current_item)
            local trk = r.GetMediaItem_Track(best_right)
            if trk then r.DeleteTrackMediaItem(trk, best_right) end
            r.UpdateArrange()
            return true
        end
    end
    return false
end

local function JoinAllTouching()
    if not current_item then return nil end
    r.Undo_BeginBlock()
    local changed = false
    while TryJoinOnce() do changed = true end
    if changed then
        r.UpdateItemInProject(current_item)
    end
    r.Undo_EndBlock("RAW: Join (heal) touching splits", -1)
    return changed and current_item or nil
end

local NORMALIZE_ITEMS_CMD = 40108 

local function FindSWSNormalizeCmd()
    if sws_norm_named_cmd and sws_norm_named_cmd ~= "" then
        local cmd = r.NamedCommandLookup(sws_norm_named_cmd)
        if cmd and cmd > 0 then return cmd end
    end
    local cmd = r.NamedCommandLookup("_BR_NORMALIZE_LOUDNESS_ITEMS")
    return (cmd and cmd > 0) and cmd or 0
end

local function NormalizeItemWhole()
    if not current_item then return nil end
    r.Undo_BeginBlock()
    r.SelectAllMediaItems(0, false)
    r.SetMediaItemSelected(current_item, true)
    local sws_cmd = prefer_sws_normalize and FindSWSNormalizeCmd() or 0
    if sws_cmd and sws_cmd > 0 then
        r.Main_OnCommand(sws_cmd, 0)
    else
        r.Main_OnCommand(NORMALIZE_ITEMS_CMD, 0)
    end
    r.Undo_EndBlock("RAW: Normalize item", -1)
    if current_accessor then r.DestroyAudioAccessor(current_accessor); current_accessor = nil end
    peak_pyr = nil; peak_pyr_ch = nil; is_loaded = false
    LoadPeaks(current_item, true)
    return current_item
end

local function NormalizeSelectionWithinItem()
    if not current_item then return nil end
    local s, e = GetSelectionRangeClamped()
    if not s then return nil end
    r.Undo_BeginBlock()
    local right_item = r.SplitMediaItem(current_item, e)
    local mid_item = r.SplitMediaItem(current_item, s)
    local target_item = nil
    if mid_item then
        r.SelectAllMediaItems(0, false)
        r.SetMediaItemSelected(mid_item, true)
        local sws_cmd = prefer_sws_normalize and FindSWSNormalizeCmd() or 0
        if sws_cmd and sws_cmd > 0 then
            r.Main_OnCommand(sws_cmd, 0)
        else
            r.Main_OnCommand(NORMALIZE_ITEMS_CMD, 0)
        end
        if glue_after_normalize_sel then
            local chain = CollectTouchingChain(mid_item)
            r.SelectAllMediaItems(0, false)
            for _, it in ipairs(chain) do r.SetMediaItemSelected(it, true) end
            r.Main_OnCommand(41588, 0) 
            local sel_cnt = r.CountSelectedMediaItems(0) or 0
            if sel_cnt > 0 then
                target_item = r.GetSelectedMediaItem(0, sel_cnt - 1)
            end
        end
        if not target_item then target_item = mid_item end
    end
    r.Undo_EndBlock("RAW: Normalize selection", -1)
    if current_accessor then r.DestroyAudioAccessor(current_accessor); current_accessor = nil end
    peak_pyr = nil; peak_pyr_ch = nil; is_loaded = false
    LoadPeaks(target_item or current_item)
    return target_item or current_item
end

local function IsAudioItem(item)
    if not item then return false end
    local take = r.GetActiveTake(item)
    if not take then return false end
    if r.TakeIsMIDI(take) then return false end
    return true
end

local function SelectAndLoadItem(item)
    if not item then return end
    r.SelectAllMediaItems(0, false)
    r.SetMediaItemSelected(item, true)
    local pos = r.GetMediaItemInfo_Value(item, "D_POSITION") or 0.0
    local len = r.GetMediaItemInfo_Value(item, "D_LENGTH") or 0.0
    local endpos = pos + math.max(0.0, len)
    r.GetSet_LoopTimeRange(true, false, pos, endpos, false)
    r.SetEditCurPos(pos, false, false)
    r.UpdateArrange()
    sel_a, sel_b = pos, endpos
    current_item = item
    if current_accessor then r.DestroyAudioAccessor(current_accessor); current_accessor = nil end
    peak_pyr = nil; peak_pyr_ch = nil; is_loaded = false
    LoadPeaks(item)
end

local function GotoPrevItemOnTrack()
    if not current_item then return end
    local tr = r.GetMediaItem_Track(current_item)
    if not tr then return end
    local pos = r.GetMediaItemInfo_Value(current_item, "D_POSITION") or 0.0
    local n = r.CountTrackMediaItems(tr) or 0
    local best, best_pos = nil, -1e18
    for i = 0, n - 1 do
        local it = r.GetTrackMediaItem(tr, i)
        if it ~= current_item and IsAudioItem(it) then
            local p = r.GetMediaItemInfo_Value(it, "D_POSITION") or 0.0
            if p < pos - 1e-9 and p > best_pos then best, best_pos = it, p end
        end
    end
    if best then SelectAndLoadItem(best) end
end

local function GotoNextItemOnTrack()
    if not current_item then return end
    local tr = r.GetMediaItem_Track(current_item)
    if not tr then return end
    local pos = r.GetMediaItemInfo_Value(current_item, "D_POSITION") or 0.0
    local n = r.CountTrackMediaItems(tr) or 0
    local best, best_pos = nil, 1e18
    for i = 0, n - 1 do
        local it = r.GetTrackMediaItem(tr, i)
        if it ~= current_item and IsAudioItem(it) then
            local p = r.GetMediaItemInfo_Value(it, "D_POSITION") or 0.0
            if p > pos + 1e-9 and p < best_pos then best, best_pos = it, p end
        end
    end
    if best then SelectAndLoadItem(best) end
end

local function NearestAudioItemOnTrackAtTime(track, t0)
    if not track then return nil end
    local n = r.CountTrackMediaItems(track) or 0
    local best, best_dist = nil, 1e18
    for i = 0, n - 1 do
        local it = r.GetTrackMediaItem(track, i)
        if IsAudioItem(it) then
            local p = r.GetMediaItemInfo_Value(it, "D_POSITION") or 0.0
            local l = r.GetMediaItemInfo_Value(it, "D_LENGTH") or 0.0
            local e = p + math.max(0.0, l)
            local dist
            if t0 >= p - 1e-9 and t0 <= e + 1e-9 then
                dist = 0.0
            elseif t0 < p then
                dist = p - t0
            else
                dist = t0 - e
            end
            if dist < best_dist then best, best_dist = it, dist end
            if best_dist == 0.0 then break end
        end
    end
    return best
end

local function GotoFirstItemOnAdjacentTrack(dir)
    if not current_item then return end
    local tr = r.GetMediaItem_Track(current_item)
    if not tr then return end
    local idx = r.CSurf_TrackToID(tr, false) - 1 
    local tracks = r.CountTracks(0) or 0
    local target_idx = idx + (dir or 0)
    if target_idx < 0 or target_idx >= tracks then return end
    local target_tr = r.GetTrack(0, target_idx)
    local t0 = r.GetMediaItemInfo_Value(current_item, "D_POSITION") or 0.0
    local it = NearestAudioItemOnTrackAtTime(target_tr, t0)
    if it then SelectAndLoadItem(it) end
end

local function ReverseItemWhole()
    if not current_item then return end
    r.Undo_BeginBlock()
    r.SelectAllMediaItems(0, false)
    r.SetMediaItemSelected(current_item, true)
    r.Main_OnCommand(41051, 0) 
    r.Undo_EndBlock("RAW: Reverse item", -1)
    if current_accessor then r.DestroyAudioAccessor(current_accessor); current_accessor = nil end
    peak_pyr = nil
    peak_pyr_ch = nil
    is_loaded = false
    LoadPeaks(current_item)
end

local function ReverseSelectionWithinItem()
    if not current_item then return end
    local s, e = GetSelectionRangeClamped()
    if not s then return end
    r.Undo_BeginBlock()
    local right_item = r.SplitMediaItem(current_item, e)
    local mid_item = r.SplitMediaItem(current_item, s)
    if mid_item then
        r.SelectAllMediaItems(0, false)
        r.SetMediaItemSelected(mid_item, true)
        r.Main_OnCommand(41051, 0) 
    end
    r.Undo_EndBlock("RAW: Reverse selection", -1)
    if current_accessor then r.DestroyAudioAccessor(current_accessor); current_accessor = nil end
    peak_pyr = nil
    peak_pyr_ch = nil
    is_loaded = false
    LoadPeaks(mid_item or current_item, true)
end

function IsItemPolarityInverted(it)
    if not it then return false end
    local ok, chunk = r.GetItemStateChunk(it, "", false)
    if not ok or not chunk then return false end
    local line = chunk:match("VOLPAN[^\r\n]*")
    if not line then return false end
    local head, sign = line:match("^(VOLPAN%s+[%-%d%.]+%s+[%-%d%.]+%s*)(%-?)(.*)$")
    if not head then return false end
    return sign == "-"
end

function SetItemPolarity(it, invert)
    if not it then return false end
    local ok, chunk = r.GetItemStateChunk(it, "", false)
    if not ok or not chunk then return false end
    local line = chunk:match("VOLPAN[^\r\n]*")
    if not line then return false end
    local head, sign, tail = line:match("^(VOLPAN%s+[%-%d%.]+%s+[%-%d%.]+%s*)(%-?)(.*)$")
    if not head then return false end
    local new_line
    if invert then
        if sign == "-" then
            new_line = line 
        else
            new_line = head .. "-" .. (tail or "")
        end
    else
        if sign == "-" then
            new_line = head .. (tail or "")
        else
            new_line = line 
        end
    end
    local start_pos = chunk:find(line, 1, true)
    if not start_pos then return false end
    local before = chunk:sub(1, start_pos - 1)
    local after = chunk:sub(start_pos + #line)
    local newchunk = before .. new_line .. after
    r.SetItemStateChunk(it, newchunk, false)
    r.UpdateItemInProject(it)
    return true
end

local function ToggleItemPolarity()
    if not current_item then return end
    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)
    local inv = not IsItemPolarityInverted(current_item)
    SetItemPolarity(current_item, inv)
    r.PreventUIRefresh(-1)
    r.Undo_EndBlock("RAW: Phase invert item", -1)
    if current_accessor then r.DestroyAudioAccessor(current_accessor); current_accessor = nil end
    peak_pyr = nil
    peak_pyr_ch = nil
    is_loaded = false
    LoadPeaks(current_item, true)
end

local function ToggleSelectionPolarity()
    if not current_item then return end
    local s, e = GetSelectionRangeClamped()
    if not s then
        ToggleItemPolarity()
        return
    end
    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)
    local right_item = r.SplitMediaItem(current_item, e)
    local mid_item = r.SplitMediaItem(current_item, s)
    local target = mid_item or current_item
    SetItemPolarity(target, not IsItemPolarityInverted(target))
    r.SetMediaItemSelected(target, true)
    r.PreventUIRefresh(-1)
    r.Undo_EndBlock("RAW: Phase invert selection", -1)
    if current_accessor then r.DestroyAudioAccessor(current_accessor); current_accessor = nil end
    peak_pyr = nil
    peak_pyr_ch = nil
    is_loaded = false
    LoadPeaks(target or current_item, true)
end

local function DrawWaveform(draw_list, x, y, w, h)
    local grid_col = ColorWithAlpha(COLOR_GRID_BASE, grid_alpha)
    local zero_col = ColorWithAlpha(COLOR_ZERO_LINE_BASE, grid_alpha)
    r.ImGui_DrawList_AddRectFilled(draw_list, x, y, x + w, y + h, COLOR_BACKGROUND)
    r.ImGui_DrawList_PushClipRect(draw_list, x, y, x + w, y + h, true)
    
    if show_grid and current_item and current_item_len > 0 then
        local _, gdiv = r.GetSetProjectGrid(0, false, 0, 0, 0)
        if not gdiv or gdiv <= 0 then gdiv = 0.25 end

        local vt0 = math.max(current_item_start, view_start)
        local vt1 = math.min(current_item_start + current_item_len, view_start + view_len)
        if vt1 > vt0 then
            local qn0 = r.TimeMap2_timeToQN(0, vt0)
            local qn1 = r.TimeMap2_timeToQN(0, vt1)

            local num0, denom0 = r.TimeMap_GetTimeSigAtTime(0, vt0)
            if not num0 or num0 <= 0 then num0 = 4 end
            if not denom0 or denom0 <= 0 then denom0 = 4 end
            local bar_qn0 = num0 * (4.0 / denom0)
            local step0 = math.max(1e-9, gdiv * bar_qn0)
            local bar_index0 = math.floor(qn0 / bar_qn0)
            local bar_start_qn0 = bar_index0 * bar_qn0
            local first_qn = bar_start_qn0 + math.ceil((qn0 - bar_start_qn0) / step0) * step0

            local qn = first_qn
            local max_lines = 4096
            local count = 0
            while qn <= qn1 + 1e-9 do
                count = count + 1
                if count > max_lines then break end
                local t = r.TimeMap2_QNToTime(0, qn)
                if not t then break end
                if t >= vt0 and t <= vt1 then
                    local num, denom = r.TimeMap_GetTimeSigAtTime(0, t)
                    if not num or num <= 0 then num = 4 end
                    if not denom or denom <= 0 then denom = 4 end
                    local bar_qn = num * (4.0 / denom)
                    local phase = qn / math.max(1e-12, bar_qn)
                    local frac = phase - math.floor(phase)
                    local is_bar = (frac < 1e-6) or ((1.0 - frac) < 1e-6)
                    local rel = (t - vt0) / (vt1 - vt0)
                    local gx = x + rel * w
                    local thickness = is_bar and 2.0 or 1.0
                    r.ImGui_DrawList_AddLine(draw_list, gx, y, gx, y + h, grid_col, thickness)
                    local step = math.max(1e-9, gdiv * bar_qn)
                    qn = qn + step
                else
                    local num, denom = r.TimeMap_GetTimeSigAtTime(0, t)
                    if not num or num <= 0 then num = 4 end
                    if not denom or denom <= 0 then denom = 4 end
                    local bar_qn = num * (4.0 / denom)
                    local step = math.max(1e-9, gdiv * bar_qn)
                    qn = qn + step
                end
            end
        end
    end
    
    local center_y = y + h / 2
    if show_grid and not (draw_channels_separately and channels >= 2) then
        r.ImGui_DrawList_AddLine(draw_list, x, center_y, x + w, center_y, zero_col, 1.0)
    end
    
    DrawDbOverlay(draw_list, x, y, w, h)

    if current_item and peak_pyr and peak_pyr.built and view_len > 0 then
        local pixels = math.max(1, math.floor(w + 0.5))
        local level = ChoosePyrLevel(pixels)
        if level then
            local scale = (h / 2) * 0.9 * amp_zoom
            local dx = w / pixels
            if spectral_peaks then EnsureViewPeaks(pixels) end
            local default_fill = ColorWithAlpha(COLOR_WAVEFORM, waveform_fill_alpha or 0.18)
            local default_line = ColorWithAlpha(COLOR_WAVEFORM, 0.90)
            local edge_alpha = math.min((waveform_fill_alpha or 0.18) * 0.6, 0.12)
            local col_edge = ColorWithAlpha(COLOR_WAVEFORM, edge_alpha)
            local item_len = math.max(1e-12, peak_pyr.item_len)
            local item_t0 = peak_pyr.item_start
            local b0 = math.max(1, math.floor(((view_start - item_t0) / item_len) * level.bins) + 1)
            local b1 = math.min(level.bins, math.floor((((view_start + view_len) - item_t0) / item_len) * level.bins + 1e-9))
            local env_t0 = current_item_start or item_t0
            local env_t1 = (current_item_start or item_t0) + (current_item_len or item_len)
            local env_fin  = (current_item and r.GetMediaItemInfo_Value(current_item, 'D_FADEINLEN'))  or 0.0
            local env_fout = (current_item and r.GetMediaItemInfo_Value(current_item, 'D_FADEOUTLEN')) or 0.0
            local env_sin  = (current_item and r.GetMediaItemInfo_Value(current_item, 'C_FADEINSHAPE'))  or 0
            local env_sout = (current_item and r.GetMediaItemInfo_Value(current_item, 'C_FADEOUTSHAPE')) or 0
            local env_din  = (current_item and r.GetMediaItemInfo_Value(current_item, 'D_FADEINDIR'))  or 0.0
            local env_dout = (current_item and r.GetMediaItemInfo_Value(current_item, 'D_FADEOUTDIR')) or 0.0
            local env_vol  = (current_item and r.GetMediaItemInfo_Value(current_item, 'D_VOL')) or 1.0
            if env_vol < 1e-6 then env_vol = 1e-6 end
            local vol_env = (current_take and ValidTake(current_take) and ValidItem(current_item)) and r.GetTakeEnvelopeByName(current_take, "Volume") or nil
            local vol_env_mode = vol_env and (r.GetEnvelopeScalingMode and r.GetEnvelopeScalingMode(vol_env) or 0) or nil
            local function EnvelopeGainAt(t)
                if not t then return env_vol end
                local base
                if env_fin and env_fin > 0 and t >= env_t0 and t <= (env_t0 + env_fin) then
                    local u = (t - env_t0) / env_fin
                    local f = EvalFadeIn and EvalFadeIn(env_sin, env_din, u) or u
                    base = env_vol * f
                elseif env_fout and env_fout > 0 and t >= (env_t1 - env_fout) and t <= env_t1 then
                    local u = (t - (env_t1 - env_fout)) / env_fout
                    local f = EvalFadeOut and EvalFadeOut(env_sout, env_dout, u) or (1 - u)
                    base = env_vol * f
                else
                    base = env_vol
                end
                if vol_env then
                    local t_in = t - env_t0
                    if t_in < 0 then t_in = 0 end
                    if t_in > (current_item_len or 0) then t_in = current_item_len or 0 end
                    local _, v = r.Envelope_Evaluate(vol_env, t_in, 0, 0)
                    if v ~= nil then
                        if r.ScaleFromEnvelopeMode and vol_env_mode ~= nil then
                            local amp = r.ScaleFromEnvelopeMode(vol_env_mode, v)
                            if amp and amp > 0 then base = base * amp else base = base * 0 end
                        else
                            base = base * v
                        end
                    end
                end
                return base
            end
            
            local dc_envL, dc_envR, dc_mode_param
            do
                if current_take and ValidTake(current_take) and ValidItem(current_item) then
                    local fxidx = r.TakeFX_AddByName(current_take, 'JS: DC_offset_sampleaccurate.jsfx', 0)
                    if fxidx == -1 and pencil_mode and pencil_target == 'dc_offset' then
                        fxidx = EnsureTakeDCOffsetFX(current_take)
                    end
                    if fxidx ~= -1 then
                        dc_envL = r.TakeFX_GetEnvelope(current_take, fxidx, 0, true)
                        dc_envR = r.TakeFX_GetEnvelope(current_take, fxidx, 1, true)
                        local function ensureBaseline(env)
                            if not env then return end
                            local cnt = r.CountEnvelopePoints(env) or 0
                            if cnt == 0 then
                                local itlen = current_item_len or 0
                r.InsertEnvelopePoint(env, 0.0, 0.0, 0, 0, 0, true)
                if itlen > 0 then r.InsertEnvelopePoint(env, itlen, 0.0, 0, 0, 0, true) end
                                r.Envelope_SortPoints(env)
                            end
                        end
                        ensureBaseline(dc_envL)
                        ensureBaseline(dc_envR)
                    end
                end
            end
            local dc_cntL = (dc_envL and (r.CountEnvelopePoints(dc_envL) or 0)) or 0
            local dc_cntR = (dc_envR and (r.CountEnvelopePoints(dc_envR) or 0)) or 0
            local function env_is_raw(env)
                if not env then return false end
                local cnt = r.CountEnvelopePoints(env) or 0
                if cnt == 0 then return false end
                local seenNonZero = false
                local max_check = math.min(cnt, 64)
                for i = 0, max_check - 1 do
                    local ok, _, v = r.GetEnvelopePoint(env, i)
                    if ok then
                        if v < 0.0 or v > 1.0 then return true end
                        if math.abs(v or 0.0) > 1e-12 then seenNonZero = true end
                    end
                end
                if not seenNonZero then return true end 
                return false
            end
            local dc_is_raw_L = env_is_raw(dc_envL)
            local dc_is_raw_R = env_is_raw(dc_envR)
            local function env_to_dc(val, is_raw)
                if val == nil then return nil end
                local v = tonumber(val) or 0.0
                if is_raw then
                    if v < -1.0 then v = -1.0 elseif v > 1.0 then v = 1.0 end
                    return v
                else
                    v = (v * 2.0) - 1.0
                    if v < -1.0 then v = -1.0 elseif v > 1.0 then v = 1.0 end
                    return v
                end
            end
            local function DCAt(t)
                if not dc_envL and not dc_envR then return 0.0, 0.0 end
                local t_in = t - (current_item_start or 0)
                if t_in < 0 then t_in = 0 end
                if t_in > (current_item_len or 0) then t_in = current_item_len or 0 end
                local l, rch = 0.0, 0.0
                if dc_envL then
                    if dc_cntL == 0 then
                        l = 0.0 
                    else
                        local _, t0e, v0 = r.GetEnvelopePoint(dc_envL, 0)
                        local _, t1e, v1 = r.GetEnvelopePoint(dc_envL, math.max(0, dc_cntL - 1))
                        if t_in <= (t0e or 0) then
                            l = env_to_dc((v0 ~= nil) and v0 or (dc_is_raw_L and 0.0 or 0.5), dc_is_raw_L) or 0.0
                        elseif t_in >= (t1e or 0) then
                            l = env_to_dc((v1 ~= nil) and v1 or (dc_is_raw_L and 0.0 or 0.5), dc_is_raw_L) or 0.0
                        else
                            local _, v = r.Envelope_Evaluate(dc_envL, t_in, 0, 0)
                            l = env_to_dc((v ~= nil) and v or (dc_is_raw_L and 0.0 or 0.5), dc_is_raw_L) or 0.0
                        end
                    end
                end
                if dc_envR then
                    if dc_cntR == 0 then
                        rch = 0.0
                    else
                        local _, t0e, v0 = r.GetEnvelopePoint(dc_envR, 0)
                        local _, t1e, v1 = r.GetEnvelopePoint(dc_envR, math.max(0, dc_cntR - 1))
                        if t_in <= (t0e or 0) then
                            rch = env_to_dc((v0 ~= nil) and v0 or (dc_is_raw_R and 0.0 or 0.5), dc_is_raw_R) or 0.0
                        elseif t_in >= (t1e or 0) then
                            rch = env_to_dc((v1 ~= nil) and v1 or (dc_is_raw_R and 0.0 or 0.5), dc_is_raw_R) or 0.0
                        else
                            local _, v2 = r.Envelope_Evaluate(dc_envR, t_in, 0, 0)
                            rch = env_to_dc((v2 ~= nil) and v2 or (dc_is_raw_R and 0.0 or 0.5), dc_is_raw_R) or 0.0
                        end
                    end
                end
                return l, rch
            end
            local function draw_lane(y0, yh, mins_arr, maxs_arr)
                if not mins_arr or not maxs_arr then return end
                local lane_center = y0 + yh * 0.5
                local lane_scale = (yh * 0.5) * 0.9 * (amp_zoom or 1.0)
                
                if show_grid then
                    r.ImGui_DrawList_AddLine(draw_list, x, lane_center, x + w, lane_center, zero_col, 1.0)
                end
                local outline_th = waveform_centerline_thickness or 1.0
                local outline_col = default_line
                local top_segments, bot_segments = nil, nil
                local cur_top, cur_bot = nil, nil
                local run_active = false
                if waveform_outline_paths then
                    top_segments, bot_segments = {}, {}
                end
                for p = 1, pixels do
                    local mn = mins_arr[p] or 0.0
                    local mx = maxs_arr[p] or 0.0
                    local t_mid = view_start + ((p - 0.5) / pixels) * view_len
                    local g = EnvelopeGainAt and EnvelopeGainAt(t_mid) or 1.0
                    local dcL, dcR = DCAt(t_mid)
                    local dc
                    if draw_channels_separately and channels >= 2 then
                        local half_h = h * 0.5
                        local is_top = (y0 < (y + half_h))
                        dc = is_top and dcL or dcR
                    else
                        dc = (channels >= 2) and ((dcL + dcR) * 0.5) or dcL
                    end
                    mn = (mn + dc) * g
                    mx = (mx + dc) * g
                    local y_top = lane_center - (mx * lane_scale)
                    local y_bot = lane_center - (mn * lane_scale)
                    if y_bot < y_top then y_top, y_bot = y_bot, y_top end
                    if y_top < y0 then y_top = y0 end
                    local y_max = y0 + yh
                    if y_bot > y_max then y_bot = y_max end
                    if y_bot > y_top then
                        local x0 = x + (p - 1) * dx
                        local x1 = x + p * dx
                        local inset = math.min(0.2 * dx, 0.6)
                        x0 = x0 + inset
                        x1 = x1 - inset
                        if x1 <= x0 then x1 = x0 + 1 end
                        local fill_col, line_col
                        if spectral_peaks and view_cache_z and view_cache_z[p] then
                            local z = view_cache_z[p]
                            local amp
                            if view_cache_rms and view_cache_rms[p] then
                                amp = view_cache_rms[p]
                            else
                                amp = math.max(math.abs(mn), math.abs(mx))
                            end
                            local bright = 0.35 + 0.65 * clamp01(amp * 1.2)
                            local rgb = apply_brightness(spectral_color(z), bright)
                            fill_col = ColorWithAlpha(rgb, waveform_fill_alpha or 0.18)
                            line_col = ColorWithAlpha(rgb, 0.90)
                        else
                            fill_col = default_fill
                            line_col = default_line
                        end
                        r.ImGui_DrawList_AddRectFilled(draw_list, x0, y_top, x1, y_bot, fill_col)
                        if waveform_soft_edges and (x1 - x0) > 1.5 then
                            r.ImGui_DrawList_AddLine(draw_list, x0, y_top, x0, y_bot, col_edge, 1.0)
                            r.ImGui_DrawList_AddLine(draw_list, x1, y_top, x1, y_bot, col_edge, 1.0)
                        end
                        if waveform_outline_paths then
                            local cxm = (x0 + x1) * 0.5
                            if not run_active then
                                cur_top, cur_bot = {}, {}
                                run_active = true
                            end
                            cur_top[#cur_top + 1] = {cxm, y_top}
                            cur_bot[#cur_bot + 1] = {cxm, y_bot}
                        else
                            local cxm = (x0 + x1) * 0.5
                            r.ImGui_DrawList_AddLine(draw_list, cxm, y_top, cxm, y_bot, line_col, outline_th)
                        end
                    else
                        if waveform_outline_paths and run_active then
                            top_segments[#top_segments + 1] = cur_top
                            bot_segments[#bot_segments + 1] = cur_bot
                            cur_top, cur_bot, run_active = nil, nil, false
                        end
                    end
                end
                if waveform_outline_paths then
                    if run_active then
                        top_segments[#top_segments + 1] = cur_top
                        bot_segments[#bot_segments + 1] = cur_bot
                    end
                    for i = 1, #top_segments do
                        local seg = top_segments[i]
                        if seg and #seg >= 2 then
                            r.ImGui_DrawList_PathClear(draw_list)
                            for j = 1, #seg do
                                local pt = seg[j]
                                r.ImGui_DrawList_PathLineTo(draw_list, pt[1], pt[2])
                            end
                            r.ImGui_DrawList_PathStroke(draw_list, outline_col, 0, outline_th)
                        end
                    end
                    for i = 1, #bot_segments do
                        local seg = bot_segments[i]
                        if seg and #seg >= 2 then
                            r.ImGui_DrawList_PathClear(draw_list)
                            for j = 1, #seg do
                                local pt = seg[j]
                                r.ImGui_DrawList_PathLineTo(draw_list, pt[1], pt[2])
                            end
                            r.ImGui_DrawList_PathStroke(draw_list, outline_col, 0, outline_th)
                        end
                    end
                end
            end

            local use_sep = (draw_channels_separately and channels >= 2)
            if use_sep and peak_pyr_ch and peak_pyr_ch.built then
                local pan_weight_L, pan_weight_R = 1.0, 1.0
                if show_pan_overlay and pan_visual_waveform and current_take then
                    local p = r.GetMediaItemTakeInfo_Value(current_take, 'D_PAN') or 0.0
                    if p < -1.0 then p = -1.0 elseif p > 1.0 then p = 1.0 end
                    local theta = (p + 1.0) * (math.pi * 0.25)
                    pan_weight_L = math.max(0.0, math.min(1.0, math.cos(theta)))
                    pan_weight_R = math.max(0.0, math.min(1.0, math.sin(theta)))
                end
                local ch_level = ChoosePyrLevelCh(pixels)
                if ch_level then
                    local lane_h = h * 0.5
            local sep_y = y + lane_h
            r.ImGui_DrawList_AddLine(draw_list, x, sep_y, x + w, sep_y, ColorWithAlpha(COLOR_GRID_BASE, 0.6), 2.0)
            if show_grid then
                r.ImGui_DrawList_AddLine(draw_list, x, sep_y, x + w, sep_y, zero_col, 1.0)
            end
                    local function draw_lane_from_pyr(y0, yh, chidx)
                        local lane_center = y0 + yh * 0.5
                        
                        if show_grid then
                            r.ImGui_DrawList_AddLine(draw_list, x, lane_center, x + w, lane_center, zero_col, 1.0)
                        end
                        local outline_th = waveform_centerline_thickness or 1.0
                        local outline_col = default_line
                        local top_segments, bot_segments = nil, nil
                        local cur_top, cur_bot = nil, nil
                        local run_active = false
                        if waveform_outline_paths then
                            top_segments, bot_segments = {}, {}
                        end
                        for p = 1, pixels do
                            local px_t0 = view_start + ((p - 1) / pixels) * view_len
                            local px_t1 = view_start + (p / pixels) * view_len
                            local bi0 = math.max(1, math.floor(((px_t0 - peak_pyr_ch.item_start) / math.max(1e-12, peak_pyr_ch.item_len)) * ch_level.bins) + 1)
                            local bi1 = math.min(ch_level.bins, math.floor(((px_t1 - peak_pyr_ch.item_start) / math.max(1e-12, peak_pyr_ch.item_len)) * ch_level.bins + 1e-9))
                            if bi1 < bi0 then bi1 = bi0 end
                            local mn, mx = 1e9, -1e9
                            for bi = bi0, bi1 do
                                local vmin = ch_level.mins_ch[chidx][bi] or 0.0
                                local vmax = ch_level.maxs_ch[chidx][bi] or 0.0
                                if vmin < mn then mn = vmin end
                                if vmax > mx then mx = vmax end
                            end
                            if mn == 1e9 then mn = 0.0; mx = 0.0 end
                            local t_mid = (px_t0 + px_t1) * 0.5
                            local g = EnvelopeGainAt and EnvelopeGainAt(t_mid) or 1.0
                            local dcL, dcR = DCAt(t_mid)
                            local dc = (chidx == 1) and dcL or dcR
                            mn = (mn + dc) * g
                            mx = (mx + dc) * g
                            if show_pan_overlay then
                                local pw = (chidx == 1) and pan_weight_L or pan_weight_R
                                mn = mn * pw
                                mx = mx * pw
                            end
                            local lane_scale = (yh * 0.5) * 0.9 * (amp_zoom or 1.0)
                            local y_top = lane_center - (mx * lane_scale)
                            local y_bot = lane_center - (mn * lane_scale)
                            if y_bot < y_top then y_top, y_bot = y_bot, y_top end
                            if y_top < y0 then y_top = y0 end
                            local y_max = y0 + yh
                            if y_bot > y_max then y_bot = y_max end
                            if y_bot > y_top then
                                local x0 = x + (p - 1) * dx
                                local x1 = x + p * dx
                                local inset = math.min(0.2 * dx, 0.6)
                                x0 = x0 + inset
                                x1 = x1 - inset
                                if x1 <= x0 then x1 = x0 + 1 end
                                local fill_col, line_col
                                if spectral_peaks and view_cache_z and view_cache_z[p] then
                                    local z = view_cache_z[p]
                                    local amp = math.max(math.abs(mn), math.abs(mx))
                                    local bright = 0.35 + 0.65 * clamp01(amp * 1.2)
                                    local rgb = apply_brightness(spectral_color(z), bright)
                                    fill_col = ColorWithAlpha(rgb, waveform_fill_alpha or 0.18)
                                    line_col = ColorWithAlpha(rgb, 0.90)
                                else
                                    fill_col = default_fill
                                    line_col = default_line
                                end
                                r.ImGui_DrawList_AddRectFilled(draw_list, x0, y_top, x1, y_bot, fill_col)
                                if waveform_soft_edges and (x1 - x0) > 1.5 then
                                    r.ImGui_DrawList_AddLine(draw_list, x0, y_top, x0, y_bot, col_edge, 1.0)
                                    r.ImGui_DrawList_AddLine(draw_list, x1, y_top, x1, y_bot, col_edge, 1.0)
                                end
                                if waveform_outline_paths then
                                    local cxm = (x0 + x1) * 0.5
                                    if not run_active then
                                        cur_top, cur_bot = {}, {}
                                        run_active = true
                                    end
                                    cur_top[#cur_top + 1] = {cxm, y_top}
                                    cur_bot[#cur_bot + 1] = {cxm, y_bot}
                                else
                                    local cxm = (x0 + x1) * 0.5
                                    r.ImGui_DrawList_AddLine(draw_list, cxm, y_top, cxm, y_bot, line_col, outline_th)
                                end
                            else
                                if waveform_outline_paths and run_active then
                                    top_segments[#top_segments + 1] = cur_top
                                    bot_segments[#bot_segments + 1] = cur_bot
                                    cur_top, cur_bot, run_active = nil, nil, false
                                end
                            end
                        end
                        if waveform_outline_paths then
                            if run_active then
                                top_segments[#top_segments + 1] = cur_top
                                bot_segments[#bot_segments + 1] = cur_bot
                            end
                            for i = 1, #top_segments do
                                local seg = top_segments[i]
                                if seg and #seg >= 2 then
                                    r.ImGui_DrawList_PathClear(draw_list)
                                    for j = 1, #seg do
                                        local pt = seg[j]
                                        r.ImGui_DrawList_PathLineTo(draw_list, pt[1], pt[2])
                                    end
                                    r.ImGui_DrawList_PathStroke(draw_list, outline_col, 0, outline_th)
                                end
                            end
                            for i = 1, #bot_segments do
                                local seg = bot_segments[i]
                                if seg and #seg >= 2 then
                                    r.ImGui_DrawList_PathClear(draw_list)
                                    for j = 1, #seg do
                                        local pt = seg[j]
                                        r.ImGui_DrawList_PathLineTo(draw_list, pt[1], pt[2])
                                    end
                                    r.ImGui_DrawList_PathStroke(draw_list, outline_col, 0, outline_th)
                                end
                            end
                        end
                    end
                    draw_lane_from_pyr(y, lane_h, 1)
                    draw_lane_from_pyr(y + lane_h, lane_h, 2)
                else
                    for p = 1, pixels do
                    end
                end
            else
                local mono_top_segments, mono_bot_segments = nil, nil
                local mono_top, mono_bot = nil, nil
                local mono_run_active = false
                if waveform_outline_paths then
                    mono_top_segments, mono_bot_segments = {}, {}
                end
                for p = 1, pixels do
                    local px_t0 = view_start + ((p - 1) / pixels) * view_len
                    local px_t1 = view_start + (p / pixels) * view_len
                    local bi0 = math.max(1, math.floor(((px_t0 - item_t0) / item_len) * level.bins) + 1)
                    local bi1 = math.min(level.bins, math.floor(((px_t1 - item_t0) / item_len) * level.bins + 1e-9))
                    if bi1 < bi0 then bi1 = bi0 end
                    local mn, mx = 1e9, -1e9
                    for bi = bi0, bi1 do
                        local vmin = level.mins[bi] or 0.0
                        local vmax = level.maxs[bi] or 0.0
                        if vmin < mn then mn = vmin end
                        if vmax > mx then mx = vmax end
                    end
                    if mn == 1e9 then mn = 0.0; mx = 0.0 end
                    local t_mid = (px_t0 + px_t1) * 0.5
                    local g = EnvelopeGainAt and EnvelopeGainAt(t_mid) or 1.0
                    local dcL, dcR = DCAt and DCAt(t_mid) or 0.0, 0.0
                    local dc = (channels >= 2) and ((dcL + dcR) * 0.5) or dcL
                    mn = (mn + dc) * g
                    mx = (mx + dc) * g
                    local y_top = center_y - (mx * scale)
                    local y_bot = center_y - (mn * scale)
                    if y_bot < y_top then y_top, y_bot = y_bot, y_top end
                    if y_top < y then y_top = y end
                    local y_max = y + h
                    if y_bot > y_max then y_bot = y_max end
                    if y_bot > y_top then
                        local x0 = x + (p - 1) * dx
                        local x1 = x + p * dx
                        local inset = math.min(0.2 * dx, 0.6)
                        x0 = x0 + inset
                        x1 = x1 - inset
                        if x1 <= x0 then x1 = x0 + 1 end
                        local fill_col, line_col
                        if spectral_peaks and view_cache_z and view_cache_z[p] then
                            local z = view_cache_z[p]
                            local amp
                            if view_cache_rms and view_cache_rms[p] then
                                amp = view_cache_rms[p]
                            else
                                amp = math.max(math.abs(mn), math.abs(mx))
                            end
                            local bright = 0.35 + 0.65 * clamp01(amp * 1.2)
                            local rgb = apply_brightness(spectral_color(z), bright)
                            fill_col = ColorWithAlpha(rgb, waveform_fill_alpha or 0.18)
                            line_col = ColorWithAlpha(rgb, 0.90)
                        else
                            fill_col = default_fill
                            line_col = default_line
                        end
                        r.ImGui_DrawList_AddRectFilled(draw_list, x0, y_top, x1, y_bot, fill_col)
                        if waveform_soft_edges and (x1 - x0) > 1.5 then
                            r.ImGui_DrawList_AddLine(draw_list, x0, y_top, x0, y_bot, col_edge, 1.0)
                            r.ImGui_DrawList_AddLine(draw_list, x1, y_top, x1, y_bot, col_edge, 1.0)
                        end
                        if waveform_outline_paths then
                            if not mono_run_active then
                                mono_top, mono_bot = {}, {}
                                mono_run_active = true
                            end
                            local cx = (x0 + x1) * 0.5
                            mono_top[#mono_top + 1] = {cx, y_top}
                            mono_bot[#mono_bot + 1] = {cx, y_bot}
                        else
                            local cx = (x0 + x1) * 0.5
                            r.ImGui_DrawList_AddLine(draw_list, cx, y_top, cx, y_bot, line_col, waveform_centerline_thickness or 1.0)
                        end
                    else
                        if waveform_outline_paths and mono_run_active then
                            mono_top_segments[#mono_top_segments + 1] = mono_top
                            mono_bot_segments[#mono_bot_segments + 1] = mono_bot
                            mono_top, mono_bot, mono_run_active = nil, nil, false
                        end
                    end
                end
                if waveform_outline_paths then
                    if mono_run_active then
                        mono_top_segments[#mono_top_segments + 1] = mono_top
                        mono_bot_segments[#mono_bot_segments + 1] = mono_bot
                    end
                    local outline_th = waveform_centerline_thickness or 1.0
                    local outline_col = default_line
                    for i = 1, #mono_top_segments do
                        local seg = mono_top_segments[i]
                        if seg and #seg >= 2 then
                            r.ImGui_DrawList_PathClear(draw_list)
                            for j = 1, #seg do
                                local pt = seg[j]
                                r.ImGui_DrawList_PathLineTo(draw_list, pt[1], pt[2])
                            end
                            r.ImGui_DrawList_PathStroke(draw_list, outline_col, 0, outline_th)
                        end
                    end
                    for i = 1, #mono_bot_segments do
                        local seg = mono_bot_segments[i]
                        if seg and #seg >= 2 then
                            r.ImGui_DrawList_PathClear(draw_list)
                            for j = 1, #seg do
                                local pt = seg[j]
                                r.ImGui_DrawList_PathLineTo(draw_list, pt[1], pt[2])
                            end
                            r.ImGui_DrawList_PathStroke(draw_list, outline_col, 0, outline_th)
                        end
                    end
                end
            end
        end
    end
    r.ImGui_DrawList_PopClipRect(draw_list)
end

local function Loop()
    
    r.ImGui_SetNextWindowSizeConstraints(ctx, MIN_WINDOW_WIDTH, MIN_WINDOW_HEIGHT, 9999, 9999)
    
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_TitleBg(),          COLOR_BACKGROUND)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_TitleBgActive(),    COLOR_BACKGROUND)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_TitleBgCollapsed(), COLOR_BACKGROUND)

    local visible, open = r.ImGui_Begin(ctx, 'TK Audio Editor', true)
    
    if visible then
        local did_reload_from_selection = false
        do
            local sel_cnt_now = r.CountSelectedMediaItems(0) or 0
            local guid_now = nil
            if sel_cnt_now > 0 then
                local it_now = r.GetSelectedMediaItem(0, sel_cnt_now - 1)
                if it_now then
                    local _ok, g = r.GetSetMediaItemInfo_String(it_now, "GUID", "", false)
                    guid_now = g
                end
            end
            if sel_cnt_now ~= (last_sel_count or -1) or guid_now ~= last_sel_guid then
                is_loaded = false
                view_cache_valid = false
                peak_pyr = nil
                peak_pyr_ch = nil
                pending_sel_reload = 2
            end
            if (pending_sel_reload or 0) > 0 then
                local sel_cnt = r.CountSelectedMediaItems(0) or 0
                local sel_item, guid = nil, nil
                if sel_cnt > 0 then
                    sel_item = r.GetSelectedMediaItem(0, sel_cnt - 1)
                    if sel_item then
                        local _ok, g = r.GetSetMediaItemInfo_String(sel_item, "GUID", "", false)
                        guid = g
                    end
                end
                LoadPeaks(sel_item)
                last_sel_count = sel_cnt
                last_sel_guid = guid
                pending_sel_reload = (pending_sel_reload or 1) - 1
                did_reload_from_selection = true
            end
        end
        if not did_reload_from_selection then LoadPeaks() end

    if r.ImGui_IsWindowFocused and r.ImGui_IsKeyPressed and r.ImGui_Key_I and r.ImGui_Key_F and r.ImGui_Key_S and r.ImGui_Key_T and r.ImGui_Key_X then
            if r.ImGui_IsWindowFocused(ctx) then
                if r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_I(), false) then
            is_interacting = true; last_interaction_time = r.time_precise()
                    if current_item and current_item_len and current_item_len > 0 then
                        view_start = current_item_start
                        view_len = math.max(1e-6, current_item_len)
                        view_cache_valid = false
                    end
                end
                if r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_F(), false) then
            is_interacting = true; last_interaction_time = r.time_precise()
                    if sel_a and sel_b and current_item then
                        local a = math.max(current_item_start, math.min(sel_a, sel_b))
                        local b = math.min(current_item_start + current_item_len, math.max(sel_a, sel_b))
                        if b > a then
                            view_start = a
                            view_len = math.max(1e-6, b - a)
                            view_cache_valid = false
                        end
                    end
                end
                if r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_S(), false) then
                    is_interacting = true; last_interaction_time = r.time_precise()
                    r.Undo_BeginBlock()
                    if current_item then
                        local s,e = GetSelectionRangeClamped()
                        if s then
                            r.SelectAllMediaItems(0, false)
                            r.SplitMediaItem(current_item, e)
                            local left_item = r.SplitMediaItem(current_item, s)
                            if left_item then r.SetMediaItemSelected(left_item, true) end
                        else
                            local t = r.GetCursorPosition()
                            if t and current_item_start and current_item_len and t > current_item_start and t < (current_item_start + current_item_len) then
                                local right = r.SplitMediaItem(current_item, t)
                                r.SelectAllMediaItems(0, false)
                                if right then r.SetMediaItemSelected(right, true) else r.SetMediaItemSelected(current_item, true) end
                            end
                        end
                        local sel_n = r.CountSelectedMediaItems(0)
                        local target = sel_n > 0 and r.GetSelectedMediaItem(0, sel_n - 1) or nil
                        if current_accessor then r.DestroyAudioAccessor(current_accessor); current_accessor = nil end
                        peak_pyr = nil
                        current_item = target or current_item
                        is_loaded = false; LoadPeaks(target)
                    end
                    r.Undo_EndBlock("RAW: Split", -1)
                end
                if r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_T(), false) then
                    is_interacting = true; last_interaction_time = r.time_precise()
                    r.Undo_BeginBlock()
                    local target = TrimItemToSelection()
                    if current_accessor then r.DestroyAudioAccessor(current_accessor); current_accessor = nil end
                    peak_pyr = nil
                    is_loaded = false; LoadPeaks(target)
                    r.Undo_EndBlock("RAW: Trim to selection", -1)
                end
                if r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_X(), false) then
                    is_interacting = true; last_interaction_time = r.time_precise()
                    r.Undo_BeginBlock()
                    local target = CutSelectionWithinItem(ripple_item)
                    if current_accessor then r.DestroyAudioAccessor(current_accessor); current_accessor = nil end
                    peak_pyr = nil
                    is_loaded = false; LoadPeaks(target)
                    r.Undo_EndBlock("RAW: Cut selection", -1)
                end
                if r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_J(), false) then
                    is_interacting = true; last_interaction_time = r.time_precise()
                    local target = JoinAllTouching()
                    if target then
                        if current_accessor then r.DestroyAudioAccessor(current_accessor); current_accessor = nil end
                        peak_pyr = nil
                        is_loaded = false; LoadPeaks(target)
                    end
                end
                if r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_G(), false) then
                    is_interacting = true; last_interaction_time = r.time_precise()
                    local target = GlueExecute()
                    if target then
                        if current_accessor then r.DestroyAudioAccessor(current_accessor); current_accessor = nil end
                        peak_pyr = nil
                        is_loaded = false; LoadPeaks(target)
                    end
                end
            end
        end
        
    r.ImGui_Separator(ctx)

        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(),         UI_BTN)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(),  UI_BTN_HOVER)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(),   UI_BTN_ACTIVE)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(),        UI_FRAME)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgHovered(), UI_FRAME_HOVER)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgActive(),  UI_FRAME_ACTIVE)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_CheckMark(),      UI_CHECK)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrab(),      UI_SLIDER_GRAB)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrabActive(),UI_SLIDER_ACT)
        r.ImGui_PushStyleVar(ctx,   r.ImGui_StyleVar_FrameRounding(), UI_ROUNDING)

    local settings_popup_x, settings_popup_y
    local help_popup_x, help_popup_y

    do
        local ux, uy = r.ImGui_GetCursorScreenPos(ctx)
        local ulabel = "↶"
        local utw, uth = r.ImGui_CalcTextSize(ctx, ulabel)
        r.ImGui_SetCursorScreenPos(ctx, ux, uy)
        r.ImGui_InvisibleButton(ctx, "undo_menu_btn", utw, uth)
        local uhovered = r.ImGui_IsItemHovered(ctx)
        if r.ImGui_IsItemClicked(ctx, 0) then
            is_interacting = true; last_interaction_time = r.time_precise()
            r.Undo_DoUndo2(0)
            if current_accessor then r.DestroyAudioAccessor(current_accessor); current_accessor = nil end
            peak_pyr = nil
            is_loaded = false
            LoadPeaks()
        end
        r.ImGui_SetCursorScreenPos(ctx, ux, uy)
    if uhovered then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), UI_TEXT_HOVER) end
        r.ImGui_AlignTextToFramePadding(ctx)
        r.ImGui_Text(ctx, ulabel)
        if uhovered then r.ImGui_PopStyleColor(ctx) end
        if show_tooltips and uhovered then
            r.ImGui_BeginTooltip(ctx); r.ImGui_Text(ctx, "Undo"); r.ImGui_EndTooltip(ctx)
        end
    end

    r.ImGui_SameLine(ctx, 0.0, 15.0)
    do
        local rx, ry = r.ImGui_GetCursorScreenPos(ctx)
        local rlabel = "↷"
        local rtw, rth = r.ImGui_CalcTextSize(ctx, rlabel)
        r.ImGui_SetCursorScreenPos(ctx, rx, ry)
        r.ImGui_InvisibleButton(ctx, "redo_menu_btn", rtw, rth)
        local rhovered = r.ImGui_IsItemHovered(ctx)
        if r.ImGui_IsItemClicked(ctx, 0) then
            is_interacting = true; last_interaction_time = r.time_precise()
            r.Undo_DoRedo2(0)
            if current_accessor then r.DestroyAudioAccessor(current_accessor); current_accessor = nil end
            peak_pyr = nil
            is_loaded = false
            LoadPeaks()
        end
        r.ImGui_SetCursorScreenPos(ctx, rx, ry)
    if rhovered then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), UI_TEXT_HOVER) end
        r.ImGui_AlignTextToFramePadding(ctx)
        r.ImGui_Text(ctx, rlabel)
        if rhovered then r.ImGui_PopStyleColor(ctx) end
        if show_tooltips and rhovered then
            r.ImGui_BeginTooltip(ctx); r.ImGui_Text(ctx, "Redo"); r.ImGui_EndTooltip(ctx)
        end
    end
    r.ImGui_SameLine(ctx)
    r.ImGui_Text(ctx, "|")
    r.ImGui_SameLine(ctx, 0.0, 15.0)
    
    do
        local lx, ly = r.ImGui_GetCursorScreenPos(ctx)
        local llabel = "Reload"
        local ltw, lth = r.ImGui_CalcTextSize(ctx, llabel)
        r.ImGui_SetCursorScreenPos(ctx, lx, ly)
        r.ImGui_InvisibleButton(ctx, "reload_menu_btn", ltw, lth)
        local lhovered = r.ImGui_IsItemHovered(ctx)
        if r.ImGui_IsItemClicked(ctx, 0) then
            is_loaded = false
            LoadPeaks()
        end
        r.ImGui_SetCursorScreenPos(ctx, lx, ly)
    if lhovered then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), UI_TEXT_HOVER) end
        r.ImGui_AlignTextToFramePadding(ctx)
        r.ImGui_Text(ctx, llabel)
        if lhovered then r.ImGui_PopStyleColor(ctx) end
        if show_tooltips and lhovered then
            r.ImGui_BeginTooltip(ctx); r.ImGui_Text(ctx, "Reload peaks"); r.ImGui_EndTooltip(ctx)
        end
    end

    r.ImGui_SameLine(ctx, 0.0, 15.0)
    local vx, vy = r.ImGui_GetCursorScreenPos(ctx)
    local label = "View"
        local tw, th = r.ImGui_CalcTextSize(ctx, label)
        r.ImGui_SetCursorScreenPos(ctx, vx, vy)
        r.ImGui_InvisibleButton(ctx, "view_menu_btn", tw, th)
        local vhovered = r.ImGui_IsItemHovered(ctx)
    if r.ImGui_IsItemClicked(ctx, 0) then r.ImGui_OpenPopup(ctx, "ViewMenu") end
    r.ImGui_SetNextWindowPos(ctx, vx, vy + th + 6.0, r.ImGui_Cond_Appearing())
        r.ImGui_SetCursorScreenPos(ctx, vx, vy)
    if vhovered then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), UI_TEXT_HOVER) end
        r.ImGui_AlignTextToFramePadding(ctx)
        r.ImGui_Text(ctx, label)
        if vhovered then r.ImGui_PopStyleColor(ctx) end
            if r.ImGui_BeginPopup(ctx, "ViewMenu") then
            if r.ImGui_MenuItem(ctx, "Grid", nil, show_grid, true) then show_grid = not show_grid; SaveSettings() end
            if r.ImGui_MenuItem(ctx, "Ruler", nil, show_ruler, true) then show_ruler = not show_ruler; SaveSettings() end
            if r.ImGui_MenuItem(ctx, "Edit cursor", nil, show_edit_cursor, true) then show_edit_cursor = not show_edit_cursor; SaveSettings() end
            if r.ImGui_MenuItem(ctx, "Play cursor", nil, show_play_cursor, true) then show_play_cursor = not show_play_cursor; SaveSettings() end
            if r.ImGui_MenuItem(ctx, "dB scale", nil, show_db_scale, true) then show_db_scale = not show_db_scale; SaveSettings() end
            if r.ImGui_MenuItem(ctx, "dB labels mirrored", nil, db_labels_mirrored, true) then db_labels_mirrored = not db_labels_mirrored; SaveSettings() end
            if r.ImGui_MenuItem(ctx, "Show fades", nil, show_fades, true) then show_fades = not show_fades; SaveSettings() end
            if r.ImGui_MenuItem(ctx, "Show footer", nil, show_footer, true) then show_footer = not show_footer; SaveSettings() end
            if r.ImGui_MenuItem(ctx, "Draw channels separately (stereo)", nil, draw_channels_separately, channels >= 2) then draw_channels_separately = not draw_channels_separately; view_cache_valid = false; SaveSettings() end
            if r.ImGui_MenuItem(ctx, "Show Pan overlay (take Pan)", nil, show_pan_overlay, (channels or 1) >= 1) then show_pan_overlay = not show_pan_overlay; SaveSettings() end
            if r.ImGui_MenuItem(ctx, "Show Transport overlay", nil, show_transport_overlay, true) then show_transport_overlay = not show_transport_overlay; SaveSettings() end
            r.ImGui_Separator(ctx)
            if r.ImGui_MenuItem(ctx, "Time", nil, not ruler_beats, true) then ruler_beats = false; SaveSettings() end
            if r.ImGui_MenuItem(ctx, "Beats", nil, ruler_beats, true) then ruler_beats = true; SaveSettings() end
            r.ImGui_Separator(ctx)
            if r.ImGui_MenuItem(ctx, "Spectral peaks (colorized)", nil, spectral_peaks, true) then spectral_peaks = not spectral_peaks; view_cache_valid = false; SaveSettings() end
            if spectral_peaks then
                local lbl = string.format("Lock spectral SR (deterministic): %s", spectral_lock_sr and "On" or "Off")
                if r.ImGui_MenuItem(ctx, lbl, nil, false, true) then
                    spectral_lock_sr = not spectral_lock_sr
                    view_cache_valid = false
                    SaveSettings()
                end
                r.ImGui_Text(ctx, string.format("Max ZCR (Hz): %.0f", spectral_max_zcr_hz))
                r.ImGui_PushItemWidth(ctx, 180)
                local changed, newv = r.ImGui_SliderDouble(ctx, "##maxzcr", spectral_max_zcr_hz or 8000, 1000, 16000, "%.0f")
                r.ImGui_PopItemWidth(ctx)
                if changed then spectral_max_zcr_hz = newv; view_cache_valid = false; SaveSettings() end
            end
            r.ImGui_EndPopup(ctx)
        end

    r.ImGui_SameLine(ctx, 0.0, 15.0)
    local bx, by = r.ImGui_GetCursorScreenPos(ctx)
    local blabel = "Behavior"
    local btw, bth = r.ImGui_CalcTextSize(ctx, blabel)
    r.ImGui_SetCursorScreenPos(ctx, bx, by)
    r.ImGui_InvisibleButton(ctx, "behavior_menu_btn", btw, bth)
    local bhovered = r.ImGui_IsItemHovered(ctx)
    if r.ImGui_IsItemClicked(ctx, 0) then r.ImGui_OpenPopup(ctx, "BehaviorMenu") end
    r.ImGui_SetNextWindowPos(ctx, bx, by + bth + 6.0, r.ImGui_Cond_Appearing())
    r.ImGui_SetCursorScreenPos(ctx, bx, by)
    if bhovered then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), UI_TEXT_HOVER) end
    r.ImGui_AlignTextToFramePadding(ctx)
    r.ImGui_Text(ctx, blabel)
    if bhovered then r.ImGui_PopStyleColor(ctx) end
        if r.ImGui_BeginPopup(ctx, "BehaviorMenu") then
            if r.ImGui_MenuItem(ctx, "Click sets edit cursor", nil, click_sets_edit_cursor, true) then click_sets_edit_cursor = not click_sets_edit_cursor; SaveSettings() end
            if r.ImGui_MenuItem(ctx, "Click seeks playback", nil, click_seeks_playback, true) then click_seeks_playback = not click_seeks_playback; SaveSettings() end
            if r.ImGui_MenuItem(ctx, "Snap to grid", nil, snap_click_to_grid, true) then snap_click_to_grid = not snap_click_to_grid; SaveSettings() end
            if r.ImGui_MenuItem(ctx, "Require Shift for selection", nil, require_shift_for_selection, true) then require_shift_for_selection = not require_shift_for_selection; SaveSettings() end
            r.ImGui_Separator(ctx)
            if r.ImGui_MenuItem(ctx, "Ripple cut (close gap)", nil, ripple_item, true) then ripple_item = not ripple_item; SaveSettings() end
            if r.ImGui_MenuItem(ctx, "Glue: include touching neighbors", nil, glue_include_touching, true) then glue_include_touching = not glue_include_touching; SaveSettings() end
            if r.ImGui_MenuItem(ctx, "Glue after normalize selection", nil, glue_after_normalize_sel, true) then glue_after_normalize_sel = not glue_after_normalize_sel; SaveSettings() end
            if r.ImGui_MenuItem(ctx, "Normalize: use SWS dB dialog (if available)", nil, prefer_sws_normalize, true) then prefer_sws_normalize = not prefer_sws_normalize; SaveSettings() end
            if prefer_sws_normalize then
                r.ImGui_Separator(ctx)
                r.ImGui_Text(ctx, "SWS normalize action (named cmd):")
                r.ImGui_PushItemWidth(ctx, 220)
                local changed, newtxt = r.ImGui_InputText(ctx, "##swsnormcmd", sws_norm_named_cmd or "")
                r.ImGui_PopItemWidth(ctx)
                if newtxt ~= nil then sws_norm_named_cmd = newtxt; SaveSettings() end
                r.ImGui_SameLine(ctx)
                if r.ImGui_Button(ctx, "Test") then
                    local id = (sws_norm_named_cmd and sws_norm_named_cmd ~= "") and r.NamedCommandLookup(sws_norm_named_cmd) or 0
                    if id and id > 0 then
                        r.ShowMessageBox("SWS normalize command found ("..sws_norm_named_cmd..")", "SWS", 0)
                    else
                        r.ShowMessageBox("Named command not found. Try Auto-detect or paste the exact ID from Actions list.", "SWS", 0)
                    end
                end
                r.ImGui_SameLine(ctx)
                if r.ImGui_Button(ctx, "Auto-detect") then
                    local nm = "_BR_NORMALIZE_LOUDNESS_ITEMS"
                    local id = r.NamedCommandLookup(nm)
                    if id and id > 0 then sws_norm_named_cmd = nm; SaveSettings(); r.ShowMessageBox("Detected "..nm, "SWS", 0) else r.ShowMessageBox("Command not found: "..nm, "SWS", 0) end
                end
            end
            r.ImGui_EndPopup(ctx)
        end


        r.ImGui_SameLine(ctx, 0.0, 15.0)
        do
            local sx, sy = r.ImGui_GetCursorScreenPos(ctx)
            local slabel = "Settings"
            local stw, sth = r.ImGui_CalcTextSize(ctx, slabel)
            r.ImGui_SetCursorScreenPos(ctx, sx, sy)
            r.ImGui_InvisibleButton(ctx, "settings_menu_btn", stw, sth)
            local shovered = r.ImGui_IsItemHovered(ctx)
            if r.ImGui_IsItemClicked(ctx, 0) then r.ImGui_OpenPopup(ctx, "Settings") end
            settings_popup_x, settings_popup_y = sx, sy + sth + 6.0
            r.ImGui_SetCursorScreenPos(ctx, sx, sy)
            if shovered then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), UI_TEXT_HOVER) end
            r.ImGui_AlignTextToFramePadding(ctx)
            r.ImGui_Text(ctx, slabel)
            if shovered then r.ImGui_PopStyleColor(ctx) end
        end

        r.ImGui_SameLine(ctx, 0.0, 15.0)
        do
            local hx, hy = r.ImGui_GetCursorScreenPos(ctx)
            local hlabel = "Help"
            local htw, hth = r.ImGui_CalcTextSize(ctx, hlabel)
            r.ImGui_SetCursorScreenPos(ctx, hx, hy)
            r.ImGui_InvisibleButton(ctx, "help_menu_btn", htw, hth)
            local hhovered = r.ImGui_IsItemHovered(ctx)
            if r.ImGui_IsItemClicked(ctx, 0) then r.ImGui_OpenPopup(ctx, "Help") end
            help_popup_x, help_popup_y = hx, hy + hth + 6.0
            r.ImGui_SetCursorScreenPos(ctx, hx, hy)
            if hhovered then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), UI_TEXT_HOVER) end
            r.ImGui_AlignTextToFramePadding(ctx)
            r.ImGui_Text(ctx, hlabel)
            if hhovered then r.ImGui_PopStyleColor(ctx) end
        end

        do
            local win_x, win_y = r.ImGui_GetWindowPos(ctx)
            local win_w, win_h = r.ImGui_GetWindowSize(ctx)
            local txt = "RAW"
            local tw, th = r.ImGui_CalcTextSize(ctx, txt)
            local tx = win_x + (win_w - tw) * 0.5
            local ty = by + (bth - th) * 0.5
            local dlc = r.ImGui_GetWindowDrawList(ctx)
            r.ImGui_DrawList_AddTextEx(dlc, font_big, 20, tx, ty, 0xFFFFFFFF, txt)
            local logo_spacing = 8.0 + 20.0 -- move 20px to the right
            local cy = ty + th * 0.5 + 3.0 
            local rlogo = math.max(7.0, th * 0.47)
            local cx = tx + tw + logo_spacing + rlogo
            local white = 0xFFFFFFFF
            r.ImGui_DrawList_AddCircle(dlc, cx, cy, rlogo, white, 32, 1.7)
            local steps = 48
            local half_w = rlogo * 0.80
            local amp = rlogo * 0.45
            r.ImGui_DrawList_PathClear(dlc)
            for i = 0, steps do
                local t = i / steps
                local a = -math.pi + t * (2.0 * math.pi)
                local x = cx + (t - 0.5) * 2.0 * half_w
                local y = cy - math.sin(a) * amp
                r.ImGui_DrawList_PathLineTo(dlc, x, y)
            end
            r.ImGui_DrawList_PathStroke(dlc, white, 0, 1.7)
        end

    r.ImGui_SameLine(ctx)
    local curx, cury = r.ImGui_GetCursorScreenPos(ctx)
    local avail_w2, _ = r.ImGui_GetContentRegionAvail(ctx)
    local slider_w = 100.0
    local slider_h = 12.0
    local frame_h = r.ImGui_GetFrameHeight and r.ImGui_GetFrameHeight(ctx) or slider_h
    local icon_w_top = frame_h
    local right_icons_w = (icon_w_top * 2) + 16.0
    local total_slider_w = 0.0
    if show_grid then total_slider_w = total_slider_w + slider_w end
    if show_db_scale then total_slider_w = total_slider_w + slider_w end
    local total_right = total_slider_w + right_icons_w
    local sx = curx + math.max(0.0, (avail_w2 or 0.0) - total_right)
    local baseline_y = cury

    if show_grid then
        local slider_y = baseline_y + math.max(0.0, (frame_h - slider_h) * 0.5) + 1.0
        r.ImGui_SetCursorScreenPos(ctx, sx, slider_y)
        r.ImGui_InvisibleButton(ctx, "##grid_alpha_slider", slider_w, slider_h)
        local hovered_slider = r.ImGui_IsItemHovered(ctx)
        local active_slider = r.ImGui_IsItemActive(ctx)
        local dl = r.ImGui_GetWindowDrawList(ctx)
        local x0, y0 = sx, slider_y
        local cx = x0 + 6.0
        local cy = y0 + slider_h * 0.5
        local track_w = slider_w - 12.0
        local tnorm = 0.0
        if grid_alpha and grid_alpha >= 0.05 then
            tnorm = (grid_alpha - 0.05) / (1.0 - 0.05)
            if tnorm < 0.0 then tnorm = 0.0 elseif tnorm > 1.0 then tnorm = 1.0 end
        end
        local function set_alpha_from_fraction(f)
            if f < 0.0 then f = 0.0 elseif f > 1.0 then f = 1.0 end
            local new_val = 0.05 + f * (1.0 - 0.05)
            if math.abs((new_val or 0) - (grid_alpha or 0)) > 1e-6 then
                grid_alpha = new_val
                SaveSettings()
            end
            return f
        end
        if active_slider then
            is_interacting = true; last_interaction_time = r.time_precise()
            local mx, _ = r.ImGui_GetMousePos(ctx)
            tnorm = set_alpha_from_fraction((mx - cx) / math.max(1.0, track_w))
        elseif hovered_slider and r.ImGui_IsMouseClicked(ctx, 0) then
            is_interacting = true; last_interaction_time = r.time_precise()
            local mx, _ = r.ImGui_GetMousePos(ctx)
            tnorm = set_alpha_from_fraction((mx - cx) / math.max(1.0, track_w))
        end
        local track_col = ColorWithAlpha(COLOR_GRID_BASE, 0.6)
        local knob_x = cx + tnorm * track_w
        r.ImGui_DrawList_AddLine(dl, cx, cy, cx + track_w, cy, track_col, 2.0)
        local knob_fill = 0xFFFFFFFF
        local knob_border = 0x000000AA
        r.ImGui_DrawList_AddCircleFilled(dl, knob_x, cy, 5.0, knob_fill)
        r.ImGui_DrawList_AddCircle(dl, knob_x, cy, 5.0, knob_border, 12, 1.2)
        if show_tooltips and hovered_slider then
            r.ImGui_BeginTooltip(ctx)
            r.ImGui_Text(ctx, string.format("Grid intensity: %.2f", grid_alpha or 0.0))
            r.ImGui_EndTooltip(ctx)
        end
    end

    local after_first_slider_x = sx + (show_grid and (slider_w + 8.0) or 0.0)
    if show_db_scale then
        local slider_y2 = baseline_y + math.max(0.0, (frame_h - slider_h) * 0.5) + 1.0
        r.ImGui_SetCursorScreenPos(ctx, after_first_slider_x, slider_y2)
        r.ImGui_InvisibleButton(ctx, "##db_alpha_slider", slider_w, slider_h)
        local hovered_slider2 = r.ImGui_IsItemHovered(ctx)
        local active_slider2 = r.ImGui_IsItemActive(ctx)
        local dl2 = r.ImGui_GetWindowDrawList(ctx)
        local x0b, y0b = after_first_slider_x, slider_y2
        local cxb = x0b + 6.0
        local cyb = y0b + slider_h * 0.5
        local track_wb = slider_w - 12.0
        local tnormb = 0.0
        if db_alpha and db_alpha >= 0.05 then
            tnormb = (db_alpha - 0.05) / (1.0 - 0.05)
            if tnormb < 0.0 then tnormb = 0.0 elseif tnormb > 1.0 then tnormb = 1.0 end
        end
        local function set_db_alpha_from_fraction(f)
            if f < 0.0 then f = 0.0 elseif f > 1.0 then f = 1.0 end
            local new_val = 0.05 + f * (1.0 - 0.05)
            if math.abs((new_val or 0) - (db_alpha or 0)) > 1e-6 then
                db_alpha = new_val
                SaveSettings()
            end
            return f
        end
        if active_slider2 then
            is_interacting = true; last_interaction_time = r.time_precise()
            local mx, _ = r.ImGui_GetMousePos(ctx)
            tnormb = set_db_alpha_from_fraction((mx - cxb) / math.max(1.0, track_wb))
        elseif hovered_slider2 and r.ImGui_IsMouseClicked(ctx, 0) then
            is_interacting = true; last_interaction_time = r.time_precise()
            local mx, _ = r.ImGui_GetMousePos(ctx)
            tnormb = set_db_alpha_from_fraction((mx - cxb) / math.max(1.0, track_wb))
        end
        local track_colb = ColorWithAlpha(COLOR_GRID_BASE, 0.6)
        local knob_xb = cxb + tnormb * track_wb
        r.ImGui_DrawList_AddLine(dl2, cxb, cyb, cxb + track_wb, cyb, track_colb, 2.0)
        local knob_fillb = 0xFFFFFFFF
        local knob_borderb = 0x000000AA
        r.ImGui_DrawList_AddCircleFilled(dl2, knob_xb, cyb, 5.0, knob_fillb)
        r.ImGui_DrawList_AddCircle(dl2, knob_xb, cyb, 5.0, knob_borderb, 12, 1.2)
        if show_tooltips and hovered_slider2 then
            r.ImGui_BeginTooltip(ctx)
            r.ImGui_Text(ctx, string.format("dB lines intensity: %.2f", db_alpha or 0.0))
            r.ImGui_EndTooltip(ctx)
        end
    end

        do
            local sep_label = "|"
            local close_label = "Close"
            local sep_w, sep_h = r.ImGui_CalcTextSize(ctx, sep_label)
            local cw, ch = r.ImGui_CalcTextSize(ctx, close_label)
            local sep_x = sx + (total_slider_w or 0.0) + 12.0
            local sep_y = baseline_y
        
            r.ImGui_SetCursorScreenPos(ctx, sep_x, sep_y)
            r.ImGui_AlignTextToFramePadding(ctx)
            r.ImGui_Text(ctx, sep_label)
            local cx = sep_x + sep_w + 8.0
            local cy = baseline_y
            r.ImGui_SetCursorScreenPos(ctx, cx, cy)
            r.ImGui_InvisibleButton(ctx, "close_menu_btn", cw, ch)
            local chov = r.ImGui_IsItemHovered(ctx)
            if r.ImGui_IsItemClicked(ctx, 0) then
                open = false
            end
            r.ImGui_SetCursorScreenPos(ctx, cx, cy)
            if chov then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), UI_TEXT_HOVER) end
            r.ImGui_AlignTextToFramePadding(ctx)
            r.ImGui_Text(ctx, close_label)
            if chov then r.ImGui_PopStyleColor(ctx) end
        end

        if settings_popup_x and settings_popup_y then
            r.ImGui_SetNextWindowPos(ctx, settings_popup_x, settings_popup_y, r.ImGui_Cond_Appearing())
        end
        if r.ImGui_BeginPopup(ctx, "Settings") then
            local t1, t2 = r.ImGui_Checkbox(ctx, "Show tooltips", show_tooltips)
            if t2 ~= nil then show_tooltips = t2; SaveSettings() elseif t1 ~= nil then show_tooltips = t1; SaveSettings() end
            r.ImGui_Separator(ctx)
            r.ImGui_Text(ctx, "Waveform style")
            local st1, st2 = r.ImGui_Checkbox(ctx, "Soft edges (AA-like)", waveform_soft_edges)
            if st2 ~= nil then waveform_soft_edges = st2; SaveSettings() elseif st1 ~= nil then waveform_soft_edges = st1; SaveSettings() end
            local wop1, wop2 = r.ImGui_Checkbox(ctx, "Use continuous outlines (PathStroke)", waveform_outline_paths)
            if wop2 ~= nil then waveform_outline_paths = wop2; SaveSettings() elseif wop1 ~= nil then waveform_outline_paths = wop1; SaveSettings() end
            local th_changed, th_val = r.ImGui_SliderDouble(ctx, "Centerline thickness", waveform_centerline_thickness, 0.6, 4.0, "%.2f")
            if th_val ~= nil then waveform_centerline_thickness = th_val; SaveSettings() elseif th_changed ~= nil then waveform_centerline_thickness = th_changed; SaveSettings() end
            local fa_changed, fa_val = r.ImGui_SliderDouble(ctx, "Fill alpha", waveform_fill_alpha, 0.05, 0.40, "%.2f")
            if fa_val ~= nil then waveform_fill_alpha = fa_val; SaveSettings() elseif fa_changed ~= nil then waveform_fill_alpha = fa_changed; SaveSettings() end

            r.ImGui_Separator(ctx)
            r.ImGui_Text(ctx, "Detail")
            local is_auto = (view_detail_mode == "auto")
            if r.ImGui_RadioButton(ctx, "Auto (adaptive)", is_auto) then
                view_detail_mode = "auto"
                view_cache_valid = false
                SaveSettings()
            end
            r.ImGui_SameLine(ctx)
            local is_fixed = (view_detail_mode == "fixed")
            if r.ImGui_RadioButton(ctx, "Fixed", is_fixed) then
                view_detail_mode = "fixed"
                view_cache_valid = false
                SaveSettings()
            end
            if view_detail_mode == "fixed" then
                local overs_list = {1, 2, 4, 8, 16}
                for i, ov in ipairs(overs_list) do
                    if i > 1 then r.ImGui_SameLine(ctx) end
                    local lbl = tostring(ov).."x"
                    local selected = (view_oversample == ov)
                    if r.ImGui_SmallButton(ctx, (selected and ("["..lbl.."]") or lbl)) then
                        if view_oversample ~= ov then
                            view_oversample = ov
                            view_cache_valid = false
                            SaveSettings()
                        end
                    end
                end
            end
            r.ImGui_EndPopup(ctx)
        end

        if help_popup_x and help_popup_y then
            r.ImGui_SetNextWindowPos(ctx, help_popup_x, help_popup_y, r.ImGui_Cond_Appearing())
        end
        if r.ImGui_BeginPopup(ctx, "Help") then
            if r.ImGui_BeginTabBar(ctx, "HelpTabs") then
                if r.ImGui_BeginTabItem(ctx, "Basics") then
                    r.ImGui_Text(ctx, "Navigation & Zoom")
                    r.ImGui_Separator(ctx)
                    r.ImGui_Text(ctx, "- Mouse wheel: horizontal zoom around cursor")
                    r.ImGui_Text(ctx, "- Shift + wheel: pan horizontally")
                    r.ImGui_Text(ctx, "- Ctrl + wheel: vertical (amplitude) zoom")
                    r.ImGui_Text(ctx, "- Middle-drag: pan")
                    r.ImGui_Text(ctx, "- Click Zoom readout to reset (Zoom: ...x)")
                    r.ImGui_NewLine(ctx)
                    r.ImGui_Text(ctx, "Click & Cursors")
                    r.ImGui_Separator(ctx)
                    r.ImGui_Text(ctx, "- Click: set edit cursor (and seek if 'Click seeks' is enabled)")
                    r.ImGui_Text(ctx, "- Ctrl + click: set only edit cursor")
                    r.ImGui_Text(ctx, "- Shift + click: move nearest time selection edge")
                    r.ImGui_Text(ctx, "- Alt during click/drag: no snap (also for envelope points)")
                    r.ImGui_EndTabItem(ctx)
                end

                if r.ImGui_BeginTabItem(ctx, "Selection") then
                    r.ImGui_Text(ctx, "Create & Adjust Selection")
                    r.ImGui_Separator(ctx)
                    r.ImGui_Text(ctx, "- Shift + drag: create/adjust selection (snaps to grid unless Alt)")
                    r.ImGui_Text(ctx, "- Alt while dragging: temporarily disable snap")
                    r.ImGui_Text(ctx, "- Double-click: clear selection and REAPER time selection")
                    r.ImGui_Text(ctx, "- If 'Require Shift for selection' is enabled, dragging without Shift won't select")
                    r.ImGui_EndTabItem(ctx)
                end

                if r.ImGui_BeginTabItem(ctx, "Editing") then
                    r.ImGui_Text(ctx, "Core Editing")
                    r.ImGui_Separator(ctx)
                    r.ImGui_Text(ctx, "- Split (S): split at selection edges; if no selection, split at edit cursor")
                    r.ImGui_Text(ctx, "- Trim (T): trim current item to selection")
                    r.ImGui_Text(ctx, "- Cut (X): remove selection; ripple/close gap if enabled in Behavior → Ripple cut")
                    r.ImGui_Text(ctx, "- Fit (I/F): I = fit to item, F = fit to selection")
                    r.ImGui_Text(ctx, "- Buttons mirror the same actions: Fit item / Fit selection / Split / Trim / Cut / Join / Glue")
                    r.ImGui_NewLine(ctx)
                    r.ImGui_Text(ctx, "Draw preview (RMB)")
                    r.ImGui_Separator(ctx)
                    r.ImGui_Text(ctx, "- Right-drag inside waveform to draw a preview line (UI only)")
                    r.ImGui_Text(ctx, "- Release RMB to keep it briefly; it fades after a moment")
                    r.ImGui_Text(ctx, "- Right double-click to clear the preview")
                    r.ImGui_EndTabItem(ctx)
                end

                if r.ImGui_BeginTabItem(ctx, "UI & Settings") then
                    r.ImGui_Text(ctx, "Menus & Controls")
                    r.ImGui_Separator(ctx)
                    r.ImGui_Text(ctx, "- View menu: Grid / Ruler / Cursors (Edit, Play) / Time vs Beats ruler")
                    r.ImGui_Text(ctx, "- Behavior menu: Click sets edit cursor / Click seeks / Snap to grid / Require Shift for selection / Ripple cut / Glue include-touching")
                    r.ImGui_Text(ctx, "- Right side: Envelopes and Pencil tools (mutually exclusive); right-click for tool menus")
                    r.ImGui_Text(ctx, "  • Envelopes menu includes 'Show volume points (experimental)'")
                    r.ImGui_Text(ctx, "- Right side also has a thin grid intensity slider and dB intensity slider (when enabled)")
                    r.ImGui_Text(ctx, "- Settings (gear): tooltips on/off, waveform soft edges, centerline thickness, fill alpha")
                    r.ImGui_Text(ctx, "  Detail: Auto vs Fixed; when Fixed, choose oversampling 1x/2x/4x/8x/16x")
                    r.ImGui_Text(ctx, "- HUD: shows active tool in the top-right of the canvas")
                    r.ImGui_Text(ctx, "- Envelope lanes visibility is managed by the tool (no need to toggle in View)")
                    r.ImGui_Text(ctx, "- L/R gutter labels only show in stereo split view (hidden in single view)")
                    r.ImGui_Text(ctx, "- Snapping respects project grid and time signatures; hold Alt for no snap")
                    r.ImGui_Text(ctx, "- Settings and toggles persist between sessions (ExtState)")
                    r.ImGui_Text(ctx, "- Right sidebar is slightly wider for readability")
                    r.ImGui_Text(ctx, "- Help (i): opens this help")
                    r.ImGui_EndTabItem(ctx)
                end

                if r.ImGui_BeginTabItem(ctx, "Shortcuts") then
                    r.ImGui_Text(ctx, "Keyboard")
                    r.ImGui_Separator(ctx)
                    r.ImGui_Text(ctx, "- I: Fit to item")
                    r.ImGui_Text(ctx, "- F: Fit to selection")
                    r.ImGui_Text(ctx, "- S: Split (at selection edges, else at edit cursor)")
                    r.ImGui_Text(ctx, "- T: Trim item to selection")
                    r.ImGui_Text(ctx, "- X: Cut selection (ripple if enabled)")
                    r.ImGui_Text(ctx, "- J: Join (heal) touching splits of same source around current item")
                    r.ImGui_Text(ctx, "- G: Glue selected (option: include touching neighbors)")
                    r.ImGui_Text(ctx, "- Delete/Backspace: delete selected volume envelope points (when shown)")
                    r.ImGui_NewLine(ctx)
                    r.ImGui_Text(ctx, "Mouse")
                    r.ImGui_Separator(ctx)
                    r.ImGui_Text(ctx, "- Wheel: horizontal zoom around cursor")
                    r.ImGui_Text(ctx, "- Shift + wheel: pan horizontally")
                    r.ImGui_Text(ctx, "- Ctrl + wheel: vertical (amplitude) zoom")
                    r.ImGui_Text(ctx, "- Middle-drag: pan")
                    r.ImGui_Text(ctx, "- Shift + drag: create/adjust selection; Alt disables snap")
                    r.ImGui_Text(ctx, "- Envelope points (experimental):")
                    r.ImGui_Text(ctx, "  • Click line to add; drag point to move (snaps to grid)")
                    r.ImGui_Text(ctx, "  • Alt while dragging: temporarily disable snap")
                    r.ImGui_Text(ctx, "  • Ctrl+Alt on selection release: bulk delete selected points")
                    r.ImGui_EndTabItem(ctx)
                end

                if r.ImGui_BeginTabItem(ctx, "Envelopes & Overlays") then
                    r.ImGui_Text(ctx, "Tools & Targets")
                    r.ImGui_Separator(ctx)
                    r.ImGui_Text(ctx, "- Envelopes and Pencil are mutually exclusive; enabling one disables the other")
                    r.ImGui_Text(ctx, "- Targets: Item Volume and Pan (take pan). The script ensures the take envelope exists,")
                    r.ImGui_Text(ctx, "  is active/armed, and visible in the arrange when Envelopes is enabled")
                    r.ImGui_NewLine(ctx)
                    r.ImGui_Text(ctx, "Overlays")
                    r.ImGui_Separator(ctx)
                    r.ImGui_Text(ctx, "- Volume overlay: green, dB-scaled with 0 dB baseline")
                    r.ImGui_Text(ctx, "- Pan overlay: purple, shows pan from L (-1) to R (+1) normalized across the lane")
                    r.ImGui_NewLine(ctx)
                    r.ImGui_Text(ctx, "Volume points (experimental)")
                    r.ImGui_Separator(ctx)
                    r.ImGui_Text(ctx, "- Toggle via Envelopes menu: 'Show volume points (experimental)'")
                    r.ImGui_Text(ctx, "- Hover highlights points; click to select; drag to move (grid-snapped; Alt = no snap)")
                    r.ImGui_Text(ctx, "- Click on the line to add a point; Delete/Backspace removes selected")
                    r.ImGui_Text(ctx, "- Undo is grouped; operations respect current selection")
                    r.ImGui_Text(ctx, "- Note: Pan points editing is not yet available")
                    r.ImGui_EndTabItem(ctx)
                end

                if r.ImGui_BeginTabItem(ctx, "Game") then
                    r.ImGui_Text(ctx, "Mini-game options")
                    r.ImGui_Separator(ctx)
                    r.ImGui_Text(ctx, "- Right-click the Game button to open the game menu")
                    r.ImGui_Text(ctx, "- 'Starfield background': toggles a black sky with white stars (persists)")
                    r.ImGui_Text(ctx, "- The starfield is cached and adapts to the viewport size")
                    r.ImGui_EndTabItem(ctx)
                end

                r.ImGui_EndTabBar(ctx)
            end
            r.ImGui_EndPopup(ctx)
        end

        r.ImGui_PopStyleVar(ctx, 1)
        r.ImGui_PopStyleColor(ctx, 9)
        r.ImGui_Dummy(ctx, 0.0, 2.0)
        r.ImGui_Separator(ctx)
        
        
    local draw_list = r.ImGui_GetWindowDrawList(ctx)
    local canvas_x, canvas_y = r.ImGui_GetCursorScreenPos(ctx)
    local avail_w, avail_h = r.ImGui_GetContentRegionAvail(ctx)
    if show_footer then
        avail_h = math.max(avail_h - 20, 100)
    else
        avail_h = math.max(avail_h, 100)
    end
    local ruler_h = show_ruler and 22 or 0
    local wave_y = canvas_y + ruler_h
    local wave_h = math.max(1, avail_h - ruler_h)
    if not vol_dragging then vol_y_draw = nil end

    local sidebar_w_full = 130.0
    local sidebar_w_collapsed = 18.0
    local side_gap = 8.0
    local sidebar_w = sidebar_collapsed and sidebar_w_collapsed or sidebar_w_full
    local wave_w = math.max(50.0, (avail_w - sidebar_w - side_gap) - LEFT_GUTTER_W)
    local content_x = canvas_x + LEFT_GUTTER_W

    local over_dc_panel = false
    local over_pan_panel = false
    if pencil_mode and pencil_target == "dc_offset" then
    local panel_w, panel_h = 180.0, 56.0
        local pad = 10.0
        local px = content_x + pad
    local stack_gap = 6.0
    local transport_h = (show_transport_overlay and 42.0) or 0.0
    local py = wave_y + wave_h - panel_h - pad - transport_h - (show_transport_overlay and stack_gap or 0.0)
    local dlp = (r.ImGui_GetForegroundDrawList and r.ImGui_GetForegroundDrawList(ctx)) or r.ImGui_GetWindowDrawList(ctx)
    local bg_col = 0x000000AA
    r.ImGui_DrawList_AddRectFilled(dlp, px, py, px + panel_w, py + panel_h, bg_col, 6.0)
    r.ImGui_DrawList_AddRect(dlp, px, py, px + panel_w, py + panel_h, 0xFFFFFFFF, 6.0, 0, 1.0)
        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), 8.0, 6.0)
        r.ImGui_SetCursorScreenPos(ctx, px + 8.0, py + 6.0)
        r.ImGui_BeginGroup(ctx)
        do
            local label = "Pixel density"
            local header_col = 0xFFD24DFF
            r.ImGui_DrawList_AddTextEx(dlp, font_big, 16, px + 8.0, py + 6.0, header_col, label)
            local val = string.format("%.1f px", (draw_min_px_step or 2.0))
            local vtw, _ = r.ImGui_CalcTextSize(ctx, val)
            r.ImGui_DrawList_AddText(dlp, px + panel_w - 8.0 - vtw, py + 6.0, 0xFFFFFFFF, val)
        end
        

        local track_w = panel_w - 16.0
        local slider_y = py + (panel_h * 0.5) - 8.0
        r.ImGui_SetCursorScreenPos(ctx, px + 8.0, slider_y)
        local sx, sy = r.ImGui_GetCursorScreenPos(ctx)
        r.ImGui_InvisibleButton(ctx, "##dc_density_slider", track_w, 16.0)
        local hovered_slider = r.ImGui_IsItemHovered(ctx)
        local active_slider = r.ImGui_IsItemActive(ctx)
        local cx = sx
        local cy = slider_y + 8.0
    local tmin, tmax = 0.1, 12.0
        local v = math.max(tmin, math.min(tmax, (draw_min_px_step or 2.0)))
        local frac = (v - tmin) / (tmax - tmin)
        local knob_x = cx + frac * track_w
      
    r.ImGui_DrawList_AddLine(dlp, cx, cy, cx + track_w, cy, 0xFFFFFF66, 1.2)
    r.ImGui_DrawList_AddCircleFilled(dlp, knob_x, cy, 5.0, 0xFFD24DFF)
    r.ImGui_DrawList_AddCircle(dlp, knob_x, cy, 5.0, 0xFFFFFFFF, 12, 1.0)
        
        if active_slider or (hovered_slider and r.ImGui_IsMouseClicked(ctx, 0)) then
            is_interacting = true; last_interaction_time = r.time_precise()
            local mx = select(1, r.ImGui_GetMousePos(ctx))
            local f = (mx - cx) / math.max(1.0, track_w)
            if f < 0 then f = 0 elseif f > 1 then f = 1 end
            local nv = tmin + f * (tmax - tmin)
            if math.abs(nv - (draw_min_px_step or 2.0)) > 1e-6 then
                draw_min_px_step = nv
                SaveSettings()
            end
        end
        r.ImGui_EndGroup(ctx)
        r.ImGui_PopStyleVar(ctx, 1)
  
        local mx, my = r.ImGui_GetMousePos(ctx)
        over_dc_panel = (mx >= px and mx <= px + panel_w and my >= py and my <= py + panel_h)
    end

    if show_pan_overlay and current_item and current_take and (view_len or 0) > 0 then
        local panel_w, panel_h = 200.0, 56.0
        local pad = 10.0
        local px = content_x + pad
        local py = wave_y + pad
        local dlp = (r.ImGui_GetForegroundDrawList and r.ImGui_GetForegroundDrawList(ctx)) or r.ImGui_GetWindowDrawList(ctx)
        local bg_col = 0x000000AA
        r.ImGui_DrawList_AddRectFilled(dlp, px, py, px + panel_w, py + panel_h, bg_col, 6.0)
        r.ImGui_DrawList_AddRect(dlp, px, py, px + panel_w, py + panel_h, 0xFFFFFFFF, 6.0, 0, 1.0)
        local label = "Pan"
        r.ImGui_DrawList_AddTextEx(dlp, font_big, 16, px + 8.0, py + 6.0, 0xFFD24DFF, label)
        local cur_pan = r.GetMediaItemTakeInfo_Value(current_take, 'D_PAN') or 0.0
        local val_txt = (cur_pan < -0.001 and string.format("L %.0f%%", math.abs(cur_pan) * 100))
                      or (cur_pan > 0.001 and string.format("R %.0f%%", math.abs(cur_pan) * 100))
                      or "C"
        local vtw, _ = r.ImGui_CalcTextSize(ctx, val_txt)
        r.ImGui_DrawList_AddText(dlp, px + panel_w - 8.0 - vtw, py + 6.0, 0xFFFFFFFF, val_txt)

        local track_w = panel_w - 16.0
        local slider_y = py + (panel_h * 0.5) - 8.0
        r.ImGui_SetCursorScreenPos(ctx, px + 8.0, slider_y)
        local sx, sy = r.ImGui_GetCursorScreenPos(ctx)
        r.ImGui_InvisibleButton(ctx, '##pan_slider', track_w, 16.0)
        local hovered_slider = r.ImGui_IsItemHovered(ctx)
        local active_slider = r.ImGui_IsItemActive(ctx)
        local cx = sx
        local cy = slider_y + 8.0
        local frac = (cur_pan + 1.0) * 0.5
        local knob_x = cx + frac * track_w
        r.ImGui_DrawList_AddLine(dlp, cx, cy, cx + track_w, cy, 0xFFFFFF66, 1.2)
        r.ImGui_DrawList_AddCircleFilled(dlp, knob_x, cy, 5.0, 0xFFD24DFF)
        r.ImGui_DrawList_AddCircle(dlp, knob_x, cy, 5.0, 0xFFFFFFFF, 12, 1.0)

        local mx, my = r.ImGui_GetMousePos(ctx)
        over_pan_panel = (mx >= px and mx <= px + panel_w and my >= py and my <= py + panel_h)

        if (active_slider or (hovered_slider and r.ImGui_IsMouseClicked(ctx, 0))) then
            is_interacting = true; last_interaction_time = r.time_precise()
            if not pan_undo_open then r.Undo_BeginBlock(); pan_undo_open = true end
            local f = (mx - cx) / math.max(1.0, track_w)
            if f < 0 then f = 0 elseif f > 1 then f = 1 end
            local new_pan = (f * 2.0) - 1.0
            r.SetMediaItemTakeInfo_Value(current_take, 'D_PAN', new_pan)
            r.UpdateItemInProject(current_item)
        end
        if hovered_slider and r.ImGui_IsMouseDoubleClicked and r.ImGui_IsMouseDoubleClicked(ctx, 0) then
            if not pan_undo_open then r.Undo_BeginBlock(); pan_undo_open = true end
            r.SetMediaItemTakeInfo_Value(current_take, 'D_PAN', 0.0)
            r.UpdateItemInProject(current_item)
        end
        if hovered_slider and r.ImGui_IsMouseClicked(ctx, 1) then
            is_interacting = true; last_interaction_time = r.time_precise()
            if not pan_undo_open then r.Undo_BeginBlock(); pan_undo_open = true end
            r.SetMediaItemTakeInfo_Value(current_take, 'D_PAN', 0.0)
            r.UpdateItemInProject(current_item)
        end
        do
            local tx = px + 8.0
            local ty = py + panel_h - 18.0
            local icon_r = 5.0
            local spacing = 12.0
            do
                local label = "Color"
                local tw, th = r.ImGui_CalcTextSize(ctx, label)
                local h = math.max(th, icon_r * 2 + 2)
                local w = icon_r * 2 + 6 + tw
                r.ImGui_SetCursorScreenPos(ctx, tx, ty)
                r.ImGui_InvisibleButton(ctx, "##pan_color_toggle", w, h)
                local hovered = r.ImGui_IsItemHovered(ctx)
                if r.ImGui_IsItemClicked(ctx, 0) then pan_color_overlay = not pan_color_overlay; SaveSettings() end
                local cx = tx + icon_r
                local cy = ty + h * 0.5
                local ring = hovered and 0xFFFFFFFF or 0xDDDDDDFF
                r.ImGui_DrawList_AddCircle(dlp, cx, cy, icon_r, ring, 20, 1.4)
                if pan_color_overlay then r.ImGui_DrawList_AddCircleFilled(dlp, cx, cy, icon_r - 2.0, 0xFFD24DFF) end
                r.ImGui_DrawList_AddText(dlp, tx + icon_r * 2 + 6, ty + (h - th) * 0.5, 0xFFFFFFFF, label)
                tx = tx + w + spacing
            end
            do
                local label = "Visual"
                local tw, th = r.ImGui_CalcTextSize(ctx, label)
                local h = math.max(th, icon_r * 2 + 2)
                local w = icon_r * 2 + 6 + tw
                r.ImGui_SetCursorScreenPos(ctx, tx, ty)
                r.ImGui_InvisibleButton(ctx, "##pan_visual_toggle", w, h)
                local hovered = r.ImGui_IsItemHovered(ctx)
                if r.ImGui_IsItemClicked(ctx, 0) then pan_visual_waveform = not pan_visual_waveform; SaveSettings() end
                local cx = tx + icon_r
                local cy = ty + h * 0.5
                local ring = hovered and 0xFFFFFFFF or 0xDDDDDDFF
                r.ImGui_DrawList_AddCircle(dlp, cx, cy, icon_r, ring, 20, 1.4)
                if pan_visual_waveform then r.ImGui_DrawList_AddCircleFilled(dlp, cx, cy, icon_r - 2.0, 0xFFD24DFF) end
                r.ImGui_DrawList_AddText(dlp, tx + icon_r * 2 + 6, ty + (h - th) * 0.5, 0xFFFFFFFF, label)
            end
        end

        if pan_undo_open and not r.ImGui_IsMouseDown(ctx, 0) then
            r.Undo_EndBlock('RAW: Adjust pan', -1)
            pan_undo_open = false
        end
    end

    if show_transport_overlay then
    local panel_w, panel_h = 340.0, 42.0
        local pad = 10.0
        local px = content_x + 10.0
    local py = wave_y + wave_h - panel_h - pad
        local dlp = (r.ImGui_GetForegroundDrawList and r.ImGui_GetForegroundDrawList(ctx)) or r.ImGui_GetWindowDrawList(ctx)
        r.ImGui_DrawList_AddRectFilled(dlp, px, py, px + panel_w, py + panel_h, 0x000000AA, 6.0)
        r.ImGui_DrawList_AddRect(dlp, px, py, px + panel_w, py + panel_h, 0xFFFFFFFF, 6.0, 0, 1.0)

    local btn_h = 20.0
    local btn_w = 26.0
    local gap = 6.0
    local tx = px + 8.0
    local ty = py + 11.0
        r.ImGui_SetCursorScreenPos(ctx, tx, ty)
        local function DrawTransButton(id, label, tooltip)
            local tw, th = r.ImGui_CalcTextSize(ctx, label)
            local w = btn_w
            r.ImGui_InvisibleButton(ctx, id, w, btn_h)
            local hov = r.ImGui_IsItemHovered(ctx)
            local minx, miny = r.ImGui_GetItemRectMin(ctx)
            local maxx, maxy = r.ImGui_GetItemRectMax(ctx)
            local bg = hov and 0x343434FF or 0x2A2A2AFF
            r.ImGui_DrawList_AddRectFilled(dlp, minx, miny, maxx, maxy, bg, 4.0)
            r.ImGui_DrawList_AddRect(dlp, minx, miny, maxx, maxy, 0x333333FF, 4.0, 0, 1.0)
            local lx = minx + (w - tw) * 0.5
            local ly = miny + (btn_h - th) * 0.5
            r.ImGui_DrawList_AddText(dlp, lx, ly, 0xFFFFFFFF, label)
            if tooltip and hov and show_tooltips then r.ImGui_BeginTooltip(ctx); r.ImGui_Text(ctx, tooltip); r.ImGui_EndTooltip(ctx) end
            return r.ImGui_IsItemClicked(ctx, 0), w
        end

        local clicked, w
    r.ImGui_SetCursorScreenPos(ctx, tx, ty); clicked, w = DrawTransButton("##proj_start", "⏮", "Go to start of project")
    if clicked then r.Main_OnCommand(40042, 0) end 
        tx = tx + w + gap
        r.ImGui_SetCursorScreenPos(ctx, tx, ty); clicked, w = DrawTransButton("##stop", "■", "Stop")
        if clicked then r.Main_OnCommand(1016, 0) end 
        tx = tx + w + gap
        local ps = r.GetPlayState() or 0
        local is_paused = (ps & 2) ~= 0
        local is_play = (ps & 1) ~= 0
        local label_pp = (is_play and not is_paused) and "⏸" or "▶"
        r.ImGui_SetCursorScreenPos(ctx, tx, ty); clicked, w = DrawTransButton("##play", label_pp, "Play/Pause")
        if clicked then
            if is_play then
                r.Main_OnCommand(1008, 0) 
            else
                if transport_item_only and current_item then
                    RunCommandOnItemWithTemporarySelection(current_item, 1007) -- Play
                else
                    r.Main_OnCommand(1007, 0)
                end
            end
        end
    tx = tx + w + gap
        r.ImGui_SetCursorScreenPos(ctx, tx, ty); clicked, w = DrawTransButton("##proj_end", "⏭", "Go to end of project")
        if clicked then r.Main_OnCommand(40043, 0) end 
        tx = tx + w + gap

        r.ImGui_SetCursorScreenPos(ctx, tx, ty); clicked, w = DrawTransButton("##ts_start", "<<", "Go to start of time selection")
        if clicked then r.Main_OnCommand(40630, 0) end 
        tx = tx + w + gap
        r.ImGui_SetCursorScreenPos(ctx, tx, ty); clicked, w = DrawTransButton("##ts_end", ">>", "Go to end of time selection")
        if clicked then r.Main_OnCommand(40631, 0) end 
        tx = tx + w + gap

    local loop_on = (r.GetSetRepeat(-1) == 1)
    local loop_label = loop_on and "⟳" or "⤿"
    r.ImGui_SetCursorScreenPos(ctx, tx, ty)
    do
        local tw, th = r.ImGui_CalcTextSize(ctx, loop_label)
        local wtmp = btn_w
        r.ImGui_InvisibleButton(ctx, "##loop", wtmp, btn_h)
        local hov = r.ImGui_IsItemHovered(ctx)
        local minx, miny = r.ImGui_GetItemRectMin(ctx)
        local maxx, maxy = r.ImGui_GetItemRectMax(ctx)
        local base = 0x2A2A2AFF
        local hovc = 0x343434FF
        local wave_green = 0x66FF66FF
        local fill = loop_on and wave_green or (hov and hovc or base)
        r.ImGui_DrawList_AddRectFilled(dlp, minx, miny, maxx, maxy, fill, 4.0)
        r.ImGui_DrawList_AddRect(dlp, minx, miny, maxx, maxy, 0x333333FF, 4.0, 0, 1.0)
        local lx = minx + (wtmp - tw) * 0.5
        local ly = miny + (btn_h - th) * 0.5
        r.ImGui_DrawList_AddText(dlp, lx, ly, 0xFFFFFFFF, loop_label)
        if r.ImGui_IsItemClicked(ctx, 0) then r.GetSetRepeat(loop_on and 0 or 1) end
        clicked, w = false, wtmp
    end
    tx = tx + w + gap

        local take = current_take
        local item = current_item
        local track = item and r.GetMediaItem_Track(item) or nil
        local cur_mute = item and (r.GetMediaItemInfo_Value(item, "B_MUTE") or 0) > 0.5
        local cur_solo = track and ((r.GetMediaTrackInfo_Value(track, "I_SOLO") or 0) > 0.5) or false
        local function DrawToggle(id, txt, is_active, active_col)
            local tw, th = r.ImGui_CalcTextSize(ctx, txt)
            local w = math.max(22.0, tw + 10.0)
            r.ImGui_InvisibleButton(ctx, id, w, btn_h)
            local hov = r.ImGui_IsItemHovered(ctx)
            local minx, miny = r.ImGui_GetItemRectMin(ctx)
            local maxx, maxy = r.ImGui_GetItemRectMax(ctx)
            local base = 0x2A2A2AFF
            local hovc = 0x343434FF
            local fill = is_active and (active_col or base) or (hov and hovc or base)
            r.ImGui_DrawList_AddRectFilled(dlp, minx, miny, maxx, maxy, fill, 4.0)
            r.ImGui_DrawList_AddRect(dlp, minx, miny, maxx, maxy, 0x333333FF, 4.0, 0, 1.0)
            local lx = minx + (w - tw) * 0.5
            local ly = miny + (btn_h - th) * 0.5
            r.ImGui_DrawList_AddText(dlp, lx, ly, 0xFFFFFFFF, txt)
            return r.ImGui_IsItemClicked(ctx, 0), w
        end
        r.ImGui_SetCursorScreenPos(ctx, tx, ty); clicked, w = DrawToggle("##mute", "M", cur_mute, 0x80CFFFEE)
        if clicked and item then
            local v = cur_mute and 0 or 1
            r.Undo_BeginBlock(); r.SetMediaItemInfo_Value(item, "B_MUTE", v); r.UpdateItemInProject(item); r.Undo_EndBlock("RAW: Toggle mute", -1)
        end
        tx = tx + w + gap
        r.ImGui_SetCursorScreenPos(ctx, tx, ty); clicked, w = DrawToggle("##solo", "S", cur_solo, 0xFF4DAAFF)
        if clicked and track then
            r.Undo_BeginBlock()
            local v = cur_solo and 0 or 1
            r.SetMediaTrackInfo_Value(track, "I_SOLO", v)
            r.TrackList_AdjustWindows(false)
            r.UpdateArrange()
            r.Undo_EndBlock("RAW: Toggle track solo", -1)
        end
        tx = tx + w + gap

    local label = "item"
    local rtw, rth = r.ImGui_CalcTextSize(ctx, label)
    local rw = 16.0 + 6.0 + rtw
    r.ImGui_SetCursorScreenPos(ctx, tx, ty)
    r.ImGui_InvisibleButton(ctx, "##radio_item", rw, btn_h)
    local rhovered = r.ImGui_IsItemHovered(ctx)
    local minx, miny = r.ImGui_GetItemRectMin(ctx)
    local cx = minx + 8.0
    local cy = miny + btn_h * 0.5
    local ring = rhovered and 0xFFFFFFFF or 0xDDDDDDFF
    r.ImGui_DrawList_AddCircle(dlp, cx, cy, 7.0, ring, 20, 1.4)
    if transport_item_only then r.ImGui_DrawList_AddCircleFilled(dlp, cx, cy, 5.0, 0xFFD24DFF) end
    r.ImGui_DrawList_AddText(dlp, minx + 16.0 + 6.0, miny + (btn_h - rth) * 0.5, 0xFFFFFFFF, label)
        if r.ImGui_IsItemClicked(ctx, 0) then
            transport_item_only = not transport_item_only
            SaveSettings()
            if transport_item_only then
                ts_user_override = HasNonEmptyTimeSelection()
                ApplyItemTimeSelection(false)
            else
                if not ts_user_override then
                    r.GetSet_LoopTimeRange(true, false, 0, 0, false)
                end
            end
            r.UpdateArrange()
        end
    end

    r.ImGui_SetCursorScreenPos(ctx, content_x, canvas_y)
    r.ImGui_InvisibleButton(ctx, "waveform_canvas", wave_w, avail_h)
    local hovered = r.ImGui_IsItemHovered(ctx)
    local mouse_down = r.ImGui_IsMouseDown(ctx, 0)
    local mouse_clicked = r.ImGui_IsMouseClicked(ctx, 0)
    local mouse_released = r.ImGui_IsMouseReleased(ctx, 0)
    
        local mmb_clicked = r.ImGui_IsMouseClicked(ctx, 2)
        local mmb_down = r.ImGui_IsMouseDown(ctx, 2)
    local rmb_clicked = r.ImGui_IsMouseClicked(ctx, 1)
    local rmb_down = r.ImGui_IsMouseDown(ctx, 1)
    local rmb_released = r.ImGui_IsMouseReleased(ctx, 1)
    local draw_mode_allowed = pencil_mode or (show_env_overlay and (pencil_target == "item_vol" or pencil_target == "item_pan"))
        local wheel = r.ImGui_GetMouseWheel(ctx) or 0
    local mods = r.ImGui_GetKeyMods and r.ImGui_GetKeyMods(ctx) or 0
    local hasAlt   = r.ImGui_Mod_Alt   and ((mods & r.ImGui_Mod_Alt())   ~= 0) or false
    local hasShift = r.ImGui_Mod_Shift and ((mods & r.ImGui_Mod_Shift()) ~= 0) or false
    local hasCtrl  = r.ImGui_Mod_Ctrl  and ((mods & r.ImGui_Mod_Ctrl())  ~= 0) or false

    local item_px_start, item_px_end = nil, nil
        local handle_hover = nil -- 'in' | 'out' | nil
    if show_fades and current_item and current_item_len > 0 and view_len > 0 then
            local vt0 = view_start
            local vt1 = view_start + view_len
            item_px_start = content_x + ((current_item_start - vt0) / (vt1 - vt0)) * wave_w
            item_px_end   = content_x + (((current_item_start + current_item_len) - vt0) / (vt1 - vt0)) * wave_w
            if item_px_end > content_x and item_px_start < (content_x + wave_w) then
                if hovered then
                    local mx, my = r.ImGui_GetMousePos(ctx)
                    local handle_r = FADE_HANDLE_RADIUS + FADE_HANDLE_HOVER_PAD
                    local amp = r.GetMediaItemInfo_Value(current_item, 'D_VOL') or 1.0
                    local db  = amp_to_db(amp)
                    local vol_y = vol_db_to_y(db, wave_y, wave_y + wave_h)
                    local fin  = r.GetMediaItemInfo_Value(current_item, 'D_FADEINLEN') or 0.0
                    local fout = r.GetMediaItemInfo_Value(current_item, 'D_FADEOUTLEN') or 0.0
                    local fin_x = (fin > 0) and (item_px_start + (fin / math.max(1e-12, view_len)) * wave_w) or item_px_start
                    local fout_x = (fout > 0) and (item_px_end   - (fout / math.max(1e-12, view_len)) * wave_w) or item_px_end
                    local function within_handle(xc)
                        local dx = math.abs(mx - xc)
                        local dy = math.abs(my - vol_y)
                        return (dx <= handle_r and dy <= handle_r)
                    end
                    if within_handle(fin_x) then handle_hover = 'in' end
                    if within_handle(fout_x) then handle_hover = 'out' end
                end
            end
        end

    if hovered and current_item and current_item_len > 0 and wheel ~= 0 then
            is_interacting = true; last_interaction_time = r.time_precise()
            local mx, _ = r.ImGui_GetMousePos(ctx)
            local relx = (mx - content_x) / math.max(1, wave_w)
            relx = math.max(0.0, math.min(1.0, relx))
            local vt0 = view_start
            local vt1 = view_start + view_len
            local mt = vt0 + relx * (vt1 - vt0)
            local factor = (1.15 ^ wheel)
            if hasCtrl then
                amp_zoom = math.max(0.1, math.min(10.0, amp_zoom * factor))
                SaveSettings()
            elseif hasShift then
                local delta = -(wheel) * view_len * 0.15
                view_start = view_start + delta
                local min_start = current_item_start
                local max_start = current_item_start + current_item_len - view_len
                if max_start < min_start then max_start = min_start end
                if view_start < min_start then view_start = min_start end
                if view_start > max_start then view_start = max_start end
            else
                local new_len = view_len / factor
                local min_len = math.max(0.001, current_item_len / 10000)
                if new_len < min_len then new_len = min_len end
                if new_len > current_item_len then new_len = current_item_len end
                local rel = (mt - view_start) / view_len
                view_start = mt - rel * new_len
                local min_start = current_item_start
                local max_start = current_item_start + current_item_len - new_len
                if max_start < min_start then max_start = min_start end
                if view_start < min_start then view_start = min_start end
                if view_start > max_start then view_start = max_start end
                view_len = new_len
            end
        end

    if hovered and mmb_clicked then
            is_interacting = true; last_interaction_time = r.time_precise()
            panning = true
            pan_start_x = select(1, r.ImGui_GetMousePos(ctx))
            pan_start_view = view_start
        end
        if panning and mmb_down then
            is_interacting = true; last_interaction_time = r.time_precise()
            local mx = select(1, r.ImGui_GetMousePos(ctx))
            local dx = mx - (pan_start_x or mx)
            local dt = (dx / math.max(1, wave_w)) * view_len
            view_start = pan_start_view - dt
            local min_start = current_item_start
            local max_start = current_item_start + current_item_len - view_len
            if max_start < min_start then max_start = min_start end
            if view_start < min_start then view_start = min_start end
            if view_start > max_start then view_start = max_start end
        end
    if panning and not mmb_down then
            panning = false
            pan_start_x = nil
            pan_start_view = nil
        end

    if hovered and (not over_dc_panel) and (not over_pan_panel) and mouse_clicked and current_item and current_item_len > 0 then
            is_interacting = true; last_interaction_time = r.time_precise()
            local mx, _ = r.ImGui_GetMousePos(ctx)
            if handle_hover == 'in' or handle_hover == 'out' then
                fade_dragging = true
                fade_drag_side = handle_hover
                dragging_select = false
                if not fade_undo_open then r.Undo_BeginBlock(); fade_undo_open = true end
            else
                drag_start_px = mx
                drag_start_time = r.time_precise()
                local relx = (mx - content_x) / math.max(1, wave_w)
                relx = math.max(0.0, math.min(1.0, relx))
                drag_start_t = view_start + relx * view_len
                drag_cur_t = drag_start_t
                dragging_select = false
            end
        end

    if hovered and rmb_clicked and current_item and current_item_len > 0 then
            is_interacting = true; last_interaction_time = r.time_precise()
            local mx, my = r.ImGui_GetMousePos(ctx)
            if handle_hover == 'in' or handle_hover == 'out' then
                fade_ctx_side = handle_hover
                r.ImGui_OpenPopup(ctx, "FadeShapeMenu")
            else
        if draw_mode_allowed then
                    rmb_pending_start = true
                    rmb_press_x, rmb_press_y = mx, my
                end
            end
        end

        if hovered and mouse_down and drag_start_px ~= nil and not dragging_select and not fade_dragging then
            local mx, _ = r.ImGui_GetMousePos(ctx)
            local moved = math.abs(mx - drag_start_px) >= DRAG_THRESHOLD_PX
            local waited = (drag_start_time and ((r.time_precise() - drag_start_time) * 1000 >= DRAG_DELAY_MS)) or false
            if moved and (not require_shift_for_selection or hasShift) and waited then dragging_select = true end
        end

    if fade_dragging and current_item and current_item_len > 0 then
            is_interacting = true; last_interaction_time = r.time_precise()
            local mx, _ = r.ImGui_GetMousePos(ctx)
            local vt0 = view_start
            local vt1 = view_start + view_len
            local item_t0 = current_item_start
            local item_t1 = current_item_start + current_item_len
            local mouse_t = vt0 + ((mx - content_x) / math.max(1, wave_w)) * (vt1 - vt0)
            if fade_drag_side == 'in' then
                local fin_new = math.max(0.0, math.min(current_item_len, mouse_t - item_t0))
                local fout_cur = r.GetMediaItemInfo_Value(current_item, 'D_FADEOUTLEN') or 0.0
                local max_fin = math.max(0.0, current_item_len - fout_cur)
                if fin_new > max_fin then
                    fout_cur = math.max(0.0, current_item_len - fin_new)
                    r.SetMediaItemInfo_Value(current_item, 'D_FADEOUTLEN', fout_cur)
                end
                r.SetMediaItemInfo_Value(current_item, 'D_FADEINLEN', fin_new)
                r.UpdateItemInProject(current_item)
            elseif fade_drag_side == 'out' then
                local fout_new = math.max(0.0, math.min(current_item_len, item_t1 - mouse_t))
                local fin_cur = r.GetMediaItemInfo_Value(current_item, 'D_FADEINLEN') or 0.0
                local max_fout = math.max(0.0, current_item_len - fin_cur)
                if fout_new > max_fout then
                    fin_cur = math.max(0.0, current_item_len - fout_new)
                    r.SetMediaItemInfo_Value(current_item, 'D_FADEINLEN', fin_cur)
                end
                r.SetMediaItemInfo_Value(current_item, 'D_FADEOUTLEN', fout_new)
                r.UpdateItemInProject(current_item)
            end
            if not mouse_down then
                fade_dragging = false
        fade_drag_side = nil
        if fade_undo_open then r.Undo_EndBlock('RAW: Adjust fade', -1); fade_undo_open = false end
            end
        end

    if dragging_select then
            is_interacting = true; last_interaction_time = r.time_precise()
            local mx, _ = r.ImGui_GetMousePos(ctx)
            local relx = (mx - content_x) / math.max(1, wave_w)
            relx = math.max(0.0, math.min(1.0, relx))
            drag_cur_t = view_start + relx * view_len
       
            if hasShift and drag_start_t then
                local t0, t1 = drag_start_t, drag_cur_t
                if snap_click_to_grid and not hasAlt then
                    t0 = SnapTimeToProjectGrid(t0)
                    t1 = SnapTimeToProjectGrid(t1)
                end
                local a = math.max(current_item_start, math.min(t0, t1))
                local b = math.min(current_item_start + current_item_len, math.max(t0, t1))
                r.GetSet_LoopTimeRange(true, false, a, b, false)
                ts_user_override = true
            end
            if mouse_released then
                is_interacting = true; last_interaction_time = r.time_precise()
                dragging_select = false
                drag_start_px = nil
     
                local t0 = drag_start_t or 0
                local t1 = drag_cur_t or t0
                if snap_click_to_grid and not hasAlt then
                    t0 = SnapTimeToProjectGrid(t0)
                    t1 = SnapTimeToProjectGrid(t1)
                end
               
                local a = math.max(current_item_start, math.min(t0, t1))
                local b = math.min(current_item_start + current_item_len, math.max(t0, t1))
                drag_start_t, drag_cur_t = a, b
                if show_vol_points and pencil_target == "item_vol" and current_take and a and b and b > a then
                    local env = r.GetTakeEnvelopeByName(current_take, 'Volume')
                    if env and hasCtrl and hasAlt then
                        local it_start = current_item_start or 0
                        local len = current_item_len or 0
                        local t0_in = math.max(0, math.min(len, (a - it_start)))
                        local t1_in = math.max(0, math.min(len, (b - it_start)))
                        if t1_in > t0_in then
                            r.Undo_BeginBlock()
                            r.DeleteEnvelopePointRangeEx(env, -1, t0_in, t1_in)
                            r.Envelope_SortPoints(env)
                            r.UpdateArrange()
                            r.Undo_EndBlock('RAW: Delete Volume envelope points in selection', -1)
                        end
                    end
                end
                
                sel_a, sel_b = a, b
             
                r.GetSet_LoopTimeRange(true, false, a, b, false)
                ts_user_override = true
            end
        end
    if hovered and rmb_down and current_item and current_item_len > 0 then
        if rmb_pending_start and draw_mode_allowed then
                local mx, my = r.ImGui_GetMousePos(ctx)
                if math.abs((mx - (rmb_press_x or mx))) >= RMB_DRAG_THRESHOLD_PX or math.abs((my - (rmb_press_y or my))) >= RMB_DRAG_THRESHOLD_PX then
                    rmb_pending_start = false
                    rmb_drawing = true
                    draw_points = {}
                    draw_last_t = nil
                    draw_visible_until = r.time_precise() + DRAW_FADE_SEC
                    draw_lane_ch = nil
            if pencil_mode and pencil_target == "dc_offset" and draw_channels_separately and (channels >= 2) then
                        local center_split = wave_y + (wave_h * 0.5)
                        if my < center_split then draw_lane_ch = 1 else draw_lane_ch = 2 end
                    end
                end
            end
        end

    if rmb_drawing and draw_mode_allowed and hovered and rmb_down and current_item and current_item_len > 0 then
            is_interacting = true; last_interaction_time = r.time_precise()
            local mx, my = r.ImGui_GetMousePos(ctx)
            local relx = (mx - content_x) / math.max(1, wave_w)
            relx = math.max(0.0, math.min(1.0, relx))
            local t = view_start + relx * view_len
            local lane_center_y, lane_h_used
        if channels >= 2 and pencil_target == "dc_offset" and draw_channels_separately then
                local half = wave_h * 0.5
                local lane = draw_lane_ch
                if not lane then lane = (my < (wave_y + half)) and 1 or 2 end
                if lane == 1 then
                    lane_center_y = wave_y + half * 0.5
                else
                    lane_center_y = wave_y + half * 1.5
                end
                lane_h_used = half
            else
                lane_center_y = wave_y + (wave_h * 0.5)
                lane_h_used = wave_h
            end
            local v
            if show_env_overlay and (pencil_target == "item_pan" or pencil_target == "item_vol") then
                local ty = (my - wave_y) / math.max(1e-6, wave_h)
                if ty < 0 then ty = 0 elseif ty > 1 then ty = 1 end
                v = (0.5 - ty) * 2.0 
            else
                local dy = (lane_center_y - my)
                v = dy / (lane_h_used * 0.45)
            end
            if v < -1 then v = -1 elseif v > 1 then v = 1 end
            local append = true
            if draw_points and #draw_points > 0 then
                local last = draw_points[#draw_points]
                local last_px = content_x + ((last.t - view_start) / math.max(1e-12, view_len)) * wave_w
                if math.abs(mx - last_px) < DRAW_MIN_PX_STEP then append = false end
            end
            if append then
                draw_points[#draw_points + 1] = { t = t, v = v }
                draw_last_t = t
                draw_visible_until = r.time_precise() + DRAW_FADE_SEC
            end
        end

    if (rmb_drawing or rmb_pending_start) and rmb_released then
            is_interacting = true; last_interaction_time = r.time_precise()
            rmb_drawing = false
            rmb_pending_start = false
    if draw_mode_allowed and current_item and current_take and draw_points and #draw_points >= 2 then
                r.Undo_BeginBlock()
                local ok
            if pencil_target == "dc_offset" then
            local link_for_stroke = (dc_link_lr or (not draw_channels_separately)) and true or false
            ok = CommitStrokeToDCOffset(current_take, current_item, draw_points, current_item_start, wave_w, wave_w, link_for_stroke, draw_lane_ch)
            elseif pencil_target == "eraser" then
                ok = CommitStrokeToMuteRange(current_take, current_item, draw_points, current_item_start, wave_w, wave_w)
                elseif pencil_target == "item_pan" then
                    ok = CommitStrokeToTakePanEnv(current_take, current_item, draw_points, current_item_start, wave_w, wave_w)
                    if ok and current_take and current_item then EnsureActiveTakeEnvelopeVisible('item_pan', current_take, current_item) end
                else
                    ok = CommitStrokeToTakeVolEnv(current_take, current_item, draw_points, current_item_start, wave_w, wave_w)
                    if ok and current_take and current_item then EnsureActiveTakeEnvelopeVisible('item_vol', current_take, current_item) end
                end
                r.UpdateItemInProject(current_item)
            local desc
            if pencil_target == "dc_offset" then
                desc = 'RAW: Pencil to DC Offset'
            elseif pencil_target == "eraser" then
                desc = 'RAW: Eraser (mute to 0)'
            else
                if pencil_target == "item_pan" then
                    if not pencil_mode and show_env_overlay then
                        desc = 'RAW: Envelopes: take Pan'
                    else
                        desc = 'RAW: Pencil to take Pan'
                    end
                else
                    if not pencil_mode and show_env_overlay then
                        desc = 'RAW: Envelopes: take Volume'
                    else
                        desc = 'RAW: Pencil to take Volume'
                    end
                end
            end
                r.Undo_EndBlock(ok and desc or (not pencil_mode and show_env_overlay and 'RAW: Envelopes (no-op)' or 'RAW: Pencil (no-op)'), -1)
                draw_lane_ch = nil
            end
            draw_visible_until = r.time_precise() + DRAW_FADE_SEC
        end

    if hovered and (not over_dc_panel) and (not over_pan_panel) and mouse_released and not dragging_select and not fade_dragging and drag_start_px ~= nil then
            if current_item and current_item_len > 0 then
                is_interacting = true; last_interaction_time = r.time_precise()
                local mouse_x, _ = r.ImGui_GetMousePos(ctx)
        local relx = (mouse_x - content_x) / math.max(1, wave_w)
                relx = math.max(0.0, math.min(1.0, relx))
                local t = view_start + relx * view_len
                if snap_click_to_grid and not hasAlt then
                    t = SnapTimeToProjectGrid(t)
                end
        if hasShift then

                    local ts, te = r.GetSet_LoopTimeRange(false, false, 0, 0, false)
                    if te > ts then
                        if math.abs(t - ts) <= math.abs(t - te) then ts = t else te = t end
                        if te < ts then ts, te = te, ts end
                        r.GetSet_LoopTimeRange(true, false, ts, te, false)
                        ts_user_override = true
            sel_a, sel_b = ts, te
                    else
                        
                        if require_shift_for_selection then
                       
                        else
                            r.GetSet_LoopTimeRange(true, false, t, t, false)
                            ts_user_override = true
                            sel_a, sel_b = t, t
                        end
                    end
                  
                    if click_sets_edit_cursor and not hasCtrl then r.SetEditCurPos(t, false, false) end
                else
  
                    if hasCtrl then
                        r.SetEditCurPos(t, false, false)
                    else
                        if click_sets_edit_cursor then r.SetEditCurPos(t, false, false) end
                        if click_seeks_playback then r.SetEditCurPos(t, true, true) end
                    end
                end
            end
            drag_start_px = nil
            drag_start_time = nil
    end

    if hovered and (not over_dc_panel) and (not over_pan_panel) and r.ImGui_IsMouseDoubleClicked and r.ImGui_IsMouseDoubleClicked(ctx, 0) then
            sel_a, sel_b = nil, nil
            ts_user_override = false
            if transport_item_only then
                ApplyItemTimeSelection(true)
            else
                r.GetSet_LoopTimeRange(true, false, 0, 0, false)
            end
        end
        if hovered and r.ImGui_IsMouseDoubleClicked and r.ImGui_IsMouseDoubleClicked(ctx, 1) then
            rmb_drawing = false
            rmb_pending_start = false
            draw_points = nil
            draw_last_t = nil
            draw_visible_until = 0
        end
        r.ImGui_DrawList_AddRectFilled(draw_list, canvas_x - LEFT_GUTTER_W, wave_y, canvas_x, wave_y + wave_h, COLOR_GUTTER_BG)
        r.ImGui_DrawList_AddRectFilled(draw_list, content_x - LEFT_GUTTER_W, wave_y, content_x, wave_y + wave_h, COLOR_GUTTER_BG)
        r.ImGui_DrawList_AddLine(draw_list, content_x, wave_y, content_x, wave_y + wave_h, 0x333333FF, 1.0)
        if show_ruler then
            DrawRuler(draw_list, content_x, canvas_y, wave_w, ruler_h)
        end
    if draw_channels_separately and channels == 2 then
            local lr_col = 0xFF4444FF
            local gx = content_x - LEFT_GUTTER_W + 6
            local cy = wave_y + wave_h * 0.5
            r.ImGui_DrawList_AddText(draw_list, gx, wave_y + 4, lr_col, 'L')
            r.ImGui_DrawList_AddText(draw_list, gx, cy + 4,      lr_col, 'R')
        end
        if current_item and (current_item_len or 0) > 0 then
            DrawWaveform(draw_list, content_x, wave_y, wave_w, wave_h)
            DrawItemInfoPanel(draw_list, content_x, wave_y, wave_w, wave_h)
            if IsItemPolarityInverted and current_item and IsItemPolarityInverted(current_item) then
                local label = "Ø"
                local pad = 4.0
                local margin = 2.0
                local gx_left = content_x - LEFT_GUTTER_W
                local tw, th = r.ImGui_CalcTextSize(ctx, label)
                local bh = (th + pad * 1.2)
                local by1 = show_ruler and (canvas_y + math.max(0.0, (ruler_h - bh) * 0.5)) or (wave_y + margin)
                local bx1 = gx_left + margin
                local bx2 = bx1 + (tw + pad * 2)
                local by2 = by1 + (th + pad * 1.2)
                local text_col = 0xFFFFFFFF
                local dlp = (r.ImGui_GetForegroundDrawList and r.ImGui_GetForegroundDrawList(ctx)) or draw_list
                r.ImGui_DrawList_AddText(dlp, bx1 + pad, by1 + pad * 0.2, text_col, label)
            end
        else
            local txt = "Select audio-item"
            local tw, th = r.ImGui_CalcTextSize(ctx, txt)
            local tx = content_x + (wave_w - tw) * 0.5
            local ty = wave_y + (wave_h - th) * 0.5
            r.ImGui_DrawList_AddTextEx(draw_list, font_big, 24, tx, ty, 0xFFFFFFFF, txt)
        end
      
        if show_env_overlay and current_take and current_item_len > 0 and view_len > 0 then
            EnsureActiveTakeEnvelopeVisible(pencil_target, current_take, current_item)
            if not ValidItem(current_item) or not ValidTake(current_take) then goto after_env_overlay end
            local draw_pan = (pencil_target == "item_pan")
            local env = r.GetTakeEnvelopeByName(current_take, draw_pan and "Pan" or "Volume")
            local top_y = wave_y
            local bot_y = wave_y + wave_h
            local has_env = (env ~= nil)
            local cnt = has_env and (r.CountEnvelopePoints(env) or 0) or 0
            local mx, my = r.ImGui_GetMousePos(ctx)
            local hover_radius = 6.0
            local hit_radius_px = 7.0
            if draw_pan then
                if not has_env or cnt < 2 then
                    local cy = top_y + (bot_y - top_y) * 0.5
                    r.ImGui_DrawList_AddLine(draw_list, content_x, cy, content_x + wave_w, cy, COLOR_ENV_PAN_OVERLAY, 1.6)
        else
                    local samples = math.max(32, math.min(512, math.floor(wave_w / 4)))
                    local last_px, last_py = nil, nil
                    for i = 0, samples do
                        local tt = (samples == 0) and 0 or (i / samples)
                        local t_abs = view_start + tt * view_len
                        local t_in = t_abs - (current_item_start or 0)
                        if t_in < 0 then t_in = 0 end
                        if t_in > (current_item_len or 0) then t_in = current_item_len or 0 end
                        local _, v = r.Envelope_Evaluate(env, t_in, 0, 0)
                        if v == nil then v = 0.0 end 
                        if v < -1.0 then v = -1.0 elseif v > 1.0 then v = 1.0 end
                        local disp = (v + 1.0) * 0.5
                        local py = bot_y - (bot_y - top_y) * disp
                        local px = content_x + tt * wave_w
                        if last_px then
                            r.ImGui_DrawList_AddLine(draw_list, last_px, last_py, px, py, COLOR_ENV_PAN_OVERLAY, 1.6)
                        end
                        last_px, last_py = px, py
                    end
                end
            else
                local mode = r.GetEnvelopeScalingMode and r.GetEnvelopeScalingMode(env) or 0
                if not has_env or cnt < 2 then
                    local vol_y = vol_db_to_y(0.0, top_y, bot_y)
                    r.ImGui_DrawList_AddLine(draw_list, content_x, vol_y, content_x + wave_w, vol_y, COLOR_ENV_VOL_OVERLAY, 1.6)
                else
                    local samples = math.max(32, math.min(512, math.floor(wave_w / 4)))
                    local last_px, last_py = nil, nil
                    for i = 0, samples do
                        local tt = (samples == 0) and 0 or (i / samples)
                        local t_abs = view_start + tt * view_len
                        local t_in = t_abs - (current_item_start or 0)
                        if t_in < 0 then t_in = 0 end
                        if t_in > (current_item_len or 0) then t_in = current_item_len or 0 end
                        local _, v = r.Envelope_Evaluate(env, t_in, 0, 0)
                        local amp
                        if v ~= nil then
                            if r.ScaleFromEnvelopeMode then amp = r.ScaleFromEnvelopeMode(mode, v) else amp = v end
                        else
                            amp = 1.0
                        end
                        if amp and amp < 1e-6 then amp = 1e-6 end
                        local db = amp_to_db(amp or 1.0)
                        if db < VOL_DB_MIN then db = VOL_DB_MIN end
                        if db > VOL_DB_MAX then db = VOL_DB_MAX end
                        local vol_y = vol_db_to_y(db, top_y, bot_y)
                        local px = content_x + tt * wave_w
                        if last_px then
                            r.ImGui_DrawList_AddLine(draw_list, last_px, last_py, px, vol_y, COLOR_ENV_VOL_OVERLAY, 1.6)
                        end
                        last_px, last_py = px, vol_y
                    end
                end

                if show_vol_points and has_env and cnt > 0 then
                    local sel_t0, sel_t1 = nil, nil
                    if dragging_select and drag_start_t and drag_cur_t then
                        sel_t0 = math.max(current_item_start or 0, math.min(drag_start_t, drag_cur_t))
                        sel_t1 = math.min((current_item_start or 0) + (current_item_len or 0), math.max(drag_start_t, drag_cur_t))
                    elseif sel_a and sel_b then
                        sel_t0, sel_t1 = sel_a, sel_b
                    end
                    local it_start = current_item_start or 0
                    local vt0 = view_start
                    local vt1 = view_start + view_len
                    local t0_in = math.max(0, vt0 - it_start)
                    local t1_in = math.max(0, vt1 - it_start)

                    local hovered_idx = nil
                    for i = 0, cnt - 1 do
                        local ok, t_in, val, shape, tens = r.GetEnvelopePoint(env, i)
                        if ok then
                            if t_in >= t0_in and t_in <= t1_in then
                                local amp = r.ScaleFromEnvelopeMode and r.ScaleFromEnvelopeMode(mode, val) or val
                                if amp and amp < 1e-6 then amp = 1e-6 end
                                local db = amp_to_db(amp or 1.0)
                                if db < VOL_DB_MIN then db = VOL_DB_MIN end
                                if db > VOL_DB_MAX then db = VOL_DB_MAX end
                                local t_abs = it_start + t_in
                                local tt = (t_abs - vt0) / math.max(1e-12, (vt1 - vt0))
                                local px = content_x + tt * wave_w
                                local py = vol_db_to_y(db, top_y, bot_y)
                                local dist = math.sqrt((mx - px)^2 + (my - py)^2)
                                local in_sel = (sel_t0 and sel_t1) and (t_abs >= sel_t0 and t_abs <= sel_t1) or false
                                local base_alpha = (STATE.vol_pt_drag_idx == i or STATE.vol_pt_hover_idx == i or in_sel) and 1.0 or 0.9
                                local clr = ColorWithAlpha(COLOR_ENV_VOL_OVERLAY, base_alpha)
                                r.ImGui_DrawList_AddCircleFilled(draw_list, px, py, 3.5, clr)
                                r.ImGui_DrawList_AddCircle(draw_list, px, py, 3.5, 0xFFFFFFFF, 12, in_sel and 2.0 or 1.2)
                                if hovered and dist <= hit_radius_px then
                                    hovered_idx = i
                                end
                            end
                        end
                    end
                    STATE.vol_pt_hover_idx = hovered_idx

                    if hovered and STATE.vol_pt_hover_idx ~= nil and not r.ImGui_IsMouseDown(ctx, 0) then
                        local idx = STATE.vol_pt_hover_idx
                        local ok, t_in, val = r.GetEnvelopePoint(env, idx)
                        if ok then
                            local amp = r.ScaleFromEnvelopeMode and r.ScaleFromEnvelopeMode(mode, val) or val
                            if amp and amp < 1e-6 then amp = 1e-6 end
                            local db = amp_to_db(amp or 1.0)
                            if db < VOL_DB_MIN then db = VOL_DB_MIN end
                            if db > VOL_DB_MAX then db = VOL_DB_MAX end
                            local t_abs = (current_item_start or 0) + (t_in or 0)
                            r.ImGui_BeginTooltip(ctx)
                            r.ImGui_Text(ctx, string.format("Point: %.3fs, %.1f dB", t_abs, db))
                            r.ImGui_Separator(ctx)
                            r.ImGui_Text(ctx, "Left-drag: move (snaps to grid)")
                            r.ImGui_Text(ctx, "Hold Alt: disable snap while moving")
                            r.ImGui_Text(ctx, "Alt+Click: delete point")
                            r.ImGui_Text(ctx, "Double-click empty area: add point")
                            r.ImGui_Text(ctx, "Ctrl+Alt (release): delete points in selection")
                            r.ImGui_EndTooltip(ctx)
                        end
                    end

                    if hovered and r.ImGui_IsMouseClicked(ctx, 0) then
                        if STATE.vol_pt_hover_idx ~= nil then
                            STATE.vol_pt_drag_idx = STATE.vol_pt_hover_idx
                            if not STATE.vol_pt_undo_open then r.Undo_BeginBlock(); STATE.vol_pt_undo_open = true end
                        end
                    end
                    if STATE.vol_pt_drag_idx ~= nil then
                        if r.ImGui_IsMouseDown(ctx, 0) then
                            local idx = STATE.vol_pt_drag_idx
                            local ok, t_in, val, shape, tens, sel = r.GetEnvelopePoint(env, idx)
                            if ok then
                                local mx_norm = (mx - content_x) / math.max(1, wave_w)
                                mx_norm = math.max(0.0, math.min(1.0, mx_norm))
                                local t_abs = vt0 + mx_norm * (vt1 - vt0)
                                if snap_click_to_grid and not hasAlt then
                                    t_abs = SnapTimeToProjectGrid(t_abs)
                                end
                                local new_t_in = math.max(0, math.min(current_item_len or 0, t_abs - it_start))
                                local new_db = vol_y_to_db(my, top_y, bot_y)
                                local new_amp = db_to_amp(new_db)
                                local new_val = r.ScaleToEnvelopeMode and r.ScaleToEnvelopeMode(mode, new_amp) or new_amp
                                r.SetEnvelopePoint(env, idx, new_t_in, new_val, shape or 0, tens or 0.0, sel or false, true)
                                r.UpdateArrange()
                            end
                        else
                            if STATE.vol_pt_undo_open then
                                r.Envelope_SortPoints(env)
                                r.Undo_EndBlock('RAW: Move Volume envelope point', -1)
                                STATE.vol_pt_undo_open = false
                            end
                            STATE.vol_pt_drag_idx = nil
                        end
                    end
                    if hovered and r.ImGui_IsMouseClicked(ctx, 0) and STATE.vol_pt_hover_idx == nil then
                    end
                    if hovered and r.ImGui_IsMouseDoubleClicked and r.ImGui_IsMouseDoubleClicked(ctx, 0) then
                        if not STATE.vol_pt_undo_open then r.Undo_BeginBlock(); STATE.vol_pt_undo_open = true end
                        local mx_norm = (mx - content_x) / math.max(1, wave_w)
                        mx_norm = math.max(0.0, math.min(1.0, mx_norm))
                        local t_abs = vt0 + mx_norm * (vt1 - vt0)
                        if snap_click_to_grid and not hasAlt then
                            t_abs = SnapTimeToProjectGrid(t_abs)
                        end
                        local new_t_in = math.max(0, math.min(current_item_len or 0, t_abs - it_start))
                        local new_db = vol_y_to_db(my, top_y, bot_y)
                        local new_amp = db_to_amp(new_db)
                        local new_val = r.ScaleToEnvelopeMode and r.ScaleToEnvelopeMode(mode, new_amp) or new_amp
                        r.InsertEnvelopePoint(env, new_t_in, new_val, 0, 0, 0, true)
                        r.Envelope_SortPoints(env)
                        r.UpdateArrange()
                        r.Undo_EndBlock('RAW: Add Volume envelope point', -1)
                        STATE.vol_pt_undo_open = false
                    end
                    if hovered and r.ImGui_IsMouseClicked(ctx, 0) and STATE.vol_pt_hover_idx ~= nil and hasAlt then
                        r.Undo_BeginBlock()
                        r.DeleteEnvelopePointEx(env, -1, STATE.vol_pt_hover_idx)
                        r.Envelope_SortPoints(env)
                        r.UpdateArrange()
                        r.Undo_EndBlock('RAW: Delete Volume envelope point', -1)
                        STATE.vol_pt_hover_idx = nil
                        STATE.vol_pt_drag_idx = nil
                    end
                end
            end
            ::after_env_overlay::
        end

    if show_dc_overlay and current_take and current_item_len > 0 and view_len > 0 then
            if not ValidItem(current_item) or not ValidTake(current_take) then goto after_dc_overlay end
            local vt0 = view_start
            local vt1 = view_start + view_len
            local top_y = wave_y
            local bot_y = wave_y + wave_h
            local fxidx = -1
            local nfx = r.TakeFX_GetCount(current_take) or 0
            for i = 0, nfx - 1 do
                local _, nm = r.TakeFX_GetFXName(current_take, i, "")
                if nm and nm:find("DC_offset_sampleaccurate", 1, true) then fxidx = i; break end
            end
            local envL, envR = nil, nil
            if fxidx ~= -1 then
                envL = r.TakeFX_GetEnvelope(current_take, fxidx, 0, false)
                envR = r.TakeFX_GetEnvelope(current_take, fxidx, 1, false)
            end
            local function env_is_raw(env)
                if not env then return false end
                local cnt = r.CountEnvelopePoints(env) or 0
                if cnt == 0 then return false end
                local seenNonZero = false
                local max_check = math.min(cnt, 64)
                for i = 0, max_check - 1 do
                    local ok, _, v = r.GetEnvelopePoint(env, i)
                    if ok then
                        if v < 0.0 or v > 1.0 then return true end
                        if math.abs(v or 0.0) > 1e-12 then seenNonZero = true end
                    end
                end
                if not seenNonZero then return true end 
                return false
            end
            local envL_is_raw = env_is_raw(envL)
            local envR_is_raw = env_is_raw(envR)
            local function dc_val_at(t_abs, env, is_raw)
                if not env then return 0.0 end
                local t_in = t_abs - (current_item_start or 0)
                if t_in < 0 then t_in = 0 end
                if t_in > (current_item_len or 0) then t_in = current_item_len or 0 end
                local cnt = r.CountEnvelopePoints(env) or 0
                if cnt == 0 then return 0.0 end
                local _, v = r.Envelope_Evaluate(env, t_in, 0, 0)
                if v ~= nil then
                    local vv = tonumber(v) or 0.0
                    if is_raw then
                        if vv < -1.0 then vv = -1.0 elseif vv > 1.0 then vv = 1.0 end
                        return vv
                    else
                        vv = (vv * 2.0) - 1.0
                        if vv < -1.0 then vv = -1.0 elseif vv > 1.0 then vv = 1.0 end
                        return vv
                    end
                end
                local _, t0e, v0 = r.GetEnvelopePoint(env, 0)
                local _, t1e, v1 = r.GetEnvelopePoint(env, math.max(0, cnt - 1))
                local usev = v0
                if t_in >= (t1e or 0) then usev = v1 end
                local fallback = is_raw and 0.0 or 0.5
                local vv = tonumber(usev) or fallback
                if is_raw then
                    if vv < -1.0 then vv = -1.0 elseif vv > 1.0 then vv = 1.0 end
                    return vv
                else
                    vv = (vv * 2.0) - 1.0
                    if vv < -1.0 then vv = -1.0 elseif vv > 1.0 then vv = 1.0 end
                    return vv
                end
            end
            local function y_for_dc(dc)
                local cy = (top_y + bot_y) * 0.5
                local scale = (bot_y - top_y) * 0.5 * 0.9
                return cy - (dc * scale)
            end
            if draw_channels_separately and channels >= 2 then
                local lane_h = wave_h * 0.5
                local topL = top_y
                local botL = top_y + lane_h
                local function y_for_dc_L(dc)
                    local cy = (topL + botL) * 0.5
                    local scale = (botL - topL) * 0.5 * 0.9
                    return cy - (dc * scale)
                end
                local samples = math.max(32, math.min(512, math.floor(wave_w / 6)))
                r.ImGui_DrawList_PathClear(draw_list)
                for i = 0, samples do
                    local tt = (samples == 0) and 0 or (i / samples)
                    local t_abs = vt0 + tt * (vt1 - vt0)
                    local dc = envL and dc_val_at(t_abs, envL, envL_is_raw) or 0.0
                    local px = content_x + tt * wave_w
                    local py = y_for_dc_L(dc)
                    r.ImGui_DrawList_PathLineTo(draw_list, px, py)
                end
                r.ImGui_DrawList_PathStroke(draw_list, COLOR_DC_OVERLAY, 0, 1.6)

                local topR = top_y + lane_h
                local botR = bot_y
                local function y_for_dc_R(dc)
                    local cy = (topR + botR) * 0.5
                    local scale = (botR - topR) * 0.5 * 0.9
                    return cy - (dc * scale)
                end
                r.ImGui_DrawList_PathClear(draw_list)
                for i = 0, samples do
                    local tt = (samples == 0) and 0 or (i / samples)
                    local t_abs = vt0 + tt * (vt1 - vt0)
                    local dc = envR and dc_val_at(t_abs, envR, envR_is_raw) or 0.0
                    local px = content_x + tt * wave_w
                    local py = y_for_dc_R(dc)
                    r.ImGui_DrawList_PathLineTo(draw_list, px, py)
                end
                r.ImGui_DrawList_PathStroke(draw_list, COLOR_DC_OVERLAY, 0, 1.6)
            else
                local samples = math.max(32, math.min(512, math.floor(wave_w / 6)))
                r.ImGui_DrawList_PathClear(draw_list)
                for i = 0, samples do
                    local tt = (samples == 0) and 0 or (i / samples)
                    local t_abs = vt0 + tt * (vt1 - vt0)
                    local dcL = envL and dc_val_at(t_abs, envL, envL_is_raw) or 0.0
                    local dcR = envR and dc_val_at(t_abs, envR, envR_is_raw) or dcL
                    local dc = (envL or envR) and ((dcL + dcR) * 0.5) or 0.0
                    local px = content_x + tt * wave_w
                    local py = y_for_dc(dc)
                    r.ImGui_DrawList_PathLineTo(draw_list, px, py)
                end
                r.ImGui_DrawList_PathStroke(draw_list, COLOR_DC_OVERLAY, 0, 1.6)
            end
            ::after_dc_overlay::
        end

    if show_pan_overlay and pan_color_overlay and current_take and current_item_len > 0 and view_len > 0 then
            local p = r.GetMediaItemTakeInfo_Value(current_take, 'D_PAN') or 0.0
            if p < -1.0 then p = -1.0 elseif p > 1.0 then p = 1.0 end
            local theta = (p + 1.0) * (math.pi * 0.25)
            local gL = math.cos(theta)
            local gR = math.sin(theta)
            local colL = 0x3DA7FFFF 
            local colR = 0xFF5544FF  
            local baseA, varA = 0.06, 0.20
            if draw_channels_separately and (channels or 1) >= 2 then
                local lane_h = wave_h * 0.5
                local topL = wave_y
                local botL = wave_y + lane_h
                local topR = wave_y + lane_h
                local botR = wave_y + wave_h
                local aL = baseA + varA * (gL or 0)
                local aR = baseA + varA * (gR or 0)
                r.ImGui_DrawList_AddRectFilled(draw_list, content_x, topL, content_x + wave_w, botL, ColorWithAlpha(colL, aL))
                r.ImGui_DrawList_AddRectFilled(draw_list, content_x, topR, content_x + wave_w, botR, ColorWithAlpha(colR, aR))
                local pLp = math.floor(((gL or 0) * (gL or 0)) * 100 + 0.5)
                local pRp = math.floor(((gR or 0) * (gR or 0)) * 100 + 0.5)
                local epLp = math.floor((gL or 0) * 100 + 0.5)
                local epRp = math.floor((gR or 0) * 100 + 0.5)
                r.ImGui_DrawList_AddText(draw_list, content_x + 6, topL + 4, 0xFFFFFFFF, string.format("L %d%% (%d%%)", pLp, epLp))
                r.ImGui_DrawList_AddText(draw_list, content_x + 6, topR + 4, 0xFFFFFFFF, string.format("R %d%% (%d%%)", pRp, epRp))
            else
                local midx = content_x + wave_w * 0.5
                local aL = baseA + varA * (gL or 0)
                local aR = baseA + varA * (gR or 0)
                r.ImGui_DrawList_AddRectFilled(draw_list, content_x, wave_y, midx, wave_y + wave_h, ColorWithAlpha(colL, aL))
                r.ImGui_DrawList_AddRectFilled(draw_list, midx,      wave_y, content_x + wave_w, wave_y + wave_h, ColorWithAlpha(colR, aR))
                local px = content_x + ((p + 1.0) * 0.5) * wave_w
                local py = wave_y + 2.0
                r.ImGui_DrawList_AddTriangleFilled(draw_list, px - 5, py + 8, px + 5, py + 8, px, py, 0xFFD24DFF)
            end
        end

        do
            if current_item and current_item_len > 0 and view_len > 0 then
                local vt0 = view_start
                local vt1 = view_start + view_len
                local item_px_start2 = content_x + ((current_item_start - vt0) / (vt1 - vt0)) * wave_w
                local item_px_end2   = content_x + (((current_item_start + current_item_len) - vt0) / (vt1 - vt0)) * wave_w
                if item_px_end2 > content_x and item_px_start2 < (content_x + wave_w) then
                    local amp = r.GetMediaItemInfo_Value(current_item, 'D_VOL') or 1.0
                    if amp < 0.000001 then amp = 0.000001 end
                    local db = amp_to_db(amp)
                    if db < VOL_DB_MIN then db = VOL_DB_MIN end
                    if db > VOL_DB_MAX then db = VOL_DB_MAX end
                    local vol_y = vol_db_to_y(db, wave_y, wave_y + wave_h)
                    local fin  = r.GetMediaItemInfo_Value(current_item, 'D_FADEINLEN') or 0.0
                    local fout = r.GetMediaItemInfo_Value(current_item, 'D_FADEOUTLEN') or 0.0
                    if fin < 0 then fin = 0 end; if fin > current_item_len then fin = current_item_len end
                    if fout < 0 then fout = 0 end; if fout > current_item_len then fout = current_item_len end
                    local start_x, end_x
                    if not show_fades then
                        start_x = math.max(content_x, item_px_start2)
                        end_x   = math.min(content_x + wave_w, item_px_end2)
                    else
                        start_x = (fin > 0) and (item_px_start2 + (fin / math.max(1e-12, view_len)) * wave_w) or item_px_start2
                        end_x   = (fout > 0) and (item_px_end2   - (fout / math.max(1e-12, view_len)) * wave_w) or item_px_end2
                        start_x = math.max(content_x, start_x)
                        end_x   = math.min(content_x + wave_w, end_x)
                    end
                    local has_span = (end_x - start_x) > 1.0
                    local mx, my = r.ImGui_GetMousePos(ctx)
                    vol_hover = has_span and (mx >= start_x and mx <= end_x and my >= (vol_y - VOL_HIT_PAD_Y) and my <= (vol_y + VOL_HIT_PAD_Y)) or false
                    if hovered and vol_hover and (not handle_hover) and r.ImGui_IsMouseDoubleClicked and r.ImGui_IsMouseDoubleClicked(ctx, 0) then
                        RunCommandOnItemWithTemporarySelection(current_item, 41589) 
                    elseif hovered and r.ImGui_IsMouseClicked(ctx, 0) and vol_hover and (not handle_hover) and (not fade_dragging) then
                        vol_dragging = true
                        if not vol_undo_open then r.Undo_BeginBlock(); vol_undo_open = true end
                    end
                    if show_tooltips and vol_hover and (not handle_hover) and not vol_dragging then
                        r.ImGui_BeginTooltip(ctx)
                        r.ImGui_Text(ctx, 'Double-click: Item properties')
                        r.ImGui_EndTooltip(ctx)
                    end
                    if vol_dragging and r.ImGui_IsMouseDown(ctx, 0) then
                        is_interacting = true; last_interaction_time = r.time_precise()
                        local _, my2 = r.ImGui_GetMousePos(ctx)
                        local db2 = vol_y_to_db(my2, wave_y, wave_y + wave_h)
                        local amp2 = db_to_amp(db2)
                        r.SetMediaItemInfo_Value(current_item, 'D_VOL', amp2)
                        r.UpdateItemInProject(current_item)
                        vol_y_draw = vol_db_to_y(db2, wave_y, wave_y + wave_h)
                        r.ImGui_BeginTooltip(ctx)
                        r.ImGui_Text(ctx, string.format("Item volume: %.1f dB", db2))
                        r.ImGui_EndTooltip(ctx)
                    end
                    if has_span then
                        local col = (vol_hover or vol_dragging) and COLOR_VOL_LINE_ACTIVE or COLOR_VOL_LINE
                        r.ImGui_DrawList_AddLine(draw_list, start_x, (vol_y_draw or vol_y), end_x, (vol_y_draw or vol_y), col, VOL_LINE_THICKNESS)
                        r.ImGui_DrawList_AddLine(draw_list, start_x, (vol_y_draw or vol_y) - 4, start_x, (vol_y_draw or vol_y) + 4, col, 1.0)
                        r.ImGui_DrawList_AddLine(draw_list, end_x,   (vol_y_draw or vol_y) - 4, end_x,   (vol_y_draw or vol_y) + 4, col, 1.0)
                    end
                    if vol_dragging and r.ImGui_IsMouseReleased(ctx, 0) then
                        vol_dragging = false
                        vol_y_draw = nil
                        if vol_undo_open then r.Undo_EndBlock('RAW: Adjust item volume', -1); vol_undo_open = false end
                    end
                end
            end
        end
        do
            if show_fades and current_item and current_item_len > 0 and view_len > 0 then
                local vt0 = view_start
                local vt1 = view_start + view_len
                local item_px_start2 = content_x + ((current_item_start - vt0) / (vt1 - vt0)) * wave_w
                local item_px_end2   = content_x + (((current_item_start + current_item_len) - vt0) / (vt1 - vt0)) * wave_w
                if item_px_end2 > content_x and item_px_start2 < (content_x + wave_w) then
                    local fin  = r.GetMediaItemInfo_Value(current_item, 'D_FADEINLEN') or 0.0
                    local fout = r.GetMediaItemInfo_Value(current_item, 'D_FADEOUTLEN') or 0.0
                    if fin < 0 then fin = 0 end; if fin > current_item_len then fin = current_item_len end
                    if fout < 0 then fout = 0 end; if fout > current_item_len then fout = current_item_len end
                    local top_y = wave_y
                    local bot_y = wave_y + wave_h
                    local amp = r.GetMediaItemInfo_Value(current_item, 'D_VOL') or 1.0
                    local db  = amp_to_db(amp)
                    local vol_y = vol_db_to_y(db, wave_y, wave_y + wave_h)
                    r.ImGui_DrawList_PushClipRect(draw_list, content_x, wave_y, content_x + wave_w, wave_y + wave_h, true)
                    if fin > 0 then
                        local fin_x = item_px_start2 + (fin / math.max(1e-12, view_len)) * wave_w
                        local shape = r.GetMediaItemInfo_Value(current_item, 'C_FADEINSHAPE') or 0
                        local dir   = r.GetMediaItemInfo_Value(current_item, 'D_FADEINDIR') or 0
                        local samples = math.max(12, math.min(96, math.floor((fin_x - item_px_start2) / 6)))
                        local pts = {}
                        for i = 0, samples do
                            local tt = (samples == 0) and 0 or (i / samples)
                            local val = EvalFadeIn(shape, dir, tt)
                            local px = item_px_start2 + tt * (fin_x - item_px_start2)
                            local py = vol_y + (1 - val) * (bot_y - vol_y)
                            pts[#pts+1] = {px, py}
                        end
                        local fill_col = ColorWithAlpha(COLOR_FADE_REGION, FADE_FILL_ALPHA)
                        for i = 2, #pts do
                            local x0, y0 = pts[i-1][1], pts[i-1][2]
                            local x1, y1 = pts[i][1],   pts[i][2]
                            r.ImGui_DrawList_AddTriangleFilled(draw_list, x0, vol_y, x1, vol_y, x1, y1, fill_col)
                            r.ImGui_DrawList_AddTriangleFilled(draw_list, x0, vol_y, x1, y1, x0, y0, fill_col)
                        end
                        for i = 2, #pts do
                            r.ImGui_DrawList_AddLine(draw_list, pts[i-1][1], pts[i-1][2], pts[i][1], pts[i][2], COLOR_FADE_LINE, 2.0)
                        end
                    end
                    if fout > 0 then
                        local fout_x = item_px_end2 - (fout / math.max(1e-12, view_len)) * wave_w
                        local shape = r.GetMediaItemInfo_Value(current_item, 'C_FADEOUTSHAPE') or 0
                        local dir   = r.GetMediaItemInfo_Value(current_item, 'D_FADEOUTDIR') or 0
                        local samples = math.max(12, math.min(96, math.floor((item_px_end2 - fout_x) / 6)))
                        local pts = {}
                        for i = 0, samples do
                            local tt = (samples == 0) and 0 or (i / samples)
                            local val = EvalFadeOut(shape, dir, tt)
                            local px = fout_x + tt * (item_px_end2 - fout_x)
                            local py = vol_y + (1 - val) * (bot_y - vol_y)
                            pts[#pts+1] = {px, py}
                        end
                        local fill_col = ColorWithAlpha(COLOR_FADE_REGION, FADE_FILL_ALPHA)
                        for i = 2, #pts do
                            local x0, y0 = pts[i-1][1], pts[i-1][2]
                            local x1, y1 = pts[i][1],   pts[i][2]
                            r.ImGui_DrawList_AddTriangleFilled(draw_list, x0, vol_y, x1, vol_y, x1, y1, fill_col)
                            r.ImGui_DrawList_AddTriangleFilled(draw_list, x0, vol_y, x1, y1, x0, y0, fill_col)
                        end
                        for i = 2, #pts do
                            r.ImGui_DrawList_AddLine(draw_list, pts[i-1][1], pts[i-1][2], pts[i][1], pts[i][2], COLOR_FADE_LINE, 2.0)
                        end
                    end
                    local col_in = (handle_hover == 'in' or (fade_dragging and fade_drag_side == 'in')) and COLOR_FADE_ACTIVE or COLOR_FADE_HANDLE_FILL
                    local col_out = (handle_hover == 'out' or (fade_dragging and fade_drag_side == 'out')) and COLOR_FADE_ACTIVE or COLOR_FADE_HANDLE_FILL
                    local fin_x = (fin > 0) and (item_px_start2 + (fin / math.max(1e-12, view_len)) * wave_w) or item_px_start2
                    local fout_x = (fout > 0) and (item_px_end2   - (fout / math.max(1e-12, view_len)) * wave_w) or item_px_end2
                    r.ImGui_DrawList_AddCircleFilled(draw_list, fin_x, vol_y, FADE_HANDLE_RADIUS, col_in)
                    r.ImGui_DrawList_AddCircle(draw_list, fin_x, vol_y, FADE_HANDLE_RADIUS, COLOR_FADE_HANDLE_BORDER, 16, 1.5)
                    r.ImGui_DrawList_AddCircleFilled(draw_list, fout_x, vol_y, FADE_HANDLE_RADIUS, col_out)
                    r.ImGui_DrawList_AddCircle(draw_list, fout_x, vol_y, FADE_HANDLE_RADIUS, COLOR_FADE_HANDLE_BORDER, 16, 1.5)
                    r.ImGui_DrawList_PopClipRect(draw_list)
                end
            end
        end
        if r.ImGui_BeginPopup(ctx, "FadeShapeMenu") then
            local function ShapeItem(label, action_id)
                if r.ImGui_MenuItem(ctx, label) then
                    if current_item and action_id and action_id > 0 then
                        RunCommandOnItemWithTemporarySelection(current_item, action_id)
                        r.UpdateItemInProject(current_item)
                    end
                    r.ImGui_CloseCurrentPopup(ctx)
                end
            end

            r.ImGui_Text(ctx, fade_ctx_side == 'in' and 'Fade In Shape' or 'Fade Out Shape')
            r.ImGui_Separator(ctx)
            if fade_ctx_side == 'in' then
               
                ShapeItem('Linear', 41514)                    -- type 1
                ShapeItem('Parabolic / Slow start', 41515)    -- type 2
                ShapeItem('Logarithmic / Slow start', 41516)  -- type 3
                ShapeItem('Parabolic / Fast start', 41517)    -- type 4
                ShapeItem('Logarithmic / Fast start', 41518)  -- type 5
                ShapeItem('S-curve (cosine)', 41519)          -- type 6
                ShapeItem('S-curve (square)', 41836)          -- type 7
            else
              
                ShapeItem('Linear', 41521)                    -- type 1
                ShapeItem('Parabolic / Slow start', 41522)    -- type 2
                ShapeItem('Logarithmic / Slow start', 41523)  -- type 3
                ShapeItem('Parabolic / Fast start', 41524)    -- type 4
                ShapeItem('Logarithmic / Fast start', 41525)  -- type 5
                ShapeItem('S-curve (cosine)', 41526)          -- type 6
                ShapeItem('S-curve (square)', 41837)          -- type 7
            end
            r.ImGui_Separator(ctx)
            ShapeItem('Cycle next shape', 41836)
            r.ImGui_EndPopup(ctx)
        end
        do
            local now = r.time_precise()
            local can_preview = pencil_mode or (show_env_overlay and (pencil_target == "item_vol" or pencil_target == "item_pan"))
            local active = can_preview and (rmb_drawing or (draw_points and #draw_points >= 2 and now <= (draw_visible_until or 0)))
            if active and draw_points and #draw_points >= 2 then
                local alpha = rmb_drawing and 0.95 or math.max(0.0, math.min(1.0, (draw_visible_until - now) / DRAW_FADE_SEC))
                local col = ColorWithAlpha(0xFF5544FF, alpha)

                r.ImGui_DrawList_PathClear(draw_list)
                for i = 1, #draw_points do
                    local pt = draw_points[i]
                    local rel = (pt.t - view_start) / math.max(1e-12, view_len)
                    if rel >= 0 and rel <= 1 then
                        local px = content_x + rel * wave_w
                        local lane_center_y, lane_h_used
                        if pencil_target == "eraser" then
                            lane_center_y = wave_y + wave_h * 0.5
                            lane_h_used = wave_h
                            pt.v = 0.0
                        elseif channels >= 2 and pencil_target == "dc_offset" then
                            local half = wave_h * 0.5
                            if draw_channels_separately then
                                local lane = draw_lane_ch or (select(2, r.ImGui_GetMousePos(ctx)) < (wave_y + half) and 1 or 2)
                                lane_center_y = (lane == 1) and (wave_y + half * 0.5) or (wave_y + half * 1.5)
                                lane_h_used = half
                            else
                                lane_center_y = wave_y + wave_h * 0.5
                                lane_h_used = wave_h
                            end
                        else
                            lane_center_y = wave_y + wave_h * 0.5
                            lane_h_used = wave_h
                        end
                        local py = lane_center_y - (pt.v * (lane_h_used * 0.45))
                        r.ImGui_DrawList_PathLineTo(draw_list, px, py)
                    end
                end
                r.ImGui_DrawList_PathStroke(draw_list, col, 0, 2.0)

                if rmb_drawing then
                    local mx, my = r.ImGui_GetMousePos(ctx)
                    local cx = math.max(content_x, math.min(content_x + wave_w, mx))
                    local cy = math.max(wave_y, math.min(wave_y + wave_h, my))
                    local cr = 4.0
                    r.ImGui_DrawList_AddCircle(draw_list, cx, cy, cr, col, 16, 1.5)
                end
            end
        end
        
        local draw_sel_a, draw_sel_b = nil, nil
        if dragging_select and drag_start_t and drag_cur_t then
            draw_sel_a = math.max(current_item_start, math.min(drag_start_t, drag_cur_t))
            draw_sel_b = math.min(current_item_start + current_item_len, math.max(drag_start_t, drag_cur_t))
        elseif sel_a and sel_b then
            draw_sel_a, draw_sel_b = sel_a, sel_b
        end
        if draw_sel_a and draw_sel_b and (draw_sel_b - draw_sel_a) > 1e-9 then
            local vt0 = view_start
            local vt1 = view_start + view_len
            local ax = content_x + ((draw_sel_a - vt0) / (vt1 - vt0)) * wave_w
            local bx = content_x + ((draw_sel_b - vt0) / (vt1 - vt0)) * wave_w
            local fill = ColorWithAlpha(COLOR_SELECTION_FILL, 0.10) 
            local border = ColorWithAlpha(COLOR_SELECTION_BORDER, 0.5) 
            r.ImGui_DrawList_AddRectFilled(draw_list, ax, wave_y, bx, wave_y + wave_h, fill)
          
            r.ImGui_DrawList_AddLine(draw_list, ax, wave_y, ax, wave_y + wave_h, border, 1.0)
            r.ImGui_DrawList_AddLine(draw_list, bx, wave_y, bx, wave_y + wave_h, border, 1.0)
        end

    if hovered and show_tooltips then
            r.ImGui_BeginTooltip(ctx)
            if fade_dragging then
                r.ImGui_Text(ctx, string.format("Dragging fade %s", fade_drag_side == 'in' and 'in' or 'out'))
                r.ImGui_Text(ctx, "Release to set fade length")
            elseif dragging_select then
                local snap_state = (snap_click_to_grid and not hasAlt) and "snap" or "free"
                r.ImGui_Text(ctx, string.format("Drag: selection (%s)", snap_state))
                if require_shift_for_selection then
                    r.ImGui_Text(ctx, "Shift: held (required) | Alt: no snap")
                else
                    r.ImGui_Text(ctx, "Shift: live TS | Alt: no snap")
                end
                if show_vol_points and pencil_target == "item_vol" then
                    r.ImGui_Text(ctx, "Ctrl+Alt (release): delete points in selection")
                    r.ImGui_Text(ctx, "Del: delete points in selection")
                end
            else
                if handle_hover == 'in' then r.ImGui_Text(ctx, "Click-drag: adjust fade-in") end
                if handle_hover == 'out' then r.ImGui_Text(ctx, "Click-drag: adjust fade-out") end
                if click_seeks_playback then
                    r.ImGui_Text(ctx, "Click: set cursor + seek")
                else
                    r.ImGui_Text(ctx, "Click: set cursor")
                end
                if require_shift_for_selection then
                    r.ImGui_Text(ctx, "Shift: start selection | Ctrl: only cursor | Alt: no snap")
                else
                    r.ImGui_Text(ctx, "Shift: selection | Ctrl: only cursor | Alt: no snap")
                end
                if pencil_mode or (show_env_overlay and (pencil_target == "item_vol" or pencil_target == "item_pan")) then r.ImGui_Text(ctx, "RMB: draw preview (UI only)") end
            end
            r.ImGui_EndTooltip(ctx)
        end
        do
            local key_del = r.ImGui_Key_Delete and r.ImGui_Key_Delete() or 0
            local key_bsp = r.ImGui_Key_Backspace and r.ImGui_Key_Backspace() or 0
            local del_pressed = (r.ImGui_IsKeyPressed and (r.ImGui_IsKeyPressed(ctx, key_del, false) or r.ImGui_IsKeyPressed(ctx, key_bsp, false))) or false
            if del_pressed and show_vol_points and pencil_target == "item_vol" and current_take and r.ImGui_IsWindowFocused and r.ImGui_IsWindowFocused(ctx) then
                local a, b = nil, nil
                if drag_start_t and drag_cur_t then
                    a = math.max(current_item_start or 0, math.min(drag_start_t, drag_cur_t))
                    b = math.min((current_item_start or 0) + (current_item_len or 0), math.max(drag_start_t, drag_cur_t))
                elseif sel_a and sel_b then
                    a, b = sel_a, sel_b
                end
                if a and b and b > a then
                    local env = r.GetTakeEnvelopeByName(current_take, 'Volume')
                    if env then
                        local it_start = current_item_start or 0
                        local len = current_item_len or 0
                        local t0_in = math.max(0, math.min(len, (a - it_start)))
                        local t1_in = math.max(0, math.min(len, (b - it_start)))
                        if t1_in > t0_in then
                            r.Undo_BeginBlock()
                            r.DeleteEnvelopePointRangeEx(env, -1, t0_in, t1_in)
                            r.Envelope_SortPoints(env)
                            r.UpdateArrange()
                            r.Undo_EndBlock('RAW: Delete Volume envelope points in selection', -1)
                        end
                    end
                end
            end
        end
        
    do
            local dl_game = (r.ImGui_GetForegroundDrawList and r.ImGui_GetForegroundDrawList(ctx)) or r.ImGui_GetWindowDrawList(ctx)
            local key_space = r.ImGui_Key_Space and r.ImGui_Key_Space() or 0
            local pressed_space = r.ImGui_IsKeyPressed and r.ImGui_IsKeyPressed(ctx, key_space, false) or false
            if pressed_space then
                game_active = true
                game_over = false
                game_score = 0
                game_obstacles = {}
                game_spawn_cooldown = 0.0
                game_last_time = nil 
                game_elapsed = 0.0
                game_packages = {}
            end
            if game_active and not game_last_time then

                local mx, my = 16, 16
                local x_min, x_max = content_x + mx, content_x + math.max(mx, wave_w - mx)
                local y_min, y_max = wave_y + my, wave_y + math.max(my, wave_h - my)
                game_player_x = x_min + math.random() * math.max(1, x_max - x_min)
                game_player_y = y_min + math.random() * math.max(1, y_max - y_min)
                game_obstacles = {}
                game_score = 0
                game_spawn_cooldown = 0.0
                game_over = false
                game_last_time = r.time_precise()
                game_elapsed = 0.0
                game_packages = {}
                local cols, rows = 5, 2
                for cy = 1, rows do
                    for cx = 1, cols do
                        local gx0 = content_x + (cx - 1) * (wave_w / cols)
                        local gy0 = wave_y + (cy - 1) * (wave_h / rows)
                        local gx1 = content_x + cx * (wave_w / cols)
                        local gy1 = wave_y + cy * (wave_h / rows)
                        local px = gx0 + 8 + math.random() * math.max(1, (gx1 - gx0) - 16)
                        local py = gy0 + 8 + math.random() * math.max(1, (gy1 - gy0) - 16)
                        table.insert(game_packages, { x = px, y = py })
                    end
                end
            end

            if game_active then
                local now = r.time_precise()
                local dt = math.min(0.05, (now - (game_last_time or now)))
                game_last_time = now
                game_elapsed = (game_elapsed or 0) + dt

                local up = r.ImGui_IsKeyDown and r.ImGui_IsKeyDown(ctx, r.ImGui_Key_UpArrow and r.ImGui_Key_UpArrow() or 0) or false
                local down = r.ImGui_IsKeyDown and r.ImGui_IsKeyDown(ctx, r.ImGui_Key_DownArrow and r.ImGui_Key_DownArrow() or 0) or false
                local left = r.ImGui_IsKeyDown and r.ImGui_IsKeyDown(ctx, r.ImGui_Key_LeftArrow and r.ImGui_Key_LeftArrow() or 0) or false
                local right = r.ImGui_IsKeyDown and r.ImGui_IsKeyDown(ctx, r.ImGui_Key_RightArrow and r.ImGui_Key_RightArrow() or 0) or false

                local sp = game_speed
                if up then game_player_y = game_player_y - sp * dt end
                if down then game_player_y = game_player_y + sp * dt end
                if left then game_player_x = game_player_x - sp * dt end
                if right then game_player_x = game_player_x + sp * dt end

                local px = math.max(content_x + 4, math.min(content_x + wave_w - 4, game_player_x))
                local py = math.max(wave_y + 4, math.min(wave_y + wave_h - 4, game_player_y))
                game_player_x, game_player_y = px, py

                local diff = 1.0 + math.min(2.0, (game_elapsed or 0) * 0.12)
                game_spawn_cooldown = (game_spawn_cooldown or 0) - dt
                if game_spawn_cooldown <= 0 then
                    local base_size = 10 + math.random() * 18
                    local os = base_size * (math.random() < 0.2 and 1.8 or 1.0)
                    local ov = (120 + math.random() * 240) * diff
                    local side = math.random(1,4) -- 1=right,2=left,3=top,4=bottom
                    local ox, oy, vx, vy
                    if side == 1 then
                        oy = wave_y + math.random() * wave_h
                        ox = content_x + wave_w + os
                        vx, vy = -ov, 0
                    elseif side == 2 then
                        oy = wave_y + math.random() * wave_h
                        ox = content_x - os
                        vx, vy = ov, 0
                    elseif side == 3 then
                        ox = content_x + math.random() * wave_w
                        oy = wave_y - os
                        vx, vy = 0, ov
                    else
                        ox = content_x + math.random() * wave_w
                        oy = wave_y + wave_h + os
                        vx, vy = 0, -ov
                    end
                    table.insert(game_obstacles, { x = ox, y = oy, r = os * 0.5, vx = vx, vy = vy })
                    local base_cd = 0.8 + math.random() * 0.6
                    game_spawn_cooldown = math.max(0.18, base_cd / diff)
                end

                for i = #game_obstacles, 1, -1 do
                    local o = game_obstacles[i]
                    o.x = o.x + (o.vx or 0) * dt
                    o.y = o.y + (o.vy or 0) * dt
                    local out_left = (o.x + o.r) < content_x
                    local out_right = (o.x - o.r) > (content_x + wave_w)
                    local out_top = (o.y + o.r) < wave_y
                    local out_bottom = (o.y - o.r) > (wave_y + wave_h)
                    if out_left or out_right or out_top or out_bottom then
                        table.remove(game_obstacles, i)
                        game_score = game_score + 1
                    end
                end

                local pr = 6
                for i = 1, #game_obstacles do
                    local o = game_obstacles[i]
                    local dx = (o.x - game_player_x)
                    local dy = (o.y - game_player_y)
                    if (dx*dx + dy*dy) <= (o.r + pr) * (o.r + pr) then
                        game_over = true
                        game_active = false
                        break
                    end
                end

                local pr = 6
                for i = #game_packages, 1, -1 do
                    local p = game_packages[i]
                    local dx = p.x - game_player_x
                    local dy = p.y - game_player_y
                    if (dx*dx + dy*dy) <= (pr + game_package_radius) * (pr + game_package_radius) then
                        table.remove(game_packages, i)
                        game_score = game_score + 10
                    end
                end
                if #game_packages == 0 then
                    local cols, rows = 5, 2
                    for cy = 1, rows do
                        for cx = 1, cols do
                            local gx0 = content_x + (cx - 1) * (wave_w / cols)
                            local gy0 = wave_y + (cy - 1) * (wave_h / rows)
                            local gx1 = content_x + cx * (wave_w / cols)
                            local gy1 = wave_y + cy * (wave_h / rows)
                            local px = gx0 + 8 + math.random() * math.max(1, (gx1 - gx0) - 16)
                            local py = gy0 + 8 + math.random() * math.max(1, (gy1 - gy0) - 16)
                            table.insert(game_packages, { x = px, y = py })
                        end
                    end
                end

                if game_starfield then
                    local gw, gh = math.max(1, wave_w), math.max(1, wave_h)
                    if (game_starfield_w or 0) ~= gw or (game_starfield_h or 0) ~= gh or not game_stars or #game_stars == 0 then
                        game_stars, game_starfield_w, game_starfield_h = {}, gw, gh
                        local n = math.floor((gw * gh) / 8000) -- density
                        n = math.max(60, math.min(400, n))
                        for i = 1, n do
                            local sx = content_x + math.random() * gw
                            local sy = wave_y + math.random() * gh
                            local a = math.random(80, 255) -- alpha
                            local rstar = (math.random() < 0.1) and 1.5 or 1.0
                            table.insert(game_stars, { x = sx, y = sy, a = a, r = rstar })
                        end
                    end
                    r.ImGui_DrawList_AddRectFilled(dl_game, content_x, wave_y, content_x + wave_w, wave_y + wave_h, 0x000000FF)
                        for i = 1, #game_stars do
                            local s = game_stars[i]
                            local col = (0xFFFFFF00 | (s.a & 0xFF))
                            r.ImGui_DrawList_AddCircleFilled(dl_game, s.x, s.y, s.r, col)
                        end
                end

                r.ImGui_DrawList_AddCircleFilled(dl_game, game_player_x, game_player_y, pr, 0xFF3333FF)
                for i = 1, #game_obstacles do
                    local o = game_obstacles[i]
                    r.ImGui_DrawList_AddCircle(dl_game, o.x, o.y, o.r, 0xFFFFFFFF, 16, 2.0)
                end

                for i = 1, #game_packages do
                    local p = game_packages[i]
                    r.ImGui_DrawList_AddCircleFilled(dl_game, p.x, p.y, game_package_radius, 0xFFD24DFF)
                    r.ImGui_DrawList_AddCircle(dl_game, p.x, p.y, game_package_radius, 0x000000AA, 12, 1.0)
                end

                local hud = string.format("Score: %d  |  Time: %.1fs", game_score, game_elapsed or 0)
                r.ImGui_DrawList_AddText(dl_game, content_x + 8, wave_y + 8, 0xFFFFFFFF, hud)
            elseif game_over then
                if game_starfield then
                    r.ImGui_DrawList_AddRectFilled(dl_game, content_x, wave_y, content_x + wave_w, wave_y + wave_h, 0x000000FF)
                    for i = 1, #game_stars do
                        local s = game_stars[i]
                        local col = (0xFFFFFF00 | (s.a & 0xFF))
                        r.ImGui_DrawList_AddCircleFilled(dl_game, s.x, s.y, s.r, col)
                    end
                end
                local txt = string.format("Game Over  |  Score: %d  |  Click Game to retry", game_score)
                local tw, th = r.ImGui_CalcTextSize(ctx, txt)
                local cx = content_x + (wave_w - tw) * 0.5
                local cy = wave_y + (wave_h - th) * 0.5
                r.ImGui_DrawList_AddRectFilled(dl_game, cx - 12, cy - 8, cx + tw + 12, cy + th + 8, 0x000000AA, 6.0)
                r.ImGui_DrawList_AddText(dl_game, cx, cy, 0xFFFFFFFF, txt)
            end
        end

        
        if current_item and current_item_len > 0 then
            local vt0 = view_start
            local vt1 = view_start + view_len
            if show_edit_cursor then
                local edit_t = r.GetCursorPosition()
                if edit_t >= vt0 - 1e-9 and edit_t <= vt1 + 1e-9 then
                    local rel = (edit_t - vt0) / (vt1 - vt0)
                    local gx = content_x + rel * wave_w
                    r.ImGui_DrawList_AddLine(draw_list, gx, canvas_y, gx, wave_y + wave_h, COLOR_CURSOR_LINE, 1.8)
                end
            end
            if show_play_cursor then
                local play_t = r.GetPlayPosition()
                if play_t >= vt0 - 1e-9 and play_t <= vt1 + 1e-9 then
                    local relp = (play_t - vt0) / (vt1 - vt0)
                    local gxp = content_x + relp * wave_w
                    r.ImGui_DrawList_AddLine(draw_list, gxp, canvas_y, gxp, wave_y + wave_h, COLOR_PLAY_CURSOR_LINE, 0.8)
                end
            end
        end
        
    local VARIATION_TEXT = "\239\184\142" -- U+FE0E
    local function MonoIcon(s) return (s or "") .. VARIATION_TEXT end
    local function IconLabel(icon, text)
        return MonoIcon(icon) .. tostring(text or "")
    end

    local function SidebarButton(id, icon, text, width)
        r.ImGui_PushID(ctx, id)
        local pressed = r.ImGui_Button(ctx, "##" .. id, width or 0, 0)
        local minx, miny = r.ImGui_GetItemRectMin(ctx)
        local maxx, maxy = r.ImGui_GetItemRectMax(ctx)
        local dl = r.ImGui_GetWindowDrawList(ctx)

        local icon_str = MonoIcon(icon)
        local iw, ih = r.ImGui_CalcTextSize(ctx, icon_str)
        local tw, th = r.ImGui_CalcTextSize(ctx, tostring(text or ""))

        local ih_y = miny + (maxy - miny - ih) * 0.5
        local th_y = miny + (maxy - miny - th) * 0.5

        local pad_x = 6
        local ix = minx + pad_x

        r.ImGui_DrawList_AddText(dl, ix, ih_y, 0xFFFFFFFF, icon_str)

        local tighten_px = 3
        local tx = ix + iw - tighten_px
        r.ImGui_DrawList_AddText(dl, tx, th_y, 0xFFFFFFFF, tostring(text or ""))

        r.ImGui_PopID(ctx)
        return pressed
    end

    do
            local sb_x = content_x + wave_w + side_gap
            local sb_y = canvas_y
            r.ImGui_DrawList_AddRectFilled(draw_list, sb_x, sb_y, sb_x + sidebar_w, sb_y + avail_h, 0x202020FF)
            r.ImGui_DrawList_AddRect(draw_list, sb_x, sb_y, sb_x + sidebar_w, sb_y + avail_h, 0x333333FF, 4.0, 0, 1.0)

            local handle_pad = 2.0
            local handle_w = math.min(16.0, sidebar_w - handle_pad * 2)
            local handle_h = r.ImGui_GetFrameHeight(ctx)
            local hx = sb_x + handle_pad
            local hy = sb_y + handle_pad
            local glyph = sidebar_collapsed and "<" or ">"
            local dl_icon = r.ImGui_GetWindowDrawList(ctx)
            r.ImGui_DrawList_AddText(dl_icon, hx + 3, hy + 2, 0xFFFFFFFF, glyph)
            r.ImGui_SetCursorScreenPos(ctx, hx, hy)
            r.ImGui_InvisibleButton(ctx, "##sidebar_toggle", handle_w, handle_h)
            if r.ImGui_IsItemClicked(ctx, 0) then
                sidebar_collapsed = not sidebar_collapsed
                SaveSettings()
            end

            if not sidebar_collapsed then
                local child_y = sb_y + handle_h + (handle_pad * 2)
                local child_h = math.max(1.0, avail_h - (child_y - sb_y))

                local side_margin = 8.0                
                local side_spacing = 1.0
                local btn_w = sidebar_w - 2 * side_margin
                local btn_h = r.ImGui_GetFrameHeight(ctx)
                local bottom_margin = 8.0
                local nav_gap = 4.0
                local footer_h = btn_h + bottom_margin

                local scroll_h = math.max(1.0, child_h - footer_h)
                r.ImGui_SetCursorScreenPos(ctx, sb_x, child_y)
                r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ScrollbarSize(), 8.0)
                -- Right sidebar scroll area (no child flags)
                local sb_disabled_active = false
                local scroll_started = r.ImGui_BeginChild(ctx, "RightSidebarScroll", sidebar_w, scroll_h)
                if scroll_started then
                    -- During the mini-game, disable sidebar interactions so arrow keys don't navigate/select
                    if game_active and r.ImGui_BeginDisabled then r.ImGui_BeginDisabled(ctx, true); sb_disabled_active = true end
                    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(),        0x2A2A2AFF)
                    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0x343434FF)
                    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(),  0x1E1E1EFF)
                    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(),          0xFFFFFFFF)

                    r.ImGui_SetCursorPosX(ctx, side_margin)
                    if SidebarButton("info", "ⓘ", info_open and "Info (on)" or "Info", btn_w) then
                        is_interacting = true; last_interaction_time = r.time_precise()
                        info_open = not info_open
                        info_item_guid, info_range_key, info_last_calc = nil, nil, 0.0
                    end
                    r.ImGui_Dummy(ctx, 1, side_spacing)

                    r.ImGui_SetCursorPosX(ctx, side_margin)
                    if SidebarButton("fit_item", "⤢", "Fit item", btn_w) then
                        is_interacting = true; last_interaction_time = r.time_precise()
                        if current_item and current_item_len and current_item_len > 0 then
                            view_start = current_item_start
                            view_len = math.max(1e-6, current_item_len)
                            view_cache_valid = false
                        end
                    end

                    r.ImGui_Dummy(ctx, 1, side_spacing)

                    r.ImGui_SetCursorPosX(ctx, side_margin)
                    if SidebarButton("fit_sel", "⤢⟦⟧", "Fit sel", btn_w) then
                        is_interacting = true; last_interaction_time = r.time_precise()
                        if sel_a and sel_b and current_item then
                            local a = math.max(current_item_start, math.min(sel_a, sel_b))
                            local b = math.min(current_item_start + current_item_len, math.max(sel_a, sel_b))
                            if b > a then
                                view_start = a
                                view_len = math.max(1e-6, b - a)
                                view_cache_valid = false
                            end
                        end
                    end

                    r.ImGui_Dummy(ctx, 1, side_spacing)

                    r.ImGui_SetCursorPosX(ctx, side_margin)
                    if SidebarButton("pencil", "✎", pencil_mode and "Pencil (on)" or "Pencil (off)", btn_w) then
                        is_interacting = true; last_interaction_time = r.time_precise()
                        pencil_mode = not pencil_mode
                        if pencil_mode then
                            if show_env_overlay then show_env_overlay = false end
                            show_dc_overlay = (pencil_target == "dc_offset")
                        else
                            show_dc_overlay = false
                        end
                        SaveSettings()
                    end
                    if r.ImGui_IsItemClicked(ctx, 1) then
                        r.ImGui_OpenPopup(ctx, "PencilTargetMenu")
                    end
                    if r.ImGui_BeginPopup(ctx, "PencilTargetMenu") then
                        local is_dc  = (pencil_target == "dc_offset")
                        local is_eraser = (pencil_target == "eraser")
                        if r.ImGui_MenuItem(ctx, "DC Offset (JSFX)", nil, is_dc, true) then
                            pencil_target = "dc_offset"
                            if pencil_mode then show_dc_overlay = true end
                            SaveSettings()
                        end
                        if r.ImGui_MenuItem(ctx, "Eraser (mute to 0)", nil, is_eraser, true) then
                            pencil_target = "eraser"
                            if pencil_mode then show_dc_overlay = false end
                            SaveSettings()
                        end
                        if is_dc then
                            r.ImGui_Separator(ctx)
                            local prev = dc_link_lr
                            local clicked, state = r.ImGui_MenuItem(ctx, "Link L/R", nil, dc_link_lr, true)
                            if clicked then dc_link_lr = not dc_link_lr; SaveSettings() end
                            r.ImGui_BeginDisabled(ctx, true)
                            r.ImGui_MenuItem(ctx, "- Unlinked: draw in top=Left, bottom=Right", nil, false, true)
                            r.ImGui_EndDisabled(ctx)
                        end
                        r.ImGui_EndPopup(ctx)
                    end
                    if show_tooltips and r.ImGui_IsItemHovered(ctx) then
                        r.ImGui_BeginTooltip(ctx)
                        local tgt = (pencil_target == "dc_offset") and "DC Offset" or "Eraser (mute)"
                        r.ImGui_Text(ctx, "Pencil: " .. tgt .. " (RMB voor keuze)")
                        r.ImGui_EndTooltip(ctx)
                    end

                    r.ImGui_Dummy(ctx, 1, side_spacing)

                    r.ImGui_SetCursorPosX(ctx, side_margin)
            if SidebarButton("envelopes", "∿", show_env_overlay and "Envelope (on)" or "Envelope (off)", btn_w) then
                        is_interacting = true; last_interaction_time = r.time_precise()
                        local newv = not show_env_overlay
                        show_env_overlay = newv
                        if newv then
                    if pencil_mode then pencil_mode = false end
                    if show_dc_overlay then show_dc_overlay = false end
                if current_take and current_item then EnsureActiveTakeEnvelopeVisible(pencil_target, current_take, current_item) end
                        end
                        SaveSettings()
                    end
                    if r.ImGui_IsItemClicked(ctx, 1) then
                        r.ImGui_OpenPopup(ctx, "EnvelopesMenu")
                    end
                    if r.ImGui_BeginPopup(ctx, "EnvelopesMenu") then
                        local is_draw_vol = (pencil_target == "item_vol")
                        local is_draw_pan = (pencil_target == "item_pan")
                        if r.ImGui_MenuItem(ctx, "Draw: Item Volume (take envelope)", nil, is_draw_vol, true) then
                            pencil_target = "item_vol"
                            pencil_mode = false
                            if not show_env_overlay then show_env_overlay = true end
                            if current_take and current_item then EnsureActiveTakeEnvelopeVisible(pencil_target, current_take, current_item) end
                            SaveSettings()
                        end
                        if r.ImGui_MenuItem(ctx, "Draw: Pan (take envelope)", nil, is_draw_pan, true) then
                            pencil_target = "item_pan"
                            pencil_mode = false
                            if not show_env_overlay then show_env_overlay = true end
                            if current_take and current_item then EnsureActiveTakeEnvelopeVisible(pencil_target, current_take, current_item) end
                            SaveSettings()
                        end
                        r.ImGui_Separator(ctx)
                        if r.ImGui_MenuItem(ctx, "Show volume points (experimental)", nil, show_vol_points, is_draw_vol) then
                            show_vol_points = not show_vol_points
                            SaveSettings()
                        end
                        r.ImGui_EndPopup(ctx)
                    end
                    if show_tooltips and r.ImGui_IsItemHovered(ctx) then
                        r.ImGui_BeginTooltip(ctx)
                        local t = (pencil_target == "item_pan") and "Pan" or "Volume"
                        r.ImGui_Text(ctx, "Toggle take " .. t .. " envelope overlay")
                        r.ImGui_EndTooltip(ctx)
                    end

                    r.ImGui_Dummy(ctx, 1, side_spacing)

                    r.ImGui_SetCursorPosX(ctx, side_margin)
                    if SidebarButton("cut", "✄", "Cut", btn_w) then
                        is_interacting = true; last_interaction_time = r.time_precise()
                        r.Undo_BeginBlock()
                        local target = CutSelectionWithinItem(ripple_item)
                        if current_accessor then r.DestroyAudioAccessor(current_accessor); current_accessor = nil end
                        peak_pyr = nil
                        current_item = target or current_item
                        is_loaded = false; LoadPeaks(target)
                        r.Undo_EndBlock("RAW: Cut selection", -1)
                    end

                    r.ImGui_Dummy(ctx, 1, side_spacing)

                    r.ImGui_SetCursorPosX(ctx, side_margin)
                    if SidebarButton("split", "⎮", "Split", btn_w) then
                        is_interacting = true; last_interaction_time = r.time_precise()
                        r.Undo_BeginBlock()
                        if current_item then
                            local s,e = GetSelectionRangeClamped()
                            if s then
                                r.SelectAllMediaItems(0, false)
                                r.SplitMediaItem(current_item, e)
                                local left_item = r.SplitMediaItem(current_item, s)
                                if left_item then r.SetMediaItemSelected(left_item, true) end
                            else
                                local t = r.GetCursorPosition()
                                if t and current_item_start and current_item_len and t > current_item_start and t < (current_item_start + current_item_len) then
                                    local right = r.SplitMediaItem(current_item, t)
                                    r.SelectAllMediaItems(0, false)
                                    if right then r.SetMediaItemSelected(right, true) else r.SetMediaItemSelected(current_item, true) end
                                end
                            end
                            local sel_n = r.CountSelectedMediaItems(0)
                            local target = sel_n > 0 and r.GetSelectedMediaItem(0, sel_n - 1) or nil
                            if current_accessor then r.DestroyAudioAccessor(current_accessor); current_accessor = nil end
                            peak_pyr = nil
                            is_loaded = false; LoadPeaks(target)
                        end
                        r.Undo_EndBlock("RAW: Split", -1)
                    end

                    r.ImGui_Dummy(ctx, 1, side_spacing)

                    r.ImGui_SetCursorPosX(ctx, side_margin)
                    if SidebarButton("trim", "⟦⟧", "Trim", btn_w) then
                        is_interacting = true; last_interaction_time = r.time_precise()
                        r.Undo_BeginBlock()
                        local target = TrimItemToSelection()
                        if current_accessor then r.DestroyAudioAccessor(current_accessor); current_accessor = nil end
                        peak_pyr = nil
                        current_item = target or current_item
                        is_loaded = false; LoadPeaks(target)
                        r.Undo_EndBlock("RAW: Trim to selection", -1)
                    end

                    r.ImGui_Dummy(ctx, 1, side_spacing)

                    r.ImGui_SetCursorPosX(ctx, side_margin)
                    if SidebarButton("join", "⤳", "Join", btn_w) then
                        is_interacting = true; last_interaction_time = r.time_precise()
                        local target = JoinAllTouching()
                        if target then
                            if current_accessor then r.DestroyAudioAccessor(current_accessor); current_accessor = nil end
                            peak_pyr = nil
                            current_item = target or current_item
                            is_loaded = false; LoadPeaks(target)
                        end
                    end

                    r.ImGui_Dummy(ctx, 1, side_spacing)

                    r.ImGui_SetCursorPosX(ctx, side_margin)
                    if SidebarButton("glue", "⊕", "Glue", btn_w) then
                        is_interacting = true; last_interaction_time = r.time_precise()
                        local target = GlueExecute()
                        if target then
                            if current_accessor then r.DestroyAudioAccessor(current_accessor); current_accessor = nil end
                            peak_pyr = nil
                            current_item = target or current_item
                            is_loaded = false; LoadPeaks(target)
                        end
                    end

                    r.ImGui_Dummy(ctx, 1, side_spacing)

                    r.ImGui_SetCursorPosX(ctx, side_margin)
                    if SidebarButton("normalize", "⤒", "Normalize", btn_w) then
                        is_interacting = true; last_interaction_time = r.time_precise()
                        NormalizeItemWhole()
                    end

                    r.ImGui_Dummy(ctx, 1, side_spacing)

                    r.ImGui_SetCursorPosX(ctx, side_margin)
                    if SidebarButton("normsel", "⤒", "Norm sel", btn_w) then
                        is_interacting = true; last_interaction_time = r.time_precise()
                        NormalizeSelectionWithinItem()
                    end

                    r.ImGui_Dummy(ctx, 1, side_spacing)

                    r.ImGui_SetCursorPosX(ctx, side_margin)
                    if SidebarButton("reverse", "↔", "Reverse", btn_w) then
                        is_interacting = true; last_interaction_time = r.time_precise()
                        ReverseItemWhole()
                    end

                    r.ImGui_Dummy(ctx, 1, side_spacing)

                    r.ImGui_SetCursorPosX(ctx, side_margin)
                    if SidebarButton("revsel", "↔", "Rev sel", btn_w) then
                        is_interacting = true; last_interaction_time = r.time_precise()
                        ReverseSelectionWithinItem()
                    end

                    r.ImGui_Dummy(ctx, 1, side_spacing)
                    r.ImGui_SetCursorPosX(ctx, side_margin)
                    do
                        local phase_on = current_item and IsItemPolarityInverted(current_item)
                        if SidebarButton("phase", "Ø", phase_on and "Phase (on)" or "Phase", btn_w) then
                            is_interacting = true; last_interaction_time = r.time_precise()
                            ToggleItemPolarity()
                        end
                    end

                    r.ImGui_Dummy(ctx, 1, side_spacing)
                    r.ImGui_SetCursorPosX(ctx, side_margin)
                    if SidebarButton("phasesel", "Ø", "Phase sel", btn_w) then
                        is_interacting = true; last_interaction_time = r.time_precise()
                        ToggleSelectionPolarity()
                    end

                    r.ImGui_Dummy(ctx, 1, side_spacing)
                    if sb_disabled_active and r.ImGui_EndDisabled then r.ImGui_EndDisabled(ctx); sb_disabled_active = false end
                    r.ImGui_SetCursorPosX(ctx, side_margin)
                    if SidebarButton("game_play", "🎮", "Play", btn_w) then
                        is_interacting = true; last_interaction_time = r.time_precise()
                        game_active = not game_active
                        game_over = false
                        if game_active then
                            game_score = 0
                            game_obstacles = {}
                            game_spawn_cooldown = 0.0
                            game_last_time = nil 
                            game_elapsed = 0.0
                        end
                    end
                    if r.ImGui_IsItemClicked(ctx, 1) then
                        r.ImGui_OpenPopup(ctx, "GameMenu")
                    end
                    if r.ImGui_BeginPopup(ctx, "GameMenu") then
                        if r.ImGui_MenuItem(ctx, "Starfield background", nil, game_starfield, true) then
                            game_starfield = not game_starfield
                            SaveSettings()
                        end
                        r.ImGui_EndPopup(ctx)
                    end
                    if game_active and r.ImGui_BeginDisabled and not sb_disabled_active then r.ImGui_BeginDisabled(ctx, true); sb_disabled_active = true end

                    r.ImGui_PopStyleColor(ctx, 4)
                end
                if scroll_started then
                    if sb_disabled_active and r.ImGui_EndDisabled then r.ImGui_EndDisabled(ctx) end
                    r.ImGui_EndChild(ctx)
                end
                r.ImGui_PopStyleVar(ctx) -- ScrollbarSize

                do
                    local label = nil
                    if show_env_overlay then
                        local env_label = (pencil_target == "item_pan") and "Take Pan" or "Take Volume"
                        label = (MonoIcon and MonoIcon("∿") or "∿") .. " Envelope: " .. env_label
                    elseif pencil_mode then
                        local tgt = (pencil_target == "dc_offset") and "DC Offset" or ((pencil_target == "eraser") and "Eraser" or "")
                        label = (MonoIcon and MonoIcon("✎") or "✎") .. " Pencil: " .. tgt
                    end
                    if label then
                        local tw, th = r.ImGui_CalcTextSize(ctx, label)
                        local pad_x, pad_y = 6.0, 4.0
                        local inset = 6.0
                        local rx1 = content_x + wave_w - (tw + 2 * pad_x) - inset
                        local ry1 = wave_y + inset
                        local rx2 = rx1 + tw + 2 * pad_x
                        local ry2 = ry1 + th + 2 * pad_y
                        local bg = 0x00000099
                        local fg = 0xFFFFFFFF
                        r.ImGui_DrawList_AddRectFilled(draw_list, rx1, ry1, rx2, ry2, bg, 6.0)
                        r.ImGui_DrawList_AddRect(draw_list, rx1, ry1, rx2, ry2, fg, 6.0, 0, 1.0)
                        r.ImGui_DrawList_AddText(draw_list, rx1 + pad_x, ry1 + pad_y, fg, label)
                    end
                end

                local footer_y = child_y + scroll_h
                local dl_sb = r.ImGui_GetWindowDrawList(ctx)
                r.ImGui_DrawList_AddRectFilled(dl_sb, sb_x, footer_y, sb_x + sidebar_w, sb_y + avail_h, 0x202020FF)
                r.ImGui_DrawList_AddLine(dl_sb, sb_x, footer_y, sb_x + sidebar_w, footer_y, 0x333333FF, 1.0)

                r.ImGui_SetCursorScreenPos(ctx, sb_x, footer_y)
                local footer_started = r.ImGui_BeginChild(ctx, "RightSidebarFooter", sidebar_w, math.max(1.0, (sb_y + avail_h) - footer_y))
                local foot_disable_scope = false
                if footer_started then
                    if game_active and r.ImGui_BeginDisabled then r.ImGui_BeginDisabled(ctx, true); foot_disable_scope = true end
                    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(),        0x2A2A2AFF)
                    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0x343434FF)
                    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(),  0x1E1E1EFF)
                    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(),          0xFFFFFFFF)

                    local nav_w = (btn_w - 3 * nav_gap)
                    local each = nav_w / 4.0
                    r.ImGui_SetCursorPosX(ctx, side_margin)
                    if r.ImGui_Button(ctx, MonoIcon("←"), each, 0) then
                        is_interacting = true; last_interaction_time = r.time_precise()
                        GotoPrevItemOnTrack()
                    end
                    r.ImGui_SameLine(ctx, 0.0, nav_gap)
                    if r.ImGui_Button(ctx, MonoIcon("↓"), each, 0) then
                        is_interacting = true; last_interaction_time = r.time_precise()
                        GotoFirstItemOnAdjacentTrack(1)
                    end
                    r.ImGui_SameLine(ctx, 0.0, nav_gap)
                    if r.ImGui_Button(ctx, MonoIcon("↑"), each, 0) then
                        is_interacting = true; last_interaction_time = r.time_precise()
                        GotoFirstItemOnAdjacentTrack(-1)
                    end
                    r.ImGui_SameLine(ctx, 0.0, nav_gap)
                    if r.ImGui_Button(ctx, MonoIcon("→"), each, 0) then
                        is_interacting = true; last_interaction_time = r.time_precise()
                        GotoNextItemOnTrack()
                    end

                    if foot_disable_scope and r.ImGui_EndDisabled then r.ImGui_EndDisabled(ctx) end
                    r.ImGui_PopStyleColor(ctx, 4)
                end
                if footer_started then r.ImGui_EndChild(ctx) end
            end
        end

    if show_footer then r.ImGui_SetCursorScreenPos(ctx, canvas_x, canvas_y + avail_h + 4) end
    local base = string.format("Canvas: %.0fx%.0f | Loaded: %s |", wave_w, avail_h, is_loaded and "Yes" or "No")
    local zf = 1.0
    if current_item and current_item_len > 0 and view_len > 0 then zf = current_item_len / view_len end
    local dl_foot = r.ImGui_GetWindowDrawList(ctx)
    local fx, fy = r.ImGui_GetCursorScreenPos(ctx)
    local avail_w_foot = select(1, r.ImGui_GetContentRegionAvail(ctx)) or 0
    local spacing = 8.0
    if show_footer and current_item then
        local tech_left = base
        local cov_txt = ""
        if spectral_peaks then
            local pct = math.floor((view_cache_cov or 0) * 100 + 0.5)
            cov_txt = string.format(" | Spectral: %d%%", pct)
        end
        dbg_sec_per_px = (view_len > 0 and wave_w > 0) and (view_len / math.max(1, math.floor(wave_w + 0.5))) or nil
        local dbg_txt = ""
        if dbg_sec_per_px then
            local spp_ms = dbg_sec_per_px * 1000.0
            local pyr = (dbg_view_bins_needed and dbg_pyr_level_bins) and string.format(" | Pyr: need %d → %d", dbg_view_bins_needed or 0, dbg_pyr_level_bins or 0) or ""
            local sp = (spectral_peaks and dbg_spectral_sr) and string.format(" | SpecSR: %.0fHz (%s, ~%dk)", dbg_spectral_sr or 0, dbg_spectral_capped and "cap" or "free", math.floor((dbg_spectral_total or 0)/1000+0.5)) or ""
            dbg_txt = string.format(" | Span: %.2fs | %.2f ms/px%s%s", view_len or 0, spp_ms, pyr, sp)
        end
        local zoom_label = string.format(" | Zoom: %.2fx%s%s", zf, cov_txt, dbg_txt)
        local right_text = string.format("Item: %s | SR: %.0f Hz | Ch: %d", filename, sample_rate, channels)
        local zw, zh = r.ImGui_CalcTextSize(ctx, zoom_label)
        local rw, rh = r.ImGui_CalcTextSize(ctx, right_text)
        local lh = math.max(zh, rh)
        local spacing_zoom = 8.0
        local left_space = math.max(0.0, (avail_w_foot or 0) - rw - spacing)
        local left_text_space = math.max(0.0, left_space - zw - spacing_zoom)
        r.ImGui_DrawList_PushClipRect(dl_foot, fx, fy, fx + left_text_space, fy + lh, true)
        r.ImGui_DrawList_AddText(dl_foot, fx, fy, 0xFFFFFFFF, tech_left)
        r.ImGui_DrawList_PopClipRect(dl_foot)
        r.ImGui_SetCursorScreenPos(ctx, fx + left_text_space + spacing_zoom, fy)
        local zx, zy = r.ImGui_GetCursorScreenPos(ctx)
        r.ImGui_Text(ctx, zoom_label)
        local tw, th = r.ImGui_CalcTextSize(ctx, zoom_label)
        r.ImGui_SetCursorScreenPos(ctx, zx, zy)
        r.ImGui_InvisibleButton(ctx, "zoom_info_btn", tw, th)
        if r.ImGui_IsItemHovered(ctx) and show_tooltips then
            r.ImGui_BeginTooltip(ctx)
            r.ImGui_Text(ctx, "Klik om zoom te resetten")
            r.ImGui_EndTooltip(ctx)
        end
        if r.ImGui_IsItemClicked(ctx, 0) and current_item_len > 0 then
            is_interacting = true; last_interaction_time = r.time_precise()
            view_start = current_item_start
            view_len = current_item_len
            amp_zoom = 1.0
        end
        local rx = fx + (avail_w_foot or 0) - rw
        if rx < fx + left_space + spacing then rx = fx + left_space + spacing end
        r.ImGui_DrawList_AddText(dl_foot, rx, fy, 0xFFFFFFFF, right_text)
        if show_footer then
            r.ImGui_SetCursorScreenPos(ctx, fx, fy)
            r.ImGui_Dummy(ctx, avail_w_foot or 0, lh)
        end
    elseif show_footer then
        local left_text = base .. " | No item selected"
        local lw, lh = r.ImGui_CalcTextSize(ctx, left_text)
        r.ImGui_DrawList_PushClipRect(dl_foot, fx, fy, fx + (avail_w_foot or 0), fy + lh, true)
        r.ImGui_DrawList_AddText(dl_foot, fx, fy, 0xFFFFFFFF, left_text)
        r.ImGui_DrawList_PopClipRect(dl_foot)
    r.ImGui_Dummy(ctx, avail_w_foot, lh)
    end
    end
    
    if visible then r.ImGui_End(ctx) end

    r.ImGui_PopStyleColor(ctx, 3)

    local now = r.time_precise()
    if is_interacting and (now - last_interaction_time) > INTERACTION_GRACE then
        is_interacting = false
    end
    
    if open then
        r.defer(Loop)
    else
        if font then
            r.ImGui_Detach(ctx, font)
        end
        if font_big then
            r.ImGui_Detach(ctx, font_big)
        end
    if current_accessor then r.DestroyAudioAccessor(current_accessor) current_accessor = nil end
    SaveSettings()
    end
end
r.defer(Loop)
