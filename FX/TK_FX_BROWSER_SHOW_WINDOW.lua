-- @description TK FX BROWSER - Show Window
-- @author TouristKiller  
-- @version 1.0.0
-- @about Force show TK FX BROWSER window (in case it's hidden)

local r = reaper

r.SetExtState("TK_FX_BROWSER", "visibility", "visible", true)
r.ShowConsoleMsg("TK FX BROWSER: Window forced to visible state\n")

r.ShowMessageBox("TK FX BROWSER window has been set to visible.\n\nIf you don't see it, the script might not be running.\nCheck the Actions list for 'TK FX BROWSER' and run it.", "Window Visibility Set", 0)
