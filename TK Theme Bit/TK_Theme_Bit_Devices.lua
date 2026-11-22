-- TK Theme Bit - the DEVICES key: opens or closes Saxmand's "FX Modulator Linking", a
-- device panel in the spirit of Bitwig's. It is Saxmand's own script, installed from his
-- ReaPack repository; this only finds it in REAPER's action list (TK_Theme_Bit_View.lua,
-- by its file name) and runs it. Not installed: a message says where to get it.
-- The key is orange while the panel is open; the view keys' background loop keeps that
-- in step, and is started here too.

local r = reaper
local dir = ({r.get_action_context()})[2]:match("^(.*)[\\/]")
local V = dofile(dir .. "/TK_Theme_Bit_View.lua")

local cmd = V.saxmand_command()
if cmd then
  r.Main_OnCommand(cmd, 0)          -- opens it, or (when open) ends it
  V.watch()
else
  r.ShowMessageBox("The DEVICES key opens Saxmand's \"FX Modulator Linking\", which isn't installed.\n\n"
    .. "Get it with ReaPack: add Saxmand's repository (Extensions > ReaPack > Import repositories), "
    .. "then install \"FX Modulator Linking\".\n\n"
    .. "You can hide this key in TK Theme Bit's settings (Transport > Devices key).",
    "TK Theme Bit", 0)
end
