local r = reaper
local script_path = debug.getinfo(1, "S").source:match("@?(.*[\\/])") or ""
local sep = package.config:sub(1, 1)
local root_path = script_path:match("^(.*[\\/])Action Clipboard Actions[\\/]$") or script_path
package.path = root_path .. "?.lua;" .. root_path .. "?" .. sep .. "init.lua;" .. package.path
require("core.action_clipboard_runner").toggle_lock(2)