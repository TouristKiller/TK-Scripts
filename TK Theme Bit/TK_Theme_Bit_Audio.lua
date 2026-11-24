-- TK Theme Bit - the AUDIO EDITOR icon: opens or closes an audio editor panel, as Bitwig's
-- audio editor at the bottom. By default that is SneakPeak (b451c's waveform item editor,
-- a REAPER extension installed through ReaPack); in the settings (Transport > Audio
-- editor) any other action can be chosen instead, TK Audio Editor for one. Nothing found:
-- a message says what to do. The icon is orange while the panel is open (when the action
-- reports its toggle state); the view icons' background loop keeps that in step.

local r = reaper
local dir = ({r.get_action_context()})[2]:match("^(.*)[\\/]")
local V = dofile(dir .. "/TK_Theme_Bit_View.lua")

local cmd = V.audio_command()
if cmd then
  -- SneakPeak's own action only opens it: when its window is up, close that instead
  if not (V.audio_action() == "" and V.close_sneakpeak()) then
    r.Main_OnCommand(cmd, 0)        -- opens it, or (an action that toggles) closes it
  end
  V.watch()
elseif V.audio_action() ~= "" then
  r.ShowMessageBox("The audio editor icon is set to the action \"" .. V.audio_action() .. "\", which REAPER doesn't "
    .. "know (any more).\n\nChoose another one in TK Theme Bit's settings (Transport > Audio editor).", "TK Theme Bit", 0)
else
  r.ShowMessageBox("The audio editor icon opens SneakPeak, which isn't installed.\n\n"
    .. "Get it with ReaPack: Extensions > ReaPack > Import repositories, add\n"
    .. "https://raw.githubusercontent.com/b451c/SneakPeak/main/index.xml\n"
    .. "then install SneakPeak and restart REAPER. Or choose any other action for the icon in TK Theme Bit's "
    .. "settings (Transport > Audio editor).", "TK Theme Bit", 0)
end
