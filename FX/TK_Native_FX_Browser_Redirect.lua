-- @description TK Native FX Browser Redirect
-- @author TouristKiller
-- @version 1.2.0
-- @about
--   Replaces REAPER's native "Add FX" / "Replace FX" / "Browse FX" windows
--   with an alternative FX browser of your choice.
--   Requires js_ReaScriptAPI.
--
--   Run this action again to stop the monitor (toggle).
--   Configure the alternative via:
--     "TK Native FX Browser Redirect - Settings"

local r = reaper

if not r.JS_Window_ArrayFind then
    r.MB("This action requires the 'js_ReaScriptAPI' extension.\nInstall it via ReaPack.",
        "TK FX Redirect", 0)
    return
end

local NS         = "TK_FX_REDIRECT"
local CONFIG_NS  = "TK_FX_REDIRECT_CONFIG"

local DEFAULTS = {
    script_path              = "TK Scripts/FX/TK_FX_BROWSER.lua",
    command_id               = "",
    action_name_match        = "TK_FX_BROWSER.lua",
    running_extstate_section = "TK_FX_BROWSER",
    running_extstate_key     = "running",
    visibility_extstate_key  = "visibility",
    ignore_titles            = "TK FX BROWSER\nTK FX Browser\nDSG Plugin\nSexan FX Browser",
}

local function getCfg(key)
    local v = r.GetExtState(CONFIG_NS, key)
    if v == nil or v == "" then return DEFAULTS[key] end
    return v
end

local function loadConfig()
    local cfg = {}
    for k in pairs(DEFAULTS) do cfg[k] = getCfg(k) end
    cfg.ignore_title_substrings = {}
    for line in (cfg.ignore_titles or ""):gmatch("[^\r\n]+") do
        local trimmed = line:match("^%s*(.-)%s*$")
        if trimmed ~= "" then
            cfg.ignore_title_substrings[#cfg.ignore_title_substrings + 1] = trimmed
        end
    end
    return cfg
end

local CONFIG = loadConfig()

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

local function shouldRedirect(title)
    if not title or title == "" then return false end
    for _, sub in ipairs(CONFIG.ignore_title_substrings) do
        if title:find(sub, 1, true) then return false end
    end
    for _, prefix in ipairs(TITLE_PREFIXES) do
        if title:sub(1, #prefix) == prefix then
            return true
        end
    end
    return false
end

local function resolveScriptPath(p)
    if not p or p == "" then return nil end
    if p:match("^[A-Za-z]:[/\\]") or p:sub(1, 1) == "/" then
        return p
    end
    return r.GetResourcePath() .. "/Scripts/" .. p
end

local function findActionIDByName(needle)
    if not needle or needle == "" or not r.kbd_enumerateActions then return 0 end
    local i = 0
    while true do
        local cmd, name = r.kbd_enumerateActions(0, i)
        if not cmd or cmd == 0 then break end
        if name and name:find(needle, 1, true) then
            return cmd
        end
        i = i + 1
        if i > 50000 then break end
    end
    return 0
end

local function resolveBrowserCmd()
    if CONFIG.command_id and CONFIG.command_id ~= "" then
        local cmd = r.NamedCommandLookup(CONFIG.command_id)
        if cmd and cmd ~= 0 then return cmd end
    end

    local path = resolveScriptPath(CONFIG.script_path)
    if path and r.file_exists(path) and r.AddRemoveReaScript then
        local cmd = r.AddRemoveReaScript(true, 0, path, true)
        if cmd and cmd ~= 0 then return cmd end
    end

    local cmd = findActionIDByName(CONFIG.action_name_match)
    if cmd and cmd ~= 0 then return cmd end

    return 0
end

local BROWSER_CMD = resolveBrowserCmd()

local function openBrowser()
    local sect = CONFIG.running_extstate_section
    if sect and sect ~= "" then
        if r.GetExtState(sect, CONFIG.running_extstate_key or "running") == "true" then
            if CONFIG.visibility_extstate_key and CONFIG.visibility_extstate_key ~= "" then
                r.SetExtState(sect, CONFIG.visibility_extstate_key, "visible", true)
            end
            return
        end
    end
    if BROWSER_CMD == 0 then
        BROWSER_CMD = resolveBrowserCmd()
    end
    if BROWSER_CMD ~= 0 then
        r.Main_OnCommand(BROWSER_CMD, 0)
        if sect and sect ~= "" and CONFIG.visibility_extstate_key and CONFIG.visibility_extstate_key ~= "" then
            r.SetExtState(sect, CONFIG.visibility_extstate_key, "visible", true)
        end
    else
        r.ShowConsoleMsg("[TK FX REDIRECT] Could not find an alternative FX browser.\n" ..
            "Open 'TK Native FX Browser Redirect - Settings' to configure it.\n")
    end
end

local killed = {}
local last_open_time = 0
local OPEN_DEBOUNCE = 1.0

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
                            r.JS_Window_Show(hwnd, "HIDE")
                            r.JS_WindowMessage_Send(hwnd, "WM_CLOSE", 0, 0, 0, 0)
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
            openBrowser()
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
        CONFIG = loadConfig()
        BROWSER_CMD = resolveBrowserCmd()
    end
end

local function loop()
    if r.GetExtState(NS, "stop") == "1" then
        return
    end
    checkConfigReload()
    killNativeBrowsers()
    r.defer(loop)
end

r.defer(loop)
