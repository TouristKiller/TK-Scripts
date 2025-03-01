local r = reaper
local script_path = debug.getinfo(1, "S").source:match("@?(.*[/\\])")
package.path = script_path .. "?.lua;"

local handler = require("TK_Widget_Handler")

local default_settings = {
    overlay_enabled = true,
    rel_pos_x = 0.25,
    rel_pos_y = 0.15,
    font_size = 14,
    show_background = true,
    widget_width = 200,
    widget_height = 30,
    use_tk_transport_theme = true,
}

local widget = handler.init("Cursor Position Widget", default_settings)
widget.SetWidgetTitle("Cursor Position")
widget.LoadSettings("CURSOR_POSITION_WIDGET")

function ShowCursorPosition(h)
    local play_state = r.GetPlayState()
    local position = (play_state == 1) and r.GetPlayPosition() or r.GetCursorPosition()

    local retval, pos, measurepos, beatpos, bpm, timesig_num, timesig_denom = r.GetTempoTimeSigMarker(0, 0)
    if not retval then timesig_num, timesig_denom = 4, 4 end
    
    local retval, measures, cml, fullbeats = r.TimeMap2_timeToBeats(0, position)
    measures = measures or 0
    
    local beatsInMeasure = fullbeats % timesig_num
    local ticks = math.floor((beatsInMeasure - math.floor(beatsInMeasure)) * 960/10)
    local minutes = math.floor(position / 60)
    local seconds = position % 60
    local time_str = string.format("%d:%06.3f", minutes, seconds)
    
    local mbt_str = string.format("%d.%d.%02d", 
        math.floor(measures+1), 
        math.floor(beatsInMeasure+1),
        ticks)
    
    r.ImGui_PushStyleColor(h.ctx, r.ImGui_Col_Button(), h.settings.button_color)
    r.ImGui_Button(h.ctx, mbt_str .. " / " .. time_str)
    r.ImGui_PopStyleColor(h.ctx)
end

function MainLoop()
    local open = widget.RunLoop(ShowCursorPosition)
    if open then
        r.defer(MainLoop)
    end
end

MainLoop()
