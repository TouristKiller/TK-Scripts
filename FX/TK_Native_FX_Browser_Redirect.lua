-- @description TK Native FX Browser Redirect
-- @author TouristKiller
-- @version 1.3.1
-- @about
--   Replaces REAPER's native "Add FX" / "Replace FX" / "Browse FX" windows
--   with the FX browser action configured by command ID.
--   Requires js_ReaScriptAPI.
--
--   Run this action again to stop the monitor (toggle).
--   Configure the command ID via:
--     "TK Native FX Browser Redirect - Settings"

local r = reaper

if not r.JS_Window_ArrayFind then
    r.MB("This action requires the 'js_ReaScriptAPI' extension.\nInstall it via ReaPack.",
        "TK FX Redirect", 0)
    return
end

local NS        = "TK_FX_REDIRECT"
local CONFIG_NS = "TK_FX_REDIRECT_CONFIG"

local function trim(s)
    return (s or ""):match("^%s*(.-)%s*$")
end

local function getCommandID()
    return trim(r.GetExtState(CONFIG_NS, "command_id"))
end

local function resolveCommandID(command_id)
    command_id = trim(command_id)
    if command_id == "" then return 0 end

    local numeric = tonumber(command_id)
    if numeric and numeric ~= 0 then return numeric end

    local cmd = r.NamedCommandLookup(command_id)
    if cmd and cmd ~= 0 then return cmd end

    return 0
end

local COMMAND_ID = getCommandID()
local BROWSER_CMD = resolveCommandID(COMMAND_ID)

local _, _, sectionID, cmdID = r.get_action_context()

if r.GetExtState(NS, "running") == "true" then
    r.SetExtState(NS, "stop", "1", false)
    return
end

r.SetExtState(NS, "running", "true", false)
r.SetExtState(NS, "stop", "", false)
r.SetToggleCommandState(sectionID, cmdID, 1)
r.RefreshToolbar2(sectionID, cmdID)

r.atexit(function()
    r.SetExtState(NS, "running", "false", false)
    r.SetExtState(NS, "stop", "", false)
    r.SetToggleCommandState(sectionID, cmdID, 0)
    r.RefreshToolbar2(sectionID, cmdID)
end)

local TITLE_PREFIXES = {
    "Add FX to",
    "Browse FX",
    "Replace FX",
}

local IGNORE_TITLE_SUBSTRINGS = {
    "TK FX BROWSER",
    "TK FX Browser",
    "DSG Plugin",
    "Sexan FX Browser",
}

local function shouldRedirect(title)
    if not title or title == "" then return false end

    for _, sub in ipairs(IGNORE_TITLE_SUBSTRINGS) do
        if title:find(sub, 1, true) then return false end
    end

    for _, prefix in ipairs(TITLE_PREFIXES) do
        if title:sub(1, #prefix) == prefix then
            return true
        end
    end

    return false
end

local function refreshCommandID()
    COMMAND_ID = getCommandID()
    BROWSER_CMD = resolveCommandID(COMMAND_ID)
end

local function showRunningTKBrowser()
    local sections = {
        "TK_FX_BROWSER",
        "TK_FX_BROWSER_MINI",
    }

    for _, section in ipairs(sections) do
        if r.GetExtState(section, "running") == "true" then
            if r.GetExtState(section, "visibility") == "hidden" then
                r.SetExtState(section, "visibility", "visible", true)
            end
            return true
        end
    end

    return false
end

local function openBrowser()
    if showRunningTKBrowser() then
        return
    end

    if BROWSER_CMD == 0 then
        BROWSER_CMD = resolveCommandID(COMMAND_ID)
    end

    if BROWSER_CMD ~= 0 then
        if r.GetToggleCommandStateEx and r.GetToggleCommandStateEx(0, BROWSER_CMD) == 1 then
            return
        end
        r.Main_OnCommand(BROWSER_CMD, 0)
    else
        r.ShowConsoleMsg("[TK FX REDIRECT] No valid alternative FX browser command ID configured.\n" ..
            "Open 'TK Native FX Browser Redirect - Settings' and enter a command ID.\n")
    end
end

local killed = {}
local last_open_time = 0
local OPEN_DEBOUNCE = 1.0
local pending_open = 0

local VK_ESCAPE = 0x1B

local function dismissNativeWindow(hwnd)
    pcall(r.JS_WindowMessage_Post, hwnd, "WM_KEYDOWN", VK_ESCAPE, 0, 0, 0)
    pcall(r.JS_WindowMessage_Post, hwnd, "WM_KEYUP",   VK_ESCAPE, 0, 0, 0)
    pcall(r.JS_WindowMessage_Post, hwnd, "WM_CLOSE",   0,         0, 0, 0)
    pcall(r.JS_Window_Show, hwnd, "HIDE")
end

local function killNativeBrowsers()
    local hit = false

    for addr in pairs(killed) do
        local hwnd = r.JS_Window_HandleFromAddress(addr)
        if not hwnd or not r.JS_Window_IsVisible(hwnd) then
            killed[addr] = nil
        end
    end

    for _, prefix in ipairs(TITLE_PREFIXES) do
        local arr = r.new_array({}, 64)
        local count = r.JS_Window_ArrayFind(prefix, false, arr)
        if count and count > 0 then
            for i = 1, count do
                local addr = arr[i]
                if addr and addr ~= 0 and not killed[addr] then
                    local hwnd = r.JS_Window_HandleFromAddress(addr)
                    if hwnd and r.JS_Window_IsVisible(hwnd) then
                        local title = r.JS_Window_GetTitle(hwnd) or ""
                        if shouldRedirect(title) then
                            dismissNativeWindow(hwnd)
                            killed[addr] = true
                            hit = true
                        end
                    end
                end
            end
        end
    end

    if hit then
        local now = r.time_precise()
        if (now - last_open_time) > OPEN_DEBOUNCE then
            last_open_time = now
            pending_open = 3
        end
    end
end

local last_config_check = 0
local function checkConfigReload()
    local now = r.time_precise()
    if now - last_config_check < 1.0 then return end
    last_config_check = now

    if r.GetExtState(CONFIG_NS, "_changed") == "1" then
        r.SetExtState(CONFIG_NS, "_changed", "0", false)
        refreshCommandID()
    end
end

local SCAN_INTERVAL = 0.15
local BURST_DURATION = 0.8
local last_scan = 0
local burst_until = 0
local last_mouse_state = 0
local last_vkeys_hash = 0

local function inputBurstTrigger(now)
    local mouse = r.JS_Mouse_GetState and r.JS_Mouse_GetState(31) or 0
    if mouse ~= 0 and last_mouse_state == 0 then
        burst_until = now + BURST_DURATION
    end
    last_mouse_state = mouse

    if r.JS_VKeys_GetState then
        local state = r.JS_VKeys_GetState(0)
        if state and state ~= "" then
            local hash = 0
            for i = 1, #state do
                local b = state:byte(i)
                if b ~= 0 then hash = hash + i * b end
            end
            if hash ~= last_vkeys_hash and hash ~= 0 then
                burst_until = now + BURST_DURATION
            end
            last_vkeys_hash = hash
        end
    end
end

local function loop()
    if r.GetExtState(NS, "stop") == "1" then
        return
    end

    checkConfigReload()

    local now = r.time_precise()
    inputBurstTrigger(now)
    if now < burst_until and (now - last_scan) >= SCAN_INTERVAL then
        last_scan = now
        killNativeBrowsers()
    end

    if pending_open > 0 then
        pending_open = pending_open - 1
        if pending_open == 0 then
            openBrowser()
        end
    end

    r.defer(loop)
end

r.defer(loop)
