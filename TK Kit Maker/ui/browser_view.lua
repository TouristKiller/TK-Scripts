local r = reaper
local Theme = require("core.theme")
local Dialogs = require("core.dialogs")
local Scanner = require("core.scanner")
local Store = require("core.browser_store")
local BuilderView = require("ui.builder_view")
local Presets = require("data.presets")
local Relink = require("core.relink")

local M = {}

local IMAGE_EXT = {
  png = true,
  jpg = true,
  jpeg = true,
  webp = true,
  bmp = true,
  gif = true,
}

local RS5K_BASE_NOTE = 36
local RS5K_MAX_SLOTS = 127 - RS5K_BASE_NOTE + 1
local KIT_RACK_SLOTS = 16

local refresh_collection
local save

local function as_number(value)
  if type(value) == "number" then return value end
  if type(value) == "string" then return tonumber(value) end
  return nil
end

local function is_image_file(path)
  local ext = tostring(path or ""):match("%.([%w]+)$")
  return ext ~= nil and IMAGE_EXT[ext:lower()] == true
end

local function file_leaf(path)
  return tostring(path or ""):match("([^/\\]+)$") or tostring(path or "")
end

local function file_stem(path)
  return file_leaf(path):gsub("%.[%w]+$", "")
end

local function detect_folder_cover(folder)
  folder = Scanner.normalize(folder or "")
  if folder == "" then return nil end

  local best_path = nil
  local best_score = nil
  local i = 0
  while true do
    local fn = r.EnumerateFiles(folder, i)
    if not fn then break end
    local stem = file_stem(fn):lower()
    if stem == "cover" then
      local ext = tostring(fn):match("%.([%w]+)$")
      ext = ext and ext:lower() or ""
      local score = ({ png = 1, jpg = 2, jpeg = 3, webp = 4, bmp = 5, gif = 6 })[ext] or 99
      local path = folder .. "/" .. fn
      if not best_path or score < best_score then
        best_path = path
        best_score = score
      end
    end
    i = i + 1
  end

  return best_path
end

local function normalize_cmp_path(path)
  local p = tostring(path or ""):lower():gsub("\\", "/")
  return p:gsub("/+", "/")
end

local function track_guid(track)
  if not track or not r.GetTrackGUID then return nil end
  return r.GetTrackGUID(track)
end

local function parse_slot_number(text)
  local s = tostring(text or ""):gsub("^%s+", "")
  local n = tonumber(s:match("^(%d+)"))
  if n and n > 0 then return n end
  return nil
end

local function stop_preview(state)
  if state.preview and r.CF_Preview_Stop then
    pcall(r.CF_Preview_Stop, state.preview)
  end
  if state.preview_source and r.PCM_Source_Destroy then
    pcall(r.PCM_Source_Destroy, state.preview_source)
  end
  state.preview = nil
  state.preview_source = nil
  state.preview_path = nil
end

local function selected_collection(app)
  local state = app.browser
  local collections = state.browser_mode == "kits" and state.kit_collections or state.collections
  local selected_id = state.selected_id
  for i, c in ipairs(collections) do
    if c.id == selected_id then
      return c, i
    end
  end
  return nil, nil
end

local function active_collections(state)
  if state.browser_mode == "kits" then
    return state.kit_collections
  end
  return state.collections
end

local function set_selected_collection(state, id)
  state.selected_id = id
  if state.browser_mode == "kits" then
    state.kit_selected_id = id
  else
    state.sample_selected_id = id
  end
end

local function mode_label(state)
  return state.browser_mode == "kits" and "Kit Browser" or "Sample Pack Browser"
end

local function switch_browser_mode(app, mode)
  local state = app.browser
  if mode ~= "packs" and mode ~= "kits" then return end
  if state.browser_mode == mode then return end

  state.browser_mode = mode
  if mode == "kits" then
    set_selected_collection(state, state.kit_selected_id or (state.kit_collections[1] and state.kit_collections[1].id or nil))
  else
    set_selected_collection(state, state.sample_selected_id or (state.collections[1] and state.collections[1].id or nil))
  end
  refresh_collection(app, false)
  save(app)
end

local function collection_key(col)
  return (col.path or ""):lower() .. "|" .. ((col.recursive ~= false) and "1" or "0")
end

save = function(app)
  Store.save(app.browser)
end

local function toolbar_same_line(ctx, next_w, spacing)
  local remain = as_number(r.ImGui_GetContentRegionAvail(ctx)) or 0
  local gap = spacing or 6
  if remain > (next_w + gap) then
    r.ImGui_SameLine(ctx, nil, gap)
    return true
  end
  return false
end

local function ordered_collections(state)
  local ordered = {}
  for _, c in ipairs(active_collections(state)) do
    if c.pinned == true then ordered[#ordered + 1] = c end
  end
  for _, c in ipairs(active_collections(state)) do
    if c.pinned ~= true then ordered[#ordered + 1] = c end
  end
  return ordered
end

local function truncate_text(text, max_chars)
  local s = tostring(text or "")
  local n = as_number(max_chars) or 24
  if n < 4 then n = 4 end
  if #s <= n then return s end
  return s:sub(1, n - 3) .. "..."
end

local function cover_texture(state, path)
  if not path or path == "" then return nil end
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

local function apply_filter(app)
  local state = app.browser
  local col = selected_collection(app)
  if not col then
    state.filtered_files = {}
    state.selected_file = nil
    state.last_scan_label = nil
    return
  end

  local key = collection_key(col)
  local files = state.scan_cache[key] or {}
  state.files = files

  local search = (state.search or ""):lower()
  local fkey = key .. "|" .. search
  local filtered = state.filter_cache[fkey]

  if not filtered then
    if search == "" then
      filtered = files
    else
      filtered = {}
      for _, f in ipairs(files) do
        local leaf = f:match("([^/\\]+)$") or f
        if leaf:lower():find(search, 1, true) then
          filtered[#filtered + 1] = f
        end
      end
    end
    state.filter_cache[fkey] = filtered
  end

  state.filtered_files = filtered
  state.last_scan_label = tostring(#filtered) .. " / " .. tostring(#files)

  local keep = false
  if state.selected_file then
    for _, f in ipairs(filtered) do
      if f == state.selected_file then
        keep = true
        break
      end
    end
  end
  if not keep then
    state.selected_file = filtered[1]
  end
end

refresh_collection = function(app, force_scan)
  local state = app.browser
  stop_preview(state)

  local col = selected_collection(app)
  if not col then
    state.files = {}
    state.filtered_files = {}
    state.selected_file = nil
    state.last_scan_label = nil
    return
  end

  if (not col.cover_path or col.cover_path == "") then
    local auto_cover = detect_folder_cover(col.path)
    if auto_cover then
      col.cover_path = auto_cover
      save(app)
    end
  end

  local key = collection_key(col)
  if force_scan or not state.scan_cache[key] then
    local pool = {
      folders = { col.path },
      recursive = state.browser_mode == "packs" and (col.recursive ~= false) or false,
      files = {},
    }
    state.scan_cache[key] = Scanner.scan_pool(pool)
    state.filter_cache = {}
  end

  apply_filter(app)
end

local function play_preview(app, path)
  local state = app.browser
  local leaf = path and file_leaf(path) or ""
  if not Scanner.is_audio_file(leaf) then
    state.preview_error = "Only audio files can be auditioned."
    return false
  end
  if not r.CF_CreatePreview or not r.CF_Preview_Play then
    state.preview_error = "SWS preview API not available."
    return false
  end

  stop_preview(state)

  local source = r.PCM_Source_CreateFromFile(path)
  if not source then
    state.preview_error = "Could not load preview source."
    return false
  end

  local preview = r.CF_CreatePreview(source)
  if not preview then
    if r.PCM_Source_Destroy then r.PCM_Source_Destroy(source) end
    state.preview_error = "Could not start preview."
    return false
  end

  if r.CF_Preview_SetValue then
    r.CF_Preview_SetValue(preview, "D_VOLUME", state.preview_volume or 1.0)
    r.CF_Preview_SetValue(preview, "B_LOOP", 0)
    r.CF_Preview_SetValue(preview, "D_POSITION", 0)
  end
  r.CF_Preview_Play(preview)

  state.preview = preview
  state.preview_source = source
  state.preview_path = path
  state.preview_error = nil
  return true
end

local function find_rs5k_fx(track)
  local count = r.TrackFX_GetCount(track)
  for i = 0, count - 1 do
    local ok, name = r.TrackFX_GetFXName(track, i, "")
    if ok and name and name:lower():find("reasamplomatic", 1, true) then
      return i
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
  if ok and path and path ~= "" then return tostring(path) end
  return nil
end

local function track_has_sample(track, sample_path)
  if not track then return false end
  local wanted = normalize_cmp_path(sample_path)
  local count = r.TrackFX_GetCount(track)
  for i = 0, count - 1 do
    local loaded = get_rs5k_file(track, i)
    if loaded and normalize_cmp_path(loaded) == wanted then
      return true
    end
  end
  if r.TrackFX_GetRecCount then
    local rec = r.TrackFX_GetRecCount(track)
    for i = 0, rec - 1 do
      local loaded = get_rs5k_file(track, 0x1000000 + i)
      if loaded and normalize_cmp_path(loaded) == wanted then
        return true
      end
    end
  end
  return false
end

local function touched_rs5k_track(sample_path)
  if not r.GetTouchedOrFocusedFX then return nil end
  local ok, tr_idx, item_idx, take_idx, fx_idx = r.GetTouchedOrFocusedFX(1)
  if not ok then return nil end
  if item_idx and item_idx >= 0 then return nil end

  local track = nil
  if tr_idx == -1 then
    track = r.GetMasterTrack(0)
  elseif tr_idx ~= nil and tr_idx >= 0 then
    track = r.GetTrack(0, tr_idx)
  end
  if not track then return nil end

  if fx_idx and fx_idx >= 0 then
    if r.TrackFX_GetParamName then
      local _, parm3_name = r.TrackFX_GetParamName(track, fx_idx, 3, "")
      local _, parm4_name = r.TrackFX_GetParamName(track, fx_idx, 4, "")
      if parm3_name == "Note range start" and parm4_name == "Note range end" then
        return track
      end
    end
    local loaded = get_rs5k_file(track, fx_idx)
    if loaded and normalize_cmp_path(loaded) == normalize_cmp_path(sample_path) then
      return track
    end
  end

  if track_has_sample(track, sample_path) then
    return track
  end
  return nil
end

local function open_rs5k_track_for_sample(sample_path)
  if not r.TrackFX_GetOpen then return nil end
  local count = r.CountTracks(0)
  for i = 0, count - 1 do
    local track = r.GetTrack(0, i)
    local fx_count = r.TrackFX_GetCount(track)
    for fx = 0, fx_count - 1 do
      if r.TrackFX_GetOpen(track, fx) then
        local loaded = get_rs5k_file(track, fx)
        if loaded and normalize_cmp_path(loaded) == normalize_cmp_path(sample_path) then
          return track
        end
      end
    end
  end
  return nil
end

local function collect_tracks_with_sample(sample_path)
  local out = {}
  local count = r.CountTracks(0)
  for i = 0, count - 1 do
    local tr = r.GetTrack(0, i)
    if track_has_sample(tr, sample_path) then
      local guid = track_guid(tr)
      if guid then
        out[guid] = tr
      end
    end
  end
  return out
end

local function collect_rs5k_state_snapshot()
  local out = {}
  local count = r.CountTracks(0)
  for i = 0, count - 1 do
    local tr = r.GetTrack(0, i)
    local guid = track_guid(tr)
    if guid then
      local files = {}
      local fx_count = r.TrackFX_GetCount(tr)
      for fx = 0, fx_count - 1 do
        local loaded = get_rs5k_file(tr, fx)
        if loaded then
          files[#files + 1] = normalize_cmp_path(loaded)
        end
      end
      if r.TrackFX_GetRecCount then
        local rec_count = r.TrackFX_GetRecCount(tr)
        for fx = 0, rec_count - 1 do
          local loaded = get_rs5k_file(tr, 0x1000000 + fx)
          if loaded then
            files[#files + 1] = normalize_cmp_path(loaded)
          end
        end
      end
      table.sort(files)
      out[guid] = {
        track = tr,
        files = table.concat(files, "\n"),
      }
    end
  end
  return out
end

local function resolve_native_drop_track(state, sample_path, track_hint, snapshot_before, state_snapshot_before)
  local focused_track = touched_rs5k_track(sample_path)
  if focused_track then
    return focused_track
  end

  local open_track = open_rs5k_track_for_sample(sample_path)
  if open_track then
    return open_track
  end

  local track = track_hint or state.drag_track_target or r.GetSelectedTrack(0, 0)
  if track and track_has_sample(track, sample_path) then
    return track
  end

  local state_before = state_snapshot_before or state.drag_native_state_snapshot or {}
  local state_now = collect_rs5k_state_snapshot()
  for guid, entry in pairs(state_now) do
    local prev = state_before[guid]
    if track_has_sample(entry.track, sample_path) and ((not prev) or prev.files ~= entry.files) then
      return entry.track
    end
  end

  local now = collect_tracks_with_sample(sample_path)
  local before = snapshot_before or state.drag_native_snapshot or {}
  for guid, tr in pairs(now) do
    if not before[guid] then
      return tr
    end
  end

  for _, tr in pairs(now) do
    return tr
  end
  return nil
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
  if (r.GetMediaTrackInfo_Value(selected, "I_FOLDERDEPTH") or 0) > 0 then
    return selected
  end
  if r.GetParentTrack then
    local parent = r.GetParentTrack(selected)
    if parent and (r.GetMediaTrackInfo_Value(parent, "I_FOLDERDEPTH") or 0) > 0 then
      return parent
    end
  end
  return nil
end

local function collect_rack_slot_usage(parent)
  local used = {}
  local max_used = 0
  each_child_track(parent, function(tr)
    local fx = find_rs5k_fx(tr)
    if fx >= 0 then
      local note = get_rs5k_note(tr, fx)
      if note and note >= RS5K_BASE_NOTE and note <= 127 then
        local slot = (note - RS5K_BASE_NOTE) + 1
        used[slot] = tr
        if slot > max_used then max_used = slot end
      end
    end
  end)
  return used, max_used
end

local function append_child_track_to_folder(parent)
  local parent_depth = r.GetTrackDepth(parent)
  local parent_idx = get_track_index0(parent)
  local track_count = r.CountTracks(0)
  local insert_idx = track_count
  local last_child = nil

  for i = parent_idx + 1, track_count - 1 do
    local tr = r.GetTrack(0, i)
    if r.GetTrackDepth(tr) <= parent_depth then
      insert_idx = i
      break
    end
    last_child = tr
  end

  r.InsertTrackAtIndex(insert_idx, true)
  local child = r.GetTrack(0, insert_idx)

  if last_child then
    local prev_depth = r.GetMediaTrackInfo_Value(last_child, "I_FOLDERDEPTH") or 0
    if prev_depth < 0 then
      r.SetMediaTrackInfo_Value(last_child, "I_FOLDERDEPTH", prev_depth + 1)
    end
  end
  r.SetMediaTrackInfo_Value(child, "I_FOLDERDEPTH", -1)

  return child
end

local function load_sample_into_rs5k(track, sample_path, midi_note)
  local fx = find_rs5k_fx(track)
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
  local fx = find_rs5k_fx(track)
  if fx < 0 then
    fx = r.TrackFX_AddByName(track, "ReaSamplOmatic5000 (Cockos)", false, -1)
  end
  if fx < 0 then return false end
  if midi_note ~= nil then
    local note = math.max(0, math.min(127, math.floor(tonumber(midi_note) or 0)))
    local normalized = note / 127
    r.TrackFX_SetParamNormalized(track, fx, 3, normalized)
    r.TrackFX_SetParamNormalized(track, fx, 4, normalized)
  end
  return true
end

local function load_sample_to_rack_slot(app, parent_track, sample_path, slot)
  local state = app.browser
  local slot_n = math.floor(tonumber(slot) or 0)
  if slot_n < 1 or slot_n > RS5K_MAX_SLOTS then
    state.preview_error = "Invalid target slot."
    return false
  end

  local used = collect_rack_slot_usage(parent_track)
  local target_track = used[slot_n]
  local note = RS5K_BASE_NOTE + (slot_n - 1)

  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)

  if not target_track then
    target_track = append_child_track_to_folder(parent_track)
  end

  local ok = target_track and load_sample_into_rs5k(target_track, sample_path, note)
  if ok and target_track then
    r.GetSetMediaTrackInfo_String(target_track, "P_NAME", file_stem(sample_path), true)
  end

  r.PreventUIRefresh(-1)

  if ok then
    r.TrackList_AdjustWindows(false)
    r.UpdateArrange()
    r.Undo_EndBlock("TK Kit Maker: Load sample to RS5K rack slot", -1)
    state.preview_error = nil
    return true
  end

  r.Undo_EndBlock("TK Kit Maker: Load sample to RS5K rack slot (failed)", -1)
  state.preview_error = "Could not load sample into rack slot."
  return false
end

local function start_external_file_drag(app, file_path)
  local state = app.browser
  if not r.TK_StartFileDrag then
    state.preview_error = "TK Native Helper is not installed. Install 'reaper_tk_native_helper' via ReaPack (Extensions) and restart REAPER."
    return false
  end
  local ok = pcall(r.TK_StartFileDrag, file_path)
  if ok then
    state.preview_error = nil
    return true
  end
  state.preview_error = "Could not start external file drag."
  return false
end

local function ensure_selected_track()
  local track = r.GetSelectedTrack(0, 0)
  if track then return track end
  local idx = r.CountTracks(0)
  r.InsertTrackAtIndex(idx, true)
  track = r.GetTrack(0, idx)
  if track then
    r.SetOnlyTrackSelected(track)
  end
  return track
end

local function load_sample_to_selected_rs5k(app, sample_path)
  local state = app.browser
  local track = ensure_selected_track()
  if not track then
    state.preview_error = "Could not find or create target track."
    return false
  end
  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)
  local ok = load_sample_into_rs5k(track, sample_path)
  if ok then
    local sample_name = file_leaf(sample_path):gsub("%.[%w]+$", "")
    r.GetSetMediaTrackInfo_String(track, "P_NAME", sample_name, true)
  end
  r.PreventUIRefresh(-1)
  if ok then
    r.TrackList_AdjustWindows(false)
    r.UpdateArrange()
    r.Undo_EndBlock("TK Kit Maker: Load sample to RS5K", -1)
    state.preview_error = nil
    return true
  end
  r.Undo_EndBlock("TK Kit Maker: Load sample to RS5K (failed)", -1)
  state.preview_error = "Could not load sample into RS5K."
  return false
end

local function load_sample_to_track(track, sample_path)
  if not track then return false end
  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)
  local ok = load_sample_into_rs5k(track, sample_path)
  if ok then
    local sample_name = file_leaf(sample_path):gsub("%.[%w]+$", "")
    r.GetSetMediaTrackInfo_String(track, "P_NAME", sample_name, true)
  end
  r.PreventUIRefresh(-1)
  if ok then
    r.TrackList_AdjustWindows(false)
    r.UpdateArrange()
    r.Undo_EndBlock("TK Kit Maker: Load sample to track", -1)
    return true
  end
  r.Undo_EndBlock("TK Kit Maker: Load sample to track (failed)", -1)
  return false
end

function M.update_drag_drop(app)
  local state = app.browser
  if not state or not state.drag_sample_path then return end

  local mouse_down = false
  if r.JS_Mouse_GetState then
    mouse_down = ((r.JS_Mouse_GetState(1) or 0) & 1) ~= 0
  elseif r.ImGui_IsMouseDown then
    mouse_down = r.ImGui_IsMouseDown(app.ctx, 0) == true
  end

  if mouse_down then
    state.drag_mouse_was_down = true
    state.drag_release_seen = false
    if r.GetTrackFromPoint and r.GetMousePosition then
      local mx, my = r.GetMousePosition()
      state.drag_track_target = select(1, r.GetTrackFromPoint(mx, my))
    end
    return
  end

  if not state.drag_mouse_was_down then
    return
  end

  state.drag_release_seen = true
  state.drag_mouse_was_down = false
end

function M.commit_track_drop(app)
  local state = app.browser
  if not state then return end

  if state.drag_native_pending_path then
    local native_track = resolve_native_drop_track(state, state.drag_native_pending_path, state.drag_native_pending_track, state.drag_native_pending_snapshot, state.drag_native_pending_state_snapshot)
    if native_track then
      local sample_name = file_leaf(state.drag_native_pending_path):gsub("%.[%w]+$", "")
      r.GetSetMediaTrackInfo_String(native_track, "P_NAME", sample_name, true)
      state.drag_native_pending_path = nil
      state.drag_native_pending_track = nil
      state.drag_native_pending_snapshot = nil
      state.drag_native_pending_state_snapshot = nil
      state.drag_native_pending_tries = 0
    else
      state.drag_native_pending_tries = math.max(0, (state.drag_native_pending_tries or 0) - 1)
      if state.drag_native_pending_tries == 0 then
        state.drag_native_pending_path = nil
        state.drag_native_pending_track = nil
        state.drag_native_pending_snapshot = nil
        state.drag_native_pending_state_snapshot = nil
      end
    end
  end

  if not state.drag_sample_path or not state.drag_release_seen then return end

  local sample_path = tostring(state.drag_sample_path or "")
  local track = state.drag_track_target or r.GetSelectedTrack(0, 0)

  if state.drag_native_mode then
    local native_track = resolve_native_drop_track(state, sample_path, track, state.drag_native_snapshot, state.drag_native_state_snapshot)
    if native_track then
      local sample_name = file_leaf(sample_path):gsub("%.[%w]+$", "")
      r.GetSetMediaTrackInfo_String(native_track, "P_NAME", sample_name, true)
    else
      state.drag_native_pending_path = sample_path
      state.drag_native_pending_track = track
      state.drag_native_pending_snapshot = state.drag_native_snapshot
      state.drag_native_pending_state_snapshot = state.drag_native_state_snapshot
      state.drag_native_pending_tries = 30
    end
  else
    if track and load_sample_to_track(track, sample_path) then
      state.drag_sample_path = nil
    end
  end

  state.drag_sample_path = nil
  state.drag_release_seen = false
  state.drag_mouse_was_down = false
  state.drag_track_target = nil
  state.drag_native_mode = false
  state.drag_native_snapshot = nil
  state.drag_native_state_snapshot = nil
end

local function create_rs5k_drum_rack_from_collection(app)
  local state = app.browser
  local col = selected_collection(app)
  if not col then
    state.preview_error = "No kit collection selected."
    return false
  end

  local key = collection_key(col)
  local scanned = state.scan_cache[key]
  if not scanned then
    refresh_collection(app, true)
    scanned = state.scan_cache[key]
  end
  if not scanned or #scanned == 0 then
    state.preview_error = "No audio files found in this kit collection."
    return false
  end

  local files = {}
  for i = 1, #scanned do
    files[i] = scanned[i]
  end
  table.sort(files, function(a, b)
    return file_leaf(a):lower() < file_leaf(b):lower()
  end)

  local total_files = #files
  local mapped = {}
  local used_slots = {}
  local next_slot = 1

  for _, sample_path in ipairs(files) do
    local slot = parse_slot_number(file_stem(sample_path))
    if not slot or slot < 1 or slot > RS5K_MAX_SLOTS or used_slots[slot] then
      while next_slot <= RS5K_MAX_SLOTS and used_slots[next_slot] do
        next_slot = next_slot + 1
      end
      slot = next_slot
    end
    if not slot or slot > RS5K_MAX_SLOTS then
      break
    end
    used_slots[slot] = true
    mapped[#mapped + 1] = {
      sample_path = sample_path,
      sample_name = file_stem(sample_path),
      slot = slot,
      midi_note = RS5K_BASE_NOTE + (slot - 1),
    }
  end

  table.sort(mapped, function(a, b)
    return a.slot < b.slot
  end)

  if #mapped == 0 then
    state.preview_error = "No mappable samples found for RS5K rack."
    return false
  end

  local insert_after = r.GetSelectedTrack(0, 0)
  local base_index = insert_after and r.GetMediaTrackInfo_Value(insert_after, "IP_TRACKNUMBER") or r.CountTracks(0)
  base_index = math.floor(base_index)

  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)

  r.InsertTrackAtIndex(base_index, true)
  local folder_track = r.GetTrack(0, base_index)
  local folder_name = col.name ~= "" and col.name or file_leaf(col.path)
  r.GetSetMediaTrackInfo_String(folder_track, "P_NAME", folder_name .. " Rack", true)
  r.SetMediaTrackInfo_Value(folder_track, "I_FOLDERDEPTH", 1)

  local mapped_by_slot = {}
  local max_slot = 0
  for _, item in ipairs(mapped) do
    mapped_by_slot[item.slot] = item
    if item.slot > max_slot then max_slot = item.slot end
  end
  local rack_slots = math.max(KIT_RACK_SLOTS, max_slot)

  for slot = 1, rack_slots do
    local idx = base_index + slot
    r.InsertTrackAtIndex(idx, true)
    local tr = r.GetTrack(0, idx)
    local item = mapped_by_slot[slot]
    local midi_note = RS5K_BASE_NOTE + (slot - 1)
    if item then
      r.GetSetMediaTrackInfo_String(tr, "P_NAME", item.sample_name, true)
      load_sample_into_rs5k(tr, item.sample_path, midi_note)
    else
      r.GetSetMediaTrackInfo_String(tr, "P_NAME", string.format("Pad %02d", slot), true)
      create_empty_rs5k(tr, midi_note)
    end
    if slot == rack_slots then
      r.SetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH", -1)
    else
      r.SetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH", 0)
    end
  end

  r.PreventUIRefresh(-1)
  r.TrackList_AdjustWindows(false)
  r.UpdateArrange()
  r.Undo_EndBlock("TK Kit Maker: Create RS5K drum rack from kit", -1)
  if total_files > #mapped then
    state.preview_error = "Rack created with " .. tostring(#mapped) .. " mapped samples."
  else
    state.preview_error = nil
  end
  return true
end

local function add_collection(app)
  local folder = Dialogs.browse_folder("Select sample folder", "")
  if not folder then return end

  local state = app.browser
  local norm = Scanner.normalize(folder)
  for _, c in ipairs(state.collections) do
    if c.path:lower() == norm:lower() then
      state.selected_id = c.id
      refresh_collection(app, false)
      save(app)
      return
    end
  end

  local name = norm:match("([^/]+)$") or norm
  local id = "col_" .. tostring(math.floor((r.time_precise and r.time_precise() or os.clock()) * 1000)) .. "_" .. tostring(#state.collections + 1)
  local cover_path = detect_folder_cover(norm)
  local collections = active_collections(state)
  collections[#collections + 1] = {
    id = id,
    name = name,
    path = norm,
    recursive = true,
    pinned = false,
    cover_path = cover_path,
  }
  set_selected_collection(state, id)
  save(app)
  refresh_collection(app, false)
end

local function remove_selected_collection(app)
  local state = app.browser
  local col, idx = selected_collection(app)
  if not idx then return end

  if col then
    local key = collection_key(col)
    state.scan_cache[key] = nil
    local prefix = key .. "|"
    for k in pairs(state.filter_cache) do
      if k:sub(1, #prefix) == prefix then
        state.filter_cache[k] = nil
      end
    end
  end

  local collections = active_collections(state)
  table.remove(collections, idx)
  local next_id = collections[1] and collections[1].id or nil
  set_selected_collection(state, next_id)
  save(app)
  refresh_collection(app, false)
end

local function ensure_builder_state(app)
  if not app.kitdef then
    app.kitdef = BuilderView.new_kitdef()
    app.pools = {}
    app.builder.pool_order = {}
  end
end

local function add_collection_as_pool(app)
  local col = selected_collection(app)
  if not col then return end

  ensure_builder_state(app)

  local id = "pool_" .. tostring(app.builder.next_pool_n)
  app.builder.next_pool_n = app.builder.next_pool_n + 1

  app.pools[id] = {
    id = id,
    alias = col.name,
    folders = { col.path },
    recursive = col.recursive ~= false,
    files = {},
    mode = "repeat",
    _bag = {},
  }
  app.builder.pool_order[#app.builder.pool_order + 1] = id
  Scanner.scan_pool(app.pools[id])
  app.view = "builder"
end

local function use_collection_as_explosion_source(app)
  local col = selected_collection(app)
  if not col then return end

  app.explosion.source_folder = col.path
  app.explosion.recursive = col.recursive ~= false
  app.explosion.found_files = nil
  app.explosion.result = nil
  app.view = "explosion"
end

local function collection_index_by_id(collections, id)
  for i, c in ipairs(collections) do
    if c.id == id then return i end
  end
  return nil
end

local function draw_collection_context_menu(app, col)
  local ctx = app.ctx
  local state = app.browser
  local collections = active_collections(state)
  local idx = collection_index_by_id(collections, col.id)
  local is_packs = state.browser_mode == "packs"
  local rename_key = "rename##" .. col.id

  if r.ImGui_BeginPopup(ctx, "##col_ctx_" .. col.id) then
    r.ImGui_SetNextItemWidth(ctx, 240)
    local n_changed, n_value = r.ImGui_InputText(ctx, rename_key, col.name or "")
    if n_changed then
      local clean = n_value:gsub("^%s+", ""):gsub("%s+$", "")
      if clean ~= "" then
        col.name = clean
        save(app)
      end
    end

    local p_changed, p_value = r.ImGui_Checkbox(ctx, "Pin##" .. col.id, col.pinned == true)
    if p_changed then
      col.pinned = p_value
      save(app)
    end

    if is_packs then
      local r_changed, r_value = r.ImGui_Checkbox(ctx, "Include subfolders##" .. col.id, col.recursive ~= false)
      if r_changed then
        col.recursive = r_value
        save(app)
        if state.selected_id == col.id then
          refresh_collection(app, true)
        end
      end
    end

    r.ImGui_BeginDisabled(ctx, not idx or idx <= 1)
    if r.ImGui_MenuItem(ctx, "Move Up##" .. col.id) then
      collections[idx], collections[idx - 1] = collections[idx - 1], collections[idx]
      save(app)
    end
    r.ImGui_EndDisabled(ctx)

    r.ImGui_BeginDisabled(ctx, not idx or idx >= #collections)
    if r.ImGui_MenuItem(ctx, "Move Down##" .. col.id) then
      collections[idx], collections[idx + 1] = collections[idx + 1], collections[idx]
      save(app)
    end
    r.ImGui_EndDisabled(ctx)

    r.ImGui_Separator(ctx)

    if is_packs then
      if r.ImGui_MenuItem(ctx, "Use for Explosion##" .. col.id) then
        state.selected_id = col.id
        set_selected_collection(state, col.id)
        save(app)
        use_collection_as_explosion_source(app)
      end
      if r.ImGui_MenuItem(ctx, "Add as Builder Pool##" .. col.id) then
        set_selected_collection(state, col.id)
        save(app)
        add_collection_as_pool(app)
      end
      if r.ImGui_MenuItem(ctx, "Switch to Sample Kits##" .. col.id) then
        switch_browser_mode(app, "kits")
      end
    else
      if r.ImGui_MenuItem(ctx, "Switch to Sample Packs##" .. col.id) then
        switch_browser_mode(app, "packs")
      end
      if r.ImGui_MenuItem(ctx, "Create Drum Rack (RS5K)##" .. col.id) then
        state.selected_id = col.id
        set_selected_collection(state, col.id)
        save(app)
        create_rs5k_drum_rack_from_collection(app)
      end
    end

    r.ImGui_Separator(ctx)

    if r.ImGui_MenuItem(ctx, "Set Cover##" .. col.id) then
      local image = Dialogs.browse_file("Select collection cover", col.cover_path or col.path, "")
      if image then
        if is_image_file(image) then
          if col.cover_path and state.cover_cache[col.cover_path] then
            state.cover_cache[col.cover_path] = nil
          end
          col.cover_path = image
          state.cover_cache[image] = nil
          state.preview_error = nil
          save(app)
        else
          state.preview_error = "Selected file is not a supported image."
        end
      end
    end

    r.ImGui_BeginDisabled(ctx, not col.cover_path)
    if r.ImGui_MenuItem(ctx, "Clear Cover##" .. col.id) then
      if col.cover_path and state.cover_cache[col.cover_path] then
        state.cover_cache[col.cover_path] = nil
      end
      col.cover_path = nil
      save(app)
    end
    r.ImGui_EndDisabled(ctx)

    r.ImGui_BeginDisabled(ctx, not col.cover_path or not r.CF_ShellExecute)
    if r.ImGui_MenuItem(ctx, "Open Cover##" .. col.id) then
      r.CF_ShellExecute(col.cover_path)
    end
    r.ImGui_EndDisabled(ctx)

    if r.CF_ShellExecute and r.ImGui_MenuItem(ctx, "Open Folder##" .. col.id) then
      r.CF_ShellExecute(col.path)
    end

    r.ImGui_Separator(ctx)
    if r.ImGui_MenuItem(ctx, "Remove Collection##" .. col.id) then
      state.selected_id = col.id
      remove_selected_collection(app)
      r.ImGui_CloseCurrentPopup(ctx)
    end

    r.ImGui_EndPopup(ctx)
  end
end

local function draw_sample_row(app, file_path)
  local ctx = app.ctx
  local state = app.browser
  local leaf = file_leaf(file_path)
  local selected = state.selected_file == file_path

  if r.ImGui_Selectable(ctx, leaf .. "##" .. file_path, selected) then
    state.selected_file = file_path
    if state.auto_audition then
      play_preview(app, file_path)
    end
  end

  if r.ImGui_IsItemHovered(ctx) then
    r.ImGui_SetTooltip(ctx, file_path)
    if r.ImGui_IsMouseDoubleClicked(ctx, 0) then
      play_preview(app, file_path)
    end
  end

  if r.ImGui_BeginDragDropSource and r.ImGui_EndDragDropSource and r.ImGui_SetDragDropPayload then
    local source_flags = r.ImGui_DragDropFlags_SourceAllowNullID and r.ImGui_DragDropFlags_SourceAllowNullID() or 0
    if r.ImGui_BeginDragDropSource(ctx, source_flags) then
      r.ImGui_SetDragDropPayload(ctx, "REAPER_MEDIAFOLDER", file_path)
      r.ImGui_Text(ctx, leaf)
      state.drag_sample_path = file_path
      state.drag_release_seen = false
      state.drag_mouse_was_down = true

      local native_drag = false
      if r.ImGui_GetKeyMods and r.ImGui_Mod_Alt then
        native_drag = (r.ImGui_GetKeyMods(ctx) & r.ImGui_Mod_Alt()) ~= 0
      end
      state.drag_native_mode = native_drag
      if native_drag then
        state.drag_native_snapshot = collect_tracks_with_sample(file_path)
        state.drag_native_state_snapshot = collect_rs5k_state_snapshot()
      else
        state.drag_native_snapshot = nil
        state.drag_native_state_snapshot = nil
      end

      if native_drag and state.native_drag_file ~= file_path then
        state.native_drag_file = file_path
        start_external_file_drag(app, file_path)
      elseif not native_drag then
        state.native_drag_file = nil
      end
      r.ImGui_EndDragDropSource(ctx)
    end
  end

  if r.ImGui_BeginPopupContextItem(ctx, "##sample_ctx_" .. file_path) then
    if r.ImGui_MenuItem(ctx, "Load to RS5K on selected track##" .. file_path) then
      load_sample_to_selected_rs5k(app, file_path)
    end
    local rack_parent = get_selected_rack_parent_track()
    if rack_parent and r.ImGui_BeginMenu(ctx, "Load to RS5K rack slot...") then
      local used, max_used = collect_rack_slot_usage(rack_parent)
      local suggested = parse_slot_number(file_stem(file_path))
      local shown = 0
      if suggested and suggested <= RS5K_MAX_SLOTS and not used[suggested] then
        local label = string.format("Use sample number (%03d)", suggested)
        if r.ImGui_MenuItem(ctx, label .. "##sample_slot_suggest_" .. file_path) then
          load_sample_to_rack_slot(app, rack_parent, file_path, suggested)
        end
        shown = shown + 1
        r.ImGui_Separator(ctx)
      end
      local limit = math.min(RS5K_MAX_SLOTS, math.max(16, max_used + 8, suggested or 0))
      for slot = 1, limit do
        if not used[slot] then
          local label = string.format("Slot %03d", slot)
          if r.ImGui_MenuItem(ctx, label .. "##sample_slot_" .. tostring(slot) .. "_" .. file_path) then
            load_sample_to_rack_slot(app, rack_parent, file_path, slot)
          end
          shown = shown + 1
        end
      end
      if shown == 0 then
        r.ImGui_BeginDisabled(ctx, true)
        r.ImGui_MenuItem(ctx, "No free slots")
        r.ImGui_EndDisabled(ctx)
      end
      r.ImGui_EndMenu(ctx)
    end
    if r.CF_ShellExecute and r.ImGui_MenuItem(ctx, "Show in Explorer##" .. file_path) then
      r.CF_ShellExecute(file_path)
    end
    r.ImGui_EndPopup(ctx)
  end
end

local function draw_samples_list(app)
  local ctx = app.ctx
  local state = app.browser
  local items = state.filtered_files
  local col = selected_collection(app)

  if #items == 0 then
    if col and col.path and col.path ~= "" and not Relink.dir_exists(col.path) then
      r.ImGui_TextColored(ctx, Theme.colors.danger or 0xFF7A5AFF, "Folder not found")
      Theme.label(ctx, col.path)
      local prefix_map = state.relink_prefixes
      local remapped = nil
      if type(prefix_map) == "table" then
        for _, e in ipairs(prefix_map) do
          local ol = Relink.normalize(e.old):lower()
          if Relink.normalize(col.path):lower():sub(1, #ol) == ol then
            local cand = Relink.normalize(e.new) .. Relink.normalize(col.path):sub(#Relink.normalize(e.old) + 1)
            if Relink.dir_exists(cand) then remapped = cand break end
          end
        end
      end
      if remapped then
        if r.ImGui_Button(ctx, "Auto relink##col_relink_auto") then
          local pair = Relink.derive_prefix_pair(col.path, remapped)
          if pair then
            state.relink_prefixes = state.relink_prefixes or {}
            Relink.remember_prefix(state.relink_prefixes, pair.old, pair.new)
          end
          col.path = remapped
          save(app)
          refresh_collection(app, true)
        end
        if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Relink to remembered location:\n" .. remapped) end
        r.ImGui_SameLine(ctx)
      end
      if r.ImGui_Button(ctx, "Relink folder\226\128\166##col_relink") then
        local pick = Dialogs.browse_folder("Locate folder for " .. (col.name or "collection"), remapped or col.path)
        if pick and Relink.dir_exists(pick) then
          state.relink_prefixes = state.relink_prefixes or {}
          local pair = Relink.derive_prefix_pair(col.path, pick)
          if pair then Relink.remember_prefix(state.relink_prefixes, pair.old, pair.new) end
          col.path = pick
          save(app)
          refresh_collection(app, true)
        end
      end
      return
    end
    Theme.label(ctx, "No samples found for this filter.")
    return
  end

  if state.browser_mode == "packs" and col and col.recursive ~= false then
    local base = (col.path or ""):gsub("\\", "/"):gsub("/+$", "")
    local groups = {}
    local order = {}
    for _, f in ipairs(items) do
      local fp = f:gsub("\\", "/")
      local rel = fp
      if base ~= "" then
        local bl = base:lower()
        if fp:lower():sub(1, #bl) == bl then
          rel = fp:sub(#base + 1)
        end
      end
      rel = rel:gsub("^/", "")
      local dir = rel:match("^(.*)/[^/]+$") or "(Root)"
      local key = dir:lower()
      if not groups[key] then
        groups[key] = { dir = dir, files = {} }
        order[#order + 1] = key
      end
      groups[key].files[#groups[key].files + 1] = f
    end

    table.sort(order, function(a, b)
      return groups[a].dir:lower() < groups[b].dir:lower()
    end)

    local force_action = state.folder_header_action
    local can_force = r.ImGui_SetNextItemOpen and r.ImGui_Cond_Always

    for i, key in ipairs(order) do
      local group = groups[key]
      local label = truncate_text(group.dir, 64) .. " (" .. tostring(#group.files) .. ")##folder_group_" .. tostring(i)
      if can_force and force_action == "expand" then
        r.ImGui_SetNextItemOpen(ctx, true, r.ImGui_Cond_Always())
      elseif can_force and force_action == "collapse" then
        r.ImGui_SetNextItemOpen(ctx, false, r.ImGui_Cond_Always())
      end
      if r.ImGui_CollapsingHeader(ctx, label) then
        for _, f in ipairs(group.files) do
          draw_sample_row(app, f)
        end
      end
      if r.ImGui_IsItemHovered(ctx) and group.dir ~= "(Root)" then
        r.ImGui_SetTooltip(ctx, group.dir)
      end
    end
    state.folder_header_action = nil
    return
  end

  if r.ImGui_CreateListClipper and r.ImGui_ListClipper_Begin and r.ImGui_ListClipper_Step and r.ImGui_ListClipper_GetDisplayRange and r.ImGui_ListClipper_End then
    if not state.list_clipper or not r.ImGui_ValidatePtr(state.list_clipper, "ImGui_ListClipper*") then
      state.list_clipper = r.ImGui_CreateListClipper(ctx)
    end
    r.ImGui_ListClipper_Begin(state.list_clipper, #items)
    while r.ImGui_ListClipper_Step(state.list_clipper) do
      local display_start, display_end = r.ImGui_ListClipper_GetDisplayRange(state.list_clipper)
      for i = display_start + 1, display_end do
        draw_sample_row(app, items[i])
      end
    end
    r.ImGui_ListClipper_End(state.list_clipper)
    return
  end

  for _, f in ipairs(items) do
    draw_sample_row(app, f)
  end
end

local function draw_collections_panel(app, panel_h)
  local ctx = app.ctx
  local state = app.browser
  local ordered = ordered_collections(state)

  local function draw_list()
    if #ordered == 0 then
      Theme.label(ctx, state.browser_mode == "kits" and "No kits added yet." or "No sample packs added yet.")
    end

    for _, c in ipairs(ordered) do
      local selected = state.selected_id == c.id
      local prefix = c.pinned and "* " or "  "
      local cover = c.cover_path and " [cover]" or ""
      local label = prefix .. truncate_text(c.name, 40) .. cover .. "##" .. c.id
      if r.ImGui_Selectable(ctx, label, selected) then
        state.selected_id = c.id
        save(app)
        refresh_collection(app, false)
      end
      if r.ImGui_IsItemHovered(ctx) then
        local tip = c.name .. "\n" .. c.path
        if c.cover_path then tip = tip .. "\nCover: " .. c.cover_path end
        r.ImGui_SetTooltip(ctx, tip)
      end
      if r.ImGui_BeginPopupContextItem(ctx, "##col_ctx_" .. c.id) then
        r.ImGui_EndPopup(ctx)
      end
      draw_collection_context_menu(app, c)
    end
  end

  local function draw_tiles()
    if #ordered == 0 then
      Theme.label(ctx, state.browser_mode == "kits" and "No kits added yet." or "No sample packs added yet.")
      return
    end

    local panel_w = as_number(r.ImGui_GetContentRegionAvail(ctx)) or 0
    local gap = 10
    local min_tile = 120
    local cols = math.max(1, math.floor((panel_w + gap) / (min_tile + gap)))
    local tile_w = math.max(min_tile, math.floor((panel_w - (gap * (cols - 1))) / cols))
    local tile_flags = 0
    if r.ImGui_WindowFlags_NoScrollbar then
      tile_flags = tile_flags | r.ImGui_WindowFlags_NoScrollbar()
    end
    if r.ImGui_WindowFlags_NoScrollWithMouse then
      tile_flags = tile_flags | r.ImGui_WindowFlags_NoScrollWithMouse()
    end

    for i, c in ipairs(ordered) do
      local col_index = ((i - 1) % cols)
      if col_index > 0 then
        r.ImGui_SameLine(ctx, nil, gap)
      end

      r.ImGui_PushID(ctx, c.id)
      r.ImGui_BeginGroup(ctx)

      local selected = state.selected_id == c.id
      local bg = selected and Theme.colors.accent_soft or Theme.colors.frame_bg
      local border = selected and Theme.colors.accent or Theme.colors.border
      local tile_h = tile_w
      local label_x = r.ImGui_GetCursorPosX(ctx)
      local pressed_tile = false
      local open_ctx = false

      r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), 0, 0)
      r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ChildBorderSize(), 1.5)
      r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ChildBg(), bg)
      r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Border(), border)
      local tile_visible = r.ImGui_BeginChild(ctx, "##tile_" .. c.id, tile_w, tile_h, 1, tile_flags)
      if tile_visible then
        local cover_inset = 2
        local tex = cover_texture(state, c.cover_path)
        if tex and r.ImGui_Image then
          local img_w, img_h = 0, 0
          if r.ImGui_Image_GetSize then
            local ok, w, h = pcall(r.ImGui_Image_GetSize, tex)
            if ok then
              img_w = as_number(w) or 0
              img_h = as_number(h) or 0
            end
          end
          local avail_w, avail_h = r.ImGui_GetContentRegionAvail(ctx)
          avail_w = math.max(1, (as_number(avail_w) or tile_w) - (cover_inset * 2))
          avail_h = math.max(1, (as_number(avail_h) or tile_h) - (cover_inset * 2))
          local draw_w, draw_h = avail_w, avail_h
          if img_w > 0 and img_h > 0 then
            local scale = math.min(avail_w / img_w, avail_h / img_h)
            draw_w = math.max(1, img_w * scale)
            draw_h = math.max(1, img_h * scale)
          end
          local x0, y0 = r.ImGui_GetCursorPos(ctx)
          r.ImGui_SetCursorPos(ctx, x0 + cover_inset + math.max(0, (avail_w - draw_w) * 0.5), y0 + cover_inset + math.max(0, (avail_h - draw_h) * 0.5))
          r.ImGui_Image(ctx, tex, draw_w, draw_h)
        else
          local nc_w = as_number(r.ImGui_CalcTextSize(ctx, "NO COVER")) or 60
          local avail_w, avail_h = r.ImGui_GetContentRegionAvail(ctx)
          avail_w = math.max(1, (as_number(avail_w) or tile_w) - (cover_inset * 2))
          avail_h = math.max(1, (as_number(avail_h) or tile_h) - (cover_inset * 2))
          r.ImGui_SetCursorPosY(ctx, cover_inset + math.max(4, avail_h * 0.42))
          r.ImGui_SetCursorPosX(ctx, cover_inset + math.max(4, (avail_w - nc_w) * 0.5))
          r.ImGui_TextColored(ctx, Theme.colors.text_dim, "NO COVER")
        end
        if r.ImGui_IsWindowHovered(ctx) then
          if r.ImGui_IsMouseReleased(ctx, 0) then
            pressed_tile = true
          end
          if r.ImGui_IsMouseClicked(ctx, 1) then
            open_ctx = true
          end
        end
        r.ImGui_EndChild(ctx)
      end
      do
        local tile_min_x, tile_min_y = r.ImGui_GetItemRectMin(ctx)
        local tile_max_x, tile_max_y = r.ImGui_GetItemRectMax(ctx)
        local tile_dl = r.ImGui_GetWindowDrawList(ctx)
        r.ImGui_DrawList_AddRect(tile_dl, tile_min_x + 0.5, tile_min_y + 0.5, tile_max_x - 0.5, tile_max_y - 0.5, border, 3, 0, selected and 2 or 1)
      end
      r.ImGui_PopStyleColor(ctx, 2)
      r.ImGui_PopStyleVar(ctx, 2)

      local pin = c.pinned and "* " or ""
      local max_chars = math.max(8, math.floor((tile_w - 8) / 7))
      local tile_label = truncate_text(pin .. c.name, max_chars)
      local tw = as_number(r.ImGui_CalcTextSize(ctx, tile_label)) or 0
      r.ImGui_SetCursorPosX(ctx, label_x + math.max(0, (tile_w - tw) * 0.5))
      r.ImGui_Text(ctx, tile_label)

      r.ImGui_EndGroup(ctx)

      if pressed_tile then
        state.selected_id = c.id
        save(app)
        refresh_collection(app, false)
      end
      if r.ImGui_IsItemHovered(ctx) then
        local tip = c.name .. "\n" .. c.path
        if c.cover_path then tip = tip .. "\nCover: " .. c.cover_path end
        r.ImGui_SetTooltip(ctx, tip)
        if r.ImGui_IsMouseClicked(ctx, 1) then
          open_ctx = true
        end
      end
      if open_ctx then
        r.ImGui_OpenPopup(ctx, "##col_ctx_" .. c.id)
      end
      draw_collection_context_menu(app, c)

      r.ImGui_PopID(ctx)
    end
  end

  if r.ImGui_BeginChild(ctx, "##browser_collections", 0, panel_h or 0, 1) then
    if state.collection_view == "tiles" then
      draw_tiles()
    else
      draw_list()
    end

    r.ImGui_EndChild(ctx)
  end
end

local function draw_samples_panel(app)
  local ctx = app.ctx
  local state = app.browser
  local col = selected_collection(app)
  local show_folder_groups = state.browser_mode == "packs" and col and col.recursive ~= false

  local avail_w = r.ImGui_GetContentRegionAvail(ctx)
  local search_w = math.min(320, math.max(180, (as_number(avail_w) or 260) - 150))
  r.ImGui_SetNextItemWidth(ctx, search_w)
  local s_changed, s_value = r.ImGui_InputTextWithHint(ctx, "##browser_search", "Filter by filename...", state.search or "")
  if s_changed then
    state.search = s_value
    save(app)
    apply_filter(app)
  end
  r.ImGui_SameLine(ctx)
  if state.last_scan_label then
    Theme.label(ctx, "Matches: " .. state.last_scan_label)
  end
  if show_folder_groups then
    local panel_w = as_number(avail_w) or 0
    local force_new_row = panel_w < 560
    local full_w = 86 + 6 + 92
    local remain_w = as_number(r.ImGui_GetContentRegionAvail(ctx)) or 0
    local compact = force_new_row or (remain_w < full_w)
    if not compact then
      r.ImGui_SameLine(ctx)
      if Theme.ghost_button(ctx, "Expand all", 86, 0) then
        state.folder_header_action = "expand"
      end
      r.ImGui_SameLine(ctx)
      if Theme.ghost_button(ctx, "Collapse all", 92, 0) then
        state.folder_header_action = "collapse"
      end
    else
      if not force_new_row then
        r.ImGui_Dummy(ctx, 0, 0)
      end
      local row_w = as_number(r.ImGui_GetContentRegionAvail(ctx)) or 0
      local btn_w = math.max(58, math.floor((row_w - 6) * 0.5))
      if Theme.ghost_button(ctx, "Expand", btn_w, 0) then
        state.folder_header_action = "expand"
      end
      r.ImGui_SameLine(ctx)
      if Theme.ghost_button(ctx, "Collapse", btn_w, 0) then
        state.folder_header_action = "collapse"
      end
    end
  end

  if state.preview_error and state.preview_error ~= "" then
    r.ImGui_TextColored(ctx, 0xFFB454FF, state.preview_error)
  end

  local _, avail_h = r.ImGui_GetContentRegionAvail(ctx)
  local transport_h = 88
  local list_h = math.max(80, avail_h - transport_h)
  local transport_flags = 0
  if r.ImGui_WindowFlags_NoScrollbar then
    transport_flags = transport_flags | r.ImGui_WindowFlags_NoScrollbar()
  end
  if r.ImGui_WindowFlags_NoScrollWithMouse then
    transport_flags = transport_flags | r.ImGui_WindowFlags_NoScrollWithMouse()
  end
  if r.ImGui_BeginChild(ctx, "##browser_samples", 0, list_h, 1, 0) then
    draw_samples_list(app)
    r.ImGui_EndChild(ctx)
  end

  if r.ImGui_BeginChild(ctx, "##browser_transport", 0, transport_h, 0, transport_flags) then
    r.ImGui_Separator(ctx)
    if Theme.ghost_button(ctx, "Audition", 90, 0) and state.selected_file then
      play_preview(app, state.selected_file)
    end
    r.ImGui_SameLine(ctx)
    if Theme.ghost_button(ctx, "Stop", 70, 0) then
      stop_preview(state)
    end
    r.ImGui_SameLine(ctx)
    local auto_changed, auto_value = r.ImGui_Checkbox(ctx, "Auto", state.auto_audition ~= false)
    if auto_changed then
      state.auto_audition = auto_value
      save(app)
    end
    r.ImGui_SameLine(ctx)
    local vol_avail = as_number(r.ImGui_GetContentRegionAvail(ctx)) or 120
    r.ImGui_SetNextItemWidth(ctx, math.max(120, vol_avail))
    local vol_changed, vol_value = r.ImGui_SliderDouble(ctx, "##browser_preview_vol", state.preview_volume or 1.0, 0, 2.0, "%.2f")
    if vol_changed then
      state.preview_volume = vol_value
      save(app)
      if state.preview and r.CF_Preview_SetValue then
        r.CF_Preview_SetValue(state.preview, "D_VOLUME", vol_value)
      end
    end

    local playing_text = "Playing: -"
    if state.preview_path then
      local leaf = state.preview_path:match("([^/\\]+)$") or state.preview_path
      playing_text = "Playing: " .. leaf
    end
    local pushed = Theme.push_small(ctx)
    Theme.label(ctx, playing_text)
    Theme.pop_font(ctx, pushed)
    r.ImGui_Separator(ctx)

    r.ImGui_EndChild(ctx)
  end
end

local function draw_top_controls(app, col, narrow)
  local ctx = app.ctx
  local state = app.browser
  local _ = col

  local first = true
  local function place(label, primary, fixed_w)
    local w
    if fixed_w then
      w = fixed_w
    else
      local tw = as_number(r.ImGui_CalcTextSize(ctx, label)) or 60
      w = math.ceil(tw + 22)
    end
    if not first then
      local last_x2 = as_number(r.ImGui_GetItemRectMax(ctx)) or 0
      local win_x = as_number(r.ImGui_GetWindowPos(ctx)) or 0
      local win_w = as_number(r.ImGui_GetWindowWidth(ctx)) or 9999
      local visible_x2 = win_x + win_w - 16
      local next_x2 = last_x2 + 8 + w
      if next_x2 < visible_x2 then
        r.ImGui_SameLine(ctx, nil, 6)
      end
    end
    first = false
    if primary then
      return Theme.primary_button(ctx, label, fixed_w or 0, 0)
    end
    return Theme.ghost_button(ctx, label, fixed_w or 0, 0)
  end

  local mode_btn = state.browser_mode == "kits" and "Sample Kits" or "Sample Packs"
  if place(mode_btn, false, 110) then
    switch_browser_mode(app, state.browser_mode == "kits" and "packs" or "kits")
  end
  if r.ImGui_IsItemHovered(ctx) then
    r.ImGui_SetTooltip(ctx, "Click to switch between Sample Packs and Sample Kits")
  end

  if place("+ Folder", false) then
    add_collection(app)
  end
  if place("Rescan", false) then
    refresh_collection(app, true)
  end
  if place("List", false) then
    state.collection_view = "list"
    save(app)
  end
  if place("Tiles", false) then
    state.collection_view = "tiles"
    save(app)
  end

  local focus = state.small_focus or "split"
  if place("Catalog", focus == "catalog", 86) then
    state.small_focus = "catalog"
    save(app)
  end
  if place("Split", focus == "split", 72) then
    state.small_focus = "split"
    save(app)
  end
  if place("Samples", focus == "samples", 86) then
    state.small_focus = "samples"
    save(app)
  end
end

local function draw_split(app)
  local ctx = app.ctx
  local state = app.browser

  local avail_w, avail_h = r.ImGui_GetContentRegionAvail(ctx)
  avail_w = as_number(avail_w) or 600
  avail_h = as_number(avail_h) or 400

  local splitter_w = 4
  local min_left, min_right = 150, 220
  local default_left = state.collection_view == "tiles" and 380 or 220
  local left_w = as_number(state.split_w) or default_left
  local max_left = math.max(min_left, avail_w - min_right - splitter_w)
  left_w = math.max(min_left, math.min(left_w, max_left))

  local noscroll = 0
  if r.ImGui_WindowFlags_NoScrollbar then noscroll = noscroll | r.ImGui_WindowFlags_NoScrollbar() end
  if r.ImGui_WindowFlags_NoScrollWithMouse then noscroll = noscroll | r.ImGui_WindowFlags_NoScrollWithMouse() end

  if r.ImGui_BeginChild(ctx, "##browser_left", left_w, avail_h, 0, noscroll) then
    draw_collections_panel(app, 0)
    r.ImGui_EndChild(ctx)
  end

  r.ImGui_SameLine(ctx, nil, 6)

  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), Theme.colors.border)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), Theme.colors.accent_soft)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), Theme.colors.accent)
  r.ImGui_Button(ctx, "##browser_splitter", splitter_w, avail_h)
  r.ImGui_PopStyleColor(ctx, 3)
  if r.ImGui_IsItemHovered(ctx) or r.ImGui_IsItemActive(ctx) then
    if r.ImGui_SetMouseCursor and r.ImGui_MouseCursor_ResizeEW then
      r.ImGui_SetMouseCursor(ctx, r.ImGui_MouseCursor_ResizeEW())
    end
  end
  if r.ImGui_IsItemActive(ctx) then
    local dx = as_number(select(1, r.ImGui_GetMouseDelta(ctx))) or 0
    if dx ~= 0 then
      state.split_w = math.max(min_left, math.min(left_w + dx, max_left))
      save(app)
    end
  end

  r.ImGui_SameLine(ctx, nil, 6)

  if r.ImGui_BeginChild(ctx, "##browser_right", 0, avail_h, 0, noscroll) then
    draw_samples_panel(app)
    r.ImGui_EndChild(ctx)
  end
end

local function draw_stacked(app)
  local ctx = app.ctx
  local state = app.browser

  local avail_w, avail_h = r.ImGui_GetContentRegionAvail(ctx)
  avail_h = as_number(avail_h) or 400

  local splitter_h = 4
  local min_top, min_bottom = 120, 150
  local top_h = as_number(state.split_h) or math.floor(avail_h * 0.42)
  local max_top = math.max(min_top, avail_h - min_bottom - splitter_h)
  top_h = math.max(min_top, math.min(top_h, max_top))

  local noscroll = 0
  if r.ImGui_WindowFlags_NoScrollbar then noscroll = noscroll | r.ImGui_WindowFlags_NoScrollbar() end
  if r.ImGui_WindowFlags_NoScrollWithMouse then noscroll = noscroll | r.ImGui_WindowFlags_NoScrollWithMouse() end

  if r.ImGui_BeginChild(ctx, "##browser_top", 0, top_h, 0, noscroll) then
    draw_collections_panel(app, 0)
    r.ImGui_EndChild(ctx)
  end

  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), Theme.colors.border)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), Theme.colors.accent_soft)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), Theme.colors.accent)
  r.ImGui_Button(ctx, "##browser_vsplit", -1, splitter_h)
  r.ImGui_PopStyleColor(ctx, 3)
  if r.ImGui_IsItemHovered(ctx) or r.ImGui_IsItemActive(ctx) then
    if r.ImGui_SetMouseCursor and r.ImGui_MouseCursor_ResizeNS then
      r.ImGui_SetMouseCursor(ctx, r.ImGui_MouseCursor_ResizeNS())
    end
  end
  if r.ImGui_IsItemActive(ctx) then
    local dy = as_number(select(2, r.ImGui_GetMouseDelta(ctx))) or 0
    if dy ~= 0 then
      state.split_h = math.max(min_top, math.min(top_h + dy, max_top))
      save(app)
    end
  end

  if r.ImGui_BeginChild(ctx, "##browser_bottom", 0, 0, 0, noscroll) then
    draw_samples_panel(app)
    r.ImGui_EndChild(ctx)
  end
end

function M.ensure_stopped(app)
  if not app or not app.browser then return end
  stop_preview(app.browser)
end

function M.init(app)
  local loaded = Store.load()
  app.browser = {
    collections = loaded.collections,
    kit_collections = loaded.kit_collections or {},
    selected_id = loaded.selected_id,
    sample_selected_id = loaded.sample_selected_id or loaded.selected_id,
    kit_selected_id = loaded.kit_selected_id,
    manager_visible = loaded.manager_visible == true,
    manager_mode = loaded.manager_mode == "make" and "make" or "view",
    search = loaded.search or "",
    auto_audition = loaded.auto_audition ~= false,
    preview_volume = loaded.preview_volume or 1.0,
    manager_audition_mode = loaded.manager_audition_mode == "preview" and "preview" or "track",
    manager_rack_color = loaded.manager_rack_color or 0x4DA3FFFF,
    manager_rack_gradient = loaded.manager_rack_gradient == true,
    manager_save_dir = loaded.manager_save_dir or "",
    files = {},
    filtered_files = {},
    selected_file = nil,
    last_scan_label = nil,
    preview = nil,
    preview_source = nil,
    preview_path = nil,
    preview_error = nil,
    scan_cache = {},
    filter_cache = {},
    list_clipper = nil,
    browser_mode = loaded.browser_mode or "packs",
    collection_view = loaded.collection_view or "list",
    small_focus = (loaded.small_focus == "catalog" or loaded.small_focus == "samples" or loaded.small_focus == "split") and loaded.small_focus or "split",
    split_w = loaded.split_w or 240,
    split_h = loaded.split_h or 240,
    folder_header_action = nil,
    native_drag_file = nil,
    drag_sample_path = nil,
    drag_release_seen = false,
    drag_mouse_was_down = false,
    drag_track_target = nil,
    drag_native_mode = false,
    drag_native_snapshot = nil,
    drag_native_state_snapshot = nil,
    drag_native_pending_path = nil,
    drag_native_pending_track = nil,
    drag_native_pending_snapshot = nil,
    drag_native_pending_state_snapshot = nil,
    drag_native_pending_tries = 0,
    cover_cache = {},
  }
  if app.browser.browser_mode == "kits" then
    app.browser.selected_id = app.browser.kit_selected_id or (app.browser.kit_collections[1] and app.browser.kit_collections[1].id or nil)
  else
    app.browser.selected_id = app.browser.sample_selected_id or (app.browser.collections[1] and app.browser.collections[1].id or nil)
  end
  refresh_collection(app, false)
end

function M.draw(app)
  local ctx = app.ctx
  local col = selected_collection(app)
  local avail_w = r.ImGui_GetContentRegionAvail(ctx)
  local narrow = (as_number(avail_w) or 9999) < 860
  local state = app.browser

  draw_top_controls(app, col, narrow)
  if state.small_focus == "catalog" then
    draw_collections_panel(app, 0)
  elseif state.small_focus == "samples" then
    draw_samples_panel(app)
  elseif narrow then
    draw_stacked(app)
  else
    draw_split(app)
  end
end

return M
