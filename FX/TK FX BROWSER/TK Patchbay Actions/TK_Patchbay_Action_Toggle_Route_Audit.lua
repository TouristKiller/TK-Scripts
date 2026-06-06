-- @description TK Patchbay: Toggle Route Audit
-- @author TouristKiller
-- @version 1.0

local r = reaper
r.SetExtState("TK_PATCHBAY_ACTIONS", "command", "toggle_route_audit", false)
r.SetExtState("TK_PATCHBAY_ACTIONS", "serial", tostring(r.time_precise()), false)
