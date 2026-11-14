-- @noindex
-- Your own name on the transport plate (Transport page, Plate logo: Own name). The build
-- ships the letters and icons as grey masks (dist/plate_font.bin, Bahnschrift Bold, as
-- TK-S73); this sets the two lines in it, shrinks them to fit the plate, engraves them in
-- the plate's colours (a light edge under the etching, as the generator's
-- render_plate_logo does) and writes the PNGs itself, at 100, 150 and 200%.
local Plate = {}

-- the plates' etching and its edge (tk_theme_gen.py, PLATES)
Plate.PLATES = {
    Black = { etch = { 0xc9, 0xcd, 0xd2 }, hi = { 0x10, 0x11, 0x13 } },
    Silver = { etch = { 0x1d, 0x1f, 0x22 }, hi = { 0xd6, 0xd9, 0xdc } },
}
Plate.ICONS = { "star", "heart", "note", "mic", "phones", "wave", "bolt", "crown", "rec", "play" }
Plate.W, Plate.H = 96, 42           -- the logo's place at 100%
local ROOM = 92                     -- the width the lines may take
local SMALL, BIG, GAP = 10.5, 22, 2.5

function Plate.load(path)
    local f = io.open(path, "rb")
    if not f then return nil, "plate_font.bin is missing" end
    local s = f:read("a")
    f:close()
    if s:sub(1, 4) ~= "TKPF" then return nil, "plate_font.bin is damaged" end
    local _, em, count, at = string.unpack("<BHH", s, 5)
    local font = { em = em, glyphs = {} }
    for _ = 1, count do
        local n
        n, at = string.unpack("<B", s, at)
        local name = s:sub(at, at + n - 1)
        at = at + n
        local x0, y0, w, h, adv
        x0, y0, w, h, adv, at = string.unpack("<hhHHH", s, at)
        font.glyphs[name] = { x0 = x0, y0 = y0, w = w, h = h, adv = adv / 16, mask = s:sub(at, at + w * h - 1) }
        at = at + w * h
    end
    return font
end

-- the glyphs of a line: characters, and icons written as [star]; what the font lacks is left out
function Plate.glyphs(font, text)
    local list, i = {}, 1
    text = text or ""
    while i <= #text do
        local icon = text:match("^%[(%a+)%]", i)
        if icon and font.glyphs["[" .. icon .. "]"] then
            list[#list + 1] = font.glyphs["[" .. icon .. "]"]
            i = i + #icon + 2
        else
            local ch = text:match("^[%z\1-\127\194-\244][\128-\191]*", i) or text:sub(i, i)
            local g = font.glyphs[ch] or font.glyphs[ch:upper()] or font.glyphs[ch:lower()]
            if g then list[#list + 1] = g end
            i = i + #ch
        end
    end
    return list
end

function Plate.width(font, list, size)
    local w = 0
    for _, g in ipairs(list) do w = w + g.adv end
    return w * size / font.em
end

-- sizes and places at 100%: each line as big as its own, smaller where it would not fit
function Plate.layout(font, top, name)
    local tl, nl = Plate.glyphs(font, top), Plate.glyphs(font, name)
    local sp, bp = SMALL, BIG
    while bp > 9 and Plate.width(font, nl, bp) > ROOM do bp = bp - 0.5 end
    while sp > 6 and #tl > 0 and Plate.width(font, tl, sp) > ROOM do sp = sp - 0.5 end
    local lines = {}
    if #tl > 0 then
        local y = 2 + (35 - (sp + GAP + bp)) / 2
        lines[1] = { list = tl, size = sp, y = y }
        lines[2] = { list = nl, size = bp, y = y + sp + GAP }
    else
        lines[1] = { list = nl, size = bp, y = 2 + (35 - bp) / 2 }
    end
    return lines
end

-- one glyph's mask into the coverage A (W x H), f times its size, its top left at ox, oy:
-- each pixel takes the share of the mask it covers
local function blit(A, W, H, g, ox, oy, f)
    if g.w == 0 then return end
    local function spans(o, n, limit)
        local out = {}
        local a, b = math.max(0, math.floor(o)), math.min(limit - 1, math.ceil(o + n * f) - 1)
        for d = a, b do
            local s0, s1 = (d - o) / f, (d + 1 - o) / f
            local list = {}
            for sx = math.max(0, math.floor(s0)), math.min(n - 1, math.ceil(s1) - 1) do
                local u = math.min(s1, sx + 1) - math.max(s0, sx)
                if u > 0 then list[#list + 1] = { sx, u * f } end
            end
            out[#out + 1] = { d, list }
        end
        return out
    end
    local cols, rows = spans(ox, g.w, W), spans(oy, g.h, H)
    local mask, gw = g.mask, g.w
    for _, row in ipairs(rows) do
        local dy, ry = row[1], row[2]
        for _, col in ipairs(cols) do
            local dx, rx = col[1], col[2]
            local sum = 0
            for _, r in ipairs(ry) do
                local base = r[1] * gw + 1
                for _, c in ipairs(rx) do
                    sum = sum + mask:byte(base + c[1]) * r[2] * c[2]
                end
            end
            if sum > 0 then
                local i = dy * W + dx + 1
                A[i] = math.min(1, A[i] + sum / 255)
            end
        end
    end
end

-- coverage of both lines at scale (1, 1.5, 2)
function Plate.coverage(font, top, name, scale)
    local W, H = math.floor(Plate.W * scale + 0.5), math.floor(Plate.H * scale + 0.5)
    local A = {}
    for i = 1, W * H do A[i] = 0 end
    for _, line in ipairs(Plate.layout(font, top, name)) do
        local f = line.size * scale / font.em
        local pen = 2 * scale
        for _, g in ipairs(line.list) do
            blit(A, W, H, g, pen + g.x0 * f, line.y * scale + g.y0 * f, f)
            pen = pen + g.adv * f
        end
    end
    return A, W, H
end

-- engraved: the etching, with its light (or dark) edge 0.8 px lower showing beneath it
function Plate.rgba(A, W, H, plate, scale)
    local etch, hi = plate.etch, plate.hi
    local d = 0.8 * scale
    local di, df = math.floor(d), d - math.floor(d)
    local out = {}
    for y = 0, H - 1 do
        for x = 0, W - 1 do
            local a = A[y * W + x + 1]
            local y1, y2 = y - di, y - di - 1
            local h1 = y1 >= 0 and A[y1 * W + x + 1] or 0
            local h2 = y2 >= 0 and A[y2 * W + x + 1] or 0
            local ah = h1 * (1 - df) + h2 * df
            local hb = ah * (1 - a)
            local alpha = a + hb
            if alpha <= 0 then
                out[#out + 1] = "\0\0\0\0"
            else
                local r = (etch[1] * a + hi[1] * hb) / alpha
                local g = (etch[2] * a + hi[2] * hb) / alpha
                local b = (etch[3] * a + hi[3] * hb) / alpha
                out[#out + 1] = string.char(math.floor(r + 0.5), math.floor(g + 0.5), math.floor(b + 0.5),
                    math.floor(math.min(1, alpha) * 255 + 0.5))
            end
        end
    end
    return table.concat(out)
end

-- a PNG of RGBA rows, without compression (zlib's stored blocks): crc32 as TK_Theme_Zip's
function Plate.png(W, H, rgba, crc32)
    local rows = {}
    for y = 0, H - 1 do rows[#rows + 1] = "\0" .. rgba:sub(y * W * 4 + 1, (y + 1) * W * 4) end
    local raw = table.concat(rows)
    local a, b = 1, 0
    for i = 1, #raw do
        a = (a + raw:byte(i)) % 65521
        b = (b + a) % 65521
    end
    local z = { "\120\1" }
    local at = 1
    repeat
        local block = raw:sub(at, at + 65534)
        at = at + #block
        z[#z + 1] = string.pack("<BI2I2", at > #raw and 1 or 0, #block, (~#block) & 0xFFFF) .. block
    until at > #raw
    z[#z + 1] = string.pack(">I4", (b << 16) | a)
    local function chunk(kind, data)
        return string.pack(">I4", #data) .. kind .. data .. string.pack(">I4", crc32(kind .. data))
    end
    return "\137PNG\r\n\26\n" .. chunk("IHDR", string.pack(">I4I4BBBBB", W, H, 8, 6, 0, 0, 0))
        .. chunk("IDAT", table.concat(z)) .. chunk("IEND", "")
end

-- the theme's images for both plates at every scale: { [name in the theme folder] = png }
function Plate.images(font, top, name, crc32)
    local files = {}
    for _, sc in ipairs({ { "", 1 }, { "150/", 1.5 }, { "200/", 2 } }) do
        local A, W, H = Plate.coverage(font, top, name, sc[2])
        for plate, col in pairs(Plate.PLATES) do
            files[sc[1] .. "transPlateOwn" .. plate .. ".png"] = Plate.png(W, H, Plate.rgba(A, W, H, col, sc[2]), crc32)
        end
    end
    return files
end

return Plate
