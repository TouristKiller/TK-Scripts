-- @description TK Kit Maker
-- @author TouristKiller
-- @version 0.1.0
-- @changelog:
--   + Initial release
--   + Folder Explosion (milestone 1): source folder -> N consecutive slots, Detonate
--   + Kit Builder (milestone 2): pools with alias, slot table editor, save/load presets
--   + Sample lock, use-up + reshuffle, Quick Preview 128-slot layout, used-samples log (milestone 3)
--   + Sequencer: sample-accurate JSFX audio-thread timing engine (rock-solid drum timing)

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
