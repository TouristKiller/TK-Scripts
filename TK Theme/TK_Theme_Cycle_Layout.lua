-- @description TK Theme: next track layout (A, B, C)
-- @author TouristKiller
-- @version 0.9.31
-- Run from the layout button in the track panel or the layout key in the mixer. Moves the
-- track under the mouse to the next layout: A, B, C and round to A. When that track is
-- selected, all selected tracks go along to the same layout. The track panel's button
-- changes the track panel layout, the mixer's key the mixer layout. From a shortcut,
-- without a track under the mouse, the first selected track decides (track panel).
local r = reaper

local x, y = r.GetMousePosition()
local track, info = r.GetThingFromPoint(x, y)
if not track then track = r.GetSelectedTrack(0, 0) end
if not track or track == r.GetMasterTrack(0) then return end

local key = (info or ""):match("^mcp") and "P_MCP_LAYOUT" or "P_TCP_LAYOUT"
local _, cur = r.GetSetMediaTrackInfo_String(track, key, "", false)
-- keep a scale or a "Dot" around the letter; a track on the default layout counts as A
local pre, letter, post = cur:match("^(.-)([ABC])(.*)$")
if not letter then pre, letter, post = "", "A", "" end
local nxt = pre .. ({ A = "B", B = "C", C = "A" })[letter] .. post

local tracks = { track }
if r.IsTrackSelected(track) then
    tracks = {}
    for i = 0, r.CountSelectedTracks(0) - 1 do tracks[#tracks + 1] = r.GetSelectedTrack(0, i) end
end

r.Undo_BeginBlock()
r.PreventUIRefresh(1)
for _, tr in ipairs(tracks) do
    if tr ~= r.GetMasterTrack(0) then r.GetSetMediaTrackInfo_String(tr, key, nxt, true) end
end
r.PreventUIRefresh(-1)
r.TrackList_AdjustWindows(false)
r.Undo_EndBlock("Track layout " .. nxt, -1)
