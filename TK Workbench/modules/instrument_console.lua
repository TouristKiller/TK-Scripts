local r = reaper
local Theme = require("core.theme")
local UI = require("core.ui")
local UIScale = require("core.ui_scale")

local M = {
  id = "instrument_console",
  title = "Instrument Console",
  icon = "INS",
  version = "0.1.0"
}

local defaults = {
  search_term = "",
  view_mode = "list",
  close_others_on_open = true,
  close_scope = "instruments",
  lock_window_position = true,
  window_x = 240,
  window_y = 140,
  window_w = 960,
  window_h = 640,
  select_track_on_open = true,
  include_hidden_tracks = true,
  selected_tracks_only = false,
  sort_mode = "track",
  show_screenshots = false,
  screenshot_height = 74,
  show_bypassed = true,
  last_active_guid = "",
  last_active_fx = -1
}

local state = {
  entries = {},
  screenshot_path = r.GetResourcePath() .. "/Scripts/TK Scripts/FX/Screenshots/",
  screenshot_index = nil,
  screenshot_cache = {},
  screenshot_missing = {},
  last_project_count = nil,
  last_scan_time = 0,
  pending_position = nil,
  status = "Ready"
}

local function ensure_settings(app)
  app.settings.instrument_console = app.settings.instrument_console or {}
  local settings = app.settings.instrument_console
  local changed = false
  for key, value in pairs(defaults) do
    if settings[key] == nil then
      settings[key] = value
      changed = true
    end
  end
  if changed and app.save_settings then app.save_settings() end
  return settings
end

local function validate_track(track)
  if not track then return false end
  if r.ValidatePtr2 then return r.ValidatePtr2(0, track, "MediaTrack*") end
  if r.ValidatePtr then return r.ValidatePtr(track, "MediaTrack*") end
  return true
end

local function track_guid(track)
  if not validate_track(track) then return "" end
  return r.GetTrackGUID(track) or ""
end

local function find_track_by_guid(guid)
  if not guid or guid == "" then return nil end
  if r.BR_GetMediaTrackByGUID then
    local track = r.BR_GetMediaTrackByGUID(0, guid)
    if validate_track(track) then return track end
  end
  for index = 0, r.CountTracks(0) - 1 do
    local track = r.GetTrack(0, index)
    if validate_track(track) and r.GetTrackGUID(track) == guid then return track end
  end
  return nil
end

local function get_track_name(track, index)
  local _, name = r.GetTrackName(track)
  if not name or name == "" then name = "Track " .. tostring(index + 1) end
  return name
end

local function get_fx_name(track, fx_index)
  local _, name = r.TrackFX_GetFXName(track, fx_index, "")
  name = tostring(name or "Instrument")
  name = name:gsub("^%s+", ""):gsub("%s+$", "")
  return name ~= "" and name or "Instrument"
end

local function strip_x86(value)
  value = tostring(value or "")
  value = value:gsub("%s*%([xX]86%)", "")
  value = value:gsub("%s*%([xX]64%)", "")
  return value
end

local function clean_fx_name(value)
  local name = strip_x86(value)
  name = name:gsub("^[%w%d]+i?:%s*", "")
  name = name:gsub("%(%w+ ?%w*%)$", "")
  name = name:gsub("%s+$", "")
  return name
end

local function normalize_plugin_name(value)
  local name = tostring(value or ""):lower()
  name = name:gsub("^vst3i?:%s*", "")
  name = name:gsub("^vsti?:%s*", "")
  name = name:gsub("^vst3:%s*", "")
  name = name:gsub("^vst:%s*", "")
  name = name:gsub("^jsfx:%s*", "")
  name = name:gsub("^js:%s*", "")
  name = name:gsub("^clapi?:%s*", "")
  name = name:gsub("^clap:%s*", "")
  name = name:gsub("^au:%s*", "")
  name = name:gsub("^lv2i?:%s*", "")
  name = name:gsub("%s+$", "")
  name = name:gsub("%s+", " ")
  name = name:gsub("[^%w]+", "")
  return name
end

local function file_exists(path)
  if r.file_exists then return r.file_exists(path) end
  local file = io.open(path, "rb")
  if file then file:close(); return true end
  return false
end

local function build_screenshot_index(force)
  if state.screenshot_index and not force then return end
  state.screenshot_index = {}
  if not file_exists(state.screenshot_path) then return end
  local index = 0
  while true do
    local file_name = r.EnumerateFiles(state.screenshot_path, index)
    if not file_name then break end
    local base = file_name:match("(.+)%.png$") or file_name:match("(.+)%.jpg$") or file_name:match("(.+)%.jpeg$")
    if base then state.screenshot_index[normalize_plugin_name(base)] = file_name end
    index = index + 1
  end
end

local function get_screenshot_path(plugin_name)
  if not plugin_name or plugin_name == "" then return nil end
  local now = r.time_precise and r.time_precise() or os.clock()
  local missing = state.screenshot_missing[plugin_name]
  if missing and now - missing < 600 then return nil end
  local cached = state.screenshot_cache[plugin_name]
  if cached and cached.path then
    cached.t = now
    return cached.path
  end
  build_screenshot_index(false)
  local indexed = state.screenshot_index and state.screenshot_index[normalize_plugin_name(plugin_name)]
  if indexed then
    local path = state.screenshot_path .. indexed
    state.screenshot_cache[plugin_name] = { path = path, t = now }
    state.screenshot_missing[plugin_name] = nil
    return path
  end
  local cleaned = clean_fx_name(plugin_name)
  local variants = {
    plugin_name,
    plugin_name:gsub("[^%w%s%-]", "_"),
    cleaned,
    cleaned:gsub("[^%w%s%-]", "_"),
    strip_x86(plugin_name),
    clean_fx_name(strip_x86(plugin_name))
  }
  local seen = {}
  for _, base in ipairs(variants) do
    if base and base ~= "" and not seen[base] then
      seen[base] = true
      for _, ext in ipairs({ ".png", ".jpg", ".jpeg" }) do
        local path = state.screenshot_path .. base .. ext
        if file_exists(path) then
          state.screenshot_cache[plugin_name] = { path = path, t = now }
          state.screenshot_missing[plugin_name] = nil
          return path
        end
      end
    end
  end
  state.screenshot_missing[plugin_name] = now
  return nil
end

local function get_screenshot_image(ctx, plugin_name)
  if not r.ImGui_CreateImage then return nil end
  local path = get_screenshot_path(plugin_name)
  if not path then return nil end
  local entry = state.screenshot_cache[plugin_name]
  if entry and entry.img then
    if not r.ImGui_ValidatePtr or r.ImGui_ValidatePtr(entry.img, "ImGui_Image*") then
      entry.t = r.time_precise and r.time_precise() or os.clock()
      return entry.img
    end
  end
  local ok, img = pcall(r.ImGui_CreateImage, path)
  if ok and img then
    if r.ImGui_Attach then pcall(r.ImGui_Attach, ctx, img) end
    entry = entry or { path = path }
    entry.img = img
    entry.t = r.time_precise and r.time_precise() or os.clock()
    state.screenshot_cache[plugin_name] = entry
    return img
  end
  return nil
end

local function track_visible(track)
  local tcp = r.GetMediaTrackInfo_Value(track, "B_SHOWINTCP") or 0
  local mcp = r.GetMediaTrackInfo_Value(track, "B_SHOWINMIXER") or 0
  return tcp > 0 or mcp > 0
end

local function selected_track(track)
  return r.IsTrackSelected and r.IsTrackSelected(track) == true
end

local function fx_enabled(track, fx_index)
  if r.TrackFX_GetEnabled then return r.TrackFX_GetEnabled(track, fx_index) == true end
  return true
end

local function fx_offline(track, fx_index)
  if r.TrackFX_GetOffline then return r.TrackFX_GetOffline(track, fx_index) == true end
  return false
end

local function compare_entries(a, b)
  if a.track_index ~= b.track_index then return a.track_index < b.track_index end
  return tostring(a.fx_name):lower() < tostring(b.fx_name):lower()
end

local function compare_entries_by_name(a, b)
  local afx = tostring(a.fx_name or ""):lower()
  local bfx = tostring(b.fx_name or ""):lower()
  if afx ~= bfx then return afx < bfx end
  return compare_entries(a, b)
end

local function scan_instruments(app, force)
  local settings = ensure_settings(app)
  local project_count = r.GetProjectStateChangeCount and r.GetProjectStateChangeCount(0) or 0
  local now = r.time_precise and r.time_precise() or os.clock()
  if not force and state.last_project_count == project_count and now - state.last_scan_time < 1.0 then return end
  state.last_project_count = project_count
  state.last_scan_time = now
  local entries = {}
  local track_count = r.CountTracks(0)
  for index = 0, track_count - 1 do
    local track = r.GetTrack(0, index)
    if validate_track(track) then
      local fx_index = r.TrackFX_GetInstrument and r.TrackFX_GetInstrument(track) or -1
      if fx_index and fx_index >= 0 then
        local visible = track_visible(track)
        local selected = selected_track(track)
        local enabled = fx_enabled(track, fx_index)
        if (settings.include_hidden_tracks or visible) and (not settings.selected_tracks_only or selected) and (settings.show_bypassed or enabled) then
          local guid = track_guid(track)
          entries[#entries + 1] = {
            id = guid .. ":" .. tostring(fx_index),
            track_guid = guid,
            track_index = index + 1,
            track_name = get_track_name(track, index),
            track_color = r.GetTrackColor(track) or 0,
            fx_index = fx_index,
            fx_name = get_fx_name(track, fx_index),
            visible = visible,
            selected = selected,
            enabled = enabled,
            offline = fx_offline(track, fx_index),
            muted = (r.GetMediaTrackInfo_Value(track, "B_MUTE") or 0) > 0,
            solo = (r.GetMediaTrackInfo_Value(track, "I_SOLO") or 0) > 0,
            armed = (r.GetMediaTrackInfo_Value(track, "I_RECARM") or 0) > 0
          }
        end
      end
    end
  end
  table.sort(entries, settings.sort_mode == "name" and compare_entries_by_name or compare_entries)
  state.entries = entries
end

local function matches_search(entry, query)
  if not query or query == "" then return true end
  query = tostring(query):lower()
  return tostring(entry.track_name or ""):lower():find(query, 1, true) ~= nil or tostring(entry.fx_name or ""):lower():find(query, 1, true) ~= nil or tostring(entry.track_index or ""):find(query, 1, true) ~= nil
end

local function filtered_entries(settings)
  local result = {}
  for _, entry in ipairs(state.entries) do
    if matches_search(entry, settings.search_term) then result[#result + 1] = entry end
  end
  return result
end

local function close_all_floating_fx(except_guid, except_fx)
  for index = 0, r.CountTracks(0) - 1 do
    local track = r.GetTrack(0, index)
    if validate_track(track) then
      local guid = track_guid(track)
      for fx_index = 0, r.TrackFX_GetCount(track) - 1 do
        if not (guid == except_guid and fx_index == except_fx) and r.TrackFX_GetFloatingWindow(track, fx_index) then r.TrackFX_Show(track, fx_index, 2) end
      end
    end
  end
end

local function close_other_instruments(except_guid, except_fx)
  for _, entry in ipairs(state.entries) do
    if not (entry.track_guid == except_guid and entry.fx_index == except_fx) then
      local track = find_track_by_guid(entry.track_guid)
      if validate_track(track) and r.TrackFX_GetFloatingWindow(track, entry.fx_index) then r.TrackFX_Show(track, entry.fx_index, 2) end
    end
  end
end

local function js_window_available()
  return r.JS_Window_SetPosition and r.JS_Window_GetRect
end

local function position_window(track, fx_index, settings)
  if not settings.lock_window_position or not js_window_available() then return false end
  local hwnd = r.TrackFX_GetFloatingWindow(track, fx_index)
  if not hwnd then return false end
  local x = math.floor(tonumber(settings.window_x) or defaults.window_x)
  local y = math.floor(tonumber(settings.window_y) or defaults.window_y)
  local w = math.max(120, math.floor(tonumber(settings.window_w) or defaults.window_w))
  local h = math.max(120, math.floor(tonumber(settings.window_h) or defaults.window_h))
  r.JS_Window_SetPosition(hwnd, x, y, w, h)
  return true
end

local function open_instrument(app, entry)
  local settings = ensure_settings(app)
  local track = find_track_by_guid(entry.track_guid)
  if not validate_track(track) then
    state.status = "Instrument track not found"
    scan_instruments(app, true)
    return
  end
  if settings.close_others_on_open then
    if settings.close_scope == "all_fx" then close_all_floating_fx(entry.track_guid, entry.fx_index) else close_other_instruments(entry.track_guid, entry.fx_index) end
  end
  r.TrackFX_Show(track, entry.fx_index, 3)
  if settings.select_track_on_open and r.SetOnlyTrackSelected then r.SetOnlyTrackSelected(track) end
  settings.last_active_guid = entry.track_guid
  settings.last_active_fx = entry.fx_index
  if app.save_settings then app.save_settings() end
  if position_window(track, entry.fx_index, settings) then
    state.pending_position = nil
  elseif settings.lock_window_position and js_window_available() then
    state.pending_position = { guid = entry.track_guid, fx_index = entry.fx_index, attempts = 0 }
  end
  state.status = "Opened " .. entry.fx_name
end

local function close_active(app)
  local settings = ensure_settings(app)
  local track = find_track_by_guid(settings.last_active_guid)
  local fx_index = tonumber(settings.last_active_fx) or -1
  if validate_track(track) and fx_index >= 0 then
    r.TrackFX_Show(track, fx_index, 2)
    state.status = "Closed active instrument"
  end
end

local function close_all_instruments(app)
  ensure_settings(app)
  for _, entry in ipairs(state.entries) do
    local track = find_track_by_guid(entry.track_guid)
    if validate_track(track) and r.TrackFX_GetFloatingWindow(track, entry.fx_index) then r.TrackFX_Show(track, entry.fx_index, 2) end
  end
  state.status = "Closed all instrument windows"
end

local function save_active_position(app)
  local settings = ensure_settings(app)
  if not js_window_available() then
    state.status = "JS position API unavailable"
    return
  end
  local track = find_track_by_guid(settings.last_active_guid)
  local fx_index = tonumber(settings.last_active_fx) or -1
  if not validate_track(track) or fx_index < 0 then
    state.status = "No active instrument window"
    return
  end
  local hwnd = r.TrackFX_GetFloatingWindow(track, fx_index)
  if not hwnd then
    state.status = "Active instrument window not open"
    return
  end
  local ok, left, top, right, bottom = r.JS_Window_GetRect(hwnd)
  if not ok then
    state.status = "Could not read window position"
    return
  end
  settings.window_x = math.floor(left or defaults.window_x)
  settings.window_y = math.floor(top or defaults.window_y)
  settings.window_w = math.max(120, math.floor((right or left or 0) - (left or 0)))
  settings.window_h = math.max(120, math.floor((bottom or top or 0) - (top or 0)))
  if app.save_settings then app.save_settings() end
  state.status = "Saved active window position"
end

local function update_pending_position(app)
  local pending = state.pending_position
  if not pending or not js_window_available() then return end
  local settings = ensure_settings(app)
  local track = find_track_by_guid(pending.guid)
  if not validate_track(track) then state.pending_position = nil return end
  if position_window(track, pending.fx_index, settings) then
    state.pending_position = nil
    return
  end
  pending.attempts = pending.attempts + 1
  if pending.attempts > 30 then state.pending_position = nil end
end

local function draw_toolbar(ctx, app, settings)
  local avail_w = r.ImGui_GetContentRegionAvail(ctx) or UIScale.round(360)
  local gap = UIScale.gap(4)
  local button_w = math.max(UIScale.round(78), ((avail_w or UIScale.round(320)) - gap) * 0.5)
  local settings_w = UIScale.button_h(ctx)
  r.ImGui_SetNextItemWidth(ctx, math.max(UIScale.round(80), (avail_w or UIScale.round(320)) - settings_w - gap))
  local changed, value = r.ImGui_InputText(ctx, "##instrument_console_search", tostring(settings.search_term or ""))
  if changed then
    settings.search_term = value
    if app.save_settings then app.save_settings() end
  end
  r.ImGui_SameLine(ctx, 0, gap)
  if r.ImGui_Button(ctx, "...##instrument_console_settings", settings_w, 0) then r.ImGui_OpenPopup(ctx, "Instrument Console Settings") end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Instrument Console settings") end
  if r.ImGui_Button(ctx, "Refresh", button_w, 0) then scan_instruments(app, true) state.status = "Instrument list refreshed" end
  r.ImGui_SameLine(ctx, 0, gap)
    if r.ImGui_Button(ctx, "Close win", button_w, 0) then close_active(app) end
  if r.ImGui_Button(ctx, "Close all", button_w, 0) then close_all_instruments(app) end
  r.ImGui_SameLine(ctx, 0, gap)
  if r.ImGui_Button(ctx, "Save pos", button_w, 0) then save_active_position(app) end
end

local function draw_settings_popup(ctx, app, settings)
  if not r.ImGui_BeginPopup(ctx, "Instrument Console Settings") then return end
  local changed
  local popup_w = UIScale.round(230)
  r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Open behavior")
  changed, settings.close_others_on_open = r.ImGui_Checkbox(ctx, "Close previous on open", settings.close_others_on_open == true)
  if changed and app.save_settings then app.save_settings() end
  changed, settings.lock_window_position = r.ImGui_Checkbox(ctx, "Lock floating position", settings.lock_window_position == true)
  if changed and app.save_settings then app.save_settings() end
  r.ImGui_SetNextItemWidth(ctx, popup_w)
  if r.ImGui_BeginCombo(ctx, "Close scope##instrument_console_close_scope", settings.close_scope == "all_fx" and "All floating FX" or "Instruments") then
    if r.ImGui_Selectable(ctx, "Close instruments", settings.close_scope ~= "all_fx") then
      settings.close_scope = "instruments"
      if app.save_settings then app.save_settings() end
    end
    if r.ImGui_Selectable(ctx, "Close all floating FX", settings.close_scope == "all_fx") then
      settings.close_scope = "all_fx"
      if app.save_settings then app.save_settings() end
    end
    r.ImGui_EndCombo(ctx)
  end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Only controls what closes when opening an instrument") end

  r.ImGui_Separator(ctx)
  r.ImGui_TextColored(ctx, Theme.colors.text_dim, "List")
  changed, settings.selected_tracks_only = r.ImGui_Checkbox(ctx, "Selected tracks only", settings.selected_tracks_only == true)
  if changed then scan_instruments(app, true) if app.save_settings then app.save_settings() end end
  changed, settings.include_hidden_tracks = r.ImGui_Checkbox(ctx, "Include hidden tracks", settings.include_hidden_tracks == true)
  if changed then scan_instruments(app, true) if app.save_settings then app.save_settings() end end
  r.ImGui_SetNextItemWidth(ctx, popup_w)
  if r.ImGui_BeginCombo(ctx, "Sort##instrument_console_sort", settings.sort_mode == "name" and "Name" or "Track") then
    if r.ImGui_Selectable(ctx, "Track", settings.sort_mode ~= "name") then
      settings.sort_mode = "track"
      scan_instruments(app, true)
      if app.save_settings then app.save_settings() end
    end
    if r.ImGui_Selectable(ctx, "Name", settings.sort_mode == "name") then
      settings.sort_mode = "name"
      scan_instruments(app, true)
      if app.save_settings then app.save_settings() end
    end
    r.ImGui_EndCombo(ctx)
  end

  r.ImGui_Separator(ctx)
  r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Display")
  changed, settings.show_screenshots = r.ImGui_Checkbox(ctx, "Show screenshots when available", settings.show_screenshots == true)
  if changed then
    if not settings.show_screenshots then state.screenshot_cache = {}; state.screenshot_missing = {} end
    if app.save_settings then app.save_settings() end
  end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Uses existing screenshots only") end
  r.ImGui_EndPopup(ctx)
end

local function draw_badge(ctx, label, color)
  r.ImGui_SameLine(ctx)
  r.ImGui_TextColored(ctx, color, label)
end

local function draw_entry_screenshot(ctx, app, entry, active, settings)
  if not settings.show_screenshots then return end
  local img = get_screenshot_image(ctx, entry.fx_name)
  if not img then return end
  local width = r.ImGui_GetContentRegionAvail(ctx) or UIScale.round(220)
  if width < UIScale.round(120) then return end
  local height = UIScale.round(settings.screenshot_height or defaults.screenshot_height)
  local image_w, image_h = r.ImGui_Image_GetSize(img)
  if not image_w or not image_h or image_w <= 0 or image_h <= 0 then return end
  local draw_list = r.ImGui_GetWindowDrawList(ctx)
  local x, y = r.ImGui_GetCursorScreenPos(ctx)
  local bg = active and (Theme.colors.accent_soft or Theme.colors.frame_bg) or (Theme.colors.frame_bg or 0x202020FF)
  local scale = math.min(width / image_w, height / image_h)
  local draw_w = image_w * scale
  local draw_h = image_h * scale
  local draw_x = x + (width - draw_w) * 0.5
  local draw_y = y + (height - draw_h) * 0.5
  r.ImGui_DrawList_AddRectFilled(draw_list, x, y, x + width, y + height, bg, UIScale.px(3))
  r.ImGui_DrawList_AddImage(draw_list, img, draw_x, draw_y, draw_x + draw_w, draw_y + draw_h, 0, 0, 1, 1, entry.enabled and 0xFFFFFFFF or 0xFFFFFF66)
  if r.ImGui_InvisibleButton(ctx, "##instrument_console_screenshot", width, height) then open_instrument(app, entry) end
end

local function draw_entry(ctx, app, entry, active)
  local settings = ensure_settings(app)
  r.ImGui_PushID(ctx, entry.id)
  if active then
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Header(), Theme.colors.accent)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderHovered(), Theme.colors.accent)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), Theme.text_for_background(Theme.colors.accent, Theme.colors.text, nil, 4.5))
  end
  local label = string.format("%02d  %s  -  %s", entry.track_index, entry.track_name, entry.fx_name)
  local clicked = r.ImGui_Selectable(ctx, label, active, 0, 0, UIScale.round(24))
  if active then r.ImGui_PopStyleColor(ctx, 3) end
  if clicked then open_instrument(app, entry) end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Open " .. entry.fx_name) end
  r.ImGui_SameLine(ctx)
  r.ImGui_TextColored(ctx, Theme.colors.text_dim, entry.visible and "" or "hidden")
  if entry.offline then draw_badge(ctx, "offline", Theme.colors.danger) end
  if not entry.enabled then draw_badge(ctx, "bypassed", Theme.colors.warning) end
  if entry.muted then draw_badge(ctx, "muted", Theme.colors.warning) end
  if entry.solo then draw_badge(ctx, "solo", Theme.colors.accent) end
  if entry.armed then draw_badge(ctx, "armed", Theme.colors.danger) end
  draw_entry_screenshot(ctx, app, entry, active, settings)
  r.ImGui_PopID(ctx)
end

function M.init(app)
  ensure_settings(app)
  scan_instruments(app, true)
end

function M.update(app)
  scan_instruments(app, false)
  update_pending_position(app)
end

function M.draw(app)
  local ctx = app.ctx
  local settings = ensure_settings(app)
  scan_instruments(app, false)
  draw_toolbar(ctx, app, settings)
  draw_settings_popup(ctx, app, settings)
  r.ImGui_Separator(ctx)
  local entries = filtered_entries(settings)
  local available_w, available_h = r.ImGui_GetContentRegionAvail(ctx)
  local content_h = math.max(UIScale.round(60), (available_h or UIScale.round(240)) - UI.info_line_height(ctx))
  if r.ImGui_BeginChild(ctx, "##instrument_console_list", available_w or 0, content_h, 0) then
    if #entries == 0 then
      r.ImGui_TextColored(ctx, Theme.colors.text_dim, "No instruments found")
    else
      for _, entry in ipairs(entries) do
        local active = settings.last_active_guid == entry.track_guid and tonumber(settings.last_active_fx) == entry.fx_index
        draw_entry(ctx, app, entry, active)
      end
    end
    r.ImGui_EndChild(ctx)
  end
  local js_text = js_window_available() and "JS position lock available" or "JS position lock unavailable"
  UI.draw_info_line(ctx, tostring(#entries) .. " instruments | " .. js_text .. " | " .. tostring(state.status or "Ready"))
end

return M