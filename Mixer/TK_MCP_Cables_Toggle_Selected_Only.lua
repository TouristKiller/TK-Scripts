-- @description TK MCP Cables Toggle Selected Tracks Only
-- @author TouristKiller
-- @version 1.0.0
-- @about Toggles the "Selected tracks only" mode of TK MCP Cables Overlay
-- @changelog:
--   v1.0.0
--   + Initial release

local r = reaper
r.SetExtState("TK_MCP_Cables_Overlay", "toggle_selected_only", "1", false)
