local r = reaper
local json = require("core.json")

local M = {}

local SLOT_COUNT = 5
local EXT_SECTION = "TK_WORKBENCH_ACTION_CLIPBOARD"
local CHANGE_KEY = "changed"
local DATA_FILE = "actions_clipboard.json"

local script_path = debug.getinfo(1, "S").source:match("@?(.*[\\/])") or ""
local root_path = script_path:match("^(.*[\\/])core[\\/]$") or script_path
local data_path = root_path .. DATA_FILE

local function now()
  return os.time()
end

local function change_stamp()
  return tostring(r.time_precise and r.time_precise() or os.time())
end

local function trim(value)
  return tostring(value or ""):match("^%s*(.-)%s*$") or ""
end

local function read_text(path)
  local file = io.open(path, "rb")
  if not file then return nil end
  local content = file:read("*all")
  file:close()
  return content
end

local function write_json(path, value)
  local ok, encoded = pcall(json.encode, value)
  if not ok or not encoded then return false end
  local file = io.open(path, "w")
  if not file then return false end
  file:write(encoded)
  file:close()
  return true
end

local function resolve_command(cmd)
  cmd = trim(cmd)
  if cmd == "" then return nil end
  if cmd:sub(1, 1) == "_" then
    local command_id = r.NamedCommandLookup(cmd)
    if command_id and command_id ~= 0 then return command_id end
    return nil
  end
  local command_id = tonumber(cmd)
  if command_id and command_id ~= 0 then return command_id end
  return nil
end

local function command_text(command_id)
  if r.CF_GetCommandText then
    local ok, text = pcall(r.CF_GetCommandText, 0, command_id)
    if ok and text and text ~= "" then return text end
  end
  return nil
end

local function empty_slot(index, locked)
  return {
    index = index,
    cmd = "",
    name = "",
    label = "",
    locked = locked == true,
    last_used = 0,
    shortcut = nil
  }
end

local function normalize_slot(slot, index)
  if type(slot) ~= "table" then return empty_slot(index, false) end
  local cmd = trim(slot.cmd or slot.command_id or slot.id)
  local command_id = resolve_command(cmd)
  local name = trim(slot.name or slot.label)
  if name == "" and command_id then name = command_text(command_id) or tostring(cmd) end
  return {
    index = index,
    cmd = cmd,
    name = name,
    label = trim(slot.label),
    locked = slot.locked == true,
    last_used = tonumber(slot.last_used) or 0,
    shortcut = slot.shortcut
  }
end

local function load_slots()
  local slots = {}
  local content = read_text(data_path)
  if content and content ~= "" then
    local ok, decoded = pcall(json.decode, content)
    if ok and type(decoded) == "table" then
      local source = type(decoded.slots) == "table" and decoded.slots or decoded
      for index = 1, SLOT_COUNT do slots[index] = normalize_slot(source[index], index) end
    end
  end
  for index = 1, SLOT_COUNT do slots[index] = normalize_slot(slots[index], index) end
  return slots
end

local function save_slots(slots)
  for index = 1, SLOT_COUNT do slots[index] = normalize_slot(slots[index], index) end
  return write_json(data_path, { slots = slots })
end

local function mark_changed()
  r.SetExtState(EXT_SECTION, CHANGE_KEY, change_stamp(), false)
end

local function commands_match(left, right)
  left = trim(left)
  right = trim(right)
  if left == "" or right == "" then return false end
  if left == right then return true end
  local left_id = resolve_command(left)
  local right_id = resolve_command(right)
  return left_id and right_id and left_id == right_id
end

local function unlocked_indices(slots)
  local indices = {}
  for index = 1, SLOT_COUNT do
    if not slots[index].locked then indices[#indices + 1] = index end
  end
  return indices
end

local function record_slot(slots, entry)
  local indices = unlocked_indices(slots)
  if #indices == 0 then return false end
  entry.last_used = now()
  local entries = { entry }
  for _, index in ipairs(indices) do
    local slot = slots[index]
    if slot.cmd ~= "" and not commands_match(slot.cmd, entry.cmd) then entries[#entries + 1] = slot end
  end
  for offset, index in ipairs(indices) do
    local source = entries[offset]
    slots[index] = source and normalize_slot(source, index) or empty_slot(index, false)
  end
  return true
end

function M.run(index)
  index = tonumber(index) or 0
  local slots = load_slots()
  local slot = slots[index]
  if not slot or slot.cmd == "" then return false end
  local command_id = resolve_command(slot.cmd)
  if not command_id then return false end
  r.Main_OnCommand(command_id, 0)
  slot.last_used = now()
  if not slot.locked then record_slot(slots, slot) end
  save_slots(slots)
  mark_changed()
  return true
end

function M.toggle_lock(index)
  index = tonumber(index) or 0
  local slots = load_slots()
  if not slots[index] then return false end
  slots[index].locked = not slots[index].locked
  save_slots(slots)
  mark_changed()
  return true
end

return M