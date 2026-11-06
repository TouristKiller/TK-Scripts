-- @description TK Theme Dark: keep the transport's metronome button in step
-- @author TouristKiller
-- @version 0.9.12
-- A theme can't read whether the metronome is on, so this background script
-- passes it on as the theme parameter tkTransMetroOn. Started by the metronome
-- button; run it from __startup.lua to have the button right from the start.
local r = reaper
local TOGGLE, PARAM = 40364, "tkTransMetroOn"

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
local next_check = 0

local function loop()
    local now = r.time_precise()
    -- parameter numbers change with the theme: look it up again now and then
    if now >= next_check then
        next_check = now + 2
        if not idx or r.ThemeLayout_GetParameter(idx) ~= PARAM then
            idx = find_param()
            shown = nil
        end
    end
    if idx then
        local on = r.GetToggleCommandState(TOGGLE) == 1 and 1 or 0
        if on ~= shown then
            shown = on
            r.ThemeLayout_SetParameter(idx, on, false)
            r.ThemeLayout_RefreshAll()
        end
    end
    r.defer(loop)
end

loop()
