-- @version 0.0.2
-- @author: TouristKiller (with assistance from Robert ;o) )
-- @changelog:
--[[     

== THNX TO MASTER SEXAN FOR HIS FX PARSER ==

]]--        
--------------------------------------------------------------------------


local r = reaper
local SCRIPT_NAME = 'TK FX Slots Single Track'

local ctx = r.ImGui_CreateContext and r.ImGui_CreateContext(SCRIPT_NAME) or nil
local iconFont = nil
local DND_FX_PAYLOAD = 'TK_FX_ROW_SINGLE'

local state = {
  selectedSourceFXName = nil,
  winW = 340,
  winH = 420,
  tooltips = true,
  scopeSelectedOnly = true,
  replaceWith = '',
  replaceDisplay = '',
  insertOverride = true,
  insertPos = 'in_place',
  insertIndex = 0,
  batchSlotIndex = 0,
  deleteInsertPlaceholder = false,
  placeholderCustomName = '',
  tkBlankVariants = nil,
  placeholderVariantName = 'Blank',
  slotUsePlaceholder = false,
  slotMatchSourceOnly = false,
  pendingMessage = '',
  pendingError = '',
  favs = {},
  showSettings = false,
  showSettingsPending = false,
  showHelp = false,
  showPicker = false,
  pickerItems = nil,
  pickerErr = nil,
  pickerFilter = '',
  pickerChosenAdd = nil,
  pickerLoadedFromCache = false,
  pickerTriedCache = false,
  pickerType = 'All types',
  actionType = 'replace_all',
  useDummyReplace = false,
  nameNoPrefix = false,
  nameHideDeveloper = false,
  trackHeaderOpen = true,
  hdrInitApplied = false,
  -- Section open states (collapsible headers)
  replHeaderOpen = true,
  actionHeaderOpen = true,
  sourceHeaderOpen = true,
  -- A/B helpers (single-slot swap)
  selectedSourceFXIndex = nil,
  abSlotIndex = nil,
  abOrigGUID = nil,
  abReplGUID = nil,
  abActiveIsRepl = false,
  screenshotTex = nil,
  screenshotKey = nil,
  screenshotFound = false,
}

local FX_END = -1

local EXT_NS = 'TK_FX_SINGLE'
local function load_window_size()
  local w = tonumber(r.GetExtState(EXT_NS, 'WIN_W') or '')
  local h = tonumber(r.GetExtState(EXT_NS, 'WIN_H') or '')
  if w and h and w > 0 and h > 0 then state.winW, state.winH = math.floor(w), math.floor(h) end
end
local function save_window_size(w, h)
  if not w or not h then return end
  r.SetExtState(EXT_NS, 'WIN_W', tostring(math.floor(w)), true)
  r.SetExtState(EXT_NS, 'WIN_H', tostring(math.floor(h)), true)
end
local function load_user_settings()
  local t = r.GetExtState(EXT_NS, 'TOOLTIPS')
  if t ~= nil and t ~= '' then state.tooltips = (t == '1') end
  local np = r.GetExtState(EXT_NS, 'NAME_NOPREFIX')
  if np ~= nil and np ~= '' then state.nameNoPrefix = (np == '1') end
  local hd = r.GetExtState(EXT_NS, 'NAME_HIDEDEV')
  if hd ~= nil and hd ~= '' then state.nameHideDeveloper = (hd == '1') end
  local ho = r.GetExtState(EXT_NS, 'HDR_OPEN')
  if ho ~= nil and ho ~= '' then state.trackHeaderOpen = (ho == '1') end
  local ro = r.GetExtState(EXT_NS, 'REPL_OPEN')
  if ro ~= nil and ro ~= '' then state.replHeaderOpen = (ro == '1') end
  local ao = r.GetExtState(EXT_NS, 'ACT_OPEN')
  if ao ~= nil and ao ~= '' then state.actionHeaderOpen = (ao == '1') end
  local so = r.GetExtState(EXT_NS, 'SRC_OPEN')
  if so ~= nil and so ~= '' then state.sourceHeaderOpen = (so == '1') end
end
local function save_user_settings()
  r.SetExtState(EXT_NS, 'TOOLTIPS', state.tooltips and '1' or '0', true)
  r.SetExtState(EXT_NS, 'NAME_NOPREFIX', state.nameNoPrefix and '1' or '0', true)
  r.SetExtState(EXT_NS, 'NAME_HIDEDEV', state.nameHideDeveloper and '1' or '0', true)
  r.SetExtState(EXT_NS, 'HDR_OPEN', state.trackHeaderOpen and '1' or '0', true)
  r.SetExtState(EXT_NS, 'REPL_OPEN', state.replHeaderOpen and '1' or '0', true)
  r.SetExtState(EXT_NS, 'ACT_OPEN', state.actionHeaderOpen and '1' or '0', true)
  r.SetExtState(EXT_NS, 'SRC_OPEN', state.sourceHeaderOpen and '1' or '0', true)
end

local PICKER_TYPE_OPTIONS = {
  'All types',
  'CLAP','CLAPi',
  'VST','VSTi',
  'VST3','VST3i',
  'JS',
  'AU','AUV3','AUV3i',
  'LV2','LV2i',
  'DX','DXi',
}

local function parse_addname_type(add)
  local s = tostring(add or '')
  local prefix = s:match('^([%w]+):')
  if not prefix then return 'All types' end
  local map = {
    CLAP = 'CLAP', CLAPI = 'CLAPi',
    VST = 'VST', VSTI = 'VSTi',
    VST3 = 'VST3', VST3I = 'VST3i',
    JS = 'JS',
    AU = 'AU', AUV3 = 'AUV3', AUV3I = 'AUV3i',
    LV2 = 'LV2', LV2I = 'LV2i',
    DX = 'DX', DXI = 'DXi',
  }
  return map[prefix:upper()] or 'All types'
end

local function col_u32(r1, g1, b1, a1)
  if r.ImGui_ColorConvertDouble4ToU32 then
    return r.ImGui_ColorConvertDouble4ToU32(r1 or 0, g1 or 0, b1 or 0, a1 or 1)
  end
  local R = math.floor((r1 or 0) * 255 + 0.5)
  local G = math.floor((g1 or 0) * 255 + 0.5)
  local B = math.floor((b1 or 0) * 255 + 0.5)
  local A = math.floor((a1 or 1) * 255 + 0.5)
  return (A << 24) | (B << 16) | (G << 8) | (R & 0xFF)
end
local function lighten(rf,gf,bf, amt)
  local function clamp(x) if x < 0 then return 0 elseif x > 1 then return 1 else return x end end
  return clamp(rf + amt), clamp(gf + amt), clamp(bf + amt)
end

local function get_selected_track()
  return r.GetSelectedTrack(0, 0)
end
local function get_track_number(tr)
  if not tr then return nil end
  return math.floor((r.GetMediaTrackInfo_Value(tr, 'IP_TRACKNUMBER') or 0) + 0.0001)
end
local function get_track_name(tr)
  if not tr then return '' end
  local ok, name = r.GetTrackName(tr)
  return (ok and name) or ''
end
local function get_track_color_rgb(tr)
  if not tr then return nil end
  local col = r.GetTrackColor(tr)
  if not col or col == 0 then return nil end
  local r8 = col & 255
  local g8 = (col >> 8) & 255
  local b8 = (col >> 16) & 255
  return (r8 or 0)/255, (g8 or 0)/255, (b8 or 0)/255
end
local function get_fx_name(tr, fxIdx)
  local _, name = r.TrackFX_GetFXName(tr, fxIdx, '')
  return name or ''
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

local function ensure_icon_font()
  if not ctx then return end
  if iconFont ~= nil then return end
  local script_dir = (debug.getinfo(1, 'S').source or '')
  if script_dir:sub(1,1) == '@' then script_dir = script_dir:sub(2) end
  script_dir = script_dir:match('^(.+[\\/])') or ''
  if r.ImGui_CreateFontFromFile and r.ImGui_Attach then
    local f = r.ImGui_CreateFontFromFile(script_dir .. 'Icons-Regular.otf', 0)
    if f then
      r.ImGui_Attach(ctx, f)
      if r.ImGui_BuildFontAtlas then r.ImGui_BuildFontAtlas(ctx) end
      iconFont = f
    else
      iconFont = false
    end
  else
    iconFont = false
  end
end

local function build_plugin_report_text()
  local buf = {}
  local function add(line) buf[#buf+1] = line end
  local trCount = r.CountTracks(0)
  add(('Project FX report (%d track(s))'):format(trCount))
  add(('Settings: nameNoPrefix=%s, hideDeveloper=%s'):format(tostring(state.nameNoPrefix), tostring(state.nameHideDeveloper)))
  add('')
  for i = 0, trCount - 1 do
    local tr = r.GetTrack(0, i)
    local tname = get_track_name(tr)
    add(('- Track %d: %s'):format(i+1, tname))
    local fxCount = r.TrackFX_GetCount(tr)
    if fxCount == 0 then
      add('  (no FX)')
    else
      for fx = 0, fxCount - 1 do
        local nm = get_fx_name(tr, fx)
        add(('  %2d. %s'):format(fx+1, format_fx_display_name(nm)))
      end
    end
    add('')
  end
  return table.concat(buf, '\n')
end

local function print_plugin_list()
  local txt = build_plugin_report_text()
  local sep = package.config:sub(1,1)
  local base = r.GetResourcePath() .. sep .. 'Scripts' .. sep .. 'TK Scripts' .. sep .. 'FX'
  if r.RecursiveCreateDirectory then r.RecursiveCreateDirectory(base, 0) end
  local path = base .. sep .. 'TK_FX_Report.txt'
  local f, err = io.open(path, 'w')
  if not f then return false, tostring(err or 'Cannot open file') end
  f:write(txt or '')
  f:close()
  return true, path
end

local function push_app_style()
  local pushed = 0
   local function P(colFn, r1, g1, b1, a1)
    if colFn and r.ImGui_PushStyleColor then
      r.ImGui_PushStyleColor(ctx, colFn(), col_u32(r1, g1, b1, a1))
      pushed = pushed + 1
    end
  end
  P(r.ImGui_Col_Button,        0.14, 0.14, 0.14, 1.00)
  P(r.ImGui_Col_ButtonHovered, 0.22, 0.22, 0.22, 1.00)
  P(r.ImGui_Col_ButtonActive,  0.10, 0.10, 0.10, 1.00)
  P(r.ImGui_Col_FrameBg,       0.12, 0.12, 0.12, 1.00)
  P(r.ImGui_Col_FrameBgHovered,0.18, 0.18, 0.18, 1.00)
  P(r.ImGui_Col_FrameBgActive, 0.16, 0.16, 0.16, 1.00)
  P(r.ImGui_Col_PopupBg,       0.10, 0.10, 0.10, 0.98)
  P(r.ImGui_Col_CheckMark,     0.85, 0.85, 0.85, 1.00)
  return pushed
end

local function pop_app_style(n)
  if n and n > 0 and r.ImGui_PopStyleColor then r.ImGui_PopStyleColor(ctx, n) end
end

 
local FAVS_NS = 'TK_FX_SLOTS'
local FAVS_NS = 'TK_FX_SLOTS'
local function favs_load()
  state.favs = {}
  local s = r.GetExtState(FAVS_NS, 'FAVS') or ''
  if s == '' then return end
  for line in string.gmatch(s, '([^\n]+)') do
    local add, disp = line:match('^(.-)\t(.*)$')
    add = add or line
    disp = disp or add
    if add ~= '' then state.favs[#state.favs+1] = { addname = add, display = disp } end
  end
end
local function favs_save()
  local buf = {}
  for i, it in ipairs(state.favs or {}) do
    buf[#buf+1] = (it.addname or '') .. "\t" .. (it.display or it.addname or '')
  end
  r.SetExtState(FAVS_NS, 'FAVS', table.concat(buf, "\n"), true)
end
local function favs_remove(addname)
  for i = #state.favs, 1, -1 do
    if state.favs[i].addname == addname then table.remove(state.favs, i) end
  end
  favs_save()
  state.pendingMessage = 'Removed from My Favorites'
end
local function favs_add(addname, display)
  if not addname or addname == '' then return end
  for _, it in ipairs(state.favs or {}) do if it.addname == addname then return end end
  state.favs[#state.favs+1] = { addname = addname, display = display or addname }
  favs_save()
  state.pendingMessage = 'Added to My Favorites'
end

local function blanks_load()
  state.tkBlankVariants = {}
  local s = r.GetExtState(FAVS_NS, 'BLANKS') or ''
  local seen = {}

  state.tkBlankVariants[#state.tkBlankVariants+1] = { name = 'Blank' }
  seen['Blank'] = true
  for line in string.gmatch(s, '([^\n]+)') do
    local nm = line:gsub('\r', '')
    if nm ~= '' and not seen[nm] then
      state.tkBlankVariants[#state.tkBlankVariants+1] = { name = nm }
      seen[nm] = true
    end
  end
end
local function blanks_save()
  local buf = {}
  for i, it in ipairs(state.tkBlankVariants or {}) do
    if it.name and it.name ~= '' and it.name ~= 'Blank' then buf[#buf+1] = it.name end
  end
  r.SetExtState(FAVS_NS, 'BLANKS', table.concat(buf, "\n"), true)
end
local function blanks_add(name)
  if not name or name == '' then return end
  if not state.tkBlankVariants or #state.tkBlankVariants == 0 then blanks_load() end
  for _, v in ipairs(state.tkBlankVariants or {}) do if v.name == name then return end end
  state.tkBlankVariants[#state.tkBlankVariants+1] = { name = name }
  blanks_save()
end

local function ensure_blank_jsfx()
  local baseDir = r.GetResourcePath() .. '/Effects/TK'
  r.RecursiveCreateDirectory(baseDir, 0)
  local baseFile = baseDir .. '/TK_Blank_NoOp_Base.jsfx'
  local baseFile = baseDir .. '/TK_Blank_NoOp_Base.jsfx'
  if not io.open(baseFile, 'r') then
    local f = io.open(baseFile, 'w')
    if f then
      f:write([[desc: TK Blank NoOp (Base)
in_pin: Input
out_pin: Output
@init
// no-op
@slider
@block
@sample
// pass-through
]])
      f:close()
    end
  end
end
local function ensure_tk_blank_addname(customDesc)
  ensure_blank_jsfx()
  local alias = tostring(customDesc or '')
  if alias == '' then alias = 'Blank' end
  local baseDir = r.GetResourcePath() .. '/Effects/TK'
  local fname = ('TK_Blank_NoOp_%s.jsfx'):format(alias)
  local path = baseDir .. '/' .. fname
  local f = io.open(path, 'w')
  if f then
    f:write(('desc: %s\n'):format(alias))
    f:write([[in_pin: Input
out_pin: Output
@init
@slider
@block
@sample
]])
    f:close()
  end
  
  local addname = 'JS: ' .. ('TK/%s'):format(fname:gsub('%.jsfx$', ''))
  local addname = 'JS: ' .. ('TK/%s'):format(fname:gsub('%.jsfx$', ''))
  return addname
end
local function refresh_tk_blank_variants()
  blanks_load()
end

 
local function rename_fx_instance(track, fxIdx, name)
  if not (track and name and name ~= '') then return end
  if r.TrackFX_SetNamedConfigParm then pcall(function() r.TrackFX_SetNamedConfigParm(track, fxIdx, 'renamed', tostring(name)) end) end
  if r.TrackList_AdjustWindows then pcall(function() r.TrackList_AdjustWindows(false) end) end
  if r.UpdateArrange then pcall(function() r.UpdateArrange() end) end
end

local function find_fx_index_by_guid(track, guid)
  if not guid then return nil end
  local cnt = r.TrackFX_GetCount(track)
  for i=0,cnt-1 do
    local g = r.TrackFX_GetFXGUID(track, i)
    if g == guid then return i end
  end
  return nil
end
local function get_fx_enabled(track, fxIdx)
  if r.TrackFX_GetEnabled then
    local ok, en = pcall(function() return r.TrackFX_GetEnabled(track, fxIdx) end)
    if ok then return en end
  end
  return nil
end
local function set_fx_enabled(track, fxIdx, enabled)
  if r.TrackFX_SetEnabled then pcall(function() r.TrackFX_SetEnabled(track, fxIdx, enabled and true or false) end) end
end
local function set_fx_offline(track, fxIdx, offline)
  if r.TrackFX_SetOffline then pcall(function() r.TrackFX_SetOffline(track, fxIdx, offline and true or false) end) end
end
local function get_fx_offline(track, fxIdx)
  if r.TrackFX_GetOffline then
    local ok, off = pcall(function() return r.TrackFX_GetOffline(track, fxIdx) end)
    if ok then return off end
  end
  return nil
end

local function find_delta_param_index(track, fxIdx)
  local guid = r.TrackFX_GetFXGUID and r.TrackFX_GetFXGUID(track, fxIdx) or nil
  state.deltaParamByGuid = state.deltaParamByGuid or {}
  if guid and state.deltaParamByGuid[guid] ~= nil then return state.deltaParamByGuid[guid] end
  local pc = r.TrackFX_GetNumParams(track, fxIdx) or 0
  local idx = nil
  for p=0, pc-1 do
    local _, pname = r.TrackFX_GetParamName(track, fxIdx, p, '')
    local pl = (pname or ''):lower()
    if pl:find('delta', 1, true) or pl:find('∆', 1, true) or pl:find('diff', 1, true) then idx = p break end
  end
  if guid then state.deltaParamByGuid[guid] = idx end
  return idx
end
local function get_fx_delta_active(track, fxIdx)
  local p = find_delta_param_index(track, fxIdx)
  if p == nil then return nil end
  local v = r.TrackFX_GetParamNormalized(track, fxIdx, p)
  if v == nil then return nil end
  return v > 0.5
end
local function toggle_fx_delta(track, fxIdx)
  local p = find_delta_param_index(track, fxIdx)
  if p == nil then return false end
  local v = r.TrackFX_GetParamNormalized(track, fxIdx, p) or 0
  local nv = (v > 0.5) and 0 or 1
  r.TrackFX_SetParamNormalized(track, fxIdx, p, nv)
  return true
end

local function get_fx_overall_wet(track, fxIdx)
  if r.TrackFX_GetParamFromIdent and r.TrackFX_GetParam then
    local p = r.TrackFX_GetParamFromIdent(track, fxIdx, ':wet')
    if p and p >= 0 then
      local val = r.TrackFX_GetParam(track, fxIdx, p)
      if type(val) == 'number' then return math.max(0, math.min(1, val)) end
    end
  end
  if r.TrackFX_GetNamedConfigParm then
    local ok2, val = pcall(function() return select(2, r.TrackFX_GetNamedConfigParm(track, fxIdx, 'wet')) end)
    if ok2 and val and val ~= '' then
      local n = tonumber(val)
      if n then return math.max(0, math.min(1, n)) end
    end
  end
  if r.TrackFX_GetWetDryMix then
    local ok, wet = pcall(function() return r.TrackFX_GetWetDryMix(track, fxIdx) end)
    if ok and type(wet) == 'number' then return math.max(0, math.min(1, wet)) end
  end
  return 1.0
end
local function set_fx_overall_wet(track, fxIdx, v)
  local wet = math.max(0, math.min(1, tonumber(v) or 0))
  if r.TrackFX_GetParamFromIdent and r.TrackFX_SetParam then
    local p = r.TrackFX_GetParamFromIdent(track, fxIdx, ':wet')
    if p and p >= 0 then
      r.TrackFX_SetParam(track, fxIdx, p, wet)
      return true
    end
  end
  if r.TrackFX_SetNamedConfigParm then
    local ok = pcall(function() r.TrackFX_SetNamedConfigParm(track, fxIdx, 'wet', string.format('%.6f', wet)) end) or false
    if ok then return true end
  end
  if r.TrackFX_SetWetDryMix then
    local ok = pcall(function() r.TrackFX_SetWetDryMix(track, fxIdx, wet, 1 - wet) end) or false
    if ok then return true end
  end
  return false
end

local function find_wet_param_index(track, fxIdx)
  local guid = r.TrackFX_GetFXGUID and r.TrackFX_GetFXGUID(track, fxIdx) or nil
  state.mixParamByGuid = state.mixParamByGuid or {}
  if guid and state.mixParamByGuid[guid] ~= nil then return state.mixParamByGuid[guid] end
  local pc = r.TrackFX_GetNumParams(track, fxIdx) or 0
  local bestIdx, bestRank = nil, 999
  for p=0, pc-1 do
    local _, pname = r.TrackFX_GetParamName(track, fxIdx, p, '')
    local pl = (pname or ''):lower()
    local rank = nil
    if pl:find('dry/wet', 1, true) then rank = 1
    elseif pl == 'wet' or pl:find(' wet', 1, true) or pl:find('wet ', 1, true) then rank = 2
    elseif pl:find('mix', 1, true) then rank = 3
    elseif pl:find('blend', 1, true) then rank = 4
    elseif pl:find('amount', 1, true) then rank = 5
    end
    if rank and rank < bestRank then bestRank, bestIdx = rank, p end
  end
  if guid then state.mixParamByGuid[guid] = bestIdx end
  return bestIdx
end
local function get_wet_value(track, fxIdx)
  local p = find_wet_param_index(track, fxIdx)
  if p == nil then return nil end
  return r.TrackFX_GetParamNormalized(track, fxIdx, p) or 0
end
local function set_wet_value(track, fxIdx, v)
  local p = find_wet_param_index(track, fxIdx)
  if p == nil then return false end
  local nv = math.max(0, math.min(1, tonumber(v) or 0))
  r.TrackFX_SetParamNormalized(track, fxIdx, p, nv)
  return true
end

local function knob_widget(id, v, size)
  local changed, out = false, v or 0
  local w, h = size, size
  local cx, cy
  local px, py = r.ImGui_GetCursorScreenPos(ctx)
  cx, cy = px + w * 0.5, py + h * 0.5
  r.ImGui_InvisibleButton(ctx, id, w, h)
  local active = r.ImGui_IsItemActive(ctx)
  local hovered = r.ImGui_IsItemHovered(ctx)
  if active then
    local dx, dy = 0, 0
    if r.ImGui_GetMouseDelta then dx, dy = r.ImGui_GetMouseDelta(ctx) end
    out = out - (dy or 0) * 0.005 - (dx or 0) * 0.000
    if r.ImGui_GetIO and r.ImGui_ModFlags_Ctrl and r.ImGui_GetIO(ctx) then
      if r.ImGui_GetIO(ctx).KeyCtrl then out = out - (dy or 0) * 0.004 end
    end
    if r.ImGui_IsKeyDown and r.ImGui_Key_ModCtrl and r.ImGui_IsKeyDown(ctx, r.ImGui_Key_ModCtrl()) then out = out - (dy or 0) * 0.004 end
    out = math.max(0, math.min(1, out))
    changed = (out ~= v)
  end
  local dl = r.ImGui_GetWindowDrawList and r.ImGui_GetWindowDrawList(ctx) or nil
  if dl and r.ImGui_DrawList_AddCircleFilled and r.ImGui_DrawList_AddLine then
    local radius = math.min(w, h) * 0.48
    local baseCol = hovered and col_u32(0.50,0.50,0.50,1.0) or col_u32(0.40,0.40,0.40,1.0)
    r.ImGui_DrawList_AddCircleFilled(dl, cx, cy, radius, baseCol)
    local ringR = radius + 2.0
    local ringCol = hovered and col_u32(0.35,0.35,0.35,1.0) or col_u32(0.25,0.25,0.25,1.0)
    if r.ImGui_DrawList_AddCircle then r.ImGui_DrawList_AddCircle(dl, cx, cy, ringR, ringCol, 24, 1.5) end
    local a_top = -0.5 * math.pi
    local sweep = 1.5 * math.pi
    local a0 = a_top + sweep
    local a1 = a_top
    local ang = a0 + (a1 - a0) * (out or 0)
    local hx = cx + math.cos(ang) * (radius * 0.75)
    local hy = cy + math.sin(ang) * (radius * 0.75)
    r.ImGui_DrawList_AddLine(dl, cx, cy, hx, hy, col_u32(0.10,0.10,0.10,1.0), 2.0)
  else
    r.ImGui_SliderFloat(ctx, id .. '##slider', out, 0.0, 1.0)
  end
  return changed, out
end

local function snapshot_fx(track, fxIdx)
  local snap = { params = {} }
  snap.slotIndex = fxIdx
  snap.enabled = get_fx_enabled(track, fxIdx)
  snap.offline = get_fx_offline(track, fxIdx)
  local _, fxname = r.TrackFX_GetFXName(track, fxIdx, '')
  snap.srcAddName = fxname
  local ok, renamed = pcall(function() return select(2, r.TrackFX_GetNamedConfigParm(track, fxIdx, 'renamed')) end)
  if ok and renamed and renamed ~= '' then snap.renamed = renamed end
  local pc = r.TrackFX_GetNumParams(track, fxIdx) or 0
  snap.paramCount = pc
  for i=0, pc-1 do
    local val = r.TrackFX_GetParamNormalized(track, fxIdx, i)
    snap.params[i] = val
  end
  return snap
end

local function restore_fx_to_slot(track, slotIndex, snap)
  if not (snap and snap.srcAddName) then return end
  local addIdx = r.TrackFX_AddByName(track, snap.srcAddName, false, -1)
  if addIdx and addIdx >= 0 then
    r.TrackFX_CopyToTrack(track, addIdx, track, slotIndex, true)
    
    local pcNew = r.TrackFX_GetNumParams(track, slotIndex) or 0
    local maxp = math.min(pcNew, snap.paramCount or 0)
    for i=0, maxp-1 do
      r.TrackFX_SetParamNormalized(track, slotIndex, i, snap.params[i] or 0)
    end
    if snap.renamed and snap.renamed ~= '' then rename_fx_instance(track, slotIndex, snap.renamed) end
    if snap.enabled ~= nil then set_fx_enabled(track, slotIndex, snap.enabled) end
    if snap.offline ~= nil then set_fx_offline(track, slotIndex, snap.offline) end
  end
end

local function ensure_ab_pair()
  local tr = get_selected_track()
  if not tr then state.pendingError = 'No selected track'; return false end
  local i = tonumber(state.selectedSourceFXIndex)
  if i == nil then state.pendingError = 'No Source slot selected'; return false end
  
  local addName, alias
  if state.useDummyReplace then
    addName = ensure_tk_blank_addname(state.placeholderCustomName)
    alias = state.placeholderCustomName
  else
    addName = state.replaceWith
  end
  if not addName or addName == '' then state.pendingError = 'No replacement selected'; return false end

  local fxCount = r.TrackFX_GetCount(tr)
  if i < 0 or i >= fxCount then state.pendingError = 'Source index out of range'; return false end

  r.Undo_BeginBlock('A/B prepare (in-slot)')
 
  state.abSnap = snapshot_fx(tr, i)
  state.abSnap.replAddName = addName
  state.abSnap.replAlias = alias
  state.abSlotIndex = i
  
  if r.TrackFX_Delete then pcall(function() r.TrackFX_Delete(tr, i) end) end
 
  local replIdx = r.TrackFX_AddByName(tr, addName, false, -1)
  if replIdx and replIdx >= 0 then
    r.TrackFX_CopyToTrack(tr, replIdx, tr, i, true)
    if alias and alias ~= '' then rename_fx_instance(tr, i, alias) end
    state.abActiveIsRepl = true
    r.Undo_EndBlock('A/B prepare (in-slot)', -1)
    state.pendingMessage = 'A/B ready'
    return true
  else
   
    restore_fx_to_slot(tr, i, state.abSnap)
    r.Undo_EndBlock('A/B prepare (failed)', -1)
    state.abSnap, state.abSlotIndex, state.abActiveIsRepl = nil, nil, false
    state.pendingError = 'Failed to create replacement'
    return false
  end
end

local function ab_toggle()
  local tr = get_selected_track(); if not tr then return end
  local s = tonumber(state.selectedSourceFXIndex)
  if not s then state.pendingError = 'No Source selected'; return end
  if not (state.abSlotIndex == s and state.abSnap and state.abSnap.replAddName) then
    ensure_ab_pair(); return
  end
  r.Undo_BeginBlock('A/B toggle (in-slot)')
  if state.abActiveIsRepl then
  
    if r.TrackFX_Delete then pcall(function() r.TrackFX_Delete(tr, s) end) end
    restore_fx_to_slot(tr, s, state.abSnap)
    state.abActiveIsRepl = false
  else
  
    if r.TrackFX_Delete then pcall(function() r.TrackFX_Delete(tr, s) end) end
    local replIdx = r.TrackFX_AddByName(tr, state.abSnap.replAddName, false, -1)
    if replIdx and replIdx >= 0 then
      r.TrackFX_CopyToTrack(tr, replIdx, tr, s, true)
      if state.abSnap.replAlias and state.abSnap.replAlias ~= '' then rename_fx_instance(tr, s, state.abSnap.replAlias) end
      state.abActiveIsRepl = true
    end
  end
  r.Undo_EndBlock('A/B toggle (in-slot)', -1)
  state.pendingMessage = state.abActiveIsRepl and 'B active (in slot)' or 'A active (in slot)'
end

local function ab_commit()
  local tr = get_selected_track(); if not tr then return end
  local a, b, orig = state.abAIndex, state.abBIndex, state.abOrigIndex
  if not (a and b and orig) then state.pendingError = 'A/B not prepared'; return end
  local keepIdx = state.abBActive and b or a
  local dropIdx = state.abBActive and a or b
  r.Undo_BeginBlock('Replace Source with A/B selection')
 
  if keepIdx ~= orig then
    local dest = orig
   
    if keepIdx > dest then dest = dest end
    r.TrackFX_CopyToTrack(tr, keepIdx, tr, dest, true)
  
    if dropIdx > keepIdx and keepIdx <= dest then dropIdx = dropIdx - 1 end
  end
 
  if r.TrackFX_Delete then pcall(function() r.TrackFX_Delete(tr, dropIdx) end) end
  r.Undo_EndBlock('Replace Source with A/B selection', -1)
  state.pendingMessage = 'Source replaced'
  state.abAIndex, state.abBIndex, state.abOrigIndex = nil, nil, nil
end

local function ab_cancel()
  local tr = get_selected_track(); if not tr then return end
  if not (state.abSnap and state.abSlotIndex) then return end
  r.Undo_BeginBlock('Cancel A/B and restore source (in-slot)')
  local s = state.abSlotIndex or tonumber(state.selectedSourceFXIndex) or 0

  if state.abActiveIsRepl then
    if r.TrackFX_Delete then pcall(function() r.TrackFX_Delete(tr, s) end) end
    restore_fx_to_slot(tr, s, state.abSnap)
  end
  r.Undo_EndBlock('Cancel A/B and restore source (in-slot)', -1)
  state.pendingMessage = 'A/B canceled'
  state.abSlotIndex, state.abSnap, state.abActiveIsRepl = nil, nil, false
end

local function replace_fx_at(track, fxIdx, fxName, overridePos, newPos, insertIndex)
  if not track then return false, 'Track missing' end
  local placeIdx = fxIdx
  if overridePos then
    if newPos == 'end' then
      placeIdx = FX_END
    elseif newPos == 'begin' then
      placeIdx = 0
    elseif newPos == 'index' then
      placeIdx = math.max(0, tonumber(insertIndex or 0) or 0)
    else
      placeIdx = fxIdx
    end
  end
  local fxCountBefore = r.TrackFX_GetCount(track)
  if fxIdx < 0 or fxIdx >= fxCountBefore then return false, 'Invalid FX index' end
  r.TrackFX_Delete(track, fxIdx)
  local newIdx = r.TrackFX_AddByName(track, fxName, false, -1)
  if newIdx < 0 then return false, ('FX "%s" not found'):format(fxName) end
  if placeIdx == FX_END then
    r.TrackFX_CopyToTrack(track, newIdx, track, FX_END, true)
  elseif placeIdx == 0 then
    r.TrackFX_CopyToTrack(track, newIdx, track, 0, true)
  elseif placeIdx == fxIdx then
    r.TrackFX_CopyToTrack(track, newIdx, track, fxIdx, true)
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
    local idxs = {}
    for i = 0, fxCount - 1 do
      local nm = get_fx_name(tr, i)
      if nm == sourceName then idxs[#idxs+1] = i end
    end
    table.sort(idxs, function(a,b) return a>b end)
    for _, i in ipairs(idxs) do
      local ok, err = replace_fx_at(tr, i, replacementName, state.insertOverride, state.insertPos, state.insertIndex)
      if ok then replaced = replaced + 1 else state.pendingError = err end
    end
  end
  r.Undo_EndBlock(('Replace all "%s" with "%s"'):format(sourceName, replacementName), -1)
  return replaced
end

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
      r.ShowMessageBox('Sexan FX Browser Parser V7 is missing. Opening ReaPack to install.', SCRIPT_NAME, 0)
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
  if okParser == false and err then return nil, err end
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

local function get_cache_path()
  local sep = package.config:sub(1,1)
  local base = r.GetResourcePath() .. sep .. 'Scripts' .. sep .. 'TK Scripts' .. sep .. 'FX'
  return base .. sep .. 'TK_FX_Picker_Cache.tsv'
end


local function read_cache_items()
  local path = get_cache_path()
  local f = io.open(path, 'r')
  if not f then return nil, 'No cache' end
  local items = {}
  for line in f:lines() do
    if line and line ~= '' then
      local add, disp = line:match('^(.-)\t(.-)$')
      add = add or line
      disp = disp ~= '' and disp or add
      if add and add ~= '' then items[#items+1] = { addname = add, display = disp } end
    end
  end
  f:close()
  if #items == 0 then return nil, 'Empty cache' end
  return items
end


local function write_cache_items(items)
  local path = get_cache_path()
  local f, err = io.open(path, 'w')
  if not f then return false, err end
  for _, it in ipairs(items or {}) do
    local add = tostring(it.addname or '')
    local disp = tostring(it.display or '')
    if add ~= '' then f:write(add, '\t', disp, '\n') end
  end
  f:close()
  return true
end


local function ensure_picker_items()
  if state.pickerItems and type(state.pickerItems) == 'table' and #state.pickerItems > 0 then return end
 
  local items, err = read_cache_items()
  if items then
    state.pickerItems = items
    state.pickerLoadedFromCache = true
    state.pickerErr = nil
    state.pickerTriedCache = true
    return
  end
  state.pickerTriedCache = true
 
  local built, perr = load_plugin_items()
  if built then
    state.pickerItems = built
    state.pickerLoadedFromCache = false
    state.pickerErr = nil
    pcall(write_cache_items, built)
  else
    state.pickerErr = perr or 'Failed to load plugin list'
  end
end

local function get_screenshots_dir()
  local sep = package.config:sub(1,1)
  return r.GetResourcePath() .. sep .. 'Scripts' .. sep .. 'TK Scripts' .. sep .. 'FX' .. sep .. 'Screenshots'
end

local function sanitize_filename(s)
  local t = tostring(s or '')
  t = t:gsub('[\\/:%*%?"<>|]', ' ')
  t = t:gsub('%s+', ' ')
  t = t:gsub('^%s+', ''):gsub('%s+$', '')
  return t
end

local function parse_name_vendor(add)
  local s = tostring(add or '')
  local name, vendor = s:match('^%w+:%s*(.-)%s*%((.-)%)')
  if not name then
    name = s:match('^%w+:%s*(.+)$') or s
  end
  return name, vendor
end

local function build_screenshot_candidates(add)
  local typ = parse_addname_type(add)
  local name, vendor = parse_name_vendor(add)
  name = sanitize_filename(name)
  local list = {}
  if vendor and vendor ~= '' then
    local vend = sanitize_filename(vendor)
    list[#list+1] = string.format('%s_ %s _%s_.png', typ, name, vend)
    list[#list+1] = string.format('%s_ %s _%s_.jpg', typ, name, vend)
  end
  list[#list+1] = string.format('%s_ %s.png', typ, name)
  list[#list+1] = string.format('%s_ %s.jpg', typ, name)
  list[#list+1] = string.format('%s.png', name)
  list[#list+1] = string.format('%s.jpg', name)
  return list
end

local function find_screenshot_path(add)
  local dir = get_screenshots_dir()
  local sep = package.config:sub(1,1)
  for _, fn in ipairs(build_screenshot_candidates(add)) do
    local p = dir .. sep .. fn
    if file_exists(p) then return p end
  end
  return nil
end

local function release_screenshot()
  if state.screenshotTex and r.ImGui_DestroyImage then
    pcall(function() r.ImGui_DestroyImage(state.screenshotTex) end)
  end
  state.screenshotTex = nil
  state.screenshotFound = false
  state.screenshotKey = nil
end

local function ensure_source_screenshot(add)
  if not add or add == '' then release_screenshot(); return end
  if state.screenshotKey == add and (state.screenshotTex or state.screenshotFound) then return end
  release_screenshot()
  if not r.ImGui_CreateImage then state.screenshotKey = add; state.screenshotFound = false; return end
  local path = find_screenshot_path(add)
  if path then
    local ok, tex = pcall(function() return r.ImGui_CreateImage(path) end)
    if ok and tex then
      state.screenshotTex = tex
      state.screenshotFound = true
      state.screenshotKey = add
      return
    end
  end
  state.screenshotKey = add
  state.screenshotFound = false
end


local function delete_all_instances(sourceName, placeholderAdd, placeholderAlias)
  if not sourceName or sourceName == '' then return 0, 'No source FX selected' end
  local deleted = 0
  r.Undo_BeginBlock()
  for tr, _ in tracks_iter(state.scopeSelectedOnly) do
    local fxCount = r.TrackFX_GetCount(tr)
    local idxs = {}
    for i = 0, fxCount - 1 do
      local nm = get_fx_name(tr, i)
      if nm == sourceName then idxs[#idxs+1] = i end
    end
    table.sort(idxs, function(a,b) return a>b end)
    for _, i in ipairs(idxs) do
      if pcall(function() r.TrackFX_Delete(tr, i) end) then
        deleted = deleted + 1
        if placeholderAdd and placeholderAdd ~= '' then
          local newIdx = r.TrackFX_AddByName(tr, placeholderAdd, false, -1)
          if newIdx >= 0 then
            r.TrackFX_CopyToTrack(tr, newIdx, tr, i, true)
            if placeholderAlias and placeholderAlias ~= '' then rename_fx_instance(tr, i, placeholderAlias) end
          end
        end
      end
    end
  end
  local withPH = (placeholderAdd and placeholderAdd ~= '') and ' + placeholders' or ''
  r.Undo_EndBlock(('Delete all instances of "%s"%s'):format(sourceName, withPH), -1)
  return deleted
end

local function replace_by_slot_across_tracks(slotIndex0, replacementName, aliasName, onlyIfName)
  if not replacementName or replacementName == '' then return 0, 'No replacement plugin selected' end
  local slot = tonumber(slotIndex0) or 0
  if slot < 0 then return 0, 'Invalid slot index' end
  local replaced = 0
  r.Undo_BeginBlock()
  for tr, _ in tracks_iter(state.scopeSelectedOnly) do
    local fxCount = r.TrackFX_GetCount(tr)
    if fxCount > slot then
      if onlyIfName and onlyIfName ~= '' then
        local atName = get_fx_name(tr, slot)
        if atName ~= onlyIfName then goto next_track end
      end
      local ok, err = replace_fx_at(tr, slot, replacementName, true, 'in_place', 0)
      if ok then replaced = replaced + 1 else state.pendingError = err end
      if ok and aliasName and aliasName ~= '' then rename_fx_instance(tr, slot, aliasName) end
    end
    ::next_track::
  end
  r.Undo_EndBlock(('Replace slot #%d across tracks with "%s"'):format((slot or 0) + 1, replacementName), -1)
  return replaced
end

local function normalize_fx_label(s)
  if not s or s == '' then return '' end
  local t = tostring(s)
  local pos = t:find(':')
  if pos then t = t:sub(pos + 1) end
  t = t:gsub('^%s+', '')
  return t:lower()
end

local function format_fx_display_name(s)
  local t = tostring(s or '')
  if t == '' then return t end
  if state.nameNoPrefix then
    local pos = t:find(':')
    if pos and pos < 10 then
      t = t:sub(pos + 1)
      t = t:gsub('^%s+', '')
    end
  end
  if state.nameHideDeveloper then
    t = t:gsub('%s*%(([^()]*)%)%s*$', '')
  end
  return t
end

local function add_by_slot_across_tracks(slotIndex0, pluginName, aliasName)
  if not pluginName or pluginName == '' then return 0, 'No plugin selected' end
  local slot = tonumber(slotIndex0) or 0
  if slot < 0 then return 0, 'Invalid slot index' end
  local added = 0
  r.Undo_BeginBlock()
  for tr, _ in tracks_iter(state.scopeSelectedOnly) do
    local fxCount = r.TrackFX_GetCount(tr)
    local destIdx
    if slot < fxCount then
      local atName = get_fx_name(tr, slot)
      if normalize_fx_label(atName) ~= normalize_fx_label(pluginName) then
        destIdx = slot
      end
    else
      destIdx = FX_END
    end
    if destIdx ~= nil then
      local newIdx = r.TrackFX_AddByName(tr, pluginName, false, -1)
      if newIdx >= 0 then
        r.TrackFX_CopyToTrack(tr, newIdx, tr, destIdx, true)
        if aliasName and aliasName ~= '' then rename_fx_instance(tr, (destIdx == FX_END) and r.TrackFX_GetCount(tr)-1 or destIdx, aliasName) end
        added = added + 1
      end
    end
  end
  r.Undo_EndBlock(('Add "%s" at slot #%d across tracks'):format(pluginName, (slot or 0) + 1), -1)
  return added
end

local function compute_preview()
  local scopeSel = state.scopeSelectedOnly
  local source = state.selectedSourceFXName or ''
  local act = state.actionType or 'replace_all'
  local slot = tonumber(state.batchSlotIndex) or 0
  local countTracks, countChanges = 0, 0
  for tr, _ in tracks_iter(scopeSel) do
    local fxCount = r.TrackFX_GetCount(tr)
    local trackHasChange = false
    if act == 'replace_all' or act == 'delete_all' then
      for i = 0, fxCount - 1 do
        local nm = get_fx_name(tr, i)
        if nm == source then countChanges = countChanges + 1; trackHasChange = true end
      end
    elseif act == 'replace_slot' or act == 'add_slot' then
      if act == 'replace_slot' then
        if fxCount > slot then
          if state.slotMatchSourceOnly then
            local atName = get_fx_name(tr, slot)
            if atName == source then countChanges = countChanges + 1; trackHasChange = true end
          else
            countChanges = countChanges + 1; trackHasChange = true
          end
        end
      else 
        local destIdx
        if slot < fxCount then
          local atName = get_fx_name(tr, slot)
          if normalize_fx_label(atName) ~= normalize_fx_label(state.replaceWith or '') then destIdx = slot end
        else destIdx = FX_END end
        if destIdx ~= nil then countChanges = countChanges + 1; trackHasChange = true end
      end
    end
    if trackHasChange then countTracks = countTracks + 1 end
  end
  return countTracks, countChanges
end

local function SeparatorText(label)
  local txt = tostring(label or '')
  if r.ImGui_SeparatorText then
    local ok = pcall(function() r.ImGui_SeparatorText(ctx, txt) end)
    if ok then return end
  end
  if r.ImGui_Text and r.ImGui_Separator then
    r.ImGui_Text(ctx, txt)
    r.ImGui_Separator(ctx)
  end
end

 
local function draw_replace_panel()
  do
    if state.replHeaderOpen then r.ImGui_SetNextItemOpen(ctx, true, r.ImGui_Cond_FirstUseEver()) end
    local open = r.ImGui_CollapsingHeader(ctx, 'Replacement', 0)
    if open ~= nil and open ~= state.replHeaderOpen then state.replHeaderOpen = open; save_user_settings() end
  if open then

  local chgSel, vSel = r.ImGui_Checkbox(ctx, 'Selected tracks only', state.scopeSelectedOnly)
  if chgSel then state.scopeSelectedOnly = vSel end
  if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then r.ImGui_SetTooltip(ctx, 'Limit to selected tracks, otherwise all tracks') end

  
  local chgDummy, vDummy = r.ImGui_Checkbox(ctx, 'Use placeholder', state.useDummyReplace)
  if chgDummy then state.useDummyReplace = vDummy end
  if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then r.ImGui_SetTooltip(ctx, 'Use a dummy "TK Blank" FX as the replacement') end
  if state.useDummyReplace then
    if not state.tkBlankVariants then refresh_tk_blank_variants() end
    r.ImGui_SetNextItemWidth(ctx, 100)
    local openedDV = r.ImGui_BeginCombo(ctx, '##dvariants', state.placeholderVariantName or 'Variant…')
    if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then r.ImGui_SetTooltip(ctx, 'Choose a preset variant; the name field stays unless empty') end
    if openedDV then
    for i, v in ipairs(state.tkBlankVariants or {}) do
        local sel = (state.placeholderVariantName == v.name)
        if r.ImGui_Selectable(ctx, v.name, sel) then
          state.placeholderVariantName = v.name

      state.placeholderCustomName = v.name

      local addName = ensure_tk_blank_addname(v.name)
      state.replaceWith = addName
      state.replaceDisplay = v.name
      state.pendingMessage = 'Placeholder ready: ' .. tostring(v.name)
        end
      end
      r.ImGui_EndCombo(ctx)
    end
    r.ImGui_SameLine(ctx)
    r.ImGui_SetNextItemWidth(ctx, 110)
    local chgAlias, alias
    local flags = 0
    if r.ImGui_InputTextFlags_EnterReturnsTrue then flags = flags | r.ImGui_InputTextFlags_EnterReturnsTrue() end
    if r.ImGui_InputTextFlags_AutoSelectAll then flags = flags | r.ImGui_InputTextFlags_AutoSelectAll() end
    if r.ImGui_InputTextWithHint then
      chgAlias, alias = r.ImGui_InputTextWithHint(ctx, '##ph_alias', 'name…', state.placeholderCustomName, flags)
    else
      chgAlias, alias = r.ImGui_InputText(ctx, '##ph_alias', state.placeholderCustomName, flags)
    end
    local commit = false
    if r.ImGui_InputTextFlags_EnterReturnsTrue and flags ~= 0 then
      commit = chgAlias
    elseif r.ImGui_IsItemDeactivatedAfterEdit then
      commit = r.ImGui_IsItemDeactivatedAfterEdit(ctx)
    end
    if chgAlias then state.placeholderCustomName = alias end
    if commit and alias and alias ~= '' then
      local addName = ensure_tk_blank_addname(alias)
    
      state.replaceWith = addName
      state.replaceDisplay = alias
      state.pendingMessage = 'Placeholder ready: ' .. tostring(alias)
  if blanks_add then blanks_add(alias) end
    end
    if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then r.ImGui_SetTooltip(ctx, 'Optional: type a custom display name for the placeholder') end
  else
    r.ImGui_SetNextItemWidth(ctx, 100)
  local preview = (state.replaceDisplay ~= '' and state.replaceDisplay) or 'My Favorites'
    local openedSL = r.ImGui_BeginCombo(ctx, '##shortlist', preview)
  if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then r.ImGui_SetTooltip(ctx, 'Pick a favorite replacement from My Favorites') end
    if openedSL then
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
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, 'Pick from list…', 100) then state.showPicker = true end
    if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then r.ImGui_SetTooltip(ctx, 'Open the full FX list with filters and search') end
  end

  end 
  r.ImGui_Dummy(ctx, 0, 4)
  end 

  do
    if state.actionHeaderOpen then r.ImGui_SetNextItemOpen(ctx, true, r.ImGui_Cond_FirstUseEver()) end
    local open = r.ImGui_CollapsingHeader(ctx, 'Action', 0)
    if open ~= nil and open ~= state.actionHeaderOpen then state.actionHeaderOpen = open; save_user_settings() end
    if open then
      local act = state.actionType
      local actLabel = (act == 'replace_all' and 'Replace everywhere')
                    or (act == 'delete_all' and 'Delete source')
                    or (act == 'replace_slot' and 'Replace slot')
                    or (act == 'add_slot' and 'Add at slot')
                    or 'Replace everywhere'
      r.ImGui_SetNextItemWidth(ctx, 210)
      local openedACT = r.ImGui_BeginCombo(ctx, '##action_combo', actLabel)
      if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then r.ImGui_SetTooltip(ctx, 'Choose the operation: Replace/Delete across tracks or Slot-based actions') end
      if openedACT then
        if r.ImGui_Selectable(ctx, 'Replace everywhere', act == 'replace_all') then state.actionType = 'replace_all' end
        if r.ImGui_Selectable(ctx, 'Delete source', act == 'delete_all') then state.actionType = 'delete_all' end
        if r.ImGui_Selectable(ctx, 'Replace slot', act == 'replace_slot') then state.actionType = 'replace_slot' end
        if r.ImGui_Selectable(ctx, 'Add at slot', act == 'add_slot') then state.actionType = 'add_slot' end
        r.ImGui_EndCombo(ctx)
      end
      
      if state.tooltips and state.actionType == 'delete_all' and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then
        r.ImGui_SetTooltip(ctx, 'Want to keep the slot/position? Choose Replacement -> Use placeholder.')
      end

      if state.actionType == 'replace_slot' or state.actionType == 'add_slot' then
        r.ImGui_SetNextItemWidth(ctx, 100)
        local chgSlot, slot1 = r.ImGui_InputInt(ctx, '##slot1', (tonumber(state.batchSlotIndex) or 0) + 1)
        if chgSlot then state.batchSlotIndex = math.max(0, (tonumber(slot1) or 1) - 1) end
        if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then r.ImGui_SetTooltip(ctx, '1-based slot index across tracks') end
        r.ImGui_SameLine(ctx)
        if state.actionType == 'replace_slot' then
          local chgMS, vMS = r.ImGui_Checkbox(ctx, 'Match source', state.slotMatchSourceOnly)
          if chgMS then state.slotMatchSourceOnly = vMS end
          if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then r.ImGui_SetTooltip(ctx, 'Only replace when the slot already contains the Source FX') end
        end
      end

      if state.actionType == 'replace_all' then
        r.ImGui_Text(ctx, 'Placement:')
        local sel = state.insertPos
        local placeLabel = (sel == 'in_place' and 'Same slot')
                        or (sel == 'begin' and 'Start')
                        or (sel == 'end' and 'End')
                        or (sel == 'index' and 'Index')
                        or 'Same slot'
        r.ImGui_SameLine(ctx)
        r.ImGui_SetNextItemWidth(ctx, 70)
        local openedPLC = r.ImGui_BeginCombo(ctx, '##placement_combo', placeLabel)
        if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then r.ImGui_SetTooltip(ctx, 'Where to put the replacement within each track') end
        if openedPLC then
          if r.ImGui_Selectable(ctx, 'Same slot', sel == 'in_place') then state.insertPos = 'in_place' end
          if r.ImGui_Selectable(ctx, 'Start', sel == 'begin') then state.insertPos = 'begin' end
          if r.ImGui_Selectable(ctx, 'End', sel == 'end') then state.insertPos = 'end' end
          if r.ImGui_Selectable(ctx, 'Index', sel == 'index') then state.insertPos = 'index' end
          r.ImGui_EndCombo(ctx)
        end
        if state.insertPos == 'index' then
          r.ImGui_SameLine(ctx)
          r.ImGui_SetNextItemWidth(ctx, 65)
          local changed2, val = r.ImGui_InputInt(ctx, '##ins_idx', (tonumber(state.insertIndex) or 0) + 1)
          if changed2 then state.insertIndex = math.max(0, (tonumber(val) or 1) - 1) end
          if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then r.ImGui_SetTooltip(ctx, '1-based destination index for placement') end
        end
      end

      r.ImGui_Dummy(ctx, 0, 4)
    end
  end

  local tracksAffected, changes = compute_preview()
  do
    local s = string.format('Preview: %d change(s) on %d track(s)', changes, tracksAffected)
    local tw = select(1, r.ImGui_CalcTextSize(ctx, s)) or 0
    local availW = select(1, r.ImGui_GetContentRegionAvail(ctx)) or 0
    local curX = select(1, r.ImGui_GetCursorPos(ctx)) or 0
    r.ImGui_SetCursorPosX(ctx, curX + math.max(0, (availW - tw) * 0.5))
    r.ImGui_Text(ctx, s)
  end
  r.ImGui_Dummy(ctx, 0, 4)
  local canExecute = true
  if not state.selectedSourceFXName or state.selectedSourceFXName == '' then canExecute = false end
  if state.actionType ~= 'delete_all' then
    if not state.useDummyReplace and (not state.replaceWith or state.replaceWith == '') then canExecute = false end
  end
  if changes <= 0 then canExecute = false end

  if not canExecute and r.ImGui_BeginDisabled then r.ImGui_BeginDisabled(ctx) end

  local exPush = 0
  if r.ImGui_PushStyleColor then
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(),        col_u32(0.22, 0.40, 0.62, 1.0)); exPush = exPush + 1
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), col_u32(0.28, 0.50, 0.75, 1.0)); exPush = exPush + 1
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(),  col_u32(0.18, 0.34, 0.54, 1.0)); exPush = exPush + 1
  end
  do
    local availW = select(1, r.ImGui_GetContentRegionAvail(ctx)) or 0
    local btnW = 100
    local curX = select(1, r.ImGui_GetCursorPos(ctx)) or 0
    r.ImGui_SetCursorPosX(ctx, curX + math.max(0, (availW - btnW) * 0.5))
  end
  if r.ImGui_Button(ctx, 'Execute', 100, 0) then
    local source = state.selectedSourceFXName
    local addName, alias = nil, nil
    if state.useDummyReplace then
      addName = ensure_tk_blank_addname(state.placeholderCustomName)
      alias = state.placeholderCustomName
    else
      addName = state.replaceWith
    end
    if state.actionType == 'replace_all' then
      local cnt = select(1, replace_all_instances(source, addName))
      state.pendingMessage = string.format('%d instances replaced.', cnt)
    elseif state.actionType == 'delete_all' then
      local cnt = select(1, delete_all_instances(source, nil, nil))
      state.pendingMessage = string.format('%d instances deleted.', cnt)
    elseif state.actionType == 'replace_slot' then
      local onlyIf = (state.slotMatchSourceOnly and source) or nil
      local cnt = select(1, replace_by_slot_across_tracks(state.batchSlotIndex, addName, alias, onlyIf))
      state.pendingMessage = string.format('Replaced on %d track(s).', cnt)
    elseif state.actionType == 'add_slot' then
      local cnt = select(1, add_by_slot_across_tracks(state.batchSlotIndex, addName, alias))
      state.pendingMessage = string.format('Added on %d track(s).', cnt)
    end
  end
  if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then r.ImGui_SetTooltip(ctx, 'Apply the changes shown in the preview') end
  if exPush > 0 and r.ImGui_PopStyleColor then r.ImGui_PopStyleColor(ctx, exPush) end
  if not canExecute and r.ImGui_EndDisabled then r.ImGui_EndDisabled(ctx) end

  r.ImGui_Dummy(ctx, 0, 10)
  do
    if state.sourceHeaderOpen then r.ImGui_SetNextItemOpen(ctx, true, r.ImGui_Cond_FirstUseEver()) end
    local prevOpen = state.sourceHeaderOpen
    local open = r.ImGui_CollapsingHeader(ctx, 'Source Controls', 0)
    if open ~= nil and open ~= state.sourceHeaderOpen then state.sourceHeaderOpen = open; save_user_settings() end
    if open ~= nil and open ~= prevOpen then
      release_screenshot()
    end
    if not open then return end
  end
  local tr = get_selected_track()
  local srcIdx = tonumber(state.selectedSourceFXIndex)
  if tr and srcIdx then
    if state.abSlotIndex and state.abSlotIndex ~= srcIdx then

      if state.abActiveIsRepl then ab_cancel() else
 
        state.abSlotIndex, state.abSnap, state.abActiveIsRepl = nil, nil, false
      end
    end
    local prepared = (state.abSlotIndex == srcIdx) and (state.abSnap ~= nil)
    local srcCtrlIdx = srcIdx

    do
      local sname = state.selectedSourceFXName
      if not sname or sname == '' then local _, nm = r.TrackFX_GetFXName(tr, srcIdx, ''); sname = nm end
      local disp = format_fx_display_name(sname)
      r.ImGui_Text(ctx, 'Source: ' .. tostring(disp or ''))
    end

    do
      local en = get_fx_enabled(tr, srcCtrlIdx)
      local bypassActive = (en ~= nil) and (not en)
      local pushed = 0
      if bypassActive and r.ImGui_PushStyleColor then
        local br,bg,bb = 0.45, 0.35, 0.10
        local hr,hg,hb = lighten(br,bg,bb, 0.10)
        local ar,ag,ab = lighten(br,bg,bb, -0.08)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(),        col_u32(br,bg,bb,1.0)); pushed = pushed + 1
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), col_u32(hr,hg,hb,1.0)); pushed = pushed + 1
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(),  col_u32(ar,ag,ab,1.0)); pushed = pushed + 1
      end
      if r.ImGui_SmallButton(ctx, 'Bypass') then
        local en2 = get_fx_enabled(tr, srcCtrlIdx)
        set_fx_enabled(tr, srcCtrlIdx, en2 == nil and false or (not en2))
      end
      if pushed > 0 and r.ImGui_PopStyleColor then r.ImGui_PopStyleColor(ctx, pushed) end
    end
    if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then r.ImGui_SetTooltip(ctx, 'Toggle bypass for the selected source FX') end
    r.ImGui_SameLine(ctx)
    do
      local off = get_fx_offline(tr, srcCtrlIdx)
      local offActive = (off ~= nil) and off
      local pushed = 0
      if offActive and r.ImGui_PushStyleColor then
        local br,bg,bb = 0.38, 0.20, 0.20
        local hr,hg,hb = lighten(br,bg,bb, 0.10)
        local ar,ag,ab = lighten(br,bg,bb, -0.08)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(),        col_u32(br,bg,bb,1.0)); pushed = pushed + 1
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), col_u32(hr,hg,hb,1.0)); pushed = pushed + 1
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(),  col_u32(ar,ag,ab,1.0)); pushed = pushed + 1
      end
      if r.ImGui_SmallButton(ctx, 'Offline') then
        local off2 = get_fx_offline(tr, srcCtrlIdx)
        set_fx_offline(tr, srcCtrlIdx, off2 == nil and true or (not off2))
      end
      if pushed > 0 and r.ImGui_PopStyleColor then r.ImGui_PopStyleColor(ctx, pushed) end
    end
  if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then r.ImGui_SetTooltip(ctx, 'Toggle offline for the selected source FX') end

    r.ImGui_SameLine(ctx)
    do
      local dstate = get_fx_delta_active(tr, srcCtrlIdx)
      local pushed = 0
      if dstate ~= nil and dstate and r.ImGui_PushStyleColor then
        local br,bg,bb = 0.20, 0.38, 0.20
        local hr,hg,hb = lighten(br,bg,bb, 0.10)
        local ar,ag,ab = lighten(br,bg,bb, -0.08)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(),        col_u32(br,bg,bb,1.0)); pushed = pushed + 1
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), col_u32(hr,hg,hb,1.0)); pushed = pushed + 1
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(),  col_u32(ar,ag,ab,1.0)); pushed = pushed + 1
      end
      local disabled = (dstate == nil)
      if disabled and r.ImGui_BeginDisabled then r.ImGui_BeginDisabled(ctx) end
      if r.ImGui_SmallButton(ctx, 'Delta') then toggle_fx_delta(tr, srcCtrlIdx) end
      if disabled and r.ImGui_EndDisabled then r.ImGui_EndDisabled(ctx) end
      if pushed > 0 and r.ImGui_PopStyleColor then r.ImGui_PopStyleColor(ctx, pushed) end
    end
    if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then r.ImGui_SetTooltip(ctx, 'Toggle Delta solo (if the plugin exposes a Delta/Diff parameter)') end

    r.ImGui_SameLine(ctx)
    
  local abEnabled = true
    if not state.useDummyReplace and (not state.replaceWith or state.replaceWith == '') then abEnabled = false end
    if not abEnabled and r.ImGui_BeginDisabled then r.ImGui_BeginDisabled(ctx) end
    local abPush = 0
    if r.ImGui_PushStyleColor then
      r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(),        col_u32(0.22, 0.40, 0.62, 1.0)); abPush = abPush + 1
      r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), col_u32(0.28, 0.50, 0.75, 1.0)); abPush = abPush + 1
      r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(),  col_u32(0.18, 0.34, 0.54, 1.0)); abPush = abPush + 1
    end
    if r.ImGui_Button(ctx, 'A/B', 48, 0) then
    
  if not (state.abSlotIndex == srcIdx and state.abSnap) then ensure_ab_pair() else ab_toggle() end
    end
    if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then r.ImGui_SetTooltip(ctx, 'Switch between Source and Replacement. First press prepares the pair, next presses toggle.') end
    if abPush > 0 and r.ImGui_PopStyleColor then r.ImGui_PopStyleColor(ctx, abPush) end
    if not abEnabled and r.ImGui_EndDisabled then r.ImGui_EndDisabled(ctx) end

    r.ImGui_Dummy(ctx, 0, 6)
    local mixVal = get_fx_overall_wet(tr, srcCtrlIdx)
    local size = 36
    local initVal = mixVal or 1.0
    local knobLeft, knobTop
    do
      local availW = select(1, r.ImGui_GetContentRegionAvail(ctx)) or 0
      local curX, curY = r.ImGui_GetCursorPos(ctx)
      local left = curX + math.max(0, (availW - size) * 0.5)
      r.ImGui_SetCursorPosX(ctx, left)
      knobLeft, knobTop = left, curY
    end
    local changed, v = knob_widget('##mix_knob', initVal, size)
    if r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip and state.tooltips then
      r.ImGui_SetTooltip(ctx, 'Overall Wet: ' .. tostring(math.floor((v or 0)*100+0.5)) .. '%')
    end
  if r.ImGui_IsItemHovered(ctx) and r.ImGui_IsMouseDoubleClicked and r.ImGui_IsMouseDoubleClicked(ctx, 0) then v, changed = 1.0, true end
  if r.ImGui_IsItemClicked and r.ImGui_IsItemClicked(ctx, 1) then v, changed = 0.5, true end
    do
      local tw = select(1, r.ImGui_CalcTextSize(ctx, 'Wet: 100%')) or 60
      local centerX = (knobLeft or 0) + size * 0.5
      local curX, curY = r.ImGui_GetCursorPos(ctx)
      r.ImGui_SetCursorPos(ctx, centerX - tw * 0.5, (knobTop or curY) + size + 6)
      r.ImGui_Text(ctx, ('Wet: %d%%'):format(math.floor((v or 0)*100+0.5)))
      r.ImGui_SetCursorPosY(ctx, curY)
    end
    if changed then set_fx_overall_wet(tr, srcCtrlIdx, v) end
  r.ImGui_Dummy(ctx, 0, 30)
    do
      local _, addname = r.TrackFX_GetFXName(tr, srcCtrlIdx, '')
      ensure_source_screenshot(addname)
      local availW = select(1, r.ImGui_GetContentRegionAvail(ctx)) or 0
      local maxW = math.max(120, math.min(280, availW - 8))
      local imgW, imgH = maxW, math.floor(maxW * 0.56)
      if state.screenshotTex then
        local curX = select(1, r.ImGui_GetCursorPos(ctx)) or 0
        local left = curX + math.max(0, (availW - imgW) * 0.5)
        r.ImGui_SetCursorPosX(ctx, left)
        if r.ImGui_Image then
          local ok = pcall(function() r.ImGui_Image(ctx, state.screenshotTex, imgW, imgH) end)
          if not ok then
            release_screenshot()
            local label = 'no image'
            local tw2 = select(1, r.ImGui_CalcTextSize(ctx, label)) or 0
            local curX2 = select(1, r.ImGui_GetCursorPos(ctx)) or 0
            local left2 = curX2 + math.max(0, (availW - tw2) * 0.5)
            r.ImGui_SetCursorPosX(ctx, left2)
            r.ImGui_TextDisabled(ctx, label)
          end
        end
      else
        local label = 'no image'
        local tw = select(1, r.ImGui_CalcTextSize(ctx, label)) or 0
        local curX = select(1, r.ImGui_GetCursorPos(ctx)) or 0
        local left = curX + math.max(0, (availW - tw) * 0.5)
        r.ImGui_SetCursorPosX(ctx, left)
        r.ImGui_TextDisabled(ctx, label)
      end
    end
  else
    r.ImGui_Text(ctx, 'Pick a Source')
  end
end

 
local function draw()
  if not ctx then return end
  if r.ImGui_SetNextWindowSize then r.ImGui_SetNextWindowSize(ctx, state.winW, state.winH, r.ImGui_Cond_FirstUseEver()) end
  if r.ImGui_SetNextWindowSizeConstraints then r.ImGui_SetNextWindowSizeConstraints(ctx, 300, 220, 2000, 1400) end
  local stylePush = push_app_style()
  local visible, open = r.ImGui_Begin(ctx, SCRIPT_NAME, true, r.ImGui_WindowFlags_NoScrollbar() | r.ImGui_WindowFlags_NoScrollWithMouse() | r.ImGui_WindowFlags_NoTitleBar())
  if visible then
    ensure_icon_font()

    
    do
      r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), 8, 6)
      local winX, winY = r.ImGui_GetWindowPos(ctx)
      local curX, curY = r.ImGui_GetCursorPos(ctx)
      r.ImGui_SetCursorPos(ctx, 8, 6)

  local availW = select(1, r.ImGui_GetContentRegionAvail(ctx)) or 0
      local pushedFont = false
      if iconFont and r.ImGui_PushFont then
        local okPush = pcall(function() r.ImGui_PushFont(ctx, iconFont, 12) end)
        pushedFont = okPush
      end
      r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x00000000)
      r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0x00000000)
      r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0x00000000)
      local clicked = false
      if pushedFont then
        clicked = r.ImGui_Button(ctx, '\u{0047}', 18, 18)
      else
        clicked = r.ImGui_Button(ctx, 'Settings', 60, 18)
      end
      if clicked then
        state.showSettings = true
        state.showSettingsPending = true
      end
      r.ImGui_PopStyleColor(ctx, 3)
      if pushedFont and r.ImGui_PopFont then r.ImGui_PopFont(ctx) end

  if true then r.ImGui_SameLine(ctx) end
  if r.ImGui_SmallButton(ctx, 'Help') then state.showHelp = true end
  r.ImGui_SameLine(ctx)
  if r.ImGui_SmallButton(ctx, 'Print') then
        local okP, pathP = print_plugin_list()
        if okP then state.pendingMessage = 'Saved report: ' .. tostring(pathP) else state.pendingError = tostring(pathP) end
      end

  local closeW = (select(1, r.ImGui_CalcTextSize(ctx, 'Close')) or 40)
  local availW2 = select(1, r.ImGui_GetContentRegionAvail(ctx)) or 0
  r.ImGui_SameLine(ctx, math.max(0, availW2 - closeW))
      local pushed = 0
      local function P(col, r1,g1,b1,a1)
        if col and r.ImGui_PushStyleColor then r.ImGui_PushStyleColor(ctx, col(), col_u32(r1,g1,b1,a1)); pushed = pushed + 1 end
      end
      P(r.ImGui_Col_Button,        0.65, 0.15, 0.15, 1.0)
      P(r.ImGui_Col_ButtonHovered, 0.80, 0.20, 0.20, 1.0)
      P(r.ImGui_Col_ButtonActive,  0.55, 0.10, 0.10, 1.0)
  if r.ImGui_SmallButton(ctx, 'Close') then open = false end
      if pushed > 0 and r.ImGui_PopStyleColor then r.ImGui_PopStyleColor(ctx, pushed) end

      r.ImGui_SetCursorPos(ctx, curX, curY + 28)
      r.ImGui_PopStyleVar(ctx)
    end

  local FOOTER_H = 30
  r.ImGui_BeginChild(ctx, 'content_child', -1, -FOOTER_H)
    local tr = get_selected_track()
    if not tr then
      r.ImGui_Text(ctx, 'No track selected. Select a track in REAPER to view its FX.')
    else
      local tnum = get_track_number(tr) or 0
      local tname = get_track_name(tr)
      local hdr = ("%d: %s"):format(tnum, tname)
      
      local rC,gC,bC = get_track_color_rgb(tr)
      local pushedHdr = 0
      if rC and gC and bC then
        local base = col_u32(rC, gC, bC, 1.0)
        local hovR,hovG,hovB = lighten(rC,gC,bC, 0.08)
        local actR,actG,actB = lighten(rC,gC,bC, -0.06)
        if r.ImGui_PushStyleColor then
          r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Header(),        base); pushedHdr = pushedHdr + 1
          r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderHovered(), col_u32(hovR,hovG,hovB,1.0)); pushedHdr = pushedHdr + 1
          r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderActive(),  col_u32(actR,actG,actB,1.0)); pushedHdr = pushedHdr + 1
        end
      end
      
      if not state.hdrInitApplied then
        
        if state.trackHeaderOpen then r.ImGui_SetNextItemOpen(ctx, true, r.ImGui_Cond_Always()) end
        state.hdrInitApplied = true
      end
      local openHdr = r.ImGui_CollapsingHeader(ctx, hdr .. '##seltrack', 0)
      if openHdr ~= nil then
        if state.trackHeaderOpen ~= openHdr then
          state.trackHeaderOpen = openHdr
          r.SetExtState(EXT_NS, 'HDR_OPEN', state.trackHeaderOpen and '1' or '0', true)
        end
      end
      if pushedHdr > 0 and r.ImGui_PopStyleColor then r.ImGui_PopStyleColor(ctx, pushedHdr) end
      if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then
        r.ImGui_SetTooltip(ctx, 'Click to expand/collapse the selected track\'s FX list')
      end

      if openHdr then
        local fxCount = r.TrackFX_GetCount(tr)
        if fxCount <= 0 then
          r.ImGui_Text(ctx, '(No FX on this track)')
        else
          local flags = r.ImGui_TableFlags_SizingFixedFit() | r.ImGui_TableFlags_RowBg()
          if r.ImGui_BeginTable(ctx, 'fx_table_single', 3, flags) then
            r.ImGui_TableSetupColumn(ctx, '#', r.ImGui_TableColumnFlags_WidthFixed(), 20)
            r.ImGui_TableSetupColumn(ctx, 'FX name', r.ImGui_TableColumnFlags_WidthStretch())
            r.ImGui_TableSetupColumn(ctx, 'Source', r.ImGui_TableColumnFlags_WidthFixed(), 56)

            for i = 0, fxCount - 1 do
              r.ImGui_TableNextRow(ctx)
              if r.ImGui_TableSetBgColor and r.ImGui_TableBgTarget_RowBg0 and r.ImGui_TableBgTarget_RowBg1 then
                local isSelected = (tonumber(state.selectedSourceFXIndex) or -1) == i
                if isSelected then
                  local hr, hg, hb, ha = 0.18, 0.28, 0.42, 0.85 
                  r.ImGui_TableSetBgColor(ctx, r.ImGui_TableBgTarget_RowBg0(), col_u32(hr, hg, hb, ha))
                  r.ImGui_TableSetBgColor(ctx, r.ImGui_TableBgTarget_RowBg1(), col_u32(hr, hg, hb, ha))
                else
                  if (i % 2) == 0 then
                    r.ImGui_TableSetBgColor(ctx, r.ImGui_TableBgTarget_RowBg0(), col_u32(0.17, 0.17, 0.17, 1.00))
                  else
                    r.ImGui_TableSetBgColor(ctx, r.ImGui_TableBgTarget_RowBg1(), col_u32(0.23, 0.23, 0.23, 1.00))
                  end
                end
              end

              
              r.ImGui_TableSetColumnIndex(ctx, 0)
              r.ImGui_Text(ctx, tostring(i + 1))

              
              r.ImGui_TableSetColumnIndex(ctx, 1)
              local nm = get_fx_name(tr, i)
              local disp = format_fx_display_name(nm)
              local pushedTxt = 0
              do
                local off = get_fx_offline(tr, i)
                local en = get_fx_enabled(tr, i)
                if off then
                  if r.ImGui_PushStyleColor then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), col_u32(0.90, 0.35, 0.35, 1.0)); pushedTxt = pushedTxt + 1 end
                elseif en ~= nil and not en then
                  if r.ImGui_PushStyleColor then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), col_u32(0.90, 0.75, 0.30, 1.0)); pushedTxt = pushedTxt + 1 end
                end
              end
              local clicked = r.ImGui_Selectable(ctx, (disp .. '##fxrow' .. i), false)
              if pushedTxt > 0 and r.ImGui_PopStyleColor then r.ImGui_PopStyleColor(ctx, pushedTxt) end
              if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then
                r.ImGui_SetTooltip(ctx, 'Click to open FX; drag to reorder')
              end
              if r.ImGui_BeginDragDropSource and r.ImGui_BeginDragDropTarget and r.ImGui_AcceptDragDropPayload and r.ImGui_SetDragDropPayload then
                if r.ImGui_BeginDragDropSource(ctx, 0) then
                  r.ImGui_SetDragDropPayload(ctx, DND_FX_PAYLOAD, tostring(i))
                  r.ImGui_Text(ctx, 'Move: ' .. disp)
                  r.ImGui_EndDragDropSource(ctx)
                end
                if r.ImGui_BeginDragDropTarget(ctx) then
                  local ok, payload = r.ImGui_AcceptDragDropPayload(ctx, DND_FX_PAYLOAD)
                  if ok and payload then
                    local src = tonumber(payload) or -1
                    local dest = i
                    if src >= 0 and src ~= dest then
                      if src < dest then dest = dest + 1 end
                      r.Undo_BeginBlock('Move FX')
                      r.TrackFX_CopyToTrack(tr, src, tr, dest, true)
                      r.Undo_EndBlock('Move FX', -1)
                      state.pendingMessage = string.format('Moved "%s" to position %d', disp, dest + 1)
                    end
                  end
                  r.ImGui_EndDragDropTarget(ctx)
                end
              end

              if clicked and r.TrackFX_Show then
                local hwnd = r.TrackFX_GetFloatingWindow and r.TrackFX_GetFloatingWindow(tr, i) or nil
                local uiOpen = r.TrackFX_GetOpen and r.TrackFX_GetOpen(tr, i) or false
                if hwnd and hwnd ~= 0 then
                  r.TrackFX_Show(tr, i, 2)
                elseif uiOpen then
                  r.TrackFX_Show(tr, i, 0)
                else
                  r.TrackFX_Show(tr, i, 3)
                  hwnd = r.TrackFX_GetFloatingWindow and r.TrackFX_GetFloatingWindow(tr, i) or nil
                  if not (hwnd and hwnd ~= 0) then r.TrackFX_Show(tr, i, 1) end
                end
              end

              
              r.ImGui_TableSetColumnIndex(ctx, 2)
              local pushedSrc = 0
              if r.ImGui_PushStyleColor then
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(),        col_u32(0.18, 0.32, 0.50, 1.0)); pushedSrc = pushedSrc + 1
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), col_u32(0.22, 0.40, 0.62, 1.0)); pushedSrc = pushedSrc + 1
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(),  col_u32(0.14, 0.26, 0.42, 1.0)); pushedSrc = pushedSrc + 1
              end
              r.ImGui_SetCursorPosX(ctx, (select(1, r.ImGui_GetCursorPos(ctx)) or 0) + 8)
              if r.ImGui_SmallButton(ctx, 'Source##' .. i) then
                state.selectedSourceFXName = nm
                state.selectedSourceFXIndex = i
              end
              if pushedSrc > 0 and r.ImGui_PopStyleColor then r.ImGui_PopStyleColor(ctx, pushedSrc) end
              if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then
                r.ImGui_SetTooltip(ctx, 'Set this FX as the Source for other actions in this script or related tools')
              end
            end
            r.ImGui_EndTable(ctx)
          end
        end
      end
    end
  
  draw_replace_panel()
    r.ImGui_EndChild(ctx)

    r.ImGui_Separator(ctx)
    r.ImGui_BeginChild(ctx, 'footer_child', -1, FOOTER_H)
      local msg = state.pendingMessage or ''
      local err = state.pendingError or ''
      local hasMsg = (msg ~= '')
      local hasErr = (err ~= '')
      if hasErr then
        r.ImGui_Text(ctx, 'Error: ' .. err)
      elseif hasMsg then
        r.ImGui_Text(ctx, msg)
      else
        r.ImGui_TextDisabled(ctx, 'Ready')
      end
    r.ImGui_EndChild(ctx)

    local cw, ch = r.ImGui_GetWindowSize(ctx)
    state.winW, state.winH = cw, ch
  end
  r.ImGui_End(ctx)
  pop_app_style(stylePush)

  
  if state.showSettings and ctx then
    if state.showSettingsPending then
      
      state.showSettingsPending = false
    else
    local settings_begun = false
    local okS, openS
    local ok_call, err = pcall(function()
  okS, openS = r.ImGui_Begin(ctx, 'Settings##TK_FX_Slots_SingleTrack', true, r.ImGui_WindowFlags_AlwaysAutoResize() | r.ImGui_WindowFlags_NoTitleBar())
      settings_begun = true
    end)
    if ok_call and settings_begun then
      if okS then
        local changed = false
        local c1, v1 = r.ImGui_Checkbox(ctx, 'Tooltips', state.tooltips)
        if c1 then state.tooltips = v1; changed = true end
        local c2, v2 = r.ImGui_Checkbox(ctx, 'Names without prefix', state.nameNoPrefix)
        if c2 then state.nameNoPrefix = v2; changed = true end
        local c3, v3 = r.ImGui_Checkbox(ctx, 'Hide developer name', state.nameHideDeveloper)
        if c3 then state.nameHideDeveloper = v3; changed = true end
        if changed then save_user_settings() end
        if r.ImGui_Button(ctx, 'Close') then state.showSettings = false end
      end
      pcall(r.ImGui_End, ctx)
      if openS == false then state.showSettings = false end
    else
      state.showSettings = false
    end
    end
  end

  if state.showHelp and ctx then
    local help_begun = false
    local okH, openH
    local ok_call, err = pcall(function()
  okH, openH = r.ImGui_Begin(ctx, 'Help##TK_FX_Slots_SingleTrack', true, r.ImGui_WindowFlags_AlwaysAutoResize() | r.ImGui_WindowFlags_NoTitleBar())
      help_begun = true
    end)
    if ok_call and help_begun then
      if okH then
        r.ImGui_Text(ctx, 'TK FX Slots Single Track - Help')
        r.ImGui_Separator(ctx)
        r.ImGui_Text(ctx, 'Source: Use the Source button next to an FX to set it as the target for Replace/Delete actions.')
  r.ImGui_Text(ctx, 'Replace: Choose a replacement via My Favorites or Pick from list…, then Replace/Delete across the chosen scope.')
        r.ImGui_Text(ctx, 'Slot ops: Replace/Add at a specific slot index across tracks; optionally insert a placeholder.')
        r.ImGui_Text(ctx, 'Settings: Toggle tooltips and control name display formatting.')
        r.ImGui_Dummy(ctx, 0, 6)
        if r.ImGui_Button(ctx, 'Close') then state.showHelp = false end
      end
      r.ImGui_End(ctx)
      if openH == false then state.showHelp = false end
    else
      state.showHelp = false
    end
  end

  if state.showPicker and ctx then
    ensure_picker_items()
    local picker_begun = false
    local okP, openP
    local ok_call, err = pcall(function()
      okP, openP = r.ImGui_Begin(ctx, 'Choose plugin (Sexan)##TK_FX_Slots_SingleTrack', true, r.ImGui_WindowFlags_AlwaysAutoResize() | r.ImGui_WindowFlags_NoTitleBar())
      picker_begun = true
    end)
    if ok_call and picker_begun then
      if okP then
     
  local availW = select(1, r.ImGui_GetContentRegionAvail(ctx)) or 0
        if r.ImGui_Button(ctx, 'Refresh list (build)') then
          local items, perr = load_plugin_items()
          if items then
            state.pickerItems, state.pickerErr = items, nil
            state.pickerLoadedFromCache = false
            write_cache_items(items)
          else
            state.pickerErr = perr or 'Failed to build list'
          end
        end
  r.ImGui_SameLine(ctx)
  r.ImGui_SetNextItemWidth(ctx, 160)
        local currentType = state.pickerType or 'All types'
        if r.ImGui_BeginCombo(ctx, '##picker_type', currentType) then
          for _, opt in ipairs(PICKER_TYPE_OPTIONS) do
            local sel = (opt == currentType)
            if r.ImGui_Selectable(ctx, opt, sel) then state.pickerType = opt end
          end
          r.ImGui_EndCombo(ctx)
        end
  if state.pickerLoadedFromCache then r.ImGui_SameLine(ctx) r.ImGui_Text(ctx, '[cache]') end

        if state.pickerErr then
          r.ImGui_TextWrapped(ctx, state.pickerErr)
        elseif not state.pickerItems then
          r.ImGui_TextWrapped(ctx, 'No list loaded. Click "Refresh list (build)" to build and cache the list.')
        else
       
          r.ImGui_SetNextItemWidth(ctx, 300)
          local chgF, ftxt = r.ImGui_InputText(ctx, '##picker_filter', state.pickerFilter or '')
          if chgF then state.pickerFilter = ftxt end
       
          r.ImGui_BeginChild(ctx, 'picker_list', 320, 360)
          local fl = (state.pickerFilter or ''):lower()
          for i, it in ipairs(state.pickerItems or {}) do
            local disp = it.display or it.addname
            local add  = it.addname or disp
            local typ = parse_addname_type(add)
            local type_ok = (state.pickerType == 'All types') or (typ == state.pickerType)
            if type_ok and (fl == '' or (disp and disp:lower():find(fl, 1, true)) or (add and add:lower():find(fl, 1, true))) then
            
              if r.ImGui_SmallButton(ctx, ('+##fav%d'):format(i)) then
                favs_add(add, disp)
              end
              if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then
                r.ImGui_SetTooltip(ctx, 'Add to My Favorites')
              end
              r.ImGui_SameLine(ctx)
              local selected = (state.pickerChosenAdd == add)
              if r.ImGui_Selectable(ctx, (disp .. ('##pick%d'):format(i)), selected) then state.pickerChosenAdd = add end
              if r.ImGui_IsItemHovered(ctx) and r.ImGui_IsMouseDoubleClicked(ctx, 0) then
                state.pickerChosenAdd = add
             
                state.replaceWith = add
                state.replaceDisplay = disp
                state.pendingMessage = 'Chosen: ' .. tostring(disp)
                openP = false
              end
            end
          end
          r.ImGui_EndChild(ctx)
        
          local disabled = not (state.pickerChosenAdd and state.pickerChosenAdd ~= '')
          if disabled and r.ImGui_BeginDisabled then r.ImGui_BeginDisabled(ctx) end
          if r.ImGui_Button(ctx, 'Use selection') then
            local chosen = state.pickerChosenAdd
            if chosen and chosen ~= '' then
              state.replaceWith = chosen
            
              local disp = chosen
              for _, it in ipairs(state.pickerItems or {}) do
                if it.addname == chosen then disp = it.display or chosen; break end
              end
              state.replaceDisplay = disp
              state.pendingMessage = 'Chosen: ' .. tostring(disp)
              openP = false
            end
          end
          if disabled and r.ImGui_EndDisabled then r.ImGui_EndDisabled(ctx) end
          r.ImGui_SameLine(ctx)
          if r.ImGui_Button(ctx, 'Cancel') then openP = false end
        end
      end
      r.ImGui_End(ctx)
      if openP == false then state.showPicker = false end
    else
      state.showPicker = false
    end
  end

  if open == nil or open then
    r.defer(draw)
  else
    
    if (state.winW or 0) > 0 and (state.winH or 0) > 0 then
      save_window_size(state.winW, state.winH)
    end
  end
end

 
load_window_size()
load_user_settings()
favs_load()
blanks_load()
draw()
