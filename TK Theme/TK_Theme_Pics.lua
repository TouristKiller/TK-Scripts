-- TK Theme: small drawn pictures on the settings window's choice buttons, for choices of where
-- something goes (knobs or sliders, keys above or beside the fader, mute and solo left or right,
-- ...). Schematic, in the window's own colours and the accent, so they follow every look and
-- accent without images. Loaded by TK_Theme_Settings.lua (Pics.bind); a choice item names its
-- picture with pic = "<name>", and Pics.button draws the button with it.

local Pics = {}

local W, H = 56, 28        -- the picture's box on the button

function Pics.bind(env)
    Pics.E = env
end

-- the drawing tools, in the button's draw list, relative to the picture's box
local function tools(dl, x0, y0, on)
    local E = Pics.E
    local r = E.r
    local line = E.rgba(on and E.UI.ink or E.mix(E.UI.text, E.UI.raised, 0.25))
    local soft = E.rgba(E.mix(E.UI.text, E.UI.raised, 0.6))
    local acc = E.rgba(E.UI.accent)
    local glass = E.rgba(E.UI.glass)
    local t = {}
    function t.box(x, y, w, h, col, round) r.ImGui_DrawList_AddRectFilled(dl, x0 + x, y0 + y, x0 + x + w, y0 + y + h, col, round or 1.5) end
    function t.frame(x, y, w, h, col, round) r.ImGui_DrawList_AddRect(dl, x0 + x, y0 + y, x0 + x + w, y0 + y + h, col, round or 2, 0, 1) end
    function t.knob(x, y, rad, col)
        r.ImGui_DrawList_AddCircleFilled(dl, x0 + x, y0 + y, rad, col)
        r.ImGui_DrawList_AddLine(dl, x0 + x, y0 + y, x0 + x + rad * 0.55, y0 + y - rad * 0.75, glass, 1.3)
    end
    -- a horizontal slider: its line and a handle at t (0..1)
    function t.hslider(x, y, w, at, col)
        t.box(x, y - 1, w, 2, soft, 1)
        t.box(x, y - 1, w * at, 2, acc, 1)
        r.ImGui_DrawList_AddCircleFilled(dl, x0 + x + w * at, y0 + y, 2.6, col)
    end
    -- a standing fader: its slot and a cap
    function t.fader(x, y, h, col)
        t.box(x, y, 2, h, soft, 1)
        t.box(x - 3, y + h * 0.35, 8, 4, col, 1)
    end
    -- a standing meter: two bars, lit from the bottom
    function t.meter(x, y, h)
        for i = 0, 1 do
            t.box(x + i * 4, y, 3, h, glass, 0)
            t.box(x + i * 4, y + h * (0.35 + i * 0.12), 3, h * (0.65 - i * 0.12), acc, 0)
        end
    end
    -- a lying meter: one bar, lit from the left
    function t.hmeter(x, y, w)
        t.box(x, y, w, 3, glass, 0)
        t.box(x, y, w * 0.6, 3, acc, 0)
    end
    -- part of an image (u0 v0 to u1 v1 of it) into x, y, w, h of the box
    function t.image(img, x, y, w, h, u0, v0, u1, v1)
        if img then
            r.ImGui_DrawList_AddImage(dl, img, x0 + x, y0 + y, x0 + x + w, y0 + y + h, u0 or 0, v0 or 0, u1 or 1, v1 or 1)
        end
    end
    t.line, t.soft, t.acc, t.glass = line, soft, acc, glass
    t.W, t.H = W, H
    return t
end

-- the track panel's row: a panel, its number column and its name window
local function tcp(t)
    t.frame(0, 3, W, H - 6, t.line, 3)
    t.box(2, 5, 6, H - 10, t.soft, 1)
end

-- each picture, by choice (1 = the first choice)
local DRAW = {}

-- Volume and pan as: Auto, Sliders, Knobs
DRAW.tcp_knobs = function(t, c)
    tcp(t)
    t.box(11, 7, 18, 6, t.glass, 1)
    if c == 2 or c == 1 then t.hslider(11, 19, 18, 0.7, t.line) else t.knob(17, 19, 4, t.line) end
    if c == 2 then t.hslider(33, 19, 18, 0.5, t.line) else t.knob(40, 19, 4, t.line) end
end

-- Pan and width as: Sliders, Knobs (on a strip)
DRAW.mcp_knobs = function(t, c)
    t.frame(14, 0, 28, H, t.line, 3)
    if c == 1 then
        t.hslider(17, 5, 22, 0.5, t.line)
        t.hslider(17, 11, 22, 0.8, t.line)
    else
        t.knob(22, 8, 4, t.line)
        t.knob(34, 8, 4, t.line)
    end
    t.meter(18, 16, 10)
    t.fader(32, 15, 11, t.line)
end

-- Mute and solo: Right (beside the name), Left, Far right
DRAW.ms = function(t, c)
    tcp(t)
    local function ms(x)
        t.box(x, 8, 6, 6, t.line, 1)
        t.box(x + 7, 8, 6, 6, t.acc, 1)
    end
    local name_x = c == 2 and 26 or 11
    t.box(name_x, 7, 14, 8, t.glass, 1)
    if c == 1 then ms(27) elseif c == 2 then ms(11) else ms(W - 16) end
    t.hslider(11, 20, 34, 0.6, t.line)
end

-- Keys: Above, Beside fader, Auto (a mixer strip on a plate)
DRAW.keys = function(t, c)
    t.frame(14, 0, 28, H, t.line, 3)
    local function key(x, y, dim) t.box(x, y, 5, 3, dim and t.soft or t.line, 1) end
    if c == 1 then
        for i = 0, 3 do key(17 + i * 6, 3) end
        t.meter(18, 10, 16)
        t.fader(32, 10, 16, t.line)
    elseif c == 2 then
        t.meter(17, 3, 23)
        t.fader(27, 3, 23, t.line)
        for i = 0, 4 do key(34, 3 + i * 5) end
    else
        -- Auto: above or beside, as the strip's height allows: both places, quiet
        for i = 0, 2 do key(17 + i * 6, 3, true) end
        t.meter(17, 9, 17)
        t.fader(27, 9, 17, t.line)
        for i = 0, 3 do key(34, 9 + i * 5, true) end
    end
end

-- Side column of the mixer's master: Off, Left, Right
DRAW.side = function(t, c)
    t.frame(4, 0, W - 8, H, t.line, 3)
    local function strip(x, w)
        t.meter(x + 2, 4, H - 8)
        t.fader(x + w - 5, 4, H - 8, t.line)
    end
    local function lists(x, w)
        for i = 0, 3 do t.box(x, 4 + i * 5, w, 3, i == 0 and t.acc or t.soft, 1) end
    end
    if c == 1 then
        lists(8, W - 16)
    elseif c == 2 then
        strip(6, 14)
        lists(24, W - 32)
    else
        lists(8, W - 32)
        strip(W - 22, 14)
    end
end

-- Lying meter: Long, Short (in a plate on the track panel)
DRAW.lying = function(t, c)
    tcp(t)
    t.box(11, 7, 16, 6, t.glass, 1)
    t.knob(34, 10, 3.5, t.line)
    t.knob(44, 10, 3.5, t.line)
    if c == 1 then t.hmeter(11, 18, W - 15) elseif c == 3 then t.hmeter(4, 18, W - 6) else t.hmeter(11, 18, 22) end
end

-- Track number: Colour (the column filled), Stripe
DRAW.number = function(t, c)
    t.frame(0, 3, W, H - 6, t.line, 3)
    if c == 1 then
        t.box(2, 5, 10, H - 10, t.acc, 1)
    else
        t.box(2, 5, 10, H - 10, t.soft, 1)
        t.box(10, 5, 2, H - 10, t.acc, 0)
    end
    t.box(15, 7, 18, 6, t.glass, 1)
    t.hslider(15, 19, 34, 0.6, t.line)
end

-- ---------------------------------------------------------------- from the theme's own images
-- (0.9.97) Rails, plate logos and the panels' styles: the theme's 200% images, read once from
-- the loaded theme's zip (all at once, so the zip is read one time) and kept

local THEME_IMAGES = { "tcpWoodWalnut", "tcpWoodTeak", "mcpWoodArmWalnut", "mcpWoodArmTeak",
    "transPlateLogoSilver", "transPlateDevilSilver", "transPlateAngelSilver", "transPlateMetalSilver", "transPlateQuickSilver",
    "transPlateLogoBlack", "transPlateDevilBlack", "transPlateAngelBlack", "transPlateMetalBlack", "transPlateQuickBlack" }

local function theme_image(name)
    local E = Pics.E
    local r, ctx = E.r, E.ctx
    local zip = E.zip_path and E.zip_path()
    if not zip then return nil end
    if Pics.zip ~= zip then
        Pics.zip, Pics.images = zip, {}
        E.Zip.hold(function()
            local root = E.Zip.root(zip)
            for _, n in ipairs(root and THEME_IMAGES or {}) do
                local data, method = E.Zip.read_entry(zip, root .. "/200/" .. n .. ".png")
                if data then data = E.unzip(data, method) end
                local ok, img = false, nil
                if data and data ~= "" then ok, img = pcall(r.ImGui_CreateImageFromMem, data) end
                if ok and img then
                    r.ImGui_Attach(ctx, img)
                    Pics.images[n] = img
                end
            end
        end)
    end
    return Pics.images[name]
end

-- the track panel's rail: Off, Walnut, Teak, Material (the number column on its left edge)
DRAW.rails = function(t, c)
    t.frame(0, 3, W, H - 6, t.line, 3)
    t.box(15, 7, 18, 6, t.glass, 1)
    t.hslider(15, 19, 34, 0.6, t.line)
    if c == 2 or c == 3 then
        -- a short piece of the lath, as long as it is wide x 2.2
        t.image(theme_image(c == 2 and "tcpWoodWalnut" or "tcpWoodTeak"), 1, 3, 11, H - 6, 0, 0, 1, 0.06)
    elseif c == 4 then
        -- a material of your own: a metal-grey lath with its bevel
        t.box(1, 3, 11, H - 6, t.soft, 2)
        t.box(1, 3, 2, H - 6, t.line, 1)
    else
        t.box(2, 5, 8, H - 10, t.soft, 1)
    end
end

-- the mixer's armrest: Off, Walnut, Teak, Material (along the strips' bottom)
DRAW.armrest = function(t, c)
    t.frame(14, 0, 28, H - 6, t.line, 3)
    t.meter(18, 4, 14)
    t.fader(32, 4, 14, t.line)
    if c == 2 or c == 3 then
        t.image(theme_image(c == 2 and "mcpWoodArmWalnut" or "mcpWoodArmTeak"), 4, H - 7, W - 8, 7, 0, 0, 0.25, 1)
    elseif c == 4 then
        t.box(4, H - 7, W - 8, 7, t.soft, 2)
        t.box(4, H - 7, W - 8, 2, t.line, 1)
    end
end

-- Plate logo: TK-S73, Red Devil, Blue Angel, Black Metal, Quicksilver, Own name (on the
-- transport's plate as chosen, Silver or Black)
local LOGOS = { "transPlateLogo", "transPlateDevil", "transPlateAngel", "transPlateMetal", "transPlateQuick" }
DRAW.logo = function(t, c)
    local E = Pics.E
    local silver = E.trans_silver and E.trans_silver()
    local img
    if LOGOS[c] then
        img = theme_image(LOGOS[c] .. (silver and "Silver" or "Black"))
    elseif E.own_logo then
        img = E.own_logo()
    end
    if img then
        -- the logo's own shape is 96 by 42: as large as fits
        local h = H
        local w = math.floor(h * 96 / 42 + 0.5)
        t.image(img, (W - w) / 2, 0, w, h)
    else
        t.box(4, 6, W - 8, H - 12, t.soft, 2)
    end
end

-- Style: Standard, Basic, Material: the part's own picture (as Fader cap and Record arm have),
-- the transport's drawn
DRAW.style = function(t, c, item)
    local E = Pics.E
    local part = item and item.part
    local key = ({ standard = "standard", basic = "basic", material = "silver" })[c]
    local img = part and key and E.part_image and E.part_image(part, key)
    if img then
        -- the part's picture is 60 by 44
        local w = math.floor(H * 60 / 44 + 0.5)
        t.image(img, (W - w) / 2, 0, w, H)
        return
    end
    -- the transport: its display window, keys, and on Material the plate's screws
    if c == "material" then
        t.box(0, 2, W, H - 4, t.soft, 3)
        for _, x in ipairs({ 3, W - 6 }) do t.box(x, 4, 3, 3, t.line, 1.5) t.box(x, H - 7, 3, 3, t.line, 1.5) end
    else
        t.frame(0, 2, W, H - 4, t.line, 3)
    end
    t.box(9, 7, 20, 14, t.glass, 2)
    t.box(12, 10, 10, 3, t.acc, 0)
    for i = 0, 2 do t.box(33 + i * 6, 11, 5, 6, t.line, 1) end
end

function Pics.has(name)
    return DRAW[name] ~= nil
end

-- a choice button with its picture over its name; the same size for the whole row
function Pics.button(name, label, choice, bw, active, item)
    local E = Pics.E
    local r, ctx = E.r, E.ctx
    local x, y = r.ImGui_GetCursorScreenPos(ctx)
    local bh = H + 30
    local clicked = r.ImGui_Button(ctx, "##pic" .. choice, bw, bh)
    local dl = r.ImGui_GetWindowDrawList(ctx)
    local px, py = x + (bw - W) / 2, y + 6
    DRAW[name](tools(dl, px, py, active), choice, item)
    local tw = r.ImGui_CalcTextSize(ctx, label)
    r.ImGui_DrawList_AddText(dl, x + (bw - tw) / 2, y + bh - 20,
        E.rgba(active and E.UI.ink or E.UI.text), label)
    return clicked
end

Pics.WIDTH = W + 20

return Pics
