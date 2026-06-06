-- @description TK Patchbay: Toggle Cable Shop
-- @author TouristKiller
-- @version 1.0

local r = reaper
r.SetExtState("TK_PATCHBAY_ACTIONS", "command", "toggle_cable_shop", false)
r.SetExtState("TK_PATCHBAY_ACTIONS", "serial", tostring(r.time_precise()), false)
