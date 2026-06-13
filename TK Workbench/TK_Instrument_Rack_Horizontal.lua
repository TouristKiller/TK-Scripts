-- @description TK Instrument Rack (Horizontal)
-- @author TouristKiller
-- @version 0.1.0
-- @changelog:
--   + Initial release: standalone horizontal Instrument Rack launcher reusing the Workbench module

local r = reaper

local SCRIPT_NAME = "TK Instrument Rack (Horizontal)"
if not r.ImGui_CreateContext then
  r.ShowMessageBox("ReaImGui is required for " .. SCRIPT_NAME .. ".", SCRIPT_NAME, 0)
  return
end

local script_path = debug.getinfo(1, "S").source:match("@?(.*[\\/])") or ""
local sep = package.config:sub(1, 1)
package.path = script_path .. "?.lua;" .. script_path .. "?" .. sep .. "init.lua;" .. package.path

local Settings = require("core.settings")
local Theme = require("core.theme")
local UIScale = require("core.ui_scale")
local json = require("core.json")
local InstrumentRack = require("modules.instrument_rack")

local config_path = script_path .. "config_instrument_rack_horizontal.json"
local workbench_config_path = script_path .. (rawget(_G, "TK_WORKBENCH_CONFIG_NAME") or "config.json")
local settings = Settings.load(config_path)

local function read_workbench_raw()
  local file = io.open(workbench_config_path, "r")
  if not file then return nil end
  local content = file:read("*a")
  file:close()
  if not content or content == "" then return nil end
  return content
end

local workbench_last_raw = nil

local function sync_workbench_settings(force)
  local content = read_workbench_raw()
  if not content then return end
  if not force and content == workbench_last_raw then return end
  workbench_last_raw = content
  local ok, wb = pcall(json.decode, content)
  if not ok or type(wb) ~= "table" then return end
  if wb.theme_preset ~= nil then settings.theme_preset = wb.theme_preset end
  if wb.custom_themes ~= nil then settings.custom_themes = wb.custom_themes end
  if wb.ui_scale ~= nil then settings.ui_scale = wb.ui_scale end
end

sync_workbench_settings(true)
local workbench_sync_next = 0

settings.instrument_rack = settings.instrument_rack or {}
if settings.instrument_rack.orientation == nil then
  settings.instrument_rack.orientation = "horizontal"
end

UIScale.set(settings.ui_scale)

local ctx = r.ImGui_CreateContext(SCRIPT_NAME)

local app = {
  ctx = ctx,
  script_name = SCRIPT_NAME,
  script_path = script_path,
  config_path = config_path,
  settings = settings,
  selection = {},
  modules_by_id = {},
  cache = {},
  status = "Ready",
  close_requested = false
}

local function save_settings()
  Settings.save(config_path, app.settings)
end
app.save_settings = save_settings

local function get_scaled_font()
  local scale = UIScale.set(app.settings.ui_scale or 1.0)
  if math.abs(scale - 1.0) < 0.01 then return nil end
  if not r.ImGui_CreateFont then return nil end
  app.cache.ui_fonts = app.cache.ui_fonts or {}
  if app.cache.ui_font_ctx ~= ctx then
    app.cache.ui_fonts = {}
    app.cache.ui_font_ctx = ctx
  end
  local font_size = math.max(10, math.floor(13 * scale + 0.5))
  local key = tostring(font_size)
  if app.cache.ui_fonts[key] then return app.cache.ui_fonts[key], font_size end
  local ok, font = pcall(r.ImGui_CreateFont, "sans-serif", font_size)
  if not ok or not font then return nil end
  if r.ImGui_Attach then pcall(r.ImGui_Attach, ctx, font) end
  app.cache.ui_fonts[key] = font
  return font, font_size
end

local function push_scaled_font()
  local font, font_size = get_scaled_font()
  if not font or not r.ImGui_PushFont then return false end
  return pcall(r.ImGui_PushFont, ctx, font, font_size) == true
end

local function pop_scaled_font(pushed)
  if pushed and r.ImGui_PopFont then pcall(r.ImGui_PopFont, ctx) end
end

if InstrumentRack.init then
  local ok, err = pcall(InstrumentRack.init, app)
  if not ok then r.ShowConsoleMsg("Instrument Rack init error: " .. tostring(err) .. "\n") end
end

local function loop()
  if r.ImGui_ValidatePtr and not r.ImGui_ValidatePtr(ctx, "ImGui_Context*") then
    ctx = r.ImGui_CreateContext(SCRIPT_NAME)
    app.ctx = ctx
    app.cache.ui_fonts = {}
    app.cache.ui_font_ctx = nil
  end
  local now = r.time_precise()
  if now >= workbench_sync_next then
    workbench_sync_next = now + 0.5
    sync_workbench_settings()
  end
  UIScale.set(app.settings.ui_scale or 1.0)
  if (app.settings.theme_preset or "Graphite") ~= Theme.current_preset then
    app.settings.theme_preset = Theme.set_preset(app.settings.theme_preset or "Graphite", app.settings.custom_themes)
  end
  local scaled_font_pushed = push_scaled_font()
  local theme_stack = Theme.push(ctx)
  r.ImGui_SetNextWindowSize(ctx, app.settings.rack_window_width or 760, app.settings.rack_window_height or 320, r.ImGui_Cond_FirstUseEver())
  local window_flags = r.ImGui_WindowFlags_NoTitleBar() | r.ImGui_WindowFlags_NoScrollbar() | r.ImGui_WindowFlags_NoScrollWithMouse()
  local visible, open = r.ImGui_Begin(ctx, SCRIPT_NAME, true, window_flags)
  if visible then
    local ok, err = pcall(InstrumentRack.draw, app)
    if not ok then r.ImGui_TextColored(ctx, Theme.colors.danger, "Draw error: " .. tostring(err)) end
    r.ImGui_End(ctx)
  end
  Theme.pop(ctx, theme_stack)
  pop_scaled_font(scaled_font_pushed)
  if open and not app.close_requested then
    r.defer(loop)
  else
    if InstrumentRack.shutdown then pcall(InstrumentRack.shutdown, app) end
    save_settings()
  end
end

r.defer(loop)
