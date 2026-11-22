-- TK Theme Bit - FILE button: new / open / save / render / settings
local dir = ({reaper.get_action_context()})[2]:match("^(.*)[\\/]")
local M = dofile(dir .. "/TK_Theme_Bit_Menu.lua")
M.show({
  40023, -- File: New project
  40025, -- File: Open project
  0,
  40026, -- File: Save project
  40022, -- File: Save project as
  0,
  40015, -- File: Render project to disk
  0,
  40021, -- File: Project settings
  40016, -- Options: Preferences
})
