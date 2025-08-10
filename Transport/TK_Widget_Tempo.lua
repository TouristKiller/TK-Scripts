local r = reaper
local script_path = debug.getinfo(1, "S").source:match("@?(.*[/\\])")
local os_separator = package.config:sub(1, 1)
package.path = script_path .. "?.lua;"

local handler = require("TK_Widget_Handler")

local default_settings = {
    overlay_enabled = true,
    rel_pos_x = 0.5,
    rel_pos_y = 0.3,
    font_size = 12,
    show_background = false,
    widget_width = 300,
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
    loop_active = 0x0088FFFF,
    last_pos_x = 100,
    last_pos_y = 100
}

local widget = handler.init("Tempo Widget", default_settings)
widget.SetWidgetTitle("Tempo & Time Signature")
widget.LoadSettings("TEMPO_WIDGET")

function ShowTempoAndTimeSignature(h)
    local tempo = r.Master_GetTempo()
    r.ImGui_SetCursorPosX(h.ctx, 10)
    r.ImGui_SetCursorPosY(h.ctx, 0)
    r.ImGui_AlignTextToFramePadding(h.ctx)
    r.ImGui_PushStyleColor(h.ctx, r.ImGui_Col_Text(), h.settings.text_color)
    r.ImGui_Text(h.ctx, "BPM:")
    r.ImGui_SameLine(h.ctx)
    r.ImGui_PushStyleColor(h.ctx, r.ImGui_Col_FrameBg(), h.settings.button_color)
    r.ImGui_PushStyleColor(h.ctx, r.ImGui_Col_FrameBgHovered(), h.settings.button_hover_color)
    r.ImGui_PushItemWidth(h.ctx, 60)
    local rv_tempo, new_tempo = r.ImGui_InputDouble(h.ctx, "##tempo", tempo, 0, 0, "%.1f")
    if rv_tempo and r.ImGui_IsItemDeactivatedAfterEdit(h.ctx) then r.CSurf_OnTempoChange(new_tempo) end
    if r.ImGui_IsItemClicked(h.ctx, 1) then r.CSurf_OnTempoChange(120.0) end
    r.ImGui_PopItemWidth(h.ctx)
    r.ImGui_SameLine(h.ctx)
    r.ImGui_Text(h.ctx, "Time Sig:")
    r.ImGui_SameLine(h.ctx)
    local retval, pos, measurepos, beatpos, bpm, timesig_num, timesig_denom = r.GetTempoTimeSigMarker(0, 0)
    if not retval then timesig_num, timesig_denom = 4, 4 end
    r.ImGui_PushItemWidth(h.ctx, 30)
    local rv_num, new_num = r.ImGui_InputInt(h.ctx, "##num", timesig_num, 0, 0)
    local num_edited = rv_num and r.ImGui_IsItemDeactivatedAfterEdit(h.ctx)
    r.ImGui_SameLine(h.ctx)
    r.ImGui_Text(h.ctx, "/")
    r.ImGui_SameLine(h.ctx)
    local rv_denom, new_denom = r.ImGui_InputInt(h.ctx, "##denom", timesig_denom, 0, 0)
    local denom_edited = rv_denom and r.ImGui_IsItemDeactivatedAfterEdit(h.ctx)
    r.ImGui_PopItemWidth(h.ctx)
    if (num_edited and new_num > 0) or (denom_edited and new_denom > 0) then
        r.Undo_BeginBlock()
        r.PreventUIRefresh(1)
        local _, measures = r.TimeMap2_timeToBeats(0, 0)
        local ptx_in_effect = r.FindTempoTimeSigMarker(0, 0)
        local num_to_set = (num_edited and new_num > 0) and new_num or timesig_num
        local denom_to_set = (denom_edited and new_denom > 0) and new_denom or timesig_denom
        r.SetTempoTimeSigMarker(0, -1, -1, measures, 0, -1, num_to_set, denom_to_set, true)
        r.GetSetTempoTimeSigMarkerFlag(0, ptx_in_effect + 1, 1|2|16, true)
        r.PreventUIRefresh(-1)
        r.Undo_EndBlock("Change time signature", 1|4|8)
    end
    r.ImGui_PopStyleColor(h.ctx, 3)
end

function MainLoop()

    local open = widget.RunLoop(ShowTempoAndTimeSignature)
    local close_command = r.GetExtState("TK_WIDGET_COMMAND", "TK_Tempo_widget.lua")
    if close_command == "close" then
        r.DeleteExtState("TK_WIDGET_COMMAND", "TK_Tempo_widget.lua", false)
        open = false
    end
    if open then
        r.defer(MainLoop)
    end
end

MainLoop()
