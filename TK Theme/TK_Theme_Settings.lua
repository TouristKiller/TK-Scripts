-- @description TK Theme: settings
-- @author TouristKiller
-- @version 0.9.21
-- The theme's own settings window, in place of the Default 7 Theme Adjuster
-- (rtconfig.txt names it with adjuster_script). Its colours are read from the
-- loaded theme, so it follows whatever the theme looks like.
--   Layout pages   ThemeLayout parameters, applied live
--   Colours        SetThemeColor live, written to the .ReaperTheme on Save
--   Dark mode      win32_darkmode(_colors) in reaper.ini, read by REAPER at startup
--   Reset          everything above back to how the theme comes, and undoing that
local r = reaper

-- run by the watcher to change the look by the time of day: no window, no message
local Auto = dofile(debug.getinfo(1, "S").source:match("^@(.*[\\/])") .. "TK_Theme_Auto.lua")
local AUTO_LOOK = Auto.take_request()

if not r.ImGui_CreateContext then
    if AUTO_LOOK then return end
    r.ShowMessageBox("This window needs ReaImGui (install it with ReaPack).", "TK Theme Settings", 0)
    return
end

-- PushFont takes a size since ReaImGui 0.10; older versions would stop with an error
do
    local _, _, version = r.ImGui_GetVersion()
    local major, minor = tostring(version):match("^(%d+)%.(%d+)")
    if not major or tonumber(major) == 0 and tonumber(minor) < 10 then
        if AUTO_LOOK then return end
        r.ShowMessageBox("This window needs ReaImGui 0.10 or newer (found " .. tostring(version)
            .. "). Update it with ReaPack.", "TK Theme Settings", 0)
        return
    end
end

local SCRIPT = "TK Theme Settings"
-- set by TK_Theme_Metronome_Watch.lua as things change: no settings, so presets and undo leave them
local LIVE = { tkTransMetroOn = true, tkGridV = true, tkGridA = true, tkSnapOn = true }
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

-- A .ReaperTheme holds red in its low byte on every system. Native colours only do on
-- Windows: on Mac and Linux red and blue are the other way around.
local function file_to_native(value)
    return r.ColorToNative(value & 255, (value >> 8) & 255, (value >> 16) & 255) & 0xFFFFFF
end

local function native_to_file(c)
    local R, G, B = r.ColorFromNative(c & 0xFFFFFF)
    return R | (G << 8) | (B << 16)
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

-- The palette for the other TK scripts (TK Workbench's "TK Theme" preset, and more to come):
-- this window's own colours by role, in Data/TK Theme/palette.txt, written when they change,
-- with a counter in an ExtState that they can watch cheaply. Only for TK Theme's looks.
local PALETTE_SECTION, palette_written = "TK Theme Palette", nil
local function publish_palette()
    local theme = (r.GetLastColorThemeFile() or ""):match("([^\\/]+)%.ReaperTheme") or ""
    if not theme:find("TK Theme", 1, true) then return end
    local hex = function(c) return string.format("#%06x", c & 0xFFFFFF) end
    local p = UI.panel
    local lum = (((p >> 16) & 255) * 299 + ((p >> 8) & 255) * 587 + (p & 255) * 114) / 1000
    local lines = { "theme=" .. theme, "mode=" .. (lum > 128 and "light" or "dark") }
    for _, k in ipairs({ "panel", "base", "raised", "glass", "ink", "text", "dim", "soft", "accent", "warn" }) do
        lines[#lines + 1] = k .. "=" .. hex(UI[k])
    end
    lines[#lines + 1] = "danger=" .. hex(theme_rgb("col_vuclip", 0xFF3B6B))
    local text = table.concat(lines, "\n") .. "\n"
    local dir = r.GetResourcePath() .. "/Data/TK Theme"
    if palette_written == nil then
        local f = io.open(dir .. "/palette.txt", "rb")
        palette_written = f and f:read("a") or ""
        if f then f:close() end
    end
    if text == palette_written then return end
    r.RecursiveCreateDirectory(dir, 0)
    local f = io.open(dir .. "/palette.txt", "wb")
    if not f then return end
    f:write(text)
    f:close()
    palette_written = text
    r.SetExtState(PALETTE_SECTION, "rev", tostring(r.time_precise()), false)
end

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
    publish_palette()
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
        -- tabs as the page list: quiet, the open one raised with a thin accent line on top
        -- (TabActive/TabUnfocused* in older ReaImGui, TabSelected/TabDimmed* in newer)
        Tab = UI.base, TabHovered = mix(UI.raised, UI.ink, 0.1),
        TabActive = UI.raised, TabSelected = UI.raised, TabSelectedOverline = UI.accent,
        TabUnfocused = UI.base, TabUnfocusedActive = UI.raised, TabDimmed = UI.base, TabDimmedSelected = UI.raised,
        TabDimmedSelectedOverline = UI.accent,
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
        { r.ImGui_StyleVar_TabRounding(), 4 },
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

-- the next item beside the last one when w fits there, else on a new row at x left
function state.next_to(w, gap, left)
    r.ImGui_SameLine(ctx, 0, gap)
    if r.ImGui_GetContentRegionAvail(ctx) < w then
        r.ImGui_NewLine(ctx)
        r.ImGui_Dummy(ctx, 0, 2)
        if left then r.ImGui_SetCursorPosX(ctx, left) end
    end
end
-- what opening the window did, step by step (Data/TK Theme/open_log.txt), to find what is slow
-- (only with "openlog" in Data/TK Theme/dev.txt)
do
    local f = io.open(r.GetResourcePath() .. "/Data/TK Theme/dev.txt", "rb")
    local dev = f and f:read("a") or ""
    if f then f:close() end
    -- "Rebuilding theme..." in a window of its own crashed REAPER on Linux at every change that
    -- rebuilds the theme (since 0.9.50, when it came; found 2026-11-17 on a Linux laptop): it
    -- never showed there, and was closed again while REAPER was busy. Off Windows it is a bar
    -- at the top of the settings window. "busywindow" in dev.txt brings the own window back
    -- there, "busyinside" puts the bar on Windows too
    state.busy_inside = dev:find("busyinside", 1, true) ~= nil or (not IS_WINDOWS and not dev:find("busywindow", 1, true))
    if dev:find("openlog", 1, true) then
        state.log_t0 = r.time_precise()
        state.log_file = r.GetResourcePath() .. "/Data/TK Theme/open_log.txt"
        local g = io.open(state.log_file, "wb")
        if g then g:write("") g:close() end
    end
end
function state.log(msg)
    if not state.log_t0 or r.time_precise() - state.log_t0 > 120 then return end
    local f = io.open(state.log_file, "ab")
    if f then f:write(string.format("%7.2f s  %s\n", r.time_precise() - state.log_t0, msg)) f:close() end
end

-- Rebuilding the theme (writing its zip, reloading it) holds the window still for a moment.
-- A change started in the window waits two frames while "Rebuilding theme..." shows, then
-- runs; what it calls on the way runs at once. Outside the window's drawing (opening, day and
-- night, tests) everything runs at once. See deferred() and the loop.
local busy = { queue = {}, ui = false, running = false, shown = 0, frames = 0 }
local function deferred(fn)
    return function(...)
        if busy.ui and not busy.running then
            local args = table.pack(...)
            busy.queue[#busy.queue + 1] = function() return fn(table.unpack(args, 1, args.n)) end
            busy.shown, busy.frames = 0, 0
            return true
        end
        return fn(...)
    end
end

local function set_param(name, value, persist)
    local p = P[name]
    if not p then return end
    p.value = value
    r.ThemeLayout_SetParameter(p.idx, value, persist)
end

-- ---------------------------------------------------------------- pages

local start_watcher     -- further down, with the startup line it shares the watcher with
local rewrite_meters    -- further down, with the parts: the meters' images again, after a switch
local plate_name        -- further down, with the parts: your own name on the transport plate
local patina            -- further down, with the plate's name: wear and a coffee ring on the plates
local function S(label, param, layouts, hint) return { kind = "slider", label = label, param = param, layouts = layouts, hint = hint } end
-- one slider for a setting that exists once more for selected and armed strips
local function Grow(label, param, also) return { kind = "slider", label = label, param = param, layouts = THIS_LAYOUT, also = also } end
local function T(label, param, layouts, hint, invert) return { kind = "toggle", label = label, param = param, layouts = layouts, hint = hint, invert = invert } end
-- a transport button that can run an action of the user's choice instead
local function B(label, key, free) return { kind = "button", label = label, param = "tkBtn_" .. key, key = key, free = free } end
-- a transport button with a fixed action: off, or in the left or right window
local function N(label, key, hint) return { kind = "place", label = label, param = "tkBtn_" .. key, hint = hint } end
local ALL = "ABC"

-- a setting that doesn't count with the choices above it is hidden (the card says how many)
local function Off(when, item)
    item.off = when
    return item
end
-- one that doesn't count only at the moment (as the mixer's width decides) shows grey, so it
-- can still be found and read
local function Grey(when, item)
    item.off, item.grey = when, true
    return item
end
-- one that a choice on another page switches on shows grey too, saying why, with a key to that
-- page (why and go may be functions); one that can never count stays hidden (Off)
function state.Elsewhere(when, why, go, item)
    item.off, item.grey, item.why, item.go = when, true, why, go
    return item
end
-- a setting that belongs to what this card is about but lives on another page: a link to it,
-- not a second control for the same thing
function state.See(text, page, card)
    return { kind = "see", label = "See also", text = text, page = page, card = card }
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
        -- the mixer's plate changes form at other widths (as its layout does)
        local narrow, wide = 52, 88
        if global_value("tkMcpPlate") then narrow, wide = 76, 100 end
        local current = width < narrow and 1 or width < wide and 2 or 3
        return current ~= form
    end
end
-- off while a track panel plate is on (it lays the panel out itself), or when `when` says so
local function plate_or(when)
    local fn = function() return global_value("tkTcpPlate") or (when ~= nil and when()) end
    -- remembered, so the card can say it is the plate that hides them
    state.plate_gated = state.plate_gated or {}
    state.plate_gated[fn] = true
    return fn
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
-- why grey on the mixer's other strip forms: the width decides which form a strip has
function state.form_why(form, plate_too)
    local names = { "narrow", "intermediate", "normal" }
    return function()
        if plate_too and global_value("tkMcpPlate") and not not_form(form)() then return "Not with a plate: it has its own." end
        return "Only on " .. names[form] .. " strips: this layout's Width (Per layout) makes it another one now."
    end
end

local KNOB_CHOICE = { "Auto", "Sliders", "Knobs" }
local SLIDER_HANDLES = { { "dot", "Dot" }, { "ring", "Ring" }, { "bar", "Bar" }, { "cap", "Cap" }, { "classic", "Classic" }, { "classic_accent", "Accent" } }

-- both panels Basic: no glass anywhere, so what lights or colours the glass does nothing
local function all_basic()
    return global_value("tkTcpBasic") and not global_value("tkTcpPlate") and global_value("tkMcpBasic") and not global_value("tkMcpPlate")
end

-- on the plates, whichever shows one (Materials page, On the plates): one setting each for
-- the track panel and the mixer together
-- (kept on state, not as locals: the main chunk is at Lua's limit of 200)
state.any_plate = function() return global_value("tkTcpPlate") or global_value("tkMcpPlate") end
state.PLATE_ITEMS = {
    Off(function() return not state.any_plate() end, { kind = "choice", label = "Wear", param = "tkPatina",
      choices = { "Off", "Light", "Used", "Road-worn" }, after = function() patina.ensure() end,
      hint = "Scratches, rubbed edges and corners, on the plates of the track panel and the mixer. Drawn for you alone: no one else has the same." }),
    Off(function() return not (state.any_plate() and global_value("tkPatina")) end, { kind = "rescratch", label = "" }),
    Off(function() return not state.any_plate() end, { kind = "coffee", label = "Coffee ring" }),
    Off(function() return not state.any_plate() end, { kind = "choice", label = "Graffiti", param = "tkGraffiti",
      choices = { "Off", "Light", "Wild" }, after = function() patina.graffiti_ensure() end,
      hint = "Spray paint, splats with drips and doodles on the plates of the track panel and the mixer, every track its own. Drawn for you alone." }),
    Off(function() return not (state.any_plate() and global_value("tkGraffiti")) end, { kind = "choice", label = "Graffiti colours", param = "tkGrafColours",
      choices = { "Neon", "Accent" }, after = function() patina.graffiti_ensure() end,
      hint = "Neon: pink, yellow, cyan, green, orange and violet. Accent: your accent colour, lighter and darker, with white and black." }),
    Off(function() return not (state.any_plate() and global_value("tkGraffiti")) end, (function()
        local item = T("Name stickers", "tkGrafSticker", nil, "Each track's name on a torn sticker over its window, in the graffiti's colours; the name dark on it.")
        item.after = function() patina.graffiti_ensure() end
        return item
    end)()),
    Off(function() return not (state.any_plate() and global_value("tkGraffiti") and global_value("tkGrafSticker")) end, { kind = "choice", label = "Sticker colour",
      param = "tkGrafStkCol", choices = { "Graffiti", "Track colour" }, after = function() patina.graffiti_ensure() end,
      hint = "Track colour: white sticker paper with the track's colour printed on it, the name dark or white to match. A track without a colour keeps the graffiti's." }),
    Off(function() return not (state.any_plate() and global_value("tkGraffiti")) end, { kind = "regraffiti", label = "" }),
}

-- what a plate covers: the panel's track colour fill, the selection's overlay and the lines on
-- sliders it has no sliders for. Hidden when both the track panel and the mixer have a plate
state.both_plates = function() return global_value("tkTcpPlate") and global_value("tkMcpPlate") end

local PAGES = {
    { title = "Look", draw = "look" },
    { title = "General", cards = {
        { "Meters", {
            { kind = "meter", label = "Type", hint = "Standing meters in the track panel, the mixer and the master. Medium and Large segments grow with the meter." },
            (function()
                local item = T("Unlit segments", "tkMeterNoUnlit", nil, "Off: only what lights up shows, on the meter's background. Every meter, in every style.", true)
                item.after = function() rewrite_meters() end
                return item
            end)(),
            Off(function() return not global_value("tkTcpPlate") end, state.See("Meter in the plate", "Track panel", "All tracks")),
        } },
        { "Displays", {
            -- (look is a local further down: the loaded theme's name says the same)
            -- the Dark look has dark glass anyway: hidden there; in Light grey without a plate
            (function()
                local item = state.Elsewhere(function() return not (global_value("tkTcpPlate") or global_value("tkMcpPlate")) end,
                    "Only with a plate: Style on the Track panel or the Mixer page.", "Track panel",
                    { kind = "part", part = "light_glass", label = "Glass", choices = { { "light", "Light" }, { "dark", "Dark" } },
                      hint = "Light look with a plate: light display windows, or dark as in the Dark look." })
                item.hide = function() return not (r.GetLastColorThemeFile() or ""):find("TK Theme Light", 1, true) end
                return item
            end)(),
            state.Elsewhere(all_basic, "Both panels are Basic, which has no display windows: Style on the Track panel or the Mixer page.", "Track panel",
              { kind = "part", part = "display_light", label = "Light", choices = { { "off", "Off" }, { "soft", "Soft" }, { "bright", "Bright" } },
              hint = "A faint light from the bottom edge of the display windows. Basic has none." }),
            state.See("Display skin", "Look", "Display"),
            state.Elsewhere(all_basic, "Both panels are Basic, which has no display windows: Style on the Track panel or the Mixer page.", "Track panel",
              T("Unselected tracks dimmed", "tkLcdDim", nil,
              "The display windows of the tracks and strips that aren't selected go darker, with their text. REAPER's own small buttons on them keep their light. Basic has none.")),
        } },
        { "Tracks and strips", {
            state.Elsewhere(state.both_plates, "Both panels have a plate, which shows this its own way: Style on the Track panel or the Mixer page.", "Track panel", S("Track colour strength", "customColorDepthParam", nil, "How much of the track colour tints panels and rims. Not on a plate: there the track colour is the stripe on the number.")),
            state.Elsewhere(state.both_plates, "Both panels have a plate, which shows this its own way: Style on the Track panel or the Mixer page.", "Track panel", T("Volume line in track colour", "tkLineVolTrk", nil, "The line on the volume slider and the mixer's fader. Off: neutral. A plate's knobs and caps have none.")),
            state.Elsewhere(state.both_plates, "Both panels have a plate, which shows this its own way: Style on the Track panel or the Mixer page.", "Track panel", T("Pan line in track colour", "tkLinePanTrk", nil, "The lines on pan and width. Off: neutral. A plate's knobs have none.")),
            state.Elsewhere(state.both_plates, "Both panels have a plate, which shows this its own way: Style on the Track panel or the Mixer page.", "Track panel", S("Selection strength", "selectStrength", nil, "How much a selected track stands out.")),
            Off(function() return not global_value("tkTcpPlate") end, state.See("Selected track on a plate", "Track panel", "All tracks")),
            T("Track names in track colour", "colorTrackLabels", nil, "On Basic up to a Track colour strength of 30; on a stronger tint the panel is the track colour itself, so the names stay plain to stay readable."),
            T("Track names in accent colour", "tkNameAccent", nil, "Goes before the track colour."),
            T("Selection dot", "selDot", nil, "The small dot on the track number."),
            { kind = "part", part = "send_tint", label = "Send colours", choices = { { "off", "Off" }, { "subtle", "Subtle" }, { "medium", "Medium" } },
              hint = "Sends in the colour of the track they go to." },
            S("Text brightness", "textBrightness"),
        } },
        { "Items", {
            { kind = "part", part = "items", label = "Items", choices = { { "classic", "Classic" }, { "reversed", "Reversed" } },
              hint = "Classic: items in the track colour, a dark waveform. Reversed: dark items, the waveform in the track colour." },
        } },
        { "MIDI editor", {
            { kind = "part", part = "midi_keys", label = "Key seams", choices = { { "accent", "Accent" }, { "black", "Black" } },
              hint = "The lines between the white keys of the piano roll." },
        } },
        { "Window and toolbars", {
            { kind = "menubar", label = "Menu bar", hint = "TK_Theme_Toggle_Menu_Bar does this from a shortcut." },
            { kind = "part", part = "toolbar_blank", label = "Text buttons", choices = { { "plain", "Plain" }, { "cell", "Cell" } },
              hint = "A quiet cell behind toolbar buttons that show text." },
            { kind = "part", part = "toolbar_text", label = "Text size", choices = { { "small", "Small" }, { "normal", "Normal" }, { "large", "Large" } } },
            { kind = "part", part = "ruler_font", label = "Ruler and markers", choices = { { "inter", "Inter" }, { "arial", "Arial" } },
              hint = "The font of the ruler and the marker and region labels. Inter is the one REAPER ships with, as Default 7 uses. Arial: for when the ruler or the markers show wrong characters, which a copy of Inter you installed yourself can cause." },
        } },
    } },
    { title = "Track panel", tabs = {
        { "All tracks", { "All tracks" } },
        { "Per layout", { "Per layout", "Set track height" }, layout = true },
        { "Master", { "Master" } },
        { "Envelope lanes", { "Envelope lanes" } },
    }, cards = {
        { "All tracks", {
            -- Standard, Basic or Material; Material is Silver, Black or a material of your own,
            -- shown on the line under it (see patina.draw_plate). The values stay as they were:
            -- tkTcpPlate 0 none, 1 Silver, 2 Black; tkTcpBasic for Basic
            { kind = "plate", plate = "tcp", label = "Style", param = "tkTcpPlate", extra = "tkTcpBasic", part = "tcp_hw",
              hint = "Basic: no windows, the controls on the panel. Material: a brushed plate with hardware knobs and caps, made for the Dark look." },
            Off(function() return not global_value("tkTcpPlate") end, { kind = "plate_material", plate = "tcp", label = "Material" }),
            Off(function() return not global_value("tkTcpPlate") end, (function()
                local item = T("Screw strips", "tkTcpNoEars", nil,
                    "The strips with the screws at the plate's left and right. Off: the plate without them, and the room they took goes to the controls and windows. Not the master.", true)
                item.after = function() patina.forge.ensure() end
                return item
            end)()),
            Off(function() return not global_value("tkTcpPlate") end, { kind = "choice", label = "Rails", param = "tkWood", choices = { "Off", "Walnut", "Teak", "Material" },
              after = function() patina.forge.rails_changed() end,
              hint = "With a plate: the number column as a rail, the track colour as a stripe on it. Walnut and Teak are the theme's own; Material uses one from the Materials page." }),
            Off(function() return not (global_value("tkTcpPlate") and P.tkWood and P.tkWood.value == 3) end, { kind = "plate_material", plate = "rails", label = "Rail material" }),
            Off(function() return not (global_value("tkTcpPlate") and global_value("tkWood")) end, T("Right rail", "tkRailRight", nil, "A second rail on the right.")),
            Off(function() return not global_value("tkTcpPlate") end, { kind = "part", part = "tcp_recarm", label = "Record arm",
              choices = { { "cap", "Cap" }, { "lamp", "Lamp" }, { "glass_white", "Glass white" }, { "glass_red", "Glass red" } } }),
            Off(function() return not global_value("tkTcpPlate") end, { kind = "part", part = "tcp_knob", label = "Knobs",
              choices = { { "classic", "Classic" }, { "chicken", "Chicken head" }, { "machined", "Machined" } },
              hint = "The plate's knobs: volume, pan, width, FX parameters and the envelope lanes. Classic and Machined take the metal chosen under Hardware on the Materials page." }),
            Off(function() return not global_value("tkTcpPlate") end, T("Selected track: LED", "tkSelLed", nil,
              "A lit strip in the accent colour, in the wooden rail (without wood: on the plate's edge).")),
            Off(function() return not global_value("tkTcpPlate") end, T("Selected track: plate lit", "tkSelLit", nil,
              "The selected track's plate a step lighter; the mixer's strips too.")),
            Off(function() return not global_value("tkTcpPlate") end, { kind = "see_materials", label = "Wear and paint" }),
            Off(function() return not global_value("tkTcpPlate") end, T("Meter in the plate", "tkPlMeterIn", nil,
              "The meter lies in the plate between the controls.")),
            Off(function() return not global_value("tkTcpPlate") end, state.See("Meter type", "General", "Meters")),
            Off(function() return not (global_value("tkTcpPlate") and global_value("tkPlMeterIn")) end,
              { kind = "choice", label = "Lying meter", param = "tkPlMeterShort", pic = "lying", choices = { "Long", "Short" },
                hint = "Short stays in the plate on narrower panels. Short lamps are 6.",
                -- the lamps have a strip per length
                after = function() rewrite_meters(true) end }),
            T("Layout button", "tkTcpLayBtn", nil, "Shows the track's layout (A, B, C); click for the next. Selected tracks go along."),
            Off(function() return global_value("tkTcpPlate") and global_value("tkWood") end, { kind = "choice", label = "Track number", param = "tkNumStyle", pic = "number", choices = { "Colour", "Stripe" },
              hint = "Colour fills the number column; Stripe is a thin line of the track colour." }),
            -- a plate has knobs: then the handle is only the envelope lanes' (on their tab)
            Off(function() return global_value("tkTcpPlate") end,
                { kind = "part", part = "tcp_thumb", label = "Slider handle", choices = SLIDER_HANDLES, hint = "For volume, pan and width, also on the master and in envelope lanes." }),
            S("Section margins", "sectionMargin", nil, "Space around and between the windows (6 as it comes). On a plate: between the display, the FX and IO window and the meter, and at the panel's edges without screw strips; the screw strips keep 20 there."),
            S("Folder indent", "tcpfolderIndentSize"),
        } },
        { "Per layout", {
            { kind = "layout", label = "Layout", hint = "For the tracks on this layout. Set a track's layout in its right-click menu." },
            T("Name only", "tkNameOnly", THIS_LAYOUT, "Just the name, large: a divider or a folder."),
            Off(lay_on("tkNameOnly"), T("Volume", "tkHideVol", THIS_LAYOUT, nil, true)),
            Off(lay_on("tkNameOnly"), T("Pan", "tkHidePan", THIS_LAYOUT, nil, true)),
            Off(plate_or(lay_on("tkNameOnly")), T("Volume and pan on the first row", "tkTopSliders", THIS_LAYOUT, "Beside the name, also on the lowest tracks.")),
            Off(plate_or(lay_off_or("tkTopSliders", "tkNameOnly")), S("Name width", "tkNameW", THIS_LAYOUT, "The sliders take the rest.")),
            Off(plate_or(lay_on("tkNameOnly")), { kind = "choice", label = "Volume and pan as", param = "tkKnobs", pic = "tcp_knobs", layouts = THIS_LAYOUT, choices = KNOB_CHOICE,
                hint = "Auto: a knob where a slider has no room." }),
            Off(lay_on("tkNameOnly"), T("Input row", "tkHideInput", THIS_LAYOUT, nil, true)),
            Off(lay_on("tkNameOnly"), T("Button row", "tkHideButtons", THIS_LAYOUT, nil, true)),
            Off(lay_on("tkNameOnly"), T("Mute and solo", "tkHideMs", THIS_LAYOUT, nil, true)),
            Off(lay_on("tkNameOnly", "tkHideMs"), { kind = "choice", label = "Mute and solo", param = "tkMsLeft", pic = "ms", layouts = THIS_LAYOUT,
              choices = { "Right", "Left", "Far right" },
              hint = "Right: beside the name. Far right: at the row's end, in the same place at every track height. On a plate Far right puts R, M and S at the right in every form, the knobs left of them; Left there is as Right." }),
            Off(lay_on("tkNameOnly"), T("Record arm and monitor", "tkHideArm", THIS_LAYOUT, nil, true)),
            Off(plate_or(lay_on("tkNameOnly")), T("Record arm and monitor on the left", "tkArmLeft", THIS_LAYOUT, "At the start of the first row.")),
            Off(lay_on("tkNameOnly"), T("FX column", "tkNoFxCol", THIS_LAYOUT, "Without it, the FX button moves to the first row.", true)),
            Off(lay_on("tkNameOnly"), T("IO column", "tkNoIoCol", THIS_LAYOUT, "Without it, the IO button moves to the first row.", true)),
            -- the buttons sit on the first row without their column, or with the column in
            -- columns (2 or more), whose lowest tracks have no header
            Off(function() return lay_value("tkNameOnly") or (lay_value("tkNoFxCol") and lay_value("tkNoIoCol")) end, T("List headers", "tkNoListHead", THIS_LAYOUT,
                "The FX and IO buttons above the lists. Off: the lists start at the top, the buttons go to the first row (FX button, IO button below).", true)),
            Off(lay_on("tkNameOnly"), T("FX button", "tkHideFxBtn", THIS_LAYOUT,
                "On the first row: without the FX column, without list headers, or on the lowest tracks.", true)),
            Off(lay_on("tkNameOnly"), T("IO button", "tkHideIoBtn", THIS_LAYOUT,
                "On the first row: without the IO column, without list headers, or on the lowest tracks.", true)),
            Off(lay_on("tkNoFxCol", "tkNameOnly"), S("FX column width", "sectionRightW", THIS_LAYOUT)),
            Off(lay_on("tkNoIoCol", "tkNameOnly"), S("IO column width", "tkIoW", THIS_LAYOUT, "0: as the FX column.")),
            { kind = "part", part = "tcp_lists", label = "Lists", choices = { { "boxes", "Boxes" }, { "plain", "Plain" } },
              hint = "The FX and send lists: each in its own box, or the names straight on the window." },
            state.See("The mixer's lists", "Mixer", "FX and send lists"),
            Off(lay_on("tkNoFxCol", "tkNameOnly"), S("FX columns", "tkFxCols", THIS_LAYOUT,
                "FX side by side; give the FX column the width. The lowest tracks show the first FX: the FX button moves to the first row.")),
            Off(lay_on("tkNoIoCol", "tkNameOnly"), S("Send columns", "tkSendCols", THIS_LAYOUT,
                "Sends side by side; give the IO column the width. The lowest tracks show the first sends: the IO button moves to the first row.")),
            Off(lay_on("tkNameOnly"), T("FX parameters", "tkHideParms", THIS_LAYOUT, "The FX parameters shown in track controls.", true)),
            Off(lay_on("tkNameOnly"), T("Embedded FX", "tkHideEmbed", THIS_LAYOUT, "An FX's embedded UI under the controls.", true)),
            Off(lay_on("tkNameOnly"), T("Meter", "tkHideMeter", THIS_LAYOUT, nil, true)),
            Off(lay_on("tkNameOnly", "tkHideMeter"), T("Meter on the left", "tkMeterLeft", THIS_LAYOUT,
                "With Meter in the plate (above): only where the plate has no room for it.")),
            Off(lay_on("tkNameOnly", "tkHideMeter"), S("Meter width", "tcpMeterWidth", THIS_LAYOUT,
                "With Meter in the plate (above): only where the plate has no room for it.")),
            Off(lay_on("tkNameOnly", "tkHideMeter"), T("Peak value", "tkPeakVal", THIS_LAYOUT,
                "The peak level as a number in the box at the meter's top. REAPER shows it only where the meter is wide enough: about 40 (Meter width).")),
            Off(lay_on("tkNameOnly"), S("Name size", "tcpLabelSize", THIS_LAYOUT)),
            Off(lay_on("tkNameOnly"), S("Minimum name width", "tkNameMin", THIS_LAYOUT,
                "The name keeps this much on a narrow panel: the FX and IO columns give way first. 0: as before. On a plate it also says when the meter comes in: the lowest tracks keep this for the name (0: 40), so less brings the meter in sooner.")),
            Off(lay_on("tkNameOnly", "tkHideInput"), S("Input text size", "tcpInputFontSize", THIS_LAYOUT)),
        } },
        { "Set track height", {
            { kind = "tracks", hint = "A fixed height for the selected tracks, saved in the project. Make divider needs Name only on that layout." },
        } },
        { "Master", {
            T("Only a meter", "tkMasterMeterOnly", nil, "The whole master becomes one big meter."),
            Off(plate_or(), T("Rack screws", "tkMasterScrews", nil, "On the left of the master, as on the transport.")),
            Off(global_on("tkMasterMeterOnly"), T("Meter", "tkMasterHideMeter", nil, nil, true)),
            Off(global_on("tkMasterMeterOnly"), T("Volume", "tkMasterHideVol", nil, nil, true)),
            Off(global_on("tkMasterMeterOnly"), T("Pan", "tkMasterHidePan", nil, nil, true)),
            Off(plate_or(global_on("tkMasterMeterOnly")), { kind = "choice", label = "Volume and pan as", param = "tkMasterKnobs", pic = "tcp_knobs", choices = KNOB_CHOICE,
                hint = "Auto: a knob where a slider has no room." }),
            Off(global_on("tkMasterMeterOnly"), T("Mute and solo", "tkMasterHideMs", nil, nil, true)),
            Off(global_on("tkMasterMeterOnly"), T("FX column", "tkMasterNoFx", nil, "Without it, the FX button moves to the first row.", true)),
            Off(global_on("tkMasterMeterOnly"), T("IO column", "tkMasterNoIo", nil, "Without it, the IO button moves to the first row.", true)),
            Off(global_off_or("tkMasterNoFx", "tkMasterMeterOnly"), T("FX button", "tkMasterHideFxBtn", nil, nil, true)),
            Off(global_off_or("tkMasterNoIo", "tkMasterMeterOnly"), T("IO button", "tkMasterHideIoBtn", nil, nil, true)),
            Off(global_on("tkMasterMeterOnly"), T("FX parameters", "tkMasterHideParms", nil, nil, true)),
            Off(global_on("tkMasterMeterOnly"), T("Embedded FX", "tkMasterHideEmbed", nil, "It takes the FX parameters' place.", true)),
            Off(global_on("tkMasterMeterOnly", "tkMasterHideMeter"), T("Meter on the left", "tkMasterMeterLeft")),
            Off(global_on("tkMasterMeterOnly", "tkMasterHideMeter"), S("Meter width", "tkMasterMeterW", nil, "0: as the tracks on layout A.")),
        } },
        { "Envelope lanes", {
            T("Show value", "showEnvValue"), T("Follow the track's indent", "indentEnvcp"),
            S("Name length", "envcpLabelLength"), S("Fader length", "envcpFaderLength"), S("Name size", "envcpFontSize"),
            Off(function() return not global_value("tkTcpPlate") end,
                { kind = "part", part = "tcp_thumb", label = "Fader handle", choices = SLIDER_HANDLES,
                  hint = "With a plate the track panel has knobs, so this is only the envelope lanes' fader." }),
        } },
    } },
    { title = "Mixer", tabs = {
        { "All strips", { "Style", "Handles", "FX and send lists", "All strips" } },
        { "Per layout", { "Per layout", "Sidebar", "Buttons", "Meter", "Normal strip", "Intermediate strip", "Narrow strip" }, layout = true },
        { "Master", { "Master" } },
    }, cards = {
        { "Style", {
            { kind = "plate", plate = "mcp", label = "Style", param = "tkMcpPlate", extra = "tkMcpBasic", part = "mcp_hw", mixer_plate = true,
              hint = "Basic: no windows. Material: a brushed plate with hardware knobs, caps and fader slots, made for the Dark look." },
            Off(function() return not global_value("tkMcpPlate") end, { kind = "plate_material", plate = "mcp", label = "Material" }),
            Off(function() return not global_value("tkMcpPlate") end, (function()
                local item = T("Screw strips", "tkMcpNoEars", nil,
                    "The strips with the screws at the top and bottom of each strip's plate. Off: the plate without them, and the room they took goes to the controls. Not the master.", true)
                item.after = function() patina.forge.ensure() end
                return item
            end)()),
            Off(function() return not global_value("tkMcpPlate") end, { kind = "choice", label = "Rails", param = "tkMcpWood", choices = { "Off", "Walnut", "Teak", "Material" },
              after = function() patina.forge.rails_changed() end,
              hint = "With a plate: an armrest along the bottom, with the numbers on it. Walnut and Teak are the theme's own; Material uses one from the Materials page (the same as the track panels' rails)." }),
            Off(function() return not (global_value("tkMcpPlate") and P.tkMcpWood and P.tkMcpWood.value == 3) end, { kind = "plate_material", plate = "rails", label = "Rail material" }),
            Off(function() return not global_value("tkMcpPlate") end, { kind = "part", part = "mcp_recarm", label = "Record arm",
              choices = { { "cap", "Cap" }, { "lamp", "Lamp" }, { "glass_white", "Glass white" }, { "glass_red", "Glass red" } } }),
            Off(function() return not global_value("tkMcpPlate") end, { kind = "part", part = "mcp_knob", label = "Knobs",
              choices = { { "classic", "Classic" }, { "chicken", "Chicken head" }, { "machined", "Machined" } },
              hint = "The plate's pan and width knobs. Classic and Machined take the metal chosen under Hardware on the Materials page." }),
            Off(function() return not global_value("tkMcpPlate") end, T("Selected strip: plate lit", "tkSelLit", nil,
              "The selected strip's plate a step lighter; the track panel's too.")),
            Off(function() return not global_value("tkMcpPlate") end, { kind = "see_materials", label = "Wear and paint" }),
        } },
        { "Handles", {
            Off(function() return global_value("tkMcpPlate") end, { kind = "handle", label = "Fader", hint = "For all layouts." }),
            Off(function() return not global_value("tkMcpPlate") end, { kind = "part", part = "mcp_volthumb", label = "Fader cap",
              choices = { { "hw", "Console" }, { "hw_long", "Long throw" }, { "hw_chrome", "Chrome" }, { "hw_colour", "Colour cap" },
                          { "hw_round", "Round top" }, { "hw_wide", "Wide grip" }, { "hw_studio", "Studio" },
                          { "hw_vintage", "Vintage" }, { "hw_knurled", "Knurled" }, { "hw_glow", "Glow" } },
              hint = "The fader's cap on a plate. Colour cap, Knurled's line and Glow's light are in your accent colour. The metal ones (Console, Chrome, Round top, Studio) take the metal chosen under Hardware on the Materials page." }),
            Off(function() return global_value("tkMcpPlate") end, { kind = "part", part = "mcp_pan", label = "Pan and width", choices = SLIDER_HANDLES,
              hint = "For all layouts and the master." }),
        } },
        { "FX and send lists", {
            { kind = "part", part = "mcp_extmixbg", label = "Lists", choices = { { "grid", "Boxes" }, { "plain", "Plain" } },
              hint = "The FX and send lists above the strips: each in its own box, the empty places as a grid, or the names straight on the background." },
            state.See("The track panel's lists", "Track panel", "Per layout"),
        } },
        { "All strips", {
            T("Layout key", "tkMcpLayBtn", nil, "Shows the strip's layout (A, B, C); click for the next. Selected tracks go along."),
            Off(function() return global_value("tkMcpPlate") and global_value("tkMcpWood") end, { kind = "choice", label = "Track number", param = "tkMcpNumStyle", pic = "number", choices = { "Colour", "Stripe" },
              hint = "Colour fills the number; Stripe is a thin line of the track colour." }),
            S("Folder indent", "mcpfolderIndentSize"),
            Off(function() return global_value("tkMcpPlate") or global_value("tkMcpBasic") end,
              S("Window margins", "tkMcpGlassM", nil, "Space between the windows and the strip's edges.")),
        } },
        { "Per layout", {
            { kind = "layout", label = "Layout", hint = "For the strips on this layout: A standard, B narrow, C with a sidebar. Set it in a track's right-click menu." },
            T("Name only", "tkMcpNameOnly", THIS_LAYOUT, "Just the name, large: a divider. In a narrow strip (Width) it stands upright."),
            Off(function() return lay_value("tkMcpNameOnly") or not global_value("tkMcpPlate") end,
                { kind = "choice", label = "Keys", param = "tkMcpKeys", pic = "keys", layouts = THIS_LAYOUT,
                  choices = { "Above", "Beside fader", "Auto" },
                  hint = "With a plate, on wide strips: the keys (FX, bypass, IO, automation, phase, monitor) above the pan knobs, or in a column beside the fader, which leaves the meter more height. Auto: beside where the strip is low. On a low strip the last keys go first." }),
            S("Width", "mcpWidth", THIS_LAYOUT, "Under 52 a narrow strip, under 88 an intermediate one (with a plate 76 and 100)."),
            S("Width when selected", "mcpWidthSel", THIS_LAYOUT), S("Width when armed", "mcpWidthRecarm", THIS_LAYOUT),
            Grow("Wider per channel", "mcpNchanGrow", { "mcpNchanGrowSel", "mcpNchanGrowRecarm" }),
            S("Name size", "mcpLabelSize", THIS_LAYOUT),
            T("More values", "verboseMcp", THIS_LAYOUT, "Such as the volume in dB above the fader."),
        } },
        { "Sidebar", {
            T("Sidebar", "mcpSidebar", THIS_LAYOUT, "The FX and send lists beside the strip instead of above it."),
            T("Sidebar when selected", "mcpSidebarSel", THIS_LAYOUT), T("Sidebar when armed", "mcpSidebarRecarm", THIS_LAYOUT),
            Off(no_sidebar, S("Sidebar width", "sidebarWidth", THIS_LAYOUT)),
            Off(no_sidebar, S("Sidebar columns", "tkSidebarCols", THIS_LAYOUT, "More columns need a wider sidebar.")),
            Off(no_sidebar, T("Sidebar on the right", "tkSidebarRight", THIS_LAYOUT)),
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
            state.Elsewhere(not_form(3), state.form_why(3), nil, S("Show input from height", "mcpNormalShowSecIn", THIS_LAYOUT, "A lower mixer drops the input window. On a plate at least 280, so the meter and fader keep room: less does nothing there.")),
            state.Elsewhere(not_form(3), state.form_why(3), nil, S("Show pan from height", "mcpNormalShowSecPan", THIS_LAYOUT, "A lower mixer drops the pan window. On a plate at least 340, so the meter and fader keep room: less does nothing there.")),
            state.Elsewhere(function() return not_form(3)() or global_value("tkMcpPlate") end, state.form_why(3, true), nil, { kind = "choice", label = "Pan and width as", param = "tkMcpKnobs", pic = "mcp_knobs", layouts = THIS_LAYOUT, choices = { "Sliders", "Knobs" },
                hint = "Dual pan keeps its sliders; a plate has knobs of its own." }),
        } },
        { "Intermediate strip", {
            state.Elsewhere(not_form(2), state.form_why(2), nil, S("Show input from height", "mcpInterShowSecIn", THIS_LAYOUT, "A lower mixer drops the input window. On a plate at least 280 to 300 (by the strip's width): less does nothing there.")),
            state.Elsewhere(function() return not_form(2)() or global_value("tkMcpPlate") end, state.form_why(2, true), nil, S("Show buttons from height", "mcpInterShowSecButtons", THIS_LAYOUT)),
            state.Elsewhere(not_form(2), state.form_why(2), nil, S("Show pan from height", "mcpInterShowSecPan", THIS_LAYOUT, "A lower mixer drops the pan window. On a plate at least 330 to 352 (by the strip's width): less does nothing there.")),
        } },
        { "Narrow strip", {
            state.Elsewhere(not_form(1), state.form_why(1), nil, T("FX and send lists", "mcpStripHideExtmixer", THIS_LAYOUT, nil, true)),
        } },
        { "Master", {
            { kind = "master_place", label = "Master shown", words = "dock docked floating window separate right left side hide",
              hint = "REAPER's own setting, not the theme's: it stays when you change themes. Own window floats; Own docked window sits in a docker." },
            S("Width", "masterMcpWidth"), T("Volume and pan values", "masterMcpVals"),
            T("Name", "masterMcpLabels"), T("Meter values", "masterMcpMeterVals"),
            T("Pan", "tkMasterMcpHidePan", nil, "Off gives the meter and fader the room.", true),
            Off(function() return not global_value("tkMcpPlate") end,
                { kind = "choice", label = "Keys", param = "tkMasterMcpKeys", pic = "keys", choices = { "Above", "Beside fader", "Auto" },
                  hint = "With a plate: the master's keys above the pan knobs, or in a column beside the fader, which leaves the meter more height. Auto: beside where the mixer is low. Apart from the strips' Keys." }),
            Off(function() return global_value("tkMcpPlate") end, { kind = "choice", label = "Pan and width as", param = "tkMasterMcpKnobs", pic = "mcp_knobs", choices = { "Sliders", "Knobs" },
              hint = "Dual pan keeps its sliders." }),
            { kind = "choice", label = "List columns", param = "tkMasterListCols", choices = { "Auto", "1", "2", "3", "4" },
              hint = "The FX and send lists over the master. Auto: as many as fit." },
            { kind = "choice", label = "Side column", param = "tkMasterSideCol", pic = "side", choices = { "Off", "Left", "Right" },
              hint = "The strip in a narrow column; the lists and plugins get the rest." },
        } },
    } },
    { title = "Transport", cards = {
        { "Plate and grid", {
            -- Standard or Material (Black, Silver or a material of your own); tkTransPlate stays
            -- 0 none, 1 Black, 2 Silver
            { kind = "plate", plate = "trans", label = "Plate", param = "tkTransPlate", styles = { "standard", "material" } },
            Off(function() return not global_value("tkTransPlate") end, { kind = "plate_material", plate = "trans", label = "Material" }),
            Off(function() return not global_value("tkTransPlate") end, T("Rate as a knob", "tkRateKnob", nil, "On the right of the plate. Off keeps the slider in the display.")),
            Off(function() return not global_value("tkTransPlate") end, { kind = "choice", label = "Plate logo", param = "tkPlateLogo", choices = { "TK-S73", "Red Devil", "Blue Angel", "Black Metal", "Quicksilver", "Own name" },
              after = function(v) if v == 5 then plate_name.ensure() end end }),
            Off(function() return not (global_value("tkTransPlate") and P.tkPlateLogo and math.floor(P.tkPlateLogo.value) == 5) end,
              { kind = "platename", label = "Your name" }),
            { kind = "toggle", label = "Grid box", param = "tkGridBox", after = function(on) if on then start_watcher() end end,
              hint = "The grid on the display: click it to choose the grid, or an adaptive one." },
            { kind = "startup", label = "Metronome and grid at startup",
              hint = "Shows the metronome's and the grid's state from the start, and keeps Day and night running." },
        } },
        { "Time display", {
            { kind = "timefont", label = "Font" },
        } },
        { "Button windows", {
            T("Rack screws", "tkTransScrews", nil, "Screws at both ends, as if mounted in a rack."),
            T("Left window at the far left", "tkBtnLeftEdge", nil, "Otherwise beside the transport buttons. Only with the transport centred."),
            T("Right window at the far right", "tkBtnRightEdge", nil, "Otherwise beside the readouts."),
        } },
        { "Transport", {
            N("Metronome", "metro", "With a small arrow for the metronome and pre-roll settings."),
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
-- the Materials page (TK Material Forge, TK_Theme_Forge.lua), after Transport
for i, page in ipairs(PAGES) do
    if page.title == "Transport" then
        table.insert(PAGES, i + 1, { title = "Materials", draw = "materials" })
        break
    end
end
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
    -- explanations off (the i key in the title row): only the settings themselves show
    if not hint then return end
    if state.hints_off then
        -- a caller that moved the cursor for the text (SetCursorPosX) needs an item there, or
        -- ImGui stops at the card's end; a zero-sized one only where the cursor was moved
        if r.ImGui_GetCursorPosX(ctx) > 24 then r.ImGui_Dummy(ctx, 0, 0) end
        return
    end
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

-- a choice that reloads the theme gets a small round arrow after its label (the Guide says
-- what it means; pointing at it says so too)
local reload_mark = false
local function row_label(label)
    r.ImGui_AlignTextToFramePadding(ctx)
    r.ImGui_Text(ctx, label)
    if state.mark_item then
        local item = state.mark_item
        state.mark_item = nil
        state.draw_changed_dot(item, reload_mark)
    end
    if reload_mark then
        reload_mark = false
        local x1, y1 = r.ImGui_GetItemRectMin(ctx)
        local x2, y2 = r.ImGui_GetItemRectMax(ctx)
        local cx, cy, rr = x2 + 10, (y1 + y2) / 2, 4
        local dl = r.ImGui_GetWindowDrawList(ctx)
        local col = rgba(UI.soft)
        r.ImGui_DrawList_PathArcTo(dl, cx, cy, rr, math.rad(-70), math.rad(220))
        r.ImGui_DrawList_PathStroke(dl, col, 0, 1.4)
        local ax, ay = cx + rr * math.cos(math.rad(-70)), cy + rr * math.sin(math.rad(-70))
        r.ImGui_DrawList_AddTriangleFilled(dl, ax - 2.6, ay - 2.2, ax + 2.4, ay - 0.6, ax - 0.4, ay + 2.6, col)
        if r.ImGui_IsMouseHoveringRect(ctx, cx - 7, cy - 7, cx + 7, cy + 7) then
            r.ImGui_SetTooltip(ctx, "Reloads the theme: the screen may blink.")
        end
    end
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

-- the grid box and day and night need the watcher, also before the first click on the
-- metronome; one still running from before an update is restarted with the new code
start_watcher = function()
    if Auto.watcher_current() then return end
    local _, cmd = watcher_id()
    if cmd then r.Main_OnCommand(cmd, 0) end
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
            s = s .. "-- TK Theme: keeps the transport's metronome button and grid box up to date" .. eol
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

-- the mixer's plate brings hardware handles (fader, pan and width) and keeps the ones chosen
-- before, the Dot layouts included, to give them back with Standard
local MIXER_HANDLES = "mixer_handles_before_plate"
-- the hardware caps a plate can have (Mixer page, Fader cap): Console and the six more
local function is_hw_cap(v) return (v or ""):sub(1, 2) == "hw" end
local HW_CAP_KEPT = "mixer_hw_cap"
local function mixer_plate_handles(parts, i)
    local now = parts.chosen.mcp_volthumb or ""
    if i > 1 then
        if not is_hw_cap(now) then
            local vol = handle_is_dot() and "dot" or (parts.chosen.mcp_volthumb or parts.default.mcp_volthumb)
            r.SetExtState("TK Theme", MIXER_HANDLES, vol .. "|" .. (parts.chosen.mcp_pan or parts.default.mcp_pan), true)
        end
        if handle_is_dot() then set_handle(false) end
        -- the hardware cap chosen last (Console the first time)
        local cap = is_hw_cap(now) and now or r.GetExtState("TK Theme", HW_CAP_KEPT)
        return { { "mcp_volthumb", is_hw_cap(cap) and cap or "hw" }, { "mcp_pan", "hw" } }
    end
    if is_hw_cap(now) then r.SetExtState("TK Theme", HW_CAP_KEPT, now, true) end
    local saved = r.GetExtState("TK Theme", MIXER_HANDLES)
    if saved == "" and not is_hw_cap(now) then return {} end
    r.DeleteExtState("TK Theme", MIXER_HANDLES, true)
    local vol, pan = saved:match("^([^|]*)|(.*)$")
    if vol == "dot" then
        set_handle(true)
        vol = nil
    end
    return { { "mcp_volthumb", (vol and vol ~= "" and not is_hw_cap(vol)) and vol or parts.default.mcp_volthumb },
             { "mcp_pan", (pan and pan ~= "" and pan ~= "hw") and pan or parts.default.mcp_pan } }
end

-- Parts: images no parameter or layout can reach. The chosen variant is written into
-- the theme's zip and the theme reloaded. parts.txt keeps the choice, so it can come
-- back when an update has replaced the zip.
local Zip = dofile(here .. "TK_Theme_Zip.lua")
local parts = { file = r.GetResourcePath() .. "/Data/TK Theme/parts.txt", chosen = {}, images = {},
    default = { basic = "off", midi_keys = "accent", items = "classic", tcp_hw = "standard", mcp_hw = "standard", mcp_volthumb = "cap", meter = "segment", meter_lying = "same", display_light = "off", light_glass = "light", tcp_thumb = "dot", mcp_pan = "dot", accent = "blue", display = "standard", mcp_extmixbg = "grid", tcp_lists = "boxes", toolbar_blank = "plain", toolbar_text = "normal", send_tint = "off", shade = "standard", tcp_recarm = "cap", mcp_recarm = "cap", tcp_knob = "classic", mcp_knob = "classic", track_lcd = "own", time_font = "standard", ruler_font = "inter" },
    images_of = { tcp_thumb = { "tcp_volthumb", "tcp_panthumb", "tcp_widththumb", "envcp_fader" }, mcp_pan = { "mcp_panthumb", "mcp_widththumb" },
        -- the track panel's list slots (Lists: Boxes or Plain; its FX slots its own since 0.9.97)
        tcp_lists = { "tcp_fxlist_norm", "tcp_fxlist_byp", "tcp_fxlist_off", "tcp_fxlist_empty", "tcp_sendlist_norm",
            "tcp_sendlist_norm2", "tcp_sendlist_mute", "tcp_sendlist_mute2", "tcp_sendlist_empty", "tcp_sendlist_midihw" },
        -- the glass of the track panel's and the mixer's displays (meters have glass of their own)
        display_light = { "tcpGlass", "tcpGlassRound" },
        -- record arm on the plates (Lamp, Glass): only the R; Cap is the hardware part's own
        tcp_recarm = { "track_recarm_off_ol", "track_recarm_on_ol", "track_recarm_norec_ol", "track_recarm_auto_ol",
            "track_recarm_auto_on_ol", "track_recarm_auto_norec_ol" },
        mcp_recarm = { "mcp_recarm_off_ol", "mcp_recarm_on_ol", "mcp_recarm_norec_ol", "mcp_recarm_auto_ol",
            "mcp_recarm_auto_on_ol", "mcp_recarm_auto_norec_ol" },
        -- the plate's knobs in another style (Classic: the hardware part's own)
        tcp_knob = { "tcp_vol_knob_stack", "tcp_pan_knob_stack", "tcp_wid_knob_stack", "tcp_fxparm_knob_stack", "envcp_knob_stack" },
        mcp_knob = { "mcp_vol_knob_stack", "mcp_pan_knob_stack", "mcp_wid_knob_stack" },
        -- the track panel's knobs and R / M / S: the theme's own, or hardware for the plate (the first differs per variant)
        mcp_hw = { "mcp_vol_knob_stack", "mcp_pan_knob_stack", "mcp_wid_knob_stack", "mcp_mute_off_ol", "mcp_mute_on",
            "mcp_solo_off_ol", "mcp_solo_on", "mcp_recarm_off_ol", "mcp_recarm_on_ol", "mcp_recarm_norec_ol",
            "mcp_recarm_auto_ol", "mcp_recarm_auto_on_ol", "mcp_recarm_auto_norec_ol" },
        tcp_hw = { "tcp_vol_knob_stack", "tcp_pan_knob_stack", "tcp_wid_knob_stack", "tcp_fxparm_knob_stack", "track_mute_off_ol", "track_mute_on",
            "track_solo_off_ol", "track_solo_on", "track_recarm_off_ol", "track_recarm_on_ol", "track_recarm_norec_ol",
            "track_recarm_auto_ol", "track_recarm_auto_on_ol", "track_recarm_auto_norec_ol", "track_mono", "track_stereo_ol",
            "envcp_arm_off_ol", "envcp_arm_on", "envcp_knob_stack" } } }
-- parts that only count on a plate and go over its hardware: the record arm (0.9.95) and the
-- knobs (0.9.97). Their first choice is the hardware's own (OWN): then the hardware is written
parts.RECARM_HW = { tcp_recarm = "tcp_hw", mcp_recarm = "mcp_hw", tcp_knob = "tcp_hw", mcp_knob = "mcp_hw" }
parts.HW_OWN = { tcp_recarm = "cap", mcp_recarm = "cap", tcp_knob = "classic", mcp_knob = "classic" }
-- a look is a theme file of its own, with its own images, colours and parts
local look = { list = { { name = "Dark", theme = "TK Theme Dark" }, { name = "Light", theme = "TK Theme Light" } } }

function look.current()
    local base = (r.GetLastColorThemeFile() or ""):match("([^\\/]+)%.ReaperTheme")
    for _, entry in ipairs(look.list) do
        if entry.theme == base then return entry end
    end
    return nil
end

function parts.load()
    for part, variant in (read_all(parts.file) or ""):gmatch("([%w_]+)=([%w_]+)") do
        parts.chosen[part] = variant
    end
    -- Lamps were a meter type of their own (lying in the plate, LED medium standing)
    if parts.chosen.meter == "lamps" then
        parts.chosen.meter, parts.chosen.meter_lying = "led_m", "lamps"
    end
    -- a chosen meter type: the lying one (Same, by default) is restored with it after an update
    if parts.chosen.meter and not parts.chosen.meter_lying then parts.chosen.meter_lying = "same" end
end

function parts.save()
    r.RecursiveCreateDirectory(r.GetResourcePath() .. "/Data/TK Theme", 0)
    local lines = {}
    for part, variant in pairs(parts.chosen) do lines[#lines + 1] = part .. "=" .. variant end
    write_all(parts.file, table.concat(lines, "\n") .. "\n")
end

-- REAPER takes the TK_ toolbar icons from Data/toolbar_icons, whatever the theme holds,
-- so each look puts its own there. An update puts Dark's back, which the check spots.
function look.apply_icons(entry)
    local pack = here .. "dist/look_icons/" .. entry.theme .. ".zip"
    local data = r.GetResourcePath() .. "/Data/toolbar_icons/"
    if Zip.same_files(pack, data) then return false end
    for _, sub in ipairs({ "150", "200" }) do r.RecursiveCreateDirectory(data .. sub, 0) end
    return Zip.extract(pack, data) == true
end

function parts.zip_path()
    return ((r.GetLastColorThemeFile() or ""):gsub("Zip$", "")) .. "Zip"
end

-- One pack per look and accent colour holds everything to choose from: what the accent
-- changes, keys.txt with its colour lines, and under parts/ every part in that colour.
parts.packs = {}
function parts.pack(zip, accent)
    accent = accent or parts.chosen.accent or parts.default.accent
    local dir = here .. "dist/accents/" .. (zip:match("([^\\/]+)%.ReaperThemeZip$") or "") .. "/"
    local path = dir .. accent .. ".zip"
    if parts.packs[path] == nil then
        -- the accent's own files over what every accent shares (common.zip, not in older packs)
        local own = Zip.read_stored(path)
        local common = own and Zip.read_stored(dir .. "common.zip")
        parts.packs[path] = own and (common and Zip.merge_stored(common, own) or own) or false
    end
    return parts.packs[path]
end

-- Ruler and markers (Window and toolbars): tl_font, REAPER's "Timeline font", which the ruler and
-- the marker and region labels use (tried with a loud font, 2026-11-18). Arial swaps only its
-- face: Myke Robinson's ruler and markers showed wrong characters with this theme and not with
-- Default 7, Inter installed by hand beside the one REAPER ships (not reproduced here). Arial
-- is on Windows and macOS (Linux maps it to Liberation Sans), as Horizon uses
-- a LOGFONTA in hex (60 bytes and a checksum) with another face
function parts.font_with_face(hex, face)
    if #hex < 122 then return hex end
    local b, sum = {}, 0
    for i = 1, 120, 2 do b[#b + 1] = tonumber(hex:sub(i, i + 1), 16) or 0 end
    for i = 29, 60 do b[i] = 0 end
    for i = 1, math.min(#face, 31) do b[28 + i] = face:byte(i) end
    for i = 1, 60 do sum = sum + b[i] b[i] = string.format("%02X", b[i]) end
    return table.concat(b) .. string.format("%02X", sum % 256)
end

-- the colour file's tl_font line for a choice: the look's own (its factory colour file), Arial in it
function parts.ruler_font_keys(variant, zip)
    local theme = (zip or parts.zip_path()):match("([^\\/]+)%.ReaperThemeZip$") or ""
    local own = (read_all(here .. "dist/" .. theme .. ".factory.ReaperTheme") or ""):match("[\r\n]tl_font=(%x+)")
    if not own then return nil end
    return "tl_font=" .. (variant == "arial" and parts.font_with_face(own, "Arial") or own) .. "\n"
end

function parts.read(zip, accent, part, variant, file)
    if part == "time_font" then return file == "keys.txt" and parts.time_font_keys(variant, zip) or nil end
    if part == "ruler_font" then return file == "keys.txt" and parts.ruler_font_keys(variant, zip) or nil end
    if part == "track_lcd" then
        local _, _, shown = parts.lcd_on()
        local display = parts.display_pack(zip, shown)
        return display and display["tracks/" .. (zip:match("([^\\/]+)%.ReaperThemeZip$") or "") .. "/" .. file]
    end
    if part == "display" then
        local display = parts.display_pack(zip, variant)
        return display and display[file]
    end
    if part == "meter_lying" then
        if file == "keys.txt" then return nil end
        part, variant = "meter", parts.lying_type(variant)
        -- the lamps lying Short: a strip of 6 (the 11 would squash)
        if variant == "lamps" and file ~= "preview.png" and global_value("tkPlMeterShort") then variant = "lamps_s" end
    end
    -- Unlit segments off (General > Meters): each type's images with the unlit half see-through
    if part == "meter" and file ~= "preview.png" and global_value("tkMeterNoUnlit") then variant = variant .. "_nu" end
    local pack = parts.pack(zip, accent)
    if not pack then return nil end
    if part == "light_glass" then
        -- the light ones that differ per accent are the pack's own
        local data = parts.glass_get(zip, accent, "parts/light_glass/" .. variant .. "/" .. file)
        if data or file == "keys.txt" then return data end
        return variant == "light" and pack[file] or nil
    end
    -- the track LCDs in a display's colour bring their own glass: the display light's images
    if part == "display_light" and file ~= "preview.png" and file ~= "keys.txt" and parts.lcd_on() then
        local glass = parts.read(zip, accent, "track_lcd", nil, file)
        if glass then return glass end
    end
    -- the meter and the display light on dark glass, when Light has it
    if (part == "meter" or part == "display_light") and parts.glass_dark(zip) then
        local dark = parts.glass_get(zip, accent, "parts/dg_" .. part .. "/" .. variant .. "/" .. file)
        if dark then return dark end
    end
    return pack["parts/" .. part .. "/" .. variant .. "/" .. file]
end

-- the layout's lines for dark glass: "line number<TAB>line", numbered from 0
function parts.glass_layout(text, pack, zip, accent)
    local fix = pack and pack["parts/light_glass/lines.txt"]
    if not fix and zip then fix = parts.glass_get(zip, accent, "parts/light_glass/lines.txt") end
    if not fix or not text then return text end
    local out = {}
    for line in (text .. "\n"):gmatch("(.-)\n") do out[#out + 1] = line end
    for idx, line in fix:gmatch("(%d+)\t([^\n]*)") do
        local at = tonumber(idx) + 1
        if out[at] then out[at] = line .. (out[at]:sub(-1) == "\r" and "\r" or "") end
    end
    if text:sub(-1) ~= "\n" then return table.concat(out, "\n"):sub(1, -1) end
    out[#out] = nil
    return table.concat(out, "\n") .. "\n"
end

-- the type the lying meter shows: Same as standing is the meter's type (Lamps only lie)
function parts.lying_type(variant)
    if variant ~= "same" then return variant end
    return parts.chosen.meter or parts.default.meter
end

-- A display skin is one set for every look, in a pack of its own: the images, keys.txt, and
-- lines.txt with the layout's lines that hold its colours. Standard is per look.
function parts.display_pack(zip, variant)
    local name = variant == "standard" and (zip:match("([^\\/]+)%.ReaperThemeZip$") or "") .. " standard" or variant
    local path = here .. "dist/display/" .. name .. ".zip"
    if parts.packs[path] == nil then parts.packs[path] = Zip.read_stored(path) or false end
    return parts.packs[path]
end

-- Dark glass in the Light look: only Light's packs have it
function parts.is_light(zip)
    return (zip or ""):find("TK Theme Light", 1, true) ~= nil
end

-- what all accents share of dark glass is in glass.zip beside the accents' packs
function parts.glass_get(zip, accent, path)
    local pack = parts.pack(zip, accent)
    local data = pack and pack[path]
    if data then return data end
    local theme = (zip:match("([^\\/]+)%.ReaperThemeZip$") or "")
    local gpath = here .. "dist/accents/" .. theme .. "/glass.zip"
    if parts.packs[gpath] == nil then parts.packs[gpath] = Zip.read_stored(gpath) or false end
    return parts.packs[gpath] and parts.packs[gpath][path] or nil
end

function parts.glass_dark(zip)
    return parts.is_light(zip) and ((parts.glass_now or parts.chosen.light_glass or parts.default.light_glass) == "dark" or (parts.lcd_on()))
end

-- Track LCDs (Look page, Display): whether the track panels' and strips' glass is in the
-- display's colours now, the choice (own, display, full) and the display. A write in progress
-- (parts.lcd_now, parts.display_now) counts over what is chosen: that is noted after the write
parts.LCD_ACCENT = { red = "red", blue = "blue", amber = "orange", violet = "violet", green = "green", ice = "graphite" }
parts.ACCENT_LCD = { red = "red", blue = "blue", orange = "amber", violet = "violet", green = "green", graphite = "ice" }
function parts.lcd_on(shown)
    local mode = parts.lcd_now or parts.chosen.track_lcd or parts.default.track_lcd
    local display = shown or parts.display_now or parts.chosen.display or parts.default.display
    return mode ~= "own" and display ~= "standard", mode, display
end

-- the track LCD images the display's pack has for this look and choice: only the glass for
-- "Display colour", everything on it too for "Like the transport"
function parts.lcd_files(zip, display, mode)
    local dir = "tracks/" .. (zip:match("([^\\/]+)%.ReaperThemeZip$") or "") .. "/"
    local list = {}
    if mode == "display" then
        for rel in (display[dir .. "glass.txt"] or ""):gmatch("[^\r\n]+") do list[#list + 1] = rel end
    elseif mode == "full" then
        for name in pairs(display) do
            local sub = name:sub(#dir + 1, #dir + 4)
            if name:sub(1, #dir) == dir and name:find("%.png$") and sub ~= "own/" and sub:sub(1, 3) ~= "hw/" then
                list[#list + 1] = name:sub(#dir + 1)
            end
        end
        table.sort(list)
    end
    return list, dir
end

-- In "Display colour" and "Like the transport" the display and the accent go together: a
-- display chosen brings its accent, an accent its display (Standard has no colour: the accent
-- stays). Choices that name both (a preset) are left as they are.
function parts.couple(choices)
    local want = {}
    for _, c in ipairs(choices) do want[c[1]] = c[2] end
    local mode = want.track_lcd or parts.chosen.track_lcd or parts.default.track_lcd
    if mode == "own" or (want.accent and want.display) then return choices end
    local out = {}
    local accent_now = parts.chosen.accent or parts.default.accent
    if want.display or want.track_lcd then
        -- the accent first: writing it writes every part again
        local a = parts.LCD_ACCENT[want.display or parts.chosen.display or parts.default.display]
        if a and a ~= accent_now and not want.accent then out[#out + 1] = { "accent", a } end
        for _, c in ipairs(choices) do out[#out + 1] = c end
    elseif want.accent then
        for _, c in ipairs(choices) do out[#out + 1] = c end
        local d = parts.ACCENT_LCD[want.accent]
        if d and d ~= (parts.chosen.display or parts.default.display) then out[#out + 1] = { "display", d } end
    else
        return choices
    end
    return out
end

-- the images of a part, as they are named in the theme. Meters have no scaled versions
function parts.files(part, zip, accent)
    if part == "track_lcd" then
        zip = zip or parts.zip_path()
        local on, mode, shown = parts.lcd_on()
        local display = on and parts.display_pack(zip, shown)
        if not display then return {} end
        return (parts.lcd_files(zip, display, mode))
    end
    if part == "light_glass" then
        -- the panels' glass and what's on it, as the generator found them in this look's pack
        zip = zip or parts.zip_path()
        local pack = parts.pack(zip, accent)
        local files, seen, prefix = {}, {}, "parts/light_glass/dark/"
        parts.glass_get(zip, accent, "")       -- loads glass.zip
        local theme = (zip:match("([^\\/]+)%.ReaperThemeZip$") or "")
        local shared = parts.packs[here .. "dist/accents/" .. theme .. "/glass.zip"]
        for _, src in ipairs({ pack or {}, shared or {} }) do
            for name in pairs(src) do
                if name:sub(1, #prefix) == prefix and not name:find("preview%.png$") and not name:find("keys%.txt$") then
                    local rel = name:sub(#prefix + 1)
                    if not seen[rel] then seen[rel] = true; files[#files + 1] = rel end
                end
            end
        end
        table.sort(files)
        return files
    end
    if part == "basic" then
        local pack = parts.pack(zip or parts.zip_path(), accent) or {}
        local files, prefix = {}, "parts/basic/on/"
        for name in pairs(pack) do
            if name:sub(1, #prefix) == prefix and not name:find("preview%.png$") then files[#files + 1] = name:sub(#prefix + 1) end
        end
        table.sort(files)
        return files
    end
    if part == "display" then return { "transSectionBg.png" } end     -- what parts.in_zip compares
    if part == "mcp_extmixbg" then
        -- the background above the strips (only at 100%, in Default 7 too), and the mixer's list
        -- slots: Lists, Boxes or Plain, as the track panel's (0.9.97)
        local files = { "mcp_extmixbg.png" }
        for _, name in ipairs({ "mcp_fxlist_norm", "mcp_fxlist_byp", "mcp_fxlist_off", "mcp_fxlist_empty", "mcp_sendlist_norm", "mcp_sendlist_mute", "mcp_sendlist_empty", "mcp_sendlist_midihw" }) do
            for _, sub in ipairs({ "", "150/", "200/" }) do files[#files + 1] = sub .. name .. ".png" end
        end
        return files
    end
    if part == "toolbar_text" or part == "send_tint" or part == "shade" or part == "items" or part == "midi_keys" or part == "time_font" or part == "ruler_font" then return {} end  -- lines in the colour file only
    if part ~= "meter" and part ~= "meter_lying" then
        local files = {}
        for _, name in ipairs(parts.images_of[part] or { part }) do
            for _, sub in ipairs({ "", "150/", "200/" }) do files[#files + 1] = sub .. name .. ".png" end
        end
        return files
    end
    -- the first is what parts.in_zip compares: the strip, which differs per type. Standing
    -- meters (the meter part) and the one lying in the plate (meter_lying) are separate files
    local o = part == "meter" and "v" or "h"
    local files = {}
    for _, name in ipairs({ "meter_strip_" .. o, "meter_strip_" .. o .. "_rms", "meter_strip_" .. o .. "_gr", "meter_clip_" .. o }) do
        files[#files + 1] = name .. ".png"
    end
    if o == "v" then files[#files + 1] = "meter_clip_v_rms2.png" end
    return files
end

-- Every value a part's colour lines can have in this look: from each of its choices in
-- each accent colour, and the look's own, which an update puts back.
parts.known_cache = {}
function parts.known(zip, part)
    local theme = zip:match("([^\\/]+)%.ReaperThemeZip$") or ""
    local id = theme .. "|" .. part
    if parts.known_cache[id] then return parts.known_cache[id] end
    local known = {}
    local function add(text)
        for key, value in (text or ""):gmatch("([%w_]+)=(%-?%w+)") do
            known[key] = known[key] or {}
            known[key][value] = true
        end
    end
    if part == "time_font" then
        add(parts.time_font_keys("standard", zip))
        add("trans_font=" .. parts.TIME_FONT_LCD)
    elseif part == "ruler_font" then
        add(parts.ruler_font_keys("inter", zip))
        add(parts.ruler_font_keys("arial", zip))
    elseif part == "display" then
        for _, choice in ipairs(parts.variants.display) do
            local pack = parts.display_pack(zip, choice[1])
            add(pack and pack["keys.txt"])
        end
    else
        local prefix = "parts/" .. part .. "/"
        for _, choice in ipairs(parts.variants.accent) do
            local pack = parts.pack(zip, choice[1])
            for name, data in pairs(pack or {}) do
                if part == "accent" and name == "keys.txt"
                    or name:sub(1, #prefix) == prefix and name:match("^[^/]+/keys%.txt$", #prefix + 1) then
                    add(data)
                end
            end
        end
    end
    for key, value in (read_all(here .. "dist/" .. theme .. ".factory.ReaperTheme") or ""):gmatch("([%w_]+)=(%-?%w+)") do
        if known[key] then known[key][value] = true end
    end
    parts.known_cache[id] = known
    return known
end

-- A part can also need lines in the theme's colour file: keys.txt beside its images.
-- Returns whether that file already has them, and the text it should hold. With
-- parts.keep_own, a colour you set yourself (one no choice of this part has) stays.
function parts.keys(keys, zip, part)
    local loose = zip:gsub("Zip$", "")
    local text = read_all(loose)
    if not keys or not text then return true end
    local known = parts.keep_own and part and parts.known(zip, part)
    local same = true
    for key, value in keys:gmatch("([%w_]+)=(%-?%w+)") do
        text = text:gsub("([\r\n]" .. key .. "=)(%-?%w+)", function(head, old)
            if old == value then return nil end
            if known and not (known[key] and known[key][old]) then return nil end
            same = false
            return head .. value
        end, 1)
    end
    return same, text, loose
end

-- Reversed items: REAPER tints the waveform with the track colour, not the item's background.
-- tinttcp in the layout overrides REAPER's own "Tint media item" preferences: 298 is Default
-- 7's (backgrounds), 2 the waveform.
function parts.layout_fix(text, items)
    items = items or parts.chosen.items or parts.default.items
    local value = items == "reversed" and "2" or "298"
    return (text:gsub("([\r\n])tinttcp %d+", "%1tinttcp " .. value, 1))
end

-- the meter comes from the pack too, so an accent writes the chosen type in its own colour,
-- and the other parts go back over what it holds
function parts.write_accent(variant, zip, root)
    local pack = parts.pack(zip, variant)
    if not pack then return nil, "this colour is missing" end
    local files = {}
    for name, data in pairs(pack) do
        if name ~= "keys.txt" and name:sub(1, 6) ~= "parts/" then
            files[root .. "/" .. name] = name == "rtconfig.txt" and parts.layout_fix(data) or data
        end
    end
    local ok, err = Zip.replace(zip, files)
    if not ok then return nil, err end
    local same, text, loose = parts.keys(pack["keys.txt"], zip, "accent")
    if not same then
        ok, err = Zip.save(loose, text)
        if not ok then return nil, err end
    end
    ok, err = parts.write("meter", parts.chosen.meter or parts.default.meter, zip, variant)
    if not ok then return nil, err end
    ok, err = parts.write("meter_lying", parts.chosen.meter_lying or parts.default.meter_lying, zip, variant)
    if not ok then return nil, err end
    local basic = parts.chosen.basic or parts.default.basic
    if basic == "off" then parts.write("basic", "off", zip, variant) end
    for part, chosen in pairs(parts.chosen) do
        if part ~= "accent" and part ~= "meter" and part ~= "meter_lying" and part ~= "basic" then parts.write(part, chosen, zip, variant) end
    end
    if basic and basic ~= "off" then parts.write("basic", basic, zip, variant) end
    return true
end

-- Standard is the look in the chosen accent colour, so the accent's own images go over it.
-- The layout comes from the accent's pack, as it's the only copy Lua can read.
function parts.write_display(variant, zip, root, accent)
    local display = parts.display_pack(zip, variant)
    local pack = parts.pack(zip, accent)
    if not display or not pack then return nil, "this display is missing" end
    local files = {}
    for name, data in pairs(display) do
        if name:find("%.png$") and name ~= "preview.png" and name:sub(1, 7) ~= "tracks/" then
            files[root .. "/" .. name] = variant == "standard" and pack[name] or data
        end
    end
    -- the track LCDs: Dark's own glass images back where a display's are (the accent's own
    -- over them), then the display's when they are on. Light's own come from its light_glass
    -- part, which writes them before it comes here
    local on, mode = parts.lcd_on(variant)
    local list, dir = parts.lcd_files(zip, display, on and mode or "own")
    local restored = false
    if not parts.is_light(zip) then
        local std = parts.display_pack(zip, "standard") or {}
        local own = dir .. "own/"
        local probe = std[own .. "tcpGlass.png"]
        if probe and Zip.crc_of(zip, root .. "/tcpGlass.png") ~= Zip.crc32(probe) or (on and mode == "display") then
            for name, data in pairs(std) do
                if name:sub(1, #own) == own and name:sub(#own + 1, #own + 3) ~= "hw/" then
                    local rel = name:sub(#own + 1)
                    files[root .. "/" .. rel] = pack[rel] or data
                    restored = true
                end
            end
        end
    end
    if on then
        for _, rel in ipairs(list) do
            local data = display[dir .. rel]
            if data then files[root .. "/" .. rel] = data end
        end
    end
    -- Standard's M, S and mono keys (hw/): in the display's colours with "Like the transport",
    -- else their own, and only on a panel whose hardware is Standard: a plate's (or Basic's)
    -- are its own (0.9.97)
    do
        local full = on and mode == "full"
        local from = full and display or (parts.display_pack(zip, "standard") or {})
        local hwdir = full and (dir .. "hw/") or (dir .. "own/hw/")
        for name, data in pairs(from) do
            if name:sub(1, #hwdir) == hwdir then
                local rel = name:sub(#hwdir + 1)
                local hwp = rel:match("^[%d/]*mcp_") and "mcp_hw" or "tcp_hw"
                if (parts.chosen[hwp] or parts.default[hwp]) == "standard" then files[root .. "/" .. rel] = data end
            end
        end
    end
    local base = pack["rtconfig.txt"] or ""
    if parts.glass_dark(zip) then base = parts.glass_layout(base, pack, zip, accent) end
    if on then
        -- the layout's lines for the track LCDs: numbered from 0, as the light glass's
        local fix = display[dir .. "lines_" .. mode .. ".txt"]
        if fix then
            local out = {}
            for line in (base .. "\n"):gmatch("(.-)\n") do out[#out + 1] = line end
            for idx, line in fix:gmatch("(%d+)\t([^\n]*)") do
                local at = tonumber(idx) + 1
                if out[at] then out[at] = line .. (out[at]:sub(-1) == "\r" and "\r" or "") end
            end
            out[#out] = nil
            base = table.concat(out, "\n") .. "\n"
        end
    end
    local layout = "\n" .. base
    for name, line in (display["lines.txt"] or ""):gmatch("([^\t\n]+)\t([^\n]*)") do
        layout = layout:gsub("\n[ \t]*set " .. name:gsub("%p", "%%%0") .. "[ \t][^\r\n]*", function() return "\n" .. line end, 1)
    end
    if pack["rtconfig.txt"] then files[root .. "/rtconfig.txt"] = parts.layout_fix(layout:sub(2), parts.items_now) end
    local ok, err = Zip.replace(zip, files)
    if not ok then return nil, err end
    -- Basic's buttons go over the glass's own that came back
    local b_now = parts.basic_now or parts.chosen.basic
    if restored and b_now and b_now ~= "off" then
        parts.in_glass = true
        ok, err = parts.write("basic", b_now, zip, accent)
        parts.in_glass = nil
        if not ok then return nil, err end
    end
    -- the track panel's Plain lists over the slots the display brought (Basic writes them
    -- again itself, above)
    if (parts.chosen.tcp_lists or parts.default.tcp_lists) == "plain" and not (restored and b_now and b_now ~= "off") then
        ok, err = parts.write("tcp_lists", "plain", zip, accent)
        if not ok then return nil, err end
    end
    if (parts.chosen.mcp_extmixbg or parts.default.mcp_extmixbg) == "plain" and not (restored and b_now and b_now ~= "off") then
        ok, err = parts.write("mcp_extmixbg", "plain", zip, accent)
        if not ok then return nil, err end
    end
    -- the glass that came back (or the display's) with the display light chosen
    local glow = parts.chosen.display_light or parts.default.display_light
    if (restored or on) and glow ~= parts.default.display_light then
        ok, err = parts.write("display_light", glow, zip, accent)
        if not ok then return nil, err end
    end
    local same, text, loose = parts.keys(display["keys.txt"], zip, "display")
    if same then return true end
    return Zip.save(loose, text)
end

-- Basic's images, for the panels that are Basic (0.9.97): "on" both, "tcp" only the track
-- panel's (and the envelope lanes'), "mixer" only the mixer's, else "off". The other panel
-- keeps its own keys, a plate's its glass ones
function parts.basic_want()
    local t, m = global_value("tkTcpBasic"), global_value("tkMcpBasic")
    if t and m then return "on" end
    if t then return "tcp" end
    if m then return "mixer" end
    return "off"
end

-- the variant a Basic image comes from: with "mixer" or "tcp", on for that panel's, off for
-- the other's
function parts.basic_from(name, variant)
    local v = variant
    if variant == "mixer" or variant == "tcp" then
        -- (the mixer has no bypass image of its own: REAPER draws the track panel's standing one)
        -- (and the master's menu key, i, is the mixer's though not named so)
        local mixer = name:match("^[%d/]*mcp_") ~= nil or name:match("^[%d/]*track_fxon_v") ~= nil
            or name:match("^[%d/]*mixer_menu") ~= nil
        if variant == "mixer" then v = mixer and "on" or "off" else v = mixer and "off" or "on" end
    end
    -- Light under dark glass: the meter's well as Dark's Basic has it (0.9.97; only Light's
    -- packs have on_dg)
    if v == "on" and (name:match("meter_bg_[hv]%.png$") or name:match("tcpGlass%a*Meter%.png$"))
        and parts.glass_dark(parts.zip_path()) then
        v = "on_dg"
    end
    return v
end

function parts.write(part, variant, zip, accent)
    zip = zip or parts.zip_path()
    local root = Zip.root(zip)
    if not root then return nil, "the loaded theme has no zip" end
    if part == "accent" then return parts.write_accent(variant, zip, root) end
    if part == "display" or part == "track_lcd" then
        if part == "display" then parts.display_now = variant else parts.lcd_now = variant end
        local ok, err
        if parts.is_light(zip) then
            ok, err = parts.write("light_glass", parts.chosen.light_glass or parts.default.light_glass, zip, accent)
        else
            ok, err = parts.write_display(parts.display_now or parts.chosen.display or parts.default.display, zip, root, accent)
        end
        parts.display_now, parts.lcd_now = nil, nil
        return ok, err
    end
    if part == "items" then
        -- its colours, then the layout with its tinttcp (from the pack, with the display's lines)
        local same, text, loose = parts.keys(parts.read(zip, accent, part, variant, "keys.txt"), zip, part)
        if not same then
            local ok, err = Zip.save(loose, text)
            if not ok then return nil, err end
        end
        parts.items_now = variant
        local ok, err = parts.write_display(parts.chosen.display or parts.default.display, zip, root, accent)
        parts.items_now = nil
        return ok, err
    end
    if part == "light_glass" then
        if not parts.is_light(zip) then return true end       -- only Light has it
        -- the track LCDs in a display's colour are on dark glass
        if parts.lcd_on() then variant = "dark" end
        parts.glass_now = variant
        local files = {}
        for _, name in ipairs(parts.files(part, zip, accent)) do
            local data = parts.read(zip, accent, part, variant, name)
            if not data then parts.glass_now = nil return nil, "the images of this choice are missing" end
            files[root .. "/" .. name] = data
        end
        local ok, err = true, nil
        if next(files) then ok, err = Zip.replace(zip, files) end
        if ok then
            local same, text, loose = parts.keys(parts.read(zip, accent, part, variant, "keys.txt"), zip, part)
            if not same then ok, err = Zip.save(loose, text) end
        end
        if ok then ok, err = parts.write_display(parts.display_now or parts.chosen.display or parts.default.display, zip, root, accent) end
        for _, p in ipairs({ "meter", "meter_lying", "display_light" }) do
            if ok then ok, err = parts.write(p, parts.chosen[p] or parts.default[p], zip, accent) end
        end
        -- Basic's buttons and lists go over the glass's (with this glass still the one that
        -- counts, and only Basic's own panel: the other's is the glass's now)
        local b_now = parts.basic_now or parts.chosen.basic
        if ok and b_now and b_now ~= "off" then
            parts.in_glass = true
            ok, err = parts.write("basic", b_now, zip, accent)
            parts.in_glass = nil
        end
        parts.glass_now = nil
        return ok, err
    end
    -- record arm on the plates: Cap is the hardware part's own R, so that part is written
    -- again for it; Lamp and Glass only count on a plate (the hardware Silver or Black)
    local recarm_hw = parts.RECARM_HW[part]
    if recarm_hw then
        -- the layout can't see an image: it learns from this that the R is a lamp (a round shadow)
        local lp = (part == "tcp_recarm" and "tkTcpRecLamp") or (part == "mcp_recarm" and "tkMcpRecLamp") or nil
        local want = variant == "lamp" and 1 or 0
        if lp and P[lp] and math.floor(P[lp].value) ~= want then set_param(lp, want, true) end
        local hw = parts.chosen[recarm_hw] or parts.default[recarm_hw]
        if hw ~= "silver" and hw ~= "black" then return true end
        if variant == parts.HW_OWN[part] then
            parts.recarm_skip = true
            local ok, err = parts.write(recarm_hw, hw, zip, accent)
            parts.recarm_skip = nil
            return ok, err
        end
    end
    local files = {}
    for _, name in ipairs(parts.files(part, zip, accent)) do
        local from = part == "basic" and parts.basic_from(name, variant) or variant
        if not (part == "basic" and parts.in_glass and from == "off" and (variant == "mixer" or variant == "tcp")) then
            local data = parts.read(zip, accent, part, from, name)
            if not data then return nil, "the images of this choice are missing" end
            files[root .. "/" .. name] = data
        end
    end
    -- the hardware brings its own R: a chosen Lamp or Glass goes over it again
    if (part == "tcp_hw" or part == "mcp_hw") and not parts.recarm_skip and (variant == "silver" or variant == "black") then
        for rp, hwp in pairs(parts.RECARM_HW) do
            local rv = parts.chosen[rp] or parts.default[rp]
            if hwp == part and rv ~= parts.HW_OWN[rp] then
                for _, name in ipairs(parts.files(rp, zip, accent)) do
                    local data = parts.read(zip, accent, rp, rv, name)
                    if data then files[root .. "/" .. name] = data end
                end
            end
        end
    end
    if next(files) then
        local ok, err = Zip.replace(zip, files)
        if not ok then return nil, err end
    end
    -- Basic on one panel only: the other panel's images just went back to the look's own as
    -- built, over Light's dark glass or the track LCDs (the plate's meter, keys and lists
    -- turned light, and the shared meter background with them). Those go on again, then this
    -- panel's Basic images over them (0.9.97)
    if part == "basic" and (variant == "mixer" or variant == "tcp") and not parts.basic_inner and not parts.in_glass
        and (parts.glass_dark(zip) or parts.lcd_on()) then
        parts.basic_inner, parts.basic_now = true, "off"
        local ok, err
        if parts.is_light(zip) then
            ok, err = parts.write("light_glass", parts.chosen.light_glass or parts.default.light_glass, zip, accent)
        else
            ok, err = parts.write_display(parts.chosen.display or parts.default.display, zip, root, accent)
        end
        parts.basic_now = nil
        if ok then
            local again = {}
            for _, name in ipairs(parts.files("basic", zip, accent)) do
                local v = parts.basic_from(name, variant)
                if v ~= "off" then
                    local data = parts.read(zip, accent, "basic", v, name)
                    if data then again[root .. "/" .. name] = data end
                end
            end
            if next(again) then ok, err = Zip.replace(zip, again) end
        end
        parts.basic_inner = nil
        if not ok then return nil, err end
    end
    if part == "basic" and (parts.chosen.tcp_lists or parts.default.tcp_lists) == "plain" then
        local ok, err = parts.write("tcp_lists", "plain", zip, accent)
        if not ok then return nil, err end
    end
    if part == "basic" and (parts.chosen.mcp_extmixbg or parts.default.mcp_extmixbg) == "plain" then
        local ok, err = parts.write("mcp_extmixbg", "plain", zip, accent)
        if not ok then return nil, err end
    end
    if (part == "tcp_hw" or part == "mcp_hw") and variant == "standard" then
        local ok, err = parts.write_display(parts.chosen.display or parts.default.display, zip, root, accent)
        if not ok then return nil, err end
    end
    if part == "basic" and variant == "off" and parts.is_light(zip) and (parts.chosen.light_glass or parts.default.light_glass) == "dark" then
        -- Basic's off images are the light glass's: the dark glass goes back over them
        parts.basic_now = "off"
        local ok, err = parts.write("light_glass", "dark", zip, accent)
        parts.basic_now = nil
        if not ok then return nil, err end
    end
    -- Basic's images hold R / M / S too (the theme's own): on a plate its hardware goes back
    -- over them, with the record arm chosen for it. Without this a Basic written as the window
    -- opened left the plate with the round buttons until the next opening
    if part == "basic" then
        for _, hwp in ipairs({ "tcp_hw", "mcp_hw" }) do
            local hv = parts.chosen[hwp] or parts.default[hwp]
            if hv == "silver" or hv == "black" then
                local ok, err = parts.write(hwp, hv, zip, accent)
                if not ok then return nil, err end
            end
        end
    end
    local same, text, loose = parts.keys(parts.read(zip, accent, part, variant, "keys.txt"), zip, part)
    if same then return true end
    return Zip.save(loose, text)
end

function parts.accent_in_zip(variant, zip, root)
    local pack = parts.pack(zip, variant)
    if not pack then return true end
    local crcs = Zip.crc_map(zip)
    -- a display skin has its own images, and its colours in the layout
    local chosen = parts.chosen.display or parts.default.display
    local display = chosen ~= parts.default.display and parts.display_pack(zip, chosen)
    local glass = {}
    if parts.glass_dark(zip) then
        for _, name in ipairs(parts.files("light_glass", zip, variant)) do glass[name] = true end
        glass["rtconfig.txt"] = true
    end
    -- files a part chosen other than its default puts in their place (the hardware knobs over
    -- the accent's own, say): the part's own check sees to them. Compared here they always
    -- differed, and the accent was written again, with every part, at each opening
    local by_part = {}
    for part, v in pairs(parts.chosen) do
        if part ~= "accent" and part ~= "display" and v ~= parts.default[part] then
            for _, name in ipairs(parts.files(part, zip, variant)) do by_part[name] = true end
        end
    end
    for name, data in pairs(pack) do
        local skinned = (display and (display[name] or name == "rtconfig.txt")) or glass[name] or by_part[name]
        local want = Zip.stored_crc(pack, name)
        if name == "rtconfig.txt" and (parts.chosen.items or parts.default.items) ~= parts.default.items then
            want = Zip.crc32(parts.layout_fix(data))     -- Reversed items: the layout has its own tinttcp
        end
        if name ~= "keys.txt" and name:sub(1, 6) ~= "parts/" and not skinned and crcs[root .. "/" .. name] ~= want then return false end
    end
    return (parts.keys(pack["keys.txt"], zip, "accent"))
end

function parts.in_zip(part, variant, zip)
    zip = zip or parts.zip_path()
    if part == "light_glass" and parts.is_light(zip) and parts.lcd_on() then return true end
    if part == "track_lcd" and not parts.lcd_on() then return true end
    if parts.RECARM_HW[part] then
        local hw = parts.chosen[parts.RECARM_HW[part]] or parts.default[parts.RECARM_HW[part]]
        if variant == parts.HW_OWN[part] or (hw ~= "silver" and hw ~= "black") then return true end
    end
    local root = Zip.root(zip)
    if part == "accent" then return not root or parts.accent_in_zip(variant, zip, root) end
    -- Basic's images (and the mixer's Basic keys): every file, so one remade on its own
    -- (tk_theme_parts.py) comes in too. Not under Light's dark glass, which has its own.
    if (part == "basic" or (part == "mcp_hw" or part == "tcp_hw") and variant == "basic") and not parts.glass_dark(zip) then
        local pack = parts.pack(zip)
        if not root or not pack then return true end
        local crcs = Zip.crc_map(zip)
        -- Basic off shares files with the hardware (R, M, S, the knobs): a hardware part
        -- chosen puts its own there, and its own check sees to them. Compared here they always
        -- differed, so Basic was written again over the hardware at each opening
        local by_part = {}
        if part == "basic" and variant ~= "on" then
            for other, v in pairs(parts.chosen) do
                if other ~= "basic" and other ~= "accent" and other ~= "display" and v ~= parts.default[other] then
                    for _, name in ipairs(parts.files(other, zip)) do by_part[name] = true end
                end
            end
        end
        for _, name in ipairs(parts.files(part, zip)) do
            local from = part == "basic" and parts.basic_from(name, variant) or variant
            local key = "parts/" .. part .. "/" .. from .. "/" .. name
            -- (one panel Basic under dark glass or track LCDs: the other panel's images are
            -- the glass's or the display's, not Basic's off; see parts.write)
            local other = part == "basic" and (variant == "mixer" or variant == "tcp") and from == "off"
                and (parts.glass_dark(zip) or parts.lcd_on())
            if not other and not by_part[name] and pack[key] and crcs[root .. "/" .. name] ~= Zip.stored_crc(pack, key) then
                if state.log then state.log("in_zip " .. part .. "=" .. variant .. ": " .. name .. " differs") end
                return false
            end
        end
        return true
    end
    -- recoloured in a metal (Materials page, Hardware) and still as drawn: that is in place
    if patina and patina.forge.hw_owns(zip, part) then return (parts.keys(parts.read(zip, nil, part, variant, "keys.txt"), zip, part)) end
    local name = parts.files(part, zip)[1]
    -- Basic on goes over what it shares with other parts (Track LCDs share 290 files with it):
    -- judged by such a file, that part was written again at one opening and Basic at the next,
    -- turn and turn about (seen 2026-11-18). Its first file of its own decides; none, Basic's
    -- own check sees to them
    local b_now = parts.chosen.basic or parts.default.basic
    if part ~= "basic" and b_now and b_now ~= "off" then
        local mine = {}
        for _, n in ipairs(parts.files("basic", zip)) do mine[n] = true end
        name = nil
        for _, n in ipairs(parts.files(part, zip)) do
            if not mine[n] then name = n break end
        end
        if not name then return (parts.keys(parts.read(zip, nil, part, variant, "keys.txt"), zip, part)) end
    end
    if not name then return (parts.keys(parts.read(zip, nil, part, variant, "keys.txt"), zip, part)) end
    local data = parts.read(zip, nil, part, variant, name)
    if not root or not data then return true end
    return Zip.crc_of(zip, root .. "/" .. name) == Zip.crc32(data) and (parts.keys(parts.read(zip, nil, part, variant, "keys.txt"), zip, part))
end

-- REAPER keeps the images of the theme that is already loaded, so step off it first:
-- onto a copy of this theme, or Default 7 if that can't be made. Colours live in the
-- loose .ReaperTheme, so that's what loads, also when the zip itself was chosen.
function parts.loaded_theme()
    local current = r.GetLastColorThemeFile() or ""
    local loose = current:gsub("Zip$", "")
    if loose ~= current and read_all(loose) then return loose, true end
    return current, false
end

-- The theme opened again shows the images just written into its zip: tested in REAPER on
-- 2026-11-15 (tests/TK_Theme_Reload_Probe2.lua), at half the time of the old way. The old
-- way, a full copy loaded first as a stand-in, stays: "standin" in Data/TK Theme/dev.txt
function parts.reload()
    state.log("RELOAD, asked by:" .. (debug.traceback("", 2):gsub("\n%s*", " | "):sub(1, 400)))
    local current = parts.loaded_theme()
    r.PreventUIRefresh(1)
    if parts.standin == nil then
        parts.standin = ((read_all(r.GetResourcePath() .. "/Data/TK Theme/dev.txt") or ""):find("standin", 1, true)) ~= nil
    end
    if parts.standin then
        local config = r.GetResourcePath() .. "/reaper-themeconfig.ini"
        local step = Zip.make_stand_in(current, config)
            or r.GetResourcePath() .. "/ColorThemes/Default_7.0.ReaperThemeZip"
        if read_all(step) then r.OpenColorThemeFile(step) end
        r.OpenColorThemeFile(current)
        Zip.remove_stand_in(current, config)
    else
        r.OpenColorThemeFile(current)
    end
    r.PreventUIRefresh(-1)
    load_params()
    refresh_palette()
    r.ThemeLayout_RefreshAll()
    r.UpdateArrange()
    r.TrackList_AdjustWindows(false)
    r.DockWindowRefresh()
end

-- fn's steps (wear, parts, ...) each write the zip and reload the theme; run together they
-- write it once and reload once. A Style change did both, at twice the wait
function parts.together(fn)
    if not look.current() then return fn() end
    local real, again = parts.reload, false
    parts.reload = function() again = true end
    local ok, res, err = pcall(Zip.batch, parts.zip_path(), function()
        local a, b = fn()
        -- parts written over the hardware's metal (a Style, an accent): drawn again
        if patina and patina.forge and patina.forge.hw_ensure then patina.forge.hw_ensure() end
        return a, b
    end)
    parts.reload = real
    if not ok then state.msg = "Could not change the theme file: " .. tostring(res) .. "."
    elseif res == nil and err then state.msg = "Could not change the theme file: " .. tostring(err) .. "." end
    if again then real() end
end

-- writes each choice into the zip, in order, and notes it as chosen; returns how many
function parts.write_choices(choices, zip)
    local made, meter = 0, false
    for _, choice in ipairs(choices) do
        local wrote, why = parts.write(choice[1], choice[2], zip)
        if wrote then
            parts.chosen[choice[1]] = choice[2]
            made = made + 1
            if choice[1] == "meter" then meter = true end
        else
            state.msg = "Could not change the theme file: " .. tostring(why) .. "."
        end
    end
    -- a lying meter that is the same as standing follows a new standing type, in whatever
    -- order the choices came (presets and undo bring them in any order)
    if meter and (parts.chosen.meter_lying or parts.default.meter_lying) == "same" then
        parts.write("meter_lying", "same", zip)
    end
    return made
end

-- choices: { { part, variant }, ... }, written in that order, as one change to the zip and
-- one reload. Returns whether any of them was made.
function parts.choose_many(choices, forced)
    if #choices == 0 then return false end
    choices = parts.couple(choices)
    if not look.current() then
        state.msg = "Load one of TK Theme's looks first."
        return false
    end
    if not forced and parts.colours_unsaved() then
        state.msg = "Save or undo your colour changes first: this reloads the theme."
        return false
    end
    local zip = parts.zip_path()
    local before, made = {}, 0
    for part, variant in pairs(parts.chosen) do before[part] = variant end
    local ok, err = Zip.batch(zip, function()
        made = parts.write_choices(choices, zip)
        -- parts written over the hardware's metal (an accent the display brought along, say):
        -- drawn again, as parts.together does
        if made > 0 and patina and patina.forge and patina.forge.hw_ensure then patina.forge.hw_ensure() end
        return true
    end)
    if not ok then
        for part in pairs(parts.chosen) do parts.chosen[part] = before[part] end
        state.msg = "Could not change the theme file: " .. tostring(err) .. "."
        return false
    end
    if made == 0 then return false end
    parts.save()
    parts.reload()
    parts.forget_factory()
    return true
end

function parts.mixer_plate_handles(i) return mixer_plate_handles(parts, i) end

function parts.choose(part, variant, forced)
    return parts.choose_many({ { part, variant } }, forced)
end

-- after an update the zip holds the standard images again
function parts.restore()
    parts.load()
    if not look.current() then return end
    local zip = parts.zip_path()
    Zip.hold(function()
        local wrote = false
        parts.keep_own = true
        local ok = Zip.batch(zip, function()
            for part, variant in pairs(parts.chosen) do
                if part ~= "basic" and not parts.in_zip(part, variant, zip) then
                    state.log("restore: " .. part .. "=" .. tostring(variant) .. " not in place, written again")
                    if parts.write(part, variant, zip) then wrote = true end
                end
            end
            local basic = parts.chosen.basic
            if basic and not parts.in_zip("basic", basic, zip) then
                state.log("restore: basic=" .. basic .. " not in place, written again")
                if parts.write("basic", basic, zip) then wrote = true end
            end
            for rp in pairs(parts.RECARM_HW) do
                local rv = parts.chosen[rp]
                if rv and not parts.in_zip(rp, rv, zip) then
                    state.log("restore: " .. rp .. "=" .. rv .. " not in place, written again")
                    if parts.write(rp, rv, zip) then wrote = true end
                end
            end
            return true
        end)
        parts.keep_own = nil
        local changed = wrote and ok
        if look.apply_icons(look.current()) then changed = true state.log("restore: the icons written again") end
        if changed then parts.reload() end
    end)
end

-- the meters' images again, after a switch that picks other ones (Unlit segments; Short,
-- which only the lamps lying have a strip for: lamps_only)
rewrite_meters = function(lamps_only)
    if not look.current() then return end
    local lying = parts.chosen.meter_lying or parts.default.meter_lying
    if lamps_only then
        if parts.lying_type(lying) == "lamps" then parts.choose("meter_lying", lying) end
        return
    end
    parts.choose_many({ { "meter", parts.chosen.meter or parts.default.meter }, { "meter_lying", lying } })
end

-- Your own name on the transport plate (Plate logo: Own name, 5). TK_Theme_Plate.lua sets the
-- two lines in the build's letters (dist/plate_font.bin) and writes the images
-- transPlateOwnBlack / Silver at every scale into the theme; the lines are kept in
-- Data/TK Theme/plate_name.txt, so they come back after an update or in the other look.
local Plate = dofile(here .. "TK_Theme_Plate.lua")
plate_name = { file = r.GetResourcePath() .. "/Data/TK Theme/plate_name.txt", top = "", name = "", loaded = false }

function plate_name.load()
    if plate_name.loaded then return end
    plate_name.loaded = true
    local s = read_all(plate_name.file)
    if s then
        plate_name.top = s:match("top=([^\n]*)") or ""
        plate_name.name = s:match("name=([^\n]*)") or ""
    end
    if plate_name.top == "" and plate_name.name == "" then plate_name.top, plate_name.name = "REAPER SYSTEMS", "TK-S73" end
end

function plate_name.save()
    r.RecursiveCreateDirectory(r.GetResourcePath() .. "/Data/TK Theme", 0)
    write_all(plate_name.file, "top=" .. plate_name.top .. "\nname=" .. plate_name.name .. "\n")
end

function plate_name.font()
    if plate_name.f == nil then plate_name.f = Plate.load(here .. "dist/plate_font.bin") or false end
    return plate_name.f
end

-- the theme's images (or nil), named as in the zip
function plate_name.files(root)
    local font = plate_name.font()
    if not font then return nil end
    local out = {}
    for rel, png in pairs(Plate.images(font, plate_name.top, plate_name.name, Zip.crc32)) do out[root .. "/" .. rel] = png end
    return out
end

-- puts the images in the loaded look's theme when Own name is chosen and they are not
-- there yet (or differ); force: write them anyway. Returns true when it wrote them
function plate_name.ensure(force)
    plate_name.load()
    if not P.tkPlateLogo or math.floor(P.tkPlateLogo.value) ~= 5 or not look.current() then return false end
    local zip = parts.zip_path()
    local root = Zip.root(zip)
    local files = root and plate_name.files(root)
    if not files then return false end
    if not force then
        local same = true
        for name, png in pairs(files) do
            if Zip.crc_of(zip, name) ~= Zip.crc32(png) then same = false break end
        end
        if same then return false end
    end
    local ok, err = Zip.replace(zip, files)
    if not ok then
        state.msg = "Could not write the plate: " .. tostring(err) .. "."
        return false
    end
    parts.reload()
    return true
end

-- the preview: the 200% image on the plate's colour, made again when the text changes
function plate_name.preview()
    local silver = P.tkTransPlate and math.floor(P.tkTransPlate.value) == 2
    local key = (silver and "S" or "B") .. "|" .. plate_name.top .. "|" .. plate_name.name
    if plate_name.key ~= key then
        plate_name.key = key
        if plate_name.img and r.ImGui_Detach then pcall(r.ImGui_Detach, ctx, plate_name.img) end
        plate_name.img = nil
        local font = plate_name.font()
        if font then
            local A, W, H = Plate.coverage(font, plate_name.top, plate_name.name, 2)
            local png = Plate.png(W, H, Plate.rgba(A, W, H, Plate.PLATES[silver and "Silver" or "Black"], 2), Zip.crc32)
            local ok, img = pcall(r.ImGui_CreateImageFromMem, png)
            if ok and img then
                r.ImGui_Attach(ctx, img)
                plate_name.img = img
            end
        end
    end
    return plate_name.img, silver
end

-- Wear on the plates (Wear: Light, Used, Road-worn) and a coffee ring on one track. Nothing
-- of it ships: TK_Theme_Patina.lua draws it from your own seed (Data/TK Theme/patina.txt) for
-- the plates in use, and it goes into the loaded look's theme. tk_patina.txt in the theme
-- says what was drawn, so nothing is drawn again until a choice changes
patina = { lib = dofile(here .. "TK_Theme_Patina.lua"), file = r.GetResourcePath() .. "/Data/TK Theme/patina.txt" }
-- TK Material Forge (proof of concept, the Materials page): your own finish on the plates.
-- Its page is Materials, after Transport; see TK_Theme_Forge.lua
patina.forge = dofile(here .. "TK_Theme_Forge.lua")

-- The plates' Style: Standard, Basic or Material, Material being Silver, Black or a material
-- of your own (the Materials page). What each means is spelled out here, not taken from where
-- its button sits: the parameter values, the hardware part and the mixer's fader handles
patina.STYLE = {
    standard = { value = 0, basic = 0, part = "standard", handles = 1 },
    basic = { value = 0, basic = 1, part = "basic", handles = 1 },
    silver = { value = 1, basic = 0, part = "silver", handles = 2 },
    black = { value = 2, basic = 0, part = "black", handles = 3 },
}

-- the Style item of the track panel ("tcp") or the mixer ("mcp")
function patina.plate_item(kind)
    for _, page in ipairs(PAGES) do
        for _, card in ipairs(page.cards or {}) do
            for _, it in ipairs(card[2]) do
                if it.kind == "plate" and it.plate == kind then return it end
            end
        end
    end
end

function patina.style_of(item)
    local v = P[item.param] and math.floor(P[item.param].value) or 0
    if item.plate == "trans" then           -- the transport counts the other way: 1 Black, 2 Silver
        return v == 2 and "silver" or v == 1 and "black" or "standard"
    end
    if v == 1 then return "silver" elseif v == 2 then return "black" end
    if item.extra and global_value(item.extra) then return "basic" end
    return "standard"
end

-- the Style set: its parameters, then the images that go with it (the hardware, the mixer's
-- handles, Basic's buttons). Callers run it inside parts.together
function patina.set_style(kind, key)
    local item = patina.plate_item(kind)
    local S = patina.STYLE[key]
    if not item or not S or not P[item.param] then return end
    if patina.style_of(item) == key then return end
    if kind == "trans" then
        -- the transport's plate is one parameter, no images go with it
        set_param(item.param, key == "silver" and 2 or key == "black" and 1 or 0, true)
        r.ThemeLayout_RefreshAll()
        return
    end
    set_param(item.param, S.value, true)
    if item.extra then set_param(item.extra, S.basic, true) end
    r.ThemeLayout_RefreshAll()
    if not look.current() then return end
    local list = { { item.part, S.part } }
    if item.mixer_plate then
        for _, more in ipairs(parts.mixer_plate_handles(S.handles)) do list[#list + 1] = more end
    end
    -- Basic's buttons and lists: on with a Basic track panel, or a Basic mixer beside a
    -- track panel without a plate; off goes first, on last
    local want = parts.basic_want()
    if want == "off" then table.insert(list, 1, { "basic", "off" }) else list[#list + 1] = { "basic", want } end
    parts.choose_many(list)
end

patina.STYLE_NAMES = { { "standard", "Standard" }, { "basic", "Basic" }, { "material", "Material" } }

function patina.draw_plate(item, id)
    if not P[item.param] then return end
    row_label(item.label)
    r.ImGui_PushID(ctx, id)
    local now = patina.style_of(item)
    local shown = (now == "silver" or now == "black") and "material" or now
    local first = true
    for _, s in ipairs(patina.STYLE_NAMES) do
        local offered = not item.styles
        for _, k in ipairs(item.styles or {}) do if k == s[1] then offered = true end end
        if not offered then goto next_style end
        if not first then r.ImGui_SameLine(ctx, 0, 2) end
        first = false
        local active = shown == s[1]
        if active then
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), rgba(mix(UI.raised, UI.accent, 0.55)))
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), rgba(UI.ink))
        end
        local clicked = r.ImGui_Button(ctx, s[2], 96, 0)
        if active then r.ImGui_PopStyleColor(ctx, 2) end
        if clicked and not active then
            if s[1] == "material" then
                -- the material this plate had last, or Silver
                patina.forge.use_now(item.plate)
            else
                parts.together(function()
                    patina.set_style(item.plate, s[1])
                    patina.forge.off(item.plate)
                    patina.ensure()
                end)
            end
        end
        ::next_style::
    end
    r.ImGui_PopID(ctx)
end

-- the line under Style when it is Material: which material, and where to change it
function patina.draw_plate_material(item, id)
    local F = patina.forge
    local current
    if item.plate == "rails" then current = F.rail_current() else current = F.current(item.plate) end
    if not current then return end
    row_label(item.label)
    r.ImGui_PushID(ctx, id)
    local page
    for i, pg in ipairs(PAGES) do
        if pg.draw == "materials" then page = i end
    end
    if page then
        local m, name = F.get(F.applied, current)
        local img = F.thumb(m)
        if img then
            r.ImGui_Image(ctx, img, 120, 28)
            r.ImGui_SameLine(ctx)
        end
        r.ImGui_AlignTextToFramePadding(ctx)
        r.ImGui_Text(ctx, name or "?")
        r.ImGui_SameLine(ctx, 0, 12)
        if r.ImGui_Button(ctx, "Change...") then
            F.select(current)
            state.page, state.confirm, state.msg = page, nil, nil
        end
    elseif item.plate ~= "rails" then
        -- without the Materials page: the theme's own two
        for i, key in ipairs({ "Silver", "Black" }) do
            if i > 1 then r.ImGui_SameLine(ctx, 0, 2) end
            local active = current == "base:" .. key
            if active then
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), rgba(mix(UI.raised, UI.accent, 0.55)))
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), rgba(UI.ink))
            end
            local clicked = r.ImGui_Button(ctx, key, 96, 0)
            if active then r.ImGui_PopStyleColor(ctx, 2) end
            if clicked and not active then F.use_now(item.plate, "base:" .. key) end
        end
    end
    r.ImGui_PopID(ctx)
end

function patina.load()
    if patina.seed then return end
    local s = read_all(patina.file)
    patina.seed = s and tonumber(s:match("seed=(%d+)"))
    if not patina.seed then patina.new_seed() end
end

function patina.new_seed()
    patina.seed = math.floor(r.time_precise() * 1000) % 999983 + 1
    r.RecursiveCreateDirectory(r.GetResourcePath() .. "/Data/TK Theme", 0)
    write_all(patina.file, "seed=" .. patina.seed .. "\n")
end

-- Graffiti (Track panel and Mixer pages): TK_Theme_Graffiti.lua draws seven variants per plate
-- from a seed of its own (Data/TK Theme/graffiti.txt); tk_graffiti.txt in the theme says what
-- was drawn. Off, or without plates, its images go out of the theme again
patina.graffiti = { lib = dofile(here .. "TK_Theme_Graffiti.lua"), file = r.GetResourcePath() .. "/Data/TK Theme/graffiti.txt" }

function patina.graffiti_seed(new)
    local G = patina.graffiti
    if not new and G.seed then return G.seed end
    local s = not new and read_all(G.file)
    G.seed = s and tonumber(s:match("seed=(%d+)"))
    if not G.seed then
        G.seed = math.floor(r.time_precise() * 1000) % 999979 + 1
        r.RecursiveCreateDirectory(r.GetResourcePath() .. "/Data/TK Theme", 0)
        write_all(G.file, "seed=" .. G.seed .. "\n")
    end
    return G.seed
end

function patina.graffiti_ensure(force)
    if not look.current() or not P.tkGraffiti then return false end
    local G = patina.graffiti
    local zip = parts.zip_path()
    local root = Zip.root(zip)
    if not root then return false end
    local key_name = root .. "/tk_graffiti.txt"
    local level = math.floor(P.tkGraffiti.value)
    local kinds = { tcp = P.tkTcpPlate ~= nil and P.tkTcpPlate.value > 0, mcp = P.tkMcpPlate ~= nil and P.tkMcpPlate.value > 0 }
    if level == 0 or not (kinds.tcp or kinds.mcp) then
        if not Zip.crc_of(zip, key_name) then return false end
        local files = { [key_name] = false }
        for _, n in ipairs(G.lib.names()) do
            if Zip.crc_of(zip, root .. "/" .. n) then files[root .. "/" .. n] = false end
        end
        Zip.replace(zip, files)
        parts.reload()
        return true
    end
    -- the colours: neon, or the accent's (as the look shows it)
    local palette, pal_key = G.lib.PALETTES.neon, "neon"
    if P.tkGrafColours and P.tkGrafColours.value > 0 then
        local want, rgb = parts.chosen.accent or parts.default.accent, 0x36B9FF
        for _, a in ipairs(parts.variants.accent or {}) do
            if a[1] == want then rgb = look.current().name == "Dark" and a[3] or a[4] end
        end
        palette = G.lib.accent_palette({ rgb >> 16 & 255, rgb >> 8 & 255, rgb & 255 })
        pal_key = string.format("%06x", rgb)
    end
    local seed = patina.graffiti_seed()
    local stickers = P.tkGrafSticker ~= nil and P.tkGrafSticker.value > 0
    local sticker_track = stickers and P.tkGrafStkCol ~= nil and P.tkGrafStkCol.value > 0
    local key = string.format("graffiti 2|%d|%d|%s|%s|%s|%s", level, seed, kinds.tcp and "tcp" or "-", kinds.mcp and "mcp" or "-", pal_key,
        stickers and (sticker_track and "stickers track" or "stickers") or "-")
    if not force and Zip.crc_of(zip, key_name) == Zip.crc32(key) then return false end
    local files = { [key_name] = key }
    local made = G.lib.images(patina.lib.util, { level = level, seed = seed, palette = palette, kinds = kinds, stickers = stickers, sticker_track = sticker_track, png = patina.forge.png_packed }, Zip.crc32)
    for rel, png in pairs(made) do files[root .. "/" .. rel] = png end
    -- a plate without graffiti now: its old images out
    for _, n in ipairs(G.lib.names()) do
        if not made[n] and Zip.crc_of(zip, root .. "/" .. n) then files[root .. "/" .. n] = false end
    end
    local ok, err = Zip.replace(zip, files)
    if not ok then
        state.msg = "Could not write the graffiti: " .. tostring(err) .. "."
        return false
    end
    parts.reload()
    return true
end

function patina.draw_regraffiti(item, id)
    if not look.current() then return end
    r.ImGui_PushID(ctx, id)
    row_label(item.label)
    if r.ImGui_Button(ctx, "New graffiti") then
        patina.graffiti_seed(true)
        parts.together(function() patina.graffiti_ensure(true) end)
    end
    r.ImGui_PopID(ctx)
end

-- draws the images into the loaded look's theme when they are wanted and not there yet;
-- force: draw them anyway (the wear only: the graffiti has its own button). Returns true
-- when it wrote them
function patina.ensure(force)
    local graffiti = patina.graffiti_ensure()
    return patina.wear_ensure(force) or graffiti
end

function patina.wear_ensure(force)
    if not look.current() or not P.tkPatina then return false end
    patina.load()
    local grade = math.floor(P.tkPatina.value)
    local coffee = P.tkCoffee ~= nil and P.tkCoffee.value > 0
    local o = { grade = grade, seed = patina.seed, coffee = coffee,
                tcp = patina.lib.plate(P.tkTcpPlate and P.tkTcpPlate.value), mcp = patina.lib.plate(P.tkMcpPlate and P.tkMcpPlate.value) }
    if (grade == 0 and not coffee) or not (o.tcp or o.mcp) then return false end
    local zip = parts.zip_path()
    local root = Zip.root(zip)
    if not root then return false end
    local key = string.format("wear 1|%d|%d|%s|%s|%s", grade, patina.seed, o.tcp or "-", o.mcp or "-", coffee and "coffee" or "-")
    -- on a plate with your own finish the wear takes its colour (Materials page)
    o.looks = patina.forge.wear_looks()
    for _, kind in ipairs({ "tcp", "mcp" }) do
        local own = o.looks and o.looks[kind]
        if own then key = key .. string.format("|%s %d %d %d %s", kind, own.wear[1], own.wear[2], own.wear[3], own.style or "metal") end
    end
    local key_name = root .. "/tk_patina.txt"
    if not force and Zip.crc_of(zip, key_name) == Zip.crc32(key) then return false end
    local files = { [key_name] = key }
    for rel, png in pairs(patina.lib.images(o, Zip.crc32)) do files[root .. "/" .. rel] = png end
    local ok, err = Zip.replace(zip, files)
    if not ok then
        state.msg = "Could not write the wear: " .. tostring(err) .. "."
        return false
    end
    parts.reload()
    return true
end

-- the coffee on another track than now: one of the project's, at random
function patina.spill()
    local count = r.CountTracks(0)
    local now = P.tkCoffee and math.floor(P.tkCoffee.value) or 0
    local pick = 1
    if count > 1 then
        repeat pick = math.random(1, count) until pick ~= now
    end
    return pick
end

function parts.picture(path)
    if parts.images[path] == nil then
        local ok, image = pcall(r.ImGui_CreateImage, path)
        if ok and image then r.ImGui_Attach(ctx, image) end
        parts.images[path] = ok and image or false
    end
    return parts.images[path]
end

function parts.image(part, variant)
    local zip = parts.zip_path()
    local accent = parts.chosen.accent or parts.default.accent
    local key = zip .. "|" .. accent .. "|" .. part .. "|" .. variant
    if part == "meter_lying" then key = key .. "|" .. parts.lying_type(variant) end   -- Same follows the standing type
    if parts.images[key] == nil then
        local data = parts.read(zip, accent, part, variant, "preview.png")
        -- ReaImGui reports unusable data in REAPER's error window, pcall or not
        local ok, image = false, nil
        if data and data ~= "" then ok, image = pcall(r.ImGui_CreateImageFromMem, data) end
        if ok and image then r.ImGui_Attach(ctx, image) end
        parts.images[key] = ok and image or false
    end
    return parts.images[key]
end

-- Some parameters hold the look's own panel colours, as their defaults: the backgrounds
-- of the transport, track panels and mixer. They are no settings, and must never follow
-- from another look or a preset, so they always stay at this look's default.
function look.own_colours()
    local changed = false
    for _, n in ipairs(order) do
        if (n:find("BgCol[RGB]$") or n:find("StatusCol[RGB]$")) and P[n].value ~= P[n].def then
            set_param(n, math.floor(P[n].def), true)
            changed = true
        end
    end
    return changed
end

-- for presets and undo: what's chosen now, and bringing it back
function look.save_lines(lines)
    local entry = look.current()
    if entry then lines[#lines + 1] = "look=" .. entry.theme end
    for part, variant in pairs(parts.chosen) do lines[#lines + 1] = "part:" .. part .. "=" .. variant end
    -- the materials on the plates, rails and hardware (Materials page)
    if patina and patina.forge then patina.forge.saved_lines(lines) end
end

-- after a preset or undo has set its parameters: its materials, the plates' images and the
-- wear drawn for them now, in one write (the window used to need reopening for it)
function look.materials_from_saved(text, label)
    parts.together(function()
        patina.forge.from_saved(text, label)
        patina.forge.ensure()
        patina.ensure()
    end)
end

-- with_mood: the colour setting goes along to another look (Red Devil, Blue Angel); a
-- preset or undo brings its own colours
function look.apply_saved(text, with_mood)
    local theme = text:match("[\r\n]look=([^\r\n]*)") or look.list[1].theme     -- older ones were all Dark
    local target
    for _, entry in ipairs(look.list) do
        if entry.theme == theme then target = entry end
    end
    local choices, pending = {}, {}
    for part, variant in text:gmatch("[\r\n]part:([%w_]+)=([%w_]+)") do
        if (pending[part] or parts.chosen[part] or parts.default[part]) ~= variant then
            choices[#choices + 1] = { part, variant }
            pending[part] = variant
        end
    end
    -- to another look: its zip gets the parts as it's loaded, so there's nothing to reload
    if target and look.current() ~= target and look.switch(target, true, choices, not with_mood) then return end
    parts.choose_many(choices, true)
end

local HANDLE_PART = "mcp_volthumb"
local HANDLES = { { "cap", "Cap" }, { "classic", "Classic" }, { "classic_accent", "Accent" }, { "slim", "Slim" }, { "ring", "Ring" }, { "dot", "Dot" } }

-- a row of picture buttons; returns the key of the one clicked, if it wasn't on already
function parts.buttons(id, part, choices, current)
    local picked
    local left = r.ImGui_GetCursorPosX(ctx)
    local last_w = 0
    r.ImGui_PushID(ctx, id)
    for i, choice in ipairs(choices) do
        local key, name = choice[1], choice[2]
        if i > 1 then
            r.ImGui_SameLine(ctx, 0, 6)
            -- what doesn't fit goes on a next row, under the first button
            if r.ImGui_GetContentRegionAvail(ctx) < last_w then
                r.ImGui_NewLine(ctx)
                r.ImGui_Dummy(ctx, 0, 2)
                r.ImGui_SetCursorPosX(ctx, left)
            end
        end
        r.ImGui_BeginGroup(ctx)
        local active = key == current
        if active then
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), rgba(mix(UI.raised, UI.accent, 0.55)))
        end
        local x = r.ImGui_GetCursorPosX(ctx)
        local image = not parts.text_buttons[part] and parts.image(part, key)
        local clicked
        if parts.text_buttons[part] then
            clicked = r.ImGui_Button(ctx, name .. "##" .. key, 0, 30)
        elseif image then
            local w, h = r.ImGui_Image_GetSize(image)
            clicked = r.ImGui_ImageButton(ctx, "##" .. key, image, w, h)
        else
            clicked = r.ImGui_Button(ctx, "?##" .. key, 55, 52)
        end
        if active then r.ImGui_PopStyleColor(ctx) end
        local width = r.ImGui_GetItemRectSize(ctx)
        if not parts.text_buttons[part] then
            r.ImGui_SetCursorPosX(ctx, x + (width - r.ImGui_CalcTextSize(ctx, name)) / 2)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), rgba(active and UI.ink or UI.text))
            r.ImGui_Text(ctx, name)
            r.ImGui_PopStyleColor(ctx)
        end
        r.ImGui_EndGroup(ctx)
        last_w = r.ImGui_GetItemRectSize(ctx)
        if clicked and not active then picked = key end
    end
    r.ImGui_PopID(ctx)
    return picked
end

local function draw_handle(item, id)
    if not look.current() then return end
    row_label(item.label)
    local current = parts.chosen[HANDLE_PART] or parts.default[HANDLE_PART]
    local picked = parts.buttons(id, HANDLE_PART, HANDLES, handle_is_dot() and "dot" or current)
    if picked == "dot" then
        set_handle(true)
    elseif picked and (picked == current or parts.choose(HANDLE_PART, picked)) then
        set_handle(false)
    end
end

local METERS = { { "segment", "Segment" }, { "colour", "Colour" }, { "led", "LED" }, { "solid", "Solid" }, { "mono", "Mono" }, { "heat", "Heat" } }
local LYING = { { "same", "Same" }, { "lamps", "Lamps" } }
local WITH_SEGMENTS = { segment = true, colour = true, led = true }

-- a type with segments and its size are one folder: led, led_m, led_l
local function draw_meter(item, id)
    if not look.current() then return end       -- only a look has parts to choose from
    row_label(item.label)
    local current = parts.chosen.meter or parts.default.meter
    local kind, size = current:match("^(%a+)(.*)$")
    local lying = parts.chosen.meter_lying or parts.default.meter_lying
    -- a new standing type: a lying meter that is the same follows it
    local function choose(standing)
        local list = { { "meter", standing } }
        if lying == "same" then list[2] = { "meter_lying", "same" } end
        parts.choose_many(list)
    end
    local picked = parts.buttons(id, "meter", METERS, kind)
    if picked then choose(picked .. (WITH_SEGMENTS[picked] and size or "")) end
    if WITH_SEGMENTS[kind] then
        r.ImGui_Dummy(ctx, 0, 2)
        row_label("Segments")
        local sizes = { { kind, "Fine" }, { kind .. "_m", "Medium" }, { kind .. "_l", "Large" } }
        picked = parts.buttons(id .. "_size", "meter", sizes, current)
        if picked then choose(picked) end
    end
    r.ImGui_Dummy(ctx, 0, 2)
    row_label("Lying")
    picked = parts.buttons(id .. "_lying", "meter_lying", LYING, lying)
    if picked then
        -- the layout can't see an image: it learns from this whether the lamps are lying (no
        -- longer used by the layout, which gives the lamps a short strip of their own)
        if P.tkPlLamps then set_param("tkPlLamps", picked == "lamps" and 1 or 0, true) end
        parts.choose("meter_lying", picked)
    end
    hint_text("The meter lying in the track panel's plate (Plate and Meter in the plate, Track panel page): the same type as standing, or round lamps as on old hi-fi gear.")
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

-- Plate logo: Own name. Two lines (the small one may stay empty), icons that go into the
-- name as [star] and the like, the plate as it will look, and Apply, which writes it
local function draw_plate_name(item, id)
    if not look.current() then return end
    plate_name.load()
    r.ImGui_PushID(ctx, id)
    row_label("Top line")
    r.ImGui_SetNextItemWidth(ctx, CONTROL_W)
    local ch1, v1 = r.ImGui_InputText(ctx, "##top", plate_name.top)
    if ch1 then plate_name.top = v1:sub(1, 40) end
    row_label("Name")
    r.ImGui_SetNextItemWidth(ctx, CONTROL_W)
    local ch2, v2 = r.ImGui_InputText(ctx, "##name", plate_name.name)
    if ch2 then plate_name.name = v2:sub(1, 60) end
    row_label("Icons")
    for i, icon in ipairs(Plate.ICONS) do
        if i > 1 and (i - 1) % 5 ~= 0 then r.ImGui_SameLine(ctx, 0, 2) elseif i > 1 then r.ImGui_SetCursorPosX(ctx, LABEL_W) end
        if r.ImGui_Button(ctx, icon .. "##icon", 54, 0) then plate_name.name = plate_name.name .. "[" .. icon .. "]" end
        if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Adds [" .. icon .. "] to the name.") end
    end
    row_label("Preview")
    local img, silver = plate_name.preview()
    local x, y = r.ImGui_GetCursorScreenPos(ctx)
    local pw, ph = Plate.W * 2 + 16, Plate.H * 2 + 12
    local dl = r.ImGui_GetWindowDrawList(ctx)
    r.ImGui_DrawList_AddRectFilled(dl, x, y, x + pw, y + ph, rgba(silver and 0x9EA1A5 or 0x2C2E31), 4)
    if img then
        r.ImGui_SetCursorScreenPos(ctx, x + 8, y + 6)
        r.ImGui_Image(ctx, img, Plate.W * 2, Plate.H * 2)
    else
        r.ImGui_Dummy(ctx, pw, ph)
        r.ImGui_Text(ctx, "plate_font.bin is missing: update TK Theme.")
    end
    r.ImGui_SetCursorPosX(ctx, LABEL_W)
    if r.ImGui_Button(ctx, "Apply##plate") then
        plate_name.save()
        plate_name.ensure(true)
    end
    r.ImGui_PopID(ctx)
    hint_text("Long lines get smaller to fit the plate. Icons: [star], [heart], [note] and the rest, typed or with the buttons.")
end

-- Wear: other scratches, from a new seed
function patina.draw_rescratch(item, id)
    if not look.current() then return end
    r.ImGui_PushID(ctx, id)
    row_label(item.label)
    if r.ImGui_Button(ctx, "New scratches") then
        patina.new_seed()
        patina.ensure(true)
    end
    r.ImGui_PopID(ctx)
end

-- a coffee ring on one track's plate: spilt on a track at random, again, or wiped off
function patina.draw_coffee(item, id)
    local p = P.tkCoffee
    if not p or not look.current() then return end
    r.ImGui_PushID(ctx, id)
    row_label(item.label)
    local on = math.floor(p.value)
    local function set(v)
        set_param("tkCoffee", v, true)
        r.ThemeLayout_RefreshAll()
        if v > 0 then patina.ensure() end
    end
    if on == 0 then
        if r.ImGui_Button(ctx, "Spill") then set(patina.spill()) end
    else
        r.ImGui_AlignTextToFramePadding(ctx)
        r.ImGui_Text(ctx, "On track " .. on)
        r.ImGui_SameLine(ctx, 0, 8)
        if r.ImGui_Button(ctx, "Spill again") then set(patina.spill()) end
        r.ImGui_SameLine(ctx, 0, 2)
        if r.ImGui_Button(ctx, "Wipe off") then set(0) end
    end
    r.ImGui_PopID(ctx)
    r.ImGui_SetCursorPosX(ctx, LABEL_W)
    hint_text("A dried mug ring on one track's plate, picked at random; in the mixer too.")
end

local function draw_setting(item, id)
    state.mark_item = state.changed(item) and item or nil
    state.row_y = select(2, r.ImGui_GetCursorScreenPos(ctx))
    reload_mark = item.kind == "part" or item.kind == "meter" or item.kind == "handle" or item.kind == "plate" or (item.kind == "choice" and item.part ~= nil)
    if item.kind == "layout" then
        draw_layout_choice(item, id)
    elseif item.kind == "tracks" then
        draw_selected_tracks(id)
    elseif item.kind == "menubar" then
        draw_menubar(item, id)
        if not r.TK_SetMainMenuVisible then return end
    elseif item.kind == "handle" then
        draw_handle(item, id)
    elseif item.kind == "timefont" then
        state.draw_timefont(item, id)
    elseif item.kind == "meter" then
        draw_meter(item, id)
    elseif item.kind == "platename" then
        draw_plate_name(item, id)
    elseif item.kind == "rescratch" then
        patina.draw_rescratch(item, id)
    elseif item.kind == "master_place" then
        state.mastermix.draw(id)
    elseif item.kind == "see" then
        row_label(item.label)
        r.ImGui_PushID(ctx, id)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), rgba(UI.raised))
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), rgba(UI.accent))
        local where = item.page .. (item.card and item.card ~= item.page and ("  >  " .. item.card) or "")
        if r.ImGui_Button(ctx, item.text .. "    " .. where .. "  \u{2192}") then
            state.go_to(item.page, item.card)
        end
        r.ImGui_PopStyleColor(ctx, 3)
        r.ImGui_PopID(ctx)
    elseif item.kind == "see_materials" then
        row_label(item.label)
        r.ImGui_PushID(ctx, id)
        if r.ImGui_Button(ctx, "Wear, coffee ring, graffiti: Materials page") then
            for i, pg in ipairs(PAGES) do
                if pg.draw == "materials" then state.page, state.confirm, state.msg = i, nil, nil end
            end
        end
        r.ImGui_PopID(ctx)
    elseif item.kind == "regraffiti" then
        patina.draw_regraffiti(item, id)
    elseif item.kind == "coffee" then
        patina.draw_coffee(item, id)
    elseif item.kind == "plate" then
        patina.draw_plate(item, id)
    elseif item.kind == "plate_material" then
        patina.draw_plate_material(item, id)
    elseif item.kind == "choice" then
        local names = expand(item.param, item.layouts)
        local p = P[names[1]]
        if not p then return end
        row_label(item.label)
        r.ImGui_PushID(ctx, id)
        local extra = item.extra and P[item.extra]
        local extra_on = extra and math.floor(extra.value) == 1
        -- one width for every button of the row, wide enough for its longest name (at least
        -- 66); a row too wide for the window goes over evenly filled lines under each other
        local bw = 66
        for _, name in ipairs(item.choices) do
            local tw = r.ImGui_CalcTextSize(ctx, name)
            if tw + 16 > bw then bw = math.ceil(tw + 16) end
        end
        -- a choice of where something goes: a drawn picture over its name (TK_Theme_Pics.lua)
        local pic = item.pic and state.pics.has(item.pic) and item.pic
        if pic then bw = math.max(bw, state.pics.WIDTH) end
        local avail = r.ImGui_GetContentRegionAvail(ctx)
        local per_row = #item.choices
        if per_row * (bw + 2) - 2 > avail then
            local rows = math.ceil(per_row * (bw + 2) / math.max(bw + 2, avail + 2))
            per_row = math.max(1, math.ceil(#item.choices / rows))
        end
        for i, name in ipairs(item.choices) do
            if i > 1 then
                if (i - 1) % per_row == 0 then r.ImGui_SetCursorPosX(ctx, LABEL_W) else r.ImGui_SameLine(ctx, 0, 2) end
            end
            local is_extra = extra and i == #item.choices
            local active
            if is_extra then active = extra_on
            else active = math.floor(p.value) == i - 1 and not extra_on end
            if active then
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), rgba(mix(UI.raised, UI.accent, 0.55)))
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), rgba(UI.ink))
            end
            local clicked
            if pic then clicked = state.pics.button(pic, name, i, bw, active)
            else clicked = r.ImGui_Button(ctx, name, bw, 0) end
            if active then r.ImGui_PopStyleColor(ctx, 2) end
            if clicked and not active then
                for _, n in ipairs(names) do set_param(n, is_extra and 0 or i - 1, true) end
                if extra then set_param(item.extra, is_extra and 1 or 0, true) end
                r.ThemeLayout_RefreshAll()
                -- what follows (the wear for this plate, the part that goes with the choice)
                -- goes into the theme in one write and one reload
                parts.together(function()
                    if item.after then item.after(i - 1) end
                    -- a choice that also needs images: the part that goes with it
                    if item.part and item.parts[i] and look.current() then
                        local list = { { item.part, item.parts[i] } }
                        if item.mixer_plate then
                            for _, more in ipairs(parts.mixer_plate_handles(is_extra and 1 or i)) do list[#list + 1] = more end
                        end
                        if extra then
                            -- Basic's buttons and lists: on with a Basic track panel, or a Basic mixer
                            -- beside a track panel without a plate; off goes first, on last
                            local want = parts.basic_want()
                            if want == "off" then table.insert(list, 1, { "basic", "off" }) else list[#list + 1] = { "basic", want } end
                        end
                        parts.choose_many(list)
                    end
                end)
            end
        end
        r.ImGui_PopID(ctx)
    elseif item.kind == "part" then
        if not look.current() then return end
        row_label(item.label)
        local picked = parts.buttons(id, item.part, item.choices, parts.chosen[item.part] or parts.default[item.part])
        if picked then parts.choose(item.part, picked) end
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
                if item.after then item.after(v ~= 0) end
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
    if item.hint and not state.hints_off then
        r.ImGui_SetCursorPosX(ctx, LABEL_W)
        hint_text(item.hint)
    elseif item.hint then
        -- explanations off (the i key in the title row): it shows when you point at the setting
        local wx = r.ImGui_GetWindowPos(ctx)
        local ww = r.ImGui_GetWindowSize(ctx)
        local _, y2 = r.ImGui_GetCursorScreenPos(ctx)
        if r.ImGui_IsWindowHovered(ctx) and not r.ImGui_IsAnyItemActive(ctx)
            and r.ImGui_IsMouseHoveringRect(ctx, wx, state.row_y, wx + ww, y2) then
            r.ImGui_BeginTooltip(ctx)
            r.ImGui_PushTextWrapPos(ctx, 380)
            r.ImGui_Text(ctx, item.hint)
            r.ImGui_PopTextWrapPos(ctx)
            r.ImGui_EndTooltip(ctx)
        end
    end
end

local CHILD_FLAGS = (r.ImGui_ChildFlags_AutoResizeY and r.ImGui_ChildFlags_AutoResizeY() or 0)
    | (r.ImGui_ChildFlags_AlwaysUseWindowPadding and r.ImGui_ChildFlags_AlwaysUseWindowPadding() or 0)

local function begin_card(title, id)
    reload_mark = false
    local flash = state.flash and state.flash.card == title and state.flash
    if flash and flash.scroll then
        r.ImGui_SetScrollHereY(ctx, 0)
        flash.scroll = nil
    end
    if not r.ImGui_BeginChild(ctx, "##card" .. id, 0, 0, CHILD_FLAGS) then return false end
    if flash then
        local age = r.time_precise() - flash.t
        if age > 1.6 then
            state.flash = nil
        else
            local x, y = r.ImGui_GetWindowPos(ctx)
            local w, h = r.ImGui_GetWindowSize(ctx)
            local a = math.floor(255 * math.min(1, (1.6 - age) / 0.6))
            r.ImGui_DrawList_AddRect(r.ImGui_GetWindowDrawList(ctx), x + 1, y + 1, x + w - 1, y + h - 1, rgba(UI.accent, a), 6, 0, 2)
        end
    end
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

-- ---------------------------------------------------------------- changed, and why grey

-- a setting not at the theme's default: its parameters (this layout's, on a per-layout page)
-- or its part
function state.changed(item)
    local part = item.part
    if part and parts.default[part] ~= nil and (parts.chosen[part] or parts.default[part]) ~= parts.default[part] then
        return true
    end
    if item.param then
        for _, n in ipairs(expand(item.param, item.layouts, item.also)) do
            local p = P[n]
            if p and math.floor(p.value + 0.5) ~= math.floor(p.def + 0.5) then return true end
        end
    end
    local e = item.extra and P[item.extra]
    if e and math.floor(e.value + 0.5) ~= math.floor(e.def + 0.5) then return true end
    return false
end

-- a dot in the accent colour after a changed setting's label; a click sets its parameters back
function state.draw_changed_dot(item, after_reload)
    local _, y1 = r.ImGui_GetItemRectMin(ctx)
    local x2, y2 = r.ImGui_GetItemRectMax(ctx)
    local cx, cy = x2 + (after_reload and 24 or 9), (y1 + y2) / 2
    r.ImGui_DrawList_AddCircleFilled(r.ImGui_GetWindowDrawList(ctx), cx, cy, 3, rgba(UI.accent))
    if r.ImGui_IsMouseHoveringRect(ctx, cx - 6, cy - 6, cx + 6, cy + 6) then
        local params = item.param and not item.part and item.kind ~= "plate"
        r.ImGui_SetTooltip(ctx, params and "Changed. Click: back to the theme's default."
            or "Changed: not the theme's default.")
        if params and r.ImGui_IsMouseClicked(ctx, 0) then
            for _, n in ipairs(expand(item.param, item.layouts, item.also)) do
                if P[n] then set_param(n, math.floor(P[n].def + 0.5), true) end
            end
            if item.after then item.after() end
            r.ThemeLayout_RefreshAll()
        end
    end
end

-- to a page, the tab that holds the card, and the card itself (scrolled to, lit a moment)
function state.go_to(title, card)
    for i, pg in ipairs(PAGES) do
        if pg.title == title then
            state.page, state.confirm, state.msg = i, nil, nil
            state.search.clear()
            if card then
                state.tab_want = card
                state.flash = { card = card, t = r.time_precise(), scroll = true }
            end
        end
    end
end

-- under a grey setting: why, and a key to the page that switches it on
function state.draw_why(item, id)
    local why = item.why
    if type(why) == "function" then why = why() end
    if not why then return end
    if state.hints_off then
        -- no text: why it is grey shows when you point at it
        local wx = r.ImGui_GetWindowPos(ctx)
        local ww = r.ImGui_GetWindowSize(ctx)
        local _, y2 = r.ImGui_GetCursorScreenPos(ctx)
        if r.ImGui_IsWindowHovered(ctx) and r.ImGui_IsMouseHoveringRect(ctx, wx, state.row_y or y2, wx + ww, y2) then
            r.ImGui_BeginTooltip(ctx)
            r.ImGui_PushTextWrapPos(ctx, 380)
            r.ImGui_Text(ctx, why)
            r.ImGui_PopTextWrapPos(ctx)
            r.ImGui_EndTooltip(ctx)
        end
        return
    end
    r.ImGui_SetCursorPosX(ctx, LABEL_W)
    hint_text(why)
    local go = item.go
    if type(go) == "function" then go = go() end
    for i, pg in ipairs(go and PAGES or {}) do
        if pg.title == go and i ~= state.page then
            r.ImGui_SetCursorPosX(ctx, LABEL_W)
            if r.ImGui_SmallButton(ctx, "Go to " .. go .. "##why" .. id) then
                state.page, state.confirm, state.msg = i, nil, nil
                state.search.clear()
            end
        end
    end
end

-- what the page shows of a card's item: "hidden", "grey" or "on"; with Only changed, an
-- unchanged one is "skip"
function state.item_show(item)
    if state.only_changed and not state.changed(item) then return "skip" end
    if item.hide and item.hide() then return "hidden" end
    local off = item.off and item.off()
    if off then return item.grey and "grey" or "hidden" end
    return "on"
end

-- the tabs of a page that has them; returns the open tab. A tab with a changed setting has a
-- dot. state.tab_want (a card's title, from the search) opens the tab with that card
function state.draw_tabs(page)
    local open
    if not r.ImGui_BeginTabBar(ctx, "##tabs" .. page.title) then return nil end
    for _, t in ipairs(page.tabs) do
        local has, changed = {}, false
        for _, title in ipairs(t[2]) do has[title] = true end
        for _, card in ipairs(page.cards) do
            if has[card[1]] then
                for _, item in ipairs(card[2]) do
                    if not changed and state.changed(item) then changed = true end
                end
            end
        end
        local flags = 0
        if state.tab_want and has[state.tab_want] then flags = r.ImGui_TabItemFlags_SetSelected() end
        if r.ImGui_BeginTabItem(ctx, t[1] .. (changed and "  \u{2022}" or "") .. "###tab" .. t[1], nil, flags) then
            open = t
            open.has = has
            r.ImGui_EndTabItem(ctx)
        end
    end
    r.ImGui_EndTabBar(ctx)
    state.tab_want = nil
    return open
end

-- on top of a per-layout tab: which layout the settings under it are for
function state.draw_layout_switch(page)
    local hint
    for _, card in ipairs(page.cards) do
        for _, item in ipairs(card[2]) do
            if item.kind == "layout" then hint = item.hint end
        end
    end
    r.ImGui_Dummy(ctx, 0, 2)
    r.ImGui_AlignTextToFramePadding(ctx)
    r.ImGui_Text(ctx, "Settings for layout")
    for _, lay in ipairs({ "A", "B", "C" }) do
        r.ImGui_SameLine(ctx, 0, lay == "A" and 12 or 2)
        local active = tcp_layout == lay
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), rgba(active and UI.accent or UI.raised))
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), rgba(active and UI.base or UI.text))
        if r.ImGui_Button(ctx, lay .. "##layswitch", 56, 0) then tcp_layout = lay end
        r.ImGui_PopStyleColor(ctx, 2)
    end
    hint_text(hint)
    r.ImGui_Dummy(ctx, 0, 4)
end

local function draw_param_page(page)
    -- Only changed: the settings not at the theme's default, the cards without one left out
    local n_changed = 0
    for _, card in ipairs(page.cards) do
        for _, item in ipairs(card[2]) do
            if state.changed(item) then n_changed = n_changed + 1 end
        end
    end
    local oc_changed, oc = r.ImGui_Checkbox(ctx, "Only what I changed (" .. n_changed .. ")##onlychanged", state.only_changed or false)
    if oc_changed then state.only_changed = oc end
    r.ImGui_Dummy(ctx, 0, 2)
    if state.only_changed and n_changed == 0 then
        hint_text("Nothing on this page differs from the theme's defaults.")
    end
    local tab = page.tabs and state.draw_tabs(page)
    if tab and tab.layout then state.draw_layout_switch(page) end
    for ci, card in ipairs(page.cards) do
        local any = not state.only_changed
        for _, item in ipairs(card[2]) do
            if not any and state.changed(item) then any = true end
        end
        if tab and not tab.has[card[1]] then any = false end
        if any and begin_card(card[1], ci) then
            local hidden, by_plate = 0, 0
            for ii, item in ipairs(card[2]) do
                local show = state.item_show(item)
                if tab and item.kind == "layout" then show = "skip" end
                local off = show == "grey"
                if show == "skip" then
                    -- not changed, with Only changed on
                elseif show == "hidden" then
                    hidden = hidden + 1
                    if state.plate_gated and state.plate_gated[item.off] and global_value("tkTcpPlate") then
                        by_plate = by_plate + 1
                    end
                else
                    if off then r.ImGui_BeginDisabled(ctx, true) end
                    draw_setting(item, ci .. "_" .. ii)
                    state.mark_item = nil    -- a kind without a label leaves it
                    if off then
                        r.ImGui_EndDisabled(ctx)
                        state.draw_why(item, ci .. "_" .. ii)
                    end
                end
            end
            if by_plate > 0 then
                hint_text((by_plate == 1 and "1 setting is" or by_plate .. " settings are")
                    .. " hidden by the plate: it places volume, pan, mute, solo and record arm itself,"
                    .. " also on the lowest tracks (pan when the name keeps room).")
                hidden = hidden - by_plate
            end
            if hidden > 0 then
                hint_text(hidden == 1 and "1 setting is hidden: it doesn't apply with the choices above."
                    or hidden .. " settings are hidden: they don't apply with the choices above.")
            end
            r.ImGui_EndChild(ctx)
        end
        if any then r.ImGui_Dummy(ctx, 0, 2) end
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
        { "Empty area", { "col_arrangebg" } }, { "Empty area under the track panels", { "col_tracklistbg" } },
        { "Track lanes", { "col_tr1_bg", "col_tr2_bg" } }, { "Lines between tracks", { "col_tr1_divline", "col_tr2_divline" } },
        { "Grid, measures", { "col_gridlines2" } }, { "Grid, beats", { "col_gridlines3" } }, { "Grid, between beats", { "col_gridlines" } },
        { "Edit cursor", { "col_cursor", "col_cursor2" } }, { "Play cursor", { "playcursor_color" } },
        { "Area selection", { "areasel_fill" } },
    } },
    { "Timeline", {
        { "Background", { "col_tl_bg" } }, { "Numbers", { "col_tl_fg" } }, { "Numbers, in between", { "col_tl_fg2" } },
        { "Time selection", { "col_tl_bgsel", "col_tl_bgsel2" } },
    } },
    { "Markers and regions", {
        { "Markers", { "marker" } }, { "Regions", { "region" } },
        { "Marker lane", { "marker_lane_bg" } }, { "Region lane", { "region_lane_bg" } },
    } },
    { "Media items", {
        { "Items without a colour", { "col_mi_bg", "col_mi_bg2" } }, { "Waveform", { "col_tr1_peaks", "col_tr2_peaks" } },
        { "Waveform when selected", { "col_tr1_ps2", "col_tr2_ps2" } },
        { "Item name", { "col_mi_label" } }, { "Item name when selected", { "col_mi_label_sel" } },
    } },
    { "Mixer", { { "Empty area", { "col_mixerbg" } } } },
    { "Lists in themed windows", {
        { "Background", { "genlist_bg" } }, { "Text", { "genlist_fg" } }, { "Selected row", { "genlist_selbg" } },
        { "Selected text", { "genlist_selfg" } }, { "Highlight", { "genlist_hilite" } },
    } },
}

-- The Inverted colour setting takes the arrange from the other look, with what has to
-- contrast with it. These aren't on the page above, so they are reset along with it.
local ARRANGE_EXTRA = { "selcol_tr1_bg", "selcol_tr2_bg", "arrange_vgrid", "col_mi_label_float", "col_mi_label_float_sel" }

local changed_colours = {}
function parts.colours_unsaved() return next(changed_colours) ~= nil end

local remember_colours     -- further down, once the factory colours are known

local function save_colours()
    local path = theme_file()
    local s = path and read_all(path)
    if not s then return false end
    for key, native in pairs(changed_colours) do
        s = s:gsub("([\r\n]" .. key .. "=)(-?%d+)", function(head, old)
            local v = (tonumber(old) & 0xFF000000) | native_to_file(native)
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
            factory_colours[name] = file_to_native(tonumber(value) & 0xFFFFFF)
        end
        -- an accent colour changes some of what the look comes with, and darkness goes over that
        local zip = parts.zip_path()
        local pack = parts.pack(zip)
        local shade = parts.read(zip, nil, "shade", parts.chosen.shade or parts.default.shade, "keys.txt")
        for _, keys in ipairs({ pack and pack["keys.txt"] or "", shade or "" }) do
            for name, value in keys:gmatch("([%w_]+)=(-?%d+)") do
                factory_colours[name] = file_to_native(tonumber(value) & 0xFFFFFF)
            end
        end
    end
    return factory_colours[key]
end
function parts.forget_factory() factory_colours = nil end

-- a ReaPack update replaces the theme's colour file. The colours that differ from the
-- theme's own are kept here too, and come back when this window opens after an update
local function my_colours_file()
    local entry = look.current()
    return r.GetResourcePath() .. "/Data/TK Theme/my_colours" .. (entry and entry.name ~= "Dark" and "_" .. entry.name or "") .. ".txt"
end

remember_colours = function()
    local lines = {}
    local keys = {}
    for _, group in ipairs(COLOUR_GROUPS) do
        for _, entry in ipairs(group[2]) do
            for _, key in ipairs(entry[2]) do keys[#keys + 1] = key end
        end
    end
    for _, key in ipairs(ARRANGE_EXTRA) do keys[#keys + 1] = key end
    for _, key in ipairs(keys) do
        local factory = factory_colour(key)
        local current = r.GetThemeColor(key, 0) & 0xFFFFFF
        if factory and factory ~= current then lines[#lines + 1] = key .. "=" .. current end
    end
    if #lines == 0 then
        os.remove(my_colours_file())
    else
        r.RecursiveCreateDirectory(r.GetResourcePath() .. "/Data/TK Theme", 0)
        write_all(my_colours_file(), table.concat(lines, "\n") .. "\n")
    end
end

-- only a colour that's back at the theme's own: anything else was changed on purpose
local function restore_my_colours()
    local text = read_all(my_colours_file())
    if not text or not look.current() then return end
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

local function reset_colours()
    for _, group in ipairs(COLOUR_GROUPS) do
        for _, entry in ipairs(group[2]) do
            local native = factory_colour(entry[2][1])
            if native then set_colour(entry, native) end
        end
    end
    for _, key in ipairs(ARRANGE_EXTRA) do
        local native = factory_colour(key)
        if native then set_colour({ key, { key } }, native) end
    end
    repaint_after_colour()
end

local function draw_colours()
    hint_text("Colours REAPER draws itself. Panels, the glass windows and icons are images in the theme, so they keep their colours.")
    r.ImGui_Dummy(ctx, 0, 2)
    if confirm_button("colours_all", "Reset all colours", "Click again to reset all colours") then
        reset_colours()
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
    look.save_lines(lines)
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
        r.DeleteExtState(LISTS_SECTION, "shown-" .. lay, true)
    end
    r.DeleteExtState(LISTS_SECTION, "shown-master", true)
end

local function needs_restart()
    state.restart = true
    r.SetExtState(SCRIPT, "restart", "1", false)
end

local function undo_reset()
    local s = read_all(undo_dir .. "/settings.txt")
    if not s then return false end
    local values = {}
    look.apply_saved(s)
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
    look.own_colours()
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
    look.materials_from_saved(s, "undo")
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
        if not LIVE[n] then
            P[n].value = P[n].def
            r.ThemeLayout_SetParameter(P[n].idx, math.floor(P[n].def), true)
        end
    end
    reset_processing()
    r.ThemeLayout_RefreshAll()
    clear_buttons_and_lists()
    if startup.on then set_startup(false) end
    set_handle(false)
    local choices = {}
    for part, default in pairs(parts.default) do
        if (parts.chosen[part] or default) ~= default then choices[#choices + 1] = { part, default } end
    end
    parts.choose_many(choices, true)
    local notes = {}
    local path = theme_file()
    local base = path and path:match("([^\\/]+)%.ReaperTheme$")
    local factory = base and read_all(here .. "dist/" .. base .. ".factory.ReaperTheme")
    if factory and write_all(path, factory) then
        changed_colours = {}
        os.remove(my_colours_file())
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
-- processing, the look, the meter type and the fader handle. Not what belongs to a project or to REAPER as a whole; dark mode colours
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
    for _, key in ipairs(ARRANGE_EXTRA) do fn(key) end
end

local function save_preset(name, with_dark)
    r.RecursiveCreateDirectory(preset_dir, 0)
    local lines = { "tk_theme_preset=1", "date=" .. os.date("%Y-%m-%d %H:%M") }
    for _, n in ipairs(order) do
        if not LIVE[n] then
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
        lines[#lines + 1] = "colour:" .. key .. "=" .. tostring(native_to_file(r.GetThemeColor(key, 0)))
    end)
    for _, id in ipairs(processing_ids()) do
        local name, _, value = r.ThemeLayout_GetParameter(id)
        if name then lines[#lines + 1] = "processing:" .. id .. "=" .. tostring(math.floor(value)) end
    end
    lines[#lines + 1] = "handle=" .. (handle_is_dot() and "dot" or "cap")
    look.save_lines(lines)
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
    look.apply_saved(s)
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
            colours[colour] = file_to_native(tonumber(native))
        else
            local key, val = line:match("^([%w_]+)=(.*)$")
            if key then values[key] = val end
        end
    end
    -- a setting the preset doesn't know, from a newer version, goes to its default
    for _, n in ipairs(order) do
        if not LIVE[n] then
            local v = params[n] or math.floor(P[n].def)
            P[n].value = v
            r.ThemeLayout_SetParameter(P[n].idx, v, true)
        end
    end
    look.own_colours()
    r.ThemeLayout_RefreshAll()
    if values.handle then set_handle(values.handle == "dot") end
    local notes = {}
    changed_colours = {}
    for _, key in ipairs(ARRANGE_EXTRA) do      -- a preset from before these were kept
        colours[key] = colours[key] or factory_colour(key)
    end
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
    look.materials_from_saved(s, name)
    load_dark()
    refresh_palette()
    repaint_after_colour()
    state.msg = 'Loaded "' .. name .. '". ' .. table.concat(notes, " ")
end

-- ---------------------------------------------------------------- theme codes

-- A theme code (Presets page, Share) is the look as one line of text: what differs from the
-- defaults and from the look's factory colours, the parts, colour processing, fader handle
-- and your name on the plate (TK_Theme_Code.lua packs it). Not the transport buttons'
-- actions, which are numbers on one computer, nor the dark mode colours, which are REAPER's.
local Code = dofile(here .. "TK_Theme_Code.lua")

local function code_data()
    local data = { params = {}, colours = {}, parts = {}, processing = {} }
    local entry = look.current()
    if entry then data.look = entry.theme end
    for _, n in ipairs(order) do
        if not LIVE[n] and math.floor(P[n].value) ~= math.floor(P[n].def) then data.params[n] = math.floor(P[n].value) end
    end
    for part, def in pairs(parts.default) do
        local v = parts.chosen[part] or def
        if v ~= def then data.parts[part] = v end
    end
    colour_keys(function(key)
        local now, fac = r.GetThemeColor(key, 0), factory_colour(key)
        if now and now ~= -1 and fac and (now & 0xFFFFFF) ~= (fac & 0xFFFFFF) then data.colours[key] = native_to_file(now) end
    end)
    for _, id in ipairs(processing_ids()) do
        local name, _, value, def = r.ThemeLayout_GetParameter(id)
        if name and math.floor(value) ~= math.floor(def) then data.processing[id] = math.floor(value) end
    end
    data.handle = handle_is_dot() and "dot" or "cap"
    if P.tkPlateLogo and math.floor(P.tkPlateLogo.value) == 5 then
        plate_name.load()
        data.plate = { top = plate_name.top, name = plate_name.name }
    end
    data.materials = patina.forge.code_materials()
    return data
end

-- the code's look in full: what it doesn't hold goes back to its default, as with a preset
local function apply_code(code)
    local data, why = Code.decode(code, Zip.crc32)
    if not data then
        state.msg = why
        return
    end
    if not look.current() then
        state.msg = "Load one of TK Theme's looks first."
        return
    end
    if not save_undo() then
        state.msg = "Nothing was applied: couldn't save the current settings for undo."
        return
    end
    local unknown = data.unknown or 0
    local lines = { "" }
    if data.look then lines[#lines + 1] = "look=" .. data.look end
    for part, def in pairs(parts.default) do lines[#lines + 1] = "part:" .. part .. "=" .. (data.parts[part] or def) end
    for part in pairs(data.parts) do
        if not parts.default[part] then unknown = unknown + 1 end
    end
    -- everything that writes the theme (the parts, your name, the wear, the materials) in one
    -- write and one reload: each on its own reloaded it, up to four times
    local notes = {}
    parts.together(function()
        look.apply_saved(table.concat(lines, "\n") .. "\n")
        parts.forget_factory()          -- the look may be the other one now
        reset_processing()
        for _, id in ipairs(processing_ids()) do
            if data.processing[id] then r.ThemeLayout_SetParameter(id, data.processing[id], true) end
        end
        for _, n in ipairs(order) do
            if not LIVE[n] then
                local v = data.params[n] or math.floor(P[n].def)
                v = math.max(math.floor(P[n].min), math.min(math.floor(P[n].max), v))
                P[n].value = v
                r.ThemeLayout_SetParameter(P[n].idx, v, true)
            end
        end
        for n in pairs(data.params) do
            if not P[n] then unknown = unknown + 1 end
        end
        look.own_colours()
        r.ThemeLayout_RefreshAll()
        if data.handle then set_handle(data.handle == "dot") end
        changed_colours = {}
        colour_keys(function(key)
            local native = data.colours[key] and file_to_native(data.colours[key]) or factory_colour(key)
            if native then
                r.SetThemeColor(key, native, 1)
                changed_colours[key] = native
            end
        end)
        if not save_colours() then notes[#notes + 1] = "Its colours are shown, but couldn't be saved to the theme file." end
        if data.plate then
            plate_name.load()
            plate_name.top, plate_name.name = data.plate.top:sub(1, 40), data.plate.name:sub(1, 60)
            plate_name.save()
        end
        load_params()
        refresh_palette()
        repaint_after_colour()
        -- the plates' own materials: kept as saved materials, then drawn
        patina.forge.from_code(data.materials)
        plate_name.ensure()
        patina.ensure()
        patina.forge.ensure()
    end)
    if unknown > 0 then
        notes[#notes + 1] = unknown .. (unknown == 1 and " setting is" or " settings are") .. " from a newer TK Theme and left out."
    end
    state.msg = "Theme code applied. " .. table.concat(notes, " ")
end

local function draw_share()
    if not begin_card("Share", "sh") then return end
    hint_text("A theme code is your look as one line of text: post it, and others paste it here. Your transport buttons' actions and the dark mode colours stay out.")
    row_label("Your look")
    if r.ImGui_Button(ctx, "Copy code") then
        local code = Code.encode(code_data(), Zip.crc32)
        r.ImGui_SetClipboardText(ctx, code)
        state.msg = "Copied your theme code (" .. #code .. " characters): paste it where you like."
    end
    row_label("A code to use")
    r.ImGui_SetNextItemWidth(ctx, CONTROL_W)
    local changed, text = r.ImGui_InputText(ctx, "##code_in", state.code_in or "")
    if changed then state.code_in = text end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Paste") then state.code_in = r.ImGui_GetClipboardText(ctx) or "" end
    r.ImGui_SetCursorPosX(ctx, LABEL_W)
    if confirm_button("code_apply", "Apply code", "Click again to apply") then apply_code(state.code_in) end
    r.ImGui_SetCursorPosX(ctx, LABEL_W)
    hint_text("Undo brings back what you had. Save it as a preset to keep it.")
    r.ImGui_EndChild(ctx)
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

local SIGNATURES = {
    { name = "Red Devil", id = "prd", plate = 1, logo = 1,
      saved = "\nlook=TK Theme Dark\npart:accent=red\npart:display=red\npart:shade=black"
          .. "\npart:mcp_volthumb=classic_accent\npart:tcp_thumb=classic_accent\npart:mcp_pan=classic_accent\n",
      hint = "The Dark look in red and near black: red accent colour, red display, Black darkness, the black transport plate with the Red Devil on it, plain rims without track colour, track names in red and classic handles with a red line. Everything else stays as it is, each can be changed back on its own, and Undo brings back what you had." },
    { name = "Blue Angel", id = "pba", plate = 2, logo = 2,
      saved = "\nlook=TK Theme Dark\npart:accent=blue\npart:display=blue\npart:shade=standard"
          .. "\npart:mcp_volthumb=classic_accent\npart:tcp_thumb=classic_accent\npart:mcp_pan=classic_accent\n",
      hint = "The Dark look in blue: blue accent colour, blue display, Standard darkness, the silver transport plate with the Blue Angel on it, plain rims without track colour, track names in blue and classic handles with a blue line. Everything else stays as it is, each can be changed back on its own, and Undo brings back what you had." },
    { name = "Black Metal", id = "pbm", plate = 1, logo = 3, params = { tkTcpPlate = 2, tkMcpPlate = 2, tkWood = 1, tkMcpWood = 1, tkRailRight = 1, tkTcpBasic = 0, tkMcpBasic = 0 },
      saved = "\nlook=TK Theme Dark\npart:accent=red\npart:display=red\npart:shade=black"
          .. "\npart:basic=off\npart:tcp_hw=black\npart:mcp_hw=black\npart:mcp_volthumb=hw\npart:mcp_pan=hw\n",
      hint = "The Dark look as a black rack: black plates on the track panels, the master and the mixer, walnut rails on both sides, red accent colour, red display, Black darkness, and the black transport plate with the Black Metal guitar on it; plain rims without track colour and track names in red. Everything else stays as it is, each can be changed back on its own, and Undo brings back what you had." },
    { name = "Quicksilver", id = "pqs", plate = 2, logo = 4, params = { tkTcpPlate = 1, tkMcpPlate = 1, tkWood = 2, tkMcpWood = 2, tkRailRight = 1, tkTcpBasic = 0, tkMcpBasic = 0 },
      saved = "\nlook=TK Theme Dark\npart:accent=blue\npart:display=blue\npart:shade=standard"
          .. "\npart:basic=off\npart:tcp_hw=silver\npart:mcp_hw=silver\npart:mcp_volthumb=hw\npart:mcp_pan=hw\n",
      hint = "The Dark look as a silver rack: silver plates on the track panels, the master and the mixer, teak rails on both sides, blue accent colour, blue display, Standard darkness, and the silver transport plate with the Quicksilver drop on it; plain rims without track colour and track names in blue. Everything else stays as it is, each can be changed back on its own, and Undo brings back what you had." },
    { name = "Basic Dark", id = "pbd", plate = 0, logo = 0, depth = 30, name_accent = 0, mood = "Neutral", fader_dot = true,
      params = { tkTcpPlate = 0, tkMcpPlate = 0, tkTcpBasic = 1, tkMcpBasic = 1, tkWood = 0, tkMcpWood = 0, tkNumStyle = 0, tkMcpNumStyle = 0, tkTcpLayBtn = 1, tkMcpLayBtn = 1 },
      saved = "\nlook=TK Theme Dark\npart:accent=graphite\npart:display=standard\npart:shade=black\npart:meter=segment"
          .. "\npart:tcp_thumb=dot\npart:mcp_pan=dot\npart:tcp_hw=basic\npart:mcp_hw=basic\npart:basic=on\n",
      hint = "The Dark look flat and quiet, as in most DAWs: Basic track panels and mixer, graphite accent, Neutral colours, Black darkness, a light track colour tint, dot handles and the layout keys." },
    { name = "Basic Light", id = "pbl", plate = 0, logo = 0, depth = 30, name_accent = 0, mood = "Neutral", fader_dot = true,
      params = { tkTcpPlate = 0, tkMcpPlate = 0, tkTcpBasic = 1, tkMcpBasic = 1, tkWood = 0, tkMcpWood = 0, tkNumStyle = 0, tkMcpNumStyle = 0, tkTcpLayBtn = 1, tkMcpLayBtn = 1 },
      saved = "\nlook=TK Theme Light\npart:accent=graphite\npart:display=standard\npart:meter=segment"
          .. "\npart:tcp_thumb=dot\npart:mcp_pan=dot\npart:tcp_hw=basic\npart:mcp_hw=basic\npart:basic=on\n",
      hint = "The Light look flat and quiet, as in most DAWs: Basic track panels and mixer, graphite accent, Neutral colours, a light track colour tint, dot handles and the layout keys." },
}

local function apply_signature(sig)
    if not save_undo() then
        state.msg = "Nothing changed: couldn't save the current settings for undo."
        return
    end
    if handle_is_dot() then set_handle(false) end      -- the mixer's handle by layout, else the cap won't show
    look.keep_mood(look.apply_saved, sig.saved, true)
    set_param("tkTransPlate", sig.plate, true)
    set_param("tkPlateLogo", sig.logo, true)
    for name, value in pairs(sig.params or {}) do set_param(name, value, true) end
    set_param("customColorDepthParam", sig.depth or 0, true)     -- plain rims, unless the preset says
    set_param("tkNameAccent", sig.name_accent or 1, true)
    if sig.fader_dot then set_handle(true) end
    -- a colour setting of its own (keep_mood above put back the one that was on)
    local entry, mood = look.current(), sig.mood and look.mood_named(sig.mood)
    if entry and mood then look.apply_mood(entry, mood) end
    r.ThemeLayout_RefreshAll()
    state.msg = sig.name .. " is on. Undo brings back what you had."
end

local function draw_signatures()
    for _, sig in ipairs(SIGNATURES) do
        if begin_card(sig.name, sig.id) then
            hint_text(sig.hint)
            r.ImGui_SetCursorPosX(ctx, LABEL_W)
            if r.ImGui_Button(ctx, "Apply " .. sig.name) then apply_signature(sig) end
            r.ImGui_EndChild(ctx)
        end
        r.ImGui_Dummy(ctx, 0, 2)
    end
end

local function draw_presets()
    hint_text("A preset holds every setting, colour, the colour processing, chosen actions, the look, the meter type and the fader handle. Track heights belong to a project, and the metronome light at startup and the menu bar stay as they are.")
    r.ImGui_Dummy(ctx, 0, 2)
    draw_signatures()
    draw_share()
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

-- ---------------------------------------------------------------- look

-- REAPER keeps layout settings per theme name, so they go along to the new look, and so
-- does the colour setting. Colours you set yourself stay with each look. choices, from a
-- preset, go into the new look's zip too; own_colours: the caller sets the colours itself.
function look.switch(entry, forced, choices, own_colours)
    local from = look.current()
    if from == entry then return true end
    if not forced and parts.colours_unsaved() then
        state.msg = "Save or undo your colour changes first: they belong to this look."
        return false
    end
    local carry = from and not own_colours and look.current_mood(from)
    local folder = r.GetResourcePath() .. "/ColorThemes/"
    local zip, loose = folder .. entry.theme .. ".ReaperThemeZip", folder .. entry.theme .. ".ReaperTheme"
    if not Zip.root(zip) then
        state.msg = "This look isn't installed: " .. entry.theme .. "."
        return false
    end
    if not read_all(loose) then
        local factory = read_all(here .. "dist/" .. entry.theme .. ".factory.ReaperTheme")
        if factory then write_all(loose, factory) end
    end
    local coming = {}
    for _, choice in ipairs(choices or {}) do coming[choice[1]] = true end
    local before, made = {}, 0
    for part, variant in pairs(parts.chosen) do before[part] = variant end
    local ok, err = Zip.batch(zip, function()
        parts.keep_own = true
        for part, variant in pairs(before) do
            if not coming[part] and not parts.in_zip(part, variant, zip) then parts.write(part, variant, zip) end
        end
        parts.keep_own = nil
        made = parts.write_choices(choices or {}, zip)
        return true
    end)
    parts.keep_own = nil
    if not ok then
        for part in pairs(parts.chosen) do parts.chosen[part] = before[part] end
        made = 0
        if choices and #choices > 0 then state.msg = "Could not change the theme file: " .. tostring(err) .. "." end
    end
    if made > 0 then parts.save() end
    look.apply_icons(entry)

    local on_look, values, processing, layouts = look.current(), {}, {}, {}
    if on_look then
        for _, n in ipairs(order) do
            if not LIVE[n] then values[n] = math.floor(P[n].value) end
        end
        for _, id in ipairs(processing_ids()) do
            local name, _, value = r.ThemeLayout_GetParameter(id)
            if name then processing[id] = math.floor(value) end
        end
        for _, section in ipairs({ "tcp", "master_tcp", "envcp", "trans" }) do
            local ok, name = r.ThemeLayout_GetLayout(section, -1)
            if ok and name ~= "" then layouts[section] = name end
        end
    end
    local dot = handle_is_dot()

    r.PreventUIRefresh(1)
    r.OpenColorThemeFile(read_all(loose) and loose or zip)
    changed_colours, factory_colours = {}, nil
    load_params()
    for n, v in pairs(values) do set_param(n, v, true) end
    for id, v in pairs(processing) do r.ThemeLayout_SetParameter(id, v, true) end
    for section, name in pairs(layouts) do r.ThemeLayout_SetLayout(section, name) end
    look.own_colours()
    if on_look then set_handle(dot) end
    r.PreventUIRefresh(-1)
    load_params()
    refresh_palette()
    if look.current() == entry then
        restore_my_colours()
        if carry then
            look.apply_mood(entry, carry, look.mood_owned(entry))
        elseif not own_colours then
            look.refresh_mood(entry)
        end
    end
    repaint_after_colour()
    if not dark.dirty then load_dark() end
    -- the other look's theme has your name on its plate too, and your wear
    plate_name.ensure()
    patina.ensure()
    patina.forge.ensure()
    return true
end

look.invert_keys = { col_arrangebg = true, col_tr1_bg = true, col_gridlines2 = true, col_gridlines3 = true,
    col_gridlines = true, col_cursor = true }
look.mood_keys = { col_arrangebg = true, col_tracklistbg = true, col_tr1_bg = true, col_gridlines2 = true, col_gridlines3 = true,
    col_gridlines = true, col_mixerbg = true, genlist_bg = true, genlist_selbg = true }

-- colours from the Colours page or a preset stay with a look, which can look like a
-- look that didn't change all the way, so this page says so
-- whether all that differs from the look's own is what a colour setting changes
function look.only_mood_colours()
    for _, group in ipairs(COLOUR_GROUPS) do
        for _, item in ipairs(group[2]) do
            local factory = factory_colour(item[2][1])
            if factory and not look.mood_keys[item[2][1]] and not look.invert_keys[item[2][1]] and factory ~= r.GetThemeColor(item[2][1], 0) & 0xFFFFFF then return false end
        end
    end
    return true
end

function look.has_own_colours()
    local own = false
    colour_keys(function(key)
        local factory = factory_colour(key)
        if factory and factory ~= r.GetThemeColor(key, 0) & 0xFFFFFF then own = true end
    end)
    return own
end

-- Colour settings: the look's own background colours, warmer, cooler or without colour,
-- keeping how light they are. Each has a hue and a saturation (per look) of its own, in HSL:
-- a dark colour then turns as warm or cool as a light one (a factor on red and blue barely
-- moved Dark's near-black backgrounds). They live in the colour file like any other colour,
-- and presets keep them.
local MOODS = { { "Standard" }, { "Warm", hue = 34, dark = 0.26, light = 0.42 }, { "Cool", hue = 214, dark = 0.30, light = 0.42 },
    { "Neutral", hue = 0, dark = 0, light = 0 } }
-- Inverted is a switch over them: each has a twin with the other look's arrange, in that
-- colour setting ("Inverted" is Standard's, the name it had when it was a setting of its own)
for i = 1, 4 do
    local m = MOODS[i]
    local twin = { i == 1 and "Inverted" or (m[1] .. " inverted"), hue = m.hue, dark = m.dark, light = m.light, invert = true }
    m.twin, twin.twin, m.base, twin.base = twin, m, m, m
    MOODS[#MOODS + 1] = twin
end
local MOOD_KEYS = look.mood_keys

function look.mood_named(name)
    for _, m in ipairs(MOODS) do
        if m[1] == name then return m end
    end
end

local function hue_rgb(p, q, t)
    if t < 0 then t = t + 1 elseif t > 1 then t = t - 1 end
    if t < 1 / 6 then return p + (q - p) * 6 * t end
    if t < 1 / 2 then return q end
    if t < 2 / 3 then return p + (q - p) * (2 / 3 - t) * 6 end
    return p
end

function look.mood_colour(native, mood, amount)
    if not mood.hue then return native end
    local rgb = native_to_rgb(native)
    local R, G, B = (rgb >> 16 & 255) / 255, (rgb >> 8 & 255) / 255, (rgb & 255) / 255
    local l = (math.max(R, G, B) + math.min(R, G, B)) / 2     -- the lightness stays
    local s, h = amount, mood.hue / 360
    local out
    if s == 0 then
        local v = math.floor(l * 255 + 0.5)
        out = v << 16 | v << 8 | v
    else
        local q = l < 0.5 and l * (1 + s) or l + s - l * s
        local p = 2 * l - q
        local function ch(t) return math.max(0, math.min(255, math.floor(hue_rgb(p, q, t) * 255 + 0.5))) end
        out = ch(h + 1 / 3) << 16 | ch(h) << 8 | ch(h - 1 / 3)
    end
    return rgb_to_native(out)
end

-- the saturation: Dark's backgrounds need a little more to show as much
function look.mood_amount(entry, mood)
    if not mood.hue then return 0 end
    return entry.name == "Dark" and mood.dark or mood.light
end

-- the same for the other look's arrange (Inverted): its own amount
function look.other_amount(entry, mood)
    if not mood.hue then return 0 end
    return entry.name == "Dark" and mood.light or mood.dark
end

-- the other look's colours as it comes, from the file a factory reset uses
look.other_colours = {}
function look.other_colour(entry, key)
    local other = entry.name == "Dark" and look.list[2] or look.list[1]
    local colours = look.other_colours[other.theme]
    if not colours then
        colours = {}
        local text = read_all(here .. "dist/" .. other.theme .. ".factory.ReaperTheme") or ""
        for name, value in text:gmatch("([%w_]+)=(-?%d+)") do colours[name] = file_to_native(tonumber(value) & 0xFFFFFF) end
        look.other_colours[other.theme] = colours
    end
    return colours[key]
end

-- calls fn for each colour setting a mood changes, with its colour in that mood. All of
-- them, in every mood: Inverted's have to go back when another is chosen
function look.each_mood_colour(entry, mood, fn)
    for _, group in ipairs(COLOUR_GROUPS) do
        for _, item in ipairs(group[2]) do
            local key = item[2][1]
            local factory = (MOOD_KEYS[key] or look.invert_keys[key]) and factory_colour(key)
            if factory then
                local value = look.mood_colour(factory, MOOD_KEYS[key] and mood or MOODS[1], look.mood_amount(entry, mood))
                if mood.invert and look.invert_keys[key] then
                    -- the other look's arrange, in this colour setting
                    local other = look.other_colour(entry, key)
                    value = other and look.mood_colour(other, MOOD_KEYS[key] and mood or MOODS[1], look.other_amount(entry, mood)) or factory
                end
                fn(item, value)
            end
        end
    end
    for _, key in ipairs(ARRANGE_EXTRA) do
        local factory = factory_colour(key)
        if factory then fn({ key, { key } }, mood.invert and look.other_colour(entry, key) or factory) end
    end
end

function look.current_mood(entry)
    for _, mood in ipairs(MOODS) do
        local same = true
        look.each_mood_colour(entry, mood, function(item, value)
            if r.GetThemeColor(item[2][1], 0) & 0xFFFFFF ~= value & 0xFFFFFF then same = false end
        end)
        if same then return mood end
    end
    return nil
end

-- A colour setting goes along to the other look, in that look's version of it. Which one
-- is on is kept with the colours it gave, so they can be told from colours you set yourself.
function look.mood_file(entry)
    return r.GetResourcePath() .. "/Data/TK Theme/mood_" .. entry.name .. ".txt"
end

-- the colours a colour setting may have given this look: any of them now, or the last one
-- chosen, over an accent or darkness since changed. Anything else you set yourself.
function look.mood_owned(entry)
    local owned = {}
    local function add(key, value)
        owned[key] = owned[key] or {}
        owned[key][value & 0xFFFFFF] = true
    end
    for _, mood in ipairs(MOODS) do
        look.each_mood_colour(entry, mood, function(item, value)
            for _, key in ipairs(item[2]) do add(key, value) end
        end)
    end
    for key, value in (read_all(look.mood_file(entry)) or ""):gmatch("[\r\n]([%w_]+)=(%w+)") do
        local v = value == "base" and factory_colour(key) or tonumber(value)
        if v then add(key, v) end
    end
    return owned
end

-- owned: only colours in it change, so your own stay
function look.apply_mood(entry, mood, owned)
    local lines = { "mood=" .. mood[1] }
    look.each_mood_colour(entry, mood, function(item, value)
        if owned then
            for _, key in ipairs(item[2]) do
                if not (owned[key] and owned[key][r.GetThemeColor(key, 0) & 0xFFFFFF]) then return end
            end
        end
        set_colour(item, value)
        for _, key in ipairs(item[2]) do
            local base = (factory_colour(key) or -1) == value & 0xFFFFFF
            lines[#lines + 1] = key .. "=" .. (base and "base" or (value & 0xFFFFFF))
        end
    end)
    repaint_after_colour()
    if not save_colours() then return false end
    r.RecursiveCreateDirectory(r.GetResourcePath() .. "/Data/TK Theme", 0)
    write_all(look.mood_file(entry), table.concat(lines, "\n") .. "\n")
    return true
end

-- without a colour setting to bring along: the last one of this look, if its colours are
-- still what it gave
function look.refresh_mood(entry)
    local text = read_all(look.mood_file(entry))
    local name = text and text:match("^mood=([^\r\n]+)")
    local mood
    for _, m in ipairs(MOODS) do
        if m[1] == name then mood = m end
    end
    if not mood or mood == MOODS[1] or look.current_mood(entry) == mood then return end
    for key, value in text:gmatch("[\r\n]([%w_]+)=(%w+)") do
        local want = value == "base" and factory_colour(key) or tonumber(value)
        if r.GetThemeColor(key, 0) & 0xFFFFFF ~= want then return end
    end
    look.apply_mood(entry, mood)
end

-- Runs fn, which changes the look's own colours (darkness, say), and puts the colour
-- setting that was on back over them; your own colours are then noted against the new ones.
function look.keep_mood(fn, ...)
    local entry = look.current()
    local mood = entry and look.current_mood(entry)
    local res = table.pack(fn(...))
    if res[1] == false then return table.unpack(res, 1, res.n) end
    parts.forget_factory()
    if entry and look.current() == entry and mood and mood ~= MOODS[1] then
        look.apply_mood(entry, mood)
    elseif look.current() then
        remember_colours()
    end
    return table.unpack(res, 1, res.n)
end

local function draw_moods(current)
    local active = look.current_mood(current)
    local inverted = active and active.invert or false
    r.ImGui_Dummy(ctx, 0, 2)
    if not begin_card("Colour setting", "lkm") then return end
    local left = r.ImGui_GetCursorPosX(ctx)
    for i = 1, 4 do
        local mood = inverted and MOODS[i].twin or MOODS[i]
        if i > 1 then state.next_to(90, 6, left) end
        local on = mood == active
        local sample
        if inverted then
            sample = look.other_colour(current, "col_tr1_bg")
            sample = sample and look.mood_colour(sample, mood, look.other_amount(current, mood))
        else
            sample = factory_colour("col_tr1_bg")
            sample = sample and look.mood_colour(sample, mood, look.mood_amount(current, mood))
        end
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), rgba(on and mix(UI.raised, UI.accent, 0.55) or sample and native_to_rgb(sample) or UI.raised))
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), rgba(UI.ink))
        local clicked = r.ImGui_Button(ctx, mood.base[1] .. "##mood", 90, 30)
        r.ImGui_PopStyleColor(ctx, 2)
        if clicked and not on then
            state.msg = look.apply_mood(current, mood) and (mood[1] .. " is on.") or "Could not write the theme file."
        end
    end
    -- the switch: the other look's arrange, in the colour setting that is on (Standard if none)
    state.next_to(100, 16, left)
    r.ImGui_SetCursorPosY(ctx, r.ImGui_GetCursorPosY(ctx) + 5)
    local changed, inv = r.ImGui_Checkbox(ctx, "Inverted##moodinv", inverted)
    if changed then
        local base = active and active.base or MOODS[1]
        local mood = inv and base.twin or base
        state.msg = look.apply_mood(current, mood) and (inv and ("Inverted: " .. (current.name == "Dark" and "Light" or "Dark") .. "'s arrange, " .. base[1] .. ".")
            or (base[1] .. " is on.")) or "Could not write the theme file."
    end
    r.ImGui_Dummy(ctx, 0, 2)
    hint_text("The colours REAPER draws itself: arrange, grid, mixer background and lists. Inverted switches to the other look's arrange, in the colour setting you pick.")
    r.ImGui_EndChild(ctx)
end

-- the accent's own colour per look, for its button
-- orange shows as Amber, the name of the display it goes with (its id stays: presets, codes)
local ACCENTS = { { "blue", "Blue", 0x36B9FF, 0x0A7FD0 }, { "orange", "Amber", 0xFF9F2E, 0xC96A00 }, { "violet", "Violet", 0xB388FF, 0x6A3FD6 }, { "red", "Red", 0xE8303A, 0xC41A24 }, { "green", "Green", 0x3FD88A, 0x1F9A57 }, { "graphite", "Graphite", 0xA8AEB8, 0x5C6370 } }

local DISPLAYS = { { "standard", "Standard" }, { "ice", "Ice" }, { "amber", "Amber" }, { "green", "Green" }, { "red", "Red" }, { "blue", "Blue" }, { "violet", "Violet" } }
parts.variants = { accent = ACCENTS, display = DISPLAYS,
    track_lcd = { { "own", "As now" }, { "display", "Display colour" }, { "full", "Like the transport" } },
    time_font = { { "standard", "Standard" }, { "lcd", "LCD" } } }
parts.text_buttons = { track_lcd = true, time_font = true, ruler_font = true }

-- The transport's time in an LCD font (Transport page, Time display): TK LCD, DSEG14 Classic Bold
-- by keshikan with its glyphs at 65.5% of its line (tk_theme_lcd_font.py: REAPER picks the time's
-- line height itself, and DSEG's digits fill the whole line), free under the SIL Open Font License (dist/fonts, licence beside it). A theme can't
-- bring a font, so a button puts it in the user's own font folder (no admin rights); REAPER
-- sees it after a restart. trans_font is the transport's own font: only the big time changes
parts.TIME_FONT_FILE = "TKLCD-Bold.ttf"
parts.TIME_FONT_LCD = "ECFFFFFF000000000000000000000000BC0200000000000003020122544B204C4344000000000000000000000000000000000000000000000000000061"
function parts.font_dirs()
    local test = os.getenv("TK_TEST_FONT_DIR")
    if test then return { test } end
    local home = os.getenv("HOME") or os.getenv("USERPROFILE") or ""
    if IS_WINDOWS then
        return { (os.getenv("LOCALAPPDATA") or (home .. "\\AppData\\Local")) .. "\\Microsoft\\Windows\\Fonts",
                 (os.getenv("WINDIR") or "C:\\Windows") .. "\\Fonts" }
    elseif r.GetOS():find("OSX", 1, true) or r.GetOS():find("mac", 1, true) then
        return { home .. "/Library/Fonts", "/Library/Fonts" }
    end
    return { home .. "/.local/share/fonts", home .. "/.fonts", "/usr/share/fonts/truetype", "/usr/local/share/fonts" }
end

function parts.time_font_installed()
    for _, dir in ipairs(parts.font_dirs()) do
        local f = io.open(dir .. "/" .. parts.TIME_FONT_FILE, "rb")
        if f then f:close() return true end
    end
    return false
end

-- the colour file's line for a choice: Standard is the look's own (its factory colour file),
-- and LCD only where the font is installed (a preset from another computer keeps Standard)
function parts.time_font_keys(variant, zip)
    if variant == "lcd" and parts.time_font_installed() then return "trans_font=" .. parts.TIME_FONT_LCD .. "\n" end
    local theme = (zip or parts.zip_path()):match("([^\\/]+)%.ReaperThemeZip$") or ""
    local own = (read_all(here .. "dist/" .. theme .. ".factory.ReaperTheme") or ""):match("[\r\n]trans_font=(%x+)")
    return own and ("trans_font=" .. own .. "\n") or nil
end

function parts.install_time_font()
    local data = read_all(here .. "dist/fonts/" .. parts.TIME_FONT_FILE)
    if not data then return nil, "the font file is missing from TK Theme's folder" end
    local dir = parts.font_dirs()[1]
    r.RecursiveCreateDirectory(dir, 0)
    local path = dir .. (IS_WINDOWS and "\\" or "/") .. parts.TIME_FONT_FILE
    if not write_all(path, data) then return nil, "could not write " .. path end
    if IS_WINDOWS then
        -- registered for this user only, as Windows' own "Install" does without admin rights
        r.ExecProcess('reg add "HKCU\\Software\\Microsoft\\Windows NT\\CurrentVersion\\Fonts" /v "TK LCD Bold (TrueType)" /t REG_SZ /d "'
            .. path .. '" /f', 10000)
    elseif not (r.GetOS():find("OSX", 1, true) or r.GetOS():find("mac", 1, true)) then
        r.ExecProcess('fc-cache -f "' .. dir .. '"', 30000)
    end
    state.time_font_fresh = true
    return true
end

-- Transport page, Time display: Install first, then Standard or LCD
state.draw_timefont = function(item, id)
    if not look.current() then return end
    row_label(item.label)
    local chosen = parts.chosen.time_font or parts.default.time_font
    if not parts.time_font_installed() then
        r.ImGui_PushID(ctx, id)
        if r.ImGui_Button(ctx, "Install LCD font") then
            local ok, err = parts.install_time_font()
            state.msg = ok and "LCD font installed: choose LCD here. If the time keeps the standard font, restart REAPER." or ("Could not install the font: " .. tostring(err) .. ".")
        end
        r.ImGui_PopID(ctx)
        hint_text("TK LCD, made from DSEG14 by keshikan (free, SIL Open Font License): the transport's time as on a hardware display. It goes into your own font folder, no admin rights needed. Usually it works at once; otherwise after restarting REAPER.")
        if chosen == "lcd" then
            hint_text("LCD is chosen (by a preset or code), but the font isn't installed here: the time shows the standard font.")
        end
        return
    end
    local picked = parts.buttons(id, "time_font", parts.variants.time_font, chosen)
    if picked and parts.choose("time_font", picked) then state.msg = "Time display changed." end
    if state.time_font_fresh then
        hint_text("Installed just now: if LCD shows the standard font, restart REAPER.")
    end
    hint_text("LCD: TK LCD (from DSEG14), as on a hardware display. Only the big time; the selection and BPM keep the theme's font. The font has no square brackets, which REAPER puts around the play state. Reloads the theme.")
end

-- Accent colour, display and track LCDs are picked first and applied together: one rebuild,
-- however many of them change. What Apply will bring shows at once, the accent or display that
-- goes along with the track LCDs too (parts.couple)
parts.pending = {}
parts.PENDING = { "accent", "display", "track_lcd" }
function parts.shown(part)
    return parts.pending[part] or parts.chosen[part] or parts.default[part]
end

function parts.stage(part, variant)
    local p = parts.pending
    p[part] = variant
    if parts.shown("track_lcd") ~= "own" then
        if part == "accent" then
            p.display = parts.ACCENT_LCD[variant] or p.display
        else
            p.accent = parts.LCD_ACCENT[parts.shown("display")] or p.accent
        end
    end
    for _, k in ipairs(parts.PENDING) do
        if p[k] == (parts.chosen[k] or parts.default[k]) then p[k] = nil end
    end
end

function parts.apply_pending()
    local p, list = parts.pending, {}
    for _, k in ipairs(parts.PENDING) do
        if p[k] then list[#list + 1] = { k, p[k] } end
    end
    if #list == 0 then return false end
    -- a choice that shows nothing (the track LCDs while the display is Standard) is only noted
    local mode = p.track_lcd or parts.chosen.track_lcd or parts.default.track_lcd
    local shown = p.display or parts.chosen.display or parts.default.display
    if #list == 1 and p.track_lcd and not parts.lcd_on() and (mode == "own" or shown == "standard") then
        parts.chosen.track_lcd = p.track_lcd
        parts.save()
        parts.pending = {}
        return true
    end
    local ok = look.keep_mood(parts.choose_many, list)
    if ok then parts.pending = {} end
    return ok
end

-- the Apply row, under the accent colours and under the display while something waits
function parts.draw_apply(id)
    local p = parts.pending
    if not (p.accent or p.display or p.track_lcd) then return end
    local function label(list, key)
        for _, c in ipairs(list) do if c[1] == key then return c[2] end end
        return key
    end
    local names = {}
    if p.accent then names[#names + 1] = "accent " .. label(ACCENTS, p.accent) end
    if p.display then names[#names + 1] = "display " .. label(DISPLAYS, p.display) end
    if p.track_lcd then names[#names + 1] = "track LCDs " .. label(parts.variants.track_lcd, p.track_lcd) end
    r.ImGui_Dummy(ctx, 0, 4)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), rgba(UI.accent))
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), rgba(UI.base))
    local go = r.ImGui_Button(ctx, "Apply##apply" .. id, 90, 28)
    r.ImGui_PopStyleColor(ctx, 2)
    r.ImGui_SameLine(ctx, 0, 6)
    local undo = r.ImGui_Button(ctx, "Cancel##cancel" .. id, 70, 28)
    hint_text("Not applied yet: " .. table.concat(names, ", ") .. ". Apply rebuilds the theme once for all of it.")
    if go and parts.apply_pending() then state.msg = "Applied: " .. table.concat(names, ", ") .. "." end
    if undo then parts.pending = {} end
end

local function draw_display()
    r.ImGui_Dummy(ctx, 0, 2)
    if not begin_card("Display", "lkv") then return end
    local picked = parts.buttons("display", "display", DISPLAYS, parts.shown("display"))
    if picked then parts.stage("display", picked) end
    r.ImGui_Dummy(ctx, 0, 2)
    hint_text("The transport's glass in one colour, as on hardware. Standard follows the accent colour.")
    r.ImGui_Dummy(ctx, 0, 4)
    r.ImGui_Text(ctx, "Track LCDs")
    local lcd = parts.buttons("track_lcd", "track_lcd", parts.variants.track_lcd, parts.shown("track_lcd"))
    if lcd then parts.stage("track_lcd", lcd) end
    r.ImGui_Dummy(ctx, 0, 2)
    hint_text("The display windows of the track panels and the mixer. Display colour: in the display's colour, and the accent goes with the display (Ice with Graphite; Standard keeps your accent). Like the transport: their buttons in it too, dimmed when off. Unselected tracks dimmed: General page, Displays.")
    parts.draw_apply("display")
    r.ImGui_EndChild(ctx)
end

local SHADES = { { "standard", "Standard" }, { "black", "Black" } }

-- Light by day, Dark by night: the watcher switches when the schedule turns
local function draw_auto()
    r.ImGui_Dummy(ctx, 0, 2)
    if not begin_card("Day and night", "lka") then return end
    local on = Auto.on()
    row_label("Switch by the time of day")
    if toggle("auto_on", on) then
        on = not on
        Auto.enable(on)
        if on then
            start_watcher()
            state.msg = "Day and night is on: the look follows the time of day."
        end
    end
    local light, dark = Auto.times()
    for _, t in ipairs({ { "light", "Light from", light }, { "dark", "Dark from", dark } }) do
        local key, label, minute = t[1], t[2], t[3]
        row_label(label)
        r.ImGui_SetNextItemWidth(ctx, 70)
        local shown = state["auto_" .. key] or string.format("%02d:%02d", minute // 60, minute % 60)
        local changed, text = r.ImGui_InputText(ctx, "##auto_" .. key, shown)
        if changed then state["auto_" .. key] = text end
        if r.ImGui_IsItemDeactivatedAfterEdit(ctx) then
            if Auto.set_time(key, state["auto_" .. key]) then
                state.msg = label .. " " .. select(2, Auto.parse(state["auto_" .. key])) .. "."
            else
                state.msg = "Not a time: use hours and minutes, like 08:00 or 19:30."
            end
            state["auto_" .. key] = nil
        end
    end
    row_label("Note it in the console")
    local notify = r.GetExtState(Auto.SECTION, "notify") ~= "0"
    if toggle("auto_notify", notify) then r.SetExtState(Auto.SECTION, "notify", notify and "0" or "1", true) end
    r.ImGui_Dummy(ctx, 0, 2)
    hint_text("Switches Light and Dark at these times, never while REAPER plays or records. Needs \"Metronome and grid at startup\" on the Transport page.")
    if on and light == dark then
        hint_text("Light and Dark start at the same time, so nothing switches.")
    end
    r.ImGui_EndChild(ctx)
end

local function draw_shade()
    r.ImGui_Dummy(ctx, 0, 2)
    if not begin_card("Darkness", "lks") then return end
    local picked = parts.buttons("shade", "shade", SHADES, parts.chosen.shade or parts.default.shade)
    if picked and look.keep_mood(parts.choose, "shade", picked) then state.msg = "Darkness changed." end
    r.ImGui_Dummy(ctx, 0, 2)
    hint_text("Black takes the arrange, lanes, lists, mixer and MIDI editor close to black. Reloads the theme.")
    r.ImGui_EndChild(ctx)
end

local function draw_accents(current)
    r.ImGui_Dummy(ctx, 0, 2)
    if not begin_card("Accent colour", "lka") then return end
    local chosen = parts.shown("accent")
    local left = r.ImGui_GetCursorPosX(ctx)
    for i, accent in ipairs(ACCENTS) do
        if i > 1 then state.next_to(90, 6, left) end
        local colour = current.name == "Dark" and accent[3] or accent[4]
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), rgba(colour))
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), rgba(mix(colour, 0xFFFFFF, 0.15)))
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), rgba(current.name == "Dark" and 0x0A1115 or 0xFFFFFF))
        local clicked = r.ImGui_Button(ctx, accent[2] .. "##accent", 90, 30)
        r.ImGui_PopStyleColor(ctx, 3)
        if accent[1] == chosen then
            local x, y = r.ImGui_GetItemRectMin(ctx)
            local x2, y2 = r.ImGui_GetItemRectMax(ctx)
            r.ImGui_DrawList_AddRect(r.ImGui_GetWindowDrawList(ctx), x - 2, y - 2, x2 + 2, y2 + 2, rgba(UI.ink), 3, 0, 2)
        elseif clicked then
            parts.stage("accent", accent[1])
        end
    end
    r.ImGui_Dummy(ctx, 0, 2)
    hint_text("The colour of what's on: selections, FX, highlights, meters. Mute, solo, record and play keep theirs. Apply rebuilds the theme.")
    parts.draw_apply("accent")
    r.ImGui_EndChild(ctx)
end

local function draw_look()
    hint_text("A look sets the theme's colours and images. Your settings and choices below go along.")
    r.ImGui_Dummy(ctx, 0, 2)
    local current = look.current()
    if begin_card("Look", "lk") then
        for _, entry in ipairs(look.list) do
            r.ImGui_PushID(ctx, entry.name)
            local active = current == entry
            if active then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), rgba(mix(UI.raised, UI.accent, 0.55))) end
            local image = parts.picture(here .. "dist/looks/" .. entry.theme .. ".png")
            local clicked
            if image then
                local w, h = r.ImGui_Image_GetSize(image)
                clicked = r.ImGui_ImageButton(ctx, "##look", image, w, h)
            else
                clicked = r.ImGui_Button(ctx, "?##look", 120, 52)
            end
            if active then r.ImGui_PopStyleColor(ctx) end
            r.ImGui_SameLine(ctx, 0, 10)
            r.ImGui_AlignTextToFramePadding(ctx)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), rgba(active and UI.ink or UI.text))
            r.ImGui_Text(ctx, entry.name)
            r.ImGui_PopStyleColor(ctx)
            if clicked and not active and look.switch(entry) then
                state.msg = entry.name .. " is on."
            end
            r.ImGui_PopID(ctx)
        end
        if not current then
            hint_text("Another theme is loaded now. Choosing a look loads TK Theme, with its settings as you last left them.")
        elseif look.has_own_colours() and not (look.current_mood(current) and look.only_mood_colours()) then
            r.ImGui_Dummy(ctx, 0, 2)
            hint_text("This look uses your own colours, from the Colours page or a preset. They are why it can differ from the picture above.")
            if confirm_button("look_colours", "Back to the colours of " .. current.name, "Click again to replace your colours") then
                reset_colours()
                state.msg = save_colours() and ("Back to the colours of " .. current.name .. ".") or "Could not write the theme file."
            end
        end
        r.ImGui_EndChild(ctx)
    end
    if current then
        draw_moods(current)
        draw_accents(current)
        if current.name == "Dark" then draw_shade() end
        draw_display()
        draw_auto()
    end
    local wants_dark = current and current.name == "Dark"
    if IS_WINDOWS and current and dark.on ~= wants_dark then
        r.ImGui_Dummy(ctx, 0, 2)
        if begin_card("Dark mode", "lkd") then
            hint_text(wants_dark and "Dark mode is off, so lists and scrollbars are light beside this dark look."
                or "Dark mode is on, so menus, lists and scrollbars stay dark beside this light look. Whether you like that is up to you.")
            if r.ImGui_Button(ctx, (wants_dark and "Turn dark mode on" or "Turn dark mode off") .. " (restart needed)") then
                dark.on = wants_dark
                apply_dark()
            end
            r.ImGui_EndChild(ctx)
        end
    end
end

-- ---------------------------------------------------------------- guide

local GUIDE = {
    { "Look", {
        "A small round arrow after a setting's name means that choosing it reloads the theme, so the screen may blink. Point at the arrow to read it. If items don't change straight away after choosing Classic or Reversed, restart REAPER.",
        "The Look page chooses Dark or Light. A look changes colours and images only: your layout settings go along. Colours you changed are kept per look, and a preset remembers which look it was saved with. When a look uses your own colours, this page says so and can take it back to the look's own.",
        "A transport plate, on the Transport page, puts brushed metal, with screws and a maker's plate, behind the whole transport, which gets a little taller. It goes with any look and display skin.",
        "A display skin gives the transport's glass and what's on it one colour of its own, in every look. The accent colour doesn't reach it.",
        "The same page chooses an accent colour: Blue, Orange, Violet, Red or Graphite (a calm grey), for selections, FX buttons, highlights, meters and the theme's icons. Mute, solo, record and play keep their own colours, and so do the TK_ icons on your own toolbars.",
        "Day and night, on the Look page, switches to Light and Dark at the times you set. It waits while REAPER plays, records or is paused, and while this window is open, and a look you choose yourself stays until the next switch. It needs the metronome and grid watcher, which \"Metronome and grid at startup\" starts with REAPER.",
        "In Options > Themes the looks are listed as TK Theme Dark and TK Theme Light. Choosing one there works too, but your settings only go along when you change the look on this page.",
    } },
    { "Transport", {
        "The gear at the end of the transport opens this window.",
        "The metronome button lights up while the metronome is on. Its small arrow opens the metronome settings. To have the light right before your first click, turn on \"Metronome and grid at startup\" on the Transport page.",
        "The grid box, on the Transport page, shows the grid on the display beside the time signature. Click it for a menu to choose the grid: the division, triplet, dotted, swing, frame, measure, or an adaptive grid. Adaptive (Narrow, Medium or Wide) picks the division for the zoom as you zoom, keeping triplet, dotted or swing, and shows an A before the grid. Choosing a division yourself turns it off. The magnet turns snap on and off and lights while it's on; the dots open REAPER's snap/grid settings. Use one adaptive grid at a time: another script that sets the grid as you zoom, or REAPER's own adaptive grid, turns this one off.",
        "Extra buttons sit in a window to the left or right of the transport. Choose them on the Transport page, where a button can also run an action of your own. When the transport gets too narrow, these windows move to a second row.",
    } },
    { "Track panel", {
        "Style: Standard has glass windows. Basic leaves them out: the name and controls stand on the panel, and the name stays readable on any track colour. Material puts the track panel and the master on a brushed plate (Silver or Black): tall tracks get a low glass band (name, level, input and the small buttons) with R, M, S and the knobs as hardware under it, middle tracks a one-row band, low tracks one row. FX parameter knobs turn hardware too, and the section margins are 10; the envelope lanes keep yours. The plates are made for the Dark look.",
        "Meter in the plate lays the meter in the plate, between R, M, S and the knobs, on low tracks between the name and R. Narrow panels keep it standing on the right. Its type is Lying, under Meters on the General page.",
        "The buttons on the lowest row are, from the left: automation mode, phase, fixed item lanes, FX and IO columns, meter, freeze and unfreeze, and the layout button when it's on. Buttons that don't fit are left out, so make the panel wider or the track taller to see them.",
        "The layout button shows the track's layout and takes it to the next one: A, B, C and round to A. Click it on one of several selected tracks and they all go along. The mixer has a layout key of its own, on the Mixer page, for the mixer layout.",
        "The columns and meter buttons work on all tracks with the same layout as the one you click; the master's buttons only on the master. The columns button hides the FX and IO columns, and brings back the ones that were shown. It also turns on REAPER's options to show FX and sends in the track panel. The FX and IO buttons are the headers of those columns; without a column, they move to the first row. Set the columns' width on the Track panel page.",
        "A track with fixed item lanes has a blue strip at the left of its window, whether the lanes are open or closed.",
        "To add a knob for an FX parameter: in the FX window, choose Param > FX parameter list > Show in track controls. It appears under the controls, so the track has to be tall enough. FX parameters and Embedded FX on the Track panel page hide them per layout, without taking them out of the project.",
        "An FX with an embedded UI shows under the controls too, once it's turned on: right-click the FX in the FX chain. Make the track taller to see it.",
    } },
    { "Master", {
        "The master has the same windows as a track. Show it with View > Master track. Its hardware outputs are in the IO column; click the IO button to add one. It can do without volume, pan or columns, have a wider meter, or be nothing but one big meter: see the Master settings on the Track panel page.",
    } },
    { "Layouts", {
        "Each track can use layout A, B or C. In the track panel they look the same until you change one on the Track panel page, for example to give your busses only a name, FX, mute and solo, with a wide meter on the left. Settings that don't count at the moment show grey. Name only turns a track into a divider: its name, large and centred, growing with the track's height.",
        "Under Set track height you set a fixed height and lock it, or make dividers in one go. The action TK_Theme_Make_Divider does the same from a shortcut. The height stays when you select other tracks and doesn't follow the selection (a theme can't resize tracks by itself); moving the slider changes nothing until you click a button. Layout A includes tracks on the default layout, and REAPER's zoom actions leave a locked height alone.",
        "Volume and pan on the first row puts them beside the name, so they also show on the lowest track height. Name width then sets the room for the name. Volume and pan as chooses Sliders, Knobs or Auto, which shows knobs when a slider wouldn't have the room. Knobs sit side by side, and on the first row the name takes the room they leave.",
        "The first row runs from the name to mute and solo, then record arm and monitor next to the meter. Record arm and monitor on the left moves those to the start of the row, so the knobs, mute and solo end up next to the meter; Mute and solo on the left moves those to the start instead.",
    } },
    { "Mixer", {
        "Style on the Mixer page works as in the track panel, on its own. On a plate the fader, pan and width are slots with hardware handles; the handles you chose come back with Standard or Basic. Wood adds an armrest with the numbers on it, and folders hang on rack rails under their strips.",
        "Basic's keys and lists are images the track panel and the mixer share: a Basic mixer beside a track panel without a plate gives that track panel Basic's keys too.",
        "Choose the fader handle on the Mixer page, for all layouts. In the track's layout menu, each layout has a twin with the word Dot; this switch moves tracks between them. A project opened later follows the next time this window opens.",
        "The handles of the pan and width sliders have their own choice there, and the Track panel page has one for its volume, pan and width sliders. Layouts A, B and C each have their own settings. The width decides the form: a narrow strip under 52, an intermediate one under 88, a normal one from 88. What doesn't count for the current form shows grey. A sidebar puts the FX and send lists beside the strip.",
        "Turn on the FX and send lists by right-clicking the mixer. An FX's embedded UI shows in that list when the strip is tall enough.",
    } },
    { "Colours", {
        "The Look page also has colour settings: Standard, Warm, Cool and Neutral. They change the arrange, grid, mixer background and lists. The Inverted switch beside them gives a look the other look's arrange, in whichever of the four you pick. Panels and glass windows are images, so they stay as they are. A colour setting goes along when you change the look, in that look's version of it.",
        "A colour that differs from the theme's own gets a Reset button, and Reset all colours does them all. A change is temporary until you click Save colours; Undo changes goes back to the last saved colours.",
        "An update of the theme replaces its colour file. Colours you saved come back by themselves the next time you open this window.",
        "Colour processing changes the whole theme at once, images included: gamma, highlights, midtones, shadows, saturation and tint.",
        "The General page chooses the meter type and the size of its segments, for the track panel and the mixer. The colour steps assume REAPER's standard meter range of -60 to +6 dB: with another range they fall elsewhere.",
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

local DRAWERS = { look = draw_look, colours = draw_colours, darkmode = draw_darkmode, reset = draw_reset, presets = draw_presets, processing = draw_processing, guide = draw_guide }
DRAWERS.materials = function() patina.forge.draw() end
patina.forge.bind({ r = r, ctx = ctx, UI = UI, rgba = rgba, mix = mix, params = function() return P end,
    set_param = set_param, set_style = function(...) return patina.set_style(...) end,
    together = function(fn) return parts.together(fn) end, Zip = Zip,
    parts = parts, look = look, state = state, patina = patina, begin_card = begin_card,
    row_label = row_label, hint_text = hint_text, LABEL_W = LABEL_W,
    -- the On the plates card (wear, coffee ring, graffiti): drawn as on the other pages
    plate_items = state.PLATE_ITEMS, draw_setting = function(item, id) return draw_setting(item, id) end })

-- the explanations under the settings: on, or off (shown when pointed at); the title row's i key
state.hints_off = r.GetExtState("TK Theme", "settings_hints_off") == "1"

-- where the mixer shows the master (REAPER's own options, through its actions)
state.mastermix = dofile(here .. "TK_Theme_MasterMix.lua")
state.mastermix.bind({ r = r, ctx = ctx, UI = UI, rgba = rgba, mix = mix, state = state, row_label = row_label, LABEL_W = LABEL_W })

-- the drawn pictures on choice buttons, in a file of its own too
state.pics = dofile(here .. "TK_Theme_Pics.lua")
state.pics.bind({ r = r, ctx = ctx, UI = UI, rgba = rgba, mix = mix })

-- searching every setting (Ctrl+F), in a file of its own (this one is near Lua's 200 locals)
state.search = dofile(here .. "TK_Theme_Search.lua")
state.search.bind({ r = r, ctx = ctx, PAGES = PAGES, draw_setting = draw_setting, begin_card = begin_card,
    hint_text = hint_text, state = state, UI = UI, rgba = rgba, mix = mix,
    mono = r.ImGui_CreateFont(IS_WINDOWS and "Consolas" or "monospace") })
r.ImGui_Attach(ctx, state.search.E.mono)

-- the page list in groups; a page not named here goes in the last
state.NAV_GROUPS = {
    { "LOOK AND COLOUR", { "Look", "Colours", "Colour processing", "Dark mode", "Materials" } },
    { "PANELS", { "General", "Track panel", "Mixer", "Transport" } },
    { "KEEP AND LEARN", { "Presets", "Reset", "Guide" } },
}
function state.nav_order()
    local out, seen = {}, {}
    for gi, g in ipairs(state.NAV_GROUPS) do
        out[#out + 1] = { head = g[1] }
        for _, title in ipairs(g[2]) do
            for i, page in ipairs(PAGES) do
                if page.title == title and not seen[i] then out[#out + 1] = i; seen[i] = true end
            end
        end
        if gi == #state.NAV_GROUPS then
            for i in ipairs(PAGES) do
                if not seen[i] then out[#out + 1] = i; seen[i] = true end
            end
        end
    end
    return out
end

local function draw_nav()
    if r.ImGui_BeginChild(ctx, "##nav", 170, 0, r.ImGui_ChildFlags_AlwaysUseWindowPadding and r.ImGui_ChildFlags_AlwaysUseWindowPadding() or 0) then
        for _, i in ipairs(state.nav_order()) do
          if type(i) == "table" then
            r.ImGui_Dummy(ctx, 0, i.head == state.NAV_GROUPS[1][1] and 0 or 6)
            r.ImGui_PushFont(ctx, font, 11)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), rgba(UI.dim))
            r.ImGui_Text(ctx, i.head)
            r.ImGui_PopStyleColor(ctx)
            r.ImGui_PopFont(ctx)
          else
            local page = PAGES[i]
            local selected = state.page == i
            r.ImGui_PushID(ctx, i)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), rgba(selected and UI.ink or UI.text))
            if r.ImGui_Selectable(ctx, page.title, selected, 0, 0, 22) and (not selected or state.search.active()) then
                state.page = i
                state.confirm, state.msg = nil, nil
                state.search.clear()
            end
            r.ImGui_PopStyleColor(ctx)
            if selected then
                local x, y = r.ImGui_GetItemRectMin(ctx)
                local _, y2 = r.ImGui_GetItemRectMax(ctx)
                r.ImGui_DrawList_AddRectFilled(r.ImGui_GetWindowDrawList(ctx), x - 2, y, x + 1, y2, rgba(UI.accent), 1)
            end
            r.ImGui_PopID(ctx)
          end
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
    local searching = state.search.active()
    r.ImGui_PushFont(ctx, font, 20)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), rgba(UI.ink))
    r.ImGui_Text(ctx, searching and "Search" or page.title)
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
    if state.checking then
        hint_text("Checking the theme...")
        r.ImGui_PopStyleColor(ctx)
        r.ImGui_EndChild(ctx)
        return
    end
    if searching then
        state.search.draw()
    else
        draw_welcome()
        if page.draw then
            DRAWERS[page.draw]()
        else
            draw_param_page(page)
        end
    end
    r.ImGui_PopStyleColor(ctx)
    r.ImGui_EndChild(ctx)
end

-- after an update, putting your choices back can take a moment: the window shows first
local function startup_checks()
    state.log("checks start")
    -- the zip chosen itself: its colours are the theme's own, not the ones kept here
    local loose, from_zip = parts.loaded_theme()
    if from_zip and look.current() then
        state.log("the zip itself was loaded: its loose colour file opened")
        r.OpenColorThemeFile(loose)
        load_params()
    end
    parts.restore()
    state.log("parts.restore done")
    -- your own name on the plate and your wear, when the theme lost them (an update, the other look)
    plate_name.ensure()
    state.log("plate_name.ensure done")
    patina.ensure()
    state.log("patina.ensure done (wear, graffiti)")
    patina.forge.ensure()
    state.log("forge.ensure done")
    -- a colour setting chosen before its colours were worked out anew: as it is now
    -- (only when the colours are still exactly what it gave: refresh_mood checks)
    if look.current() then look.refresh_mood(look.current()) end
    state.log("refresh_mood done")
    -- whether the lying meter is the lamps (see draw_meter)
    if P.tkPlLamps then
        local lamps = (parts.chosen.meter_lying or parts.default.meter_lying) == "lamps" and 1 or 0
        if math.floor(P.tkPlLamps.value) ~= lamps then set_param("tkPlLamps", lamps, true) end
    end
    -- whether the record arm is the lamp (its round shadow), as with the lamps above
    for rp, lp in pairs({ tcp_recarm = "tkTcpRecLamp", mcp_recarm = "tkMcpRecLamp" }) do
        local want = (parts.chosen[rp] or parts.default[rp]) == "lamp" and 1 or 0
        if P[lp] and math.floor(P[lp].value) ~= want then set_param(lp, want, true) end
    end
    -- Basic's buttons and lists follow its switches, also when those were set before the
    -- images came (or by hand in REAPER's own theme adjuster)
    if look.current() and P.tkTcpBasic then
        local want = parts.basic_want()
        local list = {}
        if (parts.chosen.basic or parts.default.basic) ~= want then list[#list + 1] = { "basic", want } end
        -- the mixer's R / M / S follow the mixer's own choice
        local hw = parts.chosen.mcp_hw or parts.default.mcp_hw
        if global_value("tkMcpBasic") and not global_value("tkMcpPlate") and hw ~= "basic" then list[#list + 1] = { "mcp_hw", "basic" }
        elseif not global_value("tkMcpBasic") and hw == "basic" then list[#list + 1] = { "mcp_hw", "standard" } end
        -- and the track panel's knobs and R / M / S its own
        local thw = parts.chosen.tcp_hw or parts.default.tcp_hw
        if global_value("tkTcpBasic") and not global_value("tkTcpPlate") and thw ~= "basic" then list[#list + 1] = { "tcp_hw", "basic" }
        elseif not global_value("tkTcpBasic") and thw == "basic" then list[#list + 1] = { "tcp_hw", "standard" } end
        if #list > 0 then parts.choose_many(list, true) end
    end
    state.log("switches done")
    if look.current() and look.own_colours() then r.ThemeLayout_RefreshAll() state.log("own colours: layout refreshed") end
    restore_my_colours()
    if handle_is_dot() then sync_track_handles(true) end
    refresh_palette()
    state.log("checks end")
    if P.tkGridBox and P.tkGridBox.value ~= 0 or Auto.on() then start_watcher() end
end

-- the first frames: only this, so the window is there at once; the checks and the first
-- full page (which can take a while: the packs are read) come after it, with this still
-- on screen meanwhile
local function draw_loading()
    local w, h = r.ImGui_GetContentRegionAvail(ctx)
    local title, sub = "TK Theme", "Loading settings..."
    r.ImGui_PushFont(ctx, font, 24)
    local tw, th = r.ImGui_CalcTextSize(ctx, title)
    r.ImGui_SetCursorPos(ctx, (w - tw) / 2, h / 2 - th)
    r.ImGui_Text(ctx, title)
    r.ImGui_PopFont(ctx)
    local sw = r.ImGui_CalcTextSize(ctx, sub)
    r.ImGui_SetCursorPosX(ctx, (w - sw) / 2)
    r.ImGui_TextDisabled(ctx, sub)
end

-- while a change waits to rebuild the theme: a small window of its own, always on top and
-- centred over the settings window (busy.at: its centre, kept while that was drawn), so it
-- shows over the pages and over any other window. Returns whether it was drawn
local function draw_rebuilding()
    local cx, cy = table.unpack(busy.at or { 400, 300 })
    r.ImGui_SetNextWindowPos(ctx, cx, cy, r.ImGui_Cond_Always(), 0.5, 0.5)
    local flags = r.ImGui_WindowFlags_NoTitleBar() | r.ImGui_WindowFlags_NoResize() | r.ImGui_WindowFlags_NoMove()
        | r.ImGui_WindowFlags_NoCollapse() | r.ImGui_WindowFlags_AlwaysAutoResize() | r.ImGui_WindowFlags_NoSavedSettings()
        | r.ImGui_WindowFlags_NoScrollbar() | (r.ImGui_WindowFlags_NoDocking and r.ImGui_WindowFlags_NoDocking() or 0)
        | (r.ImGui_WindowFlags_TopMost and r.ImGui_WindowFlags_TopMost() or 0)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_WindowBg(), rgba(UI.raised))
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Border(), rgba(UI.accent))
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowBorderSize(), 1.5)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowRounding(), 8)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), 26, 16)
    local visible = r.ImGui_Begin(ctx, "TK Theme rebuilding##busy", false, flags)
    if visible then
        r.ImGui_PushFont(ctx, font, 20)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), rgba(UI.ink))
        r.ImGui_Text(ctx, "Rebuilding theme...")
        r.ImGui_PopStyleColor(ctx)
        r.ImGui_PopFont(ctx)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), rgba(UI.soft))
        r.ImGui_Text(ctx, "One moment: the theme is written and reloaded.")
        r.ImGui_PopStyleColor(ctx)
        r.ImGui_End(ctx)
    end
    r.ImGui_PopStyleVar(ctx, 3)
    r.ImGui_PopStyleColor(ctx, 2)
    return visible
end

-- the same notice as a bar at the top of the settings window (see state.busy_inside)
state.draw_busy_bar = function()
    local dl = r.ImGui_GetWindowDrawList(ctx)
    local x, y = r.ImGui_GetCursorScreenPos(ctx)
    local w = r.ImGui_GetContentRegionAvail(ctx)
    local text = "Rebuilding theme...   One moment: the theme is written and reloaded."
    local tw = r.ImGui_CalcTextSize(ctx, text)
    r.ImGui_DrawList_AddRectFilled(dl, x, y, x + w, y + 30, rgba(UI.accent), 6)
    r.ImGui_DrawList_AddText(dl, x + (w - tw) / 2, y + 7, 0xFFFFFFFF, text)
    r.ImGui_Dummy(ctx, w, 34)
end

local frame = 0
local function loop()
    frame = frame + 1
    -- tells the day and night switch that this window is open, so it waits
    if frame % 20 == 1 then r.SetExtState(SCRIPT, "open", tostring(r.time_precise()), false) end
    -- (a new window is often not drawn on its first frame: the checks wait until the
    -- loading screen has been on screen twice, or half a second in a hidden dock tab)
    local loading = state.checking
    if state.checking and ((state.loading_shown or 0) >= 2 or frame > 30) then
        state.checking = false
        loading = false
        startup_checks()
    end
    -- a change that waited until "Rebuilding theme..." was on screen (twice, or half a second
    -- in a hidden dock tab): now it runs, with that still showing
    busy.frames = busy.frames + 1
    if #busy.queue > 0 and (busy.shown >= 2 or busy.frames > 30) then
        local queue = busy.queue
        busy.queue = {}
        busy.running = true
        state.log(#queue .. " waiting job(s) run")
        for _, job in ipairs(queue) do
            local ok, err = pcall(job)
            if not ok then
                state.msg = "Something went wrong while rebuilding the theme: " .. tostring(err)
                r.ShowConsoleMsg("TK Theme: " .. tostring(err) .. "\n")
            end
        end
        busy.running = false
    end
    poll_action_picker()
    -- dark glass in Light goes with a plate: with none left, the glass goes back to light (once)
    if frame % 30 == 0 then
        local cur = look.current()
        local plated = global_value("tkTcpPlate") or global_value("tkMcpPlate")
        if plated then state.glass_back_tried = nil end
        if cur and cur.name == "Light" and not plated and parts.chosen.light_glass == "dark" and not state.glass_back_tried then
            state.glass_back_tried = true
            parts.choose("light_glass", "light")
        end
    end
    if frame % 60 == 0 and not r.ImGui_IsAnyItemActive(ctx) then
        load_params()     -- the panel's own buttons change these too
        refresh_palette()
    end
    local colours, vars = push_theme()
    r.ImGui_PushFont(ctx, font, 15)
    r.ImGui_SetNextWindowSize(ctx, 780, 640, r.ImGui_Cond_FirstUseEver())
    r.ImGui_SetNextWindowSizeConstraints(ctx, 660, 480, 100000, 100000)
    -- the title row is the window's own (Search.header); the dock key docks and floats it
    if state.dock_toggle then
        r.ImGui_SetNextWindowDockID(ctx, state.docked and 0 or -1)
        state.dock_toggle = nil
    end
    local visible, open = r.ImGui_Begin(ctx, SCRIPT, true,
        r.ImGui_WindowFlags_NoCollapse() | (state.docked and 0 or r.ImGui_WindowFlags_NoTitleBar()))
    if visible then
        state.docked = r.ImGui_IsWindowDocked(ctx)
        if loading then
            draw_loading()
            state.loading_shown = (state.loading_shown or 0) + 1
        else
            busy.ui = true
            if #busy.queue > 0 and state.busy_inside then
                state.draw_busy_bar()
                busy.shown = busy.shown + 1
            end
            state.search.header()
            draw_nav()
            r.ImGui_SameLine(ctx)
            draw_content()
            busy.ui = false
            local wx, wy = r.ImGui_GetWindowPos(ctx)
            local ww, wh = r.ImGui_GetWindowSize(ctx)
            busy.at = { wx + ww / 2, wy + wh / 2 }
        end
        r.ImGui_End(ctx)
    end
    if #busy.queue > 0 and not state.busy_inside and draw_rebuilding() then busy.shown = busy.shown + 1 end
    r.ImGui_PopFont(ctx)
    r.ImGui_PopStyleVar(ctx, vars)
    r.ImGui_PopStyleColor(ctx, colours)
    if state.close then open = false end
    if open then
        r.defer(loop)
    else
        r.DeleteExtState(SCRIPT, "open", false)
    end
end

-- what rebuilds or reloads the theme, started in the window: "Rebuilding theme..." first
-- (deferred, at the top). Everything else goes through these, so a part, a look, a preset,
-- a code, a reset or undo and your plate's name all show it
parts.choose_many = deferred(parts.choose_many)
parts.together = deferred(parts.together)
look.switch = deferred(look.switch)
plate_name.ensure = deferred(plate_name.ensure)
patina.ensure = deferred(patina.ensure)
patina.forge.ensure = deferred(patina.forge.ensure)
patina.forge.apply = deferred(patina.forge.apply)
load_preset = deferred(load_preset)
apply_code = deferred(apply_code)
apply_signature = deferred(apply_signature)
factory_reset = deferred(factory_reset)
undo_reset = deferred(undo_reset)

-- the theme's buttons call these scripts by action ID, which only exists once
-- they are in the action list; once per install location is enough
local function register_helpers()
    if r.GetExtState(SCRIPT, "registered6") == here then return end
    local files = { "TK_Theme_Settings.lua", "TK_Theme_Toggle_TCP_Lists.lua", "TK_Theme_Toggle_TCP_Meter.lua", "TK_Theme_Cycle_Layout.lua",
        "TK_Theme_Metronome.lua", "TK_Theme_Metronome_Watch.lua", "TK_Theme_Toggle_Menu_Bar.lua", "TK_Theme_Make_Divider.lua",
        "TK_Theme_Grid_Menu.lua", "TK_Theme_Snap.lua" }
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
    if ok then r.SetExtState(SCRIPT, "registered6", here, true) end
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

if AUTO_LOOK then
    -- only between the schedule's checks: the watcher made sure nothing plays and this window is shut
    local entry
    for _, e in ipairs(look.list) do
        if e.theme == AUTO_LOOK then entry = e end
    end
    if entry and look.current() and look.current() ~= entry and r.GetPlayState() == 0 then
        parts.load()
        if look.switch(entry, true) and r.GetExtState(Auto.SECTION, "notify") ~= "0" then
            r.ShowConsoleMsg("TK Theme: " .. entry.name .. " look, by the time of day.\n")
        end
    end
    return
end

state.checking = true
state.restart = r.GetExtState(SCRIPT, "restart") == "1"
state.welcome = IS_WINDOWS and not dark.saved and r.GetExtState(SCRIPT, "welcomed") == ""
r.defer(loop)
