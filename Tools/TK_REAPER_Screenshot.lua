-- @description TK REAPER Screenshot
-- @author TouristKiller
-- @version 1.0
-- @about
--   Simple screenshot tool for REAPER main window
--   Captures the entire REAPER window and saves it as PNG
--   Max width 300px with automatic aspect ratio

local r = reaper
local script_name = "TK REAPER Screenshot"

if not r.JS_Window_Find then
    r.ShowMessageBox("js_ReaScriptAPI extension is required!\n\nPlease install it via ReaPack.", "Missing Extension", 0)
    return
end

local ctx = r.ImGui_CreateContext(script_name)
local font = r.ImGui_CreateFont('Consolas', 14)
if not font then
    font = r.ImGui_CreateFont('sans-serif', 14)
end
r.ImGui_Attach(ctx, font)

function GetPhysicalScreenResolution()
    local main_hwnd = r.GetMainHwnd()
    if main_hwnd and r.JS_Window_GetRect then
        local retval, left, top, right, bottom = r.JS_Window_GetRect(main_hwnd)
        if retval then
            local center_x = (left + right) / 2
            local center_y = (top + bottom) / 2
            
            local ffi = package.loaded.ffi
            if ffi then
                pcall(function()
                    ffi.cdef[[
                        typedef struct { long left; long top; long right; long bottom; } RECT;
                        typedef struct {
                            unsigned int cbSize;
                            RECT rcMonitor;
                            RECT rcWork;
                            unsigned int dwFlags;
                        } MONITORINFO;
                        typedef void* HMONITOR;
                        typedef void* HWND;
                        typedef int BOOL;
                        
                        HMONITOR MonitorFromWindow(HWND hwnd, unsigned int dwFlags);
                        BOOL GetMonitorInfoA(HMONITOR hMonitor, MONITORINFO* lpmi);
                    ]]
                end)
                
                local MONITOR_DEFAULTTONEAREST = 2
                local success, hMonitor = pcall(function() 
                    return ffi.C.MonitorFromWindow(ffi.cast("void*", main_hwnd), MONITOR_DEFAULTTONEAREST)
                end)
                
                if success and hMonitor then
                    local mi = ffi.new("MONITORINFO")
                    mi.cbSize = ffi.sizeof("MONITORINFO")
                    
                    local success2 = pcall(function()
                        return ffi.C.GetMonitorInfoA(hMonitor, mi)
                    end)
                    
                    if success2 then
                        local mon_w = mi.rcMonitor.right - mi.rcMonitor.left
                        local mon_h = mi.rcMonitor.bottom - mi.rcMonitor.top
                        
                        if mon_w > 0 and mon_h > 0 then
                            return mon_w, mon_h
                        end
                    end
                end
            end
        end
    end
    
    if r.GetOS():match("Win") then
        local ffi = package.loaded.ffi
        if ffi then
            local success = pcall(function()
                ffi.cdef[[
                    int GetSystemMetrics(int nIndex);
                ]]
            end)
            if success then
                local SM_CXSCREEN = 0
                local SM_CYSCREEN = 1
                local success_w, logical_w = pcall(function() return ffi.C.GetSystemMetrics(SM_CXSCREEN) end)
                local success_h, logical_h = pcall(function() return ffi.C.GetSystemMetrics(SM_CYSCREEN) end)
                
                if success_w and success_h and logical_w > 0 and logical_h > 0 then
                    local _, dpi_scale = r.get_config_var_string("uiscale")
                    dpi_scale = tonumber(dpi_scale) or 1.0
                    return math.floor(logical_w * dpi_scale), math.floor(logical_h * dpi_scale)
                end
            end
        end
    end
    
    local _, dpi_scale = r.get_config_var_string("uiscale")
    dpi_scale = tonumber(dpi_scale) or 1.0
    return math.floor(1920 * dpi_scale), math.floor(1080 * dpi_scale)
end

local config = {
    max_width = 300,
    aspect_ratio = 16/9,
    save_path = r.GetResourcePath() .. "/Screenshots/",
    last_screenshot = nil,
    preview_texture = nil,
    status_message = "Ready to capture",
    status_time = 0,
    capture_mode = 1,
    fullscreen_width = 1920,
    fullscreen_height = 1080,
    resolution_preset = 2,
    original_size = false
}

local resolution_presets = {
    {name = "1280x720 (HD)", w = 1280, h = 720},
    {name = "1600x900 (HD+)", w = 1600, h = 900},
    {name = "1920x1080 (Full HD)", w = 1920, h = 1080},
    {name = "2560x1440 (QHD)", w = 2560, h = 1440},
    {name = "3440x1440 (UW QHD)", w = 3440, h = 1440},
    {name = "3840x2160 (4K UHD)", w = 3840, h = 2160},
    {name = "4096x2160 (DCI 4K)", w = 4096, h = 2160},
    {name = "5120x2880 (5K)", w = 5120, h = 2880},
    {name = "7680x4320 (8K)", w = 7680, h = 4320},
}

config.fullscreen_width, config.fullscreen_height = GetPhysicalScreenResolution()

function LoadSettings()
    if r.HasExtState("TK_Screenshot", "max_width") then
        config.max_width = tonumber(r.GetExtState("TK_Screenshot", "max_width")) or 300
    end
    if r.HasExtState("TK_Screenshot", "capture_mode") then
        config.capture_mode = tonumber(r.GetExtState("TK_Screenshot", "capture_mode")) or 1
    end
    if r.HasExtState("TK_Screenshot", "resolution_preset") then
        config.resolution_preset = tonumber(r.GetExtState("TK_Screenshot", "resolution_preset")) or 3
    end
    if r.HasExtState("TK_Screenshot", "fullscreen_width") then
        config.fullscreen_width = tonumber(r.GetExtState("TK_Screenshot", "fullscreen_width")) or config.fullscreen_width
    end
    if r.HasExtState("TK_Screenshot", "fullscreen_height") then
        config.fullscreen_height = tonumber(r.GetExtState("TK_Screenshot", "fullscreen_height")) or config.fullscreen_height
    end
    if r.HasExtState("TK_Screenshot", "original_size") then
        config.original_size = r.GetExtState("TK_Screenshot", "original_size") == "true"
    end
end

function SaveSettings()
    r.SetExtState("TK_Screenshot", "max_width", tostring(config.max_width), true)
    r.SetExtState("TK_Screenshot", "capture_mode", tostring(config.capture_mode), true)
    r.SetExtState("TK_Screenshot", "resolution_preset", tostring(config.resolution_preset), true)
    r.SetExtState("TK_Screenshot", "fullscreen_width", tostring(config.fullscreen_width), true)
    r.SetExtState("TK_Screenshot", "fullscreen_height", tostring(config.fullscreen_height), true)
    r.SetExtState("TK_Screenshot", "original_size", tostring(config.original_size), true)
end

LoadSettings()

function EnsureScreenshotFolder()
    local path = config.save_path
    if not r.file_exists(path) then
        r.RecursiveCreateDirectory(path, 0)
    end
end

function GetTimestamp()
    return os.date("%Y-%m-%d_%H-%M-%S")
end

function CaptureREAPERWindow()
    local hwnd, w, h, left, top
    
    local script_hwnd = nil
    if config.capture_mode == 2 then
        script_hwnd = r.JS_Window_Find(script_name, true)
        if script_hwnd then
            r.JS_Window_Show(script_hwnd, "HIDE")
        end
        r.defer(function()
            r.time_precise()
        end)
    end
    
    if config.capture_mode == 1 then
        local arrange = r.JS_Window_FindChildByID(r.GetMainHwnd(), 0x3E8)
        hwnd = r.JS_Window_GetParent(arrange)
        
        if not hwnd or hwnd == arrange then
            hwnd = r.GetMainHwnd()
        end
        
        if not hwnd then
            return false, "REAPER window not found"
        end
        
        local retval, left_t, top_t, right, bottom = r.JS_Window_GetClientRect(hwnd)
        left, top = left_t, top_t
        w, h = right - left, bottom - top
        
    else
        hwnd = nil
        left, top = 0, 0
        
        w, h = config.fullscreen_width, config.fullscreen_height
    end
    
    if w <= 0 or h <= 0 then
        return false, "Invalid window dimensions"
    end
    
    local scale = 1
    local newW = w
    local newH = h
    
    if not config.original_size then
        scale = config.max_width / w
        newW = config.max_width
        newH = math.floor(h * scale)
    end
    
    EnsureScreenshotFolder()
    local mode_suffix = config.capture_mode == 1 and "" or "_FULLSCREEN"
    local filename = config.save_path .. "REAPER" .. mode_suffix .. "_" .. GetTimestamp() .. ".png"
    
    local srcDC
    if config.capture_mode == 1 then
        srcDC = r.JS_GDI_GetClientDC(hwnd)
    else
        srcDC = r.JS_GDI_GetScreenDC()
    end
    
    if not srcDC then
        return false, "Failed to get device context"
    end
    
    local srcBmp = r.JS_LICE_CreateBitmap(true, w, h)
    local srcDC_LICE = r.JS_LICE_GetDC(srcBmp)
    
    local src_x = config.capture_mode == 1 and 0 or left
    local src_y = config.capture_mode == 1 and 0 or top
    r.JS_GDI_Blit(srcDC_LICE, 0, 0, srcDC, src_x, src_y, w, h)
    
    local destBmp = r.JS_LICE_CreateBitmap(true, newW, newH)
    r.JS_LICE_ScaledBlit(destBmp, 0, 0, newW, newH, srcBmp, 0, 0, w, h, 1, "FAST")
    
    local save_result = r.JS_LICE_WritePNG(filename, destBmp, false)
    
    if config.capture_mode == 1 then
        r.JS_GDI_ReleaseDC(hwnd, srcDC)
    else
        r.JS_GDI_ReleaseDC(nil, srcDC)
    end
    r.JS_LICE_DestroyBitmap(srcBmp)
    
    if script_hwnd then
        r.JS_Window_Show(script_hwnd, "SHOW")
    end
    
    if config.preview_texture then
        r.JS_LICE_DestroyBitmap(config.preview_texture)
    end
    config.preview_texture = destBmp
    config.last_screenshot = filename
    
    return true, filename, newW, newH
end

function SetStatus(message, duration)
    config.status_message = message
    config.status_time = r.time_precise() + (duration or 3)
end

function loop()
    local window_flags = r.ImGui_WindowFlags_NoCollapse() | 
                        r.ImGui_WindowFlags_AlwaysAutoResize()
    
    r.ImGui_PushFont(ctx, font, 14)
    r.ImGui_SetNextWindowSize(ctx, 400, 300, r.ImGui_Cond_FirstUseEver())
    
    local visible, open = r.ImGui_Begin(ctx, script_name, true, window_flags)
    
    if visible then
        r.ImGui_TextColored(ctx, 0x00AAFFFF, "REAPER Window Screenshot Tool")
        r.ImGui_Separator(ctx)
        r.ImGui_Spacing(ctx)
        
        r.ImGui_Text(ctx, "Settings:")
        r.ImGui_Indent(ctx)
        
        local changed, new_original = r.ImGui_Checkbox(ctx, "Original Size (no scaling)", config.original_size)
        if changed then
            config.original_size = new_original
            SaveSettings()
        end
        
        if config.original_size then
            r.ImGui_BeginDisabled(ctx)
        end
        local width_changed, new_width = r.ImGui_SliderInt(ctx, "Max Width", config.max_width, 100, 1000)
        if width_changed then
            config.max_width = new_width
            SaveSettings()
        end
        if config.original_size then
            r.ImGui_EndDisabled(ctx)
        end
        
        r.ImGui_Spacing(ctx)
        r.ImGui_Text(ctx, "Capture Mode:")
        local mode_changed, new_mode = r.ImGui_RadioButtonEx(ctx, "REAPER Window Only", config.capture_mode, 1)
        if mode_changed then 
            config.capture_mode = new_mode 
            SaveSettings()
        end
        
        r.ImGui_SameLine(ctx)
        mode_changed, new_mode = r.ImGui_RadioButtonEx(ctx, "Full Screen", config.capture_mode, 2)
        if mode_changed then 
            config.capture_mode = new_mode
            SaveSettings()
        end
        
        if config.capture_mode == 2 then
            r.ImGui_Spacing(ctx)
            r.ImGui_TextColored(ctx, 0xFFAA00FF, "Screen Resolution Preset:")
            
            local preset_names = {}
            for i, preset in ipairs(resolution_presets) do
                preset_names[i] = preset.name
            end
            local preset_list = table.concat(preset_names, "\0") .. "\0"
            
            r.ImGui_SetNextItemWidth(ctx, 250)
            local changed, new_preset = r.ImGui_Combo(ctx, "##preset", config.resolution_preset - 1, preset_list)
            if changed then
                config.resolution_preset = new_preset + 1
                local preset = resolution_presets[config.resolution_preset]
                if preset then
                    config.fullscreen_width = preset.w
                    config.fullscreen_height = preset.h
                    SaveSettings()
                end
            end
            
            r.ImGui_Spacing(ctx)
            
            r.ImGui_TextColored(ctx, 0x00FF00FF, string.format("Will capture: %dx%d pixels", config.fullscreen_width, config.fullscreen_height))
            
            r.ImGui_Spacing(ctx)
            if r.ImGui_Button(ctx, "🔍 Try Auto Detect", 150) then
                config.fullscreen_width, config.fullscreen_height = GetPhysicalScreenResolution()
            end
        end
        
        r.ImGui_Spacing(ctx)
        r.ImGui_Text(ctx, string.format("Output folder: %s", config.save_path))
        r.ImGui_Unindent(ctx)
        
        r.ImGui_Spacing(ctx)
        r.ImGui_Separator(ctx)
        r.ImGui_Spacing(ctx)
        
        local button_width = r.ImGui_GetContentRegionAvail(ctx)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x00AA00FF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0x00CC00FF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0x008800FF)
        
        if r.ImGui_Button(ctx, "📷 CAPTURE SCREENSHOT", button_width, 40) then
            local success, result, w, h = CaptureREAPERWindow()
            if success then
                SetStatus(string.format("✓ Saved: %s (%dx%d)", result, w, h), 5)
            else
                SetStatus("✗ Error: " .. result, 5)
            end
        end
        
        r.ImGui_PopStyleColor(ctx, 3)
        
        r.ImGui_Spacing(ctx)
        
        if r.time_precise() < config.status_time then
            r.ImGui_TextWrapped(ctx, config.status_message)
        end
        
        if config.preview_texture and config.last_screenshot then
            r.ImGui_Spacing(ctx)
            r.ImGui_Separator(ctx)
            r.ImGui_Spacing(ctx)
            r.ImGui_Text(ctx, "Last Capture Preview:")
            
            r.ImGui_Spacing(ctx)
            r.ImGui_TextWrapped(ctx, config.last_screenshot)
            
            r.ImGui_Spacing(ctx)
            local button_width = r.ImGui_GetContentRegionAvail(ctx)
            if r.ImGui_Button(ctx, "📁 Open Screenshot Folder", button_width) then
                if r.GetOS():match("Win") then
                    os.execute('explorer "' .. config.save_path:gsub("/", "\\") .. '"')
                else
                    os.execute('open "' .. config.save_path .. '"')
                end
            end
        end
        
        r.ImGui_End(ctx)
    end
    
    r.ImGui_PopFont(ctx)
    
    if open then
        r.defer(loop)
    else
        if config.preview_texture then
            r.JS_LICE_DestroyBitmap(config.preview_texture)
        end
        r.ImGui_DestroyContext(ctx)
    end
end

EnsureScreenshotFolder()
SetStatus("Ready to capture REAPER window", 0)

r.defer(loop)
