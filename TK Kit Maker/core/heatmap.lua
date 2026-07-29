-- Heatmap grid over an analysed collection: two tag axes span the grid, the
-- third becomes a weighting slider.
--
-- Two things make this work:
--
-- 1. Ranges are fitted to the SELECTION, not to the absolute 0..1 of an axis.
--    Measured on a real library, kicks sit in roughly the bottom fifth of the
--    frequency axis and hats in the top quarter -- so filtering to one category
--    and drawing an absolute grid leaves every sample stacked in one column,
--    which is exactly what the grid is supposed to spread out. Percentile
--    bounds rather than min/max keep a single outlier from flattening the rest.
--
-- 2. The third axis weights, it does not filter. Its slider is the centre of
--    core/bias.lua's gaussian, and a cell's intensity is the summed weight of
--    the samples inside it. Moving the slider re-shades the grid without
--    changing which samples live where.

local Bias = require("core.bias")
local Tags = require("core.tags")

local M = {}

-- The three axes that are direct measurements, and therefore trustworthy enough
-- to navigate by. Spatiality is left out on purpose: it is unknown for mono.
M.GRID_AXES = { "tone", "decay", "transient" }

M.MIN_SIZE = 3
M.MAX_SIZE = 8

-- Below this many samples percentiles are noise, so the full spread is used.
local PERCENTILE_MIN_N = 20
local PERCENTILE_LO = 0.05
local PERCENTILE_HI = 0.95
local MIN_SPAN = 0.02

-- The axis that is not on the grid, i.e. the one the slider drives.
function M.weight_axis(x_id, y_id)
  for _, id in ipairs(M.GRID_AXES) do
    if id ~= x_id and id ~= y_id then return Tags.axis(id) end
  end
  return Tags.axis("transient")
end

local function bounds(values)
  local n = #values
  if n == 0 then return 0, 1 end

  table.sort(values)
  local lo, hi
  if n >= PERCENTILE_MIN_N then
    lo = values[math.max(1, math.floor(n * PERCENTILE_LO))]
    hi = values[math.min(n, math.ceil(n * PERCENTILE_HI))]
  else
    lo, hi = values[1], values[n]
  end

  -- Everything measured (almost) the same: open the range up so the grid still
  -- draws a spread instead of collapsing into a single column.
  if hi - lo < MIN_SPAN then
    local mid = (hi + lo) * 0.5
    lo, hi = math.max(0, mid - 0.05), math.min(1, mid + 0.05)
    if hi - lo < MIN_SPAN then lo, hi = 0, 1 end
  end
  return lo, hi
end

local function slot(v, lo, hi, size)
  local i = math.floor((v - lo) / (hi - lo) * size) + 1
  if i < 1 then return 1 end
  if i > size then return size end
  return i
end

-- Places every analysed file from `files` on a size x size grid.
-- opts: { size, x = axis id, y = axis id }
function M.build(files, opts)
  opts = opts or {}
  local size = math.max(M.MIN_SIZE, math.min(M.MAX_SIZE, math.floor(opts.size or 4)))
  local x_axis = Tags.axis(opts.x) or Tags.axis("tone")
  local y_axis = Tags.axis(opts.y) or Tags.axis("decay")
  if x_axis.id == y_axis.id then
    y_axis = M.weight_axis(x_axis.id, x_axis.id)
  end
  local w_axis = M.weight_axis(x_axis.id, y_axis.id)

  local placed, unanalysed = {}, 0
  local xs, ys = {}, {}
  for _, path in ipairs(files or {}) do
    local d = Tags.derive(Tags.get(path))
    if d then
      local n = #placed + 1
      placed[n] = { path = path, x = d[x_axis.key], y = d[y_axis.key], w = d[w_axis.key] }
      xs[n], ys[n] = placed[n].x, placed[n].y
    else
      unanalysed = unanalysed + 1
    end
  end

  local x_lo, x_hi = bounds(xs)
  local y_lo, y_hi = bounds(ys)

  local cells = {}
  for row = 1, size do
    cells[row] = {}
    for col = 1, size do cells[row][col] = { n = 0, items = {}, weight = 0, intensity = 0 } end
  end

  for i = 1, #placed do
    local p = placed[i]
    local col = slot(p.x, x_lo, x_hi, size)
    -- Row 1 is the top of the grid while the axis grows upward, hence the flip.
    local row = size + 1 - slot(p.y, y_lo, y_hi, size)
    local cell = cells[row][col]
    cell.n = cell.n + 1
    cell.items[cell.n] = p
  end

  local grid = {
    size = size,
    cells = cells,
    x_axis = x_axis, y_axis = y_axis, weight_axis = w_axis,
    x_lo = x_lo, x_hi = x_hi, y_lo = y_lo, y_hi = y_hi,
    placed = #placed,
    unanalysed = unanalysed,
    max_count = 0,
  }
  for row = 1, size do
    for col = 1, size do
      if cells[row][col].n > grid.max_count then grid.max_count = cells[row][col].n end
    end
  end
  return grid
end

-- Re-weights every cell for a slider position. Cheap enough to call whenever
-- the slider moves, but not per frame: the caller keys it on centre/focus.
function M.shade(grid, center, focus)
  if not grid then return nil end
  local max_w = 0
  for row = 1, grid.size do
    for col = 1, grid.size do
      local cell = grid.cells[row][col]
      local sum = 0
      for i = 1, cell.n do
        sum = sum + Bias.weight_for(cell.items[i].w, center, focus)
      end
      cell.weight = sum
      if sum > max_w then max_w = sum end
    end
  end
  grid.max_weight = max_w
  for row = 1, grid.size do
    for col = 1, grid.size do
      local cell = grid.cells[row][col]
      cell.intensity = max_w > 0 and (cell.weight / max_w) or 0
    end
  end
  return grid
end

function M.cell(grid, row, col)
  if not grid or not grid.cells[row] then return nil end
  return grid.cells[row][col]
end

-- One sample out of a cell, drawn with the same weighting that shades it: at
-- the hard end of the slider a cell hands back its hardest hits first.
--
-- Also returns which of the cell's samples it was, and how many there are, so
-- the UI can say "12 of 33". That position is stable for as long as the grid
-- stands, which makes it usable as a label rather than just a count.
function M.pick(grid, row, col, center, focus)
  local cell = M.cell(grid, row, col)
  if not cell or cell.n == 0 then return nil end
  local w = {}
  for i = 1, cell.n do w[i] = Bias.weight_for(cell.items[i].w, center, focus) end
  local idx = Bias.pick_weighted(w) or 1
  return cell.items[idx].path, idx, cell.n
end

-- A running order for one cell: every sample exactly once, the ones matching
-- the slider first. This is what repeated clicks walk through, so auditioning a
-- cell covers all of it instead of rolling the dice again and again.
--
-- Bias.order_indices ranks LOWEST weight first -- core/picker.lua consumes it
-- from the back with table.remove -- so the order is reversed here.
function M.cell_order(grid, row, col, center, focus)
  local cell = M.cell(grid, row, col)
  if not cell or cell.n == 0 then return nil end

  local indices, w = {}, {}
  for i = 1, cell.n do
    indices[i] = i
    w[i] = Bias.weight_for(cell.items[i].w, center, focus)
  end

  local ranked = Bias.order_indices(indices, w)
  local out = {}
  for i = #ranked, 1, -1 do out[#out + 1] = ranked[i] end
  return out
end

-- The path at a position in a cell's own item list.
function M.item_path(grid, row, col, index)
  local cell = M.cell(grid, row, col)
  local item = cell and cell.items[index]
  return item and item.path or nil
end

-- Places already-measured points onto an EXISTING grid, using that grid's own
-- bounds instead of fitting new ones.
--
-- That is the whole point: fitting the axes to the kit would spread its 16 pads
-- over the full grid by construction, which is exactly what hides the thing you
-- are looking for. Against the pack's spread you can see four percussion slots
-- sitting in one corner. Points outside the range clamp into the edge cells.
--
-- A point outside the grid's range is clamped into an edge cell, and says so:
-- otherwise it looks exactly like one that genuinely belongs there, and a kit
-- measured against a pack it did not come from reads as "clustered in the
-- corners" when the truth is "off this pack's scale entirely".
--
-- points: { { label = "5", x = 0..1, y = 0..1 }, ... }
-- returns cells[row][col] = { { label, clamped }, ... }, and how many clamped
function M.project(grid, points)
  local out, clamped_n = {}, 0
  if not grid then return out, 0 end
  for _, p in ipairs(points or {}) do
    local x, y = p.x or 0.5, p.y or 0.5
    local clamped = x < grid.x_lo or x > grid.x_hi or y < grid.y_lo or y > grid.y_hi
    if clamped then clamped_n = clamped_n + 1 end

    local col = slot(x, grid.x_lo, grid.x_hi, grid.size)
    local row = grid.size + 1 - slot(y, grid.y_lo, grid.y_hi, grid.size)
    out[row] = out[row] or {}
    out[row][col] = out[row][col] or {}
    local list = out[row][col]
    list[#list + 1] = { label = p.label, clamped = clamped }
  end
  return out, clamped_n
end

-- Cell -> RS5K pad slot.
--
-- The Kit Manager draws its pads bottom-up, MPC style: slot = (row-1)*cols+col
-- with row 1 at the BOTTOM. The grid's rows run top-down. Line the two up and
-- the mapping falls out the way the 4x4 sketch implies: pad 1 (bottom left) is
-- the darkest and shortest, pad 16 (top right) the brightest and longest.
function M.pad_slot(grid, row, col)
  return (grid.size - row) * grid.size + col
end

-- Human-readable span of a cell along one axis, for tooltips.
function M.cell_range(grid, index, axis)
  local lo, hi
  if axis == "x" then
    lo, hi = grid.x_lo, grid.x_hi
  else
    lo, hi = grid.y_lo, grid.y_hi
    index = grid.size + 1 - index -- rows run top-down
  end
  local step = (hi - lo) / grid.size
  return lo + step * (index - 1), lo + step * index
end

return M
