local r = reaper
local Theme = require("core.theme")
local UI = require("core.ui")

local M = {
  id = "automation_item_manager",
  title = "Automation Item Manager",
  icon = "AIM",
  version = "0.1.0"
}

local state = {
  items = {},
  loaded = false,
  automation_folder = r.GetResourcePath() .. "/AutomationItems",
  automation_folder_exists = false,
  preview_width = 120,
  preview_height = 60,
  controls_height = 132,
  footer_message = "",
  footer_message_time = 0,
  footer_message_duration = 4.0,
  has_sws = r.BR_GetMouseCursorContext ~= nil,
  is_dragging = false,
  drag_item = nil,
  drag_hover_env = nil,
  drag_hover_pos = nil,
  drag_hover_name = nil,
  morph_cleanup = nil
}

local dir_sep = package.config:sub(1, 1)

local default_settings = {
  enable_loop = false,
  show_lines_only = false,
  move_edit_cursor = false,
  use_time_selection = true,
  show_tooltips = true,
  curve_color = 0x00FF00FF,
  points_color = 0xFFFF00FF
}

local SC = {}
SC.__index = SC

local vol_params = {
  [3] = { split = 1.0000, n = 3.3219, max_db = 0 },
  [2] = { split = 0.8421, n = 3.3180, max_db = 6 },
  [6] = { split = 0.7083, n = 3.3164, max_db = 12 },
  [7] = { split = 0.5387, n = 3.4490, max_db = 24 }
}

function SC.new_volume()
  local raw = 7
  if r.SNM_GetIntConfigVar then raw = r.SNM_GetIntConfigVar("volenvrange", 0) end
  local params = vol_params[raw] or vol_params[7]
  local converter = setmetatable({}, SC)
  converter.type = "volume"
  converter.max_db = params.max_db
  converter.max_gain = 10.0 ^ (params.max_db / 20.0)
  converter.split = params.split
  converter.n = params.n
  return converter
end

function SC.new_pitch()
  local range = 12
  if r.SNM_GetIntConfigVar then
    local raw = r.SNM_GetIntConfigVar("pitchenvrange", 0)
    local value = raw & 0xFF
    if value > 0 then range = value end
  end
  local converter = setmetatable({}, SC)
  converter.type = "pitch"
  converter.range = range
  return converter
end

function SC.new_tempo()
  local min_tempo, max_tempo = 60, 180
  if r.SNM_GetIntConfigVar then
    local raw_min = r.SNM_GetIntConfigVar("tempoenvmin", -1)
    local raw_max = r.SNM_GetIntConfigVar("tempoenvmax", -1)
    if raw_min > 0 then min_tempo = raw_min end
    if raw_max > 0 then max_tempo = raw_max end
  end
  local converter = setmetatable({}, SC)
  converter.type = "tempo"
  converter.t_min = min_tempo
  converter.t_max = max_tempo
  return converter
end

function SC:to_native(value)
  if self.type == "volume" then
    if value <= 0 then return 0.0 end
    if value >= 1 then return self.max_gain end
    if value <= self.split then return (value / self.split) ^ self.n end
    local db = (value - self.split) / (1.0 - self.split) * self.max_db
    return 10.0 ^ (db / 20.0)
  end
  if self.type == "pitch" then return (math.max(0, math.min(1, value)) * 2.0 - 1.0) * self.range end
  if self.type == "tempo" then return self.t_min + math.max(0, math.min(1, value)) * (self.t_max - self.t_min) end
  return value
end

function SC:from_native(native)
  if self.type == "volume" then
    if native <= 0 then return 0.0 end
    if native >= self.max_gain then return 1.0 end
    if native <= 1.0 then return self.split * (native ^ (1.0 / self.n)) end
    local db = math.log(native) / math.log(10) * 20.0
    return self.split + (1.0 - self.split) * db / self.max_db
  end
  if self.type == "pitch" then return (math.max(-self.range, math.min(self.range, native)) / self.range + 1.0) / 2.0 end
  if self.type == "tempo" then return (math.max(self.t_min, math.min(self.t_max, native)) - self.t_min) / (self.t_max - self.t_min) end
  return native
end

function SC:to_envelope(value, mode)
  return r.ScaleToEnvelopeMode(mode, self:to_native(value))
end

function SC:from_envelope(value, mode)
  return self:from_native(r.ScaleFromEnvelopeMode(mode, value))
end

local function set_footer_message(message)
  state.footer_message = message
  state.footer_message_time = r.time_precise()
end

local function module_settings(app)
  app.settings.automation_item_manager = app.settings.automation_item_manager or {}
  local settings = app.settings.automation_item_manager
  for key, value in pairs(default_settings) do
    if settings[key] == nil then settings[key] = value end
  end
  return settings
end

local function save_module_settings(app)
  if app.save_settings then app.save_settings() end
end

local function tooltip(ctx, app, settings, text)
  if settings.show_tooltips and r.ImGui_IsItemHovered(ctx) and UI.tooltip_ready(ctx, app, text) then
    r.ImGui_BeginTooltip(ctx)
    r.ImGui_Text(ctx, text)
    r.ImGui_EndTooltip(ctx)
  end
end

local function path_join(a, b)
  if a:sub(-1) == "/" or a:sub(-1) == "\\" then return a .. b end
  return a .. dir_sep .. b
end

local function normalize_path(path)
  local normalized = path:gsub("\\", "/")
  if normalized:sub(-1) == "/" then normalized = normalized:sub(1, -2) end
  return normalized
end

local function basename(path)
  return path:match("([^/\\]+)$") or path
end

local function dirname(path)
  local directory = path:match("^(.*[/\\])")
  if not directory then return "" end
  if directory:sub(-1) == "/" or directory:sub(-1) == "\\" then directory = directory:sub(1, -2) end
  return directory
end

local function automation_folder_exists()
  local parent = dirname(state.automation_folder)
  local target = basename(state.automation_folder):lower()
  if not parent or parent == "" then return false end
  local index = 0
  while true do
    local child = r.EnumerateSubdirectories(parent, index)
    if not child then break end
    if child:lower() == target then return true end
    index = index + 1
  end
  return false
end

local function open_path(path)
  local os_name = r.GetOS()
  if os_name:match("^Win") then
    os.execute('explorer /e,"' .. path:gsub("/", "\\") .. '"')
  elseif os_name:match("^OSX") then
    os.execute('open "' .. path .. '"')
  else
    os.execute('xdg-open "' .. path .. '"')
  end
end

local function show_item_in_explorer(item)
  if not item or not item.path then
    set_footer_message("Cannot show: invalid item path")
    return
  end
  local os_name = r.GetOS()
  if os_name:match("^Win") then
    os.execute('explorer /select,"' .. item.path:gsub("/", "\\") .. '"')
  elseif os_name:match("^OSX") then
    os.execute('open -R "' .. item.path .. '"')
  else
    open_path(dirname(item.path))
  end
end

local function ensure_automation_folder_exists()
  state.automation_folder_exists = automation_folder_exists()
  if state.automation_folder_exists then return true end
  local result = r.ShowMessageBox("AutomationItems folder not found:\n" .. state.automation_folder .. "\n\nCreate it now?", M.title, 4)
  if result ~= 6 then return false end
  local ok = r.RecursiveCreateDirectory and r.RecursiveCreateDirectory(state.automation_folder, 0) == 1
  if ok then
    state.automation_folder_exists = true
    set_footer_message("AutomationItems folder created")
    return true
  end
  set_footer_message("Could not create AutomationItems folder")
  return false
end

local function walk_autoitem_files(root)
  local results = {}
  local function walk(directory)
    local file_index = 0
    while true do
      local file_name = r.EnumerateFiles(directory, file_index)
      if not file_name then break end
      if file_name:lower():sub(-15) == ".reaperautoitem" then results[#results + 1] = path_join(directory, file_name) end
      file_index = file_index + 1
    end
    local folder_index = 0
    while true do
      local child = r.EnumerateSubdirectories(directory, folder_index)
      if not child then break end
      walk(path_join(directory, child))
      folder_index = folder_index + 1
    end
  end
  walk(root)
  return results
end

local function get_envelope_type(envelope)
  if not envelope then return "unknown" end
  local ok, name = r.GetEnvelopeName(envelope)
  if not ok then return "unknown" end
  name = name:lower()
  if name:match("volume") or name:match("vol") then return "volume" end
  if name:match("pan") then return "pan" end
  if name:match("mute") then return "mute" end
  if name:match("pitch") then return "pitch" end
  if name:match("send") then return "send" end
  if name:match("fx") or name:match("vst") or name:match("param") then return "fxparam" end
  return "unknown"
end

local function to_env_value(value, converter, low, high, mode)
  if converter then
    if converter.type == "volume" then return converter:to_envelope(value, mode) end
    return converter:to_native(value)
  end
  local fader_value = mode == 1 and value or low + value * (high - low)
  return r.ScaleToEnvelopeMode(mode, fader_value)
end

local function from_env_value(raw_value, converter, low, high, mode)
  local result
  if converter then
    if converter.type == "volume" then result = converter:from_envelope(raw_value, mode) else result = converter:from_native(raw_value) end
  else
    local fader_value = r.ScaleFromEnvelopeMode(mode, raw_value)
    if mode == 1 then
      result = fader_value
    else
      local range = high - low
      result = math.abs(range) < 1e-9 and 0.5 or (fader_value - low) / range
    end
  end
  if result ~= result or result >= math.huge or result <= -math.huge then return 0.0 end
  return result
end

local function get_envelope_info(envelope)
  if not envelope then return nil end
  local _, env_name = r.GetEnvelopeName(envelope)
  env_name = env_name or ""
  local mode = r.GetEnvelopeScalingMode(envelope)
  local converter = nil
  if env_name == "Volume" or env_name == "Volume (Pre-FX)" then
    converter = SC.new_volume()
  elseif env_name == "Pitch" then
    converter = SC.new_pitch()
  elseif env_name == "Tempo map" or env_name == "Tempo" then
    converter = SC.new_tempo()
  end
  local low, high = 0, 1
  if mode ~= 1 then
    local ok, chunk = r.GetEnvelopeStateChunk(envelope, "", false)
    if ok and chunk then
      local min_value = tonumber(chunk:match("\nMINVAL ([%-%.%d]+)"))
      local max_value = tonumber(chunk:match("\nMAXVAL ([%-%.%d]+)"))
      if min_value and max_value and max_value - min_value > 1e-9 then low, high = min_value, max_value end
    end
    if env_name == "Pan" or env_name == "Pan (Pre-FX)" or env_name == "Width" or env_name == "Width (Pre-FX)" then low, high = -1, 1 end
  end
  local parm_min = r.GetEnvelopeInfo_Value(envelope, "PARM_MIN")
  local parm_max = r.GetEnvelopeInfo_Value(envelope, "PARM_MAX")
  if parm_min and parm_max and parm_max - parm_min > 1e-9 then low, high = parm_min, parm_max end
  return { name = env_name, conv = converter, lo = low, hi = high, mode = mode }
end

local function normalize_source_value(value, source_type)
  if source_type == "pan_or_bipolar" then return (value + 1.0) / 2.0 end
  if source_type == "volume_or_gain" and value > 1.0 then return SC.new_volume():from_native(value) end
  return math.max(0, math.min(1, value))
end

local function resolve_target_envelope()
  local selected_envelope = r.GetSelectedEnvelope(0)
  if selected_envelope then return selected_envelope end
  if r.CountSelectedMediaItems(0) <= 0 then return nil end
  local item = r.GetSelectedMediaItem(0, 0)
  local take = item and r.GetActiveTake(item)
  if not take then return nil end
  for index = 0, r.CountTakeEnvelopes(take) - 1 do
    local envelope = r.GetTakeEnvelope(take, index)
    local ok, chunk = r.GetEnvelopeStateChunk(envelope, "", false)
    if ok and chunk then
      local visible = tonumber(chunk:match("\nVIS (%d)"))
      if not visible or visible == 1 then return envelope end
    end
  end
  return nil
end

local function get_effective_range(settings, default_length)
  if settings.use_time_selection then
    local time_start, time_end = r.GetSet_LoopTimeRange2(0, false, false, 0, 0, false)
    if time_end - time_start >= 0.01 then return time_start, time_end, true end
  end
  local cursor = r.GetCursorPosition()
  return cursor, cursor + (default_length or 1.0), false
end

local function interpolate_value(value_a, value_b, amount, shape, tension)
  if shape == 1 then return amount >= 1.0 and value_b or value_a end
  if shape == 2 then
    local smooth = amount * amount * (3.0 - 2.0 * amount)
    return value_a + (value_b - value_a) * smooth
  end
  if shape == 3 then return value_a + (value_b - value_a) * amount * amount end
  if shape == 4 then
    local curve = 1.0 - (1.0 - amount) * (1.0 - amount)
    return value_a + (value_b - value_a) * curve
  end
  if shape == 5 then
    local smoother = amount * amount * amount * (amount * (amount * 6.0 - 15.0) + 10.0)
    return value_a + (value_b - value_a) * smoother
  end
  if shape == 6 then
    local sine = (1.0 - math.cos(amount * math.pi)) * 0.5
    return value_a + (value_b - value_a) * sine
  end
  return value_a + (value_b - value_a) * amount
end

local function parse_automation_file(file_path)
  local file = file_path and io.open(file_path, "r")
  if not file then return nil end
  local content = file:read("*all")
  file:close()
  local data = { points = {}, srclen = 1.0, point_count = 0, source_file = file_path, source_envelope_type = "unknown", value_range = { min = math.huge, max = -math.huge } }
  for line in content:gmatch("[^\r\n]+") do
    line = line:gsub("^%s+", ""):gsub("%s+$", "")
    if line:match("^SRCLEN") then
      data.srclen = tonumber(line:match("SRCLEN%s+([%d%.%-]+)")) or 1.0
    elseif line:match("^PPT") then
      local time_text, value_text, shape_text, tension_text = line:match("PPT%s+([%d%.%-]+)%s+([%d%.%-]+)%s+([%d%.%-]+)%s*([%d%.%-]*)")
      local time = tonumber(time_text)
      local value = tonumber(value_text)
      if time and value then
        data.points[#data.points + 1] = { time = time, value = value, shape = tonumber(shape_text) or 0, tension = tonumber(tension_text) or 0 }
        data.point_count = data.point_count + 1
        data.value_range.min = math.min(data.value_range.min, value)
        data.value_range.max = math.max(data.value_range.max, value)
      end
    end
  end
  if data.value_range.min == math.huge then data.value_range.min = 0 end
  if data.value_range.max == -math.huge then data.value_range.max = 1 end
  local min_value = data.value_range.min
  local max_value = data.value_range.max
  if min_value >= 0.0 and max_value <= 1.0 then
    data.source_envelope_type = "mute_or_normalized"
  elseif min_value >= -1.0 and max_value <= 1.0 then
    data.source_envelope_type = "pan_or_bipolar"
  elseif min_value >= 0.0 and max_value > 1.0 then
    data.source_envelope_type = "volume_or_gain"
  else
    data.source_envelope_type = "custom_range"
  end
  return data
end

local function generate_preview(item_data)
  if not item_data or not item_data.points or #item_data.points == 0 then return nil end
  local preview = { width = state.preview_width, height = state.preview_height, curve_points = {}, control_points = {} }
  local pixel_points = {}
  for _, point in ipairs(item_data.points) do
    if point.time and point.value then
      local x = (point.time / item_data.srclen) * state.preview_width
      local source_type = item_data.source_envelope_type
      local normalized = point.value
      if source_type == "pan_or_bipolar" then normalized = (point.value + 1.0) / 2.0 else normalized = math.max(0.0, math.min(1.0, point.value)) end
      local y = (1.0 - normalized) * state.preview_height
      pixel_points[#pixel_points + 1] = { x = x, y = y, value = point.value, shape = point.shape or 0, tension = point.tension or 0 }
      preview.control_points[#preview.control_points + 1] = { x = x, y = y }
    end
  end
  for index = 1, #pixel_points - 1 do
    local point_a = pixel_points[index]
    local point_b = pixel_points[index + 1]
    preview.curve_points[#preview.curve_points + 1] = { x = point_a.x, y = point_a.y }
    local segment_length = point_b.x - point_a.x
    if segment_length > 0 then
      local steps = math.max(3, math.floor(segment_length / 1.5))
      for step = 1, steps - 1 do
        local amount = step / steps
        local x = point_a.x + (point_b.x - point_a.x) * amount
        local y_value = interpolate_value(point_a.value or 0, point_b.value or 0, amount, point_a.shape or 0, point_a.tension or 0)
        preview.curve_points[#preview.curve_points + 1] = { x = x, y = (1.0 - y_value) * state.preview_height }
      end
    end
  end
  if #pixel_points > 0 then
    local last_point = pixel_points[#pixel_points]
    preview.curve_points[#preview.curve_points + 1] = { x = last_point.x, y = last_point.y }
  end
  return preview
end

local function sort_items()
  table.sort(state.items, function(a, b)
    local folder_a = (a.display_folder or "Home"):lower()
    local folder_b = (b.display_folder or "Home"):lower()
    if folder_a ~= folder_b then
      if folder_a == "home" then return true end
      if folder_b == "home" then return false end
      return folder_a < folder_b
    end
    return (a.name or ""):lower() < (b.name or ""):lower()
  end)
end

local function scan_automation_items()
  state.items = {}
  state.automation_folder_exists = automation_folder_exists()
  if not state.automation_folder_exists then
    set_footer_message("AutomationItems folder not found. Save an automation item first or create the folder.")
    return
  end
  local files = walk_autoitem_files(state.automation_folder)
  local root = normalize_path(state.automation_folder)
  for _, full_path in ipairs(files) do
    local filename = basename(full_path)
    local relative_path = normalize_path(full_path)
    local prefix = root .. "/"
    if relative_path:sub(1, #prefix) == prefix then relative_path = relative_path:sub(#prefix + 1) end
    local folder_path = relative_path:match("^(.*)/[^/]+$") or ""
    local display_folder = folder_path:match("^([^/]+)") or "Home"
    local item_data = parse_automation_file(full_path)
    if item_data then
      item_data.name = filename:gsub("%.ReaperAutoItem$", "")
      item_data.filename = filename
      item_data.path = full_path
      item_data.folder = folder_path
      item_data.display_folder = display_folder
      item_data.relative_path = relative_path
      item_data.preview = generate_preview(item_data)
      state.items[#state.items + 1] = item_data
    end
  end
  sort_items()
end

local function draw_preview(ctx, settings, preview, x, y, width, height)
  local draw_list = r.ImGui_GetWindowDrawList(ctx)
  local preview_width = math.max(1, tonumber(width) or state.preview_width)
  local preview_height = math.max(1, tonumber(height) or state.preview_height)
  local background = Theme.colors.frame_bg
  local border = Theme.colors.border
  r.ImGui_DrawList_AddRectFilled(draw_list, x, y, x + preview_width, y + preview_height, background, 3)
  r.ImGui_DrawList_AddRect(draw_list, x, y, x + preview_width, y + preview_height, border, 3, 0, 1)
  if not preview then
    r.ImGui_DrawList_AddText(draw_list, x + 10, y + 20, Theme.colors.text_dim, "No Preview")
    return
  end
  local source_width = math.max(1, tonumber(preview.width) or state.preview_width)
  local source_height = math.max(1, tonumber(preview.height) or state.preview_height)
  local scale_x = preview_width / source_width
  local scale_y = preview_height / source_height
  if preview.curve_points and #preview.curve_points > 1 then
    for index = 1, #preview.curve_points - 1 do
      local point_a = preview.curve_points[index]
      local point_b = preview.curve_points[index + 1]
      r.ImGui_DrawList_AddLine(draw_list, x + point_a.x * scale_x, y + point_a.y * scale_y, x + point_b.x * scale_x, y + point_b.y * scale_y, settings.curve_color, 1.5)
    end
  end
  if not settings.show_lines_only and preview.control_points then
    for _, point in ipairs(preview.control_points) do
      r.ImGui_DrawList_AddCircleFilled(draw_list, x + point.x * scale_x, y + point.y * scale_y, 4, settings.points_color)
      r.ImGui_DrawList_AddCircle(draw_list, x + point.x * scale_x, y + point.y * scale_y, 4, 0x000000FF, 0, 1)
    end
  end
end

local function apply_parsed_data_as_envelope_points(app, item_data, target_position, replace_existing)
  local settings = module_settings(app)
  if not item_data or not item_data.points or #item_data.points == 0 then
    set_footer_message("No valid automation data")
    return false
  end
  local envelope = resolve_target_envelope()
  if not envelope then
    set_footer_message("Select an envelope lane first")
    return false
  end
  local env_info = get_envelope_info(envelope)
  local source_length = (item_data.srclen or 1.0) * 0.5
  local insert_start, insert_end, has_time_selection
  if target_position then
    insert_start = target_position
    insert_end = target_position + source_length
    has_time_selection = false
  else
    insert_start, insert_end, has_time_selection = get_effective_range(settings, source_length)
  end
  local target_length = insert_end - insert_start
  local time_scale = has_time_selection and source_length > 0.001 and target_length / source_length or 1.0
  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)
  if replace_existing then
    for index = r.CountEnvelopePoints(envelope) - 1, 0, -1 do
      local ok, time = r.GetEnvelopePointEx(envelope, -1, index)
      if ok and time >= insert_start and time <= insert_end then r.DeleteEnvelopePointEx(envelope, -1, index) end
    end
  end
  local points_added = 0
  for _, point in ipairs(item_data.points) do
    local corrected_time = point.time * 0.5
    local absolute_time = insert_start + corrected_time * time_scale
    local normalized_value = normalize_source_value(point.value, item_data.source_envelope_type)
    local final_value = to_env_value(normalized_value, env_info.conv, env_info.lo, env_info.hi, env_info.mode)
    local ok = r.InsertEnvelopePoint(envelope, absolute_time, final_value, point.shape or 0, point.tension or 0, false, true)
    if ok then points_added = points_added + 1 end
  end
  r.Envelope_SortPoints(envelope)
  r.PreventUIRefresh(-1)
  r.UpdateArrange()
  r.Undo_EndBlock("Automation Item Manager: Apply envelope points", -1)
  set_footer_message("Applied " .. points_added .. " envelope points" .. (has_time_selection and " (fitted to time selection)" or ""))
  return true
end

local function convert_selected_envelope_points_to_automation_item()
  local envelope = r.GetSelectedEnvelope(0)
  if not envelope then
    set_footer_message("Please select an envelope first")
    return false
  end
  local selected_count = 0
  local start_pos = math.huge
  local end_pos = 0
  for index = 0, r.CountEnvelopePoints(envelope) - 1 do
    local ok, time, value, shape, tension, selected = r.GetEnvelopePointEx(envelope, -1, index)
    if ok and selected then
      selected_count = selected_count + 1
      start_pos = math.min(start_pos, time)
      end_pos = math.max(end_pos, time)
    end
  end
  if selected_count == 0 then
    set_footer_message("Please select envelope points first")
    return false
  end
  if end_pos - start_pos <= 0.1 then
    set_footer_message("Selected points span is too small")
    return false
  end
  r.Undo_BeginBlock()
  r.InsertAutomationItem(envelope, -1, start_pos, end_pos - start_pos)
  r.UpdateArrange()
  r.Undo_EndBlock("Automation Item Manager: Convert selected points", -1)
  scan_automation_items()
  set_footer_message("Automation item created from " .. selected_count .. " envelope points")
  return true
end

local function apply_and_create_automation_item(app, item_data, target_envelope, target_time)
  local settings = module_settings(app)
  if not item_data or not item_data.points or #item_data.points == 0 then
    set_footer_message("No valid automation data")
    return false
  end
  local envelope = target_envelope or resolve_target_envelope()
  if not envelope then
    set_footer_message("Select an envelope lane first")
    return false
  end
  local env_info = get_envelope_info(envelope)
  local max_time = 0
  for _, point in ipairs(item_data.points) do
    if point.time > max_time then max_time = point.time end
  end
  local source_length = max_time * 0.5
  local insert_start, insert_end, has_time_selection
  if target_time then
    insert_start = target_time
    local time_start, time_end = r.GetSet_LoopTimeRange2(0, false, false, 0, 0, false)
    if settings.use_time_selection and time_end - time_start >= 0.01 then
      insert_end = target_time + time_end - time_start
      has_time_selection = true
    else
      insert_end = target_time + source_length
      has_time_selection = false
    end
  else
    insert_start, insert_end, has_time_selection = get_effective_range(settings, source_length)
  end
  local target_length = insert_end - insert_start
  local time_scale = has_time_selection and source_length > 0.001 and target_length / source_length or 1.0
  local final_length = has_time_selection and target_length or source_length
  local initial_count = r.CountAutomationItems(envelope)
  local original_points = {}
  for index = 0, r.CountEnvelopePoints(envelope) - 1 do
    local ok, time, value, shape, tension = r.GetEnvelopePointEx(envelope, -1, index)
    if ok and time >= insert_start and time <= insert_start + final_length then original_points[#original_points + 1] = { time = time, value = value, shape = shape, tension = tension } end
  end
  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)
  for index = r.CountEnvelopePoints(envelope) - 1, 0, -1 do
    local ok, time = r.GetEnvelopePointEx(envelope, -1, index)
    if ok and time >= insert_start and time <= insert_start + final_length then r.DeleteEnvelopePointEx(envelope, -1, index) end
  end
  for _, point in ipairs(item_data.points) do
    local absolute_time = insert_start + (point.time * 0.5) * time_scale
    local normalized_value = normalize_source_value(point.value, item_data.source_envelope_type)
    local final_value = to_env_value(normalized_value, env_info.conv, env_info.lo, env_info.hi, env_info.mode)
    r.InsertEnvelopePoint(envelope, absolute_time, final_value, point.shape or 0, point.tension or 0, true, true)
  end
  r.Envelope_SortPoints(envelope)
  local start_pos, end_pos = math.huge, 0
  local selected_count = 0
  for index = 0, r.CountEnvelopePoints(envelope) - 1 do
    local ok, time, value, shape, tension, selected = r.GetEnvelopePointEx(envelope, -1, index)
    if ok and selected then
      selected_count = selected_count + 1
      start_pos = math.min(start_pos, time)
      end_pos = math.max(end_pos, time)
    end
  end
  if selected_count > 0 and end_pos - start_pos > 0.01 then r.InsertAutomationItem(envelope, -1, start_pos, end_pos - start_pos) end
  local after_count = r.CountAutomationItems(envelope)
  if after_count > initial_count then
    local item_index = after_count - 1
    r.GetSetAutomationItemInfo(envelope, item_index, "D_LENGTH", final_length, true)
    r.GetSetAutomationItemInfo(envelope, item_index, "D_LOOPSRC", settings.enable_loop and 1 or 0, true)
    r.GetSetAutomationItemInfo(envelope, item_index, "D_PLAYRATE", 1.0, true)
  end
  for index = 0, r.CountAutomationItems(envelope) - 1 do
    r.GetSetAutomationItemInfo(envelope, index, "D_UISEL", 0, false)
  end
  for index = r.CountEnvelopePoints(envelope) - 1, 0, -1 do
    local ok, time = r.GetEnvelopePointEx(envelope, -1, index)
    if ok and (math.abs(time - insert_start) < 0.001 or math.abs(time - (insert_start + final_length)) < 0.001) then r.DeleteEnvelopePointEx(envelope, -1, index) end
  end
  for _, original in ipairs(original_points) do
    local exists = false
    for index = 0, r.CountEnvelopePoints(envelope) - 1 do
      local ok, time = r.GetEnvelopePointEx(envelope, -1, index)
      if ok and math.abs(time - original.time) < 0.001 then exists = true break end
    end
    if not exists then r.InsertEnvelopePoint(envelope, original.time, original.value, original.shape, original.tension, false, false) end
  end
  for index = 0, r.CountEnvelopePoints(envelope) - 1 do
    local ok, time, value, shape, tension = r.GetEnvelopePointEx(envelope, -1, index)
    if ok then r.SetEnvelopePointEx(envelope, -1, index, time, value, shape, tension, false, false) end
  end
  r.Envelope_SortPoints(envelope)
  r.PreventUIRefresh(-1)
  r.UpdateArrange()
  r.Undo_EndBlock("Automation Item Manager: Create automation item", -1)
  if settings.move_edit_cursor then r.SetEditCurPos(insert_start + final_length, true, false) end
  set_footer_message("Created automation item: " .. (item_data.name or "Unknown"))
  return true
end

local function export_envelope_points_to_file()
  local envelope = r.GetSelectedEnvelope(0)
  if not envelope then
    set_footer_message("Select an envelope first")
    return false
  end
  local point_count = r.CountEnvelopePoints(envelope)
  if point_count == 0 then
    set_footer_message("No envelope points found")
    return false
  end
  local env_info = get_envelope_info(envelope)
  local selected_start, selected_end = math.huge, -math.huge
  local has_selected = false
  local points = {}
  for index = 0, point_count - 1 do
    local ok, time, value, shape, tension, selected = r.GetEnvelopePointEx(envelope, -1, index)
    if ok then
      if selected then
        has_selected = true
        selected_start = math.min(selected_start, time)
        selected_end = math.max(selected_end, time)
      end
      points[#points + 1] = { time = time, value = value, shape = shape, tension = tension, selected = selected }
    end
  end
  local export_points = {}
  local offset = 0
  if has_selected and selected_end > selected_start then
    offset = selected_start
    for _, point in ipairs(points) do
      if point.selected then export_points[#export_points + 1] = { time = (point.time - offset) * 2, value = from_env_value(point.value, env_info.conv, env_info.lo, env_info.hi, env_info.mode), shape = point.shape, tension = point.tension } end
    end
  else
    local time_start, time_end = r.GetSet_LoopTimeRange2(0, false, false, 0, 0, false)
    local use_time_selection = time_end - time_start >= 0.01
    offset = use_time_selection and time_start or (points[1] and points[1].time or 0)
    for _, point in ipairs(points) do
      if not use_time_selection or point.time >= time_start and point.time <= time_end then export_points[#export_points + 1] = { time = (point.time - offset) * 2, value = from_env_value(point.value, env_info.conv, env_info.lo, env_info.hi, env_info.mode), shape = point.shape, tension = point.tension } end
    end
  end
  if #export_points == 0 then
    set_footer_message("No points to export")
    return false
  end
  if not ensure_automation_folder_exists() then return false end
  local total_time = export_points[#export_points].time
  local ok_input, name = r.GetUserInputs("Export as .ReaperAutoItem", 1, "Name:", "Exported_" .. os.date("%Y%m%d_%H%M%S"))
  if not ok_input or not name or name == "" then return false end
  local filename = name .. ".ReaperAutoItem"
  local filepath = path_join(state.automation_folder, filename)
  local existing = io.open(filepath, "r")
  if existing then
    existing:close()
    local overwrite = r.ShowMessageBox("File already exists:\n" .. filename .. "\n\nOverwrite?", M.title, 4)
    if overwrite ~= 6 then return false end
  end
  local file = io.open(filepath, "w")
  if not file then
    set_footer_message("Could not create file: " .. filepath)
    return false
  end
  file:write("SRCLEN " .. string.format("%.10f", total_time) .. "\n")
  for _, point in ipairs(export_points) do
    file:write(string.format("PPT %.10f %.10f %d %.10f\n", point.time, point.value, point.shape, point.tension))
  end
  file:close()
  scan_automation_items()
  set_footer_message("Exported: " .. filename .. " (" .. #export_points .. " points)")
  return true
end

local function delete_automation_item(item, index)
  if not item or not item.path then
    set_footer_message("Cannot delete: invalid item data")
    return
  end
  local ok = os.remove(item.path)
  if ok then
    table.remove(state.items, index)
    set_footer_message("Deleted: " .. (item.filename or ""))
  else
    set_footer_message("Failed to delete: " .. item.path)
  end
end

local function rename_automation_item(item, index)
  if not item or not item.path then
    set_footer_message("Cannot rename: invalid item data")
    return
  end
  local old_name = (item.filename or "Unknown"):gsub("%.ReaperAutoItem$", "")
  local ok_input, new_name = r.GetUserInputs("Rename Automation Item", 1, "New name:", old_name)
  if not ok_input or not new_name or new_name == "" or new_name == old_name then return end
  local new_filename = new_name .. ".ReaperAutoItem"
  local new_path = path_join(dirname(item.path), new_filename)
  local existing = io.open(new_path, "r")
  if existing then
    existing:close()
    set_footer_message("File already exists: " .. new_filename)
    return
  end
  local ok = os.rename(item.path, new_path)
  if ok then
    state.items[index].name = new_name
    state.items[index].filename = new_filename
    state.items[index].path = new_path
    sort_items()
    set_footer_message("Renamed to: " .. new_filename)
  else
    set_footer_message("Failed to rename file: " .. (item.filename or ""))
  end
end

local function copy_item_path(ctx, item)
  if not item or not item.path then
    set_footer_message("Cannot copy: invalid item path")
    return
  end
  if r.CF_SetClipboard then r.CF_SetClipboard(item.path) else r.ImGui_SetClipboardText(ctx, item.path) end
  set_footer_message("Path copied to clipboard")
end

local function send_to_morph_slot(app, item_data, slot)
  if not item_data or not item_data.points or #item_data.points == 0 then
    set_footer_message("No valid data for MORPH slot")
    return false
  end
  local envelope = resolve_target_envelope()
  if not envelope then
    set_footer_message("Select an envelope lane for MORPH")
    return false
  end
  local env_info = get_envelope_info(envelope)
  local insert_start = r.GetCursorPosition()
  local inserted_times = {}
  local points_added = 0
  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)
  for index = 0, r.CountEnvelopePoints(envelope) - 1 do
    local ok, time, value, shape, tension = r.GetEnvelopePointEx(envelope, -1, index)
    if ok then r.SetEnvelopePointEx(envelope, -1, index, time, value, shape, tension, false, false) end
  end
  for _, point in ipairs(item_data.points) do
    local absolute_time = insert_start + point.time * 0.5
    local normalized_value = normalize_source_value(point.value, item_data.source_envelope_type)
    local final_value = to_env_value(normalized_value, env_info.conv, env_info.lo, env_info.hi, env_info.mode)
    local ok = r.InsertEnvelopePoint(envelope, absolute_time, final_value, point.shape or 0, point.tension or 0, true, true)
    if ok then
      points_added = points_added + 1
      inserted_times[#inserted_times + 1] = absolute_time
    end
  end
  r.Envelope_SortPoints(envelope)
  r.PreventUIRefresh(-1)
  r.UpdateArrange()
  r.Undo_EndBlock("Automation Item Manager: MORPH prep", -1)
  state.morph_cleanup = { env = envelope, times = inserted_times, frames = 0 }
  set_footer_message("MORPH " .. slot .. ": " .. points_added .. " points, waiting for ReaCurve capture")
  return true
end

local function poll_morph_cleanup()
  local cleanup = state.morph_cleanup
  if not cleanup then return end
  if not r.ValidatePtr(cleanup.env, "TrackEnvelope*") then
    state.morph_cleanup = nil
    return
  end
  cleanup.frames = cleanup.frames + 1
  local any_found = false
  for _, target_time in ipairs(cleanup.times) do
    for index = 0, r.CountEnvelopePoints(cleanup.env) - 1 do
      local ok, time, value, shape, tension, selected = r.GetEnvelopePointEx(cleanup.env, -1, index)
      if ok and math.abs(time - target_time) < 0.0001 then
        any_found = true
        if not selected then r.SetEnvelopePointEx(cleanup.env, -1, index, time, value, shape, tension, true, true) end
        break
      end
    end
  end
  if any_found and cleanup.frames <= 100 then return end
  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)
  for _, target_time in ipairs(cleanup.times) do
    for index = r.CountEnvelopePoints(cleanup.env) - 1, 0, -1 do
      local ok, time = r.GetEnvelopePointEx(cleanup.env, -1, index)
      if ok and math.abs(time - target_time) < 0.0001 then
        r.DeleteEnvelopePointEx(cleanup.env, -1, index)
        break
      end
    end
  end
  r.Envelope_SortPoints(cleanup.env)
  r.PreventUIRefresh(-1)
  r.UpdateArrange()
  r.Undo_EndBlock("Automation Item Manager: MORPH cleanup", -1)
  if cleanup.frames > 100 then
    set_footer_message("MORPH timeout, temporary points removed")
  else
    set_footer_message("MORPH capture complete, temporary points removed")
  end
  state.morph_cleanup = nil
end

local function handle_drag_and_drop(app, ctx)
  if not state.is_dragging or not state.drag_item then return end
  if state.has_sws then
    r.BR_GetMouseCursorContext()
    local envelope = r.BR_GetMouseCursorContext_Envelope()
    local position = r.BR_GetMouseCursorContext_Position and r.BR_GetMouseCursorContext_Position() or nil
    if envelope and position then
      state.drag_hover_env = envelope
      state.drag_hover_pos = position
      local ok, name = r.GetEnvelopeName(envelope)
      state.drag_hover_name = ok and name or nil
    end
  end
  if r.ImGui_IsMouseReleased(ctx, r.ImGui_MouseButton_Left()) then
    local placed = false
    if state.has_sws then
      r.BR_GetMouseCursorContext()
      local envelope = r.BR_GetMouseCursorContext_Envelope() or state.drag_hover_env
      local position = (r.BR_GetMouseCursorContext_Position and r.BR_GetMouseCursorContext_Position()) or state.drag_hover_pos
      if envelope and position then
        apply_and_create_automation_item(app, state.drag_item, envelope, position)
        placed = true
      end
    end
    if not placed then set_footer_message(state.has_sws and "Drop on an envelope lane to place item" or "Drag&Drop needs SWS extension installed") end
    state.is_dragging = false
    state.drag_item = nil
    state.drag_hover_env = nil
    state.drag_hover_pos = nil
    state.drag_hover_name = nil
  end
end

local function draw_settings_popup(app, ctx, settings)
  if not r.ImGui_BeginPopup(ctx, "##aim_settings_menu") then return end
  local changed, value = r.ImGui_Checkbox(ctx, "Enable Loop", settings.enable_loop)
  if changed then
    settings.enable_loop = value
    save_module_settings(app)
  end
  changed, value = r.ImGui_Checkbox(ctx, "Move Edit Cursor", settings.move_edit_cursor)
  if changed then
    settings.move_edit_cursor = value
    save_module_settings(app)
  end
  changed, value = r.ImGui_Checkbox(ctx, "Lines Only", settings.show_lines_only)
  if changed then
    settings.show_lines_only = value
    save_module_settings(app)
  end
  changed, value = r.ImGui_Checkbox(ctx, "Use Time Selection", settings.use_time_selection)
  if changed then
    settings.use_time_selection = value
    save_module_settings(app)
  end
  changed, value = r.ImGui_Checkbox(ctx, "Show Tooltips", settings.show_tooltips)
  if changed then
    settings.show_tooltips = value
    save_module_settings(app)
  end
  r.ImGui_Separator(ctx)
  local flags = r.ImGui_ColorEditFlags_NoInputs()
  changed, value = r.ImGui_ColorEdit4(ctx, "Line", settings.curve_color, flags)
  if changed then
    settings.curve_color = value
    save_module_settings(app)
  end
  changed, value = r.ImGui_ColorEdit4(ctx, "Dots", settings.points_color, flags)
  if changed then
    settings.points_color = value
    save_module_settings(app)
  end
  r.ImGui_Separator(ctx)
  if r.ImGui_MenuItem(ctx, "About") then set_footer_message("Automation Item Manager v0.1.0") end
  r.ImGui_EndPopup(ctx)
end

local function draw_header(app, ctx, settings)
  local available_width = r.ImGui_GetContentRegionAvail(ctx)
  r.ImGui_SetCursorPosX(ctx, math.max(0, available_width - 28))
  if r.ImGui_Button(ctx, "...", 28, 22) then r.ImGui_OpenPopup(ctx, "##aim_settings_menu") end
  tooltip(ctx, app, settings, "Open Automation Item Manager settings")
  draw_settings_popup(app, ctx, settings)
  r.ImGui_Separator(ctx)
end

local function draw_item_context(app, ctx, settings, item, index)
  if not r.ImGui_BeginPopup(ctx, "##aim_context_" .. index) then return end
  if r.ImGui_MenuItem(ctx, "Insert as Points") then apply_parsed_data_as_envelope_points(app, item, nil, false) end
  r.ImGui_Separator(ctx)
  if r.ImGui_MenuItem(ctx, "MORPH Slot A") then send_to_morph_slot(app, item, "A") end
  if r.ImGui_MenuItem(ctx, "MORPH Slot B") then send_to_morph_slot(app, item, "B") end
  r.ImGui_Separator(ctx)
  if r.ImGui_MenuItem(ctx, "Delete") then delete_automation_item(item, index) end
  if r.ImGui_MenuItem(ctx, "Rename") then rename_automation_item(item, index) end
  r.ImGui_Separator(ctx)
  if r.ImGui_MenuItem(ctx, "Show in Explorer") then show_item_in_explorer(item) end
  if r.ImGui_MenuItem(ctx, "Copy Path") then copy_item_path(ctx, item) end
  r.ImGui_EndPopup(ctx)
end

local function draw_item_tooltip(app, ctx, settings, item)
  if not r.ImGui_IsItemHovered(ctx) or not settings.show_tooltips or not UI.tooltip_ready(ctx, app, item.name or "Unknown") then return end
  r.ImGui_BeginTooltip(ctx)
  r.ImGui_Text(ctx, item.name or "Unknown")
  r.ImGui_Text(ctx, "Click: insert as automation item")
  r.ImGui_Text(ctx, "Drag: drop on envelope in Arrange")
  r.ImGui_Text(ctx, "Right-click: more options")
  r.ImGui_Text(ctx, string.format("%d points, %.1fs", item.point_count or 0, (item.srclen or 0) * 0.5))
  r.ImGui_EndTooltip(ctx)
end

local function draw_items_grid(app, ctx, settings)
  if #state.items == 0 then
    r.ImGui_TextWrapped(ctx, "No automation items found.")
    r.ImGui_TextWrapped(ctx, "Create or save automation items in REAPER, then click Refresh.")
    return
  end
  local available_width = math.max(1, r.ImGui_GetContentRegionAvail(ctx) or state.preview_width)
  local gap = 8
  local columns = math.max(1, math.floor((available_width + gap) / (state.preview_width + gap)))
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_CellPadding(), 4, 4)
  local flags = r.ImGui_TableFlags_SizingStretchSame and r.ImGui_TableFlags_SizingStretchSame() or r.ImGui_TableFlags_None()
  if r.ImGui_BeginTable(ctx, "##aim_items", columns, flags) then
    for index, item in ipairs(state.items) do
      r.ImGui_TableNextColumn(ctx)
      local card_width = math.max(1, r.ImGui_GetContentRegionAvail(ctx) or state.preview_width)
      local x, y = r.ImGui_GetCursorScreenPos(ctx)
      draw_preview(ctx, settings, item.preview, x, y, card_width, state.preview_height)
      r.ImGui_SetCursorScreenPos(ctx, x, y)
      if r.ImGui_InvisibleButton(ctx, "##aim_item_" .. index, card_width, state.preview_height) then apply_and_create_automation_item(app, item) end
      if r.ImGui_IsItemActive(ctx) and r.ImGui_IsMouseDragging(ctx, r.ImGui_MouseButton_Left(), 5.0) then
        state.is_dragging = true
        state.drag_item = item
      end
      if r.ImGui_IsItemClicked(ctx, r.ImGui_MouseButton_Right()) then r.ImGui_OpenPopup(ctx, "##aim_context_" .. index) end
      draw_item_context(app, ctx, settings, item, index)
      draw_item_tooltip(app, ctx, settings, item)
      if state.is_dragging and state.drag_item == item then
        r.ImGui_BeginTooltip(ctx)
        r.ImGui_Text(ctx, state.drag_hover_name and ("Drop on " .. state.drag_hover_name) or "Drop on an envelope lane in Arrange")
        r.ImGui_EndTooltip(ctx)
      end
      r.ImGui_Text(ctx, item.name or "Unknown")
      if item.display_folder then r.ImGui_TextColored(ctx, Theme.colors.text_dim, item.display_folder) end
      r.ImGui_TextColored(ctx, Theme.colors.text_dim, string.format("%.1fs, %d pts", (item.srclen or 0) * 0.5, item.point_count or 0))
    end
    r.ImGui_EndTable(ctx)
  end
  r.ImGui_PopStyleVar(ctx, 1)
end

local function draw_controls_bar(app, ctx, settings)
  local footer_flags = r.ImGui_WindowFlags_NoScrollbar() | r.ImGui_WindowFlags_NoScrollWithMouse()
  if not r.ImGui_BeginChild(ctx, "##aim_controls", -1, state.controls_height, 0, footer_flags) then return end
  r.ImGui_Separator(ctx)
  local envelope = r.GetSelectedEnvelope(0)
  if envelope then
    local ok, name = r.GetEnvelopeName(envelope)
    local env_type = get_envelope_type(envelope)
    r.ImGui_Text(ctx, "Selected envelope: " .. (ok and name or "Unknown"))
    r.ImGui_SameLine(ctx)
    local color = env_type == "volume" and Theme.colors.warning or Theme.colors.accent
    r.ImGui_TextColored(ctx, color, "[" .. env_type .. "]")
  else
    r.ImGui_TextColored(ctx, Theme.colors.text_dim, "No envelope selected")
  end
  r.ImGui_Dummy(ctx, 1, 6)
  local available_width = math.max(1, r.ImGui_GetContentRegionAvail(ctx) or 1)
  local button_gap = 4
  local button_width = math.max(1, math.floor((available_width - button_gap * 4) / 5))
  if r.ImGui_Button(ctx, "Refresh", button_width, 22) then
    scan_automation_items()
    set_footer_message("Refreshed: " .. #state.items .. " items found")
  end
  tooltip(ctx, app, settings, "Rescan AutomationItems folder")
  r.ImGui_SameLine(ctx, 0, button_gap)
  if r.ImGui_Button(ctx, "Convert", button_width, 22) then convert_selected_envelope_points_to_automation_item() end
  tooltip(ctx, app, settings, "Convert selected envelope points to automation item")
  r.ImGui_SameLine(ctx, 0, button_gap)
  if r.ImGui_Button(ctx, "Save", button_width, 22) then
    r.Main_OnCommand(42092, 0)
    set_footer_message("Save automation item command executed")
  end
  tooltip(ctx, app, settings, "Save selected automation item to file")
  r.ImGui_SameLine(ctx, 0, button_gap)
  if r.ImGui_Button(ctx, "Export", button_width, 22) then export_envelope_points_to_file() end
  tooltip(ctx, app, settings, "Export envelope points to .ReaperAutoItem file")
  r.ImGui_SameLine(ctx, 0, button_gap)
  if r.ImGui_Button(ctx, "Folder", button_width, 22) then
    if ensure_automation_folder_exists() then open_path(state.automation_folder) end
  end
  tooltip(ctx, app, settings, "Open AutomationItems folder")
  local half_width = math.max(1, math.floor((available_width - button_gap) / 2))
  if r.ImGui_Button(ctx, "Insert New", half_width, 22) then
    r.Main_OnCommand(42082, 0)
    set_footer_message("Inserted automation item")
  end
  tooltip(ctx, app, settings, "Insert a new empty automation item")
  r.ImGui_SameLine(ctx, 0, button_gap)
  if r.ImGui_Button(ctx, "Edge points", half_width, 22) then
    r.Main_OnCommand(42209, 0)
    set_footer_message("Added edge points")
  end
  tooltip(ctx, app, settings, "Add edge points at automation item boundaries")
  if r.ImGui_Button(ctx, "Pool duplicate", half_width, 22) then
    r.Main_OnCommand(42085, 0)
    set_footer_message("Pooled duplicate created")
  end
  tooltip(ctx, app, settings, "Duplicate selected automation item as pooled copy")
  r.ImGui_SameLine(ctx, 0, button_gap)
  if r.ImGui_Button(ctx, "Unpool selected", half_width, 22) then
    r.Main_OnCommand(42084, 0)
    set_footer_message("Unpooled selected item")
  end
  tooltip(ctx, app, settings, "Make selected automation item independent")
  r.ImGui_EndChild(ctx)
end

local function info_line_text()
  local folder = state.automation_folder_exists and "AutomationItems folder ready" or "AutomationItems folder missing"
  local message = "Left-click inserts, right-click opens item actions"
  if state.footer_message ~= "" and r.time_precise() - state.footer_message_time < state.footer_message_duration then message = state.footer_message end
  return tostring(#state.items) .. " automation items | " .. folder .. " | " .. message
end

function M.init(app)
  module_settings(app)
  state.automation_folder_exists = automation_folder_exists()
  if state.automation_folder_exists then
    scan_automation_items()
  else
    set_footer_message("AutomationItems folder not found. Save an automation item first or create the folder.")
  end
  state.loaded = true
end

function M.update(app)
  poll_morph_cleanup()
end

function M.draw(app)
  local ctx = app.ctx
  local settings = module_settings(app)
  draw_header(app, ctx, settings)
  local available_width, available_height = r.ImGui_GetContentRegionAvail(ctx)
  local list_height = math.max(1, (available_height or 420) - state.controls_height - UI.info_line_height(ctx))
  if r.ImGui_BeginChild(ctx, "##aim_items_scroll", available_width or 0, list_height, 0) then
    draw_items_grid(app, ctx, settings)
    r.ImGui_EndChild(ctx)
  end
  draw_controls_bar(app, ctx, settings)
  UI.draw_info_line(ctx, info_line_text())
  handle_drag_and_drop(app, ctx)
end

return M