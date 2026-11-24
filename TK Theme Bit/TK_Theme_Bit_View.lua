-- TK Theme Bit - views (library for the three TK_Theme_Bit_View_*.lua actions). The
-- transport shows them as panel icons (mixer, MIDI editor); clicking a lit one goes back to
-- ARRANGE. The ARRANGE action stays for toolbars and shortcuts.
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

-- what the DEVICES key opens: by default Saxmand's script; in the settings any other
-- action can be chosen (ExtState devices_action: a command id or a named one like _RS...)
function V.devices_action()
  return r.GetExtState(EXT, "devices_action")
end

function V.resolve(id)
  if not id or id == "" then return nil end
  local cmd = tonumber(id) or r.NamedCommandLookup(id)
  if cmd and cmd > 0 then return math.floor(cmd) end
  return nil
end

function V.devices_command()
  local own = V.devices_action()
  if own ~= "" then return V.resolve(own) end
  return V.saxmand_command()
end

-- open = the action's toggle state is on (Saxmand's script sets it while it runs; other
-- panels may not, and then the key simply stays grey)
function V.devices_open()
  local cmd = V.devices_command()
  return cmd ~= nil and r.GetToggleCommandState(cmd) == 1
end

-- the audio editor icon: SneakPeak by default (its own Open/Close action), or any action
-- chosen in the settings (ExtState audio_action)
local SNEAKPEAK = "_SneakPeak_Toggle"
function V.audio_action() return r.GetExtState(EXT, "audio_action") end
function V.sneakpeak_command()
  local cmd = r.NamedCommandLookup(SNEAKPEAK)
  return cmd ~= 0 and cmd or nil
end
function V.audio_command()
  local own = V.audio_action()
  if own ~= "" then return V.resolve(own) end
  return V.sneakpeak_command()
end
-- SneakPeak's action opens it but reports no toggle state and doesn't close it (seen
-- 2026-11-24), so its window is looked up by title (js_ReaScriptAPI): "SneakPeak ..."
function V.sneakpeak_window()
  if not r.JS_Window_ListFind then return nil end
  local n, list = r.JS_Window_ListFind("SneakPeak", false)
  if not n or n == 0 then return nil end
  local main = r.GetMainHwnd()
  for addr in (list or ""):gmatch("[^,]+") do
    local hwnd = r.JS_Window_HandleFromAddress(tonumber(addr))
    if hwnd and hwnd ~= main and r.JS_Window_IsVisible(hwnd) then
      local title = r.JS_Window_GetTitle(hwnd) or ""
      if title:find("SneakPeak", 1, true) and not title:find("REAPER", 1, true) then return hwnd end
    end
  end
  return nil
end

function V.audio_open()
  local cmd = V.audio_command()
  if not cmd then return false end
  if r.GetToggleCommandState(cmd) == 1 then return true end
  return V.audio_action() == "" and V.sneakpeak_window() ~= nil
end

-- close SneakPeak's window: out of the docker first when docked, then a close message
function V.close_sneakpeak()
  local hwnd = V.sneakpeak_window()
  if not hwnd then return false end
  if r.DockIsChildOfDock and r.DockIsChildOfDock(hwnd) ~= -1 and r.DockWindowRemove then
    r.DockWindowRemove(hwnd)
  end
  r.JS_WindowMessage_Post(hwnd, "WM_CLOSE", 0, 0, 0, 0)
  return true
end

-- a view key closes the device panel: running its action again ends it (REAPER may ask
-- once whether to terminate a script; "Remember my answer" keeps that quiet afterwards)
local function close_devices()
  if V.devices_open() then r.Main_OnCommand(V.devices_command(), 0) end
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
  local c = set_param("bitAudOn", V.audio_open() and 1 or 0)
  if a or b or c then r.ThemeLayout_RefreshAll() end
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

-- the panel icons toggle: clicking the lit mixer or MIDI editor icon goes back to the
-- arrange alone (what the ARRANGE key did)
function V.run(view)
  if view ~= 0 and V.current() == view then view = 0 end
  V.switch(view)
  V.watch()
end

return V
