local M = {}
M.PALETTE = {
    green = 0x3DDC84FF, yellow = 0xE8D44DFF, orange = 0xF0963CFF, red = 0xE5484DFF,
    blue = 0x4FA3E8FF, amber = 0xF0A63CFF, accent_dark = 0x2F5F8FFF, dim_text = 0x6A6A6AFF,
    well = 0x0F0F0FFF, well_border = 0x2A2A2AFF, readout = 0x0B0B0BFF, readout_border = 0x2E2E2EFF,
}
local P = M.PALETTE
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

local function setMeterType(r, config, t)
    config.meter_type = t
    config.show_rms_meter = t == 2
    config.show_lufs_meter = t == 3
    config.show_lufs_slra_meter = t == 4
    if t > 1 then loadJSLoudnessMeter(r) end
end

local MODE_TIPS = {
    "P: peak of the selected track",
    "R: master RMS-M and RMS-I (REAPER's Loudness Meter on the monitoring FX)",
    "L: master LUFS-M and LUFS-I",
    "L-S/LRA: master LUFS-S and loudness range",
}

-- The meter modes as one segmented control, centred in avail_w: dark like
-- the readouts, the chosen mode lit in the accent colour.
local function drawModeSegments(r, ctx, config, avail_w)
    if not config.meter_type then setMeterType(r, config, 1) end
    local dl = r.ImGui_GetWindowDrawList(ctx)
    local modes = { "P", "R", "L", "L-S/LRA" }
    local pad = 7
    local h = r.ImGui_GetTextLineHeight(ctx) + 5
    local widths, total = {}, 0
    for i, label in ipairs(modes) do
        widths[i] = r.ImGui_CalcTextSize(ctx, label) + pad * 2
        total = total + widths[i]
    end
    local x0, y0 = r.ImGui_GetCursorScreenPos(ctx)
    local x = x0 + math.max(0, math.floor((avail_w - total) * 0.5))
    r.ImGui_DrawList_AddRectFilled(dl, x, y0, x + total, y0 + h, P.readout, 3)
    for i, label in ipairs(modes) do
        local w = widths[i]
        r.ImGui_SetCursorScreenPos(ctx, x, y0)
        if r.ImGui_InvisibleButton(ctx, "##meter_mode" .. i, w, h) then setMeterType(r, config, i) end
        local hovered = r.ImGui_IsItemHovered(ctx)
        if hovered then r.ImGui_SetTooltip(ctx, MODE_TIPS[i]) end
        local selected = config.meter_type == i
        if selected then
            r.ImGui_DrawList_AddRectFilled(dl, x + 2, y0 + 2, x + w - 2, y0 + h - 2, P.accent_dark, 2)
        elseif hovered then
            r.ImGui_DrawList_AddRectFilled(dl, x + 2, y0 + 2, x + w - 2, y0 + h - 2, 0x242424FF, 2)
        end
        if i > 1 and not selected and config.meter_type ~= i - 1 then
            r.ImGui_DrawList_AddLine(dl, x, y0 + 4, x, y0 + h - 4, P.readout_border)
        end
        local tw, th = r.ImGui_CalcTextSize(ctx, label)
        r.ImGui_DrawList_AddText(dl, x + (w - tw) * 0.5, y0 + (h - th) * 0.5,
            selected and 0xFFFFFFFF or (hovered and 0xD8D8D8FF or 0x8A8A8AFF), label)
        x = x + w
    end
    r.ImGui_DrawList_AddRect(dl, x - total, y0, x, y0 + h, P.readout_border, 3)
    r.ImGui_SetCursorScreenPos(ctx, x0, y0 + h + 5)
    r.ImGui_Dummy(ctx, 0, 0)
end

-- Right-click on an empty part of the meter: switch between the horizontal
-- and the vertical meter.
local function drawOrientationMenu(r, ctx, config)
    if r.ImGui_IsWindowHovered(ctx) and not r.ImGui_IsAnyItemHovered(ctx) and r.ImGui_IsMouseClicked(ctx, 1) then
        r.ImGui_OpenPopup(ctx, "MeterOptions")
    end
    if r.ImGui_BeginPopup(ctx, "MeterOptions") then
        if r.ImGui_MenuItem(ctx, "Vertical Meter", nil, config.meter_vertical == true) then
            config.meter_vertical = not config.meter_vertical
            if SaveConfig then SaveConfig() end
        end
        r.ImGui_EndPopup(ctx)
    end
end

M.VERTICAL_MIN_HEIGHT, M.VERTICAL_MAX_HEIGHT, M.VERTICAL_DEFAULT_HEIGHT = 150, 600, 220
M.VERTICAL_METER_WIDTH = 74
M.H_LABEL_W, M.H_READOUT_W, M.H_GAP = 24, 40, 8

function M.GetHeight(config)
    if not config.meter_vertical then return 90 end
    local h = tonumber(config.meter_vertical_height) or M.VERTICAL_DEFAULT_HEIGHT
    return math.max(M.VERTICAL_MIN_HEIGHT, math.min(M.VERTICAL_MAX_HEIGHT, h))
end

local vhold = {}
local function holdValue(key, v, now)
    local e = vhold[key]
    if not e then e = { v = -60, t = 0 }; vhold[key] = e end
    if v > e.v then
        e.v, e.t = v, now
    elseif now - e.t > 2.0 then
        e.v = v
    end
    return e.v
end


local function dim(col) return (col & 0xFFFFFF00) | 0x2A end

local function peakZones(bar)
    return { { bar.min, -18, P.green }, { -18, -4, P.yellow }, { -4, 0, P.orange }, { 0, bar.max, P.red } }
end

local function zoneColorAt(bar, v)
    for _, z in ipairs(bar.zones) do
        if v <= z[2] then return z[3] end
    end
    return bar.zones[#bar.zones][3]
end

-- A small dark readout box with centred text, as on a mixer strip.
function M.DrawReadout(r, ctx, x1, y1, x2, y2, text, text_col, bg_col)
    local dl = r.ImGui_GetWindowDrawList(ctx)
    r.ImGui_DrawList_AddRectFilled(dl, x1, y1, x2, y2, bg_col or P.readout, 2)
    r.ImGui_DrawList_AddRect(dl, x1, y1, x2, y2, P.readout_border, 2)
    local tw, th = r.ImGui_CalcTextSize(ctx, text)
    r.ImGui_DrawList_AddText(dl, x1 + (x2 - x1 - tw) * 0.5, y1 + (y2 - y1 - th) * 0.5, text_col, text)
end

-- Two bars side by side with the scale between them, as in REAPER's mixer,
-- centred in w: the held value in a readout above each bar, its name below,
-- a line at the held level, the unlit part of each colour zone dimmed and
-- thin gaps for an LED look. A bar is { label, value, hold, min, max, peak
-- (green/yellow/orange/red zones) or color, text (readout, e.g. "--") }.
-- Returns the top and bottom of the bars, for a fader beside them.
local function drawVerticalBars(r, ctx, config, x, y, w, h, bars, tooltip)
    local dl = r.ImGui_GetWindowDrawList(ctx)
    local text_color = r.ImGui_ColorConvertDouble4ToU32(config.text_gray/255, config.text_gray/255, config.text_gray/255, 1)
    local line_h = r.ImGui_GetTextLineHeight(ctx)
    local scale_w = 22
    local bar_w = math.max(6, math.min(26, math.floor((w - scale_w) / 2)))
    local total_w = bar_w * 2 + scale_w
    x = x + math.floor((w - total_w) * 0.5)
    local box_h = line_h + 3
    local top = y + box_h + 6
    local bottom = y + h - line_h - 9
    local bar_h = math.max(10, bottom - top)
    bottom = top + bar_h
    local xs = { x, x + bar_w + scale_w }

    local function yOf(bar, v)
        local t = (math.max(bar.min, math.min(bar.max, v)) - bar.min) / (bar.max - bar.min)
        return bottom - t * bar_h
    end

    r.ImGui_DrawList_AddRectFilled(dl, x - 3, top - 3, x + total_w + 3, bottom + 3, P.well, 3)
    r.ImGui_DrawList_AddRect(dl, x - 3, top - 3, x + total_w + 3, bottom + 3, P.well_border, 3)

    for i, bar in ipairs(bars) do
        local bx = xs[i]
        bar.zones = bar.peak and peakZones(bar) or { { bar.min, bar.max, bar.color } }
        local value = math.max(bar.min, math.min(bar.max, bar.value))
        for _, z in ipairs(bar.zones) do
            local z_top, z_bottom = yOf(bar, z[2]), yOf(bar, z[1])
            r.ImGui_DrawList_AddRectFilled(dl, bx, z_top, bx + bar_w, z_bottom, dim(z[3]))
            if value > z[1] then
                r.ImGui_DrawList_AddRectFilled(dl, bx, yOf(bar, math.min(value, z[2])), bx + bar_w, z_bottom, z[3])
            end
        end
        for ly = bottom - 3, top + 1, -3 do
            r.ImGui_DrawList_AddLine(dl, bx, ly, bx + bar_w, ly, 0x0000005A)
        end
        if bar.hold and bar.hold > bar.min then
            local hy = yOf(bar, bar.hold)
            r.ImGui_DrawList_AddLine(dl, bx, hy, bx + bar_w, hy, zoneColorAt(bar, bar.hold), 2)
        end

        local txt = bar.text or (bar.hold and bar.hold > bar.min and string.format("%.1f", bar.hold) or "-inf")
        local over = bar.peak and bar.hold and bar.hold > 0
        local idle = txt == "-inf" or txt == "--"
        M.DrawReadout(r, ctx, bx - 3, y, bx + bar_w + 3, y + box_h, txt,
            over and 0xFFFFFFFF or (idle and P.dim_text or 0xD8D8D8FF), over and 0xB3262BFF or nil)
        local lw = r.ImGui_CalcTextSize(ctx, bar.label)
        r.ImGui_DrawList_AddText(dl, bx + (bar_w - lw) * 0.5, bottom + 6, text_color, bar.label)
    end

    local ref = bars[1]
    local px_per_db = bar_h / (ref.max - ref.min)
    local step = 3
    for _, s in ipairs({ 3, 6, 12, 24 }) do
        step = s
        if s * px_per_db >= line_h + 2 then break end
    end
    local mid_x = x + bar_w + scale_w * 0.5
    local v = math.floor(ref.max / step) * step
    while v >= ref.min do
        local ty = yOf(ref, v)
        local label = tostring(math.floor(v + 0.5))
        local tw = r.ImGui_CalcTextSize(ctx, label)
        local col = v == 0 and 0xE0E0E0FF or text_color
        r.ImGui_DrawList_AddLine(dl, x + bar_w + 1, ty, x + bar_w + 4, ty, col)
        r.ImGui_DrawList_AddLine(dl, x + bar_w + scale_w - 4, ty, x + bar_w + scale_w - 1, ty, col)
        if ty - line_h * 0.5 > top - 4 then
            r.ImGui_DrawList_AddText(dl, mid_x - tw * 0.5, ty - line_h * 0.5, col, label)
        end
        v = v - step
    end

    if r.ImGui_IsMouseHoveringRect(ctx, x - 3, y, x + total_w + 3, bottom + 3) then
        if tooltip then r.ImGui_SetTooltip(ctx, tooltip .. "\nClick: reset held values") end
        if r.ImGui_IsMouseClicked(ctx, 0) then vhold = {} end
    end
    return top, bottom
end

-- The horizontal meter in the same style: the two bars stacked in one well
-- with the dB scale between them, each bar's name on the left and its held
-- value in a readout on the right.
local function drawHorizontalBars(r, ctx, config, x, y, w, h, bars, tooltip)
    local dl = r.ImGui_GetWindowDrawList(ctx)
    local text_color = r.ImGui_ColorConvertDouble4ToU32(config.text_gray/255, config.text_gray/255, config.text_gray/255, 1)
    local line_h = r.ImGui_GetTextLineHeight(ctx)
    local label_w, readout_w = M.H_LABEL_W, M.H_READOUT_W
    local scale_h = line_h + 2
    local bar_h = math.max(6, math.min(16, math.floor((h - scale_h - 6) / 2)))
    local total_h = bar_h * 2 + scale_h + 6
    local top = y + math.floor((h - total_h) * 0.5) + 3
    local left = x + label_w
    local right = x + w - readout_w - M.H_GAP
    local bar_w = math.max(10, right - left)
    local ys = { top, top + bar_h + scale_h }

    local function xOf(bar, v)
        local t = (math.max(bar.min, math.min(bar.max, v)) - bar.min) / (bar.max - bar.min)
        return left + t * bar_w
    end

    r.ImGui_DrawList_AddRectFilled(dl, left - 3, top - 3, right + 3, ys[2] + bar_h + 3, P.well, 3)
    r.ImGui_DrawList_AddRect(dl, left - 3, top - 3, right + 3, ys[2] + bar_h + 3, P.well_border, 3)

    for i, bar in ipairs(bars) do
        local by = ys[i]
        bar.zones = bar.peak and peakZones(bar) or { { bar.min, bar.max, bar.color } }
        local value = math.max(bar.min, math.min(bar.max, bar.value))
        for _, z in ipairs(bar.zones) do
            local z_left, z_right = xOf(bar, z[1]), xOf(bar, z[2])
            r.ImGui_DrawList_AddRectFilled(dl, z_left, by, z_right, by + bar_h, dim(z[3]))
            if value > z[1] then
                r.ImGui_DrawList_AddRectFilled(dl, z_left, by, xOf(bar, math.min(value, z[2])), by + bar_h, z[3])
            end
        end
        for lx = left + 3, right - 1, 3 do
            r.ImGui_DrawList_AddLine(dl, lx, by, lx, by + bar_h, 0x0000005A)
        end
        if bar.hold and bar.hold > bar.min then
            local hx = xOf(bar, bar.hold)
            r.ImGui_DrawList_AddLine(dl, hx, by, hx, by + bar_h, zoneColorAt(bar, bar.hold), 2)
        end

        local lw = r.ImGui_CalcTextSize(ctx, bar.label)
        r.ImGui_DrawList_AddText(dl, x + (label_w - 3 - lw) * 0.5, by + (bar_h - line_h) * 0.5, text_color, bar.label)
        local txt = bar.text or (bar.hold and bar.hold > bar.min and string.format("%.1f", bar.hold) or "-inf")
        local over = bar.peak and bar.hold and bar.hold > 0
        local idle = txt == "-inf" or txt == "--"
        M.DrawReadout(r, ctx, x + w - readout_w, by, x + w, by + bar_h, txt,
            over and 0xFFFFFFFF or (idle and P.dim_text or 0xD8D8D8FF), over and 0xB3262BFF or nil)
    end

    local ref = bars[1]
    local px_per_db = bar_w / (ref.max - ref.min)
    local step = 6
    for _, s in ipairs({ 6, 12, 24 }) do
        step = s
        if s * px_per_db >= 22 then break end
    end
    local sy1, sy2 = ys[1] + bar_h, ys[2]
    local v = math.floor(ref.max / step) * step
    while v >= ref.min do
        local tx = xOf(ref, v)
        local label = tostring(math.floor(v + 0.5))
        local tw = r.ImGui_CalcTextSize(ctx, label)
        local col = v == 0 and 0xE0E0E0FF or text_color
        r.ImGui_DrawList_AddLine(dl, tx, sy1 + 1, tx, sy1 + 4, col)
        r.ImGui_DrawList_AddLine(dl, tx, sy2 - 4, tx, sy2 - 1, col)
        local lx = math.max(left - 2, math.min(right + 2 - tw, tx - tw * 0.5))
        r.ImGui_DrawList_AddText(dl, lx, sy1 + (scale_h - line_h) * 0.5, col, label)
        v = v - step
    end

    if r.ImGui_IsMouseHoveringRect(ctx, x, top - 3, x + w, ys[2] + bar_h + 3) then
        if tooltip then r.ImGui_SetTooltip(ctx, tooltip .. "\nClick: reset held values") end
        if r.ImGui_IsMouseClicked(ctx, 0) then vhold = {} end
    end
end

function M.DrawMeter(r, ctx, config, TRACK, TinyFont, mix)
    if not TRACK then return end
    local now = r.time_precise()
    -- Integrated values and LRA describe the run since play started. With the
    -- transport stopped they are shown empty ("--") instead of the last run's
    -- result, until the next play starts a new measurement. Paused counts as
    -- running: playing on continues the same measurement.
    local transport_stopped = r.GetPlayState() == 0

    local function scaleTodB(peak)
        if peak < 0.001 then return -60.0 end
        return 20 * math.log(peak, 10)
    end
    local function fmt(v) return string.format("%.1f", v) end

    -- P measures the selected track, R, L and L-S/LRA the master mix through
    -- REAPER's Loudness Meter on the monitoring FX.
    local function buildBars()
        local mt = config.meter_type or 1
        if mt == 2 or mt == 3 or mt == 4 then
            local v = readLoudness(r) or {}
            if mt == 2 then
                local m, i = v.rms_m or -100, v.rms_i or -100
                return {
                    { label = "M", value = m, hold = holdValue("rms_m", m, now), min = -60, max = 0, color = P.blue },
                    { label = "I", value = transport_stopped and -100 or i, min = -60, max = 0, color = P.blue,
                      text = (transport_stopped or i <= -100) and "--" or fmt(i) },
                }, "Master RMS-M (held) / RMS-I, dB"
            elseif mt == 3 then
                local m, i = v.lufs_m or -100, v.lufs_i or -100
                return {
                    { label = "M", value = m, hold = holdValue("lufs_m", m, now), min = -60, max = 0, color = P.orange },
                    { label = "I", value = transport_stopped and -100 or i, min = -60, max = 0, color = P.orange,
                      text = (transport_stopped or i <= -100) and "--" or fmt(i) },
                }, "Master LUFS-M (held) / LUFS-I"
            end
            local s, lra = v.lufs_s or -100, v.lra or 0
            return {
                { label = "S", value = s, hold = holdValue("lufs_s", s, now), min = -60, max = 0, color = P.orange },
                { label = "LRA", value = transport_stopped and 0 or lra, min = 0, max = 20, color = P.yellow,
                  text = transport_stopped and "--" or fmt(lra) },
            }, "Master LUFS-S (held) / LRA in LU (0-20)"
        end
        if not r.ValidatePtr2(0, TRACK, "MediaTrack*") then return nil end
        local db_L = math.max(-60, scaleTodB(r.Track_GetPeakInfo(TRACK, 0)))
        local db_R = math.max(-60, scaleTodB(r.Track_GetPeakInfo(TRACK, 1)))
        return {
            { label = "L", value = db_L, hold = holdValue("peak_l", db_L, now), min = -60, max = 6, peak = true },
            { label = "R", value = db_R, hold = holdValue("peak_r", db_R, now), min = -60, max = 6, peak = true },
        }, string.format("Track peak (held)\nL: %.1f dB   R: %.1f dB", db_L, db_R)
    end

    local hmix = not config.meter_vertical and mix and mix.horizontal
    local hmix_h = hmix and hmix.h or 0
    local child_flags = r.ImGui_WindowFlags_NoScrollbar() | r.ImGui_WindowFlags_NoScrollWithMouse()
    if not r.ImGui_BeginChild(ctx, "MeterSection", -1, M.GetHeight(config) + hmix_h, 0, child_flags) then return end
    r.ImGui_PushFont(ctx, TinyFont, 9)
    drawModeSegments(r, ctx, config, r.ImGui_GetContentRegionAvail(ctx))
    local cx, cy = r.ImGui_GetCursorScreenPos(ctx)
    local avail_w, avail_h = r.ImGui_GetContentRegionAvail(ctx)
    local color_h = 6
    local body_h = avail_h - color_h
    local bars, tip = buildBars()
    local gx, group_w

    if config.meter_vertical then
        local meter_w = M.VERTICAL_METER_WIDTH
        local strip = mix and mix.strip
        local column = mix and mix.column
        if strip then
            group_w = meter_w + strip.gap + strip.fader_w
        elseif column then
            group_w = meter_w + mix.gap + mix.column_w
        else
            group_w = meter_w
        end
        group_w = math.min(avail_w, group_w)
        gx = cx + math.max(0, math.floor((avail_w - group_w) * 0.5))
        if strip then
            local top_h = strip.top_h or 0
            local bar_top, bar_bottom
            if bars then bar_top, bar_bottom = drawVerticalBars(r, ctx, config, gx, cy + top_h, meter_w, body_h - top_h, bars, tip) end
            r.ImGui_PopFont(ctx)
            strip.top(gx, cy, group_w, top_h)
            if bar_top then strip.fader(gx + meter_w + strip.gap, bar_top, strip.fader_w, bar_bottom) end
        else
            if bars then drawVerticalBars(r, ctx, config, gx, cy, meter_w, body_h, bars, tip) end
            r.ImGui_PopFont(ctx)
            if column then
                r.ImGui_SetCursorScreenPos(ctx, gx + meter_w + mix.gap, cy)
                column(mix.column_w, body_h)
            end
        end
    else
        gx, group_w = cx + 2, avail_w - 4
        local meter_h = body_h - hmix_h
        if bars then drawHorizontalBars(r, ctx, config, gx, cy, group_w, meter_h, bars, tip) end
        r.ImGui_PopFont(ctx)
        if hmix then hmix.draw(gx, cy + meter_h, group_w) end
    end

    if r.ValidatePtr2(0, TRACK, "MediaTrack*") then
        local native = r.GetTrackColor(TRACK)
        if native and native ~= 0 then
            local cr, cg, cb = r.ColorFromNative(native)
            local col = (cr << 24) | (cg << 16) | (cb << 8) | 0xFF
            r.ImGui_DrawList_AddRectFilled(r.ImGui_GetWindowDrawList(ctx), gx, cy + avail_h - 3, gx + group_w, cy + avail_h, col, 1.5)
        end
    end
    r.ImGui_SetCursorScreenPos(ctx, cx, cy)
    r.ImGui_Dummy(ctx, avail_w, avail_h)
    drawOrientationMenu(r, ctx, config)
    r.ImGui_EndChild(ctx)
end
return M
