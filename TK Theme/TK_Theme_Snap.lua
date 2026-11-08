-- @description TK Theme Dark: snap button of the transport's grid box
-- @author TouristKiller
-- @version 0.9.18
-- Snap on/off; the button lights while snap is on, however it gets switched.
local r = reaper
local here = debug.getinfo(1, "S").source:match("^@(.*[\\/])")
local Grid = dofile(here .. "TK_Theme_Grid.lua")

r.Main_OnCommand(Grid.SNAP, 0)
Grid.show(Grid.read())
Grid.start_watcher(here)
