local r = reaper
local script_path = debug.getinfo(1, "S").source:match("@?(.*[/\\])")
package.path = script_path .. "?.lua;"

local handler = require("TK_Widget_Handler")

local default_settings = {
    overlay_enabled = true,
    rel_pos_x = 0.75,
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
    frame_bg_active = 0x888888FF,
    
    -- Tap Tempo specifieke instellingen
    input_limit = 16,
    tap_button_text = "TAP",
    tap_button_width = 50,
    tap_button_height = 30,
    set_tempo_on_tap = true,
    show_accuracy_indicator = true,
    high_accuracy_color = 0x00FF00FF,
    medium_accuracy_color = 0xFFFF00FF,
    low_accuracy_color = 0xFF0000FF
}

local widget = handler.init("Tap Tempo Widget", default_settings)
widget.SetWidgetTitle("Tap Tempo")
widget.LoadSettings("TAPTEMPO_WIDGET")

-- TapTempo state variabelen
local times = {}
local average_times = {}
local clock = 0
local average_current = 0
local clicks = 0
local z = 0
local w = 0
local last_tap_time = 0

-- Hulpfuncties voor statistieken
local function average(matrix)
    if #matrix == 0 then return 0 end
    
    local sum = 0
    for i, cell in ipairs(matrix) do
        sum = sum + cell
    end
    sum = sum / #matrix
    return sum
end

local function standardDeviation(t)
    if #t <= 1 then return 0 end
    
    local m = average(t)
    local sum = 0
    
    for k, v in pairs(t) do
        if type(v) == 'number' then
            local vm = v - m
            sum = sum + (vm * vm)
        end
    end
    
    return math.sqrt(sum / (#t - 1))
end

local function round(num, idp)
    local mult = 10^(idp or 0)
    return math.floor(num * mult + 0.5) / mult
end

local function durationToBpm(duration)
    if duration <= 0 then return 0 end
    local bpm = 60 / duration
    return bpm
end

-- Tap Tempo functie
local function TapTempo()
    local current_time = r.time_precise()
    
    if last_tap_time > 0 then
        local tap_interval = current_time - last_tap_time
        z = z + 1
        if z > default_settings.input_limit then z = 1 end
        
        times[z] = durationToBpm(tap_interval)
        
        if #times > 0 then
            average_current = average(times)
            
            -- Voeg het gemiddelde toe aan de geschiedenis
            if #times >= 4 then
                w = w + 1
                if w > default_settings.input_limit then w = 1 end
                average_times[w] = average_current
            end
            
            -- Optioneel: stel het tempo in Reaper in
            if widget.settings.set_tempo_on_tap and average_current > 0 then
                r.CSurf_OnTempoChange(average_current)
            end

        end
    end
    
    last_tap_time = current_time
    clicks = clicks + 1
end

function ShowTapTempo(h)
    -- Tap knop
    r.ImGui_PushStyleColor(h.ctx, r.ImGui_Col_Button(), h.settings.button_color)
    r.ImGui_PushStyleColor(h.ctx, r.ImGui_Col_ButtonHovered(), h.settings.button_hover_color)
    r.ImGui_PushStyleColor(h.ctx, r.ImGui_Col_ButtonActive(), h.settings.button_active_color)
    
    -- Detecteer linksklik voor tap
    local buttonPressed = r.ImGui_Button(h.ctx, h.settings.tap_button_text, h.settings.tap_button_width, h.settings.tap_button_height)
    
    -- Detecteer rechtsklik voor menu
    if r.ImGui_IsItemClicked(h.ctx, 1) then
        r.ImGui_OpenPopup(h.ctx, "TapTempoMenu")
    end
    
    r.ImGui_PopStyleColor(h.ctx, 3)
    
    if buttonPressed then
        TapTempo()
    end
    
    r.ImGui_SameLine(h.ctx)
    
    -- BPM weergave 
    if #times > 0 then
        -- Bereken statistieken
        local deviation = standardDeviation(times)
        local max_deviation = average_current + deviation
        local min_deviation = average_current - deviation
        local precision = 0
        
        if average_current > 0 then
            precision = min_deviation / average_current
        end
        
        -- Bepaal kleur op basis van nauwkeurigheid
        local accuracyColor = h.settings.low_accuracy_color
        if precision > 0.9 then
            accuracyColor = h.settings.high_accuracy_color
        elseif precision > 0.5 then
            accuracyColor = h.settings.medium_accuracy_color
        end
        
        -- Toon indicator indien ingeschakeld
        if h.settings.show_accuracy_indicator then
            r.ImGui_PushStyleColor(h.ctx, r.ImGui_Col_Text(), accuracyColor)
            r.ImGui_Text(h.ctx, string.format("%.1f%%", precision * 100))
            r.ImGui_PopStyleColor(h.ctx)
            r.ImGui_SameLine(h.ctx)
        end
        
        r.ImGui_Text(h.ctx, string.format("BPM: %.1f", round(average_current, 1)))
    else
        r.ImGui_Text(h.ctx, "Tap to start...")
    end
    
    -- Toon het popup menu
    if r.ImGui_BeginPopup(h.ctx, "TapTempoMenu") then
        if r.ImGui_MenuItem(h.ctx, "Reset Taps") then
            times = {}
            average_times = {}
            clicks = 0
            z = 0
            w = 0
            last_tap_time = 0
        end
        
        local rv
        rv, h.settings.set_tempo_on_tap = r.ImGui_MenuItem(h.ctx, "Set Project Tempo", nil, h.settings.set_tempo_on_tap)
        
        if #times > 0 then
            r.ImGui_Separator(h.ctx)
            
            if r.ImGui_MenuItem(h.ctx, "Set Half Tempo") then
                r.CSurf_OnTempoChange(average_current / 2)
            end
            
            if r.ImGui_MenuItem(h.ctx, "Set Double Tempo") then
                r.CSurf_OnTempoChange(average_current * 2)
            end
        end
        
        r.ImGui_EndPopup(h.ctx)
    end
end




-- Widget-specifieke instellingen
function WidgetSpecificSettings(ctx)
    local rv
    r.ImGui_Text(ctx, "Tap Tempo Settings")
    
    rv, widget.settings.tap_button_text = r.ImGui_InputText(ctx, "Button Text", widget.settings.tap_button_text)
    rv, widget.settings.tap_button_width = r.ImGui_InputInt(ctx, "Button Width", widget.settings.tap_button_width)
    rv, widget.settings.tap_button_height = r.ImGui_InputInt(ctx, "Button Height", widget.settings.tap_button_height)
    
    rv, widget.settings.set_tempo_on_tap = r.ImGui_Checkbox(ctx, "Set Project Tempo Automatically", widget.settings.set_tempo_on_tap)
    rv, widget.settings.show_accuracy_indicator = r.ImGui_Checkbox(ctx, "Show Accuracy Indicator", widget.settings.show_accuracy_indicator)
    
    if widget.settings.show_accuracy_indicator then
        rv, widget.settings.high_accuracy_color = r.ImGui_ColorEdit4(ctx, "High Accuracy Color", widget.settings.high_accuracy_color)
        rv, widget.settings.medium_accuracy_color = r.ImGui_ColorEdit4(ctx, "Medium Accuracy Color", widget.settings.medium_accuracy_color)
        rv, widget.settings.low_accuracy_color = r.ImGui_ColorEdit4(ctx, "Low Accuracy Color", widget.settings.low_accuracy_color)
    end
    
    rv, widget.settings.input_limit = r.ImGui_SliderInt(ctx, "History Size", widget.settings.input_limit, 4, 32)
end

widget.RegisterWidgetSettings(WidgetSpecificSettings)

function MainLoop()
    local open = widget.RunLoop(ShowTapTempo)
    if open then
        r.defer(MainLoop)
    end
end

MainLoop()
