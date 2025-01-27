-- Setup 1.0
local script_name = "TK_time selection loop color.lua"
local resource_path = reaper.GetResourcePath()
local script_path = resource_path .. "/Scripts/TK-Scripts/Tools/" .. script_name

reaper.SetExtState("TK_time selection loop color_setup", "CALL_SETUP", "1", false)
reaper.RefreshToolbar2(0, -1)
