-- @description TK_time selection loop color configuration
-- @version 2.3
-- @author TouristKiller
-- @changelog
--   + Bugfixes

local r = reaper
local ctx = r.ImGui_CreateContext('Color Settings')
local font = r.ImGui_CreateFont('Arial', 14)
r.ImGui_Attach(ctx, font)

function GetMainScriptCommandID()
    local script_path = debug.getinfo(1,'S').source:match("@?(.*)")
    local main_script_path = script_path:gsub("_setup%.lua$", ".lua")
    return reaper.AddRemoveReaScript(true, 0, main_script_path, true)
end

local function SetupStyle()
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowRounding(), 10.0)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), 8.0)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowBorderSize(), 0)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_WindowBg(), 0x000000E6)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), 0x1A1A1AFF)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x2D2D2DFF)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0x404040FF)
end

function IsWindows()
    return package.config:sub(1,1) == '\\'
end

function ProcessColor(color)
    if IsWindows() then
        local r = (color >> 16) & 0xFF
        local g = (color >> 8) & 0xFF
        local b = color & 0xFF
        return (b << 16) | (g << 8) | r
    end
    return color
end


function GetSettings()
    local loop_color = tonumber(r.GetExtState("TK_time selection loop color", "loop_color")) or r.ColorToNative(0, 0, 255)
    local default_color = tonumber(r.GetExtState("TK_time selection loop color", "default_color")) or r.ColorToNative(255, 255, 255)
    local midi_color = tonumber(r.GetExtState("TK_time selection loop color", "midi_color")) or r.ColorToNative(255, 0, 0)
    local only_loop = r.GetExtState("TK_time selection loop color", "only_loop") == "1"
    local only_arrange = r.GetExtState("TK_time selection loop color", "only_arrange") == "1"
    local enable_midi = r.GetExtState("TK_time selection loop color", "enable_midi") == "1"
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

local loop_color, default_color, midi_color, only_loop, only_arrange, enable_midi = GetSettings()
local temp_loop_color = loop_color
local temp_default_color = default_color
local temp_midi_color = midi_color
local temp_only_loop = only_loop
local temp_only_arrange = only_arrange
local temp_enable_midi = enable_midi
local temp_disco_mode = r.GetExtState("TK_time selection loop color", "disco_mode") == "1"
local temp_link_state = r.GetToggleCommandState(40621) == 1

function Main()
    r.ImGui_PushFont(ctx, font)
    SetupStyle()  
    r.ImGui_SetNextWindowSize(ctx, 250, 350) 
    local visible, open = r.ImGui_Begin(ctx, 'TK time selection loop color setup', true, r.ImGui_WindowFlags_NoResize() | r.ImGui_WindowFlags_NoScrollbar())
    
    if visible then
        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FramePadding(), 8, 4)
        
        r.ImGui_Text(ctx, 'Loop Color')
        local rv, new_color = r.ImGui_ColorEdit3(ctx, '##loop_color', ProcessColor(temp_loop_color))
        if rv then
            temp_loop_color = ProcessColor(new_color)
        end
        
        r.ImGui_Text(ctx, 'Default Color')
        local rv2, new_default = r.ImGui_ColorEdit3(ctx, '##default_color', ProcessColor(temp_default_color))
        if rv2 then
            temp_default_color = ProcessColor(new_default)
        end
        
        r.ImGui_Text(ctx, 'MIDI Selection Color')
        local rv3, new_midi = r.ImGui_ColorEdit3(ctx, '##midi_color', ProcessColor(temp_midi_color))
        if rv3 then
            temp_midi_color = ProcessColor(new_midi)
        end
        
        local cmd_id = GetMainScriptCommandID()
        local is_enabled = reaper.GetToggleCommandState(cmd_id) == 1
        local rv6, new_enabled = r.ImGui_Checkbox(ctx, 'Enable script', is_enabled)
        if rv6 and new_enabled ~= is_enabled then
            r.Main_OnCommand(cmd_id, 0)
        end
        
        local rv4, new_link_state = r.ImGui_Checkbox(ctx, 'Link loop points to time selection', temp_link_state)
        if rv4 then
            temp_link_state = new_link_state
        end
        
        local rv5, new_only_loop = r.ImGui_Checkbox(ctx, 'Only loop color', temp_only_loop)
        if rv5 then
            temp_only_loop = new_only_loop
            if new_only_loop then 
                temp_only_arrange = false 
            end
        end
        
        local rv7, new_only_arrange = r.ImGui_Checkbox(ctx, 'Only arrange color', temp_only_arrange)
        if rv7 then
            temp_only_arrange = new_only_arrange
            if new_only_arrange then 
                temp_only_loop = false 
            end
        end
        
        local rv8, new_enable_midi = r.ImGui_Checkbox(ctx, 'Enable MIDI editor colors', temp_enable_midi)
        if rv8 then
            temp_enable_midi = new_enable_midi
        end
        
        local rv9, new_disco = r.ImGui_Checkbox(ctx, 'Disco mode', temp_disco_mode)
        if rv9 then
            temp_disco_mode = new_disco
        end
        
        if r.ImGui_Button(ctx, 'Apply') then
            loop_color = temp_loop_color
            default_color = temp_default_color
            midi_color = temp_midi_color
            only_loop = temp_only_loop
            only_arrange = temp_only_arrange
            enable_midi = temp_enable_midi
            disco_mode = temp_disco_mode
            SaveSettings(loop_color, default_color, midi_color, only_loop, only_arrange, enable_midi)
            
            local current_link_state = r.GetToggleCommandState(40621) == 1
            if current_link_state ~= temp_link_state then
                r.Main_OnCommand(40621, 0)
            end
        end
        
        r.ImGui_SameLine(ctx)
        r.ImGui_Text(ctx, 'Always click "Apply" to save')
        r.ImGui_PopStyleVar(ctx)
        r.ImGui_End(ctx)
    end
    
    r.ImGui_PopFont(ctx)
    r.ImGui_PopStyleVar(ctx, 3)
    r.ImGui_PopStyleColor(ctx, 4)
    
    if open then
        r.defer(Main)
    end
end
Main()
