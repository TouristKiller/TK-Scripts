-- The character bias widget, shared by Explosion, Builder and the per-slot
-- override so they cannot drift apart.
--
-- Each axis is a gaussian over the measured tag values: the centre says which
-- end of the axis to lean towards, the focus how hard. It weights the pool
-- rather than filtering it, so a batch of 50 kits still comes out as 50
-- different kits -- they just all lean the same way.

local r = reaper
local Theme = require("core.theme")
local Tags = require("core.tags")
local Bias = require("core.bias")

local M = {}

local FOCUS_W = 92

-- Draws the three axis rows. Returns true when anything changed.
function M.draw(ctx, cfg, id, opts)
  opts = opts or {}
  local changed = false
  local c = Theme.colors

  for _, axis_id in ipairs(Tags.BIAS_AXES) do
    local axis = Tags.axis(axis_id)
    local row = cfg[axis_id]
    if axis and row then
      r.ImGui_PushID(ctx, id .. "_" .. axis_id)

      local on_changed, on_value = r.ImGui_Checkbox(ctx, "##on", row.enabled == true)
      if on_changed then
        row.enabled = on_value
        changed = true
      end
      if r.ImGui_IsItemHovered(ctx) then
        r.ImGui_SetTooltip(ctx, string.format("Lean the whole kit towards one end of %s.", axis.label:lower()))
      end

      r.ImGui_SameLine(ctx)
      r.ImGui_AlignTextToFramePadding(ctx)
      local label_col = row.enabled and c.text or c.text_faint
      r.ImGui_TextColored(ctx, label_col, axis.label)

      r.ImGui_SameLine(ctx)
      r.ImGui_SetCursorPosX(ctx, r.ImGui_GetCursorPosX(ctx) + math.max(0, 78 - (r.ImGui_CalcTextSize(ctx, axis.label) or 60)))

      r.ImGui_BeginDisabled(ctx, row.enabled ~= true)

      -- The centre slider reads out in the tag vocabulary rather than in
      -- numbers: "HARD" says more than 0.78.
      local labels = Tags.BIAS_LABELS[axis_id] or { axis.lo:upper(), axis.hi:upper() }
      local word = Bias.label(row.center or 0.5, labels)
      local avail = r.ImGui_GetContentRegionAvail(ctx)
      local center_w = math.max(110, (tonumber(avail) or 300) - FOCUS_W - 18)
      r.ImGui_SetNextItemWidth(ctx, center_w)
      local c_changed, c_value = r.ImGui_SliderDouble(ctx, "##center", row.center or 0.5, 0, 1, word)
      if c_changed then
        row.center = c_value
        changed = true
      end
      if r.ImGui_IsItemHovered(ctx) then
        r.ImGui_SetTooltip(ctx, string.format("%s \226\134\146 %s", axis.lo, axis.hi))
      end

      r.ImGui_SameLine(ctx)
      r.ImGui_SetNextItemWidth(ctx, FOCUS_W)
      local f_changed, f_value = r.ImGui_SliderDouble(ctx, "##focus", row.focus or 0.6, 0, 1, "focus %.2f")
      if f_changed then
        row.focus = f_value
        changed = true
      end
      if r.ImGui_IsItemHovered(ctx) then
        r.ImGui_SetTooltip(ctx, "How strongly to lean. 0 leaves the pool untouched;\n1 all but ignores anything off the mark.")
      end

      r.ImGui_EndDisabled(ctx)
      r.ImGui_PopID(ctx)
    end
  end

  if opts.analysed and opts.total then
    local pushed = Theme.push_small(ctx)
    if opts.total == 0 then
      Theme.label(ctx, "No samples in the pool yet.")
    elseif opts.analysed == 0 and Tags.bias_active(cfg) then
      r.ImGui_TextColored(ctx, c.warning,
        "None of these samples has been analysed, so character has no effect \226\128\148 analyse the pack in the Browser first.")
    elseif opts.analysed < opts.total and Tags.bias_active(cfg) then
      r.ImGui_TextColored(ctx, c.text_dim, string.format(
        "%d of %d samples analysed; the rest count as average and are not favoured.",
        opts.analysed, opts.total))
    else
      Theme.label(ctx, string.format("%d of %d samples analysed.", opts.analysed, opts.total))
    end
    Theme.pop_font(ctx, pushed)
  end

  return changed
end

-- One-line readout for collapsed headers.
function M.summary(cfg)
  return Tags.bias_summary(cfg)
end

-- Migrates a stored config, so presets saved before this existed still load.
function M.sanitize(cfg)
  local out = Tags.new_bias_config()
  if type(cfg) ~= "table" then return out end
  for _, id in ipairs(Tags.BIAS_AXES) do
    local src = cfg[id]
    if type(src) == "table" then
      out[id].enabled = src.enabled == true
      out[id].center = math.max(0, math.min(1, tonumber(src.center) or 0.5))
      out[id].focus = math.max(0, math.min(1, tonumber(src.focus) or 0.6))
    end
  end
  return out
end

return M
