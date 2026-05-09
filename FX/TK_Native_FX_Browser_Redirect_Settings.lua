-- @description TK Native FX Browser Redirect - Settings
-- @author TouristKiller
-- @version 1.4.1
-- @about
--   Configuration window for TK Native FX Browser Redirect.

local r = reaper

if not r.ImGui_CreateContext then
    r.MB("This action requires ReaImGui.\nInstall it via ReaPack.", "TK FX Redirect Settings", 0)
    return
end

local CONFIG_NS    = "TK_FX_REDIRECT_CONFIG"
local MONITOR_NS   = "TK_FX_REDIRECT"
local MONITOR_PATH = r.GetResourcePath() .. "/Scripts/TK Scripts/FX/TK_Native_FX_Browser_Redirect.lua"

local COLORS = {
    bg        = 0x141414FF,
    panel     = 0x1E1E1EFF,
    border    = 0x2E2E2EFF,
    accent    = 0xBFBFBFFF,
    text      = 0xD0D0D0FF,
    text_dim  = 0x707070FF,
    success   = 0xA8A8A8FF,
    danger    = 0xC86464FF,
    warn      = 0xB89A5CFF,
    info      = 0x9A9A9AFF,
    btn       = 0x2A2A2AFF,
    btn_hi    = 0x3A3A3AFF,
    btn_act   = 0x4A4A4AFF,
    input     = 0x111111FF,
    input_hi  = 0x1A1A1AFF,
}

local function trim(s)
    return (s or ""):match("^%s*(.-)%s*$")
end

local function getCommandID()
    return r.GetExtState(CONFIG_NS, "command_id") or ""
end

local state = {
    command_id   = getCommandID(),
    status_msg   = "",
    status_color = COLORS.info,
    status_time  = 0,
}

local function setStatus(msg, color)
    state.status_msg   = msg
    state.status_color = color or COLORS.info
    state.status_time  = r.time_precise()
end

local function resolveCommandID(command_id)
    command_id = trim(command_id)
    if command_id == "" then return 0 end

    local numeric = tonumber(command_id)
    if numeric and numeric ~= 0 then return numeric end

    local cmd = r.NamedCommandLookup(command_id)
    if cmd and cmd ~= 0 then return cmd end

    return 0
end

local function saveSettings()
    state.command_id = trim(state.command_id)
    r.SetExtState(CONFIG_NS, "command_id", state.command_id, true)
    r.SetExtState(CONFIG_NS, "_changed", "1", false)
    setStatus("Command ID saved.", COLORS.success)
end

local function clearSettings()
    state.command_id = ""
    r.SetExtState(CONFIG_NS, "command_id", "", true)
    r.SetExtState(CONFIG_NS, "_changed", "1", false)
    setStatus("Command ID cleared.", COLORS.warn)
end

local function isMonitorRunning()
    return r.GetExtState(MONITOR_NS, "running") == "true"
end

local function toggleMonitor()
    if not r.file_exists(MONITOR_PATH) then
        setStatus("Monitor script not found.", COLORS.danger)
        return
    end

    local cmd = r.AddRemoveReaScript(true, 0, MONITOR_PATH, true)
    if cmd and cmd ~= 0 then
        r.Main_OnCommand(cmd, 0)
    else
        setStatus("Could not start monitor.", COLORS.danger)
    end
end

local function testCommandID()
    local cmd = resolveCommandID(state.command_id)
    if cmd ~= 0 then
        setStatus("Command ID resolved: " .. tostring(cmd), COLORS.success)
    else
        setStatus("Command ID could not be resolved.", COLORS.danger)
    end
end

local ctx = r.ImGui_CreateContext("TK FX Redirect Settings")
local FONT_SIZE  = 14
local font       = r.ImGui_CreateFont("sans-serif", FONT_SIZE)
local font_small = r.ImGui_CreateFont("sans-serif", FONT_SIZE - 2)
local font_title = r.ImGui_CreateFont("sans-serif", FONT_SIZE + 4)
r.ImGui_Attach(ctx, font)
r.ImGui_Attach(ctx, font_small)
r.ImGui_Attach(ctx, font_title)

local function pushTheme()
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(),    12, 12)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FramePadding(),      8,  4)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing(),       8,  6)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ItemInnerSpacing(),  6,  4)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(),     4)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_GrabRounding(),      4)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ChildRounding(),     6)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowRounding(),    6)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameBorderSize(),   0)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ChildBorderSize(),   1)

    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_WindowBg(),         COLORS.bg)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ChildBg(),          COLORS.panel)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Border(),           COLORS.border)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(),             COLORS.text)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_TextDisabled(),     COLORS.text_dim)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(),          COLORS.input)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgHovered(),   COLORS.input_hi)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgActive(),    COLORS.input_hi)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(),           COLORS.btn)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(),    COLORS.btn_hi)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(),     COLORS.btn_act)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Separator(),        COLORS.border)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_TitleBg(),          COLORS.panel)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_TitleBgActive(),    COLORS.panel)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_TitleBgCollapsed(), COLORS.panel)
end

local function popTheme()
    r.ImGui_PopStyleColor(ctx, 15)
    r.ImGui_PopStyleVar(ctx, 10)
end

local function frame()
    local running = isMonitorRunning()

    r.ImGui_PushFont(ctx, font_title, FONT_SIZE + 4)
    r.ImGui_TextColored(ctx, COLORS.accent, "TK Native FX Browser Redirect")
    r.ImGui_PopFont(ctx)

    local win_w = r.ImGui_GetWindowWidth(ctx)
    r.ImGui_SameLine(ctx)
    r.ImGui_SetCursorPosX(ctx, win_w - 92)
    r.ImGui_TextColored(ctx, running and COLORS.success or COLORS.danger,
        running and "ACTIVE" or "STOPPED")

    r.ImGui_PushFont(ctx, font_small, FONT_SIZE - 2)
    r.ImGui_TextColored(ctx, COLORS.text_dim, "Set the command ID for the alternative FX browser action.")
    r.ImGui_PopFont(ctx)

    r.ImGui_Dummy(ctx, 0, 6)

    local NOSB = r.ImGui_WindowFlags_NoScrollbar() | r.ImGui_WindowFlags_NoScrollWithMouse()
    if r.ImGui_BeginChild(ctx, "##command_box", -1, 62, 1, NOSB) then
        r.ImGui_AlignTextToFramePadding(ctx)
        r.ImGui_TextColored(ctx, COLORS.text_dim, "Command ID")
        r.ImGui_SameLine(ctx, 110)
        r.ImGui_SetNextItemWidth(ctx, -1)
        local _, value = r.ImGui_InputText(ctx, "##command_id", state.command_id)
        state.command_id = value
        r.ImGui_EndChild(ctx)
    end

    r.ImGui_Dummy(ctx, 0, 4)

    local btn_h = 26
    if r.ImGui_Button(ctx, "Save", 82, btn_h) then saveSettings() end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Clear", 82, btn_h) then clearSettings() end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Test", 72, btn_h) then testCommandID() end
    r.ImGui_SameLine(ctx)

    local rest_w = r.ImGui_GetContentRegionAvail(ctx)
    if running then
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(),        0x4A2A2AFF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0x5E3636FF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(),  0x704040FF)
    else
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(),        0x3A3A3AFF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0x4A4A4AFF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(),  0x5A5A5AFF)
    end
    if r.ImGui_Button(ctx, running and "Stop monitor" or "Start monitor", rest_w, btn_h) then
        toggleMonitor()
    end
    r.ImGui_PopStyleColor(ctx, 3)

    r.ImGui_Dummy(ctx, 0, 8)
    r.ImGui_Separator(ctx)
    if r.ImGui_BeginChild(ctx, "##status_box", -1, 44, 0, NOSB) then
        r.ImGui_PushFont(ctx, font_small, FONT_SIZE - 2)
        if state.status_msg ~= "" and (r.time_precise() - state.status_time) < 5.0 then
            r.ImGui_TextColored(ctx, state.status_color, state.status_msg)
        else
            r.ImGui_TextColored(ctx, COLORS.text_dim, "Ready.")
        end
        r.ImGui_PopFont(ctx)
        r.ImGui_EndChild(ctx)
    end
end

local last_frame = 0
local MIN_FRAME_INTERVAL = 1 / 30

local function loop()
    local now = r.time_precise()
    if now - last_frame < MIN_FRAME_INTERVAL then
        r.defer(loop)
        return
    end
    last_frame = now

    pushTheme()
    r.ImGui_PushFont(ctx, font, FONT_SIZE)
    r.ImGui_SetNextWindowSize(ctx, 460, 285, r.ImGui_Cond_Always())
    local win_flags = r.ImGui_WindowFlags_NoScrollbar()
                    | r.ImGui_WindowFlags_NoScrollWithMouse()
                    | r.ImGui_WindowFlags_NoResize()
                    | r.ImGui_WindowFlags_NoCollapse()
    local visible, open = r.ImGui_Begin(ctx, "TK Native FX Browser Redirect - Settings", true, win_flags)
    if visible then
        frame()
        r.ImGui_End(ctx)
    end
    r.ImGui_PopFont(ctx)
    popTheme()

    if open then
        r.defer(loop)
    end
end

r.defer(loop)
