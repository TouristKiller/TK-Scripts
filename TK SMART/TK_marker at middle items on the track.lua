-- Script: Place marker in the middle between each item on the track

-- Get the number of selected items
local item_count = reaper.CountSelectedMediaItems(0)
if item_count < 2 then
  reaper.ShowMessageBox("Select at least two items", "Error", 0)
  return
end

-- Start an undo block
reaper.Undo_BeginBlock()

for i = 0, item_count - 2 do
  -- Get each selected item
  local item1 = reaper.GetSelectedMediaItem(0, i)
  local item2 = reaper.GetSelectedMediaItem(0, i + 1)
  -- Get the end position of the first item
  local position1 = reaper.GetMediaItemInfo_Value(item1, "D_POSITION") + reaper.GetMediaItemInfo_Value(item1, "D_LENGTH")
  -- Get the start position of the second item
  local position2 = reaper.GetMediaItemInfo_Value(item2, "D_POSITION")
  -- Calculate the middle position
  local middle_position = (position1 + position2) / 2
  -- Create a marker at the middle position
  reaper.AddProjectMarker(0, false, middle_position, 0, "Marker "..(i + 1), -1)
end

-- End the undo block
reaper.Undo_EndBlock("Place marker in the middle between each item on the track", -1)
