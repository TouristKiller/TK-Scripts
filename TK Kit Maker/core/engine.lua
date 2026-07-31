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
local Bias     = require("core.bias")
local Tags     = require("core.tags")
local Rng      = require("core.rng")

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
local function effective_pool(pool, max_seconds, spec, sort_by_length)
  local has_limit = max_seconds and max_seconds > 0
  if not has_limit and not spec and not sort_by_length then return pool end

  local key = tostring(has_limit and max_seconds or 0) .. "|"
    .. (spec and (spec.keyword and ("k:" .. spec.keyword:lower()) or ("c:" .. spec.category)) or "")
    .. (sort_by_length and "|len" or "")

  pool._views = pool._views or {}
  local view = pool._views[key]
  if not view or view.source_n ~= #pool.files then
    local kept = {}
    for i, f in ipairs(pool.files) do
      local keep = not spec or Categories.matches(f, spec)
      if keep and has_limit then
        local d = Duration.seconds(f)
        keep = not d or d <= max_seconds
      end
      if keep then
        kept[#kept + 1] = { path = f, folder = (pool.file_folder and pool.file_folder[i]) or 1 }
      end
    end
    if sort_by_length then
      local secs = {}
      for _, e in ipairs(kept) do secs[e.path] = Duration.seconds(e.path) or math.huge end
      table.sort(kept, function(a, b)
        if secs[a.path] == secs[b.path] then return a.path < b.path end
        return secs[a.path] < secs[b.path]
      end)
    end
    local files, folders = {}, {}
    for i, e in ipairs(kept) do
      files[i] = e.path
      folders[i] = e.folder
    end
    view = { source_n = #pool.files, files = files, file_folder = folders, _bag = {}, sorted = sort_by_length == true }
    pool._views[key] = view
  end
  view.mode = pool.mode
  return view
end

local function view_weights(view, length_bias, folder_bias, folder_count, tag_bias)
  local tag_key = tag_bias and Tags.bias_key(tag_bias) or ""
  if tag_key == "" then tag_bias = nil end
  if not length_bias and not folder_bias and not tag_bias then return nil end

  local n = #view.files
  local key = tostring(n) .. "|"
    .. (length_bias and string.format("L%.4f,%.4f", length_bias.center, length_bias.focus) or "")
    .. (folder_bias and string.format("F%.4f,%.4f,%d", folder_bias.center, folder_bias.focus, folder_count or 0) or "")
    .. (tag_bias and ("T" .. tag_key) or "")
  if view._w_key == key then return view._w end

  local w = { key = key }
  local use_length = length_bias and view.sorted
  for i = 1, n do
    local value = 1
    if use_length then
      value = value * Bias.weight_at(i, n, length_bias.center, length_bias.focus)
    end
    if folder_bias then
      local fi = view.file_folder and view.file_folder[i]
      if fi then
        value = value * Bias.weight_at(fi, folder_count, folder_bias.center, folder_bias.focus)
      end
    end
    if tag_bias then
      value = value * Tags.bias_weight(tag_bias, view.files[i])
    end
    w[i] = value
  end
  view._w = w
  view._w_key = key
  return w
end

local function pick_sample(pool, slot, used_log_enabled, max_seconds, length_bias, tag_bias)
  if slot.lock_file then return slot.lock_file end
  if not pool or not pool.files or #pool.files == 0 then
    return nil, "no sample available in pool"
  end

  -- A slot may override the kit-wide character: "the whole kit dark, but this
  -- one hat short and sharp".
  if Tags.bias_active(slot.tag_bias) then tag_bias = slot.tag_bias end

  local folder_count = pool.folder_count or #(pool.folders or {})
  local folder_bias = Bias.for_folders(pool.folder_bias, folder_count)

  local spec = Categories.spec_for_slot(slot)
  local view = effective_pool(pool, max_seconds, spec, length_bias ~= nil)
  if #view.files == 0 then
    if spec then
      local suffix = (max_seconds and max_seconds > 0) and " within max length" or ""
      return nil, string.format("no samples matching '%s'%s", Categories.spec_label(spec), suffix)
    end
    return nil, string.format("all samples exceed max length (%.1fs)", max_seconds)
  end

  local weights = view_weights(view, length_bias, folder_bias, folder_count, tag_bias)

  if used_log_enabled then
    local unused = {}
    for i, f in ipairs(view.files) do
      if not UsedLog.is_used(f) then unused[#unused + 1] = i end
    end
    if #unused == 0 then
      for _, f in ipairs(view.files) do UsedLog.clear_used(f) end
      for i = 1, #view.files do unused[i] = i end
    end
    local index
    if weights then
      index = Bias.pick_weighted_subset(unused, weights)
    else
      index = unused[Rng.random(#unused)]
    end
    local pick = view.files[index]
    UsedLog.mark_used(pick)
    return pick
  end

  return Picker.pick(view, weights)
end

-- Generates ONE kit from a KitDef. Batch = call this N times (see new_batch()).
-- pools: table keyed by pool_id -> Pool. script_path: needed for the wordlist
-- fallback file when kitdef.name_prefix is nil.
-- Kit N of a seeded batch runs on seed + N - 1, so every kit in the batch has
-- a seed of its own and can be rebuilt on its own -- "seed 84246" is one kit,
-- not "the 34th kit of run 84213". Rng.new spins the generator before handing
-- it over, which is what stops those consecutive seeds opening on very nearly
-- the same pick.
function M.seed_for(kitdef, kit_index)
  local base = tonumber(kitdef and kitdef.seed)
  if not base then return nil end
  return math.floor(base) + (kit_index or 1) - 1
end

function M.generate_kit(kitdef, pools, kit_index, script_path)
  -- Installed for the whole render and cleared at the end. There is one exit,
  -- and a crash on the way cannot leave a stale generator behind either: the
  -- next render installs its own first, and an unseeded one installs nothing,
  -- which is plain math.random.
  Rng.use(M.seed_for(kitdef, kit_index))

  local kit_name
  if kitdef.name_prefix and kitdef.name_prefix ~= "" then
    if kitdef.name_numbered == false then
      kit_name = kitdef.name_prefix
    else
      kit_name = string.format("%s %03d", kitdef.name_prefix, kit_index)
    end
  else
    kit_name = M.suggest_kit_name(kitdef, pools, script_path, kitdef.name_seed)
  end

  local dest_dir, final_name = Exporter.make_folder(kitdef.export.destination, kit_name)

  local bias = Bias.for_kit(kitdef.export.length_bias, kit_index, math.max(1, kitdef.export.kit_count or 1))
  local tag_bias = Tags.bias_active(kitdef.export.tag_bias) and kitdef.export.tag_bias or nil

  local results = {}
  local errors = {}

  for _, slot in ipairs(kitdef.slots) do
    local pool = pools[slot.pool_id]
    local sample, pick_err = pick_sample(pool, slot, kitdef.export.write_usedlog, kitdef.export.max_sample_seconds, bias, tag_bias)

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

  Rng.clear()
  return {
    name = final_name, dest = dest_dir, results = results, errors = errors,
    stitched = stitched, seed = M.seed_for(kitdef, kit_index),
  }
end

-- How much of the material behind a kit carries a measurement. A character
-- bias over an unanalysed pool is not an error -- every weight comes out equal
-- and picking stays random -- but it does nothing, so the UI has to be able to
-- say so instead of leaving the user wondering.
function M.tag_coverage(pools)
  local files, seen = {}, {}
  for _, pool in pairs(pools or {}) do
    for _, f in ipairs(pool.files or {}) do
      if not seen[f] then
        seen[f] = true
        files[#files + 1] = f
      end
    end
  end
  return Tags.count_analyzed(files), #files
end

-- Stateful batch runner: call runner:step() once (or a few times) per UI
-- frame so a 100+ kit batch does not freeze the ReaImGui loop.
function M.new_batch(kitdef, pools, script_path)
  local prefetch
  local needs_lengths = Bias.is_active(kitdef.export.length_bias)
    or ((tonumber(kitdef.export.max_sample_seconds) or 0) > 0)
  if needs_lengths then
    local files, seen = {}, {}
    for _, pool in pairs(pools) do
      for _, f in ipairs(pool.files or {}) do
        if not seen[f] then
          seen[f] = true
          files[#files + 1] = f
        end
      end
    end
    prefetch = Duration.new_prefetch(files)
    if prefetch.total == 0 then prefetch = nil end
  end

  return {
    kitdef = kitdef,
    pools = pools,
    script_path = script_path,
    index = 0,
    total = math.max(1, kitdef.export.kit_count or 1),
    kits = {},
    errors = {},
    done = false,
    prefetch = prefetch,

    step = function(self)
      if self.done then return false end
      if self.prefetch then
        if self.prefetch:step(96) then return true end
        self.prefetch = nil
        return true
      end
      self.index = self.index + 1
      local ok, kit_or_err = pcall(M.generate_kit, self.kitdef, self.pools, self.index, self.script_path)
      if ok then
        self.kits[#self.kits + 1] = kit_or_err
      else
        self.errors[#self.errors + 1] = string.format("Kit %d: %s", self.index, tostring(kit_or_err))
      end
      if self.index >= self.total then
        self.done = true
        Duration.flush()
      end
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
    name_numbered = false,
    name_seed = opts.name_seed,
    -- Not the same thing as name_seed, which is a start *word* for the kit name
    -- generator. This one makes the whole pick reproducible.
    seed = opts.seed,
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
      length_bias = opts.length_bias,
      tag_bias = opts.tag_bias,
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
