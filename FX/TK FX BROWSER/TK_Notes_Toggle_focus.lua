-- @description TK Notes - Toggle focus between note and arrange view
-- @author TouristKiller
-- @version 1.0
-- @about
--   Moves the keyboard between TK Notes and REAPER's arrange view, so you can
--   type in a note, press the shortcut, use play/stop, and press it again to
--   carry on typing where the cursor was.
--   Assign your own shortcut to this action in the Action list. TK Notes reads
--   that shortcut too, so it also works while you are typing in the note.
--   If TK Notes is not running, this action starts it.
--   Requires js_ReaScriptAPI.

local r = reaper
local EXT = "TK_NOTES"

local function notes_running()
    local beat = tonumber(r.GetExtState(EXT, "heartbeat")) or 0
    return r.time_precise() - beat < 2
end

if not r.JS_Window_SetFocus then
    r.MB("This action needs the js_ReaScriptAPI extension (install it via ReaPack).", "TK Notes", 0)
    return
end

if notes_running() then
    r.SetExtState(EXT, "focus_toggle", string.format("%.3f", r.time_precise()), false)
else
    -- Started as its own action rather than with dofile: run inside this
    -- script, TK Notes would make the next press of this shortcut ask REAPER's
    -- "already running" question. A freshly started TK Notes takes the keyboard.
    local dir = debug.getinfo(1, "S").source:match("@?(.*[\\/])") or ""
    local cmd = r.AddRemoveReaScript(true, 0, dir .. "TK_NOTES.lua", true)
    if cmd and cmd ~= 0 then r.Main_OnCommand(cmd, 0) end
end
