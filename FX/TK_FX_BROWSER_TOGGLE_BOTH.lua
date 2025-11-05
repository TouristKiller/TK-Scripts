-- @description TK FX BROWSER - Toggle Both (Main + Mini)
-- @author TouristKiller
-- @version 1.0.0
-- @about Toggle visibility of both TK FX BROWSER and Mini windows simultaneously

local r = reaper

local function IsFXBrowserRunning()
    local state = r.GetExtState("TK_FX_BROWSER", "running")
    return state == "true"
end

local function IsFXBrowserMiniRunning()
    local state = r.GetExtState("TK_FX_BROWSER_MINI", "running")
    return state == "true"
end

local function ToggleBothVisibility()
    local main_running = IsFXBrowserRunning()
    local mini_running = IsFXBrowserMiniRunning()
    
    -- If neither is running, ask to start main browser
    if not main_running and not mini_running then
        local result = r.ShowMessageBox("Neither TK FX BROWSER nor Mini is currently running.\n\nDo you want to start the main browser?", "FX Browser Not Running", 4)
        if result == 6 then
            local script_path = r.GetResourcePath() .. "/Scripts/TK Scripts/FX/TK_FX_BROWSER.lua"
            if r.file_exists(script_path) then
                r.Main_OnCommand(r.NamedCommandLookup("_RS7d3c_906867d0f022ab4b69695017f13a2944"), 0)
                r.SetExtState("TK_FX_BROWSER", "visibility", "visible", true)
            end
        end
        return
    end
    
    -- Toggle main browser if running
    if main_running then
        local current_state = r.GetExtState("TK_FX_BROWSER", "visibility")
        if current_state == "hidden" then
            r.SetExtState("TK_FX_BROWSER", "visibility", "visible", true)
        else
            r.SetExtState("TK_FX_BROWSER", "visibility", "hidden", true)
        end
    end
    
    -- Toggle mini browser if running
    if mini_running then
        local current_state = r.GetExtState("TK_FX_BROWSER_MINI", "visibility")
        if current_state == "hidden" then
            r.SetExtState("TK_FX_BROWSER_MINI", "visibility", "visible", true)
        else
            r.SetExtState("TK_FX_BROWSER_MINI", "visibility", "hidden", true)
        end
    end
end

ToggleBothVisibility()
