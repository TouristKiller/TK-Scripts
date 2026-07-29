-- The slot-pattern preset picker, shared by Explosion and the Builder.
--
-- data/slot_patterns.lua has said "for Folder Explosion and the Kit Builder"
-- since it was written; only Explosion ever had the interface for it. One
-- widget, so both pages offer the same list and a pattern saved in either turns
-- up in the other.

local r = reaper
local Theme = require("core.theme")
local SlotPatterns = require("data.slot_patterns")

local M = {}

local function trim(s)
  return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Draws a "Presets" button and its popup. `store` is any table the caller keeps
-- between frames: the loaded list, the name field and the last error live there.
-- Returns the pattern the user picked, or nil. The caller positions the button.
function M.button(ctx, id, current, store, width)
  local picked = nil
  store.user_patterns = store.user_patterns or SlotPatterns.load()
  store.pattern_save_name = store.pattern_save_name or ""

  if Theme.ghost_button(ctx, "Presets##" .. id .. "_pp", width or 68) then
    r.ImGui_OpenPopup(ctx, "##" .. id .. "_pp_popup")
  end
  if r.ImGui_IsItemHovered(ctx) then
    r.ImGui_SetTooltip(ctx, "Ready-made slot patterns, and your own saved ones.")
  end
  if not r.ImGui_BeginPopup(ctx, "##" .. id .. "_pp_popup") then return nil end

  Theme.label(ctx, "Built-in")
  for _, item in ipairs(SlotPatterns.BUILTIN) do
    if r.ImGui_Selectable(ctx, item.name .. "##bi_" .. item.name) then
      picked = item.pattern
    end
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, item.pattern) end
  end

  r.ImGui_Separator(ctx)
  Theme.label(ctx, "My patterns")
  if #store.user_patterns == 0 then
    r.ImGui_TextColored(ctx, Theme.colors.text_faint, "(none yet)")
  end

  local pending_remove = nil
  for _, item in ipairs(store.user_patterns) do
    if r.ImGui_SmallButton(ctx, "X##up_del_" .. item.name) then pending_remove = item.name end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Selectable(ctx, item.name .. "##up_" .. item.name) then
      picked = item.pattern
    end
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, item.pattern) end
  end
  if pending_remove then
    SlotPatterns.remove(store.user_patterns, pending_remove)
  end

  r.ImGui_Separator(ctx)
  r.ImGui_SetNextItemWidth(ctx, 160)
  local nm_changed, nm_value = r.ImGui_InputTextWithHint(ctx, "##" .. id .. "_pp_name",
    "Preset name", store.pattern_save_name)
  if nm_changed then
    store.pattern_save_name = nm_value
    store.pattern_error = nil
  end

  r.ImGui_SameLine(ctx)
  r.ImGui_BeginDisabled(ctx, trim(store.pattern_save_name) == "" or trim(current) == "")
  if r.ImGui_Button(ctx, "Save##" .. id .. "_pp_save") then
    local ok, err = SlotPatterns.add(store.user_patterns, store.pattern_save_name, current)
    if ok then
      store.pattern_save_name = ""
      store.pattern_error = nil
    else
      store.pattern_error = err
    end
  end
  r.ImGui_EndDisabled(ctx)
  if store.pattern_error then
    r.ImGui_TextColored(ctx, Theme.colors.danger, store.pattern_error)
  end

  r.ImGui_EndPopup(ctx)
  return picked
end

return M
