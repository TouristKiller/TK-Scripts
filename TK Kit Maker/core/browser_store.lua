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
    selected_id = nil,
    sample_selected_id = nil,
    kit_selected_id = nil,
    manager_visible = false,
    manager_mode = "view",
    search = "",
    browser_mode = "packs",
    collection_view = "list",
    auto_audition = true,
    preview_volume = 1.0,
    manager_audition_mode = "track",
    manager_rack_color = 0x4DA3FFFF,
    manager_rack_gradient = false,
    manager_save_dir = "",
    small_focus = "split",
    split_w = 240,
    split_h = 240,
    view = "browser",
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
  out.auto_audition = state.auto_audition ~= false
  out.preview_volume = math.max(0, math.min(2, tonumber(state.preview_volume) or 1.0))
  out.manager_audition_mode = state.manager_audition_mode == "preview" and "preview" or "track"
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
  if state.view == "browser" or state.view == "explosion" or state.view == "builder" or state.view == "sequencer" then
    out.view = state.view
  else
    out.view = "browser"
  end

  if type(state.collections) == "table" then
    local seen = {}
    for _, c in ipairs(state.collections) do
      local name = type(c.name) == "string" and c.name or ""
      local path = normalize(type(c.path) == "string" and c.path or "")
      local recursive = c.recursive ~= false
      local pinned = c.pinned == true
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
