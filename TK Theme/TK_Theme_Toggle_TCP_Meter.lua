-- @description TK Theme Dark: show/hide the TCP meters
-- @author TouristKiller
-- @version 0.9.7
-- Run from the button in the TCP. Shows or hides the meter for the layout of the track
-- under the mouse, or for the master if that's the one clicked. From a shortcut, without
-- a track under the mouse, the first selected track decides. This is the same switch
-- as on the Track panel page of the settings.
local r = reaper

local x, y = r.GetMousePosition()
local track = (r.GetTrackFromPoint(x, y)) or r.GetSelectedTrack(0, 0)
if not track then return end

local param = "tkMasterHideMeter"
if track ~= r.GetMasterTrack(0) then
    local _, layout = r.GetSetMediaTrackInfo_String(track, "P_TCP_LAYOUT", "", false)
    param = "Layout" .. (layout:match("([ABC])$") or "A") .. "-tkHideMeter"
end

local i = 0
while true do
    local name, _, value = r.ThemeLayout_GetParameter(i)
    if not name then return end
    if name == param then
        r.ThemeLayout_SetParameter(i, (value or 0) > 0 and 0 or 1, true)
        r.ThemeLayout_RefreshAll()
        return
    end
    i = i + 1
end
