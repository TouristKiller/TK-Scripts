local r = reaper
local Theme = require("core.theme")

local M = {
  id = "fx_chain_builder",
  title = "FX Chain Builder",
  icon = "CHN",
  version = "0.1.0"
}

local fx_root = r.GetResourcePath() .. "/Scripts/TK Scripts/FX/"
local screenshots_path = fx_root .. "Screenshots/"
local os_separator = package.config:sub(1, 1)

local defaults = {
  plugins = {},
  show_screenshots = true,
  thumbnail_height = 86,
  preserve_chunks = true,
  clear_after_commit = false,
  target_mode = "selected_tracks"
}

local state = {
  plugins = {},
  chunks = {},
  screenshot_index = nil,
  screenshot_cache = {},
  screenshot_missing = {},
  fx_chain_cache = {},
  last_error = nil
}

local function copy_list(source)
  local target = {}
  if type(source) ~= "table" then return target end
  for _, value in ipairs(source) do
    if type(value) == "string" and value ~= "" then target[#target + 1] = value end
  end
  return target
end

local function save_plugin_settings(app, settings)
  settings.plugins = copy_list(state.plugins)
  if app.save_settings then app.save_settings() end
end

local function ensure_chunk_slots()
  for index = 1, #state.plugins do
    if state.chunks[index] == nil then state.chunks[index] = false end
  end
end

local function ensure_settings(app)
  app.settings.fx_chain_builder = app.settings.fx_chain_builder or {}
  local settings = app.settings.fx_chain_builder
  local changed = false
  for key, value in pairs(defaults) do
    if settings[key] == nil then
      if type(value) == "table" then
        settings[key] = copy_list(value)
      else
        settings[key] = value
      end
      changed = true
    end
  end
  if type(settings.plugins) ~= "table" then
    settings.plugins = {}
    changed = true
  end
  settings.plugins = copy_list(settings.plugins)
  settings.thumbnail_height = math.floor(tonumber(settings.thumbnail_height) or defaults.thumbnail_height)
  if settings.thumbnail_height < 48 then settings.thumbnail_height = 48; changed = true end
  if settings.thumbnail_height > 180 then settings.thumbnail_height = 180; changed = true end
  settings.show_screenshots = settings.show_screenshots ~= false
  settings.preserve_chunks = settings.preserve_chunks ~= false
  settings.clear_after_commit = settings.clear_after_commit == true
  if changed and app.save_settings then app.save_settings() end
  return settings
end

local function validate_track(track)
  if not track then return false end
  if r.ValidatePtr2 then return r.ValidatePtr2(0, track, "MediaTrack*") end
  if r.ValidatePtr then return r.ValidatePtr(track, "MediaTrack*") end
  return true
end

local function selected_tracks()
  local tracks = {}
  local master = r.GetMasterTrack(0)
  if master and r.IsTrackSelected and r.IsTrackSelected(master) then tracks[#tracks + 1] = master end
  local count = r.CountSelectedTracks(0) or 0
  for index = 0, count - 1 do
    local track = r.GetSelectedTrack(0, index)
    if validate_track(track) then tracks[#tracks + 1] = track end
  end
  return tracks
end

local function target_label()
  local tracks = selected_tracks()
  if #tracks == 1 and tracks[1] == r.GetMasterTrack(0) then return "MASTER" end
  return tostring(#tracks) .. " selected"
end

local function file_exists(path)
  if r.file_exists then return r.file_exists(path) end
  local file = io.open(path, "rb")
  if file then file:close(); return true end
  return false
end

local function ensure_directory(path)
  if r.RecursiveCreateDirectory then r.RecursiveCreateDirectory(path, 0) end
end

local function normalize_name(value)
  local name = tostring(value or "")
  name = name:gsub("%.[Pp][Nn][Gg]$", "")
  name = name:gsub("%.[Jj][Pp][Ee]?[Gg]$", "")
  name = name:gsub("%s*%([xX]86%)", "")
  name = name:gsub("%s*%([xX]64%)", "")
  name = name:lower()
  name = name:gsub("^vst3i[%s_:%-]*", "")
  name = name:gsub("^vst3[%s_:%-]*", "")
  name = name:gsub("^vsti[%s_:%-]*", "")
  name = name:gsub("^vst[%s_:%-]*", "")
  name = name:gsub("^jsfx[%s_:%-]*", "")
  name = name:gsub("^js[%s_:%-]*", "")
  name = name:gsub("^clapi[%s_:%-]*", "")
  name = name:gsub("^clap[%s_:%-]*", "")
  name = name:gsub("^aui[%s_:%-]*", "")
  name = name:gsub("^au[%s_:%-]*", "")
  name = name:gsub("^lv2i[%s_:%-]*", "")
  name = name:gsub("^lv2[%s_:%-]*", "")
  name = name:gsub("^[^%w]+", "")
  name = name:gsub("%s+$", "")
  name = name:gsub("%s+", " ")
  return name:gsub("[^%w]+", "")
end

local function build_screenshot_index()
  if state.screenshot_index then return end
  state.screenshot_index = {}
  state.screenshot_missing = {}
  local index = 0
  while true do
    local file_name = r.EnumerateFiles(screenshots_path, index)
    if not file_name then break end
    local lower = file_name:lower()
    if lower:match("%.png$") or lower:match("%.jpe?g$") then
      local base = file_name:gsub("%.[^.]+$", "")
      local key = normalize_name(base)
      if key ~= "" then state.screenshot_index[key] = file_name end
    end
    index = index + 1
  end
end

local function screenshot_image(ctx, plugin_name)
  build_screenshot_index()
  local key = normalize_name(plugin_name)
  if key == "" or state.screenshot_missing[key] then return nil end
  local cached = state.screenshot_cache[key]
  if cached then return cached end
  local file_name = state.screenshot_index and state.screenshot_index[key]
  if not file_name then state.screenshot_missing[key] = true; return nil end
  local path = screenshots_path .. file_name
  if not file_exists(path) then state.screenshot_missing[key] = true; return nil end
  local ok, image = false, nil
  if r.ImGui_CreateImage then ok, image = pcall(r.ImGui_CreateImage, path) end
  if not ok or not image then state.screenshot_missing[key] = true; return nil end
  if r.ImGui_Attach and not pcall(r.ImGui_Attach, ctx, image) then
    if r.ImGui_DestroyImage then pcall(r.ImGui_DestroyImage, image) end
    state.screenshot_missing[key] = true
    return nil
  end
  state.screenshot_cache[key] = image
  return image
end

local function detach_images(ctx)
  if not r.ImGui_Detach then state.screenshot_cache = {}; return end
  for _, image in pairs(state.screenshot_cache) do
    if image then pcall(r.ImGui_Detach, ctx, image) end
  end
  state.screenshot_cache = {}
end

local function display_name(plugin_name)
  local text = tostring(plugin_name or "")
  text = text:gsub("^VST3i?:%s*", "")
  text = text:gsub("^VSTi?:%s*", "")
  text = text:gsub("^CLAPi?:%s*", "")
  text = text:gsub("^JS:%s*", "")
  text = text:gsub("^AU:%s*", "")
  text = text:gsub("^LV2:%s*", "")
  return text ~= "" and text or tostring(plugin_name or "FX")
end

local function truncate_text(ctx, text, max_width)
  text = tostring(text or "")
  if r.ImGui_CalcTextSize(ctx, text) <= max_width then return text end
  while #text > 3 and r.ImGui_CalcTextSize(ctx, text .. "...") > max_width do
    text = text:sub(1, -2)
  end
  return text .. "..."
end

local function add_plugin(app, settings, plugin_name, chunk, index)
  if type(plugin_name) ~= "string" or plugin_name == "" then return end
  ensure_chunk_slots()
  index = tonumber(index) or (#state.plugins + 1)
  if index < 1 then index = 1 end
  if index > #state.plugins + 1 then index = #state.plugins + 1 end
  table.insert(state.plugins, index, plugin_name)
  table.insert(state.chunks, index, chunk or false)
  save_plugin_settings(app, settings)
  app.status = "Added to Chain Builder: " .. display_name(plugin_name)
end

local function remove_plugin(app, settings, index)
  if not state.plugins[index] then return end
  local removed = state.plugins[index]
  table.remove(state.plugins, index)
  table.remove(state.chunks, index)
  save_plugin_settings(app, settings)
  app.status = "Removed from Chain Builder: " .. display_name(removed)
end

local function move_plugin(app, settings, source, destination)
  source = tonumber(source)
  destination = tonumber(destination)
  if not source or not destination or source == destination then return end
  if source < 1 or source > #state.plugins or destination < 1 or destination > #state.plugins then return end
  ensure_chunk_slots()
  local plugin = table.remove(state.plugins, source)
  local chunk = table.remove(state.chunks, source)
  if chunk == nil then chunk = false end
  table.insert(state.plugins, destination, plugin)
  table.insert(state.chunks, destination, chunk)
  save_plugin_settings(app, settings)
end

local function add_fx_to_track(track, plugin_name)
  if not validate_track(track) or type(plugin_name) ~= "string" or plugin_name == "" then return -1 end
  local dest_index = r.TrackFX_GetCount(track)
  local fx_index = r.TrackFX_AddByName(track, plugin_name, false, -1000 - dest_index)
  return fx_index or -1
end

local function find_fx_block_bounds(chunk, chain_tag, fx_index)
  local chain_start = chunk and chunk:find("<" .. chain_tag .. "\n")
  if not chain_start then return nil end
  local depth = 0
  local count = -1
  local target_start, target_depth
  for index = chain_start, #chunk do
    local char = chunk:sub(index, index)
    if char == "<" then
      depth = depth + 1
      if depth == 2 and not target_start then
        count = count + 1
        if count == fx_index then
          target_start = index
          target_depth = depth
        end
      end
    elseif char == ">" then
      if target_start and depth == target_depth then return target_start, index end
      depth = depth - 1
      if depth == 0 then break end
    end
  end
  return nil
end

local function restore_chunk(track, fx_index, saved_chunk)
  if not validate_track(track) or not saved_chunk or fx_index < 0 then return false end
  local ok, chunk = r.GetTrackStateChunk(track, "", false)
  if not ok or not chunk then return false end
  local block_start, block_end = find_fx_block_bounds(chunk, "FXCHAIN", fx_index)
  if not block_start or not block_end then return false end
  local new_chunk = chunk:sub(1, block_start - 1) .. saved_chunk .. chunk:sub(block_end + 1)
  return r.SetTrackStateChunk(track, new_chunk, false) == true
end

local function grab_chunks(track)
  local chunks = {}
  if not validate_track(track) then return chunks end
  local ok, chunk = r.GetTrackStateChunk(track, "", false)
  if not ok or not chunk then return chunks end
  local fx_count = r.TrackFX_GetCount(track)
  for fx_index = 0, fx_count - 1 do
    local block_start, block_end = find_fx_block_bounds(chunk, "FXCHAIN", fx_index)
    if block_start and block_end then chunks[fx_index + 1] = chunk:sub(block_start, block_end) end
  end
  return chunks
end

local function parse_fx_chain_file(chain_path)
  if state.fx_chain_cache[chain_path] then return copy_list(state.fx_chain_cache[chain_path]) end
  local plugins = {}
  local file = io.open(chain_path, "r")
  if not file then return plugins end
  for line in file:lines() do
    local vst = line:match('^<VST%s+"([^"]+)"')
    local js = line:match('^<JS%s+([^%s"]+)')
    local clap = line:match('^<CLAP%s+"([^"]+)"')
    local au = line:match('^<AU%s+"([^"]+)"')
    if vst then plugins[#plugins + 1] = vst end
    if js then plugins[#plugins + 1] = "JS: " .. js end
    if clap then plugins[#plugins + 1] = clap end
    if au then plugins[#plugins + 1] = au end
  end
  file:close()
  state.fx_chain_cache[chain_path] = copy_list(plugins)
  return plugins
end

local function resolve_fx_chains_root()
  local custom = r.GetExtState("TKFXB", "custom_fxchain_dir")
  if custom and custom ~= "" then return custom end
  return r.GetResourcePath() .. os_separator .. "FXChains"
end

local function extract_fxchain_block(track)
  if not validate_track(track) then return nil end
  local ok, chunk = r.GetTrackStateChunk(track, "", false)
  if not ok or not chunk then return nil end
  local fxchain_start = chunk:find("<FXCHAIN")
  if not fxchain_start then return nil end
  local depth = 0
  for index = fxchain_start, #chunk do
    local char = chunk:sub(index, index)
    if char == "<" then
      depth = depth + 1
    elseif char == ">" then
      depth = depth - 1
      if depth == 0 then return chunk:sub(fxchain_start, index) end
    end
  end
  return nil
end

local function apply_chain_to_track(track, replace_existing, preserve_chunks)
  if not validate_track(track) or #state.plugins == 0 then return 0 end
  if replace_existing then
    for fx_index = r.TrackFX_GetCount(track) - 1, 0, -1 do r.TrackFX_Delete(track, fx_index) end
  end
  local added = 0
  for index, plugin_name in ipairs(state.plugins) do
    local fx_index = add_fx_to_track(track, plugin_name)
    if fx_index >= 0 then
      added = added + 1
      if preserve_chunks and state.chunks[index] then restore_chunk(track, fx_index, state.chunks[index]) end
    end
  end
  return added
end

local function commit_chain(app, settings, replace_existing)
  local tracks = selected_tracks()
  if #tracks == 0 then app.status = "No selected tracks"; return end
  if #state.plugins == 0 then app.status = "Chain Builder is empty"; return end
  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)
  local added = 0
  for _, track in ipairs(tracks) do added = added + apply_chain_to_track(track, replace_existing, settings.preserve_chunks ~= false) end
  r.PreventUIRefresh(-1)
  r.Undo_EndBlock(replace_existing and "FX Chain Builder: Replace chain" or "FX Chain Builder: Commit chain", -1)
  app.status = (replace_existing and "Replaced" or "Committed") .. " chain to " .. tostring(#tracks) .. " track(s), " .. tostring(added) .. " FX"
  if settings.clear_after_commit then
    state.plugins = {}
    state.chunks = {}
    save_plugin_settings(app, settings)
  end
end

local function save_chain(app, settings)
  if #state.plugins == 0 then app.status = "Chain Builder is empty"; return end
  local chain_dir = resolve_fx_chains_root()
  local track_count = r.CountTracks(0)
  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)
  r.InsertTrackAtIndex(track_count, false)
  local temp_track = r.GetTrack(0, track_count)
  local block
  if temp_track then
    apply_chain_to_track(temp_track, true, settings.preserve_chunks ~= false)
    block = extract_fxchain_block(temp_track)
    r.DeleteTrack(temp_track)
  end
  r.PreventUIRefresh(-1)
  r.Undo_EndBlock("FX Chain Builder: Save chain", -1)
  if not block then app.status = "Could not build FX chain file"; return end
  local name = "Chain Builder " .. os.date("%Y-%m-%d_%H-%M-%S") .. ".RfxChain"
  local path = chain_dir .. os_separator .. name
  ensure_directory(chain_dir)
  local file = io.open(path, "w")
  if not file then app.status = "Could not write " .. path; return end
  file:write(block .. "\n")
  file:close()
  app.status = "Saved FX chain: " .. name
end

local function load_chain(app, settings)
  local ok, path
  if r.JS_Dialog_BrowseForOpenFiles then
    ok, path = r.JS_Dialog_BrowseForOpenFiles("Load FX Chain", resolve_fx_chains_root(), "", "FX Chain (*.RfxChain)\0*.RfxChain\0All Files (*.*)\0*.*\0", false)
  else
    ok, path = r.GetUserFileNameForRead("", "Load FX Chain", ".RfxChain")
  end
  if not (ok == 1 or ok == true) or not path or path == "" then return end
  local loaded = parse_fx_chain_file(path)
  if #loaded == 0 then app.status = "No FX found in chain"; return end
  for _, plugin_name in ipairs(loaded) do
    state.plugins[#state.plugins + 1] = plugin_name
    state.chunks[#state.chunks + 1] = false
  end
  save_plugin_settings(app, settings)
  app.status = "Loaded " .. tostring(#loaded) .. " FX from chain"
end

local function grab_selected_track(app, settings)
  local track = r.GetSelectedTrack(0, 0) or r.GetMasterTrack(0)
  if not validate_track(track) then app.status = "No track to grab"; return end
  local fx_count = r.TrackFX_GetCount(track)
  if fx_count == 0 then app.status = "Track has no FX"; return end
  state.plugins = {}
  state.chunks = grab_chunks(track)
  for fx_index = 0, fx_count - 1 do
    local ok, fx_name = r.TrackFX_GetFXName(track, fx_index, "")
    if ok and fx_name and fx_name ~= "" then state.plugins[#state.plugins + 1] = fx_name end
  end
  save_plugin_settings(app, settings)
  app.status = "Grabbed " .. tostring(#state.plugins) .. " FX"
end

local function clear_chain(app, settings)
  state.plugins = {}
  state.chunks = {}
  save_plugin_settings(app, settings)
  app.status = "Chain Builder cleared"
end

local function apply_pending_action(app, settings, action)
  if not action then return end
  if action.type == "add" then add_plugin(app, settings, action.plugin, false, action.index) end
  if action.type == "move" then move_plugin(app, settings, action.source, action.destination) end
  if action.type == "remove" then remove_plugin(app, settings, action.index) end
end

local function draw_thumbnail(ctx, draw_list, settings, plugin_name, x, y, width, height)
  r.ImGui_DrawList_AddRectFilled(draw_list, x, y, x + width, y + height, Theme.colors.frame_bg, 4)
  local image = settings.show_screenshots and screenshot_image(ctx, plugin_name) or nil
  if image then
    local image_w, image_h = r.ImGui_Image_GetSize(image)
    if image_w and image_h and image_w > 0 and image_h > 0 then
      local inset = 5
      local inner_w = width - inset * 2
      local inner_h = height - inset * 2
      local scale = math.min(inner_w / image_w, inner_h / image_h)
      local draw_w = image_w * scale
      local draw_h = image_h * scale
      local draw_x = x + inset + (inner_w - draw_w) * 0.5
      local draw_y = y + inset + (inner_h - draw_h) * 0.5
      r.ImGui_DrawList_AddImage(draw_list, image, draw_x, draw_y, draw_x + draw_w, draw_y + draw_h, 0, 0, 1, 1, 0xFFFFFFFF)
    end
  else
    local label = truncate_text(ctx, display_name(plugin_name), width - 10)
    local text_w = r.ImGui_CalcTextSize(ctx, label)
    r.ImGui_DrawList_AddText(draw_list, x + (width - text_w) * 0.5, y + (height - r.ImGui_GetTextLineHeight(ctx)) * 0.5, Theme.colors.text_dim, label)
  end
end

local function draw_chain_item(app, settings, plugin_name, index, width, thumb_h)
  local ctx = app.ctx
  local draw_list = r.ImGui_GetWindowDrawList(ctx)
  local item_h = math.max(58, math.min(thumb_h, 118))
  local thumb_w = math.min(math.floor(item_h * 1.35), math.max(64, math.floor(width * 0.42)))
  local text_x_pad = 10
  local pending_action = nil
  r.ImGui_PushID(ctx, "fcb_item_" .. tostring(index))
  local clicked = r.ImGui_InvisibleButton(ctx, "##item", width, item_h)
  local hovered = r.ImGui_IsItemHovered(ctx)
  local x, y = r.ImGui_GetItemRectMin(ctx)
  r.ImGui_DrawList_AddRectFilled(draw_list, x, y, x + width, y + item_h, Theme.colors.child_bg, 5)
  draw_thumbnail(ctx, draw_list, settings, plugin_name, x + 4, y + 4, thumb_w - 8, item_h - 8)
  r.ImGui_DrawList_AddRect(draw_list, x, y, x + width, y + item_h, hovered and Theme.colors.accent or Theme.colors.border, 5, 0, hovered and 2 or 1)
  local num = tostring(index)
  local num_w = r.ImGui_CalcTextSize(ctx, num)
  r.ImGui_DrawList_AddRectFilled(draw_list, x + 5, y + 5, x + num_w + 13, y + 21, 0x000000B0, 3)
  r.ImGui_DrawList_AddText(draw_list, x + 9, y + 7, Theme.colors.accent, num)
  local text_x = x + thumb_w + text_x_pad
  local text_w = math.max(24, width - thumb_w - text_x_pad - 8)
  local label = truncate_text(ctx, display_name(plugin_name), text_w)
  r.ImGui_DrawList_AddText(draw_list, text_x, y + 10, Theme.colors.text, label)
  local full = truncate_text(ctx, plugin_name, text_w)
  r.ImGui_DrawList_AddText(draw_list, text_x, y + 10 + r.ImGui_GetTextLineHeight(ctx) + 4, Theme.colors.text_dim, full)
  if clicked then app.status = plugin_name end
  if r.ImGui_BeginDragDropSource(ctx, r.ImGui_DragDropFlags_SourceNoPreviewTooltip()) then
    r.ImGui_SetDragDropPayload(ctx, "TK_WORKBENCH_CHAIN_REORDER", tostring(index))
    r.ImGui_Text(ctx, display_name(plugin_name))
    r.ImGui_EndDragDropSource(ctx)
  end
  if r.ImGui_BeginDragDropTarget(ctx) then
    local ok_plugin, payload_plugin = r.ImGui_AcceptDragDropPayload(ctx, "TK_WORKBENCH_FX_PLUGIN")
    if ok_plugin and payload_plugin and payload_plugin ~= "" then pending_action = { type = "add", plugin = payload_plugin, index = index } end
    local ok_reorder, payload_reorder = r.ImGui_AcceptDragDropPayload(ctx, "TK_WORKBENCH_CHAIN_REORDER")
    if ok_reorder then pending_action = { type = "move", source = tonumber(payload_reorder), destination = index } end
    r.ImGui_EndDragDropTarget(ctx)
  end
  if r.ImGui_BeginPopupContextItem(ctx, "##item_menu") then
    if r.ImGui_MenuItem(ctx, "Remove") then pending_action = { type = "remove", index = index } end
    r.ImGui_EndPopup(ctx)
  end
  if hovered then r.ImGui_SetTooltip(ctx, plugin_name .. "\nRight-click to remove | Drag to reorder") end
  r.ImGui_PopID(ctx)
  return pending_action
end

local function draw_chain_strip(app, settings)
  local ctx = app.ctx
  local avail_w, avail_h = r.ImGui_GetContentRegionAvail(ctx)
  local thumb_h = settings.thumbnail_height or defaults.thumbnail_height
  local item_h = math.max(58, math.min(thumb_h, 118))
  local add_button_h = 44
  local strip_h = math.max(190, (avail_h or 260) - r.ImGui_GetFrameHeight(ctx) - add_button_h - 14)
  local pending_action = nil
  local draw_list = r.ImGui_GetWindowDrawList(ctx)
  local x, y = r.ImGui_GetCursorScreenPos(ctx)
  r.ImGui_DrawList_AddRectFilled(draw_list, x, y, x + avail_w, y + strip_h, Theme.colors.child_bg, 5)
  r.ImGui_DrawList_AddRect(draw_list, x, y, x + avail_w, y + strip_h, Theme.colors.border, 5, 0, 1)
  local child_visible = r.ImGui_BeginChild(ctx, "##fcb_strip", 0, strip_h, 0, 0)
  if child_visible then
    r.ImGui_SetCursorPos(ctx, 8, 8)
    if #state.plugins == 0 then
      local text = "Drag plugins here to build a chain"
      local text_w = r.ImGui_CalcTextSize(ctx, text)
      local drop_w = math.max(1, avail_w - 16)
      local drop_h = math.max(1, strip_h - 16)
      r.ImGui_InvisibleButton(ctx, "##fcb_empty_drop", drop_w, drop_h)
      local drop_hovered = r.ImGui_IsItemHovered(ctx)
      if r.ImGui_BeginDragDropTarget(ctx) then
        local ok_plugin, payload_plugin = r.ImGui_AcceptDragDropPayload(ctx, "TK_WORKBENCH_FX_PLUGIN")
        if ok_plugin and payload_plugin and payload_plugin ~= "" then pending_action = { type = "add", plugin = payload_plugin } end
        r.ImGui_EndDragDropTarget(ctx)
      end
      local text_x = x + math.max(8, (avail_w - text_w) * 0.5)
      local text_y = y + (strip_h - r.ImGui_GetTextLineHeight(ctx)) * 0.5
      r.ImGui_DrawList_AddText(draw_list, text_x, text_y, drop_hovered and Theme.colors.accent or Theme.colors.text_dim, text)
    else
      local item_w = math.max(1, avail_w - 16)
      r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing(), 4, 6)
      for index, plugin_name in ipairs(state.plugins) do
        r.ImGui_SetCursorPosX(ctx, 8)
        local action = draw_chain_item(app, settings, plugin_name, index, item_w, item_h)
        if action and not pending_action then pending_action = action end
      end
      r.ImGui_PopStyleVar(ctx)
    end
    if r.ImGui_BeginDragDropTarget(ctx) then
      local ok_plugin, payload_plugin = r.ImGui_AcceptDragDropPayload(ctx, "TK_WORKBENCH_FX_PLUGIN")
      if ok_plugin and payload_plugin and payload_plugin ~= "" and not pending_action then pending_action = { type = "add", plugin = payload_plugin } end
      r.ImGui_EndDragDropTarget(ctx)
    end
  end
  r.ImGui_EndChild(ctx)
  return pending_action
end

local function draw_add_plugin_button(app)
  local ctx = app.ctx
  local avail_w = r.ImGui_GetContentRegionAvail(ctx)
  local size = 34
  local x = r.ImGui_GetCursorPosX(ctx) + math.max(0, (avail_w - size) * 0.5)
  r.ImGui_SetCursorPosX(ctx, x)
  local draw_list = r.ImGui_GetWindowDrawList(ctx)
  r.ImGui_InvisibleButton(ctx, "##fcb_add_plugin", size, size)
  local hovered = r.ImGui_IsItemHovered(ctx)
  local clicked = r.ImGui_IsItemClicked(ctx, 0)
  local min_x, min_y = r.ImGui_GetItemRectMin(ctx)
  local max_x, max_y = r.ImGui_GetItemRectMax(ctx)
  local cx = (min_x + max_x) * 0.5
  local cy = (min_y + max_y) * 0.5
  local color = hovered and Theme.colors.accent or Theme.colors.border
  r.ImGui_DrawList_AddCircleFilled(draw_list, cx, cy, size * 0.5, Theme.colors.frame_bg, 32)
  r.ImGui_DrawList_AddCircle(draw_list, cx, cy, size * 0.5 - 1, color, 32, hovered and 2 or 1)
  r.ImGui_DrawList_AddLine(draw_list, cx - 7, cy, cx + 7, cy, Theme.colors.text, 2)
  r.ImGui_DrawList_AddLine(draw_list, cx, cy - 7, cx, cy + 7, Theme.colors.text, 2)
  if hovered then r.ImGui_SetTooltip(ctx, "Open Plugin Browser") end
  if clicked then
    app.settings.active_module = "plugin_browser"
    app.status = "Plugin Browser"
    if app.save_settings then app.save_settings() end
  end
end

local function draw_controls(app, settings)
  local ctx = app.ctx
  local button_h = r.ImGui_GetFrameHeight(ctx)
  local avail_w = r.ImGui_GetContentRegionAvail(ctx)
  local gap = 4
  local count_w = 42
  local button_w = math.max(45, math.floor((avail_w - count_w - gap * 7) / 6))
  if r.ImGui_Button(ctx, "Commit##fcb", button_w, button_h) then commit_chain(app, settings, false) end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Add chain to selected track(s)") end
  r.ImGui_SameLine(ctx, 0, gap)
  if r.ImGui_Button(ctx, "Replace##fcb", button_w, button_h) then commit_chain(app, settings, true) end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Replace FX on selected track(s)") end
  r.ImGui_SameLine(ctx, 0, gap)
  if r.ImGui_Button(ctx, "Clear##fcb", button_w, button_h) then clear_chain(app, settings) end
  r.ImGui_SameLine(ctx, 0, gap)
  if r.ImGui_Button(ctx, "Save##fcb", button_w, button_h) then save_chain(app, settings) end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Save chain as .RfxChain") end
  r.ImGui_SameLine(ctx, 0, gap)
  if r.ImGui_Button(ctx, "Load##fcb", button_w, button_h) then load_chain(app, settings) end
  r.ImGui_SameLine(ctx, 0, gap)
  if r.ImGui_Button(ctx, "Grab##fcb", button_w, button_h) then grab_selected_track(app, settings) end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Grab FX from selected track") end
  r.ImGui_SameLine(ctx, 0, gap)
  r.ImGui_Text(ctx, "(" .. tostring(#state.plugins) .. ")")
end

local function draw_settings(ctx, settings, app)
  if not r.ImGui_BeginPopup(ctx, "##fcb_settings") then return end
  local changed, value = r.ImGui_Checkbox(ctx, "Show screenshots", settings.show_screenshots ~= false)
  if changed then settings.show_screenshots = value; if app.save_settings then app.save_settings() end end
  changed, value = r.ImGui_Checkbox(ctx, "Preserve grabbed chunks", settings.preserve_chunks ~= false)
  if changed then settings.preserve_chunks = value; if app.save_settings then app.save_settings() end end
  changed, value = r.ImGui_Checkbox(ctx, "Clear after commit", settings.clear_after_commit == true)
  if changed then settings.clear_after_commit = value; if app.save_settings then app.save_settings() end end
  r.ImGui_SetNextItemWidth(ctx, 150)
  changed, value = r.ImGui_SliderInt(ctx, "Thumbnail height", settings.thumbnail_height or defaults.thumbnail_height, 48, 180, "%d px")
  if changed then settings.thumbnail_height = value; if app.save_settings then app.save_settings() end end
  r.ImGui_EndPopup(ctx)
end

function M.init(app)
  local settings = ensure_settings(app)
  state.plugins = copy_list(settings.plugins)
  state.chunks = {}
  ensure_chunk_slots()
end

function M.draw(app)
  local ctx = app.ctx
  local settings = ensure_settings(app)
  r.ImGui_TextColored(ctx, Theme.colors.accent, "FX Chain Builder")
  r.ImGui_SameLine(ctx)
  r.ImGui_TextColored(ctx, Theme.colors.text_dim, target_label())
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "Settings##fcb") then r.ImGui_OpenPopup(ctx, "##fcb_settings") end
  draw_settings(ctx, settings, app)
  r.ImGui_Separator(ctx)
  local pending_action = draw_chain_strip(app, settings)
  apply_pending_action(app, settings, pending_action)
  r.ImGui_Spacing(ctx)
  draw_add_plugin_button(app)
  r.ImGui_Spacing(ctx)
  draw_controls(app, settings)
end

function M.add_plugin(app, plugin_name)
  local settings = ensure_settings(app)
  add_plugin(app, settings, plugin_name, false)
end

function M.shutdown(app)
  detach_images(app.ctx)
end

return M