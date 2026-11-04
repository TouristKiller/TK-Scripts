-- @description TK Theme Dark: show/hide the TCP FX and IO columns
-- @author TouristKiller
-- @version 0.9.9
-- Run from the button in the TCP. Shows or hides both columns for the layout of the
-- track under the mouse, or for the master if that's the one clicked. From a shortcut,
-- without a track under the mouse, the first selected track decides. These are the
-- same switches as on the Track panel page of the settings.
local r = reaper
local SHOW_FX, SHOW_SENDS = 40302, 40677   -- REAPER's own options, off on a new install

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
local fx, io_, locations
if track == r.GetMasterTrack(0) then
    fx, io_ = "tkMasterNoFx", "tkMasterNoIo"
    locations = {}
else
    local _, layout = r.GetSetMediaTrackInfo_String(track, "P_TCP_LAYOUT", "", false)
    local lay = layout:match("([ABC])$") or "A"
    fx, io_ = "Layout" .. lay .. "-tkNoFxCol", "Layout" .. lay .. "-tkNoIoCol"
    locations = { ["Layout" .. lay .. "-tcpFxLocation"] = 7, ["Layout" .. lay .. "-tcpSendLocation"] = 8 }
end
if not P[fx] or not P[io_] then return end

local options_on = r.GetToggleCommandState(SHOW_FX) == 1 or r.GetToggleCommandState(SHOW_SENDS) == 1
local shown = options_on and (P[fx].value == 0 or P[io_].value == 0)
local value = shown and 1 or 0
r.ThemeLayout_SetParameter(P[fx].idx, value, true)
r.ThemeLayout_SetParameter(P[io_].idx, value, true)
if not shown then
    for name, position in pairs(locations) do
        if P[name] and P[name].value == 0 then r.ThemeLayout_SetParameter(P[name].idx, position, true) end
    end
    for _, cmd in ipairs({ SHOW_FX, SHOW_SENDS }) do
        if r.GetToggleCommandState(cmd) ~= 1 then r.Main_OnCommand(cmd, 0) end
    end
end
r.ThemeLayout_RefreshAll()
