-- @description Replace focused FX slot on all selected tracks (picker)
-- @author TouristKiller
-- @version 0.0.1 
-- @changelog Initial version

-- THANX SEXAN FOR HIS FX PARSER
-- Requirements: ReaImGui and Sexan's FX Browser Parser V7

local r = reaper
local SCRIPT_TITLE = 'Replace focused slot across selected (picker)'

-- Load Sexan parser
local function ensure_sexan_parser()
  local path = r.GetResourcePath() .. '/Scripts/Sexan_Scripts/FX/Sexan_FX_Browser_ParserV7.lua'
  local f = io.open(path, 'r')
  if not f then return nil, 'Sexan FX Browser Parser V7 not found. Install via ReaPack.' end
  f:close()
  local ok, res = pcall(dofile, path)
  if not ok then return nil, 'Sexan parser error: ' .. tostring(res) end
  local parser = res or _G.FXB
  if type(parser) ~= 'table' or type(parser.BuildFXList) ~= 'function' then
    return nil, 'Sexan parser table (FXB) not found after loading.'
  end
  return parser
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
  local parser, err = ensure_sexan_parser()
  local items, seen = {}, {}
  if parser then
    local okBuild, list = pcall(parser.BuildFXList)
    if okBuild then
      flatten_plugins(list, items, seen, 0)
      table.sort(items, function(a,b) return (a.display or ''):lower() < (b.display or ''):lower() end)
      return items
    else
      err = 'Parser BuildFXList failed'
    end
  end
  local prefixes = {
    'VST3:', 'VSTi3:', 'VST:', 'VSTi:', 'CLAP:', 'JS:', 'JSFX:', 'AU:', 'DX:'
  }
  local tested = {}
  for _, p in ipairs(prefixes) do
    local candidates = {
      p .. ' ReaEQ', p .. ' ReaComp', p .. ' ReaGate', p .. ' ReaDelay', p .. ' ReaLimit', p .. ' ReaXcomp',
      p .. ' ReaFIR', p .. ' ReaTune', p .. ' ReaVerb', p .. ' ReaVerbate', p .. ' ReaSurround'
    }
    for _, name in ipairs(candidates) do
      if not tested[name] then
        tested[name] = true
        local tr = r.GetMasterTrack(0)
        local idx = r.TrackFX_AddByName(tr, name, false, -1)
        if idx >= 0 then
          r.TrackFX_Delete(tr, idx)
          items[#items+1] = { display = name, addname = name }
        end
      end
    end
  end
  if #items == 0 then
    return nil, err or 'Sexan parser table (FXB) not found and no fallback items detected.'
  end
  table.sort(items, function(a,b) return (a.display or ''):lower() < (b.display or ''):lower() end)
  return items
end

local function replace_across_selected(slotIdx, target)
  local selCount = r.CountSelectedTracks(0)
  if selCount == 0 then
    r.ShowMessageBox('No selected tracks.', SCRIPT_TITLE, 0)
    return
  end
  local probeTrack = r.GetSelectedTrack(0, 0)
  local probeIdx = r.TrackFX_AddByName(probeTrack, target, false, -1)
  if probeIdx < 0 then
    r.ShowMessageBox('FX not found: ' .. target, SCRIPT_TITLE, 0)
    return
  else
    r.TrackFX_Delete(probeTrack, probeIdx)
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
      end
    end
  end
  r.PreventUIRefresh(-1)
  r.Undo_EndBlock(string.format('Replace slot %d on %d selected track(s) with %s', slotIdx + 1, replaced, target), -1)
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
      
      r.ImGui_BeginChild(ctx, 'list', -1, -38)
      local fl = (state.filter or ''):lower()
      for _, it in ipairs(state.items or {}) do
        local disp = it.display or it.addname
        local add  = it.addname or disp
        if fl == '' or (disp and disp:lower():find(fl, 1, true)) or (add and add:lower():find(fl, 1, true)) then
          local selected = (state.chosenAdd == add)
          if r.ImGui_Selectable(ctx, disp, selected) then state.chosenAdd = add end
          if r.ImGui_IsItemHovered(ctx) and r.ImGui_IsMouseDoubleClicked(ctx, 0) then
            state.chosenAdd = add
            open = false
          end
        end
      end
      r.ImGui_EndChild(ctx)
    
      if r.ImGui_Button(ctx, 'Replace across selected') then
        if state.chosenAdd and state.chosenAdd ~= '' then
          open = false
        end
      end
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
      replace_across_selected(fx, target)
    end
  end
end

main_loop()
