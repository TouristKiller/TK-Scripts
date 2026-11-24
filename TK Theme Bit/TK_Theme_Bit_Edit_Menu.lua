-- TK Theme Bit - EDIT button: undo, clipboard, select, split, duplicate
local dir = ({reaper.get_action_context()})[2]:match("^(.*)[\\/]")
local M = dofile(dir .. "/TK_Theme_Bit_Menu.lua")
M.show({
  { 40029, "undo", "Undo" },                        -- Edit: Undo
  { 40030, "redo", "Redo" },                        -- Edit: Redo
  0,
  { 40059, "cut", "Cut" },                          -- Edit: Cut items/tracks/envelope points
  { 40057, "copy", "Copy" },                        -- Edit: Copy items/tracks/envelope points
  { 40058, "paste", "Paste" },                      -- Item: Paste items/tracks
  { 40697, "delete", "Delete" },                    -- Remove items/tracks/envelope points
  0,
  { 40182, "selclips", "Select All Clips" },        -- Item: Select all items
  { 40296, "seltracks", "Select All Tracks" },      -- Track: Select all tracks
  0,
  { 40757, "split", "Split at Edit Cursor" },       -- Item: Split items at edit cursor
  { 41295, "duplicate", "Duplicate" },              -- Item: Duplicate items
})
