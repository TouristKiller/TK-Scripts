-- @description TK MCP Cables Overlay - Toggle Settings Window
-- @author TouristKiller
-- @version 1.1
-- @changelog:
--   + Toggle state reflected on toolbar button

local r = reaper
local _, _, sectionID, cmdID = r.get_action_context()
if sectionID and sectionID ~= -1 then
 r.SetExtState("TK_MCP_Cables_Overlay", "toggle_cmd", sectionID .. ":" .. cmdID, true)
end
r.SetExtState("TK_MCP_Cables_Overlay", "toggle_settings", "1", false)
