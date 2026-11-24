-- TK Theme Bit - the AUDIO EDITOR icon: opens or closes an audio editor panel, as Bitwig's
-- audio editor at the bottom. What it opens is chosen in the settings (Transport > Audio
-- editor opens): TK Bit Clip Edit, this theme's own editor (the default); SneakPeak
-- (b451c's waveform item editor, a REAPER extension from its own ReaPack repository); or
-- any other action. Nothing found: a message says what to do. The icon is orange while the
-- panel is open; the view icons' background loop keeps that in step.

local r = reaper
local dir = ({r.get_action_context()})[2]:match("^(.*)[\\/]")
local V = dofile(dir .. "/TK_Theme_Bit_View.lua")

local cmd = V.audio_command()
local choice = V.audio_choice()
if cmd then
  -- SneakPeak's own action only opens it: when its window is up, close that instead
  if not (choice == "sneakpeak" and V.close_sneakpeak()) then
    r.Main_OnCommand(cmd, 0)        -- opens it, or (an action that toggles) closes it
  end
  V.watch()
elseif choice == "other" then
  r.ShowMessageBox("The audio editor icon is set to the action \"" .. V.audio_action() .. "\", which REAPER doesn't "
    .. "know (any more).\n\nChoose another one in TK Theme Bit's settings (Transport > Audio editor opens).", "TK Theme Bit", 0)
elseif choice == "sneakpeak" then
  r.ShowMessageBox("The audio editor icon opens SneakPeak, which isn't installed.\n\n"
    .. "Get it with ReaPack: Extensions > ReaPack > Import repositories, add\n"
    .. "https://raw.githubusercontent.com/b451c/SneakPeak/main/index.xml\n"
    .. "then install SneakPeak and restart REAPER. Or choose Clip Edit in TK Theme Bit's settings "
    .. "(Transport > Audio editor opens).", "TK Theme Bit", 0)
else
  r.ShowMessageBox("The audio editor icon opens TK Bit Clip Edit, which REAPER doesn't list as an action.\n\n"
    .. "Synchronize TK Theme Bit in ReaPack (Extensions > ReaPack > Synchronize packages), which registers it.",
    "TK Theme Bit", 0)
end
