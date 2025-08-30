-- @description TK FX BROWSER - Toggle Visibility
-- @author TouristKiller
-- @version 1.0.0
-- @about Toggle visibility of TK FX BROWSER window (hide/show while keeping it running)

local r = reaper

local function IsFXBrowserRunning()
    local state = r.GetExtState("TK_FX_BROWSER", "running")
    return state == "true"
end

local function ToggleVisibility()
    if not IsFXBrowserRunning() then
        local result = r.ShowMessageBox("TK FX BROWSER is not currently running.\n\nDo you want to start it now?", "FX Browser Not Running", 4)
        if result == 6 then
            local script_path = r.GetResourcePath() .. "/Scripts/TK Scripts/FX/TK_FX_BROWSER_TEST.lua"
            if r.file_exists(script_path) then
                r.Main_OnCommand(r.NamedCommandLookup("_RS7d3c_906867d0f022ab4b69695017f13a2944"), 0)
                r.ShowConsoleMsg("TK FX BROWSER: Starting script...\n")
                r.SetExtState("TK_FX_BROWSER", "visibility", "visible", true)
            else
                r.ShowMessageBox("Could not find TK_FX_BROWSER_TEST.lua script.\n\nPlease start it manually from the Actions list.", "Script Not Found", 0)
            end
        end
        return
    end
    
    local current_state = r.GetExtState("TK_FX_BROWSER", "visibility")
    
    if current_state == "hidden" then
        r.SetExtState("TK_FX_BROWSER", "visibility", "visible", true)
        r.ShowConsoleMsg("TK FX BROWSER: Window shown\n")
    else
        r.SetExtState("TK_FX_BROWSER", "visibility", "hidden", true)
        r.ShowConsoleMsg("TK FX BROWSER: Window hidden (still running in background)\n")
    end
end

ToggleVisibility()
