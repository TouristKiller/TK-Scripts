-- @description TK_Play_And_Stop_MediaExplorer
-- @author TouristKiller
-- @version 1.0.0
-----------------------------------------------------------------------------
--[[    
This script is designed to replace the default Spacebar shortcut.

When you run it, it performs two steps:

It searches for the Media Explorer window and sends a specific 'Stop Preview' command 
directly to it. This ensures the preview stops immediately, even if the Media Explorer
doesn't have focus.
It triggers the standard Transport: Play/Stop action.
By assigning this script to the Spacebar, hitting Space will always silence the 
Media Explorer before starting or stopping your project playback, preventing them 
from playing on top of each other
]]--
-----------------------------------------------------------------------------
local r = reaper
local me_cmd = 1009
local me_title = "Media Explorer"

if r.APIExists("JS_Window_Find") then
    local hwnd = r.JS_Window_Find(me_title, true)
    if hwnd then r.JS_Window_OnCommand(hwnd, me_cmd) end
elseif r.APIExists("BR_Win32_FindWindowEx") then
    local hwnd = r.BR_Win32_FindWindowEx(0, 0, 0, me_title, false, true)
    if hwnd then r.BR_Win32_SendMessage(hwnd, 0x0111, me_cmd, 0) end
end

r.Main_OnCommand(40044, 0)
