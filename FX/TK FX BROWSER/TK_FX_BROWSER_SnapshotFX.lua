-- @description TK FX BROWSER - Snapshot FX
-- @author TouristKiller
-- @version 1.1
-- @changelog:
--   + GUI with FX list and checkboxes
--   + Snap multiple FX at once
-- @about
--   Standalone action: select which FX on the selected track to screenshot.
--   Uses the same Screenshots folder and config.json as the TK FX BROWSER.

local r = reaper

if not r.APIExists or not r.APIExists("JS_GDI_GetClientDC") then
    r.ShowMessageBox(
        "Missing dependency: 'js_ReaScriptAPI' (by Julian Sader).\n\n"
        .. "Install via ReaPack:\n"
        .. "1) Extensions > ReaPack > Browse Packages\n"
        .. "2) Search for 'js_ReaScriptAPI' and install it\n"
        .. "3) Restart REAPER",
        "TK FX BROWSER Snap – Missing dependency", 0)
    return
end

local script_path = debug.getinfo(1, "S").source:match("@?(.*[/\\])")
local os_separator = package.config:sub(1, 1)
local screenshot_path = script_path .. "Screenshots" .. os_separator

if not r.file_exists(screenshot_path) then
    r.RecursiveCreateDirectory(screenshot_path, 0)
end

package.path = script_path .. "?.lua;"
local json_ok, json = pcall(require, "json")

local config = {
    srcx = 0,
    srcy = 27,
    capture_height_offset = 0,
    screenshot_delay = 0.5,
    screenshot_size_option = 2,
}

if json_ok then
    local f = io.open(script_path .. "config.json", "r")
    if f then
        local content = f:read("*all")
        f:close()
        local ok, loaded = pcall(json.decode, content)
        if ok and loaded then
            for _, key in ipairs({
                "srcx", "srcy", "capture_height_offset",
                "screenshot_delay", "screenshot_size_option"
            }) do
                if loaded[key] ~= nil then config[key] = loaded[key] end
            end
        end
    end
end

local ctx = r.ImGui_CreateContext("TK Snapshot FX")
local font = r.ImGui_CreateFont("Arial", 12)
local font_large = r.ImGui_CreateFont("Arial", 15)
r.ImGui_Attach(ctx, font)
r.ImGui_Attach(ctx, font_large)

local COL = {
    bg           = 0x1C1C1CFF,
    child_bg     = 0x232323FF,
    border       = 0x3A3A3AFF,
    text         = 0xC8C8C8FF,
    text_dim     = 0x888888FF,
    btn          = 0x333333FF,
    btn_hover    = 0x444444FF,
    btn_active   = 0x555555FF,
    accent       = 0x5B9BD5FF,
    accent_hover = 0x6DB3E8FF,
    accent_active= 0x4A87BFFF,
    frame_bg     = 0x2A2A2AFF,
    frame_hover  = 0x383838FF,
    frame_active = 0x454545FF,
    check        = 0x5B9BD5FF,
    header       = 0x2F2F2FFF,
    header_hover = 0x3A3A3AFF,
    separator    = 0x3A3A3AFF,
    scrollbar    = 0x2A2A2AFF,
    scrollbar_grab = 0x555555FF,
    status_ok    = 0x6BCB77FF,
    status_busy  = 0xFFD966FF,
    status_err   = 0xE06C6CFF,
}

local fx_checked = {}
local fx_list = {}
local fx_has_screenshot = {}
local capturing = false
local capture_queue = {}
local capture_index = 0
local capture_start_time = 0
local capture_waiting = false
local capture_opened = {}
local status_msg = ""
local status_type = ""
local last_track = nil
local show_delay_slider = false
local use_screen_capture = false

local function HasScreenshot(fx_name)
    local safe_name = fx_name:gsub("[^%w%s-]", "_")
    local path = screenshot_path .. safe_name .. ".png"
    local f = io.open(path, "rb")
    if f then
        local size = f:seek("end")
        f:close()
        return size and size > 0
    end
    return false
end

local function IsOSX()
    return reaper.GetOS():match("OSX") or reaper.GetOS():match("macOS")
end

local function ScaleBitmap(srcBmp, w, h)
    local destBmp
    if config.screenshot_size_option == 1 then
        destBmp = r.JS_LICE_CreateBitmap(true, 128, 128)
        r.JS_LICE_ScaledBlit(destBmp, 0, 0, 128, 128, srcBmp, 0, 0, w, h, 1, "FAST")
    elseif config.screenshot_size_option == 2 then
        local scale = 500 / w
        local newW, newH = 500, math.floor(h * scale)
        destBmp = r.JS_LICE_CreateBitmap(true, newW, newH)
        r.JS_LICE_ScaledBlit(destBmp, 0, 0, newW, newH, srcBmp, 0, 0, w, h, 1, "FAST")
    else
        destBmp = srcBmp
    end
    return destBmp
end

local function CaptureWindowGDI(hwnd, fx_name)
    local safe_name = fx_name:gsub("[^%w%s-]", "_")
    local filename = screenshot_path .. safe_name .. ".png"

    local _, left, top, right, bottom = r.JS_Window_GetClientRect(hwnd)
    local w, h = right - left, bottom - top
    local offset = fx_name:match("^JS") and 0 or config.capture_height_offset
    h = h - offset

    if not IsOSX() then
        local srcDC = r.JS_GDI_GetClientDC(hwnd)
        local srcBmp = r.JS_LICE_CreateBitmap(true, w, h)
        local srcDC_LICE = r.JS_LICE_GetDC(srcBmp)
        r.JS_GDI_Blit(srcDC_LICE, 0, 0, srcDC, config.srcx, config.srcy, w, h)

        local destBmp = ScaleBitmap(srcBmp, w, h)
        r.JS_LICE_WritePNG(filename, destBmp, false)
        if destBmp ~= srcBmp then r.JS_LICE_DestroyBitmap(destBmp) end
        r.JS_GDI_ReleaseDC(hwnd, srcDC)
        r.JS_LICE_DestroyBitmap(srcBmp)
    else
        h = top - bottom
        local command = 'screencapture -x -R %d,%d,%d,%d -t png "%s"'
        os.execute(command:format(left, top, w, h, filename))
    end

    return filename
end

local function CaptureWindowScreen(hwnd, fx_name)
    local safe_name = fx_name:gsub("[^%w%s-]", "_")
    local filename = screenshot_path .. safe_name .. ".png"

    if IsOSX() then
        local _, left, top, right, bottom = r.JS_Window_GetClientRect(hwnd)
        local w, h = right - left, top - bottom
        local command = 'screencapture -x -R %d,%d,%d,%d -t png "%s"'
        os.execute(command:format(left, top, w, h, filename))
        return filename
    end

    local _, wl, wt, wr, wb = r.JS_Window_GetRect(hwnd)
    local _, cl, ct, cr, cb = r.JS_Window_GetClientRect(hwnd)
    local border_l = cl - wl
    local border_t = ct - wt
    local border_r = wr - cr
    local border_b = wb - cb
    local x = wl + border_l
    local y = wt + border_t
    local w = (wr - wl) - border_l - border_r
    local h = (wb - wt) - border_t - border_b
    local offset = fx_name:match("^JS") and 0 or config.capture_height_offset
    h = h - offset - config.srcy
    if w <= 0 or h <= 0 then return nil end

    local screenDC = r.JS_GDI_GetScreenDC()
    local srcBmp = r.JS_LICE_CreateBitmap(true, w, h)
    local srcDC_LICE = r.JS_LICE_GetDC(srcBmp)
    r.JS_GDI_Blit(srcDC_LICE, 0, 0, screenDC, x, y + config.srcy, w, h)

    local destBmp = ScaleBitmap(srcBmp, w, h)
    r.JS_LICE_WritePNG(filename, destBmp, false)
    if destBmp ~= srcBmp then r.JS_LICE_DestroyBitmap(destBmp) end
    r.JS_GDI_ReleaseDC(nil, screenDC)
    r.JS_LICE_DestroyBitmap(srcBmp)

    return filename
end

local function CaptureWindow(hwnd, fx_name)
    if use_screen_capture then
        return CaptureWindowScreen(hwnd, fx_name)
    else
        return CaptureWindowGDI(hwnd, fx_name)
    end
end

local function RefreshFXList(force)
    local track = r.GetSelectedTrack(0, 0)
    if not force and track == last_track then return end
    last_track = track
    fx_list = {}
    fx_checked = {}
    fx_has_screenshot = {}
    if not track then return end
    local count = r.TrackFX_GetCount(track)
    for i = 0, count - 1 do
        local _, name = r.TrackFX_GetFXName(track, i, "")
        fx_list[#fx_list + 1] = { index = i, name = name }
        fx_checked[i] = false
        fx_has_screenshot[i] = HasScreenshot(name)
    end
end

local function StartCapture()
    local track = r.GetSelectedTrack(0, 0)
    if not track then return end

    capture_queue = {}
    for i = 1, #fx_list do
        if fx_checked[fx_list[i].index] then
            capture_queue[#capture_queue + 1] = fx_list[i].index
        end
    end
    if #capture_queue == 0 then
        status_msg = "No FX selected"
        status_type = "err"
        return
    end
    capturing = true
    capture_index = 1
    capture_waiting = false
    capture_opened = {}
    status_msg = "Capturing 0/" .. #capture_queue .. "..."
    status_type = "busy"
end

local function ProcessCapture()
    local track = r.GetSelectedTrack(0, 0)
    if not track or not r.ValidatePtr(track, "MediaTrack*") then
        capturing = false
        status_msg = "Track no longer available"
        status_type = "err"
        return
    end

    if capture_index > #capture_queue then
        for idx, was_opened in pairs(capture_opened) do
            if was_opened then
                r.TrackFX_Show(track, idx, 2)
            end
        end
        capturing = false
        status_msg = "Done! " .. #capture_queue .. " screenshot(s) saved"
        status_type = "ok"
        last_track = nil
        RefreshFXList()
        return
    end

    local fx_idx = capture_queue[capture_index]

    if not capture_waiting then
        local already_open = r.TrackFX_GetFloatingWindow(track, fx_idx) ~= nil
        if not already_open then
            r.TrackFX_Show(track, fx_idx, 3)
            capture_opened[fx_idx] = true
        end
        capture_start_time = r.time_precise()
        capture_waiting = true
        status_msg = "Capturing " .. capture_index .. "/" .. #capture_queue .. "..."
        status_type = "busy"
        return
    end

    if r.time_precise() - capture_start_time < config.screenshot_delay then
        return
    end

    local hwnd = r.TrackFX_GetFloatingWindow(track, fx_idx)
    if hwnd then
        local _, fx_name = r.TrackFX_GetFXName(track, fx_idx, "")
        CaptureWindow(hwnd, fx_name)
        if capture_opened[fx_idx] then
            r.TrackFX_Show(track, fx_idx, 2)
        end
    end

    capture_waiting = false
    capture_index = capture_index + 1
end

local function PushTheme()
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_WindowBg(), COL.bg)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ChildBg(), COL.child_bg)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Border(), COL.border)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), COL.text)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), COL.btn)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), COL.btn_hover)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), COL.btn_active)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), COL.frame_bg)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgHovered(), COL.frame_hover)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgActive(), COL.frame_active)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_CheckMark(), COL.check)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Header(), COL.header)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderHovered(), COL.header_hover)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Separator(), COL.separator)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ScrollbarBg(), COL.scrollbar)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ScrollbarGrab(), COL.scrollbar_grab)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowRounding(), 6)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), 4)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ChildRounding(), 4)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), 10, 10)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FramePadding(), 6, 4)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing(), 8, 6)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ScrollbarSize(), 10)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ScrollbarRounding(), 4)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_GrabRounding(), 3)
end

local function PopTheme()
    r.ImGui_PopStyleVar(ctx, 9)
    r.ImGui_PopStyleColor(ctx, 16)
end

local function Loop()
    RefreshFXList()

    if capturing then
        ProcessCapture()
    end

    PushTheme()
    r.ImGui_PushFont(ctx, font, 12)
    r.ImGui_SetNextWindowSize(ctx, 360, 420, r.ImGui_Cond_FirstUseEver())

    local visible, open = r.ImGui_Begin(ctx, "TK Snapshot FX", true, r.ImGui_WindowFlags_NoCollapse())
    if visible then
        local track = r.GetSelectedTrack(0, 0)
        if not track then
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), COL.text_dim)
            r.ImGui_Text(ctx, "No track selected")
            r.ImGui_PopStyleColor(ctx)
        elseif #fx_list == 0 then
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), COL.text_dim)
            r.ImGui_Text(ctx, "No FX on this track")
            r.ImGui_PopStyleColor(ctx)
        else
            local _, track_name = r.GetTrackName(track)
            r.ImGui_PushFont(ctx, font_large, 15)
            r.ImGui_Text(ctx, track_name)
            r.ImGui_PopFont(ctx)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), COL.text_dim)
            r.ImGui_Text(ctx, #fx_list .. " FX on track")
            r.ImGui_PopStyleColor(ctx)
            r.ImGui_Spacing(ctx)
            r.ImGui_Separator(ctx)
            r.ImGui_Spacing(ctx)

            if not capturing then
                if r.ImGui_Button(ctx, "Select All") then
                    for i = 1, #fx_list do fx_checked[fx_list[i].index] = true end
                end
                r.ImGui_SameLine(ctx)
                if r.ImGui_Button(ctx, "Deselect All") then
                    for i = 1, #fx_list do fx_checked[fx_list[i].index] = false end
                end
                r.ImGui_SameLine(ctx)
                local missing_count = 0
                for i = 1, #fx_list do
                    if not fx_has_screenshot[fx_list[i].index] then missing_count = missing_count + 1 end
                end
                if missing_count == 0 then r.ImGui_BeginDisabled(ctx) end
                if r.ImGui_Button(ctx, "Missing (" .. missing_count .. ")") then
                    for i = 1, #fx_list do
                        fx_checked[fx_list[i].index] = not fx_has_screenshot[fx_list[i].index]
                    end
                end
                if missing_count == 0 then r.ImGui_EndDisabled(ctx) end

                local any_checked = false
                for i = 1, #fx_list do
                    if fx_checked[fx_list[i].index] then any_checked = true break end
                end

                if any_checked then
                    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), COL.accent)
                    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), COL.accent_hover)
                    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), COL.accent_active)
                else
                    r.ImGui_BeginDisabled(ctx)
                end
                if r.ImGui_Button(ctx, "  Snap!  ") then
                    StartCapture()
                end
                if any_checked then
                    r.ImGui_PopStyleColor(ctx, 3)
                else
                    r.ImGui_EndDisabled(ctx)
                end
            else
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), COL.accent)
                r.ImGui_BeginDisabled(ctx)
                r.ImGui_Button(ctx, "  Working...  ")
                r.ImGui_EndDisabled(ctx)
                r.ImGui_PopStyleColor(ctx)
            end

            r.ImGui_Spacing(ctx)
            r.ImGui_Separator(ctx)
            r.ImGui_Spacing(ctx)

            local bottom_h = r.ImGui_GetFrameHeightWithSpacing(ctx) * 3 + 20
            if status_msg ~= "" then
                bottom_h = bottom_h + r.ImGui_GetFrameHeightWithSpacing(ctx)
            end

            if r.ImGui_BeginChild(ctx, "fx_list", 0, -bottom_h, 1) then
                for i = 1, #fx_list do
                    r.ImGui_PushID(ctx, i)
                    local has_ss = fx_has_screenshot[fx_list[i].index]
                    local label = (has_ss and "  " or "  ") .. fx_list[i].name
                    if has_ss then
                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), COL.status_ok)
                        r.ImGui_Text(ctx, "\xe2\x97\x8f")
                        r.ImGui_PopStyleColor(ctx)
                    else
                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), COL.text_dim)
                        r.ImGui_Text(ctx, "\xe2\x97\x8b")
                        r.ImGui_PopStyleColor(ctx)
                    end
                    r.ImGui_SameLine(ctx)
                    local changed, val = r.ImGui_Checkbox(ctx, fx_list[i].name, fx_checked[fx_list[i].index])
                    if changed then fx_checked[fx_list[i].index] = val end
                    r.ImGui_PopID(ctx)
                end
                r.ImGui_EndChild(ctx)
            end
        end

        if status_msg ~= "" then
            r.ImGui_Spacing(ctx)
            local col = COL.text_dim
            if status_type == "ok" then col = COL.status_ok
            elseif status_type == "busy" then col = COL.status_busy
            elseif status_type == "err" then col = COL.status_err
            end
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), col)
            r.ImGui_Text(ctx, status_msg)
            r.ImGui_PopStyleColor(ctx)
        end

        r.ImGui_Spacing(ctx)
        r.ImGui_Separator(ctx)
        r.ImGui_Spacing(ctx)
        local changed_slider
        r.ImGui_SetNextItemWidth(ctx, -1)
        changed_slider, config.screenshot_delay = r.ImGui_SliderDouble(ctx, "##delay", config.screenshot_delay, 0.1, 3.0, "Delay: %.1fs")

        local changed_mode
        changed_mode, use_screen_capture = r.ImGui_Checkbox(ctx, "Screen capture (for OpenGL/DX plugins)", use_screen_capture)

        r.ImGui_End(ctx)
    end
    r.ImGui_PopFont(ctx)
    PopTheme()

    if open then
        r.defer(Loop)
    end
end

local track = r.GetSelectedTrack(0, 0)
if not track then
    r.ShowMessageBox("No track selected.", "TK Snapshot FX", 0)
    return
end
if r.TrackFX_GetCount(track) == 0 then
    r.ShowMessageBox("No FX on the selected track.", "TK Snapshot FX", 0)
    return
end

r.defer(Loop)
