local r = reaper
local Dialogs = require("core.dialogs")
local Engine = require("core.engine")
local Exporter = require("core.exporter")
local Theme = require("core.theme")
local Naming = require("core.naming")
local Store = require("core.browser_store")

local M = {}

local GRID_COLS = 4
local GRID_ROWS = 4
local GRID_SLOTS = GRID_COLS * GRID_ROWS
local DEFAULT_BASE_NOTE = 36
local COVER_EXT_KEY = "P_EXT:TK_KIT_MAKER_COVER"
local MIDI_INPUT_EXT_KEY = "P_EXT:TK_KIT_MAKER_MIDI_INPUT"

local function save(app)
  if app.browser then
    Store.save(app.browser)
  end
end

local function file_leaf(path)
  return tostring(path or ""):match("([^/\\]+)$") or tostring(path or "")
end

local function file_stem(path)
  return file_leaf(path):gsub("%.[%w]+$", "")
end

local function normalized_path(path)
  return Exporter.normalize(path or "")
end

local function parent_folder_name(path)
  local normalized = normalized_path(path)
  local parent = normalized:match("^(.*)/[^/]+$") or ""
  return parent:match("([^/]+)$") or ""
end

local function file_ext(path)
  local ext = tostring(path or ""):match("(%.[%w]+)$")
  return ext or ""
end

local AUDIO_EXT = {
  wav = true,
  wave = true,
  aif = true,
  aiff = true,
  flac = true,
  mp3 = true,
  ogg = true,
  opus = true,
  m4a = true,
  wv = true,
}

local DROP_PAYLOAD_TYPES = {
  "TK_WORKBENCH_MEDIA_FILE",
  "REAPER_MEDIAFOLDER",
  "text/uri-list",
  "UTF8_STRING",
  "TEXT",
  "FILE_PATH",
  "FILES",
}

local function decode_file_uri(uri)
  local s = tostring(uri or "")
  if s == "" then return "" end
  s = s:gsub("^<", ""):gsub(">$", "")
  s = s:gsub("^file://", "")
  s = s:gsub("^localhost/", "")
  s = s:gsub("^/([A-Za-z]:)", "%1")
  s = s:gsub("%%(%x%x)", function(hex)
    return string.char(tonumber(hex, 16))
  end)
  return s
end

local function is_audio_file_path(path)
  local p = tostring(path or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if p == "" then return false end
  p = p:gsub('^"', ""):gsub('"$', "")
  local ext = p:match("%.([%w]+)$")
  ext = ext and ext:lower() or ""
  if ext == "" then return false end
  return AUDIO_EXT[ext] == true
end

local function extract_sample_path_from_payload(payload)
  local text = tostring(payload or "")
  if text == "" then return nil end
  text = text:gsub("%z", "\n")
  text = text:gsub("\r", "")
  for line in text:gmatch("[^\n]+") do
    local candidate = tostring(line or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if candidate ~= "" then
      candidate = candidate:gsub('^"', ""):gsub('"$', "")
      if candidate:lower():match("^file://") or candidate:match("^<file://") then
        candidate = decode_file_uri(candidate)
      end
      if is_audio_file_path(candidate) then
        return candidate
      end
    end
  end
  if is_audio_file_path(text) then
    return text
  end
  return nil
end

local function accept_dropped_sample_path(ctx)
  if r.ImGui_AcceptDragDropPayloadFiles and r.ImGui_GetDragDropPayloadFile then
    local ok_files, count = r.ImGui_AcceptDragDropPayloadFiles(ctx)
    if ok_files and tonumber(count) and tonumber(count) > 0 then
      for i = 0, tonumber(count) - 1 do
        local ok_file, file_path = r.ImGui_GetDragDropPayloadFile(ctx, i)
        if ok_file then
          local sample_path = extract_sample_path_from_payload(file_path)
          if sample_path then return sample_path end
        end
      end
    end
  end

  if not r.ImGui_AcceptDragDropPayload then return nil end

  for _, payload_type in ipairs(DROP_PAYLOAD_TYPES) do
    local ok_payload, payload = r.ImGui_AcceptDragDropPayload(ctx, payload_type)
    if ok_payload then
      local sample_path = extract_sample_path_from_payload(payload)
      if sample_path then return sample_path end
    end
  end

  if r.ImGui_GetDragDropPayload then
    local ok_type, payload_type = r.ImGui_GetDragDropPayload(ctx)
    if ok_type and payload_type and payload_type ~= "" then
      local ok_payload, payload = r.ImGui_AcceptDragDropPayload(ctx, payload_type)
      if ok_payload then
        local sample_path = extract_sample_path_from_payload(payload)
        if sample_path then return sample_path end
      end
    end
  end

  return nil
end

local function safe_filename(text)
  local s = tostring(text or ""):gsub("[<>:\"/\\|%?%*]", "_"):gsub("%s+$", "")
  s = s:gsub("^%s+", "")
  return s ~= "" and s or "Untitled"
end

local function global_mouse_pos(ctx)
  if r.GetMousePosition and r.ImGui_PointConvertNative then
    local sx, sy = r.GetMousePosition()
    local ok, mx, my = pcall(r.ImGui_PointConvertNative, ctx, sx, sy)
    if ok and mx and my then
      return mx, my
    end
  end
  return r.ImGui_GetMousePos(ctx)
end

local function point_in_rect(mx, my, x1, y1, x2, y2)
  return mx >= x1 and mx <= x2 and my >= y1 and my <= y2
end

local function now_seconds()
  return r.time_precise and r.time_precise() or os.clock()
end

local function flash_pads_from_recent_midi(manager, grid_base_note)
  if not manager or not r.MIDI_GetRecentInputEvent then return end
  if manager.midi_last_retval == nil then
    manager.midi_last_retval = r.MIDI_GetRecentInputEvent(0) or 0
    return
  end
  manager.pad_click_flash = manager.pad_click_flash or {}
  local now = now_seconds()
  local first_retval = nil
  for idx = 0, 127 do
    local retval, msg = r.MIDI_GetRecentInputEvent(idx)
    if idx == 0 then first_retval = retval end
    if retval == 0 or retval == manager.midi_last_retval then break end
    if msg and #msg >= 3 then
      local status = string.byte(msg, 1) or 0
      local data1 = string.byte(msg, 2) or 0
      local data2 = string.byte(msg, 3) or 0
      local msg_type = status & 0xF0
      if msg_type == 0x90 and data2 > 0 then
        local slot = (math.floor(data1 + 0.5) - math.floor(grid_base_note + 0.5)) + 1
        if slot >= 1 and slot <= GRID_SLOTS then
          manager.pad_click_flash[slot] = math.max(manager.pad_click_flash[slot] or 0, now + 0.16)
        end
      end
    end
  end
  if first_retval and first_retval ~= 0 then
    manager.midi_last_retval = first_retval
  end
end

local stop_preview
local play_preview

local function play_track_audition(current, manager, note)
  if not current or not current.track or not r.StuffMIDIMessage then return false end
  r.SetMediaTrackInfo_Value(current.track, "I_RECARM", 1)
  r.SetMediaTrackInfo_Value(current.track, "I_RECMON", 1)
  r.SetMediaTrackInfo_Value(current.track, "I_RECMODE", 0)
  if manager and manager.track_audition_note then
    pcall(r.StuffMIDIMessage, 0, 0x80, manager.track_audition_note, 0)
    manager.track_audition_note = nil
    manager.track_audition_track = nil
  end
  local midi_note = math.max(0, math.min(127, math.floor(tonumber(note) or 0)))
  local ok = pcall(r.StuffMIDIMessage, 0, 0x90, midi_note, 100)
  if ok then
    manager.preview_path = current.sample_path
    manager.track_audition_note = midi_note
    manager.track_audition_track = current.track
    manager.track_audition_slot = current.slot or current.grid_slot
    return true
  end
  return false
end

local function stop_track_audition(manager)
  if not manager or not r.StuffMIDIMessage then return false end
  local note = manager.track_audition_note
  local sent = false
  if note then
    local ok1 = pcall(r.StuffMIDIMessage, 0, 0x80, note, 0)
    local ok2 = pcall(r.StuffMIDIMessage, 0, 0x90, note, 0)
    sent = ok1 or ok2 or sent
  end
  for ch = 0, 15 do
    local status = 0xB0 + ch
    local ok_all_notes = pcall(r.StuffMIDIMessage, 0, status, 123, 0)
    local ok_all_sound = pcall(r.StuffMIDIMessage, 0, status, 120, 0)
    sent = ok_all_notes or ok_all_sound or sent
  end
  manager.track_audition_note = nil
  manager.track_audition_track = nil
  manager.track_audition_slot = nil
  manager.preview_path = nil
  return sent
end

local function audition_selected_sample(app, current)
  if not current or not current.sample_path or current.sample_path == "" then return false end

  local manager = app.rs5k_manager
  local mode = app.browser and app.browser.manager_audition_mode or "track"
  local slot = current.slot or current.grid_slot
  local note = current.note or (DEFAULT_BASE_NOTE + ((current.grid_slot or 1) - 1))

  if mode == "track" then
    stop_preview(manager)
    if play_track_audition(current, manager, note) then
      return true
    end
  end

  stop_track_audition(manager)
  return play_preview(manager, current.sample_path, slot)
end

local function open_row_rs5k(row)
  if not row or not row.track or not row.has_rs5k or not row.fx or row.fx < 0 then return false end
  if r.TrackFX_Show then
    pcall(r.TrackFX_Show, row.track, row.fx, 3)
  end
  if r.TrackFX_SetOpen then
    pcall(r.TrackFX_SetOpen, row.track, row.fx, true)
  end
  return true
end

local function pad_truncate(text, max_chars)
  local s = tostring(text or "")
  local limit = math.max(4, math.floor(tonumber(max_chars) or 12))
  if #s <= limit then return s end
  return s:sub(1, limit - 3) .. "..."
end

local function draw_pad_cell(ctx, manager, slot, row, grid_base_note, pad_w, pad_h, is_selected, rhythm_active)
  local dl = r.ImGui_GetWindowDrawList(ctx)
  local button_id = "##kit_manager_pad_" .. tostring(slot)
  local button_clicked = r.ImGui_InvisibleButton(ctx, button_id, pad_w, pad_h)
  local hovered = r.ImGui_IsItemHovered(ctx)
  local clicked = false
  if r.ImGui_IsItemActivated then
    clicked = r.ImGui_IsItemActivated(ctx)
  else
    clicked = button_clicked
  end
  local released = r.ImGui_IsItemDeactivated and r.ImGui_IsItemDeactivated(ctx) or false
  local shift_down = false
  if r.ImGui_IsKeyDown then
    if r.ImGui_Key_LeftShift then
      shift_down = shift_down or r.ImGui_IsKeyDown(ctx, r.ImGui_Key_LeftShift())
    end
    if r.ImGui_Key_RightShift then
      shift_down = shift_down or r.ImGui_IsKeyDown(ctx, r.ImGui_Key_RightShift())
    end
  end
  local open_modifier_clicked = clicked and shift_down
  local active = r.ImGui_IsItemActive(ctx)
  local min_x, min_y = r.ImGui_GetItemRectMin(ctx)
  local max_x, max_y = r.ImGui_GetItemRectMax(ctx)
  local click_flash_until = manager and manager.pad_click_flash and manager.pad_click_flash[slot] or nil
  local flash_active = click_flash_until and click_flash_until > now_seconds()

  if clicked and manager then
    manager.pad_click_flash = manager.pad_click_flash or {}
    manager.pad_click_flash[slot] = now_seconds() + 0.16
    flash_active = true
  end

  local fill
  local border
  if is_selected then
    fill = Theme.colors.accent_soft
    border = Theme.colors.accent
  elseif row and row.has_rs5k then
    fill = Theme.colors.frame_bg
    border = Theme.colors.border
  else
    fill = 0x20242BFF
    border = 0x2B3139FF
  end

  if active then
    fill = Theme.colors.accent_soft
    border = Theme.colors.accent_hover
  elseif flash_active then
    fill = Theme.colors.accent
    border = Theme.colors.accent_hover
  elseif rhythm_active then
    fill = Theme.colors.accent_soft
    border = Theme.colors.accent
  elseif hovered then
    fill = Theme.colors.frame_hover
  end

  r.ImGui_DrawList_AddRectFilled(dl, min_x, min_y, max_x, max_y, fill, 4)
  r.ImGui_DrawList_AddRect(dl, min_x, min_y, max_x, max_y, border, 4, 0, (flash_active or rhythm_active) and 2 or 1)

  if active or flash_active or rhythm_active then
    local inset = active and 3 or 4
    r.ImGui_DrawList_AddRect(dl, min_x + inset, min_y + inset, max_x - inset, max_y - inset, Theme.colors.text, 4, 0, 1)
  end

  local pushed = Theme.push_small(ctx)
  local small_h = select(2, r.ImGui_CalcTextSize(ctx, "Ag")) or 10
  local inner_pad = 5
  local top_y = min_y + 3
  local bottom_line_y = max_y - small_h - 7
  local name_y = bottom_line_y + 3

  local slot_text = string.format("%03d", slot)
  local note_text = Naming.note_name(grid_base_note + slot - 1)
  local name_text = row and row.track_name or "Empty"
  local max_name_chars = math.max(6, math.floor((pad_w - (inner_pad * 2)) / 5.5))
  name_text = pad_truncate(name_text, max_name_chars)

  local slot_w = select(1, r.ImGui_CalcTextSize(ctx, slot_text)) or 0
  local note_w = select(1, r.ImGui_CalcTextSize(ctx, note_text)) or 0
  local name_w = select(1, r.ImGui_CalcTextSize(ctx, name_text)) or 0

  r.ImGui_DrawList_AddText(dl, min_x + inner_pad, top_y, Theme.colors.text, slot_text)
  r.ImGui_DrawList_AddText(dl, max_x - inner_pad - note_w, top_y, Theme.colors.text_dim, note_text)
  r.ImGui_DrawList_AddLine(dl, min_x + inner_pad, bottom_line_y, max_x - inner_pad, bottom_line_y, Theme.colors.border, 1)
  r.ImGui_DrawList_AddText(dl, min_x + inner_pad, name_y, Theme.colors.text, name_text)
  Theme.pop_font(ctx, pushed)

  if hovered then
    local tip = string.format("Slot %03d\n%s", slot, note_text)
    if row then
      tip = tip .. "\n" .. row.track_name
      if row.sample_path and row.sample_path ~= "" then
        tip = tip .. "\n" .. row.sample_path
      elseif not row.has_rs5k then
        tip = tip .. "\nNo RS5K loaded on this track."
      end
    else
      tip = tip .. "\nEmpty"
    end
    tip = tip .. "\nShift+Click: Open RS5K"
    r.ImGui_SetTooltip(ctx, tip)
  end

  return clicked, open_modifier_clicked, released
end

local function selected_collection_cover(app)
  local state = app.browser
  if not state then return nil end
  local collections = state.browser_mode == "kits" and state.kit_collections or state.collections
  local selected_id = state.browser_mode == "kits" and state.kit_selected_id or state.sample_selected_id
  for _, col in ipairs(collections or {}) do
    if col.id == selected_id then
      return col.cover_path
    end
  end
  return nil
end

local function selected_kit_collection_cover(app)
  local state = app.browser
  if not state then return nil end
  for _, col in ipairs(state.kit_collections or {}) do
    if col.id == state.kit_selected_id then
      return col.cover_path
    end
  end
  return nil
end

local function selected_collection_name(app)
  local state = app.browser
  if not state then return nil end
  local collections = state.browser_mode == "kits" and state.kit_collections or state.collections
  local selected_id = state.browser_mode == "kits" and state.kit_selected_id or state.sample_selected_id
  for _, col in ipairs(collections or {}) do
    if col.id == selected_id then
      return col.name or file_leaf(col.path)
    end
  end
  return nil
end

local function track_cover_path(track)
  if not track then return nil end
  local ok, value = r.GetSetMediaTrackInfo_String(track, COVER_EXT_KEY, "", false)
  if not ok then return nil end
  value = normalized_path(value)
  return value ~= "" and value or nil
end

local function set_track_cover_path(track, path)
  if not track then return false end
  local value = normalized_path(path)
  r.GetSetMediaTrackInfo_String(track, COVER_EXT_KEY, value, true)
  return true
end

local function rows_have_samples(rows)
  for _, row in ipairs(rows or {}) do
    if row.sample_path and row.sample_path ~= "" then
      return true
    end
  end
  return false
end

local function track_guid(track)
  if not track or not r.GetTrackGUID then return nil end
  return r.GetTrackGUID(track)
end

local function resolve_cover_path(app, parent, rows)
  local cover_path = track_cover_path(parent)
  if cover_path and cover_path ~= "" then
    return cover_path
  end
  if rows_have_samples(rows) then
    local manager = app and app.rs5k_manager
    local guid = track_guid(parent)
    if manager and guid then
      manager.cover_fallback_by_track = manager.cover_fallback_by_track or {}
      local remembered = manager.cover_fallback_by_track[guid]
      if remembered and remembered ~= "" then
        return remembered
      end
      local fallback = selected_kit_collection_cover(app)
      if fallback and fallback ~= "" then
        manager.cover_fallback_by_track[guid] = fallback
        return fallback
      end
      return nil
    end
    return selected_kit_collection_cover(app) or selected_collection_cover(app)
  end
  return nil
end

local function choose_cover_path(app, parent, rows)
  if not parent then return nil end
  local current = resolve_cover_path(app, parent, rows)
  local start_folder = current and parent_folder_name(current) or (r.GetResourcePath() .. "/Data")
  local path = Dialogs.browse_file("Select cover image", start_folder, "")
  if not path or path == "" then return nil end
  set_track_cover_path(parent, path)
  return path
end

local function track_midi_input_value(track)
  if not track then return 6112 end
  local ok, value = r.GetSetMediaTrackInfo_String(track, MIDI_INPUT_EXT_KEY, "", false)
  if ok and value and value ~= "" then
    local stored = tonumber(value)
    if stored then return stored end
  end
  local rec_input = math.floor(r.GetMediaTrackInfo_Value(track, "I_RECINPUT") or -1)
  if rec_input >= 4096 then
    return rec_input
  end
  return 6112
end

local function set_track_midi_input_value(track, value)
  if not track then return false end
  local stored = math.floor(tonumber(value) or 6112)
  r.GetSetMediaTrackInfo_String(track, MIDI_INPUT_EXT_KEY, tostring(stored), true)
  r.SetMediaTrackInfo_Value(track, "I_RECINPUT", stored)
  return true
end

local function midi_input_options()
  local options = {
    { value = 6112, label = "All MIDI" },
  }
  if r.GetNumMIDIInputs and r.GetMIDIInputName then
    local count = r.GetNumMIDIInputs()
    for index = 0, count - 1 do
      local ok, name = r.GetMIDIInputName(index, "")
      if ok and name and name ~= "" then
        options[#options + 1] = {
          value = 4096 + (index * 32),
          label = name,
        }
      end
    end
  end
  return options
end

local function midi_input_label(value, options)
  local current = math.floor(tonumber(value) or 6112)
  for _, opt in ipairs(options or {}) do
    if opt.value == current then
      return opt.label
    end
  end
  if current == 6112 then
    return "All MIDI"
  end
  if current >= 4096 then
    local device_index = math.floor((current - 4096) / 32)
    return string.format("MIDI input %d", device_index + 1)
  end
  return "All MIDI"
end

local function rack_all_armed(parent, rows)
  if not parent then return false end
  if math.floor(r.GetMediaTrackInfo_Value(parent, "I_RECARM") or 0) ~= 1 then
    return false
  end
  for _, row in ipairs(rows or {}) do
    if math.floor(r.GetMediaTrackInfo_Value(row.track, "I_RECARM") or 0) ~= 1 then
      return false
    end
  end
  return true
end

local function apply_rack_midi_input(parent, rows, value)
  if not parent then return false end
  local stored = math.floor(tonumber(value) or 6112)
  set_track_midi_input_value(parent, stored)
  for _, row in ipairs(rows or {}) do
    if row.track then
      set_track_midi_input_value(row.track, stored)
    end
  end
  return true
end

local function set_rack_arm_state(parent, rows, armed, midi_value)
  if not parent then return false end
  local arm_value = armed and 1 or 0
  local monitor_value = armed and 2 or 0
  local input_value = math.floor(tonumber(midi_value) or track_midi_input_value(parent))
  if armed then
    apply_rack_midi_input(parent, rows, input_value)
  end
  r.SetMediaTrackInfo_Value(parent, "I_RECARM", arm_value)
  r.SetMediaTrackInfo_Value(parent, "I_RECMON", monitor_value)
  r.SetMediaTrackInfo_Value(parent, "I_RECMODE", 0)
  for _, row in ipairs(rows or {}) do
    if row.track then
      r.SetMediaTrackInfo_Value(row.track, "I_RECARM", arm_value)
      r.SetMediaTrackInfo_Value(row.track, "I_RECMON", monitor_value)
      r.SetMediaTrackInfo_Value(row.track, "I_RECMODE", 0)
      if armed then
        set_track_midi_input_value(row.track, input_value)
      end
    end
  end
  if armed then
    set_track_midi_input_value(parent, input_value)
  end
  return true
end

local function cover_texture(state, path)
  if not path or path == "" then return nil end
  state.cover_cache = state.cover_cache or {}
  local cached = state.cover_cache[path]
  if cached and cached ~= false and r.ImGui_ValidatePtr then
    local ok, valid = pcall(r.ImGui_ValidatePtr, cached, "ImGui_Image*")
    if not ok or not valid then
      state.cover_cache[path] = nil
      cached = nil
    end
  end
  if not cached then
    local img = nil
    if r.ImGui_CreateImage then
      local ok, tex = pcall(r.ImGui_CreateImage, path)
      if ok then img = tex end
    end
    state.cover_cache[path] = img or false
    cached = state.cover_cache[path]
  end
  if cached == false then return nil end
  return cached
end

local function image_size(ctx, tex, fallback_w, fallback_h)
  if r.ImGui_Image_GetSize then
    local ok, w, h = pcall(r.ImGui_Image_GetSize, tex)
    if ok then
      w = tonumber(w) or 0
      h = tonumber(h) or 0
      if w > 0 and h > 0 then
        return w, h
      end
    end
  end
  return fallback_w or 1, fallback_h or 1
end

local function close_button(ctx, size)
  local dl = r.ImGui_GetWindowDrawList(ctx)
  local x, y = r.ImGui_GetCursorScreenPos(ctx)
  local clicked = r.ImGui_InvisibleButton(ctx, "##kit_manager_close", size, size)
  local hovered = r.ImGui_IsItemHovered(ctx)
  local cx, cy = x + size * 0.5, y + size * 0.5
  local rad = size * 0.5
  local col = hovered and Theme.colors.danger or 0xC85A60FF
  r.ImGui_DrawList_AddCircleFilled(dl, cx, cy, rad, col)
  if hovered and r.ImGui_SetTooltip then r.ImGui_SetTooltip(ctx, "Close") end
  return clicked
end

local function track_name(track)
  local _, name = r.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
  if name and name ~= "" then return name end
  local idx = r.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER") or 0
  return "Track " .. tostring(math.floor(idx + 0.5))
end

local function sync_rename_state(app, parent)
  local state = app.rs5k_manager
  if not state then return end
  local guid = parent and r.GetTrackGUID and r.GetTrackGUID(parent) or nil
  if state.rename_track_guid ~= guid then
    state.rename_track_guid = guid
    state.rename_buffer = parent and track_name(parent) or ""
  end
end

local function rename_kit_track(app, parent)
  local state = app.rs5k_manager
  if not state or not parent then return false end
  local new_name = tostring(state.rename_buffer or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if new_name == "" then return false end
  r.GetSetMediaTrackInfo_String(parent, "P_NAME", new_name, true)
  return true
end

local function suggest_manager_kit_name(app, rows)
  local kitdef = { slots = {} }
  local pools = {}
  local alias = selected_collection_name(app) or "Kit"
  local folders = {}
  local seen_folders = {}

  for _, row in ipairs(rows or {}) do
    if row.sample_path and row.sample_path ~= "" then
      local folder = parent_folder_name(row.sample_path)
      if folder ~= "" and not seen_folders[folder:lower()] then
        seen_folders[folder:lower()] = true
        folders[#folders + 1] = folder
      end
    end
  end

  pools.main = {
    alias = alias,
    folders = folders,
  }

  for _, row in ipairs(rows or {}) do
    kitdef.slots[#kitdef.slots + 1] = {
      type_label = "Pad",
      keyword = "",
    }
  end

  return Engine.suggest_kit_name(kitdef, pools, app.script_path, app.rs5k_manager.rename_seed)
end

local function open_rename_popup(app, parent)
  sync_rename_state(app, parent)
  app.rs5k_manager.rename_popup_open = true
end

local function draw_rename_popup(app, parent, rows)
  local ctx = app.ctx
  local state = app.rs5k_manager
  if state.rename_popup_open then
    r.ImGui_OpenPopup(ctx, "Rename kit##kit_manager_rename_popup")
    state.rename_popup_open = false
  end

  local visible = r.ImGui_BeginPopupModal(ctx, "Rename kit##kit_manager_rename_popup", true, r.ImGui_WindowFlags_AlwaysAutoResize())
  if not visible then return end

  r.ImGui_SetNextItemWidth(ctx, 280)
  local rename_changed, rename_value = r.ImGui_InputText(ctx, "Kit name##kit_manager_popup_name", state.rename_buffer or "")
  if rename_changed then
    state.rename_buffer = rename_value
  end

  r.ImGui_SetNextItemWidth(ctx, 180)
  local seed_changed, seed_value = r.ImGui_InputTextWithHint(ctx, "Start word##kit_manager_popup_seed", "optional", state.rename_seed or "")
  if seed_changed then
    state.rename_seed = tostring(seed_value or ""):gsub("^%s+", ""):gsub("%s+$", "")
  end

  r.ImGui_SameLine(ctx)
  if Theme.ghost_button(ctx, "Generate##kit_manager_popup_generate", 86, 0) then
    state.rename_buffer = suggest_manager_kit_name(app, rows)
  end

  if Theme.ghost_button(ctx, "Cancel##kit_manager_popup_cancel", 90, 0) then
    sync_rename_state(app, parent)
    r.ImGui_CloseCurrentPopup(ctx)
  end
  r.ImGui_SameLine(ctx)
  if Theme.primary_button(ctx, "Apply##kit_manager_popup_apply", 90, 0) then
    rename_kit_track(app, parent)
    r.ImGui_CloseCurrentPopup(ctx)
  end

  r.ImGui_EndPopup(ctx)
end

local function save_current_kit(app, parent, rows)
  local state = app.rs5k_manager
  if not state or not parent then return false end
  local destination = state.save_dir
  if not destination or destination == "" then
    destination = Dialogs.browse_folder("Save kit to folder", r.GetResourcePath() .. "/TrackTemplates")
    if not destination or destination == "" then return false end
    state.save_dir = destination
    if app.browser then
      app.browser.manager_save_dir = destination
      save(app)
    end
  end

  local kit_name = tostring(state.rename_buffer or track_name(parent) or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if kit_name == "" then kit_name = "Untitled Kit" end
  local dest_dir, final_name = Exporter.make_folder(destination, safe_filename(kit_name))
  local saved = 0
  local results = {}

  for _, row in ipairs(rows or {}) do
    if row.sample_path and row.sample_path ~= "" then
      local base = row.track_name ~= "" and row.track_name or file_stem(row.sample_path)
      local prefix = row.grid_slot and string.format("%03d_", row.grid_slot) or ""
      local filename = prefix .. safe_filename(base) .. file_ext(row.sample_path)
      local out_name = Exporter.copy(row.sample_path, dest_dir, filename)
      if out_name then
        saved = saved + 1
        results[#results + 1] = {
          slot = {
            midi_note = row.note or (DEFAULT_BASE_NOTE + ((row.grid_slot or 1) - 1)),
            pad = row.grid_slot or row.slot or saved,
            number = row.grid_slot or row.slot or saved,
          },
          sample = row.sample_path,
          out_name = out_name,
        }
      end
    end
  end

  local cover_path = resolve_cover_path(app, parent, rows)
  if cover_path and cover_path ~= "" then
    Exporter.copy(cover_path, dest_dir, "Cover" .. file_ext(cover_path))
  end

  if #results > 0 then
    Exporter.write_midilog(dest_dir, final_name, results)
    Exporter.write_sourcelog(dest_dir, final_name, results)
  end

  if saved > 0 then
    if r.CF_ShellExecute then
      r.CF_ShellExecute(dest_dir)
    end
    return true
  end
  return false
end

stop_preview = function(state)
  if state.preview and r.CF_Preview_Stop then
    pcall(r.CF_Preview_Stop, state.preview)
  end
  if state.preview_source and r.PCM_Source_Destroy then
    pcall(r.PCM_Source_Destroy, state.preview_source)
  end
  state.preview = nil
  state.preview_source = nil
  state.preview_path = nil
  state.preview_slot = nil
end

play_preview = function(state, path, slot)
  if not path or path == "" then return false end
  if not r.CF_CreatePreview or not r.CF_Preview_Play then return false end

  stop_preview(state)

  local source = r.PCM_Source_CreateFromFile(path)
  if not source then return false end
  local preview = r.CF_CreatePreview(source)
  if not preview then
    if r.PCM_Source_Destroy then r.PCM_Source_Destroy(source) end
    return false
  end
  if r.CF_Preview_SetValue then
    r.CF_Preview_SetValue(preview, "D_VOLUME", math.max(0, math.min(2, tonumber(state.preview_volume) or 1.0)))
    r.CF_Preview_SetValue(preview, "B_LOOP", 0)
    r.CF_Preview_SetValue(preview, "D_POSITION", 0)
  end
  r.CF_Preview_Play(preview)
  state.preview = preview
  state.preview_source = source
  state.preview_path = path
  state.preview_slot = slot
  return true
end

local function load_sample_into_rs5k(track, sample_path, midi_note)
  local fx = -1
  local count = r.TrackFX_GetCount(track)
  for i = 0, count - 1 do
    local ok_name, name = r.TrackFX_GetFXName(track, i, "")
    local lower_name = ok_name and name and name:lower() or ""
    if lower_name:find("reasamplomatic", 1, true) or lower_name:find("rs5k", 1, true) then
      fx = i
      break
    end
    if r.TrackFX_GetNamedConfigParm then
      local ok_file = r.TrackFX_GetNamedConfigParm(track, i, "FILE0")
      if ok_file then
        fx = i
        break
      end
    end
  end
  if fx < 0 then
    fx = r.TrackFX_AddByName(track, "ReaSamplOmatic5000 (Cockos)", false, -1)
  end
  if fx < 0 then return false end
  local ok = r.TrackFX_SetNamedConfigParm(track, fx, "FILE0", sample_path)
  if ok then
    r.TrackFX_SetNamedConfigParm(track, fx, "DONE", "")
    if midi_note ~= nil then
      local note = math.max(0, math.min(127, math.floor(tonumber(midi_note) or 0)))
      local normalized = note / 127
      r.TrackFX_SetParamNormalized(track, fx, 3, normalized)
      r.TrackFX_SetParamNormalized(track, fx, 4, normalized)
    end
  end
  return ok == true
end

local function create_empty_rs5k(track, midi_note)
  local fx = r.TrackFX_AddByName(track, "ReaSamplOmatic5000 (Cockos)", false, -1)
  if fx < 0 then return false end
  if midi_note ~= nil then
    local note = math.max(0, math.min(127, math.floor(tonumber(midi_note) or 0)))
    local normalized = note / 127
    r.TrackFX_SetParamNormalized(track, fx, 3, normalized)
    r.TrackFX_SetParamNormalized(track, fx, 4, normalized)
  end
  return true
end

local function create_empty_rack(app)
  local state = app.browser
  if not state then return false end

  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)

  local insert_idx = r.CountTracks(0)
  r.InsertTrackAtIndex(insert_idx, true)
  local parent = r.GetTrack(0, insert_idx)
  if not parent then
    r.PreventUIRefresh(-1)
    r.Undo_EndBlock("TK Kit Maker: Create empty kit rack (failed)", -1)
    return false
  end

  r.GetSetMediaTrackInfo_String(parent, "P_NAME", "Empty Kit", true)
  r.SetMediaTrackInfo_Value(parent, "I_FOLDERDEPTH", 1)

  for i = 1, GRID_SLOTS do
    r.InsertTrackAtIndex(insert_idx + i, true)
    local child = r.GetTrack(0, insert_idx + i)
    if child then
      r.GetSetMediaTrackInfo_String(child, "P_NAME", string.format("Pad %02d", i), true)
      create_empty_rs5k(child, DEFAULT_BASE_NOTE + (i - 1))
      r.SetMediaTrackInfo_Value(child, "I_FOLDERDEPTH", i == GRID_SLOTS and -1 or 0)
    end
  end

  local rows = collect_rows(parent)
  apply_rack_midi_input(parent, rows, 6112)
  set_rack_arm_state(parent, rows, false, 6112)

  r.SetOnlyTrackSelected(parent)
  if app.rs5k_manager then
    app.rs5k_manager.selected_slot = nil
    stop_preview(app.rs5k_manager)
  end

  r.PreventUIRefresh(-1)
  r.TrackList_AdjustWindows(false)
  r.UpdateArrange()
  r.Undo_EndBlock("TK Kit Maker: Create empty kit rack", -1)
  state.manager_visible = true
  save(app)
  return true
end

local function find_rs5k_fx(track)
  local function looks_like_rs5k(fx)
    local ok, name = r.TrackFX_GetFXName(track, fx, "")
    local lower_name = ok and name and name:lower() or ""
    if lower_name:find("reasamplomatic", 1, true) or lower_name:find("rs5k", 1, true) then
      return true
    end
    if r.TrackFX_GetNamedConfigParm then
      local parm_ok, path = r.TrackFX_GetNamedConfigParm(track, fx, "FILE0")
      if parm_ok and path ~= nil then
        return true
      end
    end
    return false
  end

  local count = r.TrackFX_GetCount(track)
  for i = 0, count - 1 do
    if looks_like_rs5k(i) then
      return i
    end
  end

  if r.TrackFX_GetRecCount then
    local rec_count = r.TrackFX_GetRecCount(track)
    for i = 0, rec_count - 1 do
      local fx = 0x1000000 + i
      if looks_like_rs5k(fx) then
        return fx
      end
    end
  end
  return -1
end

local function get_rs5k_note(track, fx)
  local n = r.TrackFX_GetParamNormalized(track, fx, 3)
  if n == nil then return nil end
  return math.floor((n * 127) + 0.5)
end

local function get_rs5k_file(track, fx)
  if not r.TrackFX_GetNamedConfigParm then return nil end
  local ok, path = r.TrackFX_GetNamedConfigParm(track, fx, "FILE0")
  if ok and path and path ~= "" then return path end
  return nil
end

local function rs5k_obeys_note_off(track, fx)
  if not track or fx == nil or fx < 0 then return false end
  if not r.TrackFX_GetParamNormalized then return false end
  local value = r.TrackFX_GetParamNormalized(track, fx, 11)
  return (tonumber(value) or 0) > 0.5
end

local function set_row_rs5k_obey_note_off(row, enabled)
  if not row or not row.track or row.fx == nil or row.fx < 0 then return false end
  if not r.TrackFX_SetParamNormalized then return false end
  r.TrackFX_SetParamNormalized(row.track, row.fx, 11, enabled and 1 or 0)
  return true
end

local function release_note_off_on_mouse_up_enabled(state)
  if not state then return true end
  return state.manager_release_note_off_on_mouse_up ~= false
end

local function clamp_byte(v)
  return math.max(0, math.min(255, math.floor((tonumber(v) or 0) + 0.5)))
end

local function rgba_to_rgb_components(rgba)
  local c = math.floor(tonumber(rgba) or 0)
  local rr = (c >> 24) & 0xFF
  local gg = (c >> 16) & 0xFF
  local bb = (c >> 8) & 0xFF
  return rr, gg, bb
end

local function rgb_to_rgba(rr, gg, bb)
  return ((clamp_byte(rr) & 0xFF) << 24) | ((clamp_byte(gg) & 0xFF) << 16) | ((clamp_byte(bb) & 0xFF) << 8) | 0xFF
end

local function shade_rgba(rgba, factor)
  local rr, gg, bb = rgba_to_rgb_components(rgba)
  return rgb_to_rgba(rr * factor, gg * factor, bb * factor)
end

local function blend_rgba(rgba_a, rgba_b, t)
  local a_r, a_g, a_b = rgba_to_rgb_components(rgba_a)
  local b_r, b_g, b_b = rgba_to_rgb_components(rgba_b)
  local k = math.max(0, math.min(1, tonumber(t) or 0))
  local rr = a_r + ((b_r - a_r) * k)
  local gg = a_g + ((b_g - a_g) * k)
  local bb = a_b + ((b_b - a_b) * k)
  return rgb_to_rgba(rr, gg, bb)
end

local function apply_track_color(track, rgba)
  if not track or not r.ColorToNative then return false end
  local rr, gg, bb = rgba_to_rgb_components(rgba)
  local native = (r.ColorToNative(rr, gg, bb) or 0) | 0x1000000
  r.SetMediaTrackInfo_Value(track, "I_CUSTOMCOLOR", native)
  return true
end

local function apply_rack_colors(parent, rows, base_color, gradient)
  if not parent then return 0 end
  local opaque_base = ((math.floor(tonumber(base_color) or 0) >> 8) << 8) | 0xFF
  local changed = 0
  if apply_track_color(parent, opaque_base) then
    changed = changed + 1
  end
  local count = #rows
  for i, row in ipairs(rows or {}) do
    if row and row.track then
      local child_color = opaque_base
      if gradient and count > 1 then
        local t = (i - 1) / (count - 1)
        local eased_t = t ^ 0.70
        local whiten = 0.22 + (0.66 * eased_t)
        child_color = blend_rgba(opaque_base, 0xFFFFFFFF, whiten)
      elseif gradient then
        child_color = blend_rgba(opaque_base, 0xFFFFFFFF, 0.30)
      end
      if apply_track_color(row.track, child_color) then
        changed = changed + 1
      end
    end
  end
  return changed
end

local function get_track_index0(track)
  return math.floor((r.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER") or 1) - 1)
end

local function each_child_track(parent, fn)
  if not parent then return end
  local parent_depth = r.GetTrackDepth(parent)
  local parent_idx = get_track_index0(parent)
  local track_count = r.CountTracks(0)
  for i = parent_idx + 1, track_count - 1 do
    local tr = r.GetTrack(0, i)
    if r.GetTrackDepth(tr) <= parent_depth then
      break
    end
    local is_bus = false
    if r.GetSetMediaTrackInfo_String then
      local ok, v = r.GetSetMediaTrackInfo_String(tr, "P_EXT:TK_KIT_MAKER_SEQ_BUS", "", false)
      is_bus = ok and v ~= nil and v ~= ""
    end
    if not is_bus then
      fn(tr, i)
    end
  end
end

local function get_selected_rack_parent_track()
  local selected = r.GetSelectedTrack(0, 0)
  if not selected then return nil end
  local current = selected
  while current do
    if (r.GetMediaTrackInfo_Value(current, "I_FOLDERDEPTH") or 0) > 0 then
      return current
    end
    if not r.GetParentTrack then break end
    current = r.GetParentTrack(current)
  end
  return nil
end

local function collect_rows(parent)
  local rows = {}
  each_child_track(parent, function(tr)
    local fx = find_rs5k_fx(tr)
    local note = fx >= 0 and get_rs5k_note(tr, fx) or nil
    local slot = note and note >= DEFAULT_BASE_NOTE and ((note - DEFAULT_BASE_NOTE) + 1) or nil
    rows[#rows + 1] = {
      track = tr,
      fx = fx,
      note = note,
      slot = slot,
      track_name = track_name(tr),
      sample_path = fx >= 0 and get_rs5k_file(tr, fx) or nil,
      has_rs5k = fx >= 0,
    }
  end)
  table.sort(rows, function(a, b)
    local as = a.slot or 9999
    local bs = b.slot or 9999
    if as == bs then
      return a.track_name:lower() < b.track_name:lower()
    end
    return as < bs
  end)
  return rows
end

local function detect_grid_base_note(rows)
  local min_note = nil
  for _, row in ipairs(rows) do
    if row.note then
      if not min_note or row.note < min_note then
        min_note = row.note
      end
    end
  end
  return min_note or DEFAULT_BASE_NOTE
end

local function rows_by_slot(rows, base_note)
  local map = {}
  local extras = {}
  for i, row in ipairs(rows) do
    local slot = nil
    if row.note then
      slot = (row.note - base_note) + 1
    end
    if (not slot or slot < 1 or slot > GRID_SLOTS) and i <= GRID_SLOTS then
      slot = i
    end
    row.grid_slot = slot
    if slot and slot >= 1 and slot <= GRID_SLOTS and not map[slot] then
      map[slot] = row
    else
      extras[#extras + 1] = row
    end
  end
  return map, extras
end

local function selected_row(rows, slot)
  for _, row in ipairs(rows) do
    if row.slot == slot then return row end
  end
  return rows[1]
end

local function load_sample_to_pad(parent, slot, sample_path)
  local slot_n = math.floor(tonumber(slot) or 0)
  if slot_n < 1 or slot_n > GRID_SLOTS then
    return false
  end

  local rows = collect_rows(parent)
  local slot_map = rows_by_slot(rows, detect_grid_base_note(rows))
  local row = slot_map[slot_n]

  if not row then
    return false
  end

  local note = DEFAULT_BASE_NOTE + (slot_n - 1)
  local ok = load_sample_into_rs5k(row.track, sample_path, note)
  if ok then
    r.GetSetMediaTrackInfo_String(row.track, "P_NAME", file_leaf(sample_path), true)
  end
  return ok
end

function M.init(app)
  app.rs5k_manager = {
    selected_slot = nil,
    preview = nil,
    preview_source = nil,
    preview_path = nil,
    preview_slot = nil,
    midi_last_retval = nil,
    preview_volume = 1.0,
    cover_cache = {},
    cover_fallback_by_track = {},
    rename_buffer = "",
    rename_seed = "",
    rename_track_guid = nil,
    rename_popup_open = false,
    save_dir = app.browser and app.browser.manager_save_dir or nil,
  }
end

function M.draw(app)
  local state = app.browser
  local manager = app.rs5k_manager
  if not state or state.manager_visible ~= true or not manager then return end

  local ctx = app.ctx
  r.ImGui_SetNextWindowSize(ctx, 520, 700, r.ImGui_Cond_FirstUseEver())
  if r.ImGui_SetNextWindowSizeConstraints then
    r.ImGui_SetNextWindowSizeConstraints(ctx, 410, 480, 100000, 100000)
  end
  local window_flags = r.ImGui_WindowFlags_NoTitleBar() | r.ImGui_WindowFlags_NoScrollbar() | r.ImGui_WindowFlags_NoScrollWithMouse()
  local visible, open = r.ImGui_Begin(ctx, "Kit Manager", true, window_flags)
  if visible then
    local body_pushed = Theme.push_body(ctx)

    local header_h = 54
    local settings_size = 16
    local close_size = 16
    local header_y = r.ImGui_GetCursorPosY(ctx)
    local header_x = r.ImGui_GetCursorPosX(ctx)
    local avail_w = select(1, r.ImGui_GetContentRegionAvail(ctx)) or 0
    local close_x = header_x + math.max(0, avail_w - close_size)
    local settings_x = close_x - settings_size - 8
    local title_pushed = Theme.push_h1(ctx)
    r.ImGui_TextColored(ctx, Theme.colors.accent, "Kit Manager")
    Theme.pop_font(ctx, title_pushed)

    r.ImGui_SetCursorPosX(ctx, settings_x)
    r.ImGui_SetCursorPosY(ctx, header_y + 2)
    do
      local dl = r.ImGui_GetWindowDrawList(ctx)
      local x, y = r.ImGui_GetCursorScreenPos(ctx)
      local clicked = r.ImGui_InvisibleButton(ctx, "##kit_manager_settings", settings_size, settings_size)
      local hovered = r.ImGui_IsItemHovered(ctx)
      local col = hovered and Theme.colors.accent or 0xFFFFFFFF
      r.ImGui_DrawList_AddCircleFilled(dl, x + settings_size * 0.5, y + settings_size * 0.5, settings_size * 0.42, col)
      if hovered and r.ImGui_SetTooltip then r.ImGui_SetTooltip(ctx, "Kit Manager settings") end
      if clicked then
        r.ImGui_OpenPopup(ctx, "##kit_manager_settings_popup")
      end
    end

    r.ImGui_SetCursorPosX(ctx, close_x)
    r.ImGui_SetCursorPosY(ctx, header_y + 2)
    if close_button(ctx, close_size) then
      state.manager_visible = false
      stop_track_audition(app.rs5k_manager)
      stop_preview(app.rs5k_manager)
      save(app)
      Theme.pop_font(ctx, body_pushed)
      r.ImGui_End(ctx)
      return
    end

    if r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_Escape()) then
      state.manager_visible = false
      stop_track_audition(app.rs5k_manager)
      stop_preview(app.rs5k_manager)
      save(app)
      Theme.pop_font(ctx, body_pushed)
      r.ImGui_End(ctx)
      return
    end

    if r.ImGui_BeginPopup(ctx, "##kit_manager_settings_popup") then
      local track_mode = (state.manager_audition_mode == "track")
      local changed, value = r.ImGui_Checkbox(ctx, "Play samples via track MIDI", track_mode)
      if changed then
        state.manager_audition_mode = value and "track" or "preview"
        if value then
          local parent_track = get_selected_rack_parent_track()
          if parent_track then
            apply_rack_midi_input(parent_track, collect_rows(parent_track), 6112)
          end
        end
        save(app)
      end
      local release_note_off = release_note_off_on_mouse_up_enabled(state)
      local release_changed, release_value = r.ImGui_Checkbox(ctx, "Releasing mouse on pad sends note off", release_note_off)
      if release_changed then
        state.manager_release_note_off_on_mouse_up = release_value and true or false
        save(app)
      end
      if r.ImGui_ColorEdit4 then
        local flags = r.ImGui_ColorEditFlags_NoInputs and r.ImGui_ColorEditFlags_NoInputs() or 0
        local current_color = (((math.floor(tonumber(state.manager_rack_color) or 0x4DA3FFFF) >> 8) << 8) | 0xFF)
        local color_changed, picked = r.ImGui_ColorEdit4(ctx, "Rack color##kit_manager_rack_color", current_color, flags)
        if color_changed then
          state.manager_rack_color = (((math.floor(tonumber(picked) or current_color) >> 8) << 8) | 0xFF)
          save(app)
        end
      end
      local gradient_changed, gradient_enabled = r.ImGui_Checkbox(ctx, "Gradient across rack tracks", state.manager_rack_gradient == true)
      if gradient_changed then
        state.manager_rack_gradient = gradient_enabled == true
        save(app)
      end
      if Theme.ghost_button(ctx, "Apply rack color##kit_manager_apply_rack_color", 0, 0) then
        local parent_track = get_selected_rack_parent_track()
        if parent_track then
          local rack_rows = collect_rows(parent_track)
          r.Undo_BeginBlock()
          r.PreventUIRefresh(1)
          local changed_count = apply_rack_colors(parent_track, rack_rows, state.manager_rack_color or 0x4DA3FFFF, state.manager_rack_gradient == true)
          r.PreventUIRefresh(-1)
          r.TrackList_AdjustWindows(false)
          r.UpdateArrange()
          if changed_count > 0 then
            r.Undo_EndBlock("TK Kit Maker: Apply rack colors", -1)
          else
            r.Undo_EndBlock("TK Kit Maker: Apply rack colors (no changes)", -1)
          end
        end
      end
      Theme.label(ctx, "Track mode needs the kit rack to be armed and monitoring.")
      if Theme.ghost_button(ctx, "Close##kit_manager_settings_close", 70, 0) then
        r.ImGui_CloseCurrentPopup(ctx)
      end
      r.ImGui_EndPopup(ctx)
    end

    r.ImGui_Dummy(ctx, 0, 2)
    r.ImGui_Separator(ctx)
    r.ImGui_Dummy(ctx, 0, 10)

    local parent = get_selected_rack_parent_track()
    local rows = parent and collect_rows(parent) or {}
    local grid_base_note = detect_grid_base_note(rows)
    local slot_map, extras = parent and rows_by_slot(rows, grid_base_note) or {}, {}
    sync_rename_state(app, parent)
    draw_rename_popup(app, parent, rows)

    local cover_path = resolve_cover_path(app, parent, rows)
    local cover_tex = cover_texture(app.rs5k_manager, cover_path)
    local cover_w, cover_h = 118, 118
    local spacing = 10
    local avail_w = select(1, r.ImGui_GetContentRegionAvail(ctx)) or 0
    local start_x = r.ImGui_GetCursorPosX(ctx)
    local start_y = r.ImGui_GetCursorPosY(ctx)
    local cover_y = math.max(0, start_y - 18)
    local row_h = r.ImGui_GetFrameHeight(ctx)
    local header_gap = math.max(0, math.floor((cover_h - (row_h * 3)) / 2))

    local midi_options = midi_input_options()
    local midi_input_value = parent and track_midi_input_value(parent) or 6112
    local midi_label = midi_input_label(midi_input_value, midi_options)

    r.ImGui_SetCursorPosY(ctx, cover_y)
    local kit_name = parent and track_name(parent) or "Empty kit"
    local name_label = app.rs5k_manager.rename_buffer ~= "" and app.rs5k_manager.rename_buffer or kit_name
    local action_gap = 8
    local name_button_w = 76 + action_gap + 76 + action_gap + 82
    if Theme.ghost_button(ctx, name_label .. "##kit_manager_name_button", name_button_w, 0) then
      open_rename_popup(app, parent)
    end
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Rename kit") end

    local buttons_y = cover_y + row_h + header_gap
    r.ImGui_SetCursorPosY(ctx, buttons_y)

    if Theme.ghost_button(ctx, "New Kit##kit_manager_new", 76, 0) then
      create_empty_rack(app)
    end
    if r.ImGui_IsItemHovered(ctx) then
      r.ImGui_SetTooltip(ctx, "Creates a brand-new empty kit rack in REAPER.")
    end

    r.ImGui_SameLine(ctx, 0, action_gap)
    if Theme.ghost_button(ctx, "Save kit##kit_manager_save", 76, 0) then
      save_current_kit(app, parent, rows)
    end

    r.ImGui_SameLine(ctx, 0, action_gap)
    local armed = parent and rack_all_armed(parent, rows) or false
    if Theme.ghost_button(ctx, armed and "Disarm Kit##kit_manager_arm" or "Arm Kit##kit_manager_arm", 82, 0) then
      set_rack_arm_state(parent, rows, not armed, midi_input_value)
    end

    local midi_y = buttons_y + row_h + header_gap
    r.ImGui_SetCursorPosY(ctx, midi_y)
    local midi_combo_w = name_button_w
    r.ImGui_SetNextItemWidth(ctx, midi_combo_w)
    if parent and r.ImGui_BeginCombo(ctx, "##kit_manager_midi_input", midi_label) then
      if r.ImGui_Selectable(ctx, "All MIDI##kit_manager_midi_all", midi_input_value == 6112) then
        apply_rack_midi_input(parent, rows, 6112)
        midi_input_value = 6112
      end
      for _, opt in ipairs(midi_options) do
        if opt.value ~= 6112 then
          local selected = midi_input_value == opt.value
          if r.ImGui_Selectable(ctx, opt.label .. "##kit_manager_midi_" .. tostring(opt.value), selected) then
            apply_rack_midi_input(parent, rows, opt.value)
            midi_input_value = opt.value
          end
        end
      end
      r.ImGui_EndCombo(ctx)
    end

    r.ImGui_SetCursorPosX(ctx, start_x + math.max(0, avail_w - cover_w))
    r.ImGui_SetCursorPosY(ctx, cover_y)
    local cover_flags = 0
    if r.ImGui_WindowFlags_NoScrollbar then
      cover_flags = cover_flags | r.ImGui_WindowFlags_NoScrollbar()
    end
    if r.ImGui_WindowFlags_NoScrollWithMouse then
      cover_flags = cover_flags | r.ImGui_WindowFlags_NoScrollWithMouse()
    end

    local cover_padding_pushed = false
    local cover_border_pushed = false
    if r.ImGui_PushStyleVar and r.ImGui_StyleVar_WindowPadding then
      r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), 0, 0)
      cover_padding_pushed = true
    end
    if r.ImGui_PushStyleVar and r.ImGui_StyleVar_ChildBorderSize then
      r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ChildBorderSize(), 1.5)
      cover_border_pushed = true
    end

    if r.ImGui_BeginChild(ctx, "##kit_manager_cover", cover_w, cover_h, 1, cover_flags) then
      local cover_hovered = r.ImGui_IsWindowHovered(ctx)
      local cover_inset = 2
      if cover_tex and r.ImGui_Image then
        local img_w, img_h = image_size(ctx, cover_tex, cover_w, cover_h)
        local inner_w, inner_h = r.ImGui_GetContentRegionAvail(ctx)
        inner_w = math.max(1, (tonumber(inner_w) or cover_w) - (cover_inset * 2))
        inner_h = math.max(1, (tonumber(inner_h) or cover_h) - (cover_inset * 2))
        local scale = math.min(inner_w / img_w, inner_h / img_h)
        local draw_w = math.max(1, img_w * scale)
        local draw_h = math.max(1, img_h * scale)
        local x0, y0 = r.ImGui_GetCursorPos(ctx)
        r.ImGui_SetCursorPos(ctx, x0 + cover_inset + math.max(0, (inner_w - draw_w) * 0.5), y0 + cover_inset + math.max(0, (inner_h - draw_h) * 0.5))
        r.ImGui_Image(ctx, cover_tex, draw_w, draw_h)
      else
        local text = "No image"
        local text_w = select(1, r.ImGui_CalcTextSize(ctx, text)) or 0
        local inner_w, inner_h = r.ImGui_GetContentRegionAvail(ctx)
        inner_w = math.max(1, (tonumber(inner_w) or cover_w) - (cover_inset * 2))
        inner_h = math.max(1, (tonumber(inner_h) or cover_h) - (cover_inset * 2))
        local text_x = cover_inset + math.max(0, (inner_w - text_w) * 0.5)
        local text_y = cover_inset + math.max(22, (inner_h * 0.5) - 8)
        r.ImGui_SetCursorPos(ctx, text_x, text_y)
        Theme.label(ctx, text)
      end
      if parent and cover_hovered then
        if r.ImGui_SetTooltip then r.ImGui_SetTooltip(ctx, "Click to choose cover image") end
        if r.ImGui_IsMouseClicked(ctx, 0) then
          local selected_cover = choose_cover_path(app, parent, rows)
          if selected_cover then
            cover_path = selected_cover
          end
        end
      end
      r.ImGui_EndChild(ctx)
    end
    do
      local cover_min_x, cover_min_y = r.ImGui_GetItemRectMin(ctx)
      local cover_max_x, cover_max_y = r.ImGui_GetItemRectMax(ctx)
      local cover_dl = r.ImGui_GetWindowDrawList(ctx)
      r.ImGui_DrawList_AddRect(cover_dl, cover_min_x + 0.5, cover_min_y + 0.5, cover_max_x - 0.5, cover_max_y - 0.5, Theme.colors.accent, 3, 0, 2)
    end
    if cover_border_pushed and r.ImGui_PopStyleVar then
      r.ImGui_PopStyleVar(ctx)
    end
    if cover_padding_pushed and r.ImGui_PopStyleVar then
      r.ImGui_PopStyleVar(ctx)
    end
    local line_x, line_y = r.ImGui_GetCursorScreenPos(ctx)
    local line_w = math.max(1, avail_w)
    local dl = r.ImGui_GetWindowDrawList(ctx)
    r.ImGui_DrawList_AddLine(dl, line_x, line_y, line_x + line_w, line_y, Theme.colors.border, 1)
    r.ImGui_Dummy(ctx, 0, 0)
    if not parent then
      r.ImGui_TextColored(ctx, Theme.colors.warning, "Select a folder track or a child track inside a kit.")
      if not open then
        state.manager_visible = false
        save(app)
      end
      Theme.pop_font(ctx, body_pushed)
      r.ImGui_End(ctx)
      return
    end

    if #rows == 0 then
      r.ImGui_TextColored(ctx, Theme.colors.warning, "No child tracks found under the selected rack.")
      if not open then
        state.manager_visible = false
        save(app)
      end
      Theme.pop_font(ctx, body_pushed)
      r.ImGui_End(ctx)
      return
    end

    local current = selected_row(rows, app.rs5k_manager.selected_slot)
    if current and current.slot then app.rs5k_manager.selected_slot = current.slot end

    flash_pads_from_recent_midi(app.rs5k_manager, grid_base_note)

    local avail_w = select(1, r.ImGui_GetContentRegionAvail(ctx)) or 520
    local pad_gap = avail_w <= 430 and 4 or 8
    local pad_w = math.max(64, math.floor((avail_w - (pad_gap * (GRID_COLS - 1))) / GRID_COLS))
    local pad_h = math.max(52, math.floor(pad_w * 0.72))
    local grid_h = (pad_h * GRID_ROWS) + (pad_gap * (GRID_ROWS - 1)) + 14

    local seq_state = app.sequencer
    local parent_guid = parent and r.GetTrackGUID and r.GetTrackGUID(parent) or nil
    local seq_running = seq_state and seq_state.playing and parent_guid and seq_state.current_guid == parent_guid
    local seq_data = seq_running and seq_state.cache and seq_state.cache[parent_guid] or nil
    if r.ImGui_BeginChild(ctx, "##kit_manager_grid", 0, math.max(230, grid_h), 0) then
      for visual_row = GRID_ROWS, 1, -1 do
        for col = 1, GRID_COLS do
          local slot = ((visual_row - 1) * GRID_COLS) + col
          local row = slot_map[slot]
          local is_selected = current and current.slot == slot
          local lane = row and row.grid_slot or slot
          local lane_step = (seq_running and seq_state.lane_play_steps) and seq_state.lane_play_steps[lane] or nil
          local rhythm_active = false
          if lane_step and seq_data and seq_data.pattern and seq_data.pattern[lane] then
            rhythm_active = (seq_data.pattern[lane][lane_step] == 1)
          end
          local clicked, open_modifier_clicked, released = draw_pad_cell(ctx, app.rs5k_manager, slot, row, grid_base_note, pad_w, pad_h, is_selected, rhythm_active)
          if clicked then
            app.rs5k_manager.selected_slot = slot
            current = row or current
            if row and row.track then
              r.SetOnlyTrackSelected(row.track)
            end
            if open_modifier_clicked then
              open_row_rs5k(row)
            else
              audition_selected_sample(app, row)
            end
          end
          if released and release_note_off_on_mouse_up_enabled(state) then
            if state.manager_audition_mode == "track" and row and row.track and row.fx and row.fx >= 0 and app.rs5k_manager.track_audition_slot == slot and rs5k_obeys_note_off(row.track, row.fx) then
              stop_track_audition(app.rs5k_manager)
            elseif state.manager_audition_mode ~= "track" and app.rs5k_manager.preview_slot == slot then
              stop_preview(app.rs5k_manager)
            end
          end
          local pad_min_x, pad_min_y = r.ImGui_GetItemRectMin(ctx)
          local pad_max_x, pad_max_y = r.ImGui_GetItemRectMax(ctx)
          local mx, my = global_mouse_pos(ctx)
          if state.drag_sample_path and state.drag_release_seen and point_in_rect(mx, my, pad_min_x, pad_min_y, pad_max_x, pad_max_y) then
            if row and row.track and load_sample_to_pad(parent, slot, state.drag_sample_path) then
              app.rs5k_manager.selected_slot = slot
              current = row
              r.SetOnlyTrackSelected(row.track)
              state.drag_sample_path = nil
              state.drag_release_seen = false
              save(app)
            end
          end
          if r.ImGui_BeginDragDropTarget and r.ImGui_AcceptDragDropPayload then
            if r.ImGui_BeginDragDropTarget(ctx) then
              local payload = accept_dropped_sample_path(ctx)
              if payload and payload ~= "" then
                if row and row.track then
                  load_sample_to_pad(parent, slot, payload)
                  app.rs5k_manager.selected_slot = slot
                  current = row
                  r.SetOnlyTrackSelected(row.track)
                  save(app)
                end
              end
              r.ImGui_EndDragDropTarget(ctx)
            end
          end
          if col < GRID_COLS then
            r.ImGui_SameLine(ctx, nil, pad_gap)
          end
        end
      end
      r.ImGui_EndChild(ctx)
    end

    if #extras > 0 then
      r.ImGui_TextColored(ctx, Theme.colors.text_dim, tostring(#extras) .. " child tracks fall outside the current 4x4 kit range.")
    end

    if r.ImGui_BeginChild(ctx, "##kit_manager_transport", 0, 0, 1) then
      current = selected_row(rows, app.rs5k_manager.selected_slot)
      r.ImGui_Separator(ctx)
      if Theme.ghost_button(ctx, "Aud##kit_manager_audition", 58, 0) and current and current.sample_path and current.sample_path ~= "" then
        audition_selected_sample(app, current)
      end
      r.ImGui_SameLine(ctx)
      if Theme.ghost_button(ctx, "Stop##kit_manager_stop_preview", 58, 0) then
        stop_track_audition(app.rs5k_manager)
        stop_preview(app.rs5k_manager)
      end
      r.ImGui_SameLine(ctx)
      if Theme.ghost_button(ctx, "RS5K##kit_manager_open_rs5k", 58, 0) and current then
        if current.track then
          r.SetOnlyTrackSelected(current.track)
        end
        open_row_rs5k(current)
      end
      if current and current.track and current.fx and current.fx >= 0 then
        r.ImGui_SameLine(ctx)
        local obey_note_off = rs5k_obeys_note_off(current.track, current.fx)
        local obey_changed, obey_value = r.ImGui_Checkbox(ctx, "Note-off##kit_manager_row_obey", obey_note_off)
        if obey_changed then
          r.Undo_BeginBlock()
          r.PreventUIRefresh(1)
          local ok = set_row_rs5k_obey_note_off(current, obey_value == true)
          r.PreventUIRefresh(-1)
          r.TrackList_AdjustWindows(false)
          r.UpdateArrange()
          if ok then
            r.Undo_EndBlock("TK Kit Maker: Set RS5K obey note-offs for pad", -1)
          else
            r.Undo_EndBlock("TK Kit Maker: Set RS5K obey note-offs for pad (failed)", -1)
          end
        end
        if r.ImGui_IsItemHovered(ctx) then
          r.ImGui_SetTooltip(ctx, "Echte RS5K instelling voor geselecteerd pad")
        end
      end
      r.ImGui_SameLine(ctx)
      local vol_avail = tonumber((r.ImGui_GetContentRegionAvail(ctx))) or 120
      r.ImGui_SetNextItemWidth(ctx, math.max(120, vol_avail))
      local vol_changed, vol_value = r.ImGui_SliderDouble(ctx, "##kit_manager_preview_vol", manager.preview_volume or 1.0, 0, 2.0, "%.2f")
      if vol_changed then
        manager.preview_volume = vol_value
        if manager.preview and r.CF_Preview_SetValue then
          r.CF_Preview_SetValue(manager.preview, "D_VOLUME", vol_value)
        end
      end

      local playing_text = "Playing: -"
      if manager.preview_path then
        local leaf = manager.preview_path:match("([^/\\]+)$") or manager.preview_path
        playing_text = "Playing: " .. leaf
      end
      local pushed = Theme.push_small(ctx)
      Theme.label(ctx, playing_text)
      Theme.pop_font(ctx, pushed)
      r.ImGui_Separator(ctx)

      local transport_min_x, transport_min_y = r.ImGui_GetWindowPos(ctx)
      local transport_w, transport_h = r.ImGui_GetWindowSize(ctx)
      local transport_max_x = transport_min_x + transport_w
      local transport_max_y = transport_min_y + transport_h
      local mx, my = global_mouse_pos(ctx)
      if state.drag_sample_path and state.drag_release_seen and current and current.track and point_in_rect(mx, my, transport_min_x, transport_min_y, transport_max_x, transport_max_y) then
        if load_sample_into_rs5k(current.track, state.drag_sample_path, current.note or (DEFAULT_BASE_NOTE + ((current.grid_slot or 1) - 1))) then
          local sample_name = file_leaf(state.drag_sample_path)
          r.GetSetMediaTrackInfo_String(current.track, "P_NAME", sample_name, true)
          state.drag_sample_path = nil
          state.drag_release_seen = false
          save(app)
        end
      end
      if r.ImGui_BeginDragDropTarget and r.ImGui_AcceptDragDropPayload and current and current.track then
        if r.ImGui_BeginDragDropTarget(ctx) then
          local payload = accept_dropped_sample_path(ctx)
          if payload and payload ~= "" then
            if load_sample_into_rs5k(current.track, payload, current.note or (DEFAULT_BASE_NOTE + ((current.grid_slot or 1) - 1))) then
              local sample_name = file_leaf(payload)
              r.GetSetMediaTrackInfo_String(current.track, "P_NAME", sample_name, true)
              save(app)
            end
          end
          r.ImGui_EndDragDropTarget(ctx)
        end
      end
      r.ImGui_EndChild(ctx)
    end

    Theme.pop_font(ctx, body_pushed)
    r.ImGui_End(ctx)
  end
  if not open then
    stop_track_audition(app.rs5k_manager)
    stop_preview(app.rs5k_manager)
    state.manager_visible = false
    save(app)
  end
end

return M