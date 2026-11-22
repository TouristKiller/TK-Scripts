-- TK Theme Bit - EDIT button: undo, clipboard, select, split, duplicate
local dir = ({reaper.get_action_context()})[2]:match("^(.*)[\\/]")
local M = dofile(dir .. "/TK_Theme_Bit_Menu.lua")
M.show({
  40029, -- Edit: Undo
  40030, -- Edit: Redo
  0,
  40059, -- Edit: Cut items/tracks/envelope points
  40057, -- Edit: Copy items/tracks/envelope points
  40058, -- Item: Paste items/tracks
  40697, -- Remove items/tracks/envelope points
  0,
  40182, -- Item: Select all items
  40296, -- Track: Select all tracks
  0,
  40757, -- Item: Split items at edit cursor
  41295, -- Item: Duplicate items
})
