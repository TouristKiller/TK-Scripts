local r = reaper
local Theme = require("core.theme")
local UI = require("core.ui")

local M = {
  id = "color_studio",
  title = "Color Studio",
  icon = "CLR",
  version = "0.1.0"
}

local TARGETS = {
  { id = "auto", label = "Auto" },
  { id = "tracks", label = "Track" },
  { id = "items", label = "Item" },
  { id = "takes", label = "Take" },
  { id = "regions", label = "Region" },
  { id = "markers", label = "Marker" }
}

local COLOR_PAYLOAD_TYPE = "TK_COLOR_STUDIO_COLOR"
local AUTO_RULE_PAYLOAD_TYPE = "TK_COLOR_STUDIO_AUTO_RULE"
local ACTION_TRACK_DEFAULT_COLOR = 40359

local RANDOM_MODES = {
  { id = "same", label = "Same color" },
  { id = "per_target", label = "Per target" }
}

local PALETTE_COLOR_COUNTS = { 8, 16, 24 }

local AUTO_MATCHERS = {
  { id = "contains", label = "Contains" },
  { id = "starts", label = "Starts" },
  { id = "ends", label = "Ends" },
  { id = "exact", label = "Exact" }
}

local AUTO_TARGETS = {
  { id = "tracks", label = "Track", hint = "Track name" },
  { id = "markers", label = "Marker", hint = "Marker name" },
  { id = "regions", label = "Region", hint = "Region name" }
}

local PALETTES = {
  { name = "Workbench", colors = { 0x7AA2F7FF, 0x9ECE6AFF, 0xE0AF68FF, 0xF7768EFF, 0xBB9AF7FF, 0x2AC3DEFF, 0xC0CAF5FF, 0x565F89FF, 0xF8E58CFF, 0x00A896FF, 0xFF9E64FF, 0xB8E986FF, 0x4C6FFFFF, 0xE879F9FF, 0xEF4444FF, 0xA9B1D6FF } },
  { name = "Warm", colors = { 0xD00000FF, 0xF94144FF, 0xF3722CFF, 0xF8961EFF, 0xF9C74FFF, 0xFFB703FF, 0xE76F51FF, 0xB56576FF, 0x9D0208FF, 0xC1121FFF, 0x99582AFF, 0xBC6C25FF, 0xE09F3EFF, 0xFFB4A2FF, 0xC8553DFF, 0x6F1D1BFF } },
  { name = "Cool", colors = { 0x006D77FF, 0x118AB2FF, 0x00B4D8FF, 0x48CAE4FF, 0x4D96FFFF, 0x1D4ED8FF, 0x577590FF, 0x43AA8BFF, 0x06D6A0FF, 0x80ED99FF, 0x277DA1FF, 0x64DFDFFF, 0x5390D9FF, 0x6930C3FF, 0x4361EEFF, 0x8B5CF6FF } },
  { name = "Neutral", colors = { 0xF8F9FAFF, 0xE0AFA0FF, 0xBCCCDCFF, 0xADB5BDFF, 0x868E96FF, 0x6C757DFF, 0x495057FF, 0x212529FF, 0xD6CCC2FF, 0xB08968FF, 0x7F5539FF, 0x9C6644FF, 0xB7B7A4FF, 0xA5A58DFF, 0x52796FFF, 0x415A77FF } },
  { name = "Pastel", colors = { 0xFFADADFF, 0xFFD6A5FF, 0xFDFFB6FF, 0xCAFFBFFF, 0x9BF6FFFF, 0xA0C4FFFF, 0xBDB2FFFF, 0xFFC6FFFF, 0xB5EAD7FF, 0xFAD2E1FF, 0xFFDAC1FF, 0xE2F0CBFF, 0xCDB4DBFF, 0xBDE0FEFF, 0xD0F4DEFF, 0xABC4AAFF } },
  { name = "High Contrast", colors = { 0xFF006EFF, 0xFFBE0BFF, 0x00F5D4FF, 0x8338ECFF, 0x3A86FFFF, 0xFB5607FF, 0x06D6A0FF, 0xFFFFFFFF, 0xD00000FF, 0x70E000FF, 0x00BBF9FF, 0xF15BB5FF, 0xFEE440FF, 0x9B5DE5FF, 0xFF2E63FF, 0x111111FF } },
  { name = "Folders", colors = { 0x3A86FFFF, 0x06D6A0FF, 0xFFBE0BFF, 0xFB5607FF, 0x8338ECFF, 0xEF476FFF, 0x118AB2FF, 0x8AC926FF, 0x4361EEFF, 0x2A9D8FFF, 0xE9C46AFF, 0xF4A261FF, 0x7209B7FF, 0xD62828FF, 0x457B9DFF, 0x588157FF } }
}

local defaults = {
  view_mode = "manual",
  target_mode = "auto",
  palette_index = 1,
  random_mode = "per_target",
  recent_colors = {},
  recent_max = 20,
  active_color = 0x7AA2F7FF,
  gradient_start = 0x7AA2F7FF,
  gradient_end = 0xF7768EFF,
  palette_adjustments = {},
  palette_color_count = 16,
  palette_sorted = false,
  custom_palettes = {},
  custom_palette_name = "My Palette",
  selected_custom_palette = "",
  auto_rules = {},
  auto_rule_index = 1
}

local state = {}
local adjusted_palette_colors

local function default_auto_rule(index)
  return {
    enabled = true,
    name = "Rule " .. tostring(index or 1),
    target = "tracks",
    matcher = "contains",
    value = "",
    color_index = 1,
    color = 0x7AA2F7FF
  }
end

local function valid_auto_matcher(matcher)
  for _, entry in ipairs(AUTO_MATCHERS) do
    if entry.id == matcher then return true end
  end
  return false
end

local function valid_auto_target(target)
  for _, entry in ipairs(AUTO_TARGETS) do
    if entry.id == target then return true end
  end
  return false
end

local function copy_default(value)
  if type(value) ~= "table" then return value end
  local result = {}
  for key, child in pairs(value) do result[key] = copy_default(child) end
  return result
end

local function ensure_settings(app)
  app.settings.color_studio = app.settings.color_studio or {}
  local settings = app.settings.color_studio
  local changed = false
  for key, value in pairs(defaults) do
    if settings[key] == nil then
      settings[key] = copy_default(value)
      changed = true
    end
  end
  if settings.auto_target_migrated ~= true then
    if settings.target_mode == "tracks" then settings.target_mode = "auto" end
    settings.auto_target_migrated = true
    changed = true
  end
  local valid_target = false
  for _, target in ipairs(TARGETS) do
    if settings.target_mode == target.id then valid_target = true; break end
  end
  if not valid_target then
    settings.target_mode = "auto"
    changed = true
  end
  settings.palette_index = math.max(1, math.min(#PALETTES, tonumber(settings.palette_index) or 1))
  local valid_palette_count = false
  settings.palette_color_count = tonumber(settings.palette_color_count) or defaults.palette_color_count
  for _, count in ipairs(PALETTE_COLOR_COUNTS) do
    if settings.palette_color_count == count then valid_palette_count = true; break end
  end
  if not valid_palette_count then
    settings.palette_color_count = defaults.palette_color_count
    changed = true
  end
  if type(settings.palette_sorted) ~= "boolean" then
    settings.palette_sorted = defaults.palette_sorted
    changed = true
  end
  settings.recent_colors = type(settings.recent_colors) == "table" and settings.recent_colors or {}
  settings.palette_adjustments = type(settings.palette_adjustments) == "table" and settings.palette_adjustments or {}
  settings.custom_palettes = type(settings.custom_palettes) == "table" and settings.custom_palettes or {}
  settings.custom_palette_name = tostring(settings.custom_palette_name or defaults.custom_palette_name)
  settings.selected_custom_palette = tostring(settings.selected_custom_palette or "")
  if settings.view_mode ~= "auto" then settings.view_mode = "manual" end
  settings.auto_rules = type(settings.auto_rules) == "table" and settings.auto_rules or {}
  if #settings.auto_rules == 0 then
    settings.auto_rules[1] = default_auto_rule(1)
    changed = true
  end
  for index, rule in ipairs(settings.auto_rules) do
    if type(rule) ~= "table" then
      settings.auto_rules[index] = default_auto_rule(index)
      changed = true
    else
      rule.enabled = rule.enabled ~= false
      rule.name = tostring(rule.name or ("Rule " .. tostring(index)))
      rule.target = valid_auto_target(rule.target) and rule.target or "tracks"
      rule.matcher = valid_auto_matcher(rule.matcher) and rule.matcher or "contains"
      rule.value = tostring(rule.value or "")
      rule.color_index = math.max(1, tonumber(rule.color_index) or 1)
      if tonumber(rule.color) then
        rule.color = tonumber(rule.color)
      else
        local colors = adjusted_palette_colors(settings)
        rule.color = colors[math.max(1, math.min(#colors, rule.color_index))] or defaults.active_color
        changed = true
      end
    end
  end
  settings.auto_rule_index = math.max(1, math.min(#settings.auto_rules, tonumber(settings.auto_rule_index) or 1))
  if changed and app.save_settings then app.save_settings() end
  return settings
end

local function valid_track(track)
  return track and (not r.ValidatePtr2 or r.ValidatePtr2(0, track, "MediaTrack*"))
end

local function valid_item(item)
  return item and (not r.ValidatePtr2 or r.ValidatePtr2(0, item, "MediaItem*"))
end

local function valid_take(take)
  return take and (not r.ValidatePtr2 or r.ValidatePtr2(0, take, "MediaItem_Take*"))
end

local function clamp(value, min_value, max_value)
  value = tonumber(value) or 0
  if value < min_value then return min_value end
  if value > max_value then return max_value end
  return value
end

local function rgba(color)
  color = tonumber(color) or 0
  return (color >> 24) & 0xFF, (color >> 16) & 0xFF, (color >> 8) & 0xFF, color & 0xFF
end

local function pack_rgba(red, green, blue, alpha)
  red = math.floor(clamp(red, 0, 255) + 0.5)
  green = math.floor(clamp(green, 0, 255) + 0.5)
  blue = math.floor(clamp(blue, 0, 255) + 0.5)
  alpha = math.floor(clamp(alpha or 255, 0, 255) + 0.5)
  return (red << 24) | (green << 16) | (blue << 8) | alpha
end

local function u32_to_native(color, custom_flag)
  local red, green, blue = rgba(color)
  if not r.ColorToNative then return 0 end
  local native = r.ColorToNative(red, green, blue) or 0
  return custom_flag and (native | 0x1000000) or native
end

local function native_to_u32(native, alpha)
  native = tonumber(native) or 0
  if native == 0 then return nil end
  native = native & 0xFFFFFF
  alpha = alpha or 0xFF
  if r.ColorFromNative then
    local ok, red, green, blue = pcall(r.ColorFromNative, native)
    if ok and red and green and blue then return pack_rgba(red, green, blue, alpha) end
  end
  local red = native & 0xFF
  local green = (native >> 8) & 0xFF
  local blue = (native >> 16) & 0xFF
  return pack_rgba(red, green, blue, alpha)
end

local function color_hex(color)
  local red, green, blue = rgba(color)
  return string.format("#%02X%02X%02X", red, green, blue)
end

local function trim_text(value)
  return tostring(value or ""):match("^%s*(.-)%s*$") or ""
end

local function color_matches(left, right)
  if not left or not right then return false end
  local left_red, left_green, left_blue = rgba(left)
  local right_red, right_green, right_blue = rgba(right)
  return math.abs(left_red - right_red) <= 1 and math.abs(left_green - right_green) <= 1 and math.abs(left_blue - right_blue) <= 1
end

local function adjust_color(color, amount)
  local red, green, blue, alpha = rgba(color)
  local function adjust(channel)
    if amount >= 0 then return channel + (255 - channel) * amount end
    return channel * (1 + amount)
  end
  return pack_rgba(adjust(red), adjust(green), adjust(blue), alpha)
end

local function adjust_saturation(color, amount)
  local red, green, blue, alpha = rgba(color)
  local gray = red * 0.299 + green * 0.587 + blue * 0.114
  local factor = amount >= 0 and (1 + amount) or (1 + amount)
  return pack_rgba(gray + (red - gray) * factor, gray + (green - gray) * factor, gray + (blue - gray) * factor, alpha)
end

local function color_sort_values(color)
  local red, green, blue = rgba(color)
  red, green, blue = red / 255, green / 255, blue / 255
  local max_value = math.max(red, green, blue)
  local min_value = math.min(red, green, blue)
  local delta = max_value - min_value
  local hue = 0
  if delta > 0 then
    if max_value == red then
      hue = ((green - blue) / delta) % 6
    elseif max_value == green then
      hue = ((blue - red) / delta) + 2
    else
      hue = ((red - green) / delta) + 4
    end
    hue = hue / 6
  end
  local saturation = max_value == 0 and 0 or delta / max_value
  local luma = red * 0.299 + green * 0.587 + blue * 0.114
  return saturation < 0.08 and 2 or 1, hue, luma
end

local function sort_colors_by_hue(colors)
  table.sort(colors, function(left, right)
    local left_group, left_hue, left_luma = color_sort_values(left)
    local right_group, right_hue, right_luma = color_sort_values(right)
    if left_group ~= right_group then return left_group < right_group end
    if math.abs(left_hue - right_hue) > 0.01 then return left_hue < right_hue end
    return left_luma < right_luma
  end)
  return colors
end

local function interpolate_color(left, right, amount)
  local lr, lg, lb, la = rgba(left)
  local rr, rg, rb, ra = rgba(right)
  amount = clamp(amount, 0, 1)
  return pack_rgba(lr + (rr - lr) * amount, lg + (rg - lg) * amount, lb + (rb - lb) * amount, la + (ra - la) * amount)
end

local function selected_tracks()
  local tracks = {}
  local count = r.CountSelectedTracks(0) or 0
  for index = 0, count - 1 do
    local track = r.GetSelectedTrack(0, index)
    if valid_track(track) then tracks[#tracks + 1] = track end
  end
  return tracks
end

local function selected_items()
  local items = {}
  local count = r.CountSelectedMediaItems(0) or 0
  for index = 0, count - 1 do
    local item = r.GetSelectedMediaItem(0, index)
    if valid_item(item) then items[#items + 1] = item end
  end
  return items
end

local function selected_takes_from_items(items)
  local takes = {}
  for _, item in ipairs(items or {}) do
    local take = r.GetActiveTake(item)
    if valid_take(take) then takes[#takes + 1] = take end
  end
  return takes
end

local function marker_region_selected(enum_index)
  if not r.GetRegionOrMarker or not r.GetRegionOrMarkerInfo_Value then return false end
  local marker = r.GetRegionOrMarker(0, enum_index, "")
  if not marker then return false end
  local ok, selected = pcall(r.GetRegionOrMarkerInfo_Value, 0, marker, "B_UISEL")
  return ok and selected == 1
end

local function selected_marker_region_targets(include_markers, include_regions)
  local targets = {}
  local _, marker_count, region_count = r.CountProjectMarkers(0)
  local total = (marker_count or 0) + (region_count or 0)
  for index = 0, total - 1 do
    local ok, is_region, pos, region_end, name, number, color = r.EnumProjectMarkers3(0, index)
    if ok then
      local include = (is_region and include_regions) or ((not is_region) and include_markers)
      if include and marker_region_selected(index) then
        targets[#targets + 1] = { index = number, is_region = is_region, pos = pos, region_end = region_end, name = name or "", color = color or 0 }
      end
    end
  end
  return targets
end

local function marker_region_targets(include_markers, include_regions)
  local targets = {}
  local selected = {}
  local time_start, time_end = r.GetSet_LoopTimeRange(false, false, 0, 0, false)
  local has_time_selection = time_end and time_start and time_end > time_start
  local cursor = r.GetCursorPosition and r.GetCursorPosition() or 0
  local _, marker_count, region_count = r.CountProjectMarkers(0)
  local total = (marker_count or 0) + (region_count or 0)
  for index = 0, total - 1 do
    local ok, is_region, pos, region_end, name, number, color = r.EnumProjectMarkers3(0, index)
    if ok then
      local include = (is_region and include_regions) or ((not is_region) and include_markers)
      if include then
        local target = { index = number, is_region = is_region, pos = pos, region_end = region_end, name = name or "", color = color or 0 }
        if marker_region_selected(index) then selected[#selected + 1] = target end
        local matched = false
        if has_time_selection then
          matched = is_region and region_end > time_start and pos < time_end or ((not is_region) and pos >= time_start and pos <= time_end)
        else
          matched = is_region and pos <= cursor and cursor <= region_end or ((not is_region) and math.abs(pos - cursor) < 0.000001)
        end
        if matched then targets[#targets + 1] = target end
      end
    end
  end
  if #selected > 0 then return selected end
  return targets
end

local function all_marker_region_targets(include_markers, include_regions)
  local targets = {}
  local _, marker_count, region_count = r.CountProjectMarkers(0)
  local total = (marker_count or 0) + (region_count or 0)
  for index = 0, total - 1 do
    local ok, is_region, pos, region_end, name, number, color = r.EnumProjectMarkers3(0, index)
    if ok then
      local include = (is_region and include_regions) or ((not is_region) and include_markers)
      if include then targets[#targets + 1] = { index = number, is_region = is_region, pos = pos, region_end = region_end, name = name or "", color = color or 0 } end
    end
  end
  return targets
end

local function target_signature(targets, prefix)
  local parts = {}
  for _, target in ipairs(targets or {}) do
    if prefix == "t" then
      parts[#parts + 1] = prefix .. ":" .. tostring(target)
    elseif prefix == "i" then
      parts[#parts + 1] = prefix .. ":" .. tostring(target)
    elseif prefix == "m" or prefix == "r" then
      parts[#parts + 1] = prefix .. ":" .. tostring(target.index)
    end
  end
  return table.concat(parts, "|")
end

local function update_auto_target_from_mouse_click()
  if not r.JS_Mouse_GetState or not r.BR_GetMouseCursorContext then return end
  local mouse_down = (r.JS_Mouse_GetState(1) & 1) == 1
  if mouse_down and not state.auto_mouse_down then
    local window = r.BR_GetMouseCursorContext()
    if window == "arrange" or window == "tcp" then
      local item = r.BR_GetMouseCursorContext_Item and r.BR_GetMouseCursorContext_Item() or nil
      if valid_item(item) then
        state.auto_target_kind = "items"
      else
        local track = r.BR_GetMouseCursorContext_Track and r.BR_GetMouseCursorContext_Track() or nil
        if valid_track(track) then state.auto_target_kind = "tracks" end
      end
    end
  end
  state.auto_mouse_down = mouse_down
end

local function resolve_auto_target_kind(tracks, items, markers, regions)
  update_auto_target_from_mouse_click()
  local signatures = {
    tracks = target_signature(tracks, "t"),
    items = target_signature(items, "i"),
    markers = target_signature(markers, "m"),
    regions = target_signature(regions, "r")
  }
  local previous = state.auto_target_signatures
  local kind = state.auto_target_kind
  if not previous then
    if #items > 0 then kind = "items"
    elseif #tracks > 0 then kind = "tracks"
    elseif #markers > 0 then kind = "markers"
    elseif #regions > 0 then kind = "regions"
    end
  else
    if signatures.items ~= previous.items then
      kind = #items > 0 and "items" or (#tracks > 0 and "tracks" or nil)
    end
    if signatures.markers ~= previous.markers and #markers > 0 then kind = "markers" end
    if signatures.regions ~= previous.regions and #regions > 0 then kind = "regions" end
    if signatures.tracks ~= previous.tracks and #tracks > 0 and signatures.items == previous.items then kind = "tracks" end
  end
  state.auto_target_signatures = signatures
  state.auto_target_kind = kind
  return kind
end

local function selected_targets(settings)
  local mode = settings.target_mode
  local tracks = selected_tracks()
  local items = selected_items()
  local takes = selected_takes_from_items(items)
  if mode == "auto" then
    local selected_markers = selected_marker_region_targets(true, false)
    local selected_regions = selected_marker_region_targets(false, true)
    local kind = resolve_auto_target_kind(tracks, items, selected_markers, selected_regions)
    if kind == "items" and #items > 0 then return {}, items, {}, {}, {} end
    if kind == "tracks" and #tracks > 0 then return tracks, {}, {}, {}, {} end
    if kind == "markers" and #selected_markers > 0 then return {}, {}, {}, selected_markers, {} end
    if kind == "regions" and #selected_regions > 0 then return {}, {}, {}, {}, selected_regions end
    if #items > 0 then return {}, items, {}, {}, {} end
    if #tracks > 0 then return tracks, {}, {}, {}, {} end
    if #selected_markers > 0 then return {}, {}, {}, selected_markers, {} end
    if #selected_regions > 0 then return {}, {}, {}, {}, selected_regions end
    local markers = marker_region_targets(true, false)
    if #markers > 0 then return {}, {}, {}, markers, {} end
    local regions = marker_region_targets(false, true)
    if #regions > 0 then return {}, {}, {}, {}, regions end
    return tracks, {}, {}, {}, {}
  end
  if mode == "tracks" then return tracks, items, {}, {}, {} end
  if mode == "items" then return {}, items, {}, {}, {} end
  if mode == "takes" then return {}, {}, takes, {}, {} end
  if mode == "regions" then return {}, {}, {}, {}, marker_region_targets(false, true) end
  if mode == "markers" then return {}, {}, {}, marker_region_targets(true, false), {} end
  return tracks, items, {}, {}, {}
end

local function target_total(tracks, items, takes, markers, regions)
  return #(tracks or {}) + #(items or {}) + #(takes or {}) + #(markers or {}) + #(regions or {})
end

local function target_label(settings, selected_item_count)
  if settings.target_mode ~= "auto" then
    for _, target in ipairs(TARGETS) do
      if target.id == settings.target_mode then return target.label end
    end
  end
  if state.auto_target_kind == "items" and (selected_item_count or 0) > 0 then return "Auto: Item" end
  if state.auto_target_kind == "tracks" then return "Auto: Track" end
  if state.auto_target_kind == "markers" then return "Auto: Marker" end
  if state.auto_target_kind == "regions" then return "Auto: Region" end
  if (selected_item_count or 0) > 0 then return "Auto: Item" end
  local markers = marker_region_targets(true, false)
  if #markers > 0 then return "Auto: Marker" end
  local regions = marker_region_targets(false, true)
  if #regions > 0 then return "Auto: Region" end
  return "Auto: Track"
end

local function cycle_target_mode(app, settings)
  local current_index = 1
  for index, target in ipairs(TARGETS) do
    if target.id == settings.target_mode then current_index = index; break end
  end
  local next_target = TARGETS[(current_index % #TARGETS) + 1]
  settings.target_mode = next_target.id
  if app.save_settings then app.save_settings() end
  app.status = "Mode: " .. next_target.label
end

local function first_item_color(item)
  if not valid_item(item) then return nil end
  local native = 0
  if r.GetDisplayedMediaItemColor then native = r.GetDisplayedMediaItemColor(item) or 0 end
  if native == 0 then native = r.GetMediaItemInfo_Value(item, "I_CUSTOMCOLOR") or 0 end
  return native_to_u32(native)
end

local function track_color(track)
  if not valid_track(track) then return nil end
  return native_to_u32(r.GetTrackColor(track) or 0)
end

local function set_track_color(track, color)
  if valid_track(track) then r.SetTrackColor(track, color and u32_to_native(color, false) or 0) end
end

local function set_item_color(item, color)
  if valid_item(item) then r.SetMediaItemInfo_Value(item, "I_CUSTOMCOLOR", color and u32_to_native(color, true) or 0) end
end

local function take_color(take)
  if not valid_take(take) or not r.GetMediaItemTakeInfo_Value then return nil end
  return native_to_u32(r.GetMediaItemTakeInfo_Value(take, "I_CUSTOMCOLOR") or 0)
end

local function set_take_color(take, color)
  if valid_take(take) and r.SetMediaItemTakeInfo_Value then r.SetMediaItemTakeInfo_Value(take, "I_CUSTOMCOLOR", color and u32_to_native(color, true) or 0) end
end

local function marker_region_color(target)
  return target and native_to_u32(target.color or 0) or nil
end

local function current_target_color(settings)
  local tracks, items, takes, markers, regions = selected_targets(settings)
  if #tracks > 0 then return track_color(tracks[1]) end
  if #items > 0 then return first_item_color(items[1]) end
  if #takes > 0 then return take_color(takes[1]) end
  if #markers > 0 then return marker_region_color(markers[1]) end
  if #regions > 0 then return marker_region_color(regions[1]) end
  return nil
end

local function set_marker_region_color(target, color)
  if not target then return end
  local native = color and u32_to_native(color, true) or 0
  if r.SetProjectMarker4 then
    r.SetProjectMarker4(0, target.index, target.is_region, target.pos, target.region_end or 0, target.name or "", native, 0)
  elseif r.SetProjectMarker3 then
    r.SetProjectMarker3(0, target.index, target.is_region, target.pos, target.region_end or 0, target.name or "", native)
  end
  target.color = native
end

local function default_item_color(item)
  if not valid_item(item) then return end
  r.SetMediaItemInfo_Value(item, "I_CUSTOMCOLOR", 0)
  local take_count = r.CountTakes and (r.CountTakes(item) or 0) or 0
  for take_index = 0, take_count - 1 do
    local take = r.GetTake(item, take_index)
    if take and r.SetMediaItemTakeInfo_Value then r.SetMediaItemTakeInfo_Value(take, "I_CUSTOMCOLOR", 0) end
  end
end

local function with_undo(label, callback)
  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)
  local ok, result = pcall(callback)
  r.PreventUIRefresh(-1)
  if r.TrackList_AdjustWindows then r.TrackList_AdjustWindows(false) end
  r.UpdateArrange()
  r.Undo_EndBlock(label, -1)
  if not ok then error(result) end
  return result
end

local function add_recent_color(app, settings, color)
  color = tonumber(color) or settings.active_color
  local recents = settings.recent_colors
  for index = #recents, 1, -1 do
    if recents[index] == color then table.remove(recents, index) end
  end
  table.insert(recents, 1, color)
  local max_count = math.max(1, tonumber(settings.recent_max) or defaults.recent_max)
  while #recents > max_count do table.remove(recents) end
  if app.save_settings then app.save_settings() end
end

local function set_active_color(app, settings, color, remember)
  if not color then return end
  settings.active_color = color
  if remember then add_recent_color(app, settings, color) elseif app.save_settings then app.save_settings() end
end

local function is_builtin_palette_name(name)
  local normalized = trim_text(name):lower()
  for _, pal in ipairs(PALETTES) do
    if pal.name:lower() == normalized then return true end
  end
  return false
end

local function custom_palette_names(settings)
  local names = {}
  for name, pal in pairs(settings.custom_palettes or {}) do
    if type(pal) == "table" and type(pal.colors) == "table" and #pal.colors > 0 then names[#names + 1] = name end
  end
  table.sort(names)
  return names
end

local function palette(settings)
  local custom_name = trim_text(settings.selected_custom_palette or "")
  local custom = custom_name ~= "" and settings.custom_palettes and settings.custom_palettes[custom_name] or nil
  if type(custom) == "table" and type(custom.colors) == "table" and #custom.colors > 0 then
    return { name = custom_name, colors = custom.colors, custom = true }
  end
  settings.selected_custom_palette = ""
  return PALETTES[math.max(1, math.min(#PALETTES, tonumber(settings.palette_index) or 1))] or PALETTES[1]
end

local function palette_adjustment(settings)
  local pal = palette(settings)
  settings.palette_adjustments[pal.name] = settings.palette_adjustments[pal.name] or { brightness = 0, saturation = 0 }
  local adjustment = settings.palette_adjustments[pal.name]
  adjustment.brightness = tonumber(adjustment.brightness) or 0
  adjustment.saturation = tonumber(adjustment.saturation) or 0
  return adjustment
end

local function apply_palette_adjustment(color, adjustment)
  local saturation = clamp((adjustment.saturation or 0) / 100, -1, 1)
  local brightness = clamp((adjustment.brightness or 0) / 100, -1, 1)
  return adjust_color(adjust_saturation(color, saturation), brightness)
end

function adjusted_palette_colors(settings)
  local pal = palette(settings)
  local adjustment = palette_adjustment(settings)
  local count = tonumber(settings.palette_color_count) or defaults.palette_color_count
  local colors = {}
  for index = 1, count do
    local base_index = ((index - 1) % #pal.colors) + 1
    local color = pal.colors[base_index]
    if index > #pal.colors then color = adjust_color(color, 0.22) end
    colors[index] = apply_palette_adjustment(color, adjustment)
  end
  if settings.palette_sorted then sort_colors_by_hue(colors) end
  return colors
end

local function palette_edit_signature(settings)
  local pal = palette(settings)
  local adjustment = palette_adjustment(settings)
  return table.concat({ pal.name, tostring(settings.palette_color_count), tostring(settings.palette_sorted), tostring(adjustment.brightness or 0), tostring(adjustment.saturation or 0) }, "|")
end

local function editable_palette_colors(settings)
  local signature = palette_edit_signature(settings)
  if state.palette_edit_signature ~= signature or type(state.palette_edit_colors) ~= "table" then
    state.palette_edit_signature = signature
    state.palette_edit_colors = adjusted_palette_colors(settings)
  end
  return state.palette_edit_colors
end

local function reset_palette_edit_buffer()
  state.palette_edit_signature = nil
  state.palette_edit_colors = nil
end

local function copy_palette_colors(colors)
  local copy = {}
  for _, color in ipairs(colors or {}) do
    if tonumber(color) then copy[#copy + 1] = tonumber(color) end
  end
  return copy
end

local function save_custom_palette(app, settings)
  local name = trim_text(settings.custom_palette_name or "")
  if name == "" then app.status = "Palette name required"; return end
  if is_builtin_palette_name(name) then app.status = "Built-in palette names cannot be overwritten"; return end
  local colors = copy_palette_colors(editable_palette_colors(settings))
  if #colors == 0 then app.status = "No palette colors to save"; return end
  local existed = settings.custom_palettes and settings.custom_palettes[name] ~= nil
  settings.custom_palettes = settings.custom_palettes or {}
  settings.custom_palettes[name] = { colors = colors }
  settings.custom_palette_name = name
  settings.selected_custom_palette = name
  settings.palette_adjustments[name] = { brightness = 0, saturation = 0 }
  reset_palette_edit_buffer()
  if app.save_settings then app.save_settings() end
  app.status = (existed and "Updated Color Studio theme: " or "Saved Color Studio theme: ") .. name
end

local function delete_custom_palette(app, settings)
  local name = trim_text(settings.custom_palette_name or "")
  if name == "" then app.status = "Palette name required"; return end
  if is_builtin_palette_name(name) then app.status = "Built-in palettes cannot be deleted"; return end
  if not (settings.custom_palettes and settings.custom_palettes[name]) then app.status = "Color Studio theme not found: " .. name; return end
  settings.custom_palettes[name] = nil
  settings.palette_adjustments[name] = nil
  settings.custom_palette_name = name
  if settings.selected_custom_palette == name then settings.selected_custom_palette = "" end
  reset_palette_edit_buffer()
  if app.save_settings then app.save_settings() end
  app.status = "Deleted Color Studio theme: " .. name
end

local function random_palette_color(settings)
  local colors = editable_palette_colors(settings)
  return colors[math.random(1, #colors)] or settings.active_color
end

local function apply_color(app, settings, color)
  local tracks, items, takes, markers, regions = selected_targets(settings)
  local total = target_total(tracks, items, takes, markers, regions)
  if total == 0 then app.status = "No selected targets"; return end
  with_undo("Color Studio: Apply", function()
    for _, track in ipairs(tracks) do set_track_color(track, color) end
    for _, item in ipairs(items) do set_item_color(item, color) end
    for _, take in ipairs(takes) do set_take_color(take, color) end
    for _, marker in ipairs(markers) do set_marker_region_color(marker, color) end
    for _, region in ipairs(regions) do set_marker_region_color(region, color) end
  end)
  add_recent_color(app, settings, color)
  app.status = "Applied " .. color_hex(color) .. " to " .. tostring(total) .. " target(s)"
end

local function select_color(app, settings, color, remember, apply_now)
  set_active_color(app, settings, color, remember)
  if apply_now then apply_color(app, settings, color) end
end

local function default_color(app, settings)
  local tracks, items, takes, markers, regions = selected_targets(settings)
  local total = target_total(tracks, items, takes, markers, regions)
  if total == 0 then app.status = "No selected targets"; return end
  with_undo("Color Studio: Default", function()
    if #tracks > 0 then r.Main_OnCommand(ACTION_TRACK_DEFAULT_COLOR, 0) end
    for _, item in ipairs(items) do default_item_color(item) end
    for _, take in ipairs(takes) do set_take_color(take, nil) end
    for _, marker in ipairs(markers) do set_marker_region_color(marker, nil) end
    for _, region in ipairs(regions) do set_marker_region_color(region, nil) end
  end)
  if #items > 0 and total == #items then
    app.status = "Reset " .. tostring(#items) .. " item(s) to track color"
  else
    app.status = "Reset " .. tostring(total) .. " target(s) to default color"
  end
end

local function pick_color(app, settings)
  local color = nil
  local tracks = selected_tracks()
  local items = selected_items()
  local takes = selected_takes_from_items(items)
  if settings.target_mode == "tracks" and #tracks > 0 then color = track_color(tracks[1]) end
  if settings.target_mode == "takes" and #takes > 0 then color = take_color(takes[1]) end
  if settings.target_mode == "markers" then
    local markers = marker_region_targets(true, false)
    if #markers > 0 then color = marker_region_color(markers[1]) end
  end
  if settings.target_mode == "regions" then
    local regions = marker_region_targets(false, true)
    if #regions > 0 then color = marker_region_color(regions[1]) end
  end
  if not color and #items > 0 then color = first_item_color(items[1]) end
  if not color and #takes > 0 then color = take_color(takes[1]) end
  if not color and #tracks > 0 then color = track_color(tracks[1]) end
  if not color then app.status = "No custom color to pick"; return end
  set_active_color(app, settings, color, true)
  app.status = "Picked " .. color_hex(color)
end

local function apply_random(app, settings)
  local tracks, items, takes, markers, regions = selected_targets(settings)
  local total = target_total(tracks, items, takes, markers, regions)
  if total == 0 then app.status = "No selected targets"; return end
  local shared = random_palette_color(settings)
  with_undo("Color Studio: Random", function()
    for _, track in ipairs(tracks) do set_track_color(track, settings.random_mode == "same" and shared or random_palette_color(settings)) end
    for _, item in ipairs(items) do set_item_color(item, settings.random_mode == "same" and shared or random_palette_color(settings)) end
    for _, take in ipairs(takes) do set_take_color(take, settings.random_mode == "same" and shared or random_palette_color(settings)) end
    for _, marker in ipairs(markers) do set_marker_region_color(marker, settings.random_mode == "same" and shared or random_palette_color(settings)) end
    for _, region in ipairs(regions) do set_marker_region_color(region, settings.random_mode == "same" and shared or random_palette_color(settings)) end
  end)
  add_recent_color(app, settings, shared)
  app.status = "Randomized " .. tostring(total) .. " target(s)"
end

local function apply_gradient_colors(app, settings, start_color, end_color)
  local tracks, items, takes, markers, regions = selected_targets(settings)
  local total = target_total(tracks, items, takes, markers, regions)
  if total == 0 then app.status = "No selected targets"; return end
  with_undo("Color Studio: Gradient", function()
    local index = 0
    for _, track in ipairs(tracks) do
      index = index + 1
      set_track_color(track, total > 1 and interpolate_color(start_color, end_color, (index - 1) / (total - 1)) or start_color)
    end
    for _, item in ipairs(items) do
      index = index + 1
      set_item_color(item, total > 1 and interpolate_color(start_color, end_color, (index - 1) / (total - 1)) or start_color)
    end
    for _, take in ipairs(takes) do
      index = index + 1
      set_take_color(take, total > 1 and interpolate_color(start_color, end_color, (index - 1) / (total - 1)) or start_color)
    end
    for _, marker in ipairs(markers) do
      index = index + 1
      set_marker_region_color(marker, total > 1 and interpolate_color(start_color, end_color, (index - 1) / (total - 1)) or start_color)
    end
    for _, region in ipairs(regions) do
      index = index + 1
      set_marker_region_color(region, total > 1 and interpolate_color(start_color, end_color, (index - 1) / (total - 1)) or start_color)
    end
  end)
  settings.gradient_start = start_color
  settings.gradient_end = end_color
  add_recent_color(app, settings, start_color)
  add_recent_color(app, settings, end_color)
  app.status = "Applied gradient to " .. tostring(total) .. " target(s)"
end

local function apply_gradient(app, settings)
  apply_gradient_colors(app, settings, settings.gradient_start, settings.gradient_end)
end

local function selected_adjust_signature(tracks, items, takes, markers, regions)
  local parts = {}
  for _, track in ipairs(tracks) do parts[#parts + 1] = "t:" .. tostring(track) end
  for _, item in ipairs(items) do parts[#parts + 1] = "i:" .. tostring(item) end
  for _, take in ipairs(takes) do parts[#parts + 1] = "k:" .. tostring(take) end
  for _, marker in ipairs(markers) do parts[#parts + 1] = "m:" .. tostring(marker.index) end
  for _, region in ipairs(regions) do parts[#parts + 1] = "r:" .. tostring(region.index) end
  return table.concat(parts, "|")
end

local function capture_selected_adjust_base(settings, tracks, items, takes, markers, regions, signature)
  local base = { signature = signature, tracks = {}, items = {}, takes = {}, markers = {}, regions = {} }
  for _, track in ipairs(tracks) do base.tracks[#base.tracks + 1] = { target = track, color = track_color(track) or settings.active_color } end
  for _, item in ipairs(items) do base.items[#base.items + 1] = { target = item, color = first_item_color(item) or settings.active_color } end
  for _, take in ipairs(takes) do base.takes[#base.takes + 1] = { target = take, color = take_color(take) or settings.active_color } end
  for _, marker in ipairs(markers) do base.markers[#base.markers + 1] = { target = marker, color = marker_region_color(marker) or settings.active_color } end
  for _, region in ipairs(regions) do base.regions[#base.regions + 1] = { target = region, color = marker_region_color(region) or settings.active_color } end
  state.selected_adjust_base = base
  return base
end

local function apply_selected_adjustment(app, settings)
  local tracks, items, takes, markers, regions = selected_targets(settings)
  local total = target_total(tracks, items, takes, markers, regions)
  if total == 0 then app.status = "No selected targets"; return end
  local signature = selected_adjust_signature(tracks, items, takes, markers, regions)
  local base = state.selected_adjust_base
  if not base or base.signature ~= signature then base = capture_selected_adjust_base(settings, tracks, items, takes, markers, regions, signature) end
  local adjustment = { brightness = state.selected_adjust_brightness or 0, saturation = state.selected_adjust_saturation or 0 }
  with_undo("Color Studio: Adjust Selected", function()
    for _, entry in ipairs(base.tracks) do set_track_color(entry.target, apply_palette_adjustment(entry.color, adjustment)) end
    for _, entry in ipairs(base.items) do set_item_color(entry.target, apply_palette_adjustment(entry.color, adjustment)) end
    for _, entry in ipairs(base.takes) do set_take_color(entry.target, apply_palette_adjustment(entry.color, adjustment)) end
    for _, entry in ipairs(base.markers) do set_marker_region_color(entry.target, apply_palette_adjustment(entry.color, adjustment)) end
    for _, entry in ipairs(base.regions) do set_marker_region_color(entry.target, apply_palette_adjustment(entry.color, adjustment)) end
  end)
  if adjustment.brightness == 0 and adjustment.saturation == 0 then state.selected_adjust_base = nil end
  app.status = "Adjusted " .. tostring(total) .. " selected target(s)"
end

local function track_index(track)
  return math.floor((r.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER") or 1) - 1)
end

local function folder_children(track)
  local children = {}
  if not valid_track(track) or (r.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH") or 0) <= 0 then return children end
  local depth = r.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH") or 0
  local count = r.CountTracks(0) or 0
  for index = track_index(track) + 1, count - 1 do
    local child = r.GetTrack(0, index)
    if not valid_track(child) then break end
    children[#children + 1] = { track = child, depth = math.max(1, depth) }
    depth = depth + (r.GetMediaTrackInfo_Value(child, "I_FOLDERDEPTH") or 0)
    if depth <= 0 then break end
  end
  return children
end

local function child_depth_amount(depth)
  return math.min(0.68, 0.22 + (math.max(1, depth or 1) - 1) * 0.16)
end

local function apply_children_from_parent(app, settings)
  local tracks = selected_tracks()
  if #tracks == 0 then app.status = "No selected tracks"; return end
  local changed = 0
  with_undo("Color Studio: Children From Parent", function()
    for _, track in ipairs(tracks) do
      local base = track_color(track) or settings.active_color
      for _, child in ipairs(folder_children(track)) do
        local amount = child_depth_amount(child.depth)
        set_track_color(child.track, adjust_color(base, amount))
        changed = changed + 1
      end
    end
  end)
  app.status = changed > 0 and ("Colored " .. tostring(changed) .. " child track(s)") or "No folder children found"
end

local function items_on_tracks(tracks)
  local items = {}
  for _, track in ipairs(tracks or {}) do
    if valid_track(track) then
      local count = r.CountTrackMediaItems(track) or 0
      for index = 0, count - 1 do
        local item = r.GetTrackMediaItem(track, index)
        if valid_item(item) then items[#items + 1] = item end
      end
    end
  end
  return items
end

local function apply_items_follow_track(app, settings)
  local items = selected_items()
  if #items == 0 then items = items_on_tracks(selected_tracks()) end
  if #items == 0 then app.status = "No selected items or track items"; return end
  local changed = 0
  with_undo("Color Studio: Items Follow Track", function()
    for _, item in ipairs(items) do
      local color = r.GetMediaItemInfo_Value(item, "I_CUSTOMCOLOR") or 0
      if color ~= 0 then
        set_item_color(item, nil)
        changed = changed + 1
      end
    end
  end)
  app.status = changed > 0 and ("Restored track color follow on " .. tostring(changed) .. " item(s)") or "Selected items already follow track color"
end

local function track_name(track)
  local ok, name = r.GetTrackName(track)
  if ok and name and name ~= "" then return name end
  local index = math.floor(r.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER") or 0)
  return "Track " .. tostring(index)
end

local function auto_rule_matches(rule, name)
  local pattern = trim_text(rule.value or ""):lower()
  if pattern == "" then return false end
  name = tostring(name or ""):lower()
  if rule.matcher == "exact" then return name == pattern end
  if rule.matcher == "starts" then return name:sub(1, #pattern) == pattern end
  if rule.matcher == "ends" then return name:sub(-#pattern) == pattern end
  return name:find(pattern, 1, true) ~= nil
end

local function auto_color_for_rule(settings, rule)
  return tonumber(rule.color) or settings.active_color
end

local function auto_matcher_label(matcher)
  for _, entry in ipairs(AUTO_MATCHERS) do
    if entry.id == matcher then return entry.label end
  end
  return AUTO_MATCHERS[1].label
end

local function auto_target_label(target)
  for _, entry in ipairs(AUTO_TARGETS) do
    if entry.id == target then return entry.label end
  end
  return AUTO_TARGETS[1].label
end

local function auto_target_hint(target)
  for _, entry in ipairs(AUTO_TARGETS) do
    if entry.id == target then return entry.hint end
  end
  return AUTO_TARGETS[1].hint
end

local function auto_rule_target(rule)
  return valid_auto_target(rule and rule.target) and rule.target or "tracks"
end

local function auto_target_entries(target)
  local entries = {}
  if target == "markers" then
    for _, marker in ipairs(all_marker_region_targets(true, false)) do entries[#entries + 1] = { target = marker, name = marker.name or "" } end
  elseif target == "regions" then
    for _, region in ipairs(all_marker_region_targets(false, true)) do entries[#entries + 1] = { target = region, name = region.name or "" } end
  else
    for track_index = 0, (r.CountTracks(0) or 0) - 1 do
      local track = r.GetTrack(0, track_index)
      if valid_track(track) then entries[#entries + 1] = { target = track, name = track_name(track) } end
    end
  end
  return entries
end

local function set_auto_entry_color(target, entry, color)
  if target == "markers" or target == "regions" then
    set_marker_region_color(entry.target, color)
  else
    set_track_color(entry.target, color)
  end
end

local function selected_auto_rule(settings)
  settings.auto_rule_index = math.max(1, math.min(#settings.auto_rules, tonumber(settings.auto_rule_index) or 1))
  return settings.auto_rules[settings.auto_rule_index]
end

local function renumber_auto_rule_names(settings)
  for index, rule in ipairs(settings.auto_rules or {}) do
    local name = trim_text(rule.name or "")
    if name == "" or name:match("^Track Rule %d+$") or name:match("^Rule %d+$") then
      rule.name = "Rule " .. tostring(index)
    end
  end
end

local function add_auto_rule(app, settings)
  local index = #settings.auto_rules + 1
  local rule = default_auto_rule(index)
  local colors = editable_palette_colors(settings)
  rule.color = colors[1] or settings.active_color
  settings.auto_rules[index] = rule
  settings.auto_rule_index = index
  if app.save_settings then app.save_settings() end
  app.status = "Added auto color rule"
end

local function delete_auto_rule(app, settings)
  if #settings.auto_rules <= 1 then
    local rule = default_auto_rule(1)
    local colors = editable_palette_colors(settings)
    rule.color = colors[1] or settings.active_color
    settings.auto_rules[1] = rule
    settings.auto_rule_index = 1
    app.status = "Reset auto color rule"
  else
    table.remove(settings.auto_rules, settings.auto_rule_index)
    settings.auto_rule_index = math.max(1, math.min(#settings.auto_rules, settings.auto_rule_index))
    app.status = "Deleted auto color rule"
  end
  renumber_auto_rule_names(settings)
  if app.save_settings then app.save_settings() end
end

local function count_auto_matches(settings)
  local count = 0
  for _, target_info in ipairs(AUTO_TARGETS) do
    for _, entry in ipairs(auto_target_entries(target_info.id)) do
      for _, rule in ipairs(settings.auto_rules or {}) do
        if rule.enabled and auto_rule_target(rule) == target_info.id and auto_rule_matches(rule, entry.name) then
          count = count + 1
          break
        end
      end
    end
  end
  return count
end

local function count_auto_rule_matches(rule)
  if not rule or not rule.enabled then return 0 end
  local count = 0
  for _, entry in ipairs(auto_target_entries(auto_rule_target(rule))) do
    if auto_rule_matches(rule, entry.name) then count = count + 1 end
  end
  return count
end

local function apply_auto_color(app, settings)
  local changed = 0
  with_undo("Color Studio: Apply Auto", function()
    for _, target_info in ipairs(AUTO_TARGETS) do
      for _, entry in ipairs(auto_target_entries(target_info.id)) do
        for _, rule in ipairs(settings.auto_rules or {}) do
          if rule.enabled and auto_rule_target(rule) == target_info.id and auto_rule_matches(rule, entry.name) then
            set_auto_entry_color(target_info.id, entry, auto_color_for_rule(settings, rule))
            changed = changed + 1
            break
          end
        end
      end
    end
  end)
  app.status = changed > 0 and ("Auto colored " .. tostring(changed) .. " track(s)") or "No auto color matches"
end

local function draw_button(ctx, label, width)
  return r.ImGui_Button(ctx, label, width or 92, 0)
end

local function draw_toggle_button(ctx, label, active, width)
  local style_count = 0
  if active and r.ImGui_Col_Button then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), Theme.colors.accent_soft); style_count = style_count + 1 end
  if active and r.ImGui_Col_ButtonHovered then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), Theme.colors.accent); style_count = style_count + 1 end
  if active and r.ImGui_Col_ButtonActive then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), Theme.colors.accent); style_count = style_count + 1 end
  local clicked = r.ImGui_Button(ctx, label, width or 54, 0)
  if style_count > 0 then r.ImGui_PopStyleColor(ctx, style_count) end
  return clicked
end

local function three_column_flags()
  return r.ImGui_TableFlags_SizingStretchSame and r.ImGui_TableFlags_SizingStretchSame() or 0
end

local function auto_rules_overview_flags()
  return r.ImGui_TableFlags_SizingStretchProp and r.ImGui_TableFlags_SizingStretchProp() or three_column_flags()
end

local function setup_auto_rules_overview_columns(ctx)
  if not r.ImGui_TableSetupColumn then return end
  local stretch = r.ImGui_TableColumnFlags_WidthStretch and r.ImGui_TableColumnFlags_WidthStretch() or 0
  local fixed = r.ImGui_TableColumnFlags_WidthFixed and r.ImGui_TableColumnFlags_WidthFixed() or 0
  r.ImGui_TableSetupColumn(ctx, "Rule", stretch, 1.0)
  r.ImGui_TableSetupColumn(ctx, "Info", stretch, 1.7)
  r.ImGui_TableSetupColumn(ctx, "Color", fixed, 24)
end

local function draw_three_column_buttons(ctx, id, buttons)
  if r.ImGui_BeginTable and r.ImGui_BeginTable(ctx, id, 3, three_column_flags()) then
    for _, button in ipairs(buttons) do
      r.ImGui_TableNextColumn(ctx)
      if draw_button(ctx, button.label, -1) then button.action() end
      if button.tooltip and r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, button.tooltip) end
    end
    r.ImGui_EndTable(ctx)
    return
  end
  for index, button in ipairs(buttons) do
    if index > 1 and (index - 1) % 3 ~= 0 then r.ImGui_SameLine(ctx) end
    if draw_button(ctx, button.label) then button.action() end
    if button.tooltip and r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, button.tooltip) end
  end
end

local function push_slider_theme(ctx)
  local count = 0
  if r.ImGui_Col_FrameBg then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), Theme.colors.frame_bg); count = count + 1 end
  if r.ImGui_Col_FrameBgHovered then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgHovered(), Theme.colors.frame_hover); count = count + 1 end
  if r.ImGui_Col_FrameBgActive then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgActive(), Theme.colors.accent_soft); count = count + 1 end
  if r.ImGui_Col_SliderGrab then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrab(), Theme.colors.accent); count = count + 1 end
  if r.ImGui_Col_SliderGrabActive then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrabActive(), Theme.colors.text); count = count + 1 end
  return count
end

local function themed_slider_double(ctx, label, value, min_value, max_value, format)
  local style_count = push_slider_theme(ctx)
  local changed, next_value = r.ImGui_SliderDouble(ctx, label, value, min_value, max_value, format)
  if style_count > 0 then r.ImGui_PopStyleColor(ctx, style_count) end
  return changed, next_value
end

local function draw_target_selector(ctx, app, settings, selected_item_count)
  local function draw_target_button(width)
    if r.ImGui_Button(ctx, target_label(settings, selected_item_count) .. "##color_studio_target", width or 112, 0) then
      cycle_target_mode(app, settings)
    end
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Auto: selected item = item, otherwise track") end
  end

  local function draw_count_combo(width)
    if r.ImGui_SetNextItemWidth then r.ImGui_SetNextItemWidth(ctx, width or 72) end
    if r.ImGui_BeginCombo(ctx, "##color_studio_palette_color_count", tostring(settings.palette_color_count)) then
      for _, count in ipairs(PALETTE_COLOR_COUNTS) do
        local selected = settings.palette_color_count == count
        if r.ImGui_Selectable(ctx, tostring(count) .. "##palette_color_count_" .. tostring(count), selected) then
          settings.palette_color_count = count
          if app.save_settings then app.save_settings() end
        end
        if selected then r.ImGui_SetItemDefaultFocus(ctx) end
      end
      r.ImGui_EndCombo(ctx)
    end
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Palette colors") end
  end

  local function draw_sort_button(width)
    if r.ImGui_Button(ctx, (settings.palette_sorted and "Hue" or "Seq") .. "##color_studio_palette_sort", width or 44, 0) then
      settings.palette_sorted = not settings.palette_sorted
      if app.save_settings then app.save_settings() end
    end
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, settings.palette_sorted and "Sorted by color" or "Palette order") end
  end

  if r.ImGui_BeginTable and r.ImGui_BeginTable(ctx, "##color_studio_target_row", 3, three_column_flags()) then
    r.ImGui_TableNextColumn(ctx)
    draw_target_button(-1)
    r.ImGui_TableNextColumn(ctx)
    draw_count_combo(-1)
    r.ImGui_TableNextColumn(ctx)
    draw_sort_button(-1)
    r.ImGui_EndTable(ctx)
    return
  end

  draw_target_button()
  r.ImGui_SameLine(ctx)
  draw_count_combo()
  r.ImGui_SameLine(ctx)
  draw_sort_button()
end

local function draw_random_controls(ctx, app, settings)
  if r.ImGui_BeginTable and r.ImGui_BeginTable(ctx, "##color_studio_random_row", 3, three_column_flags()) then
    r.ImGui_TableNextColumn(ctx)
    if draw_button(ctx, "Random", -1) then apply_random(app, settings) end
    for _, mode in ipairs(RANDOM_MODES) do
      r.ImGui_TableNextColumn(ctx)
      local changed, value = r.ImGui_Checkbox(ctx, mode.label .. "##random_" .. mode.id, settings.random_mode == mode.id)
      if changed and value then
        settings.random_mode = mode.id
        if app.save_settings then app.save_settings() end
      end
    end
    r.ImGui_EndTable(ctx)
    return
  end
  if draw_button(ctx, "Random") then apply_random(app, settings) end
  for _, mode in ipairs(RANDOM_MODES) do
    r.ImGui_SameLine(ctx)
    local changed, value = r.ImGui_Checkbox(ctx, mode.label .. "##random_" .. mode.id, settings.random_mode == mode.id)
    if changed and value then
      settings.random_mode = mode.id
      if app.save_settings then app.save_settings() end
    end
  end
end

local function draw_swatch(ctx, id, color, size, highlighted)
  size = size or 26
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), color)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), adjust_color(color, 0.18))
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), adjust_color(color, -0.18))
  local clicked = r.ImGui_Button(ctx, "##" .. id, size, size)
  r.ImGui_PopStyleColor(ctx, 3)
  if highlighted and r.ImGui_GetWindowDrawList and r.ImGui_GetItemRectMin and r.ImGui_GetItemRectMax then
    local x1, y1 = r.ImGui_GetItemRectMin(ctx)
    local x2, y2 = r.ImGui_GetItemRectMax(ctx)
    r.ImGui_DrawList_AddRect(r.ImGui_GetWindowDrawList(ctx), x1 - 2, y1 - 2, x2 + 2, y2 + 2, Theme.colors.accent or Theme.colors.text or 0xFFFFFFFF, 3, 0, 2)
  end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, color_hex(color)) end
  return clicked
end

local function begin_color_drag(ctx, color)
  if not (r.ImGui_BeginDragDropSource and r.ImGui_SetDragDropPayload) then return end
  if r.ImGui_BeginDragDropSource(ctx, 0) then
    r.ImGui_SetDragDropPayload(ctx, COLOR_PAYLOAD_TYPE, tostring(color))
    r.ImGui_Text(ctx, color_hex(color))
    r.ImGui_EndDragDropSource(ctx)
  end
end

local function accept_color_drop(ctx)
  if not (r.ImGui_BeginDragDropTarget and r.ImGui_AcceptDragDropPayload) then return nil end
  local color = nil
  if r.ImGui_BeginDragDropTarget(ctx) then
    local ok, payload = r.ImGui_AcceptDragDropPayload(ctx, COLOR_PAYLOAD_TYPE)
    if ok then color = tonumber(payload) end
    r.ImGui_EndDragDropTarget(ctx)
  end
  return color
end

local function apply_active_color_drop(ctx, app, settings)
  local color = accept_color_drop(ctx)
  if not color then return false end
  set_active_color(app, settings, color, true)
  state.active_color_dirty = false
  app.status = "Active color: " .. color_hex(color)
  return true
end

local function apply_gradient_color_drop(ctx, app, settings, key, label)
  local color = accept_color_drop(ctx)
  if not color then return false end
  settings[key] = color
  add_recent_color(app, settings, color)
  app.status = label .. ": " .. color_hex(color)
  return true
end

local function shift_pressed(ctx)
  return r.ImGui_IsKeyDown and r.ImGui_Mod_Shift and r.ImGui_IsKeyDown(ctx, r.ImGui_Mod_Shift())
end

local function draw_palette_swatch_editor(ctx, app, settings, colors, index)
  if not r.ImGui_BeginPopupContextItem then return end
  if r.ImGui_BeginPopupContextItem(ctx, "##palette_swatch_editor_" .. tostring(index)) then
    r.ImGui_Text(ctx, "Palette " .. tostring(index))
    local changed, value
    if r.ImGui_ColorPicker4 then
      changed, value = r.ImGui_ColorPicker4(ctx, "##palette_swatch_picker_" .. tostring(index), colors[index] or settings.active_color, 0)
    else
      changed, value = r.ImGui_ColorEdit4(ctx, "##palette_swatch_picker_" .. tostring(index), colors[index] or settings.active_color, 0)
    end
    if changed then
      colors[index] = value
      app.status = "Edited palette color " .. tostring(index)
    end
    if draw_button(ctx, "Use Active") then
      colors[index] = settings.active_color
      app.status = "Edited palette color " .. tostring(index)
      if r.ImGui_CloseCurrentPopup then r.ImGui_CloseCurrentPopup(ctx) end
    end
    r.ImGui_EndPopup(ctx)
  end
end

local function draw_swatch_grid(ctx, prefix, colors, min_size, on_click, allow_drag, highlight_color, on_edit, highlight_index)
  local count = #colors
  if count == 0 then return end
  local available_w = r.ImGui_GetContentRegionAvail(ctx) or min_size
  local margin = 6
  local gap = 4
  local grid_w = math.max(min_size, available_w - margin * 2)
  local columns = math.max(1, math.min(count, math.floor((grid_w + gap) / (min_size + gap))))
  local size = math.max(18, math.floor((grid_w - gap * (columns - 1)) / columns))
  if r.ImGui_Indent then r.ImGui_Indent(ctx, margin) end
  for index, color in ipairs(colors) do
    if index > 1 and (index - 1) % columns ~= 0 then r.ImGui_SameLine(ctx, 0, gap) end
    local highlighted = (highlight_index and index == highlight_index) or color_matches(color, highlight_color)
    if draw_swatch(ctx, prefix .. tostring(index), color, size, highlighted) then on_click(color, index) end
    if on_edit then on_edit(index) end
    if allow_drag then begin_color_drag(ctx, color) end
  end
  if r.ImGui_Unindent then r.ImGui_Unindent(ctx, margin) end
end

local function draw_palette_selector(ctx, app, settings)
  local current = palette(settings).name
  if r.ImGui_BeginCombo(ctx, "Palette##color_studio_palette", current) then
    for index, pal in ipairs(PALETTES) do
      local selected = settings.selected_custom_palette == "" and index == settings.palette_index
      if r.ImGui_Selectable(ctx, pal.name .. "##palette_select_" .. tostring(index), selected) then
        settings.palette_index = index
        settings.selected_custom_palette = ""
        reset_palette_edit_buffer()
        if app.save_settings then app.save_settings() end
      end
      if selected then r.ImGui_SetItemDefaultFocus(ctx) end
    end
    local names = custom_palette_names(settings)
    if #names > 0 then r.ImGui_Separator(ctx) end
    for _, name in ipairs(names) do
      local selected = settings.selected_custom_palette == name
      if r.ImGui_Selectable(ctx, name .. "##custom_palette_select", selected) then
        settings.selected_custom_palette = name
        settings.custom_palette_name = name
        reset_palette_edit_buffer()
        if app.save_settings then app.save_settings() end
      end
      if selected then r.ImGui_SetItemDefaultFocus(ctx) end
    end
    r.ImGui_EndCombo(ctx)
  end
end

local function draw_custom_palette_controls(ctx, app, settings)
  local palette_name = trim_text(settings.custom_palette_name or "")
  local exists = settings.custom_palettes and settings.custom_palettes[palette_name] ~= nil
  if r.ImGui_BeginTable and r.ImGui_BeginTable(ctx, "##color_studio_custom_palette_controls", 3, three_column_flags()) then
    r.ImGui_TableNextColumn(ctx)
    if r.ImGui_SetNextItemWidth then r.ImGui_SetNextItemWidth(ctx, -1) end
    local changed, value = r.ImGui_InputTextWithHint(ctx, "##color_studio_custom_palette_name", "Color Studio theme name", settings.custom_palette_name or "My Palette")
    if changed then settings.custom_palette_name = value end
    r.ImGui_TableNextColumn(ctx)
    if draw_button(ctx, (exists and "Update" or "Save") .. "##color_studio_save_palette", -1) then save_custom_palette(app, settings) end
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, exists and "Update custom Color Studio theme" or "Save current palette as Color Studio theme") end
    r.ImGui_TableNextColumn(ctx)
    if draw_button(ctx, "Delete##color_studio_delete_palette", -1) then delete_custom_palette(app, settings) end
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Delete custom Color Studio theme") end
    r.ImGui_EndTable(ctx)
    return
  end
  local changed, value = r.ImGui_InputTextWithHint(ctx, "##color_studio_custom_palette_name", "Color Studio theme name", settings.custom_palette_name or "My Palette")
  if changed then settings.custom_palette_name = value end
  r.ImGui_SameLine(ctx)
  if draw_button(ctx, exists and "Update" or "Save") then save_custom_palette(app, settings) end
  r.ImGui_SameLine(ctx)
  if draw_button(ctx, "Delete") then delete_custom_palette(app, settings) end
end

local function draw_palette_adjustments(ctx, app, settings)
  local adjustment = palette_adjustment(settings)
  local function save_adjustment()
    if app.save_settings then app.save_settings() end
  end
  if r.ImGui_BeginTable and r.ImGui_BeginTable(ctx, "##color_studio_palette_adjustments", 2, three_column_flags()) then
    r.ImGui_TableNextColumn(ctx)
    if r.ImGui_SetNextItemWidth then r.ImGui_SetNextItemWidth(ctx, -1) end
    local changed, value = themed_slider_double(ctx, "Brightness##color_studio_palette_bright", adjustment.brightness, -50, 50, "%.0f%%")
    if changed then adjustment.brightness = value; save_adjustment() end
    r.ImGui_TableNextColumn(ctx)
    if draw_button(ctx, "Reset Bright", -1) then adjustment.brightness = 0; save_adjustment() end
    r.ImGui_TableNextColumn(ctx)
    if r.ImGui_SetNextItemWidth then r.ImGui_SetNextItemWidth(ctx, -1) end
    changed, value = themed_slider_double(ctx, "Saturation##color_studio_palette_sat", adjustment.saturation, -100, 100, "%.0f%%")
    if changed then adjustment.saturation = value; save_adjustment() end
    r.ImGui_TableNextColumn(ctx)
    if draw_button(ctx, "Reset Sat", -1) then adjustment.saturation = 0; save_adjustment() end
    r.ImGui_EndTable(ctx)
    return
  end
  local changed, value = themed_slider_double(ctx, "Brightness##color_studio_palette_bright", adjustment.brightness, -50, 50, "%.0f%%")
  if changed then adjustment.brightness = value; save_adjustment() end
  r.ImGui_SameLine(ctx)
  if draw_button(ctx, "Reset Bright") then adjustment.brightness = 0; save_adjustment() end
  changed, value = themed_slider_double(ctx, "Saturation##color_studio_palette_sat", adjustment.saturation, -100, 100, "%.0f%%")
  if changed then adjustment.saturation = value; save_adjustment() end
  r.ImGui_SameLine(ctx)
  if draw_button(ctx, "Reset Sat") then adjustment.saturation = 0; save_adjustment() end
end

local function draw_palette_swatches(ctx, app, settings)
  local colors = editable_palette_colors(settings)
  local target_color = current_target_color(settings)
  local highlight_color = nil
  for _, color in ipairs(colors) do
    if color_matches(color, target_color) then highlight_color = target_color; break end
  end
  draw_swatch_grid(ctx, "palette_swatch_", colors, 28, function(color, index)
    if shift_pressed(ctx) then
      local next_color = colors[(index % #colors) + 1]
      set_active_color(app, settings, color, true)
      apply_gradient_colors(app, settings, color, next_color)
      return
    end
    select_color(app, settings, color, true, true)
  end, true, highlight_color, function(index) draw_palette_swatch_editor(ctx, app, settings, colors, index) end)
end

local function draw_recent_swatches(ctx, app, settings)
  if #settings.recent_colors == 0 then
    r.ImGui_TextColored(ctx, Theme.colors.text_dim, "No recent colors")
    return
  end
  draw_swatch_grid(ctx, "recent_swatch_", settings.recent_colors, 24, function(color) select_color(app, settings, color, false, true) end)
end

local function draw_primary_actions(ctx, app, settings)
  if r.ImGui_BeginTable and r.ImGui_BeginTable(ctx, "##color_studio_primary_action_grid", 3, three_column_flags()) then
    r.ImGui_TableNextColumn(ctx)
    if draw_button(ctx, "Default", -1) then default_color(app, settings) end
    r.ImGui_TableNextColumn(ctx)
    if draw_button(ctx, "Items Follow", -1) then apply_items_follow_track(app, settings) end
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Clear custom item colors so items inherit their track color") end
    r.ImGui_TableNextColumn(ctx)
    if draw_button(ctx, "Children", -1) then apply_children_from_parent(app, settings) end
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Derive child track colors from selected parent folders") end
    r.ImGui_EndTable(ctx)
    return
  end
  if draw_button(ctx, "Default") then default_color(app, settings) end
  r.ImGui_SameLine(ctx)
  if draw_button(ctx, "Items Follow") then apply_items_follow_track(app, settings) end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Clear custom item colors so items inherit their track color") end
  r.ImGui_SameLine(ctx)
  if draw_button(ctx, "Children") then apply_children_from_parent(app, settings) end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Derive child track colors from selected parent folders") end
end

local function draw_adjust_selected(ctx, app, settings)
  state.selected_adjust_brightness = state.selected_adjust_brightness or 0
  state.selected_adjust_saturation = state.selected_adjust_saturation or 0
  r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Adjust selected")
  if r.ImGui_BeginTable and r.ImGui_BeginTable(ctx, "##color_studio_selected_adjust", 2, three_column_flags()) then
    r.ImGui_TableNextColumn(ctx)
    if r.ImGui_SetNextItemWidth then r.ImGui_SetNextItemWidth(ctx, -1) end
    local changed, value = themed_slider_double(ctx, "Brightness##color_studio_selected_bright", state.selected_adjust_brightness, -50, 50, "%.0f%%")
    if changed then state.selected_adjust_brightness = value; apply_selected_adjustment(app, settings) end
    r.ImGui_TableNextColumn(ctx)
    if draw_button(ctx, "Reset Bright", -1) then state.selected_adjust_brightness = 0; apply_selected_adjustment(app, settings) end
    r.ImGui_TableNextColumn(ctx)
    if r.ImGui_SetNextItemWidth then r.ImGui_SetNextItemWidth(ctx, -1) end
    changed, value = themed_slider_double(ctx, "Saturation##color_studio_selected_sat", state.selected_adjust_saturation, -100, 100, "%.0f%%")
    if changed then state.selected_adjust_saturation = value; apply_selected_adjustment(app, settings) end
    r.ImGui_TableNextColumn(ctx)
    if draw_button(ctx, "Reset Sat", -1) then state.selected_adjust_saturation = 0; apply_selected_adjustment(app, settings) end
    r.ImGui_EndTable(ctx)
    return
  end
  local changed, value = themed_slider_double(ctx, "Brightness##color_studio_selected_bright", state.selected_adjust_brightness, -50, 50, "%.0f%%")
  if changed then state.selected_adjust_brightness = value; apply_selected_adjustment(app, settings) end
  r.ImGui_SameLine(ctx)
  if draw_button(ctx, "Reset Bright") then state.selected_adjust_brightness = 0; apply_selected_adjustment(app, settings) end
  changed, value = themed_slider_double(ctx, "Saturation##color_studio_selected_sat", state.selected_adjust_saturation, -100, 100, "%.0f%%")
  if changed then state.selected_adjust_saturation = value; apply_selected_adjustment(app, settings) end
  r.ImGui_SameLine(ctx)
  if draw_button(ctx, "Reset Sat") then state.selected_adjust_saturation = 0; apply_selected_adjustment(app, settings) end
end

local function draw_active_controls(ctx, app, settings, flags)
  if r.ImGui_BeginTable and r.ImGui_BeginTable(ctx, "##color_studio_active_row", 3, three_column_flags()) then
    r.ImGui_TableNextColumn(ctx)
    if r.ImGui_SetNextItemWidth then r.ImGui_SetNextItemWidth(ctx, -1) end
    local changed, value = r.ImGui_ColorEdit4(ctx, "Active##color_studio_active", settings.active_color, flags)
    if changed then
      set_active_color(app, settings, value, false)
      state.active_color_dirty = true
    end
    if state.active_color_dirty and r.ImGui_IsItemDeactivatedAfterEdit and r.ImGui_IsItemDeactivatedAfterEdit(ctx) then
      apply_color(app, settings, settings.active_color)
      state.active_color_dirty = false
    end
    apply_active_color_drop(ctx, app, settings)
    r.ImGui_TableNextColumn(ctx)
    if draw_button(ctx, "Pick", -1) then pick_color(app, settings) end
    r.ImGui_TableNextColumn(ctx)
    if draw_button(ctx, "Apply", -1) then apply_color(app, settings, settings.active_color) end
    r.ImGui_EndTable(ctx)
    return
  end
  local changed, value = r.ImGui_ColorEdit4(ctx, "Active##color_studio_active", settings.active_color, flags)
  if changed then
    set_active_color(app, settings, value, false)
    state.active_color_dirty = true
  end
  if state.active_color_dirty and r.ImGui_IsItemDeactivatedAfterEdit and r.ImGui_IsItemDeactivatedAfterEdit(ctx) then
    apply_color(app, settings, settings.active_color)
    state.active_color_dirty = false
  end
  apply_active_color_drop(ctx, app, settings)
  r.ImGui_SameLine(ctx)
  if draw_button(ctx, "Pick") then pick_color(app, settings) end
  r.ImGui_SameLine(ctx)
  if draw_button(ctx, "Apply") then apply_color(app, settings, settings.active_color) end
end

local function draw_gradient_controls(ctx, app, settings, flags)
  if r.ImGui_BeginTable and r.ImGui_BeginTable(ctx, "##color_studio_gradient_row", 3, three_column_flags()) then
    r.ImGui_TableNextColumn(ctx)
    if r.ImGui_SetNextItemWidth then r.ImGui_SetNextItemWidth(ctx, -1) end
    local changed, value = r.ImGui_ColorEdit4(ctx, "Color A##color_studio_gradient_a", settings.gradient_start, flags)
    if changed then settings.gradient_start = value; if app.save_settings then app.save_settings() end end
    apply_gradient_color_drop(ctx, app, settings, "gradient_start", "Color A")
    r.ImGui_TableNextColumn(ctx)
    if r.ImGui_SetNextItemWidth then r.ImGui_SetNextItemWidth(ctx, -1) end
    changed, value = r.ImGui_ColorEdit4(ctx, "Color B##color_studio_gradient_b", settings.gradient_end, flags)
    if changed then settings.gradient_end = value; if app.save_settings then app.save_settings() end end
    apply_gradient_color_drop(ctx, app, settings, "gradient_end", "Color B")
    r.ImGui_TableNextColumn(ctx)
    if draw_button(ctx, "Gradient", -1) then apply_gradient(app, settings) end
    r.ImGui_EndTable(ctx)
    return
  end
  local changed, value = r.ImGui_ColorEdit4(ctx, "Color A##color_studio_gradient_a", settings.gradient_start, flags)
  if changed then settings.gradient_start = value; if app.save_settings then app.save_settings() end end
  apply_gradient_color_drop(ctx, app, settings, "gradient_start", "Color A")
  r.ImGui_SameLine(ctx)
  changed, value = r.ImGui_ColorEdit4(ctx, "Color B##color_studio_gradient_b", settings.gradient_end, flags)
  if changed then settings.gradient_end = value; if app.save_settings then app.save_settings() end end
  apply_gradient_color_drop(ctx, app, settings, "gradient_end", "Color B")
  r.ImGui_SameLine(ctx)
  if draw_button(ctx, "Gradient") then apply_gradient(app, settings) end
end

local function draw_view_tab_button(ctx, app, settings, label, mode, width)
  local active = settings.view_mode == mode
  local style_count = 0
  if active and r.ImGui_Col_Button then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), Theme.colors.accent_soft); style_count = style_count + 1 end
  if active and r.ImGui_Col_ButtonHovered then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), Theme.colors.accent); style_count = style_count + 1 end
  if active and r.ImGui_Col_ButtonActive then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), Theme.colors.accent); style_count = style_count + 1 end
  if r.ImGui_Button(ctx, label .. "##color_studio_view_" .. mode, width or 92, 0) and not active then
    settings.view_mode = mode
    if app.save_settings then app.save_settings() end
  end
  if style_count > 0 then r.ImGui_PopStyleColor(ctx, style_count) end
end

local function draw_view_tabs(ctx, app, settings)
  if r.ImGui_BeginTable and r.ImGui_BeginTable(ctx, "##color_studio_view_tabs", 2, three_column_flags()) then
    r.ImGui_TableNextColumn(ctx)
    draw_view_tab_button(ctx, app, settings, "Manual", "manual", -1)
    r.ImGui_TableNextColumn(ctx)
    draw_view_tab_button(ctx, app, settings, "Auto", "auto", -1)
    r.ImGui_EndTable(ctx)
    return
  end
  draw_view_tab_button(ctx, app, settings, "Manual", "manual")
  r.ImGui_SameLine(ctx)
  draw_view_tab_button(ctx, app, settings, "Auto", "auto")
end

local function draw_manual_tab(ctx, app, settings, selected_item_count)
  draw_target_selector(ctx, app, settings, selected_item_count)
  r.ImGui_Spacing(ctx)

  draw_palette_selector(ctx, app, settings)
  draw_palette_swatches(ctx, app, settings)
  draw_palette_adjustments(ctx, app, settings)
  draw_custom_palette_controls(ctx, app, settings)
  r.ImGui_Separator(ctx)

  local flags = r.ImGui_ColorEditFlags_NoInputs and r.ImGui_ColorEditFlags_NoInputs() or 0
  draw_active_controls(ctx, app, settings, flags)
  draw_gradient_controls(ctx, app, settings, flags)

  r.ImGui_Separator(ctx)
  draw_primary_actions(ctx, app, settings)
  draw_random_controls(ctx, app, settings)

  r.ImGui_Separator(ctx)
  draw_adjust_selected(ctx, app, settings)

  r.ImGui_Separator(ctx)
  r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Recent")
  draw_recent_swatches(ctx, app, settings)
end

local function draw_auto_rule_selector(ctx, app, settings)
  local rule = selected_auto_rule(settings)
  local label = "Rule " .. tostring(settings.auto_rule_index)
  if r.ImGui_BeginTable and r.ImGui_BeginTable(ctx, "##color_studio_auto_rule_selector", 3, three_column_flags()) then
    r.ImGui_TableNextColumn(ctx)
    if r.ImGui_SetNextItemWidth then r.ImGui_SetNextItemWidth(ctx, -1) end
    if r.ImGui_BeginCombo(ctx, "##color_studio_auto_rule_combo", label) then
      for index, option in ipairs(settings.auto_rules or {}) do
        local option_label = "Rule " .. tostring(index)
        local selected = settings.auto_rule_index == index
        if r.ImGui_Selectable(ctx, option_label .. "##auto_rule_select_" .. tostring(index), selected) then
          settings.auto_rule_index = index
          if app.save_settings then app.save_settings() end
        end
        if selected then r.ImGui_SetItemDefaultFocus(ctx) end
      end
      r.ImGui_EndCombo(ctx)
    end
    r.ImGui_TableNextColumn(ctx)
    if draw_button(ctx, "Add", -1) then add_auto_rule(app, settings) end
    r.ImGui_TableNextColumn(ctx)
    if draw_button(ctx, "Delete", -1) then delete_auto_rule(app, settings) end
    r.ImGui_EndTable(ctx)
    return
  end
  if r.ImGui_BeginCombo(ctx, "Rule##color_studio_auto_rule_combo", label) then
    for index, option in ipairs(settings.auto_rules or {}) do
      local option_label = "Rule " .. tostring(index)
      local selected = settings.auto_rule_index == index
      if r.ImGui_Selectable(ctx, option_label .. "##auto_rule_select_" .. tostring(index), selected) then
        settings.auto_rule_index = index
        if app.save_settings then app.save_settings() end
      end
      if selected then r.ImGui_SetItemDefaultFocus(ctx) end
    end
    r.ImGui_EndCombo(ctx)
  end
  r.ImGui_SameLine(ctx)
  if draw_button(ctx, "Add") then add_auto_rule(app, settings) end
  r.ImGui_SameLine(ctx)
  if draw_button(ctx, "Delete") then delete_auto_rule(app, settings) end
end

local function draw_auto_color_slot(ctx, app, settings, rule)
  local colors = editable_palette_colors(settings)
  if #colors == 0 then
    r.ImGui_TextColored(ctx, Theme.colors.text_dim, "No palette colors")
    return
  end
  local current = tonumber(rule.color) or settings.active_color
  local selected_index = nil
  for index, color in ipairs(colors) do
    if color_matches(color, current) then selected_index = index; break end
  end
  if r.ImGui_Indent then r.ImGui_Indent(ctx, 6) end
  if draw_swatch(ctx, "auto_selected_color", current, 26, true) then
    if r.ImGui_OpenPopup then r.ImGui_OpenPopup(ctx, "##auto_selected_color_picker") end
  end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Edit stored auto color") end
  if r.ImGui_BeginPopup and r.ImGui_BeginPopup(ctx, "##auto_selected_color_picker") then
    r.ImGui_Text(ctx, "Auto color")
    local changed, value
    if r.ImGui_ColorPicker4 then
      changed, value = r.ImGui_ColorPicker4(ctx, "##auto_selected_color_picker_value", current, 0)
    else
      changed, value = r.ImGui_ColorEdit4(ctx, "##auto_selected_color_picker_value", current, 0)
    end
    if changed then
      rule.color = value
      rule.color_index = selected_index or rule.color_index
      if app.save_settings then app.save_settings() end
      app.status = "Auto color: " .. color_hex(value)
    end
    r.ImGui_EndPopup(ctx)
  end
  if r.ImGui_Unindent then r.ImGui_Unindent(ctx, 6) end
  r.ImGui_Spacing(ctx)
  draw_swatch_grid(ctx, "auto_color_slot_", colors, 24, function(_, index)
    local color = colors[index]
    if not color_matches(rule.color, color) then
      rule.color_index = index
      rule.color = color
      if app.save_settings then app.save_settings() end
      app.status = "Auto color: " .. color_hex(color)
    end
  end, false, current, nil, selected_index)
end

local function draw_auto_target_combo(ctx, app, rule)
  if r.ImGui_SetNextItemWidth then r.ImGui_SetNextItemWidth(ctx, -1) end
  if r.ImGui_BeginCombo(ctx, "Target##color_studio_auto_target", auto_target_label(auto_rule_target(rule))) then
    for _, target in ipairs(AUTO_TARGETS) do
      local selected = auto_rule_target(rule) == target.id
      if r.ImGui_Selectable(ctx, target.label .. "##auto_target_" .. target.id, selected) then
        rule.target = target.id
        if app.save_settings then app.save_settings() end
      end
      if selected then r.ImGui_SetItemDefaultFocus(ctx) end
    end
    r.ImGui_EndCombo(ctx)
  end
end

local function draw_auto_rule_editor(ctx, app, settings)
  local rule = selected_auto_rule(settings)
  if not rule then return end

  local changed, value
  if r.ImGui_BeginTable and r.ImGui_BeginTable(ctx, "##color_studio_auto_rule_fields", 2, three_column_flags()) then
    r.ImGui_TableNextColumn(ctx)
    if draw_toggle_button(ctx, rule.enabled and "On##color_studio_auto_enabled" or "Off##color_studio_auto_enabled", rule.enabled, -1) then
      rule.enabled = not rule.enabled
      if app.save_settings then app.save_settings() end
    end
    r.ImGui_TableNextColumn(ctx)
    draw_auto_target_combo(ctx, app, rule)
    r.ImGui_TableNextColumn(ctx)
    if r.ImGui_SetNextItemWidth then r.ImGui_SetNextItemWidth(ctx, -1) end
    if r.ImGui_BeginCombo(ctx, "Match##color_studio_auto_matcher", auto_matcher_label(rule.matcher)) then
      for _, matcher in ipairs(AUTO_MATCHERS) do
        local selected = rule.matcher == matcher.id
        if r.ImGui_Selectable(ctx, matcher.label .. "##auto_matcher_" .. matcher.id, selected) then
          rule.matcher = matcher.id
          if app.save_settings then app.save_settings() end
        end
        if selected then r.ImGui_SetItemDefaultFocus(ctx) end
      end
      r.ImGui_EndCombo(ctx)
    end
    r.ImGui_TableNextColumn(ctx)
    if r.ImGui_SetNextItemWidth then r.ImGui_SetNextItemWidth(ctx, -1) end
    changed, value = r.ImGui_InputTextWithHint(ctx, "Text##color_studio_auto_value", auto_target_hint(auto_rule_target(rule)), rule.value or "")
    if changed then rule.value = value; if app.save_settings then app.save_settings() end end
    r.ImGui_EndTable(ctx)
    draw_auto_color_slot(ctx, app, settings, rule)
    return
  end

  if draw_toggle_button(ctx, rule.enabled and "On##color_studio_auto_enabled" or "Off##color_studio_auto_enabled", rule.enabled) then
    rule.enabled = not rule.enabled
    if app.save_settings then app.save_settings() end
  end
  r.ImGui_SameLine(ctx)
  draw_auto_target_combo(ctx, app, rule)
  if r.ImGui_NewLine then r.ImGui_NewLine(ctx) end
  if r.ImGui_BeginCombo(ctx, "Match##color_studio_auto_matcher", auto_matcher_label(rule.matcher)) then
    for _, matcher in ipairs(AUTO_MATCHERS) do
      local selected = rule.matcher == matcher.id
      if r.ImGui_Selectable(ctx, matcher.label .. "##auto_matcher_" .. matcher.id, selected) then
        rule.matcher = matcher.id
        if app.save_settings then app.save_settings() end
      end
      if selected then r.ImGui_SetItemDefaultFocus(ctx) end
    end
    r.ImGui_EndCombo(ctx)
  end
  r.ImGui_SameLine(ctx)
  changed, value = r.ImGui_InputTextWithHint(ctx, "Text##color_studio_auto_value", auto_target_hint(auto_rule_target(rule)), rule.value or "")
  if changed then rule.value = value; if app.save_settings then app.save_settings() end end
  draw_auto_color_slot(ctx, app, settings, rule)
end

local function auto_rule_summary_text(rule, index)
  local value = trim_text(rule.value or "")
  local name = value ~= "" and value or trim_text(rule.name or "")
  if name == "" then name = "Rule " .. tostring(index) end
  return tostring(index) .. ". " .. name
end

local function move_auto_rule(app, settings, from_index, to_index)
  from_index = tonumber(from_index)
  to_index = tonumber(to_index)
  local rules = settings.auto_rules or {}
  if not from_index or not to_index or from_index == to_index then return end
  if from_index < 1 or from_index > #rules or to_index < 1 or to_index > #rules then return end
  local selected = tonumber(settings.auto_rule_index) or 1
  local rule = table.remove(rules, from_index)
  table.insert(rules, to_index, rule)
  if selected == from_index then
    settings.auto_rule_index = to_index
  elseif from_index < selected and selected <= to_index then
    settings.auto_rule_index = selected - 1
  elseif to_index <= selected and selected < from_index then
    settings.auto_rule_index = selected + 1
  end
  renumber_auto_rule_names(settings)
  if app.save_settings then app.save_settings() end
  app.status = "Moved auto color rule"
end

local function begin_auto_rule_drag(ctx, index, label)
  if not (r.ImGui_BeginDragDropSource and r.ImGui_SetDragDropPayload) then return end
  if r.ImGui_BeginDragDropSource(ctx, 0) then
    r.ImGui_SetDragDropPayload(ctx, AUTO_RULE_PAYLOAD_TYPE, tostring(index))
    r.ImGui_Text(ctx, label)
    r.ImGui_EndDragDropSource(ctx)
  end
end

local function accept_auto_rule_drop(ctx, app, settings, to_index)
  if not (r.ImGui_BeginDragDropTarget and r.ImGui_AcceptDragDropPayload) then return end
  if r.ImGui_BeginDragDropTarget(ctx) then
    local ok, payload = r.ImGui_AcceptDragDropPayload(ctx, AUTO_RULE_PAYLOAD_TYPE)
    if ok then move_auto_rule(app, settings, tonumber(payload), to_index) end
    r.ImGui_EndDragDropTarget(ctx)
  end
end

local function draw_auto_rule_overview_label(ctx, app, settings, rule, index, label, text_color)
  local style_count = 0
  if r.ImGui_Col_Text then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), text_color); style_count = style_count + 1 end
  if r.ImGui_Selectable(ctx, label .. "##auto_rule_overview_select_" .. tostring(index), settings.auto_rule_index == index) then
    settings.auto_rule_index = index
    if app.save_settings then app.save_settings() end
  end
  if style_count > 0 then r.ImGui_PopStyleColor(ctx, style_count) end
  begin_auto_rule_drag(ctx, index, auto_rule_summary_text(rule, index))
  accept_auto_rule_drop(ctx, app, settings, index)
end

local function draw_auto_rules_overview(ctx, app, settings)
  r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Rules")
  if r.ImGui_BeginTable and r.ImGui_BeginTable(ctx, "##color_studio_auto_rules_overview", 3, auto_rules_overview_flags()) then
    setup_auto_rules_overview_columns(ctx)
    for index, rule in ipairs(settings.auto_rules or {}) do
      local color = tonumber(rule.color) or settings.active_color
      local text_color = rule.enabled and Theme.colors.text or Theme.colors.text_dim
      r.ImGui_TableNextColumn(ctx)
      draw_auto_rule_overview_label(ctx, app, settings, rule, index, auto_rule_summary_text(rule, index), text_color)
      r.ImGui_TableNextColumn(ctx)
      r.ImGui_TextColored(ctx, Theme.colors.text_dim, auto_target_label(auto_rule_target(rule)) .. " | " .. auto_matcher_label(rule.matcher) .. " | " .. tostring(count_auto_rule_matches(rule)))
      r.ImGui_TableNextColumn(ctx)
      if draw_swatch(ctx, "auto_rule_overview_color_" .. tostring(index), color, 18, settings.auto_rule_index == index) then
        settings.auto_rule_index = index
        if app.save_settings then app.save_settings() end
      end
      begin_auto_rule_drag(ctx, index, auto_rule_summary_text(rule, index))
      accept_auto_rule_drop(ctx, app, settings, index)
    end
    r.ImGui_EndTable(ctx)
    return
  end
  for index, rule in ipairs(settings.auto_rules or {}) do
    local color = tonumber(rule.color) or settings.active_color
    draw_auto_rule_overview_label(ctx, app, settings, rule, index, auto_rule_summary_text(rule, index) .. " | " .. auto_target_label(auto_rule_target(rule)) .. " | " .. auto_matcher_label(rule.matcher) .. " | " .. tostring(count_auto_rule_matches(rule)), rule.enabled and Theme.colors.text or Theme.colors.text_dim)
    r.ImGui_SameLine(ctx)
    if draw_swatch(ctx, "auto_rule_overview_color_" .. tostring(index), color, 18, settings.auto_rule_index == index) then
      settings.auto_rule_index = index
      if app.save_settings then app.save_settings() end
    end
    begin_auto_rule_drag(ctx, index, auto_rule_summary_text(rule, index))
    accept_auto_rule_drop(ctx, app, settings, index)
  end
end

local function draw_auto_tab(ctx, app, settings)
  r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Auto rules")
  draw_auto_rule_selector(ctx, app, settings)
  r.ImGui_Spacing(ctx)
  draw_auto_rule_editor(ctx, app, settings)
  r.ImGui_Separator(ctx)
  if draw_button(ctx, "Apply Auto", -1) then apply_auto_color(app, settings) end
  r.ImGui_TextColored(ctx, Theme.colors.text_dim, tostring(count_auto_matches(settings)) .. " matching track(s)")
  r.ImGui_Separator(ctx)
  draw_auto_rules_overview(ctx, app, settings)
end

function M.init(app)
  ensure_settings(app)
end

function M.draw(app)
  local ctx = app.ctx
  local settings = ensure_settings(app)
  local selected_track_count = r.CountSelectedTracks(0) or 0
  local selected_item_count = r.CountSelectedMediaItems(0) or 0
  local target_tracks, target_items, target_takes, target_markers, target_regions = selected_targets(settings)
  local active_target_count = target_total(target_tracks, target_items, target_takes, target_markers, target_regions)
  r.ImGui_Text(ctx, "Color Studio")
  r.ImGui_SameLine(ctx)
  r.ImGui_TextColored(ctx, Theme.colors.text_dim, tostring(selected_track_count) .. " tracks | " .. tostring(selected_item_count) .. " items | " .. tostring(active_target_count) .. " targets")
  r.ImGui_Separator(ctx)

  draw_view_tabs(ctx, app, settings)
  r.ImGui_Separator(ctx)

  local available_w, available_h = r.ImGui_GetContentRegionAvail(ctx)
  local content_h = math.max(40, (available_h or 240) - UI.info_line_height(ctx))

  if r.ImGui_BeginChild(ctx, "##color_studio_content", 0, content_h, 0) then
    if settings.view_mode == "auto" then
      draw_auto_tab(ctx, app, settings)
    else
      draw_manual_tab(ctx, app, settings, selected_item_count)
    end
    r.ImGui_EndChild(ctx)
  end

  UI.draw_info_line(ctx, "Color Studio | " .. target_label(settings, selected_item_count) .. " | " .. tostring(active_target_count) .. " target(s)")
end

return M