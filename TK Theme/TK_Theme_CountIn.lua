-- @description TK Theme Dark: the transport's count-in button
-- @author TouristKiller
-- @version 0.9.99.2
-- Count-in on/off (before recording, or before playback: Transport page), then keeps
-- watching it, so the button lights up however it gets switched. Needs SWS.
local r = reaper
local here = debug.getinfo(1, "S").source:match("^@(.*[\\/])")
local Count = dofile(here .. "TK_Theme_Count.lua")

local cmd = Count.command()
if not cmd then
    r.ShowMessageBox("The count-in button needs the SWS extension: REAPER itself has no action to switch the count-in.\n\n"
        .. "Install SWS (sws-extension.org, or with ReaPack), restart REAPER, and the button works.", "TK Theme", 0)
    return
end
r.Main_OnCommand(cmd, 0)

dofile(here .. "TK_Theme_Metronome_Watch.lua")
