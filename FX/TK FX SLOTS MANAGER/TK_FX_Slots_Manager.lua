-- @version 0.1.1
-- @changelog:

--[[
== THNX TO MASTER SEXAN FOR HIS FX PARSER ==
]]--

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
  Window_NoTitleBar         = flag(r.ImGui_WindowFlags_NoTitleBar),
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
  StyleVar_WindowRounding = enum(r.ImGui_StyleVar_WindowRounding),
  StyleVar_FrameRounding = enum(r.ImGui_StyleVar_FrameRounding),
  StyleVar_ItemSpacing = enum(r.ImGui_StyleVar_ItemSpacing),
  Col_Header = enum(r.ImGui_Col_Header),
  Col_HeaderHovered = enum(r.ImGui_Col_HeaderHovered),
  Col_HeaderActive = enum(r.ImGui_Col_HeaderActive),
  Col_Button = enum(r.ImGui_Col_Button),
  Col_ButtonHovered = enum(r.ImGui_Col_ButtonHovered),
  Col_ButtonActive = enum(r.ImGui_Col_ButtonActive),
  Col_FrameBg = enum(r.ImGui_Col_FrameBg),
  Col_FrameBgHovered = enum(r.ImGui_Col_FrameBgHovered),
  Col_FrameBgActive = enum(r.ImGui_Col_FrameBgActive),
  Col_PopupBg = enum(r.ImGui_Col_PopupBg),
  Col_CheckMark = enum(r.ImGui_Col_CheckMark),
}

local HAVE_StyleVar_FramePadding = ENUM.StyleVar_FramePadding ~= nil
local HAVE_PushStyleColor = (r.ImGui_PushStyleColor ~= nil) and (ENUM.Col_Text ~= nil)
local HAVE_PushStyleVar = (r.ImGui_PushStyleVar ~= nil)

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

local function push_style_var(idx, v)
  if not HAVE_PushStyleVar or not idx or v == nil then return false end
  local ok = pcall(r.ImGui_PushStyleVar, ctx, idx, v)
  return ok and true or false
end

local function push_style_var2(idx, v1, v2)
  if not HAVE_PushStyleVar or not idx or v1 == nil or v2 == nil then return false end
  if r.ImGui_PushStyleVar(ctx, idx, v1, v2) then return true end
  return false
end

local function push_app_style()
  local pushed = { colors = 0, vars = 0 }
  if ENUM.StyleVar_WindowRounding and push_style_var(ENUM.StyleVar_WindowRounding, 3.0) then pushed.vars = pushed.vars + 1 end
  if ENUM.StyleVar_FrameRounding and push_style_var(ENUM.StyleVar_FrameRounding, 3.0) then pushed.vars = pushed.vars + 1 end
  if ENUM.Col_Button and push_style_color(ENUM.Col_Button, 0.18, 0.18, 0.18, 1.00) then pushed.colors = pushed.colors + 1 end
  if ENUM.Col_ButtonHovered and push_style_color(ENUM.Col_ButtonHovered, 0.26, 0.26, 0.26, 1.00) then pushed.colors = pushed.colors + 1 end
  if ENUM.Col_ButtonActive and push_style_color(ENUM.Col_ButtonActive, 0.12, 0.12, 0.12, 1.00) then pushed.colors = pushed.colors + 1 end
  if ENUM.Col_FrameBg and push_style_color(ENUM.Col_FrameBg, 0.20, 0.20, 0.20, 1.00) then pushed.colors = pushed.colors + 1 end
  if ENUM.Col_FrameBgHovered and push_style_color(ENUM.Col_FrameBgHovered, 0.26, 0.26, 0.26, 1.00) then pushed.colors = pushed.colors + 1 end
  if ENUM.Col_FrameBgActive and push_style_color(ENUM.Col_FrameBgActive, 0.14, 0.14, 0.14, 1.00) then pushed.colors = pushed.colors + 1 end
  if ENUM.Col_PopupBg and push_style_color(ENUM.Col_PopupBg, 0.10, 0.10, 0.10, 0.98) then pushed.colors = pushed.colors + 1 end
  if ENUM.Col_CheckMark and push_style_color(ENUM.Col_CheckMark, 0.92, 0.92, 0.92, 1.00) then pushed.colors = pushed.colors + 1 end
  return pushed
end

local function pop_app_style(pushed)
  if pushed then
    if HAVE_PushStyleColor and pushed.colors and pushed.colors > 0 then r.ImGui_PopStyleColor(ctx, pushed.colors) end
    if r.ImGui_PopStyleVar and pushed.vars and pushed.vars > 0 then r.ImGui_PopStyleVar(ctx, pushed.vars) end
  end
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

local font_small = nil
local function ensure_small_font()
  if font_small ~= nil then return end
  if r.ImGui_CreateFont and r.ImGui_Attach then
    local ok, f = pcall(r.ImGui_CreateFont, 'arial', 9)
    if ok and f then
      font_small = f
      pcall(r.ImGui_Attach, ctx, font_small)
    end
  end
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

local function safe_SetNextWindowSizeConstraints(min_w, min_h, max_w, max_h)
  if r.ImGui_SetNextWindowSizeConstraints then
    safe_call(function() return r.ImGui_SetNextWindowSizeConstraints(ctx, min_w, min_h, max_w, max_h) end)
  end
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
  batchSlotIndex            = 0,
  deleteInsertPlaceholder   = false,
  placeholderAdd            = '',
  placeholderDisplay        = '',
  placeholderCustomName     = '',
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
  replaceToggles            = {},
  pluginList                = nil,
  showPicker                = false,
  pickerFilter              = '',
  replaceDisplay            = '',
  favs                      = {},
  dragging                  = nil,
  typeFilters               = nil,
  pickerMode                = 'replace',
  tkBlankVariants           = nil,
  sidebarWidth              = 220,
  hidePrefix                = false,
  hideDeveloper             = false,
  selAnchorIdx              = nil,
  tooltips                  = true,
  slotUsePlaceholder        = false,
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

local function load_window_size()
  local w = tonumber(r.GetExtState('TK_FX_SLOTS', 'WIN_W') or '')
  local h = tonumber(r.GetExtState('TK_FX_SLOTS', 'WIN_H') or '')
  if w and h and w > 0 and h > 0 then
    state.winW = math.floor(w)
    state.winH = math.floor(h)
  end
end

local function save_window_size(w, h)
  if not w or not h then return end
  r.SetExtState('TK_FX_SLOTS', 'WIN_W', tostring(math.floor(w)), true)
  r.SetExtState('TK_FX_SLOTS', 'WIN_H', tostring(math.floor(h)), true)
end

local function load_ui_prefs()
  local hp = r.GetExtState('TK_FX_SLOTS', 'HIDE_PREFIX') or ''
  local hd = r.GetExtState('TK_FX_SLOTS', 'HIDE_DEV') or ''
  state.hidePrefix = (hp == '1' or hp == 'true') and true or false
  state.hideDeveloper = (hd == '1' or hd == 'true') and true or false
  local sw = tonumber(r.GetExtState('TK_FX_SLOTS', 'SIDEBAR_W') or '')
  if sw and sw > 0 then
    local clamped = math.max(220, math.min(480, math.floor(sw)))
    state.sidebarWidth = clamped
  end
  local tt = r.GetExtState('TK_FX_SLOTS', 'TOOLTIPS') or ''
  state.tooltips = (tt == '' and true) or (tt == '1' or tt == 'true')
end

local function save_ui_prefs()
  r.SetExtState('TK_FX_SLOTS', 'HIDE_PREFIX', state.hidePrefix and '1' or '0', true)
  r.SetExtState('TK_FX_SLOTS', 'HIDE_DEV', state.hideDeveloper and '1' or '0', true)
  if state.sidebarWidth and state.sidebarWidth > 0 then
    r.SetExtState('TK_FX_SLOTS', 'SIDEBAR_W', tostring(math.floor(state.sidebarWidth)), true)
  end
  r.SetExtState('TK_FX_SLOTS', 'TOOLTIPS', state.tooltips and '1' or '0', true)
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

local function write_text_file(path, text)
  local f, err = io.open(path, 'wb')
  if not f then return false, err end
  f:write(text or '')
  f:close()
  return true
end

local function fmt_timestamp()
  local t = os.date('*t')
  return string.format('%04d-%02d-%02d_%02d-%02d-%02d', t.year, t.month, t.day, t.hour, t.min, t.sec)
end

local function build_plugin_report_text()
  local trackLines = {}
  local totalFX = 0
  local scope = state.scopeSelectedOnly and 'Selected tracks only' or 'All tracks'
  local gen = os.date('%Y-%m-%d %H:%M:%S')
  local selectedOnly = state.scopeSelectedOnly
  local tcount = selectedOnly and r.CountSelectedTracks(0) or r.CountTracks(0)
  for i = 0, tcount - 1 do
    local tr = selectedOnly and r.GetSelectedTrack(0, i) or r.GetTrack(0, i)
    if tr then
      local proj_idx = r.GetMediaTrackInfo_Value and r.GetMediaTrackInfo_Value(tr, 'IP_TRACKNUMBER') or (i + 1)
      proj_idx = tonumber(proj_idx) and math.floor(proj_idx) or (i + 1)
      local rvName, tname = r.GetTrackName(tr)
      tname = rvName and tname or '(track)'
  trackLines[#trackLines+1] = string.format('Track %d: %s', proj_idx, tname)
      local fxCount = r.TrackFX_GetCount(tr)
      trackLines[#trackLines+1] = string.format('  FX count: %d', fxCount)
      totalFX = totalFX + (fxCount or 0)
      if fxCount == 0 then
        trackLines[#trackLines+1] = ''
      else
        local instIdx = -1
        if r.TrackFX_GetInstrument then
          local ii = r.TrackFX_GetInstrument(tr)
          if type(ii) == 'number' then instIdx = ii end
        end
        for fi = 0, fxCount - 1 do
          local rvFX, fxName = r.TrackFX_GetFXName(tr, fi, '')
          fxName = rvFX and fxName or string.format('FX %d', fi+1)
          local enabled = r.TrackFX_GetEnabled(tr, fi) and true or false
          local offline = r.TrackFX_GetOffline(tr, fi) and true or false
          local typ
          do
            local u = tostring(fxName):upper()
            if u:find('^CLAPI:') then typ = 'CLAPi'
            elseif u:find('^CLAP:') then typ = 'CLAP'
            elseif u:find('^VST3I:') then typ = 'VST3i'
            elseif u:find('^VST3:') then typ = 'VST3'
            elseif u:find('^VSTI:') then typ = 'VSTi'
            elseif u:find('^VST:') then typ = 'VST'
            elseif u:find('^JSFX:') then typ = 'JSFX'
            elseif u:find('^JS:') then typ = 'JS'
            elseif u:find('^AUV3:') then typ = 'AUv3'
            elseif u:find('^AU:') then typ = 'AU'
            elseif u:find('^LV2:') then typ = 'LV2'
            elseif u:find('^DXI:') then typ = 'DXi'
            elseif u:find('^DX:') then typ = 'DX'
            else typ = 'Other' end
          end
          local isInst = (instIdx == fi)
          local latency = 0
          if r.TrackFX_GetLatency then
            local okL, lat = pcall(r.TrackFX_GetLatency, tr, fi)
            if okL and type(lat) == 'number' then latency = lat end
          end
          trackLines[#trackLines+1] = string.format('  %2d) [%s] %s%s  (bypassed=%s, offline=%s, latency=%ds)', fi+1, typ, fxName, (isInst and ' [Instrument]' or ''), (enabled and 'no' or 'yes'), (offline and 'yes' or 'no'), latency)
        end
        trackLines[#trackLines+1] = ''
      end
    end
  end
  local lines = {}
  lines[#lines+1] = 'TK FX Slots Manager - Plugin List Report'
  lines[#lines+1] = 'Scope: ' .. scope
  lines[#lines+1] = 'Generated: ' .. gen
  lines[#lines+1] = 'Total FX: ' .. tostring(totalFX)
  lines[#lines+1] = ''
  for _, ln in ipairs(trackLines) do lines[#lines+1] = ln end
  return table.concat(lines, '\n')
end

local function print_plugin_list()
  local txt = build_plugin_report_text()
  local sep = package.config:sub(1,1)
  local baseDir = r.GetResourcePath() .. sep .. 'Scripts'
  if r.RecursiveCreateDirectory then r.RecursiveCreateDirectory(baseDir, 0) end
  local fname = 'TK FX Slots Manager - Plugin List ' .. fmt_timestamp() .. '.txt'
  local full = baseDir .. sep .. fname
  local ok, err = write_text_file(full, txt)
  if not ok then return false, 'Write failed: ' .. tostring(err) end
  return true, full
end

local function ensure_tk_blank_addname(customDesc)
  local sep = package.config:sub(1,1)
  local effectsDir = r.GetResourcePath() .. sep .. 'Effects' .. sep .. 'TK'
  if r.RecursiveCreateDirectory then r.RecursiveCreateDirectory(effectsDir, 0) end
  local baseFile = 'TK_Blank_NoOp.jsfx'
  local target = effectsDir .. sep .. baseFile
  local function file_exists(p)
    local f = io.open(p, 'rb'); if f then f:close(); return true else return false end
  end
  if not file_exists(target) then
  local content = [[desc: TK Blank (no-op)
author: TouristKiller
version: 1.1
license: MIT

@init

@sample
]]
    local wf = io.open(target, 'wb')
    if wf then wf:write(content) wf:close() end
  if r.Main_OnCommand then r.Main_OnCommand(40506, 0) end
  end
  if customDesc and customDesc ~= '' then
    local safe = tostring(customDesc):gsub('[^%w%-_ ]', ''):gsub('%s+', '_')
    if safe == '' then safe = 'Custom' end
    local variantFile = ('TK_Blank_NoOp_%s.jsfx'):format(safe)
    local variantPath = effectsDir .. sep .. variantFile
    if not file_exists(variantPath) then
  local content = ('desc: %s\nauthor: TouristKiller\nversion: 1.1\nlicense: MIT\n\n@init\n\n@sample\n'):format(customDesc)
      local wf = io.open(variantPath, 'wb')
      if wf then wf:write(content) wf:close() end
  if r.Main_OnCommand then r.Main_OnCommand(40506, 0) end
    end
    state.tkBlankVariants = nil
    return 'JS: TK/' .. (variantFile:gsub('%.jsfx$', ''))
  end
  return 'JS: TK/TK_Blank_NoOp'
end

local function refresh_tk_blank_variants()
  local sep = package.config:sub(1,1)
  local dir = r.GetResourcePath() .. sep .. 'Effects' .. sep .. 'TK'
  local list = {}
  if r.EnumerateFiles then
    local i = 0
    while true do
      local fn = r.EnumerateFiles(dir, i)
      if not fn then break end
      if fn:match('^TK_Blank_NoOp_.*%.jsfx$') then
        local full = dir .. sep .. fn
        local name = fn:gsub('^TK_Blank_NoOp_', ''):gsub('%.jsfx$', '')
        local f = io.open(full, 'r')
        if f then
          local first = f:read('*l') or ''
          f:close()
          local desc = first:match('^%s*desc:%s*(.+)$')
          if desc and desc ~= '' then name = desc end
        end
        list[#list+1] = { name = name, file = fn, addname = 'JS: TK/' .. fn:gsub('%.jsfx$', '') }
      end
      i = i + 1
    end
  end
  state.tkBlankVariants = list
end
local function ensure_blank_jsfx()
  local sep = package.config:sub(1,1)
  local jsfxDir = r.GetResourcePath() .. sep .. 'Effects' .. sep .. 'TK'
  if r.RecursiveCreateDirectory then r.RecursiveCreateDirectory(jsfxDir, 0) end
  local path = jsfxDir .. sep .. 'TK_Blank_NoOp.jsfx'
  local f = io.open(path, 'rb')
  if not f then
  local content = [[desc: TK Blank (no-op)
author: TouristKiller
version: 1.1
license: MIT

@init

@sample
]]
    local wf = io.open(path, 'wb')
    if wf then wf:write(content) wf:close() end
  if r.Main_OnCommand then r.Main_OnCommand(40506, 0) end
  else
    f:close()
  end
  return path
end
 
local function sanitize_filename(name)
  name = tostring(name or 'FX Chain')
  name = name:gsub('[\\/:*?"<>|]', '_')
  name = name:gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', '')
  if name == '' then name = 'FX Chain' end
  return name
end

local function extract_fxchain_block(chunk)
  if not chunk or chunk == '' then return nil end
  local startPos = chunk:find('<FXCHAIN', 1, true)
  if not startPos then return nil end
  local i = startPos
  local len = #chunk
  local depth = 0
  local pos = startPos
  while true do
    local lineEnd = chunk:find('\n', pos, true) or (len + 1)
    local line = chunk:sub(pos, lineEnd - 1)
    if line:sub(1,1) == '<' then depth = depth + 1 end
    if line == '>' then
      depth = depth - 1
      if depth == 0 then
        local endPos = lineEnd
        return chunk:sub(startPos, endPos)
      end
    end
    if lineEnd > len then break end
    pos = lineEnd + 1
  end
  return nil
end

local function save_fx_chain_for_track(track, trackName)
  if not track then return false, 'Track missing' end
  local ok, chunk = r.GetTrackStateChunk(track, '', false)
  if not ok then return false, 'Could not read track state' end
  local fxchain = extract_fxchain_block(chunk)
  if not fxchain then return false, 'No FX chain found' end
  local sep = package.config:sub(1,1)
  local baseDir = r.GetResourcePath() .. sep .. 'FXChains'
  if r.RecursiveCreateDirectory then r.RecursiveCreateDirectory(baseDir, 0) end
  local defaultName = sanitize_filename(trackName) .. '.rfxchain'
  local fname = defaultName
  do
    local okUI, val = r.GetUserInputs('Save FX chain', 1, 'Filename (.rfxchain):,extrawidth=100', defaultName)
    if not okUI then return false, 'Canceled' end
    fname = sanitize_filename(val)
    if not fname:lower():match('%.rfxchain$') then fname = fname .. '.rfxchain' end
  end
  local fullpath = baseDir .. sep .. fname
  local f, err = io.open(fullpath, 'wb')
  if not f then return false, 'Write failed: ' .. tostring(err) end
  f:write(fxchain)
  f:close()
  return true, fullpath
end

 
local function read_text_file(path)
  local f, err = io.open(path, 'rb')
  if not f then return nil, err end
  local data = f:read('*a')
  f:close()
  return data
end

local function find_fxchain_span(chunk)
  if not chunk or chunk == '' then return nil end
  local startPos = chunk:find('<FXCHAIN', 1, true)
  if not startPos then return nil end
  local len = #chunk
  local depth = 0
  local pos = startPos
  local spanStart = startPos
  while true do
    local lineStart = pos
    local lineEnd = chunk:find('\n', pos, true) or (len + 1)
    local line = chunk:sub(pos, lineEnd - 1)
    if line:sub(1,1) == '<' then depth = depth + 1 end
    if line == '>' then
      depth = depth - 1
      if depth == 0 then
        return spanStart, lineEnd
      end
    end
    if lineEnd > len then break end
    pos = lineEnd + 1
  end
  return nil
end

local function find_track_close_pos(chunk)
  if not chunk or chunk == '' then return nil end
  local startPos = chunk:find('<TRACK', 1, true) or 1
  local len = #chunk
  local depth = 0
  local pos = startPos
  local closeStart = nil
  while true do
    local lineStart = pos
    local lineEnd = chunk:find('\n', pos, true) or (len + 1)
    local line = chunk:sub(pos, lineEnd - 1)
    if line:sub(1,1) == '<' then depth = depth + 1 end
    if line == '>' then
      depth = depth - 1
      if depth == 0 then
        closeStart = lineStart
        break
      end
    end
    if lineEnd > len then break end
    pos = lineEnd + 1
  end
  return closeStart
end

local function replace_fx_chain_from_file(track, fullpath)
  if not track then return false, 'Track missing' end
  if not fullpath or fullpath == '' then return false, 'No file chosen' end
  local data, err = read_text_file(fullpath)
  if not data then return false, 'Read failed: ' .. tostring(err) end
  if not data:find('<FXCHAIN', 1, true) then return false, 'Not a valid .rfxchain' end
  local ok, chunk = r.GetTrackStateChunk(track, '', false)
  if not ok then return false, 'Could not read track state' end
  local s1, e1 = find_fxchain_span(chunk)
  local newChunk
  if s1 and e1 then
    newChunk = chunk:sub(1, s1 - 1) .. data .. chunk:sub(e1 + 1)
  else
    local ins = find_track_close_pos(chunk)
    if not ins then return false, 'Track chunk parse error' end
    local prefix = chunk:sub(1, ins - 1)
    local suffix = chunk:sub(ins)
    if not data:match('\n$') then data = data .. '\n' end
    newChunk = prefix .. data .. suffix
  end
  local setOk = r.SetTrackStateChunk(track, newChunk, false)
  if not setOk then return false, 'Failed to set track state' end
  return true
end

 
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

local PLUGIN_TYPE_ORDER = { 'CLAP','CLAPi','VST3','VST3i','VST','VSTi','JS','JSFX','AUv3','AU','LV2','DX','DXi','Other' }
local function detect_plugin_type(s)
  if not s or s == '' then return 'Other' end
  local u = tostring(s):upper()
  
  if u:find('^CLAPI:') then return 'CLAPi' end
  if u:find('^CLAP:') then return 'CLAP' end
  if u:find('^VST3I:') then return 'VST3i' end
  if u:find('^VST3:') then return 'VST3' end
  if u:find('^VSTI:') then return 'VSTi' end
  if u:find('^VST:') then return 'VST' end
  if u:find('^JSFX:') then return 'JSFX' end
  if u:find('^JS:') then return 'JS' end
  if u:find('^AUV3:') then return 'AUv3' end
  if u:find('^AU:') then return 'AU' end
  if u:find('^LV2:') then return 'LV2' end
  if u:find('^DXI:') then return 'DXi' end
  if u:find('^DX:') then return 'DX' end
  return 'Other'
end

local function ensure_type_filters()
  if state.typeFilters ~= nil then return end
  state.typeFilters = {}
  for _, t in ipairs(PLUGIN_TYPE_ORDER) do state.typeFilters[t] = true end 
end

local function draw_plugin_picker()
  if not state.showPicker then return end
  if not state.pluginItems then
    load_plugin_list()
  end
  ensure_ctx()
  safe_SetNextWindowSize(520, 600, FLAGS.Cond_Appearing)
  local stylePush = push_app_style()
  local title = (state.pickerMode == 'placeholder') and 'Choose placeholder plugin' or 'Choose plugin (Sexan parser)'
  local begunPicker, visible, open = safe_Begin(title, true, FLAGS.Window_MenuBar)
  if visible then
    local prompt = (state.pickerMode == 'placeholder') and 'Pick a placeholder to insert on delete:' or 'Search and select a plugin to use as replacement:'
    r.ImGui_Text(ctx, prompt)
    r.ImGui_SetNextItemWidth(ctx, 300)
    local chg, txt = r.ImGui_InputText(ctx, 'Filter##picker', state.pickerFilter)
    if chg then state.pickerFilter = txt end
    ensure_type_filters()
    
    local availW1, _availH = r.ImGui_GetContentRegionAvail(ctx)
    if availW1 > 200 then r.ImGui_SameLine(ctx) else r.ImGui_NewLine(ctx) end
    local summary
    do
      local on = {}
      local cnt = 0
      for _, t in ipairs(PLUGIN_TYPE_ORDER) do if state.typeFilters[t] then on[#on+1] = t; cnt = cnt + 1 end end
      summary = (cnt == #PLUGIN_TYPE_ORDER) and 'All' or table.concat(on, ', ')
      if #summary > 24 then summary = summary:sub(1, 24) .. '…' end
    end
    local availW2 = select(1, r.ImGui_GetContentRegionAvail(ctx))
    if availW2 and availW2 > 0 then r.ImGui_SetNextItemWidth(ctx, math.max(120, availW2)) end
    if r.ImGui_BeginCombo(ctx, 'Types', summary) then
      if r.ImGui_SmallButton(ctx, 'All') then for _, t in ipairs(PLUGIN_TYPE_ORDER) do state.typeFilters[t] = true end end
      r.ImGui_SameLine(ctx)
      if r.ImGui_SmallButton(ctx, 'None') then for _, t in ipairs(PLUGIN_TYPE_ORDER) do state.typeFilters[t] = false end end
      r.ImGui_Separator(ctx)
      for _, t in ipairs(PLUGIN_TYPE_ORDER) do
        local changedTF, v = r.ImGui_Checkbox(ctx, t, state.typeFilters[t])
        if changedTF then state.typeFilters[t] = v end
      end
      r.ImGui_EndCombo(ctx)
    end
  local childVisible = r.ImGui_BeginChild(ctx, 'picker_list', 0, -32, 0)
  if childVisible then
      local filter = (state.pickerFilter or ''):lower()
      local shown = 0
      local idx = 0
      for _, it in ipairs(state.pluginItems or {}) do
        local disp = tostring(it.display)
        local addn = tostring(it.addname or disp)
        local ptype = detect_plugin_type(addn)
        if state.typeFilters[ptype] and (filter == '' or disp:lower():find(filter, 1, true)) then
          idx = idx + 1
          if r.ImGui_SmallButton(ctx, '+##pick' .. idx) then
            favs_add(it.addname, tostring(it.display))
          end
          r.ImGui_SameLine(ctx)
          if r.ImGui_Selectable(ctx, disp, false) then
            if state.pickerMode == 'placeholder' then
              state.placeholderAdd = it.addname
              state.placeholderDisplay = disp
              state.pendingMessage = 'Placeholder: ' .. disp
            else
              state.replaceWith = it.addname
              state.replaceDisplay = disp
              state.pendingMessage = 'Chosen: ' .. disp
            end
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
  if childVisible then r.ImGui_EndChild(ctx) end
    if r.ImGui_Button(ctx, 'Close') then
      state.showPicker = false
    end
  end
  if begunPicker then r.ImGui_End(ctx) end
  pop_app_style(stylePush)
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
  if r.TrackFX_GetNamedConfigParm then
    local ok, alias = r.TrackFX_GetNamedConfigParm(track, fx, 'renamed')
    if ok and alias and alias ~= '' then return alias end
  end
  local rv, buf = r.TrackFX_GetFXName(track, fx, '')
  if rv then return buf else return ("FX %d"):format(fx+1) end
end

local function rename_fx_instance(track, fxIdx, name)
  if not name or name == '' then return end
  if r.TrackFX_SetNamedConfigParm then
    pcall(function() r.TrackFX_SetNamedConfigParm(track, fxIdx, 'renamed', tostring(name)) end)
  end
  if r.TrackList_AdjustWindows then pcall(function() r.TrackList_AdjustWindows(false) end) end
  if r.UpdateArrange then pcall(function() r.UpdateArrange() end) end
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

 
local function has_toggle_for(guid, idx)
  if not guid or not idx then return false end
  local m = state.replaceToggles[guid]
  return m and m[idx] ~= nil and m[idx].active == true
end

local function set_toggle_entry(guid, idx, entry)
  if not guid or not idx then return end
  state.replaceToggles[guid] = state.replaceToggles[guid] or {}
  state.replaceToggles[guid][idx] = entry
end

local function clear_toggle_entry(guid, idx)
  local m = state.replaceToggles[guid]
  if m then m[idx] = nil end
end

local function toggle_replace_fx(tr, trGuid, fxIdx)
  if not tr or not trGuid then return end
  local rv, curName = r.TrackFX_GetFXName(tr, fxIdx, '')
  curName = rv and curName or ('FX %d'):format(fxIdx+1)
  if has_toggle_for(trGuid, fxIdx) then
  
    local ent = state.replaceToggles[trGuid][fxIdx]
    r.Undo_BeginBlock()
    local ok, err = replace_fx_at(tr, fxIdx, ent.originalName, true, 'in_place')
    r.Undo_EndBlock('Restore original FX', -1)
    if not ok then state.pendingError = err or 'Restore failed' end
    clear_toggle_entry(trGuid, fxIdx)
    rebuild_model()
  else
    if not state.replaceWith or state.replaceWith == '' then
      state.pendingError = 'Please pick a replacement plugin first.'
      return
    end
    set_toggle_entry(trGuid, fxIdx, { originalName = curName, replacementAdd = state.replaceWith, active = true })
    r.Undo_BeginBlock()
    local ok, err = replace_fx_at(tr, fxIdx, state.replaceWith, true, 'in_place')
    r.Undo_EndBlock('Replace (toggle)', -1)
    if not ok then
      state.pendingError = err or 'Replace failed'
      clear_toggle_entry(trGuid, fxIdx)
    end
    rebuild_model()
  end
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

local function delete_all_instances(sourceName, placeholderAdd, placeholderAlias)
  if not sourceName or sourceName == '' then return 0, 'No source FX selected' end
  local deleted = 0
  r.Undo_BeginBlock()
  for tr, _ in tracks_iter(state.scopeSelectedOnly) do
    local fxCount = r.TrackFX_GetCount(tr)
    local toDelete = {}
    for i = 0, fxCount - 1 do
      local name = get_fx_name(tr, i)
      if name == sourceName then toDelete[#toDelete+1] = i end
    end
    table.sort(toDelete, function(a,b) return a>b end)
    for _, idx in ipairs(toDelete) do
      local okDel = pcall(function() r.TrackFX_Delete(tr, idx) end)
      if okDel then
        deleted = deleted + 1
        if placeholderAdd and placeholderAdd ~= '' then
          local newIdx = r.TrackFX_AddByName(tr, placeholderAdd, false, -1)
          if newIdx >= 0 then
            r.TrackFX_CopyToTrack(tr, newIdx, tr, idx, true)
            if placeholderAlias and placeholderAlias ~= '' then
              rename_fx_instance(tr, idx, placeholderAlias)
            end
          end
        end
      end
    end
  end
  local withPH = (placeholderAdd and placeholderAdd ~= '') and ' + placeholders' or ''
  r.Undo_EndBlock(('Delete all instances of "%s"%s'):format(sourceName, withPH), -1)
  return deleted
end

local function replace_by_slot_across_tracks(slotIndex0, replacementName, aliasName)
  if replacementName == nil or replacementName == '' then
    return 0, 'No replacement plugin selected'
  end
  local slot = tonumber(slotIndex0)
  if not slot or slot < 0 then
    return 0, 'Invalid slot index'
  end
  local replaced = 0
  r.Undo_BeginBlock()
  for tr, _ in tracks_iter(state.scopeSelectedOnly) do
    local fxCount = r.TrackFX_GetCount(tr)
    if fxCount > slot then
      local ok, err = replace_fx_at(tr, slot, replacementName, true, 'in_place')
      if ok then replaced = replaced + 1 else state.pendingError = err end
      if ok and aliasName and aliasName ~= '' then
        rename_fx_instance(tr, slot, aliasName)
      end
    end
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

local function add_by_slot_across_tracks(slotIndex0, pluginName, aliasName)
  if not pluginName or pluginName == '' then return 0, 'No plugin selected' end
  local slot = tonumber(slotIndex0)
  if not slot or slot < 0 then return 0, 'Invalid slot index' end
  local added = 0
  r.Undo_BeginBlock()
  for tr, _ in tracks_iter(state.scopeSelectedOnly) do
    local fxCount = r.TrackFX_GetCount(tr)
    local skip = false
    local destIdx
    if slot < fxCount then
      local atName = get_fx_name(tr, slot)
      if normalize_fx_label(atName) == normalize_fx_label(pluginName) then
        skip = true 
      else
        destIdx = slot
      end
    elseif slot == fxCount then
      destIdx = FX_END 
    else
      destIdx = FX_END 
    end
    if not skip and destIdx ~= nil then
      local newIdx = r.TrackFX_AddByName(tr, pluginName, false, -1)
      if newIdx >= 0 then
        r.TrackFX_CopyToTrack(tr, newIdx, tr, destIdx, true)
        if aliasName and aliasName ~= '' then
          local finalIdx = (destIdx == FX_END) and (r.TrackFX_GetCount(tr) - 1) or destIdx
          rename_fx_instance(tr, finalIdx, aliasName)
        end
        added = added + 1
      end
    end
  end
  r.Undo_EndBlock(('Add "%s" at slot #%d across tracks'):format(pluginName, (slot or 0) + 1), -1)
  return added
end

local function draw_compact_toolbar()
  local availW = select(1, r.ImGui_GetContentRegionAvail(ctx)) or 0
  r.ImGui_SetNextItemWidth(ctx, math.max(140, math.min(300, math.floor(availW * 0.45))))
  local chg, f
  if r.ImGui_InputTextWithHint then
    chg, f = r.ImGui_InputTextWithHint(ctx, '##filter', 'enter filter tekst...', state.filter)
  else
    chg, f = r.ImGui_InputText(ctx, '##filter', state.filter)
    if (state.filter or '') == '' then
      local x, y = r.ImGui_GetItemRectMin(ctx)
      local dl = r.ImGui_GetWindowDrawList(ctx)
      local col = r.ImGui_ColorConvertDouble4ToU32 and r.ImGui_ColorConvertDouble4ToU32(0.70, 0.70, 0.70, 0.55) or 0x80B0B0B0
      r.ImGui_DrawList_AddText(dl, x + 6, y + 2, col, 'enter filter text...')
    end
  end
  if chg then state.filter = f end
  local pushedVars = 0
  if ENUM.StyleVar_ItemSpacing and push_style_var2(ENUM.StyleVar_ItemSpacing, 2.0, 1.0) then pushedVars = pushedVars + 1 end
  r.ImGui_SameLine(ctx)
  if r.ImGui_SmallButton(ctx, 'x##clear_filter') then state.filter = '' end
  if pushedVars > 0 and r.ImGui_PopStyleVar then r.ImGui_PopStyleVar(ctx, pushedVars) end
  r.ImGui_SameLine(ctx)
  if r.ImGui_SmallButton(ctx, '-') then state.forceHeaders = false end
  if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then r.ImGui_SetTooltip(ctx, 'Collapse all') end
  r.ImGui_SameLine(ctx)
  if r.ImGui_SmallButton(ctx, '+') then state.forceHeaders = true end
  if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then r.ImGui_SetTooltip(ctx, 'Expand all') end
  r.ImGui_SameLine(ctx)
  r.ImGui_Text(ctx, 'T#')
  r.ImGui_SameLine(ctx)
  r.ImGui_SetNextItemWidth(ctx, 40)
  local chgNum, newTxt
  local curTxt = tostring(state.gotoTrackInput or '')
  if r.ImGui_InputTextWithHint then
    chgNum, newTxt = r.ImGui_InputTextWithHint(ctx, '##gotoTrack', 'nr', curTxt)
  else
    chgNum, newTxt = r.ImGui_InputText(ctx, '##gotoTrack', curTxt)
  end
  if chgNum then
    local digits = tostring(newTxt or ''):gsub('%D', '')
    if digits == '' then
      state.gotoTrackInput = 1
    else
      state.gotoTrackInput = math.max(1, tonumber(digits) or 1)
    end
  end
  r.ImGui_SameLine(ctx)
  if r.ImGui_SmallButton(ctx, 'Go') then state.scrollToTrackNum = tonumber(state.gotoTrackInput) or 1 end
  -- r.ImGui_NewLine(ctx)
  local _, v1 = r.ImGui_Checkbox(ctx, 'Selected', state.scopeSelectedOnly); if _ then state.scopeSelectedOnly = v1; rebuild_model() end
  r.ImGui_SameLine(ctx)
  local _, v2 = r.ImGui_Checkbox(ctx, 'Hide empty', state.showOnlyTracksWithFX); if _ then state.showOnlyTracksWithFX = v2; rebuild_model() end
  r.ImGui_SameLine(ctx)
  local chgHP, v3 = r.ImGui_Checkbox(ctx, 'Hide prefix', state.hidePrefix); if chgHP then state.hidePrefix = v3; save_ui_prefs() end
  r.ImGui_SameLine(ctx)
  local chgHD, v4 = r.ImGui_Checkbox(ctx, 'Hide dev', state.hideDeveloper); if chgHD then state.hideDeveloper = v4; save_ui_prefs() end
  
end
local function draw_replace_panel()
  SeparatorText('Replace')
  local label = state.selectedSourceFXName and ('Selected: ' .. state.selectedSourceFXName) or '1. Pick a Source FX First'
  r.ImGui_Text(ctx, label)
  if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then
    local tip = state.selectedSourceFXName and 'Press "Source" in the track list to change the Source FX' or 'Press "Source" in the track list to set the Source FX'
    r.ImGui_SetTooltip(ctx, tip)
  end
  r.ImGui_Dummy(ctx, 0, 4)
  r.ImGui_Separator(ctx)
  r.ImGui_Text(ctx, '2. Placement:')
  -- r.ImGui_SameLine(ctx)
  local sel = state.insertPos
  local pushedVars = 0
  if ENUM.StyleVar_FramePadding and push_style_var2(ENUM.StyleVar_FramePadding, 1.0, 1.0) then pushedVars = pushedVars + 1 end
  if ENUM.StyleVar_ItemSpacing and push_style_var2(ENUM.StyleVar_ItemSpacing, 4.0, 1.0) then pushedVars = pushedVars + 1 end
  ensure_small_font()
  local pushedFont = false
  if font_small and r.ImGui_PushFont then
    local ok = pcall(r.ImGui_PushFont, ctx, font_small, 11)
    pushedFont = ok and true or false
  end
  if r.ImGui_RadioButton(ctx, 'Same slot', sel == 'in_place') then state.insertPos = 'in_place' end
  r.ImGui_SameLine(ctx)
  if r.ImGui_RadioButton(ctx, 'Start', sel == 'begin') then state.insertPos = 'begin' end
  r.ImGui_SameLine(ctx)
  if r.ImGui_RadioButton(ctx, 'End', sel == 'end') then state.insertPos = 'end' end
  r.ImGui_SameLine(ctx)
  if r.ImGui_RadioButton(ctx, 'Index', sel == 'index') then state.insertPos = 'index' end
  if pushedFont and r.ImGui_PopFont then r.ImGui_PopFont(ctx) end
  if pushedVars > 0 and r.ImGui_PopStyleVar then r.ImGui_PopStyleVar(ctx, pushedVars) end
  if state.insertPos == 'index' then
    r.ImGui_SameLine(ctx)
    r.ImGui_SetNextItemWidth(ctx, 80)
    local changed2, val = r.ImGui_InputInt(ctx, '##Slot (1-based)', (tonumber(state.insertIndex) or 0) + 1)
    if changed2 then state.insertIndex = math.max(0, (tonumber(val) or 1) - 1) end
  end
  r.ImGui_Dummy(ctx, 0, 4)
  r.ImGui_Separator(ctx)
  r.ImGui_Text(ctx, '3. Select Replacement FX:')
  if r.ImGui_Button(ctx, 'Pick from list…', 105) then state.showPicker = true end
  local bw, bh = r.ImGui_GetItemRectSize(ctx)
  r.ImGui_SameLine(ctx)
  r.ImGui_SetNextItemWidth(ctx, bw)
  r.ImGui_SetNextItemWidth(ctx, 105)
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
  r.ImGui_Dummy(ctx, 0, 4)
  r.ImGui_Separator(ctx)
  r.ImGui_Text(ctx, '4a. Replace all instances of source FX:')
  if r.ImGui_Button(ctx, 'Replace..', 60) then
    local count = 0
    count = select(1, replace_all_instances(state.selectedSourceFXName, state.replaceWith))
    state.pendingMessage = ('%d instances replaced.'):format(count)
    rebuild_model()
  end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, 'Delete', 60) then
    if not state.selectedSourceFXName or state.selectedSourceFXName == '' then
      state.pendingError = 'First choose a source FX (use the Source button).'
    else
      local phAdd, phAlias = nil, nil
      if state.deleteInsertPlaceholder then
        phAdd = ensure_tk_blank_addname(state.placeholderCustomName)
        phAlias = state.placeholderCustomName
      end
      local count = select(1, delete_all_instances(state.selectedSourceFXName, phAdd, phAlias))
      if state.deleteInsertPlaceholder and (state.placeholderAdd or '') ~= '' then
        state.pendingMessage = ('Deleted %d instances (with placeholders).'):format(count)
      else
        state.pendingMessage = ('Deleted %d instances.'):format(count)
      end
      rebuild_model()
    end
  end
  r.ImGui_SameLine(ctx)
  local chgPH, ph = r.ImGui_Checkbox(ctx, 'placeholder', state.deleteInsertPlaceholder)
  if chgPH then state.deleteInsertPlaceholder = ph end
  if state.deleteInsertPlaceholder then

  local nameWidth = 105
  r.ImGui_SetNextItemWidth(ctx, nameWidth)
  
    local chgAlias, alias
    if r.ImGui_InputTextWithHint then
      chgAlias, alias = r.ImGui_InputTextWithHint(ctx, '##tkblank', 'name...', state.placeholderCustomName)
    else
      chgAlias, alias = r.ImGui_InputText(ctx, '##tkblank', state.placeholderCustomName)
      if (state.placeholderCustomName or '') == '' then
        local x, y = r.ImGui_GetItemRectMin(ctx)
        local dl = r.ImGui_GetWindowDrawList(ctx)
        local col
        if r.ImGui_ColorConvertDouble4ToU32 then
          col = r.ImGui_ColorConvertDouble4ToU32(0.70, 0.70, 0.70, 0.55)
        else
          col = 0x80B0B0B0
        end
        r.ImGui_DrawList_AddText(dl, x + 6, y + 2, col, 'name...')
      end
    end
    if chgAlias then state.placeholderCustomName = alias end
    r.ImGui_SameLine(ctx)
    if not state.tkBlankVariants then refresh_tk_blank_variants() end
  r.ImGui_SetNextItemWidth(ctx, nameWidth)
  local label = '##Variants'
  if r.ImGui_BeginCombo(ctx, label, 'Choose…') then
      for i, v in ipairs(state.tkBlankVariants or {}) do
        if r.ImGui_Selectable(ctx, v.name, false) then
          state.placeholderCustomName = v.name
          state.pendingMessage = 'Using variant: ' .. v.name
        end
      end
      r.ImGui_EndCombo(ctx)
    end
  end
  r.ImGui_Dummy(ctx, 0, 4)
  r.ImGui_Separator(ctx)
  r.ImGui_Text(ctx, '4b. Replace by slot across tracks:')
  -- r.ImGui_SameLine(ctx)
  r.ImGui_SetNextItemWidth(ctx, 80)
  local chgSlot, slot1 = r.ImGui_InputInt(ctx, '##Slot (1-based)##batch', (tonumber(state.batchSlotIndex) or 0) + 1)
  if chgSlot then state.batchSlotIndex = math.max(0, (tonumber(slot1) or 1) - 1) end
 
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, 'Replace', 60) then
    if (not state.slotUsePlaceholder) and (not state.replaceWith or state.replaceWith == '') then
      state.pendingError = 'Pick a replacement plugin first.'
    else
      local addName, alias = state.replaceWith, nil
      if state.slotUsePlaceholder then
        addName = ensure_tk_blank_addname(state.placeholderCustomName)
        alias = state.placeholderCustomName
      end
      local count = select(1, replace_by_slot_across_tracks(state.batchSlotIndex, addName, alias))
      state.pendingMessage = ('Replaced %d track slots.'):format(count)
      rebuild_model()
    end
  end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, 'Add', 60) then
    if (not state.slotUsePlaceholder) and (not state.replaceWith or state.replaceWith == '') then
      state.pendingError = 'Pick a plugin first.'
    else
      local addName, alias = state.replaceWith, nil
      if state.slotUsePlaceholder then
        addName = ensure_tk_blank_addname(state.placeholderCustomName)
        alias = state.placeholderCustomName
      end
      local count = select(1, add_by_slot_across_tracks(state.batchSlotIndex, addName, alias))
      state.pendingMessage = ('Added on %d tracks.'):format(count)
      rebuild_model()
    end
  end
  local chgPH2, vPH2 = r.ImGui_Checkbox(ctx, 'Use Placeholder##slot', state.slotUsePlaceholder)
  if chgPH2 then state.slotUsePlaceholder = vPH2 end
  r.ImGui_Dummy(ctx, 0, 6)
  r.ImGui_Separator(ctx)
  local chgTT, vTT = r.ImGui_Checkbox(ctx, 'Tooltips', state.tooltips)
  if chgTT then
    state.tooltips = vTT
    save_ui_prefs()
  end
end

local function draw_track_fx_rows(trEntry)
  local tr = resolve_track_entry(trEntry)
  if not tr then
    r.ImGui_Text(ctx, '[Track missing]')
    return
  end

  if r.ImGui_BeginTable(ctx, ('fx_table_%p'):format(tr), 5, FLAGS.Table_SizingStretchProp) then
    r.ImGui_TableSetupColumn(ctx, '#', FLAGS.Col_WidthFixed, 20)
    r.ImGui_TableSetupColumn(ctx, 'FX name', FLAGS.Col_WidthStretch)
    r.ImGui_TableSetupColumn(ctx, 'Byp/Offl', FLAGS.Col_WidthFixed, 60)
    r.ImGui_TableSetupColumn(ctx, 'Actions', FLAGS.Col_WidthFixed, 100)
  r.ImGui_TableSetupColumn(ctx, 'Source', FLAGS.Col_WidthFixed, 50)

    local filter = state.filter
    for i, fx in ipairs(trEntry.fxList) do
      if filter == '' or string.find(string.lower(fx.name), string.lower(filter), 1, true) then
        r.ImGui_TableNextRow(ctx)

  r.ImGui_TableSetColumnIndex(ctx, 0)
  r.ImGui_Text(ctx, tostring(fx.idx + 1))
  if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then r.ImGui_SetTooltip(ctx, 'Drop here to place/copy an FX to this slot') end
       
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
  local nameToShow = tostring(fx.name)
  if state.hidePrefix then nameToShow = nameToShow:gsub('^[^:]+:%s*', '') end
  if state.hideDeveloper then nameToShow = nameToShow:gsub('%s*%b()%s*$', '') end
  local label = ("%s##fx%d"):format(nameToShow, fx.idx)
    r.ImGui_Selectable(ctx, label, _sel)
  if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then r.ImGui_SetTooltip(ctx, 'Drag to move within this track. Drop on another track to copy. Drop on the # or Name cell to place.') end
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
            local _pushedBtnStyle = false
            if ENUM and ENUM.Col_Button then
              _pushedBtnStyle = push_style_color(ENUM.Col_Button, 0, 0, 0, 0)
            end
  local btnLabel = fx.enabled and 'On' or 'Off'
  if r.ImGui_SmallButton(ctx, btnLabel .. '##b' .. i) then
          r.Undo_BeginBlock()
          toggle_bypass(tr, fx.idx)
          r.Undo_EndBlock('Toggle FX bypass', -1)
          rebuild_model()
  end
  if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then r.ImGui_SetTooltip(ctx, 'Toggle bypass for this FX') end
        r.ImGui_SameLine(ctx)
        local is_offline = r.TrackFX_GetOffline(tr, fx.idx)
        local offLabel = is_offline and 'Ofl' or 'Onl'
  if r.ImGui_SmallButton(ctx, offLabel .. '##o' .. i) then
          r.Undo_BeginBlock()
          r.TrackFX_SetOffline(tr, fx.idx, not is_offline)
          r.Undo_EndBlock('Toggle FX offline', -1)
          rebuild_model()
  end
  if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then r.ImGui_SetTooltip(ctx, 'Toggle offline (unloads/loads the plugin)') end

        r.ImGui_TableSetColumnIndex(ctx, 3)
        if r.ImGui_SmallButton(ctx, 'Del##' .. i) then
          r.Undo_BeginBlock()
          delete_fx(tr, fx.idx)
          r.Undo_EndBlock('Delete FX', -1)
          rebuild_model()
        end
  if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then r.ImGui_SetTooltip(ctx, 'Delete this FX from the track') end
        r.ImGui_SameLine(ctx)
        do
          local isToggled = has_toggle_for(trEntry.guid, fx.idx)
          local btnLabel = (isToggled and 'Restore##' or 'Replace..##') .. i
          if r.ImGui_SmallButton(ctx, btnLabel) then
            toggle_replace_fx(tr, trEntry.guid, fx.idx)
          end
          if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then
            if isToggled then r.ImGui_SetTooltip(ctx, 'Restore the original FX in this slot') else r.ImGui_SetTooltip(ctx, 'Replace this FX with the chosen plugin (toggle)') end
          end
        end

        r.ImGui_TableSetColumnIndex(ctx, 4)
        local _sp = 0
        if ENUM and ENUM.Col_Button and ENUM.Col_ButtonHovered and ENUM.Col_ButtonActive then
          if push_style_color(ENUM.Col_Button, 0.14, 0.14, 0.14, 1.0) then _sp = _sp + 1 end
          if push_style_color(ENUM.Col_ButtonHovered, 0.22, 0.22, 0.22, 1.0) then _sp = _sp + 1 end
          if push_style_color(ENUM.Col_ButtonActive, 0.10, 0.10, 0.10, 1.0) then _sp = _sp + 1 end
        end
  if r.ImGui_SmallButton(ctx, 'Source##' .. i) then
          state.selectedSourceFXName = fx.name
  end
  if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then r.ImGui_SetTooltip(ctx, 'Set this FX as the Source for batch replace/delete') end
        if _sp > 0 and r.ImGui_PopStyleColor then r.ImGui_PopStyleColor(ctx, _sp) end
            if _pushedBtnStyle and r.ImGui_PopStyleColor then r.ImGui_PopStyleColor(ctx, 1) end
      end
    end

    r.ImGui_EndTable(ctx)
  end
  r.ImGui_Dummy(ctx, 1, 2)
  if r.ImGui_SmallButton(ctx, ('Save chain##%s'):format(tostring(trEntry.guid or trEntry.idx))) then
    if (trEntry.fxList and #trEntry.fxList or 0) == 0 then
      state.pendingError = 'No FX on this track to save.'
    else
      local okS, pathS = save_fx_chain_for_track(tr, get_track_name(tr))
      if okS then state.pendingMessage = 'Saved FX chain: ' .. tostring(pathS) else state.pendingError = pathS end
    end
  end
  if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then r.ImGui_SetTooltip(ctx, 'Save the whole FX chain of this track to an .rfxchain file') end
  r.ImGui_SameLine(ctx)
  if r.ImGui_SmallButton(ctx, ('Replace chain##%s'):format(tostring(trEntry.guid or trEntry.idx))) then
    local sep = package.config:sub(1,1)
    local baseDir = r.GetResourcePath() .. sep .. 'FXChains'
    local init = baseDir .. sep
    local okPick, chosen = r.GetUserFileNameForRead(init, 'Choose FX chain', 'rfxchain')
    if okPick and chosen and chosen ~= '' then
  state.pendingMessage = 'Replacing chain...'
  state.pendingJob = { kind = 'replace_chain', trackGuid = (trEntry.guid or (r.GetTrackGUID and r.GetTrackGUID(tr))), file = chosen }
  state.jobDelayFrames = 1
    end
  end
  if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then r.ImGui_SetTooltip(ctx, 'Load an .rfxchain and replace the whole FX chain on this track') end
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
    
    do
      local selId = ('##sel_%s'):format(tostring(trEntry.guid or trEntry.idx))
      local changedSel, vSel = r.ImGui_Checkbox(ctx, selId, is_sel)
  if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then
        r.ImGui_SetTooltip(ctx, 'Select/deselect this track\nShift+click (on empty): select range from last anchor\nShift+click (on checked): deselect upward until first unchecked')
      end
      if changedSel then
        local shiftDown = false
        if r.ImGui_GetKeyMods and r.ImGui_Mod_Shift then
          local mods = r.ImGui_GetKeyMods(ctx)
          local mshift = r.ImGui_Mod_Shift()
          if type(mods) == 'number' and type(mshift) == 'number' then
            shiftDown = (mods & mshift) ~= 0
          end
        end
        if shiftDown and vSel then
          local anchor = tonumber(state.selAnchorIdx or proj_idx) or proj_idx
          local s = math.min(anchor, proj_idx)
          local e = math.max(anchor, proj_idx)
          for i = s, e do
            local trk = r.GetTrack(0, i - 1)
            if trk then pcall(function() r.SetTrackSelected(trk, true) end) end
          end
          if r.TrackList_AdjustWindows then pcall(function() r.TrackList_AdjustWindows(false) end) end
          if r.UpdateArrange then pcall(function() r.UpdateArrange() end) end
          is_sel = true
        elseif shiftDown and (not vSel) then
          local i = proj_idx
          while i >= 1 do
            local trk = r.GetTrack(0, i - 1)
            if not trk then break end
            local sel = r.IsTrackSelected and (r.IsTrackSelected(trk) == true) or false
            if (not sel) and i ~= proj_idx then break end
            pcall(function() r.SetTrackSelected(trk, false) end)
            i = i - 1
          end
          if r.TrackList_AdjustWindows then pcall(function() r.TrackList_AdjustWindows(false) end) end
          if r.UpdateArrange then pcall(function() r.UpdateArrange() end) end
          is_sel = false
        else
          pcall(function() r.SetTrackSelected(trEntry.track, vSel) end)
          if r.TrackList_AdjustWindows then pcall(function() r.TrackList_AdjustWindows(false) end) end
          if r.UpdateArrange then pcall(function() r.UpdateArrange() end) end
          is_sel = vSel
          if vSel then state.selAnchorIdx = proj_idx end
        end
        rebuild_model()
      end
      r.ImGui_SameLine(ctx)
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
  if job.kind == 'replace_chain' then
    local tr = find_track_by_guid(job.trackGuid)
    if not tr then return end
    r.PreventUIRefresh(1)
    r.Undo_BeginBlock()
    local okR, errR = replace_fx_chain_from_file(tr, job.file)
    r.Undo_EndBlock('Replace FX chain from file', -1)
    r.PreventUIRefresh(-1)
    if okR then
      state.pendingMessage = 'Replaced FX chain: ' .. job.file
      rebuild_model()
    else
      state.pendingError = errR or 'Replace failed'
    end
  else
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
end

local function main_loop()
  ensure_ctx()
  local now = getProjectTimeSec()
  if state.autoRefresh and (now - state.lastRefreshTime) > state.refreshInterval then
    rebuild_model()
    state.lastRefreshTime = now
  end

  local initW = tonumber(state.winW) or 820
  local initH = tonumber(state.winH) or 560
  safe_SetNextWindowSize(initW, initH, FLAGS.Cond_Appearing)
  safe_SetNextWindowSizeConstraints(540, 340, 4096, 4096)
  local stylePush = push_app_style()
  local begunMain, visible, open = safe_Begin(SCRIPT_NAME, true, FLAGS.Window_MenuBar | FLAGS.Window_NoTitleBar)
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
          'Replace panel & picker:\n' ..
          ' - Press Source on a row to choose the source FX.\n' ..
          ' - Placement: Same slot / Start / End / Index (slot is 1-based).\n' ..
          ' - Pick from list… uses Sexan\'s FX parser. Use the Types dropdown to filter by CLAP/VST/VST3/JS/etc.\n' ..
          ' - Short list holds your favorites (+ in picker, x in dropdown).\n' ..
          ' - Replace all instances replaces the source FX across the current scope.\n' ..
          ' - Delete all instances removes all occurrences of the chosen Source FX across the current scope.\n' ..
          ' - Replace by slot across tracks: choose a slot number and replace that slot on each track in scope.\n' ..
          ' - Add across tracks: add the chosen plugin at the given slot (or at end if the slot exceeds the FX count).\n' ..
          '   • Tip: use the global "Selected tracks only" at the top to limit scope for all actions.\n\n' ..
          'Per-FX row actions:\n' ..
          ' - Drag the FX name to reorder within a track (move) or drop on another track (copy).\n' ..
          ' - Drop is accepted on the # cell and the Name cell.\n' ..
          ' - On/Off toggles bypass. Ofl/Onl toggles offline. Del deletes.\n' ..
          ' - Replace is a toggle: first click replaces with the chosen plugin; next click (Restore) brings the original back in the same slot.\n' ..
          ' - Source marks this FX for batch Replace all instances.\n\n' ..
          'Track FX chains (per track, under the list):\n' ..
          ' - Save chain writes the current track FX to REAPER/FXChains (.rfxchain).\n' ..
          ' - Replace chain loads an .rfxchain and replaces the whole FX chain on the track.\n\n' ..
          'Status, performance & safety:\n' ..
          ' - Progress and errors show at the bottom; long operations (FX placements and chain replace) are non-blocking and can be Cancelled.\n' ..
          ' - Loading heavy plugins or chains can take time while plugins initialize.\n' ..
          ' - If tracks are deleted while open, the view auto-recovers.')
          , SCRIPT_NAME, 0)
      end
      r.ImGui_SameLine(ctx)
      if r.ImGui_MenuItem(ctx, 'Print plugin list') then
        local okP, pathP = print_plugin_list()
        if okP then state.pendingMessage = 'Saved plugin list: ' .. tostring(pathP) else state.pendingError = pathP end
      end
  local availW = select(1, r.ImGui_GetContentRegionAvail(ctx)) or 0
  local tw, th = r.ImGui_CalcTextSize(ctx, 'Close')
  local btnW = (tw or 40)
  local spacing = (availW or 0) - btnW
  if spacing < 0 then spacing = 0 end
  r.ImGui_SameLine(ctx, 0, spacing)
  local pushed = 0
  if ENUM.Col_Button and push_style_color(ENUM.Col_Button, 0.65, 0.15, 0.15, 1.0) then pushed = pushed + 1 end
  if ENUM.Col_ButtonHovered and push_style_color(ENUM.Col_ButtonHovered, 0.80, 0.20, 0.20, 1.0) then pushed = pushed + 1 end
  if ENUM.Col_ButtonActive and push_style_color(ENUM.Col_ButtonActive, 0.55, 0.10, 0.10, 1.0) then pushed = pushed + 1 end
  if r.ImGui_SmallButton(ctx, 'Close') then open = false end
  if pushed > 0 and r.ImGui_PopStyleColor then r.ImGui_PopStyleColor(ctx, pushed) end
  r.ImGui_EndMenuBar(ctx)
    end
    local fullW, fullH = r.ImGui_GetContentRegionAvail(ctx)
  local sidebarW = math.max(220, math.min(480, state.sidebarWidth or 220))

    local leftVisible = r.ImGui_BeginChild(ctx, 'left_sidebar', sidebarW, 0, 1)
    if leftVisible then
      draw_replace_panel()
    end
    if leftVisible then r.ImGui_EndChild(ctx) end
    
  r.ImGui_SameLine(ctx)
  local splitter_w = 6
  local dl = r.ImGui_GetWindowDrawList(ctx)
  local x1, y1 = r.ImGui_GetCursorScreenPos(ctx)
  local availH = select(2, r.ImGui_GetContentRegionAvail(ctx)) or 1
  if availH < 1 then availH = 1 end
  local x2, y2 = x1 + splitter_w, y1 + availH
  r.ImGui_InvisibleButton(ctx, '##vsplit', splitter_w, availH)
  local hovered = r.ImGui_IsItemHovered(ctx)
  local active  = r.ImGui_IsItemActive(ctx)
    local cx = x1 + math.floor(splitter_w/2)
    local line_w = hovered and 2 or 1
    local col
    if active then
      col = 0xE0FFFFFF; line_w = 3
    elseif hovered then
      col = 0x90FFFFFF
    else
      col = 0x50808080
    end
  r.ImGui_DrawList_AddRectFilled(dl, cx - math.floor(line_w/2), y1, cx + math.ceil(line_w/2), y2, col)
    if active then
      local dx = 0
      if r.ImGui_GetMouseDelta then
        local mdx = select(1, r.ImGui_GetMouseDelta(ctx)) or 0
        dx = mdx
      end
  local newW = math.max(180, math.min(520, (state.sidebarWidth or 220) + dx))
  local contentW = (select(1, r.ImGui_GetWindowSize(ctx)) or 0) - 24
      if newW < contentW - 220 then state.sidebarWidth = newW end
    end
    r.ImGui_SameLine(ctx)
    
  local rightFlags = (flag(r.ImGui_WindowFlags_NoScrollbar) or 0) | (flag(r.ImGui_WindowFlags_NoScrollWithMouse) or 0)
  local rightVisible = r.ImGui_BeginChild(ctx, 'right_content', 0, 0, 0, rightFlags)
    if rightVisible then
      draw_compact_toolbar()
      r.ImGui_Separator(ctx)
      local tracksVisible = r.ImGui_BeginChild(ctx, 'tracks_panel_scroll', 0, 0, 0)
      if tracksVisible then
        draw_tracks_panel()
      end
      if tracksVisible then r.ImGui_EndChild(ctx) end
      r.ImGui_Separator(ctx)
      draw_status_bar()
    end
    if rightVisible then r.ImGui_EndChild(ctx) end
  end
  if begunMain then
    if visible then
      local cw, ch = r.ImGui_GetWindowSize(ctx)
      state.winW, state.winH = cw, ch
    end
    r.ImGui_End(ctx)
  end
  pop_app_style(stylePush)
  draw_plugin_picker()
  process_pending_job()
  if not (open == nil or open) then
    local cw, ch = state.winW or 0, state.winH or 0
    if (cw or 0) > 0 and (ch or 0) > 0 then save_window_size(cw, ch) end
  save_ui_prefs()
  end
  if open == nil or open then
    r.defer(main_loop)
  end
end

rebuild_model()
r.defer(function()
  favs_load()
  load_window_size()
  load_ui_prefs()
  main_loop()
end)
