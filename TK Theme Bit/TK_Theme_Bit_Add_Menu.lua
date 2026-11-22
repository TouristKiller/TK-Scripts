-- TK Theme Bit - ADD button: tracks, instruments, media, markers, regions
local dir = ({reaper.get_action_context()})[2]:match("^(.*)[\\/]")
local M = dofile(dir .. "/TK_Theme_Bit_Menu.lua")
M.show({
  40001, -- Track: Insert new track
  40701, -- Insert virtual instrument on new track
  0,
  40018, -- Insert media files
  0,
  40157, -- Markers: Insert marker at current position
  40174, -- Markers: Insert region from time selection
})
