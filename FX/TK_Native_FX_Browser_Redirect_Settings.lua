-- @description TK Native FX Browser Redirect - Settings
-- @author TouristKiller
-- @version 1.3.0
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

local DEFAULTS = {
    script_path              = "TK Scripts/FX/TK_FX_BROWSER.lua",
    command_id               = "",
    action_name_match        = "TK_FX_BROWSER.lua",
    running_extstate_section = "TK_FX_BROWSER",
    running_extstate_key     = "running",
    visibility_extstate_key  = "visibility",
    ignore_titles            = "TK FX BROWSER\nTK FX Browser",
}

local PRESETS = {
    { name = "TK FX Browser",
      script_path = "TK Scripts/FX/TK_FX_BROWSER.lua", command_id = "",
      action_name = "TK_FX_BROWSER.lua",
      run_sect = "TK_FX_BROWSER", run_key = "running", vis_key = "visibility",
      ignore = "TK FX BROWSER\nTK FX Browser" },
    { name = "TK FX Browser Mini",
      script_path = "TK Scripts/FX/TK_FX_BROWSER Mini.lua", command_id = "",
      action_name = "TK_FX_BROWSER Mini.lua",
      run_sect = "TK_FX_BROWSER_MINI", run_key = "running", vis_key = "visibility",
      ignore = "TK FX BROWSER\nTK FX Browser" },
    { name = "Custom (manual)",
      script_path = "", command_id = "", action_name = "",
      run_sect = "", run_key = "", vis_key = "", ignore = "" },
}

local COLORS = {
    bg          = 0x141414FF,
    panel       = 0x1E1E1EFF,
    border      = 0x2E2E2EFF,
    accent      = 0xBFBFBFFF,
    accent_hi   = 0xE6E6E6FF,
    text        = 0xD0D0D0FF,
    text_dim    = 0x707070FF,
    success     = 0xA8A8A8FF,
    danger      = 0xC86464FF,
    warn        = 0xB89A5CFF,
    info        = 0x9A9A9AFF,
    btn         = 0x2A2A2AFF,
    btn_hi      = 0x3A3A3AFF,
    btn_act     = 0x4A4A4AFF,
    input       = 0x111111FF,
    input_hi    = 0x1A1A1AFF,
}

local function getCfg(key)
    local v = r.GetExtState(CONFIG_NS, key)
    if v == nil or v == "" then return DEFAULTS[key] end
    return v
end

local state = {
    script_path       = getCfg("script_path"),
    command_id        = getCfg("command_id"),
    action_name_match = getCfg("action_name_match"),
    run_sect          = getCfg("running_extstate_section"),
    run_key           = getCfg("running_extstate_key"),
    vis_key           = getCfg("visibility_extstate_key"),
    ignore_titles     = getCfg("ignore_titles"),
    preset_idx        = 0,
    status_msg        = "",
    status_color      = COLORS.info,
    status_time       = 0,
}

local function setStatus(msg, color)
    state.status_msg   = msg
    state.status_color = color or COLORS.info
    state.status_time  = r.time_precise()
end

local function saveAll()
    r.SetExtState(CONFIG_NS, "script_path",              state.script_path,       true)
    r.SetExtState(CONFIG_NS, "command_id",               state.command_id,        true)
    r.SetExtState(CONFIG_NS, "action_name_match",        state.action_name_match, true)
    r.SetExtState(CONFIG_NS, "running_extstate_section", state.run_sect,          true)
    r.SetExtState(CONFIG_NS, "running_extstate_key",     state.run_key,           true)
    r.SetExtState(CONFIG_NS, "visibility_extstate_key",  state.vis_key,           true)
    r.SetExtState(CONFIG_NS, "ignore_titles",            state.ignore_titles,     true)
    r.SetExtState(CONFIG_NS, "_changed", "1", false)
    setStatus("Settings saved.", COLORS.success)
end

local function applyPreset(p)
    state.script_path       = p.script_path
    state.command_id        = p.command_id
    state.action_name_match = p.action_name
    state.run_sect          = p.run_sect
    state.run_key           = p.run_key
    state.vis_key           = p.vis_key
    state.ignore_titles     = p.ignore
end

local function resetDefaults()
    state.script_path       = DEFAULTS.script_path
    state.command_id        = DEFAULTS.command_id
    state.action_name_match = DEFAULTS.action_name_match
    state.run_sect          = DEFAULTS.running_extstate_section
    state.run_key           = DEFAULTS.running_extstate_key
    state.vis_key           = DEFAULTS.visibility_extstate_key
    state.ignore_titles     = DEFAULTS.ignore_titles
    setStatus("Defaults restored (not yet saved).", COLORS.warn)
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
    end
end

local function testResolve()
    if state.command_id ~= "" then
        local c = r.NamedCommandLookup(state.command_id)
        if c and c ~= 0 then
            setStatus("Resolved via command ID.", COLORS.success); return
        end
    end
    local path = state.script_path
    if path ~= "" and not (path:match("^[A-Za-z]:[/\\]") or path:sub(1,1) == "/") then
        path = r.GetResourcePath() .. "/Scripts/" .. path
    end
    if path ~= "" and r.file_exists(path) then
        local c = r.AddRemoveReaScript(true, 0, path, true)
        if c and c ~= 0 then
            setStatus("Resolved via script path.", COLORS.success); return
        end
    end
    if state.action_name_match ~= "" and r.kbd_enumerateActions then
        local i = 0
        while true do
            local c, name = r.kbd_enumerateActions(0, i)
            if not c or c == 0 then break end
            if name and name:find(state.action_name_match, 1, true) then
                setStatus("Resolved via action name: " .. name, COLORS.success); return
            end
            i = i + 1
            if i > 50000 then break end
        end
    end
    setStatus("Could not resolve any alternative.", COLORS.danger)
end

local ctx = r.ImGui_CreateContext('TK FX Redirect Settings')
local FONT_SIZE  = 14
local font       = r.ImGui_CreateFont('sans-serif', FONT_SIZE)
local font_small = r.ImGui_CreateFont('sans-serif', FONT_SIZE - 2)
local font_title = r.ImGui_CreateFont('sans-serif', FONT_SIZE + 4)
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
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_PopupRounding(),     6)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowRounding(),    6)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ScrollbarRounding(), 4)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameBorderSize(),   0)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ChildBorderSize(),   1)

    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_WindowBg(),         COLORS.bg)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ChildBg(),          COLORS.panel)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_PopupBg(),          COLORS.panel)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Border(),           COLORS.border)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(),             COLORS.text)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_TextDisabled(),     COLORS.text_dim)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(),          COLORS.input)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgHovered(),   COLORS.input_hi)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgActive(),    COLORS.input_hi)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(),           COLORS.btn)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(),    COLORS.btn_hi)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(),     COLORS.btn_act)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Header(),           COLORS.btn)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderHovered(),    COLORS.btn_hi)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderActive(),     COLORS.btn_act)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Separator(),        COLORS.border)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_CheckMark(),        COLORS.accent)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_TitleBg(),          COLORS.panel)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_TitleBgActive(),    COLORS.panel)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_TitleBgCollapsed(), COLORS.panel)
end

local function popTheme()
    r.ImGui_PopStyleColor(ctx, 20)
    r.ImGui_PopStyleVar(ctx, 12)
end

local function sectionLabel(text)
    r.ImGui_PushFont(ctx, font_small, FONT_SIZE - 2)
    r.ImGui_TextColored(ctx, COLORS.accent, text:upper())
    r.ImGui_PopFont(ctx)
end

local function labeledInput(label, value, key)
    r.ImGui_AlignTextToFramePadding(ctx)
    r.ImGui_TextColored(ctx, COLORS.text_dim, label)
    r.ImGui_SameLine(ctx, 130)
    r.ImGui_SetNextItemWidth(ctx, -1)
    local _, nv = r.ImGui_InputText(ctx, "##" .. key, value)
    return nv
end

local function frame()
    local running = isMonitorRunning()

    r.ImGui_PushFont(ctx, font_title, FONT_SIZE + 4)
    r.ImGui_TextColored(ctx, COLORS.accent, "TK Native FX Browser Redirect")
    r.ImGui_PopFont(ctx)

    local win_w = r.ImGui_GetWindowWidth(ctx)
    r.ImGui_SameLine(ctx)
    r.ImGui_SetCursorPosX(ctx, win_w - 96)
    if running then
        r.ImGui_TextColored(ctx, COLORS.success, "● ACTIVE")
    else
        r.ImGui_TextColored(ctx, COLORS.danger, "● STOPPED")
    end

    r.ImGui_PushFont(ctx, font_small, FONT_SIZE - 2)
    r.ImGui_TextColored(ctx, COLORS.text_dim,
        "Replace REAPER's native FX browser with an alternative of your choice.")
    r.ImGui_PopFont(ctx)

    r.ImGui_Dummy(ctx, 0, 4)

    local NOSB = r.ImGui_WindowFlags_NoScrollbar() | r.ImGui_WindowFlags_NoScrollWithMouse()

    sectionLabel("Preset")
    if r.ImGui_BeginChild(ctx, "##preset_box", -1, 48, 1, NOSB) then
        r.ImGui_AlignTextToFramePadding(ctx)
        r.ImGui_TextColored(ctx, COLORS.text_dim, "Profile")
        r.ImGui_SameLine(ctx, 130)
        r.ImGui_SetNextItemWidth(ctx, -1)
        if r.ImGui_BeginCombo(ctx, "##preset", PRESETS[state.preset_idx + 1].name) then
            for i, p in ipairs(PRESETS) do
                local sel = (i - 1) == state.preset_idx
                if r.ImGui_Selectable(ctx, p.name, sel) then
                    state.preset_idx = i - 1
                    applyPreset(p)
                    setStatus("Preset loaded: " .. p.name .. " (not yet saved).", COLORS.warn)
                end
            end
            r.ImGui_EndCombo(ctx)
        end
        r.ImGui_EndChild(ctx)
    end

    r.ImGui_Dummy(ctx, 0, 2)
    sectionLabel("Alternative source")
    if r.ImGui_BeginChild(ctx, "##src_box", -1, 116, 1, NOSB) then
        state.script_path       = labeledInput("Script path",  state.script_path,       "sp")
        state.command_id        = labeledInput("Command ID",   state.command_id,        "ci")
        state.action_name_match = labeledInput("Action name",  state.action_name_match, "an")
        r.ImGui_EndChild(ctx)
    end

    r.ImGui_Dummy(ctx, 0, 2)
    sectionLabel("Already-running detection (optional)")
    if r.ImGui_BeginChild(ctx, "##det_box", -1, 116, 1, NOSB) then
        state.run_sect = labeledInput("ExtState section", state.run_sect, "rs")
        state.run_key  = labeledInput("Running key",      state.run_key,  "rk")
        state.vis_key  = labeledInput("Visibility key",   state.vis_key,  "vk")
        r.ImGui_EndChild(ctx)
    end

    r.ImGui_Dummy(ctx, 0, 2)
    sectionLabel("Ignore windows  ·  one substring per line")
    if r.ImGui_BeginChild(ctx, "##ign_box", -1, 92, 1, NOSB) then
        local _
        _, state.ignore_titles = r.ImGui_InputTextMultiline(ctx, "##ignore",
            state.ignore_titles, -1, -1)
        r.ImGui_EndChild(ctx)
    end

    r.ImGui_Dummy(ctx, 0, 4)

    local btn_h = 26
    if r.ImGui_Button(ctx, "Save", 90, btn_h) then saveAll() end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Defaults", 90, btn_h) then resetDefaults() end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Test", 70, btn_h) then testResolve() end
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
    local lbl = running and "Stop monitor" or "Start monitor"
    if r.ImGui_Button(ctx, lbl, rest_w, btn_h) then toggleMonitor() end
    r.ImGui_PopStyleColor(ctx, 3)

    r.ImGui_Dummy(ctx, 0, 2)
    r.ImGui_Separator(ctx)
    r.ImGui_PushFont(ctx, font_small, FONT_SIZE - 2)
    if state.status_msg ~= "" and (r.time_precise() - state.status_time) < 5.0 then
        r.ImGui_TextColored(ctx, state.status_color, state.status_msg)
    else
        r.ImGui_TextColored(ctx, COLORS.text_dim, "Ready.")
    end
    r.ImGui_PopFont(ctx)
end

local function loop()
    pushTheme()
    r.ImGui_PushFont(ctx, font, FONT_SIZE)
    r.ImGui_SetNextWindowSize(ctx, 400, 700, r.ImGui_Cond_Always())
    local win_flags = r.ImGui_WindowFlags_NoScrollbar()
                    | r.ImGui_WindowFlags_NoScrollWithMouse()
                    | r.ImGui_WindowFlags_NoResize()
                    | r.ImGui_WindowFlags_NoCollapse()
    local visible, open = r.ImGui_Begin(ctx, 'TK Native FX Browser Redirect - Settings', true, win_flags)
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
