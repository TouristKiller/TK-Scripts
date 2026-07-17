-- Milestone 1: Folder Explosion -- the "5-click flow".
-- Fills the SAME KitDef/Pool/Slot structures as the full Kit Builder via
-- Engine.kitdef_from_explosion(); Detonate calls the SAME Engine.generate_kit().

local r = reaper
local Engine   = require("core.engine")
local Dialogs  = require("core.dialogs")
local Scanner  = require("core.scanner")
local Theme    = require("core.theme")
local Naming   = require("core.naming")
local Categories = require("core.categories")

local M = {}

local MAX_SLOTS = 128

local function trim(s)
  return tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

function M.init(app)
  app.explosion = {
    source_folder = "",
    destination   = "",
    alias         = "",
    name_seed     = "",
    count         = 16,
    start_note    = 36,
    recursive     = true,
    stitched      = false,
    max_sample_seconds = 0,
    pattern       = "",
    found_files   = nil,
    result        = nil,
  }
end

local function rescan_preview(state)
  if state.source_folder == "" then
    state.found_files = nil
    return
  end
  local pool = { folders = { state.source_folder }, recursive = state.recursive }
  local files = Scanner.scan_pool(pool)
  state.found_files = #files
end

local function step_badge(ctx, n)
  local c = Theme.colors
  local x, y = r.ImGui_GetCursorScreenPos(ctx)
  local dl = r.ImGui_GetWindowDrawList(ctx)
  local size = 20
  r.ImGui_DrawList_AddCircleFilled(dl, x + size * 0.5, y + size * 0.5 + 1, size * 0.5, c.accent_soft)
  r.ImGui_DrawList_AddCircle(dl, x + size * 0.5, y + size * 0.5 + 1, size * 0.5, c.accent, 24, 1)
  local tw = r.ImGui_CalcTextSize(ctx, n)
  r.ImGui_DrawList_AddText(dl, x + (size - tw) * 0.5, y + 2, 0xFFFFFFFF, n)
  r.ImGui_Dummy(ctx, size + 6, size)
  r.ImGui_SameLine(ctx)
  r.ImGui_AlignTextToFramePadding(ctx)
end

local function path_row(ctx, id, value, placeholder)
  local avail = select(1, r.ImGui_GetContentRegionAvail(ctx))
  r.ImGui_SetNextItemWidth(ctx, avail - 92)
  if placeholder and r.ImGui_InputTextWithHint then
    return r.ImGui_InputTextWithHint(ctx, id, placeholder, value)
  end
  return r.ImGui_InputText(ctx, id, value)
end

function M.draw(app)
  local ctx = app.ctx
  local state = app.explosion
  local c = Theme.colors

  Theme.help(ctx, "Pick a source folder, a destination folder and the number of slots. Hit Detonate and the script copies random samples into a tidy, renamed kit.")
  r.ImGui_Dummy(ctx, 0, 4)

  step_badge(ctx, "1")
  Theme.section(ctx, "Source folder")
  Theme.help(ctx, "A folder full of kicks, a whole sample pack -- anything you like.")

  local src_changed, src_value = path_row(ctx, "##expl_src", state.source_folder, "Drag or pick a folder with samples...")
  if src_changed then state.source_folder = src_value; rescan_preview(state) end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "Browse##expl_src_browse", 82) then
    local folder = Dialogs.browse_folder("Select source folder", state.source_folder)
    if folder then state.source_folder = folder; rescan_preview(state) end
  end

  local rec_changed, rec_value = r.ImGui_Checkbox(ctx, "Include subfolders##expl_recursive", state.recursive)
  if rec_changed then state.recursive = rec_value; rescan_preview(state) end
  r.ImGui_SameLine(ctx)
  if Theme.ghost_button(ctx, "Rescan##expl_rescan") then rescan_preview(state) end
  if state.found_files ~= nil then
    r.ImGui_SameLine(ctx)
    r.ImGui_AlignTextToFramePadding(ctx)
    local col = state.found_files > 0 and c.success or c.warning
    r.ImGui_TextColored(ctx, col, string.format("%d samples found", state.found_files))
  end

  r.ImGui_Dummy(ctx, 0, 4)
  r.ImGui_Separator(ctx)
  r.ImGui_Dummy(ctx, 0, 4)

  step_badge(ctx, "2")
  Theme.section(ctx, "Destination folder")
  local dst_changed, dst_value = path_row(ctx, "##expl_dst", state.destination, "Where the kit should end up...")
  if dst_changed then state.destination = dst_value end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "Browse##expl_dst_browse", 82) then
    local folder = Dialogs.browse_folder("Select destination folder", state.destination)
    if folder then state.destination = folder end
  end

  r.ImGui_Dummy(ctx, 0, 4)
  r.ImGui_Separator(ctx)
  r.ImGui_Dummy(ctx, 0, 4)

  step_badge(ctx, "3")
  Theme.section(ctx, "Kit layout")

  local field_w = math.min(220, math.max(120, select(1, r.ImGui_GetContentRegionAvail(ctx)) - 60))

  r.ImGui_AlignTextToFramePadding(ctx)
  Theme.label(ctx, "Name in filename (optional)")
  r.ImGui_SetNextItemWidth(ctx, field_w)
  local alias_changed, alias_value = r.ImGui_InputTextWithHint(ctx, "##expl_alias", "e.g. Kick", state.alias)
  if alias_changed then state.alias = alias_value end

  r.ImGui_SetNextItemWidth(ctx, field_w)
  local seed_changed, seed_value = r.ImGui_InputTextWithHint(ctx, "Start word##expl_name_seed", "optional", state.name_seed or "")
  if seed_changed then state.name_seed = trim(seed_value) end

  if Theme.ghost_button(ctx, "Generate kit name##expl_name_generate") then
    local pattern_specs = nil
    if state.pattern ~= "" then
      pattern_specs = Categories.parse_pattern(state.pattern)
    end
    local kitdef, pools = Engine.kitdef_from_explosion({
      source_folder = state.source_folder,
      recursive     = state.recursive,
      alias         = state.alias,
      count         = state.count,
      start_note    = state.start_note,
      destination   = state.destination,
      stitched      = state.stitched,
      max_sample_seconds = state.max_sample_seconds,
      pattern       = pattern_specs,
      name_seed     = state.name_seed,
    })
    state.alias = Engine.suggest_kit_name(kitdef, pools, app.script_path, state.name_seed)
  end

  r.ImGui_SetNextItemWidth(ctx, field_w)
  local count_changed, count_value = r.ImGui_SliderInt(ctx, "Slot count##expl_count", state.count, 1, MAX_SLOTS, "%d")
  if count_changed then state.count = count_value end

  local max_start_note = math.max(0, 127 - state.count + 1)
  r.ImGui_SetNextItemWidth(ctx, field_w)
  local note_changed, note_value = r.ImGui_SliderInt(ctx, "Start note##expl_note", state.start_note, 0, max_start_note, "%d")
  if note_changed then state.start_note = note_value end
  if state.start_note > max_start_note then state.start_note = max_start_note end
  r.ImGui_SameLine(ctx)
  r.ImGui_AlignTextToFramePadding(ctx)
  local last_note = math.min(127, state.start_note + state.count - 1)
  Theme.label(ctx, string.format("%s -> %s", Naming.note_name(state.start_note), Naming.note_name(last_note)))

  -- Optional slot pattern: repeats cyclically over the slots
  local avail = select(1, r.ImGui_GetContentRegionAvail(ctx))
  r.ImGui_SetNextItemWidth(ctx, math.min(avail - 40, 420))
  local pat_changed, pat_value = r.ImGui_InputTextWithHint(ctx, "##expl_pattern", "Slot pattern (optional), e.g. Kick, Snare, Hihat, Clap", state.pattern)
  if pat_changed then state.pattern = pat_value end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Comma-separated categories or keywords, assigned to slots in order.\nThe pattern repeats to fill all slots (4 entries x 16 slots = 4 rounds).\nEmpty = any sample. Unknown words match as 'name contains'.") end
  r.ImGui_SameLine(ctx)
  if Theme.ghost_button(ctx, "+##expl_pattern_add", 26) then
    r.ImGui_OpenPopup(ctx, "##expl_pattern_popup")
  end
  if r.ImGui_BeginPopup(ctx, "##expl_pattern_popup") then
    for _, cat in ipairs(Categories.list) do
      if r.ImGui_Selectable(ctx, cat.label .. "##pat_add_" .. cat.id) then
        state.pattern = state.pattern == "" and cat.label or (state.pattern .. ", " .. cat.label)
      end
    end
    r.ImGui_EndPopup(ctx)
  end

  if state.pattern ~= "" then
    local _, labels = Categories.parse_pattern(state.pattern)
    if #labels > 0 then
      local parts = {}
      for i = 1, math.min(#labels, 8) do parts[#parts + 1] = i .. " " .. labels[i] end
      if #labels > 8 then parts[#parts + 1] = "..." end
      local preview = table.concat(parts, "  ·  ")
      if state.count > #labels then preview = preview .. "  ·  (repeats)" end
      Theme.help(ctx, preview)
    end
  end

  local st_changed, st_value = r.ImGui_Checkbox(ctx, "Stitched WAV + cues##expl_stitched", state.stitched)
  if st_changed then state.stitched = st_value end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Also joins all samples into one WAV with embedded cue points per slice (for slicers).\nWAV sources only; other formats are skipped.") end

  r.ImGui_AlignTextToFramePadding(ctx)
  Theme.label(ctx, "Max sample length (s)")
  r.ImGui_SameLine(ctx)
  r.ImGui_SetNextItemWidth(ctx, 100)
  local ml_changed, ml_value = r.ImGui_InputDouble(ctx, "##expl_maxlen", state.max_sample_seconds, 0, 0, "%.1f")
  if ml_changed then state.max_sample_seconds = math.max(0, ml_value) end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Samples longer than this are never picked for the kit\n(and stay out of the stitched WAV). 0 = no limit.") end

  r.ImGui_Dummy(ctx, 0, 6)

  local can_detonate = state.source_folder ~= "" and state.destination ~= ""
  if not can_detonate then
    r.ImGui_AlignTextToFramePadding(ctx)
    r.ImGui_TextColored(ctx, c.text_faint, "Pick a source and destination folder first.")
  end

  local detonate_w = math.min(180, math.max(120, select(1, r.ImGui_GetContentRegionAvail(ctx))))
  r.ImGui_BeginDisabled(ctx, not can_detonate)
  if Theme.primary_button(ctx, "Detonate", detonate_w, 38) then
    local pattern_specs = nil
    if state.pattern ~= "" then
      pattern_specs = Categories.parse_pattern(state.pattern)
    end
    local kitdef, pools = Engine.kitdef_from_explosion({
      source_folder = state.source_folder,
      recursive     = state.recursive,
      alias         = state.alias,
      count         = state.count,
      start_note    = state.start_note,
      destination   = state.destination,
      stitched      = state.stitched,
      max_sample_seconds = state.max_sample_seconds,
      pattern       = pattern_specs,
      name_seed     = state.name_seed,
    })
    Engine.rescan_pools(pools, true)
    state.result = Engine.generate_kit(kitdef, pools, 1, app.script_path)
  end
  r.ImGui_EndDisabled(ctx)

  -- Result popup (modal): opens after Detonate, stays until closed
  if state.result then
    if not r.ImGui_IsPopupOpen(ctx, "Kit exported###expl_result") then
      r.ImGui_OpenPopup(ctx, "Kit exported###expl_result")
    end
    local visible, popup_open = r.ImGui_BeginPopupModal(ctx, "Kit exported###expl_result", true, r.ImGui_WindowFlags_AlwaysAutoResize())
    if visible then
      local res = state.result
      Theme.section(ctx, res.name)
      Theme.label(ctx, res.dest)
      r.ImGui_Dummy(ctx, 0, 2)
      r.ImGui_TextColored(ctx, c.success, string.format("%d samples copied", #res.results))
      if res.stitched then
        local stitched_name = res.stitched:match("([^/\\]+)$") or res.stitched
        r.ImGui_Text(ctx, "Stitched: " .. stitched_name)
      end
      if #res.errors > 0 then
        r.ImGui_TextColored(ctx, c.danger, string.format("%d errors:", #res.errors))
        if r.ImGui_BeginChild(ctx, "##expl_result_errors", 420, math.min(150, #res.errors * 20 + 8)) then
          for _, err in ipairs(res.errors) do
            r.ImGui_TextWrapped(ctx, err)
          end
          r.ImGui_EndChild(ctx)
        end
      end
      r.ImGui_Dummy(ctx, 0, 4)
      if r.CF_ShellExecute then
        if r.ImGui_Button(ctx, "Open folder##expl_open_folder", 120, 0) then
          r.CF_ShellExecute(res.dest)
        end
        r.ImGui_SameLine(ctx)
      end
      if Theme.primary_button(ctx, "Close##expl_result_close", 120, 0) or not popup_open then
        state.result = nil
        r.ImGui_CloseCurrentPopup(ctx)
      end
      r.ImGui_EndPopup(ctx)
    end
  end
end

return M
