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
local Duration = require("core.duration")
local Bias     = require("core.bias")
local Tags     = require("core.tags")
local Rng      = require("core.rng")
local Character = require("ui.character")
local PatternPresets = require("ui.pattern_presets")
local SampleShape = require("core.sample_shape")

local M = {}

local MAX_SLOTS = 128
local DETONATE_STEPS_PER_FRAME = 3

local function trim(s)
  return tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

function M.init(app)
  app.explosion = {
    source_folder = "",
    destination   = "",
    alias         = "",
    kit_name      = "",
    name_seed     = "",
    name_mode     = "variable",
    count         = 16,
    start_note    = 36,
    recursive     = true,
    shape_mode    = "all",
    stitched      = false,
    stitched_only = false,
    max_sample_seconds = 0,
    length_bias   = Bias.new_config(),
    tag_bias      = Tags.new_bias_config(),
    pattern       = "",
    -- Every detonate runs on a seed, whether or not you chose it. Rolling a new
    -- one each time is the old behaviour -- a different kit every press -- but
    -- the number is left in the field afterwards, so a kit you liked is never
    -- unrecoverable. Untick to keep the seed and rebuild the same kit.
    seed          = Rng.new_seed(),
    seed_auto     = true,
    found_files   = nil,
    result        = nil,
  }
end

local function rescan_preview(state)
  if state.source_folder == "" then
    state.found_files = nil
    state.files = nil
    state.cat_counts = nil
    state.keyword_counts = nil
    return
  end
  local pool = { folders = { state.source_folder }, recursive = state.recursive }
  local files = Scanner.scan_pool(pool)
  if state.shape_mode ~= "all" then
    local shaped = {}
    for _, path in ipairs(files) do
      if SampleShape.matches(path, state.shape_mode, Tags.get(path), true) then shaped[#shaped + 1] = path end
    end
    files = shaped
  end
  state.found_files = #files
  state.files = files
  -- Computed here rather than per frame: a seed only describes a kit together
  -- with the samples it drew from, and this is what tells two people whether
  -- they are holding the same pack.
  state.fingerprint = Rng.fingerprint(files)
  state.cat_counts = Categories.count_all(files)
  state.keyword_counts = {}
end

local function split_pattern(str)
  local out = {}
  for part in tostring(str or ""):gmatch("[^,]+") do
    local word = part:match("^%s*(.-)%s*$")
    if word ~= "" then out[#out + 1] = word end
  end
  return out
end

local function spec_count(state, spec)
  if not state.cat_counts then return nil end
  if spec.category then return state.cat_counts[spec.category] end
  if spec.keyword and spec.keyword ~= "" then
    state.keyword_counts = state.keyword_counts or {}
    local key = spec.keyword:lower()
    if state.keyword_counts[key] == nil then
      state.keyword_counts[key] = Categories.match_count(state.files, spec)
    end
    return state.keyword_counts[key]
  end
  return nil
end

-- Lives in core/theme.lua now, so the Builder numbers its steps the same way.
local step_badge = Theme.step_badge

local function path_row(ctx, id, value, placeholder)
  local avail = select(1, r.ImGui_GetContentRegionAvail(ctx))
  r.ImGui_SetNextItemWidth(ctx, avail - 92)
  if placeholder and r.ImGui_InputTextWithHint then
    return r.ImGui_InputTextWithHint(ctx, id, placeholder, value)
  end
  return r.ImGui_InputText(ctx, id, value)
end

-- Shared with the Builder; see ui/pattern_presets.lua.
local function draw_pattern_presets(app, state)
  r.ImGui_SameLine(app.ctx)
  local picked = PatternPresets.button(app.ctx, "expl", state.pattern, state)
  if picked then state.pattern = picked end
end

function M.draw(app)
  local ctx = app.ctx
  local state = app.explosion
  local c = Theme.colors

  if state.source_folder ~= "" and state.found_files == nil then rescan_preview(state) end

  Theme.help(ctx, "Point at a folder of samples, say how many slots you want, and hit Detonate. The script copies random samples into a tidy, renamed kit.")
  r.ImGui_Dummy(ctx, 0, 4)

  step_badge(ctx, "1")
  Theme.section(ctx, "Source folder")
  Theme.help(ctx, "A folder full of kicks, a whole sample pack -- anything you like.")

  local src_changed, src_value = path_row(ctx, "##expl_src", state.source_folder, "Pick or paste a folder with samples...")
  if src_changed then state.source_folder = src_value; rescan_preview(state) end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "Browse##expl_src_browse", 82) then
    local folder = Dialogs.browse_folder("Select source folder", state.source_folder, "source")
    if folder then state.source_folder = folder; rescan_preview(state) end
  end

  local rec_changed, rec_value = r.ImGui_Checkbox(ctx, "Include subfolders##expl_recursive", state.recursive)
  if rec_changed then state.recursive = rec_value; rescan_preview(state) end
  r.ImGui_SameLine(ctx)
  r.ImGui_SetNextItemWidth(ctx, 100)
  local shape_label = state.shape_mode == "loop" and "Loop" or state.shape_mode == "oneshot" and "One-shot" or "All"
  if r.ImGui_BeginCombo(ctx, "##expl_shape", shape_label) then
    for _, option in ipairs({ { "all", "All" }, { "loop", "Loop" }, { "oneshot", "One-shot" } }) do
      if r.ImGui_Selectable(ctx, option[2] .. "##expl_shape_" .. option[1], state.shape_mode == option[1]) then
        state.shape_mode = option[1]
        rescan_preview(state)
      end
    end
    r.ImGui_EndCombo(ctx)
  end
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
  Theme.section(ctx, "Kit layout")
  Theme.help(ctx, "How many slots, and where they sit on the keyboard.")

  local field_w = math.min(220, math.max(120, select(1, r.ImGui_GetContentRegionAvail(ctx)) - 60))

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

  r.ImGui_Dummy(ctx, 0, 4)
  r.ImGui_Separator(ctx)
  r.ImGui_Dummy(ctx, 0, 4)

  step_badge(ctx, "3")
  Theme.section(ctx, "Slot pattern")
  Theme.help(ctx, "Optional. Decides what kind of sample lands in each slot; leave it empty and every slot takes anything.")

  -- Optional slot pattern: repeats cyclically over the slots
  local avail = select(1, r.ImGui_GetContentRegionAvail(ctx))
  r.ImGui_SetNextItemWidth(ctx, math.min(avail - 116, 420))
  local pat_changed, pat_value = r.ImGui_InputTextWithHint(ctx, "##expl_pattern", "e.g. Kick, Snare, Hihat, Clap", state.pattern)
  if pat_changed then state.pattern = pat_value end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Comma-separated categories or keywords, assigned to slots in order.\nThe pattern repeats to fill all slots (4 entries x 16 slots = 4 rounds).\nEmpty = any sample. Unknown words match as 'name contains'.") end
  r.ImGui_SameLine(ctx)
  if Theme.ghost_button(ctx, "+##expl_pattern_add", 26) then
    r.ImGui_OpenPopup(ctx, "##expl_pattern_popup")
  end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Append a category") end
  if r.ImGui_BeginPopup(ctx, "##expl_pattern_popup") then
    for _, cat in ipairs(Categories.list) do
      local n = state.cat_counts and state.cat_counts[cat.id] or nil
      local label = n and string.format("%s  (%d)", cat.label, n) or cat.label
      local empty = n == 0
      if empty then r.ImGui_BeginDisabled(ctx, true) end
      if r.ImGui_Selectable(ctx, label .. "##pat_add_" .. cat.id) then
        state.pattern = state.pattern == "" and cat.label or (state.pattern .. ", " .. cat.label)
      end
      if empty then r.ImGui_EndDisabled(ctx) end
    end
    r.ImGui_EndPopup(ctx)
  end

  draw_pattern_presets(app, state)

  if state.pattern ~= "" then
    local specs, labels = Categories.parse_pattern(state.pattern)
    local words = split_pattern(state.pattern)
    if #labels > 0 then
      local missing = {}
      local pushed = Theme.push_small(ctx)
      local avail_w = select(1, r.ImGui_GetContentRegionAvail(ctx))
      local spacing = 14
      local x = 0
      for i = 1, #labels do
        local n = spec_count(state, specs[i])
        if n == 0 then missing[#missing + 1] = words[i] end
        local text = n and string.format("%d %s (%d)", i, labels[i], n) or string.format("%d %s", i, labels[i])
        local tw = select(1, r.ImGui_CalcTextSize(ctx, text))
        if x > 0 then
          if x + spacing + tw > avail_w then
            x = 0
          else
            r.ImGui_SameLine(ctx, 0, spacing)
            x = x + spacing
          end
        end
        local col = (n == nil and c.text_dim) or (n == 0 and c.danger) or c.success
        r.ImGui_TextColored(ctx, col, text)
        if n == 0 and r.ImGui_IsItemHovered(ctx) then
          r.ImGui_SetTooltip(ctx, "No matching samples in the source folder.\nThese slots will be skipped on Detonate.")
        end
        x = x + tw
      end
      Theme.pop_font(ctx, pushed)

      if state.count > #labels then Theme.help(ctx, "Pattern repeats to fill all slots.") end

      if #missing > 0 then
        if Theme.ghost_button(ctx, string.format("Drop %d empty##expl_pattern_clean", #missing)) then
          local kept = {}
          for i = 1, #words do
            if spec_count(state, specs[i]) ~= 0 then kept[#kept + 1] = words[i] end
          end
          state.pattern = table.concat(kept, ", ")
        end
        if r.ImGui_IsItemHovered(ctx) then
          r.ImGui_SetTooltip(ctx, "Removes: " .. table.concat(missing, ", "))
        end
      end
    end
  end

  r.ImGui_Dummy(ctx, 0, 4)
  r.ImGui_Separator(ctx)
  r.ImGui_Dummy(ctx, 0, 4)

  -- Naming comes last on purpose: it is the part you think about once the kit
  -- itself is settled, and it used to open this half of the page.
  step_badge(ctx, "4")
  Theme.section(ctx, "Naming")
  Theme.help(ctx, "Optional. Leave the kit name empty for a random one.")

  r.ImGui_SetNextItemWidth(ctx, field_w)
  local kn_changed, kn_value = r.ImGui_InputTextWithHint(ctx, "Kit name##expl_kit_name", "empty = random name", state.kit_name or "")
  if kn_changed then state.kit_name = kn_value end

  -- Seed and button sit right under the field they fill, so the chain
  -- start word -> Generate -> kit name is visible instead of implied.
  r.ImGui_SetNextItemWidth(ctx, field_w)
  local seed_changed, seed_value = r.ImGui_InputTextWithHint(ctx, "Start word##expl_name_seed", "optional", state.name_seed or "")
  if seed_changed then state.name_seed = trim(seed_value) end

  local name_mode = state.name_mode == "three" and "three" or "variable"
  local name_mode_label = name_mode == "three" and "Always 3 words" or "Variable: 2 or 3 words"
  r.ImGui_SetNextItemWidth(ctx, field_w)
  if r.ImGui_BeginCombo(ctx, "Name structure##expl_name_mode", name_mode_label) then
    if r.ImGui_Selectable(ctx, "Variable: list 1 + optional list 2 + list 3", name_mode == "variable") then
      state.name_mode = "variable"
    end
    if r.ImGui_Selectable(ctx, "Always 3: list 1 + list 2 + list 3", name_mode == "three") then
      state.name_mode = "three"
    end
    r.ImGui_EndCombo(ctx)
  end

  if Theme.ghost_button(ctx, "Generate kit name##expl_name_generate") then
    local pattern_specs = nil
    if state.pattern ~= "" then
      pattern_specs = Categories.parse_pattern(state.pattern)
    end
    local kitdef, pools = Engine.kitdef_from_explosion({
      source_folder = state.source_folder,
      shape_mode    = state.shape_mode,
      recursive     = state.recursive,
      alias         = state.alias,
      count         = state.count,
      start_note    = state.start_note,
      destination   = state.destination,
      stitched      = state.stitched,
      max_sample_seconds = state.max_sample_seconds,
      pattern       = pattern_specs,
      name_seed     = state.name_seed,
      name_mode     = state.name_mode,
    })
    state.kit_name = Engine.suggest_kit_name(kitdef, pools, app.script_path, state.name_seed)
  end
  if r.ImGui_IsItemHovered(ctx) then
    r.ImGui_SetTooltip(ctx, "Fills the kit name above with a generated one.\nWith a start word it builds around that word.")
  end

  r.ImGui_SetNextItemWidth(ctx, field_w)
  local alias_changed, alias_value = r.ImGui_InputTextWithHint(ctx, "Name in filename##expl_alias", "e.g. Kick", state.alias)
  if alias_changed then state.alias = alias_value end
  if r.ImGui_IsItemHovered(ctx) then
    r.ImGui_SetTooltip(ctx, "Added to every copied sample's filename.\nThe kit name above names the folder.")
  end

  r.ImGui_Dummy(ctx, 0, 4)
  r.ImGui_Separator(ctx)
  r.ImGui_Dummy(ctx, 0, 4)

  step_badge(ctx, "5")
  Theme.section(ctx, "Export")
  Theme.help(ctx, "Where the kit lands, what gets picked, and what comes out.")

  -- The destination sits here rather than up front: it is an output setting,
  -- like the stitched WAV below it, and the Builder has always kept it with the
  -- export. Everything above this point is about the kit itself.
  local dst_changed, dst_value = path_row(ctx, "##expl_dst", state.destination, "Where the kit should end up...")
  if dst_changed then state.destination = dst_value end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "Browse##expl_dst_browse", 82) then
    local folder = Dialogs.browse_folder("Select destination folder", state.destination, "destination")
    if folder then state.destination = folder end
  end

  r.ImGui_Dummy(ctx, 0, 4)

  -- The seed. Every detonate uses one; this only decides whether you pick it.
  r.ImGui_AlignTextToFramePadding(ctx)
  Theme.label(ctx, "Seed")
  r.ImGui_SameLine(ctx)
  r.ImGui_SetNextItemWidth(ctx, 110)
  local seed_num_changed, seed_num = r.ImGui_InputInt(ctx, "##expl_seed", math.floor(tonumber(state.seed) or 0), 0, 0)
  if seed_num_changed then
    state.seed = math.max(0, seed_num)
    state.seed_auto = false
  end
  if r.ImGui_IsItemHovered(ctx) then
    r.ImGui_SetTooltip(ctx,
      "The same seed over the same samples builds the same kit --\n"
        .. "on any machine, so a kit can be shared as a number\ninstead of as files.")
  end

  r.ImGui_SameLine(ctx)
  if Theme.ghost_button(ctx, "Roll##expl_seed_roll", 54, 0) then
    state.seed = Rng.new_seed()
    state.seed_auto = false
  end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Pick a new seed now.") end

  r.ImGui_SameLine(ctx)
  local auto_changed, auto_value = r.ImGui_Checkbox(ctx, "New seed each detonate##expl_seed_auto", state.seed_auto ~= false)
  if auto_changed then state.seed_auto = auto_value end
  if r.ImGui_IsItemHovered(ctx) then
    r.ImGui_SetTooltip(ctx,
      "On: a different kit every press, and the seed it used is left\n"
        .. "here afterwards -- so a kit you liked can always be rebuilt.\n"
        .. "Off: the same kit every press, until you change the seed.")
  end

  -- The other half of the recipe. A seed on its own does not describe a kit:
  -- the same seed over a different set of samples gives a different kit,
  -- correctly but bafflingly. Two people comparing these two numbers can see
  -- at once which of the two is out of step.
  -- On its own line: the row above already holds three controls, and this page
  -- has to survive a narrow window.
  if state.fingerprint then
    local pushed_fp = Theme.push_small(ctx)
    r.ImGui_AlignTextToFramePadding(ctx)
    r.ImGui_TextColored(ctx, c.text_faint, "pack " .. state.fingerprint)
    Theme.pop_font(ctx, pushed_fp)
    if r.ImGui_IsItemHovered(ctx) then
      r.ImGui_SetTooltip(ctx,
        "Identifies the samples this seed will draw from: how many\n"
          .. "there are, and their names. A seed only rebuilds the same kit\n"
          .. "for someone whose pack shows this same code.")
    end
  end

  r.ImGui_Dummy(ctx, 0, 4)

  local st_changed, st_value = r.ImGui_Checkbox(ctx, "Stitched WAV + cues##expl_stitched", state.stitched)
  if st_changed then state.stitched = st_value end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Also joins all samples into one WAV with embedded cue points per slice (for slicers).\nWAV sources only; other formats are skipped.") end

  r.ImGui_SameLine(ctx, nil, 12)
  r.ImGui_BeginDisabled(ctx, not state.stitched)
  local so_changed, so_value = r.ImGui_Checkbox(ctx, "Cue file only##expl_stitched_only", state.stitched_only == true)
  if so_changed then state.stitched_only = so_value end
  r.ImGui_EndDisabled(ctx)
  if r.ImGui_IsItemHovered(ctx, r.ImGui_HoveredFlags_AllowWhenDisabled and r.ImGui_HoveredFlags_AllowWhenDisabled() or nil) then
    r.ImGui_SetTooltip(ctx, state.stitched
      and ("Keep the stitched WAV and its cue sheet, and delete the one-shots that went into it."
        .. "\nA kit for a slicer is one file; the copies beside it are the same audio twice."
        .. "\n\nAnything the stitcher skipped is kept and named in the result.")
      or "Needs 'Stitched WAV + cues' -- it decides what happens to the one-shots after stitching.")
  end

  r.ImGui_AlignTextToFramePadding(ctx)
  Theme.label(ctx, "Max sample length (s)")
  r.ImGui_SameLine(ctx)
  r.ImGui_SetNextItemWidth(ctx, 100)
  local ml_changed, ml_value = r.ImGui_InputDouble(ctx, "##expl_maxlen", state.max_sample_seconds, 0, 0, "%.1f")
  if ml_changed then state.max_sample_seconds = math.max(0, ml_value) end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Samples longer than this are never picked for the kit\n(and stay out of the stitched WAV). 0 = no limit.") end

  local cfg = state.length_bias or Bias.new_config()
  state.length_bias = cfg
  local bias_changed, bias_enabled = r.ImGui_Checkbox(ctx, "Length bias##expl_bias_enable", cfg.enabled == true)
  if bias_changed then cfg.enabled = bias_enabled end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Steers the random pick towards shorter or longer samples\ninstead of picking flat random.") end

  r.ImGui_BeginDisabled(ctx, not cfg.enabled)
  r.ImGui_SameLine(ctx)
  r.ImGui_SetNextItemWidth(ctx, 150)
  local ctr_changed, ctr_value = r.ImGui_SliderDouble(ctx, "##expl_bias_center", cfg.center or 0.5, 0, 1, Bias.length_label(cfg.center or 0.5))
  if ctr_changed then cfg.center = ctr_value end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Left = shortest samples, right = longest samples.") end
  r.ImGui_SameLine(ctx)
  r.ImGui_SetNextItemWidth(ctx, 110)
  local foc_changed, foc_value = r.ImGui_SliderInt(ctx, "##expl_bias_focus", math.floor((cfg.focus or 0) * 100 + 0.5), 0, 100, "Focus %d%%")
  if foc_changed then cfg.focus = foc_value / 100 end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "0% = still fully random, 100% = only the samples right at the bias point.") end
  r.ImGui_EndDisabled(ctx)

  r.ImGui_SameLine(ctx)
  if Theme.ghost_button(ctx, string.format("Clear length cache (%d)##expl_bias_clear_cache", Duration.cache_size())) then
    Duration.clear_cache()
  end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Forgets all measured sample lengths.\nUse this after replacing or re-rendering files;\nthe next detonate re-analyzes them.") end

  r.ImGui_Dummy(ctx, 0, 6)

  -- Character: the same weighting the Browser heatmap uses, applied to the pick.
  -- Shown open rather than folded away -- it is one of the more interesting
  -- controls on the page, and a collapsed header hides that it exists.
  state.tag_bias = state.tag_bias or Tags.new_bias_config()
  r.ImGui_AlignTextToFramePadding(ctx)
  Theme.label(ctx, "Character  \226\128\148  " .. Character.summary(state.tag_bias))
  Theme.help(ctx, "Leans the random pick towards a sound, without narrowing it down: every detonate still gives a different kit, they just all lean the same way.")
  local analysed, total = Engine.tag_coverage({ source = { files = state.files or {} } })
  Character.draw(ctx, state.tag_bias, "expl", { analysed = analysed, total = total })

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
    -- Rolled before the run, not after, so the field shows the seed that built
    -- the kit you are looking at rather than the one for the next press.
    if state.seed_auto ~= false or not tonumber(state.seed) then
      state.seed = Rng.new_seed()
    end
    local kitdef, pools = Engine.kitdef_from_explosion({
      source_folder = state.source_folder,
      shape_mode    = state.shape_mode,
      recursive     = state.recursive,
      alias         = state.alias,
      count         = state.count,
      start_note    = state.start_note,
      destination   = state.destination,
      stitched      = state.stitched,
      stitched_only = state.stitched_only,
      max_sample_seconds = state.max_sample_seconds,
      pattern       = pattern_specs,
      name_seed     = state.name_seed,
      name_mode     = state.name_mode,
      name_prefix   = (trim(state.kit_name) ~= "") and trim(state.kit_name) or nil,
      length_bias   = state.length_bias,
      tag_bias      = state.tag_bias,
      seed          = math.floor(tonumber(state.seed) or 0),
    })
    Engine.rescan_pools(pools, true)
    Dialogs.set_last_export_folder(state.destination)
    state.batch = Engine.new_batch(kitdef, pools, app.script_path)
  end
  r.ImGui_EndDisabled(ctx)

  if state.batch then
    local batch = state.batch
    if not r.ImGui_IsPopupOpen(ctx, "Detonating###expl_progress") then
      r.ImGui_OpenPopup(ctx, "Detonating###expl_progress")
    end
    if r.ImGui_BeginPopupModal(ctx, "Detonating###expl_progress", nil, r.ImGui_WindowFlags_AlwaysAutoResize()) then
      for _ = 1, DETONATE_STEPS_PER_FRAME do
        if batch.done then break end
        batch:step()
      end

      local pf = batch.prefetch
      if pf then
        r.ImGui_ProgressBar(ctx, pf.total > 0 and (pf.index / pf.total) or 0, 340, 0, string.format("Analyzing sample lengths  %d / %d", pf.index, pf.total))
        r.ImGui_Dummy(ctx, 0, 2)
        if Theme.ghost_button(ctx, "Cancel##expl_progress_cancel") then
          state.batch = nil
          r.ImGui_CloseCurrentPopup(ctx)
        end
      else
        r.ImGui_ProgressBar(ctx, 1, 340, 0, "Building kit...")
      end

      if state.batch and batch.done then
        state.batch = nil
        state.result = batch.kits[1] or {
          name = (trim(state.kit_name) ~= "") and trim(state.kit_name) or "Kit",
          dest = state.destination,
          results = {},
          errors = batch.errors,
        }
        r.ImGui_CloseCurrentPopup(ctx)
      end
      r.ImGui_EndPopup(ctx)
    end
  end

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
      -- The recipe, next to the result: this number and the same samples
      -- rebuild this exact kit, here or on anyone else's machine.
      if res.seed then
        local recipe = "Seed " .. tostring(res.seed)
        if state.fingerprint then recipe = recipe .. "   pack " .. state.fingerprint end
        r.ImGui_Text(ctx, recipe)
        r.ImGui_SameLine(ctx)
        if Theme.ghost_button(ctx, "Copy##expl_result_seed", 56, 0) then
          if r.ImGui_SetClipboardText then r.ImGui_SetClipboardText(ctx, recipe) end
        end
        if r.ImGui_IsItemHovered(ctx) then
          r.ImGui_SetTooltip(ctx, "Copy the recipe. Someone whose pack shows the same\ncode can rebuild this exact kit from the seed.")
        end
      end
      if res.stitched then
        local stitched_name = res.stitched:match("([^/\\]+)$") or res.stitched
        r.ImGui_Text(ctx, "Stitched: " .. stitched_name)
      end
      -- Said out loud, because deleting files is not something to leave to be
      -- discovered: the option is a checkbox two rows up on a page you may not
      -- have looked at since last week.
      if (res.stitched_only_removed or 0) > 0 then
        r.ImGui_TextColored(ctx, c.text_dim, string.format(
          "Cue file only: %d one-shot%s removed, the stitched WAV and its cues kept.",
          res.stitched_only_removed, res.stitched_only_removed == 1 and "" or "s"))
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
