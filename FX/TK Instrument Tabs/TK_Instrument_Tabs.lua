-- @description TK Instrument Tabs
-- @author TouristKiller
-- @version 1.0.0
-- @changelog:
--   + Initial ReaPack release
--   + Added instrument tabs with native floating FX window placement
--   + Added instrument add menu, tab context actions, MIDI input selection, settings, and close control


local r = reaper

local SCRIPT_NAME = "TK Instrument Tabs"
local SECTION = "TK_INSTRUMENT_TABS"

if not r.ImGui_CreateContext then
  r.ShowMessageBox("TK Instrument Tabs requires ReaImGui.", SCRIPT_NAME, 0)
  return
end

local ctx = r.ImGui_CreateContext(SCRIPT_NAME)
local status_font = nil
if r.ImGui_CreateFont and r.ImGui_Attach then
  status_font = r.ImGui_CreateFont("Arial", 112)
  if status_font then r.ImGui_Attach(ctx, status_font) end
end
local instruments = {}
local selected_key = ""
local active_key = ""
local last_scan_time = 0
local force_scan = true
local pending_activate_key = ""
local pending_activate_frames = 0
local pending_place_until = 0
local pending_close_key = ""
local pending_close_deadline = 0
local last_place_time = 0
local last_external_watch_time = 0
local external_open_state = {}
local host_rect = { left = 0, top = 0, width = 0, height = 0 }
local fx_size_cache = {}
local tab_width_cache = {}
local tab_scroll_x = 0
local tab_context_key = ""
local topbar_width = 980
local topbar_height = 66
local topbar_side_overhang = 1
local default_fx_width = 920
local default_fx_height = 620
local theme = nil
local cleanup_done = false
local close_requested = false
local startup_open_done = false
local startup_clean_done = false
local sexan_parser_loaded = false
local add_instrument_items = nil
local add_instrument_struct = nil
local add_instrument_error = nil

local function ext_get_bool(key, default_value)
  local value = r.GetExtState(SECTION, key)
  if value == nil or value == "" then return default_value end
  return value == "1"
end

local function ext_set_bool(key, value)
  r.SetExtState(SECTION, key, value and "1" or "0", true)
end

local function ext_get_number(key, default_value)
  local value = tonumber(r.GetExtState(SECTION, key))
  if value == nil then return default_value end
  return value
end

local function ext_set_number(key, value)
  r.SetExtState(SECTION, key, tostring(value), true)
end

local settings = {
  select_track_on_open = ext_get_bool("select_track_on_open", true),
  auto_open_on_start = ext_get_bool("auto_open_on_start", false),
  capture_external_floating = ext_get_bool("capture_external_floating", true),
  plugin_overlap_y = ext_get_number("plugin_overlap_y", 12),
  scan_interval = 0.75,
}

local function imgui_flag(name)
  local flag_function = r[name]
  if flag_function then return flag_function() end
  return 0
end

local function add_imgui_flag(flags, name)
  local value = imgui_flag(name)
  if value ~= 0 then return flags | value end
  return flags
end

local function clamp(value, min_value, max_value)
  value = tonumber(value) or min_value
  return math.max(min_value, math.min(max_value, value))
end

local function js_int(value)
  return math.floor((tonumber(value) or 0) + 0.5)
end

local function rgba(red, green, blue, alpha)
  red = js_int(clamp(red, 0, 255))
  green = js_int(clamp(green, 0, 255))
  blue = js_int(clamp(blue, 0, 255))
  alpha = js_int(clamp(alpha or 255, 0, 255))
  return red * 0x1000000 + green * 0x10000 + blue * 0x100 + alpha
end

local function split_rgba(color)
  color = math.floor(tonumber(color) or 0)
  if color < 0 then color = color + 0x100000000 end
  local red = math.floor(color / 0x1000000) % 0x100
  local green = math.floor(color / 0x10000) % 0x100
  local blue = math.floor(color / 0x100) % 0x100
  local alpha = color % 0x100
  return red, green, blue, alpha
end

local function blend(first, second, amount)
  amount = clamp(amount, 0, 1)
  local ar, ag, ab, aa = split_rgba(first)
  local br, bg, bb, ba = split_rgba(second)
  return rgba(ar + (br - ar) * amount, ag + (bg - ag) * amount, ab + (bb - ab) * amount, aa + (ba - aa) * amount)
end

local function luminance(color)
  local red, green, blue = split_rgba(color)
  return (0.2126 * red + 0.7152 * green + 0.0722 * blue) / 255
end

local function readable_text(background)
  return luminance(background) > 0.52 and 0x20242AFF or 0xF2F4F7FF
end

local function theme_color(name, fallback)
  if not r.GetThemeColor or not r.ColorFromNative then return fallback end
  local ok_color, native = pcall(r.GetThemeColor, name, 0)
  if not ok_color or native == nil or native < 0 then return fallback end
  local ok_rgb, red, green, blue = pcall(r.ColorFromNative, native)
  if not ok_rgb then return fallback end
  return rgba(red or 0, green or 0, blue or 0, 255)
end

local function first_theme_color(names, fallback)
  for _, name in ipairs(names) do
    local color = theme_color(name, nil)
    if color then return color end
  end
  return fallback
end

local function build_theme()
  local fallback_bg = 0x16181CFF
  local fallback_panel = 0x20242AFF
  local window_bg = first_theme_color({ "col_main_bg", "docker_bg", "col_main_bg2", "col_arrangebg" }, fallback_bg)
  local panel_bg = first_theme_color({ "docker_bg", "genlist_bg", "col_main_bg2", "col_tracklistbg" }, fallback_panel)
  local edit_bg = first_theme_color({ "col_main_editbk", "genlist_bg", "col_buttonbg" }, blend(panel_bg, readable_text(panel_bg), 0.08))
  local accent = first_theme_color({ "genlist_selbg", "docker_selface", "col_seltrack", "selcol_tr1_bg", "marker", "region", "col_routingact", "col_vumid" }, 0x7AA2F7FF)
  local highlight = first_theme_color({ "col_main_3dhl", "tcp_list_scrollbar_mouseover", "mcp_list_scrollbar_mouseover" }, readable_text(window_bg))
  local shadow = first_theme_color({ "col_main_3dsh", "genlist_grid", "col_gridlines" }, blend(window_bg, readable_text(window_bg), 0.18))
  local dark = luminance(window_bg) < 0.5
  local text = first_theme_color({ "col_main_text", "genlist_fg", "col_tcp_text", "col_mixer_text" }, readable_text(window_bg))
  local text_dim = first_theme_color({ "col_main_text2", "genlist_seliafg", "col_tl_fg2", "col_toolbar_text" }, blend(text, window_bg, dark and 0.38 or 0.52))
  local tab_bg = blend(edit_bg, window_bg, dark and 0.22 or 0.16)
  local tab_hover = blend(tab_bg, highlight, dark and 0.18 or 0.12)
  local tab_active = blend(tab_bg, accent, dark and 0.42 or 0.34)
  local topbar_border = dark and blend(0xFFFFFFFF, window_bg, 0.82) or blend(0x000000FF, window_bg, 0.36)
  return {
    window_bg = window_bg,
    panel_bg = panel_bg,
    edit_bg = edit_bg,
    popup_bg = blend(panel_bg, window_bg, 0.18),
    tab_bg = tab_bg,
    tab_hover = tab_hover,
    tab_active = tab_active,
    border = blend(highlight, shadow, 0.55),
    topbar_border = topbar_border,
    text = readable_text(window_bg),
    text_tab = readable_text(tab_bg),
    text_active = readable_text(tab_active),
    text_dim = text_dim,
    accent = accent,
    accent_soft = blend(accent, window_bg, dark and 0.62 or 0.76),
  }
end

local function push_theme()
  theme = build_theme()
  local colors = 0
  local vars = 0
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_WindowBg(), theme.window_bg); colors = colors + 1
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_PopupBg(), theme.popup_bg); colors = colors + 1
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), theme.edit_bg); colors = colors + 1
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgHovered(), theme.tab_hover); colors = colors + 1
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Border(), theme.border); colors = colors + 1
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), theme.text); colors = colors + 1
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), theme.tab_bg); colors = colors + 1
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), theme.tab_hover); colors = colors + 1
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), theme.tab_active); colors = colors + 1
  if r.ImGui_StyleVar_WindowRounding then r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowRounding(), 0); vars = vars + 1 end
  if r.ImGui_StyleVar_FrameRounding then r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), 4); vars = vars + 1 end
  if r.ImGui_StyleVar_WindowPadding then r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), 8, 6); vars = vars + 1 end
  if r.ImGui_StyleVar_ItemSpacing then r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing(), 6, 5); vars = vars + 1 end
  return { colors = colors, vars = vars }
end

local function pop_theme(stack)
  if stack and stack.vars and stack.vars > 0 then r.ImGui_PopStyleVar(ctx, stack.vars) end
  if stack and stack.colors and stack.colors > 0 then r.ImGui_PopStyleColor(ctx, stack.colors) end
end

local function draw_topbar_background()
  local draw_list = r.ImGui_GetWindowDrawList(ctx)
  local x, y = r.ImGui_GetWindowPos(ctx)
  local width, height = r.ImGui_GetWindowSize(ctx)
  local bg_x1 = x
  local bg_x2 = x + width
  local rounding = 7
  local border_color = theme.topbar_border or theme.border
  local line_x1 = bg_x1 + 0.5
  local line_x2 = bg_x2 - 0.5
  local line_y = y + 0.5
  local line_bottom = y + height
  local corner_flags = imgui_flag("ImGui_DrawFlags_RoundCornersTop")
  if corner_flags ~= 0 then
    r.ImGui_DrawList_AddRectFilled(draw_list, bg_x1, y, bg_x2, y + height, theme.window_bg, rounding, corner_flags)
    r.ImGui_DrawList_AddRect(draw_list, line_x1, line_y, line_x2, y + height, border_color, rounding, corner_flags, 1)
    r.ImGui_DrawList_AddLine(draw_list, line_x1 + rounding, line_y, line_x2 - rounding, line_y, border_color, 1)
    r.ImGui_DrawList_AddLine(draw_list, line_x1, line_y + rounding, line_x1, line_bottom, border_color, 1)
    r.ImGui_DrawList_AddLine(draw_list, line_x2, line_y + rounding, line_x2, line_bottom, border_color, 1)
    r.ImGui_DrawList_AddLine(draw_list, bg_x1, y + height - 1, bg_x2, y + height - 1, theme.window_bg, 2)
  else
    r.ImGui_DrawList_AddRectFilled(draw_list, bg_x1, y, bg_x2, y + height, theme.window_bg, rounding)
    r.ImGui_DrawList_AddRectFilled(draw_list, bg_x1, y + rounding, bg_x2, y + height, theme.window_bg, 0)
    r.ImGui_DrawList_AddLine(draw_list, line_x1 + rounding, line_y, line_x2 - rounding, line_y, border_color, 1)
    r.ImGui_DrawList_AddLine(draw_list, line_x1, line_y + rounding, line_x1, line_bottom, border_color, 1)
    r.ImGui_DrawList_AddLine(draw_list, line_x2, line_y + rounding, line_x2, line_bottom, border_color, 1)
  end
end

local function main_viewport_rect()
  local vx, vy, vw, vh = 80, 80, 1280, 720
  local vp = r.ImGui_GetMainViewport and r.ImGui_GetMainViewport(ctx)
  if vp then
    if r.ImGui_Viewport_GetPos then
      local x, y = r.ImGui_Viewport_GetPos(vp)
      if x and y then vx, vy = x, y end
    end
    if r.ImGui_Viewport_GetSize then
      local w, h = r.ImGui_Viewport_GetSize(vp)
      if w and h and w > 0 and h > 0 then vw, vh = w, h end
    end
  end
  return vx, vy, vw, vh
end

local function is_valid_media_track(track)
  if not track then return false end
  if r.ValidatePtr2 then return r.ValidatePtr2(0, track, "MediaTrack*") end
  if r.ValidatePtr then return r.ValidatePtr(track, "MediaTrack*") end
  return true
end

local function track_guid(track)
  if track and r.GetTrackGUID then return r.GetTrackGUID(track) end
  return tostring(track or "")
end

local function track_name(track, track_index)
  local fallback_name = "Track " .. tostring(track_index + 1)
  if not track then return fallback_name end
  local retval, name = r.GetTrackName(track, "")
  if retval and name and name ~= "" then return name end
  return fallback_name
end

local function clean_fx_name(name)
  name = tostring(name or "")
  name = name:gsub("^%s+", ""):gsub("%s+$", "")
  name = name:gsub("^VST3i:%s*", "")
  name = name:gsub("^VSTi:%s*", "")
  name = name:gsub("^VST3:%s*", "")
  name = name:gsub("^VST:%s*", "")
  name = name:gsub("^CLAPi:%s*", "")
  name = name:gsub("^CLAP:%s*", "")
  name = name:gsub("^AUi:%s*", "")
  name = name:gsub("^LV2i:%s*", "")
  name = name:gsub("^AU:%s*", "")
  name = name:gsub("%s+%(.-%)%s*$", "")
  if name == "" then return "Instrument" end
  return name
end

local function is_instrument_fx_name(name)
  name = tostring(name or "")
  return name:match("^VSTi:%s") ~= nil
    or name:match("^VST3i:%s") ~= nil
    or name:match("^CLAPi:%s") ~= nil
    or name:match("^AUi:%s") ~= nil
    or name:match("^LV2i:%s") ~= nil
end

local function entry_label(entry)
  if not entry then return "" end
  return tostring(entry.track_index + 1) .. "  " .. tostring(entry.fx_label or entry.fx_name or "Instrument")
end

local function find_entry_by_key(key)
  for entry_index = 1, #instruments do
    local entry = instruments[entry_index]
    if entry.key == key then return entry end
  end
  return nil
end

local function resolve_entry_track(entry)
  if not entry then return nil end
  if entry.track_guid and r.BR_GetMediaTrackByGUID then
    local track = r.BR_GetMediaTrackByGUID(0, entry.track_guid)
    if is_valid_media_track(track) then return track end
  end
  local track = r.GetTrack(0, entry.track_index)
  if not is_valid_media_track(track) then return nil end
  if entry.track_guid and track_guid(track) ~= entry.track_guid then return nil end
  return track
end

local function safe_trackfx_show(track, fx_index, show_flag)
  if not r.TrackFX_Show then return false end
  if not is_valid_media_track(track) then return false end
  r.TrackFX_Show(track, fx_index, show_flag)
  return true
end

local function safe_trackfx_get_floating_window(track, fx_index)
  if not r.TrackFX_GetFloatingWindow then return nil end
  if not is_valid_media_track(track) then return nil end
  return r.TrackFX_GetFloatingWindow(track, fx_index)
end

local function safe_trackfx_get_enabled(track, fx_index, fallback)
  if not r.TrackFX_GetEnabled then return fallback end
  if not is_valid_media_track(track) then return fallback end
  return r.TrackFX_GetEnabled(track, fx_index)
end

local function safe_trackfx_get_offline(track, fx_index, fallback)
  if not r.TrackFX_GetOffline then return fallback end
  if not is_valid_media_track(track) then return fallback end
  return r.TrackFX_GetOffline(track, fx_index)
end

local function safe_trackfx_set_enabled(track, fx_index, enabled)
  if not r.TrackFX_SetEnabled then return false end
  if not is_valid_media_track(track) then return false end
  r.TrackFX_SetEnabled(track, fx_index, enabled)
  return true
end

local function safe_trackfx_set_offline(track, fx_index, offline)
  if not r.TrackFX_SetOffline then return false end
  if not is_valid_media_track(track) then return false end
  r.TrackFX_SetOffline(track, fx_index, offline)
  return true
end

local function safe_trackfx_delete(track, fx_index)
  if not r.TrackFX_Delete then return false end
  if not is_valid_media_track(track) then return false end
  r.TrackFX_Delete(track, fx_index)
  return true
end

local function midi_input_value(device_index)
  if device_index == nil then return -1 end
  return 4096 + (device_index << 5)
end

local function midi_input_options()
  local options = {
    { label = "None", value = -1 },
    { label = "All MIDI inputs", value = midi_input_value(63) },
    { label = "Virtual MIDI Keyboard", value = midi_input_value(62) },
  }
  if r.GetNumMIDIInputs and r.GetMIDIInputName then
    local count = r.GetNumMIDIInputs()
    for index = 0, count - 1 do
      local ok, name = r.GetMIDIInputName(index, "")
      if ok and name and name ~= "" then options[#options + 1] = { label = name, value = midi_input_value(index) } end
    end
  end
  return options
end

local function midi_input_label(value)
  value = math.floor(tonumber(value) or -1)
  if value < 0 then return "None" end
  if (value & 4096) ~= 4096 then return "Audio input" end
  local device = (value >> 5) & 63
  local channel = value & 31
  local suffix = channel > 0 and (" ch " .. tostring(channel)) or ""
  if device == 63 then return "All MIDI inputs" .. suffix end
  if device == 62 then return "Virtual MIDI Keyboard" .. suffix end
  if r.GetMIDIInputName then
    local ok, name = r.GetMIDIInputName(device, "")
    if ok and name and name ~= "" then return name .. suffix end
  end
  return "MIDI input " .. tostring(device + 1) .. suffix
end

local function set_track_midi_input(track, value)
  if not is_valid_media_track(track) then return false end
  r.Undo_BeginBlock()
  r.SetMediaTrackInfo_Value(track, "I_RECINPUT", value)
  r.Undo_EndBlock("Set instrument MIDI input", -1)
  return true
end

local function refresh_entry_state(entry, track)
  if not entry or not track then return end
  entry.enabled = safe_trackfx_get_enabled(track, entry.fx_index, entry.enabled ~= false)
  entry.offline = safe_trackfx_get_offline(track, entry.fx_index, entry.offline == true)
end

local function entry_blocked_state(entry)
  if not entry then return nil end
  if entry.offline then return "OFFLINE" end
  if entry.enabled == false then return "BYPASS" end
  return nil
end

local function cached_fx_size(entry)
  if entry and fx_size_cache[entry.key] then return fx_size_cache[entry.key] end
  return { width = default_fx_width, height = default_fx_height }
end

local function update_topbar_width_from_size(width)
  local _, _, viewport_width = main_viewport_rect()
  topbar_width = clamp(width or topbar_width, 360, math.max(360, viewport_width - 24))
end

local function measure_fx_window(entry, hwnd)
  if not entry or not hwnd or not r.JS_Window_GetRect then return false end
  local ok, left, top, right, bottom = r.JS_Window_GetRect(hwnd)
  if not ok then return false end
  local width = math.max(180, (right or 0) - (left or 0))
  local height = math.max(140, (bottom or 0) - (top or 0))
  if width <= 180 or height <= 140 then return false end
  local previous = fx_size_cache[entry.key]
  fx_size_cache[entry.key] = { width = width, height = height }
  update_topbar_width_from_size(width)
  if not previous then return true end
  return math.abs((previous.width or 0) - width) > 2 or math.abs((previous.height or 0) - height) > 2
end

local function place_active_window()
  if host_rect.width < 120 or host_rect.height < 90 then return false end
  if not r.JS_Window_SetPosition then return false end
  local entry = find_entry_by_key(active_key)
  if entry_blocked_state(entry) then return false end
  local track = resolve_entry_track(entry)
  if not track then return false end
  refresh_entry_state(entry, track)
  if entry_blocked_state(entry) then return false end
  local hwnd = safe_trackfx_get_floating_window(track, entry.fx_index)
  if not hwnd then return false end
  measure_fx_window(entry, hwnd)
  local size = cached_fx_size(entry)
  host_rect.width = size.width
  host_rect.height = size.height
  r.JS_Window_SetPosition(hwnd, js_int(host_rect.left), js_int(host_rect.top), js_int(host_rect.width), js_int(host_rect.height))
  return true
end

local function close_entry(entry)
  local track = resolve_entry_track(entry)
  if track then safe_trackfx_show(track, entry.fx_index, 2) end
end

local function close_pending_previous()
  if pending_close_key == "" then return end
  local entry = find_entry_by_key(pending_close_key)
  if entry then close_entry(entry) end
  pending_close_key = ""
  pending_close_deadline = 0
end

local function close_active_window()
  local entry = find_entry_by_key(active_key)
  if entry then close_entry(entry) end
  close_pending_previous()
  pending_activate_key = ""
  pending_activate_frames = 0
  active_key = ""
  pending_place_until = 0
end

local function close_all_instruments()
  for entry_index = 1, #instruments do close_entry(instruments[entry_index]) end
  active_key = ""
  pending_activate_key = ""
  pending_activate_frames = 0
  pending_close_key = ""
  pending_close_deadline = 0
  external_open_state = {}
  pending_place_until = 0
end

local function activate_entry(entry)
  if not entry then return end
  local previous_key = active_key
  local track = resolve_entry_track(entry)
  if not track then return end
  refresh_entry_state(entry, track)
  if settings.select_track_on_open and r.SetOnlyTrackSelected then r.SetOnlyTrackSelected(track) end
  if entry_blocked_state(entry) then
    close_entry(entry)
    if previous_key ~= "" and previous_key ~= entry.key then
      local previous_entry = find_entry_by_key(previous_key)
      if previous_entry then close_entry(previous_entry) end
      pending_close_key = ""
      pending_close_deadline = 0
    end
    local cached_size = cached_fx_size(entry)
    update_topbar_width_from_size(cached_size.width)
    selected_key = entry.key
    active_key = entry.key
    pending_place_until = 0
    last_place_time = 0
    return
  end
  if not safe_trackfx_show(track, entry.fx_index, 3) then return end
  if previous_key ~= "" and previous_key ~= entry.key then
    pending_close_key = previous_key
    pending_close_deadline = r.time_precise() + 0.75
  end
  local cached_size = cached_fx_size(entry)
  update_topbar_width_from_size(cached_size.width)
  selected_key = entry.key
  active_key = entry.key
  pending_place_until = r.time_precise() + 1.25
  last_place_time = 0
end

local function request_activate_entry(entry)
  if not entry then return end
  selected_key = entry.key
  if entry.key == active_key then
    pending_activate_key = ""
    pending_activate_frames = 0
    return
  end
  pending_activate_key = entry.key
  pending_activate_frames = 2
end

local function process_pending_activation()
  if pending_activate_key == "" then return end
  if pending_activate_frames > 0 then
    pending_activate_frames = pending_activate_frames - 1
    return
  end
  local entry = find_entry_by_key(pending_activate_key)
  pending_activate_key = ""
  pending_activate_frames = 0
  if entry then activate_entry(entry) end
end

local function scan_instruments(force)
  local now = r.time_precise()
  if not force and now - last_scan_time < settings.scan_interval then return end
  last_scan_time = now
  force_scan = false
  local previous_selected_key = selected_key
  local next_instruments = {}
  local track_count = r.CountTracks(0)
  for track_index = 0, track_count - 1 do
    local track = r.GetTrack(0, track_index)
    if is_valid_media_track(track) then
      local primary_instrument = r.TrackFX_GetInstrument and r.TrackFX_GetInstrument(track) or -1
      local fx_count = r.TrackFX_GetCount(track)
      for fx_index = 0, fx_count - 1 do
        local retval, fx_name = r.TrackFX_GetFXName(track, fx_index, "")
        fx_name = retval and fx_name or "Instrument"
        if fx_index == primary_instrument or is_instrument_fx_name(fx_name) then
          local guid = track_guid(track)
          next_instruments[#next_instruments + 1] = {
            key = guid .. "|" .. tostring(fx_index),
            track_guid = guid,
            track_index = track_index,
            track_name = track_name(track, track_index),
            fx_index = fx_index,
            fx_name = fx_name,
            fx_label = clean_fx_name(fx_name),
            enabled = safe_trackfx_get_enabled(track, fx_index, true),
            offline = safe_trackfx_get_offline(track, fx_index, false),
          }
        end
      end
    end
  end
  instruments = next_instruments
  tab_width_cache = {}
  if #instruments == 0 then selected_key = ""; active_key = ""; return end
  if previous_selected_key ~= "" and find_entry_by_key(previous_selected_key) then selected_key = previous_selected_key else selected_key = instruments[1].key end
end

local function selected_track_entry()
  if not r.CountSelectedTracks or not r.GetSelectedTrack then return nil end
  if r.CountSelectedTracks(0) < 1 then return nil end
  local selected_track = r.GetSelectedTrack(0, 0)
  if not is_valid_media_track(selected_track) then return nil end
  local guid = track_guid(selected_track)
  for entry_index = 1, #instruments do
    local entry = instruments[entry_index]
    if entry.track_guid == guid then return entry end
  end
  return nil
end

local function open_startup_instrument()
  if startup_open_done then return end
  startup_open_done = true
  if not settings.auto_open_on_start or active_key ~= "" or #instruments == 0 then return end
  activate_entry(selected_track_entry() or instruments[1])
end

local function close_existing_instruments_on_start()
  if startup_clean_done then return end
  startup_clean_done = true
  if #instruments > 0 then close_all_instruments() end
end

local function file_exists(path)
  local file = io.open(path, "r")
  if file then file:close(); return true end
  return false
end

local function extract_fx_entry(entry)
  if type(entry) == "string" then return entry, entry end
  if type(entry) == "table" then
    local name = entry.name or entry.fxname or entry.fxName or entry.fname or entry.FX_NAME or entry[1]
    local addname = entry.addname or entry.fullname or entry.name or entry.fxname or entry[2] or name
    if name or addname then return tostring(name or addname), tostring(addname or name) end
  end
  return nil, nil
end

local function item_list_from_names(names)
  local out = {}
  local seen = {}
  for index = 1, #(names or {}) do
    local name = names[index]
    if type(name) == "string" and is_instrument_fx_name(name) and not seen[name] then
      out[#out + 1] = { display = clean_fx_name(name), addname = name }
      seen[name] = true
    end
  end
  table.sort(out, function(a, b) return (a.display or ""):lower() < (b.display or ""):lower() end)
  return out
end

local function sorted_keys(tbl)
  local keys = {}
  for key in pairs(tbl or {}) do keys[#keys + 1] = key end
  table.sort(keys, function(a, b) return tostring(a):lower() < tostring(b):lower() end)
  return keys
end

local function find_cat_entry(cat_tbl, name)
  for index = 1, #(cat_tbl or {}) do
    if cat_tbl[index].name == name then return cat_tbl[index] end
  end
  return nil
end

local function add_folder_entry(node, folder_entry)
  if type(folder_entry) ~= "table" or not folder_entry.name then return end
  node.children = node.children or {}
  node.items = node.items or {}
  local child = node.children[folder_entry.name] or { name = folder_entry.name, children = {}, items = {} }
  node.children[folder_entry.name] = child
  if type(folder_entry.fx) == "table" then
    for index = 1, #folder_entry.fx do
      local fx_name = folder_entry.fx[index]
      if type(fx_name) == "string" and is_instrument_fx_name(fx_name) then child.items[#child.items + 1] = { display = clean_fx_name(fx_name), addname = fx_name } end
    end
  end
  if type(folder_entry.list) == "table" then
    for index = 1, #folder_entry.list do
      local value = folder_entry.list[index]
      if type(value) == "table" and value.name then add_folder_entry(child, value) end
    end
  end
end

local function build_instrument_struct(list, cat_tbl)
  local struct = { all = {}, types = {}, categories = {}, developers = {}, folders = { name = "ROOT", children = {}, items = {} } }
  local all = find_cat_entry(cat_tbl, "ALL PLUGINS")
  if all and all.list then
    for index = 1, #all.list do
      local entry = all.list[index]
      if type(entry) == "table" and entry.name and entry.fx then
        local items = item_list_from_names(entry.fx)
        if #items > 0 then
          if entry.name == "INSTRUMENTS" then struct.all = items else struct.types[entry.name] = items end
        end
      end
    end
  end
  if #struct.all == 0 then
    local flat, seen = {}, {}
    local function flatten(obj, depth)
      if depth > 6 then return end
      local display, addname = extract_fx_entry(obj)
      if addname and is_instrument_fx_name(addname) and not seen[addname] then
        flat[#flat + 1] = { display = clean_fx_name(display or addname), addname = addname }
        seen[addname] = true
      end
      if type(obj) == "table" then
        for _, value in pairs(obj) do
          if type(value) == "table" or type(value) == "string" then flatten(value, depth + 1) end
        end
      end
    end
    flatten(list, 0)
    table.sort(flat, function(a, b) return (a.display or ""):lower() < (b.display or ""):lower() end)
    struct.all = flat
  end
  local category = find_cat_entry(cat_tbl, "CATEGORY")
  if category and category.list then
    for index = 1, #category.list do
      local entry = category.list[index]
      if type(entry) == "table" and entry.name and entry.fx then
        local items = item_list_from_names(entry.fx)
        if #items > 0 then struct.categories[entry.name] = items end
      end
    end
  end
  local developer = find_cat_entry(cat_tbl, "DEVELOPER")
  if developer and developer.list then
    for index = 1, #developer.list do
      local entry = developer.list[index]
      if type(entry) == "table" and entry.name and entry.fx then
        local items = item_list_from_names(entry.fx)
        if #items > 0 then struct.developers[entry.name] = items end
      end
    end
  end
  local folders = find_cat_entry(cat_tbl, "FOLDERS")
  if folders and folders.list then
    for index = 1, #folders.list do add_folder_entry(struct.folders, folders.list[index]) end
  end
  return struct
end

local function load_instrument_items(force)
  if add_instrument_items and not force then return add_instrument_items, nil end
  local parser_path = r.GetResourcePath() .. "/Scripts/Sexan_Scripts/FX/Sexan_FX_Browser_ParserV7.lua"
  if not sexan_parser_loaded then
    if not file_exists(parser_path) then add_instrument_error = "Sexan FX Browser Parser V7 not found."; return nil, add_instrument_error end
    local ok, err = pcall(dofile, parser_path)
    if not ok then add_instrument_error = "Sexan parser error: " .. tostring(err); return nil, add_instrument_error end
    sexan_parser_loaded = true
  end
  local list, cat_tbl, dev_list = nil, nil, nil
  if type(ReadFXFile) == "function" then list, cat_tbl, dev_list = ReadFXFile() end
  if (not list or not cat_tbl) and type(MakeFXFiles) == "function" then
    local ok, fx_list, cat, dev = pcall(MakeFXFiles)
    if ok then list, cat_tbl, dev_list = fx_list, cat, dev end
  end
  if (not list or not cat_tbl) and type(GetFXTbl) == "function" then
    local ok, fx_list, cat, dev = pcall(GetFXTbl)
    if ok then list, cat_tbl, dev_list = fx_list, cat, dev end
  end
  if not list or not cat_tbl then add_instrument_error = "Could not load instrument list."; return nil, add_instrument_error end
  add_instrument_struct = build_instrument_struct(list, cat_tbl)
  add_instrument_items = add_instrument_struct.all or {}
  add_instrument_error = nil
  return add_instrument_items, nil
end

local function target_track_for_new_instrument()
  if r.CountSelectedTracks and r.GetSelectedTrack and r.CountSelectedTracks(0) > 0 then
    local track = r.GetSelectedTrack(0, 0)
    if is_valid_media_track(track) then return track end
  end
  local index = r.CountTracks(0)
  r.InsertTrackAtIndex(index, true)
  return r.GetTrack(0, index)
end

local function add_instrument_to_project(item)
  if not item or not item.addname then return end
  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)
  local track = target_track_for_new_instrument()
  local new_index = -1
  if track then new_index = r.TrackFX_AddByName(track, item.addname, false, -1) end
  r.PreventUIRefresh(-1)
  r.TrackList_AdjustWindows(false)
  r.UpdateArrange()
  r.Undo_EndBlock("Add instrument from TK Instrument Tabs", -1)
  if not track then add_instrument_error = "Could not create or find target track."; return end
  if not new_index or new_index < 0 then add_instrument_error = "Instrument could not be added."; return end
  if settings.select_track_on_open and r.SetOnlyTrackSelected then r.SetOnlyTrackSelected(track) end
  scan_instruments(true)
  local entry = find_entry_by_key(track_guid(track) .. "|" .. tostring(new_index))
  if entry then request_activate_entry(entry) end
  add_instrument_error = nil
  r.ImGui_CloseCurrentPopup(ctx)
end

local function draw_instrument_item_list(items)
  if not items or #items == 0 then r.ImGui_TextDisabled(ctx, "No instruments"); return end
  for index = 1, #items do
    local item = items[index]
    if r.ImGui_Selectable(ctx, item.display or item.addname or "Instrument") then add_instrument_to_project(item) end
  end
end

local function draw_named_instrument_menus(label, lists)
  if r.ImGui_BeginMenu(ctx, label) then
    local keys = sorted_keys(lists)
    if #keys == 0 then r.ImGui_TextDisabled(ctx, "No entries") end
    for index = 1, #keys do
      if r.ImGui_BeginMenu(ctx, keys[index]) then
        draw_instrument_item_list(lists[keys[index]])
        r.ImGui_EndMenu(ctx)
      end
    end
    r.ImGui_EndMenu(ctx)
  end
end

local function draw_folder_instrument_menus(node)
  if node and node.items and #node.items > 0 then draw_instrument_item_list(node.items) end
  local keys = sorted_keys(node and node.children or {})
  for index = 1, #keys do
    local child = node.children[keys[index]]
    if r.ImGui_BeginMenu(ctx, keys[index]) then
      draw_folder_instrument_menus(child)
      r.ImGui_EndMenu(ctx)
    end
  end
end

local function draw_add_instrument_popup()
  if r.ImGui_BeginPopup(ctx, "Add Instrument Menu") then
    local _, load_err = load_instrument_items(false)
    local struct = add_instrument_struct or {}
    if load_err then
      r.ImGui_TextDisabled(ctx, load_err)
    else
      if r.ImGui_BeginMenu(ctx, "ALL INSTRUMENTS") then
        draw_instrument_item_list(struct.all or add_instrument_items or {})
        r.ImGui_EndMenu(ctx)
      end
      draw_named_instrument_menus("TYPE", struct.types or {})
      draw_named_instrument_menus("CATEGORY", struct.categories or {})
      draw_named_instrument_menus("DEVELOPER", struct.developers or {})
      if r.ImGui_BeginMenu(ctx, "FOLDERS") then
        draw_folder_instrument_menus(struct.folders or { children = {}, items = {} })
        r.ImGui_EndMenu(ctx)
      end
    end
    if add_instrument_error then r.ImGui_TextDisabled(ctx, add_instrument_error) end
    r.ImGui_Separator(ctx)
    if r.ImGui_MenuItem(ctx, "Refresh instrument list") then load_instrument_items(true) end
    r.ImGui_EndPopup(ctx)
  end
end

local function find_entry_index_by_key(key)
  for index = 1, #instruments do
    if instruments[index].key == key then return index end
  end
  return nil
end

local function find_entry_after_delete(track_guid_value, fx_index, fx_name)
  local key = track_guid_value .. "|" .. tostring(fx_index)
  local entry = find_entry_by_key(key)
  if entry then return entry end
  for index = 1, #instruments do
    local candidate = instruments[index]
    if candidate.track_guid == track_guid_value and candidate.fx_name == fx_name then return candidate end
  end
  return nil
end

local function set_entry_bypass(entry, bypassed)
  local track = resolve_entry_track(entry)
  if not track then return end
  r.Undo_BeginBlock()
  local ok = safe_trackfx_set_enabled(track, entry.fx_index, not bypassed)
  r.Undo_EndBlock(bypassed and "Bypass instrument" or "Unbypass instrument", -1)
  if not ok then return end
  if bypassed then close_entry(entry) end
  scan_instruments(true)
  local updated = find_entry_by_key(entry.key)
  if updated then activate_entry(updated) end
end

local function set_entry_offline(entry, offline)
  local track = resolve_entry_track(entry)
  if not track then return end
  r.Undo_BeginBlock()
  local ok = safe_trackfx_set_offline(track, entry.fx_index, offline)
  r.Undo_EndBlock(offline and "Set instrument offline" or "Set instrument online", -1)
  if not ok then return end
  if offline then close_entry(entry) end
  scan_instruments(true)
  local updated = find_entry_by_key(entry.key)
  if updated then activate_entry(updated) end
end

local function remove_entry(entry)
  local track = resolve_entry_track(entry)
  if not track then return end
  local entry_index = find_entry_index_by_key(entry.key)
  local target = entry_index and (instruments[entry_index + 1] or instruments[entry_index - 1]) or nil
  local target_guid, target_fx_index, target_fx_name = nil, nil, nil
  if target then
    target_guid = target.track_guid
    target_fx_index = target.fx_index
    target_fx_name = target.fx_name
    if target.track_guid == entry.track_guid and target.fx_index > entry.fx_index then target_fx_index = target_fx_index - 1 end
  end
  close_entry(entry)
  r.Undo_BeginBlock()
  local ok = safe_trackfx_delete(track, entry.fx_index)
  r.Undo_EndBlock("Remove instrument", -1)
  if not ok then return end
  pending_activate_key = ""
  pending_activate_frames = 0
  pending_close_key = ""
  pending_close_deadline = 0
  scan_instruments(true)
  local next_entry = target_guid and find_entry_after_delete(target_guid, target_fx_index, target_fx_name) or nil
  if next_entry then
    activate_entry(next_entry)
  elseif #instruments > 0 then
    selected_key = instruments[1].key
    if active_key == entry.key then active_key = "" end
  else
    selected_key = ""
    active_key = ""
  end
end

local function draw_tab_context_popup()
  if r.ImGui_BeginPopup(ctx, "Instrument Tab Context") then
    local entry = find_entry_by_key(tab_context_key)
    if entry then
      local bypassed = entry.enabled == false
      local offline = entry.offline == true
      local changed_bypass, next_bypass = r.ImGui_Checkbox(ctx, "Bypass", bypassed)
      if changed_bypass then set_entry_bypass(entry, next_bypass); r.ImGui_CloseCurrentPopup(ctx) end
      local changed_offline, next_offline = r.ImGui_Checkbox(ctx, "Offline", offline)
      if changed_offline then set_entry_offline(entry, next_offline); r.ImGui_CloseCurrentPopup(ctx) end
      local track = resolve_entry_track(entry)
      if track and r.ImGui_BeginCombo then
        local current_input = math.floor(r.GetMediaTrackInfo_Value(track, "I_RECINPUT") or -1)
        if r.ImGui_BeginCombo(ctx, "MIDI input", midi_input_label(current_input)) then
          local options = midi_input_options()
          for option_index = 1, #options do
            local option = options[option_index]
            local selected = current_input == option.value
            if r.ImGui_Selectable(ctx, option.label, selected) then
              set_track_midi_input(track, option.value)
              current_input = option.value
            end
            if selected and r.ImGui_SetItemDefaultFocus then r.ImGui_SetItemDefaultFocus(ctx) end
          end
          r.ImGui_EndCombo(ctx)
        end
      end
      r.ImGui_Separator(ctx)
      if r.ImGui_Selectable(ctx, "Remove") then remove_entry(entry); r.ImGui_CloseCurrentPopup(ctx) end
    else
      r.ImGui_TextDisabled(ctx, "Instrument not found")
    end
    r.ImGui_EndPopup(ctx)
  end
end

local function draw_settings_popup()
  if r.ImGui_BeginPopup(ctx, "Instrument Tabs Settings") then
    if r.ImGui_Button(ctx, "Scan / Refresh", 132, 0) then scan_instruments(true) end
    if r.ImGui_SliderInt then
      local changed_overlap, next_overlap = r.ImGui_SliderInt(ctx, "Plugin top overlap", settings.plugin_overlap_y, 0, 60, "%d px")
      if changed_overlap then settings.plugin_overlap_y = next_overlap; ext_set_number("plugin_overlap_y", next_overlap); pending_place_until = r.time_precise() + 0.5 end
    end
    local changed_start, next_start = r.ImGui_Checkbox(ctx, "Open instrument on start", settings.auto_open_on_start)
    if changed_start then settings.auto_open_on_start = next_start; ext_set_bool("auto_open_on_start", next_start); if next_start and active_key == "" then startup_open_done = false; open_startup_instrument() end end
    local changed_capture, next_capture = r.ImGui_Checkbox(ctx, "Capture externally opened instruments", settings.capture_external_floating)
    if changed_capture then settings.capture_external_floating = next_capture; ext_set_bool("capture_external_floating", next_capture); external_open_state = {} end
    local changed_select, next_select = r.ImGui_Checkbox(ctx, "Select track on tab change", settings.select_track_on_open)
    if changed_select then settings.select_track_on_open = next_select; ext_set_bool("select_track_on_open", next_select) end
    r.ImGui_EndPopup(ctx)
  end
end

local function draw_toolbar()
  local active_entry = find_entry_by_key(active_key)
  local label = active_entry and (active_entry.track_name .. " / " .. active_entry.fx_label) or "Select an instrument"
  if r.ImGui_Button(ctx, "+", 28, 0) then r.ImGui_OpenPopup(ctx, "Add Instrument Menu") end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Add instrument") end
  draw_add_instrument_popup()
  r.ImGui_SameLine(ctx)
  r.ImGui_TextColored(ctx, theme.text_dim, label)
  r.ImGui_SameLine(ctx)
  if r.ImGui_SetCursorPosX and r.ImGui_GetWindowSize then
    local window_w = select(1, r.ImGui_GetWindowSize(ctx))
    r.ImGui_SetCursorPosX(ctx, math.max(0, window_w - 62))
  end
  if r.ImGui_Button(ctx, "...", 28, 0) then r.ImGui_OpenPopup(ctx, "Instrument Tabs Settings") end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Settings") end
  r.ImGui_SameLine(ctx, 0, 7)
  local dot_x, dot_y = r.ImGui_GetCursorScreenPos(ctx)
  local dot_size = 18
  if r.ImGui_InvisibleButton then
    if r.ImGui_InvisibleButton(ctx, "##close_script", dot_size, dot_size) then close_requested = true end
  elseif r.ImGui_Button(ctx, "##close_script", dot_size, dot_size) then
    close_requested = true
  end
  local dot_col = r.ImGui_IsItemHovered(ctx) and 0xFF6B6BFF or 0xD84A4AFF
  r.ImGui_DrawList_AddCircleFilled(r.ImGui_GetWindowDrawList(ctx), dot_x + dot_size * 0.5, dot_y + dot_size * 0.5, 5.5, dot_col, 18)
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Close") end
  draw_settings_popup()
end

local function tab_width(entry)
  if tab_width_cache[entry.key] then return tab_width_cache[entry.key] end
  local text_w = 88
  if r.ImGui_CalcTextSize then text_w = r.ImGui_CalcTextSize(ctx, entry_label(entry)) or text_w end
  local width = clamp(text_w + 34, 92, 220)
  tab_width_cache[entry.key] = width
  return width
end

local function scroll_active_tab_into_view(view_width)
  local cursor = 0
  for entry_index = 1, #instruments do
    local entry = instruments[entry_index]
    local width = tab_width(entry)
    if entry.key == selected_key then
      if cursor < tab_scroll_x then tab_scroll_x = cursor end
      if cursor + width > tab_scroll_x + view_width then tab_scroll_x = cursor + width - view_width end
      return
    end
    cursor = cursor + width + 4
  end
end

local function draw_custom_tabs()
  local draw_list = r.ImGui_GetWindowDrawList(ctx)
  local x, y = r.ImGui_GetCursorScreenPos(ctx)
  local available_w = select(1, r.ImGui_GetContentRegionAvail(ctx))
  local tab_h = 26
  local arrow_w = 24
  local total_w = 0
  for entry_index = 1, #instruments do total_w = total_w + tab_width(instruments[entry_index]) + 4 end
  total_w = math.max(0, total_w - 4)
  local overflow = total_w > available_w
  local list_x = x
  local list_w = available_w
  if overflow then
    list_x = x + arrow_w + 4
    list_w = math.max(1, available_w - (arrow_w * 2) - 8)
    if r.ImGui_Button(ctx, "<##tabs_left", arrow_w, tab_h) then tab_scroll_x = math.max(0, tab_scroll_x - list_w * 0.65) end
    r.ImGui_SameLine(ctx, 0, 4)
  end
  tab_scroll_x = clamp(tab_scroll_x, 0, math.max(0, total_w - list_w))
  scroll_active_tab_into_view(list_w)
  r.ImGui_DrawList_PushClipRect(draw_list, list_x, y - 1, list_x + list_w, y + tab_h, true)
  local cursor = list_x - tab_scroll_x
  for entry_index = 1, #instruments do
    local entry = instruments[entry_index]
    local width = tab_width(entry)
    local tab_x1 = cursor
    local tab_x2 = cursor + width
    if tab_x2 >= list_x and tab_x1 <= list_x + list_w then
      local active = selected_key == entry.key
      local mouse_x, mouse_y = r.ImGui_GetMousePos(ctx)
      local hovered = mouse_x >= tab_x1 and mouse_x <= tab_x2 and mouse_y >= y and mouse_y <= y + tab_h
      local bg = active and theme.tab_active or (hovered and theme.tab_hover or theme.tab_bg)
      local text_col = active and theme.text_active or theme.text_tab
      r.ImGui_DrawList_AddRectFilled(draw_list, tab_x1, y, tab_x2, y + tab_h - 1, bg, 5)
      r.ImGui_DrawList_AddRect(draw_list, tab_x1, y, tab_x2, y + tab_h - 1, active and theme.accent or theme.border, 5, 0, active and 1.4 or 0.8)
      r.ImGui_DrawList_AddText(draw_list, tab_x1 + 12, y + 6, text_col, entry_label(entry))
      if hovered and r.ImGui_IsMouseClicked and r.ImGui_IsMouseClicked(ctx, 0) then request_activate_entry(entry) end
      if hovered and r.ImGui_IsMouseClicked and r.ImGui_IsMouseClicked(ctx, 1) then tab_context_key = entry.key; r.ImGui_OpenPopup(ctx, "Instrument Tab Context") end
      if hovered then r.ImGui_SetTooltip(ctx, entry.track_name .. "\n" .. entry.fx_name) end
    end
    cursor = cursor + width + 4
  end
  r.ImGui_DrawList_PopClipRect(draw_list)
  draw_tab_context_popup()
  r.ImGui_Dummy(ctx, list_w, tab_h)
  if overflow then
    r.ImGui_SameLine(ctx, 0, 4)
    if r.ImGui_Button(ctx, ">##tabs_right", arrow_w, tab_h) then tab_scroll_x = math.min(math.max(0, total_w - list_w), tab_scroll_x + list_w * 0.65) end
  end
  if #instruments == 0 then r.ImGui_TextColored(ctx, theme.text_dim, "No instrument FX found.") end
end

local function update_plugin_rect_from_topbar()
  local window_left, window_top = r.ImGui_GetWindowPos(ctx)
  local _, window_height = r.ImGui_GetWindowSize(ctx)
  local _, viewport_top, _, viewport_height = main_viewport_rect()
  local plugin_top = window_top + window_height - clamp(settings.plugin_overlap_y, 0, 48)
  local viewport_bottom = viewport_top + viewport_height - 12
  local active_entry = find_entry_by_key(active_key)
  local size = cached_fx_size(active_entry)
  host_rect.left = window_left + topbar_side_overhang
  host_rect.top = plugin_top
  host_rect.width = math.max(180, size.width)
  host_rect.height = math.max(140, math.min(size.height, viewport_bottom - plugin_top))
end

local function draw_blocked_state_window()
  local entry = find_entry_by_key(active_key)
  local state = entry_blocked_state(entry)
  if not state or host_rect.width < 120 or host_rect.height < 90 then return end
  local top_offset = clamp(settings.plugin_overlap_y, 0, 48)
  local state_top = host_rect.top + top_offset
  local state_height = math.max(120, host_rect.height - top_offset)
  r.ImGui_SetNextWindowPos(ctx, host_rect.left, state_top, imgui_flag("ImGui_Cond_Always"))
  r.ImGui_SetNextWindowSize(ctx, host_rect.width, state_height, imgui_flag("ImGui_Cond_Always"))
  if r.ImGui_SetNextWindowBgAlpha then r.ImGui_SetNextWindowBgAlpha(ctx, 0.76) end
  local flags = 0
  flags = add_imgui_flag(flags, "ImGui_WindowFlags_NoTitleBar")
  flags = add_imgui_flag(flags, "ImGui_WindowFlags_NoResize")
  flags = add_imgui_flag(flags, "ImGui_WindowFlags_NoMove")
  flags = add_imgui_flag(flags, "ImGui_WindowFlags_NoScrollbar")
  flags = add_imgui_flag(flags, "ImGui_WindowFlags_NoScrollWithMouse")
  flags = add_imgui_flag(flags, "ImGui_WindowFlags_NoSavedSettings")
  flags = add_imgui_flag(flags, "ImGui_WindowFlags_TopMost")
  flags = add_imgui_flag(flags, "ImGui_WindowFlags_NoBackground")
  local visible = r.ImGui_Begin(ctx, "TK Instrument Tabs Blocked State", true, flags)
  if visible then
    local draw_list = r.ImGui_GetWindowDrawList(ctx)
    local x, y = r.ImGui_GetWindowPos(ctx)
    local w, h = r.ImGui_GetWindowSize(ctx)
    r.ImGui_DrawList_AddRectFilled(draw_list, x, y, x + w, y + h, blend(theme.window_bg, 0x000000B8, 0.18), 0)
    r.ImGui_DrawList_AddRect(draw_list, x, y, x + w, y + h, blend(theme.border, 0x000000AA, 0.25), 0, 0, 1.0)
    local pushed_status_font = false
    if status_font and r.ImGui_PushFont then
      r.ImGui_PushFont(ctx, status_font, 112)
      pushed_status_font = true
    elseif r.ImGui_SetWindowFontScale then
      r.ImGui_SetWindowFontScale(ctx, 7.8)
    end
    local text_w, text_h = 120, 24
    if r.ImGui_CalcTextSize then text_w, text_h = r.ImGui_CalcTextSize(ctx, state) end
    r.ImGui_SetCursorPos(ctx, math.max(0, (w - text_w) * 0.5), math.max(0, (h - text_h) * 0.5 - 42))
    r.ImGui_TextColored(ctx, state == "OFFLINE" and 0xE06C75FF or 0xE5C07BFF, state)
    if pushed_status_font and r.ImGui_PopFont then
      r.ImGui_PopFont(ctx)
    elseif r.ImGui_SetWindowFontScale then
      r.ImGui_SetWindowFontScale(ctx, 1.0)
    end
    local subtitle = entry.track_name .. " / " .. entry.fx_label
    local subtitle_w = 240
    if r.ImGui_CalcTextSize then subtitle_w = r.ImGui_CalcTextSize(ctx, subtitle) end
    r.ImGui_SetCursorPos(ctx, math.max(0, (w - subtitle_w) * 0.5), math.max(0, (h * 0.5) + 72))
    r.ImGui_TextColored(ctx, theme.text_dim, subtitle)
  end
  r.ImGui_End(ctx)
end

local function maintain_active_window()
  if active_key == "" then return end
  local active_entry = find_entry_by_key(active_key)
  if entry_blocked_state(active_entry) then close_pending_previous(); return end
  local now = r.time_precise()
  if now - last_place_time >= 0.08 then
    if place_active_window() then close_pending_previous(); pending_place_until = 0 end
    last_place_time = now
  end
  if pending_close_key ~= "" and pending_close_deadline > 0 and now >= pending_close_deadline then
    close_pending_previous()
  end
end

local function capture_external_floating_window()
  if not settings.capture_external_floating or not r.TrackFX_GetFloatingWindow then return end
  local now = r.time_precise()
  if now - last_external_watch_time < 0.12 then return end
  last_external_watch_time = now
  local opened_entry = nil
  local current_open_state = {}
  for entry_index = 1, #instruments do
    local entry = instruments[entry_index]
    local track = resolve_entry_track(entry)
    local hwnd = track and safe_trackfx_get_floating_window(track, entry.fx_index) or nil
    local is_open = hwnd ~= nil
    current_open_state[entry.key] = is_open
    if is_open and not external_open_state[entry.key] and entry.key ~= active_key then opened_entry = entry end
  end
  external_open_state = current_open_state
  if not opened_entry then return end
  local previous_key = active_key
  pending_activate_key = ""
  pending_activate_frames = 0
  selected_key = opened_entry.key
  active_key = opened_entry.key
  update_topbar_width_from_size(cached_fx_size(opened_entry).width)
  pending_place_until = now + 1.25
  last_place_time = 0
  if settings.select_track_on_open and r.SetOnlyTrackSelected then
    local track = resolve_entry_track(opened_entry)
    if track then r.SetOnlyTrackSelected(track) end
  end
  if previous_key ~= "" and previous_key ~= opened_entry.key then
    pending_close_key = previous_key
    pending_close_deadline = now + 0.75
  end
end

local function cleanup()
  if cleanup_done then return end
  cleanup_done = true
  scan_instruments(true)
  close_all_instruments()
  if r.ImGui_DestroyContext and ctx then r.ImGui_DestroyContext(ctx) end
end

local function loop()
  scan_instruments(force_scan)
  close_existing_instruments_on_start()
  open_startup_instrument()
  r.ImGui_SetNextWindowSize(ctx, topbar_width + topbar_side_overhang * 2, topbar_height, imgui_flag("ImGui_Cond_Always"))
  local window_flags = 0
  window_flags = add_imgui_flag(window_flags, "ImGui_WindowFlags_NoScrollbar")
  window_flags = add_imgui_flag(window_flags, "ImGui_WindowFlags_NoScrollWithMouse")
  window_flags = add_imgui_flag(window_flags, "ImGui_WindowFlags_NoTitleBar")
  window_flags = add_imgui_flag(window_flags, "ImGui_WindowFlags_NoResize")
  window_flags = add_imgui_flag(window_flags, "ImGui_WindowFlags_TopMost")
  window_flags = add_imgui_flag(window_flags, "ImGui_WindowFlags_NoBackground")
  local theme_stack = push_theme()
  local visible, open = r.ImGui_Begin(ctx, SCRIPT_NAME, true, window_flags)
  if visible then
    draw_topbar_background()
    draw_toolbar()
    if r.ImGui_SetCursorPosY then r.ImGui_SetCursorPosY(ctx, math.max(0, topbar_height - 31)) end
    draw_custom_tabs()
    if not r.JS_Window_SetPosition or not r.TrackFX_GetFloatingWindow then r.ImGui_TextColored(ctx, theme.text_dim, "js_ReaScriptAPI is not available") end
    update_plugin_rect_from_topbar()
  end
  r.ImGui_End(ctx)
  if visible then draw_blocked_state_window() end
  pop_theme(theme_stack)
  if close_requested then
    cleanup()
    return
  end
  process_pending_activation()
  capture_external_floating_window()
  maintain_active_window()
  if open then
    r.defer(loop)
  else
    cleanup()
  end
end

if r.atexit then r.atexit(cleanup) end

loop()