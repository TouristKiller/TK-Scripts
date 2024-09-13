-- Script: Place marker at the start of each item on the track

-- Get the number of selected items
local item_count = reaper.CountSelectedMediaItems(0)
if item_count == 0 then
  reaper.ShowMessageBox("No items selected", "Error", 0)
  return
end

-- Start an undo block
reaper.Undo_BeginBlock()

for i = 0, item_count - 1 do
  -- Get each selected item
  local item = reaper.GetSelectedMediaItem(0, i)
  -- Get the position of the item
  local position = reaper.GetMediaItemInfo_Value(item, "D_POSITION")
  -- Create a marker at the position of the item
  reaper.AddProjectMarker(0, false, position, 0, "Marker "..(i + 1), -1)
end

-- End the undo block
reaper.Undo_EndBlock("Place marker at the start of each item on the track", -1)
