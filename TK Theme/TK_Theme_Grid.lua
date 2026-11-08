-- @noindex
-- The project grid as the transport's grid box shows and sets it, shared by the
-- watcher, the grid menu and the snap button. A theme can't read the grid itself,
-- so these pass it on as the theme parameters tkGridV, tkGridA and tkSnapOn.
-- tk_theme_gen.py reads VALUES too, for one text element per entry, numbered from
-- 1 (0 is "Grid", for a grid that isn't in the list): keep one entry per line.
local r = reaper
local Grid = {}

Grid.SNAP, Grid.ADAPTIVE, Grid.FRAME, Grid.MEASURE, Grid.SETTINGS = 1157, 43813, 41885, 40725, 40071

Grid.VALUES = {
    { "4", 4, base = 0.25, kind = "straight" },
    { "2", 2, base = 0.5, kind = "straight" },
    { "1", 1, base = 1, kind = "straight" },
    { "1/2", 1 / 2, base = 2, kind = "straight" },
    { "1/4", 1 / 4, base = 4, kind = "straight" },
    { "1/8", 1 / 8, base = 8, kind = "straight" },
    { "1/16", 1 / 16, base = 16, kind = "straight" },
    { "1/32", 1 / 32, base = 32, kind = "straight" },
    { "1/64", 1 / 64, base = 64, kind = "straight" },
    { "1/128", 1 / 128, base = 128, kind = "straight" },
    { "1T", 2 / 3, base = 1, kind = "triplet" },
    { "1/2T", 1 / 3, base = 2, kind = "triplet" },
    { "1/4T", 1 / 6, base = 4, kind = "triplet" },
    { "1/8T", 1 / 12, base = 8, kind = "triplet" },
    { "1/16T", 1 / 24, base = 16, kind = "triplet" },
    { "1/32T", 1 / 48, base = 32, kind = "triplet" },
    { "1/64T", 1 / 96, base = 64, kind = "triplet" },
    { "1/128T", 1 / 192, base = 128, kind = "triplet" },
    { "1D", 3 / 2, base = 1, kind = "dotted" },
    { "1/2D", 3 / 4, base = 2, kind = "dotted" },
    { "1/4D", 3 / 8, base = 4, kind = "dotted" },
    { "1/8D", 3 / 16, base = 8, kind = "dotted" },
    { "1/16D", 3 / 32, base = 16, kind = "dotted" },
    { "1/32D", 3 / 64, base = 32, kind = "dotted" },
    { "1/64D", 3 / 128, base = 64, kind = "dotted" },
    { "1/128D", 3 / 256, base = 128, kind = "dotted" },
    { "1/4Q", 1 / 5, base = 4, kind = "quintuplet" },
    { "1/8Q", 1 / 10, base = 8, kind = "quintuplet" },
    { "1/16Q", 1 / 20, base = 16, kind = "quintuplet" },
    { "1/32Q", 1 / 40, base = 32, kind = "quintuplet" },
    { "1 Sw", 1, base = 1, kind = "swing" },
    { "1/2 Sw", 1 / 2, base = 2, kind = "swing" },
    { "1/4 Sw", 1 / 4, base = 4, kind = "swing" },
    { "1/8 Sw", 1 / 8, base = 8, kind = "swing" },
    { "1/16 Sw", 1 / 16, base = 16, kind = "swing" },
    { "1/32 Sw", 1 / 32, base = 32, kind = "swing" },
    { "1/64 Sw", 1 / 64, base = 64, kind = "swing" },
    { "1/128 Sw", 1 / 128, base = 128, kind = "swing" },
    { "Frame", special = "frame" },
    { "Measure", special = "measure" },
    { "Adaptive", special = "adaptive" },
}

Grid.FACTOR = { straight = 1, swing = 1, triplet = 2 / 3, dotted = 3 / 2, quintuplet = 4 / 5 }
Grid.BASES = { 1, 2, 4, 8, 16, 32, 64, 128 }
-- the theme's own adaptive grid: the finest division whose lines are at least this
-- many pixels apart, set as a plain grid, so the ruler keeps its own spacing
Grid.MODES = { { "Narrow", 10 }, { "Medium", 20 }, { "Wide", 40 } }

local SECTION = "TK_Theme_Grid"

local function on(cmd) return r.GetToggleCommandState(cmd) == 1 end

local function same(a, b) return math.abs(a - b) <= 1e-9 * math.max(1, math.abs(b)) end

local function entry_of(div, swing)
    for i, v in ipairs(Grid.VALUES) do
        if not v.special and (v.kind == "swing") == (swing == 1) and div and same(div, v[2]) then return i, v end
    end
    return 0, nil
end

-- the mode that's on: { name, pixels }, or nil; it stays on across projects and restarts
function Grid.mode()
    local name = r.GetExtState(SECTION, "adaptive")
    for _, m in ipairs(Grid.MODES) do
        if m[1] == name then return m end
    end
    return nil
end

-- which entry of VALUES the project's grid is (0 when none), whether snap is on, and
-- whether the theme's adaptive grid is on
function Grid.read()
    local _, div, swing = r.GetSetProjectGrid(0, false)
    local special = (on(Grid.ADAPTIVE) and "adaptive") or (on(Grid.FRAME) and "frame")
        or ((swing == 3 or on(Grid.MEASURE)) and "measure") or nil
    if special then
        for i, v in ipairs(Grid.VALUES) do
            if v.special == special then return i, on(Grid.SNAP), false end
        end
    end
    return (entry_of(div, swing)), on(Grid.SNAP), Grid.mode() ~= nil
end

-- parameter numbers change with the theme, so they're looked up again when they don't match
local found = {}
local function param(name)
    local i = found[name]
    if i and r.ThemeLayout_GetParameter(i) == name then return i end
    i = 0
    while true do
        local n = r.ThemeLayout_GetParameter(i)
        if not n then
            found[name] = nil
            return nil
        end
        if n == name then
            found[name] = i
            return i
        end
        i = i + 1
    end
end

local shown = {}
local function set(name, value)
    local i = param(name)
    if not i then return false end
    local _, _, current = r.ThemeLayout_GetParameter(i)
    if shown[name] == value and current == value then return false end
    shown[name] = value
    r.ThemeLayout_SetParameter(i, value, false)
    return true
end

-- passes the grid on to the theme; true when that changed anything
function Grid.show(index, snap, adaptive)
    local a = set("tkGridV", index)
    local b = set("tkSnapOn", snap and 1 or 0)
    local c = set("tkGridA", adaptive and 1 or 0)
    if a or b or c then r.ThemeLayout_RefreshAll() end
    return a or b or c
end

function Grid.forget() found, shown = {}, {} end

-- the watcher says it's running; it doesn't survive a restart, so neither does this
local WATCH = "TK_Theme_Watch"
function Grid.beat() r.SetExtState(WATCH, "beat", tostring(r.time_precise()), false) end

function Grid.watching()
    local beat = tonumber(r.GetExtState(WATCH, "beat"))
    return beat ~= nil and r.time_precise() - beat < 3
end

-- starts the watcher when it isn't running, so the grid box keeps up with other changes
function Grid.start_watcher(folder)
    if Grid.watching() then return end
    local path = folder .. "TK_Theme_Metronome_Watch.lua"
    local f = io.open(path, "rb")
    if not f then return end
    f:close()
    local cmd = r.AddRemoveReaScript(true, 0, path, true)
    if cmd and cmd > 0 then r.Main_OnCommand(cmd, 0) end
end

-- ---------------------------------------------------------------- adaptive grid

function Grid.set_mode(name)
    if name then
        r.SetExtState(SECTION, "adaptive", name, true)
    else
        r.DeleteExtState(SECTION, "adaptive", true)
        r.DeleteExtState(SECTION, "last", false)
    end
end

-- the division for this zoom: the finest one of this kind whose lines are at least
-- px apart in the middle of the view (tempo can change along the way)
function Grid.target(px, kind)
    local zoom = r.GetHZoomLevel()
    local s, e = r.GetSet_ArrangeView2(0, false, 0, 0)
    local t = (s + e) / 2
    local qn = r.TimeMap2_timeToQN(0, t)
    local per_whole = (r.TimeMap2_QNToTime(0, qn + 1) - t) * 4 * zoom
    local f = Grid.FACTOR[kind] or 1
    local d, top = 1 / 128, kind == "straight" and 4 or 1
    while d < top and d * f * per_whole < px do d = d * 2 end
    return d * f
end

local last_project
-- keeps the grid in step with the zoom; now: right away, as asked from the menu, without
-- taking a change of grid for one made elsewhere
function Grid.adapt(now)
    local mode = Grid.mode()
    if not mode then return false end
    local project = r.EnumProjects(-1)
    local last = tonumber(r.GetExtState(SECTION, "last"))
    if project ~= last_project then
        last_project, last = project, nil
    end
    local _, div, swing, amount = r.GetSetProjectGrid(0, false)
    -- frame, measure, REAPER's own adaptive grid or a grid chosen elsewhere: that wins
    if on(Grid.ADAPTIVE) or on(Grid.FRAME) or on(Grid.MEASURE) or swing == 3
        or (not now and last and div and not same(div, last)) then
        Grid.set_mode(nil)
        return false
    end
    local _, v = entry_of(div, swing)
    local target = Grid.target(mode[2], v and v.kind or "straight")
    if not (div and same(div, target)) then
        r.GetSetProjectGrid(0, true, target, swing == 1 and 1 or 0, amount or 0)
    end
    r.SetExtState(SECTION, "last", tostring(target), false)
    return true
end

-- ---------------------------------------------------------------- the menu

local function leave_specials()
    if on(Grid.ADAPTIVE) then r.Main_OnCommand(Grid.ADAPTIVE, 0) end
    if on(Grid.FRAME) then r.Main_OnCommand(Grid.FRAME, 0) end
end

-- a division in one of the kinds, out of frame, measure and REAPER's adaptive grid
function Grid.set(base, kind)
    leave_specials()
    local _, _, _, amount = r.GetSetProjectGrid(0, false)
    r.GetSetProjectGrid(0, true, (1 / base) * Grid.FACTOR[kind], kind == "swing" and 1 or 0, amount or 0)
    if on(Grid.MEASURE) then r.Main_OnCommand(Grid.MEASURE, 0) end
end

-- the theme's adaptive grid in a mode, in the kind there is now (straight from frame,
-- measure or a grid not in the list); nil turns it off
function Grid.choose_mode(name)
    if not name then
        Grid.set_mode(nil)
        return
    end
    local _, div, swing = r.GetSetProjectGrid(0, false)
    local _, v = entry_of(div, swing)
    local special = on(Grid.ADAPTIVE) or on(Grid.FRAME) or on(Grid.MEASURE) or swing == 3
    if special or not v then Grid.set(4, "straight") end
    Grid.set_mode(name)
    Grid.adapt(true)
end

-- the menu as gfx.showmenu takes it, and what each of its items does, by number
function Grid.menu()
    local index = Grid.read()
    local now = Grid.VALUES[index]
    local special = now and now.special
    local mode = Grid.mode()
    local base = now and not special and now.base or 4
    local kind = now and not special and now.kind or "straight"
    local items, run = {}, {}
    local function add(label, fn, checked, prefix)
        items[#items + 1] = (prefix or "") .. (checked and "!" or "") .. label
        if fn then run[#run + 1] = fn end
    end
    for _, b in ipairs(Grid.BASES) do
        add("1/" .. b, function()
            Grid.set_mode(nil)
            Grid.set(b, kind)
        end, index > 0 and not special and not mode and now.base == b)
    end
    add("")
    -- with the adaptive grid on, a kind keeps it on: the division follows the zoom in that kind
    for _, k in ipairs({ { "Straight", "straight" }, { "Triplet", "triplet" }, { "Dotted", "dotted" }, { "Swing", "swing" } }) do
        add(k[1], function()
            Grid.set(base, k[2])
            if mode then Grid.adapt(true) end
        end, index > 0 and not special and kind == k[2])
    end
    add("")
    add("Frame", function()
        Grid.set_mode(nil)
        if on(Grid.ADAPTIVE) then r.Main_OnCommand(Grid.ADAPTIVE, 0) end
        if not on(Grid.FRAME) then r.Main_OnCommand(Grid.FRAME, 0) end
    end, special == "frame")
    add("Measure", function()
        Grid.set_mode(nil)
        leave_specials()
        if not on(Grid.MEASURE) then r.Main_OnCommand(Grid.MEASURE, 0) end
    end, special == "measure")
    items[#items + 1] = ">Adaptive"
    add("Off", function()
        Grid.set_mode(nil)
        if on(Grid.ADAPTIVE) then r.Main_OnCommand(Grid.ADAPTIVE, 0) end
    end, not mode and special ~= "adaptive")
    for i, m in ipairs(Grid.MODES) do
        add(m[1], function() Grid.choose_mode(m[1]) end, mode == m, i == #Grid.MODES and "<" or nil)
    end
    add("")
    add("Snap", function() r.Main_OnCommand(Grid.SNAP, 0) end, on(Grid.SNAP))
    add("")
    add("Snap/Grid settings...", function() r.Main_OnCommand(Grid.SETTINGS, 0) end)
    -- an empty label is a separator: gfx.showmenu doesn't count those
    return table.concat(items, "|"), run
end

return Grid
