-- @description TK Theme Dark: show/hide the TCP FX and IO columns
-- @author TouristKiller
-- @version 0.9.18
-- Run from the button in the TCP. Hides the FX and IO columns for the layout of the
-- track under the mouse, or for the master if that's the one clicked, and shows again
-- the ones that were shown. From a shortcut, without a track under the mouse, the first
-- selected track decides. These are the same switches as on the Track panel page of the
-- settings.
local r = reaper
local SHOW_FX, SHOW_SENDS = 40302, 40677   -- REAPER's own options, off on a new install
local LISTS_SECTION = "TK_Theme_TCP_Lists"  -- shared with TK_Theme_Settings.lua

local function clicked_track()
    local x, y = r.GetMousePosition()
    return (r.GetTrackFromPoint(x, y)) or r.GetSelectedTrack(0, 0)
end

local function params()
    local out, i = {}, 0
    while true do
        local name, _, value = r.ThemeLayout_GetParameter(i)
        if not name then return out end
        out[name] = { idx = i, value = value or 0 }
        i = i + 1
    end
end

local track = clicked_track()
if not track then return end
local P = params()
local fx, io_, locations, key
if track == r.GetMasterTrack(0) then
    fx, io_ = "tkMasterNoFx", "tkMasterNoIo"
    locations = {}
    key = "shown-master"
else
    local _, layout = r.GetSetMediaTrackInfo_String(track, "P_TCP_LAYOUT", "", false)
    local lay = layout:match("([ABC])$") or "A"
    fx, io_ = "Layout" .. lay .. "-tkNoFxCol", "Layout" .. lay .. "-tkNoIoCol"
    locations = { [fx] = { "Layout" .. lay .. "-tcpFxLocation", 7 }, [io_] = { "Layout" .. lay .. "-tcpSendLocation", 8 } }
    key = "shown-" .. lay
end
if not P[fx] or not P[io_] then return end

local options_on = r.GetToggleCommandState(SHOW_FX) == 1 or r.GetToggleCommandState(SHOW_SENDS) == 1
local shown = options_on and (P[fx].value == 0 or P[io_].value == 0)
if shown then
    -- what's shown now comes back with the next click
    local was = {}
    if P[fx].value == 0 then was[#was + 1] = "fx" end
    if P[io_].value == 0 then was[#was + 1] = "io" end
    r.SetExtState(LISTS_SECTION, key, table.concat(was, ","), true)
    r.ThemeLayout_SetParameter(P[fx].idx, 1, true)
    r.ThemeLayout_SetParameter(P[io_].idx, 1, true)
else
    local was = r.GetExtState(LISTS_SECTION, key)
    if P[fx].value == 0 or P[io_].value == 0 then   -- on in the settings, but REAPER's options are off
        was = (P[fx].value == 0 and "fx" or "") .. "," .. (P[io_].value == 0 and "io" or "")
    end
    if not was:find("fx", 1, true) and not was:find("io", 1, true) then was = "fx,io" end
    local show = { [fx] = was:find("fx", 1, true) ~= nil, [io_] = was:find("io", 1, true) ~= nil }
    for name, on in pairs(show) do
        r.ThemeLayout_SetParameter(P[name].idx, on and 0 or 1, true)
        local location = on and locations[name]
        if location and P[location[1]] and P[location[1]].value == 0 then
            r.ThemeLayout_SetParameter(P[location[1]].idx, location[2], true)
        end
    end
    for name, cmd in pairs({ [fx] = SHOW_FX, [io_] = SHOW_SENDS }) do
        if show[name] and r.GetToggleCommandState(cmd) ~= 1 then r.Main_OnCommand(cmd, 0) end
    end
end
r.ThemeLayout_RefreshAll()
