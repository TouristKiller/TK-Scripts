-- TK Theme Bit - set the selected tracks' volume to -10 dB (Bitwig's default level).
-- With no track selected it says so and does nothing.

local function run()
  local n = reaper.CountSelectedTracks(0)
  if n == 0 then
    reaper.ShowMessageBox("Select one or more tracks first.", "TK Theme Bit: -10 dB", 0)
    return
  end
  local gain = 10 ^ (-10 / 20)
  reaper.Undo_BeginBlock()
  for i = 0, n - 1 do
    reaper.SetMediaTrackInfo_Value(reaper.GetSelectedTrack(0, i), "D_VOL", gain)
  end
  reaper.Undo_EndBlock("Set selected tracks to -10 dB", -1)
end

run()
