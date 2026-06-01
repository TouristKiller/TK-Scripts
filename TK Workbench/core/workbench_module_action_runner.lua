local r = reaper

local M = {}

local EXT_SECTION = "TK_WORKBENCH_MODULE_ACTIONS"
local COMMAND_KEY = "command"
local RUNNING_KEY = "running"
local HEARTBEAT_KEY = "heartbeat"
local WORKBENCH_FILE = "TK_Workbench.lua"

local script_path = debug.getinfo(1, "S").source:match("@?(.*[\\/])") or ""
local root_path = script_path:match("^(.*[\\/])core[\\/]$") or script_path

local function now()
  return r.time_precise and r.time_precise() or os.clock()
end

local function workbench_alive()
  if r.GetExtState(EXT_SECTION, RUNNING_KEY) ~= "true" then return false end
  local heartbeat = tonumber(r.GetExtState(EXT_SECTION, HEARTBEAT_KEY)) or 0
  return now() - heartbeat < 2.5
end

function M.open(module_id)
  if not module_id or module_id == "" then return false end
  r.SetExtState(EXT_SECTION, COMMAND_KEY, "open:" .. tostring(module_id), false)
  if workbench_alive() then return true end
  local path = root_path .. WORKBENCH_FILE
  local file = io.open(path, "rb")
  if not file then return false end
  file:close()
  dofile(path)
  return true
end

return M