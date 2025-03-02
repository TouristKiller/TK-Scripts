local r = reaper
local script_path = debug.getinfo(1, "S").source:match("@?(.*[/\\])")
package.path = script_path .. "?.lua;"

local handler = require("TK_Widget_Handler")

local default_settings = {
    overlay_enabled = true,
    rel_pos_x = 0.93,
    rel_pos_y = 0.15,
    font_size = 14,
    show_background = true,
    widget_width = 150,
    widget_height = 30,
    use_tk_transport_theme = true,
    
    -- Voeg deze ontbrekende stijlwaarden toe
    window_rounding = 4.0,
    frame_rounding = 4.0,
    popup_rounding = 4.0,
    grab_rounding = 4.0,
    grab_min_size = 10.0,
    button_border_size = 1.0,
    border_size = 1.0,
    
    -- Basiskleurinstellingen
    background_color = 0x333333FF,
    text_color = 0xFFFFFFFF,
    button_color = 0x555555FF,
    button_hover_color = 0x777777FF,
    button_active_color = 0x999999FF,
    border_color = 0x888888FF,
    check_mark = 0xFFFFFFFF,
    slider_grab = 0x888888FF,
    slider_grab_active = 0xAAAAAAFF,
    frame_bg = 0x444444FF,
    frame_bg_hovered = 0x666666FF,
    frame_bg_active = 0x888888FF
}

local widget = handler.init("PlayRate Widget", default_settings)
widget.SetWidgetTitle("Playback Rate")
widget.LoadSettings("PLAYRATE_WIDGET")


function ShowPlayRateSlider(h)
    local current_rate = r.Master_GetPlayRate(0)
    
    r.ImGui_AlignTextToFramePadding(h.ctx)
    r.ImGui_Text(h.ctx, 'Rate:')
    r.ImGui_SameLine(h.ctx)
    r.ImGui_PushItemWidth(h.ctx, 80)
    local rv, new_rate = r.ImGui_SliderDouble(h.ctx, '##PlayRateSlider', current_rate, 0.25, 4.0, "%.2fx")  
    
    if r.ImGui_IsItemClicked(h.ctx, 1) then
        new_rate = 1.0
        r.CSurf_OnPlayRateChange(new_rate)
    elseif rv then
        r.CSurf_OnPlayRateChange(new_rate)
    end
    
    r.ImGui_PopItemWidth(h.ctx)
end

function MainLoop()
    local open = widget.RunLoop(ShowPlayRateSlider)
    if open then
        r.defer(MainLoop)
    end
end

MainLoop()
