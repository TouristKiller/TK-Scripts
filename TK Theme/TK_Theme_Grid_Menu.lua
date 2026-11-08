-- @description TK Theme Dark: grid menu of the transport's grid box
-- @author TouristKiller
-- @version 0.9.18
-- Run from the grid value in the transport. A menu at the mouse to choose the grid:
-- the division, straight, triplet, dotted or swing, frame, measure, an adaptive grid
-- that follows the zoom, snap, and REAPER's own snap/grid settings.
local r = reaper
local here = debug.getinfo(1, "S").source:match("^@(.*[\\/])")
local Grid = dofile(here .. "TK_Theme_Grid.lua")

local text, run = Grid.menu()

-- gfx.showmenu needs a window of its own; an empty one at the mouse
local x, y = r.GetMousePosition()
gfx.init("TK Theme grid", 0, 0, 0, x, y)
gfx.x, gfx.y = gfx.screentoclient(x, y)
local choice = gfx.showmenu(text)
gfx.quit()

if run[choice] then
    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)
    run[choice]()
    r.PreventUIRefresh(-1)
    r.Undo_EndBlock("TK Theme: grid", -1)
    r.UpdateArrange()
    r.UpdateTimeline()
end
Grid.show(Grid.read())
Grid.start_watcher(here)
