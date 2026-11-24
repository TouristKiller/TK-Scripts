-- TK Theme Bit - FILE button: new / open / save / render / settings
local dir = ({reaper.get_action_context()})[2]:match("^(.*)[\\/]")
local M = dofile(dir .. "/TK_Theme_Bit_Menu.lua")
M.show({
  { 40023, "new", "New Project" },                  -- File: New project
  { 40025, "open", "Open Project..." },             -- File: Open project
  0,
  { 40026, "save", "Save" },                        -- File: Save project
  { 40022, "saveas", "Save As..." },                -- File: Save project as
  0,
  { 40015, "render", "Render..." },                 -- File: Render project to disk
  0,
  { 40021, "settings", "Project Settings..." },     -- File: Project settings
  { 40016, "prefs", "Preferences..." },             -- Options: Preferences
})
