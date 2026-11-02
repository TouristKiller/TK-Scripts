-- @description TK Theme: show/hide REAPER's menu bar
-- @author TouristKiller
-- @version 0.9.0
-- Windows only, and needs TK Native Helper (ReaPack). Give it a shortcut in the
-- action list; the same switch is on the General page of the theme's settings.
local r = reaper

if not r.TK_SetMainMenuVisible then
    r.ShowMessageBox("Hiding the menu bar needs TK Native Helper, version 1.1.0 or newer (install it with ReaPack), on Windows.",
        "TK Theme", 0)
    return
end
r.TK_SetMainMenuVisible(not r.TK_IsMainMenuVisible())
r.defer(function() end)     -- no undo point for this
