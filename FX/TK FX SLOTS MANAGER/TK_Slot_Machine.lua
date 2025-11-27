-- @version 0.3.7
-- @author: TouristKiller (with assistance from Robert ;o) )
-- @changelog:
--[[     

== THNX TO MASTER SEXAN FOR HIS FX PARSER ==

]]--        
--------------------------------------------------------------------------


local r = reaper
local SCRIPT_NAME = 'TK Slot Machine'
local SCRIPT_VERSION = '0.3.7'

local script_path = debug.getinfo(1, "S").source:match("@?(.*[/\\])")
local os_separator = package.config:sub(1, 1)

function ThirdPartyDeps()
end

if ThirdPartyDeps() then return end

local fx_browser = r.GetResourcePath() .. "/Scripts/Sexan_Scripts/FX/Sexan_FX_Browser_ParserV7.lua"
if r.file_exists(fx_browser) then
    dofile(fx_browser)
else
    error("Sexan FX Browser Parser not found. Please run TK FX Browser first to install dependencies.")
end

local FX_LIST_TEST, CAT_TEST, FX_DEV_LIST_FILE
local function init_fx_parser()
    FX_LIST_TEST, CAT_TEST, FX_DEV_LIST_FILE = ReadFXFile()
    if not FX_LIST_TEST or not CAT_TEST or not FX_DEV_LIST_FILE then
        FX_LIST_TEST, CAT_TEST, FX_DEV_LIST_FILE = MakeFXFiles()
    end
end

init_fx_parser()

local ctx = nil
local DND_FX_PAYLOAD = 'TK_FX_ROW_SINGLE'

local styleStackDepth = {colors = 0, vars = 0}
local windowStack = {depth = 0} -- Track ImGui window Begin/End balance

local function debug_stack_state(location)
  if styleStackDepth.colors > 0 or styleStackDepth.vars > 0 then
    end
end

local function is_context_valid(c)
  if not c then return false end
  local ok = pcall(function()
    if r.ImGui_ValidatePtr then
      return r.ImGui_ValidatePtr(c, 'ImGui_Context*')
    else
      if r.ImGui_GetVersion then r.ImGui_GetVersion() end
      return true
    end
  end)
  return ok
end

local function emergency_reset_stacks()
  -- Emergency reset van alle tracking variabelen
  styleStackDepth.colors = 0
  styleStackDepth.vars = 0
  windowStack.depth = 0
  r.ShowConsoleMsg("Emergency reset: all ImGui stacks cleared\n")
end

local function safe_imgui_call(func, ...)
  if not ctx or not is_context_valid(ctx) then
    return false
  end
  local success, result = pcall(func, ctx, ...)
  if not success then
    return false
  end
  return true, result
end

local function cleanup_resources()
  if not ctx then return end
  if styleStackDepth.colors > 0 and r.ImGui_PopStyleColor then
    pcall(r.ImGui_PopStyleColor, ctx, styleStackDepth.colors)
    styleStackDepth.colors = 0
  end
  if styleStackDepth.vars > 0 and r.ImGui_PopStyleVar then
    pcall(r.ImGui_PopStyleVar, ctx, styleStackDepth.vars)
    styleStackDepth.vars = 0
  end
  if state and state.slotLogoTex and r.ImGui_DestroyImage then
    pcall(function() r.ImGui_DestroyImage(state.slotLogoTex) end)
    state.slotLogoTex = nil
  end
end

local function init_context()
  ctx = r.ImGui_CreateContext(SCRIPT_NAME)
  if not ctx then
    r.ShowMessageBox('Failed to create ImGui context. Check ReaImGui installation.', 'Error', 0)
    return false
  end
  
  styleStackDepth.colors = 0
  styleStackDepth.vars = 0
  windowStack.depth = 0
  
  return true
end

if not init_context() then
  return 
end

local state = {
  winW = 340,
  winH = 420,
  
  -- UI preferences
  tooltips = true,
  showScreenshot = true,
  showRMSButtons = true,
  showTrackList = true,          
  showTrackNavButtons = true,   
  showTopPanelToggleBar = true,  
  nameNoPrefix = false,
  nameHideDeveloper = false,
  hideWetControl = false,        
  
  -- Header states (collapsible sections)
  trackHeaderOpen = true,
  replHeaderOpen = true,
  actionHeaderOpen = true,
  sourceHeaderOpen = true,
  fxChainHeaderOpen = true,
  trackVersionHeaderOpen = false,
  -- Panel visibility (new)
  showPanelReplacement = true,
  showPanelSource = true,
  showPanelFXChain = true,
  showPanelTrackVersion = true,
  hdrInitApplied = false,
  
  -- Branding
  slotLogoTex = nil,
  
  -- Operation settings
  scopeSelectedOnly = false,
  insertOverride = true,
  insertPos = 'in_place',
  insertIndex = 0,
  actionType = 'replace_all',
  useDummyReplace = false,
  
  -- Replacement settings
  replaceWith = '',
  replaceDisplay = '',
  selectedSourceFXName = nil,
  lastTrackGUID = nil,
  selectedSourceFXIndex = nil,
  
  -- Placeholder settings
  deleteInsertPlaceholder = false,
  placeholderCustomName = '',
  placeholderVariantName = 'Blank',
  slotUsePlaceholder = false,
  slotMatchSourceOnly = false,
  
  -- A/B testing
  abSlotIndex = nil,
  abOrigGUID = nil,
  abReplGUID = nil,
  abActiveIsRepl = false,
  
  -- UI states
  showSettings = false,
  showSettingsPending = false,
  showHelp = false,
  showPicker = false,
  
  styleRounding = 4.0,
  styleButtonRounding = 4.0,
  styleWindowRounding = 8.0,
  styleFrameRounding = 4.0,
  styleGrabRounding = 4.0,
  styleTabRounding = 4.0,
  
  styleButtonColorR = 0.26,
  styleButtonColorG = 0.59,
  styleButtonColorB = 0.98,
  styleButtonHoveredR = 0.36,
  styleButtonHoveredG = 0.69,
  styleButtonHoveredB = 1.0,
  styleButtonActiveR = 0.16,
  styleButtonActiveG = 0.49,
  styleButtonActiveB = 0.88,
  
  styleWindowBgR = 0.14,
  styleWindowBgG = 0.14,
  styleWindowBgB = 0.14,
  styleWindowBgA = 1.0,
  
  styleFrameBgR = 0.16,
  styleFrameBgG = 0.29,
  styleFrameBgB = 0.48,
  styleFrameBgA = 0.54,
  styleFrameBgHoveredR = 0.26,
  styleFrameBgHoveredG = 0.59,
  styleFrameBgHoveredB = 0.98,
  styleFrameBgHoveredA = 0.40,
  styleFrameBgActiveR = 0.26,
  styleFrameBgActiveG = 0.59,
  styleFrameBgActiveB = 0.98,
  styleFrameBgActiveA = 0.67,
  
  -- Plugin picker
  pickerItems = nil,
  pickerErr = nil,
  pickerFilter = '',
  pickerChosenAdd = nil,
  pickerLoadedFromCache = false,
  pickerTriedCache = false,
  pickerType = 'All types',
  
  -- Screenshots
  screenshotTex = nil,
  screenshotKey = nil,
  screenshotFound = false,
  
  -- Favorites and variants
  favs = {},
  tkBlankVariants = nil,
  
  -- FX Chain management
  fxChains = nil,
  fxChainsFromCache = false,
  fxChainFilter = '',
  selectedFxChain = nil,
  fxChainLoadToCurrent = true,
  fxChainLoadToSelected = false,
  fxChainLoadToAll = false,
  fxChainListHeight = 140,
  
  trackNavInput = '',
  
  -- Messages and feedback
  pendingMessage = '',
  pendingError = '',
  
  -- Deletion management
  _pendingDelGUID = nil,
  _pendingDelTrack = nil,
  _pendingDelArmed = false,
  trackVersions = {},
  trackVersionsCurrentIndex = {},
  _versionsLoaded = false,
  _tvSelected = nil,
  autoApplySnapshots = false,
}

-- Constants and configuration
local FX_END = -1
local EXT_NS = 'TK_FX_SINGLE'
local FAVS_NS = 'TK_FX_SLOTS'

-- UI Constants
local UI = {
  FOOTER_HEIGHT = 30,
  HEADER_BUTTON_SIZE = 18,
  SMALL_BUTTON_HEIGHT = 20,
  DEFAULT_SPACING = 4,
  WINDOW_PADDING = 8,
  MIN_WINDOW_WIDTH = 300,
  MIN_WINDOW_HEIGHT = 220,
  MAX_WINDOW_WIDTH = 2000,
  MAX_WINDOW_HEIGHT = 1400,
}

-- Color constants 
local COLORS = {
  BUTTON_NORMAL = {0.14, 0.14, 0.14, 1.00},
  BUTTON_HOVERED = {0.22, 0.22, 0.22, 1.00},
  BUTTON_ACTIVE = {0.10, 0.10, 0.10, 1.00},
  FRAME_BG = {0.12, 0.12, 0.12, 1.00},
  FRAME_BG_HOVERED = {0.18, 0.18, 0.18, 1.00},
  FRAME_BG_ACTIVE = {0.16, 0.16, 0.16, 1.00},
  POPUP_BG = {0.10, 0.10, 0.10, 0.98},
  CHECK_MARK = {0.85, 0.85, 0.85, 1.00},
  
  -- Status colors
  EXECUTE_BUTTON = {0.22, 0.40, 0.62, 1.0},
  EXECUTE_BUTTON_HOVERED = {0.28, 0.50, 0.75, 1.0},
  EXECUTE_BUTTON_ACTIVE = {0.18, 0.34, 0.54, 1.0},
  
  BYPASS_ACTIVE = {0.45, 0.35, 0.10, 1.0},
  RECORD_ACTIVE = {0.70, 0.20, 0.20, 1.0},
  MUTE_ACTIVE = {0.60, 0.45, 0.20, 1.0},
  SOLO_ACTIVE = {0.60, 0.60, 0.20, 1.0},
}
local function load_window_size()
  local w = tonumber(r.GetExtState(EXT_NS, 'WIN_W') or '') or state.winW
  local h = tonumber(r.GetExtState(EXT_NS, 'WIN_H') or '') or state.winH
  
  w = math.max(UI.MIN_WINDOW_WIDTH, math.min(UI.MAX_WINDOW_WIDTH, w))
  h = math.max(UI.MIN_WINDOW_HEIGHT, math.min(UI.MAX_WINDOW_HEIGHT, h))
  
  state.winW, state.winH = w, h
end

local function save_window_size(w, h)
  if not w or not h or w <= 0 or h <= 0 then return end
  
  w = math.max(UI.MIN_WINDOW_WIDTH, math.min(UI.MAX_WINDOW_WIDTH, math.floor(w)))
  h = math.max(UI.MIN_WINDOW_HEIGHT, math.min(UI.MAX_WINDOW_HEIGHT, math.floor(h)))
  
  r.SetExtState(EXT_NS, 'WIN_W', tostring(w), true)
  r.SetExtState(EXT_NS, 'WIN_H', tostring(h), true)
end

local function get_bool_setting(key, default)
  local val = r.GetExtState(EXT_NS, key)
  if val == '' or val == nil then return default end
  return val == '1'
end

local function set_bool_setting(key, value)
  r.SetExtState(EXT_NS, key, value and '1' or '0', true)
end

local function get_float_setting(key, default)
  local val = tonumber(r.GetExtState(EXT_NS, key) or '')
  if val == nil then return default end
  return val
end

local function set_float_setting(key, value)
  r.SetExtState(EXT_NS, key, tostring(value), true)
end

local function load_user_settings()
  state.tooltips = get_bool_setting('TOOLTIPS', state.tooltips)
  state.nameNoPrefix = get_bool_setting('NAME_NOPREFIX', state.nameNoPrefix)
  state.nameHideDeveloper = get_bool_setting('NAME_HIDEDEV', state.nameHideDeveloper)
  state.trackHeaderOpen = get_bool_setting('HDR_OPEN', state.trackHeaderOpen) and true or false
  state.replHeaderOpen = get_bool_setting('REPL_OPEN', state.replHeaderOpen)
  state.actionHeaderOpen = get_bool_setting('ACT_OPEN', state.actionHeaderOpen)
  state.sourceHeaderOpen = get_bool_setting('SRC_OPEN', state.sourceHeaderOpen)
  state.showScreenshot = get_bool_setting('IMG_SHOW', state.showScreenshot)
  state.fxChainHeaderOpen = get_bool_setting('FXC_OPEN', state.fxChainHeaderOpen)
  state.trackVersionHeaderOpen = get_bool_setting('TRV_OPEN', state.trackVersionHeaderOpen)
  state.showRMSButtons = get_bool_setting('SHOW_RMS', state.showRMSButtons)
  state.showTrackList = get_bool_setting('SHOW_TRK_LIST', state.showTrackList)
  state.showTopPanelToggleBar = get_bool_setting('SHOW_TOP_PANEL_TOGGLES', state.showTopPanelToggleBar == nil and true or state.showTopPanelToggleBar)
  state.showTrackNavButtons = get_bool_setting('SHOW_TRK_NAV', state.showTrackNavButtons)
  state.showPanelReplacement = get_bool_setting('PANEL_REPLACEMENT', state.showPanelReplacement == nil and true or state.showPanelReplacement)
  state.showPanelSource = get_bool_setting('PANEL_SOURCE', state.showPanelSource == nil and true or state.showPanelSource)
  state.showPanelFXChain = get_bool_setting('PANEL_FXCHAIN', state.showPanelFXChain == nil and true or state.showPanelFXChain)
  state.showPanelTrackVersion = get_bool_setting('PANEL_TRKVER', state.showPanelTrackVersion == nil and true or state.showPanelTrackVersion)
  state.fxChainListHeight    = get_float_setting('FXC_LIST_H', state.fxChainListHeight)
  -- Style numeric settings
  state.styleRounding         = get_float_setting('STYLE_ROUNDING', state.styleRounding)
  state.styleButtonRounding   = get_float_setting('STYLE_BTN_ROUNDING', state.styleButtonRounding)
  state.styleWindowRounding   = get_float_setting('STYLE_WIN_ROUNDING', state.styleWindowRounding)
  state.styleFrameRounding    = get_float_setting('STYLE_FRAME_ROUNDING', state.styleFrameRounding)
  state.styleGrabRounding     = get_float_setting('STYLE_GRAB_ROUNDING', state.styleGrabRounding)
  state.styleTabRounding      = get_float_setting('STYLE_TAB_ROUNDING', state.styleTabRounding)
  -- Button colors
  state.styleButtonColorR     = get_float_setting('STYLE_BTN_R', state.styleButtonColorR)
  state.styleButtonColorG     = get_float_setting('STYLE_BTN_G', state.styleButtonColorG)
  state.styleButtonColorB     = get_float_setting('STYLE_BTN_B', state.styleButtonColorB)
  state.styleButtonHoveredR   = get_float_setting('STYLE_BTN_HOV_R', state.styleButtonHoveredR)
  state.styleButtonHoveredG   = get_float_setting('STYLE_BTN_HOV_G', state.styleButtonHoveredG)
  state.styleButtonHoveredB   = get_float_setting('STYLE_BTN_HOV_B', state.styleButtonHoveredB)
  state.styleButtonActiveR    = get_float_setting('STYLE_BTN_ACT_R', state.styleButtonActiveR)
  state.styleButtonActiveG    = get_float_setting('STYLE_BTN_ACT_G', state.styleButtonActiveG)
  state.styleButtonActiveB    = get_float_setting('STYLE_BTN_ACT_B', state.styleButtonActiveB)
  -- Window background
  state.styleWindowBgR        = get_float_setting('STYLE_WIN_BG_R', state.styleWindowBgR)
  state.styleWindowBgG        = get_float_setting('STYLE_WIN_BG_G', state.styleWindowBgG)
  state.styleWindowBgB        = get_float_setting('STYLE_WIN_BG_B', state.styleWindowBgB)
  state.styleWindowBgA        = get_float_setting('STYLE_WIN_BG_A', state.styleWindowBgA)
  -- Frame background + hovered + active
  state.styleFrameBgR         = get_float_setting('STYLE_FRAME_BG_R', state.styleFrameBgR)
  state.styleFrameBgG         = get_float_setting('STYLE_FRAME_BG_G', state.styleFrameBgG)
  state.styleFrameBgB         = get_float_setting('STYLE_FRAME_BG_B', state.styleFrameBgB)
  state.styleFrameBgA         = get_float_setting('STYLE_FRAME_BG_A', state.styleFrameBgA)
  state.styleFrameBgHoveredR  = get_float_setting('STYLE_FRAME_HOV_R', state.styleFrameBgHoveredR)
  state.styleFrameBgHoveredG  = get_float_setting('STYLE_FRAME_HOV_G', state.styleFrameBgHoveredG)
  state.styleFrameBgHoveredB  = get_float_setting('STYLE_FRAME_HOV_B', state.styleFrameBgHoveredB)
  state.styleFrameBgHoveredA  = get_float_setting('STYLE_FRAME_HOV_A', state.styleFrameBgHoveredA)
  state.styleFrameBgActiveR = get_float_setting('STYLE_FRAME_ACT_R', state.styleFrameBgActiveR)
  state.styleFrameBgActiveG = get_float_setting('STYLE_FRAME_ACT_G', state.styleFrameBgActiveG)
  state.styleFrameBgActiveB = get_float_setting('STYLE_FRAME_ACT_B', state.styleFrameBgActiveB)
  state.styleFrameBgActiveA = get_float_setting('STYLE_FRAME_ACT_A', state.styleFrameBgActiveA)
  if get_bool_setting then
    state.hideWetControl = get_bool_setting('HIDE_WET', state.hideWetControl)
  end
end 

local load_track_versions

state.trackVersions = state.trackVersions
state.trackVersionsCurrentIndex = state.trackVersionsCurrentIndex

local function save_user_settings()
  set_bool_setting('TOOLTIPS', state.tooltips)
  set_bool_setting('NAME_NOPREFIX', state.nameNoPrefix)
  set_bool_setting('NAME_HIDEDEV', state.nameHideDeveloper)
  set_bool_setting('HDR_OPEN', state.trackHeaderOpen)
  set_bool_setting('REPL_OPEN', state.replHeaderOpen)
  set_bool_setting('ACT_OPEN', state.actionHeaderOpen)
  set_bool_setting('SRC_OPEN', state.sourceHeaderOpen)
  set_bool_setting('IMG_SHOW', state.showScreenshot)
  set_bool_setting('FXC_OPEN', state.fxChainHeaderOpen)
  set_bool_setting('TRV_OPEN', state.trackVersionHeaderOpen)
  set_bool_setting('SHOW_RMS', state.showRMSButtons)
  set_bool_setting('SHOW_TRK_LIST', state.showTrackList ~= false)
  set_bool_setting('SHOW_TOP_PANEL_TOGGLES', state.showTopPanelToggleBar ~= false)
  set_bool_setting('SHOW_TRK_NAV', state.showTrackNavButtons ~= false)
  set_bool_setting('HIDE_WET', state.hideWetControl == true)
  set_bool_setting('PANEL_REPLACEMENT', state.showPanelReplacement ~= false)
  set_bool_setting('PANEL_SOURCE', state.showPanelSource ~= false)
  set_bool_setting('PANEL_FXCHAIN', state.showPanelFXChain ~= false)
  set_bool_setting('PANEL_TRKVER', state.showPanelTrackVersion ~= false)
  set_float_setting('FXC_LIST_H', state.fxChainListHeight)
  
  set_float_setting('STYLE_ROUNDING', state.styleRounding)
  set_float_setting('STYLE_BTN_ROUNDING', state.styleButtonRounding)
  set_float_setting('STYLE_WIN_ROUNDING', state.styleWindowRounding)
  set_float_setting('STYLE_FRAME_ROUNDING', state.styleFrameRounding)
  set_float_setting('STYLE_GRAB_ROUNDING', state.styleGrabRounding)
  set_float_setting('STYLE_TAB_ROUNDING', state.styleTabRounding)
  
  set_float_setting('STYLE_BTN_R', state.styleButtonColorR)
  set_float_setting('STYLE_BTN_G', state.styleButtonColorG)
  set_float_setting('STYLE_BTN_B', state.styleButtonColorB)
  set_float_setting('STYLE_BTN_HOV_R', state.styleButtonHoveredR)
  set_float_setting('STYLE_BTN_HOV_G', state.styleButtonHoveredG)
  set_float_setting('STYLE_BTN_HOV_B', state.styleButtonHoveredB)
  set_float_setting('STYLE_BTN_ACT_R', state.styleButtonActiveR)
  set_float_setting('STYLE_BTN_ACT_G', state.styleButtonActiveG)
  set_float_setting('STYLE_BTN_ACT_B', state.styleButtonActiveB)
  
  set_float_setting('STYLE_WIN_BG_R', state.styleWindowBgR)
  set_float_setting('STYLE_WIN_BG_G', state.styleWindowBgG)
  set_float_setting('STYLE_WIN_BG_B', state.styleWindowBgB)
  set_float_setting('STYLE_WIN_BG_A', state.styleWindowBgA)
  
  set_float_setting('STYLE_FRAME_BG_R', state.styleFrameBgR)
  set_float_setting('STYLE_FRAME_BG_G', state.styleFrameBgG)
  set_float_setting('STYLE_FRAME_BG_B', state.styleFrameBgB)
  set_float_setting('STYLE_FRAME_BG_A', state.styleFrameBgA)
  set_float_setting('STYLE_FRAME_HOV_R', state.styleFrameBgHoveredR)
  set_float_setting('STYLE_FRAME_HOV_G', state.styleFrameBgHoveredG)
  set_float_setting('STYLE_FRAME_HOV_B', state.styleFrameBgHoveredB)
  set_float_setting('STYLE_FRAME_HOV_A', state.styleFrameBgHoveredA)
  set_float_setting('STYLE_FRAME_ACT_R', state.styleFrameBgActiveR)
  set_float_setting('STYLE_FRAME_ACT_G', state.styleFrameBgActiveG)
  set_float_setting('STYLE_FRAME_ACT_B', state.styleFrameBgActiveB)
  set_float_setting('STYLE_FRAME_ACT_A', state.styleFrameBgActiveA)
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
  r1, g1, b1, a1 = r1 or 0, g1 or 0, b1 or 0, a1 or 1
  
  r1 = math.max(0, math.min(1, r1))
  g1 = math.max(0, math.min(1, g1))
  b1 = math.max(0, math.min(1, b1))
  a1 = math.max(0, math.min(1, a1))
  
  if r.ImGui_ColorConvertDouble4ToU32 then
    return r.ImGui_ColorConvertDouble4ToU32(r1, g1, b1, a1)
  end
  
  local R = math.floor(r1 * 255 + 0.5)
  local G = math.floor(g1 * 255 + 0.5)
  local B = math.floor(b1 * 255 + 0.5)
  local A = math.floor(a1 * 255 + 0.5)
  return (A << 24) | (B << 16) | (G << 8) | (R & 0xFF)
end

local function rgb_to_int(r, g, b)
  return math.floor(b * 255) | (math.floor(g * 255) << 8) | (math.floor(r * 255) << 16)
end

local function rgba_to_int(r, g, b, a)
  return math.floor(r * 255) | (math.floor(g * 255) << 8) | (math.floor(b * 255) << 16) | (math.floor(a * 255) << 24)
end

local function int_to_rgb(color_int)
  local b = (color_int & 0xFF) / 255.0
  local g = ((color_int >> 8) & 0xFF) / 255.0  
  local r = ((color_int >> 16) & 0xFF) / 255.0
  return r, g, b
end

local function int_to_rgba(color_int)
  local r = (color_int & 0xFF) / 255.0
  local g = ((color_int >> 8) & 0xFF) / 255.0
  local b = ((color_int >> 16) & 0xFF) / 255.0
  local a = ((color_int >> 24) & 0xFF) / 255.0
  return r, g, b, a
end

local function rgba_hex_to_abgr(rgba_hex)
  local r = (rgba_hex >> 24) & 0xFF
  local g = (rgba_hex >> 16) & 0xFF
  local b = (rgba_hex >> 8) & 0xFF
  local a = rgba_hex & 0xFF
  return (a << 24) | (b << 16) | (g << 8) | r
end

local function abgr_to_rgba_hex(abgr)
  local a = (abgr >> 24) & 0xFF
  local b = (abgr >> 16) & 0xFF
  local g = (abgr >> 8) & 0xFF
  local r = abgr & 0xFF
  return (r << 24) | (g << 16) | (b << 8) | a
end

local function col_from_table(color_table)
  if not color_table or #color_table < 3 then return 0x000000FF end
  return col_u32(color_table[1], color_table[2], color_table[3], color_table[4])
end

local function lighten(rf, gf, bf, amt)
  amt = amt or 0.1
  local function clamp(x) 
    return math.max(0, math.min(1, x)) 
  end
  return clamp(rf + amt), clamp(gf + amt), clamp(bf + amt)
end

local function darken(rf, gf, bf, amt)
  return lighten(rf, gf, bf, -(amt or 0.1))
end

local function truncate_text_to_width(ctxRef, text, maxWidth)
  if not text or text == '' then return '' end
  if not ctxRef or not r.ImGui_CalcTextSize then return text end
  if not maxWidth or maxWidth <= 0 then return '' end
  local w = select(1, r.ImGui_CalcTextSize(ctxRef, text)) or 0
  if w <= maxWidth then return text end
  local ell = '…'
  local left, right = 1, #text
  local best = ell
  while left <= right do
    local mid = math.floor((left + right) / 2)
    local candidate = text:sub(1, mid) .. ell
    local cw = select(1, r.ImGui_CalcTextSize(ctxRef, candidate)) or 0
    if cw <= maxWidth then
      best = candidate
      left = mid + 1
    else
      right = mid - 1
    end
  end
  return best
end


local function is_modifier_down(mod_type)
  if not ctx then return false end
  
  if r.ImGui_GetKeyMods then
    local mods = r.ImGui_GetKeyMods(ctx)
    if mods then
      if mod_type == 'alt' and r.ImGui_Mod_Alt and (mods & r.ImGui_Mod_Alt()) ~= 0 then return true end
      if mod_type == 'shift' and r.ImGui_Mod_Shift and (mods & r.ImGui_Mod_Shift()) ~= 0 then return true end
      if mod_type == 'ctrl' and r.ImGui_Mod_Ctrl and (mods & r.ImGui_Mod_Ctrl()) ~= 0 then return true end
    end
  end
  
  if r.ImGui_GetIO then
    local io = r.ImGui_GetIO(ctx)
    if io then
      if mod_type == 'alt' and io.KeyAlt then return true end
      if mod_type == 'shift' and io.KeyShift then return true end
      if mod_type == 'ctrl' and io.KeyCtrl then return true end
    end
  end
  
  return false
end

local function is_alt_down() return is_modifier_down('alt') end
local function is_shift_down() return is_modifier_down('shift') end
local function is_ctrl_down() return is_modifier_down('ctrl') end

local function get_selected_track()
  return r.GetSelectedTrack(0, 0)
end

local function get_track_number(tr)
  if not tr or not r.ValidatePtr(tr, 'MediaTrack*') then return nil end
  local track_num = r.GetMediaTrackInfo_Value(tr, 'IP_TRACKNUMBER')
  return track_num and math.floor(track_num + 0.0001) or nil
end

local function go_to_track(track_number)
  local total_tracks = r.CountTracks(0)
  if track_number < 1 or track_number > total_tracks then
    return false, 'Track number out of range (1-' .. total_tracks .. ')'
  end
  local track = r.GetTrack(0, track_number - 1)
  if track then
    r.SetOnlyTrackSelected(track)
    r.Main_OnCommand(40913, 0)
    return true, 'Selected track ' .. track_number
  else
    return false, 'Failed to select track ' .. track_number
  end
end

local function navigate_to_previous_track()
  local current_track = get_selected_track()
            pcall(r.ImGui_DestroyContext, ctx)
  local current_number = get_track_number(current_track)
  if not current_number or current_number <= 1 then
    return false, 'Already at first track'
  end
  return go_to_track(current_number - 1)
end

local function navigate_to_next_track()
  local current_track = get_selected_track()
  if not current_track then return false, 'No track selected' end
  local current_number = get_track_number(current_track)
  local total_tracks = r.CountTracks(0)
  if not current_number or current_number >= total_tracks then
    return false, 'Already at last track'
  end
  return go_to_track(current_number + 1)
end

local function navigate_to_first_track()
  local total_tracks = r.CountTracks(0)
  if total_tracks == 0 then return false, 'No tracks in project' end
  return go_to_track(1)
end

local function navigate_to_last_track()
  local total_tracks = r.CountTracks(0)
  if total_tracks == 0 then return false, 'No tracks in project' end
  return go_to_track(total_tracks)
end

local function get_track_name(tr)
  if not tr or not r.ValidatePtr(tr, 'MediaTrack*') then return '' end
  local ok, name = r.GetTrackName(tr)
  return (ok and name) or ''
end

local function get_track_color_rgb(tr)
  if not tr or not r.ValidatePtr(tr, 'MediaTrack*') then return nil end
  local col = r.GetTrackColor(tr)
  if not col or col == 0 then return nil end
  
  local r8 = col & 255
  local g8 = (col >> 8) & 255
  local b8 = (col >> 16) & 255
  return (r8 or 0)/255, (g8 or 0)/255, (b8 or 0)/255
end

local function get_text_color_for_background(r, g, b)
  if not r or not g or not b then 
    return 1.0, 1.0, 1.0 
  end
  
  local luminance = 0.299 * r + 0.587 * g + 0.114 * b
  
  if luminance > 0.5 then
    return 0.0, 0.0, 0.0 
  else
    return 1.0, 1.0, 1.0 
  end
end

local function get_fx_name(tr, fxIdx)
  if not tr or not r.ValidatePtr(tr, 'MediaTrack*') or not fxIdx then return '' end
  if fxIdx < 0 or fxIdx >= (r.TrackFX_GetCount(tr) or 0) then return '' end
  
  local _, name = r.TrackFX_GetFXName(tr, fxIdx, '')
  return name or ''
end

local function get_fx_display_name(name)
  if not name or name == '' then return '' end
  
  local display = name
  
  if state.nameNoPrefix then
    display = display:gsub('^[^:]*:%s*', '')
  end
  
  if state.nameHideDeveloper then
    display = display:gsub('%s*%(.-%)%s*$', '')
  end
  
  return display
end

local function tracks_iter(selectedOnly)
  selectedOnly = selectedOnly or false
  local count = selectedOnly and r.CountSelectedTracks(0) or r.CountTracks(0)
  local i = 0
  
  return function()
    if i >= count then return nil end
    local tr = selectedOnly and r.GetSelectedTrack(0, i) or r.GetTrack(0, i)
    i = i + 1
    
    if tr and r.ValidatePtr(tr, 'MediaTrack*') then
      return tr, i-1
    else
      return tracks_iter(selectedOnly)()
    end
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
  if not ctx or not r.ImGui_PushStyleColor then return 0 end
  
  local pushed = 0
  local varPushed = 0
  
  local function push_color(color_id_func, red, green, blue, alpha)
    if color_id_func then
      local success = pcall(r.ImGui_PushStyleColor, ctx, color_id_func(), col_u32(red, green, blue, alpha or 1.0))
      if success then 
        pushed = pushed + 1
        styleStackDepth.colors = styleStackDepth.colors + 1
      end
    end
  end
  
  local function push_var(var_id_func, value)
    if var_id_func and r.ImGui_PushStyleVar and value then
      local var_id = nil
      local success_id = pcall(function() var_id = var_id_func() end)
      if success_id and var_id then
        local success = pcall(r.ImGui_PushStyleVar, ctx, var_id, value)
        if success then 
          varPushed = varPushed + 1
          styleStackDepth.vars = styleStackDepth.vars + 1
        end
      end
    end
  end
  
  push_var(r.ImGui_StyleVar_WindowRounding, state.styleWindowRounding)
  push_var(r.ImGui_StyleVar_FrameRounding, state.styleButtonRounding)
  push_var(r.ImGui_StyleVar_GrabRounding, state.styleGrabRounding)
  push_var(r.ImGui_StyleVar_TabRounding, state.styleTabRounding)
  
  push_color(r.ImGui_Col_Button, state.styleButtonColorR, state.styleButtonColorG, state.styleButtonColorB)
  push_color(r.ImGui_Col_ButtonHovered, state.styleButtonHoveredR, state.styleButtonHoveredG, state.styleButtonHoveredB)
  push_color(r.ImGui_Col_ButtonActive, state.styleButtonActiveR, state.styleButtonActiveG, state.styleButtonActiveB)
  push_color(r.ImGui_Col_FrameBg, state.styleFrameBgR, state.styleFrameBgG, state.styleFrameBgB, state.styleFrameBgA)
  push_color(r.ImGui_Col_FrameBgHovered, state.styleFrameBgHoveredR, state.styleFrameBgHoveredG, state.styleFrameBgHoveredB, state.styleFrameBgHoveredA)
  push_color(r.ImGui_Col_FrameBgActive, state.styleFrameBgActiveR, state.styleFrameBgActiveG, state.styleFrameBgActiveB, state.styleFrameBgActiveA)
  push_color(r.ImGui_Col_PopupBg, COLORS.POPUP_BG[1], COLORS.POPUP_BG[2], COLORS.POPUP_BG[3], COLORS.POPUP_BG[4] or 1.0)
  push_color(r.ImGui_Col_CheckMark, COLORS.CHECK_MARK[1], COLORS.CHECK_MARK[2], COLORS.CHECK_MARK[3], COLORS.CHECK_MARK[4] or 1.0)
  push_color(r.ImGui_Col_WindowBg, state.styleWindowBgR, state.styleWindowBgG, state.styleWindowBgB, state.styleWindowBgA)
  push_color(r.ImGui_Col_ChildBg, 0.0, 0.0, 0.0, 0.0)
  
  return {colors = pushed, vars = varPushed}
end

local function pop_app_style(styleData)
  if not ctx or not styleData then return end
  
  if styleData.colors and styleData.colors > 0 and r.ImGui_PopStyleColor then
    pcall(r.ImGui_PopStyleColor, ctx, styleData.colors)
    styleStackDepth.colors = math.max(0, styleStackDepth.colors - styleData.colors)
  end
  
  if styleData.vars and styleData.vars > 0 and r.ImGui_PopStyleVar then
    pcall(r.ImGui_PopStyleVar, ctx, styleData.vars)
    styleStackDepth.vars = math.max(0, styleStackDepth.vars - styleData.vars)
  end
end

local function favs_load()
  state.favs = {}
  local s = r.GetExtState(FAVS_NS, 'FAVS') or ''
  if s == '' then return end
  
  for line in string.gmatch(s, '([^\n]+)') do
    line = line:gsub('\r', '') 
    if line ~= '' then
      local add, disp = line:match('^(.-)\t(.*)$')
      add = add or line
      disp = disp ~= '' and disp or add
      
      if add ~= '' then 
        state.favs[#state.favs+1] = { 
          addname = add, 
          display = disp 
        } 
      end
    end
  end
end

local function favs_save()
  if not state.favs then return end
  
  local buf = {}
  for _, item in ipairs(state.favs) do
    if item.addname and item.addname ~= '' then
      local display = item.display or item.addname
      buf[#buf+1] = item.addname .. "\t" .. display
    end
  end
  
  r.SetExtState(FAVS_NS, 'FAVS', table.concat(buf, "\n"), true)
end

local function favs_remove(addname)
  if not addname or addname == '' or not state.favs then return end
  
  local removed = false
  for i = #state.favs, 1, -1 do
    if state.favs[i].addname == addname then 
      table.remove(state.favs, i)
      removed = true
    end
  end
  
  if removed then
    favs_save()
    state.pendingMessage = 'Removed from My Favorites'
  end
end

local function favs_add(addname, display)
  if not addname or addname == '' then return end
  if not state.favs then state.favs = {} end
  
  for _, item in ipairs(state.favs) do 
    if item.addname == addname then return end 
  end
  
  state.favs[#state.favs+1] = { 
    addname = addname, 
    display = display or addname 
  }
  
  favs_save()
  state.pendingMessage = 'Added to My Favorites'
end

local function favs_exists(addname)
  if not addname or addname == '' or not state.favs then return false end
  
  for _, item in ipairs(state.favs) do
    if item.addname == addname then return true end
  end
  return false
end

local function blanks_load()
  if not state.tkBlankVariants then state.tkBlankVariants = {} end
  
  local s = r.GetExtState(FAVS_NS, 'BLANKS') or ''
  local seen = {}
  
  state.tkBlankVariants = {{ name = 'Blank' }}
  seen['Blank'] = true
  
  if s ~= '' then
    for line in string.gmatch(s, '([^\n]+)') do
      local name = line:gsub('\r', ''):gsub('^%s+', ''):gsub('%s+$', '') -- Trim whitespace
      if name ~= '' and not seen[name] then
        state.tkBlankVariants[#state.tkBlankVariants+1] = { name = name }
        seen[name] = true
      end
    end
  end
end

local function blanks_save()
  if not state.tkBlankVariants then return end
  
  local buf = {}
  for _, item in ipairs(state.tkBlankVariants) do
    if item.name and item.name ~= '' and item.name ~= 'Blank' then 
      buf[#buf+1] = item.name 
    end
  end
  
  r.SetExtState(FAVS_NS, 'BLANKS', table.concat(buf, "\n"), true)
end

local function blanks_add(name)
  if not name or name == '' then return end
  
  name = name:gsub('^%s+', ''):gsub('%s+$', '') 
  if name == '' or name == 'Blank' then return end
  
  if not state.tkBlankVariants then blanks_load() end
  
  for _, variant in ipairs(state.tkBlankVariants) do 
    if variant.name == name then return end 
  end
  
  state.tkBlankVariants[#state.tkBlankVariants+1] = { name = name }
  blanks_save()
end

local function ensure_directory(path)
  if not path or path == '' then return false end
  
  if r.RecursiveCreateDirectory then
    return pcall(r.RecursiveCreateDirectory, path, 0)
  end
  return false
end

local function file_exists(path)
  if not path or path == '' then return false end
  
  local file = io.open(path, 'r')
  if file then
    file:close()
    return true
  end
  return false
end

local function write_file(path, content)
  if not path or path == '' then return false end
  
  local file, err = io.open(path, 'w')
  if not file then return false, err end
  
  file:write(content or '')
  file:close()
  return true
end

local function get_effects_directory()
  local sep = package.config:sub(1,1)
  return r.GetResourcePath() .. sep .. 'Effects' .. sep .. 'TK'
end

local function ensure_blank_jsfx()
  local effects_dir = get_effects_directory()
  if not ensure_directory(effects_dir) then 
    return false, 'Failed to create effects directory' 
  end
  
  local base_file = effects_dir .. package.config:sub(1,1) .. 'TK_Blank_NoOp_Base.jsfx'
  
  if file_exists(base_file) then return true end
  
  local base_content = [[desc: TK Blank NoOp (Base)
in_pin: Input
out_pin: Output

@init
// Base blank plugin - no processing

@slider
// No sliders needed

@block
// Process at block level if needed

@sample
// Pass-through audio (no processing)
]]

  local success, err = write_file(base_file, base_content)
  if not success then
    return false, 'Failed to create base JSFX file: ' .. (err or 'Unknown error')
  end
  
  return true
end

local function sanitize_jsfx_name(name)
  if not name or name == '' then return 'Blank' end
  
  name = tostring(name)
  name = name:gsub('[<>:"/\\|?*]', '_') 
  name = name:gsub('%.%.+', '.') 
  name = name:gsub('^%.', ''):gsub('%.$', '') 
  name = name:gsub('^%s+', ''):gsub('%s+$', '') 
  
  if name == '' then name = 'Blank' end
  return name
end

local function ensure_tk_blank_addname(customDesc)
  local success, err = ensure_blank_jsfx()
  if not success then return nil, err end
  
  local alias = sanitize_jsfx_name(customDesc or 'Blank')
  local effects_dir = get_effects_directory()
  local filename = 'TK_Blank_NoOp_' .. alias .. '.jsfx'
  local file_path = effects_dir .. package.config:sub(1,1) .. filename
  
  local content = string.format([[desc: %s
in_pin: Input
out_pin: Output

@init
// Custom blank plugin: %s

@slider
// No sliders

@block
// Block processing (pass-through)

@sample
// Sample processing (pass-through)
]], alias, alias)
  
  local write_success, write_err = write_file(file_path, content)
  if not write_success then
    return nil, 'Failed to create custom JSFX: ' .. (write_err or 'Unknown error')
  end
  
  local jsfx_name = filename:gsub('%.jsfx$', '')
  local addname = 'JS: TK/' .. jsfx_name
  
  return addname, nil
end

local function refresh_tk_blank_variants()
  blanks_load()
end

local function rename_fx_instance(track, fxIdx, name)
  if not track or not r.ValidatePtr(track, 'MediaTrack*') or not fxIdx or not name or name == '' then 
    return false 
  end
  
  local fx_count = r.TrackFX_GetCount(track)
  if fxIdx < 0 or fxIdx >= fx_count then return false end
  
  local success = false
  if r.TrackFX_SetNamedConfigParm then 
    success = pcall(r.TrackFX_SetNamedConfigParm, track, fxIdx, 'renamed', tostring(name))
  end
  
  if success then
    if r.TrackList_AdjustWindows then 
      pcall(r.TrackList_AdjustWindows, false) 
    end
    if r.UpdateArrange then 
      pcall(r.UpdateArrange) 
    end
  end
  
  return success
end

local function find_fx_index_by_guid(track, guid)
  if not track or not r.ValidatePtr(track, 'MediaTrack*') or not guid or guid == '' then 
    return nil 
  end
  
  local count = r.TrackFX_GetCount(track) or 0
  for i = 0, count - 1 do
    local fx_guid = r.TrackFX_GetFXGUID and r.TrackFX_GetFXGUID(track, i)
    if fx_guid == guid then return i end
  end
  return nil
end

local function get_fx_enabled(track, fxIdx)
  if not track or not r.ValidatePtr(track, 'MediaTrack*') or not fxIdx then return nil end
  
  if r.TrackFX_GetEnabled then
    local success, enabled = pcall(r.TrackFX_GetEnabled, track, fxIdx)
    if success then return enabled end
  end
  return nil
end

local function set_fx_enabled(track, fxIdx, enabled)
  if not track or not r.ValidatePtr(track, 'MediaTrack*') or not fxIdx then return false end
  
  if r.TrackFX_SetEnabled then
    return pcall(r.TrackFX_SetEnabled, track, fxIdx, enabled and true or false)
  end
  return false
end

local function get_fx_offline(track, fxIdx)
  if not track or not r.ValidatePtr(track, 'MediaTrack*') or not fxIdx then return nil end
  
  if r.TrackFX_GetOffline then
    local success, offline = pcall(r.TrackFX_GetOffline, track, fxIdx)
    if success then return offline end
  end
  return nil
end

local function set_fx_offline(track, fxIdx, offline)
  if not track or not r.ValidatePtr(track, 'MediaTrack*') or not fxIdx then return false end
  
  if r.TrackFX_SetOffline then
    return pcall(r.TrackFX_SetOffline, track, fxIdx, offline and true or false)
  end
  return false
end

local function move_selected_fx_up()
  local track = get_selected_track()
  if not track then return false, 'No track selected' end
  
  local srcIdx = tonumber(state.selectedSourceFXIndex)
  if not srcIdx then return false, 'No FX selected' end
  
  if srcIdx == 0 then return false, 'FX already at top' end
  
  r.Undo_BeginBlock('Move selected FX up')
  local success = pcall(function()
    r.TrackFX_CopyToTrack(track, srcIdx, track, srcIdx - 1, true)
  end)
  r.Undo_EndBlock('Move selected FX up', -1)
  
  if success then
    state.selectedSourceFXIndex = srcIdx - 1
    return true, 'FX moved up'
  else
    return false, 'Failed to move FX up'
  end
end

local function move_selected_fx_down()
  local track = get_selected_track()
  if not track then return false, 'No track selected' end
  
  local srcIdx = tonumber(state.selectedSourceFXIndex)
  if not srcIdx then return false, 'No FX selected' end
  
  local fxCount = r.TrackFX_GetCount(track)
  if srcIdx >= fxCount - 1 then return false, 'FX already at bottom' end
  
  r.Undo_BeginBlock('Move selected FX down')
  local success = pcall(function()
    r.TrackFX_CopyToTrack(track, srcIdx, track, srcIdx + 2, true)
  end)
  r.Undo_EndBlock('Move selected FX down', -1)
  
  if success then
    state.selectedSourceFXIndex = srcIdx + 1
    return true, 'FX moved down'
  else
    return false, 'Failed to move FX down'
  end
end

local function move_all_instances_up(sourceName)
  if not sourceName or sourceName == '' then return 0, 'No source FX selected' end
  
  local moved = 0
  r.Undo_BeginBlock('Move all instances up')
  
  for tr, _ in tracks_iter(false) do
    local fxCount = r.TrackFX_GetCount(tr)
    local toMove = {}
    
    for i = 1, fxCount - 1 do
      local name = get_fx_name(tr, i)
      if name == sourceName then
        table.insert(toMove, i)
      end
    end
    
    for _, idx in ipairs(toMove) do
      local success = pcall(function()
        r.TrackFX_CopyToTrack(tr, idx, tr, idx - 1, true)
      end)
      if success then moved = moved + 1 end
    end
  end
  
  r.Undo_EndBlock('Move all instances up', -1)
  return moved, string.format('%d instances moved up', moved)
end

local function move_all_instances_down(sourceName)
  if not sourceName or sourceName == '' then return 0, 'No source FX selected' end
  
  local moved = 0
  r.Undo_BeginBlock('Move all instances down')
  
  for tr, _ in tracks_iter(false) do
    local fxCount = r.TrackFX_GetCount(tr)
    local toMove = {}
    
    for i = 0, fxCount - 2 do
      local name = get_fx_name(tr, i)
      if name == sourceName then
        table.insert(toMove, i)
      end
    end
    
    table.sort(toMove, function(a, b) return a > b end)
    
    for _, idx in ipairs(toMove) do
      local success = pcall(function()
        r.TrackFX_CopyToTrack(tr, idx, tr, idx + 1, true)
      end)
      if success then moved = moved + 1 end
    end
  end
  
  r.Undo_EndBlock('Move all instances down', -1)
  return moved, string.format('%d instances moved down', moved)
end

local function format_fx_display_name(name)
  return get_fx_display_name(name) 
end

local function build_plugin_report_text()
  local buf = {}
  local function add_line(line) buf[#buf+1] = line end
  
  local track_count = r.CountTracks(0)
  add_line(string.format('Project FX report (%d track(s))', track_count))
  add_line(string.format('Settings: nameNoPrefix=%s, hideDeveloper=%s', 
    tostring(state.nameNoPrefix), tostring(state.nameHideDeveloper)))
  add_line('')
  
  for i = 0, track_count - 1 do
    local track = r.GetTrack(0, i)
    if track and r.ValidatePtr(track, 'MediaTrack*') then
      local track_name = get_track_name(track)
      add_line(string.format('- Track %d: %s', i + 1, track_name))
      
      local fx_count = r.TrackFX_GetCount(track) or 0
      if fx_count == 0 then
        add_line('  (no FX)')
      else
        for fx = 0, fx_count - 1 do
          local fx_name = get_fx_name(track, fx)
          if fx_name ~= '' then
            add_line(string.format('  %2d. %s', fx + 1, format_fx_display_name(fx_name)))
          end
        end
      end
      add_line('')
    end
  end
  
  return table.concat(buf, '\n')
end

local function print_plugin_list()
  local report_text = build_plugin_report_text()
  if not report_text or report_text == '' then 
    return false, 'No report data to save' 
  end
  
  local sep = package.config:sub(1,1)
  local base_dir = r.GetResourcePath() .. sep .. 'Scripts' .. sep .. 'TK Scripts' .. sep .. 'FX'
  
  if not ensure_directory(base_dir) then
    return false, 'Failed to create report directory'
  end
  
  local report_path = base_dir .. sep .. 'TK_FX_Report.txt'
  local success, error_msg = write_file(report_path, report_text)
  
  if success then
    return true, report_path
  else
    return false, error_msg or 'Failed to write report file'
  end
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
  
  local type_map = {
    CLAP = 'CLAP', CLAPI = 'CLAPi',
    VST = 'VST', VSTI = 'VSTi',
    VST3 = 'VST3', VST3I = 'VST3i',
    JS = 'JS',
    AU = 'AU', AUV3 = 'AUV3', AUV3I = 'AUV3i',
    LV2 = 'LV2', LV2I = 'LV2i',
    DX = 'DX', DXI = 'DXi',
  }
  
  return type_map[prefix:upper()] or 'All types'
end

local function cleanup_resources()
  if state.screenshotTex and r.ImGui_DestroyImage then
    pcall(r.ImGui_DestroyImage, state.screenshotTex)
  end
  state.screenshotTex = nil
  state.screenshotKey = nil
  state.screenshotFound = false
  if state.slotLogoTex and r.ImGui_DestroyImage then
    pcall(function() r.ImGui_DestroyImage(state.slotLogoTex) end)
  end
  state.slotLogoTex = nil
  
  if ctx then
    if iconFont and iconFont ~= false and r.ImGui_ValidatePtr and r.ImGui_Detach then
      if r.ImGui_ValidatePtr(iconFont, 'ImGui_Resource*') then
        pcall(r.ImGui_Detach, ctx, iconFont)
      end
    end
  end
  iconFont = nil
  
  ctx = nil
end

if r.atexit then
  r.atexit(cleanup_resources)
end

local copied_fx_chain_info = nil 

local SWS_COMMANDS = {
  COPY_FROM_TRACK = '_S&M_COPYFXCHAIN5',      
  PASTE_TO_SELECTED = '_S&M_COPYFXCHAIN10',  
  PASTE_TO_TRACK = '_S&M_COPYFXCHAIN8',       
}

local function get_sws_command_id(command_string)
  local id = r.NamedCommandLookup(command_string)
  return id ~= 0 and id or nil
end

local function is_sws_available()
  local test_id = get_sws_command_id(SWS_COMMANDS.COPY_FROM_TRACK)
  return test_id ~= nil
end

local function copy_fx_chain_from_track(source_track)
  if not source_track or not r.ValidatePtr(source_track, 'MediaTrack*') then
    return false, 'Invalid source track'
  end
  
  if not is_sws_available() then
    return false, 'SWS extension not found. Please install SWS/S&M extension.'
  end
  
  local fx_count = r.TrackFX_GetCount(source_track) or 0
  if fx_count == 0 then
    return false, 'No FX to copy from source track'
  end
  
  r.SetOnlyTrackSelected(source_track)
  
  local copy_cmd = get_sws_command_id(SWS_COMMANDS.COPY_FROM_TRACK)
  if copy_cmd then
    r.Main_OnCommand(copy_cmd, 0)
    
    copied_fx_chain_info = {
      source_track_name = get_track_name(source_track),
      fx_count = fx_count,
      timestamp = os.time(),
      method = 'SWS'
    }
    
    return true, string.format('Copied %d FX from track "%s" (using SWS)', fx_count, copied_fx_chain_info.source_track_name)
  else
    return false, 'SWS copy command not available'
  end
end

local function paste_fx_chain_to_selected_tracks()
  if not copied_fx_chain_info then
    return 0, 'No FX chain copied'
  end
  
  if not is_sws_available() then
    return 0, 'SWS extension not found'
  end
  
  local selected_count = r.CountSelectedTracks(0)
  if selected_count == 0 then
    return 0, 'No tracks selected'
  end
  
  local paste_cmd = get_sws_command_id(SWS_COMMANDS.PASTE_TO_SELECTED)
  if paste_cmd then
    r.Undo_BeginBlock()
    r.Main_OnCommand(paste_cmd, 0)
    r.Undo_EndBlock(string.format('Paste FX chain to %d selected track(s)', selected_count), -1)
    
    return selected_count, string.format('Pasted FX chain to %d selected track(s)', selected_count)
  else
    return 0, 'SWS paste command not available'
  end
end

local function replace_fx_chain_to_selected_tracks()
  if not copied_fx_chain_info then
    return 0, 'No FX chain copied'
  end
  
  local selected_count = r.CountSelectedTracks(0)
  if selected_count == 0 then
    return 0, 'No tracks selected'
  end
  
  r.Undo_BeginBlock()
  
  for i = 0, selected_count - 1 do
    local track = r.GetSelectedTrack(0, i)
    if track then
      local fx_count = r.TrackFX_GetCount(track) or 0
      for fx = fx_count - 1, 0, -1 do
        pcall(r.TrackFX_Delete, track, fx)
      end
    end
  end
  
  if is_sws_available() then
    local paste_cmd = get_sws_command_id(SWS_COMMANDS.PASTE_TO_SELECTED)
    if paste_cmd then
      r.Main_OnCommand(paste_cmd, 0)
      r.Undo_EndBlock(string.format('Replace FX chain on %d selected track(s)', selected_count), -1)
      return selected_count, string.format('Replaced FX chain on %d selected track(s)', selected_count)
    end
  end
  
  r.Undo_EndBlock('Failed to replace FX chain', -1)
  return 0, 'Failed to replace FX chain on selected tracks'
end

local function paste_fx_chain_to_all_tracks()
  if not copied_fx_chain_info then
    return 0, 'No FX chain copied'
  end
  
  local track_count = r.CountTracks(0)
  if track_count == 0 then
    return 0, 'No tracks in project'
  end
  
  r.Undo_BeginBlock()
  
  r.Main_OnCommand(40296, 0) 
  
  if is_sws_available() then
    local paste_cmd = get_sws_command_id(SWS_COMMANDS.PASTE_TO_SELECTED)
    if paste_cmd then
      r.Main_OnCommand(paste_cmd, 0)
      r.Undo_EndBlock(string.format('Paste FX chain to all %d track(s)', track_count), -1)
      return track_count, string.format('Pasted FX chain to all %d track(s)', track_count)
    end
  end
  
  r.Undo_EndBlock('Failed to paste FX chain to all tracks', -1)
  return 0, 'Failed to paste FX chain to all tracks'
end

local function replace_fx_chain_to_all_tracks()
  if not copied_fx_chain_info then
    return 0, 'No FX chain copied'
  end
  
  local track_count = r.CountTracks(0)
  if track_count == 0 then
    return 0, 'No tracks in project'
  end
  
  r.Undo_BeginBlock()
  
  for i = 0, track_count - 1 do
    local track = r.GetTrack(0, i)
    if track then
      local fx_count = r.TrackFX_GetCount(track) or 0
      for fx = fx_count - 1, 0, -1 do
        pcall(r.TrackFX_Delete, track, fx)
      end
    end
  end
  
  r.Main_OnCommand(40296, 0) 
  
  if is_sws_available() then
    local paste_cmd = get_sws_command_id(SWS_COMMANDS.PASTE_TO_SELECTED)
    if paste_cmd then
      r.Main_OnCommand(paste_cmd, 0)
      r.Undo_EndBlock(string.format('Replace FX chain on all %d track(s)', track_count), -1)
      return track_count, string.format('Replaced FX chain on all %d track(s)', track_count)
    end
  end
  
  r.Undo_EndBlock('Failed to replace FX chain on all tracks', -1)
  return 0, 'Failed to replace FX chain on all tracks'
end

local function create_fx_chain(track, name)
  if not track or not r.ValidatePtr(track, "MediaTrack*") then 
    return false, 'Invalid track'
  end
  
  local fx_count = r.TrackFX_GetCount(track)
  if fx_count == 0 then 
    return false, 'Track has no FX to save'
  end
  
  r.SetOnlyTrackSelected(track)
  local cmd_id = r.NamedCommandLookup("_S&M_SAVE_FXCHAIN_SLOT1")
  if cmd_id == 0 then
    return false, 'SWS extension required'
  end
  
  r.Main_OnCommand(cmd_id, 0)
  
  local resource_path = r.GetResourcePath()
  local sep = package.config:sub(1,1)
  local fx_chains_path = resource_path .. sep .. "FXChains" .. sep
  local slot_path = fx_chains_path .. "S&M FX chain slot 1.RfxChain"
  
  if not file_exists(slot_path) then
    return false, 'FX chain file not created'
  end
  
  local retval, input_name = r.GetUserInputs("Save FX Chain", 1, "Chain name:", "")
  if not retval or input_name == '' then
    return true, 'FX Chain saved as "S&M FX chain slot 1"'
  end
  
  local new_path = fx_chains_path .. input_name .. ".RfxChain"
  
  if file_exists(new_path) then
    local result = r.MB(string.format('FX Chain "%s" already exists. Overwrite?', input_name), 'File Exists', 4)
    if result ~= 6 then
      return true, 'FX Chain saved as "S&M FX chain slot 1"'
    end
    os.remove(new_path)
  end
  
  if os.rename(slot_path, new_path) then
    FX_LIST_TEST, CAT_TEST = MakeFXFiles()
    return true, string.format('FX Chain "%s" saved successfully', input_name)
  else
    return true, 'FX Chain saved as "S&M FX chain slot 1" (rename failed)'
  end
end

local function get_fx_chains_list()
  local chains = {}
  
  if not CAT_TEST then
    init_fx_parser()
  end
  
  if CAT_TEST then
    for i = 1, #CAT_TEST do
      if CAT_TEST[i].name == "FX CHAINS" and CAT_TEST[i].list then
        local function process_chain_list(list, path_prefix)
          path_prefix = path_prefix or ""
          for j = 1, #list do
            local item = list[j]
            if type(item) == "string" then
              local display_name = path_prefix == "" and item or path_prefix .. "/" .. item
              chains[#chains + 1] = {
                name = item,
                display_name = display_name,
                path = display_name,
                full_path = display_name
              }
            elseif type(item) == "table" and item.dir then
              local new_prefix = path_prefix == "" and item.dir or path_prefix .. "/" .. item.dir
              process_chain_list(item, new_prefix)
            elseif type(item) == "table" and not item.dir then
              for k = 1, #item do
                if type(item[k]) == "string" then
                  local display_name = path_prefix == "" and item[k] or path_prefix .. "/" .. item[k]
                  chains[#chains + 1] = {
                    name = item[k],
                    display_name = display_name,
                    path = display_name,
                    full_path = display_name
                  }
                end
              end
            end
          end
        end
        
        process_chain_list(CAT_TEST[i].list)
        break
      end
    end
  end
  
  table.sort(chains, function(a, b) 
    return a.display_name:lower() < b.display_name:lower() 
  end)
  
  return chains
end

local CHUNK_DEBUG = false -- Debug uitgezet 
local function dbg(msg)
  if CHUNK_DEBUG then r.ShowConsoleMsg('[FXCHAIN CHUNK] '..tostring(msg)..'\n') end
end

local function extract_fxchain_block(fullChunk)
  if not fullChunk then dbg('No fullChunk'); return nil end
  local startPos = fullChunk:find('<FXCHAIN') or fullChunk:find('%s<FXCHAIN')
  if not startPos then dbg('No <FXCHAIN found'); return nil end
  local pos, len, depth, capturing = startPos, #fullChunk, 0, false
  local endPos
  while pos <= len do
    local lineEnd = fullChunk:find('\n', pos) or (len+1)
    local line = fullChunk:sub(pos, lineEnd-1)
    if line:find('^%s*<') then
      if not capturing and line:find('^%s*<FXCHAIN') then capturing = true end
      if capturing then depth = depth + 1 end
    elseif capturing and line:match('^%s*>%s*$') then
      depth = depth - 1
      if depth == 0 then endPos = lineEnd; break end
    end
    pos = lineEnd + 1
  end
  if not endPos then dbg('Did not close FXCHAIN depth='..depth) return nil end
  local block = fullChunk:sub(startPos, endPos)
  return block, startPos, endPos
end

local function set_track_fxchain_chunk(track, newFxChainChunk)
  if not (track and newFxChainChunk and newFxChainChunk:find('<FXCHAIN')) then dbg('Bad args to set_track_fxchain_chunk'); return false end
  _G.__TK_LAST_FXCHAIN_HASHES = _G.__TK_LAST_FXCHAIN_HASHES or {}
  local ptrStr = tostring(track)
  local h = r.genGuid and r.genGuid() or (#newFxChainChunk .. ':' .. (newFxChainChunk:match('<VST.-%(') or '')) -- fallback pseudo hash
  local hashNum = 2166136261
  for i=1,#newFxChainChunk, math.max(1, math.floor(#newFxChainChunk/4000)) do
    hashNum = hashNum ~ newFxChainChunk:byte(i);
    hashNum = (hashNum * 16777619) % 4294967295
  end
  local finalHash = string.format('%08x', hashNum)
  if _G.__TK_LAST_FXCHAIN_HASHES[ptrStr] == finalHash then
    if CHUNK_DEBUG then dbg('Skip duplicate FXCHAIN apply hash '..finalHash) end
    return true
  end
  local ok, full = r.GetTrackStateChunk(track, '', false)
  if not ok or not full then dbg('GetTrackStateChunk failed'); return false end
  local oldBlock, s, e = extract_fxchain_block(full)
  if not oldBlock or not s or not e then dbg('Existing FXCHAIN block not found'); return false end
  local merged = full:sub(1, s-1) .. newFxChainChunk .. full:sub(e+1)
  local setOk = r.SetTrackStateChunk(track, merged, false)
  if CHUNK_DEBUG then dbg('SetTrackStateChunk result '..tostring(setOk)..' newLen='..#merged) end
  if setOk then _G.__TK_LAST_FXCHAIN_HASHES[ptrStr] = finalHash end
  return setOk
end

local function read_fxchain_file_block(chain_path)
  if not chain_path or chain_path == '' then return nil end
  local sep = package.config:sub(1,1)
  local rel = chain_path:gsub('/', sep)
  local full_path = r.GetResourcePath() .. sep .. 'FXChains' .. sep .. rel .. '.RfxChain'
  local f = io.open(full_path,'r'); if not f then return nil end
  local txt = f:read('*a') or ''
  f:close()
  if txt == '' then return nil end
  txt = txt:gsub('^\239\187\191','')
  if CHUNK_DEBUG then dbg('Loaded chain file '..full_path..' size '..#txt) end
  if not txt:find('<FXCHAIN') then
    if CHUNK_DEBUG then dbg('No <FXCHAIN in file; synthesizing wrapper') end
    if txt:find('\n<') or txt:find('^<') then
      local body = txt
      if not body:match('\n$') then body = body .. '\n' end
      txt = table.concat({
        '<FXCHAIN',
        'SHOW 0',
        'LASTSEL 0',
        'DOCKED 0',
        body,
        '>'
      }, '\n') .. '\n'
      if CHUNK_DEBUG then dbg('Synth wrapper body length '..#body) end
    end
  end
  return extract_fxchain_block(txt)
end

local function get_track_fx_blocks(track)
  local ok, full = r.GetTrackStateChunk(track, '', false)
  if not ok or not full then return nil end
  local block, s, e = extract_fxchain_block(full)
  if not block then return nil end
  local headerLineEnd = block:find('\n') or (#block+1)
  local header = block:sub(1, headerLineEnd-1)
  local body = block:sub(headerLineEnd+1)
  local fxRanges = {}
  local pos, len = 1, #body
  while pos <= len do
    local lineEnd = body:find('\n', pos) or (len+1)
    local line = body:sub(pos, lineEnd-1)
    if line:find('^<') and not line:find('^<FXCHAIN') then
      local d = 0
      local startFx = pos
      local p2 = pos
      while p2 <= len do
        local le2 = body:find('\n', p2) or (len+1)
        local l2 = body:sub(p2, le2-1)
        if l2:find('^<') then d = d + 1 end
        if l2:match('^>%s*$') then d = d - 1; if d == 0 then
          fxRanges[#fxRanges+1] = {start=startFx, finish=le2-1}
          pos = le2
          break
        end end
        p2 = le2 + 1
      end
    end
    pos = (body:find('\n', pos) or (len+1)) + 1
  end
  return {full=full, block=block, startPos=s, endPos=e, header=header, body=body, fxRanges=fxRanges}
end

local function rebuild_block_from_ranges(info, newOrder)
  local parts = {}
  parts[#parts+1] = info.header
  local cursor = 1
  for _, rIdx in ipairs(newOrder) do
    local rDef = info.fxRanges[rIdx]
    if rDef then
      parts[#parts+1] = info.body:sub(rDef.start, rDef.finish)
    end
  end
  parts[#parts+1] = '>'
  return table.concat(parts, '\n') .. '\n'
end

local function swap_fx_via_chunk(track, a, b)
  if a == b then return false end
  local info = get_track_fx_blocks(track)
  if not info or not info.fxRanges or not info.fxRanges[a+1] or not info.fxRanges[b+1] then return false end
  local count = #info.fxRanges
  local order = {}
  for i=1,count do order[i]=i end
  order[a+1], order[b+1] = order[b+1], order[a+1]
  local newFxChain = rebuild_block_from_ranges(info, order)
  return set_track_fxchain_chunk(track, newFxChain)
end

local function move_fx_drag_chunk(track, src, dest)
  local info = get_track_fx_blocks(track)
  if not info then return false end
  local count = #info.fxRanges
  if src < 0 or dest < 0 or src >= count or dest > count then return false end
  if dest > src then dest = dest - 1 end
  if src == dest then return false end
  local order = {}
  for i=1,count do order[i]=i end
  local grabbed = table.remove(order, src+1)
  table.insert(order, dest+1, grabbed)
  local newFxChain = rebuild_block_from_ranges(info, order)
  return set_track_fxchain_chunk(track, newFxChain)
end

local function load_fx_chain(track, chain_path, replace_existing)
  if not track or not r.ValidatePtr(track, "MediaTrack*") then 
    return false, 'Invalid track'
  end
  
  if not chain_path or chain_path == '' then
    return false, 'No chain path provided'
  end
  
  local resource_path = r.GetResourcePath()
  local sep = package.config:sub(1,1)
  local rel = chain_path:gsub('/', sep)
  local full_path = resource_path .. sep .. 'FXChains' .. sep .. rel .. '.RfxChain'
  local file = io.open(full_path,'r'); if not file then return false, string.format('FX Chain file not found: "%s"', full_path) end; file:close()
  local before = r.TrackFX_GetCount(track)
  if replace_existing then
    local chunkFailReason
    local fileBlock = read_fxchain_file_block(chain_path)
    if fileBlock then
      if CHUNK_DEBUG then dbg('File block length '..#fileBlock) end
      local okChunk = set_track_fxchain_chunk(track, fileBlock)
      if okChunk then
        local after = r.TrackFX_GetCount(track)
        return true, string.format('FX Chain replaced "%s" (%d FX) via chunk', chain_path, after)
      else
        chunkFailReason = 'set_chunk_failed'
        if CHUNK_DEBUG then dbg('Chunk replace failed; falling back to delete path') end
      end
    else
      chunkFailReason = 'file_block_nil'
      if CHUNK_DEBUG then dbg('fileBlock nil for '..tostring(chain_path)) end
    end
    local fx_count = r.TrackFX_GetCount(track)
    for i=fx_count-1,0,-1 do r.TrackFX_Delete(track,i) end
    if chunkFailReason and CHUNK_DEBUG then dbg('Fallback after reason '..chunkFailReason) end
  end
  local success = r.TrackFX_AddByName(track, full_path, false, -1000 - r.TrackFX_GetCount(track))
  if r.TrackFX_GetCount(track) == before then
    success = r.TrackFX_AddByName(track, chain_path .. '.RfxChain', false, -1000 - r.TrackFX_GetCount(track))
    if r.TrackFX_GetCount(track) == before then
      success = r.TrackFX_AddByName(track, sep .. chain_path .. '.RfxChain', false, -1000 - r.TrackFX_GetCount(track))
    end
  end
  local after = r.TrackFX_GetCount(track)
  if after > before then
  local tail = ''
  if replace_existing then tail = ' (fallback add)' end
  return true, string.format('FX Chain loaded "%s" (%d FX)%s', chain_path, after - before, tail)
  end
  return false, string.format('No FX added from chain "%s"', chain_path)
end

local function add_chain_file_to_track(track, chain_path)
  if not track then return false, 'Invalid track' end
  if not chain_path or chain_path=='' then return false, 'No chain path' end
  local before = r.TrackFX_GetCount(track)
  local resource_path = r.GetResourcePath()
  local sep = package.config:sub(1,1)
  local full_path = resource_path .. sep .. 'FXChains' .. sep .. chain_path .. '.RfxChain'
  local file = io.open(full_path,'r')
  if not file then return false, 'Chain file not found' end
  file:close()
  r.TrackFX_AddByName(track, full_path, false, -1000 - r.TrackFX_GetCount(track))
  if r.TrackFX_GetCount(track) == before then
    r.TrackFX_AddByName(track, chain_path .. '.RfxChain', false, -1000 - r.TrackFX_GetCount(track))
  end
  if r.TrackFX_GetCount(track) == before then
    local sep = package.config:sub(1,1)
    r.TrackFX_AddByName(track, sep .. chain_path .. '.RfxChain', false, -1000 - r.TrackFX_GetCount(track))
  end
  local after = r.TrackFX_GetCount(track)
  return after > before, (after>before) and (after-before) or 0
end

local function delete_fx_chain(chain_path)
  if not chain_path or chain_path == '' then
    return false, 'No chain path provided'
  end
  
  local resource_path = r.GetResourcePath()
  local sep = package.config:sub(1,1)
  local full_path = resource_path .. sep .. "FXChains" .. sep .. chain_path .. ".RfxChain"
  
  if not file_exists(full_path) then
    return false, 'FX Chain file not found'
  end
  
  local result = r.MB(string.format('Delete FX Chain "%s"?\n\nThis action cannot be undone.', chain_path), 
    'Confirm Delete', 4)
  
  if result == 6 then
    if os.remove(full_path) then
      FX_LIST_TEST, CAT_TEST = MakeFXFiles()
      return true, string.format('FX Chain "%s" deleted', chain_path)
    else
      return false, 'Failed to delete FX chain file'
    end
  end
  
  return false, 'Delete cancelled'
end

local function rename_fx_chain(old_path, new_name)
  if not old_path or old_path == '' or not new_name or new_name == '' then
    return false, 'Invalid parameters'
  end
  
  local resource_path = r.GetResourcePath()
  local sep = package.config:sub(1,1)
  local fx_chains_path = resource_path .. sep .. "FXChains" .. sep
  local old_full_path = fx_chains_path .. old_path .. ".RfxChain"
  local new_full_path = fx_chains_path .. new_name .. ".RfxChain"
  
  if not file_exists(old_full_path) then
    return false, 'Original FX Chain file not found'
  end
  
  if file_exists(new_full_path) then
    local result = r.MB(string.format('FX Chain "%s" already exists. Overwrite?', new_name), 'File Exists', 4)
    if result ~= 6 then
      return false, 'Rename cancelled'
    end
  end
  
  if os.rename(old_full_path, new_full_path) then
    FX_LIST_TEST, CAT_TEST = MakeFXFiles()
    return true, string.format('FX Chain renamed to "%s"', new_name)
  else
    return false, 'Failed to rename FX Chain file'
  end
end

local function load_fx_chain_to_selected_tracks(chain_path, replace_existing)
  if not chain_path or chain_path == '' then
    return 0, 'No chain path provided'
  end
  
  local selected_count = r.CountSelectedTracks(0)
  if selected_count == 0 then
    return 0, 'No tracks selected'
  end
  
  r.Undo_BeginBlock()
  
  local success_count = 0
  local fileBlock = replace_existing and read_fxchain_file_block(chain_path) or nil
  for i=0, selected_count-1 do
    local track = r.GetSelectedTrack(0,i)
    if track then
      if replace_existing and fileBlock then
        if set_track_fxchain_chunk(track, fileBlock) then success_count = success_count + 1 goto continue_sel end
      end
      local ok = select(1, add_chain_file_to_track(track, chain_path))
      if ok then success_count = success_count + 1 end
    end
    ::continue_sel::
  end
  
  local action = replace_existing and "replaced with" or "loaded to"
  r.Undo_EndBlock(string.format('FX Chain %s %d selected track(s)', action, success_count), -1)
  return success_count, string.format('FX Chain %s %d selected track(s)', action, success_count)
end

local function load_fx_chain_to_all_tracks(chain_path, replace_existing)
  if not chain_path or chain_path == '' then
    return 0, 'No chain path provided'
  end
  
  local track_count = r.CountTracks(0)
  if track_count == 0 then
    return 0, 'No tracks in project'
  end
  
  r.Undo_BeginBlock()
  
  local success_count = 0
  local fileBlock = replace_existing and read_fxchain_file_block(chain_path) or nil
  for i=0, track_count-1 do
    local track = r.GetTrack(0,i)
    if track then
      if replace_existing and fileBlock then
        if set_track_fxchain_chunk(track, fileBlock) then success_count = success_count + 1 goto continue_all end
      end
      local ok = select(1, add_chain_file_to_track(track, chain_path))
      if ok then success_count = success_count + 1 end
    end
    ::continue_all::
  end
  
  local action = replace_existing and "replaced with" or "loaded to"
  r.Undo_EndBlock(string.format('FX Chain %s all %d track(s)', action, success_count), -1)
  return success_count, string.format('FX Chain %s all %d track(s)', action, success_count)
end

local function save_fx_chains_cache(chains_list)
  if chains_list then
    r.SetExtState('TK_FX_Slots_SingleTrack', 'fx_chains_cache_time', tostring(os.time()), true)
    
    r.SetExtState('TK_FX_Slots_SingleTrack', 'fx_chains_cache_count', tostring(#chains_list), true)
    
    for i, chain in ipairs(chains_list) do
      r.SetExtState('TK_FX_Slots_SingleTrack', 'fx_chain_' .. i .. '_path', chain.path or '', true)
      r.SetExtState('TK_FX_Slots_SingleTrack', 'fx_chain_' .. i .. '_name', chain.name or '', true)
      r.SetExtState('TK_FX_Slots_SingleTrack', 'fx_chain_' .. i .. '_display', chain.display_name or '', true)
    end
  end
end

local function load_fx_chains_cache()
  local cache_count_str = r.GetExtState('TK_FX_Slots_SingleTrack', 'fx_chains_cache_count')
  local cache_time_str = r.GetExtState('TK_FX_Slots_SingleTrack', 'fx_chains_cache_time')
  
  if cache_count_str and cache_count_str ~= '' and cache_time_str and cache_time_str ~= '' then
    local cache_count = tonumber(cache_count_str)
    local cache_time = tonumber(cache_time_str)
    
    if cache_count and cache_count > 0 then
      local chains = {}
      for i = 1, cache_count do
        local path = r.GetExtState('TK_FX_Slots_SingleTrack', 'fx_chain_' .. i .. '_path')
        local name = r.GetExtState('TK_FX_Slots_SingleTrack', 'fx_chain_' .. i .. '_name')
        local display = r.GetExtState('TK_FX_Slots_SingleTrack', 'fx_chain_' .. i .. '_display')
        
        if path and path ~= '' then
          table.insert(chains, {
            path = path,
            name = name,
            display_name = display
          })
        end
      end
      
      if #chains > 0 then
        return chains, cache_time
      end
    end
  end
  return nil, nil
end

local function refresh_fx_chains_list(force_refresh)
  if not force_refresh then
    local cached_chains, cache_time = load_fx_chains_cache()
    if cached_chains then
      state.fxChains = cached_chains
      state.fxChainsFromCache = true
      return
    end
  end
  
  FX_LIST_TEST, CAT_TEST = MakeFXFiles()
  state.fxChains = get_fx_chains_list()
  state.fxChainsFromCache = false

  save_fx_chains_cache(state.fxChains)
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
  snap.name = fxname
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
  for tr, _ in tracks_iter(false) do
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
  if not state.pickerTriedCache then
    local items, err = read_cache_items()
    state.pickerTriedCache = true
    if items then
      state.pickerItems = items
      state.pickerLoadedFromCache = true
      state.pickerErr = nil
      return
    else
      state.pickerErr = 'No cached list (press Refresh)'
    end
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
  if state.screenshotTex then
    if r.ImGui_DestroyImage and type(state.screenshotTex) == "userdata" then
      pcall(function() r.ImGui_DestroyImage(state.screenshotTex) end)
    end
    state.screenshotTex = nil
  end
  state.screenshotFound = false
  state.screenshotKey = nil
  state.screenshotNeedsRefresh = true
  state.deferScreenshotDraw = 0
end

local function validate_screenshot_ptr()
  if state.screenshotTex and r.ImGui_ValidatePtr then
    local ok = false
    pcall(function() ok = r.ImGui_ValidatePtr(state.screenshotTex, 'ImGui_Image*') end)
    if not ok then
      state.screenshotTex = nil
      state.screenshotFound = false
      state.screenshotNeedsRefresh = true
      state.deferScreenshotDraw = 0
    end
  end
end

local function ensure_source_screenshot(add)
  if not add or add == '' then release_screenshot(); return end
  if state.screenshotNeedsRefresh ~= true and state.screenshotKey == add and (state.screenshotTex or state.screenshotFound) then return end
  release_screenshot() 
  if not r.ImGui_CreateImage then state.screenshotKey = add; state.screenshotFound = false; return end
  local path = find_screenshot_path(add)
  if path then
    local ok, tex = pcall(function() return r.ImGui_CreateImage(path) end)
    if ok and tex and type(tex) == "userdata" then
      state.screenshotTex = tex
      state.screenshotFound = true
      state.screenshotKey = add
      state.screenshotNeedsRefresh = false
      state.deferScreenshotDraw = 1 
      return
    end
  end
  state.screenshotKey = add
  state.screenshotFound = false
  state.screenshotNeedsRefresh = false
  state.deferScreenshotDraw = 0
end

local function ensure_slot_logo()
  if state.slotLogoTex or not r.ImGui_CreateImage then return end
  
  local function try_load_image(path)
    local file_test = io.open(path, 'r')
    if file_test then
      file_test:close()
      local ok, tex = pcall(function() return r.ImGui_CreateImage(path) end)
      if ok and tex and type(tex) == 'userdata' then
        return tex
      end
    end
    return nil
  end
  
  if script_path and script_path ~= '' then
    local tex = try_load_image(script_path .. 'SLOTS.png')
    if tex then 
      state.slotLogoTex = tex 
      return 
    end
  end
  
  local info = debug.getinfo(1, "S")
  if info and info.source then
    local source_path = info.source:match("^@(.+)")
    if source_path then
      local dir = source_path:match("^(.+[/\\])")
      if dir then
        local tex = try_load_image(dir .. 'SLOTS.png')
        if tex then 
          state.slotLogoTex = tex 
          return 
        end
      end
    end
  end
  
  local tex = try_load_image('SLOTS.png')
  if tex then 
    state.slotLogoTex = tex 
    return 
  end
  
  local resource_path = r.GetResourcePath()
  if resource_path then
    local sep = package.config:sub(1,1)
    local paths = {
      resource_path .. sep .. 'Scripts' .. sep .. 'TK Scripts' .. sep .. 'TK FX SLOTS MANAGER' .. sep .. 'SLOTS.png',
      resource_path .. sep .. 'Scripts' .. sep .. 'TK Scripts' .. sep .. 'SLOTS.png'
    }
    
    for _, path in ipairs(paths) do
      local tex = try_load_image(path)
      if tex then 
        state.slotLogoTex = tex 
        return 
      end
    end
  end
  
  state.slotLogoTex = false
end


local function delete_all_instances(sourceName, placeholderAdd, placeholderAlias)
  if not sourceName or sourceName == '' then return 0, 'No source FX selected' end
  local deleted = 0
  r.Undo_BeginBlock()
  for tr, _ in tracks_iter(false) do
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
  local scopeSelected = state.replScopeSelected or state.scopeSelectedOnly
  for tr, _ in tracks_iter(scopeSelected) do
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
  local scopeSelected = state.replScopeSelected or state.scopeSelectedOnly
  for tr, _ in tracks_iter(scopeSelected) do
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
  local scopeSel = false 
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
  if state.showPanelReplacement == false then return end
  if state.replHeaderOpen then r.ImGui_SetNextItemOpen(ctx, true, r.ImGui_Cond_FirstUseEver()) end
  local srcName = state.selectedSourceFXName
  local srcLabel = (srcName and srcName ~= '') and format_fx_display_name(srcName) or nil
  local hdrVisible = 'Replacement:' .. (srcLabel and (' (for source ' .. tostring(srcLabel) .. ')') or '')
  local headerId = hdrVisible .. '##replacement_header'
  local open = r.ImGui_CollapsingHeader(ctx, headerId, 0)
  if open ~= nil and open ~= state.replHeaderOpen then state.replHeaderOpen = open; save_user_settings() end
  if open then
  local halfWidth = (r.ImGui_GetContentRegionAvail(ctx) - 4) * 0.5
    do
      local label = (state.replaceDisplay and state.replaceDisplay ~= '') and tostring(state.replaceDisplay) or 'choose replacement plugin'
      local availW = select(1, r.ImGui_GetContentRegionAvail(ctx)) or 0
      local textW = 0
      if r.ImGui_CalcTextSize then textW = select(1, r.ImGui_CalcTextSize(ctx, label)) or 0 end
      local padX = math.max(0, (availW - textW) * 0.5)
      local curX = select(1, r.ImGui_GetCursorPos(ctx)) or 0
      if r.ImGui_GetWindowDrawList then
        local dl = r.ImGui_GetWindowDrawList(ctx)
        if dl and r.ImGui_GetCursorScreenPos then
          local startX, startY = r.ImGui_GetCursorScreenPos(ctx)
          local bgX1 = startX
          local bgY1 = startY
          local bgX2 = startX + availW
            local lineH = (r.ImGui_GetTextLineHeightWithSpacing and r.ImGui_GetTextLineHeightWithSpacing(ctx)) or (r.ImGui_GetTextLineHeight and r.ImGui_GetTextLineHeight(ctx)) or 18
          local bgY2 = bgY1 + lineH
          local selCol = col_u32(0.24,0.38,0.55,0.90)
          if r.ImGui_DrawList_AddRectFilled then r.ImGui_DrawList_AddRectFilled(dl, bgX1, bgY1, bgX2, bgY2, selCol, 4) end
        end
      end
      r.ImGui_SetCursorPosX(ctx, curX + padX)
      if state.replaceDisplay and state.replaceDisplay ~= '' then
        r.ImGui_Text(ctx, label)
      else
        r.ImGui_TextDisabled(ctx, label)
      end
      r.ImGui_Dummy(ctx, 0, 4)
    end

  if state.useDummyReplace then
      if not state.tkBlankVariants then refresh_tk_blank_variants() end
      r.ImGui_SetNextItemWidth(ctx, halfWidth)
      local openedDV = r.ImGui_BeginCombo(ctx, '##dvariants', state.placeholderVariantName or 'Variant…')
      if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then r.ImGui_SetTooltip(ctx, 'Choose preset variant') end
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
  r.ImGui_SameLine(ctx, 0, gap)
    r.ImGui_SetNextItemWidth(ctx, halfWidth)
      local chgAlias, alias
      local flags = 0
      if r.ImGui_InputTextFlags_EnterReturnsTrue then flags = flags | r.ImGui_InputTextFlags_EnterReturnsTrue() end
      if r.ImGui_InputTextFlags_AutoSelectAll then flags = flags | r.ImGui_InputTextFlags_AutoSelectAll() end
      if r.ImGui_InputTextWithHint then
        chgAlias, alias = r.ImGui_InputTextWithHint(ctx, '##ph_alias', 'custom name…', state.placeholderCustomName, flags)
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
      if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then r.ImGui_SetTooltip(ctx, 'Custom display name') end
    else
      local button_width = r.ImGui_GetContentRegionAvail(ctx)
      do
        local active = state.showPicker == true
        if active then
          r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x33AA33AA)
          r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0x33CC33DD)
          r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0x229922FF)
        end
        local label = active and 'Pick from list (on)' or 'Pick from list'
        if r.ImGui_Button(ctx, label, button_width, 0) then
          state.showPicker = not active
        end
        if active then r.ImGui_PopStyleColor(ctx, 3) end
      end
      if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then r.ImGui_SetTooltip(ctx, 'Open volledige FX browser') end
    end
    do
  r.ImGui_Dummy(ctx,0,3)
  local availW = r.ImGui_GetContentRegionAvail(ctx)
  local halfW = (availW - 8) * 0.5
  local startX = select(1, r.ImGui_GetCursorPos(ctx))
  r.ImGui_PushItemWidth(ctx, halfW)
  local chgDummy2, vDummy2 = r.ImGui_Checkbox(ctx, 'Use placeholder', state.useDummyReplace)
  if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then r.ImGui_SetTooltip(ctx, 'Use a blank placeholder plugin name instead of the real replacement FX') end
  if chgDummy2 then state.useDummyReplace = vDummy2 end
  r.ImGui_PopItemWidth(ctx)
  r.ImGui_SameLine(ctx)
  local gapAlign = 6 
  local curX, curY = r.ImGui_GetCursorPos(ctx)
  local targetX = startX + halfW + gapAlign
  if curX < targetX then r.ImGui_SetCursorPosX(ctx, targetX) end
  local chgSel, valSel = r.ImGui_Checkbox(ctx, 'Selected track(s) Only', state.replScopeSelected or false)
  if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then r.ImGui_SetTooltip(ctx, 'Limit replace operation to currently selected tracks') end
  if chgSel then state.replScopeSelected = valSel; save_user_settings() end
    end

   do
      local sourceValid = state.selectedSourceFXIndex ~= nil
      local hasReplacement = (state.useDummyReplace and state.placeholderCustomName and state.placeholderCustomName ~= '') or (state.replaceWith and state.replaceWith ~= '')
      local abEnabled = sourceValid and hasReplacement
      local rowAvail = r.ImGui_GetContentRegionAvail(ctx)
      local gapRow = 6
      local abW = (rowAvail - gapRow) * 0.5
      local replW = rowAvail - gapRow - abW
      if not abEnabled and r.ImGui_BeginDisabled then r.ImGui_BeginDisabled(ctx) end
      if r.ImGui_Button(ctx, 'A/B Replace', abW, 0) then
        local srcIdx = tonumber(state.selectedSourceFXIndex)
        if srcIdx then if not (state.abSlotIndex == srcIdx and state.abSnap) then ensure_ab_pair() else ab_toggle() end end
      end
      if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then
        if not (state.abSlotIndex == tonumber(state.selectedSourceFXIndex) and state.abSnap) then
          r.ImGui_SetTooltip(ctx, 'Prepare A/B pair (source & replacement) for quick toggling')
        else
          r.ImGui_SetTooltip(ctx, 'Toggle between original (A) and replacement (B)')
        end
      end
      if not abEnabled and r.ImGui_EndDisabled then r.ImGui_EndDisabled(ctx) end
      r.ImGui_SameLine(ctx,0,gapRow)
     
      local pushedTight = false
      if r.ImGui_PushStyleVar and r.ImGui_StyleVar_ItemSpacing then
        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing(), 6, 2) 
        pushedTight = true
      end

  local rowW = r.ImGui_GetContentRegionAvail(ctx)
  local btnW = rowW
      local srcIdx = tonumber(state.selectedSourceFXIndex)
      local selectedTrackCount = r.CountSelectedTracks(0)
      local hasReplacementCurrent = sourceValid and hasReplacement
      local canDo = (srcIdx ~= nil) and hasReplacementCurrent and ((state.replScopeSelected and selectedTrackCount>0) or (not state.replScopeSelected))
      if not canDo and r.ImGui_BeginDisabled then r.ImGui_BeginDisabled(ctx) end
  if r.ImGui_Button(ctx, 'Replace Source', btnW, 0) then
        local addName = state.useDummyReplace and ensure_tk_blank_addname(state.placeholderCustomName) or state.replaceWith
        if addName and addName ~= '' then
          if state.replScopeSelected then
            local replacedCount = 0
            r.Undo_BeginBlock2(0)
            for t = 0, selectedTrackCount - 1 do
              local tr = r.GetSelectedTrack(0, t)
              if tr and r.ValidatePtr(tr, 'MediaTrack*') then
                local fxCount = r.TrackFX_GetCount(tr)
                local matchIdx = {}
                for i = 0, fxCount - 1 do if get_fx_name(tr, i) == state.selectedSourceFXName then matchIdx[#matchIdx+1]=i end end
                table.sort(matchIdx, function(a,b) return a>b end)
                for _, idx in ipairs(matchIdx) do
                  local deletedOK = pcall(function() r.TrackFX_Delete(tr, idx) end)
                  if deletedOK then
                    local newIdx = r.TrackFX_AddByName(tr, addName, false, -1)
                    if newIdx and newIdx >= 0 then
                      if newIdx ~= idx then pcall(function() r.TrackFX_CopyToTrack(tr, newIdx, tr, idx, true) end) end
                      replacedCount = replacedCount + 1
                      if state.useDummyReplace and state.placeholderCustomName and state.placeholderCustomName ~= '' then rename_fx_instance(tr, idx, state.placeholderCustomName) end
                    end
                  end
                end
              end
            end
            r.Undo_EndBlock2(0, 'Replace FX on selected tracks', -1)
            if replacedCount > 0 then state.selectedSourceFXName = addName; state.pendingMessage = string.format('Replaced %d instance(s).', replacedCount) else state.pendingError = 'No matching FX found.' end
          else
            local source = state.selectedSourceFXName
            local cnt = select(1, replace_all_instances(source, addName))
            state.pendingMessage = string.format('%d instances replaced.', cnt)
          end
        else
          state.pendingError = 'No replacement FX name.'
        end
      end
      if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then
        if state.replScopeSelected then
          r.ImGui_SetTooltip(ctx, 'Replace the source FX with the replacement on selected track(s)')
        else
          r.ImGui_SetTooltip(ctx, 'Replace every instance of the source FX with the replacement across all tracks')
        end
      end
      if not canDo and r.ImGui_EndDisabled then r.ImGui_EndDisabled(ctx) end

  if pushedTight and r.ImGui_PopStyleVar then r.ImGui_PopStyleVar(ctx,1) end
  r.ImGui_Dummy(ctx,0,1)
   end
    
   
    local tracksAffected, changes = compute_preview()
    
    local canExecute = true
    if not state.selectedSourceFXName or state.selectedSourceFXName == '' then canExecute = false end
    if state.actionType ~= 'delete_all' then
      if not state.useDummyReplace and (not state.replaceWith or state.replaceWith == '') then canExecute = false end
    end
    if changes <= 0 then canExecute = false end

    if not canExecute and r.ImGui_BeginDisabled then r.ImGui_BeginDisabled(ctx) end
    
  if not canExecute and r.ImGui_EndDisabled then r.ImGui_EndDisabled(ctx) end
    
  local gap = 6
  local availRowW = r.ImGui_GetContentRegionAvail(ctx)
  local colW = (availRowW - gap) * 0.5
  if colW < 90 then colW = 90 end
  local rowStartX = r.ImGui_GetCursorPosX(ctx)
  r.ImGui_PushItemWidth(ctx, 70)
  local chgSlot, slot1 = r.ImGui_InputInt(ctx, '##slot_inline', (tonumber(state.batchSlotIndex) or 0) + 1)
  if chgSlot then state.batchSlotIndex = math.max(0, (tonumber(slot1) or 1) - 1) end
  if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then r.ImGui_SetTooltip(ctx, 'Slot number (1-based)') end
  r.ImGui_PopItemWidth(ctx)

  local secondX = rowStartX + colW + gap
  r.ImGui_SameLine(ctx, 0, 0)
  r.ImGui_SetCursorPosX(ctx, secondX)
  local chgMS, vMS = r.ImGui_Checkbox(ctx, 'Only if slot is source', state.slotMatchSourceOnly)
  if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then r.ImGui_SetTooltip(ctx, 'Apply only when the slot currently contains the chosen source FX') end
  if chgMS then state.slotMatchSourceOnly = vMS end
  if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then r.ImGui_SetTooltip(ctx, 'When enabled: replace/add only if this slot currently holds the selected source FX') end

  local btnW = colW
  if btnW < 90 then btnW = 90 end
  local beforeBtnX = r.ImGui_GetCursorPosX(ctx)
  if not canExecute and r.ImGui_BeginDisabled then r.ImGui_BeginDisabled(ctx) end
  if r.ImGui_Button(ctx, 'Replace slot', btnW, 0) then
    state.actionType = 'replace_slot'
    local source = state.selectedSourceFXName
    local addName = state.useDummyReplace and ensure_tk_blank_addname(state.placeholderCustomName) or state.replaceWith
    local alias = state.useDummyReplace and state.placeholderCustomName or nil
    local onlyIf = (state.slotMatchSourceOnly and source) or nil
    local cnt = select(1, replace_by_slot_across_tracks(state.batchSlotIndex, addName, alias, onlyIf))
    state.pendingMessage = string.format('Replaced on %d track(s).', cnt)
  end
  if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then r.ImGui_SetTooltip(ctx, string.format('Replace slot #%d across tracks', (state.batchSlotIndex or 0) + 1)) end

  r.ImGui_SameLine(ctx, 0, gap)
  if r.ImGui_Button(ctx, 'Add at slot', btnW, 0) then
    state.actionType = 'add_slot'
    local addName = state.useDummyReplace and ensure_tk_blank_addname(state.placeholderCustomName) or state.replaceWith
    local alias = state.useDummyReplace and state.placeholderCustomName or nil
    local cnt = select(1, add_by_slot_across_tracks(state.batchSlotIndex, addName, alias))
    state.pendingMessage = string.format('Added on %d track(s).', cnt)
  end
  if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then r.ImGui_SetTooltip(ctx, string.format('Add replacement at slot #%d across tracks', (state.batchSlotIndex or 0) + 1)) end
  if not canExecute and r.ImGui_EndDisabled then r.ImGui_EndDisabled(ctx) end

      if changes and tracksAffected and changes >= 0 then
      state.previewPending = string.format('Preview: %d change(s) on %d track(s)', changes, tracksAffected)
    end
  r.ImGui_Dummy(ctx, 0, 2)
  r.ImGui_Separator(ctx)
    
  end 
end 

local function draw_source_panel()
  if state.showPanelSource == false then return end
  if state.sourceHeaderOpen then r.ImGui_SetNextItemOpen(ctx, true, r.ImGui_Cond_FirstUseEver()) end
  local prevOpen = state.sourceHeaderOpen
  local open = r.ImGui_CollapsingHeader(ctx, 'Source:', 0)
  if open ~= nil and open ~= state.sourceHeaderOpen then state.sourceHeaderOpen = open; save_user_settings() end
  if open ~= nil and open ~= prevOpen then
    state.deferScreenshotDraw = 1
  end
  if not (state.sourceHeaderOpen and open) then return end
  local tr = get_selected_track()
  local srcIdx = tonumber(state.selectedSourceFXIndex)
  if not (tr and srcIdx) then r.ImGui_Text(ctx, 'Pick a Source'); return end
  if state.abSlotIndex and state.abSlotIndex ~= srcIdx then
    if state.abActiveIsRepl then ab_cancel() else state.abSlotIndex, state.abSnap, state.abActiveIsRepl = nil, nil, false end
  end
  local srcCtrlIdx = srcIdx
  local sname = state.selectedSourceFXName
  if not sname or sname == '' then local _, nm = r.TrackFX_GetFXName(tr, srcIdx, ''); sname = nm end
  local disp = format_fx_display_name(sname)
  do
    local label = tostring(disp or '')
    local availW = select(1, r.ImGui_GetContentRegionAvail(ctx)) or 0
    local textW = 0
    if r.ImGui_CalcTextSize then textW = select(1,r.ImGui_CalcTextSize(ctx,label)) or 0 end
    local padX = math.max(0,(availW - textW)*0.5)
    local curX, curY = select(1,r.ImGui_GetCursorPos(ctx)) or 0, select(2,r.ImGui_GetCursorPos(ctx)) or 0
    if r.ImGui_GetWindowDrawList then
      local dl = r.ImGui_GetWindowDrawList(ctx)
      if dl and r.ImGui_GetCursorScreenPos then
        local startX, startY = r.ImGui_GetCursorScreenPos(ctx)
        local bgX1 = startX
        local bgY1 = startY
        local bgX2 = startX + availW
        local lineH = (r.ImGui_GetTextLineHeightWithSpacing and r.ImGui_GetTextLineHeightWithSpacing(ctx)) or (r.ImGui_GetTextLineHeight and r.ImGui_GetTextLineHeight(ctx)) or 18
        local bgY2 = bgY1 + lineH
        local selCol = col_u32(0.24,0.38,0.55,0.90)
        if r.ImGui_DrawList_AddRectFilled then
          r.ImGui_DrawList_AddRectFilled(dl, bgX1, bgY1, bgX2, bgY2, selCol, 4)
        end
      end
    end
    r.ImGui_SetCursorPosX(ctx, curX + padX)
    r.ImGui_Text(ctx, label)
  end
  r.ImGui_Dummy(ctx,0,2)
  local availW = select(1, r.ImGui_GetContentRegionAvail(ctx)) or 0
  if state.showScreenshot then
    local _, addname = r.TrackFX_GetFXName(tr, srcCtrlIdx, '')
    validate_screenshot_ptr()
    if state.screenshotNeedsRefresh or state.screenshotKey ~= addname or not state.screenshotTex then
      state.screenshotNeedsRefresh = true
      ensure_source_screenshot(addname)
    end
    local maxW = math.max(120, math.min(280, availW - 8))
    local imgW, imgH = maxW, math.floor(maxW * 0.56)
    local pad, spacing = 8, 8
    local knobSize = math.floor(math.min(imgW, imgH) * 0.30); if knobSize < 34 then knobSize = 34 end
    local deltaBtnH, labelH = 18, 16
    local mixValPreview = get_fx_overall_wet(tr, srcCtrlIdx) or 1.0
    local previewTxt = ('Wet %d%%'):format(math.floor(mixValPreview*100+0.5))
    local labelW = 0; if r.ImGui_CalcTextSize then labelW = select(1, r.ImGui_CalcTextSize(ctx, previewTxt)) or 0 end
    local neededInnerW = math.max(knobSize, 64, labelW)
    local ctrlBoxW = neededInnerW + pad * 2 + 6
    local ctrlBoxH = pad + deltaBtnH + 2 + knobSize + 2 + labelH + pad
    local imgBoxW = imgW + pad * 2
    local imgBoxH = imgH + pad * 2
    local frameH = math.max(imgBoxH, ctrlBoxH)
    local totalW = imgBoxW + spacing + ctrlBoxW
    if not state.hideWetControl and imgBoxH > ctrlBoxH * 1.35 then
      local desiredImgH = math.max(ctrlBoxH - pad * 2, 40)
      local scale = desiredImgH / imgH
      if scale < 1.0 then
        imgW = math.max(80, math.floor(imgW * scale))
        imgH = math.floor(imgH * scale)
        imgBoxW = imgW + pad * 2
        imgBoxH = imgH + pad * 2
        frameH = math.max(imgBoxH, ctrlBoxH)
      end
    end
    if totalW > availW - 4 then
      local maxImgAllowed = math.max(80, (availW - ctrlBoxW - spacing - pad * 2))
      if maxImgAllowed < imgW then
        imgW = maxImgAllowed; imgH = math.floor(imgW * 0.56)
        imgBoxW = imgW + pad * 2; imgBoxH = imgH + pad * 2
        frameH = math.max(imgBoxH, ctrlBoxH)
        totalW = imgBoxW + spacing + ctrlBoxW
      end
    end
    local startX = select(1, r.ImGui_GetCursorPos(ctx)) or 0
    local startY = select(2, r.ImGui_GetCursorPos(ctx)) or 0
  totalW = imgBoxW + spacing + ctrlBoxW
  state.lastSourceBlockWidth = totalW 
    if totalW < 0 then totalW = 0 end
    local offset
    if totalW >= availW then
      offset = 0 
    else
      offset = math.floor((availW - totalW) * 0.5 + 0.5)
    end
    local imgX = startX + offset
    local ctrlX = imgX + imgBoxW + spacing
    if state.hideWetControl then
      frameH = imgBoxH
      imgX = startX + math.max(0,(availW - imgBoxW) * 0.5)
      if r.ImGui_SetCursorPos then r.ImGui_SetCursorPos(ctx, imgX, startY) end
      if r.ImGui_GetWindowDrawList then
        local dl = r.ImGui_GetWindowDrawList(ctx)
        local x1,y1 = r.ImGui_GetCursorScreenPos(ctx)
        local x2,y2 = x1 + imgBoxW, y1 + frameH
        if r.ImGui_DrawList_AddRectFilled then r.ImGui_DrawList_AddRectFilled(dl, x1,y1,x2,y2, col_u32(0.05,0.05,0.05,0.45), 6) end
        if r.ImGui_DrawList_AddRect then r.ImGui_DrawList_AddRect(dl, x1,y1,x2,y2, col_u32(0.8,0.8,0.8,0.25), 6,0,1.1) end
      end
      if r.ImGui_SetCursorPos then r.ImGui_SetCursorPos(ctx, imgX + pad, startY + pad) end
      if state.deferScreenshotDraw and state.deferScreenshotDraw > 0 then
        state.deferScreenshotDraw = state.deferScreenshotDraw - 1
        local placeholder = 'Loading...'
        local tw,th = 0,0
        if r.ImGui_CalcTextSize then tw,th = r.ImGui_CalcTextSize(ctx, placeholder) end
        local offX = (imgW - tw) * 0.5
        local offY = (imgH - th) * 0.5
        r.ImGui_SetCursorPos(ctx, imgX + pad + offX, startY + pad + offY)
        r.ImGui_TextDisabled(ctx, placeholder)
      elseif state.screenshotTex and type(state.screenshotTex)=='userdata' then
        local ok = pcall(function() if r.ImGui_Image then r.ImGui_Image(ctx, state.screenshotTex, imgW, imgH) end end)
        if not ok then release_screenshot() end
      else
        local placeholder = 'No Image'
        local tw,th = 0,0
        if r.ImGui_CalcTextSize then tw,th = r.ImGui_CalcTextSize(ctx, placeholder) end
        local offX = (imgW - tw) * 0.5
        local offY = (imgH - th) * 0.5
        r.ImGui_SetCursorPos(ctx, imgX + pad + offX, startY + pad + offY)
        r.ImGui_TextDisabled(ctx, placeholder)
      end
  if r.ImGui_SetCursorPos then r.ImGui_SetCursorPos(ctx, startX, startY + frameH + 6) end
  if r.ImGui_Dummy then r.ImGui_Dummy(ctx, 0, 0) end
    else
      if r.ImGui_SetCursorPos then r.ImGui_SetCursorPos(ctx, imgX, startY) end
      if r.ImGui_GetWindowDrawList then
        local dl = r.ImGui_GetWindowDrawList(ctx)
        local x1,y1 = r.ImGui_GetCursorScreenPos(ctx)
        local x2,y2 = x1 + imgBoxW, y1 + frameH
        if r.ImGui_DrawList_AddRectFilled then r.ImGui_DrawList_AddRectFilled(dl, x1,y1,x2,y2, col_u32(0.05,0.05,0.05,0.45), 6) end
        if r.ImGui_DrawList_AddRect then r.ImGui_DrawList_AddRect(dl, x1,y1,x2,y2, col_u32(0.8,0.8,0.8,0.25), 6,0,1.1) end
      end
      if r.ImGui_SetCursorPos then r.ImGui_SetCursorPos(ctx, imgX + pad, startY + pad) end
      if state.deferScreenshotDraw and state.deferScreenshotDraw > 0 then
        state.deferScreenshotDraw = state.deferScreenshotDraw - 1
        local placeholder = 'Loading...'
        local tw,th = 0,0
        if r.ImGui_CalcTextSize then tw,th = r.ImGui_CalcTextSize(ctx, placeholder) end
        local offX = (imgW - tw) * 0.5
        local offY = (imgH - th) * 0.5
        r.ImGui_SetCursorPos(ctx, imgX + pad + offX, startY + pad + offY)
        r.ImGui_TextDisabled(ctx, placeholder)
      elseif state.screenshotTex and type(state.screenshotTex)=='userdata' then
        local ok = pcall(function() if r.ImGui_Image then r.ImGui_Image(ctx, state.screenshotTex, imgW, imgH) end end)
        if not ok then release_screenshot() end
      else
        local placeholder = 'No Image'
        local tw,th = 0,0
        if r.ImGui_CalcTextSize then tw,th = r.ImGui_CalcTextSize(ctx, placeholder) end
        local offX = (imgW - tw) * 0.5
        local offY = (imgH - th) * 0.5
        r.ImGui_SetCursorPos(ctx, imgX + pad + offX, startY + pad + offY)
        r.ImGui_TextDisabled(ctx, placeholder)
      end
      if r.ImGui_SetCursorPos then r.ImGui_SetCursorPos(ctx, ctrlX, startY) end
      if r.ImGui_GetWindowDrawList then
        local dl2 = r.ImGui_GetWindowDrawList(ctx)
        local cx1,cy1 = r.ImGui_GetCursorScreenPos(ctx)
        local cx2,cy2 = cx1 + ctrlBoxW, cy1 + frameH
        if r.ImGui_DrawList_AddRectFilled then r.ImGui_DrawList_AddRectFilled(dl2, cx1,cy1,cx2,cy2, col_u32(0.05,0.05,0.05,0.55), 6) end
        if r.ImGui_DrawList_AddRect then r.ImGui_DrawList_AddRect(dl2, cx1,cy1,cx2,cy2, col_u32(0.9,0.9,0.9,0.30), 6,0,1.2) end
      end
      local innerX, innerY = ctrlX + pad, startY + pad
      if r.ImGui_SetCursorPos then r.ImGui_SetCursorPos(ctx, innerX + (ctrlBoxW - pad*2 - 64)*0.5, innerY) end
      local dstate = get_fx_delta_active(tr, srcCtrlIdx)
      do
        local pushed=0
        if dstate and r.ImGui_PushStyleColor then
          local br,bg,bb=0.20,0.38,0.20; local hr,hg,hb=lighten(br,bg,bb,0.10); local ar,ag,ab=lighten(br,bg,bb,-0.08)
          r.ImGui_PushStyleColor(ctx,r.ImGui_Col_Button(),col_u32(br,bg,bb,1.0)); pushed=pushed+1
          r.ImGui_PushStyleColor(ctx,r.ImGui_Col_ButtonHovered(),col_u32(hr,hg,hb,1.0)); pushed=pushed+1
          r.ImGui_PushStyleColor(ctx,r.ImGui_Col_ButtonActive(),col_u32(ar,ag,ab,1.0)); pushed=pushed+1
        end
        local disabled = (dstate == nil)
        if disabled and r.ImGui_BeginDisabled then r.ImGui_BeginDisabled(ctx) end
        if r.ImGui_Button(ctx,'Delta',64,deltaBtnH) then toggle_fx_delta(tr, srcCtrlIdx) end
        if disabled and r.ImGui_EndDisabled then r.ImGui_EndDisabled(ctx) end
        if pushed>0 and r.ImGui_PopStyleColor then r.ImGui_PopStyleColor(ctx,pushed) end
        if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then r.ImGui_SetTooltip(ctx,'Toggle Delta solo (if plugin supports it)') end
      end
      local knobPosX = innerX + (ctrlBoxW - pad*2 - knobSize)*0.5
      local knobPosY = innerY + deltaBtnH + 2
      if r.ImGui_SetCursorPos then r.ImGui_SetCursorPos(ctx, knobPosX, knobPosY) end
      local mixVal = get_fx_overall_wet(tr, srcCtrlIdx) or 1.0
      local changedOV, newVal = knob_widget('##mix_knob_overlay', mixVal, knobSize)
      if r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip and state.tooltips then r.ImGui_SetTooltip(ctx, ('Overall Wet: %d%% (Double-click=100, Right-click=50)'):format(math.floor(((newVal or mixVal) or 0)*100+0.5))) end
      if r.ImGui_IsItemHovered(ctx) and r.ImGui_IsMouseDoubleClicked and r.ImGui_IsMouseDoubleClicked(ctx,0) then newVal,changedOV=1.0,true end
      if r.ImGui_IsItemClicked and r.ImGui_IsItemClicked(ctx,1) then newVal,changedOV=0.5,true end
      if changedOV then set_fx_overall_wet(tr, srcCtrlIdx, newVal) end
      if r.ImGui_CalcTextSize then
        local pctLabel = ('Wet %d%%'):format(math.floor(((newVal or mixVal))*100+0.5))
        local tw = select(1, r.ImGui_CalcTextSize(ctx, pctLabel)) or 0
        local labelX = innerX + (ctrlBoxW - pad*2 - tw)*0.5
  if r.ImGui_SetCursorPos then r.ImGui_SetCursorPos(ctx, labelX, knobPosY + knobSize + 2) end
        r.ImGui_Text(ctx, pctLabel)
      end
    end
    do
      local afterY = (startY or 0) + frameH + 2
  if r.ImGui_SetCursorPos then r.ImGui_SetCursorPos(ctx, startX or 0, afterY) end
  if r.ImGui_Dummy then r.ImGui_Dummy(ctx, 0, 0) end
    end
  else
    if not state.hideWetControl then
      local pad = 8
      local deltaBtnH, labelH = 18, 16
      local baseImgW = math.max(120, math.min(280, availW - 8))
      local baseImgH = math.floor(baseImgW * 0.56)
      local knobSize = math.floor(math.min(baseImgW, baseImgH) * 0.30); if knobSize < 34 then knobSize = 34 end
      local mixValPreview = get_fx_overall_wet(tr, srcCtrlIdx) or 1.0
      local previewTxt = ('Wet %d%%'):format(math.floor(mixValPreview*100+0.5))
      local labelW = 0; if r.ImGui_CalcTextSize then labelW = select(1, r.ImGui_CalcTextSize(ctx, previewTxt)) or 0 end
      local neededInnerW = math.max(knobSize, 64, labelW)
      local ctrlBoxW = neededInnerW + pad * 2 + 6
      local ctrlBoxH = pad + deltaBtnH + 2 + knobSize + 2 + labelH + pad
      local startX = select(1, r.ImGui_GetCursorPos(ctx)) or 0
      local startY = select(2, r.ImGui_GetCursorPos(ctx)) or 0
      local ctrlX = startX + math.max(0,(availW - ctrlBoxW) * 0.5)
      if r.ImGui_SetCursorPos then r.ImGui_SetCursorPos(ctx, ctrlX, startY) end
      if r.ImGui_GetWindowDrawList then
        local dl = r.ImGui_GetWindowDrawList(ctx)
        local x1,y1 = r.ImGui_GetCursorScreenPos(ctx)
        local x2,y2 = x1 + ctrlBoxW, y1 + ctrlBoxH
        if r.ImGui_DrawList_AddRectFilled then r.ImGui_DrawList_AddRectFilled(dl, x1,y1,x2,y2, col_u32(0.05,0.05,0.05,0.55), 6) end
        if r.ImGui_DrawList_AddRect then r.ImGui_DrawList_AddRect(dl, x1,y1,x2,y2, col_u32(0.9,0.9,0.9,0.30), 6,0,1.2) end
      end
      local innerX, innerY = ctrlX + pad, startY + pad
      if r.ImGui_SetCursorPos then r.ImGui_SetCursorPos(ctx, innerX + (ctrlBoxW - pad*2 - 64)*0.5, innerY) end
      local dstate = get_fx_delta_active(tr, srcCtrlIdx)
      do
        local pushed=0
        if dstate and r.ImGui_PushStyleColor then
          local br,bg,bb=0.20,0.38,0.20; local hr,hg,hb=lighten(br,bg,bb,0.10); local ar,ag,ab=lighten(br,bg,bb,-0.08)
          r.ImGui_PushStyleColor(ctx,r.ImGui_Col_Button(),col_u32(br,bg,bb,1.0)); pushed=pushed+1
          r.ImGui_PushStyleColor(ctx,r.ImGui_Col_ButtonHovered(),col_u32(hr,hg,hb,1.0)); pushed=pushed+1
          r.ImGui_PushStyleColor(ctx,r.ImGui_Col_ButtonActive(),col_u32(ar,ag,ab,1.0)); pushed=pushed+1
        end
        local disabled = (dstate == nil)
        if disabled and r.ImGui_BeginDisabled then r.ImGui_BeginDisabled(ctx) end
        if r.ImGui_Button(ctx,'Delta',64,deltaBtnH) then toggle_fx_delta(tr, srcCtrlIdx) end
        if disabled and r.ImGui_EndDisabled then r.ImGui_EndDisabled(ctx) end
        if pushed>0 and r.ImGui_PopStyleColor then r.ImGui_PopStyleColor(ctx,pushed) end
        if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then r.ImGui_SetTooltip(ctx,'Toggle Delta solo (if plugin supports it)') end
      end
      local knobPosX = innerX + (ctrlBoxW - pad*2 - knobSize)*0.5
      local knobPosY = innerY + deltaBtnH + 2
      if r.ImGui_SetCursorPos then r.ImGui_SetCursorPos(ctx, knobPosX, knobPosY) end
      local mixVal = mixValPreview
      local changedOV, newVal = knob_widget('##mix_knob_centered', mixVal, knobSize)
      if r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip and state.tooltips then r.ImGui_SetTooltip(ctx, ('Overall Wet: %d%% (Double-click=100, Right-click=50)'):format(math.floor(((newVal or mixVal))*100+0.5))) end
      if r.ImGui_IsItemHovered(ctx) and r.ImGui_IsMouseDoubleClicked and r.ImGui_IsMouseDoubleClicked(ctx,0) then newVal,changedOV=1.0,true end
      if r.ImGui_IsItemClicked and r.ImGui_IsItemClicked(ctx,1) then newVal,changedOV=0.5,true end
      if changedOV then set_fx_overall_wet(tr, srcCtrlIdx, newVal) end
      if r.ImGui_CalcTextSize then
        local pctLabel = ('Wet %d%%'):format(math.floor(((newVal or mixVal))*100+0.5))
        local tw = select(1, r.ImGui_CalcTextSize(ctx, pctLabel)) or 0
        local labelX = innerX + (ctrlBoxW - pad*2 - tw)*0.5
        if r.ImGui_SetCursorPos then r.ImGui_SetCursorPos(ctx, labelX, knobPosY + knobSize + 4) end
        r.ImGui_Text(ctx, pctLabel)
      end
  if r.ImGui_SetCursorPos then r.ImGui_SetCursorPos(ctx, startX, startY + ctrlBoxH + 2) end
      if r.ImGui_Dummy then r.ImGui_Dummy(ctx, 0, 0) end
    end
  end
  r.ImGui_Dummy(ctx,0,4)
  local hasSelName = state.selectedSourceFXName and state.selectedSourceFXName ~= ''
  if r.ImGui_Checkbox then
  local changed, val = r.ImGui_Checkbox(ctx, 'Only selected track(s)', state.scopeSelectedOnly or false)
  if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then r.ImGui_SetTooltip(ctx, 'When enabled: operations target only the single selected track context') end
    if changed then state.scopeSelectedOnly = val; save_user_settings() end
  end
  r.ImGui_Dummy(ctx,0,2)
  local fullW = r.ImGui_GetContentRegionAvail(ctx)
  local gap = 6
  local btnW = (fullW - gap*2) / 3
  local dis = (not hasSelName) and r.ImGui_BeginDisabled and r.ImGui_BeginDisabled(ctx)
  local source = state.selectedSourceFXName
  local scopeSel = state.scopeSelectedOnly == true
  if r.ImGui_Button(ctx,'Move up', btnW, 0) then
    if scopeSel then
      local tr = get_selected_track(); local idx = tonumber(state.selectedSourceFXIndex)
      if tr and idx and idx>0 then
        if not swap_fx_via_chunk(tr, idx, idx-1) then
          r.TrackFX_CopyToTrack(tr, idx, tr, idx-1, true)
        end
        state.selectedSourceFXIndex = idx-1; state.pendingMessage='Moved up (selected track).'
      end
    else
      local cnt,msg = move_all_instances_up(source); if cnt>0 then state.pendingMessage=msg else state.pendingError=msg or 'No instances moved up' end
    end
  end
  if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then r.ImGui_SetTooltip(ctx, scopeSel and 'Move this FX one position up on the selected track' or 'Move every matching FX instance up by one slot on all tracks') end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx,'Move down', btnW, 0) then
    if scopeSel then
      local tr = get_selected_track(); local idx = tonumber(state.selectedSourceFXIndex)
  if tr and idx then local fxCount = r.TrackFX_GetCount(tr); if idx < fxCount-1 then if not swap_fx_via_chunk(tr, idx, idx+1) then r.TrackFX_CopyToTrack(tr, idx, tr, idx+1, true) end; state.selectedSourceFXIndex=idx+1; state.pendingMessage='Moved down (selected track).' end end
    else
      local cnt,msg = move_all_instances_down(source); if cnt>0 then state.pendingMessage=msg else state.pendingError=msg or 'No instances moved down' end
    end
  end
  if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then r.ImGui_SetTooltip(ctx, scopeSel and 'Move this FX one position down on the selected track' or 'Move every matching FX instance down by one slot on all tracks') end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx,'Delete', btnW, 0) then
    if scopeSel then
      local tr = get_selected_track(); local idx = tonumber(state.selectedSourceFXIndex)
      if tr and idx then r.TrackFX_Delete(tr, idx); state.pendingMessage='Deleted (selected track)'; state.selectedSourceFXIndex, state.selectedSourceFXName=nil,nil end
    else
      local cnt = select(1, delete_all_instances(source, nil, nil)); state.pendingMessage=string.format('%d instances deleted (all tracks).', cnt); state.selectedSourceFXIndex, state.selectedSourceFXName=nil,nil
    end
  end
  if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then r.ImGui_SetTooltip(ctx, scopeSel and 'Delete this FX from the selected track' or 'Delete every matching FX instance from all tracks') end
  if dis and r.ImGui_EndDisabled then r.ImGui_EndDisabled(ctx) end
  r.ImGui_Dummy(ctx,0,4)
  r.ImGui_Separator(ctx)
end

local function draw_source_controls_inline()
  if state.showPanelSource == false then return end
  local tr = get_selected_track()
  local srcIdx = tonumber(state.selectedSourceFXIndex)
  if not (tr and srcIdx) then r.ImGui_Text(ctx, 'Pick a Source'); return end
  if state.abSlotIndex and state.abSlotIndex ~= srcIdx then
    if state.abActiveIsRepl then ab_cancel() else state.abSlotIndex, state.abSnap, state.abActiveIsRepl = nil, nil, false end
  end
  local srcCtrlIdx = srcIdx
  local sname = state.selectedSourceFXName
  if not sname or sname == '' then local _, nm = r.TrackFX_GetFXName(tr, srcIdx, ''); sname = nm end
  local disp = format_fx_display_name(sname)
  do
    local label = tostring(disp or '')
    local availW = select(1, r.ImGui_GetContentRegionAvail(ctx)) or 0
    local textW = 0
    if r.ImGui_CalcTextSize then textW = select(1,r.ImGui_CalcTextSize(ctx,label)) or 0 end
    local padX = math.max(0,(availW - textW)*0.5)
    local curX = select(1,r.ImGui_GetCursorPos(ctx)) or 0
    if r.ImGui_GetWindowDrawList then
      local dl = r.ImGui_GetWindowDrawList(ctx)
      if dl and r.ImGui_GetCursorScreenPos then
        local startX, startY = r.ImGui_GetCursorScreenPos(ctx)
        local bgX1 = startX
        local bgY1 = startY
        local bgX2 = startX + availW
        local lineH = (r.ImGui_GetTextLineHeightWithSpacing and r.ImGui_GetTextLineHeightWithSpacing(ctx)) or (r.ImGui_GetTextLineHeight and r.ImGui_GetTextLineHeight(ctx)) or 18
        local bgY2 = bgY1 + lineH
        local selCol = col_u32(0.24,0.38,0.55,0.90)
        if r.ImGui_DrawList_AddRectFilled then
          r.ImGui_DrawList_AddRectFilled(dl, bgX1, bgY1, bgX2, bgY2, selCol, 4)
        end
      end
    end
    r.ImGui_SetCursorPosX(ctx, curX + padX)
    r.ImGui_Text(ctx, label)
  end
  r.ImGui_Dummy(ctx,0,2)

  local availW = select(1, r.ImGui_GetContentRegionAvail(ctx)) or 0
  if state.showScreenshot then
    local _, addname = r.TrackFX_GetFXName(tr, srcCtrlIdx, '')
    validate_screenshot_ptr()
    if state.screenshotNeedsRefresh or state.screenshotKey ~= addname or not state.screenshotTex then
      state.screenshotNeedsRefresh = true
      ensure_source_screenshot(addname)
    end
    local maxW = math.max(120, math.min(280, availW - 8))
    local imgW, imgH = maxW, math.floor(maxW * 0.56)
    local pad, spacing = 8, 8
    local knobSize = math.floor(math.min(imgW, imgH) * 0.30); if knobSize < 34 then knobSize = 34 end
    local deltaBtnH, labelH = 18, 16
    local mixValPreview = get_fx_overall_wet(tr, srcCtrlIdx) or 1.0
    local previewTxt = ('Wet %d%%'):format(math.floor(mixValPreview*100+0.5))
    local labelW = 0; if r.ImGui_CalcTextSize then labelW = select(1, r.ImGui_CalcTextSize(ctx, previewTxt)) or 0 end
    local neededInnerW = math.max(knobSize, 64, labelW)
    local ctrlBoxW = neededInnerW + pad * 2 + 6
    local ctrlBoxH = pad + deltaBtnH + 2 + knobSize + 2 + labelH + pad
    local imgBoxW = imgW + pad * 2
    local imgBoxH = imgH + pad * 2
    local frameH = math.max(imgBoxH, ctrlBoxH)
    local totalW = imgBoxW + spacing + ctrlBoxW
    if not state.hideWetControl and imgBoxH > ctrlBoxH * 1.35 then
      local desiredImgH = math.max(ctrlBoxH - pad * 2, 40)
      local scale = desiredImgH / imgH
      if scale < 1.0 then
        imgW = math.max(80, math.floor(imgW * scale))
        imgH = math.floor(imgH * scale)
        imgBoxW = imgW + pad * 2
        imgBoxH = imgH + pad * 2
        frameH = math.max(imgBoxH, ctrlBoxH)
      end
    end
    if totalW > availW - 4 then
      local maxImgAllowed = math.max(80, (availW - ctrlBoxW - spacing - pad * 2))
      if maxImgAllowed < imgW then
        imgW = maxImgAllowed; imgH = math.floor(imgW * 0.56)
        imgBoxW = imgW + pad * 2; imgBoxH = imgH + pad * 2
        frameH = math.max(imgBoxH, ctrlBoxH)
        totalW = imgBoxW + spacing + ctrlBoxW
      end
    end
    local startX = select(1, r.ImGui_GetCursorPos(ctx)) or 0
    local startY = select(2, r.ImGui_GetCursorPos(ctx)) or 0
    totalW = imgBoxW + spacing + ctrlBoxW
    state.lastSourceBlockWidth = totalW 
    if totalW < 0 then totalW = 0 end
    local offset
    if totalW >= availW then offset = 0 else offset = math.floor((availW - totalW) * 0.5 + 0.5) end
    local imgX = startX + offset
    local ctrlX = imgX + imgBoxW + spacing
    if state.hideWetControl then
      local frameH2 = imgBoxH
      imgX = startX + math.max(0,(availW - imgBoxW) * 0.5)
      if r.ImGui_SetCursorPos then r.ImGui_SetCursorPos(ctx, imgX, startY) end
      if r.ImGui_GetWindowDrawList then
        local dl = r.ImGui_GetWindowDrawList(ctx)
        local x1,y1 = r.ImGui_GetCursorScreenPos(ctx)
        local x2,y2 = x1 + imgBoxW, y1 + frameH2
        if r.ImGui_DrawList_AddRectFilled then r.ImGui_DrawList_AddRectFilled(dl, x1,y1,x2,y2, col_u32(0.05,0.05,0.05,0.45), 6) end
        if r.ImGui_DrawList_AddRect then r.ImGui_DrawList_AddRect(dl, x1,y1,x2,y2, col_u32(0.8,0.8,0.8,0.25), 6,0,1.1) end
      end
      if r.ImGui_SetCursorPos then r.ImGui_SetCursorPos(ctx, imgX + pad, startY + pad) end
      if state.deferScreenshotDraw and state.deferScreenshotDraw > 0 then
        state.deferScreenshotDraw = state.deferScreenshotDraw - 1
        local placeholder = 'Loading...'
        local tw,th = 0,0
        if r.ImGui_CalcTextSize then tw,th = r.ImGui_CalcTextSize(ctx, placeholder) end
        local offX = (imgW - tw) * 0.5
        local offY = (imgH - th) * 0.5
        r.ImGui_SetCursorPos(ctx, imgX + pad + offX, startY + pad + offY)
        r.ImGui_TextDisabled(ctx, placeholder)
      elseif state.screenshotTex and type(state.screenshotTex)=='userdata' then
        local ok = pcall(function() if r.ImGui_Image then r.ImGui_Image(ctx, state.screenshotTex, imgW, imgH) end end)
        if not ok then release_screenshot() end
      else
        local placeholder = 'No Image'
        local tw,th = 0,0
        if r.ImGui_CalcTextSize then tw,th = r.ImGui_CalcTextSize(ctx, placeholder) end
        local offX = (imgW - tw) * 0.5
        local offY = (imgH - th) * 0.5
        r.ImGui_SetCursorPos(ctx, imgX + pad + offX, startY + pad + offY)
        r.ImGui_TextDisabled(ctx, placeholder)
      end
      if r.ImGui_SetCursorPos then r.ImGui_SetCursorPos(ctx, startX, startY + frameH2 + 6) end
      if r.ImGui_Dummy then r.ImGui_Dummy(ctx, 0, 0) end
    else
      if r.ImGui_SetCursorPos then r.ImGui_SetCursorPos(ctx, imgX, startY) end
      if r.ImGui_GetWindowDrawList then
        local dl = r.ImGui_GetWindowDrawList(ctx)
        local x1,y1 = r.ImGui_GetCursorScreenPos(ctx)
        local x2,y2 = x1 + imgBoxW, y1 + frameH
        if r.ImGui_DrawList_AddRectFilled then r.ImGui_DrawList_AddRectFilled(dl, x1,y1,x2,y2, col_u32(0.05,0.05,0.05,0.45), 6) end
        if r.ImGui_DrawList_AddRect then r.ImGui_DrawList_AddRect(dl, x1,y1,x2,y2, col_u32(0.8,0.8,0.8,0.25), 6,0,1.1) end
      end
      if r.ImGui_SetCursorPos then r.ImGui_SetCursorPos(ctx, imgX + pad, startY + pad) end
      if state.deferScreenshotDraw and state.deferScreenshotDraw > 0 then
        state.deferScreenshotDraw = state.deferScreenshotDraw - 1
        local placeholder = 'Loading...'
        local tw,th = 0,0
        if r.ImGui_CalcTextSize then tw,th = r.ImGui_CalcTextSize(ctx, placeholder) end
        local offX = (imgW - tw) * 0.5
        local offY = (imgH - th) * 0.5
        r.ImGui_SetCursorPos(ctx, imgX + pad + offX, startY + pad + offY)
        r.ImGui_TextDisabled(ctx, placeholder)
      elseif state.screenshotTex and type(state.screenshotTex)=='userdata' then
        local ok = pcall(function() if r.ImGui_Image then r.ImGui_Image(ctx, state.screenshotTex, imgW, imgH) end end)
        if not ok then release_screenshot() end
      else
        local placeholder = 'No Image'
        local tw,th = 0,0
        if r.ImGui_CalcTextSize then tw,th = r.ImGui_CalcTextSize(ctx, placeholder) end
        local offX = (imgW - tw) * 0.5
        local offY = (imgH - th) * 0.5
        r.ImGui_SetCursorPos(ctx, imgX + pad + offX, startY + pad + offY)
        r.ImGui_TextDisabled(ctx, placeholder)
      end
      if r.ImGui_SetCursorPos then r.ImGui_SetCursorPos(ctx, ctrlX, startY) end
      if r.ImGui_GetWindowDrawList then
        local dl2 = r.ImGui_GetWindowDrawList(ctx)
        local cx1,cy1 = r.ImGui_GetCursorScreenPos(ctx)
        local cx2,cy2 = cx1 + ctrlBoxW, cy1 + frameH
        if r.ImGui_DrawList_AddRectFilled then r.ImGui_DrawList_AddRectFilled(dl2, cx1,cy1,cx2,cy2, col_u32(0.05,0.05,0.05,0.55), 6) end
        if r.ImGui_DrawList_AddRect then r.ImGui_DrawList_AddRect(dl2, cx1,cy1,cx2,cy2, col_u32(0.9,0.9,0.9,0.30), 6,0,1.2) end
      end
      local innerX, innerY = ctrlX + pad, startY + pad
      if r.ImGui_SetCursorPos then r.ImGui_SetCursorPos(ctx, innerX + (ctrlBoxW - pad*2 - 64)*0.5, innerY) end
      local dstate = get_fx_delta_active(tr, srcCtrlIdx)
      do
        local pushed=0
        if dstate and r.ImGui_PushStyleColor then
          local br,bg,bb=0.20,0.38,0.20; local hr,hg,hb=lighten(br,bg,bb,0.10); local ar,ag,ab=lighten(br,bg,bb,-0.08)
          r.ImGui_PushStyleColor(ctx,r.ImGui_Col_Button(),col_u32(br,bg,bb,1.0)); pushed=pushed+1
          r.ImGui_PushStyleColor(ctx,r.ImGui_Col_ButtonHovered(),col_u32(hr,hg,hb,1.0)); pushed=pushed+1
          r.ImGui_PushStyleColor(ctx,r.ImGui_Col_ButtonActive(),col_u32(ar,ag,ab,1.0)); pushed=pushed+1
        end
        local disabled = (dstate == nil)
        if disabled and r.ImGui_BeginDisabled then r.ImGui_BeginDisabled(ctx) end
        if r.ImGui_Button(ctx,'Delta',64,deltaBtnH) then toggle_fx_delta(tr, srcCtrlIdx) end
        if disabled and r.ImGui_EndDisabled then r.ImGui_EndDisabled(ctx) end
        if pushed>0 and r.ImGui_PopStyleColor then r.ImGui_PopStyleColor(ctx,pushed) end
        if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then r.ImGui_SetTooltip(ctx,'Toggle Delta solo (if plugin supports it)') end
      end
      local knobPosX = innerX + (ctrlBoxW - pad*2 - knobSize)*0.5
      local knobPosY = innerY + deltaBtnH + 2
      if r.ImGui_SetCursorPos then r.ImGui_SetCursorPos(ctx, knobPosX, knobPosY) end
      local mixVal = get_fx_overall_wet(tr, srcCtrlIdx) or 1.0
      local changedOV, newVal = knob_widget('##mix_knob_overlay_inline', mixVal, knobSize)
      if r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip and state.tooltips then r.ImGui_SetTooltip(ctx, ('Overall Wet: %d%% (Double-click=100, Right-click=50)'):format(math.floor(((newVal or mixVal) or 0)*100+0.5))) end
      if r.ImGui_IsItemHovered(ctx) and r.ImGui_IsMouseDoubleClicked and r.ImGui_IsMouseDoubleClicked(ctx,0) then newVal,changedOV=1.0,true end
      if r.ImGui_IsItemClicked and r.ImGui_IsItemClicked(ctx,1) then newVal,changedOV=0.5,true end
      if changedOV then set_fx_overall_wet(tr, srcCtrlIdx, newVal) end
      if r.ImGui_CalcTextSize then
        local pctLabel = ('Wet %d%%'):format(math.floor(((newVal or mixVal))*100+0.5))
        local tw = select(1, r.ImGui_CalcTextSize(ctx, pctLabel)) or 0
        local labelX = innerX + (ctrlBoxW - pad*2 - tw)*0.5
        if r.ImGui_SetCursorPos then r.ImGui_SetCursorPos(ctx, labelX, knobPosY + knobSize + 2) end
        r.ImGui_Text(ctx, pctLabel)
      end
    end
    do
      local afterY = (startY or 0) + frameH + 2
      if r.ImGui_SetCursorPos then r.ImGui_SetCursorPos(ctx, startX or 0, afterY) end
      if r.ImGui_Dummy then r.ImGui_Dummy(ctx, 0, 0) end
    end
  else
    if not state.hideWetControl then
      local pad = 8
      local deltaBtnH, labelH = 18, 16
      local baseImgW = math.max(120, math.min(280, availW - 8))
      local baseImgH = math.floor(baseImgW * 0.56)
      local knobSize = math.floor(math.min(baseImgW, baseImgH) * 0.30); if knobSize < 34 then knobSize = 34 end
      local mixValPreview = get_fx_overall_wet(tr, srcCtrlIdx) or 1.0
      local previewTxt = ('Wet %d%%'):format(math.floor(mixValPreview*100+0.5))
      local labelW = 0; if r.ImGui_CalcTextSize then labelW = select(1, r.ImGui_CalcTextSize(ctx, previewTxt)) or 0 end
      local neededInnerW = math.max(knobSize, 64, labelW)
      local ctrlBoxW = neededInnerW + pad * 2 + 6
      local ctrlBoxH = pad + deltaBtnH + 2 + knobSize + 2 + labelH + pad
      local startX = select(1, r.ImGui_GetCursorPos(ctx)) or 0
      local startY = select(2, r.ImGui_GetCursorPos(ctx)) or 0
      local ctrlX = startX + math.max(0,(availW - ctrlBoxW) * 0.5)
      if r.ImGui_SetCursorPos then r.ImGui_SetCursorPos(ctx, ctrlX, startY) end
      if r.ImGui_GetWindowDrawList then
        local dl = r.ImGui_GetWindowDrawList(ctx)
        local x1,y1 = r.ImGui_GetCursorScreenPos(ctx)
        local x2,y2 = x1 + ctrlBoxW, y1 + ctrlBoxH
        if r.ImGui_DrawList_AddRectFilled then r.ImGui_DrawList_AddRectFilled(dl, x1,y1,x2,y2, col_u32(0.05,0.05,0.05,0.55), 6) end
        if r.ImGui_DrawList_AddRect then r.ImGui_DrawList_AddRect(dl, x1,y1,x2,y2, col_u32(0.9,0.9,0.9,0.30), 6,0,1.2) end
      end
      local innerX, innerY = ctrlX + pad, startY + pad
      if r.ImGui_SetCursorPos then r.ImGui_SetCursorPos(ctx, innerX + (ctrlBoxW - pad*2 - 64)*0.5, innerY) end
      local dstate = get_fx_delta_active(tr, srcCtrlIdx)
      do
        local pushed=0
        if dstate and r.ImGui_PushStyleColor then
          local br,bg,bb=0.20,0.38,0.20; local hr,hg,hb=lighten(br,bg,bb,0.10); local ar,ag,ab=lighten(br,bg,bb,-0.08)
          r.ImGui_PushStyleColor(ctx,r.ImGui_Col_Button(),col_u32(br,bg,bb,1.0)); pushed=pushed+1
          r.ImGui_PushStyleColor(ctx,r.ImGui_Col_ButtonHovered(),col_u32(hr,hg,hb,1.0)); pushed=pushed+1
          r.ImGui_PushStyleColor(ctx,r.ImGui_Col_ButtonActive(),col_u32(ar,ag,ab,1.0)); pushed=pushed+1
        end
        local disabled = (dstate == nil)
        if disabled and r.ImGui_BeginDisabled then r.ImGui_BeginDisabled(ctx) end
        if r.ImGui_Button(ctx,'Delta',64,deltaBtnH) then toggle_fx_delta(tr, srcCtrlIdx) end
        if disabled and r.ImGui_EndDisabled then r.ImGui_EndDisabled(ctx) end
        if pushed>0 and r.ImGui_PopStyleColor then r.ImGui_PopStyleColor(ctx,pushed) end
        if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then r.ImGui_SetTooltip(ctx,'Toggle Delta solo (if plugin supports it)') end
      end
      local knobPosX = innerX + (ctrlBoxW - pad*2 - knobSize)*0.5
      local knobPosY = innerY + deltaBtnH + 2
      if r.ImGui_SetCursorPos then r.ImGui_SetCursorPos(ctx, knobPosX, knobPosY) end
      local mixVal = mixValPreview
      local changedOV, newVal = knob_widget('##mix_knob_centered_inline', mixVal, knobSize)
      if r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip and state.tooltips then r.ImGui_SetTooltip(ctx, ('Overall Wet: %d%% (Double-click=100, Right-click=50)'):format(math.floor(((newVal or mixVal))*100+0.5))) end
      if r.ImGui_IsItemHovered(ctx) and r.ImGui_IsMouseDoubleClicked and r.ImGui_IsMouseDoubleClicked(ctx,0) then newVal,changedOV=1.0,true end
      if r.ImGui_IsItemClicked and r.ImGui_IsItemClicked(ctx,1) then newVal,changedOV=0.5,true end
      if changedOV then set_fx_overall_wet(tr, srcCtrlIdx, newVal) end
      if r.ImGui_CalcTextSize then
        local pctLabel = ('Wet %d%%'):format(math.floor(((newVal or mixVal))*100+0.5))
        local tw = select(1, r.ImGui_CalcTextSize(ctx, pctLabel)) or 0
        local labelX = innerX + (ctrlBoxW - pad*2 - tw)*0.5
        if r.ImGui_SetCursorPos then r.ImGui_SetCursorPos(ctx, labelX, knobPosY + knobSize + 4) end
        r.ImGui_Text(ctx, pctLabel)
      end
      if r.ImGui_SetCursorPos then r.ImGui_SetCursorPos(ctx, startX, startY + ctrlBoxH + 2) end
      if r.ImGui_Dummy then r.ImGui_Dummy(ctx, 0, 0) end
    end
  end
  r.ImGui_Dummy(ctx,0,4)
  local hasSelName = state.selectedSourceFXName and state.selectedSourceFXName ~= ''
  if r.ImGui_Checkbox then
    local changed, val = r.ImGui_Checkbox(ctx, 'Only selected track(s)', state.scopeSelectedOnly or false)
    if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then r.ImGui_SetTooltip(ctx, 'When enabled: operations target only the single selected track context') end
    if changed then state.scopeSelectedOnly = val; save_user_settings() end
  end
  r.ImGui_Dummy(ctx,0,2)
  local fullW = r.ImGui_GetContentRegionAvail(ctx)
  local gap = 6
  local btnW = (fullW - gap*2) / 3
  local dis = (not hasSelName) and r.ImGui_BeginDisabled and r.ImGui_BeginDisabled(ctx)
  local source = state.selectedSourceFXName
  local scopeSel = state.scopeSelectedOnly == true
  if r.ImGui_Button(ctx,'Move up', btnW, 0) then
    if scopeSel then
      local trk = get_selected_track(); local idx = tonumber(state.selectedSourceFXIndex)
      if trk and idx and idx>0 then
        if not swap_fx_via_chunk(trk, idx, idx-1) then
          r.TrackFX_CopyToTrack(trk, idx, trk, idx-1, true)
        end
        state.selectedSourceFXIndex = idx-1; state.pendingMessage='Moved up (selected track).'
      end
    else
      local cnt,msg = move_all_instances_up(source); if cnt>0 then state.pendingMessage=msg else state.pendingError=msg or 'No instances moved up' end
    end
  end
  if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then r.ImGui_SetTooltip(ctx, scopeSel and 'Move this FX one position up on the selected track' or 'Move every matching FX instance up by one slot on all tracks') end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx,'Move down', btnW, 0) then
    if scopeSel then
      local trk = get_selected_track(); local idx = tonumber(state.selectedSourceFXIndex)
      if trk and idx then local fxCount = r.TrackFX_GetCount(trk); if idx < fxCount-1 then if not swap_fx_via_chunk(trk, idx, idx+1) then r.TrackFX_CopyToTrack(trk, idx, trk, idx+1, true) end; state.selectedSourceFXIndex=idx+1; state.pendingMessage='Moved down (selected track).' end end
    else
      local cnt,msg = move_all_instances_down(source); if cnt>0 then state.pendingMessage=msg else state.pendingError=msg or 'No instances moved down' end
    end
  end
  if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then r.ImGui_SetTooltip(ctx, scopeSel and 'Move this FX one position down on the selected track' or 'Move every matching FX instance down by one slot on all tracks') end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx,'Delete', btnW, 0) then
    if scopeSel then
      local trk = get_selected_track(); local idx = tonumber(state.selectedSourceFXIndex)
      if trk and idx then r.TrackFX_Delete(trk, idx); state.pendingMessage='Deleted (selected track)'; state.selectedSourceFXIndex, state.selectedSourceFXName=nil,nil end
    else
      local cnt = select(1, delete_all_instances(source, nil, nil)); state.pendingMessage=string.format('%d instances deleted (all tracks).', cnt); state.selectedSourceFXIndex, state.selectedSourceFXName=nil,nil
    end
  end
  if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then r.ImGui_SetTooltip(ctx, scopeSel and 'Delete this FX from the selected track' or 'Delete every matching FX instance from all tracks') end
  if dis and r.ImGui_EndDisabled then r.ImGui_EndDisabled(ctx) end
  r.ImGui_Dummy(ctx,0,4)
  r.ImGui_Separator(ctx)
end

local function draw_fxchain_panel()
  if state.showPanelFXChain == false then return end
  local tr = get_selected_track()
  local openFxC = r.ImGui_CollapsingHeader(ctx, 'FXChain:', 0)
  if openFxC ~= nil and openFxC ~= state.fxChainHeaderOpen then state.fxChainHeaderOpen = openFxC; save_user_settings() end
  if not (openFxC and tr) then
    if openFxC and not tr then r.ImGui_TextDisabled(ctx,'Select a track to use FX Chain controls') end
    return
  end
  local sws_available = is_sws_available()
  if not sws_available then
    r.ImGui_TextColored(ctx,1.0,0.5,0.0,1.0,'SWS extension required for FX Chain operations')
    r.ImGui_TextDisabled(ctx,'Please install SWS/S&M extension from sws-extension.org')
    return
  end
  local fx_count = r.TrackFX_GetCount(tr) or 0
  local track_name = get_track_name(tr)
  if r.ImGui_Button(ctx, 'Save FX Chain', -1, 0) then
    local success, msg = create_fx_chain(tr)
    if success then state.pendingMessage = msg; refresh_fx_chains_list(true) else state.pendingError = msg end
  end
  if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then
    r.ImGui_SetTooltip(ctx, string.format('Save all FX from: %s (%d FX) as a new FX Chain', track_name, fx_count))
  end
  r.ImGui_Dummy(ctx,0,4); 
  r.ImGui_Text(ctx,'Load FX Chain:')
  if not state.fxChains then refresh_fx_chains_list() end
  local chain_count = state.fxChains and #state.fxChains or 0
  r.ImGui_SameLine(ctx)
  local status_text = string.format('Found %d chains', chain_count)
  if state.fxChainsFromCache then status_text = status_text .. ' (cached)' end
  r.ImGui_TextDisabled(ctx,status_text)
  local button_width = (r.ImGui_GetContentRegionAvail(ctx) - 4) * 0.3
  if r.ImGui_Button(ctx, 'Refresh', button_width, 0) then refresh_fx_chains_list(true); state.pendingMessage='FX Chains list refreshed from disk' end
  if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then r.ImGui_SetTooltip(ctx,'Force refresh FX chains list from disk (cached otherwise)') end
  r.ImGui_SameLine(ctx)
  r.ImGui_SetNextItemWidth(ctx,-1)
  local changedFilter, new_filter = r.ImGui_InputText(ctx,'##fxchain_filter', state.fxChainFilter)
  if changedFilter then state.fxChainFilter = new_filter end
  if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then r.ImGui_SetTooltip(ctx,'Filter FX chains by name') end
  r.ImGui_Dummy(ctx,0,2)
  if r.ImGui_BeginChild(ctx,'##fxchains_list', -1, state.fxChainListHeight or 140) then
    if state.fxChains and #state.fxChains > 0 then
      local filter = state.fxChainFilter:lower()
      for i, chain in ipairs(state.fxChains) do
        local show_chain = filter == '' or chain.display_name:lower():find(filter,1,true)
        if show_chain then
          local selected = state.selectedFxChain == chain.path
            if r.ImGui_Selectable(ctx, chain.display_name, selected) then state.selectedFxChain = chain.path end
            if r.ImGui_IsItemClicked(ctx,1) then r.ImGui_OpenPopup(ctx,'FXChainContext_'..i) end
            if r.ImGui_BeginPopup(ctx,'FXChainContext_'..i) then
              if r.ImGui_MenuItem(ctx,'Load (Add to existing)') then local success,msg=load_fx_chain(tr, chain.path,false); if success then state.pendingMessage=msg else state.pendingError=msg end end
              if r.ImGui_MenuItem(ctx,'Load (Replace all FX)') then local success,msg=load_fx_chain(tr, chain.path,true); if success then state.pendingMessage=msg else state.pendingError=msg end end
              r.ImGui_Separator(ctx)
              if r.ImGui_MenuItem(ctx,'Rename Chain') then
                local retval,new_name = r.GetUserInputs('Rename FX Chain',1,'New name:', chain.name)
                if retval and new_name ~= '' and new_name ~= chain.name then
                  local success,msg = rename_fx_chain(chain.path,new_name)
                  if success then state.pendingMessage=msg; refresh_fx_chains_list(true); state.selectedFxChain=nil else state.pendingError=msg end
                end
              end
              if r.ImGui_MenuItem(ctx,'Delete Chain') then
                local success,msg = delete_fx_chain(chain.path)
                if success then state.pendingMessage=msg; refresh_fx_chains_list(true) else state.pendingError=msg end
              end
              r.ImGui_EndPopup(ctx)
            end
        end
      end
    else
      r.ImGui_TextDisabled(ctx,'No FX chains found')
      r.ImGui_TextDisabled(ctx,'Save some FX chains to see them here')
    end
    r.ImGui_EndChild(ctx)
  end
  do
    local splitterHeight = 6
    local availW = select(1, r.ImGui_GetContentRegionAvail(ctx)) or -1
    if r.ImGui_InvisibleButton then
      r.ImGui_InvisibleButton(ctx, '##fxChainListResize', availW, splitterHeight)
      local hovered = r.ImGui_IsItemHovered(ctx)
      local active = r.ImGui_IsItemActive(ctx)
      if hovered and r.ImGui_SetMouseCursor and r.ImGui_MouseCursor_ResizeNS then
        pcall(function() r.ImGui_SetMouseCursor(ctx, r.ImGui_MouseCursor_ResizeNS()) end)
      end
      if state.tooltips and hovered and r.ImGui_SetTooltip then r.ImGui_SetTooltip(ctx, 'Sleep om de FX chain lijst hoogte aan te passen') end
      if active and r.ImGui_IsMouseDragging and r.ImGui_IsMouseDragging(ctx,0) then
        local dragDy = select(2, r.ImGui_GetMouseDragDelta(ctx,0)) or 0
        local newH = (state.fxChainListHeight or 140) + dragDy
        newH = math.max(60, math.min(500, newH))
        if newH ~= state.fxChainListHeight then
          state.fxChainListHeight = newH
          r.ImGui_ResetMouseDragDelta(ctx,0)
          save_user_settings()
        end
      end
      if r.ImGui_GetItemRectMin and r.ImGui_GetItemRectMax and r.ImGui_DrawList_AddRectFilled then
        local minx, miny = r.ImGui_GetItemRectMin(ctx)
        local maxx, maxy = r.ImGui_GetItemRectMax(ctx)
        local dl = r.ImGui_GetWindowDrawList(ctx)
        if dl then
          local hovered = r.ImGui_IsItemHovered(ctx)
          local active = r.ImGui_IsItemActive(ctx)
          local baseCol = col_u32(0.55,0.55,0.55,0.35)
          if hovered then baseCol = col_u32(0.80,0.80,0.80,0.55) end
          if active then baseCol = col_u32(0.32,0.60,0.95,0.85) end
          r.ImGui_DrawList_AddRectFilled(dl, minx, miny, maxx, maxy, baseCol, 2)
          local midY = (miny + maxy) * 0.5
          local centerX = (minx + maxx) * 0.5
          local dotCol = col_u32(0.15,0.15,0.15, active and 1.0 or (hovered and 0.9 or 0.6))
          if r.ImGui_DrawList_AddCircleFilled then
            local spacing = 6
            r.ImGui_DrawList_AddCircleFilled(dl, centerX - spacing, midY, 2, dotCol)
            r.ImGui_DrawList_AddCircleFilled(dl, centerX,          midY, 2, dotCol)
            r.ImGui_DrawList_AddCircleFilled(dl, centerX + spacing, midY, 2, dotCol)
          end
        end
      end
    end
  end
  r.ImGui_Dummy(ctx,0,4)
  if state.selectedFxChain then
    r.ImGui_Text(ctx,'Load to:')
    local changedC, new_current = r.ImGui_Checkbox(ctx,'Current', state.fxChainLoadToCurrent)
    if changedC then state.fxChainLoadToCurrent = new_current; if new_current then state.fxChainLoadToSelected=false; state.fxChainLoadToAll=false end end
    r.ImGui_SameLine(ctx)
    local changedS, new_selected = r.ImGui_Checkbox(ctx,'Selected', state.fxChainLoadToSelected)
    if changedS then state.fxChainLoadToSelected = new_selected; if new_selected then state.fxChainLoadToCurrent=false; state.fxChainLoadToAll=false end end
    r.ImGui_SameLine(ctx)
    local changedA, new_all = r.ImGui_Checkbox(ctx,'All', state.fxChainLoadToAll)
    if changedA then state.fxChainLoadToAll = new_all; if new_all then state.fxChainLoadToCurrent=false; state.fxChainLoadToSelected=false end end
    local any_target_selected = state.fxChainLoadToCurrent or state.fxChainLoadToSelected or state.fxChainLoadToAll
    if not any_target_selected then
      r.ImGui_TextColored(ctx,1.0,0.5,0.0,1.0,'Select a target (Current/Selected/All)')
    else
      r.ImGui_Dummy(ctx,0,4)
      local bw = (r.ImGui_GetContentRegionAvail(ctx) - 4) * 0.5
      if r.ImGui_Button(ctx,'Add', bw,0) then
        if not state.selectedFxChain or state.selectedFxChain == '' then state.pendingError='No FX chain selected' else
          local success,msg=false,''
          if state.fxChainLoadToCurrent then success,msg=load_fx_chain(tr,state.selectedFxChain,false)
          elseif state.fxChainLoadToSelected then local count; count,msg=load_fx_chain_to_selected_tracks(state.selectedFxChain,false); success = count>0
          elseif state.fxChainLoadToAll then local track_count=r.CountTracks(0); local result=r.MB(string.format('Add FX chain to ALL %d tracks?',track_count),'Confirm Add to All',4); if result==6 then local count; count,msg=load_fx_chain_to_all_tracks(state.selectedFxChain,false); success=count>0 else msg='Add to all tracks cancelled' end end
          if success then state.pendingMessage=msg else state.pendingError=msg end
        end
      end
      if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then
        local target = state.fxChainLoadToCurrent and 'current track' or state.fxChainLoadToSelected and 'selected tracks' or state.fxChainLoadToAll and 'all tracks' or 'target'
        r.ImGui_SetTooltip(ctx,string.format('Add FX chain to %s (keeps existing FX)', target))
      end
      r.ImGui_SameLine(ctx)
      if r.ImGui_Button(ctx,'Replace!', bw,0) then
        if not state.selectedFxChain or state.selectedFxChain == '' then state.pendingError='No FX chain selected' else
          local confirm_msg=''
          local track_count=0
          if state.fxChainLoadToCurrent then confirm_msg='Replace ALL existing FX on current track?'; track_count=1
          elseif state.fxChainLoadToSelected then track_count=r.CountSelectedTracks(0); if track_count==0 then state.pendingError='No tracks selected' else confirm_msg=string.format('Replace ALL FX on %d selected track(s)?',track_count) end
          elseif state.fxChainLoadToAll then track_count=r.CountTracks(0); confirm_msg=string.format('Replace ALL FX on ALL %d tracks?\n\nPERMANENT deletion of existing FX!',track_count) end
          local result = r.MB(confirm_msg,'Confirm Replace',4)
          if result==6 then
            local success,msg=false,''
            if state.fxChainLoadToCurrent then success,msg=load_fx_chain(tr,state.selectedFxChain,true)
            elseif state.fxChainLoadToSelected then local count; count,msg=load_fx_chain_to_selected_tracks(state.selectedFxChain,true); success=count>0
            elseif state.fxChainLoadToAll then local count; count,msg=load_fx_chain_to_all_tracks(state.selectedFxChain,true); success=count>0 end
            if success then state.pendingMessage=msg else state.pendingError=msg end
          end
        end
      end
      if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then
        local target = state.fxChainLoadToCurrent and 'current track' or state.fxChainLoadToSelected and 'selected tracks' or state.fxChainLoadToAll and 'all tracks' or 'target'
        r.ImGui_SetTooltip(ctx,string.format('Replace ALL FX on %s (DANGER!)', target))
      end
    end
  end
  r.ImGui_Dummy(ctx,0,8); r.ImGui_Separator(ctx); 
  local fx_count2 = r.TrackFX_GetCount(tr) or 0
  if r.ImGui_Button(ctx,'Copy FX from current track', -1,0) then
    if fx_count2 > 0 then local success,msg = copy_fx_chain_from_track(tr); if success then state.pendingMessage=msg else state.pendingError=msg end else state.pendingError='Current track has no FX to copy' end
  end
  if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then r.ImGui_SetTooltip(ctx,string.format('Copy all FX from: %s (%d FX)', track_name, fx_count2)) end
  r.ImGui_Dummy(ctx,0,2)
  local has_copied_chain = copied_fx_chain_info ~= nil
  if has_copied_chain then
    local age_minutes = math.floor((os.time() - copied_fx_chain_info.timestamp) / 60)
    r.ImGui_TextDisabled(ctx, string.format('%s (%d FX, %dm ago)', copied_fx_chain_info.source_track_name, copied_fx_chain_info.fx_count, age_minutes))
  else
    r.ImGui_TextDisabled(ctx,'No FX chain copied yet')
  end
  if not has_copied_chain and r.ImGui_BeginDisabled then r.ImGui_BeginDisabled(ctx) end
  local bw2 = (r.ImGui_GetContentRegionAvail(ctx) - 4) * 0.5
  if r.ImGui_Button(ctx,'Add to selected', bw2,0) then local count,msg=paste_fx_chain_to_selected_tracks(); if count>0 then state.pendingMessage=msg else state.pendingError=msg or 'Failed to add to selected tracks' end end
  if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then r.ImGui_SetTooltip(ctx,'Add FX to selected tracks (keeps existing)') end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx,'Replace selected', bw2,0) then
    local selected_count = r.CountSelectedTracks(0)
    if selected_count>0 then
      local result = r.MB(string.format('Replace ALL FX on %d selected track(s)?', selected_count),'Confirm Replace',4)
      if result==6 then local count,msg=replace_fx_chain_to_selected_tracks(); if count>0 then state.pendingMessage=msg else state.pendingError=msg or 'Failed to replace on selected tracks' end end
    else state.pendingError='No tracks selected' end
  end
  if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then r.ImGui_SetTooltip(ctx,'Replace ALL FX on selected tracks') end
  if r.ImGui_Button(ctx,'Add to all tracks', bw2,0) then local track_count=r.CountTracks(0); local result=r.MB(string.format('Add FX chain to ALL %d tracks?',track_count),'Confirm Add to All',4); if result==6 then local count,msg=paste_fx_chain_to_all_tracks(); if count>0 then state.pendingMessage=msg else state.pendingError=msg or 'Failed to add to all tracks' end end end
  if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then r.ImGui_SetTooltip(ctx,'Add FX to ALL tracks (keeps existing)') end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx,'Replace all tracks', bw2,0) then local track_count=r.CountTracks(0); local result=r.MB(string.format('Replace ALL FX on ALL %d tracks?\n\nPERMANENT deletion of existing FX!',track_count),'CONFIRM REPLACE ALL',4); if result==6 then local count,msg=replace_fx_chain_to_all_tracks(); if count>0 then state.pendingMessage=msg else state.pendingError=msg or 'Failed to replace all tracks' end end end
  if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then r.ImGui_SetTooltip(ctx,'Replace ALL FX on ALL tracks (DANGER!)') end
  if not has_copied_chain and r.ImGui_EndDisabled then r.ImGui_EndDisabled(ctx) end
  if has_copied_chain then
    r.ImGui_Dummy(ctx,0,2); r.ImGui_Separator(ctx); r.ImGui_TextDisabled(ctx,'Add: keeps existing • Replace: deletes existing first')
    if r.ImGui_SmallButton(ctx,'Clear') then copied_fx_chain_info=nil; state.pendingMessage='Cleared copied FX chain' end
  end
  r.ImGui_Separator(ctx)
end

local function track_guid(tr) return tr and r.GetTrackGUID(tr) or nil end
local function capture_full_track_snapshot(tr)
  local fxCount = r.TrackFX_GetCount(tr)
  local list = {}
  for i=0, fxCount-1 do list[#list+1] = snapshot_fx(tr, i) end
  return list
end
local function snapshot_storage_candidates()
  local sep = package.config:sub(1,1)
  local resPath = r.GetResourcePath and r.GetResourcePath() or script_path
  local dataDir = resPath .. sep .. 'Data' .. sep .. 'TK_FX_Slots'
  return {
    {dir=dataDir, file='ChainSnapshots.dat'},            
    {dir=script_path, file='ChainSnapshots.dat'},        
    {dir=script_path, file='TK_TrackVersions.dat'},      
  }
end
local function ensure_dir(path)
  if not path or path=='' then return end
  if r.RecursiveCreateDirectory then r.RecursiveCreateDirectory(path,0) end
end
local function save_track_versions()
  local list = snapshot_storage_candidates()
  local f, targetPath
  for _,c in ipairs(list) do
    ensure_dir(c.dir)
    local p = c.dir .. (c.dir:sub(-1) == '/' or c.dir:sub(-1) == '\\' and '' or package.config:sub(1,1)) .. c.file
    f = io.open(p,'w')
    if f then targetPath = p break end
  end
  if not f then state.pendingError = 'Could not save snapshots (no writable path)'; return end
  state.lastSnapshotSavePath = targetPath
  f:write('VER1\n')
  for guid, versions in pairs(state.trackVersions or {}) do
    if type(guid)=='string' and #guid>5 and guid:find('{',1,true) then
      f:write('T\t',guid,'\n')
      for i, ver in ipairs(versions) do
        f:write('V\t',ver.name or ('v'..i),'\t',tostring(ver.time or 0),'\n')
        if ver.fxchainChunk and ver.fxchainChunk:find('<FXCHAIN') then
          f:write('R\t', tostring(#ver.fxchainChunk),'\n')
          f:write(ver.fxchainChunk)
          if ver.fxchainChunk:sub(-1) ~= '\n' then f:write('\n') end
          f:write('RAW_END\n')
        end
        for _, fx in ipairs(ver.fx or {}) do
          f:write('F\t',fx.name or '', '\t', tostring(fx.enabled and 1 or 0), '\t', tostring(fx.offline and 1 or 0), '\t', (fx.renamed or ''), '\t', tostring(fx.paramCount or 0), '\n')
          if fx.params then
            for p=0,(fx.paramCount or 0)-1 do
              local v = fx.params[p]
              if v then f:write('P\t',p,'\t',string.format('%.9f',v),'\n') end
            end
          end
        end
        f:write('E\n')
      end
      local cur = state.trackVersionsCurrentIndex[guid]
      if cur then f:write('C\t',guid,'\t',cur,'\n') end
      f:write('X\n')
    end
  end
  f:close()
end
function load_track_versions()
  local candidates = snapshot_storage_candidates()
  state.trackVersions = {}
  state.trackVersionsCurrentIndex = {}
  local totalFiles, parsedFiles, totalSnapshots, trackCount = 0,0,0,0
  local debugLines = {}
  local function parse_file(path)
    local fh = io.open(path,'r'); if not fh then debugLines[#debugLines+1] = ('MISS %s'):format(path); return 0,0,false end
    local content = fh:read('*a') or ''
    fh:close()
    local size = #content
    if size == 0 then debugLines[#debugLines+1] = ('EMPTY %s'):format(path); return 0,0,true end
    content = content:gsub('\r\n','\n'):gsub('\r','\n')
    if content:sub(1,3) == '\239\187\191' then content = content:sub(4) end
    local addedTracks, addedSnaps = 0,0
    local curTrack, curVer, mode
    local lineIndex = 0
    local linesIter = content:gmatch('([^\n]+)')
    local rawMode = false
    local sawHeader = false
    local previewLines = {}
    for line in linesIter do
      lineIndex = lineIndex + 1
      line = line:gsub('^%s+','')
      if lineIndex <= 8 then previewLines[#previewLines+1] = line end
      if rawMode then
        if line == 'RAW_END' then
          rawMode = false
        else
          if curVer then curVer._rawBuf[#curVer._rawBuf+1] = line .. '\n' end
        end
      else
        if line == 'VER1' then
          sawHeader = true
        else
          local tag,a,b,c,d,e = line:match('^(%S+)\t?(.-)\t?(.-)\t?(.-)\t?(.-)\t?(.-)$')
          if (tag == 'T' or tag == 'V') and (a == nil or a == '' or (tag=='T' and (not a:find('{',1,true)))) then
            local parts = {}
            for token in line:gmatch('%S+') do parts[#parts+1]=token end
            if parts[1] == 'T' and parts[2] then a = parts[2] end
            if parts[1] == 'V' and parts[2] then a = parts[2]; b = parts[3] end
          end
        if tag == 'T' then
          if a and a ~= '' then
            curTrack = a
            if not state.trackVersions[curTrack] then state.trackVersions[curTrack] = {}; addedTracks = addedTracks + 1 end
          else
            curTrack,curVer,mode=nil,nil,nil
          end
        elseif tag == 'V' and curTrack then
          curVer = { name = (a and a ~= '' and a or ('snap'..tostring(#state.trackVersions[curTrack]+1))), time=tonumber(b) or 0, fx={} }
          table.insert(state.trackVersions[curTrack], curVer)
          addedSnaps = addedSnaps + 1
        elseif tag == 'R' and curTrack then
          if curVer then curVer._rawBuf = {}; rawMode = true end
        elseif tag == 'F' and curVer then
          local fxname = a ~= '' and a or nil
          local fx = { name=fxname, enabled=(b=='1'), offline=(c=='1'), renamed=d~='' and d or nil, paramCount=tonumber(e) or 0, params={} }
          if fx.name then fx.srcAddName = fx.name end
          table.insert(curVer.fx, fx); mode = fx
        elseif tag == 'P' and mode then
          local pi=tonumber(a); local val=tonumber(b); if pi and val then mode.params[pi]=val end
        elseif tag == 'E' then mode=nil
        elseif tag == 'X' then curTrack,curVer,mode=nil,nil,nil
        elseif tag == 'C' then
          local g=a; local idx=tonumber(b); if g and idx and state.trackVersions[g] then state.trackVersionsCurrentIndex[g]=idx end
        end
        end
      end
    end
    for _,vers in pairs(state.trackVersions) do
      for _,v in ipairs(vers) do
        if v._rawBuf then v.fxchainChunk = table.concat(v._rawBuf); v._rawBuf=nil end
      end
    end
    debugLines[#debugLines+1] = ('PARSED %s size=%d tracks+%d snaps+%d'):format(path,size,addedTracks,addedSnaps)
  if #previewLines>0 then debugLines[#debugLines+1] = 'FIRSTLINES '..table.concat(previewLines,' | ') end
    return addedTracks, addedSnaps, true
  end
  for _,c in ipairs(candidates) do
    local sep = package.config:sub(1,1)
    local path = c.dir .. (c.dir:sub(-1) == '/' or c.dir:sub(-1) == '\\' and '' or sep) .. c.file
    totalFiles = totalFiles + 1
    local tracks,snaps,ok = parse_file(path)
    if ok then
      if tracks>0 or snaps>0 then parsedFiles = parsedFiles + 1 end
      totalSnapshots = totalSnapshots + snaps
    end
  end
  for _ in pairs(state.trackVersions) do trackCount = trackCount + 1 end
  if trackCount==0 and totalSnapshots==0 then
  else
  end
end
local function create_track_version(tr,name)
  if not tr then return false,'No track' end
  local guid = track_guid(tr); if not guid then return false,'No GUID' end
  local versions = state.trackVersions[guid]; if not versions then versions={}; state.trackVersions[guid]=versions end
  local vName = (name and name~='') and name or ('v'..(#versions+1))
  local fxList = capture_full_track_snapshot(tr)
  local fxNames = {}
  for i,s in ipairs(fxList) do fxNames[i] = s.srcAddName or s.name end
  local okChunk, fullChunk = r.GetTrackStateChunk(tr, '', false)
  local fxchainChunk
  if okChunk and fullChunk then
    local startPos = fullChunk:find('<FXCHAIN')
    if startPos then
      local pos = startPos
      local len = #fullChunk
      local depth = 0
      local capturing = false
      while pos <= len do
        local lineEnd = fullChunk:find('\n', pos) or (len+1)
        local line = fullChunk:sub(pos, lineEnd-1)
        if line:find('^<') then
          if not capturing and line:find('^<FXCHAIN') then capturing = true end
          if capturing then depth = depth + 1 end
        elseif line:match('^>%s*$') and capturing then
          depth = depth - 1
          if depth == 0 then
            fxchainChunk = fullChunk:sub(startPos, lineEnd)
            break
          end
        end
        pos = lineEnd + 1
      end
    end
  end
  versions[#versions+1] = { name=vName, time=os.time(), fx=fxList, fxNames=fxNames, fxchainChunk=fxchainChunk }
  state.trackVersionsCurrentIndex[guid] = #versions
  save_track_versions()
  return true,vName
end
local function apply_track_version(tr,index)
  if not tr then return false,'No track' end
  local guid = track_guid(tr); if not guid then return false,'No GUID' end
  local versions = state.trackVersions[guid]; if not versions or not versions[index] then return false,'Invalid version' end
  local ver = versions[index]
  r.Undo_BeginBlock('Apply snapshot')
  local fastApplied = false
  local snapNames = ver.fxNames
  if snapNames and #snapNames > 0 then
    local curCount = r.TrackFX_GetCount(tr)
    if curCount == #snapNames then
      local match = true
      for i=0, curCount-1 do
        local _, curName = r.TrackFX_GetFXName(tr, i, '')
        if curName ~= snapNames[i+1] then match = false break end
      end
      if match then
        for i,snap in ipairs(ver.fx or {}) do
          local idx = i-1
          if snap.enabled ~= nil then set_fx_enabled(tr, idx, snap.enabled) end
          if snap.offline ~= nil then set_fx_offline(tr, idx, snap.offline) end
          local pc = r.TrackFX_GetNumParams(tr, idx) or 0
          local maxp = math.min(pc, snap.paramCount or 0)
          for p=0, maxp-1 do
            local val = snap.params and snap.params[p]
            if val then r.TrackFX_SetParamNormalized(tr, idx, p, val) end
          end
          if snap.renamed then rename_fx_instance(tr, idx, snap.renamed) end
        end
        fastApplied = true
      end
    end
  end
  local usedChunk = fastApplied
  if (not usedChunk) and ver.fxchainChunk and ver.fxchainChunk:find('<FXCHAIN') then
    local okOrig, origChunk = r.GetTrackStateChunk(tr, '', false)
    if okOrig and origChunk then
      local startPos = origChunk:find('<FXCHAIN')
      if startPos then
        local pos = startPos
        local len = #origChunk
        local depth = 0
        local capturing = false
        local endPos
        while pos <= len do
          local lineEnd = origChunk:find('\n', pos) or (len+1)
          local line = origChunk:sub(pos, lineEnd-1)
          if line:find('^<') then
            if not capturing and line:find('^<FXCHAIN') then capturing = true end
            if capturing then depth = depth + 1 end
          elseif line:match('^>%s*$') and capturing then
            depth = depth - 1
            if depth == 0 then endPos = lineEnd; break end
          end
          pos = lineEnd + 1
        end
        if endPos then
          local newChunk = origChunk:sub(1,startPos-1) .. ver.fxchainChunk .. origChunk:sub(endPos+1)
          r.SetTrackStateChunk(tr, newChunk, false)
          usedChunk = true
        end
      end
    end
  end
  if not usedChunk then
    for i=r.TrackFX_GetCount(tr)-1,0,-1 do r.TrackFX_Delete(tr,i) end
    for _,snap in ipairs(ver.fx or {}) do
      local addName = snap.srcAddName or snap.name
      if addName and addName ~= '' then
        local idx = r.TrackFX_AddByName(tr, addName, false, -1)
        if idx >= 0 then
          local pc = r.TrackFX_GetNumParams(tr, idx) or 0
            local maxp = math.min(pc, snap.paramCount or 0)
            for p=0,maxp-1 do
              local val = snap.params and snap.params[p]
              if val then r.TrackFX_SetParamNormalized(tr, idx, p, val) end
            end
            if snap.renamed then rename_fx_instance(tr, idx, snap.renamed) end
            if snap.enabled ~= nil then set_fx_enabled(tr, idx, snap.enabled) end
            if snap.offline ~= nil then set_fx_offline(tr, idx, snap.offline) end
        end
      end
    end
  end
  r.Undo_EndBlock('Apply snapshot', -1)
  state.trackVersionsCurrentIndex[guid] = index
  save_track_versions()
  return true,ver.name
end
local function delete_track_version(tr,index)
  if not tr then return false,'No track' end
  local guid = track_guid(tr); if not guid then return false,'No GUID' end
  local versions = state.trackVersions[guid]; if not versions or not versions[index] then return false,'Invalid version' end
  table.remove(versions,index)
  if #versions==0 then
    state.trackVersions[guid]=nil
    state.trackVersionsCurrentIndex[guid]=nil
  else
    local cur = state.trackVersionsCurrentIndex[guid] or 1
    if cur==index then state.trackVersionsCurrentIndex[guid]=math.min(index,#versions)
    elseif cur>index then state.trackVersionsCurrentIndex[guid]=cur-1 end
  end
  save_track_versions()
  return true
end
local function rename_track_version(tr,index,newName)
  if not tr then return false,'No track' end
  local guid = track_guid(tr); if not guid then return false,'No GUID' end
  local versions = state.trackVersions[guid]; if not versions or not versions[index] then return false,'Invalid version' end
  if newName and newName~='' then versions[index].name=newName; save_track_versions(); return true end
  return false,'Empty name'
end
local function draw_trackversion_panel()
  if state.showPanelTrackVersion == false then return end
  if state.trackVersionHeaderOpen then r.ImGui_SetNextItemOpen(ctx,true,r.ImGui_Cond_FirstUseEver()) end
  local open = r.ImGui_CollapsingHeader(ctx,'Chain Snapshots:',0)
  if open ~= nil and open ~= state.trackVersionHeaderOpen then state.trackVersionHeaderOpen = open; save_user_settings() end
  if not open then return end
  local tr = get_selected_track()
  if not tr then
    r.ImGui_TextDisabled(ctx,'Select a track to manage versions')
    r.ImGui_Separator(ctx)
    return
  end
  if not state._versionsLoaded then load_track_versions(); state._versionsLoaded = true end
  local guid = track_guid(tr)
  local versions = state.trackVersions[guid] or {}
  local curIdx = state.trackVersionsCurrentIndex[guid]
  local btnW = (r.ImGui_GetContentRegionAvail(ctx)-4)*0.5

  local chgAA, valAA = r.ImGui_Checkbox(ctx, 'Auto apply on select', state.autoApplySnapshots or false)
  if chgAA then state.autoApplySnapshots = valAA end
  if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then r.ImGui_SetTooltip(ctx,'When enabled: a single click on a snapshot applies it immediately') end
  if r.ImGui_Button(ctx,'New Snapshot', btnW,0) then
    local def = 'snap'..(#versions+1)
    local ok,name = r.GetUserInputs('New Chain Snapshot',1,'Snapshot name:',def)
    if ok then
      local s,msg = create_track_version(tr,name)
      if s then state.pendingMessage='Created snapshot '..msg else state.pendingError=msg end
    end
  end
  if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then r.ImGui_SetTooltip(ctx,'Capture current FX chain (order, params, bypass/offline, names)') end
  r.ImGui_SameLine(ctx)
  local canApply = (#versions>0 and state._tvSelected and versions[state._tvSelected]) and true or false
  if not canApply and r.ImGui_BeginDisabled then r.ImGui_BeginDisabled(ctx) end
  if r.ImGui_Button(ctx,'Apply Selected', btnW,0) then
    if state._tvSelected and versions[state._tvSelected] then
      local s,msg = apply_track_version(tr,state._tvSelected)
      if s then state.pendingMessage='Applied snapshot '..msg else state.pendingError=msg end
    end
  end
  if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then r.ImGui_SetTooltip(ctx,'Replace current track FX chain with selected snapshot') end
  if not canApply and r.ImGui_EndDisabled then r.ImGui_EndDisabled(ctx) end
  r.ImGui_Dummy(ctx,0,4)
  local listH = 140
  if r.ImGui_BeginChild(ctx,'##tv_list', -1, listH) then
    for i,ver in ipairs(versions) do
      local label = ver.name
      if curIdx == i then label = label .. '  [active]' end
      local sel = (state._tvSelected == i)
      if r.ImGui_Selectable(ctx,label, sel) then
        state._tvSelected = i
        if state.autoApplySnapshots then
          local s,msg = apply_track_version(tr,i)
          if s then state.pendingMessage='Applied snapshot '..msg else state.pendingError=msg end
        end
      end
  if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then r.ImGui_SetTooltip(ctx,'Click: select snapshot\nDouble-click: apply\nRight-click: menu (apply / rename / delete)') end
      if r.ImGui_IsItemHovered(ctx) and r.ImGui_IsMouseDoubleClicked(ctx,0) then
        local s,msg = apply_track_version(tr,i)
        if s then state.pendingMessage='Applied version '..msg else state.pendingError=msg end
      end
      if r.ImGui_IsItemClicked(ctx,1) then r.ImGui_OpenPopup(ctx,'tv_ctx'..i) end
      if r.ImGui_BeginPopup(ctx,'tv_ctx'..i) then
        if r.ImGui_MenuItem(ctx,'Apply') then
          local s,msg=apply_track_version(tr,i)
          if s then state.pendingMessage='Applied snapshot '..msg else state.pendingError=msg end
        end
        if r.ImGui_MenuItem(ctx,'Rename') then
          local ok,newName = r.GetUserInputs('Rename Snapshot',1,'New name:', ver.name)
          if ok and newName~='' then
            local s,msg = rename_track_version(tr,i,newName)
            if s then state.pendingMessage='Renamed snapshot' else state.pendingError=msg end
          end
        end
        if r.ImGui_MenuItem(ctx,'Delete') then
          local s,msg=delete_track_version(tr,i)
          if s then state.pendingMessage='Deleted snapshot'; state._tvSelected=nil else state.pendingError=msg end
        end
        r.ImGui_EndPopup(ctx)
      end
    end
    if #versions==0 then r.ImGui_TextDisabled(ctx,'(no versions yet)') end
    if #versions>0 and state._tvSelected and versions[state._tvSelected] then
      r.ImGui_TextDisabled(ctx, string.format('Selected: %s', versions[state._tvSelected].name))
    end
    r.ImGui_EndChild(ctx)
  end
  r.ImGui_Dummy(ctx,0,4)
  r.ImGui_Separator(ctx)
end

 
local function draw()
  do
    local tr = get_selected_track()
    if tr and r.ValidatePtr(tr,'MediaTrack*') then
      local guid = r.GetTrackGUID(tr)
      if state.lastTrackGUID ~= guid then
        state.lastTrackGUID = guid
        local idx = tonumber(state.selectedSourceFXIndex)
        if idx and idx >=0 then
          local name = get_fx_name(tr, idx)
          if name ~= '' then
            state.selectedSourceFXName = name
          else
            state.selectedSourceFXIndex, state.selectedSourceFXName = nil, nil
          end
        end
      else
        local idx = tonumber(state.selectedSourceFXIndex)
        if idx then
          local name = get_fx_name(tr, idx)
           if name == '' then
             state.selectedSourceFXIndex, state.selectedSourceFXName = nil, nil
           else
             state.selectedSourceFXName = name
           end
        end
      end
    else
      state.selectedSourceFXIndex, state.selectedSourceFXName = nil, nil
      state.lastTrackGUID = nil
    end
  end
  if not is_context_valid(ctx) then 
    r.ShowConsoleMsg("Context invalid, reinitializing...\n")
    if not init_context() then 
      r.ShowConsoleMsg("Failed to reinitialize context\n")
      return 
    end
  end
  
  if not ctx then
    ctx = r.ImGui_CreateContext(SCRIPT_NAME)
    if not ctx then return end
  end
  
  if r.ImGui_SetNextWindowSize then 
    local success = pcall(r.ImGui_SetNextWindowSize, ctx, state.winW, state.winH, r.ImGui_Cond_FirstUseEver())
    if not success then
      r.ShowConsoleMsg("SetNextWindowSize failed, context may be invalid\n")
      return
    end
  end
  if r.ImGui_SetNextWindowSizeConstraints then r.ImGui_SetNextWindowSizeConstraints(ctx, 300, 220, 2000, 1400) end
  
  local stylePush = push_app_style()
  local visible, open = r.ImGui_Begin(ctx, SCRIPT_NAME, true, r.ImGui_WindowFlags_NoScrollbar() | r.ImGui_WindowFlags_NoScrollWithMouse() | r.ImGui_WindowFlags_NoTitleBar())
  
  if visible then
      do
      r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), 8, 6)
      styleStackDepth.vars = styleStackDepth.vars + 1  
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
        clicked = r.ImGui_Button(ctx, '⚙', 24, 18)
      end
      if clicked then
        state.showSettings = true
        state.showSettingsPending = true
      end
      if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then 
        r.ImGui_SetTooltip(ctx, 'Open settings and preferences') 
      end
      r.ImGui_PopStyleColor(ctx, 3)
      if pushedFont and r.ImGui_PopFont then r.ImGui_PopFont(ctx) end

  if true then r.ImGui_SameLine(ctx) end
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x00000000)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0x00000000)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0x00000000)
  if r.ImGui_SmallButton(ctx, 'ⓘ') then state.showHelp = true end
  if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then 
    r.ImGui_SetTooltip(ctx, 'Show help and usage information') 
  end
  r.ImGui_PopStyleColor(ctx, 3)
  
  r.ImGui_SameLine(ctx)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x00000000)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0x00000000)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0x00000000)
  if r.ImGui_SmallButton(ctx, '⎙') then
        local okP, pathP = print_plugin_list()
        if okP then state.pendingMessage = 'Saved report: ' .. tostring(pathP) else state.pendingError = tostring(pathP) end
  end
  if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then 
    r.ImGui_SetTooltip(ctx, 'Export FX report to text file') 
  end
  r.ImGui_PopStyleColor(ctx, 3)

  r.ImGui_SameLine(ctx)
  r.ImGui_Text(ctx, ' - SLOT')
  r.ImGui_SameLine(ctx)
  ensure_slot_logo()
  if state.slotLogoTex and state.slotLogoTex ~= false and r.ImGui_Image then
    r.ImGui_Image(ctx, state.slotLogoTex, 32, 20)
    if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then
      r.ImGui_SetTooltip(ctx, 'Slot Machine')
    end
  end
  r.ImGui_SameLine(ctx)
  r.ImGui_Text(ctx, 'MACHINE - ')

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
      styleStackDepth.vars = math.max(0, styleStackDepth.vars - 1)  
    end

  local FOOTER_H = 60
  local tr = get_selected_track()
  local frameHeight_header = r.ImGui_GetFrameHeight(ctx)
  local togglesH = 0
  if state.showTopPanelToggleBar ~= false then
    togglesH = frameHeight_header + 10
  end
  if state.showTopPanelToggleBar ~= false and togglesH > 0 then
    if r.ImGui_BeginChild(ctx, 'top_buttons', -1, togglesH) then
      local availW = select(1, r.ImGui_GetContentRegionAvail(ctx)) or 0
      local spacing = 4
      local labels = {
        {'Source','showTrackList'},
        {'Replace','showPanelReplacement'},
        {'FXChain','showPanelFXChain'},
        {'Snapshots','showPanelTrackVersion'},
      }
      local btnCount = #labels
      local totalSpacing = spacing * (btnCount - 1)
      local rawW = (availW - totalSpacing)
      if rawW < 50 * btnCount then rawW = 50 * btnCount end
      local btnW = math.floor(rawW / btnCount)
      for i, def in ipairs(labels) do
        local label, flagField = def[1], def[2]
        local on = state[flagField] ~= false
        if on and r.ImGui_PushStyleColor then
          r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), col_u32(0.20,0.38,0.20,1.0))
          r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), col_u32(0.26,0.46,0.26,1.0))
          r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), col_u32(0.18,0.32,0.18,1.0))
        end
        if r.ImGui_Button(ctx, label, btnW, 0) then
          state[flagField] = not on
          if flagField == 'showTrackList' then
            state.showPanelSource = (state[flagField] ~= false)
          end
        end
        if on and r.ImGui_PopStyleColor then r.ImGui_PopStyleColor(ctx,3) end
        if i < btnCount then r.ImGui_SameLine(ctx, nil, spacing) end
      end
      r.ImGui_Separator(ctx)
      r.ImGui_EndChild(ctx)
    end
  end

  local trackSectionH = 0
  if state.showTrackList ~= false then
    local headerH = frameHeight_header
    trackSectionH = headerH + 8
    if tr and state.trackHeaderOpen then
      local fxCount = r.TrackFX_GetCount(tr)
      if fxCount > 0 then
        local rowLineH = (r.ImGui_GetTextLineHeightWithSpacing and r.ImGui_GetTextLineHeightWithSpacing(ctx)) or (r.ImGui_GetTextLineHeight and r.ImGui_GetTextLineHeight(ctx)) or 18
        local rows = math.max(1, math.min(8, tonumber(state.fxSlotsVisibleRows) or 4))
        local tableH = math.floor((rowLineH + 4) * rows + 6)
        trackSectionH = headerH + tableH + 12
      end
    end
  end

  if state.showTrackList ~= false and trackSectionH > 0 then
    if r.ImGui_BeginChild(ctx, 'top_tracklist', -1, trackSectionH) then
      if tr then
        local tnum = get_track_number(tr) or 0
        local tname = get_track_name(tr)
        local hdr = ("%d: %s"):format(tnum, tname)
        local rC,gC,bC = get_track_color_rgb(tr)
        local pushedHdr = 0
        if not state.hdrInitApplied then
          if state.trackHeaderOpen then r.ImGui_SetNextItemOpen(ctx, true, r.ImGui_Cond_Always()) end
          state.hdrInitApplied = true
        end
        local buttonAreaWidth = state.showRMSButtons and 60 or 0
        local availWidth = r.ImGui_GetContentRegionAvail(ctx)
        local headerWidth = availWidth - buttonAreaWidth
        do
          local arrowReserve = 26
          local paddingReserve = 10
          local extraGap = 8
          local maxNameWidth = headerWidth - arrowReserve - paddingReserve - extraGap
          if maxNameWidth < 20 then maxNameWidth = 20 end
          hdr = truncate_text_to_width(ctx, hdr, maxNameWidth)
        end
        local openHdr = state.trackHeaderOpen
        if rC and gC and bC then
          local base = col_u32(rC, gC, bC, 1.0)
          local hovR,hovG,hovB = lighten(rC,gC,bC, 0.08)
          local actR,actG,actB = lighten(rC,gC,bC, -0.06)
          if r.ImGui_PushStyleColor then
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(),        base); pushedHdr = pushedHdr + 1
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), col_u32(hovR,hovG,hovB,1.0)); pushedHdr = pushedHdr + 1
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(),  col_u32(actR,actG,actB,1.0)); pushedHdr = pushedHdr + 1
          end
        end
        local frameHeight = r.ImGui_GetFrameHeight(ctx)
        if r.ImGui_Button(ctx, "##header_bg", headerWidth, frameHeight) then
          openHdr = not openHdr
          state.trackHeaderOpen = openHdr
          r.SetExtState(EXT_NS, 'HDR_OPEN', state.trackHeaderOpen and '1' or '0', true)
        end
        if state.showRMSButtons then
          local trRec = tr and (r.GetMediaTrackInfo_Value(tr, 'I_RECARM') or 0) or 0
          local trMute = tr and (r.GetMediaTrackInfo_Value(tr, 'B_MUTE') or 0) or 0
          local trSolo = tr and (r.GetMediaTrackInfo_Value(tr, 'I_SOLO') or 0) or 0
          r.ImGui_SameLine(ctx, 0, 2)
          local spacingX = 2
          local pushedSV = 0
          if r.ImGui_PushStyleVar then
            if r.ImGui_StyleVar_FramePadding then
              r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FramePadding(), 3, 3); pushedSV = pushedSV + 1; styleStackDepth.vars = styleStackDepth.vars + 1
            end
            if r.ImGui_StyleVar_ItemSpacing then
              r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing(), spacingX, 0); pushedSV = pushedSV + 1; styleStackDepth.vars = styleStackDepth.vars + 1
            end
          end
          do
            local isOn = (trRec or 0) > 0
            local pushed = 0
            if isOn and r.ImGui_PushStyleColor then
              r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(),        col_u32(0.70, 0.20, 0.20, 1.0)); pushed = pushed + 1
              r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), col_u32(0.85, 0.30, 0.30, 1.0)); pushed = pushed + 1
              r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(),  col_u32(0.60, 0.15, 0.15, 1.0)); pushed = pushed + 1
              local textR, textG, textB = get_text_color_for_background(rC, gC, bC)
              r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), col_u32(textR, textG, textB, 1.0)); pushed = pushed + 1
            elseif rC and gC and bC then
              local textR, textG, textB = get_text_color_for_background(rC, gC, bC)
              r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), col_u32(textR, textG, textB, 1.0)); pushed = pushed + 1
            end
            r.ImGui_Button(ctx, 'R', 18, frameHeight)
            if r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip and state.tooltips then r.ImGui_SetTooltip(ctx, 'Click: Record arm on/off') end
            if r.ImGui_IsItemClicked and r.ImGui_IsItemClicked(ctx, 0) then
              r.Undo_BeginBlock('Toggle record arm')
              r.SetMediaTrackInfo_Value(tr, 'I_RECARM', isOn and 0 or 1)
              r.Undo_EndBlock('Toggle record arm', -1)
            end
            if pushed > 0 and r.ImGui_PopStyleColor then r.ImGui_PopStyleColor(ctx, pushed) end
          end
          r.ImGui_SameLine(ctx)
          do
            local isOn = (trMute or 0) > 0
            local pushed = 0
            if isOn and r.ImGui_PushStyleColor then
              r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(),        col_u32(0.75, 0.55, 0.20, 1.0)); pushed = pushed + 1
              r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), col_u32(0.85, 0.65, 0.25, 1.0)); pushed = pushed + 1
              r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(),  col_u32(0.65, 0.45, 0.18, 1.0)); pushed = pushed + 1
              local textR, textG, textB = get_text_color_for_background(rC, gC, bC)
              r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), col_u32(textR, textG, textB, 1.0)); pushed = pushed + 1
            elseif rC and gC and bC then
              local textR, textG, textB = get_text_color_for_background(rC, gC, bC)
              r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), col_u32(textR, textG, textB, 1.0)); pushed = pushed + 1
            end
            r.ImGui_Button(ctx, 'M', 18, frameHeight)
            if r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip and state.tooltips then r.ImGui_SetTooltip(ctx, 'Click: Mute on/off\nCtrl+Click: Unmute all\nCtrl+Alt+Click: Exclusive mute\nAlt+Click: Mute all others') end
            if r.ImGui_IsItemClicked and r.ImGui_IsItemClicked(ctx, 0) then
              local ctrl = r.ImGui_IsKeyDown(ctx, r.ImGui_Key_LeftCtrl()) or r.ImGui_IsKeyDown(ctx, r.ImGui_Key_RightCtrl())
              local alt = r.ImGui_IsKeyDown(ctx, r.ImGui_Key_LeftAlt()) or r.ImGui_IsKeyDown(ctx, r.ImGui_Key_RightAlt())
              if ctrl and alt then
                r.Undo_BeginBlock('Exclusive mute')
                r.Main_OnCommand(40339, 0)
                r.SetMediaTrackInfo_Value(tr, 'B_MUTE', 1)
                r.Undo_EndBlock('Exclusive mute', -1)
              elseif ctrl then
                r.Undo_BeginBlock('Unmute all')
                r.Main_OnCommand(40339, 0)
                r.Undo_EndBlock('Unmute all', -1)
              elseif alt then
                r.Undo_BeginBlock('Mute all others')
                r.SetMediaTrackInfo_Value(tr, 'B_MUTE', 0)
                local trackCount = r.CountTracks(0)
                for i = 0, trackCount - 1 do
                  local track = r.GetTrack(0, i)
                  if track ~= tr then
                    r.SetMediaTrackInfo_Value(track, 'B_MUTE', 1)
                  end
                end
                r.Undo_EndBlock('Mute all others', -1)
              else
                r.Undo_BeginBlock('Toggle mute')
                r.SetMediaTrackInfo_Value(tr, 'B_MUTE', isOn and 0 or 1)
                r.Undo_EndBlock('Toggle mute', -1)
              end
            end
            if pushed > 0 and r.ImGui_PopStyleColor then r.ImGui_PopStyleColor(ctx, pushed) end
          end
          r.ImGui_SameLine(ctx)
          do
            local isOn = (trSolo or 0) > 0
            local pushed = 0
            if isOn and r.ImGui_PushStyleColor then
              r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(),        col_u32(0.25, 0.60, 0.25, 1.0)); pushed = pushed + 1
              r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), col_u32(0.30, 0.70, 0.30, 1.0)); pushed = pushed + 1
              r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(),  col_u32(0.20, 0.50, 0.20, 1.0)); pushed = pushed + 1
              local textR, textG, textB = get_text_color_for_background(rC, gC, bC)
              r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), col_u32(textR, textG, textB, 1.0)); pushed = pushed + 1
            elseif rC and gC and bC then
              local textR, textG, textB = get_text_color_for_background(rC, gC, bC)
              r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), col_u32(textR, textG, textB, 1.0)); pushed = pushed + 1
            end
            r.ImGui_Button(ctx, 'S', 18, frameHeight)
            if r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip and state.tooltips then r.ImGui_SetTooltip(ctx, 'Click: Solo on/off\nCtrl+Click: Unsolo all\nCtrl+Shift+Click: Solo defeat\nCtrl+Alt+Click: Exclusive solo') end
            if r.ImGui_IsItemClicked and r.ImGui_IsItemClicked(ctx, 0) then
              local ctrl = r.ImGui_IsKeyDown(ctx, r.ImGui_Key_LeftCtrl()) or r.ImGui_IsKeyDown(ctx, r.ImGui_Key_RightCtrl())
              local alt = r.ImGui_IsKeyDown(ctx, r.ImGui_Key_LeftAlt()) or r.ImGui_IsKeyDown(ctx, r.ImGui_Key_RightAlt())
              local shift = r.ImGui_IsKeyDown(ctx, r.ImGui_Key_LeftShift()) or r.ImGui_IsKeyDown(ctx, r.ImGui_Key_RightShift())
              if ctrl and shift then
                r.Undo_BeginBlock('Solo defeat')
                r.Main_OnCommand(41199, 0)
                r.Undo_EndBlock('Solo defeat', -1)
              elseif ctrl and alt then
                r.Undo_BeginBlock('Exclusive solo')
                local trackCount = r.CountTracks(0)
                for i = 0, trackCount - 1 do
                  local track = r.GetTrack(0, i)
                  if track == tr then
                    r.SetMediaTrackInfo_Value(track, 'I_SOLO', 1)
                  else
                    r.SetMediaTrackInfo_Value(track, 'I_SOLO', 0)
                  end
                end
                r.Undo_EndBlock('Exclusive solo', -1)
              elseif ctrl then
                r.Undo_BeginBlock('Unsolo all')
                r.Main_OnCommand(40340, 0)
                r.Undo_EndBlock('Unsolo all', -1)
              else
                r.Undo_BeginBlock('Toggle solo')
                r.SetMediaTrackInfo_Value(tr, 'I_SOLO', isOn and 0 or 1)
                r.Undo_EndBlock('Toggle solo', -1)
              end
            end
            if pushed > 0 and r.ImGui_PopStyleColor then r.ImGui_PopStyleColor(ctx, pushed) end
          end
          if pushedSV > 0 and r.ImGui_PopStyleVar then
            r.ImGui_PopStyleVar(ctx, pushedSV)
            styleStackDepth.vars = math.max(0, styleStackDepth.vars - pushedSV)
          end
        end
        r.ImGui_SameLine(ctx, 0, 0)
        r.ImGui_SetCursorPosX(ctx, r.ImGui_GetCursorPosX(ctx) - availWidth + 4)
        local textColorPushed = 0
        if rC and gC and bC then
          local textR, textG, textB = get_text_color_for_background(rC, gC, bC)
          r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), col_u32(textR, textG, textB, 1.0))
          textColorPushed = 1
        end
        r.ImGui_Text(ctx, openHdr and "▼" or "►")
        r.ImGui_SameLine(ctx, 0, 6)
        local currentY = r.ImGui_GetCursorPosY(ctx)
        r.ImGui_SetCursorPosY(ctx, currentY - 3)
        local fontPushed = false
        if r.ImGui_PushFont then
          local pushSuccess = pcall(r.ImGui_PushFont, ctx, nil, r.ImGui_GetFontSize(ctx) * 1.25)
          fontPushed = pushSuccess
        end
        r.ImGui_Text(ctx, hdr)
        if fontPushed and r.ImGui_PopFont then
          pcall(r.ImGui_PopFont, ctx)
        end
        if textColorPushed > 0 then
          r.ImGui_PopStyleColor(ctx, textColorPushed)
        end
        if r.ImGui_SetItemAllowOverlap then r.ImGui_SetItemAllowOverlap(ctx) end
        if pushedHdr > 0 and r.ImGui_PopStyleColor then r.ImGui_PopStyleColor(ctx, pushedHdr) end
        if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then
          r.ImGui_SetTooltip(ctx, 'Click to expand/collapse the selected track\'s FX list')
        end
        if openHdr then
          local fxCount = r.TrackFX_GetCount(tr)
          if fxCount <= 0 then
            r.ImGui_Text(ctx, '(No FX on this track)')
          else
            state.fxSlotsVisibleRows = math.max(1, math.min(8, tonumber(state.fxSlotsVisibleRows) or 4))
            local rowLineH = (r.ImGui_GetTextLineHeightWithSpacing and r.ImGui_GetTextLineHeightWithSpacing(ctx)) or (r.ImGui_GetTextLineHeight and r.ImGui_GetTextLineHeight(ctx)) or 18
            local flags = r.ImGui_TableFlags_SizingFixedFit() | r.ImGui_TableFlags_RowBg()
            if r.ImGui_BeginTable(ctx, 'fx_table_single', 3, flags) then
              r.ImGui_TableSetupColumn(ctx, '#', r.ImGui_TableColumnFlags_WidthFixed(), 20)
              r.ImGui_TableSetupColumn(ctx, 'FX name', r.ImGui_TableColumnFlags_WidthStretch())
              r.ImGui_TableSetupColumn(ctx, 'Ctl', r.ImGui_TableColumnFlags_WidthFixed(), 46)
              for i = 0, fxCount - 1 do
                r.ImGui_TableNextRow(ctx)
                if r.ImGui_TableSetBgColor and r.ImGui_TableBgTarget_RowBg0 and r.ImGui_TableBgTarget_RowBg1 then
                  local isSelected = (tonumber(state.selectedSourceFXIndex) or -1) == i
                  local col = isSelected and col_u32(0.24,0.38,0.55,0.55) or col_u32(0.19,0.19,0.19,1.0)
                  r.ImGui_TableSetBgColor(ctx, r.ImGui_TableBgTarget_RowBg0(), col)
                  r.ImGui_TableSetBgColor(ctx, r.ImGui_TableBgTarget_RowBg1(), col)
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
                  r.ImGui_SetTooltip(ctx, 'Right-Click: open | Alt+Click: delete | Shift+Click: bypass | Ctrl+Shift+Click: offline | Drag: reorder')
                end
                if r.ImGui_BeginDragDropSource and r.ImGui_BeginDragDropTarget and r.ImGui_AcceptDragDropPayload and r.ImGui_SetDragDropPayload then
                  if r.ImGui_BeginDragDropSource(ctx, 0) then
                    r.ImGui_SetDragDropPayload(ctx, DND_FX_PAYLOAD, tostring(i))
                    r.ImGui_Text(ctx, 'Move: ' .. disp)
                    if r.ImGui_EndDragDropSource then r.ImGui_EndDragDropSource(ctx) end
                  end
                  if r.ImGui_BeginDragDropTarget(ctx) then
                    local ok, payload = r.ImGui_AcceptDragDropPayload(ctx, DND_FX_PAYLOAD)
                    if ok and payload then
                      local src = tonumber(payload) or -1
                      local dest = i
                      if src >= 0 and src ~= dest then
                        if src < dest then dest = dest + 1 end
                        r.Undo_BeginBlock('Move FX')
                        if not move_fx_drag_chunk(tr, src, dest) then
                          r.TrackFX_CopyToTrack(tr, src, tr, dest, true)
                        end
                        r.Undo_EndBlock('Move FX', -1)
                        state.pendingMessage = string.format('Moved "%s" to position %d', disp, (dest<r.TrackFX_GetCount(tr) and dest or (r.TrackFX_GetCount(tr)-1)) + 1)
                      end
                    end
                    if r.ImGui_EndDragDropTarget then r.ImGui_EndDragDropTarget(ctx) end
                  end
                end
                local altClick = false
                local anyClick = false
                local rightClick = false
                if r.ImGui_IsItemClicked then
                  anyClick = r.ImGui_IsItemClicked(ctx, 0)
                  rightClick = r.ImGui_IsItemClicked(ctx, 1)
                  if anyClick and is_alt_down() then altClick = true end
                else
                  anyClick = clicked
                end
                if (clicked or anyClick or altClick) and not state._pendingDelArmed then
                  local altDown = is_alt_down()
                  local shiftDown = is_shift_down()
                  local ctrlDown = is_ctrl_down()
                  if altDown then
                    local guid = r.TrackFX_GetFXGUID and r.TrackFX_GetFXGUID(tr, i) or nil
                    state._pendingDelGUID = guid
                    state._pendingDelTrack = tr
                    state._pendingDelDisp = disp
                    state._pendingDelIndex = i
                    state._pendingDelArmed = true
                    break
                  elseif shiftDown and ctrlDown then
                    r.Undo_BeginBlock('Toggle FX Offline')
                    local off = get_fx_offline(tr, i)
                    set_fx_offline(tr, i, off == nil and true or (not off))
                    r.Undo_EndBlock('Toggle FX Offline', -1)
                    state.pendingMessage = string.format('Offline: %s (%s)', (get_fx_offline(tr, i) and 'On' or 'Off'), disp)
                    state._pendingDelArmed = true
                    break
                  elseif shiftDown then
                    r.Undo_BeginBlock('Toggle FX Bypass')
                    local en = get_fx_enabled(tr, i)
                    set_fx_enabled(tr, i, en == nil and false or (not en))
                    r.Undo_EndBlock('Toggle FX Bypass', -1)
                    local newEn = get_fx_enabled(tr, i)
                    state.pendingMessage = string.format('Bypass: %s (%s)', (newEn == false) and 'On' or 'Off', disp)
                    state._pendingDelArmed = true
                    break
                  end
                end
                if rightClick and r.TrackFX_Show then
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
                do
                  local setNormal = false
                  if clicked and r.ImGui_IsItemHovered(ctx) then
                    local altDown = is_alt_down()
                    local shiftDown = is_shift_down()
                    local ctrlDown = is_ctrl_down()
                    if not altDown and not shiftDown and not ctrlDown and not rightClick then
                      setNormal = true
                    end
                  end
                  if setNormal then
                    state.selectedSourceFXName = nm
                    state.selectedSourceFXIndex = i
                  end
                end
                r.ImGui_TableSetColumnIndex(ctx, 2)
                local frameH = r.ImGui_GetFrameHeight(ctx)
                local btnW = 18
                do
                  local en = get_fx_enabled(tr, i)
                  local bypassActive = (en ~= nil) and (not en)
                  local pushedB = 0
                  if bypassActive and r.ImGui_PushStyleColor then
                    local br,bg,bb = 0.45,0.35,0.10
                    local hr,hg,hb = lighten(br,bg,bb,0.10)
                    local ar,ag,ab = lighten(br,bg,bb,-0.08)
                    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), col_u32(br,bg,bb,1.0)); pushedB=pushedB+1
                    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), col_u32(hr,hg,hb,1.0)); pushedB=pushedB+1
                    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), col_u32(ar,ag,ab,1.0)); pushedB=pushedB+1
                  end
                  if r.ImGui_Button(ctx, 'B##rowB'..i, btnW, frameH) then
                    local curEn = get_fx_enabled(tr, i)
                    set_fx_enabled(tr, i, curEn == nil and false or (not curEn))
                  end
                  if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then r.ImGui_SetTooltip(ctx,'Toggle bypass') end
                  if pushedB>0 and r.ImGui_PopStyleColor then r.ImGui_PopStyleColor(ctx,pushedB) end
                end
                r.ImGui_SameLine(ctx,nil,2)
                do
                  local off = get_fx_offline(tr, i)
                  local offActive = (off ~= nil) and off
                  local pushedO = 0
                  if offActive and r.ImGui_PushStyleColor then
                    local br,bg,bb = 0.38,0.20,0.20
                    local hr,hg,hb = lighten(br,bg,bb,0.10)
                    local ar,ag,ab = lighten(br,bg,bb,-0.08)
                    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), col_u32(br,bg,bb,1.0)); pushedO=pushedO+1
                    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), col_u32(hr,hg,hb,1.0)); pushedO=pushedO+1
                    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), col_u32(ar,ag,ab,1.0)); pushedO=pushedO+1
                  end
                  if r.ImGui_Button(ctx, 'O##rowO'..i, btnW, frameH) then
                    local curOff = get_fx_offline(tr, i)
                    set_fx_offline(tr, i, curOff == nil and true or (not curOff))
                  end
                  if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then r.ImGui_SetTooltip(ctx,'Toggle offline') end
                  if pushedO>0 and r.ImGui_PopStyleColor then r.ImGui_PopStyleColor(ctx,pushedO) end
                end
              end
              r.ImGui_EndTable(ctx)
            end
            
            if state._pendingDelGUID and state._pendingDelTrack then
              local delTr = state._pendingDelTrack
              local delGuid = state._pendingDelGUID
              local delIdx = find_fx_index_by_guid(delTr, delGuid)
              r.Undo_BeginBlock('Delete FX')
              local ok = false
              if delIdx and delIdx >= 0 then
                ok = pcall(function() r.TrackFX_Delete(delTr, delIdx) end)
              end
              r.Undo_EndBlock('Delete FX', -1)
              if ok then
                if delTr == tr then
                  local sel = tonumber(state.selectedSourceFXIndex)
                  if sel ~= nil then
                    if sel == delIdx then
                      state.selectedSourceFXIndex = nil
                      state.selectedSourceFXName = nil
                    elseif sel > delIdx then
                      state.selectedSourceFXIndex = sel - 1
                    end
                  end
                end
                state.pendingMessage = string.format('Deleted "%s" (slot %d)', tostring(state._pendingDelDisp or ''), (delIdx or 0) + 1)
              else
                state.pendingError = 'Failed to delete FX'
              end
              state._pendingDelGUID, state._pendingDelTrack, state._pendingDelDisp, state._pendingDelIndex = nil, nil, nil, nil
            end
          end
        end
      else
        r.ImGui_Text(ctx, 'No track selected. Select a track in REAPER to view its FX.')
      end
  r.ImGui_EndChild(ctx)
    end
  end

  if state.showTrackList ~= false then
    local splitterHeight = 6
    local availW = select(1, r.ImGui_GetContentRegionAvail(ctx)) or -1
    if r.ImGui_InvisibleButton then
      r.ImGui_InvisibleButton(ctx, '##fxSlotsResize_fixed', availW, splitterHeight)
      local hovered = r.ImGui_IsItemHovered(ctx)
      local active = r.ImGui_IsItemActive(ctx)
      if hovered and r.ImGui_SetMouseCursor and r.ImGui_MouseCursor_ResizeNS then
        pcall(function() r.ImGui_SetMouseCursor(ctx, r.ImGui_MouseCursor_ResizeNS()) end)
      end
      if state.tooltips and hovered and r.ImGui_SetTooltip then r.ImGui_SetTooltip(ctx, 'Drag to change FX slots height (1-8 rows)') end
      if active and r.ImGui_IsMouseDragging and r.ImGui_IsMouseDragging(ctx,0) then
        local rowLineH = (r.ImGui_GetTextLineHeightWithSpacing and r.ImGui_GetTextLineHeightWithSpacing(ctx)) or (r.ImGui_GetTextLineHeight and r.ImGui_GetTextLineHeight(ctx)) or 18
        local dragDy = select(2, r.ImGui_GetMouseDragDelta(ctx,0)) or 0
        local deltaRows = math.floor(dragDy / (rowLineH * 0.9))
        if deltaRows ~= 0 then
          state.fxSlotsVisibleRows = math.max(1, math.min(8, state.fxSlotsVisibleRows + deltaRows))
          r.ImGui_ResetMouseDragDelta(ctx,0)
          save_user_settings()
        end
      end
      if r.ImGui_GetItemRectMin and r.ImGui_GetItemRectMax and r.ImGui_DrawList_AddRectFilled then
        local minx, miny = r.ImGui_GetItemRectMin(ctx)
        local maxx, maxy = r.ImGui_GetItemRectMax(ctx)
        local dl = r.ImGui_GetWindowDrawList(ctx)
        if dl then
          local hovered = r.ImGui_IsItemHovered(ctx)
          local active = r.ImGui_IsItemActive(ctx)
          local baseCol = col_u32(0.55,0.55,0.55,0.35)
          if hovered then baseCol = col_u32(0.80,0.80,0.80,0.55) end
          if active then baseCol = col_u32(0.32,0.60,0.95,0.85) end
          r.ImGui_DrawList_AddRectFilled(dl, minx, miny, maxx, maxy, baseCol, 2)
          local midY = (miny + maxy) * 0.5
          local centerX = (minx + maxx) * 0.5
          local dotCol = col_u32(0.15,0.15,0.15, active and 1.0 or (hovered and 0.9 or 0.6))
          if r.ImGui_DrawList_AddCircleFilled then
            local spacing = 6
            r.ImGui_DrawList_AddCircleFilled(dl, centerX - spacing, midY, 2, dotCol)
            r.ImGui_DrawList_AddCircleFilled(dl, centerX,          midY, 2, dotCol)
            r.ImGui_DrawList_AddCircleFilled(dl, centerX + spacing, midY, 2, dotCol)
          end
        end
      end
    end
  end
  
  if state.showTrackList ~= false and state.showPanelSource ~= false then
    r.ImGui_Dummy(ctx,0,4)
    draw_source_controls_inline()
  end

  if r.ImGui_BeginChild(ctx, 'content_child', -1, -FOOTER_H) then
    if not tr then
      r.ImGui_Text(ctx, 'No track selected. Select a track in REAPER to view its FX.')
    else
    end
    local hdrColorCount = 0
    if r.ImGui_PushStyleColor then
      r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Header(),        col_u32(0.12,0.12,0.12,1.00)); hdrColorCount = hdrColorCount + 1
      r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderHovered(), col_u32(0.18,0.18,0.18,1.00)); hdrColorCount = hdrColorCount + 1
      r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderActive(),  col_u32(0.24,0.24,0.24,1.00)); hdrColorCount = hdrColorCount + 1
    end
    if state.showPanelReplacement ~= false then draw_replace_panel() end
    if state.showPanelFXChain ~= false then draw_fxchain_panel() end
    if state.showPanelTrackVersion ~= false then draw_trackversion_panel() end
    if hdrColorCount > 0 and r.ImGui_PopStyleColor then r.ImGui_PopStyleColor(ctx, hdrColorCount) end
    r.ImGui_EndChild(ctx)
  end

    r.ImGui_Separator(ctx)
    
    -- Define track variables before navigation section (always needed for footer)
    local current_track = get_selected_track()
    local current_number = current_track and get_track_number(current_track) or 0
    local total_tracks = r.CountTracks(0)
    
    -- Navigation buttons section with safety checks
    if (state.showTrackNavButtons ~= false) and ctx and is_context_valid(ctx) then
      local nav_width = (state.lastSourceBlockWidth and state.lastSourceBlockWidth > 120) and math.min(state.lastSourceBlockWidth, 600) or 280
      local available_width = r.ImGui_GetContentRegionAvail(ctx) or 0
      local start_pos = math.max(0, (available_width - nav_width) * 0.5)
      r.ImGui_SetCursorPosX(ctx, start_pos)
  if r.ImGui_Button(ctx, '⟪', 25, 0) then
      local success, msg = navigate_to_first_track()
      if success then state.pendingMessage = msg else state.pendingError = msg end
    end
    if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then
      r.ImGui_SetTooltip(ctx, 'Go to first track')
    end
    
    r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, '◀', 25, 0) then
      local success, msg = navigate_to_previous_track()
      if success then state.pendingMessage = msg else state.pendingError = msg end
    end
    if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then
      r.ImGui_SetTooltip(ctx, 'Go to previous track')
    end
    
  r.ImGui_SameLine(ctx)
  local usedButtonsW = (25+4) + (25+4) + (35+4) + (25+4) + 25
  local trackPickerWidth = nav_width - usedButtonsW
  if trackPickerWidth < 60 then trackPickerWidth = 60 end
  r.ImGui_SetNextItemWidth(ctx, trackPickerWidth)
    local changed, new_input = r.ImGui_InputText(ctx, '##track_nav_input', state.trackNavInput)
    if changed then state.trackNavInput = new_input end
    if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then
      r.ImGui_SetTooltip(ctx, 'Enter track number (1-' .. tostring(total_tracks) .. ')')
    end
    
    r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, 'Go!', 35, 0) then
      local track_num = tonumber(state.trackNavInput)
      if track_num then
        local success, msg = go_to_track(track_num)
        if success then
          state.pendingMessage = msg
          state.trackNavInput = ''
        else
          state.pendingError = msg
        end
      else
        state.pendingError = 'Invalid track number: ' .. tostring(state.trackNavInput)
      end
    end
    if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then
      r.ImGui_SetTooltip(ctx, 'Go to specified track number')
    end
    
    r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, '▶', 25, 0) then
      local success, msg = navigate_to_next_track()
      if success then state.pendingMessage = msg else state.pendingError = msg end
    end
    if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then
      r.ImGui_SetTooltip(ctx, 'Go to next track')
    end
    
    r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, '⟫', 25, 0) then
      local success, msg = navigate_to_last_track()
      if success then state.pendingMessage = msg else state.pendingError = msg end
  end
    if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then
      r.ImGui_SetTooltip(ctx, 'Go to last track')
    end
  end 
  

    local footer_open = r.ImGui_BeginChild(ctx, 'footer_child', -1, FOOTER_H)
    if footer_open then
      local msg = state.pendingMessage or ''
      local err = state.pendingError or ''
      local hasMsg = (msg ~= '')
      local hasErr = (err ~= '')
      if hasErr then
        r.ImGui_Text(ctx, 'Error: ' .. tostring(err))
      elseif hasMsg then
        r.ImGui_Text(ctx, msg)
      else
        r.ImGui_TextDisabled(ctx, 'Ready')
      end
      r.ImGui_SameLine(ctx)
      r.ImGui_TextDisabled(ctx, string.format(' (%d/%d)', current_number, total_tracks))
      local preview = state.previewPending
      if preview and preview ~= '' then
        r.ImGui_NewLine(ctx)
        r.ImGui_TextDisabled(ctx, preview)
      end
      state.previewPending = nil
      r.ImGui_EndChild(ctx)
    end

    local cw, ch = r.ImGui_GetWindowSize(ctx)
    state.winW, state.winH = cw, ch
    
    r.ImGui_End(ctx)
  end
  
  pop_app_style(stylePush)
  
  if r.ImGui_IsMouseReleased and r.ImGui_IsMouseReleased(ctx, 0) then
    state._pendingDelArmed = false
  end
  
  if state.showSettings and ctx then
    if state.showSettingsPending then
      
      state.showSettingsPending = false
    else
    local settings_begun = false
    local okS, openS
    local settingsStylePush = push_app_style()
    local ok_call, err = pcall(function()
      okS, openS = r.ImGui_Begin(ctx, 'Settings##TK_FX_Slots_SingleTrack', true,
        r.ImGui_WindowFlags_AlwaysAutoResize() | r.ImGui_WindowFlags_NoTitleBar())
      settings_begun = true
    end)
    if ok_call and settings_begun then
      if okS then
  r.ImGui_TextColored(ctx, col_u32(0.85,0.85,0.85,1.0), 'Settings')
  r.ImGui_Dummy(ctx, 0, 2)
        r.ImGui_Separator(ctx)
        local changed = false
        
        if r.ImGui_BeginTabBar and r.ImGui_BeginTabBar(ctx, 'SettingsTabs') then
          
          if r.ImGui_BeginTabItem and r.ImGui_BeginTabItem(ctx, 'General') then
            local c1, v1 = r.ImGui_Checkbox(ctx, 'Tooltips', state.tooltips)
            if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then r.ImGui_SetTooltip(ctx,'Show on-hover help popups throughout the UI') end
            if c1 then state.tooltips = v1; changed = true end
            local c2, v2 = r.ImGui_Checkbox(ctx, 'Names without prefix', state.nameNoPrefix)
            if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then r.ImGui_SetTooltip(ctx,'Strip common vendor / category prefixes from FX names') end
            if c2 then state.nameNoPrefix = v2; changed = true end
            local c3, v3 = r.ImGui_Checkbox(ctx, 'Hide developer name', state.nameHideDeveloper)
            if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then r.ImGui_SetTooltip(ctx,'Hide the developer (author) segment from FX display names') end
            if c3 then state.nameHideDeveloper = v3; changed = true end
            local c4, v4 = r.ImGui_Checkbox(ctx, 'Plugin image', state.showScreenshot)
            if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then r.ImGui_SetTooltip(ctx,'Show / hide captured plugin interface image') end
            if c4 then
              state.showScreenshot = v4; changed = true
              if v4 then
                state.screenshotNeedsRefresh = true
              else
                release_screenshot()
              end
            end
            local c5, v5 = r.ImGui_Checkbox(ctx, 'Show R/M/S buttons', state.showRMSButtons)
            if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then r.ImGui_SetTooltip(ctx,'Show record (R), mute (M) and solo (S) buttons near tracks list') end
            if c5 then state.showRMSButtons = v5; changed = true end
            local c6, v6 = r.ImGui_Checkbox(ctx, 'Show Track FX list', state.showTrackList ~= false)
            if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then r.ImGui_SetTooltip(ctx,'Toggle visibility of the left track FX list panel') end
            if c6 then state.showTrackList = v6; changed = true end
            local c7, v7 = r.ImGui_Checkbox(ctx, 'Show Track Nav buttons', state.showTrackNavButtons ~= false)
            if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then r.ImGui_SetTooltip(ctx,'Show previous / next / range navigation buttons for tracks') end
            if c7 then state.showTrackNavButtons = v7; changed = true end
            local c7c, v7c = r.ImGui_Checkbox(ctx, 'Show Top Panel Toggle bar', state.showTopPanelToggleBar ~= false)
            if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then r.ImGui_SetTooltip(ctx,'Show or hide the row of panel toggle buttons at the top') end
            if c7c then state.showTopPanelToggleBar = v7c; changed = true end
            local c7b, v7b = r.ImGui_Checkbox(ctx, 'Hide Wet control', state.hideWetControl == true)
            if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then r.ImGui_SetTooltip(ctx,'Completely hide the global Wet (mix) knob control') end
            if c7b then state.hideWetControl = v7b; changed = true end
            r.ImGui_Separator(ctx)
            r.ImGui_TextDisabled(ctx, 'Panels:')
            local cp1, vp1 = r.ImGui_Checkbox(ctx, 'Replacement panel', state.showPanelReplacement ~= false)
            if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then r.ImGui_SetTooltip(ctx,'Toggle visibility of the Replacement (batch operations) panel') end
            if cp1 then state.showPanelReplacement = vp1; changed = true end
            local cp2, vp2 = r.ImGui_Checkbox(ctx, 'FX Instance Controls panel', state.showPanelSource ~= false)
            if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then r.ImGui_SetTooltip(ctx,'Toggle visibility of the per-instance Source FX control panel') end
            if cp2 then state.showPanelSource = vp2; changed = true end
            local cp3, vp3 = r.ImGui_Checkbox(ctx, 'FXChain Controls panel', state.showPanelFXChain ~= false)
            if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then r.ImGui_SetTooltip(ctx,'Toggle visibility of the FX Chain (preset/chain) panel') end
            if cp3 then state.showPanelFXChain = vp3; changed = true end
            local cp4, vp4 = r.ImGui_Checkbox(ctx, 'Chain Snapshots panel', state.showPanelTrackVersion ~= false)
            if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then r.ImGui_SetTooltip(ctx,'Toggle visibility of FX chain snapshot controls panel') end
            if cp4 then state.showPanelTrackVersion = vp4; changed = true end
            
            if r.ImGui_EndTabItem then r.ImGui_EndTabItem(ctx) end
          end
          
          if r.ImGui_BeginTabItem and r.ImGui_BeginTabItem(ctx, 'Style') then
            r.ImGui_Text(ctx, 'Rounding:')
            
            r.ImGui_SetNextItemWidth(ctx, 100)
            local cr2, vr2 = r.ImGui_SliderDouble(ctx, '##ButtonRounding', state.styleButtonRounding, 0.0, 15.0, '%.1f')
            if cr2 then state.styleButtonRounding = vr2; changed = true end
            r.ImGui_SameLine(ctx); r.ImGui_Text(ctx, 'Buttons')
            
            r.ImGui_SetNextItemWidth(ctx, 100)
            local cr3, vr3 = r.ImGui_SliderDouble(ctx, '##WindowRounding', state.styleWindowRounding, 0.0, 15.0, '%.1f')
            if cr3 then state.styleWindowRounding = vr3; changed = true end
            r.ImGui_SameLine(ctx); r.ImGui_Text(ctx, 'Window')
            
            r.ImGui_Separator(ctx)
            r.ImGui_Text(ctx, 'Button Colors:')
            
            local buttonColorInt = rgb_to_int(state.styleButtonColorR, state.styleButtonColorG, state.styleButtonColorB)
            r.ImGui_SetNextItemWidth(ctx, 200)
            local cc1, vc1 = r.ImGui_ColorEdit3(ctx, 'Button', buttonColorInt, r.ImGui_ColorEditFlags_NoInputs())
            if cc1 then 
              state.styleButtonColorR, state.styleButtonColorG, state.styleButtonColorB = int_to_rgb(vc1)
              changed = true 
            end
            
            local buttonHovColorInt = rgb_to_int(state.styleButtonHoveredR, state.styleButtonHoveredG, state.styleButtonHoveredB)
            r.ImGui_SetNextItemWidth(ctx, 200)
            local cc2, vc2 = r.ImGui_ColorEdit3(ctx, 'Button Hovered', buttonHovColorInt, r.ImGui_ColorEditFlags_NoInputs())
            if cc2 then 
              state.styleButtonHoveredR, state.styleButtonHoveredG, state.styleButtonHoveredB = int_to_rgb(vc2)
              changed = true 
            end
            
            local buttonActColorInt = rgb_to_int(state.styleButtonActiveR, state.styleButtonActiveG, state.styleButtonActiveB)
            r.ImGui_SetNextItemWidth(ctx, 200)
            local cc3, vc3 = r.ImGui_ColorEdit3(ctx, 'Button Active', buttonActColorInt, r.ImGui_ColorEditFlags_NoInputs())
            if cc3 then 
              state.styleButtonActiveR, state.styleButtonActiveG, state.styleButtonActiveB = int_to_rgb(vc3)
              changed = true 
            end
            
            r.ImGui_Separator(ctx)
            r.ImGui_Text(ctx, 'Background Colors:')
            
          
            local winBgHex = rgba_to_int(state.styleWindowBgR, state.styleWindowBgG, state.styleWindowBgB, state.styleWindowBgA)
            local winBgColorInt = rgba_hex_to_abgr(winBgHex)
            r.ImGui_SetNextItemWidth(ctx, 200)
            local cc4, vc4 = r.ImGui_ColorEdit4(ctx, 'Window Background', winBgColorInt, r.ImGui_ColorEditFlags_NoInputs())
            if cc4 then 
              
              local rgbaHex = abgr_to_rgba_hex(vc4)
              state.styleWindowBgR, state.styleWindowBgG, state.styleWindowBgB, state.styleWindowBgA = int_to_rgba(rgbaHex)
              changed = true 
            end
            
          
            local frameBgHex = rgba_to_int(state.styleFrameBgR, state.styleFrameBgG, state.styleFrameBgB, state.styleFrameBgA)
            local frameBgColorInt = rgba_hex_to_abgr(frameBgHex)
            r.ImGui_SetNextItemWidth(ctx, 200)
            local cc5, vc5 = r.ImGui_ColorEdit4(ctx, 'Frame Background', frameBgColorInt, r.ImGui_ColorEditFlags_NoInputs())
            if cc5 then 
            
              local rgbaHex = abgr_to_rgba_hex(vc5)
              state.styleFrameBgR, state.styleFrameBgG, state.styleFrameBgB, state.styleFrameBgA = int_to_rgba(rgbaHex)
              changed = true 
            end
            
            r.ImGui_Separator(ctx)
            
            
            if r.ImGui_Button(ctx, 'Save Style Settings') then
              save_user_settings()
              changed = false
            end
            r.ImGui_SameLine(ctx)
            if r.ImGui_Button(ctx, 'Reset Defaults') then
              local ns = EXT_NS
              local keys = {
                'TOOLTIPS','NAME_NOPREFIX','NAME_HIDEDEV','HDR_OPEN','REPL_OPEN','ACT_OPEN','SRC_OPEN',
                'IMG_SHOW','FXC_OPEN','TRV_OPEN','SHOW_RMS','SHOW_TRK_LIST','SHOW_TOP_PANEL_TOGGLES',
                'SHOW_TRK_NAV','HIDE_WET','PANEL_REPLACEMENT','PANEL_SOURCE','PANEL_FXCHAIN','PANEL_TRKVER',
                'STYLE_ROUNDING','STYLE_BTN_ROUNDING','STYLE_WIN_ROUNDING','STYLE_FRAME_ROUNDING',
                'STYLE_GRAB_ROUNDING','STYLE_TAB_ROUNDING','STYLE_BTN_R','STYLE_BTN_G','STYLE_BTN_B',
                'STYLE_BTN_HOV_R','STYLE_BTN_HOV_G','STYLE_BTN_HOV_B','STYLE_BTN_ACT_R','STYLE_BTN_ACT_G','STYLE_BTN_ACT_B',
                'STYLE_WIN_BG_R','STYLE_WIN_BG_G','STYLE_WIN_BG_B','STYLE_WIN_BG_A',
                'STYLE_FRAME_BG_R','STYLE_FRAME_BG_G','STYLE_FRAME_BG_B','STYLE_FRAME_BG_A',
                'STYLE_FRAME_HOV_R','STYLE_FRAME_HOV_G','STYLE_FRAME_HOV_B','STYLE_FRAME_HOV_A',
                'STYLE_FRAME_ACT_R','STYLE_FRAME_ACT_G','STYLE_FRAME_ACT_B','STYLE_FRAME_ACT_A'
              }
              for _,k in ipairs(keys) do r.SetExtState(ns, k, '', true) end
              state.tooltips = true
              state.nameNoPrefix = false
              state.nameHideDeveloper = false
              state.showScreenshot = true
              state.showTrackList = true
              state.showTopPanelToggleBar = true
              state.showTrackNavButtons = true
              state.showPanelReplacement = true
              state.showPanelSource = true
              state.showPanelFXChain = true
              state.showPanelTrackVersion = true
              state.styleRounding = state.styleRounding or 4
              state.styleButtonRounding = state.styleButtonRounding or 4
              state.styleWindowRounding = state.styleWindowRounding or 6
              state.styleFrameRounding = state.styleFrameRounding or 4
              state.styleGrabRounding = state.styleGrabRounding or 4
              state.styleTabRounding = state.styleTabRounding or 4
              state.styleButtonColorR, state.styleButtonColorG, state.styleButtonColorB = 0.30,0.30,0.30
              state.styleButtonHoveredR, state.styleButtonHoveredG, state.styleButtonHoveredB = 0.38,0.38,0.38
              state.styleButtonActiveR, state.styleButtonActiveG, state.styleButtonActiveB = 0.20,0.20,0.20
              state.styleWindowBgR, state.styleWindowBgG, state.styleWindowBgB, state.styleWindowBgA = 0.14,0.14,0.14,1.0
              state.styleFrameBgR, state.styleFrameBgG, state.styleFrameBgB, state.styleFrameBgA = 0.12,0.12,0.12,1.0
              state.styleFrameBgHoveredR, state.styleFrameBgHoveredG, state.styleFrameBgHoveredB, state.styleFrameBgHoveredA = 0.18,0.18,0.18,1.0
              state.styleFrameBgActiveR, state.styleFrameBgActiveG, state.styleFrameBgActiveB, state.styleFrameBgActiveA = 0.16,0.16,0.16,1.0
              save_user_settings()
            end
            
            if r.ImGui_EndTabItem then r.ImGui_EndTabItem(ctx) end
          end
          
          if r.ImGui_EndTabBar then r.ImGui_EndTabBar(ctx) end
        else
          local c1, v1 = r.ImGui_Checkbox(ctx, 'Tooltips', state.tooltips)
          if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then r.ImGui_SetTooltip(ctx,'Enable or disable all tooltips globally') end
          if c1 then state.tooltips = v1; changed = true end
          local c2, v2 = r.ImGui_Checkbox(ctx, 'Names without prefix', state.nameNoPrefix)
          if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then r.ImGui_SetTooltip(ctx,'Remove vendor / category prefixes in displayed FX names') end
          if c2 then state.nameNoPrefix = v2; changed = true end
          local c3, v3 = r.ImGui_Checkbox(ctx, 'Hide developer name', state.nameHideDeveloper)
          if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then r.ImGui_SetTooltip(ctx,'Omit the developer name portion from FX titles') end
          if c3 then state.nameHideDeveloper = v3; changed = true end
          local c4, v4 = r.ImGui_Checkbox(ctx, 'Plugin image', state.showScreenshot)
          if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then r.ImGui_SetTooltip(ctx,'Show or hide captured plugin GUI image') end
          if c4 then
            state.showScreenshot = v4; changed = true
            if not v4 then release_screenshot() end
          end
          local c5, v5 = r.ImGui_Checkbox(ctx, 'Show R/M/S buttons', state.showRMSButtons)
          if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then r.ImGui_SetTooltip(ctx,'Display Record / Mute / Solo buttons alongside track entries') end
          if c5 then state.showRMSButtons = v5; changed = true end
          local c6, v6 = r.ImGui_Checkbox(ctx, 'Show Track FX list', state.showTrackList ~= false)
          if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then r.ImGui_SetTooltip(ctx,'Toggle track FX list visibility') end
          if c6 then state.showTrackList = v6; changed = true end
          local c7, v7 = r.ImGui_Checkbox(ctx, 'Show Track Nav buttons', state.showTrackNavButtons ~= false)
          if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then r.ImGui_SetTooltip(ctx,'Toggle previous/next track navigation buttons') end
          if c7 then state.showTrackNavButtons = v7; changed = true end
          
          if changed then save_user_settings() end
        end
        
        
        r.ImGui_Separator(ctx)
        if r.ImGui_Button(ctx, 'Close') then state.showSettings = false end
      end
  pcall(r.ImGui_End, ctx)
  pop_app_style(settingsStylePush)
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
  r.ImGui_Text(ctx, 'TK FX Slots Single Track - Help / Usage Guide')
  r.ImGui_Separator(ctx)

  r.ImGui_TextColored(ctx, col_u32(0.85,0.85,1,1), 'Overview')
  r.ImGui_TextWrapped(ctx, 'Manage, replace and audition FX instances across one or many tracks. Provides A/B testing, batch slot operations, FX chain preset management, drag+drop slot reordering and panel customization.')
  r.ImGui_Dummy(ctx,0,4)

  r.ImGui_TextColored(ctx, col_u32(0.9,0.8,0.6,1), 'Panels / Sections')
  r.ImGui_BulletText(ctx, 'FX Instance Controls (Source): Shows controls for currently selected (source) FX: bypass/offline/delta toggles, wet mix knob, A/B prepare & toggle, commit (Replace Source).')
  r.ImGui_BulletText(ctx, 'Replacement Panel: Choose replacement FX or placeholder; batch Replace/Delete/Move Up/Down All; targeted slot Replace/Add with conditional safety.')
  r.ImGui_BulletText(ctx, 'FX Chain Panel: Save current chain, refresh list, apply or replace chains for current / selected / all tracks (confirmation for destructive actions).')
  r.ImGui_BulletText(ctx, 'Snapshots / Navigation (optional): Previous / next / jump to track index; FX chain snapshot panel if enabled.')
  r.ImGui_BulletText(ctx, 'Track FX List (optional left panel): Per‑track FX rows with status & direct mouse interactions (see Mouse Reference).')
  r.ImGui_Dummy(ctx,0,4)

  r.ImGui_TextColored(ctx, col_u32(0.9,0.8,0.6,1), 'Selecting / Managing the Source FX')
  r.ImGui_TextWrapped(ctx, 'There is no separate "Source" button anymore: simply Left‑Click (no modifiers) an FX row in the Track FX List to set it as the active Source. All replace / delete / move operations target this FX name & index (subject to scope).')
  r.ImGui_Dummy(ctx,0,2)

  r.ImGui_TextColored(ctx, col_u32(0.9,0.8,0.6,1), 'Replacement Selection')
  r.ImGui_BulletText(ctx, 'Pick from list / browser: Internal filtered list or full REAPER browser (button).')
  r.ImGui_BulletText(ctx, 'Placeholder mode: Inserts a dummy FX and optionally renames it (staging marker).')
  r.ImGui_BulletText(ctx, 'Custom name field: Overrides display (useful with placeholders).')
  r.ImGui_Dummy(ctx,0,2)

  r.ImGui_TextColored(ctx, col_u32(0.9,0.8,0.6,1), 'Chain Snapshots (FX Chain Only)')
  r.ImGui_TextWrapped(ctx,'Capture the current FX chain state (order, enabled/offline flags, parameter values, FX names). Apply snapshots to instantly revert or compare alternate processing chains.')
  r.ImGui_BulletText(ctx,'New Snapshot: Stores current chain as a named snapshot (no items, sends, volumes, envelopes).')
  r.ImGui_BulletText(ctx,'Apply Selected: Overwrites current chain with the chosen snapshot.')
  r.ImGui_BulletText(ctx,'List interactions: Click select / Double-click apply / Right-click menu (Apply, Rename, Delete).')
  r.ImGui_BulletText(ctx,'Scope: This is not a full track version system—only FX chain state is stored.')
  r.ImGui_Dummy(ctx,0,2)
  r.ImGui_TextColored(ctx, col_u32(0.9,0.8,0.6,1), 'A/B Testing Workflow')
  r.ImGui_BulletText(ctx, 'A/B Replace button: First press snapshots Source+Replacement (prepare). Next presses toggle which side is active (A=original, B=replacement).')
  r.ImGui_BulletText(ctx, 'Replace Source: Commits the currently active side over the original slot and clears A/B state.')
  r.ImGui_BulletText(ctx, 'Auto Reset: Changing the source FX or invalidating the prepared pair resets A/B.')
  r.ImGui_Dummy(ctx,0,2)

  r.ImGui_TextColored(ctx, col_u32(0.9,0.8,0.6,1), 'Batch & Slot Operations')
  r.ImGui_BulletText(ctx, 'Replace all / Delete all / Move Up/Down All: Act on every instance of the Source FX (or only selected tracks when that scope is enabled).')
  r.ImGui_BulletText(ctx, 'Slot Replace/Add: Force action at an explicit slot index across tracks.')
  r.ImGui_BulletText(ctx, 'Only if slot is source: Skip slots whose current FX name does not match the Source (safety).')
  r.ImGui_BulletText(ctx, 'Selected track(s) Only: Restrict operations to currently selected tracks instead of project‑wide.')
  r.ImGui_Dummy(ctx,0,2)

  r.ImGui_TextColored(ctx, col_u32(0.9,0.8,0.6,1), 'Wet / Mix Control')
  r.ImGui_BulletText(ctx, 'Drag knob: Adjust wet mix (if FX supports global wet).')
  r.ImGui_BulletText(ctx, 'Double‑Click: Set 100% wet. Right‑Click: Set 50%.')
  r.ImGui_Dummy(ctx,0,2)

  r.ImGui_TextColored(ctx, col_u32(0.9,0.8,0.6,1), 'Delta / Bypass / Offline')
  r.ImGui_BulletText(ctx, 'Bypass (B): Toggle enable state (keeps FX loaded).')
  r.ImGui_BulletText(ctx, 'Offline (O): Fully unloads processing (saves CPU/RAM).')
  r.ImGui_BulletText(ctx, 'Delta: If supported by plugin, isolates difference signal for critical listening.')
  r.ImGui_Dummy(ctx,0,2)

  r.ImGui_TextColored(ctx, col_u32(0.9,0.8,0.6,1), 'FX Chain Management')
  r.ImGui_BulletText(ctx, 'Save: Write current track chain to .RfxChain.')
  r.ImGui_BulletText(ctx, 'Refresh: Re-scan chain folder from disk.')
  r.ImGui_BulletText(ctx, 'Apply: Append chain FX to target(s). Replace: Clear then load chain (confirmation).')
  r.ImGui_BulletText(ctx, 'Targets: Current, selected, or all tracks (asks before large/global destructive actions).')
  r.ImGui_Dummy(ctx,0,2)

  r.ImGui_TextColored(ctx, col_u32(0.9,0.8,0.6,1), 'Navigation & Panels')
  r.ImGui_BulletText(ctx, 'Track Nav (⟪ ◀ Go ▶ ⟫): Step previous / next or jump by index.')
  r.ImGui_BulletText(ctx, 'Toggle Bar: One‑click show/hide for major panels (can be hidden in Settings).')
  r.ImGui_BulletText(ctx, 'Settings: Panel visibility, tooltip enable, FX name formatting, wet knob, track buttons, image capture.')
  r.ImGui_Dummy(ctx,0,2)

  r.ImGui_TextColored(ctx, col_u32(0.9,0.8,0.6,1), 'Placeholders')
  r.ImGui_TextWrapped(ctx, 'Enable "Use placeholder" to insert a dummy slot marker. Provide a custom display label to mark intent (e.g. "(SAT Comp Here)" ). Later you can batch replace placeholders with real FX.')
  r.ImGui_Dummy(ctx,0,2)

  r.ImGui_TextColored(ctx, col_u32(0.9,0.8,0.6,1), 'Mouse & Modifier Reference')
  r.ImGui_BulletText(ctx, 'FX Row (left panel list):')
  r.ImGui_TextWrapped(ctx, '  Left-Click: select as Source | Alt+Click: arm delete (confirmation phase) | Shift+Click: toggle bypass | Ctrl+Shift+Click: toggle offline | Right-Click: open/close plugin UI (float/embedded cycle) | Drag: reorder (drop on another row to move).')
  r.ImGui_BulletText(ctx, 'FX Row Buttons:')
  r.ImGui_TextWrapped(ctx, '  B = bypass toggle, O = offline toggle (these reflect per-row state; tooltips show when enabled).')
  r.ImGui_BulletText(ctx, 'Track Header Bar:')
  r.ImGui_TextWrapped(ctx, '  Click track name header to expand/collapse its FX list (multi-track mode if enabled).')
  r.ImGui_BulletText(ctx, 'Record / Mute / Solo (R/M/S) Buttons:')
  r.ImGui_TextWrapped(ctx, '  R: Click = arm toggle.  M: Click = mute; Ctrl+Click = unmute all; Alt+Click = mute all others; Ctrl+Alt+Click = exclusive mute.  S: Click = solo; Ctrl+Click = unsolo all; Ctrl+Shift+Click = solo defeat; Ctrl+Alt+Click = exclusive solo.')
  r.ImGui_BulletText(ctx, 'A/B Replace Button:')
  r.ImGui_TextWrapped(ctx, '  First press prepares pair (captures original + replacement); subsequent presses toggle active side. State auto-clears when source changes.')
  r.ImGui_BulletText(ctx, 'Wet Knob:')
  r.ImGui_TextWrapped(ctx, '  Drag = adjust | Double-Click = 100% | Right-Click = 50%.')
  r.ImGui_BulletText(ctx, 'FX Chain List:')
  r.ImGui_TextWrapped(ctx, '  Right-Click chain entry (where available) for context popup; filters and buttons as labeled.')
  r.ImGui_BulletText(ctx, 'Drag & Drop:')
  r.ImGui_TextWrapped(ctx, '  Begin drag on FX row text, drop onto another row to move (internal copy + delete). Undo supported.')
  r.ImGui_BulletText(ctx, 'Slot Index Field:')
  r.ImGui_TextWrapped(ctx, '  Enter 1-based slot number for Slot Replace/Add batch actions.')
  r.ImGui_Dummy(ctx,0,2)

  r.ImGui_TextColored(ctx, col_u32(0.9,0.8,0.6,1), 'Safety & Undo')
  r.ImGui_BulletText(ctx, 'Destructive actions (global replace / chain replace / delete all) wrapped in Undo & may prompt.')
  r.ImGui_BulletText(ctx, 'Drag reorders and A/B operations are undoable.')
  r.ImGui_Dummy(ctx,0,2)

  r.ImGui_TextColored(ctx, col_u32(0.9,0.8,0.6,1), 'Tips')
  r.ImGui_BulletText(ctx, 'Enable tooltips (Settings) for contextual guidance while learning.')
  r.ImGui_BulletText(ctx, 'Use Selected Track(s) scope before applying project‑wide changes.')
  r.ImGui_BulletText(ctx, 'Prepare A/B early to compare subtle processing tweaks.')
  r.ImGui_BulletText(ctx, 'Placeholders help plan future routing / processing stages.')
  r.ImGui_Dummy(ctx,0,4)

        if r.ImGui_Button(ctx, 'Close') then state.showHelp = false end
      end
      pcall(r.ImGui_End, ctx)
      if openH == false then state.showHelp = false end
    else
      state.showHelp = false
    end
  end

  if state.showPicker and ctx then
    ensure_picker_items()
    local picker_begun = false
  local okP, openP
  local pickerStylePush = push_app_style()
  local ok_call, err = pcall(function()
  if is_context_valid(ctx) then
  r.ImGui_SetNextWindowSize(ctx, 600, 440, r.ImGui_Cond_Appearing())
  r.ImGui_SetNextWindowSizeConstraints(ctx, 480, 340, 1000, 800)
  else
    return
  end
  local picker_flags = r.ImGui_WindowFlags_NoCollapse() | r.ImGui_WindowFlags_NoScrollbar() | r.ImGui_WindowFlags_NoTitleBar()
  okP, openP = r.ImGui_Begin(ctx, 'FX Picker##TK_FX_Slots_SingleTrack', true, picker_flags)
      picker_begun = true
    end)
    if ok_call and picker_begun then
      if okP then
        
  r.ImGui_Separator(ctx)
  r.ImGui_Text(ctx, 'FX Picker')
  if state.pickerSearchAll == nil then state.pickerSearchAll = false end
  r.ImGui_SameLine(ctx)
  r.ImGui_SetNextItemWidth(ctx, 200)
  local chgF, ftxt = r.ImGui_InputTextWithHint(ctx, '##fxpick_filter', 'Search...', state.pickerFilter or '')
  if chgF then state.pickerFilter = ftxt end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, 'x##clr_fxpick', 18, 0) then
    state.pickerFilter = ''
  end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, 'Clear filter') end
  r.ImGui_SameLine(ctx)
  local chgAll, all = r.ImGui_Checkbox(ctx, 'All', state.pickerSearchAll)
  if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then r.ImGui_SetTooltip(ctx,'Search across all FX categories instead of the current filter') end
  if chgAll then state.pickerSearchAll = all end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, 'Search all sections (ignore current selection)') end
  local filter_l = (state.pickerFilter or ''):lower()
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, 'Refresh') then
          local items, perr = load_plugin_items()
          if items then
            state.pickerItems, state.pickerErr = items, nil
            state._pickerStructBuilt = false
            state.pickerLoadedFromCache = false
            local ok = pcall(write_cache_items, items)
            state.pickerStatusMsg = ok and 'List rebuilt & cached' or 'List rebuilt (cache write failed)'
          else
            state.pickerErr = perr or 'Failed to build list'
            state.pickerStatusMsg = nil
          end
        end
  if state.pickerStatusMsg then
          r.ImGui_SameLine(ctx)
          r.ImGui_TextColored(ctx, 0x55FF55FF, state.pickerStatusMsg)
        end
        if state.pickerErr then
          r.ImGui_SameLine(ctx)
          r.ImGui_TextColored(ctx, 0xFF6666FF, state.pickerErr)
        end

        local function parse_type(add)
          return parse_addname_type and parse_addname_type(add) or 'OTHER'
        end
        local function extract_dev(add)
          if not add then return 'Unknown' end
          local last
          for m in add:gmatch('%(([^)]+)%)') do
            if not m:match('^%d+in') and not m:match('^%d+out') and not m:match('^%d+ch') then last = m end
          end
            return last or 'Unknown'
        end
        local function extract_cat(it)
          local p = it.path or ''
          local c = p:match('^([^/]+)/')
          if not c or c == '' then
            c = parse_type(it.addname or it.display)
          end
          return c or 'Other'
        end

        local function ensure_structure()
          if state._pickerStructBuilt then return end
          local list, cat_tbl, dev_list = FX_LIST_TEST, CAT_TEST, FX_DEV_LIST_FILE
          if (not cat_tbl or #cat_tbl == 0) and type(ReadFXFile)=='function' then
            local ok,a,b,c = pcall(ReadFXFile)
            if ok then list, cat_tbl, dev_list = a,b,c end
          end
          if (not cat_tbl or #cat_tbl == 0) and type(GetFXTbl)=='function' then
            local ok,a,b,c = pcall(GetFXTbl)
            if ok then list, cat_tbl, dev_list = a,b,c end
          end
          if not cat_tbl or #cat_tbl == 0 then return end
          local favorites = {}
          local types = {}
          local foldersRoot = { name='ROOT', children={}, items={} }
          local categories = {} 
          local devs = {}      

          if type(dev_list)=='table' then
            for _, d in ipairs(dev_list) do if d and d~='' then devs[d] = {} end end
          end

          local exclude_generic = {
            ['FAVORITES']=true,['ALL PLUGINS']=true,['FOLDERS']=true,
            ['FX CHAINS']=true,['TRACK TEMPLATES']=true,
          }
          for i = 1, #cat_tbl do
            local cEntry = cat_tbl[i]
            if cEntry.name == 'FAVORITES' then
              for j=1,#cEntry.list do favorites[#favorites+1] = { addname = cEntry.list[j], display = cEntry.list[j] } end
            elseif cEntry.name == 'ALL PLUGINS' then
              for j=1,#cEntry.list do
                local subtype = cEntry.list[j]
                if subtype.name and subtype.fx then
                  types[subtype.name] = {}
                  for k=1,#subtype.fx do
                    types[subtype.name][#types[subtype.name]+1] = { addname = subtype.fx[k], display = subtype.fx[k] }
                  end
                end
              end
            elseif cEntry.name == 'DEVELOPER' then
              for j=1,#cEntry.list do
                local devEntry = cEntry.list[j]
                if type(devEntry)=='table' and devEntry.name and devEntry.fx then
                  local arr = devs[devEntry.name] or {}
                  for _, fxn in ipairs(devEntry.fx) do
                    arr[#arr+1] = { addname = fxn, display = fxn }
                  end
                  devs[devEntry.name] = arr
                end
              end
            elseif cEntry.name == 'CATEGORY' then
              for j=1,#cEntry.list do
                local catEntry = cEntry.list[j]
                if type(catEntry)=='table' and catEntry.name and catEntry.fx then
                  local arr = categories[catEntry.name] or {}
                  for _, fxn in ipairs(catEntry.fx) do
                    arr[#arr+1] = { addname = fxn, display = fxn }
                  end
                  categories[catEntry.name] = arr
                end
              end
            elseif cEntry.name == 'FOLDERS' then
              local function add_folder(node, folder_entry)
                local child = node.children[folder_entry.name] or { name=folder_entry.name, children={}, items={} }
                node.children[folder_entry.name] = child
                if type(folder_entry.fx) == 'table' then
                  for _, fxn in ipairs(folder_entry.fx) do
                    child.items[#child.items+1] = { addname = fxn, display = fxn }
                    if folder_entry.name and folder_entry.name:lower() == 'favorites' then
                      if not fxn:lower():find('%.rfxchain$') then 
                        favorites[#favorites+1] = { addname = fxn, display = fxn }
                      end
                    end
                  end
                end
                if folder_entry.list then
                  for _, v in ipairs(folder_entry.list) do
                    if type(v) == 'table' and v.name and v.list then
                      add_folder(child, v)
                    elseif type(v) == 'string' then
                      child.items[#child.items+1] = { addname = v, display = v }
                    end
                  end
                end
              end
              for j=1,#cEntry.list do
                local folder_entry = cEntry.list[j]
                if type(folder_entry)=='table' and folder_entry.name then
                  add_folder(foldersRoot, folder_entry)
                end
              end
            else
            end
          end

          if next(devs) == nil and list and dev_list then
            local lowerDev = {}
            for _, d in ipairs(dev_list) do lowerDev[d] = d:lower() devs[d]={} end
            for _, pname in ipairs(list) do
              local pl = pname:lower()
              for _, d in ipairs(dev_list) do
                if pl:find(lowerDev[d],1,true) then devs[d][#devs[d]+1]={ addname=pname, display=pname } break end
              end
            end
          end
          for d, arr in pairs(devs) do
            if type(arr) == 'table' and #arr == 0 then
              devs[d] = nil
            end
          end
          if state.fxPickerSection and state.fxPickerSection:match('^dev:') then
            local curDev = state.fxPickerSection:sub(5)
            if not devs[curDev] then state.fxPickerSection = 'Favorites' end
          end

          if not state.cherryPicksLoaded then
            local s = r.GetExtState(EXT_NS, 'CHERRYPICKS') or ''
            state.cherryPicks = {}
            for line in s:gmatch('[^\n]+') do
              local name = line:match('^%s*(.-)%s*$')
              if name ~= '' then
                state.cherryPicks[#state.cherryPicks+1] = { addname = name, display = name }
              end
            end
            state.cherryPicksLoaded = true
          end
          state.fxPickerStruct = {
            favorites = favorites,
            types = types,
            developers = devs,
            categories = categories,
            folders = foldersRoot,
            cherry = state.cherryPicks or {},
          }
          state.fxPickerSection = state.fxPickerSection or 'Favorites'
          state._pickerStructBuilt = true
        end

        ensure_structure()

  r.ImGui_Separator(ctx)

  local availW, availH = r.ImGui_GetContentRegionAvail(ctx)
  local leftW = 170
  local footerH = 30 
  local listH = math.max(150, availH - footerH)
        if r.ImGui_BeginChild(ctx, 'fxpick_sections', leftW, listH) then
          local function selectable_section(label, key)
            local sel = (state.fxPickerSection == key)
            if r.ImGui_Selectable(ctx, label .. (sel and ' *' or ''), sel) then
              state.fxPickerSection = key
              state.fxPickerFolderPath = nil
            end
          end
          selectable_section('Cherry Picks', 'Cherry')
          selectable_section('Favorites', 'Favorites')
          if r.ImGui_TreeNode(ctx, 'All Plugins##fxpick_types') then
            local type_keys = {}
            for k in pairs(state.fxPickerStruct.types or {}) do type_keys[#type_keys+1] = k end
            table.sort(type_keys)
            for _, t in ipairs(type_keys) do
              local key = 'type:' .. t
              local sel = (state.fxPickerSection == key)
              if r.ImGui_Selectable(ctx, t .. (sel and ' *' or ''), sel) then state.fxPickerSection = key end
            end
            r.ImGui_TreePop(ctx)
          end
          if r.ImGui_TreeNode(ctx, 'Developer##fxpick_devs') then
            local dev_keys = {}
            for k in pairs(state.fxPickerStruct.devs or state.fxPickerStruct.developers or {}) do dev_keys[#dev_keys+1] = k end
            table.sort(dev_keys, function(a,b) return a:lower()<b:lower() end)
            for _, d in ipairs(dev_keys) do
              local key = 'dev:' .. d
              local sel = (state.fxPickerSection == key)
              if r.ImGui_Selectable(ctx, d .. (sel and ' *' or ''), sel) then state.fxPickerSection = key end
            end
            r.ImGui_TreePop(ctx)
          end
            if r.ImGui_TreeNode(ctx, 'Category##fxpick_cat') then
              local cat_keys = {}
              for k in pairs(state.fxPickerStruct.categories or {}) do cat_keys[#cat_keys+1] = k end
              table.sort(cat_keys, function(a,b) return a:lower()<b:lower() end)
              for _, c in ipairs(cat_keys) do
                local key = 'cat:' .. c
                local sel = (state.fxPickerSection == key)
                if r.ImGui_Selectable(ctx, c .. (sel and ' *' or ''), sel) then state.fxPickerSection = key end
              end
              r.ImGui_TreePop(ctx)
            end
          if r.ImGui_TreeNode(ctx, 'Folders##fxpick_folders') then
            local function draw_folder(node, pathPrefix)
              local children_names = {}
              for name in pairs(node.children or {}) do children_names[#children_names+1]=name end
              table.sort(children_names, function(a,b) return a:lower()<b:lower() end)
              for _, childName in ipairs(children_names) do
                local child = node.children[childName]
                local fullPath = pathPrefix and (pathPrefix .. '/' .. childName) or childName
                local hasKids = (child.children and next(child.children)) ~= nil
                local label = childName
                if hasKids then
                  local open = r.ImGui_TreeNode(ctx, childName .. '##fold_'..fullPath)
                  if r.ImGui_IsItemClicked(ctx,0) then
                    state.fxPickerSection = 'folder'
                    state.fxPickerFolderPath = fullPath
                  end
                  if open then
                    draw_folder(child, fullPath)
                    r.ImGui_TreePop(ctx)
                  end
                else
                  local sel = (state.fxPickerSection=='folder' and state.fxPickerFolderPath==fullPath)
                  if r.ImGui_Selectable(ctx, label .. (sel and ' *' or ''), sel) then
                    state.fxPickerSection = 'folder'
                    state.fxPickerFolderPath = fullPath
                  end
                end
              end
            end
            draw_folder(state.fxPickerStruct.folders or {children={}}, nil)
            r.ImGui_TreePop(ctx)
          end
          r.ImGui_EndChild(ctx)
        end

        r.ImGui_SameLine(ctx)
        if r.ImGui_BeginChild(ctx, 'fxpick_items', availW-leftW-6, listH) then
          local itemsToShow = {}
          local section = state.fxPickerSection
          local struct = state.fxPickerStruct or {}
          if state.pickerSearchAll and filter_l ~= '' then
            local uniq = {}
            local function add_items(arr)
              if not arr then return end
              for _, it in ipairs(arr) do
                local key = it.addname or it.display
                if key and not uniq[key] then uniq[key] = true; itemsToShow[#itemsToShow+1] = it end
              end
            end
         
            add_items(struct.favorites)
          
            if struct.types then for _, arr in pairs(struct.types) do add_items(arr) end end
        
            if struct.developers then for _, arr in pairs(struct.developers) do add_items(arr) end end
         
            if struct.categories then for _, arr in pairs(struct.categories) do add_items(arr) end end
         
            local function walk_folder(node)
              if not node then return end
              add_items(node.items)
              if node.children then for _, child in pairs(node.children) do walk_folder(child) end end
            end
            walk_folder(struct.folders)
          else
            if section == 'Favorites' then
              itemsToShow = struct.favorites or {}
            elseif section == 'Cherry' then
              itemsToShow = struct.cherry or {}
            elseif section and section:match('^type:') then
              local t = section:sub(6)
              itemsToShow = struct.types and struct.types[t] or {}
            elseif section and section:match('^dev:') then
              local d = section:sub(5)
              itemsToShow = (struct.devs and struct.devs[d]) or (struct.developers and struct.developers[d]) or {}
            elseif section and section:match('^cat:') then
              local c = section:sub(5)
              itemsToShow = struct.categories and struct.categories[c] or {}
            elseif section == 'folder' and state.fxPickerFolderPath then
              local node = struct.folders
              if node then
                for seg in state.fxPickerFolderPath:gmatch('[^/]+') do
                  if node.children then node = node.children[seg] else node = nil break end
                end
                if node and node.items then itemsToShow = node.items end
              end
            end
          end
          if filter_l ~= '' then
            local filtered = {}
            for _, it in ipairs(itemsToShow) do
              local disp = (it.display or it.addname or ''):lower()
              local add  = (it.addname or ''):lower()
              if disp:find(filter_l,1,true) or add:find(filter_l,1,true) then
                filtered[#filtered+1] = it
              end
            end
            itemsToShow = filtered
          end
          table.sort(itemsToShow, function(a,b) return (a.display or a.addname or ''):lower() < (b.display or b.addname or ''):lower() end)
          if #itemsToShow == 0 then
            r.ImGui_TextDisabled(ctx, '(no items)')
          else
            for i, it in ipairs(itemsToShow) do
              local disp = it.display or it.addname
              local add  = it.addname or disp
              local maxLabelW = (availW - leftW - 80)
              if maxLabelW and maxLabelW > 100 then
                local tw = select(1, r.ImGui_CalcTextSize(ctx, disp))
                if tw > maxLabelW then
                  local trunc = disp
                  local cut = #trunc
                  while cut > 4 do
                    cut = cut - 1
                    trunc = trunc:sub(1, cut) .. '…'
                    if select(1, r.ImGui_CalcTextSize(ctx, trunc)) <= maxLabelW then break end
                  end
                  disp = trunc
                end
              end
              local selected = (state.replaceWith == add)
              if r.ImGui_Selectable(ctx, (disp .. '##fxp_'..i), selected) then
                state.pickerChosenAdd = add
                state.replaceWith = add
                state.replaceDisplay = disp
                state.pendingMessage = 'Chosen: '..tostring(disp)
              end
              if r.ImGui_BeginPopupContextItem(ctx, '##fxp_ctx_'..i) then
                local isCherry = false
                if state.cherryPicks then
                  for _, cp in ipairs(state.cherryPicks) do if (cp.addname or cp.display) == add then isCherry = true break end end
                end
                if not isCherry and r.ImGui_MenuItem(ctx, 'Add to Cherry Picks') then
                  state.cherryPicks = state.cherryPicks or {}
                  state.cherryPicks[#state.cherryPicks+1] = { addname = add, display = (it.display or add) }
                  local lines = {}
                  for _, cp in ipairs(state.cherryPicks) do lines[#lines+1] = cp.addname or cp.display end
                  r.SetExtState(EXT_NS, 'CHERRYPICKS', table.concat(lines, '\n'), true)
                  if state.fxPickerStruct then state.fxPickerStruct.cherry = state.cherryPicks end
                elseif isCherry and r.ImGui_MenuItem(ctx, 'Remove from Cherry Picks') then
                  for idx, cp in ipairs(state.cherryPicks) do
                    local nm = cp.addname or cp.display
                    if nm == add then table.remove(state.cherryPicks, idx) break end
                  end
                  local lines = {}
                  for _, cp in ipairs(state.cherryPicks) do lines[#lines+1] = cp.addname or cp.display end
                  r.SetExtState(EXT_NS, 'CHERRYPICKS', table.concat(lines, '\n'), true)
                  if state.fxPickerStruct then state.fxPickerStruct.cherry = state.cherryPicks end
                end
                r.ImGui_EndPopup(ctx)
              end
            end
          end
          r.ImGui_EndChild(ctx)
        end

  r.ImGui_Separator(ctx)
  if r.ImGui_Button(ctx, 'Close', 70, 0) then openP = false end
      end
  pcall(r.ImGui_End, ctx)
  if pickerStylePush then pop_app_style(pickerStylePush) end
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
    
    save_user_settings()
  end
end

local function safe_draw()
  local success, error_msg = pcall(draw)
  if not success then
    local error_text = tostring(error_msg or 'Unknown error')
    r.ShowConsoleMsg("Draw error: " .. error_text .. "\n")
    
    r.ShowConsoleMsg("Recreating context due to error...\n")
    ctx = r.ImGui_CreateContext(SCRIPT_NAME)
    styleStackDepth.colors = 0
    styleStackDepth.vars = 0
    windowStack.depth = 0
    
    r.defer(safe_draw)
  end
end

local function main()
  init_fx_parser()
  load_window_size()
  load_user_settings()
  favs_load()
  blanks_load()
  load_track_versions()
  
  safe_draw()
end

r.atexit(cleanup_resources)

main()
