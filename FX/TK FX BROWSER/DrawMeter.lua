local M = {}
local function loadJSLoudnessMeter(r)
    local monitor_fx_count = r.TrackFX_GetRecCount(r.GetMasterTrack(0))
    local js_meter_loaded = false
    for i = 0, monitor_fx_count - 1 do
        local _, fx_name = r.TrackFX_GetFXName(r.GetMasterTrack(0), 0x1000000 + i, "")
        if fx_name:find("JS: analysis\\loudness_meter") then
            js_meter_loaded = true
            break
        end
    end
    if not js_meter_loaded then
        local fx_idx = r.TrackFX_AddByName(r.GetMasterTrack(0), "JS: analysis/loudness_meter", true, -1)
        r.TrackFX_Show(r.GetMasterTrack(0), 0x1000000 + fx_idx, 2)  -- 2 = verberg venster
        r.TrackFX_SetEnabled(r.GetMasterTrack(0), 0x1000000, true)
    end
end

function M.DrawMeter(r, ctx, config, TRACK, TinyFont)
    if not TRACK then return end
    
    -- peak hold
    peak_hold_L = peak_hold_L or -60
    peak_hold_R = peak_hold_R or -60
    peak_hold_time_L = peak_hold_time_L or 0
    peak_hold_time_R = peak_hold_time_R or 0
    PEAK_HOLD_DURATION = 2.0

    local function scaleTodB(peak)
        if peak < 0.001 then return -60.0 end
        return 20 * math.log(peak, 10)
    end

    local function getRMSValues()
        local monitor_fx_count = r.TrackFX_GetRecCount(r.GetMasterTrack(0))
        for i = 0, monitor_fx_count - 1 do
            local _, fx_name = r.TrackFX_GetFXName(r.GetMasterTrack(0), 0x1000000 + i, "")
            if fx_name:find("JS: analysis\\loudness_meter") then
                local rms_M = r.TrackFX_GetParamNormalized(r.GetMasterTrack(0), 0x1000000 + i, 16)
                local rms_I = r.TrackFX_GetParamNormalized(r.GetMasterTrack(0), 0x1000000 + i, 17)
                
                local db_M = -100 + (rms_M * 100)
                local db_I = -100 + (rms_I * 100)
                
                return db_M, db_I
            end
        end
        return -100, -100
    end
    local function getLUFSValues()
        local monitor_fx_count = r.TrackFX_GetRecCount(r.GetMasterTrack(0))
        for i = 0, monitor_fx_count - 1 do
            local _, fx_name = r.TrackFX_GetFXName(r.GetMasterTrack(0), 0x1000000 + i, "")
            if fx_name:find("JS: analysis\\loudness_meter") then
                local lufs_M = r.TrackFX_GetParamNormalized(r.GetMasterTrack(0), 0x1000000 + i, 18)
                local lufs_I = r.TrackFX_GetParamNormalized(r.GetMasterTrack(0), 0x1000000 + i, 20)
                local lufs_S = r.TrackFX_GetParamNormalized(r.GetMasterTrack(0), 0x1000000 + i, 19)
                local lufs_LRA = r.TrackFX_GetParamNormalized(r.GetMasterTrack(0), 0x1000000 + i, 21)
                
                local db_M = -100 + (lufs_M * 100)
                local db_I = -100 + (lufs_I * 100)
                local db_S = -100 + (lufs_S * 100)
                local db_LRA = -100 + (lufs_LRA * 100)
                
                return db_M, db_I, db_S, db_LRA
            end
        end
        return -100, -100, -100, -100
    end
    
    
    local window_height = r.ImGui_GetWindowHeight(ctx)
    local bottom_buttons_height = config.hideBottomButtons and 0 or 70
    local volume_slider_height = (config.hideBottomButtons or config.hideVolumeSlider) and 0 or 20
    local meter_height = 80
    local spacing = 2
    local margin = 5
    local meter_offset = 7
    local line_length = 3
    local peak_text_width = 45
    local meter_y = window_height - bottom_buttons_height - volume_slider_height - meter_height - spacing
    r.ImGui_SetCursorPosY(ctx, meter_y)

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
        r.ImGui_PushFont(ctx, TinyFont)
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
            -- RMS-M (Momentary)
            r.ImGui_SetNextItemWidth(ctx, 80)
            r.ImGui_Text(ctx, string.format("RMS-M: %.1f dB", rms_M))
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
            r.ImGui_SetNextItemWidth(ctx, 80)
            r.ImGui_Text(ctx, string.format("RMS-I: %.1f dB", rms_I))
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
                if lufs_M and lufs_I then
                    -- LUFS-M (Momentary)
                    r.ImGui_SetNextItemWidth(ctx, 80)
                    r.ImGui_Text(ctx, string.format("LUFS-M: %.1f dB", lufs_M))
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
                r.ImGui_SetNextItemWidth(ctx, 80)
                r.ImGui_Text(ctx, string.format("LUFS-I: %.1f dB", lufs_I))
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
            if lufs_S and lufs_LRA then
                -- LUFS-S
                r.ImGui_SetNextItemWidth(ctx, 80)
                r.ImGui_Text(ctx, string.format("LUFS-S: %.1f dB", lufs_S))
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
                r.ImGui_SetNextItemWidth(ctx, 80)
                r.ImGui_Text(ctx, string.format("LRA: %.1f dB", lufs_LRA))
                meter_pos_x, meter_pos_y = r.ImGui_GetCursorScreenPos(ctx)
                meter_pos_x = meter_pos_x + meter_offset
                drawMeterSegments(meter_pos_x, meter_pos_y, meter_width - meter_offset, meter_bar_height, lufs_LRA, true, 0xFF8C00FF)
                for _, db in ipairs(scale_points) do
                    local x_pos = meter_pos_x + ((db + 60) / 60) * (meter_width - meter_offset)
                    r.ImGui_DrawList_AddLine(draw_list, x_pos, meter_pos_y, x_pos, meter_pos_y + line_length, text_color)
                    r.ImGui_DrawList_AddLine(draw_list, x_pos, meter_pos_y + meter_bar_height - line_length, x_pos, meter_pos_y + meter_bar_height, text_color)
                    r.ImGui_DrawList_AddText(draw_list, x_pos - 8, meter_pos_y + (meter_bar_height - r.ImGui_GetFontSize(ctx))/2, text_color, tostring(db))
                end
                r.ImGui_Dummy(ctx, meter_width, meter_bar_height)
            end
            else
            -- Peak meters
            if TRACK and r.ValidatePtr2(0, TRACK, "MediaTrack*") then
                local current_time = r.time_precise()
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
