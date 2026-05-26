local r = reaper
local Theme = require("core.theme")
local UI = require("core.ui")

local M = {
  id = "instrument_rack",
  title = "Instrument Rack",
  icon = "FX",
  version = "0.1.0"
}

local EXT_SECTION = "TK_WORKBENCH_INSTRUMENT_RACK"
local REC_FX_OFFSET = 0x1000000

local state = {
  screenshot_path = r.GetResourcePath() .. "/Scripts/TK Scripts/FX/Screenshots/",
  screenshot_index = nil,
  screenshot_cache = {},
  screenshot_missing = {},
  pinned_params = {},
  pinned_project = nil,
  collapsed = {},
  drop_mouse_was_down = false,
  last_external_drag = nil,
  pending_param_action = nil
}

local defaults = {
  pinned_track_guid = "",
  add_fx_target = "tk_fx_browser",
  show_screenshots = true,
  screenshot_height = 90,
  show_track_fx = true,
  show_pinned_params = true,
  show_input_fx = false,
  show_selected_item_fx = false,
  show_ab = false,
  tile_compact = false,
  body_collapsed = false
}

local function ensure_settings(app)
  app.settings.instrument_rack = app.settings.instrument_rack or {}
  local settings = app.settings.instrument_rack
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

local function validate_item(item)
  if not item then return false end
  if r.ValidatePtr2 then return r.ValidatePtr2(0, item, "MediaItem*") end
  if r.ValidatePtr then return r.ValidatePtr(item, "MediaItem*") end
  return true
end

local function validate_take(take)
  if not take then return false end
  if r.ValidatePtr2 then return r.ValidatePtr2(0, take, "MediaItem_Take*") end
  if r.ValidatePtr then return r.ValidatePtr(take, "MediaItem_Take*") end
  return true
end

local function track_guid(track)
  if not validate_track(track) then return "" end
  if track == r.GetMasterTrack(0) then return "MASTER" end
  return r.GetTrackGUID(track) or ""
end

local function find_track_by_guid(guid)
  if not guid or guid == "" then return nil end
  if guid == "MASTER" then return r.GetMasterTrack(0) end
  if r.BR_GetMediaTrackByGUID then
    local track = r.BR_GetMediaTrackByGUID(0, guid)
    if validate_track(track) then return track end
  end
  for index = 0, r.CountTracks(0) - 1 do
    local track = r.GetTrack(0, index)
    if track and r.GetTrackGUID(track) == guid then return track end
  end
  return nil
end

local function get_target_track(settings)
  local pinned = find_track_by_guid(settings.pinned_track_guid)
  if pinned then return pinned end
  local master = r.GetMasterTrack(0)
  if master and r.IsTrackSelected and r.IsTrackSelected(master) then return master end
  local selected = r.GetSelectedTrack(0, 0)
  if selected then return selected end
  return r.GetTrack(0, 0)
end

local function get_track_label(track)
  if not validate_track(track) then return "No track" end
  if track == r.GetMasterTrack(0) then return "MASTER" end
  local index = math.floor(r.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER") or 0)
  local _, name = r.GetTrackName(track)
  if not name or name == "" then name = "Track " .. tostring(index) end
  return tostring(index) .. " - " .. name
end

local function get_selected_take(target_track)
  local item = r.GetSelectedMediaItem(0, 0)
  if not validate_item(item) then return nil, nil end
  if validate_track(target_track) and r.GetMediaItemTrack(item) ~= target_track then return item, nil, false end
  local take = r.GetActiveTake(item)
  if not validate_take(take) then return item, nil end
  return item, take, true
end

local function get_take_label(take)
  if not validate_take(take) then return "No selected item" end
  local ok, name = r.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)
  if ok and name and name ~= "" then return name end
  return r.TakeIsMIDI(take) and "MIDI take" or "Audio take"
end

local function get_available_width(ctx)
  local width = r.ImGui_GetContentRegionAvail(ctx)
  return tonumber(width) or 0
end

local function get_centered_item_width(ctx)
  local width = get_available_width(ctx)
  if width <= 0 then return 220 end
  if width < 240 then return math.max(1, width) end
  return math.min(width - 12, 560)
end

local function center_next_item(ctx, item_width)
  local width = get_available_width(ctx)
  if width > item_width then
    r.ImGui_SetCursorPosX(ctx, r.ImGui_GetCursorPosX(ctx) + math.floor((width - item_width) * 0.5))
  end
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
  local name = strip_x86(value):lower()
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

local function build_screenshot_index(force)
  if state.screenshot_index and not force then return end
  state.screenshot_index = {}
  if not r.file_exists(state.screenshot_path) then return end
  local index = 0
  while true do
    local file_name = r.EnumerateFiles(state.screenshot_path, index)
    if not file_name then break end
    local base = file_name:match("(.+)%.png$") or file_name:match("(.+)%.jpg$") or file_name:match("(.+)%.jpeg$")
    if base then state.screenshot_index[normalize_plugin_name(base)] = file_name end
    index = index + 1
  end
end

local function file_exists(path)
  if r.file_exists then return r.file_exists(path) end
  local file = io.open(path, "rb")
  if file then file:close(); return true end
  return false
end

local function current_project()
  local project = r.EnumProjects(-1, "")
  return project or 0
end

local function clean_storage_field(value)
  return tostring(value or ""):gsub("[\t\r\n]", " ")
end

local function get_fx_guid(track, fx_index)
  local guid = r.TrackFX_GetFXGUID(track, fx_index)
  if guid and guid ~= "" then return guid end
  return "INDEX:" .. tostring(fx_index)
end

local function find_fx_index_by_guid(track, fx_guid)
  if not validate_track(track) or not fx_guid or fx_guid == "" then return nil end
  local normal_count = r.TrackFX_GetCount(track) or 0
  for index = 0, normal_count - 1 do
    if get_fx_guid(track, index) == fx_guid then return index end
  end
  local input_count = r.TrackFX_GetRecCount and r.TrackFX_GetRecCount(track) or 0
  for index = 0, input_count - 1 do
    local fx_index = REC_FX_OFFSET + index
    if get_fx_guid(track, fx_index) == fx_guid then return fx_index end
  end
  local fallback = fx_guid:match("^INDEX:(%-?%d+)$")
  return fallback and tonumber(fallback) or nil
end

local function param_key(fx_guid, param_idx)
  return tostring(fx_guid or "") .. "|" .. tostring(param_idx or -1)
end

local function load_pinned_params()
  local project = current_project()
  state.pinned_project = project
  state.pinned_params = {}
  if not r.GetProjExtState then return end
  local _, content = r.GetProjExtState(project, EXT_SECTION, "pinned_params")
  if not content or content == "" then return end
  for line in content:gmatch("[^\r\n]+") do
    local track_id, fx_guid, param_idx, param_name, fx_name = line:match("^([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t(.*)$")
    param_idx = tonumber(param_idx)
    if track_id and track_id ~= "" and fx_guid and fx_guid ~= "" and param_idx then
      state.pinned_params[track_id] = state.pinned_params[track_id] or {}
      state.pinned_params[track_id][param_key(fx_guid, param_idx)] = {
        track_guid = track_id,
        fx_guid = fx_guid,
        param_idx = param_idx,
        param_name = param_name or "",
        fx_name = fx_name or ""
      }
    end
  end
end

local function ensure_pinned_params_loaded()
  local project = current_project()
  if state.pinned_project ~= project then load_pinned_params() end
end

local function save_pinned_params()
  if not r.SetProjExtState then return end
  ensure_pinned_params_loaded()
  local lines = {}
  for track_id, entries in pairs(state.pinned_params) do
    for _, entry in pairs(entries) do
      lines[#lines + 1] = table.concat({
        clean_storage_field(track_id),
        clean_storage_field(entry.fx_guid),
        tostring(entry.param_idx),
        clean_storage_field(entry.param_name),
        clean_storage_field(entry.fx_name)
      }, "\t")
    end
  end
  table.sort(lines)
  r.SetProjExtState(current_project(), EXT_SECTION, "pinned_params", table.concat(lines, "\n"))
end

local function get_pinned_for_fx(track, fx_index)
  ensure_pinned_params_loaded()
  local track_id = track_guid(track)
  local fx_guid = get_fx_guid(track, fx_index)
  local result = {}
  local entries = state.pinned_params[track_id]
  if not entries then return result end
  local param_count = r.TrackFX_GetNumParams(track, fx_index)
  for _, entry in pairs(entries) do
    if entry.fx_guid == fx_guid and entry.param_idx >= 0 and entry.param_idx < param_count then
      result[#result + 1] = entry
    end
  end
  table.sort(result, function(left, right) return (left.param_name or "") < (right.param_name or "") end)
  return result
end

local function pin_parameter(app, track, fx_index, param_idx)
  if not validate_track(track) or not param_idx or param_idx < 0 then return end
  ensure_pinned_params_loaded()
  local track_id = track_guid(track)
  local fx_guid = get_fx_guid(track, fx_index)
  state.pinned_params[track_id] = state.pinned_params[track_id] or {}
  local key = param_key(fx_guid, param_idx)
  if state.pinned_params[track_id][key] then
    app.status = "Parameter already pinned"
    return
  end
  if #get_pinned_for_fx(track, fx_index) >= 4 then
    app.status = "Parameter slots are full"
    return
  end
  local _, fx_name = r.TrackFX_GetFXName(track, fx_index, "")
  local _, param_name = r.TrackFX_GetParamName(track, fx_index, param_idx, "")
  state.pinned_params[track_id][key] = {
    track_guid = track_id,
    fx_guid = fx_guid,
    param_idx = param_idx,
    param_name = param_name or ("Param " .. tostring(param_idx)),
    fx_name = fx_name or ""
  }
  save_pinned_params()
  app.status = "Pinned " .. (param_name ~= "" and param_name or ("Param " .. tostring(param_idx)))
end

local function unpin_parameter(app, track, fx_index, param_idx)
  ensure_pinned_params_loaded()
  local track_id = track_guid(track)
  local entries = state.pinned_params[track_id]
  if not entries then return end
  entries[param_key(get_fx_guid(track, fx_index), param_idx)] = nil
  save_pinned_params()
  app.status = "Parameter unpinned"
end

local function queue_param_action(action, track, fx_index, param_idx)
  if not validate_track(track) or not action or not param_idx then return end
  state.pending_param_action = {
    action = action,
    track_guid = track_guid(track),
    fx_guid = get_fx_guid(track, fx_index),
    param_idx = param_idx,
    delay = 1,
    defer_frames = action == "modulate" and 6 or 1,
    wait_mouse = action == "modulate"
  }
end

local function mouse_buttons_down()
  if not r.JS_Mouse_GetState then return false end
  return (r.JS_Mouse_GetState(0xFF) & 0xFF) ~= 0
end

local function nudge_param_as_last_touched(track, fx_index, param_idx)
  local _, _, minv, maxv = r.TrackFX_GetParamEx(track, fx_index, param_idx)
  local cur = r.TrackFX_GetParam(track, fx_index, param_idx)
  local range = (maxv or 1) - (minv or 0)
  if range == 0 then range = 1 end
  local eps = range * 1e-6
  local nudged = cur + eps
  if maxv and nudged > maxv then nudged = cur - eps end
  r.TrackFX_SetParam(track, fx_index, param_idx, nudged)
  r.TrackFX_SetParam(track, fx_index, param_idx, cur)
end

local function execute_param_action(app, pending)
  local track = find_track_by_guid(pending.track_guid)
  local fx_index = find_fx_index_by_guid(track, pending.fx_guid)
  if not validate_track(track) or not fx_index then return end
  if pending.action == "learn" then
    nudge_param_as_last_touched(track, fx_index, pending.param_idx)
    r.Main_OnCommand(41144, 0)
    app.status = "Opened MIDI learn"
  end
end

local function defer_param_action(app, pending, frames)
  if frames > 0 or (pending.wait_mouse and mouse_buttons_down()) then
    r.defer(function() defer_param_action(app, pending, frames - 1) end)
    return
  end
  execute_param_action(app, pending)
end

local function run_pending_param_action(app)
  local pending = state.pending_param_action
  if not pending then return end
  if pending.delay and pending.delay > 0 then
    pending.delay = pending.delay - 1
    return
  end
  state.pending_param_action = nil
  r.defer(function() defer_param_action(app, pending, pending.defer_frames or 1) end)
end

local function draw_param_context_menu(app, ctx, track, fx_index, param_idx)
  local request_unpin = false
  local current_value = r.TrackFX_GetParam(track, fx_index, param_idx)
  if r.ImGui_MenuItem(ctx, "Reset") then
    local _, default_value = r.TrackFX_GetParamEx(track, fx_index, param_idx)
    r.TrackFX_SetParam(track, fx_index, param_idx, default_value or 0)
    app.status = "Parameter reset"
  end
  r.ImGui_Separator(ctx)
  if r.ImGui_MenuItem(ctx, "Learn (MIDI CC)") then
    queue_param_action("learn", track, fx_index, param_idx)
    app.status = "Opening MIDI learn"
  end
  if r.ImGui_MenuItem(ctx, "Modulate") then
    r.Main_OnCommand(41143, 0)
    app.status = "Opened parameter modulation"
  end
  if r.ImGui_MenuItem(ctx, "Show Envelope") then
    local envelope = r.GetFXEnvelope(track, fx_index, param_idx, true)
    if envelope then
      r.TrackList_AdjustWindows(false)
      app.status = "Parameter envelope shown"
    end
  end
  r.ImGui_Separator(ctx)
  if r.ImGui_MenuItem(ctx, "Unpin") then request_unpin = true end
  r.ImGui_Separator(ctx)
  if r.ImGui_MenuItem(ctx, "Open FX Chain") then r.TrackFX_Show(track, fx_index, 1) end
  if r.ImGui_MenuItem(ctx, "Open FX Window") then
    local hwnd = r.TrackFX_GetFloatingWindow(track, fx_index)
    r.TrackFX_Show(track, fx_index, hwnd and 2 or 3)
  end
  return request_unpin
end

local function get_screenshot_path(plugin_name)
  if not plugin_name or plugin_name == "" then return nil end
  local now = r.time_precise()
  local missing = state.screenshot_missing[plugin_name]
  if missing and now - missing < 600 then return nil end
  state.screenshot_missing[plugin_name] = nil
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
      entry.t = r.time_precise()
      return entry.img
    end
  end
  local ok, img = pcall(r.ImGui_CreateImage, path)
  if ok and img then
    pcall(r.ImGui_Attach, ctx, img)
    entry.img = img
    entry.t = r.time_precise()
    return img
  end
  return nil
end

local function select_only_track(track)
  if not validate_track(track) then return end
  r.Main_OnCommand(40297, 0)
  if track == r.GetMasterTrack(0) then
    if r.SetMasterTrackVisibility then r.SetMasterTrackVisibility(1) end
  else
    r.SetTrackSelected(track, true)
  end
end

local function open_add_fx_browser(app, track)
  local settings = ensure_settings(app)
  if not validate_track(track) then return end
  select_only_track(track)
  local target = settings.add_fx_target or "tk_fx_browser"
  if target == "native" then
    r.Main_OnCommand(40271, 0)
    app.status = "Opened native FX browser"
    return
  end
  if target == "plugin_browser" and app.modules_by_id and app.modules_by_id.plugin_browser then
    app.settings.active_module = "plugin_browser"
    if app.save_settings then app.save_settings() end
    app.status = "Opened Plugin Browser"
    return
  end
  if target == "plugin_browser" then
    app.status = "Plugin Browser module not loaded"
    return
  end
  local section = "TK_FX_BROWSER"
  local script_rel = "/Scripts/TK Scripts/FX/TK_FX_BROWSER.lua"
  local nice_name = "TK FX BROWSER"
  local running = r.GetExtState(section, "running") == "true"
  local heartbeat = tonumber(r.GetExtState(section, "heartbeat")) or 0
  local alive = running and (r.time_precise() - heartbeat < 2.0)
  if alive then
    local visible = r.GetExtState(section, "visibility")
    r.SetExtState(section, "visibility", visible == "hidden" and "visible" or "hidden", true)
    app.status = "Toggled " .. nice_name
    return
  end
  if running and not alive then r.SetExtState(section, "running", "false", true) end
  local script_path = r.GetResourcePath() .. script_rel
  if not file_exists(script_path) then
    app.status = nice_name .. " script not found"
    return
  end
  if r.AddRemoveReaScript then
    local cmd_id = r.AddRemoveReaScript(true, 0, script_path, true)
    if cmd_id and cmd_id ~= 0 then
      r.SetExtState(section, "visibility", "visible", true)
      r.Main_OnCommand(cmd_id, 0)
      app.status = "Opened " .. nice_name
      return
    end
  end
  app.status = "Start " .. nice_name .. " once from the Actions list"
end

local function get_track_header_color(track)
  if not validate_track(track) then return 0x44444488 end
  local native = r.GetTrackColor(track) or 0
  if native == 0 then return 0x44444488 end
  local cr, cg, cb = r.ColorFromNative(native)
  return ((cr & 0xFF) << 24) | ((cg & 0xFF) << 16) | ((cb & 0xFF) << 8) | 0xCC
end

local function luminance(rgba)
  local cr = (rgba >> 24) & 0xFF
  local cg = (rgba >> 16) & 0xFF
  local cb = (rgba >> 8) & 0xFF
  return (0.299 * cr + 0.587 * cg + 0.114 * cb) / 255
end

local function draw_header(app, ctx, settings, track)
  local label = get_track_label(track)
  local header_color = get_track_header_color(track)
  local text_color = luminance(header_color) > 0.55 and 0x000000FF or 0xFFFFFFFF
  local avail = get_available_width(ctx)
  local cursor_x, cursor_y = r.ImGui_GetCursorScreenPos(ctx)
  local pad_x, pad_y = 6, 3
  local text_w, text_h = r.ImGui_CalcTextSize(ctx, label)
  local bar_h = text_h + pad_y * 2
  local draw_list = r.ImGui_GetWindowDrawList(ctx)
  r.ImGui_DrawList_AddRectFilled(draw_list, cursor_x, cursor_y, cursor_x + avail, cursor_y + bar_h, header_color, 3)
  r.ImGui_DrawList_PushClipRect(draw_list, cursor_x + pad_x, cursor_y, cursor_x + avail - pad_x, cursor_y + bar_h)
  r.ImGui_DrawList_AddText(draw_list, cursor_x + pad_x, cursor_y + pad_y, text_color, label)
  r.ImGui_DrawList_PopClipRect(draw_list)
  r.ImGui_Dummy(ctx, avail, bar_h)
  if r.ImGui_Button(ctx, (settings.pinned_track_guid ~= "" and "Unpin" or "Pin") .. "##ir_pin") then
    if settings.pinned_track_guid ~= "" then
      settings.pinned_track_guid = ""
      app.status = "Instrument Rack follows selected track"
    elseif track then
      settings.pinned_track_guid = track_guid(track)
      app.status = "Instrument Rack pinned to " .. label
    end
    if app.save_settings then app.save_settings() end
  end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "Add FX##ir_add_top") then open_add_fx_browser(app, track) end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "Settings##ir_settings") then r.ImGui_OpenPopup(ctx, "Instrument Rack Settings") end
  if r.ImGui_BeginPopup(ctx, "Instrument Rack Settings") then
    local changed, value
    changed, value = r.ImGui_Checkbox(ctx, "Show screenshots", settings.show_screenshots)
    if changed then settings.show_screenshots = value; if app.save_settings then app.save_settings() end end
    changed, value = r.ImGui_Checkbox(ctx, "Show parameters", settings.show_pinned_params)
    if changed then settings.show_pinned_params = value; if app.save_settings then app.save_settings() end end
    changed, value = r.ImGui_Checkbox(ctx, "Show track FX", settings.show_track_fx)
    if changed then settings.show_track_fx = value; if app.save_settings then app.save_settings() end end
    changed, value = r.ImGui_Checkbox(ctx, "Show input FX", settings.show_input_fx)
    if changed then settings.show_input_fx = value; if app.save_settings then app.save_settings() end end
    changed, value = r.ImGui_Checkbox(ctx, "Show selected item FX", settings.show_selected_item_fx)
    if changed then settings.show_selected_item_fx = value; if app.save_settings then app.save_settings() end end
    changed, value = r.ImGui_Checkbox(ctx, "Compact tiles", settings.tile_compact)
    if changed then settings.tile_compact = value; if app.save_settings then app.save_settings() end end
    r.ImGui_SetNextItemWidth(ctx, 160)
    changed, value = r.ImGui_SliderInt(ctx, "Screenshot height", settings.screenshot_height or 90, 48, 180, "%d px")
    if changed then settings.screenshot_height = value; if app.save_settings then app.save_settings() end end
    r.ImGui_Text(ctx, "Add FX target")
    local targets = {
      { id = "tk_fx_browser", label = "TK FX Browser" },
      { id = "plugin_browser", label = "Plugin Browser" },
      { id = "native", label = "Native FX Browser" }
    }
    for _, target in ipairs(targets) do
      local selected = settings.add_fx_target == target.id
      if r.ImGui_MenuItem(ctx, target.label, nil, selected) then
        settings.add_fx_target = target.id
        if app.save_settings then app.save_settings() end
      end
    end
    if r.ImGui_Button(ctx, "Refresh screenshots##ir_refresh_screenshots") then
      state.screenshot_index = nil
      state.screenshot_cache = {}
      state.screenshot_missing = {}
      app.status = "Screenshot index refreshed"
    end
    r.ImGui_EndPopup(ctx)
  end
end

local function get_fx_short_name(fx_name)
  local name = clean_fx_name(fx_name or "")
  if name == "" then name = fx_name or "FX" end
  return name
end

local function get_wet_param_index(track, fx_index)
  local idx = r.TrackFX_GetParamFromIdent(track, fx_index, ":wet")
  if idx and idx >= 0 then return idx end
  return nil
end

local function get_fx_wet(track, fx_index)
  local idx = get_wet_param_index(track, fx_index)
  if not idx then return 1.0 end
  return r.TrackFX_GetParamNormalized(track, fx_index, idx) or 1.0
end

local function set_fx_wet(track, fx_index, value)
  local idx = get_wet_param_index(track, fx_index)
  if not idx then return end
  if value < 0 then value = 0 elseif value > 1 then value = 1 end
  r.TrackFX_SetParamNormalized(track, fx_index, idx, value)
end

local function draw_wet_popup(ctx, track, fx_index, wet_value)
  if r.ImGui_BeginPopup(ctx, "##ir_wet_pop") then
    r.ImGui_SetNextItemWidth(ctx, 150)
    local changed, value = r.ImGui_SliderDouble(ctx, "Wet##ir_wet_slider", wet_value, 0.0, 1.0, "%.2f")
    if changed then set_fx_wet(track, fx_index, value) end
    if r.ImGui_Button(ctx, "Reset##ir_wet_reset") then set_fx_wet(track, fx_index, 1.0) end
    r.ImGui_EndPopup(ctx)
  end
end

local function draw_preset_popup(ctx, track, fx_index)
  if r.ImGui_BeginPopup(ctx, "##ir_preset_pop") then
    local _, preset = r.TrackFX_GetPreset(track, fx_index, "")
    r.ImGui_Text(ctx, preset ~= "" and preset or "(no preset)")
    r.ImGui_Separator(ctx)
    if r.ImGui_Button(ctx, "Prev##ir_preset_prev") then r.TrackFX_NavigatePresets(track, fx_index, -1) end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Next##ir_preset_next") then r.TrackFX_NavigatePresets(track, fx_index, 1) end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Default##ir_preset_default") then r.TrackFX_NavigatePresets(track, fx_index, 0) end
    r.ImGui_EndPopup(ctx)
  end
end

local function delete_fx(app, track, fx_index, fx_name)
  if not validate_track(track) then return end
  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)
  r.TrackFX_Delete(track, fx_index)
  r.PreventUIRefresh(-1)
  r.Undo_EndBlock("Delete rack FX", -1)
  app.status = "Deleted " .. get_fx_short_name(fx_name)
end

local function add_external_fx(app, track, payload, insert_index)
  if not validate_track(track) or not payload or payload == "" then return end
  local names = {}
  for name in payload:gmatch("[^\n]+") do
    if name ~= "" then names[#names + 1] = name end
  end
  if #names == 0 then return end
  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)
  for offset, name in ipairs(names) do
    local target_index = insert_index and (-1000 - (insert_index + offset - 1)) or -1
    r.TrackFX_AddByName(track, name, false, target_index)
  end
  r.PreventUIRefresh(-1)
  r.Undo_EndBlock("Add FX to instrument rack", -1)
  r.SetExtState("TKFXB", "drag_consumed", "1", false)
  r.DeleteExtState("TKFXB", "drag_fx", false)
  if r.HasExtState("TKMIX", "rack_target") then r.DeleteExtState("TKMIX", "rack_target", false) end
  app.status = "Added " .. tostring(#names) .. " FX"
end

local function draw_fx_screenshot(ctx, settings, fx_name, width, height, enabled)
  if not settings.show_screenshots then return end
  local draw_list = r.ImGui_GetWindowDrawList(ctx)
  local x, y = r.ImGui_GetCursorScreenPos(ctx)
  r.ImGui_DrawList_AddRectFilled(draw_list, x, y, x + width, y + height, 0x111111FF, 3)
  local img = get_screenshot_image(ctx, fx_name)
  if img then
    local image_w, image_h = r.ImGui_Image_GetSize(img)
    local scale = math.min(width / image_w, height / image_h)
    local draw_w = image_w * scale
    local draw_h = image_h * scale
    local draw_x = x + (width - draw_w) * 0.5
    local draw_y = y + (height - draw_h) * 0.5
    r.ImGui_DrawList_AddImage(draw_list, img, draw_x, draw_y, draw_x + draw_w, draw_y + draw_h, 0, 0, 1, 1, enabled and 0xFFFFFFFF or 0xFFFFFF66)
  else
    local text = "no screenshot"
    local text_w = r.ImGui_CalcTextSize(ctx, text)
    r.ImGui_DrawList_AddText(draw_list, x + (width - text_w) * 0.5, y + height * 0.5 - 6, Theme.colors.text_dim, text)
  end
  r.ImGui_InvisibleButton(ctx, "##ir_screenshot_hit", width, height)
end

local function draw_small_button(ctx, draw_list, id, x, y, width, height, label, bg, fg, tooltip)
  r.ImGui_DrawList_AddRectFilled(draw_list, x, y, x + width, y + height, bg, 2)
  r.ImGui_DrawList_AddRect(draw_list, x, y, x + width, y + height, Theme.colors.border, 2, 0, 1)
  local text_w = r.ImGui_CalcTextSize(ctx, label)
  r.ImGui_DrawList_AddTextEx(draw_list, nil, 10, x + (width - text_w) * 0.5, y + 1, fg, label)
  r.ImGui_SetCursorScreenPos(ctx, x, y)
  r.ImGui_InvisibleButton(ctx, id, width, height)
  local clicked = r.ImGui_IsItemClicked(ctx, 0)
  local right_clicked = r.ImGui_IsItemClicked(ctx, 1)
  if tooltip and r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, tooltip) end
  return clicked, right_clicked
end

local function draw_pin_menu(app, ctx, track, fx_index)
  if r.GetLastTouchedFX then
    local ok, track_index, touched_fx, param_idx = r.GetLastTouchedFX()
    local touched_track = nil
    if ok then
      if track_index == 0 then touched_track = r.GetMasterTrack(0) else touched_track = r.GetTrack(0, track_index - 1) end
    end
    local matches = ok and touched_track == track and touched_fx == fx_index and param_idx and param_idx >= 0
    local label = "Pin last touched parameter"
    if matches then
      local _, param_name = r.TrackFX_GetParamName(track, fx_index, param_idx, "")
      label = "Pin last touched: " .. (param_name ~= "" and param_name or ("Param " .. tostring(param_idx)))
    end
    if r.ImGui_MenuItem(ctx, label, nil, false, matches) then pin_parameter(app, track, fx_index, param_idx) end
  end
  if r.ImGui_BeginMenu(ctx, "Pin parameter...") then
    local param_count = math.min(r.TrackFX_GetNumParams(track, fx_index), 200)
    for param_idx = 0, param_count - 1 do
      local _, param_name = r.TrackFX_GetParamName(track, fx_index, param_idx, "")
      if param_name == "" then param_name = "Param " .. tostring(param_idx) end
      if r.ImGui_MenuItem(ctx, param_name .. "##ir_pin_param_" .. tostring(param_idx)) then
        pin_parameter(app, track, fx_index, param_idx)
      end
    end
    r.ImGui_EndMenu(ctx)
  end
end

local function short_param_label(value)
  local label = tostring(value or "")
  if label == "" then return "Param" end
  if #label > 9 then return label:sub(1, 8) .. "." end
  return label
end

local function param_config_key(param_idx, name)
  return "param." .. tostring(param_idx) .. "." .. name
end

local function get_param_config_number(track, fx_index, param_idx, name)
  local ok, value = r.TrackFX_GetNamedConfigParm(track, fx_index, param_config_key(param_idx, name))
  if ok and value ~= nil and value ~= "" then return tonumber(value) end
  return nil
end

local function is_param_modulated(track, fx_index, param_idx)
  local keys = { "mod.active", "lfo.active", "acs.active", "plink.active" }
  for _, key in ipairs(keys) do
    local value = get_param_config_number(track, fx_index, param_idx, key)
    if value and value ~= 0 then return true end
  end
  return false
end

local function get_rack_param_value(track, fx_index, param_idx)
  if is_param_modulated(track, fx_index, param_idx) then
    local baseline = get_param_config_number(track, fx_index, param_idx, "mod.baseline")
    if baseline then return math.max(0, math.min(1, baseline)), true end
  end
  return r.TrackFX_GetParamNormalized(track, fx_index, param_idx), false
end

local function set_rack_param_value(track, fx_index, param_idx, value, uses_baseline)
  value = math.max(0, math.min(1, value or 0))
  if uses_baseline then
    r.TrackFX_SetNamedConfigParm(track, fx_index, param_config_key(param_idx, "mod.baseline"), tostring(value))
  else
    r.TrackFX_SetParamNormalized(track, fx_index, param_idx, value)
  end
end

local function draw_param_knob(app, ctx, draw_list, track, fx_index, entry, cx, cy, radius)
  local value, uses_baseline = get_rack_param_value(track, fx_index, entry.param_idx)
  local start_angle = math.pi * 0.75
  local end_angle = math.pi * 2.25
  local value_angle = start_angle + value * (end_angle - start_angle)
  local segments = radius < 8 and 12 or (radius < 14 and 18 or 24)
  r.ImGui_DrawList_AddCircleFilled(draw_list, cx + 1, cy + 1, radius, 0x00000066, segments)
  r.ImGui_DrawList_AddCircleFilled(draw_list, cx, cy, radius, 0x555555FF, segments)
  if value > 0.01 then
    r.ImGui_DrawList_PathArcTo(draw_list, cx, cy, radius - 2, start_angle, value_angle, segments)
    r.ImGui_DrawList_PathStroke(draw_list, 0xCCCCCCFF, 0, 2.5)
  end
  if value < 0.02 then
    local line_x = cx + math.cos(value_angle) * radius * 0.85
    local line_y = cy + math.sin(value_angle) * radius * 0.85
    r.ImGui_DrawList_AddLine(draw_list, cx, cy, line_x, line_y, 0xCCCCCCFF, 2)
  end
  if uses_baseline then
    local mod_value = r.TrackFX_GetParamNormalized(track, fx_index, entry.param_idx)
    mod_value = math.max(0, math.min(1, mod_value or 0))
    local mod_angle = start_angle + mod_value * (end_angle - start_angle)
    local outer_r = radius + 2
    r.ImGui_DrawList_PathArcTo(draw_list, cx, cy, outer_r, start_angle, end_angle, segments)
    r.ImGui_DrawList_PathStroke(draw_list, 0x7AA2F744, 0, 1.5)
    if mod_value > 0.001 then
      r.ImGui_DrawList_PathArcTo(draw_list, cx, cy, outer_r, start_angle, mod_angle, segments)
      r.ImGui_DrawList_PathStroke(draw_list, 0x7AA2F7FF, 0, 1.8)
    end
  end
  r.ImGui_DrawList_AddCircleFilled(draw_list, cx, cy, radius * 0.45, 0xCCCCCCFF, segments)
  local label = short_param_label(entry.param_name)
  local text_w = r.ImGui_CalcTextSize(ctx, label) * (8 / r.ImGui_GetFontSize(ctx))
  r.ImGui_DrawList_AddTextEx(draw_list, nil, 8, cx - text_w * 0.5, cy + radius + 1, 0xAAAAAAFF, label)
  r.ImGui_SetCursorScreenPos(ctx, cx - radius - 4, cy - radius - 4)
  r.ImGui_InvisibleButton(ctx, "##ir_param_knob_" .. tostring(entry.param_idx), (radius + 4) * 2, (radius + 4) * 2)
  if r.ImGui_IsItemActive(ctx) then
    local _, dy = r.ImGui_GetMouseDragDelta(ctx, 0, 0.0)
    if math.abs(dy) > 0 then
      local next_value = math.max(0, math.min(1, value - dy * 0.005))
      set_rack_param_value(track, fx_index, entry.param_idx, next_value, uses_baseline)
      r.ImGui_ResetMouseDragDelta(ctx, 0)
    end
  end
  if r.ImGui_IsItemClicked(ctx, 1) then
    nudge_param_as_last_touched(track, fx_index, entry.param_idx)
    r.ImGui_OpenPopup(ctx, "##ir_param_menu_" .. tostring(entry.param_idx))
  end
  if r.ImGui_BeginPopup(ctx, "##ir_param_menu_" .. tostring(entry.param_idx)) then
    if draw_param_context_menu(app, ctx, track, fx_index, entry.param_idx) then unpin_parameter(app, track, fx_index, entry.param_idx) end
    r.ImGui_EndPopup(ctx)
  end
  if r.ImGui_IsItemHovered(ctx) or r.ImGui_IsItemActive(ctx) then
    local _, formatted = r.TrackFX_GetFormattedParamValue(track, fx_index, entry.param_idx, "")
    local prefix = uses_baseline and "Baseline: " or ""
    r.ImGui_SetTooltip(ctx, (entry.param_name or "Param") .. ": " .. prefix .. (formatted or string.format("%.0f%%", value * 100)))
  end
end

local function draw_empty_param_slot(app, ctx, draw_list, track, fx_index, cx, cy, radius, slot)
  r.ImGui_DrawList_AddCircle(draw_list, cx, cy, radius, 0x4A5360AA, 0, 1)
  local plus_w = r.ImGui_CalcTextSize(ctx, "+") * (10 / r.ImGui_GetFontSize(ctx))
  r.ImGui_DrawList_AddTextEx(draw_list, nil, 10, cx - plus_w * 0.5, cy - 6, 0x66666688, "+")
  r.ImGui_SetCursorScreenPos(ctx, cx - radius - 4, cy - radius - 4)
  r.ImGui_InvisibleButton(ctx, "##ir_empty_param_" .. tostring(slot), (radius + 4) * 2, (radius + 4) * 2)
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Right-click to pin a parameter") end
  if r.ImGui_IsItemClicked(ctx, 1) then r.ImGui_OpenPopup(ctx, "##ir_empty_param_menu_" .. tostring(slot)) end
  if r.ImGui_BeginPopup(ctx, "##ir_empty_param_menu_" .. tostring(slot)) then
    draw_pin_menu(app, ctx, track, fx_index)
    r.ImGui_EndPopup(ctx)
  end
end

local function draw_param_slots(app, ctx, track, fx_index, item_width)
  local row_width = math.max(1, item_width - 14)
  local row_height = 54
  local x, y = r.ImGui_GetCursorScreenPos(ctx)
  local draw_list = r.ImGui_GetWindowDrawList(ctx)
  local pinned = get_pinned_for_fx(track, fx_index)
  r.ImGui_Dummy(ctx, row_width, row_height)
  r.ImGui_DrawList_AddLine(draw_list, x + 4, y + 3, x + row_width - 4, y + 3, 0x3D4450AA, 1)
  for slot = 1, 4 do
    local cell_width = row_width / 4
    local cx = x + (slot - 0.5) * cell_width
    local cy = y + 23
    local entry = pinned[slot]
    if entry then
      draw_param_knob(app, ctx, draw_list, track, fx_index, entry, cx, cy, 12)
    else
      draw_empty_param_slot(app, ctx, draw_list, track, fx_index, cx, cy, 12, slot)
    end
  end
  r.ImGui_SetCursorScreenPos(ctx, x, y + row_height)
end

local function reorder_fx(app, track, source_index, target_index, short_name)
  if not source_index or source_index == target_index then return end
  local destination = source_index < target_index and target_index + 1 or target_index
  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)
  r.TrackFX_CopyToTrack(track, source_index, track, destination, true)
  r.PreventUIRefresh(-1)
  r.Undo_EndBlock("Reorder rack FX", -1)
  app.status = "Reordered " .. short_name
end

local function handle_reorder_item(app, ctx, draw_list, track, fx_index, short_name, x, y, width, height)
  if r.ImGui_BeginDragDropSource(ctx, r.ImGui_DragDropFlags_SourceNoPreviewTooltip()) then
    r.ImGui_SetDragDropPayload(ctx, "TK_WORKBENCH_RACK_FX", tostring(fx_index))
    r.ImGui_Text(ctx, "Move: " .. short_name)
    r.ImGui_EndDragDropSource(ctx)
  end
  if r.ImGui_BeginDragDropTarget(ctx) then
    local ok_payload, payload = r.ImGui_AcceptDragDropPayload(ctx, "TK_WORKBENCH_RACK_FX")
    r.ImGui_DrawList_AddRect(draw_list, x - 1, y - 1, x + width + 1, y + height + 1, 0x44CC44FF, 3, 0, 2)
    local hint = "Insert here"
    local hint_w = r.ImGui_CalcTextSize(ctx, hint) * (11 / r.ImGui_GetFontSize(ctx))
    r.ImGui_DrawList_AddRectFilled(draw_list, x + (width - hint_w) * 0.5 - 4, y + height - 16, x + (width + hint_w) * 0.5 + 4, y + height - 2, 0x000000CC, 2)
    r.ImGui_DrawList_AddTextEx(draw_list, nil, 11, x + (width - hint_w) * 0.5, y + height - 14, 0x44CC44FF, hint)
    if ok_payload and payload and payload ~= "" then reorder_fx(app, track, tonumber(payload), fx_index, short_name) end
    r.ImGui_EndDragDropTarget(ctx)
  end
end

local function draw_fx_tile(app, ctx, settings, track, fx_index, item_width, allow_reorder)
  local _, fx_name = r.TrackFX_GetFXName(track, fx_index, "")
  local enabled = r.TrackFX_GetEnabled(track, fx_index)
  local offline = r.TrackFX_GetOffline(track, fx_index)
  local short_name = get_fx_short_name(fx_name)
  r.ImGui_PushID(ctx, "ir_fx_" .. tostring(fx_index))
  local flags = r.ImGui_WindowFlags_NoScrollbar() | r.ImGui_WindowFlags_NoScrollWithMouse()
  local shot_h = settings.show_screenshots and not settings.tile_compact and (settings.screenshot_height or 90) or 0
  local param_h = settings.show_pinned_params and 58 or 0
  local row1_h = 18
  local toolbar_h = 16
  local collapse_key = track_guid(track) .. "|" .. get_fx_guid(track, fx_index)
  local is_collapsed = state.collapsed[collapse_key] == true
  local title_h = is_collapsed and row1_h or (row1_h + toolbar_h + 2)
  local tile_h = is_collapsed and title_h or (title_h + shot_h + param_h + 4)
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), 0, 0)
  local tile_visible = r.ImGui_BeginChild(ctx, "##ir_fx_tile", item_width, tile_h, 0, flags)
  r.ImGui_PopStyleVar(ctx, 1)
  if tile_visible then
    local draw_list = r.ImGui_GetWindowDrawList(ctx)
    local bx, by = r.ImGui_GetCursorScreenPos(ctx)
    r.ImGui_DrawList_AddRectFilled(draw_list, bx, by, bx + item_width, by + tile_h, Theme.colors.frame_bg, 3)
    r.ImGui_DrawList_AddRect(draw_list, bx, by, bx + item_width, by + tile_h, enabled and Theme.colors.border or Theme.colors.danger, 3, 0, 1)

    local delete_x = bx + item_width - 10
    local delete_y = by + row1_h * 0.5
    r.ImGui_DrawList_AddCircleFilled(draw_list, delete_x, delete_y, 4, 0xCC3333FF)
    r.ImGui_SetCursorScreenPos(ctx, delete_x - 6, delete_y - 6)
    r.ImGui_InvisibleButton(ctx, "##ir_fx_delete", 12, 12)
    if r.ImGui_IsItemClicked(ctx, 0) then r.ImGui_OpenPopup(ctx, "##ir_delete_pop") end
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Delete FX") end

    local led_x = delete_x - 14
    r.ImGui_DrawList_AddCircleFilled(draw_list, led_x, by + row1_h * 0.5, 4, enabled and 0x44CC44FF or 0xCC3333FF)
    r.ImGui_SetCursorScreenPos(ctx, led_x - 6, by + 2)
    if r.ImGui_InvisibleButton(ctx, "##ir_fx_led", 12, 12) then
      r.TrackFX_SetEnabled(track, fx_index, not enabled)
      app.status = (enabled and "Bypassed " or "Enabled ") .. short_name
    end
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, enabled and "Bypass FX" or "Enable FX") end

    local chev_size = 12
    local chev_x = led_x - 20
    local chev_y = by + (row1_h - chev_size) * 0.5
    local chev_cx = chev_x + chev_size * 0.5
    local chev_cy = chev_y + chev_size * 0.5
    if is_collapsed then
      r.ImGui_DrawList_AddTriangleFilled(draw_list, chev_cx - 3, chev_cy - 3, chev_cx + 3, chev_cy, chev_cx - 3, chev_cy + 3, 0xAAAAAAFF)
    else
      r.ImGui_DrawList_AddTriangleFilled(draw_list, chev_cx - 3, chev_cy - 2, chev_cx + 3, chev_cy - 2, chev_cx, chev_cy + 3, 0xAAAAAAFF)
    end
    r.ImGui_SetCursorScreenPos(ctx, chev_x, chev_y)
    if r.ImGui_InvisibleButton(ctx, "##ir_fx_collapse", chev_size, chev_size) then state.collapsed[collapse_key] = not is_collapsed end
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, is_collapsed and "Expand" or "Collapse") end

    local name_max_w = math.max(20, chev_x - (bx + 6) - 4)
    r.ImGui_DrawList_PushClipRect(draw_list, bx + 6, by, bx + 6 + name_max_w, by + row1_h, true)
    r.ImGui_DrawList_AddText(draw_list, bx + 6, by + 2, enabled and Theme.colors.text or Theme.colors.text_dim, short_name)
    r.ImGui_DrawList_PopClipRect(draw_list)

    if not is_collapsed then
      local tb_y = by + row1_h
      local button_y = tb_y + 2
      local tx = bx + 6
      local wet_value = get_fx_wet(track, fx_index)
      local wet_alpha = math.floor((1 - math.max(0, math.min(1, wet_value))) * 0xCC + 0x44)
      local wet_bg = wet_value < 0.999 and (0x4488CC00 | wet_alpha) or 0x33333388
      local clicked_wet, right_wet = draw_small_button(ctx, draw_list, "##ir_fx_wet", tx, button_y, 18, 12, "W", wet_bg, 0xFFFFFFFF, string.format("Wet: %d%%", math.floor(wet_value * 100 + 0.5)))
      if clicked_wet then r.ImGui_OpenPopup(ctx, "##ir_wet_pop") end
      if right_wet then set_fx_wet(track, fx_index, 1.0) end
      draw_wet_popup(ctx, track, fx_index, wet_value)
      tx = tx + 22
      if draw_small_button(ctx, draw_list, "##ir_fx_float", tx, button_y, 14, 12, "F", 0x33333388, 0xFFFFFFFF, "Open floating") then
        local hwnd = r.TrackFX_GetFloatingWindow(track, fx_index)
        r.TrackFX_Show(track, fx_index, hwnd and 2 or 3)
      end
      tx = tx + 18
      if draw_small_button(ctx, draw_list, "##ir_fx_offline", tx, button_y, 14, 12, "O", offline and 0xAA3333FF or 0x33333388, 0xFFFFFFFF, offline and "Bring FX online" or "Set FX offline") then
        r.TrackFX_SetOffline(track, fx_index, not offline)
        app.status = (offline and "Brought online " or "Set offline ") .. short_name
      end
      tx = tx + 18
      if draw_small_button(ctx, draw_list, "##ir_fx_preset", tx, button_y, 14, 12, "P", 0x33333388, 0xFFFFFFFF, "Preset") then r.ImGui_OpenPopup(ctx, "##ir_preset_pop") end
      draw_preset_popup(ctx, track, fx_index)
      local sep_y = by + title_h - 1
      r.ImGui_DrawList_AddLine(draw_list, bx + 4, sep_y, bx + item_width - 4, sep_y, Theme.colors.separator, 1)

      if settings.show_screenshots and not settings.tile_compact then
        r.ImGui_SetCursorScreenPos(ctx, bx + 2, by + title_h)
        draw_fx_screenshot(ctx, settings, fx_name, item_width - 4, shot_h, enabled and not offline)
        if r.ImGui_IsItemClicked(ctx, 0) then
          local hwnd = r.TrackFX_GetFloatingWindow(track, fx_index)
          r.TrackFX_Show(track, fx_index, hwnd and 2 or 3)
        end
        if allow_reorder ~= false then handle_reorder_item(app, ctx, draw_list, track, fx_index, short_name, bx, by, item_width, tile_h) end
      end
      if settings.show_pinned_params then
        r.ImGui_SetCursorScreenPos(ctx, bx + 7, by + title_h + shot_h + 4)
        draw_param_slots(app, ctx, track, fx_index, item_width - 14)
      end
    end

    if r.ImGui_BeginPopup(ctx, "##ir_delete_pop") then
      r.ImGui_Text(ctx, "Delete this FX?")
      r.ImGui_Separator(ctx)
      if r.ImGui_Button(ctx, "Delete##ir_delete_confirm") then
        delete_fx(app, track, fx_index, fx_name)
        r.ImGui_CloseCurrentPopup(ctx)
      end
      r.ImGui_SameLine(ctx)
      if r.ImGui_Button(ctx, "Cancel##ir_delete_cancel") then r.ImGui_CloseCurrentPopup(ctx) end
      r.ImGui_EndPopup(ctx)
    end

    r.ImGui_SetCursorScreenPos(ctx, bx, by)
    if r.ImGui_InvisibleButton(ctx, "##ir_fx_title_hit", math.max(1, name_max_w + 8), row1_h) then
      local hwnd = r.TrackFX_GetFloatingWindow(track, fx_index)
      r.TrackFX_Show(track, fx_index, hwnd and 2 or 3)
    end
    if allow_reorder ~= false then handle_reorder_item(app, ctx, draw_list, track, fx_index, short_name, bx, by, item_width, tile_h) end
    if r.ImGui_BeginPopupContextItem(ctx, "##ir_fx_context") then
      if r.ImGui_MenuItem(ctx, enabled and "Bypass" or "Enable") then r.TrackFX_SetEnabled(track, fx_index, not enabled) end
      if r.ImGui_MenuItem(ctx, "Open floating") then
        local hwnd = r.TrackFX_GetFloatingWindow(track, fx_index)
        r.TrackFX_Show(track, fx_index, hwnd and 2 or 3)
      end
      if r.ImGui_MenuItem(ctx, offline and "Bring online" or "Set offline") then r.TrackFX_SetOffline(track, fx_index, not offline) end
      r.ImGui_Separator(ctx)
      if r.ImGui_MenuItem(ctx, "Remove") then delete_fx(app, track, fx_index, fx_name) end
      r.ImGui_EndPopup(ctx)
    end
    r.ImGui_EndChild(ctx)
  end
  r.ImGui_PopID(ctx)
end

local function mouse_release_state(ctx)
  local mouse_down
  if r.JS_Mouse_GetState then
    mouse_down = (r.JS_Mouse_GetState(1) & 1) == 1
  else
    mouse_down = r.ImGui_IsMouseDown(ctx, 0)
  end
  local released = state.drop_mouse_was_down and not mouse_down
  state.drop_mouse_was_down = mouse_down
  return mouse_down, released
end

local function update_external_drag(ctx)
  local external_drag = r.GetExtState("TKFXB", "drag_fx")
  local mouse_down, mouse_released = mouse_release_state(ctx)
  if external_drag ~= "" then state.last_external_drag = external_drag elseif not mouse_down then state.last_external_drag = nil end
  state.mouse_released = mouse_released
  state.mouse_down = mouse_down
end

local function draw_add_zone(app, ctx, settings, track, item_width, insert_index)
  local payload = state.last_external_drag or ""
  local label = payload ~= "" and "+ Drop to add FX" or "+ Add FX"
  local draw_list = r.ImGui_GetWindowDrawList(ctx)
  local x, y = r.ImGui_GetCursorScreenPos(ctx)
  r.ImGui_InvisibleButton(ctx, "##ir_add_zone", item_width, 36)
  local hovered = r.ImGui_IsItemHovered(ctx)
  local clicked = r.ImGui_IsItemClicked(ctx, 0)
  local border = payload ~= "" and Theme.colors.accent or (hovered and Theme.colors.frame_hover or Theme.colors.border)
  r.ImGui_DrawList_AddRect(draw_list, x, y, x + item_width, y + 36, border, 4, 0, payload ~= "" and 2 or 1)
  local text_w = r.ImGui_CalcTextSize(ctx, label)
  r.ImGui_DrawList_AddText(draw_list, x + (item_width - text_w) * 0.5, y + 12, payload ~= "" and Theme.colors.accent or Theme.colors.text_dim, label)
  if clicked then open_add_fx_browser(app, track) end
  if hovered then
    local guid = track_guid(track)
    if payload ~= "" and guid ~= "" then r.SetExtState("TKMIX", "rack_target", guid .. "|" .. tostring(insert_index or -1), false) end
    if payload ~= "" and state.mouse_released then add_external_fx(app, track, payload, insert_index) end
    local target = settings.add_fx_target == "native" and "native FX browser" or settings.add_fx_target == "plugin_browser" and "Plugin Browser" or "TK FX Browser"
    r.ImGui_SetTooltip(ctx, payload ~= "" and "Drop FX here" or "Open " .. target)
  end
  if r.ImGui_BeginDragDropTarget(ctx) then
    local ok_payload, workbench_payload = r.ImGui_AcceptDragDropPayload(ctx, "TK_WORKBENCH_FX_PLUGIN")
    if ok_payload and workbench_payload and workbench_payload ~= "" then add_external_fx(app, track, workbench_payload, insert_index) end
    r.ImGui_EndDragDropTarget(ctx)
  end
end

local function take_fx_enabled(take, fx_index)
  if r.TakeFX_GetEnabled then return r.TakeFX_GetEnabled(take, fx_index) end
  return true
end

local function take_fx_offline(take, fx_index)
  if r.TakeFX_GetOffline then return r.TakeFX_GetOffline(take, fx_index) end
  return false
end

local function set_take_fx_enabled(take, fx_index, enabled)
  if r.TakeFX_SetEnabled then r.TakeFX_SetEnabled(take, fx_index, enabled) end
end

local function set_take_fx_offline(take, fx_index, offline)
  if r.TakeFX_SetOffline then r.TakeFX_SetOffline(take, fx_index, offline) end
end

local function show_take_fx(take, fx_index)
  if not r.TakeFX_Show then return end
  local hwnd = r.TakeFX_GetFloatingWindow and r.TakeFX_GetFloatingWindow(take, fx_index) or nil
  r.TakeFX_Show(take, fx_index, hwnd and 2 or 3)
end

local function delete_take_fx(app, take, fx_index, fx_name)
  if not validate_take(take) or not r.TakeFX_Delete then return end
  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)
  r.TakeFX_Delete(take, fx_index)
  r.PreventUIRefresh(-1)
  r.Undo_EndBlock("Delete item FX", -1)
  app.status = "Deleted " .. get_fx_short_name(fx_name)
end

local function draw_take_fx_tile(app, ctx, settings, take, fx_index, item_width)
  local _, fx_name = r.TakeFX_GetFXName(take, fx_index, "")
  local enabled = take_fx_enabled(take, fx_index)
  local offline = take_fx_offline(take, fx_index)
  local short_name = get_fx_short_name(fx_name)
  r.ImGui_PushID(ctx, "ir_take_fx_" .. tostring(fx_index))
  local flags = r.ImGui_WindowFlags_NoScrollbar() | r.ImGui_WindowFlags_NoScrollWithMouse()
  local shot_h = settings.show_screenshots and not settings.tile_compact and (settings.screenshot_height or 90) or 0
  local row1_h = 18
  local toolbar_h = 16
  local tile_h = row1_h + toolbar_h + shot_h + 6
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), 0, 0)
  local tile_visible = r.ImGui_BeginChild(ctx, "##ir_take_fx_tile", item_width, tile_h, 0, flags)
  r.ImGui_PopStyleVar(ctx, 1)
  if tile_visible then
    local draw_list = r.ImGui_GetWindowDrawList(ctx)
    local bx, by = r.ImGui_GetCursorScreenPos(ctx)
    r.ImGui_DrawList_AddRectFilled(draw_list, bx, by, bx + item_width, by + tile_h, Theme.colors.frame_bg, 3)
    r.ImGui_DrawList_AddRect(draw_list, bx, by, bx + item_width, by + tile_h, enabled and Theme.colors.border or Theme.colors.danger, 3, 0, 1)

    local delete_x = bx + item_width - 10
    local delete_y = by + row1_h * 0.5
    r.ImGui_DrawList_AddCircleFilled(draw_list, delete_x, delete_y, 4, 0xCC3333FF)
    r.ImGui_SetCursorScreenPos(ctx, delete_x - 6, delete_y - 6)
    r.ImGui_InvisibleButton(ctx, "##ir_take_fx_delete", 12, 12)
    if r.ImGui_IsItemClicked(ctx, 0) then r.ImGui_OpenPopup(ctx, "##ir_take_delete_pop") end
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Delete item FX") end

    local led_x = delete_x - 14
    r.ImGui_DrawList_AddCircleFilled(draw_list, led_x, by + row1_h * 0.5, 4, enabled and 0x44CC44FF or 0xCC3333FF)
    r.ImGui_SetCursorScreenPos(ctx, led_x - 6, by + 2)
    if r.ImGui_InvisibleButton(ctx, "##ir_take_fx_led", 12, 12) then
      set_take_fx_enabled(take, fx_index, not enabled)
      app.status = (enabled and "Bypassed " or "Enabled ") .. short_name
    end
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, enabled and "Bypass item FX" or "Enable item FX") end

    local name_max_w = math.max(20, led_x - (bx + 6) - 4)
    r.ImGui_DrawList_PushClipRect(draw_list, bx + 6, by, bx + 6 + name_max_w, by + row1_h, true)
    r.ImGui_DrawList_AddText(draw_list, bx + 6, by + 2, enabled and Theme.colors.text or Theme.colors.text_dim, short_name)
    r.ImGui_DrawList_PopClipRect(draw_list)

    local button_y = by + row1_h + 2
    local tx = bx + 6
    if draw_small_button(ctx, draw_list, "##ir_take_fx_float", tx, button_y, 14, 12, "F", 0x33333388, 0xFFFFFFFF, "Open floating") then show_take_fx(take, fx_index) end
    tx = tx + 18
    if draw_small_button(ctx, draw_list, "##ir_take_fx_offline", tx, button_y, 14, 12, "O", offline and 0xAA3333FF or 0x33333388, 0xFFFFFFFF, offline and "Bring item FX online" or "Set item FX offline") then
      set_take_fx_offline(take, fx_index, not offline)
      app.status = (offline and "Brought online " or "Set offline ") .. short_name
    end
    if settings.show_screenshots and not settings.tile_compact then
      r.ImGui_SetCursorScreenPos(ctx, bx + 2, by + row1_h + toolbar_h + 4)
      draw_fx_screenshot(ctx, settings, fx_name, item_width - 4, shot_h, enabled and not offline)
      if r.ImGui_IsItemClicked(ctx, 0) then show_take_fx(take, fx_index) end
    end

    if r.ImGui_BeginPopup(ctx, "##ir_take_delete_pop") then
      r.ImGui_Text(ctx, "Delete this item FX?")
      r.ImGui_Separator(ctx)
      if r.ImGui_Button(ctx, "Delete##ir_take_delete_confirm") then
        delete_take_fx(app, take, fx_index, fx_name)
        r.ImGui_CloseCurrentPopup(ctx)
      end
      r.ImGui_SameLine(ctx)
      if r.ImGui_Button(ctx, "Cancel##ir_take_delete_cancel") then r.ImGui_CloseCurrentPopup(ctx) end
      r.ImGui_EndPopup(ctx)
    end

    r.ImGui_SetCursorScreenPos(ctx, bx, by)
    if r.ImGui_InvisibleButton(ctx, "##ir_take_fx_title_hit", math.max(1, name_max_w + 8), row1_h) then show_take_fx(take, fx_index) end
    if r.ImGui_BeginPopupContextItem(ctx, "##ir_take_fx_context") then
      if r.ImGui_MenuItem(ctx, enabled and "Bypass" or "Enable") then set_take_fx_enabled(take, fx_index, not enabled) end
      if r.ImGui_MenuItem(ctx, "Open floating", nil, false, r.TakeFX_Show ~= nil) then show_take_fx(take, fx_index) end
      if r.ImGui_MenuItem(ctx, offline and "Bring online" or "Set offline", nil, false, r.TakeFX_SetOffline ~= nil) then set_take_fx_offline(take, fx_index, not offline) end
      r.ImGui_Separator(ctx)
      if r.ImGui_MenuItem(ctx, "Remove", nil, false, r.TakeFX_Delete ~= nil) then delete_take_fx(app, take, fx_index, fx_name) end
      r.ImGui_EndPopup(ctx)
    end
    r.ImGui_EndChild(ctx)
  end
  r.ImGui_PopID(ctx)
end

local function draw_section_label(ctx, label, detail, count)
  local draw_list = r.ImGui_GetWindowDrawList(ctx)
  local x, y = r.ImGui_GetCursorScreenPos(ctx)
  local width = math.max(120, get_available_width(ctx))
  local height = detail and detail ~= "" and 32 or 24
  r.ImGui_Dummy(ctx, width, height)
  r.ImGui_DrawList_AddRectFilled(draw_list, x, y, x + width, y + height, Theme.colors.frame_bg, 4)
  r.ImGui_DrawList_AddRectFilled(draw_list, x, y, x + 3, y + height, Theme.colors.accent, 4)
  r.ImGui_DrawList_AddText(draw_list, x + 10, y + 5, Theme.colors.text, label)
  if count then
    local count_text = tostring(count) .. " FX"
    local count_w = r.ImGui_CalcTextSize(ctx, count_text)
    r.ImGui_DrawList_AddText(draw_list, x + width - count_w - 10, y + 5, Theme.colors.text_dim, count_text)
  end
  if detail and detail ~= "" then r.ImGui_DrawList_AddTextEx(draw_list, nil, 10, x + 10, y + 20, Theme.colors.text_dim, detail) end
end

local function info_line_text(app, track, fx_count, input_fx_count, take_fx_count, item_on_track, take)
  local status = app.status and app.status ~= "" and app.status or "Ready"
  local detail
  if not validate_track(track) then
    detail = "No track selected"
  elseif item_on_track == false then
    detail = string.format("Track FX: %d  |  Input FX: %d  |  Selected item is on another track", fx_count or 0, input_fx_count or 0)
  elseif validate_take(take) then
    detail = string.format("Track FX: %d  |  Input FX: %d  |  Item FX: %d", fx_count or 0, input_fx_count or 0, take_fx_count or 0)
  else
    detail = string.format("Track FX: %d  |  Input FX: %d", fx_count or 0, input_fx_count or 0)
  end
  return detail .. " | " .. status
end

function M.init(app)
  ensure_settings(app)
  build_screenshot_index(false)
end

function M.draw(app)
  local ctx = app.ctx
  local settings = ensure_settings(app)
  update_external_drag(ctx)
  run_pending_param_action(app)
  local track = get_target_track(settings)
  draw_header(app, ctx, settings, track)
  r.ImGui_Separator(ctx)
  if not validate_track(track) then
    r.ImGui_TextColored(ctx, Theme.colors.warning, "Select a track to show its FX chain.")
    UI.draw_info_line(ctx, info_line_text(app, track, 0, 0, 0, nil, nil))
    return
  end
  if settings.body_collapsed then
    if r.ImGui_Button(ctx, "Expand rack##ir_expand") then
      settings.body_collapsed = false
      if app.save_settings then app.save_settings() end
    end
    UI.draw_info_line(ctx, info_line_text(app, track, r.TrackFX_GetCount(track), 0, 0, nil, nil))
    return
  end
  local fx_count = r.TrackFX_GetCount(track)
  local show_track_fx = settings.show_track_fx ~= false
  local input_fx_count = settings.show_input_fx and r.TrackFX_GetRecCount and r.TrackFX_GetRecCount(track) or 0
  local selected_item, take, item_on_track = get_selected_take(track)
  local take_fx_count = settings.show_selected_item_fx and item_on_track and validate_take(take) and r.TakeFX_GetCount and r.TakeFX_GetCount(take) or 0
  local info_h = UI.info_line_height(ctx)
  local flags = 0
  if r.ImGui_BeginChild(ctx, "##instrument_rack_scroll", 0, -info_h, 0, flags) then
    local width = get_centered_item_width(ctx)
    if show_track_fx and fx_count == 0 then
      r.ImGui_TextColored(ctx, Theme.colors.text_dim, "No FX on this track.")
    end
    if show_track_fx then
      for index = 0, fx_count - 1 do
        center_next_item(ctx, width)
        draw_fx_tile(app, ctx, settings, track, index, width, true)
      end
      center_next_item(ctx, width)
      draw_add_zone(app, ctx, settings, track, width, -1)
    end
    if settings.show_input_fx then
      draw_section_label(ctx, "Track Input FX", get_track_label(track), input_fx_count)
      if input_fx_count == 0 then r.ImGui_TextColored(ctx, Theme.colors.text_dim, "No input FX on this track.") end
      for index = 0, input_fx_count - 1 do
        center_next_item(ctx, width)
        draw_fx_tile(app, ctx, settings, track, REC_FX_OFFSET + index, width, false)
      end
    end
    if settings.show_selected_item_fx then
      draw_section_label(ctx, "Selected Track Item FX", get_track_label(track), take_fx_count)
      if selected_item and item_on_track == false then
        r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Selected item is on another track.")
      elseif not validate_take(take) then
        r.ImGui_TextColored(ctx, Theme.colors.text_dim, "No selected item with active take on this track.")
      elseif take_fx_count == 0 then
        r.ImGui_TextColored(ctx, Theme.colors.text_dim, "No item FX on selected item: " .. get_take_label(take))
      else
        r.ImGui_TextColored(ctx, Theme.colors.text_dim, get_take_label(take))
        for index = 0, take_fx_count - 1 do
          center_next_item(ctx, width)
          draw_take_fx_tile(app, ctx, settings, take, index, width)
        end
      end
    end
    r.ImGui_EndChild(ctx)
  end
  UI.draw_info_line(ctx, info_line_text(app, track, fx_count, input_fx_count, take_fx_count, item_on_track, take))
end

return M