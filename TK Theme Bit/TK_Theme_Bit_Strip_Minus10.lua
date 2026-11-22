-- TK Theme Bit - the "-10" key in a mixer strip: sets THAT strip's track to -10 dB (the
-- track under the mouse). If that track is part of a selection, the whole selection goes.
-- (TK_Theme_Bit_Tracks_Minus10.lua is the one for a shortcut: it works on the selection.)

local x, y = reaper.GetMousePosition()
local track = reaper.GetTrackFromPoint(x, y)
if not track then
  dofile(({reaper.get_action_context()})[2]:match("^(.*)[\\/]") .. "/TK_Theme_Bit_Tracks_Minus10.lua")
  return
end

local gain = 10 ^ (-10 / 20)
reaper.Undo_BeginBlock()
if reaper.IsTrackSelected(track) then
  for i = 0, reaper.CountSelectedTracks(0) - 1 do
    reaper.SetMediaTrackInfo_Value(reaper.GetSelectedTrack(0, i), "D_VOL", gain)
  end
else
  reaper.SetMediaTrackInfo_Value(track, "D_VOL", gain)
end
reaper.Undo_EndBlock("Set track volume to -10 dB", -1)
