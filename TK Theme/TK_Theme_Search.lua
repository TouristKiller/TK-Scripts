-- TK Theme: searching the settings window (Ctrl+F). Every setting on the pages with cards is
-- found by its name, its hint, its choices, its card and its page; the ones found are drawn
-- in the results, grouped by card, to be set right there. Pages of their own kind (Look,
-- Colours, ...) are found by their name. Loaded by TK_Theme_Settings.lua (Search.bind).

local Search = { text = "" }

function Search.bind(env)
    Search.E = env
end

local function lower(s)
    return tostring(s or ""):lower()
end

-- what an item is found by: its label, its hint, its choices' names and its extra words
local function item_text(item)
    local t = { item.label or "", item.hint or "", item.words or "" }
    if type(item.choices) == "table" then
        for _, c in ipairs(item.choices) do
            t[#t + 1] = type(c) == "table" and tostring(c[2] or c[1]) or tostring(c)
        end
    end
    return lower(table.concat(t, " "))
end

-- every word of the search somewhere in the text
local function hits(text, words)
    for _, w in ipairs(words) do
        if not text:find(w, 1, true) then return false end
    end
    return true
end

function Search.active()
    return Search.text:match("%S") ~= nil
end

function Search.clear()
    Search.text = ""
end

-- the window's own title row (the window has no title bar of its own when floating): a small
-- display as on the transport, four meter bars and TK THEME SETTINGS in the accent colour; the
-- search in the middle; the version, a dock key and (floating) a close key at the right
local HEADER_H = 40

local function version_text()
    if Search.version ~= nil then return Search.version end
    Search.version = false
    local r = Search.E.r
    if r.ReaPack_GetOwner and r.ReaPack_GetEntryInfo then
        local here = debug.getinfo(1, "S").source:match("^@(.*[\\/])") or ""
        local ok, entry = pcall(r.ReaPack_GetOwner, here .. "TK_Theme_Settings.lua")
        if ok and entry then
            -- pcall's ok, then retval, repo, cat, pkg, desc, type, ver
            local ok2, _, _, _, _, _, _, ver = pcall(r.ReaPack_GetEntryInfo, entry)
            if ok2 and ver and ver ~= "" then Search.version = "v" .. ver end
            pcall(r.ReaPack_FreeEntry, entry)
        end
    end
    return Search.version
end

function Search.header()
    local E = Search.E
    local r, ctx = E.r, E.ctx
    local draw = r.ImGui_GetWindowDrawList(ctx)
    local x0, y0 = r.ImGui_GetCursorScreenPos(ctx)
    local w = r.ImGui_GetContentRegionAvail(ctx)
    local ink = E.rgba(E.UI.accent)
    local dim = E.rgba(E.mix(E.UI.accent, E.UI.glass, 0.45))
    -- the display: its glass, four bars, the name
    r.ImGui_PushFont(ctx, E.mono, 16)
    local t1w = r.ImGui_CalcTextSize(ctx, "TK THEME")
    r.ImGui_PopFont(ctx)
    r.ImGui_PushFont(ctx, E.mono, 11)
    local t2w, t2h = r.ImGui_CalcTextSize(ctx, "SETTINGS")
    r.ImGui_PopFont(ctx)
    local bx, by, bh = x0, y0 + 3, HEADER_H - 6
    local bw = 12 + 4 * 5 + 10 + t1w + 10 + t2w + 14
    r.ImGui_DrawList_AddRectFilled(draw, bx, by, bx + bw, by + bh, E.rgba(E.UI.glass), 6)
    r.ImGui_DrawList_AddRect(draw, bx, by, bx + bw, by + bh, E.rgba(E.UI.dim), 6)
    local base = by + bh - 9
    for i, hgt in ipairs({ 8, 14, 18, 11 }) do
        local x = bx + 12 + (i - 1) * 5
        r.ImGui_DrawList_AddRectFilled(draw, x, base - hgt, x + 3, base, ink)
    end
    local tx = bx + 12 + 4 * 5 + 10
    r.ImGui_PushFont(ctx, E.mono, 16)
    r.ImGui_DrawList_AddText(draw, tx, by + (bh - 16) / 2, ink, "TK THEME")
    r.ImGui_PopFont(ctx)
    r.ImGui_PushFont(ctx, E.mono, 11)
    r.ImGui_DrawList_AddText(draw, tx + t1w + 10, by + (bh - t2h) / 2 + 1, dim, "SETTINGS")
    r.ImGui_PopFont(ctx)
    -- the right: version, then the keys (explanations, dock, close)
    local docked = r.ImGui_IsWindowDocked(ctx)
    local keys = docked and 2 or 3
    local kx = x0 + w - keys * 26
    local right = kx - 10
    local ver = version_text()
    if ver then
        r.ImGui_PushFont(ctx, E.mono, 11)
        local vw, vh = r.ImGui_CalcTextSize(ctx, ver)
        right = kx - vw - 10
        r.ImGui_DrawList_AddText(draw, right, y0 + (HEADER_H - vh) / 2, E.rgba(E.UI.dim), ver)
        r.ImGui_PopFont(ctx)
    end
    -- the search, in the middle between the display and the version
    local left = bx + bw
    local sw = math.max(120, math.min(280, right - left - 24))
    r.ImGui_SetCursorScreenPos(ctx, left + (right - left - sw) / 2, y0 + (HEADER_H - 24) / 2)
    Search.box(sw)
    -- the keys: drawn icons on a quiet square that lights up under the mouse
    local ky = y0 + (HEADER_H - 22) / 2
    local function key(id, x, tip, danger, icon)
        r.ImGui_SetCursorScreenPos(ctx, x, ky)
        local clicked = r.ImGui_InvisibleButton(ctx, id, 22, 22)
        local hot, held = r.ImGui_IsItemHovered(ctx), r.ImGui_IsItemActive(ctx)
        if hot then
            local bg = danger and E.mix(E.UI.raised, 0xD9483B, held and 0.85 or 0.7)
                or E.mix(E.UI.raised, E.UI.accent, held and 0.45 or 0.2)
            r.ImGui_DrawList_AddRectFilled(draw, x, ky, x + 22, ky + 22, E.rgba(bg), 5)
            r.ImGui_SetTooltip(ctx, tip)
        end
        icon(x + 11, ky + 11, E.rgba(hot and E.UI.ink or E.UI.text))
        return clicked
    end
    -- explanations under the settings on or off (off: they show when you point at a setting)
    local hints = not E.state.hints_off
    if key("##tk_hints", kx, hints and "Hide all explanation text: only the settings (pointing at one still explains it)"
        or "Show the explanation text again", false, function(cx, cy, col)
        local c = hints and E.rgba(E.UI.accent) or col
        r.ImGui_DrawList_AddCircle(draw, cx, cy, 7, c, 0, 1.4)
        r.ImGui_DrawList_AddCircleFilled(draw, cx, cy - 3.5, 1.3, c)
        r.ImGui_DrawList_AddLine(draw, cx, cy - 0.5, cx, cy + 4, c, 1.6)
    end) then
        E.state.hints_off = hints
        r.SetExtState("TK Theme", "settings_hints_off", hints and "1" or "0", true)
    end
    kx = kx + 26
    local dock_tip = docked and "Float the window" or "Dock the window"
    if key("##tk_dock", kx, dock_tip, false, function(cx, cy, col)
        -- a window; docked: a second one coming out of it, floating: its lower part filled (the docker)
        if docked then
            r.ImGui_DrawList_AddRect(draw, cx - 6, cy - 2, cx + 3, cy + 6, col, 1.5, 0, 1.4)
            r.ImGui_DrawList_AddRectFilled(draw, cx - 3, cy - 6, cx + 6, cy + 3, E.rgba(E.UI.panel), 1.5)
            r.ImGui_DrawList_AddRect(draw, cx - 3, cy - 6, cx + 6, cy + 3, col, 1.5, 0, 1.4)
        else
            r.ImGui_DrawList_AddRect(draw, cx - 6, cy - 5, cx + 6, cy + 6, col, 1.5, 0, 1.4)
            r.ImGui_DrawList_AddRectFilled(draw, cx - 6, cy + 1, cx + 6, cy + 6, col, 1.5)
        end
    end) then
        E.state.dock_toggle = true
    end
    if not docked then
        if key("##tk_close", kx + 26, "Close", true, function(cx, cy, col)
            r.ImGui_DrawList_AddLine(draw, cx - 4.5, cy - 4.5, cx + 4.5, cy + 4.5, col, 1.6)
            r.ImGui_DrawList_AddLine(draw, cx + 4.5, cy - 4.5, cx - 4.5, cy + 4.5, col, 1.6)
        end) then
            E.state.close = true
        end
    end
    -- a line under the row, then the window as before
    r.ImGui_DrawList_AddLine(draw, x0, y0 + HEADER_H + 2, x0 + w, y0 + HEADER_H + 2, E.rgba(E.UI.dim), 1)
    r.ImGui_SetCursorScreenPos(ctx, x0, y0 + HEADER_H + 6)
    r.ImGui_Dummy(ctx, 0, 0)
end

-- the box, in the title row: Ctrl+F puts you in it, Escape empties it
function Search.box(width)
    local E = Search.E
    local r, ctx = E.r, E.ctx
    if r.ImGui_IsWindowFocused(ctx, r.ImGui_FocusedFlags_RootAndChildWindows())
        and r.ImGui_IsKeyDown(ctx, r.ImGui_Mod_Ctrl()) and r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_F()) then
        Search.focus = true
    end
    if Search.focus then
        r.ImGui_SetKeyboardFocusHere(ctx)
        Search.focus = nil
    end
    r.ImGui_SetNextItemWidth(ctx, width or -1)
    local changed, v = r.ImGui_InputTextWithHint(ctx, "##tk_search", "Search (Ctrl+F)", Search.text)
    if changed then Search.text = v end
    if r.ImGui_IsItemActive(ctx) and r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_Escape()) then Search.text = "" end
end

-- the results, in the content area
function Search.draw()
    local E = Search.E
    local r, ctx = E.r, E.ctx
    local words = {}
    for w in lower(Search.text):gmatch("%S+") do words[#words + 1] = w end
    local found = 0
    for pi, page in ipairs(E.PAGES) do
        if page.cards then
            for ci, card in ipairs(page.cards) do
                local where = lower(page.title .. " " .. card[1])
                local items = {}
                for ii, item in ipairs(card[2]) do
                    if hits(where .. " " .. item_text(item), words) then items[#items + 1] = { ii, item } end
                end
                if #items > 0 then
                    found = found + #items
                    if E.begin_card(page.title .. "  >  " .. card[1], "search" .. pi .. "_" .. ci) then
                        for _, p in ipairs(items) do
                            local ii, item = p[1], p[2]
                            local hide = item.hide and item.hide()
                            local off = hide or (item.off and item.off())
                            local id = "search" .. pi .. "_" .. ci .. "_" .. ii
                            if off then r.ImGui_BeginDisabled(ctx, true) end
                            E.draw_setting(item, id)
                            E.state.mark_item = nil
                            if off then r.ImGui_EndDisabled(ctx) end
                            if off and item.grey and not hide then
                                E.state.draw_why(item, id)
                            elseif off then
                                E.hint_text("Not with the choices you have now: on its page it is hidden.")
                            end
                        end
                        r.ImGui_Dummy(ctx, 0, 2)
                        if r.ImGui_SmallButton(ctx, "Go to " .. page.title .. "##go" .. pi .. "_" .. ci) then
                            E.state.page = pi
                            E.state.tab_want = card[1]
                            Search.text = ""
                        end
                        r.ImGui_EndChild(ctx)
                    end
                    r.ImGui_Dummy(ctx, 0, 2)
                end
            end
        elseif hits(lower(page.title), words) then
            -- a page of its own kind: found by its name only
            found = found + 1
            if r.ImGui_Button(ctx, "Open the " .. page.title .. " page##open" .. pi) then
                E.state.page = pi
                Search.text = ""
            end
            r.ImGui_Dummy(ctx, 0, 2)
        end
    end
    if found == 0 then
        E.hint_text('Nothing found for "' .. Search.text .. '". Try another word, or fewer.')
    end
end

return Search
