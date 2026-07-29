local M = {}

local function clamp01(v)
  v = tonumber(v) or 0
  if v < 0 then return 0 end
  if v > 1 then return 1 end
  return v
end
M.clamp01 = clamp01

local function sigma_for(focus)
  local f = 1 - clamp01(focus)
  return 0.05 + 2.0 * f * f
end

-- Gaussian weight with an explicit spread, for callers whose focus response is
-- not sigma_for()'s -- see the tag axes in core/tags.lua.
function M.weight_with_sigma(x, center, sigma)
  local d = clamp01(x) - clamp01(center)
  sigma = math.max(1e-6, tonumber(sigma) or 1)
  return math.exp(-(d * d) / (2 * sigma * sigma))
end

-- Gaussian weight for a value already normalised to 0..1. Used directly by the
-- heatmap, where samples carry a measured position rather than a rank.
function M.weight_for(x, center, focus)
  return M.weight_with_sigma(x, center, sigma_for(focus))
end

function M.weight_at(rank, count, center, focus)
  if count <= 1 then return 1 end
  return M.weight_for((rank - 1) / (count - 1), center, focus)
end

function M.weights(count, center, focus)
  local w = {}
  for i = 1, count do
    w[i] = M.weight_at(i, count, center, focus)
  end
  return w
end

-- u is an optional uniform value in [0,1); pass it to make the draw
-- deterministic (the sequencer feeds its own hash-based PRNG).
function M.pick_weighted(w, u)
  local n = #w
  if n == 0 then return nil end
  if n == 1 then return 1 end
  local total = 0
  for i = 1, n do total = total + (w[i] or 0) end
  if total <= 0 then return u and (1 + math.floor(u * n)) or math.random(n) end
  local roll = (u or math.random()) * total
  local acc = 0
  for i = 1, n do
    acc = acc + (w[i] or 0)
    if roll <= acc then return i end
  end
  return n
end

function M.pick_weighted_subset(indices, w)
  local n = #indices
  if n == 0 then return nil end
  if n == 1 then return indices[1] end
  local total = 0
  for i = 1, n do total = total + (w[indices[i]] or 0) end
  if total <= 0 then return indices[math.random(n)] end
  local roll = math.random() * total
  local acc = 0
  for i = 1, n do
    acc = acc + (w[indices[i]] or 0)
    if roll <= acc then return indices[i] end
  end
  return indices[n]
end

function M.order_indices(indices, w)
  local keyed = {}
  for i = 1, #indices do
    local idx = indices[i]
    local weight = w[idx] or 0
    local key
    if weight <= 1e-12 then
      key = -math.huge
    else
      key = math.log(math.random()) / weight
    end
    keyed[i] = { idx = idx, key = key }
  end
  table.sort(keyed, function(a, b)
    if a.key == b.key then return a.idx < b.idx end
    return a.key < b.key
  end)
  local out = {}
  for i = 1, #keyed do out[i] = keyed[i].idx end
  return out
end

function M.sweep_center(index, total)
  if not total or total <= 1 then return 0 end
  local i = math.max(1, math.min(total, index or 1))
  return (i - 1) / (total - 1)
end

function M.label(center, labels)
  local m = #labels
  if m == 0 then return "" end
  if m == 1 then return labels[1] end
  local p = clamp01(center) * (m - 1)
  local lo = math.floor(p)
  if lo >= m - 1 then return labels[m] end
  local frac = p - lo
  if frac < 0.2 then return labels[lo + 1] end
  if frac > 0.8 then return labels[lo + 2] end
  return labels[lo + 1] .. "-" .. labels[lo + 2]
end

M.LENGTH_LABELS = { "Short", "Medium", "Long" }

function M.length_label(center)
  return M.label(center, M.LENGTH_LABELS)
end

function M.is_active(cfg)
  return cfg ~= nil and cfg.enabled == true and (tonumber(cfg.focus) or 0) > 0
end

function M.for_kit(cfg, kit_index, kit_count)
  if not M.is_active(cfg) then return nil end
  local center = clamp01(cfg.center == nil and 0.5 or cfg.center)
  if cfg.sweep and (kit_count or 1) > 1 then
    center = M.sweep_center(kit_index, kit_count)
  end
  return { center = center, focus = clamp01(cfg.focus) }
end

function M.new_config()
  return { enabled = false, center = 0.5, focus = 0.6, sweep = false }
end

function M.new_folder_config()
  return { enabled = false, root = 1, amount = 0 }
end

-- Maps a bipolar amount (-1..1) around an anchor position to a 0..1 center:
-- amount 0 keeps the anchor, +1 pushes to the top, -1 to the bottom.
function M.center_from_anchor(anchor_index, count, amount)
  if not count or count < 2 then return 0.5 end
  local i = math.max(1, math.min(count, math.floor(tonumber(anchor_index) or 1)))
  local a = tonumber(amount) or 0
  if a < -1 then a = -1 elseif a > 1 then a = 1 end
  local pos = (i - 1) / (count - 1)
  if a >= 0 then return clamp01(pos + a * (1 - pos)) end
  return clamp01(pos + a * pos)
end

function M.for_folders(cfg, folder_count)
  folder_count = folder_count or 0
  if not cfg or cfg.enabled ~= true or folder_count < 2 then return nil end
  local amount = tonumber(cfg.amount) or 0
  if amount < -1 then amount = -1 elseif amount > 1 then amount = 1 end
  if amount == 0 then return nil end
  local root = math.floor(tonumber(cfg.root) or 1)
  if root < 1 then root = 1 elseif root > folder_count then root = folder_count end
  return { center = M.center_from_anchor(root, folder_count, amount), focus = math.abs(amount) }
end

function M.folder_label(amount)
  local a = tonumber(amount) or 0
  if a <= -0.999 then return "Lowest only" end
  if a >= 0.999 then return "Highest only" end
  if a > -0.02 and a < 0.02 then return "No bias (all folders)" end
  return string.format("%s %d%%%%", a < 0 and "Down" or "Up", math.floor(math.abs(a) * 100 + 0.5))
end

return M
