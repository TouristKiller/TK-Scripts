-- @description TK Theme Dark: the transport's metronome button
-- @author TouristKiller
-- @version 0.9.12
-- Metronome on/off, then keeps watching the metronome, so the button lights up
-- however it gets switched.
local r = reaper
local here = debug.getinfo(1, "S").source:match("^@(.*[\\/])")

r.Main_OnCommand(40364, 0)

dofile(here .. "TK_Theme_Metronome_Watch.lua")
