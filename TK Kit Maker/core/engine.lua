-- The shared motor (architecture doc, section 4): one GenerateKit function for
-- both the Folder Explosion (milestone 1) and the full Kit Builder (milestone 2+).
-- Sample lock, use-up/reshuffle and the used-samples-log are not bolted on
-- later -- the hooks are here from the start, per the doc's design intent.

local Scanner  = require("core.scanner")
local Picker   = require("core.picker")
local Naming   = require("core.naming")
local Exporter = require("core.exporter")
local Wordlist = require("core.wordlist")
local UsedLog  = require("core.used_log")
local Stitcher = require("core.stitcher")
local Duration = require("core.duration")
local Categories = require("core.categories")

local M = {}

local function add_tokens(set, text)
  for token in tostring(text or ""):gmatch("[A-Za-z]+") do
    local t = token:lower()
    if #t > 1 then set[t] = true end
  end
end

local function sorted_tokens(set)
  local out = {}
  for t in pairs(set) do out[#out + 1] = t end
  table.sort(out)
  return out
end

function M.name_context_tokens(kitdef, pools)
  local set = {}
  for _, pool in pairs(pools or {}) do
    add_tokens(set, pool.alias)
    for _, folder in ipairs(pool.folders or {}) do
      local leaf = tostring(folder or ""):match("([^/\\]+)$")
      add_tokens(set, leaf)
    end
  end
  for _, slot in ipairs((kitdef and kitdef.slots) or {}) do
    add_tokens(set, slot.type_label)
    add_tokens(set, slot.keyword)
  end
  return sorted_tokens(set)
end

function M.suggest_kit_name(kitdef, pools, script_path, seed_word)
  local context = M.name_context_tokens(kitdef, pools)
  return Wordlist.suggest_name(script_path, {
    seed_word = seed_word,
    context_words = context,
  })
end

-- Scans every pool that doesn't have a cache yet (or all of them if force).
function M.rescan_pools(pools, force)
  for _, pool in pairs(pools) do
    if force or not pool.files or #pool.files == 0 then
      Scanner.scan_pool(pool)
    end
  end
end

-- Returns a pick view on the pool: the pool itself when no filter is active,
-- otherwise a cached filtered copy (keyed per keyword/category + length
-- limit, since different slots can use different filters on the same pool).
-- Each view carries its own use_up bag so no-repeat picking works within it.
local function effective_pool(pool, max_seconds, spec)
  local has_limit = max_seconds and max_seconds > 0
  if not has_limit and not spec then return pool end

  local key = tostring(has_limit and max_seconds or 0) .. "|"
    .. (spec and (spec.keyword and ("k:" .. spec.keyword:lower()) or ("c:" .. spec.category)) or "")

  pool._views = pool._views or {}
  local view = pool._views[key]
  if not view or view.source_n ~= #pool.files then
    local files = {}
    for _, f in ipairs(pool.files) do
      local keep = not spec or Categories.matches(f, spec)
      if keep and has_limit then
        local d = Duration.seconds(f)
        keep = not d or d <= max_seconds
      end
      if keep then files[#files + 1] = f end
    end
    view = { source_n = #pool.files, files = files, _bag = {} }
    pool._views[key] = view
  end
  view.mode = pool.mode
  return view
end

local function pick_sample(pool, slot, used_log_enabled, max_seconds)
  if slot.lock_file then return slot.lock_file end
  if not pool or not pool.files or #pool.files == 0 then
    return nil, "no sample available in pool"
  end

  local spec = Categories.spec_for_slot(slot)
  local view = effective_pool(pool, max_seconds, spec)
  if #view.files == 0 then
    if spec then
      local suffix = (max_seconds and max_seconds > 0) and " within max length" or ""
      return nil, string.format("no samples matching '%s'%s", Categories.spec_label(spec), suffix)
    end
    return nil, string.format("all samples exceed max length (%.1fs)", max_seconds)
  end

  if used_log_enabled then
    local unused = {}
    for _, f in ipairs(view.files) do
      if not UsedLog.is_used(f) then unused[#unused + 1] = f end
    end
    if #unused == 0 then
      -- Every pickable sample has been used before; reset their history.
      for _, f in ipairs(view.files) do UsedLog.clear_used(f) end
      unused = view.files
    end
    local pick = unused[math.random(#unused)]
    UsedLog.mark_used(pick)
    return pick
  end

  return Picker.pick(view)
end

-- Generates ONE kit from a KitDef. Batch = call this N times (see new_batch()).
-- pools: table keyed by pool_id -> Pool. script_path: needed for the wordlist
-- fallback file when kitdef.name_prefix is nil.
function M.generate_kit(kitdef, pools, kit_index, script_path)
  local kit_name = (kitdef.name_prefix and kitdef.name_prefix ~= "")
    and string.format("%s %03d", kitdef.name_prefix, kit_index)
    or  M.suggest_kit_name(kitdef, pools, script_path, kitdef.name_seed)

  local dest_dir, final_name = Exporter.make_folder(kitdef.export.destination, kit_name)

  local results = {}
  local errors = {}

  for _, slot in ipairs(kitdef.slots) do
    local pool = pools[slot.pool_id]
    local sample, pick_err = pick_sample(pool, slot, kitdef.export.write_usedlog, kitdef.export.max_sample_seconds)

    if sample then
      local filename = Naming.build(slot, sample, pool, kitdef.naming)
      local out_name, err = Exporter.copy(sample, dest_dir, filename)
      if out_name then
        results[#results + 1] = { slot = slot, pool = pool, sample = sample, out_name = out_name }
      else
        errors[#errors + 1] = string.format("Slot %d: %s", slot.number, err)
      end
    else
      errors[#errors + 1] = string.format("Slot %d: %s", slot.number, pick_err or "no sample available in pool")
    end
  end

  if kitdef.export.write_midilog   then Exporter.write_midilog(dest_dir, final_name, results)   end
  if kitdef.export.write_sourcelog then Exporter.write_sourcelog(dest_dir, final_name, results) end
  if kitdef.export.write_usedlog   then UsedLog.flush() end

  local stitched
  if kitdef.export.write_stitched and #results > 0 then
    -- The pick filter already keeps long samples out; passing the limit to the
    -- stitcher as well covers locked samples, which bypass the pick filter.
    local ok, path_or_err, stitch_err, stitch_warnings = pcall(Stitcher.stitch_kit, dest_dir, final_name, results, kitdef.export.max_sample_seconds)
    if ok and path_or_err then
      stitched = path_or_err
      for _, warning in ipairs(stitch_warnings or {}) do
        errors[#errors + 1] = "Stitch: " .. warning
      end
    elseif ok then
      errors[#errors + 1] = "Stitch: " .. tostring(stitch_err)
    else
      errors[#errors + 1] = "Stitch failed: " .. tostring(path_or_err)
    end
  end

  return { name = final_name, dest = dest_dir, results = results, errors = errors, stitched = stitched }
end

-- Stateful batch runner: call runner:step() once (or a few times) per UI
-- frame so a 100+ kit batch does not freeze the ReaImGui loop.
function M.new_batch(kitdef, pools, script_path)
  return {
    kitdef = kitdef,
    pools = pools,
    script_path = script_path,
    index = 0,
    total = math.max(1, kitdef.export.kit_count or 1),
    kits = {},
    errors = {},
    done = false,

    step = function(self)
      if self.done then return false end
      self.index = self.index + 1
      local ok, kit_or_err = pcall(M.generate_kit, self.kitdef, self.pools, self.index, self.script_path)
      if ok then
        self.kits[#self.kits + 1] = kit_or_err
      else
        self.errors[#self.errors + 1] = string.format("Kit %d: %s", self.index, tostring(kit_or_err))
      end
      if self.index >= self.total then self.done = true end
      return not self.done
    end,
  }
end

-- Milestone 1 helper: builds a full KitDef from the minimal "5-click" inputs
-- -- one pool, auto-generated consecutive slots from a start note.
function M.kitdef_from_explosion(opts)
  local pool = {
    id = "pool_explosion",
    alias = opts.alias or "Sample",
    folders = { opts.source_folder },
    recursive = opts.recursive ~= false,
    files = {},
    mode = "repeat",
    _bag = {},
  }

  -- opts.pattern: ordered spec list from Categories.parse_pattern; it repeats
  -- cyclically over the slots ("Kick, Snare, Hihat, Clap" x4 fills 16 slots).
  local pattern = opts.pattern
  if pattern and #pattern == 0 then pattern = nil end

  local slots = {}
  for i = 1, opts.count do
    local slot = {
      number = i,
      pool_id = pool.id,
      midi_note = opts.start_note + (i - 1),
      pad = i,
      lock_file = nil,
    }
    if pattern then
      local spec = pattern[((i - 1) % #pattern) + 1]
      slot.category = spec.category
      slot.keyword = spec.keyword
      slot.type_label = Categories.spec_label(spec)
    end
    slots[i] = slot
  end

  local kitdef = {
    name_prefix = opts.name_prefix,
    name_seed = opts.name_seed,
    slots = slots,
    naming = opts.naming or {
      prefix_style = "001",
      include_type = true,
      note_style = "name",
      separator = "_",
    },
    export = opts.export or {
      destination = opts.destination,
      kit_count = 1,
      write_midilog = false,
      write_sourcelog = false,
      write_usedlog = false,
      write_stitched = opts.stitched == true,
      max_sample_seconds = opts.max_sample_seconds or 0,
    },
  }

  return kitdef, { [pool.id] = pool }
end

local WHITE_KEY_PITCH_CLASSES = { [0]=true,[2]=true,[4]=true,[5]=true,[7]=true,[9]=true,[11]=true }

-- Milestone 3 helper: "Quick Preview" layout -- 128 slots spread over pools,
-- alternating white keys between two pools (e.g. Kick/Snare) and routing every
-- black key to a third pool (e.g. Hi-hat). Same GenerateKit motor underneath.
function M.quick_preview_kitdef(white_pool_a_id, white_pool_b_id, black_pool_id, opts)
  opts = opts or {}
  local slots = {}
  local white_toggle = true

  for note = 0, 127 do
    local pool_id
    if WHITE_KEY_PITCH_CLASSES[note % 12] then
      pool_id = white_toggle and white_pool_a_id or white_pool_b_id
      white_toggle = not white_toggle
    else
      pool_id = black_pool_id
    end

    slots[#slots + 1] = {
      number = note + 1,
      pool_id = pool_id,
      midi_note = note,
      pad = note + 1,
      lock_file = nil,
    }
  end

  return {
    name_prefix = opts.name_prefix,
    slots = slots,
    naming = opts.naming or {
      prefix_style = "001",
      include_type = true,
      note_style = "name",
      separator = "_",
    },
    export = opts.export or {
      destination = opts.destination,
      kit_count = 1,
      write_midilog = false,
      write_sourcelog = false,
      write_usedlog = false,
      write_stitched = false,
      max_sample_seconds = 0,
    },
  }
end

return M
