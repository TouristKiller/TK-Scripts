-- @description TK Theme Dark: keep the transport's metronome button and grid box in step
-- @author TouristKiller
-- @version 0.9.18
-- A theme can't read whether the metronome or snap is on, or what the grid is, so
-- this background script passes them on as theme parameters: tkTransMetroOn, and
-- tkGridV, tkGridA and tkSnapOn for the grid box. It also keeps the grid box's
-- adaptive grid in step with the zoom. Started by the metronome button, the grid
-- box and the snap button; run it from __startup.lua to have them right from the start.
local r = reaper
local TOGGLE, PARAM = 40364, "tkTransMetroOn"
local here = debug.getinfo(1, "S").source:match("^@(.*[\\/])")
local Grid = dofile(here .. "TK_Theme_Grid.lua")

-- running this again replaces the running copy, without REAPER's dialog
if r.set_action_options then r.set_action_options(3) end

local function find_param()
    local i = 0
    while true do
        local name = r.ThemeLayout_GetParameter(i)
        if not name then return nil end
        if name == PARAM then return i end
        i = i + 1
    end
end

local idx, shown
local next_check, next_beat = 0, 0

local function loop()
    local now = r.time_precise()
    -- parameter numbers change with the theme: look it up again now and then
    if now >= next_check then
        next_check = now + 2
        if not idx or r.ThemeLayout_GetParameter(idx) ~= PARAM then
            idx = find_param()
            shown = nil
            Grid.forget()
        end
    end
    if now >= next_beat then
        next_beat = now + 1
        Grid.beat()
    end
    if idx then
        local on = r.GetToggleCommandState(TOGGLE) == 1 and 1 or 0
        if on ~= shown then
            shown = on
            r.ThemeLayout_SetParameter(idx, on, false)
            r.ThemeLayout_RefreshAll()
        end
    end
    Grid.adapt()
    Grid.show(Grid.read())
    r.defer(loop)
end

loop()
