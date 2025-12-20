-- @description TK_Trackname_Overlay_Toggle
-- @author TouristKiller
-- @version 1.2
-- @changelog:
--   v1.2: Simplified - just toggle ExtState
-- @about Toggle the overlay visibility on/off (for drag & drop from external sources)

local r = reaper

local current_state = r.GetExtState("TK_TRACKNAMES", "overlay_visible")

if current_state == "0" then
    r.SetExtState("TK_TRACKNAMES", "overlay_visible", "1", false)
else
    r.SetExtState("TK_TRACKNAMES", "overlay_visible", "0", false)
end
