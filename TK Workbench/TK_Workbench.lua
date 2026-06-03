-- @description TK Workbench
-- @author TouristKiller
-- @version 0.2.2
-- @changelog:
-- v0.2.2
--   + Action Clipboard: Added cross-platform TK Action Capture binaries for Windows, macOS and Linux delivery
--   + Native capture: Updated ReaPack delivery so platform artifacts install into the Workbench folder for manual UserPlugins copy
-- v0.2.1
--   + Action Browser: Added Action Clipboard footer with 5 recent, lockable action slots
--   + Action Browser: Added C shortcut to show or hide the Action Clipboard footer
--   + Action Browser: Added context menu actions to add actions to the clipboard or directly to a specific slot
--   + Action Clipboard: Added mappable run and lock-toggle slot scripts that work without Workbench being open
--   + Action Clipboard: Added persistent slot storage, external refresh handling, clearer lock styling, and shortcut details in tooltips
--   + Media Browser: Auto Categories now works on the currently open subfolder when folder browsing is active
--   + Project Browser: Added optional folder view for browsing subfolders in projects, project templates, and track templates
--   + Plugin Browser: Added virtual instrument new-track action with MIDI input selection
--   + Workbench: Added REAPER Theme preset for deriving Workbench colors from the active REAPER theme
--   + Workbench: Added mappable module actions for opening Home and each Workbench module, with automatic Workbench launch
--   + Workbench: Added separate Action Clipboard Actions and Module Actions folders for cleaner REAPER action organization
--   + Workbench: Added ExtState command handling for external clipboard and module action scripts
-- v0.1.7
--   + Project Browser: Added compact Workbench module for projects, project templates, and track templates
--   + Project Browser: Added per-type user locations, recursive scanning, search/filter, date sorting, cover previews, and open/insert actions
--   + Project Browser: Added read-only project metadata for BPM, signature, tracks, sample rate, modified date, and lightweight length detection
-- v0.1.5
--   + Media Browser: Added optional fade-in/fade-out handling for onboard audio previews
--   + Media Browser: Added configurable preview fade duration, disabled by default
--   + Media Browser: Added configurable audio switch gap and delayed source cleanup for onboard preview file switching
--   + Media Browser: Added optional tape-speed rate mode so pitch follows persistent rate changes while previewing files
--   + Media Browser: Added optional double-click-to-open behavior for folder browsing
--   + Plugin Browser: Added right-click screenshot capture with normal and OpenGL/DX modes, saved to the central TK FX BROWSER Screenshots folder
--   + Plugin Browser: Improved screenshot matching for x86/x86 bridged, Mono/Stereo, sanitized underscore, and manufacturer-prefix variants
--   + Control Room: Added monitor output modes for Stereo, Mono Sum, L/R Source, and L/R Speaker checks
--   + Control Room: Added setup and right-click lane controls for monitor output modes
--   + Control Room: Added Stereo and Mono Sum output modes for cue outputs, including setup and right-click lane controls
--   + Track Recall: Added multi-track save for selected tracks with automatic track-name based recall names
-- v0.1.4
--   + Media Browser: Added lazy per-location cache loading with explicit refresh
--   + Media Browser: Added compact folder browsing with subfolder rows
--   + Media Browser: Added folder cover-art thumbnails for cover/folder/front images
--   + Media Browser: Reworked media cache storage to avoid large Lua cache load errors
--   + Media Browser: Added option for random navigation during auto-preview playback
--   + Media Browser: Fixed drag-and-drop insertion into REAPER fixed item lanes
--   + Media Browser: Added audio-file context menu actions for RS5K and Cartridge loading
--   + Media Browser: Added RS5K Manager pad load/create/delete actions from the audio context menu
--   + Media Browser: Added RS5K Manager toggle action matching the standalone browser workflow
--   + Workbench: Added global tooltip enable and delay preferences
--   + Workbench: Added optional compact Info box footer with clipped text and hover details
--   + Workbench: Centralized Info box positioning so it stays aligned across modules
--   + Workbench: Improved module error display with compact diagnostics
--   + Color Studio: Added optional auto-apply for matching track color rules
-- v0.1.3
--   + Plugin Browser: Added option to return to Rack after adding FX from Rack
--   + Plugin Browser: Added option to return to FX Chain Builder after adding FX to Chain Builder
--   + Media Browser: Stop active preview playback when Workbench is closed by shortcut or action toggle
-- v0.1.2
--   + Added support for secondary Workbench launchers with separate script name and config file
-- v0.1.1
--   + Home: Added drag-and-drop module tile reordering with matching module dropdown order
--   + Instrument Rack: Added MIDI learn and hardware control support for rack macros
--   + Instrument Rack: Added absolute, relative, invert, range calibration, and sensitivity options for macro MIDI control
--   + Instrument Rack: Added global rack macro footer with 8 macro controls
--   + Instrument Rack: Added Assign to Macro workflow from pinned parameter controls
--   + Instrument Rack: Added project-persistent macro assignments with range and invert support
--   + Script Launcher: Added Capture Window for thumbnail screenshot capture
--   + Script Launcher: Added right-click context menu with Edit and Delete
--   + Script Launcher: Stabilized context-menu edit flow


local r = reaper

local SCRIPT_NAME = rawget(_G, "TK_WORKBENCH_SCRIPT_NAME") or "TK Workbench"
if not r.ImGui_CreateContext then
  r.ShowMessageBox("ReaImGui is required for TK Workbench.", SCRIPT_NAME, 0)
  return
end

local script_path = debug.getinfo(1, "S").source:match("@?(.*[\\/])") or ""
local sep = package.config:sub(1, 1)
package.path = script_path .. "?.lua;" .. script_path .. "?" .. sep .. "init.lua;" .. package.path

local Settings = require("core.settings")
local Theme = require("core.theme")
local Selection = require("core.selection")
local ModuleLoader = require("core.module_loader")
local UI = require("core.ui")

local ctx = r.ImGui_CreateContext(SCRIPT_NAME)
local config_name = rawget(_G, "TK_WORKBENCH_CONFIG_NAME") or "config.json"
local config_path = script_path .. config_name
local settings = Settings.load(config_path)

local app = {
  ctx = ctx,
  script_name = SCRIPT_NAME,
  script_path = script_path,
  config_path = config_path,
  settings = settings,
  selection = {},
  modules = {},
  modules_by_id = {},
  module_errors = {},
  cache = {},
  status = "Ready",
  close_requested = false,
  settings_panel = nil
}
UI.configure_tooltips(app)
app.cache.saved_theme_preset = settings.theme_preset or "Graphite"

local HOME_MODULE_ID = "__home"
local MODULE_REORDER_PAYLOAD = "TK_WORKBENCH_MODULE_REORDER"
local MODULE_ACTION_EXT_SECTION = "TK_WORKBENCH_MODULE_ACTIONS"
local MODULE_ACTION_COMMAND_KEY = "command"
local MODULE_ACTION_RUNNING_KEY = "running"
local MODULE_ACTION_HEARTBEAT_KEY = "heartbeat"

local module_names = {
  "project_overview",
  "project_browser",
  "action_browser",
  "action_clipboard",
  "script_launcher",
  "track_recall",
  "automation_item_manager",
  "control_room",
  "instrument_rack",
  "fx_chain_builder",
  "notes",
  "plugin_browser",
  "media_browser",
  "color_studio"
}

local theme_color_fields = {
  { key = "window_bg", label = "Window" },
  { key = "child_bg", label = "Panel" },
  { key = "popup_bg", label = "Popup" },
  { key = "frame_bg", label = "Frame" },
  { key = "frame_hover", label = "Frame Hover" },
  { key = "header", label = "Header" },
  { key = "header_hover", label = "Header Hover" },
  { key = "separator", label = "Separator" },
  { key = "border", label = "Border" },
  { key = "text", label = "Text" },
  { key = "text_dim", label = "Dim Text" },
  { key = "badge_text", label = "Badge Text" },
  { key = "accent", label = "Accent" },
  { key = "accent_soft", label = "Accent Soft" },
  { key = "warning", label = "Warning" },
  { key = "danger", label = "Danger" }
}

local function save_settings()
  Settings.save(config_path, app.settings)
end

app.save_settings = save_settings

local function find_module_index_by_id(id)
  for index, module in ipairs(app.modules) do
    if module.id == id then return index end
  end
  return nil
end

local function normalize_module_order()
  local loaded = {}
  for _, module in ipairs(app.modules) do loaded[module.id] = true end
  local order = type(app.settings.module_order) == "table" and app.settings.module_order or {}
  local normalized = {}
  local used = {}
  for _, id in ipairs(order) do
    if loaded[id] and not used[id] then
      normalized[#normalized + 1] = id
      used[id] = true
    end
  end
  for _, module in ipairs(app.modules) do
    if not used[module.id] then
      normalized[#normalized + 1] = module.id
      used[module.id] = true
    end
  end
  local changed = #normalized ~= #order
  if not changed then
    for index, id in ipairs(normalized) do
      if order[index] ~= id then changed = true; break end
    end
  end
  app.settings.module_order = normalized
  if changed then save_settings() end
  return normalized
end

local function save_module_order()
  local order = {}
  for _, module in ipairs(app.modules) do order[#order + 1] = module.id end
  app.settings.module_order = order
  save_settings()
end

local function apply_module_order()
  local order = normalize_module_order()
  local rank = {}
  for index, id in ipairs(order) do rank[id] = index end
  table.sort(app.modules, function(left, right)
    return (rank[left.id] or 9999) < (rank[right.id] or 9999)
  end)
end

local function move_module_to_target(source_id, target_id)
  if not source_id or not target_id or source_id == target_id then return false end
  local source_index = find_module_index_by_id(source_id)
  local target_index = find_module_index_by_id(target_id)
  if not source_index or not target_index then return false end
  local item = table.remove(app.modules, source_index)
  target_index = find_module_index_by_id(target_id) or target_index
  table.insert(app.modules, target_index, item)
  save_module_order()
  app.status = "Module order updated"
  return true
end

local function is_home_active()
  return app.settings.active_module == HOME_MODULE_ID
end

local function set_active_view(id)
  local current = app.settings.active_module
  if id == "plugin_browser" and current == "instrument_rack" then
    app.cache.plugin_browser_return_module = "instrument_rack"
  elseif id ~= "plugin_browser" then
    app.cache.plugin_browser_return_module = nil
  end
  app.settings.active_module = id
  save_settings()
end

app.set_active_view = set_active_view

local function process_module_action_commands()
  local command = r.GetExtState(MODULE_ACTION_EXT_SECTION, MODULE_ACTION_COMMAND_KEY) or ""
  if command == "" then return end
  r.SetExtState(MODULE_ACTION_EXT_SECTION, MODULE_ACTION_COMMAND_KEY, "", false)
  local action, target = command:match("^([%w_]+):(.+)$")
  if action ~= "open" or not target or target == "" then return end
  if target == HOME_MODULE_ID or app.modules_by_id[target] then
    set_active_view(target)
    local module = app.modules_by_id[target]
    app.status = "Opened " .. tostring(module and (module.title or module.id) or "Home")
  else
    app.status = "Workbench module not found: " .. tostring(target)
  end
end

local function get_active_module()
  local active_id = app.settings.active_module
  if active_id == HOME_MODULE_ID then return nil end
  if app.modules_by_id[active_id] then return app.modules_by_id[active_id] end
  if app.modules[1] then
    app.settings.active_module = app.modules[1].id
    save_settings()
    return app.modules[1]
  end
end

local function calc_text_width(value)
  if r.ImGui_CalcTextSize then
    local width = r.ImGui_CalcTextSize(ctx, tostring(value or ""))
    return tonumber(width) or 0
  end
  return #(tostring(value or "")) * 7
end

local function ellipsize_text(value, max_width)
  value = tostring(value or "")
  if value == "" or calc_text_width(value) <= max_width then return value end
  while #value > 1 and calc_text_width(value .. "...") > max_width do value = value:sub(1, -2) end
  return value .. "..."
end

local function card_title_lines(title, max_width)
  local lines = { "", "" }
  local line_index = 1
  for token in tostring(title or ""):gmatch("%S+") do
    local candidate = lines[line_index] == "" and token or (lines[line_index] .. " " .. token)
    if calc_text_width(candidate) > max_width and lines[line_index] ~= "" then
      line_index = math.min(2, line_index + 1)
      candidate = lines[line_index] == "" and token or (lines[line_index] .. " " .. token)
    end
    lines[line_index] = candidate
  end
  lines[1] = ellipsize_text(lines[1], max_width)
  lines[2] = ellipsize_text(lines[2], max_width)
  return lines
end

local function fallback_icon_text(module)
  local icon = tostring(module and module.icon or "")
  if icon ~= "" then return icon end
  local text = tostring(module and (module.title or module.id) or "")
  local result = ""
  for token in text:gmatch("%S+") do result = result .. token:sub(1, 1):upper() end
  if result == "" then result = "?" end
  return result:sub(1, 3)
end

local function draw_home_icon(draw_list, x, y, size, color)
  local left = x + size * 0.2
  local right = x + size * 0.8
  local top = y + size * 0.25
  local mid = y + size * 0.48
  local bottom = y + size * 0.82
  r.ImGui_DrawList_AddLine(draw_list, left, mid, x + size * 0.5, top, color, 2)
  r.ImGui_DrawList_AddLine(draw_list, x + size * 0.5, top, right, mid, color, 2)
  r.ImGui_DrawList_AddRect(draw_list, left + 2, mid, right - 2, bottom, color, 2, 0, 2)
  r.ImGui_DrawList_AddLine(draw_list, x + size * 0.48, bottom, x + size * 0.48, y + size * 0.64, color, 2)
  r.ImGui_DrawList_AddLine(draw_list, x + size * 0.48, y + size * 0.64, x + size * 0.62, y + size * 0.64, color, 2)
  r.ImGui_DrawList_AddLine(draw_list, x + size * 0.62, y + size * 0.64, x + size * 0.62, bottom, color, 2)
end

local function draw_module_icon(draw_list, module, cx, cy, size, color)
  local id = module and module.id or ""
  local left = cx - size * 0.5
  local right = cx + size * 0.5
  local top = cy - size * 0.5
  local bottom = cy + size * 0.5
  if id == "project_overview" then
    r.ImGui_DrawList_AddCircle(draw_list, cx, cy, size * 0.34, color, 32, 2)
    r.ImGui_DrawList_AddCircleFilled(draw_list, cx, top + 16, 2.2, color, 12)
    r.ImGui_DrawList_AddLine(draw_list, cx, cy - 2, cx, bottom - 14, color, 3)
    r.ImGui_DrawList_AddLine(draw_list, cx - 5, cy - 2, cx, cy - 2, color, 3)
    r.ImGui_DrawList_AddLine(draw_list, cx - 5, bottom - 14, cx + 5, bottom - 14, color, 3)
  elseif id == "action_browser" then
    r.ImGui_DrawList_AddRect(draw_list, left + 7, top + 9, right - 7, bottom - 9, color, 4, 0, 2)
    r.ImGui_DrawList_AddLine(draw_list, left + 14, top + 18, left + 20, cy - 1, color, 2)
    r.ImGui_DrawList_AddLine(draw_list, left + 20, cy - 1, left + 14, cy + 8, color, 2)
    r.ImGui_DrawList_AddLine(draw_list, left + 25, cy + 8, left + 34, cy + 8, color, 2)
    r.ImGui_DrawList_AddLine(draw_list, left + 14, bottom - 17, right - 16, bottom - 17, color, 2)
    r.ImGui_DrawList_AddLine(draw_list, left + 14, bottom - 10, right - 24, bottom - 10, color, 2)
  elseif id == "action_clipboard" then
    r.ImGui_DrawList_AddRect(draw_list, left + 9, top + 10, right - 9, bottom - 5, color, 4, 0, 2)
    r.ImGui_DrawList_AddRect(draw_list, cx - 10, top + 5, cx + 10, top + 15, color, 4, 0, 2)
    r.ImGui_DrawList_AddLine(draw_list, left + 17, top + 25, left + 21, top + 29, color, 2)
    r.ImGui_DrawList_AddLine(draw_list, left + 21, top + 29, left + 27, top + 20, color, 2)
    r.ImGui_DrawList_AddLine(draw_list, left + 32, top + 26, right - 16, top + 26, color, 2)
    r.ImGui_DrawList_AddLine(draw_list, left + 17, top + 36, left + 21, top + 40, color, 2)
    r.ImGui_DrawList_AddLine(draw_list, left + 21, top + 40, left + 27, top + 31, color, 2)
    r.ImGui_DrawList_AddLine(draw_list, left + 32, top + 37, right - 16, top + 37, color, 2)
  elseif id == "script_launcher" then
    r.ImGui_DrawList_AddRect(draw_list, left + 7, top + 8, right - 7, bottom - 8, color, 4, 0, 2)
    r.ImGui_DrawList_AddLine(draw_list, left + 17, top + 16, left + 17, bottom - 16, color, 2)
    r.ImGui_DrawList_AddLine(draw_list, left + 17, top + 16, right - 16, cy, color, 2)
    r.ImGui_DrawList_AddLine(draw_list, right - 16, cy, left + 17, bottom - 16, color, 2)
  elseif id == "track_recall" then
    r.ImGui_DrawList_AddLine(draw_list, left + 14, top + 8, right - 14, top + 8, color, 2)
    r.ImGui_DrawList_AddLine(draw_list, left + 14, bottom - 8, right - 14, bottom - 8, color, 2)
    r.ImGui_DrawList_AddLine(draw_list, left + 16, top + 10, right - 16, bottom - 10, color, 2)
    r.ImGui_DrawList_AddLine(draw_list, right - 16, top + 10, left + 16, bottom - 10, color, 2)
    r.ImGui_DrawList_AddLine(draw_list, left + 20, top + 15, cx, cy - 2, color, 2)
    r.ImGui_DrawList_AddLine(draw_list, right - 20, top + 15, cx, cy - 2, color, 2)
    r.ImGui_DrawList_AddLine(draw_list, cx, cy + 3, left + 21, bottom - 14, color, 2)
    r.ImGui_DrawList_AddLine(draw_list, cx, cy + 3, right - 21, bottom - 14, color, 2)
  elseif id == "automation_item_manager" then
    r.ImGui_DrawList_AddLine(draw_list, left + 6, bottom - 12, cx - 8, cy + 7, color, 2)
    r.ImGui_DrawList_AddLine(draw_list, cx - 8, cy + 7, cx + 7, cy - 8, color, 2)
    r.ImGui_DrawList_AddLine(draw_list, cx + 7, cy - 8, right - 7, top + 14, color, 2)
    r.ImGui_DrawList_AddCircleFilled(draw_list, left + 6, bottom - 12, 4, color, 12)
    r.ImGui_DrawList_AddCircleFilled(draw_list, cx - 8, cy + 7, 4, color, 12)
    r.ImGui_DrawList_AddCircleFilled(draw_list, cx + 7, cy - 8, 4, color, 12)
    r.ImGui_DrawList_AddCircleFilled(draw_list, right - 7, top + 14, 4, color, 12)
  elseif id == "control_room" then
    r.ImGui_DrawList_AddRect(draw_list, left + 8, top + 8, right - 8, bottom - 8, color, 4, 0, 2)
    r.ImGui_DrawList_AddLine(draw_list, left + 17, bottom - 13, left + 17, top + 18, color, 2)
    r.ImGui_DrawList_AddLine(draw_list, cx, bottom - 13, cx, top + 13, color, 2)
    r.ImGui_DrawList_AddLine(draw_list, right - 17, bottom - 13, right - 17, top + 23, color, 2)
    r.ImGui_DrawList_AddCircleFilled(draw_list, left + 17, cy + 6, 4, color, 12)
    r.ImGui_DrawList_AddCircleFilled(draw_list, cx, cy - 4, 4, color, 12)
    r.ImGui_DrawList_AddCircleFilled(draw_list, right - 17, cy + 10, 4, color, 12)
  elseif id == "instrument_rack" then
    r.ImGui_DrawList_AddRect(draw_list, left + 7, top + 8, right - 7, bottom - 8, color, 3, 0, 2)
    for index = 0, 3 do
      local key_x = left + 12 + index * 9
      r.ImGui_DrawList_AddLine(draw_list, key_x, cy, key_x, bottom - 10, color, 2)
    end
    r.ImGui_DrawList_AddLine(draw_list, left + 8, cy, right - 8, cy, color, 2)
  elseif id == "fx_chain_builder" then
    r.ImGui_DrawList_AddRect(draw_list, left + 6, cy - 13, right - 6, cy + 13, color, 4, 0, 2)
    r.ImGui_DrawList_AddRect(draw_list, left + 10, cy - 6, left + 20, cy + 4, color, 2, 0, 2)
    r.ImGui_DrawList_AddRect(draw_list, left + 23, cy - 6, left + 33, cy + 4, color, 2, 0, 2)
  elseif id == "notes" then
    r.ImGui_DrawList_AddRect(draw_list, left + 8, top + 5, right - 8, bottom - 5, color, 4, 0, 2)
    r.ImGui_DrawList_AddLine(draw_list, left + 14, top + 15, right - 14, top + 15, color, 2)
    r.ImGui_DrawList_AddLine(draw_list, left + 14, top + 25, right - 18, top + 25, color, 2)
    r.ImGui_DrawList_AddLine(draw_list, left + 14, top + 35, right - 22, top + 35, color, 2)
  elseif id == "plugin_browser" then
    r.ImGui_DrawList_AddRect(draw_list, left + 11, cy - 13, right - 13, cy + 13, color, 4, 0, 2)
    r.ImGui_DrawList_AddLine(draw_list, right - 13, cy - 6, right - 6, cy - 6, color, 2)
    r.ImGui_DrawList_AddLine(draw_list, right - 13, cy + 6, right - 6, cy + 6, color, 2)
    r.ImGui_DrawList_AddLine(draw_list, left + 6, cy, left + 11, cy, color, 2)
  elseif id == "media_browser" then
    r.ImGui_DrawList_AddRect(draw_list, left + 6, top + 9, right - 6, bottom - 9, color, 4, 0, 2)
    for index = 0, 3 do
      local film_x = left + 12 + index * 9
      r.ImGui_DrawList_AddLine(draw_list, film_x, top + 10, film_x, top + 17, color, 2)
      r.ImGui_DrawList_AddLine(draw_list, film_x, bottom - 17, film_x, bottom - 10, color, 2)
    end
    r.ImGui_DrawList_AddLine(draw_list, left + 14, cy, cx - 6, cy - 8, color, 2)
    r.ImGui_DrawList_AddLine(draw_list, cx - 6, cy - 8, cx + 6, cy + 8, color, 2)
    r.ImGui_DrawList_AddLine(draw_list, cx + 6, cy + 8, right - 14, cy, color, 2)
  else
    local icon = fallback_icon_text(module)
    r.ImGui_DrawList_AddCircle(draw_list, cx, cy, size * 0.34, color, 32, 2)
    local text_w = calc_text_width(icon)
    r.ImGui_DrawList_AddText(draw_list, cx - text_w * 0.5, cy - r.ImGui_GetTextLineHeight(ctx) * 0.5, color, icon)
  end
end

local function draw_module_card(module, card_width, card_height)
  local draw_list = r.ImGui_GetWindowDrawList(ctx)
  local active = app.settings.active_module == module.id
  r.ImGui_PushID(ctx, module.id)
  local clicked = r.ImGui_InvisibleButton(ctx, "##home_module_card", card_width, card_height)
  local hovered = r.ImGui_IsItemHovered(ctx)
  local x1, y1 = r.ImGui_GetItemRectMin(ctx)
  local x2, y2 = r.ImGui_GetItemRectMax(ctx)
  local bg = active and Theme.colors.accent_soft or (hovered and Theme.colors.frame_hover or Theme.colors.frame_bg)
  local border = active and Theme.colors.accent or Theme.colors.border
  local icon_color = (hovered or active) and Theme.colors.accent or Theme.colors.text_dim
  r.ImGui_DrawList_AddRectFilled(draw_list, x1, y1, x2, y2, bg, 6)
  r.ImGui_DrawList_AddRect(draw_list, x1, y1, x2, y2, border, 6, 0, active and 1.6 or 0.8)
  draw_module_icon(draw_list, module, (x1 + x2) * 0.5, y1 + 36, 48, icon_color)
  local title = tostring(module.title or module.id or "Module")
  local lines = card_title_lines(title, card_width - 14)
  local line_h = r.ImGui_GetTextLineHeight(ctx)
  local text_y = y2 - 12 - line_h * ((lines[2] ~= "" and 2 or 1))
  r.ImGui_DrawList_PushClipRect(draw_list, x1 + 7, y1 + 5, x2 - 7, y2 - 5, true)
  for index = 1, 2 do
    if lines[index] ~= "" then
      local text_w = calc_text_width(lines[index])
      r.ImGui_DrawList_AddText(draw_list, x1 + math.max(7, (card_width - text_w) * 0.5), text_y + (index - 1) * line_h, Theme.colors.text, lines[index])
    end
  end
  r.ImGui_DrawList_PopClipRect(draw_list)
  if r.ImGui_BeginDragDropSource and r.ImGui_SetDragDropPayload then
    local source_flags = r.ImGui_DragDropFlags_SourceNoPreviewTooltip and r.ImGui_DragDropFlags_SourceNoPreviewTooltip() or 0
    if r.ImGui_BeginDragDropSource(ctx, source_flags) then
      r.ImGui_SetDragDropPayload(ctx, MODULE_REORDER_PAYLOAD, module.id)
      r.ImGui_Text(ctx, title)
      r.ImGui_EndDragDropSource(ctx)
    end
  end
  if r.ImGui_BeginDragDropTarget and r.ImGui_AcceptDragDropPayload and r.ImGui_BeginDragDropTarget(ctx) then
    r.ImGui_DrawList_AddRect(draw_list, x1 + 2, y1 + 2, x2 - 2, y2 - 2, Theme.colors.accent, 6, 0, 2)
    local ok, payload = r.ImGui_AcceptDragDropPayload(ctx, MODULE_REORDER_PAYLOAD)
    if ok and payload and payload ~= module.id then app.cache.pending_module_reorder = { source = payload, target = module.id } end
    r.ImGui_EndDragDropTarget(ctx)
  end
  if clicked then set_active_view(module.id) end
  if hovered then r.ImGui_SetTooltip(ctx, title .. "\nDrag to reorder") end
  r.ImGui_PopID(ctx)
end

local function draw_home_view()
  local _, available_h = r.ImGui_GetContentRegionAvail(ctx)
  local status_h = app.settings.show_status and UI.info_line_height(ctx) or 0
  local content_h = math.max(40, (available_h or 240) - status_h)
  if r.ImGui_BeginChild(ctx, "##home_module_tiles", 0, content_h, 0) then
    local avail_w = r.ImGui_GetContentRegionAvail(ctx) or 1
    local gap = 10
    local min_card_w = 118
    local columns = math.max(1, math.floor((avail_w + gap) / (min_card_w + gap)))
    local card_w = math.max(1, math.floor((avail_w - gap * (columns - 1)) / columns))
    while columns > 1 and card_w < min_card_w do
      columns = columns - 1
      card_w = math.max(1, math.floor((avail_w - gap * (columns - 1)) / columns))
    end
    local card_h = 104
    for index, module in ipairs(app.modules) do
      draw_module_card(module, card_w, card_h)
      if index % columns ~= 0 then r.ImGui_SameLine(ctx, 0, gap) end
    end
    local pending = app.cache.pending_module_reorder
    if pending then
      app.cache.pending_module_reorder = nil
      move_module_to_target(pending.source, pending.target)
    end
    r.ImGui_EndChild(ctx)
  end
end

local function draw_top_bar()
  local module = get_active_module()
  local title = is_home_active() and "Home" or (module and (module.title or module.id) or "No modules")
  local avail_w = r.ImGui_GetContentRegionAvail(ctx)
  local dot_size = 14
  local dot_gap = 8
  r.ImGui_TextColored(ctx, Theme.colors.accent, SCRIPT_NAME .. " - " .. title)
  r.ImGui_SameLine(ctx, math.max(120, avail_w - (dot_size * 2) - dot_gap))
  local draw_list = r.ImGui_GetWindowDrawList(ctx)
  local settings_x, settings_y = r.ImGui_GetCursorScreenPos(ctx)
  local dot_y = settings_y + dot_size * 0.5
  r.ImGui_DrawList_AddCircleFilled(draw_list, settings_x + dot_size * 0.5, dot_y, dot_size * 0.5, 0xF2F2F2FF)
  r.ImGui_DrawList_AddCircle(draw_list, settings_x + dot_size * 0.5, dot_y, dot_size * 0.5, 0x8F9AA8FF, 16, 1)
  if r.ImGui_InvisibleButton(ctx, "##workbench_settings_dot", dot_size, dot_size) then
    r.ImGui_OpenPopup(ctx, "##workbench_settings_menu")
  end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Settings") end
  if r.ImGui_BeginPopup(ctx, "##workbench_settings_menu") then
    if r.ImGui_MenuItem(ctx, "Theme") then app.settings_panel = "theme" end
    if r.ImGui_MenuItem(ctx, "Preferences") then app.settings_panel = "preferences" end
    r.ImGui_EndPopup(ctx)
  end
  r.ImGui_SameLine(ctx, 0, dot_gap)
  local close_x, close_y = r.ImGui_GetCursorScreenPos(ctx)
  local close_y_mid = close_y + dot_size * 0.5
  r.ImGui_DrawList_AddCircleFilled(draw_list, close_x + dot_size * 0.5, close_y_mid, dot_size * 0.5, 0xF7768EFF)
  r.ImGui_DrawList_AddCircle(draw_list, close_x + dot_size * 0.5, close_y_mid, dot_size * 0.5, 0x3A1018FF, 16, 1)
  if r.ImGui_InvisibleButton(ctx, "##workbench_close_dot", dot_size, dot_size) then app.close_requested = true end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Close") end
  local home_size = r.ImGui_GetFrameHeight(ctx)
  local home_x, home_y = r.ImGui_GetCursorScreenPos(ctx)
  if r.ImGui_InvisibleButton(ctx, "##tk_workbench_home", home_size, home_size) then set_active_view(HOME_MODULE_ID) end
  local home_hovered = r.ImGui_IsItemHovered(ctx)
  local home_color = (is_home_active() or home_hovered) and Theme.colors.accent or Theme.colors.text_dim
  r.ImGui_DrawList_AddRectFilled(draw_list, home_x, home_y, home_x + home_size, home_y + home_size, is_home_active() and Theme.colors.accent_soft or Theme.colors.frame_bg, 4)
  r.ImGui_DrawList_AddRect(draw_list, home_x, home_y, home_x + home_size, home_y + home_size, home_hovered and Theme.colors.accent or Theme.colors.border, 4, 0, 1)
  draw_home_icon(draw_list, home_x + 3, home_y + 3, home_size - 6, home_color)
  if home_hovered then r.ImGui_SetTooltip(ctx, "Home") end
  r.ImGui_SameLine(ctx, 0, 6)
  local combo_flags = r.ImGui_ComboFlags_HeightLargest and r.ImGui_ComboFlags_HeightLargest() or 0
  r.ImGui_PushItemWidth(ctx, -1)
  if r.ImGui_BeginCombo(ctx, "##tk_workbench_module_select", title, combo_flags) then
    for _, candidate in ipairs(app.modules) do
      local selected = app.settings.active_module == candidate.id
      if r.ImGui_Selectable(ctx, candidate.title or candidate.id, selected) then
        set_active_view(candidate.id)
      end
      if selected then r.ImGui_SetItemDefaultFocus(ctx) end
    end
    r.ImGui_EndCombo(ctx)
  end
  r.ImGui_PopItemWidth(ctx)
  r.ImGui_Separator(ctx)
end

local function draw_theme_preview(colors)
  local draw_list = r.ImGui_GetWindowDrawList(ctx)
  local x, y = r.ImGui_GetCursorScreenPos(ctx)
  local size = 18
  local gap = 6
  local swatches = { colors.window_bg, colors.child_bg, colors.frame_bg, colors.accent, colors.warning, colors.danger }
  for index, color in ipairs(swatches) do
    local left = x + (index - 1) * (size + gap)
    r.ImGui_DrawList_AddRectFilled(draw_list, left, y, left + size, y + size, color, 3)
    r.ImGui_DrawList_AddRect(draw_list, left, y, left + size, y + size, Theme.colors.border, 3, 0, 1)
  end
  r.ImGui_Dummy(ctx, (#swatches * (size + gap)) - gap, size)
end

local function trim_text(value)
  return tostring(value or ""):match("^%s*(.-)%s*$") or ""
end

local function is_reserved_theme_name(name)
  local normalized = trim_text(name):lower()
  if normalized == "unsaved custom" then return true end
  if Theme.is_reserved_preset_name and Theme.is_reserved_preset_name(normalized) then return true end
  for preset_name in pairs(Theme.presets or {}) do
    if preset_name:lower() == normalized then return true end
  end
  return false
end

local function draw_theme_settings()
  if app.settings_panel == "theme" then
    app.cache.theme_settings_open = true
    app.settings_panel = nil
    if app.settings.theme_preset == Theme.reaper_preset_name then
      Theme.set_preset(Theme.reaper_preset_name, app.settings.custom_themes)
    end
  end
  if not app.cache.theme_settings_open then return end
  r.ImGui_SetNextWindowSize(ctx, 360, 500, r.ImGui_Cond_Appearing())
  local visible, open = r.ImGui_Begin(ctx, "Theme Settings##tk_workbench_theme_settings", true, r.ImGui_WindowFlags_NoTitleBar() | r.ImGui_WindowFlags_NoCollapse())
  app.cache.theme_settings_open = open
  if visible then
    r.ImGui_TextColored(ctx, Theme.colors.accent, "Theme Settings")
    r.ImGui_SameLine(ctx, 330)
    local draw_list = r.ImGui_GetWindowDrawList(ctx)
    local close_x, close_y = r.ImGui_GetCursorScreenPos(ctx)
    r.ImGui_DrawList_AddCircleFilled(draw_list, close_x + 7, close_y + 7, 7, 0xF7768EFF)
    r.ImGui_DrawList_AddCircle(draw_list, close_x + 7, close_y + 7, 7, 0x3A1018FF, 16, 1)
    if r.ImGui_InvisibleButton(ctx, "##theme_settings_close", 14, 14) then app.cache.theme_settings_open = false end
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Close") end
    r.ImGui_Separator(ctx)
    r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Preset")
    local current = app.settings.theme_preset or "Graphite"
    if r.ImGui_BeginCombo(ctx, "##theme_preset", current) then
      for _, name in ipairs(Theme.get_preset_names()) do
        local selected = current == name
        if r.ImGui_Selectable(ctx, name, selected) then
          app.settings.theme_preset = Theme.set_preset(name, app.settings.custom_themes)
          app.cache.saved_theme_preset = app.settings.theme_preset
          app.status = "Theme preset: " .. app.settings.theme_preset
          save_settings()
        end
        if selected then r.ImGui_SetItemDefaultFocus(ctx) end
      end
      if next(app.settings.custom_themes or {}) then r.ImGui_Separator(ctx) end
      local custom_names = {}
      for name in pairs(app.settings.custom_themes or {}) do custom_names[#custom_names + 1] = name end
      table.sort(custom_names)
      for _, name in ipairs(custom_names) do
        local selected = current == name
        if r.ImGui_Selectable(ctx, name .. "##custom_theme", selected) then
          app.settings.theme_preset = Theme.set_preset(name, app.settings.custom_themes)
          app.settings.custom_theme_name = name
          app.cache.saved_theme_preset = app.settings.theme_preset
          app.status = "Theme preset: " .. app.settings.theme_preset
          save_settings()
        end
        if selected then r.ImGui_SetItemDefaultFocus(ctx) end
      end
      r.ImGui_EndCombo(ctx)
    end
    if current == Theme.reaper_preset_name then
      if r.ImGui_Button(ctx, "Refresh REAPER Theme", 160, 24) then
        app.settings.theme_preset = Theme.set_preset(Theme.reaper_preset_name, app.settings.custom_themes)
        app.cache.saved_theme_preset = app.settings.theme_preset
        app.status = "REAPER theme colors refreshed"
        save_settings()
      end
      if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Read colors from the active REAPER theme") end
    end
    r.ImGui_Separator(ctx)
    r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Preview")
    draw_theme_preview(Theme.colors)
    r.ImGui_Spacing(ctx)
    if r.ImGui_BeginChild(ctx, "##theme_color_editor", 0, 190, 1) then
      local color_flags = r.ImGui_ColorEditFlags_NoInputs()
      for _, field in ipairs(theme_color_fields) do
        local changed, value = r.ImGui_ColorEdit4(ctx, field.label .. "##" .. field.key, Theme.colors[field.key], color_flags)
        if changed then
          Theme.colors[field.key] = value
          app.settings.theme_preset = "Unsaved Custom"
          Theme.set_colors(Theme.colors, app.settings.theme_preset)
        end
      end
      r.ImGui_EndChild(ctx)
    end
    r.ImGui_TextWrapped(ctx, "Theme changes are applied immediately. Custom themes load from the preset dropdown.")
    local name_changed, new_name = r.ImGui_InputTextWithHint(ctx, "##custom_theme_name", "Custom theme name", app.settings.custom_theme_name or "My Theme")
    if name_changed then app.settings.custom_theme_name = new_name end
    local theme_name = trim_text(app.settings.custom_theme_name or "")
    local theme_exists = app.settings.custom_themes and app.settings.custom_themes[theme_name] ~= nil
    local save_label = theme_exists and "Update Custom##save_custom_theme" or "Save Custom##save_custom_theme"
    if r.ImGui_Button(ctx, save_label, 110, 24) then
      if theme_name == "" then
        app.status = "Custom theme name required"
      elseif is_reserved_theme_name(theme_name) then
        app.status = "Reserved theme names cannot be overwritten"
      else
        local existed = app.settings.custom_themes and app.settings.custom_themes[theme_name] ~= nil
        app.settings.custom_theme_name = theme_name
        app.settings.custom_themes = app.settings.custom_themes or {}
        app.settings.custom_themes[theme_name] = Theme.copy_current_colors()
        app.settings.theme_preset = theme_name
        Theme.set_preset(theme_name, app.settings.custom_themes)
        app.cache.saved_theme_preset = app.settings.theme_preset
        app.status = (existed and "Updated custom theme: " or "Saved custom theme: ") .. theme_name
        save_settings()
      end
    end
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, theme_exists and "Update existing custom theme" or "Save current colors as custom theme") end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Delete Custom", 110, 24) then
      if theme_name == "" then
        app.status = "Custom theme name required"
      elseif is_reserved_theme_name(theme_name) then
        app.status = "Reserved themes cannot be deleted"
      elseif app.settings.custom_themes and app.settings.custom_themes[theme_name] then
        app.settings.custom_themes[theme_name] = nil
        app.settings.custom_theme_name = theme_name
        if app.settings.theme_preset == theme_name then
          app.settings.theme_preset = Theme.set_preset("Graphite", app.settings.custom_themes)
          app.cache.saved_theme_preset = app.settings.theme_preset
        end
        app.status = "Deleted custom theme: " .. theme_name
        save_settings()
      else
        app.status = "Custom theme not found: " .. theme_name
      end
    end
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Delete custom theme by name") end
    r.ImGui_Separator(ctx)
    if r.ImGui_Button(ctx, "Reset", 90, 24) then
      app.settings.theme_preset = Theme.set_preset("Graphite", app.settings.custom_themes)
      app.cache.saved_theme_preset = app.settings.theme_preset
      app.status = "Theme preset reset"
      save_settings()
    end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Close", 90, 24) then app.cache.theme_settings_open = false end
  end
  r.ImGui_End(ctx)
end

local function draw_preferences_settings()
  if app.settings_panel == "preferences" then
    app.cache.preferences_open = true
    app.settings_panel = nil
  end
  if not app.cache.preferences_open then return end
  r.ImGui_SetNextWindowSize(ctx, 300, 230, r.ImGui_Cond_Appearing())
  local visible, open = r.ImGui_Begin(ctx, "Preferences##tk_workbench_preferences", true, r.ImGui_WindowFlags_NoTitleBar() | r.ImGui_WindowFlags_NoCollapse())
  app.cache.preferences_open = open
  if visible then
    r.ImGui_TextColored(ctx, Theme.colors.accent, "Preferences")
    r.ImGui_SameLine(ctx, 270)
    local draw_list = r.ImGui_GetWindowDrawList(ctx)
    local close_x, close_y = r.ImGui_GetCursorScreenPos(ctx)
    r.ImGui_DrawList_AddCircleFilled(draw_list, close_x + 7, close_y + 7, 7, 0xF7768EFF)
    r.ImGui_DrawList_AddCircle(draw_list, close_x + 7, close_y + 7, 7, 0x3A1018FF, 16, 1)
    if r.ImGui_InvisibleButton(ctx, "##preferences_close", 14, 14) then app.cache.preferences_open = false end
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Close") end
    r.ImGui_Separator(ctx)
    local changed, value = r.ImGui_Checkbox(ctx, "Hide scrollbars", app.settings.hide_scrollbars == true)
    if changed then
      app.settings.hide_scrollbars = value
      app.status = value and "Scrollbars hidden" or "Scrollbars visible"
      save_settings()
    end
    r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Scroll wheel remains active.")
    r.ImGui_Separator(ctx)
    changed, value = r.ImGui_Checkbox(ctx, "Info box", app.settings.show_status ~= false)
    if changed then
      app.settings.show_status = value
      app.status = value and "Info box visible" or "Info box hidden"
      save_settings()
    end
    r.ImGui_Separator(ctx)
    changed, value = r.ImGui_Checkbox(ctx, "Tooltips", app.settings.tooltips_enabled ~= false)
    if changed then
      app.settings.tooltips_enabled = value
      app.cache.tooltip = nil
      app.status = value and "Tooltips enabled" or "Tooltips disabled"
      save_settings()
    end
    local delays = {
      { label = "Direct", value = 0 },
      { label = "0.5 seconds", value = 0.5 },
      { label = "1 second", value = 1.0 },
      { label = "2 seconds", value = 2.0 },
      { label = "3 seconds", value = 3.0 }
    }
    local current_delay = tonumber(app.settings.tooltip_delay) or 1.0
    local current_label = "1 second"
    for _, option in ipairs(delays) do
      if math.abs(current_delay - option.value) < 0.01 then current_label = option.label; break end
    end
    r.ImGui_PushItemWidth(ctx, 140)
    if r.ImGui_BeginCombo(ctx, "Tooltip delay", current_label) then
      for _, option in ipairs(delays) do
        local selected = math.abs(current_delay - option.value) < 0.01
        if r.ImGui_Selectable(ctx, option.label, selected) then
          app.settings.tooltip_delay = option.value
          app.cache.tooltip = nil
          app.status = option.value <= 0 and "Tooltips show directly" or ("Tooltip delay: " .. option.label)
          save_settings()
        end
        if selected then r.ImGui_SetItemDefaultFocus(ctx) end
      end
      r.ImGui_EndCombo(ctx)
    end
    r.ImGui_PopItemWidth(ctx)
  end
  r.ImGui_End(ctx)
end

local function push_workspace_style()
  local vars = 0
  if app.settings.hide_scrollbars and r.ImGui_StyleVar_ScrollbarSize then
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ScrollbarSize(), 0)
    vars = vars + 1
  end
  return vars
end

local function pop_workspace_style(vars)
  if vars and vars > 0 then r.ImGui_PopStyleVar(ctx, vars) end
end

local function draw_module_error(module, err)
  local width = r.ImGui_GetContentRegionAvail(ctx)
  local x, y = r.ImGui_GetCursorScreenPos(ctx)
  local draw_list = r.ImGui_GetWindowDrawList(ctx)
  local height = 72
  r.ImGui_DrawList_AddRectFilled(draw_list, x, y, x + width, y + height, Theme.colors.frame_bg, 5)
  r.ImGui_DrawList_AddRect(draw_list, x, y, x + width, y + height, Theme.colors.warning, 5, 0, 1)
  r.ImGui_SetCursorScreenPos(ctx, x + 10, y + 8)
  r.ImGui_TextColored(ctx, Theme.colors.warning, tostring(module and (module.title or module.id) or "Module") .. " error")
  r.ImGui_SetCursorScreenPos(ctx, x + 10, y + 30)
  r.ImGui_PushTextWrapPos(ctx, x + width - 10)
  r.ImGui_TextColored(ctx, Theme.colors.text_dim, tostring(err))
  r.ImGui_PopTextWrapPos(ctx)
  r.ImGui_SetCursorScreenPos(ctx, x, y + height + 6)
end

local function draw_module_canvas()
  if is_home_active() then
    draw_home_view()
    return
  end
  local module = get_active_module()
  if module then
    if module.draw then
      local ok, err = pcall(module.draw, app)
      if ok then
        app.module_errors[module.id .. ".draw"] = nil
      else
        app.module_errors[module.id .. ".draw"] = tostring(err)
        draw_module_error(module, err)
      end
    end
  else
    r.ImGui_TextColored(ctx, Theme.colors.warning, "No modules loaded")
  end
end

local function draw_status_bar()
  local selection = app.selection or {}
  local captured = UI.get_captured_info_line(app)
  local text = captured and tostring(captured.text or "") or (app.status or "Ready")
  local captured_options = captured and captured.options or {}
  local details = ""
  local severity = captured_options.severity or "info"
  if captured_options.details then details = tostring(captured_options.details) end
  if selection.track and selection.track.name then text = text .. " | Track: " .. selection.track.name end
  if selection.item and selection.item.take_name then text = text .. " | Take: " .. selection.item.take_name end
  for key, err in pairs(app.module_errors) do
    local module_id = tostring(key):match("^(.-)%.") or tostring(key)
    local module = app.modules_by_id[module_id]
    text = tostring(module and (module.title or module.id) or module_id) .. " error"
    details = tostring(err)
    severity = "error"
    break
  end
  UI.draw_info_line(ctx, text, { severity = severity, details = details, force = true })
end

local function update_modules()
  for _, module in ipairs(app.modules) do
    if module.update then
      local ok, err = pcall(module.update, app)
      if ok then app.module_errors[module.id .. ".update"] = nil else app.module_errors[module.id .. ".update"] = tostring(err) end
    end
  end
end

local function shutdown()
  if app.cache.shutdown_done then return end
  app.cache.shutdown_done = true
  r.SetExtState(MODULE_ACTION_EXT_SECTION, MODULE_ACTION_RUNNING_KEY, "false", false)
  r.SetExtState(MODULE_ACTION_EXT_SECTION, MODULE_ACTION_HEARTBEAT_KEY, "", false)
  for _, module in ipairs(app.modules) do
    if module.shutdown then pcall(module.shutdown, app) end
  end
  if app.settings.theme_preset == "Unsaved Custom" then
    app.settings.theme_preset = app.cache.saved_theme_preset or "Graphite"
  end
  save_settings()
end

if r.atexit then r.atexit(shutdown) end

local function draw_shell()
  draw_top_bar()
  local status_h = app.settings.show_status and UI.info_line_height(ctx, true) or 0
  local _, available_h = r.ImGui_GetContentRegionAvail(ctx)
  local canvas_h = math.max(40, (available_h or 240) - status_h)
  local canvas_flags = 0
  if r.ImGui_WindowFlags_NoScrollbar then canvas_flags = canvas_flags | r.ImGui_WindowFlags_NoScrollbar() end
  if r.ImGui_WindowFlags_NoScrollWithMouse then canvas_flags = canvas_flags | r.ImGui_WindowFlags_NoScrollWithMouse() end
  app.cache.captured_info_line = nil
  if r.ImGui_BeginChild(ctx, "##workbench_module_canvas", 0, canvas_h, 0, canvas_flags) then
    UI.begin_info_line_capture(app)
    draw_module_canvas()
    UI.end_info_line_capture(app)
    r.ImGui_EndChild(ctx)
  end
  if app.settings.show_status then draw_status_bar() end
end

local function loop()
  if r.ImGui_ValidatePtr and not r.ImGui_ValidatePtr(ctx, "ImGui_Context*") then
    ctx = r.ImGui_CreateContext(SCRIPT_NAME)
    app.ctx = ctx
    app.cache.tooltip = nil
  end
  app.selection = Selection.scan()
  update_modules()
  r.SetExtState(MODULE_ACTION_EXT_SECTION, MODULE_ACTION_RUNNING_KEY, "true", false)
  r.SetExtState(MODULE_ACTION_EXT_SECTION, MODULE_ACTION_HEARTBEAT_KEY, tostring(r.time_precise and r.time_precise() or os.clock()), false)
  process_module_action_commands()
  UI.begin_tooltip_frame(app)
  r.ImGui_SetNextWindowSize(ctx, app.settings.window_width or 430, app.settings.window_height or 760, r.ImGui_Cond_FirstUseEver())
  if (app.settings.theme_preset or "Graphite") ~= Theme.current_preset then
    app.settings.theme_preset = Theme.set_preset(app.settings.theme_preset or "Graphite", app.settings.custom_themes)
  end
  local theme_stack = Theme.push(ctx)
  local workspace_style_vars = push_workspace_style()
  local window_flags = r.ImGui_WindowFlags_NoTitleBar() | r.ImGui_WindowFlags_NoScrollbar() | r.ImGui_WindowFlags_NoScrollWithMouse()
  local visible, open = r.ImGui_Begin(ctx, SCRIPT_NAME, true, window_flags)
  if visible then
    app.cache.window_x, app.cache.window_y = r.ImGui_GetWindowPos(ctx)
    app.cache.window_w, app.cache.window_h = r.ImGui_GetWindowSize(ctx)
    draw_shell()
    r.ImGui_End(ctx)
  end
  draw_theme_settings()
  draw_preferences_settings()
  UI.end_tooltip_frame(app)
  pop_workspace_style(workspace_style_vars)
  Theme.pop(ctx, theme_stack)
  if open and not app.close_requested then
    r.defer(loop)
  else
    shutdown()
  end
end

ModuleLoader.load(app, module_names)
apply_module_order()
if app.settings.active_module ~= HOME_MODULE_ID and not app.modules_by_id[app.settings.active_module] and app.modules[1] then
  app.settings.active_module = app.modules[1].id
  save_settings()
end

r.defer(loop)