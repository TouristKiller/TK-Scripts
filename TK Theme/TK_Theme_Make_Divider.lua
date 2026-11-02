-- @description TK Theme: make the selected tracks dividers
-- @author TouristKiller
-- @version 0.9.6
-- Puts the selected tracks on the first layout with "Name only" turned on, at the
-- height and lock chosen under Selected tracks on the Track panel page of the
-- theme's settings. Give it a shortcut in the action list.
local r = reaper
local SCRIPT = "TK Theme Settings"

local function name_only_layout()
    local i = 0
    while true do
        local name, _, value = r.ThemeLayout_GetParameter(i)
        if not name then return nil end
        local lay = name:match("^Layout([ABC])%-tkNameOnly$")
        if lay and value ~= 0 then return lay end
        i = i + 1
    end
end

local layout = name_only_layout()
if not layout then
    r.ShowMessageBox('Turn on "Name only" for a layout first, on the Track panel page of the theme\'s settings.', "TK Theme", 0)
    return
end
local count = r.CountSelectedTracks(0)
if count == 0 then return end

local height = tonumber(r.GetExtState(SCRIPT, "track_height")) or 40
local lock = r.GetExtState(SCRIPT, "track_lock") ~= "0"
r.Undo_BeginBlock()
for i = 0, count - 1 do
    local track = r.GetSelectedTrack(0, i)
    r.GetSetMediaTrackInfo_String(track, "P_TCP_LAYOUT", layout, true)
    -- a locked height has to be released first; REAPER wants the height set before locking
    r.SetMediaTrackInfo_Value(track, "B_HEIGHTLOCK", 0)
    r.SetMediaTrackInfo_Value(track, "I_HEIGHTOVERRIDE", height)
    r.SetMediaTrackInfo_Value(track, "B_HEIGHTLOCK", lock and 1 or 0)
end
r.TrackList_AdjustWindows(false)
r.UpdateArrange()
r.Undo_EndBlock("TK Theme: make dividers", -1)
