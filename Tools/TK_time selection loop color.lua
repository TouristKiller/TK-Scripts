-- @description TK_time selection loop color
-- @version 1.2
-- @author TouristKiller
-- @about
--   # if script is enabled, you can switch the time selection and arrange within that time selection color when the loop function is turned on or off.
-- @changelog
--    Toggle button state added
--    ExtState color configuration added

local function GetColors()
  local loop_color = tonumber(reaper.GetExtState("TK_time selection loop color", "loop_color")) or 0x0000FF
  local default_color = tonumber(reaper.GetExtState("TK_time selection loop color", "default_color")) or 0xFFFFFF
  return loop_color, default_color
end

local function SaveColors(loop_color, default_color)
  reaper.SetExtState("TK_time selection loop color", "loop_color", string.format("0x%06X", loop_color), true)
  reaper.SetExtState("TK_time selection loop color", "default_color", string.format("0x%06X", default_color), true)
end

function SetupColors()
  local loop_color, default_color = GetColors()
  local ret, user_input = reaper.GetUserInputs("Color Settings", 2,
      "Loop color (hex, e.g. 0000FF),Default color (hex, e.g. FFFFFF)",
      string.format("%06X,%06X", loop_color, default_color))
  if ret then
      local loop_col, default_col = user_input:match("([^,]+),([^,]+)")
      if loop_col and default_col then
          SaveColors(tonumber(loop_col, 16), tonumber(default_col, 16))
      end
  end
end

function SetButtonState(set)
  local is_new_value, filename, sec, cmd, mode, resolution, val = reaper.get_action_context()
  reaper.SetToggleCommandState(sec, cmd, set or 0)
  reaper.RefreshToolbar2(sec, cmd)
end

local last_loop_state = -1
function ChangeTimeSelectionColor()
  local is_loop_enabled = reaper.GetSetRepeat(-1)
  if is_loop_enabled ~= last_loop_state then
      local loop_color, default_color = GetColors() 
      if is_loop_enabled == 1 then
          reaper.SetThemeColor("col_tl_bgsel", loop_color, 0)
          reaper.SetThemeColor("col_tl_bgsel2", loop_color, 0)
      else
          reaper.SetThemeColor("col_tl_bgsel", default_color, 0)
          reaper.SetThemeColor("col_tl_bgsel2", default_color, 0)
      end
      reaper.UpdateArrange()
      reaper.UpdateTimeline()
      last_loop_state = is_loop_enabled
  end
end

function Main()
  ChangeTimeSelectionColor()
  reaper.defer(Main)
end

if reaper.HasExtState("TK_time selection loop color", "loop_color") == false then
  SetupColors()
end

function SetupContextMenu()
  local menu = "Color Settings"
  local ret = reaper.ShowMessageBox("Would you like to adjust the colors?", "TK Time Selection Loop Color", 4)
  if ret == 6 then -- Yes
      SetupColors()
  end
end
if reaper.GetExtState("TK_time selection loop color", "CALL_SETUP") == "1" then
  reaper.SetExtState("TK_time selection loop color", "CALL_SETUP", "0", false)
  SetupContextMenu()
else
  SetButtonState(1)
  Main()
  reaper.atexit(SetButtonState)
end
