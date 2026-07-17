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

local M = {}

local function fit_w(ctx, want, reserve)
  local avail = select(1, r.ImGui_GetContentRegionAvail(ctx))
  return math.max(120, math.min(want, avail - (reserve or 0)))
end

local function new_naming()
  return { prefix_style = "001", include_type = true, note_style = "name", separator = "_" }
end

local function new_export()
  return { destination = "", kit_count = 1, write_midilog = false, write_sourcelog = false, write_usedlog = false, write_stitched = false, max_sample_seconds = 0 }
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
  table.sort(order)
  return order
end

local function load_preset(app, name)
  local kitdef, pools = Presets.load(name)
  if kitdef then
    app.kitdef = kitdef
    app.pools = pools
    app.builder.pool_order = pool_order_from(pools)
    app.builder.preset_name = name
    app.builder.loaded_preset = name
  end
end

local function add_pool(app)
  local id = "pool_" .. tostring(app.builder.next_pool_n)
  app.builder.next_pool_n = app.builder.next_pool_n + 1
  app.pools[id] = {
    id = id,
    alias = "Pool " .. id:gsub("pool_", ""),
    folders = {},
    recursive = true,
    files = {},
    mode = "repeat",
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

local function draw_pools(app)
  local ctx = app.ctx
  local c = Theme.colors

  if not r.ImGui_CollapsingHeader(ctx, "Pools###pools_section") then return end
  r.ImGui_Indent(ctx, 6)

  if Theme.primary_button(ctx, "+ Pool##builder_add_pool", 96, 0) then add_pool(app) end
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

        Theme.label(ctx, "Folders")
        local folder_pending_delete = nil
        if #pool.folders == 0 then
          r.ImGui_TextColored(ctx, c.text_faint, "(no folders yet)")
        end
        for fi, folder in ipairs(pool.folders) do
          r.ImGui_Bullet(ctx)
          r.ImGui_SameLine(ctx)
          r.ImGui_Text(ctx, folder)
          r.ImGui_SameLine(ctx)
          if r.ImGui_SmallButton(ctx, "X##folder_" .. fi) then folder_pending_delete = fi end
        end
        if folder_pending_delete then
          table.remove(pool.folders, folder_pending_delete)
          pool.files = {}
        end

        if r.ImGui_Button(ctx, "+ Add folder##add_folder") then
          local folder = Dialogs.browse_folder("Select folder for " .. (pool.alias or pool_id), "")
          if folder then pool.folders[#pool.folders + 1] = folder; pool.files = {} end
        end
        r.ImGui_SameLine(ctx)
        local rec_changed, rec_value = r.ImGui_Checkbox(ctx, "Subfolders##recursive", pool.recursive)
        if rec_changed then pool.recursive = rec_value; pool.files = {} end

        r.ImGui_SetNextItemWidth(ctx, fit_w(ctx, 240, 60))
        local mode_label = pool.mode == "use_up" and "Use up (no repeats)" or "Repeat (repeats allowed)"
        if r.ImGui_BeginCombo(ctx, "Mode##mode", mode_label) then
          if r.ImGui_Selectable(ctx, "Repeat (repeats allowed)##mode_repeat", pool.mode ~= "use_up") then pool.mode = "repeat" end
          if r.ImGui_Selectable(ctx, "Use up (no repeats + reshuffle)##mode_useup", pool.mode == "use_up") then pool.mode = "use_up" end
          r.ImGui_EndCombo(ctx)
        end

        if Theme.ghost_button(ctx, "Scan##pool_rescan") then Scanner.scan_pool(pool) end
        r.ImGui_SameLine(ctx)
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

local function draw_slots(app)
  local ctx = app.ctx
  local c = Theme.colors
  local kitdef = app.kitdef

  local header = string.format("Slots  (%d)###slots_section", #kitdef.slots)
  if not r.ImGui_CollapsingHeader(ctx, header) then return end
  r.ImGui_Indent(ctx, 6)

  if r.ImGui_Button(ctx, "+ Slot##add_slot") then add_slot(app, nil) end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "+ 16 slots##add_16_slots") then
    for _ = 1, 16 do add_slot(app, nil) end
  end
  r.ImGui_SameLine(ctx)
  if Theme.ghost_button(ctx, "Notes from 36##renote") then
    for i, slot in ipairs(kitdef.slots) do slot.midi_note = math.min(127, 35 + i) end
  end

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
  if r.ImGui_BeginTable(ctx, "##slots_table", 7, flags, 0, 0) then
    if narrow then
      r.ImGui_TableSetupColumn(ctx, "#", r.ImGui_TableColumnFlags_WidthFixed(), 42)
      r.ImGui_TableSetupColumn(ctx, "Pool", r.ImGui_TableColumnFlags_WidthFixed(), 110)
      r.ImGui_TableSetupColumn(ctx, "Note", r.ImGui_TableColumnFlags_WidthFixed(), 42)
      r.ImGui_TableSetupColumn(ctx, "Pad", r.ImGui_TableColumnFlags_WidthFixed(), 42)
      r.ImGui_TableSetupColumn(ctx, "Filter", r.ImGui_TableColumnFlags_WidthFixed(), 120)
      r.ImGui_TableSetupColumn(ctx, "Lock", r.ImGui_TableColumnFlags_WidthFixed(), 56)
      r.ImGui_TableSetupColumn(ctx, "", r.ImGui_TableColumnFlags_WidthFixed(), 42)
    else
      r.ImGui_TableSetupColumn(ctx, "#", r.ImGui_TableColumnFlags_WidthFixed(), 42)
      r.ImGui_TableSetupColumn(ctx, "Pool", r.ImGui_TableColumnFlags_WidthStretch())
      r.ImGui_TableSetupColumn(ctx, "Note", r.ImGui_TableColumnFlags_WidthFixed(), 42)
      r.ImGui_TableSetupColumn(ctx, "Pad", r.ImGui_TableColumnFlags_WidthFixed(), 42)
      r.ImGui_TableSetupColumn(ctx, "Filter", r.ImGui_TableColumnFlags_WidthFixed(), 110)
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
          local file = Dialogs.browse_file("Select fixed sample", "")
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

local function draw_quick_preview(app)
  local ctx = app.ctx
  if not r.ImGui_CollapsingHeader(ctx, "Quick layout (128 slots)##qp_section") then return end
  r.ImGui_Indent(ctx, 6)
  Theme.help(ctx, "White keys alternate between pool A/B, all black keys go to one pool (e.g. Kick/Snare/Hi-hat).")

  pool_picker(app, "White keys A (e.g. Kick)##qp_a", "quick_white_a")
  pool_picker(app, "White keys B (e.g. Snare)##qp_b", "quick_white_b")
  pool_picker(app, "Black keys (e.g. Hi-hat)##qp_black", "quick_black")

  local can_generate = app.builder.quick_white_a and app.builder.quick_white_b and app.builder.quick_black
  r.ImGui_BeginDisabled(ctx, not can_generate)
  if r.ImGui_Button(ctx, "Generate 128-slot layout##qp_generate") then
    local layout = Engine.quick_preview_kitdef(
      app.builder.quick_white_a, app.builder.quick_white_b, app.builder.quick_black,
      { destination = app.kitdef.export.destination, naming = app.kitdef.naming, export = app.kitdef.export }
    )
    app.kitdef.slots = layout.slots
  end
  r.ImGui_EndDisabled(ctx)
  r.ImGui_Unindent(ctx, 6)
end

local function draw_presets(app)
  local ctx = app.ctx
  local c = Theme.colors
  if not r.ImGui_CollapsingHeader(ctx, "Presets##presets_section") then return end
  r.ImGui_Indent(ctx, 6)

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
      Presets.delete(name)
      if app.builder.loaded_preset == name then app.builder.loaded_preset = nil end
      app.builder.presets_list = Presets.list()
    end
    r.ImGui_PopStyleColor(ctx)
    r.ImGui_PopID(ctx)
  end
  r.ImGui_Unindent(ctx, 6)
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
  draw_pools(app)
  r.ImGui_Dummy(ctx, 0, 2)
  draw_slots(app)
  r.ImGui_Dummy(ctx, 0, 2)
  draw_quick_preview(app)
  r.ImGui_Dummy(ctx, 0, 2)
  draw_presets(app)
end

return M
