-- @description TK Patchbay: Show all tracks
-- @author TouristKiller
-- @version 1.0

local r = reaper
r.SetExtState("TK_PATCHBAY_ACTIONS", "command", "show_all_tracks", false)
r.SetExtState("TK_PATCHBAY_ACTIONS", "serial", tostring(r.time_precise()), false)
