-- @version 0.2.0
-- @author: TouristKiller (with assistance from Robert ;o) )
-- @changelog:
--[[     
A Lot of changes... hahahaha!

== THNX TO MASTER SEXAN FOR HIS FX PARSER ==

]]--        
--------------------------------------------------------------------------


local r = reaper
local SCRIPT_NAME = 'TK FX Slots Single Track'
local SCRIPT_VERSION = '0.2.0'

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

local ctx = nil
local DND_FX_PAYLOAD = 'TK_FX_ROW_SINGLE'

local ctx = nil
local styleStackDepth = {colors = 0, vars = 0} 

local function debug_stack_state(location)
  if styleStackDepth.colors > 0 or styleStackDepth.vars > 0 then
    r.ShowConsoleMsg(string.format("[%s] Stack depth: colors=%d, vars=%d\n", 
      location or "Unknown", styleStackDepth.colors, styleStackDepth.vars))
  end
end

local function is_context_valid(ctx)
  if not ctx then return false end
  
  local success = pcall(function()
    if r.ImGui_ValidatePtr then
      return r.ImGui_ValidatePtr(ctx, 'ImGui_Context*')
    else
      if r.ImGui_GetVersion then 
        r.ImGui_GetVersion()
      end
      return true
    end
  end)
  
  return success
end

local function cleanup_resources()
  if ctx then
    if styleStackDepth.colors > 0 and r.ImGui_PopStyleColor then
      pcall(r.ImGui_PopStyleColor, ctx, styleStackDepth.colors)
      styleStackDepth.colors = 0
    end
    if styleStackDepth.vars > 0 and r.ImGui_PopStyleVar then  
      pcall(r.ImGui_PopStyleVar, ctx, styleStackDepth.vars)
      styleStackDepth.vars = 0
    end
    
    if r.ImGui_DestroyContext then
      r.ImGui_DestroyContext(ctx)
    end
    ctx = nil
  end
end

local function init_context()
  if ctx then
    if r.ImGui_DestroyContext then
      pcall(r.ImGui_DestroyContext, ctx)
    end
    ctx = nil
  end
  
  styleStackDepth.colors = 0
  styleStackDepth.vars = 0
  
  if not ctx then
    if r.ImGui_CreateContext then
      ctx = r.ImGui_CreateContext(SCRIPT_NAME)
      if not ctx then
        r.ShowMessageBox('Failed to create ImGui context. Please check your ReaImGui installation.', 'Error', 0)
        return false
      end
    else
      r.ShowMessageBox('ReaImGui extension not found. Please install ReaImGui to use this script.', 'Error', 0)
      return false
    end
  end
  
  if is_context_valid(ctx) then
    return true
  else
    r.ShowMessageBox('ImGui context is invalid. Please restart the script.', 'Error', 0)
    return false
  end
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
  nameNoPrefix = false,
  nameHideDeveloper = false,
  
  -- Header states (collapsible sections)
  trackHeaderOpen = true,
  replHeaderOpen = true,
  actionHeaderOpen = true,
  sourceHeaderOpen = true,
  fxChainHeaderOpen = true,
  trackVersionHeaderOpen = false,
  hdrInitApplied = false,
  
  -- Operation settings
  scopeSelectedOnly = true,
  insertOverride = true,
  insertPos = 'in_place',
  insertIndex = 0,
  batchSlotIndex = 0,
  actionType = 'replace_all',
  useDummyReplace = false,
  
  -- Replacement settings
  replaceWith = '',
  replaceDisplay = '',
  selectedSourceFXName = nil,
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
  
  trackNavInput = '',
  
  -- Messages and feedback
  pendingMessage = '',
  pendingError = '',
  
  -- Deletion management
  _pendingDelGUID = nil,
  _pendingDelTrack = nil,
  _pendingDelArmed = false,
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
  state.trackHeaderOpen = get_bool_setting('HDR_OPEN', state.trackHeaderOpen)
  state.replHeaderOpen = get_bool_setting('REPL_OPEN', state.replHeaderOpen)
  state.actionHeaderOpen = get_bool_setting('ACT_OPEN', state.actionHeaderOpen)
  state.sourceHeaderOpen = get_bool_setting('SRC_OPEN', state.sourceHeaderOpen)
  state.showScreenshot = get_bool_setting('IMG_SHOW', state.showScreenshot)
  state.fxChainHeaderOpen = get_bool_setting('FXC_OPEN', state.fxChainHeaderOpen)
  state.trackVersionHeaderOpen = get_bool_setting('TRV_OPEN', state.trackVersionHeaderOpen)
  state.showRMSButtons = get_bool_setting('SHOW_RMS', state.showRMSButtons)
  
  state.styleRounding = get_float_setting('STYLE_ROUNDING', state.styleRounding)
  state.styleButtonRounding = get_float_setting('STYLE_BTN_ROUNDING', state.styleButtonRounding)
  state.styleWindowRounding = get_float_setting('STYLE_WIN_ROUNDING', state.styleWindowRounding)
  state.styleFrameRounding = get_float_setting('STYLE_FRAME_ROUNDING', state.styleFrameRounding)
  state.styleGrabRounding = get_float_setting('STYLE_GRAB_ROUNDING', state.styleGrabRounding)
  state.styleTabRounding = get_float_setting('STYLE_TAB_ROUNDING', state.styleTabRounding)
  
  state.styleButtonColorR = get_float_setting('STYLE_BTN_R', state.styleButtonColorR)
  state.styleButtonColorG = get_float_setting('STYLE_BTN_G', state.styleButtonColorG)
  state.styleButtonColorB = get_float_setting('STYLE_BTN_B', state.styleButtonColorB)
  state.styleButtonHoveredR = get_float_setting('STYLE_BTN_HOV_R', state.styleButtonHoveredR)
  state.styleButtonHoveredG = get_float_setting('STYLE_BTN_HOV_G', state.styleButtonHoveredG)
  state.styleButtonHoveredB = get_float_setting('STYLE_BTN_HOV_B', state.styleButtonHoveredB)
  state.styleButtonActiveR = get_float_setting('STYLE_BTN_ACT_R', state.styleButtonActiveR)
  state.styleButtonActiveG = get_float_setting('STYLE_BTN_ACT_G', state.styleButtonActiveG)
  state.styleButtonActiveB = get_float_setting('STYLE_BTN_ACT_B', state.styleButtonActiveB)
  
  state.styleWindowBgR = get_float_setting('STYLE_WIN_BG_R', state.styleWindowBgR)
  state.styleWindowBgG = get_float_setting('STYLE_WIN_BG_G', state.styleWindowBgG)
  state.styleWindowBgB = get_float_setting('STYLE_WIN_BG_B', state.styleWindowBgB)
  state.styleWindowBgA = get_float_setting('STYLE_WIN_BG_A', state.styleWindowBgA)
  
  state.styleFrameBgR = get_float_setting('STYLE_FRAME_BG_R', state.styleFrameBgR)
  state.styleFrameBgG = get_float_setting('STYLE_FRAME_BG_G', state.styleFrameBgG)
  state.styleFrameBgB = get_float_setting('STYLE_FRAME_BG_B', state.styleFrameBgB)
  state.styleFrameBgA = get_float_setting('STYLE_FRAME_BG_A', state.styleFrameBgA)
  state.styleFrameBgHoveredR = get_float_setting('STYLE_FRAME_HOV_R', state.styleFrameBgHoveredR)
  state.styleFrameBgHoveredG = get_float_setting('STYLE_FRAME_HOV_G', state.styleFrameBgHoveredG)
  state.styleFrameBgHoveredB = get_float_setting('STYLE_FRAME_HOV_B', state.styleFrameBgHoveredB)
  state.styleFrameBgHoveredA = get_float_setting('STYLE_FRAME_HOV_A', state.styleFrameBgHoveredA)
  state.styleFrameBgActiveR = get_float_setting('STYLE_FRAME_ACT_R', state.styleFrameBgActiveR)
  state.styleFrameBgActiveG = get_float_setting('STYLE_FRAME_ACT_G', state.styleFrameBgActiveG)
  state.styleFrameBgActiveB = get_float_setting('STYLE_FRAME_ACT_B', state.styleFrameBgActiveB)
  state.styleFrameBgActiveA = get_float_setting('STYLE_FRAME_ACT_A', state.styleFrameBgActiveA)
end

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
  if not current_track then return false, 'No track selected' end
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
    return 0.0, 0.0, 0.0 -- Black text
  else
    return 1.0, 1.0, 1.0 -- White text
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
  name = name:gsub('[<>:"/\\|?*]', '_') -- Replace invalid filename chars
  name = name:gsub('%.%.+', '.') -- Collapse multiple dots
  name = name:gsub('^%.', ''):gsub('%.$', '') -- Remove leading/trailing dots
  name = name:gsub('^%s+', ''):gsub('%s+$', '') -- Trim whitespace
  
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
  
  for tr, _ in tracks_iter(state.scopeSelectedOnly) do
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
  
  for tr, _ in tracks_iter(state.scopeSelectedOnly) do
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
  
  if ctx then
    if iconFont and iconFont ~= false and r.ImGui_ValidatePtr and r.ImGui_Detach then
      if r.ImGui_ValidatePtr(iconFont, 'ImGui_Resource*') then
        pcall(r.ImGui_Detach, ctx, iconFont)
      end
    end
  end
  iconFont = nil
  
  if ctx and r.ImGui_DestroyContext then
    pcall(r.ImGui_DestroyContext, ctx)
  end
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

local function load_fx_chain(track, chain_path, replace_existing)
  if not track or not r.ValidatePtr(track, "MediaTrack*") then 
    return false, 'Invalid track'
  end
  
  if not chain_path or chain_path == '' then
    return false, 'No chain path provided'
  end
  
  r.SetOnlyTrackSelected(track)
  
  if replace_existing then
    local fx_count = r.TrackFX_GetCount(track)
    for i = fx_count - 1, 0, -1 do
      r.TrackFX_Delete(track, i)
    end
  end
  
  local resource_path = r.GetResourcePath()
  local sep = package.config:sub(1,1)
  local full_path = resource_path .. sep .. "FXChains" .. sep .. chain_path .. ".RfxChain"
  
  r.TrackFX_AddByName(track, full_path, false, -1000 - r.TrackFX_GetCount(track))
  
  local action = replace_existing and "replaced with" or "loaded"
  return true, string.format('FX Chain %s "%s"', action, chain_path)
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
  for i = 0, selected_count - 1 do
    local track = r.GetSelectedTrack(0, i)
    if track then
      if replace_existing then
        local fx_count = r.TrackFX_GetCount(track)
        for fx = fx_count - 1, 0, -1 do
          r.TrackFX_Delete(track, fx)
        end
      end
      
      local resource_path = r.GetResourcePath()
      local sep = package.config:sub(1,1)
      local full_path = resource_path .. sep .. "FXChains" .. sep .. chain_path .. ".RfxChain"
      
      r.TrackFX_AddByName(track, full_path, false, -1000 - r.TrackFX_GetCount(track))
      success_count = success_count + 1
    end
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
  for i = 0, track_count - 1 do
    local track = r.GetTrack(0, i)
    if track then
      if replace_existing then
        local fx_count = r.TrackFX_GetCount(track)
        for fx = fx_count - 1, 0, -1 do
          r.TrackFX_Delete(track, fx)
        end
      end
      
      local resource_path = r.GetResourcePath()
      local sep = package.config:sub(1,1)
      local full_path = resource_path .. sep .. "FXChains" .. sep .. chain_path .. ".RfxChain"
      
      r.TrackFX_AddByName(track, full_path, false, -1000 - r.TrackFX_GetCount(track))
      success_count = success_count + 1
    end
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
    r.ImGui_Dummy(ctx, 0, 4)
    if state.replHeaderOpen then r.ImGui_SetNextItemOpen(ctx, true, r.ImGui_Cond_FirstUseEver()) end
    local open = r.ImGui_CollapsingHeader(ctx, 'Replacement', 0)
    if open ~= nil and open ~= state.replHeaderOpen then state.replHeaderOpen = open; save_user_settings() end
  if open then
    local button_width = (r.ImGui_GetContentRegionAvail(ctx) - 4) * 0.5
    
    local chgSel, vSel = r.ImGui_Checkbox(ctx, 'Selected tracks', state.scopeSelectedOnly)
    if chgSel then state.scopeSelectedOnly = vSel end
    if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then r.ImGui_SetTooltip(ctx, 'Limit to selected tracks') end

    r.ImGui_SameLine(ctx, button_width + 8) 
    local chgDummy, vDummy = r.ImGui_Checkbox(ctx, 'Use placeholder', state.useDummyReplace)
    if chgDummy then state.useDummyReplace = vDummy end
    if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then r.ImGui_SetTooltip(ctx, 'Use TK Blank FX as replacement') end
    
    r.ImGui_Dummy(ctx, 0, 2)
    
    if state.useDummyReplace then
      if not state.tkBlankVariants then refresh_tk_blank_variants() end
      r.ImGui_SetNextItemWidth(ctx, button_width)
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
      r.ImGui_SameLine(ctx)
      r.ImGui_SetNextItemWidth(ctx, button_width)
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
    local button_width = (r.ImGui_GetContentRegionAvail(ctx) - 4) * 0.5
    
    r.ImGui_SetNextItemWidth(ctx, button_width)
    local preview = (state.replaceDisplay ~= '' and state.replaceDisplay) or 'My Favorites'
    local openedSL = r.ImGui_BeginCombo(ctx, '##shortlist', preview)
    if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then r.ImGui_SetTooltip(ctx, 'Pick from favorites') end
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
    if r.ImGui_Button(ctx, 'Pick from list', button_width, 0) then state.showPicker = true end
    if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then r.ImGui_SetTooltip(ctx, 'Open full FX list with search') end
  end

    r.ImGui_Dummy(ctx, 0, 4)

    local tracksAffected, changes = compute_preview()
    
    local canExecute = true
    if not state.selectedSourceFXName or state.selectedSourceFXName == '' then canExecute = false end
    if state.actionType ~= 'delete_all' then
      if not state.useDummyReplace and (not state.replaceWith or state.replaceWith == '') then canExecute = false end
    end
    if changes <= 0 then canExecute = false end

    if not canExecute and r.ImGui_BeginDisabled then r.ImGui_BeginDisabled(ctx) end
    
    local button_width = (r.ImGui_GetContentRegionAvail(ctx) - 4) * 0.5
    
    if r.ImGui_Button(ctx, 'Replace all', button_width, 0) then
      state.actionType = 'replace_all'
      local source = state.selectedSourceFXName
      local addName = state.useDummyReplace and ensure_tk_blank_addname(state.placeholderCustomName) or state.replaceWith
      local cnt = select(1, replace_all_instances(source, addName))
      state.pendingMessage = string.format('%d instances replaced.', cnt)
    end
    
    if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then
      r.ImGui_SetTooltip(ctx, 'Replace all instances of source FX everywhere')
    end
    
    r.ImGui_SameLine(ctx)
    
    if r.ImGui_Button(ctx, 'Delete all', button_width, 0) then
      state.actionType = 'delete_all'
      local source = state.selectedSourceFXName
      local cnt = select(1, delete_all_instances(source, nil, nil))
      state.pendingMessage = string.format('%d instances deleted.', cnt)
    end
    
    if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then
      r.ImGui_SetTooltip(ctx, 'Delete all instances of source FX')
    end
    
    if not canExecute and r.ImGui_EndDisabled then r.ImGui_EndDisabled(ctx) end

    -- r.ImGui_Dummy(ctx, 0, 4)

    local move_button_width = (r.ImGui_GetContentRegionAvail(ctx) - 4) * 0.5
    local hasSelection = state.selectedSourceFXName ~= nil and state.selectedSourceFXName ~= ''
    
    if not hasSelection then r.ImGui_BeginDisabled(ctx) end
    if r.ImGui_Button(ctx, 'Move Up All', move_button_width, 0) then
      local source = state.selectedSourceFXName
      local cnt, msg = move_all_instances_up(source)
      if cnt > 0 then
        state.pendingMessage = msg
      else
        state.pendingError = msg or 'No instances moved up'
      end
    end
    if not hasSelection then r.ImGui_EndDisabled(ctx) end
    
    if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then
      r.ImGui_SetTooltip(ctx, 'Move all instances of source FX up in their chains')
    end
    
    r.ImGui_SameLine(ctx)
    
    if not hasSelection then r.ImGui_BeginDisabled(ctx) end
    if r.ImGui_Button(ctx, 'Move Down All', move_button_width, 0) then
      local source = state.selectedSourceFXName
      local cnt, msg = move_all_instances_down(source)
      if cnt > 0 then
        state.pendingMessage = msg
      else
        state.pendingError = msg or 'No instances moved down'
      end
    end
    if not hasSelection then r.ImGui_EndDisabled(ctx) end
    
    if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then
      r.ImGui_SetTooltip(ctx, 'Move all instances of source FX down in their chains')
    end

    r.ImGui_Dummy(ctx, 0, 2)
    r.ImGui_Separator(ctx)
    
    r.ImGui_SetNextItemWidth(ctx,80)
    local chgSlot, slot1 = r.ImGui_InputInt(ctx, '##slot', (tonumber(state.batchSlotIndex) or 0) + 1)
    if chgSlot then state.batchSlotIndex = math.max(0, (tonumber(slot1) or 1) - 1) end
    if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then r.ImGui_SetTooltip(ctx, 'Slot number for slot actions') end
    
    r.ImGui_SameLine(ctx)
    local chgMS, vMS = r.ImGui_Checkbox(ctx, 'Match source', state.slotMatchSourceOnly)
    if chgMS then state.slotMatchSourceOnly = vMS end
    if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then r.ImGui_SetTooltip(ctx, 'Only replace when slot contains source FX') end
    
    -- Slot action buttons
    r.ImGui_Dummy(ctx, 0, 2)
    local slot_button_width = (r.ImGui_GetContentRegionAvail(ctx) - 4) * 0.5
    
    if not canExecute and r.ImGui_BeginDisabled then r.ImGui_BeginDisabled(ctx) end
    
    if r.ImGui_Button(ctx, 'Replace slot', slot_button_width, 0) then
      state.actionType = 'replace_slot'
      local source = state.selectedSourceFXName
      local addName = state.useDummyReplace and ensure_tk_blank_addname(state.placeholderCustomName) or state.replaceWith
      local alias = state.useDummyReplace and state.placeholderCustomName or nil
      local onlyIf = (state.slotMatchSourceOnly and source) or nil
      local cnt = select(1, replace_by_slot_across_tracks(state.batchSlotIndex, addName, alias, onlyIf))
      state.pendingMessage = string.format('Replaced on %d track(s).', cnt)
    end
    
    if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then
      r.ImGui_SetTooltip(ctx, string.format('Replace slot #%d across tracks', (state.batchSlotIndex or 0) + 1))
    end
    
    r.ImGui_SameLine(ctx)
    
    if r.ImGui_Button(ctx, 'Add at slot', slot_button_width, 0) then
      state.actionType = 'add_slot'
      local addName = state.useDummyReplace and ensure_tk_blank_addname(state.placeholderCustomName) or state.replaceWith
      local alias = state.useDummyReplace and state.placeholderCustomName or nil
      local cnt = select(1, add_by_slot_across_tracks(state.batchSlotIndex, addName, alias))
      state.pendingMessage = string.format('Added on %d track(s).', cnt)
    end
    
    if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then
      r.ImGui_SetTooltip(ctx, string.format('Add replacement at slot #%d across tracks', (state.batchSlotIndex or 0) + 1))
    end
    
    if not canExecute and r.ImGui_EndDisabled then r.ImGui_EndDisabled(ctx) end
    
    -- Preview text at bottom, centered
    r.ImGui_Dummy(ctx, 0, 8)
    local preview_text = string.format('Preview: %d change(s) on %d track(s)', changes, tracksAffected)
    local text_width = r.ImGui_CalcTextSize(ctx, preview_text)
    local avail_width = r.ImGui_GetContentRegionAvail(ctx)
    local offset = math.max(0, (avail_width - text_width) * 0.5)
    r.ImGui_SetCursorPosX(ctx, r.ImGui_GetCursorPosX(ctx) + offset)
    r.ImGui_TextDisabled(ctx, preview_text)
    
    r.ImGui_Dummy(ctx, 0, 4)
  end 

  do
    if state.sourceHeaderOpen then r.ImGui_SetNextItemOpen(ctx, true, r.ImGui_Cond_FirstUseEver()) end
    local prevOpen = state.sourceHeaderOpen
    local open = r.ImGui_CollapsingHeader(ctx, 'Source Controls', 0)
    if open ~= nil and open ~= state.sourceHeaderOpen then state.sourceHeaderOpen = open; save_user_settings() end
    if open ~= nil and open ~= prevOpen then
      release_screenshot()
    end
  end
  local tr = get_selected_track()
  local srcIdx = tonumber(state.selectedSourceFXIndex)
  if state.sourceHeaderOpen then
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

    local button_width = (r.ImGui_GetContentRegionAvail(ctx) - 4) * 0.5
    
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
      if r.ImGui_Button(ctx, 'Bypass', button_width, 0) then
        local en2 = get_fx_enabled(tr, srcCtrlIdx)
        set_fx_enabled(tr, srcCtrlIdx, en2 == nil and false or (not en2))
      end
      if pushed > 0 and r.ImGui_PopStyleColor then r.ImGui_PopStyleColor(ctx, pushed) end
      if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then r.ImGui_SetTooltip(ctx, 'Toggle bypass for source FX') end
    end
    
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
      if r.ImGui_Button(ctx, 'Offline', button_width, 0) then
        local off2 = get_fx_offline(tr, srcCtrlIdx)
        set_fx_offline(tr, srcCtrlIdx, off2 == nil and true or (not off2))
      end
      if pushed > 0 and r.ImGui_PopStyleColor then r.ImGui_PopStyleColor(ctx, pushed) end
      if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then r.ImGui_SetTooltip(ctx, 'Toggle offline for source FX') end
    end

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
      if r.ImGui_Button(ctx, 'Delta', button_width, 0) then toggle_fx_delta(tr, srcCtrlIdx) end
      if disabled and r.ImGui_EndDisabled then r.ImGui_EndDisabled(ctx) end
      if pushed > 0 and r.ImGui_PopStyleColor then r.ImGui_PopStyleColor(ctx, pushed) end
      if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then r.ImGui_SetTooltip(ctx, 'Toggle Delta solo (if plugin supports it)') end
    end
    
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
    if r.ImGui_Button(ctx, 'A/B (Replace)', button_width, 0) then
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
      if state.showScreenshot then
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
      else
        release_screenshot()
      end
    end
    else
      r.ImGui_Text(ctx, 'Pick a Source')
    end
  end

  do
    local openFxC = r.ImGui_CollapsingHeader(ctx, 'FXChain Controls', 0)
    if openFxC ~= nil and openFxC ~= state.fxChainHeaderOpen then
      state.fxChainHeaderOpen = openFxC; save_user_settings()
    end
    if openFxC and tr then
      local sws_available = is_sws_available()
      
      if not sws_available then
        r.ImGui_TextColored(ctx, 1.0, 0.5, 0.0, 1.0, 'SWS extension required for FX Chain operations')
        r.ImGui_TextDisabled(ctx, 'Please install SWS/S&M extension from sws-extension.org')
      else
        local fx_count = r.TrackFX_GetCount(tr) or 0
        local track_name = get_track_name(tr)
        
        if r.ImGui_Button(ctx, 'Save FX Chain', -1, 0) then
          local success, msg = create_fx_chain(tr)
          if success then
            state.pendingMessage = msg
            refresh_fx_chains_list(true) 
          else
            state.pendingError = msg
          end
        end
        
        if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then
          r.ImGui_SetTooltip(ctx, string.format('Save all FX from: %s (%d FX) as a new FX Chain', track_name, fx_count))
        end
        
        r.ImGui_Dummy(ctx, 0, 4)
        r.ImGui_Separator(ctx)
        r.ImGui_Dummy(ctx, 0, 4)
        
        r.ImGui_Text(ctx, 'Load FX Chain:')

        if not state.fxChains then
          refresh_fx_chains_list()
        end
        
        local chain_count = state.fxChains and #state.fxChains or 0
        r.ImGui_SameLine(ctx)
        local status_text = string.format('Found %d chains', chain_count)
        if state.fxChainsFromCache then
          status_text = status_text .. ' (cached)'
        end
        r.ImGui_TextDisabled(ctx, status_text)
        
        local button_width = (r.ImGui_GetContentRegionAvail(ctx) - 4) * 0.3
        if r.ImGui_Button(ctx, 'Refresh', button_width, 0) then
          refresh_fx_chains_list(true)  
          state.pendingMessage = 'FX Chains list refreshed from disk'
        end
        
        if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then
          r.ImGui_SetTooltip(ctx, 'Force refresh FX chains list from disk (cached otherwise)')
        end
        
        r.ImGui_SameLine(ctx)
        r.ImGui_SetNextItemWidth(ctx, -1)
        local changed, new_filter = r.ImGui_InputText(ctx, '##fxchain_filter', state.fxChainFilter)
        if changed then
          state.fxChainFilter = new_filter
        end
        
        if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then
          r.ImGui_SetTooltip(ctx, 'Filter FX chains by name')
        end
        
        r.ImGui_Dummy(ctx, 0, 2)
        
        if r.ImGui_BeginChild(ctx, '##fxchains_list', -1, 120) then
          if state.fxChains and #state.fxChains > 0 then
            local filter = state.fxChainFilter:lower()
            
            for i, chain in ipairs(state.fxChains) do
              local show_chain = filter == '' or chain.display_name:lower():find(filter, 1, true)
              
              if show_chain then
                local selected = state.selectedFxChain == chain.path
                if r.ImGui_Selectable(ctx, chain.display_name, selected) then
                  state.selectedFxChain = chain.path
                end
                
                if r.ImGui_IsItemClicked(ctx, 1) then
                  r.ImGui_OpenPopup(ctx, 'FXChainContext_' .. i)
                end
                
                if r.ImGui_BeginPopup(ctx, 'FXChainContext_' .. i) then
                  if r.ImGui_MenuItem(ctx, 'Load (Add to existing)') then
                    local success, msg = load_fx_chain(tr, chain.path, false)
                    if success then
                      state.pendingMessage = msg
                    else
                      state.pendingError = msg
                    end
                  end
                  
                  if r.ImGui_MenuItem(ctx, 'Load (Replace all FX)') then
                    local success, msg = load_fx_chain(tr, chain.path, true)
                    if success then
                      state.pendingMessage = msg
                    else
                      state.pendingError = msg
                    end
                  end
                  
                  r.ImGui_Separator(ctx)
                  
                  if r.ImGui_MenuItem(ctx, 'Rename Chain') then
                    local retval, new_name = r.GetUserInputs("Rename FX Chain", 1, "New name:", chain.name)
                    if retval and new_name ~= '' and new_name ~= chain.name then
                      local success, msg = rename_fx_chain(chain.path, new_name)
                      if success then
                        state.pendingMessage = msg
                        refresh_fx_chains_list(true)  
                        state.selectedFxChain = nil
                      else
                        state.pendingError = msg
                      end
                    end
                  end
                  
                  if r.ImGui_MenuItem(ctx, 'Delete Chain') then
                    local success, msg = delete_fx_chain(chain.path)
                    if success then
                      state.pendingMessage = msg
                      refresh_fx_chains_list(true)  
                    else
                      state.pendingError = msg
                    end
                  end
                  
                  r.ImGui_EndPopup(ctx)
                end
              end
            end
          else
            r.ImGui_TextDisabled(ctx, 'No FX chains found')
            r.ImGui_TextDisabled(ctx, 'Save some FX chains to see them here')
          end
          r.ImGui_EndChild(ctx)
        end
        
        r.ImGui_Dummy(ctx, 0, 4)
        
        if state.selectedFxChain then
          r.ImGui_Text(ctx, 'Load to:')
          
          local changed, new_current = r.ImGui_Checkbox(ctx, 'Current Track', state.fxChainLoadToCurrent)
          if changed then 
            state.fxChainLoadToCurrent = new_current
            if new_current then
              state.fxChainLoadToSelected = false
              state.fxChainLoadToAll = false
            end
          end
          
          r.ImGui_SameLine(ctx)
          local changed2, new_selected = r.ImGui_Checkbox(ctx, 'Selected Tracks', state.fxChainLoadToSelected)
          if changed2 then 
            state.fxChainLoadToSelected = new_selected
            if new_selected then
              state.fxChainLoadToCurrent = false
              state.fxChainLoadToAll = false
            end
          end
          
          r.ImGui_SameLine(ctx)
          local changed3, new_all = r.ImGui_Checkbox(ctx, 'All Tracks', state.fxChainLoadToAll)
          if changed3 then 
            state.fxChainLoadToAll = new_all
            if new_all then
              state.fxChainLoadToCurrent = false
              state.fxChainLoadToSelected = false
            end
          end
          
          local any_target_selected = state.fxChainLoadToCurrent or state.fxChainLoadToSelected or state.fxChainLoadToAll
          
          if not any_target_selected then
            r.ImGui_TextColored(ctx, 1.0, 0.5, 0.0, 1.0, 'Select a target (Current/Selected/All)')
          else
            r.ImGui_Dummy(ctx, 0, 4)
            
            local button_width = (r.ImGui_GetContentRegionAvail(ctx) - 4) * 0.5
            
            if r.ImGui_Button(ctx, 'Add', button_width, 0) then
              local success = false
              local msg = ''
              
              if state.fxChainLoadToCurrent then
                success, msg = load_fx_chain(tr, state.selectedFxChain, false)
              elseif state.fxChainLoadToSelected then
                local count
                count, msg = load_fx_chain_to_selected_tracks(state.selectedFxChain, false)
                success = count > 0
              elseif state.fxChainLoadToAll then
                local track_count = r.CountTracks(0)
                local result = r.MB(string.format('Add FX chain to ALL %d tracks?', track_count), 'Confirm Add to All', 4)
                if result == 6 then
                  local count
                  count, msg = load_fx_chain_to_all_tracks(state.selectedFxChain, false)
                  success = count > 0
                else
                  msg = 'Add to all tracks cancelled'
                end
              end
              
              if success then
                state.pendingMessage = msg
              else
                state.pendingError = msg
              end
            end
            
            if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then
              local target = state.fxChainLoadToCurrent and 'current track' or 
                            state.fxChainLoadToSelected and 'selected tracks' or 
                            state.fxChainLoadToAll and 'all tracks' or 'target'
              r.ImGui_SetTooltip(ctx, string.format('Add FX chain to %s (keeps existing FX)', target))
            end
            
            r.ImGui_SameLine(ctx)
            
            if r.ImGui_Button(ctx, 'Replace', button_width, 0) then
              local confirm_msg = ''
              local track_count = 0
              
              if state.fxChainLoadToCurrent then
                confirm_msg = 'Replace ALL existing FX on current track?'
                track_count = 1
              elseif state.fxChainLoadToSelected then
                track_count = r.CountSelectedTracks(0)
                if track_count == 0 then
                  state.pendingError = 'No tracks selected'
                  goto skip_replace
                end
                confirm_msg = string.format('Replace ALL FX on %d selected track(s)?', track_count)
              elseif state.fxChainLoadToAll then
                track_count = r.CountTracks(0)
                confirm_msg = string.format('Replace ALL FX on ALL %d tracks?\n\nPERMANENT deletion of existing FX!', track_count)
              end
              
              local result = r.MB(confirm_msg, 'Confirm Replace', 4)
              if result == 6 then
                local success = false
                local msg = ''
                
                if state.fxChainLoadToCurrent then
                  success, msg = load_fx_chain(tr, state.selectedFxChain, true)
                elseif state.fxChainLoadToSelected then
                  local count
                  count, msg = load_fx_chain_to_selected_tracks(state.selectedFxChain, true)
                  success = count > 0
                elseif state.fxChainLoadToAll then
                  local count
                  count, msg = load_fx_chain_to_all_tracks(state.selectedFxChain, true)
                  success = count > 0
                end
                
                if success then
                  state.pendingMessage = msg
                else
                  state.pendingError = msg
                end
              end
              
              ::skip_replace::
            end
            
            if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then
              local target = state.fxChainLoadToCurrent and 'current track' or 
                            state.fxChainLoadToSelected and 'selected tracks' or 
                            state.fxChainLoadToAll and 'all tracks' or 'target'
              r.ImGui_SetTooltip(ctx, string.format('Replace ALL FX on %s (DANGER!)', target))
            end
          end
        end
        r.ImGui_Dummy(ctx, 0, 8)
        r.ImGui_Separator(ctx)
        r.ImGui_Dummy(ctx, 0, 4)
        
        r.ImGui_Text(ctx, 'FX Chain Copy/Paste:')
        
        if r.ImGui_Button(ctx, 'Copy FX from current track', -1, 0) then
          if fx_count > 0 then
            local success, msg = copy_fx_chain_from_track(tr)
            if success then
              state.pendingMessage = msg
            else
              state.pendingError = msg
            end
          else
            state.pendingError = 'Current track has no FX to copy'
          end
        end
        
        if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then
          r.ImGui_SetTooltip(ctx, string.format('Copy all FX from: %s (%d FX)', track_name, fx_count))
        end
        
        r.ImGui_Dummy(ctx, 0, 2)
        
        local has_copied_chain = copied_fx_chain_info ~= nil
        if has_copied_chain then
          local age_minutes = math.floor((os.time() - copied_fx_chain_info.timestamp) / 60)
          r.ImGui_TextDisabled(ctx, string.format('%s (%d FX, %dm ago)', 
            copied_fx_chain_info.source_track_name, copied_fx_chain_info.fx_count, age_minutes))
        else
          r.ImGui_TextDisabled(ctx, 'No FX chain copied yet')
        end
        
        if not has_copied_chain and r.ImGui_BeginDisabled then r.ImGui_BeginDisabled(ctx) end
        
        local button_width = (r.ImGui_GetContentRegionAvail(ctx) - 4) * 0.5
        
        if r.ImGui_Button(ctx, 'Add to selected', button_width, 0) then
          local count, msg = paste_fx_chain_to_selected_tracks()
          if count > 0 then
            state.pendingMessage = msg
          else
            state.pendingError = msg or 'Failed to add to selected tracks'
          end
        end
        
        if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then
          r.ImGui_SetTooltip(ctx, 'Add FX to selected tracks (keeps existing)')
        end
        
        r.ImGui_SameLine(ctx)
        
        if r.ImGui_Button(ctx, 'Replace selected', button_width, 0) then
          local selected_count = r.CountSelectedTracks(0)
          if selected_count > 0 then
            local result = r.MB(string.format('Replace ALL FX on %d selected track(s)?', selected_count), 
              'Confirm Replace', 4)
            if result == 6 then
              local count, msg = replace_fx_chain_to_selected_tracks()
              if count > 0 then
                state.pendingMessage = msg
              else
                state.pendingError = msg or 'Failed to replace on selected tracks'
              end
            end
          else
            state.pendingError = 'No tracks selected'
          end
        end
        
        if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then
          r.ImGui_SetTooltip(ctx, 'Replace ALL FX on selected tracks')
        end
        
        if r.ImGui_Button(ctx, 'Add to all tracks', button_width, 0) then
          local track_count = r.CountTracks(0)
          local result = r.MB(string.format('Add FX chain to ALL %d tracks?', track_count), 
            'Confirm Add to All', 4)
          if result == 6 then
            local count, msg = paste_fx_chain_to_all_tracks()
            if count > 0 then
              state.pendingMessage = msg
            else
              state.pendingError = msg or 'Failed to add to all tracks'
            end
          end
        end
        
        if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then
          r.ImGui_SetTooltip(ctx, 'Add FX to ALL tracks (keeps existing)')
        end
        
        r.ImGui_SameLine(ctx)
        
        if r.ImGui_Button(ctx, 'Replace all tracks', button_width, 0) then
          local track_count = r.CountTracks(0)
          local result = r.MB(string.format('Replace ALL FX on ALL %d tracks?\n\nPERMANENT deletion of existing FX!', track_count), 
            'CONFIRM REPLACE ALL', 4)
          if result == 6 then
            local count, msg = replace_fx_chain_to_all_tracks()
            if count > 0 then
              state.pendingMessage = msg
            else
              state.pendingError = msg or 'Failed to replace all tracks'
            end
          end
        end
        
        if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then
          r.ImGui_SetTooltip(ctx, 'Replace ALL FX on ALL tracks (DANGER!)')
        end
        
        if not has_copied_chain and r.ImGui_EndDisabled then r.ImGui_EndDisabled(ctx) end
        
        if has_copied_chain then
          r.ImGui_Dummy(ctx, 0, 2)
          r.ImGui_Separator(ctx)
          r.ImGui_TextDisabled(ctx, 'Add: keeps existing • Replace: deletes existing first')
          if r.ImGui_SmallButton(ctx, 'Clear') then
            copied_fx_chain_info = nil
            state.pendingMessage = 'Cleared copied FX chain'
          end
          if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then
            r.ImGui_SetTooltip(ctx, 'Clear copied FX chain from memory')
          end
        end
      end
    elseif openFxC and not tr then
      r.ImGui_TextDisabled(ctx, 'Select a track to use FX Chain controls')
    end
  end


  do
    if state.trackVersionHeaderOpen then r.ImGui_SetNextItemOpen(ctx, true, r.ImGui_Cond_FirstUseEver()) end
    local open = r.ImGui_CollapsingHeader(ctx, 'Track Version Controls', 0)
    if open ~= nil and open ~= state.trackVersionHeaderOpen then state.trackVersionHeaderOpen = open; save_user_settings() end
    if open then
      r.ImGui_Dummy(ctx, 0, 4)
      r.ImGui_TextDisabled(ctx, 'Track version controls will be implemented here')
      r.ImGui_Text(ctx, 'Coming soon:')
      r.ImGui_BulletText(ctx, 'Create track versions/snapshots')
      r.ImGui_BulletText(ctx, 'Switch between versions')  
      r.ImGui_BulletText(ctx, 'Compare versions')
      r.ImGui_BulletText(ctx, 'Merge version changes')
      r.ImGui_Dummy(ctx, 0, 4)
    end
  end
end
end

 
local function draw()
  if not is_context_valid(ctx) then 
    r.ShowConsoleMsg("Context invalid, reinitializing...\n")
    if not init_context() then 
      r.ShowConsoleMsg("Failed to reinitialize context\n")
      return 
    end
  end
  
  if not ctx then
    r.ShowConsoleMsg("No context available\n")
    return
  end
  
  if r.ImGui_SetNextWindowSize then 
    local success = pcall(r.ImGui_SetNextWindowSize, ctx, state.winW, state.winH, r.ImGui_Cond_FirstUseEver())
    if not success then
      r.ShowConsoleMsg("SetNextWindowSize failed, context may be invalid\n")
      return
    end
  end
  if r.ImGui_SetNextWindowSizeConstraints then r.ImGui_SetNextWindowSizeConstraints(ctx, 300, 220, 2000, 1400) end
  
  if not is_context_valid(ctx) then 
    r.ShowConsoleMsg("Context became invalid before Begin\n")
    return 
  end
  
  local stylePush = push_app_style()
  local success, visible, open = pcall(r.ImGui_Begin, ctx, SCRIPT_NAME, true, r.ImGui_WindowFlags_NoScrollbar() | r.ImGui_WindowFlags_NoScrollWithMouse() | r.ImGui_WindowFlags_NoTitleBar())
  
  if not success then
    r.ShowConsoleMsg("ImGui_Begin failed, context invalid\n")
    pop_app_style(stylePush)
    return
  end
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
      if not state.hdrInitApplied then
        
        if state.trackHeaderOpen then r.ImGui_SetNextItemOpen(ctx, true, r.ImGui_Cond_Always()) end
        state.hdrInitApplied = true
      end
      local hdrFlags = 0
      if r.ImGui_TreeNodeFlags_AllowItemOverlap then
        hdrFlags = hdrFlags | r.ImGui_TreeNodeFlags_AllowItemOverlap()
      end
      
      local buttonAreaWidth = state.showRMSButtons and 60 or 0
      local availWidth = r.ImGui_GetContentRegionAvail(ctx)
      local headerWidth = availWidth - buttonAreaWidth
      
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
            r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FramePadding(), 3, 3); 
            pushedSV = pushedSV + 1
            styleStackDepth.vars = styleStackDepth.vars + 1
          end
          if r.ImGui_StyleVar_ItemSpacing then 
            r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing(), spacingX, 0); 
            pushedSV = pushedSV + 1
            styleStackDepth.vars = styleStackDepth.vars + 1
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
            -- Add adaptive text color for RMS buttons
            local textR, textG, textB = get_text_color_for_background(rC, gC, bC)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), col_u32(textR, textG, textB, 1.0)); pushed = pushed + 1
          elseif rC and gC and bC then
            -- For non-active button, still apply adaptive text color
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
            -- Add adaptive text color for RMS buttons
            local textR, textG, textB = get_text_color_for_background(rC, gC, bC)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), col_u32(textR, textG, textB, 1.0)); pushed = pushed + 1
          elseif rC and gC and bC then
            -- For non-active button, still apply adaptive text color
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
      r.ImGui_SetCursorPosY(ctx, currentY - 3) -- Move up by 3 pixels

      local fontPushed = false
      if r.ImGui_PushFont then
        local pushSuccess = pcall(r.ImGui_PushFont, ctx, nil, r.ImGui_GetFontSize(ctx) * 1.25) -- 25% larger
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
                      r.TrackFX_CopyToTrack(tr, src, tr, dest, true)
                      r.Undo_EndBlock('Move FX', -1)
                      state.pendingMessage = string.format('Moved "%s" to position %d', disp, dest + 1)
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
                rightClick = r.ImGui_IsItemClicked(ctx, 1) -- Right mouse button
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

              -- Right click opens FX floating window
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
      end
    end
  
  draw_replace_panel()
    r.ImGui_EndChild(ctx)

    r.ImGui_Separator(ctx)
    
    local current_track = get_selected_track()
    local current_number = current_track and get_track_number(current_track) or 0
    local total_tracks = r.CountTracks(0)
    local nav_width = 280
    local available_width = r.ImGui_GetContentRegionAvail(ctx)
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
    r.ImGui_SetNextItemWidth(ctx, 60)
    local changed, new_input = r.ImGui_InputText(ctx, '##track_nav_input', state.trackNavInput)
    if changed then state.trackNavInput = new_input end
    if state.tooltips and r.ImGui_IsItemHovered(ctx) and r.ImGui_SetTooltip then
      r.ImGui_SetTooltip(ctx, 'Enter track number (1-' .. total_tracks .. ')')
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
    
    r.ImGui_SameLine(ctx)
    r.ImGui_TextDisabled(ctx, string.format(' (%d/%d)', current_number, total_tracks))
    
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
  
    debug_stack_state("Before cleanup")
  if styleStackDepth.colors > 0 and r.ImGui_PopStyleColor then
    pcall(r.ImGui_PopStyleColor, ctx, styleStackDepth.colors)
    styleStackDepth.colors = 0
  end
  if styleStackDepth.vars > 0 and r.ImGui_PopStyleVar then
    pcall(r.ImGui_PopStyleVar, ctx, styleStackDepth.vars)  
    styleStackDepth.vars = 0
  end
  debug_stack_state("After cleanup")

  if r.ImGui_IsMouseDown and r.ImGui_IsMouseReleased then
    if r.ImGui_IsMouseReleased(ctx, 0) then
      state._pendingDelArmed = false
    end
  else
    if r.ImGui_GetIO then
      local io = r.ImGui_GetIO(ctx)
      if io and not (io.MouseDown and io.MouseDown[1]) then
        state._pendingDelArmed = false
      end
    end
  end

  
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
        
        if r.ImGui_BeginTabBar and r.ImGui_BeginTabBar(ctx, 'SettingsTabs') then
          
          if r.ImGui_BeginTabItem and r.ImGui_BeginTabItem(ctx, 'General') then
            local c1, v1 = r.ImGui_Checkbox(ctx, 'Tooltips', state.tooltips)
            if c1 then state.tooltips = v1; changed = true end
            local c2, v2 = r.ImGui_Checkbox(ctx, 'Names without prefix', state.nameNoPrefix)
            if c2 then state.nameNoPrefix = v2; changed = true end
            local c3, v3 = r.ImGui_Checkbox(ctx, 'Hide developer name', state.nameHideDeveloper)
            if c3 then state.nameHideDeveloper = v3; changed = true end
            local c4, v4 = r.ImGui_Checkbox(ctx, 'Plugin image', state.showScreenshot)
            if c4 then
              state.showScreenshot = v4; changed = true
              if not v4 then release_screenshot() end
            end
            local c5, v5 = r.ImGui_Checkbox(ctx, 'Show R/M/S buttons', state.showRMSButtons)
            if c5 then state.showRMSButtons = v5; changed = true end
            
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
            
            if r.ImGui_EndTabItem then r.ImGui_EndTabItem(ctx) end
          end
          
          if r.ImGui_EndTabBar then r.ImGui_EndTabBar(ctx) end
        else
          local c1, v1 = r.ImGui_Checkbox(ctx, 'Tooltips', state.tooltips)
          if c1 then state.tooltips = v1; changed = true end
          local c2, v2 = r.ImGui_Checkbox(ctx, 'Names without prefix', state.nameNoPrefix)
          if c2 then state.nameNoPrefix = v2; changed = true end
          local c3, v3 = r.ImGui_Checkbox(ctx, 'Hide developer name', state.nameHideDeveloper)
          if c3 then state.nameHideDeveloper = v3; changed = true end
          local c4, v4 = r.ImGui_Checkbox(ctx, 'Plugin image', state.showScreenshot)
          if c4 then
            state.showScreenshot = v4; changed = true
            if not v4 then release_screenshot() end
          end
          local c5, v5 = r.ImGui_Checkbox(ctx, 'Show R/M/S buttons', state.showRMSButtons)
          if c5 then state.showRMSButtons = v5; changed = true end
          
          if changed then save_user_settings() end
        end
        
        
        r.ImGui_Separator(ctx)
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
    
    save_user_settings()
  end
end

local function safe_draw()
  if not is_context_valid(ctx) then
    r.ShowConsoleMsg("Context invalid in safe_draw, reinitializing...\n")
    if not init_context() then
      r.ShowConsoleMsg("Failed to reinitialize context in safe_draw\n")
      return 
    end
  end
  
  local success, error_msg = pcall(draw)
  if not success then
    local error_text = tostring(error_msg or 'Unknown error')
    r.ShowConsoleMsg("Draw error: " .. error_text .. "\n")
    
    if error_text:find('ImGui_Context', 1, true) or 
       error_text:find('ValidatePtr', 1, true) or
       error_text:find('invalid', 1, true) then
      r.ShowConsoleMsg("Detected ImGui context error, cleaning up and reinitializing...\n")
      cleanup_resources()
      if init_context() then
        r.defer(safe_draw) 
      else
        r.ShowMessageBox('Failed to recover from ImGui context error. Please restart the script.', 'Error', 0)
      end
    else
      state.pendingError = 'Script error: ' .. error_text
      r.defer(safe_draw) 
    end
  end
end

local function main()
  init_fx_parser()
  load_window_size()
  load_user_settings()
  favs_load()
  blanks_load()
  
  safe_draw()
end

r.atexit(cleanup_resources)

main()
