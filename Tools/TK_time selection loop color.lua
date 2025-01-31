-- @description TK_time selection loop color
-- @version 2.0
-- @author TouristKiller
-- @changelog
--   + Added separate control for loop and arrange colors
--   + New setup UI
-----------------------------------------------------------------------------------
local r               = reaper
local original_bgsel  = r.GetThemeColor("col_tl_bgsel", 0)
local original_bgsel2 = r.GetThemeColor("col_tl_bgsel2", 0)

function GetSettings()
    local loop_color = tonumber(r.GetExtState("TK_time selection loop color", "loop_color")) or 0x0000FF
    local default_color = tonumber(r.GetExtState("TK_time selection loop color", "default_color")) or 0xFFFFFF
    local only_loop = r.GetExtState("TK_time selection loop color", "only_loop") == "1"
    local only_arrange = r.GetExtState("TK_time selection loop color", "only_arrange") == "1"
    return loop_color, default_color, only_loop, only_arrange
end

function SaveSettings(loop_color, default_color, only_loop, only_arrange)
    r.SetExtState("TK_time selection loop color", "loop_color", string.format("0x%06X", loop_color), true)
    r.SetExtState("TK_time selection loop color", "default_color", string.format("0x%06X", default_color), true)
    r.SetExtState("TK_time selection loop color", "only_loop", only_loop and "1" or "0", true)
    r.SetExtState("TK_time selection loop color", "only_arrange", only_arrange and "1" or "0", true)
end

function RestoreThemeColors()
    r.SetThemeColor("col_tl_bgsel", original_bgsel, 0)
    r.SetThemeColor("col_tl_bgsel2", original_bgsel2, 0)
    r.UpdateArrange()
    r.UpdateTimeline()
end

function SetButtonState(set)
    local is_new_value, filename, sec, cmd, mode, resolution, val = r.get_action_context()
    r.SetToggleCommandState(sec, cmd, set or 0)
    r.RefreshToolbar2(sec, cmd)
end

local last_loop_state = -1
function ChangeTimeSelectionColor()
    local is_loop_enabled = r.GetSetRepeat(-1)
    local loop_color, default_color, only_loop, only_arrange = GetSettings()
    if is_loop_enabled ~= last_loop_state then
        if only_loop then
            if is_loop_enabled == 1 then
                r.SetThemeColor("col_tl_bgsel2", loop_color, 0)
                r.SetThemeColor("col_tl_bgsel", original_bgsel, 0)
            else
                r.SetThemeColor("col_tl_bgsel2", default_color, 0)
                r.SetThemeColor("col_tl_bgsel", original_bgsel, 0)
            end
        elseif only_arrange then
            if is_loop_enabled == 1 then
                r.SetThemeColor("col_tl_bgsel", loop_color, 0)
                r.SetThemeColor("col_tl_bgsel2", original_bgsel2, 0)
            else
                r.SetThemeColor("col_tl_bgsel", default_color, 0)
                r.SetThemeColor("col_tl_bgsel2", original_bgsel2, 0)
            end
        else
            if is_loop_enabled == 1 then
                r.SetThemeColor("col_tl_bgsel", loop_color, 0)
                r.SetThemeColor("col_tl_bgsel2", loop_color, 0)
            else
                r.SetThemeColor("col_tl_bgsel", default_color, 0)
                r.SetThemeColor("col_tl_bgsel2", default_color, 0)
            end
        end    
        r.UpdateArrange()
        r.UpdateTimeline()
        last_loop_state = is_loop_enabled
    end
end

function Main()
    ChangeTimeSelectionColor()
    r.defer(Main)
end

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
