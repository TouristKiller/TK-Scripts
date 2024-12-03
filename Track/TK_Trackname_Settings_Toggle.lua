-- @description TK_Trackname_Settings_Toggle
-- @author TouristKiller
-- @version 1.1:
-- @changelog:

local r = reaper

function ToggleSettings()
    local current = r.GetExtState("TK_TRACKNAMES", "settings_visible")
    local new_state = current ~= "1" and "1" or "0"
    r.SetExtState("TK_TRACKNAMES", "settings_visible", new_state, false)
end

ToggleSettings()
