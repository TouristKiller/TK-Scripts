-- @description TK Notes - Open in Track Mode
-- @author TouristKiller
-- @version 1.0
-- @provides [main] .
-- @about Opens TK Notes directly in Track mode

local r = reaper

r.SetExtState("TK_NOTES", "startup_mode", "track", false)

local script_path = debug.getinfo(1, "S").source:match("@(.+[\\/])")
dofile(script_path .. "TK_NOTES.lua")
