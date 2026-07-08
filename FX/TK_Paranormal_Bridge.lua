-- @description TK Paranormal FX Bridge (drag FX from TK FX Browser into Paranormal)
-- @author TouristKiller
-- @version 1.0.0
-- @changelog:
--   + Initial release: launches Paranormal FX and lets you drop plugins from TK FX Browser / Mini onto the canvas.

local r = reaper

local ROUTER = r.GetResourcePath() .. "/Scripts/Sexan_Scripts/ParanormalFX/Sexan_ParaNormal_FX_Router.lua"
if not r.file_exists(ROUTER) then
    r.ShowMessageBox(
        "Paranormal FX not found.\nExpected:\n" .. ROUTER ..
        "\n\nInstall 'Sexan Paranormal FX Router' via ReaPack first.",
        "TK Paranormal Bridge", 0)
    return
end

dofile(ROUTER)

if type(Draw) ~= "function"
   or type(AddFX) ~= "function"
   or type(CalcFxID) ~= "function"
   or type(GetParentContainerByGuid) ~= "function" then
    r.ShowMessageBox(
        "This Paranormal FX version is not compatible with the bridge\n" ..
        "(internal API changed). Nothing was patched; Paranormal runs normally.",
        "TK Paranormal Bridge", 0)
    return
end

local DROP_COLOR = 0x00FF88FF
local PARA_COLOR = 0x33AAFFFF  -- parallel "||" drop zone colour
local PLUS_W = 56  -- fixed width of the "+" drop zone (px @ 100% zoom)
local PARA_W = 34  -- size of the parallel "||" drop zone (px @ 100% zoom)

if type(GetPayload) == "function" then
    local ORIG_GetPayload = GetPayload
    function GetPayload()
        local dndtype, payload = ORIG_GetPayload()
        if (not dndtype or dndtype == "") and r.HasExtState("TKFXB", "drag_fx") then
            return "DND ADD FX", ""
        end
        return dndtype, payload
    end
end

-- Find the "+" (serial) or "||" (parallel) drop zone under the cursor.
-- Returns: add_id, parallel, hx1, hy1, hx2, hy2
local function FindPlusSlot(tbl, mx, my, pad, hw, paraw, vertical, dim)
    if type(tbl) ~= "table" then return nil end
    local nodes = {}
    for i = 0, #tbl do
        local n = tbl[i]
        if type(n) == "table" and n.xs and n.type ~= "ROOT" and n.type ~= "INSERT_POINT" then
            nodes[#nodes + 1] = n
        end
    end
    -- deeper (container) gaps win
    for _, n in ipairs(nodes) do
        if n.sub then
            local id, par, a, b, c, d = FindPlusSlot(n.sub, mx, my, pad, hw, paraw, vertical, dim)
            if id then return id, par, a, b, c, d end
            if n.xs and mx >= n.xs and mx <= n.xe and my >= n.ys and my <= n.ye then
                local innerLast = 0
                for j = 0, #n.sub do
                    local s = n.sub[j]
                    if type(s) == "table" and s.xs and s.type ~= "ROOT" and s.type ~= "INSERT_POINT"
                        and (s.IDX or 0) > innerLast then
                        innerLast = s.IDX
                    end
                end
                local aid = CalcFxID(n, innerLast + 1)
                if aid then
                    local cx = (n.xs + n.xe) * 0.5
                    return aid, false,
                        cx - dim.aw * 0.5, n.ye - dim.ah - dim.sp, cx + dim.aw * 0.5, n.ye - dim.sp
                end
            end
        end
    end
    if #nodes == 0 then
        local ref = tbl[0]
        if type(ref) ~= "table" or ref.type ~= "ROOT" or not ref.xs then return nil end
        local aid = CalcFxID(ref, 1)
        if not aid then return nil end
        if mx >= ref.xs - pad and mx <= ref.xe + pad and my >= ref.ys and my <= ref.ye + pad * 3 then
            local cx = (ref.xs + ref.xe) * 0.5
            return aid, false,
                cx - dim.aw * 0.5, ref.ye + dim.sp, cx + dim.aw * 0.5, ref.ye + dim.sp + dim.ah
        end
        return nil
    end

    local parent = GetParentContainerByGuid(nodes[1])
    if not parent then return nil end

    local rows = {}
    for k = 1, #nodes do
        local n = nodes[k]
        if (n.p or 0) == 0 or k == 1 then
            rows[#rows + 1] = { n }
        else
            table.insert(rows[#rows], n)
        end
    end

    local rb = {}
    for i = 1, #rows do
        local xs, ys, xe, ye = math.huge, math.huge, -math.huge, -math.huge
        for _, n in ipairs(rows[i]) do
            if n.xs < xs then xs = n.xs end
            if n.ys < ys then ys = n.ys end
            if n.xe > xe then xe = n.xe end
            if n.ye > ye then ye = n.ye end
        end
        rb[i] = { xs = xs, ys = ys, xe = xe, ye = ye, first = rows[i][1], last = rows[i][#rows[i]] }
    end

    local function hit(x1, y1, x2, y2, slot, parallel, dx1, dy1, dx2, dy2)
        if mx >= x1 and mx <= x2 and my >= y1 and my <= y2 then
            local id = CalcFxID(parent, slot)
            if id then return id, parallel, dx1 or x1, dy1 or y1, dx2 or x2, dy2 or y2 end
        end
    end

    local aw, ah, pw, ph, sp, po, ny = dim.aw, dim.ah, dim.pw, dim.ph, dim.sp, dim.po, dim.ny

    if vertical then
        local cxs, cxe = math.huge, -math.huge
        for i = 1, #rows do
            if rb[i].xs < cxs then cxs = rb[i].xs end
            if rb[i].xe > cxe then cxe = rb[i].xe end
        end
        local bx1 = cxs - pad
        local px = (rb[1].xs + rb[1].xe) * 0.5 - pw + po
        local px1, px2 = px - aw * 0.5, px + aw * 0.5
        local f = rb[1]
        local dcy = f.ys - pad * 0.5
        local id, par, a, b, c, d = hit(bx1, f.ys - pad, cxe, f.ys, f.first.IDX, false,
            px1, dcy - ah * 0.5, px2, dcy + ah * 0.5)
        if id then return id, par, a, b, c, d end
        for i = 1, #rows do
            local rw, nxt = rb[i], rb[i + 1]
            local gb = nxt and nxt.ys or (rw.ye + pad)
            dcy = (rw.ye + gb) * 0.5
            id, par, a, b, c, d = hit(bx1, rw.ye, cxe, gb, rw.last.IDX + 1, false,
                px1, dcy - ah * 0.5, px2, dcy + ah * 0.5)
            if id then return id, par, a, b, c, d end
        end
        for i = 1, #rows do
            local rw = rb[i]
            id, par, a, b, c, d = hit(rw.xe, rw.ys, rw.xe + paraw, rw.ye, rw.last.IDX + 1, true,
                rw.xe + sp, rw.ys, rw.xe + sp + pw, rw.ys + ph)
            if id then return id, par, a, b, c, d end
        end
    else
        for i = 1, #rows do
            local rw = rb[i]
            local cx = rw.first.x or rw.first.xs
            local dcy = (rw.ys + rw.ye) * 0.5
            local id, par, a, b, c, d = hit(cx - hw, rw.ys, cx + hw, rw.ye, rw.first.IDX, false,
                cx - aw * 0.5, dcy - ah * 0.5, cx + aw * 0.5, dcy + ah * 0.5)
            if id then return id, par, a, b, c, d end
        end
        local last = rb[#rows]
        local dcy = (last.ys + last.ye) * 0.5
        local id, par, a, b, c, d = hit(last.xe, last.ys, last.xe + 2 * hw, last.ye, last.last.IDX + 1, false,
            last.xe + sp, dcy - ah * 0.5, last.xe + sp + aw, dcy + ah * 0.5)
        if id then return id, par, a, b, c, d end
        for i = 1, #rows do
            local rw = rb[i]
            id, par, a, b, c, d = hit(rw.xs, rw.ye, rw.xs + paraw, rw.ye + paraw, rw.last.IDX + 1, true,
                rw.xs, rw.ye + ny, rw.xs + pw, rw.ye + ny + ph)
            if id then return id, par, a, b, c, d end
        end
    end
    return nil
end

local DEBUG = false
local _last_dbg = ""
local function DBG(msg)
    if not DEBUG then return end
    if msg ~= _last_dbg then
        r.ShowConsoleMsg("[TKParaBridge] " .. msg .. "\n")
        _last_dbg = msg
    end
end

local function InsertAtSlot(add_id, parallel, payload)
    if not add_id then return false end
    INSERT_FX_SERIAL_POS, INSERT_FX_PARALLEL_POS, REPLACE_FX_POS, INSERT_FX_ENCLOSE_POS = nil, nil, nil, nil
    local ok, err = pcall(function()
        for fx in (payload .. "\n"):gmatch("(.-)\n") do
            if fx ~= "" then
                AddFX(fx, add_id, parallel and true or false)
            end
        end
    end)
    if not ok then DBG("insert ERROR: " .. tostring(err)) end
    return ok
end

local function AppendRoot(payload)
    return pcall(function()
        r.Undo_BeginBlock()
        r.PreventUIRefresh(1)
        for fx in (payload .. "\n"):gmatch("(.-)\n") do
            if fx ~= "" then
                if MODE == "ITEM" and TAKE and r.ValidatePtr(TAKE, "MediaItem_Take*") then
                    r.TakeFX_AddByName(TAKE, fx, -1)
                elseif TRACK and r.ValidatePtr(TRACK, "MediaTrack*") then
                    r.TrackFX_AddByName(TRACK, fx, false, -1)
                end
            end
        end
        r.PreventUIRefresh(-1)
        r.Undo_EndBlock("Add FX from TK FX Browser", -1)
    end)
end

local latched_payload = nil
local claimed = false
local prev_down = false

local function ReleaseClaim()
    if claimed then
        r.DeleteExtState("TKFXB", "drag_consumed", false)
        claimed = false
    end
end

local function Claim()
    if not claimed then
        r.SetExtState("TKFXB", "drag_consumed", "1", false)
        claimed = true
    end
end

local function GlobalMouse()
    if r.ImGui_PointConvertNative and r.GetMousePosition then
        local sx, sy = r.GetMousePosition()
        local ok, cx, cy = pcall(r.ImGui_PointConvertNative, ctx, sx, sy)
        if ok and cx then return cx, cy end
    end
    return MX, MY
end

local function MouseDown()
    if r.JS_Mouse_GetState then
        return (r.JS_Mouse_GetState(1) & 1) == 1
    end
    return r.ImGui_IsMouseDown(ctx, 0)
end

local ORIG_DRAW = Draw

local _upv = {}
local function GetUpv(name, fallback)
    if not (debug and debug.getupvalue) then return fallback end
    local idx = _upv[name]
    if idx == nil then
        idx = false
        local i = 1
        while true do
            local n = debug.getupvalue(ORIG_DRAW, i)
            if not n then break end
            if n == name then idx = i; break end
            i = i + 1
        end
        _upv[name] = idx
    end
    if idx then
        local _, val = debug.getupvalue(ORIG_DRAW, idx)
        return val
    end
    return fallback
end

function Draw()
    ORIG_DRAW()

    local down = MouseDown()
    local released = prev_down and not down
    prev_down = down

    local has = r.HasExtState("TKFXB", "drag_fx")
    if has then
        local p = r.GetExtState("TKFXB", "drag_fx")
        if p ~= "" then latched_payload = p end
    end
    if not latched_payload then return end

    if not has and not down then
        latched_payload = nil
        ReleaseClaim()
        return
    end

    local gmx, gmy = GlobalMouse()
    local plugins = GetUpv("PLUGINS", PLUGINS)
    local canvas = GetUpv("CANVAS", CANVAS)
    local vlay = GetUpv("V_LAYOUT", V_LAYOUT)
    local vertical = vlay ~= false
    local scale = (canvas and canvas.scale) or 1
    local pad = 28 * scale
    local hw = (PLUS_W * 0.5) * scale
    local paraw = PARA_W * scale
    local dim = {
        aw = (ADD_BTN_W or 55) * scale,
        ah = (ADD_BTN_H or 14) * scale,
        pw = (para_btn_size or 16) * scale,
        ph = (def_btn_h or 16) * scale,
        sp = (def_s_spacing_x or 8) * scale,
        po = 22 * scale,
        ny = (new_spacing_y or 10) * scale,
    }

    local slot_id, parallel, hx1, hy1, hx2, hy2
    if plugins and gmx and gmy then
        slot_id, parallel, hx1, hy1, hx2, hy2 = FindPlusSlot(plugins, gmx, gmy, pad, hw, paraw, vertical, dim)
    end

    if not slot_id then
        ReleaseClaim()
        if released then latched_payload = nil end
        return
    end

    if DEBUG then
        DBG("drag | slot=" .. tostring(slot_id))
    end

    local dl = r.ImGui_GetForegroundDrawList and r.ImGui_GetForegroundDrawList(ctx) or nil
    if dl and hx1 then
        local col = parallel and PARA_COLOR or DROP_COLOR
        r.ImGui_DrawList_AddRectFilled(dl, hx1, hy1, hx2, hy2, (col & 0xFFFFFF00) | 0x44)
        r.ImGui_DrawList_AddRect(dl, hx1, hy1, hx2, hy2, col, 2, 0, 2)
    end

    Claim()

    if released then
        local ok = InsertAtSlot(slot_id, parallel, latched_payload)
        if not ok then ok = AppendRoot(latched_payload) end
        if ok then
            r.DeleteExtState("TKFXB", "drag_fx", false)
        else
            ReleaseClaim()
        end
        latched_payload = nil
        claimed = false
    end
end
