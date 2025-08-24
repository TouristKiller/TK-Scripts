-- @description TK FX SLOTS MANAGER
-- @author TouristKiller
-- @version 0.0.2
-- @changelog:
--[[     
++ INITIAL LAUNCH FOR TESTING
            
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

-- no window helpers to avoid mismatches; use direct Begin/End

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

  -- Sexan parser (Goran rules!!)
  pluginList                = nil,
  showPicker                = false,
  pickerFilter              = '',
  replaceDisplay            = '',
}

local model = {
  tracks = {},
}

-- Helpers
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
    -- try treat as leaf first
    local disp, add = extract_fx_entry(obj)
    if disp and add then
      if not seen[add] then
        items[#items+1] = { display = disp, addname = add }
        seen[add] = true
      end
    end
    -- then traverse children
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
  -- Prefer GetFXTbl if available
  local list
  if type(GetFXTbl) == 'function' then
    local ok, res = pcall(GetFXTbl)
    if ok then list = res end
  end
  -- If not, try ReadFXFile/MakeFXFiles sequence
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
  -- Build flat items
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
      for _, it in ipairs(state.pluginItems or {}) do
        if filter == '' or tostring(it.display):lower():find(filter, 1, true) then
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
      table.insert(model.tracks, { track = tr, idx = ti, name = get_track_name(tr), fxList = fxList })
    end
  end
end

local function toggle_bypass(track, fx)
  local enabled = r.TrackFX_GetEnabled(track, fx)
  r.TrackFX_SetEnabled(track, fx, not enabled)
end

local function delete_fx(track, fx)
  r.TrackFX_Delete(track, fx)
end

local function move_fx(track, fromIdx, toIdx)
  if fromIdx == toIdx then return end
  local fxCount = r.TrackFX_GetCount(track)
  if fromIdx < 0 or fromIdx >= fxCount then return end
  if toIdx < 0 then toIdx = 0 end
  if toIdx >= fxCount then toIdx = FX_END end
  r.TrackFX_CopyToTrack(track, fromIdx, track, toIdx, true)
end

local function add_fx_at(track, fxName, atIdx)
  local fxIndex = r.TrackFX_AddByName(track, fxName, false, -1) 
  if fxIndex < 0 then return -1 end
  if atIdx == nil or atIdx == FX_END then return fxIndex end
  r.TrackFX_CopyToTrack(track, fxIndex, track, atIdx, true)
  return atIdx
end

local function replace_fx_at(track, fxIdx, fxName, overridePos, newPos)
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
  if state.replaceDisplay ~= '' then
    r.ImGui_SameLine(ctx)
    r.ImGui_Text(ctx, 'Selected: ' .. state.replaceDisplay)
  end
  if r.ImGui_Button(ctx, 'Replace all instances') then
    local count = 0
    count = select(1, replace_all_instances(state.selectedSourceFXName, state.replaceWith))
    state.pendingMessage = ('%d instances replaced.'):format(count)
    rebuild_model()
  end
end

local function draw_track_fx_rows(trEntry)
  local tr = trEntry.track

    if r.ImGui_BeginTable(ctx, ('fx_table_%p'):format(tr), 6, FLAGS.Table_SizingStretchProp) then
      r.ImGui_TableSetupColumn(ctx, '#', FLAGS.Col_WidthFixed, 30)
      r.ImGui_TableSetupColumn(ctx, 'FX name', FLAGS.Col_WidthStretch)
  r.ImGui_TableSetupColumn(ctx, 'Byp/Offl', FLAGS.Col_WidthFixed, 90)
      r.ImGui_TableSetupColumn(ctx, 'Move', FLAGS.Col_WidthFixed, 80)
      r.ImGui_TableSetupColumn(ctx, 'Actions', FLAGS.Col_WidthFixed, 200)
      r.ImGui_TableSetupColumn(ctx, 'Source', FLAGS.Col_WidthFixed, 50)
     r.ImGui_TableHeadersRow(ctx)

    local filter = state.filter
    for i, fx in ipairs(trEntry.fxList) do
      if filter == '' or string.find(string.lower(fx.name), string.lower(filter), 1, true) then
        r.ImGui_TableNextRow(ctx)

        r.ImGui_TableSetColumnIndex(ctx, 0)
        r.ImGui_Text(ctx, tostring(fx.idx + 1))

        r.ImGui_TableSetColumnIndex(ctx, 1)
        r.ImGui_Text(ctx, fx.name)

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
          -- bypass state unchanged; rebuild for consistency
          rebuild_model()
        end

        r.ImGui_TableSetColumnIndex(ctx, 3)
        if HAVE_StyleVar_FramePadding then
          r.ImGui_PushStyleVar(ctx, ENUM.StyleVar_FramePadding, 2, 2)
        end
        if r.ImGui_SmallButton(ctx, 'Up##u' .. i) then
          r.Undo_BeginBlock()
          move_fx(tr, fx.idx, fx.idx - 1)
          r.Undo_EndBlock('Move FX up', -1)
          rebuild_model()
        end
        r.ImGui_SameLine(ctx)
        if r.ImGui_SmallButton(ctx, 'Down##d' .. i) then
          r.Undo_BeginBlock()
          move_fx(tr, fx.idx, fx.idx + 2) 
          r.Undo_EndBlock('Move FX down', -1)
          rebuild_model()
        end
        if HAVE_StyleVar_FramePadding then
          r.ImGui_PopStyleVar(ctx)
        end

        r.ImGui_TableSetColumnIndex(ctx, 4)
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

        r.ImGui_TableSetColumnIndex(ctx, 5)
        if r.ImGui_SmallButton(ctx, 'Source##' .. i) then
          state.selectedSourceFXName = fx.name
        end
      end
    end

    r.ImGui_EndTable(ctx)
  end
end

local function draw_tracks_panel()
  for _, trEntry in ipairs(model.tracks) do
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
      -- Optionally make selected slightly stronger
      local a1, a2, a3 = (is_sel and 0.65 or 0.6), (is_sel and 0.8 or 0.75), (is_sel and 0.95 or 0.9)
      push_style_color(ENUM.Col_Header, rr, gg, bb, a1)
      push_style_color(ENUM.Col_HeaderHovered, rr, gg, bb, a2)
      push_style_color(ENUM.Col_HeaderActive, rr, gg, bb, a3)
      pushed = true
    end
  if state.forceHeaders ~= nil and r.ImGui_SetNextItemOpen then r.ImGui_SetNextItemOpen(ctx, state.forceHeaders) end
  local open = r.ImGui_CollapsingHeader(ctx, header)
    if pushed and HAVE_PushStyleColor then r.ImGui_PopStyleColor(ctx, 3) end
    if open then
      draw_track_fx_rows(trEntry)
    end
  end
end

local function draw_status_bar()
  if state.pendingMessage ~= '' then
    if push_text_color(0.1, 1.0, 0.1, 1.0) then end
    r.ImGui_Text(ctx, state.pendingMessage)
    if HAVE_PushStyleColor then r.ImGui_PopStyleColor(ctx) end
    state.pendingMessage = ''
  end
  if state.pendingError ~= '' then
    if push_text_color(1.0, 0.2, 0.2, 1.0) then end
    r.ImGui_Text(ctx, state.pendingError)
    if HAVE_PushStyleColor then r.ImGui_PopStyleColor(ctx) end
    state.pendingError = ''
  end
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
      if r.ImGui_BeginMenu(ctx, 'Help') then
        if r.ImGui_MenuItem(ctx, 'About') then
          r.MB('FX Slots Manager\nUsage: choose scope (selected or all tracks).\nSelect a source FX and choose a replacement to replace all instances.\nPer FX you can bypass, move, delete, or replace.', SCRIPT_NAME, 0)
        end
        r.ImGui_EndMenu(ctx)
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
    r.ImGui_Separator(ctx)
    draw_replace_panel()
    r.ImGui_Separator(ctx)
    draw_tracks_panel()
    r.ImGui_Separator(ctx)
    draw_status_bar()
  end
  if begunMain and visible then r.ImGui_End(ctx) end
  draw_plugin_picker()
  if open == nil or open then
    r.defer(main_loop)
  end
end

rebuild_model()
r.defer(main_loop)
