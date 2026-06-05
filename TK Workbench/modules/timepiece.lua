local r = reaper
local Theme = require("core.theme")
local UI = require("core.ui")

local M = {
  id = "timepiece",
  title = "Timepiece",
  icon = "TIM",
  version = "0.1.0"
}

local defaults = {
  display_mode = "time",
  show_bpm = true,
  show_signature = true,
  show_status = true,
  show_project_position = false,
  show_region_progress = false,
  show_play_rate = false,
  show_context_info = false,
  show_local_time = false,
  show_local_date = false,
  show_next_marker = false,
  clock_visibility = 1.0,
  clock_at_top = false,
  alarm_time_text = "09:00",
  alarm_target_epoch = 0,
  alarm_ringing = false,
  timer_duration_text = "00:05:00",
  timer_target_epoch = 0,
  timer_ringing = false,
  compact_controls = true
}

local state = {
  fonts = {}
}

local display_modes = {
  { id = "time", label = "Time" },
  { id = "local_clock", label = "Local clock" },
  { id = "measures", label = "Measures.Beats", mode = 2 },
  { id = "beats_ticks", label = "Beats.Ticks" },
  { id = "measures_time", label = "Measures + Time", mode = 1 },
  { id = "project", label = "Project default", mode = -1 },
  { id = "seconds", label = "Seconds", mode = 3 },
  { id = "samples", label = "Samples", mode = 4 },
  { id = "frames", label = "H:M:S:F", mode = 5 }
}

local function display_mode_def(id)
  for _, option in ipairs(display_modes) do
    if option.id == id then return option end
  end
  return display_modes[1]
end

local function ensure_settings(app)
  app.settings.timepiece = app.settings.timepiece or {}
  local settings = app.settings.timepiece
  local changed = false
  for key, value in pairs(defaults) do
    if settings[key] == nil then
      settings[key] = value
      changed = true
    end
  end
  local mode = display_mode_def(settings.display_mode)
  if settings.display_mode ~= mode.id then settings.display_mode = mode.id; changed = true end
  settings.clock_visibility = math.max(0.1, math.min(1.0, tonumber(settings.clock_visibility) or defaults.clock_visibility))
  settings.alarm_time_text = tostring(settings.alarm_time_text or defaults.alarm_time_text)
  settings.alarm_target_epoch = math.max(0, tonumber(settings.alarm_target_epoch) or 0)
  settings.alarm_ringing = settings.alarm_ringing == true
  settings.timer_duration_text = tostring(settings.timer_duration_text or defaults.timer_duration_text)
  settings.timer_target_epoch = math.max(0, tonumber(settings.timer_target_epoch) or 0)
  settings.timer_ringing = settings.timer_ringing == true
  if changed and app.save_settings then app.save_settings() end
  return settings
end

local function color_with_alpha(color, alpha)
  color = math.floor(tonumber(color) or 0)
  if color < 0 then color = color + 0x100000000 end
  alpha = math.floor(math.max(0, math.min(255, tonumber(alpha) or 255)) + 0.5)
  return (color & 0xFFFFFF00) | alpha
end

local function native_color_to_u32(native, alpha)
  native = tonumber(native) or 0
  if native == 0 then return nil end
  alpha = alpha or 0xEE
  if r.ColorFromNative then
    local ok, red, green, blue = pcall(r.ColorFromNative, native & 0xFFFFFF)
    if ok and red and green and blue then return ((red & 0xFF) << 24) | ((green & 0xFF) << 16) | ((blue & 0xFF) << 8) | (alpha & 0xFF) end
  end
  local red = native & 0xFF
  local green = (native >> 8) & 0xFF
  local blue = (native >> 16) & 0xFF
  return (red << 24) | (green << 16) | (blue << 8) | (alpha & 0xFF)
end

local function format_time(seconds)
  seconds = tonumber(seconds) or 0
  local sign = seconds < 0 and "-" or ""
  seconds = math.abs(seconds)
  local hours = math.floor(seconds / 3600)
  local minutes = math.floor((seconds % 3600) / 60)
  local whole = math.floor(seconds % 60)
  local millis = math.floor(((seconds % 1) * 1000) + 0.5)
  if millis >= 1000 then whole = whole + 1; millis = 0 end
  if whole >= 60 then minutes = minutes + 1; whole = 0 end
  if minutes >= 60 then hours = hours + 1; minutes = 0 end
  if hours > 0 then return string.format("%s%d:%02d:%02d.%03d", sign, hours, minutes, whole, millis) end
  return string.format("%s%02d:%02d.%03d", sign, minutes, whole, millis)
end

local function format_native_position(seconds, mode)
  if r.format_timestr_pos then
    local ok, value = pcall(r.format_timestr_pos, tonumber(seconds) or 0, "", mode)
    if ok and value and value ~= "" then return tostring(value) end
  end
  return format_time(seconds)
end

local function format_beats_ticks(seconds)
  if not r.TimeMap2_timeToBeats then return format_native_position(seconds, 2) end
  local ok, beat_pos, measures, cml = pcall(r.TimeMap2_timeToBeats, 0, tonumber(seconds) or 0)
  if not ok or beat_pos == nil then return format_native_position(seconds, 2) end
  local ticks_per_beat = 960
  local measure = math.floor(tonumber(measures) or 0) + 1
  local beat_value = math.max(0, tonumber(beat_pos) or 0)
  local beat = math.floor(beat_value) + 1
  local tick = math.floor(((beat_value % 1) * ticks_per_beat) + 0.5)
  if tick >= ticks_per_beat then beat = beat + 1; tick = 0 end
  local measure_len = math.floor(tonumber(cml) or 0)
  if measure_len > 0 and beat > measure_len then measure = measure + 1; beat = 1 end
  return string.format("%d.%d.%03d", measure, beat, tick)
end

local function format_measures_time(seconds)
  return format_native_position(seconds, 2) .. " | " .. format_time(seconds)
end

local function format_hms(seconds)
  seconds = math.max(0, math.floor((tonumber(seconds) or 0) + 0.5))
  local hours = math.floor(seconds / 3600)
  local minutes = math.floor((seconds % 3600) / 60)
  local whole = math.floor(seconds % 60)
  return string.format("%02d:%02d:%02d", hours, minutes, whole)
end

local function parse_time_of_day(text)
  local parts = {}
  for value in tostring(text or ""):gmatch("%d+") do parts[#parts + 1] = tonumber(value) or 0 end
  if #parts < 2 then return nil end
  local hour = math.floor(parts[1] or 0)
  local minute = math.floor(parts[2] or 0)
  local second = math.floor(parts[3] or 0)
  if hour < 0 or hour > 23 or minute < 0 or minute > 59 or second < 0 or second > 59 then return nil end
  return hour, minute, second
end

local function parse_duration(text)
  local parts = {}
  for value in tostring(text or ""):gmatch("%d+") do parts[#parts + 1] = tonumber(value) or 0 end
  local seconds = 0
  if #parts == 1 then seconds = parts[1] * 60 end
  if #parts == 2 then seconds = parts[1] * 60 + parts[2] end
  if #parts >= 3 then seconds = parts[1] * 3600 + parts[2] * 60 + parts[3] end
  seconds = math.floor(tonumber(seconds) or 0)
  if seconds <= 0 then return nil end
  return math.min(seconds, 24 * 3600)
end

local function next_alarm_epoch(text, now)
  local hour, minute, second = parse_time_of_day(text)
  if not hour then return nil end
  now = tonumber(now) or os.time()
  local date = os.date("*t", now)
  date.hour = hour
  date.min = minute
  date.sec = second or 0
  local target = os.time(date)
  if target <= now then target = target + 24 * 3600 end
  return target
end

local function format_clock_position(seconds, settings)
  local mode = display_mode_def(settings.display_mode)
  if mode.id == "time" then return format_time(seconds) end
  if mode.id == "local_clock" then return os.date("%H:%M:%S") or "--:--:--" end
  if mode.id == "beats_ticks" then return format_beats_ticks(seconds) end
  if mode.id == "measures_time" then return format_measures_time(seconds) end
  return format_native_position(seconds, mode.mode or 0)
end

local function play_state_info()
  local state = r.GetPlayState and (r.GetPlayState() or 0) or 0
  if state & 4 == 4 then return "Recording", Theme.colors.danger, state end
  if state & 2 == 2 then return "Paused", Theme.colors.warning, state end
  if state & 1 == 1 then return "Playing", Theme.colors.accent, state end
  return "Stopped", Theme.colors.text_dim, state
end

local function clock_position(play_state)
  play_state = tonumber(play_state) or 0
  if play_state ~= 0 then return r.GetPlayPosition and r.GetPlayPosition() or 0, "play position" end
  return r.GetCursorPosition and r.GetCursorPosition() or 0, "edit cursor"
end

local function project_signature()
  if r.GetProjectTimeSignature2 then
    local ok, bpm, numerator, denominator = pcall(r.GetProjectTimeSignature2, 0)
    if ok then return tonumber(bpm), tonumber(numerator) or 4, tonumber(denominator) or 4 end
  end
  return r.Master_GetTempo and r.Master_GetTempo() or 120, 4, 4
end

local function project_position_label(seconds)
  if not r.TimeMap2_timeToBeats or not r.GetProjectLength then return nil end
  local ok_pos, _, measures = pcall(r.TimeMap2_timeToBeats, 0, tonumber(seconds) or 0)
  local ok_len, project_length = pcall(r.GetProjectLength, 0)
  if not ok_pos or not ok_len or measures == nil or project_length == nil then return nil end
  local ok_end, _, end_measures = pcall(r.TimeMap2_timeToBeats, 0, math.max(0, tonumber(project_length) or 0))
  if not ok_end or end_measures == nil then return nil end
  local current = math.max(1, math.floor((tonumber(measures) or 0) + 1))
  local total = math.max(current, math.floor((tonumber(end_measures) or 0) + 1))
  local digits = math.max(2, #tostring(total))
  return string.format("%0" .. tostring(digits) .. "d/%0" .. tostring(digits) .. "d", current, total)
end

local function play_rate_label()
  if r.Master_GetPlayRate then
    local ok, rate = pcall(r.Master_GetPlayRate, 0)
    if ok and rate then return string.format("%.3fx", tonumber(rate) or 1) end
  end
  return "1.000x"
end

local function context_info_badge(region, seconds)
  if region then return "REM", format_time(math.max(0, (tonumber(region.region_end) or 0) - (tonumber(seconds) or 0))) end
  if r.GetProjectLength then
    local ok, length = pcall(r.GetProjectLength, 0)
    if ok and length then return "LEN", format_time(length) end
  end
  return nil, nil
end

local function local_time_label()
  return os.date("%H:%M:%S") or "--:--:--"
end

local function local_date_label()
  return os.date("%d-%m-%y") or "--"
end

local function status_line_text(settings, status_text, project_label)
  local parts = {}
  if settings.show_status ~= false then parts[#parts + 1] = status_text end
  if settings.show_project_position ~= false and project_label then parts[#parts + 1] = project_label end
  return table.concat(parts, "  ")
end

local function active_region_at(seconds)
  if not r.CountProjectMarkers or not r.EnumProjectMarkers3 then return nil end
  seconds = tonumber(seconds) or 0
  local ok_count, marker_count, region_count = r.CountProjectMarkers(0)
  local total = ((marker_count or 0) + (region_count or 0))
  if not ok_count or total <= 0 then return nil end
  local region
  for index = 0, total - 1 do
    local ok, is_region, pos, region_end, name, number, color = r.EnumProjectMarkers3(0, index)
    pos = tonumber(pos) or 0
    region_end = tonumber(region_end) or pos
    if ok and is_region and region_end > pos and seconds >= pos and seconds <= region_end then
      if not region or pos >= region.pos then region = { pos = pos, region_end = region_end, name = name or "Region", number = number or 0, color = color or 0 } end
    end
  end
  if not region then return nil end
  region.progress = math.max(0, math.min(1, (seconds - region.pos) / math.max(0.000001, region.region_end - region.pos)))
  return region
end

local function next_marker_badge(seconds)
  if not r.CountProjectMarkers or not r.EnumProjectMarkers3 then return "NEXT", "No marker" end
  seconds = tonumber(seconds) or 0
  local ok_count, marker_count, region_count = r.CountProjectMarkers(0)
  local total = (marker_count or 0) + (region_count or 0)
  if not ok_count or total <= 0 then return "NEXT", "No marker" end
  local marker
  for index = 0, total - 1 do
    local ok, is_region, pos, _, name, number = r.EnumProjectMarkers3(0, index)
    pos = tonumber(pos) or 0
    if ok and not is_region and pos > seconds then
      if not marker or pos < marker.pos then marker = { pos = pos, name = name or "Marker", number = number or 0 } end
    end
  end
  if not marker then return "NEXT", "No next marker" end
  local name = tostring(marker.name or "") ~= "" and tostring(marker.name) or ("#" .. tostring(marker.number or 0))
  return "NEXT", format_time(marker.pos - seconds) .. " " .. name
end

local function update_alarm_state(app, settings)
  local now = os.time()
  local changed = false
  if settings.alarm_target_epoch > 0 and now >= settings.alarm_target_epoch and settings.alarm_ringing ~= true then
    settings.alarm_ringing = true
    changed = true
    app.status = "Timepiece alarm"
  end
  if settings.timer_target_epoch > 0 and now >= settings.timer_target_epoch and settings.timer_ringing ~= true then
    settings.timer_ringing = true
    changed = true
    app.status = "Timepiece timer"
  end
  if changed and app.save_settings then app.save_settings() end
end

local function alarm_items(settings)
  local now = os.time()
  local items = {}
  if settings.alarm_ringing == true then
    items[#items + 1] = { label = "ALARM", value = "Time " .. tostring(settings.alarm_time_text or ""), color = Theme.colors.danger }
  elseif (tonumber(settings.alarm_target_epoch) or 0) > 0 then
    items[#items + 1] = { label = "ALARM", value = format_hms((tonumber(settings.alarm_target_epoch) or now) - now), color = Theme.colors.warning }
  end
  if settings.timer_ringing == true then
    items[#items + 1] = { label = "TIMER", value = "Done", color = Theme.colors.danger }
  elseif (tonumber(settings.timer_target_epoch) or 0) > 0 then
    items[#items + 1] = { label = "TIMER", value = format_hms((tonumber(settings.timer_target_epoch) or now) - now), color = Theme.colors.accent }
  end
  return items
end

local function calc_text_width(ctx, value)
  if r.ImGui_CalcTextSize then
    local width = r.ImGui_CalcTextSize(ctx, tostring(value or ""))
    return tonumber(width) or 0
  end
  return #(tostring(value or "")) * 7
end

local function fit_text(ctx, text, width)
  text = tostring(text or "")
  if calc_text_width(ctx, text) <= width then return text end
  local suffix = "..."
  while #text > 1 and calc_text_width(ctx, text .. suffix) > width do
    text = text:sub(1, #text - 1)
  end
  return text .. suffix
end

local function draw_centered_text(ctx, text, color, width)
  local text_w = calc_text_width(ctx, text)
  local x, y = r.ImGui_GetCursorScreenPos(ctx)
  r.ImGui_SetCursorScreenPos(ctx, x + math.max(0, ((width or text_w) - text_w) * 0.5), y)
  r.ImGui_TextColored(ctx, color, text)
end

local function get_clock_font(ctx, font_size)
  if not r.ImGui_CreateFont then return nil end
  font_size = math.max(14, math.floor((tonumber(font_size) or 24) + 0.5))
  local key = tostring(font_size)
  if state.fonts[key] then return state.fonts[key] end
  local ok, font = pcall(r.ImGui_CreateFont, "sans-serif", font_size)
  if not ok or not font then return nil end
  if r.ImGui_Attach then pcall(r.ImGui_Attach, ctx, font) end
  state.fonts[key] = font
  return font
end

local function draw_clock_text(ctx, draw_list, text, color, x, y, width, height, align_top)
  local current_size = r.ImGui_GetFontSize and (r.ImGui_GetFontSize(ctx) or 13) or 13
  local base_w = math.max(1, calc_text_width(ctx, text))
  local width_size = current_size * (math.max(1, width) / base_w)
  local font_size = math.max(current_size, math.min(width_size, math.max(current_size, height * 0.92)))
  local font = get_clock_font(ctx, font_size)
  local scale = font_size / math.max(1, current_size)
  local text_w = base_w * scale
  local text_x = x + math.max(0, (width - text_w) * 0.5)
  local text_y = align_top and y or (y + math.max(0, (height - font_size) * 0.5))
  if r.ImGui_DrawList_AddTextEx and font then
    local ok = pcall(r.ImGui_DrawList_AddTextEx, draw_list, font, font_size, text_x, text_y, color, text)
    if ok then return end
  end
  r.ImGui_DrawList_AddText(draw_list, text_x, text_y, color, text)
end

local function draw_badge(ctx, label, value, width)
  local draw_list = r.ImGui_GetWindowDrawList(ctx)
  local x, y = r.ImGui_GetCursorScreenPos(ctx)
  local height = 26
  r.ImGui_InvisibleButton(ctx, "##badge_" .. label, width, height)
  local hovered = r.ImGui_IsItemHovered(ctx)
  local bg = hovered and Theme.colors.frame_hover or Theme.colors.frame_bg
  r.ImGui_DrawList_AddRectFilled(draw_list, x, y, x + width, y + height, bg, 5)
  r.ImGui_DrawList_AddRect(draw_list, x, y, x + width, y + height, Theme.colors.border, 5, 0, 1)
  r.ImGui_DrawList_AddText(draw_list, x + 8, y + 6, Theme.colors.text_dim, label)
  local label_w = calc_text_width(ctx, label)
  local value_text = fit_text(ctx, tostring(value or "-"), math.max(20, width - label_w - 26))
  local value_w = calc_text_width(ctx, value_text)
  r.ImGui_DrawList_AddText(draw_list, x + width - value_w - 8, y + 6, Theme.colors.text, value_text)
end

local function draw_alarm_bar(ctx, item, width)
  local draw_list = r.ImGui_GetWindowDrawList(ctx)
  local x, y = r.ImGui_GetCursorScreenPos(ctx)
  local height = 26
  local color = item.color or Theme.colors.accent
  r.ImGui_InvisibleButton(ctx, "##alarm_" .. tostring(item.label), width, height)
  local bg = r.ImGui_IsItemHovered(ctx) and color_with_alpha(color, 0x38) or color_with_alpha(color, 0x24)
  r.ImGui_DrawList_AddRectFilled(draw_list, x, y, x + width, y + height, bg, 5)
  r.ImGui_DrawList_AddRect(draw_list, x, y, x + width, y + height, color_with_alpha(color, 0xAA), 5, 0, 1)
  r.ImGui_DrawList_AddText(draw_list, x + 8, y + 6, Theme.colors.text_dim, item.label)
  local label_w = calc_text_width(ctx, item.label)
  local value_text = fit_text(ctx, tostring(item.value or "-"), math.max(20, width - label_w - 26))
  local value_w = calc_text_width(ctx, value_text)
  r.ImGui_DrawList_AddText(draw_list, x + width - value_w - 8, y + 6, Theme.colors.text, value_text)
end

local function add_badge(items, label, value)
  if label and value then items[#items + 1] = { label = label, value = value } end
end

local function draw_badge_items(ctx, items, x, y, width, row_h, gap)
  if #items == 0 then return end
  local badge_w = math.max(80, (width - gap) * 0.5)
  for index, item in ipairs(items) do
    local column = (index - 1) % 2
    local row = math.floor((index - 1) / 2)
    r.ImGui_SetCursorScreenPos(ctx, x + column * (badge_w + gap), y + row * (row_h + gap))
    draw_badge(ctx, item.label, item.value, badge_w)
  end
end

local function draw_alarm_items(ctx, items, x, y, width, row_h, gap)
  for index, item in ipairs(items) do
    r.ImGui_SetCursorScreenPos(ctx, x, y + (index - 1) * (row_h + gap))
    draw_alarm_bar(ctx, item, width)
  end
end

local function draw_region_progress(ctx, draw_list, region, x, y, width)
  if not region then return end
  local height = 22
  local fill = native_color_to_u32(region.color, 0xEE) or Theme.colors.accent
  local track = color_with_alpha(fill, 0x24)
  local progress = math.max(0, math.min(1, tonumber(region.progress) or 0))
  local label = fit_text(ctx, tostring(region.name or "Region") .. "  " .. tostring(math.floor(progress * 100 + 0.5)) .. "%", math.max(24, width - 18))
  local label_w = calc_text_width(ctx, label)
  r.ImGui_SetCursorScreenPos(ctx, x, y)
  r.ImGui_InvisibleButton(ctx, "##timepiece_region_progress", width, height)
  if r.ImGui_IsItemHovered(ctx) then
    r.ImGui_SetTooltip(ctx, tostring(region.name or "Region") .. " " .. tostring(math.floor(progress * 100 + 0.5)) .. "%")
  end
  r.ImGui_DrawList_AddRectFilled(draw_list, x, y, x + width, y + height, track, 4)
  r.ImGui_DrawList_AddRectFilled(draw_list, x, y, x + width * progress, y + height, fill, 4)
  r.ImGui_DrawList_AddRect(draw_list, x, y, x + width, y + height, color_with_alpha(fill, 0x88), 4, 0, 1)
  r.ImGui_DrawList_AddText(draw_list, x + math.max(8, (width - label_w) * 0.5), y + 4, Theme.colors.text, label)
end

local function draw_toggle(ctx, app, settings, key, label)
  local changed, value = r.ImGui_Checkbox(ctx, label, settings[key] ~= false)
  if changed then
    settings[key] = value
    app.status = "Timepiece " .. label .. (value and " shown" or " hidden")
    if app.save_settings then app.save_settings() end
  end
end

local function push_slider_style(ctx)
  local count = 0
  if r.ImGui_Col_FrameBg then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), Theme.colors.frame_bg); count = count + 1 end
  if r.ImGui_Col_FrameBgHovered then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgHovered(), Theme.colors.frame_hover); count = count + 1 end
  if r.ImGui_Col_FrameBgActive then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgActive(), Theme.colors.accent_soft); count = count + 1 end
  if r.ImGui_Col_SliderGrab then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrab(), Theme.colors.accent); count = count + 1 end
  if r.ImGui_Col_SliderGrabActive then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrabActive(), Theme.colors.text); count = count + 1 end
  return count
end

local function pop_slider_style(ctx, count)
  if count and count > 0 then r.ImGui_PopStyleColor(ctx, count) end
end

local function draw_visibility_slider(ctx, app, settings)
  r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Clock text")
  r.ImGui_SetNextItemWidth(ctx, 180)
  local style_count = push_slider_style(ctx)
  local shown = (settings.clock_visibility or 1.0) * 100
  local changed, value = r.ImGui_SliderDouble(ctx, "Visibility##timepiece_clock_visibility", shown, 10, 100, "%.0f%%")
  pop_slider_style(ctx, style_count)
  if changed then
    settings.clock_visibility = math.max(0.1, math.min(1.0, (tonumber(value) or 100) / 100))
    app.status = "Timepiece clock visibility: " .. tostring(math.floor(settings.clock_visibility * 100 + 0.5)) .. "%"
    if app.save_settings then app.save_settings() end
  end
end

local function draw_display_mode_combo(ctx, app, settings)
  local current = display_mode_def(settings.display_mode)
  r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Display")
  r.ImGui_SetNextItemWidth(ctx, 180)
  if r.ImGui_BeginCombo(ctx, "##timepiece_display_mode", current.label) then
    for _, option in ipairs(display_modes) do
      local selected = settings.display_mode == option.id
      if r.ImGui_Selectable(ctx, option.label .. "##timepiece_mode_" .. option.id, selected) then
        settings.display_mode = option.id
        app.status = "Timepiece display: " .. option.label
        if app.save_settings then app.save_settings() end
      end
    end
    r.ImGui_EndCombo(ctx)
  end
end

local function draw_alarm_settings(ctx, app, settings)
  r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Alarm")
  r.ImGui_SetNextItemWidth(ctx, 110)
  local changed, value = r.ImGui_InputText(ctx, "Time##timepiece_alarm_time", settings.alarm_time_text or defaults.alarm_time_text)
  if changed then settings.alarm_time_text = value; if app.save_settings then app.save_settings() end end
  local alarm_active = settings.alarm_target_epoch > 0 or settings.alarm_ringing == true
  if r.ImGui_Button(ctx, alarm_active and "Stop alarm##timepiece_alarm" or "Arm alarm##timepiece_alarm", 110, 0) then
    if alarm_active then
      settings.alarm_target_epoch = 0
      settings.alarm_ringing = false
      app.status = "Timepiece alarm stopped"
    else
      local target = next_alarm_epoch(settings.alarm_time_text)
      if target then
        settings.alarm_target_epoch = target
        settings.alarm_ringing = false
        app.status = "Timepiece alarm armed for " .. tostring(settings.alarm_time_text)
      else
        app.status = "Timepiece alarm time must be HH:MM"
      end
    end
    if app.save_settings then app.save_settings() end
  end
  if settings.alarm_target_epoch > 0 and settings.alarm_ringing ~= true then
    r.ImGui_SameLine(ctx)
    r.ImGui_TextColored(ctx, Theme.colors.text_dim, format_hms(settings.alarm_target_epoch - os.time()))
  end
  r.ImGui_Separator(ctx)
  r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Timer")
  r.ImGui_SetNextItemWidth(ctx, 110)
  changed, value = r.ImGui_InputText(ctx, "Duration##timepiece_timer_duration", settings.timer_duration_text or defaults.timer_duration_text)
  if changed then settings.timer_duration_text = value; if app.save_settings then app.save_settings() end end
  local timer_active = settings.timer_target_epoch > 0 or settings.timer_ringing == true
  if r.ImGui_Button(ctx, timer_active and "Stop timer##timepiece_timer" or "Start timer##timepiece_timer", 110, 0) then
    if timer_active then
      settings.timer_target_epoch = 0
      settings.timer_ringing = false
      app.status = "Timepiece timer stopped"
    else
      local duration = parse_duration(settings.timer_duration_text)
      if duration then
        settings.timer_target_epoch = os.time() + duration
        settings.timer_ringing = false
        app.status = "Timepiece timer started: " .. format_hms(duration)
      else
        app.status = "Timepiece timer duration must be MM:SS or HH:MM:SS"
      end
    end
    if app.save_settings then app.save_settings() end
  end
  if settings.timer_target_epoch > 0 and settings.timer_ringing ~= true then
    r.ImGui_SameLine(ctx)
    r.ImGui_TextColored(ctx, Theme.colors.text_dim, format_hms(settings.timer_target_epoch - os.time()))
  end
end

local function draw_settings_button(ctx, app, settings, x, y, width)
  local button_h = r.ImGui_GetFrameHeight(ctx)
  r.ImGui_SetCursorScreenPos(ctx, x + width - button_h - 6, y + 8)
  if r.ImGui_Button(ctx, "...##timepiece_settings", button_h, button_h) then r.ImGui_OpenPopup(ctx, "##timepiece_settings_popup") end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Timepiece settings") end
  if r.ImGui_BeginPopup(ctx, "##timepiece_settings_popup") then
    r.ImGui_TextColored(ctx, Theme.colors.accent, "Timepiece")
    r.ImGui_Separator(ctx)
    draw_toggle(ctx, app, settings, "show_status", "Status")
    draw_toggle(ctx, app, settings, "show_project_position", "Project position")
    draw_toggle(ctx, app, settings, "show_bpm", "BPM")
    draw_toggle(ctx, app, settings, "show_signature", "Signature")
    draw_toggle(ctx, app, settings, "show_play_rate", "Rate")
    draw_toggle(ctx, app, settings, "show_context_info", "Context info")
    draw_toggle(ctx, app, settings, "show_local_time", "Local time")
    draw_toggle(ctx, app, settings, "show_local_date", "Local date")
    draw_toggle(ctx, app, settings, "show_next_marker", "Next marker")
    draw_toggle(ctx, app, settings, "show_region_progress", "Region progress")
    draw_toggle(ctx, app, settings, "clock_at_top", "Clock at top")
    r.ImGui_Separator(ctx)
    draw_display_mode_combo(ctx, app, settings)
    r.ImGui_Separator(ctx)
    draw_visibility_slider(ctx, app, settings)
    r.ImGui_Separator(ctx)
    draw_alarm_settings(ctx, app, settings)
    r.ImGui_EndPopup(ctx)
  end
end

function M.draw(app)
  local ctx = app.ctx
  local settings = ensure_settings(app)
  update_alarm_state(app, settings)
  local available_w, available_h = r.ImGui_GetContentRegionAvail(ctx)
  local width = math.max(120, available_w or 320)
  local height = math.max(90, (available_h or 240) - UI.info_line_height(ctx))
  local status_text, status_color, play_state = play_state_info()
  local source_time, source_label = clock_position(play_state)
  local time_text = format_clock_position(source_time, settings)
  local clock_color = (settings.alarm_ringing == true or settings.timer_ringing == true) and Theme.colors.danger or Theme.colors.text
  local bpm, numerator, denominator = project_signature()
  local mode = display_mode_def(settings.display_mode)
  local needs_region = settings.show_region_progress ~= false or settings.show_context_info ~= false
  local region = needs_region and active_region_at(source_time) or nil
  local project_label = settings.show_project_position ~= false and project_position_label(source_time) or nil
  local top_text = status_line_text(settings, status_text, project_label)
  local show_top_text = top_text ~= ""
  local context_label, context_value = nil, nil
  if settings.show_context_info ~= false then context_label, context_value = context_info_badge(region, source_time) end
  local next_marker_label, next_marker_value = nil, nil
  if settings.show_next_marker ~= false then next_marker_label, next_marker_value = next_marker_badge(source_time) end
  local primary_badges = {}
  local extra_badges = {}
  if settings.show_bpm ~= false then add_badge(primary_badges, "BPM", string.format("%.2f", bpm or 0)) end
  if settings.show_signature ~= false then add_badge(primary_badges, "SIG", tostring(math.floor((numerator or 4) + 0.5)) .. "/" .. tostring(math.floor((denominator or 4) + 0.5))) end
  if settings.show_play_rate ~= false then add_badge(extra_badges, "RATE", play_rate_label()) end
  if settings.show_context_info ~= false then add_badge(extra_badges, context_label, context_value) end
  if settings.show_local_time ~= false then add_badge(extra_badges, "TIME", local_time_label()) end
  if settings.show_local_date ~= false then add_badge(extra_badges, "DATE", local_date_label()) end
  local show_next_marker_badge = settings.show_next_marker ~= false
  local alarms = alarm_items(settings)

  if r.ImGui_BeginChild(ctx, "##timepiece_surface", 0, height, 0) then
    local draw_list = r.ImGui_GetWindowDrawList(ctx)
    local x, y = r.ImGui_GetCursorScreenPos(ctx)
    local panel_h = math.max(74, height)
    r.ImGui_DrawList_AddRectFilled(draw_list, x, y, x + width, y + panel_h, Theme.colors.child_bg, 6)
    r.ImGui_DrawList_AddRect(draw_list, x, y, x + width, y + panel_h, Theme.colors.border, 6, 0, 1)
    draw_settings_button(ctx, app, settings, x, y, width)
    r.ImGui_SetCursorScreenPos(ctx, x + 12, y + 12)
    if show_top_text then draw_centered_text(ctx, top_text, settings.show_status ~= false and status_color or Theme.colors.text_dim, width - 24) end
    local line_h = r.ImGui_GetTextLineHeight(ctx)
    local clock_w = math.max(40, width - 22)
    local info_x = x + 6
    local info_w = math.max(40, width - 12)
    local top_reserved = show_top_text and (line_h + (settings.clock_at_top ~= false and 8 or 22)) or (settings.clock_at_top ~= false and 8 or 12)
    local badge_row_h = 26
    local badge_gap = 6
    local primary_rows = #primary_badges > 0 and 1 or 0
    local extra_rows = math.ceil(#extra_badges / 2)
    local badge_rows = primary_rows + extra_rows
    local badge_area_h = badge_rows > 0 and (badge_rows * badge_row_h + (badge_rows - 1) * badge_gap) or 0
    local show_region_bar = settings.show_region_progress ~= false and region ~= nil
    local region_bar_h = show_region_bar and 22 or 0
    local next_marker_h = show_next_marker_badge and badge_row_h or 0
    local alarm_area_h = #alarms > 0 and (#alarms * badge_row_h + (#alarms - 1) * badge_gap) or 0
    local stack_h = badge_area_h
    if next_marker_h > 0 then stack_h = stack_h + (stack_h > 0 and badge_gap or 0) + next_marker_h end
    if alarm_area_h > 0 then stack_h = stack_h + (stack_h > 0 and badge_gap or 0) + alarm_area_h end
    if region_bar_h > 0 then stack_h = stack_h + (stack_h > 0 and 8 or 0) + region_bar_h end
    local bottom_reserved = stack_h + 18
    local clock_h = math.max(line_h, panel_h - top_reserved - bottom_reserved)
    draw_clock_text(ctx, draw_list, time_text, color_with_alpha(clock_color, (settings.clock_visibility or 1.0) * 255), x, y + top_reserved, clock_w, clock_h, settings.clock_at_top ~= false)
    local stack_y = y + panel_h - 10
    local stack_has_items = false
    local function stack_reserve(item_h, gap_h)
      if item_h <= 0 then return stack_y end
      if stack_has_items then stack_y = stack_y - gap_h end
      stack_y = stack_y - item_h
      stack_has_items = true
      return stack_y
    end
    if alarm_area_h > 0 then
      local alarm_y = stack_reserve(alarm_area_h, badge_gap)
      draw_alarm_items(ctx, alarms, info_x, alarm_y, info_w, badge_row_h, badge_gap)
    end
    local badge_y = stack_reserve(badge_area_h, badge_gap)
    draw_badge_items(ctx, primary_badges, info_x, badge_y, info_w, badge_row_h, badge_gap)
    draw_badge_items(ctx, extra_badges, info_x, badge_y + primary_rows * (badge_row_h + badge_gap), info_w, badge_row_h, badge_gap)
    if show_next_marker_badge then
      local marker_y = stack_reserve(next_marker_h, badge_gap)
      r.ImGui_SetCursorScreenPos(ctx, info_x, marker_y)
      draw_badge(ctx, next_marker_label or "NEXT", next_marker_value or "No marker", info_w)
    end
    if show_region_bar then
      local region_y = stack_reserve(region_bar_h, 8)
      draw_region_progress(ctx, draw_list, region, info_x, region_y, info_w)
    end
    r.ImGui_EndChild(ctx)
  end
  UI.draw_info_line(ctx, "Timepiece | " .. mode.label .. " | " .. (mode.id == "local_clock" and "local time" or source_label) .. " | " .. status_text)
end

return M