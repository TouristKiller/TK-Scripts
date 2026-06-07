local r = reaper

local M = {}

local current_scale = 1.0

local function clamp(value, min_value, max_value)
  value = tonumber(value) or 1.0
  if value < min_value then return min_value end
  if value > max_value then return max_value end
  return value
end

function M.normalize(value)
  return clamp(value, 0.85, 2.0)
end

function M.set(value)
  current_scale = M.normalize(value)
  return current_scale
end

function M.value()
  return current_scale
end

function M.px(value)
  return (tonumber(value) or 0) * current_scale
end

function M.floor(value)
  return math.floor(M.px(value) + 0.0001)
end

function M.ceil(value)
  return math.ceil(M.px(value) - 0.0001)
end

function M.round(value)
  return math.floor(M.px(value) + 0.5)
end

function M.gap(value)
  return M.round(value)
end

function M.button_h(ctx, base)
  local frame_h = r.ImGui_GetFrameHeight and r.ImGui_GetFrameHeight(ctx) or 0
  return math.max(frame_h or 0, M.round(base or 24))
end

function M.window_size(width, height)
  return M.round(width), M.round(height)
end

function M.text_width(ctx, label)
  if r.ImGui_CalcTextSize then
    local width_value = r.ImGui_CalcTextSize(ctx, tostring(label or ""))
    return tonumber(width_value) or 0
  end
  return #(tostring(label or "")) * M.px(7)
end

function M.text_button_w(ctx, label, min_width, padding)
  local text_w = M.text_width(ctx, label)
  return math.max(M.round(min_width or 0), math.ceil(text_w + M.px((padding or 10) * 2)))
end

function M.short_label(ctx, full, short, width)
  if not width or width <= 0 then return full end
  if M.text_width(ctx, full) + M.px(16) <= width then return full end
  return short or full
end

return M