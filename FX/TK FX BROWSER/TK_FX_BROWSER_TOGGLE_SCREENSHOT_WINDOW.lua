-- @description TK FX BROWSER - Toggle Screenshot Window
-- @author TouristKiller
-- @version 1.0
-- @about Toggle the Screenshot Window panel of TK FX BROWSER (show/hide while keeping the browser running)

local r = reaper

local function IsFXBrowserRunning()
    local state = r.GetExtState("TK_FX_BROWSER", "running")
    return state == "true"
end

local function ToggleScreenshotWindow()
    if not IsFXBrowserRunning() then
        r.ShowMessageBox("TK FX BROWSER is not currently running.\n\nPlease start it first.", "FX Browser Not Running", 0)
        return
    end

    r.SetExtState("TK_FX_BROWSER", "toggle_screenshot_window", "1", false)
end

ToggleScreenshotWindow()
