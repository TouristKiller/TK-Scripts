-- @description TK Patchbay: Focus selected subtree
-- @author TouristKiller
-- @version 1.0

local r = reaper
r.SetExtState("TK_PATCHBAY_ACTIONS", "command", "focus_selected_subtree", false)
r.SetExtState("TK_PATCHBAY_ACTIONS", "serial", tostring(r.time_precise()), false)
