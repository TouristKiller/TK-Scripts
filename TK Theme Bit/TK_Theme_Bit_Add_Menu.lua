-- TK Theme Bit - ADD button: tracks, instruments, media, markers, regions
local dir = ({reaper.get_action_context()})[2]:match("^(.*)[\\/]")
local M = dofile(dir .. "/TK_Theme_Bit_Menu.lua")
M.show({
  { 40701, "instrument", "Add Instrument Track..." },          -- Insert virtual instrument on new track
  { 40001, "track", "Add Audio Track" },                       -- Track: Insert new track
  0,
  { 40018, "media", "Add Media Files..." },                    -- Insert media files
  0,
  { 40157, "marker", "Insert Marker Here" },                   -- Markers: Insert marker at current position
  { 40174, "region", "Insert Region from Time Selection" },    -- Markers: Insert region from time selection
})
