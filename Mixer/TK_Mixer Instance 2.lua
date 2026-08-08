-- @description TK Mixer - Instance 2
-- @author TouristKiller
-- @version 1.0

local r = reaper
local script_path = debug.getinfo(1, "S").source:match("@?(.*[/\\])")
_G.TK_MIXER_INSTANCE_ID = "2"
_G.TK_MIXER_INSTANCE_NAME = "Instance 2"
local ok, err = pcall(dofile, script_path .. "TK_Mixer.lua")
if not ok then
 r.ShowMessageBox(tostring(err), "TK Mixer - Instance 2", 0)
end