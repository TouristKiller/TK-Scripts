-- @noindex
-- Graffiti on the plates (Materials page, On the plates): spray clouds, splats with
-- drips, and doodles (crowns, X's, stars, arrows, bolts), worn a little. Nothing of it ships:
-- the settings window draws it from your own seed, as the wear. Seven variants per plate,
-- which the theme picks by the track's number (with the wear's three: the same pair only
-- every 21 tracks). The images stretch like the plates (a pink marker ring, fixed borders), so
-- everything is drawn squeezed where the theme stretches and comes out round.
local Graffiti = {}

Graffiti.VARIANTS = 7
-- as TK_Theme_Forge's KINDS: size at 100%, fixed borders (left, top, right, bottom), and how
-- far the middle stretches in the theme
Graffiti.KINDS = {
    tcp = { w = 300, h = 96, fix = { 30, 22, 30, 22 }, sx = 2.2, sy = 1 },
    mcp = { w = 100, h = 320, fix = { 0, 40, 0, 40 }, sx = 1, sy = 2.2 },
}
local SCALES = { { "", 1 }, { "150/", 1.5 }, { "200/", 2 } }

Graffiti.PALETTES = {
    neon = { { 255, 46, 170 }, { 255, 222, 30 }, { 40, 220, 255 }, { 120, 255, 60 }, { 255, 120, 30 }, { 170, 80, 255 } },
}
-- how much of each, per level (1 Light, 2 Wild)
local AMOUNT = { { clouds = 1, splats = 3, doodles = 1, cloud_a = 0.30 }, { clouds = 3, splats = 7, doodles = 3, cloud_a = 0.42 } }

local floor, sqrt, exp, sin, cos, atan, pi = math.floor, math.sqrt, math.exp, math.sin, math.cos, math.atan, math.pi
local function clamp01(v) return v < 0 and 0 or (v > 1 and 1 or v) end

-- the accent colour's set: the colour, lighter, darker, and white and black for the doodles
function Graffiti.accent_palette(c)
    local function mixc(a, b, t) return { floor(a[1] + (b[1] - a[1]) * t + 0.5), floor(a[2] + (b[2] - a[2]) * t + 0.5), floor(a[3] + (b[3] - a[3]) * t + 0.5) } end
    return { c, mixc(c, { 255, 255, 255 }, 0.45), mixc(c, { 0, 0, 0 }, 0.45), { 245, 245, 245 }, { 24, 24, 28 }, mixc(c, { 255, 255, 255 }, 0.2) }
end

-- one plate's graffiti, variant v, at 200%: W, H and premultiplied colour + alpha arrays
function Graffiti.draw(U_, kind, level, seed, v, palette)
    local K = Graffiti.KINDS[kind]
    local s = 2
    local W, H = K.w * s, K.h * s
    local R = U_.rng(seed * 17 + v * 389 + (kind == "mcp" and 2003 or 0) + 11)
    local L, T, Rr, B = K.fix[1] * s, K.fix[2] * s, K.fix[3] * s, K.fix[4] * s
    -- each pixel's place on the plate as it is seen, in 100% units
    local U, V = {}, {}
    for x = 0, W - 1 do
        local u
        if x <= L then u = x elseif x >= W - Rr then u = L + (W - Rr - L) * K.sx + (x - (W - Rr)) else u = L + (x - L) * K.sx end
        U[x] = u / s
    end
    for y = 0, H - 1 do
        local t
        if y <= T then t = y elseif y >= H - B then t = T + (H - B - T) * K.sy + (y - (H - B)) else t = T + (y - T) * K.sy end
        V[y] = t / s
    end
    local umax, vmax = U[W - 1], V[H - 1]
    local PR, PG, PB, PA = {}, {}, {}, {}
    for i = 1, W * H do PR[i], PG[i], PB[i], PA[i] = 0, 0, 0, 0 end
    -- the pixel ranges a shape from u0..u1, v0..v1 can reach
    local function range(u0, u1, v0, v1)
        local x0, x1, y0, y1 = W, -1, H, -1
        for x = 0, W - 1 do
            if U[x] >= u0 and U[x] <= u1 then
                if x < x0 then x0 = x end
                x1 = x
            end
        end
        for y = 0, H - 1 do
            if V[y] >= v0 and V[y] <= v1 then
                if y < y0 then y0 = y end
                y1 = y
            end
        end
        return x0, x1, y0, y1
    end
    local function over(i, c, a)
        if a <= 0.002 then return end
        local k = 1 - a
        PR[i] = c[1] * a + PR[i] * k
        PG[i] = c[2] * a + PG[i] * k
        PB[i] = c[3] * a + PB[i] * k
        PA[i] = a + PA[i] * k
    end
    -- a shape given as coverage(u, v) over its box, in one colour
    local function paint(u0, u1, v0, v1, c, alpha, cover)
        local x0, x1, y0, y1 = range(u0, u1, v0, v1)
        for y = y0, y1 do
            local vv, base = V[y], y * W + 1
            for x = x0, x1 do
                local a = cover(U[x], vv)
                if a > 0 then over(base + x, c, a * alpha) end
            end
        end
    end
    -- the distance from (u, v) to a segment
    local function seg_d(u, v, a, b, c, d)
        local dx, dy = c - a, d - b
        local L2 = dx * dx + dy * dy
        local t = L2 > 0 and clamp01(((u - a) * dx + (v - b) * dy) / L2) or 0
        local ex, ey = u - a - t * dx, v - b - t * dy
        return sqrt(ex * ex + ey * ey)
    end
    -- lines of width wd (100% units) through points, as one shape
    local function polyline(pts, wd, c, alpha)
        local u0, u1, v0, v1 = 1e9, -1e9, 1e9, -1e9
        for _, p in ipairs(pts) do
            if p[1] < u0 then u0 = p[1] end
            if p[1] > u1 then u1 = p[1] end
            if p[2] < v0 then v0 = p[2] end
            if p[2] > v1 then v1 = p[2] end
        end
        local hw = wd / 2
        paint(u0 - wd, u1 + wd, v0 - wd, v1 + wd, c, alpha, function(u, v)
            local best = 1e9
            for j = 1, #pts - 1 do
                local d = seg_d(u, v, pts[j][1], pts[j][2], pts[j + 1][1], pts[j + 1][2])
                if d < best then best = d end
            end
            return clamp01((hw - best) * s + 0.5)
        end)
    end
    local function disc(cu, cv, r, c, alpha)
        paint(cu - r - 1, cu + r + 1, cv - r - 1, cv + r + 1, c, alpha, function(u, v)
            local du, dv = u - cu, v - cv
            return clamp01((r - sqrt(du * du + dv * dv)) * s + 0.5)
        end)
    end
    local A = AMOUNT[level]
    local cols = {}
    for i = 1, #palette do cols[i] = palette[i] end
    for i = #cols, 2, -1 do                      -- shuffled per variant
        local j = R.int(1, i)
        cols[i], cols[j] = cols[j], cols[i]
    end
    local function col(i) return cols[(i - 1) % #cols + 1] end
    -- 1: spray clouds, soft and wide, with the grain of a spray can
    for i = 1, A.clouds do
        local cu, cv = R.uni(0, umax), R.uni(0, vmax)
        local ru = R.uni(umax * 0.14, umax * 0.32)
        local rv = R.uni(vmax * 0.30, vmax * 0.60)
        if kind == "mcp" then ru, rv = R.uni(umax * 0.40, umax * 0.80), R.uni(vmax * 0.12, vmax * 0.26) end
        local gseed = R.int(1, 1000000)
        local G = U_.rng(gseed)
        paint(cu - ru * 1.7, cu + ru * 1.7, cv - rv * 1.7, cv + rv * 1.7, col(i), A.cloud_a, function(u, v)
            local du, dv = (u - cu) / ru, (v - cv) / rv
            return exp(-2 * (du * du + dv * dv)) * (0.55 + 0.45 * G.next())
        end)
    end
    -- 2: splats: a ragged blob, droplets thrown round it, streaks, and drips running down
    for i = 1, A.splats do
        local c = col(i + 1)
        local r0 = R.uni(5, 11)
        local cu, cv = R.uni(r0, umax - r0), R.uni(r0, vmax - r0)
        local amp, ph = {}, {}
        for k = 1, 5 do amp[k], ph[k] = R.uni(0.04, 0.16), R.uni(0, 2 * pi) end
        paint(cu - r0 * 1.8, cu + r0 * 1.8, cv - r0 * 1.8, cv + r0 * 1.8, c, 0.92, function(u, v)
            local du, dv = u - cu, v - cv
            local t = atan(dv, du)
            local rr = r0
            for k = 1, 5 do rr = rr + r0 * amp[k] * sin((k + 2) * t + ph[k]) end
            return clamp01((rr - sqrt(du * du + dv * dv)) * s + 0.5)
        end)
        for _ = 1, floor(6 + r0 * 1.2) do
            local a, dist = R.uni(0, 2 * pi), r0 * R.uni(1.2, 2.6)
            disc(cu + cos(a) * dist, cv + sin(a) * dist, R.uni(0.4, r0 * 0.16 + 0.6), c, 0.92)
        end
        for _ = 1, 2 do
            local a, l = R.uni(0, 2 * pi), r0 * R.uni(1.3, 2.2)
            polyline({ { cu, cv }, { cu + cos(a) * l, cv + sin(a) * l } }, math.max(1, r0 * 0.18), c, 0.9)
        end
        if R.next() < 0.6 then
            for _ = 1, R.int(1, 3) do
                local du = R.uni(-r0 * 0.6, r0 * 0.6)
                local top = cv + r0 * 0.5
                local len = math.min(R.uni(4, 22), vmax - top - 3)
                if len > 2 then
                    local wd = R.uni(1.2, 2.4)
                    polyline({ { cu + du, top }, { cu + du, top + len } }, wd, c, 0.9)
                    disc(cu + du, top + len, wd * 0.75, c, 0.9)
                end
            end
        end
    end
    -- 3: doodles in marker
    local KINDS = { "crown", "x", "star", "arrow", "bolt" }
    for i = 1, A.doodles do
        local what = KINDS[R.int(1, #KINDS)]
        local sz = R.uni(7, 13)
        local cu, cv = R.uni(sz * 1.5, umax - sz * 1.5), R.uni(sz * 1.2, vmax - sz * 1.2)
        local c = col(i + 3)
        local function j() return R.uni(-sz * 0.05, sz * 0.05) end
        local wd = 2
        if what == "crown" then
            local p = { { -1, .5 }, { -1, -.3 }, { -.5, .1 }, { 0, -.6 }, { .5, .1 }, { 1, -.3 }, { 1, .5 }, { -1, .5 } }
            local pts = {}
            for k, q in ipairs(p) do pts[k] = { cu + q[1] * sz + j(), cv + q[2] * sz + j() } end
            polyline(pts, wd, c, 0.95)
            for _, q in ipairs({ { -1, -.45 }, { 0, -.75 }, { 1, -.45 } }) do disc(cu + q[1] * sz, cv + q[2] * sz, 1.3, c, 0.95) end
        elseif what == "x" then
            polyline({ { cu - sz + j(), cv - sz + j() }, { cu + sz + j(), cv + sz + j() } }, wd + 1, c, 0.95)
            polyline({ { cu + sz + j(), cv - sz + j() }, { cu - sz + j(), cv + sz + j() } }, wd + 1, c, 0.95)
        elseif what == "star" then
            local pts = {}
            for k = 0, 10 do
                local a = -pi / 2 + k * pi / 5
                local rr = k % 2 == 0 and sz or sz * 0.45
                pts[#pts + 1] = { cu + cos(a) * rr + j(), cv + sin(a) * rr + j() }
            end
            polyline(pts, wd, c, 0.95)
        elseif what == "arrow" then
            local pts = {}
            for k = 0, 10 do pts[#pts + 1] = { cu - sz * 1.4 + k * sz * 0.28, cv + sin(k * 0.9) * sz * 0.25 } end
            polyline(pts, wd, c, 0.95)
            local e = pts[#pts]
            polyline({ { e[1] - sz * .4, e[2] - sz * .3 }, e, { e[1] - sz * .4, e[2] + sz * .3 } }, wd, c, 0.95)
        else
            polyline({ { cu - sz * .2, cv - sz }, { cu + sz * .3, cv - sz * .1 }, { cu - sz * .1, cv - sz * .05 }, { cu + sz * .25, cv + sz } }, wd + 0.5, c, 0.95)
        end
    end
    -- 4: worn a little, as the wear would: fine scratches through the paint, and specks
    local keep = {}
    for i = 1, W * H do keep[i] = 1 end
    for _ = 1, 20 * level do
        local y, x0 = R.int(0, H - 1), R.int(0, W - 1)
        local len = R.int(20, 160)
        for x = x0, math.min(W - 1, x0 + len) do keep[y * W + x + 1] = keep[y * W + x + 1] * 0.3 end
    end
    for _ = 1, floor(W * H * 0.01) do
        local i = R.int(1, W * H)
        keep[i] = keep[i] * 0.35
    end
    for i = 1, W * H do
        local k = keep[i]
        if k < 1 then PR[i], PG[i], PB[i], PA[i] = PR[i] * k, PG[i] * k, PB[i] * k, PA[i] * k end
    end
    return W, H, PR, PG, PB, PA
end

-- the four channels made smaller to w x h at once, each new pixel the mean of what it covers
-- (one set of weights for all four, in flat arrays: Patina's shrink per channel took 4x as long)
local function weights(n, m)
    local f, first, count, idx, wt = n / m, {}, {}, {}, {}
    for d = 0, m - 1 do
        local s0, s1 = d * f, (d + 1) * f
        first[d] = #idx + 1
        for sx = floor(s0), math.min(n - 1, math.ceil(s1) - 1) do
            local u = math.min(s1, sx + 1) - math.max(s0, sx)
            if u > 0 then idx[#idx + 1] = sx wt[#wt + 1] = u / f end
        end
        count[d] = #idx + 1 - first[d]
    end
    return first, count, idx, wt
end

local function shrink4(C, W, H, w, h)
    local cf, cc, ci, cw = weights(W, w)
    local rf, rc, ri, rw = weights(H, h)
    local C1, C2, C3, C4 = C[1], C[2], C[3], C[4]
    local t1, t2, t3, t4 = {}, {}, {}, {}
    for y = 0, H - 1 do
        local base = y * W + 1
        for x = 0, w - 1 do
            local s1, s2, s3, s4 = 0, 0, 0, 0
            for k = cf[x], cf[x] + cc[x] - 1 do
                local i, q = base + ci[k], cw[k]
                s1, s2, s3, s4 = s1 + C1[i] * q, s2 + C2[i] * q, s3 + C3[i] * q, s4 + C4[i] * q
            end
            local o = y * w + x + 1
            t1[o], t2[o], t3[o], t4[o] = s1, s2, s3, s4
        end
    end
    local o1, o2, o3, o4 = {}, {}, {}, {}
    for y = 0, h - 1 do
        for x = 1, w do
            local s1, s2, s3, s4 = 0, 0, 0, 0
            for k = rf[y], rf[y] + rc[y] - 1 do
                local i, q = ri[k] * w + x, rw[k]
                s1, s2, s3, s4 = s1 + t1[i] * q, s2 + t2[i] * q, s3 + t3[i] * q, s4 + t4[i] * q
            end
            local o = y * w + x
            o1[o], o2[o], o3[o], o4[o] = s1, s2, s3, s4
        end
    end
    return o1, o2, o3, o4
end

-- every image the theme needs: { [name in the theme folder] = png }
-- o: { level = 1|2, seed, palette = { {r,g,b}, ... }, kinds = { tcp = true, mcp = true }, png = fn(W, H, rgba, crc32) }
-- U_: TK_Theme_Patina's helpers (rng, shrink, ring)
function Graffiti.images(U_, o, crc32)
    local files = {}
    local char, concat = string.char, table.concat
    local jobs = {}
    for _, kind in ipairs({ "tcp", "mcp" }) do
        if o.kinds[kind] then
            jobs[#jobs + 1] = { kind, "Graffiti", Graffiti.KINDS[kind].fix, function(v) return Graffiti.draw(U_, kind, o.level, o.seed, v, o.palette) end }
            if o.stickers then
                jobs[#jobs + 1] = { kind, "Sticker", Graffiti.STICKER[kind].fix, function(v) return Graffiti.sticker(U_, kind, o.seed, v, o.palette) end }
                if o.sticker_track then
                    jobs[#jobs + 1] = { kind, "StickerW", Graffiti.STICKER[kind].fix, function(v) return Graffiti.sticker(U_, kind, o.seed, v, o.palette, true) end }
                end
            end
        end
    end
    for _, job in ipairs(jobs) do
        local kind, what, fix, make = job[1], job[2], job[3], job[4]
        do
            for v = 0, Graffiti.VARIANTS - 1 do
                local W2, H2, PR, PG, PB, PA = make(v)
                for _, sc in ipairs(SCALES) do
                    local W, H = floor(W2 * sc[2] / 2 + 0.5), floor(H2 * sc[2] / 2 + 0.5)
                    local r, g, b, a = PR, PG, PB, PA
                    if sc[2] ~= 2 then r, g, b, a = shrink4({ PR, PG, PB, PA }, W2, H2, W, H) end
                    local px = {}
                    for i = 1, W * H do
                        local al = a[i]
                        if al <= 0.004 then
                            px[i] = "\0\0\0\0"
                        else
                            local inv = 1 / al
                            local cr, cg, cb = r[i] * inv, g[i] * inv, b[i] * inv
                            cr = cr > 255 and 255 or floor(cr + 0.5)
                            cg = cg > 255 and 255 or floor(cg + 0.5)
                            cb = cb > 255 and 255 or floor(cb + 0.5)
                            px[i] = char(cr, cg, cb, floor((al > 1 and 1 or al) * 255 + 0.5))
                        end
                    end
                    U_.ring(px, W, H, fix, sc[2])
                    files[sc[1] .. kind .. what .. v .. ".png"] = o.png(W, H, concat(px), crc32)
                end
            end
        end
    end
    return files
end

-- Name stickers (with Graffiti): a torn paper sticker under the track's name, the name
-- itself REAPER's text on it, dark. Seven, by the same track number as the graffiti; the
-- papers kept light so dark text reads on all of them. They stretch to the name's width:
-- the torn ends are fixed, the middle stretches
Graffiti.STICKER = {
    tcp = { w = 150, h = 26, fix = { 14, 0, 20, 0 } },
    mcp = { w = 90, h = 24, fix = { 12, 0, 16, 0 } },
}

local function paper_colour(c)
    -- a sticker's paper: the colour, lifted towards white where it is dark
    local l = (c[1] * 299 + c[2] * 587 + c[3] * 114) / 1000
    local t = l < 150 and (150 - l) / 255 + 0.25 or 0.12
    return { floor(c[1] + (255 - c[1]) * t + 0.5), floor(c[2] + (255 - c[2]) * t + 0.5), floor(c[3] + (255 - c[3]) * t + 0.5) }
end

-- white: blank sticker paper, for the track colour printed on it (the theme fills that in)
function Graffiti.sticker(U_, kind, seed, v, palette, white)
    local S_ = Graffiti.STICKER[kind]
    local s = 2
    local W, H = S_.w * s, S_.h * s
    local R = U_.rng(seed * 23 + v * 71 + (kind == "mcp" and 401 or 0) + 5)
    local col = white and { 244, 242, 236 } or paper_colour(palette[(v * 2 + 1) % #palette + 1])
    -- the paper's outline: torn top and bottom edges, a margin for the shadow
    local m = 2 * s
    local top, bot = {}, {}
    local step = 3 * s
    for x = 0, W - 1 do
        local k = floor(x / step)
        top[k] = top[k] or R.uni(0, 1.6) * s
        bot[k] = bot[k] or R.uni(0, 1.6) * s
    end
    local peel = v % 3 == 1 and not white          -- the right end's top corner come loose (not on the plain paper)
    local PR, PG, PB, PA = {}, {}, {}, {}
    for i = 1, W * H do PR[i], PG[i], PB[i], PA[i] = 0, 0, 0, 0 end
    local function inside(x, y)
        if x < m or x > W - m - 2 * s then return false end
        local k = floor(x / step)
        local t0, b0 = m + top[k], H - m - 2 * s - bot[k]
        if y < t0 or y > b0 then return false end
        if peel and x > W - m - 2 * s - 12 * s and y < t0 + (x - (W - m - 2 * s - 12 * s)) * 0.7 then return false end
        return true
    end
    -- shadow first, down and right, soft
    local sh = {}
    for i = 1, W * H do sh[i] = 0 end
    for y = 0, H - 1 do
        for x = 0, W - 1 do
            if inside(x - 1.5 * s, y - 2 * s) then sh[y * W + x + 1] = 0.45 end
        end
    end
    U_.blur(sh, W, H, 1.2 * s)
    for i = 1, W * H do PA[i] = sh[i] end
    -- the paper: lit a little from the top, a fine grain
    for y = 0, H - 1 do
        local light = 1.04 - 0.10 * y / H
        for x = 0, W - 1 do
            if inside(x, y) then
                local i = y * W + x + 1
                local g = 1 + (R.next() - 0.5) * 0.06
                local f = light * g
                PR[i], PG[i], PB[i], PA[i] = col[1] * f, col[2] * f, col[3] * f, 1
            end
        end
    end
    -- the peeled corner: its white back folded over
    if peel then
        local x0 = W - m - 2 * s - 12 * s
        for y = 0, H - 1 do
            for x = x0, W - 1 do
                local dx = x - x0
                local k = floor(x / step)
                local t0 = m + top[k]
                if y >= t0 and y < t0 + dx * 0.7 and y > t0 + dx * 0.7 - 7 * s and x < W - m - 2 * s then
                    local i = y * W + x + 1
                    PR[i], PG[i], PB[i], PA[i] = 238, 236, 228, 1
                end
            end
        end
    end
    -- premultiplied, as Graffiti.draw gives them
    for i = 1, W * H do
        local a = PA[i]
        if a < 1 then PR[i], PG[i], PB[i] = PR[i] * a, PG[i] * a, PB[i] * a end
    end
    return W, H, PR, PG, PB, PA
end

-- every image name, for taking them out again
function Graffiti.names()
    local list = {}
    for _, kind in ipairs({ "tcp", "mcp" }) do
        for v = 0, Graffiti.VARIANTS - 1 do
            for _, sc in ipairs(SCALES) do
                list[#list + 1] = sc[1] .. kind .. "Graffiti" .. v .. ".png"
                list[#list + 1] = sc[1] .. kind .. "Sticker" .. v .. ".png"
                list[#list + 1] = sc[1] .. kind .. "StickerW" .. v .. ".png"
            end
        end
    end
    return list
end

return Graffiti
