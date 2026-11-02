-- @description TK Theme Dark: show/hide the TCP meters
-- @author TouristKiller
-- @version 0.9.4
-- Run from the button in the TCP (TK_Theme_Rebuild.lua registers this script
-- and the generator wires the button to it). Flips the theme's own
-- tkTcpMeterHide parameter; hidden, the meter section is zero wide and the
-- FX/IO window takes the room.
local r = reaper

local i = 0
while true do
    local name, _, value = r.ThemeLayout_GetParameter(i)
    if not name then return end
    if name == "tkTcpMeterHide" then
        r.ThemeLayout_SetParameter(i, (value or 0) > 0 and 0 or 1, true)
        r.ThemeLayout_RefreshAll()
        return
    end
    i = i + 1
end
