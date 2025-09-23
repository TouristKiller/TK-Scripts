-- @author TouristKiller
-- @version 0.3.0
-- @changelog
--   - Startup now always loads plugins: if cache is missing or empty, parse once immediately and refresh cache (no Rescan required).
--   - Keeps fast starts when cache exists; Rescan still rebuilds and updates cache on demand.
-- @about
--   Minimal FX browser for take FX using Sexan's FX Parser v7.
--   Filters instruments out (since this is for audio takes). Adds FX to all selected audio takes.

local r = reaper
local settings

local SCRIPT_DIR = debug.getinfo(1, 'S').source:match('@?(.*[/\\])') or ''
local function load_json_module()
  local candidates = { 'json_raw.lua', 'json.lua' }
  for _, fn in ipairs(candidates) do
    local p = SCRIPT_DIR .. fn
    if r.file_exists(p) then
      local ok, mod = pcall(dofile, p)
      if ok and mod then return mod end
    end
  end
  r.ShowMessageBox('JSON module not found next to FX browser.\nExpected json_raw.lua or json.lua in:\n' .. SCRIPT_DIR, 'TK RAW fx browser', 0)
  return { encode = function() return '{}' end, decode = function() return nil end }
end
local json = load_json_module()
local SETTINGS_FILE = SCRIPT_DIR .. 'TK_RAW_fx_browser.settings.json'
local CACHE_FILE    = SCRIPT_DIR .. 'TK_RAW_fx_browser.cache.json'
local LUA_CACHE_FILE = SCRIPT_DIR .. 'TK_RAW_fx_browser.cache.lua'
local SEXAN_PARSER = r.GetResourcePath() .. '/Scripts/Sexan_Scripts/FX/Sexan_FX_Browser_ParserV7.lua'
local function file_exists(path)
  return r.file_exists(path)
end

local function ensure_sexan_parser()
  if not file_exists(SEXAN_PARSER) then
    if r.ReaPack_BrowsePackages then
      r.ShowMessageBox('Sexan FX Browser Parser V7 is missing. Opening ReaPack to install.', 'Missing dependency', 0)
      r.ReaPack_BrowsePackages('"sexan fx browser parser v7"')
    else
      r.ShowMessageBox('Sexan FX Browser Parser V7 not found. Please install via ReaPack.', 'Missing dependency', 0)
    end
    return false, 'Parser not found'
  end
  local ok, err = pcall(dofile, SEXAN_PARSER)
  if not ok then return false, 'Sexan parser error: ' .. tostring(err) end
  return true
end

local function bind_parser_functions()
  local ReadFXFile   = _G.ReadFXFile
  local MakeFXFiles  = _G.MakeFXFiles
  local ReadCATFile  = _G.ReadCATFile
  local MakeCATFile  = _G.MakeCATFile
  local ReadDEVFile  = _G.ReadDEVFile
  local MakeDEVFile  = _G.MakeDEVFile
  local GetFXTbl     = _G.GetFXTbl
  local FXB          = _G.FXB
  return {
    ReadFXFile = ReadFXFile,
    MakeFXFiles = MakeFXFiles,
    ReadCATFile = ReadCATFile,
    MakeCATFile = MakeCATFile,
    ReadDEVFile = ReadDEVFile,
    MakeDEVFile = MakeDEVFile,
    GetFXTbl = GetFXTbl,
    FXB = FXB,
  }
end

local function safe_lower(s) return tostring(s or ''):lower() end

local function ends_with(str, suffix)
  str = tostring(str or '')
  suffix = tostring(suffix or '')
  return suffix ~= '' and str:sub(-#suffix) == suffix or false
end

local function is_instrument(entry)
  local t = entry.type or ''
  local add = entry.addname or ''
  if type(t) == 'string' and ends_with(t, 'i') then return true end
  if add:find('^VSTi%s*:') or add:find('^CLAPi%s*:') then return true end
  return false
end

local function build_display_name(entry)
  local name = entry.NAME or entry.Name or entry.name or 'Unknown'
  local dev = entry.DEVELOPER or entry.VENDOR or entry.Vendor or ''
  if dev ~= '' then return string.format('%s — %s', name, dev) end
  return name
end
local function format_fx_label(e)
  local token = (e and e.addname) or ''
  if not (settings and settings.cleanName) or token == '' then
    return token ~= '' and token or (e and e.name or '')
  end
  local s = token
  s = s:gsub('^%s*[%w_]+%s*:%s*', '')
  local vend = e and e.vendor or ''
  if vend ~= '' then
    local esc = vend:gsub('([^%w%s])', '%%%1')
    s = s:gsub('%s*%(' .. esc .. '%)%s*$', '')
  else
    s = s:gsub('%s*%([^)]-*%)%s*$', '')
  end
  -- trim
  s = s:gsub('^%s+', ''):gsub('%s+$', '')
  return s
end

local function get_addname(entry)
  return entry.addname or entry.ADDNAME or entry.AddName or entry.name or entry.NAME or ''
end

local function extract_fx_entry(entry)
  local t = type(entry)
  if t == 'string' then return entry, entry end
  if t == 'table' then
    local name = entry.name or entry.fxname or entry.fxName or entry.fname or entry.FX_NAME or entry.NAME or entry[1]
    local add  = entry.addname or entry.fullname or entry.name or entry.fxname or entry[2] or entry.ADDNAME or name
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
      items[#items+1] = { name = disp, addname = add }
      seen[add] = true
    end
    for _, v in pairs(obj) do
      if type(v) == 'table' or type(v) == 'string' then
        flatten_plugins(v, items, seen, depth + 1)
      end
    end
  elseif t == 'string' then
    if not seen[obj] then items[#items+1] = { name = obj, addname = obj }; seen[obj] = true end
  end
end

local function infer_type_from_add(add)
  local t = add:match('^%s*([%w_]+)%s*:')
  return t or ''
end

local function infer_vendor_from_add(add)
  if not add or add == '' then return '' end
  local v = add:match('%((.-)%)%s*$')
  if v and v ~= '' then return v end
  return ''
end

local function load_all_fx()
  local okParser, perr = ensure_sexan_parser()
  if okParser == false then return nil, perr end
  local api = bind_parser_functions()
  local list = nil
  local cat_data = nil
  if type(api.GetFXTbl) == 'function' then
    local ok, res = pcall(api.GetFXTbl)
    if ok then list = res end
  end
  if type(api.ReadFXFile) == 'function' then
    local FX_LIST, CAT_TEST_RET, FX_DEV_LIST_FILE = api.ReadFXFile()
    if (not FX_LIST or not CAT_TEST_RET or not FX_DEV_LIST_FILE) and type(api.MakeFXFiles) == 'function' then
      FX_LIST, CAT_TEST_RET, FX_DEV_LIST_FILE = api.MakeFXFiles()
    end
    if CAT_TEST_RET then cat_data = CAT_TEST_RET end
    if not list and type(api.GetFXTbl) == 'function' then
      local ok, res = pcall(api.GetFXTbl)
      if ok then list = res end
    end
  end
  if not list and type(api.FXB) == 'table' and type(api.FXB.BuildFXList) == 'function' then
    local okB, resB = pcall(api.FXB.BuildFXList)
    if okB then list = resB end
  end
  if not cat_data then
    if type(api.ReadCATFile) == 'function' then
      local okc, c = pcall(api.ReadCATFile)
      if okc then cat_data = c end
    end
    if not cat_data and type(api.MakeCATFile) == 'function' then
      local okm, c2 = pcall(api.MakeCATFile)
      if okm then cat_data = c2 end
    end
  end
  if not list then return nil, 'Could not load plugin list from Sexan parser.' end

  _G.__TK_CAT_DATA = cat_data or _G.__TK_CAT_DATA

  local flat, seen = {}, {}
  flatten_plugins(list, flat, seen, 0)
  local out = {}
  for _, it in ipairs(flat) do
    local add = get_addname(it)
    if add and add ~= '' then
      local tp = infer_type_from_add(add)
      local vendor = infer_vendor_from_add(add)
      out[#out+1] = { name = it.name or build_display_name(it), addname = add, type = tp, vendor = vendor }
    end
  end
  table.sort(out, function(a,b) return safe_lower(a.name) < safe_lower(b.name) end)
  return out
end

local function save_cache()
  local payload = { fx = ALL_FX or {}, cat = rawget(_G, '__TK_CAT_DATA') }
  local okj, txt = pcall(json.encode, payload)
  if okj then local fh = io.open(CACHE_FILE, 'w'); if fh then fh:write(txt) fh:close() end end
  local function serialize(v)
    local t = type(v)
    if t == 'string' then return string.format('%q', v) end
    if t == 'number' or t == 'boolean' or v == nil then return tostring(v) end
    if t == 'table' then
      local is_array = true
      local maxn = 0
      for k in pairs(v) do
        if type(k) ~= 'number' then is_array = false break end
        if k > maxn then maxn = k end
      end
      local parts = {}
      if is_array then
        for i=1,maxn do parts[#parts+1] = serialize(v[i]) end
      else
        for k,val in pairs(v) do
          local key
          if type(k) == 'string' and k:match('^[_%a][_%w]*$') then
            key = k .. '=' .. serialize(val)
          else
            key = '[' .. serialize(k) .. ']=' .. serialize(val)
          end
          parts[#parts+1] = key
        end
      end
      return '{' .. table.concat(parts, ',') .. '}'
    end
    return 'nil'
  end
  local lua_txt = 'return ' .. serialize(payload)
  local fh2 = io.open(LUA_CACHE_FILE, 'w')
  if fh2 then fh2:write(lua_txt) fh2:close() end
end

local function load_cache()
  if file_exists(LUA_CACHE_FILE) then
    local ok, obj = pcall(dofile, LUA_CACHE_FILE)
    local function valid_obj(o)
      if type(o) ~= 'table' then return false end
      if type(o.fx) ~= 'table' then return false end
      local checked = 0
      for i=1, math.min(#o.fx, 10) do
        local e = o.fx[i]
        if type(e) == 'table' and type(e.addname) == 'string' and e.addname ~= '' then
          checked = checked + 1
        end
      end
      return checked >= 3
    end
    if ok and valid_obj(obj) then
      ALL_FX = obj.fx or {}
      _G.__TK_CAT_DATA = obj.cat or _G.__TK_CAT_DATA
      return true
    end
  end
  local fh = io.open(CACHE_FILE, 'r')
  if not fh then return false end
  local txt = fh:read('*a'); fh:close()
  local okj, obj = pcall(json.decode, txt)
  if not okj or type(obj) ~= 'table' then return false end
  ALL_FX = obj.fx or {}
  _G.__TK_CAT_DATA = obj.cat or _G.__TK_CAT_DATA
  return true
end

ALL_FX = {}
local DATA_SOURCE = 'unknown'
local BOOTSTRAPPED_NOW = false

local function has_valid_tokens(list)
  if type(list) ~= 'table' then return false end
  local good = 0
  for i=1, math.min(#list, 20) do
    local e = list[i]
    local s = e and e.addname
    if type(s) == 'string' and s:match('^%s*[%w_]+%s*:') then good = good + 1 end
  end
  return good >= 3
end

local function quick_read_bootstrap_flag()
  local fh = io.open(SETTINGS_FILE, 'r')
  if not fh then return false end
  local txt = fh:read('*a'); fh:close()
  local okj, obj = pcall(json.decode, txt)
  if okj and type(obj) == 'table' then
    return obj.bootstrap_done == true
  end
  return false
end

local cache_ok = load_cache()
if cache_ok and ALL_FX and #ALL_FX > 0 then
  if not has_valid_tokens(ALL_FX) then
    local fresh, err = load_all_fx()
    if fresh and #fresh > 0 then
      ALL_FX = fresh
      save_cache()
      DATA_SOURCE = 'fresh'
      BOOTSTRAPPED_NOW = true
    else
      DATA_SOURCE = 'cache'
    end
  else
    DATA_SOURCE = 'cache'
  end
else
  local fresh, err = load_all_fx()
  if fresh and #fresh > 0 then
    ALL_FX = fresh
    save_cache()
    DATA_SOURCE = 'fresh'
    BOOTSTRAPPED_NOW = true
  else
  end
end

local FX_INDEX = {}
local VENDORS = {}
local CATEGORIES = {}
local DEV_MAP = {}
local CAT_MAP = {}
local DEV_KEYS = {}
local CAT_KEYS = {}
local FOLDER_MAP = {}
local FOLDERS = {}
local VIS_CACHE = { vendors = {}, categories = {}, folders = {}, dirty = true }
local SORT_CACHE = { key = nil, items = nil }
local FAV_GEN = 0
local DATA_GEN = 0
local function rebuild_indexes()
  FX_INDEX, VENDORS, CATEGORIES = {}, {}, {}
  local vset, cset = {}, {}
  for _, e in ipairs(ALL_FX) do
    if e.addname then FX_INDEX[e.addname] = e end
    if not e.vendor or e.vendor == '' then e.vendor = infer_vendor_from_add(e.addname or '') end
    local vend = (e.vendor and e.vendor ~= '' and e.vendor) or 'Unknown'
    if not vset[vend] then vset[vend] = true; VENDORS[#VENDORS+1] = vend end
    local cat = (e.type and e.type ~= '' and e.type) or 'Other'
    if not cset[cat] then cset[cat] = true; CATEGORIES[#CATEGORIES+1] = cat end
  end
  table.sort(VENDORS, function(a,b) return safe_lower(a) < safe_lower(b) end)
  table.sort(CATEGORIES, function(a,b) return safe_lower(a) < safe_lower(b) end)
  DATA_GEN = (DATA_GEN or 0) + 1
end
local function rebuild_from_cat()
  FOLDER_MAP, FOLDERS = {}, {}
  DEV_MAP, CAT_MAP = {}, {}
  DEV_KEYS, CAT_KEYS = {}, {}
  local CAT_DATA = rawget(_G, '__TK_CAT_DATA')
  if type(CAT_DATA) ~= 'table' then return end
  for _, cat in ipairs(CAT_DATA) do
    if cat and cat.name == 'FOLDERS' and type(cat.list) == 'table' then
      for _, entry in ipairs(cat.list) do
        local fname = entry and entry.name
        local fx = entry and entry.fx
        if type(fname) == 'string' and type(fx) == 'table' then
          local set = {}
          for _, t in ipairs(fx) do if type(t) == 'string' then set[t] = true end end
          FOLDER_MAP[fname] = set
          FOLDERS[#FOLDERS+1] = fname
        end
      end
    elseif cat and cat.name == 'DEVELOPER' and type(cat.list) == 'table' then
      for _, entry in ipairs(cat.list) do
        local dname = entry and entry.name
        local fx = entry and entry.fx
        if type(dname) == 'string' and type(fx) == 'table' then
          local set = {}
          for _, t in ipairs(fx) do if type(t) == 'string' then set[t] = true end end
          DEV_MAP[dname] = set
          DEV_KEYS[#DEV_KEYS+1] = dname
        end
      end
    elseif cat and cat.name == 'CATEGORY' and type(cat.list) == 'table' then
      for _, entry in ipairs(cat.list) do
        local cname = entry and entry.name
        local fx = entry and entry.fx
        if type(cname) == 'string' and type(fx) == 'table' then
          local set = {}
          for _, t in ipairs(fx) do if type(t) == 'string' then set[t] = true end end
          CAT_MAP[cname] = set
          CAT_KEYS[#CAT_KEYS+1] = cname
        end
      end
    end
  end
  table.sort(FOLDERS, function(a,b) return safe_lower(a) < safe_lower(b) end)
  table.sort(DEV_KEYS, function(a,b) return safe_lower(a) < safe_lower(b) end)
  table.sort(CAT_KEYS, function(a,b) return safe_lower(a) < safe_lower(b) end)
  VIS_CACHE.dirty = true
end
rebuild_indexes()
rebuild_from_cat()

settings = { favorites = {}, recents = {}, filters = { VST3 = true, VST = true, VSTi = false, CLAP = true, CLAPi = false, JS = true, Other = true }, hideInstruments = true, sidebar_w = 220, bootstrap_done = false, sort = { col = 1, dir = 'asc' }, singleClickAdd = false, doubleClickInterval = 0.60, cleanName = false, searchAll = false, rememberLastNav = false, lastNav = nil }
local save_settings 
local function load_settings()
  local fh = io.open(SETTINGS_FILE, 'r')
  if fh then
    local txt = fh:read('*a') fh:close()
    local okj, obj = pcall(json.decode, txt)
    if okj and type(obj) == 'table' then settings = obj end
  end
  settings.favorites = settings.favorites or {}
  settings.recents = settings.recents or {}
  settings.hideInstruments = (settings.hideInstruments ~= false)
  settings.sidebar_w = tonumber(settings.sidebar_w) or 170
  settings.filters = settings.filters or {}
  settings.sort = settings.sort or { col = 1, dir = 'asc' }
  if settings.sort.col == nil then settings.sort.col = 1 end
  if settings.sort.dir ~= 'asc' and settings.sort.dir ~= 'desc' then settings.sort.dir = 'asc' end
  if settings.singleClickAdd == nil then settings.singleClickAdd = false end
  if type(settings.doubleClickInterval) ~= 'number' then settings.doubleClickInterval = 0.60 end
  if settings.cleanName == nil then settings.cleanName = false end
  if settings.searchAll == nil then settings.searchAll = false end
  if settings.rememberLastNav == nil then settings.rememberLastNav = false end
  if settings.lastNav ~= nil and type(settings.lastNav) ~= 'table' then settings.lastNav = nil end
  if settings.bootstrap_done == nil then settings.bootstrap_done = false end
  local f = settings.filters
  if f.VST3 == nil then f.VST3 = true end
  if f.VST == nil then f.VST = true end
  if f.VSTi == nil then f.VSTi = false end
  if f.CLAP == nil then f.CLAP = true end
  if f.CLAPi == nil then f.CLAPi = false end
  if f.JS == nil then f.JS = true end
  if f.Other == nil then f.Other = true end
  if not settings._migrated_left120 then
    if (settings.sidebar_w or 170) >= 200 then
      settings.sidebar_w = 170
      settings._migrated_left120 = true
      save_settings()
    else
      settings._migrated_left120 = true
      save_settings()
    end
  end
  if not settings._migrated_min200 then
    if (settings.sidebar_w or 170) < 200 then
      settings.sidebar_w = 200
    end
    settings._migrated_min200 = true
    save_settings()
  end
end

save_settings = function()
  local okj, txt = pcall(json.encode, settings)
  if okj then local fh = io.open(SETTINGS_FILE, 'w') if fh then fh:write(txt) fh:close() end end
end
load_settings()
if BOOTSTRAPPED_NOW and not settings.bootstrap_done then
  settings.bootstrap_done = true
  save_settings()
end

local function is_favorite(addname) return settings.favorites and settings.favorites[addname] == true end
local function toggle_favorite(addname)
  if not settings.favorites then settings.favorites = {} end
  settings.favorites[addname] = not settings.favorites[addname] or nil
  save_settings()
  FAV_GEN = (FAV_GEN or 0) + 1
end

local function push_recent(addname)
  settings.recents = settings.recents or {}
  local newlist, seen = { addname }, { [addname] = true }
  for _, t in ipairs(settings.recents) do if not seen[t] then newlist[#newlist+1] = t end end
  while #newlist > 20 do table.remove(newlist) end
  settings.recents = newlist
  save_settings()
end

local __last_fail = { t = 0, tok = '' }
local function add_fx_to_selected_takes(token, open_ui)
  token = tostring(token or ''):gsub('^%s+', ''):gsub('%s+$', '')
  if token == '' then return false end
  r.Undo_BeginBlock()
  local proj = 0
  local added = 0
  local audio_candidates = 0
  for i = 0, r.CountSelectedMediaItems(proj)-1 do
    local item = r.GetSelectedMediaItem(proj, i)
    local take = item and r.GetActiveTake(item)
    if take then
      local src = r.GetMediaItemTake_Source(take)
      local st = r.GetMediaSourceType(src, '')
      if st ~= 'MIDI' then
        audio_candidates = audio_candidates + 1
        local idx = r.TakeFX_AddByName(take, token, 1)
        if idx < 0 then
          local no_vendor = token:gsub('%s*%([^)]-%)%s*$', '')
          if no_vendor ~= token then idx = r.TakeFX_AddByName(take, no_vendor, 1) end
        end
        if idx < 0 then
          local no_prefix = token:gsub('^%s*[%w_]+%s*:%s*', '')
          if no_prefix ~= token then idx = r.TakeFX_AddByName(take, no_prefix, 1) end
        end
        if idx >= 0 then
          added = added + 1
          if open_ui then r.TakeFX_Show(take, idx, 3) end
        end
      end
    end
  end
  r.Undo_EndBlock(added > 0 and ('FX: add to selected takes (' .. tostring(added) .. ')') or 'FX: no-op', -1)
  if added == 0 then
    local now = (r.time_precise and r.time_precise()) or os.clock()
    if (now - (__last_fail.t or 0)) > 2.0 then
      __last_fail.t = now
      __last_fail.tok = token
      if audio_candidates == 0 then
        r.ShowMessageBox('No audio takes selected. Select at least one audio take and try again.', 'Add FX', 0)
      else
        r.ShowMessageBox('Could not add FX with token:\n' .. token .. '\nMake sure the plugin is installed and compatible with take FX.', 'Add FX', 0)
      end
    end
  end
  return added > 0
end

local ctx = r.ImGui_CreateContext('TK RAW fx browser')
if not ctx then return end
r.SetExtState('TK_RAW_FX_BROWSER', 'running', '1', false)

local state = {
  query = '',
  showFav = false, 
  showRecents = true,
  openUI = true,
  needRescan = false,
  win_open = true,
  selIndex = 1,
  nav = { root = 'favorites', mode = 'all', vendor = nil, category = nil, folder = nil },
  navScrollPending = false,
}

local developer_has_visible_fx
local category_has_visible_fx
local folder_has_visible_fx
local match_format
local function recompute_visibility()
  VIS_CACHE.vendors, VIS_CACHE.categories, VIS_CACHE.folders = {}, {}, {}
  for _, name in ipairs(DEV_KEYS) do
    local set = DEV_MAP[name]
    local vis = false
    if set then
      for addname in pairs(set) do
        local e = FX_INDEX[addname]
        if e and match_format(settings.filters, e.type) and not is_instrument(e) then vis = true break end
      end
    end
    VIS_CACHE.vendors[name] = vis
  end
  for _, name in ipairs(CAT_KEYS) do
    local set = CAT_MAP[name]
    local vis = false
    if set then
      for addname in pairs(set) do
        local e = FX_INDEX[addname]
        if e and match_format(settings.filters, e.type) and not is_instrument(e) then vis = true break end
      end
    end
    VIS_CACHE.categories[name] = vis
  end
  for _, name in ipairs(FOLDERS) do
    local set = FOLDER_MAP[name]
    local vis = false
    if set then
      for addname in pairs(set) do
        local e = FX_INDEX[addname]
        if e and match_format(settings.filters, e.type) and not is_instrument(e) then vis = true break end
      end
    end
    VIS_CACHE.folders[name] = vis
  end
  VIS_CACHE.dirty = false
end

local function is_valid_nav(nav)
  if type(nav) ~= 'table' then return false end
  local root = nav.root
  if root == 'favorites' then
    return true
  elseif root == 'all' then
    local m = nav.mode or 'all'
    local ok = (m == 'all' or m == 'VST3' or m == 'VST' or m == 'CLAP' or m == 'JS' or m == 'Other')
    return ok
  elseif root == 'developer' then
    return nav.vendor ~= nil and DEV_MAP[nav.vendor] ~= nil and developer_has_visible_fx(nav.vendor)
  elseif root == 'category' then
    return nav.category ~= nil and CAT_MAP[nav.category] ~= nil and category_has_visible_fx(nav.category)
  elseif root == 'folders' then
    return nav.folder ~= nil and FOLDER_MAP[nav.folder] ~= nil and folder_has_visible_fx(nav.folder)
  end
  return false
end

local function apply_remembered_nav_if_any()
  if settings.rememberLastNav and settings.lastNav and is_valid_nav(settings.lastNav) then
    local ln = settings.lastNav
    state.nav = { root = ln.root, mode = ln.mode, vendor = ln.vendor, category = ln.category, folder = ln.folder }
    state.navScrollPending = true
  else
    state.nav = { root = 'favorites', mode = 'all', vendor = nil, category = nil, folder = nil }
    state.navScrollPending = true
  end
end


local function persist_nav()
  settings.lastNav = { root = state.nav.root, mode = state.nav.mode, vendor = state.nav.vendor, category = state.nav.category, folder = state.nav.folder }
  save_settings()
end

local __last_add = { id = nil, t = 0 }
local __last_click = { id = nil, t = 0 }
local function maybe_add_fx_ui(e, trigger)
  if not e or not e.addname or e.addname == '' then return end
  local now = (r.time_precise and r.time_precise()) or os.clock()
  if trigger == 'double' and settings.singleClickAdd then
    if __last_add.id == e.addname and (now - (__last_add.t or 0)) < 0.35 then
      return
    end
  end
  local ok = add_fx_to_selected_takes(e.addname, state.openUI)
  if ok then push_recent(e.addname) end
  __last_add.id = e.addname
  __last_add.t = now
end

match_format = function(filter, t)
  t = tostring(t or '')
  if ends_with(t, 'i') then return false end
  if t == 'VST3' then return filter.VST3 end
  if t == 'VST' then return filter.VST end
  if t == 'CLAP' then return filter.CLAP end
  if t == 'JS' then return filter.JS end
  return filter.Other
end

local function __set_has_visible_fx(set)
  if type(set) ~= 'table' then return false end
  for addname, _ in pairs(set) do
    local e = FX_INDEX[addname]
    if e and match_format(settings.filters, e.type) and not is_instrument(e) then
      return true
    end
  end
  return false
end

developer_has_visible_fx = function(name)
  if VIS_CACHE.dirty then recompute_visibility() end
  return VIS_CACHE.vendors[name] == true
end

category_has_visible_fx = function(name)
  if VIS_CACHE.dirty then recompute_visibility() end
  return VIS_CACHE.categories[name] == true
end

folder_has_visible_fx = function(name)
  if VIS_CACHE.dirty then recompute_visibility() end
  return VIS_CACHE.folders[name] == true
end

apply_remembered_nav_if_any()

local function get_scope_text()
  local n = state.nav or {}
  if n.root == 'favorites' then return 'Favorites' end
  if n.root == 'all' then return (n.mode == 'all') and 'All Plugins' or ('All Plugins / ' .. tostring(n.mode)) end
  if n.root == 'developer' then return 'Developer / ' .. tostring(n.vendor) end
  if n.root == 'category' then return 'Category / ' .. tostring(n.category) end
  if n.root == 'folders' then return 'Folders / ' .. tostring(n.folder) end
  return '(all)'
end

local function get_filtered()
  local q = safe_lower(state.query)
  local out = {}
  local nav = state.nav or { root = 'all', mode = 'all' }

  local function include(e)
    if not match_format(settings.filters, e.type) then return false end
    if is_instrument(e) then return false end
    if q ~= '' then
      local n = safe_lower(e.name)
      local a = safe_lower(e.addname)
      if not n:find(q, 1, true) and not a:find(q, 1, true) then return false end
    end
    return true
  end

  if (settings.searchAll == true) and (q ~= '') then
    for _, e in ipairs(ALL_FX) do
      if include(e) then out[#out+1] = e end
    end
  elseif nav.root == 'folders' and nav.folder and FOLDER_MAP[nav.folder] then
    local fset = FOLDER_MAP[nav.folder]
    for _, e in ipairs(ALL_FX) do
      if fset[e.addname] and include(e) then out[#out+1] = e end
    end
  elseif nav.root == 'developer' then
    local dset = (nav.vendor and DEV_MAP[nav.vendor]) or nil
    if dset then
      for _, e in ipairs(ALL_FX) do
        if dset[e.addname] and include(e) then out[#out+1] = e end
      end
    end
  elseif nav.root == 'category' then
    local cset = (nav.category and CAT_MAP[nav.category]) or nil
    if cset then
      for _, e in ipairs(ALL_FX) do
        if cset[e.addname] and include(e) then out[#out+1] = e end
      end
    end
  else
    for _, e in ipairs(ALL_FX) do
      if include(e) then
        local ok = true
        if nav.root == 'favorites' then ok = is_favorite(e.addname) end
        if ok and nav.root == 'all' and nav.mode and nav.mode ~= 'all' then
          local tp = e.type or 'Other'
          if nav.mode ~= tp and not (nav.mode == 'Other' and tp == 'Other') then ok = false end
        end
        if ok then out[#out+1] = e end
      end
    end
  end

  if state.selIndex < 1 then state.selIndex = 1 end
  if #out == 0 then state.selIndex = 1 elseif state.selIndex > #out then state.selIndex = #out end
  return out
end

local function draw_left_panel(height)
  local lp_flags = (r.ImGui_ChildFlags_Border and r.ImGui_ChildFlags_Border()) or 0
  r.ImGui_BeginChild(ctx, 'left', settings.sidebar_w or 260, height, lp_flags)
  local avail_w = (settings.sidebar_w or 260)
  local inner_h = math.max(40, (height or 0) - 2)
  local child_flags = (r.ImGui_ChildFlags_Border and r.ImGui_ChildFlags_Border()) or 0
  r.ImGui_BeginChild(ctx, 'left_scroll', avail_w, inner_h, child_flags)

  local nav = state.nav
  if r.ImGui_Selectable(ctx, 'Favorites', nav.root == 'favorites') then
    state.nav = { root = 'favorites', mode = 'all', vendor = nil, category = nil }
    state.selIndex = 1
    if settings.rememberLastNav then persist_nav() end
  end
  if state.nav and state.nav.root == 'all' and r.ImGui_SetNextItemOpen then
    local cond = r.ImGui_Cond_Appearing and r.ImGui_Cond_Appearing() or nil
    r.ImGui_SetNextItemOpen(ctx, true, cond)
  end
  if r.ImGui_TreeNode(ctx, 'All Plugins') then
    if r.ImGui_Selectable(ctx, 'All', nav.root == 'all' and nav.mode == 'all') then
      state.nav = { root = 'all', mode = 'all' }
      state.selIndex = 1
      if settings.rememberLastNav then persist_nav() end
    end
    local types = { 'VST3', 'VST', 'CLAP', 'JS', 'Other' }
    for i, typ in ipairs(types) do
      r.ImGui_PushID(ctx, 'typ_' .. tostring(i))
      local sel = (nav.root == 'all' and nav.mode == typ)
      if r.ImGui_Selectable(ctx, typ, sel) then
        state.nav = { root = 'all', mode = typ }
        state.selIndex = 1
        if settings.rememberLastNav then persist_nav() end
      end
      r.ImGui_PopID(ctx)
    end
    r.ImGui_TreePop(ctx)
  end
  if state.nav and state.nav.root == 'developer' and r.ImGui_SetNextItemOpen then
    local cond = r.ImGui_Cond_Appearing and r.ImGui_Cond_Appearing() or nil
    r.ImGui_SetNextItemOpen(ctx, true, cond)
  end
  if r.ImGui_TreeNode(ctx, 'Developer') then
    for i, vend in ipairs(DEV_KEYS) do
      if developer_has_visible_fx(vend) then
        r.ImGui_PushID(ctx, 'vend_' .. tostring(i))
        local sel = (nav.root == 'developer' and nav.vendor == vend)
        if sel and state.navScrollPending and r.ImGui_SetScrollHereY then r.ImGui_SetScrollHereY(ctx, 0.5) end
        if r.ImGui_Selectable(ctx, vend, sel) then
          state.nav = { root = 'developer', vendor = vend }
          state.selIndex = 1
          if settings.rememberLastNav then persist_nav() end
        end
        r.ImGui_PopID(ctx)
      end
    end
    r.ImGui_TreePop(ctx)
  end
  if state.nav and state.nav.root == 'category' and r.ImGui_SetNextItemOpen then
    local cond = r.ImGui_Cond_Appearing and r.ImGui_Cond_Appearing() or nil
    r.ImGui_SetNextItemOpen(ctx, true, cond)
  end
  if r.ImGui_TreeNode(ctx, 'Category') then
    for i, cat in ipairs(CAT_KEYS) do
      if category_has_visible_fx(cat) then
        r.ImGui_PushID(ctx, 'cat_' .. tostring(i))
        local sel = (nav.root == 'category' and nav.category == cat)
        if sel and state.navScrollPending and r.ImGui_SetScrollHereY then r.ImGui_SetScrollHereY(ctx, 0.5) end
        if r.ImGui_Selectable(ctx, cat, sel) then
          state.nav = { root = 'category', category = cat }
          state.selIndex = 1
          if settings.rememberLastNav then persist_nav() end
        end
        r.ImGui_PopID(ctx)
      end
    end
    r.ImGui_TreePop(ctx)
  end
  if state.nav and state.nav.root == 'folders' and r.ImGui_SetNextItemOpen then
    local cond = r.ImGui_Cond_Appearing and r.ImGui_Cond_Appearing() or nil
    r.ImGui_SetNextItemOpen(ctx, true, cond)
  end
  if r.ImGui_TreeNode(ctx, 'Folders') then
    for i, fname in ipairs(FOLDERS) do
      if folder_has_visible_fx(fname) then
        r.ImGui_PushID(ctx, 'fld_' .. tostring(i))
        local sel = (nav.root == 'folders' and nav.folder == fname)
        if sel and state.navScrollPending and r.ImGui_SetScrollHereY then r.ImGui_SetScrollHereY(ctx, 0.5) end
        if r.ImGui_Selectable(ctx, fname, sel) then
          state.nav = { root = 'folders', folder = fname }
          state.selIndex = 1
          if settings.rememberLastNav then persist_nav() end
        end
        r.ImGui_PopID(ctx)
      end
    end
    r.ImGui_TreePop(ctx)
  end

  if state.navScrollPending then state.navScrollPending = false end


  r.ImGui_EndChild(ctx) 
  r.ImGui_EndChild(ctx) 
end

local function draw_top_header()
  local avail_w = select(1, r.ImGui_GetContentRegionAvail(ctx)) or 0
  r.ImGui_SetNextItemWidth(ctx, math.max(180, math.min(420, (avail_w or 600) * 0.5)))
  local changed, s
  if r.ImGui_InputTextWithHint then
    changed, s = r.ImGui_InputTextWithHint(ctx, '##search_global', 'Search', state.query)
  else
    changed, s = r.ImGui_InputText(ctx, '##search_global', state.query)
  end
  if changed then state.query = s end
  r.ImGui_SameLine(ctx)
  do
    local _, v = r.ImGui_Checkbox(ctx, 'All', settings.searchAll == true)
    if v ~= settings.searchAll then settings.searchAll = v; save_settings() end
  end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, 'Rescan') then state.needRescan = true end
  r.ImGui_SameLine(ctx)
  local src_tag = (DATA_SOURCE == 'cache') and ' (cache)' or ''
  r.ImGui_Text(ctx, string.format('%d%s', #(ALL_FX or {}), src_tag))
  r.ImGui_SameLine(ctx)
  do
    local cur_x = r.ImGui_GetCursorPosX(ctx)
    local avail = select(1, r.ImGui_GetContentRegionAvail(ctx)) or 0
    local gear_label = (MonoIcon and MonoIcon('⚙')) or '⚙'
    local tw = select(1, r.ImGui_CalcTextSize(ctx, gear_label)) or 12
    local btn_w = tw + 14
    r.ImGui_SetCursorPosX(ctx, cur_x + math.max(0, avail - btn_w))
    if r.ImGui_Button(ctx, gear_label .. '##settings_btn', btn_w, 0) then
      r.ImGui_OpenPopup(ctx, 'settings_popup')
    end
  end
  if r.ImGui_BeginPopup(ctx, 'settings_popup') then
    r.ImGui_Text(ctx, 'Settings')
    r.ImGui_Separator(ctx)
    do local _, v = r.ImGui_Checkbox(ctx, 'Open UI after add', state.openUI); state.openUI = v end
    do
      local _, v = r.ImGui_Checkbox(ctx, 'Single click to add', settings.singleClickAdd == true)
      if v ~= settings.singleClickAdd then settings.singleClickAdd = v; save_settings() end
    end
    do
      local _, v = r.ImGui_Checkbox(ctx, 'Clean name', settings.cleanName == true)
      if v ~= settings.cleanName then settings.cleanName = v; save_settings() end
    end
    do
      local _, v = r.ImGui_Checkbox(ctx, 'Remember last opened', settings.rememberLastNav == true)
      if v ~= settings.rememberLastNav then
        settings.rememberLastNav = v
        if v then persist_nav() else save_settings() end
      end
    end
    do
      local relaxed = (settings.doubleClickInterval or 0.6) >= 0.6
      local _, v = r.ImGui_Checkbox(ctx, 'Relaxed double-click timing', relaxed)
      if v ~= relaxed then
        settings.doubleClickInterval = v and 0.75 or 0.50
        save_settings()
      end
    end
    if r.ImGui_TreeNode(ctx, 'Filters') then
      local f = settings.filters
      local _, f1 = r.ImGui_Checkbox(ctx, 'VST3', f.VST3)
      local _, f2 = r.ImGui_Checkbox(ctx, 'VST2', f.VST)
      local _, f4 = r.ImGui_Checkbox(ctx, 'CLAP', f.CLAP)
      local _, f6 = r.ImGui_Checkbox(ctx, 'JS', f.JS)
      local _, f7 = r.ImGui_Checkbox(ctx, 'Other', f.Other)
      if f1 ~= f.VST3 or f2 ~= f.VST or f4 ~= f.CLAP or f6 ~= f.JS or f7 ~= f.Other then
        f.VST3, f.VST, f.CLAP, f.JS, f.Other = f1, f2, f4, f6, f7
        save_settings()
        VIS_CACHE.dirty = true
      end
      r.ImGui_TreePop(ctx)
    end
    r.ImGui_EndPopup(ctx)
  end
  r.ImGui_Separator(ctx)
end

local function draw_list(height_override)
  local avail_w = select(1, r.ImGui_GetContentRegionAvail(ctx))
  local avail_h = height_override or select(2, r.ImGui_GetContentRegionAvail(ctx))
  if (avail_h or 0) < 80 then avail_h = 80 end
  local child_flags = 0
  if type(r.ImGui_ChildFlags_Border) == 'function' then
    child_flags = r.ImGui_ChildFlags_Border()
  elseif type(r.ImGui_ChildFlags_Border) == 'number' then
    child_flags = r.ImGui_ChildFlags_Border
  end
  local pushed_vars = 0
  if r.ImGui_StyleVar_WindowPadding then
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), 4, 4)
    pushed_vars = pushed_vars + 1
  end
  r.ImGui_BeginChild(ctx, 'list', avail_w, avail_h, child_flags)
  local items = get_filtered()
  local tf_rowbg = (r.ImGui_TableFlags_RowBg and r.ImGui_TableFlags_RowBg()) or 0
  local tf_borders = (r.ImGui_TableFlags_BordersOuter and r.ImGui_TableFlags_BordersOuter()) or 0
  local tf_resizable = (r.ImGui_TableFlags_Resizable and r.ImGui_TableFlags_Resizable()) or 0
  local tf_sizing = (r.ImGui_TableFlags_SizingFixedFit and r.ImGui_TableFlags_SizingFixedFit()) or 0
  local tf_sortable = (r.ImGui_TableFlags_Sortable and r.ImGui_TableFlags_Sortable()) or 0
  local table_flags = tf_rowbg | tf_borders | tf_resizable | tf_sizing | tf_sortable
  if r.ImGui_BeginTable(ctx, 'fx_table', 3, table_flags, avail_w, avail_h - 6) then
    local ch_flags = (r.ImGui_TableColumnFlags_NoHide and r.ImGui_TableColumnFlags_NoHide()) or 0
    local ch_default_sort = (r.ImGui_TableColumnFlags_DefaultSort and r.ImGui_TableColumnFlags_DefaultSort()) or 0
    local col_fixed = (r.ImGui_TableColumnFlags_WidthFixed and r.ImGui_TableColumnFlags_WidthFixed()) or 0
    local col_stretch = (r.ImGui_TableColumnFlags_WidthStretch and r.ImGui_TableColumnFlags_WidthStretch()) or 0
    local star_w = 34.0
    local type_w = 110.0
    r.ImGui_TableSetupColumn(ctx, '★', ch_flags | col_fixed, star_w, 0)
    r.ImGui_TableSetupColumn(ctx, 'Name', ch_flags | ch_default_sort | col_stretch, 1.0, 1)
    r.ImGui_TableSetupColumn(ctx, 'Type', ch_flags | col_fixed, type_w, 2)
    do
      local hdr_flags = (r.ImGui_TableRowFlags_Headers and r.ImGui_TableRowFlags_Headers()) or 0
      r.ImGui_TableNextRow(ctx, hdr_flags)
      local active_col = tonumber(settings.sort and settings.sort.col) or 1
      local dir = (settings.sort and settings.sort.dir) or 'asc'
      local arrow = (dir == 'asc') and ' ▲' or ' ▼'

      r.ImGui_TableSetColumnIndex(ctx, 0)
      local lab0 = (active_col == 0) and ('★' .. arrow) or '★'
      if r.ImGui_Selectable(ctx, lab0, active_col == 0, 0) then
        if active_col == 0 then dir = (dir == 'asc') and 'desc' or 'asc' else dir = 'asc' end
        settings.sort = { col = 0, dir = dir }
        save_settings()
      end
      r.ImGui_TableSetColumnIndex(ctx, 1)
      local lab1 = (active_col == 1) and ('Name' .. arrow) or 'Name'
      if r.ImGui_Selectable(ctx, lab1, active_col == 1, 0) then
        if active_col == 1 then dir = (dir == 'asc') and 'desc' or 'asc' else dir = 'asc' end
        settings.sort = { col = 1, dir = dir }
        save_settings()
      end
      r.ImGui_TableSetColumnIndex(ctx, 2)
      local lab2 = (active_col == 2) and ('Type' .. arrow) or 'Type'
      if r.ImGui_Selectable(ctx, lab2, active_col == 2, 0) then
        if active_col == 2 then dir = (dir == 'asc') and 'desc' or 'asc' else dir = 'asc' end
        settings.sort = { col = 2, dir = dir }
        save_settings()
      end

      local sort_col = (settings.sort and settings.sort.col) or 1
      local sort_dir = (settings.sort and settings.sort.dir) or 'asc'

      local function cmp(a, b)
        local function key_name(x)
          if settings and settings.cleanName then
            return safe_lower(format_fx_label(x))
          end
          return safe_lower((x and (x.addname or x.name)) or '')
        end
        local function key_type(x)
          local t = x and x.type or ''
          if t == nil or t == '' then return 'Other' else return t end
        end
        local function key_star(x)
          return (x and is_favorite(x.addname)) and 1 or 0
        end
        if sort_col == 0 then -- star
          local a1, b1 = key_star(a), key_star(b)
          if a1 ~= b1 then
            if sort_dir == 'asc' then return a1 < b1 else return a1 > b1 end
          end
          local a2, b2 = key_name(a), key_name(b)
          if a2 ~= b2 then
            if sort_dir == 'asc' then return a2 < b2 else return a2 > b2 end
          end
          local a3, b3 = key_type(a), key_type(b)
          if a3 ~= b3 then
            if sort_dir == 'asc' then return a3 < b3 else return a3 > b3 end
          end
          return false
        elseif sort_col == 2 then -- type
          local a1, b1 = key_type(a), key_type(b)
          if a1 ~= b1 then
            if sort_dir == 'asc' then return a1 < b1 else return a1 > b1 end
          end
          local a2, b2 = key_name(a), key_name(b)
          if a2 ~= b2 then
            if sort_dir == 'asc' then return a2 < b2 else return a2 > b2 end
          end
          local a3, b3 = key_star(a), key_star(b)
          if a3 ~= b3 then
            if sort_dir == 'asc' then return a3 < b3 else return a3 > b3 end
          end
          return false
        else -- name
          local a1, b1 = key_name(a), key_name(b)
          if a1 ~= b1 then
            if sort_dir == 'asc' then return a1 < b1 else return a1 > b1 end
          end
          local a2, b2 = key_type(a), key_type(b)
          if a2 ~= b2 then
            if sort_dir == 'asc' then return a2 < b2 else return a2 > b2 end
          end
          local a3, b3 = key_star(a), key_star(b)
          if a3 ~= b3 then
            if sort_dir == 'asc' then return a3 < b3 else return a3 > b3 end
          end
          return false
        end
      end
      local sort_col = (settings.sort and settings.sort.col) or 1
      local sort_dir = (settings.sort and settings.sort.dir) or 'asc'
      local cache_key = table.concat({
        sort_col, sort_dir, settings.cleanName and 1 or 0, settings.searchAll and 1 or 0,
        state.query or '', state.nav.root or '', state.nav.mode or '', state.nav.vendor or '', state.nav.category or '', state.nav.folder or '',
        FAV_GEN or 0, DATA_GEN or 0, settings.filters.VST3 and 1 or 0, settings.filters.VST and 1 or 0, settings.filters.CLAP and 1 or 0,
        settings.filters.JS and 1 or 0, settings.filters.Other and 1 or 0
      }, '|')
      if SORT_CACHE.key ~= cache_key then
        table.sort(items, cmp)
        SORT_CACHE.key = cache_key
        local copy = {}
        for i=1,#items do copy[i] = items[i] end
        SORT_CACHE.items = copy
      else
        items = SORT_CACHE.items or items
      end
    end

    for i, e in ipairs(items) do
      r.ImGui_TableNextRow(ctx)
      local isSel = (i == state.selIndex)
      r.ImGui_PushID(ctx, 'row_' .. tostring(i))

      r.ImGui_TableSetColumnIndex(ctx, 0)
      local isFav = is_favorite(e.addname)
      local star_label = (isFav and '★' or '☆') .. '##star'
      if r.ImGui_Selectable(ctx, star_label, false, 0) then
      end
      if r.ImGui_IsItemClicked(ctx, 0) then
        toggle_favorite(e.addname)
      end

      r.ImGui_TableSetColumnIndex(ctx, 1)
  local name_label = format_fx_label(e) .. '##name'
      local span_all = r.ImGui_SelectableFlags_SpanAllColumns and r.ImGui_SelectableFlags_SpanAllColumns() or 0
      if r.ImGui_Selectable(ctx, name_label, isSel, span_all) then
        state.selIndex = i
        local now = (r.time_precise and r.time_precise()) or os.clock()
        local id = e.addname or e.name
        if settings.singleClickAdd then
          maybe_add_fx_ui(e, 'single')
        else
          if __last_click.id == id and (now - (__last_click.t or 0)) <= (settings.doubleClickInterval or 0.6) then
            maybe_add_fx_ui(e, 'double')
            __last_click.id, __last_click.t = nil, 0
          else
            __last_click.id, __last_click.t = id, now
          end
        end
      end
      if r.ImGui_IsItemClicked(ctx, 1) then
        r.ImGui_OpenPopup(ctx, 'fx_row_ctx_' .. tostring(i))
      end

      r.ImGui_TableSetColumnIndex(ctx, 2)
      r.ImGui_Text(ctx, e.type ~= '' and e.type or 'Other')

      if r.ImGui_BeginPopup(ctx, 'fx_row_ctx_' .. tostring(i)) then
        if r.ImGui_MenuItem(ctx, isFav and 'Unfavorite' or 'Favorite') then toggle_favorite(e.addname) end
        if r.ImGui_MenuItem(ctx, 'Add to selected takes') then
          local ok = add_fx_to_selected_takes(e.addname, state.openUI)
          if ok then push_recent(e.addname) end
        end
        r.ImGui_EndPopup(ctx)
      end

      r.ImGui_PopID(ctx)
    end
    do
      local row_h = (r.ImGui_GetTextLineHeightWithSpacing and r.ImGui_GetTextLineHeightWithSpacing(ctx)) or (r.ImGui_GetTextLineHeight and r.ImGui_GetTextLineHeight(ctx)) or 16
      local rows_fit = math.floor(math.max(0, (avail_h - 6) / row_h))
      local extra = rows_fit - (#items + 1)
      if extra > 0 then
        for _=1, extra do
          r.ImGui_TableNextRow(ctx)
          r.ImGui_TableSetColumnIndex(ctx, 1)
          r.ImGui_Text(ctx, ' ')
        end
      end
    end
    r.ImGui_EndTable(ctx)
  else
    for i, e in ipairs(items) do
      r.ImGui_PushID(ctx, 'row_nt_' .. tostring(i))
      local isFav = is_favorite(e.addname)
      local star = isFav and '★' or '☆'
  local label = string.format('%s  %s  [%s]##row', star, format_fx_label(e), e.type ~= '' and e.type or 'Other')
      if r.ImGui_Selectable(ctx, label, i == state.selIndex) then
        state.selIndex = i
        local now = (r.time_precise and r.time_precise()) or os.clock()
        local id = e.addname or e.name
        if settings.singleClickAdd then
          maybe_add_fx_ui(e, 'single')
        else
          if __last_click.id == id and (now - (__last_click.t or 0)) <= (settings.doubleClickInterval or 0.6) then
            maybe_add_fx_ui(e, 'double')
            __last_click.id, __last_click.t = nil, 0
          else
            __last_click.id, __last_click.t = id, now
          end
        end
      end
      if r.ImGui_IsItemClicked(ctx, 0) then
        local mx, _ = r.ImGui_GetMousePos(ctx)
        local ix, _ = r.ImGui_GetItemRectMin(ctx)
        if mx and ix and (mx - ix) <= 20 then
          toggle_favorite(e.addname)
        end
      end
      r.ImGui_PopID(ctx)
    end
  end
  r.ImGui_EndChild(ctx)
  if pushed_vars > 0 then r.ImGui_PopStyleVar(ctx, pushed_vars) end
end

local function push_audio_style()
  local col_count, var_count = 0, 0
  local function PSC(idx, col) r.ImGui_PushStyleColor(ctx, idx, col); col_count = col_count + 1 end
  local function PSV(idx, v) r.ImGui_PushStyleVar(ctx, idx, v); var_count = var_count + 1 end
  if r.ImGui_Col_WindowBg then PSC(r.ImGui_Col_WindowBg(), 0x1E1E1EFF) end
  if r.ImGui_Col_TitleBg then PSC(r.ImGui_Col_TitleBg(), 0x000000FF) end
  if r.ImGui_Col_TitleBgActive then PSC(r.ImGui_Col_TitleBgActive(), 0x000000FF) end
  if r.ImGui_Col_TitleBgCollapsed then PSC(r.ImGui_Col_TitleBgCollapsed(), 0x000000FF) end
  if r.ImGui_Col_Tab then PSC(r.ImGui_Col_Tab(), 0x000000FF) end
  if r.ImGui_Col_TabHovered then PSC(r.ImGui_Col_TabHovered(), 0x000000FF) end
  if r.ImGui_Col_TabActive then PSC(r.ImGui_Col_TabActive(), 0x000000FF) end
  if r.ImGui_Col_TabUnfocused then PSC(r.ImGui_Col_TabUnfocused(), 0x000000FF) end
  if r.ImGui_Col_TabUnfocusedActive then PSC(r.ImGui_Col_TabUnfocusedActive(), 0x000000FF) end
  if r.ImGui_Col_FrameBg then PSC(r.ImGui_Col_FrameBg(), 0x303030FF) end
  if r.ImGui_Col_FrameBgHovered then PSC(r.ImGui_Col_FrameBgHovered(), 0x3A3A3AFF) end
  if r.ImGui_Col_FrameBgActive then PSC(r.ImGui_Col_FrameBgActive(), 0x272727FF) end
  if r.ImGui_Col_Button then PSC(r.ImGui_Col_Button(), 0x2A2A2AFF) end
  if r.ImGui_Col_ButtonHovered then PSC(r.ImGui_Col_ButtonHovered(), 0x343434FF) end
  if r.ImGui_Col_ButtonActive then PSC(r.ImGui_Col_ButtonActive(), 0x1E1E1EFF) end
  if r.ImGui_Col_CheckMark then PSC(r.ImGui_Col_CheckMark(), 0xFFFFFFFF) end
  if r.ImGui_Col_SliderGrab then PSC(r.ImGui_Col_SliderGrab(), 0xA0A0A0FF) end
  if r.ImGui_Col_SliderGrabActive then PSC(r.ImGui_Col_SliderGrabActive(), 0xFFFFFFFF) end
  if r.ImGui_StyleVar_FrameRounding then PSV(r.ImGui_StyleVar_FrameRounding(), 4.0) end
  return col_count, var_count
end

local function pop_audio_style(col_count, var_count)
  if var_count and var_count > 0 then r.ImGui_PopStyleVar(ctx, var_count) end
  if col_count and col_count > 0 then r.ImGui_PopStyleColor(ctx, col_count) end
end

local function main()
  local cmd = r.GetExtState('TK_RAW_FX_BROWSER', 'command') or ''
  if cmd == 'close' or cmd == 'toggle' then
    r.SetExtState('TK_RAW_FX_BROWSER', 'command', '', false)
    r.SetExtState('TK_RAW_FX_BROWSER', 'running', '', false)
    if type(r.ImGui_DestroyContext) == 'function' then r.ImGui_DestroyContext(ctx) end
    return
  end
  r.ImGui_SetNextWindowSize(ctx, 760, 520, r.ImGui_Cond_FirstUseEver())
  local right_min = 220
  local splitter_w = 3
  local pad = 16
  local min_w = 150 + splitter_w + right_min + pad
  r.ImGui_SetNextWindowSizeConstraints(ctx, min_w, 320, 100000, 100000)
  local wflags = 0
  if r.ImGui_WindowFlags_NoScrollbar then
    wflags = (type(r.ImGui_WindowFlags_NoScrollbar) == 'function' and r.ImGui_WindowFlags_NoScrollbar() or r.ImGui_WindowFlags_NoScrollbar)
  end
  if r.ImGui_WindowFlags_NoScrollWithMouse then
    local f2 = (type(r.ImGui_WindowFlags_NoScrollWithMouse) == 'function' and r.ImGui_WindowFlags_NoScrollWithMouse() or r.ImGui_WindowFlags_NoScrollWithMouse)
    wflags = (wflags or 0) | f2
  end
  local style_cols, style_vars = push_audio_style()
  local win_title = 'TK RAW fx browser'
  local visible, open_ret = r.ImGui_Begin(ctx, win_title .. '##main', state.win_open, wflags)
  if visible then
    if (not ALL_FX or #ALL_FX == 0) and file_exists(CACHE_FILE) then
      local ok = load_cache()
      if ok and ALL_FX and #ALL_FX > 0 then
        rebuild_indexes()
        rebuild_from_cat()
        DATA_SOURCE = 'cache'
        VIS_CACHE.dirty = true
        DATA_GEN = (DATA_GEN or 0) + 1
      end
    end
    if state.needRescan then
      local fresh, err = load_all_fx()
      if fresh and #fresh > 0 then
        ALL_FX = fresh
        rebuild_indexes()
        rebuild_from_cat()
        save_cache()
        DATA_SOURCE = 'fresh'
        VIS_CACHE.dirty = true
        DATA_GEN = (DATA_GEN or 0) + 1
      else
        r.ShowMessageBox(err or 'Rescan failed', 'Parser', 0)
      end
      state.needRescan = false
    end
  draw_top_header()
  local avail_w, avail_h = r.ImGui_GetContentRegionAvail(ctx)
    local max_left = math.max(150, (avail_w or 700) - right_min - splitter_w)
    local left_w = math.max(150, math.min(settings.sidebar_w or 260, max_left))
    if (avail_w - left_w - splitter_w) < right_min then
      left_w = math.max(150, (avail_w or 700) - right_min - splitter_w)
    end
  settings.sidebar_w = left_w
  draw_left_panel(avail_h)
  if r.ImGui_SameLine then r.ImGui_SameLine(ctx, 0, 0) end
    r.ImGui_InvisibleButton(ctx, '##split', splitter_w, avail_h)
    if r.ImGui_IsItemActive(ctx) and r.ImGui_IsMouseDragging(ctx, 0) then
      local dx = r.ImGui_GetMouseDragDelta(ctx, 0)
      if dx then
        local upper = math.max(120, (avail_w or 700) - right_min - splitter_w)
        settings.sidebar_w = math.max(120, math.min((settings.sidebar_w or 260) + dx, upper))
        r.ImGui_ResetMouseDragDelta(ctx, 0)
        save_settings()
      end
    end
    do
      local dl = r.ImGui_GetWindowDrawList(ctx)
      local minx, miny = r.ImGui_GetItemRectMin(ctx)
      local _, maxy = r.ImGui_GetItemRectMax(ctx)
      if dl and minx and miny and maxy then
        local x = minx + (splitter_w * 0.5)
        r.ImGui_DrawList_AddLine(dl, x, miny + 1, x, maxy - 1, 0x3A3A3AFF, 1.5)
      end
    end
    r.ImGui_SameLine(ctx)

  local footer_h = 2
    draw_list(math.max(80, (avail_h or 200) - footer_h))

    r.ImGui_Separator(ctx)
    if r.ImGui_Button(ctx, 'Close') then
      state.win_open = false
    end

    local key_up = r.ImGui_Key_UpArrow and r.ImGui_Key_UpArrow() or 0
    local key_down = r.ImGui_Key_DownArrow and r.ImGui_Key_DownArrow() or 0
    local key_enter = r.ImGui_Key_Enter and r.ImGui_Key_Enter() or 0
    local want_kbd = r.ImGui_IsWindowFocused(ctx)
    if want_kbd then
      if key_up ~= 0 and r.ImGui_IsKeyPressed(ctx, key_up, false) then state.selIndex = math.max(1, (state.selIndex or 1) - 1) end
      if key_down ~= 0 and r.ImGui_IsKeyPressed(ctx, key_down, false) then
        local cnt = #(get_filtered())
        state.selIndex = math.min(cnt, (state.selIndex or 1) + 1)
      end
      if key_enter ~= 0 and r.ImGui_IsKeyPressed(ctx, key_enter, false) then
        local items = get_filtered()
        local e = items[state.selIndex or 1]
        if e then
          local ok = add_fx_to_selected_takes(e.addname, state.openUI)
          if ok then push_recent(e.addname) end
        end
      end
    end
    r.ImGui_End(ctx)
  end
  pop_audio_style(style_cols, style_vars)
  if type(open_ret) == 'boolean' then state.win_open = open_ret end
  if state.win_open ~= false then
    r.defer(main)
  else
    if type(r.ImGui_DestroyContext) == 'function' then r.ImGui_DestroyContext(ctx) end
    r.SetExtState('TK_RAW_FX_BROWSER', 'running', '', false)
  end
end

main()
