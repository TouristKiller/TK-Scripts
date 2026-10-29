local json = require("core.json")
local Settings = require("core.settings")

-- A profile is the part of the settings that is a choice: which modules are
-- shown, the theme and scale, and how each module is set up. What the user is
-- in the middle of - the open module, window positions, a search, a filter,
-- the current folder, a running timer - is state, and never goes into a
-- profile. Otherwise "Reset to my default" would also send you back to the
-- folder you happened to be in when you saved it, or hide files behind a
-- rating filter you forgot was on.
local M = {}

M.FORMAT = "tk_workbench_profile"
M.VERSION = 1

-- Top-level keys that are where you are, not how you work.
local TOP_STATE = {
  window_width = true, window_height = true,
  active_module = true,
  split_view_enabled = true, split_module = true, split_ratio = true,
  split_orientation = true, split_pinned_pane = true, split_pinned_return = true,
  auto_collapse_pin_edge = true,
  first_run_done = true
}

-- Safe for every module: names that mean state wherever they appear.
local STATE_PATTERNS = {
  "^window_[xywh]$", "_window$", "^last_", "^pending_", "_epoch$", "_ringing$",
  "_guid$", "^search_term$", "^search$", "^current_location", "^recent_colors$"
}

-- Names that are only state in one module: "source" is the group being
-- browsed in Plugin Browser, but a real setting in Timepiece. A module can add
-- its own with M.profile_state_keys = { ... }.
local MODULE_STATE = {
  plugin_browser = { "group_selection", "source" },
  project_browser = { "folder_paths" },
  media_browser = { "auto_selected_category", "minimum_rating", "rating_match" },
  track_tags = { "filter_tag", "selected_tags", "hidden_tags" },
  color_studio = { "auto_rule_index", "palette_edit_slot", "active_color" },
  arrange_bg_presets = { "selected", "last_toggle", "favorite_selected" },
  calculator = { "active_tab", "ms_value", "samples_value", "db_value", "lin_value", "freq_value", "note_index", "note_octave", "decay_predelay_index" },
  control_room = { "meter_open", "mono_restore", "settings_version" },
  notes = { "active_context" }
}

local function module_state_set(module_id, modules_by_id)
  local set = {}
  for _, key in ipairs(MODULE_STATE[module_id] or {}) do set[key] = true end
  local module = modules_by_id and modules_by_id[module_id]
  if module and type(module.profile_state_keys) == "table" then
    for _, key in ipairs(module.profile_state_keys) do set[key] = true end
  end
  return set
end

local function matches_pattern(key)
  for _, pattern in ipairs(STATE_PATTERNS) do
    if tostring(key):match(pattern) then return true end
  end
  return false
end

-- A table under a module's own id is that module's settings.
local function is_module_table(key, value, modules_by_id)
  return type(value) == "table" and modules_by_id and modules_by_id[key] ~= nil
end

function M.is_state(module_id, key, modules_by_id)
  if module_id == nil then return TOP_STATE[key] == true end
  if matches_pattern(key) then return true end
  return module_state_set(module_id, modules_by_id)[key] == true
end

-- Splits settings into choices and state, both deep copies.
function M.split(settings, modules_by_id)
  local choices, state = {}, {}
  for key, value in pairs(settings or {}) do
    if is_module_table(key, value, modules_by_id) then
      local module_choices, module_state = {}, {}
      for sub_key, sub_value in pairs(value) do
        local copy = type(sub_value) == "table" and Settings.copy(sub_value) or sub_value
        if M.is_state(key, sub_key, modules_by_id) then module_state[sub_key] = copy else module_choices[sub_key] = copy end
      end
      choices[key] = module_choices
      if next(module_state) then state[key] = module_state end
    elseif M.is_state(nil, key, modules_by_id) then
      state[key] = type(value) == "table" and Settings.copy(value) or value
    else
      choices[key] = type(value) == "table" and Settings.copy(value) or value
    end
  end
  return choices, state
end

-- Like Settings.merge, except that a list from the profile replaces the
-- default list. Merged index by index, a profile with two auto rules over a
-- default of three would come back with the third default rule still there.
local function is_list(value)
  return type(value) == "table" and (next(value) == nil or value[1] ~= nil)
end

local function merge_choices(base, override)
  local result = Settings.copy(base)
  for key, value in pairs(override or {}) do
    if type(value) == "table" and type(result[key]) == "table" and not is_list(value) then
      result[key] = merge_choices(result[key], value)
    elseif type(value) == "table" then
      result[key] = Settings.copy(value)
    else
      result[key] = value
    end
  end
  return result
end

function M.snapshot(settings, modules_by_id)
  local choices = M.split(settings, modules_by_id)
  return choices
end

-- New settings from a profile's choices (nil = factory), keeping the current
-- state on top. Module tables the profile does not mention start empty and
-- are filled with that module's defaults the next time it runs.
function M.compose(current, choices, modules_by_id)
  local result = merge_choices(Settings.defaults(), choices or {})
  local _, state = M.split(current, modules_by_id)
  for key, value in pairs(state) do
    if is_module_table(key, current[key], modules_by_id) then
      result[key] = type(result[key]) == "table" and result[key] or {}
      for sub_key, sub_value in pairs(value) do result[key][sub_key] = sub_value end
    else
      result[key] = value
    end
  end
  return result
end

-- One module's settings from a profile (nil = factory), keeping its state.
function M.compose_module(current, module_id, choices, modules_by_id)
  local factory = Settings.defaults()[module_id]
  local result = type(factory) == "table" and factory or {}
  local wanted = choices and choices[module_id]
  if type(wanted) == "table" then result = merge_choices(result, wanted) end
  for key, value in pairs((current and current[module_id]) or {}) do
    if M.is_state(module_id, key, modules_by_id) then
      result[key] = type(value) == "table" and Settings.copy(value) or value
    end
  end
  return result
end

local function read_file(path)
  local file = io.open(path, "r")
  if not file then return nil end
  local content = file:read("*a")
  file:close()
  return content
end

function M.write(path, choices, label)
  local ok, encoded = pcall(json.encode, {
    format = M.FORMAT,
    version = M.VERSION,
    label = label or "",
    saved = os.date("%Y-%m-%d %H:%M"),
    settings = choices
  })
  if not ok or not encoded then return false, "could not encode the profile" end
  local file = io.open(path, "w")
  if not file then return false, "could not write " .. tostring(path) end
  file:write(encoded, "\n")
  file:close()
  return true
end

-- Returns the profile's choices and its header, or nil and why not.
function M.read(path)
  local content = read_file(path)
  if not content or content == "" then return nil, "file not found" end
  local ok, decoded = pcall(json.decode, content)
  if not ok or type(decoded) ~= "table" then return nil, "not a valid profile file" end
  if decoded.format ~= M.FORMAT or type(decoded.settings) ~= "table" then return nil, "not a TK Workbench profile" end
  return decoded.settings, decoded
end

return M
