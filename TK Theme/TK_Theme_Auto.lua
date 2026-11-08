-- @noindex
-- Day and night: Light from one time, Dark from another, switched by the watcher
-- (TK_Theme_Metronome_Watch.lua) through the settings script, which then runs
-- without its window and changes the look as its Look page would. Only when the
-- schedule turns: a look chosen by hand stays until the next turn. Never while
-- playing, recording or paused, nor with the settings window open.
local r = reaper
local Auto = {}

Auto.SECTION = "TK_Theme_Auto"
Auto.LIGHT, Auto.DARK = "TK Theme Light", "TK Theme Dark"
Auto.DEFAULT = { light = "08:00", dark = "19:00" }
-- what the running watcher does: one that started before an update keeps its old code, so a
-- higher number here has it restarted. Raise it whenever TK_Theme_Metronome_Watch.lua changes.
Auto.WATCHER = "2"

-- whether the watcher runs, and is the one this version of the theme comes with
function Auto.watcher_current()
    local beat = tonumber(r.GetExtState("TK_Theme_Watch", "beat"))
    if not beat or r.time_precise() - beat >= 3 then return false end
    return r.GetExtState("TK_Theme_Watch", "version") == Auto.WATCHER
end

local function get(key) return r.GetExtState(Auto.SECTION, key) end
local function set(key, value, persist) r.SetExtState(Auto.SECTION, key, value, persist ~= false) end

-- "8", "8:00", "08:00" or "8.30": minutes after midnight, and the time as HH:MM; nil when not a time
function Auto.parse(text)
    local h, m = tostring(text or ""):match("^%s*(%d%d?)%s*[:.]?%s*(%d?%d?)%s*$")
    h, m = tonumber(h), tonumber(m ~= "" and m or "0")
    if not h or not m or h > 23 or m > 59 then return nil end
    return h * 60 + m, string.format("%02d:%02d", h, m)
end

function Auto.times()
    local light = Auto.parse(get("light")) or Auto.parse(Auto.DEFAULT.light)
    local dark = Auto.parse(get("dark")) or Auto.parse(Auto.DEFAULT.dark)
    return light, dark
end

function Auto.on() return get("on") == "1" end

-- the look the schedule asks for at this minute of the day
function Auto.wanted(minute, light, dark)
    if light == dark then return nil end
    local is_light
    if light < dark then
        is_light = minute >= light and minute < dark
    else
        is_light = minute >= light or minute < dark
    end
    return is_light and Auto.LIGHT or Auto.DARK
end

function Auto.now_minute()
    local t = os.date("*t")
    return t.hour * 60 + t.min
end

function Auto.loaded_theme()
    local base = (r.GetLastColorThemeFile() or ""):match("([^\\/]+)%.ReaperTheme")
    if base == Auto.LIGHT or base == Auto.DARK then return base end
    return nil
end

-- why not now, or nil when it's safe to change the look
function Auto.busy()
    if r.GetPlayState() ~= 0 then return "playing" end
    local beat = tonumber(r.GetExtState("TK Theme Settings", "open"))
    if beat and r.time_precise() - beat < 3 then return "settings" end
    return nil
end

-- turning it on (or changing a time) applies the schedule right away, when safe
function Auto.enable(on)
    set("on", on and "1" or "0")
    set("done", "")
end

function Auto.set_time(which, text)
    local _, hhmm = Auto.parse(text)
    if not hhmm then return false end
    set(which, hhmm)
    set("done", "")
    return true
end

-- One step of the watcher. run(theme) asks for that look and returns whether it could.
-- Returns what happened: nil, "waiting", "switched" or "kept".
function Auto.step(run, minute)
    if not Auto.on() then return nil end
    local light, dark = Auto.times()
    local wanted = Auto.wanted(minute or Auto.now_minute(), light, dark)
    if not wanted or get("done") == wanted then return nil end
    -- another theme loaded: that's the user's choice, so this turn is left alone
    local loaded = Auto.loaded_theme()
    if not loaded then
        set("done", wanted)
        return "kept"
    end
    if Auto.busy() then return "waiting" end
    if loaded == wanted then
        set("done", wanted)
        return "kept"
    end
    if run(wanted) then
        set("done", wanted)
        return "switched"
    end
    return "waiting"
end

-- the request the settings script reads when it starts without its window
function Auto.request(theme) set("request", theme, false) end

function Auto.take_request()
    local theme = get("request")
    if theme == "" then return nil end
    r.DeleteExtState(Auto.SECTION, "request", false)
    return theme
end

return Auto
