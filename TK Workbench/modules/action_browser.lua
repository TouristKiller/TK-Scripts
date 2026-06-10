local r = reaper
local Theme = require("core.theme")
local UI = require("core.ui")
local UIScale = require("core.ui_scale")
local ActionClipboard = require("modules.action_clipboard")

local M = {
  id = "action_browser",
  title = "Action Browser",
  icon = "ACT",
  version = "0.1.0"
}

local state = {
  actions = {},
  categories = {},
  cached_items = nil,
  search_term = "",
  last_search_term = nil,
  show_categories = true,
  last_show_categories = nil,
  show_only_active = false,
  last_show_only_active = nil,
  search_change_time = 0,
  debounce_ms = 150,
  source = "",
  loaded = false
}

local fuzzy_cache = {}
local category_names = {
  "Appearance and Themes",
  "Automation",
  "Editing",
  "Markers and Regions",
  "MIDI",
  "Miscellaneous",
  "Mixing and Effects",
  "Project Management",
  "Recording and Playback",
  "Scripting and Customization",
  "Synchronization and Tempo",
  "Track and Item Management",
  "Transport",
  "View and Zoom"
}

local fallback_actions = {
  { name = "Transport: Play/stop", id = 40044 },
  { name = "Transport: Record", id = 1013 },
  { name = "Edit: Copy items/tracks/envelope points", id = 40698 },
  { name = "Edit: Paste items/tracks", id = 40058 },
  { name = "Track: Insert new track", id = 40001 },
  { name = "Item: Split items at edit cursor", id = 40746 },
  { name = "View: Zoom to fit all in window", id = 40031 }
}

local function fuzzy_normalize(value)
  if not value then return "" end
  local cached = fuzzy_cache[value]
  if cached then return cached end
  local normalized = value:lower():gsub("[%-_%.%s]+", "")
  fuzzy_cache[value] = normalized
  return normalized
end

local function fuzzy_find(haystack, needle)
  if not needle or needle == "" then return true end
  if not haystack then return false end
  local needle_lower = needle:lower()
  local haystack_lower = haystack:lower()
  if haystack_lower:find(needle_lower, 1, true) then return true end
  if needle_lower:find("%s") then
    local haystack_norm = fuzzy_normalize(haystack)
    for token in needle_lower:gmatch("%S+") do
      local token_norm = token:gsub("[%-_%.]+", "")
      if token_norm ~= "" and not haystack_lower:find(token, 1, true) and not haystack_norm:find(token_norm, 1, true) then
        return false
      end
    end
    return true
  end
  if needle_lower:find("[%-_%.]") then
    local haystack_norm = fuzzy_normalize(haystack)
    local needle_norm = needle_lower:gsub("[%-_%.%s]+", "")
    return needle_norm ~= "" and haystack_norm:find(needle_norm, 1, true) ~= nil
  end
  return false
end

local function reset_categories()
  state.categories = {}
  for _, name in ipairs(category_names) do
    state.categories[name] = {}
  end
end

local function action_category(action_name)
  local name = (action_name or ""):lower()
  if name:find("transport") or name:find("stop") or name:find("pause") or name:find("rewind") or name:find("forward") then return "Transport" end
  if name:find("project") or name:find("file") or name:find("save") or name:find("open") then return "Project Management" end
  if name:find("edit") or name:find("cut") or name:find("copy") or name:find("paste") then return "Editing" end
  if name:find("track") or name:find("item") then return "Track and Item Management" end
  if name:find("record") or name:find("play") then return "Recording and Playback" end
  if name:find("mix") or name:find("fx") or name:find("effect") then return "Mixing and Effects" end
  if name:find("midi") then return "MIDI" end
  if name:find("marker") or name:find("region") then return "Markers and Regions" end
  if name:find("view") or name:find("zoom") then return "View and Zoom" end
  if name:find("automation") or name:find("envelope") then return "Automation" end
  if name:find("sync") or name:find("tempo") then return "Synchronization and Tempo" end
  if name:find("script") or name:find("action") then return "Scripting and Customization" end
  if name:find("theme") or name:find("color") then return "Appearance and Themes" end
  return "Miscellaneous"
end

local function shortcut_for_action(action_id)
  if not r.CountActionShortcuts or not r.GetActionShortcutDesc then return nil end
  local ok_count, count = pcall(r.CountActionShortcuts, 0, action_id)
  if not ok_count or not count or count <= 0 then return nil end
  local ok_desc, has_desc, desc = pcall(r.GetActionShortcutDesc, 0, action_id, 0)
  if ok_desc and has_desc and desc and desc ~= "" then return desc end
  return nil
end

local function command_identifier(command_id)
  if r.ReverseNamedCommandLookup then
    local ok, name = pcall(r.ReverseNamedCommandLookup, command_id)
    name = ok and tostring(name or ""):match("^%s*(.-)%s*$") or ""
    if name ~= "" then
      if name:sub(1, 1) ~= "_" then name = "_" .. name end
      return name
    end
  end
  return tostring(command_id or "")
end

local function add_action(action)
  action.shortcut = shortcut_for_action(action.id)
  state.actions[#state.actions + 1] = action
  local category = action_category(action.name)
  state.categories[category][#state.categories[category] + 1] = action
end

local function load_actions()
  state.actions = {}
  fuzzy_cache = {}
  reset_categories()
  if r.CF_EnumerateActions then
    local index = 0
    while true do
      local command_id, name = r.CF_EnumerateActions(0, index)
      if not command_id or command_id <= 0 then break end
      if name and name ~= "" then add_action({ name = name, id = command_id }) end
      index = index + 1
    end
    state.source = "SWS action index"
  else
    for _, action in ipairs(fallback_actions) do
      add_action({ name = action.name, id = action.id })
    end
    state.source = "Fallback action list"
  end
  table.sort(state.actions, function(left, right) return left.name < right.name end)
  for _, actions in pairs(state.categories) do
    table.sort(actions, function(left, right) return left.name < right.name end)
  end
  state.cached_items = nil
  state.loaded = true
end

local function create_smart_marker(action_id)
  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)
  local color = r.ColorToNative(255, 64, 64) | 0x1000000
  local marker_name = "!" .. tostring(action_id)
  r.AddProjectMarker2(0, false, r.GetCursorPosition(), 0, marker_name, -1, color)
  r.PreventUIRefresh(-1)
  r.UpdateTimeline()
  r.Undo_EndBlock("Create action marker", -1)
end

local function execute_action(app, action)
  if not action then return end
  r.Main_OnCommand(action.id, 0)
  ActionClipboard.record_action(app, action, false)
  app.status = "Executed: " .. action.name
end

local function copy_to_clipboard(app, value, label)
  if r.CF_SetClipboard then
    r.CF_SetClipboard(tostring(value or ""))
    app.status = "Copied " .. label
  else
    app.status = "SWS clipboard API is not available"
  end
end

local function filtered_categories()
  local result = {}
  for _, category in ipairs(category_names) do
    local filtered = {}
    for _, action in ipairs(state.categories[category] or {}) do
      local toggle_state = r.GetToggleCommandState(action.id)
      local matches = fuzzy_find(action.name, state.search_term)
      if matches and (not state.show_only_active or toggle_state == 1) then
        action.state = toggle_state
        filtered[#filtered + 1] = action
      end
    end
    if #filtered > 0 then result[#result + 1] = { name = category, actions = filtered } end
  end
  return result
end

local function filtered_flat()
  local result = {}
  for _, action in ipairs(state.actions) do
    local toggle_state = r.GetToggleCommandState(action.id)
    local matches = fuzzy_find(action.name, state.search_term)
    if matches and (not state.show_only_active or toggle_state == 1) then
      action.state = toggle_state
      result[#result + 1] = { action = action }
    end
  end
  return result
end

local function refresh_cache(force)
  local term_changed = state.search_term ~= state.last_search_term
  local mode_changed = state.show_categories ~= state.last_show_categories or state.show_only_active ~= state.last_show_only_active
  local debounce_ready = (r.time_precise() - state.search_change_time) * 1000 >= state.debounce_ms
  if force or not state.cached_items or mode_changed or (term_changed and debounce_ready) then
    state.cached_items = state.show_categories and filtered_categories() or filtered_flat()
    state.last_search_term = state.search_term
    state.last_show_categories = state.show_categories
    state.last_show_only_active = state.show_only_active
  end
end

local function draw_action_context_menu(app, action, popup_id)
  local ctx = app.ctx
  if r.ImGui_BeginPopupContextItem(ctx, popup_id) then
    if r.ImGui_MenuItem(ctx, "Set Action Marker") then
      create_smart_marker(action.id)
      app.status = "Set action marker: " .. tostring(action.id)
    end
    if r.ImGui_MenuItem(ctx, "Add to Script Launcher") then
      local launcher = app.modules_by_id and app.modules_by_id.script_launcher
      if launcher and launcher.add_entry then
        launcher.add_entry(app, action)
      else
        app.status = "Script Launcher module not loaded"
      end
    end
    if r.ImGui_MenuItem(ctx, "Add to Action Clipboard") then ActionClipboard.record_action(app, action, true) end
    if r.ImGui_BeginMenu(ctx, "Add to Clipboard Slot") then
      local slot_count = ActionClipboard.get_slot_count and ActionClipboard.get_slot_count(app) or ActionClipboard.slot_count
      for index = 1, slot_count do
        if r.ImGui_MenuItem(ctx, "Slot " .. tostring(index)) then ActionClipboard.set_slot(app, action, index, true) end
      end
      r.ImGui_EndMenu(ctx)
    end
    if r.ImGui_MenuItem(ctx, "Copy Command ID") then copy_to_clipboard(app, command_identifier(action.id), "command ID") end
    if r.ImGui_MenuItem(ctx, "Copy Action Text") then copy_to_clipboard(app, action.name, "action text") end
    r.ImGui_EndPopup(ctx)
  end
end

local function draw_action_row(app, action, suffix)
  local ctx = app.ctx
  local active = action.state == 1
  if active then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), Theme.text_for_backgrounds({ Theme.colors.window_bg, Theme.colors.child_bg, Theme.colors.frame_bg }, Theme.colors.danger, Theme.colors.text, 4.5)) end
  local prefix = active and "[ON] " or ""
  if r.ImGui_Selectable(ctx, prefix .. action.name .. "##" .. suffix .. tostring(action.id), false, r.ImGui_SelectableFlags_AllowOverlap()) then
    execute_action(app, action)
  end
  if active then r.ImGui_PopStyleColor(ctx) end
  draw_action_context_menu(app, action, "##action_context_" .. suffix .. tostring(action.id))
  if action.shortcut then
    r.ImGui_SameLine(ctx)
    r.ImGui_TextColored(ctx, Theme.colors.accent, "[" .. action.shortcut .. "]")
  end
end

function M.init()
  load_actions()
end

function M.draw(app)
  local ctx = app.ctx
  if not state.loaded then load_actions() end

  local avail_w, avail_h = r.ImGui_GetContentRegionAvail(ctx)
  local button_h = UIScale.button_h(ctx)
  local button_w = button_h
  local search_w = math.max(UIScale.round(80), avail_w - (button_w * 3) - UIScale.round(24))
  local changed, search = UI.search_input(ctx, "##action_browser_search", "Search actions", state.search_term or "", search_w)
  if changed then
    state.search_term = search
    state.search_change_time = r.time_precise()
  end

  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, state.show_categories and "G" or "F", button_w, button_h) then
    state.show_categories = not state.show_categories
    refresh_cache(true)
  end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, state.show_categories and "Grouped view" or "Flat view") end

  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, state.show_only_active and "On" or "All", button_w, button_h) then
    state.show_only_active = not state.show_only_active
    refresh_cache(true)
  end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, state.show_only_active and "Showing active toggle actions" or "Showing all matching actions") end

  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "R", button_w, button_h) then
    load_actions()
    app.status = "Action list reloaded"
  end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Reload action list") end

  refresh_cache(false)

  local info_h = UI.info_line_height(ctx)
  local _, list_avail_h = r.ImGui_GetContentRegionAvail(ctx)
  local list_h = math.max(UIScale.round(60), (list_avail_h or avail_h or UIScale.round(300)) - info_h)
  if r.ImGui_BeginChild(ctx, "##action_browser_list", 0, list_h, 0) then
    if state.show_categories then
      for _, category in ipairs(state.cached_items or {}) do
        if r.ImGui_TreeNode(ctx, category.name .. " (" .. tostring(#category.actions) .. ")") then
          for _, action in ipairs(category.actions) do
            draw_action_row(app, action, "cat")
          end
          r.ImGui_TreePop(ctx)
        end
      end
    else
      for _, item in ipairs(state.cached_items or {}) do
        draw_action_row(app, item.action, "flat")
      end
    end
    r.ImGui_EndChild(ctx)
  end

  UI.draw_info_line(ctx, tostring(#state.actions) .. " actions | " .. state.source .. " | Left-click executes, right-click opens context")
end

return M