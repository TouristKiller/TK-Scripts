local r = reaper
local json = require("core.json")

local M = {}

local EXT_SECTION = "TK_Kit_Maker"
local EXT_KEY = "browser_state"

local function normalize(path)
  path = tostring(path or ""):gsub("\\", "/")
  return path:gsub("/+$", "")
end

local function default_state()
  return {
    collections = {},
    kit_collections = {},
    -- Whether the collections panel shows its group headings at all. The
    -- filing is kept either way -- switching this off ignores the groups, it
    -- does not undo them.
    collections_flat = false,
    -- Which collection groups are folded shut, keyed by lower-cased name so a
    -- group renamed to a different capitalisation stays as you left it.
    collapsed_groups = {},
    selected_id = nil,
    sample_selected_id = nil,
    kit_selected_id = nil,
    manager_visible = false,
    manager_mode = "view",
    search = "",
    browser_mode = "packs",
    collection_view = "list",
    tile_size = "normal",
    auto_audition = true,
    show_tags = true,
    -- Which of the two the strip under the list is showing: the tags of the
    -- selected sample, or its waveform with the slice points on it.
    detail_view = "tags",
    sample_view = "list",
    list_flat = false,
    -- How the sample list is ordered. Persisted, unlike the tag filter: an
    -- order you forgot about still shows you everything, so it cannot leave you
    -- staring at a pack that looks half empty.
    sort_mode = "name",
    sort_desc = false,
    grid_x = "tone",
    grid_y = "decay",
    grid_size = 4,
    grid_center = 0.5,
    grid_focus = 0.6,
    preview_volume = 1.0,
    manager_rack_color = 0x4DA3FFFF,
    manager_rack_gradient = false,
    manager_save_dir = "",
    small_focus = "split",
    split_w = 240,
    split_h = 240,
    view = "browser",
    relink_prefixes = {},
  }
end

local function sanitize(state)
  if type(state) ~= "table" then return default_state() end

  local out = default_state()
  if type(state.search) == "string" then out.search = state.search end
  out.manager_visible = state.manager_visible == true
  out.manager_mode = state.manager_mode == "make" and "make" or "view"
  out.browser_mode = (state.browser_mode == "kits") and "kits" or "packs"
  out.collection_view = (state.collection_view == "tiles") and "tiles" or "list"
  if state.tile_size == "small" or state.tile_size == "large" or state.tile_size == "huge" then
    out.tile_size = state.tile_size
  else
    out.tile_size = "normal"
  end
  out.auto_audition = state.auto_audition ~= false
  out.show_tags = state.show_tags ~= false
  out.detail_view = (state.detail_view == "slice") and "slice" or "tags"
  out.sample_view = (state.sample_view == "grid") and "grid" or "list"
  out.list_flat = state.list_flat == true
  out.collections_flat = state.collections_flat == true
  out.sort_mode = (state.sort_mode == "length") and "length" or "name"
  out.sort_desc = state.sort_desc == true
  if state.grid_x == "tone" or state.grid_x == "decay" or state.grid_x == "transient" then
    out.grid_x = state.grid_x
  end
  if state.grid_y == "tone" or state.grid_y == "decay" or state.grid_y == "transient" then
    out.grid_y = state.grid_y
  end
  if out.grid_x == out.grid_y then
    out.grid_y = (out.grid_x == "decay") and "tone" or "decay"
  end
  out.grid_size = math.max(3, math.min(8, math.floor(tonumber(state.grid_size) or 4)))
  out.grid_center = math.max(0, math.min(1, tonumber(state.grid_center) or 0.5))
  out.grid_focus = math.max(0, math.min(1, tonumber(state.grid_focus) or 0.6))
  out.preview_volume = math.max(0, math.min(2, tonumber(state.preview_volume) or 1.0))
  out.manager_rack_color = math.max(0, math.min(0xFFFFFFFF, math.floor(tonumber(state.manager_rack_color) or 0x4DA3FFFF)))
  out.manager_rack_gradient = state.manager_rack_gradient == true
  if type(state.manager_save_dir) == "string" then
    out.manager_save_dir = normalize(state.manager_save_dir)
  end
  if state.small_focus == "catalog" or state.small_focus == "samples" or state.small_focus == "split" then
    out.small_focus = state.small_focus
  else
    out.small_focus = "split"
  end
  out.split_w = math.max(120, math.min(1600, tonumber(state.split_w) or 240))
  out.split_h = math.max(100, math.min(1600, tonumber(state.split_h) or 240))
  if state.view == "sequencer" then
    out.view = "step"
  elseif state.view == "browser" or state.view == "explosion" or state.view == "builder" or state.view == "step" or state.view == "euclid" then
    out.view = state.view
  else
    out.view = "browser"
  end

  if type(state.relink_prefixes) == "table" then
    for _, e in ipairs(state.relink_prefixes) do
      local old_prefix = normalize(type(e.old) == "string" and e.old or "")
      local new_prefix = normalize(type(e.new) == "string" and e.new or "")
      if old_prefix ~= "" and new_prefix ~= "" and #out.relink_prefixes < 24 then
        out.relink_prefixes[#out.relink_prefixes + 1] = { old = old_prefix, new = new_prefix }
      end
    end
  end

  if type(state.collections) == "table" then
    local seen = {}
    for _, c in ipairs(state.collections) do
      local name = type(c.name) == "string" and c.name or ""
      local path = normalize(type(c.path) == "string" and c.path or "")
      local recursive = c.recursive ~= false
      local pinned = c.pinned == true
      local group = type(c.group) == "string" and c.group:gsub("^%s+", ""):gsub("%s+$", "") or ""
      local cover_path = normalize(type(c.cover_path) == "string" and c.cover_path or "")
      if path ~= "" then
        local key = path:lower()
        if not seen[key] then
          seen[key] = true
          out.collections[#out.collections + 1] = {
            id = tostring(c.id or ("col_" .. tostring(#out.collections + 1))),
            name = name ~= "" and name or (path:match("([^/]+)$") or path),
            path = path,
            recursive = recursive,
            pinned = pinned,
            group = group ~= "" and group or nil,
            cover_path = cover_path ~= "" and cover_path or nil,
          }
        end
      end
    end
  end

  if type(state.kit_collections) == "table" then
    local seen = {}
    for _, c in ipairs(state.kit_collections) do
      local name = type(c.name) == "string" and c.name or ""
      local path = normalize(type(c.path) == "string" and c.path or "")
      local recursive = c.recursive ~= false
      local pinned = c.pinned == true
      local group = type(c.group) == "string" and c.group:gsub("^%s+", ""):gsub("%s+$", "") or ""
      local cover_path = normalize(type(c.cover_path) == "string" and c.cover_path or "")
      if path ~= "" then
        local key = path:lower()
        if not seen[key] then
          seen[key] = true
          out.kit_collections[#out.kit_collections + 1] = {
            id = tostring(c.id or ("kit_" .. tostring(#out.kit_collections + 1))),
            name = name ~= "" and name or (path:match("([^/]+)$") or path),
            path = path,
            recursive = recursive,
            pinned = pinned,
            group = group ~= "" and group or nil,
            cover_path = cover_path ~= "" and cover_path or nil,
          }
        end
      end
    end
  end

  if type(state.selected_id) == "string" then
    out.selected_id = state.selected_id
  end

  if type(state.sample_selected_id) == "string" then
    out.sample_selected_id = state.sample_selected_id
  end

  if type(state.kit_selected_id) == "string" then
    out.kit_selected_id = state.kit_selected_id
  end

  if not out.selected_id and #out.collections > 0 then
    out.selected_id = out.collections[1].id
  end

  if not out.sample_selected_id and #out.collections > 0 then
    out.sample_selected_id = out.collections[1].id
  end

  if not out.kit_selected_id and #out.kit_collections > 0 then
    out.kit_selected_id = out.kit_collections[1].id
  end

  if out.browser_mode == "kits" then
    out.selected_id = out.kit_selected_id or out.selected_id
  else
    out.selected_id = out.sample_selected_id or out.selected_id
  end

  -- Only names that are still in use. Folding a group shut and then emptying
  -- it would otherwise leave an entry behind for ever, and a group recreated
  -- under the same name months later would come back mysteriously collapsed.
  if type(state.collapsed_groups) == "table" then
    local live = {}
    for _, list in ipairs({ out.collections, out.kit_collections }) do
      for _, c in ipairs(list) do
        if c.group then live[c.group:lower()] = true end
      end
    end
    for name, folded in pairs(state.collapsed_groups) do
      if type(name) == "string" and folded == true and live[name:lower()] then
        out.collapsed_groups[name:lower()] = true
      end
    end
  end

  return out
end

function M.load()
  local raw = r.GetExtState(EXT_SECTION, EXT_KEY)
  if raw == "" then return default_state() end
  local ok, data = pcall(json.decode, raw)
  if not ok then return default_state() end
  return sanitize(data)
end

function M.save(state)
  local payload = sanitize(state)
  local ok, encoded = pcall(json.encode, payload)
  if ok and encoded then
    r.SetExtState(EXT_SECTION, EXT_KEY, encoded, true)
  end
end

return M
