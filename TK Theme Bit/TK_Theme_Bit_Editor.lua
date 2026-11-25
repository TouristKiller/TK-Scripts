-- TK Theme Bit - EDITOR: Bitwig's E key. Opens the editor for the selected clip, or closes
-- it again: a MIDI item opens the MIDI editor (as the MIDI editor icon), an audio item the
-- audio editor (as the audio editor icon: TK Bit Clip Edit, SneakPeak or your own choice).
-- Nothing selected: closes whichever editor is open.

local r = reaper
local dir = ({r.get_action_context()})[2]:match("^(.*)[\\/]")
local V = dofile(dir .. "/TK_Theme_Bit_View.lua")

local function selected_kind()
  local item = r.GetSelectedMediaItem(0, 0)
  local take = item and r.GetActiveTake(item)
  if not take then return nil end
  return r.TakeIsMIDI(take) and "midi" or "audio"
end

local function audio_editor()
  dofile(dir .. "/TK_Theme_Bit_Audio.lua")       -- opens it, or closes it when open
end

local kind = selected_kind()
if kind == "midi" then
  V.run(2)
elseif kind == "audio" then
  if V.current() == 2 then V.run(0) end          -- the MIDI editor makes way
  audio_editor()
elseif V.current() == 2 then
  V.run(0)
elseif V.audio_open() then
  audio_editor()
else
  local x, y = r.GetMousePosition()
  r.TrackCtl_SetToolTip("Editor: select a clip first", x + 10, y + 10, true)
end
