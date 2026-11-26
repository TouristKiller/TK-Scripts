-- TK Theme Bit - the DEVICES key: opens or closes a device panel. By default that is TK Bit
-- Devices (TK_Theme_Bit_Devices_Panel.lua, this theme's own); in the settings (Transport >
-- Devices key opens) Saxmand's "FX Modulator Linking" or any other action can be chosen
-- instead. Nothing found: a message says what to do.
-- The key is orange while the panel is open (when the action reports its toggle state);
-- the view keys' background loop keeps that in step, and is started here too.

local r = reaper
local dir = ({r.get_action_context()})[2]:match("^(.*)[\\/]")
local V = dofile(dir .. "/TK_Theme_Bit_View.lua")

local cmd = V.devices_command()
if cmd then
  r.Main_OnCommand(cmd, 0)          -- opens it, or (when open) ends it
  V.watch()
elseif V.devices_action() == "saxmand" then
  r.ShowMessageBox("The DEVICES key is set to Saxmand's \"FX Modulator Linking\", which isn't installed.\n\n"
    .. "Get it with ReaPack (Saxmand's repository), or choose TK Devices again in TK Theme Bit's settings "
    .. "(Transport > Devices key opens).", "TK Theme Bit", 0)
elseif V.devices_action() ~= "" then
  r.ShowMessageBox("The DEVICES key is set to the action \"" .. V.devices_action() .. "\", which REAPER doesn't know "
    .. "(any more).\n\nChoose another one in TK Theme Bit's settings (Transport > Devices key).", "TK Theme Bit", 0)
else
  r.ShowMessageBox("The DEVICES key opens TK Bit Devices (TK_Theme_Bit_Devices_Panel.lua), which REAPER "
    .. "doesn't know as an action.\n\nSynchronize TK Theme Bit in ReaPack (Extensions > ReaPack > "
    .. "Synchronize packages), or load the script in the Actions list. Or choose another action for the key "
    .. "in TK Theme Bit's settings (Transport > Devices key opens).", "TK Theme Bit", 0)
end
