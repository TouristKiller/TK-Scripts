-- @noindex
-- The metronome's count-in, for the transport's count-in button (TK_Theme_CountIn.lua) and
-- the watcher that lights it (TK_Theme_Metronome_Watch.lua). REAPER has no action of its own
-- to switch the count-in: SWS has them ("Toggle count-in before recording / playback"), so
-- they are looked up by their named ID, else by name in the action list. Which one the
-- button switches is the theme parameter tkCountInMode (Transport page): 0 before recording,
-- 1 before playback. Asked for by Vincent (2026-11-23).
local r = reaper
local Count = {}

Count.MODE_PARAM, Count.ON_PARAM = "tkCountInMode", "tkCountInOn"
local NAMED = { [0] = "_SWS_AWCOUNTRECTOG", [1] = "_SWS_AWCOUNTPLAYTOG" }
local TEXT = { [0] = "count-in before recording", [1] = "count-in before playback" }

-- a theme parameter's number by its name, kept while it still has that name
local params = {}
function Count.param(name)
    local i = params[name]
    if i and r.ThemeLayout_GetParameter(i) == name then return i end
    params[name] = nil
    i = 0
    while true do
        local n = r.ThemeLayout_GetParameter(i)
        if not n then return nil end
        if n == name then
            params[name] = i
            return i
        end
        i = i + 1
    end
end

function Count.mode()
    local i = Count.param(Count.MODE_PARAM)
    local _, _, value = r.ThemeLayout_GetParameter(i or -1)
    return (i and math.floor(value or 0) == 1) and 1 or 0
end

-- the toggle action for a mode, or nil when there is none (no SWS). Looked up once
local found = {}
function Count.command(mode)
    mode = mode or Count.mode()
    if found[mode] ~= nil then return found[mode] or nil end
    local cmd = r.NamedCommandLookup(NAMED[mode])
    if not cmd or cmd == 0 then
        cmd = nil
        local want = TEXT[mode]
        local section = r.SectionFromUniqueID and r.SectionFromUniqueID(0)
        for i = 0, 100000 do
            local id, name
            if r.kbd_enumerateActions and section then
                id, name = r.kbd_enumerateActions(section, i)
            elseif r.CF_EnumerateActions then
                id, name = r.CF_EnumerateActions(0, i, "")
            end
            if not id or id == 0 then break end
            name = (name or ""):lower()
            if name:find(want, 1, true) and name:find("toggle", 1, true) then
                cmd = id
                break
            end
        end
    end
    found[mode] = cmd or false
    return cmd
end

-- whether the count-in the button switches is on now
function Count.on()
    local cmd = Count.command()
    return cmd ~= nil and r.GetToggleCommandState(cmd) == 1
end

return Count
