local r = reaper
local Theme = require("core.theme")
local UI = require("core.ui")
local UIScale = require("core.ui_scale")
local json = require("core.json")
local QuickFX = require("core.quick_fx_menu")

local M = {
  id = "fx_groups",
  title = "FX Groups",
  icon = "GRP",
  version = "0.1.0"
}

local EXT_SECTION = "TK_WORKBENCH_FX_GROUPS_V1"
local EXT_KEY = "groups"

local PALETTE = {
  0x7AA2F7FF, 0x9ECE6AFF, 0xE0AF68FF, 0xF7768EFF,
  0xBB9AF7FF, 0x7DCFFFFF, 0xFF9E64FF, 0xA0A0A0FF
}

local defaults = {
  sync_paused = false
}

local state = {
  groups = {},
  selected_group_id = nil,
  project = nil,
  last_sig = nil,
  last_value = nil,
  expanded = {},
  editing_group_id = nil,
  editing_focus = false
}

local function ensure_settings(app)
  app.settings.fx_groups = app.settings.fx_groups or {}
  local settings = app.settings.fx_groups
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

local function current_project()
  if r.EnumProjects then return r.EnumProjects(-1, "") end
  return 0
end

local function new_id()
  if r.genGuid then
    local guid = r.genGuid("")
    if guid and guid ~= "" then return guid end
  end
  return tostring(math.floor((r.time_precise and r.time_precise() or os.clock()) * 1000000)) .. "_" .. tostring(math.random(1000, 9999))
end

local function validate_track(track)
  if not track then return false end
  if r.ValidatePtr2 then return r.ValidatePtr2(0, track, "MediaTrack*") end
  return true
end

local function track_guid(track)
  if not validate_track(track) then return "" end
  if r.GetTrackGUID then return r.GetTrackGUID(track) or "" end
  return ""
end

local function find_track_by_guid(guid)
  if not guid or guid == "" then return nil end
  if r.BR_GetMediaTrackByGUID then
    local track = r.BR_GetMediaTrackByGUID(0, guid)
    if validate_track(track) then return track end
  end
  for index = 0, (r.CountTracks(0) or 0) - 1 do
    local track = r.GetTrack(0, index)
    if track and r.GetTrackGUID(track) == guid then return track end
  end
  return nil
end

local function track_name(track)
  if not track then return "" end
  local ok, name = r.GetTrackName(track)
  if ok and name and name ~= "" then return name end
  return "Track"
end

local function fx_name(track, idx)
  local _, name = r.TrackFX_GetFXName(track, idx, "")
  return name or ""
end

local function occurrence_index(track, fxidx, name)
  local occ = 0
  for i = 0, fxidx do
    if fx_name(track, i) == name then occ = occ + 1 end
  end
  return occ
end

local function find_nth_named_fx(track, name, occ)
  local seen = 0
  local count = r.TrackFX_GetCount(track) or 0
  for i = 0, count - 1 do
    if fx_name(track, i) == name then
      seen = seen + 1
      if seen == occ then return i end
    end
  end
  return nil
end

local function normalize_group(raw)
  if type(raw) ~= "table" then return nil end
  local group = {
    id = type(raw.id) == "string" and raw.id ~= "" and raw.id or new_id(),
    name = type(raw.name) == "string" and raw.name or "Group",
    color = tonumber(raw.color) or PALETTE[1],
    link_active = raw.link_active ~= false,
    master = type(raw.master) == "string" and raw.master ~= "" and raw.master or nil,
    excluded = {},
    param_excluded = {},
    fx_master = {},
    members = {}
  }
  if type(raw.members) == "table" then
    for _, guid in ipairs(raw.members) do
      if type(guid) == "string" and guid ~= "" then group.members[#group.members + 1] = guid end
    end
  end
  if type(raw.excluded) == "table" then
    for _, key in ipairs(raw.excluded) do
      if type(key) == "string" and key ~= "" then group.excluded[#group.excluded + 1] = key end
    end
  end
  if type(raw.param_excluded) == "table" then
    for _, key in ipairs(raw.param_excluded) do
      if type(key) == "string" and key ~= "" then group.param_excluded[#group.param_excluded + 1] = key end
    end
  end
  if type(raw.fx_master) == "table" then
    for key, guid in pairs(raw.fx_master) do
      if type(key) == "string" and key ~= "" and type(guid) == "string" and guid ~= "" then
        group.fx_master[key] = guid
      end
    end
  end
  return group
end

local function load_groups()
  local result = {}
  if not r.GetProjExtState then return result end
  local _, raw = r.GetProjExtState(0, EXT_SECTION, EXT_KEY)
  if not raw or raw == "" then return result end
  local ok, decoded = pcall(json.decode, raw)
  if not ok or type(decoded) ~= "table" then return result end
  for _, entry in ipairs(decoded) do
    local group = normalize_group(entry)
    if group then result[#result + 1] = group end
  end
  return result
end

local function save_groups()
  if not r.SetProjExtState then return end
  local ok, encoded = pcall(json.encode, state.groups)
  if not ok or not encoded then return end
  r.SetProjExtState(0, EXT_SECTION, EXT_KEY, encoded)
end

local function refresh_project()
  local proj = current_project()
  if proj ~= state.project then
    state.project = proj
    state.groups = load_groups()
    state.last_sig = nil
    state.last_value = nil
    if state.selected_group_id then
      local found = false
      for _, group in ipairs(state.groups) do
        if group.id == state.selected_group_id then found = true break end
      end
      if not found then state.selected_group_id = nil end
    end
  end
end

local function selected_group()
  if not state.selected_group_id then return nil end
  for _, group in ipairs(state.groups) do
    if group.id == state.selected_group_id then return group end
  end
  return nil
end

local function member_has(group, guid)
  for _, existing in ipairs(group.members) do
    if existing == guid then return true end
  end
  return false
end

local function groups_with_member(guid, only_active)
  local result = {}
  for _, group in ipairs(state.groups) do
    if (not only_active or group.link_active) and member_has(group, guid) then
      result[#result + 1] = group
    end
  end
  return result
end

local function create_group()
  local group = {
    id = new_id(),
    name = "Group " .. tostring(#state.groups + 1),
    color = PALETTE[((#state.groups) % #PALETTE) + 1],
    link_active = true,
    members = {}
  }
  state.groups[#state.groups + 1] = group
  state.selected_group_id = group.id
  save_groups()
  return group
end

local function delete_group(group)
  for index, existing in ipairs(state.groups) do
    if existing.id == group.id then
      table.remove(state.groups, index)
      break
    end
  end
  if state.selected_group_id == group.id then state.selected_group_id = nil end
  save_groups()
end

local function add_selected_tracks(group)
  local added = 0
  local count = r.CountSelectedTracks and (r.CountSelectedTracks(0) or 0) or 0
  for index = 0, count - 1 do
    local track = r.GetSelectedTrack(0, index)
    local guid = track_guid(track)
    if guid ~= "" and not member_has(group, guid) then
      group.members[#group.members + 1] = guid
      added = added + 1
    end
  end
  if added > 0 then
    if not group.master or not member_has(group, group.master) then
      group.master = group.members[1]
    end
    save_groups()
  end
  return added
end

local function set_master(group, guid)
  group.master = guid
  save_groups()
end

local function remove_member(group, guid)
  for index, existing in ipairs(group.members) do
    if existing == guid then
      table.remove(group.members, index)
      if group.master == guid then group.master = group.members[1] end
      save_groups()
      return
    end
  end
end

local function fx_key(name, occ)
  return tostring(name) .. "##" .. tostring(occ)
end

local function members_with_fx(group, name, occ)
  local result = {}
  for _, guid in ipairs(group.members) do
    local track = find_track_by_guid(guid)
    if track then
      local fxidx = find_nth_named_fx(track, name, occ)
      if fxidx then result[#result + 1] = { guid = guid, track = track, fxidx = fxidx } end
    end
  end
  return result
end

local function set_fx_master(group, key, guid)
  group.fx_master = group.fx_master or {}
  group.fx_master[key] = guid or nil
  save_groups()
end

local function resolve_fx_source(group, name, occ)
  local pinned = group.fx_master and group.fx_master[fx_key(name, occ)]
  if pinned and member_has(group, pinned) then
    local pt = find_track_by_guid(pinned)
    if pt then
      local fxidx = find_nth_named_fx(pt, name, occ)
      if fxidx then return pt, fxidx end
    end
  end
  if group.master and member_has(group, group.master) then
    local mt = find_track_by_guid(group.master)
    if mt then
      local fxidx = find_nth_named_fx(mt, name, occ)
      if fxidx then return mt, fxidx end
    end
  end
  for _, guid in ipairs(group.members) do
    local track = find_track_by_guid(guid)
    if track then
      local fxidx = find_nth_named_fx(track, name, occ)
      if fxidx then return track, fxidx end
    end
  end
  return nil
end

local function is_fx_excluded(group, key)
  if not group.excluded then return false end
  for _, existing in ipairs(group.excluded) do
    if existing == key then return true end
  end
  return false
end

local function set_fx_excluded(group, key, excluded)
  group.excluded = group.excluded or {}
  local idx = nil
  for index, existing in ipairs(group.excluded) do
    if existing == key then idx = index break end
  end
  if excluded and not idx then
    group.excluded[#group.excluded + 1] = key
  elseif not excluded and idx then
    table.remove(group.excluded, idx)
  end
  save_groups()
end

local function param_key(name, occ, param)
  return tostring(name) .. "##" .. tostring(occ) .. "##" .. tostring(param)
end

local function is_param_excluded(group, name, occ, param)
  if not group.param_excluded then return false end
  local key = param_key(name, occ, param)
  for _, existing in ipairs(group.param_excluded) do
    if existing == key then return true end
  end
  return false
end

local function set_param_excluded(group, name, occ, param, excluded)
  group.param_excluded = group.param_excluded or {}
  local key = param_key(name, occ, param)
  local idx = nil
  for index, existing in ipairs(group.param_excluded) do
    if existing == key then idx = index break end
  end
  if excluded and not idx then
    group.param_excluded[#group.param_excluded + 1] = key
  elseif not excluded and idx then
    table.remove(group.param_excluded, idx)
  end
  save_groups()
end

local function group_linked_fx(group)
  local total = 0
  local present = {}
  local order = {}
  for _, guid in ipairs(group.members) do
    local track = find_track_by_guid(guid)
    if track then
      total = total + 1
      local seen = {}
      local count = r.TrackFX_GetCount(track) or 0
      for i = 0, count - 1 do
        local name = fx_name(track, i)
        if name ~= "" then
          seen[name] = (seen[name] or 0) + 1
          local occ = seen[name]
          local key = name .. "\31" .. tostring(occ)
          local entry = present[key]
          if not entry then
            entry = { name = name, occ = occ, count = 0, key = fx_key(name, occ) }
            present[key] = entry
            order[#order + 1] = entry
          end
          entry.count = entry.count + 1
        end
      end
    end
  end
  table.sort(order, function(a, b)
    if a.name == b.name then return a.occ < b.occ end
    return a.name:lower() < b.name:lower()
  end)
  return order, total
end

local function entry_reference_fx(group, entry)
  for _, guid in ipairs(group.members) do
    local track = find_track_by_guid(guid)
    if track then
      local fxidx = find_nth_named_fx(track, entry.name, entry.occ)
      if fxidx then return track, fxidx end
    end
  end
  return nil
end

local function sync_one_fx(group, entry)
  local src_track, src_fx = resolve_fx_source(group, entry.name, entry.occ)
  if not (src_track and src_fx) then return 0 end
  local src_guid = track_guid(src_track)
  local src_params = r.TrackFX_GetNumParams(src_track, src_fx) or 0
  local synced = 0
  for _, guid in ipairs(group.members) do
    if guid ~= src_guid then
      local member = find_track_by_guid(guid)
      if member then
        local midx = find_nth_named_fx(member, entry.name, entry.occ)
        if midx then
          local member_params = r.TrackFX_GetNumParams(member, midx) or 0
          local limit = math.min(src_params, member_params)
          for param = 0, limit - 1 do
            if not is_param_excluded(group, entry.name, entry.occ, param) then
              local value = r.TrackFX_GetParamNormalized(src_track, src_fx, param)
              if value then r.TrackFX_SetParamNormalized(member, midx, param, value) end
            end
          end
          synced = synced + 1
        end
      end
    end
  end
  return synced
end

local function sync_fx_now(group, entry)
  if is_fx_excluded(group, entry.key) then return false, "FX is unlinked" end
  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)
  local synced = sync_one_fx(group, entry)
  r.PreventUIRefresh(-1)
  r.Undo_EndBlock("FX Groups: sync FX", -1)
  if synced == 0 then return false, "Nothing to sync for this FX" end
  return true, "Synced " .. entry.name .. " to " .. tostring(synced) .. " member(s)"
end

local function add_fx_to_group(group, payload)
  if not payload or payload == "" then return 0 end
  local added = 0
  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)
  for _, guid in ipairs(group.members) do
    local track = find_track_by_guid(guid)
    if track then
      local index = r.TrackFX_AddByName(track, payload, false, -1)
      if (not index or index < 0) and payload:lower():sub(-9) == ".rfxchain" then
        local basename = payload:match("([^/\\]+)$") or payload
        if basename ~= payload then index = r.TrackFX_AddByName(track, basename, false, -1) end
      end
      if index and index >= 0 then added = added + 1 end
    end
  end
  r.PreventUIRefresh(-1)
  r.Undo_EndBlock("FX Groups: add FX to group", -1)
  return added
end

function M.init(app)
  ensure_settings(app)
  state.project = current_project()
  state.groups = load_groups()
end

function M.update(app)
  refresh_project()
  local settings = app.settings and app.settings.fx_groups
  if not settings or settings.sync_paused then return end
  if #state.groups == 0 then return end
  if not r.GetLastTouchedFX then return end
  local ok, tracknumber, fxnumber, paramnumber = r.GetLastTouchedFX()
  if not ok then return end
  if not tracknumber or tracknumber < 1 then return end
  if not fxnumber or fxnumber < 0 then return end
  if (fxnumber & 0xFFFFFF) ~= fxnumber then return end
  local track = r.GetTrack(0, tracknumber - 1)
  if not track then return end
  local fx_count = r.TrackFX_GetCount(track) or 0
  if fxnumber >= fx_count then return end
  local num_params = r.TrackFX_GetNumParams(track, fxnumber) or 0
  if not paramnumber or paramnumber < 0 or paramnumber >= num_params then return end
  local src_guid = track_guid(track)
  if src_guid == "" then return end
  local active_groups = groups_with_member(src_guid, true)
  if #active_groups == 0 then return end
  local name = fx_name(track, fxnumber)
  if name == "" then return end
  local occ = occurrence_index(track, fxnumber, name)
  local value = r.TrackFX_GetParamNormalized(track, fxnumber, paramnumber)
  if not value then return end
  local sig = src_guid .. "|" .. name .. "|" .. tostring(occ) .. "|" .. tostring(paramnumber)
  if state.last_sig == sig and state.last_value == value then return end
  state.last_sig = sig
  state.last_value = value
  for _, group in ipairs(active_groups) do
    if not is_fx_excluded(group, fx_key(name, occ)) and not is_param_excluded(group, name, occ, paramnumber) then
      for _, guid in ipairs(group.members) do
        if guid ~= src_guid then
          local member = find_track_by_guid(guid)
          if member then
            local midx = find_nth_named_fx(member, name, occ)
            if midx then
              local member_params = r.TrackFX_GetNumParams(member, midx) or 0
              if paramnumber < member_params then
                local current = r.TrackFX_GetParamNormalized(member, midx, paramnumber)
                if not current or math.abs(current - value) > 1e-9 then
                  r.TrackFX_SetParamNormalized(member, midx, paramnumber, value)
                end
              end
            end
          end
        end
      end
    end
  end
end

local function draw_member_rows(ctx, app, group)
  local pending_remove = nil
  if #group.members == 0 then
    r.ImGui_TextColored(ctx, Theme.colors.text_dim, "No tracks yet.")
  end
  for _, guid in ipairs(group.members) do
    r.ImGui_PushID(ctx, "mem_" .. guid)
    if r.ImGui_SmallButton(ctx, "x") then pending_remove = guid end
    if r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then
      r.ImGui_SetTooltip(ctx, "Remove this track from the group")
    end
    r.ImGui_SameLine(ctx, 0, UIScale.gap(6))
    local track = find_track_by_guid(guid)
    if track then
      r.ImGui_Text(ctx, track_name(track))
    else
      r.ImGui_TextColored(ctx, Theme.colors.warning, "(missing in project)")
    end
    r.ImGui_PopID(ctx)
  end
  if r.ImGui_SmallButton(ctx, "+ Add selected tracks##fxg_add_sel") then
    local added = add_selected_tracks(group)
    if app then app.status = added > 0 and (tostring(added) .. " track(s) added") or "No new tracks selected" end
  end
  if r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then
    r.ImGui_SetTooltip(ctx, "Add the currently selected tracks to this group")
  end
  if pending_remove then remove_member(group, pending_remove) end
end

local function color_edit_flags()
  local flags = 0
  if r.ImGui_ColorEditFlags_NoInputs then flags = flags | r.ImGui_ColorEditFlags_NoInputs() end
  if r.ImGui_ColorEditFlags_NoLabel then flags = flags | r.ImGui_ColorEditFlags_NoLabel() end
  return flags
end

local function draw_group_list(ctx, app)
  local _, avail_h = r.ImGui_GetContentRegionAvail(ctx)
  local height = math.max(UIScale.round(90), math.floor((avail_h or UIScale.round(300)) * 0.4))
  local pending_delete = nil
  local del_flags = r.ImGui_ColorEditFlags_NoTooltip and r.ImGui_ColorEditFlags_NoTooltip() or 0
  if r.ImGui_BeginChild(ctx, "##fxg_list", 0, height, 1) then
    if #state.groups == 0 then
      r.ImGui_TextColored(ctx, Theme.colors.text_dim, "No groups yet. Click 'New group'.")
    end
    for _, group in ipairs(state.groups) do
      r.ImGui_PushID(ctx, "grp_" .. group.id)
      local expanded = state.expanded[group.id] == true
      local dir = (expanded and r.ImGui_Dir_Down and r.ImGui_Dir_Down()) or (r.ImGui_Dir_Right and r.ImGui_Dir_Right()) or 0
      if r.ImGui_ArrowButton(ctx, "##fxg_expand", dir) then
        state.expanded[group.id] = not expanded
      end
      if r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then
        r.ImGui_SetTooltip(ctx, "Show / hide tracks in this group")
      end
      r.ImGui_SameLine(ctx, 0, UIScale.gap(4))
      local active_changed, active_value = r.ImGui_Checkbox(ctx, "##fxg_active", group.link_active)
      if active_changed then
        group.link_active = active_value
        save_groups()
      end
      if r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then
        r.ImGui_SetTooltip(ctx, "Group active (live link on/off)")
      end
      r.ImGui_SameLine(ctx, 0, UIScale.gap(6))
      if r.ImGui_ColorEdit4 then
        local col_changed, col = r.ImGui_ColorEdit4(ctx, "##fxg_swatch", group.color, color_edit_flags())
        if col_changed then
          group.color = (col & 0xFFFFFF00) | 0xFF
          save_groups()
        end
        if r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then
          r.ImGui_SetTooltip(ctx, "Group color")
        end
      end
      r.ImGui_SameLine(ctx, 0, UIScale.gap(6))
      local del_size = UIScale.round(13)
      local row_avail = select(1, r.ImGui_GetContentRegionAvail(ctx))
      local sel_w = math.max(UIScale.round(40), row_avail - del_size - UIScale.gap(8))
      if state.editing_group_id == group.id then
        r.ImGui_SetNextItemWidth(ctx, sel_w)
        if state.editing_focus then
          r.ImGui_SetKeyboardFocusHere(ctx)
          state.editing_focus = false
        end
        local nm_changed, nm_value = r.ImGui_InputText(ctx, "##fxg_rename", group.name)
        if nm_changed then
          group.name = nm_value or ""
          save_groups()
        end
        if r.ImGui_IsItemDeactivated(ctx) then
          state.editing_group_id = nil
        end
      else
        local label = group.name .. "  (" .. tostring(#group.members) .. ")##sel"
        if r.ImGui_Selectable(ctx, label, state.selected_group_id == group.id, 0, sel_w) then
          state.selected_group_id = group.id
        end
        if r.ImGui_IsItemHovered(ctx) then
          if r.ImGui_SetTooltip then r.ImGui_SetTooltip(ctx, "Double-click to rename") end
          if r.ImGui_IsMouseDoubleClicked and r.ImGui_IsMouseDoubleClicked(ctx, 0) then
            state.editing_group_id = group.id
            state.editing_focus = true
          end
        end
      end
      r.ImGui_SameLine(ctx, 0, UIScale.gap(8))
      local danger = Theme.colors.danger or 0xE0534FFF
      if r.ImGui_ColorButton and r.ImGui_ColorButton(ctx, "##fxg_del", danger, del_flags, del_size, del_size) then
        pending_delete = group
      end
      if r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then
        r.ImGui_SetTooltip(ctx, "Delete this group")
      end
      if expanded then
        local indent = UIScale.gap(18)
        r.ImGui_Indent(ctx, indent)
        draw_member_rows(ctx, app, group)
        r.ImGui_Unindent(ctx, indent)
      end
      r.ImGui_PopID(ctx)
    end
    r.ImGui_EndChild(ctx)
  end
  if pending_delete then
    delete_group(pending_delete)
    app.status = "Group deleted"
  end
end

local function set_all_fx_linked(group, linked)
  group.excluded = {}
  if not linked then
    local list = group_linked_fx(group)
    for _, entry in ipairs(list) do
      if entry.count >= 2 then group.excluded[#group.excluded + 1] = entry.key end
    end
  end
  save_groups()
end

local function set_all_params_linked(group, entry, count, linked)
  local prefix = param_key(entry.name, entry.occ, "")
  local kept = {}
  for _, k in ipairs(group.param_excluded or {}) do
    if k:sub(1, #prefix) ~= prefix then kept[#kept + 1] = k end
  end
  if not linked then
    for p = 0, (count or 0) - 1 do kept[#kept + 1] = param_key(entry.name, entry.occ, p) end
  end
  group.param_excluded = kept
  save_groups()
end

local function draw_linked_fx(ctx, app, group, height)
  local fx_list, total_members = group_linked_fx(group)
  local visible = {}
  for _, entry in ipairs(fx_list) do
    if entry.count >= 2 or is_fx_excluded(group, entry.key) then
      visible[#visible + 1] = entry
    end
  end
  if r.ImGui_SmallButton(ctx, "Link all##fxg_linkall") then set_all_fx_linked(group, true) end
  r.ImGui_SameLine(ctx, 0, UIScale.gap(6))
  if r.ImGui_SmallButton(ctx, "Unlink all##fxg_unlinkall") then set_all_fx_linked(group, false) end
  if r.ImGui_BeginChild(ctx, "##fxg_linked", 0, height or 0, 0) then
    if total_members == 0 then
      r.ImGui_TextColored(ctx, Theme.colors.text_dim, "No tracks in this group yet.")
    elseif #visible == 0 then
      r.ImGui_TextColored(ctx, Theme.colors.text_dim, "No FX shared across members.")
    else
      for index, entry in ipairs(visible) do
        r.ImGui_PushID(ctx, "lfx_" .. tostring(index))
        local excluded = is_fx_excluded(group, entry.key)
        local toggle_changed, toggle_value = r.ImGui_Checkbox(ctx, "##fxg_link_toggle", not excluded)
        if toggle_changed then set_fx_excluded(group, entry.key, not toggle_value) end
        if r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then
          r.ImGui_SetTooltip(ctx, "Link this FX within the group")
        end
        r.ImGui_SameLine(ctx, 0, UIScale.gap(6))
        local label = entry.name
        if entry.occ > 1 then label = label .. " #" .. tostring(entry.occ) end
        local count_text = "  (" .. tostring(entry.count) .. "/" .. tostring(total_members) .. ")"
        if excluded then
          r.ImGui_TextColored(ctx, Theme.colors.text_dim, label .. count_text .. "  unlinked")
        elseif entry.count == total_members then
          r.ImGui_Text(ctx, label .. count_text)
        else
          r.ImGui_Text(ctx, label .. count_text)
          r.ImGui_SameLine(ctx, 0, UIScale.gap(6))
          r.ImGui_TextColored(ctx, Theme.colors.warning, "partial")
        end
        if not excluded then
          if r.ImGui_SmallButton(ctx, "SYNC##fxg_syncfx") then
            local _, message = sync_fx_now(group, entry)
            app.status = message
          end
          if r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then
            r.ImGui_SetTooltip(ctx, "Copy this FX's parameter values from the source track to all other members now.\nExcluded parameters are skipped.")
          end
          if r.ImGui_BeginCombo then
            r.ImGui_SameLine(ctx, 0, UIScale.gap(6))
            r.ImGui_TextColored(ctx, Theme.colors.text_dim, "to")
            r.ImGui_SameLine(ctx, 0, UIScale.gap(6))
            local pinned = group.fx_master and group.fx_master[entry.key]
            local has_pin = pinned and member_has(group, pinned)
            local src_track = resolve_fx_source(group, entry.name, entry.occ)
            local src_label = src_track and track_name(src_track) or "?"
            local preview = has_pin and src_label or ("Auto (" .. src_label .. ")")
            r.ImGui_SetNextItemWidth(ctx, -1)
            if r.ImGui_BeginCombo(ctx, "##fxg_srcmaster", preview) then
              if r.ImGui_Selectable(ctx, "Auto", not has_pin) then
                set_fx_master(group, entry.key, nil)
              end
              for _, opt in ipairs(members_with_fx(group, entry.name, entry.occ)) do
                local selected = pinned == opt.guid
                if r.ImGui_Selectable(ctx, track_name(opt.track) .. "##src_" .. opt.guid, selected) then
                  set_fx_master(group, entry.key, opt.guid)
                end
              end
              r.ImGui_EndCombo(ctx)
            end
            if r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then
              r.ImGui_SetTooltip(ctx, "Source track to copy this FX's parameters from")
            end
          end
        end
        if not excluded and r.ImGui_TreeNode then
          if r.ImGui_TreeNode(ctx, "Parameters##fxg_params") then
            local ref_track, ref_fx = entry_reference_fx(group, entry)
            if ref_track and ref_fx then
              local nparams = r.TrackFX_GetNumParams(ref_track, ref_fx) or 0
              if r.ImGui_SmallButton(ctx, "All##fxg_pall") then set_all_params_linked(group, entry, nparams, true) end
              r.ImGui_SameLine(ctx, 0, UIScale.gap(6))
              if r.ImGui_SmallButton(ctx, "None##fxg_pnone") then set_all_params_linked(group, entry, nparams, false) end
              for param = 0, nparams - 1 do
                r.ImGui_PushID(ctx, "p_" .. tostring(param))
                local _, pname = r.TrackFX_GetParamName(ref_track, ref_fx, param, "")
                if not pname or pname == "" then pname = "Param " .. tostring(param) end
                local p_excluded = is_param_excluded(group, entry.name, entry.occ, param)
                local p_changed, p_value = r.ImGui_Checkbox(ctx, pname .. "##fxg_param", not p_excluded)
                if p_changed then set_param_excluded(group, entry.name, entry.occ, param, not p_value) end
                r.ImGui_PopID(ctx)
              end
            else
              r.ImGui_TextColored(ctx, Theme.colors.text_dim, "FX not found on members.")
            end
            r.ImGui_TreePop(ctx)
          end
        end
        r.ImGui_PopID(ctx)
      end
    end
    r.ImGui_EndChild(ctx)
  end
end

local function draw_group_details(ctx, app, settings)
  local group = selected_group()
  if not group then
    r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Select a group to edit.")
    return
  end
  r.ImGui_PushID(ctx, "details_" .. group.id)

  r.ImGui_TextColored(ctx, Theme.colors.accent, "Linked FX")
  r.ImGui_SameLine(ctx, 0, UIScale.gap(8))
  if r.ImGui_SmallButton(ctx, "+ Add FX...##fxg_addfx_btn") then
    local target = group
    QuickFX.request_open(function(payload)
      local added = add_fx_to_group(target, payload)
      app.status = added > 0 and ("FX added to " .. tostring(added) .. " track(s)") or "FX not added"
    end)
  end
  if r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then
    r.ImGui_SetTooltip(ctx, "Add an FX to every track in this group")
  end
  draw_linked_fx(ctx, app, group, 0)

  r.ImGui_PopID(ctx)
end

function M.draw(app)
  local ctx = app.ctx
  local settings = ensure_settings(app)
  refresh_project()

  r.ImGui_TextColored(ctx, Theme.colors.accent, "FX Groups")
  r.ImGui_SameLine(ctx, 0, UIScale.gap(10))
  if r.ImGui_Button(ctx, "New group##fxg_new") then
    create_group()
    app.status = "Group created"
  end
  r.ImGui_SameLine(ctx, 0, UIScale.gap(10))
  local paused_changed, paused_value = r.ImGui_Checkbox(ctx, "Sync paused##fxg_pause", settings.sync_paused == true)
  if paused_changed then
    settings.sync_paused = paused_value
    if app.save_settings then app.save_settings() end
  end
  r.ImGui_Separator(ctx)

  draw_group_list(ctx, app)
  r.ImGui_Separator(ctx)
  draw_group_details(ctx, app, settings)

  QuickFX.draw(ctx)
end

return M
