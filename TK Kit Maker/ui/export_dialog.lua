-- Batch export options + progress for the Kit Builder (milestone 2/3):
-- naming convention, kit count, optional logs, and a per-frame batch runner
-- so large batches (100+ kits) don't freeze the ReaImGui loop.

local r = reaper
local Engine  = require("core.engine")
local Dialogs = require("core.dialogs")
local Theme   = require("core.theme")
local Naming  = require("core.naming")

local M = {}

local function trim(s)
  return tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function fit_w(ctx, want, reserve)
  local avail = select(1, r.ImGui_GetContentRegionAvail(ctx))
  return math.max(100, math.min(want, avail - (reserve or 0)))
end

local function as_number(v)
  if type(v) == "number" then return v end
  if type(v) == "string" then return tonumber(v) end
  return nil
end

local function checkbox_width(ctx, label)
  local caption = label:gsub("##.*$", "")
  local tw = as_number(select(1, r.ImGui_CalcTextSize(ctx, caption))) or 60
  return tw + 34
end

local function flow_same_line(ctx, next_w)
  local last_x2 = as_number(select(1, r.ImGui_GetItemRectMax(ctx))) or 0
  local win_x = as_number(select(1, r.ImGui_GetWindowPos(ctx))) or 0
  local win_w = as_number(r.ImGui_GetWindowWidth(ctx)) or 9999
  local visible_x2 = win_x + win_w - 16
  if (last_x2 + 8 + next_w) < visible_x2 then
    r.ImGui_SameLine(ctx, nil, 12)
  end
end

local STEPS_PER_FRAME = 2

local PREFIX_STYLES = { "1", "01", "001" }
local NOTE_STYLES   = { { id = "name", label = "Note name (C1)" }, { id = "number", label = "Note number (36)" }, { id = "none", label = "None" } }

function M.init(app)
  app.export_batch = nil
end

local function name_preview(app)
  local kitdef = app.kitdef
  local slot = kitdef.slots and kitdef.slots[1]
  if not slot then return nil end
  local pool = slot.pool_id and app.pools[slot.pool_id]
  local ok, name = pcall(Naming.build, slot, "kick_punchy.wav", pool, kitdef.naming)
  return ok and name or nil
end

local function draw_naming_options(app)
  local ctx = app.ctx
  local naming = app.kitdef.naming

  Theme.section(ctx, "Naming")

  r.ImGui_SetNextItemWidth(ctx, fit_w(ctx, 150, 110))
  if r.ImGui_BeginCombo(ctx, "Number style##export_prefix_style", naming.prefix_style) then
    for _, style in ipairs(PREFIX_STYLES) do
      local selected = naming.prefix_style == style
      if r.ImGui_Selectable(ctx, style .. "##prefix_" .. style, selected) then
        naming.prefix_style = style
      end
    end
    r.ImGui_EndCombo(ctx)
  end
  local note_label = "None"
  for _, opt in ipairs(NOTE_STYLES) do
    if opt.id == naming.note_style then note_label = opt.label end
  end
  flow_same_line(ctx, 270)
  r.ImGui_SetNextItemWidth(ctx, fit_w(ctx, 190, 80))
  if r.ImGui_BeginCombo(ctx, "Notation##export_note_style", note_label) then
    for _, opt in ipairs(NOTE_STYLES) do
      local selected = naming.note_style == opt.id
      if r.ImGui_Selectable(ctx, opt.label .. "##note_style_" .. opt.id, selected) then
        naming.note_style = opt.id
      end
    end
    r.ImGui_EndCombo(ctx)
  end

  local inc_changed, inc_value = r.ImGui_Checkbox(ctx, "Alias in filename##export_include_type", naming.include_type)
  if inc_changed then naming.include_type = inc_value end

  flow_same_line(ctx, 130)
  r.ImGui_SetNextItemWidth(ctx, 60)
  local sep_changed, sep_value = r.ImGui_InputText(ctx, "Separator##export_separator", naming.separator)
  if sep_changed then naming.separator = sep_value end

  local preview = name_preview(app)
  if preview then
    r.ImGui_AlignTextToFramePadding(ctx)
    Theme.label(ctx, "Preview:")
    r.ImGui_SameLine(ctx)
    r.ImGui_TextColored(ctx, Theme.colors.accent, preview)
  end
end

local function draw_batch_options(app)
  local ctx = app.ctx
  local kitdef = app.kitdef
  local export = kitdef.export

  r.ImGui_Dummy(ctx, 0, 2)
  Theme.section(ctx, "Batch")

  r.ImGui_SetNextItemWidth(ctx, fit_w(ctx, 200, 120))
  local prefix_changed, prefix_value = r.ImGui_InputTextWithHint(ctx, "Kit name prefix##export_name_prefix", "empty = random", kitdef.name_prefix or "")
  if prefix_changed then kitdef.name_prefix = (prefix_value ~= "") and prefix_value or nil end

  r.ImGui_SetNextItemWidth(ctx, fit_w(ctx, 200, 120))
  local seed_changed, seed_value = r.ImGui_InputTextWithHint(ctx, "Start word##export_name_seed", "optional", kitdef.name_seed or "")
  if seed_changed then kitdef.name_seed = trim(seed_value) end

  local can_suggest = not kitdef.name_prefix or kitdef.name_prefix == ""
  r.ImGui_BeginDisabled(ctx, not can_suggest)
  if r.ImGui_Button(ctx, "Generate kit name##export_name_generate", 130, 0) then
    kitdef.name_prefix = Engine.suggest_kit_name(kitdef, app.pools, app.script_path, trim(kitdef.name_seed))
  end
  r.ImGui_EndDisabled(ctx)
  if r.ImGui_IsItemHovered(ctx) then
    r.ImGui_SetTooltip(ctx, "Only works when Kit name prefix is empty.")
  end

  local avail = select(1, r.ImGui_GetContentRegionAvail(ctx))
  r.ImGui_SetNextItemWidth(ctx, avail - 92)
  local dest_changed, dest_value = r.ImGui_InputTextWithHint(ctx, "##export_destination", "Destination folder for the kits...", export.destination or "")
  if dest_changed then export.destination = dest_value end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "Browse##export_dest_browse", 82) then
    local folder = Dialogs.browse_folder("Select destination folder", export.destination)
    if folder then export.destination = folder end
  end

  r.ImGui_SetNextItemWidth(ctx, fit_w(ctx, 240, 80))
  local count_changed, count_value = r.ImGui_SliderInt(ctx, "Kit count##export_kit_count", export.kit_count or 1, 1, 200, "%d")
  if count_changed then export.kit_count = count_value end

  r.ImGui_Dummy(ctx, 0, 1)
  local midi_changed, midi_value = r.ImGui_Checkbox(ctx, "MIDI log##export_midilog", export.write_midilog)
  if midi_changed then export.write_midilog = midi_value end
  flow_same_line(ctx, checkbox_width(ctx, "Sources log"))
  local src_changed, src_value = r.ImGui_Checkbox(ctx, "Sources log##export_sourcelog", export.write_sourcelog)
  if src_changed then export.write_sourcelog = src_value end
  flow_same_line(ctx, checkbox_width(ctx, "Used-samples log"))
  local used_changed, used_value = r.ImGui_Checkbox(ctx, "Used-samples log##export_usedlog", export.write_usedlog)
  if used_changed then export.write_usedlog = used_value end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Avoids repeats across sessions.") end
  flow_same_line(ctx, checkbox_width(ctx, "Stitched WAV + cues"))
  local st_changed, st_value = r.ImGui_Checkbox(ctx, "Stitched WAV + cues##export_stitched", export.write_stitched)
  if st_changed then export.write_stitched = st_value end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Joins all samples into one WAV with embedded cue points per slice (for slicers).\nWAV sources only; other formats are skipped.") end

  r.ImGui_AlignTextToFramePadding(ctx)
  Theme.label(ctx, "Max sample length (s)")
  r.ImGui_SameLine(ctx)
  r.ImGui_SetNextItemWidth(ctx, 100)
  local ml_changed, ml_value = r.ImGui_InputDouble(ctx, "##export_maxlen", export.max_sample_seconds or 0, 0, 0, "%.1f")
  if ml_changed then export.max_sample_seconds = math.max(0, ml_value) end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Samples longer than this are never picked for a kit\n(and stay out of the stitched WAV). 0 = no limit.\nLocked samples are always used.") end
end

-- Batch progress + result summary in a modal popup. Keeps stepping the batch
-- per frame while open; Cancel stops a running batch, Close dismisses the
-- summary when done.
local function draw_progress_modal(app)
  local ctx = app.ctx
  local c = Theme.colors
  local batch = app.export_batch

  if not r.ImGui_IsPopupOpen(ctx, "Batch export###export_progress") then
    r.ImGui_OpenPopup(ctx, "Batch export###export_progress")
  end
  local visible, popup_open = r.ImGui_BeginPopupModal(ctx, "Batch export###export_progress", true, r.ImGui_WindowFlags_AlwaysAutoResize())
  if not visible then return end

  for _ = 1, STEPS_PER_FRAME do
    if batch.done then break end
    batch:step()
  end

  r.ImGui_ProgressBar(ctx, batch.index / batch.total, 380, 0, string.format("%d / %d", batch.index, batch.total))

  local close_requested = false
  if batch.done then
    r.ImGui_Dummy(ctx, 0, 2)
    r.ImGui_TextColored(ctx, c.success, string.format("Done: %d kits generated.", #batch.kits))

    if #batch.kits > 0 then
      if r.ImGui_BeginChild(ctx, "##export_result_kits", 380, math.min(150, #batch.kits * 20 + 8)) then
        for _, kit in ipairs(batch.kits) do
          r.ImGui_Text(ctx, string.format("%s  (%d samples)", kit.name, #kit.results))
          if #kit.errors > 0 then
            r.ImGui_SameLine(ctx)
            r.ImGui_TextColored(ctx, c.warning, string.format("%d errors", #kit.errors))
          end
        end
        r.ImGui_EndChild(ctx)
      end
    end

    local all_errors = {}
    for _, err in ipairs(batch.errors) do all_errors[#all_errors + 1] = err end
    for _, kit in ipairs(batch.kits) do
      for _, err in ipairs(kit.errors) do all_errors[#all_errors + 1] = kit.name .. ": " .. err end
    end
    if #all_errors > 0 then
      r.ImGui_TextColored(ctx, c.danger, string.format("%d errors:", #all_errors))
      if r.ImGui_BeginChild(ctx, "##export_result_errors", 380, math.min(120, #all_errors * 20 + 8)) then
        for _, err in ipairs(all_errors) do
          r.ImGui_TextWrapped(ctx, err)
        end
        r.ImGui_EndChild(ctx)
      end
    end

    r.ImGui_Dummy(ctx, 0, 4)
    if r.CF_ShellExecute then
      if r.ImGui_Button(ctx, "Open folder##export_open_folder", 120, 0) then
        r.CF_ShellExecute(batch.kitdef.export.destination)
      end
      r.ImGui_SameLine(ctx)
    end
    if Theme.primary_button(ctx, "Close##export_close_progress", 120, 0) then
      close_requested = true
    end
  else
    if r.ImGui_Button(ctx, "Cancel##export_cancel", 120, 0) then
      close_requested = true
    end
  end

  if close_requested or not popup_open then
    app.export_batch = nil
    r.ImGui_CloseCurrentPopup(ctx)
  end
  r.ImGui_EndPopup(ctx)
end

function M.draw(app)
  local ctx = app.ctx
  local c = Theme.colors
  r.ImGui_Dummy(ctx, 0, 2)

  if app.export_batch then
    Theme.section(ctx, "Export")
    draw_progress_modal(app)
    return
  end

  if not r.ImGui_CollapsingHeader(ctx, "Export###export_section") then return end
  r.ImGui_Indent(ctx, 6)

  draw_naming_options(app)
  draw_batch_options(app)

  r.ImGui_Dummy(ctx, 0, 4)
  local has_slots = #(app.kitdef.slots or {}) > 0
  local has_destination = app.kitdef.export.destination and app.kitdef.export.destination ~= ""
  local can_export = has_slots and has_destination

  if not can_export then
    r.ImGui_AlignTextToFramePadding(ctx)
    r.ImGui_TextColored(ctx, c.text_faint, "Add slots and pick a destination folder to export.")
  end

  local export_w = math.min(180, math.max(120, select(1, r.ImGui_GetContentRegionAvail(ctx))))
  r.ImGui_BeginDisabled(ctx, not can_export)
  if Theme.primary_button(ctx, "Batch export", export_w, 38) then
    Engine.rescan_pools(app.pools, false)
    app.export_batch = Engine.new_batch(app.kitdef, app.pools, app.script_path)
  end
  r.ImGui_EndDisabled(ctx)
  r.ImGui_Unindent(ctx, 6)
end

return M
