-- Batch export options + progress for the Kit Builder (milestone 2/3):
-- naming convention, kit count, optional logs, and a per-frame batch runner
-- so large batches (100+ kits) don't freeze the ReaImGui loop.

local r = reaper
local Engine  = require("core.engine")
local Dialogs = require("core.dialogs")
local Theme   = require("core.theme")
local Naming  = require("core.naming")
local Bias    = require("core.bias")
local Tags    = require("core.tags")
local Character = require("ui.character")
local Duration = require("core.duration")
local Rng     = require("core.rng")

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
-- The example is spelled out by Naming rather than typed in, so it cannot drift
-- from what the filenames actually get -- which is exactly what happened when
-- the octave numbering moved and this label still said C1.
local NOTE_STYLES   = {
  { id = "name",   label = "Note name (" .. Naming.note_name(36) .. ")" },
  { id = "number", label = "Note number (36)" },
  { id = "none",   label = "None" },
}

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

-- Kit-wide character. Individual slots can override it (see the Char column in
-- the slots table); this is the default every slot follows.
local function draw_character(app)
  local ctx = app.ctx
  local export = app.kitdef.export
  export.tag_bias = export.tag_bias or Tags.new_bias_config()

  r.ImGui_Dummy(ctx, 0, 2)
  Theme.section(ctx, "Character  \226\128\148  " .. Tags.bias_summary(export.tag_bias))
  Theme.help(ctx, "Leans every slot towards a sound without narrowing it down: a batch of 50 kits still gives 50 different kits, they just all lean the same way. Individual slots can override this in the Char column.")

  local analysed, total = Engine.tag_coverage(app.pools)
  Character.draw(ctx, export.tag_bias, "export", { analysed = analysed, total = total })
end

local function draw_length_bias(app)
  local ctx = app.ctx
  local export = app.kitdef.export
  export.length_bias = export.length_bias or Bias.new_config()
  local cfg = export.length_bias

  r.ImGui_Dummy(ctx, 0, 2)
  Theme.section(ctx, "Length bias")
  Theme.help(ctx, "Steers the random pick towards shorter or longer samples instead of picking flat random.")

  local en_changed, en_value = r.ImGui_Checkbox(ctx, "Enable##export_bias_enable", cfg.enabled == true)
  if en_changed then cfg.enabled = en_value end

  r.ImGui_BeginDisabled(ctx, not cfg.enabled)

  r.ImGui_AlignTextToFramePadding(ctx)
  Theme.label(ctx, "Bias")
  r.ImGui_SameLine(ctx)
  r.ImGui_BeginDisabled(ctx, cfg.sweep == true)
  r.ImGui_SetNextItemWidth(ctx, fit_w(ctx, 240, 60))
  local ctr_changed, ctr_value = r.ImGui_SliderDouble(ctx, "##export_bias_center", cfg.center or 0.5, 0, 1, Bias.length_label(cfg.center or 0.5))
  if ctr_changed then cfg.center = ctr_value end
  r.ImGui_EndDisabled(ctx)
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Left = shortest samples, right = longest samples.") end

  r.ImGui_AlignTextToFramePadding(ctx)
  Theme.label(ctx, "Focus")
  r.ImGui_SameLine(ctx)
  r.ImGui_SetNextItemWidth(ctx, fit_w(ctx, 240, 60))
  local foc_changed, foc_value = r.ImGui_SliderInt(ctx, "##export_bias_focus", math.floor((cfg.focus or 0) * 100 + 0.5), 0, 100, "%d%%")
  if foc_changed then cfg.focus = foc_value / 100 end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "0% = still fully random, 100% = only the samples right at the bias point.") end

  local sw_changed, sw_value = r.ImGui_Checkbox(ctx, "Sweep over batch##export_bias_sweep", cfg.sweep == true)
  if sw_changed then cfg.sweep = sw_value end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Kit 1 uses the shortest samples, the last kit the longest,\nwith every kit in between shifting one step further.") end

  r.ImGui_EndDisabled(ctx)

  if Theme.ghost_button(ctx, string.format("Clear length cache (%d)##export_bias_clear_cache", Duration.cache_size())) then
    Duration.clear_cache()
  end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Forgets all measured sample lengths.\nUse this after replacing or re-rendering files;\nthe next export re-analyzes them.") end
end

-- First thing under Export, as in Explosion: where the kits land is the one
-- setting you must fill in, so it should not be buried among the batch options.
local function draw_destination(app)
  local ctx = app.ctx
  local export = app.kitdef.export

  local avail = select(1, r.ImGui_GetContentRegionAvail(ctx))
  r.ImGui_SetNextItemWidth(ctx, (as_number(avail) or 300) - 92)
  local dest_changed, dest_value = r.ImGui_InputTextWithHint(ctx, "##export_destination", "Where the kits should end up...", export.destination or "")
  if dest_changed then export.destination = dest_value end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "Browse##export_dest_browse", 82) then
    local folder = Dialogs.browse_folder("Select destination folder", export.destination, "destination")
    if folder then export.destination = folder end
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


  r.ImGui_SetNextItemWidth(ctx, fit_w(ctx, 240, 80))
  local count_changed, count_value = r.ImGui_SliderInt(ctx, "Kit count##export_kit_count", export.kit_count or 1, 1, 200, "%d")
  if count_changed then export.kit_count = count_value end

  -- The seed, as in Explosion. It lives on the kitdef rather than on the
  -- dialog, so a preset carries it: a saved Builder setup and its seed rebuild
  -- the same kits together.
  r.ImGui_AlignTextToFramePadding(ctx)
  Theme.label(ctx, "Seed")
  r.ImGui_SameLine(ctx)
  r.ImGui_SetNextItemWidth(ctx, 110)
  local sd_changed, sd_value = r.ImGui_InputInt(ctx, "##export_seed", math.floor(tonumber(kitdef.seed) or 0), 0, 0)
  if sd_changed then
    kitdef.seed = math.max(0, sd_value)
    kitdef.seed_auto = false
  end
  if r.ImGui_IsItemHovered(ctx) then
    r.ImGui_SetTooltip(ctx,
      "The same seed over the same samples builds the same kits --\n"
        .. "on any machine. A batch runs on consecutive seeds, so kit 34\n"
        .. "of seed 84213 is simply seed 84246 on its own.")
  end

  r.ImGui_SameLine(ctx)
  if Theme.ghost_button(ctx, "Roll##export_seed_roll", 54, 0) then
    kitdef.seed = Rng.new_seed()
    kitdef.seed_auto = false
  end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Pick a new seed now.") end

  r.ImGui_SameLine(ctx)
  local sa_changed, sa_value = r.ImGui_Checkbox(ctx, "New seed each export##export_seed_auto", kitdef.seed_auto ~= false)
  if sa_changed then kitdef.seed_auto = sa_value end
  if r.ImGui_IsItemHovered(ctx) then
    r.ImGui_SetTooltip(ctx,
      "On: different kits every export, with the seed left here afterwards.\n"
        .. "Off: the same kits every export, until you change the seed.")
  end

  local pack = Engine.pack_fingerprint(app.pools)
  if pack then
    local pushed_fp = Theme.push_small(ctx)
    r.ImGui_TextColored(ctx, Theme.colors.text_faint, "pack " .. pack)
    Theme.pop_font(ctx, pushed_fp)
    if r.ImGui_IsItemHovered(ctx) then
      r.ImGui_SetTooltip(ctx,
        "Identifies the samples in your pools. A seed only rebuilds\n"
          .. "the same kits for someone whose pools show this same code.")
    end
  end

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

  -- Beside the stitch rather than under Naming, because it only means anything
  -- with the stitch on: it says what to do with the one-shots afterwards.
  flow_same_line(ctx, checkbox_width(ctx, "Cue file only"))
  r.ImGui_BeginDisabled(ctx, not export.write_stitched)
  local so_changed, so_value = r.ImGui_Checkbox(ctx, "Cue file only##export_stitched_only", export.stitched_only == true)
  if so_changed then export.stitched_only = so_value end
  r.ImGui_EndDisabled(ctx)
  if r.ImGui_IsItemHovered(ctx, r.ImGui_HoveredFlags_AllowWhenDisabled and r.ImGui_HoveredFlags_AllowWhenDisabled() or nil) then
    r.ImGui_SetTooltip(ctx, export.write_stitched
      and ("Keep the stitched WAV and its cue sheet, and delete the one-shots that went into it."
        .. "\nA kit for a slicer is one file; the copies beside it are the same audio twice."
        .. "\n\nAnything the stitcher skipped is kept and named in the result, so a sample"
        .. "\nthat is not in the stitched file is never the one that gets deleted.")
      or "Needs 'Stitched WAV + cues' -- it decides what happens to the one-shots after stitching.")
  end

  r.ImGui_AlignTextToFramePadding(ctx)
  Theme.label(ctx, "Max sample length (s)")
  r.ImGui_SameLine(ctx)
  r.ImGui_SetNextItemWidth(ctx, 100)
  local ml_changed, ml_value = r.ImGui_InputDouble(ctx, "##export_maxlen", export.max_sample_seconds or 0, 0, 0, "%.1f")
  if ml_changed then export.max_sample_seconds = math.max(0, ml_value) end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Samples longer than this are never picked for a kit\n(and stay out of the stitched WAV). 0 = no limit.\nLocked samples are always used.") end

  draw_length_bias(app)
  draw_character(app)
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

  if batch.prefetch then
    local pf = batch.prefetch
    r.ImGui_ProgressBar(ctx, pf.total > 0 and (pf.index / pf.total) or 0, 380, 0, string.format("Analyzing sample lengths  %d / %d", pf.index, pf.total))
    r.ImGui_Dummy(ctx, 0, 2)
  end

  r.ImGui_ProgressBar(ctx, batch.index / batch.total, 380, 0, string.format("%d / %d", batch.index, batch.total))

  local close_requested = false
  if batch.done then
    r.ImGui_Dummy(ctx, 0, 2)
    r.ImGui_TextColored(ctx, c.success, string.format("Done: %d kits generated.", #batch.kits))

    if #batch.kits > 0 then
      if r.ImGui_BeginChild(ctx, "##export_result_kits", 380, math.min(150, #batch.kits * 20 + 8)) then
        for _, kit in ipairs(batch.kits) do
          r.ImGui_Text(ctx, (kit.stitched_only_removed or 0) > 0
            and string.format("%s  (%d samples \226\134\146 cue file)", kit.name, #kit.results)
            or string.format("%s  (%d samples)", kit.name, #kit.results))
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

  -- Not collapsible: the button that does the thing must not be foldable away.
  Theme.step(ctx, "3", "Export")
  r.ImGui_Indent(ctx, 6)

  draw_destination(app)
  draw_naming_options(app)
  draw_batch_options(app)

  r.ImGui_Dummy(ctx, 0, 4)

  -- Readiness at a glance. A slot with no pool is silently skipped on export,
  -- and finding those meant reading down the whole table.
  local slots = app.kitdef.slots or {}
  local no_pool = 0
  for _, slot in ipairs(slots) do
    if not slot.pool_id or not app.pools[slot.pool_id] then no_pool = no_pool + 1 end
  end

  local has_slots = #slots > 0
  local has_destination = app.kitdef.export.destination and app.kitdef.export.destination ~= ""
  local can_export = has_slots and has_destination

  if has_slots then
    r.ImGui_AlignTextToFramePadding(ctx)
    if no_pool > 0 then
      r.ImGui_TextColored(ctx, c.warning, string.format(
        "%d slots, %d without a pool \226\128\148 those stay empty.", #slots, no_pool))
    else
      r.ImGui_TextColored(ctx, c.success, string.format("%d slots, all linked to a pool.", #slots))
    end
  end

  if not can_export then
    r.ImGui_AlignTextToFramePadding(ctx)
    r.ImGui_TextColored(ctx, c.text_faint, has_slots
      and "Pick a destination folder to export."
      or "Add slots and pick a destination folder to export.")
  end

  local export_w = math.min(180, math.max(120, select(1, r.ImGui_GetContentRegionAvail(ctx))))
  r.ImGui_BeginDisabled(ctx, not can_export)
  if Theme.primary_button(ctx, "Batch export", export_w, 38) then
    Engine.rescan_pools(app.pools, false)
    -- Rolled before the run, so the field ends up showing the seed that built
    -- the kits you have, not the one for the next press.
    if app.kitdef.seed_auto ~= false or not tonumber(app.kitdef.seed) then
      app.kitdef.seed = Rng.new_seed()
    end
    -- Remembered here rather than when the batch finishes: a cancelled run has
    -- still written the kits it got through, and that half-finished folder is
    -- exactly the one you want to go and look at.
    Dialogs.set_last_export_folder(app.kitdef.export.destination)
    app.export_batch = Engine.new_batch(app.kitdef, app.pools, app.script_path)
  end
  r.ImGui_EndDisabled(ctx)
  r.ImGui_Unindent(ctx, 6)
end

return M
