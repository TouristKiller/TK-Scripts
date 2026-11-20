-- TK Theme: where the mixer shows the master (Mixer page, Master card): in the mixer on the left
-- or the right, in a window of its own (floating or docked), or not at all. These are REAPER's
-- own options, not the theme's: they go through REAPER's actions, found by their names (the
-- numbers are not documented), and the master's visibility. Loaded by TK_Theme_Settings.lua.

local M = {}

-- REAPER's names for them (from REAPER 7's action list)
local NAMES = {
    right = "Mixer: Toggle show master track on right side",
    visible = "Mixer: Master track visible",
    window = "Mixer: toggle master track in separate window",
    docked = "Mixer: toggle master track in docked window",
}

function M.bind(env)
    M.E = env
end

-- the actions' numbers, looked up once by name in the main section
local function find()
    if M.ids then return M.ids end
    local r = M.E.r
    M.ids = {}
    if not r.kbd_getTextFromCmd then return M.ids end
    local want = {}
    for key, name in pairs(NAMES) do want[name:lower()] = key end
    for id = 40000, 44999 do
        local name = r.kbd_getTextFromCmd(id, 0)
        local key = name and want[name:lower()]
        if key then M.ids[key] = id end
    end
    -- only actions that report on/off can be set to a state; one that doesn't is left out
    for key, id in pairs(M.ids) do
        if r.GetToggleCommandState(id) == -1 then M.ids[key] = nil end
    end
    return M.ids
end

local function on(key)
    local id = find()[key]
    return id and M.E.r.GetToggleCommandState(id) == 1
end

local function set(key, want)
    local id = find()[key]
    if id and on(key) ~= want then M.E.r.Main_OnCommand(id, 0) end
end

-- where it is now: "mixer", "window", "docked" or "hidden"
function M.place()
    local r = M.E.r
    local id = find().visible
    if id then
        if r.GetToggleCommandState(id) == 0 then return "hidden" end
    elseif (r.GetMasterTrackVisibility() & 2) ~= 0 then
        return "hidden"
    end
    if on("docked") then return "docked" end
    if on("window") then return "window" end
    return "mixer"
end

function M.set_place(place)
    local r = M.E.r
    -- hidden or shown: REAPER's own action (it also redraws the mixer), else the API
    local function show(want)
        if find().visible then
            set("visible", want)
        else
            local vis = r.GetMasterTrackVisibility()
            r.SetMasterTrackVisibility(want and (vis & ~2) or (vis | 2))
        end
        r.TrackList_AdjustWindows(false)
    end
    if place == "hidden" then
        show(false)
        return
    end
    show(true)
    -- what is on and shouldn't be goes off first, then the one wanted on
    if place ~= "docked" then set("docked", false) end
    if place ~= "window" then set("window", false) end
    if place == "window" then set("window", true) end
    if place == "docked" then set("docked", true) end
end

local PLACES = { { "mixer", "In the mixer" }, { "window", "Own window" }, { "docked", "Own docked window" }, { "hidden", "Hidden" } }

-- the two rows: where, and (in the mixer) which side
function M.draw(id)
    local E = M.E
    local r, ctx = E.r, E.ctx
    local ids = find()
    E.row_label("Master shown")
    r.ImGui_PushID(ctx, id)
    local now = M.place()
    for i, p in ipairs(PLACES) do
        local usable = p[1] == "mixer" or p[1] == "hidden" or ids[p[1]]
        if i > 1 then E.state.next_to(r.ImGui_CalcTextSize(ctx, p[2]) + 16, 2, E.LABEL_W) end
        local active = now == p[1]
        if active then
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), E.rgba(E.mix(E.UI.raised, E.UI.accent, 0.55)))
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), E.rgba(E.UI.ink))
        end
        if not usable then r.ImGui_BeginDisabled(ctx, true) end
        if r.ImGui_Button(ctx, p[2]) and not active then M.set_place(p[1]) end
        if not usable then r.ImGui_EndDisabled(ctx) end
        if active then r.ImGui_PopStyleColor(ctx, 2) end
    end
    if ids.right then
        E.row_label("Master on the side")
        if now ~= "mixer" then r.ImGui_BeginDisabled(ctx, true) end
        local right = on("right")
        for i, side in ipairs({ { false, "Left" }, { true, "Right" } }) do
            if i > 1 then r.ImGui_SameLine(ctx, 0, 2) end
            local active = right == side[1]
            if active then
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), E.rgba(E.mix(E.UI.raised, E.UI.accent, 0.55)))
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), E.rgba(E.UI.ink))
            end
            if r.ImGui_Button(ctx, side[2], 66, 0) and not active then set("right", side[1]) end
            if active then r.ImGui_PopStyleColor(ctx, 2) end
        end
        if now ~= "mixer" then r.ImGui_EndDisabled(ctx) end
    end
    r.ImGui_PopID(ctx)
end

return M
