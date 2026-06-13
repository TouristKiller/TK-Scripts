-- @description TK_Trackname_Toggle_Child
-- @author TouristKiller
-- @version 1.0
-- @changelog:
--   v1.0: Initial release
-- @about Toggle visibility of Child track names on/off, independent of Parent and Normal tracks

local r = reaper
local script_path = debug.getinfo(1,'S').source:match[[^@?(.*[\/])[^\/]-$]]
local json = dofile(script_path .. "json.lua")

local section = "TK_TRACKNAMES"

local function SetButtonState(state)
    local _, _, sec, cmd = r.get_action_context()
    r.SetToggleCommandState(sec, cmd, state)
    r.RefreshToolbar2(sec, cmd)
end

local settings_json = r.GetExtState(section, "settings")
if settings_json == "" then return end

local settings = json.decode(settings_json)

settings.show_child_tracks = not settings.show_child_tracks

r.SetExtState(section, "settings", json.encode(settings), true)
r.SetExtState(section, "reload_settings", "1", false)

SetButtonState(settings.show_child_tracks and 1 or 0)
r.UpdateArrange()
