-- @description TK_time selection loop color configuration
-- @version 2.1
-- @author TouristKiller
-- @changelog
--   + Added native color conversion for cross-platform compatibility

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

function GetSettings()
    local loop_color = tonumber(r.GetExtState("TK_time selection loop color", "loop_color")) or r.ColorToNative(0, 0, 255)
    local default_color = tonumber(r.GetExtState("TK_time selection loop color", "default_color")) or r.ColorToNative(255, 255, 255)
    local only_loop = r.GetExtState("TK_time selection loop color", "only_loop") == "1"
    local only_arrange = r.GetExtState("TK_time selection loop color", "only_arrange") == "1"
    return loop_color, default_color, only_loop, only_arrange
end

function SaveSettings(loop_color, default_color, only_loop, only_arrange)
    r.SetExtState("TK_time selection loop color", "loop_color", tostring(loop_color), true)
    r.SetExtState("TK_time selection loop color", "default_color", tostring(default_color), true)
    r.SetExtState("TK_time selection loop color", "only_loop", only_loop and "1" or "0", true)
    r.SetExtState("TK_time selection loop color", "only_arrange", only_arrange and "1" or "0", true)
    r.SetExtState("TK_time selection loop color", "disco_mode", disco_mode and "1" or "0", true)
end

function SwapRB(color)
    local r = (color >> 16) & 0xFF
    local g = (color >> 8) & 0xFF
    local b = color & 0xFF
    return (b << 16) | (g << 8) | r
end

local loop_color, default_color, only_loop, only_arrange = GetSettings()
local temp_loop_color = loop_color
local temp_default_color = default_color
local temp_only_loop = only_loop
local temp_only_arrange = only_arrange
local temp_disco_mode = r.GetExtState("TK_time selection loop color", "disco_mode") == "1"
local temp_link_state = r.GetToggleCommandState(40621) == 1

function Main()
    r.ImGui_PushFont(ctx, font)
    SetupStyle()  
    r.ImGui_SetNextWindowSize(ctx, 250, 280)
    local visible, open = r.ImGui_Begin(ctx, 'TK time selection loop color setup', true, r.ImGui_WindowFlags_NoResize() | r.ImGui_WindowFlags_NoScrollbar())
    
    if visible then
        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FramePadding(), 8, 4)
        
        r.ImGui_Text(ctx, 'Loop Color')
        -- Converteer BGR naar RGB voor de kleurenkiezer
        local rv, new_color = r.ImGui_ColorEdit3(ctx, '##loop_color', SwapRB(temp_loop_color))
        if rv then
            -- Converteer RGB terug naar BGR voor opslag
            temp_loop_color = SwapRB(new_color)
        end
        
        r.ImGui_Text(ctx, 'Default Color')
        local rv2, new_default = r.ImGui_ColorEdit3(ctx, '##default_color', SwapRB(temp_default_color))
        if rv2 then
            temp_default_color = SwapRB(new_default)
        end
        
        local cmd_id = GetMainScriptCommandID()
        local is_enabled = reaper.GetToggleCommandState(cmd_id) == 1
        local rv6, new_enabled = r.ImGui_Checkbox(ctx, 'Enable script', is_enabled)
        if rv6 and new_enabled ~= is_enabled then
            r.Main_OnCommand(cmd_id, 0)  -- Toggle the script
        end
        
        local rv3, new_link_state = r.ImGui_Checkbox(ctx, 'Link loop points to time selection', temp_link_state)
        if rv3 then
            temp_link_state = new_link_state
        end
        
        local rv4, new_only_loop = r.ImGui_Checkbox(ctx, 'Only loop color', temp_only_loop)
        if rv4 then
            temp_only_loop = new_only_loop
            if new_only_loop then 
                temp_only_arrange = false 
            end
        end
        
        local rv5, new_only_arrange = r.ImGui_Checkbox(ctx, 'Only arrange color', temp_only_arrange)
        if rv5 then
            temp_only_arrange = new_only_arrange
            if new_only_arrange then 
                temp_only_loop = false 
            end
        end
        
        local rv7, new_disco = r.ImGui_Checkbox(ctx, 'Disco mode', temp_disco_mode)
        if rv7 then
            temp_disco_mode = new_disco
        end
        
        if r.ImGui_Button(ctx, 'Apply') then
            loop_color = temp_loop_color
            default_color = temp_default_color
            only_loop = temp_only_loop
            only_arrange = temp_only_arrange
            disco_mode = temp_disco_mode
            SaveSettings(loop_color, default_color, only_loop, only_arrange, disco_mode)
            
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
