-- @noindex
-- TK Material Forge (proof of concept): your own finish on the track panel and mixer plates.
-- Nothing of it ships. The plates in the theme are the work material: their pixels are read
-- from the theme itself and coloured anew by their lightness, so brushing, grooves and screws
-- stay as drawn. Corrosion fitting the finish (rust, verdigris, tarnish, oxide) is drawn as
-- three overlays per plate, picked per track as the wear is. The settings window shows a
-- preview; the theme is only written on Apply.
local Forge = {}
local byte, char, concat, unpack = string.byte, string.char, table.concat, table.unpack

-- ---------------------------------------------------------------- the finishes
-- base: the plate the finish is made from (its value for tkTcpPlate / tkMcpPlate);
-- ramp: dark, mid and light colour along the plate's lightness; corr: what corrosion is;
-- bare: the wear's colour, the bare metal under a coloured finish (Silver and Black keep
-- the wear of their own plate)
Forge.FINISHES = {
    { name = "Silver", base = 1, ramp = { { 16, 17, 19 }, { 158, 161, 165 }, { 236, 238, 240 } }, corr = "rust" },
    { name = "Gunmetal", base = 1, ramp = { { 16, 18, 22 }, { 78, 84, 92 }, { 176, 182, 190 } }, corr = "rust", bare = { 196, 202, 210 }, bare_a = 0.9 },
    { name = "Titanium", base = 1, ramp = { { 30, 31, 34 }, { 128, 126, 122 }, { 216, 215, 212 } }, corr = "heat", bare = { 228, 228, 230 }, bare_a = 0.9 },
    { name = "Copper", base = 1, ramp = { { 58, 22, 10 }, { 178, 98, 58 }, { 255, 214, 176 } }, corr = "verdigris", bare = { 255, 206, 168 }, bare_a = 0.85 },
    { name = "Brass", base = 1, ramp = { { 62, 44, 12 }, { 182, 146, 66 }, { 255, 238, 176 } }, corr = "tarnish", bare = { 255, 240, 186 }, bare_a = 0.85 },
    { name = "Bronze", base = 1, ramp = { { 52, 30, 14 }, { 140, 92, 52 }, { 232, 190, 140 } }, corr = "verdigris", bare = { 240, 202, 152 }, bare_a = 0.85 },
    { name = "Anodized", base = 1, ramp = { { 8, 22, 58 }, { 42, 92, 168 }, { 156, 200, 244 } }, corr = "oxide", bare = { 214, 220, 228 }, bare_a = 1.0 },
    { name = "Anodized red", base = 1, ramp = { { 60, 6, 10 }, { 176, 30, 40 }, { 250, 150, 150 } }, corr = "oxide", bare = { 214, 220, 228 }, bare_a = 1.0 },
    -- made from the Black plate: black anodizing, its scratches bare aluminium
    { name = "Anodized black", base = 2, ramp = { { 6, 6, 8 }, { 34, 34, 38 }, { 120, 120, 128 } }, corr = "oxide", bare = { 200, 204, 210 }, bare_a = 1.0 },
    -- cardboard: made from the cardboard work plate (tcpPlateCardboard, ...), not from metal.
    -- Its three numbers mean other things: gloss is how creased, contrast how strong the
    -- fibres, corrosion how stained (labels); it has Silver's knobs and dark labels (base 1)
    { name = "Kraft", base = 1, work = "Cardboard", group = "Cardboard", paper = true, nogloss = true, creases = true, fastens = true, wear_style = "paper", ramp = { { 98, 76, 52 }, { 178, 138, 94 }, { 216, 172, 122 } }, corr = "stains", bare = { 246, 232, 206 }, bare_a = 1.0,
      labels = { gloss = "Creases", contrast = "Fibre" }, defaults = { gloss = 0 } },
    { name = "Grey board", base = 1, work = "Cardboard", group = "Cardboard", paper = true, nogloss = true, creases = true, fastens = true, wear_style = "paper", ramp = { { 84, 83, 80 }, { 150, 148, 142 }, { 192, 190, 184 } }, corr = "stains", bare = { 236, 234, 228 }, bare_a = 1.0,
      labels = { gloss = "Creases", contrast = "Fibre" }, defaults = { gloss = 0 } },
    { name = "White board", base = 1, work = "Cardboard", group = "Cardboard", paper = true, nogloss = true, creases = true, fastens = true, wear_style = "paper", ramp = { { 150, 148, 140 }, { 226, 222, 212 }, { 250, 248, 240 } }, corr = "stains", bare = { 176, 164, 140 }, bare_a = 0.9,
      labels = { gloss = "Creases", contrast = "Fibre" }, defaults = { gloss = 0 } },
    -- wood: made from the wood work plate. Teak and Walnut in the rails' colours (tk_theme_gen.py
    -- WOODS), their dark and light pulled further out as the plate's grain is fine. Varnish has
    -- a gloss; its layer is worn varnish and glass rings. Walnut is dark: Black's knobs, light labels
    { name = "Teak", base = 1, work = "Wood", group = "Wood", fastens = true, ramp = { { 43, 20, 7 }, { 140, 94, 54 }, { 237, 169, 102 } }, corr = "varnish", bare = { 226, 182, 132 }, bare_a = 0.85,
      labels = { contrast = "Grain" } },
    { name = "Walnut", base = 2, work = "Wood", group = "Wood", fastens = true, ramp = { { 8, 4, 2 }, { 94, 64, 41 }, { 191, 134, 87 } }, corr = "varnish", bare = { 196, 158, 116 }, bare_a = 0.8,
      labels = { contrast = "Grain" } },
    -- cork: made from the cork work plate; no gloss; its layer is dents and crumbs, its wear
    -- crumbling edges as board's
    { name = "Cork", base = 1, work = "Cork", group = "Cork", nogloss = true, fastens = true, wear_style = "paper", ramp = { { 122, 91, 60 }, { 196, 146, 96 }, { 255, 200, 132 } }, corr = "dents", bare = { 238, 210, 176 }, bare_a = 0.85,
      labels = { gloss = false, contrast = "Grain" } },
    { name = "Dark cork", base = 2, work = "Cork", group = "Cork", nogloss = true, fastens = true, wear_style = "paper", ramp = { { 6, 2, 1 }, { 105, 71, 44 }, { 204, 144, 92 } }, corr = "dents", bare = { 190, 150, 110 }, bare_a = 0.8,
      labels = { gloss = false, contrast = "Grain" } },
    { name = "Black", base = 2, ramp = { { 8, 9, 10 }, { 44, 46, 49 }, { 150, 154, 160 } }, corr = "rust" },
    -- Plain: no image at all; REAPER fills the plate in one colour, fixed or the track's
    { name = "Plain", base = 1, group = "Plain", plain = true, ramp = { { 0, 0, 0 }, { 128, 128, 128 }, { 255, 255, 255 } }, corr = "rust" },
}
Forge.CORR_LABEL = { rust = "Rust", verdigris = "Verdigris", tarnish = "Tarnish", oxide = "Oxide", heat = "Heat tint", stains = "Stains", varnish = "Worn varnish", dents = "Dents" }
Forge.GROUPS = { "Metal", "Cardboard", "Wood", "Cork", "Plain" }

-- Plain's Style: light colours on Silver (dark text on it), dark ones and the track colour on Black
function Forge.base_of(m)
    local fin = Forge.finish(m.finish)
    if not fin.plain then return fin.base end
    if (m.track or 0) > 0 then return 2 end
    local c = m.colour or 0xA0282C
    local l = ((c >> 16) & 255) * 0.299 + ((c >> 8) & 255) * 0.587 + (c & 255) * 0.114
    return l >= 140 and 1 or 2
end

-- the work plate a finish is made from: Silver, Black or Cardboard
function Forge.source(fin) return fin.work or Forge.BASE_NAME[fin.base] end

-- whether a material has a layer over its plate: corrosion, or for cardboard stains or creases
function Forge.layered(m)
    local fin = Forge.finish(m.finish)
    if fin.plain then return false end
    return m.corrosion > 0 or (fin.creases and m.gloss > 0) or false
end

-- the gloss a plate is drawn with: cardboard has none (its gloss is the creases, a layer)
local function plate_gloss(fin, m) return fin.nogloss and 0.4 or m.gloss end
function Forge.finish(name)
    for _, f in ipairs(Forge.FINISHES) do if f.name == name then return f end end
    return Forge.FINISHES[1]
end

Forge.SCALES = { { "", 1 }, { "150/", 1.5 }, { "200/", 2 } }
Forge.BASE_NAME = { [1] = "Silver", [2] = "Black" }
-- the overlays: as the wear's (TK_Theme_Patina), the same sizes and fixed borders
-- sx, sy: how far the middle stretches in the theme, so the corrosion is drawn squeezed
-- there and comes out round; values: the Style parameter's value for a base (1 Silver,
-- 2 Black), the transport's being the other way round; variants: corrosion patterns
Forge.KINDS = {
    tcp = { w = 300, h = 96, fix = { 30, 22, 30, 22 }, plate = "tcpPlate", screws = { 8.5, 8.5 }, sx = 2.2, sy = 1, values = { 1, 2 } },
    mcp = { w = 100, h = 320, fix = { 0, 40, 0, 40 }, plate = "mcpPlate", screws = { 8.5, 8.5 }, sx = 1, sy = 2.2, values = { 1, 2 } },
    -- the transport: one plate, no screws on it, stretched far across
    trans = { w = 480, h = 60, fix = { 30, 3, 30, 3 }, plate = "transPlate", sx = 4, sy = 1, values = { 2, 1 }, variants = 1 },
}
Forge.VERSION = 2             -- goes into the key: a new drawing draws everything again (2: packed PNGs)
-- corrosion patterns per plate, picked by the track's number mod 5 (tk_theme_gen.py
-- FORGE_RUST_VARIANTS): against the wear's three, the two repeat only every 15 tracks
Forge.RUST_VARIANTS = 5

-- ---------------------------------------------------------------- inflate (PNG reading)
local LBASE = { [0] = 3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258 }
local LEXT = { [0] = 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0 }
local DBASE = { [0] = 1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073,
    4097, 6145, 8193, 12289, 16385, 24577 }
local DEXT = { [0] = 0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13 }
local CL_ORDER = { 16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15 }

-- a lookup table for a code: index the next `max` bits, get symbol << 4 | length
local function huff(lens, n)
    local max = 0
    for i = 0, n - 1 do if (lens[i] or 0) > max then max = lens[i] end end
    local count, nextc = {}, {}
    for b = 0, max do count[b] = 0 end
    for i = 0, n - 1 do local l = lens[i] or 0 if l > 0 then count[l] = count[l] + 1 end end
    -- canonical codes as RFC 1951 3.2.2
    local code = 0
    count[0] = 0
    for b = 1, max do
        code = (code + count[b - 1]) << 1
        nextc[b] = code
    end
    local T, size = {}, 1 << max
    for sym = 0, n - 1 do
        local l = lens[sym] or 0
        if l > 0 then
            local c = nextc[l]
            nextc[l] = c + 1
            local rev = 0
            for _ = 1, l do rev = (rev << 1) | (c & 1) c = c >> 1 end
            local e = (sym << 4) | l
            for k = rev, size - 1, 1 << l do T[k] = e end
        end
    end
    return T, max
end

local FIXED_L, FIXED_LM, FIXED_D, FIXED_DM
do
    local l = {}
    for i = 0, 143 do l[i] = 8 end
    for i = 144, 255 do l[i] = 9 end
    for i = 256, 279 do l[i] = 7 end
    for i = 280, 287 do l[i] = 8 end
    FIXED_L, FIXED_LM = huff(l, 288)
    local d = {}
    for i = 0, 29 do d[i] = 5 end
    FIXED_D, FIXED_DM = huff(d, 30)
end

-- deflated data from position p to an array of byte values
local function inflate(s, p)
    local acc, nb = 0, 0
    local o, n = {}, 0
    local final = 0
    repeat
        while nb < 3 do acc = acc | ((byte(s, p) or 0) << nb) p = p + 1 nb = nb + 8 end
        final = acc & 1
        local kind = (acc >> 1) & 3
        acc, nb = acc >> 3, nb - 3
        if kind == 0 then
            local drop = nb & 7
            acc, nb = acc >> drop, nb - drop
            p = p - (nb >> 3)
            acc, nb = 0, 0
            local len = byte(s, p) | (byte(s, p + 1) << 8)
            p = p + 4
            for i = 0, len - 1 do n = n + 1 o[n] = byte(s, p + i) end
            p = p + len
        else
            local LT, lmax, DT, dmax
            if kind == 1 then
                LT, lmax, DT, dmax = FIXED_L, FIXED_LM, FIXED_D, FIXED_DM
            else
                while nb < 14 do acc = acc | ((byte(s, p) or 0) << nb) p = p + 1 nb = nb + 8 end
                local hlit, hdist, hclen = (acc & 31) + 257, ((acc >> 5) & 31) + 1, ((acc >> 10) & 15) + 4
                acc, nb = acc >> 14, nb - 14
                local cl = {}
                for i = 1, hclen do
                    while nb < 3 do acc = acc | ((byte(s, p) or 0) << nb) p = p + 1 nb = nb + 8 end
                    cl[CL_ORDER[i]] = acc & 7
                    acc, nb = acc >> 3, nb - 3
                end
                local CT, cmax = huff(cl, 19)
                local lens, i = {}, 0
                while i < hlit + hdist do
                    while nb < cmax + 7 do acc = acc | ((byte(s, p) or 0) << nb) p = p + 1 nb = nb + 8 end
                    local e = CT[acc & ((1 << cmax) - 1)]
                    local l = e & 15
                    acc, nb = acc >> l, nb - l
                    local sym = e >> 4
                    if sym < 16 then
                        lens[i] = sym i = i + 1
                    elseif sym == 16 then
                        local rep = 3 + (acc & 3) acc, nb = acc >> 2, nb - 2
                        local prev = lens[i - 1]
                        for _ = 1, rep do lens[i] = prev i = i + 1 end
                    elseif sym == 17 then
                        local rep = 3 + (acc & 7) acc, nb = acc >> 3, nb - 3
                        for _ = 1, rep do lens[i] = 0 i = i + 1 end
                    else
                        local rep = 11 + (acc & 127) acc, nb = acc >> 7, nb - 7
                        for _ = 1, rep do lens[i] = 0 i = i + 1 end
                    end
                end
                local ll, dl = {}, {}
                for k = 0, hlit - 1 do ll[k] = lens[k] end
                for k = 0, hdist - 1 do dl[k] = lens[hlit + k] end
                LT, lmax = huff(ll, hlit)
                DT, dmax = huff(dl, hdist)
            end
            local lmask, dmask = (1 << lmax) - 1, (1 << dmax) - 1
            while true do
                while nb < lmax do acc = acc | ((byte(s, p) or 0) << nb) p = p + 1 nb = nb + 8 end
                local e = LT[acc & lmask]
                local l = e & 15
                acc, nb = acc >> l, nb - l
                local sym = e >> 4
                if sym < 256 then
                    n = n + 1
                    o[n] = sym
                elseif sym == 256 then
                    break
                else
                    sym = sym - 257
                    local len, eb = LBASE[sym], LEXT[sym]
                    while nb < eb + dmax + 13 do acc = acc | ((byte(s, p) or 0) << nb) p = p + 1 nb = nb + 8 end
                    if eb > 0 then
                        len = len + (acc & ((1 << eb) - 1))
                        acc, nb = acc >> eb, nb - eb
                    end
                    e = DT[acc & dmask]
                    l = e & 15
                    acc, nb = acc >> l, nb - l
                    local ds = e >> 4
                    local dist, de = DBASE[ds], DEXT[ds]
                    if de > 0 then
                        dist = dist + (acc & ((1 << de) - 1))
                        acc, nb = acc >> de, nb - de
                    end
                    local from = n - dist
                    for k = 1, len do o[n + k] = o[from + k] end
                    n = n + len
                end
            end
        end
    until final == 1
    return o, n
end

-- a zip entry's bytes (Zip.read_entry) as the file: stored as it is, deflated unpacked
function Forge.unzip(data, method)
    if method == 0 then return data end
    if method ~= 8 then return nil end
    local o, n = inflate(data, 1)
    local parts = {}
    for i = 1, n, 4096 do parts[#parts + 1] = char(unpack(o, i, math.min(n, i + 4095))) end
    return concat(parts)
end

-- a PNG (8-bit RGBA, not interlaced) to W, H and its pixels as one string, row after row
function Forge.decode(png)
    if png:sub(1, 8) ~= "\137PNG\r\n\26\n" then return nil, "not a PNG" end
    local W, H, depth, ctype, inter, _
    local idat, p = {}, 9
    while p < #png do
        local len = string.unpack(">I4", png, p)
        local kind = png:sub(p + 4, p + 7)
        if kind == "IHDR" then
            W, H, depth, ctype, _, _, inter = string.unpack(">I4I4BBBBB", png, p + 8)
        elseif kind == "IDAT" then
            idat[#idat + 1] = png:sub(p + 8, p + 7 + len)
        elseif kind == "IEND" then
            break
        end
        p = p + 12 + len
    end
    if depth ~= 8 or ctype ~= 6 or inter ~= 0 then return nil, "not 8-bit RGBA" end
    local o = inflate(concat(idat), 3)          -- after zlib's 2-byte header
    -- undo the filters, in place; each row has its filter byte in front
    local stride, bpp = W * 4, 4
    local rows = {}
    for y = 0, H - 1 do
        local at = y * (stride + 1) + 1          -- the filter byte
        local ft = o[at]
        if ft == 1 then
            for i = at + 1 + bpp, at + stride do o[i] = (o[i] + o[i - bpp]) & 255 end
        elseif ft == 2 then
            if y > 0 then for i = at + 1, at + stride do o[i] = (o[i] + o[i - stride - 1]) & 255 end end
        elseif ft == 3 then
            for i = at + 1, at + stride do
                local left = i - bpp > at and o[i - bpp] or 0
                local above = y > 0 and o[i - stride - 1] or 0
                o[i] = (o[i] + ((left + above) >> 1)) & 255
            end
        elseif ft == 4 then
            for i = at + 1, at + stride do
                local a = i - bpp > at and o[i - bpp] or 0
                local b = y > 0 and o[i - stride - 1] or 0
                local c = (y > 0 and i - bpp > at) and o[i - stride - 1 - bpp] or 0
                local pa, pb, pc = math.abs(b - c), math.abs(a - c), math.abs(a + b - 2 * c)
                local pr = (pa <= pb and pa <= pc) and a or (pb <= pc and b or c)
                o[i] = (o[i] + pr) & 255
            end
        end
        local parts = {}
        for i = at + 1, at + stride, 4096 do
            parts[#parts + 1] = char(unpack(o, i, math.min(at + stride, i + 4095)))
        end
        rows[y + 1] = concat(parts)
    end
    return W, H, concat(rows)
end

-- ---------------------------------------------------------------- PNG writing (stored)
local function adler32(s)
    local a, b = 1, 0
    for i = 1, #s, 4096 do
        local t = { byte(s, i, math.min(#s, i + 4095)) }
        for j = 1, #t do a = a + t[j] b = b + a end
        a, b = a % 65521, b % 65521
    end
    return (b << 16) | a
end

-- a stored PNG (no packing): for the previews in the window, which are made often and never kept
function Forge.png(W, H, rgba, crc32)
    local rows = {}
    for y = 0, H - 1 do rows[#rows + 1] = "\0" .. rgba:sub(y * W * 4 + 1, (y + 1) * W * 4) end
    local raw = concat(rows)
    local z, i, n = { "\120\1" }, 1, #raw
    repeat
        local len = math.min(65535, n - i + 1)
        z[#z + 1] = string.pack("<BI2I2", i + len > n and 1 or 0, len, len ~ 0xFFFF)
        z[#z + 1] = raw:sub(i, i + len - 1)
        i = i + len
    until i > n
    z[#z + 1] = string.pack(">I4", adler32(raw))
    local function chunk(kind, data)
        return string.pack(">I4", #data) .. kind .. data .. string.pack(">I4", crc32(kind .. data))
    end
    return "\137PNG\r\n\26\n" .. chunk("IHDR", string.pack(">I4I4BBBBB", W, H, 8, 6, 0, 0, 0))
        .. chunk("IDAT", concat(z)) .. chunk("IEND", "")
end

-- ---------------------------------------------------------------- PNG writing (packed)
-- A plate is brushed metal: along a row, a pixel is mostly its left neighbour give or take a
-- little. So each row is stored as the difference to the pixel on its left (PNG filter 1,
-- "Sub"): small numbers, many of them the same, and runs of zero. Those are packed with
-- Huffman codes made for this image, runs as matches one byte back. About a tenth of the
-- stored size (measured on the copper plate: 10%), quick enough in Lua.

-- code lengths (at most maxbits) for symbol counts freq[0..n-1]: Huffman's, and while the
-- longest is too long, again with the rare counts made a little less rare
local function code_lengths(freq, n, maxbits)
    local lens = {}
    for i = 0, n - 1 do lens[i] = 0 end
    local used = {}
    for i = 0, n - 1 do if (freq[i] or 0) > 0 then used[#used + 1] = i end end
    if #used == 0 then return lens end
    if #used == 1 then lens[used[1]] = 1 return lens end
    local floor = 0
    while true do
        -- two queues: the leaves sorted by weight, the merged nodes in the order made
        local leaves = {}
        for _, s in ipairs(used) do leaves[#leaves + 1] = { w = math.max(freq[s], floor), s = s } end
        table.sort(leaves, function(a, b) return a.w < b.w or (a.w == b.w and a.s < b.s) end)
        local nodes, li, ni = {}, 1, 1
        local function take()
            local a, b = leaves[li], nodes[ni]
            if a and (not b or a.w <= b.w) then li = li + 1 return a end
            ni = ni + 1
            return b
        end
        for _ = 1, #leaves - 1 do
            local x, y = take(), take()
            nodes[#nodes + 1] = { w = x.w + y.w, l = x, r = y }
        end
        local deepest = 0
        local function walk(node, d)
            if node.s then
                lens[node.s] = d
                if d > deepest then deepest = d end
            else
                walk(node.l, d + 1)
                walk(node.r, d + 1)
            end
        end
        walk(nodes[#nodes], 0)
        if deepest <= maxbits then return lens end
        floor = math.max(1, floor * 2)
        for _, s in ipairs(used) do lens[s] = 0 end
    end
end

-- canonical codes for lens[0..n-1], bit-reversed as deflate sends them
local function codes_for(lens, n)
    local count, nextc, max = {}, {}, 0
    for i = 0, n - 1 do if lens[i] > max then max = lens[i] end end
    for b = 0, max do count[b] = 0 end
    for i = 0, n - 1 do if lens[i] > 0 then count[lens[i]] = count[lens[i]] + 1 end end
    local code = 0
    count[0] = 0
    for b = 1, max do
        code = (code + count[b - 1]) << 1
        nextc[b] = code
    end
    local codes = {}
    for s = 0, n - 1 do
        local l = lens[s]
        if l > 0 then
            local c, rev = nextc[l], 0
            nextc[l] = c + 1
            for _ = 1, l do rev = (rev << 1) | (c & 1) c = c >> 1 end
            codes[s] = rev
        end
    end
    return codes
end

local LEN_SYM, LEN_XB, LEN_XV = {}, {}, {}     -- run length 3..258 -> symbol, extra bits, value
for i = 0, 28 do
    for n = LBASE[i], math.min(258, LBASE[i] + (1 << LEXT[i]) - 1) do
        if not LEN_SYM[n] then LEN_SYM[n], LEN_XB[n], LEN_XV[n] = 257 + i, LEXT[i], n - LBASE[i] end
    end
end
LEN_SYM[258], LEN_XB[258], LEN_XV[258] = 285, 0, 0

function Forge.png_packed(W, H, rgba, crc32)
    -- the rows, each a filter byte (1) and its differences, as numbers; adler-32 on the way
    local d, n = {}, 0
    local stride = W * 4
    for y = 0, H - 1 do
        local row = { byte(rgba, y * stride + 1, (y + 1) * stride) }
        n = n + 1
        d[n] = 1
        for k = 1, 4 do n = n + 1 d[n] = row[k] end
        for k = 5, stride do n = n + 1 d[n] = (row[k] - row[k - 4]) & 255 end
    end
    local a, b = 1, 0
    for i = 1, n, 4096 do
        for j = i, math.min(n, i + 4095) do a = a + d[j] b = b + a end
        a, b = a % 65521, b % 65521
    end
    -- tokens: a byte, or (as -length) a run of the byte before; counted on the way
    local tok, tn = {}, 0
    local lfreq = {}
    for s = 0, 285 do lfreq[s] = 0 end
    local i = 1
    while i <= n do
        local c = d[i]
        tn = tn + 1
        tok[tn] = c
        lfreq[c] = lfreq[c] + 1
        local j = i + 1
        while j <= n and d[j] == c and j - i <= 258 * 64 do j = j + 1 end
        local rest = j - i - 1
        while rest >= 3 do
            local len = rest > 258 and 258 or rest
            if rest - len > 0 and rest - len < 3 then len = rest - 3 end
            tn = tn + 1
            tok[tn] = -len
            lfreq[LEN_SYM[len]] = lfreq[LEN_SYM[len]] + 1
            rest = rest - len
        end
        for _ = 1, rest do
            tn = tn + 1
            tok[tn] = c
            lfreq[c] = lfreq[c] + 1
        end
        i = j
    end
    lfreq[256] = 1
    local llens = code_lengths(lfreq, 286, 15)
    local lcodes = codes_for(llens, 286)
    local dlens = { [0] = 1 }                -- one distance: 1 (code 0, one bit)
    -- the code lengths themselves, run-length coded (16 repeat, 17/18 zeros)
    local hlit = 286
    while hlit > 257 and llens[hlit - 1] == 0 do hlit = hlit - 1 end
    local all = {}
    for s = 0, hlit - 1 do all[#all + 1] = llens[s] end
    all[#all + 1] = dlens[0]
    local cl, cfreq = {}, {}
    for s = 0, 18 do cfreq[s] = 0 end
    local k = 1
    while k <= #all do
        local v, run = all[k], 1
        while k + run <= #all and all[k + run] == v do run = run + 1 end
        if v == 0 and run >= 3 then
            local m = math.min(run, 138)
            if m >= 11 then cl[#cl + 1] = { 18, m - 11 } cfreq[18] = cfreq[18] + 1
            else cl[#cl + 1] = { 17, m - 3 } cfreq[17] = cfreq[17] + 1 end
            k = k + m
        elseif v ~= 0 and run >= 4 then
            cl[#cl + 1] = { v } cfreq[v] = cfreq[v] + 1
            local m = math.min(run - 1, 6)
            cl[#cl + 1] = { 16, m - 3 } cfreq[16] = cfreq[16] + 1
            k = k + 1 + m
        else
            cl[#cl + 1] = { v } cfreq[v] = cfreq[v] + 1
            k = k + 1
        end
    end
    local clens = code_lengths(cfreq, 19, 7)
    local ccodes = codes_for(clens, 19)
    local hclen = 19
    while hclen > 4 and clens[CL_ORDER[hclen]] == 0 do hclen = hclen - 1 end
    -- the bits
    local out, on, acc, nb = {}, 0, 0, 0
    local function put(v, bits)
        acc = acc | (v << nb)
        nb = nb + bits
        while nb >= 8 do
            on = on + 1
            out[on] = acc & 255
            acc = acc >> 8
            nb = nb - 8
        end
    end
    put(1, 1)                                -- the last block
    put(2, 2)                                -- dynamic codes
    put(hlit - 257, 5)
    put(0, 5)                                -- one distance code
    put(hclen - 4, 4)
    for q = 1, hclen do put(clens[CL_ORDER[q]], 3) end
    for _, e in ipairs(cl) do
        put(ccodes[e[1]], clens[e[1]])
        if e[1] == 16 then put(e[2], 2) elseif e[1] == 17 then put(e[2], 3) elseif e[1] == 18 then put(e[2], 7) end
    end
    -- the data, the bit writer written out: this loop runs once per byte of the image
    for q = 1, tn do
        local v = tok[q]
        local code, bits
        if v >= 0 then
            code, bits = lcodes[v], llens[v]
        else
            local len = -v
            local sym = LEN_SYM[len]
            -- the length's code, its extra bits, then distance 1 (code 0, one bit)
            code, bits = lcodes[sym], llens[sym]
            local xb = LEN_XB[len]
            if xb > 0 then
                code = code | (LEN_XV[len] << bits)
                bits = bits + xb
            end
            bits = bits + 1
        end
        acc = acc | (code << nb)
        nb = nb + bits
        while nb >= 8 do
            on = on + 1
            out[on] = acc & 255
            acc = acc >> 8
            nb = nb - 8
        end
    end
    put(lcodes[256], llens[256])
    if nb > 0 then on = on + 1 out[on] = acc & 255 end
    local parts = { "\120\1" }
    for q = 1, on, 4096 do parts[#parts + 1] = char(unpack(out, q, math.min(on, q + 4095))) end
    parts[#parts + 1] = string.pack(">I4", (b << 16) | a)
    local idat = concat(parts)
    local function chunk(kind, data)
        return string.pack(">I4", #data) .. kind .. data .. string.pack(">I4", crc32(kind .. data))
    end
    return "\137PNG\r\n\26\n" .. chunk("IHDR", string.pack(">I4I4BBBBB", W, H, 8, 6, 0, 0, 0))
        .. chunk("IDAT", idat) .. chunk("IEND", "")
end

-- ---------------------------------------------------------------- the finish on a plate
local function clamp(v) return v < 0 and 0 or v > 255 and 255 or math.floor(v + 0.5) end

-- the plate's own lightness in the middle: where the ramp's mid colour goes
function Forge.median(W, H, px)
    local hist, n = {}, 0
    for i = 0, 255 do hist[i] = 0 end
    for y = math.floor(H * 0.25), math.floor(H * 0.75), 3 do
        for x = math.floor(W * 0.2), math.floor(W * 0.8), 3 do
            local at = (y * W + x) * 4 + 1
            local r, g, b = byte(px, at, at + 2)
            local L = (r * 77 + g * 150 + b * 29) >> 8
            hist[L] = hist[L] + 1
            n = n + 1
        end
    end
    local half, sum = n / 2, 0
    for i = 0, 255 do
        sum = sum + hist[i]
        if sum >= half then return i end
    end
    return 128
end

-- 256 lightness values to the finish's colours: contrast spreads them round the middle,
-- gloss lifts the highlights and deepens the shadows
function Forge.lut(fin, mid, gloss, contrast)
    local d, m, l = fin.ramp[1], fin.ramp[2], fin.ramp[3]
    local k = 0.4 + 1.2 * contrast
    local out = {}
    for L = 0, 255 do
        local v = mid + (L - mid) * k
        local t
        if v <= mid then t = -(1 - math.max(0, v) / math.max(1, mid)) else t = (math.min(255, v) - mid) / math.max(1, 255 - mid) end
        -- gloss: an S on each side, stronger with more gloss
        local g = (gloss - 0.4) * 1.2
        local a = math.abs(t)
        a = math.max(0, math.min(1, a + g * a * (1 - a) * 1.6))
        local c
        if t < 0 then
            c = { m[1] + (d[1] - m[1]) * a, m[2] + (d[2] - m[2]) * a, m[3] + (d[3] - m[3]) * a }
        else
            c = { m[1] + (l[1] - m[1]) * a, m[2] + (l[2] - m[2]) * a, m[3] + (l[3] - m[3]) * a }
        end
        out[L] = char(clamp(c[1]), clamp(c[2]), clamp(c[3]))
    end
    return out
end

-- the plate's pixels in the finish. Transparent pixels and the pink markers stay; so do the
-- screws (steel on every finish), found by where they are: 8.5 in from each corner
function Forge.recolour(W, H, px, lut, s, fixed_screws)
    local out = {}
    local sr = (4.6 + 1.2) * s
    local sc = 8.5 * s
    local centres = { { sc, sc }, { W - sc, sc }, { sc, H - sc }, { W - sc, H - sc } }
    local box = math.ceil(sr + sc + 1)
    local solid = {}                          -- the common case, opaque: one string per lightness
    for L = 0, 255 do solid[L] = lut[L] .. "\255" end
    for y = 0, H - 1 do
        local base = y * W
        local near_y = y < box or y >= H - box
        for x = 0, W - 1 do
            local at = (base + x) * 4 + 1
            local r, g, b, a = byte(px, at, at + 3)
            local keep = a < 250 or (r == 255 and g == 0 and b == 255)
            if not keep and fixed_screws and near_y and (x < box or x >= W - box) then
                for _, c in ipairs(centres) do
                    local dx, dy = x + 0.5 - c[1], y + 0.5 - c[2]
                    if dx * dx + dy * dy < sr * sr then keep = true break end
                end
            end
            if keep then
                out[base + x + 1] = px:sub(at, at + 3)
            elseif a == 255 then
                out[base + x + 1] = solid[(r * 77 + g * 150 + b * 29) >> 8]
            else
                out[base + x + 1] = lut[(r * 77 + g * 150 + b * 29) >> 8] .. char(a)
            end
        end
    end
    return concat(out)
end

-- ---------------------------------------------------------------- corrosion
local P                       -- TK_Theme_Patina's helpers, given by Forge.use
function Forge.use(patina_lib) P = patina_lib.util end

-- value noise on a lattice `cell` wide, smooth between the points; the lattice comes from R
local function lattice(R, gw, gh)
    local g = {}
    for i = 1, (gw + 2) * (gh + 2) do g[i] = R.next() end
    return g, gw + 2
end

-- fractal noise over W x H; ux(x) and uy(y) map pixels to noise space (the stretch fix).
-- step > 1: worked out on every step-th pixel and spread between them (for coarse noise)
local fbm_full
local function fbm(R, W, H, cell, oct, ux, uy, step)
    if not step or step <= 1 then return fbm_full(R, W, H, cell, oct, ux, uy) end
    local w, h = math.ceil((W - 1) / step) + 2, math.ceil((H - 1) / step) + 2
    local small = fbm_full(R, w, h, cell, oct, function(x) return ux(math.min(W - 1, x * step)) end,
        function(y) return uy(math.min(H - 1, y * step)) end)
    local F = {}
    for y = 0, H - 1 do
        local v = y / step
        local yi = math.floor(v)
        local fy = v - yi
        local r0, r1 = yi * w + 1, (yi + 1) * w + 1
        local base = y * W + 1
        for x = 0, W - 1 do
            local u = x / step
            local xi = math.floor(u)
            local fx = u - xi
            local a, b = small[r0 + xi], small[r0 + xi + 1]
            local top = a + (b - a) * fx
            local c, d = small[r1 + xi], small[r1 + xi + 1]
            F[base + x] = top + (c + (d - c) * fx - top) * fy
        end
    end
    return F
end

function fbm_full(R, W, H, cell, oct, ux, uy)
    local F = {}
    for i = 1, W * H do F[i] = 0 end
    local amp, tot = 1, 0
    local umax, vmax = ux(W), uy(H)
    for _ = 1, oct do
        local c = math.max(2, cell)
        local gw, gh = math.ceil(umax / c) + 1, math.ceil(vmax / c) + 1
        local g, stride = lattice(R, gw, gh)
        local xs, fx = {}, {}
        for x = 0, W - 1 do
            local u = ux(x) / c
            local xi = math.floor(u)
            local f = u - xi
            xs[x], fx[x] = xi, f * f * (3 - 2 * f)
        end
        for y = 0, H - 1 do
            local v = uy(y) / c
            local yi = math.floor(v)
            local fy = v - yi
            fy = fy * fy * (3 - 2 * fy)
            local r0, r1 = yi * stride + 1, (yi + 1) * stride + 1
            local base = y * W + 1
            for x = 0, W - 1 do
                local xi, f = xs[x], fx[x]
                local a, b = g[r0 + xi], g[r0 + xi + 1]
                local cc, d = g[r1 + xi], g[r1 + xi + 1]
                local top = a + (b - a) * f
                F[base + x] = F[base + x] + amp * (top + (cc + (d - cc) * f - top) * fy)
            end
        end
        tot = tot + amp
        amp = amp * 0.5
        cell = cell / 2
    end
    for i = 1, W * H do F[i] = F[i] / tot end
    return F
end

local function smooth(e0, e1, x)
    local t = (x - e0) / (e1 - e0)
    t = t < 0 and 0 or t > 1 and 1 or t
    return t * t * (3 - 2 * t)
end

-- per kind of corrosion: crust colours (dark, light, specks), halo and streak colours
local CORR = {
    rust = { dark = { 62, 26, 12 }, lite = { 176, 82, 30 }, speck = { 214, 128, 60 }, halo = { 96, 58, 34 }, streak = { 150, 72, 30 }, drip = true },
    verdigris = { dark = { 34, 92, 78 }, lite = { 86, 168, 140 }, speck = { 168, 216, 192 }, halo = { 60, 36, 20 }, streak = { 80, 160, 130 }, drip = true },
    tarnish = { dark = { 52, 40, 18 }, lite = { 98, 92, 48 }, speck = { 80, 150, 120 }, halo = { 70, 52, 24 } },
    oxide = { white = { 226, 230, 234 } },
}

-- one corrosion overlay, variant v, at scale s (200% unless given): W, H and RGBA pixels as
-- a table of 4-byte strings
function Forge.corrosion(kind, corr, amount, seed, v, s)
    local K = Forge.KINDS[kind]
    s = s or 2               -- 2: the theme's images are drawn at 200%; 1 for the small thumbnails
    local W, H = K.w * s, K.h * s
    local R = P.rng(seed * 11 + v * 197 + (kind == "mcp" and 1231 or 0) + 7)
    -- the middle stretches in the theme: noise is drawn squeezed there, so blobs come out round
    local L, T, Rr, B = K.fix[1] * s, K.fix[2] * s, K.fix[3] * s, K.fix[4] * s
    local sx, sy = K.sx or 1, K.sy or 1
    local function ux(x)
        if x <= L then return x end
        if x >= W - Rr then return L + (W - Rr - L) * sx + (x - (W - Rr)) end
        return L + (x - L) * sx
    end
    local function uy(y)
        if y <= T then return y end
        if y >= H - B then return T + (H - B - T) * sy + (y - (H - B)) end
        return T + (y - T) * sy
    end
    local blobs = fbm(R, W, H, 48 * s, 4, ux, uy, 4)
    local breaker = fbm(R, W, H, 30 * s, 3, ux, uy, 4)
    local fine = fbm(R, W, H, 6 * s, 2, ux, uy, 2)
    local pits = fbm(R, W, H, 1.5 * s, 1, ux, uy)
    -- blobs with more contrast: spread round their mean
    local mean, sq = 0, 0
    for i = 1, W * H do mean = mean + blobs[i] end
    mean = mean / (W * H)
    for i = 1, W * H do sq = sq + (blobs[i] - mean) ^ 2 end
    local sd = math.sqrt(sq / (W * H)) + 1e-6
    local th = 1.0 - 0.40 * amount
    local sc = K.screws and K.screws[1] * s
    local screws = sc and { { sc, sc }, { W - sc, sc }, { sc, H - sc }, { W - sc, H - sc } } or {}
    local core, field = {}, {}
    -- the edge's and the screws' pull, looked up: both are gone some 40 px (1x) in
    local EDGE = {}
    for d = 0, 60 * s do EDGE[d] = math.exp(-(d / s) / 6) end
    local reach = 50 * s
    local exp, sqrt = math.exp, math.sqrt
    local k06 = 0.16 / sd
    for y = 0, H - 1 do
        local dy_edge = math.min(y, H - 1 - y)
        local near_y = y < reach or y > H - 1 - reach
        for x = 0, W - 1 do
            local i = y * W + x + 1
            local de = W - 1 - x
            if x < de then de = x end
            if dy_edge < de then de = dy_edge end
            local edge = EDGE[de] or 0
            local scr = 0
            if near_y and (x < reach or x > W - 1 - reach) then
                for _, c in ipairs(screws) do
                    local dx, dy = x - c[1], (y - c[2]) * 0.8
                    local e = exp(-sqrt(dx * dx + dy * dy) / (9 * s))
                    if e > scr then scr = e end
                end
            end
            local b = (blobs[i] - mean) * k06 + 0.5
            local br = breaker[i]
            br = br <= 0.35 and 0 or br >= 0.65 and 1 or ((br - 0.35) / 0.3) ^ 2 * (3 - 2 * (br - 0.35) / 0.3)
            local f = b * 0.70 + edge * br * 0.40 + scr * 0.45 + fine[i] * 0.16
            field[i] = f
            -- smooth(th, th + 0.07, f), written out: this loop runs for every pixel
            local q = (f - th) / (th + 0.07 - th)
            q = q < 0 and 0 or q > 1 and 1 or q
            core[i] = q * q * (3 - 2 * q)
        end
    end
    local C = CORR[corr]
    local out = {}
    local function put(i, r, g, b, a)
        a = a < 0 and 0 or a > 1 and 1 or a
        out[i] = a <= 0.004 and "\0\0\0\0" or char(clamp(r), clamp(g), clamp(b), clamp(a * 255))
    end
    if corr == "heat" then
        -- titanium's heat tint: no crust, but colour bands from straw through purple to blue,
        -- strongest where corrosion would be
        local bands = { { 214, 176, 92 }, { 176, 104, 70 }, { 132, 72, 156 }, { 70, 112, 204 } }
        for i = 1, W * H do
            local f = field[i]
            local q = (f - (th - 0.14)) / 0.24
            if q <= 0 then
                out[i] = "\0\0\0\0"
            else
                q = q > 1 and 1 or q
                local pos = q * 3
                local j = math.floor(pos)
                if j > 2 then j = 2 end
                local u = pos - j
                local a1, a2 = bands[j + 1], bands[j + 2]
                put(i, a1[1] + (a2[1] - a1[1]) * u, a1[2] + (a2[2] - a1[2]) * u, a1[3] + (a2[3] - a1[3]) * u, math.min(1, q * 1.6) * 0.62)
            end
        end
        return W, H, out
    end
    if corr == "oxide" then
        local w = C.white
        for i = 1, W * H do
            local f = field[i]
            local haze = smooth(th - 0.15, th + 0.15, f) * 0.35 * 0.85
            local spot = smooth(0.74, 0.86, pits[i] * 0.6 + f * 0.5) * 0.75 * smooth(th - 0.25, th, f)
            local a = haze + spot * (1 - haze)
            put(i, w[1], w[2], w[3], a)
        end
    else
        -- streaks: rust running down under the crust, fading
        local streak = {}
        if C.drip then
            local len = 26 * s
            -- only some columns drip, thin ones: the middle is stretched sideways in the theme
            for x = 0, W - 1 do
                local drip = R.next() ^ 4
                local carry = 0
                for y = 0, H - 1 do
                    local i = y * W + x + 1
                    carry = math.max(core[i], carry * (1 - 1 / len))
                    streak[i] = math.max(0, carry * drip - core[i]) * 0.35 * amount
                end
            end
        end
        for y = 0, H - 1 do
            for x = 0, W - 1 do
                local i = y * W + x + 1
                local c, f = core[i], field[i]
                local halo = smooth(th - 0.10, th, f) * (1 - c) * 0.55
                local st = streak[i] or 0
                -- layer the three: halo, streak, crust (over each other, as REAPER would)
                local r, g, b, a = C.halo[1], C.halo[2], C.halo[3], halo
                if st > 0 then
                    local na = st + a * (1 - st)
                    r = (C.streak[1] * st + r * a * (1 - st)) / na
                    g = (C.streak[2] * st + g * a * (1 - st)) / na
                    b = (C.streak[3] * st + b * a * (1 - st)) / na
                    a = na
                end
                if c > 0 then
                    local var = (blobs[i] - mean) / sd * 0.25 + fine[i] * 0.5 + 0.25
                    var = var < 0 and 0 or var > 1 and 1 or var
                    local cr = C.dark[1] + (C.lite[1] - C.dark[1]) * var
                    local cg = C.dark[2] + (C.lite[2] - C.dark[2]) * var
                    local cb = C.dark[3] + (C.lite[3] - C.dark[3]) * var
                    if pits[i] > 0.62 then
                        local k = math.min(1, (pits[i] - 0.62) * 8) * 0.6
                        cr, cg, cb = cr + (C.speck[1] - cr) * k, cg + (C.speck[2] - cg) * k, cb + (C.speck[3] - cb) * k
                    end
                    -- a raised crust: lighter where the one above is not crust
                    local above = y >= s and core[i - s * W] or 0
                    local lift = math.max(0, c - above) * 26
                    cr, cg, cb = cr + lift, cg + lift, cb + lift
                    local ca = c * 0.92
                    local na = ca + a * (1 - ca)
                    r = (cr * ca + r * a * (1 - ca)) / na
                    g = (cg * ca + g * a * (1 - ca)) / na
                    b = (cb * ca + b * a * (1 - ca)) / na
                    a = na
                end
                put(i, r, g, b, a)
            end
        end
    end
    return W, H, out
end

-- cardboard's layer, variant v, at scale s (200% unless given): water stains with a dark
-- tide line, lighter scuffs where the liner is rubbed off near the edges, and creases (a
-- light ridge beside a dark valley). amount: the stains and scuffs, creases: how many creases.
-- Where they are comes from the seed alone, so a slider only changes how much shows
-- what each kind of layer is made of: rings (inside and tide line), scuffs, creases, pits
local LAYER_LOOK = {
    stains = { ring = { 74, 50, 26, 0.10, 0.32 }, scuff = { 238, 222, 192, 0.45 }, creases = true },
    -- wood: glasses leave pale rings on varnish, and the varnish wears dull where hands go
    varnish = { ring = { 236, 228, 212, 0.05, 0.36 }, scuff = { 214, 188, 152, 0.42 } },
    -- cork: crumbs broken off near the edges, and small dents pressed in
    dents = { scuff = { 240, 214, 180, 0.50 }, pits = { 46, 30, 18, 0.62 } },
}

function Forge.stains(kind, amount, creases, seed, v, s, look)
    look = look or LAYER_LOOK.stains
    local K = Forge.KINDS[kind]
    s = s or 2
    local W, H = K.w * s, K.h * s
    local R = P.rng(seed * 13 + v * 211 + (kind == "mcp" and 977 or kind == "trans" and 1913 or 0) + 3)
    -- as the corrosion: drawn squeezed where the theme stretches, so rings come out round
    local L, T, Rr, B = K.fix[1] * s, K.fix[2] * s, K.fix[3] * s, K.fix[4] * s
    local sx, sy = K.sx or 1, K.sy or 1
    local function ux(x)
        if x <= L then return x end
        if x >= W - Rr then return L + (W - Rr - L) * sx + (x - (W - Rr)) end
        return L + (x - L) * sx
    end
    local function uy(y)
        if y <= T then return y end
        if y >= H - B then return T + (H - B - T) * sy + (y - (H - B)) end
        return T + (y - T) * sy
    end
    local U, V = {}, {}
    for x = 0, W - 1 do U[x] = ux(x) / s end
    for y = 0, H - 1 do V[y] = uy(y) / s end
    local umax, vmax = U[W - 1], V[H - 1]
    -- every random number drawn in the same order whatever the sliders say
    local rings, lines = {}, {}
    for j = 1, 5 do rings[j] = { x = R.uni(0, umax), y = R.uni(0, vmax), r = R.uni(12, 30) } end
    for j = 1, 3 do
        local ang = math.pi / 2 + R.uni(-0.9, 0.9)
        lines[j] = { x = R.uni(umax * 0.12, umax * 0.88), y = vmax / 2, dx = math.cos(ang), dy = math.sin(ang) }
    end
    -- dents (cork only, so board draws exactly as before): drawn into an array of their own,
    -- each only over the pixels it can reach
    local pitA
    if look.pits then
        local list = {}
        for j = 1, 48 do list[j] = { x = R.uni(0, umax), y = R.uni(0, vmax), r = R.uni(0.7, 1.7) } end
        pitA = {}
        for i = 1, W * H do pitA[i] = 0 end
        for j = 1, math.floor(amount * 48 + 0.5) do
            local c = list[j]
            local x0, x1, y0, y1 = W, -1, H, -1
            for x = 0, W - 1 do
                if U[x] >= c.x - c.r - 1 and U[x] <= c.x + c.r + 1 then
                    if x < x0 then x0 = x end
                    if x > x1 then x1 = x end
                end
            end
            for y = 0, H - 1 do
                if V[y] >= c.y - c.r - 1 and V[y] <= c.y + c.r + 1 then
                    if y < y0 then y0 = y end
                    if y > y1 then y1 = y end
                end
            end
            for y = y0, y1 do
                for x = x0, x1 do
                    local dx, dy = U[x] - c.x, V[y] - c.y
                    local q = (c.r - math.sqrt(dx * dx + dy * dy)) / 0.6
                    q = q < 0 and 0 or q > 1 and 1 or q
                    local i = y * W + x + 1
                    if q > pitA[i] then pitA[i] = q end
                end
            end
        end
    end
    local wob = fbm(R, W, H, 10 * s, 2, ux, uy, 2)
    local rough = fbm(R, W, H, 16 * s, 3, ux, uy, 2)
    local n_rings = look.ring and math.floor(amount * 4 + 0.5) or 0
    local n_lines = look.creases and math.floor(creases * 3 + 0.5) or 0
    local SC, RG = look.scuff, look.ring
    local grow = 0.6 + amount * 0.6
    local th = 0.95 - 0.35 * amount
    local EMPTY = string.char(0, 0, 0, 0)
    local out = {}
    local exp = math.exp
    -- one layer over what is there (colour and alpha in, colour and alpha out)
    local function over(r, g, b, a, cr, cg, cb, ca)
        if ca <= 0 then return r, g, b, a end
        local na = ca + a * (1 - ca)
        return (cr * ca + r * a * (1 - ca)) / na, (cg * ca + g * a * (1 - ca)) / na, (cb * ca + b * a * (1 - ca)) / na, na
    end
    for y = 0, H - 1 do
        local vy = V[y]
        local dy_edge = y < H - 1 - y and y or H - 1 - y
        for x = 0, W - 1 do
            local i = y * W + x + 1
            local de = W - 1 - x
            if x < de then de = x end
            if dy_edge < de then de = dy_edge end
            de = de / s
            local w = wob[i] - 0.5
            -- the layers, each over the one before: scuffs, stains, creases
            local r, g, b, a = 0, 0, 0, 0
            if amount > 0 and de > 1.5 then
                local f = rough[i] * 0.8 + exp(-de / 5) * 0.35
                local q = (f - th) / 0.1
                q = q < 0 and 0 or q > 1 and 1 or q
                r, g, b, a = over(r, g, b, a, SC[1], SC[2], SC[3], q * q * (3 - 2 * q) * SC[4])
            end
            local ux_ = U[x]
            for j = 1, n_rings do
                local c = rings[j]
                local dx, dyy = ux_ - c.x, vy - c.y
                local d = math.sqrt(dx * dx + dyy * dyy) + w * 6
                local rr = c.r * grow
                if d < rr + 4 then
                    local q = (rr - d) / 3
                    q = q < 0 and 0 or q > 1 and 1 or q
                    local inside = q * q * (3 - 2 * q) * RG[4]
                    local tide = exp(-((d - rr) / 1.3) ^ 2) * RG[5]
                    r, g, b, a = over(r, g, b, a, RG[1], RG[2], RG[3], inside > tide and inside or tide)
                end
            end
            for j = 1, n_lines do
                local c = lines[j]
                local dist = (ux_ - c.x) * -c.dy + (vy - c.y) * c.dx + w * 2.5
                if dist > -4 and dist < 4 then
                    r, g, b, a = over(r, g, b, a, 250, 236, 210, exp(-((dist + 1.0) / 0.9) ^ 2) * 0.5)
                    r, g, b, a = over(r, g, b, a, 60, 42, 24, exp(-((dist - 0.6) / 1.0) ^ 2) * 0.45)
                end
            end
            if pitA and pitA[i] > 0 then
                local pt = look.pits
                r, g, b, a = over(r, g, b, a, pt[1], pt[2], pt[3], pitA[i] * pt[4])
            end
            if a <= 0.004 then out[i] = EMPTY
            else out[i] = char(clamp(r), clamp(g), clamp(b), clamp(a * 255)) end
        end
    end
    return W, H, out
end

-- a material's layer over its plate: a metal's corrosion, or for board, wood and cork the
-- one drawing of stains in their own look
function Forge.layer(kind, m, v, s)
    local fin = Forge.finish(m.finish)
    if LAYER_LOOK[fin.corr] then return Forge.stains(kind, m.corrosion, m.gloss, m.seed, v, s, LAYER_LOOK[fin.corr]) end
    return Forge.corrosion(kind, fin.corr, m.corrosion, m.seed, v, s)
end

-- ---------------------------------------------------------------- fastening
-- What holds a plate: staples, brown or clear tape, push pins. Four small images, one per
-- corner, set in the plate's corners by the layout and never stretched, so a staple stays a
-- staple on any track. Drawn at 200% and made smaller for 150% and 100%.
-- new kinds only at the end: materials and theme codes keep the number
Forge.FASTENINGS = { "None", "Staples", "Brown tape", "Clear tape", "Push pins", "Screws" }
-- the corner images' size at 100%, per plate (the layout sets them in the same size)
Forge.FASTEN_BOX = { tcp = { 34, 28 }, mcp = { 28, 34 }, trans = { 36, 28 } }
Forge.CORNERS = { "TL", "TR", "BL", "BR" }

-- coverage of a shape in a box, 4 x 4 samples a pixel: inside(x, y) in 100% units
local function cover(W, H, s, inside)
    local A = {}
    for y = 0, H - 1 do
        for x = 0, W - 1 do
            local n = 0
            for sy = 0, 3 do
                local py = (y + (sy + 0.5) / 4) / s
                for sx = 0, 3 do
                    if inside((x + (sx + 0.5) / 4) / s, py) then n = n + 1 end
                end
            end
            A[y * W + x + 1] = n / 16
        end
    end
    return A
end

local function seg_dist(px, py, x0, y0, x1, y1)
    local dx, dy = x1 - x0, y1 - y0
    local L2 = dx * dx + dy * dy
    local t = L2 > 0 and math.max(0, math.min(1, ((px - x0) * dx + (py - y0) * dy) / L2)) or 0
    local ex, ey = px - x0 - t * dx, py - y0 - t * dy
    return math.sqrt(ex * ex + ey * ey)
end

local function in_poly(px, py, poly)
    local inside, j = false, #poly
    for i = 1, #poly do
        local xi, yi, xj, yj = poly[i][1], poly[i][2], poly[j][1], poly[j][2]
        if (yi > py) ~= (yj > py) and px < (xj - xi) * (py - yi) / (yj - yi) + xi then inside = not inside end
        j = i
    end
    return inside
end

-- one corner's image: W x H at 200% as a table of 4-byte strings
function Forge.fasten_corner(kind, what, seed, corner, ci)
    local s = 2
    local bw, bh = Forge.FASTEN_BOX[kind][1], Forge.FASTEN_BOX[kind][2]
    local W, H = bw * s, bh * s
    local R = P.rng(seed * 17 + ci * 31 + (kind == "mcp" and 501 or kind == "trans" and 907 or 0) + 11)
    -- the corner's point and the way into the plate, in 100% units
    local right, bottom = corner:sub(2, 2) == "R", corner:sub(1, 1) == "B"
    local cx, cy = right and bw or 0, bottom and bh or 0
    local ix, iy = right and -1 or 1, bottom and -1 or 1
    local R_, G_, B_, A_ = {}, {}, {}, {}
    for i = 1, W * H do R_[i], G_[i], B_[i], A_[i] = 0, 0, 0, 0 end
    local function paint(cov, col, alpha)
        for i = 1, W * H do
            local ca = cov[i] * alpha
            if ca > 0 then
                local a = A_[i]
                local na = ca + a * (1 - ca)
                R_[i] = (col[1] * ca + R_[i] * a * (1 - ca)) / na
                G_[i] = (col[2] * ca + G_[i] * a * (1 - ca)) / na
                B_[i] = (col[3] * ca + B_[i] * a * (1 - ca)) / na
                A_[i] = na
            end
        end
    end
    local function shadow(cov, dx, dy, sigma, alpha)
        local sh = {}
        for y = 0, H - 1 do
            for x = 0, W - 1 do
                local sx, sy = x - math.floor(dx * s + 0.5), y - math.floor(dy * s + 0.5)
                sh[y * W + x + 1] = (sx >= 0 and sx < W and sy >= 0 and sy < H) and cov[sy * W + sx + 1] or 0
            end
        end
        P.blur(sh, W, H, sigma * s)
        paint(sh, { 0, 0, 0 }, alpha)
    end
    if what == "Staples" then
        local ang = R.uni(-0.5, 0.5) + (R.next() < 0.3 and math.pi / 2 or 0)
        local mx, my = cx + ix * 11, cy + iy * 9.5
        local hl = 8
        local x0, y0 = mx - math.cos(ang) * hl, my - math.sin(ang) * hl
        local x1, y1 = mx + math.cos(ang) * hl, my + math.sin(ang) * hl
        local body = cover(W, H, s, function(px, py) return seg_dist(px, py, x0, y0, x1, y1) < 1.05 end)
        shadow(body, 0.4, 0.7, 0.5, 0.55)
        paint(body, { 150, 154, 160 }, 1)
        local nx, ny = -math.sin(ang) * 0.3, math.cos(ang) * 0.3
        paint(cover(W, H, s, function(px, py) return seg_dist(px, py, x0 - nx, y0 - ny, x1 - nx, y1 - ny) < 0.3 end), { 224, 228, 234 }, 1)
        paint(cover(W, H, s, function(px, py)
            local a, b = px - x0, py - y0
            local c, d = px - x1, py - y1
            return a * a + b * b < 0.55 or c * c + d * d < 0.55
        end), { 70, 70, 72 }, 1)
    elseif what == "Brown tape" or what == "Clear tape" then
        local ang = math.atan(iy, ix) + R.uni(-0.15, 0.15)
        local ux, uy = math.cos(ang), math.sin(ang)
        local px_, py_ = -uy, ux
        local hw, out_len, in_len = 6.5, 12, 22 + R.uni(0, 4)
        local poly = { { cx - ux * out_len + px_ * hw, cy - uy * out_len + py_ * hw },
                       { cx - ux * out_len - px_ * hw, cy - uy * out_len - py_ * hw } }
        local n = 7
        for j = 0, n do                      -- the torn end: a zigzag
            local q = -1 + 2 * j / n
            local z = (j % 2 == 1) and R.uni(0, 1.0) or 0
            poly[#poly + 1] = { cx + ux * (in_len + z) + px_ * hw * q, cy + uy * (in_len + z) + py_ * hw * q }
        end
        local body = cover(W, H, s, function(x, y) return in_poly(x, y, poly) end)
        local clear = what == "Clear tape"
        paint(body, clear and { 250, 252, 255 } or { 188, 132, 66 }, clear and 0.26 or 0.72)
        -- the tape catches the light: two streaks along it, and its long edges
        for _, off in ipairs({ 0.45, -0.2 }) do
            local gx0, gy0 = cx - ux * out_len + px_ * hw * off, cy - uy * out_len + py_ * hw * off
            local gx1, gy1 = cx + ux * in_len * 0.9 + px_ * hw * off, cy + uy * in_len * 0.9 + py_ * hw * off
            local streak = cover(W, H, s, function(x, y) return seg_dist(x, y, gx0, gy0, gx1, gy1) < 0.3 end)
            for i = 1, W * H do streak[i] = streak[i] * body[i] end
            paint(streak, { 255, 255, 255 }, (clear and 0.55 or 0.3) * (off > 0 and 1 or 0.6))
        end
        if clear then                        -- a little dust caught under it
            for _ = 1, 4 do
                local dx, dy = cx + ux * R.uni(0, in_len) + px_ * R.uni(-hw, hw), cy + uy * R.uni(0, in_len) + py_ * R.uni(-hw, hw)
                paint(cover(W, H, s, function(x, y) return (x - dx) ^ 2 + (y - dy) ^ 2 < 0.12 end), { 90, 80, 70 }, 0.4)
            end
        end
    elseif what == "Screws" then
        -- a Phillips screw driven into the board: a steel head with a bevel, its cross at
        -- an angle of its own, a little shadow
        local mx, my = cx + ix * 10.5, cy + iy * 10
        local r = 3.6
        local head = cover(W, H, s, function(x, y) return (x - mx) ^ 2 + (y - my) ^ 2 < r * r end)
        shadow(head, 0.6, 0.9, 0.7, 0.5)
        paint(head, { 96, 100, 106 }, 1)
        local r2 = r * 0.82
        paint(cover(W, H, s, function(x, y) return (x - mx + 0.2) ^ 2 + (y - my + 0.25) ^ 2 < r2 * r2 end), { 176, 180, 186 }, 1)
        paint(cover(W, H, s, function(x, y) return (x - mx + 1.1) ^ 2 + (y - my + 1.2) ^ 2 < 0.7 end), { 236, 238, 242 }, 0.7)
        local ang = R.uni(0, math.pi / 2)
        local ca, sa = math.cos(ang), math.sin(ang)
        local arm = r * 0.62
        paint(cover(W, H, s, function(x, y)
            return seg_dist(x, y, mx - ca * arm, my - sa * arm, mx + ca * arm, my + sa * arm) < 0.42
                or seg_dist(x, y, mx + sa * arm, my - ca * arm, mx - sa * arm, my + ca * arm) < 0.42
        end), { 54, 56, 60 }, 1)
    elseif what == "Push pins" then
        local cols = { { 212, 44, 44 }, { 236, 196, 40 }, { 40, 110, 210 }, { 52, 168, 90 } }
        local col = cols[(ci + seed) % 4 + 1]
        local mx, my = cx + ix * 11, cy + iy * 10
        local r = 3.9
        local head = cover(W, H, s, function(x, y) return (x - mx) ^ 2 + (y - my) ^ 2 < r * r end)
        shadow(head, 1.0, 1.5, 0.9, 0.5)
        paint(head, { math.floor(col[1] * 0.62), math.floor(col[2] * 0.62), math.floor(col[3] * 0.62) }, 1)
        local r2 = r * 0.8
        paint(cover(W, H, s, function(x, y) return (x - mx + 0.25) ^ 2 + (y - my + 0.3) ^ 2 < r2 * r2 end), col, 1)
        paint(cover(W, H, s, function(x, y) return (x - mx + 1.3) ^ 2 + (y - my + 1.4) ^ 2 < 0.9 end), { 255, 255, 255 }, 0.75)
    end
    local out = {}
    for i = 1, W * H do
        local a = A_[i]
        out[i] = a <= 0.004 and "\0\0\0\0" or char(clamp(R_[i]), clamp(G_[i]), clamp(B_[i]), clamp(a * 255))
    end
    return W, H, out
end

-- every corner image of one plate's fastening, at every scale: { [name] = png }
function Forge.fasten_images(kind, what, seed, crc32)
    local files = {}
    local bw, bh = Forge.FASTEN_BOX[kind][1], Forge.FASTEN_BOX[kind][2]
    for ci, corner in ipairs(Forge.CORNERS) do
        local W, H, big = Forge.fasten_corner(kind, what, seed, corner, ci)
        for _, sc in ipairs(Forge.SCALES) do
            local w, h = math.floor(bw * sc[2] + 0.5), math.floor(bh * sc[2] + 0.5)
            local px = sc[2] == 2 and big or Forge.shrink_rgba(big, W, H, w, h)
            files[sc[1] .. kind .. "Fasten" .. corner .. ".png"] = Forge.png_packed(w, h, concat(px), crc32)
        end
    end
    return files
end

-- source spans for an area shrink of n to m: for each target, flat lists of index and weight
local function spans(n, m)
    local f = n / m
    local first, count, idx, wt = {}, {}, {}, {}
    for d = 0, m - 1 do
        local s0, s1 = d * f, (d + 1) * f
        first[d] = #idx + 1
        for sx = math.floor(s0), math.min(n - 1, math.ceil(s1) - 1) do
            local u = math.min(s1, sx + 1) - math.max(s0, sx)
            if u > 0 then idx[#idx + 1] = sx wt[#wt + 1] = u / f end
        end
        count[d] = #idx + 1 - first[d]
    end
    return first, count, idx, wt
end

-- an RGBA table (4-byte strings) made smaller by area, the colours weighted by alpha; the
-- empty parts (most of an overlay) cost almost nothing
local function shrink_rgba(px, W, H, w, h)
    local cf, cc, ci, cw = spans(W, w)
    local rf, rc, ri, rw = spans(H, h)
    -- across first: per source row, w premultiplied values (rows that are empty stay nil)
    local rows = {}
    for y = 0, H - 1 do
        local base = y * W
        local any = false
        for x = 1, W do if px[base + x] ~= "\0\0\0\0" then any = true break end end
        if any then
            local R, G, B, A = {}, {}, {}, {}
            for x = 0, w - 1 do
                local r, g, b, a = 0, 0, 0, 0
                local f = cf[x]
                for k = f, f + cc[x] - 1 do
                    local p = px[base + ci[k] + 1]
                    if p ~= "\0\0\0\0" then
                        local pr, pg, pb, pa = byte(p, 1, 4)
                        local u = cw[k] * pa
                        r, g, b, a = r + pr * u, g + pg * u, b + pb * u, a + u
                    end
                end
                R[x], G[x], B[x], A[x] = r, g, b, a
            end
            rows[y] = { R, G, B, A }
        end
    end
    local out = {}
    for y = 0, h - 1 do
        local f = rf[y]
        for x = 0, w - 1 do
            local r, g, b, a = 0, 0, 0, 0
            for k = f, f + rc[y] - 1 do
                local row = rows[ri[k]]
                if row then
                    local u = rw[k]
                    r, g, b, a = r + row[1][x] * u, g + row[2][x] * u, b + row[3][x] * u, a + row[4][x] * u
                end
            end
            if a < 0.5 then out[y * w + x + 1] = "\0\0\0\0"
            else out[y * w + x + 1] = char(clamp(r / a), clamp(g / a), clamp(b / a), clamp(a)) end
        end
    end
    return out
end
Forge.shrink_rgba = shrink_rgba

-- ---------------------------------------------------------------- the images for the theme
-- o: { finish = name, gloss, contrast, corrosion (0..1), seed, tcp = bool, mcp = bool }
-- Two layers per plate, each with a key of its own (kept in the theme as tk_forge_<kind>_
-- <layer>.txt): a slider of one draws only that one again

-- the finish on one plate, at every scale. bases(name, prefix) gives W, H, pixels of
-- tcpPlateSilver / ... at a scale (Forge.reader). Returns { [path in the theme folder] = png }
function Forge.plate_images(kind, o, bases, crc32)
    local K, fin, files = Forge.KINDS[kind], Forge.finish(o.finish), {}
    for _, sc in ipairs(Forge.SCALES) do
        local W, H, px = bases(K.plate .. Forge.source(fin), sc[1])
        if not W then return nil, "no " .. K.plate .. Forge.source(fin) .. " in the theme" end
        local lut = Forge.lut(fin, Forge.median(W, H, px), plate_gloss(fin, o), o.contrast)
        files[sc[1] .. K.plate .. "Mat.png"] = Forge.png_packed(W, H, Forge.recolour(W, H, px, lut, sc[2], fin.base == 1 and not fin.work and K.screws ~= nil), crc32)
    end
    return files
end

-- The rails: the lath beside the track panel (also the master's and the envelope lanes') and
-- the mixer's armrest, in place of walnut or teak. Cut from the middle of the material's work
-- plate (clear of its edges, screws and grooves), recoloured as its plates are, and shaded
-- round across, as the wooden laths are. Sizes at 100% as tcpWoodWalnut / mcpWoodArmWalnut
Forge.RAILS = {
    { name = "tcpWoodMat", w = 20, h = 400, from = "mcpPlate", across = "x", box = { 0.3, 0.7, 0.15, 0.85 } },
    { name = "mcpWoodArmMat", w = 400, h = 20, from = "tcpPlate", across = "y", box = { 0.15, 0.85, 0.3, 0.7 } },
}

function Forge.rail_images(m, bases, crc32)
    local fin, files = Forge.finish(m.finish), {}
    for _, R in ipairs(Forge.RAILS) do
        for _, sc in ipairs(Forge.SCALES) do
            local W, H, px = bases(R.from .. Forge.source(fin), sc[1])
            if not W then return nil, "no " .. R.from .. Forge.source(fin) .. " in the theme" end
            local lut = Forge.lut(fin, Forge.median(W, H, px), plate_gloss(fin, m), m.contrast)
            local w, h = math.floor(R.w * sc[2] + 0.5), math.floor(R.h * sc[2] + 0.5)
            local x0, x1 = math.floor(W * R.box[1]), math.floor(W * R.box[2])
            local y0, y1 = math.floor(H * R.box[3]), math.floor(H * R.box[4])
            local n = R.across == "x" and w or h
            local shade = {}
            for i = 0, n - 1 do shade[i] = 0.82 + 0.28 * math.sin(math.pi * (i + 0.5) / n) ^ 0.6 end
            local out = {}
            for y = 0, h - 1 do
                local sy = y0 + math.floor((y + 0.5) * (y1 - y0) / h)
                for x = 0, w - 1 do
                    local sx = x0 + math.floor((x + 0.5) * (x1 - x0) / w)
                    local at = (sy * W + sx) * 4 + 1
                    local r, g, b = byte(px, at, at + 2)
                    local cr, cg, cb = byte(lut[(r * 77 + g * 150 + b * 29) >> 8], 1, 3)
                    local f = shade[R.across == "x" and x or y]
                    out[y * w + x + 1] = char(clamp(cr * f), clamp(cg * f), clamp(cb * f), 255)
                end
            end
            files[sc[1] .. R.name .. ".png"] = Forge.png_packed(w, h, concat(out), crc32)
        end
    end
    return files
end

function Forge.rail_key(m)
    local fin = Forge.finish(m.finish)
    return string.format("rails %d|%s|%.2f|%.2f", Forge.VERSION, m.finish, plate_gloss(fin, m), m.contrast)
end

-- the corrosion on one plate: its patterns (Forge.RUST_VARIANTS) at every scale
function Forge.rust_images(kind, o, crc32)
    local K, fin, files = Forge.KINDS[kind], Forge.finish(o.finish), {}
    for v = 0, (K.variants or Forge.RUST_VARIANTS) - 1 do
        local W2, H2, big = Forge.layer(kind, o, v)
        for _, sc in ipairs(Forge.SCALES) do
            local w, h = math.floor(K.w * sc[2] + 0.5), math.floor(K.h * sc[2] + 0.5)
            local px
            if sc[2] == 2 then
                px = {}
                for i = 1, #big do px[i] = big[i] end
            else
                px = shrink_rgba(big, W2, H2, w, h)
            end
            P.ring(px, w, h, K.fix, sc[2])
            files[sc[1] .. kind .. "Rust" .. v .. ".png"] = Forge.png_packed(w, h, concat(px), crc32)
        end
    end
    return files
end

function Forge.plate_key(o)
    local fin = Forge.finish(o.finish)
    return string.format("plate %d|%s|%.2f|%.2f", Forge.VERSION, o.finish, plate_gloss(fin, o), o.contrast)
end

function Forge.fasten_key(o)
    return string.format("fasten %d|%s|%d", Forge.VERSION, Forge.FASTENINGS[o.fasten or 1] or "None", o.seed)
end

-- whether a material has something holding it
function Forge.fastened(m) return (m.fasten or 1) > 1 and not Forge.finish(m.finish).plain end

function Forge.rust_key(o)
    local fin = Forge.finish(o.finish)
    local key = string.format("rust %d x%d|%s|%.2f|%d", Forge.VERSION, Forge.RUST_VARIANTS, fin.corr, o.corrosion, o.seed)
    if fin.creases then key = key .. string.format("|creases %.2f", o.gloss) end
    return key
end

-- every image (both plates, both layers), for the tests
function Forge.images(o, bases, crc32)
    local files = {}
    for _, kind in ipairs({ "tcp", "mcp" }) do
        if o[kind] then
            local made, err = Forge.plate_images(kind, o, bases, crc32)
            if not made then return nil, err end
            for k, v in pairs(made) do files[k] = v end
            if Forge.layered(o) then
                for k, v in pairs(Forge.rust_images(kind, o, crc32)) do files[k] = v end
            end
        end
    end
    return files
end

-- the plates as the theme holds them, read once: unpacking a PNG in Lua takes a second or
-- two, so the pixels are kept in `dir` (under the file's checksum: a new theme, a new file)
-- and in memory. Returns the bases() Forge.images wants
function Forge.reader(Zip, zip, root, dir)
    local mem = {}
    return function(name, prefix)
        local entry = root .. "/" .. prefix .. name .. ".png"
        local crc = Zip.crc_of(zip, entry)
        if not crc then return nil end
        local key = string.format("%s%s-%08x", prefix:gsub("/", "_"), name, crc)
        if mem[key] then return table.unpack(mem[key]) end
        local path = dir and (dir .. "/" .. key .. ".raw")
        local f = path and io.open(path, "rb")
        if f then
            local s = f:read("a")
            f:close()
            local W, H = string.unpack("<I4I4", s)
            if #s == 8 + W * H * 4 then
                mem[key] = { W, H, s:sub(9) }
                return W, H, mem[key][3]
            end
        end
        local W, H, px = Forge.decode(Forge.unzip(Zip.read_entry(zip, entry)) or "")
        if not W then return nil end
        mem[key] = { W, H, px }
        if path then
            local out = io.open(path, "wb")
            if out then out:write(string.pack("<I4I4", W, H), px) out:close() end
        end
        return W, H, px
    end
end

-- what decides the images: one line, kept in the theme as tk_forge.txt
function Forge.key(o)
    return string.format("forge %d|%s|%.2f|%.2f|%.2f|%d|%s|%s", Forge.VERSION, o.finish, o.gloss, o.contrast,
        o.corrosion, o.seed, o.tcp and "tcp" or "-", o.mcp and "mcp" or "-")
end

-- the wear's colour on this finish: scratches and rubbed edges show the bare metal under it
-- (blank aluminium under anodizing, bright copper, ...). nil: the plate's own wear
function Forge.wear_look(o)
    local fin = Forge.finish(o.finish)
    if not fin.bare then return nil end
    return { wear = fin.bare, wear_a = fin.bare_a, style = fin.wear_style }
end

-- ---------------------------------------------------------------- the preview
-- nearest-neighbour 9-slice to w x h, as REAPER stretches. px a string with the marker ring
-- (the fixed parts read from it, the ring dropped), or a table without one and fix given
function Forge.nine(W, H, px, w, h, fix)
    local get, ox, sw, sh, L, T, Rr, B
    if type(px) == "string" then
        local function pink(at) local r, g, b = byte(px, at, at + 2) return r == 255 and g == 0 and b == 255 end
        local n = 0
        for x = 0, W - 1 do if pink(x * 4 + 1) then n = n + 1 else break end end
        L = math.max(0, n - 1)
        n = 0
        for y = 0, H - 1 do if pink(y * W * 4 + 1) then n = n + 1 else break end end
        T = math.max(0, n - 1)
        Rr, B = L, T                          -- the plates are symmetric
        ox, sw, sh = 1, W - 2, H - 2
        get = function(sx, sy) local at = (sy * W + sx) * 4 + 1 return px:sub(at, at + 3) end
    else
        L, T, Rr, B = fix[1], fix[2], fix[3], fix[4]
        ox, sw, sh = 0, W, H
        get = function(sx, sy) return px[sy * W + sx + 1] end
    end
    local function map(d, n, a, b, size)
        if d < a then return d end
        if d >= size - b then return n - (size - d) end
        return a + math.floor((d - a) * (n - a - b) / math.max(1, size - a - b))
    end
    local xs = {}
    for x = 0, w - 1 do xs[x] = map(x, sw, L, Rr, w) + ox end
    local out = {}
    for y = 0, h - 1 do
        local sy = map(y, sh, T, B, h) + ox
        for x = 0, w - 1 do out[y * w + x + 1] = get(xs[x], sy) end
    end
    return out
end

-- b over a, both tables of 4-byte strings of the same size
function Forge.over(a, b)
    local out = {}
    for i = 1, #a do
        local br, bg, bb, ba = byte(b[i], 1, 4)
        if ba == 0 then out[i] = a[i]
        elseif ba == 255 then out[i] = b[i]
        else
            local ar, ag, ab, aa = byte(a[i], 1, 4)
            local k = ba / 255
            out[i] = char(clamp(ar + (br - ar) * k), clamp(ag + (bg - ag) * k), clamp(ab + (bb - ab) * k), math.max(aa, ba))
        end
    end
    return out
end

-- the background the preview sits on, so a transparent edge shows as the panel
function Forge.flatten(px, bg)
    local out = {}
    for i = 1, #px do
        local r, g, b, a = byte(px[i], 1, 4)
        local k = a / 255
        out[i] = char(clamp(bg[1] + (r - bg[1]) * k), clamp(bg[2] + (g - bg[2]) * k), clamp(bg[3] + (b - bg[3]) * k), 255)
    end
    return concat(out)
end

-- ---------------------------------------------------------------- in the settings window
-- E: what the settings window lends (Forge.bind).
--
-- Materials: every finish is a base material (Silver, Black, Copper, ...) with one setting of
-- its own, changed in place; Save material keeps a setting under a name of its own, until
-- deleted. Each plate (track panel, mixer) uses one material: Data/TK Theme/materials.txt.
-- Silver and Black at their factory setting are the theme's own images and cost nothing; any
-- other material is drawn. The Materials page edits a draft; Apply makes it so.
local E
local ui = { sel = nil, saving = nil, picked = {} }   -- the page's own state (further down)
-- On the plates (wear, a coffee ring, graffiti): what the page shows until Apply sets it.
-- v: parameter -> the value picked; scratch, graffiti: a new pattern asked for
ui.plate = { v = {}, scratch = false, graffiti = false }
Forge.PLATE_SETTINGS = {
    { "tkPatina", "Wear", { "Off", "Light", "Used", "Road-worn" } },
    { "tkGraffiti", "Graffiti", { "Off", "Light", "Wild" } },
    { "tkGrafColours", "Graffiti colours", { "Neon", "Accent" }, needs = { "tkGraffiti" } },
    { "tkGrafSticker", "Name stickers", { "Off", "On" }, needs = { "tkGraffiti" } },
    { "tkGrafStkCol", "Sticker colour", { "Graffiti", "Track colour" }, needs = { "tkGraffiti", "tkGrafSticker" } },
}
Forge.FACTORY = { gloss = 0.4, contrast = 0.5, corrosion = 0, seed = 1832, fasten = 1 }
local FIELDS = { "finish", "gloss", "contrast", "corrosion", "seed", "fasten", "colour", "track" }
local PLATES = { { "tcp", "Track panel" }, { "mcp", "Mixer" }, { "trans", "Transport" } }

function Forge.bind(env)
    E = env
    Forge.use(env.patina.lib)
    local res = env.r.GetResourcePath() .. "/Data/TK Theme"
    Forge.file, Forge.old_file, Forge.dir = res .. "/materials.txt", res .. "/forge.txt", res .. "/forge"
end

local function new_base(finish)
    local f, own = Forge.FACTORY, Forge.finish(finish).defaults or {}
    return { finish = finish, gloss = own.gloss or f.gloss, contrast = own.contrast or f.contrast,
             corrosion = own.corrosion or f.corrosion, seed = f.seed, fasten = f.fasten, colour = 0xA0282C, track = 0 }
end

local function copy(o)
    local c = {}
    for _, k in ipairs(FIELDS) do c[k] = o[k] end
    c.fasten = c.fasten or 1
    c.colour, c.track = c.colour or 0xA0282C, c.track or 0
    return c
end

local function same(a, b)
    if (a == nil) ~= (b == nil) then return false end
    if not a then return true end
    for _, k in ipairs(FIELDS) do
        local x, y = a[k], b[k]
        if type(x) == "number" then
            if math.abs(x - y) > 0.004 then return false end
        elseif x ~= y then return false end
    end
    return true
end

-- a whole library: { bases = { [finish] = m }, saved = { [name] = m }, order = { names }, use = { tcp = id } }
local function copy_lib(l)
    local c = { bases = {}, saved = {}, order = {}, use = {} }
    for k, m in pairs(l.bases) do c.bases[k] = copy(m) end
    for k, m in pairs(l.saved) do c.saved[k] = copy(m) end
    for i, n in ipairs(l.order) do c.order[i] = n end
    for k, v in pairs(l.use) do c.use[k] = v end
    return c
end

-- an id ("base:Copper", "saved:Old copper") to its material and the name it shows
function Forge.get(lib, id)
    if not id then return nil end
    local kind, name = id:match("^(%a+):(.*)$")
    if kind == "base" then return lib.bases[name], name end
    if kind == "saved" then return lib.saved[name], name end
end

-- Silver or Black as they come: the theme's own images, nothing drawn
function Forge.factory(m)
    if not m or (m.finish ~= "Silver" and m.finish ~= "Black") then return false end
    local f = Forge.FACTORY
    return math.abs(m.gloss - f.gloss) < 0.004 and math.abs(m.contrast - f.contrast) < 0.004 and m.corrosion < 0.004
end

local function fields_line(m)
    return string.format("finish=%s gloss=%.2f contrast=%.2f corrosion=%.2f seed=%d fasten=%d colour=%06x track=%d", m.finish, m.gloss, m.contrast,
        m.corrosion, m.seed, m.fasten or 1, m.colour or 0xA0282C, m.track or 0)
end

local function parse_fields(s, m)
    for k, v in s:gmatch("(%a+)=(%S+)") do
        if k == "finish" then m.finish = Forge.finish(v).name
        elseif k == "colour" then m.colour = tonumber(v, 16) or m.colour
        elseif m[k] ~= nil then m[k] = tonumber(v) or m[k] end
    end
    return m
end

function Forge.load()
    if Forge.applied then return end
    local lib = { bases = {}, saved = {}, order = {}, use = {} }
    for _, f in ipairs(Forge.FINISHES) do lib.bases[f.name] = new_base(f.name) end
    local f = io.open(Forge.file, "rb")
    if f then
        for line in f:read("a"):gmatch("[^\r\n]+") do
            local kind, rest = line:match("^(%a+) (.*)$")
            if kind == "use" then
                local plate, id = rest:match("^([%a_]+)=(.*)$")
                if plate then lib.use[plate] = id end
            elseif kind == "base" then
                local name, fields = rest:match("^([^:]+): (.*)$")
                if name and lib.bases[name] then parse_fields(fields, lib.bases[name]) lib.bases[name].finish = name end
            elseif kind == "saved" then
                local name, fields = rest:match("^([^:]+): (.*)$")
                if name and not lib.saved[name] then
                    lib.saved[name] = parse_fields(fields, new_base("Silver"))
                    lib.order[#lib.order + 1] = name
                end
            end
        end
        f:close()
    else
        -- the proof of concept kept one material in forge.txt: it becomes its finish's setting
        local old = io.open(Forge.old_file, "rb")
        if old then
            local s = old:read("a")
            old:close()
            local m = new_base(Forge.finish(s:match("finish=([^\n]+)") or "Silver").name)
            for _, k in ipairs({ "gloss", "contrast", "corrosion", "seed" }) do
                m[k] = tonumber(s:match(k .. "=([^\n]+)") or "") or m[k]
            end
            lib.bases[m.finish] = m
            for _, plate in ipairs({ "tcp", "mcp" }) do
                if s:match(plate .. "=1") then lib.use[plate] = "base:" .. m.finish end
            end
        end
    end
    Forge.applied, Forge.draft = lib, copy_lib(lib)
end

local function save()
    E.r.RecursiveCreateDirectory(Forge.dir, 0)
    local lib, lines = Forge.applied, {}
    for _, kind in ipairs({ "tcp", "mcp", "trans", "rails", "hw_knobs", "hw_caps", "hw_brackets", "hw_screws" }) do
        if lib.use[kind] then lines[#lines + 1] = "use " .. kind .. "=" .. lib.use[kind] end
    end
    for _, f in ipairs(Forge.FINISHES) do
        local m = lib.bases[f.name]
        if not same(m, new_base(f.name)) then lines[#lines + 1] = "base " .. f.name .. ": " .. fields_line(m) end
    end
    for _, n in ipairs(lib.order) do lines[#lines + 1] = "saved " .. n .. ": " .. fields_line(lib.saved[n]) end
    local f = io.open(Forge.file, "wb")
    if f then f:write(concat(lines, "\n") .. "\n") f:close() end
end

local function param(name)
    local p = E.params()[name]
    return p and math.floor(p.value) or nil
end
local STYLE_PARAM = { tcp = "tkTcpPlate", mcp = "tkMcpPlate", trans = "tkTransPlate" }
local MAT_PARAM = { tcp = "tkTcpMat", mcp = "tkMcpMat", trans = "tkTransMat" }

-- the material a plate shows now (its Style is Material), as an id, or nil. Without a
-- material of your own on it, that is Silver or Black as the Style says
function Forge.current(kind)
    Forge.load()
    local value = param(STYLE_PARAM[kind]) or 0
    local values = Forge.KINDS[kind].values
    local plate = value == values[1] and 1 or value == values[2] and 2 or nil
    if not plate then return nil end
    local id = Forge.applied.use[kind]
    local m = Forge.get(Forge.applied, id)
    if m and Forge.base_of(m) == plate then return id end
    return plate == 1 and "base:Silver" or "base:Black"
end

-- the material a plate shows, when it is one Forge draws (not Silver or Black as they come)
local function drawn(kind)
    local id = Forge.current(kind)
    local m = Forge.get(Forge.applied, id)
    if not m or Forge.factory(m) then return nil end
    local mat = param(MAT_PARAM[kind]) or 0
    return mat > 0 and m or nil
end

-- the rails' material (an id) while Rails is Material somewhere, else nil
function Forge.rail_current()
    Forge.load()
    if (param("tkWood") or 0) ~= 3 and (param("tkMcpWood") or 0) ~= 3 then return nil end
    local id = Forge.applied.use.rails
    return Forge.get(Forge.applied, id) and id or "base:Walnut"
end

-- for the wear (TK_Theme_Patina): its colour on the plates that show a drawn material
function Forge.wear_looks()
    if not E then return nil end
    local looks
    for _, p in ipairs(PLATES) do
        local m = drawn(p[1])
        local look = m and Forge.wear_look(m)
        if look then
            looks = looks or {}
            looks[p[1]] = look
        end
    end
    return looks
end

-- how long each step took, the last Apply (Data/TK Theme/forge_log.txt), to find what is slow
local timing
local function mark(what)
    if not timing then return end
    local now = E.r.time_precise()
    timing.lines[#timing.lines + 1] = string.format("%6.2f s  %s", now - timing.last, what)
    timing.last = now
end

-- every image name of one plate's layers, at every scale, for taking them out again
local function layer_names(kind, root)
    local K, plate, rust, fasten = Forge.KINDS[kind], {}, {}, {}
    for _, sc in ipairs(Forge.SCALES) do
        plate[#plate + 1] = root .. "/" .. sc[1] .. K.plate .. "Mat.png"
        for v = 0, 9 do rust[#rust + 1] = root .. "/" .. sc[1] .. kind .. "Rust" .. v .. ".png" end
        for _, c in ipairs(Forge.CORNERS) do fasten[#fasten + 1] = root .. "/" .. sc[1] .. kind .. "Fasten" .. c .. ".png" end
    end
    return plate, rust, fasten
end

-- ---------------------------------------------------------------- without screw strips
-- The track panel's plate without its ears (Track panel page, Screw strips off; res 0.9.97):
-- the fixed part at each side (screws and groove, 20 at 100%) taken off, the plate's edge put
-- back. The image keeps WALTER's 1-pixel border, whose pink marks the fixed parts (left: the
-- top row from the left; right: the bottom row from the right); they become the edge's few
-- columns only. The mixer's plate the same, turned: its rails at the top and bottom (Mixer
-- page), cut as rows (Forge.flat_rows).
Forge.FLAT_VERSION = 1
-- per plate: its switch, Style, Plain, image prefix
Forge.FLAT = {
    { kind = "tcp", switch = "tkTcpNoEars", plate = "tkTcpPlate", plain = "tkTcpPlain", pre = "tcp" },
    { kind = "mcp", switch = "tkMcpNoEars", plate = "tkMcpPlate", plain = "tkMcpPlain", pre = "mcp", rows = true },
}

-- the image a plate shows, when it should go without its strips: nil with the switch off,
-- with no plate, or Plain (REAPER fills a box, no image). m: the drawn material (drawn(kind))
function Forge.flat_source(f, m)
    if (param(f.switch) or 0) < 1 then return nil end
    local plate = param(f.plate) or 0
    if plate < 1 or (param(f.plain) or 0) > 0 then return nil end
    if m then return f.pre .. "PlateMat" end
    return f.pre .. (plate == 2 and "PlateBlack" or "PlateSilver")
end

-- the mixer's: its top and bottom fixed parts (the rails) off, read from the left column's
-- pink from the top; the bottom one (the right column's from the bottom) is as tall
function Forge.flat_rows(W, H, px, scale)
    local pink, stride = "\255\0\255", W * 4
    local rail = 0
    while rail + 1 < H // 2 and px:sub((rail + 1) * stride + 1, (rail + 1) * stride + 3) == pink do rail = rail + 1 end
    local edge = math.max(1, math.floor(scale + 0.5)) + 1
    if rail <= edge then return H, px end
    local nh = H - 2 * (rail - edge)
    local mid = nh - 2 - 2 * edge
    return nh, px:sub(1, (1 + edge) * stride)
        .. px:sub((1 + rail) * stride + 1, (1 + rail + mid) * stride)
        .. px:sub((H - 1 - edge) * stride + 1, H * stride)
end

-- W x H RGBA (a string) at a scale → the width and pixels without the ears
function Forge.flat(W, H, px, scale)
    local pink = "\255\0\255"
    local ear = 0                               -- the fixed part's width, from the top row's pink
    while ear + 1 < W // 2 and px:sub((ear + 1) * 4 + 1, (ear + 1) * 4 + 3) == pink do ear = ear + 1 end
    local edge = math.max(1, math.floor(scale + 0.5)) + 1   -- the bevel's columns, and one more
    if ear <= edge then return W, px end         -- nothing to cut
    local nw = W - 2 * (ear - edge)
    local mid = nw - 2 - 2 * edge
    local rows = {}
    for y = 0, H - 1 do
        local at = y * W * 4
        -- the border and the left edge, the middle past the left ear, the right edge and border
        rows[y + 1] = px:sub(at + 1, at + (1 + edge) * 4)
            .. px:sub(at + (1 + ear) * 4 + 1, at + (1 + ear + mid) * 4)
            .. px:sub(at + (W - 1 - edge) * 4 + 1, at + W * 4)
    end
    -- (the marks need nothing more: WALTER reads the left fixed part from the top row's pink
    -- at the left, the right one from the bottom row's at the right, and both now span the
    -- border and the edge's columns, kept as they were)
    return nw, concat(rows)
end

-- old copies of the plates (from before a theme update) out of Data/TK Theme/forge
local function tidy_cache(zip, root)
    if not E.r.EnumerateFiles then return end
    local want = {}
    for kind in pairs(Forge.KINDS) do
        for _, base in ipairs({ "Silver", "Black", "Cardboard", "Wood", "Cork" }) do
            for _, sc in ipairs(Forge.SCALES) do
                local name = Forge.KINDS[kind].plate .. base
                local crc = E.Zip.crc_of(zip, root .. "/" .. sc[1] .. name .. ".png")
                if crc then want[string.format("%s%s-%08x.raw", sc[1]:gsub("/", "_"), name, crc)] = true end
            end
        end
    end
    local gone, i = {}, 0
    while true do
        local file = E.r.EnumerateFiles(Forge.dir, i)
        if not file then break end
        if file:match("%.raw$") and not want[file] then gone[#gone + 1] = file end
        i = i + 1
    end
    for _, file in ipairs(gone) do os.remove(Forge.dir .. "/" .. file) end
end

-- the images in the loaded look's theme as the plates need them: drawn where a plate shows a
-- drawn material and they are not there yet or differ (per plate and layer: only what
-- changed), taken out where nothing needs them any more. force: draw everything
function Forge.ensure(force)
    if not E or not E.look.current() then return false end
    Forge.load()
    local zip = E.parts.zip_path()
    local root = E.Zip.root(zip)
    if not root then return false end
    local files, reader = {}, nil
    local function out(names, key_name)
        if E.Zip.crc_of(zip, key_name) then
            for _, n in ipairs(names) do if E.Zip.crc_of(zip, n) then files[n] = false end end
            files[key_name] = false
        end
    end
    for _, p in ipairs(PLATES) do
        local kind = p[1]
        local m = drawn(kind)
        local plate_names, rust_names, fasten_names = layer_names(kind, root)
        local fname = root .. "/tk_forge_" .. kind .. "_fasten.txt"
        local pname, rname = root .. "/tk_forge_" .. kind .. "_plate.txt", root .. "/tk_forge_" .. kind .. "_rust.txt"
        if m then
            local pk = Forge.plate_key(m)
            if force or E.Zip.crc_of(zip, pname) ~= E.Zip.crc32(pk) then
                E.r.RecursiveCreateDirectory(Forge.dir, 0)
                reader = reader or Forge.reader(E.Zip, zip, root, Forge.dir)
                local made, err = Forge.plate_images(kind, m, reader, E.Zip.crc32)
                if not made then
                    E.state.msg = "Could not make the material: " .. tostring(err) .. "."
                    return false
                end
                for rel, png in pairs(made) do files[root .. "/" .. rel] = png end
                files[pname] = pk
                mark(kind .. " plate drawn")
            end
            if Forge.layered(m) then
                local rk = Forge.rust_key(m)
                if force or E.Zip.crc_of(zip, rname) ~= E.Zip.crc32(rk) then
                    for rel, png in pairs(Forge.rust_images(kind, m, E.Zip.crc32)) do files[root .. "/" .. rel] = png end
                    files[rname] = rk
                    mark(kind .. " corrosion drawn")
                end
            else
                out(rust_names, rname)
            end
            if Forge.fastened(m) then
                local fk = Forge.fasten_key(m)
                if force or E.Zip.crc_of(zip, fname) ~= E.Zip.crc32(fk) then
                    for rel, png in pairs(Forge.fasten_images(kind, Forge.FASTENINGS[m.fasten], m.seed, E.Zip.crc32)) do files[root .. "/" .. rel] = png end
                    files[fname] = fk
                    mark(kind .. " fastening drawn")
                end
            else
                out(fasten_names, fname)
            end
        else
            out(plate_names, pname)
            out(rust_names, rname)
            out(fasten_names, fname)
        end
    end
    -- the plates without their screw strips (tkTcpNoEars, tkMcpNoEars): cut from the plate shown
    for _, f in ipairs(Forge.FLAT) do
    local flat_names = {}
    for _, sc in ipairs(Forge.SCALES) do flat_names[#flat_names + 1] = root .. "/" .. sc[1] .. f.pre .. "PlateFlat.png" end
    local flname = root .. "/tk_forge_" .. f.kind .. "_flat.txt"
    local src = Forge.flat_source(f, drawn(f.kind))
    if src then
        -- the source at each scale: just drawn in this pass (still in files), or in the theme
        local key, got = { "flat " .. Forge.FLAT_VERSION .. "|" .. src }, {}
        for _, sc in ipairs(Forge.SCALES) do
            local entry = root .. "/" .. sc[1] .. src .. ".png"
            local png = files[entry]
            local crc = png and E.Zip.crc32(png) or E.Zip.crc_of(zip, entry)
            if not crc then src = nil break end
            key[#key + 1] = string.format("%08x", crc)
            got[sc[1]] = png or false
        end
        if src then
            local k = concat(key, "|")
            if force or E.Zip.crc_of(zip, flname) ~= E.Zip.crc32(k) then
                E.r.RecursiveCreateDirectory(Forge.dir, 0)
                for _, sc in ipairs(Forge.SCALES) do
                    local W, H, px
                    if got[sc[1]] then
                        W, H, px = Forge.decode(got[sc[1]])
                    else
                        reader = reader or Forge.reader(E.Zip, zip, root, Forge.dir)
                        W, H, px = reader(src, sc[1])
                    end
                    if not W then
                        E.state.msg = "Could not make the plate without screw strips: no " .. src .. " in the theme."
                        return false
                    end
                    local fw, fh, fpx = W, H, nil
                    if f.rows then
                        fh, fpx = Forge.flat_rows(W, H, px, sc[2])
                    else
                        fw, fpx = Forge.flat(W, H, px, sc[2])
                    end
                    files[root .. "/" .. sc[1] .. f.pre .. "PlateFlat.png"] = Forge.png_packed(fw, fh, fpx, E.Zip.crc32)
                end
                files[flname] = k
                mark(f.kind .. " plate without screw strips cut")
            end
        else
            out(flat_names, flname)
        end
    else
        out(flat_names, flname)
    end
    end
    -- the rails
    local rail_names = {}
    for _, sc in ipairs(Forge.SCALES) do
        for _, R in ipairs(Forge.RAILS) do rail_names[#rail_names + 1] = root .. "/" .. sc[1] .. R.name .. ".png" end
    end
    local rlname = root .. "/tk_forge_rails.txt"
    local rid = Forge.rail_current()
    local rm = rid and Forge.get(Forge.applied, rid)
    if rm then
        local key = Forge.rail_key(rm)
        if force or E.Zip.crc_of(zip, rlname) ~= E.Zip.crc32(key) then
            E.r.RecursiveCreateDirectory(Forge.dir, 0)
            reader = reader or Forge.reader(E.Zip, zip, root, Forge.dir)
            local made, err = Forge.rail_images(rm, reader, E.Zip.crc32)
            if not made then
                E.state.msg = "Could not make the rails: " .. tostring(err) .. "."
                return false
            end
            for rel, png in pairs(made) do files[root .. "/" .. rel] = png end
            files[rlname] = key
            mark("rails drawn")
        end
    else
        out(rail_names, rlname)
    end
    if reader then tidy_cache(zip, root) end
    -- the proof of concept's one key, from before plates and layers had keys of their own
    if E.Zip.crc_of(zip, root .. "/tk_forge.txt") then files[root .. "/tk_forge.txt"] = false end
    for k, v in pairs(Forge.hw_files(zip, root)) do files[k] = v end
    if next(files) == nil then return false end
    local ok, werr = E.Zip.replace(zip, files)
    if not ok then
        E.state.msg = "Could not write the material: " .. tostring(werr) .. "."
        return false
    end
    mark("handed to the zip")
    E.parts.reload()
    return true
end

-- corrosion shows on the plates that have it (one switch for both: what has none, has no images)
local function rust_param()
    local any, held = false, false
    for _, p in ipairs(PLATES) do
        local m = drawn(p[1])
        if m and Forge.layered(m) then any = true end
        if m and Forge.fastened(m) then held = true end
    end
    E.set_param("tkRust", any and 1 or 0, true)
    E.set_param("tkFasten", held and 1 or 0, true)
    local rm = Forge.get(Forge.applied, Forge.rail_current())
    E.set_param("tkRailInk", (rm and Forge.finish(rm.finish).base == 2) and 1 or 0, true)
end

-- Rails chosen on the Track panel or Mixer page (Off, Walnut, Teak, Material): the material's
-- rails drawn or taken out, and the text on them light or dark. Run inside E.together
function Forge.rails_changed()
    if not E then return end
    Forge.load()
    rust_param()
    Forge.ensure()
end

-- a plate gets a material: its Style becomes the plate the material is made from, and the
-- material switch says whether Forge draws it. Run inside E.together (one write, one reload)
local PLAIN_PARAM = { tcp = "tkTcpPlain", mcp = "tkMcpPlain", trans = "tkTransPlain" }
local function put_on(kind, id)
    local m = Forge.get(Forge.applied, id)
    if not m then return end
    Forge.applied.use[kind] = id
    local base = Forge.base_of(m)
    E.set_style(kind, base == 1 and "silver" or "black")
    local plain = Forge.finish(m.finish).plain
    -- the switch holds the Style's value it is shown with (the transport counts the other way);
    -- Plain draws nothing: REAPER fills the plate in its colour
    E.set_param(MAT_PARAM[kind], (Forge.factory(m) or plain) and 0 or Forge.KINDS[kind].values[base], true)
    local pp = PLAIN_PARAM[kind]
    E.set_param(pp, plain and (((m.track or 0) > 0 and kind ~= "trans") and 2 or 1) or 0, true)
    if kind ~= "trans" then E.set_param(pp .. "Screws", (plain and (m.fasten or 1) == 6) and 1 or 0, true) end
    if plain then
        local c = m.colour or 0xA0282C
        E.set_param(pp .. "R", (c >> 16) & 255, true)
        E.set_param(pp .. "G", (c >> 8) & 255, true)
        E.set_param(pp .. "B", c & 255, true)
    end
end

-- Material chosen on the Track panel or Mixer page: the material it had, at once
function Forge.use_now(kind, id)
    Forge.load()
    id = id or Forge.applied.use[kind] or "base:Silver"
    if not Forge.get(Forge.applied, id) then id = "base:Silver" end
    E.together(function()
        put_on(kind, id)
        Forge.draft.use[kind] = id
        save()
        rust_param()
        E.r.ThemeLayout_RefreshAll()
        Forge.ensure()
        E.patina.ensure()
    end)
    E.r.ThemeLayout_RefreshAll()
end

-- Standard or Basic chosen: the plate's material switch off, its images out of the theme
function Forge.off(kind)
    if not E then return end
    E.set_param(MAT_PARAM[kind], 0, true)
    E.set_param(PLAIN_PARAM[kind], 0, true)
    rust_param()
    Forge.ensure()
end

-- the draft becomes the materials. Plates whose material was picked under Use on get it (and
-- Material as their Style); the plates that show a changed material get it drawn again
function Forge.apply()
    Forge.load()
    local before = Forge.applied
    local draft = copy_lib(Forge.draft)
    -- a deleted material's plates fall back on the base material it was made from
    for _, p in ipairs({ PLATES[1], PLATES[2], PLATES[3], { "rails" } }) do
        local id = draft.use[p[1]]
        if id and not Forge.get(draft, id) then
            local m = Forge.get(before, id)
            draft.use[p[1]] = "base:" .. (m and m.finish or "Silver")
        end
    end
    for _, G in ipairs(Forge.HW) do
        local id = draft.use[G.key]
        if id and not Forge.get(draft, id) then
            local m = Forge.get(before, id)
            draft.use[G.key] = m and ("base:" .. m.finish) or nil
        end
    end
    timing = { last = E.r.time_precise(), lines = {} }
    local start = timing.last
    E.together(function()
        Forge.applied = draft
        save()
        for _, p in ipairs(PLATES) do
            local kind = p[1]
            local picked = draft.use[kind] ~= before.use[kind] or ui.picked[kind]
            if draft.use[kind] and (picked or Forge.current(kind)) then put_on(kind, draft.use[kind]) end
        end
        if draft.use.rails and (draft.use.rails ~= before.use.rails or ui.picked.rails) then
            local tcp_on, mcp_on = (param("tkWood") or 0) > 0, (param("tkMcpWood") or 0) > 0
            if tcp_on or not mcp_on then E.set_param("tkWood", 3, true) end
            if mcp_on or not tcp_on then E.set_param("tkMcpWood", 3, true) end
        end
        rust_param()
        -- On the plates: their switches, and new patterns where asked for
        for name, v in pairs(ui.plate.v) do E.set_param(name, v, true) end
        if ui.plate.scratch then E.patina.new_seed() end
        if ui.plate.graffiti then E.patina.graffiti_seed(true) end
        ui.plate = { v = {}, scratch = false, graffiti = false }
        mark("style and settings")
        E.r.ThemeLayout_RefreshAll()
        Forge.ensure()
        E.patina.ensure()
        mark("wear")
    end)
    mark("zip written and theme reloaded")
    E.r.ThemeLayout_RefreshAll()
    Forge.draft = copy_lib(Forge.applied)
    ui.picked = {}
    timing.lines[#timing.lines + 1] = string.format("%6.2f s  in all", E.r.time_precise() - start)
    local f = io.open(Forge.dir .. "/../forge_log.txt", "wb")
    if f then f:write(concat(timing.lines, "\n") .. "\n") f:close() end
    timing = nil
end

-- ---- theme codes (Presets > Share): the recipe of each plate's drawn material goes along,
-- so a code with copper plates gives copper plates elsewhere. Silver and Black as they come
-- need nothing: the Style says it
function Forge.code_materials()
    if not E then return nil end
    local out
    for _, p in ipairs(PLATES) do
        local m = drawn(p[1])
        local cur = Forge.get(Forge.applied, Forge.current(p[1]))
        if not m and cur and Forge.finish(cur.finish).plain and (param(PLAIN_PARAM[p[1]]) or 0) > 0 then m = cur end
        if m then
            out = out or {}
            out[p[1]] = copy(m)
            if Forge.finish(m.finish).plain then out[p[1]].seed, out[p[1]].gloss = m.colour or 0, m.track or 0 end
        end
    end
    local rm = Forge.get(Forge.applied, Forge.rail_current())
    if rm then
        out = out or {}
        out.rails = copy(rm)
    end
    for _, G in ipairs(Forge.HW) do
        local hm = Forge.get(Forge.applied, Forge.applied.use[G.key])
        if Forge.is_metal(hm) then
            out = out or {}
            out[G.key] = copy(hm)
        end
    end
    return out
end

-- a code's materials: each kept as a saved material "<finish> (shared)" and put on its
-- plate, so your own setting of that finish stays as it was. Run before Forge.ensure
function Forge.from_code(materials)
    if not E or not materials then return end
    Forge.load()
    local lib = Forge.applied
    for _, p in ipairs({ PLATES[1], PLATES[2], PLATES[3], { "rails" } }) do
        local m = materials[p[1]]
        if m and Forge.finish(m.finish).name == m.finish then
            local name = m.finish .. " (shared)"
            if not lib.saved[name] then lib.order[#lib.order + 1] = name end
            lib.saved[name] = { finish = m.finish, gloss = m.gloss, contrast = m.contrast, corrosion = m.corrosion, seed = m.seed, fasten = m.fasten or 1 }
            if Forge.finish(m.finish).plain then
                lib.saved[name].colour, lib.saved[name].track = m.seed, (m.gloss or 0) >= 0.5 and 1 or 0
                lib.saved[name].seed, lib.saved[name].gloss = 1832, 0.4
            end
            lib.use[p[1]] = "saved:" .. name
        end
    end
    -- the hardware: as the code has it, or as it comes
    for _, G in ipairs(Forge.HW) do
        local m = materials[G.key]
        if m and Forge.finish(m.finish).name == m.finish then
            local name = m.finish .. " (shared)"
            if not lib.saved[name] then lib.order[#lib.order + 1] = name end
            lib.saved[name] = { finish = m.finish, gloss = m.gloss, contrast = m.contrast, corrosion = m.corrosion, seed = m.seed, fasten = m.fasten or 1 }
            lib.use[G.key] = "saved:" .. name
        else
            lib.use[G.key] = nil
        end
    end
    save()
    Forge.draft = copy_lib(lib)
    rust_param()
end

-- ---------------------------------------------------------------- hardware
-- Knobs, fader caps, folder brackets and screws in a metal of your own (Materials page,
-- Hardware). Their shape is the part you chose; the Forge recolours the theme's own Silver
-- hardware: grey metal only, so white pointers and ticks, black skirts and the accent stay.
-- Knobs: only the cap, found per frame from its middle. parts: { part, images, the variant
-- recoloured, the variants it applies to }; theme: images in the theme itself, the first of
-- each set recoloured into all of them (their originals kept in the theme under tk_orig/)
Forge.HW = {
    { key = "hw_knobs", label = "Knobs", cap = true, parts = {
        -- knob: the part with the plate's other knob styles (0.9.97); Machined is recoloured
        -- from itself, Chicken head (ivory) keeps its own
        { "tcp_hw", { "tcp_vol_knob_stack", "tcp_pan_knob_stack", "tcp_wid_knob_stack", "tcp_fxparm_knob_stack", "envcp_knob_stack" }, "silver", { silver = true, black = true }, knob = "tcp_knob" },
        { "mcp_hw", { "mcp_vol_knob_stack", "mcp_pan_knob_stack", "mcp_wid_knob_stack" }, "silver", { silver = true, black = true }, knob = "mcp_knob" } } },
    { key = "hw_caps", label = "Fader caps", parts = {
        -- the metal caps, each recoloured from itself (Long throw, Colour cap and Wide grip keep theirs)
        { "mcp_volthumb", { "mcp_volthumb" }, "chosen", { hw = true, hw_chrome = true, hw_round = true, hw_studio = true } },
        { "mcp_pan", { "mcp_panthumb", "mcp_widththumb" }, "hw", { hw = true } } } },
    { key = "hw_brackets", label = "Brackets", theme = {
        { "tcpRackRailS", "tcpRackRailB" }, { "tcpRackEndS", "tcpRackEndB" }, { "tcpRackHeadS", "tcpRackHeadB" },
        { "mcpRackRailS", "mcpRackRailB" }, { "mcpRackEndS", "mcpRackEndB" }, { "mcpRackStartS", "mcpRackStartB" } } },
    { key = "hw_screws", label = "Screws", theme = { { "transScrew1" }, { "transScrew2" }, { "transScrew3" }, { "transScrew4" } } },
}

-- a material hardware can have: a metal
function Forge.is_metal(m)
    return m ~= nil and (Forge.finish(m.finish).group or "Metal") == "Metal"
end

local function clamp01(v) return v < 0 and 0 or (v > 1 and 1 or v) end

-- one image's pixels in the metal: px RGBA rows, W x H; cap: a stack of W x W knob frames
function Forge.hw_recolour(W, H, px, fin, m, cap)
    local n = W * H
    local wt, Ls = {}, {}
    for i = 0, n - 1 do
        local r, g, b, a = byte(px, i * 4 + 1, i * 4 + 4)
        local L = (r * 77 + g * 150 + b * 29) >> 8
        Ls[i] = L
        local w = 0
        if a > 0 then
            local mx, mn = math.max(r, g, b), math.min(r, g, b)
            w = clamp01(1 - ((mx - mn) / 255 - 0.08) * 8) * clamp01((232 - L) / 22)
        end
        wt[i] = w
    end
    if cap and H % W == 0 then
        -- the cap: lighter than the black skirt, reached from the middle of each frame
        local inside = {}
        for f = 0, H // W - 1 do
            local y0 = f * W
            local start = (y0 + W // 2) * W + W // 2
            local stack, seen = { start }, { [start] = true }
            while #stack > 0 do
                local i = stack[#stack]
                stack[#stack] = nil
                local alpha = byte(px, i * 4 + 4)
                if Ls[i] > 45 and alpha > 128 then
                    inside[i] = true
                    local x, y = i % W, i // W
                    for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
                        local nx, ny = x + d[1], y + d[2]
                        if nx >= 0 and nx < W and ny >= y0 and ny < y0 + W then
                            local j = ny * W + nx
                            if not seen[j] then seen[j] = true stack[#stack + 1] = j end
                        end
                    end
                end
            end
        end
        for i = 0, n - 1 do
            if not inside[i] then
                -- the cap's soft rim: half
                local x, y = i % W, i // W
                local rim = Ls[i] > 30 and ((x > 0 and inside[i - 1]) or (x < W - 1 and inside[i + 1])
                    or (y > 0 and inside[i - W]) or (y < H - 1 and inside[i + W]))
                wt[i] = rim and wt[i] * 0.5 or 0
            end
        end
    end
    -- the middle lightness of what changes goes onto the finish's middle colour
    local hist, total = {}, 0
    for L = 0, 255 do hist[L] = 0 end
    for i = 0, n - 1 do
        if wt[i] > 0.5 then hist[Ls[i]] = hist[Ls[i]] + 1 total = total + 1 end
    end
    local mid, sum = 128, 0
    for L = 0, 255 do
        sum = sum + hist[L]
        if total > 0 and sum >= total / 2 then mid = L break end
    end
    local lut = Forge.lut(fin, mid, plate_gloss(fin, m), m.contrast)
    local out = {}
    for i = 0, n - 1 do
        local at = i * 4 + 1
        local w = wt[i]
        if w <= 0.004 then
            out[i + 1] = px:sub(at, at + 3)
        else
            local r, g, b, a = byte(px, at, at + 3)
            local cr, cg, cb = byte(lut[Ls[i]], 1, 3)
            out[i + 1] = char(clamp(r + (cr - r) * w), clamp(g + (cg - g) * w), clamp(b + (cb - b) * w), a)
        end
    end
    return concat(out)
end

-- what the theme will hold: what this run hands over first, else the file as it is
local function now_data(zip, name)
    local p = E.Zip.pending_file and E.Zip.pending_file(zip, name)
    if p ~= nil then return p or nil end
    local data, method = E.Zip.read_entry(zip, name)
    return data and Forge.unzip(data, method or 0)
end
local function now_crc(zip, name)
    local p = E.Zip.pending_file and E.Zip.pending_file(zip, name)
    if p ~= nil then return p and E.Zip.crc32(p) or nil end
    return E.Zip.crc_of(zip, name)
end

-- the hardware's images as they should be: { [entry] = png or false }. A group's key file
-- holds what decided it and one image with its checksum: a part written over it since (a
-- Style, an accent) shows as another checksum, and the group is drawn again
-- a hardware group as it stands: its metal (or nil), what its images must be drawn for, what
-- the theme's key says they were, and whether they still are (one image per part with its
-- checksum: each must still be ours)
local function hw_state(zip, root, G)
    local function chosen(part) return E.parts.chosen[part] or E.parts.default[part] or "" end
    local m = Forge.get(Forge.applied, Forge.applied.use[G.key])
    if not Forge.is_metal(m) then m = nil end
    local stored = now_data(zip, root .. "/tk_forge_" .. G.key .. ".txt")
    local desc
    if m then
        local fin = Forge.finish(m.finish)
        local srcs = {}
        for _, p in ipairs(G.parts or {}) do srcs[#srcs + 1] = p[1] .. "=" .. chosen(p[1]) .. (p.knob and ("+" .. chosen(p.knob)) or "") end
        desc = string.format("hw %d|%s|%s|%.2f|%.2f|%s|%s", Forge.VERSION, G.key, m.finish, plate_gloss(fin, m), m.contrast,
            chosen("accent"), concat(srcs, ","))
    end
    local valid = false
    if stored and desc and stored:sub(1, #desc + 1) == desc .. "|" then
        valid = true
        for sname, scrc in stored:sub(#desc + 2):gmatch("([^;@]+)@(%x+)") do
            if sname ~= "-" and now_crc(zip, sname) ~= tonumber(scrc, 16) then valid = false end
        end
    end
    return m, desc, stored, valid
end

-- for the settings window's check at opening (parts.in_zip): a part whose images the
-- hardware's metal has recoloured, and still as drawn, is in place as it is. Without this the
-- check put the part's own images back and the metal was drawn again: two reloads each time
function Forge.hw_owns(zip, part)
    if not (E and E.parts.chosen and E.parts.read) then return false end
    Forge.load()
    local root = E.Zip.root(zip)
    if not root then return false end
    for _, G in ipairs(Forge.HW) do
        for _, p in ipairs(G.parts or {}) do
            if p[1] == part and p[4][E.parts.chosen[part] or E.parts.default[part] or ""] then
                local m, _, _, valid = hw_state(zip, root, G)
                if m and valid then return true end
            end
        end
    end
    return false
end

function Forge.hw_files(zip, root)
    local files = {}
    if not (E.parts.chosen and E.parts.read) then return files end
    local function chosen(part) return E.parts.chosen[part] or E.parts.default[part] or "" end
    for _, G in ipairs(Forge.HW) do
        local keyname = root .. "/tk_forge_" .. G.key .. ".txt"
        local m, desc, stored, valid = hw_state(zip, root, G)
        if m and not valid then
            local fin, first, samples = Forge.finish(m.finish), nil, {}
            local function sample()
                if first then samples[#samples + 1] = string.format("%s@%08x", first[1], E.Zip.crc32(first[2])) end
                first = nil
            end
            local function put(name, data)
                local W, H, px = Forge.decode(data)
                if not W then return end
                local png = Forge.png_packed(W, H, Forge.hw_recolour(W, H, px, fin, m, G.cap), E.Zip.crc32)
                files[name] = png
                first = first or { name, png }
            end
            for _, p in ipairs(G.parts or {}) do
                local on = p[4][chosen(p[1])]
                for _, img in ipairs(p[2]) do
                    for _, sc in ipairs(Forge.SCALES) do
                        local file = sc[1] .. img .. ".png"
                        local kv = p.knob and chosen(p.knob) or ""
                        if on and kv ~= "" and kv ~= "classic" then
                            local data = E.parts.read(zip, nil, p.knob, kv, file)
                            if data and kv == "machined" then put(root .. "/" .. file, data)
                            elseif data then files[root .. "/" .. file] = data end
                        elseif on then
                            local data = E.parts.read(zip, nil, p[1], p[3] == "chosen" and chosen(p[1]) or p[3], file)
                            if data then put(root .. "/" .. file, data) end
                        elseif stored then
                            -- not hardware now: the part's own images back
                            local data = E.parts.read(zip, nil, p[1], chosen(p[1]), file)
                            if data then files[root .. "/" .. file] = data end
                        end
                    end
                end
                sample()
            end
            for _, set in ipairs(G.theme or {}) do
                for _, sc in ipairs(Forge.SCALES) do
                    for _, img in ipairs(set) do
                        local name, orig = root .. "/" .. sc[1] .. img .. ".png", root .. "/tk_orig/" .. sc[1] .. img .. ".png"
                        if not now_crc(zip, orig) then files[orig] = now_data(zip, name) end
                    end
                    local src = files[root .. "/tk_orig/" .. sc[1] .. set[1] .. ".png"] or now_data(zip, root .. "/tk_orig/" .. sc[1] .. set[1] .. ".png")
                    if src then
                        local W, H, px = Forge.decode(src)
                        if W then
                            local png = Forge.png_packed(W, H, Forge.hw_recolour(W, H, px, fin, m, false), E.Zip.crc32)
                            for _, img in ipairs(set) do files[root .. "/" .. sc[1] .. img .. ".png"] = png end
                            first = first or { root .. "/" .. sc[1] .. set[1] .. ".png", png }
                        end
                    end
                end
                sample()
            end
            files[keyname] = desc .. "|" .. (#samples > 0 and concat(samples, ";") or "-@0")
        elseif not m and stored then
            -- back to as it comes
            for _, p in ipairs(G.parts or {}) do
                for _, img in ipairs(p[2]) do
                    for _, sc in ipairs(Forge.SCALES) do
                        local file = sc[1] .. img .. ".png"
                        local data = E.parts.read(zip, nil, p[1], chosen(p[1]), file)
                        if data then files[root .. "/" .. file] = data end
                    end
                end
            end
            for _, set in ipairs(G.theme or {}) do
                for _, sc in ipairs(Forge.SCALES) do
                    for _, img in ipairs(set) do
                        local orig = root .. "/tk_orig/" .. sc[1] .. img .. ".png"
                        local data = now_data(zip, orig)
                        if data then
                            files[root .. "/" .. sc[1] .. img .. ".png"] = data
                            files[orig] = false
                        end
                    end
                end
            end
            files[keyname] = false
        end
    end
    return files
end

-- after parts were written (parts.together): the hardware drawn again where they went over it
function Forge.hw_ensure()
    if not E or not E.look.current() then return false end
    Forge.load()
    local zip = E.parts.zip_path()
    local root = E.Zip.root(zip)
    if not root then return false end
    local files = Forge.hw_files(zip, root)
    if next(files) == nil then return false end
    local ok = E.Zip.replace(zip, files)
    if ok then E.parts.reload() end
    return ok
end

-- ---- presets and undo: which material is on what, with its settings
local USE_KINDS = { "tcp", "mcp", "trans", "rails", "hw_knobs", "hw_caps", "hw_brackets", "hw_screws" }

function Forge.saved_lines(lines)
    Forge.load()
    for _, kind in ipairs(USE_KINDS) do
        local id = Forge.applied.use[kind]
        local m = Forge.get(Forge.applied, id)
        if m then lines[#lines + 1] = "material:" .. kind .. "=" .. id .. "|" .. fields_line(m) end
    end
end

-- a preset's (or undo's) materials back on their plates: the same material where your
-- library still has it as it was, else kept as a saved one "<name> (<label>)". A preset
-- from before materials were kept leaves them as they are (false). Run before Forge.ensure
function Forge.from_saved(text, label)
    if not E then return false end
    Forge.load()
    local lib, got, any = Forge.applied, {}, false
    for kind, id, fields in ("\n" .. text):gmatch("[\r\n]material:([%w_]+)=([^|\r\n]+)|([^\r\n]*)") do
        any = true
        local m = parse_fields(fields, new_base("Silver"))
        local have = Forge.get(lib, id)
        if have and same(have, m) then
            got[kind] = id
        else
            local name = (id:match("^%a+:(.*)$") or m.finish) .. " (" .. label .. ")"
            if not lib.saved[name] then lib.order[#lib.order + 1] = name end
            lib.saved[name] = m
            got[kind] = "saved:" .. name
        end
    end
    if not any then return false end
    for _, kind in ipairs(USE_KINDS) do lib.use[kind] = got[kind] end
    save()
    Forge.draft = copy_lib(lib)
    ui.picked = {}
    rust_param()
    return true
end

function Forge.discard()
    Forge.draft = copy_lib(Forge.applied)
    ui.picked = {}
    ui.plate = { v = {}, scratch = false, graffiti = false }
end

-- ---- pictures: a plate in a material, made in memory
local pictures = { made = {}, queue_used = false }

local function half(tiles, w, h)
    local out = {}
    for y = 0, h // 2 - 1 do
        for x = 0, w // 2 - 1 do
            local r, g, b, a = 0, 0, 0, 0
            for _, at in ipairs({ y * 2 * w + x * 2 + 1, y * 2 * w + x * 2 + 2, (y * 2 + 1) * w + x * 2 + 1, (y * 2 + 1) * w + x * 2 + 2 }) do
                local pr, pg, pb, pa = byte(tiles[at], 1, 4)
                r, g, b, a = r + pr, g + pg, b + pb, a + pa
            end
            out[y * (w // 2) + x + 1] = char(r // 4, g // 4, b // 4, a // 4)
        end
    end
    return out
end

local function reader_now()
    local zip = E.parts.zip_path()
    local root = E.Zip.root(zip)
    if not root then return nil end
    if pictures.zip ~= zip then
        E.r.RecursiveCreateDirectory(Forge.dir, 0)
        pictures.zip, pictures.reader = zip, Forge.reader(E.Zip, zip, root, Forge.dir)
    end
    return pictures.reader
end

-- a track panel plate in material m, w x h at 100% (drawn at 200% and halved), with its
-- corrosion; as a table of 4-byte strings
local function picture(m, w, h)
    if Forge.finish(m.finish).plain then
        local tiles = {}
        local list = (m.track or 0) > 0 and { 0xC83C3C, 0x3C78DC, 0xF0C828, 0x78C85A, 0x9658D2 } or { m.colour or 0xA0282C }
        for y = 0, h - 1 do
            for x = 0, w - 1 do
                local c = list[math.floor(x * #list / w) + 1]
                tiles[#tiles + 1] = char((c >> 16) & 255, (c >> 8) & 255, c & 255, 255)
            end
        end
        return tiles
    end
    local reader = reader_now()
    if not reader then return nil end
    local fin = Forge.finish(m.finish)
    local K = Forge.KINDS.tcp
    local W, H, px = reader(K.plate .. Forge.source(fin), "200/")
    if not W then return nil end
    local plate = concat(Forge.nine(W, H, px, w * 2, h * 2))
    if not Forge.factory(m) then
        plate = Forge.recolour(w * 2, h * 2, plate, Forge.lut(fin, Forge.median(W, H, px), plate_gloss(fin, m), m.contrast), 2, fin.base == 1 and not fin.work)
    end
    local tiles = {}
    for i = 1, w * h * 4 do tiles[i] = plate:sub(i * 4 - 3, i * 4) end
    if Forge.layered(m) then
        local _, _, big = Forge.layer("tcp", m, 0)
        tiles = Forge.over(tiles, Forge.nine(K.w * 2, K.h * 2, big, w * 2, h * 2, { K.fix[1] * 2, K.fix[2] * 2, K.fix[3] * 2, K.fix[4] * 2 }))
    end
    return half(tiles, w * 2, h * 2)
end

local function image_of(tiles, w, h)
    local bg = E.UI.glass
    local png = Forge.png(w, h, Forge.flatten(tiles, { (bg >> 16) & 255, (bg >> 8) & 255, bg & 255 }), E.Zip.crc32)
    local ok, img = pcall(E.r.ImGui_CreateImageFromMem, png)
    if not ok or not img then return nil end
    E.r.ImGui_Attach(E.ctx, img)
    return img
end

local function recipe(m)
    return string.format("%s|%.2f|%.2f|%.2f|%d|%06x|%d", m.finish, m.gloss, m.contrast, m.corrosion, m.seed, m.colour or 0, m.track or 0)
end

-- the small picture of a material (120 x 28), made once; one new one per frame at most, so
-- opening the page with many materials stays smooth. nil while it waits
function Forge.thumb(m)
    if not m then return nil end
    local key = recipe(m)
    local hit = pictures.made[key]
    if hit ~= nil then return hit or nil end
    if pictures.frame == E.r.ImGui_GetFrameCount(E.ctx) then return nil end
    pictures.frame = E.r.ImGui_GetFrameCount(E.ctx)
    local tiles = picture(m, 120, 28)
    pictures.made[key] = tiles and image_of(tiles, 120, 28) or false
    return pictures.made[key] or nil
end

-- the preview of the material being edited: 500 x 84 at 100%, made again once a slider is let go
local preview = {}
local function preview_image(m)
    local key = recipe(m)
    if preview.key == key then return preview.img end
    if E.r.ImGui_IsAnyItemActive(E.ctx) and preview.img then return preview.img end
    if preview.img and E.r.ImGui_Detach then pcall(E.r.ImGui_Detach, E.ctx, preview.img) end
    preview.key, preview.img = key, nil
    local t0 = E.r.time_precise()
    local tiles = picture(m, 500, 84)
    preview.took = E.r.time_precise() - t0
    preview.img = tiles and image_of(tiles, 500, 84)
    return preview.img
end
Forge.preview_tiles = function(m) return picture(m, 500, 84) end     -- for the tests

-- ---- the page

function Forge.select(id) ui.sel = id end

local function chip(label, active, w)
    local r, ctx = E.r, E.ctx
    if active then
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), E.rgba(E.mix(E.UI.raised, E.UI.accent, 0.55)))
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), E.rgba(E.UI.ink))
    end
    local clicked = r.ImGui_Button(ctx, label, w or 0, 0)
    if active then r.ImGui_PopStyleColor(ctx, 2) end
    return clicked and not active
end

local function percent(label, id, value)
    local r, ctx = E.r, E.ctx
    E.row_label(label)
    r.ImGui_SetNextItemWidth(ctx, 280)
    local changed, v = r.ImGui_SliderInt(ctx, "##" .. id, math.floor(value * 100 + 0.5), 0, 100, "%d%%")
    return changed and v / 100 or value
end

local function soft(text, colour)
    E.r.ImGui_PushStyleColor(E.ctx, E.r.ImGui_Col_Text(), E.rgba(colour or E.UI.soft))
    E.r.ImGui_Text(E.ctx, text)
    E.r.ImGui_PopStyleColor(E.ctx)
end

local function used_on(lib, id)
    local list = {}
    for _, p in ipairs(PLATES) do
        local now = Forge.current(p[1])
        if lib.use[p[1]] == id and now == id then list[#list + 1] = p[2] end
    end
    for _, G in ipairs(Forge.HW) do
        if lib.use[G.key] == id then list[#list + 1] = G.label end
    end
    return concat(list, ", ")
end

-- one material as a tile: its picture, its name, a line under it
local function tile(id, m, name, under, under_warn)
    local r, ctx = E.r, E.ctx
    r.ImGui_BeginGroup(ctx)
    local active = ui.sel == id
    if active then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), E.rgba(E.mix(E.UI.raised, E.UI.accent, 0.55))) end
    local x = r.ImGui_GetCursorPosX(ctx)
    local img = Forge.thumb(m)
    local clicked
    if img then clicked = r.ImGui_ImageButton(ctx, "##t" .. id, img, 120, 28)
    else clicked = r.ImGui_Button(ctx, "...##t" .. id, 128, 36) end
    if active then r.ImGui_PopStyleColor(ctx) end
    local width = r.ImGui_GetItemRectSize(ctx)
    r.ImGui_SetCursorPosX(ctx, x + (width - r.ImGui_CalcTextSize(ctx, name)) / 2)
    soft(name, active and E.UI.ink or E.UI.text)
    under = under or ""
    r.ImGui_SetCursorPosX(ctx, x + (width - r.ImGui_CalcTextSize(ctx, under)) / 2)
    soft(under, under_warn and E.UI.warn or E.UI.dim)
    r.ImGui_EndGroup(ctx)
    if clicked then ui.sel = id end
    return width
end

local function tiles_row(list)
    local r, ctx = E.r, E.ctx
    local left = r.ImGui_GetCursorPosX(ctx)
    for i, t in ipairs(list) do
        if i > 1 then
            r.ImGui_SameLine(ctx, 0, 6)
            if r.ImGui_GetContentRegionAvail(ctx) < 134 then
                r.ImGui_NewLine(ctx)
                r.ImGui_SetCursorPosX(ctx, left)
            end
        end
        tile(t[1], t[2], t[3], t[4], t[5])
    end
end

-- a plate setting as the page shows it: picked, or as it is
local function plate_value(name)
    local v = ui.plate.v[name]
    if v == nil then v = param(name) or 0 end
    return v
end

local function changes()
    local a, d, out = Forge.applied, Forge.draft, {}
    for _, s in ipairs(Forge.PLATE_SETTINGS) do
        local v = ui.plate.v[s[1]]
        if v ~= nil and v ~= (param(s[1]) or 0) then out[#out + 1] = s[2] .. "  ->  " .. s[3][v + 1] end
    end
    local cof = ui.plate.v.tkCoffee
    if cof ~= nil and cof ~= (param("tkCoffee") or 0) then
        out[#out + 1] = cof > 0 and ("Coffee ring on track " .. cof) or "Coffee ring wiped off"
    end
    if ui.plate.scratch then out[#out + 1] = "New scratches" end
    if ui.plate.graffiti then out[#out + 1] = "New graffiti" end
    for _, f in ipairs(Forge.FINISHES) do
        if not same(a.bases[f.name], d.bases[f.name]) then out[#out + 1] = f.name .. " changed" end
    end
    for _, n in ipairs(d.order) do
        if not a.saved[n] then out[#out + 1] = "Saved: " .. n
        elseif not same(a.saved[n], d.saved[n]) then out[#out + 1] = n .. " changed" end
    end
    for _, n in ipairs(a.order) do
        if not d.saved[n] then out[#out + 1] = "Deleted: " .. n end
    end
    for _, p in ipairs({ PLATES[1], PLATES[2], PLATES[3], { "rails", "Rails" } }) do
        local current = p[1] == "rails" and Forge.rail_current() or (p[1] ~= "rails" and Forge.current(p[1]))
        local picked = ui.picked[p[1]] and not current
        if d.use[p[1]] ~= a.use[p[1]] or picked then
            local _, name = Forge.get(d, d.use[p[1]])
            out[#out + 1] = p[2] .. "  ->  " .. (name or "?")
        end
    end
    for _, G in ipairs(Forge.HW) do
        if d.use[G.key] ~= a.use[G.key] then
            local _, name = Forge.get(d, d.use[G.key])
            out[#out + 1] = G.label .. "  ->  " .. (name or "As now")
        end
    end
    return out
end

local function names_in(lib)
    local list = {}
    for _, f in ipairs(Forge.FINISHES) do list[#list + 1] = { "base:" .. f.name, lib.bases[f.name], f.name } end
    for _, n in ipairs(lib.order) do list[#list + 1] = { "saved:" .. n, lib.saved[n], n } end
    return list
end

function Forge.draw()
    local r, ctx = E.r, E.ctx
    Forge.load()
    E.hint_text("Pick a material and set it up, then choose which plates use it. Nothing is built until you press Apply.")
    r.ImGui_Dummy(ctx, 0, 2)
    if not E.look.current() then
        E.hint_text("Choose one of TK Theme's looks first.")
        return
    end
    local d = Forge.draft
    if not Forge.get(d, ui.sel) then ui.sel = Forge.current("tcp") or Forge.current("mcp") or "base:Silver" end

    -- the selected material's settings and preview, drawn right under the row it is in
    local function editor()
        local m, name = Forge.get(d, ui.sel)
        local fin = Forge.finish(m.finish)
        local is_base = ui.sel:match("^base:") ~= nil
        if E.begin_card(name, "forge_edit") then
            local own = fin.name == "Silver" or fin.name == "Black"
            local info = (is_base and "base material" or ("saved, from " .. m.finish))
                .. (own and ", the theme's own plate" or fin.plain and ", one flat colour, nothing drawn" or (", made from " .. Forge.source(fin)))
            local where = used_on(Forge.applied, ui.sel)
            if where ~= "" then info = info .. "   ·   used on: " .. where end
            if Forge.factory(m) then info = info .. "   ·   as it comes: the theme's own images" end
            soft(info)
            r.ImGui_Dummy(ctx, 0, 2)
            local labels = fin.labels or {}
            if fin.plain then
                E.row_label("Colour")
                local track = (m.track or 0) > 0
                if chip("Fixed colour", not track, 110) then m.track = 0 end
                r.ImGui_SameLine(ctx, 0, 2)
                if chip("Track colour", track, 110) then m.track = 1 end
                if not track then
                    E.row_label("")
                    local changed, col = r.ImGui_ColorEdit3(ctx, "##plain_colour", m.colour or 0xA0282C)
                    if changed then m.colour = col end
                end
                E.row_label("Screws")
                local screws = (m.fasten or 1) == 6
                if chip("Off", not screws, 60) then m.fasten = 1 end
                r.ImGui_SameLine(ctx, 0, 2)
                if chip("On", screws, 60) then m.fasten = 6 end
                E.hint_text("The plate in one colour, nothing drawn: knobs, glass and the rest stay as they are. Track colour: every track its own (the transport takes the fixed one). Screws: in the corners of the track panels and the mixer, in the metal chosen under Hardware.")
                goto plain_done
            end
            if labels.gloss ~= false then m.gloss = percent(labels.gloss or "Gloss", "gloss", m.gloss) end
            m.contrast = percent(labels.contrast or "Contrast", "contrast", m.contrast)
            m.corrosion = percent(Forge.CORR_LABEL[fin.corr], "corr", m.corrosion)
            if fin.fastens then
                E.row_label("Fastening")
                for i, name in ipairs(Forge.FASTENINGS) do
                    if i > 1 then r.ImGui_SameLine(ctx, 0, 2) end
                    if chip(name, (m.fasten or 1) == i) then m.fasten = i end
                end
            end
            E.row_label("Pattern")
            r.ImGui_Text(ctx, tostring(m.seed))
            r.ImGui_SameLine(ctx)
            if r.ImGui_Button(ctx, "New pattern") then m.seed = math.floor(r.time_precise() * 1000) % 999983 + 1 end
            ::plain_done::
            r.ImGui_Dummy(ctx, 0, 2)
            r.ImGui_SetCursorPosX(ctx, E.LABEL_W)
            if is_base then
                if r.ImGui_Button(ctx, "Reset") then d.bases[m.finish] = new_base(m.finish) end
            else
                if r.ImGui_Button(ctx, "Delete") then
                    d.saved[name] = nil
                    for i, n in ipairs(d.order) do if n == name then table.remove(d.order, i) break end end
                    ui.sel = "base:" .. m.finish
                end
            end
            r.ImGui_SameLine(ctx)
            if ui.saving then
                r.ImGui_SetNextItemWidth(ctx, 200)
                local changed, text = r.ImGui_InputText(ctx, "##forge_name", ui.saving)
                if changed then ui.saving = text:gsub("[:=\r\n]", "") end
                r.ImGui_SameLine(ctx)
                local nm = (ui.saving or ""):match("^%s*(.-)%s*$")
                local taken = d.saved[nm] ~= nil
                if r.ImGui_Button(ctx, "Save") and nm ~= "" and not taken then
                    local c = copy(m)
                    d.saved[nm] = c
                    d.order[#d.order + 1] = nm
                    ui.sel, ui.saving = "saved:" .. nm, nil
                end
                r.ImGui_SameLine(ctx)
                if r.ImGui_Button(ctx, "Cancel") then ui.saving = nil end
                if taken then r.ImGui_SameLine(ctx) soft("that name is taken", E.UI.warn) end
            else
                if r.ImGui_Button(ctx, "Save material...") then ui.saving = name .. " 2" end
                r.ImGui_SameLine(ctx)
                E.hint_text(is_base and "Reset: back to how " .. name .. " comes." or "Delete: plates that use it go back to " .. m.finish .. ".")
            end
            r.ImGui_EndChild(ctx)
        end
        r.ImGui_Dummy(ctx, 0, 2)

        if E.begin_card("Preview", "forge_prev") then
            local img = preview_image(m)
            if img then
                r.ImGui_Image(ctx, img, 500, 84)
                E.hint_text(string.format("100%%, a track 84 px high (drawn in %.1f s). Here only: the theme is not touched until Apply.", preview.took or 0))
            else
                E.hint_text("No preview: the plates were not found in the theme.")
            end
            r.ImGui_EndChild(ctx)
        end
        r.ImGui_Dummy(ctx, 0, 2)

    end

    if E.begin_card("Materials", "forge_lib") then
        for _, group in ipairs(Forge.GROUPS) do
            soft(group == "Metal" and "Metals" or group)
            local bases = {}
            for _, f in ipairs(Forge.FINISHES) do
                if (f.group or "Metal") == group then
                    local id = "base:" .. f.name
                    local where = used_on(Forge.applied, id)
                    local changed = not same(d.bases[f.name], new_base(f.name))
                    bases[#bases + 1] = { id, d.bases[f.name], f.name, where ~= "" and ("used: " .. where) or (changed and "changed" or ""), where ~= "" }
                end
            end
            tiles_row(bases)
            r.ImGui_Dummy(ctx, 0, 2)
            local sel = ui.sel:match("^base:(.*)$")
            if sel and (Forge.finish(sel).group or "Metal") == group then editor() end
        end
        r.ImGui_Dummy(ctx, 0, 4)
        soft("Saved")
        if #d.order == 0 then
            E.hint_text("None yet. Save material... keeps a setting under a name of its own.")
        else
            local saved = {}
            for _, n in ipairs(d.order) do
                local id = "saved:" .. n
                local where = used_on(Forge.applied, id)
                saved[#saved + 1] = { id, d.saved[n], n, where ~= "" and ("used: " .. where) or "", where ~= "" }
            end
            tiles_row(saved)
            if ui.sel:match("^saved:") then
                r.ImGui_Dummy(ctx, 0, 2)
                editor()
            end
        end
        r.ImGui_EndChild(ctx)
    end
    r.ImGui_Dummy(ctx, 0, 2)

    if E.begin_card("Use on", "forge_use") then
        local all = names_in(d)
        for _, p in ipairs(PLATES) do
            local kind = p[1]
            local id = d.use[kind] or Forge.current(kind)
            local _, shown = Forge.get(d, id)
            E.row_label(p[2])
            local img = Forge.thumb(Forge.get(d, id))
            if img then
                r.ImGui_Image(ctx, img, 60, 14)
                r.ImGui_SameLine(ctx)
            end
            r.ImGui_SetNextItemWidth(ctx, 200)
            if r.ImGui_BeginCombo(ctx, "##use_" .. kind, shown or "Choose...") then
                for _, it in ipairs(all) do
                    local timg = Forge.thumb(it[2])
                    if timg then
                        r.ImGui_Image(ctx, timg, 60, 14)
                        r.ImGui_SameLine(ctx)
                    end
                    if r.ImGui_Selectable(ctx, it[3] .. "##" .. it[1], it[1] == id) then
                        d.use[kind] = it[1]
                        ui.picked[kind] = true
                    end
                end
                r.ImGui_EndCombo(ctx)
            end
            if not Forge.current(kind) then
                r.ImGui_SameLine(ctx)
                soft(ui.picked[kind] and "its Style becomes Material on Apply"
                    or "Style is not Material now: pick a material here to make it so", ui.picked[kind] and E.UI.warn or E.UI.dim)
            end
        end
        -- the rails: beside the track panels (and the master and envelope lanes), the mixer's armrest
        do
            local id = d.use.rails or Forge.rail_current() or "base:Walnut"
            local rm, shown = Forge.get(d, id)
            E.row_label("Rails")
            local img = Forge.thumb(rm)
            if img then
                r.ImGui_Image(ctx, img, 60, 14)
                r.ImGui_SameLine(ctx)
            end
            r.ImGui_SetNextItemWidth(ctx, 200)
            if r.ImGui_BeginCombo(ctx, "##use_rails", shown or "Choose...") then
                for _, it in ipairs(all) do
                    if Forge.finish(it[2].finish).plain then goto next_rail end
                    local timg = Forge.thumb(it[2])
                    if timg then
                        r.ImGui_Image(ctx, timg, 60, 14)
                        r.ImGui_SameLine(ctx)
                    end
                    if r.ImGui_Selectable(ctx, it[3] .. "##r" .. it[1], it[1] == id) then
                        d.use.rails = it[1]
                        ui.picked.rails = true
                    end
                    ::next_rail::
                end
                r.ImGui_EndCombo(ctx)
            end
            if not Forge.rail_current() then
                r.ImGui_SameLine(ctx)
                soft(ui.picked.rails and "Rails become Material on Apply"
                    or "Rails are not Material now: pick a material here to make them so", ui.picked.rails and E.UI.warn or E.UI.dim)
            end
        end
        r.ImGui_EndChild(ctx)
    end
    r.ImGui_Dummy(ctx, 0, 2)

    if E.begin_card("Hardware", "forge_hw") then
        local metals = {}
        for _, it in ipairs(names_in(d)) do
            if Forge.is_metal(it[2]) then metals[#metals + 1] = it end
        end
        local function chosen(part) return E.parts.chosen[part] or E.parts.default[part] or "" end
        for _, G in ipairs(Forge.HW) do
            local id = d.use[G.key]
            local m, shown = Forge.get(d, id)
            E.row_label(G.label)
            local img = m and Forge.thumb(m)
            if img then
                r.ImGui_Image(ctx, img, 60, 14)
                r.ImGui_SameLine(ctx)
            end
            r.ImGui_SetNextItemWidth(ctx, 200)
            if r.ImGui_BeginCombo(ctx, "##" .. G.key, shown or "As now") then
                if r.ImGui_Selectable(ctx, "As now##" .. G.key, id == nil) then d.use[G.key] = nil end
                for _, it in ipairs(metals) do
                    local timg = Forge.thumb(it[2])
                    if timg then
                        r.ImGui_Image(ctx, timg, 60, 14)
                        r.ImGui_SameLine(ctx)
                    end
                    if r.ImGui_Selectable(ctx, it[3] .. "##" .. G.key .. it[1], it[1] == id) then d.use[G.key] = it[1] end
                end
                r.ImGui_EndCombo(ctx)
            end
            -- where the shape chosen isn't hardware, there is nothing to colour
            if id and G.parts then
                local any = false
                for _, p in ipairs(G.parts) do if p[4][chosen(p[1])] then any = true end end
                if not any then
                    r.ImGui_SameLine(ctx)
                    soft(G.key == "hw_knobs" and "shows with Style Material (its hardware knobs)"
                        or "shows with the Hardware fader handle", E.UI.dim)
                end
            end
            if G.key == "hw_knobs" then
                r.ImGui_SameLine(ctx, 0, 12)
                if r.ImGui_Button(ctx, "Same for all") then
                    for _, H in ipairs(Forge.HW) do d.use[H.key] = id end
                end
            end
        end
        E.hint_text("Knobs and caps keep their shape (the parts you chose); only the metal changes. Screws: the transport's. The mute, solo and record keys keep their colours.")
        r.ImGui_EndChild(ctx)
    end
    r.ImGui_Dummy(ctx, 0, 2)

    -- wear, a coffee ring and graffiti on whatever plate shows: picked here, drawn on Apply
    if E.begin_card("On the plates", "forge_on") then
        if (param("tkTcpPlate") or 0) == 0 and (param("tkMcpPlate") or 0) == 0 then
            E.hint_text("With a plate on the track panel or the mixer (their Style: Material).")
        else
            local function pick(name, i)
                ui.plate.v[name] = (i ~= (param(name) or 0)) and i or nil
            end
            for _, s in ipairs(Forge.PLATE_SETTINGS) do
                local shown = true
                for _, need in ipairs(s.needs or {}) do if plate_value(need) == 0 then shown = false end end
                if shown then
                    E.row_label(s[2])
                    local now = plate_value(s[1])
                    for i, label in ipairs(s[3]) do
                        if i > 1 then r.ImGui_SameLine(ctx, 0, 2) end
                        if chip(label .. "##" .. s[1], now == i - 1, 96) then pick(s[1], i - 1) end
                    end
                    if s[1] == "tkPatina" and now > 0 then
                        E.row_label("")
                        if r.ImGui_Button(ctx, "New scratches") then ui.plate.scratch = true end
                        if ui.plate.scratch then r.ImGui_SameLine(ctx) soft("new ones on Apply", E.UI.warn) end
                        -- the coffee ring, under the wear
                    end
                    if s[1] == "tkPatina" then
                        E.row_label("Coffee ring")
                        local cof = plate_value("tkCoffee")
                        if cof > 0 then
                            r.ImGui_AlignTextToFramePadding(ctx)
                            r.ImGui_Text(ctx, "On track " .. cof)
                            r.ImGui_SameLine(ctx, 0, 8)
                        end
                        if r.ImGui_Button(ctx, cof > 0 and "Spill again" or "Spill") then pick("tkCoffee", E.patina.spill()) end
                        if cof > 0 then
                            r.ImGui_SameLine(ctx, 0, 2)
                            if r.ImGui_Button(ctx, "Wipe off") then pick("tkCoffee", 0) end
                        end
                    end
                end
            end
            if plate_value("tkGraffiti") > 0 then
                E.row_label("")
                if r.ImGui_Button(ctx, "New graffiti") then ui.plate.graffiti = true end
                if ui.plate.graffiti then r.ImGui_SameLine(ctx) soft("new graffiti on Apply", E.UI.warn) end
            end
        end
        E.hint_text("For the track panel and the mixer together. Like the rest of this page: drawn on Apply.")
        r.ImGui_EndChild(ctx)
    end
    r.ImGui_Dummy(ctx, 0, 6)

    local list = changes()
    if #list > 0 then
        soft(#list == 1 and "1 change waiting" or (#list .. " changes waiting"), E.UI.warn)
        r.ImGui_TextWrapped(ctx, concat(list, "   ·   "))
        E.hint_text("Only the images that changed are drawn again, then the theme reloads once.")
        if r.ImGui_Button(ctx, "Discard") then Forge.discard() end
        r.ImGui_SameLine(ctx)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), E.rgba(E.UI.accent))
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), E.rgba(0xFFFFFF))
        if r.ImGui_Button(ctx, "  Apply  ") then Forge.apply() end
        r.ImGui_PopStyleColor(ctx, 2)
    end
end

return Forge
