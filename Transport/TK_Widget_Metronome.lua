local r = reaper
local script_path = debug.getinfo(1, "S").source:match("@?(.*[/\\])")
package.path = script_path .. "?.lua;"

local handler = require("TK_Widget_Handler")

local default_settings = {
    overlay_enabled = true,
    rel_pos_x = 0.32,
    rel_pos_y = 0.15,
    font_size = 14,
    show_background = true,
    widget_width = 40,
    widget_height = 40,
    use_tk_transport_theme = true,
    
    -- Metronoom specifieke instellingen
    metronome_active = 0x00FF00FF,
    metronome_enabled = 0x00FF00FF,
    
    -- Voeg deze ontbrekende stijlwaarden toe
    window_rounding = 4.0,
    frame_rounding = 4.0,
    popup_rounding = 4.0,
    grab_rounding = 4.0,
    grab_min_size = 10.0,
    button_border_size = 1.0,
    border_size = 1.0,
    
    -- Basiskleurinstellingen (voor het geval use_tk_transport_theme uitstaat)
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

local widget = handler.init("Visual Metronome Widget", default_settings)
widget.SetWidgetTitle("Visual Metronome")
widget.LoadSettings("VISUAL_METRONOME_WIDGET")

function ShowVisualMetronome(h)
    local playPos = r.GetPlayPosition()
    local tempo = r.Master_GetTempo()
    local beatLength = 60/tempo
    local currentBeatPhase = playPos % beatLength
    local pulseSize = h.settings.font_size * 0.5

    local pulseIntensity = math.exp(-currentBeatPhase * 8/beatLength)
    local finalSize = pulseSize * (1 + pulseIntensity * 0.1)
    
    local screenX, screenY = r.ImGui_GetCursorScreenPos(h.ctx)
    local posX = screenX + pulseSize
    local posY = screenY + pulseSize
    
    local buttonSize = pulseSize * 2
    r.ImGui_InvisibleButton(h.ctx, "MetronomeButton", buttonSize, buttonSize)
    
    local drawList = r.ImGui_GetWindowDrawList(h.ctx)
    local color = h.settings.button_color
    if currentBeatPhase < 0.05 then
        color = h.settings.metronome_active
    end

    r.ImGui_DrawList_AddCircleFilled(drawList, posX, posY, finalSize, color)
    
    local metronome_enabled = r.GetToggleCommandState(40364) == 1
    if metronome_enabled then
        r.ImGui_DrawList_AddCircle(drawList, posX, posY, finalSize + 2, h.settings.metronome_enabled, 32, 2)
    end
    
    if r.ImGui_IsItemClicked(h.ctx, 1) then
        r.ImGui_OpenPopup(h.ctx, "MetronomeMenu")
    end
    
    if r.ImGui_BeginPopup(h.ctx, "MetronomeMenu") then
        if r.ImGui_MenuItem(h.ctx, "Metronome Settings") then
            r.Main_OnCommand(40363, 0)
        end
        if r.ImGui_MenuItem(h.ctx, "Toggle Metronome") then
            r.Main_OnCommand(40364, 0)
        end
        r.ImGui_EndPopup(h.ctx)
    end
end

function MainLoop()
    local open = widget.RunLoop(ShowVisualMetronome)
    if open then
        r.defer(MainLoop)
    end
end

MainLoop()
