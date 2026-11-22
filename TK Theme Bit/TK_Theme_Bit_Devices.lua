-- TK Theme Bit - the DEVICES key: starts Saxmand's "FX Modulator Linking", a device panel
-- in the spirit of Bitwig's. It is Saxmand's own script, installed from his ReaPack
-- repository; this only finds it in REAPER's action list (by its file name, so its
-- action id doesn't matter) and runs it. Not installed: a message says where to get it.

local r = reaper
local FILE = "Saxmand_FX Modulator Linking.lua"

local function find_command()
  local f = io.open(r.GetResourcePath() .. "/reaper-kb.ini", "rb")
  if not f then return nil end
  local text = f:read("a")
  f:close()
  for line in text:gmatch("[^\r\n]+") do
    local id = line:match("^SCR %d+ %d+ (%S+) ")
    if id and line:find(FILE, 1, true) then
      local cmd = r.NamedCommandLookup("_" .. id)
      if cmd ~= 0 then return cmd end
    end
  end
  return nil
end

local cmd = find_command()
if cmd then
  r.Main_OnCommand(cmd, 0)
else
  r.ShowMessageBox("The DEVICES key opens Saxmand's \"FX Modulator Linking\", which isn't installed.\n\n"
    .. "Get it with ReaPack: add Saxmand's repository (Extensions > ReaPack > Import repositories), "
    .. "then install \"FX Modulator Linking\".\n\n"
    .. "You can hide this key in TK Theme Bit's settings (Transport > Devices key).",
    "TK Theme Bit", 0)
end
