local r = reaper
local Theme = require("core.theme")
local json = require("core.json")

local M = {
  slot_count = 5
}

local EXT_SECTION = "TK_WORKBENCH_ACTION_CLIPBOARD"
local COMMAND_KEY = "command"
local CHANGE_KEY = "changed"
local DATA_FILE = "actions_clipboard.json"

local state = {
  slots = {},
  data_path = "",
  loaded = false,
  last_change = ""
}

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

local function command_text(command_id)
  if r.CF_GetCommandText then
    local ok, text = pcall(r.CF_GetCommandText, 0, command_id)
    if ok and text and text ~= "" then return text end
  end
  return nil
end

local function shortcut_for_action(action_id)
  if not r.CountActionShortcuts or not r.GetActionShortcutDesc then return nil end
  local ok_count, count = pcall(r.CountActionShortcuts, 0, action_id)
  if not ok_count or not count or count <= 0 then return nil end
  local ok_desc, has_desc, desc = pcall(r.GetActionShortcutDesc, 0, action_id, 0)
  if ok_desc and has_desc and desc and desc ~= "" then return desc end
  return nil
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
    shortcut = command_id and shortcut_for_action(command_id) or nil
  }
end

local function ensure_slots()
  for index = 1, M.slot_count do
    state.slots[index] = normalize_slot(state.slots[index], index)
  end
end

local function save_slots()
  ensure_slots()
  return write_json(state.data_path, { slots = state.slots })
end

local function mark_changed()
  state.last_change = change_stamp()
  r.SetExtState(EXT_SECTION, CHANGE_KEY, state.last_change, false)
end

local function load_slots(app)
  state.data_path = (app and app.script_path or "") .. DATA_FILE
  state.slots = {}
  local content = read_text(state.data_path)
  if content and content ~= "" then
    local ok, decoded = pcall(json.decode, content)
    if ok and type(decoded) == "table" then
      local source = type(decoded.slots) == "table" and decoded.slots or decoded
      for index = 1, M.slot_count do
        state.slots[index] = normalize_slot(source[index], index)
      end
    end
  end
  ensure_slots()
  state.last_change = trim(r.GetExtState(EXT_SECTION, CHANGE_KEY))
  state.loaded = true
end

local function ensure_loaded(app)
  if not state.loaded or state.data_path == "" then load_slots(app) end
end

local function entry_from_action(action)
  if type(action) ~= "table" then return nil end
  local cmd = trim(action.cmd or action.command_id or action.id)
  if cmd == "" then return nil end
  local command_id = resolve_command(cmd)
  local name = trim(action.name or action.label)
  if name == "" and command_id then name = command_text(command_id) or tostring(cmd) end
  if name == "" then name = tostring(cmd) end
  return {
    cmd = tostring(cmd),
    name = name,
    label = trim(action.label),
    locked = false,
    last_used = now(),
    shortcut = command_id and shortcut_for_action(command_id) or nil
  }
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

local function unlocked_indices()
  local indices = {}
  for index = 1, M.slot_count do
    if not state.slots[index].locked then indices[#indices + 1] = index end
  end
  return indices
end

local function record_entry(app, entry, update_status)
  ensure_loaded(app)
  if not entry then return false end
  for index, slot in ipairs(state.slots) do
    if slot.locked and commands_match(slot.cmd, entry.cmd) then
      slot.last_used = now()
      save_slots()
      mark_changed()
      if update_status then app.status = "Action already locked in slot " .. tostring(index) end
      return true
    end
  end
  local indices = unlocked_indices()
  if #indices == 0 then
    if update_status then app.status = "All action clipboard slots are locked" end
    return false
  end
  local entries = { entry }
  for _, index in ipairs(indices) do
    local slot = state.slots[index]
    if slot.cmd ~= "" and not commands_match(slot.cmd, entry.cmd) then
      entries[#entries + 1] = slot
    end
  end
  for offset, index in ipairs(indices) do
    local source = entries[offset]
    if source then
      state.slots[index] = normalize_slot(source, index)
    else
      state.slots[index] = empty_slot(index, false)
    end
  end
  save_slots()
  mark_changed()
  if update_status then app.status = "Added to action clipboard: " .. entry.name end
  return true
end

local function set_slot_entry(app, entry, index, update_status)
  ensure_loaded(app)
  index = tonumber(index) or 0
  if not entry or index < 1 or index > M.slot_count then return false end
  local target_locked = state.slots[index] and state.slots[index].locked == true
  for slot_index, slot in ipairs(state.slots) do
    if slot_index ~= index and not slot.locked and commands_match(slot.cmd, entry.cmd) then
      state.slots[slot_index] = empty_slot(slot_index, false)
    end
  end
  entry.locked = target_locked
  entry.last_used = now()
  state.slots[index] = normalize_slot(entry, index)
  save_slots()
  mark_changed()
  if update_status then app.status = "Added to action clipboard slot " .. tostring(index) .. ": " .. entry.name end
  return true
end

local function copy_to_clipboard(app, value, label)
  if r.CF_SetClipboard then
    r.CF_SetClipboard(tostring(value or ""))
    app.status = "Copied " .. label
  else
    app.status = "SWS clipboard API is not available"
  end
end

function M.init(app)
  ensure_loaded(app)
end

function M.record_action(app, action, update_status)
  return record_entry(app, entry_from_action(action), update_status)
end

function M.set_slot(app, action, index, update_status)
  return set_slot_entry(app, entry_from_action(action), index, update_status)
end

function M.execute_slot(app, index)
  ensure_loaded(app)
  index = tonumber(index) or 0
  local slot = state.slots[index]
  if not slot or slot.cmd == "" then
    app.status = "Action clipboard slot " .. tostring(index) .. " is empty"
    return false
  end
  local command_id = resolve_command(slot.cmd)
  if not command_id then
    app.status = "Command not found: " .. tostring(slot.cmd)
    return false
  end
  r.Main_OnCommand(command_id, 0)
  slot.last_used = now()
  save_slots()
  mark_changed()
  app.status = "Executed slot " .. tostring(index) .. ": " .. tostring(slot.name or slot.cmd)
  if not slot.locked then M.record_action(app, slot, false) end
  return true
end

function M.toggle_lock(app, index)
  ensure_loaded(app)
  index = tonumber(index) or 0
  local slot = state.slots[index]
  if not slot then return false end
  slot.locked = not slot.locked
  save_slots()
  mark_changed()
  app.status = (slot.locked and "Locked" or "Unlocked") .. " action clipboard slot " .. tostring(index)
  return true
end

function M.clear_slot(app, index)
  ensure_loaded(app)
  index = tonumber(index) or 0
  if not state.slots[index] then return false end
  state.slots[index] = empty_slot(index, false)
  save_slots()
  mark_changed()
  app.status = "Cleared action clipboard slot " .. tostring(index)
  return true
end

function M.process_commands(app)
  local changed = trim(r.GetExtState(EXT_SECTION, CHANGE_KEY))
  if changed ~= "" and changed ~= state.last_change then load_slots(app) end
  local command = trim(r.GetExtState(EXT_SECTION, COMMAND_KEY))
  if command == "" then return end
  r.SetExtState(EXT_SECTION, COMMAND_KEY, "", false)
  local action, index = command:match("^([%w_]+):(%d+)$")
  if action == "run" then
    M.execute_slot(app, tonumber(index))
  elseif action == "toggle_lock" then
    M.toggle_lock(app, tonumber(index))
  end
end

function M.panel_height(ctx)
  local button_h = r.ImGui_GetFrameHeight(ctx)
  local line_h = r.ImGui_GetTextLineHeight(ctx)
  return line_h + (button_h + 6) * M.slot_count + 36
end

function M.draw_panel(app)
  ensure_loaded(app)
  local ctx = app.ctx
  local avail_w = r.ImGui_GetContentRegionAvail(ctx)
  local button_h = r.ImGui_GetFrameHeight(ctx)
  r.ImGui_TextColored(ctx, Theme.colors.accent, "Action Clipboard")
  r.ImGui_Separator(ctx)
  for index = 1, M.slot_count do
    local slot = state.slots[index]
    r.ImGui_PushID(ctx, "action_clipboard_slot_" .. tostring(index))
    if r.ImGui_Button(ctx, tostring(index), button_h, button_h) then M.execute_slot(app, index) end
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Run slot " .. tostring(index)) end
    r.ImGui_SameLine(ctx)
    local lock_label = slot.locked and "L" or "U"
    if slot.locked then
      r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), Theme.colors.warning)
      r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), Theme.colors.warning)
      r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), Theme.colors.warning)
      r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), Theme.colors.badge_text)
    elseif slot.cmd == "" then
      r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), Theme.colors.frame_bg)
      r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), Theme.colors.frame_hover)
      r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), Theme.colors.frame_hover)
      r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), Theme.colors.text_dim)
    else
      r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), Theme.colors.frame_bg)
      r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), Theme.colors.header_hover)
      r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), Theme.colors.header)
      r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), Theme.colors.text)
    end
    if r.ImGui_Button(ctx, lock_label, button_h, button_h) then M.toggle_lock(app, index) end
    r.ImGui_PopStyleColor(ctx, 4)
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, slot.locked and "Unlock slot" or "Lock slot") end
    r.ImGui_SameLine(ctx)
    local label = slot.cmd ~= "" and tostring(slot.name or slot.cmd) or "Empty"
    local text_color = slot.locked and Theme.colors.warning or (slot.cmd ~= "" and Theme.colors.text or Theme.colors.text_dim)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), text_color)
    r.ImGui_Selectable(ctx, label .. "##slot_select", false, 0, math.max(80, avail_w - (button_h * 2) - 16), button_h)
    r.ImGui_PopStyleColor(ctx)
    if r.ImGui_IsItemHovered(ctx) and slot.cmd ~= "" then
      local details = tostring(slot.name or slot.cmd) .. "\nCommand: " .. tostring(slot.cmd)
      if slot.shortcut then details = details .. "\nShortcut: " .. tostring(slot.shortcut) end
      r.ImGui_SetTooltip(ctx, details)
    end
    if r.ImGui_BeginPopupContextItem(ctx, "##slot_context") then
      if r.ImGui_MenuItem(ctx, "Run Slot") then M.execute_slot(app, index) end
      if r.ImGui_MenuItem(ctx, slot.locked and "Unlock Slot" or "Lock Slot") then M.toggle_lock(app, index) end
      if r.ImGui_MenuItem(ctx, "Clear Slot") then M.clear_slot(app, index) end
      if slot.cmd ~= "" then
        if r.ImGui_MenuItem(ctx, "Copy Command ID") then copy_to_clipboard(app, slot.cmd, "command ID") end
        if r.ImGui_MenuItem(ctx, "Copy Action Text") then copy_to_clipboard(app, slot.name, "action text") end
      end
      r.ImGui_EndPopup(ctx)
    end
    r.ImGui_PopID(ctx)
  end
  r.ImGui_Separator(ctx)
end

function M.command_script(action, index)
  return string.format('local r = reaper\nr.SetExtState("%s", "%s", "%s:%d", false)\n', EXT_SECTION, COMMAND_KEY, action, index)
end

return M