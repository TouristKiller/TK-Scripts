-- @description TK FX SLOTS MANAGER
-- @author TouristKiller
-- @version 0.0.3
-- @changelog:
--[[     
++ INITIAL LAUNCH FOR TESTING

== THNX TO MASTER SEXAN FOR HIS FX PARSER ==

]]--        
--------------------------------------------------------------------------



local SCRIPT_NAME = 'TK FX Slots Manager'
local r = reaper

if not r or not r.ImGui_CreateContext then
  r.MB('ReaImGui extension is required. Please install "ReaImGui: Dear ImGui bindings for ReaScript" via ReaPack.', SCRIPT_NAME, 0)
  return
end

local ctx = r.ImGui_CreateContext(SCRIPT_NAME)

if r.ImGui_StyleColorsDark then
  local ok = pcall(function() r.ImGui_StyleColorsDark(ctx) end)
  if not ok then pcall(r.ImGui_StyleColorsDark) end
end

local function flag(val)
  local t = type(val)
  if t == 'function' then
    local ok, res = pcall(val)
    if ok and type(res) == 'number' then return res end
  elseif t == 'number' then
    return val
  end
  return 0
end

local FLAGS = {
  Window_MenuBar            = flag(r.ImGui_WindowFlags_MenuBar),
  Table_SizingStretchProp   = flag(r.ImGui_TableFlags_SizingStretchProp),
  Col_WidthFixed            = flag(r.ImGui_TableColumnFlags_WidthFixed),
  Col_WidthStretch          = flag(r.ImGui_TableColumnFlags_WidthStretch),
  Cond_Appearing            = flag(r.ImGui_Cond_Appearing),
}

local function enum(val)
  local t = type(val)
  if t == 'function' then
    local ok, res = pcall(val)
    if ok and type(res) == 'number' then return res end
  elseif t == 'number' then
    return val
  end
  return nil
end

local ENUM = {
  Col_Text = enum(r.ImGui_Col_Text),
  StyleVar_FramePadding = enum(r.ImGui_StyleVar_FramePadding),
  Col_Header = enum(r.ImGui_Col_Header),
  Col_HeaderHovered = enum(r.ImGui_Col_HeaderHovered),
  Col_HeaderActive = enum(r.ImGui_Col_HeaderActive),
}

local HAVE_StyleVar_FramePadding = ENUM.StyleVar_FramePadding ~= nil
local HAVE_PushStyleColor = (r.ImGui_PushStyleColor ~= nil) and (ENUM.Col_Text ~= nil)

local function push_text_color(red, green, blue, alpha)
  if not HAVE_PushStyleColor then return false end
  if r.ImGui_ColorConvertDouble4ToU32 then
    local col = r.ImGui_ColorConvertDouble4ToU32(red, green, blue, alpha)
    local ok = pcall(r.ImGui_PushStyleColor, ctx, ENUM.Col_Text, col)
    if ok then return true end
  end
  local ok = pcall(r.ImGui_PushStyleColor, ctx, ENUM.Col_Text, red, green, blue, alpha)
  return ok and true or false
end

local function push_style_color(idx, red, green, blue, alpha)
  if not HAVE_PushStyleColor or not idx then return false end
  if r.ImGui_ColorConvertDouble4ToU32 then
    local col = r.ImGui_ColorConvertDouble4ToU32(red, green, blue, alpha)
    local ok = pcall(r.ImGui_PushStyleColor, ctx, idx, col)
    if ok then return true end
  end
  local ok = pcall(r.ImGui_PushStyleColor, ctx, idx, red, green, blue, alpha)
  return ok and true or false
end

local function SeparatorText(label)
  if r.ImGui_SeparatorText then
    r.ImGui_SeparatorText(ctx, label)
  else
    r.ImGui_Text(ctx, label)
    r.ImGui_Separator(ctx)
  end
end

local function ensure_ctx()
  if not ctx then
    ctx = r.ImGui_CreateContext(SCRIPT_NAME)
    if r.ImGui_StyleColorsDark then pcall(function() r.ImGui_StyleColorsDark(ctx) end) end
  end
end

local function recreate_ctx()
  if r.ImGui_DestroyContext and ctx then pcall(r.ImGui_DestroyContext, ctx) end
  ctx = r.ImGui_CreateContext(SCRIPT_NAME)
  if r.ImGui_StyleColorsDark then pcall(function() r.ImGui_StyleColorsDark(ctx) end) end
end

local function safe_call(f)
  local ok, a, b, c = pcall(f)
  if ok then return true, a, b, c end
  local err = tostring(a)
  if err:find('valid ImGui_Context', 1, true) then
    recreate_ctx()
    return pcall(f)
  end
  return false, a
end

local function safe_SetNextWindowSize(w, h, cond)
  safe_call(function() return r.ImGui_SetNextWindowSize(ctx, w, h, cond) end)
end

local function safe_Begin(title, open, flags)
  local ok, v, o = safe_call(function() return r.ImGui_Begin(ctx, title, open, flags) end)
  if not ok then return false, nil, nil end
  return true, v, o
end

local FX_END = 0x7fffffff 

local state                 = {
  scopeSelectedOnly         = false, 
  filter                    = '',
  replaceWith               = '',
  insertOverride            = true,    
  insertPos                 = 'in_place',   
  insertIndex               = 0,          
  selectedSourceFXName      = nil,
  showOnlyTracksWithFX      = false,
  pendingMessage            = '',
  pendingError              = '',
  autoRefresh               = true,
  lastRefreshTime           = 0,
  refreshInterval           = 0.5,
  pendingJob                = nil,   
  jobDelayFrames            = 0,    
  gotoTrackInput            = 1,     
  scrollToTrackNum          = nil,   

  -- Sexan parser (Goran rules!!)
  pluginList                = nil,
  showPicker                = false,
  pickerFilter              = '',
  replaceDisplay            = '',
  favs                      = {},
  dragging                  = nil,
}

local model = {
  tracks = {},
}

local function favs_save()
  local buf = {}
  for i, it in ipairs(state.favs or {}) do
    buf[#buf+1] = (it.addname or '') .. "\t" .. (it.display or it.addname or '')
  end
  r.SetExtState('TK_FX_SLOTS', 'FAVS', table.concat(buf, "\n"), true)
end

local function favs_load()
  state.favs = {}
  local s = r.GetExtState('TK_FX_SLOTS', 'FAVS') or ''
  if s == '' then return end
  for line in string.gmatch(s, '([^\n]+)') do
    local add, disp = line:match('^(.-)\t(.*)$')
    add = add or line
    disp = disp or add
    if add ~= '' then state.favs[#state.favs+1] = { addname = add, display = disp } end
  end
end

local function favs_has(addname)
  for _, it in ipairs(state.favs or {}) do if it.addname == addname then return true end end
  return false
end

local function favs_add(addname, display)
  if addname and addname ~= '' and not favs_has(addname) then
    state.favs[#state.favs+1] = { addname = addname, display = display or addname }
    favs_save()
    state.pendingMessage = 'Added to short list'
  end
end

local function favs_remove(addname)
  for i = #state.favs, 1, -1 do
    if state.favs[i].addname == addname then table.remove(state.favs, i) end
  end
  favs_save()
  state.pendingMessage = 'Removed from short list'
end

local function printf(fmt, ...)
  r.ShowConsoleMsg(string.format(fmt, ...))
end
local function file_exists(path)
  local f = io.open(path, 'r')
  if f then f:close() return true end
  return false
end

-- Sexan FX Parser integration -------------------------------------------
local function ensure_sexan_parser()
  local fx_parser = r.GetResourcePath() .. '/Scripts/Sexan_Scripts/FX/Sexan_FX_Browser_ParserV7.lua'
  if file_exists(fx_parser) then
    local ok, err = pcall(dofile, fx_parser)
    if not ok then
      state.pendingError = 'Sexan parser error: ' .. tostring(err)
      return false
    end
    return true
  else
    if r.ReaPack_BrowsePackages then
      r.ShowMessageBox('Sexan FX Browser Parser V7 is missing. Opening ReaPack to install.', SCRIPT_NAME, 0)
      r.ReaPack_BrowsePackages('"sexan fx browser parser v7"')
    else
      state.pendingError = 'Sexan FX Browser Parser V7 not found. Please install via ReaPack.'
    end
    return false
  end
end

local function extract_fx_entry(entry)
  local t = type(entry)
  if t == 'string' then return entry, entry end
  if t == 'table' then
    local name = entry.name or entry.fxname or entry.fxName or entry.fname or entry.FX_NAME or entry[1]
    local add  = entry.addname or entry.fullname or entry.name or entry.fxname or entry[2] or name
    if name or add then
      return tostring(name or add), tostring(add or name)
    end
  end
  return nil, nil
end

local function flatten_plugins(obj, items, seen, depth)
  if depth > 6 then return end
  local t = type(obj)
  if t == 'table' then
  
    local disp, add = extract_fx_entry(obj)
    if disp and add then
      if not seen[add] then
        items[#items+1] = { display = disp, addname = add }
        seen[add] = true
      end
    end
    for k, v in pairs(obj) do
      if type(v) == 'table' or type(v) == 'string' then
        flatten_plugins(v, items, seen, depth + 1)
      end
    end
  elseif t == 'string' then
    if not seen[obj] then
      items[#items+1] = { display = obj, addname = obj }
      seen[obj] = true
    end
  end
end

local function load_plugin_list()
  state.pluginList, state.pluginItems = nil, nil
  if not ensure_sexan_parser() then return end
  local list
  if type(GetFXTbl) == 'function' then
    local ok, res = pcall(GetFXTbl)
    if ok then list = res end
  end
  if not list and type(ReadFXFile) == 'function' then
    local FX_LIST, CAT_TEST, FX_DEV_LIST_FILE = ReadFXFile()
    if (not FX_LIST or not CAT_TEST or not FX_DEV_LIST_FILE) and type(MakeFXFiles) == 'function' then
      FX_LIST, CAT_TEST, FX_DEV_LIST_FILE = MakeFXFiles()
    end
    if type(GetFXTbl) == 'function' then
      local ok, res = pcall(GetFXTbl)
      if ok then list = res end
    end
  end
  if not list then
    state.pendingError = 'Could not load plugin list from Sexan parser.'
    return
  end
  state.pluginList = list
  local items, seen = {}, {}
  flatten_plugins(list, items, seen, 0)
  table.sort(items, function(a,b) return tostring(a.display):lower() < tostring(b.display):lower() end)
  state.pluginItems = items
end

local function draw_plugin_picker()
  if not state.showPicker then return end
  if not state.pluginItems then
    load_plugin_list()
  end
  ensure_ctx()
  safe_SetNextWindowSize(520, 600, FLAGS.Cond_Appearing)
  local begunPicker, visible, open = safe_Begin('Choose plugin (Sexan parser)', true, FLAGS.Window_MenuBar)
  if visible then
    r.ImGui_Text(ctx, 'Search and select a plugin to use as replacement:')
    r.ImGui_SetNextItemWidth(ctx, 300)
    local chg, txt = r.ImGui_InputText(ctx, 'Filter##picker', state.pickerFilter)
    if chg then state.pickerFilter = txt end
    local childVisible = r.ImGui_BeginChild(ctx, 'picker_list', 0, -32, 0)
    if childVisible then
      local filter = (state.pickerFilter or ''):lower()
      local shown = 0
      local idx = 0
      for _, it in ipairs(state.pluginItems or {}) do
        if filter == '' or tostring(it.display):lower():find(filter, 1, true) then
          idx = idx + 1
          if r.ImGui_SmallButton(ctx, '+##pick' .. idx) then
            favs_add(it.addname, tostring(it.display))
          end
          r.ImGui_SameLine(ctx)
          if r.ImGui_Selectable(ctx, it.display, false) then
            state.replaceWith = it.addname
            state.replaceDisplay = tostring(it.display)
            state.pendingMessage = 'Chosen: ' .. state.replaceDisplay
            state.showPicker = false
            break
          end
          shown = shown + 1
        end
        if shown > 2000 then
          break
        end
      end
    end
    r.ImGui_EndChild(ctx)
    if r.ImGui_Button(ctx, 'Close') then
      state.showPicker = false
    end
  end
  if begunPicker then r.ImGui_End(ctx) end
end

local function getProjectTimeSec()
  return r.time_precise and r.time_precise() or (r.time_precise and r.time_precise() or os.clock())
end

local function get_track_name(tr)
  local retval, name = r.GetTrackName(tr)
  if not retval then return '(track)'
  else return name end
end

local function get_fx_name(track, fx)
  local rv, buf = r.TrackFX_GetFXName(track, fx, '')
  if rv then return buf else return ("FX %d"):format(fx+1) end
end

local function tracks_iter(selectedOnly)
  local count = selectedOnly and r.CountSelectedTracks(0) or r.CountTracks(0)
  local i = 0
  return function()
    if i >= count then return nil end
    local tr = selectedOnly and r.GetSelectedTrack(0, i) or r.GetTrack(0, i)
    i = i + 1
    return tr, i-1
  end
end

local function rebuild_model()
  model.tracks = {}
  for tr, ti in tracks_iter(state.scopeSelectedOnly) do
  local fxCount = r.TrackFX_GetCount(tr)
  state.forceHeaders = nil
    if (not state.showOnlyTracksWithFX) or fxCount > 0 then
      local fxList = {}
      for fx = 0, fxCount-1 do
        local name = get_fx_name(tr, fx)
        local enabled = r.TrackFX_GetEnabled(tr, fx)
        table.insert(fxList, { idx = fx, name = name, enabled = enabled })
      end
      local guid = r.GetTrackGUID and r.GetTrackGUID(tr) or nil
      table.insert(model.tracks, { track = tr, guid = guid, idx = ti, name = get_track_name(tr), fxList = fxList })
    end
  end
end


local function resolve_track_entry(trEntry)
  if not trEntry then return nil end
  local tr = trEntry.track
  local ok = pcall(function() return r.GetTrackGUID and r.GetTrackGUID(tr) or nil end)
  if not ok or tr == nil then
    if trEntry.guid and find_track_by_guid then
      local ntr = find_track_by_guid(trEntry.guid)
      trEntry.track = ntr
      return ntr
    else
      return nil
    end
  end
  return tr
end

local function toggle_bypass(track, fx)
  if not track then return end
  local ok, _ = pcall(function() return r.TrackFX_GetEnabled(track, fx) end)
  if not ok then state.pendingError = 'Track missing for bypass'; return end
  local enabled = r.TrackFX_GetEnabled(track, fx)
  r.TrackFX_SetEnabled(track, fx, not enabled)
end

local function delete_fx(track, fx)
  if not track then return end
  local ok = pcall(function() r.TrackFX_Delete(track, fx) end)
  if not ok then state.pendingError = 'Track missing for delete' end
end

local function move_fx(track, fromIdx, toIdx)
  if fromIdx == toIdx then return end
  if not track then return end
  local fxCount = r.TrackFX_GetCount(track)
  if fromIdx < 0 or fromIdx >= fxCount then return end
  if toIdx < 0 then toIdx = 0 end
  if toIdx >= fxCount then toIdx = FX_END end
  r.TrackFX_CopyToTrack(track, fromIdx, track, toIdx, true)
end

local function find_track_by_guid(guid)
  if not guid or guid == '' then return nil end
  local cnt = r.CountTracks(0)
  for i = 0, cnt - 1 do
    local tr = r.GetTrack(0, i)
    local g = r.GetTrackGUID and r.GetTrackGUID(tr)
    if g == guid then return tr end
  end
  return nil
end

local function add_fx_at(track, fxName, atIdx)
  if not track then return -1 end
  local fxIndex = r.TrackFX_AddByName(track, fxName, false, -1) 
  if fxIndex < 0 then return -1 end
  if atIdx == nil or atIdx == FX_END then return fxIndex end
  r.TrackFX_CopyToTrack(track, fxIndex, track, atIdx, true)
  return atIdx
end

local function replace_fx_at(track, fxIdx, fxName, overridePos, newPos)
  if not track then return false, 'Track missing' end
  local placeIdx = fxIdx
  if overridePos then
    if newPos == 'end' then
      placeIdx = FX_END
    elseif newPos == 'begin' then
      placeIdx = 0
    elseif newPos == 'index' then
      placeIdx = math.max(0, tonumber(state.insertIndex) or 0)
    else
      placeIdx = fxIdx 
    end
  end
  local originalIdx = fxIdx
  local fxCountBefore = r.TrackFX_GetCount(track)
  if originalIdx < 0 or originalIdx >= fxCountBefore then return false, 'Invalid FX index' end

  r.TrackFX_Delete(track, originalIdx)
  local newIdx = r.TrackFX_AddByName(track, fxName, false, -1)
  if newIdx < 0 then
    return false, ('FX "%s" not found'):format(fxName)
  end
  if placeIdx == FX_END then
    r.TrackFX_CopyToTrack(track, newIdx, track, FX_END, true)
  elseif placeIdx == 0 then
    r.TrackFX_CopyToTrack(track, newIdx, track, 0, true)
  elseif placeIdx == originalIdx then
    r.TrackFX_CopyToTrack(track, newIdx, track, originalIdx, true)
  else
    r.TrackFX_CopyToTrack(track, newIdx, track, placeIdx, true)
  end
  return true
end

local function replace_all_instances(sourceName, replacementName)
  if not sourceName or sourceName == '' then return 0, 'No source FX selected' end
  if not replacementName or replacementName == '' then return 0, 'No replacement FX specified' end
  local replaced = 0
  r.Undo_BeginBlock()
  for tr, _ in tracks_iter(state.scopeSelectedOnly) do
    local fxCount = r.TrackFX_GetCount(tr)
    local toReplace = {}
    for i = 0, fxCount-1 do
      local name = get_fx_name(tr, i)
      if name == sourceName then table.insert(toReplace, i) end
    end
    table.sort(toReplace, function(a,b) return a>b end)
    for _, idx in ipairs(toReplace) do
      local ok, err = replace_fx_at(tr, idx, replacementName, state.insertOverride, state.insertPos)
      if ok then replaced = replaced + 1 else state.pendingError = err end
    end
  end
  r.Undo_EndBlock(('Replace all "%s" with "%s"'):format(sourceName, replacementName), -1)
  return replaced
end

local function draw_scope_row()
  local changed
  changed, state.scopeSelectedOnly = r.ImGui_Checkbox(ctx, 'Selected tracks only', state.scopeSelectedOnly)
  r.ImGui_SameLine(ctx)
  changed, state.showOnlyTracksWithFX = r.ImGui_Checkbox(ctx, 'Hide empty tracks', state.showOnlyTracksWithFX)
  r.ImGui_SameLine(ctx)
  changed, state.autoRefresh = r.ImGui_Checkbox(ctx, 'Auto refresh', state.autoRefresh)
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, 'Refresh') then rebuild_model() end
end
local function draw_replace_panel()
  SeparatorText('Replace')
  if state.selectedSourceFXName then
    r.ImGui_Text(ctx, 'Selected source FX: ' .. state.selectedSourceFXName)
  else
    r.ImGui_Text(ctx, 'First pick a source FX (press "Source" in the list below)')
  end
  r.ImGui_Text(ctx, 'Placement:')
  local sel = state.insertPos
  if r.ImGui_RadioButton(ctx, 'Same slot', sel == 'in_place') then state.insertPos = 'in_place' end
  r.ImGui_SameLine(ctx)
  if r.ImGui_RadioButton(ctx, 'Start', sel == 'begin') then state.insertPos = 'begin' end
  r.ImGui_SameLine(ctx)
  if r.ImGui_RadioButton(ctx, 'End', sel == 'end') then state.insertPos = 'end' end
  r.ImGui_SameLine(ctx)
  if r.ImGui_RadioButton(ctx, 'Index', sel == 'index') then state.insertPos = 'index' end
  if state.insertPos == 'index' then
    r.ImGui_SameLine(ctx)
    r.ImGui_SetNextItemWidth(ctx, 80)
    local changed2, val = r.ImGui_InputInt(ctx, 'Slot (1-based)', (tonumber(state.insertIndex) or 0) + 1)
    if changed2 then state.insertIndex = math.max(0, (tonumber(val) or 1) - 1) end
  end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, 'Pick from list…') then state.showPicker = true end
  local bw, bh = r.ImGui_GetItemRectSize(ctx)
  r.ImGui_SameLine(ctx)
  r.ImGui_SetNextItemWidth(ctx, bw)
  local preview = (state.replaceDisplay ~= '' and state.replaceDisplay) or 'Short list'
  if r.ImGui_BeginCombo(ctx, '##shortlist', preview) then
    local del_key
    for i, it in ipairs(state.favs or {}) do
      if r.ImGui_Selectable(ctx, tostring(it.display), false) then
        state.replaceWith = it.addname
        state.replaceDisplay = tostring(it.display)
        state.pendingMessage = 'Chosen: ' .. state.replaceDisplay
      end
      r.ImGui_SameLine(ctx)
      if r.ImGui_SmallButton(ctx, ('x##dropfav%d'):format(i)) then del_key = it.addname end
    end
    if del_key then favs_remove(del_key) end
    r.ImGui_EndCombo(ctx)
  end
  if r.ImGui_Button(ctx, 'Replace all instances') then
    local count = 0
    count = select(1, replace_all_instances(state.selectedSourceFXName, state.replaceWith))
    state.pendingMessage = ('%d instances replaced.'):format(count)
    rebuild_model()
  end
end

local function draw_track_fx_rows(trEntry)
  local tr = resolve_track_entry(trEntry)
  if not tr then
    r.ImGui_Text(ctx, '[Track missing]')
    return
  end

  if r.ImGui_BeginTable(ctx, ('fx_table_%p'):format(tr), 5, FLAGS.Table_SizingStretchProp) then
    r.ImGui_TableSetupColumn(ctx, '#', FLAGS.Col_WidthFixed, 30)
    r.ImGui_TableSetupColumn(ctx, 'FX name', FLAGS.Col_WidthStretch)
    r.ImGui_TableSetupColumn(ctx, 'Byp/Offl', FLAGS.Col_WidthFixed, 90)
    r.ImGui_TableSetupColumn(ctx, 'Actions', FLAGS.Col_WidthFixed, 200)
    r.ImGui_TableSetupColumn(ctx, 'Source', FLAGS.Col_WidthFixed, 50)
    r.ImGui_TableHeadersRow(ctx)

    local filter = state.filter
    for i, fx in ipairs(trEntry.fxList) do
      if filter == '' or string.find(string.lower(fx.name), string.lower(filter), 1, true) then
        r.ImGui_TableNextRow(ctx)

        r.ImGui_TableSetColumnIndex(ctx, 0)
        r.ImGui_Text(ctx, tostring(fx.idx + 1))
       
         do
          local dndType = 'TK_FXIDX'
          local trackId = (r.GetTrackGUID and r.GetTrackGUID(tr)) or tostring(tr)
          if r.ImGui_BeginDragDropTarget(ctx) then
            local p1, p2 = r.ImGui_AcceptDragDropPayload(ctx, dndType)
            local payload = nil
            if type(p1) == 'string' then
              payload = p1
            elseif (p1 == true or p1 == 1) and type(p2) == 'string' then
              payload = p2
            end
            if payload then
              local dest = fx.idx
              local pid, srcStr = payload:match('^(.-)|(.+)$')
              local srcIdx = nil
              if pid and srcStr then
                srcIdx = tonumber(srcStr)
              else
                srcIdx = tonumber(payload)
                pid = trackId 
              end
              if srcIdx ~= nil then
    local sameTrack = (pid == trackId)
    local toIdx = (sameTrack and srcIdx < dest) and (dest + 1) or dest
  state.pendingMessage = 'Placing FX...'
    state.pendingJob = { srcGuid = pid, srcIdx = srcIdx, destGuid = trackId, destIdx = toIdx, remove = sameTrack }
    state.jobDelayFrames = 1
              end
            end
            r.ImGui_EndDragDropTarget(ctx)
          end
        end

        r.ImGui_TableSetColumnIndex(ctx, 1)
        local _sel = false
        local label = ("%s##fx%d"):format(fx.name, fx.idx)
  r.ImGui_Selectable(ctx, label, _sel)
    local dndType = 'TK_FXIDX' 
    local trackId = (r.GetTrackGUID and r.GetTrackGUID(tr)) or tostring(tr)
    local canDrag = (r.ImGui_IsItemActive and r.ImGui_IsItemActive(ctx)) or (r.ImGui_IsItemClicked and r.ImGui_IsItemClicked(ctx)) or (r.ImGui_IsItemHovered and r.ImGui_IsItemHovered(ctx))
  if canDrag and r.ImGui_BeginDragDropSource(ctx, 0) then
          r.ImGui_SetDragDropPayload(ctx, dndType, trackId .. '|' .. tostring(fx.idx))
          r.ImGui_Text(ctx, ("Move: %s"):format(fx.name))
          r.ImGui_EndDragDropSource(ctx)
        end
        if r.ImGui_BeginDragDropTarget(ctx) then
          do
            local dl = r.ImGui_GetWindowDrawList(ctx)
            local x1, y1 = r.ImGui_GetItemRectMin(ctx)
            local x2, y2 = r.ImGui_GetItemRectMax(ctx)
            r.ImGui_DrawList_AddRectFilled(dl, x1, y1, x1 + 3, y2, 0x20FFFFFF)
          end
          local p1, p2 = r.ImGui_AcceptDragDropPayload(ctx, dndType)
          local payload = nil
          if type(p1) == 'string' then
            payload = p1
          elseif (p1 == true or p1 == 1) and type(p2) == 'string' then
            payload = p2
          end
          if payload then
            local dest = fx.idx
            local pid, srcStr = payload:match('^(.-)|(.+)$')
            local srcIdx = nil
            if pid and srcStr then
              srcIdx = tonumber(srcStr)
            else
              srcIdx = tonumber(payload)
              pid = trackId
            end
            if srcIdx ~= nil then
      local sameTrack = (pid == trackId)
      local toIdx = (sameTrack and srcIdx < dest) and (dest + 1) or dest
  state.pendingMessage = 'Placing FX...'
      state.pendingJob = { srcGuid = pid, srcIdx = srcIdx, destGuid = trackId, destIdx = toIdx, remove = sameTrack }
      state.jobDelayFrames = 1
            end
          end
          r.ImGui_EndDragDropTarget(ctx)
        end

        r.ImGui_TableSetColumnIndex(ctx, 2)
        local btnLabel = fx.enabled and 'On' or 'Off'
        if r.ImGui_SmallButton(ctx, btnLabel .. '##b' .. i) then
          r.Undo_BeginBlock()
          toggle_bypass(tr, fx.idx)
          r.Undo_EndBlock('Toggle FX bypass', -1)
          rebuild_model()
        end
        r.ImGui_SameLine(ctx)
        local is_offline = r.TrackFX_GetOffline(tr, fx.idx)
        local offLabel = is_offline and 'Ofl' or 'Onl'
        if r.ImGui_SmallButton(ctx, offLabel .. '##o' .. i) then
          r.Undo_BeginBlock()
          r.TrackFX_SetOffline(tr, fx.idx, not is_offline)
          r.Undo_EndBlock('Toggle FX offline', -1)
          rebuild_model()
        end

        r.ImGui_TableSetColumnIndex(ctx, 3)
        if r.ImGui_SmallButton(ctx, 'Del##' .. i) then
          r.Undo_BeginBlock()
          delete_fx(tr, fx.idx)
          r.Undo_EndBlock('Delete FX', -1)
          rebuild_model()
        end
        r.ImGui_SameLine(ctx)
        if r.ImGui_SmallButton(ctx, 'Replace..##' .. i) then
          if state.replaceWith ~= '' then
            r.Undo_BeginBlock()
            local ok, err = replace_fx_at(tr, fx.idx, state.replaceWith, true, state.insertPos)
            r.Undo_EndBlock('Replace FX', -1)
            if not ok then state.pendingError = err end
            rebuild_model()
          else
            state.pendingError = 'Please pick a replacement plugin (use "Pick from list…").'
          end
        end

        r.ImGui_TableSetColumnIndex(ctx, 4)
        if r.ImGui_SmallButton(ctx, 'Source##' .. i) then
          state.selectedSourceFXName = fx.name
        end
      end
    end

    r.ImGui_EndTable(ctx)
  end
end

function draw_tracks_panel()
  local filter = tostring(state.filter or '')
  local fl = filter ~= '' and string.lower(filter) or ''
  local shown = 0
  local missingFound = false
  for _, trEntry in ipairs(model.tracks) do
    local trOK = resolve_track_entry(trEntry)
    if not trOK then
      missingFound = true
      goto continue_track
    end
    if fl ~= '' then
      local hasMatch = false
      for _, fx in ipairs(trEntry.fxList or {}) do
        if string.find(string.lower(fx.name or ''), fl, 1, true) then
          hasMatch = true
          break
        end
      end
      if not hasMatch then
        goto continue_track
      end
    end
    local proj_idx = r.GetMediaTrackInfo_Value and r.GetMediaTrackInfo_Value(trEntry.track, 'IP_TRACKNUMBER') or (trEntry.idx + 1)
    proj_idx = tonumber(proj_idx) and math.floor(proj_idx) or (trEntry.idx + 1)
    local header = ("Track %d: %s"):format(proj_idx, trEntry.name)
    local is_sel = r.IsTrackSelected and (r.IsTrackSelected(trEntry.track) == true)
    local col = (r.GetTrackColor and r.GetTrackColor(trEntry.track)) or 0
    local rr, gg, bb = 0, 0, 0
    if col ~= 0 then
      if r.ColorFromNative then
        local cr, cg, cb = r.ColorFromNative(col)
        rr, gg, bb = (cr or 0)/255.0, (cg or 0)/255.0, (cb or 0)/255.0
      else
        rr = ((col      ) & 0xFF) / 255.0
        gg = ((col >> 8 ) & 0xFF) / 255.0
        bb = ((col >> 16) & 0xFF) / 255.0
      end
    end
    local pushed = false
    if col ~= 0 and ENUM.Col_Header and ENUM.Col_HeaderHovered and ENUM.Col_HeaderActive then
      local a1, a2, a3 = (is_sel and 0.65 or 0.6), (is_sel and 0.8 or 0.75), (is_sel and 0.95 or 0.9)
      push_style_color(ENUM.Col_Header, rr, gg, bb, a1)
      push_style_color(ENUM.Col_HeaderHovered, rr, gg, bb, a2)
      push_style_color(ENUM.Col_HeaderActive, rr, gg, bb, a3)
      pushed = true
    end
    if state.forceHeaders ~= nil and r.ImGui_SetNextItemOpen then r.ImGui_SetNextItemOpen(ctx, state.forceHeaders) end
    local open = r.ImGui_CollapsingHeader(ctx, header)
    if state.scrollToTrackNum and proj_idx == tonumber(state.scrollToTrackNum) then
      if r.ImGui_SetScrollHereY then
        pcall(r.ImGui_SetScrollHereY, ctx, 0.25)
      end
      state.scrollToTrackNum = nil
    end
    if pushed and HAVE_PushStyleColor then r.ImGui_PopStyleColor(ctx, 3) end
    if open then draw_track_fx_rows(trEntry) end
    shown = shown + 1
    ::continue_track::
  end
  if fl ~= '' and shown == 0 then
    r.ImGui_Text(ctx, 'No tracks match current filter')
  end
  if missingFound then
    rebuild_model()
  end
end

local function draw_status_bar()
  if state.pendingMessage ~= '' then
    if push_text_color(0.1, 1.0, 0.1, 1.0) then end
    r.ImGui_Text(ctx, state.pendingMessage)
    if HAVE_PushStyleColor then r.ImGui_PopStyleColor(ctx) end
    if not state.pendingJob then state.pendingMessage = '' end
  end
  if state.pendingJob then
    r.ImGui_SameLine(ctx)
    if r.ImGui_SmallButton(ctx, 'Cancel') then
      state.pendingJob = nil
      state.pendingMessage = 'Drop canceled'
    end
  end
  if state.pendingError ~= '' then
    if push_text_color(1.0, 0.2, 0.2, 1.0) then end
    r.ImGui_Text(ctx, state.pendingError)
    if HAVE_PushStyleColor then r.ImGui_PopStyleColor(ctx) end
    state.pendingError = ''
  end
end

local function process_pending_job()
  if not state.pendingJob then return end
  if state.jobDelayFrames and state.jobDelayFrames > 0 then
    state.jobDelayFrames = state.jobDelayFrames - 1
    return
  end
  local job = state.pendingJob
  state.pendingJob = nil
  local srcTr = find_track_by_guid(job.srcGuid)
  local destTr = find_track_by_guid(job.destGuid)
  if not srcTr or not destTr then return end
  r.PreventUIRefresh(1)
  r.Undo_BeginBlock()
  local ok = pcall(function()
    r.TrackFX_CopyToTrack(srcTr, job.srcIdx, destTr, job.destIdx, job.remove and true or false)
  end)
  r.Undo_EndBlock(job.remove and 'Move FX' or 'Copy FX to track', -1)
  r.PreventUIRefresh(-1)
  rebuild_model()
end

local function main_loop()
  ensure_ctx()
  local now = getProjectTimeSec()
  if state.autoRefresh and (now - state.lastRefreshTime) > state.refreshInterval then
    rebuild_model()
    state.lastRefreshTime = now
  end

  safe_SetNextWindowSize(800, 600, FLAGS.Cond_Appearing)
  local begunMain, visible, open = safe_Begin(SCRIPT_NAME, true, FLAGS.Window_MenuBar)
  if visible then
    if r.ImGui_BeginMenuBar(ctx) then
      if r.ImGui_MenuItem(ctx, 'Help') then
        r.MB((
          'TK FX Slots Manager - Help\n\n' ..
          'Scope & refresh:\n' ..
          ' - Selected tracks only limits scope to selected tracks.\n' ..
          ' - Hide empty tracks hides tracks without FX.\n' ..
          ' - Auto refresh updates the list periodically; use Refresh for manual update.\n\n' ..
          'Filter & headers:\n' ..
          ' - Filter matches FX names; tracks without matches are hidden.\n' ..
          ' - Reset filter clears it. Collapse/Expand all toggles all track headers.\n\n' ..
          'Jump to track:\n' ..
          ' - Enter Track # and press Go to scroll the list to that project track.\n\n' ..
          'Replace panel:\n' ..
          ' - Press Source on a row to choose the source FX.\n' ..
          ' - Placement: Same slot / Start / End / Index (slot is 1-based).\n' ..
          ' - Pick from list… uses Sexan\'s FX parser; Short list holds your favorites.\n' ..
          ' - Replace all instances replaces the source FX across the current scope.\n\n' ..
          'Per-FX row actions:\n' ..
          ' - Drag the FX name to reorder within a track (move) or drop on another track (copy).\n' ..
          ' - Drop is accepted on the # cell and the Name cell.\n' ..
          ' - On/Off toggles bypass. Ofl/Onl toggles offline. Del deletes.\n' ..
          ' - Replace.. replaces this FX with the chosen plugin.\n' ..
          ' - Source marks this FX for batch Replace all instances.\n\n' ..
          'Favorites:\n' ..
          ' - In the picker, + adds to Short list; in the dropdown, x removes. Favorites persist.\n\n' ..
          'Status & safety:\n' ..
          ' - Progress and errors show at the bottom; you can Cancel long FX placements.\n' ..
          ' - If tracks are deleted while open, the view auto-recovers.')
          , SCRIPT_NAME, 0)
      end
      r.ImGui_EndMenuBar(ctx)
    end
    draw_scope_row()
    r.ImGui_SetNextItemWidth(ctx, 300)
    local chg, f = r.ImGui_InputText(ctx, 'Filter', state.filter)
    if chg then state.filter = f end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, 'Reset filter') then state.filter = '' end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, 'Collapse all') then state.forceHeaders = false end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, 'Expand all') then state.forceHeaders = true end
  r.ImGui_SameLine(ctx)
  r.ImGui_Text(ctx, 'Track #')
  r.ImGui_SameLine(ctx)
  r.ImGui_SetNextItemWidth(ctx, 60)
  local chgNum, newNum = r.ImGui_InputInt(ctx, '##gotoTrack', tonumber(state.gotoTrackInput) or 1)
  if chgNum then
    state.gotoTrackInput = math.max(1, newNum or 1)
  end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, 'Go') then
    state.scrollToTrackNum = tonumber(state.gotoTrackInput) or 1
  end
    r.ImGui_Separator(ctx)
    draw_replace_panel()
    r.ImGui_Separator(ctx)
    local aw, ah = r.ImGui_GetContentRegionAvail(ctx)
    local status_h = 26 
    local child_h = (tonumber(ah) and ah or 0) - status_h
    if child_h < 0 then child_h = 0 end
    if r.ImGui_BeginChild(ctx, 'tracks_panel_scroll', 0, child_h, 0) then
      draw_tracks_panel()
    end
    r.ImGui_EndChild(ctx)
    r.ImGui_Separator(ctx)
    draw_status_bar()
  end
  if begunMain and visible then r.ImGui_End(ctx) end
  draw_plugin_picker()
  process_pending_job()
  if open == nil or open then
    r.defer(main_loop)
  end
end

rebuild_model()
r.defer(function()
  favs_load()
  main_loop()
end)
