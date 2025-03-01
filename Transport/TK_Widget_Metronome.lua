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
    
    metronome_active = 0x00FF00FF,
    metronome_enabled = 0x00FF00FF,
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
