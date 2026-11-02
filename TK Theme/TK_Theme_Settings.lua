-- @description TK Theme: settings
-- @author TouristKiller
-- @version 0.9.6
-- The theme's own settings window, in place of the Default 7 Theme Adjuster
-- (rtconfig.txt names it with adjuster_script). Its colours are read from the
-- loaded theme, so it follows whatever the theme looks like.
--   Layout pages   ThemeLayout parameters, applied live
--   Colours        SetThemeColor live, written to the .ReaperTheme on Save
--   Dark mode      win32_darkmode(_colors) in reaper.ini, read by REAPER at startup
--   Reset          everything above back to how the theme comes, and undoing that
local r = reaper

if not r.ImGui_CreateContext then
    r.ShowMessageBox("This window needs ReaImGui (install it with ReaPack).", "TK Theme Settings", 0)
    return
end

-- PushFont takes a size since ReaImGui 0.10; older versions would stop with an error
do
    local _, _, version = r.ImGui_GetVersion()
    local major, minor = tostring(version):match("^(%d+)%.(%d+)")
    if not major or tonumber(major) == 0 and tonumber(minor) < 10 then
        r.ShowMessageBox("This window needs ReaImGui 0.10 or newer (found " .. tostring(version)
            .. "). Update it with ReaPack.", "TK Theme Settings", 0)
        return
    end
end

local SCRIPT = "TK Theme Settings"
local IS_WINDOWS = r.GetOS():find("Win", 1, true) ~= nil    -- dark mode colours exist only there
local here = debug.getinfo(1, "S").source:match("^@(.*[\\/])")
local ini = r.get_ini_file()
local undo_dir = r.GetResourcePath() .. "/Data/TK Theme/last_reset"
local LISTS_SECTION = "TK_Theme_TCP_Lists"      -- shared with TK_Theme_Toggle_TCP_Lists.lua
local THEME_DARKMODE = "252930 2f343c a3cad8 3a5662 252930 252930 16191e 0a1115 a3cad8 567581 050608 "
    .. "2f343c 2f343c 252930 a3cad8 c6f1ff 16191e 2f343c 252930 21516d 2f343c 1f2329 36b9ff"

local ctx = r.ImGui_CreateContext(SCRIPT)
local font = r.ImGui_CreateFont(IS_WINDOWS and "Bahnschrift" or "sans-serif")
r.ImGui_Attach(ctx, font)

-- ---------------------------------------------------------------- files

local function read_all(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local s = f:read("a")
    f:close()
    return s
end

local function write_all(path, s)
    local f = io.open(path, "wb")
    if not f then return false end
    f:write(s)
    f:close()
    return true
end

local function ini_get(key)
    return (read_all(ini) or ""):match("[\r\n]" .. key .. "=([^\r\n]*)")
end

-- value nil removes the key; a new key goes straight under [reaper]
local function ini_set(key, value)
    local s = read_all(ini)
    if not s then return false end
    local line = "([\r\n])" .. key .. "=[^\r\n]*"
    if s:find(line) then
        if value then
            s = s:gsub(line, function(c) return c .. key .. "=" .. value end, 1)
        else
            s = s:gsub("[\r\n]+" .. key .. "=[^\r\n]*", "", 1)
        end
    elseif value then
        local eol = s:find("\r\n", 1, true) and "\r\n" or "\n"
        local _, stop = s:lower():find("%[reaper%][\r\n]+")
        if not stop then return false end
        s = s:sub(1, stop) .. key .. "=" .. value .. eol .. s:sub(stop + 1)
    end
    return write_all(ini, s)
end

-- the theme's editable colour file; a zip can't be written, its loose copy can
local function theme_file()
    local path = r.GetLastColorThemeFile() or ""
    path = path:gsub("Zip$", "")
    if path:match("%.ReaperTheme$") and read_all(path) then return path end
    return nil
end

-- ---------------------------------------------------------------- colours

local function rgba(rgb, a)
    return (rgb << 8) | (a or 255)
end

local function rgb_from_hex(hex)
    return tonumber(hex, 16) or 0
end

local function native_to_rgb(c)
    local R, G, B = r.ColorFromNative(c & 0xFFFFFF)
    return (R << 16) | (G << 8) | B
end

local function rgb_to_native(rgb)
    return r.ColorToNative((rgb >> 16) & 255, (rgb >> 8) & 255, rgb & 255)
end

local function mix(a, b, t)
    local out = 0
    for shift = 16, 0, -8 do
        local x, y = (a >> shift) & 255, (b >> shift) & 255
        out = out | (math.floor(x + (y - x) * t + 0.5) << shift)
    end
    return out
end

local function theme_rgb(key, fallback)
    local c = r.GetThemeColor(key, 0)
    if not c or c == -1 then return fallback end
    return native_to_rgb(c)
end

local UI = {}
local function refresh_palette()
    UI.panel = theme_rgb("col_main_bg2", 0x252930)
    UI.base = theme_rgb("col_tracklistbg", 0x16191E)
    UI.raised = theme_rgb("col_seltrack", 0x2F343C)
    UI.glass = theme_rgb("col_main_editbk", 0x0A1115)
    UI.ink = theme_rgb("genlist_selfg", 0xC6F1FF)
    UI.text = theme_rgb("genlist_fg", 0xA3CAD8)
    UI.dim = theme_rgb("col_tl_fg2", 0x3A5662)
    UI.accent = theme_rgb("genlist_hilite", 0x36B9FF)
    UI.soft = mix(UI.dim, UI.ink, 0.45)
    UI.warn = 0xFFB22E
end

local function push_theme()
    local c = {
        WindowBg = UI.panel, ChildBg = UI.base, PopupBg = UI.base, Border = UI.raised,
        FrameBg = UI.glass, FrameBgHovered = mix(UI.glass, UI.ink, 0.08), FrameBgActive = mix(UI.glass, UI.ink, 0.14),
        TitleBg = UI.panel, TitleBgActive = UI.panel, TitleBgCollapsed = UI.panel,
        Text = UI.text, TextDisabled = UI.soft,
        Button = UI.raised, ButtonHovered = mix(UI.raised, UI.ink, 0.15), ButtonActive = mix(UI.raised, UI.accent, 0.4),
        SliderGrab = UI.ink, SliderGrabActive = UI.accent,
        Header = UI.raised, HeaderHovered = mix(UI.raised, UI.ink, 0.1), HeaderActive = mix(UI.raised, UI.accent, 0.3),
        ScrollbarBg = UI.base, ScrollbarGrab = UI.raised, ScrollbarGrabHovered = mix(UI.raised, UI.ink, 0.15),
        ScrollbarGrabActive = UI.accent, Separator = UI.raised, CheckMark = UI.accent,
        ResizeGrip = UI.raised, ResizeGripHovered = mix(UI.raised, UI.ink, 0.15), ResizeGripActive = UI.accent,
    }
    local n = 0
    for name, col in pairs(c) do
        local fn = r["ImGui_Col_" .. name]
        if fn then
            r.ImGui_PushStyleColor(ctx, fn(), rgba(col))
            n = n + 1
        end
    end
    local v = {
        { r.ImGui_StyleVar_WindowRounding(), 6 }, { r.ImGui_StyleVar_ChildRounding(), 6 },
        { r.ImGui_StyleVar_FrameRounding(), 4 }, { r.ImGui_StyleVar_GrabRounding(), 8 },
        { r.ImGui_StyleVar_GrabMinSize(), 12 }, { r.ImGui_StyleVar_ScrollbarSize(), 10 },
    }
    for _, sv in ipairs(v) do r.ImGui_PushStyleVar(ctx, sv[1], sv[2]) end
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing(), 8, 7)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FramePadding(), 7, 4)
    return n, #v + 2
end

-- ---------------------------------------------------------------- parameters

local P, order = {}, {}
local function load_params()
    P, order = {}, {}
    local i = 0
    while true do
        local name, desc, value, def, min, max = r.ThemeLayout_GetParameter(i)
        if not name then break end
        P[name] = { idx = i, desc = desc, value = value or 0, def = def or 0, min = min or 0, max = max or 1 }
        order[#order + 1] = name
        i = i + 1
    end
end

-- the track panel page sets one layout at a time, chosen at the top of that page
local THIS_LAYOUT = "*"
local tcp_layout = "A"

local function expand(param, layouts, also)
    if not layouts then return { param } end
    if layouts == THIS_LAYOUT then layouts = tcp_layout end
    local out = {}
    for lay in layouts:gmatch(".") do
        out[#out + 1] = "Layout" .. lay .. "-" .. param
        for _, more in ipairs(also or {}) do out[#out + 1] = "Layout" .. lay .. "-" .. more end
    end
    return out
end

local state = { page = 1, restart = false, msg = nil, confirm = nil, factory_dark = false }

local function set_param(name, value, persist)
    local p = P[name]
    if not p then return end
    p.value = value
    r.ThemeLayout_SetParameter(p.idx, value, persist)
end

-- ---------------------------------------------------------------- pages

local function S(label, param, layouts, hint) return { kind = "slider", label = label, param = param, layouts = layouts, hint = hint } end
-- one slider for a setting that exists once more for selected and armed strips
local function Grow(label, param, also) return { kind = "slider", label = label, param = param, layouts = THIS_LAYOUT, also = also } end
local function T(label, param, layouts, hint, invert) return { kind = "toggle", label = label, param = param, layouts = layouts, hint = hint, invert = invert } end
-- a transport button that can run an action of the user's choice instead
local function B(label, key, free) return { kind = "button", label = label, param = "tkBtn_" .. key, key = key, free = free } end
-- a transport button with a fixed action: off, or in the left or right window
local function N(label, key, hint) return { kind = "place", label = label, param = "tkBtn_" .. key, hint = hint } end
local ALL = "ABC"

-- a setting that doesn't count at the moment shows grey and can't be changed
local function Off(when, item)
    item.off = when
    return item
end
local function lay_value(name)
    local p = P["Layout" .. tcp_layout .. "-" .. name]
    return p and p.value ~= 0
end
local function global_value(name)
    local p = P[name]
    return p and p.value ~= 0
end
local function lay_on(...)
    local names = { ... }
    return function()
        for _, n in ipairs(names) do
            if lay_value(n) then return true end
        end
        return false
    end
end
-- off while `need` is off, or while `other` is on
local function lay_off_or(need, other)
    return function() return not lay_value(need) or lay_value(other) end
end
local function lay_all_or(all, other)
    return function()
        if lay_value(other) then return true end
        for _, n in ipairs(all) do
            if not lay_value(n) then return false end
        end
        return true
    end
end
local function no_sidebar()
    return not (lay_value("mcpSidebar") or lay_value("mcpSidebarSel") or lay_value("mcpSidebarRecarm"))
end
-- 1 narrow, 2 intermediate, 3 normal: the width decides, as in the theme
local function not_form(form)
    return function()
        local p = P["Layout" .. tcp_layout .. "-mcpWidth"]
        local width = p and p.value or 0
        local current = width < 52 and 1 or width < 88 and 2 or 3
        return current ~= form
    end
end
local function global_on(...)
    local names = { ... }
    return function()
        for _, n in ipairs(names) do
            if global_value(n) then return true end
        end
        return false
    end
end
local function global_off_or(need, other)
    return function() return not global_value(need) or global_value(other) end
end

local PAGES = {
    { title = "General", cards = {
        { "Tracks and strips", {
            S("Track colour strength", "customColorDepthParam", nil, "How much of the track colour tints panels and rims."),
            S("Selection strength", "selectStrength", nil, "How much a selected track lightens."),
            T("Track names in track colour", "colorTrackLabels"),
            T("Selection dot", "selDot", nil, "The small dot on the track number."),
        } },
        { "Text and spacing", {
            S("Text brightness", "textBrightness"),
        } },
        { "Main window", {
            { kind = "menubar", label = "Menu bar",
              hint = "Give the action TK_Theme_Toggle_Menu_Bar a shortcut to do this from the keyboard. The menu bar comes back when REAPER restarts." },
        } },
        { "Transport", {
            { kind = "startup", label = "Metronome light at startup",
              hint = "Without it the metronome button shows its state after the first click. Adds one line to Scripts/__startup.lua; switching it off removes that line again." },
        } },
    } },
    { title = "Track panel", cards = {
        { "All tracks", {
            S("Section margins", "sectionMargin", nil, "Space around the windows, in track panels and envelope lanes. Clicking between or in the windows selects the track."),
            S("Folder indent", "tcpfolderIndentSize"),
        } },
        { "Per layout", {
            { kind = "layout", label = "Layout", hint = "These settings are for the tracks on this layout. Set a track's layout in its right-click menu. The columns and meter buttons in a track panel change them too, for that track's layout." },
            T("Name only", "tkNameOnly", THIS_LAYOUT, "Just the track's name, large and centred, for a divider or a folder."),
            Off(lay_on("tkNameOnly"), T("Volume", "tkHideVol", THIS_LAYOUT, nil, true)),
            Off(lay_on("tkNameOnly"), T("Pan", "tkHidePan", THIS_LAYOUT, nil, true)),
            Off(lay_on("tkNameOnly"), T("Input row", "tkHideInput", THIS_LAYOUT, nil, true)),
            Off(lay_on("tkNameOnly"), T("Button row", "tkHideButtons", THIS_LAYOUT, nil, true)),
            Off(lay_on("tkNameOnly"), T("Mute and solo", "tkHideMs", THIS_LAYOUT, nil, true)),
            Off(lay_on("tkNameOnly", "tkHideMs"), T("Mute and solo on the left", "tkMsLeft", THIS_LAYOUT)),
            Off(lay_on("tkNameOnly"), T("Record arm and monitor", "tkHideArm", THIS_LAYOUT, nil, true)),
            Off(lay_on("tkNameOnly"), T("FX column", "tkNoFxCol", THIS_LAYOUT, "Without its column, the FX button moves to the first row.", true)),
            Off(lay_on("tkNameOnly"), T("IO column", "tkNoIoCol", THIS_LAYOUT, "Without its column, the IO button moves to the first row.", true)),
            Off(lay_off_or("tkNoFxCol", "tkNameOnly"), T("FX button", "tkHideFxBtn", THIS_LAYOUT, nil, true)),
            Off(lay_off_or("tkNoIoCol", "tkNameOnly"), T("IO button", "tkHideIoBtn", THIS_LAYOUT, nil, true)),
            Off(lay_all_or({ "tkNoFxCol", "tkNoIoCol" }, "tkNameOnly"), S("Column width", "sectionRightW", THIS_LAYOUT, "The FX and IO columns share this width.")),
            Off(lay_on("tkNameOnly"), T("Meter", "tkHideMeter", THIS_LAYOUT, nil, true)),
            Off(lay_on("tkNameOnly", "tkHideMeter"), T("Meter on the left", "tkMeterLeft", THIS_LAYOUT)),
            Off(lay_on("tkNameOnly", "tkHideMeter"), S("Meter width", "tcpMeterWidth", THIS_LAYOUT)),
            Off(lay_on("tkNameOnly"), S("Name size", "tcpLabelSize", THIS_LAYOUT)),
            Off(lay_on("tkNameOnly", "tkHideInput"), S("Input text size", "tcpInputFontSize", THIS_LAYOUT)),
        } },
        { "Selected tracks", {
            { kind = "tracks", hint = "Saved per track, in the project. Moving the slider changes nothing until you click a button, so a new track on a layout gets its height the next time you click. Make divider needs Name only on that layout. Layout A includes tracks on the default layout. REAPER's zoom actions leave a locked track's height alone." },
        } },
        { "Master", {
            T("Only a meter", "tkMasterMeterOnly", nil, "The whole master becomes one big meter."),
            Off(global_on("tkMasterMeterOnly"), T("Meter", "tkMasterHideMeter", nil, nil, true)),
            Off(global_on("tkMasterMeterOnly"), T("Volume", "tkMasterHideVol", nil, nil, true)),
            Off(global_on("tkMasterMeterOnly"), T("Pan", "tkMasterHidePan", nil, nil, true)),
            Off(global_on("tkMasterMeterOnly"), T("Mute and solo", "tkMasterHideMs", nil, nil, true)),
            Off(global_on("tkMasterMeterOnly"), T("FX column", "tkMasterNoFx", nil, "Without its column, the FX button moves to the first row.", true)),
            Off(global_on("tkMasterMeterOnly"), T("IO column", "tkMasterNoIo", nil, "Without its column, the IO button moves to the first row.", true)),
            Off(global_off_or("tkMasterNoFx", "tkMasterMeterOnly"), T("FX button", "tkMasterHideFxBtn", nil, nil, true)),
            Off(global_off_or("tkMasterNoIo", "tkMasterMeterOnly"), T("IO button", "tkMasterHideIoBtn", nil, nil, true)),
            Off(global_on("tkMasterMeterOnly", "tkMasterHideMeter"), T("Meter on the left", "tkMasterMeterLeft")),
            Off(global_on("tkMasterMeterOnly", "tkMasterHideMeter"), S("Meter width", "tkMasterMeterW", nil, "0 follows the tracks on layout A. Any other width no longer lines up with them.")),
        } },
    } },
    { title = "Mixer", cards = {
        { "Fader", {
            { kind = "handle", label = "Handle", hint = "For all layouts. A project opened later follows the next time this window opens." },
        } },
        { "Per layout", {
            { kind = "layout", label = "Layout", hint = "These settings are for the strips on this layout. Layout A is the standard strip, B the narrow one, and C has a sidebar and more values. Set a track's layout in its right-click menu." },
            S("Width", "mcpWidth", THIS_LAYOUT, "Under 52 this is a narrow strip, under 88 an intermediate one, from 88 a normal one."),
            S("Width when selected", "mcpWidthSel", THIS_LAYOUT), S("Width when armed", "mcpWidthRecarm", THIS_LAYOUT),
            Grow("Wider per channel", "mcpNchanGrow", { "mcpNchanGrowSel", "mcpNchanGrowRecarm" }),
            S("Name size", "mcpLabelSize", THIS_LAYOUT),
            T("More values", "verboseMcp", THIS_LAYOUT, "Such as the volume in dB above the fader."),
        } },
        { "Sidebar", {
            T("Sidebar", "mcpSidebar", THIS_LAYOUT, "The FX and send lists beside the strip instead of above it."),
            T("Sidebar when selected", "mcpSidebarSel", THIS_LAYOUT), T("Sidebar when armed", "mcpSidebarRecarm", THIS_LAYOUT),
            Off(no_sidebar, S("Sidebar width", "sidebarWidth", THIS_LAYOUT)),
            Off(no_sidebar, S("Sidebar columns", "tkSidebarCols", THIS_LAYOUT, "For the FX and send lists. More columns need a wider sidebar.")),
        } },
        { "Buttons", {
            T("I/O button", "mcpNormalShowRoute", THIS_LAYOUT), T("FX buttons", "mcpNormalShowSecFx", THIS_LAYOUT),
            T("Envelope button", "mcpNormalShowEnv", THIS_LAYOUT), T("Phase button", "mcpNormalShowPhase", THIS_LAYOUT),
        } },
        { "Meter", {
            T("Peak readout", "mcpMeterReadout", THIS_LAYOUT), T("Scale", "mcpMeterVals", THIS_LAYOUT),
            T("Scale when selected", "mcpMeterValsSel", THIS_LAYOUT), T("Scale when armed", "mcpMeterValsRecarm", THIS_LAYOUT),
        } },
        { "Normal strip", {
            Off(not_form(3), S("Show input from height", "mcpNormalShowSecIn", THIS_LAYOUT, "A lower mixer drops the input window.")),
            Off(not_form(3), S("Show pan from height", "mcpNormalShowSecPan", THIS_LAYOUT, "A lower mixer drops the pan window.")),
        } },
        { "Intermediate strip", {
            Off(not_form(2), S("Show input from height", "mcpInterShowSecIn", THIS_LAYOUT)),
            Off(not_form(2), S("Show buttons from height", "mcpInterShowSecButtons", THIS_LAYOUT)),
            Off(not_form(2), S("Show pan from height", "mcpInterShowSecPan", THIS_LAYOUT)),
        } },
        { "Narrow strip", {
            Off(not_form(1), S("Name height", "mcpStripLabelHeight", THIS_LAYOUT)),
            Off(not_form(1), S("Input height", "mcpStripInputHeight", THIS_LAYOUT)),
            Off(not_form(1), S("Meter height", "mcpStripMeterHeight", THIS_LAYOUT)),
            Off(not_form(1), S("Volume height", "mcpStripVolumeHeight", THIS_LAYOUT)),
            Off(not_form(1), T("FX and send lists", "mcpStripHideExtmixer", THIS_LAYOUT, nil, true)),
        } },
        { "All strips", {
            S("Folder indent", "mcpfolderIndentSize"),
        } },
        { "Master", {
            S("Width", "masterMcpWidth"), T("Volume and pan values", "masterMcpVals"),
            T("Name", "masterMcpLabels"), T("Meter values", "masterMcpMeterVals"),
        } },
    } },
    { title = "Envelopes", cards = {
        { "Envelope lanes", {
            T("Show value", "showEnvValue"), T("Follow the track's indent", "indentEnvcp"),
            S("Name length", "envcpLabelLength"), S("Fader length", "envcpFaderLength"), S("Name size", "envcpFontSize"),
        } },
    } },
    { title = "Transport buttons", cards = {
        { "Button windows", {
            T("Left window at the far left", "tkBtnLeftEdge", nil, "Otherwise it sits right beside the transport buttons. Only when the transport is centred."),
            T("Right window at the far right", "tkBtnRightEdge", nil, "Otherwise it sits right beside the readouts."),
        } },
        { "Transport", {
            N("Metronome", "metro", "With a small arrow beside it for the metronome and pre-roll settings."),
        } },
        { "Project", {
            N("New project", "new"), N("Open project", "open"), N("Save project", "save"),
            N("Render", "render"), N("Project settings", "projset"), N("Preferences", "prefs"),
            N("Quit REAPER", "quit"),
        } },
        { "Windows", {
            B("Mixer", "mixer"), B("Media Explorer", "explorer"), B("FX Browser", "fxbrowser"),
            B("Track Manager", "trackmgr"), B("Project Bay", "bay"), B("Big clock", "clock"),
            B("Actions", "actions"), B("Routing matrix", "routing"), B("Region/marker manager", "regions"),
            B("Virtual MIDI keyboard", "vkb"), N("Master track in the track panel", "master"),
        } },
        { "Your own actions", {
            B("Button 1", "free1", true), B("Button 2", "free2", true), B("Button 3", "free3", true),
        } },
        { "Editing", {
            N("Cycle ripple editing", "ripple"), N("Undo", "undo"), N("Redo", "redo"),
        } },
    } },
    { title = "Colours", draw = "colours" },
    { title = "Colour processing", draw = "processing" },
    { title = "Dark mode", draw = "darkmode" },
    { title = "Presets", draw = "presets" },
    { title = "Reset", draw = "reset" },
    { title = "Guide", draw = "guide" },
}
if not IS_WINDOWS then
    for i, page in ipairs(PAGES) do
        if page.draw == "darkmode" then
            table.remove(PAGES, i)
            break
        end
    end
end

-- ---------------------------------------------------------------- widgets

local LABEL_W, CONTROL_W = 230, 280

local function hint_text(hint)
    if not hint then return end
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), rgba(UI.soft))
    r.ImGui_TextWrapped(ctx, hint)
    r.ImGui_PopStyleColor(ctx)
end

local function toggle(id, on)
    local W, H = 36, 18
    r.ImGui_PushID(ctx, id)
    local clicked = r.ImGui_InvisibleButton(ctx, "##switch", W, H)
    r.ImGui_PopID(ctx)
    local hovered = r.ImGui_IsItemHovered(ctx)
    local x, y = r.ImGui_GetItemRectMin(ctx)
    local dl = r.ImGui_GetWindowDrawList(ctx)
    local back = on and UI.accent or (hovered and mix(UI.raised, UI.ink, 0.15) or UI.raised)
    r.ImGui_DrawList_AddRectFilled(dl, x, y, x + W, y + H, rgba(back), H / 2)
    local knob = on and (x + W - H / 2) or (x + H / 2)
    r.ImGui_DrawList_AddCircleFilled(dl, knob, y + H / 2, H / 2 - 3, rgba(on and UI.glass or UI.ink))
    return clicked
end

local function row_label(label)
    r.ImGui_AlignTextToFramePadding(ctx)
    r.ImGui_Text(ctx, label)
    r.ImGui_SameLine(ctx, LABEL_W)
end

-- the metronome button's watcher in Scripts/__startup.lua, so the button is right
-- from the moment REAPER starts; only our own lines are ever added or removed
local startup_file = r.GetResourcePath() .. "/Scripts/__startup.lua"
local startup = {}

local function watcher_id()
    local path = here .. "TK_Theme_Metronome_Watch.lua"
    if not read_all(path) then return nil end
    local cmd = r.AddRemoveReaScript(true, 0, path, true)
    if not cmd or cmd <= 0 then return nil end
    local name = r.ReverseNamedCommandLookup(cmd)
    return name and ("_" .. name), cmd
end

local function load_startup()
    local id = watcher_id()
    startup.id = id
    startup.on = id ~= nil and (read_all(startup_file) or ""):find(id, 1, true) ~= nil
end

local function set_startup(on)
    local id, cmd = watcher_id()
    if not id then
        state.msg = "TK_Theme_Metronome_Watch.lua wasn't found next to this script."
        return
    end
    local s = read_all(startup_file) or ""
    local eol = s:find("\r\n", 1, true) and "\r\n" or "\n"
    if on then
        if not s:find(id, 1, true) then
            if s ~= "" and not s:find("[\r\n]$") then s = s .. eol end
            s = s .. "-- TK Theme: keeps the transport's metronome button lit while the metronome is on" .. eol
                .. 'reaper.Main_OnCommand(reaper.NamedCommandLookup("' .. id .. '"), 0)' .. eol
        end
    else
        local out = {}
        for line, sep in s:gmatch("([^\r\n]*)(\r?\n?)") do
            if line:find(id, 1, true) then
                if #out > 0 and out[#out]:find("^%-%- TK Theme") then out[#out] = nil end
            elseif line ~= "" or sep ~= "" then
                out[#out + 1] = line .. sep
            end
        end
        s = table.concat(out)
    end
    if write_all(startup_file, s) then
        startup.on = on
        if on then r.Main_OnCommand(cmd, 0) end     -- no need to wait for a restart
    else
        state.msg = "Could not write __startup.lua."
    end
end

-- what a button runs instead of its standard action: its command name, kept per
-- REAPER install, for slots/TK_Theme_Slot_<key>.lua to run
local BUTTONS_SECTION = "TK_Theme_Buttons"
local SLOT_KEYS = { "actions", "bay", "clock", "explorer", "fxbrowser", "mixer", "regions", "routing", "trackmgr", "vkb", "free1", "free2", "free3" }

local function poll_action_picker()
    if not state.pick then return end
    local cmd = r.PromptForAction(0, 0, 0)
    if cmd == 0 then return end
    local item = state.pick
    state.pick = nil
    r.PromptForAction(-1, 0, 0)
    if cmd < 0 then return end
    local name = r.ReverseNamedCommandLookup(cmd)
    local text = r.kbd_getTextFromCmd(cmd, r.SectionFromUniqueID(0))
    r.SetExtState(BUTTONS_SECTION, item.key, name and ("_" .. name) or tostring(cmd), true)
    r.SetExtState(BUTTONS_SECTION, item.key .. "_name", text or "", true)
    if not item.free then set_param("tkAlt_" .. item.key, 1, true) end
    r.ThemeLayout_RefreshAll()
end

-- off, or the left or right button window (the parameter's 0, 2 or 1)
local PLACES = { { "Off", 0 }, { "Left", 2 }, { "Right", 1 } }
local function draw_place(item, id)
    local p = P[item.param]
    row_label(item.label)
    r.ImGui_PushID(ctx, id)
    for i, place in ipairs(PLACES) do
        if i > 1 then r.ImGui_SameLine(ctx, 0, 2) end
        local active = math.floor(p.value) == place[2]
        if active then
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), rgba(mix(UI.raised, UI.accent, 0.55)))
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), rgba(UI.ink))
        end
        local clicked = r.ImGui_Button(ctx, place[1], 46, 0)
        if active then r.ImGui_PopStyleColor(ctx, 2) end
        if clicked and not active then
            set_param(item.param, place[2], true)
            r.ThemeLayout_RefreshAll()
        end
    end
    r.ImGui_PopID(ctx)
end

local function draw_button_row(item, id)
    local p = P[item.param]
    if not p then return end
    draw_place(item, id)
    local chosen = r.GetExtState(BUTTONS_SECTION, item.key)
    local alt = P["tkAlt_" .. item.key]
    local own = chosen ~= "" and (item.free or (alt and alt.value ~= 0))
    r.ImGui_SameLine(ctx, LABEL_W + 156)
    r.ImGui_PushID(ctx, id)
    if not state.pick and r.ImGui_Button(ctx, "Choose...") then
        state.pick = item
        r.PromptForAction(1, 0, 0)
    elseif state.pick == item then
        r.ImGui_AlignTextToFramePadding(ctx)
        r.ImGui_Text(ctx, "Choose in the action list...")
    end
    if own then
        r.ImGui_SameLine(ctx)
        if r.ImGui_Button(ctx, item.free and "Clear" or "Standard") then
            r.DeleteExtState(BUTTONS_SECTION, item.key, true)
            r.DeleteExtState(BUTTONS_SECTION, item.key .. "_name", true)
            if not item.free then set_param("tkAlt_" .. item.key, 0, true) end
            r.ThemeLayout_RefreshAll()
        end
    end
    r.ImGui_PopID(ctx)
    if own then
        r.ImGui_SetCursorPosX(ctx, LABEL_W)
        hint_text(r.GetExtState(BUTTONS_SECTION, item.key .. "_name"))
    end
end

-- the mixer's fader handle is chosen by layout: images can't follow a parameter
-- so each of A, B and C has a twin with the dot, and tracks set to a layout of their
-- own move to the matching one
local DOT_LAYOUT = "A Dot"
local function handle_is_dot()
    local ok, name = r.ThemeLayout_GetLayout("mcp", -1)
    return ok and name == DOT_LAYOUT
end

local function sync_track_handles(dot)
    local project_index = 0
    while true do
        local project = r.EnumProjects(project_index)
        if not project then break end
        for i = 0, r.CountTracks(project) - 1 do
            local track = r.GetTrack(project, i)
            local _, name = r.GetSetMediaTrackInfo_String(track, "P_MCP_LAYOUT", "", false)
            local lay = name:match("^([ABC])$") or name:match("^([ABC]) Dot$")
            local wanted = lay and (dot and lay .. " Dot" or lay)
            if wanted and wanted ~= name then
                r.GetSetMediaTrackInfo_String(track, "P_MCP_LAYOUT", wanted, true)
            end
        end
        project_index = project_index + 1
    end
end

local function set_handle(dot)
    r.ThemeLayout_SetLayout("mcp", dot and DOT_LAYOUT or "A")
    r.ThemeLayout_SetLayout("master_mcp", dot and DOT_LAYOUT or "A")
    sync_track_handles(dot)
    r.ThemeLayout_RefreshAll()
end

local function draw_handle(item, id)
    row_label(item.label)
    local dot = handle_is_dot()
    r.ImGui_PushID(ctx, id)
    for i, choice in ipairs({ { "Cap", false }, { "Dot", true } }) do
        if i > 1 then r.ImGui_SameLine(ctx, 0, 2) end
        local active = dot == choice[2]
        if active then
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), rgba(mix(UI.raised, UI.accent, 0.55)))
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), rgba(UI.ink))
        end
        local clicked = r.ImGui_Button(ctx, choice[1], 46, 0)
        if active then r.ImGui_PopStyleColor(ctx, 2) end
        if clicked and not active then
            set_handle(choice[2])
        end
    end
    r.ImGui_PopID(ctx)
end

-- TK Native Helper does this on Windows; without it, say what's missing
local function draw_menubar(item, id)
    if not IS_WINDOWS then return end
    row_label(item.label)
    if r.TK_SetMainMenuVisible then
        local on = r.TK_IsMainMenuVisible()
        if toggle(id, on) then
            if not r.TK_SetMainMenuVisible(not on) then state.msg = "Could not change the menu bar." end
        end
    else
        hint_text("Hiding it needs TK Native Helper 1.1.0 or newer (install it with ReaPack, then restart REAPER).")
    end
end

local function draw_layout_choice(item, id)
    row_label(item.label)
    r.ImGui_PushID(ctx, id)
    for i, lay in ipairs({ "A", "B", "C" }) do
        if i > 1 then r.ImGui_SameLine(ctx, 0, 2) end
        local active = tcp_layout == lay
        if active then
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), rgba(mix(UI.raised, UI.accent, 0.55)))
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), rgba(UI.ink))
        end
        local clicked = r.ImGui_Button(ctx, lay, 46, 0)
        if active then r.ImGui_PopStyleColor(ctx, 2) end
        if clicked then tcp_layout = lay end
    end
    r.ImGui_PopID(ctx)
end

-- a height for the selected tracks; a theme can't set one itself. A divider also
-- gets the layout chosen above. TK_Theme_Make_Divider.lua does the same from an action.
local track_height = tonumber(r.GetExtState(SCRIPT, "track_height")) or 40
local track_lock = r.GetExtState(SCRIPT, "track_lock") ~= "0"

local function apply_to_tracks(tracks, layout, undo_name)
    local count = #tracks
    if count == 0 then
        state.msg = undo_name and "No tracks on this layout." or "Select one or more tracks first."
        return
    end
    r.Undo_BeginBlock()
    for _, track in ipairs(tracks) do
        if layout then r.GetSetMediaTrackInfo_String(track, "P_TCP_LAYOUT", layout, true) end
        -- a locked height has to be released first; REAPER wants the height set before locking
        r.SetMediaTrackInfo_Value(track, "B_HEIGHTLOCK", 0)
        r.SetMediaTrackInfo_Value(track, "I_HEIGHTOVERRIDE", track_height)
        r.SetMediaTrackInfo_Value(track, "B_HEIGHTLOCK", track_lock and 1 or 0)
    end
    r.TrackList_AdjustWindows(false)
    r.UpdateArrange()
    r.Undo_EndBlock(undo_name or (layout and "TK Theme: make dividers") or "TK Theme: set track height", -1)
    state.msg = count .. (count == 1 and " track" or " tracks") .. " changed."
end

local function selected_tracks()
    local tracks = {}
    for i = 0, r.CountSelectedTracks(0) - 1 do tracks[#tracks + 1] = r.GetSelectedTrack(0, i) end
    return tracks
end

-- a track on the default layout has no name stored, and that's layout A
local function tracks_on_layout(lay)
    local tracks = {}
    for i = 0, r.CountTracks(0) - 1 do
        local track = r.GetTrack(0, i)
        local _, name = r.GetSetMediaTrackInfo_String(track, "P_TCP_LAYOUT", "", false)
        if name == lay or name:match("_" .. lay .. "$") or (name == "" and lay == "A") then
            tracks[#tracks + 1] = track
        end
    end
    return tracks
end

local function draw_selected_tracks(id)
    row_label("Height")
    r.ImGui_SetNextItemWidth(ctx, CONTROL_W)
    r.ImGui_PushID(ctx, id)
    local changed, v = r.ImGui_SliderInt(ctx, "##height", track_height, 20, 400)
    r.ImGui_PopID(ctx)
    if changed then
        track_height = v
        r.SetExtState(SCRIPT, "track_height", tostring(v), true)
    end
    row_label("Lock height")
    if toggle(id .. "_lock", track_lock) then
        track_lock = not track_lock
        r.SetExtState(SCRIPT, "track_lock", track_lock and "1" or "0", true)
    end
    r.ImGui_SetCursorPosX(ctx, LABEL_W)
    if r.ImGui_Button(ctx, "Apply##" .. id) then apply_to_tracks(selected_tracks()) end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Apply to all on layout " .. tcp_layout .. "##" .. id) then
        apply_to_tracks(tracks_on_layout(tcp_layout), nil, "TK Theme: set height on layout " .. tcp_layout)
    end
    r.ImGui_SameLine(ctx)
    local no_name_only = not lay_value("tkNameOnly")
    if no_name_only then r.ImGui_BeginDisabled(ctx, true) end
    if r.ImGui_Button(ctx, "Make divider on layout " .. tcp_layout .. "##" .. id) then
        apply_to_tracks(selected_tracks(), tcp_layout)
    end
    if no_name_only then r.ImGui_EndDisabled(ctx) end
end

local function draw_setting(item, id)
    if item.kind == "layout" then
        draw_layout_choice(item, id)
    elseif item.kind == "tracks" then
        draw_selected_tracks(id)
    elseif item.kind == "menubar" then
        draw_menubar(item, id)
        if not r.TK_SetMainMenuVisible then return end
    elseif item.kind == "handle" then
        draw_handle(item, id)
    elseif item.kind == "button" then
        draw_button_row(item, id)
    elseif item.kind == "place" then
        if P[item.param] then draw_place(item, id) end
    elseif item.kind == "startup" then
        row_label(item.label)
        if toggle(id, startup.on) then set_startup(not startup.on) end
    else
        local names = expand(item.param, item.layouts, item.also)
        local p = P[names[1]]
        if not p then return end
        row_label(item.label)
        if item.kind == "toggle" then
            local on = p.value ~= 0
            if item.invert then on = not on end
            if toggle(id, on) then
                local v = (on == not item.invert) and 0 or 1
                for _, n in ipairs(names) do set_param(n, v, true) end
                r.ThemeLayout_RefreshAll()
            end
        else
            r.ImGui_SetNextItemWidth(ctx, CONTROL_W)
            r.ImGui_PushID(ctx, id)
            local changed, v = r.ImGui_SliderInt(ctx, "##value", math.floor(p.value), math.floor(p.min), math.floor(p.max))
            local done = r.ImGui_IsItemDeactivatedAfterEdit(ctx)
            local reset = r.ImGui_IsItemClicked(ctx, 1)
            r.ImGui_PopID(ctx)
            if reset then
                changed, done, v = true, true, math.floor(p.def)
            end
            if changed or done then
                for _, n in ipairs(names) do set_param(n, v, done) end
                r.ThemeLayout_RefreshAll()
            end
        end
    end
    if item.hint then
        r.ImGui_SetCursorPosX(ctx, LABEL_W)
        hint_text(item.hint)
    end
end

local CHILD_FLAGS = (r.ImGui_ChildFlags_AutoResizeY and r.ImGui_ChildFlags_AutoResizeY() or 0)
    | (r.ImGui_ChildFlags_AlwaysUseWindowPadding and r.ImGui_ChildFlags_AlwaysUseWindowPadding() or 0)

local function begin_card(title, id)
    if not r.ImGui_BeginChild(ctx, "##card" .. id, 0, 0, CHILD_FLAGS) then return false end
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), rgba(UI.ink))
    r.ImGui_Text(ctx, title)
    r.ImGui_PopStyleColor(ctx)
    r.ImGui_Dummy(ctx, 0, 2)
    return true
end

local function page_params(page)
    local out = {}
    for _, card in ipairs(page.cards or {}) do
        for _, item in ipairs(card[2]) do
            if item.param then
                for _, n in ipairs(expand(item.param, item.layouts, item.also)) do out[#out + 1] = n end
            end
        end
    end
    return out
end

-- a second click within the same page confirms; returns true on that click
local function confirm_button(id, label, sure)
    local armed = state.confirm == id
    if r.ImGui_Button(ctx, (armed and sure or label) .. "##" .. id) then
        if armed then
            state.confirm = nil
            return true
        end
        state.confirm = id
    end
    return false
end

local function draw_param_page(page)
    for ci, card in ipairs(page.cards) do
        if begin_card(card[1], ci) then
            for ii, item in ipairs(card[2]) do
                local off = item.off and item.off()
                if off then r.ImGui_BeginDisabled(ctx, true) end
                draw_setting(item, ci .. "_" .. ii)
                if off then r.ImGui_EndDisabled(ctx) end
            end
            r.ImGui_EndChild(ctx)
        end
        r.ImGui_Dummy(ctx, 0, 2)
    end
    if confirm_button("reset" .. state.page, "Reset this page", "Click again to reset") then
        for _, n in ipairs(page_params(page)) do
            if P[n] then set_param(n, math.floor(P[n].def), true) end
        end
        r.ThemeLayout_RefreshAll()
    end
    r.ImGui_SameLine(ctx)
    hint_text("Right-click a slider for its default.")
end

-- ---------------------------------------------------------------- colours page

local COLOUR_GROUPS = {
    { "Arrange", {
        { "Empty area", { "col_arrangebg", "col_tracklistbg" } }, { "Track lanes", { "col_tr1_bg", "col_tr2_bg" } },
        { "Grid, measures", { "col_gridlines2" } }, { "Grid, beats", { "col_gridlines3" } }, { "Grid, between beats", { "col_gridlines" } },
        { "Edit cursor", { "col_cursor", "col_cursor2" } },
    } },
    { "Media items", {
        { "Items without a colour", { "col_mi_bg", "col_mi_bg2" } }, { "Waveform", { "col_tr1_peaks", "col_tr2_peaks" } },
        { "Waveform when selected", { "col_tr1_ps2", "col_tr2_ps2" } },
    } },
    { "Mixer", { { "Empty area", { "col_mixerbg" } } } },
    { "Lists in themed windows", {
        { "Background", { "genlist_bg" } }, { "Text", { "genlist_fg" } }, { "Selected row", { "genlist_selbg" } },
        { "Selected text", { "genlist_selfg" } }, { "Highlight", { "genlist_hilite" } },
    } },
}

local changed_colours = {}

local remember_colours     -- further down, once the factory colours are known

local function save_colours()
    local path = theme_file()
    local s = path and read_all(path)
    if not s then return false end
    for key, native in pairs(changed_colours) do
        s = s:gsub("([\r\n]" .. key .. "=)(-?%d+)", function(head, old)
            local v = (tonumber(old) & 0xFF000000) | (native & 0xFFFFFF)
            if v >= 0x80000000 then v = v - 0x100000000 end
            return head .. v
        end, 1)
    end
    if not write_all(path, s) then return false end
    changed_colours = {}
    remember_colours()
    return true
end

-- REAPER only repaints some windows (the mixer's background, for one) when told to
local function repaint_after_colour()
    r.UpdateArrange()
    r.UpdateTimeline()
    r.TrackList_AdjustWindows(false)
    r.ThemeLayout_RefreshAll()
    r.DockWindowRefresh()
end

-- the colours as the theme comes, from the file a factory reset uses
local factory_colours
local function factory_colour(key)
    if not factory_colours then
        factory_colours = {}
        local path = theme_file()
        local base = path and path:match("([^\\/]+)%.ReaperTheme$")
        local text = base and read_all(here .. "dist/" .. base .. ".factory.ReaperTheme") or ""
        for name, value in text:gmatch("([%w_]+)=(-?%d+)") do
            factory_colours[name] = tonumber(value) & 0xFFFFFF
        end
    end
    return factory_colours[key]
end

-- a ReaPack update replaces the theme's colour file. The colours that differ from the
-- theme's own are kept here too, and come back when this window opens after an update
local my_colours_file = r.GetResourcePath() .. "/Data/TK Theme/my_colours.txt"

remember_colours = function()
    local lines = {}
    for _, group in ipairs(COLOUR_GROUPS) do
        for _, entry in ipairs(group[2]) do
            for _, key in ipairs(entry[2]) do
                local factory = factory_colour(key)
                local current = r.GetThemeColor(key, 0) & 0xFFFFFF
                if factory and factory ~= current then lines[#lines + 1] = key .. "=" .. current end
            end
        end
    end
    if #lines == 0 then
        os.remove(my_colours_file)
    else
        r.RecursiveCreateDirectory(r.GetResourcePath() .. "/Data/TK Theme", 0)
        write_all(my_colours_file, table.concat(lines, "\n") .. "\n")
    end
end

-- only a colour that's back at the theme's own: anything else was changed on purpose
local function restore_my_colours()
    local text = read_all(my_colours_file)
    if not text then return end
    local restored = false
    for key, value in text:gmatch("([%w_]+)=(%d+)") do
        local mine, factory = tonumber(value), factory_colour(key)
        local current = r.GetThemeColor(key, 0) & 0xFFFFFF
        if factory and current == factory and mine ~= current then
            r.SetThemeColor(key, mine, 1)
            changed_colours[key] = mine
            restored = true
        end
    end
    if restored and save_colours() then
        repaint_after_colour()
        state.msg = "Your saved colours were restored after the update."
    end
end

local function set_colour(entry, native)
    for _, key in ipairs(entry[2]) do
        r.SetThemeColor(key, native, 1)
        changed_colours[key] = native
    end
end

local function draw_colours()
    hint_text("Colours REAPER draws itself. Panels, the glass windows and icons are images in the theme, so they keep their colours.")
    r.ImGui_Dummy(ctx, 0, 2)
    if confirm_button("colours_all", "Reset all colours", "Click again to reset all colours") then
        for _, group in ipairs(COLOUR_GROUPS) do
            for _, entry in ipairs(group[2]) do
                local native = factory_colour(entry[2][1])
                if native then set_colour(entry, native) end
            end
        end
        repaint_after_colour()
        state.msg = "Colours reset. Click Save colours to keep them."
    end
    r.ImGui_Dummy(ctx, 0, 2)
    for gi, group in ipairs(COLOUR_GROUPS) do
        if begin_card(group[1], "c" .. gi) then
            for ii, entry in ipairs(group[2]) do
                r.ImGui_PushID(ctx, gi .. "_" .. ii)
                row_label(entry[1])
                local rgb = theme_rgb(entry[2][1], 0)
                local flags = r.ImGui_ColorEditFlags_NoInputs() | r.ImGui_ColorEditFlags_NoLabel()
                local changed, value = r.ImGui_ColorEdit3(ctx, "##colour", rgb, flags)
                if changed then
                    set_colour(entry, rgb_to_native(value))
                    repaint_after_colour()
                end
                local factory = factory_colour(entry[2][1])
                if factory and factory ~= rgb_to_native(rgb) then
                    r.ImGui_SameLine(ctx)
                    if r.ImGui_SmallButton(ctx, "Reset") then
                        set_colour(entry, factory)
                        repaint_after_colour()
                    end
                end
                r.ImGui_PopID(ctx)
            end
            r.ImGui_EndChild(ctx)
        end
        r.ImGui_Dummy(ctx, 0, 2)
    end
    local dirty = next(changed_colours) ~= nil
    local path = theme_file()
    if not path then
        hint_text("Saving needs the theme's .ReaperTheme file next to its zip; it wasn't found.")
    elseif dirty then
        if r.ImGui_Button(ctx, "Save colours") then
            state.msg = save_colours() and "Colours saved." or "Could not write the theme file."
        end
        r.ImGui_SameLine(ctx)
        if r.ImGui_Button(ctx, "Undo changes") then
            changed_colours = {}
            r.OpenColorThemeFile(path)
            refresh_palette()
            repaint_after_colour()
        end
    else
        hint_text("No unsaved changes.")
    end
end

-- ---------------------------------------------------------------- colour processing

-- REAPER's own colour controls for the whole theme, images included, as in Default 7's
-- adjuster: parameter numbers below zero, shown on the same scales as there
local PROCESSING = {
    { -1000, "Gamma", 25, 200, "%d" }, { -1003, "Highlights", -100, 100, "%d" }, { -1002, "Midtones", -100, 100, "%d" },
    { -1001, "Shadows", -100, 100, "%d" }, { -1004, "Saturation", 0, 200, "%d%%" }, { -1005, "Tint", -180, 180, "%d\u{B0}" },
}
local PROCESS_CUSTOM = -1006    -- also affect project custom colours

local function processing_ids()
    local ids = { PROCESS_CUSTOM }
    for _, c in ipairs(PROCESSING) do ids[#ids + 1] = c[1] end
    return ids
end

local function reset_processing()
    for _, id in ipairs(processing_ids()) do
        local name, _, _, def = r.ThemeLayout_GetParameter(id)
        if name then r.ThemeLayout_SetParameter(id, def, true) end
    end
    r.ThemeLayout_RefreshAll()
end

local function draw_processing()
    hint_text("REAPER's own colour controls. They work on the whole theme, images included. Right-click a slider for its default.")
    r.ImGui_Dummy(ctx, 0, 2)
    if begin_card("Colour processing", "cp") then
        for i, c in ipairs(PROCESSING) do
            local id, label, lo, hi, format = c[1], c[2], c[3], c[4], c[5]
            local name, _, value, def, min, max = r.ThemeLayout_GetParameter(id)
            if name and max ~= min then
                row_label(label)
                local shown = math.floor(lo + (value - min) / (max - min) * (hi - lo) + 0.5)
                r.ImGui_SetNextItemWidth(ctx, CONTROL_W)
                r.ImGui_PushID(ctx, "cp" .. i)
                local changed, v = r.ImGui_SliderInt(ctx, "##value", shown, lo, hi, format)
                local done = r.ImGui_IsItemDeactivatedAfterEdit(ctx)
                local reset = r.ImGui_IsItemClicked(ctx, 1)
                r.ImGui_PopID(ctx)
                if reset then
                    r.ThemeLayout_SetParameter(id, def, true)
                    r.ThemeLayout_RefreshAll()
                elseif changed or done then
                    local raw = math.floor(min + (v - lo) / (hi - lo) * (max - min) + 0.5)
                    r.ThemeLayout_SetParameter(id, raw, done)
                    r.ThemeLayout_RefreshAll()
                end
            end
        end
        local name, _, value = r.ThemeLayout_GetParameter(PROCESS_CUSTOM)
        if name then
            row_label("Also affect track colours")
            if toggle("cp_custom", value ~= 0) then
                r.ThemeLayout_SetParameter(PROCESS_CUSTOM, value ~= 0 and 0 or 1, true)
                r.ThemeLayout_RefreshAll()
            end
        end
        r.ImGui_Dummy(ctx, 0, 2)
        if r.ImGui_Button(ctx, "Reset all##cp") then reset_processing() end
        r.ImGui_EndChild(ctx)
    end
end

-- ---------------------------------------------------------------- dark mode page

local DARK_GROUPS = {
    { "Lists", { { 7, "Background" }, { 9, "Text" }, { 10, "Disabled text" }, { 22, "Grid lines" }, { 20, "Selected row" }, { 21, "Selected row, inactive" }, { 16, "Selected text" } } },
    { "Column headers", { { 14, "Background" }, { 15, "Text" } } },
    { "Fields and boxes", { { 8, "Edit fields and dropdowns" }, { 12, "Borders" }, { 13, "Group boxes" }, { 23, "Focus" } } },
    { "Windows", { { 5, "Title bar" }, { 11, "Window border" }, { 6, "Main" }, { 19, "System windows" } } },
    { "Menu bar", { { 1, "Background" }, { 2, "Hover" }, { 3, "Text" }, { 4, "Disabled text" } } },
    { "Tabs", { { 17, "Background" }, { 18, "Selected" } } },
}

local dark = {}

local function parse_dark(value)
    local out = {}
    for hex in (value or ""):gmatch("%x%x%x%x%x%x") do out[#out + 1] = rgb_from_hex(hex) end
    return #out == 23 and out or nil
end

local function format_dark(slots)
    local out = {}
    for i, c in ipairs(slots) do out[i] = string.format("%06x", c) end
    return table.concat(out, " ")
end

local function theme_dark_value()
    local value = read_all(here .. "dist/darkmode_colors.txt") or read_all(here .. "darkmode_colors.txt")
    return parse_dark(value) and value:match("^[%x ]+") or THEME_DARKMODE
end

local function load_dark()
    dark.on = ini_get("win32_darkmode") ~= "0"
    dark.saved = ini_get("win32_darkmode_colors")
    dark.slots = parse_dark(dark.saved) or parse_dark(theme_dark_value())
    dark.dirty = false
end

local function apply_dark()
    local ok = ini_set("win32_darkmode", dark.on and "1" or "0")
    ok = ini_set("win32_darkmode_colors", format_dark(dark.slots)) and ok
    if ok then
        dark.saved, dark.dirty = format_dark(dark.slots), false
        state.restart = true
        r.SetExtState(SCRIPT, "restart", "1", false)
    end
    state.msg = ok and "Written to reaper.ini. Restart REAPER to see it." or "Could not write reaper.ini."
end

local function draw_darkmode()
    hint_text("Windows dark mode colours lists, menus, title bars and borders. REAPER reads these colours when it starts, so changes appear after a restart. They belong to this REAPER, not to the theme file.")
    r.ImGui_Dummy(ctx, 0, 2)
    if begin_card("Dark mode", "dm") then
        row_label("Use dark mode")
        if toggle("dm_on", dark.on) then
            dark.on, dark.dirty = not dark.on, true
        end
        r.ImGui_SetCursorPosX(ctx, LABEL_W)
        hint_text("Without it, lists follow the Colours page but scrollbars turn white.")
        r.ImGui_EndChild(ctx)
    end
    r.ImGui_Dummy(ctx, 0, 2)
    for gi, group in ipairs(DARK_GROUPS) do
        if begin_card(group[1], "d" .. gi) then
            for _, entry in ipairs(group[2]) do
                r.ImGui_PushID(ctx, entry[1])
                row_label(entry[2])
                local flags = r.ImGui_ColorEditFlags_NoInputs() | r.ImGui_ColorEditFlags_NoLabel()
                local changed, value = r.ImGui_ColorEdit3(ctx, "##colour", dark.slots[entry[1]], flags)
                if changed then
                    dark.slots[entry[1]], dark.dirty = value, true
                end
                r.ImGui_PopID(ctx)
            end
            r.ImGui_EndChild(ctx)
        end
        r.ImGui_Dummy(ctx, 0, 2)
    end
    if r.ImGui_Button(ctx, dark.dirty and "Apply (restart needed)" or "Apply") then apply_dark() end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Theme colours") then
        dark.slots, dark.dirty = parse_dark(theme_dark_value()), true
    end
    r.ImGui_SameLine(ctx)
    if confirm_button("dark_default", "Back to REAPER's original", "Click again to restore REAPER's original") then
        if ini_set("win32_darkmode_colors", nil) then
            load_dark()
            state.restart = true
            r.SetExtState(SCRIPT, "restart", "1", false)
            state.msg = "Removed from reaper.ini. Restart REAPER to see it."
        end
    end
    hint_text(dark.saved and "reaper.ini now holds custom colours. Back to REAPER's original removes them, as if this window never set any."
        or "reaper.ini holds no custom colours: REAPER uses its original ones. The colours above are the theme's, ready to apply.")
end

-- ---------------------------------------------------------------- reset

-- what a factory reset is about to change, for undoing it
local function save_undo()
    r.RecursiveCreateDirectory(undo_dir, 0)
    local lines = { "date=" .. os.date("%Y-%m-%d %H:%M") }
    for _, key in ipairs({ "win32_darkmode", "win32_darkmode_colors" }) do
        local v = ini_get(key)
        if v then lines[#lines + 1] = key .. "=" .. v end
    end
    for _, n in ipairs(order) do
        lines[#lines + 1] = "param:" .. n .. "=" .. tostring(math.floor(P[n].value))
    end
    for _, key in ipairs(SLOT_KEYS) do
        for _, k in ipairs({ key, key .. "_name" }) do
            local v = r.GetExtState(BUTTONS_SECTION, k)
            if v ~= "" then lines[#lines + 1] = "button:" .. k .. "=" .. v end
        end
    end
    for lay in ALL:gmatch(".") do
        for _, kind in ipairs({ "Fx", "Send" }) do
            local k = "Layout" .. lay .. "-tcp" .. kind .. "Location"
            local v = r.GetExtState(LISTS_SECTION, k)
            if v ~= "" then lines[#lines + 1] = "lists:" .. k .. "=" .. v end
        end
    end
    for _, id in ipairs(processing_ids()) do
        local name, _, value = r.ThemeLayout_GetParameter(id)
        if name then lines[#lines + 1] = "processing:" .. id .. "=" .. tostring(math.floor(value)) end
    end
    lines[#lines + 1] = "handle=" .. (handle_is_dot() and "dot" or "cap")
    lines[#lines + 1] = "startup=" .. (startup.on and "1" or "0")
    local path = theme_file()
    local theme = path and read_all(path)
    os.remove(undo_dir .. "/theme.ReaperTheme")
    if theme then write_all(undo_dir .. "/theme.ReaperTheme", theme) end
    return write_all(undo_dir .. "/settings.txt", table.concat(lines, "\n") .. "\n")
end

local function undo_date()
    return (read_all(undo_dir .. "/settings.txt") or ""):match("^date=([^\r\n]*)")
end

local function clear_undo()
    os.remove(undo_dir .. "/settings.txt")
    os.remove(undo_dir .. "/theme.ReaperTheme")
end

local function clear_buttons_and_lists()
    for _, key in ipairs(SLOT_KEYS) do
        r.DeleteExtState(BUTTONS_SECTION, key, true)
        r.DeleteExtState(BUTTONS_SECTION, key .. "_name", true)
    end
    for lay in ALL:gmatch(".") do
        r.DeleteExtState(LISTS_SECTION, "Layout" .. lay .. "-tcpFxLocation", true)
        r.DeleteExtState(LISTS_SECTION, "Layout" .. lay .. "-tcpSendLocation", true)
    end
end

local function needs_restart()
    state.restart = true
    r.SetExtState(SCRIPT, "restart", "1", false)
end

local function undo_reset()
    local s = read_all(undo_dir .. "/settings.txt")
    if not s then return false end
    local values = {}
    clear_buttons_and_lists()
    for line in s:gmatch("[^\r\n]+") do
        local param, v = line:match("^param:(.-)=(-?%d+)$")
        local button, text = line:match("^button:(.-)=(.*)$")
        local lists, pos = line:match("^lists:(.-)=(.*)$")
        local process, amount = line:match("^processing:(-%d+)=(-?%d+)$")
        if process then r.ThemeLayout_SetParameter(tonumber(process), tonumber(amount), true) end
        if button then
            r.SetExtState(BUTTONS_SECTION, button, text, true)
        elseif lists then
            r.SetExtState(LISTS_SECTION, lists, pos, true)
        elseif param then
            if P[param] then
                P[param].value = tonumber(v)
                r.ThemeLayout_SetParameter(P[param].idx, tonumber(v), true)
            end
        else
            local key, val = line:match("^([%w_]+)=(.*)$")
            if key then values[key] = val end
        end
    end
    r.ThemeLayout_RefreshAll()
    if values.handle then set_handle(values.handle == "dot") end
    if (values.startup == "1") ~= startup.on then set_startup(values.startup == "1") end
    local dm, colours = values.win32_darkmode, values.win32_darkmode_colors
    if dm ~= ini_get("win32_darkmode") or colours ~= ini_get("win32_darkmode_colors") then
        if dm then ini_set("win32_darkmode", dm) end
        ini_set("win32_darkmode_colors", colours)
        needs_restart()
    end
    local theme = read_all(undo_dir .. "/theme.ReaperTheme")
    local path = theme_file()
    if theme and path and write_all(path, theme) then
        changed_colours = {}
        r.OpenColorThemeFile(path)
        remember_colours()
    end
    clear_undo()
    load_params()
    load_dark()
    refresh_palette()
    return true
end

local function factory_reset()
    if not save_undo() then
        state.msg = "Nothing was reset: couldn't save the current settings for undo."
        return
    end
    for _, n in ipairs(order) do
        if n ~= "tkTransMetroOn" then
            P[n].value = P[n].def
            r.ThemeLayout_SetParameter(P[n].idx, math.floor(P[n].def), true)
        end
    end
    reset_processing()
    r.ThemeLayout_RefreshAll()
    clear_buttons_and_lists()
    if startup.on then set_startup(false) end
    set_handle(false)
    local notes = {}
    local path = theme_file()
    local base = path and path:match("([^\\/]+)%.ReaperTheme$")
    local factory = base and read_all(here .. "dist/" .. base .. ".factory.ReaperTheme")
    if factory and write_all(path, factory) then
        changed_colours = {}
        os.remove(my_colours_file)
        r.OpenColorThemeFile(path)
    else
        notes[#notes + 1] = "The theme's colour file couldn't be reset."
    end
    if state.factory_dark and ini_get("win32_darkmode_colors") then
        ini_set("win32_darkmode_colors", nil)
        needs_restart()
        notes[#notes + 1] = "Restart REAPER to see the dark mode colours go."
    end
    load_params()
    load_dark()
    refresh_palette()
    state.msg = "Factory settings restored. " .. table.concat(notes, " ")
end

-- ---------------------------------------------------------------- presets

-- a preset is one text file: every setting, colour, chosen action, the colour
-- processing and the fader handle. Not what belongs to a project or to REAPER as a whole; dark mode colours
-- only if asked for, as they apply to all of REAPER and need a restart.
local preset_dir = r.GetResourcePath() .. "/Data/TK Theme/presets"

local function preset_path(name) return preset_dir .. "/" .. name .. ".txt" end

local function preset_names()
    if state.presets then return state.presets end
    local names, i = {}, 0
    while true do
        local file = r.EnumerateFiles(preset_dir, i)
        if not file then break end
        local name = file:match("^(.*)%.txt$")
        if name then names[#names + 1] = name end
        i = i + 1
    end
    table.sort(names, function(a, b) return a:lower() < b:lower() end)
    state.presets = names
    return names
end

local function colour_keys(fn)
    for _, group in ipairs(COLOUR_GROUPS) do
        for _, entry in ipairs(group[2]) do
            for _, key in ipairs(entry[2]) do fn(key) end
        end
    end
end

local function save_preset(name, with_dark)
    r.RecursiveCreateDirectory(preset_dir, 0)
    local lines = { "tk_theme_preset=1", "date=" .. os.date("%Y-%m-%d %H:%M") }
    for _, n in ipairs(order) do
        if n ~= "tkTransMetroOn" then
            lines[#lines + 1] = "param:" .. n .. "=" .. tostring(math.floor(P[n].value))
        end
    end
    for _, key in ipairs(SLOT_KEYS) do
        for _, k in ipairs({ key, key .. "_name" }) do
            local v = r.GetExtState(BUTTONS_SECTION, k)
            if v ~= "" then lines[#lines + 1] = "button:" .. k .. "=" .. v end
        end
    end
    colour_keys(function(key)
        lines[#lines + 1] = "colour:" .. key .. "=" .. tostring(r.GetThemeColor(key, 0) & 0xFFFFFF)
    end)
    for _, id in ipairs(processing_ids()) do
        local name, _, value = r.ThemeLayout_GetParameter(id)
        if name then lines[#lines + 1] = "processing:" .. id .. "=" .. tostring(math.floor(value)) end
    end
    lines[#lines + 1] = "handle=" .. (handle_is_dot() and "dot" or "cap")
    if with_dark and ini_get("win32_darkmode_colors") then
        lines[#lines + 1] = "win32_darkmode_colors=" .. ini_get("win32_darkmode_colors")
    end
    state.presets = nil
    return write_all(preset_path(name), table.concat(lines, "\n") .. "\n")
end

local function load_preset(name, with_dark)
    local s = read_all(preset_path(name))
    if not s or not s:find("^tk_theme_preset=") then
        state.msg = "This isn't a TK Theme preset."
        return
    end
    if not save_undo() then
        state.msg = "Nothing was loaded: couldn't save the current settings for undo."
        return
    end
    local params, colours, values = {}, {}, {}
    clear_buttons_and_lists()
    reset_processing()      -- what the preset holds comes right back
    local missing = 0
    for line in s:gmatch("[^\r\n]+") do
        local process, amount = line:match("^processing:(-%d+)=(-?%d+)$")
        if process then r.ThemeLayout_SetParameter(tonumber(process), tonumber(amount), true) end
        local param, v = line:match("^param:(.-)=(-?%d+)$")
        local button, text = line:match("^button:(.-)=(.*)$")
        local colour, native = line:match("^colour:(.-)=(%d+)$")
        if param then
            params[param] = tonumber(v)
        elseif button then
            r.SetExtState(BUTTONS_SECTION, button, text, true)
            if not button:find("_name$") and not tonumber(text) and r.NamedCommandLookup(text) == 0 then
                missing = missing + 1
            end
        elseif colour then
            colours[colour] = tonumber(native)
        else
            local key, val = line:match("^([%w_]+)=(.*)$")
            if key then values[key] = val end
        end
    end
    -- a setting the preset doesn't know, from a newer version, goes to its default
    for _, n in ipairs(order) do
        if n ~= "tkTransMetroOn" then
            local v = params[n] or math.floor(P[n].def)
            P[n].value = v
            r.ThemeLayout_SetParameter(P[n].idx, v, true)
        end
    end
    r.ThemeLayout_RefreshAll()
    if values.handle then set_handle(values.handle == "dot") end
    local notes = {}
    changed_colours = {}
    for key, native in pairs(colours) do
        r.SetThemeColor(key, native, 1)
        changed_colours[key] = native
    end
    if not save_colours() then notes[#notes + 1] = "Its colours are shown, but couldn't be saved to the theme file." end
    if with_dark and values.win32_darkmode_colors then
        ini_set("win32_darkmode_colors", values.win32_darkmode_colors)
        needs_restart()
    end
    if missing > 0 then
        notes[#notes + 1] = missing .. (missing == 1 and " chosen action isn't" or " chosen actions aren't") .. " on this computer, so those buttons do nothing."
    end
    load_params()
    load_dark()
    refresh_palette()
    repaint_after_colour()
    state.msg = 'Loaded "' .. name .. '". ' .. table.concat(notes, " ")
end

local function draw_undo_card()
    local date = undo_date()
    if not date then return end
    r.ImGui_Dummy(ctx, 0, 2)
    if begin_card("Undo", "u") then
        hint_text("Brings back everything as it was before the reset or preset of " .. date .. ".")
        if confirm_button("undo", "Undo", "Click again to undo") then
            state.msg = undo_reset() and "Undone." or "Could not read the saved settings."
        end
        r.ImGui_EndChild(ctx)
    end
end

local function draw_presets()
    hint_text("A preset holds every setting, colour, the colour processing, chosen actions and the fader handle. Track heights belong to a project, and the metronome light at startup and the menu bar stay as they are.")
    r.ImGui_Dummy(ctx, 0, 2)
    if begin_card("Save as a new preset", "ps") then
        row_label("Name")
        r.ImGui_SetNextItemWidth(ctx, CONTROL_W)
        local changed, name = r.ImGui_InputText(ctx, "##preset_name", state.preset_name or "")
        if changed then state.preset_name = name end
        if IS_WINDOWS then
            row_label("With dark mode colours")
            if toggle("preset_dark_save", state.preset_dark_save) then state.preset_dark_save = not state.preset_dark_save end
        end
        r.ImGui_SetCursorPosX(ctx, LABEL_W)
        if r.ImGui_Button(ctx, "Save preset") then
            local clean = (state.preset_name or ""):gsub('[\\/:*?"<>|]', ""):match("^%s*(.-)%s*$")
            if clean == "" then
                state.msg = "Give the preset a name first."
            elseif read_all(preset_path(clean)) then
                state.msg = 'There already is a preset "' .. clean .. '". Use its Overwrite button, or choose another name.'
            elseif save_preset(clean, state.preset_dark_save) then
                state.preset_name = ""
                state.msg = 'Saved "' .. clean .. '".'
            else
                state.msg = "Could not write the preset."
            end
        end
        r.ImGui_EndChild(ctx)
    end
    r.ImGui_Dummy(ctx, 0, 2)
    if begin_card("Presets", "pl") then
        local names = preset_names()
        if #names == 0 then hint_text("No presets yet.") end
        if IS_WINDOWS and #names > 0 then
            row_label("Load dark mode colours too")
            if toggle("preset_dark_load", state.preset_dark_load) then state.preset_dark_load = not state.preset_dark_load end
            r.ImGui_SetCursorPosX(ctx, LABEL_W)
            hint_text("Only for a preset saved with them. They apply to all of REAPER, after a restart.")
            r.ImGui_Dummy(ctx, 0, 2)
        end
        for i, name in ipairs(names) do
            r.ImGui_PushID(ctx, "preset" .. i)
            row_label(name)
            if r.ImGui_Button(ctx, "Load") then load_preset(name, state.preset_dark_load) end
            r.ImGui_SameLine(ctx)
            if confirm_button("over" .. i, "Overwrite", "Click again to overwrite") then
                state.msg = save_preset(name, state.preset_dark_save) and ('Saved "' .. name .. '".') or "Could not write the preset."
            end
            r.ImGui_SameLine(ctx)
            if confirm_button("del" .. i, "Delete", "Click again to delete") then
                os.remove(preset_path(name))
                state.presets = nil
                state.msg = 'Deleted "' .. name .. '".'
            end
            r.ImGui_PopID(ctx)
        end
        r.ImGui_Dummy(ctx, 0, 2)
        hint_text("To share a preset, copy its file from " .. preset_dir .. ". A copied file shows up the next time this window opens.")
        r.ImGui_EndChild(ctx)
    end
    draw_undo_card()
end

local function draw_reset()
    if begin_card("Factory reset", "f") then
        hint_text("Puts every setting, colour, transport button and chosen action back to how the theme comes, and removes the metronome line from __startup.lua.")
        if IS_WINDOWS then
            row_label("Also dark mode colours")
            if toggle("factory_dark", state.factory_dark) then state.factory_dark = not state.factory_dark end
            r.ImGui_SetCursorPosX(ctx, LABEL_W)
            hint_text("Back to REAPER's original ones: lists turn grey again. Dark mode itself stays as it is.")
        end
        if confirm_button("factory", "Reset to factory settings", "Click again to reset everything") then
            factory_reset()
        end
        r.ImGui_EndChild(ctx)
    end
    draw_undo_card()
end

-- ---------------------------------------------------------------- guide

local GUIDE = {
    { "Transport", {
        "The gear at the end of the transport opens this window.",
        "The metronome button lights up while the metronome is on. Its small arrow opens the metronome settings. To have the light right before your first click, turn on \"Metronome light at startup\" on the General page.",
        "Extra buttons sit in a window to the left or right of the transport. Choose them on the Transport buttons page, where a button can also run an action of your own. When the transport gets too narrow, these windows move to a second row.",
    } },
    { "Track panel", {
        "The buttons on the lowest row are, from the left: automation mode, phase, fixed item lanes, FX and IO columns, meter, freeze and unfreeze. Buttons that don't fit are left out, so make the panel wider or the track taller to see them.",
        "The columns and meter buttons work on all tracks with the same layout as the one you click; the master's buttons only on the master. The columns button also turns on REAPER's options to show FX and sends in the track panel. The FX and IO buttons are the headers of those columns; without a column, they move to the first row. Set the columns' width on the Track panel page.",
        "A track with fixed item lanes has a blue strip at the left of its window, whether the lanes are open or closed.",
        "To add a knob for an FX parameter: in the FX window, choose Param > FX parameter list > Show in track controls. It appears under the controls, so the track has to be tall enough.",
        "An FX with an embedded UI shows under the controls too, once it's turned on: right-click the FX in the FX chain. Make the track taller to see it.",
    } },
    { "Master", {
        "The master has the same windows as a track. Show it with View > Master track. Its hardware outputs are in the IO column; click the IO button to add one. It can do without volume, pan or columns, have a wider meter, or be nothing but one big meter: see the Master settings on the Track panel page.",
    } },
    { "Layouts", {
        "Each track can use layout A, B or C. In the track panel they look the same until you change one on the Track panel page, for example to give your busses only a name, FX, mute and solo, with a wide meter on the left. Settings that don't count at the moment show grey. Name only turns a track into a divider: its name, large and centred, growing with the track's height.",
        "Under Selected tracks you set a height and lock it, or make dividers in one go. The action TK_Theme_Make_Divider does the same from a shortcut.",
    } },
    { "Mixer", {
        "Choose a fader cap or a dot on the Mixer page, for all layouts. In the track's layout menu, each layout has a twin with the word Dot; this switch moves tracks between them. A project opened later follows the next time this window opens.",
        "Layouts A, B and C each have their own settings. The width decides the form: a narrow strip under 52, an intermediate one under 88, a normal one from 88. What doesn't count for the current form shows grey. A sidebar puts the FX and send lists beside the strip.",
        "Turn on the FX and send lists by right-clicking the mixer. An FX's embedded UI shows in that list when the strip is tall enough.",
    } },
    { "Colours", {
        "A colour that differs from the theme's own gets a Reset button, and Reset all colours does them all. A change is temporary until you click Save colours; Undo changes goes back to the last saved colours.",
        "An update of the theme replaces its colour file. Colours you saved come back by themselves the next time you open this window.",
        "Colour processing changes the whole theme at once, images included: gamma, highlights, midtones, shadows, saturation and tint.",
    } },
    { "Dark mode and the menu bar", windows = true, {
        "The Dark mode page sets the colours of REAPER's lists, menus and borders. REAPER reads them when it starts, so changes show after a restart. It keeps your own colours, and can go back to REAPER's original ones. Popup menus, buttons and dropdowns in REAPER's windows keep their own grey: none of REAPER's colour settings changes them.",
        "Hiding the menu bar needs TK Native Helper 1.1.0 or newer, from ReaPack. Give the action TK_Theme_Toggle_Menu_Bar a shortcut to do it from the keyboard. The menu bar comes back when REAPER restarts.",
    } },
    { "Toolbar icons", {
        "ReaPack also installs a set of TK_ icons for toolbars and menus you make yourself, in Data/toolbar_icons in REAPER's resource folder. Right-click a toolbar, choose Customize toolbar, select a button and click Icon. A button that toggles has an _off and an _on file: choose _off.",
    } },
    { "Presets", {
        "The Presets page saves all your settings and colours under a name, to go back to or to share as a file. Loading one can be undone on that same page.",
    } },
    { "Going back", {
        "Each page has a Reset button for its own settings; on the Track panel and Mixer pages it also takes only the chosen layout. The Reset page puts the whole theme back as it comes, and can undo the last reset.",
    } },
}

local function draw_guide()
    for i, section in ipairs(GUIDE) do
        if (IS_WINDOWS or not section.windows) and begin_card(section[1], "guide" .. i) then
            for j, text in ipairs(section[2]) do
                if j > 1 then r.ImGui_Dummy(ctx, 0, 2) end
                r.ImGui_TextWrapped(ctx, text)
            end
            r.ImGui_EndChild(ctx)
        end
        if IS_WINDOWS or not section.windows then r.ImGui_Dummy(ctx, 0, 2) end
    end
end

-- ---------------------------------------------------------------- window

local DRAWERS = { colours = draw_colours, darkmode = draw_darkmode, reset = draw_reset, presets = draw_presets, processing = draw_processing, guide = draw_guide }

local function draw_nav()
    if r.ImGui_BeginChild(ctx, "##nav", 170, 0, r.ImGui_ChildFlags_AlwaysUseWindowPadding and r.ImGui_ChildFlags_AlwaysUseWindowPadding() or 0) then
        r.ImGui_Dummy(ctx, 0, 2)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), rgba(UI.ink))
        r.ImGui_Text(ctx, "TK Theme")
        r.ImGui_PopStyleColor(ctx)
        r.ImGui_Dummy(ctx, 0, 6)
        for i, page in ipairs(PAGES) do
            local selected = state.page == i
            r.ImGui_PushID(ctx, i)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), rgba(selected and UI.ink or UI.text))
            if r.ImGui_Selectable(ctx, page.title, selected, 0, 0, 22) and not selected then
                state.page = i
                state.confirm, state.msg = nil, nil
            end
            r.ImGui_PopStyleColor(ctx)
            if selected then
                local x, y = r.ImGui_GetItemRectMin(ctx)
                local _, y2 = r.ImGui_GetItemRectMax(ctx)
                r.ImGui_DrawList_AddRectFilled(r.ImGui_GetWindowDrawList(ctx), x - 2, y, x + 1, y2, rgba(UI.accent), 1)
            end
            r.ImGui_PopID(ctx)
        end
        r.ImGui_EndChild(ctx)
    end
end

-- the first time on Windows, without custom colours yet: lists are grey until
-- the dark mode colours are applied, and nothing else tells a new user that
local function draw_welcome()
    if not state.welcome then return end
    if begin_card("Welcome to TK Theme", "welcome") then
        r.ImGui_TextWrapped(ctx, "For lists, menus and borders to match the theme, REAPER's dark mode needs the theme's colours. These apply to this REAPER, and show after a restart.")
        r.ImGui_Dummy(ctx, 0, 2)
        if r.ImGui_Button(ctx, "Apply the theme's colours") then
            dark.slots = parse_dark(theme_dark_value())
            apply_dark()
            state.welcome = false
            r.SetExtState(SCRIPT, "welcomed", "1", true)
        end
        r.ImGui_SameLine(ctx)
        if r.ImGui_Button(ctx, "Not now") then
            state.welcome = false
            r.SetExtState(SCRIPT, "welcomed", "1", true)
        end
        r.ImGui_SameLine(ctx)
        hint_text("You can always do this on the Dark mode page.")
        r.ImGui_EndChild(ctx)
    end
    r.ImGui_Dummy(ctx, 0, 2)
end

local function draw_content()
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ChildBg(), rgba(UI.panel))
    local visible = r.ImGui_BeginChild(ctx, "##content", 0, 0, 0)
    r.ImGui_PopStyleColor(ctx)
    if not visible then return end
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ChildBg(), rgba(UI.glass))   -- the cards
    local page = PAGES[state.page]
    r.ImGui_PushFont(ctx, font, 20)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), rgba(UI.ink))
    r.ImGui_Text(ctx, page.title)
    r.ImGui_PopStyleColor(ctx)
    r.ImGui_PopFont(ctx)
    if state.restart then
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), rgba(UI.warn))
        r.ImGui_Text(ctx, "Restart REAPER to see the dark mode changes.")
        r.ImGui_PopStyleColor(ctx)
    end
    if state.msg then
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), rgba(UI.accent))
        r.ImGui_Text(ctx, state.msg)
        r.ImGui_PopStyleColor(ctx)
    end
    r.ImGui_Dummy(ctx, 0, 2)
    draw_welcome()
    if page.draw then
        DRAWERS[page.draw]()
    else
        draw_param_page(page)
    end
    r.ImGui_PopStyleColor(ctx)
    r.ImGui_EndChild(ctx)
end

local frame = 0
local function loop()
    frame = frame + 1
    poll_action_picker()
    if frame % 60 == 0 and not r.ImGui_IsAnyItemActive(ctx) then
        load_params()     -- the panel's own buttons change these too
        refresh_palette()
    end
    local colours, vars = push_theme()
    r.ImGui_PushFont(ctx, font, 15)
    r.ImGui_SetNextWindowSize(ctx, 780, 640, r.ImGui_Cond_FirstUseEver())
    local visible, open = r.ImGui_Begin(ctx, SCRIPT, true, r.ImGui_WindowFlags_NoCollapse())
    if visible then
        draw_nav()
        r.ImGui_SameLine(ctx)
        draw_content()
        r.ImGui_End(ctx)
    end
    r.ImGui_PopFont(ctx)
    r.ImGui_PopStyleVar(ctx, vars)
    r.ImGui_PopStyleColor(ctx, colours)
    if open then r.defer(loop) end
end

-- the theme's buttons call these scripts by action ID, which only exists once
-- they are in the action list; once per install location is enough
local function register_helpers()
    if r.GetExtState(SCRIPT, "registered4") == here then return end
    local files = { "TK_Theme_Settings.lua", "TK_Theme_Toggle_TCP_Lists.lua", "TK_Theme_Toggle_TCP_Meter.lua",
        "TK_Theme_Metronome.lua", "TK_Theme_Metronome_Watch.lua", "TK_Theme_Toggle_Menu_Bar.lua", "TK_Theme_Make_Divider.lua" }
    for _, key in ipairs(SLOT_KEYS) do files[#files + 1] = "slots/TK_Theme_Slot_" .. key .. ".lua" end
    local ok = true
    for i, file in ipairs(files) do
        local path = here .. file
        if read_all(path) then
            ok = r.AddRemoveReaScript(true, 0, path, i == #files) > 0 and ok
        else
            ok = false
        end
    end
    if ok then r.SetExtState(SCRIPT, "registered4", here, true) end
end

-- REAPER's Theme Adjuster action (the gear in the transport) only looks directly
-- in Scripts/, so a small script there opens this one; put back if it's missing
local function ensure_launcher()
    local path = r.GetResourcePath() .. "/Scripts/TK_Theme_Dark_theme_adjuster.lua"
    local rel = here:gsub("\\", "/"):match("/Scripts/(.*)$")
    if not rel or read_all(path) then return end
    write_all(path, "-- Opens the TK Theme settings window. REAPER's Theme Adjuster action looks for\n"
        .. "-- this file in the Scripts folder; rtconfig.txt names it with adjuster_script.\n"
        .. 'dofile(reaper.GetResourcePath() .. "/Scripts/' .. rel .. 'TK_Theme_Settings.lua")\n')
end

register_helpers()
ensure_launcher()
load_startup()
refresh_palette()
load_params()
load_dark()
restore_my_colours()
if handle_is_dot() then sync_track_handles(true) end
refresh_palette()
state.restart = r.GetExtState(SCRIPT, "restart") == "1"
state.welcome = IS_WINDOWS and not dark.saved and r.GetExtState(SCRIPT, "welcomed") == ""
r.defer(loop)
