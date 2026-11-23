-- TK Theme: the transport's icon picker (Transport page, 0.9.99). A button that runs an action of
-- your choice (Button 1-3, and the ten whose action can be swapped) can wear another icon: one
-- of the theme's own (TK icons, drawn by the generator in every look and display skin), or one
-- of REAPER's toolbar icons (Data/toolbar_icons), turned into the button's look here: its shape
-- in the ink the theme gives each of the button's three frames, on the button without a glyph.
-- Both come from the display pack in use (icons/ in dist/display/<skin or look standard>.zip).
-- The choices are kept in Data/TK Theme/icons.txt; Icons.ensure puts them into the theme again
-- whenever the display, the look or an accent wrote the buttons over. Loaded by
-- TK_Theme_Settings.lua (Icons.bind).

local Icons = { chosen = {}, ui = nil, tex = {}, conv = {} }
local SCALES = { { "", 1 }, { "150/", 1.5 }, { "200/", 2 } }

function Icons.bind(env)
    Icons.E = env
    Icons.file = env.r.GetResourcePath() .. "/Data/TK Theme/icons.txt"
    Icons.folder = env.r.GetResourcePath() .. "/Data/toolbar_icons/"
    Icons.load()
end

function Icons.load()
    Icons.chosen = {}
    local f = io.open(Icons.file, "rb")
    if not f then return end
    for line in f:lines() do
        local k, v = line:match("^(%w+)=(.+)$")
        if k then Icons.chosen[k] = v end
    end
    f:close()
end

function Icons.save()
    local keys = {}
    for k in pairs(Icons.chosen) do keys[#keys + 1] = k end
    table.sort(keys)
    local f = io.open(Icons.file, "wb")
    if not f then return end
    for _, k in ipairs(keys) do f:write(k, "=", Icons.chosen[k], "\n") end
    f:close()
end

-- the display pack in use (the look's own, or a display skin's)
local function pack(zip)
    local E = Icons.E
    return E.parts.display_pack(zip, E.parts.chosen.display or E.parts.default.display)
end

local function read_file(path)
    local f = io.open(path, "rb")
    if not f then return nil end
    local d = f:read("a")
    f:close()
    return d
end

-- a toolbar icon's shape: the alpha of its first frame (three frames side by side, or one),
-- cropped to what shows. From its 200% file where there is one: the sharpest to shrink
local function icon_mask(name)
    local E = Icons.E
    local data
    for _, sub in ipairs({ "200/", "150/", "" }) do
        data = read_file(Icons.folder .. sub .. name)
        if data then break end
    end
    if not data then return nil, "not found" end
    local W, H, px = E.decode(data)
    if not W then return nil, H end
    local fw = W >= 3 * H and math.floor(W / 3) or W
    local x0, y0, x1, y1 = fw, H, -1, -1
    local a = {}
    for y = 0, H - 1 do
        for x = 0, fw - 1 do
            local v = px:byte((y * W + x) * 4 + 4)
            a[y * fw + x] = v
            if v > 8 then
                if x < x0 then x0 = x end
                if x > x1 then x1 = x end
                if y < y0 then y0 = y end
                if y > y1 then y1 = y end
            end
        end
    end
    if x1 < 0 then return nil, "empty" end
    return { a = a, fw = fw, x0 = x0, y0 = y0, w = x1 - x0 + 1, h = y1 - y0 + 1 }
end

-- the mask's value at a point of its crop (0..1), bilinear
local function sample(m, x, y)
    x, y = x + m.x0 - 0.5, y + m.y0 - 0.5
    local ix, iy = math.floor(x), math.floor(y)
    local fx, fy = x - ix, y - iy
    local function at(px, py)
        if px < m.x0 or py < m.y0 or px >= m.x0 + m.w or py >= m.y0 + m.h then return 0 end
        return m.a[py * m.fw + px] or 0
    end
    local v = at(ix, iy) * (1 - fx) * (1 - fy) + at(ix + 1, iy) * fx * (1 - fy)
        + at(ix, iy + 1) * (1 - fx) * fy + at(ix + 1, iy + 1) * fx * fy
    return v / 255
end

-- a toolbar icon as a transport button at one scale: on the blank button, in each frame's ink
local function convert(pk, name, sub, sc)
    local E = Icons.E
    local blank = pk["icons/blank/" .. sub .. "transB.png"]
    local ink = pk["icons/ink.txt"]
    if not (blank and ink) then return nil end
    local m = icon_mask(name)
    if not m then return nil end
    local W, H, px = E.decode(blank)
    if not W then return nil end
    local out = {}
    for i = 1, W * H * 4 do out[i] = px:byte(i) end
    for line in ink:gmatch("[^\n]+") do
        local s, _, cx, cy, box, cr, cg, cb, ca = line:match("^(%S+) (%d) (%S+) (%S+) (%S+) (%d+) (%d+) (%d+) (%d+)")
        if tonumber(s) == sc then
            cx, cy, box = tonumber(cx), tonumber(cy), tonumber(box)
            cr, cg, cb, ca = tonumber(cr), tonumber(cg), tonumber(cb), tonumber(ca) / 255
            local k = box / math.max(m.w, m.h)
            local tw, th = m.w * k, m.h * k
            local left, top = cx - tw / 2, cy - th / 2
            -- every pixel the icon covers, 4 x 4 samples each
            for y = math.floor(top), math.ceil(top + th) - 1 do
                for x = math.floor(left), math.ceil(left + tw) - 1 do
                    if x >= 0 and y >= 0 and x < W and y < H then
                        local sum = 0
                        for sy = 0, 3 do
                            for sx = 0, 3 do
                                local ux = (x + (sx + 0.5) / 4 - left) / k
                                local uy = (y + (sy + 0.5) / 4 - top) / k
                                if ux >= 0 and uy >= 0 and ux < m.w and uy < m.h then sum = sum + sample(m, ux, uy) end
                            end
                        end
                        local a = sum / 16 * ca
                        if a > 0 then
                            local p = (y * W + x) * 4
                            local da = out[p + 4] / 255
                            local oa = a + da * (1 - a)
                            if oa > 0 then
                                out[p + 1] = math.floor((cr * a + out[p + 1] * da * (1 - a)) / oa + 0.5)
                                out[p + 2] = math.floor((cg * a + out[p + 2] * da * (1 - a)) / oa + 0.5)
                                out[p + 3] = math.floor((cb * a + out[p + 3] * da * (1 - a)) / oa + 0.5)
                            end
                            out[p + 4] = math.floor(oa * 255 + 0.5)
                        end
                    end
                end
            end
        end
    end
    local parts = {}
    for i = 1, #out, 4096 do parts[#parts + 1] = string.char(table.unpack(out, i, math.min(#out, i + 4095))) end
    return E.png(W, H, table.concat(parts), E.Zip.crc32)
end

Icons._convert = function(...) return convert(...) end

-- what a button's image should be at one scale: { [rel] = png }, or nil for its own
local function wanted(pk, key, choice, sub, sc)
    if not choice or choice == "" then return nil end
    local kind, name = choice:match("^(%a+):(.+)$")
    if kind == "tk" then return pk["icons/tk/" .. name .. "/" .. sub .. "transB.png"] end
    if kind == "tb" then
        local id = (pk["icons/ink.txt"] or "") .. "|" .. name .. "|" .. sub
        if Icons.conv[id] == nil then Icons.conv[id] = convert(pk, name, sub, sc) or false end
        return Icons.conv[id] or nil
    end
    if kind == "own" then return pk[sub .. "transB_" .. key .. ".png"] end
    return nil
end

-- the chosen icons into the theme where they are not (after the display, the look or an
-- accent wrote the buttons): true when it wrote. Inside a batch or together: no reload here
function Icons.ensure(zip)
    local E = Icons.E
    zip = zip or E.parts.zip_path()
    local root = E.Zip.root(zip)
    local pk = root and pack(zip)
    if not pk or not pk["icons/ink.txt"] then return false end
    local files = {}
    for key, choice in pairs(Icons.chosen) do
        for _, s in ipairs(SCALES) do
            local data = wanted(pk, key, choice, s[1], s[2])
            local rel = root .. "/" .. s[1] .. "transB_" .. key .. ".png"
            if data and E.Zip.crc_of(zip, rel) ~= E.Zip.crc32(data) then files[rel] = data end
        end
    end
    if not next(files) then return false end
    local ok = E.Zip.replace(zip, files)
    return ok and true or false
end

-- a choice made: kept, written, and the theme reloaded (own: the button's own image back,
-- once; then it is no longer kept)
function Icons.choose(key, choice)
    local E = Icons.E
    Icons.chosen[key] = choice
    E.parts.together(function()
        if Icons.ensure() then E.parts.reload() end
    end)
    if choice == "own" then Icons.chosen[key] = nil end
    Icons.save()
end

-- ---------------------------------------------------------------- the picker
-- images are NOT attached to the context: ReaImGui caps attachments (~1000), and paging
-- through the toolbar icons hit it (Vincent, page 17). An unattached image lives as long as
-- it is drawn every frame; ReaImGui frees the ones of pages left behind, and a freed one
-- found in the cache is simply loaded again.
-- A freed image can't be told by ValidatePtr alone: a new image may get its address, and the
-- old entry then passes as valid and shows that other picture (Vincent: after a tab switch the
-- TK icons sat over the toolbar ones until the settings were reopened). So an entry is only
-- trusted when it was drawn in the frame before; one left undrawn is loaded again.
local function texture(id, make)
    local r, ctx = Icons.E.r, Icons.E.ctx
    local frame = r.ImGui_GetFrameCount(ctx)
    local e = Icons.tex[id]
    if e and e.img and (e.used < frame - 1 or not r.ImGui_ValidatePtr(e.img, "ImGui_Image*")) then e = nil end
    if e == nil then
        local ok, img = pcall(make)
        e = { img = ok and img or false }
        Icons.tex[id] = e
    end
    e.used = frame
    return e.img or nil
end

-- a TK icon's picture: its 200% button image, normal frame
local function tk_image(pk, name)
    local data = pk["icons/tk/" .. name .. "/200/transB.png"]
    if not data then return nil end
    return texture("tk|" .. (pk["icons/ink.txt"] or "") .. name, function() return Icons.E.r.ImGui_CreateImageFromMem(data) end)
end

local function tb_image(name)
    return texture("tb|" .. name, function() return Icons.E.r.ImGui_CreateImage(Icons.folder .. name) end)
end

-- the toolbar icons, found once per opening of the picker
local function toolbar_list()
    local E = Icons.E
    if Icons.list then return Icons.list end
    local list, i = {}, 0
    while true do
        local f = E.r.EnumerateFiles(Icons.folder, i)
        if not f then break end
        if f:lower():match("%.png$") then list[#list + 1] = f end
        i = i + 1
    end
    table.sort(list, function(a, b) return a:lower() < b:lower() end)
    Icons.list = list
    return list
end

-- the button that shows a key's icon and opens the picker
function Icons.button(key, label)
    local E = Icons.E
    local r, ctx = E.r, E.ctx
    local choice = Icons.chosen[key]
    local text = "Icon..."
    if choice then
        local kind, name = choice:match("^(%a+):(.+)$")
        text = "Icon: " .. (kind == "tb" and (name:gsub("%.png$", "")) or name)
        if #text > 26 then text = text:sub(1, 24) .. ".." end
    end
    if r.ImGui_Button(ctx, text .. "##icon" .. key) then
        Icons.ui = { key = key, label = label, tab = 1, filter = "", page = 0 }
        Icons.list = nil
        r.ImGui_OpenPopup(ctx, "Icon for this button##iconpicker")
    end
end

local CELL = 40

-- how many icons fit in a row: each is CELL plus its frame padding on both sides, with the
-- item spacing between them (counting only CELL + 8 lost the last column, the user saw)
local function per_row(avail)
    local E = Icons.E
    local r, ctx = E.r, E.ctx
    local px = r.ImGui_GetStyleVar(ctx, r.ImGui_StyleVar_FramePadding())
    local sx = r.ImGui_GetStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing())
    return math.max(1, math.floor((avail + sx) / (CELL + 2 * px + sx)))
end

-- the picker itself: drawn right after its button (Icons.button), in the same ID scope, which
-- a popup needs to find the one its button opened
function Icons.draw(key)
    local E = Icons.E
    local r, ctx = E.r, E.ctx
    if not Icons.ui or Icons.ui.key ~= key then return end
    r.ImGui_SetNextWindowSize(ctx, 520, 440, r.ImGui_Cond_Appearing())
    if not r.ImGui_BeginPopupModal(ctx, "Icon for this button##iconpicker", true) then
        Icons.ui = nil
        return
    end
    local u = Icons.ui
    local zip = E.parts.zip_path()
    local pk = pack(zip)
    r.ImGui_Text(ctx, u.label)
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "The theme's own") then
        Icons.choose(u.key, "own")
        r.ImGui_CloseCurrentPopup(ctx)
    end
    local function pick(choice)
        Icons.choose(u.key, choice)
        r.ImGui_CloseCurrentPopup(ctx)
    end
    if r.ImGui_BeginTabBar(ctx, "icontabs") then
        if r.ImGui_BeginTabItem(ctx, "TK icons") then
            if not (pk and pk["icons/list.txt"]) then
                r.ImGui_TextWrapped(ctx, "This theme has no icons yet: update TK Theme.")
            else
                local avail = r.ImGui_GetContentRegionAvail(ctx)
                local per = per_row(avail)
                local n = 0
                for name in pk["icons/list.txt"]:gmatch("[^\n]+") do
                    local img = tk_image(pk, name)
                    if n % per ~= 0 then r.ImGui_SameLine(ctx) end
                    n = n + 1
                    local sel = Icons.chosen[u.key] == "tk:" .. name
                    if img then
                        if r.ImGui_ImageButton(ctx, "tk" .. name, img, CELL, CELL, 0, 0, 1 / 3, 1) then pick("tk:" .. name) end
                    elseif r.ImGui_Button(ctx, name, CELL + 8, CELL + 8) then pick("tk:" .. name) end
                    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, name .. (sel and " (now)" or "")) end
                end
            end
            r.ImGui_EndTabItem(ctx)
        end
        if r.ImGui_BeginTabItem(ctx, "Toolbar icons") then
            local changed
            r.ImGui_SetNextItemWidth(ctx, 220)
            changed, u.filter = r.ImGui_InputTextWithHint(ctx, "##iconfilter", "Search", u.filter)
            if changed then u.page = 0 end
            local list, shown = toolbar_list(), {}
            local want = u.filter:lower()
            for _, f in ipairs(list) do
                if want == "" or f:lower():find(want, 1, true) then shown[#shown + 1] = f end
            end
            local per_page = 60
            local pages = math.max(1, math.ceil(#shown / per_page))
            if u.page >= pages then u.page = pages - 1 end
            r.ImGui_SameLine(ctx)
            r.ImGui_Text(ctx, #shown .. " icons")
            if pages > 1 then
                r.ImGui_SameLine(ctx)
                if r.ImGui_ArrowButton(ctx, "##prev", r.ImGui_Dir_Left()) and u.page > 0 then u.page = u.page - 1 end
                r.ImGui_SameLine(ctx)
                r.ImGui_Text(ctx, (u.page + 1) .. " / " .. pages)
                r.ImGui_SameLine(ctx)
                if r.ImGui_ArrowButton(ctx, "##next", r.ImGui_Dir_Right()) and u.page < pages - 1 then u.page = u.page + 1 end
            end
            if r.ImGui_BeginChild(ctx, "##tbgrid", 0, 0) then
                local avail = r.ImGui_GetContentRegionAvail(ctx)
                local per = per_row(avail)
                local n = 0
                for i = u.page * per_page + 1, math.min(#shown, (u.page + 1) * per_page) do
                    local f = shown[i]
                    local img = tb_image(f)
                    if n % per ~= 0 then r.ImGui_SameLine(ctx) end
                    n = n + 1
                    if img then
                        local w, h = r.ImGui_Image_GetSize(img)
                        local u1 = (w >= 3 * h) and 1 / 3 or 1
                        if r.ImGui_ImageButton(ctx, "tb" .. f, img, CELL, CELL, 0, 0, u1, 1) then pick("tb:" .. f) end
                    elseif r.ImGui_Button(ctx, "?##" .. f, CELL + 8, CELL + 8) then pick("tb:" .. f) end
                    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, (f:gsub("%.png$", ""))) end
                end
                r.ImGui_EndChild(ctx)
            end
            r.ImGui_EndTabItem(ctx)
        end
        r.ImGui_EndTabBar(ctx)
    end
    r.ImGui_EndPopup(ctx)
end

return Icons
