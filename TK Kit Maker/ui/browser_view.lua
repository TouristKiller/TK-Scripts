local r = reaper
local Theme = require("core.theme")
local Dialogs = require("core.dialogs")
local Scanner = require("core.scanner")
local Store = require("core.browser_store")
local BuilderView = require("ui.builder_view")
local Presets = require("data.presets")
local Relink = require("core.relink")
local Tags = require("core.tags")
local Analyzer = require("core.analyzer")
local Heatmap = require("core.heatmap")
local RS5K = require("core.rs5k")
local Engine = require("core.engine")

local M = {}

local IMAGE_EXT = {
  png = true,
  jpg = true,
  jpeg = true,
  webp = true,
  bmp = true,
  gif = true,
}

local MAX_COVER_DIMENSION = 4096
local MAX_COVER_PIXELS = 16777216

local RS5K_BASE_NOTE = 36
local RS5K_MAX_SLOTS = 127 - RS5K_BASE_NOTE + 1
local KIT_RACK_SLOTS = 16

local TILE_SIZES = {
  small = 72,
  normal = 120,
  large = 170,
  huge = 240,
}
local TILE_ORDER = { "small", "normal", "large", "huge" }

local refresh_collection
local save
local sample_menu_items

local function as_number(value)
  if type(value) == "number" then return value end
  if type(value) == "string" then return tonumber(value) end
  return nil
end

local function is_image_file(path)
  local ext = tostring(path or ""):match("%.([%w]+)$")
  return ext ~= nil and IMAGE_EXT[ext:lower()] == true
end

local function validate_cover_image(state, path)
  if not is_image_file(path) then
    return false, "Selected file is not a supported image."
  end
  if not r.ImGui_CreateImage then
    return false, "Image loading API is not available."
  end

  local ok_create, tex = pcall(r.ImGui_CreateImage, path)
  if not ok_create or not tex then
    return false, "Image could not be decoded."
  end

  if r.ImGui_Image_GetSize then
    local ok_size, w, h = pcall(r.ImGui_Image_GetSize, tex)
    if not ok_size then
      return false, "Image metadata could not be read."
    end
    w = as_number(w) or 0
    h = as_number(h) or 0
    if w <= 0 or h <= 0 then
      return false, "Image has invalid dimensions."
    end
    if w > MAX_COVER_DIMENSION or h > MAX_COVER_DIMENSION then
      return false, "Image is too large (max 4096 px per side)."
    end
    if (w * h) > MAX_COVER_PIXELS then
      return false, "Image is too large (max 16 megapixels)."
    end
  end

  state.cover_cache = state.cover_cache or {}
  state.cover_cache[path] = tex
  return true, nil
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

-- Writes a set of samples out as a kit folder -- copied, renamed and numbered,
-- the same shape the Explosion and Builder pages produce. Every slot is locked
-- to one file, so the ordinary export engine does the work: pick_sample hands a
-- locked slot straight back without needing a pool behind it.
--
-- The caller numbers the slots, because the two callers number differently: the
-- heatmap keeps a hole in the pad layout as a hole in the filenames, the file
-- list runs straight through. Returns ok, message.
local function export_kit_folder(app, slots, kit_name)
  if #slots == 0 then return false, "Nothing to export." end

  local dest = Dialogs.browse_folder("Select a destination folder for the kit", "", "destination")
  if not dest then return false, nil end

  -- The note is only in the filename while it still means something. Notes run
  -- from 36 up, so beyond 92 samples they would all clamp to 127 and every file
  -- after the 92nd would claim the same one.
  local fits_notes = #slots <= (127 - RS5K_BASE_NOTE + 1)

  local kitdef = {
    name_prefix = kit_name,
    name_numbered = false,
    slots = slots,
    naming = {
      prefix_style = "001",
      include_type = false,
      note_style = fits_notes and "name" or "none",
      separator = "_",
    },
    export = {
      destination = dest,
      kit_count = 1,
      write_midilog = false,
      write_sourcelog = false,
      write_usedlog = false,
      write_stitched = false,
      max_sample_seconds = 0,
    },
  }

  local ok, kit = pcall(Engine.generate_kit, kitdef, {}, 1, app.script_path)
  if not ok or not kit then
    return false, "Export failed: " .. tostring(kit)
  end

  local note = string.format("Exported %d samples to %s.", #(kit.results or {}), kit.name)
  if #(kit.errors or {}) > 0 then
    note = note .. string.format(" %d skipped.", #kit.errors)
  end
  return true, note
end

-- Everything the file list is showing, in the order it shows it: the tag filter
-- and the filename filter have already done their work, so this writes out
-- exactly what is on screen.
local function export_filtered_as_kit(app)
  local state = app.browser
  local col = selected_collection(app)
  local slots = {}
  for i, path in ipairs(state.filtered_files or {}) do
    slots[#slots + 1] = {
      number = i,
      midi_note = math.min(127, RS5K_BASE_NOTE + i - 1),
      pad = i,
      lock_file = path,
    }
  end

  local ok, note = export_kit_folder(app, slots, ((col and col.name) or "Browser") .. " Kit")
  state.preview_error = (not ok) and note or nil
  state.export_note = ok and note or nil
  return ok
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
  -- The export note names a count from the set that is about to change.
  state.export_note = nil
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
  local tag_key = Tags.filter_key(state.tag_filter)

  -- The name-filtered set is cached on its own key. The tag chips are counted
  -- over it, so they describe what is actually in front of you instead of the
  -- whole collection.
  local nkey = key .. "|" .. search
  local by_name = state.filter_cache[nkey]
  if not by_name then
    if search == "" then
      by_name = files
    else
      by_name = {}
      for _, f in ipairs(files) do
        local leaf = f:match("([^/\\]+)$") or f
        if leaf:lower():find(search, 1, true) then
          by_name[#by_name + 1] = f
        end
      end
    end
    state.filter_cache[nkey] = by_name
  end

  -- Name first, tags second: the cheap test thins the list before the one that
  -- has to look every file up.
  local filtered = by_name
  if tag_key ~= "" then
    local fkey = nkey .. "|" .. tag_key
    filtered = state.filter_cache[fkey]
    if not filtered then
      filtered = {}
      for _, f in ipairs(by_name) do
        if Tags.matches_filter(f, state.tag_filter) then
          filtered[#filtered + 1] = f
        end
      end
      state.filter_cache[fkey] = filtered
    end
  end

  state.filtered_files = filtered
  state.last_scan_label = tostring(#filtered) .. " / " .. tostring(#files)
  state.analysis_count = Tags.count_analyzed(files)
  state.tag_facets, state.tag_unmeasured = Tags.filter_facets(by_name, state.tag_filter)

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

  -- A job is scoped to the collection it was started from: its progress counts
  -- would be meaningless against another one's file list. Stopping is free --
  -- everything measured so far is already cached.
  if state.analysis_job then
    state.analysis_job:cancel()
    state.analysis_job = nil
  end

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

-- Shared with the Kit Manager, deliberately: this matched on the plugin name
-- alone here, so a pad whose RS5K had been renamed looked empty and filling it
-- stacked a second instance on the track. See core/rs5k.lua.
local function find_rs5k_fx(track)
  return RS5K.find(track)
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

-- The instrument a sample plays, or nil when the naming rules do not recognise
-- one. Used for the MIDI note names: nil means REAPER goes on showing the pad
-- track's name, which is the filename, so nothing is lost on a sample that fits
-- no category. These are exactly the files the Tags filter calls Uncategorised.
local function role_of(path)
  local _, category = Tags.function_of(path)
  return category
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
    RS5K.set_note_name(parent_track, note, role_of(sample_path))
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

-- Builds a fresh RS5K folder rack. `mapped_by_slot` maps slot number ->
-- { sample_path, sample_name }; slots without an entry get an empty RS5K so the
-- pad grid stays complete. Shared by the kit-collection rack and the heatmap.
local function build_rs5k_rack(rack_name, mapped_by_slot, rack_slots, undo_label)
  local insert_after = r.GetSelectedTrack(0, 0)
  local base_index = insert_after and r.GetMediaTrackInfo_Value(insert_after, "IP_TRACKNUMBER") or r.CountTracks(0)
  base_index = math.floor(base_index)

  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)

  r.InsertTrackAtIndex(base_index, true)
  local folder_track = r.GetTrack(0, base_index)
  r.GetSetMediaTrackInfo_String(folder_track, "P_NAME", rack_name, true)
  r.SetMediaTrackInfo_Value(folder_track, "I_FOLDERDEPTH", 1)

  for slot = 1, rack_slots do
    local idx = base_index + slot
    r.InsertTrackAtIndex(idx, true)
    local tr = r.GetTrack(0, idx)
    local item = mapped_by_slot[slot]
    local midi_note = RS5K_BASE_NOTE + (slot - 1)
    if item then
      r.GetSetMediaTrackInfo_String(tr, "P_NAME", item.sample_name, true)
      load_sample_into_rs5k(tr, item.sample_path, midi_note)
      RS5K.set_note_name(folder_track, midi_note, role_of(item.sample_path))
    else
      r.GetSetMediaTrackInfo_String(tr, "P_NAME", string.format("Pad %02d", slot), true)
      create_empty_rs5k(tr, midi_note)
    end
    r.SetMediaTrackInfo_Value(tr, "I_FOLDERDEPTH", slot == rack_slots and -1 or 0)
  end

  r.PreventUIRefresh(-1)
  r.TrackList_AdjustWindows(false)
  r.UpdateArrange()
  r.Undo_EndBlock(undo_label, -1)
  return folder_track
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

  local mapped_by_slot = {}
  local max_slot = 0
  for _, item in ipairs(mapped) do
    mapped_by_slot[item.slot] = item
    if item.slot > max_slot then max_slot = item.slot end
  end

  local folder_name = col.name ~= "" and col.name or file_leaf(col.path)
  build_rs5k_rack(folder_name .. " Rack", mapped_by_slot,
    math.max(KIT_RACK_SLOTS, max_slot),
    "TK Kit Maker: Create RS5K drum rack from kit")

  if total_files > #mapped then
    state.preview_error = "Rack created with " .. tostring(#mapped) .. " mapped samples."
  else
    state.preview_error = nil
  end
  return true
end

local function add_collection(app)
  local folder = Dialogs.browse_folder("Select sample folder", "", "source")
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

-- Skips ids that are already taken rather than trusting the counter: a loaded
-- preset brings its own pool_1, pool_2... while next_pool_n stays where it was.
-- The Builder's own "+ Pool" learned this the hard way; these two entry points
-- never did.
local function new_pool_id(app)
  local id
  repeat
    id = "pool_" .. tostring(app.builder.next_pool_n)
    app.builder.next_pool_n = app.builder.next_pool_n + 1
  until not app.pools[id]
  return id
end

local function add_collection_as_pool(app)
  local col = selected_collection(app)
  if not col then return end

  ensure_builder_state(app)

  local id = new_pool_id(app)

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

local function add_folder_as_pool(app, folder_path, alias)
  local folder = Scanner.normalize(folder_path or "")
  if folder == "" then return false end

  ensure_builder_state(app)

  local id = new_pool_id(app)

  app.pools[id] = {
    id = id,
    alias = alias and alias ~= "" and alias or (file_leaf(folder) ~= "" and file_leaf(folder) or folder),
    folders = { folder },
    recursive = false,
    files = {},
    mode = "repeat",
    _bag = {},
  }
  app.builder.pool_order[#app.builder.pool_order + 1] = id
  Scanner.scan_pool(app.pools[id])
  app.view = "builder"
  return true
end

-- Where a cell sits on one axis, in that axis's own words. The grid is rescaled
-- to the collection on screen, so this says where the cell falls within that
-- selection -- not an absolute frequency or length.
local function axis_word(axis, idx, size)
  if not axis or size < 2 then return "mid" end
  local f = (idx - 0.5) / size
  if f < 0.34 then return axis.lo end
  if f > 0.66 then return axis.hi end
  return "mid"
end

local function cell_alias(grid, row, col)
  local function cap(w) return (w:sub(1, 1):upper() .. w:sub(2)) end
  local x = axis_word(grid.x_axis, col, grid.size)
  -- Row 1 is the top of the grid while the axis grows upward.
  local y = axis_word(grid.y_axis, grid.size + 1 - row, grid.size)
  if x == y then return x == "mid" and "Middle" or cap(x) end
  return cap(x) .. " " .. cap(y)
end

-- A heatmap cell as a Builder pool: the samples in one corner of the sound
-- space, so a slot can be told "something short and bright goes here" and never
-- draw anything else. This is the one pool that is a fixed list of files rather
-- than a folder, since what selects them is how they measure, not where they
-- live -- see the `fixed` flag, which Scanner.scan_pool honours.
local function add_cell_as_pool(app, row, col)
  local state = app.browser
  local grid = state.grid
  local cell = grid and Heatmap.cell(grid, row, col)
  if not cell or cell.n == 0 then return false end

  ensure_builder_state(app)
  local id = new_pool_id(app)

  local files = {}
  for i, item in ipairs(cell.items) do files[i] = item.path end

  app.pools[id] = {
    id = id,
    alias = cell_alias(grid, row, col),
    folders = {},
    recursive = false,
    files = files,
    fixed = true,
    fixed_origin = string.format("%d samples from the heatmap: %s %s, %s %s",
      #files,
      grid.x_axis.label:lower(), axis_word(grid.x_axis, col, grid.size),
      grid.y_axis.label:lower(), axis_word(grid.y_axis, grid.size + 1 - row, grid.size)),
    mode = "repeat",
    _bag = {},
  }
  app.builder.pool_order[#app.builder.pool_order + 1] = id
  app.view = "builder"
  return true
end

local function add_folder_to_existing_pool(app, pool_id, folder_path)
  local folder = Scanner.normalize(folder_path or "")
  if folder == "" then return false, "Folder path is empty." end

  ensure_builder_state(app)
  local pool = app.pools[pool_id]
  if not pool then return false, "Pool not found." end
  if pool.fixed then return false, "This pool holds a fixed set of samples." end

  for _, existing in ipairs(pool.folders or {}) do
    if Scanner.normalize(existing):lower() == folder:lower() then
      return false, "That folder is already linked to this pool."
    end
  end

  pool.folders = pool.folders or {}
  pool.folders[#pool.folders + 1] = folder
  pool.files = {}
  pool._bag = {}
  pool._views = nil
  Scanner.scan_pool(pool)
  return true
end

local function draw_existing_pool_menu(app, uid, folder_path)
  local ctx = app.ctx
  local state = app.browser
  if not r.ImGui_BeginMenu(ctx, "Add to Existing Builder Pool##pool_existing_" .. uid) then return end

  if not app.builder or not app.builder.pool_order or #app.builder.pool_order == 0 then
    r.ImGui_BeginDisabled(ctx, true)
    r.ImGui_MenuItem(ctx, "No pools yet")
    r.ImGui_EndDisabled(ctx)
  else
    for _, pool_id in ipairs(app.builder.pool_order) do
      local pool = app.pools and app.pools[pool_id] or nil
      if pool then
        if r.ImGui_MenuItem(ctx, (pool.alias or pool_id) .. "##pool_target_" .. uid .. "_" .. pool_id) then
          local ok, err = add_folder_to_existing_pool(app, pool_id, folder_path)
          if ok then
            state.preview_error = "Folder toegevoegd aan pool: " .. tostring(pool.alias or pool_id)
          else
            state.preview_error = err or "Kon folder niet toevoegen aan pool."
          end
        end
      end
    end
  end
  r.ImGui_EndMenu(ctx)
end

local function use_collection_as_explosion_source(app)
  local col = selected_collection(app)
  if not col then return end

  app.explosion.source_folder = col.path
  app.explosion.recursive = col.recursive ~= false
  app.explosion.found_files = nil
  app.explosion.files = nil
  app.explosion.cat_counts = nil
  app.explosion.keyword_counts = nil
  app.explosion.result = nil
  app.view = "explosion"
end

local function use_folder_as_explosion_source(app, folder_path, recursive)
  local folder = Scanner.normalize(folder_path or "")
  if folder == "" then return false end
  app.explosion.source_folder = folder
  app.explosion.recursive = recursive ~= false
  app.explosion.found_files = nil
  app.explosion.files = nil
  app.explosion.cat_counts = nil
  app.explosion.keyword_counts = nil
  app.explosion.result = nil
  app.view = "explosion"
  return true
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
      draw_existing_pool_menu(app, "col_" .. tostring(col.id), col.path)
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

    -- Writes out what the file list is showing, so the filters are the
    -- selection: this is the same export the heatmap offers, for the other
    -- half of the browser. Only on the open collection, since the filtered
    -- set belongs to that one and would not be rebuilt until the next frame.
    local is_open = state.selected_id == col.id
    local shown = is_open and #(state.filtered_files or {}) or 0
    r.ImGui_BeginDisabled(ctx, not is_open or shown == 0)
    if r.ImGui_MenuItem(ctx, string.format("Export %s as a kit folder\226\128\166##export_kit_%s",
        is_open and (shown .. " sample" .. (shown == 1 and "" or "s")) or "list", col.id)) then
      export_filtered_as_kit(app)
    end
    r.ImGui_EndDisabled(ctx)
    if r.ImGui_IsItemHovered(ctx, r.ImGui_HoveredFlags_AllowWhenDisabled and r.ImGui_HoveredFlags_AllowWhenDisabled() or nil) then
      r.ImGui_SetTooltip(ctx, is_open
        and "Copy the samples the list is showing into a new kit folder,\nnumbered and renamed. The tag and filename filters decide what goes in."
        or "Open this collection first -- the export follows the filters on screen.")
    end

    r.ImGui_Separator(ctx)

    if r.ImGui_MenuItem(ctx, "Set Cover##" .. col.id) then
      local image = Dialogs.browse_file("Select collection cover", col.cover_path or col.path, "", "cover")
      if image then
        local ok_cover, err = validate_cover_image(state, image)
        if ok_cover then
          if col.cover_path and state.cover_cache[col.cover_path] then
            state.cover_cache[col.cover_path] = nil
          end
          col.cover_path = image
          state.preview_error = nil
          save(app)
        else
          state.preview_error = err or "Selected file is not a supported image."
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
    sample_menu_items(app, file_path)
    r.ImGui_EndPopup(ctx)
  end
end

-- The body of the sample right-click menu, shared by the list rows and the
-- heatmap cells.
sample_menu_items = function(app, file_path)
  local ctx = app.ctx
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
        local pick = Dialogs.browse_folder("Locate folder for " .. (col.name or "collection"), remapped or col.path, "source")
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

  if state.browser_mode == "packs" and col and col.recursive ~= false
      and state.list_flat ~= true then
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
      local folder_open = r.ImGui_CollapsingHeader(ctx, label)
      if folder_open then
        for _, f in ipairs(group.files) do
          draw_sample_row(app, f)
        end
      end
      if r.ImGui_IsItemHovered(ctx) and group.dir ~= "(Root)" then
        r.ImGui_SetTooltip(ctx, group.dir)
      end
      if r.ImGui_BeginPopupContextItem(ctx, "##folder_group_ctx_" .. tostring(i)) then
        local folder_path
        if group.dir == "(Root)" then
          folder_path = base
        elseif base ~= "" then
          folder_path = base .. "/" .. group.dir
        else
          folder_path = group.dir
        end
        folder_path = Scanner.normalize(folder_path)
        local folder_alias = group.dir == "(Root)" and (col.name or file_leaf(folder_path)) or file_leaf(folder_path)

        if r.ImGui_MenuItem(ctx, "Use for Explosion##folder_explosion_" .. tostring(i)) then
          local ok = use_folder_as_explosion_source(app, folder_path, true)
          if not ok then
            state.preview_error = "Kon folder niet als Explosion bron instellen."
          end
        end

        r.ImGui_Separator(ctx)

        if r.ImGui_MenuItem(ctx, "Add as Builder Pool##folder_pool_new_" .. tostring(i)) then
          local ok = add_folder_as_pool(app, folder_path, folder_alias)
          if ok then
            state.preview_error = "Folder toegevoegd als nieuwe Builder pool: " .. tostring(folder_alias)
          else
            state.preview_error = "Kon folder niet als pool toevoegen."
          end
        end

        draw_existing_pool_menu(app, "grp_" .. tostring(i), folder_path)

        r.ImGui_EndPopup(ctx)
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
    local min_tile = TILE_SIZES[state.tile_size] or TILE_SIZES.normal
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
        local cover_path = c.cover_path
        local tex = cover_texture(state, cover_path)
        local cover_drawn = false
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
          local ok_draw = pcall(r.ImGui_Image, ctx, tex, draw_w, draw_h)
          if ok_draw then
            cover_drawn = true
          else
            if cover_path and state.cover_cache then
              state.cover_cache[cover_path] = false
            end
            c.cover_path = nil
            state.preview_error = "Cover image kon niet worden geladen en is verwijderd."
            save(app)
          end
        end
        if not cover_drawn then
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

-- Analysis ------------------------------------------------------------------
--
-- Analysis is never started on its own: scanning a pack costs orders of
-- magnitude more than the duration prefetch, and REAPER is a DAW -- taking CPU
-- unasked during a take is not acceptable. So a whole collection is only
-- measured when the user presses the button, the job yields on a wall-clock
-- budget that shrinks during playback and drops to zero while recording, and
-- Stop is safe because every result is cached the moment it is measured.
--
-- The one exception is the sample the user just clicked on: auditioning
-- decodes it anyway, so measuring that single file is free and keeps the
-- readout populated as you browse.

local TAG_POPUP_W = 430      -- fixed width of the tag filter popup; chips wrap
local GRID_MIN_CELL = 44     -- smallest heatmap cell; below this the panel scrolls
local TAG_BODY_H = 90        -- drawn content of the tags panel
local TAG_PADDING = 6        -- its own window padding: the theme's 14 is too costly here
local ANALYSIS_PANEL_H = TAG_BODY_H + TAG_PADDING * 2 + 2
local CHILD_SPACING = 8      -- StyleVar_ItemSpacing y, see core/theme.lua

local function fmt_eta(seconds)
  if not seconds or seconds <= 0 then return "" end
  if seconds < 60 then return string.format("~%ds left", math.ceil(seconds)) end
  return string.format("~%dm left", math.ceil(seconds / 60))
end

local function step_analysis(app)
  local state = app.browser
  local job = state.analysis_job
  if not job then return end
  if not job:step(Tags.frame_budget()) then
    -- Kept so a change to the analyser can be compared against a number rather
    -- than a feeling: rescan the same pack and read this off.
    if job.index > 0 and job.elapsed > 0 then
      state.analysis_rate_ms = job.elapsed / job.index * 1000
    end
    state.analysis_job = nil
    state.analysis_count = Tags.count_analyzed(state.files)
  end
end

local function start_analysis(app, force)
  local state = app.browser
  state.analysis_note = nil
  if state.analysis_job then state.analysis_job:cancel() end
  state.analysis_job = Tags.new_job(state.files or {}, force)
  if state.analysis_job.total == 0 then state.analysis_job = nil end
end

local function draw_analysis_bar(app)
  local ctx = app.ctx
  local state = app.browser
  local c = Theme.colors
  local job = state.analysis_job

  if not Analyzer.available() then
    local pushed = Theme.push_small(ctx)
    r.ImGui_TextColored(ctx, c.text_faint, "Sample analysis needs a newer REAPER build.")
    Theme.pop_font(ctx, pushed)
    return
  end

  local total = #(state.files or {})
  local done = state.analysis_count or 0
  local btn_w = 74

  -- Room for the count/ETA text, the Analyse/Stop button, the options button
  -- and the spacing between them.
  local avail = as_number(r.ImGui_GetContentRegionAvail(ctx)) or 300
  local bar_w = math.max(60, avail - btn_w - 172)

  -- Progress track. Doubles as the "how much of this pack is measured" readout
  -- when no job is running, so the state is always visible at a glance.
  local x, y = r.ImGui_GetCursorScreenPos(ctx)
  local dl = r.ImGui_GetWindowDrawList(ctx)
  local h = 8
  local cy = y + math.floor((r.ImGui_GetFrameHeight(ctx) - h) * 0.5)
  local frac = total > 0 and (done / total) or 0
  if job and job.total > 0 then
    frac = total > 0 and ((total - job.total + job.index) / total) or 0
  end
  if frac < 0 then frac = 0 elseif frac > 1 then frac = 1 end

  r.ImGui_DrawList_AddRectFilled(dl, x, cy, x + bar_w, cy + h, c.frame_bg, h * 0.5)
  if frac > 0 then
    local fill = job and c.accent or (done >= total and c.success or c.accent_soft)
    r.ImGui_DrawList_AddRectFilled(dl, x, cy, x + bar_w * frac, cy + h, fill, h * 0.5)
  end
  r.ImGui_Dummy(ctx, bar_w, r.ImGui_GetFrameHeight(ctx))

  r.ImGui_SameLine(ctx)
  local label
  if job then
    label = string.format("%d / %d  %s", done + job.index, total, fmt_eta(job:eta()))
  elseif total == 0 then
    label = "No samples"
  elseif done >= total then
    label = string.format("%d analysed%s", total,
      state.analysis_rate_ms and string.format("  \226\128\148  %.0f ms each", state.analysis_rate_ms) or "")
  else
    label = string.format("%d / %d analysed", done, total)
  end
  local pushed = Theme.push_small(ctx)
  r.ImGui_AlignTextToFramePadding(ctx)
  r.ImGui_TextColored(ctx, job and c.accent or c.text_dim,
    (not job and state.analysis_note) or label)
  Theme.pop_font(ctx, pushed)
  if not job and state.analysis_note and r.ImGui_IsItemHovered(ctx) then
    r.ImGui_SetTooltip(ctx, label)
  end

  r.ImGui_SameLine(ctx)
  if job then
    if Theme.ghost_button(ctx, "Stop##analysis_stop", btn_w, 0) then
      if job.index > 0 and job.elapsed > 0 then
        state.analysis_rate_ms = job.elapsed / job.index * 1000
      end
      job:cancel()
      state.analysis_job = nil
      state.analysis_count = Tags.count_analyzed(state.files)
    end
    if r.ImGui_IsItemHovered(ctx) then
      r.ImGui_SetTooltip(ctx, "Stop analysing.\nEverything measured so far is kept -- restarting picks up where this left off.")
    end
  else
    local can = total > 0 and done < total
    r.ImGui_BeginDisabled(ctx, not can)
    if Theme.ghost_button(ctx, "Analyse##analysis_start", btn_w, 0) then
      start_analysis(app, false)
    end
    r.ImGui_EndDisabled(ctx)
    if r.ImGui_IsItemHovered(ctx) then
      r.ImGui_SetTooltip(ctx, can
        and "Measure every sample in this collection.\nRuns in the background, pauses while REAPER records, and can be stopped at any time."
        or "Every sample in this collection has been measured.")
    end
  end

  r.ImGui_SameLine(ctx)
  if Theme.ghost_button(ctx, "\226\139\175", 26, 0) then
    r.ImGui_OpenPopup(ctx, "##analysis_menu")
  end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Analysis options") end

  if r.ImGui_BeginPopup(ctx, "##analysis_menu") then
    if r.ImGui_MenuItem(ctx, "Re-analyse this collection") then
      start_analysis(app, true)
    end
    -- Cheaper than re-analysing everything: check the files against disk and
    -- only re-measure the ones that changed.
    if r.ImGui_MenuItem(ctx, "Re-analyse changed files") then
      local stale = Tags.stale_files(state.files or {})
      for _, f in ipairs(stale) do Tags.forget_if_stale(f) end
      state.analysis_count = Tags.count_analyzed(state.files)
      if #stale > 0 then
        start_analysis(app, false)
      end
      state.analysis_note = #stale > 0
        and string.format("%d changed file%s to re-measure.", #stale, #stale == 1 and "" or "s")
        or "Nothing has changed on disk."
    end
    if r.ImGui_IsItemHovered(ctx) then
      r.ImGui_SetTooltip(ctx, "Compares every sample with the file on disk and\nre-measures the ones that were edited or replaced.")
    end
    r.ImGui_Separator(ctx)
    local t_changed, t_value = r.ImGui_Checkbox(ctx, "Show tags panel", state.show_tags ~= false)
    if t_changed then
      state.show_tags = t_value
      save(app)
    end
    r.ImGui_Separator(ctx)
    if r.ImGui_MenuItem(ctx, string.format("Clear analysis cache (%d files)", Tags.cache_size())) then
      if state.analysis_job then
        state.analysis_job:cancel()
        state.analysis_job = nil
      end
      Tags.clear_cache()
      state.analysis_count = 0
    end
    r.ImGui_EndPopup(ctx)
  end
end

-- Tag filter ----------------------------------------------------------------
--
-- A real filter, unlike the character bias in Explosion and Builder: searching
-- for the noise hats should give the noise hats. Only labels that occur in the
-- collection are offered, with faceted counts, so the list never offers AIR on
-- a pack of kicks.

local function draw_tag_filter(app)
  local ctx = app.ctx
  local state = app.browser
  local c = Theme.colors
  local active = Tags.filter_count(state.tag_filter)

  if active > 0 then
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), c.accent)
  end
  if Theme.ghost_button(ctx, (active > 0 and string.format("Tags (%d)", active) or "Tags")
      .. "##tag_filter_btn", 74, 0) then
    r.ImGui_OpenPopup(ctx, "##tag_filter_popup")
  end
  if active > 0 then r.ImGui_PopStyleColor(ctx) end
  if r.ImGui_IsItemHovered(ctx) then
    r.ImGui_SetTooltip(ctx, "Filter the list by what the samples sound like.\nOnly tags present in this collection are offered.")
  end

  -- Fixed width, free height: seventeen category chips on one line would drag
  -- the popup off the screen, so the width is pinned and the chips wrap.
  if r.ImGui_SetNextWindowSizeConstraints then
    r.ImGui_SetNextWindowSizeConstraints(ctx, TAG_POPUP_W, 0, TAG_POPUP_W, 100000)
  end
  if not r.ImGui_BeginPopup(ctx, "##tag_filter_popup") then return end

  local facets = state.tag_facets or {}
  local any_offered = false
  local changed = false

  for _, axis_id in ipairs(Tags.FILTER_AXES) do
    local list = facets[axis_id] or {}
    if #list > 0 then
      any_offered = true
      -- The small font stays pushed across the chips too: the widths below are
      -- measured with CalcTextSize, so it has to be the font they are drawn in.
      local pushed = Theme.push_small(ctx)
      Theme.label(ctx, Tags.FILTER_LABELS[axis_id])

      local picked = state.tag_filter[axis_id] or {}
      local win_x = as_number(r.ImGui_GetWindowPos(ctx)) or 0
      local win_w = as_number(r.ImGui_GetWindowWidth(ctx)) or TAG_POPUP_W
      local right_edge = win_x + win_w - 14

      for i, entry in ipairs(list) do
        local shown = string.format("%s (%d)", entry.label, entry.n)
        local chip_w = (as_number(r.ImGui_CalcTextSize(ctx, shown)) or 40) + 20
        if i > 1 then
          -- Stay on this line only while the next chip still fits on it.
          local last_x2 = as_number(r.ImGui_GetItemRectMax(ctx)) or 0
          if last_x2 + 4 + chip_w < right_edge then
            r.ImGui_SameLine(ctx, 0, 4)
          end
        end

        local on = picked[entry.label] == true
        if on then
          r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), c.accent_soft)
          r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0xFFFFFFFF)
        end
        -- A count of 0 only happens for a label you have selected that nothing
        -- else allows through; keep it clickable so it can be switched off.
        if r.ImGui_SmallButton(ctx, shown .. "##tf_" .. axis_id .. "_" .. entry.label) then
          picked[entry.label] = (not on) or nil
          state.tag_filter[axis_id] = picked
          changed = true
        end
        if on then r.ImGui_PopStyleColor(ctx, 2) end
      end
      Theme.pop_font(ctx, pushed)
      r.ImGui_Dummy(ctx, 0, 2)
    end
  end

  if not any_offered then
    Theme.label(ctx, "Nothing analysed in this collection yet.")
  end

  -- Only worth saying when a MEASURED axis is on: a Source filter reads the
  -- filename, so it does not hide anything for want of analysis.
  if (state.tag_unmeasured or 0) > 0 and Tags.filter_needs_analysis(state.tag_filter) then
    local pushed = Theme.push_small(ctx)
    r.ImGui_TextColored(ctx, c.text_faint, string.format(
      "%d unanalysed samples are hidden while a measured tag is selected.", state.tag_unmeasured))
    Theme.pop_font(ctx, pushed)
  end

  if any_offered then
    r.ImGui_Separator(ctx)
    r.ImGui_BeginDisabled(ctx, active == 0)
    if Theme.ghost_button(ctx, "Clear all##tag_filter_clear", 90, 0) then
      state.tag_filter = Tags.new_filter()
      changed = true
    end
    r.ImGui_EndDisabled(ctx)
  end

  r.ImGui_EndPopup(ctx)
  if changed then apply_filter(app) end
end

-- Tags panel ----------------------------------------------------------------

local function draw_chip(ctx, dl, x, y, text, bg, fg)
  local tw = as_number(r.ImGui_CalcTextSize(ctx, text)) or 30
  local w = tw + 12
  r.ImGui_DrawList_AddRectFilled(dl, x, y, x + w, y + 17, bg, 4)
  r.ImGui_DrawList_AddText(dl, x + 6, y + 2, fg, text)
  return w + 5
end

local function draw_rail(ctx, dl, x, y, w, value, name, value_label)
  local c = Theme.colors
  local name_w = 62
  local val_w = 60
  r.ImGui_DrawList_AddText(dl, x, y, c.text_faint, name)

  local rx = x + name_w
  local rw = math.max(24, w - name_w - val_w)
  local cy = y + 7
  r.ImGui_DrawList_AddRectFilled(dl, rx, cy - 2, rx + rw, cy + 2, c.frame_bg, 2)
  if value then
    local px = rx + rw * value
    r.ImGui_DrawList_AddRectFilled(dl, rx, cy - 2, px, cy + 2, c.accent_soft, 2)
    r.ImGui_DrawList_AddCircleFilled(dl, px, cy, 4.5, c.accent)
  end
  r.ImGui_DrawList_AddText(dl, rx + rw + 10, y, value and c.text or c.text_faint, value_label or "\226\128\148")
end

local function draw_tag_panel(app)
  local ctx = app.ctx
  local state = app.browser
  local c = Theme.colors
  local path = state.selected_file

  local pushed = Theme.push_small(ctx)
  local dl = r.ImGui_GetWindowDrawList(ctx)
  local x0, y0 = r.ImGui_GetCursorScreenPos(ctx)
  local w = math.max(240, (as_number(r.ImGui_GetContentRegionAvail(ctx)) or 300) - 4)

  if not path then
    r.ImGui_DrawList_AddText(dl, x0, y0 + 4, c.text_faint, "Select a sample to see its tags.")
    r.ImGui_Dummy(ctx, w, 22)
    Theme.pop_font(ctx, pushed)
    return
  end

  -- The file the user is looking at gets measured on the spot: it costs a few
  -- milliseconds and it is already being decoded for auditioning anyway.
  --
  -- Once per selection it is also checked against disk, so a sample you just
  -- re-rendered shows its new measurements rather than yesterday's. Once, not
  -- every frame: that check opens the file.
  if Analyzer.available() then
    if state.tag_checked_path ~= path then
      state.tag_checked_path = path
      Tags.forget_if_stale(path)
    end
    Tags.ensure(path)
  end
  local t = Tags.tags(path)
  local labels = t.labels

  -- Row 1: the labels themselves.
  local cx = x0
  if t.category then
    cx = cx + draw_chip(ctx, dl, cx, y0, t.category:upper(), c.accent_soft, 0xFFFFFFFF)
  end
  if labels then
    cx = cx + draw_chip(ctx, dl, cx, y0, labels.band, c.frame_bg, c.text)
    cx = cx + draw_chip(ctx, dl, cx, y0, labels.transient, c.frame_bg, c.text)
    cx = cx + draw_chip(ctx, dl, cx, y0, labels.decay, c.frame_bg, c.text)
    cx = cx + draw_chip(ctx, dl, cx, y0, labels.tonality, c.frame_bg, c.text)
    if labels.space then
      cx = cx + draw_chip(ctx, dl, cx, y0, labels.space, c.frame_bg, c.text)
    end
  end
  if t.source then
    -- A source read from a folder name is a guess about the pack, not about
    -- this sample, so it is drawn as one.
    cx = cx + draw_chip(ctx, dl, cx, y0, t.source .. (t.source_from_file and "" or "?"),
      c.frame_bg, t.source_from_file and c.text_dim or c.text_faint)
  end
  if not labels then
    r.ImGui_DrawList_AddText(dl, cx, y0 + 2, c.text_faint,
      Analyzer.available() and "not measurable (silent or unreadable)" or "analysis unavailable")
  end

  -- Row 2, left: the spectrum across the seven bands. Dropped on a narrow
  -- panel, where the axis rails are the more useful half.
  local by = y0 + 26
  local bars_w = 132
  local compact = w < 340
  if not compact then
    local bar_h = 40
    local bw = bars_w / Analyzer.BAND_COUNT
    local bands = t.metrics and t.metrics.bands
    for i = 1, Analyzer.BAND_COUNT do
      local bx = x0 + (i - 1) * bw
      local x2 = bx + bw - 3
      r.ImGui_DrawList_AddRectFilled(dl, bx, by, x2, by + bar_h, c.frame_bg, 2)
      local v = bands and bands[i] or 0
      if v > 0 then
        local fh = math.max(2, v * bar_h)
        local hot = t.axes and i == t.axes.band
        r.ImGui_DrawList_AddRectFilled(dl, bx, by + bar_h - fh, x2, by + bar_h,
          hot and c.accent or c.accent_dim, 2)
      end
    end
    r.ImGui_DrawList_AddText(dl, x0, by + bar_h + 3, c.text_faint, "SUB")
    local air_w = as_number(r.ImGui_CalcTextSize(ctx, "AIR")) or 20
    r.ImGui_DrawList_AddText(dl, x0 + bars_w - air_w - 3, by + bar_h + 3, c.text_faint, "AIR")
  end

  -- Row 2, right: where this sample sits on each continuous axis.
  local rx = compact and x0 or (x0 + bars_w + 18)
  local rw = compact and w or math.max(150, w - bars_w - 18)
  local a = t.axes
  for i, axis in ipairs(Tags.AXES) do
    local value = a and a[axis.key] or nil
    local vlabel = labels and labels[axis.id] or nil
    if axis.id == "tone" then vlabel = labels and labels.band or nil end
    draw_rail(ctx, dl, rx, by + (i - 1) * 15, rw, value, axis.label, vlabel)
  end

  -- Hovering shows the raw measurements -- the numbers behind every label, so
  -- they can be checked against what the sample actually sounds like.
  r.ImGui_Dummy(ctx, w, TAG_BODY_H)
  if r.ImGui_IsItemHovered(ctx) and t.metrics then
    local m = t.metrics
    local source_note = ""
    if t.source and not t.source_from_file then
      source_note = "\n\nSource '" .. t.source .. "?' comes from a folder name, not from this\nfile -- a guess about the pack rather than about the sample."
    end
    r.ImGui_SetTooltip(ctx, string.format(
      "attack %.2f ms\ndecay to -40 dB %.0f ms\ncentroid %.0f Hz\nflatness %.3f\ncrest %.1f dB\n%s\n\n"
        .. "Spatiality needs stereo; texture is not measured yet.%s",
      m.attack_ms, m.decay_ms, m.centroid, m.flat, m.crest_db,
      (m.nch or 1) >= 2 and string.format("stereo, width %.2f", m.width) or "mono",
      source_note))
  end

  Theme.pop_font(ctx, pushed)
end

-- Heatmap ------------------------------------------------------------------
--
-- Two measured axes on a grid, the third on a slider that weights rather than
-- filters. Clicking a cell hands back a random sample from that region, drawn
-- with the same weighting that shades it. See core/heatmap.lua for the logic.

local function lerp_color(a, b, t)
  if t <= 0 then return a end
  if t >= 1 then return b end
  local out = 0
  for _, shift in ipairs({ 24, 16, 8, 0 }) do
    local ca = (a >> shift) & 0xFF
    local cb = (b >> shift) & 0xFF
    out = out | ((math.floor(ca + (cb - ca) * t + 0.5) & 0xFF) << shift)
  end
  return out
end

-- The grid's hot colour follows the slider, so the whole map visibly shifts
-- character as you sweep it -- accent at the soft end through to danger at the
-- hard end. Built from theme colours so it stays coherent in all eight themes.
local function hot_color(center)
  local c = Theme.colors
  if center < 0.5 then return lerp_color(c.accent, c.warning, center * 2) end
  return lerp_color(c.warning, c.danger, (center - 0.5) * 2)
end

local function ensure_grid(app)
  local state = app.browser
  -- Rebuilding walks every file, so it is keyed on everything that can change
  -- the placement. While a job runs the key also ticks every 200 files, so the
  -- grid fills in visibly as the collection is measured without being rebuilt
  -- on every frame.
  local job = state.analysis_job
  local key = table.concat({
    tostring(state.selected_id), tostring(state.search), Tags.filter_key(state.tag_filter),
    tostring(state.grid_x), tostring(state.grid_y), tostring(state.grid_size),
    tostring(#(state.filtered_files or {})), tostring(state.analysis_count),
    job and tostring(math.floor(job.index / 200)) or "-",
  }, "|")

  if state.grid_key ~= key then
    state.grid = Heatmap.build(state.filtered_files or {}, {
      size = state.grid_size, x = state.grid_x, y = state.grid_y,
    })
    state.grid_key = key
    state.grid_shade_key = nil
    -- The cell indices a pick or a walk refers to only mean anything for the
    -- grid they came from, so a rebuild retires both.
    state.grid_pick = nil
    state.grid_walk = nil
    state.grid_kit_cells = nil
  end

  local shade_key = string.format("%.4f|%.4f", state.grid_center or 0.5, state.grid_focus or 0.6)
  if state.grid_shade_key ~= shade_key then
    Heatmap.shade(state.grid, state.grid_center or 0.5, state.grid_focus or 0.6)
    state.grid_shade_key = shade_key
    -- The slider moved, so the running order it produced no longer holds and
    -- the position shown alongside it would be a stale number.
    state.grid_pick = nil
    state.grid_walk = nil
  end
  return state.grid
end

local function shift_held(ctx)
  if r.ImGui_GetKeyMods and r.ImGui_Mod_Shift then
    return (r.ImGui_GetKeyMods(ctx) & r.ImGui_Mod_Shift()) ~= 0
  end
  return false
end

-- Repeated clicks on the same cell walk through it rather than rolling the dice
-- again: the weighting sets the ORDER, so the best match for the slider still
-- comes first, but clicking on lets you hear the whole cell without repeats.
-- Shift steps back the other way; both wrap around.
--
-- The order stays put for as long as you are in the cell, which is what makes
-- "12 of 33" a position you can walk back to rather than a number that moved.
-- Leaving the cell or moving the slider draws a fresh one, so a later visit is
-- not a rerun.
local function step_cell_walk(app, grid, row, col, backwards)
  local state = app.browser
  local center, focus = state.grid_center or 0.5, state.grid_focus or 0.6
  local walk = state.grid_walk
  local fresh = false

  if not walk or walk.row ~= row or walk.col ~= col or not walk.order then
    walk = { row = row, col = col, order = Heatmap.cell_order(grid, row, col, center, focus), pos = 0 }
    state.grid_walk = walk
    fresh = true
  end
  if not walk.order or #walk.order == 0 then return nil end
  local n = #walk.order

  if backwards then
    -- Stepping back into a cell you have not opened yet enters it from the end.
    walk.pos = fresh and n or (walk.pos - 1)
    if walk.pos < 1 then walk.pos = n end
  else
    walk.pos = walk.pos + 1
    if walk.pos > n then walk.pos = 1 end
  end

  return Heatmap.item_path(grid, row, col, walk.order[walk.pos]), walk.pos, n
end

-- Slot -> existing track, using the SAME rule the Kit Manager draws its pads
-- with: the RS5K note when it resolves, otherwise the child's position in the
-- folder (see rs5k_manager_view.lua, grid_slot).
--
-- collect_rack_slot_usage() goes by note alone, which is right for finding a
-- free slot but wrong here: on a rack whose children carry no usable note every
-- pad looks empty, and filling then appends a second set of children underneath
-- instead of replacing the ones already there.
local function rack_tracks_by_slot(parent)
  local by_slot, index, pads = {}, 0, 0
  each_child_track(parent, function(tr)
    index = index + 1
    local slot
    local fx = find_rs5k_fx(tr)
    if fx >= 0 then
      local note = get_rs5k_note(tr, fx)
      if note and note >= RS5K_BASE_NOTE and note <= 127 then
        slot = (note - RS5K_BASE_NOTE) + 1
      end
    end
    if not slot or slot < 1 or slot > KIT_RACK_SLOTS then slot = index end
    if slot >= 1 and slot <= KIT_RACK_SLOTS and not by_slot[slot] then
      by_slot[slot] = tr
      pads = pads + 1
    end
  end)
  return by_slot, pads, index
end

-- Rack -> grid --------------------------------------------------------------
--
-- Reads the samples off the selected rack and works out where each pad sits in
-- the pack's spread, so a kit that huddles in one corner shows itself.

local function collection_file_set(app)
  local set = {}
  for _, f in ipairs(app.browser.files or {}) do
    set[(tostring(f):gsub("\\", "/"):lower())] = true
  end
  return set
end

local function collect_rack_points(app, grid)
  local parent = get_selected_rack_parent_track()
  if not parent then
    return nil, "Select a track inside the rack you want to see."
  end
  local by_slot, pads = rack_tracks_by_slot(parent)
  if pads == 0 then
    return nil, "No rack pads found on the selected track."
  end

  local x_key, y_key = grid.x_axis.key, grid.y_axis.key
  local in_collection = collection_file_set(app)
  local points, unmeasured, from_here = {}, 0, 0

  for slot = 1, KIT_RACK_SLOTS do
    local tr = by_slot[slot]
    local fx = tr and find_rs5k_fx(tr) or -1
    local path = fx >= 0 and get_rs5k_file(tr, fx) or nil
    if path and path ~= "" then
      -- Sixteen files is a moment's work, and measuring them here saves having
      -- to go and analyse the kit's folder separately first.
      if Analyzer.available() then Tags.ensure(path) end
      local axes = Tags.axes(path)
      if axes then
        points[#points + 1] = { label = tostring(slot), x = axes[x_key], y = axes[y_key], path = path }
        if in_collection[(path:gsub("\\", "/"):lower())] then from_here = from_here + 1 end
      else
        unmeasured = unmeasured + 1
      end
    end
  end

  if #points == 0 then
    return nil, unmeasured > 0
      and "None of this rack's samples could be measured."
      or "This rack has no samples loaded."
  end
  return points, nil, unmeasured, from_here
end

local function refresh_rack_overlay(app, grid)
  local state = app.browser
  -- Tied to the grid it was projected onto: different axes or a different
  -- filter and the cell coordinates mean something else. Recorded even when the
  -- read fails, so a failure is not retried on every frame.
  state.grid_kit_key = state.grid_key
  local points, err, unmeasured, from_here = collect_rack_points(app, grid)
  state.grid_kit_points = points
  state.grid_kit_note = err
  state.grid_kit_warn = err ~= nil
  if not points then
    state.grid_kit_cells = nil
    return
  end

  local cells, clamped = Heatmap.project(grid, points)
  state.grid_kit_cells = cells

  -- The grid's axes are fitted to the collection on screen. Against a rack that
  -- came from somewhere else that is the wrong yardstick -- the pads are placed
  -- honestly, but "clustered in a corner" then says nothing about the kit. Say
  -- so rather than let it read as a finding.
  from_here = from_here or 0
  if from_here == 0 then
    state.grid_kit_warn = true
    state.grid_kit_note = string.format(
      "%d pads placed, but none are from this collection \226\128\148 the axes are scaled to other samples.", #points)
  elseif from_here < #points then
    state.grid_kit_warn = true
    state.grid_kit_note = string.format(
      "%d pads on the grid; %d are not from this collection.", #points, #points - from_here)
  else
    state.grid_kit_warn = false
    state.grid_kit_note = string.format("%d pads on the grid%s%s", #points,
      clamped > 0 and string.format(", %d outside the range", clamped) or "",
      (unmeasured or 0) > 0 and string.format(", %d unmeasured", unmeasured) or "")
  end
end

-- Grid -> rack --------------------------------------------------------------
--
-- One weighted pick per cell. Empty cells stay empty: a pack that has nothing
-- in a corner should show that, not have the gap papered over.
local function picks_from_grid(app, grid)
  local state = app.browser
  local picks, filled = {}, 0
  for row = 1, grid.size do
    for col = 1, grid.size do
      local path = Heatmap.pick(grid, row, col, state.grid_center or 0.5, state.grid_focus or 0.6)
      if path then
        picks[Heatmap.pad_slot(grid, row, col)] = { sample_path = path, sample_name = file_stem(path) }
        filled = filled + 1
      end
    end
  end
  return picks, filled
end

-- Fills the rack the user is sitting in. This REPLACES and never grows: pads
-- the rack does not have are skipped rather than appended.
--
-- Appending was the earlier behaviour and it is the wrong contract for an
-- action called "fill the selected rack" -- any mismatch between the grid's 16
-- cells and the rack's pads silently doubled the track count instead of doing
-- nothing visible. If you want a full 16-pad kit, "Create a new rack" is the
-- option that builds one.
local function fill_selected_rack_from_grid(app, picks)
  local state = app.browser
  local parent = get_selected_rack_parent_track()
  if not parent then
    state.preview_error = "Select a track inside the rack you want to fill first."
    return false
  end

  local existing, pads, children = rack_tracks_by_slot(parent)
  if pads == 0 then
    state.preview_error = children > 0
      and "Could not match the pads in this rack. Try 'Create a new rack'."
      or "That folder has no rack pads in it."
    return false
  end

  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)
  local replaced, skipped = 0, 0
  for slot = 1, KIT_RACK_SLOTS do
    local item = picks[slot]
    if item then
      local tr = existing[slot]
      if tr then
        local note = RS5K_BASE_NOTE + (slot - 1)
        if load_sample_into_rs5k(tr, item.sample_path, note) then
          r.GetSetMediaTrackInfo_String(tr, "P_NAME", item.sample_name, true)
          RS5K.set_note_name(parent, note, role_of(item.sample_path))
          replaced = replaced + 1
        end
      else
        skipped = skipped + 1
      end
    end
  end
  r.PreventUIRefresh(-1)
  r.TrackList_AdjustWindows(false)
  r.UpdateArrange()
  r.Undo_EndBlock("TK Kit Maker: Fill rack from heatmap", -1)

  state.preview_error = nil
  -- The pad count is reported so a mismatch is visible rather than mysterious.
  state.grid_fill_note = skipped > 0
    and string.format("Replaced %d of %d pads; %d cells had no pad.", replaced, pads, skipped)
    or string.format("Replaced %d of %d pads.", replaced, pads)
  return true
end

-- Named after the tag filter when it points at exactly one category ("Kick Grid
-- Rack"), since that is what the grid is showing; otherwise after the
-- collection.
local function rack_name_for_grid(app)
  local state = app.browser
  local picked, count = nil, 0
  for label in pairs((state.tag_filter or {}).category or {}) do
    picked = label
    count = count + 1
  end

  local col = selected_collection(app)
  local base = (count == 1 and picked) or (col and col.name) or "Heatmap"
  return base .. " Grid Rack"
end

-- Writes the grid out as a kit folder rather than loading it into a rack.
local function export_kit_from_grid(app, picks)
  local state = app.browser
  local slots = {}
  for slot = 1, KIT_RACK_SLOTS do
    local item = picks[slot]
    if item then
      -- Numbered by pad, so a gap in the grid stays a gap in the filenames
      -- instead of quietly renumbering the kit.
      slots[#slots + 1] = {
        number = slot,
        midi_note = math.min(127, RS5K_BASE_NOTE + slot - 1),
        pad = slot,
        lock_file = item.sample_path,
      }
    end
  end

  local ok, note = export_kit_folder(app, slots,
    (rack_name_for_grid(app):gsub(" Grid Rack$", "") .. " Grid Kit"))
  state.preview_error = (not ok) and note or nil
  if ok then state.grid_fill_note = note end
  return ok
end

-- target: "selected" fills the rack the user is sitting in, "new" builds a
-- fresh one. Re-running either re-rolls the contents while the layout -- which
-- corner of the sound space each pad covers -- stays put.
local function build_kit_from_grid(app, grid, target)
  local state = app.browser
  if not grid or grid.size ~= 4 then
    state.preview_error = "Rack fill needs a 4\195\1974 grid."
    return false
  end

  local picks, filled = picks_from_grid(app, grid)
  if filled == 0 then
    state.preview_error = "No analysed samples in the grid to build from."
    return false
  end

  if target == "export" then
    local ok = export_kit_from_grid(app, picks)
    if ok then state.grid_last_target = "export" end
    return ok
  end

  if target == "selected" then
    local ok = fill_selected_rack_from_grid(app, picks)
    if ok then state.grid_last_target = "selected" end
    return ok
  end

  build_rs5k_rack(rack_name_for_grid(app), picks, KIT_RACK_SLOTS,
    "TK Kit Maker: Create rack from heatmap")
  state.preview_error = nil
  state.grid_fill_note = string.format("New rack with %d of %d pads filled.", filled, KIT_RACK_SLOTS)
  state.grid_last_target = "new"
  return true
end

local function draw_grid_toolbar(app)
  local ctx = app.ctx
  local state = app.browser

  -- No category picker of its own: the Tags button above already filters the
  -- list the grid is built from, and it does it better -- several categories at
  -- once, with counts. A second picker here did not replace that one, it ANDed
  -- with it, so Kick here and Snare there quietly produced an empty grid.

  -- The two grid axes are picked here; whichever of the three is left over
  -- automatically becomes the weighting slider below the grid.
  local first_combo = true
  local function axis_combo(id, current, other, tip)
    local picked = nil
    if not first_combo then r.ImGui_SameLine(ctx) end
    first_combo = false
    r.ImGui_SetNextItemWidth(ctx, 96)
    local axis = Tags.axis(current)
    if r.ImGui_BeginCombo(ctx, "##grid_axis_" .. id, axis and axis.label or "?") then
      for _, aid in ipairs(Heatmap.GRID_AXES) do
        if aid ~= other then
          local a = Tags.axis(aid)
          if r.ImGui_Selectable(ctx, a.label, aid == current) then picked = aid end
        end
      end
      r.ImGui_EndCombo(ctx)
    end
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, tip) end
    return picked
  end

  local pick_x = axis_combo("x", state.grid_x, state.grid_y, "Horizontal axis")
  if pick_x then
    state.grid_x = pick_x
    save(app)
  end
  local pick_y = axis_combo("y", state.grid_y, state.grid_x, "Vertical axis")
  if pick_y then
    state.grid_y = pick_y
    save(app)
  end

  r.ImGui_SameLine(ctx)
  r.ImGui_SetNextItemWidth(ctx, 78)
  local s_changed, s_value = r.ImGui_SliderInt(ctx, "##grid_size", state.grid_size or 4,
    Heatmap.MIN_SIZE, Heatmap.MAX_SIZE, "%d\194\1782")
  if s_changed then
    state.grid_size = s_value
    save(app)
  end
  if r.ImGui_IsItemHovered(ctx) then
    r.ImGui_SetTooltip(ctx, "Grid resolution. 4\195\1514 matches the pad layout.")
  end
end

local function draw_grid_cells(app, grid, x0, y0, area_w, area_h)
  local ctx = app.ctx
  local state = app.browser
  local c = Theme.colors
  local dl = r.ImGui_GetWindowDrawList(ctx)

  local gutter_l, gutter_b = 52, 16
  -- Floor chosen so the "12/33" readout still fits (it needs cell - 9 pixels of
  -- text width); below that a cell can only carry its ring and the panel is
  -- better off scrolling than shrinking further.
  local size = grid.size
  local cell = math.floor(math.min((area_w - gutter_l) / size, (area_h - gutter_b) / size))
  if cell < GRID_MIN_CELL then cell = GRID_MIN_CELL end
  local gx, gy = x0 + gutter_l, y0
  local hot = hot_color(state.grid_center or 0.5)
  local pick = state.grid_pick
  local kit_cells = state.grid_show_kit and state.grid_kit_cells or nil

  for row = 1, size do
    for col = 1, size do
      local cx1 = gx + (col - 1) * cell
      local cy1 = gy + (row - 1) * cell
      local cx2, cy2 = cx1 + cell - 3, cy1 + cell - 3
      local data = grid.cells[row][col]

      -- Gamma on the intensity: without it everything but the busiest cell
      -- reads as empty, and the point is to see the whole distribution.
      local fill = c.frame_bg
      if data.n > 0 then
        fill = lerp_color(c.frame_bg, hot, math.min(1, data.intensity) ^ 0.65)
      end
      r.ImGui_DrawList_AddRectFilled(dl, cx1, cy1, cx2, cy2, fill, 4)

      r.ImGui_SetCursorScreenPos(ctx, cx1, cy1)
      r.ImGui_InvisibleButton(ctx, string.format("##grid_%d_%d", row, col), cell - 3, cell - 3)
      local hovered = r.ImGui_IsItemHovered(ctx)

      -- Ring the cell the current sound came out of, so it stays findable even
      -- when the tiles are far too small to hold any text.
      local is_picked = pick and pick.row == row and pick.col == col
      if is_picked then
        r.ImGui_DrawList_AddRect(dl, cx1, cy1, cx2, cy2, c.accent, 4, 0, 2)
      end
      if hovered then
        r.ImGui_DrawList_AddRect(dl, cx1, cy1, cx2, cy2, c.text, 4, 0, 2)
      end

      -- Pads of the projected kit that land in this cell. Drawn on the window
      -- background rather than tinted, so they stay legible over any heat.
      local pads = kit_cells and kit_cells[row] and kit_cells[row][col]
      if pads then
        local pushed_pad = Theme.push_small(ctx)
        -- Badge size follows the real text metrics, so the number sits dead
        -- centre instead of near a hardcoded box.
        local _, text_h = r.ImGui_CalcTextSize(ctx, "8")
        text_h = as_number(text_h) or 12
        local bh = text_h + 4
        local by2 = cy2 - bh - 3
        local bx = cx1 + 3

        for i = 1, #pads do
          local entry = pads[i]
          local tw = as_number(r.ImGui_CalcTextSize(ctx, entry.label)) or 8
          local bw = tw + 8
          if bx + bw > cx2 - 3 then
            r.ImGui_DrawList_AddText(dl, bx, by2 + 2, c.text, "+" .. tostring(#pads - i + 1))
            break
          end
          -- Clamped pads are dimmed: they were pushed into this cell from
          -- outside the range, they do not belong to it.
          local edge = entry.clamped and c.text_faint or c.accent
          r.ImGui_DrawList_AddRectFilled(dl, bx, by2, bx + bw, by2 + bh, c.window_bg, 3)
          r.ImGui_DrawList_AddRect(dl, bx, by2, bx + bw, by2 + bh, edge, 3, 0, 1)
          r.ImGui_DrawList_AddText(dl, bx + (bw - tw) * 0.5, by2 + (bh - text_h) * 0.5, edge, entry.label)
          bx = bx + bw + 3
        end
        Theme.pop_font(ctx, pushed_pad)
      end

      if data.n > 0 then
        -- The picked cell reads "12/33" -- which of its samples is playing --
        -- and falls back to the plain count when the tile is too narrow for it.
        local txt = tostring(data.n)
        if is_picked then
          local wide = string.format("%d/%d", pick.index, data.n)
          if (as_number(r.ImGui_CalcTextSize(ctx, wide)) or 99) <= cell - 9 then txt = wide end
        end
        local tw = as_number(r.ImGui_CalcTextSize(ctx, txt)) or 10
        local col_txt = c.text_dim
        if is_picked then
          col_txt = c.accent
        elseif data.intensity > 0.55 then
          col_txt = 0xFFFFFFFF
        end
        r.ImGui_DrawList_AddText(dl, cx1 + (cell - 3 - tw) * 0.5, cy1 + (cell - 3) * 0.5 - 7, col_txt, txt)
      end

      if r.ImGui_IsItemClicked(ctx, 0) and data.n > 0 then
        local path, index, total = step_cell_walk(app, grid, row, col, shift_held(ctx))
        if path then
          state.selected_file = path
          state.grid_pick = { row = row, col = col, index = index, total = total, path = path }
          play_preview(app, path)
        end
      end
      if r.ImGui_IsItemClicked(ctx, 1) and data.n > 0 then
        -- Acts on what you are hearing; only starts a walk if this cell is not
        -- the one already playing.
        local path, index, total = nil, nil, nil
        if is_picked then
          path, index, total = pick.path, pick.index, pick.total
        else
          path, index, total = step_cell_walk(app, grid, row, col)
        end
        state.grid_menu_file = path
        if path then
          state.selected_file = path
          state.grid_pick = { row = row, col = col, index = index, total = total, path = path }
          r.ImGui_OpenPopup(ctx, "##grid_cell_menu")
        end
      end

      -- Also worth a tooltip when the cell is empty but holds a kit pad: that
      -- is a pad sitting where this pack has nothing.
      if hovered and (data.n > 0 or pads) then
        local xl, xh = Heatmap.cell_range(grid, col, "x")
        local yl, yh = Heatmap.cell_range(grid, row, "y")
        local playing = ""
        if pads then
          local here, off = {}, {}
          for _, entry in ipairs(pads) do
            local list = entry.clamped and off or here
            list[#list + 1] = entry.label
          end
          if #here > 0 then
            playing = "\n\nKit pads here: " .. table.concat(here, ", ")
          end
          if #off > 0 then
            playing = playing .. "\n\nPushed in from outside the range: " .. table.concat(off, ", ")
          end
        end
        if is_picked then
          playing = playing .. string.format("\n\nPlaying %d of %d:\n%s", pick.index, data.n, file_leaf(pick.path))
        end
        r.ImGui_SetTooltip(ctx, string.format(
          "%d samples\n%s %.0f-%.0f%%\n%s %.0f-%.0f%%%s\n\n"
            .. "Click to step through the cell, shift-click to step back,\nright-click for options.",
          data.n, grid.x_axis.label, xl * 100, xh * 100,
          grid.y_axis.label, yl * 100, yh * 100, playing))
      end
    end
  end

  if r.ImGui_BeginPopup(ctx, "##grid_cell_menu") then
    if state.grid_menu_file then
      local pushed = Theme.push_small(ctx)
      Theme.label(ctx, file_leaf(state.grid_menu_file))
      Theme.pop_font(ctx, pushed)
      r.ImGui_Separator(ctx)
      sample_menu_items(app, state.grid_menu_file)
    end

    -- The whole cell, rather than the one sample the walk is on: a corner of
    -- the sound space handed to the Builder as a pool.
    local at = state.grid_pick
    local cell = at and Heatmap.cell(grid, at.row, at.col)
    if cell and cell.n > 0 then
      r.ImGui_Separator(ctx)
      if r.ImGui_MenuItem(ctx, string.format("Add cell as Builder Pool (%d samples)", cell.n)) then
        add_cell_as_pool(app, at.row, at.col)
      end
      if r.ImGui_IsItemHovered(ctx) then
        r.ImGui_SetTooltip(ctx, string.format(
          "Make a pool of every sample in this cell, and open the Builder.\n"
            .. "Link a slot to it and that slot only ever draws\n%s.",
          cell_alias(grid, at.row, at.col):lower() .. " samples"))
      end
    end
    r.ImGui_EndPopup(ctx)
  end

  -- Axis ends. The grid is relative to the current selection, so these are the
  -- extremes of what is actually in it, not of the axis as a whole.
  local pushed = Theme.push_small(ctx)
  local grid_px = cell * size
  r.ImGui_DrawList_AddText(dl, x0, gy, c.text_faint, grid.y_axis.hi:upper())
  local ly = gy + grid_px - 16
  r.ImGui_DrawList_AddText(dl, x0, ly, c.text_faint, grid.y_axis.lo:upper())
  r.ImGui_DrawList_AddText(dl, gx, gy + grid_px + 1, c.text_faint, grid.x_axis.lo:upper())
  local hi_txt = grid.x_axis.hi:upper()
  local hw = as_number(r.ImGui_CalcTextSize(ctx, hi_txt)) or 24
  r.ImGui_DrawList_AddText(dl, gx + grid_px - hw - 3, gy + grid_px + 1, c.text_faint, hi_txt)
  Theme.pop_font(ctx, pushed)

  r.ImGui_SetCursorScreenPos(ctx, x0, gy + grid_px + gutter_b)
end

local function draw_heatmap(app)
  local ctx = app.ctx
  local state = app.browser
  local c = Theme.colors

  draw_grid_toolbar(app)

  local grid = ensure_grid(app)
  local avail_w, avail_h = r.ImGui_GetContentRegionAvail(ctx)
  avail_w = as_number(avail_w) or 300
  avail_h = as_number(avail_h) or 200
  -- Everything below the grid: axis caption, the two sliders, the rack button
  -- row and the status line. Derived from the real frame height rather than
  -- guessed -- the button row was what pushed this past the bottom edge.
  local frame_h = as_number(r.ImGui_GetFrameHeight(ctx)) or 28
  local footer_h = 2 + 16 + 8 + frame_h + 8 + frame_h + 8 + 16

  if grid.placed == 0 then
    if grid.unanalysed > 0 then
      Theme.label(ctx, string.format(
        "None of these %d samples has been analysed yet \226\128\148 press Analyse above.", grid.unanalysed))
    elseif Tags.filter_active(state.tag_filter) then
      Theme.label(ctx, string.format(
        "Nothing left after the tag filter (%d selected) \226\128\148 clear it in Tags above.",
        Tags.filter_count(state.tag_filter)))
    else
      Theme.label(ctx, "No samples match this filter.")
    end
    return
  end

  if state.grid_show_kit and state.grid_kit_key ~= state.grid_key then
    refresh_rack_overlay(app, grid)
  end

  local x0, y0 = r.ImGui_GetCursorScreenPos(ctx)
  draw_grid_cells(app, grid, x0, y0, avail_w, math.max(60, avail_h - footer_h))

  -- The weighting slider: the axis that is not on the grid.
  local w_axis = grid.weight_axis
  r.ImGui_Dummy(ctx, 0, 2)
  local pushed = Theme.push_small(ctx)
  Theme.label(ctx, string.format("%s  \226\128\148  %s to %s", w_axis.label, w_axis.lo, w_axis.hi))
  Theme.pop_font(ctx, pushed)

  r.ImGui_SetNextItemWidth(ctx, math.max(120, avail_w - 128))
  local changed, value = r.ImGui_SliderDouble(ctx, "##grid_weight", state.grid_center or 0.5, 0, 1, "%.2f")
  if changed then
    state.grid_center = value
    save(app)
  end
  if r.ImGui_IsItemHovered(ctx) then
    r.ImGui_SetTooltip(ctx, string.format(
      "Weighting, not a filter: no sample leaves the grid.\nCells holding %s material light up, and clicking one\nfavours those samples.",
      w_axis.label:lower()))
  end

  r.ImGui_SameLine(ctx)
  r.ImGui_SetNextItemWidth(ctx, 104)
  local f_changed, f_value = r.ImGui_SliderDouble(ctx, "##grid_focus", state.grid_focus or 0.6, 0, 1, "focus %.2f")
  if f_changed then
    state.grid_focus = f_value
    save(app)
  end
  if r.ImGui_IsItemHovered(ctx) then
    r.ImGui_SetTooltip(ctx, "How sharply the weighting falls off around the slider.\n0 = everything counts equally, 1 = only the exact spot.")
  end

  -- Turn the grid into a rack. The 4x4 IS the pad layout, so one press gives a
  -- kit that spans the sound space by construction.
  local can_fill = grid.size == 4 and grid.placed > 0
  r.ImGui_BeginDisabled(ctx, not can_fill)
  if Theme.primary_button(ctx, "Make rack##grid_make", 104, 0) then
    r.ImGui_OpenPopup(ctx, "##grid_make_rack")
  end
  r.ImGui_EndDisabled(ctx)
  if r.ImGui_IsItemHovered(ctx) then
    if grid.size ~= 4 then
      r.ImGui_SetTooltip(ctx, "Needs a 4\195\1974 grid: 16 cells for 16 pads.")
    elseif grid.placed == 0 then
      r.ImGui_SetTooltip(ctx, "Nothing analysed in this selection yet.")
    else
      r.ImGui_SetTooltip(ctx, "Fill 16 pads, one sample per cell.\nPad 1 is the bottom-left cell, pad 16 the top-right,\nso the kit spans the whole grid. Empty cells leave their pad empty.")
    end
  end

  if r.ImGui_BeginPopup(ctx, "##grid_make_rack") then
    if r.ImGui_MenuItem(ctx, "Fill the selected rack") then
      build_kit_from_grid(app, grid, "selected")
    end
    if r.ImGui_IsItemHovered(ctx) then
      r.ImGui_SetTooltip(ctx, "Loads into the rack whose track is selected in REAPER.\nPads that already hold a sample are replaced.")
    end
    if r.ImGui_MenuItem(ctx, "Create a new rack") then
      build_kit_from_grid(app, grid, "new")
    end
    r.ImGui_Separator(ctx)
    if r.ImGui_MenuItem(ctx, "Export as a kit folder\226\128\166") then
      build_kit_from_grid(app, grid, "export")
    end
    if r.ImGui_IsItemHovered(ctx) then
      r.ImGui_SetTooltip(ctx, "Copies and renames the picked samples into a kit folder\non disk, instead of loading them into a rack.")
    end
    r.ImGui_EndPopup(ctx)
  end

  if state.grid_last_target then
    r.ImGui_SameLine(ctx)
    if Theme.ghost_button(ctx, "Re-roll##grid_reroll", 82, 0) then
      build_kit_from_grid(app, grid, state.grid_last_target)
    end
    if r.ImGui_IsItemHovered(ctx) then
      r.ImGui_SetTooltip(ctx, "Same layout, new samples: every pad keeps its corner\nof the sound space and draws a different sample from it.")
    end
  end

  -- Read the other way round: where does an existing kit sit in this pack?
  r.ImGui_SameLine(ctx)
  local showing = state.grid_show_kit == true
  if showing then
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), c.accent)
  end
  if Theme.ghost_button(ctx, "Show kit##grid_show_kit", 84, 0) then
    state.grid_show_kit = not showing
    if state.grid_show_kit then refresh_rack_overlay(app, grid) end
  end
  if showing then r.ImGui_PopStyleColor(ctx) end
  if r.ImGui_IsItemHovered(ctx) then
    r.ImGui_SetTooltip(ctx, "Mark where the selected rack's pads sit in this collection.\nPads huddled in one corner is why a kit sounds flat.\n\nOnly meaningful on the collection the kit draws from:\nthe axes are scaled to what is on screen.\n\nRight-click to re-read the rack.")
  end
  if r.ImGui_IsItemClicked(ctx, 1) and state.grid_show_kit then
    refresh_rack_overlay(app, grid)
  end

  local pushed_note = Theme.push_small(ctx)
  local kit_note = state.grid_show_kit and state.grid_kit_note or nil
  local note = kit_note or state.grid_fill_note
  if note then
    r.ImGui_SameLine(ctx)
    r.ImGui_AlignTextToFramePadding(ctx)
    r.ImGui_TextColored(ctx, (kit_note and state.grid_kit_warn) and c.warning or c.text_dim, note)
  end
  if grid.unanalysed > 0 then
    r.ImGui_TextColored(ctx, c.text_faint,
      string.format("%d placed, %d not analysed yet", grid.placed, grid.unanalysed))
  end
  Theme.pop_font(ctx, pushed_note)
end

local function draw_samples_panel(app)
  local ctx = app.ctx
  local state = app.browser
  local col = selected_collection(app)
  -- `can_group` is whether folders exist to group by at all; `list_flat` is
  -- whether the user wants them, and only the toggle depends on the first.
  local can_group = state.browser_mode == "packs" and col and col.recursive ~= false
  local show_folder_groups = can_group and state.list_flat ~= true

  -- The reserve covers what shares this row: the view toggle, the Tags button
  -- and the match count. It was still set for the row as it looked before those
  -- two buttons existed, which pushed everything past the right edge on a
  -- narrow window.
  local avail_w = r.ImGui_GetContentRegionAvail(ctx)
  local search_w = math.min(320, math.max(96, (as_number(avail_w) or 260) - 290))
  r.ImGui_SetNextItemWidth(ctx, search_w)
  local s_changed, s_value = r.ImGui_InputTextWithHint(ctx, "##browser_search", "Filter by filename...", state.search or "")
  if s_changed then
    state.search = s_value
    save(app)
    apply_filter(app)
  end
  r.ImGui_SameLine(ctx)
  -- Labelled with what it switches TO, and given its own id: "List" is already
  -- taken by the List/Tiles pair in the top bar, which drives the collection
  -- catalogue, not this panel.
  local grid_mode = state.sample_view == "grid"
  if Theme.ghost_button(ctx, (grid_mode and "File list" or "Heatmap") .. "##sample_view_toggle", 76, 0) then
    state.sample_view = grid_mode and "list" or "grid"
    save(app)
  end
  if r.ImGui_IsItemHovered(ctx) then
    r.ImGui_SetTooltip(ctx, grid_mode
      and "Back to the file list."
      or "Show the heatmap: analysed samples spread over two measured axes.")
  end

  r.ImGui_SameLine(ctx)
  draw_tag_filter(app)

  r.ImGui_SameLine(ctx)
  if state.last_scan_label then
    -- Just the figures: this row is crowded, and what they mean fits in a
    -- tooltip better than in a word repeated on every redraw.
    Theme.label(ctx, state.last_scan_label)
    if r.ImGui_IsItemHovered(ctx) then
      r.ImGui_SetTooltip(ctx, "Samples shown / samples in this collection")
    end
  end
  if can_group and not grid_mode then
    -- Measured against where the previous item actually ended, rather than
    -- against a fixed panel width: that threshold was set before the view and
    -- tag buttons joined this row, which is why the wrap came too late.
    local last_x2 = as_number(r.ImGui_GetItemRectMax(ctx)) or 0
    local win_x = as_number(r.ImGui_GetWindowPos(ctx)) or 0
    local win_w = as_number(r.ImGui_GetWindowWidth(ctx)) or 9999
    local right_edge = win_x + win_w - 16

    local flat = state.list_flat == true
    local gap = 6
    local flat_w, exp_w, col_w = 76, 86, 92
    local needed = 9 + flat_w + (flat and 0 or (gap + exp_w + gap + col_w))
    local compact = (last_x2 + needed) > right_edge

    -- On their own row the buttons share its full width. The widths have to be
    -- worked out BEFORE the first one is drawn: once it is, the cursor has
    -- already moved to the next line and the remaining width reads as the whole
    -- panel, which is what pushed Collapse off the edge.
    if compact then
      r.ImGui_Dummy(ctx, 0, 0)
      local row_w = as_number(r.ImGui_GetContentRegionAvail(ctx)) or 240
      local n = flat and 1 or 3
      local w = math.max(52, math.floor((row_w - gap * (n - 1)) / n))
      flat_w, exp_w, col_w = w, w, w
    else
      r.ImGui_SameLine(ctx)
    end

    local flat_label = flat and "Folders" or (compact and "Flat" or "Flat list")
    if Theme.ghost_button(ctx, flat_label .. "##list_flat", flat_w, 0) then
      state.list_flat = not flat
      save(app)
    end
    if r.ImGui_IsItemHovered(ctx) then
      r.ImGui_SetTooltip(ctx, flat
        and "Group the samples by folder again."
        or "Show every sample in one list, ignoring folders.")
    end

    -- Expand/Collapse only mean something while there are folders to fold.
    if not flat then
      r.ImGui_SameLine(ctx, 0, gap)
      if Theme.ghost_button(ctx, (compact and "Expand" or "Expand all") .. "##fold_expand", exp_w, 0) then
        state.folder_header_action = "expand"
      end
      r.ImGui_SameLine(ctx, 0, gap)
      if Theme.ghost_button(ctx, (compact and "Collapse" or "Collapse all") .. "##fold_collapse", col_w, 0) then
        state.folder_header_action = "collapse"
      end
    end
  end

  draw_analysis_bar(app)

  if state.preview_error and state.preview_error ~= "" then
    r.ImGui_TextColored(ctx, 0xFFB454FF, state.preview_error)
  elseif state.export_note then
    r.ImGui_TextColored(ctx, Theme.colors.success, state.export_note)
  end

  local _, avail_h = r.ImGui_GetContentRegionAvail(ctx)
  avail_h = as_number(avail_h) or 300
  local transport_h = 88
  local min_list_h = 80

  -- The transport keeps its place: rather than pushing it off the bottom, the
  -- tags panel steps aside when the window is too short to hold both.
  local tags_h = 0
  if state.show_tags ~= false then
    local needed = min_list_h + ANALYSIS_PANEL_H + transport_h + CHILD_SPACING * 2
    if avail_h >= needed then tags_h = ANALYSIS_PANEL_H end
  end

  local gaps = (tags_h > 0 and 2 or 1) * CHILD_SPACING
  local list_h = math.max(min_list_h, avail_h - transport_h - tags_h - gaps)
  local transport_flags = 0
  if r.ImGui_WindowFlags_NoScrollbar then
    transport_flags = transport_flags | r.ImGui_WindowFlags_NoScrollbar()
  end
  if r.ImGui_WindowFlags_NoScrollWithMouse then
    transport_flags = transport_flags | r.ImGui_WindowFlags_NoScrollWithMouse()
  end
  -- The grid panel stays scrollable: on a very short window the cells hit their
  -- minimum size and the footer would otherwise be clipped out of reach.
  if r.ImGui_BeginChild(ctx, "##browser_samples", 0, list_h, 1, 0) then
    if grid_mode then
      draw_heatmap(app)
    else
      draw_samples_list(app)
    end
    r.ImGui_EndChild(ctx)
  end

  if tags_h > 0 then
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), 12, TAG_PADDING)
    local tags_visible = r.ImGui_BeginChild(ctx, "##browser_tags", 0, tags_h, 0, transport_flags)
    r.ImGui_PopStyleVar(ctx)
    if tags_visible then
      draw_tag_panel(app)
      r.ImGui_EndChild(ctx)
    end
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

  -- Short label, with what the two actually mean moved into the tooltip.
  local kits_mode = state.browser_mode == "kits"
  -- Ghost, not primary: these three now read their own state out of their
  -- label, so a filled accent button would only claim the visual weight that
  -- belongs to the actions -- and it is the same kind of control as the
  -- Heatmap and Flat list toggles further down.
  if place(kits_mode and "KITS" or "PACKS", false, 74) then
    switch_browser_mode(app, kits_mode and "packs" or "kits")
  end
  if r.ImGui_IsItemHovered(ctx) then
    r.ImGui_SetTooltip(ctx, kits_mode
      and "Sample kits: finished kits, ready to build an RS5K rack from.\nClick for sample packs."
      or "Sample packs: raw folders of samples to browse and pull from.\nClick for sample kits.")
  end

  -- The start folder lives on this button's right-click menu: it is set once
  -- and then forgotten, so it does not deserve permanent space in a row that
  -- has to survive a narrow window.
  local base_folder = Dialogs.get_base_folder()
  if place("+ Folder", false) then
    add_collection(app)
  end
  if r.ImGui_IsItemClicked(ctx, 1) then
    r.ImGui_OpenPopup(ctx, "##add_folder_menu")
  end
  if r.ImGui_IsItemHovered(ctx) then
    r.ImGui_SetTooltip(ctx, "Add a folder as a collection."
      .. "\nRight click: start folder for browse dialogs"
      .. (base_folder ~= "" and ("\nCurrently: " .. base_folder) or ""))
  end

  if r.ImGui_BeginPopup(ctx, "##add_folder_menu") then
    local pushed = Theme.push_small(ctx)
    Theme.label(ctx, base_folder ~= ""
      and ("Start folder: " .. base_folder)
      or "No start folder set")
    Theme.help(ctx, base_folder ~= ""
      and "Every browse dialog opens here, whatever you browsed last."
      or "Set one and every browse dialog opens there; without one they reopen on the folder you used last.")
    Theme.pop_font(ctx, pushed)
    r.ImGui_Separator(ctx)

    if r.ImGui_MenuItem(ctx, "Set start folder\226\128\166##set_base") then
      local pick = Dialogs.browse_folder("Select the default start folder for browse dialogs", base_folder, false)
      if pick then Dialogs.set_base_folder(pick) end
    end
    r.ImGui_BeginDisabled(ctx, base_folder == "")
    if r.ImGui_MenuItem(ctx, "Clear start folder##clear_base") then
      Dialogs.set_base_folder("")
    end
    r.ImGui_EndDisabled(ctx)
    r.ImGui_EndPopup(ctx)
  end
  if place("Rescan", false) then
    refresh_collection(app, true)
  end
  -- Two mutually exclusive states, so one button that shows where you are and
  -- steps to the other -- the pair took twice the width to say the same thing.
  local tiles = state.collection_view == "tiles"
  if place(tiles and "Tiles" or "List", false, 72) then
    state.collection_view = tiles and "list" or "tiles"
    save(app)
  end
  if r.ImGui_IsItemClicked(ctx, 1) then
    r.ImGui_OpenPopup(ctx, "##tile_size_menu")
  end
  if r.ImGui_IsItemHovered(ctx) then
    r.ImGui_SetTooltip(ctx, tiles
      and ("Collections as cover tiles. Click for the list.\nTile size: "
        .. tostring(state.tile_size or "normal") .. "\nRight click: change tile size")
      or "Collections as a list. Click for cover tiles.\nRight click: tile size")
  end
  if r.ImGui_BeginPopup(ctx, "##tile_size_menu") then
    Theme.label(ctx, "Tile size")
    r.ImGui_Separator(ctx)
    for _, size in ipairs(TILE_ORDER) do
      local label = size:sub(1, 1):upper() .. size:sub(2)
      if r.ImGui_MenuItem(ctx, label, nil, state.tile_size == size) then
        state.tile_size = size
        state.collection_view = "tiles"
        save(app)
      end
    end
    r.ImGui_EndPopup(ctx)
  end

  -- Three states, so one button that cycles. Right-click steps back, which
  -- matters at three: without it, overshooting means going all the way round.
  local FOCUS_ORDER = { "catalog", "split", "samples" }
  local FOCUS_LABEL = { catalog = "Catalog", split = "Split", samples = "Samples" }
  local focus = state.small_focus or "split"
  local focus_index = 2
  for i, id in ipairs(FOCUS_ORDER) do
    if id == focus then focus_index = i end
  end

  local function step_focus(delta)
    local next_index = ((focus_index - 1 + delta) % #FOCUS_ORDER) + 1
    state.small_focus = FOCUS_ORDER[next_index]
    save(app)
  end

  if place(FOCUS_LABEL[focus] or "Split", false, 86) then
    step_focus(1)
  end
  if r.ImGui_IsItemClicked(ctx, 1) then
    step_focus(-1)
  end
  if r.ImGui_IsItemHovered(ctx) then
    r.ImGui_SetTooltip(ctx, "Which panel gets the room on a narrow window."
      .. "\nCatalog \226\134\146 Split \226\134\146 Samples"
      .. "\nRight click: step back")
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
  -- Analysis results only reach disk every few hundred files, so a job that is
  -- still running when the window closes would lose everything since the last
  -- write. This runs on tab switches too, which is exactly when we want it: the
  -- job itself only advances while the Browser is on screen. Flushing a clean
  -- cache is free.
  Tags.flush()
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
    tile_size = loaded.tile_size or "normal",
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
    show_tags = loaded.show_tags ~= false,
    analysis_job = nil,
    analysis_count = 0,
    analysis_rate_ms = nil,
    analysis_note = nil,
    tag_checked_path = nil,
    -- Deliberately not persisted: a tag filter you forgot about would greet you
    -- next session with most of your pack missing and no obvious reason why.
    tag_filter = Tags.new_filter(),
    tag_facets = nil,
    tag_unmeasured = 0,
    sample_view = loaded.sample_view or "list",
    list_flat = loaded.list_flat == true,
    grid_x = loaded.grid_x or "tone",
    grid_y = loaded.grid_y or "decay",
    grid_size = loaded.grid_size or 4,
    grid_center = loaded.grid_center or 0.5,
    grid_focus = loaded.grid_focus or 0.6,
    grid = nil,
    grid_key = nil,
    grid_shade_key = nil,
    grid_menu_file = nil,
    grid_pick = nil,
    grid_walk = nil,
    grid_last_target = nil,
    grid_fill_note = nil,
    grid_show_kit = false,
    grid_kit_points = nil,
    grid_kit_cells = nil,
    grid_kit_note = nil,
    grid_kit_warn = false,
    grid_kit_key = nil,
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

  step_analysis(app)
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
