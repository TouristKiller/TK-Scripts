-- @description TK Patchbay: Center view
-- @author TouristKiller
-- @version 1.0

local r = reaper
r.SetExtState("TK_PATCHBAY_ACTIONS", "command", "center_view", false)
r.SetExtState("TK_PATCHBAY_ACTIONS", "serial", tostring(r.time_precise()), false)
