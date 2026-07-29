-- core/heatmap.lua against a synthetic library. The property that matters most:
-- a selection narrowed to one category must still fill the grid.
--
-- The analyser is swapped for a table of hand-written measurements, so this
-- exercises the real cache path without needing audio.

local KIT = assert(TEST_DIR, "run these through tests/run_all.py") .. "/../"
package.path = KIT .. "?.lua;" .. package.path

reaper = {
  GetResourcePath = function() return (os.getenv("TEMP") or ".") .. "/tkkm_hmtest" end,
  RecursiveCreateDirectory = function(d) os.execute('mkdir "' .. d:gsub("/", "\\") .. '" 2>nul') end,
  time_precise = os.clock,
  GetPlayState = function() return 0 end,
  new_array = function(n) local a = {} for i = 1, n do a[i] = 0 end a.clear = function() end return a end,
}

local Analyzer = require("core.analyzer")
local synth = {}
Analyzer.analyze = function(path) return synth[path] end

local Tags = require("core.tags")
local Heatmap = require("core.heatmap")
Tags.clear_cache()

local fail = 0
local function check(label, ok, got)
  if not ok then fail = fail + 1 print("FAIL: " .. label .. "  (got " .. tostring(got) .. ")") end
end

local function put(path, m)
  synth[path] = m
  Tags.ensure(path)
  return path
end

local kicks, all = {}, {}
-- Kicks occupy a sliver of the absolute frequency axis: 45-95 Hz.
for i = 1, 120 do
  local p = string.format("Pack/Kicks/BD_%03d.wav", i)
  put(p, {
    dur = 1, nch = 1, attack_ms = 3 + (i % 7), decay_ms = 150 + (i % 15) * 30,
    decay10_ms = 40, crest_db = 9, centroid = 45 + (i % 11) * 5, flat = 0.02,
    pitch = 60, tail_ratio = 0.5, hf_ratio = 0.1, width = 0,
    bands = { 1.0, 0.6, 0.2, 0.1, 0.05, 0.02, 0.01 },
  })
  kicks[#kicks + 1] = p
  all[#all + 1] = p
end
for i = 1, 60 do
  local p = string.format("Pack/Hats/HH_%03d.wav", i)
  put(p, {
    dur = 1, nch = 1, attack_ms = 0.4 + (i % 5) * 0.3, decay_ms = 30 + (i % 9) * 12,
    decay10_ms = 8, crest_db = 13, centroid = 6500 + (i % 13) * 400, flat = 0.7,
    pitch = 0, tail_ratio = 0.2, hf_ratio = 0.6, width = 0,
    bands = { 0.02, 0.03, 0.05, 0.2, 0.5, 0.9, 1.0 },
  })
  all[#all + 1] = p
end
all[#all + 1] = "Pack/Kicks/never_analysed.wav"

local function occupied(grid)
  local n = 0
  for row = 1, grid.size do
    for col = 1, grid.size do
      if grid.cells[row][col].n > 0 then n = n + 1 end
    end
  end
  return n
end

local function columns_used(grid)
  local n = 0
  for col = 1, grid.size do
    for row = 1, grid.size do
      if grid.cells[row][col].n > 0 then n = n + 1 break end
    end
  end
  return n
end

-- 1. mixed library
local g = Heatmap.build(all, { size = 4, x = "tone", y = "decay" })
print(string.format("mixed:  %d placed, %d unanalysed, %d/%d cells used",
  g.placed, g.unanalysed, occupied(g), g.size * g.size))
check("every analysed file is placed", g.placed == 180, g.placed)
check("the unmeasured file is counted, not placed", g.unanalysed == 1, g.unanalysed)

-- 2. THE point of the feature: narrowed to kicks alone, the grid must still
-- spread them instead of stacking them in one column.
local gk = Heatmap.build(kicks, { size = 4, x = "tone", y = "decay" })
print(string.format("kicks:  %d placed, %d/%d cells used, %d/%d columns, x range %.3f-%.3f",
  gk.placed, occupied(gk), gk.size * gk.size, columns_used(gk), gk.size, gk.x_lo, gk.x_hi))
check("all kicks placed", gk.placed == #kicks, gk.placed)
check("kicks spread across more than one column", columns_used(gk) >= 3, columns_used(gk))
check("kicks fill most of the grid", occupied(gk) >= 8, occupied(gk))
check("the axis zoomed in on the kicks", gk.x_hi - gk.x_lo < 0.30, gk.x_hi - gk.x_lo)

-- 3. the leftover axis becomes the slider
check("frequency+decay leaves transient", gk.weight_axis.id == "transient", gk.weight_axis.id)
check("frequency+transient leaves decay",
  Heatmap.build(kicks, { x = "tone", y = "transient" }).weight_axis.id == "decay", "?")

-- 4. the slider weights, it does not filter
Heatmap.shade(gk, 0.0, 0.6)
local soft_total, soft_cells = 0, occupied(gk)
for row = 1, gk.size do for col = 1, gk.size do soft_total = soft_total + gk.cells[row][col].n end end
local soft_map = {}
for row = 1, gk.size do
  for col = 1, gk.size do soft_map[row .. "," .. col] = gk.cells[row][col].intensity end
end

Heatmap.shade(gk, 1.0, 0.6)
local hard_total, moved = 0, 0
for row = 1, gk.size do
  for col = 1, gk.size do
    hard_total = hard_total + gk.cells[row][col].n
    if math.abs(gk.cells[row][col].intensity - soft_map[row .. "," .. col]) > 0.01 then
      moved = moved + 1
    end
  end
end
check("no sample leaves the grid when the slider moves", soft_total == hard_total, hard_total)
check("cell membership is unchanged too", occupied(gk) == soft_cells, occupied(gk))
check("but the shading does change", moved > 0, moved)

-- 5. picking
Heatmap.shade(gk, 0.5, 0.6)
local frow, fcol
for row = 1, gk.size do
  for col = 1, gk.size do
    if gk.cells[row][col].n > 0 then frow, fcol = row, col break end
  end
  if frow then break end
end
local pick = Heatmap.pick(gk, frow, fcol, 0.5, 0.6)
check("a cell hands back one of its own samples", (function()
  for _, item in ipairs(gk.cells[frow][fcol].items) do
    if item.path == pick then return true end
  end
  return false
end)(), tostring(pick))
check("an out-of-range cell hands back nothing", Heatmap.pick(gk, 99, 99, 0.5, 0.6) == nil, "picked")

-- 6. degenerate input: every sample identical
local same = {}
for i = 1, 30 do
  same[#same + 1] = put("Pack/Same/" .. i .. ".wav", {
    dur = 1, nch = 1, attack_ms = 4, decay_ms = 200, decay10_ms = 50, crest_db = 9,
    centroid = 100, flat = 0.02, pitch = 60, tail_ratio = 0.5, hf_ratio = 0.1, width = 0,
    bands = { 1, 0.5, 0.2, 0.1, 0.05, 0.02, 0.01 },
  })
end
local gs = Heatmap.build(same, { size = 4 })
Heatmap.shade(gs, 0.5, 0.6)
check("identical samples still place", gs.placed == 30, gs.placed)
check("identical samples do not collapse the range", gs.x_hi > gs.x_lo, gs.x_hi - gs.x_lo)

-- 7. empty selection
local ge = Heatmap.build({}, { size = 4 })
Heatmap.shade(ge, 0.5, 0.6)
check("empty selection is safe", ge.placed == 0 and ge.max_count == 0, ge.placed)
check("empty selection picks nothing", Heatmap.pick(ge, 1, 1, 0.5, 0.6) == nil, "picked")

-- 8. same axis on both sides must not produce a degenerate grid
local gd = Heatmap.build(kicks, { x = "tone", y = "tone" })
check("duplicate axes are corrected", gd.x_axis.id ~= gd.y_axis.id, gd.y_axis.id)

-- 9. grid size is clamped to what the UI offers
check("size is clamped low", Heatmap.build(kicks, { size = 1 }).size == Heatmap.MIN_SIZE, "?")
check("size is clamped high", Heatmap.build(kicks, { size = 99 }).size == Heatmap.MAX_SIZE, "?")

-- 10. cell -> pad. The Kit Manager lays its pads out bottom-up (MPC style), the
-- grid top-down, so this mapping is the whole of "the grid IS a kit layout".
local g4 = Heatmap.build(kicks, { size = 4, x = "tone", y = "decay" })
print()
print("cell -> pad  (grid row 1 = top = longest decay)")
for row = 1, 4 do
  local line = "  row " .. row .. " |"
  for col = 1, 4 do line = line .. string.format("%4d", Heatmap.pad_slot(g4, row, col)) end
  print(line)
end

check("bottom-left cell is pad 1", Heatmap.pad_slot(g4, 4, 1) == 1, Heatmap.pad_slot(g4, 4, 1))
check("bottom-right cell is pad 4", Heatmap.pad_slot(g4, 4, 4) == 4, Heatmap.pad_slot(g4, 4, 4))
check("top-left cell is pad 13", Heatmap.pad_slot(g4, 1, 1) == 13, Heatmap.pad_slot(g4, 1, 1))
check("top-right cell is pad 16", Heatmap.pad_slot(g4, 1, 4) == 16, Heatmap.pad_slot(g4, 1, 4))

check("every cell maps to exactly one pad, 1..16", (function()
  local seen = {}
  for row = 1, 4 do
    for col = 1, 4 do
      local s = Heatmap.pad_slot(g4, row, col)
      if s < 1 or s > 16 or seen[s] then return false end
      seen[s] = true
    end
  end
  for s = 1, 16 do if not seen[s] then return false end end
  return true
end)(), "not a bijection")

-- Pad 1 must genuinely be the darkest and shortest corner, or the whole premise
-- ("pad 1 dark and short, pad 16 bright and long") is wrong.
local function cell_mid(grid, row, col)
  local xl, xh = Heatmap.cell_range(grid, col, "x")
  local yl, yh = Heatmap.cell_range(grid, row, "y")
  return (xl + xh) * 0.5, (yl + yh) * 0.5
end
local x1, y1 = cell_mid(g4, 4, 1)
local x16, y16 = cell_mid(g4, 1, 4)
check("pad 1 sits low on the frequency axis", x1 < x16, x1)
check("pad 1 sits low on the decay axis", y1 < y16, y1)

-- 11. cell_order: clicking a cell repeatedly must walk it, not re-roll it.
local orow, ocol
for row = 1, 4 do
  for col = 1, 4 do
    local cl = g4.cells[row][col]
    if cl.n >= 4 and not orow then orow, ocol = row, col end
  end
end
check("found a cell with enough samples to order", orow ~= nil, "none")

if orow then
  Heatmap.shade(g4, 0.0, 0.8)
  local order = Heatmap.cell_order(g4, orow, ocol, 0.0, 0.8)
  local cell = g4.cells[orow][ocol]
  print()
  print(string.format("cell order (%d samples, slider at 0.00)", cell.n))

  check("the order covers the cell exactly once", (function()
    if #order ~= cell.n then return false end
    local seen = {}
    for _, idx in ipairs(order) do
      if idx < 1 or idx > cell.n or seen[idx] then return false end
      seen[idx] = true
    end
    return true
  end)(), #order)

  -- Weighting sets the order, so what you hear FIRST must be the best match for
  -- where the slider sits -- otherwise the walk has thrown the weighting away.
  local Bias = require("core.bias")
  local first_w = Bias.weight_for(cell.items[order[1]].w, 0.0, 0.8)
  local last_w = Bias.weight_for(cell.items[order[#order]].w, 0.0, 0.8)
  print(string.format("  first weight %.4f, last weight %.4f", first_w, last_w))
  check("the walk starts nearer the slider than it ends", first_w >= last_w, first_w)

  check("every entry resolves to a real path", (function()
    for _, idx in ipairs(order) do
      if not Heatmap.item_path(g4, orow, ocol, idx) then return false end
    end
    return true
  end)(), "nil path")

  check("an empty cell has no order", (function()
    for row = 1, 4 do
      for col = 1, 4 do
        if g4.cells[row][col].n == 0 then
          return Heatmap.cell_order(g4, row, col, 0.5, 0.6) == nil
        end
      end
    end
    return true
  end)(), "got an order")
  check("an out-of-range cell has no order", Heatmap.cell_order(g4, 99, 99, 0.5, 0.6) == nil, "got one")
  check("item_path is nil past the end", Heatmap.item_path(g4, orow, ocol, cell.n + 1) == nil, "got a path")
end

-- 11. projecting a kit onto the grid. The property that decides whether this
-- feature works at all: the projection must use the GRID's bounds, so a kit
-- huddled in one corner still looks huddled instead of being spread out by a
-- helpful rescale.
local gp = Heatmap.build(all, { size = 4, x = "tone", y = "decay" })

-- Four pads all taken from the same narrow corner of the pack.
local corner = {}
for i = 1, 4 do
  corner[i] = { label = tostring(i), x = gp.x_lo + 0.01, y = gp.y_lo + 0.01 }
end
local pc, pc_clamped = Heatmap.project(gp, corner)
local occupied_cells = 0
for row = 1, gp.size do
  for col = 1, gp.size do
    if pc[row] and pc[row][col] then occupied_cells = occupied_cells + 1 end
  end
end
check("a kit stuck in one corner projects into one cell", occupied_cells == 1, occupied_cells)
check("that cell is the bottom-left one", pc[gp.size] and pc[gp.size][1] and #pc[gp.size][1] == 4,
  occupied_cells)
check("pads inside the range are not flagged as clamped", pc_clamped == 0, pc_clamped)

-- A kit that really is spread out must show as spread out.
local spread_pts = {
  { label = "1", x = gp.x_lo, y = gp.y_lo },
  { label = "2", x = gp.x_hi, y = gp.y_lo },
  { label = "3", x = gp.x_lo, y = gp.y_hi },
  { label = "4", x = gp.x_hi, y = gp.y_hi },
}
local ps = Heatmap.project(gp, spread_pts)
check("corner pads land in the four corners",
  ps[gp.size] and ps[gp.size][1] and ps[gp.size][gp.size] and ps[1] and ps[1][1] and ps[1][gp.size],
  "not spread")

-- Samples outside the grid's range must clamp inside rather than vanish -- and
-- must SAY they were clamped, or a kit measured against a pack it did not come
-- from reads as "clustered in the corners" when it is really off this scale.
local outside, out_clamped = Heatmap.project(gp, {
  { label = "9", x = -5, y = -5 },
  { label = "10", x = 99, y = 99 },
})
check("a pad below the range clamps to the bottom-left",
  outside[gp.size] and outside[gp.size][1] and outside[gp.size][1][1].label == "9", "lost")
check("a pad above the range clamps to the top-right",
  outside[1] and outside[1][gp.size] and outside[1][gp.size][1].label == "10", "lost")
check("both are counted as clamped", out_clamped == 2, out_clamped)
check("a clamped pad is flagged", outside[gp.size][1][1].clamped == true, "not flagged")

-- A pad genuinely in an edge cell must NOT be flagged, or the marking says
-- nothing.
local edge_in = Heatmap.project(gp, { { label = "1", x = gp.x_lo, y = gp.y_lo } })
check("a pad exactly on the bound is not clamped",
  edge_in[gp.size][1][1].clamped == false, "flagged")

-- Extra parentheses: project returns two values and next() would take the
-- second as a key.
check("projecting nothing is safe", next((Heatmap.project(gp, {}))) == nil, "not empty")
check("projecting onto no grid is safe", next((Heatmap.project(nil, spread_pts))) == nil, "not empty")

print()
print(fail == 0 and "ALL CHECKS PASSED" or (fail .. " CHECK(S) FAILED"))

-- Read by tests/run_all.py; a suite that only prints cannot be checked.
TEST_FAILED = fail
