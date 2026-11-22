-- TK Theme Bit - views, as Bitwig's ARRANGE / MIX / EDIT keys (library for the three
-- TK_Theme_Bit_View_*.lua actions, which the keys in the transport call).
--
--   ARRANGE  the arrange alone: the mixer and the MIDI editor are closed
--   MIX      the mixer shown, the MIDI editor closed
--   EDIT     the selected MIDI item in the MIDI editor, the mixer closed
--
-- The theme can't see which view is up, so a small background loop passes it on as the
-- theme parameter bitView (0 / 1 / 2): the MIDI editor open = EDIT, else the mixer shown
-- = MIX, else ARRANGE. So the lit key also follows when you open or close the mixer or
-- the MIDI editor yourself. The loop starts with the first click on a view key; one loop
-- at a time (a newer one takes over through an ExtState token).

local r = reaper
local V = {}
local MIXER = 40078                 -- View: Toggle mixer visible
local OPEN_MIDI = 40153             -- Item: Open in built-in MIDI editor
local PARAM, EXT = "bitView", "TK Theme Bit"

local function mixer_shown() return r.GetToggleCommandState(MIXER) == 1 end

-- Saxmand's FX Modulator Linking (the DEVICES key): found by its file name in REAPER's
-- action list, so its id doesn't matter. While it runs, it sets its own toggle state to 1.
local SAXMAND = "Saxmand_FX Modulator Linking.lua"
local sax_cmd

function V.saxmand_command()
  if sax_cmd == nil then
    sax_cmd = false
    local f = io.open(r.GetResourcePath() .. "/reaper-kb.ini", "rb")
    if f then
      local text = f:read("a")
      f:close()
      for line in text:gmatch("[^\r\n]+") do
        local id = line:match("^SCR %d+ %d+ (%S+) ")
        if id and line:find(SAXMAND, 1, true) then
          local cmd = r.NamedCommandLookup("_" .. id)
          if cmd ~= 0 then sax_cmd = cmd break end
        end
      end
    end
  end
  return sax_cmd or nil
end

function V.devices_open()
  local cmd = V.saxmand_command()
  return cmd ~= nil and r.GetToggleCommandState(cmd) == 1
end

-- a view key closes the device panel: running its action again ends it (REAPER may ask
-- once whether to terminate it; "Remember my answer" keeps that quiet afterwards)
local function close_devices()
  if V.devices_open() then r.Main_OnCommand(V.saxmand_command(), 0) end
end

local function close_midi_editor()
  local ed = r.MIDIEditor_GetActive()
  if ed then r.MIDIEditor_OnCommand(ed, 2) end     -- File: Close window
end

local function selected_midi_item()
  for i = 0, r.CountSelectedMediaItems(0) - 1 do
    local take = r.GetActiveTake(r.GetSelectedMediaItem(0, i))
    if take and r.TakeIsMIDI(take) then return true end
  end
  return false
end

function V.current()
  if r.MIDIEditor_GetActive() then return 2 end
  if mixer_shown() then return 1 end
  return 0
end

local function set_param(name, value)
  local i = 0
  while true do
    local n, _, v = r.ThemeLayout_GetParameter(i)
    if not n then return false end
    if n == name then
      if v ~= value then
        r.ThemeLayout_SetParameter(i, value, false)
        return true
      end
      return false
    end
    i = i + 1
  end
end

-- the lit keys: the view (bitView) and whether the device panel is open (bitDevOn)
function V.show(view)
  local a = set_param(PARAM, view)
  local b = set_param("bitDevOn", V.devices_open() and 1 or 0)
  if a or b then r.ThemeLayout_RefreshAll() end
end

function V.switch(view)
  close_devices()
  if view == 0 then
    close_midi_editor()
    if mixer_shown() then r.Main_OnCommand(MIXER, 0) end
  elseif view == 1 then
    close_midi_editor()
    if not mixer_shown() then r.Main_OnCommand(MIXER, 0) end
  else
    if not r.MIDIEditor_GetActive() then
      if selected_midi_item() then
        r.Main_OnCommand(OPEN_MIDI, 0)
      else
        local x, y = r.GetMousePosition()
        r.TrackCtl_SetToolTip("EDIT: select a MIDI item first", x + 10, y + 10, true)
        return
      end
    end
    if mixer_shown() then r.Main_OnCommand(MIXER, 0) end
  end
  V.show(V.current())
end

-- the background loop: keeps bitView in step, every few frames
function V.watch()
  -- clicking the key again ends this copy and runs the new one, without REAPER's dialog
  if r.set_action_options then r.set_action_options(3) end
  local token = tostring(r.time_precise())
  r.SetExtState(EXT, "view_watch", token, false)
  local n = 0
  local function loop()
    if r.GetExtState(EXT, "view_watch") ~= token then return end   -- a newer loop took over
    n = n + 1
    if n % 6 == 0 then V.show(V.current()) end
    r.defer(loop)
  end
  r.defer(loop)
end

function V.run(view)
  V.switch(view)
  V.watch()
end

return V
