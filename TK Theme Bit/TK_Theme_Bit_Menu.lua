-- TK Theme Bit - shared popup menu for the transport's FILE / ADD / EDIT buttons.
-- Each item is a REAPER main-section command ID; its label comes from REAPER itself
-- (kbd_getTextFromCmd), so a menu entry always says what it really does. A 0 is a separator.

local M = {}

local function label(id)
  local name = reaper.kbd_getTextFromCmd(id, 0) or ""
  -- "File: Save project" -> "Save project"
  name = name:gsub("^[^:]+:%s*", "")
  -- characters gfx.showmenu treats specially
  name = name:gsub("[|#!<>&]", "")
  if name == "" then name = "Command " .. id end
  return name
end

function M.show(items)
  local parts, ids = {}, {}
  for _, id in ipairs(items) do
    if id == 0 then
      parts[#parts + 1] = ""
    else
      parts[#parts + 1] = label(id)
      ids[#ids + 1] = id
    end
  end
  local x, y = reaper.GetMousePosition()
  gfx.init("TK Theme Bit menu", 0, 0, 0, x, y)
  gfx.x, gfx.y = 0, 0
  local choice = gfx.showmenu(table.concat(parts, "|"))
  gfx.quit()
  if choice > 0 and ids[choice] then
    reaper.Main_OnCommand(ids[choice], 0)
  end
end

return M
