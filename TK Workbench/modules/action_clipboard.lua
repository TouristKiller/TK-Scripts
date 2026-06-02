local r = reaper
local Theme = require("core.theme")
local json = require("core.json")

local M = {
  id = "action_clipboard",
  title = "Action Clipboard",
  icon = "CLP",
  version = "0.1.0",
  slot_count = 5
}

local DEFAULT_SLOT_COUNT = 5
local MIN_SLOT_COUNT = 1
local MAX_SLOT_COUNT = 10

local EXT_SECTION = "TK_WORKBENCH_ACTION_CLIPBOARD"
local COMMAND_KEY = "command"
local CHANGE_KEY = "changed"
local CAPTURE_EXT_SECTION = "TK_WORKBENCH_ACTION_CAPTURE"
local CAPTURE_SEQ_KEY = "seq"
local CAPTURE_EVENTS_KEY = "events"
local CAPTURE_AVAILABLE_KEY = "available"
local CAPTURE_HEARTBEAT_KEY = "heartbeat"
local DATA_FILE = "actions_clipboard.json"
local HISTORY_LIMIT = 20

local state = {
  slots = {},
  data_path = "",
  loaded = false,
  last_change = "",
  last_capture_seq = 0,
  ignore_capture_cmd = nil,
  ignore_capture_until = 0,
  capture_last_recorded = "",
  capture_history = {}
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

local function clamp_slot_count(value)
  value = math.floor(tonumber(value) or DEFAULT_SLOT_COUNT)
  return math.max(MIN_SLOT_COUNT, math.min(MAX_SLOT_COUNT, value))
end

local function apply_slot_count(value)
  M.slot_count = clamp_slot_count(value)
  return M.slot_count
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

local function command_identifier(command_id)
  command_id = tonumber(command_id)
  if not command_id then return nil end
  if r.ReverseNamedCommandLookup then
    local ok, name = pcall(r.ReverseNamedCommandLookup, command_id)
    name = ok and trim(name) or ""
    if name ~= "" then
      if name:sub(1, 1) ~= "_" then name = "_" .. name end
      return name
    end
  end
  return tostring(command_id)
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
  if command_id then cmd = command_identifier(command_id) or cmd end
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
  local slots = {}
  local limit = math.max(M.slot_count, math.min(#state.slots, MAX_SLOT_COUNT))
  for index = 1, limit do
    slots[index] = normalize_slot(state.slots[index], index)
  end
  return write_json(state.data_path, { slot_count = M.slot_count, slots = slots })
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
      for index = 1, MAX_SLOT_COUNT do
        if source[index] ~= nil then state.slots[index] = normalize_slot(source[index], index) end
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
  if command_id then cmd = command_identifier(command_id) or cmd end
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
  for index = 1, M.slot_count do
    local slot = state.slots[index]
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
  for slot_index = 1, M.slot_count do
    local slot = state.slots[slot_index]
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

local function copy_command_id(app, entry)
  local cmd = trim(entry and entry.cmd)
  local command_id = resolve_command(cmd)
  if command_id then cmd = command_identifier(command_id) or cmd end
  copy_to_clipboard(app, cmd, "command ID")
end

local function ignored_commands(settings)
  settings.ignored_capture_commands = type(settings.ignored_capture_commands) == "table" and settings.ignored_capture_commands or {}
  return settings.ignored_capture_commands
end

local function ensure_settings(app)
  app.settings = app.settings or {}
  app.settings.action_clipboard = app.settings.action_clipboard or {}
  if app.settings.action_clipboard.capture_native_actions == nil then
    app.settings.action_clipboard.capture_native_actions = true
  end
  if app.settings.action_clipboard.auto_fill_slots == nil then
    app.settings.action_clipboard.auto_fill_slots = false
  end
  ignored_commands(app.settings.action_clipboard)
  app.settings.action_clipboard.slot_count = apply_slot_count(app.settings.action_clipboard.slot_count)
  if state.loaded then ensure_slots() end
  return app.settings.action_clipboard
end

local function capture_enabled(app)
  return ensure_settings(app).capture_native_actions ~= false
end

local function native_capture_available()
  return trim(r.GetExtState(CAPTURE_EXT_SECTION, CAPTURE_AVAILABLE_KEY)) == "true"
end

local function push_slider_theme(ctx)
  local count = 0
  if r.ImGui_Col_FrameBg then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), Theme.colors.frame_bg); count = count + 1 end
  if r.ImGui_Col_FrameBgHovered then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgHovered(), Theme.colors.frame_hover); count = count + 1 end
  if r.ImGui_Col_FrameBgActive then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgActive(), Theme.colors.accent_soft); count = count + 1 end
  if r.ImGui_Col_SliderGrab then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrab(), Theme.colors.accent); count = count + 1 end
  if r.ImGui_Col_SliderGrabActive then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrabActive(), Theme.colors.text); count = count + 1 end
  return count
end

local function pop_slider_theme(ctx, count)
  if count and count > 0 then r.ImGui_PopStyleColor(ctx, count) end
end

local function is_action_clipboard_control_action(command_text_value)
  return command_text_value:find("tk_workbench_action_clipboard_run_slot_", 1, true)
    or command_text_value:find("tk_workbench_action_clipboard_toggle_lock_slot_", 1, true)
    or command_text_value:find("action clipboard: run slot", 1, true)
    or command_text_value:find("action clipboard: toggle lock slot", 1, true)
end

local function is_ignored_command(app, command_id)
  local settings = ensure_settings(app)
  local ignored = ignored_commands(settings)
  local named_command = command_identifier(command_id)
  return ignored[tostring(command_id)] == true or (named_command and ignored[named_command] == true)
end

local function ignore_history_entry(app, entry)
  if not entry or trim(entry.cmd) == "" then return end
  local settings = ensure_settings(app)
  ignored_commands(settings)[tostring(entry.cmd)] = true
  for index = #state.capture_history, 1, -1 do
    if commands_match(state.capture_history[index].cmd, entry.cmd) then table.remove(state.capture_history, index) end
  end
  if app.save_settings then app.save_settings() end
  app.status = "Ignored capture: " .. tostring(entry.name or entry.cmd)
end

local function ignored_command_count(app)
  local count = 0
  for _, ignored in pairs(ignored_commands(ensure_settings(app))) do
    if ignored == true then count = count + 1 end
  end
  return count
end

local function clear_ignored_commands(app)
  ensure_settings(app).ignored_capture_commands = {}
  if app.save_settings then app.save_settings() end
  app.status = "Cleared ignored captures"
end

local function add_capture_history(entry)
  if not entry then return end
  for index = #state.capture_history, 1, -1 do
    if commands_match(state.capture_history[index].cmd, entry.cmd) then table.remove(state.capture_history, index) end
  end
  table.insert(state.capture_history, 1, entry)
  while #state.capture_history > HISTORY_LIMIT do table.remove(state.capture_history) end
end

local function should_ignore_captured_action(app, command_id, name, event_time)
  local command_text_value = tostring(name or ""):lower()
  if command_id <= 0 then return true end
  if command_text_value:find("^tk workbench:") then return true end
  if is_action_clipboard_control_action(command_text_value) then return true end
  if is_ignored_command(app, command_id) then return true end
  if state.ignore_capture_cmd and tostring(command_id) == tostring(state.ignore_capture_cmd) then
    if (tonumber(event_time) or 0) <= (tonumber(state.ignore_capture_until) or 0) then return true end
  end
  return false
end

local function parse_capture_event(line)
  local seq, event_time, section, command, source = tostring(line or ""):match("^(%d+)|([^|]*)|([^|]*)|([^|]*)|([^|]*)$")
  seq = tonumber(seq)
  command = tonumber(command)
  if not seq or not command then return nil end
  return {
    seq = seq,
    time = tonumber(event_time) or 0,
    section = tonumber(section) or 0,
    command = command,
    source = tostring(source or "")
  }
end

local function sync_capture_sequence()
  state.last_capture_seq = tonumber(r.GetExtState(CAPTURE_EXT_SECTION, CAPTURE_SEQ_KEY)) or state.last_capture_seq or 0
end

local function process_native_capture(app)
  local settings = ensure_settings(app)
  if not capture_enabled(app) then
    sync_capture_sequence()
    return
  end
  local newest_seq = tonumber(r.GetExtState(CAPTURE_EXT_SECTION, CAPTURE_SEQ_KEY)) or 0
  if newest_seq <= (state.last_capture_seq or 0) then return end
  local events = r.GetExtState(CAPTURE_EXT_SECTION, CAPTURE_EVENTS_KEY) or ""
  local processed_seq = state.last_capture_seq or 0
  for line in tostring(events):gmatch("[^\r\n]+") do
    local event = parse_capture_event(line)
    if event and event.seq > (state.last_capture_seq or 0) then
      local name = command_text(event.command) or ("Command " .. tostring(event.command))
      if not should_ignore_captured_action(app, event.command, name, event.time) then
        local entry = {
          cmd = command_identifier(event.command) or tostring(event.command),
          name = name,
          label = trim(event.source),
          locked = false,
          last_used = now(),
          shortcut = shortcut_for_action(event.command)
        }
        add_capture_history(entry)
        if settings.auto_fill_slots == true then record_entry(app, entry, false) end
        state.capture_last_recorded = name
      end
      if event.seq > processed_seq then processed_seq = event.seq end
    end
  end
  state.last_capture_seq = math.max(processed_seq, newest_seq)
end

function M.init(app)
  ensure_loaded(app)
  ensure_settings(app)
  sync_capture_sequence()
end

function M.record_action(app, action, update_status)
  return record_entry(app, entry_from_action(action), update_status)
end

function M.set_slot(app, action, index, update_status)
  return set_slot_entry(app, entry_from_action(action), index, update_status)
end

function M.get_slot_count(app)
  if app then return ensure_settings(app).slot_count end
  return M.slot_count
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
  state.ignore_capture_cmd = tostring(command_id)
  state.ignore_capture_until = (r.time_precise and r.time_precise() or os.clock()) + 1.0
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
  return line_h * 2 + (button_h + 6) * M.slot_count + 190
end

local function set_history_entry_slot(app, entry, index, locked)
  if not set_slot_entry(app, entry, index, true) then return end
  if locked then
    state.slots[index].locked = true
    save_slots()
    mark_changed()
    app.status = "Pinned capture to slot " .. tostring(index) .. ": " .. tostring(entry.name or entry.cmd)
  end
end

local function draw_history_entry_menu(app, entry)
  local ctx = app.ctx
  if r.ImGui_MenuItem(ctx, "Run Action") then
    local command_id = resolve_command(entry.cmd)
    if command_id then
      r.Main_OnCommand(command_id, 0)
      app.status = "Executed history action: " .. tostring(entry.name or entry.cmd)
    end
  end
  if r.ImGui_MenuItem(ctx, "Add to Clipboard") then record_entry(app, entry, true) end
  if r.ImGui_BeginMenu(ctx, "Set Slot") then
    for index = 1, M.slot_count do
      if r.ImGui_MenuItem(ctx, "Slot " .. tostring(index)) then set_history_entry_slot(app, entry, index, false) end
    end
    r.ImGui_EndMenu(ctx)
  end
  if r.ImGui_BeginMenu(ctx, "Pin to Slot") then
    for index = 1, M.slot_count do
      if r.ImGui_MenuItem(ctx, "Slot " .. tostring(index)) then set_history_entry_slot(app, entry, index, true) end
    end
    r.ImGui_EndMenu(ctx)
  end
  if r.ImGui_MenuItem(ctx, "Ignore From Now On") then ignore_history_entry(app, entry) end
  if r.ImGui_MenuItem(ctx, "Copy Command ID") then copy_command_id(app, entry) end
  if r.ImGui_MenuItem(ctx, "Copy Action Text") then copy_to_clipboard(app, entry.name, "action text") end
end

local function draw_capture_history(app, avail_w)
  local ctx = app.ctx
  local line_h = r.ImGui_GetTextLineHeight(ctx)
  r.ImGui_TextColored(ctx, Theme.colors.accent, "Capture History")
  r.ImGui_SameLine(ctx)
  r.ImGui_TextColored(ctx, Theme.colors.text_dim, tostring(#state.capture_history) .. "/" .. tostring(HISTORY_LIMIT))
  if #state.capture_history > 0 then
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Clear##capture_history", 58, 0) then state.capture_history = {} end
  end
  if ignored_command_count(app) > 0 then
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Clear Ignored##capture_history_clear_ignored") then clear_ignored_commands(app) end
  end
  local history_h = (r.ImGui_GetFrameHeight(ctx) + 4) * 7
  if r.ImGui_BeginChild(ctx, "##action_clipboard_capture_history", 0, history_h, 1) then
    if #state.capture_history == 0 then
      r.ImGui_TextColored(ctx, Theme.colors.text_dim, "No captured actions yet")
    else
      for index, entry in ipairs(state.capture_history) do
        r.ImGui_PushID(ctx, "capture_history_" .. tostring(index))
        local label = tostring(entry.name or entry.cmd)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), Theme.colors.text)
        if r.ImGui_Selectable(ctx, label .. "##history_select", false, 0, math.max(80, avail_w - 16), line_h + 4) then record_entry(app, entry, true) end
        r.ImGui_PopStyleColor(ctx)
        if r.ImGui_IsItemHovered(ctx) then
          local details = tostring(entry.name or entry.cmd) .. "\nCommand: " .. tostring(entry.cmd)
          if entry.shortcut then details = details .. "\nShortcut: " .. tostring(entry.shortcut) end
          r.ImGui_SetTooltip(ctx, details)
        end
        if r.ImGui_BeginPopupContextItem(ctx, "##capture_history_context") then
          draw_history_entry_menu(app, entry)
          r.ImGui_EndPopup(ctx)
        end
        r.ImGui_PopID(ctx)
      end
    end
    r.ImGui_EndChild(ctx)
  end
end

function M.draw_panel(app)
  ensure_loaded(app)
  local ctx = app.ctx
  local settings = ensure_settings(app)
  local avail_w = r.ImGui_GetContentRegionAvail(ctx)
  local button_h = r.ImGui_GetFrameHeight(ctx)
  r.ImGui_TextColored(ctx, Theme.colors.accent, "Action Clipboard")
  local changed, enabled = r.ImGui_Checkbox(ctx, "Native capture", settings.capture_native_actions ~= false)
  if changed then
    settings.capture_native_actions = enabled
    sync_capture_sequence()
    if app.save_settings then app.save_settings() end
    app.status = enabled and "Native action capture enabled" or "Native action capture disabled"
  end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Capture actions reported by the native TK Action Capture extension") end
  r.ImGui_SameLine(ctx)
  local auto_changed, auto_fill = r.ImGui_Checkbox(ctx, "Auto-fill slots", settings.auto_fill_slots == true)
  if auto_changed then
    settings.auto_fill_slots = auto_fill
    if app.save_settings then app.save_settings() end
    app.status = auto_fill and "Capture auto-fill enabled" or "Capture auto-fill disabled"
  end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Automatically push native captures into the slots") end
  r.ImGui_SameLine(ctx)
  local capture_text = native_capture_available() and "available" or "not installed"
  r.ImGui_TextColored(ctx, native_capture_available() and Theme.colors.accent or Theme.colors.text_dim, capture_text)
  if state.capture_last_recorded ~= "" then
    r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Last native capture: " .. tostring(state.capture_last_recorded))
  end
  r.ImGui_SetNextItemWidth(ctx, math.min(180, math.max(120, avail_w * 0.45)))
  local slider_style_count = push_slider_theme(ctx)
  local slot_changed, slot_count = r.ImGui_SliderInt(ctx, "Slots", settings.slot_count, MIN_SLOT_COUNT, MAX_SLOT_COUNT, "%d")
  pop_slider_theme(ctx, slider_style_count)
  if slot_changed then
    settings.slot_count = apply_slot_count(slot_count)
    ensure_slots()
    save_slots()
    if app.save_settings then app.save_settings() end
    app.status = "Action clipboard slots: " .. tostring(settings.slot_count)
  end
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
        if r.ImGui_MenuItem(ctx, "Copy Command ID") then copy_command_id(app, slot) end
        if r.ImGui_MenuItem(ctx, "Copy Action Text") then copy_to_clipboard(app, slot.name, "action text") end
      end
      r.ImGui_EndPopup(ctx)
    end
    r.ImGui_PopID(ctx)
  end
  r.ImGui_Separator(ctx)
  draw_capture_history(app, avail_w)
end

function M.draw(app)
  M.draw_panel(app)
end

function M.update(app)
  M.process_commands(app)
  process_native_capture(app)
end

function M.command_script(action, index)
  return string.format('local r = reaper\nr.SetExtState("%s", "%s", "%s:%d", false)\n', EXT_SECTION, COMMAND_KEY, action, index)
end

return M