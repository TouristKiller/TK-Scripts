-- @description TK_time selection loop color
-- @version 2.2
-- @author TouristKiller
-- @changelog
--   + Added MIDI editor time selection coloring
--   + Added platform independent color handling

local r = reaper
local original_bgsel = r.ColorToNative(0, 0, 0)
local original_bgsel2 = r.ColorToNative(0, 0, 0)
local original_midi_sel = r.ColorToNative(0, 0, 0)
local disco_mode = false
local disco_hue = 0
local DISCO_SPEED = 0.005
local last_loop_state = -1

-- Initialize original colors
function InitColors()
    original_bgsel = r.GetThemeColor("col_tl_bgsel", 0)
    original_bgsel2 = r.GetThemeColor("col_tl_bgsel2", 0)
    original_midi_sel = r.GetThemeColor("midi_selbg", 0)
end

function GetSettings()
    local loop_color = tonumber(r.GetExtState("TK_time selection loop color", "loop_color")) or r.ColorToNative(0, 0, 255)
    local default_color = tonumber(r.GetExtState("TK_time selection loop color", "default_color")) or r.ColorToNative(255, 255, 255)
    local midi_color = tonumber(r.GetExtState("TK_time selection loop color", "midi_color")) or r.ColorToNative(255, 0, 0)
    local only_loop = r.GetExtState("TK_time selection loop color", "only_loop") == "1"
    local only_arrange = r.GetExtState("TK_time selection loop color", "only_arrange") == "1"
    local enable_midi = r.GetExtState("TK_time selection loop color", "enable_midi") == "1"
    disco_mode = r.GetExtState("TK_time selection loop color", "disco_mode") == "1"
    return loop_color, default_color, midi_color, only_loop, only_arrange, enable_midi
end

function SaveSettings(loop_color, default_color, midi_color, only_loop, only_arrange, enable_midi)
    r.SetExtState("TK_time selection loop color", "loop_color", tostring(loop_color), true)
    r.SetExtState("TK_time selection loop color", "default_color", tostring(default_color), true)
    r.SetExtState("TK_time selection loop color", "midi_color", tostring(midi_color), true)
    r.SetExtState("TK_time selection loop color", "only_loop", only_loop and "1" or "0", true)
    r.SetExtState("TK_time selection loop color", "only_arrange", only_arrange and "1" or "0", true)
    r.SetExtState("TK_time selection loop color", "enable_midi", enable_midi and "1" or "0", true)
    r.SetExtState("TK_time selection loop color", "disco_mode", disco_mode and "1" or "0", true)
end

function RestoreThemeColors()
    r.SetThemeColor("col_tl_bgsel", original_bgsel, 0)
    r.SetThemeColor("col_tl_bgsel2", original_bgsel2, 0)
    r.SetThemeColor("midi_selbg", original_midi_sel, 0)
    r.UpdateArrange()
    r.UpdateTimeline()
    -- Update MIDI editor if it's open
    local midi_editor = r.MIDIEditor_GetActive()
    if midi_editor then
        r.MIDIEditor_OnCommand(midi_editor, 40462) -- Refresh MIDI editor
    end
end

function SetButtonState(set)
    local is_new_value, filename, sec, cmd, mode, resolution, val = r.get_action_context()
    r.SetToggleCommandState(sec, cmd, set or 0)
    r.RefreshToolbar2(sec, cmd)
end

function RGBtoHSV(r, g, b)
    local max = math.max(r, g, b)
    local min = math.min(r, g, b)
    local h, s, v
    v = max
    
    local d = max - min
    if max == 0 then s = 0 else s = d / max end
    
    if max == min then
        h = 0
    else
        if max == r then
            h = (g - b) / d
            if g < b then h = h + 6 end
        elseif max == g then
            h = (b - r) / d + 2
        else
            h = (r - g) / d + 4
        end
        h = h / 6
    end
    
    return h, s, v
end

function HSVtoRGB(h, s, v)
    local red, green, blue
    
    local i = math.floor(h * 6)
    local f = h * 6 - i
    local p = v * (1 - s)
    local q = v * (1 - f * s)
    local t = v * (1 - (1 - f) * s)
    
    i = i % 6
    
    if i == 0 then red, green, blue = v, t, p
    elseif i == 1 then red, green, blue = q, v, p
    elseif i == 2 then red, green, blue = p, v, t
    elseif i == 3 then red, green, blue = p, q, v
    elseif i == 4 then red, green, blue = t, p, v
    else red, green, blue = v, p, q
    end
    
    return red, green, blue
end

function GetDiscoColor()
    local red, green, blue = HSVtoRGB(disco_hue, 1, 1)
    disco_hue = (disco_hue + DISCO_SPEED) % 1
    return r.ColorToNative(math.floor(red * 255), math.floor(green * 255), math.floor(blue * 255))
end

function ChangeTimeSelectionColor()
    local is_loop_enabled = r.GetSetRepeat(-1)
    local loop_color, default_color, midi_color, only_loop, only_arrange, enable_midi = GetSettings()
    
    -- Update arrange view colors
    if is_loop_enabled == 0 then
        if only_loop then
            r.SetThemeColor("col_tl_bgsel2", default_color, 0)
            r.SetThemeColor("col_tl_bgsel", original_bgsel, 0)
        elseif only_arrange then
            r.SetThemeColor("col_tl_bgsel", default_color, 0)
            r.SetThemeColor("col_tl_bgsel2", original_bgsel2, 0)
        else
            r.SetThemeColor("col_tl_bgsel", default_color, 0)
            r.SetThemeColor("col_tl_bgsel2", default_color, 0)
        end
    else
        local active_color = disco_mode and GetDiscoColor() or loop_color
        if only_loop then
            r.SetThemeColor("col_tl_bgsel2", active_color, 0)
            r.SetThemeColor("col_tl_bgsel", original_bgsel, 0)
        elseif only_arrange then
            r.SetThemeColor("col_tl_bgsel", active_color, 0)
            r.SetThemeColor("col_tl_bgsel2", original_bgsel2, 0)
        else
            r.SetThemeColor("col_tl_bgsel", active_color, 0)
            r.SetThemeColor("col_tl_bgsel2", active_color, 0)
        end
    end

    -- Update MIDI editor colors if enabled
    if enable_midi then
        if is_loop_enabled == 1 then
            r.SetThemeColor("midi_selbg", midi_color, 0)
        else
            r.SetThemeColor("midi_selbg", default_color, 0)
        end
    else
        r.SetThemeColor("midi_selbg", original_midi_sel, 0)
    end
    
    r.UpdateArrange()
    r.UpdateTimeline()
    
    -- Update MIDI editor if it's open
    local midi_editor = r.MIDIEditor_GetActive()
    if midi_editor then
        r.MIDIEditor_OnCommand(midi_editor, 40462) -- Refresh MIDI editor
    end
    
    last_loop_state = is_loop_enabled
end

function Main()
    ChangeTimeSelectionColor()
    r.defer(Main)
end

-- Script initialization
InitColors()

if r.GetExtState("TK_time selection loop color", "CALL_SETUP") == "1" then
    r.SetExtState("TK_time selection loop color", "CALL_SETUP", "0", false)
    local info = debug.getinfo(1,'S')
    local script_path = info.source:match("@?(.*)")
    local setup_script_path = script_path:match("(.*[/\\])") .. "TK_time selection loop color_setup.lua"
    dofile(setup_script_path)
else
    SetButtonState(1)
    Main()
    r.atexit(function()
        SetButtonState()
        RestoreThemeColors()
    end)
end