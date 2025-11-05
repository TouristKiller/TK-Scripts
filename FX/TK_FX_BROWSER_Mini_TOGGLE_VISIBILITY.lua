-- @description TK FX BROWSER Mini - Toggle Visibility
-- @author TouristKiller
-- @version 1.0.0
-- @about Toggle visibility of TK FX BROWSER Mini window (hide/show while keeping it running)

local r = reaper

local function IsFXBrowserMiniRunning()
    local state = r.GetExtState("TK_FX_BROWSER_MINI", "running")
    return state == "true"
end

local function ToggleVisibility()
    if not IsFXBrowserMiniRunning() then
        local result = r.ShowMessageBox("TK FX BROWSER Mini is not currently running.\n\nDo you want to start it now?", "FX Browser Mini Not Running", 4)
        if result == 6 then
            local script_path = r.GetResourcePath() .. "/Scripts/TK Scripts/FX/TK_FX_BROWSER Mini.lua"
            if r.file_exists(script_path) then
                r.Main_OnCommand(r.NamedCommandLookup("_RS7d3c_906867d0f022ab4b69695017f13a2944"), 0)
                r.SetExtState("TK_FX_BROWSER_MINI", "visibility", "visible", true)
            else
                r.ShowMessageBox("Could not find TK_FX_BROWSER Mini.lua script.\n\nPlease start it manually from the Actions list.", "Script Not Found", 0)
            end
        end
        return
    end
    
    local current_state = r.GetExtState("TK_FX_BROWSER_MINI", "visibility")
    
    if current_state == "hidden" then
        r.SetExtState("TK_FX_BROWSER_MINI", "visibility", "visible", true)
    else
        r.SetExtState("TK_FX_BROWSER_MINI", "visibility", "hidden", true)
    end
end

ToggleVisibility()
