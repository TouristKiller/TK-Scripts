-- @description TK Mixer Only
-- @author TouristKiller
-- @version 1.0
-- @changelog:
--   + Initial release - Standalone mixer without transport

local r = reaper

r.SetExtState("TK_TRANSPORT", "mixer_only_mode", "1", false)

local script_path = debug.getinfo(1, "S").source:match("@?(.*[/\\])")
dofile(script_path .. "TK_TRANSPORT.lua")
