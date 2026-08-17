-- @description TK Workbench: Idea Vault - Capture selected track
-- @author TouristKiller
-- @version 1.0
-- @about
--   Opens the Idea Vault capture dialog inside TK Workbench. For a capture that
--   does not need Workbench at all, bind TK_Idea_Capture.lua instead.

local script_path = debug.getinfo(1, "S").source:match("@?(.*[\\/])") or ""
local sep = package.config:sub(1, 1)
local root_path = script_path:match("^(.*[\\/])Module Actions[\\/]$") or script_path
package.path = root_path .. "?.lua;" .. root_path .. "?" .. sep .. "init.lua;" .. package.path
require("core.workbench_module_action_runner").run("idea_vault", "capture")
