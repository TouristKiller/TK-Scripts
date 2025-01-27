-- @description TK_time selection loop color configuration
-- @version 1.0
-- @author TouristKiller

function GetColors()
  local loop_color = tonumber(reaper.GetExtState("TK_time selection loop color", "loop_color")) or 0x0000FF
  local default_color = tonumber(reaper.GetExtState("TK_time selection loop color", "default_color")) or 0xFFFFFF
  return loop_color, default_color
end

function SaveColors(loop_color, default_color)
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

SetupColors()
