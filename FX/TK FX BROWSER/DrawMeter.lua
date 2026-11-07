local M = {}
-- tst
function normalizePath(path)
    local sep = package.config:sub(1,1) 
    return path:gsub("[/\\]", sep)
end

function findJSLoudnessMeter(r)
    local master = r.GetMasterTrack(0)
    local meter_patterns = {
        "js[%s%-_]?analysis[/\\]loudness_meter",
        "js.*loudness.*meter",
        "loudness.*meter"
    }
    
    local monitor_fx_count = r.TrackFX_GetRecCount(master)
    for i = 0, monitor_fx_count - 1 do
        local _, fx_name = r.TrackFX_GetFXName(master, 0x1000000 + i, "")
        for _, pattern in ipairs(meter_patterns) do
            if fx_name:lower():match(pattern) then
                return i
            end
        end
    end
    return -1
end

function initializeLoudnessMeter(r)
    local master = r.GetMasterTrack(0)
    local meter_idx = findJSLoudnessMeter(r)
    
    if meter_idx == -1 then
        local paths = {
            "JS: analysis/loudness_meter",
            "JS/analysis/loudness_meter",
            "JS: Loudness Meter",
            "JS: Analysis/Loudness Meter"
        }
        
        for _, path in ipairs(paths) do
            meter_idx = r.TrackFX_AddByName(master, path, true, -1)
            if meter_idx >= 0 then break end
        end
    end
    
    if meter_idx >= 0 then
        r.TrackFX_SetEnabled(master, 0x1000000 + meter_idx, true)
        r.defer(function() end)
    end
    
    return meter_idx
end

function loadJSLoudnessMeter(r)
    local master = r.GetMasterTrack(0)
    local meter_idx = initializeLoudnessMeter(r)
    
    if meter_idx >= 0 then
        r.TrackFX_Show(master, 0x1000000 + meter_idx, 2)
    end
end

-- Values from REAPER's "Loudness Meter Peak/RMS/LUFS (Cockos)" on the
-- master's monitoring FX (R, L and L-S/LRA modes; Peak reads the track).
-- The meter is found by its display name (findJSLoudnessMeter), and its
-- output parameters by their own names: the meter's parameter numbers moved
-- when Cockos added sliders, and fixed numbers then read the wrong value
-- (RMS-M showed the peak, and so on) - while matching the file name against
-- the display name never found the meter at all, so every value was -100.
local LOUDNESS_PARAMS = {
    rms_m = "RMS-M (output)", rms_i = "RMS-I (output)",
    lufs_m = "LUFS-M (output)", lufs_s = "LUFS-S (output)", lufs_i = "LUFS-I (output)",
    lra = "LRA (output)",
}
local loudness_cache = { fx = nil, params = nil }

local function readLoudness(r)
    local master = r.GetMasterTrack(0)
    local idx = findJSLoudnessMeter(r)
    if idx < 0 then return nil end
    local fx = 0x1000000 + idx
    if loudness_cache.fx ~= fx or not loudness_cache.params then
        local params = {}
        for p = 0, r.TrackFX_GetNumParams(master, fx) - 1 do
            local _, name = r.TrackFX_GetParamName(master, fx, p)
            -- A hidden JSFX slider is declared with a leading "-"; compare
            -- without it in case REAPER passes it on.
            name = (name or ""):gsub("^%-", ""):match("^%s*(.-)%s*$")
            for key, wanted in pairs(LOUDNESS_PARAMS) do
                if name == wanted then params[key] = p end
            end
        end
        -- Nothing found: do not keep that, look again next frame.
        loudness_cache.fx, loudness_cache.params = fx, next(params) and params or nil
        if not loudness_cache.params then return nil end
    end
    local out = {}
    for key, p in pairs(loudness_cache.params) do
        local v = r.TrackFX_GetParam(master, fx, p)
        out[key] = v
    end
    return out
end

function M.DrawMeter(r, ctx, config, TRACK, TinyFont)
    if not TRACK then return end
    local current_time = r.time_precise()
    
    peak_hold_L = peak_hold_L or -60
    peak_hold_R = peak_hold_R or -60
    rms_m_hold = rms_m_hold or -60
    rms_i_hold = rms_i_hold or -60
    lufs_m_hold = lufs_m_hold or -60
    lufs_i_hold = lufs_i_hold or -60
    lufs_s_hold = lufs_s_hold or -60
    lra_hold = lra_hold or -60
    peak_hold_time_L = peak_hold_time_L or 0
    peak_hold_time_R = peak_hold_time_R or 0
    rms_m_hold_time = rms_m_hold_time or 0
    rms_i_hold_time = rms_i_hold_time or 0
    lufs_m_hold_time = lufs_m_hold_time or 0
    lufs_i_hold_time = lufs_i_hold_time or 0
    lufs_s_hold_time = lufs_s_hold_time or 0
    lra_hold_time = lra_hold_time or 0
    PEAK_HOLD_DURATION = 2.0
    -- Integrated values and LRA describe the run since play started. With the
    -- transport stopped they are shown empty ("--") instead of the last run's
    -- result, until the next play starts a new measurement. Paused counts as
    -- running: playing on continues the same measurement.
    local transport_stopped = r.GetPlayState() == 0

    local function scaleTodB(peak)
        if peak < 0.001 then return -60.0 end
        return 20 * math.log(peak, 10)
    end

    local function getRMSValues()
        local v = readLoudness(r)
        if not v then return -100, -100 end
        return v.rms_m or -100, v.rms_i or -100
    end
    local function getLUFSValues()
        local v = readLoudness(r)
        if not v then return -100, -100, -100, -100 end
        return v.lufs_m or -100, v.lufs_i or -100, v.lufs_s or -100, v.lra or 0
    end

    local meter_height = 90
    local margin = 5
    local meter_offset = 8
    local line_length = 3
    local peak_text_width = 45

    if r.ImGui_BeginChild(ctx, "MeterSection", -1, meter_height) then
        local window_width = r.ImGui_GetWindowWidth(ctx)
        local meter_width = window_width - (margin * 2)
        local meter_bar_height = 15
        
        local function drawMeterSegments(x, y, width, height, db_value, is_rms, color)
        local draw_list = r.ImGui_GetWindowDrawList(ctx)
            if is_rms then
                -- Gebruik de meegegeven kleur of standaard blauw
                local meter_color = color or 0x0088FFFF
                local current_pos = x + ((db_value + 60) / 60) * width
                r.ImGui_DrawList_AddRectFilled(draw_list, x, y, current_pos, y + height, meter_color)
            else
                -- Normale peak meter met kleur segmenten
                local pos_minus18 = x + (((-18) + 60) / 60) * width
                local pos_minus4 = x + (((-4) + 60) / 60) * width
                local pos_zero = x + ((0 + 60) / 60) * width
                local current_pos = x + ((db_value + 60) / 60) * width
                
                r.ImGui_DrawList_AddRectFilled(draw_list, x, y, math.min(current_pos, pos_minus18), y + height, 0x00FF00FF)
                if db_value > -18 then
                    r.ImGui_DrawList_AddRectFilled(draw_list, pos_minus18, y, math.min(current_pos, pos_minus4), y + height, 0xFFFF00FF)
                end
                if db_value > -4 then
                    r.ImGui_DrawList_AddRectFilled(draw_list, pos_minus4, y, math.min(current_pos, pos_zero), y + height, 0xFF8C00FF)
                end
                if db_value > 0 then
                    r.ImGui_DrawList_AddRectFilled(draw_list, pos_zero, y, current_pos, y + height, 0xFF0000FF)
                end
            end
        end
        r.ImGui_PushFont(ctx, TinyFont, 9)
        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FramePadding(), 0, 0)
        -- meter_type
        if not config.meter_type then 
            config.meter_type = 1
            config.show_rms_meter = false
            config.show_lufs_meter = false
            config.show_lufs_slra_meter = false
        end
        -- meter selectie
        if r.ImGui_RadioButton(ctx, "P", config.meter_type == 1) then
            config.meter_type = 1
            config.show_rms_meter = false
            config.show_lufs_meter = false
            config.show_lufs_slra_meter = false
        end
        r.ImGui_SameLine(ctx)
        if r.ImGui_RadioButton(ctx, "R", config.meter_type == 2) then
            config.meter_type = 2
            config.show_rms_meter = true
            config.show_lufs_meter = false
            config.show_lufs_slra_meter = false
            loadJSLoudnessMeter(r)
        end
        r.ImGui_SameLine(ctx)
        if r.ImGui_RadioButton(ctx, "L", config.meter_type == 3) then
            config.meter_type = 3
            config.show_rms_meter = false
            config.show_lufs_meter = true
            config.show_lufs_slra_meter = false
            loadJSLoudnessMeter(r)
        end
        r.ImGui_SameLine(ctx)
        if r.ImGui_RadioButton(ctx, "L-S/LRA", config.meter_type == 4) then
            config.meter_type = 4
            config.show_rms_meter = false
            config.show_lufs_meter = false
            config.show_lufs_slra_meter = true
            loadJSLoudnessMeter(r)
        end
        r.ImGui_PopStyleVar(ctx)
        r.ImGui_Separator(ctx)
        if config.show_rms_meter then
            -- RMS meters
            local rms_M, rms_I = getRMSValues()
            if transport_stopped then rms_I = -100; rms_i_hold = -60 end

            if rms_M > rms_m_hold then
                rms_m_hold = rms_M
                rms_m_hold_time = current_time
            elseif current_time - rms_m_hold_time > PEAK_HOLD_DURATION then
                rms_m_hold = rms_M
            end
            -- RMS-M (Momentary)
            r.ImGui_SetNextItemWidth(ctx, 80)
            r.ImGui_Text(ctx, string.format("Master RMS-M: %.1f dB", rms_M))
            if rms_m_hold > -60 then
                r.ImGui_SameLine(ctx, meter_width - peak_text_width)
                r.ImGui_Text(ctx, string.format("%.1f", rms_m_hold))
            end
            local meter_pos_x, meter_pos_y = r.ImGui_GetCursorScreenPos(ctx)
            meter_pos_x = meter_pos_x + meter_offset
            drawMeterSegments(meter_pos_x, meter_pos_y, meter_width - meter_offset, meter_bar_height, rms_M, true)
            local scale_points = {0, -12, -24, -36, -48, -60}
            local draw_list = r.ImGui_GetWindowDrawList(ctx)
            local text_color = r.ImGui_ColorConvertDouble4ToU32(config.text_gray/255, config.text_gray/255, config.text_gray/255, 1)
            for _, db in ipairs(scale_points) do
                local x_pos = meter_pos_x + ((db + 60) / 60) * (meter_width - meter_offset)
                r.ImGui_DrawList_AddLine(draw_list, x_pos, meter_pos_y, x_pos, meter_pos_y + line_length, text_color)
                r.ImGui_DrawList_AddLine(draw_list, x_pos, meter_pos_y + meter_bar_height - line_length, x_pos, meter_pos_y + meter_bar_height, text_color)
                r.ImGui_DrawList_AddText(draw_list, x_pos - 8, meter_pos_y + (meter_bar_height - r.ImGui_GetFontSize(ctx))/2, text_color, tostring(db))
            end
            r.ImGui_Dummy(ctx, meter_width, meter_bar_height)
            
            -- RMS-I (Integrated)
            if rms_I > rms_i_hold then
                rms_i_hold = rms_I
                rms_i_hold_time = current_time
            elseif current_time - rms_i_hold_time > PEAK_HOLD_DURATION then
                rms_i_hold = rms_I
            end
            r.ImGui_SetNextItemWidth(ctx, 80)
            r.ImGui_Text(ctx, transport_stopped and "Master RMS-I: --" or string.format("Master RMS-I: %.1f dB", rms_I))
            if rms_i_hold > -60 then
                r.ImGui_SameLine(ctx, meter_width - peak_text_width)
                r.ImGui_Text(ctx, string.format("%.1f", rms_i_hold))
            end
            meter_pos_x, meter_pos_y = r.ImGui_GetCursorScreenPos(ctx)
            meter_pos_x = meter_pos_x + meter_offset
            drawMeterSegments(meter_pos_x, meter_pos_y, meter_width - meter_offset, meter_bar_height, rms_I, true)
            local scale_points = {0, -12, -24, -36, -48, -60}
            local draw_list = r.ImGui_GetWindowDrawList(ctx)
            local text_color = r.ImGui_ColorConvertDouble4ToU32(config.text_gray/255, config.text_gray/255, config.text_gray/255, 1)
            for _, db in ipairs(scale_points) do
                local x_pos = meter_pos_x + ((db + 60) / 60) * (meter_width - meter_offset)
                r.ImGui_DrawList_AddLine(draw_list, x_pos, meter_pos_y, x_pos, meter_pos_y + line_length, text_color)
                r.ImGui_DrawList_AddLine(draw_list, x_pos, meter_pos_y + meter_bar_height - line_length, x_pos, meter_pos_y + meter_bar_height, text_color)
                r.ImGui_DrawList_AddText(draw_list, x_pos - 8, meter_pos_y + (meter_bar_height - r.ImGui_GetFontSize(ctx))/2, text_color, tostring(db))
            end
            r.ImGui_Dummy(ctx, meter_width, meter_bar_height)

            elseif config.show_lufs_meter then
                local lufs_M, lufs_I = getLUFSValues()
                if transport_stopped then lufs_I = -100; lufs_i_hold = -60 end
                if lufs_M and lufs_I then
                    if lufs_M > lufs_m_hold then
                        lufs_m_hold = lufs_M
                        lufs_m_hold_time = current_time
                    elseif current_time - lufs_m_hold_time > PEAK_HOLD_DURATION then
                        lufs_m_hold = lufs_M
                    end
                    -- LUFS-M (Momentary)
                    r.ImGui_SetNextItemWidth(ctx, 80)
                    r.ImGui_Text(ctx, string.format("Master LUFS-M: %.1f", lufs_M))
                    if lufs_m_hold > -60 then
                        r.ImGui_SameLine(ctx, meter_width - peak_text_width)
                        r.ImGui_Text(ctx, string.format("%.1f", lufs_m_hold))
                    end
                local meter_pos_x, meter_pos_y = r.ImGui_GetCursorScreenPos(ctx)
                meter_pos_x = meter_pos_x + meter_offset
                drawMeterSegments(meter_pos_x, meter_pos_y, meter_width - meter_offset, meter_bar_height, lufs_M, true, 0xFF8C00FF)
                local scale_points = {0, -12, -24, -36, -48, -60}
                local draw_list = r.ImGui_GetWindowDrawList(ctx)
                local text_color = r.ImGui_ColorConvertDouble4ToU32(config.text_gray/255, config.text_gray/255, config.text_gray/255, 1)
                for _, db in ipairs(scale_points) do
                    local x_pos = meter_pos_x + ((db + 60) / 60) * (meter_width - meter_offset)
                    r.ImGui_DrawList_AddLine(draw_list, x_pos, meter_pos_y, x_pos, meter_pos_y + line_length, text_color)
                    r.ImGui_DrawList_AddLine(draw_list, x_pos, meter_pos_y + meter_bar_height - line_length, x_pos, meter_pos_y + meter_bar_height, text_color)
                    r.ImGui_DrawList_AddText(draw_list, x_pos - 8, meter_pos_y + (meter_bar_height - r.ImGui_GetFontSize(ctx))/2, text_color, tostring(db))
                end
                r.ImGui_Dummy(ctx, meter_width, meter_bar_height)
                
                -- LUFS-I (Integrated)
                if lufs_I > lufs_i_hold then
                    lufs_i_hold = lufs_I
                    lufs_i_hold_time = current_time
                elseif current_time - lufs_i_hold_time > PEAK_HOLD_DURATION then
                    lufs_i_hold = lufs_I
                end
                r.ImGui_SetNextItemWidth(ctx, 80)
                r.ImGui_Text(ctx, transport_stopped and "Master LUFS-I: --" or string.format("Master LUFS-I: %.1f", lufs_I))
                if lufs_i_hold > -60 then
                    r.ImGui_SameLine(ctx, meter_width - peak_text_width)
                    r.ImGui_Text(ctx, string.format("%.1f", lufs_i_hold))
                end
                meter_pos_x, meter_pos_y = r.ImGui_GetCursorScreenPos(ctx)
                meter_pos_x = meter_pos_x + meter_offset
                drawMeterSegments(meter_pos_x, meter_pos_y, meter_width - meter_offset, meter_bar_height, lufs_I, true, 0xFF8C00FF)
                for _, db in ipairs(scale_points) do
                    local x_pos = meter_pos_x + ((db + 60) / 60) * (meter_width - meter_offset)
                    r.ImGui_DrawList_AddLine(draw_list, x_pos, meter_pos_y, x_pos, meter_pos_y + line_length, text_color)
                    r.ImGui_DrawList_AddLine(draw_list, x_pos, meter_pos_y + meter_bar_height - line_length, x_pos, meter_pos_y + meter_bar_height, text_color)
                    r.ImGui_DrawList_AddText(draw_list, x_pos - 8, meter_pos_y + (meter_bar_height - r.ImGui_GetFontSize(ctx))/2, text_color, tostring(db))
                end
            end
            r.ImGui_Dummy(ctx, meter_width, meter_bar_height)
            elseif config.show_lufs_slra_meter then
            local _, _, lufs_S, lufs_LRA = getLUFSValues()
            if transport_stopped and lufs_LRA then lufs_LRA = 0; lra_hold = -60 end
            if lufs_S and lufs_LRA then
                -- LUFS-S
                if lufs_S > lufs_s_hold then
                    lufs_s_hold = lufs_S
                    lufs_s_hold_time = current_time
                elseif current_time - lufs_s_hold_time > PEAK_HOLD_DURATION then
                    lufs_s_hold = lufs_S
                end
                r.ImGui_SetNextItemWidth(ctx, 80)
                r.ImGui_Text(ctx, string.format("Master LUFS-S: %.1f", lufs_S))
                if lufs_s_hold > -60 then
                    r.ImGui_SameLine(ctx, meter_width - peak_text_width)
                    r.ImGui_Text(ctx, string.format("%.1f", lufs_s_hold))
                end
                local meter_pos_x, meter_pos_y = r.ImGui_GetCursorScreenPos(ctx)
                meter_pos_x = meter_pos_x + meter_offset
                drawMeterSegments(meter_pos_x, meter_pos_y, meter_width - meter_offset, meter_bar_height, lufs_S, true, 0xFF8C00FF)
                local scale_points = {0, -12, -24, -36, -48, -60}
                local draw_list = r.ImGui_GetWindowDrawList(ctx)
                local text_color = r.ImGui_ColorConvertDouble4ToU32(config.text_gray/255, config.text_gray/255, config.text_gray/255, 1)
                for _, db in ipairs(scale_points) do
                    local x_pos = meter_pos_x + ((db + 60) / 60) * (meter_width - meter_offset)
                    r.ImGui_DrawList_AddLine(draw_list, x_pos, meter_pos_y, x_pos, meter_pos_y + line_length, text_color)
                    r.ImGui_DrawList_AddLine(draw_list, x_pos, meter_pos_y + meter_bar_height - line_length, x_pos, meter_pos_y + meter_bar_height, text_color)
                    r.ImGui_DrawList_AddText(draw_list, x_pos - 8, meter_pos_y + (meter_bar_height - r.ImGui_GetFontSize(ctx))/2, text_color, tostring(db))
                end
                r.ImGui_Dummy(ctx, meter_width, meter_bar_height)
                
                -- LRA
                if lufs_LRA > lra_hold then
                    lra_hold = lufs_LRA
                    lra_hold_time = current_time
                elseif current_time - lra_hold_time > PEAK_HOLD_DURATION then
                    lra_hold = lufs_LRA
                end
                -- LRA
                r.ImGui_SetNextItemWidth(ctx, 80)
                r.ImGui_Text(ctx, transport_stopped and "Master LRA: --" or string.format("Master LRA: %.1f LU", lufs_LRA))
                if lra_hold > -60 and not transport_stopped then
                    r.ImGui_SameLine(ctx, meter_width - peak_text_width)
                    r.ImGui_Text(ctx, string.format("%.1f", lra_hold))
                end
                    local meter_pos_x, meter_pos_y = r.ImGui_GetCursorScreenPos(ctx)
                    meter_pos_x = meter_pos_x + meter_offset

                    -- Aangepaste meter voor LRA
                    local current_pos = meter_pos_x + ((lufs_LRA) / 20) * (meter_width - meter_offset)
                    local draw_list = r.ImGui_GetWindowDrawList(ctx)
                    r.ImGui_DrawList_AddRectFilled(draw_list, meter_pos_x, meter_pos_y, current_pos, meter_pos_y + meter_bar_height, 0xFF8C00FF)

                    -- Aangepaste schaalverdeling voor LRA
                    local lra_scale_points = {0, 4, 8, 12, 16, 20}
                for _, db in ipairs(lra_scale_points) do
                    local x_pos = meter_pos_x + (db / 20) * (meter_width - meter_offset)
                    r.ImGui_DrawList_AddRectFilled(draw_list, meter_pos_x, meter_pos_y, current_pos, meter_pos_y + meter_bar_height, 0xFFFF00FF)
                    r.ImGui_DrawList_AddLine(draw_list, x_pos, meter_pos_y, x_pos, meter_pos_y + line_length, text_color)
                    r.ImGui_DrawList_AddLine(draw_list, x_pos, meter_pos_y + meter_bar_height - line_length, x_pos, meter_pos_y + meter_bar_height, text_color)
                    r.ImGui_DrawList_AddText(draw_list, x_pos - 8, meter_pos_y + (meter_bar_height - r.ImGui_GetFontSize(ctx))/2, text_color, tostring(db))
                end
                r.ImGui_Dummy(ctx, meter_width, meter_bar_height)
            end
            else
            -- Peak meters
            if TRACK and r.ValidatePtr2(0, TRACK, "MediaTrack*") then
                
                local peak_L = r.Track_GetPeakInfo(TRACK, 0)
                local peak_R = r.Track_GetPeakInfo(TRACK, 1)
                local db_L = math.max(-60, scaleTodB(peak_L))
                local db_R = math.max(-60, scaleTodB(peak_R))
            
                if db_L > peak_hold_L then
                    peak_hold_L = db_L
                    peak_hold_time_L = current_time
                elseif current_time - peak_hold_time_L > PEAK_HOLD_DURATION then
                    peak_hold_L = db_L
                end
                
                if db_R > peak_hold_R then
                    peak_hold_R = db_R
                    peak_hold_time_R = current_time
                elseif current_time - peak_hold_time_R > PEAK_HOLD_DURATION then
                    peak_hold_R = db_R
                end
            
                -- Linker meter
                r.ImGui_SetNextItemWidth(ctx, 80)
                r.ImGui_Text(ctx, string.format("Left: %.1f dB", db_L))
                if peak_hold_L > -60 then
                    r.ImGui_SameLine(ctx, meter_width - peak_text_width)
                    if peak_hold_L > 0 then
                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0xFF0000FF)
                    end
                    r.ImGui_Text(ctx, string.format("%.1f", peak_hold_L))
                    if peak_hold_L > 0 then
                        r.ImGui_PopStyleColor(ctx)
                    end
                end
                
                local meter_pos_x, meter_pos_y = r.ImGui_GetCursorScreenPos(ctx)
                meter_pos_x = meter_pos_x + meter_offset
                drawMeterSegments(meter_pos_x, meter_pos_y, meter_width - meter_offset, meter_bar_height, db_L)
                local scale_points = {0, -12, -24, -36, -48, -60}
                local draw_list = r.ImGui_GetWindowDrawList(ctx)
                local text_color = r.ImGui_ColorConvertDouble4ToU32(config.text_gray/255, config.text_gray/255, config.text_gray/255, 1)
                for _, db in ipairs(scale_points) do
                    local x_pos = meter_pos_x + ((db + 60) / 60) * (meter_width - meter_offset)
                    r.ImGui_DrawList_AddLine(draw_list, x_pos, meter_pos_y, x_pos, meter_pos_y + line_length, text_color)
                    r.ImGui_DrawList_AddLine(draw_list, x_pos, meter_pos_y + meter_bar_height - line_length, x_pos, meter_pos_y + meter_bar_height, text_color)
                    r.ImGui_DrawList_AddText(draw_list, x_pos - 8, meter_pos_y + (meter_bar_height - r.ImGui_GetFontSize(ctx))/2, text_color, tostring(db))
                end
                r.ImGui_Dummy(ctx, meter_width, meter_bar_height)
                
                -- Rechter meter
                r.ImGui_SetNextItemWidth(ctx, 80)
                r.ImGui_Text(ctx, string.format("Right: %.1f dB", db_R))
                if peak_hold_R > -60 then
                    r.ImGui_SameLine(ctx, meter_width - peak_text_width)
                    if peak_hold_R > 0 then
                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0xFF0000FF)
                    end
                    r.ImGui_Text(ctx, string.format("%.1f", peak_hold_R))
                    if peak_hold_R > 0 then
                        r.ImGui_PopStyleColor(ctx)
                    end
                end
                meter_pos_x, meter_pos_y = r.ImGui_GetCursorScreenPos(ctx)
                meter_pos_x = meter_pos_x + meter_offset
                drawMeterSegments(meter_pos_x, meter_pos_y, meter_width - meter_offset, meter_bar_height, db_R)
                local scale_points = {0, -12, -24, -36, -48, -60}
                local draw_list = r.ImGui_GetWindowDrawList(ctx)
                local text_color = r.ImGui_ColorConvertDouble4ToU32(config.text_gray/255, config.text_gray/255, config.text_gray/255, 1)
                for _, db in ipairs(scale_points) do
                    local x_pos = meter_pos_x + ((db + 60) / 60) * (meter_width - meter_offset)
                    r.ImGui_DrawList_AddLine(draw_list, x_pos, meter_pos_y, x_pos, meter_pos_y + line_length, text_color)
                    r.ImGui_DrawList_AddLine(draw_list, x_pos, meter_pos_y + meter_bar_height - line_length, x_pos, meter_pos_y + meter_bar_height, text_color)
                    r.ImGui_DrawList_AddText(draw_list, x_pos - 8, meter_pos_y + (meter_bar_height - r.ImGui_GetFontSize(ctx))/2, text_color, tostring(db))
                end
                r.ImGui_Dummy(ctx, meter_width, meter_bar_height)
            end
        end
        r.ImGui_PopFont(ctx)
        r.ImGui_EndChild(ctx)
    end
end
return M
