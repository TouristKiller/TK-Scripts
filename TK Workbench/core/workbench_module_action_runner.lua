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

local function normalize(path)
  return tostring(path or ""):gsub("\\", "/"):gsub("/+", "/"):lower()
end

-- The action id REAPER gave TK_Workbench.lua, read from reaper-kb.ini. A
-- script path in there is relative to the Scripts folder, or absolute when the
-- script lives elsewhere; both are compared against the real file, so
-- TK_Workbench_2.lua - or a copy in another folder - is never picked.
local function main_script_command()
  if not (r.GetResourcePath and r.NamedCommandLookup and r.Main_OnCommand) then return nil end
  local resource = r.GetResourcePath()
  local file = io.open(resource .. "/reaper-kb.ini", "r")
  if not file then return nil end
  local wanted = normalize(root_path .. WORKBENCH_FILE)
  local scripts = normalize(resource .. "/Scripts/")
  local found = nil
  for line in file:lines() do
    if line:sub(1, 4) == "SCR " then
      local section, id, path = line:match('^SCR%s+%d+%s+(%d+)%s+(%S+)%s+"[^"]*"%s+"?([^"]+)"?')
      if section == "0" and id and path then
        local full = normalize(path)
        if not full:match("^%a:/") and full:sub(1, 1) ~= "/" then full = scripts .. full end
        if full == wanted then found = id; break end
      end
    end
  end
  file:close()
  if not found then return nil end
  local command = r.NamedCommandLookup("_" .. found)
  if command and command ~= 0 then return command end
  return nil
end

-- Starts Workbench as the script "TK_Workbench.lua", whatever asked for it.
-- It used to be started with dofile, which made Workbench part of the action
-- script that started it: running TK_Workbench.lua afterwards opened a second
-- Workbench on the same settings, pressing the same action again ran into
-- REAPER's "already running" question - and with "terminate" remembered, that
-- closed Workbench - and the toolbar state belonged to the action. dofile is
-- left only for a Workbench that is not in the action list at all.
local function start_workbench()
  local command = main_script_command()
  if command then
    r.Main_OnCommand(command, 0)
    return true
  end
  local path = root_path .. WORKBENCH_FILE
  local file = io.open(path, "rb")
  if not file then return false end
  file:close()
  dofile(path)
  return true
end

-- The command is left in ExtState first: a running Workbench picks it up on its
-- next frame, a starting one on its first.
local function send(command)
  r.SetExtState(EXT_SECTION, COMMAND_KEY, command, false)
  if workbench_alive() then return true end
  return start_workbench()
end

-- Hands a module something to do rather than merely bringing it to the front,
-- which is what lets an action be bound to a key or a control surface. The
-- module decides what the verb means; this only carries it.
function M.run(module_id, command)
  if not module_id or module_id == "" or not command or command == "" then return false end
  return send("run:" .. tostring(module_id) .. ":" .. tostring(command))
end

-- Puts back a saved split layout. Workbench is started if it is not running,
-- like for the open actions, and picks the command up on its first frame.
function M.workspace(index)
  index = tonumber(index)
  if not index then return false end
  return send("workspace:" .. tostring(math.floor(index)))
end

function M.open(module_id)
  if not module_id or module_id == "" then return false end
  return send("open:" .. tostring(module_id))
end

return M
