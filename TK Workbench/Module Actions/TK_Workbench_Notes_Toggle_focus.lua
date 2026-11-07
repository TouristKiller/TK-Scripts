-- @description TK Workbench: Notes - Toggle focus between note and arrange view
-- @author TouristKiller
-- @version 1.0
-- @about
--   Moves the keyboard between the Notes module and REAPER's arrange view:
--   type in a note, press the shortcut, use play/stop, press it again to carry
--   on typing where the cursor was. Assign your own shortcut in the Action
--   list; Notes reads it too, so it also works while you are typing.
--   Opens Workbench and the Notes view when they are not showing.

local script_path = debug.getinfo(1, "S").source:match("@?(.*[\\/])") or ""
local sep = package.config:sub(1, 1)
local root_path = script_path:match("^(.*[\\/])Module Actions[\\/]$") or script_path
package.path = root_path .. "?.lua;" .. root_path .. "?" .. sep .. "init.lua;" .. package.path
require("core.workbench_module_action_runner").run("notes", "toggle_focus")
