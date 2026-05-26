local r = reaper
local Theme = require("core.theme")
local UI = require("core.ui")
local json = require("core.json")

local M = {
  id = "notes",
  title = "Notes",
  icon = "NOT",
  version = "0.1.0"
}

local EXT_NAMESPACE = "TK_WORKBENCH_NOTES"
local DEFAULT_NOTE_COLOR = 0x2A303AFF
local DEFAULT_TEXT_COLOR = 0xE6EDF3FF
local DEFAULT_FONT_SIZE = 14
local DEFAULT_FONT_FAMILY = "sans-serif"

local FONT_FAMILIES = {
  "sans-serif",
  "serif",
  "monospace",
  "cursive",
  "Arial",
  "Courier New",
  "Times New Roman",
  "Verdana",
  "Georgia",
  "Comic Sans MS"
}

local TEXT_COLOR_PRESETS = {
  { name = "White", color = 0xFFFFFFFF },
  { name = "Black", color = 0x000000FF },
  { name = "Red", color = 0xFF4444FF },
  { name = "Orange", color = 0xFF9933FF },
  { name = "Yellow", color = 0xFFDD33FF },
  { name = "Green", color = 0x44CC66FF },
  { name = "Cyan", color = 0x44BBDDFF },
  { name = "Blue", color = 0x5588EEFF },
  { name = "Purple", color = 0xAA55DDFF },
  { name = "Pink", color = 0xFF66AAFF },
  { name = "Gray", color = 0x999999FF },
  { name = "Brown", color = 0xAA7744FF }
}

local defaults = {
  active_context = "project",
  auto_context = true,
  auto_save_interval = 1.0,
  show_empty_contexts = true,
  block_height = 120
}

local MIN_BLOCK_HEIGHT = 70
local MAX_BLOCK_HEIGHT = 1200
local MIN_FONT_SIZE = 10
local MAX_FONT_SIZE = 32

local LIST_MODES = { none = true, bullet = true, numbered = true, checkbox = true }
local NOTE_STATUS_MESSAGES = { ["Could not save notes"] = true, ["Notes saved"] = true }

local state = {
  context_id = nil,
  context_info = nil,
  blocks = {},
  dirty = false,
  last_edit_time = 0,
  next_id = 1,
  loaded = false,
  font_cache = {}
}

local function copy_default(value)
  if type(value) ~= "table" then return value end
  local target = {}
  for key, child in pairs(value) do target[key] = copy_default(child) end
  return target
end

local function ensure_settings(app)
  app.settings.notes = app.settings.notes or {}
  local settings = app.settings.notes
  local changed = false
  for key, value in pairs(defaults) do
    if settings[key] == nil then
      settings[key] = copy_default(value)
      changed = true
    end
  end
  if settings.active_context ~= "global" and settings.active_context ~= "project" and settings.active_context ~= "track" and settings.active_context ~= "item" then settings.active_context = "project" end
  settings.auto_save_interval = math.max(0.2, math.min(10, tonumber(settings.auto_save_interval) or defaults.auto_save_interval))
  settings.block_height = math.max(70, math.min(260, tonumber(settings.block_height) or defaults.block_height))
  if changed and app.save_settings then app.save_settings() end
  return settings
end

local function now()
  return r.time_precise and r.time_precise() or os.clock()
end

local function clear_note_status(app)
  if app and NOTE_STATUS_MESSAGES[app.status] then app.status = "Ready" end
end

local function native_color_to_u32(native, alpha)
  native = tonumber(native) or 0
  if native == 0 then return nil end
  alpha = alpha or 0x66
  if r.ColorFromNative then
    local ok, red, green, blue = pcall(r.ColorFromNative, native & 0xFFFFFF)
    if ok and red and green and blue then return ((red & 0xFF) << 24) | ((green & 0xFF) << 16) | ((blue & 0xFF) << 8) | (alpha & 0xFF) end
  end
  local red = native & 0xFF
  local green = (native >> 8) & 0xFF
  local blue = (native >> 16) & 0xFF
  return (red << 24) | (green << 16) | (blue << 8) | (alpha & 0xFF)
end

local function track_color(track)
  if not track or not r.GetTrackColor then return nil end
  return native_color_to_u32(r.GetTrackColor(track), 0x66)
end

local function item_color(item)
  if not item then return nil end
  if r.GetDisplayedMediaItemColor then return native_color_to_u32(r.GetDisplayedMediaItemColor(item), 0x66) end
  return native_color_to_u32(r.GetMediaItemInfo_Value(item, "I_CUSTOMCOLOR"), 0x66)
end

local function read_proj_ext_state(project, key)
  if r.GetSetProjExtState then
    local _, value = r.GetSetProjExtState(project or 0, EXT_NAMESPACE, key, "")
    return value or ""
  end
  if r.GetProjExtState then
    local ok, value = r.GetProjExtState(project or 0, EXT_NAMESPACE, key)
    if (ok == true or ok == 1) and value then return value end
  end
  return ""
end

local function write_proj_ext_state(project, key, value)
  if r.GetSetProjExtState then
    r.GetSetProjExtState(project or 0, EXT_NAMESPACE, key, value or "")
    return true
  end
  if r.SetProjExtState then
    local ok = r.SetProjExtState(project or 0, EXT_NAMESPACE, key, value or "")
    return ok == true or ok == 1
  end
  return false
end

local function read_ext_state(key)
  if r.HasExtState and r.HasExtState(EXT_NAMESPACE, key) then return r.GetExtState(EXT_NAMESPACE, key) or "" end
  return ""
end

local function write_ext_state(key, value)
  r.SetExtState(EXT_NAMESPACE, key, value or "", true)
  return true
end

local function project_label(selection)
  local project = selection.project or {}
  return project.name or "Project Notes"
end

local function track_label(selection)
  local track = selection.track
  if not track then return "No track selected" end
  return string.format("%02d - %s", track.index or 0, track.name or "Track")
end

local function item_label(selection)
  local item = selection.item
  if not item then return "No item selected" end
  return item.take_name or "Item"
end

local function resolve_context(app, settings)
  local selection = app.selection or {}
  local project = selection.project and selection.project.pointer or 0
  local context = settings.active_context or "project"
  if settings.auto_context then
    if selection.item and selection.item.pointer and r.BR_GetMediaItemGUID then
      context = "item"
    elseif selection.track and selection.track.pointer then
      context = "track"
    else
      context = "project"
    end
  end
  if context == "global" then
    return { id = "global|GLOBAL", storage = "global", key = "GLOBAL::blocks", label = "Global Notes", can_edit = true, kind = "global" }
  end
  if context == "project" then
    return { id = "project|PROJECT", storage = "project", project = project, key = "PROJECT::blocks", label = project_label(selection), can_edit = true, kind = "project" }
  end
  if context == "track" then
    local track = selection.track and selection.track.pointer or nil
    local guid = track and r.GetTrackGUID and r.GetTrackGUID(track) or nil
    if not guid or guid == "" then return { id = "track|none", storage = "project", project = project, key = "", label = "No track selected", can_edit = false, kind = "track" } end
    return { id = "track|" .. guid, storage = "project", project = project, key = guid .. "::blocks", label = track_label(selection), can_edit = true, kind = "track", track = track, context_color = track_color(track) }
  end
  if context == "item" then
    if not r.BR_GetMediaItemGUID then return { id = "item|nosws", storage = "project", project = project, key = "", label = "SWS required for item notes", can_edit = false, kind = "item" } end
    local item = selection.item and selection.item.pointer or nil
    local guid = item and r.BR_GetMediaItemGUID(item) or nil
    if not guid or guid == "" then return { id = "item|none", storage = "project", project = project, key = "", label = "No item selected", can_edit = false, kind = "item" } end
    return { id = "item|" .. guid, storage = "project", project = project, key = "ITEM::" .. guid .. "::blocks", label = item_label(selection), can_edit = true, kind = "item", item = item, context_color = item_color(item) }
  end
  return { id = "project|PROJECT", storage = "project", project = project, key = "PROJECT::blocks", label = project_label(selection), can_edit = true, kind = "project" }
end

local function new_block(title, body)
  local id = "block_" .. tostring(state.next_id)
  state.next_id = state.next_id + 1
  local use_context_color = state.context_info and (state.context_info.kind == "track" or state.context_info.kind == "item") or false
  return { id = id, title = title or "Notes", body = body or "", collapsed = false, use_context_color = use_context_color, note_color = DEFAULT_NOTE_COLOR, text_color = DEFAULT_TEXT_COLOR, line_colors = {}, font_size = DEFAULT_FONT_SIZE, font_family = DEFAULT_FONT_FAMILY, list_mode = "none", checkbox_lines = {}, images = {}, height = defaults.block_height, created_at = os.time(), updated_at = os.time() }
end

local function normalize_color(value, fallback)
  value = tonumber(value)
  if not value then return fallback end
  return math.floor(value) & 0xFFFFFFFF
end

local function opaque_color(value, fallback)
  return (normalize_color(value, fallback) & 0xFFFFFF00) | 0xFF
end

local function normalize_font_size(value)
  return math.max(MIN_FONT_SIZE, math.min(MAX_FONT_SIZE, math.floor((tonumber(value) or DEFAULT_FONT_SIZE) + 0.5)))
end

local function normalize_font_family(value)
  value = tostring(value or DEFAULT_FONT_FAMILY)
  for _, family in ipairs(FONT_FAMILIES) do
    if value == family then return family end
  end
  return DEFAULT_FONT_FAMILY
end

local function normalize_list_mode(value)
  value = tostring(value or "none")
  return LIST_MODES[value] and value or "none"
end

local function normalize_line_colors(line_colors)
  local result = {}
  if type(line_colors) ~= "table" then return result end
  for key, value in pairs(line_colors) do
    local line = tonumber(key)
    if line and line >= 1 and tonumber(value) then result[math.floor(line)] = opaque_color(value, DEFAULT_TEXT_COLOR) end
  end
  return result
end

local function encode_line_colors(line_colors)
  local result = {}
  for line, color in pairs(normalize_line_colors(line_colors)) do result[tostring(line)] = opaque_color(color, DEFAULT_TEXT_COLOR) end
  return result
end

local function copy_line_colors(line_colors)
  local result = {}
  for line, color in pairs(normalize_line_colors(line_colors)) do result[line] = color end
  return result
end

local function normalize_checkbox_lines(lines)
  local result = {}
  if type(lines) ~= "table" then return result end
  for key, value in pairs(lines) do
    local line = tonumber(key)
    if line and line >= 1 and value == true then result[math.floor(line)] = true end
  end
  return result
end

local function encode_checkbox_lines(lines)
  local result = {}
  for line in pairs(normalize_checkbox_lines(lines)) do result[tostring(line)] = true end
  return result
end

local function copy_checkbox_lines(lines)
  local result = {}
  for line in pairs(normalize_checkbox_lines(lines)) do result[line] = true end
  return result
end

local function normalize_images(images)
  local result = {}
  if type(images) ~= "table" then return result end
  for _, image in ipairs(images) do
    if type(image) == "table" then
      local path = tostring(image.path or "")
      if path ~= "" then
        result[#result + 1] = {
          id = tonumber(image.id) or #result + 1,
          path = path,
          width = math.max(1, tonumber(image.width) or 150),
          height = math.max(1, tonumber(image.height) or 100),
          pos_x = math.max(0, tonumber(image.pos_x) or 10),
          pos_y = math.max(0, tonumber(image.pos_y) or 10),
          scale = math.max(10, math.min(200, math.floor((tonumber(image.scale) or 100) + 0.5)))
        }
      end
    end
  end
  return result
end

local function encode_images(images)
  local result = {}
  for _, image in ipairs(images or {}) do
    if type(image) == "table" and image.path and image.path ~= "" then
      result[#result + 1] = {
        id = tonumber(image.id) or #result + 1,
        path = tostring(image.path),
        width = math.max(1, tonumber(image.width) or 150),
        height = math.max(1, tonumber(image.height) or 100),
        pos_x = math.max(0, tonumber(image.pos_x) or 10),
        pos_y = math.max(0, tonumber(image.pos_y) or 10),
        scale = math.max(10, math.min(200, math.floor((tonumber(image.scale) or 100) + 0.5)))
      }
    end
  end
  return result
end

local function copy_images(images)
  return encode_images(images)
end

local function destroy_image_texture(image)
  if not image or not image.texture then return end
  if r.ImGui_DestroyImage then pcall(r.ImGui_DestroyImage, image.texture) end
  image.texture = nil
end

local function clear_block_images(block)
  if not block then return end
  for _, image in ipairs(block.images or {}) do destroy_image_texture(image) end
  block.images = {}
  block.selected_image_id = nil
end

local function release_blocks_images(blocks)
  for _, block in ipairs(blocks or {}) do
    for _, image in ipairs(block.images or {}) do destroy_image_texture(image) end
  end
end

local function prepare_block(block, info)
  if block.use_context_color == nil then block.use_context_color = info and (info.kind == "track" or info.kind == "item") or false end
  if tonumber(block.note_color) == nil then block.note_color = DEFAULT_NOTE_COLOR end
  if tonumber(block.text_color) == nil then block.text_color = DEFAULT_TEXT_COLOR end
  block.line_colors = normalize_line_colors(block.line_colors)
  block.font_size = normalize_font_size(block.font_size)
  block.font_family = normalize_font_family(block.font_family)
  block.list_mode = normalize_list_mode(block.list_mode)
  block.checkbox_lines = normalize_checkbox_lines(block.checkbox_lines)
  if type(block.images) ~= "table" then block.images = {} end
  block.height = math.max(MIN_BLOCK_HEIGHT, math.min(MAX_BLOCK_HEIGHT, tonumber(block.height) or defaults.block_height))
end

local function effective_note_color(block, info)
  if block.use_context_color and info and info.context_color then return info.context_color end
  return normalize_color(block.note_color, DEFAULT_NOTE_COLOR)
end

local function normalize_blocks(blocks)
  local result = {}
  if type(blocks) == "table" then
    for _, block in ipairs(blocks) do
      if type(block) == "table" then
        local clean = {
          id = tostring(block.id or "block_" .. tostring(state.next_id)),
          title = tostring(block.title or "Notes"),
          body = tostring(block.body or ""),
          collapsed = block.collapsed == true,
          use_context_color = block.use_context_color,
          note_color = normalize_color(block.note_color, DEFAULT_NOTE_COLOR),
          text_color = opaque_color(block.text_color, DEFAULT_TEXT_COLOR),
          line_colors = normalize_line_colors(block.line_colors),
          font_size = normalize_font_size(block.font_size),
          font_family = normalize_font_family(block.font_family),
          list_mode = normalize_list_mode(block.list_mode),
          checkbox_lines = normalize_checkbox_lines(block.checkbox_lines),
          images = normalize_images(block.images),
          height = math.max(MIN_BLOCK_HEIGHT, math.min(MAX_BLOCK_HEIGHT, tonumber(block.height) or defaults.block_height)),
          created_at = tonumber(block.created_at) or os.time(),
          updated_at = tonumber(block.updated_at) or os.time()
        }
        result[#result + 1] = clean
        local number = tonumber(clean.id:match("block_(%d+)"))
        if number and number >= state.next_id then state.next_id = number + 1 end
      end
    end
  end
  if #result == 0 then result[1] = new_block("Notes", "") end
  return result
end

local function read_blocks(info)
  if not info or not info.can_edit or info.key == "" then return { new_block("Notes", "") } end
  local raw = info.storage == "global" and read_ext_state(info.key) or read_proj_ext_state(info.project, info.key)
  if raw == "" then return { new_block("Notes", "") } end
  local ok, decoded = pcall(json.decode, raw)
  if not ok then return { new_block("Notes", "") } end
  return normalize_blocks(decoded)
end

local function write_blocks(info, blocks)
  if not info or not info.can_edit or info.key == "" then return false end
  local clean = {}
  for _, block in ipairs(blocks or {}) do
    clean[#clean + 1] = {
      id = tostring(block.id or "block"),
      title = tostring(block.title or "Notes"),
      body = tostring(block.body or ""),
      collapsed = block.collapsed == true,
      use_context_color = block.use_context_color == true,
      note_color = normalize_color(block.note_color, DEFAULT_NOTE_COLOR),
      text_color = opaque_color(block.text_color, DEFAULT_TEXT_COLOR),
      line_colors = encode_line_colors(block.line_colors),
      font_size = normalize_font_size(block.font_size),
      font_family = normalize_font_family(block.font_family),
      list_mode = normalize_list_mode(block.list_mode),
      checkbox_lines = encode_checkbox_lines(block.checkbox_lines),
      images = encode_images(block.images),
      height = math.max(MIN_BLOCK_HEIGHT, math.min(MAX_BLOCK_HEIGHT, tonumber(block.height) or defaults.block_height)),
      created_at = tonumber(block.created_at) or os.time(),
      updated_at = tonumber(block.updated_at) or os.time()
    }
  end
  local ok, encoded = pcall(json.encode, clean)
  if not ok or not encoded then return false end
  if info.storage == "global" then return write_ext_state(info.key, encoded) end
  return write_proj_ext_state(info.project, info.key, encoded)
end

local function save_current(app)
  if not state.dirty then clear_note_status(app); return true end
  if not write_blocks(state.context_info, state.blocks) then return false end
  state.dirty = false
  clear_note_status(app)
  return true
end

local function mark_dirty(block)
  if block then block.updated_at = os.time() end
  state.dirty = true
  state.last_edit_time = now()
end

local function load_context(app, info)
  save_current(app)
  release_blocks_images(state.blocks)
  state.context_id = info.id
  state.context_info = info
  state.blocks = read_blocks(info)
  state.dirty = false
  state.loaded = true
end

local function ensure_context(app)
  local settings = ensure_settings(app)
  local info = resolve_context(app, settings)
  if not state.loaded or state.context_id ~= info.id then load_context(app, info) else state.context_info = info end
  return settings, info
end

local function add_block()
  state.blocks[#state.blocks + 1] = new_block("Notes", "")
  mark_dirty(state.blocks[#state.blocks])
end

local function duplicate_block(index)
  local source = state.blocks[index]
  if not source then return end
  local block = new_block(source.title .. " Copy", source.body)
  block.collapsed = false
  block.height = source.height
  block.use_context_color = source.use_context_color
  block.note_color = source.note_color
  block.text_color = source.text_color
  block.line_colors = copy_line_colors(source.line_colors)
  block.font_size = normalize_font_size(source.font_size)
  block.font_family = normalize_font_family(source.font_family)
  block.list_mode = normalize_list_mode(source.list_mode)
  block.checkbox_lines = copy_checkbox_lines(source.checkbox_lines)
  block.images = copy_images(source.images)
  table.insert(state.blocks, index + 1, block)
  mark_dirty(block)
end

local function remove_block(index)
  if #state.blocks <= 1 then
    state.blocks[1].body = ""
    state.blocks[1].title = "Notes"
    state.blocks[1].collapsed = false
    state.blocks[1].line_colors = {}
    state.blocks[1].font_size = DEFAULT_FONT_SIZE
    state.blocks[1].font_family = DEFAULT_FONT_FAMILY
    state.blocks[1].list_mode = "none"
    state.blocks[1].checkbox_lines = {}
    clear_block_images(state.blocks[1])
    mark_dirty(state.blocks[1])
    return
  end
  clear_block_images(state.blocks[index])
  table.remove(state.blocks, index)
  mark_dirty()
end

local function context_button(ctx, app, settings, id, label, active, enabled, width)
  if enabled == false and r.ImGui_BeginDisabled then r.ImGui_BeginDisabled(ctx, true) end
  if active then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), Theme.colors.accent & 0xFFFFFFAA) end
  if r.ImGui_Button(ctx, label, width or 0, 0) then
    save_current(app)
    if id == "auto" then
      settings.auto_context = not settings.auto_context
    else
      settings.auto_context = false
      settings.active_context = id
    end
    state.loaded = false
    if app.save_settings then app.save_settings() end
  end
  if active then r.ImGui_PopStyleColor(ctx) end
  if enabled == false and r.ImGui_EndDisabled then r.ImGui_EndDisabled(ctx) end
end

local function draw_context_bar(app, settings, info, width)
  local ctx = app.ctx
  local gap = 4
  local button_w = math.max(48, ((width or 320) - gap * 4) / 5)
  context_button(ctx, app, settings, "auto", "Auto", settings.auto_context == true, true, button_w)
  r.ImGui_SameLine(ctx, 0, gap)
  context_button(ctx, app, settings, "global", "Global", settings.auto_context ~= true and settings.active_context == "global", true, button_w)
  r.ImGui_SameLine(ctx, 0, gap)
  context_button(ctx, app, settings, "project", "Project", info.kind == "project", true, button_w)
  r.ImGui_SameLine(ctx, 0, gap)
  context_button(ctx, app, settings, "track", "Track", info.kind == "track", true, button_w)
  r.ImGui_SameLine(ctx, 0, gap)
  context_button(ctx, app, settings, "item", "Item", info.kind == "item", r.BR_GetMediaItemGUID ~= nil, button_w)
end

local function info_text(settings, info)
  local mode = settings.auto_context and "Auto" or "Manual"
  local status = state.dirty and "unsaved" or "saved"
  local blocks = tostring(#state.blocks) .. " block" .. (#state.blocks == 1 and "" or "s")
  return mode .. " | " .. tostring(info.label or "Notes") .. " | " .. blocks .. " | " .. status
end

local function push_note_style(ctx, note_color, text_color)
  local count = 0
  if r.ImGui_Col_FrameBg then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), note_color); count = count + 1 end
  if r.ImGui_Col_FrameBgHovered then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgHovered(), note_color); count = count + 1 end
  if r.ImGui_Col_FrameBgActive then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgActive(), note_color); count = count + 1 end
  if r.ImGui_Col_Text then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), text_color); count = count + 1 end
  return count
end

local function pop_note_style(ctx, count)
  if count and count > 0 then r.ImGui_PopStyleColor(ctx, count) end
end

local function draw_color_popup(ctx, block, info)
  if not r.ImGui_BeginPopup(ctx, "##note_colors") then return end
  local changed = false
  if info and (info.kind == "track" or info.kind == "item") then
    local c, value = r.ImGui_Checkbox(ctx, "Use context color", block.use_context_color == true)
    if c then block.use_context_color = value; changed = true end
  end
  local flags = r.ImGui_ColorEditFlags_NoInputs and r.ImGui_ColorEditFlags_NoInputs() or 0
  local disabled = block.use_context_color == true and info and info.context_color ~= nil
  if disabled and r.ImGui_BeginDisabled then r.ImGui_BeginDisabled(ctx, true) end
  local c, value = r.ImGui_ColorEdit4(ctx, "Note", block.note_color or DEFAULT_NOTE_COLOR, flags)
  if c then block.note_color = value; block.use_context_color = false; changed = true end
  if disabled and r.ImGui_EndDisabled then r.ImGui_EndDisabled(ctx) end
  local text_color = opaque_color(block.text_color, DEFAULT_TEXT_COLOR)
  c, value = r.ImGui_ColorEdit4(ctx, "Text", text_color, flags)
  if c then block.text_color = opaque_color(value, DEFAULT_TEXT_COLOR); changed = true end
  if changed then mark_dirty(block) end
  r.ImGui_EndPopup(ctx)
end

local function draw_font_size_popup(ctx, block)
  if not r.ImGui_BeginPopup(ctx, "##font_size") then return end
  local value = normalize_font_size(block.font_size)
  local family = normalize_font_family(block.font_family)
  local changed = false
  if r.ImGui_Button(ctx, "-", 24, 0) then value = normalize_font_size(value - 1); changed = true end
  r.ImGui_SameLine(ctx)
  r.ImGui_SetNextItemWidth(ctx, 120)
  local slider_changed, slider_value = r.ImGui_SliderInt(ctx, "##font_size_slider", value, MIN_FONT_SIZE, MAX_FONT_SIZE, "%d px")
  if slider_changed then value = normalize_font_size(slider_value); changed = true end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "+", 24, 0) then value = normalize_font_size(value + 1); changed = true end
  r.ImGui_Separator(ctx)
  r.ImGui_Text(ctx, "Font")
  for _, option in ipairs(FONT_FAMILIES) do
    if r.ImGui_MenuItem(ctx, option, nil, option == family) then family = option; changed = true end
  end
  r.ImGui_Separator(ctx)
  if r.ImGui_MenuItem(ctx, "Reset", nil, false, value ~= DEFAULT_FONT_SIZE or family ~= DEFAULT_FONT_FAMILY) then value = DEFAULT_FONT_SIZE; family = DEFAULT_FONT_FAMILY; changed = true end
  if changed then block.font_size = value; block.font_family = family; mark_dirty(block) end
  r.ImGui_EndPopup(ctx)
end

local function clamp_caret(text, caret)
  caret = tonumber(caret) or 0
  if caret < 0 then return 0 end
  local length = #(text or "")
  if caret > length then return length end
  return caret
end

local function ensure_body_editor(block)
  block.editor = block.editor or { caret = #(block.body or ""), active = false, preferred_x = nil, selection_start = #(block.body or ""), selection_end = #(block.body or ""), selection_anchor = #(block.body or ""), mouse_selecting = false }
  block.editor.caret = clamp_caret(block.body or "", block.editor.caret)
  block.editor.selection_start = clamp_caret(block.body or "", block.editor.selection_start or block.editor.caret)
  block.editor.selection_end = clamp_caret(block.body or "", block.editor.selection_end or block.editor.caret)
  block.editor.selection_anchor = clamp_caret(block.body or "", block.editor.selection_anchor or block.editor.caret)
  return block.editor
end

local function clear_selection(editor, caret)
  caret = caret or editor.caret or 0
  editor.selection_start = caret
  editor.selection_end = caret
  editor.selection_anchor = caret
end

local function selection_range(editor)
  if not editor or editor.selection_start == editor.selection_end then return nil end
  local start_pos = editor.selection_start or 0
  local end_pos = editor.selection_end or start_pos
  if end_pos < start_pos then start_pos, end_pos = end_pos, start_pos end
  return start_pos, end_pos
end

local function selected_text(text, editor)
  local start_pos, end_pos = selection_range(editor)
  if not start_pos or end_pos <= start_pos then return nil end
  return text:sub(start_pos + 1, end_pos)
end

local function delete_selection(text, editor)
  local start_pos, end_pos = selection_range(editor)
  if not start_pos then return text, editor.caret or 0, false end
  local new_text = (start_pos > 0 and text:sub(1, start_pos) or "") .. text:sub(end_pos + 1)
  editor.caret = start_pos
  clear_selection(editor, start_pos)
  return new_text, start_pos, true
end

local function bold_candidate(text, editor)
  text = tostring(text or "")
  local start_pos, end_pos = selection_range(editor)
  if not start_pos then
    local caret = clamp_caret(text, editor.caret or 0)
    local new_text = (caret > 0 and text:sub(1, caret) or "") .. "****" .. text:sub(caret + 1)
    return new_text, caret + 2, caret + 2, caret + 2
  end
  local selected = text:sub(start_pos + 1, end_pos)
  if #selected >= 4 and selected:sub(1, 2) == "**" and selected:sub(-2) == "**" then
    local inner = selected:sub(3, -3)
    local new_text = (start_pos > 0 and text:sub(1, start_pos) or "") .. inner .. text:sub(end_pos + 1)
    return new_text, start_pos + #inner, start_pos, start_pos + #inner
  end
  if start_pos >= 2 and end_pos + 2 <= #text and text:sub(start_pos - 1, start_pos) == "**" and text:sub(end_pos + 1, end_pos + 2) == "**" then
    local new_text = text:sub(1, start_pos - 2) .. selected .. text:sub(end_pos + 3)
    return new_text, end_pos - 2, start_pos - 2, end_pos - 2
  end
  local new_text = (start_pos > 0 and text:sub(1, start_pos) or "") .. "**" .. selected .. "**" .. text:sub(end_pos + 1)
  return new_text, end_pos + 2, start_pos + 2, end_pos + 2
end

local function build_bold_lookup(text)
  local lookup = {}
  local active = false
  local index = 1
  text = tostring(text or "")
  while index <= #text do
    if index < #text and text:sub(index, index + 1) == "**" then
      active = not active
      index = index + 2
    else
      local next_index = utf8.offset(text, 2, index) or (#text + 1)
      if active then
        for pos = index, next_index - 1 do lookup[pos] = true end
      end
      index = next_index
    end
  end
  return lookup
end

local function set_clipboard(ctx, text)
  if not text or text == "" then return end
  if r.ImGui_SetClipboardText then
    local ok = pcall(r.ImGui_SetClipboardText, ctx, text)
    if ok then return end
  end
  if r.CF_SetClipboard then pcall(r.CF_SetClipboard, text) end
end

local function get_clipboard(ctx)
  if r.ImGui_GetClipboardText then
    local ok, value = pcall(r.ImGui_GetClipboardText, ctx)
    if ok and value then return value end
  end
  if r.CF_GetClipboard then
    local ok, value = pcall(r.CF_GetClipboard)
    if ok and value then return value end
  end
  return ""
end

local function insert_at(text, caret, value)
  local prefix = caret > 0 and text:sub(1, caret) or ""
  local suffix = text:sub(caret + 1)
  return prefix .. value .. suffix, caret + #value
end

local function trim_blank_tail_for_input(text, caret, value)
  if not value or value:match("^%s*$") then return text, caret end
  text = tostring(text or "")
  caret = clamp_caret(text, caret)
  local prefix = caret > 0 and text:sub(1, caret) or ""
  local suffix = text:sub(caret + 1)
  if suffix:match("^%s*$") and suffix:find("[\r\n]") then suffix = "" end
  return prefix .. suffix, caret
end

local function delete_previous(text, caret)
  if caret <= 0 then return text, caret end
  local start_pos = utf8.offset(text, -1, caret + 1) or caret
  return text:sub(1, start_pos - 1) .. text:sub(caret + 1), math.max(0, start_pos - 1)
end

local function delete_next(text, caret)
  local start_pos = utf8.offset(text, 1, caret + 1)
  if not start_pos then return text, caret end
  local end_pos = utf8.offset(text, 2, caret + 1) or (#text + 1)
  return text:sub(1, start_pos - 1) .. text:sub(end_pos), caret
end

local function move_left(text, caret)
  if caret <= 0 then return 0 end
  local start_pos = utf8.offset(text, -1, caret + 1)
  return start_pos and (start_pos - 1) or math.max(0, caret - 1)
end

local function move_right(text, caret)
  if caret >= #text then return #text end
  local end_pos = utf8.offset(text, 2, caret + 1)
  return end_pos and (end_pos - 1) or #text
end

local function count_newlines(value)
  local count = 0
  for _ in tostring(value or ""):gmatch("\n") do count = count + 1 end
  return count
end

local function get_source_line_from_byte(text, byte_pos)
  text = tostring(text or "")
  byte_pos = tonumber(byte_pos) or 0
  if byte_pos <= 0 then return 1 end
  local count = 1
  for index = 1, math.min(byte_pos, #text) do
    if text:byte(index) == 10 then count = count + 1 end
  end
  return count
end

local function count_source_lines(text)
  return get_source_line_from_byte(text, #(text or ""))
end

local function selected_line_range(text, editor)
  local start_pos, end_pos = selection_range(editor)
  if not start_pos then
    local line = get_source_line_from_byte(text, editor and editor.caret or 0)
    return line, line
  end
  local end_byte = math.max(start_pos, end_pos - 1)
  return get_source_line_from_byte(text, start_pos), get_source_line_from_byte(text, end_byte)
end

local function shift_line_colors(line_colors, from_line, delta)
  if type(line_colors) ~= "table" or delta == 0 then return end
  local shifted = {}
  for line, color in pairs(line_colors) do
    if line >= from_line then
      local new_line = line + delta
      if new_line >= 1 then shifted[new_line] = color end
    else
      shifted[line] = color
    end
  end
  for line in pairs(line_colors) do line_colors[line] = nil end
  for line, color in pairs(shifted) do line_colors[line] = color end
end

local function shift_checkbox_lines(lines, from_line, delta)
  if type(lines) ~= "table" or delta == 0 then return end
  local shifted = {}
  for line, value in pairs(lines) do
    if line >= from_line then
      local new_line = line + delta
      if new_line >= 1 and value == true then shifted[new_line] = true end
    elseif value == true then
      shifted[line] = true
    end
  end
  for line in pairs(lines) do lines[line] = nil end
  for line, value in pairs(shifted) do lines[line] = value end
end

local function prune_line_colors(line_colors, text)
  if type(line_colors) ~= "table" then return end
  local max_line = count_source_lines(text)
  for line in pairs(line_colors) do
    if line < 1 or line > max_line then line_colors[line] = nil end
  end
end

local function prune_checkbox_lines(lines, text)
  if type(lines) ~= "table" then return end
  local max_line = count_source_lines(text)
  for line in pairs(lines) do
    if line < 1 or line > max_line then lines[line] = nil end
  end
end

local function update_line_colors_after_replace(block, old_text, replace_start, replace_end, insert_value, new_text)
  block.line_colors = normalize_line_colors(block.line_colors)
  block.checkbox_lines = normalize_checkbox_lines(block.checkbox_lines)
  local deleted_lines = count_newlines(tostring(old_text or ""):sub((replace_start or 0) + 1, replace_end or replace_start or 0))
  local inserted_lines = count_newlines(insert_value)
  if deleted_lines > 0 then
    local start_line = get_source_line_from_byte(old_text, replace_start or 0)
    for line = start_line + 1, start_line + deleted_lines do block.line_colors[line] = nil end
    for line = start_line + 1, start_line + deleted_lines do block.checkbox_lines[line] = nil end
    shift_line_colors(block.line_colors, start_line + deleted_lines + 1, -deleted_lines)
    shift_checkbox_lines(block.checkbox_lines, start_line + deleted_lines + 1, -deleted_lines)
  end
  if inserted_lines > 0 then
    local start_line = get_source_line_from_byte(old_text, replace_start or 0)
    shift_line_colors(block.line_colors, start_line + 1, inserted_lines)
    shift_checkbox_lines(block.checkbox_lines, start_line + 1, inserted_lines)
  end
  prune_line_colors(block.line_colors, new_text)
  prune_checkbox_lines(block.checkbox_lines, new_text)
end

local function apply_line_color(block, text, editor, color)
  block.line_colors = normalize_line_colors(block.line_colors)
  local start_line, end_line = selected_line_range(text, editor)
  for line = start_line, end_line do block.line_colors[line] = color and opaque_color(color, DEFAULT_TEXT_COLOR) or nil end
  mark_dirty(block)
end

local function has_line_color(line_colors, start_line, end_line)
  if type(line_colors) ~= "table" then return false end
  for line = start_line, end_line do
    if line_colors[line] then return true end
  end
  return false
end

local function source_line_bounds(text, source_line)
  text = tostring(text or "")
  source_line = math.max(1, tonumber(source_line) or 1)
  local line = 1
  local start_pos = 1
  local index = 1
  while index <= #text do
    if line == source_line then break end
    if text:byte(index) == 10 then line = line + 1; start_pos = index + 1 end
    index = index + 1
  end
  local end_pos = #text
  index = start_pos
  while index <= #text do
    if text:byte(index) == 10 then end_pos = index - 1; break end
    index = index + 1
  end
  return start_pos, end_pos
end

local function split_source_lines(text)
  text = tostring(text or "")
  local lines = {}
  local index = 1
  while index <= #text do
    local newline = text:find("\n", index, true)
    if newline then
      lines[#lines + 1] = { text = text:sub(index, newline - 1), newline = true }
      index = newline + 1
    else
      lines[#lines + 1] = { text = text:sub(index), newline = false }
      index = #text + 1
    end
  end
  if text:sub(-1) == "\n" then lines[#lines + 1] = { text = "", newline = false } end
  if #lines == 0 then lines[1] = { text = "", newline = false } end
  return lines
end

local function strip_list_prefix(line_text)
  line_text = tostring(line_text or "")
  local stripped = line_text:gsub("^•%s+", "", 1)
  if stripped ~= line_text then return stripped end
  stripped = line_text:gsub("^%d+%.%s+", "", 1)
  if stripped ~= line_text then return stripped end
  stripped = line_text:gsub("^%[[ xX]%]%s+", "", 1)
  return stripped
end

local function list_prefix_length(line_text)
  line_text = tostring(line_text or "")
  local prefix = line_text:match("^•%s+") or line_text:match("^%d+%.%s+") or line_text:match("^%[[ xX]%]%s+")
  return prefix and #prefix or 0
end

local function numbered_start_for_line(lines, source_line)
  for line = source_line - 1, 1, -1 do
    local number = lines[line] and lines[line].text:match("^(%d+)%.%s+")
    if number then return tonumber(number) + 1 end
  end
  return 1
end

local function marker_for_mode(mode, number)
  if mode == "bullet" then return "• " end
  if mode == "numbered" then return tostring(number or 1) .. ". " end
  if mode == "checkbox" then return "[ ] " end
  return ""
end

local function list_mode_from_line(line_text)
  if tostring(line_text or ""):match("^•%s+") then return "bullet" end
  if tostring(line_text or ""):match("^%d+%.%s+") then return "numbered" end
  if tostring(line_text or ""):match("^%[[ xX]%]%s+") then return "checkbox" end
  return "none"
end

local function next_list_marker(text, caret, mode)
  mode = normalize_list_mode(mode)
  local start_pos, end_pos = source_line_bounds(text, get_source_line_from_byte(text, caret))
  local line_text = tostring(text or ""):sub(start_pos, end_pos)
  if mode == "none" then mode = list_mode_from_line(line_text) end
  if mode == "numbered" then
    local number = tonumber(line_text:match("^(%d+)%.%s+")) or 0
    return marker_for_mode(mode, number + 1)
  end
  return marker_for_mode(mode, 1)
end

local function apply_list_mode_to_selection(block, text, editor, mode)
  mode = normalize_list_mode(mode)
  local lines = split_source_lines(text)
  local start_line, end_line = selected_line_range(text, editor)
  local number = numbered_start_for_line(lines, start_line)
  local caret_line = get_source_line_from_byte(text, editor.caret or 0)
  local caret_line_start = source_line_bounds(text, caret_line)
  local caret_column = (editor.caret or 0) - (caret_line_start - 1)
  local old_prefix_len = lines[caret_line] and list_prefix_length(lines[caret_line].text) or 0
  local content_column = math.max(0, caret_column - old_prefix_len)
  local new_caret_column = content_column
  for line = start_line, end_line do
    if lines[line] then
      local body = strip_list_prefix(lines[line].text)
      if mode == "none" then
        lines[line].text = body
        if line == caret_line then new_caret_column = math.min(#body, content_column) end
      else
        local prefix = marker_for_mode(mode, number)
        lines[line].text = prefix .. body
        if line == caret_line then new_caret_column = #prefix + math.min(#body, content_column) end
        if mode == "numbered" then number = number + 1 end
      end
    end
  end
  local parts = {}
  local new_caret = 0
  for line, entry in ipairs(lines) do
    if line < caret_line then new_caret = new_caret + #entry.text + (entry.newline and 1 or 0) end
    parts[#parts + 1] = entry.text
    if entry.newline then parts[#parts + 1] = "\n" end
  end
  if lines[caret_line] then new_caret = new_caret + math.min(#lines[caret_line].text, math.max(0, new_caret_column)) end
  block.list_mode = mode
  return table.concat(parts), new_caret
end

local function toggle_checkbox_line(block, line)
  local text = tostring(block.body or "")
  local start_pos, end_pos = source_line_bounds(text, line)
  local line_text = text:sub(start_pos, end_pos)
  local toggled = line_text
  if line_text:match("^%[[xX]%]%s+") then
    toggled = line_text:gsub("^%[[xX]%](%s+)", "[ ]%1", 1)
  elseif line_text:match("^%[ %]%s+") then
    toggled = line_text:gsub("^%[ %](%s+)", "[x]%1", 1)
  else
    toggled = "[x] " .. strip_list_prefix(line_text)
  end
  block.body = text:sub(1, start_pos - 1) .. toggled .. text:sub(end_pos + 1)
  mark_dirty(block)
end

local function scaled_text_width(ctx, text, font_size)
  local width = r.ImGui_CalcTextSize and (r.ImGui_CalcTextSize(ctx, text) or 0) or 0
  local current_size = r.ImGui_GetFontSize and (r.ImGui_GetFontSize(ctx) or DEFAULT_FONT_SIZE) or DEFAULT_FONT_SIZE
  if width <= 0 then width = (font_size or current_size) * 0.45 end
  if font_size and current_size > 0 then width = width * (font_size / current_size) end
  return width
end

local function get_note_font(ctx, family, font_size)
  if not r.ImGui_CreateFont then return nil end
  family = normalize_font_family(family)
  font_size = normalize_font_size(font_size)
  local key = family .. "|" .. tostring(font_size)
  local cached = state.font_cache[key]
  if cached then return cached end
  local ok, font = pcall(r.ImGui_CreateFont, family, font_size)
  if not ok or not font then return nil end
  if r.ImGui_Attach then pcall(r.ImGui_Attach, ctx, font) end
  state.font_cache[key] = font
  return font
end

local function draw_text_sized(ctx, draw_list, x, y, color, text, font_size, font)
  if r.ImGui_DrawList_AddTextEx and font_size then
    local ok = pcall(r.ImGui_DrawList_AddTextEx, draw_list, font, font_size, x, y, color, text)
    if ok then return end
  end
  r.ImGui_DrawList_AddText(draw_list, x, y, color, text)
end

local function file_exists(path)
  path = tostring(path or "")
  if path == "" then return false end
  if r.file_exists then return r.file_exists(path) end
  local file = io.open(path, "rb")
  if file then file:close(); return true end
  return false
end

local function validate_image_texture(texture)
  return texture ~= nil
end

local function load_note_image(ctx, image)
  if not image or image.path == "" then return false end
  if validate_image_texture(image.texture) then return true end
  image.texture = nil
  if not file_exists(image.path) or not r.ImGui_CreateImage then return false end
  local ok, texture = pcall(r.ImGui_CreateImage, image.path)
  if not ok or not validate_image_texture(texture) then return false end
  if r.ImGui_Attach then
    local attached = pcall(r.ImGui_Attach, ctx, texture)
    if not attached then return false end
  end
  image.texture = texture
  if r.ImGui_Image_GetSize then
    local size_ok, width, height = pcall(r.ImGui_Image_GetSize, texture)
    if size_ok and width and height and width > 0 and height > 0 then
      image.width = 150
      image.height = math.max(1, math.floor((height / width) * 150))
    end
  end
  return true
end

local function next_image_id(block)
  local id = 1
  for _, image in ipairs(block.images or {}) do
    local value = tonumber(image.id) or 0
    if value >= id then id = value + 1 end
  end
  return id
end

local function add_note_image(ctx, block, path)
  if not block or not path or path == "" then return nil end
  block.images = block.images or {}
  local image = { id = next_image_id(block), path = path, width = 150, height = 100, pos_x = 10 + (#block.images * 20), pos_y = 10 + (#block.images * 20), scale = 100 }
  if not load_note_image(ctx, image) then return nil end
  block.images[#block.images + 1] = image
  block.selected_image_id = image.id
  return image
end

local function remove_note_image(block, image_id)
  for index, image in ipairs(block.images or {}) do
    if image.id == image_id then
      destroy_image_texture(image)
      table.remove(block.images, index)
      if block.selected_image_id == image_id then block.selected_image_id = block.images[1] and block.images[1].id or nil end
      if block.dragging_image_id == image_id then block.dragging_image_id = nil end
      return true
    end
  end
  return false
end

local function choose_image_file()
  local function first_existing_path(value)
    value = tostring(value or "")
    if value == "" then return nil end
    if file_exists(value) then return value end
    local parts = {}
    for path in value:gmatch("[^\0\r\n]+") do
      parts[#parts + 1] = path
      if file_exists(path) then return path end
    end
    if #parts >= 2 then
      local base = parts[1]
      local separator = base:match("[\\/]$") and "" or "\\"
      for idx = 2, #parts do
        local full_path = base .. separator .. parts[idx]
        if file_exists(full_path) then return full_path end
      end
    end
    return value
  end
  if r.JS_Dialog_BrowseForOpenFiles then
    local ok, selected, path = pcall(r.JS_Dialog_BrowseForOpenFiles, "Select Image", "", "*.png;*.jpg;*.jpeg;*.bmp;*.gif", "Images", false)
    if ok and selected and path and path ~= "" then return first_existing_path(path) end
  end
  if r.GetUserFileNameForRead then
    local ok, path = r.GetUserFileNameForRead("", "Select Image", "png;bmp;jpg;jpeg;gif")
    if ok and path and path ~= "" then return first_existing_path(path) end
  end
  return nil
end

local function image_display_size(image)
  local base_w = math.max(1, tonumber(image.width) or 150)
  local base_h = math.max(1, tonumber(image.height) or 100)
  if base_w > 150 then
    local scale = 150 / base_w
    base_w = 150
    base_h = base_h * scale
  end
  local user_scale = math.max(10, math.min(200, tonumber(image.scale) or 100)) / 100
  return base_w * user_scale, base_h * user_scale
end

local function collect_image_rects(ctx, block)
  local rects = {}
  for _, image in ipairs(block.images or {}) do
    if load_note_image(ctx, image) then
      local width, height = image_display_size(image)
      rects[#rects + 1] = { image = image, x1 = tonumber(image.pos_x) or 0, y1 = tonumber(image.pos_y) or 0, x2 = (tonumber(image.pos_x) or 0) + width, y2 = (tonumber(image.pos_y) or 0) + height, width = width, height = height }
    end
  end
  return rects
end

local function image_content_height(block)
  local bottom = 0
  for _, image in ipairs(block.images or {}) do
    local _, height = image_display_size(image)
    bottom = math.max(bottom, (tonumber(image.pos_y) or 0) + height)
  end
  return bottom
end

local function draw_note_images(ctx, draw_list, block, rects, origin_x, origin_y, text_color)
  for _, rect in ipairs(rects or {}) do
    local image = rect.image
    if image and validate_image_texture(image.texture) then
      local x1 = origin_x + rect.x1
      local y1 = origin_y + rect.y1
      local x2 = origin_x + rect.x2
      local y2 = origin_y + rect.y2
      local drawn = false
      if r.ImGui_DrawList_AddImage then drawn = pcall(r.ImGui_DrawList_AddImage, draw_list, image.texture, x1, y1, x2, y2, 0, 0, 1, 1, 0xFFFFFFFF) end
      if not drawn and r.ImGui_Image and r.ImGui_SetCursorScreenPos then
        r.ImGui_SetCursorScreenPos(ctx, x1, y1)
        pcall(r.ImGui_Image, ctx, image.texture, rect.width, rect.height)
      end
      if block.selected_image_id == image.id then r.ImGui_DrawList_AddRect(draw_list, x1 - 2, y1 - 2, x2 + 2, y2 + 2, Theme.colors.accent or text_color, 0, 0, 2) end
    end
  end
end

local function build_body_layout(ctx, text, wrap_width, line_height, font_size)
  local lines = {}
  local current_chars = {}
  local current_width = 0
  local last_break_idx = nil
  local line_start_byte = 1
  local index = 1
  local checkbox_checked = nil
  text = tostring(text or "")

  local function recalc_width()
    current_width = 0
    last_break_idx = nil
    for idx, info in ipairs(current_chars) do
      current_width = current_width + info.width
      if info.char == " " or info.char == "\t" then last_break_idx = idx end
    end
  end

  local function finalize_line(start_byte, chars, newline_byte)
    local line = { start_byte = start_byte, newline_byte = newline_byte, source_line = get_source_line_from_byte(text, start_byte - 1), checkbox = checkbox_checked ~= nil, checked = checkbox_checked == true, chars = {}, width = 0, text = "" }
    local parts = {}
    local x = 0
    for idx, info in ipairs(chars) do
      local entry = { byte_start = info.byte_start, byte_end = info.byte_end, char = info.char, width = info.width, x0 = x, x1 = x + info.width }
      line.chars[idx] = entry
      parts[#parts + 1] = info.char
      x = x + info.width
    end
    line.width = x
    line.end_byte = #chars > 0 and chars[#chars].byte_end or start_byte - 1
    line.text = table.concat(parts)
    lines[#lines + 1] = line
    checkbox_checked = nil
  end

  while index <= #text do
    local byte = text:byte(index)
    if byte == 13 then
      index = index + 1
    elseif byte == 10 then
      finalize_line(line_start_byte, current_chars, index)
      current_chars = {}
      current_width = 0
      last_break_idx = nil
      line_start_byte = index + 1
      index = index + 1
    elseif index == line_start_byte and index + 3 <= #text and text:sub(index, index + 3):match("^%[[ xX]%]%s") then
      local mark = text:sub(index + 1, index + 1)
      checkbox_checked = mark == "x" or mark == "X"
      line_start_byte = index + 4
      index = index + 4
    elseif index < #text and text:sub(index, index + 1) == "**" then
      index = index + 2
    else
      local next_index = utf8.offset(text, 2, index) or (#text + 1)
      local char = text:sub(index, next_index - 1)
      local char_width = scaled_text_width(ctx, char, font_size)
      current_chars[#current_chars + 1] = { char = char, width = char_width, byte_start = index, byte_end = next_index - 1 }
      current_width = current_width + char_width
      if char == " " or char == "\t" then last_break_idx = #current_chars end
      if wrap_width > 0 and current_width > wrap_width and #current_chars > 1 then
        local break_idx = last_break_idx or (#current_chars - 1)
        local line_chars = {}
        for idx = 1, break_idx do line_chars[#line_chars + 1] = current_chars[idx] end
        while #line_chars > 0 and line_chars[#line_chars].char:match("%s") do table.remove(line_chars) end
        finalize_line(line_start_byte, line_chars, nil)
        local leftover = {}
        for idx = break_idx + 1, #current_chars do leftover[#leftover + 1] = current_chars[idx] end
        current_chars = leftover
        line_start_byte = #current_chars > 0 and current_chars[1].byte_start or next_index
        recalc_width()
      end
      index = next_index
    end
  end

  finalize_line(line_start_byte, current_chars, nil)
  return { lines = lines, line_height = line_height, total_height = math.max(line_height, #lines * line_height) }
end

local function caret_at_line_position(line, target_x)
  if not line then return 0 end
  local caret = (line.start_byte or 1) - 1
  for _, char in ipairs(line.chars or {}) do
    local middle = char.x0 + (char.width * 0.5)
    if target_x < middle then return caret end
    caret = char.byte_end
  end
  if line.newline_byte then return line.newline_byte - 1 end
  return caret
end

local function locate_caret(layout, text, caret)
  caret = clamp_caret(text, caret)
  for idx, line in ipairs(layout.lines) do
    if caret < line.start_byte then return idx, 0, (idx - 1) * layout.line_height, line end
    if line.end_byte >= line.start_byte and caret <= line.end_byte then
      for _, char in ipairs(line.chars or {}) do
        if caret < char.byte_start then return idx, char.x0, (idx - 1) * layout.line_height, line end
        if caret <= char.byte_end then return idx, char.x1, (idx - 1) * layout.line_height, line end
      end
      return idx, line.width, (idx - 1) * layout.line_height, line
    end
    if line.newline_byte and caret == line.newline_byte then
      local next_line = layout.lines[idx + 1]
      if next_line then return idx + 1, 0, idx * layout.line_height, next_line end
      return idx, line.width, (idx - 1) * layout.line_height, line
    end
  end
  local last_idx = math.max(1, #layout.lines)
  local line = layout.lines[last_idx]
  return last_idx, line and line.width or 0, (last_idx - 1) * layout.line_height, line
end

local function draw_body_editor(ctx, block, width, height, note_color, text_color)
  local editor = ensure_body_editor(block)
  local text = tostring(block.body or "")
  local font_size = normalize_font_size(block.font_size)
  local font_family = normalize_font_family(block.font_family)
  local font = get_note_font(ctx, font_family, font_size)
  local checkbox_indent = math.max(16, font_size + 4)
  local line_height = font_size + 6
  local padding_x = 8
  local padding_y = 6
  local child_w = width or 320
  local child_h = height or 120
  local style_count = 0
  if r.ImGui_Col_ChildBg then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ChildBg(), note_color); style_count = style_count + 1 end
  if r.ImGui_Col_Border then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Border(), Theme.colors.border or 0x444444FF); style_count = style_count + 1 end
  local child_flags = 0
  if r.ImGui_WindowFlags_NoScrollbar then child_flags = child_flags | r.ImGui_WindowFlags_NoScrollbar() end
  if r.ImGui_WindowFlags_NoScrollWithMouse then child_flags = child_flags | r.ImGui_WindowFlags_NoScrollWithMouse() end
  local visible = r.ImGui_BeginChild(ctx, "##body_editor", child_w, child_h, 1, child_flags)
  if visible then
    local avail_w, avail_h = r.ImGui_GetContentRegionAvail(ctx)
    avail_w = math.max(40, avail_w or child_w)
    avail_h = math.max(40, avail_h or child_h)
    local wrap_width = math.max(24, avail_w - padding_x * 2 - checkbox_indent)
    local layout = build_body_layout(ctx, text, wrap_width, line_height, font_size)
    local image_rects = collect_image_rects(ctx, block)
    local fit_margin = line_height + padding_y
    local content_height = math.max(layout.total_height, image_content_height(block))
    block.body_fit_height = math.max(MIN_BLOCK_HEIGHT, math.min(MAX_BLOCK_HEIGHT, content_height + padding_y * 2 + fit_margin))
    local origin_x, origin_y = r.ImGui_GetCursorScreenPos(ctx)
    local function is_first_visual_line(idx)
      local line = layout.lines[idx]
      local previous = layout.lines[idx - 1]
      return line and (not previous or previous.source_line ~= line.source_line)
    end
    local function line_indent(line)
      return line and line.checkbox and checkbox_indent or 0
    end
    local function caret_from_mouse()
      local mouse_x, mouse_y = r.ImGui_GetMousePos(ctx)
      local local_y = mouse_y - origin_y - padding_y
      local line_idx = math.max(1, math.min(#layout.lines, math.floor(local_y / line_height) + 1))
      local line = layout.lines[line_idx]
      local local_x = mouse_x - origin_x - padding_x - line_indent(line)
      return caret_at_line_position(layout.lines[line_idx], local_x)
    end
    local function checkbox_line_from_mouse()
      local mouse_x, mouse_y = r.ImGui_GetMousePos(ctx)
      local marker_x = origin_x + padding_x
      local size = math.max(10, math.min(16, font_size * 0.85))
      for idx, line in ipairs(layout.lines) do
        if line.checkbox and is_first_visual_line(idx) then
          local line_y = origin_y + padding_y + (idx - 1) * line_height
          local box_y = line_y + (line_height - size) * 0.5
          if mouse_x >= marker_x and mouse_x <= marker_x + size and mouse_y >= box_y and mouse_y <= box_y + size then return line.source_line end
        end
      end
      return nil
    end
    local function image_at_mouse()
      local mouse_x, mouse_y = r.ImGui_GetMousePos(ctx)
      local local_x = mouse_x - origin_x
      local local_y = mouse_y - origin_y
      for idx = #image_rects, 1, -1 do
        local rect = image_rects[idx]
        if local_x >= rect.x1 and local_x <= rect.x2 and local_y >= rect.y1 and local_y <= rect.y2 then return rect.image, rect end
      end
      return nil, nil
    end
    local function image_by_id(image_id)
      for _, image in ipairs(block.images or {}) do
        if image.id == image_id then return image end
      end
      return nil
    end
    local mouse_button = r.ImGui_MouseButton_Left and r.ImGui_MouseButton_Left() or 0
    local function update_image_drag()
      local image = image_by_id(block.dragging_image_id)
      if not image then block.dragging_image_id = nil; return end
      if r.ImGui_IsMouseDown and r.ImGui_IsMouseDown(ctx, mouse_button) then
        local delta_x, delta_y = 0, 0
        if r.ImGui_GetMouseDragDelta then delta_x, delta_y = r.ImGui_GetMouseDragDelta(ctx, mouse_button, 0) end
        if (delta_x or 0) ~= 0 or (delta_y or 0) ~= 0 then
          local width, height = image_display_size(image)
          local new_x = math.max(0, math.min(math.max(0, avail_w - width), (tonumber(image.pos_x) or 0) + (delta_x or 0)))
          local new_y = math.max(0, math.min(math.max(0, avail_h - height), (tonumber(image.pos_y) or 0) + (delta_y or 0)))
          if new_x ~= image.pos_x or new_y ~= image.pos_y then
            image.pos_x = new_x
            image.pos_y = new_y
            mark_dirty(block)
            image_rects = collect_image_rects(ctx, block)
          end
          if r.ImGui_ResetMouseDragDelta then r.ImGui_ResetMouseDragDelta(ctx, mouse_button) end
        end
      else
        block.dragging_image_id = nil
      end
    end
    r.ImGui_InvisibleButton(ctx, "##body_capture", avail_w, avail_h)
    local hovered = r.ImGui_IsItemHovered(ctx)
    local hovered_image = hovered and image_at_mouse() or nil
    if hovered_image and r.ImGui_MouseCursor_Hand then r.ImGui_SetMouseCursor(ctx, r.ImGui_MouseCursor_Hand()) end
    if hovered_image and r.ImGui_SetTooltip then r.ImGui_SetTooltip(ctx, "Drag to move | Right-click for options") end
    update_image_drag()
    if r.ImGui_IsItemClicked(ctx, 0) then
      if hovered_image then
        block.selected_image_id = hovered_image.id
        block.dragging_image_id = hovered_image.id
        editor.active = false
        editor.mouse_selecting = false
      else
        local checkbox_line = checkbox_line_from_mouse()
        if checkbox_line then
        toggle_checkbox_line(block, checkbox_line)
        editor.active = true
        editor.mouse_selecting = false
        else
          block.selected_image_id = nil
        editor.caret = caret_from_mouse()
        editor.active = true
        editor.preferred_x = nil
        editor.mouse_selecting = true
        clear_selection(editor, editor.caret)
        end
      end
    elseif r.ImGui_IsItemClicked(ctx, 1) then
      if hovered_image then
        block.selected_image_id = hovered_image.id
        editor.active = false
        editor.mouse_selecting = false
        r.ImGui_OpenPopup(ctx, "##image_context_" .. tostring(hovered_image.id))
      else
        editor.active = true
        if not selection_range(editor) then
          editor.caret = caret_from_mouse()
          clear_selection(editor, editor.caret)
        end
        r.ImGui_OpenPopup(ctx, "##body_context")
      end
    elseif r.ImGui_IsMouseClicked(ctx, 0) and not hovered then
      editor.active = false
    end
    if editor.mouse_selecting and r.ImGui_IsMouseDown and r.ImGui_IsMouseDown(ctx, mouse_button) then
      local caret = caret_from_mouse()
      editor.caret = caret
      editor.selection_start = editor.selection_anchor or editor.caret
      editor.selection_end = caret
    elseif editor.mouse_selecting then
      editor.mouse_selecting = false
    end

    local changed = false
    local function apply_text(new_text, new_caret)
      text = new_text
      editor.caret = clamp_caret(text, new_caret)
      clear_selection(editor, editor.caret)
      changed = true
    end
    local max_text_height = math.max(line_height, avail_h - padding_y * 2)
    local function apply_candidate(new_text, new_caret, selection_start, selection_end)
      local candidate_layout = build_body_layout(ctx, new_text, wrap_width, line_height, font_size)
      if candidate_layout.total_height > max_text_height + 0.5 then return false end
      text = new_text
      editor.caret = clamp_caret(text, new_caret)
      editor.selection_start = clamp_caret(text, selection_start or editor.caret)
      editor.selection_end = clamp_caret(text, selection_end or editor.selection_start)
      editor.selection_anchor = editor.selection_start
      changed = true
      return true
    end
    local function try_insert(value)
      local old_text = text
      local base_text = old_text
      local base_caret = editor.caret
      local replace_start = editor.caret
      local replace_end = editor.caret
      local sel_start, sel_end = selection_range(editor)
      if sel_start then
        replace_start = sel_start
        replace_end = sel_end
        base_text = (sel_start > 0 and old_text:sub(1, sel_start) or "") .. old_text:sub(sel_end + 1)
        base_caret = sel_start
      end
      base_text, base_caret = trim_blank_tail_for_input(base_text, base_caret, value)
      local candidate_text, candidate_caret = insert_at(base_text, base_caret, value)
      local candidate_layout = build_body_layout(ctx, candidate_text, wrap_width, line_height, font_size)
      if candidate_layout.total_height > max_text_height + 0.5 then return false end
      update_line_colors_after_replace(block, old_text, replace_start, replace_end, value, candidate_text)
      apply_text(candidate_text, candidate_caret)
      return true
    end
    local function try_bold()
      local new_text, new_caret, selection_start, selection_end = bold_candidate(text, editor)
      return apply_candidate(new_text, new_caret, selection_start, selection_end)
    end
    if editor.active then
      local ctrl_down = false
      if r.ImGui_IsKeyDown and r.ImGui_Key_LeftCtrl and r.ImGui_Key_RightCtrl then ctrl_down = r.ImGui_IsKeyDown(ctx, r.ImGui_Key_LeftCtrl()) or r.ImGui_IsKeyDown(ctx, r.ImGui_Key_RightCtrl()) end
      if ctrl_down and r.ImGui_Key_A and r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_A(), false) then
        editor.selection_start = 0
        editor.selection_end = #text
        editor.selection_anchor = 0
        editor.caret = #text
      end
      if ctrl_down and r.ImGui_Key_B and r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_B(), false) then try_bold() end
      if ctrl_down and r.ImGui_Key_C and r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_C(), false) then set_clipboard(ctx, selected_text(text, editor)) end
      if ctrl_down and r.ImGui_Key_X and r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_X(), false) then
        set_clipboard(ctx, selected_text(text, editor))
        local old_text = text
        local sel_start, sel_end = selection_range(editor)
        local new_text, new_caret, did_delete = delete_selection(text, editor)
        if did_delete then update_line_colors_after_replace(block, old_text, sel_start, sel_end, "", new_text); apply_text(new_text, new_caret) end
      end
      if r.ImGui_Key_Enter and r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_Enter(), false) then try_insert("\n" .. next_list_marker(text, editor.caret, block.list_mode)) end
      if r.ImGui_Key_KeypadEnter and r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_KeypadEnter(), false) then try_insert("\n" .. next_list_marker(text, editor.caret, block.list_mode)) end
      if ctrl_down and r.ImGui_Key_V and r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_V(), false) and r.ImGui_GetClipboardText then
        local clip = get_clipboard(ctx)
        if clip and clip ~= "" then try_insert(clip:gsub("\r\n", "\n"):gsub("\r", "\n")) end
      elseif r.ImGui_GetInputQueueCharacter then
        for idx = 0, math.huge do
          local primary, secondary = r.ImGui_GetInputQueueCharacter(ctx, idx)
          if not primary or primary == 0 then break end
          local codepoint = secondary or primary
          if codepoint >= 32 and not ctrl_down then
            local ok_char, char = pcall(utf8.char, codepoint)
            if ok_char and char and char ~= "" then try_insert(char) end
          end
        end
      end
      if r.ImGui_Key_Backspace and r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_Backspace(), true) then
        local old_text = text
        local sel_start, sel_end = selection_range(editor)
        local new_text, new_caret, did_delete = delete_selection(text, editor)
        if did_delete then update_line_colors_after_replace(block, old_text, sel_start, sel_end, "", new_text); apply_text(new_text, new_caret) else local old_caret = editor.caret; new_text, new_caret = delete_previous(text, editor.caret); if new_text ~= text then update_line_colors_after_replace(block, old_text, new_caret, old_caret, "", new_text); apply_text(new_text, new_caret) end end
      end
      if r.ImGui_Key_Delete and r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_Delete(), true) then
        local old_text = text
        local sel_start, sel_end = selection_range(editor)
        local new_text, new_caret, did_delete = delete_selection(text, editor)
        if did_delete then update_line_colors_after_replace(block, old_text, sel_start, sel_end, "", new_text); apply_text(new_text, new_caret) else local delete_end = utf8.offset(text, 2, editor.caret + 1); delete_end = delete_end and (delete_end - 1) or #text; new_text, new_caret = delete_next(text, editor.caret); if new_text ~= text then update_line_colors_after_replace(block, old_text, editor.caret, delete_end, "", new_text); apply_text(new_text, new_caret) end end
      end
      if r.ImGui_Key_LeftArrow and r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_LeftArrow(), true) then editor.caret = move_left(text, editor.caret); editor.preferred_x = nil end
      if r.ImGui_Key_RightArrow and r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_RightArrow(), true) then editor.caret = move_right(text, editor.caret); editor.preferred_x = nil end
      if r.ImGui_Key_UpArrow and r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_UpArrow(), true) then
        local line_idx, caret_x = locate_caret(layout, text, editor.caret)
        editor.preferred_x = editor.preferred_x or caret_x
        local target = layout.lines[math.max(1, (line_idx or 1) - 1)]
        if target then editor.caret = caret_at_line_position(target, editor.preferred_x) end
      end
      if r.ImGui_Key_DownArrow and r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_DownArrow(), true) then
        local line_idx, caret_x = locate_caret(layout, text, editor.caret)
        editor.preferred_x = editor.preferred_x or caret_x
        local target = layout.lines[math.min(#layout.lines, (line_idx or 1) + 1)]
        if target then editor.caret = caret_at_line_position(target, editor.preferred_x) end
      end
    end

    if r.ImGui_BeginPopup(ctx, "##body_context") then
      local has_selection = selection_range(editor) ~= nil
      if r.ImGui_MenuItem(ctx, "Bold", "Ctrl+B", false, true) then try_bold() end
      if r.ImGui_MenuItem(ctx, "Add Image") then
        local path = choose_image_file()
        if path and add_note_image(ctx, block, path) then mark_dirty(block); image_rects = collect_image_rects(ctx, block) end
      end
      if #(block.images or {}) > 0 then
        r.ImGui_Separator(ctx)
        if r.ImGui_MenuItem(ctx, "Remove All Images") then clear_block_images(block); mark_dirty(block); image_rects = {} end
      end
      if r.ImGui_BeginMenu(ctx, "List Mode") then
        local mode = normalize_list_mode(block.list_mode)
        local function try_list_mode(new_mode)
          local new_text, new_caret = apply_list_mode_to_selection(block, text, editor, new_mode)
          if apply_candidate(new_text, new_caret, new_caret, new_caret) then block.list_mode = new_mode; mark_dirty(block) end
        end
        if r.ImGui_MenuItem(ctx, "None", nil, mode == "none") then try_list_mode("none") end
        if r.ImGui_MenuItem(ctx, "Bullet (•)", nil, mode == "bullet") then try_list_mode("bullet") end
        if r.ImGui_MenuItem(ctx, "Numbered (1. 2. 3.)", nil, mode == "numbered") then try_list_mode("numbered") end
        if r.ImGui_MenuItem(ctx, "Checkbox ([ ])", nil, mode == "checkbox") then try_list_mode("checkbox") end
        if text:find("%[[xX]%]%s") then
          r.ImGui_Separator(ctx)
          if r.ImGui_MenuItem(ctx, "Clear Checked Boxes") then apply_candidate(text:gsub("^%[[xX]%](%s+)", "[ ]%1"):gsub("\n%[[xX]%](%s+)", "\n[ ]%1"), editor.caret, editor.selection_start, editor.selection_end); mark_dirty(block) end
        end
        r.ImGui_EndMenu(ctx)
      end
      if r.ImGui_BeginMenu(ctx, "Line Color") then
        local line_start, line_end = selected_line_range(text, editor)
        r.ImGui_Text(ctx, line_start == line_end and ("Line " .. tostring(line_start)) or ("Lines " .. tostring(line_start) .. "-" .. tostring(line_end)))
        r.ImGui_Separator(ctx)
        for _, preset in ipairs(TEXT_COLOR_PRESETS) do
          local active = has_line_color({ [line_start] = block.line_colors and block.line_colors[line_start] }, line_start, line_start) and block.line_colors[line_start] == preset.color
          if r.ImGui_MenuItem(ctx, preset.name, nil, active, true) then apply_line_color(block, text, editor, preset.color) end
        end
        if has_line_color(block.line_colors, line_start, line_end) then
          r.ImGui_Separator(ctx)
          if r.ImGui_MenuItem(ctx, line_start == line_end and "Reset Line Color" or "Reset Selected Line Colors") then apply_line_color(block, text, editor, nil) end
        end
        if next(block.line_colors or {}) then
          if r.ImGui_MenuItem(ctx, "Reset All Line Colors") then block.line_colors = {}; mark_dirty(block) end
        end
        r.ImGui_EndMenu(ctx)
      end
      r.ImGui_Separator(ctx)
      if r.ImGui_MenuItem(ctx, "Copy", nil, false, has_selection) then set_clipboard(ctx, selected_text(text, editor)) end
      if r.ImGui_MenuItem(ctx, "Cut", nil, false, has_selection) then
        set_clipboard(ctx, selected_text(text, editor))
        local old_text = text
        local sel_start, sel_end = selection_range(editor)
        local new_text, new_caret, did_delete = delete_selection(text, editor)
        if did_delete then update_line_colors_after_replace(block, old_text, sel_start, sel_end, "", new_text); apply_text(new_text, new_caret) end
      end
      if r.ImGui_MenuItem(ctx, "Paste", nil, false, true) then
        local clip = get_clipboard(ctx)
        if clip and clip ~= "" then try_insert(clip:gsub("\r\n", "\n"):gsub("\r", "\n")) end
      end
      if r.ImGui_MenuItem(ctx, "Delete", nil, false, has_selection) then
        local old_text = text
        local sel_start, sel_end = selection_range(editor)
        local new_text, new_caret, did_delete = delete_selection(text, editor)
        if did_delete then update_line_colors_after_replace(block, old_text, sel_start, sel_end, "", new_text); apply_text(new_text, new_caret) end
      end
      r.ImGui_Separator(ctx)
      if r.ImGui_MenuItem(ctx, "Select All", nil, false, #text > 0) then
        editor.selection_start = 0
        editor.selection_end = #text
        editor.selection_anchor = 0
        editor.caret = #text
      end
      r.ImGui_EndPopup(ctx)
    end

    for _, image in ipairs(block.images or {}) do
      if r.ImGui_BeginPopup(ctx, "##image_context_" .. tostring(image.id)) then
        r.ImGui_Text(ctx, "Image " .. tostring(image.id))
        r.ImGui_Separator(ctx)
        r.ImGui_Text(ctx, "Image Size:")
        r.ImGui_PushItemWidth(ctx, 200)
        local scale_changed, new_scale = r.ImGui_SliderInt(ctx, "##image_scale_" .. tostring(image.id), tonumber(image.scale) or 100, 10, 200, "%d%%")
        r.ImGui_PopItemWidth(ctx)
        if scale_changed and new_scale ~= image.scale then image.scale = new_scale; mark_dirty(block); image_rects = collect_image_rects(ctx, block) end
        r.ImGui_Separator(ctx)
        if r.ImGui_MenuItem(ctx, "Remove This Image") then remove_note_image(block, image.id); mark_dirty(block); image_rects = collect_image_rects(ctx, block) end
        if #(block.images or {}) > 1 then
          r.ImGui_Separator(ctx)
          if r.ImGui_MenuItem(ctx, "Remove All Images") then clear_block_images(block); mark_dirty(block); image_rects = {} end
        end
        r.ImGui_EndPopup(ctx)
      end
    end

    if changed then
      block.body = text
      mark_dirty(block)
      layout = build_body_layout(ctx, text, wrap_width, line_height, font_size)
    end

    local draw_list = r.ImGui_GetWindowDrawList(ctx)
    r.ImGui_DrawList_PushClipRect(draw_list, origin_x, origin_y, origin_x + avail_w, origin_y + avail_h, true)
    local sel_start, sel_end = selection_range(editor)
    local bold_lookup = build_bold_lookup(text)
    image_rects = collect_image_rects(ctx, block)
    if sel_start and sel_end and sel_end > sel_start then
      local highlight = Theme.colors.accent_soft or 0x2B4B78FF
      highlight = (highlight & 0xFFFFFF00) | 0x99
      for idx, line in ipairs(layout.lines) do
        local line_y = origin_y + padding_y + (idx - 1) * line_height
        if line_y > origin_y - line_height and line_y < origin_y + avail_h then
          local indent = line_indent(line)
          local active = false
          local start_x = 0
          local end_x = 0
          for _, char in ipairs(line.chars or {}) do
            if char.byte_end >= sel_start + 1 and char.byte_start <= sel_end then
              if not active then
                active = true
                start_x = char.x0
              end
              end_x = char.x1
            elseif active then
              r.ImGui_DrawList_AddRectFilled(draw_list, origin_x + padding_x + indent + start_x, line_y, origin_x + padding_x + indent + end_x, line_y + line_height, highlight)
              active = false
            end
          end
          if active then r.ImGui_DrawList_AddRectFilled(draw_list, origin_x + padding_x + indent + start_x, line_y, origin_x + padding_x + indent + end_x, line_y + line_height, highlight) end
          if line.newline_byte and line.newline_byte >= sel_start + 1 and line.newline_byte <= sel_end then
            r.ImGui_DrawList_AddRectFilled(draw_list, origin_x + padding_x + indent + line.width, line_y, origin_x + padding_x + indent + line.width + math.max(6, line_height * 0.4), line_y + line_height, highlight)
          end
        end
      end
    end
    for idx, line in ipairs(layout.lines) do
      local line_y = origin_y + padding_y + (idx - 1) * line_height
      if line_y > origin_y - line_height and line_y < origin_y + avail_h then
        local draw_color = (block.line_colors and line.source_line and block.line_colors[line.source_line]) or text_color
        if line.checkbox and is_first_visual_line(idx) then
          local size = math.max(10, math.min(16, font_size * 0.85))
          local box_x = origin_x + padding_x
          local box_y = line_y + (line_height - size) * 0.5
          r.ImGui_DrawList_AddRect(draw_list, box_x, box_y, box_x + size, box_y + size, draw_color, 2, 0, 1.2)
          if line.checked then
            r.ImGui_DrawList_AddLine(draw_list, box_x + size * 0.22, box_y + size * 0.52, box_x + size * 0.42, box_y + size * 0.74, draw_color, 1.8)
            r.ImGui_DrawList_AddLine(draw_list, box_x + size * 0.42, box_y + size * 0.74, box_x + size * 0.82, box_y + size * 0.26, draw_color, 1.8)
          end
        end
        local indent = line_indent(line)
        for _, char in ipairs(line.chars or {}) do
          local char_x = origin_x + padding_x + indent + char.x0
          draw_text_sized(ctx, draw_list, char_x, line_y, draw_color, char.char or "", font_size, font)
          if bold_lookup[char.byte_start] then draw_text_sized(ctx, draw_list, char_x + math.max(0.7, font_size * 0.05), line_y, draw_color, char.char or "", font_size, font) end
        end
      end
    end
    if layout.total_height > math.max(line_height, avail_h - padding_y * 2 - 2) + 0.5 then
      local more_text = "more....."
      local more_w = scaled_text_width(ctx, more_text, font_size)
      local more_y = origin_y + avail_h - line_height
      local more_bg = (note_color & 0xFFFFFF00) | 0xEE
      r.ImGui_DrawList_AddRectFilled(draw_list, origin_x, more_y - 2, origin_x + avail_w, origin_y + avail_h, more_bg)
      draw_text_sized(ctx, draw_list, origin_x + math.max(padding_x, avail_w - more_w - padding_x), more_y, text_color, more_text, font_size, font)
    end
    draw_note_images(ctx, draw_list, block, image_rects, origin_x, origin_y, text_color)
    if editor.active then
      local _, caret_x, caret_y, caret_line = locate_caret(layout, text, editor.caret)
      local x = origin_x + padding_x + line_indent(caret_line) + caret_x
      local y = origin_y + padding_y + caret_y
      if y >= origin_y and y <= origin_y + avail_h then r.ImGui_DrawList_AddLine(draw_list, x, y, x, y + line_height, text_color, 1.4) end
    end
    r.ImGui_DrawList_PopClipRect(draw_list)
    r.ImGui_EndChild(ctx)
  end
  if style_count > 0 then r.ImGui_PopStyleColor(ctx, style_count) end

  local handle_x, handle_y = r.ImGui_GetCursorScreenPos(ctx)
  r.ImGui_InvisibleButton(ctx, "##body_resize", child_w, 8)
  local handle_active = r.ImGui_IsItemActive(ctx)
  local handle_hovered = r.ImGui_IsItemHovered(ctx)
  local draw_list = r.ImGui_GetWindowDrawList(ctx)
  local handle_color = handle_active and (Theme.colors.accent or 0x7AA2F7FF) or (handle_hovered and (Theme.colors.text_dim or 0xA0A0A0FF) or (Theme.colors.border or 0x444444FF))
  r.ImGui_DrawList_AddLine(draw_list, handle_x + 12, handle_y + 4, handle_x + child_w - 12, handle_y + 4, handle_color, handle_active and 2.0 or 1.0)
  if handle_hovered then r.ImGui_SetTooltip(ctx, "Drag to resize note | Double-click to fit") end
  local mouse_button = r.ImGui_MouseButton_Left and r.ImGui_MouseButton_Left() or 0
  local fit_clicked = handle_hovered and r.ImGui_IsMouseDoubleClicked and r.ImGui_IsMouseDoubleClicked(ctx, mouse_button)
  if fit_clicked then
    local new_height = math.max(MIN_BLOCK_HEIGHT, math.min(MAX_BLOCK_HEIGHT, block.body_fit_height or child_h))
    if math.floor(new_height + 0.5) ~= math.floor((block.height or child_h) + 0.5) then
      block.height = new_height
      mark_dirty(block)
    end
  elseif handle_active and r.ImGui_GetMouseDragDelta then
    if not block.resize_start_height then block.resize_start_height = block.height or child_h end
    local _, drag_y = r.ImGui_GetMouseDragDelta(ctx, mouse_button, 0)
    local new_height = math.max(MIN_BLOCK_HEIGHT, math.min(MAX_BLOCK_HEIGHT, (block.resize_start_height or child_h) + (drag_y or 0)))
    if math.floor(new_height + 0.5) ~= math.floor((block.height or child_h) + 0.5) then
      block.height = new_height
      mark_dirty(block)
    end
  else
    block.resize_start_height = nil
  end
end

local function draw_block(app, settings, block, index, width)
  local ctx = app.ctx
  prepare_block(block, state.context_info)
  local note_color = effective_note_color(block, state.context_info)
  local text_color = opaque_color(block.text_color, DEFAULT_TEXT_COLOR)
  r.ImGui_PushID(ctx, block.id or tostring(index))
  local arrow = block.collapsed and ">" or "v"
  if r.ImGui_Button(ctx, arrow, 22, 0) then block.collapsed = not block.collapsed; mark_dirty(block) end
  r.ImGui_SameLine(ctx)
  r.ImGui_PushItemWidth(ctx, math.max(80, (width or 320) - 154))
  local style_count = push_note_style(ctx, note_color, text_color)
  local title_changed, title = r.ImGui_InputText(ctx, "##title", block.title or "Notes")
  pop_note_style(ctx, style_count)
  if title_changed then block.title = title; mark_dirty(block) end
  r.ImGui_PopItemWidth(ctx)
  r.ImGui_SameLine(ctx)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), note_color)
  if r.ImGui_Button(ctx, "C", 22, 0) then r.ImGui_OpenPopup(ctx, "##note_colors") end
  r.ImGui_PopStyleColor(ctx)
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Colors") end
  draw_color_popup(ctx, block, state.context_info)
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "A", 22, 0) then r.ImGui_OpenPopup(ctx, "##font_size") end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, normalize_font_family(block.font_family) .. " | " .. tostring(normalize_font_size(block.font_size)) .. " px") end
  draw_font_size_popup(ctx, block)
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "D", 22, 0) then duplicate_block(index) end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Duplicate") end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "x", 22, 0) then remove_block(index); r.ImGui_PopID(ctx); return end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, #state.blocks <= 1 and "Clear" or "Delete") end
  if not block.collapsed then
    draw_body_editor(ctx, block, width or 320, block.height or settings.block_height, note_color, text_color)
  end
  r.ImGui_Spacing(ctx)
  r.ImGui_PopID(ctx)
end

function M.init(app)
  ensure_settings(app)
end

function M.update(app)
  local settings, info = ensure_context(app)
  if state.dirty and now() - (state.last_edit_time or 0) >= settings.auto_save_interval then save_current(app) end
end

function M.draw(app)
  local ctx = app.ctx
  local settings, info = ensure_context(app)
  local width = r.ImGui_GetContentRegionAvail(ctx)
  draw_context_bar(app, settings, info, width)
  if info.can_edit then
    if r.ImGui_Button(ctx, "+ Note", math.max(80, width or 320), 0) then add_block() end
  else
    r.ImGui_BeginDisabled(ctx, true)
    r.ImGui_Button(ctx, "+ Note", math.max(80, width or 320), 0)
    r.ImGui_EndDisabled(ctx)
  end
  r.ImGui_Separator(ctx)
  local _, remaining_h = r.ImGui_GetContentRegionAvail(ctx)
  local list_h = math.max(40, (remaining_h or 200) - UI.info_line_height(ctx))
  local child_visible = r.ImGui_BeginChild(ctx, "##notes_blocks", 0, list_h, 0)
  if child_visible then
    if info.can_edit then
      for index, block in ipairs(state.blocks) do draw_block(app, settings, block, index, math.max(120, (width or 320) - 4)) end
    else
      r.ImGui_TextColored(ctx, Theme.colors.warning, info.label or "Context unavailable")
    end
    r.ImGui_EndChild(ctx)
  end
  UI.draw_info_line(ctx, info_text(settings, info))
end

function M.shutdown(app)
  save_current(app)
  release_blocks_images(state.blocks)
end

return M