-- @description TK_Mixer
-- @author TouristKiller
-- @version 1.0.0
-- @changelog 
--[[
  v1.0.0:
  + Initial standalone release
  + Extracted from TK_TRANSPORT for independent use
  + All mixer functionality preserved: VU meters, Compressor, Limiter, EQ, FX slots, Meters, Sidebar, Parameters
  ]]--

local r = reaper
local ctx = r.ImGui_CreateContext('TK Mixer')

local script_version = "1.0.0"

local mixer_state = {}
local TCP_ICON_EXT_KEY = "TK_TCP_ICON"

local script_path = debug.getinfo(1, "S").source:match("@?(.*[/\\])")
local os_separator = package.config:sub(1, 1)
local transport_path = script_path:gsub("[/\\]Mixer[/\\]$", os_separator .. "Transport" .. os_separator)
package.path = script_path .. "?.lua;" .. transport_path .. "?.lua;"

local json = require("json")
local mixer_settings_path = script_path .. "tk_mixer_settings" .. os_separator
local preset_path = script_path .. "tk_mixer_presets" .. os_separator

local EXT_STATE_KEY = "TK_MIXER"

local simple_mixer_editing_track_guid = nil
local simple_mixer_editing_track_name = ""
local simple_mixer_collapsed_folders = {}
local simple_mixer_hidden_dividers = {}
local simple_mixer_fx_handle_clicked = false
local simple_mixer_track_fx_heights = {}
local simple_mixer_fx_sync_resize = false
local simple_mixer_fx_section_hovered = false
local simple_mixer_editing_divider_guid = nil
local simple_mixer_editing_divider_name = ""
local simple_mixer_divider_names = {}
local simple_mixer_track_icon_cache = {}
local simple_mixer_track_icon_paths = {}
local simple_mixer_pinned_params = {}
local simple_mixer_last_touched_param = nil
local simple_mixer_param_learn_active = false
local simple_mixer_param_learn_last_check = nil
local simple_mixer_params_selected_track = nil
local simple_mixer_last_clicked_track_idx = nil
local simple_mixer_meter_data = {}
local simple_mixer_vu_data = {}
local simple_mixer_ltp_open = true
local simple_mixer_fx_open_state = {}

mixer_state.divider_names = simple_mixer_divider_names
mixer_state.track_icon_cache = simple_mixer_track_icon_cache
mixer_state.track_icon_paths = simple_mixer_track_icon_paths
mixer_state.pinned_params = simple_mixer_pinned_params
mixer_state.collapsed_folders = simple_mixer_collapsed_folders
mixer_state.hidden_dividers = simple_mixer_hidden_dividers
mixer_state.linked_channels = {}
mixer_state.ab_state = {}
mixer_state.ab_current = {}
mixer_state.meter_data = simple_mixer_meter_data
mixer_state.vu_data = simple_mixer_vu_data
mixer_state.track_fx_heights = simple_mixer_track_fx_heights
mixer_state.hidden_track_guids = {}
mixer_state.fx_open_state = simple_mixer_fx_open_state
mixer_state.editing_track_guid = nil
mixer_state.editing_track_name = ""
mixer_state.editing_divider_guid = nil
mixer_state.editing_divider_name = ""
mixer_state.fx_section_hovered = false
mixer_state.fx_handle_clicked = false
mixer_state.fx_sync_resize = false
mixer_state.fader_reset_track = nil
mixer_state.icon_target_track = nil
mixer_state.last_clicked_track_idx = nil
mixer_state.settings_tab = 0
mixer_state.select_settings_tab = nil
mixer_state.params_selected_track = nil
mixer_state.param_learn_active = false
mixer_state.param_learn_last_check = nil
mixer_state.ltp_open = true
mixer_state.last_touched_param = nil

local vu_jsfx_cache = {}
local vu_gmem_attached = false
local vu_track_slot_counter = 0
local vu_track_slots = {}

local comp_fx_cache = {}

local font_mixer = nil
local font_loaded = false
local font_simple_mixer = nil
local font_simple_mixer_attached_size = nil
local font_simple_mixer_dirty = true
local font_settings_ui = nil

local settings = {
 simple_mixer_font_style = 1,
 simple_mixer_button_font_style = 1,
 simple_mixer_window_open = true,
 simple_mixer_tracks = {},
 simple_mixer_current_preset = "",
 simple_mixer_window_width = 600,
 simple_mixer_window_height = 700,
 simple_mixer_window_x = -1,
 simple_mixer_window_y = -1,
 simple_mixer_slider_height = 200,
 simple_mixer_use_track_color = true,
 simple_mixer_selection_color = 0x4A90D9FF,
 simple_mixer_selection_intensity = 0.67,
 simple_mixer_track_name_use_color = false,
 simple_mixer_track_name_bg_use_color = false,
 simple_mixer_auto_height = true,
 simple_mixer_show_rms = true,
 simple_mixer_show_pan = true,
 simple_mixer_show_width = false,
 simple_mixer_font = 1,
 simple_mixer_font_size = 12,
 simple_mixer_window_bg_color = 0x1E1E1EFF,
 simple_mixer_border_color = 0x444444FF,
 simple_mixer_button_font = 1,
 simple_mixer_button_font_size = 14,
 simple_mixer_button_width = 60,
 simple_mixer_button_height = 25,
 simple_mixer_button_use_icon = false,
 simple_mixer_button_color_closed = 0x808080FF,
 simple_mixer_button_color_open = 0x00AA00FF,
 simple_mixer_button_hover_color = 0xAAAAAAFF,
 simple_mixer_button_rounding = 0,
 simple_mixer_button_border_size = 0,
 simple_mixer_button_border_color = 0xFFFFFFFF,
 simple_mixer_button_text_color = 0xFFFFFFFF,
 simple_mixer_channel_text_color = 0xFFFFFFFF,
 simple_mixer_control_bg_color = 0x333333FF,
 simple_mixer_slider_handle_color = 0x888888FF,
 simple_mixer_rms_button_off_color = 0x404040FF,
 simple_mixer_rms_text_color = 0xFFFFFFFF,
 simple_mixer_fader_bg_color = 0x404040FF,
 simple_mixer_master_fader_color = 0x4A90D9FF,
 simple_mixer_icon_color = 0xAAAAAAFF,
 simple_mixer_show_fx_slots = false,
 simple_mixer_fx_slot_count = 4,
 simple_mixer_fx_slot_height = 16,
 simple_mixer_fx_section_height = 80,
 simple_mixer_fx_slot_color = 0x404040FF,
 simple_mixer_fx_slot_active_color = 0x444444FF,
 simple_mixer_fx_slot_bypass_color = 0x666600FF,
 simple_mixer_fx_slot_offline_color = 0x553333FF,
 simple_mixer_fx_slot_show_offline = true,
 simple_mixer_fx_slot_text_color = 0x888888FF,
 simple_mixer_fx_dropzone_color = 0x2A2A2AFF,
 simple_mixer_fx_dropzone_border_color = 0x555555FF,
 simple_mixer_fx_show_bypass_button = true,
 simple_mixer_fx_section_collapsed = false,
 simple_mixer_fx_font_size = 12,
 simple_mixer_show_master = false,
 simple_mixer_master_position = "left",
 simple_mixer_show_track_buttons = true,
 simple_mixer_spacer_style = "line",
 simple_mixer_divider_show_border = true,
 simple_mixer_divider_filled = false,
 simple_mixer_divider_use_track_color = true,
 simple_mixer_divider_custom_color = 0x444444FF,
 simple_mixer_divider_border_custom_color = 0x888888FF,
 simple_mixer_divider_text_use_track_color = true,
 simple_mixer_divider_text_custom_color = 0xFFFFFFFF,
 simple_mixer_divider_width = 20,
 simple_mixer_track_buttons_height = 16,
 simple_mixer_channel_rounding = 0,
 simple_mixer_show_folder_groups = false,
 simple_mixer_show_pinned_first = false,
 simple_mixer_show_track_icons = true,
 simple_mixer_track_icon_opacity = 0.3,
 simple_mixer_track_icon_size = 1.0,
 simple_mixer_track_icon_vertical_pos = 0.5,
 simple_mixer_folder_border_thickness = 2,
 simple_mixer_folder_use_track_color = true,
 simple_mixer_folder_border_color = 0x00AAFFFF,
 simple_mixer_folder_border_rounding = 4,
 simple_mixer_folder_padding = 2,
 simple_mixer_show_meters = true,
 simple_mixer_meter_width = 12,
 simple_mixer_meter_show_ticks = true,
 simple_mixer_meter_tick_size = 8,
 simple_mixer_meter_tick_color_below = 0x888888FF,
 simple_mixer_meter_tick_color_above = 0x000000FF,
 simple_mixer_meter_segment_gap = 1,
 simple_mixer_meter_decay_speed = 0.92,
 simple_mixer_meter_hold_time = 1.5,
 simple_mixer_meter_color_normal = 0x00CC00FF,
 simple_mixer_meter_color_mid = 0xCCFF00FF,
 simple_mixer_meter_color_high = 0xFFFF00FF,
 simple_mixer_meter_color_clip = 0xFF0000FF,
 simple_mixer_meter_bg_color = 0x1A1A1AFF,
 simple_mixer_show_vu_meter = false,
 simple_mixer_vu_pre_fader = false,
 simple_mixer_vu_height = 50,
 simple_mixer_vu_bg_color = 0x2A2015FF,
 simple_mixer_vu_color_normal = 0xC9A855FF,
 simple_mixer_vu_color_mid = 0xC9A855FF,
 simple_mixer_vu_color_high = 0xC9A855FF,
 simple_mixer_vu_color_clip = 0xCC5544FF,
 simple_mixer_vu_border_color = 0xB89840FF,
 simple_mixer_vu_show_db = true,
 simple_mixer_vu_integration_time = 300,
 simple_mixer_vu_needle_color = 0xDDDDDDFF,
 simple_mixer_show_compressor = false,
 simple_mixer_comp_height = 140,
 simple_mixer_comp_bg_color = 0x2A2A3AFF,
 simple_mixer_comp_section_color = 0x3A3A4AFF,
 simple_mixer_comp_header_color = 0x4A4A6AFF,
 simple_mixer_comp_knob_color = 0xCCCCCCFF,
 simple_mixer_comp_knob_track_color = 0x555555FF,
 simple_mixer_comp_gr_color = 0xFF6644FF,
 simple_mixer_comp_gr_bg_color = 0x333333FF,
 simple_mixer_comp_text_color = 0xAAAAAAFF,
 simple_mixer_comp_bypass_color = 0x666600FF,
 simple_mixer_comp_active_color = 0x00AA44FF,
 simple_mixer_comp_show_gr_meter = true,
 simple_mixer_comp_show_labels = true,
 simple_mixer_comp_auto_insert = true,
 simple_mixer_show_limiter = false,
 simple_mixer_lim_height = 90,
 simple_mixer_lim_bg_color = 0x2A1A2AFF,
 simple_mixer_lim_header_color = 0x5A3A5AFF,
 simple_mixer_lim_knob_color = 0xCCCCCCFF,
 simple_mixer_lim_knob_track_color = 0x555555FF,
 simple_mixer_lim_gr_color = 0xFF4466FF,
 simple_mixer_lim_gr_bg_color = 0x333333FF,
 simple_mixer_lim_text_color = 0xAAAAAAFF,
 simple_mixer_lim_bypass_color = 0x666600FF,
 simple_mixer_lim_active_color = 0x00AA44FF,
 simple_mixer_lim_show_gr_meter = true,
 simple_mixer_lim_show_labels = true,
 simple_mixer_lim_auto_insert = true,
 simple_mixer_show_eq = false,
 simple_mixer_eq_bg_color = 0x1A2A2AFF,
 simple_mixer_eq_header_color = 0x3A5A5AFF,
 simple_mixer_eq_knob_color = 0xCCCCCCFF,
 simple_mixer_eq_knob_track_color = 0x555555FF,
 simple_mixer_eq_text_color = 0xAAAAAAFF,
 simple_mixer_eq_bypass_color = 0x666600FF,
 simple_mixer_eq_active_color = 0x00AA88FF,
 simple_mixer_eq_show_labels = true,
 simple_mixer_eq_lf_bg = 0xFF666618,
 simple_mixer_eq_lmf_bg = 0xFFAA4418,
 simple_mixer_eq_hmf_bg = 0x66FF6618,
 simple_mixer_eq_hf_bg = 0x6666FF18,
 simple_mixer_sidebar_collapsed = true,
 simple_mixer_sidebar_mode = "settings",
 simple_mixer_sidebar_text = "",
 simple_mixer_sidebar_text_size = 14,
 simple_mixer_sidebar_text_color = 0xAAAAAAFF,
 simple_mixer_presets_open = true,
 simple_mixer_snapshots_open = true,
 simple_mixer_current_snapshot = "",
 simple_mixer_new_snapshot_name = "",
 simple_mixer_snapshot_include_faders = true,
 simple_mixer_show_open = true,
 simple_mixer_input_open = true,
 simple_mixer_output_open = true,
 simple_mixer_inputfx_open = true,
 simple_mixer_recmode_open = true,
 simple_mixer_hide_all_dividers = false,
 simple_mixer_font_name = "Arial",
 simple_mixer_button_font_name = "Arial",
 simple_mixer_remember_state = true,
 simple_mixer_channel_width = 70,
 simple_mixer_track_name_centered = false,
 simple_mixer_rms_position = "top",
 simple_mixer_auto_all = false,
 simple_mixer_button_text_hover_color = nil,
 simple_mixer_button_text_active_color = nil,
 simple_mixer_fader_bg_style = 0,
 simple_mixer_fader_bg_gradient_top = 0x606060FF,
 simple_mixer_fader_bg_gradient_bottom = 0x202020FF,
 simple_mixer_fader_bg_gradient_middle = 0x404040FF,
 simple_mixer_fader_bg_use_three_color = false,
 simple_mixer_fader_bg_inset = false,
 simple_mixer_fader_bg_glow = false,
 simple_mixer_fader_bg_glow_color = 0x00FFFF40,
 simple_mixer_fader_style = 0,
 simple_mixer_fader_cyberpunk_color = 0x00FFFFFF,
 simple_mixer_show_gain_staging = true,
 simple_mixer_hide_tcp_icons = false,
 simple_mixer_track_icon_position = "overlay",
 simple_mixer_track_icon_section_height = 40,
 simple_mixer_track_icon_section_bg = true,
 simple_mixer_show_trim = false,
 simple_mixer_trim_bg_color = 0x2A2A1AFF,
 simple_mixer_trim_header_color = 0x5A5A3AFF,
 simple_mixer_trim_knob_color = 0xCCCCCCFF,
 simple_mixer_trim_text_color = 0xAAAAAAFF,
 simple_mixer_trim_active_color = 0x88AA00FF,
 simple_mixer_trim_auto_insert = true,
 simple_mixer_strip_routing_order = 0,
 simple_mixer_auto_remove_unused_fx = false,
 simple_mixer_knob_style = 0,
 simple_mixer_vu_style = 0,
}

local function EnsureFolder(path)
 local sep = os_separator
 local parts = {}
 for part in path:gmatch("[^/\\]+") do
  table.insert(parts, part)
 end
 local current = ""
 for i, part in ipairs(parts) do
  if i == 1 and part:match(":$") then
   current = part .. sep
  else
   current = current .. part .. sep
  end
  r.RecursiveCreateDirectory(current:sub(1, -2), 0)
 end
end

local function EnsureMixerSettingsFolder()
 EnsureFolder(mixer_settings_path)
end

local function GetMixerSettingsFilename()
 local project_path = r.GetProjectPath("")
 local project_name = r.GetProjectName(0, "")
 return mixer_settings_path .. project_name:gsub("%.rpp$", "") .. "_mixer.json"
end

local mixer_settings_dirty = false

local function WriteMixerSettingsToDisk()
 EnsureMixerSettingsFolder()
 local filename = GetMixerSettingsFilename()
 local file = io.open(filename, "w")
 if file then
  local data = {}
  for k, v in pairs(settings) do
   if k:find("^simple_mixer_") then
    data[k] = v
   end
  end
  file:write(json.encode(data))
  file:close()
  mixer_settings_dirty = false
 end
end

local function SaveMixerSettings()
 mixer_settings_dirty = true
end

local function LoadMixerSettings()
 EnsureMixerSettingsFolder()
 local filename = GetMixerSettingsFilename()
 local file = io.open(filename, "r")
 if file then
  local content = file:read("*all")
  file:close()
  if content and content ~= "" then
   local ok, data = pcall(json.decode, content)
   if ok and data then
    for k, v in pairs(data) do
     if k:find("^simple_mixer_") then
      settings[k] = v
     end
    end
   end
  end
 end
end

local _cached_project_tracks = nil
local _cached_project_tracks_key = nil
local _cached_hidden_tracks = nil
local _cached_hidden_tracks_key = nil

local SaveProjectMixerTracks

local function GetProjectMixerTracks()
 local project_file = r.GetProjectPath("")
 if project_file == "" then return {} end
 if _cached_project_tracks_key == project_file and _cached_project_tracks then
  return _cached_project_tracks
 end
 local key = "simple_mixer_tracks_" .. project_file
 local tracks_json = r.GetExtState(EXT_STATE_KEY, key)
 if tracks_json ~= "" then
  local success, tracks = pcall(function() return json.decode(tracks_json) end)
  if success and tracks then
   local validated_tracks = {}
   local needs_repair = false
   for _, track_data in ipairs(tracks) do
    if type(track_data) == "string" then
     table.insert(validated_tracks, track_data)
    elseif type(track_data) == "table" then
     needs_repair = true
     if track_data.guid and type(track_data.guid) == "string" then
      table.insert(validated_tracks, track_data.guid)
     elseif track_data[1] and type(track_data[1]) == "string" then
      table.insert(validated_tracks, track_data[1])
     end
    end
   end
   if needs_repair then
    SaveProjectMixerTracks(validated_tracks)
   end
   _cached_project_tracks = validated_tracks
   _cached_project_tracks_key = project_file
   return validated_tracks
  end
 end
 _cached_project_tracks = {}
 _cached_project_tracks_key = project_file
 return _cached_project_tracks
end

SaveProjectMixerTracks = function(tracks)
 local project_file = r.GetProjectPath("")
 if project_file == "" then return end
 local key = "simple_mixer_tracks_" .. project_file
 local tracks_json = json.encode(tracks)
 r.SetExtState(EXT_STATE_KEY, key, tracks_json, true)
 _cached_project_tracks = tracks
 _cached_project_tracks_key = project_file
end

local function GetProjectMixerPresets()
 local project_file = r.GetProjectPath("")
 if project_file == "" then return {} end
 local key = "simple_mixer_presets_" .. project_file
 local presets_json = r.GetExtState(EXT_STATE_KEY, key)
 if presets_json and presets_json ~= "" then
  local success, presets = pcall(json.decode, presets_json)
  if success and presets then
   return presets
  end
 end
 return {}
end

local function SaveProjectMixerPresets(presets)
 local project_file = r.GetProjectPath("")
 if project_file == "" then return end
 local key = "simple_mixer_presets_" .. project_file
 local presets_json = json.encode(presets)
 r.SetExtState(EXT_STATE_KEY, key, presets_json, true)
end

local function EnsurePresetDir()
 local presets_dir = r.GetResourcePath() .. "/Scripts/TK Scripts/Mixer/tk_mixer_presets"
 r.RecursiveCreateDirectory(presets_dir, 0)
 return presets_dir
end

local SETTINGS_PRESET_BLACKLIST = {
 simple_mixer_window_open = true,
 simple_mixer_settings_popup_open = true,
 simple_mixer_current_preset = true,
 simple_mixer_preset_name_input = true,
 simple_mixer_new_preset_name = true,
 simple_mixer_current_snapshot = true,
 simple_mixer_new_snapshot_name = true,
 simple_mixer_snapshot_include_faders = true,
}

local GetProjectMixerHiddenTracks
local SaveProjectMixerHiddenTracks

local function SaveMixerPreset(name)
 local presets_dir = EnsurePresetDir()
 local preset_path = presets_dir .. "/" .. name .. ".json"
 local saved_settings = {}
 for k, v in pairs(settings) do
  if type(k) == "string" and k:find("^simple_mixer_") and not SETTINGS_PRESET_BLACKLIST[k] then
   local t = type(v)
   if t == "string" or t == "number" or t == "boolean" then
    saved_settings[k] = v
   end
  end
 end
 local preset_data = {
  version = 2,
  settings = saved_settings,
 }
 local file = io.open(preset_path, "w")
 if file then
  file:write(json.encode(preset_data))
  file:close()
 end
end

local function LoadMixerPreset(name)
 local presets_dir = EnsurePresetDir()
 local preset_path = presets_dir .. "/" .. name .. ".json"
 local file = io.open(preset_path, "r")
 if file then
  local content = file:read("*all")
  file:close()
  local ok, preset_data = pcall(json.decode, content)
  if ok and preset_data then
   if preset_data.settings then
    for k, v in pairs(preset_data.settings) do
     settings[k] = v
    end
    SaveMixerSettings()
   end
   settings.simple_mixer_current_preset = name
  end
 end
end

local function GetProjectSnapshots()
 local project_file = r.GetProjectPath("")
 if project_file == "" then return {} end
 local key = "simple_mixer_snapshots_" .. project_file
 local js = r.GetExtState(EXT_STATE_KEY, key)
 if js and js ~= "" then
  local ok, data = pcall(json.decode, js)
  if ok and type(data) == "table" then return data end
 end
 return {}
end

local function SaveProjectSnapshots(snapshots)
 local project_file = r.GetProjectPath("")
 if project_file == "" then return end
 local key = "simple_mixer_snapshots_" .. project_file
 r.SetExtState(EXT_STATE_KEY, key, json.encode(snapshots or {}), true)
end

local function SaveProjectSnapshot(name, include_faders)
 if not name or name == "" then return end
 local snapshots = GetProjectSnapshots()
 local tracks = GetProjectMixerTracks()
 local hidden = GetProjectMixerHiddenTracks()
 local hidden_list = {}
 for guid, is_hidden in pairs(hidden or {}) do
  if is_hidden then table.insert(hidden_list, guid) end
 end
 local entry = {
  tracks = tracks,
  hidden = hidden_list,
 }
 if include_faders then
  local faders = {}
  for _, guid in ipairs(tracks) do
   local track = r.BR_GetMediaTrackByGUID(0, guid)
   if track then
    faders[guid] = {
     vol = r.GetMediaTrackInfo_Value(track, "D_VOL"),
     pan = r.GetMediaTrackInfo_Value(track, "D_PAN"),
     mute = r.GetMediaTrackInfo_Value(track, "B_MUTE"),
     solo = r.GetMediaTrackInfo_Value(track, "I_SOLO"),
    }
   end
  end
  entry.faders = faders
 end
 snapshots[name] = entry
 SaveProjectSnapshots(snapshots)
end

local function LoadProjectSnapshot(name)
 if not name or name == "" then return end
 local snapshots = GetProjectSnapshots()
 local entry = snapshots[name]
 if not entry then return end
 if entry.tracks then
  SaveProjectMixerTracks(entry.tracks)
 end
 if entry.hidden then
  local hidden = {}
  for _, guid in ipairs(entry.hidden) do hidden[guid] = true end
  SaveProjectMixerHiddenTracks(hidden)
 end
 if entry.faders then
  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)
  for guid, vals in pairs(entry.faders) do
   local track = r.BR_GetMediaTrackByGUID(0, guid)
   if track then
    if vals.vol  then r.SetMediaTrackInfo_Value(track, "D_VOL",  vals.vol)  end
    if vals.pan  then r.SetMediaTrackInfo_Value(track, "D_PAN",  vals.pan)  end
    if vals.mute then r.SetMediaTrackInfo_Value(track, "B_MUTE", vals.mute) end
    if vals.solo then r.SetMediaTrackInfo_Value(track, "I_SOLO", vals.solo) end
   end
  end
  r.PreventUIRefresh(-1)
  r.Undo_EndBlock("Load Mixer Snapshot: " .. name, -1)
 end
 settings.simple_mixer_current_snapshot = name
end

local function DeleteProjectSnapshot(name)
 if not name or name == "" then return end
 local snapshots = GetProjectSnapshots()
 snapshots[name] = nil
 SaveProjectSnapshots(snapshots)
end

local function SavePinnedParams()
 local data = {}
 for track_guid, params in pairs(simple_mixer_pinned_params) do
  data[track_guid] = {}
  for key, pp in pairs(params) do
   data[track_guid][key] = {
    fxidx = pp.fxidx,
    paramidx = pp.paramidx,
    fx_name = pp.fx_name,
    param_name = pp.param_name
   }
  end
 end
 local json_str = json.encode(data)
 r.SetExtState(EXT_STATE_KEY, "pinned_params", json_str, true)
end

local function LoadPinnedParams()
 local json_str = r.GetExtState(EXT_STATE_KEY, "pinned_params")
 if json_str == "" then return end
 local ok, data = pcall(json.decode, json_str)
 if not ok or not data then return end
 simple_mixer_pinned_params = {}
 for track_guid, params in pairs(data) do
  local track = r.BR_GetMediaTrackByGUID(0, track_guid)
  if track then
   simple_mixer_pinned_params[track_guid] = {}
   local _, track_name = r.GetTrackName(track)
   local is_master = (track == r.GetMasterTrack(0))
   local track_num = is_master and "M" or tostring(r.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER"))
   for key, pp in pairs(params) do
    simple_mixer_pinned_params[track_guid][key] = {
     track = track,
     track_num = track_num,
     track_name = track_name,
     fxidx = pp.fxidx,
     paramidx = pp.paramidx,
     fx_name = pp.fx_name,
     param_name = pp.param_name
    }
   end
  end
 end
end

local function SyncEmbeddedParams(target_track)
 if not target_track or not r.ValidatePtr(target_track, "MediaTrack*") then return 0 end
 local track_guid = r.GetTrackGUID(target_track)
 if not simple_mixer_pinned_params[track_guid] then
  simple_mixer_pinned_params[track_guid] = {}
 end
 local added_count = 0
 local removed_count = 0
 local _, track_name = r.GetTrackName(target_track)
 local is_master = (target_track == r.GetMasterTrack(0))
 local track_num = is_master and "M" or tostring(r.GetMediaTrackInfo_Value(target_track, "IP_TRACKNUMBER"))
 local tcp_params = {}
 local num_tcp_params = r.CountTCPFXParms(0, target_track)
 for i = 0, num_tcp_params - 1 do
  local retval, fx_idx, param_idx = r.GetTCPFXParm(0, target_track, i)
  if retval then
   local key = fx_idx .. "_" .. param_idx
   tcp_params[key] = true
   local _, fx_name = r.TrackFX_GetFXName(target_track, fx_idx, "")
   local _, param_name = r.TrackFX_GetParamName(target_track, fx_idx, param_idx, "")
   if not simple_mixer_pinned_params[track_guid][key] then
    simple_mixer_pinned_params[track_guid][key] = {
     track = target_track,
     track_num = track_num,
     track_name = track_name,
     fxidx = fx_idx,
     paramidx = param_idx,
     fx_name = fx_name,
     param_name = param_name
    }
    added_count = added_count + 1
   end
  end
 end
 for key, _ in pairs(simple_mixer_pinned_params[track_guid]) do
  if not tcp_params[key] then
   simple_mixer_pinned_params[track_guid][key] = nil
   removed_count = removed_count + 1
  end
 end
 if added_count > 0 or removed_count > 0 then
  SavePinnedParams()
 end
 return added_count
end

local function RemoveParamFromTCP(track, fxidx, paramidx)
 if not track or not r.ValidatePtr(track, "MediaTrack*") then return false end
 local param_val = r.TrackFX_GetParam(track, fxidx, paramidx)
 r.TrackFX_SetParam(track, fxidx, paramidx, param_val)
 r.Main_OnCommand(41141, 0)
 return true
end

local function AddParamToTCP(track, fxidx, paramidx)
 if not track or not r.ValidatePtr(track, "MediaTrack*") then return false end
 local _, chunk = r.GetTrackStateChunk(track, "", false)
 if not chunk then return false end
 local new_param = fxidx .. ":" .. paramidx
 local parm_start, parm_end = chunk:find("PARM_TCP [^\n]+")
 if parm_start then
  local parm_line = chunk:sub(parm_start, parm_end)
  if parm_line:find(new_param, 1, true) then
   return true
  end
  local new_chunk = chunk:sub(1, parm_end) .. " " .. new_param .. chunk:sub(parm_end + 1)
  r.SetTrackStateChunk(track, new_chunk, false)
 else
  local fx_start = chunk:find("<FXCHAIN[^\n]*\n")
  if not fx_start then
   return false
  end
  local fx_line_end = chunk:find("\n", fx_start)
  if not fx_line_end then return false end
  local new_chunk = chunk:sub(1, fx_line_end) .. "PARM_TCP " .. new_param .. "\n" .. chunk:sub(fx_line_end + 1)
  r.SetTrackStateChunk(track, new_chunk, false)
 end
 r.TrackList_AdjustWindows(false)
 r.UpdateArrange()
 return true
end

local function GetProjectMixerHiddenTracks_impl()
 local project_file = r.GetProjectPath("")
 if project_file == "" then return {} end
 if _cached_hidden_tracks_key == project_file and _cached_hidden_tracks then
  return _cached_hidden_tracks
 end
 local key = "simple_mixer_hidden_tracks_" .. project_file
 local hidden_json = r.GetExtState(EXT_STATE_KEY, key)
 local hidden = {}
 if hidden_json and hidden_json ~= "" then
  local success, list = pcall(function() return json.decode(hidden_json) end)
  if success and type(list) == "table" then
   for _, guid in ipairs(list) do
    if type(guid) == "string" then
     hidden[guid] = true
    end
   end
  end
 end
 _cached_hidden_tracks = hidden
 _cached_hidden_tracks_key = project_file
 return hidden
end
GetProjectMixerHiddenTracks = GetProjectMixerHiddenTracks_impl

SaveProjectMixerHiddenTracks = function(hidden)
 local project_file = r.GetProjectPath("")
 if project_file == "" then return end
 local key = "simple_mixer_hidden_tracks_" .. project_file
 local list = {}
 for guid, is_hidden in pairs(hidden or {}) do
  if is_hidden and type(guid) == "string" then
   list[#list + 1] = guid
  end
 end
 table.sort(list)
 r.SetExtState(EXT_STATE_KEY, key, json.encode(list), true)
 _cached_hidden_tracks = hidden
 _cached_hidden_tracks_key = project_file
end

local channelstrip_fx_cache = {}

local STRIP_OFFSET = {
 EQ = 0,
 COMP = 19,
 LIM = 26,
 ROUTING = 33,
 EQ_BYPASS = 34,
 COMP_BYPASS = 35,
 LIM_BYPASS = 36
}

local function FindChannelStripFX(track, track_guid)
 if channelstrip_fx_cache[track_guid] then
  local cached = channelstrip_fx_cache[track_guid]
  local retval, fx_name = r.TrackFX_GetFXName(track, cached.fx_index, "")
  if retval then
   local name_lower = fx_name:lower()
   if name_lower:find("tk channel strip") or name_lower:find("tk_channelstrip") then
    return cached.fx_index
   end
  end
  channelstrip_fx_cache[track_guid] = nil
 end
 local fx_count = r.TrackFX_GetCount(track)
 for i = 0, fx_count - 1 do
  local retval, fx_name = r.TrackFX_GetFXName(track, i, "")
  if retval then
   local name_lower = fx_name:lower()
   if name_lower:find("tk channel strip") or name_lower:find("tk_channelstrip") then
    channelstrip_fx_cache[track_guid] = {fx_index = i}
    return i
   end
  end
 end
 return -1
end

local function InsertChannelStripFX(track, track_guid)
 local fx_index = r.TrackFX_AddByName(track, "JS:TK_ChannelStrip", false, -1)
 if fx_index >= 0 then
  r.TrackFX_SetEnabled(track, fx_index, true)
  channelstrip_fx_cache[track_guid] = {fx_index = fx_index}
  local routing_order = settings.simple_mixer_strip_routing_order or 0
  r.TrackFX_SetParam(track, fx_index, STRIP_OFFSET.ROUTING, routing_order)
  r.TrackFX_SetParam(track, fx_index, STRIP_OFFSET.EQ_BYPASS, 0)
  r.TrackFX_SetParam(track, fx_index, STRIP_OFFSET.COMP_BYPASS, 0)
  r.TrackFX_SetParam(track, fx_index, STRIP_OFFSET.LIM_BYPASS, 0)
 end
 return fx_index
end

local function UpdateAllStripsRoutingOrder()
 local routing_order = settings.simple_mixer_strip_routing_order or 0
 local track_count = r.CountTracks(0)
 for i = 0, track_count - 1 do
  local track = r.GetTrack(0, i)
  if track then
   local fx_count = r.TrackFX_GetCount(track)
   for j = 0, fx_count - 1 do
    local retval, fx_name = r.TrackFX_GetFXName(track, j, "")
    if retval then
     local name_lower = fx_name:lower()
     if name_lower:find("tk channel strip") or name_lower:find("tk_channelstrip") then
      r.TrackFX_SetParam(track, j, STRIP_OFFSET.ROUTING, routing_order)
      break
     end
    end
   end
  end
 end
end

local function RemoveChannelStripFromAllTracks()
 local track_count = r.CountTracks(0)
 local removed = 0
 r.PreventUIRefresh(1)
 r.Undo_BeginBlock()
 for i = -1, track_count - 1 do
  local track = (i == -1) and r.GetMasterTrack(0) or r.GetTrack(0, i)
  if track then
   local fx_count = r.TrackFX_GetCount(track)
   for j = fx_count - 1, 0, -1 do
    local retval, fx_name = r.TrackFX_GetFXName(track, j, "")
    if retval then
     local name_lower = fx_name:lower()
     if name_lower:find("tk channel strip") or name_lower:find("tk_channelstrip") then
      r.TrackFX_Delete(track, j)
      removed = removed + 1
     end
    end
   end
  end
 end
 channelstrip_fx_cache = {}
 r.Undo_EndBlock("Remove TK Channel Strip from all tracks", -1)
 r.PreventUIRefresh(-1)
 return removed
end

local function RemoveTrimFromAllTracks()
 local track_count = r.CountTracks(0)
 local removed = 0
 r.PreventUIRefresh(1)
 r.Undo_BeginBlock()
 for i = -1, track_count - 1 do
  local track = (i == -1) and r.GetMasterTrack(0) or r.GetTrack(0, i)
  if track then
   local fx_count = r.TrackFX_GetCount(track)
   for j = fx_count - 1, 0, -1 do
    local retval, fx_name = r.TrackFX_GetFXName(track, j, "")
    if retval then
     local name_lower = fx_name:lower()
     if name_lower:find("tk_trim") or name_lower:find("tk trim") then
      r.TrackFX_Delete(track, j)
      removed = removed + 1
     end
    end
   end
  end
 end
 r.Undo_EndBlock("Remove TK Trim from all tracks", -1)
 r.PreventUIRefresh(-1)
 return removed
end

local function CleanupUnusedChannelFX()
 local total = 0
 local strip_used = settings.simple_mixer_show_eq or settings.simple_mixer_show_compressor or settings.simple_mixer_show_limiter
 if not strip_used then
  total = total + RemoveChannelStripFromAllTracks()
 end
 if not settings.simple_mixer_show_trim then
  total = total + RemoveTrimFromAllTracks()
 end
 return total
end

local function FindCompressorFX(track, track_guid)
 return FindChannelStripFX(track, track_guid)
end

local function InsertCompressorFX(track, track_guid)
 return InsertChannelStripFX(track, track_guid)
end

local function ResetCompressor(track, fx_index)
 if fx_index < 0 then return end
 r.TrackFX_SetParam(track, fx_index, STRIP_OFFSET.COMP + 0, 0)
 r.TrackFX_SetParam(track, fx_index, STRIP_OFFSET.COMP + 1, 5)
 r.TrackFX_SetParam(track, fx_index, STRIP_OFFSET.COMP + 2, 0)
 r.TrackFX_SetParam(track, fx_index, STRIP_OFFSET.COMP + 3, 20)
 r.TrackFX_SetParam(track, fx_index, STRIP_OFFSET.COMP + 4, 250)
 r.TrackFX_SetParam(track, fx_index, STRIP_OFFSET.COMP + 5, 100)
end

local function EnsureCompressorFX(track, track_guid)
 local fx_index = FindCompressorFX(track, track_guid)
 if fx_index >= 0 then return fx_index end
 if not settings.simple_mixer_comp_auto_insert then return -1 end
 return InsertCompressorFX(track, track_guid)
end

local function GetCompressorParams(track, fx_index)
 if fx_index < 0 then return nil end
 local plugin_enabled = r.TrackFX_GetEnabled(track, fx_index)
 local thresh = r.TrackFX_GetParam(track, fx_index, STRIP_OFFSET.COMP + 0)
 local ratio = r.TrackFX_GetParam(track, fx_index, STRIP_OFFSET.COMP + 1)
 local makeup = r.TrackFX_GetParam(track, fx_index, STRIP_OFFSET.COMP + 2)
 local attack = r.TrackFX_GetParam(track, fx_index, STRIP_OFFSET.COMP + 3)
 local release = r.TrackFX_GetParam(track, fx_index, STRIP_OFFSET.COMP + 4)
 local mix = r.TrackFX_GetParam(track, fx_index, STRIP_OFFSET.COMP + 5)
 local gr_db = r.TrackFX_GetParam(track, fx_index, STRIP_OFFSET.COMP + 6)
 local params = {
  threshold = (thresh + 60) / 60,
  ratio = ratio / 9,
  gain = (makeup + 20) / 40,
  attack = (attack - 20) / 1980,
  release = (release - 20) / 980,
  mix = mix / 100,
  enabled = plugin_enabled and r.TrackFX_GetParam(track, fx_index, STRIP_OFFSET.COMP_BYPASS) == 1
 }
 local gr = math.min(1, math.abs(gr_db) / 20)
 params.gr = gr
 return params
end

local function SetCompressorParam(track, fx_index, param_idx, value)
 if fx_index < 0 then return end
 r.TrackFX_SetParamNormalized(track, fx_index, STRIP_OFFSET.COMP + param_idx, value)
end

local function DrawStyledKnob(ctx, draw_list, center_x, center_y, radius, norm_val, knob_color, is_bipolar, style, track_color)
 style = style or settings.simple_mixer_knob_style or 0
 track_color = track_color or 0x555555FF
 local start_angle = math.pi * 0.75
 local end_angle = math.pi * 2.25
 local center_angle = math.pi * 1.5
 local angle_range = end_angle - start_angle
 local value_angle = start_angle + norm_val * angle_range
 if style == 0 then
  r.ImGui_DrawList_AddCircleFilled(draw_list, center_x + 1, center_y + 1, radius, 0x00000066, 32)
  r.ImGui_DrawList_AddCircleFilled(draw_list, center_x, center_y, radius, track_color, 32)
  local arc_radius = radius - 2
  if is_bipolar then
   if norm_val > 0.5 then
    r.ImGui_DrawList_PathArcTo(draw_list, center_x, center_y, arc_radius, center_angle, value_angle, 32)
   elseif norm_val < 0.5 then
    r.ImGui_DrawList_PathArcTo(draw_list, center_x, center_y, arc_radius, value_angle, center_angle, 32)
   end
  else
   if norm_val > 0.01 then
    r.ImGui_DrawList_PathArcTo(draw_list, center_x, center_y, arc_radius, start_angle, value_angle, 32)
   end
  end
  r.ImGui_DrawList_PathStroke(draw_list, knob_color, 0, 2.5)
  local is_default = (is_bipolar and math.abs(norm_val - 0.5) < 0.02) or (not is_bipolar and norm_val < 0.02)
  if is_default then
   local px = center_x + math.cos(value_angle) * radius * 0.85
   local py = center_y + math.sin(value_angle) * radius * 0.85
   r.ImGui_DrawList_AddLine(draw_list, center_x, center_y, px, py, knob_color, 2)
  end
  r.ImGui_DrawList_AddCircleFilled(draw_list, center_x, center_y, radius * 0.45, knob_color, 32)
 elseif style == 1 then
  r.ImGui_DrawList_AddCircleFilled(draw_list, center_x, center_y, radius, 0x00000066, 32)
  r.ImGui_DrawList_AddCircleFilled(draw_list, center_x, center_y, radius - 1, 0x3A3A3AFF, 32)
  r.ImGui_DrawList_AddCircleFilled(draw_list, center_x, center_y, radius - 3, 0x2A2A2AFF, 32)
  local pointer_inner = radius * 0.35
  local pointer_outer = radius - 2
  local inner_x = center_x + math.cos(value_angle) * pointer_inner
  local inner_y = center_y + math.sin(value_angle) * pointer_inner
  local outer_x = center_x + math.cos(value_angle) * pointer_outer
  local outer_y = center_y + math.sin(value_angle) * pointer_outer
  r.ImGui_DrawList_AddLine(draw_list, inner_x, inner_y, outer_x, outer_y, knob_color, 2)
  r.ImGui_DrawList_AddCircleFilled(draw_list, center_x, center_y, math.max(2, radius * 0.3), 0x1A1A1AFF, 16)
 elseif style == 2 then
  r.ImGui_DrawList_AddCircleFilled(draw_list, center_x, center_y, radius, 0x1A1510FF, 32)
  local metal_color = 0x6B5335FF
  local metal_highlight = 0x9A8355FF
  r.ImGui_DrawList_AddCircleFilled(draw_list, center_x, center_y, radius - 2, metal_color, 32)
  local tick_count = math.max(5, math.floor(radius / 2))
  for i = 0, tick_count do
   local tick_angle = start_angle + (i / tick_count) * angle_range
   local tick_inner = radius - 1
   local tick_outer = radius + 1
   local tx1 = center_x + math.cos(tick_angle) * tick_inner
   local ty1 = center_y + math.sin(tick_angle) * tick_inner
   local tx2 = center_x + math.cos(tick_angle) * tick_outer
   local ty2 = center_y + math.sin(tick_angle) * tick_outer
   r.ImGui_DrawList_AddLine(draw_list, tx1, ty1, tx2, ty2, 0xFFFFFF33, 1)
  end
  r.ImGui_DrawList_AddCircleFilled(draw_list, center_x, center_y, radius - 4, metal_highlight, 32)
  r.ImGui_DrawList_AddCircleFilled(draw_list, center_x + 1, center_y + 1, radius - 6, metal_color, 32)
  local pointer_length = radius - 2
  local pointer_x = center_x + math.cos(value_angle) * pointer_length
  local pointer_y = center_y + math.sin(value_angle) * pointer_length
  r.ImGui_DrawList_AddLine(draw_list, center_x, center_y, pointer_x, pointer_y, 0x000000FF, 2)
  r.ImGui_DrawList_AddCircleFilled(draw_list, center_x, center_y, math.max(2, radius * 0.2), 0x000000FF, 16)
 elseif style == 3 then
  r.ImGui_DrawList_AddCircleFilled(draw_list, center_x, center_y, radius, 0x0A0A0AFF, 32)
  local led_count = math.max(7, math.floor(radius))
  local led_radius = math.max(1, radius * 0.08)
  for i = 0, led_count - 1 do
   local led_angle = start_angle + (i / led_count) * angle_range
   local led_dist = radius - led_radius - 1
   local led_x = center_x + math.cos(led_angle) * led_dist
   local led_y = center_y + math.sin(led_angle) * led_dist
   local is_lit = (i / led_count) <= norm_val
   local led_color
   if is_lit then
    if i < led_count * 0.6 then
     led_color = 0x00FF00FF
    elseif i < led_count * 0.8 then
     led_color = 0xFFFF00FF
    else
     led_color = 0xFF0000FF
    end
   else
    led_color = 0x222222FF
   end
   r.ImGui_DrawList_AddCircleFilled(draw_list, led_x, led_y, led_radius, led_color, 8)
  end
  local inner_radius = radius - led_radius * 2 - 3
  r.ImGui_DrawList_AddCircleFilled(draw_list, center_x, center_y, inner_radius, 0x1A1A1AFF, 32)
  local dot_dist = inner_radius * 0.6
  local dot_x = center_x + math.cos(value_angle) * dot_dist
  local dot_y = center_y + math.sin(value_angle) * dot_dist
  r.ImGui_DrawList_AddCircleFilled(draw_list, dot_x, dot_y, math.max(1, radius * 0.1), knob_color, 8)
 elseif style == 4 then
  r.ImGui_DrawList_PathArcTo(draw_list, center_x, center_y, radius - 2, start_angle, end_angle, 32)
  r.ImGui_DrawList_PathStroke(draw_list, track_color, 0, 3)
  if norm_val > 0.01 then
   if is_bipolar then
    if norm_val > 0.5 then
     r.ImGui_DrawList_PathArcTo(draw_list, center_x, center_y, radius - 2, center_angle, value_angle, 32)
    else
     r.ImGui_DrawList_PathArcTo(draw_list, center_x, center_y, radius - 2, value_angle, center_angle, 32)
    end
   else
    r.ImGui_DrawList_PathArcTo(draw_list, center_x, center_y, radius - 2, start_angle, value_angle, 32)
   end
   r.ImGui_DrawList_PathStroke(draw_list, knob_color, 0, 3)
  end
  local dot_dist = radius - 2
  local dot_x = center_x + math.cos(value_angle) * dot_dist
  local dot_y = center_y + math.sin(value_angle) * dot_dist
  local dot_size = math.max(2, radius * 0.25)
  r.ImGui_DrawList_AddCircleFilled(draw_list, dot_x, dot_y, dot_size, knob_color, 16)
  r.ImGui_DrawList_AddCircleFilled(draw_list, center_x, center_y, math.max(2, radius * 0.2), track_color, 16)
 elseif style == 5 then
  if not mixer_state.knob_image_loaded then
   local knob_image_path = script_path .. "Images" .. os_separator .. "knob01.png"
   local ok, img = pcall(r.ImGui_CreateImage, knob_image_path)
   if ok and img then
    mixer_state.knob_image = img
    mixer_state.knob_image_loaded = true
   else
    mixer_state.knob_image_loaded = true
   end
  end
  if mixer_state.knob_image and r.ImGui_ValidatePtr(mixer_state.knob_image, 'ImGui_Image*') then
   local scale = 5.0
   local target_size = radius * scale
   local img_w, img_h = r.ImGui_Image_GetSize(mixer_state.knob_image)
   local aspect = img_w / img_h
   local draw_w, draw_h
   if aspect >= 1 then
    draw_w = target_size
    draw_h = target_size / aspect
   else
    draw_w = target_size * aspect
    draw_h = target_size
   end
   local img_x = center_x - draw_w / 2
   local img_y = center_y - draw_h / 2
   r.ImGui_DrawList_AddImage(draw_list, mixer_state.knob_image, img_x, img_y, img_x + draw_w, img_y + draw_h, 0, 0, 1, 1, 0xFFFFFFFF)
   local border_radius = math.min(draw_w, draw_h) / 2 * 0.6
   r.ImGui_DrawList_AddCircle(draw_list, center_x, center_y, border_radius, 0x000000FF, 32, 1)
   local knob_visual_radius = math.min(draw_w, draw_h) / 2 * 0.55
   local dot_dist = knob_visual_radius * 0.65
   local dot_x = center_x + math.cos(value_angle) * dot_dist
   local dot_y = center_y + math.sin(value_angle) * dot_dist
   local dot_size = math.max(1.5, knob_visual_radius * 0.08)
   local dot_color
   if is_bipolar then
    local deviation = math.abs(norm_val - 0.5) * 2
    if deviation < 0.3 then
     local t = deviation / 0.3
     local r_val = math.floor(t * 255)
     local g_val = 255
     dot_color = (r_val * 0x1000000) + (g_val * 0x10000) + 0x00FF
    elseif deviation < 0.7 then
     local t = (deviation - 0.3) / 0.4
     local r_val = 255
     local g_val = math.floor((1 - t * 0.5) * 255)
     dot_color = (r_val * 0x1000000) + (g_val * 0x10000) + 0x00FF
    else
     local t = (deviation - 0.7) / 0.3
     local r_val = 255
     local g_val = math.floor((1 - t) * 128)
     dot_color = (r_val * 0x1000000) + (g_val * 0x10000) + 0x00FF
    end
   else
    if norm_val < 0.5 then
     local t = norm_val * 2
     local r_val = math.floor(t * 255)
     local g_val = 255
     dot_color = (r_val * 0x1000000) + (g_val * 0x10000) + 0x00FF
    elseif norm_val < 0.8 then
     local t = (norm_val - 0.5) / 0.3
     local r_val = 255
     local g_val = math.floor((1 - t * 0.5) * 255)
     dot_color = (r_val * 0x1000000) + (g_val * 0x10000) + 0x00FF
    else
     local t = (norm_val - 0.8) / 0.2
     local r_val = 255
     local g_val = math.floor((1 - t) * 128)
     dot_color = (r_val * 0x1000000) + (g_val * 0x10000) + 0x00FF
    end
   end
   r.ImGui_DrawList_AddCircleFilled(draw_list, dot_x, dot_y, dot_size, dot_color, 12)
  else
   local center_angle = (start_angle + end_angle) / 2
   r.ImGui_DrawList_AddCircleFilled(draw_list, center_x, center_y, radius, track_color, 32)
   r.ImGui_DrawList_PathArcTo(draw_list, center_x, center_y, radius - 2, start_angle, value_angle, 32)
   r.ImGui_DrawList_PathStroke(draw_list, knob_color, 0, 3)
   local dot_dist = radius - 2
   local dx = center_x + math.cos(value_angle) * dot_dist
   local dy = center_y + math.sin(value_angle) * dot_dist
   r.ImGui_DrawList_AddCircleFilled(draw_list, dx, dy, math.max(2, radius * 0.25), knob_color, 16)
  end
 end
end

local function DrawCompKnob(ctx, draw_list, x, y, radius, value, label, track, fx_index, param_idx)
 local knob_color = settings.simple_mixer_comp_knob_color or 0xCCCCCCFF
 local track_color = settings.simple_mixer_comp_knob_track_color or 0x555555FF
 local text_color = settings.simple_mixer_comp_text_color or 0xAAAAAAFF
 DrawStyledKnob(ctx, draw_list, x, y, radius, value, knob_color, false, settings.simple_mixer_knob_style, track_color)
 if settings.simple_mixer_comp_show_labels then
  local font_size = 8
  local text_w = r.ImGui_CalcTextSize(ctx, label)
  local scaled_text_w = text_w * (font_size / r.ImGui_GetFontSize(ctx))
  r.ImGui_DrawList_AddTextEx(draw_list, nil, font_size, x - scaled_text_w / 2, y + radius - 1, text_color, label)
 end
 local inv_btn_id = "##knob_" .. label .. "_" .. tostring(track)
 r.ImGui_SetCursorScreenPos(ctx, x - radius, y - radius)
 r.ImGui_InvisibleButton(ctx, inv_btn_id, radius * 2, radius * 2)
 local is_hovered = r.ImGui_IsItemHovered(ctx)
 local is_active = r.ImGui_IsItemActive(ctx)
 if r.ImGui_IsItemClicked(ctx, 1) and fx_index >= 0 then
  r.ImGui_OpenPopup(ctx, "comp_knob_menu_" .. label .. "_" .. tostring(track))
 end
 if r.ImGui_BeginPopup(ctx, "comp_knob_menu_" .. label .. "_" .. tostring(track)) then
  local presets = {}
  if param_idx == 0 then
   presets = {
    {name = "Reset (0 dB)", value = 1.0},
    {name = "-6 dB", value = 0.9},
    {name = "-12 dB", value = 0.8},
    {name = "-18 dB", value = 0.7},
    {name = "-24 dB", value = 0.6},
    {name = "-30 dB", value = 0.5},
   }
  elseif param_idx == 3 then
   presets = {
    {name = "Fastest (20 us)", value = 0.0},
    {name = "Fast (500 us)", value = 0.25},
    {name = "Medium (1 ms)", value = 0.5},
    {name = "Slow (1.5 ms)", value = 0.75},
    {name = "Slowest (2 ms)", value = 1.0},
   }
  elseif param_idx == 4 then
   presets = {
    {name = "Fastest (20 ms)", value = 0.0},
    {name = "Fast (100 ms)", value = 0.08},
    {name = "Medium (250 ms)", value = 0.23},
    {name = "Slow (500 ms)", value = 0.49},
    {name = "Very Slow (750 ms)", value = 0.74},
    {name = "Slowest (1 sec)", value = 1.0},
   }
  elseif param_idx == 2 then
   presets = {
    {name = "Reset (0 dB)", value = 0.5},
    {name = "+3 dB", value = 0.575},
    {name = "+6 dB", value = 0.65},
    {name = "+12 dB", value = 0.8},
    {name = "-3 dB", value = 0.425},
    {name = "-6 dB", value = 0.35},
   }
  elseif param_idx == 5 then
   presets = {
    {name = "Reset (100%)", value = 1.0},
    {name = "75%", value = 0.75},
    {name = "50%", value = 0.5},
    {name = "25%", value = 0.25},
    {name = "0% (Dry)", value = 0.0},
   }
  end
  for _, preset in ipairs(presets) do
   if r.ImGui_MenuItem(ctx, preset.name) then
    SetCompressorParam(track, fx_index, param_idx, preset.value)
   end
  end
  r.ImGui_EndPopup(ctx)
 end
 if is_active then
  local _, delta_y = r.ImGui_GetMouseDragDelta(ctx, 0, 0.0)
  if math.abs(delta_y) > 0 then
   local new_value = math.max(0, math.min(1, value - delta_y * 0.005))
   SetCompressorParam(track, fx_index, param_idx, new_value)
   r.ImGui_ResetMouseDragDelta(ctx, 0)
  end
 end
 if (is_hovered or is_active) and fx_index >= 0 then
  local real_param_idx = STRIP_OFFSET.COMP + param_idx
  local _, param_name = r.TrackFX_GetParamName(track, fx_index, real_param_idx)
  local param_val = r.TrackFX_GetParam(track, fx_index, real_param_idx)
  local _, formatted = r.TrackFX_GetFormattedParamValue(track, fx_index, real_param_idx)
  r.ImGui_SetTooltip(ctx, string.format("%s: %s", param_name or label, formatted or string.format("%.0f%%", param_val * 100)))
 end
 return is_hovered
end

local function DrawRatioKnob(ctx, draw_list, x, y, radius, value, track, fx_index, param_idx)
 local btn_width = radius * 3.2
 local btn_height = radius * 1.6
 local btn_x = x - btn_width / 2
 local btn_y = y - btn_height / 2
 r.ImGui_DrawList_AddRectFilled(draw_list, btn_x + 2, btn_y + 2, btn_x + btn_width + 2, btn_y + btn_height + 2, 0x00000088, 3)
 r.ImGui_DrawList_AddRectFilled(draw_list, btn_x, btn_y, btn_x + btn_width, btn_y + btn_height, 0xEEEEEEFF, 3)
 r.ImGui_DrawList_AddRect(draw_list, btn_x, btn_y, btn_x + btn_width, btn_y + btn_height, 0x000000FF, 3, 0, 1)
 local ratio_names = {"BC4", "BC8", "BC12", "BC20", "BCAll", "4", "8", "12", "20", "All"}
 local ratio_steps = {0.0, 0.111, 0.222, 0.333, 0.444, 0.556, 0.667, 0.778, 0.889, 1.0}
 local current_idx = 1
 local min_diff = 1
 for i, v in ipairs(ratio_steps) do
  local diff = math.abs(value - v)
  if diff < min_diff then
   min_diff = diff
   current_idx = i
  end
 end
 local display_text = ratio_names[current_idx] or "4"
 local font_size = 9
 local text_w = r.ImGui_CalcTextSize(ctx, display_text)
 local scaled_text_w = text_w * (font_size / r.ImGui_GetFontSize(ctx))
 local text_x = x - scaled_text_w / 2
 local text_y = btn_y + (btn_height - font_size) / 2
 r.ImGui_DrawList_AddTextEx(draw_list, nil, font_size, text_x, text_y, 0x000000FF, display_text)
 local label = "Ratio"
 local label_font_size = 8
 local label_w = r.ImGui_CalcTextSize(ctx, label)
 local scaled_label_w = label_w * (label_font_size / r.ImGui_GetFontSize(ctx))
 local text_color = settings.simple_mixer_comp_text_color or 0xAAAAAAFF
 r.ImGui_DrawList_AddTextEx(draw_list, nil, label_font_size, x - scaled_label_w / 2, btn_y + btn_height + 1, text_color, label)
 r.ImGui_SetCursorScreenPos(ctx, btn_x, btn_y)
 r.ImGui_InvisibleButton(ctx, "##ratio_btn_" .. tostring(track), btn_width, btn_height)
 local is_hovered = r.ImGui_IsItemHovered(ctx)
 local is_clicked = r.ImGui_IsItemClicked(ctx, 0)
 local is_right_clicked = r.ImGui_IsItemClicked(ctx, 1)
 if is_clicked and fx_index >= 0 then
  local next_idx = (current_idx % #ratio_steps) + 1
  SetCompressorParam(track, fx_index, param_idx, ratio_steps[next_idx])
 end
 if is_right_clicked and fx_index >= 0 then
  local prev_idx = current_idx - 1
  if prev_idx < 1 then prev_idx = #ratio_steps end
  SetCompressorParam(track, fx_index, param_idx, ratio_steps[prev_idx])
 end
 if is_hovered then
  r.ImGui_SetTooltip(ctx, "Click to cycle ratio | Right-click reverse")
 end
 return is_hovered
end

local function DrawGRMeter(ctx, draw_list, x, y, width, height, gr_value)
 local bg_color = settings.simple_mixer_comp_gr_bg_color or 0x333333FF
 local gr_color = settings.simple_mixer_comp_gr_color or 0xFF6644FF
 r.ImGui_DrawList_AddRectFilled(draw_list, x, y, x + width, y + height, bg_color, 2)
 local gr_width = gr_value * width
 if gr_width > 1 then
  r.ImGui_DrawList_AddRectFilled(draw_list, x + width - gr_width, y + 1, x + width, y + height - 1, gr_color, 1)
 end
 r.ImGui_DrawList_AddRect(draw_list, x, y, x + width, y + height, 0x555555FF, 2, 0, 1)
end

local function DrawCompressorModule(ctx, draw_list, x, y, width, height, track_guid, track)
 if not settings.simple_mixer_show_compressor then return 0 end
 if not track then return 0 end
 local fx_index = FindCompressorFX(track, track_guid)
 local params = nil
 local has_comp = fx_index >= 0
 if has_comp then
  params = GetCompressorParams(track, fx_index)
 end
 local bg_color = settings.simple_mixer_comp_bg_color or 0x1A1A2AFF
 local header_color = settings.simple_mixer_comp_header_color or 0x3A3A5AFF
 local text_color = settings.simple_mixer_comp_text_color or 0xAAAAAAFF
 local bypass_color = settings.simple_mixer_comp_bypass_color or 0x666600FF
 local active_color = settings.simple_mixer_comp_active_color or 0x00AA44FF
 local comp_height = 120
 local header_height = 14
 local knob_radius = 8
 local row_height = 32
 r.ImGui_DrawList_AddRectFilled(draw_list, x, y, x + width, y + comp_height, bg_color, 3)
 local gloss_x = x + width * 0.25
 local gloss_y = y + comp_height * 0.3
 local gloss_radius = width * 0.4
 r.ImGui_DrawList_AddCircleFilled(draw_list, gloss_x, gloss_y, gloss_radius, 0xFFFFFF08, 24)
 r.ImGui_DrawList_AddCircleFilled(draw_list, gloss_x, gloss_y, gloss_radius * 0.6, 0xFFFFFF06, 24)
 r.ImGui_DrawList_AddRectFilled(draw_list, x, y, x + width, y + header_height, header_color, 3, r.ImGui_DrawFlags_RoundCornersTop())
 local header_text = "COMP"
 local header_w = r.ImGui_CalcTextSize(ctx, header_text)
 r.ImGui_DrawList_AddText(draw_list, x + (width - header_w) / 2, y, 0xFFFFFFFF, header_text)
 if has_comp then
  r.ImGui_SetCursorScreenPos(ctx, x + 12, y)
  if r.ImGui_InvisibleButton(ctx, "##comp_header_" .. track_guid, width - 24, header_height) then
   local hwnd = r.TrackFX_GetFloatingWindow(track, fx_index)
   r.TrackFX_Show(track, fx_index, hwnd and 2 or 3)
  end
  if r.ImGui_IsItemClicked(ctx, 1) then
   r.ImGui_OpenPopup(ctx, "##comp_reset_menu_" .. track_guid)
  end
  if r.ImGui_BeginPopup(ctx, "##comp_reset_menu_" .. track_guid) then
   if r.ImGui_MenuItem(ctx, "Reset Compressor") then
    ResetCompressor(track, fx_index)
   end
   r.ImGui_EndPopup(ctx)
  end
 end
 if has_comp then
  local bypass_btn_size = 8
  local bypass_btn_x = x + width - bypass_btn_size - 2
  local bypass_btn_y = y + 2
  local is_enabled = params and params.enabled
  local btn_color = is_enabled and active_color or bypass_color
  r.ImGui_DrawList_AddRectFilled(draw_list, bypass_btn_x, bypass_btn_y, bypass_btn_x + bypass_btn_size, bypass_btn_y + bypass_btn_size, btn_color, 2)
  r.ImGui_SetCursorScreenPos(ctx, bypass_btn_x, bypass_btn_y)
  if r.ImGui_InvisibleButton(ctx, "##comp_bypass_" .. track_guid, bypass_btn_size, bypass_btn_size) then
   r.TrackFX_SetParamNormalized(track, fx_index, STRIP_OFFSET.COMP_BYPASS, is_enabled and 0 or 1)
  end
  local remove_btn_x = x + 2
  local remove_btn_y = y + 2
  r.ImGui_DrawList_AddRectFilled(draw_list, remove_btn_x, remove_btn_y, remove_btn_x + bypass_btn_size, remove_btn_y + bypass_btn_size, 0x333333FF, 2)
  r.ImGui_SetCursorScreenPos(ctx, remove_btn_x, remove_btn_y)
  if r.ImGui_InvisibleButton(ctx, "##comp_remove_" .. track_guid, bypass_btn_size, bypass_btn_size) then
   r.TrackFX_Delete(track, fx_index)
   comp_fx_cache[track_guid] = nil
  end
 end
 local content_y = y + header_height + 2
 if not has_comp then
  local add_text = "+ Add"
  local add_w = r.ImGui_CalcTextSize(ctx, add_text)
  local add_x = x + (width - add_w) / 2
  local add_y = y + comp_height / 2 - 6
  r.ImGui_DrawList_AddText(draw_list, add_x, add_y, text_color, add_text)
  r.ImGui_SetCursorScreenPos(ctx, x, y + header_height)
  if r.ImGui_InvisibleButton(ctx, "##add_comp_" .. track_guid, width, comp_height - header_height) then
   InsertCompressorFX(track, track_guid)
  end
  r.ImGui_DrawList_AddRect(draw_list, x, y, x + width, y + comp_height, 0x444444FF, 3, 0, 1)
  r.ImGui_SetCursorScreenPos(ctx, x, y)
  return comp_height
 end
 local left_x = x + width * 0.25
 local right_x = x + width * 0.75
 local row1_y = content_y + knob_radius
 DrawCompKnob(ctx, draw_list, left_x, row1_y, knob_radius, params.threshold, "Thres", track, fx_index, 0)
 DrawRatioKnob(ctx, draw_list, right_x, row1_y, knob_radius, params.ratio, track, fx_index, 1)
 local row2_y = row1_y + row_height
 DrawCompKnob(ctx, draw_list, left_x, row2_y, knob_radius, params.attack, "Attack", track, fx_index, 3)
 DrawCompKnob(ctx, draw_list, right_x, row2_y, knob_radius, params.release, "Release", track, fx_index, 4)
 local row3_y = row2_y + row_height
 DrawCompKnob(ctx, draw_list, left_x, row3_y, knob_radius, params.gain, "Gain", track, fx_index, 2)
 DrawCompKnob(ctx, draw_list, right_x, row3_y, knob_radius, params.mix, "Mix", track, fx_index, 5)
 if settings.simple_mixer_comp_show_gr_meter then
  local gr_y = row3_y + knob_radius + 11
  local gr_height = 5
  local gr_margin = 3
  DrawGRMeter(ctx, draw_list, x + gr_margin, gr_y, width - gr_margin * 2, gr_height, params.gr or 0)
 end
 r.ImGui_DrawList_AddRect(draw_list, x, y, x + width, y + comp_height, 0x444444FF, 3, 0, 1)
 r.ImGui_SetCursorScreenPos(ctx, x, y)
 return comp_height
end

local Limiter = {
 fx_cache = {}
}

function Limiter.FindFX(track, track_guid)
 return FindChannelStripFX(track, track_guid)
end

function Limiter.InsertFX(track, track_guid)
 return InsertChannelStripFX(track, track_guid)
end

function Limiter.Reset(track, fx_index)
 if fx_index < 0 then return end
 r.TrackFX_SetParam(track, fx_index, STRIP_OFFSET.LIM + 0, -3)
 r.TrackFX_SetParam(track, fx_index, STRIP_OFFSET.LIM + 1, 200)
 r.TrackFX_SetParam(track, fx_index, STRIP_OFFSET.LIM + 2, 100)
 r.TrackFX_SetParam(track, fx_index, STRIP_OFFSET.LIM + 3, 0)
 r.TrackFX_SetParam(track, fx_index, STRIP_OFFSET.LIM + 4, 250)
 r.TrackFX_SetParam(track, fx_index, STRIP_OFFSET.LIM + 5, -0.1)
end

function Limiter.GetParams(track, fx_index)
 if fx_index < 0 then return nil end
 local plugin_enabled = r.TrackFX_GetEnabled(track, fx_index)
 local thresh = r.TrackFX_GetParam(track, fx_index, STRIP_OFFSET.LIM + 0)
 local lookahead = r.TrackFX_GetParam(track, fx_index, STRIP_OFFSET.LIM + 1)
 local attack = r.TrackFX_GetParam(track, fx_index, STRIP_OFFSET.LIM + 2)
 local hold = r.TrackFX_GetParam(track, fx_index, STRIP_OFFSET.LIM + 3)
 local release = r.TrackFX_GetParam(track, fx_index, STRIP_OFFSET.LIM + 4)
 local limit = r.TrackFX_GetParam(track, fx_index, STRIP_OFFSET.LIM + 5)
 local gr_db = r.TrackFX_GetParam(track, fx_index, STRIP_OFFSET.LIM + 6)
 local params = {
  threshold = (thresh + 20) / 19.9,
  lookahead = lookahead / 1000,
  attack = attack / 1000,
  hold = hold / 10,
  release = release / 1000,
  limit = (limit + 6) / 6,
  enabled = plugin_enabled and r.TrackFX_GetParam(track, fx_index, STRIP_OFFSET.LIM_BYPASS) == 1,
  gr = math.min(1, math.abs(gr_db) / 20)
 }
 return params
end

function Limiter.SetParam(track, fx_index, param_idx, value)
 r.TrackFX_SetParamNormalized(track, fx_index, STRIP_OFFSET.LIM + param_idx, value)
end

function Limiter.DrawKnob(ctx, draw_list, x, y, radius, value, label, track, fx_index, param_idx)
 local knob_color = settings.simple_mixer_lim_knob_color or 0xCCCCCCFF
 local track_color = settings.simple_mixer_lim_knob_track_color or 0x555555FF
 local text_color = settings.simple_mixer_lim_text_color or 0xAAAAAAFF
 DrawStyledKnob(ctx, draw_list, x, y, radius, value, knob_color, false, settings.simple_mixer_knob_style, track_color)
 if settings.simple_mixer_lim_show_labels then
  local text_w = r.ImGui_CalcTextSize(ctx, label)
  local scaled_text_w = text_w * (8 / r.ImGui_GetFontSize(ctx))
  r.ImGui_DrawList_AddTextEx(draw_list, nil, 8, x - scaled_text_w / 2, y + radius - 1, text_color, label)
 end
 r.ImGui_SetCursorScreenPos(ctx, x - radius, y - radius)
 r.ImGui_InvisibleButton(ctx, "##limknob_" .. label .. "_" .. tostring(track), radius * 2, radius * 2)
 local is_hovered = r.ImGui_IsItemHovered(ctx)
 local is_active = r.ImGui_IsItemActive(ctx)
 if r.ImGui_IsItemClicked(ctx, 1) and fx_index >= 0 then
  r.ImGui_OpenPopup(ctx, "lim_knob_menu_" .. label .. "_" .. tostring(track))
 end
 if r.ImGui_BeginPopup(ctx, "lim_knob_menu_" .. label .. "_" .. tostring(track)) then
  local presets = {}
  if param_idx == 0 then
   presets = {
    {name = "Reset (-3 dB)", value = 0.85},
    {name = "-1 dB", value = 0.95},
    {name = "-2 dB", value = 0.9},
    {name = "-6 dB", value = 0.7},
    {name = "-10 dB", value = 0.5},
    {name = "-15 dB", value = 0.25},
   }
  elseif param_idx == 1 then
   presets = {
    {name = "Reset (200 us)", value = 0.2},
    {name = "Off (0 us)", value = 0.0},
    {name = "50 us", value = 0.05},
    {name = "100 us", value = 0.1},
    {name = "500 us", value = 0.5},
    {name = "Max (1 ms)", value = 1.0},
   }
  elseif param_idx == 2 then
   presets = {
    {name = "Reset (100 us)", value = 0.1},
    {name = "Instant (0 us)", value = 0.0},
    {name = "50 us", value = 0.05},
    {name = "200 us", value = 0.2},
    {name = "500 us", value = 0.5},
    {name = "Max (1 ms)", value = 1.0},
   }
  elseif param_idx == 3 then
   presets = {
    {name = "Reset (0 ms)", value = 0.0},
    {name = "1 ms", value = 0.1},
    {name = "2 ms", value = 0.2},
    {name = "5 ms", value = 0.5},
    {name = "10 ms", value = 1.0},
   }
  elseif param_idx == 4 then
   presets = {
    {name = "Reset (250 ms)", value = 0.25},
    {name = "Fast (50 ms)", value = 0.05},
    {name = "Medium (100 ms)", value = 0.1},
    {name = "Slow (500 ms)", value = 0.5},
    {name = "Very Slow (750 ms)", value = 0.75},
    {name = "Max (1 sec)", value = 1.0},
   }
  elseif param_idx == 5 then
   presets = {
    {name = "Reset (-0.1 dB)", value = 1.0},
    {name = "0 dB", value = 1.0},
    {name = "-0.3 dB", value = 0.95},
    {name = "-1 dB", value = 0.833},
    {name = "-2 dB", value = 0.667},
    {name = "-3 dB", value = 0.5},
    {name = "-6 dB", value = 0.0},
   }
  end
  for _, preset in ipairs(presets) do
   if r.ImGui_MenuItem(ctx, preset.name) then
    Limiter.SetParam(track, fx_index, param_idx, preset.value)
   end
  end
  r.ImGui_EndPopup(ctx)
 end
 if is_active then
  local _, dy = r.ImGui_GetMouseDragDelta(ctx, 0)
  if math.abs(dy) > 0 then
   Limiter.SetParam(track, fx_index, param_idx, math.max(0, math.min(1, value - dy * 0.005)))
   r.ImGui_ResetMouseDragDelta(ctx, 0)
  end
 end
 if (is_hovered or is_active) and fx_index >= 0 then
  local real_param_idx = STRIP_OFFSET.LIM + param_idx
  local _, param_name = r.TrackFX_GetParamName(track, fx_index, real_param_idx)
  local _, formatted = r.TrackFX_GetFormattedParamValue(track, fx_index, real_param_idx)
  r.ImGui_SetTooltip(ctx, string.format("%s: %s", param_name or label, formatted or ""))
 end
 return is_hovered
end

function Limiter.DrawGRMeter(ctx, draw_list, x, y, width, height, gr_value)
 local bg_color = settings.simple_mixer_lim_gr_bg_color or 0x333333FF
 local gr_color = settings.simple_mixer_lim_gr_color or 0xFF4466FF
 r.ImGui_DrawList_AddRectFilled(draw_list, x, y, x + width, y + height, bg_color, 2)
 local gr_width = gr_value * width
 if gr_width > 1 then
  r.ImGui_DrawList_AddRectFilled(draw_list, x + width - gr_width, y + 1, x + width, y + height - 1, gr_color, 1)
 end
 r.ImGui_DrawList_AddRect(draw_list, x, y, x + width, y + height, 0x555555FF, 2, 0, 1)
end

function Limiter.DrawModule(ctx, draw_list, x, y, width, height, track_guid, track)
 if not settings.simple_mixer_show_limiter or not track then return 0 end
 local fx_index = Limiter.FindFX(track, track_guid)
 if fx_index < 0 and settings.simple_mixer_lim_auto_insert ~= false and not track_guid:match("^MASTER") then
  fx_index = Limiter.InsertFX(track, track_guid)
 end
 local params = fx_index >= 0 and Limiter.GetParams(track, fx_index) or nil
 local has_lim = fx_index >= 0
 local bg_color = settings.simple_mixer_lim_bg_color or 0x2A1A2AFF
 local header_color = settings.simple_mixer_lim_header_color or 0x5A3A5AFF
 local text_color = settings.simple_mixer_lim_text_color or 0xAAAAAAFF
 local lim_height, header_height, knob_radius, row_height = 120, 14, 8, 32
 r.ImGui_DrawList_AddRectFilled(draw_list, x, y, x + width, y + lim_height, bg_color, 3)
 r.ImGui_DrawList_AddCircleFilled(draw_list, x + width * 0.25, y + lim_height * 0.3, width * 0.4, 0xFFFFFF08, 24)
 r.ImGui_DrawList_AddCircleFilled(draw_list, x + width * 0.25, y + lim_height * 0.3, width * 0.24, 0xFFFFFF06, 24)
 r.ImGui_DrawList_AddRectFilled(draw_list, x, y, x + width, y + header_height, header_color, 3, r.ImGui_DrawFlags_RoundCornersTop())
 local header_w = r.ImGui_CalcTextSize(ctx, "LIMIT")
 r.ImGui_DrawList_AddText(draw_list, x + (width - header_w) / 2, y, 0xFFFFFFFF, "LIMIT")
 if has_lim then
  r.ImGui_SetCursorScreenPos(ctx, x + 12, y)
  if r.ImGui_InvisibleButton(ctx, "##lim_header_" .. track_guid, width - 24, header_height) then
   local hwnd = r.TrackFX_GetFloatingWindow(track, fx_index)
   r.TrackFX_Show(track, fx_index, hwnd and 2 or 3)
  end
  if r.ImGui_IsItemClicked(ctx, 1) then
   r.ImGui_OpenPopup(ctx, "##lim_reset_menu_" .. track_guid)
  end
  if r.ImGui_BeginPopup(ctx, "##lim_reset_menu_" .. track_guid) then
   if r.ImGui_MenuItem(ctx, "Reset Limiter") then
    Limiter.Reset(track, fx_index)
   end
   r.ImGui_EndPopup(ctx)
  end
 end
 if has_lim then
  local btn_size, btn_x, btn_y = 8, x + width - 10, y + 2
  local btn_color = (params and params.enabled) and (settings.simple_mixer_lim_active_color or 0x00AA44FF) or (settings.simple_mixer_lim_bypass_color or 0x666600FF)
  r.ImGui_DrawList_AddRectFilled(draw_list, btn_x, btn_y, btn_x + btn_size, btn_y + btn_size, btn_color, 2)
  r.ImGui_SetCursorScreenPos(ctx, btn_x, btn_y)
  if r.ImGui_InvisibleButton(ctx, "##lim_bypass_" .. track_guid, btn_size, btn_size) then
   local is_enabled = params and params.enabled
   r.TrackFX_SetParamNormalized(track, fx_index, STRIP_OFFSET.LIM_BYPASS, is_enabled and 0 or 1)
  end
  local remove_btn_x = x + 2
  local remove_btn_y = y + 2
  r.ImGui_DrawList_AddRectFilled(draw_list, remove_btn_x, remove_btn_y, remove_btn_x + btn_size, remove_btn_y + btn_size, 0x333333FF, 2)
  r.ImGui_SetCursorScreenPos(ctx, remove_btn_x, remove_btn_y)
  if r.ImGui_InvisibleButton(ctx, "##lim_remove_" .. track_guid, btn_size, btn_size) then
   r.TrackFX_Delete(track, fx_index)
   Limiter.fx_cache[track_guid] = nil
  end
 end
 if not has_lim then
  local add_w = r.ImGui_CalcTextSize(ctx, "+ Add")
  r.ImGui_DrawList_AddText(draw_list, x + (width - add_w) / 2, y + lim_height / 2 - 6, text_color, "+ Add")
  r.ImGui_SetCursorScreenPos(ctx, x, y + header_height)
  if r.ImGui_InvisibleButton(ctx, "##add_lim_" .. track_guid, width, lim_height - header_height) then
   Limiter.InsertFX(track, track_guid)
  end
  r.ImGui_DrawList_AddRect(draw_list, x, y, x + width, y + lim_height, 0x444444FF, 3, 0, 1)
  r.ImGui_SetCursorScreenPos(ctx, x, y)
  return lim_height
 end
 local left_x, right_x = x + width * 0.25, x + width * 0.75
 local row1_y = y + header_height + 2 + knob_radius
 Limiter.DrawKnob(ctx, draw_list, left_x, row1_y, knob_radius, params.threshold, "Thres", track, fx_index, 0)
 Limiter.DrawKnob(ctx, draw_list, right_x, row1_y, knob_radius, params.limit, "Limit", track, fx_index, 5)
 local row2_y = row1_y + row_height
 Limiter.DrawKnob(ctx, draw_list, left_x, row2_y, knob_radius, params.attack, "Attack", track, fx_index, 2)
 Limiter.DrawKnob(ctx, draw_list, right_x, row2_y, knob_radius, params.release, "Release", track, fx_index, 4)
 local row3_y = row2_y + row_height
 Limiter.DrawKnob(ctx, draw_list, left_x, row3_y, knob_radius, params.hold, "Hold", track, fx_index, 3)
 Limiter.DrawKnob(ctx, draw_list, right_x, row3_y, knob_radius, params.lookahead, "Look", track, fx_index, 1)
 if settings.simple_mixer_lim_show_gr_meter then
  Limiter.DrawGRMeter(ctx, draw_list, x + 3, row3_y + knob_radius + 11, width - 6, 5, params.gr or 0)
 end
 r.ImGui_DrawList_AddRect(draw_list, x, y, x + width, y + lim_height, 0x444444FF, 3, 0, 1)
 r.ImGui_SetCursorScreenPos(ctx, x, y)
 return lim_height
end

local Trim = {
 fx_cache = {}
}

function Trim.FindFX(track, track_guid)
 if Trim.fx_cache[track_guid] then
  local cached = Trim.fx_cache[track_guid]
  if cached.fx_index >= 0 then
   local retval, fx_name = r.TrackFX_GetFXName(track, cached.fx_index, "")
   if retval then
    local name_lower = fx_name:lower()
    if name_lower:find("tk_trim") or name_lower:find("tk trim") then
     return cached.fx_index
    end
   end
  end
  Trim.fx_cache[track_guid] = nil
 end
 local fx_count = r.TrackFX_GetCount(track)
 for i = 0, fx_count - 1 do
  local retval, fx_name = r.TrackFX_GetFXName(track, i, "")
  if retval then
   local name_lower = fx_name:lower()
   if name_lower:find("tk_trim") or name_lower:find("tk trim") then
    Trim.fx_cache[track_guid] = {fx_index = i}
    return i
   end
  end
 end
 return -1
end

function Trim.InsertFX(track, track_guid)
 local existing = Trim.FindFX(track, track_guid)
 if existing >= 0 then return existing end
 local instrument_idx = r.TrackFX_GetInstrument(track)
 local insert_pos
 if instrument_idx >= 0 then
  insert_pos = -(instrument_idx + 1001)
 else
  insert_pos = -1000
 end
 local fx_index = r.TrackFX_AddByName(track, "JS:TK_Trim", false, insert_pos)
 if fx_index >= 0 then
  r.TrackFX_SetEnabled(track, fx_index, true)
  Trim.fx_cache[track_guid] = {fx_index = fx_index}
 end
 return fx_index
end

function Trim.GetValue(track, fx_index)
 if fx_index < 0 then return 0 end
 local retval, minval, maxval = r.TrackFX_GetParamEx(track, fx_index, 0)
 return retval
end

function Trim.SetValue(track, fx_index, db_value)
 if fx_index < 0 then return end
 db_value = math.max(-24, math.min(24, db_value))
 r.TrackFX_SetParam(track, fx_index, 0, db_value)
end

function Trim.DrawKnob(ctx, draw_list, x, y, radius, value_db, track, fx_index, track_guid)
 local knob_color = settings.simple_mixer_trim_knob_color or 0xCCCCCCFF
 local track_color = settings.simple_mixer_trim_knob_track_color or 0x555555FF
 local text_color = settings.simple_mixer_trim_text_color or 0xAAAAAAFF
 local norm = (value_db + 24) / 48
 DrawStyledKnob(ctx, draw_list, x, y, radius, norm, knob_color, true, settings.simple_mixer_knob_style, track_color)
 r.ImGui_SetCursorScreenPos(ctx, x - radius, y - radius)
 r.ImGui_InvisibleButton(ctx, "##trim_knob_" .. tostring(track), radius * 2, radius * 2)
 local is_hovered = r.ImGui_IsItemHovered(ctx)
 local is_active = r.ImGui_IsItemActive(ctx)
 if is_active then
  local _, dy = r.ImGui_GetMouseDragDelta(ctx, 0)
  if math.abs(dy) > 0 then
   local sensitivity = 0.3
   local new_db = value_db - dy * sensitivity
   new_db = math.max(-24, math.min(24, new_db))
   Trim.SetValue(track, fx_index, new_db)
   r.ImGui_ResetMouseDragDelta(ctx, 0)
  end
 end
 if r.ImGui_IsItemClicked(ctx, 1) then
  Trim.SetValue(track, fx_index, 0)
 end
 if is_hovered or is_active then
  r.ImGui_SetTooltip(ctx, string.format("Trim: %.1f dB", value_db))
 end
 return is_hovered, is_active
end

function Trim.DrawModule(ctx, draw_list, x, y, width, track_guid, track)
 if not settings.simple_mixer_show_trim or not track then return 0 end
 local fx_index = Trim.FindFX(track, track_guid)
 if fx_index < 0 and settings.simple_mixer_trim_auto_insert ~= false and not track_guid:match("^MASTER") then
  fx_index = Trim.InsertFX(track, track_guid)
 end
 local has_trim = fx_index >= 0
 local is_enabled = has_trim and r.TrackFX_GetEnabled(track, fx_index) or false
 local bg_color = settings.simple_mixer_trim_bg_color or 0x2A2A1AFF
 local header_color = settings.simple_mixer_trim_header_color or 0x5A5A3AFF
 local text_color = settings.simple_mixer_trim_text_color or 0xAAAAAAFF
 local active_color = settings.simple_mixer_trim_active_color or 0x88AA00FF
 local trim_height, header_height, knob_radius = 38, 12, 8
 r.ImGui_DrawList_AddRectFilled(draw_list, x, y, x + width, y + trim_height, bg_color, 3)
 r.ImGui_DrawList_AddRectFilled(draw_list, x, y, x + width, y + header_height, header_color, 3, r.ImGui_DrawFlags_RoundCornersTop())
 local header_text = "TRIM"
 local header_w = r.ImGui_CalcTextSize(ctx, header_text)
 r.ImGui_DrawList_AddText(draw_list, x + (width - header_w) / 2, y, 0xFFFFFFFF, header_text)
 if has_trim then
  r.ImGui_SetCursorScreenPos(ctx, x + 12, y)
  if r.ImGui_InvisibleButton(ctx, "##trim_header_" .. track_guid, width - 24, header_height) then
   local hwnd = r.TrackFX_GetFloatingWindow(track, fx_index)
   r.TrackFX_Show(track, fx_index, hwnd and 2 or 3)
  end
  if r.ImGui_IsItemClicked(ctx, 1) then
   r.ImGui_OpenPopup(ctx, "##trim_reset_menu_" .. track_guid)
  end
  if r.ImGui_BeginPopup(ctx, "##trim_reset_menu_" .. track_guid) then
   if r.ImGui_MenuItem(ctx, "Reset Trim") then
    Trim.SetValue(track, fx_index, 0)
   end
   r.ImGui_EndPopup(ctx)
  end
  local btn_size, btn_x, btn_y = 7, x + width - 9, y + 2
  local btn_color = is_enabled and active_color or 0x666600FF
  r.ImGui_DrawList_AddRectFilled(draw_list, btn_x, btn_y, btn_x + btn_size, btn_y + btn_size, btn_color, 2)
  r.ImGui_SetCursorScreenPos(ctx, btn_x, btn_y)
  if r.ImGui_InvisibleButton(ctx, "##trim_bypass_" .. track_guid, btn_size, btn_size) then
   r.TrackFX_SetEnabled(track, fx_index, not is_enabled)
  end
  local remove_btn_x = x + 2
  local remove_btn_y = y + 2
  r.ImGui_DrawList_AddRectFilled(draw_list, remove_btn_x, remove_btn_y, remove_btn_x + btn_size, remove_btn_y + btn_size, 0x333333FF, 2)
  r.ImGui_SetCursorScreenPos(ctx, remove_btn_x, remove_btn_y)
  if r.ImGui_InvisibleButton(ctx, "##trim_remove_" .. track_guid, btn_size, btn_size) then
   r.TrackFX_Delete(track, fx_index)
   Trim.fx_cache[track_guid] = nil
  end
 end
 if not has_trim then
  local add_text = "+ Add"
  local add_w = r.ImGui_CalcTextSize(ctx, add_text)
  r.ImGui_DrawList_AddText(draw_list, x + (width - add_w) / 2, y + header_height + 8, text_color, add_text)
  r.ImGui_SetCursorScreenPos(ctx, x, y + header_height)
  if r.ImGui_InvisibleButton(ctx, "##add_trim_" .. track_guid, width, trim_height - header_height) then
   Trim.InsertFX(track, track_guid)
  end
  r.ImGui_DrawList_AddRect(draw_list, x, y, x + width, y + trim_height, 0x444444FF, 3, 0, 1)
  r.ImGui_SetCursorScreenPos(ctx, x, y)
  return trim_height
 end
 local trim_db = Trim.GetValue(track, fx_index)
 local knob_y = y + header_height + knob_radius + 4
 local knob_x = x + width / 2
 Trim.DrawKnob(ctx, draw_list, knob_x, knob_y, knob_radius, trim_db, track, fx_index, track_guid)
 local db_text = string.format("%.1f", trim_db)
 local db_w = r.ImGui_CalcTextSize(ctx, db_text)
 r.ImGui_DrawList_AddTextEx(draw_list, nil, 8, x + width - db_w - 3, y + header_height + 4, text_color, db_text)
 r.ImGui_DrawList_AddRect(draw_list, x, y, x + width, y + trim_height, 0x444444FF, 3, 0, 1)
 r.ImGui_SetCursorScreenPos(ctx, x, y)
 return trim_height
end

local EQ = {
 fx_cache = {}
}

function EQ.FindFX(track, track_guid)
 return FindChannelStripFX(track, track_guid)
end

function EQ.InsertFX(track, track_guid)
 local fx_index = InsertChannelStripFX(track, track_guid)
 return fx_index
end

function EQ.Reset(track, fx_index)
 if fx_index < 0 then return end
 r.TrackFX_SetParam(track, fx_index, STRIP_OFFSET.EQ + 0, 80)
 r.TrackFX_SetParam(track, fx_index, STRIP_OFFSET.EQ + 1, 0)
 r.TrackFX_SetParam(track, fx_index, STRIP_OFFSET.EQ + 2, 200)
 r.TrackFX_SetParam(track, fx_index, STRIP_OFFSET.EQ + 3, 0)
 r.TrackFX_SetParam(track, fx_index, STRIP_OFFSET.EQ + 4, 1)
 r.TrackFX_SetParam(track, fx_index, STRIP_OFFSET.EQ + 5, 800)
 r.TrackFX_SetParam(track, fx_index, STRIP_OFFSET.EQ + 6, 0)
 r.TrackFX_SetParam(track, fx_index, STRIP_OFFSET.EQ + 7, 1)
 r.TrackFX_SetParam(track, fx_index, STRIP_OFFSET.EQ + 8, 3000)
 r.TrackFX_SetParam(track, fx_index, STRIP_OFFSET.EQ + 9, 0)
 r.TrackFX_SetParam(track, fx_index, STRIP_OFFSET.EQ + 10, 1)
 r.TrackFX_SetParam(track, fx_index, STRIP_OFFSET.EQ + 11, 8000)
 r.TrackFX_SetParam(track, fx_index, STRIP_OFFSET.EQ + 12, 0)
 r.TrackFX_SetParam(track, fx_index, STRIP_OFFSET.EQ + 13, 1)
 r.TrackFX_SetParam(track, fx_index, STRIP_OFFSET.EQ + 14, 12000)
 r.TrackFX_SetParam(track, fx_index, STRIP_OFFSET.EQ + 15, 0)
 r.TrackFX_SetParam(track, fx_index, STRIP_OFFSET.EQ + 16, 0)
 r.TrackFX_SetParam(track, fx_index, STRIP_OFFSET.EQ + 17, 0)
 r.TrackFX_SetParam(track, fx_index, STRIP_OFFSET.EQ + 18, 0.7)
end

function EQ.DrawKnob(ctx, draw_list, x, y, radius, value, min_val, max_val, is_bipolar, knob_color, id_suffix, track, fx_index, param_idx)
 local norm_val = (value - min_val) / (max_val - min_val)
 local track_color = settings.simple_mixer_eq_knob_track_color or 0x555555FF
 DrawStyledKnob(ctx, draw_list, x, y, radius, norm_val, knob_color, is_bipolar, settings.simple_mixer_knob_style, track_color)
 r.ImGui_SetCursorScreenPos(ctx, x - radius, y - radius)
 r.ImGui_InvisibleButton(ctx, "##eq_" .. id_suffix .. "_" .. tostring(track), radius * 2, radius * 2)
 local is_hovered = r.ImGui_IsItemHovered(ctx)
 local is_active = r.ImGui_IsItemActive(ctx)
 if is_active then
  local _, dy = r.ImGui_GetMouseDragDelta(ctx, 0)
  if math.abs(dy) > 0 then
   local range = max_val - min_val
   local new_val = math.max(min_val, math.min(max_val, value - dy * range * 0.005))
   local new_norm = (new_val - min_val) / (max_val - min_val)
   r.TrackFX_SetParamNormalized(track, fx_index, param_idx, new_norm)
   r.ImGui_ResetMouseDragDelta(ctx, 0)
  end
 end
 local is_rclicked = r.ImGui_IsItemClicked(ctx, 1)
 return is_hovered, is_active, is_rclicked
end

function EQ.DrawBandRow(ctx, draw_list, x, y, width, row_height, track, fx_index, freq_param, gain_param, q_param, label, bg_color, freq_min, freq_max, show_divider, type_param)
 local freq_val = r.TrackFX_GetParam(track, fx_index, freq_param)
 local gain_val = r.TrackFX_GetParam(track, fx_index, gain_param)
 local q_val = r.TrackFX_GetParam(track, fx_index, q_param)
 local is_bell = true
 local has_type_toggle = type_param ~= nil
 if has_type_toggle then
  is_bell = r.TrackFX_GetParam(track, fx_index, type_param) > 0.5
 end
 local knob_radius = 7
 local label_height = 12
 local knob_color = settings.simple_mixer_eq_knob_color or 0xCCCCCCFF
 local text_color = settings.simple_mixer_eq_text_color or 0xAAAAAAFF
 r.ImGui_DrawList_AddRectFilled(draw_list, x + 2, y + 1, x + width - 2, y + row_height - 1, bg_color, 2)
 if settings.simple_mixer_eq_show_labels ~= false then
  r.ImGui_DrawList_AddTextEx(draw_list, nil, 7, x + 3, y + 2, text_color, label)
 end
 local knob_y = y + label_height + knob_radius + 4
 local freq_hov, freq_act, gain_hov, gain_act, q_hov, q_act
 if has_type_toggle then
  local btn_width = 16
  local btn_height = 10
  local led_size = 3
  local led_x = x + width - btn_width - led_size - 7
  local led_y = y + 2 + btn_height / 2
  local btn_x = x + width - btn_width - 3
  local btn_y = y + 2
  local btn_bg_color = is_bell and 0xAAAAAAFF or 0xFFFFFFFF
  local btn_text_color = 0x000000FF
  if is_bell then
   r.ImGui_DrawList_AddCircleFilled(draw_list, led_x, led_y, led_size, 0x00FF00FF, 12)
   r.ImGui_DrawList_AddCircle(draw_list, led_x, led_y, led_size, 0x00AA0088, 12, 1)
  else
   r.ImGui_DrawList_AddCircleFilled(draw_list, led_x, led_y, led_size, 0x444444FF, 12)
  end
  r.ImGui_DrawList_AddRectFilled(draw_list, btn_x + 1, btn_y + 1, btn_x + btn_width + 1, btn_y + btn_height + 1, 0x00000044, 2)
  r.ImGui_DrawList_AddRectFilled(draw_list, btn_x, btn_y, btn_x + btn_width, btn_y + btn_height, btn_bg_color, 2)
  r.ImGui_DrawList_AddRect(draw_list, btn_x, btn_y, btn_x + btn_width, btn_y + btn_height, 0x00000088, 2, 0, 1)
  local display_text = "Bell"
  local font_size = 7
  local text_w = r.ImGui_CalcTextSize(ctx, display_text)
  local scaled_text_w = text_w * (font_size / r.ImGui_GetFontSize(ctx))
  local text_x = btn_x + (btn_width - scaled_text_w) / 2
  local text_y = btn_y + (btn_height - font_size) / 2
  r.ImGui_DrawList_AddTextEx(draw_list, nil, font_size, text_x, text_y, btn_text_color, display_text)
  r.ImGui_SetCursorScreenPos(ctx, led_x - led_size, btn_y)
  local total_btn_width = btn_width + led_size + 2
  if r.ImGui_InvisibleButton(ctx, "##bell_" .. label, total_btn_width, btn_height) then
   r.TrackFX_SetParam(track, fx_index, type_param, is_bell and 0 or 1)
  end
  if r.ImGui_IsItemHovered(ctx) then
   r.ImGui_SetTooltip(ctx, is_bell and "Bell (click for Shelf)" or "Shelf (click for Bell)")
  end
  if r.ImGui_IsItemClicked(ctx, 1) then
   local shelf_q = r.TrackFX_GetParam(track, fx_index, STRIP_OFFSET.EQ + 18)
   if shelf_q < 0.3 then shelf_q = 0.7 end
   mixer_state.shelf_q_popup = { track = track, fx_index = fx_index, shelf_q = shelf_q, needs_open = true }
  end
  local q_min = 0.3
  local q_max = 3
  if is_bell then
   local col_width = width / 3
   local freq_x = x + col_width * 0.5
   local gain_x = x + col_width * 1.5
   local q_x = x + col_width * 2.5
   freq_hov, freq_act = EQ.DrawKnob(ctx, draw_list, freq_x, knob_y, knob_radius, freq_val, freq_min, freq_max, false, knob_color, label .. "_freq", track, fx_index, freq_param)
   gain_hov, gain_act = EQ.DrawKnob(ctx, draw_list, gain_x, knob_y, knob_radius, gain_val, -12, 12, true, knob_color, label .. "_gain", track, fx_index, gain_param)
   q_hov, q_act = EQ.DrawKnob(ctx, draw_list, q_x, knob_y, knob_radius, q_val, q_min, q_max, false, knob_color, label .. "_q", track, fx_index, q_param)
  else
   local col_width = width / 2
   local freq_x = x + col_width * 0.5
   local gain_x = x + col_width * 1.5
   freq_hov, freq_act = EQ.DrawKnob(ctx, draw_list, freq_x, knob_y, knob_radius, freq_val, freq_min, freq_max, false, knob_color, label .. "_freq", track, fx_index, freq_param)
   gain_hov, gain_act = EQ.DrawKnob(ctx, draw_list, gain_x, knob_y, knob_radius, gain_val, -12, 12, true, knob_color, label .. "_gain", track, fx_index, gain_param)
  end
 else
  local q_min = 0.3
  local q_max = 3
  local col_width = width / 3
  local freq_x = x + col_width * 0.5
  local gain_x = x + col_width * 1.5
  local q_x = x + col_width * 2.5
  freq_hov, freq_act = EQ.DrawKnob(ctx, draw_list, freq_x, knob_y, knob_radius, freq_val, freq_min, freq_max, false, knob_color, label .. "_freq", track, fx_index, freq_param)
  gain_hov, gain_act = EQ.DrawKnob(ctx, draw_list, gain_x, knob_y, knob_radius, gain_val, -12, 12, true, knob_color, label .. "_gain", track, fx_index, gain_param)
  q_hov, q_act = EQ.DrawKnob(ctx, draw_list, q_x, knob_y, knob_radius, q_val, q_min, q_max, false, knob_color, label .. "_q", track, fx_index, q_param)
 end
 if show_divider then
  r.ImGui_DrawList_AddLine(draw_list, x + 4, y + row_height - 1, x + width - 4, y + row_height - 1, 0x333333FF, 1)
 end
 if freq_hov or freq_act then
  r.ImGui_SetTooltip(ctx, string.format("%s Freq: %.0f Hz", label, freq_val))
 elseif gain_hov or gain_act then
  r.ImGui_SetTooltip(ctx, string.format("%s Gain: %.1f dB", label, gain_val))
 elseif q_hov or q_act then
  r.ImGui_SetTooltip(ctx, string.format("%s Q: %.2f", label, q_val))
 end
end

function EQ.DrawFilterRow(ctx, draw_list, x, y, width, row_height, track, fx_index)
 local hpf_freq = r.TrackFX_GetParam(track, fx_index, STRIP_OFFSET.EQ + 0)
 local hpf_on = r.TrackFX_GetParam(track, fx_index, STRIP_OFFSET.EQ + 1)
 local lpf_freq = r.TrackFX_GetParam(track, fx_index, STRIP_OFFSET.EQ + 14)
 local lpf_on = r.TrackFX_GetParam(track, fx_index, STRIP_OFFSET.EQ + 15)
 local knob_radius = 8
 local knob_color = settings.simple_mixer_eq_knob_color or 0xCCCCCCFF
 local text_color = settings.simple_mixer_eq_text_color or 0xAAAAAAFF
 local off_color = 0x555555FF
 local col_width = width / 2
 local hpf_knob_x = x + col_width * 0.5
 local lpf_knob_x = x + col_width * 1.5
 local knob_y = y + 14 + knob_radius
 local hpf_btn_color = hpf_on > 0.5 and knob_color or off_color
 local lpf_btn_color = lpf_on > 0.5 and knob_color or off_color
 local hpf_text_color = hpf_on > 0.5 and text_color or off_color
 local lpf_text_color = lpf_on > 0.5 and text_color or off_color
 if settings.simple_mixer_eq_show_labels ~= false then
  r.ImGui_DrawList_AddTextEx(draw_list, nil, 7, hpf_knob_x - 7, y + 2, hpf_text_color, "HPF")
  r.ImGui_DrawList_AddTextEx(draw_list, nil, 7, lpf_knob_x - 7, y + 2, lpf_text_color, "LPF")
 end
 local hpf_hov, hpf_act, hpf_rclick = EQ.DrawKnob(ctx, draw_list, hpf_knob_x, knob_y, knob_radius, hpf_freq, 20, 500, false, hpf_btn_color, "hpf", track, fx_index, STRIP_OFFSET.EQ + 0)
 local lpf_hov, lpf_act, lpf_rclick = EQ.DrawKnob(ctx, draw_list, lpf_knob_x, knob_y, knob_radius, lpf_freq, 4000, 20000, false, lpf_btn_color, "lpf", track, fx_index, STRIP_OFFSET.EQ + 14)
 if hpf_rclick then
  r.TrackFX_SetParamNormalized(track, fx_index, STRIP_OFFSET.EQ + 1, hpf_on > 0.5 and 0 or 1)
 end
 if lpf_rclick then
  r.TrackFX_SetParamNormalized(track, fx_index, STRIP_OFFSET.EQ + 15, lpf_on > 0.5 and 0 or 1)
 end
 if hpf_hov or hpf_act then
  r.ImGui_SetTooltip(ctx, string.format("HPF: %.0f Hz%s", hpf_freq, hpf_on > 0.5 and "" or " (OFF)"))
 elseif lpf_hov or lpf_act then
  r.ImGui_SetTooltip(ctx, string.format("LPF: %.0f Hz%s", lpf_freq, lpf_on > 0.5 and "" or " (OFF)"))
 end
end

function EQ.DrawModule(ctx, draw_list, x, y, width, height, track_guid, track)
 if not settings.simple_mixer_show_eq or not track then return 0 end
 local fx_index = EQ.FindFX(track, track_guid)
 local has_eq = fx_index >= 0
 local bg_color = settings.simple_mixer_eq_bg_color or 0x1A2A2AFF
 local header_color = settings.simple_mixer_eq_header_color or 0x3A5A5AFF
 local text_color = settings.simple_mixer_eq_text_color or 0xAAAAAAFF
 local header_height, row_height, filter_row_height = 14, 32, 34
 local eq_height = header_height + 4 + (row_height * 4) + filter_row_height + 4
 r.ImGui_DrawList_AddRectFilled(draw_list, x, y, x + width, y + eq_height, bg_color, 3)
 r.ImGui_DrawList_AddCircleFilled(draw_list, x + width * 0.75, y + eq_height * 0.3, width * 0.35, 0xFFFFFF04, 24)
 r.ImGui_DrawList_AddRectFilled(draw_list, x, y, x + width, y + header_height, header_color, 3, r.ImGui_DrawFlags_RoundCornersTop())
 local header_w = r.ImGui_CalcTextSize(ctx, "EQ")
 r.ImGui_DrawList_AddText(draw_list, x + (width - header_w) / 2, y, 0xFFFFFFFF, "EQ")
 if has_eq then
  r.ImGui_SetCursorScreenPos(ctx, x + 12, y)
  if r.ImGui_InvisibleButton(ctx, "##eq_header_" .. track_guid, width - 24, header_height) then
   local hwnd = r.TrackFX_GetFloatingWindow(track, fx_index)
   r.TrackFX_Show(track, fx_index, hwnd and 2 or 3)
  end
  if r.ImGui_IsItemClicked(ctx, 1) then
   r.ImGui_OpenPopup(ctx, "##eq_reset_menu_" .. track_guid)
  end
  if r.ImGui_BeginPopup(ctx, "##eq_reset_menu_" .. track_guid) then
   if r.ImGui_MenuItem(ctx, "Reset EQ") then
    EQ.Reset(track, fx_index)
   end
   r.ImGui_EndPopup(ctx)
  end
  local btn_size = 8
  local plugin_enabled = r.TrackFX_GetEnabled(track, fx_index)
  local is_enabled = plugin_enabled and r.TrackFX_GetParam(track, fx_index, STRIP_OFFSET.EQ_BYPASS) == 1
  local btn_color = is_enabled and (settings.simple_mixer_eq_active_color or 0x00AA88FF) or (settings.simple_mixer_eq_bypass_color or 0x666600FF)
  r.ImGui_DrawList_AddRectFilled(draw_list, x + width - 10, y + 2, x + width - 2, y + 10, btn_color, 2)
  r.ImGui_SetCursorScreenPos(ctx, x + width - 10, y + 2)
  if r.ImGui_InvisibleButton(ctx, "##eq_bypass_" .. track_guid, btn_size, btn_size) then
   r.TrackFX_SetParamNormalized(track, fx_index, STRIP_OFFSET.EQ_BYPASS, is_enabled and 0 or 1)
  end
  r.ImGui_DrawList_AddRectFilled(draw_list, x + 2, y + 2, x + 10, y + 10, 0x333333FF, 2)
  r.ImGui_SetCursorScreenPos(ctx, x + 2, y + 2)
  if r.ImGui_InvisibleButton(ctx, "##eq_remove_" .. track_guid, btn_size, btn_size) then
   r.TrackFX_Delete(track, fx_index)
   EQ.fx_cache[track_guid] = nil
  end
 end
 if not has_eq then
  local add_w = r.ImGui_CalcTextSize(ctx, "+ Add EQ")
  r.ImGui_DrawList_AddText(draw_list, x + (width - add_w) / 2, y + eq_height / 2 - 6, text_color, "+ Add EQ")
  r.ImGui_SetCursorScreenPos(ctx, x, y + header_height)
  if r.ImGui_InvisibleButton(ctx, "##add_eq_" .. track_guid, width, eq_height - header_height) then
   EQ.InsertFX(track, track_guid)
  end
  r.ImGui_DrawList_AddRect(draw_list, x, y, x + width, y + eq_height, 0x444444FF, 3, 0, 1)
  r.ImGui_SetCursorScreenPos(ctx, x, y)
  return eq_height
 end
 local hf_bg = settings.simple_mixer_eq_hf_bg or 0x6666FF18
 local hmf_bg = settings.simple_mixer_eq_hmf_bg or 0x66FF6618
 local lmf_bg = settings.simple_mixer_eq_lmf_bg or 0xFFAA4418
 local lf_bg = settings.simple_mixer_eq_lf_bg or 0xFF666618
 local row_start = y + header_height + 4
 EQ.DrawBandRow(ctx, draw_list, x, row_start, width, row_height, track, fx_index, STRIP_OFFSET.EQ + 11, STRIP_OFFSET.EQ + 12, STRIP_OFFSET.EQ + 13, "HF", hf_bg, 2000, 16000, true, STRIP_OFFSET.EQ + 17)
 EQ.DrawBandRow(ctx, draw_list, x, row_start + row_height, width, row_height, track, fx_index, STRIP_OFFSET.EQ + 8, STRIP_OFFSET.EQ + 9, STRIP_OFFSET.EQ + 10, "HMF", hmf_bg, 1000, 8000, true, nil)
 EQ.DrawBandRow(ctx, draw_list, x, row_start + row_height * 2, width, row_height, track, fx_index, STRIP_OFFSET.EQ + 5, STRIP_OFFSET.EQ + 6, STRIP_OFFSET.EQ + 7, "LMF", lmf_bg, 200, 2000, true, nil)
 EQ.DrawBandRow(ctx, draw_list, x, row_start + row_height * 3, width, row_height, track, fx_index, STRIP_OFFSET.EQ + 2, STRIP_OFFSET.EQ + 3, STRIP_OFFSET.EQ + 4, "LF", lf_bg, 40, 600, false, STRIP_OFFSET.EQ + 16)
 local filter_y = row_start + row_height * 4
 r.ImGui_DrawList_AddLine(draw_list, x + 4, filter_y, x + width - 4, filter_y, 0x444444FF, 1)
 EQ.DrawFilterRow(ctx, draw_list, x, filter_y + 2, width, filter_row_height, track, fx_index)
 r.ImGui_DrawList_AddRect(draw_list, x, y, x + width, y + eq_height, 0x444444FF, 3, 0, 1)
 r.ImGui_SetCursorScreenPos(ctx, x, y)
 return eq_height
end

function EQ.DrawShelfQPopup(ctx)
 if not mixer_state.shelf_q_popup then return end
 local popup_id = "##shelf_q_popup"
 if mixer_state.shelf_q_popup.needs_open then
  r.ImGui_OpenPopup(ctx, popup_id)
  mixer_state.shelf_q_popup.needs_open = false
 end
 if r.ImGui_BeginPopup(ctx, popup_id) then
  r.ImGui_Text(ctx, "Shelf Q:")
  r.ImGui_SetNextItemWidth(ctx, 100)
  local changed, new_val = r.ImGui_SliderDouble(ctx, "##shelf_q_slider", mixer_state.shelf_q_popup.shelf_q, 0.3, 2.0, "%.2f")
  if changed then
   mixer_state.shelf_q_popup.shelf_q = new_val
   r.TrackFX_SetParam(mixer_state.shelf_q_popup.track, mixer_state.shelf_q_popup.fx_index, STRIP_OFFSET.EQ + 18, new_val)
  end
  if r.ImGui_Button(ctx, "Reset##shelf_q") then
   r.TrackFX_SetParam(mixer_state.shelf_q_popup.track, mixer_state.shelf_q_popup.fx_index, STRIP_OFFSET.EQ + 18, 0.7)
   mixer_state.shelf_q_popup.shelf_q = 0.7
  end
  r.ImGui_EndPopup(ctx)
 else
  mixer_state.shelf_q_popup = nil
 end
end

local InputSelector = {
 GetTypeAndChannel = function(track)
  local rec_input = r.GetMediaTrackInfo_Value(track, "I_RECINPUT")
  rec_input = math.floor(rec_input)
  if rec_input < 0 then return "none", 0, rec_input, 0 end
  if rec_input >= 4096 then
   local midi_channel = rec_input & 31
   local midi_device = (rec_input >> 5) & 127
   return "midi", midi_channel, rec_input, midi_device
  end
  local is_stereo = (rec_input & 1024) ~= 0
  local channel = rec_input & 1023
  if is_stereo then
   return "stereo", channel, rec_input, 0
  else
   return "mono", channel, rec_input, 0
  end
 end,
 SetInput = function(track, input_type, channel, midi_device)
  local rec_input = -1
  if input_type == "mono" then
   rec_input = channel
  elseif input_type == "stereo" then
   rec_input = 1024 + channel
  elseif input_type == "midi" then
   rec_input = 4096 + ((midi_device or 63) << 5) + channel
  end
  r.SetMediaTrackInfo_Value(track, "I_RECINPUT", rec_input)
 end,
 GetAudioInputs = function()
  local inputs = {}
  table.insert(inputs, {channel = 0, name = "Not connected 1"})
  table.insert(inputs, {channel = 1, name = "Not connected 2"})
  local retval, num_str = r.GetAudioDeviceInfo("NINPUTS", "")
  local num_hw = retval and tonumber(num_str) or 0
  for i = 0, num_hw - 1 do
   local ret, name = r.GetAudioDeviceInfo("INPUT" .. i, "")
   local input_name = (ret and name and name ~= "") and name or ("Input " .. (i + 1))
   table.insert(inputs, {channel = i + 2, name = input_name})
  end
  return inputs
 end,
 Draw = function(self, ctx, track)
  if not track then return end
  local current_type, current_channel, _, current_midi_device = self.GetTypeAndChannel(track)
  local audio_inputs = self.GetAudioInputs()
  r.ImGui_Indent(ctx, 5)
  local type_names, type_values = {"No Input", "Mono", "Stereo", "MIDI"}, {"none", "mono", "stereo", "midi"}
  local current_type_idx = 0
  for i, v in ipairs(type_values) do if v == current_type then current_type_idx = i - 1 break end end
  r.ImGui_Text(ctx, "Type:")
  r.ImGui_SameLine(ctx, 60)
  r.ImGui_SetNextItemWidth(ctx, -1)
  local type_changed, new_type_idx = r.ImGui_Combo(ctx, "##InputType", current_type_idx, table.concat(type_names, "\0") .. "\0")
  if type_changed then 
   local new_type = type_values[new_type_idx + 1]
   if new_type == "mono" or new_type == "stereo" then
    self.SetInput(track, new_type, audio_inputs[1] and audio_inputs[1].channel or 0, 0)
   else
    self.SetInput(track, new_type, 0, 63) 
   end
  end
  if current_type == "mono" then
   r.ImGui_Text(ctx, "Ch:")
   r.ImGui_SameLine(ctx, 60)
   r.ImGui_SetNextItemWidth(ctx, -1)
   local channel_names, channel_values = {}, {}
   for _, inp in ipairs(audio_inputs) do 
    table.insert(channel_names, inp.name)
    table.insert(channel_values, inp.channel)
   end
   if #channel_names == 0 then channel_names = {"No inputs"} channel_values = {0} end
   local current_idx = 0
   for i, ch in ipairs(channel_values) do if ch == current_channel then current_idx = i - 1 break end end
   local channel_changed, new_idx = r.ImGui_Combo(ctx, "##MonoChannel", current_idx, table.concat(channel_names, "\0") .. "\0")
   if channel_changed then self.SetInput(track, "mono", channel_values[new_idx + 1], 0) end
  elseif current_type == "stereo" then
   r.ImGui_Text(ctx, "Ch:")
   r.ImGui_SameLine(ctx, 60)
   r.ImGui_SetNextItemWidth(ctx, -1)
   local stereo_pairs, stereo_values = {}, {}
   for i = 1, #audio_inputs, 2 do
    if audio_inputs[i + 1] then
     table.insert(stereo_pairs, audio_inputs[i].name .. " / " .. audio_inputs[i + 1].name)
     table.insert(stereo_values, audio_inputs[i].channel)
    end
   end
   if #stereo_pairs == 0 then stereo_pairs = {"No pairs"} stereo_values = {0} end
   local current_idx = 0
   for i, ch in ipairs(stereo_values) do if ch == current_channel then current_idx = i - 1 break end end
   local pair_changed, new_idx = r.ImGui_Combo(ctx, "##StereoPair", current_idx, table.concat(stereo_pairs, "\0") .. "\0")
   if pair_changed then self.SetInput(track, "stereo", stereo_values[new_idx + 1], 0) end
  elseif current_type == "midi" then
   r.ImGui_Text(ctx, "Dev:")
   r.ImGui_SameLine(ctx, 60)
   r.ImGui_SetNextItemWidth(ctx, -1)
   local midi_devices, device_ids = {"All"}, {63}
   local num_midi = r.GetNumMIDIInputs()
   for i = 0, num_midi - 1 do
    local retval, name = r.GetMIDIInputName(i, "")
    if retval then 
     table.insert(midi_devices, (name and name ~= "") and name or ("MIDI Device " .. (i + 1)))
     table.insert(device_ids, i)
    end
   end
   local current_device_idx = 0
   for i, dev_id in ipairs(device_ids) do 
    if dev_id == current_midi_device then 
     current_device_idx = i - 1 
     break 
    end 
   end
   local device_changed, new_device_idx = r.ImGui_Combo(ctx, "##MIDIDevice", current_device_idx, table.concat(midi_devices, "\0") .. "\0")
   if device_changed then self.SetInput(track, "midi", current_channel, device_ids[new_device_idx + 1] or 63) end
   r.ImGui_Text(ctx, "Ch:")
   r.ImGui_SameLine(ctx, 60)
   r.ImGui_SetNextItemWidth(ctx, -1)
   local midi_channels = {"All"}
   for i = 1, 16 do table.insert(midi_channels, tostring(i)) end
   local current_midi_ch = current_channel > 16 and 0 or current_channel
   local ch_changed, new_ch = r.ImGui_Combo(ctx, "##MIDIChannel", current_midi_ch, table.concat(midi_channels, "\0") .. "\0")
   if ch_changed then self.SetInput(track, "midi", new_ch, current_midi_device) end
  end
  r.ImGui_Unindent(ctx, 5)
 end
}

local OutputSelector = {
 GetCurrentOutput = function(track)
  local main_send = r.GetMediaTrackInfo_Value(track, "B_MAINSEND")
  local main_send_offs = math.floor(r.GetMediaTrackInfo_Value(track, "C_MAINSEND_OFFS"))
  return main_send == 1, main_send_offs
 end,
 SetOutput = function(track, send_to_master, channel_offset)
  r.SetMediaTrackInfo_Value(track, "B_MAINSEND", send_to_master and 1 or 0)
  r.SetMediaTrackInfo_Value(track, "C_MAINSEND_OFFS", channel_offset or 0)
 end,
 GetHardwareOutputs = function()
  local outputs = {}
  local retval, num_str = r.GetAudioDeviceInfo("NOUTPUTS", "")
  local num_hw = retval and tonumber(num_str) or 0
  for i = 0, math.max(1, num_hw - 1), 2 do
   local ret1, name1 = r.GetAudioDeviceInfo("OUTPUT" .. i, "")
   local ret2, name2 = r.GetAudioDeviceInfo("OUTPUT" .. (i + 1), "")
   local out_name1 = (ret1 and name1 and name1 ~= "") and name1 or ("Output " .. (i + 1))
   local out_name2 = (ret2 and name2 and name2 ~= "") and name2 or ("Output " .. (i + 2))
   table.insert(outputs, {channel = i, name = out_name1 .. " / " .. out_name2})
  end
  if #outputs == 0 then
   table.insert(outputs, {channel = 0, name = "Output 1 / 2"})
  end
  return outputs
 end,
 Draw = function(self, ctx, track)
  if not track then return end
  local sends_to_master, channel_offset = self.GetCurrentOutput(track)
  local hw_outputs = self.GetHardwareOutputs()
  r.ImGui_Indent(ctx, 5)
  local master_changed, new_master = r.ImGui_Checkbox(ctx, "Master/Parent", sends_to_master)
  if master_changed then
   self.SetOutput(track, new_master, channel_offset)
  end
  r.ImGui_Text(ctx, "HW Out:")
  r.ImGui_SameLine(ctx, 60)
  r.ImGui_SetNextItemWidth(ctx, -1)
  local output_names, output_values = {}, {}
  table.insert(output_names, "None")
  table.insert(output_values, -1)
  for _, out in ipairs(hw_outputs) do
   table.insert(output_names, out.name)
   table.insert(output_values, out.channel)
  end
  local num_sends = r.GetTrackNumSends(track, 1)
  local current_hw_idx = 0
  for s = 0, num_sends - 1 do
   local dest_chan = r.GetTrackSendInfo_Value(track, 1, s, "I_DSTCHAN")
   for i, ch in ipairs(output_values) do
    if ch == dest_chan then current_hw_idx = i - 1 break end
   end
  end
  local hw_changed, new_hw_idx = r.ImGui_Combo(ctx, "##HWOutput", current_hw_idx, table.concat(output_names, "\0") .. "\0")
  if hw_changed then
   for s = r.GetTrackNumSends(track, 1) - 1, 0, -1 do
    r.RemoveTrackSend(track, 1, s)
   end
   local new_channel = output_values[new_hw_idx + 1]
   if new_channel >= 0 then
    local send_idx = r.CreateTrackSend(track, nil)
    r.SetTrackSendInfo_Value(track, 1, 0, "I_DSTCHAN", new_channel)
   end
  end
  r.ImGui_Unindent(ctx, 5)
 end
}

local RecordModeSelector = {
 modes = {
  {name = "Input (audio or MIDI)", value = 0},
  {name = "Disable (input monitoring only)", value = 2},
 },
 midi_modes = {
  {name = "MIDI overdub", value = 7},
  {name = "MIDI replace", value = 8},
  {name = "MIDI touch-replace", value = 9},
  {name = "MIDI latch-replace", value = 16},
 },
 output_types = {
  {name = "Multichannel out", value = 1, multichannel = true},
  {name = "Stereo out", value = 1},
  {name = "Stereo out w/latency comp", value = 3},
  {name = "Mono out", value = 5},
  {name = "Mono out w/latency comp", value = 6},
  {name = "MIDI output", value = 4},
 },
 output_flags = {
  {name = "Post-Fader (default)", value = 0},
  {name = "Pre-FX", value = 1},
  {name = "Post-FX/Pre-Fader", value = 2},
 },
 GetRecordMode = function(track) return math.floor(r.GetMediaTrackInfo_Value(track, "I_RECMODE")) end,
 SetRecordMode = function(track, mode) r.SetMediaTrackInfo_Value(track, "I_RECMODE", mode) end,
 GetRecModeFlags = function(track) return math.floor(r.GetMediaTrackInfo_Value(track, "I_RECMODE_FLAGS")) end,
 SetRecModeFlags = function(track, flags) r.SetMediaTrackInfo_Value(track, "I_RECMODE_FLAGS", flags) end,
 IsOutputMode = function(mode) return mode == 1 or mode == 3 or mode == 4 or mode == 5 or mode == 6 end,
 GetModeName = function(self, mode, track)
  for _, m in ipairs(self.modes) do if m.value == mode then return m.name end end
  for _, m in ipairs(self.midi_modes) do if m.value == mode then return m.name end end
  for _, m in ipairs(self.output_types) do
   if m.value == mode then 
    if track then
     local flags = self.GetRecModeFlags(track)
     local flag_mode = flags % 4
     for _, f in ipairs(self.output_flags) do
      if f.value == flag_mode then return m.name .. " (" .. f.name:gsub(" %(default%)", "") .. ")" end
     end
    end
    return m.name
   end
  end
  return "Mode " .. mode
 end,
 Draw = function(self, ctx, track)
  if not track then return end
  local current_mode = self.GetRecordMode(track)
  local current_name = self:GetModeName(current_mode, track)
  r.ImGui_Indent(ctx, 5)
  r.ImGui_Text(ctx, "Mode:")
  r.ImGui_SameLine(ctx, 50)
  r.ImGui_SetNextItemWidth(ctx, -1)
  if r.ImGui_BeginCombo(ctx, "##RecMode", current_name) then
   for _, m in ipairs(self.modes) do
    local is_selected = (current_mode == m.value)
    if r.ImGui_Selectable(ctx, m.name, is_selected) then self.SetRecordMode(track, m.value) end
   end
   if r.ImGui_BeginMenu(ctx, "MIDI overdub/replace") then
    for _, m in ipairs(self.midi_modes) do
     local is_selected = (current_mode == m.value)
     if r.ImGui_MenuItem(ctx, m.name, nil, is_selected) then self.SetRecordMode(track, m.value) end
    end
    r.ImGui_EndMenu(ctx)
   end
   if r.ImGui_BeginMenu(ctx, "Record: output") then
    local current_flags = self.GetRecModeFlags(track)
    local current_flag_mode = current_flags % 4
    for _, m in ipairs(self.output_types) do
     local is_selected = (current_mode == m.value)
     if r.ImGui_MenuItem(ctx, m.name, nil, is_selected) then self.SetRecordMode(track, m.value) end
    end
    if self.IsOutputMode(current_mode) then
     r.ImGui_Separator(ctx)
     r.ImGui_Text(ctx, "Output mode:")
     for _, f in ipairs(self.output_flags) do
      local is_selected = (current_flag_mode == f.value)
      if r.ImGui_MenuItem(ctx, f.name, nil, is_selected) then
       local new_flags = (current_flags - current_flag_mode) + f.value
       self.SetRecModeFlags(track, new_flags)
      end
     end
    end
    r.ImGui_EndMenu(ctx)
   end
   r.ImGui_EndCombo(ctx)
  end
  r.ImGui_Unindent(ctx, 5)
 end
}

local function GetPostFaderPeakDB(track)
 if not track then return -60, -60, -60 end
 local peak_l = r.Track_GetPeakInfo(track, 0)
 local peak_r = r.Track_GetPeakInfo(track, 1)
 local peak_combined = math.max(peak_l, peak_r)
 local db_l = peak_l > 0.0000001 and 20 * math.log(peak_l, 10) or -60
 local db_r = peak_r > 0.0000001 and 20 * math.log(peak_r, 10) or -60
 local db_combined = peak_combined > 0.0000001 and 20 * math.log(peak_combined, 10) or -60
 db_l = math.max(-60, math.min(6, db_l))
 db_r = math.max(-60, math.min(6, db_r))
 db_combined = math.max(-60, math.min(6, db_combined))
 return db_l, db_r, db_combined
end

local function EnsureVUJSFX(track)
 local track_guid = r.GetTrackGUID(track)
 if not vu_gmem_attached then
  r.gmem_attach("TK_VU_Meters")
  vu_gmem_attached = true
 end
 if vu_jsfx_cache[track_guid] then
  local cached = vu_jsfx_cache[track_guid]
  if cached.fx_index >= 0 then
   local retval, fx_name = r.TrackFX_GetFXName(track, cached.fx_index, "")
   if retval then
    local name_lower = fx_name:lower()
    if name_lower:find("tk_vu_meter") or name_lower:find("tk vu meter") then
     return cached.fx_index, cached.slot_id
    end
   end
  end
  vu_jsfx_cache[track_guid] = nil
 end
 local fx_count = r.TrackFX_GetCount(track)
 for i = 0, fx_count - 1 do
  local retval, fx_name = r.TrackFX_GetFXName(track, i, "")
  if retval then
   local name_lower = fx_name:lower()
   if name_lower:find("tk_vu_meter") or name_lower:find("tk vu meter") then
    local slot_id = vu_track_slots[track_guid]
    if not slot_id then
     vu_track_slot_counter = vu_track_slot_counter + 1
     slot_id = vu_track_slot_counter
     vu_track_slots[track_guid] = slot_id
     r.TrackFX_SetParam(track, i, 0, slot_id)
    end
    vu_jsfx_cache[track_guid] = {fx_index = i, slot_id = slot_id}
    return i, slot_id
   end
  end
 end
 local fx_index = r.TrackFX_AddByName(track, "JS:TK_VU_Meter", false, -1)
 if fx_index >= 0 then
  vu_track_slot_counter = vu_track_slot_counter + 1
  local slot_id = vu_track_slot_counter
  vu_track_slots[track_guid] = slot_id
  r.TrackFX_SetParam(track, fx_index, 0, slot_id)
  r.TrackFX_SetEnabled(track, fx_index, true)
  r.TrackFX_Show(track, fx_index, 0)
  vu_jsfx_cache[track_guid] = {fx_index = fx_index, slot_id = slot_id}
  return fx_index, slot_id
 end
 return -1, 0
end

local function GetPreFaderPeakDB(track, slot_id)
 if not track or slot_id <= 0 then return -60, -60, -60 end
 local db_l = r.gmem_read(slot_id * 3)
 local db_r = r.gmem_read(slot_id * 3 + 1)
 local db_combined = r.gmem_read(slot_id * 3 + 2)
 if db_l == 0 and db_r == 0 and db_combined == 0 then return -60, -60, -60 end
 return db_l, db_r, db_combined
end

local function GetPeakDB(track, track_guid)
 local use_pre_fader = settings.simple_mixer_vu_pre_fader
 if use_pre_fader then
  local data = simple_mixer_vu_data[track_guid]
  local slot_id = data and data.slot_id or 0
  if slot_id <= 0 then
   local fx_index
   fx_index, slot_id = EnsureVUJSFX(track)
   if data then 
    data.fx_index = fx_index
    data.slot_id = slot_id
   end
  end
  if slot_id > 0 then return GetPreFaderPeakDB(track, slot_id) end
 end
 return GetPostFaderPeakDB(track)
end

LoadMixerSettings()
LoadPinnedParams()

local function UpdateVUData(track_guid, track)
 if not track then return nil end
 local data = simple_mixer_vu_data[track_guid] or {
  peak_l = -60, peak_r = -60, peak_combined = -60,
  smoothed_input = -20, smoothed_vu = -20, peak_hold = -20,
  peak_hold_time = 0, display_value = 0, last_time = r.time_precise(),
  fx_index = -1, slot_id = 0
 }
 local current_time = r.time_precise()
 local delta_time = current_time - (data.last_time or current_time)
 if delta_time > 0.1 then delta_time = 0.1 end
 data.last_time = current_time
 simple_mixer_vu_data[track_guid] = data
 data.peak_l, data.peak_r, data.peak_combined = GetPeakDB(track, track_guid)
 local input_attack_time = 0.15
 local input_release_time = 0.1
 if data.peak_combined > data.smoothed_input then
  local input_coef = 1 - math.exp(-delta_time / input_attack_time)
  data.smoothed_input = data.smoothed_input + (data.peak_combined - data.smoothed_input) * input_coef
 else
  local input_coef = 1 - math.exp(-delta_time / input_release_time)
  data.smoothed_input = data.smoothed_input + (data.peak_combined - data.smoothed_input) * input_coef
 end
 local use_pre_fader = settings.simple_mixer_vu_pre_fader
 local vu_reference = use_pre_fader and 18 or 0
 data.raw_db = data.peak_combined
 data.is_pre_fader = use_pre_fader
 local hold_duration = 2.0
 if use_pre_fader then
  local target_vu = data.smoothed_input + vu_reference
  target_vu = math.max(-20, math.min(3, target_vu))
  data.smoothed_vu = target_vu
  if data.smoothed_vu > data.peak_hold then
   data.peak_hold = data.smoothed_vu
   data.peak_hold_time = hold_duration
  else
   data.peak_hold_time = data.peak_hold_time - delta_time
   if data.peak_hold_time <= 0 then data.peak_hold = data.smoothed_vu end
  end
  data.smoothed_peak_vu = data.peak_hold
 else
  local direct_vu = data.peak_combined + vu_reference
  direct_vu = math.max(-20, math.min(3, direct_vu))
  local visual_vu = data.visual_vu or direct_vu
  local lerp_speed = 25
  if direct_vu > visual_vu then
   visual_vu = visual_vu + (direct_vu - visual_vu) * math.min(1, lerp_speed * delta_time)
  else
   visual_vu = visual_vu + (direct_vu - visual_vu) * math.min(1, lerp_speed * 0.7 * delta_time)
  end
  data.visual_vu = visual_vu
  data.smoothed_vu = visual_vu
  if direct_vu > (data.peak_hold or -60) then
   data.peak_hold = direct_vu
   data.peak_hold_time = hold_duration
  else
   data.peak_hold_time = (data.peak_hold_time or 0) - delta_time
   if data.peak_hold_time <= 0 then data.peak_hold = direct_vu end
  end
  data.smoothed_peak_vu = data.peak_hold
 end
 if data.peak_combined > (data.raw_peak_db or -60) then
  data.raw_peak_db = data.peak_combined
  data.raw_peak_hold_time = hold_duration
 else
  data.raw_peak_hold_time = (data.raw_peak_hold_time or 0) - delta_time
  if data.raw_peak_hold_time <= 0 then data.raw_peak_db = data.peak_combined end
 end
 data.display_value = (data.smoothed_vu - (-20)) / 23
 simple_mixer_vu_data[track_guid] = data
 return data
end

local function DrawVUMeter(ctx, draw_list, x, y, width, height, track_guid, track)
    if not settings.simple_mixer_show_vu_meter then return 0 end
    
    local data = UpdateVUData(track_guid, track)
    if not data then return 0 end
    
    local vu_style = settings.simple_mixer_vu_style or 0
    local vu_height = 45
    
    local bg_color = 0x000000FF
    local scale_color = 0xAAAAAAFF
    local red_color = 0xFF4444FF
    
    local is_clipping
    if data.is_pre_fader then
        is_clipping = data.smoothed_vu >= 0
    else
        is_clipping = (data.raw_db or -60) >= 0
    end
    
    if vu_style == 2 then
        local padding = 4
        local bar_width = width - padding * 2
        local bar_height = vu_height - padding * 2
        
        r.ImGui_DrawList_AddRectFilled(draw_list, x, y, x + width, y + vu_height, 0x1A1A1AFF, 3)
        
        local num_segments = 20
        local segment_gap = 2
        local segment_width = (bar_width - (num_segments - 1) * segment_gap) / num_segments
        
        local needle_vu = data.smoothed_vu or (data.smoothed_db + 18)
        needle_vu = math.max(-20, math.min(3, needle_vu))
        local level = (needle_vu + 20) / 23
        
        local peak_vu = data.smoothed_peak_vu or (data.smoothed_peak_db + 18)
        peak_vu = math.max(-20, math.min(3, peak_vu))
        local peak_level = (peak_vu + 20) / 23
        local peak_segment = math.floor(peak_level * num_segments)
        
        for i = 0, num_segments - 1 do
            local seg_x = x + padding + i * (segment_width + segment_gap)
            local seg_y = y + padding
            local seg_progress = (i + 1) / num_segments
            
            local seg_color
            if seg_progress <= 0.6 then
                seg_color = 0x00FF00FF
            elseif seg_progress <= 0.85 then
                seg_color = 0xFFFF00FF
            else
                seg_color = 0xFF0000FF
            end
            
            local is_lit = seg_progress <= level
            local is_peak = (i == peak_segment)
            
            if is_lit then
                r.ImGui_DrawList_AddRectFilled(draw_list, seg_x, seg_y, seg_x + segment_width, seg_y + bar_height, seg_color, 1)
                local highlight = (seg_color & 0xFFFFFF00) | 0x40
                r.ImGui_DrawList_AddRectFilled(draw_list, seg_x, seg_y, seg_x + segment_width, seg_y + bar_height * 0.3, highlight, 1)
            elseif is_peak then
                local dim_color = (seg_color & 0xFFFFFF00) | 0xCC
                r.ImGui_DrawList_AddRectFilled(draw_list, seg_x, seg_y, seg_x + segment_width, seg_y + bar_height, dim_color, 1)
            else
                local off_color = (seg_color & 0xFFFFFF00) | 0x20
                r.ImGui_DrawList_AddRectFilled(draw_list, seg_x, seg_y, seg_x + segment_width, seg_y + bar_height, off_color, 1)
            end
        end
        
        local led_radius = 3
        local led_x = x + width - led_radius - 3
        local led_y = y + vu_height - led_radius - 3
        local led_color = is_clipping and 0xFF0000FF or 0x440000FF
        r.ImGui_DrawList_AddCircleFilled(draw_list, led_x, led_y, led_radius, led_color)
        
        r.ImGui_DrawList_AddRect(draw_list, x, y, x + width, y + vu_height, 0x333333FF, 3, 0, 1)
        
    elseif vu_style == 3 then
        local padding = 4
        local bar_area_width = width - padding * 2
        local bar_height = (vu_height - padding * 2 - 4) / 2
        
        r.ImGui_DrawList_AddRectFilled(draw_list, x, y, x + width, y + vu_height, 0x0D0D12FF, 4)
        
        local needle_vu = data.smoothed_vu or (data.smoothed_db + 18)
        needle_vu = math.max(-20, math.min(3, needle_vu))
        local level = (needle_vu + 20) / 23
        
        local peak_vu = data.smoothed_peak_vu or (data.smoothed_peak_db + 18)
        peak_vu = math.max(-20, math.min(3, peak_vu))
        local peak_level = (peak_vu + 20) / 23
        
        for ch = 0, 1 do
            local bar_y = y + padding + ch * (bar_height + 2)
            local bar_x = x + padding
            
            r.ImGui_DrawList_AddRectFilled(draw_list, bar_x, bar_y, bar_x + bar_area_width, bar_y + bar_height, 0x1A1A20FF, 2)
            
            local level_width = bar_area_width * level
            if level_width > 0 then
                local green_end = bar_area_width * 0.65
                local yellow_end = bar_area_width * 0.85
                
                if level_width <= green_end then
                    local grad_start = 0x00AA44FF
                    local grad_end = 0x44FF88FF
                    r.ImGui_DrawList_AddRectFilledMultiColor(draw_list, bar_x, bar_y, bar_x + level_width, bar_y + bar_height, grad_start, grad_end, grad_end, grad_start)
                elseif level_width <= yellow_end then
                    r.ImGui_DrawList_AddRectFilledMultiColor(draw_list, bar_x, bar_y, bar_x + green_end, bar_y + bar_height, 0x00AA44FF, 0x44FF88FF, 0x44FF88FF, 0x00AA44FF)
                    r.ImGui_DrawList_AddRectFilledMultiColor(draw_list, bar_x + green_end, bar_y, bar_x + level_width, bar_y + bar_height, 0xCCCC00FF, 0xFFFF44FF, 0xFFFF44FF, 0xCCCC00FF)
                else
                    r.ImGui_DrawList_AddRectFilledMultiColor(draw_list, bar_x, bar_y, bar_x + green_end, bar_y + bar_height, 0x00AA44FF, 0x44FF88FF, 0x44FF88FF, 0x00AA44FF)
                    r.ImGui_DrawList_AddRectFilledMultiColor(draw_list, bar_x + green_end, bar_y, bar_x + yellow_end, bar_y + bar_height, 0xCCCC00FF, 0xFFFF44FF, 0xFFFF44FF, 0xCCCC00FF)
                    r.ImGui_DrawList_AddRectFilledMultiColor(draw_list, bar_x + yellow_end, bar_y, bar_x + level_width, bar_y + bar_height, 0xCC2200FF, 0xFF4444FF, 0xFF4444FF, 0xCC2200FF)
                end
            end
            
            local peak_x = bar_x + bar_area_width * peak_level
            if peak_x > bar_x + 2 then
                local peak_color = peak_level > 0.87 and 0xFF4444FF or 0xFFFFFFFF
                r.ImGui_DrawList_AddLine(draw_list, peak_x, bar_y, peak_x, bar_y + bar_height, peak_color, 2)
            end
        end
        
        local db_text
        if needle_vu < -18 then
            db_text = "-∞"
        else
            db_text = string.format("%.0f", needle_vu - 3)
        end
        local text_w = r.ImGui_CalcTextSize(ctx, db_text)
        local text_color = is_clipping and 0xFF4444FF or 0x888888FF
        r.ImGui_DrawList_AddTextEx(draw_list, nil, 9, x + width - text_w - 4, y + vu_height - 11, text_color, db_text)
        
        r.ImGui_DrawList_AddRect(draw_list, x, y, x + width, y + vu_height, 0x2A2A35FF, 4, 0, 1)
        
    elseif vu_style == 1 then
        local light_bg = 0xE8E4DCFF
        local light_scale = 0x444444FF
        local light_red = 0xCC2222FF
        local needle_color = 0x222222FF
        
        r.ImGui_DrawList_AddRectFilled(draw_list, x, y, x + width, y + vu_height, light_bg, 4)
        
        r.ImGui_DrawList_PushClipRect(draw_list, x, y, x + width, y + vu_height, true)
        
        local center_x = x + width / 2
        local max_radius = vu_height * 0.85
        local radius = math.min(width * 0.55, max_radius)
        local pivot_y = y + vu_height + radius * 0.15
        local inner_radius = radius * 0.90
        
        local start_angle = math.pi * 0.68
        local end_angle = math.pi * 0.32
        local angle_range = start_angle - end_angle
        
        local segments = 40
        for i = 0, segments - 1 do
            local t1 = i / segments
            local t2 = (i + 1) / segments
            local a1 = start_angle - t1 * angle_range
            local a2 = start_angle - t2 * angle_range
            
            local x1 = center_x + math.cos(a1) * radius
            local y1 = pivot_y - math.sin(a1) * radius
            local x2 = center_x + math.cos(a2) * radius
            local y2 = pivot_y - math.sin(a2) * radius
            
            local db_at_t = -20 + t1 * 23
            local arc_color = db_at_t >= 0 and light_red or light_scale
            r.ImGui_DrawList_AddLine(draw_list, x1, y1, x2, y2, arc_color, 1.5)
        end
        
        local tick_db_values = {-20, -10, -7, -5, -3, 0, 3}
        for _, db in ipairs(tick_db_values) do
            local t = (db - (-20)) / 23
            local angle = start_angle - t * angle_range
            
            local tick_outer = radius
            local tick_inner = inner_radius
            
            local x_outer = center_x + math.cos(angle) * tick_outer
            local y_outer = pivot_y - math.sin(angle) * tick_outer
            local x_inner = center_x + math.cos(angle) * tick_inner
            local y_inner = pivot_y - math.sin(angle) * tick_inner
            
            local tick_color = db >= 0 and light_red or light_scale
            r.ImGui_DrawList_AddLine(draw_list, x_inner, y_inner, x_outer, y_outer, tick_color, 1)
            
            local label = tostring(math.abs(db))
            local vu_font_size = 7
            local base_text_w, base_text_h = r.ImGui_CalcTextSize(ctx, label)
            local font_scale = vu_font_size / r.ImGui_GetFontSize(ctx)
            local text_w, text_h = base_text_w * font_scale, base_text_h * font_scale
            local label_radius = radius + 5
            local label_x = center_x + math.cos(angle) * label_radius - text_w / 2
            local label_y = pivot_y - math.sin(angle) * label_radius - text_h / 2
            local label_color = db >= 0 and light_red or 0x666666FF
            r.ImGui_DrawList_AddTextEx(draw_list, nil, vu_font_size, label_x, label_y, label_color, label)
        end
        
        local needle_length = radius * 0.88
        local vu_needle_color = 0x2266AAFF
        local peak_needle_color = 0x888888FF
        
        local peak_vu = data.smoothed_peak_vu or (data.smoothed_peak_db + 18)
        peak_vu = math.max(-20, math.min(3, peak_vu))
        local peak_t = (peak_vu - (-20)) / 23
        local peak_angle = start_angle - peak_t * angle_range
        local peak_tip_x = center_x + math.cos(peak_angle) * needle_length
        local peak_tip_y = pivot_y - math.sin(peak_angle) * needle_length
        r.ImGui_DrawList_AddLine(draw_list, center_x, pivot_y, peak_tip_x, peak_tip_y, peak_needle_color, 1.5)
        
        local needle_vu = data.smoothed_vu or (data.smoothed_db + 18)
        needle_vu = math.max(-20, math.min(3, needle_vu))
        local needle_t = (needle_vu - (-20)) / 23
        local needle_angle = start_angle - needle_t * angle_range
        local needle_tip_x = center_x + math.cos(needle_angle) * needle_length
        local needle_tip_y = pivot_y - math.sin(needle_angle) * needle_length
        r.ImGui_DrawList_AddLine(draw_list, center_x, pivot_y, needle_tip_x, needle_tip_y, vu_needle_color, 2)
        
        local vu_text = "VU"
        local vu_text_font_size = 10
        local base_vu_text_w = r.ImGui_CalcTextSize(ctx, vu_text)
        local vu_text_scale = vu_text_font_size / r.ImGui_GetFontSize(ctx)
        local vu_text_w = base_vu_text_w * vu_text_scale
        local vu_text_x = center_x - vu_text_w / 2
        local vu_text_y = y + vu_height * 0.55
        r.ImGui_DrawList_AddTextEx(draw_list, nil, vu_text_font_size, vu_text_x, vu_text_y, 0x888888FF, vu_text)
        
        r.ImGui_DrawList_PopClipRect(draw_list)
        
        local led_radius = 4
        local led_x = x + width - led_radius - 4
        local led_y = y + vu_height - led_radius - 4
        local led_color = is_clipping and 0xDD0000FF or 0xFFCCCCFF
        r.ImGui_DrawList_AddCircleFilled(draw_list, led_x, led_y, led_radius, led_color)
        
        local pivot_radius = 8
        local pivot_center_y = y + vu_height
        local pivot_color = 0xBBB8B0FF
        local pivot_segments = 16
        for i = 0, pivot_segments - 1 do
            local a1 = (i / pivot_segments) * math.pi
            local a2 = ((i + 1) / pivot_segments) * math.pi
            local px1 = center_x + math.cos(a1) * pivot_radius
            local py1 = pivot_center_y - math.sin(a1) * pivot_radius
            local px2 = center_x + math.cos(a2) * pivot_radius
            local py2 = pivot_center_y - math.sin(a2) * pivot_radius
            r.ImGui_DrawList_AddTriangleFilled(draw_list, center_x, pivot_center_y, px1, py1, px2, py2, pivot_color)
        end
        
        local border_color = 0xAAAAAFFF
        r.ImGui_DrawList_AddRect(draw_list, x, y, x + width, y + vu_height, border_color, 4, 0, 1)
        
    else
        local needle_color = 0xFFFFFFFF
        
        r.ImGui_DrawList_AddRectFilled(draw_list, x, y, x + width, y + vu_height, bg_color, 4)
        
        r.ImGui_DrawList_PushClipRect(draw_list, x, y, x + width, y + vu_height, true)
        
        local center_x = x + width / 2
        local max_radius = vu_height * 0.85
        local radius = math.min(width * 0.55, max_radius)
        local pivot_y = y + vu_height + radius * 0.15
        local inner_radius = radius * 0.90
        
        local glow_layers = 7
        for i = glow_layers, 1, -1 do
            local glow_radius = radius * (0.25 + i * 0.13)
            local alpha = math.floor(20 - i * 2)
            local glow_color = (0xFFAA40 * 256) + alpha
            r.ImGui_DrawList_AddCircleFilled(draw_list, center_x, pivot_y, glow_radius, glow_color, 32)
        end
        
        local start_angle = math.pi * 0.68
        local end_angle = math.pi * 0.32
        local angle_range = start_angle - end_angle
        
        local segments = 40
        for i = 0, segments - 1 do
            local t1 = i / segments
            local t2 = (i + 1) / segments
            local a1 = start_angle - t1 * angle_range
            local a2 = start_angle - t2 * angle_range
            
            local x1 = center_x + math.cos(a1) * radius
            local y1 = pivot_y - math.sin(a1) * radius
            local x2 = center_x + math.cos(a2) * radius
            local y2 = pivot_y - math.sin(a2) * radius
            
            local db_at_t = -20 + t1 * 23
            local arc_color = db_at_t >= 0 and red_color or scale_color
            r.ImGui_DrawList_AddLine(draw_list, x1, y1, x2, y2, arc_color, 1.5)
        end
        
        local tick_db_values = {-20, -10, -7, -5, -3, 0, 3}
        for _, db in ipairs(tick_db_values) do
            local t = (db - (-20)) / 23
            local angle = start_angle - t * angle_range
            
            local tick_outer = radius
            local tick_inner = inner_radius
            
            local x_outer = center_x + math.cos(angle) * tick_outer
            local y_outer = pivot_y - math.sin(angle) * tick_outer
            local x_inner = center_x + math.cos(angle) * tick_inner
            local y_inner = pivot_y - math.sin(angle) * tick_inner
            
            local tick_color = db >= 0 and red_color or scale_color
            r.ImGui_DrawList_AddLine(draw_list, x_inner, y_inner, x_outer, y_outer, tick_color, 1)
            
            local label = tostring(math.abs(db))
            local vu_font_size = 7
            local base_text_w, base_text_h = r.ImGui_CalcTextSize(ctx, label)
            local font_scale = vu_font_size / r.ImGui_GetFontSize(ctx)
            local text_w, text_h = base_text_w * font_scale, base_text_h * font_scale
            local label_radius = radius + 5
            local label_x = center_x + math.cos(angle) * label_radius - text_w / 2
            local label_y = pivot_y - math.sin(angle) * label_radius - text_h / 2
            local label_color = db >= 0 and red_color or 0x888888FF
            r.ImGui_DrawList_AddTextEx(draw_list, nil, vu_font_size, label_x, label_y, label_color, label)
        end
        
        local needle_length = radius * 0.88
        local vu_needle_color = 0x4A90D9FF
        local peak_needle_color = 0xAAAAAAFF
        
        local peak_vu = data.smoothed_peak_vu or (data.smoothed_peak_db + 18)
        peak_vu = math.max(-20, math.min(3, peak_vu))
        local peak_t = (peak_vu - (-20)) / 23
        local peak_angle = start_angle - peak_t * angle_range
        local peak_tip_x = center_x + math.cos(peak_angle) * needle_length
        local peak_tip_y = pivot_y - math.sin(peak_angle) * needle_length
        r.ImGui_DrawList_AddLine(draw_list, center_x, pivot_y, peak_tip_x, peak_tip_y, peak_needle_color, 1.5)
        
        local needle_vu = data.smoothed_vu or (data.smoothed_db + 18)
        needle_vu = math.max(-20, math.min(3, needle_vu))
        local needle_t = (needle_vu - (-20)) / 23
        local needle_angle = start_angle - needle_t * angle_range
        local needle_tip_x = center_x + math.cos(needle_angle) * needle_length
        local needle_tip_y = pivot_y - math.sin(needle_angle) * needle_length
        r.ImGui_DrawList_AddLine(draw_list, center_x, pivot_y, needle_tip_x, needle_tip_y, vu_needle_color, 1.5)
        
        local vu_text = "VU"
        local vu_text_font_size = 10
        local base_vu_text_w = r.ImGui_CalcTextSize(ctx, vu_text)
        local vu_text_scale = vu_text_font_size / r.ImGui_GetFontSize(ctx)
        local vu_text_w = base_vu_text_w * vu_text_scale
        local vu_text_x = center_x - vu_text_w / 2
        local vu_text_y = y + vu_height * 0.55
        r.ImGui_DrawList_AddTextEx(draw_list, nil, vu_text_font_size, vu_text_x, vu_text_y, 0x666666FF, vu_text)
        
        r.ImGui_DrawList_PopClipRect(draw_list)
        
        local led_radius = 4
        local led_x = x + width - led_radius - 4
        local led_y = y + vu_height - led_radius - 4
        local led_color = is_clipping and 0xFF0000FF or 0x440000FF
        r.ImGui_DrawList_AddCircleFilled(draw_list, led_x, led_y, led_radius, led_color)
        
        local pivot_radius = 8
        local pivot_center_y = y + vu_height
        local pivot_color = 0x000000FF
        local pivot_segments = 16
        for i = 0, pivot_segments - 1 do
            local a1 = (i / pivot_segments) * math.pi
            local a2 = ((i + 1) / pivot_segments) * math.pi
            local px1 = center_x + math.cos(a1) * pivot_radius
            local py1 = pivot_center_y - math.sin(a1) * pivot_radius
            local px2 = center_x + math.cos(a2) * pivot_radius
            local py2 = pivot_center_y - math.sin(a2) * pivot_radius
            r.ImGui_DrawList_AddTriangleFilled(draw_list, center_x, pivot_center_y, px1, py1, px2, py2, pivot_color)
        end
        
        local border_color = 0x333333FF
        r.ImGui_DrawList_AddRect(draw_list, x, y, x + width, y + vu_height, border_color, 4, 0, 1)
    end
    
    return vu_height + 4
end

ResetVUData = function()
    mixer_state.vu_data = {}
    vu_jsfx_cache = {}
    vu_track_slots = {}
    vu_track_slot_counter = 0
end

local channelstrip_fx_cache = {}

local STRIP_OFFSET = {
    EQ = 0,
    COMP = 19,
    LIM = 26,
    ROUTING = 33,
    EQ_BYPASS = 34,
    COMP_BYPASS = 35,
    LIM_BYPASS = 36
}

local function UpdateMeterData(track_guid, track)
 if not track then return end
 if not simple_mixer_meter_data[track_guid] then
  simple_mixer_meter_data[track_guid] = {
   peak_L = 0, peak_R = 0, peak_L_decay = 0, peak_R_decay = 0,
   peak_L_hold = 0, peak_R_hold = 0, hold_time_L = 0, hold_time_R = 0, max_peak = 0
  }
 end
 local data = simple_mixer_meter_data[track_guid]
 local current_time = r.time_precise()
 local decay_speed = settings.simple_mixer_meter_decay_speed or 0.92
 local hold_time = settings.simple_mixer_meter_hold_time or 1.5
 local peak_L = r.Track_GetPeakInfo(track, 0)
 local peak_R = r.Track_GetPeakInfo(track, 1)
 if peak_L > data.peak_L_decay then data.peak_L_decay = peak_L
 else data.peak_L_decay = data.peak_L_decay * decay_speed end
 if peak_R > data.peak_R_decay then data.peak_R_decay = peak_R
 else data.peak_R_decay = data.peak_R_decay * decay_speed end
 if peak_L >= data.peak_L_hold then
  data.peak_L_hold = peak_L
  data.hold_time_L = current_time
 elseif current_time - data.hold_time_L > hold_time then
  data.peak_L_hold = data.peak_L_hold * 0.95
 end
 if peak_R >= data.peak_R_hold then
  data.peak_R_hold = peak_R
  data.hold_time_R = current_time
 elseif current_time - data.hold_time_R > hold_time then
  data.peak_R_hold = data.peak_R_hold * 0.95
 end
 local current_max = math.max(peak_L, peak_R)
 if current_max > (data.max_peak or 0) then data.max_peak = current_max end
 data.peak_L = peak_L
 data.peak_R = peak_R
end

local function PeakToDb(peak)
 if peak <= 0 then return -150 end
 return 20 * math.log(peak, 10)
end

local function DbToNormalized(db, min_db, max_db)
 min_db = min_db or -60
 max_db = max_db or 6
 if db <= min_db then return 0 end
 if db >= max_db then return 1 end
 return (db - min_db) / (max_db - min_db)
end

local function GetMeterColor(normalized_value)
 local color_clip = settings.simple_mixer_meter_color_clip or 0xFF0000FF
 local color_high = settings.simple_mixer_meter_color_high or 0xFFFF00FF
 local color_mid = settings.simple_mixer_meter_color_mid or 0xCCFF00FF
 local color_normal = settings.simple_mixer_meter_color_normal or 0x00CC00FF
 local zero_db = 60 / 66
 if normalized_value >= zero_db then return color_clip
 elseif normalized_value > 0.75 then return color_high
 elseif normalized_value > 0.5 then return color_mid
 else return color_normal end
end

local function DrawMeter(ctx, draw_list, x, y, width, height, track_guid, fader_margin)
 fader_margin = fader_margin or 0
 local data = simple_mixer_meter_data[track_guid]
 if not data then
  data = { peak_L = 0, peak_R = 0, peak_L_decay = 0, peak_R_decay = 0, peak_L_hold = 0, peak_R_hold = 0, max_peak = 0 }
 end
 local meter_bg = settings.simple_mixer_meter_bg_color or 0x1A1A1AFF
 r.ImGui_DrawList_AddRectFilled(draw_list, x, y, x + width, y + height, meter_bg)
 local hold_color = 0xFFFFFFFF
 local tick_color_below = settings.simple_mixer_meter_tick_color_below or 0x888888FF
 local tick_color_above = settings.simple_mixer_meter_tick_color_above or 0x000000FF
 local segment_gap = settings.simple_mixer_meter_segment_gap or 1
 local show_ticks = settings.simple_mixer_meter_show_ticks ~= false
 local peak_display_height = fader_margin > 0 and fader_margin or 14
 local max_peak_db = PeakToDb(data.max_peak or 0)
 local is_clipping = max_peak_db >= 0
 if is_clipping then
  r.ImGui_DrawList_AddRectFilled(draw_list, x, y, x + width, y + peak_display_height, 0xFF0000FF)
 end
 local peak_text = max_peak_db > -100 and string.format("%.1f", max_peak_db) or "-∞"
 local text_w, text_h = r.ImGui_CalcTextSize(ctx, peak_text)
 text_w = text_w * 0.7
 text_h = text_h * 0.7
 local text_x = x + (width - text_w) / 2
 local text_y = y + (peak_display_height - text_h) / 2
 local text_color = is_clipping and 0xFFFFFFFF or 0xCCCCCCFF
 r.ImGui_DrawList_AddTextEx(draw_list, nil, 9, text_x, text_y, text_color, peak_text)
 local mx, my = r.ImGui_GetMousePos(ctx)
 if mx >= x and mx <= x + width and my >= y and my <= y + peak_display_height then
  if r.ImGui_IsMouseClicked(ctx, 0) then data.max_peak = 0 end
 end
 local meter_y = y + peak_display_height + 2
 local meter_height = height - peak_display_height - 2
 local tick_db_values = {0, -6, -12, -24, -48}
 local meter_width = math.floor(width / 2 - 1)
 local current_peak_db = math.max(PeakToDb(data.peak_L_decay), PeakToDb(data.peak_R_decay))
 local function DrawSingleMeter(mx, my, mw, mh, peak_decay, peak_hold)
  local peak_db = PeakToDb(peak_decay)
  local normalized = DbToNormalized(peak_db)
  if normalized > 0.001 then
   local segments = 20
   local total_segments = math.floor(normalized * segments)
   local segment_height = (mh - (segments - 1) * segment_gap) / segments
   for i = 0, total_segments - 1 do
    local seg_normalized = (i + 1) / segments
    local seg_color = GetMeterColor(seg_normalized)
    local seg_y = my + mh - (i + 1) * (segment_height + segment_gap)
    r.ImGui_DrawList_AddRectFilled(draw_list, mx, seg_y, mx + mw, seg_y + segment_height, seg_color)
   end
  end
  local hold_db = PeakToDb(peak_hold)
  local hold_normalized = DbToNormalized(hold_db)
  if hold_normalized > 0.01 then
   local hold_y = my + mh - (mh * hold_normalized)
   r.ImGui_DrawList_AddLine(draw_list, mx, hold_y, mx + mw, hold_y, hold_color, 2)
  end
 end
 DrawSingleMeter(x, meter_y, meter_width, meter_height, data.peak_L_decay, data.peak_L_hold)
 DrawSingleMeter(x + meter_width + 2, meter_y, meter_width, meter_height, data.peak_R_decay, data.peak_R_hold)
 if show_ticks then
  for _, db_val in ipairs(tick_db_values) do
   local tick_normalized = DbToNormalized(db_val)
   if tick_normalized > 0 and tick_normalized < 1 then
    local tick_y = meter_y + meter_height - (meter_height * tick_normalized)
    local tick_color = (current_peak_db >= db_val) and tick_color_above or tick_color_below
    local label = (db_val == 0 and "-0-" or (tostring(db_val) .. "-"))
    local tick_font_size = settings.simple_mixer_meter_tick_size or 8
    local text_w, text_h = r.ImGui_CalcTextSize(ctx, label)
    text_w = text_w * (tick_font_size / r.ImGui_GetFontSize(ctx))
    text_h = text_h * (tick_font_size / r.ImGui_GetFontSize(ctx))
    local text_x = x + (width - text_w) / 2
    local text_y = tick_y - text_h / 2
    if text_y > meter_y + 2 and text_y < meter_y + meter_height - text_h - 2 then
     r.ImGui_DrawList_AddTextEx(draw_list, nil, tick_font_size, text_x, text_y, tick_color, label)
    else
     r.ImGui_DrawList_AddLine(draw_list, x, tick_y, x + width, tick_y, tick_color, 1)
    end
   end
  end
 end
 return data
end

local function GetTrackIcon(ctx, track)
 local track_guid = r.GetTrackGUID(track)
 local _, ext_icon = r.GetSetMediaTrackInfo_String(track, "P_EXT:" .. TCP_ICON_EXT_KEY, "", false)
 local icon_path
 if ext_icon ~= "" then
  icon_path = ext_icon
 else
  local _, p_icon = r.GetSetMediaTrackInfo_String(track, "P_ICON", "", false)
  icon_path = p_icon
 end
 if not icon_path or icon_path == "" then
  if simple_mixer_track_icon_cache[track_guid] then
   simple_mixer_track_icon_cache[track_guid] = nil
   simple_mixer_track_icon_paths[track_guid] = nil
  end
  return nil
 end
 if simple_mixer_track_icon_paths[track_guid] == icon_path and simple_mixer_track_icon_cache[track_guid] ~= nil then
  local cached = simple_mixer_track_icon_cache[track_guid]
  if cached == false then return nil end
  if r.ImGui_ValidatePtr(cached, 'ImGui_Image*') then
   return cached
  end
 end
 if simple_mixer_track_icon_cache[track_guid] then
  simple_mixer_track_icon_cache[track_guid] = nil
 end
 local full_path = icon_path
 if not icon_path:match("^[A-Za-z]:") and not icon_path:match("^/") then
  full_path = r.GetResourcePath() .. "/Data/track_icons/" .. icon_path
 end
 local file_exists = false
 local f = io.open(full_path, "rb")
 if f then file_exists = true; f:close() end
 if not file_exists then
  simple_mixer_track_icon_paths[track_guid] = icon_path
  simple_mixer_track_icon_cache[track_guid] = false
  return nil
 end
 local ok, img = pcall(r.ImGui_CreateImage, full_path)
 if ok and img then
  simple_mixer_track_icon_cache[track_guid] = img
  simple_mixer_track_icon_paths[track_guid] = icon_path
  return img
 end
 simple_mixer_track_icon_paths[track_guid] = icon_path
 simple_mixer_track_icon_cache[track_guid] = false
 return nil
end

local function DrawFaderBackground(ctx, draw_list, x, y, width, height, rounding, track_color_rgb, fader_margin)
 local style = settings.simple_mixer_fader_bg_style or 0
 local inset = settings.simple_mixer_fader_bg_inset or false
 local glow = settings.simple_mixer_fader_bg_glow or false
 fader_margin = fader_margin or 0
 local fader_top = y + fader_margin
 local fader_bottom = y + height - fader_margin
 local fader_height = height - (fader_margin * 2)
 local top_color, bottom_color, mid_color
 if track_color_rgb then
  local tr, tg, tb = track_color_rgb[1], track_color_rgb[2], track_color_rgb[3]
  local light_r = math.min(1, tr * 1.4 + 0.1)
  local light_g = math.min(1, tg * 1.4 + 0.1)
  local light_b = math.min(1, tb * 1.4 + 0.1)
  local dark_r = tr * 0.3
  local dark_g = tg * 0.3
  local dark_b = tb * 0.3
  top_color = r.ImGui_ColorConvertDouble4ToU32(light_r, light_g, light_b, 1.0)
  bottom_color = r.ImGui_ColorConvertDouble4ToU32(dark_r, dark_g, dark_b, 1.0)
  mid_color = r.ImGui_ColorConvertDouble4ToU32(tr * 0.7, tg * 0.7, tb * 0.7, 1.0)
 else
  top_color = settings.simple_mixer_fader_bg_gradient_top or 0x606060FF
  bottom_color = settings.simple_mixer_fader_bg_gradient_bottom or 0x202020FF
  mid_color = settings.simple_mixer_fader_bg_gradient_middle or 0x404040FF
 end
 if style == 0 then
  if track_color_rgb then
   local tr, tg, tb = track_color_rgb[1], track_color_rgb[2], track_color_rgb[3]
   local bg_color = r.ImGui_ColorConvertDouble4ToU32(tr * 0.25, tg * 0.25, tb * 0.25, 1.0)
   r.ImGui_DrawList_AddRectFilled(draw_list, x, y, x + width, y + height, bg_color, rounding)
  else
   local bg_color = settings.simple_mixer_fader_bg_color or 0x404040FF
   r.ImGui_DrawList_AddRectFilled(draw_list, x, y, x + width, y + height, bg_color, rounding)
  end
 elseif style == 1 then
  if settings.simple_mixer_fader_bg_use_three_color and not track_color_rgb then
   local mid_y = y + height * 0.5
   r.ImGui_DrawList_AddRectFilledMultiColor(draw_list, x, y, x + width, mid_y, top_color, top_color, mid_color, mid_color)
   r.ImGui_DrawList_AddRectFilledMultiColor(draw_list, x, mid_y, x + width, y + height, mid_color, mid_color, bottom_color, bottom_color)
  else
   r.ImGui_DrawList_AddRectFilledMultiColor(draw_list, x, y, x + width, y + height, top_color, top_color, bottom_color, bottom_color)
  end
 elseif style == 2 then
  local left_color, right_color = top_color, bottom_color
  if settings.simple_mixer_fader_bg_use_three_color and not track_color_rgb then
   local mid_x = x + width * 0.5
   r.ImGui_DrawList_AddRectFilledMultiColor(draw_list, x, y, mid_x, y + height, left_color, mid_color, mid_color, left_color)
   r.ImGui_DrawList_AddRectFilledMultiColor(draw_list, mid_x, y, x + width, y + height, mid_color, right_color, right_color, mid_color)
  else
   r.ImGui_DrawList_AddRectFilledMultiColor(draw_list, x, y, x + width, y + height, left_color, right_color, right_color, left_color)
  end
 elseif style == 3 then
  local outer_color, center_color = bottom_color, top_color
  local mid_y = y + height * 0.5
  r.ImGui_DrawList_AddRectFilledMultiColor(draw_list, x, y, x + width, mid_y, outer_color, outer_color, center_color, center_color)
  r.ImGui_DrawList_AddRectFilledMultiColor(draw_list, x, mid_y, x + width, y + height, center_color, center_color, outer_color, outer_color)
 elseif style == 4 then
  local base_color = r.ImGui_ColorConvertDouble4ToU32(0.1, 0.1, 0.12, 1.0)
  r.ImGui_DrawList_AddRectFilled(draw_list, x, y, x + width, y + height, base_color, rounding)
  if track_color_rgb then
   local tr, tg, tb = track_color_rgb[1], track_color_rgb[2], track_color_rgb[3]
   local red_zone = r.ImGui_ColorConvertDouble4ToU32(tr * 0.8 + 0.2, tg * 0.3, tb * 0.3, 0.7)
   local yellow_zone = r.ImGui_ColorConvertDouble4ToU32(tr * 0.6 + 0.3, tg * 0.6 + 0.2, tb * 0.2, 0.7)
   local orange_zone = r.ImGui_ColorConvertDouble4ToU32(tr * 0.7 + 0.2, tg * 0.4 + 0.1, tb * 0.2, 0.7)
   local green_zone = r.ImGui_ColorConvertDouble4ToU32(tr * 0.3, tg * 0.5 + 0.2, tb * 0.3, 0.3)
   local db_0_pos = fader_top + fader_height * (1 - (0 + 60) / 72)
   local db_minus6_pos = fader_top + fader_height * (1 - (-6 + 60) / 72)
   local db_minus12_pos = fader_top + fader_height * (1 - (-12 + 60) / 72)
   r.ImGui_DrawList_AddRectFilled(draw_list, x, fader_top, x + width, db_0_pos, red_zone, 0)
   r.ImGui_DrawList_AddRectFilled(draw_list, x, db_0_pos, x + width, db_minus6_pos, orange_zone, 0)
   r.ImGui_DrawList_AddRectFilled(draw_list, x, db_minus6_pos, x + width, db_minus12_pos, yellow_zone, 0)
   r.ImGui_DrawList_AddRectFilled(draw_list, x, db_minus12_pos, x + width, fader_bottom, green_zone, 0)
  else
   local green_zone = 0x00660040
   local yellow_zone = 0x666600AA
   local orange_zone = 0x664400AA
   local red_zone = 0x660000AA
   local db_0_pos = fader_top + fader_height * (1 - (0 + 60) / 72)
   local db_minus6_pos = fader_top + fader_height * (1 - (-6 + 60) / 72)
   local db_minus12_pos = fader_top + fader_height * (1 - (-12 + 60) / 72)
   r.ImGui_DrawList_AddRectFilled(draw_list, x, fader_top, x + width, db_0_pos, red_zone, 0)
   r.ImGui_DrawList_AddRectFilled(draw_list, x, db_0_pos, x + width, db_minus6_pos, orange_zone, 0)
   r.ImGui_DrawList_AddRectFilled(draw_list, x, db_minus6_pos, x + width, db_minus12_pos, yellow_zone, 0)
   r.ImGui_DrawList_AddRectFilled(draw_list, x, db_minus12_pos, x + width, fader_bottom, green_zone, 0)
  end
 elseif style == 5 then
  local segment_count = 24
  local segment_height = height / segment_count
  local gap = 1
  for i = 0, segment_count - 1 do
   local seg_y = y + i * segment_height
   local seg_h = segment_height - gap
   local seg_color
   if track_color_rgb then
    local tr, tg, tb = track_color_rgb[1], track_color_rgb[2], track_color_rgb[3]
    local brightness = 0.15 + (segment_count - 1 - i) * 0.02
    seg_color = r.ImGui_ColorConvertDouble4ToU32(tr * brightness, tg * brightness, tb * brightness, 1.0)
    if i < 3 then
     seg_color = r.ImGui_ColorConvertDouble4ToU32(tr * 0.5 + 0.3, tg * 0.2, tb * 0.2, 1.0)
    elseif i < 8 then
     seg_color = r.ImGui_ColorConvertDouble4ToU32(tr * 0.5 + 0.2, tg * 0.4 + 0.1, tb * 0.2, 1.0)
    end
   else
    local brightness = 0.15 + (segment_count - 1 - i) * 0.01
    seg_color = r.ImGui_ColorConvertDouble4ToU32(brightness * 0.3, brightness * 0.3, brightness * 0.3, 1.0)
    if i < 3 then
     seg_color = r.ImGui_ColorConvertDouble4ToU32(0.3, 0.05, 0.05, 1.0)
    elseif i < 8 then
     seg_color = r.ImGui_ColorConvertDouble4ToU32(0.3, 0.2, 0.05, 1.0)
    end
   end
   r.ImGui_DrawList_AddRectFilled(draw_list, x, seg_y, x + width, seg_y + seg_h, seg_color, 0)
  end
 elseif style == 6 then
  local base_r, base_g, base_b = 0.35, 0.37, 0.4
  if track_color_rgb then
   base_r, base_g, base_b = track_color_rgb[1] * 0.5, track_color_rgb[2] * 0.5, track_color_rgb[3] * 0.5
  end
  local base_color = r.ImGui_ColorConvertDouble4ToU32(base_r, base_g, base_b, 1.0)
  r.ImGui_DrawList_AddRectFilled(draw_list, x, y, x + width, y + height, base_color, rounding)
  local line_spacing = 2
  for ly = y, y + height, line_spacing do
   local line_offset = ((ly - y) % 4) / 4
   local light = r.ImGui_ColorConvertDouble4ToU32(base_r + 0.08, base_g + 0.08, base_b + 0.08, 0.6 - line_offset * 0.3)
   local dark = r.ImGui_ColorConvertDouble4ToU32(base_r - 0.05, base_g - 0.05, base_b - 0.05, 0.4 + line_offset * 0.2)
   r.ImGui_DrawList_AddLine(draw_list, x, ly, x + width, ly, light, 1)
   if ly + 1 < y + height then
    r.ImGui_DrawList_AddLine(draw_list, x, ly + 1, x + width, ly + 1, dark, 1)
   end
  end
  r.ImGui_DrawList_AddRectFilledMultiColor(draw_list, x, y, x + width, y + 8, 0xFFFFFF18, 0xFFFFFF18, 0x00000000, 0x00000000)
  r.ImGui_DrawList_AddRectFilledMultiColor(draw_list, x, y + height - 8, x + width, y + height, 0x00000000, 0x00000000, 0x00000018, 0x00000018)
 elseif style == 7 then
  local base_r, base_g, base_b = 0.12, 0.12, 0.14
  if track_color_rgb then
   base_r = 0.08 + track_color_rgb[1] * 0.15
   base_g = 0.08 + track_color_rgb[2] * 0.15
   base_b = 0.08 + track_color_rgb[3] * 0.15
  end
  local base_color = r.ImGui_ColorConvertDouble4ToU32(base_r, base_g, base_b, 1.0)
  r.ImGui_DrawList_AddRectFilled(draw_list, x, y, x + width, y + height, base_color, rounding)
  local weave_size = 4
  for wy = 0, height, weave_size * 2 do
   for wx = 0, width, weave_size * 2 do
    local px, py = x + wx, y + wy
    local highlight = r.ImGui_ColorConvertDouble4ToU32(base_r + 0.06, base_g + 0.06, base_b + 0.08, 0.8)
    local shadow = r.ImGui_ColorConvertDouble4ToU32(base_r - 0.03, base_g - 0.03, base_b - 0.02, 0.6)
    if px + weave_size <= x + width and py + weave_size <= y + height then
     r.ImGui_DrawList_AddRectFilled(draw_list, px, py, px + weave_size, py + weave_size, highlight, 0)
    end
    if px + weave_size * 2 <= x + width and py + weave_size <= y + height then
     r.ImGui_DrawList_AddRectFilled(draw_list, px + weave_size, py, px + weave_size * 2, py + weave_size, shadow, 0)
    end
    if px + weave_size <= x + width and py + weave_size * 2 <= y + height then
     r.ImGui_DrawList_AddRectFilled(draw_list, px, py + weave_size, px + weave_size, py + weave_size * 2, shadow, 0)
    end
    if px + weave_size * 2 <= x + width and py + weave_size * 2 <= y + height then
     r.ImGui_DrawList_AddRectFilled(draw_list, px + weave_size, py + weave_size, px + weave_size * 2, py + weave_size * 2, highlight, 0)
    end
   end
  end
 elseif style == 8 then
  local base_r, base_g, base_b = 0.22, 0.20, 0.18
  if track_color_rgb then
   base_r = track_color_rgb[1] * 0.4 + 0.1
   base_g = track_color_rgb[2] * 0.4 + 0.1
   base_b = track_color_rgb[3] * 0.4 + 0.1
  end
  local base_color = r.ImGui_ColorConvertDouble4ToU32(base_r, base_g, base_b, 1.0)
  r.ImGui_DrawList_AddRectFilled(draw_list, x, y, x + width, y + height, base_color, rounding)
  local seed = math.floor(x * 100 + y * 10)
  for i = 0, math.floor(width * height / 8) do
   local px = x + ((seed + i * 7) % math.floor(width))
   local py = y + ((seed + i * 13) % math.floor(height))
   local noise_val = ((seed + i * 17) % 100) / 100
   local noise_color
   if noise_val > 0.5 then
    noise_color = r.ImGui_ColorConvertDouble4ToU32(1, 1, 1, (noise_val - 0.5) * 0.15)
   else
    noise_color = r.ImGui_ColorConvertDouble4ToU32(0, 0, 0, (0.5 - noise_val) * 0.2)
   end
   r.ImGui_DrawList_AddRectFilled(draw_list, px, py, px + 1, py + 1, noise_color, 0)
  end
  r.ImGui_DrawList_AddRectFilledMultiColor(draw_list, x, y, x + width, y + height * 0.3, 0xFFFFFF08, 0xFFFFFF08, 0x00000000, 0x00000000)
 elseif style == 9 then
  local base_r, base_g, base_b = 0.15, 0.15, 0.17
  if track_color_rgb then
   base_r = track_color_rgb[1] * 0.3 + 0.08
   base_g = track_color_rgb[2] * 0.3 + 0.08
   base_b = track_color_rgb[3] * 0.3 + 0.08
  end
  local base_color = r.ImGui_ColorConvertDouble4ToU32(base_r, base_g, base_b, 1.0)
  r.ImGui_DrawList_AddRectFilled(draw_list, x, y, x + width, y + height, base_color, rounding)
  local grid_size = 6
  local grid_color = r.ImGui_ColorConvertDouble4ToU32(base_r + 0.08, base_g + 0.08, base_b + 0.1, 0.5)
  local grid_highlight = r.ImGui_ColorConvertDouble4ToU32(base_r + 0.15, base_g + 0.15, base_b + 0.18, 0.3)
  for gx = x, x + width, grid_size do
   r.ImGui_DrawList_AddLine(draw_list, gx, y, gx, y + height, grid_color, 1)
  end
  for gy = y, y + height, grid_size do
   r.ImGui_DrawList_AddLine(draw_list, x, gy, x + width, gy, grid_color, 1)
  end
  for gy = y, y + height, grid_size * 4 do
   r.ImGui_DrawList_AddLine(draw_list, x, gy, x + width, gy, grid_highlight, 1)
  end
 elseif style == 10 then
  local base_r, base_g, base_b = 0.08, 0.08, 0.10
  if track_color_rgb then
   base_r = track_color_rgb[1] * 0.15 + 0.05
   base_g = track_color_rgb[2] * 0.15 + 0.05
   base_b = track_color_rgb[3] * 0.15 + 0.05
  end
  local base_color = r.ImGui_ColorConvertDouble4ToU32(base_r, base_g, base_b, 1.0)
  r.ImGui_DrawList_AddRectFilled(draw_list, x, y, x + width, y + height, base_color, rounding)
  local db_marks = {12, 6, 3, 0, -3, -6, -9, -12, -18, -24, -30, -40, -50, -60}
  local major_marks = {12, 0, -12, -24, -60}
  local text_color = 0xAAAAAAFF
  local tick_color = 0x666666FF
  local major_tick_color = 0x888888FF
  if track_color_rgb then
   local tr, tg, tb = track_color_rgb[1], track_color_rgb[2], track_color_rgb[3]
   text_color = r.ImGui_ColorConvertDouble4ToU32(tr * 0.6 + 0.4, tg * 0.6 + 0.4, tb * 0.6 + 0.4, 0.9)
   tick_color = r.ImGui_ColorConvertDouble4ToU32(tr * 0.4 + 0.2, tg * 0.4 + 0.2, tb * 0.4 + 0.2, 0.8)
   major_tick_color = r.ImGui_ColorConvertDouble4ToU32(tr * 0.5 + 0.3, tg * 0.5 + 0.3, tb * 0.5 + 0.3, 1.0)
  end
  for _, db in ipairs(db_marks) do
   local normalized = (db + 60) / 72
   local mark_y = fader_bottom - (fader_height * normalized)
   local is_major = false
   for _, major in ipairs(major_marks) do
    if db == major then is_major = true break end
   end
   if is_major then
    r.ImGui_DrawList_AddLine(draw_list, x, mark_y, x + width * 0.4, mark_y, major_tick_color, 1)
    r.ImGui_DrawList_AddLine(draw_list, x + width * 0.6, mark_y, x + width, mark_y, major_tick_color, 1)
   else
    r.ImGui_DrawList_AddLine(draw_list, x, mark_y, x + width * 0.25, mark_y, tick_color, 1)
    r.ImGui_DrawList_AddLine(draw_list, x + width * 0.75, mark_y, x + width, mark_y, tick_color, 1)
   end
  end
  local zone_0db = fader_bottom - (fader_height * (60 / 72))
  local zone_minus12 = fader_bottom - (fader_height * (48 / 72))
  r.ImGui_DrawList_AddRectFilled(draw_list, x, fader_top, x + 2, zone_0db, 0xFF000030, 0)
  r.ImGui_DrawList_AddRectFilled(draw_list, x, zone_0db, x + 2, zone_minus12, 0xFFFF0020, 0)
  r.ImGui_DrawList_AddRectFilled(draw_list, x, zone_minus12, x + 2, fader_bottom, 0x00FF0015, 0)
 end
 if inset then
  local shadow_color = 0x00000088
  local highlight_color = 0xFFFFFF22
  r.ImGui_DrawList_AddLine(draw_list, x, y, x + width, y, shadow_color, 2)
  r.ImGui_DrawList_AddLine(draw_list, x, y, x, y + height, shadow_color, 2)
  r.ImGui_DrawList_AddLine(draw_list, x + width, y, x + width, y + height, highlight_color, 1)
  r.ImGui_DrawList_AddLine(draw_list, x, y + height, x + width, y + height, highlight_color, 1)
 end
 if glow then
  local glow_color = settings.simple_mixer_fader_bg_glow_color or 0x00FFFF40
  if track_color_rgb then
   local tr, tg, tb = track_color_rgb[1], track_color_rgb[2], track_color_rgb[3]
   glow_color = r.ImGui_ColorConvertDouble4ToU32(tr, tg, tb, 0.4)
  end
  r.ImGui_DrawList_AddRect(draw_list, x - 1, y - 1, x + width + 1, y + height + 1, glow_color, rounding, 0, 2)
  local glow_r, glow_g, glow_b, _ = r.ImGui_ColorConvertU32ToDouble4(glow_color)
  local outer_glow = r.ImGui_ColorConvertDouble4ToU32(glow_r, glow_g, glow_b, 0.15)
  r.ImGui_DrawList_AddRect(draw_list, x - 2, y - 2, x + width + 2, y + height + 2, outer_glow, rounding, 0, 1)
 end
end

local function DrawTrackIcon(ctx, draw_list, track, x, y, width, height, opacity)
 local img = GetTrackIcon(ctx, track)
 if not img then return end
 local img_w, img_h = r.ImGui_Image_GetSize(img)
 if not img_w or img_w == 0 then return end
 local aspect_ratio = img_w / img_h
 local is_3state_icon = aspect_ratio > 2.5
 local state_w = is_3state_icon and (img_w / 3) or img_w
 local uv_max_x = is_3state_icon and 0.333 or 1
 local max_size = 48
 local size_multiplier = settings.simple_mixer_track_icon_size or 1.0
 local scale = math.min(width / state_w, height / img_h, max_size / state_w, max_size / img_h) * 0.8 * size_multiplier
 local draw_w = state_w * scale
 local draw_h = img_h * scale
 local draw_x = x + (width - draw_w) / 2
 local vertical_pos = settings.simple_mixer_track_icon_vertical_pos or 0.5
 local draw_y = y + (height - draw_h) * vertical_pos
 local alpha = math.floor(opacity * 255)
 local tint_col = 0xFFFFFF00 | alpha
 r.ImGui_DrawList_AddImage(draw_list, img, draw_x, draw_y, draw_x + draw_w, draw_y + draw_h, 0, 0, uv_max_x, 1, tint_col)
end

local function GetDividerConfig(track_guid)
 local cached = simple_mixer_divider_names[track_guid]
 if type(cached) == "table" then return cached end
 local key = "divider_cfg_" .. track_guid
 local stored = r.GetExtState(EXT_STATE_KEY, key)
 if stored and stored ~= "" then
  local ok, cfg = pcall(json.decode, stored)
  if ok and type(cfg) == "table" then
   cfg.mode = cfg.mode or "default"
   cfg.text = cfg.text or "Divider"
   cfg.size = cfg.size or (settings.simple_mixer_font_size or 12)
   simple_mixer_divider_names[track_guid] = cfg
   return cfg
  end
 end
 local legacy = r.GetExtState(EXT_STATE_KEY, "divider_name_" .. track_guid)
 local cfg = { mode = "default", text = "Divider", size = settings.simple_mixer_font_size or 12 }
 if legacy and legacy ~= "" then
  cfg.mode = "custom"
  cfg.text = legacy
 end
 simple_mixer_divider_names[track_guid] = cfg
 return cfg
end

local function SetDividerConfig(track_guid, cfg)
 simple_mixer_divider_names[track_guid] = cfg
 r.SetExtState(EXT_STATE_KEY, "divider_cfg_" .. track_guid, json.encode(cfg), true)
end

local function GetDividerDisplayText(cfg)
 if cfg.mode == "none" then return "" end
 if cfg.mode == "custom" then return cfg.text or "" end
 return "Divider"
end

local function GetDividerName(track_guid)
 return GetDividerDisplayText(GetDividerConfig(track_guid))
end

local function SetDividerName(track_guid, name)
 local cfg = GetDividerConfig(track_guid)
 cfg.mode = "custom"
 cfg.text = name
 SetDividerConfig(track_guid, cfg)
end

local function DrawSectionHeader(ctx, label, setting_key, sidebar_width)
 if settings[setting_key] == nil then settings[setting_key] = true end
 local is_open = settings[setting_key]
 local arrow = is_open and "▼ " or "▶ "
 local header_color = 0x3A3A3AFF
 local header_hover_color = 0x4A4A4AFF
 local text_color = 0xCCCCCCFF
 r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), header_color)
 r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), header_hover_color)
 r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), header_hover_color)
 r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), text_color)
 r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ButtonTextAlign(), 0.0, 0.5)
 if r.ImGui_Button(ctx, arrow .. label, sidebar_width - 16, 20) then
  settings[setting_key] = not is_open
  is_open = settings[setting_key]
  SaveMixerSettings()
 end
 r.ImGui_PopStyleVar(ctx, 1)
 r.ImGui_PopStyleColor(ctx, 4)
 return is_open
end

local function DrawMixerSidebarParams(mixer_ctx, sidebar_width)
 local sel_for_top = r.GetSelectedTrack(0, 0) or r.GetMasterTrack(0)
 local btn_width_top = math.floor((sidebar_width - 20) / 2)

 if mixer_state.param_learn_active then
  r.ImGui_PushStyleColor(mixer_ctx, r.ImGui_Col_Button(), 0xAA4444FF)
  r.ImGui_PushStyleColor(mixer_ctx, r.ImGui_Col_ButtonHovered(), 0xBB5555FF)
 else
  r.ImGui_PushStyleColor(mixer_ctx, r.ImGui_Col_Button(), 0x4A4A4AFF)
  r.ImGui_PushStyleColor(mixer_ctx, r.ImGui_Col_ButtonHovered(), 0x5A5A5AFF)
 end
 if r.ImGui_Button(mixer_ctx, mixer_state.param_learn_active and "Learn.." or "Learn", btn_width_top, 0) then
  mixer_state.param_learn_active = not mixer_state.param_learn_active
  if mixer_state.param_learn_active then
   mixer_state.param_learn_last_check = nil
  end
 end
 r.ImGui_PopStyleColor(mixer_ctx, 2)
 if r.ImGui_IsItemHovered(mixer_ctx) then
  r.ImGui_SetTooltip(mixer_ctx, "Click to start learning.\nThen touch any FX parameter to pin it.")
 end

 r.ImGui_SameLine(mixer_ctx, 0, 4)

 if r.ImGui_Button(mixer_ctx, "Sync", btn_width_top, 0) then
  SyncEmbeddedParams(sel_for_top)
  SavePinnedParams()
 end
 if r.ImGui_IsItemHovered(mixer_ctx) then
  r.ImGui_SetTooltip(mixer_ctx, "Sync embedded TCP/MCP parameters for this track")
 end

 if mixer_state.param_learn_active then
  local retval, trackidx, fxidx, paramidx = r.GetLastTouchedFX()
  if retval then
   local current_check = trackidx .. "_" .. fxidx .. "_" .. paramidx
   if mixer_state.param_learn_last_check and current_check ~= mixer_state.param_learn_last_check then
    local learn_track
    if trackidx == 0 then
     learn_track = r.GetMasterTrack(0)
    else
     learn_track = r.GetTrack(0, trackidx - 1)
    end
    if learn_track then
     local learn_guid = r.GetTrackGUID(learn_track)
     local _, fx_name = r.TrackFX_GetFXName(learn_track, fxidx, "")
     local _, param_name = r.TrackFX_GetParamName(learn_track, fxidx, paramidx, "")
     local learn_track_num = trackidx == 0 and "M" or tostring(trackidx)
     local _, learn_track_name = r.GetTrackName(learn_track)
     local key = fxidx .. "_" .. paramidx

     if not simple_mixer_pinned_params[learn_guid] then
      simple_mixer_pinned_params[learn_guid] = {}
     end
     simple_mixer_pinned_params[learn_guid][key] = {
      track = learn_track,
      track_num = learn_track_num,
      track_name = learn_track_name,
      fxidx = fxidx,
      paramidx = paramidx,
      fx_name = fx_name,
      param_name = param_name
     }
     SavePinnedParams()
     if r.SNM_AddTCPFXParm then
      r.SNM_AddTCPFXParm(learn_track, fxidx, paramidx)
      r.TrackList_AdjustWindows(false)
     end
     mixer_state.param_learn_active = false
    end
   end
   mixer_state.param_learn_last_check = current_check
  end

  r.ImGui_TextColored(mixer_ctx, 0xFF8888FF, "Touch a parameter...")
 end

 r.ImGui_Spacing(mixer_ctx)
 r.ImGui_Separator(mixer_ctx)
 r.ImGui_Spacing(mixer_ctx)

 if mixer_state.ltp_open == nil then mixer_state.ltp_open = true end
 local sel_for_ltp = r.GetSelectedTrack(0, 0) or r.GetMasterTrack(0)
 local ltp_bg_color = 0x3A3A3AFF
 local ltp_hover_color = 0x4A4A4AFF
 local ltp_active_color = 0x5A5A5AFF
 if mixer_state.last_touched_param and r.ValidatePtr(mixer_state.last_touched_param.track, "MediaTrack*") then
  local ltp_track_color = r.GetTrackColor(mixer_state.last_touched_param.track)
  if ltp_track_color ~= 0 then
   local rv, gv, bv = r.ColorFromNative(ltp_track_color)
   ltp_bg_color = r.ImGui_ColorConvertDouble4ToU32(rv/255, gv/255, bv/255, 0.8)
   ltp_hover_color = r.ImGui_ColorConvertDouble4ToU32(math.min(1, rv/255 + 0.1), math.min(1, gv/255 + 0.1), math.min(1, bv/255 + 0.1), 0.9)
   ltp_active_color = r.ImGui_ColorConvertDouble4ToU32(math.min(1, rv/255 + 0.2), math.min(1, gv/255 + 0.2), math.min(1, bv/255 + 0.2), 1.0)
  end
 end

 local ltp_draw_list = r.ImGui_GetWindowDrawList(mixer_ctx)
 r.ImGui_PushStyleColor(mixer_ctx, r.ImGui_Col_Button(), ltp_bg_color)
 r.ImGui_PushStyleColor(mixer_ctx, r.ImGui_Col_ButtonHovered(), ltp_hover_color)
 r.ImGui_PushStyleColor(mixer_ctx, r.ImGui_Col_ButtonActive(), ltp_active_color)

 local ltp_header = "Last Touched"
 local ltp_text_w = r.ImGui_CalcTextSize(mixer_ctx, ltp_header)
 local ltp_btn_w = sidebar_width - 8
 local ltp_btn_h = 16
 if r.ImGui_Button(mixer_ctx, "##ltpheader", ltp_btn_w, ltp_btn_h) then
  mixer_state.ltp_open = not mixer_state.ltp_open
 end
 local ltp_btn_x, ltp_btn_y = r.ImGui_GetItemRectMin(mixer_ctx)
 local ltp_text_x = ltp_btn_x + (ltp_btn_w - ltp_text_w) / 2
 local ltp_text_y = ltp_btn_y + (ltp_btn_h - r.ImGui_GetTextLineHeight(mixer_ctx)) / 2
 r.ImGui_DrawList_AddText(ltp_draw_list, ltp_text_x, ltp_text_y, 0xFFFFFFFF, ltp_header)
 r.ImGui_PopStyleColor(mixer_ctx, 3)

 if mixer_state.ltp_open then
  local retval, trackidx, fxidx, paramidx = r.GetLastTouchedFX()
  if retval then
   local track
   if trackidx == 0 then
    track = r.GetMasterTrack(0)
   else
    track = r.GetTrack(0, trackidx - 1)
   end
   if track then
    local _, fx_name = r.TrackFX_GetFXName(track, fxidx, "")
    local _, param_name = r.TrackFX_GetParamName(track, fxidx, paramidx, "")
    local track_num_str = trackidx == 0 and "M" or tostring(trackidx)
    local _, t_name = r.GetTrackName(track)
    mixer_state.last_touched_param = {
     track = track, track_num = track_num_str, track_name = t_name,
     fxidx = fxidx, paramidx = paramidx, fx_name = fx_name, param_name = param_name
    }
   end
  end

  if mixer_state.last_touched_param then
   local ltp = mixer_state.last_touched_param
   local short_fx = ltp.fx_name:match("^[^%(]+") or ltp.fx_name
   if #short_fx > 18 then short_fx = short_fx:sub(1, 16) .. ".." end
   r.ImGui_Text(mixer_ctx, ltp.track_num .. ": " .. short_fx)
   local short_param = ltp.param_name
   if #short_param > 20 then short_param = short_param:sub(1, 18) .. ".." end
   r.ImGui_TextColored(mixer_ctx, 0xAAAAAAFF, short_param)
   if r.ValidatePtr(ltp.track, "MediaTrack*") then
    local param_val = r.TrackFX_GetParam(ltp.track, ltp.fxidx, ltp.paramidx)
    local _, formatted = r.TrackFX_GetFormattedParamValue(ltp.track, ltp.fxidx, ltp.paramidx, "")
    local pin_btn_w = 28
    r.ImGui_SetNextItemWidth(mixer_ctx, sidebar_width - 16 - pin_btn_w - 4)
    local changed, new_val = r.ImGui_SliderDouble(mixer_ctx, "##ltpslider", param_val, 0.0, 1.0, formatted)
    if changed then
     r.TrackFX_SetParam(ltp.track, ltp.fxidx, ltp.paramidx, new_val)
    end
    if r.ImGui_IsItemHovered(mixer_ctx) and r.ImGui_IsMouseClicked(mixer_ctx, r.ImGui_MouseButton_Right()) then
     r.ImGui_OpenPopup(mixer_ctx, "LTPContextMenu")
    end
    if r.ImGui_BeginPopup(mixer_ctx, "LTPContextMenu") then
     if r.ImGui_MenuItem(mixer_ctx, "Open FX Chain") then
      r.TrackFX_Show(ltp.track, ltp.fxidx, 1)
     end
     if r.ImGui_MenuItem(mixer_ctx, "Open FX Window") then
      r.TrackFX_Show(ltp.track, ltp.fxidx, 3)
     end
     r.ImGui_EndPopup(mixer_ctx)
    end
    r.ImGui_SameLine(mixer_ctx, 0, 4)
    if r.ImGui_Button(mixer_ctx, "Pin##ltppin", pin_btn_w, 0) then
     local pin_guid = r.GetTrackGUID(ltp.track)
     if not simple_mixer_pinned_params[pin_guid] then
      simple_mixer_pinned_params[pin_guid] = {}
     end
     local pin_key = ltp.fxidx .. "_" .. ltp.paramidx
     simple_mixer_pinned_params[pin_guid][pin_key] = {
      track = ltp.track,
      track_num = ltp.track_num,
      track_name = ltp.track_name,
      fxidx = ltp.fxidx,
      paramidx = ltp.paramidx,
      fx_name = ltp.fx_name,
      param_name = ltp.param_name
     }
     SavePinnedParams()
     if r.SNM_AddTCPFXParm then
      r.SNM_AddTCPFXParm(ltp.track, ltp.fxidx, ltp.paramidx)
      r.TrackList_AdjustWindows(false)
     end
     r.SetOnlyTrackSelected(ltp.track)
    end
    if r.ImGui_IsItemHovered(mixer_ctx) then
     r.ImGui_SetTooltip(mixer_ctx, "Pin this parameter")
    end
   end
  else
   r.ImGui_TextColored(mixer_ctx, 0x666666FF, "(Touch a parameter)")
  end
 end

 r.ImGui_Spacing(mixer_ctx)
 r.ImGui_Separator(mixer_ctx)
 r.ImGui_Spacing(mixer_ctx)
 r.ImGui_Text(mixer_ctx, "Pinned Parameters")
 r.ImGui_Spacing(mixer_ctx)
 local num_sel = r.CountSelectedTracks(0)
 if num_sel == 1 then
  local sel_track = r.GetSelectedTrack(0, 0)
  if sel_track then
   local track_guid = r.GetTrackGUID(sel_track)
   local _, track_name = r.GetTrackName(sel_track)
   r.ImGui_Text(mixer_ctx, "Track: " .. track_name)
   r.ImGui_Spacing(mixer_ctx)
   r.ImGui_Separator(mixer_ctx)
   r.ImGui_Spacing(mixer_ctx)
   local pinned = simple_mixer_pinned_params[track_guid]
   if pinned then
    local to_remove = nil
    for key, pp in pairs(pinned) do
     r.ImGui_PushID(mixer_ctx, key)
     local short_fx = pp.fx_name and pp.fx_name:match("^[^:]+:%s*(.+)$") or pp.fx_name or "?"
     if #short_fx > 12 then short_fx = short_fx:sub(1, 11) .. ".." end
     local short_param = pp.param_name or "?"
     if #short_param > 12 then short_param = short_param:sub(1, 11) .. ".." end
     r.ImGui_Text(mixer_ctx, short_fx)
     r.ImGui_Text(mixer_ctx, "  " .. short_param)
     local val = r.TrackFX_GetParam(sel_track, pp.fxidx, pp.paramidx)
     r.ImGui_SetNextItemWidth(mixer_ctx, sidebar_width - 32)
     local rv, new_val = r.ImGui_SliderDouble(mixer_ctx, "##param", val, 0.0, 1.0, "%.2f")
     if rv then
      r.TrackFX_SetParam(sel_track, pp.fxidx, pp.paramidx, new_val)
     end
     if r.ImGui_IsItemHovered(mixer_ctx) and r.ImGui_IsMouseClicked(mixer_ctx, r.ImGui_MouseButton_Right()) then
      r.ImGui_OpenPopup(mixer_ctx, "PinnedContextMenu")
     end
     if r.ImGui_BeginPopup(mixer_ctx, "PinnedContextMenu") then
      if r.ImGui_MenuItem(mixer_ctx, "Learn (MIDI CC)") then
       r.TrackFX_SetParam(sel_track, pp.fxidx, pp.paramidx, val)
       r.Main_OnCommand(41144, 0)
      end
      if r.ImGui_MenuItem(mixer_ctx, "Modulate") then
       r.TrackFX_SetParam(sel_track, pp.fxidx, pp.paramidx, val)
       r.Main_OnCommand(41143, 0)
      end
      if r.ImGui_MenuItem(mixer_ctx, "Show Envelope") then
       local fx_env = r.GetFXEnvelope(sel_track, pp.fxidx, pp.paramidx, true)
       if fx_env then
        r.TrackList_AdjustWindows(false)
       end
      end
      r.ImGui_Separator(mixer_ctx)
      if r.ImGui_MenuItem(mixer_ctx, "Unpin") then
       to_remove = key
      end
      r.ImGui_Separator(mixer_ctx)
      if r.ImGui_MenuItem(mixer_ctx, "Open FX Chain") then
       r.TrackFX_Show(sel_track, pp.fxidx, 1)
      end
      if r.ImGui_MenuItem(mixer_ctx, "Open FX Window") then
       r.TrackFX_Show(sel_track, pp.fxidx, 3)
      end
      r.ImGui_EndPopup(mixer_ctx)
     end
     r.ImGui_SameLine(mixer_ctx)
     if r.ImGui_SmallButton(mixer_ctx, "X##remove") then
      to_remove = key
     end
     r.ImGui_Spacing(mixer_ctx)
     r.ImGui_PopID(mixer_ctx)
    end
    if to_remove then
     pinned[to_remove] = nil
     SavePinnedParams()
    end
   else
    r.ImGui_TextWrapped(mixer_ctx, "No pinned parameters.\nUse 'Learn' or 'Sync Embedded' to add.")
   end
  end
 else
  r.ImGui_TextWrapped(mixer_ctx, "Select a single track to manage parameters.")
 end
end

local function DrawMixerSidebar(mixer_ctx, sidebar_width, project_mixer_tracks)
 local sidebar_mode = settings.simple_mixer_sidebar_mode or "track"
 r.ImGui_Spacing(mixer_ctx)
 r.ImGui_Separator(mixer_ctx)
 r.ImGui_Spacing(mixer_ctx)
 if sidebar_mode == "params" then
  DrawMixerSidebarParams(mixer_ctx, sidebar_width)
  return
 end
 if r.ImGui_Button(mixer_ctx, "Settings...", sidebar_width - 16) then
  settings.simple_mixer_settings_popup_open = not settings.simple_mixer_settings_popup_open
 end
 r.ImGui_Spacing(mixer_ctx)
 if DrawSectionHeader(mixer_ctx, "Looks Preset", "simple_mixer_presets_open", sidebar_width) then
  local preset_files = {}
  local presets_dir = r.GetResourcePath() .. "/Scripts/TK Scripts/Mixer/tk_mixer_presets/"
  local idx = 0
  repeat
   local file = r.EnumerateFiles(presets_dir, idx)
   if file then
    if file:match("%.json$") then
     table.insert(preset_files, (file:gsub("%.json$", "")))
    end
    idx = idx + 1
   end
  until not file
  if #preset_files > 0 then
   r.ImGui_SetNextItemWidth(mixer_ctx, sidebar_width - 16)
   if r.ImGui_BeginCombo(mixer_ctx, "##preset_combo", settings.simple_mixer_current_preset or "Select...") then
    for _, preset_name in ipairs(preset_files) do
     if r.ImGui_Selectable(mixer_ctx, preset_name, settings.simple_mixer_current_preset == preset_name) then
      LoadMixerPreset(preset_name)
     end
    end
    r.ImGui_EndCombo(mixer_ctx)
   end
  end
  r.ImGui_Spacing(mixer_ctx)
  r.ImGui_SetNextItemWidth(mixer_ctx, sidebar_width - 16)
  local rv, new_name = r.ImGui_InputText(mixer_ctx, "##new_preset", settings.simple_mixer_new_preset_name or "")
  if rv then settings.simple_mixer_new_preset_name = new_name end
  local typed = settings.simple_mixer_new_preset_name or ""
  local cur = settings.simple_mixer_current_preset or ""
  local btn_label = "Save"
  if typed == "" and cur ~= "" then btn_label = "Update" end
  if r.ImGui_Button(mixer_ctx, btn_label .. "##looks", (sidebar_width - 20) / 2) then
   local name = (typed ~= "") and typed or cur
   if name and name ~= "" then
    SaveMixerPreset(name)
    settings.simple_mixer_current_preset = name
    settings.simple_mixer_new_preset_name = ""
   end
  end
  if r.ImGui_IsItemHovered(mixer_ctx) then
   if btn_label == "Update" then
    r.ImGui_SetTooltip(mixer_ctx, "Overwrite Looks Preset: " .. cur .. "\n(visual settings only, no tracks/faders)")
   else
    r.ImGui_SetTooltip(mixer_ctx, "Save visual settings as preset.\nTracks and fader positions are NOT included\n(use Project Snapshot for those).")
   end
  end
  r.ImGui_SameLine(mixer_ctx, 0, 4)
  if r.ImGui_Button(mixer_ctx, "Del##looks", (sidebar_width - 20) / 2) then
   local name = settings.simple_mixer_current_preset
   if name then
    local preset_path = presets_dir .. name .. ".json"
    os.remove(preset_path)
    settings.simple_mixer_current_preset = nil
   end
  end
 end
 r.ImGui_Spacing(mixer_ctx)
 if DrawSectionHeader(mixer_ctx, "Project Snapshot", "simple_mixer_snapshots_open", sidebar_width) then
  local proj_path = r.GetProjectPath("")
  if proj_path == "" then
   r.ImGui_TextWrapped(mixer_ctx, "Open or save a project to use Snapshots.")
  else
   local snapshots = GetProjectSnapshots()
   local snap_names = {}
   for snap_name, _ in pairs(snapshots) do
    table.insert(snap_names, snap_name)
   end
   table.sort(snap_names)
   if #snap_names > 0 then
    r.ImGui_SetNextItemWidth(mixer_ctx, sidebar_width - 16)
    if r.ImGui_BeginCombo(mixer_ctx, "##snap_combo", settings.simple_mixer_current_snapshot or "Select...") then
     for _, sn in ipairs(snap_names) do
      if r.ImGui_Selectable(mixer_ctx, sn, settings.simple_mixer_current_snapshot == sn) then
       LoadProjectSnapshot(sn)
      end
     end
     r.ImGui_EndCombo(mixer_ctx)
    end
   end
   r.ImGui_Spacing(mixer_ctx)
   r.ImGui_SetNextItemWidth(mixer_ctx, sidebar_width - 16)
   local rv_sn, snap_typed = r.ImGui_InputText(mixer_ctx, "##new_snap", settings.simple_mixer_new_snapshot_name or "")
   if rv_sn then settings.simple_mixer_new_snapshot_name = snap_typed end
   local s_typed = settings.simple_mixer_new_snapshot_name or ""
   local s_cur = settings.simple_mixer_current_snapshot or ""
   local s_btn = "Save"
   if s_typed == "" and s_cur ~= "" then s_btn = "Update" end
   if r.ImGui_Button(mixer_ctx, s_btn .. "##snap", (sidebar_width - 20) / 2) then
    local nm = (s_typed ~= "") and s_typed or s_cur
    if nm and nm ~= "" then
     SaveProjectSnapshot(nm, settings.simple_mixer_snapshot_include_faders ~= false)
     settings.simple_mixer_current_snapshot = nm
     settings.simple_mixer_new_snapshot_name = ""
    end
   end
   if r.ImGui_IsItemHovered(mixer_ctx) then
    if s_btn == "Update" then
     r.ImGui_SetTooltip(mixer_ctx, "Overwrite snapshot: " .. s_cur)
    else
     r.ImGui_SetTooltip(mixer_ctx, "Save current tracks, hidden state\nand (optionally) fader positions\nas a project snapshot.")
    end
   end
   r.ImGui_SameLine(mixer_ctx, 0, 4)
   if r.ImGui_Button(mixer_ctx, "Del##snap", (sidebar_width - 20) / 2) then
    local nm = settings.simple_mixer_current_snapshot
    if nm and nm ~= "" then
     DeleteProjectSnapshot(nm)
     settings.simple_mixer_current_snapshot = ""
    end
   end
   r.ImGui_Spacing(mixer_ctx)
   local rv_sf
   rv_sf, settings.simple_mixer_snapshot_include_faders = r.ImGui_Checkbox(mixer_ctx, "Save Faders", settings.simple_mixer_snapshot_include_faders ~= false)
   if rv_sf then SaveMixerSettings() end
   if r.ImGui_IsItemHovered(mixer_ctx) then
    r.ImGui_SetTooltip(mixer_ctx, "Include volume, pan, mute & solo in snapshots")
   end
  end
 end
 r.ImGui_Spacing(mixer_ctx)
 r.ImGui_Separator(mixer_ctx)
 r.ImGui_Spacing(mixer_ctx)
 r.ImGui_Text(mixer_ctx, "Tracks")
 r.ImGui_Spacing(mixer_ctx)
 local btn_spacing = 4
 local btn_width = math.floor((sidebar_width - 16 - btn_spacing * 2) / 3)
 if r.ImGui_Button(mixer_ctx, "+##addsel", btn_width) then
  local num_sel_tracks = r.CountSelectedTracks(0)
  if num_sel_tracks > 0 then
   for i = 0, num_sel_tracks - 1 do
    local track = r.GetSelectedTrack(0, i)
    local guid = r.GetTrackGUID(track)
    local already_added = false
    for _, existing_guid in ipairs(project_mixer_tracks) do
     if existing_guid == guid then already_added = true break end
    end
    if not already_added then table.insert(project_mixer_tracks, guid) end
   end
   SaveProjectMixerTracks(project_mixer_tracks)
  end
 end
 if r.ImGui_IsItemHovered(mixer_ctx) then r.ImGui_SetTooltip(mixer_ctx, "Add Selected Tracks") end
 r.ImGui_SameLine(mixer_ctx, 0, btn_spacing)
 if r.ImGui_Button(mixer_ctx, "All##addall", btn_width) then
  local num_tracks = r.CountTracks(0)
  for i = 0, num_tracks - 1 do
   local track = r.GetTrack(0, i)
   local guid = r.GetTrackGUID(track)
   local already_added = false
   for _, existing_guid in ipairs(project_mixer_tracks) do
    if existing_guid == guid then already_added = true break end
   end
   if not already_added then table.insert(project_mixer_tracks, guid) end
  end
  SaveProjectMixerTracks(project_mixer_tracks)
 end
 if r.ImGui_IsItemHovered(mixer_ctx) then r.ImGui_SetTooltip(mixer_ctx, "Add All Tracks") end
 r.ImGui_SameLine(mixer_ctx, 0, btn_spacing)
 if r.ImGui_Button(mixer_ctx, "Clr##clearall", btn_width) then
  project_mixer_tracks = {}
  SaveProjectMixerTracks(project_mixer_tracks)
 end
 if r.ImGui_IsItemHovered(mixer_ctx) then r.ImGui_SetTooltip(mixer_ctx, "Remove All Tracks from Mixer") end
 r.ImGui_Spacing(mixer_ctx)
 r.ImGui_Separator(mixer_ctx)
 r.ImGui_Spacing(mixer_ctx)
 if DrawSectionHeader(mixer_ctx, "Show", "simple_mixer_show_open", sidebar_width) then
  if r.ImGui_BeginTable(mixer_ctx, "ShowToggles", 2) then
   local changed, rv = false, false
   r.ImGui_TableNextRow(mixer_ctx)
   r.ImGui_TableNextColumn(mixer_ctx)
   rv, settings.simple_mixer_show_rms = r.ImGui_Checkbox(mixer_ctx, "RMS##QT", settings.simple_mixer_show_rms ~= false)
   if rv then changed = true end
   r.ImGui_TableNextColumn(mixer_ctx)
   rv, settings.simple_mixer_show_pan = r.ImGui_Checkbox(mixer_ctx, "Pan##QT", settings.simple_mixer_show_pan ~= false)
   if rv then changed = true end
   r.ImGui_TableNextRow(mixer_ctx)
   r.ImGui_TableNextColumn(mixer_ctx)
   rv, settings.simple_mixer_show_width = r.ImGui_Checkbox(mixer_ctx, "Wdth##QT", settings.simple_mixer_show_width or false)
   if rv then changed = true end
   r.ImGui_TableNextColumn(mixer_ctx)
   rv, settings.simple_mixer_show_track_buttons = r.ImGui_Checkbox(mixer_ctx, "Btns##QT", settings.simple_mixer_show_track_buttons or false)
   if rv then changed = true end
   r.ImGui_TableNextRow(mixer_ctx)
   r.ImGui_TableNextColumn(mixer_ctx)
   rv, settings.simple_mixer_show_meters = r.ImGui_Checkbox(mixer_ctx, "Mtrs##QT", settings.simple_mixer_show_meters ~= false)
   if rv then changed = true end
   r.ImGui_TableNextColumn(mixer_ctx)
   rv, settings.simple_mixer_show_vu_meter = r.ImGui_Checkbox(mixer_ctx, "VU##QT", settings.simple_mixer_show_vu_meter or false)
   if rv then changed = true end
   r.ImGui_TableNextRow(mixer_ctx)
   r.ImGui_TableNextColumn(mixer_ctx)
   rv, settings.simple_mixer_show_fx_slots = r.ImGui_Checkbox(mixer_ctx, "FX##QT", settings.simple_mixer_show_fx_slots or false)
   if rv then changed = true end
   r.ImGui_TableNextColumn(mixer_ctx)
   rv, settings.simple_mixer_show_master = r.ImGui_Checkbox(mixer_ctx, "Mstr##QT", settings.simple_mixer_show_master or false)
   if rv then changed = true end
   r.ImGui_TableNextRow(mixer_ctx)
   r.ImGui_TableNextColumn(mixer_ctx)
   rv, settings.simple_mixer_show_track_icons = r.ImGui_Checkbox(mixer_ctx, "Icon##QT", settings.simple_mixer_show_track_icons ~= false)
   if rv then changed = true end
   r.ImGui_TableNextColumn(mixer_ctx)
   rv, settings.simple_mixer_use_track_color = r.ImGui_Checkbox(mixer_ctx, "TClr##QT", settings.simple_mixer_use_track_color ~= false)
   if rv then changed = true end
   r.ImGui_TableNextRow(mixer_ctx)
   r.ImGui_TableNextColumn(mixer_ctx)
   rv, settings.simple_mixer_show_pinned_first = r.ImGui_Checkbox(mixer_ctx, "Pin##QT", settings.simple_mixer_show_pinned_first or false)
   if rv then changed = true end
   r.ImGui_TableNextColumn(mixer_ctx)
   local show_dividers = not settings.simple_mixer_hide_all_dividers
   rv, show_dividers = r.ImGui_Checkbox(mixer_ctx, "Divdr##QT", show_dividers)
   if rv then
    settings.simple_mixer_hide_all_dividers = not show_dividers
    changed = true
   end
   r.ImGui_EndTable(mixer_ctx)
   if changed then SaveMixerSettings() end
  end
 end
 local num_sel = r.CountSelectedTracks(0)
 if num_sel == 1 then
  local sel_track = r.GetSelectedTrack(0, 0)
  if sel_track then
   r.ImGui_Spacing(mixer_ctx)
   r.ImGui_Separator(mixer_ctx)
   r.ImGui_Spacing(mixer_ctx)
   local track_num = math.floor(r.GetMediaTrackInfo_Value(sel_track, "IP_TRACKNUMBER"))
   local _, sel_track_name = r.GetTrackName(sel_track)
   local track_color = r.GetTrackColor(sel_track)
   local cx, cy = r.ImGui_GetCursorScreenPos(mixer_ctx)
   local draw_list = r.ImGui_GetWindowDrawList(mixer_ctx)
   local color_box_size = 12
   if track_color ~= 0 then
    local rv, gv, bv = r.ColorFromNative(track_color)
    local imgui_color = r.ImGui_ColorConvertDouble4ToU32(rv/255, gv/255, bv/255, 1.0)
    r.ImGui_DrawList_AddRectFilled(draw_list, cx, cy + 2, cx + color_box_size, cy + 2 + color_box_size, imgui_color, 2)
    r.ImGui_SetCursorPosX(mixer_ctx, r.ImGui_GetCursorPosX(mixer_ctx) + color_box_size + 4)
   end
   r.ImGui_Text(mixer_ctx, track_num .. ": " .. sel_track_name)
   r.ImGui_Spacing(mixer_ctx)
   if DrawSectionHeader(mixer_ctx, "Input", "simple_mixer_input_open", sidebar_width) then
    InputSelector:Draw(mixer_ctx, sel_track)
   end
   r.ImGui_Spacing(mixer_ctx)
   if DrawSectionHeader(mixer_ctx, "Output", "simple_mixer_output_open", sidebar_width) then
    OutputSelector:Draw(mixer_ctx, sel_track)
   end
   r.ImGui_Spacing(mixer_ctx)
   if DrawSectionHeader(mixer_ctx, "Input FX", "simple_mixer_inputfx_open", sidebar_width) then
    r.ImGui_Indent(mixer_ctx, 5)
    local input_fx_count = r.TrackFX_GetRecCount(sel_track)
    local all_infx_enabled = true
    for i = 0, input_fx_count - 1 do
     if not r.TrackFX_GetEnabled(sel_track, 0x1000000 + i) then
      all_infx_enabled = false
      break
     end
    end
    if input_fx_count == 0 then all_infx_enabled = false end
    local rv_infx, new_infx = r.ImGui_Checkbox(mixer_ctx, "All InFX Enabled", all_infx_enabled)
    if rv_infx then
     for i = 0, input_fx_count - 1 do
      r.TrackFX_SetEnabled(sel_track, 0x1000000 + i, new_infx)
     end
    end
    if r.ImGui_IsItemHovered(mixer_ctx) then
     r.ImGui_SetTooltip(mixer_ctx, "Enable/Bypass all Input FX at once")
    end
    r.ImGui_Text(mixer_ctx, "FX: " .. input_fx_count)
    r.ImGui_SameLine(mixer_ctx)
    if r.ImGui_SmallButton(mixer_ctx, "+##AddInputFX") then
     r.SetOnlyTrackSelected(sel_track)
     r.Main_OnCommand(40844, 0)
    end
    if r.ImGui_IsItemHovered(mixer_ctx) then
     r.ImGui_SetTooltip(mixer_ctx, "Open Input FX Chain")
    end
    r.ImGui_SameLine(mixer_ctx)
    if r.ImGui_SmallButton(mixer_ctx, "Show##ShowInputFX") then
     r.SetOnlyTrackSelected(sel_track)
     r.Main_OnCommand(40844, 0)
    end
    if r.ImGui_IsItemHovered(mixer_ctx) then
     r.ImGui_SetTooltip(mixer_ctx, "Show Input FX Chain window")
    end
    if input_fx_count > 0 then
     r.ImGui_Spacing(mixer_ctx)
     for i = 0, input_fx_count - 1 do
      local _, fx_name = r.TrackFX_GetFXName(sel_track, 0x1000000 + i, "")
      local short_name = fx_name:match("^[^%(]+") or fx_name
      if #short_name > 15 then short_name = short_name:sub(1, 14) .. "..." end
      local fx_enabled = r.TrackFX_GetEnabled(sel_track, 0x1000000 + i)
      r.ImGui_PushID(mixer_ctx, "infx" .. i)
      local btn_color = fx_enabled and 0x4A7A4AFF or 0x7A4A4AFF
      r.ImGui_PushStyleColor(mixer_ctx, r.ImGui_Col_Button(), btn_color)
      local alt_held = r.ImGui_IsKeyDown(mixer_ctx, r.ImGui_Mod_Alt())
      if r.ImGui_Button(mixer_ctx, short_name, sidebar_width - 30, 0) then
       if alt_held then
        r.TrackFX_Delete(sel_track, 0x1000000 + i)
       else
        r.TrackFX_SetOpen(sel_track, 0x1000000 + i, true)
       end
      end
      r.ImGui_PopStyleColor(mixer_ctx, 1)
      if r.ImGui_IsItemClicked(mixer_ctx, r.ImGui_MouseButton_Right()) then
       r.TrackFX_SetEnabled(sel_track, 0x1000000 + i, not fx_enabled)
      end
      if r.ImGui_IsItemHovered(mixer_ctx) then
       r.ImGui_SetTooltip(mixer_ctx, fx_name .. "\nClick: Open FX\nAlt+Click: Delete FX\nRight-click: Bypass")
      end
      r.ImGui_PopID(mixer_ctx)
     end
    end
    r.ImGui_Unindent(mixer_ctx, 5)
   end
   r.ImGui_Spacing(mixer_ctx)
   if DrawSectionHeader(mixer_ctx, "Record Mode", "simple_mixer_recmode_open", sidebar_width) then
    RecordModeSelector:Draw(mixer_ctx, sel_track)
   end
  end
 end
end

local simple_mixer_last_clicked_track_idx = nil
local simple_mixer_track_fx_heights = {}

local function DrawRoutingIndicator(ctx, draw_list, x, y, width, track, track_guid)
 local routing_order = settings.simple_mixer_strip_routing_order or 0
 local show_eq = settings.simple_mixer_show_eq
 local show_comp = settings.simple_mixer_show_compressor
 local show_lim = settings.simple_mixer_show_limiter
 if not (show_eq or show_comp or show_lim) then return 0 end
 local eq_bypassed = false
 local comp_bypassed = false
 local lim_bypassed = false
 if track then
  local fx_index = FindChannelStripFX(track, track_guid)
  if fx_index and fx_index >= 0 then
   eq_bypassed = r.TrackFX_GetParam(track, fx_index, STRIP_OFFSET.EQ_BYPASS) < 0.5
   comp_bypassed = r.TrackFX_GetParam(track, fx_index, STRIP_OFFSET.COMP_BYPASS) < 0.5
   lim_bypassed = r.TrackFX_GetParam(track, fx_index, STRIP_OFFSET.LIM_BYPASS) < 0.5
  end
 end
 local routing_labels = {
  [0] = {"EQ", "Comp", "Limit"},
  [1] = {"Comp", "EQ", "Limit"},
  [2] = {"EQ", "Limit", "Comp"},
  [3] = {"Comp", "Limit", "EQ"},
  [4] = {"Limit", "EQ", "Comp"},
  [5] = {"Limit", "Comp", "EQ"}
 }
 local labels = routing_labels[routing_order] or routing_labels[0]
 local indicator_height = 18
 local font_size = 7
 local title_font_size = 6
 local title_str = "TKCS 25-ECL"
 local base_title_w = r.ImGui_CalcTextSize(ctx, title_str)
 local title_scale = title_font_size / r.ImGui_GetFontSize(ctx)
 local title_w = base_title_w * title_scale
 local title_x = x + (width - title_w) / 2
 local title_y = y + 1
 r.ImGui_DrawList_AddTextEx(draw_list, nil, title_font_size, title_x, title_y, 0x666666FF, title_str)
 local scale = font_size / r.ImGui_GetFontSize(ctx)
 local separator = " > "
 local sep_w = r.ImGui_CalcTextSize(ctx, separator) * scale
 local total_w = 0
 for i, lbl in ipairs(labels) do
  total_w = total_w + r.ImGui_CalcTextSize(ctx, lbl) * scale
  if i < #labels then total_w = total_w + sep_w end
 end
 local text_x = x + (width - total_w) / 2
 local text_y = y + 9
 for i, lbl in ipairs(labels) do
  local is_visible = (lbl == "EQ" and show_eq) or (lbl == "Comp" and show_comp) or (lbl == "Limit" and show_lim)
  local is_bypassed = (lbl == "EQ" and eq_bypassed) or (lbl == "Comp" and comp_bypassed) or (lbl == "Limit" and lim_bypassed)
  local label_color
  if not is_visible then
   label_color = 0xFFFFFFFF
  elseif is_bypassed then
   label_color = 0xFF8800FF
  else
   label_color = 0x00FF00FF
  end
  local lbl_w = r.ImGui_CalcTextSize(ctx, lbl) * scale
  r.ImGui_DrawList_AddTextEx(draw_list, nil, font_size, text_x, text_y, label_color, lbl)
  text_x = text_x + lbl_w
  if i < #labels then
   r.ImGui_DrawList_AddTextEx(draw_list, nil, font_size, text_x, text_y, 0x666666FF, separator)
   text_x = text_x + sep_w
  end
 end
 return indicator_height
end

local IconBrowser
do
 local ok, mod = pcall(require, "icon_browser")
 if ok and type(mod) == "table" then
  IconBrowser = mod
 else
  IconBrowser = { show_window = false, SetBrowseMode = function(_) end, Show = function() end }
 end
end
local function GetMixerIconPath(track)
 local _, ext_icon = r.GetSetMediaTrackInfo_String(track, "P_EXT:" .. TCP_ICON_EXT_KEY, "", false)
 if ext_icon ~= "" then return ext_icon end
 local _, icon = r.GetSetMediaTrackInfo_String(track, "P_ICON", "", false)
 return icon ~= "" and icon or nil
end
local function ClearTrackIconCache(track)
 local guid = r.GetTrackGUID(track)
 if guid then
  simple_mixer_track_icon_cache[guid] = nil
  simple_mixer_track_icon_paths[guid] = nil
 end
end

local track_lock_cache = {}
local function IsTrackLocked(track)
 local guid = r.GetTrackGUID(track)
 local now = r.time_precise()
 local entry = track_lock_cache[guid]
 if entry and (now - entry.t) < 0.5 then
  return entry.locked
 end
 local _, chunk = r.GetTrackStateChunk(track, "", false)
 local locked = false
 if chunk then
  local lock_val = chunk:match("\nLOCK (%d+)")
  if lock_val and (tonumber(lock_val) or 0) > 0 then
   locked = true
  end
 end
 track_lock_cache[guid] = { t = now, locked = locked }
 return locked
end

local function DrawLockIcon(draw_list, x, y, size, color)
 local body_h = size * 0.55
 local body_w = size * 0.75
 local body_x = x + (size - body_w) / 2
 local body_y = y + size - body_h
 r.ImGui_DrawList_AddRectFilled(draw_list, body_x, body_y, body_x + body_w, body_y + body_h, color, 1)
 local shackle_r = body_w * 0.32
 local shackle_cx = x + size / 2
 local shackle_cy = body_y
 local thickness = math.max(1, size * 0.12)
 r.ImGui_DrawList_PathArcTo(draw_list, shackle_cx, shackle_cy, shackle_r, math.pi, math.pi * 2, 12)
 r.ImGui_DrawList_PathStroke(draw_list, color, 0, thickness)
end

local function DrawFolderIcon(draw_list, x, y, size, color)
 local w = size * 0.95
 local h = size * 0.7
 local fx = x + (size - w) / 2
 local fy = y + (size - h) / 2
 local tab_w = w * 0.4
 local tab_h = h * 0.22
 r.ImGui_DrawList_AddRectFilled(draw_list, fx, fy, fx + tab_w, fy + tab_h + 1, color, 1)
 r.ImGui_DrawList_AddRectFilled(draw_list, fx, fy + tab_h, fx + w, fy + h, color, 1)
end

local function GetTrackBlockEnd(start_idx)
 local depth = 0
 local total = r.CountTracks(0)
 local i = start_idx
 while i < total do
  local t = r.GetTrack(0, i)
  local fd = r.GetMediaTrackInfo_Value(t, "I_FOLDERDEPTH")
  depth = depth + fd
  if depth <= 0 then return i end
  i = i + 1
 end
 return total - 1
end

local function FindTrackByGUID(guid)
 if not guid or guid == "" then return nil, -1 end
 local total = r.CountTracks(0)
 for i = 0, total - 1 do
  local t = r.GetTrack(0, i)
  if r.GetTrackGUID(t) == guid then return t, i end
 end
 return nil, -1
end

local function MoveTrackBlock(src_guid, target_track)
 local src_track, src_idx = FindTrackByGUID(src_guid)
 if not src_track or not target_track or not r.ValidatePtr(target_track, "MediaTrack*") then return end
 local tgt_idx = math.floor(r.GetMediaTrackInfo_Value(target_track, "IP_TRACKNUMBER")) - 1
 local block_end = GetTrackBlockEnd(src_idx)
 local block_size = block_end - src_idx + 1
 if tgt_idx >= src_idx and tgt_idx <= block_end then return end
 local final_tgt
 if tgt_idx > block_end then
  final_tgt = tgt_idx + 1
 else
  final_tgt = tgt_idx
 end
 r.PreventUIRefresh(1)
 r.Undo_BeginBlock()
 local saved_sel = {}
 for i = 0, r.CountTracks(0) - 1 do
  local t = r.GetTrack(0, i)
  if r.IsTrackSelected(t) then saved_sel[#saved_sel + 1] = t end
 end
 r.Main_OnCommand(40297, 0)
 for i = src_idx, block_end do
  r.SetTrackSelected(r.GetTrack(0, i), true)
 end
 r.ReorderSelectedTracks(final_tgt, 0)
 r.Main_OnCommand(40297, 0)
 for _, t in ipairs(saved_sel) do
  if r.ValidatePtr(t, "MediaTrack*") then r.SetTrackSelected(t, true) end
 end
 r.Undo_EndBlock("TK Mixer: Reorder tracks", -1)
 r.PreventUIRefresh(-1)
 r.TrackList_AdjustWindows(false)
 r.UpdateArrange()
end

local function DrawMixerChannel(ctx, track, track_name, idx, track_width, base_slider_height, is_master, show_remove_button, show_fx_handle, folder_info)
 local should_remove = false
 local should_delete = false
 local should_delete_selected = false
 folder_info = folder_info or {}
 local is_folder = folder_info.is_folder or false
 local is_child = folder_info.is_child or false
 local folder_color = folder_info.folder_color or 0
 local is_locked = (not is_master) and IsTrackLocked(track)
 
 local track_guid_for_fx = is_master and "master" or r.GetTrackGUID(track)
 local track_fx_height = 0
 local fx_divider_height = 0
 if settings.simple_mixer_show_fx_slots and not settings.simple_mixer_fx_section_collapsed then
  track_fx_height = (mixer_state.track_fx_heights[track_guid_for_fx] or settings.simple_mixer_fx_section_height or 80) + 4
  fx_divider_height = 6
 end
 local track_number_height = 18
 local vu_meter_height = 0
 if settings.simple_mixer_show_vu_meter then
  vu_meter_height = 49 + 4
 end
 local comp_module_height = 0
 if settings.simple_mixer_show_compressor then
  comp_module_height = 120 + 4
 end
 local lim_module_height = 0
 if settings.simple_mixer_show_limiter then
  lim_module_height = 120 + 4
 end
 local trim_module_height = 0
 if settings.simple_mixer_show_trim then
  trim_module_height = 38 + 4
 end
 local eq_module_height = 0
 if settings.simple_mixer_show_eq then
  eq_module_height = 184 + 4
 end
 local rms_height = 0
 if settings.simple_mixer_show_rms then
  rms_height = 24
 end
 local pan_height = 0
 if settings.simple_mixer_show_pan then
  pan_height = 14
 end
 local width_height = 0
 if settings.simple_mixer_show_width then
  width_height = 14
 end
 local buttons_height = 0
 if settings.simple_mixer_show_track_buttons then
  buttons_height = (settings.simple_mixer_track_buttons_height or 16) + 4
 end
 local fx_handle_height = 0
 if settings.simple_mixer_show_fx_slots and show_fx_handle then
  fx_handle_height = 8
 end
 local name_height = 20
 
 local icon_section_height = 0
 if settings.simple_mixer_show_track_icons and settings.simple_mixer_track_icon_position == "section" and not is_master then
  icon_section_height = (settings.simple_mixer_track_icon_section_height or 40) + 4
 end
 
 local routing_indicator_height = 0
 local has_strip_modules = settings.simple_mixer_show_eq or settings.simple_mixer_show_compressor or settings.simple_mixer_show_limiter
 if has_strip_modules then
  routing_indicator_height = 18 + 4
 end
 
 local fixed_padding = 14
 if not settings.simple_mixer_show_fx_slots then
  fixed_padding = fixed_padding - 4
 elseif not settings.simple_mixer_fx_section_collapsed then
  fixed_padding = fixed_padding - 4
 end
 local slider_height = base_slider_height - track_fx_height - track_number_height - vu_meter_height - comp_module_height - lim_module_height - trim_module_height - eq_module_height - fx_divider_height - rms_height - pan_height - width_height - buttons_height - fx_handle_height - name_height - routing_indicator_height - icon_section_height - fixed_padding
 if slider_height < 50 then slider_height = 50 end
 
 r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), settings.simple_mixer_channel_rounding or 0)
 r.ImGui_BeginGroup(ctx)
 r.ImGui_PushID(ctx, is_master and "master" or idx)

 if not is_master then
  local track_number = math.floor(r.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER"))
  local track_number_str = tostring(track_number)
  local track_color = r.GetTrackColor(track)
  local is_selected = r.IsTrackSelected(track)
  local bg_color = 0x404040FF
  if track_color ~= 0 then
   local r_val, g_val, b_val = r.ColorFromNative(track_color)
   if is_selected then
    r_val = math.min(255, r_val + (255 - r_val) * 0.4)
    g_val = math.min(255, g_val + (255 - g_val) * 0.4)
    b_val = math.min(255, b_val + (255 - b_val) * 0.4)
   end
   bg_color = r.ImGui_ColorConvertDouble4ToU32(r_val/255, g_val/255, b_val/255, 0.9)
  else
   if is_selected then
    bg_color = 0x606060FF
   end
  end
  local draw_list = r.ImGui_GetWindowDrawList(ctx)
  local cx, cy = r.ImGui_GetCursorScreenPos(ctx)
  local num_height = 18
  r.ImGui_DrawList_AddRectFilled(draw_list, cx, cy, cx + track_width, cy + num_height, bg_color, 2)
  local text_w = r.ImGui_CalcTextSize(ctx, track_number_str)
  local text_x = cx + (track_width - text_w) / 2
  local text_y = cy + (num_height - r.ImGui_GetTextLineHeight(ctx)) / 2
  local text_color = settings.simple_mixer_channel_text_color or 0xFFFFFFFF
  r.ImGui_DrawList_AddText(draw_list, text_x, text_y, text_color, track_number_str)
  if IsTrackLocked(track) then
   local icon_size = num_height - 6
   local icon_x = cx + track_width - icon_size - 3
   local icon_y = cy + (num_height - icon_size) / 2
   DrawLockIcon(draw_list, icon_x, icon_y, icon_size, text_color)
  end
  if is_folder then
   local icon_size = num_height - 6
   local icon_x = cx + 3
   local icon_y = cy + (num_height - icon_size) / 2
   DrawFolderIcon(draw_list, icon_x, icon_y, icon_size, text_color)
  end
  r.ImGui_SetCursorScreenPos(ctx, cx, cy)
  r.ImGui_InvisibleButton(ctx, "##track_num_" .. track_number_str, track_width, num_height)
  if r.ImGui_BeginDragDropSource(ctx) then
   r.ImGui_SetDragDropPayload(ctx, "TK_TRACK_REORDER", r.GetTrackGUID(track))
   local label = "Move: " .. (track_name ~= "" and track_name or ("Track " .. track_number_str))
   r.ImGui_Text(ctx, label)
   r.ImGui_EndDragDropSource(ctx)
  end
  if r.ImGui_BeginDragDropTarget(ctx) then
   local accepted, payload = r.ImGui_AcceptDragDropPayload(ctx, "TK_TRACK_REORDER")
   if accepted and payload and payload ~= "" then
    MoveTrackBlock(payload, track)
   end
   r.ImGui_EndDragDropTarget(ctx)
  end
  if r.ImGui_IsItemClicked(ctx, 0) then
   local ctrl = r.ImGui_IsKeyDown(ctx, r.ImGui_Mod_Ctrl())
   local shift = r.ImGui_IsKeyDown(ctx, r.ImGui_Mod_Shift())
   local track_idx = r.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER") - 1
   if shift and mixer_state.last_clicked_track_idx then
    local from_idx = math.min(mixer_state.last_clicked_track_idx, track_idx)
    local to_idx = math.max(mixer_state.last_clicked_track_idx, track_idx)
    for i = from_idx, to_idx do
     local t = r.GetTrack(0, i)
     if t then r.SetTrackSelected(t, true) end
    end
   elseif ctrl then
    r.SetTrackSelected(track, not r.IsTrackSelected(track))
   else
    r.SetOnlyTrackSelected(track)
   end
   mixer_state.last_clicked_track_idx = track_idx
  end
  if r.ImGui_IsItemClicked(ctx, r.ImGui_MouseButton_Right()) then
   r.ImGui_OpenPopup(ctx, "FaderContextMenu##" .. idx)
  end
  
  if is_locked then r.ImGui_BeginDisabled(ctx) end
  
  if settings.simple_mixer_show_vu_meter then
   local vu_cx, vu_cy = r.ImGui_GetCursorScreenPos(ctx)
   local track_guid = r.GetTrackGUID(track)
   local vu_height = DrawVUMeter(ctx, draw_list, vu_cx, vu_cy, track_width, settings.simple_mixer_vu_height or 8, track_guid, track)
   if vu_height > 0 then
    r.ImGui_Dummy(ctx, track_width, vu_height)
   end
  end
  
  if has_strip_modules then
   local ri_cx, ri_cy = r.ImGui_GetCursorScreenPos(ctx)
   local track_guid = r.GetTrackGUID(track)
   local ri_h = DrawRoutingIndicator(ctx, draw_list, ri_cx, ri_cy, track_width, track, track_guid)
   if ri_h > 0 then
    r.ImGui_Dummy(ctx, track_width, ri_h)
   end
  end
  
  if settings.simple_mixer_show_trim then
   local trim_cx, trim_cy = r.ImGui_GetCursorScreenPos(ctx)
   local track_guid = r.GetTrackGUID(track)
   local trim_h = Trim.DrawModule(ctx, draw_list, trim_cx, trim_cy, track_width, track_guid, track)
   if trim_h > 0 then
    r.ImGui_Dummy(ctx, track_width, trim_h)
   end
  end
  
  if settings.simple_mixer_show_eq then
   local eq_cx, eq_cy = r.ImGui_GetCursorScreenPos(ctx)
   local track_guid = r.GetTrackGUID(track)
   local eq_h = EQ.DrawModule(ctx, draw_list, eq_cx, eq_cy, track_width, 68, track_guid, track)
   if eq_h > 0 then
    r.ImGui_Dummy(ctx, track_width, eq_h)
   end
  end
  
  if settings.simple_mixer_show_compressor then
   local comp_cx, comp_cy = r.ImGui_GetCursorScreenPos(ctx)
   local track_guid = r.GetTrackGUID(track)
   local comp_h = DrawCompressorModule(ctx, draw_list, comp_cx, comp_cy, track_width, settings.simple_mixer_comp_height or 90, track_guid, track)
   if comp_h > 0 then
    r.ImGui_Dummy(ctx, track_width, comp_h)
   end
  end
  
  if settings.simple_mixer_show_limiter then
   local lim_cx, lim_cy = r.ImGui_GetCursorScreenPos(ctx)
   local track_guid = r.GetTrackGUID(track)
   local lim_h = Limiter.DrawModule(ctx, draw_list, lim_cx, lim_cy, track_width, settings.simple_mixer_lim_height or 120, track_guid, track)
   if lim_h > 0 then
    r.ImGui_Dummy(ctx, track_width, lim_h)
   end
  end
 else
  local master_col = settings.simple_mixer_master_fader_color or 0x4A90D9FF
  local draw_list = r.ImGui_GetWindowDrawList(ctx)
  local cx, cy = r.ImGui_GetCursorScreenPos(ctx)
  local num_height = 18
  r.ImGui_DrawList_AddRectFilled(draw_list, cx, cy, cx + track_width, cy + num_height, master_col, 2)
  local label_text = "MASTER"
  local label_w = r.ImGui_CalcTextSize(ctx, label_text)
  local text_x = cx + (track_width - label_w) / 2
  local text_y = cy + (num_height - r.ImGui_GetTextLineHeight(ctx)) / 2
  r.ImGui_DrawList_AddText(draw_list, text_x, text_y, 0xFFFFFFFF, label_text)
  r.ImGui_SetCursorScreenPos(ctx, cx, cy)
  r.ImGui_InvisibleButton(ctx, "##master_label", track_width, num_height)
  if r.ImGui_IsItemClicked(ctx, r.ImGui_MouseButton_Right()) then
   r.ImGui_OpenPopup(ctx, "FaderContextMenu##master")
  end
  
  if settings.simple_mixer_show_vu_meter then
   local vu_cx, vu_cy = r.ImGui_GetCursorScreenPos(ctx)
   local master_guid = "master"
   local vu_height = DrawVUMeter(ctx, draw_list, vu_cx, vu_cy, track_width, settings.simple_mixer_vu_height or 8, master_guid, track)
   if vu_height > 0 then
    r.ImGui_Dummy(ctx, track_width, vu_height)
   end
  end
  
  if has_strip_modules then
   local ri_cx, ri_cy = r.ImGui_GetCursorScreenPos(ctx)
   local ri_h = DrawRoutingIndicator(ctx, draw_list, ri_cx, ri_cy, track_width, track, "master")
   if ri_h > 0 then
    r.ImGui_Dummy(ctx, track_width, ri_h)
   end
  end
  
  if settings.simple_mixer_show_trim then
   local trim_cx, trim_cy = r.ImGui_GetCursorScreenPos(ctx)
   local trim_h = Trim.DrawModule(ctx, draw_list, trim_cx, trim_cy, track_width, "master", track)
   if trim_h > 0 then
    r.ImGui_Dummy(ctx, track_width, trim_h)
   end
  end
  
  if settings.simple_mixer_show_eq then
   local eq_cx, eq_cy = r.ImGui_GetCursorScreenPos(ctx)
   local eq_h = EQ.DrawModule(ctx, draw_list, eq_cx, eq_cy, track_width, 68, "master", track)
   if eq_h > 0 then
    r.ImGui_Dummy(ctx, track_width, eq_h)
   end
  end
  
  if settings.simple_mixer_show_compressor then
   local comp_cx, comp_cy = r.ImGui_GetCursorScreenPos(ctx)
   local comp_h = DrawCompressorModule(ctx, draw_list, comp_cx, comp_cy, track_width, settings.simple_mixer_comp_height or 90, "master", track)
   if comp_h > 0 then
    r.ImGui_Dummy(ctx, track_width, comp_h)
   end
  end
  
  if settings.simple_mixer_show_limiter then
   local lim_cx, lim_cy = r.ImGui_GetCursorScreenPos(ctx)
   local lim_h = Limiter.DrawModule(ctx, draw_list, lim_cx, lim_cy, track_width, settings.simple_mixer_lim_height or 120, "master", track)
   if lim_h > 0 then
    r.ImGui_Dummy(ctx, track_width, lim_h)
   end
  end
 end

 local rms_position = settings.simple_mixer_rms_position or "top"
 if settings.simple_mixer_show_rms and rms_position == "top" then
  local is_muted = r.GetMediaTrackInfo_Value(track, "B_MUTE") == 1
  local rms_off_color = settings.simple_mixer_rms_button_off_color or 0x404040FF
  local rms_text_color = settings.simple_mixer_rms_text_color or 0xFFFFFFFF
  
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), rms_text_color)
  
  if is_master then
   r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), is_muted and 0xFF6666FF or rms_off_color)
   if r.ImGui_Button(ctx, "M##rms_top", track_width, 20) then
    r.SetMediaTrackInfo_Value(track, "B_MUTE", is_muted and 0 or 1)
   end
   r.ImGui_PopStyleColor(ctx, 1)
  else
   local is_armed = r.GetMediaTrackInfo_Value(track, "I_RECARM") == 1
   local is_solo = r.GetMediaTrackInfo_Value(track, "I_SOLO") > 0
   local rms_btn_width = (track_width - 6) / 3

   r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), is_armed and 0xFF0000FF or rms_off_color)
   if r.ImGui_Button(ctx, "R##rms_top", rms_btn_width, 20) then
    r.SetMediaTrackInfo_Value(track, "I_RECARM", is_armed and 0 or 1)
   end
   r.ImGui_PopStyleColor(ctx, 1)

   r.ImGui_SameLine(ctx, 0, 3)

   r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), is_muted and 0xFF6666FF or rms_off_color)
   if r.ImGui_Button(ctx, "M##rms_top", rms_btn_width, 20) then
    r.SetMediaTrackInfo_Value(track, "B_MUTE", is_muted and 0 or 1)
   end
   r.ImGui_PopStyleColor(ctx, 1)

   r.ImGui_SameLine(ctx, 0, 3)

   r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), is_solo and 0xFF8800FF or rms_off_color)
   if r.ImGui_Button(ctx, "S##rms_top", rms_btn_width, 20) then
    if r.ImGui_IsKeyDown(ctx, r.ImGui_Mod_Shift()) then
     for i = 0, r.CountTracks(0) - 1 do
      local tr = r.GetTrack(0, i)
      if tr ~= track then
       r.SetMediaTrackInfo_Value(tr, "I_SOLO", 0)
      end
     end
     r.SetMediaTrackInfo_Value(track, "I_SOLO", 1)
    else
     r.SetMediaTrackInfo_Value(track, "I_SOLO", is_solo and 0 or 1)
    end
   end
   if r.ImGui_IsItemHovered(ctx) then
    r.ImGui_SetTooltip(ctx, "Solo\nShift+Click: Exclusive Solo")
   end
   r.ImGui_PopStyleColor(ctx, 1)
  end
  
  r.ImGui_PopStyleColor(ctx, 1)
 end

 local pan_slider_height = 10
 local slider_grab_width = 6
 local control_bg_col = settings.simple_mixer_control_bg_color or 0x333333FF
 local slider_grab_col = settings.simple_mixer_slider_handle_color or 0x888888FF
 local slider_grab_active_col = 0xAAAAAAFF
 
 if settings.simple_mixer_show_pan then
  local pan = r.GetMediaTrackInfo_Value(track, "D_PAN")
  local x, y = r.ImGui_GetCursorScreenPos(ctx)
  
  r.ImGui_InvisibleButton(ctx, "##pan_slider", track_width, pan_slider_height)
  local is_active = r.ImGui_IsItemActive(ctx)
  local is_hovered = r.ImGui_IsItemHovered(ctx)
  
  if is_active then
   local mx = r.ImGui_GetMousePos(ctx)
   local new_pan = ((mx - x) / track_width) * 2 - 1
   new_pan = math.max(-1, math.min(1, new_pan))
   r.SetMediaTrackInfo_Value(track, "D_PAN", new_pan)
   pan = new_pan
  end
  
  if r.ImGui_IsItemClicked(ctx, r.ImGui_MouseButton_Right()) then
   r.SetMediaTrackInfo_Value(track, "D_PAN", 0.0)
   pan = 0.0
  end
  
  local draw_list = r.ImGui_GetWindowDrawList(ctx)
  r.ImGui_DrawList_AddRectFilled(draw_list, x, y, x + track_width, y + pan_slider_height, control_bg_col, 2)
  
  local grab_x = x + ((pan + 1) / 2) * (track_width - slider_grab_width)
  local grab_col = is_active and slider_grab_active_col or slider_grab_col
  r.ImGui_DrawList_AddRectFilled(draw_list, grab_x, y, grab_x + slider_grab_width, y + pan_slider_height, grab_col, 2)

  if is_hovered then
   local pan_text
   if math.abs(pan) < 0.01 then
    pan_text = "Center"
   elseif pan < 0 then
    pan_text = string.format("%.0f%% L", math.abs(pan) * 100)
   else
    pan_text = string.format("%.0f%% R", pan * 100)
   end
   r.ImGui_SetTooltip(ctx, "Pan: " .. pan_text .. " (Right-click to reset)")
  end
 end

 if settings.simple_mixer_show_width then
  local width = r.GetMediaTrackInfo_Value(track, "D_WIDTH")
  local x, y = r.ImGui_GetCursorScreenPos(ctx)
  
  r.ImGui_InvisibleButton(ctx, "##width_slider", track_width, pan_slider_height)
  local is_active = r.ImGui_IsItemActive(ctx)
  local is_hovered = r.ImGui_IsItemHovered(ctx)
  
  if is_active then
   local mx = r.ImGui_GetMousePos(ctx)
   local new_width = ((mx - x) / track_width) * 2 - 1
   new_width = math.max(-1, math.min(1, new_width))
   r.SetMediaTrackInfo_Value(track, "D_WIDTH", new_width)
   width = new_width
  end
  
  if r.ImGui_IsItemClicked(ctx, r.ImGui_MouseButton_Right()) then
   r.SetMediaTrackInfo_Value(track, "D_WIDTH", 1.0)
   width = 1.0
  end
  
  local draw_list = r.ImGui_GetWindowDrawList(ctx)
  r.ImGui_DrawList_AddRectFilled(draw_list, x, y, x + track_width, y + pan_slider_height, control_bg_col, 2)
  
  local grab_x = x + ((width + 1) / 2) * (track_width - slider_grab_width)
  local grab_col = is_active and slider_grab_active_col or slider_grab_col
  r.ImGui_DrawList_AddRectFilled(draw_list, grab_x, y, grab_x + slider_grab_width, y + pan_slider_height, grab_col, 2)

  if is_hovered then
   local width_pct = math.abs(width) * 100
   local width_text
   if width == 0 then
    width_text = "Mono"
   elseif width < 0 then
    width_text = string.format("%.0f%% (Swapped)", width_pct)
   elseif width == 1 then
    width_text = "100% (Stereo)"
   else
    width_text = string.format("%.0f%%", width_pct)
   end
   r.ImGui_SetTooltip(ctx, "Width: " .. width_text .. " (Right-click to reset)")
  end
 end

 if settings.simple_mixer_show_track_buttons then
  local btn_height = settings.simple_mixer_track_buttons_height or 16
  local btn_width = (track_width - 8) / 5
  local is_phase_inverted = r.GetMediaTrackInfo_Value(track, "B_PHASE") == 1
  local icon_color = settings.simple_mixer_icon_color or 0xAAAAAAFF
  
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), control_bg_col)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0x44444488)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0x66666688)
  
  local btn_x, btn_y = r.ImGui_GetCursorScreenPos(ctx)
  if r.ImGui_Button(ctx, "##phase", btn_width, btn_height) then
   r.SetMediaTrackInfo_Value(track, "B_PHASE", is_phase_inverted and 0 or 1)
  end
  if r.ImGui_IsItemHovered(ctx) then
   r.ImGui_SetTooltip(ctx, "Toggle Phase (" .. (is_phase_inverted and "Inverted" or "Normal") .. ")")
  end
  
  local draw_list = r.ImGui_GetWindowDrawList(ctx)
  local cx = btn_x + btn_width / 2
  local cy = btn_y + btn_height / 2
  local line_size = math.min(btn_width, btn_height) / 2 - 2
  local radius = line_size * 0.65
  local phase_color = is_phase_inverted and 0xFF6666FF or icon_color
  r.ImGui_DrawList_AddCircle(draw_list, cx, cy, radius, phase_color, 12, 1.5)
  local offset = line_size * 0.85
  r.ImGui_DrawList_AddLine(draw_list, cx - offset, cy + offset, cx + offset, cy - offset, phase_color, 1.5)
  
  r.ImGui_SameLine(ctx, 0, 2)
  local mon_mode = r.GetMediaTrackInfo_Value(track, "I_RECMON")
  local mon_btn_x, mon_btn_y = r.ImGui_GetCursorScreenPos(ctx)
  if r.ImGui_Button(ctx, "##monitor", btn_width, btn_height) then
   local new_mode = (mon_mode + 1) % 3
   r.SetMediaTrackInfo_Value(track, "I_RECMON", new_mode)
  end
  local mon_names = {"Off", "On", "Auto"}
  if r.ImGui_IsItemHovered(ctx) then
   r.ImGui_SetTooltip(ctx, "Monitor: " .. mon_names[mon_mode + 1] .. "\nClick to cycle | Right-click for options")
  end
  if r.ImGui_IsItemClicked(ctx, r.ImGui_MouseButton_Right()) then
   r.ImGui_OpenPopup(ctx, "MonitorMenu##" .. idx)
  end
  if r.ImGui_BeginPopup(ctx, "MonitorMenu##" .. idx) then
   if r.ImGui_MenuItem(ctx, "Monitor Off", nil, mon_mode == 0) then
    r.SetMediaTrackInfo_Value(track, "I_RECMON", 0)
   end
   if r.ImGui_MenuItem(ctx, "Monitor Input", nil, mon_mode == 1) then
    r.SetMediaTrackInfo_Value(track, "I_RECMON", 1)
   end
   local is_tape_auto = mon_mode == 2
   if r.ImGui_MenuItem(ctx, "Monitor Input (Tape Auto Style)", nil, is_tape_auto) then
    r.SetMediaTrackInfo_Value(track, "I_RECMON", 2)
   end
   r.ImGui_Separator(ctx)
   local rec_mon_items = r.GetMediaTrackInfo_Value(track, "I_RECMONITEMS") == 1
   if r.ImGui_MenuItem(ctx, "Monitor track media when recording", nil, rec_mon_items) then
    r.SetMediaTrackInfo_Value(track, "I_RECMONITEMS", rec_mon_items and 0 or 1)
   end
   local preserve_pdc = r.GetMediaTrackInfo_Value(track, "B_MONITEM_PRESERVE_PDC") == 1
   if r.ImGui_MenuItem(ctx, "Preserve PDC delayed monitoring in recorded items", nil, preserve_pdc) then
    r.SetMediaTrackInfo_Value(track, "B_MONITEM_PRESERVE_PDC", preserve_pdc and 0 or 1)
   end
   r.ImGui_EndPopup(ctx)
  end
  
  local mon_cx = mon_btn_x + btn_width / 2
  local mon_cy = mon_btn_y + btn_height / 2
  local mon_size = math.min(btn_width, btn_height) / 2 - 2
  local mon_colors = {0x666666FF, 0x00FF00FF, 0xFFAA00FF}
  local mon_color = mon_colors[mon_mode + 1]
  local ear_w = mon_size * 0.3
  local ear_h = mon_size * 0.5
  local band_w = mon_size * 0.65
  local band_top = mon_cy - mon_size * 0.4
  r.ImGui_DrawList_AddBezierQuadratic(draw_list, mon_cx - band_w, band_top + ear_h * 0.3, mon_cx, band_top - mon_size * 0.3, mon_cx + band_w, band_top + ear_h * 0.3, mon_color, 2, 12)
  r.ImGui_DrawList_AddRectFilled(draw_list, mon_cx - band_w - ear_w/2, mon_cy - ear_h * 0.2, mon_cx - band_w + ear_w/2, mon_cy + ear_h * 0.8, mon_color, 2)
  r.ImGui_DrawList_AddRectFilled(draw_list, mon_cx + band_w - ear_w/2, mon_cy - ear_h * 0.2, mon_cx + band_w + ear_w/2, mon_cy + ear_h * 0.8, mon_color, 2)
  
  r.ImGui_SameLine(ctx, 0, 2)
  local route_btn_x, route_btn_y = r.ImGui_GetCursorScreenPos(ctx)
  if r.ImGui_Button(ctx, "##routing", btn_width, btn_height) then
   r.SetOnlyTrackSelected(track)
   r.Main_OnCommand(40293, 0)
  end
  if r.ImGui_IsItemHovered(ctx) then
   r.ImGui_SetTooltip(ctx, "Open Routing Window")
  end
  local route_cx = route_btn_x + btn_width / 2
  local route_cy = route_btn_y + btn_height / 2
  local route_size = math.min(btn_width, btn_height) / 2 - 2
  local route_color = icon_color
  local arrow_len = route_size * 0.5
  local arrow_head = route_size * 0.3
  r.ImGui_DrawList_AddLine(draw_list, route_cx, route_cy - arrow_len, route_cx, route_cy + arrow_len, route_color, 1.5)
  r.ImGui_DrawList_AddTriangleFilled(draw_list, route_cx, route_cy + arrow_len + arrow_head, route_cx - arrow_head * 0.7, route_cy + arrow_len - 1, route_cx + arrow_head * 0.7, route_cy + arrow_len - 1, route_color)
  r.ImGui_DrawList_AddLine(draw_list, route_cx - arrow_len * 0.8, route_cy - arrow_len * 0.6, route_cx + arrow_len * 0.8, route_cy - arrow_len * 0.6, route_color, 1.5)
  
  r.ImGui_SameLine(ctx, 0, 2)
  local env_btn_x, env_btn_y = r.ImGui_GetCursorScreenPos(ctx)
  if r.ImGui_Button(ctx, "##envelope", btn_width, btn_height) then
   r.SetOnlyTrackSelected(track)
   r.Main_OnCommand(42678, 0)
  end
  if r.ImGui_IsItemHovered(ctx) then
   r.ImGui_SetTooltip(ctx, "Show Envelope Window")
  end
  local env_cx = env_btn_x + btn_width / 2
  local env_cy = env_btn_y + btn_height / 2
  local env_size = math.min(btn_width, btn_height) / 2 - 2
  local env_color = icon_color
  local wave_amp = env_size * 0.7
  local wave_width = env_size * 0.9
  r.ImGui_DrawList_AddBezierCubic(draw_list, env_cx - wave_width, env_cy, env_cx - wave_width * 0.3, env_cy - wave_amp, env_cx + wave_width * 0.3, env_cy + wave_amp, env_cx + wave_width, env_cy, env_color, 1.5, 16)
  
  r.ImGui_SameLine(ctx, 0, 2)
  local fx_enabled = r.GetMediaTrackInfo_Value(track, "I_FXEN") == 1
  local fxbyp_btn_x, fxbyp_btn_y = r.ImGui_GetCursorScreenPos(ctx)
  if r.ImGui_Button(ctx, "##fxbypass", btn_width, btn_height) then
   r.SetMediaTrackInfo_Value(track, "I_FXEN", fx_enabled and 0 or 1)
  end
  if r.ImGui_IsItemHovered(ctx) then
   r.ImGui_SetTooltip(ctx, "FX " .. (fx_enabled and "Enabled" or "Bypassed") .. "\nClick to toggle all track FX")
  end
  local fxbyp_cx = fxbyp_btn_x + btn_width / 2
  local fxbyp_cy = fxbyp_btn_y + btn_height / 2
  local fxbyp_size = math.min(btn_width, btn_height) / 2 - 2
  local fxbyp_color = fx_enabled and icon_color or 0xFFAA00FF
  local box_size = fxbyp_size * 0.7
  r.ImGui_DrawList_AddRect(draw_list, fxbyp_cx - box_size, fxbyp_cy - box_size * 0.6, fxbyp_cx + box_size, fxbyp_cy + box_size * 0.6, fxbyp_color, 2, 0, 1.5)
  local knob_radius = box_size * 0.25
  r.ImGui_DrawList_AddCircleFilled(draw_list, fxbyp_cx - box_size * 0.4, fxbyp_cy, knob_radius, fxbyp_color, 8)
  r.ImGui_DrawList_AddCircleFilled(draw_list, fxbyp_cx + box_size * 0.4, fxbyp_cy, knob_radius, fxbyp_color, 8)
  
  r.ImGui_PopStyleColor(ctx, 3)
 end

 if settings.simple_mixer_show_fx_slots and not settings.simple_mixer_fx_section_collapsed then
  local fx_count = r.TrackFX_GetCount(track)
  local slot_height = settings.simple_mixer_fx_slot_height or 16
  local show_bypass = settings.simple_mixer_fx_show_bypass_button ~= false
  local bypass_btn_width = show_bypass and 16 or 0
  local fx_btn_width = track_width - (show_bypass and bypass_btn_width + 2 or 0)
  local section_height = mixer_state.track_fx_heights[track_guid_for_fx] or settings.simple_mixer_fx_section_height or 80

  local divider_x, divider_y = r.ImGui_GetCursorScreenPos(ctx)
  local tr_color = r.GetTrackColor(track)
  local divider_color = 0x444444FF
  if tr_color and tr_color ~= 0 then
   local r_val, g_val, b_val = r.ColorFromNative(tr_color)
   divider_color = r.ImGui_ColorConvertDouble4ToU32(r_val/255, g_val/255, b_val/255, 1.0)
  end
  local fx_draw_list = r.ImGui_GetWindowDrawList(ctx)
  r.ImGui_DrawList_AddLine(fx_draw_list, divider_x, divider_y, divider_x + track_width, divider_y, divider_color, 1)
  r.ImGui_Dummy(ctx, 0, 2)

  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ChildBg(), settings.simple_mixer_window_bg_color or 0x1E1E1EFF)
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing(), 0, 0)
  if r.ImGui_BeginChild(ctx, "FXSection##" .. (is_master and "master" or idx), track_width, section_height, 0, r.ImGui_WindowFlags_None()) then
   if r.ImGui_IsWindowHovered(ctx, r.ImGui_HoveredFlags_None()) then
    mixer_state.fx_section_hovered = true
   end
   for slot = 0, fx_count - 1 do
    r.ImGui_PushID(ctx, "fx_slot_" .. slot)
    
    local _, fx_name = r.TrackFX_GetFXName(track, slot, "")
    local is_enabled = r.TrackFX_GetEnabled(track, slot)
    local is_offline = r.TrackFX_GetOffline and r.TrackFX_GetOffline(track, slot) or false
    
    local slot_color
    if is_offline and settings.simple_mixer_fx_slot_show_offline ~= false then
     slot_color = settings.simple_mixer_fx_slot_offline_color or 0x553333FF
    elseif is_enabled then
     slot_color = settings.simple_mixer_fx_slot_active_color or 0x444444FF
    else
     slot_color = settings.simple_mixer_fx_slot_bypass_color or 0x666600FF
    end
    
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), slot_color)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), settings.simple_mixer_fx_slot_text_color or 0x888888FF)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ButtonTextAlign(), 0.0, 0.5)
    
    local fx_font_size = settings.simple_mixer_fx_font_size or 12
    if font_mixer then
     r.ImGui_PushFont(ctx, font_mixer, fx_font_size)
    end
    
    local short_name = fx_name:match("^[^:]+:%s*(.+)$") or fx_name
    local available_width = fx_btn_width - 4
    local text_width = r.ImGui_CalcTextSize(ctx, short_name)
    if text_width > available_width then
     local ellipsis = ".."
     local ellipsis_width = r.ImGui_CalcTextSize(ctx, ellipsis)
     local target_width = available_width - ellipsis_width
     while #short_name > 1 and r.ImGui_CalcTextSize(ctx, short_name) > target_width do
      short_name = short_name:sub(1, -2)
     end
     short_name = short_name .. ellipsis
    end
    
    if r.ImGui_Button(ctx, short_name .. "##fx" .. slot, fx_btn_width, slot_height) then
     local alt_held = r.ImGui_IsKeyDown(ctx, r.ImGui_Mod_Alt())
     if alt_held then
      r.TrackFX_Delete(track, slot)
     else
      local is_open = r.TrackFX_GetOpen(track, slot)
      r.TrackFX_Show(track, slot, is_open and 2 or 3)
     end
    end
    
    if r.ImGui_BeginDragDropSource(ctx, r.ImGui_DragDropFlags_None()) then
     local track_guid = r.GetTrackGUID(track)
     r.ImGui_SetDragDropPayload(ctx, "FX_SLOT", track_guid .. "|" .. tostring(slot))
     r.ImGui_Text(ctx, fx_name)
     r.ImGui_EndDragDropSource(ctx)
    end
    
    if r.ImGui_BeginDragDropTarget(ctx) then
     local payload_type, payload_data = r.ImGui_AcceptDragDropPayload(ctx, "FX_SLOT")
     if payload_data then
      local src_guid, src_slot_str = payload_data:match("^(.+)|(%d+)$")
      local source_slot = tonumber(src_slot_str)
      if src_guid and source_slot then
       local source_track = r.BR_GetMediaTrackByGUID(0, src_guid)
       if source_track then
        local same_track = (src_guid == r.GetTrackGUID(track))
        local is_move = same_track
        if same_track then
         if source_slot ~= slot then
          r.TrackFX_CopyToTrack(source_track, source_slot, track, slot, is_move)
         end
        else
         r.TrackFX_CopyToTrack(source_track, source_slot, track, slot, is_move)
        end
       end
      end
     end
     r.ImGui_EndDragDropTarget(ctx)
    end
    
    if r.ImGui_IsItemHovered(ctx) then
     local enabled_text = is_enabled and "Enabled" or "Bypassed"
     local offline_text = is_offline and ", Offline" or ""
     local is_open = r.TrackFX_GetOpen(track, slot)
     r.ImGui_SetTooltip(ctx, fx_name .. "\n(" .. enabled_text .. offline_text .. (is_open and ", Open" or "") .. ")\nDrag to reorder | Click to toggle floating | Alt+Click to delete | Right-click for menu")
    end
    
    if r.ImGui_IsItemClicked(ctx, r.ImGui_MouseButton_Right()) then
     r.ImGui_OpenPopup(ctx, "FXSlotContextMenu##" .. (is_master and "master" or idx) .. "_" .. slot)
    end
    
    if r.ImGui_BeginPopup(ctx, "FXSlotContextMenu##" .. (is_master and "master" or idx) .. "_" .. slot) then
     if r.ImGui_MenuItem(ctx, "Open FX Window") then
      r.TrackFX_Show(track, slot, 3)
     end
     if r.ImGui_MenuItem(ctx, "Close FX Window") then
      r.TrackFX_Show(track, slot, 2)
     end
     r.ImGui_Separator(ctx)
     if r.ImGui_MenuItem(ctx, is_enabled and "Bypass FX" or "Enable FX", nil, not is_enabled) then
      r.TrackFX_SetEnabled(track, slot, not is_enabled)
     end
     if r.TrackFX_SetOffline then
      if r.ImGui_MenuItem(ctx, is_offline and "Set Online" or "Set Offline", nil, is_offline) then
       r.TrackFX_SetOffline(track, slot, not is_offline)
      end
     end
     r.ImGui_Separator(ctx)
     if r.ImGui_BeginMenu(ctx, "Move") then
      if slot > 0 then
       if r.ImGui_MenuItem(ctx, "Move Up") then
        r.TrackFX_CopyToTrack(track, slot, track, slot - 1, true)
       end
       if r.ImGui_MenuItem(ctx, "Move to Top") then
        r.TrackFX_CopyToTrack(track, slot, track, 0, true)
       end
      end
      if slot < fx_count - 1 then
       if r.ImGui_MenuItem(ctx, "Move Down") then
        r.TrackFX_CopyToTrack(track, slot, track, slot + 2, true)
       end
       if r.ImGui_MenuItem(ctx, "Move to Bottom") then
        r.TrackFX_CopyToTrack(track, slot, track, fx_count, true)
       end
      end
      r.ImGui_EndMenu(ctx)
     end
     r.ImGui_Separator(ctx)
     if r.ImGui_MenuItem(ctx, "Copy FX") then
      r.TrackFX_CopyToTrack(track, slot, track, fx_count, false)
     end
     r.ImGui_Separator(ctx)
     if r.ImGui_MenuItem(ctx, "Delete FX") then
      r.TrackFX_Delete(track, slot)
     end
     r.ImGui_EndPopup(ctx)
    end
    
    if font_mixer then
     r.ImGui_PopFont(ctx)
    end
    r.ImGui_PopStyleVar(ctx)
    r.ImGui_PopStyleColor(ctx, 2)
    
    if show_bypass then
     r.ImGui_SameLine(ctx, 0, 2)
     local bypass_color = is_enabled and 0x00AA00FF or 0xFF0000FF
     r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), bypass_color)
     if r.ImGui_Button(ctx, is_enabled and "O" or "X", bypass_btn_width, slot_height) then
      r.TrackFX_SetEnabled(track, slot, not is_enabled)
     end
     r.ImGui_PopStyleColor(ctx, 1)
    end
    
    r.ImGui_PopID(ctx)
   end
   
   if fx_count == 0 then
    local dropzone_color = settings.simple_mixer_fx_dropzone_color or 0x2A2A2AFF
    local dropzone_border = settings.simple_mixer_fx_dropzone_border_color or 0x555555FF
    local dropzone_hover = ((dropzone_color & 0xFFFFFF00) | math.min(255, ((dropzone_color & 0xFF) + 0x20))) + 0x10101000
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), dropzone_color)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), dropzone_hover)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), dropzone_hover)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), 2)
    local btn_x, btn_y = r.ImGui_GetCursorScreenPos(ctx)
    local btn_w, btn_h = track_width - 4, slot_height
    r.ImGui_Button(ctx, "+##fxdrop_empty", btn_w, btn_h)
    local draw_list = r.ImGui_GetWindowDrawList(ctx)
    r.ImGui_DrawList_AddRect(draw_list, btn_x, btn_y, btn_x + btn_w, btn_y + btn_h, dropzone_border, 2, 0, 1)
    r.ImGui_PopStyleVar(ctx)
    if r.ImGui_BeginDragDropTarget(ctx) then
     local payload_type, payload_data = r.ImGui_AcceptDragDropPayload(ctx, "FX_SLOT")
     if payload_data then
      local src_guid, src_slot_str = payload_data:match("^(.+)|(%d+)$")
      local source_slot = tonumber(src_slot_str)
      if src_guid and source_slot then
       local source_track = r.BR_GetMediaTrackByGUID(0, src_guid)
       if source_track then
        local same_track = (src_guid == r.GetTrackGUID(track))
        local is_move = same_track
        r.TrackFX_CopyToTrack(source_track, source_slot, track, 0, is_move)
       end
      end
     end
     r.ImGui_EndDragDropTarget(ctx)
    end
    if r.ImGui_IsItemHovered(ctx) then
     r.ImGui_SetTooltip(ctx, "Drop FX here to add\nDouble-click to open FX browser")
    end
    if r.ImGui_IsItemHovered(ctx) and r.ImGui_IsMouseDoubleClicked(ctx, r.ImGui_MouseButton_Left()) then
     r.SetOnlyTrackSelected(track)
     r.Main_OnCommand(40271, 0)
    end
    r.ImGui_PopStyleColor(ctx, 3)
   else
    local dropzone_color = settings.simple_mixer_fx_dropzone_color or 0x2A2A2AFF
    local dropzone_border = settings.simple_mixer_fx_dropzone_border_color or 0x555555FF
    local dropzone_hover = ((dropzone_color & 0xFFFFFF00) | math.min(255, ((dropzone_color & 0xFF) + 0x20))) + 0x10101000
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), dropzone_color)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), dropzone_hover)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), dropzone_hover)
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), 2)
    local btn_x, btn_y = r.ImGui_GetCursorScreenPos(ctx)
    local btn_w, btn_h = track_width - 4, slot_height
    r.ImGui_Button(ctx, "+##fxdrop_end", btn_w, btn_h)
    local draw_list = r.ImGui_GetWindowDrawList(ctx)
    r.ImGui_DrawList_AddRect(draw_list, btn_x, btn_y, btn_x + btn_w, btn_y + btn_h, dropzone_border, 2, 0, 1)
    r.ImGui_PopStyleVar(ctx)
    if r.ImGui_BeginDragDropTarget(ctx) then
     local payload_type, payload_data = r.ImGui_AcceptDragDropPayload(ctx, "FX_SLOT")
     if payload_data then
      local src_guid, src_slot_str = payload_data:match("^(.+)|(%d+)$")
      local source_slot = tonumber(src_slot_str)
      if src_guid and source_slot then
       local source_track = r.BR_GetMediaTrackByGUID(0, src_guid)
       if source_track then
        local same_track = (src_guid == r.GetTrackGUID(track))
        local is_move = same_track
        r.TrackFX_CopyToTrack(source_track, source_slot, track, fx_count, is_move)
       end
      end
     end
     r.ImGui_EndDragDropTarget(ctx)
    end
    if r.ImGui_IsItemHovered(ctx) then
     r.ImGui_SetTooltip(ctx, "Drop FX here to add at end\nDouble-click to open FX browser")
    end
    if r.ImGui_IsItemHovered(ctx) and r.ImGui_IsMouseDoubleClicked(ctx, r.ImGui_MouseButton_Left()) then
     r.SetOnlyTrackSelected(track)
     r.Main_OnCommand(40271, 0)
    end
    r.ImGui_PopStyleColor(ctx, 3)
   end
   
   r.ImGui_EndChild(ctx)
  end
  r.ImGui_PopStyleVar(ctx)
  r.ImGui_PopStyleColor(ctx, 1)
 end

 if settings.simple_mixer_show_fx_slots and show_fx_handle then
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x00000000)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0x00000000)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0x00000000)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Border(), 0x00000000)
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameBorderSize(), 0)
  
  local handle_height = 8
  local btn_x, btn_y = r.ImGui_GetCursorScreenPos(ctx)
  r.ImGui_Button(ctx, "##fxhandle", track_width, handle_height)
  
  local draw_list = r.ImGui_GetWindowDrawList(ctx)
  local line_y = btn_y + handle_height / 2
  
  local handle_color = 0x888888FF
  local track_color = r.GetTrackColor(track)
  if track_color ~= 0 then
   local rv, gv, bv = r.ColorFromNative(track_color)
   handle_color = r.ImGui_ColorConvertDouble4ToU32(rv/255, gv/255, bv/255, 1.0)
  end
  
  r.ImGui_DrawList_AddLine(draw_list, btn_x + 4, line_y, btn_x + track_width - 4, line_y, handle_color, 3)
  
  local ctrl_held = r.ImGui_IsKeyDown(ctx, r.ImGui_Mod_Ctrl())
  
  if r.ImGui_IsItemClicked(ctx, r.ImGui_MouseButton_Left()) then
   if ctrl_held then
    mixer_state.fx_sync_resize = true
    local my_height = mixer_state.track_fx_heights[track_guid_for_fx] or settings.simple_mixer_fx_section_height or 80
    for guid, _ in pairs(mixer_state.track_fx_heights) do
     mixer_state.track_fx_heights[guid] = my_height
    end
    settings.simple_mixer_fx_section_height = my_height
   end
  end
  
  local was_dragging = r.ImGui_IsItemActive(ctx) and r.ImGui_IsMouseDragging(ctx, r.ImGui_MouseButton_Left(), 3)
  if was_dragging then
   local _, dy = r.ImGui_GetMouseDelta(ctx)
   if mixer_state.fx_sync_resize or ctrl_held then
    local current_height = settings.simple_mixer_fx_section_height or 80
    local new_height = math.max(30, math.min(300, current_height + dy))
    settings.simple_mixer_fx_section_height = new_height
    for guid, _ in pairs(mixer_state.track_fx_heights) do
     mixer_state.track_fx_heights[guid] = new_height
    end
   else
    local current_height = mixer_state.track_fx_heights[track_guid_for_fx] or settings.simple_mixer_fx_section_height or 80
    mixer_state.track_fx_heights[track_guid_for_fx] = math.max(30, math.min(300, current_height + dy))
   end
  end
  
  if r.ImGui_IsItemDeactivated(ctx) then
   mixer_state.fx_sync_resize = false
  end
  
  if r.ImGui_IsItemClicked(ctx, r.ImGui_MouseButton_Left()) and not r.ImGui_IsMouseDragging(ctx, r.ImGui_MouseButton_Left(), 3) then
   mixer_state.fx_handle_clicked = true
  end
  
  if r.ImGui_IsItemDeactivated(ctx) and mixer_state.fx_handle_clicked then
   if not r.ImGui_IsMouseDragging(ctx, r.ImGui_MouseButton_Left(), 3) then
    local drag_x, drag_y = r.ImGui_GetMouseDragDelta(ctx, r.ImGui_MouseButton_Left(), 3)
    if math.abs(drag_y) < 3 then
     settings.simple_mixer_fx_section_collapsed = not settings.simple_mixer_fx_section_collapsed
    end
   end
   mixer_state.fx_handle_clicked = false
  end
  
  if r.ImGui_IsItemHovered(ctx) then
   r.ImGui_SetTooltip(ctx, "Click to collapse/expand FX section\nDrag to resize this track\nCtrl+Drag to sync all tracks")
   r.ImGui_SetMouseCursor(ctx, r.ImGui_MouseCursor_ResizeNS())
  end
  
  r.ImGui_PopStyleVar(ctx, 1)
  r.ImGui_PopStyleColor(ctx, 4)
 end

 local volume = r.GetMediaTrackInfo_Value(track, "D_VOL")
 local volume_db = 20.0 * math.log(volume, 10)

 local is_track_selected = r.IsTrackSelected(track)
 local slider_color_pushed = false

 if is_master then
  local master_col = settings.simple_mixer_master_fader_color or 0x4A90D9FF
  local mr, mg, mb, ma = r.ImGui_ColorConvertU32ToDouble4(master_col)
  local fader_bg = r.ImGui_ColorConvertDouble4ToU32(mr, mg, mb, 0.25)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), fader_bg)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgHovered(), fader_bg)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgActive(), fader_bg)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrab(), master_col)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrabActive(), master_col)
  slider_color_pushed = true
 elseif settings.simple_mixer_use_track_color then
  local track_color = r.GetTrackColor(track)
  if track_color ~= 0 then
   local r_val, g_val, b_val = r.ColorFromNative(track_color)
   
   if is_track_selected then
    r_val = math.min(255, r_val + (255 - r_val) * 0.5)
    g_val = math.min(255, g_val + (255 - g_val) * 0.5)
    b_val = math.min(255, b_val + (255 - b_val) * 0.5)
   end
   
   local fader_bg_style = settings.simple_mixer_fader_bg_style or 0
   local imgui_color_full = r.ImGui_ColorConvertDouble4ToU32(r_val/255, g_val/255, b_val/255, 1.0)
   local imgui_color_bg = (fader_bg_style > 0) and 0x00000000 or r.ImGui_ColorConvertDouble4ToU32(r_val/255, g_val/255, b_val/255, 0.25)
   local imgui_color_hover = (fader_bg_style > 0) and 0x00000000 or r.ImGui_ColorConvertDouble4ToU32(r_val/255, g_val/255, b_val/255, 0.38)
   local imgui_color_active = (fader_bg_style > 0) and 0x00000000 or r.ImGui_ColorConvertDouble4ToU32(r_val/255, g_val/255, b_val/255, 0.5)
   local imgui_color_grab_active = r.ImGui_ColorConvertDouble4ToU32(r_val/255, g_val/255, b_val/255, 0.87)
   
   r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), imgui_color_bg)
   r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgHovered(), imgui_color_hover)
   r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgActive(), imgui_color_active)
   r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrab(), imgui_color_full)
   r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrabActive(), imgui_color_grab_active)
   slider_color_pushed = true
  elseif is_track_selected then
   local sel_col = settings.simple_mixer_selection_color or 0x4A90D9FF
   local sr, sg, sb = r.ImGui_ColorConvertU32ToDouble4(sel_col)
   local intensity = math.max(0.1, math.min(1.0, settings.simple_mixer_selection_intensity or 0.67))
   local lr = math.min(1, sr + 0.18)
   local lg = math.min(1, sg + 0.18)
   local lb = math.min(1, sb + 0.18)
   r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(),        r.ImGui_ColorConvertDouble4ToU32(sr, sg, sb, intensity))
   r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgHovered(), r.ImGui_ColorConvertDouble4ToU32(sr, sg, sb, math.min(1, intensity + 0.1)))
   r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgActive(),  r.ImGui_ColorConvertDouble4ToU32(sr, sg, sb, math.min(1, intensity + 0.2)))
   r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrab(),       r.ImGui_ColorConvertDouble4ToU32(lr, lg, lb, 1.0))
   r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrabActive(), r.ImGui_ColorConvertDouble4ToU32(math.min(1, sr + 0.28), math.min(1, sg + 0.28), math.min(1, sb + 0.28), 1.0))
   slider_color_pushed = true
  else
   local fader_bg_style = settings.simple_mixer_fader_bg_style or 0
   local fader_bg = (fader_bg_style > 0) and 0x00000000 or (settings.simple_mixer_fader_bg_color or 0x404040FF)
   local handle_col = settings.simple_mixer_slider_handle_color or 0x888888FF
   r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), fader_bg)
   r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgHovered(), fader_bg)
   r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgActive(), fader_bg)
   r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrab(), handle_col)
   r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrabActive(), handle_col)
   slider_color_pushed = true
  end
 elseif is_track_selected then
  local sel_col = settings.simple_mixer_selection_color or 0x4A90D9FF
  local sr, sg, sb = r.ImGui_ColorConvertU32ToDouble4(sel_col)
  local intensity = math.max(0.1, math.min(1.0, settings.simple_mixer_selection_intensity or 0.67))
  local lr = math.min(1, sr + 0.18)
  local lg = math.min(1, sg + 0.18)
  local lb = math.min(1, sb + 0.18)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(),        r.ImGui_ColorConvertDouble4ToU32(sr, sg, sb, intensity))
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgHovered(), r.ImGui_ColorConvertDouble4ToU32(sr, sg, sb, math.min(1, intensity + 0.1)))
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgActive(),  r.ImGui_ColorConvertDouble4ToU32(sr, sg, sb, math.min(1, intensity + 0.2)))
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrab(),       r.ImGui_ColorConvertDouble4ToU32(lr, lg, lb, 1.0))
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrabActive(), r.ImGui_ColorConvertDouble4ToU32(math.min(1, sr + 0.28), math.min(1, sg + 0.28), math.min(1, sb + 0.28), 1.0))
  slider_color_pushed = true
 else
  local fader_bg_style = settings.simple_mixer_fader_bg_style or 0
  local fader_bg = (fader_bg_style > 0) and 0x00000000 or (settings.simple_mixer_fader_bg_color or 0x404040FF)
  local handle_col = settings.simple_mixer_slider_handle_color or 0x888888FF
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), fader_bg)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgHovered(), fader_bg)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgActive(), fader_bg)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrab(), handle_col)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrabActive(), handle_col)
  slider_color_pushed = true
 end

 local slider_start_x, slider_start_y = r.ImGui_GetCursorScreenPos(ctx)
 
 local show_meters = settings.simple_mixer_show_meters ~= false
 local fixed_meter_width = math.max(4, math.min(40, settings.simple_mixer_meter_width or 12))
 local slider_actual_width = show_meters and (track_width - fixed_meter_width - 2) or track_width
 local meter_width = show_meters and fixed_meter_width or 0
 local fader_margin = 20
 
 local fader_bg_style = settings.simple_mixer_fader_bg_style or 0
 local track_color_native = r.GetTrackColor(track)
 local track_has_color = track_color_native ~= 0
 local use_custom_fader_bg = fader_bg_style > 0
 if use_custom_fader_bg then
  local draw_list = r.ImGui_GetWindowDrawList(ctx)
  local rounding = settings.simple_mixer_channel_rounding or 0
  local track_color_rgb = nil
  if settings.simple_mixer_use_track_color and track_has_color then
   local r_val, g_val, b_val = r.ColorFromNative(track_color_native)
   track_color_rgb = {r_val/255, g_val/255, b_val/255}
  end
  DrawFaderBackground(ctx, draw_list, slider_start_x, slider_start_y, slider_actual_width, slider_height, rounding, track_color_rgb, fader_margin)
 end
 
 r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), settings.simple_mixer_channel_text_color or 0xFFFFFFFF)
 r.ImGui_PushItemWidth(ctx, slider_actual_width)
 
 local fader_style = settings.simple_mixer_fader_style or 0
 local custom_fader = fader_style > 0
 if custom_fader then
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_GrabMinSize(), 0)
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FramePadding(), 0, fader_margin)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrab(), 0x00000000)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrabActive(), 0x00000000)
 end
 
 local slider_format = custom_fader and "" or "%.1f"
 
 local current_track_id = is_master and "master" or r.GetTrackGUID(track)
 
 if not is_locked and r.ImGui_IsMouseDoubleClicked(ctx, r.ImGui_MouseButton_Left()) then
  local mx, my = r.ImGui_GetMousePos(ctx)
  if mx >= slider_start_x and mx <= slider_start_x + slider_actual_width and
     my >= slider_start_y and my <= slider_start_y + slider_height then
   r.SetMediaTrackInfo_Value(track, "D_VOL", 1.0)
   mixer_state.fader_reset_track = current_track_id
  end
 end
 
 if mixer_state.fader_reset_track == current_track_id then
  if not r.ImGui_IsMouseDown(ctx, r.ImGui_MouseButton_Left()) then
   mixer_state.fader_reset_track = nil
  end
 end
 
 local rv, new_vol_db = r.ImGui_VSliderDouble(ctx, "##vol", slider_actual_width, slider_height, volume_db, -60.0, 12.0, slider_format)
 
 if rv and mixer_state.fader_reset_track ~= current_track_id then
  local new_volume = 10.0 ^ (new_vol_db / 20.0)
  local delta_db = new_vol_db - volume_db
  r.SetMediaTrackInfo_Value(track, "D_VOL", new_volume)
  local track_guid = is_master and "master" or r.GetTrackGUID(track)
  if mixer_state.linked_channels[track_guid] then
   for linked_guid, _ in pairs(mixer_state.linked_channels[track_guid]) do
    local linked_track = nil
    if linked_guid == "master" then
     linked_track = r.GetMasterTrack(0)
    else
     for i = 0, r.CountTracks(0) - 1 do
      local tr = r.GetTrack(0, i)
      if r.GetTrackGUID(tr) == linked_guid then
       linked_track = tr
       break
      end
     end
    end
    if linked_track then
     local linked_vol = r.GetMediaTrackInfo_Value(linked_track, "D_VOL")
     local linked_db = 20.0 * math.log(linked_vol, 10)
     local new_linked_db = math.max(-60, math.min(12, linked_db + delta_db))
     local new_linked_vol = 10.0 ^ (new_linked_db / 20.0)
     r.SetMediaTrackInfo_Value(linked_track, "D_VOL", new_linked_vol)
    end
   end
  end
 end
 
 if custom_fader then
  r.ImGui_PopStyleColor(ctx, 2)
  r.ImGui_PopStyleVar(ctx, 2)
 end
 
 r.ImGui_PopItemWidth(ctx)
 r.ImGui_PopStyleColor(ctx, 1)

 local knob_data = nil
 if custom_fader then
  local draw_list = r.ImGui_GetWindowDrawList(ctx)
  local center_x = slider_start_x + slider_actual_width * 0.5
  local track_line_width = 4
  local groove_top = slider_start_y + fader_margin
  local groove_bottom = slider_start_y + slider_height - fader_margin
  local groove_left = center_x - track_line_width * 0.5
  local groove_right = center_x + track_line_width * 0.5
  
  r.ImGui_DrawList_AddRectFilled(draw_list, groove_left, groove_top, groove_right, groove_bottom, 0x0A0A0AFF, 1)
  r.ImGui_DrawList_AddLine(draw_list, groove_left, groove_top, groove_left, groove_bottom, 0x000000FF, 1)
  r.ImGui_DrawList_AddLine(draw_list, groove_left, groove_top, groove_right, groove_top, 0x000000FF, 1)
  r.ImGui_DrawList_AddLine(draw_list, groove_right - 1, groove_top, groove_right - 1, groove_bottom, 0x404040FF, 1)
  r.ImGui_DrawList_AddLine(draw_list, groove_left, groove_bottom - 1, groove_right, groove_bottom - 1, 0x404040FF, 1)
  local inner_highlight = 0x1A1A1A88
  r.ImGui_DrawList_AddRectFilled(draw_list, groove_left + 1, groove_top + 1, groove_right - 1, groove_top + 4, inner_highlight, 0)
  
  local normalized = (volume_db + 60.0) / 72.0
  normalized = math.max(0, math.min(1, normalized))
  local fader_travel = slider_height - fader_margin * 2
  local knob_y = slider_start_y + slider_height - fader_margin - fader_travel * normalized
  local knob_width = math.min(slider_actual_width * 0.55, 24)
  local knob_height = 20
  local knob_x = center_x - knob_width * 0.5
  local knob_top = knob_y - knob_height * 0.5
  local knob_bottom = knob_y + knob_height * 0.5
  local knob_right = knob_x + knob_width
  
  knob_data = {
   draw_list = draw_list,
   knob_x = knob_x,
   knob_y = knob_y,
   knob_top = knob_top,
   knob_bottom = knob_bottom,
   knob_right = knob_right,
   knob_width = knob_width,
   knob_height = knob_height
  }
 end

 local track_icon_position = settings.simple_mixer_track_icon_position or "overlay"
 if settings.simple_mixer_show_track_icons and not is_master and track_icon_position == "overlay" then
  local draw_list = r.ImGui_GetWindowDrawList(ctx)
  local opacity = settings.simple_mixer_track_icon_opacity or 0.3
  DrawTrackIcon(ctx, draw_list, track, slider_start_x, slider_start_y, slider_actual_width, slider_height, opacity)
 end

 if custom_fader and knob_data then
  local draw_list = knob_data.draw_list
  local knob_x = knob_data.knob_x
  local knob_y = knob_data.knob_y
  local knob_top = knob_data.knob_top
  local knob_bottom = knob_data.knob_bottom
  local knob_right = knob_data.knob_right
  local knob_width = knob_data.knob_width
  local knob_height = knob_data.knob_height
  
  if fader_style == 1 then
   local knob_color = 0x222222FF
   r.ImGui_DrawList_AddRectFilled(draw_list, knob_x, knob_top, knob_right, knob_bottom, knob_color, 2)
   local highlight_height = 4
   local highlight_color_top = 0x606060AA
   local highlight_color_bottom = 0x40404000
   r.ImGui_DrawList_AddRectFilledMultiColor(draw_list, knob_x + 1, knob_top + 1, knob_right - 1, knob_top + highlight_height, highlight_color_top, highlight_color_top, highlight_color_bottom, highlight_color_bottom)
   local groove_color = 0x777777AA
   local groove_spacing = 3
   local num_grooves = math.floor(knob_height / groove_spacing) - 1
   local groove_start_y = knob_y - (num_grooves - 1) * groove_spacing * 0.5
   for i = 0, num_grooves - 1 do
    local gy = groove_start_y + i * groove_spacing
    r.ImGui_DrawList_AddLine(draw_list, knob_x + knob_width * 0.15, gy, knob_x + knob_width * 0.85, gy, groove_color, 1)
   end
   r.ImGui_DrawList_AddRect(draw_list, knob_x, knob_top, knob_right, knob_bottom, 0x00000088, 2, 0, 1)
  elseif fader_style == 2 then
   local shadow_offset = 3
   r.ImGui_DrawList_AddRectFilled(draw_list, knob_x + shadow_offset, knob_top + shadow_offset, knob_right + shadow_offset, knob_bottom + shadow_offset, 0x00000066, 3)
   local knob_color_bottom = 0x1A1A1AFF
   local knob_color_top = 0x3D3D3DFF
   r.ImGui_DrawList_AddRectFilledMultiColor(draw_list, knob_x, knob_top, knob_right, knob_bottom, knob_color_top, knob_color_top, knob_color_bottom, knob_color_bottom)
   local bevel_top = 0x5A5A5AFF
   local bevel_bottom = 0x0A0A0AFF
   r.ImGui_DrawList_AddLine(draw_list, knob_x, knob_top, knob_right, knob_top, bevel_top, 2)
   r.ImGui_DrawList_AddLine(draw_list, knob_x, knob_bottom, knob_right, knob_bottom, bevel_bottom, 2)
   local center_line_y = knob_y
   r.ImGui_DrawList_AddLine(draw_list, knob_x + knob_width * 0.2, center_line_y, knob_x + knob_width * 0.8, center_line_y, 0x888888FF, 2)
   r.ImGui_DrawList_AddRect(draw_list, knob_x, knob_top, knob_right, knob_bottom, 0x000000AA, 3, 0, 1)
  elseif fader_style == 3 then
   local knob_color = 0x2A2A2AFF
   r.ImGui_DrawList_AddRectFilled(draw_list, knob_x, knob_top, knob_right, knob_bottom, knob_color, 2)
   local led_height = 4
   local led_width = knob_width - 8
   local led_x = knob_x + 4
   local led_y = knob_y - led_height * 0.5
   local led_color
   if volume_db > 0 then
    led_color = 0xFF3333FF
   elseif volume_db > -6 then
    led_color = 0xFFAA33FF
   elseif volume_db > -18 then
    led_color = 0x33FF33FF
   else
    led_color = 0x228822FF
   end
   local glow_color = (led_color & 0xFFFFFF00) | 0x44
   r.ImGui_DrawList_AddRectFilled(draw_list, led_x - 1, led_y - 2, led_x + led_width + 1, led_y + led_height + 2, glow_color, 2)
   r.ImGui_DrawList_AddRectFilled(draw_list, led_x, led_y, led_x + led_width, led_y + led_height, led_color, 1)
   r.ImGui_DrawList_AddRect(draw_list, knob_x, knob_top, knob_right, knob_bottom, 0x00000088, 2, 0, 1)
  elseif fader_style == 4 then
   r.ImGui_DrawList_AddRectFilled(draw_list, knob_x + 2, knob_top + 2, knob_right + 2, knob_bottom + 2, 0x00000044, 4)
   local glass_top = 0x8899AACC
   local glass_bottom = 0x44556688
   r.ImGui_DrawList_AddRectFilledMultiColor(draw_list, knob_x, knob_top, knob_right, knob_bottom, glass_top, glass_top, glass_bottom, glass_bottom)
   local shine_height = knob_height * 0.35
   local shine_top = 0xFFFFFF66
   local shine_bottom = 0xFFFFFF00
   r.ImGui_DrawList_AddRectFilledMultiColor(draw_list, knob_x + 2, knob_top + 1, knob_right - 2, knob_top + shine_height, shine_top, shine_top, shine_bottom, shine_bottom)
   r.ImGui_DrawList_AddRect(draw_list, knob_x, knob_top, knob_right, knob_bottom, 0xAABBCCFF, 4, 0, 1)
   local center_dot_y = knob_y
   r.ImGui_DrawList_AddCircleFilled(draw_list, knob_x + knob_width * 0.5, center_dot_y, 2, 0xFFFFFFAA, 8)
  elseif fader_style == 5 then
   local knob_color = 0x1A1A1AFF
   r.ImGui_DrawList_AddRectFilled(draw_list, knob_x, knob_top, knob_right, knob_bottom, knob_color, 3)
   local meter_left = knob_x + 3
   local meter_right = knob_right - 3
   local meter_top = knob_top + 4
   local meter_bottom = knob_bottom - 4
   local meter_center_x = (meter_left + meter_right) * 0.5
   local meter_center_y = meter_bottom
   local needle_length = (meter_bottom - meter_top) * 0.85
   r.ImGui_DrawList_AddRectFilled(draw_list, meter_left, meter_top, meter_right, meter_bottom, 0x2A2A1AFF, 2)
   local num_ticks = 7
   for i = 0, num_ticks do
    local tick_angle = math.pi * 0.15 + (math.pi * 0.7) * (i / num_ticks)
    local tick_x1 = meter_center_x - math.cos(tick_angle) * needle_length * 0.7
    local tick_y1 = meter_center_y - math.sin(tick_angle) * needle_length * 0.7
    local tick_x2 = meter_center_x - math.cos(tick_angle) * needle_length * 0.9
    local tick_y2 = meter_center_y - math.sin(tick_angle) * needle_length * 0.9
    local tick_color = i >= 5 and 0xFF4444FF or 0x888866FF
    r.ImGui_DrawList_AddLine(draw_list, tick_x1, tick_y1, tick_x2, tick_y2, tick_color, 1)
   end
   local needle_pos = (volume_db + 60) / 72
   needle_pos = math.max(0, math.min(1, needle_pos))
   local needle_angle = math.pi * 0.15 + (math.pi * 0.7) * needle_pos
   local needle_x = meter_center_x - math.cos(needle_angle) * needle_length
   local needle_y = meter_center_y - math.sin(needle_angle) * needle_length
   r.ImGui_DrawList_AddLine(draw_list, meter_center_x, meter_center_y, needle_x, needle_y, 0xFF6633FF, 1.5)
   r.ImGui_DrawList_AddCircleFilled(draw_list, meter_center_x, meter_center_y, 2, 0xCC5522FF, 8)
   r.ImGui_DrawList_AddRect(draw_list, knob_x, knob_top, knob_right, knob_bottom, 0x00000088, 3, 0, 1)
  elseif fader_style == 6 then
   r.ImGui_DrawList_AddRectFilled(draw_list, knob_x, knob_top, knob_right, knob_bottom, 0x0A0A12FF, 2)
   local cyber_color = settings.simple_mixer_fader_cyberpunk_color or 0x00FFFFFF
   local pulse = (math.sin(r.time_precise() * 4) + 1) * 0.5
   local glow_thickness = 2 + pulse * 3
   r.ImGui_DrawList_AddRect(draw_list, knob_x - 2, knob_top - 2, knob_right + 2, knob_bottom + 2, cyber_color, 3, 0, glow_thickness)
   r.ImGui_DrawList_AddRect(draw_list, knob_x, knob_top, knob_right, knob_bottom, cyber_color, 2, 0, 1.5)
   local line_y1 = knob_y - 3
   local line_y2 = knob_y + 3
   r.ImGui_DrawList_AddLine(draw_list, knob_x + 3, line_y1, knob_right - 3, line_y1, cyber_color, 1)
   r.ImGui_DrawList_AddLine(draw_list, knob_x + 3, line_y2, knob_right - 3, line_y2, cyber_color, 1)
   local corner_size = 3
   r.ImGui_DrawList_AddTriangleFilled(draw_list, knob_x, knob_top, knob_x + corner_size, knob_top, knob_x, knob_top + corner_size, cyber_color)
   r.ImGui_DrawList_AddTriangleFilled(draw_list, knob_right, knob_top, knob_right - corner_size, knob_top, knob_right, knob_top + corner_size, cyber_color)
   r.ImGui_DrawList_AddTriangleFilled(draw_list, knob_x, knob_bottom, knob_x + corner_size, knob_bottom, knob_x, knob_bottom - corner_size, cyber_color)
   r.ImGui_DrawList_AddTriangleFilled(draw_list, knob_right, knob_bottom, knob_right - corner_size, knob_bottom, knob_right, knob_bottom - corner_size, cyber_color)
  end
 end

 if custom_fader then
  local draw_list = r.ImGui_GetWindowDrawList(ctx)
  local text_color = settings.simple_mixer_channel_text_color or 0xFFFFFFFF
  local vol_text = string.format("%.1f", volume_db)
  local text_w, text_h = r.ImGui_CalcTextSize(ctx, vol_text)
  local text_x = slider_start_x + (slider_actual_width - text_w) * 0.5
  local text_y = slider_start_y + 4
  r.ImGui_DrawList_AddText(draw_list, text_x, text_y, text_color, vol_text)
 end

 if show_meters and meter_width > 0 then
  UpdateMeterData(track_guid_for_fx, track)
  local draw_list = r.ImGui_GetWindowDrawList(ctx)
  local meter_x = slider_start_x + slider_actual_width + 2
  local meter_y = slider_start_y
  local meter_height = slider_height
  local meter_data = DrawMeter(ctx, draw_list, meter_x, meter_y, meter_width, meter_height, track_guid_for_fx, fader_margin)
  
  local peak_L_db = PeakToDb(meter_data.peak_L_decay)
  local peak_R_db = PeakToDb(meter_data.peak_R_decay)
  local max_peak_db = math.max(peak_L_db, peak_R_db)
  local gain_indicator_color = nil
  local gain_status = ""
  if max_peak_db > -0.5 then
   gain_indicator_color = 0xFF0000FF
   gain_status = "HOT!"
  elseif max_peak_db > -6 then
   gain_indicator_color = 0xFF8800FF
   gain_status = "Loud"
  elseif max_peak_db < -40 and max_peak_db > -100 then
   gain_indicator_color = 0x4488FFFF
   gain_status = "Low"
  end
  if gain_indicator_color and settings.simple_mixer_show_gain_staging ~= false then
   local indicator_y = meter_y - 14
   local indicator_w = slider_actual_width + meter_width + 2
   r.ImGui_DrawList_AddRectFilled(draw_list, slider_start_x, indicator_y, slider_start_x + indicator_w, indicator_y + 12, gain_indicator_color, 2)
   local text_w = r.ImGui_CalcTextSize(ctx, gain_status)
   local text_x = slider_start_x + (indicator_w - text_w) / 2
   r.ImGui_DrawList_AddText(draw_list, text_x, indicator_y, 0xFFFFFFFF, gain_status)
  end
  
  local mx, my = r.ImGui_GetMousePos(ctx)
  if mx >= meter_x and mx <= meter_x + meter_width and my >= meter_y and my <= meter_y + meter_height then
   local hold_L_db = PeakToDb(meter_data.peak_L_hold)
   local hold_R_db = PeakToDb(meter_data.peak_R_hold)
   local tooltip = string.format("L: %.1f dB (peak: %.1f)\nR: %.1f dB (peak: %.1f)", 
    peak_L_db > -100 and peak_L_db or -math.huge,
    hold_L_db > -100 and hold_L_db or -math.huge,
    peak_R_db > -100 and peak_R_db or -math.huge,
    hold_R_db > -100 and hold_R_db or -math.huge)
   r.ImGui_SetTooltip(ctx, tooltip)
  end
 end

 if not is_locked and r.ImGui_IsItemHovered(ctx) and r.ImGui_IsMouseDoubleClicked(ctx, r.ImGui_MouseButton_Left()) then
  r.SetMediaTrackInfo_Value(track, "D_VOL", 1.0)
 end
 
 if r.ImGui_IsItemClicked(ctx, r.ImGui_MouseButton_Right()) then
  r.ImGui_OpenPopup(ctx, "FaderContextMenu##" .. (is_master and "master" or idx))
 end
 
 if is_locked then r.ImGui_EndDisabled(ctx) end
 if r.ImGui_BeginPopup(ctx, "FaderContextMenu##" .. (is_master and "master" or idx)) then
  local track_guid = is_master and "master" or r.GetTrackGUID(track)
  if r.ImGui_BeginMenu(ctx, "Volume") then
   if r.ImGui_MenuItem(ctx, "Reset to 0 dB") then
    r.SetMediaTrackInfo_Value(track, "D_VOL", 1.0)
   end
   r.ImGui_Separator(ctx)
   if r.ImGui_MenuItem(ctx, "-6 dB") then
    r.SetMediaTrackInfo_Value(track, "D_VOL", 10.0 ^ (-6.0 / 20.0))
   end
   if r.ImGui_MenuItem(ctx, "-12 dB") then
    r.SetMediaTrackInfo_Value(track, "D_VOL", 10.0 ^ (-12.0 / 20.0))
   end
   if r.ImGui_MenuItem(ctx, "-18 dB") then
    r.SetMediaTrackInfo_Value(track, "D_VOL", 10.0 ^ (-18.0 / 20.0))
   end
   if r.ImGui_MenuItem(ctx, "-inf dB (Mute)") then
    r.SetMediaTrackInfo_Value(track, "D_VOL", 0.0)
   end
   r.ImGui_EndMenu(ctx)
  end
  
  if r.ImGui_BeginMenu(ctx, "A/B Compare") then
   local has_a = mixer_state.ab_state[track_guid] and mixer_state.ab_state[track_guid].a
   local has_b = mixer_state.ab_state[track_guid] and mixer_state.ab_state[track_guid].b
   local current_ab = mixer_state.ab_current[track_guid] or "a"
   if r.ImGui_MenuItem(ctx, "Store A", nil, false) then
    mixer_state.ab_state[track_guid] = mixer_state.ab_state[track_guid] or {}
    mixer_state.ab_state[track_guid].a = volume_db
   end
   if r.ImGui_MenuItem(ctx, "Store B", nil, false) then
    mixer_state.ab_state[track_guid] = mixer_state.ab_state[track_guid] or {}
    mixer_state.ab_state[track_guid].b = volume_db
   end
   r.ImGui_Separator(ctx)
   if has_a and has_b then
    if r.ImGui_MenuItem(ctx, "Switch to A", nil, current_ab == "a") then
     local vol_a = mixer_state.ab_state[track_guid].a
     r.SetMediaTrackInfo_Value(track, "D_VOL", 10.0 ^ (vol_a / 20.0))
     mixer_state.ab_current[track_guid] = "a"
    end
    if r.ImGui_MenuItem(ctx, "Switch to B", nil, current_ab == "b") then
     local vol_b = mixer_state.ab_state[track_guid].b
     r.SetMediaTrackInfo_Value(track, "D_VOL", 10.0 ^ (vol_b / 20.0))
     mixer_state.ab_current[track_guid] = "b"
    end
   else
    r.ImGui_TextDisabled(ctx, "Store A and B first")
   end
   if has_a or has_b then
    r.ImGui_Separator(ctx)
    if r.ImGui_MenuItem(ctx, "Clear A/B") then
     mixer_state.ab_state[track_guid] = nil
     mixer_state.ab_current[track_guid] = nil
    end
   end
   r.ImGui_EndMenu(ctx)
  end
  
  if not is_master then
   if r.ImGui_BeginMenu(ctx, "Link Channel") then
    local current_links = mixer_state.linked_channels[track_guid] or {}
    local has_links = next(current_links) ~= nil
    for i = 0, r.CountTracks(0) - 1 do
     local other_track = r.GetTrack(0, i)
     local other_guid = r.GetTrackGUID(other_track)
     if other_guid ~= track_guid then
      local _, other_name = r.GetTrackName(other_track)
      local other_num = math.floor(r.GetMediaTrackInfo_Value(other_track, "IP_TRACKNUMBER"))
      local display = other_num .. ": " .. (other_name ~= "" and other_name or "Track " .. other_num)
      local is_linked = current_links[other_guid] == true
      if r.ImGui_MenuItem(ctx, display, nil, is_linked) then
       if is_linked then
        mixer_state.linked_channels[track_guid][other_guid] = nil
        if mixer_state.linked_channels[other_guid] then
         mixer_state.linked_channels[other_guid][track_guid] = nil
        end
       else
        mixer_state.linked_channels[track_guid] = mixer_state.linked_channels[track_guid] or {}
        mixer_state.linked_channels[track_guid][other_guid] = true
        mixer_state.linked_channels[other_guid] = mixer_state.linked_channels[other_guid] or {}
        mixer_state.linked_channels[other_guid][track_guid] = true
       end
      end
     end
    end
    if has_links then
     r.ImGui_Separator(ctx)
     if r.ImGui_MenuItem(ctx, "Unlink All") then
      for linked_guid, _ in pairs(current_links) do
       if mixer_state.linked_channels[linked_guid] then
        mixer_state.linked_channels[linked_guid][track_guid] = nil
       end
      end
      mixer_state.linked_channels[track_guid] = nil
     end
    end
    r.ImGui_EndMenu(ctx)
   end
  end
  
  r.ImGui_Separator(ctx)
  
  if not is_master then
   if r.ImGui_BeginMenu(ctx, "Track") then
    if r.ImGui_MenuItem(ctx, "Rename Track...") then
     mixer_state.editing_track_guid = r.GetTrackGUID(track)
     mixer_state.editing_track_name = track_name
    end
    if r.ImGui_MenuItem(ctx, "Duplicate Track") then
     r.SetOnlyTrackSelected(track)
     r.Main_OnCommand(40062, 0)
    end
    if r.ImGui_MenuItem(ctx, "Lock Track Controls") then
     r.SetOnlyTrackSelected(track)
     r.Main_OnCommand(41314, 0)
     track_lock_cache[r.GetTrackGUID(track)] = nil
    end
    r.ImGui_Separator(ctx)
    if r.ImGui_BeginMenu(ctx, "Create Folder") then
     if r.ImGui_MenuItem(ctx, "Around This Track") then
      local idx = math.floor(r.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER")) - 1
      r.PreventUIRefresh(1)
      r.Undo_BeginBlock()
      r.InsertTrackAtIndex(idx, true)
      local parent = r.GetTrack(0, idx)
      r.GetSetMediaTrackInfo_String(parent, "P_NAME", "Folder", true)
      r.SetMediaTrackInfo_Value(parent, "I_FOLDERDEPTH", 1)
      local child = r.GetTrack(0, idx + 1)
      local old_depth = r.GetMediaTrackInfo_Value(child, "I_FOLDERDEPTH")
      r.SetMediaTrackInfo_Value(child, "I_FOLDERDEPTH", old_depth - 1)
      local new_guid = r.GetTrackGUID(parent)
      local hidden = GetProjectMixerHiddenTracks()
      hidden[new_guid] = nil
      SaveProjectMixerHiddenTracks(hidden)
      local pmt = GetProjectMixerTracks()
      local has = false
      for _, g in ipairs(pmt) do if g == new_guid then has = true break end end
      if not has then
       local child_guid = r.GetTrackGUID(child)
       local insert_pos = #pmt + 1
       for i, g in ipairs(pmt) do if g == child_guid then insert_pos = i break end end
       table.insert(pmt, insert_pos, new_guid)
       SaveProjectMixerTracks(pmt)
      end
      r.Undo_EndBlock("TK Mixer: Create folder around track", -1)
      r.PreventUIRefresh(-1)
      r.TrackList_AdjustWindows(false)
      r.UpdateArrange()
     end
     local num_selected = r.CountSelectedTracks(0)
     local can_from_sel = num_selected >= 2 and r.IsTrackSelected(track)
     if not can_from_sel then r.ImGui_BeginDisabled(ctx) end
     if r.ImGui_MenuItem(ctx, "From Selected Tracks (" .. num_selected .. ")") then
      local min_idx, max_idx = math.huge, -1
      for i = 0, r.CountSelectedTracks(0) - 1 do
       local t = r.GetSelectedTrack(0, i)
       local n = math.floor(r.GetMediaTrackInfo_Value(t, "IP_TRACKNUMBER")) - 1
       if n < min_idx then min_idx = n end
       if n > max_idx then max_idx = n end
      end
      if min_idx ~= math.huge and max_idx >= min_idx then
       r.PreventUIRefresh(1)
       r.Undo_BeginBlock()
       r.InsertTrackAtIndex(min_idx, true)
       local parent = r.GetTrack(0, min_idx)
       r.GetSetMediaTrackInfo_String(parent, "P_NAME", "Folder", true)
       r.SetMediaTrackInfo_Value(parent, "I_FOLDERDEPTH", 1)
       local last = r.GetTrack(0, max_idx + 1)
       local old_depth = r.GetMediaTrackInfo_Value(last, "I_FOLDERDEPTH")
       r.SetMediaTrackInfo_Value(last, "I_FOLDERDEPTH", old_depth - 1)
       local new_guid = r.GetTrackGUID(parent)
       local hidden = GetProjectMixerHiddenTracks()
       hidden[new_guid] = nil
       SaveProjectMixerHiddenTracks(hidden)
       local pmt = GetProjectMixerTracks()
       local has = false
       for _, g in ipairs(pmt) do if g == new_guid then has = true break end end
       if not has then
        local first_child = r.GetTrack(0, min_idx + 1)
        local fc_guid = first_child and r.GetTrackGUID(first_child) or nil
        local insert_pos = #pmt + 1
        if fc_guid then
         for i, g in ipairs(pmt) do if g == fc_guid then insert_pos = i break end end
        end
        table.insert(pmt, insert_pos, new_guid)
        SaveProjectMixerTracks(pmt)
       end
       r.Undo_EndBlock("TK Mixer: Create folder from selection", -1)
       r.PreventUIRefresh(-1)
       r.TrackList_AdjustWindows(false)
       r.UpdateArrange()
      end
     end
     if not can_from_sel then r.ImGui_EndDisabled(ctx) end
     r.ImGui_EndMenu(ctx)
    end
    r.ImGui_Separator(ctx)
    local track_has_spacer = r.GetMediaTrackInfo_Value(track, "I_SPACER") > 0
    if track_has_spacer then
     if r.ImGui_MenuItem(ctx, "Remove Divider") then
      r.Undo_BeginBlock()
      r.SetMediaTrackInfo_Value(track, "I_SPACER", 0)
      r.TrackList_AdjustWindows(false)
      r.UpdateTimeline()
      r.Undo_EndBlock("Remove track divider", -1)
     end
    end
    if r.ImGui_MenuItem(ctx, "Hide from Mixer") then
     should_remove = true
    end
    local num_selected = r.CountSelectedTracks(0)
    if num_selected > 1 and r.IsTrackSelected(track) then
     if r.ImGui_MenuItem(ctx, "Delete Selected Tracks (" .. num_selected .. ")") then
      should_delete_selected = true
     end
    end
    if r.ImGui_MenuItem(ctx, "Delete Track") then
     should_delete = true
    end
    r.ImGui_EndMenu(ctx)
   end
  end
  
  if r.ImGui_BeginMenu(ctx, "Routing") then
   if r.ImGui_MenuItem(ctx, "Open Routing Window...") then
    r.SetOnlyTrackSelected(track)
    r.Main_OnCommand(40293, 0)
   end
   r.ImGui_Separator(ctx)
   local is_master_send = r.GetMediaTrackInfo_Value(track, "B_MAINSEND") == 1
   if r.ImGui_MenuItem(ctx, "Master/Parent Send", nil, is_master_send) then
    r.SetMediaTrackInfo_Value(track, "B_MAINSEND", is_master_send and 0 or 1)
   end
   r.ImGui_EndMenu(ctx)
  end
  
  if r.ImGui_BeginMenu(ctx, "FX") then
   if r.ImGui_MenuItem(ctx, "Show FX Chain...") then
    r.TrackFX_Show(track, 0, 1)
   end
   local fx_count = r.TrackFX_GetCount(track)
   local all_bypassed = true
   for i = 0, fx_count - 1 do
    if r.TrackFX_GetEnabled(track, i) then all_bypassed = false break end
   end
   if r.ImGui_MenuItem(ctx, "Bypass All FX", nil, all_bypassed) then
    for i = 0, fx_count - 1 do
     r.TrackFX_SetEnabled(track, i, all_bypassed)
    end
   end
   if fx_count > 0 then
    r.ImGui_Separator(ctx)
    if r.ImGui_MenuItem(ctx, "Clear FX Chain") then
     for i = fx_count - 1, 0, -1 do
      r.TrackFX_Delete(track, i)
     end
    end
   end
   r.ImGui_EndMenu(ctx)
  end
  
  if not is_master then
   if r.ImGui_BeginMenu(ctx, "Automation") then
    local current_mode = r.GetMediaTrackInfo_Value(track, "I_AUTOMODE")
    if r.ImGui_MenuItem(ctx, "Trim/Read", nil, current_mode == 0) then
     r.SetMediaTrackInfo_Value(track, "I_AUTOMODE", 0)
    end
    if r.ImGui_MenuItem(ctx, "Read", nil, current_mode == 1) then
     r.SetMediaTrackInfo_Value(track, "I_AUTOMODE", 1)
    end
    if r.ImGui_MenuItem(ctx, "Touch", nil, current_mode == 2) then
     r.SetMediaTrackInfo_Value(track, "I_AUTOMODE", 2)
    end
    if r.ImGui_MenuItem(ctx, "Write", nil, current_mode == 3) then
     r.SetMediaTrackInfo_Value(track, "I_AUTOMODE", 3)
    end
    if r.ImGui_MenuItem(ctx, "Latch", nil, current_mode == 4) then
     r.SetMediaTrackInfo_Value(track, "I_AUTOMODE", 4)
    end
    if r.ImGui_MenuItem(ctx, "Latch Preview", nil, current_mode == 5) then
     r.SetMediaTrackInfo_Value(track, "I_AUTOMODE", 5)
    end
    r.ImGui_Separator(ctx)
    if r.ImGui_MenuItem(ctx, "Show Track Envelopes...") then
     r.SetOnlyTrackSelected(track)
     r.Main_OnCommand(42678, 0)
    end
    r.ImGui_EndMenu(ctx)
   end
   
   if r.ImGui_BeginMenu(ctx, "Grouping") then
    local group_flags = r.GetSetTrackGroupMembership(track, "VOLUME_LEAD", 0, 0)
    local is_grouped = group_flags ~= 0
    if r.ImGui_MenuItem(ctx, "Group Selected Tracks") then
     r.Main_OnCommand(40497, 0)
    end
    if r.ImGui_MenuItem(ctx, "Remove from All Groups") then
     r.SetOnlyTrackSelected(track)
     r.Main_OnCommand(40500, 0)
    end
    r.ImGui_EndMenu(ctx)
   end
   
   if r.ImGui_BeginMenu(ctx, "Color") then
    if r.ImGui_MenuItem(ctx, "Set Track Color...") then
     local current_color = r.GetTrackColor(track)
     local rv, gv, bv = r.ColorFromNative(current_color)
     local retval, new_color = r.GR_SelectColor(r.GetMainHwnd(), r.ColorToNative(rv, gv, bv))
     if retval ~= 0 then
      r.SetTrackColor(track, new_color | 0x1000000)
     end
    end
    if r.ImGui_MenuItem(ctx, "Random Color") then
     local random_color = r.ColorToNative(math.random(50, 255), math.random(50, 255), math.random(50, 255)) | 0x1000000
     r.SetTrackColor(track, random_color)
    end
    if r.ImGui_MenuItem(ctx, "Remove Color") then
     r.SetTrackColor(track, 0)
    end
    if is_folder then
     r.ImGui_Separator(ctx)
     local parent_color = r.GetTrackColor(track)
     local has_color = parent_color ~= 0
     if not has_color then r.ImGui_BeginDisabled(ctx) end
     if r.ImGui_MenuItem(ctx, "Apply Color to Children") then
      local parent_idx = math.floor(r.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER")) - 1
      local end_idx = GetTrackBlockEnd(parent_idx)
      r.Undo_BeginBlock()
      for i = parent_idx + 1, end_idx do
       local ch = r.GetTrack(0, i)
       if ch then r.SetTrackColor(ch, parent_color) end
      end
      r.Undo_EndBlock("TK Mixer: Apply folder color to children", -1)
     end
     if r.ImGui_MenuItem(ctx, "Apply Gradient to Children") then
      local parent_idx = math.floor(r.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER")) - 1
      local end_idx = GetTrackBlockEnd(parent_idx)
      local count = end_idx - parent_idx
      if count > 0 then
       local pr, pg, pb = r.ColorFromNative(parent_color)
       r.Undo_BeginBlock()
       for i = 1, count do
        local t = (i / count) * 0.6
        local nr = math.floor(pr + (255 - pr) * t)
        local ng = math.floor(pg + (255 - pg) * t)
        local nb = math.floor(pb + (255 - pb) * t)
        local ch = r.GetTrack(0, parent_idx + i)
        if ch then r.SetTrackColor(ch, r.ColorToNative(nr, ng, nb) | 0x1000000) end
       end
       r.Undo_EndBlock("TK Mixer: Apply gradient color to children", -1)
      end
     end
     if not has_color then r.ImGui_EndDisabled(ctx) end
     if r.ImGui_MenuItem(ctx, "Clear Children Colors") then
      local parent_idx = math.floor(r.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER")) - 1
      local end_idx = GetTrackBlockEnd(parent_idx)
      r.Undo_BeginBlock()
      for i = parent_idx + 1, end_idx do
       local ch = r.GetTrack(0, i)
       if ch then r.SetTrackColor(ch, 0) end
      end
      r.Undo_EndBlock("TK Mixer: Clear children colors", -1)
     end
    end
    r.ImGui_EndMenu(ctx)
   end
   
   r.ImGui_Separator(ctx)
   
   if r.ImGui_BeginMenu(ctx, "Divider") then
    local current_spacer = r.GetMediaTrackInfo_Value(track, "I_SPACER")
    local has_divider = current_spacer > 0
    
    if has_divider then
     if r.ImGui_MenuItem(ctx, "Remove Divider") then
      r.SetMediaTrackInfo_Value(track, "I_SPACER", 0)
      r.TrackList_AdjustWindows(false)
      r.UpdateTimeline()
     end
     r.ImGui_Separator(ctx)
    end
    
    if r.ImGui_MenuItem(ctx, "Add Before This Track") then
     r.SetMediaTrackInfo_Value(track, "I_SPACER", 1)
     r.TrackList_AdjustWindows(false)
     r.UpdateTimeline()
    end
    
    local track_num = math.floor(r.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER"))
    local next_track = r.GetTrack(0, track_num)
    if next_track then
     if r.ImGui_MenuItem(ctx, "Add After This Track") then
      r.SetMediaTrackInfo_Value(next_track, "I_SPACER", 1)
      r.TrackList_AdjustWindows(false)
      r.UpdateTimeline()
     end
    end
    r.ImGui_EndMenu(ctx)
   end
   
   local is_tcp_pinned = r.GetMediaTrackInfo_Value(track, "B_TCPPIN") == 1
   local is_mcp_pinned = r.GetMediaTrackInfo_Value(track, "B_MCPPIN") == 1
   local is_pinned = is_tcp_pinned or is_mcp_pinned
   if r.ImGui_MenuItem(ctx, is_pinned and "Unpin Track" or "Pin Track") then
    local new_val = is_pinned and 0 or 1
    r.SetMediaTrackInfo_Value(track, "B_TCPPIN", new_val)
    r.SetMediaTrackInfo_Value(track, "B_MCPPIN", new_val)
   end
   
     if r.ImGui_BeginMenu(ctx, "Track Icon") then
      local current_icon = GetMixerIconPath(track)
      local has_icon = current_icon ~= nil and current_icon ~= ""
    
    if r.ImGui_MenuItem(ctx, "Track Icons...") then
     mixer_state.icon_target_track = track
     IconBrowser.SetBrowseMode("track_icons")
     IconBrowser.show_window = true
    end
    
    if r.ImGui_MenuItem(ctx, "Toolbar Icons...") then
     mixer_state.icon_target_track = track
     IconBrowser.SetBrowseMode("icons")
     IconBrowser.show_window = true
    end
    
    if r.ImGui_MenuItem(ctx, "Custom Images...") then
     mixer_state.icon_target_track = track
     IconBrowser.SetBrowseMode("images")
     IconBrowser.show_window = true
    end
    
      if has_icon then
       r.ImGui_Separator(ctx)
       if r.ImGui_MenuItem(ctx, "Remove Icon") then
        if settings.simple_mixer_hide_tcp_icons then
         r.GetSetMediaTrackInfo_String(track, "P_EXT:" .. TCP_ICON_EXT_KEY, "", true)
         r.GetSetMediaTrackInfo_String(track, "P_ICON", "", true)
        else
         r.GetSetMediaTrackInfo_String(track, "P_ICON", "", true)
        end
        ClearTrackIconCache(track)
       end
      end
      r.ImGui_EndMenu(ctx)
     end
  end
  
  r.ImGui_EndPopup(ctx)
 end
 if is_locked then r.ImGui_BeginDisabled(ctx) end

 if slider_color_pushed then
  r.ImGui_PopStyleColor(ctx, 5)
 end

 r.ImGui_Dummy(ctx, 0, 2)

 if not is_master and folder_color ~= 0 and (is_folder or is_child) and not settings.simple_mixer_show_folder_groups then
  local draw_list = r.ImGui_GetWindowDrawList(ctx)
  local cx, cy = r.ImGui_GetCursorScreenPos(ctx)
  local r_val, g_val, b_val = r.ColorFromNative(folder_color)
  local line_color = r.ImGui_ColorConvertDouble4ToU32(r_val/255, g_val/255, b_val/255, 1.0)
  local continue_line = folder_info.continue_line or false
  local line_end_x = cx + track_width
  if continue_line then
   local item_spacing = r.ImGui_GetStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing())
   line_end_x = line_end_x + item_spacing
  end
  r.ImGui_DrawList_AddRectFilled(draw_list, cx, cy - 5, line_end_x, cy - 3, line_color)
 end

 if settings.simple_mixer_show_track_icons and not is_master and track_icon_position == "section" then
  local section_height = settings.simple_mixer_track_icon_section_height or 40
  local draw_list = r.ImGui_GetWindowDrawList(ctx)
  local icon_x, icon_y = r.ImGui_GetCursorScreenPos(ctx)
  
  if settings.simple_mixer_track_icon_section_bg then
   local track_color = r.GetTrackColor(track)
   local btn_rounding = settings.simple_mixer_channel_rounding or 0
   local bg_color
   if track_color ~= 0 then
    local r_val, g_val, b_val = r.ColorFromNative(track_color)
    if is_track_selected then
     r_val = math.min(255, r_val + (255 - r_val) * 0.5)
     g_val = math.min(255, g_val + (255 - g_val) * 0.5)
     b_val = math.min(255, b_val + (255 - b_val) * 0.5)
    end
    bg_color = r.ImGui_ColorConvertDouble4ToU32(r_val/255, g_val/255, b_val/255, 0.7)
   elseif is_track_selected then
    bg_color = 0x4A90D9CC
   else
    bg_color = 0x333333AA
   end
   r.ImGui_DrawList_AddRectFilled(draw_list, icon_x, icon_y, icon_x + track_width, icon_y + section_height, bg_color, btn_rounding)
  end
  
  local opacity = settings.simple_mixer_track_icon_opacity or 1.0
  DrawTrackIcon(ctx, draw_list, track, icon_x, icon_y, track_width, section_height, opacity)
  r.ImGui_InvisibleButton(ctx, "##icon_section_btn", track_width, section_height)
  if not is_master and r.ImGui_IsItemHovered(ctx) and r.ImGui_IsMouseClicked(ctx, r.ImGui_MouseButton_Right()) then
   r.ImGui_OpenPopup(ctx, "FaderContextMenu##" .. idx)
  end
 end

 if settings.simple_mixer_show_rms and rms_position == "bottom" then
  local is_muted = r.GetMediaTrackInfo_Value(track, "B_MUTE") == 1
  local rms_off_color = settings.simple_mixer_rms_button_off_color or 0x404040FF
  local rms_text_color = settings.simple_mixer_rms_text_color or 0xFFFFFFFF
  
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), rms_text_color)
  
  if is_master then
   r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), is_muted and 0xFF6666FF or rms_off_color)
   if r.ImGui_Button(ctx, "M##rms_btm", track_width, 20) then
    r.SetMediaTrackInfo_Value(track, "B_MUTE", is_muted and 0 or 1)
   end
   r.ImGui_PopStyleColor(ctx, 1)
  else
   local is_armed = r.GetMediaTrackInfo_Value(track, "I_RECARM") == 1
   local is_solo = r.GetMediaTrackInfo_Value(track, "I_SOLO") > 0
   local rms_btn_width = (track_width - 6) / 3

   r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), is_armed and 0xFF0000FF or rms_off_color)
   if r.ImGui_Button(ctx, "R##rms_btm", rms_btn_width, 20) then
    r.SetMediaTrackInfo_Value(track, "I_RECARM", is_armed and 0 or 1)
   end
   r.ImGui_PopStyleColor(ctx, 1)

   r.ImGui_SameLine(ctx, 0, 3)

   r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), is_muted and 0xFF6666FF or rms_off_color)
   if r.ImGui_Button(ctx, "M##rms_btm", rms_btn_width, 20) then
    r.SetMediaTrackInfo_Value(track, "B_MUTE", is_muted and 0 or 1)
   end
   r.ImGui_PopStyleColor(ctx, 1)

   r.ImGui_SameLine(ctx, 0, 3)

   r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), is_solo and 0xFF8800FF or rms_off_color)
   if r.ImGui_Button(ctx, "S##rms_btm", rms_btn_width, 20) then
    if r.ImGui_IsKeyDown(ctx, r.ImGui_Mod_Shift()) then
     for i = 0, r.CountTracks(0) - 1 do
      local tr = r.GetTrack(0, i)
      if tr ~= track then
       r.SetMediaTrackInfo_Value(tr, "I_SOLO", 0)
      end
     end
     r.SetMediaTrackInfo_Value(track, "I_SOLO", 1)
    else
     r.SetMediaTrackInfo_Value(track, "I_SOLO", is_solo and 0 or 1)
    end
   end
   if r.ImGui_IsItemHovered(ctx) then
    r.ImGui_SetTooltip(ctx, "Solo\nShift+Click: Exclusive Solo")
   end
   r.ImGui_PopStyleColor(ctx, 1)
  end
  
  r.ImGui_PopStyleColor(ctx, 1)
 end

 local display_name
 if is_master then
  display_name = "MASTER"
 else
  local has_custom_name = track_name ~= "" and not track_name:match("^Track %d+$")
  if has_custom_name then
   display_name = track_name
  else
   display_name = ""
  end
 end
 local font_size = settings.simple_mixer_font_size or 12
 local estimated_char_width = font_size * 0.65
 local max_chars = math.floor(track_width / estimated_char_width)
 if max_chars < 2 then max_chars = 2 end

 if #display_name > max_chars then
  display_name = display_name:sub(1, max_chars)
 end

 local name_bg_drawn = false
 if settings.simple_mixer_track_name_bg_use_color and not is_master then
  local track_color = r.GetTrackColor(track)
  local draw_list = r.ImGui_GetWindowDrawList(ctx)
  local cx, cy = r.ImGui_GetCursorScreenPos(ctx)
  local text_h = r.ImGui_GetTextLineHeight(ctx)
  local bg_color
  if track_color ~= 0 then
   local r_val, g_val, b_val = r.ColorFromNative(track_color)
   if is_track_selected then
    r_val = math.min(255, r_val + (255 - r_val) * 0.5)
    g_val = math.min(255, g_val + (255 - g_val) * 0.5)
    b_val = math.min(255, b_val + (255 - b_val) * 0.5)
   end
   bg_color = r.ImGui_ColorConvertDouble4ToU32(r_val/255, g_val/255, b_val/255, 0.7)
  elseif is_track_selected then
   bg_color = 0x4A90D9CC
  else
   bg_color = 0x333333AA
  end
  r.ImGui_DrawList_AddRectFilled(draw_list, cx, cy, cx + track_width, cy + text_h + 2, bg_color, 2)
  name_bg_drawn = true
 elseif is_track_selected and not is_master then
  local bg_color = 0x4A90D9CC
  local draw_list = r.ImGui_GetWindowDrawList(ctx)
  local cx, cy = r.ImGui_GetCursorScreenPos(ctx)
  local text_h = r.ImGui_GetTextLineHeight(ctx)
  r.ImGui_DrawList_AddRectFilled(draw_list, cx, cy, cx + track_width, cy + text_h + 2, bg_color, 2)
  name_bg_drawn = true
 end

 r.ImGui_PushItemWidth(ctx, track_width)
 local name_color_pushed = false
 if settings.simple_mixer_track_name_use_color and not is_master then
  local track_color = r.GetTrackColor(track)
  if track_color ~= 0 then
   local r_val, g_val, b_val = r.ColorFromNative(track_color)
   
   if is_track_selected then
    r_val = math.min(255, r_val + (255 - r_val) * 0.5)
    g_val = math.min(255, g_val + (255 - g_val) * 0.5)
    b_val = math.min(255, b_val + (255 - b_val) * 0.5)
   end
   
   local text_color = r.ImGui_ColorConvertDouble4ToU32(r_val/255, g_val/255, b_val/255, 1.0)
   r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), text_color)
   name_color_pushed = true
  end
 end
 if not name_color_pushed then
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), settings.simple_mixer_channel_text_color or 0xFFFFFFFF)
  name_color_pushed = true
 end
 
 local track_guid = not is_master and r.GetTrackGUID(track) or nil
 local is_editing = (track_guid and mixer_state.editing_track_guid == track_guid)
 
 if is_editing then
  r.ImGui_SetNextItemWidth(ctx, track_width)
  local rv, new_name = r.ImGui_InputText(ctx, "##editname", mixer_state.editing_track_name, r.ImGui_InputTextFlags_EnterReturnsTrue() | r.ImGui_InputTextFlags_AutoSelectAll())
  if rv then
   r.GetSetMediaTrackInfo_String(track, "P_NAME", new_name, true)
   mixer_state.editing_track_guid = nil
   mixer_state.editing_track_name = ""
  elseif r.ImGui_IsItemDeactivated(ctx) then
   mixer_state.editing_track_guid = nil
   mixer_state.editing_track_name = ""
  end
  if not r.ImGui_IsItemActive(ctx) and r.ImGui_IsMouseClicked(ctx, r.ImGui_MouseButton_Left()) and not r.ImGui_IsItemHovered(ctx) then
   mixer_state.editing_track_guid = nil
   mixer_state.editing_track_name = ""
  end
 else
  local text_h = r.ImGui_GetTextLineHeight(ctx)
  local cursor_x, cursor_y = r.ImGui_GetCursorScreenPos(ctx)
  
  if is_folder and not is_master then
   local folder_guid = r.GetTrackGUID(track)
   local is_collapsed = mixer_state.collapsed_folders[folder_guid] or false
   local collapse_indicator = is_collapsed and "+" or "-"
   local indicator_width = r.ImGui_CalcTextSize(ctx, "+ ")
   
   r.ImGui_Text(ctx, collapse_indicator)
   r.ImGui_SameLine(ctx, 0, 2)
   r.ImGui_SetCursorScreenPos(ctx, cursor_x, cursor_y)
   if r.ImGui_InvisibleButton(ctx, "##collapse_btn", indicator_width, text_h) then
    mixer_state.collapsed_folders[folder_guid] = not is_collapsed
   end
   if r.ImGui_IsItemHovered(ctx) then
    r.ImGui_SetTooltip(ctx, is_collapsed and "Expand folder" or "Collapse folder")
   end
   
   r.ImGui_SameLine(ctx, 0, 0)
   local name_start_x = cursor_x + indicator_width
   local name_area_w = track_width - indicator_width
   local name_text_w = r.ImGui_CalcTextSize(ctx, display_name)
   local draw_x = name_start_x
   if settings.simple_mixer_track_name_centered and display_name ~= "" and name_text_w < name_area_w then
    draw_x = name_start_x + (name_area_w - name_text_w) / 2
   end
   r.ImGui_SetCursorScreenPos(ctx, draw_x, cursor_y)
   r.ImGui_Text(ctx, display_name)
   r.ImGui_SetCursorScreenPos(ctx, name_start_x, cursor_y)
   r.ImGui_InvisibleButton(ctx, "##name_area", name_area_w, text_h)
  else
   if is_master then
    local is_mono = r.GetToggleCommandState(40917) == 1
    local icon_size = 12
    local icon_spacing = 5
    local total_text_w = r.ImGui_CalcTextSize(ctx, display_name)
    local total_w = total_text_w + icon_spacing + icon_size
    local start_x = cursor_x + (track_width - total_w) / 2
    r.ImGui_SetCursorScreenPos(ctx, start_x, cursor_y)
    r.ImGui_Text(ctx, display_name)
    local draw_list = r.ImGui_GetWindowDrawList(ctx)
    local icon_x = start_x + total_text_w + icon_spacing
    local icon_y = cursor_y + (text_h - icon_size) / 2
    if is_mono then
     r.ImGui_DrawList_AddCircleFilled(draw_list, icon_x + icon_size/2, icon_y + icon_size/2, icon_size/2, 0xFFCC00FF)
    else
     r.ImGui_DrawList_AddCircleFilled(draw_list, icon_x + 3, icon_y + icon_size/2, 3, 0x00AAFFFF)
     r.ImGui_DrawList_AddCircleFilled(draw_list, icon_x + icon_size - 3, icon_y + icon_size/2, 3, 0x00AAFFFF)
    end
    r.ImGui_SetCursorScreenPos(ctx, cursor_x, cursor_y)
    if r.ImGui_InvisibleButton(ctx, "##master_mono_btn", track_width, text_h) then
     r.Main_OnCommand(40917, 0)
    end
   else
    if settings.simple_mixer_track_name_centered and display_name ~= "" then
     local name_w = r.ImGui_CalcTextSize(ctx, display_name)
     local centered_x = cursor_x + (track_width - name_w) / 2
     r.ImGui_SetCursorScreenPos(ctx, centered_x, cursor_y)
    end
    r.ImGui_Text(ctx, display_name)
    r.ImGui_SetCursorScreenPos(ctx, cursor_x, cursor_y)
    r.ImGui_InvisibleButton(ctx, "##name_area", track_width, text_h)
   end
  end
  if r.ImGui_IsItemHovered(ctx) then
   if is_master then
    local is_mono = r.GetMediaTrackInfo_Value(track, "B_MONO") == 1
    r.ImGui_SetTooltip(ctx, is_mono and "MASTER: MONO\nClick to toggle Stereo" or "MASTER: STEREO\nClick to toggle Mono")
   else
    r.ImGui_SetTooltip(ctx, track_name .. "\nClick to select | Double-click to rename")
   end
   if not is_master then
    if r.ImGui_IsMouseDoubleClicked(ctx, r.ImGui_MouseButton_Left()) then
     mixer_state.editing_track_guid = track_guid
     mixer_state.editing_track_name = track_name
    elseif r.ImGui_IsMouseClicked(ctx, r.ImGui_MouseButton_Left()) then
     local ctrl = r.ImGui_IsKeyDown(ctx, r.ImGui_Mod_Ctrl())
     local shift = r.ImGui_IsKeyDown(ctx, r.ImGui_Mod_Shift())
     if ctrl then
      r.SetTrackSelected(track, not r.IsTrackSelected(track))
     elseif shift then
      local last_touched = r.GetLastTouchedTrack()
      if last_touched and last_touched ~= track then
       local start_idx = r.CSurf_TrackToID(last_touched, false)
       local end_idx = r.CSurf_TrackToID(track, false)
       if start_idx > end_idx then start_idx, end_idx = end_idx, start_idx end
       for i = start_idx, end_idx do
        local range_track = r.CSurf_TrackFromID(i, false)
        if range_track then r.SetTrackSelected(range_track, true) end
       end
      else
       r.SetTrackSelected(track, true)
      end
     else
      r.SetOnlyTrackSelected(track)
     end
    end
    if r.ImGui_IsMouseClicked(ctx, r.ImGui_MouseButton_Right()) then
     r.ImGui_OpenPopup(ctx, "FaderContextMenu##" .. idx)
    end
   end
  end
 end
 
 if name_color_pushed then
  r.ImGui_PopStyleColor(ctx, 1)
 end
 r.ImGui_PopItemWidth(ctx)

 if is_locked then r.ImGui_EndDisabled(ctx) end

 r.ImGui_PopID(ctx)
 r.ImGui_EndGroup(ctx)
 r.ImGui_PopStyleVar(ctx)
 return should_remove or false, should_delete or false, should_delete_selected or false
end

local function DrawSectionHeader(ctx, label, setting_key, sidebar_width)
 if settings[setting_key] == nil then settings[setting_key] = true end
 local is_open = settings[setting_key]
 
 local header_color = 0x3A3A3AFF
 local header_hover_color = 0x4A4A4AFF
 local header_active_color = 0x5A5A5AFF
 local text_color = 0xFFFFFFFF
 
 r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), header_color)
 r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), header_hover_color)
 r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), header_active_color)
 
 local btn_w = sidebar_width - 8
 local btn_h = 16
 
 if r.ImGui_Button(ctx, "##sectionheader_" .. setting_key, btn_w, btn_h) then
  settings[setting_key] = not is_open
  is_open = settings[setting_key]
  SaveMixerSettings()
 end
 
 local btn_x, btn_y = r.ImGui_GetItemRectMin(ctx)
 local text_w = r.ImGui_CalcTextSize(ctx, label)
 local text_x = btn_x + (btn_w - text_w) / 2
 local text_y = btn_y + (btn_h - r.ImGui_GetTextLineHeight(ctx)) / 2
 local draw_list = r.ImGui_GetWindowDrawList(ctx)
 r.ImGui_DrawList_AddText(draw_list, text_x, text_y, text_color, label)
 
 r.ImGui_PopStyleColor(ctx, 3)
 
 return is_open
end

local function MarkTransportPresetChanged() SaveMixerSettings() end
local function ApplyTcpIconVisibility()
 local hide = settings.simple_mixer_hide_tcp_icons
 for i = 0, r.CountTracks(0) - 1 do
  local tr = r.GetTrack(0, i)
  if tr then
   local _, ext_icon = r.GetSetMediaTrackInfo_String(tr, "P_EXT:" .. TCP_ICON_EXT_KEY, "", false)
   local _, p_icon = r.GetSetMediaTrackInfo_String(tr, "P_ICON", "", false)
   if hide then
    if p_icon ~= "" then
     r.GetSetMediaTrackInfo_String(tr, "P_EXT:" .. TCP_ICON_EXT_KEY, p_icon, true)
     r.GetSetMediaTrackInfo_String(tr, "P_ICON", "", true)
     ClearTrackIconCache(tr)
    end
   else
    if ext_icon ~= "" then
     r.GetSetMediaTrackInfo_String(tr, "P_ICON", ext_icon, true)
     r.GetSetMediaTrackInfo_String(tr, "P_EXT:" .. TCP_ICON_EXT_KEY, "", true)
     ClearTrackIconCache(tr)
    end
   end
  end
 end
 r.TrackList_AdjustWindows(false)
end
local function ResetVUData() simple_mixer_vu_data = {} mixer_state.vu_data = simple_mixer_vu_data end
local function CleanupVUJSFX()
 for i = 0, r.CountTracks(0) - 1 do
  local tr = r.GetTrack(0, i)
  if tr then
   for fx = r.TrackFX_GetCount(tr) - 1, 0, -1 do
    local _, fname = r.TrackFX_GetFXName(tr, fx, "")
    if fname:match("TK_VU_Meter") then r.TrackFX_Delete(tr, fx) end
   end
  end
 end
 vu_jsfx_cache = {}
 vu_track_slots = {}
 vu_track_slot_counter = 0
end
local cached_system_fonts = nil

local function LoadCachedFonts()
 local cached = r.GetExtState("TK_Mixer", "cached_system_fonts")
 if cached and cached ~= "" then
  local fonts_list = {}
  for font in cached:gmatch("[^|]+") do
   table.insert(fonts_list, font)
  end
  if #fonts_list > 0 then
   cached_system_fonts = fonts_list
   return true
  end
 end
 return false
end

local function SaveCachedFonts(fonts_list)
 local str = table.concat(fonts_list, "|")
 r.SetExtState("TK_Mixer", "cached_system_fonts", str, true)
end

local function ScanSystemFonts()
 local fonts_list = {}
 local seen = {}
 local function add_font(name)
  name = name:gsub("%s*%(TrueType%)%s*$", "")
  name = name:gsub("%s*%(OpenType%)%s*$", "")
  name = name:gsub("%s*Bold%s*Italic%s*$", "")
  name = name:gsub("%s*Bold%s*$", "")
  name = name:gsub("%s*Italic%s*$", "")
  name = name:gsub("%s*Light%s*$", "")
  name = name:gsub("%s*Medium%s*$", "")
  name = name:gsub("%s*Semibold%s*$", "")
  name = name:gsub("%s*Black%s*$", "")
  name = name:gsub("%s*Thin%s*$", "")
  name = name:gsub("%s*Regular%s*$", "")
  name = name:gsub("%s+$", "")
  if name ~= "" and #name > 1 and not seen[name:lower()] then
   seen[name:lower()] = true
   table.insert(fonts_list, name)
  end
 end
 local os_name = r.GetOS()
 if os_name:match("Win") then
  local p = io.popen('reg query "HKLM\\SOFTWARE\\Microsoft\\Windows NT\\CurrentVersion\\Fonts" 2>nul')
  if p then
   for line in p:lines() do
    local font_name = line:match("^%s+(.-)%s+REG_SZ")
    if font_name then add_font(font_name) end
   end
   p:close()
  end
 elseif os_name:match("OSX") or os_name:match("macOS") then
  local p = io.popen('system_profiler SPFontsDataType 2>/dev/null | grep "Full Name:" | cut -d: -f2')
  if p then
   for line in p:lines() do
    local name = line:match("^%s*(.-)%s*$")
    if name then add_font(name) end
   end
   p:close()
  end
 else
  local p = io.popen('fc-list : family 2>/dev/null | sort -u')
  if p then
   for line in p:lines() do
    local name = line:match("^%s*(.-)%s*$")
    if name and name ~= "" then
     for part in name:gmatch("[^,]+") do
      part = part:match("^%s*(.-)%s*$")
      if part then add_font(part) end
     end
    end
   end
   p:close()
  end
 end
 if #fonts_list > 0 then
  table.sort(fonts_list, function(a, b) return a:lower() < b:lower() end)
  cached_system_fonts = fonts_list
  SaveCachedFonts(fonts_list)
  return fonts_list
 end
 return nil
end

local function HasCachedSystemFonts()
 if cached_system_fonts then return true end
 return LoadCachedFonts()
end

local function GetFontList(use_system_fonts)
 local builtin = {"Arial","Verdana","Tahoma","Calibri","Consolas","Helvetica","Times New Roman","Courier New"}
 if not use_system_fonts then return builtin end
 if cached_system_fonts then return cached_system_fonts end
 if LoadCachedFonts() then return cached_system_fonts end
 return builtin
end
local function GetMixerFontFlags(style)
 style = style or 1
 local flags = 0
 if style == 2 or style == 4 then flags = flags | r.ImGui_FontFlags_Bold() end
 if style == 3 or style == 4 then flags = flags | r.ImGui_FontFlags_Italic() end
 return flags
end

local function RebuildSectionFonts()
 font_simple_mixer_dirty = true
 font_loaded = false
end

local function EnsureSimpleMixerFont()
 if not font_simple_mixer_dirty then return end
 local font_name = settings.simple_mixer_font_name or fonts[settings.simple_mixer_font or 1] or "Arial"
 local style = settings.simple_mixer_font_style or 1
 local new_font = r.ImGui_CreateFont(font_name, GetMixerFontFlags(style))
 if font_simple_mixer then
  pcall(r.ImGui_Detach, ctx, font_simple_mixer)
 end
 r.ImGui_Attach(ctx, new_font)
 font_simple_mixer = new_font
 font_simple_mixer_dirty = false
end
local font_styles = { {name="Regular"}, {name="Bold"}, {name="Italic"}, {name="Bold Italic"} }
local fonts = {"Arial","Verdana","Tahoma","Calibri","Consolas"}

local function PushSettingsTheme(c)
 r.ImGui_PushStyleVar(c, r.ImGui_StyleVar_WindowRounding(), 8)
 r.ImGui_PushStyleVar(c, r.ImGui_StyleVar_FrameRounding(), 4)
 r.ImGui_PushStyleVar(c, r.ImGui_StyleVar_FramePadding(), 4, 2)
 r.ImGui_PushStyleVar(c, r.ImGui_StyleVar_PopupRounding(), 4)
 r.ImGui_PushStyleVar(c, r.ImGui_StyleVar_GrabRounding(), 4)
 r.ImGui_PushStyleVar(c, r.ImGui_StyleVar_GrabMinSize(), 10)
 r.ImGui_PushStyleVar(c, r.ImGui_StyleVar_WindowBorderSize(), 1)
 r.ImGui_PushStyleVar(c, r.ImGui_StyleVar_FrameBorderSize(), 0)

 r.ImGui_PushStyleColor(c, r.ImGui_Col_WindowBg(), 0x1E1E1EFF)
 r.ImGui_PushStyleColor(c, r.ImGui_Col_FrameBg(), 0x2D2D2DFF)
 r.ImGui_PushStyleColor(c, r.ImGui_Col_FrameBgHovered(), 0x3D3D3DFF)
 r.ImGui_PushStyleColor(c, r.ImGui_Col_FrameBgActive(), 0x4D4D4DFF)
 r.ImGui_PushStyleColor(c, r.ImGui_Col_SliderGrab(), 0x0078D7FF)
 r.ImGui_PushStyleColor(c, r.ImGui_Col_SliderGrabActive(), 0x1E90FFFF)
 r.ImGui_PushStyleColor(c, r.ImGui_Col_CheckMark(), 0x0078D7FF)
 r.ImGui_PushStyleColor(c, r.ImGui_Col_Button(), 0x2D2D2DFF)
 r.ImGui_PushStyleColor(c, r.ImGui_Col_ButtonHovered(), 0x3D3D3DFF)
 r.ImGui_PushStyleColor(c, r.ImGui_Col_ButtonActive(), 0x4D4D4DFF)
 r.ImGui_PushStyleColor(c, r.ImGui_Col_Border(), 0x3C3C3CFF)
 r.ImGui_PushStyleColor(c, r.ImGui_Col_Text(), 0xFFFFFFFF)
 r.ImGui_PushStyleColor(c, r.ImGui_Col_PopupBg(), 0x1E1E1EFF)
end

local function PopSettingsTheme(c)
 r.ImGui_PopStyleColor(c, 13)
 r.ImGui_PopStyleVar(c, 8)
end

local function DrawSettingsHeader(c, title)
 local window_width = r.ImGui_GetWindowWidth(c)
 r.ImGui_PushStyleColor(c, r.ImGui_Col_Text(), 0xFF0000FF)
 r.ImGui_Text(c, "TK")
 r.ImGui_PopStyleColor(c)
 r.ImGui_SameLine(c)
 r.ImGui_Text(c, title)
 r.ImGui_SameLine(c)
 r.ImGui_PushStyleColor(c, r.ImGui_Col_Text(), 0x888888FF)
 r.ImGui_Text(c, "v" .. script_version)
 r.ImGui_PopStyleColor(c)
 if mixer_settings_dirty then
  r.ImGui_SameLine(c)
  r.ImGui_PushStyleColor(c, r.ImGui_Col_Text(), 0xFFAA00FF)
  r.ImGui_Text(c, "*")
  r.ImGui_PopStyleColor(c)
  if r.ImGui_IsItemHovered(c) then
   r.ImGui_SetTooltip(c, "Unsaved changes")
  end
 end
 r.ImGui_SameLine(c)
 r.ImGui_SetCursorPosX(c, window_width - 70)
 r.ImGui_SetCursorPosY(c, 4)
 local save_btn_color = mixer_settings_dirty and 0x4A8A4AFF or 0x3A3A3AFF
 local save_btn_hover = mixer_settings_dirty and 0x5AAA5AFF or 0x4A4A4AFF
 r.ImGui_PushStyleColor(c, r.ImGui_Col_Button(), save_btn_color)
 r.ImGui_PushStyleColor(c, r.ImGui_Col_ButtonHovered(), save_btn_hover)
 r.ImGui_PushStyleColor(c, r.ImGui_Col_ButtonActive(), save_btn_hover)
 if r.ImGui_Button(c, "Save##settings_save", 40, 18) then
  WriteMixerSettingsToDisk()
 end
 r.ImGui_PopStyleColor(c, 3)
 if r.ImGui_IsItemHovered(c) then
  r.ImGui_SetTooltip(c, "Save mixer settings to disk")
 end
 r.ImGui_SameLine(c)
 r.ImGui_SetCursorPosX(c, window_width - 25)
 r.ImGui_SetCursorPosY(c, 6)
 r.ImGui_PushStyleColor(c, r.ImGui_Col_Button(), 0xFF0000FF)
 r.ImGui_PushStyleColor(c, r.ImGui_Col_ButtonHovered(), 0xFF3333FF)
 r.ImGui_PushStyleColor(c, r.ImGui_Col_ButtonActive(), 0xFF6666FF)
 local close_clicked = r.ImGui_Button(c, "##settings_close", 14, 14)
 r.ImGui_PopStyleColor(c, 3)
 return close_clicked
end

local function DrawSettingsWindow()
 if not settings.simple_mixer_settings_popup_open then return end
 r.ImGui_SetNextWindowSize(ctx, 560, 560)
 PushSettingsTheme(ctx)
 local settings_flags = r.ImGui_WindowFlags_NoTitleBar() | r.ImGui_WindowFlags_NoCollapse() | r.ImGui_WindowFlags_NoResize() | r.ImGui_WindowFlags_NoScrollbar() | r.ImGui_WindowFlags_NoScrollWithMouse()
 local visible, open = r.ImGui_Begin(ctx, "TK Mixer Settings", true, settings_flags)
 if visible then
  if not font_settings_ui then
   font_settings_ui = r.ImGui_CreateFont('Arial', 0)
   r.ImGui_Attach(ctx, font_settings_ui)
  end
  r.ImGui_PushFont(ctx, font_settings_ui, 13)
  if DrawSettingsHeader(ctx, "MIXER") then open = false end
  r.ImGui_Spacing(ctx)
  local rv
  local main_window_width = settings.simple_mixer_window_width or 600
  local main_window_height = settings.simple_mixer_window_height or 700
  mixer_state.settings_top_tab = mixer_state.settings_top_tab or 1
  do
   local _tabs_def = {
    { label = "Mixer",    idx = 1 },
    { label = "Meters",   idx = 2 },
    { label = "Channels", idx = 3 },
    { label = "Strip",    idx = 4 },
    { label = "FX Slots", idx = 5 },
    { label = "Dividers", idx = 6 },
    { label = "Folders",  idx = 7 },
   }
   local _gap = 6
   local _active_color = 0x2D7FE6FF
   local _hover_color  = 0x3D8FF2FF
   local _idle_color   = 0x4A4A4AFF
   local _avail_w = select(1, r.ImGui_GetContentRegionAvail(ctx))
   local _btn_w = math.floor((_avail_w - _gap * (#_tabs_def - 1)) / #_tabs_def)
   r.ImGui_Separator(ctx)
   r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing(), _gap, 0)
   for i, t in ipairs(_tabs_def) do
    if i > 1 then r.ImGui_SameLine(ctx) end
    local is_active = (mixer_state.settings_top_tab == t.idx)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(),        is_active and _active_color or _idle_color)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), is_active and _active_color or _hover_color)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(),  _active_color)
    local w = (i == #_tabs_def) and math.max(1, _avail_w - (_btn_w + _gap) * (#_tabs_def - 1)) or _btn_w
    if r.ImGui_Button(ctx, t.label, w, 0) then
     mixer_state.settings_top_tab = t.idx
    end
    r.ImGui_PopStyleColor(ctx, 3)
   end
   r.ImGui_PopStyleVar(ctx)
   r.ImGui_Spacing(ctx)
   r.ImGui_Separator(ctx)
  end
  r.ImGui_BeginChild(ctx, "##settings_content", 0, 0, 0)
  if true then
  if mixer_state.settings_top_tab == 1 then
   mixer_state.settings_tab = 1
   r.ImGui_Spacing(ctx)
   
   if r.ImGui_BeginTable(ctx, "MixerGeneralTable", 2, r.ImGui_TableFlags_None()) then
    r.ImGui_TableSetupColumn(ctx, "col1", r.ImGui_TableColumnFlags_WidthStretch())
    r.ImGui_TableSetupColumn(ctx, "col2", r.ImGui_TableColumnFlags_WidthStretch())
    
    r.ImGui_TableNextRow(ctx)
    r.ImGui_TableNextColumn(ctx)
    rv, settings.simple_mixer_remember_state = r.ImGui_Checkbox(ctx, "Remember Window State", settings.simple_mixer_remember_state ~= false)
    if rv then
     r.SetExtState("TK_TRANSPORT", "simple_mixer_remember_state", tostring(settings.simple_mixer_remember_state), true)
    end
    r.ImGui_TableNextColumn(ctx)
    if r.ImGui_IsItemHovered(ctx) then
     r.ImGui_SetTooltip(ctx, "When enabled, the mixer window will reopen automatically if it was open when REAPER was closed.")
    end
    
    r.ImGui_TableNextRow(ctx)
    r.ImGui_TableNextColumn(ctx)
    r.ImGui_Text(ctx, "Channel Width:")
    r.ImGui_TableNextColumn(ctx)
    r.ImGui_SetNextItemWidth(ctx, -1)
    rv, settings.simple_mixer_channel_width = r.ImGui_SliderInt(ctx, "##ChannelW", settings.simple_mixer_channel_width or 70, 60, 160, "%d px")
    
    r.ImGui_TableNextRow(ctx)
    r.ImGui_TableNextColumn(ctx)
    rv, settings.simple_mixer_show_master = r.ImGui_Checkbox(ctx, "Show Master", settings.simple_mixer_show_master or false)
    r.ImGui_TableNextColumn(ctx)
    if settings.simple_mixer_show_master then
     if r.ImGui_RadioButton(ctx, "Left", settings.simple_mixer_master_position == "left") then
      settings.simple_mixer_master_position = "left"
     end
     r.ImGui_SameLine(ctx)
     if r.ImGui_RadioButton(ctx, "Right", settings.simple_mixer_master_position == "right") then
      settings.simple_mixer_master_position = "right"
     end
    end
    
    r.ImGui_TableNextRow(ctx)
    r.ImGui_TableNextColumn(ctx)
    rv, settings.simple_mixer_show_pinned_first = r.ImGui_Checkbox(ctx, "Show Pinned Tracks First", settings.simple_mixer_show_pinned_first or false)
    r.ImGui_TableNextColumn(ctx)
    if r.ImGui_IsItemHovered(ctx) then
     r.ImGui_SetTooltip(ctx, "Tracks pinned in REAPER (B_TCPPIN) will be shown at the beginning of the mixer, similar to the master track.")
    end
    
    r.ImGui_TableNextRow(ctx)
    r.ImGui_TableNextColumn(ctx)
    rv, settings.simple_mixer_show_track_icons = r.ImGui_Checkbox(ctx, "Show Track Icons", settings.simple_mixer_show_track_icons)
    if settings.simple_mixer_show_track_icons == nil then settings.simple_mixer_show_track_icons = true end
    r.ImGui_TableNextColumn(ctx)
      if r.ImGui_IsItemHovered(ctx) then
       r.ImGui_SetTooltip(ctx, "Display track icons as background in the volume slider. Set icons via right-click menu.")
      end

      r.ImGui_TableNextRow(ctx)
      r.ImGui_TableNextColumn(ctx)
      rv, settings.simple_mixer_hide_tcp_icons = r.ImGui_Checkbox(ctx, "Hide TCP Icons", settings.simple_mixer_hide_tcp_icons or false)
      if rv then
       ApplyTcpIconVisibility()
      end
      r.ImGui_TableNextColumn(ctx)
      if r.ImGui_IsItemHovered(ctx) then
       r.ImGui_SetTooltip(ctx, "Hide REAPER TCP icons but keep them visible in the TK mixer.")
      end
      
      if settings.simple_mixer_show_track_icons then
     r.ImGui_TableNextRow(ctx)
     r.ImGui_TableNextColumn(ctx)
     r.ImGui_Text(ctx, "Icon Display:")
     r.ImGui_TableNextColumn(ctx)
     r.ImGui_SetNextItemWidth(ctx, 100)
     local icon_pos = settings.simple_mixer_track_icon_position or "overlay"
     local icon_pos_idx = icon_pos == "section" and 1 or 0
     local rv_pos, new_idx = r.ImGui_Combo(ctx, "##IconDisplay", icon_pos_idx, "Overlay\0Section\0")
     if rv_pos then
      settings.simple_mixer_track_icon_position = new_idx == 0 and "overlay" or "section"
     end
     if r.ImGui_IsItemHovered(ctx) then
      r.ImGui_SetTooltip(ctx, "Overlay = on the fader, Section = separate area below fader")
     end
     
     if settings.simple_mixer_track_icon_position == "section" then
      r.ImGui_TableNextRow(ctx)
      r.ImGui_TableNextColumn(ctx)
      r.ImGui_Text(ctx, "Section Height:")
      r.ImGui_TableNextColumn(ctx)
      r.ImGui_SetNextItemWidth(ctx, 100)
      rv, settings.simple_mixer_track_icon_section_height = r.ImGui_SliderInt(ctx, "##IconSectionH", settings.simple_mixer_track_icon_section_height or 40, 24, 80, "%d px")
      
      r.ImGui_TableNextRow(ctx)
      r.ImGui_TableNextColumn(ctx)
      rv, settings.simple_mixer_track_icon_section_bg = r.ImGui_Checkbox(ctx, "Section Background", settings.simple_mixer_track_icon_section_bg ~= false)
      r.ImGui_TableNextColumn(ctx)
      if r.ImGui_IsItemHovered(ctx) then
       r.ImGui_SetTooltip(ctx, "Show track color as background for the icon section")
      end
     end

     r.ImGui_TableNextRow(ctx)
     r.ImGui_TableNextColumn(ctx)
     r.ImGui_Text(ctx, "Icon Opacity:")
     r.ImGui_TableNextColumn(ctx)
     r.ImGui_SetNextItemWidth(ctx, 100)
     rv, settings.simple_mixer_track_icon_opacity = r.ImGui_SliderDouble(ctx, "##IconOpacity", settings.simple_mixer_track_icon_opacity or 0.3, 0.1, 1.0, "%.1f")
     
     r.ImGui_TableNextRow(ctx)
     r.ImGui_TableNextColumn(ctx)
     r.ImGui_Text(ctx, "Icon Size:")
     r.ImGui_TableNextColumn(ctx)
     r.ImGui_SetNextItemWidth(ctx, 100)
     rv, settings.simple_mixer_track_icon_size = r.ImGui_SliderDouble(ctx, "##IconSize", settings.simple_mixer_track_icon_size or 1.0, 0.3, 2.0, "%.1f")
     
     r.ImGui_TableNextRow(ctx)
     r.ImGui_TableNextColumn(ctx)
     r.ImGui_Text(ctx, "Icon Position:")
     r.ImGui_TableNextColumn(ctx)
     r.ImGui_SetNextItemWidth(ctx, 100)
     rv, settings.simple_mixer_track_icon_vertical_pos = r.ImGui_SliderDouble(ctx, "##IconVPos", settings.simple_mixer_track_icon_vertical_pos or 0.5, 0.0, 1.0, "%.1f")
     if r.ImGui_IsItemHovered(ctx) then
      r.ImGui_SetTooltip(ctx, "0 = Top, 0.5 = Center, 1 = Bottom")
     end
    end
    
    r.ImGui_EndTable(ctx)
   end
   
   r.ImGui_Separator(ctx)
   r.ImGui_Spacing(ctx)
   r.ImGui_Text(ctx, "Window Colors:")
   
   if r.ImGui_BeginTable(ctx, "WinColorsTable", 2, r.ImGui_TableFlags_None()) then
    r.ImGui_TableNextRow(ctx)
    r.ImGui_TableNextColumn(ctx)
    rv, settings.simple_mixer_window_bg_color = r.ImGui_ColorEdit4(ctx, "Background##WinBg", settings.simple_mixer_window_bg_color or 0x1E1E1EFF, r.ImGui_ColorEditFlags_NoInputs())
    r.ImGui_TableNextColumn(ctx)
    rv, settings.simple_mixer_border_color = r.ImGui_ColorEdit4(ctx, "Border##WinBorder", settings.simple_mixer_border_color or 0x444444FF, r.ImGui_ColorEditFlags_NoInputs())
    r.ImGui_EndTable(ctx)
   end
   
   r.ImGui_Separator(ctx)
   r.ImGui_Spacing(ctx)
   r.ImGui_Text(ctx, "Font:")
   
   if r.ImGui_BeginTable(ctx, "MixerFontTable", 2, r.ImGui_TableFlags_None()) then
    r.ImGui_TableSetupColumn(ctx, "col1", r.ImGui_TableColumnFlags_WidthStretch())
    r.ImGui_TableSetupColumn(ctx, "col2", r.ImGui_TableColumnFlags_WidthStretch())
    
    r.ImGui_TableNextRow(ctx)
    r.ImGui_TableNextColumn(ctx)
    r.ImGui_Text(ctx, "Font:")
    r.ImGui_SameLine(ctx)
    r.ImGui_SetNextItemWidth(ctx, -30)
    local font_list = GetFontList(settings.use_system_fonts)
    local current_font = settings.simple_mixer_font_name or fonts[settings.simple_mixer_font or 1] or fonts[1]
    local current_idx = 0
    for i, f in ipairs(font_list) do
     if f == current_font then current_idx = i - 1; break end
    end
    local rv_font, new_idx = r.ImGui_Combo(ctx, "##MixerFont", current_idx, table.concat(font_list, '\0') .. '\0')
    if rv_font then
     settings.simple_mixer_font_name = font_list[new_idx + 1]
     settings.simple_mixer_font = nil
     RebuildSectionFonts()
    end
    r.ImGui_SameLine(ctx)
    local rv_sys, new_sys = r.ImGui_Checkbox(ctx, "##MixerSys", settings.use_system_fonts or false)
    if rv_sys then
     settings.use_system_fonts = new_sys
     if new_sys and not HasCachedSystemFonts() then
      ScanSystemFonts()
     end
     RebuildSectionFonts()
     SaveMixerSettings()
    end
    if r.ImGui_IsItemHovered(ctx) then
     local status = ""
     if HasCachedSystemFonts() then
      status = string.format("\n(%d system fonts loaded)", #(cached_system_fonts or {}))
     end
     r.ImGui_SetTooltip(ctx, "Use System Fonts" .. status)
    end
    
    r.ImGui_TableNextColumn(ctx)
    r.ImGui_Text(ctx, "Size:")
    r.ImGui_SameLine(ctx)
    r.ImGui_SetNextItemWidth(ctx, -1)
    rv, settings.simple_mixer_font_size = r.ImGui_SliderInt(ctx, "##MixerFontSize", settings.simple_mixer_font_size or 12, 9, 13, "%d")
    if rv then RebuildSectionFonts() end
    
    r.ImGui_TableNextRow(ctx)
    r.ImGui_TableNextColumn(ctx)
    r.ImGui_Text(ctx, "Style:")
    r.ImGui_SameLine(ctx)
    r.ImGui_SetNextItemWidth(ctx, -1)
    local current_style = settings.simple_mixer_font_style or 1
    local current_style_name = font_styles[current_style] and font_styles[current_style].name or "Regular"
    if r.ImGui_BeginCombo(ctx, "##MixerFontStyle", current_style_name) then
     for i, style in ipairs(font_styles) do
      if r.ImGui_Selectable(ctx, style.name, i == current_style) then
       settings.simple_mixer_font_style = i
       RebuildSectionFonts()
      end
     end
     r.ImGui_EndCombo(ctx)
    end
    
    r.ImGui_TableNextColumn(ctx)
    rv, settings.simple_mixer_channel_text_color = r.ImGui_ColorEdit4(ctx, "Text Color##MixerText", settings.simple_mixer_channel_text_color or 0xFFFFFFFF, r.ImGui_ColorEditFlags_NoInputs())
    
    r.ImGui_EndTable(ctx)
   end
   
   r.ImGui_Separator(ctx)
   r.ImGui_Spacing(ctx)
   r.ImGui_Text(ctx, "Collapsed Sidebar Text:")
   r.ImGui_SetNextItemWidth(ctx, -1)
   rv, settings.simple_mixer_sidebar_text = r.ImGui_InputText(ctx, "##SidebarText", settings.simple_mixer_sidebar_text or "")
   if r.ImGui_IsItemHovered(ctx) then
    r.ImGui_SetTooltip(ctx, "Text shown vertically (top to bottom) in the collapsed sidebar.\nLeave empty to disable.")
   end
   if r.ImGui_BeginTable(ctx, "SidebarTextTable", 2, r.ImGui_TableFlags_None()) then
    r.ImGui_TableSetupColumn(ctx, "col1", r.ImGui_TableColumnFlags_WidthStretch())
    r.ImGui_TableSetupColumn(ctx, "col2", r.ImGui_TableColumnFlags_WidthStretch())
    r.ImGui_TableNextRow(ctx)
    r.ImGui_TableNextColumn(ctx)
    r.ImGui_Text(ctx, "Size:")
    r.ImGui_SameLine(ctx)
    r.ImGui_SetNextItemWidth(ctx, -1)
    rv, settings.simple_mixer_sidebar_text_size = r.ImGui_SliderInt(ctx, "##SidebarTextSize", settings.simple_mixer_sidebar_text_size or 14, 8, 32, "%d px")
    r.ImGui_TableNextColumn(ctx)
    rv, settings.simple_mixer_sidebar_text_color = r.ImGui_ColorEdit4(ctx, "Color##SidebarTextColor", settings.simple_mixer_sidebar_text_color or 0xAAAAAAFF, r.ImGui_ColorEditFlags_NoInputs())
    r.ImGui_EndTable(ctx)
   end
   
  end
  
  if mixer_state.settings_top_tab == 2 then
   mixer_state.settings_tab = 5
   r.ImGui_Spacing(ctx)
   
   rv, settings.simple_mixer_show_meters = r.ImGui_Checkbox(ctx, "Show Meters", settings.simple_mixer_show_meters ~= false)
   if r.ImGui_IsItemHovered(ctx) then
    r.ImGui_SetTooltip(ctx, "Display peak meters next to volume faders (50/50 split)")
   end
   
   if settings.simple_mixer_show_meters then
    r.ImGui_Separator(ctx)
    r.ImGui_Spacing(ctx)
    r.ImGui_Text(ctx, "Display Options:")
    
    if r.ImGui_BeginTable(ctx, "MeterOptionsTable", 2, r.ImGui_TableFlags_None()) then
     r.ImGui_TableNextRow(ctx)
     r.ImGui_TableNextColumn(ctx)
     rv, settings.simple_mixer_meter_show_ticks = r.ImGui_Checkbox(ctx, "Show dB Ticks", settings.simple_mixer_meter_show_ticks ~= false)
     if r.ImGui_IsItemHovered(ctx) then
      r.ImGui_SetTooltip(ctx, "Show tick marks at 0, -6, -12, -24, -48 dB")
     end
     r.ImGui_SameLine(ctx)
     r.ImGui_SetNextItemWidth(ctx, 100)
     rv, settings.simple_mixer_meter_tick_size = r.ImGui_SliderInt(ctx, "Size##MtrTickSize", settings.simple_mixer_meter_tick_size or 8, 6, 20, "%d px")
     r.ImGui_TableNextColumn(ctx)
     rv, settings.simple_mixer_show_gain_staging = r.ImGui_Checkbox(ctx, "Gain Staging", settings.simple_mixer_show_gain_staging ~= false)
     if r.ImGui_IsItemHovered(ctx) then
      r.ImGui_SetTooltip(ctx, "Show level indicator (HOT/Loud/Low)")
     end
     r.ImGui_TableNextRow(ctx)
     r.ImGui_TableNextColumn(ctx)
     r.ImGui_Text(ctx, "Segment Gap:")
     r.ImGui_SameLine(ctx)
     r.ImGui_SetNextItemWidth(ctx, 60)
     rv, settings.simple_mixer_meter_segment_gap = r.ImGui_SliderInt(ctx, "##SegGap", settings.simple_mixer_meter_segment_gap or 1, 0, 3)
     r.ImGui_TableNextColumn(ctx)
     r.ImGui_Text(ctx, "Meter Width:")
     r.ImGui_SameLine(ctx)
     r.ImGui_SetNextItemWidth(ctx, 80)
     rv, settings.simple_mixer_meter_width = r.ImGui_SliderInt(ctx, "##MeterW", settings.simple_mixer_meter_width or 12, 4, 40)
     if r.ImGui_IsItemHovered(ctx) then
      r.ImGui_SetTooltip(ctx, "Width of the peak meter in pixels.\nWider meter = narrower fader.")
     end
     r.ImGui_EndTable(ctx)
    end
    
    r.ImGui_Separator(ctx)
    r.ImGui_Spacing(ctx)
    r.ImGui_Text(ctx, "Behavior:")
    
    if r.ImGui_BeginTable(ctx, "MeterBehaviorTable", 2, r.ImGui_TableFlags_None()) then
     r.ImGui_TableNextRow(ctx)
     r.ImGui_TableNextColumn(ctx)
     r.ImGui_Text(ctx, "Decay Speed:")
     r.ImGui_SetNextItemWidth(ctx, -1)
     rv, settings.simple_mixer_meter_decay_speed = r.ImGui_SliderDouble(ctx, "##Decay", settings.simple_mixer_meter_decay_speed or 0.92, 0.8, 0.99, "%.2f")
     if r.ImGui_IsItemHovered(ctx) then
      r.ImGui_SetTooltip(ctx, "How fast the meter falls back (higher = slower)")
     end
     
     r.ImGui_TableNextColumn(ctx)
     r.ImGui_Text(ctx, "Peak Hold Time:")
     r.ImGui_SetNextItemWidth(ctx, -1)
     rv, settings.simple_mixer_meter_hold_time = r.ImGui_SliderDouble(ctx, "##Hold", settings.simple_mixer_meter_hold_time or 1.5, 0.5, 3.0, "%.1f s")
     if r.ImGui_IsItemHovered(ctx) then
      r.ImGui_SetTooltip(ctx, "How long the peak indicator stays visible")
     end
     r.ImGui_EndTable(ctx)
    end
    
    r.ImGui_Separator(ctx)
    r.ImGui_Spacing(ctx)
    r.ImGui_Text(ctx, "Colors:")
    
    if r.ImGui_BeginTable(ctx, "MeterColorsTable", 2, r.ImGui_TableFlags_None()) then
     r.ImGui_TableNextRow(ctx)
     r.ImGui_TableNextColumn(ctx)
     rv, settings.simple_mixer_meter_color_normal = r.ImGui_ColorEdit4(ctx, "Normal##MtrNorm", settings.simple_mixer_meter_color_normal or 0x00CC00FF, r.ImGui_ColorEditFlags_NoInputs())
     r.ImGui_TableNextColumn(ctx)
     rv, settings.simple_mixer_meter_color_mid = r.ImGui_ColorEdit4(ctx, "Mid##MtrMid", settings.simple_mixer_meter_color_mid or 0xCCFF00FF, r.ImGui_ColorEditFlags_NoInputs())
     
     r.ImGui_TableNextRow(ctx)
     r.ImGui_TableNextColumn(ctx)
     rv, settings.simple_mixer_meter_color_high = r.ImGui_ColorEdit4(ctx, "High##MtrHigh", settings.simple_mixer_meter_color_high or 0xFFFF00FF, r.ImGui_ColorEditFlags_NoInputs())
     r.ImGui_TableNextColumn(ctx)
     rv, settings.simple_mixer_meter_color_clip = r.ImGui_ColorEdit4(ctx, "Clip##MtrClip", settings.simple_mixer_meter_color_clip or 0xFF0000FF, r.ImGui_ColorEditFlags_NoInputs())
     
     r.ImGui_TableNextRow(ctx)
     r.ImGui_TableNextColumn(ctx)
     rv, settings.simple_mixer_meter_bg_color = r.ImGui_ColorEdit4(ctx, "Background##MtrBg", settings.simple_mixer_meter_bg_color or 0x1A1A1AFF, r.ImGui_ColorEditFlags_NoInputs())
     r.ImGui_TableNextColumn(ctx)
     
     r.ImGui_TableNextRow(ctx)
     r.ImGui_TableNextColumn(ctx)
     rv, settings.simple_mixer_meter_tick_color_below = r.ImGui_ColorEdit4(ctx, "Tick (below)##MtrTickBelow", settings.simple_mixer_meter_tick_color_below or 0x888888FF, r.ImGui_ColorEditFlags_NoInputs())
     if r.ImGui_IsItemHovered(ctx) then
      r.ImGui_SetTooltip(ctx, "Tick color when meter is below this level")
     end
     r.ImGui_TableNextColumn(ctx)
     rv, settings.simple_mixer_meter_tick_color_above = r.ImGui_ColorEdit4(ctx, "Tick (above)##MtrTickAbove", settings.simple_mixer_meter_tick_color_above or 0x000000FF, r.ImGui_ColorEditFlags_NoInputs())
     if r.ImGui_IsItemHovered(ctx) then
      r.ImGui_SetTooltip(ctx, "Tick color when meter is at or above this level")
     end
     r.ImGui_EndTable(ctx)
    end
   end
   
  end
  
  if mixer_state.settings_top_tab == 3 then
   mixer_state.settings_tab = 2
   r.ImGui_Spacing(ctx)
   
   r.ImGui_Text(ctx, "Track Color Options:")
   rv, settings.simple_mixer_use_track_color = r.ImGui_Checkbox(ctx, "Color Slider", settings.simple_mixer_use_track_color ~= false)
   r.ImGui_SameLine(ctx)
   rv, settings.simple_mixer_track_name_use_color = r.ImGui_Checkbox(ctx, "Color Name", settings.simple_mixer_track_name_use_color or false)
   r.ImGui_SameLine(ctx)
   rv, settings.simple_mixer_track_name_bg_use_color = r.ImGui_Checkbox(ctx, "Color Name BG", settings.simple_mixer_track_name_bg_use_color or false)
   r.ImGui_SameLine(ctx)
   rv, settings.simple_mixer_track_name_centered = r.ImGui_Checkbox(ctx, "Center Name", settings.simple_mixer_track_name_centered or false)

   r.ImGui_Spacing(ctx)
   r.ImGui_Text(ctx, "Selection Color (when no track color):")
   rv, settings.simple_mixer_selection_color = r.ImGui_ColorEdit4(ctx, "##sel_color", settings.simple_mixer_selection_color or 0x4A90D9FF, r.ImGui_ColorEditFlags_NoInputs())
   r.ImGui_SameLine(ctx)
   r.ImGui_SetNextItemWidth(ctx, 180)
   rv, settings.simple_mixer_selection_intensity = r.ImGui_SliderDouble(ctx, "Intensity##sel_int", settings.simple_mixer_selection_intensity or 0.67, 0.1, 1.0, "%.2f")
   
   r.ImGui_Separator(ctx)
   r.ImGui_Spacing(ctx)
   r.ImGui_Text(ctx, "Fader Style:")
   local fader_styles = {"Normal", "Classic", "Vintage", "LED", "Glass", "VU Needle", "Cyberpunk"}
   local current_style = settings.simple_mixer_fader_style or 0
   r.ImGui_PushItemWidth(ctx, 120)
   if r.ImGui_BeginCombo(ctx, "##fader_style", fader_styles[current_style + 1] or "Normal") then
    for i, style_name in ipairs(fader_styles) do
     local is_selected = (current_style == i - 1)
     if r.ImGui_Selectable(ctx, style_name, is_selected) then
      settings.simple_mixer_fader_style = i - 1
      need_save = true
     end
    end
    r.ImGui_EndCombo(ctx)
   end
   r.ImGui_PopItemWidth(ctx)
   if r.ImGui_IsItemHovered(ctx) then
    r.ImGui_SetTooltip(ctx, "Normal: standaard brede fader\nClassic: dunne lijn met knop en groeven\nVintage: 3D look met schaduw\nLED: met gekleurde indicator\nGlass: transparante glazen look\nVU Needle: miniatuur VU meter\nCyberpunk: neon glow effect")
   end
   
   if (settings.simple_mixer_fader_style or 0) == 6 then
    r.ImGui_SameLine(ctx)
    local cyber_col = settings.simple_mixer_fader_cyberpunk_color or 0x00FFFFFF
    local col_flags = r.ImGui_ColorEditFlags_NoInputs()
    local rv_col, new_col = r.ImGui_ColorEdit4(ctx, "##CyberpunkCol", cyber_col, col_flags)
    if rv_col then
     settings.simple_mixer_fader_cyberpunk_color = new_col
    end
    if r.ImGui_IsItemHovered(ctx) then
     r.ImGui_SetTooltip(ctx, "Cyberpunk neon color")
    end
   end
   
   r.ImGui_Separator(ctx)
   r.ImGui_Spacing(ctx)
   r.ImGui_Text(ctx, "Channel Controls:")
   
   if r.ImGui_BeginTable(ctx, "ChannelControlsTable", 2, r.ImGui_TableFlags_None()) then
    r.ImGui_TableNextRow(ctx)
    r.ImGui_TableNextColumn(ctx)
    rv, settings.simple_mixer_show_rms = r.ImGui_Checkbox(ctx, "R/M/S Buttons", settings.simple_mixer_show_rms ~= false)
    if settings.simple_mixer_show_rms then
     r.ImGui_SameLine(ctx)
     local rms_pos = settings.simple_mixer_rms_position or "top"
     local rms_pos_idx = rms_pos == "bottom" and 1 or 0
     r.ImGui_SetNextItemWidth(ctx, 70)
     local rv_pos, new_idx = r.ImGui_Combo(ctx, "##RMSPos", rms_pos_idx, "Top\0Bottom\0")
     if rv_pos then
      settings.simple_mixer_rms_position = new_idx == 0 and "top" or "bottom"
     end
    end
    r.ImGui_TableNextColumn(ctx)
    rv, settings.simple_mixer_show_track_buttons = r.ImGui_Checkbox(ctx, "Track Buttons", settings.simple_mixer_show_track_buttons ~= false)
    
    r.ImGui_TableNextRow(ctx)
    r.ImGui_TableNextColumn(ctx)
    rv, settings.simple_mixer_show_pan = r.ImGui_Checkbox(ctx, "Pan Slider", settings.simple_mixer_show_pan ~= false)
    r.ImGui_TableNextColumn(ctx)
    rv, settings.simple_mixer_show_width = r.ImGui_Checkbox(ctx, "Width Slider", settings.simple_mixer_show_width or false)
    
    r.ImGui_EndTable(ctx)
   end
   
   r.ImGui_Separator(ctx)
   r.ImGui_Spacing(ctx)
   r.ImGui_Text(ctx, "Button Rounding:")
   r.ImGui_SetNextItemWidth(ctx, -1)
   rv, settings.simple_mixer_channel_rounding = r.ImGui_SliderDouble(ctx, "##ChRnd", settings.simple_mixer_channel_rounding or 0, 0, 10, "%.0f px")
   if rv then MarkTransportPresetChanged() end
   
   r.ImGui_Separator(ctx)
   r.ImGui_Spacing(ctx)
   r.ImGui_Text(ctx, "Fader Background:")
   local fader_bg_styles = {"Solid", "Gradient V", "Gradient H", "Gradient Center", "VU Zones", "LED Segments", "Brushed Metal", "Carbon Fiber", "Noise/Grain", "Grid/Mesh", "dB Scale"}
   local current_fader_bg_style = settings.simple_mixer_fader_bg_style or 0
   r.ImGui_SetNextItemWidth(ctx, 120)
   if r.ImGui_BeginCombo(ctx, "##FaderBGStyle", fader_bg_styles[current_fader_bg_style + 1] or "Solid") then
    for i, style_name in ipairs(fader_bg_styles) do
     if r.ImGui_Selectable(ctx, style_name, current_fader_bg_style == i - 1) then
      settings.simple_mixer_fader_bg_style = i - 1
      SaveMixerSettings()
     end
    end
    r.ImGui_EndCombo(ctx)
   end
   
   if current_fader_bg_style == 0 then
    r.ImGui_SameLine(ctx)
    rv, settings.simple_mixer_fader_bg_color = r.ImGui_ColorEdit4(ctx, "##FdrBGSolid", settings.simple_mixer_fader_bg_color or 0x404040FF, r.ImGui_ColorEditFlags_NoInputs())
    if rv then SaveMixerSettings() end
   elseif current_fader_bg_style >= 1 and current_fader_bg_style <= 3 then
    rv, settings.simple_mixer_fader_bg_gradient_top = r.ImGui_ColorEdit4(ctx, "Top##GradTop", settings.simple_mixer_fader_bg_gradient_top or 0x606060FF, r.ImGui_ColorEditFlags_NoInputs())
    if rv then SaveMixerSettings() end
    r.ImGui_SameLine(ctx)
    rv, settings.simple_mixer_fader_bg_gradient_bottom = r.ImGui_ColorEdit4(ctx, "Bottom##GradBot", settings.simple_mixer_fader_bg_gradient_bottom or 0x202020FF, r.ImGui_ColorEditFlags_NoInputs())
    if rv then SaveMixerSettings() end
    if current_fader_bg_style == 1 or current_fader_bg_style == 2 then
     rv, settings.simple_mixer_fader_bg_use_three_color = r.ImGui_Checkbox(ctx, "3-Color##3Col", settings.simple_mixer_fader_bg_use_three_color or false)
     if rv then SaveMixerSettings() end
     if settings.simple_mixer_fader_bg_use_three_color then
      r.ImGui_SameLine(ctx)
      rv, settings.simple_mixer_fader_bg_gradient_middle = r.ImGui_ColorEdit4(ctx, "Mid##GradMid", settings.simple_mixer_fader_bg_gradient_middle or 0x404040FF, r.ImGui_ColorEditFlags_NoInputs())
      if rv then SaveMixerSettings() end
     end
    end
   elseif current_fader_bg_style == 4 then
    r.ImGui_TextDisabled(ctx, "Green/Yellow/Red zones based on dB")
   elseif current_fader_bg_style == 5 then
    r.ImGui_TextDisabled(ctx, "LED-style segments")
   elseif current_fader_bg_style == 6 then
    r.ImGui_TextDisabled(ctx, "Brushed metal with horizontal lines")
   elseif current_fader_bg_style == 7 then
    r.ImGui_TextDisabled(ctx, "Carbon fiber weave pattern")
   elseif current_fader_bg_style == 8 then
    r.ImGui_TextDisabled(ctx, "Analog noise/grain texture")
   elseif current_fader_bg_style == 9 then
    r.ImGui_TextDisabled(ctx, "Vintage mixer grid pattern")
   elseif current_fader_bg_style == 10 then
    r.ImGui_TextDisabled(ctx, "Hardware mixer dB scale")
   end
   
   rv, settings.simple_mixer_fader_bg_inset = r.ImGui_Checkbox(ctx, "Inset Shadow##Inset", settings.simple_mixer_fader_bg_inset or false)
   if rv then SaveMixerSettings() end
   r.ImGui_SameLine(ctx)
   rv, settings.simple_mixer_fader_bg_glow = r.ImGui_Checkbox(ctx, "Edge Glow##Glow", settings.simple_mixer_fader_bg_glow or false)
   if rv then SaveMixerSettings() end
   if settings.simple_mixer_fader_bg_glow then
    r.ImGui_SameLine(ctx)
    rv, settings.simple_mixer_fader_bg_glow_color = r.ImGui_ColorEdit4(ctx, "##GlowCol", settings.simple_mixer_fader_bg_glow_color or 0x00FFFF40, r.ImGui_ColorEditFlags_NoInputs())
    if rv then SaveMixerSettings() end
   end
   
   r.ImGui_Separator(ctx)
   r.ImGui_Spacing(ctx)
   r.ImGui_Text(ctx, "Colors:")
   if r.ImGui_BeginTable(ctx, "ChannelColorsTable", 2, r.ImGui_TableFlags_None()) then
    r.ImGui_TableNextRow(ctx)
    r.ImGui_TableNextColumn(ctx)
    rv, settings.simple_mixer_control_bg_color = r.ImGui_ColorEdit4(ctx, "Controls##CtrlBG", settings.simple_mixer_control_bg_color or 0x333333FF, r.ImGui_ColorEditFlags_NoInputs())
    r.ImGui_TableNextColumn(ctx)
    rv, settings.simple_mixer_slider_handle_color = r.ImGui_ColorEdit4(ctx, "Handle##SldrH", settings.simple_mixer_slider_handle_color or 0x888888FF, r.ImGui_ColorEditFlags_NoInputs())
    
    r.ImGui_TableNextRow(ctx)
    r.ImGui_TableNextColumn(ctx)
    rv, settings.simple_mixer_icon_color = r.ImGui_ColorEdit4(ctx, "Icons##IcnClr", settings.simple_mixer_icon_color or 0xAAAAAAFF, r.ImGui_ColorEditFlags_NoInputs())
    r.ImGui_TableNextColumn(ctx)
    
    r.ImGui_TableNextRow(ctx)
    r.ImGui_TableNextColumn(ctx)
    rv, settings.simple_mixer_rms_button_off_color = r.ImGui_ColorEdit4(ctx, "RMS Off##RMSOff", settings.simple_mixer_rms_button_off_color or 0x404040FF, r.ImGui_ColorEditFlags_NoInputs())
    r.ImGui_TableNextColumn(ctx)
    rv, settings.simple_mixer_rms_text_color = r.ImGui_ColorEdit4(ctx, "RMS Text##RMSTxt", settings.simple_mixer_rms_text_color or 0xFFFFFFFF, r.ImGui_ColorEditFlags_NoInputs())
    
    r.ImGui_TableNextRow(ctx)
    r.ImGui_TableNextColumn(ctx)
    rv, settings.simple_mixer_master_fader_color = r.ImGui_ColorEdit4(ctx, "Master##MstrClr", settings.simple_mixer_master_fader_color or 0x4A90D9FF, r.ImGui_ColorEditFlags_NoInputs())
    r.ImGui_TableNextColumn(ctx)
    
    r.ImGui_EndTable(ctx)
   end
   
  end
  
  if mixer_state.settings_top_tab == 4 then
   mixer_state.settings_tab = 4
   r.ImGui_Spacing(ctx)
   
   r.ImGui_Text(ctx, "Channel Strip Processing Order:")
   r.ImGui_Separator(ctx)
   
   local routing_options = {"EQ > Comp > Lim", "Comp > EQ > Lim", "EQ > Lim > Comp", "Comp > Lim > EQ", "Lim > EQ > Comp", "Lim > Comp > EQ"}
   local current_routing = settings.simple_mixer_strip_routing_order or 0
   r.ImGui_SetNextItemWidth(ctx, 150)
   if r.ImGui_BeginCombo(ctx, "##StripRoutingOrder", routing_options[current_routing + 1] or "EQ > Comp > Lim") then
    for i, option in ipairs(routing_options) do
     local is_selected = (current_routing == i - 1)
     if r.ImGui_Selectable(ctx, option, is_selected) then
      settings.simple_mixer_strip_routing_order = i - 1
      MarkTransportPresetChanged()
      UpdateAllStripsRoutingOrder()
     end
     if is_selected then
      r.ImGui_SetItemDefaultFocus(ctx)
     end
    end
    r.ImGui_EndCombo(ctx)
   end
   if r.ImGui_IsItemHovered(ctx) then
    r.ImGui_SetTooltip(ctx, "Sets the signal processing order for EQ, Compressor and Limiter.\\nApplies to all tracks with TK Channel Strip.")
   end
   
   r.ImGui_Spacing(ctx)
   
   r.ImGui_Text(ctx, "Knob Style:")
   local knob_styles = {"Classic", "Modern", "Vintage", "LED", "Minimal", "Image"}
   local current_style = settings.simple_mixer_knob_style or 0
   r.ImGui_SetNextItemWidth(ctx, 150)
   if r.ImGui_BeginCombo(ctx, "##KnobStyle", knob_styles[current_style + 1] or "Classic") then
    for i, style_name in ipairs(knob_styles) do
     local is_selected = (current_style == i - 1)
     if r.ImGui_Selectable(ctx, style_name, is_selected) then
      settings.simple_mixer_knob_style = i - 1
      MarkTransportPresetChanged()
      if SaveMixerSettings then SaveMixerSettings() end
     end
     if is_selected then
      r.ImGui_SetItemDefaultFocus(ctx)
     end
    end
    r.ImGui_EndCombo(ctx)
   end
   if r.ImGui_IsItemHovered(ctx) then
    r.ImGui_SetTooltip(ctx, "Visual style for all knobs in the mixer modules.")
   end
   
   r.ImGui_Spacing(ctx)
   r.ImGui_Spacing(ctx)
   
   r.ImGui_Text(ctx, "FX Cleanup:")
   r.ImGui_Separator(ctx)
   rv, settings.simple_mixer_auto_remove_unused_fx = r.ImGui_Checkbox(ctx, "Auto-remove unused FX", settings.simple_mixer_auto_remove_unused_fx or false)
   if r.ImGui_IsItemHovered(ctx) then
    r.ImGui_SetTooltip(ctx, "When EQ + Compressor + Limiter are all hidden, automatically remove TK_ChannelStrip from all tracks.\nSame for TK_Trim when Trim is hidden.")
   end
   if rv then MarkTransportPresetChanged() end
   r.ImGui_SameLine(ctx)
   if r.ImGui_Button(ctx, "Clean up now", 110, 20) then
    CleanupUnusedChannelFX()
   end
   if r.ImGui_IsItemHovered(ctx) then
    r.ImGui_SetTooltip(ctx, "Remove TK_ChannelStrip and TK_Trim from all tracks where the corresponding modules are currently hidden.")
   end
   
   r.ImGui_Spacing(ctx)
   r.ImGui_Spacing(ctx)
   
   r.ImGui_Text(ctx, "VU Meter (Analog Style):")
   r.ImGui_Separator(ctx)
   
   rv, settings.simple_mixer_show_vu_meter = r.ImGui_Checkbox(ctx, "Show VU Meter", settings.simple_mixer_show_vu_meter or false)
   if r.ImGui_IsItemHovered(ctx) then
    r.ImGui_SetTooltip(ctx, "Shows an analog-style VU meter below the track number.")
   end
   if rv then MarkTransportPresetChanged() end
   
   if settings.simple_mixer_show_vu_meter then
    r.ImGui_Indent(ctx, 10)
    
    r.ImGui_Text(ctx, "Style:")
    r.ImGui_SameLine(ctx)
    local vu_styles = {"Analog", "Analog Light", "LED Bars", "Digital"}
    local current_vu_style = settings.simple_mixer_vu_style or 0
    r.ImGui_SetNextItemWidth(ctx, 110)
    if r.ImGui_BeginCombo(ctx, "##VUStyle", vu_styles[current_vu_style + 1] or "Analog") then
     for i, style_name in ipairs(vu_styles) do
      local is_selected = (current_vu_style == i - 1)
      if r.ImGui_Selectable(ctx, style_name, is_selected) then
       settings.simple_mixer_vu_style = i - 1
       MarkTransportPresetChanged()
       if SaveMixerSettings then SaveMixerSettings() end
      end
      if is_selected then
       r.ImGui_SetItemDefaultFocus(ctx)
      end
     end
     r.ImGui_EndCombo(ctx)
    end
    if r.ImGui_IsItemHovered(ctx) then
     r.ImGui_SetTooltip(ctx, "Visual style for VU meters.\nAnalog: Classic needle meter\nLED Bars: Retro LED segment display\nDigital: Modern gradient bars")
    end
    
    r.ImGui_Spacing(ctx)
    
    local old_pre_fader = settings.simple_mixer_vu_pre_fader
    rv, settings.simple_mixer_vu_pre_fader = r.ImGui_Checkbox(ctx, "Pre-Fader (Gain Staging)", settings.simple_mixer_vu_pre_fader or false)
    if r.ImGui_IsItemHovered(ctx) then
     r.ImGui_SetTooltip(ctx, "Pre-Fader: Shows input level before volume fader - good for gain staging.\\nPost-Fader: Shows output level after volume fader - good for mixing.")
    end
    if rv and old_pre_fader ~= settings.simple_mixer_vu_pre_fader then
     ResetVUData()
    end
    
    if settings.simple_mixer_vu_pre_fader then
     r.ImGui_SameLine(ctx, 0, 20)
     if r.ImGui_Button(ctx, "Remove JSFX from tracks") then
      CleanupVUJSFX()
     end
     if r.ImGui_IsItemHovered(ctx) then
      r.ImGui_SetTooltip(ctx, "Removes the TK_VU_Meter JSFX from all tracks.\\nUseful when switching to Post-Fader mode.")
     end
    end
    
    r.ImGui_Unindent(ctx, 10)
   end
   
   r.ImGui_Spacing(ctx)
   r.ImGui_Text(ctx, "Compressor (SSL Style):")
   r.ImGui_Separator(ctx)
   
   rv, settings.simple_mixer_show_compressor = r.ImGui_Checkbox(ctx, "Show Compressor", settings.simple_mixer_show_compressor or false)
   if r.ImGui_IsItemHovered(ctx) then
    r.ImGui_SetTooltip(ctx, "Shows an SSL-style compressor module on each channel strip.\nUses JS: TK 1175 Compressor plugin.")
   end
   if rv then
    MarkTransportPresetChanged()
    if settings.simple_mixer_auto_remove_unused_fx then CleanupUnusedChannelFX() end
   end
   
   if settings.simple_mixer_show_compressor then
    r.ImGui_Indent(ctx, 10)
    
    rv, settings.simple_mixer_comp_auto_insert = r.ImGui_Checkbox(ctx, "Auto-insert", settings.simple_mixer_comp_auto_insert ~= false)
    if r.ImGui_IsItemHovered(ctx) then
     r.ImGui_SetTooltip(ctx, "Automatically add JS: 1175 Compressor to tracks when clicking 'Add'.")
    end
    if rv then MarkTransportPresetChanged() end
    
    r.ImGui_SameLine(ctx)
    rv, settings.simple_mixer_comp_show_gr_meter = r.ImGui_Checkbox(ctx, "GR Meter", settings.simple_mixer_comp_show_gr_meter ~= false)
    if rv then MarkTransportPresetChanged() end
    
    r.ImGui_SameLine(ctx)
    rv, settings.simple_mixer_comp_show_labels = r.ImGui_Checkbox(ctx, "Labels", settings.simple_mixer_comp_show_labels ~= false)
    if rv then MarkTransportPresetChanged() end
    
    r.ImGui_Spacing(ctx)
    r.ImGui_Text(ctx, "Colors:")
    if r.ImGui_BeginTable(ctx, "CompColorsTable", 2, r.ImGui_TableFlags_None()) then
     r.ImGui_TableNextRow(ctx)
     r.ImGui_TableNextColumn(ctx)
     rv, settings.simple_mixer_comp_bg_color = r.ImGui_ColorEdit4(ctx, "Background##CompBG", settings.simple_mixer_comp_bg_color or 0x1A1A2AFF, r.ImGui_ColorEditFlags_NoInputs())
     if rv then MarkTransportPresetChanged() end
     r.ImGui_TableNextColumn(ctx)
     rv, settings.simple_mixer_comp_header_color = r.ImGui_ColorEdit4(ctx, "Header##CompHdr", settings.simple_mixer_comp_header_color or 0x3A3A5AFF, r.ImGui_ColorEditFlags_NoInputs())
     if rv then MarkTransportPresetChanged() end
     
     r.ImGui_TableNextRow(ctx)
     r.ImGui_TableNextColumn(ctx)
     rv, settings.simple_mixer_comp_knob_color = r.ImGui_ColorEdit4(ctx, "Indicator##CompKnob", settings.simple_mixer_comp_knob_color or 0xCCCCCCFF, r.ImGui_ColorEditFlags_NoInputs())
     if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Kleur van de waarde-indicator (niet bij Vintage)") end
     if rv then MarkTransportPresetChanged() end
     r.ImGui_TableNextColumn(ctx)
     rv, settings.simple_mixer_comp_knob_track_color = r.ImGui_ColorEdit4(ctx, "Track##CompKnobTrk", settings.simple_mixer_comp_knob_track_color or 0x555555FF, r.ImGui_ColorEditFlags_NoInputs())
     if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Achtergrondkleur van de knob (alleen Classic/Minimal)") end
     if rv then MarkTransportPresetChanged() end
     
     r.ImGui_TableNextRow(ctx)
     r.ImGui_TableNextColumn(ctx)
     rv, settings.simple_mixer_comp_gr_color = r.ImGui_ColorEdit4(ctx, "GR Meter##CompGR", settings.simple_mixer_comp_gr_color or 0xFF6644FF, r.ImGui_ColorEditFlags_NoInputs())
     if rv then MarkTransportPresetChanged() end
     r.ImGui_TableNextColumn(ctx)
     rv, settings.simple_mixer_comp_text_color = r.ImGui_ColorEdit4(ctx, "Text##CompTxt", settings.simple_mixer_comp_text_color or 0xAAAAAAFF, r.ImGui_ColorEditFlags_NoInputs())
     if rv then MarkTransportPresetChanged() end
     
     r.ImGui_TableNextRow(ctx)
     r.ImGui_TableNextColumn(ctx)
     rv, settings.simple_mixer_comp_active_color = r.ImGui_ColorEdit4(ctx, "Active##CompAct", settings.simple_mixer_comp_active_color or 0x00AA44FF, r.ImGui_ColorEditFlags_NoInputs())
     if rv then MarkTransportPresetChanged() end
     r.ImGui_TableNextColumn(ctx)
     rv, settings.simple_mixer_comp_bypass_color = r.ImGui_ColorEdit4(ctx, "Bypass##CompByp", settings.simple_mixer_comp_bypass_color or 0x666600FF, r.ImGui_ColorEditFlags_NoInputs())
     if rv then MarkTransportPresetChanged() end
     
     r.ImGui_EndTable(ctx)
    end
    
    r.ImGui_Unindent(ctx, 10)
   end
   
   r.ImGui_Spacing(ctx)
   r.ImGui_Text(ctx, "Limiter:")
   r.ImGui_Separator(ctx)
   
   rv, settings.simple_mixer_show_limiter = r.ImGui_Checkbox(ctx, "Show Limiter", settings.simple_mixer_show_limiter or false)
   if r.ImGui_IsItemHovered(ctx) then
    r.ImGui_SetTooltip(ctx, "Shows a limiter module on each channel strip.\nUses JS: TK Limiter plugin.")
   end
   if rv then
    MarkTransportPresetChanged()
    if settings.simple_mixer_auto_remove_unused_fx then CleanupUnusedChannelFX() end
   end
   
   if settings.simple_mixer_show_limiter then
    r.ImGui_Indent(ctx, 10)
    
    rv, settings.simple_mixer_lim_auto_insert = r.ImGui_Checkbox(ctx, "Auto-insert##Lim", settings.simple_mixer_lim_auto_insert ~= false)
    if r.ImGui_IsItemHovered(ctx) then
     r.ImGui_SetTooltip(ctx, "Automatically add JS: TK Limiter to tracks when clicking 'Add'.")
    end
    if rv then MarkTransportPresetChanged() end
    
    r.ImGui_SameLine(ctx)
    rv, settings.simple_mixer_lim_show_gr_meter = r.ImGui_Checkbox(ctx, "GR Meter##Lim", settings.simple_mixer_lim_show_gr_meter ~= false)
    if rv then MarkTransportPresetChanged() end
    
    r.ImGui_SameLine(ctx)
    rv, settings.simple_mixer_lim_show_labels = r.ImGui_Checkbox(ctx, "Labels##Lim", settings.simple_mixer_lim_show_labels ~= false)
    if rv then MarkTransportPresetChanged() end
    
    r.ImGui_Spacing(ctx)
    r.ImGui_Text(ctx, "Colors:")
    if r.ImGui_BeginTable(ctx, "LimColorsTable", 2, r.ImGui_TableFlags_None()) then
     r.ImGui_TableNextRow(ctx)
     r.ImGui_TableNextColumn(ctx)
     rv, settings.simple_mixer_lim_bg_color = r.ImGui_ColorEdit4(ctx, "Background##LimBG", settings.simple_mixer_lim_bg_color or 0x2A1A2AFF, r.ImGui_ColorEditFlags_NoInputs())
     if rv then MarkTransportPresetChanged() end
     r.ImGui_TableNextColumn(ctx)
     rv, settings.simple_mixer_lim_header_color = r.ImGui_ColorEdit4(ctx, "Header##LimHdr", settings.simple_mixer_lim_header_color or 0x5A3A5AFF, r.ImGui_ColorEditFlags_NoInputs())
     if rv then MarkTransportPresetChanged() end
     
     r.ImGui_TableNextRow(ctx)
     r.ImGui_TableNextColumn(ctx)
     rv, settings.simple_mixer_lim_knob_color = r.ImGui_ColorEdit4(ctx, "Indicator##LimKnob", settings.simple_mixer_lim_knob_color or 0xCCCCCCFF, r.ImGui_ColorEditFlags_NoInputs())
     if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Kleur van de waarde-indicator (niet bij Vintage)") end
     if rv then MarkTransportPresetChanged() end
     r.ImGui_TableNextColumn(ctx)
     rv, settings.simple_mixer_lim_knob_track_color = r.ImGui_ColorEdit4(ctx, "Track##LimKnobTrk", settings.simple_mixer_lim_knob_track_color or 0x555555FF, r.ImGui_ColorEditFlags_NoInputs())
     if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Achtergrondkleur van de knob (alleen Classic/Minimal)") end
     if rv then MarkTransportPresetChanged() end
     
     r.ImGui_TableNextRow(ctx)
     r.ImGui_TableNextColumn(ctx)
     rv, settings.simple_mixer_lim_gr_color = r.ImGui_ColorEdit4(ctx, "GR Meter##LimGR", settings.simple_mixer_lim_gr_color or 0xFF4466FF, r.ImGui_ColorEditFlags_NoInputs())
     if rv then MarkTransportPresetChanged() end
     r.ImGui_TableNextColumn(ctx)
     rv, settings.simple_mixer_lim_text_color = r.ImGui_ColorEdit4(ctx, "Text##LimTxt", settings.simple_mixer_lim_text_color or 0xAAAAAAFF, r.ImGui_ColorEditFlags_NoInputs())
     if rv then MarkTransportPresetChanged() end
     
     r.ImGui_TableNextRow(ctx)
     r.ImGui_TableNextColumn(ctx)
     rv, settings.simple_mixer_lim_active_color = r.ImGui_ColorEdit4(ctx, "Active##LimAct", settings.simple_mixer_lim_active_color or 0x00AA44FF, r.ImGui_ColorEditFlags_NoInputs())
     if rv then MarkTransportPresetChanged() end
     r.ImGui_TableNextColumn(ctx)
     rv, settings.simple_mixer_lim_bypass_color = r.ImGui_ColorEdit4(ctx, "Bypass##LimByp", settings.simple_mixer_lim_bypass_color or 0x666600FF, r.ImGui_ColorEditFlags_NoInputs())
     if rv then MarkTransportPresetChanged() end
     
     r.ImGui_EndTable(ctx)
    end
    
    r.ImGui_Unindent(ctx, 10)
   end
   
   r.ImGui_Spacing(ctx)
   r.ImGui_Text(ctx, "Trim:")
   r.ImGui_Separator(ctx)
   
   rv, settings.simple_mixer_show_trim = r.ImGui_Checkbox(ctx, "Show Trim", settings.simple_mixer_show_trim or false)
   if r.ImGui_IsItemHovered(ctx) then
    r.ImGui_SetTooltip(ctx, "Shows a Trim/Gain staging module on each channel strip.\nUses JS: TK Trim plugin.")
   end
   if rv then
    MarkTransportPresetChanged()
    if settings.simple_mixer_auto_remove_unused_fx then CleanupUnusedChannelFX() end
   end
   
   if settings.simple_mixer_show_trim then
    r.ImGui_Indent(ctx, 10)
    
    rv, settings.simple_mixer_trim_auto_insert = r.ImGui_Checkbox(ctx, "Auto-insert##Trim", settings.simple_mixer_trim_auto_insert ~= false)
    if r.ImGui_IsItemHovered(ctx) then
     r.ImGui_SetTooltip(ctx, "Automatically add JS: TK Trim to tracks when clicking 'Add'.")
    end
    if rv then MarkTransportPresetChanged() end
    
    r.ImGui_Spacing(ctx)
    r.ImGui_Text(ctx, "Colors:")
    if r.ImGui_BeginTable(ctx, "TrimColorsTable", 2, r.ImGui_TableFlags_None()) then
     r.ImGui_TableNextRow(ctx)
     r.ImGui_TableNextColumn(ctx)
     rv, settings.simple_mixer_trim_bg_color = r.ImGui_ColorEdit4(ctx, "Background##TrimBG", settings.simple_mixer_trim_bg_color or 0x2A2A1AFF, r.ImGui_ColorEditFlags_NoInputs())
     if rv then MarkTransportPresetChanged() end
     r.ImGui_TableNextColumn(ctx)
     rv, settings.simple_mixer_trim_header_color = r.ImGui_ColorEdit4(ctx, "Header##TrimHdr", settings.simple_mixer_trim_header_color or 0x5A5A3AFF, r.ImGui_ColorEditFlags_NoInputs())
     if rv then MarkTransportPresetChanged() end
     
     r.ImGui_TableNextRow(ctx)
     r.ImGui_TableNextColumn(ctx)
     rv, settings.simple_mixer_trim_knob_color = r.ImGui_ColorEdit4(ctx, "Indicator##TrimKnob", settings.simple_mixer_trim_knob_color or 0xCCCCCCFF, r.ImGui_ColorEditFlags_NoInputs())
     if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Kleur van de waarde-indicator (niet bij Vintage)") end
     if rv then MarkTransportPresetChanged() end
     r.ImGui_TableNextColumn(ctx)
     rv, settings.simple_mixer_trim_knob_track_color = r.ImGui_ColorEdit4(ctx, "Track##TrimKnobTrk", settings.simple_mixer_trim_knob_track_color or 0x555555FF, r.ImGui_ColorEditFlags_NoInputs())
     if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Achtergrondkleur van de knob (alleen Classic/Minimal)") end
     if rv then MarkTransportPresetChanged() end
     
     r.ImGui_TableNextRow(ctx)
     r.ImGui_TableNextColumn(ctx)
     rv, settings.simple_mixer_trim_text_color = r.ImGui_ColorEdit4(ctx, "Text##TrimTxt", settings.simple_mixer_trim_text_color or 0xAAAAAAFF, r.ImGui_ColorEditFlags_NoInputs())
     if rv then MarkTransportPresetChanged() end
     
     r.ImGui_EndTable(ctx)
    end
    
    r.ImGui_Unindent(ctx, 10)
   end
   
   r.ImGui_Spacing(ctx)
   r.ImGui_Text(ctx, "EQ:")
   r.ImGui_Separator(ctx)
   
   rv, settings.simple_mixer_show_eq = r.ImGui_Checkbox(ctx, "Show EQ", settings.simple_mixer_show_eq or false)
   if r.ImGui_IsItemHovered(ctx) then
    r.ImGui_SetTooltip(ctx, "Shows an EQ module on each channel strip.\nUses ReaEQ plugin.")
   end
   if rv then
    MarkTransportPresetChanged()
    if settings.simple_mixer_auto_remove_unused_fx then CleanupUnusedChannelFX() end
   end
   
   if settings.simple_mixer_show_eq then
    r.ImGui_Indent(ctx, 10)
    
    rv, settings.simple_mixer_eq_show_labels = r.ImGui_Checkbox(ctx, "Labels##EQ", settings.simple_mixer_eq_show_labels ~= false)
    if rv then MarkTransportPresetChanged() end
    
    r.ImGui_Spacing(ctx)
    r.ImGui_Text(ctx, "Band Background Colors:")
    if r.ImGui_BeginTable(ctx, "EQBandColorsTable", 2, r.ImGui_TableFlags_None()) then
     r.ImGui_TableNextRow(ctx)
     r.ImGui_TableNextColumn(ctx)
     rv, settings.simple_mixer_eq_lf_bg = r.ImGui_ColorEdit4(ctx, "LF##EQLF", settings.simple_mixer_eq_lf_bg or 0xFF666618, r.ImGui_ColorEditFlags_NoInputs() | r.ImGui_ColorEditFlags_AlphaBar())
     if rv then MarkTransportPresetChanged() end
     r.ImGui_TableNextColumn(ctx)
     rv, settings.simple_mixer_eq_lmf_bg = r.ImGui_ColorEdit4(ctx, "LMF##EQLMF", settings.simple_mixer_eq_lmf_bg or 0xFFAA4418, r.ImGui_ColorEditFlags_NoInputs() | r.ImGui_ColorEditFlags_AlphaBar())
     if rv then MarkTransportPresetChanged() end
     
     r.ImGui_TableNextRow(ctx)
     r.ImGui_TableNextColumn(ctx)
     rv, settings.simple_mixer_eq_hmf_bg = r.ImGui_ColorEdit4(ctx, "HMF##EQHMF", settings.simple_mixer_eq_hmf_bg or 0x66FF6618, r.ImGui_ColorEditFlags_NoInputs() | r.ImGui_ColorEditFlags_AlphaBar())
     if rv then MarkTransportPresetChanged() end
     r.ImGui_TableNextColumn(ctx)
     rv, settings.simple_mixer_eq_hf_bg = r.ImGui_ColorEdit4(ctx, "HF##EQHF", settings.simple_mixer_eq_hf_bg or 0x6666FF18, r.ImGui_ColorEditFlags_NoInputs() | r.ImGui_ColorEditFlags_AlphaBar())
     if rv then MarkTransportPresetChanged() end
     
     r.ImGui_EndTable(ctx)
    end
    
    r.ImGui_Spacing(ctx)
    r.ImGui_Text(ctx, "Module Colors:")
    if r.ImGui_BeginTable(ctx, "EQColorsTable", 2, r.ImGui_TableFlags_None()) then
     r.ImGui_TableNextRow(ctx)
     r.ImGui_TableNextColumn(ctx)
     rv, settings.simple_mixer_eq_bg_color = r.ImGui_ColorEdit4(ctx, "Background##EQBG", settings.simple_mixer_eq_bg_color or 0x1A2A2AFF, r.ImGui_ColorEditFlags_NoInputs())
     if rv then MarkTransportPresetChanged() end
     r.ImGui_TableNextColumn(ctx)
     rv, settings.simple_mixer_eq_header_color = r.ImGui_ColorEdit4(ctx, "Header##EQHdr", settings.simple_mixer_eq_header_color or 0x3A5A5AFF, r.ImGui_ColorEditFlags_NoInputs())
     if rv then MarkTransportPresetChanged() end
     
     r.ImGui_TableNextRow(ctx)
     r.ImGui_TableNextColumn(ctx)
     rv, settings.simple_mixer_eq_knob_color = r.ImGui_ColorEdit4(ctx, "Indicator##EQKnob", settings.simple_mixer_eq_knob_color or 0xCCCCCCFF, r.ImGui_ColorEditFlags_NoInputs())
     if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Kleur van de waarde-indicator (niet bij Vintage)") end
     if rv then MarkTransportPresetChanged() end
     r.ImGui_TableNextColumn(ctx)
     rv, settings.simple_mixer_eq_knob_track_color = r.ImGui_ColorEdit4(ctx, "Track##EQKnobTrk", settings.simple_mixer_eq_knob_track_color or 0x555555FF, r.ImGui_ColorEditFlags_NoInputs())
     if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Achtergrondkleur van de knob (alleen Classic/Minimal)") end
     if rv then MarkTransportPresetChanged() end
     
     r.ImGui_TableNextRow(ctx)
     r.ImGui_TableNextColumn(ctx)
     rv, settings.simple_mixer_eq_text_color = r.ImGui_ColorEdit4(ctx, "Text##EQTxt", settings.simple_mixer_eq_text_color or 0xAAAAAAFF, r.ImGui_ColorEditFlags_NoInputs())
     if rv then MarkTransportPresetChanged() end
     
     r.ImGui_TableNextRow(ctx)
     r.ImGui_TableNextColumn(ctx)
     rv, settings.simple_mixer_eq_active_color = r.ImGui_ColorEdit4(ctx, "Active##EQAct", settings.simple_mixer_eq_active_color or 0x00AA88FF, r.ImGui_ColorEditFlags_NoInputs())
     if rv then MarkTransportPresetChanged() end
     r.ImGui_TableNextColumn(ctx)
     rv, settings.simple_mixer_eq_bypass_color = r.ImGui_ColorEdit4(ctx, "Bypass##EQByp", settings.simple_mixer_eq_bypass_color or 0x666600FF, r.ImGui_ColorEditFlags_NoInputs())
     if rv then MarkTransportPresetChanged() end
     
     r.ImGui_EndTable(ctx)
    end
    
    r.ImGui_Unindent(ctx, 10)
   end
   
  end
  
  if mixer_state.settings_top_tab == 5 then
   mixer_state.settings_tab = 3
   r.ImGui_Spacing(ctx)
   
   rv, settings.simple_mixer_show_fx_slots = r.ImGui_Checkbox(ctx, "Show FX Slots", settings.simple_mixer_show_fx_slots or false)
   
   if settings.simple_mixer_show_fx_slots then
    r.ImGui_Separator(ctx)
    r.ImGui_Spacing(ctx)
    
    if r.ImGui_BeginTable(ctx, "FXDimTable", 2, r.ImGui_TableFlags_None()) then
     r.ImGui_TableNextRow(ctx)
     r.ImGui_TableNextColumn(ctx)
     r.ImGui_Text(ctx, "Section Height:")
     r.ImGui_SetNextItemWidth(ctx, -1)
     rv, settings.simple_mixer_fx_section_height = r.ImGui_SliderInt(ctx, "##FXSecH", settings.simple_mixer_fx_section_height or 80, 30, 200, "%d px")
     
     r.ImGui_TableNextColumn(ctx)
     r.ImGui_Text(ctx, "Slot Height:")
     r.ImGui_SetNextItemWidth(ctx, -1)
     rv, settings.simple_mixer_fx_slot_height = r.ImGui_SliderInt(ctx, "##FXSlotH", settings.simple_mixer_fx_slot_height or 16, 12, 24, "%d px")
     
     r.ImGui_TableNextRow(ctx)
     r.ImGui_TableNextColumn(ctx)
     r.ImGui_Text(ctx, "Font Size:")
     r.ImGui_SetNextItemWidth(ctx, -1)
     rv, settings.simple_mixer_fx_font_size = r.ImGui_SliderInt(ctx, "##FXFontSize", settings.simple_mixer_fx_font_size or 12, 8, 16, "%d px")
     
     r.ImGui_TableNextColumn(ctx)
     
     r.ImGui_EndTable(ctx)
    end
    
    rv, settings.simple_mixer_fx_show_bypass_button = r.ImGui_Checkbox(ctx, "Show Bypass Button", settings.simple_mixer_fx_show_bypass_button ~= false)
    r.ImGui_SameLine(ctx)
    rv, settings.simple_mixer_fx_slot_show_offline = r.ImGui_Checkbox(ctx, "Show Offline State", settings.simple_mixer_fx_slot_show_offline ~= false)
    if r.ImGui_IsItemHovered(ctx) then
     r.ImGui_SetTooltip(ctx, "Use a separate color for offline FX in slots")
    end
    
    r.ImGui_Separator(ctx)
    r.ImGui_Spacing(ctx)
    r.ImGui_Text(ctx, "Colors:")
    
    if r.ImGui_BeginTable(ctx, "FXColorsTable", 2, r.ImGui_TableFlags_None()) then
     r.ImGui_TableNextRow(ctx)
     r.ImGui_TableNextColumn(ctx)
     rv, settings.simple_mixer_fx_slot_active_color = r.ImGui_ColorEdit4(ctx, "Active##FXActive", settings.simple_mixer_fx_slot_active_color or 0x444444FF, r.ImGui_ColorEditFlags_NoInputs())
     r.ImGui_TableNextColumn(ctx)
     rv, settings.simple_mixer_fx_slot_bypass_color = r.ImGui_ColorEdit4(ctx, "Bypassed##FXBypass", settings.simple_mixer_fx_slot_bypass_color or 0x666600FF, r.ImGui_ColorEditFlags_NoInputs())
     
     r.ImGui_TableNextRow(ctx)
     r.ImGui_TableNextColumn(ctx)
     rv, settings.simple_mixer_fx_slot_offline_color = r.ImGui_ColorEdit4(ctx, "Offline##FXOffline", settings.simple_mixer_fx_slot_offline_color or 0x553333FF, r.ImGui_ColorEditFlags_NoInputs())
     r.ImGui_TableNextColumn(ctx)
     rv, settings.simple_mixer_fx_slot_text_color = r.ImGui_ColorEdit4(ctx, "Text##FXText", settings.simple_mixer_fx_slot_text_color or 0x888888FF, r.ImGui_ColorEditFlags_NoInputs())
     
     r.ImGui_TableNextRow(ctx)
     r.ImGui_TableNextColumn(ctx)
     rv, settings.simple_mixer_fx_dropzone_color = r.ImGui_ColorEdit4(ctx, "Dropzone##FXDrop", settings.simple_mixer_fx_dropzone_color or 0x2A2A2AFF, r.ImGui_ColorEditFlags_NoInputs())
     r.ImGui_TableNextColumn(ctx)
     rv, settings.simple_mixer_fx_dropzone_border_color = r.ImGui_ColorEdit4(ctx, "Dropzone Border##FXDropBorder", settings.simple_mixer_fx_dropzone_border_color or 0x555555FF, r.ImGui_ColorEditFlags_NoInputs())
     
     r.ImGui_EndTable(ctx)
    end
   end
   
  end
  
  if mixer_state.settings_top_tab == 6 then
   mixer_state.settings_tab = 4
   r.ImGui_Spacing(ctx)
   
   r.ImGui_Text(ctx, "Spacer Style:")
   local spacer_style = settings.simple_mixer_spacer_style or "line"
   if r.ImGui_RadioButton(ctx, "Line", spacer_style == "line") then
    settings.simple_mixer_spacer_style = "line"
    MarkTransportPresetChanged()
   end
   r.ImGui_SameLine(ctx)
   if r.ImGui_RadioButton(ctx, "Divider Track", spacer_style == "track") then
    settings.simple_mixer_spacer_style = "track"
    MarkTransportPresetChanged()
   end
   
   if spacer_style == "track" then
    r.ImGui_Separator(ctx)
    r.ImGui_Spacing(ctx)
    
    if r.ImGui_BeginTable(ctx, "DividerTable", 2, r.ImGui_TableFlags_None()) then
     r.ImGui_TableNextRow(ctx)
     r.ImGui_TableNextColumn(ctx)
     r.ImGui_Text(ctx, "Width:")
     r.ImGui_SetNextItemWidth(ctx, -1)
     local divider_w = settings.simple_mixer_divider_width or 20
     rv, divider_w = r.ImGui_SliderInt(ctx, "##DivW", divider_w, 10, 60, "%d px")
     if rv then
      settings.simple_mixer_divider_width = divider_w
      MarkTransportPresetChanged()
     end
     
     r.ImGui_TableNextColumn(ctx)
     rv, settings.simple_mixer_divider_show_border = r.ImGui_Checkbox(ctx, "Show Border", settings.simple_mixer_divider_show_border ~= false)
     if rv then MarkTransportPresetChanged() end
     
     r.ImGui_TableNextRow(ctx)
     r.ImGui_TableNextColumn(ctx)
     rv, settings.simple_mixer_divider_filled = r.ImGui_Checkbox(ctx, "Filled", settings.simple_mixer_divider_filled or false)
     if rv then MarkTransportPresetChanged() end
     
     r.ImGui_EndTable(ctx)
    end
    
    r.ImGui_Separator(ctx)
    r.ImGui_Spacing(ctx)
    r.ImGui_Text(ctx, "Background/Border:")
    
    rv, settings.simple_mixer_divider_use_track_color = r.ImGui_Checkbox(ctx, "Use Track Color", settings.simple_mixer_divider_use_track_color ~= false)
    if rv then MarkTransportPresetChanged() end
    
    if not settings.simple_mixer_divider_use_track_color then
     if r.ImGui_BeginTable(ctx, "DivColorTable", 2, r.ImGui_TableFlags_None()) then
      r.ImGui_TableNextRow(ctx)
      r.ImGui_TableNextColumn(ctx)
      local bg_color = settings.simple_mixer_divider_custom_color or 0x444444FF
      rv, bg_color = r.ImGui_ColorEdit4(ctx, "Fill##DivFill", bg_color, r.ImGui_ColorEditFlags_NoInputs())
      if rv then
       settings.simple_mixer_divider_custom_color = bg_color
       MarkTransportPresetChanged()
      end
      
      r.ImGui_TableNextColumn(ctx)
      local border_color = settings.simple_mixer_divider_border_custom_color or 0x888888FF
      rv, border_color = r.ImGui_ColorEdit4(ctx, "Border##DivBorder", border_color, r.ImGui_ColorEditFlags_NoInputs())
      if rv then
       settings.simple_mixer_divider_border_custom_color = border_color
       MarkTransportPresetChanged()
      end
      
      r.ImGui_EndTable(ctx)
     end
    end
    
    r.ImGui_Separator(ctx)
    r.ImGui_Spacing(ctx)
    r.ImGui_Text(ctx, "Text:")
    
    rv, settings.simple_mixer_divider_text_use_track_color = r.ImGui_Checkbox(ctx, "Use Track Color##DivText", settings.simple_mixer_divider_text_use_track_color ~= false)
    if rv then MarkTransportPresetChanged() end
    
    if not settings.simple_mixer_divider_text_use_track_color then
     r.ImGui_SameLine(ctx)
     local text_color = settings.simple_mixer_divider_text_custom_color or 0xFFFFFFFF
     rv, text_color = r.ImGui_ColorEdit4(ctx, "##DivTextColor", text_color, r.ImGui_ColorEditFlags_NoInputs())
     if rv then
      settings.simple_mixer_divider_text_custom_color = text_color
      MarkTransportPresetChanged()
     end
    end
   end
   
  end
  
  if mixer_state.settings_top_tab == 7 then
   mixer_state.settings_tab = 5
   r.ImGui_Spacing(ctx)
   
   rv, settings.simple_mixer_show_folder_groups = r.ImGui_Checkbox(ctx, "Show Folder Groups", settings.simple_mixer_show_folder_groups or false)
   if rv then MarkTransportPresetChanged() end
   
   if settings.simple_mixer_show_folder_groups then
    r.ImGui_Separator(ctx)
    r.ImGui_Spacing(ctx)
    
    rv, settings.simple_mixer_folder_use_track_color = r.ImGui_Checkbox(ctx, "Use Track Color", settings.simple_mixer_folder_use_track_color ~= false)
    if rv then MarkTransportPresetChanged() end
    
    if not settings.simple_mixer_folder_use_track_color then
     r.ImGui_SameLine(ctx)
     local color_val = settings.simple_mixer_folder_border_color or 0x00AAFFFF
     rv, color_val = r.ImGui_ColorEdit4(ctx, "Border##FolderBorder", color_val, r.ImGui_ColorEditFlags_NoInputs())
     if rv then
      settings.simple_mixer_folder_border_color = color_val
      MarkTransportPresetChanged()
     end
    end
    
    r.ImGui_Separator(ctx)
    r.ImGui_Spacing(ctx)
    
    if r.ImGui_BeginTable(ctx, "FolderStyleTable", 2, r.ImGui_TableFlags_None()) then
     r.ImGui_TableNextRow(ctx)
     r.ImGui_TableNextColumn(ctx)
     r.ImGui_Text(ctx, "Thickness:")
     r.ImGui_SetNextItemWidth(ctx, -1)
     rv, settings.simple_mixer_folder_border_thickness = r.ImGui_SliderInt(ctx, "##FolderThick", settings.simple_mixer_folder_border_thickness or 2, 1, 5, "%d px")
     if rv then MarkTransportPresetChanged() end
     
     r.ImGui_TableNextColumn(ctx)
     r.ImGui_Text(ctx, "Rounding:")
     r.ImGui_SetNextItemWidth(ctx, -1)
     rv, settings.simple_mixer_folder_border_rounding = r.ImGui_SliderInt(ctx, "##FolderRnd", settings.simple_mixer_folder_border_rounding or 4, 0, 12, "%d px")
     if rv then MarkTransportPresetChanged() end
     
     r.ImGui_EndTable(ctx)
    end
   end
   
  end
  
   end
  r.ImGui_EndChild(ctx)
  r.ImGui_PopFont(ctx)
  r.ImGui_End(ctx)
 end
 PopSettingsTheme(ctx)
 if not open then settings.simple_mixer_settings_popup_open = false end
end
local function DrawSimpleMixerWindow()
 if not settings.simple_mixer_window_open then return end

 EnsureSimpleMixerFont()
 mixer_state.fx_section_hovered = false

 local window_flags = r.ImGui_WindowFlags_NoCollapse() | r.ImGui_WindowFlags_NoTitleBar() | r.ImGui_WindowFlags_NoScrollbar() | r.ImGui_WindowFlags_NoScrollWithMouse()
 local mixer_ctx = ctx

 local project_mixer_tracks = GetProjectMixerTracks()
 mixer_state.hidden_track_guids = GetProjectMixerHiddenTracks()

 if settings.simple_mixer_auto_all then
  local visible_guids = {}
  local num_tracks = r.CountTracks(0)
  for i = 0, num_tracks - 1 do
   local track = r.GetTrack(0, i)
   local is_visible = r.GetMediaTrackInfo_Value(track, "B_SHOWINTCP") == 1
   if is_visible then
    local guid = r.GetTrackGUID(track)
    local spacer = r.GetMediaTrackInfo_Value(track, "I_SPACER")
    if not mixer_state.hidden_track_guids[guid] or spacer > 0 then
     visible_guids[guid] = i
    end
   end
  end
  local needs_update = false
  local new_tracks = {}
  for guid, idx in pairs(visible_guids) do
   local found = false
   for _, existing_guid in ipairs(project_mixer_tracks) do
    if existing_guid == guid then found = true break end
   end
   if not found then needs_update = true end
   table.insert(new_tracks, {guid = guid, idx = idx})
  end
  if #new_tracks ~= #project_mixer_tracks then needs_update = true end
  if needs_update then
   table.sort(new_tracks, function(a, b) return a.idx < b.idx end)
   project_mixer_tracks = {}
   for _, t in ipairs(new_tracks) do
    table.insert(project_mixer_tracks, t.guid)
   end
   SaveProjectMixerTracks(project_mixer_tracks)
  end
 end

 r.ImGui_PushStyleVar(mixer_ctx, r.ImGui_StyleVar_WindowRounding(), 8)
 r.ImGui_PushStyleVar(mixer_ctx, r.ImGui_StyleVar_FrameBorderSize(), 1)
 r.ImGui_PushStyleColor(mixer_ctx, r.ImGui_Col_WindowBg(), settings.simple_mixer_window_bg_color or 0x1E1E1EFF)
 r.ImGui_PushStyleColor(mixer_ctx, r.ImGui_Col_Border(), settings.simple_mixer_border_color or 0x444444FF)
 r.ImGui_SetNextWindowSize(mixer_ctx, settings.simple_mixer_window_width or 600, settings.simple_mixer_window_height or 700, r.ImGui_Cond_FirstUseEver())
 if settings.simple_mixer_remember_state ~= false then
  local sx = settings.simple_mixer_window_x
  local sy = settings.simple_mixer_window_y
  if sx and sy and sx > -1 and sy > -1 then
   r.ImGui_SetNextWindowPos(mixer_ctx, sx, sy, r.ImGui_Cond_FirstUseEver())
  end
 end
 local visible, open = r.ImGui_Begin(mixer_ctx, "TK Mixer", true, window_flags)
 if visible then
  if font_simple_mixer then
   r.ImGui_PushFont(mixer_ctx, font_simple_mixer, settings.simple_mixer_font_size or 12)
  end
  local sidebar_collapsed = settings.simple_mixer_sidebar_collapsed
  if sidebar_collapsed == nil then sidebar_collapsed = true end
  local sidebar_width = sidebar_collapsed and 24 or 140
  local full_avail_width, full_avail_height = r.ImGui_GetContentRegionAvail(mixer_ctx)

  r.ImGui_PushStyleColor(mixer_ctx, r.ImGui_Col_ChildBg(), settings.simple_mixer_window_bg_color or 0x1E1E1EFF)
  if r.ImGui_BeginChild(mixer_ctx, "SidebarPanel", sidebar_width, full_avail_height, 0, 0) then
   r.ImGui_PushStyleColor(mixer_ctx, r.ImGui_Col_Button(), 0x00000000)
   r.ImGui_PushStyleColor(mixer_ctx, r.ImGui_Col_ButtonHovered(), 0x44444488)
   r.ImGui_PushStyleColor(mixer_ctx, r.ImGui_Col_ButtonActive(), 0x66666688)
   local toggle_btn_x, toggle_btn_y = r.ImGui_GetCursorScreenPos(mixer_ctx)
   local arrow_btn_width = 20
   if r.ImGui_Button(mixer_ctx, "##toggle_sidebar", arrow_btn_width, 20) then
    settings.simple_mixer_sidebar_collapsed = not sidebar_collapsed
    sidebar_collapsed = settings.simple_mixer_sidebar_collapsed
    SaveMixerSettings()
   end
   local draw_list = r.ImGui_GetWindowDrawList(mixer_ctx)
   local arrow_cx = toggle_btn_x + 10
   local arrow_cy = toggle_btn_y + 10
   local arrow_color = 0xAAAAAAFF
   if sidebar_collapsed then
    r.ImGui_DrawList_AddLine(draw_list, arrow_cx - 3, arrow_cy - 5, arrow_cx + 2, arrow_cy, arrow_color, 2)
    r.ImGui_DrawList_AddLine(draw_list, arrow_cx + 2, arrow_cy, arrow_cx - 3, arrow_cy + 5, arrow_color, 2)
   else
    r.ImGui_DrawList_AddLine(draw_list, arrow_cx + 3, arrow_cy - 5, arrow_cx - 2, arrow_cy, arrow_color, 2)
    r.ImGui_DrawList_AddLine(draw_list, arrow_cx - 2, arrow_cy, arrow_cx + 3, arrow_cy + 5, arrow_color, 2)
   end
   r.ImGui_PopStyleColor(mixer_ctx, 3)
   if sidebar_collapsed then
    local sb_text = settings.simple_mixer_sidebar_text or ""
    if sb_text ~= "" then
     local text_size = settings.simple_mixer_sidebar_text_size or 14
     local text_color = settings.simple_mixer_sidebar_text_color or 0xAAAAAAFF
     local sb_font = font_simple_mixer
     if sb_font then
      r.ImGui_PushFont(mixer_ctx, sb_font, text_size)
      local win_x, win_y = r.ImGui_GetWindowPos(mixer_ctx)
      local start_y = toggle_btn_y + 24
      local line_h = math.floor(text_size * 1.05)
      local cx = toggle_btn_x + math.floor(arrow_btn_width / 2)
      for i = 1, #sb_text do
       local ch = sb_text:sub(i, i)
       local cw = r.ImGui_CalcTextSize(mixer_ctx, ch)
       r.ImGui_DrawList_AddText(draw_list, cx - cw / 2, start_y + (i - 1) * line_h, text_color, ch)
      end
      r.ImGui_PopFont(mixer_ctx)
     end
    end
   end
   if not sidebar_collapsed then
    local sidebar_mode = settings.simple_mixer_sidebar_mode or "track"
    local mode_btn_width = math.floor((sidebar_width - arrow_btn_width - 16) / 2)
    r.ImGui_SameLine(mixer_ctx, 0, 4)
    r.ImGui_PushStyleVar(mixer_ctx, r.ImGui_StyleVar_FrameRounding(), 4)
    if sidebar_mode == "track" then
     r.ImGui_PushStyleColor(mixer_ctx, r.ImGui_Col_Button(), 0x4A7A4AFF)
     r.ImGui_PushStyleColor(mixer_ctx, r.ImGui_Col_ButtonHovered(), 0x5A8A5AFF)
    else
     r.ImGui_PushStyleColor(mixer_ctx, r.ImGui_Col_Button(), 0x3A3A3AFF)
     r.ImGui_PushStyleColor(mixer_ctx, r.ImGui_Col_ButtonHovered(), 0x4A4A4AFF)
    end
    if r.ImGui_Button(mixer_ctx, "Track##mode", mode_btn_width, 20) then
     settings.simple_mixer_sidebar_mode = "track"
     SaveMixerSettings()
    end
    r.ImGui_PopStyleColor(mixer_ctx, 2)
    r.ImGui_SameLine(mixer_ctx, 0, 2)
    if sidebar_mode == "params" then
     r.ImGui_PushStyleColor(mixer_ctx, r.ImGui_Col_Button(), 0x4A7A4AFF)
     r.ImGui_PushStyleColor(mixer_ctx, r.ImGui_Col_ButtonHovered(), 0x5A8A5AFF)
    else
     r.ImGui_PushStyleColor(mixer_ctx, r.ImGui_Col_Button(), 0x3A3A3AFF)
     r.ImGui_PushStyleColor(mixer_ctx, r.ImGui_Col_ButtonHovered(), 0x4A4A4AFF)
    end
    if r.ImGui_Button(mixer_ctx, "Para##mode", mode_btn_width, 20) then
     settings.simple_mixer_sidebar_mode = "params"
     SaveMixerSettings()
    end
    r.ImGui_PopStyleColor(mixer_ctx, 2)
    r.ImGui_PopStyleVar(mixer_ctx)
    PushSettingsTheme(mixer_ctx)
    DrawMixerSidebar(mixer_ctx, sidebar_width, project_mixer_tracks)
    PopSettingsTheme(mixer_ctx)
   end
   r.ImGui_EndChild(mixer_ctx)
  end
  r.ImGui_PopStyleColor(mixer_ctx, 1)
  r.ImGui_SameLine(mixer_ctx, 0, 4)

  if project_mixer_tracks and #project_mixer_tracks > 0 then
   local track_width = settings.simple_mixer_channel_width or settings.simple_mixer_track_width or 70
   local avail_width, avail_height = r.ImGui_GetContentRegionAvail(mixer_ctx)
   local _, window_padding_y = r.ImGui_GetStyleVar(mixer_ctx, r.ImGui_StyleVar_WindowPadding())
   window_padding_y = window_padding_y or 8

   local slider_height, base_slider_height
   base_slider_height = avail_height
   if base_slider_height < 100 then base_slider_height = 100 end
   slider_height = base_slider_height

   local function RenderMasterFader()
    local master = r.GetMasterTrack(0)
    if master then
     DrawMixerChannel(mixer_ctx, master, "MASTER", 0, track_width, base_slider_height, true, false, true, nil)
    end
   end

   local pinned_tracks_data = {}
   local pinned_spacers = {}
   if settings.simple_mixer_show_pinned_first then
    for _, track_guid in ipairs(project_mixer_tracks) do
     if type(track_guid) == "string" then
      local track = r.BR_GetMediaTrackByGUID(0, track_guid)
      if track then
       local is_tcp_pinned = r.GetMediaTrackInfo_Value(track, "B_TCPPIN") == 1
       local is_mcp_pinned = r.GetMediaTrackInfo_Value(track, "B_MCPPIN") == 1
       if is_tcp_pinned or is_mcp_pinned then
        local track_num = r.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER")
        local spacer = r.GetMediaTrackInfo_Value(track, "I_SPACER")
        table.insert(pinned_tracks_data, {guid = track_guid, track = track, num = track_num})
        if spacer > 0 then
         table.insert(pinned_spacers, {track_num = track_num, spacer = spacer, track_guid = track_guid, track = track})
        end
       end
      end
     end
    end
    table.sort(pinned_tracks_data, function(a, b) return a.num < b.num end)
    table.sort(pinned_spacers, function(a, b) return a.track_num < b.track_num end)
   end

   local pinned_width = 0
   if #pinned_tracks_data > 0 then
    pinned_width = (#pinned_tracks_data * (track_width + 4)) + 4
   end

   if settings.simple_mixer_show_master and settings.simple_mixer_master_position == "left" then
    r.ImGui_PushStyleColor(mixer_ctx, r.ImGui_Col_ChildBg(), settings.simple_mixer_window_bg_color or 0x1E1E1EFF)
    if r.ImGui_BeginChild(mixer_ctx, "MasterFaderLeft", track_width + 4, avail_height, 0, r.ImGui_WindowFlags_NoScrollbar()) then
     RenderMasterFader()
     r.ImGui_EndChild(mixer_ctx)
    end
    r.ImGui_PopStyleColor(mixer_ctx, 1)
    r.ImGui_SameLine(mixer_ctx, 0, 4)
   end

   if #pinned_tracks_data > 0 then
    r.ImGui_PushStyleColor(mixer_ctx, r.ImGui_Col_ChildBg(), settings.simple_mixer_window_bg_color or 0x1E1E1EFF)
    if r.ImGui_BeginChild(mixer_ctx, "PinnedTracks", pinned_width, avail_height, 0, r.ImGui_WindowFlags_NoScrollbar()) then
     for pidx, pdata in ipairs(pinned_tracks_data) do
      local _, ptrack_name = r.GetTrackName(pdata.track)
      local show_handle = settings.simple_mixer_show_fx_slots
      DrawMixerChannel(mixer_ctx, pdata.track, ptrack_name, 1000 + pidx, track_width, base_slider_height, false, true, show_handle, nil)
      if pidx < #pinned_tracks_data then
       r.ImGui_SameLine(mixer_ctx, 0, 4)
      end
     end
     r.ImGui_EndChild(mixer_ctx)
    end
    r.ImGui_PopStyleColor(mixer_ctx, 1)
    r.ImGui_SameLine(mixer_ctx, 0, 4)
   end

   local master_right_width = (settings.simple_mixer_show_master and settings.simple_mixer_master_position == "right") and (track_width + 8) or 0
   local child_width = master_right_width > 0 and (avail_width - master_right_width - pinned_width) or (pinned_width > 0 and (avail_width - pinned_width) or 0)
   if r.ImGui_BeginChild(mixer_ctx, "MixerTracks", child_width, avail_height, r.ImGui_ChildFlags_None(), r.ImGui_WindowFlags_NoScrollbar() | r.ImGui_WindowFlags_NoScrollWithMouse()) then
    local mixer_tracks_hovered = r.ImGui_IsWindowHovered(mixer_ctx, r.ImGui_HoveredFlags_ChildWindows())
    local pending_wheel_y = r.ImGui_GetMouseWheel(mixer_ctx)
    local pending_delete = r.ImGui_IsKeyPressed(mixer_ctx, r.ImGui_Key_Delete())
    local pending_shift_held = r.ImGui_IsKeyDown(mixer_ctx, r.ImGui_Mod_Shift())

    local tracks_to_remove = {}
    local tracks_to_delete = {}
    local first_track_rendered = false

    local folder_groups = {}
    local folder_stack = {}
    local track_positions = {}
    local child_start_x, child_start_y = r.ImGui_GetCursorScreenPos(mixer_ctx)

    local function ToggleTracksAfterDivider(divider_track)
     if not divider_track then return end
     mixer_state.hidden_track_guids = mixer_state.hidden_track_guids or GetProjectMixerHiddenTracks()
     local divider_num = r.GetMediaTrackInfo_Value(divider_track, "IP_TRACKNUMBER")
     if not divider_num or divider_num < 1 then return end
     local divider_guid = r.GetTrackGUID(divider_track)
     local num_tracks = r.CountTracks(0)
     local range_guids = {}
     if divider_guid and divider_guid ~= "" then
      table.insert(range_guids, divider_guid)
     end
     for i = divider_num, num_tracks - 1 do
      local tr = r.GetTrack(0, i)
      if not tr then break end
      if r.GetMediaTrackInfo_Value(tr, "I_SPACER") > 0 then break end
      table.insert(range_guids, r.GetTrackGUID(tr))
     end
     if #range_guids == 0 then return end
     local visible = {}
     for _, guid in ipairs(project_mixer_tracks) do
      if not mixer_state.hidden_track_guids[guid] then
       visible[guid] = true
      end
     end
     local any_visible = false
     for _, guid in ipairs(range_guids) do
      if visible[guid] then any_visible = true break end
     end
     if any_visible then
      for _, guid in ipairs(range_guids) do
       visible[guid] = nil
       mixer_state.hidden_track_guids[guid] = true
      end
     else
      for _, guid in ipairs(range_guids) do
       visible[guid] = true
       mixer_state.hidden_track_guids[guid] = nil
      end
     end
     SaveProjectMixerHiddenTracks(mixer_state.hidden_track_guids)
     if settings.simple_mixer_auto_all then
      if any_visible then
       for i = #project_mixer_tracks, 1, -1 do
        local guid = project_mixer_tracks[i]
        if mixer_state.hidden_track_guids[guid] then
         local tr = r.BR_GetMediaTrackByGUID(0, guid)
         local spacer = tr and r.GetMediaTrackInfo_Value(tr, "I_SPACER") or 0
         if spacer <= 0 then
          table.remove(project_mixer_tracks, i)
         end
        end
       end
       SaveProjectMixerTracks(project_mixer_tracks)
      end
      return
     end
     local new_list = {}
     for i = 0, num_tracks - 1 do
      local tr = r.GetTrack(0, i)
      if tr then
       local guid = r.GetTrackGUID(tr)
       local spacer = r.GetMediaTrackInfo_Value(tr, "I_SPACER")
       if visible[guid] or (mixer_state.hidden_track_guids[guid] and spacer > 0) then
        table.insert(new_list, guid)
       end
      end
     end
     for i = #project_mixer_tracks, 1, -1 do
      table.remove(project_mixer_tracks, i)
     end
     for _, guid in ipairs(new_list) do
      table.insert(project_mixer_tracks, guid)
     end
     SaveProjectMixerTracks(project_mixer_tracks)
    end

    local sorted_tracks = {}
    for idx, track_guid in ipairs(project_mixer_tracks) do
     if type(track_guid) == "string" then
      local track = r.BR_GetMediaTrackByGUID(0, track_guid)
      if track then
       local track_num = r.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER")
       local is_tcp_pinned = r.GetMediaTrackInfo_Value(track, "B_TCPPIN") == 1
       local is_mcp_pinned = r.GetMediaTrackInfo_Value(track, "B_MCPPIN") == 1
       local is_pinned = is_tcp_pinned or is_mcp_pinned
       if not (settings.simple_mixer_show_pinned_first and is_pinned) then
        table.insert(sorted_tracks, {guid = track_guid, track = track, num = track_num, is_pinned = false})
       end
      end
     end
    end
    table.sort(sorted_tracks, function(a, b) return a.num < b.num end)

    if settings.simple_mixer_show_folder_groups then
     for idx, track_data in ipairs(sorted_tracks) do
      local track = track_data.track
      if track then
       local folder_depth = r.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")
       if folder_depth == 1 then
        table.insert(folder_stack, {start_idx = idx, track = track})
       elseif folder_depth < 0 then
        for _ = 1, math.abs(folder_depth) do
         if #folder_stack > 0 then
          local folder_info = table.remove(folder_stack)
          folder_info.end_idx = idx
          table.insert(folder_groups, folder_info)
         end
        end
       end
      end
     end
     for _, folder_info in ipairs(folder_stack) do
      folder_info.end_idx = #sorted_tracks
      table.insert(folder_groups, folder_info)
     end
    end

    for idx, track_data in ipairs(sorted_tracks) do
     local track = track_data.track
     local track_guid = track_data.guid
     local _, track_name = r.GetTrackName(track)

     local current_parent = r.GetParentTrack(track)
     if current_parent then
      local parent_guid = r.GetTrackGUID(current_parent)
      if mixer_state.collapsed_folders[parent_guid] then
       goto continue_track_loop
      end
     end

     if not first_track_rendered then
      first_track_rendered = true
     else
      r.ImGui_SameLine(mixer_ctx)
     end

     local current_track_num = track_data.num

     for ps_idx, ps_data in ipairs(pinned_spacers) do
      if ps_data.track_num < current_track_num and not ps_data.rendered then
       ps_data.rendered = true
       local spacer_style = settings.simple_mixer_spacer_style or "line"
       local cx, cy = r.ImGui_GetCursorScreenPos(mixer_ctx)
       local dlist = r.ImGui_GetWindowDrawList(mixer_ctx)
       local divider_height = avail_height - window_padding_y + 10
       local bg_color = settings.simple_mixer_divider_custom_color or 0x444444FF
       local border_color = settings.simple_mixer_divider_border_custom_color or 0x888888FF
       local text_color = settings.simple_mixer_divider_text_custom_color or 0xFFFFFFFF
       local pinned_track_color = r.GetTrackColor(ps_data.track)
       if settings.simple_mixer_divider_use_track_color ~= false and pinned_track_color ~= 0 then
        local rv, gv, bv = r.ColorFromNative(pinned_track_color)
        bg_color = r.ImGui_ColorConvertDouble4ToU32(rv/255, gv/255, bv/255, 0.6)
        border_color = r.ImGui_ColorConvertDouble4ToU32(rv/255, gv/255, bv/255, 1.0)
       end
       if settings.simple_mixer_divider_text_use_track_color ~= false and pinned_track_color ~= 0 then
        local rv, gv, bv = r.ColorFromNative(pinned_track_color)
        text_color = r.ImGui_ColorConvertDouble4ToU32(rv/255, gv/255, bv/255, 1.0)
       end
       if spacer_style == "track" then
        local divider_width = settings.simple_mixer_divider_width or 20
        if settings.simple_mixer_divider_filled then
         r.ImGui_DrawList_AddRectFilled(dlist, cx + 1, cy + 1, cx + divider_width - 1, cy + divider_height - 1, bg_color, 2)
        end
        if settings.simple_mixer_divider_show_border ~= false then
         r.ImGui_DrawList_AddRect(dlist, cx + 1, cy + 1, cx + divider_width - 1, cy + divider_height - 1, border_color, 2, 0, 2)
        end
        local divider_cfg = GetDividerConfig(ps_data.track_guid)
        local divider_text = GetDividerDisplayText(divider_cfg)
        if divider_text ~= "" then
         local char_height = divider_cfg.size or settings.simple_mixer_font_size or 12
         local total_text_height = #divider_text * char_height
         local start_y = cy + (divider_height - total_text_height) / 2
         for i = 1, #divider_text do
          local char = divider_text:sub(i, i)
          local char_w = r.ImGui_CalcTextSize(mixer_ctx, char)
          local char_x = cx + (divider_width - char_w) / 2
          local char_y = start_y + (i - 1) * char_height
          r.ImGui_DrawList_AddTextEx(dlist, nil, char_height, char_x, char_y, text_color, char)
         end
        end
        r.ImGui_Dummy(mixer_ctx, divider_width, divider_height)
       else
        local spacer_width = math.min(ps_data.spacer / 4, 20)
        if spacer_width < 4 then spacer_width = 4 end
        r.ImGui_DrawList_AddRectFilled(dlist, cx, cy, cx + spacer_width, cy + divider_height, bg_color, 2)
        r.ImGui_Dummy(mixer_ctx, spacer_width, divider_height)
       end
       r.ImGui_SameLine(mixer_ctx)
      end
     end

     local track_spacer = r.GetMediaTrackInfo_Value(track, "I_SPACER")
     local divider_is_hidden = mixer_state.hidden_dividers[track_guid] or settings.simple_mixer_hide_all_dividers or false
     if track_spacer > 0 and first_track_rendered and not divider_is_hidden then
      local spacer_style = settings.simple_mixer_spacer_style or "line"
      local cx, cy = r.ImGui_GetCursorScreenPos(mixer_ctx)
      local dlist = r.ImGui_GetWindowDrawList(mixer_ctx)
      local divider_height = avail_height - window_padding_y + 10
      local bg_color = settings.simple_mixer_divider_custom_color or 0x444444FF
      local border_color = settings.simple_mixer_divider_border_custom_color or 0x888888FF
      local text_color = settings.simple_mixer_divider_text_custom_color or 0xFFFFFFFF
      local track_color = r.GetTrackColor(track)
      if settings.simple_mixer_divider_use_track_color ~= false and track_color ~= 0 then
       local rv, gv, bv = r.ColorFromNative(track_color)
       bg_color = r.ImGui_ColorConvertDouble4ToU32(rv/255, gv/255, bv/255, 0.6)
       border_color = r.ImGui_ColorConvertDouble4ToU32(rv/255, gv/255, bv/255, 1.0)
      end
      if settings.simple_mixer_divider_text_use_track_color ~= false and track_color ~= 0 then
       local rv, gv, bv = r.ColorFromNative(track_color)
       text_color = r.ImGui_ColorConvertDouble4ToU32(rv/255, gv/255, bv/255, 1.0)
      end
      if spacer_style == "track" then
       local divider_width = settings.simple_mixer_divider_width or 20
       if settings.simple_mixer_divider_filled then
        r.ImGui_DrawList_AddRectFilled(dlist, cx + 1, cy + 1, cx + divider_width - 1, cy + divider_height - 1, bg_color, 2)
       end
       if settings.simple_mixer_divider_show_border ~= false then
        r.ImGui_DrawList_AddRect(dlist, cx + 1, cy + 1, cx + divider_width - 1, cy + divider_height - 1, border_color, 2, 0, 2)
       end
       local is_editing_divider = (mixer_state.editing_divider_guid == track_guid)
       local popup_id = "DividerEditPopup##" .. track_guid
       if is_editing_divider then
        r.ImGui_OpenPopup(mixer_ctx, popup_id)
       end
       r.ImGui_SetNextWindowPos(mixer_ctx, cx + divider_width + 5, cy + 20, r.ImGui_Cond_Appearing())
       if r.ImGui_BeginPopup(mixer_ctx, popup_id) then
        local edit_cfg = mixer_state.editing_divider_cfg
        if not edit_cfg then
         local current = GetDividerConfig(track_guid)
         edit_cfg = { mode = current.mode, text = current.text, size = current.size }
         mixer_state.editing_divider_cfg = edit_cfg
        end
        r.ImGui_Text(mixer_ctx, "Divider Text:")
        if r.ImGui_RadioButton(mixer_ctx, "No text", edit_cfg.mode == "none") then edit_cfg.mode = "none" end
        r.ImGui_SameLine(mixer_ctx)
        if r.ImGui_RadioButton(mixer_ctx, "Default", edit_cfg.mode == "default") then edit_cfg.mode = "default" end
        r.ImGui_SameLine(mixer_ctx)
        if r.ImGui_RadioButton(mixer_ctx, "Custom", edit_cfg.mode == "custom") then edit_cfg.mode = "custom" end
        r.ImGui_PushItemWidth(mixer_ctx, 200)
        local rv_text, new_text = r.ImGui_InputText(mixer_ctx, "##divider_text", edit_cfg.text or "", r.ImGui_InputTextFlags_AutoSelectAll())
        if rv_text then edit_cfg.text = new_text; edit_cfg.mode = "custom" end
        if r.ImGui_IsWindowAppearing(mixer_ctx) then
         r.ImGui_SetKeyboardFocusHere(mixer_ctx, -1)
        end
        local rv_size, new_size = r.ImGui_SliderInt(mixer_ctx, "Size##divider_size", edit_cfg.size or 12, 8, 36, "%d px")
        if rv_size then edit_cfg.size = new_size end
        r.ImGui_PopItemWidth(mixer_ctx)
        if r.ImGui_Button(mixer_ctx, "OK") or r.ImGui_IsKeyPressed(mixer_ctx, r.ImGui_Key_Enter()) then
         SetDividerConfig(track_guid, { mode = edit_cfg.mode, text = edit_cfg.text or "", size = edit_cfg.size or 12 })
         mixer_state.editing_divider_guid = nil
         mixer_state.editing_divider_name = ""
         mixer_state.editing_divider_cfg = nil
         r.ImGui_CloseCurrentPopup(mixer_ctx)
        end
        r.ImGui_SameLine(mixer_ctx)
        if r.ImGui_Button(mixer_ctx, "Cancel") then
         mixer_state.editing_divider_guid = nil
         mixer_state.editing_divider_name = ""
         mixer_state.editing_divider_cfg = nil
         r.ImGui_CloseCurrentPopup(mixer_ctx)
        end
        r.ImGui_EndPopup(mixer_ctx)
       elseif is_editing_divider then
        mixer_state.editing_divider_guid = nil
        mixer_state.editing_divider_name = ""
        mixer_state.editing_divider_cfg = nil
       end
       local divider_cfg = GetDividerConfig(track_guid)
       local divider_text = GetDividerDisplayText(divider_cfg)
       if divider_text ~= "" then
        local char_height = divider_cfg.size or settings.simple_mixer_font_size or 12
        local total_text_height = #divider_text * char_height
        local start_y = cy + (divider_height - total_text_height) / 2
        for i = 1, #divider_text do
         local char = divider_text:sub(i, i)
         local char_w = r.ImGui_CalcTextSize(mixer_ctx, char)
         local char_x = cx + (divider_width - char_w) / 2
         local char_y = start_y + (i - 1) * char_height
         r.ImGui_DrawList_AddTextEx(dlist, nil, char_height, char_x, char_y, text_color, char)
        end
       end
       r.ImGui_Dummy(mixer_ctx, divider_width, divider_height)
       if r.ImGui_IsItemHovered(mixer_ctx) then
        r.ImGui_SetTooltip(mixer_ctx, "Double-click to edit, right-click for menu")
        if r.ImGui_IsMouseDoubleClicked(mixer_ctx, r.ImGui_MouseButton_Left()) then
         mixer_state.editing_divider_guid = track_guid
         mixer_state.editing_divider_name = divider_text
         mixer_state.editing_divider_cfg = nil
        end
        if r.ImGui_IsMouseClicked(mixer_ctx, r.ImGui_MouseButton_Right()) then
         r.ImGui_OpenPopup(mixer_ctx, "DividerContextMenu##" .. track_guid)
        end
       end
       if r.ImGui_BeginPopup(mixer_ctx, "DividerContextMenu##" .. track_guid) then
        if r.ImGui_MenuItem(mixer_ctx, "Edit Divider...") then
         mixer_state.editing_divider_guid = track_guid
         mixer_state.editing_divider_name = divider_text
         mixer_state.editing_divider_cfg = nil
        end
        if r.ImGui_MenuItem(mixer_ctx, "Toggle Tracks After Divider") then
         ToggleTracksAfterDivider(track)
        end
        if r.ImGui_MenuItem(mixer_ctx, "Hide Divider") then
         mixer_state.hidden_dividers[track_guid] = true
        end
        if r.ImGui_MenuItem(mixer_ctx, "Remove Divider") then
         r.Undo_BeginBlock()
         r.SetMediaTrackInfo_Value(track, "I_SPACER", 0)
         r.TrackList_AdjustWindows(false)
         r.UpdateTimeline()
         r.Undo_EndBlock("Remove track divider", -1)
        end
        r.ImGui_EndPopup(mixer_ctx)
       end
      else
       local spacer_width = math.min(track_spacer / 4, 20)
       if spacer_width < 4 then spacer_width = 4 end
       r.ImGui_DrawList_AddRectFilled(dlist, cx, cy, cx + spacer_width, cy + divider_height, bg_color, 2)
       r.ImGui_Dummy(mixer_ctx, spacer_width, divider_height)
       if r.ImGui_IsItemHovered(mixer_ctx) then
        r.ImGui_SetTooltip(mixer_ctx, "Right-click for menu")
        if r.ImGui_IsMouseClicked(mixer_ctx, r.ImGui_MouseButton_Right()) then
         r.ImGui_OpenPopup(mixer_ctx, "DividerLineContextMenu##" .. track_guid)
        end
       end
       if r.ImGui_BeginPopup(mixer_ctx, "DividerLineContextMenu##" .. track_guid) then
        if r.ImGui_MenuItem(mixer_ctx, "Toggle Tracks After Divider") then
         ToggleTracksAfterDivider(track)
        end
        if r.ImGui_MenuItem(mixer_ctx, "Hide Divider") then
         mixer_state.hidden_dividers[track_guid] = true
        end
        if r.ImGui_MenuItem(mixer_ctx, "Remove Divider") then
         r.Undo_BeginBlock()
         r.SetMediaTrackInfo_Value(track, "I_SPACER", 0)
         r.TrackList_AdjustWindows(false)
         r.UpdateTimeline()
         r.Undo_EndBlock("Remove track divider", -1)
        end
        r.ImGui_EndPopup(mixer_ctx)
       end
      end
      r.ImGui_SameLine(mixer_ctx)
      if mixer_state.hidden_track_guids and mixer_state.hidden_track_guids[track_guid] and track_spacer > 0 then
       local cursor_x, cursor_y = r.ImGui_GetCursorScreenPos(mixer_ctx)
       track_positions[idx] = {x = cursor_x, y = cursor_y}
       r.ImGui_SameLine(mixer_ctx)
       goto continue_track_loop
      end
     end

     local cursor_x, cursor_y = r.ImGui_GetCursorScreenPos(mixer_ctx)
     track_positions[idx] = {x = cursor_x, y = cursor_y}

     local show_handle = settings.simple_mixer_show_fx_slots
     local folder_info = {is_folder = false, is_child = false, folder_color = 0, continue_line = false}
     local folder_depth = r.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH")
     if folder_depth == 1 then
      folder_info.is_folder = true
      folder_info.folder_color = r.GetTrackColor(track)
      local folder_guid = r.GetTrackGUID(track)
      if not mixer_state.collapsed_folders[folder_guid] then
       folder_info.continue_line = true
      end
     else
      if current_parent then
       folder_info.is_child = true
       folder_info.folder_color = r.GetTrackColor(current_parent)
       local next_track_data = sorted_tracks[idx + 1]
       if next_track_data then
        local next_parent = r.GetParentTrack(next_track_data.track)
        if next_parent == current_parent then
         folder_info.continue_line = true
        end
       end
      end
     end

     local should_remove, should_delete, should_delete_selected = DrawMixerChannel(mixer_ctx, track, track_name, idx, track_width, base_slider_height, false, true, show_handle, folder_info)
     if should_remove then
      table.insert(tracks_to_remove, track_guid)
     end
     if should_delete then
      table.insert(tracks_to_delete, {idx = idx, track = track, guid = track_guid})
     end
     if should_delete_selected then
      local num_sel = r.CountSelectedTracks(0)
      for i = 0, num_sel - 1 do
       local sel_track = r.GetSelectedTrack(0, i)
       if sel_track then
        local sel_guid = r.GetTrackGUID(sel_track)
        local already_in_list = false
        for _, del_info in ipairs(tracks_to_delete) do
         if del_info.guid == sel_guid then already_in_list = true break end
        end
        if not already_in_list then
         table.insert(tracks_to_delete, {idx = -1, track = sel_track, guid = sel_guid})
        end
       end
      end
     end
     ::continue_track_loop::
    end

    local remaining_width = r.ImGui_GetContentRegionAvail(mixer_ctx)
    if remaining_width > 10 then
     if first_track_rendered then
      r.ImGui_SameLine(mixer_ctx)
     end
     r.ImGui_PushStyleColor(mixer_ctx, r.ImGui_Col_Button(), 0x00000000)
     r.ImGui_PushStyleColor(mixer_ctx, r.ImGui_Col_ButtonHovered(), 0x00000000)
     r.ImGui_PushStyleColor(mixer_ctx, r.ImGui_Col_ButtonActive(), 0x00000000)
     r.ImGui_PushStyleColor(mixer_ctx, r.ImGui_Col_Border(), 0x00000000)
     r.ImGui_PushStyleVar(mixer_ctx, r.ImGui_StyleVar_FrameBorderSize(), 0)
     r.ImGui_InvisibleButton(mixer_ctx, "##AddNewTrackInvisible", remaining_width, avail_height)
     local is_hovered = r.ImGui_IsItemHovered(mixer_ctx)
     if is_hovered and r.ImGui_IsMouseDoubleClicked(mixer_ctx, 0) then
      r.Undo_BeginBlock()
      r.InsertTrackAtIndex(r.CountTracks(0), true)
      local new_track = r.GetTrack(0, r.CountTracks(0) - 1)
      if new_track then
       local new_guid = r.GetTrackGUID(new_track)
       table.insert(project_mixer_tracks, new_guid)
       SaveProjectMixerTracks(project_mixer_tracks)
      end
      r.Undo_EndBlock("Insert new track for mixer", -1)
     end
     if is_hovered and r.ImGui_IsMouseClicked(mixer_ctx, r.ImGui_MouseButton_Right()) then
      r.ImGui_OpenPopup(mixer_ctx, "MixerEmptyAreaMenu")
     end
     if r.ImGui_BeginPopup(mixer_ctx, "MixerEmptyAreaMenu") then
      if r.ImGui_MenuItem(mixer_ctx, "Add Selected Tracks") then
       local num_sel_tracks = r.CountSelectedTracks(0)
       if num_sel_tracks > 0 then
        for i = 0, num_sel_tracks - 1 do
         local track = r.GetSelectedTrack(0, i)
         local guid = r.GetTrackGUID(track)
         local already_added = false
         for _, existing_guid in ipairs(project_mixer_tracks) do
          if existing_guid == guid then already_added = true break end
         end
         if not already_added then
          table.insert(project_mixer_tracks, guid)
         end
        end
        SaveProjectMixerTracks(project_mixer_tracks)
       end
      end
      if r.ImGui_MenuItem(mixer_ctx, "Add All Tracks") then
       local num_tracks = r.CountTracks(0)
       for i = 0, num_tracks - 1 do
        local track = r.GetTrack(0, i)
        local guid = r.GetTrackGUID(track)
        local already_added = false
        for _, existing_guid in ipairs(project_mixer_tracks) do
         if existing_guid == guid then already_added = true break end
        end
        if not already_added then
         table.insert(project_mixer_tracks, guid)
        end
       end
       SaveProjectMixerTracks(project_mixer_tracks)
      end
      r.ImGui_Separator(mixer_ctx)
      if r.ImGui_MenuItem(mixer_ctx, "Mixer Settings...") then
       settings.simple_mixer_settings_popup_open = true
       mixer_state.select_settings_tab = "mixer"
      end
      r.ImGui_EndPopup(mixer_ctx)
     end
     r.ImGui_PopStyleVar(mixer_ctx, 1)
     r.ImGui_PopStyleColor(mixer_ctx, 4)
     if is_hovered then
      r.ImGui_SetTooltip(mixer_ctx, "Double-click to add new track\nRight-click for more options")
     end
    end

    if settings.simple_mixer_show_folder_groups and #folder_groups > 0 then
     local dlist = r.ImGui_GetWindowDrawList(mixer_ctx)
     local padding = settings.simple_mixer_folder_padding or 2
     local thickness = settings.simple_mixer_folder_border_thickness or 2
     local rounding = settings.simple_mixer_folder_border_rounding or 4
     local text_line_height = r.ImGui_GetTextLineHeight(mixer_ctx)
     local name_area_height = text_line_height + 16
     for _, group in ipairs(folder_groups) do
      local start_pos = track_positions[group.start_idx]
      local end_pos = track_positions[group.end_idx]
      if start_pos and end_pos then
       local border_color
       if settings.simple_mixer_folder_use_track_color and group.track then
        local track_color = r.GetTrackColor(group.track)
        if track_color ~= 0 then
         local rb, gb, bb = r.ColorFromNative(track_color)
         border_color = r.ImGui_ColorConvertDouble4ToU32(rb/255, gb/255, bb/255, 1.0)
        else
         border_color = settings.simple_mixer_folder_border_color or 0x888888FF
        end
       else
        border_color = settings.simple_mixer_folder_border_color or 0x888888FF
       end
       local rect_x1 = start_pos.x - padding
       local rect_y1 = start_pos.y
       local rect_y2 = child_start_y + avail_height
       local rect_x2 = end_pos.x + track_width + padding
       if rounding > 0 then
        local corner_y = rect_y2 - rounding
        r.ImGui_DrawList_AddLine(dlist, rect_x1, rect_y1, rect_x1, corner_y, border_color, thickness)
        r.ImGui_DrawList_AddLine(dlist, rect_x2, rect_y1, rect_x2, corner_y, border_color, thickness)
        r.ImGui_DrawList_AddBezierQuadratic(dlist, rect_x1, corner_y, rect_x1, rect_y2, rect_x1 + rounding, rect_y2, border_color, thickness, 12)
        r.ImGui_DrawList_AddBezierQuadratic(dlist, rect_x2, corner_y, rect_x2, rect_y2, rect_x2 - rounding, rect_y2, border_color, thickness, 12)
        r.ImGui_DrawList_AddLine(dlist, rect_x1 + rounding, rect_y2, rect_x2 - rounding, rect_y2, border_color, thickness)
       else
        r.ImGui_DrawList_AddLine(dlist, rect_x1, rect_y1, rect_x1, rect_y2, border_color, thickness)
        r.ImGui_DrawList_AddLine(dlist, rect_x2, rect_y1, rect_x2, rect_y2, border_color, thickness)
        r.ImGui_DrawList_AddLine(dlist, rect_x1, rect_y2, rect_x2, rect_y2, border_color, thickness)
       end
      end
     end
    end

    for _, guid_to_remove in ipairs(tracks_to_remove) do
     for i = #project_mixer_tracks, 1, -1 do
      if project_mixer_tracks[i] == guid_to_remove then
       table.remove(project_mixer_tracks, i)
       break
      end
     end
    end
    if #tracks_to_remove > 0 then
     SaveProjectMixerTracks(project_mixer_tracks)
    end

    if #tracks_to_delete > 0 then
     r.Undo_BeginBlock()
     r.PreventUIRefresh(1)
     for i = #tracks_to_delete, 1, -1 do
      local del_info = tracks_to_delete[i]
      if del_info.track and r.ValidatePtr(del_info.track, "MediaTrack*") then
       r.DeleteTrack(del_info.track)
      end
      for j = #project_mixer_tracks, 1, -1 do
       if project_mixer_tracks[j] == del_info.guid then
        table.remove(project_mixer_tracks, j)
        break
       end
      end
     end
     SaveProjectMixerTracks(project_mixer_tracks)
     r.PreventUIRefresh(-1)
     r.Undo_EndBlock("Delete tracks from mixer", -1)
    end

    if mixer_tracks_hovered and not mixer_state.fx_section_hovered then
     if pending_wheel_y ~= 0 then
      local scroll_x = r.ImGui_GetScrollX(mixer_ctx)
      r.ImGui_SetScrollX(mixer_ctx, scroll_x - pending_wheel_y * 50)
     end
     if pending_delete then
      local selected_guids = {}
      for _, track_guid in ipairs(project_mixer_tracks) do
       local track = r.BR_GetMediaTrackByGUID(0, track_guid)
       if track and r.IsTrackSelected(track) then
        table.insert(selected_guids, track_guid)
       end
      end
      if #selected_guids > 0 then
       if pending_shift_held then
        r.Undo_BeginBlock()
        r.PreventUIRefresh(1)
        for i = #selected_guids, 1, -1 do
         local track = r.BR_GetMediaTrackByGUID(0, selected_guids[i])
         if track and r.ValidatePtr(track, "MediaTrack*") then
          r.DeleteTrack(track)
         end
         for j = #project_mixer_tracks, 1, -1 do
          if project_mixer_tracks[j] == selected_guids[i] then
           table.remove(project_mixer_tracks, j)
           break
          end
         end
        end
        SaveProjectMixerTracks(project_mixer_tracks)
        r.PreventUIRefresh(-1)
        r.Undo_EndBlock("Delete selected tracks from mixer", -1)
       else
        for _, guid in ipairs(selected_guids) do
         for j = #project_mixer_tracks, 1, -1 do
          if project_mixer_tracks[j] == guid then
           table.remove(project_mixer_tracks, j)
           break
          end
         end
        end
        SaveProjectMixerTracks(project_mixer_tracks)
       end
      end
     end
    end

    r.ImGui_EndChild(mixer_ctx)
   end

   if settings.simple_mixer_show_master and settings.simple_mixer_master_position == "right" then
    r.ImGui_SameLine(mixer_ctx, 0, 4)
    r.ImGui_PushStyleColor(mixer_ctx, r.ImGui_Col_ChildBg(), settings.simple_mixer_window_bg_color or 0x1E1E1EFF)
    if r.ImGui_BeginChild(mixer_ctx, "MasterFaderRight", track_width + 4, avail_height, 0, r.ImGui_WindowFlags_NoScrollbar()) then
     RenderMasterFader()
     r.ImGui_EndChild(mixer_ctx)
    end
    r.ImGui_PopStyleColor(mixer_ctx, 1)
   end
  else
   local avail_w, avail_h = r.ImGui_GetContentRegionAvail(mixer_ctx)
   if avail_w < 50 then avail_w = 200 end
   if avail_h < 50 then avail_h = 200 end
   r.ImGui_PushStyleColor(mixer_ctx, r.ImGui_Col_ChildBg(), settings.simple_mixer_window_bg_color or 0x1E1E1EFF)
   if r.ImGui_BeginChild(mixer_ctx, "EmptyMixerArea", avail_w, avail_h, 0, 0) then
    local child_w, child_h = r.ImGui_GetContentRegionAvail(mixer_ctx)
    local content_start_y = r.ImGui_GetCursorPosY(mixer_ctx)
    r.ImGui_Text(mixer_ctx, "No tracks added.")
    r.ImGui_TextWrapped(mixer_ctx, "Double-click to create a new track, or use the buttons below.")
    r.ImGui_Spacing(mixer_ctx)
    if r.ImGui_Button(mixer_ctx, "+ Add Selected Tracks", -1, 30) then
     local num_sel_tracks = r.CountSelectedTracks(0)
     if num_sel_tracks > 0 then
      for i = 0, num_sel_tracks - 1 do
       local track = r.GetSelectedTrack(0, i)
       local guid = r.GetTrackGUID(track)
       local already_added = false
       for _, existing_guid in ipairs(project_mixer_tracks) do
        if existing_guid == guid then already_added = true break end
       end
       if not already_added then
        table.insert(project_mixer_tracks, guid)
       end
      end
      SaveProjectMixerTracks(project_mixer_tracks)
     end
    end
    r.ImGui_Spacing(mixer_ctx)
    if r.ImGui_Button(mixer_ctx, "+ Create New Track", -1, 30) then
     r.Undo_BeginBlock()
     r.InsertTrackAtIndex(r.CountTracks(0), true)
     local new_track = r.GetTrack(0, r.CountTracks(0) - 1)
     if new_track then
      local new_guid = r.GetTrackGUID(new_track)
      table.insert(project_mixer_tracks, new_guid)
      SaveProjectMixerTracks(project_mixer_tracks)
     end
     r.Undo_EndBlock("Insert new track for mixer", -1)
    end
    local remaining_h = child_h - (r.ImGui_GetCursorPosY(mixer_ctx) - content_start_y)
    if remaining_h > 10 then
     r.ImGui_InvisibleButton(mixer_ctx, "##empty_mixer_dblclick", child_w, remaining_h)
     if r.ImGui_IsItemHovered(mixer_ctx) and r.ImGui_IsMouseDoubleClicked(mixer_ctx, r.ImGui_MouseButton_Left()) then
      r.Undo_BeginBlock()
      r.InsertTrackAtIndex(r.CountTracks(0), true)
      local new_track = r.GetTrack(0, r.CountTracks(0) - 1)
      if new_track then
       local new_guid = r.GetTrackGUID(new_track)
       table.insert(project_mixer_tracks, new_guid)
       SaveProjectMixerTracks(project_mixer_tracks)
      end
      r.Undo_EndBlock("Insert new track for mixer", -1)
     end
    end
    r.ImGui_EndChild(mixer_ctx)
   end
   r.ImGui_PopStyleColor(mixer_ctx, 1)
  end

  if EQ and EQ.DrawShelfQPopup then
   EQ.DrawShelfQPopup(mixer_ctx)
  end

  if settings.simple_mixer_remember_state ~= false then
   local wx, wy = r.ImGui_GetWindowPos(mixer_ctx)
   local ww, wh = r.ImGui_GetWindowSize(mixer_ctx)
   if wx and wy and ww and wh then
    local sx = settings.simple_mixer_window_x or -1
    local sy = settings.simple_mixer_window_y or -1
    local sw = settings.simple_mixer_window_width or 600
    local sh = settings.simple_mixer_window_height or 700
    if math.abs(wx - sx) > 1 or math.abs(wy - sy) > 1 or math.abs(ww - sw) > 1 or math.abs(wh - sh) > 1 then
     settings.simple_mixer_window_x = math.floor(wx)
     settings.simple_mixer_window_y = math.floor(wy)
     settings.simple_mixer_window_width = math.floor(ww)
     settings.simple_mixer_window_height = math.floor(wh)
     SaveMixerSettings()
    end
   end
  end

  if font_simple_mixer then
   r.ImGui_PopFont(mixer_ctx)
  end
  r.ImGui_End(mixer_ctx)
 end
 r.ImGui_PopStyleColor(mixer_ctx, 2)
 r.ImGui_PopStyleVar(mixer_ctx, 2)
 if not open then settings.simple_mixer_window_open = false end
end

local function HandleMixerIconBrowser()
 if not IconBrowser or not IconBrowser.show_window then return end
 local ok, selected_icon = pcall(IconBrowser.Show, ctx, settings)
 if not ok then
  IconBrowser.show_window = false
  return
 end
 local picked
 if IconBrowser.browse_mode == "images" and IconBrowser.selected_image_path then
  picked = IconBrowser.selected_image_path
 elseif selected_icon then
  picked = selected_icon
 end
 if not picked then return end
 local target = r.GetSelectedTrack(0, 0) or mixer_state.icon_target_track
 if not target or not r.ValidatePtr(target, "MediaTrack*") then return end
 local target_guid = r.GetTrackGUID(target)
 local apply_key = tostring(target_guid) .. "|" .. picked
 if apply_key == mixer_state.icon_browser_last_applied then return end
 if settings.simple_mixer_hide_tcp_icons then
  r.GetSetMediaTrackInfo_String(target, "P_EXT:" .. TCP_ICON_EXT_KEY, picked, true)
  r.GetSetMediaTrackInfo_String(target, "P_ICON", "", true)
 else
  r.GetSetMediaTrackInfo_String(target, "P_EXT:" .. TCP_ICON_EXT_KEY, "", true)
  r.GetSetMediaTrackInfo_String(target, "P_ICON", picked, true)
 end
 ClearTrackIconCache(target)
 mixer_state.icon_browser_last_applied = apply_key
end

local function Loop()
 DrawSimpleMixerWindow()
 DrawSettingsWindow()
 HandleMixerIconBrowser()
 if settings.simple_mixer_window_open then
  r.defer(Loop)
 elseif mixer_settings_dirty then
  WriteMixerSettingsToDisk()
 end
end

r.atexit(function()
 if mixer_settings_dirty then
  WriteMixerSettingsToDisk()
 end
end)

r.defer(Loop)
