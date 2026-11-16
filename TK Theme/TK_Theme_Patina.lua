-- @noindex
-- Wear on the plates (Track panel and Mixer pages, Wear) and a coffee ring on one track.
-- Nothing of it ships: the settings window draws it here, from your own seed, so no two
-- users have the same scratches. Three variants per plate, which the theme picks by the
-- track's number; the images stretch like the plates (a pink marker ring, fixed corners).
-- PNGs go out through TK_Theme_Plate's writer.
local Patina = {}

-- the plates' sizes at 100% and their fixed borders (left, top, right, bottom)
Patina.KINDS = {
    tcp = { w = 300, h = 96, fix = { 30, 22, 30, 22 } },
    mcp = { w = 100, h = 320, fix = { 0, 40, 0, 40 } },
}
Patina.COFFEE = { tcp = 112, mcp = 96 }
local SCALES = { { "", 1 }, { "150/", 1.5 }, { "200/", 2 } }

-- per plate: the colour of worn metal and of a dried coffee ring, and how strong
local LOOK = {
    Black = { wear = { 176, 180, 186 }, wear_a = 1.0, coffee = { 190, 140, 88 }, coffee_a = 0.62 },
    Silver = { wear = { 74, 70, 62 }, wear_a = 0.8, coffee = { 112, 70, 34 }, coffee_a = 0.72 },
}

-- a small random generator of its own (xorshift), so a seed always gives the same wear
local function rng(seed)
    local s = (seed * 2654435761) % 4294967296
    if s == 0 then s = 1 end
    local self = {}
    function self.next()
        s = s ~ ((s << 13) & 0xFFFFFFFF)
        s = s ~ (s >> 17)
        s = s ~ ((s << 5) & 0xFFFFFFFF)
        return s / 4294967296
    end
    function self.uni(a, b) return a + (b - a) * self.next() end
    function self.int(a, b) return math.floor(a + (b - a + 1) * self.next()) end
    return self
end

local function canvas(W, H)
    local A = {}
    for i = 1, W * H do A[i] = 0 end
    return A
end

-- a thick antialiased segment into A (keeps the larger value)
local function segment(A, W, H, x0, y0, x1, y1, width, v)
    local hw = width / 2
    local xa, xb = math.max(0, math.floor(math.min(x0, x1) - hw - 1)), math.min(W - 1, math.ceil(math.max(x0, x1) + hw + 1))
    local ya, yb = math.max(0, math.floor(math.min(y0, y1) - hw - 1)), math.min(H - 1, math.ceil(math.max(y0, y1) + hw + 1))
    local dx, dy = x1 - x0, y1 - y0
    local L2 = dx * dx + dy * dy
    for y = ya, yb do
        local base = y * W + 1
        for x = xa, xb do
            local px, py = x + 0.5 - x0, y + 0.5 - y0
            local t = L2 > 0 and math.max(0, math.min(1, (px * dx + py * dy) / L2)) or 0
            local ex, ey = px - t * dx, py - t * dy
            local c = hw + 0.5 - math.sqrt(ex * ex + ey * ey)
            if c > 0 then
                c = math.min(1, c) * v
                if c > A[base + x] then A[base + x] = c end
            end
        end
    end
end

local function disc(A, W, H, cx, cy, rad, v)
    segment(A, W, H, cx, cy, cx, cy, rad * 2, v)
end

-- a gaussian-like blur: three box passes each way. The clamped neighbours are looked up in
-- tables made once, which keeps math.min and math.max out of the inner loops
local function blur(A, W, H, sigma)
    local r = math.max(1, math.floor(sigma * 0.85 + 0.5))
    local n = 2 * r + 1
    local addX, subX, addY, subY = {}, {}, {}, {}
    for x = 0, W - 1 do
        addX[x] = (x + r + 1 > W - 1 and W - 1 or x + r + 1) + 1
        subX[x] = (x - r < 0 and 0 or x - r) + 1
    end
    for y = 0, H - 1 do
        addY[y] = (y + r + 1 > H - 1 and H - 1 or y + r + 1) * W + 1
        subY[y] = (y - r < 0 and 0 or y - r) * W + 1
    end
    local tmp = {}
    for _ = 1, 3 do
        for y = 0, H - 1 do                     -- across
            local base = y * W
            local sum = 0
            for x = -r, r do sum = sum + A[base + (x < 0 and 0 or x > W - 1 and W - 1 or x) + 1] end
            for x = 0, W - 1 do
                tmp[base + x + 1] = sum / n
                sum = sum + A[base + addX[x]] - A[base + subX[x]]
            end
        end
        for x = 0, W - 1 do                     -- down
            local sum = 0
            for y = -r, r do sum = sum + tmp[(y < 0 and 0 or y > H - 1 and H - 1 or y) * W + x + 1] end
            for y = 0, H - 1 do
                A[y * W + x + 1] = sum / n
                sum = sum + tmp[addY[y] + x] - tmp[subY[y] + x]
            end
        end
    end
end

-- A (W x H) made smaller to w x h, each new pixel the mean of what it covers
local function weights(n, m)
    local f, list = n / m, {}
    for d = 0, m - 1 do
        local s0, s1 = d * f, (d + 1) * f
        local row = {}
        for sx = math.floor(s0), math.min(n - 1, math.ceil(s1) - 1) do
            local u = math.min(s1, sx + 1) - math.max(s0, sx)
            if u > 0 then row[#row + 1] = { sx, u / f } end
        end
        list[d + 1] = row
    end
    return list
end

local function shrink(A, W, H, w, h)
    local cols, rows = weights(W, w), weights(H, h)
    local tmp = {}
    for y = 0, H - 1 do
        local base = y * W + 1
        for x = 1, w do
            local sum = 0
            for _, c in ipairs(cols[x]) do sum = sum + A[base + c[1]] * c[2] end
            tmp[y * w + x] = sum
        end
    end
    local out = {}
    for y = 1, h do
        local row = rows[y]
        for x = 1, w do
            local sum = 0
            for _, r in ipairs(row) do sum = sum + tmp[r[1] * w + x] * r[2] end
            out[(y - 1) * w + x] = sum
        end
    end
    return out
end

-- RGBA pixels of one colour, A times strength as alpha
local function compose(W, H, A, col, k)
    local out = {}
    local head = string.char(col[1], col[2], col[3])
    local cache = {}
    for i = 1, W * H do
        local a = math.floor(math.min(1, A[i] * k) * 255 + 0.5)
        if a <= 0 then
            out[i] = "\0\0\0\0"
        else
            local c = cache[a]
            if not c then c = head .. string.char(a) cache[a] = c end
            out[i] = c
        end
    end
    return out
end

-- the marker ring REAPER reads: an empty 1 px border, pink runs for the fixed parts
local function ring(px, W, H, fix, s)
    for x = 0, W - 1 do px[x + 1], px[(H - 1) * W + x + 1] = "\0\0\0\0", "\0\0\0\0" end
    for y = 0, H - 1 do px[y * W + 1], px[y * W + W] = "\0\0\0\0", "\0\0\0\0" end
    local pink = "\255\0\255\255"
    local L, T, R, B = math.floor(fix[1] * s + 0.5), math.floor(fix[2] * s + 0.5), math.floor(fix[3] * s + 0.5), math.floor(fix[4] * s + 0.5)
    for i = 0, L do px[i + 1] = pink end
    for i = 0, T do px[i * W + 1] = pink end
    for i = 0, R do px[(H - 1) * W + (W - 1 - i) + 1] = pink end
    for i = 0, B do px[(H - 1 - i) * W + W] = pink end
end

-- one plate's wear, grade 1..3, variant v (0..2), at scale s: its coverage and strength
function Patina.wear(kind, plate, grade, seed, v, s)
    local K, C = Patina.KINDS[kind], LOOK[plate]
    local W, H = math.floor(K.w * s + 0.5), math.floor(K.h * s + 0.5)
    local R = rng(seed * 7 + v * 131 + (kind == "mcp" and 977 or 0))
    -- edges and corners rubbed to bare metal
    local edge = canvas(W, H)
    local horizontal = kind == "tcp"
    for _ = 1, 14 * grade do
        local side = R.int(1, 4)
        local len = (horizontal and R.uni(8, 40) or R.uni(4, 18)) * grade / 2
        local width, val = R.uni(1, 3) * s, R.uni(60, 160) / 255
        if side <= 2 then
            local x, y = R.uni(0, K.w), side == 1 and 1 or K.h - 1
            segment(edge, W, H, x * s, y * s, (x + len) * s, y * s, width, val)
        else
            local x, y = side == 3 and 1 or K.w - 1, R.uni(0, K.h)
            segment(edge, W, H, x * s, y * s, x * s, (y + len * 0.6) * s, width, val)
        end
    end
    local cr = (5 + 4 * grade) * s
    for _, c in ipairs({ { 0, 0 }, { W, 0 }, { 0, H }, { W, H } }) do disc(edge, W, H, c[1], c[2], cr, (90 + 25 * grade) / 255) end
    blur(edge, W, H, 1.6 * s)
    -- long fine scratches, mostly along the plate, and dust
    local fine = canvas(W, H)
    for _ = 1, ({ 3, 6, 11 })[grade] do
        local x, y = R.uni(0, K.w), R.uni(0, K.h)
        local ang = (R.next() + R.next() + R.next() - 1.5) * 0.6 + (R.next() < 0.5 and math.pi or 0)
        if not horizontal then ang = ang + math.pi / 2 * (R.next() < 0.6 and 1 or 0) end
        local len, bend, val = R.uni(40, 150), R.uni(-0.2, 0.2), R.uni(60, 120) / 255
        local px, py = x, y
        for i = 1, 11 do
            local t = i / 11
            local nx, ny = x + math.cos(ang + t * bend) * len * t, y + math.sin(ang) * len * t
            segment(fine, W, H, px * s, py * s, nx * s, ny * s, 0.7 * s, val)
            px, py = nx, ny
        end
    end
    for _ = 1, 6 * grade do
        disc(fine, W, H, R.uni(0, W), R.uni(0, H), R.uni(0.25, 0.55) * s, R.uni(50, 120) / 255)
    end
    for i = 1, W * H do if fine[i] > edge[i] then edge[i] = fine[i] end end
    return W, H, edge, (0.30 + 0.10 * grade) * C.wear_a
end

-- wear on cardboard (a plate of your own in board, TK_Theme_Forge): no scratches, but edges
-- frayed and rubbed to the lighter fibre, short fibres standing up along them, and soft
-- scuffed patches near the edges and corners. Same sizes, grades and returns as Patina.wear
function Patina.wear_paper(kind, plate, grade, seed, v, s)
    local K, C = Patina.KINDS[kind], LOOK[plate]
    local W, H = math.floor(K.w * s + 0.5), math.floor(K.h * s + 0.5)
    local R = rng(seed * 5 + v * 157 + (kind == "mcp" and 613 or 0) + 29)
    local A = canvas(W, H)
    -- the rubbed edge: many short soft strokes hugging all four edges
    for _ = 1, 26 * grade do
        local side = R.int(1, 4)
        local len = R.uni(6, 22) * (0.6 + grade * 0.3)
        local width, val = R.uni(2.0, 4.5) * s, R.uni(120, 220) / 255
        local inset = R.uni(0.5, 2.0)
        if side <= 2 then
            local x, y = R.uni(0, K.w), side == 1 and inset or K.h - inset
            segment(A, W, H, x * s, y * s, (x + len) * s, y * s, width, val)
        else
            local x, y = side == 3 and inset or K.w - inset, R.uni(0, K.h)
            segment(A, W, H, x * s, y * s, x * s, (y + len * 0.5) * s, width, val)
        end
    end
    -- corners worn round
    local cr = (4 + 3 * grade) * s
    for _, c in ipairs({ { 0, 0 }, { W, 0 }, { 0, H }, { W, H } }) do disc(A, W, H, c[1], c[2], cr, (110 + 30 * grade) / 255) end
    -- soft scuffs near the edges
    for _ = 1, 3 + 3 * grade do
        local near = R.next() < 0.5
        local x = near and (R.next() < 0.5 and R.uni(2, 14) or K.w - R.uni(2, 14)) or R.uni(0, K.w)
        local y = near and R.uni(0, K.h) or (R.next() < 0.5 and R.uni(2, 12) or K.h - R.uni(2, 12))
        disc(A, W, H, x * s, y * s, R.uni(3, 8) * s, R.uni(70, 140) / 255)
    end
    blur(A, W, H, 1.4 * s)
    -- fibres standing up from the edge: short thin hairs, kept sharp
    local hair = canvas(W, H)
    for _ = 1, 40 * grade do
        local side = R.int(1, 4)
        local len = R.uni(1.0, 2.6)
        local ang = R.uni(-0.6, 0.6)
        local x, y, dx, dy
        if side == 1 then x, y, dx, dy = R.uni(0, K.w), 0.4, math.sin(ang), math.cos(ang)
        elseif side == 2 then x, y, dx, dy = R.uni(0, K.w), K.h - 0.4, math.sin(ang), -math.cos(ang)
        elseif side == 3 then x, y, dx, dy = 0.4, R.uni(0, K.h), math.cos(ang), math.sin(ang)
        else x, y, dx, dy = K.w - 0.4, R.uni(0, K.h), -math.cos(ang), math.sin(ang) end
        segment(hair, W, H, x * s, y * s, (x + dx * len) * s, (y + dy * len) * s, 0.6 * s, R.uni(170, 240) / 255)
    end
    for i = 1, W * H do if hair[i] > A[i] then A[i] = hair[i] end end
    return W, H, A, (0.30 + 0.10 * grade) * C.wear_a
end

-- a mug's ring: a sharp dark rim fading inward, a faint inside, part of a second print and
-- a drop beside it, all worked out per pixel
function Patina.coffee(kind, plate, seed, s)
    local C = LOOK[plate]
    local size = Patina.COFFEE[kind]
    local N = math.floor(size * s + 0.5)
    local R = rng(seed * 3 + (kind == "mcp" and 51 or 17))
    local function wobble()
        local ph, out = {}, {}
        for k = 1, 5 do ph[k] = R.uni(0, 6.2832) end
        return function(t)
            local v = 0
            for k = 1, 5 do v = v + 0.02 / k * math.sin((k + 1) * t + ph[k]) end
            return 1 + v
        end
    end
    local function thickness()
        local ph = {}
        for k = 1, 4 do ph[k] = R.uni(0, 6.2832) end
        return function(t)
            local v = 0
            for k = 1, 4 do v = v + math.sin(k * t + ph[k]) / (k + 1) end
            return 0.65 + 0.35 * v
        end
    end
    local c = N / 2
    local prints = {
        { x = c, y = c, r = N * 0.40, rim = N * 0.035, fill = 22 / 255, w = wobble(), t = thickness() },
        { x = c + N * 0.10, y = c - N * 0.06, r = N * 0.40, rim = N * 0.025, fill = 0, w = wobble(), t = thickness(),
          from = R.uni(0, 6.2832), arc = 0.4 * 6.2832 },
    }
    local drop = kind == "tcp" and { x = c + N * 0.29, y = c + N * 0.29, r = N * 0.03 } or nil
    local A = {}
    for y = 0, N - 1 do
        for x = 0, N - 1 do
            local v = 0
            for _, p in ipairs(prints) do
                local dx, dy = x + 0.5 - p.x, y + 0.5 - p.y
                local dist = math.sqrt(dx * dx + dy * dy)
                local t = math.atan(dy, dx)
                local edge = p.r * p.w(t)
                local inside = edge - dist
                if inside > -1 then
                    local cover = math.min(1, inside + 1)      -- the sharp outer edge
                    local rim = math.exp(-math.max(0, inside) / (p.rim * p.t(t))) * (190 / 255) * p.t(t)
                    local here = cover * math.max(rim, p.fill)
                    if p.arc then
                        local a = (t - p.from) % 6.2832
                        local soft = math.min(a / 0.6, (p.arc - a) / 0.6)
                        here = here * math.max(0, math.min(1, soft))
                    end
                    if here > v then v = here end
                end
            end
            if drop then
                local dx, dy = x + 0.5 - drop.x, y + 0.5 - drop.y
                local d = drop.r + 0.5 - math.sqrt(dx * dx + dy * dy)
                if d > 0 then v = math.max(v, math.min(1, d) * 110 / 255) end
            end
            A[y * N + x + 1] = v
        end
    end
    return N, N, A, C.coffee_a
end

-- A PNG, deflated with the fixed codes: bytes as literals, runs of one byte as a match one
-- back. Wear is mostly empty, so this is a fraction of a stored PNG and quick to write.
local LEN_BASE = { 3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258 }
local LEN_EXTRA = { 0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0 }
local LEN_CODE = {}           -- length 3..258 -> { symbol, extra bits, extra value }
for i = 1, #LEN_BASE - 1 do
    for n = LEN_BASE[i], LEN_BASE[i] + (1 << LEN_EXTRA[i]) - 1 do
        if n <= 257 then LEN_CODE[n] = { 256 + i, LEN_EXTRA[i], n - LEN_BASE[i] } end
    end
end
LEN_CODE[258] = { 285, 0, 0 }
local function reversed(code, bits)
    local out = 0
    for _ = 1, bits do
        out = (out << 1) | (code & 1)
        code = code >> 1
    end
    return out
end
local SYM = {}                -- symbol -> { code with its bits reversed, length }
for v = 0, 287 do
    local code, bits
    if v <= 143 then code, bits = 0x30 + v, 8
    elseif v <= 255 then code, bits = 0x190 + v - 144, 9
    elseif v <= 279 then code, bits = v - 256, 7
    else code, bits = 0xC0 + v - 280, 8 end
    SYM[v] = { reversed(code, bits), bits }
end

local function deflate(raw)
    local out, acc, nbits = {}, 0, 0
    local function put(value, bits)
        acc = acc | (value << nbits)
        nbits = nbits + bits
        while nbits >= 8 do
            out[#out + 1] = string.char(acc & 0xFF)
            acc = acc >> 8
            nbits = nbits - 8
        end
    end
    local function sym(v) local c = SYM[v] put(c[1], c[2]) end
    local a, b = 1, 0
    put(1, 1)                 -- the last block
    put(1, 2)                 -- fixed codes
    local i, n = 1, #raw
    while i <= n do
        local c = raw:byte(i)
        -- how far this byte repeats
        local j = i + 1
        if c == 0 then
            j = raw:find("[^%z]", i + 1) or n + 1
        else
            while j <= n and j - i < 259 and raw:byte(j) == c do j = j + 1 end
        end
        sym(c)
        a = (a + c) % 65521
        b = (b + a) % 65521
        local rest = j - i - 1
        if rest >= 3 then
            -- adler over the run in one go: a grows by c each byte
            b = (b + rest * a + c * (rest * (rest + 1) // 2)) % 65521
            a = (a + rest * c) % 65521
            while rest >= 3 do
                local len = math.min(258, rest)
                if rest - len > 0 and rest - len < 3 then len = rest - 3 end
                local L = LEN_CODE[len]
                sym(L[1])
                if L[2] > 0 then put(L[3], L[2]) end
                put(0, 5)     -- distance 1: code 0, no extra bits
                rest = rest - len
            end
        end
        for _ = 1, rest do
            sym(c)
            a = (a + c) % 65521
            b = (b + a) % 65521
        end
        i = j
    end
    sym(256)
    if nbits > 0 then out[#out + 1] = string.char(acc & 0xFF) end
    return "\120\1" .. table.concat(out) .. string.pack(">I4", (b << 16) | a)
end
Patina.deflate = deflate

function Patina.png(W, H, rgba, crc32)
    local rows = {}
    for y = 0, H - 1 do rows[#rows + 1] = "\0" .. rgba:sub(y * W * 4 + 1, (y + 1) * W * 4) end
    local function chunk(kind, data)
        return string.pack(">I4", #data) .. kind .. data .. string.pack(">I4", crc32(kind .. data))
    end
    return "\137PNG\r\n\26\n" .. chunk("IHDR", string.pack(">I4I4BBBBB", W, H, 8, 6, 0, 0, 0))
        .. chunk("IDAT", deflate(table.concat(rows))) .. chunk("IEND", "")
end

-- the plate style's name for a style value (1 Silver, 2 Black), or nil without a plate
function Patina.plate(value)
    value = math.floor(value or 0)
    return value == 1 and "Silver" or value == 2 and "Black" or nil
end

-- the drawing helpers, for TK_Theme_Forge
Patina.util = { rng = rng, shrink = shrink, ring = ring, blur = blur, png = Patina.png }

-- every image the theme needs for these choices: { [name in the theme folder] = png }
-- o: { grade = 0..3, seed, tcp = "Black"/"Silver"/nil, mcp = ..., coffee = true/false,
--      looks = { tcp = { wear, wear_a, style } } for a plate with its own finish (TK_Theme_Forge);
--      style "paper": board's frayed edges instead of scratches }
-- The scratches' shape (where they run, how strong) doesn't depend on their colour: it is
-- worked out once per plate, grade, seed and variant, with its 150% and 100% sizes, and kept
-- while the settings window is open (some 20 MB). A new finish only colours them anew; the
-- images come out exactly as drawn from scratch
local kept = { tag = nil, by = {} }
local function coverage(kind, plate, grade, seed, v, style)
    local tag = grade .. "|" .. seed
    if kept.tag ~= tag then kept.tag, kept.by = tag, {} end
    local key = kind .. "|" .. plate .. "|" .. v .. "|" .. (style or "metal")
    local hit = kept.by[key]
    if hit then return hit end
    -- the wear's shape follows the plate's material: scratches on metal, frayed edges on board
    local W2, H2, A, k = (style == "paper" and Patina.wear_paper or Patina.wear)(kind, plate, grade, seed, v, 2)
    hit = { k = k, scaled = {} }
    for _, sc in ipairs(SCALES) do
        local W, H = math.floor(W2 * sc[2] / 2 + 0.5), math.floor(H2 * sc[2] / 2 + 0.5)
        hit.scaled[sc[2]] = { W, H, sc[2] == 2 and A or shrink(A, W2, H2, W, H) }
    end
    kept.by[key] = hit
    return hit
end

function Patina.images(o, crc32)
    local files = {}
    local function out(name, W2, H2, A, col, k, fix)
        for _, sc in ipairs(SCALES) do
            local W, H = math.floor(W2 * sc[2] / 2 + 0.5), math.floor(H2 * sc[2] / 2 + 0.5)
            local px = compose(W, H, sc[2] == 2 and A or shrink(A, W2, H2, W, H), col, k)
            if fix then ring(px, W, H, fix, sc[2]) end
            files[sc[1] .. name .. ".png"] = Patina.png(W, H, table.concat(px), crc32)
        end
    end
    for _, kind in ipairs({ "tcp", "mcp" }) do
        local plate = o[kind]
        if plate then
            if o.grade > 0 then
                local own = o.looks and o.looks[kind]
                for v = 0, 2 do
                    local cov = coverage(kind, plate, o.grade, o.seed, v, own and own.style)
                    local k = cov.k
                    if own then k = k / LOOK[plate].wear_a * own.wear_a end
                    local col = own and own.wear or LOOK[plate].wear
                    for _, sc in ipairs(SCALES) do
                        local W, H, B = table.unpack(cov.scaled[sc[2]])
                        local px = compose(W, H, B, col, k)
                        ring(px, W, H, Patina.KINDS[kind].fix, sc[2])
                        files[sc[1] .. kind .. "Patina" .. v .. ".png"] = Patina.png(W, H, table.concat(px), crc32)
                    end
                end
            end
            if o.coffee then
                local N, _, A, k = Patina.coffee(kind, plate, o.seed, 2)
                out(kind .. "Coffee", N, N, A, LOOK[plate].coffee, k)
            end
        end
    end
    return files
end

return Patina
