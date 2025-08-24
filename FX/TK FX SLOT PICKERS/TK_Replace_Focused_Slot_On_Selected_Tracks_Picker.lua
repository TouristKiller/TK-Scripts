-- @description Replace focused FX slot on all selected tracks (picker)
-- @author TouristKiller
-- @version 0.0.3
-- @changelog Initial version

-- THANX SEXAN FOR HIS FX PARSER
-- Requirements: ReaImGui and Sexan's FX Browser Parser V7

local r = reaper
local SCRIPT_TITLE = 'Replace focused slot across selected (picker)'

-- Load Sexan parser
local function file_exists(path)
  local f = io.open(path, 'r')
  if f then f:close() return true end
  return false
end

local function ensure_sexan_parser()
  local fx_parser = r.GetResourcePath() .. '/Scripts/Sexan_Scripts/FX/Sexan_FX_Browser_ParserV7.lua'
  if file_exists(fx_parser) then
    local ok, err = pcall(dofile, fx_parser)
    if not ok then
      return false, 'Sexan parser error: ' .. tostring(err)
    end
    return true
  else
    if r.ReaPack_BrowsePackages then
      r.ShowMessageBox('Sexan FX Browser Parser V7 is missing. Opening ReaPack to install.', SCRIPT_TITLE, 0)
      r.ReaPack_BrowsePackages('"sexan fx browser parser v7"')
    end
    return false, 'Sexan FX Browser Parser V7 not found. Please install via ReaPack.'
  end
end

local function extract_fx_entry(entry)
  local t = type(entry)
  if t == 'string' then return entry, entry end
  if t == 'table' then
    local name = entry.name or entry.fxname or entry.fxName or entry.fname or entry.FX_NAME or entry[1]
    local add  = entry.addname or entry.fullname or entry.name or entry.fxname or entry[2] or name
    if name or add then return tostring(name or add), tostring(add or name) end
  end
  return nil, nil
end

local function flatten_plugins(obj, items, seen, depth)
  if depth > 6 then return end
  local t = type(obj)
  if t == 'table' then
    local disp, add = extract_fx_entry(obj)
    if disp and add and not seen[add] then
      items[#items+1] = { display = disp, addname = add }
      seen[add] = true
    end
    for _, v in pairs(obj) do
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

local function load_plugin_items()
  local okParser, err = ensure_sexan_parser()
 
  local list = nil
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
  if not list and type(_G.FXB) == 'table' and type(_G.FXB.BuildFXList) == 'function' then
    local okB, resB = pcall(_G.FXB.BuildFXList)
    if okB then list = resB end
  end
  if not list then
    return nil, err or 'Could not load plugin list from Sexan parser.'
  end
  local items, seen = {}, {}
  flatten_plugins(list, items, seen, 0)
  table.sort(items, function(a,b) return (a.display or ''):lower() < (b.display or ''):lower() end)
  return items
end

local function replace_across_selected(slotIdx, target)
  local selCount = r.CountSelectedTracks(0)
  if selCount == 0 then
    r.ShowMessageBox('No selected tracks.', SCRIPT_TITLE, 0)
    return
  end

  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)
  local replaced = 0
  for i = 0, selCount - 1 do
    local track = r.GetSelectedTrack(0, i)
    if track then
      local fxCount = r.TrackFX_GetCount(track)
      if slotIdx >= 0 and slotIdx < fxCount then
        r.TrackFX_Delete(track, slotIdx)
      end
      local newIdx = r.TrackFX_AddByName(track, target, false, -1)
      if newIdx >= 0 then
        local curCount = r.TrackFX_GetCount(track)
        local dest = (slotIdx >= 0 and slotIdx < curCount) and slotIdx or -1
        r.TrackFX_CopyToTrack(track, newIdx, track, dest, true)
        replaced = replaced + 1
      else
      end
    end
  end
  r.PreventUIRefresh(-1)
  r.Undo_EndBlock(string.format('Replace slot %d on %d selected track(s) with %s', slotIdx + 1, replaced, target), -1)
  if replaced == 0 then
    r.ShowMessageBox('FX not found: ' .. tostring(target), SCRIPT_TITLE, 0)
  end
end

local function replace_across_all(slotIdx, target)
  local total = r.CountTracks(0)
  if total == 0 then
    r.ShowMessageBox('No tracks in project.', SCRIPT_TITLE, 0)
    return
  end
  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)
  local replaced = 0
  for i = 0, total - 1 do
    local track = r.GetTrack(0, i)
    if track then
      local fxCount = r.TrackFX_GetCount(track)
      if slotIdx >= 0 and slotIdx < fxCount then
        r.TrackFX_Delete(track, slotIdx)
      end
      local newIdx = r.TrackFX_AddByName(track, target, false, -1)
      if newIdx >= 0 then
        local curCount = r.TrackFX_GetCount(track)
        local dest = (slotIdx >= 0 and slotIdx < curCount) and slotIdx or -1
        r.TrackFX_CopyToTrack(track, newIdx, track, dest, true)
        replaced = replaced + 1
      end
    end
  end
  r.PreventUIRefresh(-1)
  r.Undo_EndBlock(string.format('Replace slot %d on %d track(s) with %s', slotIdx + 1, replaced, target), -1)
  if replaced == 0 then
    r.ShowMessageBox('FX not found: ' .. tostring(target), SCRIPT_TITLE, 0)
  end
end

local have_imgui = (r.ImGui_CreateContext ~= nil)
if not have_imgui then
  r.ShowMessageBox('ReaImGui is required. Install via ReaPack: ReaImGui - Dear ImGui bindings for ReaScript.', SCRIPT_TITLE, 0)
  return
end

local ctx = r.ImGui_CreateContext(SCRIPT_TITLE)
if r.ImGui_StyleColorsDark then pcall(function() r.ImGui_StyleColorsDark(ctx) end) end

local state = {
  items = nil,
  err = nil,
  filter = '',
  chosenAdd = nil,
  triedCache = false,
  loadedFromCache = false,
  intent = 'selected',
}

local function get_cache_path()
  local sep = package.config:sub(1,1)
  local base = r.GetResourcePath() .. sep .. 'Scripts' .. sep .. 'TK Scripts' .. sep .. 'FX'
  return base .. sep .. 'TK_FX_Picker_Cache.tsv'
end

local function read_cache_items()
  local path = get_cache_path()
  local f = io.open(path, 'r')
  if not f then return nil end
  local items = {}
  for line in f:lines() do
    local add, disp = line:match('^(.-)\t(.*)$')
    add = add or line
    disp = disp or add
    if add ~= '' then items[#items+1] = { addname = add, display = disp } end
  end
  f:close()
  if #items == 0 then return nil end
  table.sort(items, function(a,b) return (a.display or ''):lower() < (b.display or ''):lower() end)
  return items
end

local function write_cache_items(items)
  local path = get_cache_path()
  local f = io.open(path, 'w')
  if not f then return false end
  for _, it in ipairs(items or {}) do
    local add = tostring(it.addname or '')
    local disp = tostring(it.display or it.addname or '')
    if add ~= '' then f:write(add .. "\t" .. disp .. "\n") end
  end
  f:close()
  return true
end

local function ensure_items()
  if state.items or state.err then return end
  if not state.triedCache then
    state.triedCache = true
    local cached = read_cache_items()
    if cached then
      state.items = cached
      state.loadedFromCache = true
      return
    end
  end
end

local function draw()
  ensure_items()
  r.ImGui_SetNextWindowSize(ctx, 680, 520, r.ImGui_Cond_Appearing())
  local visible, open = r.ImGui_Begin(ctx, SCRIPT_TITLE, true, r.ImGui_WindowFlags_MenuBar())
  if visible then
    if r.ImGui_BeginMenuBar and r.ImGui_BeginMenuBar(ctx) then
      if r.ImGui_MenuItem(ctx, 'Refresh list (build)') then
        local items, err = load_plugin_items()
        if items then
          state.items, state.err = items, nil
          state.loadedFromCache = false
          write_cache_items(items)
        else
          state.err = err or 'Failed to build list'
        end
      end
      if state.loadedFromCache then
        r.ImGui_Text(ctx, '  [cache]')
      end
      r.ImGui_EndMenuBar(ctx)
    end

    if state.err then
      r.ImGui_TextWrapped(ctx, state.err)
    elseif not state.items then
      r.ImGui_TextWrapped(ctx, 'Geen lijst geladen. Klik boven op "Refresh list (build)" om de lijst te bouwen en te cachen.')
    else
      
      r.ImGui_SetNextItemWidth(ctx, -1)
      local changed, txt = r.ImGui_InputText(ctx, '##filter', state.filter or '')
      if changed then state.filter = txt end
      
      r.ImGui_BeginChild(ctx, 'list', -1, -66)
      local fl = (state.filter or ''):lower()
      for _, it in ipairs(state.items or {}) do
        local disp = it.display or it.addname
        local add  = it.addname or disp
        if fl == '' or (disp and disp:lower():find(fl, 1, true)) or (add and add:lower():find(fl, 1, true)) then
          local selected = (state.chosenAdd == add)
          if r.ImGui_Selectable(ctx, disp, selected) then state.chosenAdd = add end
          if r.ImGui_IsItemHovered(ctx) and r.ImGui_IsMouseDoubleClicked(ctx, 0) then
            state.chosenAdd = add
            state.intent = 'selected'
            open = false
          end
        end
      end
      r.ImGui_EndChild(ctx)
    
      local disabled = not (state.chosenAdd and state.chosenAdd ~= '')
      if disabled then r.ImGui_BeginDisabled(ctx) end
      if r.ImGui_Button(ctx, 'Apply to selected tracks') then
        state.intent = 'selected'
        open = false
      end
      r.ImGui_SameLine(ctx)
      if r.ImGui_Button(ctx, 'Apply to all tracks') then
        state.intent = 'all'
        open = false
      end
      if disabled then r.ImGui_EndDisabled(ctx) end
      r.ImGui_SameLine(ctx)
      if r.ImGui_Button(ctx, 'Cancel') then
        state.chosenAdd = nil
        open = false
      end
    end
  end
  r.ImGui_End(ctx)
  return open ~= false
end

local function main_loop()
  local retval, trk, _, fx = r.GetFocusedFX()
  if retval ~= 1 then
    r.ShowMessageBox('Focus a Track FX first (not a Take/Monitoring FX).', SCRIPT_TITLE, 0)
    return
  end
  if draw() then
    r.defer(main_loop)
  else
    local target = state.chosenAdd
    if target and target ~= '' then
      if state.intent == 'all' then
        replace_across_all(fx, target)
      else
        replace_across_selected(fx, target)
      end
    end
  end
end

main_loop()
