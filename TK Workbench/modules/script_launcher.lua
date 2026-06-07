local r = reaper
local Theme = require("core.theme")
local UI = require("core.ui")
local UIScale = require("core.ui_scale")
local json = require("core.json")

local M = {
  id = "script_launcher",
  title = "Script Launcher",
  icon = "SCR",
  version = "0.1.0"
}

local defaults = {
  search_term = "",
  show_labels = true,
  sort_mode = "name",
  max_textures_per_frame = 12,
  max_cached_textures = 120,
  min_cached_textures = 40,
  texture_ttl_seconds = 300
}

local state = {
  entries = {},
  filtered = {},
  data_path = "",
  thumbs_dir = "",
  image_cache = {},
  texture_load_queue = {},
  loaded = false,
  dirty_filter = true,
  edit_index = nil,
  popup_mode = nil,
  form_name = "",
  form_cmd = "",
  form_thumb = "",
  form_label = "",
  capture_window_list = {},
  capture_target_name = "",
  pending_edit_index = nil
}

local function copy_default(value)
  if type(value) ~= "table" then return value end
  local result = {}
  for key, child in pairs(value) do result[key] = copy_default(child) end
  return result
end

local function ensure_settings(app)
  app.settings.script_launcher = app.settings.script_launcher or {}
  local settings = app.settings.script_launcher
  local changed = false
  for key, value in pairs(defaults) do
    if settings[key] == nil then
      settings[key] = copy_default(value)
      changed = true
    end
  end
  if settings.sort_mode ~= "manual" then settings.sort_mode = "name" end
  if changed and app.save_settings then app.save_settings() end
  return settings
end

local function now()
  return os.time()
end

local function precise_now()
  if r.time_precise then return r.time_precise() end
  return os.clock()
end

local function file_exists(path)
  local file = io.open(path, "rb")
  if file then file:close(); return true end
  return false
end

local function read_text(path)
  local file = io.open(path, "rb")
  if not file then return nil end
  local content = file:read("*all")
  file:close()
  return content
end

local function write_json(path, value)
  local ok, encoded = pcall(json.encode, value)
  if not ok or not encoded then return false end
  local file = io.open(path, "w")
  if not file then return false end
  file:write(encoded)
  file:close()
  return true
end

local function os_separator()
  return package.config and package.config:sub(1, 1) or "\\"
end

local function join_path(base, leaf)
  if not base or base == "" then return leaf or "" end
  if not leaf or leaf == "" then return base end
  local sep = os_separator()
  if base:sub(-1) == sep or base:sub(-1) == "/" or base:sub(-1) == "\\" then
    return base .. leaf
  end
  return base .. sep .. leaf
end

local function ensure_dir(path)
  if not path or path == "" then return false end
  if r.file_exists and r.file_exists(path) then return true end
  local ok = r.RecursiveCreateDirectory and r.RecursiveCreateDirectory(path, 0)
  return ok and true or false
end

local function sanitize_name(name)
  local value = tostring(name or ""):gsub("[^%w%s-]", "_"):match("^%s*(.-)%s*$")
  if value == "" then value = "screenshot_" .. tostring(now()) end
  return value
end

local function normalize_entry(entry, index)
  if type(entry) ~= "table" then return nil end
  local cmd = tostring(entry.cmd or ""):match("^%s*(.-)%s*$")
  local name = tostring(entry.name or ""):match("^%s*(.-)%s*$")
  if cmd == "" then return nil end
  if name == "" then name = cmd end
  local created = tonumber(entry.created_at) or now()
  return {
    id = tostring(entry.id or ("script_" .. tostring(index or created))),
    name = name,
    cmd = cmd,
    thumb = tostring(entry.thumb or ""),
    label = tostring(entry.label or ""),
    created_at = created,
    updated_at = tonumber(entry.updated_at) or created
  }
end

local function load_entries(app)
  state.data_path = (app.script_path or "") .. "script_launcher.json"
  state.thumbs_dir = join_path(app.script_path or "", "ScriptThumbnails")
  ensure_dir(state.thumbs_dir)
  state.entries = {}
  local content = read_text(state.data_path)
  if content and content ~= "" then
    local ok, decoded = pcall(json.decode, content)
    if ok and type(decoded) == "table" then
      local source = type(decoded.entries) == "table" and decoded.entries or decoded
      for index, entry in ipairs(source) do
        local clean = normalize_entry(entry, index)
        if clean then state.entries[#state.entries + 1] = clean end
      end
    end
  end
  state.loaded = true
  state.dirty_filter = true
end

local function get_visible_windows()
  if not (r.JS_Window_ListAllTop and r.JS_Window_HandleFromAddress and r.JS_Window_IsVisible and r.JS_Window_GetTitle) then
    return nil
  end
  local windows = {}
  local _, list = r.JS_Window_ListAllTop()
  if not list or list == "" then return windows end
  local main_hwnd = r.GetMainHwnd and r.GetMainHwnd() or nil
  for addr_str in list:gmatch("[^,]+") do
    local hwnd = r.JS_Window_HandleFromAddress(addr_str)
    if not hwnd then
      hwnd = r.JS_Window_HandleFromAddress(tonumber(addr_str))
    end
    if hwnd and hwnd ~= main_hwnd and r.JS_Window_IsVisible(hwnd) then
      local title = r.JS_Window_GetTitle(hwnd)
      if title and title ~= "" and not title:match("^TK FX BROWSER") then
        windows[#windows + 1] = { hwnd = hwnd, title = title }
      end
    end
  end
  table.sort(windows, function(left, right) return left.title:lower() < right.title:lower() end)
  return windows
end

local function is_osx()
  local platform = r.GetOS and r.GetOS() or ""
  return platform:match("OSX") or platform:match("macOS")
end

local function capture_window_screenshot(hwnd, save_name)
  if not hwnd then return nil end
  if not ensure_dir(state.thumbs_dir) then return nil end
  local safe_name = sanitize_name(save_name)
  local filename = join_path(state.thumbs_dir, safe_name .. ".png")
  if is_osx() and r.JS_Window_GetRect then
    local ok, left, top, right, bottom = r.JS_Window_GetRect(hwnd)
    local w = (right or 0) - (left or 0)
    local h = (bottom or 0) - (top or 0)
    if ok and w > 0 and h > 0 then
      local command = string.format('screencapture -x -R %d,%d,%d,%d -t png "%s"', left, top, w, h, filename)
      os.execute(command)
      if file_exists(filename) then return filename end
    end
    return nil
  end
  if not (r.JS_Window_GetClientRect and r.JS_GDI_GetClientDC and r.JS_LICE_CreateBitmap and r.JS_LICE_GetDC and r.JS_GDI_Blit and r.JS_LICE_WritePNG and r.JS_GDI_ReleaseDC and r.JS_LICE_DestroyBitmap) then
    return nil
  end
  local ok, left, top, right, bottom = r.JS_Window_GetClientRect(hwnd)
  if not ok then return nil end
  local w, h = right - left, bottom - top
  if w <= 0 or h <= 0 then return nil end
  local src_dc = r.JS_GDI_GetClientDC(hwnd)
  if not src_dc then return nil end
  local src_bmp = r.JS_LICE_CreateBitmap(true, w, h)
  if not src_bmp then
    r.JS_GDI_ReleaseDC(hwnd, src_dc)
    return nil
  end
  local src_dc_lice = r.JS_LICE_GetDC(src_bmp)
  r.JS_GDI_Blit(src_dc_lice, 0, 0, src_dc, 0, 0, w, h)
  r.JS_LICE_WritePNG(filename, src_bmp, false)
  r.JS_GDI_ReleaseDC(hwnd, src_dc)
  r.JS_LICE_DestroyBitmap(src_bmp)
  if file_exists(filename) then return filename end
  return nil
end

local function save_entries()
  return write_json(state.data_path, state.entries)
end

local function command_text(command_id)
  if r.CF_GetCommandText then
    local ok, text = pcall(r.CF_GetCommandText, 0, command_id)
    if ok and text and text ~= "" then return text end
  end
  return nil
end

local function resolve_command(cmd)
  cmd = tostring(cmd or ""):match("^%s*(.-)%s*$")
  if cmd == "" then return nil end
  if cmd:sub(1, 1) == "_" then
    local command_id = r.NamedCommandLookup(cmd)
    if command_id and command_id ~= 0 then return command_id end
    return nil
  end
  local command_id = tonumber(cmd)
  if command_id and command_id ~= 0 then return command_id end
  return nil
end

local function execute_entry(app, entry)
  local command_id = resolve_command(entry and entry.cmd)
  if not command_id then
    app.status = "Command not found: " .. tostring(entry and entry.cmd or "")
    return false
  end
  r.Main_OnCommand(command_id, 0)
  app.status = "Executed: " .. tostring(entry.name or entry.cmd)
  return true
end

local function matches_search(entry, term)
  if term == "" then return true end
  local haystack = (tostring(entry.name or "") .. " " .. tostring(entry.cmd or "") .. " " .. tostring(entry.label or "")):lower()
  for token in term:gmatch("%S+") do
    if not haystack:find(token, 1, true) then return false end
  end
  return true
end

local function refresh_filter(settings)
  if not state.dirty_filter then return end
  local term = tostring(settings.search_term or ""):lower()
  local result = {}
  for index, entry in ipairs(state.entries) do
    if matches_search(entry, term) then result[#result + 1] = { index = index, entry = entry } end
  end
  if settings.sort_mode ~= "manual" then
    table.sort(result, function(left, right)
      local left_label = tostring(left.entry.label or "")
      local right_label = tostring(right.entry.label or "")
      if left_label:lower() ~= right_label:lower() then return left_label:lower() < right_label:lower() end
      return tostring(left.entry.name or ""):lower() < tostring(right.entry.name or ""):lower()
    end)
  end
  state.filtered = result
  state.dirty_filter = false
end

local function destroy_texture(texture)
  if not texture or not r.ImGui_DestroyImage then return end
  local ok = pcall(r.ImGui_DestroyImage, texture)
  if not ok then pcall(r.ImGui_DestroyImage, nil, texture) end
end

local function clear_image_cache()
  for _, entry in pairs(state.image_cache) do destroy_texture(entry.texture) end
  state.image_cache = {}
  state.texture_load_queue = {}
end

local function get_cached_texture(path)
  local cached = state.image_cache[path]
  if not cached then return nil end
  cached.last_used = precise_now()
  return cached.texture
end

local function queue_texture(path)
  if not path or path == "" then return end
  if state.image_cache[path] or state.texture_load_queue[path] then return end
  state.texture_load_queue[path] = precise_now()
end

local function load_texture(ctx, path)
  if not path or path == "" or not file_exists(path) or not r.ImGui_CreateImage then return nil end
  local texture = get_cached_texture(path)
  if texture then return texture end
  queue_texture(path)
  return nil
end

local function process_texture_load_queue(ctx, settings)
  if not r.ImGui_CreateImage then
    state.texture_load_queue = {}
    return
  end
  local max_per_frame = math.max(1, tonumber(settings.max_textures_per_frame) or 12)
  local loaded = 0
  for path in pairs(state.texture_load_queue) do
    if loaded >= max_per_frame then break end
    state.texture_load_queue[path] = nil
    if file_exists(path) and not state.image_cache[path] then
      local ok, texture = pcall(r.ImGui_CreateImage, path)
      if ok and texture then
        if r.ImGui_Attach then pcall(r.ImGui_Attach, ctx, texture) end
        state.image_cache[path] = { texture = texture, last_used = precise_now() }
      end
    end
    loaded = loaded + 1
  end
end

local function trim_image_cache(settings)
  local max_cached = math.max(1, tonumber(settings.max_cached_textures) or 120)
  local min_cached = math.max(0, tonumber(settings.min_cached_textures) or 40)
  if min_cached > max_cached then min_cached = max_cached end
  local ttl = math.max(1, tonumber(settings.texture_ttl_seconds) or 300)
  local current_time = precise_now()
  local keys = {}
  local count = 0
  for path, entry in pairs(state.image_cache) do
    count = count + 1
    if current_time - (entry.last_used or current_time) > ttl and count > min_cached then
      keys[#keys + 1] = path
    end
  end
  if count > max_cached then
    local all = {}
    for path, entry in pairs(state.image_cache) do
      all[#all + 1] = { path = path, last_used = entry.last_used or 0 }
    end
    table.sort(all, function(left, right) return left.last_used < right.last_used end)
    local remove_needed = count - max_cached
    for index = 1, remove_needed do
      local item = all[index]
      if item then keys[#keys + 1] = item.path end
    end
  end
  local removed = {}
  for _, path in ipairs(keys) do
    if not removed[path] and state.image_cache[path] then
      destroy_texture(state.image_cache[path].texture)
      state.image_cache[path] = nil
      removed[path] = true
    end
  end
end

local function begin_form(mode, index, entry)
  state.popup_mode = mode
  state.edit_index = index
  state.form_name = entry and entry.name or ""
  state.form_cmd = entry and entry.cmd or ""
  state.form_thumb = entry and entry.thumb or ""
  state.form_label = entry and entry.label or ""
end

local function label_options()
  local seen = {}
  local labels = {}
  for _, entry in ipairs(state.entries) do
    local label = tostring(entry.label or "")
    if label ~= "" and not seen[label] then
      seen[label] = true
      labels[#labels + 1] = label
    end
  end
  table.sort(labels, function(left, right) return left:lower() < right:lower() end)
  return labels
end

local function command_exists_elsewhere(cmd, skip_index)
  cmd = tostring(cmd or "")
  for index, entry in ipairs(state.entries) do
    if index ~= skip_index and tostring(entry.cmd or "") == cmd then return true end
  end
  return false
end

local function choose_thumbnail()
  if not r.GetUserFileNameForRead then return nil end
  local ok, path = r.GetUserFileNameForRead("", "Choose thumbnail", "png;bmp;jpg;jpeg")
  if ok and path and path ~= "" then return path end
  return nil
end

local draw_capture_popup

local function draw_form_popup(app)
  local ctx = app.ctx
  local title = state.popup_mode == "edit" and "Edit Script" or "Add Script"
  if not r.ImGui_BeginPopupModal(ctx, title, true, r.ImGui_WindowFlags_AlwaysAutoResize()) then return end
  local changed, value
  changed, value = r.ImGui_InputText(ctx, "Name", state.form_name or "")
  if changed then state.form_name = value end
  changed, value = r.ImGui_InputText(ctx, "Command ID", state.form_cmd or "")
  if changed then state.form_cmd = value end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "Paste##script_launcher_paste") and r.CF_GetClipboard then
    local clip = r.CF_GetClipboard("")
    if clip and clip ~= "" then
      state.form_cmd = clip:match("^%s*(.-)%s*$")
      local command_id = resolve_command(state.form_cmd)
      local text = command_id and command_text(command_id) or nil
      if state.form_name == "" and text then state.form_name = text end
    end
  end
  changed, value = r.ImGui_InputText(ctx, "Thumbnail", state.form_thumb or "")
  if changed then state.form_thumb = value end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "Choose##script_launcher_thumb") then
    local path = choose_thumbnail()
    if path then state.form_thumb = path end
  end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "Capture Window##script_launcher_capture") then
    local windows = get_visible_windows()
    if windows == nil then
      app.status = "Capture requires js_ReaScriptAPI"
    else
      state.capture_window_list = windows
      state.capture_target_name = state.form_name ~= "" and state.form_name or state.form_cmd
      r.ImGui_OpenPopup(ctx, "SelectCaptureWindow")
      if #windows == 0 then
        app.status = "No visible windows found to capture"
      end
    end
  end
  changed, value = r.ImGui_InputText(ctx, "Label", state.form_label or "")
  if changed then state.form_label = value end
  r.ImGui_SameLine(ctx)
  if r.ImGui_BeginCombo(ctx, "##script_launcher_label_pick", "", r.ImGui_ComboFlags_NoPreview()) then
    for _, label in ipairs(label_options()) do
      if r.ImGui_Selectable(ctx, label) then state.form_label = label end
    end
    r.ImGui_EndCombo(ctx)
  end
  r.ImGui_Separator(ctx)
  local cmd = tostring(state.form_cmd or ""):match("^%s*(.-)%s*$")
  local name = tostring(state.form_name or ""):match("^%s*(.-)%s*$")
  local can_save = cmd ~= "" and name ~= "" and not command_exists_elsewhere(cmd, state.edit_index)
  if not can_save and r.ImGui_BeginDisabled then r.ImGui_BeginDisabled(ctx, true) end
  local popup_button_w = UIScale.text_button_w(ctx, "Cancel", 70)
  if r.ImGui_Button(ctx, "Save##script_launcher_save", popup_button_w, 0) and can_save then
    if state.popup_mode == "edit" and state.edit_index and state.entries[state.edit_index] then
      local entry = state.entries[state.edit_index]
      entry.name = name
      entry.cmd = cmd
      entry.thumb = tostring(state.form_thumb or "")
      entry.label = tostring(state.form_label or ""):match("^%s*(.-)%s*$")
      entry.updated_at = now()
      app.status = "Updated launcher item"
    else
      state.entries[#state.entries + 1] = {
        id = "script_" .. tostring(now()) .. "_" .. tostring(#state.entries + 1),
        name = name,
        cmd = cmd,
        thumb = tostring(state.form_thumb or ""),
        label = tostring(state.form_label or ""):match("^%s*(.-)%s*$"),
        created_at = now(),
        updated_at = now()
      }
      app.status = "Added launcher item"
    end
    save_entries()
    state.dirty_filter = true
    r.ImGui_CloseCurrentPopup(ctx)
  end
  if not can_save and r.ImGui_EndDisabled then r.ImGui_EndDisabled(ctx) end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "Cancel##script_launcher_cancel", popup_button_w, 0) then r.ImGui_CloseCurrentPopup(ctx) end
  if state.popup_mode == "edit" then
    r.ImGui_SameLine(ctx)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), Theme.colors.danger)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), Theme.text_for_background(Theme.colors.danger, Theme.colors.text, nil, 4.5))
    if r.ImGui_Button(ctx, "Delete##script_launcher_delete", popup_button_w, 0) then
      if state.edit_index then table.remove(state.entries, state.edit_index) end
      save_entries()
      state.dirty_filter = true
      app.status = "Deleted launcher item"
      r.ImGui_CloseCurrentPopup(ctx)
    end
    r.ImGui_PopStyleColor(ctx, 2)
  end
  if not can_save then
    r.ImGui_TextColored(ctx, Theme.colors.warning, command_exists_elsewhere(cmd, state.edit_index) and "Command already exists" or "Name and command are required")
  end
  if draw_capture_popup then draw_capture_popup(app) end
  r.ImGui_EndPopup(ctx)
end

draw_capture_popup = function(app)
  local ctx = app.ctx
  if not r.ImGui_BeginPopup(ctx, "SelectCaptureWindow") then return end
  r.ImGui_Text(ctx, "Select window to capture")
  r.ImGui_Separator(ctx)
  if #state.capture_window_list == 0 then
    r.ImGui_Text(ctx, "(no visible windows found)")
  else
    for index, win in ipairs(state.capture_window_list) do
      if r.ImGui_Selectable(ctx, tostring(win.title or "") .. "##script_launcher_cap_" .. tostring(index)) then
        local target_name = state.capture_target_name ~= "" and state.capture_target_name or tostring(win.title or "")
        local path = capture_window_screenshot(win.hwnd, target_name)
        if path then
          state.form_thumb = path
          clear_image_cache()
          app.status = "Screenshot captured"
        else
          app.status = "Screenshot capture failed"
        end
        r.ImGui_CloseCurrentPopup(ctx)
      end
    end
  end
  r.ImGui_Separator(ctx)
  if r.ImGui_Button(ctx, "Refresh##script_launcher_cap_refresh") then
    local windows = get_visible_windows()
    state.capture_window_list = windows or {}
  end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "Cancel##script_launcher_cap_cancel") then
    r.ImGui_CloseCurrentPopup(ctx)
  end
  r.ImGui_EndPopup(ctx)
end

local function draw_entry_card(app, item, width, height)
  local ctx = app.ctx
  local entry = item.entry
  local x, y = r.ImGui_GetCursorScreenPos(ctx)
  local clicked = r.ImGui_InvisibleButton(ctx, "##script_card", width, height)
  local hovered = r.ImGui_IsItemHovered(ctx)
  local draw_list = r.ImGui_GetWindowDrawList(ctx)
  local bg = hovered and Theme.colors.header_hover or Theme.colors.frame_bg
  r.ImGui_DrawList_AddRectFilled(draw_list, x, y, x + width, y + height, bg, UIScale.px(4))
  r.ImGui_DrawList_AddRect(draw_list, x, y, x + width, y + height, Theme.colors.border, UIScale.px(4), 0, UIScale.px(1))
  local image_h = math.max(UIScale.round(28), height - UIScale.round(28))
  local texture = load_texture(ctx, entry.thumb)
  if texture and r.ImGui_DrawList_AddImage then
    local ok_size, image_w, image_h_source = pcall(r.ImGui_Image_GetSize, texture)
    if ok_size and image_w and image_h_source and image_w > 0 and image_h_source > 0 then
      local inset = UIScale.round(8)
      local inner_w = width - inset * 2
      local inner_h = image_h - inset * 2
      local scale = math.min(inner_w / image_w, inner_h / image_h_source)
      local draw_w = image_w * scale
      local draw_h = image_h_source * scale
      local draw_x = x + inset + (inner_w - draw_w) * 0.5
      local draw_y = y + inset + (inner_h - draw_h) * 0.5
      r.ImGui_DrawList_AddImage(draw_list, texture, draw_x, draw_y, draw_x + draw_w, draw_y + draw_h, 0, 0, 1, 1, 0xFFFFFFFF)
    end
  else
    local command_id = resolve_command(entry.cmd)
    local mark = command_id and "RUN" or "MISS"
    local tw = r.ImGui_CalcTextSize(ctx, mark)
    r.ImGui_DrawList_AddText(draw_list, x + (width - tw) * 0.5, y + (image_h - r.ImGui_GetTextLineHeight(ctx)) * 0.5, command_id and Theme.colors.accent or Theme.colors.warning, mark)
  end
  local label = tostring(entry.name or entry.cmd)
  r.ImGui_DrawList_PushClipRect(draw_list, x + UIScale.round(6), y + image_h + UIScale.round(3), x + width - UIScale.round(6), y + height - UIScale.round(3), true)
  r.ImGui_DrawList_AddText(draw_list, x + UIScale.round(6), y + image_h + UIScale.round(4), Theme.colors.text, label)
  r.ImGui_DrawList_PopClipRect(draw_list)
  if clicked then execute_entry(app, entry) end
  if r.ImGui_BeginPopupContextItem(ctx, "##script_launcher_tile_ctx") then
    if r.ImGui_Selectable(ctx, "Edit") then
      state.pending_edit_index = item.index
      r.ImGui_CloseCurrentPopup(ctx)
    end
    if r.ImGui_Selectable(ctx, "Delete") then
      table.remove(state.entries, item.index)
      save_entries()
      state.dirty_filter = true
      app.status = "Deleted launcher item"
      r.ImGui_CloseCurrentPopup(ctx)
    end
    r.ImGui_EndPopup(ctx)
  end
  if hovered then r.ImGui_SetTooltip(ctx, tostring(entry.cmd or "")) end
end

local function draw_grid(app, settings, items, width)
  local ctx = app.ctx
  local spacing = UIScale.round(8)
  local min_card_w = UIScale.round(150)
  local columns = math.max(1, math.floor((width + spacing) / (min_card_w + spacing)))
  local card_w = (width - spacing * (columns - 1)) / columns
  local card_h = math.floor(card_w * 0.72) + UIScale.round(28)
  local index = 1
  while index <= #items do
    local row_columns = math.min(columns, #items - index + 1)
    for column = 1, row_columns do
      local item = items[index]
      r.ImGui_PushID(ctx, "script_launcher_" .. tostring(item.index))
      local card_ok, card_err = pcall(draw_entry_card, app, item, card_w, card_h)
      r.ImGui_PopID(ctx)
      if not card_ok then error(card_err) end
      if column < row_columns then r.ImGui_SameLine(ctx, 0, spacing) end
      index = index + 1
    end
  end
end

local function grouped_items(items)
  local groups = {}
  local order = {}
  for _, item in ipairs(items) do
    local label = tostring(item.entry.label or "")
    if label == "" then label = "No Label" end
    if not groups[label] then
      groups[label] = {}
      order[#order + 1] = label
    end
    groups[label][#groups[label] + 1] = item
  end
  table.sort(order, function(left, right)
    if left == "No Label" then return false end
    if right == "No Label" then return true end
    return left:lower() < right:lower()
  end)
  return groups, order
end

function M.add_entry(app, action)
  if not state.loaded then load_entries(app) end
  local command_id = action and action.id
  local command = tostring(command_id or "")
  if command == "" then return false end
  if command_exists_elsewhere(command, nil) then
    app.status = "Already in Script Launcher"
    return false
  end
  local name = tostring(action.name or command)
  state.entries[#state.entries + 1] = { id = "script_" .. tostring(now()) .. "_" .. tostring(#state.entries + 1), name = name, cmd = command, thumb = "", label = "", created_at = now(), updated_at = now() }
  save_entries()
  state.dirty_filter = true
  app.status = "Added to Script Launcher: " .. name
  return true
end

function M.init(app)
  ensure_settings(app)
  load_entries(app)
end

function M.draw(app)
  local ctx = app.ctx
  local settings = ensure_settings(app)
  if not state.loaded then load_entries(app) end
  local avail_w, avail_h = r.ImGui_GetContentRegionAvail(ctx)
  local button_h = UIScale.button_h(ctx)
  if r.ImGui_Button(ctx, "+##script_launcher_add", button_h, button_h) then
    begin_form("add", nil, nil)
    r.ImGui_OpenPopup(ctx, "Add Script")
  end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Add script/action") end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "R##script_launcher_refresh", button_h, button_h) then
    clear_image_cache()
    load_entries(app)
    app.status = "Script Launcher reloaded"
  end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Reload launcher") end
  r.ImGui_SameLine(ctx)
  local labels_active = settings.show_labels ~= false
  if not labels_active then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x555555FF) end
  local labels_w = UIScale.text_button_w(ctx, "Labels", 58)
  if r.ImGui_Button(ctx, "Labels##script_launcher_labels", labels_w, button_h) then
    settings.show_labels = not labels_active
    if app.save_settings then app.save_settings() end
  end
  if not labels_active then r.ImGui_PopStyleColor(ctx) end
  r.ImGui_SameLine(ctx)
  local search_w = math.max(UIScale.round(80), (avail_w or UIScale.round(320)) - button_h * 2 - labels_w - UIScale.round(32))
  r.ImGui_SetNextItemWidth(ctx, search_w)
  local search_changed, search = r.ImGui_InputTextWithHint(ctx, "##script_launcher_search", "Search scripts", settings.search_term or "")
  if search_changed then settings.search_term = search; state.dirty_filter = true; if app.save_settings then app.save_settings() end end
  if state.pending_edit_index and state.entries[state.pending_edit_index] then
    begin_form("edit", state.pending_edit_index, state.entries[state.pending_edit_index])
    state.pending_edit_index = nil
    r.ImGui_OpenPopup(ctx, "Edit Script")
  elseif state.pending_edit_index then
    state.pending_edit_index = nil
  end
  draw_form_popup(app)
  process_texture_load_queue(ctx, settings)
  trim_image_cache(settings)
  refresh_filter(settings)
  local info_h = UI.info_line_height(ctx)
  local list_h = math.max(UIScale.round(80), (avail_h or UIScale.round(300)) - button_h - info_h)
  local list_visible = r.ImGui_BeginChild(ctx, "##script_launcher_list", 0, list_h, 0)
  local list_ok = true
  local list_err = nil
  if list_visible then
    list_ok, list_err = pcall(function()
      if #state.entries == 0 then
        r.ImGui_TextColored(ctx, Theme.colors.text_dim, "No launcher items yet.")
      elseif #state.filtered == 0 then
        r.ImGui_TextColored(ctx, Theme.colors.text_dim, "No matching launcher items.")
      elseif settings.show_labels ~= false then
        local groups, order = grouped_items(state.filtered)
        for _, label in ipairs(order) do
          r.ImGui_TextColored(ctx, Theme.colors.text_dim, label)
          r.ImGui_Separator(ctx)
          draw_grid(app, settings, groups[label], math.max(UIScale.round(80), avail_w or UIScale.round(320)))
          r.ImGui_Spacing(ctx)
        end
      else
        draw_grid(app, settings, state.filtered, math.max(UIScale.round(80), avail_w or UIScale.round(320)))
      end
    end)
  end
  r.ImGui_EndChild(ctx)
  if not list_ok then error(list_err) end
  UI.draw_info_line(ctx, tostring(#state.entries) .. " launcher items | standalone Workbench data")
end

function M.shutdown()
  clear_image_cache()
end

return M