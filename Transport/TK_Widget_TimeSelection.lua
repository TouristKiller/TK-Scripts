local r = reaper
local script_path = debug.getinfo(1, "S").source:match("@?(.*[/\\])")
local os_separator = package.config:sub(1, 1)
package.path = script_path .. "?.lua;"

local handler = require("TK_Widget_Handler")

local default_settings = {
    overlay_enabled = true,
    rel_pos_x = 0.0,
    rel_pos_y = 0.15,
    font_size = 14,
    show_background = true,
    widget_width = 400,
    widget_height = 30,
    use_tk_transport_theme = true,
    current_preset = "",
    window_rounding = 12.0,
    frame_rounding = 6.0,
    popup_rounding = 6.0,
    grab_rounding = 12.0,
    grab_min_size = 8.0,
    button_border_size = 1.0,
    border_size = 1.0,
    current_font = "Arial",
    last_pos_x = 100,
    last_pos_y = 100,
    
    show_time_selection = true,
    show_beats_selection = true,
    timesel_border = true,
    timesel_invisible = false,
    timesel_color = 0x333333FF,
    background_color = 0x33333366,
    text_color = 0xFFFFFFFF,
    button_color = 0x44444477,
    button_hover_color = 0x55555588,
    button_active_color = 0x666666AA,
    border_color = 0x444444FF,
    frame_bg = 0x333333FF,
    frame_bg_hovered = 0x444444FF,
    frame_bg_active = 0x555555FF,
    slider_grab = 0x999999FF,
    slider_grab_active = 0xAAAAAAFF,
    check_mark = 0x999999FF,
    play_active = 0x00FF00FF,
    record_active = 0xFF0000FF,
    pause_active = 0xFFFF00FF,
    loop_active = 0x0088FFFF
}

local widget = handler.init("Time Selection Widget", default_settings)
widget.SetWidgetTitle("Time Selection")
widget.LoadSettings("TIME_SELECTION_WIDGET")

function WidgetSpecificSettings(ctx)
    local rv
    r.ImGui_Text(ctx, "Time Selection Display")
    rv, widget.settings.show_time_selection = r.ImGui_Checkbox(ctx, "Show Time", widget.settings.show_time_selection)
    r.ImGui_SameLine(ctx)
    rv, widget.settings.show_beats_selection = r.ImGui_Checkbox(ctx, "Show Beats", widget.settings.show_beats_selection)
    
    rv, widget.settings.timesel_invisible = r.ImGui_Checkbox(ctx, "Invisible Button", widget.settings.timesel_invisible)
    r.ImGui_SameLine(ctx)
    rv, widget.settings.timesel_border = r.ImGui_Checkbox(ctx, "Show Button Border", widget.settings.timesel_border)
    
    if not widget.settings.timesel_invisible then
        rv, widget.settings.timesel_color = r.ImGui_ColorEdit4(ctx, "Button Color", widget.settings.timesel_color)
    end
end

widget.RegisterWidgetSettings(WidgetSpecificSettings)

function ShowTimeSelection(h)
    local start_time, end_time = r.GetSet_LoopTimeRange2(0, false, false, 0, 0, false)
    local length = end_time - start_time
    
    local retval, pos, measurepos, beatpos, bpm, timesig_num, timesig_denom = r.GetTempoTimeSigMarker(0, 0)
    if not retval then timesig_num, timesig_denom = 4, 4 end
    
    local minutes_start = math.floor(start_time / 60)
    local seconds_start = start_time % 60
    local sec_format = string.format("%d:%06.3f", minutes_start, seconds_start)
    
    local retval, measures_start, cml, fullbeats_start = r.TimeMap2_timeToBeats(0, start_time)
    local beatsInMeasure_start = fullbeats_start % timesig_num
    local ticks_start = math.floor((beatsInMeasure_start - math.floor(beatsInMeasure_start)) * 960/10)
    local start_midi = string.format("%d.%d.%02d",
        math.floor(measures_start+1),
        math.floor(beatsInMeasure_start+1),
        ticks_start)
    
    local minutes_end = math.floor(end_time / 60)
    local seconds_end = end_time % 60
    local end_format = string.format("%d:%06.3f", minutes_end, seconds_end)
    
    local retval, measures_end, cml, fullbeats_end = r.TimeMap2_timeToBeats(0, end_time)
    local beatsInMeasure_end = fullbeats_end % timesig_num
    local ticks_end = math.floor((beatsInMeasure_end - math.floor(beatsInMeasure_end)) * 960/10)
    local end_midi = string.format("%d.%d.%02d",
        math.floor(measures_end+1),
        math.floor(beatsInMeasure_end+1),
        ticks_end)
    
    local minutes_len = math.floor(length / 60)
    local seconds_len = length % 60
    local len_format = string.format("%d:%06.3f", minutes_len, seconds_len)
    
    local retval, measures_length, cml, fullbeats_length = r.TimeMap2_timeToBeats(0, length)
    local beatsInMeasure_length = fullbeats_length % timesig_num
    local ticks_length = math.floor((beatsInMeasure_length - math.floor(beatsInMeasure_length)) * 960/10)
    local len_midi = string.format("%d.%d.%02d",
        math.floor(measures_length),
        math.floor(beatsInMeasure_length),
        ticks_length)

    if h.settings.timesel_invisible then
        r.ImGui_PushStyleColor(h.ctx, r.ImGui_Col_Button(), 0x00000000)
        r.ImGui_PushStyleColor(h.ctx, r.ImGui_Col_ButtonHovered(), 0x00000000)
        r.ImGui_PushStyleColor(h.ctx, r.ImGui_Col_ButtonActive(), 0x00000000)
    else
        r.ImGui_PushStyleColor(h.ctx, r.ImGui_Col_Button(), h.settings.timesel_color)
    end

    if not h.settings.timesel_border then
        r.ImGui_PushStyleVar(h.ctx, r.ImGui_StyleVar_FrameBorderSize(), 0)
    end

    local display_text = ""
    if h.settings.show_beats_selection and h.settings.show_time_selection then
        display_text = string.format("Selection: %s / %s / %s / %s / %s / %s",
            start_midi, sec_format,
            end_midi, end_format,
            len_midi, len_format)
    elseif h.settings.show_beats_selection then
        display_text = string.format("Selection: %s / %s / %s",
            start_midi, end_midi, len_midi)
    elseif h.settings.show_time_selection then
        display_text = string.format("Selection: %s / %s / %s",
            sec_format, end_format, len_format)
    end

    if display_text == "" then
        r.ImGui_Button(h.ctx, "##TimeSelectionEmpty")
    else
        r.ImGui_Button(h.ctx, display_text)
    end

    if not h.settings.timesel_border then
        r.ImGui_PopStyleVar(h.ctx)
    end
    
    if h.settings.timesel_invisible then
        r.ImGui_PopStyleColor(h.ctx, 3)
    else
        r.ImGui_PopStyleColor(h.ctx)
    end
    
    if r.ImGui_IsItemClicked(h.ctx, 1) then
        r.ImGui_OpenPopup(h.ctx, "TimeSelectionMenu")
    end
    
    if r.ImGui_BeginPopup(h.ctx, "TimeSelectionMenu") then
        if r.ImGui_MenuItem(h.ctx, "Go to start") then
            r.Main_OnCommand(40630, 0)
        end
        if r.ImGui_MenuItem(h.ctx, "Go to end") then
            r.Main_OnCommand(40631, 0)
        end
        r.ImGui_Separator(h.ctx)
        if r.ImGui_MenuItem(h.ctx, "Clear time selection") then
            r.Main_OnCommand(40635, 0)
        end
        if r.ImGui_MenuItem(h.ctx, "Loop selection") then
            r.Main_OnCommand(40222, 0)
        end
        if r.ImGui_MenuItem(h.ctx, "Set time selection to items") then
            r.Main_OnCommand(40290, 0) 
        end
        r.ImGui_EndPopup(h.ctx)
    end
end

function MainLoop()
    local open = widget.RunLoop(ShowTimeSelection)
    if open then
        r.defer(MainLoop)
    end
end

MainLoop()
