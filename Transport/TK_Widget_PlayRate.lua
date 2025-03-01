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
