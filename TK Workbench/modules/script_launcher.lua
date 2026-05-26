local r = reaper
local Theme = require("core.theme")
local UI = require("core.ui")
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
  sort_mode = "name"
}

local state = {
  entries = {},
  filtered = {},
  data_path = "",
  image_cache = {},
  loaded = false,
  dirty_filter = true,
  edit_index = nil,
  popup_mode = nil,
  form_name = "",
  form_cmd = "",
  form_thumb = "",
  form_label = ""
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
end

local function load_texture(ctx, path)
  if not path or path == "" or not file_exists(path) or not r.ImGui_CreateImage then return nil end
  local cached = state.image_cache[path]
  if cached then return cached.texture end
  local ok, texture = pcall(r.ImGui_CreateImage, path)
  if not ok or not texture then return nil end
  if r.ImGui_Attach then pcall(r.ImGui_Attach, ctx, texture) end
  state.image_cache[path] = { texture = texture }
  return texture
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
  if r.ImGui_Button(ctx, "Save##script_launcher_save", 70, 0) and can_save then
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
  if r.ImGui_Button(ctx, "Cancel##script_launcher_cancel", 70, 0) then r.ImGui_CloseCurrentPopup(ctx) end
  if state.popup_mode == "edit" then
    r.ImGui_SameLine(ctx)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), Theme.colors.danger)
    if r.ImGui_Button(ctx, "Delete##script_launcher_delete", 70, 0) then
      if state.edit_index then table.remove(state.entries, state.edit_index) end
      save_entries()
      state.dirty_filter = true
      app.status = "Deleted launcher item"
      r.ImGui_CloseCurrentPopup(ctx)
    end
    r.ImGui_PopStyleColor(ctx)
  end
  if not can_save then
    r.ImGui_TextColored(ctx, Theme.colors.warning, command_exists_elsewhere(cmd, state.edit_index) and "Command already exists" or "Name and command are required")
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
  r.ImGui_DrawList_AddRectFilled(draw_list, x, y, x + width, y + height, bg, 4)
  r.ImGui_DrawList_AddRect(draw_list, x, y, x + width, y + height, Theme.colors.border, 4, 0, 1)
  local image_h = math.max(28, height - 28)
  local texture = load_texture(ctx, entry.thumb)
  if texture and r.ImGui_DrawList_AddImage then
    local ok_size, image_w, image_h_source = pcall(r.ImGui_Image_GetSize, texture)
    if ok_size and image_w and image_h_source and image_w > 0 and image_h_source > 0 then
      local inset = 8
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
  r.ImGui_DrawList_PushClipRect(draw_list, x + 6, y + image_h + 3, x + width - 6, y + height - 3, true)
  r.ImGui_DrawList_AddText(draw_list, x + 6, y + image_h + 4, Theme.colors.text, label)
  r.ImGui_DrawList_PopClipRect(draw_list)
  if clicked then execute_entry(app, entry) end
  if r.ImGui_IsItemClicked(ctx, 1) then
    begin_form("edit", item.index, entry)
    r.ImGui_OpenPopup(ctx, "Edit Script")
  end
  if hovered then r.ImGui_SetTooltip(ctx, tostring(entry.cmd or "")) end
end

local function draw_grid(app, settings, items, width)
  local ctx = app.ctx
  local spacing = 8
  local min_card_w = 150
  local max_card_w = 220
  local columns = math.max(1, math.floor((width + spacing) / (min_card_w + spacing)))
  local card_w = math.min(max_card_w, math.floor((width - spacing * (columns - 1)) / columns))
  local card_h = math.floor(card_w * 0.72) + 28
  local row_start_x = select(1, r.ImGui_GetCursorScreenPos(ctx))
  for index, item in ipairs(items) do
    r.ImGui_PushID(ctx, "script_launcher_" .. tostring(item.index))
    local card_ok, card_err = pcall(draw_entry_card, app, item, card_w, card_h)
    r.ImGui_PopID(ctx)
    if not card_ok then error(card_err) end
    local max_x = select(1, r.ImGui_GetItemRectMax(ctx))
    if index < #items and max_x + spacing + card_w <= row_start_x + width then r.ImGui_SameLine(ctx, 0, spacing) end
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
  local button_h = r.ImGui_GetFrameHeight(ctx)
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
  if r.ImGui_Button(ctx, "Labels##script_launcher_labels", 58, button_h) then
    settings.show_labels = not labels_active
    if app.save_settings then app.save_settings() end
  end
  if not labels_active then r.ImGui_PopStyleColor(ctx) end
  r.ImGui_SameLine(ctx)
  local search_w = math.max(80, (avail_w or 320) - button_h * 2 - 58 - 32)
  r.ImGui_SetNextItemWidth(ctx, search_w)
  local search_changed, search = r.ImGui_InputTextWithHint(ctx, "##script_launcher_search", "Search scripts", settings.search_term or "")
  if search_changed then settings.search_term = search; state.dirty_filter = true; if app.save_settings then app.save_settings() end end
  draw_form_popup(app)
  refresh_filter(settings)
  local info_h = UI.info_line_height(ctx)
  local list_h = math.max(80, (avail_h or 300) - button_h - info_h)
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
          draw_grid(app, settings, groups[label], math.max(80, avail_w or 320))
          r.ImGui_Spacing(ctx)
        end
      else
        draw_grid(app, settings, state.filtered, math.max(80, avail_w or 320))
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