-- @description TK Kit Maker
-- @author TouristKiller
-- @version 0.1.1
-- @changelog:
--   + Sequencer UI polish: lane row order aangepast (1x, RS5k, Copy, Paste, Clear)
--   + Sequencer UI polish: full-width separator met extra spacing boven Auto Name
--   + Sequencer UI polish: huidige racknaam zichtbaar naast Auto Name
--   + Fix: Auto Name separator drawing (geldige kleur en drawlist)

local r = reaper

local SCRIPT_NAME = "TK Kit Maker"
if not r.ImGui_CreateContext then
  r.ShowMessageBox("ReaImGui is required for TK Kit Maker.\nInstall 'ReaImGui: ReaScript binding for Dear ImGui' via ReaPack.", SCRIPT_NAME, 0)
  return
end

local script_path = debug.getinfo(1, "S").source:match("@?(.*[\\/])") or ""
local sep = package.config:sub(1, 1)
package.path = script_path .. "?.lua;" .. script_path .. "?" .. sep .. "init.lua;" .. package.path

math.randomseed(os.time() + math.floor((r.time_precise and r.time_precise() or os.clock()) * 1000))

local MainWindow = require("ui.main_window")

local ctx = r.ImGui_CreateContext(SCRIPT_NAME)

local app = {
  ctx = ctx,
  script_name = SCRIPT_NAME,
  script_path = script_path,
}

MainWindow.init(app)

local function loop()
  local ok, open = pcall(MainWindow.frame, app)
  if not ok then
    r.ShowConsoleMsg(SCRIPT_NAME .. " error: " .. tostring(open) .. "\n")
    return
  end
  if open then
    r.defer(loop)
  end
end

r.defer(loop)
