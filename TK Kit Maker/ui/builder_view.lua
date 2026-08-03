-- Milestone 2/3: Kit Builder -- pool/slot table editor, presets, sample lock
-- and the Quick Preview 128-slot layout helper. Everything here fills the
-- SAME KitDef/Pool/Slot structures the Folder Explosion uses, and export goes
-- through the SAME Engine.generate_kit()/new_batch() (see ui/export_dialog.lua).

local r = reaper
local Engine  = require("core.engine")
local Scanner = require("core.scanner")
local Dialogs = require("core.dialogs")
local Presets = require("data.presets")
local Theme   = require("core.theme")
local Categories = require("core.categories")
local Relink  = require("core.relink")
local Store   = require("core.browser_store")
local Undo    = require("core.undo")
local Bias    = require("core.bias")
local Tags    = require("core.tags")
local Naming  = require("core.naming")
local Character = require("ui.character")
local PatternPresets = require("ui.pattern_presets")

local M = {}

local draw_quick_layout_popup
local draw_pattern_slots_popup

local function fit_w(ctx, want, reserve)
  local avail = select(1, r.ImGui_GetContentRegionAvail(ctx))
  return math.max(120, math.min(want, avail - (reserve or 0)))
end

local function new_naming()
  return { prefix_style = "001", include_type = true, note_style = "name", separator = "_" }
end

local function new_export()
  return { destination = "", kit_count = 1, write_midilog = false, write_sourcelog = false, write_usedlog = false, write_stitched = false, max_sample_seconds = 0, length_bias = Bias.new_config(), tag_bias = Tags.new_bias_config() }
end

function M.new_kitdef()
  return { name_prefix = nil, slots = {}, naming = new_naming(), export = new_export() }
end

function M.init(app)
  app.kitdef = nil
  app.pools = {}
  app.builder = {
    next_pool_n = 1,
    pool_order = {},
    pool_pending_delete = nil,
    undo = Undo.new(),
    preset_name = "",
    preset_status = nil,
    loaded_preset = nil,
    match_cache = {},
    presets_list = Presets.list(),
    quick_white_a = nil,
    quick_white_b = nil,
    quick_black = nil,
  }
end

local function pool_order_from(pools)
  local order = {}
  for id in pairs(pools) do order[#order + 1] = id end
  -- Numerically where the ids allow it: a plain sort puts pool_10 between
  -- pool_1 and pool_2.
  table.sort(order, function(a, b)
    local na = tonumber(a:match("^pool_(%d+)$"))
    local nb = tonumber(b:match("^pool_(%d+)$"))
    if na and nb then return na < nb end
    return a < b
  end)
  return order
end

local function load_preset(app, name)
  local kitdef, pools = Presets.load(name)
  if kitdef then
    -- Loading replaces pools and slots at once, which is the same kind of
    -- "oops" as deleting one -- especially over work that was never saved.
    Undo.push(app.builder.undo, app, "load preset")
    -- Presets written before character bias existed have no config at all, and
    -- one written by a future version may have a partial one; normalise both.
    kitdef.export = kitdef.export or {}
    kitdef.export.tag_bias = Character.sanitize(kitdef.export.tag_bias)
    for _, slot in ipairs(kitdef.slots or {}) do
      if slot.tag_bias ~= nil then
        slot.tag_bias = Character.sanitize(slot.tag_bias)
      end
    end
    app.kitdef = kitdef
    app.pools = pools
    app.builder.pool_order = pool_order_from(pools)
    app.builder.preset_name = name
    app.builder.loaded_preset = name
  end
end

local function add_pool(app)
  -- Skip ids that are already taken rather than trusting the counter. A loaded
  -- preset brings its own pool_1, pool_2... while next_pool_n stays wherever it
  -- was, so "+ Pool" landed straight on top of a pool the preset had filled:
  -- the full one was replaced by an empty one, and pool_order then listed the
  -- same id twice. Checking here covers every caller, now and later.
  local id
  repeat
    id = "pool_" .. tostring(app.builder.next_pool_n)
    app.builder.next_pool_n = app.builder.next_pool_n + 1
  until not app.pools[id]

  app.pools[id] = {
    id = id,
    alias = "Pool " .. id:gsub("pool_", ""),
    folders = {},
    recursive = true,
    files = {},
    mode = "repeat",
    folder_bias = Bias.new_folder_config(),
    _bag = {},
  }
  app.builder.pool_order[#app.builder.pool_order + 1] = id
  return id
end

local function add_slot(app, pool_id)
  local kitdef = app.kitdef
  local number = #kitdef.slots + 1
  kitdef.slots[#kitdef.slots + 1] = {
    number = number,
    pool_id = pool_id,
    midi_note = math.min(127, 35 + number),
    pad = number,
    lock_file = nil,
  }
end

local function pool_sample_count(pool)
  return pool.files and #pool.files or 0
end

local function folder_leaf(path)
  return tostring(path or ""):match("([^/\\]+)$") or tostring(path or "")
end

local function draw_folder_bias(app, pool)
  local ctx = app.ctx
  local n = #(pool.folders or {})

  pool.folder_bias = pool.folder_bias or Bias.new_folder_config()
  local cfg = pool.folder_bias

  r.ImGui_BeginDisabled(ctx, n < 2)
  local en_changed, en_value = r.ImGui_Checkbox(ctx, "Folder bias##folder_bias_enable", cfg.enabled == true)
  if en_changed then cfg.enabled = en_value end
  r.ImGui_EndDisabled(ctx)
  if r.ImGui_IsItemHovered(ctx) then
    r.ImGui_SetTooltip(ctx, "Favours folders around a chosen root folder instead of drawing\nfrom all folders equally. Use the folder order above as the axis.")
  end
  if n < 2 then
    r.ImGui_SameLine(ctx)
    r.ImGui_AlignTextToFramePadding(ctx)
    r.ImGui_TextColored(ctx, Theme.colors.text_faint, "(needs 2+ folders)")
    return
  end

  r.ImGui_BeginDisabled(ctx, not cfg.enabled)

  local root = math.max(1, math.min(n, math.floor(tonumber(cfg.root) or 1)))
  cfg.root = root
  r.ImGui_SetNextItemWidth(ctx, fit_w(ctx, 240, 60))
  if r.ImGui_BeginCombo(ctx, "Root folder##folder_bias_root", string.format("%d. %s", root, folder_leaf(pool.folders[root]))) then
    for i, folder in ipairs(pool.folders) do
      if r.ImGui_Selectable(ctx, string.format("%d. %s##folder_bias_root_%d", i, folder_leaf(folder), i), i == root) then
        cfg.root = i
      end
    end
    r.ImGui_EndCombo(ctx)
  end

  r.ImGui_SetNextItemWidth(ctx, fit_w(ctx, 240, 60))
  local amt_changed, amt_value = r.ImGui_SliderDouble(ctx, "Bias##folder_bias_amount", tonumber(cfg.amount) or 0, -1, 1, Bias.folder_label(cfg.amount))
  if amt_changed then cfg.amount = amt_value end
  if r.ImGui_IsItemHovered(ctx) then
    r.ImGui_SetTooltip(ctx, "0 = every folder equally likely.\nTowards + = the root folder and the ones below it in the list.\nTowards - = the root folder and the ones above it.")
  end

  r.ImGui_EndDisabled(ctx)
end

local function draw_pools(app)
  local ctx = app.ctx
  local c = Theme.colors

  -- Not collapsible: pools and slots are what the Builder is for, and folding
  -- them away leaves a page with nothing on it.
  Theme.step(ctx, "1", "Pools")
  r.ImGui_Indent(ctx, 6)

  if Theme.primary_button(ctx, "+ Pool##builder_add_pool", 96, 0) then add_pool(app) end

  -- Undo appears only when there is something to undo, and looks like an action
  -- rather than a label.
  --
  -- It was a ghost button, greyed out whenever the history was empty -- which is
  -- most of the time. A permanently dim button in a corner is one you learn to
  -- stop seeing, so when it finally mattered it was not findable. Now the row
  -- simply has nothing there until it does, and then it is the brightest thing
  -- in it.
  --
  -- It names what it will put back: a bare "Undo" leaves you guessing whether
  -- it means the pool you just deleted or the slots you replaced before that.
  local label = Undo.label(app.builder.undo)
  if label then
    r.ImGui_SameLine(ctx)
    if Theme.primary_button(ctx, "Undo " .. label .. "##builder_undo", 190, 0) then
      Undo.pop(app.builder.undo, app)
    end
    if r.ImGui_IsItemHovered(ctx) then
      r.ImGui_SetTooltip(ctx, "Ctrl+Z -- puts back what was there before you " .. label .. ".")
    end
  end

  Theme.help(ctx, "A pool points to one or more sample folders. Link slots to it; on export each slot gets a random sample from its pool.")

  if #app.builder.pool_order == 0 then
    r.ImGui_Dummy(ctx, 0, 2)
    r.ImGui_TextColored(ctx, c.text_faint, "No pools yet. Create one with '+ Pool'.")
  end

  for _, pool_id in ipairs(app.builder.pool_order) do
    local pool = app.pools[pool_id]
    if pool then
      r.ImGui_PushID(ctx, pool_id)
      local count = pool_sample_count(pool)
      local header = string.format("%s   (%d)", pool.alias or pool_id, count)
      if r.ImGui_CollapsingHeader(ctx, header .. "###header") then
        r.ImGui_Indent(ctx, 6)
        r.ImGui_SetNextItemWidth(ctx, fit_w(ctx, 240, 60))
        local a_changed, a_value = r.ImGui_InputText(ctx, "Alias##alias", pool.alias)
        if a_changed then pool.alias = a_value end

        -- A fixed pool is a list of files, not a folder: it came out of a
        -- heatmap cell, where what selects a sample is how it measures rather
        -- than where it lives. The folder editor is hidden for it -- not only
        -- because it has nothing to show, but because "+ Add folder" and the
        -- Subfolders checkbox both clear pool.files to force a rescan, and for
        -- this pool that rescan can never put anything back.
        if pool.fixed then
          local pushed_fixed = Theme.push_small(ctx)
          r.ImGui_TextColored(ctx, c.text_faint, pool.fixed_origin or "A fixed set of samples.")
          Theme.pop_font(ctx, pushed_fixed)
          r.ImGui_Dummy(ctx, 0, 2)
        end

        local folder_pending_delete = nil
        local folder_move = nil
        if not pool.fixed then
        Theme.label(ctx, "Folders")
        Theme.help(ctx, "The order matters for the folder bias below: top = low end, bottom = high end.")
        if #pool.folders == 0 then
          r.ImGui_TextColored(ctx, c.text_faint, "(no folders yet)")
        end
        for fi, folder in ipairs(pool.folders) do
          local missing = not Relink.dir_exists(folder)
          r.ImGui_BeginDisabled(ctx, fi == 1)
          if r.ImGui_SmallButton(ctx, "^##folder_up_" .. fi) then folder_move = { from = fi, to = fi - 1 } end
          r.ImGui_EndDisabled(ctx)
          r.ImGui_SameLine(ctx)
          r.ImGui_BeginDisabled(ctx, fi == #pool.folders)
          if r.ImGui_SmallButton(ctx, "v##folder_down_" .. fi) then folder_move = { from = fi, to = fi + 1 } end
          r.ImGui_EndDisabled(ctx)
          r.ImGui_SameLine(ctx)
          r.ImGui_AlignTextToFramePadding(ctx)
          if missing then
            r.ImGui_TextColored(ctx, c.danger, folder)
          else
            r.ImGui_Text(ctx, folder)
          end
          r.ImGui_SameLine(ctx)
          if missing then
            local prefix_map = app.browser and app.browser.relink_prefixes or nil
            local remapped = nil
            if prefix_map then
              for _, e in ipairs(prefix_map) do
                local ol = Relink.normalize(e.old):lower()
                if Relink.normalize(folder):lower():sub(1, #ol) == ol then
                  local cand = Relink.normalize(e.new) .. Relink.normalize(folder):sub(#Relink.normalize(e.old) + 1)
                  if Relink.dir_exists(cand) then remapped = cand break end
                end
              end
            end
            if remapped and r.ImGui_SmallButton(ctx, "Auto##folder_auto_" .. fi) then
              if app.browser then
                local pair = Relink.derive_prefix_pair(folder, remapped)
                if pair then
                  Relink.remember_prefix(app.browser.relink_prefixes, pair.old, pair.new)
                  Store.save(app.browser)
                end
              end
              pool.folders[fi] = remapped
              pool.files = {}
            end
            if remapped and r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Relink to remembered location:\n" .. remapped) end
            if remapped then r.ImGui_SameLine(ctx) end
            if r.ImGui_SmallButton(ctx, "Relink##folder_relink_" .. fi) then
              local pick = Dialogs.browse_folder("Locate folder for " .. (pool.alias or pool_id), remapped or folder, "source")
              if pick and Relink.dir_exists(pick) then
                if app.browser then
                  app.browser.relink_prefixes = app.browser.relink_prefixes or {}
                  local pair = Relink.derive_prefix_pair(folder, pick)
                  if pair then
                    Relink.remember_prefix(app.browser.relink_prefixes, pair.old, pair.new)
                    Store.save(app.browser)
                  end
                end
                pool.folders[fi] = pick
                pool.files = {}
              end
            end
            if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Folder not found - locate its new location") end
            r.ImGui_SameLine(ctx)
          end
          if r.ImGui_SmallButton(ctx, "X##folder_" .. fi) then folder_pending_delete = fi end
        end
        if folder_pending_delete then
          table.remove(pool.folders, folder_pending_delete)
          pool.files = {}
        end
        if folder_move then
          local moved = table.remove(pool.folders, folder_move.from)
          table.insert(pool.folders, folder_move.to, moved)
          pool.files = {}
        end

        if r.ImGui_Button(ctx, "+ Add folder##add_folder") then
          local folder = Dialogs.browse_folder("Select folder for " .. (pool.alias or pool_id), "", "source")
          if folder then pool.folders[#pool.folders + 1] = folder; pool.files = {} end
        end
        r.ImGui_SameLine(ctx)
        local rec_changed, rec_value = r.ImGui_Checkbox(ctx, "Subfolders##recursive", pool.recursive)
        if rec_changed then pool.recursive = rec_value; pool.files = {} end
        end -- not pool.fixed

        r.ImGui_SetNextItemWidth(ctx, fit_w(ctx, 240, 60))
        local mode_label = pool.mode == "use_up" and "Use up (no repeats)" or "Repeat (repeats allowed)"
        if r.ImGui_BeginCombo(ctx, "Mode##mode", mode_label) then
          if r.ImGui_Selectable(ctx, "Repeat (repeats allowed)##mode_repeat", pool.mode ~= "use_up") then pool.mode = "repeat" end
          if r.ImGui_Selectable(ctx, "Use up (no repeats + reshuffle)##mode_useup", pool.mode == "use_up") then pool.mode = "use_up" end
          r.ImGui_EndCombo(ctx)
        end

        -- Folder bias orders the pick across folders; a fixed pool has none.
        if not pool.fixed then
          draw_folder_bias(app, pool)
          if Theme.ghost_button(ctx, "Scan##pool_rescan") then Scanner.scan_pool(pool) end
          r.ImGui_SameLine(ctx)
        end
        if count > 0 then
          r.ImGui_AlignTextToFramePadding(ctx)
          r.ImGui_TextColored(ctx, c.success, count .. " samples")
          r.ImGui_SameLine(ctx)
        end
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), c.danger)
        if r.ImGui_SmallButton(ctx, "Delete pool##delete_pool") then
          app.builder.pool_pending_delete = pool_id
        end
        r.ImGui_PopStyleColor(ctx)

        r.ImGui_Unindent(ctx, 6)
        r.ImGui_Dummy(ctx, 0, 2)
      end
      r.ImGui_PopID(ctx)
    end
  end

  if app.builder.pool_pending_delete then
    -- Taken before, not after: what you want back is the state you had.
    Undo.push(app.builder.undo, app, "delete pool")
    local id = app.builder.pool_pending_delete
    app.pools[id] = nil
    for i, pid in ipairs(app.builder.pool_order) do
      if pid == id then table.remove(app.builder.pool_order, i); break end
    end
    for _, slot in ipairs(app.kitdef.slots) do
      if slot.pool_id == id then slot.pool_id = nil end
    end
    app.builder.pool_pending_delete = nil
  end
  r.ImGui_Unindent(ctx, 6)
end

-- Cached "how many pool files match this filter" lookup for the Filter column.
local function match_count_cached(app, pool, spec)
  local spec_key = spec.keyword and ("k:" .. spec.keyword:lower()) or ("c:" .. tostring(spec.category))
  local key = tostring(pool.id) .. "|" .. spec_key .. "|" .. #pool.files
  local cache = app.builder.match_cache
  local count = cache[key]
  if count == nil then
    count = Categories.match_count(pool.files, spec)
    cache[key] = count
  end
  return count
end

local function draw_filter_cell(app, slot, pool)
  local ctx = app.ctx
  local c = Theme.colors

  local filter_label = "(any)"
  if slot.keyword and slot.keyword ~= "" then
    filter_label = '"' .. slot.keyword .. '"'
  elseif slot.category then
    local cat = Categories.by_id(slot.category)
    filter_label = cat and cat.label or slot.category
  end

  local spec = Categories.spec_for_slot(slot)
  local count, total
  if spec and pool and pool.files and #pool.files > 0 then
    count = match_count_cached(app, pool, spec)
    total = #pool.files
  end

  local zero_matches = count == 0
  if zero_matches then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), c.danger) end
  r.ImGui_SetNextItemWidth(ctx, -1)
  if r.ImGui_BeginCombo(ctx, "##slot_filter", filter_label) then
    if r.ImGui_Selectable(ctx, "(any)##filter_any", spec == nil) then
      slot.category, slot.keyword, slot.type_label = nil, nil, nil
    end
    for _, cat in ipairs(Categories.list) do
      local selected = slot.category == cat.id and not (slot.keyword and slot.keyword ~= "")
      if r.ImGui_Selectable(ctx, cat.label .. "##filter_" .. cat.id, selected) then
        slot.category, slot.keyword, slot.type_label = cat.id, nil, cat.label
      end
    end
    r.ImGui_Separator(ctx)
    r.ImGui_AlignTextToFramePadding(ctx)
    Theme.label(ctx, "Custom:")
    r.ImGui_SameLine(ctx)
    r.ImGui_SetNextItemWidth(ctx, 110)
    local kw_changed, kw_value = r.ImGui_InputText(ctx, "##filter_custom", slot.keyword or "")
    if kw_changed then
      if kw_value ~= "" then
        slot.keyword, slot.category, slot.type_label = kw_value, nil, kw_value
      else
        slot.keyword = nil
        slot.type_label = slot.category and (Categories.by_id(slot.category) or {}).label or nil
      end
    end
    r.ImGui_EndCombo(ctx)
  end
  if zero_matches then r.ImGui_PopStyleColor(ctx) end

  if count and r.ImGui_IsItemHovered(ctx) then
    r.ImGui_SetTooltip(ctx, string.format("%d of %d samples match", count, total))
  end
end

-- Per-slot character override. Empty by default: the kit-wide setting under
-- Export applies unless a slot says otherwise ("whole kit dark, but this hat
-- short and sharp").
local function draw_slot_character(app, slot)
  local ctx = app.ctx
  local active = Tags.bias_active(slot.tag_bias)

  if active then
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), Theme.colors.accent)
  end
  if r.ImGui_SmallButton(ctx, (active and "On" or "\226\128\148") .. "##slot_char") then
    slot.tag_bias = slot.tag_bias or Tags.new_bias_config()
    r.ImGui_OpenPopup(ctx, "##slot_char_popup")
  end
  if active then r.ImGui_PopStyleColor(ctx) end
  if r.ImGui_IsItemHovered(ctx) then
    r.ImGui_SetTooltip(ctx, active
      and ("Character for this slot: " .. Tags.bias_summary(slot.tag_bias) .. "\nOverrides the kit-wide setting.")
      or "Character for this slot only.\nLeave off to follow the kit-wide setting under Export.")
  end

  if r.ImGui_BeginPopup(ctx, "##slot_char_popup") then
    slot.tag_bias = slot.tag_bias or Tags.new_bias_config()
    Theme.section(ctx, string.format("Slot %d character", slot.number or 0))
    Theme.help(ctx, "Overrides the kit-wide character for this slot only.")
    r.ImGui_Dummy(ctx, 340, 2)
    Character.draw(ctx, slot.tag_bias, "slot")
    r.ImGui_Separator(ctx)
    if Theme.ghost_button(ctx, "Clear##slot_char_clear") then
      slot.tag_bias = nil
      r.ImGui_CloseCurrentPopup(ctx)
    end
    r.ImGui_EndPopup(ctx)
  end
end

local function draw_slots(app)
  local ctx = app.ctx
  local c = Theme.colors
  local kitdef = app.kitdef

  Theme.step(ctx, "2", string.format("Slots  (%d)", #kitdef.slots))
  r.ImGui_Indent(ctx, 6)

  if r.ImGui_Button(ctx, "+ Slot##add_slot") then add_slot(app, nil) end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "+ 16 slots##add_16_slots") then
    for _ = 1, 16 do add_slot(app, nil) end
  end

  r.ImGui_SameLine(ctx)
  if Theme.primary_button(ctx, "From pattern\226\128\166##sp_open", 120, 0) then
    r.ImGui_OpenPopup(ctx, "##slot_pattern_popup")
  end
  if r.ImGui_IsItemHovered(ctx) then
    r.ImGui_SetTooltip(ctx, "Type Kick, Snare, Hihat, Clap and get slots with the\nfilter and the matching pool already set.")
  end
  draw_pattern_slots_popup(app)

  r.ImGui_SameLine(ctx)
  if Theme.ghost_button(ctx, "Renumber notes##renote") then
    for i, slot in ipairs(kitdef.slots) do slot.midi_note = math.min(127, 35 + i) end
  end
  if r.ImGui_IsItemHovered(ctx) then
    r.ImGui_SetTooltip(ctx, string.format(
      "Numbers the notes upward from %s (36), one per slot.", Naming.note_name(36)))
  end

  -- Quick layout builds slots, so it belongs here rather than as a step of its
  -- own after them -- it REPLACES the table, which read like a refinement when
  -- it sat further down the page.
  r.ImGui_SameLine(ctx)
  if Theme.ghost_button(ctx, "Quick layout\226\128\166##qp_open", 108, 0) then
    r.ImGui_OpenPopup(ctx, "##qp_popup")
  end
  if r.ImGui_IsItemHovered(ctx) then
    r.ImGui_SetTooltip(ctx, "Fill a whole keyboard from three pools in one go.\nReplaces the slots you have.")
  end
  draw_quick_layout_popup(app)

  if #kitdef.slots == 0 then
    r.ImGui_TextColored(ctx, c.text_faint, "No slots yet. Add some and link each to a pool.")
    r.ImGui_Unindent(ctx, 6)
    return
  end

  local avail_w = select(1, r.ImGui_GetContentRegionAvail(ctx))
  local narrow = (tonumber(avail_w) or 999) < 640

  local flags = r.ImGui_TableFlags_Borders()
  if narrow then
    flags = flags | r.ImGui_TableFlags_SizingFixedFit() | r.ImGui_TableFlags_ScrollX()
  else
    flags = flags | r.ImGui_TableFlags_SizingStretchProp()
  end
  if r.ImGui_BeginTable(ctx, "##slots_table", 8, flags, 0, 0) then
    if narrow then
      r.ImGui_TableSetupColumn(ctx, "#", r.ImGui_TableColumnFlags_WidthFixed(), 42)
      r.ImGui_TableSetupColumn(ctx, "Pool", r.ImGui_TableColumnFlags_WidthFixed(), 110)
      r.ImGui_TableSetupColumn(ctx, "Note", r.ImGui_TableColumnFlags_WidthFixed(), 42)
      r.ImGui_TableSetupColumn(ctx, "Pad", r.ImGui_TableColumnFlags_WidthFixed(), 42)
      r.ImGui_TableSetupColumn(ctx, "Filter", r.ImGui_TableColumnFlags_WidthFixed(), 120)
      r.ImGui_TableSetupColumn(ctx, "Char", r.ImGui_TableColumnFlags_WidthFixed(), 46)
      r.ImGui_TableSetupColumn(ctx, "Lock", r.ImGui_TableColumnFlags_WidthFixed(), 56)
      r.ImGui_TableSetupColumn(ctx, "", r.ImGui_TableColumnFlags_WidthFixed(), 42)
    else
      r.ImGui_TableSetupColumn(ctx, "#", r.ImGui_TableColumnFlags_WidthFixed(), 42)
      r.ImGui_TableSetupColumn(ctx, "Pool", r.ImGui_TableColumnFlags_WidthStretch())
      r.ImGui_TableSetupColumn(ctx, "Note", r.ImGui_TableColumnFlags_WidthFixed(), 42)
      r.ImGui_TableSetupColumn(ctx, "Pad", r.ImGui_TableColumnFlags_WidthFixed(), 42)
      r.ImGui_TableSetupColumn(ctx, "Filter", r.ImGui_TableColumnFlags_WidthFixed(), 110)
      r.ImGui_TableSetupColumn(ctx, "Char", r.ImGui_TableColumnFlags_WidthFixed(), 46)
      r.ImGui_TableSetupColumn(ctx, "Lock", r.ImGui_TableColumnFlags_WidthStretch())
      r.ImGui_TableSetupColumn(ctx, "", r.ImGui_TableColumnFlags_WidthFixed(), 64)
    end
    r.ImGui_TableHeadersRow(ctx)

    local pending_delete = nil
    for i, slot in ipairs(kitdef.slots) do
      r.ImGui_PushID(ctx, i)
      r.ImGui_TableNextRow(ctx)

      r.ImGui_TableNextColumn(ctx)
      r.ImGui_SetNextItemWidth(ctx, -1)
      local n_changed, n_value = r.ImGui_InputInt(ctx, "##slot_number", slot.number, 0)
      if n_changed then slot.number = n_value end

      r.ImGui_TableNextColumn(ctx)
      r.ImGui_SetNextItemWidth(ctx, -1)
      local pool = app.pools[slot.pool_id]
      local pool_label = pool and pool.alias or "(no pool)"
      if not pool then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), c.warning) end
      if r.ImGui_BeginCombo(ctx, "##slot_pool", pool_label) then
        for _, pool_id in ipairs(app.builder.pool_order) do
          local p = app.pools[pool_id]
          if p then
            local selected = slot.pool_id == pool_id
            if r.ImGui_Selectable(ctx, p.alias .. "##pool_opt_" .. pool_id, selected) then
              slot.pool_id = pool_id
            end
          end
        end
        r.ImGui_EndCombo(ctx)
      end
      if not pool then r.ImGui_PopStyleColor(ctx) end

      r.ImGui_TableNextColumn(ctx)
      r.ImGui_SetNextItemWidth(ctx, -1)
      local note_changed, note_value = r.ImGui_InputInt(ctx, "##slot_note", slot.midi_note, 0)
      if note_changed then slot.midi_note = math.max(0, math.min(127, note_value)) end

      r.ImGui_TableNextColumn(ctx)
      r.ImGui_SetNextItemWidth(ctx, -1)
      local pad_changed, pad_value = r.ImGui_InputInt(ctx, "##slot_pad", slot.pad or slot.number, 0)
      if pad_changed then slot.pad = pad_value end

      r.ImGui_TableNextColumn(ctx)
      draw_filter_cell(app, slot, pool)

      r.ImGui_TableNextColumn(ctx)
      draw_slot_character(app, slot)

      r.ImGui_TableNextColumn(ctx)
      if slot.lock_file then
        local shown = slot.lock_file:match("([^/\\]+)$") or slot.lock_file
        if #shown > 20 then shown = "..." .. shown:sub(-17) end
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), c.accent)
        r.ImGui_AlignTextToFramePadding(ctx)
        r.ImGui_Text(ctx, shown)
        r.ImGui_PopStyleColor(ctx)
        if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, slot.lock_file) end
        r.ImGui_SameLine(ctx)
        if r.ImGui_SmallButton(ctx, "Unlock##unlock") then slot.lock_file = nil end
      else
        if r.ImGui_SmallButton(ctx, "Lock##lock") then
          local file = Dialogs.browse_file("Select fixed sample", "", nil, "source")
          if file then slot.lock_file = file end
        end
      end

      r.ImGui_TableNextColumn(ctx)
      r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), c.danger)
      if r.ImGui_SmallButton(ctx, "Del##delete_slot") then pending_delete = i end
      r.ImGui_PopStyleColor(ctx)

      r.ImGui_PopID(ctx)
    end
    r.ImGui_EndTable(ctx)

    if pending_delete then table.remove(kitdef.slots, pending_delete) end
  end
  r.ImGui_Unindent(ctx, 6)
end

local function pool_picker(app, label, key)
  local ctx = app.ctx
  local current = app.builder[key]
  local pool = current and app.pools[current]
  local caption = label:gsub("##.*$", "")
  local suffix = label:match("##(.+)$") or caption
  r.ImGui_AlignTextToFramePadding(ctx)
  Theme.label(ctx, caption)
  r.ImGui_SetNextItemWidth(ctx, fit_w(ctx, 260, 20))
  if r.ImGui_BeginCombo(ctx, "##" .. suffix, pool and pool.alias or "(pick pool)") then
    for _, pool_id in ipairs(app.builder.pool_order) do
      local p = app.pools[pool_id]
      if p then
        local selected = current == pool_id
        if r.ImGui_Selectable(ctx, p.alias .. "##" .. suffix .. "_" .. pool_id, selected) then
          app.builder[key] = pool_id
        end
      end
    end
    r.ImGui_EndCombo(ctx)
  end
end

-- Slots from a pattern -------------------------------------------------------
--
-- The Builder's real cost is the setup: a pool, its folders, sixteen slots, a
-- pool on each, a filter on each. Explosion already solves that with a comma
-- separated pattern, and the same parser works here -- with one addition that
-- matters more than it sounds: the pattern word is matched against the pool
-- ALIASES, so pools called Kick / Snare / Hihat get wired up on their own.

-- Exact alias match first, then a loose one so "Kicks" still answers to "Kick".
local function pool_for_word(app, word)
  word = (word or ""):lower()
  if word == "" then return nil end

  for _, id in ipairs(app.builder.pool_order) do
    local pool = app.pools[id]
    if pool and (pool.alias or ""):lower() == word then return id end
  end
  for _, id in ipairs(app.builder.pool_order) do
    local alias = (app.pools[id] and app.pools[id].alias or ""):lower()
    if alias ~= "" and (alias:find(word, 1, true) or word:find(alias, 1, true)) then
      return id
    end
  end
  return nil
end

local function spec_word(spec, label)
  if spec.keyword and spec.keyword ~= "" then return spec.keyword end
  return (label or ""):gsub('"', "")
end

draw_pattern_slots_popup = function(app)
  local ctx = app.ctx
  local c = Theme.colors
  local b = app.builder
  if not r.ImGui_BeginPopup(ctx, "##slot_pattern_popup") then return end

  Theme.section(ctx, "Slots from a pattern")
  Theme.help(ctx, "Comma-separated categories or keywords, repeated to fill the slots. Each slot gets that filter, and the pool whose alias matches the word.")
  r.ImGui_Dummy(ctx, 420, 2)

  b.slot_pattern = b.slot_pattern or ""
  b.slot_pattern_count = b.slot_pattern_count or 16

  r.ImGui_SetNextItemWidth(ctx, fit_w(ctx, 300, 40))
  local p_changed, p_value = r.ImGui_InputTextWithHint(ctx, "##slot_pattern",
    "e.g. Kick, Snare, Hihat, Clap", b.slot_pattern)
  if p_changed then b.slot_pattern = p_value end
  r.ImGui_SameLine(ctx)
  if Theme.ghost_button(ctx, "+##slot_pattern_add", 26) then
    r.ImGui_OpenPopup(ctx, "##slot_pattern_cats")
  end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Append a category") end
  if r.ImGui_BeginPopup(ctx, "##slot_pattern_cats") then
    for _, cat in ipairs(Categories.list) do
      if r.ImGui_Selectable(ctx, cat.label .. "##sp_add_" .. cat.id) then
        b.slot_pattern = b.slot_pattern == "" and cat.label or (b.slot_pattern .. ", " .. cat.label)
      end
    end
    r.ImGui_EndPopup(ctx)
  end

  -- The same list Explosion offers, and the same store: a pattern saved on
  -- either page shows up on the other.
  r.ImGui_SameLine(ctx)
  local from_preset = PatternPresets.button(ctx, "slots", b.slot_pattern, b)
  if from_preset then b.slot_pattern = from_preset end

  r.ImGui_SetNextItemWidth(ctx, 180)
  local n_changed, n_value = r.ImGui_SliderInt(ctx, "Slots##slot_pattern_count", b.slot_pattern_count, 1, 128, "%d")
  if n_changed then b.slot_pattern_count = n_value end

  pool_picker(app, "Pool when nothing matches##slot_pattern_pool", "slot_pattern_pool")

  -- Which pool each word resolved to, before anything is created.
  local specs, labels = Categories.parse_pattern(b.slot_pattern)
  local unmatched = 0
  if #labels > 0 then
    r.ImGui_Dummy(ctx, 0, 2)
    local pushed = Theme.push_small(ctx)
    for i = 1, #labels do
      local id = pool_for_word(app, spec_word(specs[i], labels[i])) or b.slot_pattern_pool
      local pool = id and app.pools[id]
      if not pool then unmatched = unmatched + 1 end
      r.ImGui_TextColored(ctx, pool and c.success or c.warning, string.format(
        "%s  \226\134\146  %s", labels[i], pool and (pool.alias or "pool") or "no pool"))
    end
    Theme.pop_font(ctx, pushed)
  end

  local existing = #(app.kitdef.slots or {})
  if existing > 0 then
    r.ImGui_TextColored(ctx, c.warning,
      string.format("Replaces the %d slot%s you have now.", existing, existing == 1 and "" or "s"))
  end

  r.ImGui_BeginDisabled(ctx, #specs == 0)
  if Theme.primary_button(ctx, "Create slots##slot_pattern_go", 150, 0) then
    Undo.push(app.builder.undo, app, "slots from pattern")
    local slots = {}
    for i = 1, b.slot_pattern_count do
      local idx = ((i - 1) % #specs) + 1
      local spec = specs[idx]
      local slot = {
        number = i,
        pool_id = pool_for_word(app, spec_word(spec, labels[idx])) or b.slot_pattern_pool,
        midi_note = math.min(127, 35 + i),
        pad = i,
        lock_file = nil,
      }
      if spec.category then slot.category = spec.category else slot.keyword = spec.keyword end
      -- Same field the filter cell sets by hand: core/naming.lua puts it in the
      -- exported filename, so generated slots name their files like the rest.
      slot.type_label = Categories.spec_label(spec)
      slots[i] = slot
    end
    app.kitdef.slots = slots
    r.ImGui_CloseCurrentPopup(ctx)
  end
  r.ImGui_EndDisabled(ctx)
  if unmatched > 0 and r.ImGui_IsItemHovered(ctx) then
    r.ImGui_SetTooltip(ctx, "Slots with no pool are created anyway; link them in the table.")
  end

  r.ImGui_EndPopup(ctx)
end

draw_quick_layout_popup = function(app)
  local ctx = app.ctx
  local c = Theme.colors
  if not r.ImGui_BeginPopup(ctx, "##qp_popup") then return end

  Theme.section(ctx, "Quick layout (128 slots)")
  Theme.help(ctx, "White keys alternate between pool A/B, all black keys go to one pool (e.g. Kick/Snare/Hi-hat).")
  r.ImGui_Dummy(ctx, 320, 2)

  pool_picker(app, "White keys A (e.g. Kick)##qp_a", "quick_white_a")
  pool_picker(app, "White keys B (e.g. Snare)##qp_b", "quick_white_b")
  pool_picker(app, "Black keys (e.g. Hi-hat)##qp_black", "quick_black")

  local existing = #(app.kitdef.slots or {})
  if existing > 0 then
    r.ImGui_TextColored(ctx, c.warning,
      string.format("Replaces the %d slot%s you have now.", existing, existing == 1 and "" or "s"))
  end

  local can_generate = app.builder.quick_white_a and app.builder.quick_white_b and app.builder.quick_black
  r.ImGui_BeginDisabled(ctx, not can_generate)
  if Theme.primary_button(ctx, "Generate 128 slots##qp_generate", 180, 0) then
    Undo.push(app.builder.undo, app, "quick layout")
    local layout = Engine.quick_preview_kitdef(
      app.builder.quick_white_a, app.builder.quick_white_b, app.builder.quick_black,
      { destination = app.kitdef.export.destination, naming = app.kitdef.naming, export = app.kitdef.export }
    )
    app.kitdef.slots = layout.slots
    r.ImGui_CloseCurrentPopup(ctx)
  end
  r.ImGui_EndDisabled(ctx)
  r.ImGui_EndPopup(ctx)
end

-- Saving and loading is a file operation, not a step in building a kit, so it
-- sits in a bar above the steps rather than interrupting them halfway down.
local function draw_presets_body(app)
  local ctx = app.ctx
  local c = Theme.colors

  r.ImGui_SetNextItemWidth(ctx, fit_w(ctx, 240, 90))
  local name_changed, name_value = r.ImGui_InputText(ctx, "##preset_name", app.builder.preset_name)
  if name_changed then app.builder.preset_name = name_value end
  r.ImGui_SameLine(ctx)
  local can_save = app.builder.preset_name ~= ""
  r.ImGui_BeginDisabled(ctx, not can_save)
  if r.ImGui_Button(ctx, "Save##preset_save") then
    local ok, err = Presets.save(app.builder.preset_name, app.kitdef, app.pools)
    app.builder.preset_status = ok and "Saved." or ("Error: " .. tostring(err))
    app.builder.presets_list = Presets.list()
  end
  r.ImGui_EndDisabled(ctx)
  if app.builder.preset_status then
    r.ImGui_SameLine(ctx)
    r.ImGui_AlignTextToFramePadding(ctx)
    r.ImGui_TextColored(ctx, c.text_dim, app.builder.preset_status)
  end

  if #app.builder.presets_list == 0 then
    r.ImGui_TextColored(ctx, c.text_faint, "(no presets saved yet)")
  end
  for _, name in ipairs(app.builder.presets_list) do
    r.ImGui_PushID(ctx, "preset_" .. name)
    r.ImGui_AlignTextToFramePadding(ctx)
    r.ImGui_Bullet(ctx)
    r.ImGui_SameLine(ctx)
    r.ImGui_Text(ctx, name)
    r.ImGui_SameLine(ctx)
    if r.ImGui_SmallButton(ctx, "Load##load") then load_preset(app, name) end
    r.ImGui_SameLine(ctx)
    if r.ImGui_SmallButton(ctx, "Update##update") then
      local ok, err = Presets.save(name, app.kitdef, app.pools)
      app.builder.preset_status = ok and ("Updated '" .. name .. "'.") or ("Error: " .. tostring(err))
      app.builder.presets_list = Presets.list()
    end
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Overwrite this preset with the current pools and slots.") end
    r.ImGui_SameLine(ctx)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), c.danger)
    if r.ImGui_SmallButton(ctx, "Delete##delpreset") then
      -- Read before removing, so undo has something to write back. A preset is
      -- a file, and the snapshot the other actions take -- pools and slots in
      -- memory -- cannot bring a file back.
      local raw = Presets.read_raw(name)
      local was_loaded = app.builder.loaded_preset == name
      Presets.delete(name)
      if was_loaded then app.builder.loaded_preset = nil end
      app.builder.presets_list = Presets.list()
      if raw then
        Undo.push_action(app.builder.undo, "delete preset", function()
          Presets.write_raw(name, raw)
          if was_loaded then app.builder.loaded_preset = name end
          app.builder.presets_list = Presets.list()
        end)
      end
    end
    r.ImGui_PopStyleColor(ctx)
    r.ImGui_PopID(ctx)
  end
end

local function draw_preset_bar(app)
  local ctx = app.ctx
  local c = Theme.colors

  if Theme.ghost_button(ctx, "Presets\226\128\166##builder_presets", 88, 0) then
    r.ImGui_OpenPopup(ctx, "##builder_presets_popup")
  end
  if r.ImGui_IsItemHovered(ctx) then
    r.ImGui_SetTooltip(ctx, "Save, load, update and delete pool + slot presets.")
  end

  r.ImGui_SameLine(ctx)
  r.ImGui_AlignTextToFramePadding(ctx)
  local pushed = Theme.push_small(ctx)
  r.ImGui_TextColored(ctx, c.text_dim, app.builder.loaded_preset
    and ("Preset: " .. app.builder.loaded_preset)
    or "Unsaved kit")
  Theme.pop_font(ctx, pushed)

  if r.ImGui_BeginPopup(ctx, "##builder_presets_popup") then
    Theme.section(ctx, "Presets")
    r.ImGui_Dummy(ctx, 360, 2)
    draw_presets_body(app)
    r.ImGui_EndPopup(ctx)
  end

  r.ImGui_Dummy(ctx, 0, 4)
  r.ImGui_Separator(ctx)
  r.ImGui_Dummy(ctx, 0, 4)
end

local function draw_empty_state(app)
  local ctx = app.ctx
  local c = Theme.colors
  Theme.section(ctx, "Kit Builder")
  Theme.help(ctx, "Define the composition yourself: create pools per instrument and link slots to pools. On export each slot gets a random sample from its pool.")
  r.ImGui_Dummy(ctx, 0, 6)
  if Theme.primary_button(ctx, "Fresh start##builder_fresh", 180, 36) then
    app.kitdef = M.new_kitdef()
    app.pools = {}
    app.builder.pool_order = {}
  end

  r.ImGui_Dummy(ctx, 0, 8)
  r.ImGui_Separator(ctx)
  r.ImGui_Dummy(ctx, 0, 2)
  Theme.label(ctx, "Or load an existing preset:")
  if #app.builder.presets_list == 0 then
    r.ImGui_TextColored(ctx, c.text_faint, "(no presets saved yet)")
  end
  for _, name in ipairs(app.builder.presets_list) do
    r.ImGui_PushID(ctx, "empty_" .. name)
    r.ImGui_AlignTextToFramePadding(ctx)
    r.ImGui_Bullet(ctx)
    r.ImGui_SameLine(ctx)
    r.ImGui_Text(ctx, name)
    r.ImGui_SameLine(ctx)
    if r.ImGui_SmallButton(ctx, "Load##empty_load") then load_preset(app, name) end
    r.ImGui_PopID(ctx)
  end
end

function M.draw(app)
  if not app.kitdef then
    draw_empty_state(app)
    return
  end

  local ctx = app.ctx

  -- Ctrl+Z, with the same guard the sample list uses: while a field or a slider
  -- is active the keys belong to it. Taking Ctrl+Z off a text box would be a
  -- worse bug than the one this feature exists to soften.
  if r.ImGui_IsKeyPressed and r.ImGui_Key_Z and r.ImGui_Mod_Ctrl then
    local typing = r.ImGui_IsAnyItemActive and r.ImGui_IsAnyItemActive(ctx)
    local ctrl = r.ImGui_GetKeyMods and ((r.ImGui_GetKeyMods(ctx) & r.ImGui_Mod_Ctrl()) ~= 0)
    if ctrl and not typing and r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_Z(), false) then
      Undo.pop(app.builder.undo, app)
    end
  end

  draw_preset_bar(app)
  draw_pools(app)

  r.ImGui_Dummy(ctx, 0, 4)
  r.ImGui_Separator(ctx)
  r.ImGui_Dummy(ctx, 0, 4)

  draw_slots(app)

  r.ImGui_Dummy(ctx, 0, 4)
  r.ImGui_Separator(ctx)
  -- Step 3 (Export) is drawn by ui/export_dialog.lua, right after this.
end

return M
