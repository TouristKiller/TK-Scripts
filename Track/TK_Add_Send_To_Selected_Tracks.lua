-- @description Add Send to Selected Tracks (popup menu)
-- @author TouristKiller
-- @version 1.0
-- @changelog:
--   + Initial release

local r = reaper

local function getTrackName(tr)
    local _, name = r.GetTrackName(tr)
    if name == nil or name == "" then
        return "Track " .. tostring(math.floor(r.GetMediaTrackInfo_Value(tr, "IP_TRACKNUMBER")))
    end
    return name
end

local function collectSelectedSources()
    local list, set = {}, {}
    local cnt = r.CountSelectedTracks(0)
    for i = 0, cnt - 1 do
        local tr = r.GetSelectedTrack(0, i)
        list[#list + 1] = tr
        set[tr] = true
    end
    return list, set
end

local function collectDestinations(sourceSet)
    local usage, order = {}, {}
    local trackCount = r.CountTracks(0)
    for i = 0, trackCount - 1 do
        local tr = r.GetTrack(0, i)
        local sendCount = r.GetTrackNumSends(tr, 0)
        for s = 0, sendCount - 1 do
            local dest = r.GetTrackSendInfo_Value(tr, 0, s, "P_DESTTRACK")
            if dest and dest ~= 0 then
                local key = tostring(dest)
                if not usage[key] then
                    usage[key] = { track = dest, count = 0 }
                    order[#order + 1] = key
                end
                usage[key].count = usage[key].count + 1
            end
        end
    end

    local used = {}
    for _, key in ipairs(order) do
        local entry = usage[key]
        if not sourceSet[entry.track] then
            used[#used + 1] = entry
        end
    end
    table.sort(used, function(a, b) return a.count > b.count end)
    return used
end

local function buildMenu(used)
    local parts, slots = {}, {}
    local index = 0
    local function addItem(label, track)
        index = index + 1
        slots[index] = track
        parts[#parts + 1] = label
    end

    addItem("#Send to:", nil)
    for _, e in ipairs(used) do
        addItem(getTrackName(e.track) .. "  (" .. e.count .. "x)", e.track)
    end
    return table.concat(parts, "|"), slots
end

local function showMenuAtMouse(menu)
    local x, y = r.GetMousePosition()
    gfx.init("tk_add_send_menu", 0, 0, 0, x, y)
    if r.JS_Window_Find then
        local hwnd = r.JS_Window_Find("tk_add_send_menu", true)
        if hwnd then r.JS_Window_Show(hwnd, "HIDE") end
    end
    gfx.x, gfx.y = 0, 0
    local ret = gfx.showmenu(menu)
    gfx.quit()
    return ret
end

local function sendExists(srcTr, destTr)
    local n = r.GetTrackNumSends(srcTr, 0)
    for s = 0, n - 1 do
        local d = r.GetTrackSendInfo_Value(srcTr, 0, s, "P_DESTTRACK")
        if d == destTr then return true end
    end
    return false
end

local function main()
    local sources, sourceSet = collectSelectedSources()
    if #sources == 0 then
        r.MB("Select one or more source tracks first.", "Add Send to Selected Tracks", 0)
        return
    end

    local used = collectDestinations(sourceSet)
    if #used == 0 then
        r.MB("No existing send destinations found in this project.", "Add Send to Selected Tracks", 0)
        return
    end

    local menu, slots = buildMenu(used)
    local choice = showMenuAtMouse(menu)
    if choice <= 0 then return end

    local pick = slots[choice]
    if not pick then return end

    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)
    for _, src in ipairs(sources) do
        if src ~= pick and not sendExists(src, pick) then
            r.CreateTrackSend(src, pick)
        end
    end
    r.PreventUIRefresh(-1)
    r.Undo_EndBlock("Add send from selected tracks to " .. getTrackName(pick), -1)
    r.TrackList_AdjustWindows(false)
    r.UpdateArrange()
end

main()
