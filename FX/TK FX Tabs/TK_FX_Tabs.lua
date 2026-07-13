-- @description TK FX Tabs
-- @author TouristKiller
-- @version 1.1.4
-- @changelog:
--   v1.1.4
--   + ESC closes the script
--   v1.1.3
--   + Tab bar below plugin (flip): place the tab bar on the opposite side of the plugin, works in all modes
--   + Also fixes macOS setups where the tab bar appeared at the bottom of the plugin instead of the top
--   + Tab bar vertical offset slider to fine-tune the bar position
--   v1.1.2
--   # Offline/bypassed FX now respect the 'Center FX' setting (kept in place and draggable when centering is off, instead of always snapping to center)
--   # Enabling Follow FX window now automatically turns off 'Center FX' (which stays greyed out while follow is active)
--   v1.1.0
--   + Follow FX window mode: tab bar follows the plugin window instead of moving it
--   + Option to hide track numbers on tabs
--   + Ctrl-click a tab to bypass, Alt-click to set offline
--   # Follow mode no longer steals focus from REAPER (menus/shortcuts keep working)
--   # Follow mode keeps the tab bar reliably above the plugin (cross-platform)



local r = reaper

local SCRIPT_NAME = "TK FX Tabs"
local BLOCKED_WINDOW_NAME = "TK FX Tabs Blocked State"
local SECTION = "TK_FX_TABS"
local IS_WINDOWS = r.GetOS and tostring(r.GetOS()):match("Win") ~= nil

if not r.ImGui_CreateContext then
  r.ShowMessageBox("TK FX Tabs requires ReaImGui.", SCRIPT_NAME, 0)
  return
end

local ctx = r.ImGui_CreateContext(SCRIPT_NAME)
local status_font = nil
if r.ImGui_CreateFont and r.ImGui_Attach then
  status_font = r.ImGui_CreateFont("Arial", 112)
  if status_font then r.ImGui_Attach(ctx, status_font) end
end
local instruments = {}
local selected_key = ""
local active_key = ""
local last_scan_time = 0
local force_scan = true
local pending_activate_key = ""
local pending_activate_frames = 0
local pending_place_until = 0
local pending_pair_front_until = 0
local pending_close_key = ""
local pending_close_deadline = 0
local last_place_time = 0
local last_external_watch_time = 0
local topbar_focus_click_armed = false
local topbar_mouse_captured = false
local topbar_dragging = false
local topbar_focus_click_x = 0
local topbar_focus_click_y = 0
local topbar_popup_active = false
local topbar_popup_hold_until = 0
local topbar_control_block_until = 0
local window_touch_pause_until = 0
local topbar_restack_until = 0
local topbar_owner_hwnd = nil
local topbar_owner_fx_hwnd = nil
local topbar_original_owner = nil
local topbar_owner_supported = IS_WINDOWS
local external_open_state = {}
local host_rect = { left = 0, top = 0, width = 0, height = 0 }
local fx_size_cache = {}
local tab_width_cache = {}
local tab_scroll_x = 0
local tab_context_key = ""
local topbar_width = 980
local topbar_height = 66
local topbar_side_overhang = 1
local default_fx_width = 920
local default_fx_height = 620
local theme = nil
local cleanup_done = false
local close_requested = false
local startup_open_done = false
local startup_clean_done = false
local sexan_parser_loaded = false
local add_instrument_items = nil
local add_instrument_struct = nil
local add_instrument_error = nil
local add_instrument_search = ""
local add_instrument_content_mode = nil
local pending_add_instrument_item = nil
local CONTENT_MODE_ALL_FX = 0
local CONTENT_MODE_INSTRUMENTS = 1
local CONTENT_MODE_LABELS = { "All FX", "Instruments only" }
local TAB_FILTER_ALL = 0
local TAB_FILTER_SELECTED = 1
local TAB_FILTER_FOLDER = 2
local TAB_FILTER_GROUP = 3
local TAB_FILTER_LABELS = { "All FX", "Selected tracks", "Same folder/parent", "Same REAPER track group" }

local function ext_get_bool(key, default_value)
  local value = r.GetExtState(SECTION, key)
  if value == nil or value == "" then return default_value end
  return value == "1"
end

local function ext_set_bool(key, value)
  r.SetExtState(SECTION, key, value and "1" or "0", true)
end

local function ext_get_number(key, default_value)
  local value = tonumber(r.GetExtState(SECTION, key))
  if value == nil then return default_value end
  return value
end

local function ext_set_number(key, value)
  r.SetExtState(SECTION, key, tostring(value), true)
end

function ext_get_string(key, default_value)
  local value = r.GetExtState(SECTION, key)
  if value == nil or value == "" then return default_value end
  return value
end

function ext_set_string(key, value)
  r.SetExtState(SECTION, key, tostring(value or ""), true)
end

local settings = {
  select_track_on_open = ext_get_bool("select_track_on_open", true),
  auto_open_on_start = ext_get_bool("auto_open_on_start", true),
  capture_external_floating = ext_get_bool("capture_external_floating", true),
  center_fx_in_reaper_window = ext_get_bool("center_fx_in_reaper_window", true),
  follow_fx_position = ext_get_bool("follow_fx_position", false),
  show_track_numbers = ext_get_bool("show_track_numbers", true),
  content_mode = ext_get_number("content_mode", CONTENT_MODE_ALL_FX),
  tab_filter_mode = ext_get_number("tab_filter_mode", TAB_FILTER_ALL),
  plugin_overlap_y = ext_get_number("plugin_overlap_y", 80),
  vertical_flip = ext_get_bool("vertical_flip", false),
  vertical_offset = ext_get_number("vertical_offset", 0),
  topbar_left_overhang = ext_get_number("topbar_left_overhang", topbar_side_overhang),
  topbar_right_overhang = ext_get_number("topbar_right_overhang", topbar_side_overhang),
  theme_preset = ext_get_string("theme_preset", "REAPER Theme"),
  theme_topbar_border = ext_get_bool("theme_topbar_border", true),
  scan_interval = 0.75,
}

if settings.follow_fx_position and settings.center_fx_in_reaper_window then
  settings.center_fx_in_reaper_window = false
  ext_set_bool("center_fx_in_reaper_window", false)
end

local function imgui_flag(name)
  local flag_function = r[name]
  if flag_function then return flag_function() end
  return 0
end

local function add_imgui_flag(flags, name)
  local value = imgui_flag(name)
  if value ~= 0 then return flags | value end
  return flags
end

local function clamp(value, min_value, max_value)
  value = tonumber(value) or min_value
  return math.max(min_value, math.min(max_value, value))
end

local function topbar_left_overhang()
  return clamp(settings.topbar_left_overhang, -24, 48)
end

local function topbar_right_overhang()
  return clamp(settings.topbar_right_overhang, -24, 48)
end

local function topbar_vertical_offset()
  return clamp(settings.vertical_offset, -120, 120)
end

local function topbar_window_width(width)
  return math.max(120, (width or topbar_width) + topbar_left_overhang() + topbar_right_overhang())
end

local function js_int(value)
  return math.floor((tonumber(value) or 0) + 0.5)
end

local function native_to_imgui(x, y)
  if r.ImGui_PointConvertNative then return r.ImGui_PointConvertNative(ctx, x, y) end
  return x, y
end

local function imgui_to_native(x, y)
  if r.ImGui_PointConvertNative then return r.ImGui_PointConvertNative(ctx, x, y, true) end
  return x, y
end

local function main_viewport_rect()
  local vx, vy, vw, vh = 80, 80, 1280, 720
  local vp = r.ImGui_GetMainViewport and r.ImGui_GetMainViewport(ctx)
  if vp then
    if r.ImGui_Viewport_GetPos then
      local x, y = r.ImGui_Viewport_GetPos(vp)
      if x and y then vx, vy = x, y end
    end
    if r.ImGui_Viewport_GetSize then
      local w, h = r.ImGui_Viewport_GetSize(vp)
      if w and h and w > 0 and h > 0 then vw, vh = w, h end
    end
  end
  return vx, vy, vw, vh
end

local function reaper_window_rect()
  if r.GetMainHwnd and r.JS_Window_GetRect then
    local hwnd = r.GetMainHwnd()
    local ok, left, top, right, bottom = r.JS_Window_GetRect(hwnd)
    if ok and left and top and right and bottom and right > left and bottom > top then
      local imgui_left, imgui_top = native_to_imgui(left, top)
      local imgui_right, imgui_bottom = native_to_imgui(right, bottom)
      return imgui_left, imgui_top, imgui_right - imgui_left, imgui_bottom - imgui_top
    end
  end
  return main_viewport_rect()
end

function rgba(red, green, blue, alpha)
  red = js_int(clamp(red, 0, 255))
  green = js_int(clamp(green, 0, 255))
  blue = js_int(clamp(blue, 0, 255))
  alpha = js_int(clamp(alpha or 255, 0, 255))
  return red * 0x1000000 + green * 0x10000 + blue * 0x100 + alpha
end

function split_rgba(color)
  color = math.floor(tonumber(color) or 0)
  if color < 0 then color = color + 0x100000000 end
  local red = math.floor(color / 0x1000000) % 0x100
  local green = math.floor(color / 0x10000) % 0x100
  local blue = math.floor(color / 0x100) % 0x100
  local alpha = color % 0x100
  return red, green, blue, alpha
end

function blend(first, second, amount)
  amount = clamp(amount, 0, 1)
  local ar, ag, ab, aa = split_rgba(first)
  local br, bg, bb, ba = split_rgba(second)
  return rgba(ar + (br - ar) * amount, ag + (bg - ag) * amount, ab + (bb - ab) * amount, aa + (ba - aa) * amount)
end

function luminance(color)
  local red, green, blue = split_rgba(color)
  return (0.2126 * red + 0.7152 * green + 0.0722 * blue) / 255
end

function readable_text(background)
  return luminance(background) > 0.52 and 0x20242AFF or 0xF2F4F7FF
end

function theme_color(name, fallback)
  if not r.GetThemeColor or not r.ColorFromNative then return fallback end
  local ok_color, native = pcall(r.GetThemeColor, name, 0)
  if not ok_color or native == nil or native < 0 then return fallback end
  local ok_rgb, red, green, blue = pcall(r.ColorFromNative, native)
  if not ok_rgb then return fallback end
  return rgba(red or 0, green or 0, blue or 0, 255)
end

function first_theme_color(names, fallback)
  for _, name in ipairs(names) do
    local color = theme_color(name, nil)
    if color then return color end
  end
  return fallback
end

THEME_UNSAVED = "Unsaved Custom"
THEME_PRESET_NAMES = { "REAPER Theme", "Graphite", "Light", "Blue", "Amber", "High Contrast" }
THEME_COLOR_FIELDS = {
  { key = "window_bg", label = "Window" },
  { key = "panel_bg", label = "Panel" },
  { key = "popup_bg", label = "Popup" },
  { key = "edit_bg", label = "Frame" },
  { key = "tab_bg", label = "Tab" },
  { key = "tab_hover", label = "Tab Hover" },
  { key = "tab_active", label = "Active Tab" },
  { key = "border", label = "Border" },
  { key = "text", label = "Text" },
  { key = "text_dim", label = "Dim Text" },
  { key = "accent", label = "Accent" },
  { key = "accent_soft", label = "Accent Soft" },
  { key = "warning", label = "Warning" },
  { key = "danger", label = "Danger" }
}

THEME_PRESETS = {
  Graphite = {
    window_bg = 0x111111FF, panel_bg = 0x181818FF, popup_bg = 0x1B1B1BFF, edit_bg = 0x242424FF,
    tab_bg = 0x242424FF, tab_hover = 0x333333FF, tab_active = 0x4C566AFF, border = 0x444444FF,
    text = 0xF0F0F0FF, text_dim = 0xA0A0A0FF, accent = 0xD8DEE9FF, accent_soft = 0x4C566AFF,
    warning = 0xEBCB8BFF, danger = 0xBF616AFF
  },
  Light = {
    window_bg = 0xEDE8DEFF, panel_bg = 0xF7F3ECFF, popup_bg = 0xF4EFE7FF, edit_bg = 0xDED6CAFF,
    tab_bg = 0xDED6CAFF, tab_hover = 0xD1C7B8FF, tab_active = 0xB8D3E8FF, border = 0xB4AA9DFF,
    text = 0x252A2EFF, text_dim = 0x697078FF, accent = 0x246AA8FF, accent_soft = 0xB8D3E8FF,
    warning = 0xB86E00FF, danger = 0xC4414BFF
  },
  Blue = {
    window_bg = 0x121417FF, panel_bg = 0x181B20FF, popup_bg = 0x181B20FF, edit_bg = 0x222730FF,
    tab_bg = 0x222730FF, tab_hover = 0x2B3440FF, tab_active = 0x2B4B78FF, border = 0x343A46FF,
    text = 0xE8EDF2FF, text_dim = 0x8F9AA8FF, accent = 0x7AA2F7FF, accent_soft = 0x2B4B78FF,
    warning = 0xE0AF68FF, danger = 0xF7768EFF
  },
  Amber = {
    window_bg = 0x17130EFF, panel_bg = 0x211A12FF, popup_bg = 0x261E14FF, edit_bg = 0x312719FF,
    tab_bg = 0x312719FF, tab_hover = 0x44351FFF, tab_active = 0x624719FF, border = 0x5A4326FF,
    text = 0xF4E8D4FF, text_dim = 0xB89D78FF, accent = 0xE6B450FF, accent_soft = 0x624719FF,
    warning = 0xFFCF70FF, danger = 0xE06C75FF
  },
  ["High Contrast"] = {
    window_bg = 0x050505FF, panel_bg = 0x0E0E0EFF, popup_bg = 0x101010FF, edit_bg = 0x1A1A1AFF,
    tab_bg = 0x1A1A1AFF, tab_hover = 0x303030FF, tab_active = 0x00566BFF, border = 0x606060FF,
    text = 0xFFFFFFFF, text_dim = 0xC8C8C8FF, accent = 0x00D4FFFF, accent_soft = 0x00566BFF,
    warning = 0xFFD166FF, danger = 0xFF4D6DFF
  }
}

theme_edit_name = ext_get_string("custom_theme_name", "My Theme")
theme_status = ""
unsaved_theme_colors = nil

function copy_theme_colors(source)
  local target = {}
  for key, value in pairs(source or {}) do target[key] = value end
  return target
end

function trim_text(value)
  return tostring(value or ""):match("^%s*(.-)%s*$") or ""
end

function encode_text(value)
  return tostring(value or ""):gsub("([^%w _%-%.])", function(char) return string.format("%%%02X", string.byte(char)) end):gsub(" ", "+")
end

function decode_text(value)
  return tostring(value or ""):gsub("+", " "):gsub("%%(%x%x)", function(hex) return string.char(tonumber(hex, 16)) end)
end

function serialize_theme_colors(colors)
  local parts = {}
  for _, field in ipairs(THEME_COLOR_FIELDS) do parts[#parts + 1] = field.key .. "=" .. tostring(math.floor(tonumber(colors[field.key]) or 0)) end
  return table.concat(parts, ",")
end

function parse_theme_colors(text)
  local colors = {}
  for key, value in tostring(text or ""):gmatch("([%w_]+)=(-?%d+)") do colors[key] = tonumber(value) end
  return colors
end

function load_custom_themes()
  local themes = {}
  local text = ext_get_string("custom_themes", "")
  for encoded_name, color_text in text:gmatch("([^|;]+)|([^;]+)") do
    local name = decode_text(encoded_name)
    if name ~= "" then themes[name] = parse_theme_colors(color_text) end
  end
  return themes
end

custom_themes = load_custom_themes()

function save_custom_themes()
  local names = {}
  for name in pairs(custom_themes or {}) do names[#names + 1] = name end
  table.sort(names, function(a, b) return a:lower() < b:lower() end)
  local parts = {}
  for _, name in ipairs(names) do parts[#parts + 1] = encode_text(name) .. "|" .. serialize_theme_colors(custom_themes[name]) end
  ext_set_string("custom_themes", table.concat(parts, ";"))
end

function complete_theme_colors(colors)
  colors = copy_theme_colors(colors)
  colors.window_bg = colors.window_bg or 0x16181CFF
  colors.panel_bg = colors.panel_bg or blend(colors.window_bg, readable_text(colors.window_bg), 0.06)
  colors.popup_bg = colors.popup_bg or blend(colors.panel_bg, colors.window_bg, 0.18)
  colors.edit_bg = colors.edit_bg or blend(colors.panel_bg, readable_text(colors.panel_bg), 0.08)
  colors.accent = colors.accent or 0x7AA2F7FF
  colors.tab_bg = colors.tab_bg or blend(colors.edit_bg, colors.window_bg, 0.2)
  colors.tab_hover = colors.tab_hover or blend(colors.tab_bg, readable_text(colors.tab_bg), 0.16)
  colors.tab_active = colors.tab_active or blend(colors.tab_bg, colors.accent, 0.36)
  colors.border = colors.border or blend(readable_text(colors.window_bg), colors.window_bg, 0.65)
  colors.separator = colors.separator or colors.border
  colors.header = colors.header or colors.tab_bg
  colors.header_hover = colors.header_hover or colors.tab_hover
  colors.topbar_border = colors.topbar_border or (luminance(colors.window_bg) < 0.5 and blend(0xFFFFFFFF, colors.window_bg, 0.82) or blend(0x000000FF, colors.window_bg, 0.36))
  colors.text = colors.text or readable_text(colors.window_bg)
  colors.text_tab = readable_text(colors.tab_bg)
  colors.text_active = readable_text(colors.tab_active)
  colors.text_dim = colors.text_dim or blend(colors.text, colors.window_bg, luminance(colors.window_bg) < 0.5 and 0.38 or 0.52)
  colors.accent_soft = colors.accent_soft or blend(colors.accent, colors.window_bg, 0.64)
  colors.warning = colors.warning or 0xE5C07BFF
  colors.danger = colors.danger or 0xE06C75FF
  return colors
end

function build_theme()
  local fallback_bg = 0x16181CFF
  local fallback_panel = 0x20242AFF
  local window_bg = first_theme_color({ "col_main_bg", "docker_bg", "col_main_bg2", "col_arrangebg" }, fallback_bg)
  local panel_bg = first_theme_color({ "docker_bg", "genlist_bg", "col_main_bg2", "col_tracklistbg" }, fallback_panel)
  local edit_bg = first_theme_color({ "col_main_editbk", "genlist_bg", "col_buttonbg" }, blend(panel_bg, readable_text(panel_bg), 0.08))
  local accent = first_theme_color({ "genlist_selbg", "docker_selface", "col_seltrack", "selcol_tr1_bg", "marker", "region", "col_routingact", "col_vumid" }, 0x7AA2F7FF)
  local highlight = first_theme_color({ "col_main_3dhl", "tcp_list_scrollbar_mouseover", "mcp_list_scrollbar_mouseover" }, readable_text(window_bg))
  local shadow = first_theme_color({ "col_main_3dsh", "genlist_grid", "col_gridlines" }, blend(window_bg, readable_text(window_bg), 0.18))
  local dark = luminance(window_bg) < 0.5
  local text = first_theme_color({ "col_main_text", "genlist_fg", "col_tcp_text", "col_mixer_text" }, readable_text(window_bg))
  local text_dim = first_theme_color({ "col_main_text2", "genlist_seliafg", "col_tl_fg2", "col_toolbar_text" }, blend(text, window_bg, dark and 0.38 or 0.52))
  local tab_bg = blend(edit_bg, window_bg, dark and 0.22 or 0.16)
  local tab_hover = blend(tab_bg, highlight, dark and 0.18 or 0.12)
  local tab_active = blend(tab_bg, accent, dark and 0.42 or 0.34)
  local topbar_border = dark and blend(0xFFFFFFFF, window_bg, 0.82) or blend(0x000000FF, window_bg, 0.36)
  local reaper_theme = {
    window_bg = window_bg,
    panel_bg = panel_bg,
    edit_bg = edit_bg,
    popup_bg = blend(panel_bg, window_bg, 0.18),
    tab_bg = tab_bg,
    tab_hover = tab_hover,
    tab_active = tab_active,
    border = blend(highlight, shadow, 0.55),
    topbar_border = topbar_border,
    text = readable_text(window_bg),
    text_tab = readable_text(tab_bg),
    text_active = readable_text(tab_active),
    text_dim = text_dim,
    accent = accent,
    accent_soft = blend(accent, window_bg, dark and 0.62 or 0.76),
    warning = first_theme_color({ "col_tl_bgsel", "col_tl_bgsel2", "playrate_edited", "marker", "region" }, 0xE5C07BFF),
    danger = first_theme_color({ "col_vuclip", "midi_noteon_flash", "midi_notemute_sel", "mute_overlay_col" }, 0xE06C75FF),
  }
  local preset_name = settings.theme_preset or "REAPER Theme"
  if preset_name == THEME_UNSAVED and unsaved_theme_colors then return complete_theme_colors(unsaved_theme_colors) end
  if preset_name ~= "REAPER Theme" and THEME_PRESETS[preset_name] then return complete_theme_colors(THEME_PRESETS[preset_name]) end
  if preset_name ~= "REAPER Theme" and custom_themes[preset_name] then return complete_theme_colors(custom_themes[preset_name]) end
  return complete_theme_colors(reaper_theme)
end

function push_theme()
  theme = build_theme()
  local colors = 0
  local vars = 0
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_WindowBg(), theme.window_bg); colors = colors + 1
  if r.ImGui_Col_ChildBg then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ChildBg(), theme.panel_bg); colors = colors + 1 end
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_PopupBg(), theme.popup_bg); colors = colors + 1
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), theme.edit_bg); colors = colors + 1
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgHovered(), theme.tab_hover); colors = colors + 1
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Border(), theme.border); colors = colors + 1
  if r.ImGui_Col_Separator then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Separator(), theme.separator); colors = colors + 1 end
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), theme.text); colors = colors + 1
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), theme.tab_bg); colors = colors + 1
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), theme.tab_hover); colors = colors + 1
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), theme.tab_active); colors = colors + 1
  if r.ImGui_Col_Header then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Header(), theme.header); colors = colors + 1 end
  if r.ImGui_Col_HeaderHovered then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderHovered(), theme.header_hover); colors = colors + 1 end
  if r.ImGui_Col_HeaderActive then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderActive(), theme.accent_soft); colors = colors + 1 end
  if r.ImGui_StyleVar_WindowRounding then r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowRounding(), 0); vars = vars + 1 end
  if r.ImGui_StyleVar_FrameRounding then r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), 4); vars = vars + 1 end
  if r.ImGui_StyleVar_WindowPadding then r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), 8, 6); vars = vars + 1 end
  if r.ImGui_StyleVar_ItemSpacing then r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing(), 6, 5); vars = vars + 1 end
  return { colors = colors, vars = vars }
end

function pop_theme(stack)
  if stack and stack.vars and stack.vars > 0 then r.ImGui_PopStyleVar(ctx, stack.vars) end
  if stack and stack.colors and stack.colors > 0 then r.ImGui_PopStyleColor(ctx, stack.colors) end
end

local function draw_topbar_background()
  local draw_list = r.ImGui_GetWindowDrawList(ctx)
  local x, y = r.ImGui_GetWindowPos(ctx)
  local width, height = r.ImGui_GetWindowSize(ctx)
  local bg_x1 = x
  local bg_x2 = x + width
  local rounding = 7
  local border_color = theme.topbar_border or theme.border
  local show_border = settings.theme_topbar_border ~= false
  local line_x1 = bg_x1 + 0.5
  local line_x2 = bg_x2 - 0.5
  local line_y = y + 0.5
  local line_bottom = y + height
  local corner_flags = imgui_flag("ImGui_DrawFlags_RoundCornersTop")
  if corner_flags ~= 0 then
    r.ImGui_DrawList_AddRectFilled(draw_list, bg_x1, y, bg_x2, y + height, theme.window_bg, rounding, corner_flags)
    if show_border then
      r.ImGui_DrawList_AddRect(draw_list, line_x1, line_y, line_x2, y + height, border_color, rounding, corner_flags, 1)
      r.ImGui_DrawList_AddLine(draw_list, line_x1 + rounding, line_y, line_x2 - rounding, line_y, border_color, 1)
      r.ImGui_DrawList_AddLine(draw_list, line_x1, line_y + rounding, line_x1, line_bottom, border_color, 1)
      r.ImGui_DrawList_AddLine(draw_list, line_x2, line_y + rounding, line_x2, line_bottom, border_color, 1)
    end
    r.ImGui_DrawList_AddLine(draw_list, bg_x1, y + height - 1, bg_x2, y + height - 1, theme.window_bg, 2)
  else
    r.ImGui_DrawList_AddRectFilled(draw_list, bg_x1, y, bg_x2, y + height, theme.window_bg, rounding)
    r.ImGui_DrawList_AddRectFilled(draw_list, bg_x1, y + rounding, bg_x2, y + height, theme.window_bg, 0)
    if show_border then
      r.ImGui_DrawList_AddLine(draw_list, line_x1 + rounding, line_y, line_x2 - rounding, line_y, border_color, 1)
      r.ImGui_DrawList_AddLine(draw_list, line_x1, line_y + rounding, line_x1, line_bottom, border_color, 1)
      r.ImGui_DrawList_AddLine(draw_list, line_x2, line_y + rounding, line_x2, line_bottom, border_color, 1)
    end
  end
end

local function is_valid_media_track(track)
  if not track then return false end
  if r.ValidatePtr2 then return r.ValidatePtr2(0, track, "MediaTrack*") end
  if r.ValidatePtr then return r.ValidatePtr(track, "MediaTrack*") end
  return true
end

local function track_guid(track)
  if track and r.GetTrackGUID then return r.GetTrackGUID(track) end
  return tostring(track or "")
end

local function track_name(track, track_index)
  local fallback_name = "Track " .. tostring(track_index + 1)
  if not track then return fallback_name end
  local retval, name = r.GetTrackName(track, "")
  if retval and name and name ~= "" then return name end
  return fallback_name
end

local function clean_fx_name(name)
  name = tostring(name or "")
  name = name:gsub("^%s+", ""):gsub("%s+$", "")
  name = name:gsub("^VST3i:%s*", "")
  name = name:gsub("^VSTi:%s*", "")
  name = name:gsub("^VST3:%s*", "")
  name = name:gsub("^VST:%s*", "")
  name = name:gsub("^CLAPi:%s*", "")
  name = name:gsub("^CLAP:%s*", "")
  name = name:gsub("^AUi:%s*", "")
  name = name:gsub("^LV2i:%s*", "")
  name = name:gsub("^AU:%s*", "")
  name = name:gsub("%s+%(.-%)%s*$", "")
  if name == "" then return "FX" end
  return name
end

local function is_instrument_fx_name(name)
  name = tostring(name or "")
  return name:match("^VSTi:%s") ~= nil
    or name:match("^VST3i:%s") ~= nil
    or name:match("^CLAPi:%s") ~= nil
    or name:match("^AUi:%s") ~= nil
    or name:match("^LV2i:%s") ~= nil
end

local function normalized_content_mode()
  local mode = math.floor(tonumber(settings.content_mode) or CONTENT_MODE_ALL_FX)
  if mode < CONTENT_MODE_ALL_FX or mode > CONTENT_MODE_INSTRUMENTS then return CONTENT_MODE_ALL_FX end
  return mode
end

local function content_mode_instruments_only()
  return normalized_content_mode() == CONTENT_MODE_INSTRUMENTS
end

local function content_mode_allows_fx(fx_index, primary_instrument, fx_name)
  if not content_mode_instruments_only() then return true end
  return fx_index == primary_instrument or is_instrument_fx_name(fx_name)
end

local function entry_label(entry)
  if not entry then return "" end
  local name = tostring(entry.fx_label or entry.fx_name or "FX")
  if settings.show_track_numbers == false then return name end
  return tostring(entry.track_index + 1) .. "  " .. name
end

local function find_entry_by_key(key)
  for entry_index = 1, #instruments do
    local entry = instruments[entry_index]
    if entry.key == key then return entry end
  end
  return nil
end

local function resolve_entry_track(entry)
  if not entry then return nil end
  if entry.track_guid and r.BR_GetMediaTrackByGUID then
    local track = r.BR_GetMediaTrackByGUID(0, entry.track_guid)
    if is_valid_media_track(track) then return track end
  end
  local track = r.GetTrack(0, entry.track_index)
  if not is_valid_media_track(track) then return nil end
  if entry.track_guid and track_guid(track) ~= entry.track_guid then return nil end
  return track
end

local function safe_trackfx_show(track, fx_index, show_flag)
  if not r.TrackFX_Show then return false end
  if not is_valid_media_track(track) then return false end
  r.TrackFX_Show(track, fx_index, show_flag)
  return true
end

local function safe_trackfx_get_floating_window(track, fx_index)
  if not r.TrackFX_GetFloatingWindow then return nil end
  if not is_valid_media_track(track) then return nil end
  return r.TrackFX_GetFloatingWindow(track, fx_index)
end

local function safe_trackfx_get_enabled(track, fx_index, fallback)
  if not r.TrackFX_GetEnabled then return fallback end
  if not is_valid_media_track(track) then return fallback end
  return r.TrackFX_GetEnabled(track, fx_index)
end

local function safe_trackfx_get_offline(track, fx_index, fallback)
  if not r.TrackFX_GetOffline then return fallback end
  if not is_valid_media_track(track) then return fallback end
  return r.TrackFX_GetOffline(track, fx_index)
end

local function safe_trackfx_set_enabled(track, fx_index, enabled)
  if not r.TrackFX_SetEnabled then return false end
  if not is_valid_media_track(track) then return false end
  r.TrackFX_SetEnabled(track, fx_index, enabled)
  return true
end

local function safe_trackfx_set_offline(track, fx_index, offline)
  if not r.TrackFX_SetOffline then return false end
  if not is_valid_media_track(track) then return false end
  r.TrackFX_SetOffline(track, fx_index, offline)
  return true
end

local function safe_trackfx_delete(track, fx_index)
  if not r.TrackFX_Delete then return false end
  if not is_valid_media_track(track) then return false end
  r.TrackFX_Delete(track, fx_index)
  return true
end

function midi_input_value(device_index)
  if device_index == nil then return -1 end
  return 4096 + (device_index << 5)
end

function midi_input_options()
  local options = {
    { label = "None", value = -1 },
    { label = "All MIDI inputs", value = midi_input_value(63) },
    { label = "Virtual MIDI Keyboard", value = midi_input_value(62) },
  }
  if r.GetNumMIDIInputs and r.GetMIDIInputName then
    local count = r.GetNumMIDIInputs()
    for index = 0, count - 1 do
      local ok, name = r.GetMIDIInputName(index, "")
      if ok and name and name ~= "" then options[#options + 1] = { label = name, value = midi_input_value(index) } end
    end
  end
  return options
end

function midi_input_label(value)
  value = math.floor(tonumber(value) or -1)
  if value < 0 then return "None" end
  if (value & 4096) ~= 4096 then return "Audio input" end
  local device = (value >> 5) & 63
  local channel = value & 31
  local suffix = channel > 0 and (" ch " .. tostring(channel)) or ""
  if device == 63 then return "All MIDI inputs" .. suffix end
  if device == 62 then return "Virtual MIDI Keyboard" .. suffix end
  if r.GetMIDIInputName then
    local ok, name = r.GetMIDIInputName(device, "")
    if ok and name and name ~= "" then return name .. suffix end
  end
  return "MIDI input " .. tostring(device + 1) .. suffix
end

function set_track_midi_input(track, value)
  if not is_valid_media_track(track) then return false end
  r.Undo_BeginBlock()
  r.SetMediaTrackInfo_Value(track, "I_RECINPUT", value)
  r.Undo_EndBlock("Set instrument MIDI input", -1)
  return true
end

function entry_supports_midi_input(entry, track)
  if not entry or not is_valid_media_track(track) then return false end
  if is_instrument_fx_name(entry.fx_name) then return true end
  if r.TrackFX_GetInstrument then return r.TrackFX_GetInstrument(track) == entry.fx_index end
  return false
end

local function refresh_entry_state(entry, track)
  if not entry or not track then return end
  entry.enabled = safe_trackfx_get_enabled(track, entry.fx_index, entry.enabled ~= false)
  entry.offline = safe_trackfx_get_offline(track, entry.fx_index, entry.offline == true)
end

local function entry_blocked_state(entry)
  if not entry then return nil end
  if entry.offline then return "OFFLINE" end
  if entry.enabled == false then return "BYPASS" end
  return nil
end

local function cached_fx_size(entry)
  if entry and fx_size_cache[entry.key] then return fx_size_cache[entry.key] end
  return { width = default_fx_width, height = default_fx_height }
end

function entry_window_size(entry)
  return cached_fx_size(entry)
end

local function centered_topbar_position()
  if active_key == "" or topbar_dragging then return nil end
  if not settings.center_fx_in_reaper_window then return nil end
  local blocked = entry_blocked_state(find_entry_by_key(active_key)) ~= nil
  if not blocked and settings.follow_fx_position then return nil end
  local size = entry_window_size(find_entry_by_key(active_key))
  local reaper_left, reaper_top, reaper_width, reaper_height = reaper_window_rect()
  local overlap = clamp(settings.plugin_overlap_y, 0, 80)
  local margin = 10
  local combo_height = topbar_height + size.height - overlap
  local host_left = reaper_left + (reaper_width - size.width) * 0.5
  local combo_top = reaper_top + (reaper_height - combo_height) * 0.5
  local min_left = reaper_left + margin
  local max_left = reaper_left + reaper_width - size.width - margin
  if max_left >= min_left then host_left = clamp(host_left, min_left, max_left) end
  local min_top = reaper_top + margin
  local max_top = reaper_top + reaper_height - combo_height - margin
  if max_top >= min_top then combo_top = clamp(combo_top, min_top, max_top) else combo_top = math.max(min_top, combo_top) end
  return host_left - topbar_left_overhang(), combo_top, host_left
end

local function apply_centered_host_rect()
  local centered_left, centered_top, centered_host_left = centered_topbar_position()
  if not centered_left or not centered_top then return false end
  host_rect.left = centered_host_left or centered_left + topbar_side_overhang
  if settings.vertical_flip then
    host_rect.top = centered_top
  else
    host_rect.top = centered_top + topbar_height - clamp(settings.plugin_overlap_y, 0, 80)
  end
  return true
end

local function topbar_position_from_host_rect()
  if host_rect.width < 120 or host_rect.height < 90 then return nil end
  local overlap = clamp(settings.plugin_overlap_y, 0, 80)
  local bar_top
  if settings.vertical_flip then
    bar_top = host_rect.top + host_rect.height - overlap + topbar_vertical_offset()
  else
    bar_top = host_rect.top - topbar_height + overlap + topbar_vertical_offset()
  end
  return host_rect.left - topbar_left_overhang(), bar_top
end

local function update_topbar_width_from_size(width)
  local _, _, viewport_width = main_viewport_rect()
  local max_width = viewport_width - 24 - topbar_left_overhang() - topbar_right_overhang()
  topbar_width = clamp(width or topbar_width, 360, math.max(360, max_width))
end

function sync_host_rect_to_entry_size(entry)
  if not entry then return end
  local size = entry_window_size(entry)
  update_topbar_width_from_size(size.width)
  host_rect.width = size.width
  host_rect.height = size.height
  if not topbar_dragging then apply_centered_host_rect() end
end

local function measure_fx_window(entry, hwnd)
  if not entry or not hwnd or not r.JS_Window_GetRect then return false end
  local ok, left, top, right, bottom = r.JS_Window_GetRect(hwnd)
  if not ok then return false end
  local imgui_left, imgui_top = native_to_imgui(left or 0, top or 0)
  local imgui_right, imgui_bottom = native_to_imgui(right or 0, bottom or 0)
  local width = math.max(180, math.abs(imgui_right - imgui_left))
  local height = math.max(140, math.abs(imgui_bottom - imgui_top))
  if width <= 180 or height <= 140 then return false end
  local previous = fx_size_cache[entry.key]
  fx_size_cache[entry.key] = { width = width, height = height }
  update_topbar_width_from_size(width)
  if not previous then return true end
  return math.abs((previous.width or 0) - width) > 2 or math.abs((previous.height or 0) - height) > 2
end

function cache_entry_current_fx_window_size(entry, track)
  if not entry or not track then return false end
  local hwnd = safe_trackfx_get_floating_window(track, entry.fx_index)
  if not hwnd then return false end
  return measure_fx_window(entry, hwnd)
end

local function topbar_hwnd()
  if not r.JS_Window_Find then return nil end
  return r.JS_Window_Find(SCRIPT_NAME, true)
end

function sync_topbar_window_to_blocked_entry(entry)
  if not entry_blocked_state(entry) then return end
  sync_host_rect_to_entry_size(entry)
  local width = topbar_window_width(topbar_width)
  if r.ImGui_SetWindowSize then r.ImGui_SetWindowSize(ctx, width, topbar_height, imgui_flag("ImGui_Cond_Always")) end
  if not topbar_dragging then
    local topbar_left, topbar_top = topbar_position_from_host_rect()
    if topbar_left and topbar_top and r.ImGui_SetWindowPos then r.ImGui_SetWindowPos(ctx, topbar_left, topbar_top, imgui_flag("ImGui_Cond_Always")) end
  end
  if not r.JS_Window_SetPosition then return end
  local hwnd = topbar_hwnd()
  if not hwnd then return end
  local left, top = r.ImGui_GetWindowPos(ctx)
  local native_x1, native_y1 = imgui_to_native(left, top)
  local native_x2, native_y2 = imgui_to_native(left + width, top + topbar_height)
  local native_left = js_int(math.min(native_x1, native_x2))
  local native_top = js_int(math.min(native_y1, native_y2))
  local native_right = js_int(math.max(native_x1, native_x2))
  local native_bottom = js_int(math.max(native_y1, native_y2))
  r.JS_Window_SetPosition(hwnd, native_left, native_top, native_right - native_left, native_bottom - native_top)
end

local function blocked_state_hwnd()
  if not r.JS_Window_Find then return nil end
  return r.JS_Window_Find(BLOCKED_WINDOW_NAME, true)
end

local function get_window_owner(hwnd)
  if not hwnd or not r.JS_Window_GetParent then return nil end
  local ok, owner = pcall(r.JS_Window_GetParent, hwnd)
  if ok then return owner end
  return nil
end

local function set_window_owner(hwnd, owner)
  if not IS_WINDOWS or not hwnd or not r.JS_Window_SetLong then return false end
  local owner_value = 0
  if owner and owner ~= 0 then
    if not r.JS_Window_AddressFromHandle then return false end
    owner_value = r.JS_Window_AddressFromHandle(owner)
    if not owner_value or owner_value == 0 then return false end
  end
  local ok, result = pcall(r.JS_Window_SetLong, hwnd, "PARENT", owner_value)
  if not ok or result == false then return false end
  if owner and owner ~= 0 and r.JS_Window_GetParent then
    local parent = r.JS_Window_GetParent(hwnd)
    return parent == owner
  end
  return true
end

local function clear_topbar_owner()
  if topbar_owner_hwnd and topbar_original_owner ~= nil then set_window_owner(topbar_owner_hwnd, topbar_original_owner) end
  topbar_owner_hwnd = nil
  topbar_owner_fx_hwnd = nil
  topbar_original_owner = nil
end

local function set_topbar_owner(fx_hwnd)
  if not topbar_owner_supported then return false end
  local owner_target = r.GetMainHwnd and r.GetMainHwnd() or nil
  if not owner_target then return false end
  local hwnd = topbar_hwnd()
  if not hwnd or hwnd == owner_target then return false end
  if topbar_owner_hwnd ~= hwnd then
    clear_topbar_owner()
    topbar_owner_hwnd = hwnd
    topbar_original_owner = get_window_owner(hwnd) or 0
  end
  if topbar_owner_fx_hwnd == owner_target then return true end
  if not set_window_owner(hwnd, owner_target) then
    topbar_owner_supported = false
    clear_topbar_owner()
    return false
  end
  topbar_owner_fx_hwnd = owner_target
  return true
end

local function topbar_owner_active()
  return topbar_owner_supported and topbar_owner_hwnd == topbar_hwnd() and topbar_owner_fx_hwnd ~= nil
end

function owner_pairing_status_label()
  if not IS_WINDOWS then return "Owner pairing: unsupported (non-Windows)" end
  if not r.JS_Window_SetLong or not r.JS_Window_AddressFromHandle then return "Owner pairing: unavailable (js_ReaScriptAPI owner API missing)" end
  if not topbar_owner_supported then return "Owner pairing: failed" end
  if active_key == "" then return "Owner pairing: waiting for active FX" end
  if entry_blocked_state(find_entry_by_key(active_key)) then return "Owner pairing: not used for bypass/offline state" end
  if topbar_owner_active() then return "Owner pairing: active" end
  return "Owner pairing: waiting for FX window"
end

local function current_foreground_hwnd()
  if r.JS_Window_GetForeground then return r.JS_Window_GetForeground() end
  if r.JS_Window_GetFocus then return r.JS_Window_GetFocus() end
  return nil
end

local function hwnd_is_or_child_of(hwnd, parent)
  if not hwnd or not parent then return false end
  local current = hwnd
  for _ = 1, 16 do
    if current == parent then return true end
    if not r.JS_Window_GetParent then return false end
    current = r.JS_Window_GetParent(current)
    if not current then return false end
  end
  return false
end

local function foreground_allows_active_window_placement(fx_hwnd)
  local foreground = current_foreground_hwnd()
  if not foreground then return true end
  if hwnd_is_or_child_of(foreground, fx_hwnd) then return true end
  if hwnd_is_or_child_of(foreground, topbar_hwnd()) then return true end
  if r.GetMainHwnd and hwnd_is_or_child_of(foreground, r.GetMainHwnd()) then return true end
  return false
end

local function foreground_is_topbar_pair(fx_hwnd)
  local foreground = current_foreground_hwnd()
  if not foreground then return false end
  if hwnd_is_or_child_of(foreground, fx_hwnd) then return true end
  return hwnd_is_or_child_of(foreground, topbar_hwnd())
end

local function left_mouse_down()
  if r.JS_Mouse_GetState then return (r.JS_Mouse_GetState(1) & 1) == 1 end
  if r.ImGui_IsMouseDown then return r.ImGui_IsMouseDown(ctx, 0) end
  return false
end

local function update_window_touch_pause()
  if left_mouse_down() then window_touch_pause_until = r.time_precise() + 0.18 end
end

local function window_touch_paused()
  return r.time_precise() < window_touch_pause_until
end

local function topbar_drag_active()
  return topbar_dragging and left_mouse_down()
end

local function fx_window_is_above_topbar(fx_hwnd, topbar)
  if not fx_hwnd or not topbar or not r.JS_Window_GetRelated then return false end
  local current = topbar
  for _ = 1, 64 do
    local prev = r.JS_Window_GetRelated(current, "PREV")
    if not prev or prev == 0 or prev == current then return false end
    if prev == fx_hwnd then return true end
    current = prev
  end
  return false
end

local function place_topbar_above_fx(fx_hwnd)
  if window_touch_paused() then return end
  if topbar_mouse_captured then return end
  if topbar_popup_active or r.time_precise() < topbar_popup_hold_until then return end
  if not fx_hwnd or not r.JS_Window_Find or not r.JS_Window_SetZOrder then return end
  local hwnd = topbar_hwnd()
  if not hwnd or hwnd == fx_hwnd then return end
  local ok = r.JS_Window_SetZOrder(fx_hwnd, "INSERT_AFTER", hwnd)
  if ok == false then r.JS_Window_SetZOrder(fx_hwnd, "INSERTAFTER", hwnd) end
end

local function bring_topbar_pair_to_front(fx_hwnd)
  if not fx_hwnd or not r.JS_Window_SetZOrder then return end
  local hwnd = topbar_hwnd()
  if not hwnd or hwnd == fx_hwnd then return end
  r.JS_Window_SetZOrder(hwnd, "TOP")
  local ok = r.JS_Window_SetZOrder(fx_hwnd, "INSERT_AFTER", hwnd)
  if ok == false then r.JS_Window_SetZOrder(fx_hwnd, "INSERTAFTER", hwnd) end
  r.JS_Window_SetZOrder(hwnd, "TOP")
end

local function keep_topbar_above_fx(fx_hwnd)
  if window_touch_paused() or topbar_mouse_captured then return end
  if topbar_popup_active or r.time_precise() < topbar_popup_hold_until then return end
  if not fx_hwnd or not r.JS_Window_SetZOrder then return end
  local hwnd = topbar_hwnd()
  if not hwnd or hwnd == fx_hwnd then return end
  if fx_window_is_above_topbar(fx_hwnd, hwnd) then
    place_topbar_above_fx(fx_hwnd)
  end
end

local function bring_blocked_pair_to_front()
  if not r.JS_Window_SetZOrder then return false end
  local hwnd = topbar_hwnd()
  local blocked_hwnd = blocked_state_hwnd()
  if not hwnd and not blocked_hwnd then return false end
  if hwnd then r.JS_Window_SetZOrder(hwnd, "TOP") end
  if blocked_hwnd and hwnd and blocked_hwnd ~= hwnd then
    local ok = r.JS_Window_SetZOrder(blocked_hwnd, "INSERT_AFTER", hwnd)
    if ok == false then r.JS_Window_SetZOrder(blocked_hwnd, "INSERTAFTER", hwnd) end
    r.JS_Window_SetZOrder(hwnd, "TOP")
  elseif blocked_hwnd then
    r.JS_Window_SetZOrder(blocked_hwnd, "TOP")
  end
  return true
end

local function window_rect_needs_update(hwnd, left, top, right, bottom)
  if not r.JS_Window_GetRect then return true end
  local ok, current_left, current_top, current_right, current_bottom = r.JS_Window_GetRect(hwnd)
  if not ok then return true end
  return math.abs((current_left or 0) - left) > 2
    or math.abs((current_top or 0) - top) > 2
    or math.abs((current_right or 0) - right) > 2
    or math.abs((current_bottom or 0) - bottom) > 2
end

function follow_fx_window_update()
  follow_pair_on_top = false
  if not settings.follow_fx_position or active_key == "" or topbar_dragging then return false end
  if not r.JS_Window_GetRect then return false end
  local entry = find_entry_by_key(active_key)
  if not entry or entry_blocked_state(entry) then return false end
  local track = resolve_entry_track(entry)
  if not track then return false end
  refresh_entry_state(entry, track)
  if entry_blocked_state(entry) then return false end
  local hwnd = safe_trackfx_get_floating_window(track, entry.fx_index)
  if not hwnd then return false end
  set_topbar_owner(hwnd)
  local ok, left, top, right, bottom = r.JS_Window_GetRect(hwnd)
  if not ok or not left or not top or not right or not bottom or right <= left or bottom <= top then return false end
  measure_fx_window(entry, hwnd)
  local imgui_left, imgui_top = native_to_imgui(left, top)
  local imgui_right, imgui_bottom = native_to_imgui(right, bottom)
  local x_min = math.min(imgui_left, imgui_right)
  local x_max = math.max(imgui_left, imgui_right)
  local y_min = math.min(imgui_top, imgui_bottom)
  local y_max = math.max(imgui_top, imgui_bottom)
  host_rect.left = x_min
  host_rect.top = y_min
  host_rect.width = math.max(180, x_max - x_min)
  host_rect.height = math.max(140, y_max - y_min)
  follow_pair_on_top = foreground_is_topbar_pair(hwnd)
  return true
end

local function place_active_window()
  local dragging_topbar = topbar_drag_active()
  if settings.follow_fx_position and not dragging_topbar then return follow_fx_window_update() end
  if window_touch_paused() and not dragging_topbar then return false end
  if host_rect.width < 120 or host_rect.height < 90 then return false end
  if not r.JS_Window_SetPosition then return false end
  local entry = find_entry_by_key(active_key)
  if entry_blocked_state(entry) then return false end
  local track = resolve_entry_track(entry)
  if not track then return false end
  refresh_entry_state(entry, track)
  if entry_blocked_state(entry) then return false end
  local hwnd = safe_trackfx_get_floating_window(track, entry.fx_index)
  if not hwnd then return false end
  set_topbar_owner(hwnd)
  if not dragging_topbar then keep_topbar_above_fx(hwnd) end
  local pending_placement = r.time_precise() < pending_place_until
  if not dragging_topbar and not pending_placement and not foreground_allows_active_window_placement(hwnd) then return false end
  local pending_restack = r.time_precise() < topbar_restack_until and foreground_is_topbar_pair(hwnd)
  local resized_window = measure_fx_window(entry, hwnd)
  local size = cached_fx_size(entry)
  host_rect.width = size.width
  host_rect.height = size.height
  if not dragging_topbar then apply_centered_host_rect() end
  local native_x1, native_y1 = imgui_to_native(host_rect.left, host_rect.top)
  local native_x2, native_y2 = imgui_to_native(host_rect.left + host_rect.width, host_rect.top + host_rect.height)
  local native_left = js_int(math.min(native_x1, native_x2))
  local native_top = js_int(math.min(native_y1, native_y2))
  local native_right = js_int(math.max(native_x1, native_x2))
  local native_bottom = js_int(math.max(native_y1, native_y2))
  local moved_window = false
  if window_rect_needs_update(hwnd, native_left, native_top, native_right, native_bottom) then
    r.JS_Window_SetPosition(hwnd, native_left, native_top, native_right - native_left, native_bottom - native_top)
    moved_window = true
    topbar_restack_until = r.time_precise() + 0.35
  end
  if not dragging_topbar and (pending_placement or resized_window) then
    bring_topbar_pair_to_front(hwnd)
  elseif not dragging_topbar and (moved_window or pending_restack) then
    place_topbar_above_fx(hwnd)
  end
  return true
end

local function close_entry(entry)
  local track = resolve_entry_track(entry)
  if track then
    local hwnd = safe_trackfx_get_floating_window(track, entry.fx_index)
    if hwnd and hwnd == topbar_owner_fx_hwnd then clear_topbar_owner() end
    safe_trackfx_show(track, entry.fx_index, 2)
  end
end

local function focus_active_window()
  local entry = find_entry_by_key(active_key)
  if entry_blocked_state(entry) then return false end
  local track = resolve_entry_track(entry)
  if not track then return false end
  refresh_entry_state(entry, track)
  if entry_blocked_state(entry) then return false end
  local hwnd = safe_trackfx_get_floating_window(track, entry.fx_index)
  if not hwnd then
    if not safe_trackfx_show(track, entry.fx_index, 3) then return false end
    hwnd = safe_trackfx_get_floating_window(track, entry.fx_index)
  end
  if not hwnd then return false end
  bring_topbar_pair_to_front(hwnd)
  return true
end

local function process_pending_pair_front()
  if pending_pair_front_until <= 0 then return end
  local now = r.time_precise()
  if now > pending_pair_front_until then pending_pair_front_until = 0; return end
  if window_touch_paused() or topbar_mouse_captured then return end
  local entry = find_entry_by_key(active_key)
  if entry_blocked_state(entry) then
    if bring_blocked_pair_to_front() then pending_pair_front_until = 0 end
    return
  end
  if focus_active_window() then pending_pair_front_until = 0 end
end

local function update_topbar_focus_click()
  if not r.ImGui_IsWindowHovered or not r.ImGui_IsMouseClicked or not r.ImGui_IsMouseReleased or not r.ImGui_GetMousePos then return end
  if r.time_precise() < topbar_control_block_until then
    if r.ImGui_IsMouseReleased(ctx, 0) then
      topbar_mouse_captured = false
      topbar_focus_click_armed = false
      topbar_dragging = false
    end
    return
  end
  if r.ImGui_IsWindowHovered(ctx) and r.ImGui_IsMouseClicked(ctx, 0) then
    topbar_mouse_captured = true
    topbar_dragging = false
    local item_hovered = r.ImGui_IsAnyItemHovered and r.ImGui_IsAnyItemHovered(ctx)
    topbar_focus_click_armed = not item_hovered
    topbar_focus_click_x, topbar_focus_click_y = r.ImGui_GetMousePos(ctx)
  end
  if not topbar_focus_click_armed then
    if topbar_mouse_captured and r.ImGui_IsMouseReleased(ctx, 0) then
      if topbar_dragging then
        local now = r.time_precise()
        window_touch_pause_until = math.min(window_touch_pause_until, now + 0.04)
        topbar_restack_until = now + 0.35
        last_place_time = 0
        if entry_blocked_state(find_entry_by_key(active_key)) then pending_pair_front_until = now + 0.45 end
      end
      topbar_mouse_captured = false
      topbar_dragging = false
    end
    return
  end
  local mouse_x, mouse_y = r.ImGui_GetMousePos(ctx)
  local delta_x = mouse_x - topbar_focus_click_x
  local delta_y = mouse_y - topbar_focus_click_y
  local moved = (delta_x * delta_x + delta_y * delta_y) > 36
  if moved then topbar_focus_click_armed = false; topbar_dragging = true end
  if r.ImGui_IsMouseReleased(ctx, 0) then
    if topbar_dragging then
      local now = r.time_precise()
      window_touch_pause_until = math.min(window_touch_pause_until, now + 0.04)
      topbar_restack_until = now + 0.35
      last_place_time = 0
      if entry_blocked_state(find_entry_by_key(active_key)) then pending_pair_front_until = now + 0.45 end
    end
    if topbar_focus_click_armed and not topbar_dragging then pending_pair_front_until = r.time_precise() + 0.45 end
    topbar_mouse_captured = false
    topbar_focus_click_armed = false
    topbar_dragging = false
  end
end

local function open_topbar_popup(name)
  topbar_popup_active = true
  topbar_popup_hold_until = r.time_precise() + 0.75
  r.ImGui_OpenPopup(ctx, name)
end

local function topbar_popup_flags()
  local flags = 0
  flags = add_imgui_flag(flags, "ImGui_WindowFlags_TopMost")
  flags = add_imgui_flag(flags, "ImGui_WindowFlags_NoDocking")
  return flags
end

local function block_topbar_focus_click()
  topbar_focus_click_armed = false
  topbar_mouse_captured = false
  topbar_dragging = false
  topbar_control_block_until = r.time_precise() + 0.35
end

local function current_item_rect_clicked(clicked)
  if clicked then block_topbar_focus_click(); return true end
  if not r.ImGui_GetItemRectMin or not r.ImGui_GetItemRectMax or not r.ImGui_GetMousePos or not r.ImGui_IsMouseClicked then return false end
  if not r.ImGui_IsMouseClicked(ctx, 0) then return false end
  local left, top = r.ImGui_GetItemRectMin(ctx)
  local right, bottom = r.ImGui_GetItemRectMax(ctx)
  local mouse_x, mouse_y = r.ImGui_GetMousePos(ctx)
  local hit = mouse_x >= left and mouse_x <= right and mouse_y >= top and mouse_y <= bottom
  if hit then block_topbar_focus_click() end
  return hit
end

local function close_pending_previous()
  if pending_close_key == "" then return end
  local entry = find_entry_by_key(pending_close_key)
  if entry then close_entry(entry) end
  pending_close_key = ""
  pending_close_deadline = 0
end

local function close_active_window()
  local entry = find_entry_by_key(active_key)
  clear_topbar_owner()
  if entry then close_entry(entry) end
  close_pending_previous()
  pending_activate_key = ""
  pending_activate_frames = 0
  active_key = ""
  pending_place_until = 0
  pending_pair_front_until = 0
end

local function close_all_instruments()
  clear_topbar_owner()
  for entry_index = 1, #instruments do close_entry(instruments[entry_index]) end
  active_key = ""
  pending_activate_key = ""
  pending_activate_frames = 0
  pending_close_key = ""
  pending_close_deadline = 0
  external_open_state = {}
  pending_place_until = 0
  pending_pair_front_until = 0
end

local function activate_entry(entry)
  if not entry then return end
  local previous_key = active_key
  local track = resolve_entry_track(entry)
  if not track then return end
  refresh_entry_state(entry, track)
  if settings.select_track_on_open and r.SetOnlyTrackSelected then r.SetOnlyTrackSelected(track) end
  if entry_blocked_state(entry) then
    clear_topbar_owner()
    close_entry(entry)
    if previous_key ~= "" and previous_key ~= entry.key then
      local previous_entry = find_entry_by_key(previous_key)
      if previous_entry then close_entry(previous_entry) end
      pending_close_key = ""
      pending_close_deadline = 0
    end
    selected_key = entry.key
    active_key = entry.key
    sync_host_rect_to_entry_size(entry)
    pending_place_until = 0
    last_place_time = 0
    pending_pair_front_until = r.time_precise() + 0.45
    return
  end
  if not safe_trackfx_show(track, entry.fx_index, 3) then return end
  if previous_key ~= "" and previous_key ~= entry.key then
    pending_close_key = previous_key
    pending_close_deadline = r.time_precise() + 0.75
  end
  selected_key = entry.key
  active_key = entry.key
  sync_host_rect_to_entry_size(entry)
  pending_place_until = r.time_precise() + 1.25
  last_place_time = 0
end

local function request_activate_entry(entry)
  if not entry then return end
  selected_key = entry.key
  if entry.key == active_key then
    pending_activate_key = ""
    pending_activate_frames = 0
    return
  end
  pending_activate_key = entry.key
  pending_activate_frames = 2
end

local function process_pending_activation()
  if pending_activate_key == "" then return end
  if pending_activate_frames > 0 then
    pending_activate_frames = pending_activate_frames - 1
    return
  end
  local entry = find_entry_by_key(pending_activate_key)
  pending_activate_key = ""
  pending_activate_frames = 0
  if entry then activate_entry(entry) end
end

local function scan_instruments(force)
  local now = r.time_precise()
  if not force and now - last_scan_time < settings.scan_interval then return end
  last_scan_time = now
  force_scan = false
  local previous_selected_key = selected_key
  local next_instruments = {}
  local track_count = r.CountTracks(0)
  for track_index = 0, track_count - 1 do
    local track = r.GetTrack(0, track_index)
    if is_valid_media_track(track) then
      local primary_instrument = content_mode_instruments_only() and r.TrackFX_GetInstrument and r.TrackFX_GetInstrument(track) or -1
      local fx_count = r.TrackFX_GetCount(track)
      for fx_index = 0, fx_count - 1 do
        local retval, fx_name = r.TrackFX_GetFXName(track, fx_index, "")
        fx_name = retval and fx_name or "FX"
        if content_mode_allows_fx(fx_index, primary_instrument, fx_name) then
          local guid = track_guid(track)
          next_instruments[#next_instruments + 1] = {
            key = guid .. "|" .. tostring(fx_index),
            track_guid = guid,
            track_index = track_index,
            track_name = track_name(track, track_index),
            fx_index = fx_index,
            fx_name = fx_name,
            fx_label = clean_fx_name(fx_name),
            enabled = safe_trackfx_get_enabled(track, fx_index, true),
            offline = safe_trackfx_get_offline(track, fx_index, false),
          }
        end
      end
    end
  end
  instruments = next_instruments
  tab_width_cache = {}
  if #instruments == 0 then selected_key = ""; active_key = ""; return end
  if previous_selected_key ~= "" and find_entry_by_key(previous_selected_key) then selected_key = previous_selected_key else selected_key = instruments[1].key end
end

local function selected_track_entry()
  if not r.CountSelectedTracks or not r.GetSelectedTrack then return nil end
  if r.CountSelectedTracks(0) < 1 then return nil end
  local selected_track = r.GetSelectedTrack(0, 0)
  if not is_valid_media_track(selected_track) then return nil end
  local guid = track_guid(selected_track)
  for entry_index = 1, #instruments do
    local entry = instruments[entry_index]
    if entry.track_guid == guid then return entry end
  end
  return nil
end

local function normalized_tab_filter_mode()
  local mode = math.floor(tonumber(settings.tab_filter_mode) or TAB_FILTER_ALL)
  if mode < TAB_FILTER_ALL or mode > TAB_FILTER_GROUP then return TAB_FILTER_ALL end
  return mode
end

local function selected_track_guid_set()
  local set = {}
  local first_track = nil
  if not r.CountSelectedTracks or not r.GetSelectedTrack then return set, first_track, 0 end
  local count = r.CountSelectedTracks(0)
  for index = 0, count - 1 do
    local track = r.GetSelectedTrack(0, index)
    if is_valid_media_track(track) then
      set[track_guid(track)] = true
      if not first_track then first_track = track end
    end
  end
  return set, first_track, count
end

local function tab_filter_anchor_track()
  local _, first_selected_track = selected_track_guid_set()
  if first_selected_track then return first_selected_track end
  return resolve_entry_track(find_entry_by_key(active_key))
end

local function top_folder_track(track)
  if not is_valid_media_track(track) or not r.GetParentTrack then return track end
  local current = track
  local parent = r.GetParentTrack(current)
  while is_valid_media_track(parent) do
    current = parent
    parent = r.GetParentTrack(current)
  end
  return current
end

local TRACK_GROUP_NAMES = {
  "VOLUME_LEAD", "VOLUME_FOLLOW", "VOLUME_VCA_LEAD", "VOLUME_VCA_FOLLOW",
  "PAN_LEAD", "PAN_FOLLOW", "WIDTH_LEAD", "WIDTH_FOLLOW",
  "MUTE_LEAD", "MUTE_FOLLOW", "SOLO_LEAD", "SOLO_FOLLOW",
  "RECARM_LEAD", "RECARM_FOLLOW", "POLARITY_LEAD", "POLARITY_FOLLOW",
  "AUTOMODE_LEAD", "AUTOMODE_FOLLOW"
}

local function add_group_mask_tokens(tokens, group_name, mask, offset)
  mask = math.floor(tonumber(mask) or 0)
  if mask == 0 then return end
  for bit = 0, 31 do
    local flag = 1 << bit
    if (mask & flag) ~= 0 then tokens[tostring(offset + bit)] = true end
  end
end

local function track_group_tokens(track)
  local tokens = {}
  if not is_valid_media_track(track) or not r.GetSetTrackGroupMembership then return tokens end
  for index = 1, #TRACK_GROUP_NAMES do
    local group_name = TRACK_GROUP_NAMES[index]
    add_group_mask_tokens(tokens, group_name, r.GetSetTrackGroupMembership(track, group_name, 0, 0), 1)
    if r.GetSetTrackGroupMembershipHigh then add_group_mask_tokens(tokens, group_name, r.GetSetTrackGroupMembershipHigh(track, group_name, 0, 0), 33) end
  end
  return tokens
end

local function shares_group_tokens(track, anchor_tokens)
  local tokens = track_group_tokens(track)
  for token in pairs(tokens) do
    if anchor_tokens[token] then return true end
  end
  return false
end

local function visible_instruments()
  local mode = normalized_tab_filter_mode()
  if mode == TAB_FILTER_ALL then return instruments end
  local visible = {}
  if mode == TAB_FILTER_SELECTED then
    local selected_guids = selected_track_guid_set()
    for index = 1, #instruments do
      local entry = instruments[index]
      if selected_guids[entry.track_guid] then visible[#visible + 1] = entry end
    end
    return visible
  end
  local anchor_track = tab_filter_anchor_track()
  if not anchor_track then return instruments end
  if mode == TAB_FILTER_FOLDER then
    local anchor_folder = track_guid(top_folder_track(anchor_track))
    for index = 1, #instruments do
      local entry = instruments[index]
      local track = resolve_entry_track(entry)
      if track and track_guid(top_folder_track(track)) == anchor_folder then visible[#visible + 1] = entry end
    end
    return visible
  end
  if mode == TAB_FILTER_GROUP then
    local anchor_tokens = track_group_tokens(anchor_track)
    for index = 1, #instruments do
      local entry = instruments[index]
      local track = resolve_entry_track(entry)
      if track and shares_group_tokens(track, anchor_tokens) then visible[#visible + 1] = entry end
    end
    return visible
  end
  return instruments
end

local function entry_is_visible_in_tabs(key, entries)
  entries = entries or visible_instruments()
  for index = 1, #entries do
    if entries[index].key == key then return true end
  end
  return false
end

local function ensure_active_entry_visible()
  local entries = visible_instruments()
  if #entries == 0 then selected_key = ""; return end
  if active_key == "" then
    if not entry_is_visible_in_tabs(selected_key, entries) then selected_key = entries[1].key end
    return
  end
  if entry_is_visible_in_tabs(active_key, entries) then
    if not entry_is_visible_in_tabs(selected_key, entries) then selected_key = active_key end
    return
  end
  activate_entry(entries[1])
end

local function open_startup_instrument()
  if startup_open_done then return end
  startup_open_done = true
  if not settings.auto_open_on_start or active_key ~= "" or #instruments == 0 then return end
  activate_entry(selected_track_entry() or instruments[1])
end

local function close_existing_instruments_on_start()
  if startup_clean_done then return end
  startup_clean_done = true
  if #instruments > 0 then close_all_instruments() end
end

local function file_exists(path)
  local file = io.open(path, "r")
  if file then file:close(); return true end
  return false
end

local function extract_fx_entry(entry)
  if type(entry) == "string" then return entry, entry end
  if type(entry) == "table" then
    local name = entry.name or entry.fxname or entry.fxName or entry.fname or entry.FX_NAME or entry[1]
    local addname = entry.addname or entry.fullname or entry.name or entry.fxname or entry[2] or name
    if name or addname then return tostring(name or addname), tostring(addname or name) end
  end
  return nil, nil
end

local function append_fx_item(out, seen, display, addname)
  if type(addname) ~= "string" or addname == "" or seen[addname] then return end
  out[#out + 1] = { display = clean_fx_name(display or addname), addname = addname }
  seen[addname] = true
end

local function item_list_from_names(names, instruments_only)
  local out = {}
  local seen = {}
  for index = 1, #(names or {}) do
    local name = names[index]
    if type(name) == "string" and (not instruments_only or is_instrument_fx_name(name)) then append_fx_item(out, seen, name, name) end
  end
  table.sort(out, function(a, b) return (a.display or ""):lower() < (b.display or ""):lower() end)
  return out
end

local function sorted_keys(tbl)
  local keys = {}
  for key in pairs(tbl or {}) do keys[#keys + 1] = key end
  table.sort(keys, function(a, b) return tostring(a):lower() < tostring(b):lower() end)
  return keys
end

local function find_cat_entry(cat_tbl, name)
  for index = 1, #(cat_tbl or {}) do
    if cat_tbl[index].name == name then return cat_tbl[index] end
  end
  return nil
end

local function folder_node_has_content(node)
  return node and ((node.items and #node.items > 0) or next(node.children or {}) ~= nil)
end

local function add_folder_entry(node, folder_entry, instruments_only)
  if type(folder_entry) ~= "table" or not folder_entry.name then return end
  node.children = node.children or {}
  node.items = node.items or {}
  local child = node.children[folder_entry.name] or { name = folder_entry.name, children = {}, items = {} }
  if type(folder_entry.fx) == "table" then
    local items = item_list_from_names(folder_entry.fx, instruments_only)
    for index = 1, #items do child.items[#child.items + 1] = items[index] end
  end
  if type(folder_entry.list) == "table" then
    for index = 1, #folder_entry.list do
      local value = folder_entry.list[index]
      if type(value) == "table" and value.name then add_folder_entry(child, value, instruments_only) end
    end
  end
  if folder_node_has_content(child) then node.children[folder_entry.name] = child end
end

local function build_instrument_struct(list, cat_tbl)
  local struct = { all = {}, types = {}, categories = {}, developers = {}, folders = { name = "ROOT", children = {}, items = {} } }
  local all_seen = {}
  local instruments_only = content_mode_instruments_only()
  local all = find_cat_entry(cat_tbl, "ALL PLUGINS")
  if all and all.list then
    for index = 1, #all.list do
      local entry = all.list[index]
      if type(entry) == "table" and entry.name and entry.fx then
        local items = item_list_from_names(entry.fx, instruments_only)
        if #items > 0 then
          struct.types[entry.name] = items
          for item_index = 1, #items do append_fx_item(struct.all, all_seen, items[item_index].display, items[item_index].addname) end
        end
      end
    end
  end
  table.sort(struct.all, function(a, b) return (a.display or ""):lower() < (b.display or ""):lower() end)
  if #struct.all == 0 then
    local flat, seen = {}, {}
    local function flatten(obj, depth)
      if depth > 6 then return end
      local display, addname = extract_fx_entry(obj)
      if not instruments_only or is_instrument_fx_name(addname) then append_fx_item(flat, seen, display or addname, addname) end
      if type(obj) == "table" then
        for _, value in pairs(obj) do
          if type(value) == "table" or type(value) == "string" then flatten(value, depth + 1) end
        end
      end
    end
    flatten(list, 0)
    table.sort(flat, function(a, b) return (a.display or ""):lower() < (b.display or ""):lower() end)
    struct.all = flat
  end
  local category = find_cat_entry(cat_tbl, "CATEGORY")
  if category and category.list then
    for index = 1, #category.list do
      local entry = category.list[index]
      if type(entry) == "table" and entry.name and entry.fx then
        local items = item_list_from_names(entry.fx, instruments_only)
        if #items > 0 then struct.categories[entry.name] = items end
      end
    end
  end
  local developer = find_cat_entry(cat_tbl, "DEVELOPER")
  if developer and developer.list then
    for index = 1, #developer.list do
      local entry = developer.list[index]
      if type(entry) == "table" and entry.name and entry.fx then
        local items = item_list_from_names(entry.fx, instruments_only)
        if #items > 0 then struct.developers[entry.name] = items end
      end
    end
  end
  local folders = find_cat_entry(cat_tbl, "FOLDERS")
  if folders and folders.list then
    for index = 1, #folders.list do add_folder_entry(struct.folders, folders.list[index], instruments_only) end
  end
  return struct
end

local function load_instrument_items(force)
  local current_content_mode = normalized_content_mode()
  if add_instrument_items and add_instrument_content_mode == current_content_mode and not force then return add_instrument_items, nil end
  local parser_path = r.GetResourcePath() .. "/Scripts/Sexan_Scripts/FX/Sexan_FX_Browser_ParserV7.lua"
  if not sexan_parser_loaded then
    if not file_exists(parser_path) then add_instrument_error = "Sexan FX Browser Parser V7 not found."; return nil, add_instrument_error end
    local ok, err = pcall(dofile, parser_path)
    if not ok then add_instrument_error = "Sexan parser error: " .. tostring(err); return nil, add_instrument_error end
    sexan_parser_loaded = true
  end
  local list, cat_tbl, dev_list = nil, nil, nil
  if type(ReadFXFile) == "function" then list, cat_tbl, dev_list = ReadFXFile() end
  if (not list or not cat_tbl) and type(MakeFXFiles) == "function" then
    local ok, fx_list, cat, dev = pcall(MakeFXFiles)
    if ok then list, cat_tbl, dev_list = fx_list, cat, dev end
  end
  if (not list or not cat_tbl) and type(GetFXTbl) == "function" then
    local ok, fx_list, cat, dev = pcall(GetFXTbl)
    if ok then list, cat_tbl, dev_list = fx_list, cat, dev end
  end
  if not list or not cat_tbl then add_instrument_error = "Could not load FX list."; return nil, add_instrument_error end
  add_instrument_struct = build_instrument_struct(list, cat_tbl)
  add_instrument_items = add_instrument_struct.all or {}
  add_instrument_content_mode = current_content_mode
  add_instrument_error = nil
  return add_instrument_items, nil
end

local function target_track_for_new_instrument()
  if r.CountSelectedTracks and r.GetSelectedTrack and r.CountSelectedTracks(0) > 0 then
    local track = r.GetSelectedTrack(0, 0)
    if is_valid_media_track(track) then return track end
  end
  local index = r.CountTracks(0)
  r.InsertTrackAtIndex(index, true)
  return r.GetTrack(0, index)
end

local function add_instrument_to_project(item)
  if not item or not item.addname then return end
  local instruments_only = content_mode_instruments_only()
  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)
  local track = target_track_for_new_instrument()
  local new_index = -1
  if track then new_index = r.TrackFX_AddByName(track, item.addname, false, -1) end
  r.PreventUIRefresh(-1)
  r.TrackList_AdjustWindows(false)
  r.UpdateArrange()
  r.Undo_EndBlock(instruments_only and "Add instrument from TK FX Tabs" or "Add FX from TK FX Tabs", -1)
  if not track then add_instrument_error = "Could not create or find target track."; return end
  if not new_index or new_index < 0 then add_instrument_error = instruments_only and "Instrument could not be added." or "FX could not be added."; return end
  if settings.select_track_on_open and r.SetOnlyTrackSelected then r.SetOnlyTrackSelected(track) end
  scan_instruments(true)
  local entry = find_entry_by_key(track_guid(track) .. "|" .. tostring(new_index))
  if entry then request_activate_entry(entry) end
  add_instrument_error = nil
  add_instrument_search = ""
end

local function queue_add_instrument(item)
  if not item or not item.addname then return end
  pending_add_instrument_item = item
  r.ImGui_CloseCurrentPopup(ctx)
end

local function draw_instrument_item_list(items)
  if not items or #items == 0 then r.ImGui_TextDisabled(ctx, content_mode_instruments_only() and "No instruments" or "No FX"); return end
  for index = 1, #items do
    local item = items[index]
    local label = tostring(item.display or item.addname or "FX") .. "##fx_item_" .. tostring(index) .. "_" .. tostring(item.addname or "")
    if r.ImGui_Selectable(ctx, label) then queue_add_instrument(item) end
  end
end

local function normalized_search_text(text)
  text = tostring(text or ""):lower()
  return text:gsub("^%s+", ""):gsub("%s+$", "")
end

local function instrument_item_matches_search(item, search)
  if search == "" then return false end
  local display = tostring(item and item.display or "")
  local addname = tostring(item and item.addname or "")
  local haystack = (display .. " " .. addname .. " " .. clean_fx_name(addname)):lower()
  return haystack:find(search, 1, true) ~= nil
end

local function draw_instrument_search_results(items)
  local search = normalized_search_text(add_instrument_search)
  if search == "" then return end
  local shown = 0
  local limit = 40
  for index = 1, #(items or {}) do
    local item = items[index]
    if instrument_item_matches_search(item, search) then
      shown = shown + 1
      local label = tostring(item.display or item.addname or "FX") .. "##fx_search_" .. tostring(index) .. "_" .. tostring(item.addname or "")
      if shown <= limit and r.ImGui_Selectable(ctx, label) then queue_add_instrument(item) end
    end
  end
  if shown == 0 then r.ImGui_TextDisabled(ctx, "No search results") end
  if shown > limit then r.ImGui_TextDisabled(ctx, tostring(shown - limit) .. " more results") end
end

local function draw_named_instrument_menus(label, lists)
  if r.ImGui_BeginMenu(ctx, label) then
    local keys = sorted_keys(lists)
    if #keys == 0 then r.ImGui_TextDisabled(ctx, "No entries") end
    for index = 1, #keys do
      if r.ImGui_BeginMenu(ctx, keys[index]) then
        draw_instrument_item_list(lists[keys[index]])
        r.ImGui_EndMenu(ctx)
      end
    end
    r.ImGui_EndMenu(ctx)
  end
end

local function draw_folder_instrument_menus(node)
  if node and node.items and #node.items > 0 then draw_instrument_item_list(node.items) end
  local keys = sorted_keys(node and node.children or {})
  for index = 1, #keys do
    local child = node.children[keys[index]]
    if folder_node_has_content(child) and r.ImGui_BeginMenu(ctx, keys[index]) then
      draw_folder_instrument_menus(child)
      r.ImGui_EndMenu(ctx)
    end
  end
end

local function draw_add_instrument_popup()
  if r.ImGui_BeginPopup(ctx, "Add FX Menu", topbar_popup_flags()) then
    topbar_popup_active = true
    local _, load_err = load_instrument_items(false)
    local struct = add_instrument_struct or {}
    if load_err then
      r.ImGui_TextDisabled(ctx, load_err)
    else
      if r.ImGui_InputText then
        local changed_search, next_search = r.ImGui_InputText(ctx, "Search##add_fx_search", add_instrument_search)
        if changed_search then add_instrument_search = next_search end
        local search = normalized_search_text(add_instrument_search)
        if search ~= "" then
          draw_instrument_search_results(struct.all or add_instrument_items or {})
          r.ImGui_Separator(ctx)
        end
      end
      if r.ImGui_BeginMenu(ctx, content_mode_instruments_only() and "ALL INSTRUMENTS" or "ALL FX") then
        draw_instrument_item_list(struct.all or add_instrument_items or {})
        r.ImGui_EndMenu(ctx)
      end
      draw_named_instrument_menus("TYPE", struct.types or {})
      draw_named_instrument_menus("CATEGORY", struct.categories or {})
      draw_named_instrument_menus("DEVELOPER", struct.developers or {})
      local folders_node = struct.folders or { children = {}, items = {} }
      if folder_node_has_content(folders_node) then
        if r.ImGui_BeginMenu(ctx, "FOLDERS") then
          draw_folder_instrument_menus(folders_node)
          r.ImGui_EndMenu(ctx)
        end
      end
    end
    if add_instrument_error then r.ImGui_TextDisabled(ctx, add_instrument_error) end
    r.ImGui_Separator(ctx)
    if r.ImGui_MenuItem(ctx, content_mode_instruments_only() and "Refresh instrument list" or "Refresh FX list") then load_instrument_items(true) end
    r.ImGui_EndPopup(ctx)
  end
  if pending_add_instrument_item then
    local item = pending_add_instrument_item
    pending_add_instrument_item = nil
    add_instrument_to_project(item)
  end
end

local function find_entry_index_by_key(key)
  for index = 1, #instruments do
    if instruments[index].key == key then return index end
  end
  return nil
end

local function find_entry_after_delete(track_guid_value, fx_index, fx_name)
  local key = track_guid_value .. "|" .. tostring(fx_index)
  local entry = find_entry_by_key(key)
  if entry then return entry end
  for index = 1, #instruments do
    local candidate = instruments[index]
    if candidate.track_guid == track_guid_value and candidate.fx_name == fx_name then return candidate end
  end
  return nil
end

local function set_entry_bypass(entry, bypassed)
  local track = resolve_entry_track(entry)
  if not track then return end
  if bypassed then cache_entry_current_fx_window_size(entry, track) end
  r.Undo_BeginBlock()
  local ok = safe_trackfx_set_enabled(track, entry.fx_index, not bypassed)
  r.Undo_EndBlock(bypassed and "Bypass FX" or "Unbypass FX", -1)
  if not ok then return end
  if bypassed then close_entry(entry) end
  scan_instruments(true)
  local updated = find_entry_by_key(entry.key)
  if updated then activate_entry(updated) end
end

local function set_entry_offline(entry, offline)
  local track = resolve_entry_track(entry)
  if not track then return end
  if offline then cache_entry_current_fx_window_size(entry, track) end
  r.Undo_BeginBlock()
  local ok = safe_trackfx_set_offline(track, entry.fx_index, offline)
  r.Undo_EndBlock(offline and "Set FX offline" or "Set FX online", -1)
  if not ok then return end
  if offline then close_entry(entry) end
  scan_instruments(true)
  local updated = find_entry_by_key(entry.key)
  if updated then activate_entry(updated) end
end

local function remove_entry(entry)
  local track = resolve_entry_track(entry)
  if not track then return end
  local entry_index = find_entry_index_by_key(entry.key)
  local target = entry_index and (instruments[entry_index + 1] or instruments[entry_index - 1]) or nil
  local target_guid, target_fx_index, target_fx_name = nil, nil, nil
  if target then
    target_guid = target.track_guid
    target_fx_index = target.fx_index
    target_fx_name = target.fx_name
    if target.track_guid == entry.track_guid and target.fx_index > entry.fx_index then target_fx_index = target_fx_index - 1 end
  end
  close_entry(entry)
  r.Undo_BeginBlock()
  local ok = safe_trackfx_delete(track, entry.fx_index)
  r.Undo_EndBlock("Remove FX", -1)
  if not ok then return end
  pending_activate_key = ""
  pending_activate_frames = 0
  pending_close_key = ""
  pending_close_deadline = 0
  scan_instruments(true)
  local next_entry = target_guid and find_entry_after_delete(target_guid, target_fx_index, target_fx_name) or nil
  if next_entry then
    activate_entry(next_entry)
  elseif #instruments > 0 then
    selected_key = instruments[1].key
    if active_key == entry.key then active_key = "" end
  else
    selected_key = ""
    active_key = ""
  end
end

local function draw_tab_context_popup()
  if r.ImGui_BeginPopup(ctx, "FX Tab Context", topbar_popup_flags()) then
    topbar_popup_active = true
    local entry = find_entry_by_key(tab_context_key)
    if entry then
      local bypassed = entry.enabled == false
      local offline = entry.offline == true
      local changed_bypass, next_bypass = r.ImGui_Checkbox(ctx, "Bypass", bypassed)
      if changed_bypass then set_entry_bypass(entry, next_bypass); r.ImGui_CloseCurrentPopup(ctx) end
      local changed_offline, next_offline = r.ImGui_Checkbox(ctx, "Offline", offline)
      if changed_offline then set_entry_offline(entry, next_offline); r.ImGui_CloseCurrentPopup(ctx) end
      local track = resolve_entry_track(entry)
      if track and entry_supports_midi_input(entry, track) and r.ImGui_BeginCombo then
        local current_input = math.floor(r.GetMediaTrackInfo_Value(track, "I_RECINPUT") or -1)
        if r.ImGui_BeginCombo(ctx, "MIDI input", midi_input_label(current_input)) then
          local options = midi_input_options()
          for option_index = 1, #options do
            local option = options[option_index]
            local selected = current_input == option.value
            if r.ImGui_Selectable(ctx, option.label, selected) then
              set_track_midi_input(track, option.value)
              current_input = option.value
            end
            if selected and r.ImGui_SetItemDefaultFocus then r.ImGui_SetItemDefaultFocus(ctx) end
          end
          r.ImGui_EndCombo(ctx)
        end
      end
      r.ImGui_Separator(ctx)
      if r.ImGui_Selectable(ctx, "Remove") then remove_entry(entry); r.ImGui_CloseCurrentPopup(ctx) end
    else
      r.ImGui_TextDisabled(ctx, "FX not found")
    end
    r.ImGui_EndPopup(ctx)
  end
end

function set_theme_preset(name)
  settings.theme_preset = name or "REAPER Theme"
  ext_set_string("theme_preset", settings.theme_preset)
end

function is_reserved_theme_name(name)
  local normalized = trim_text(name):lower()
  if normalized == "" or normalized == THEME_UNSAVED:lower() then return true end
  if normalized == "reaper theme" then return true end
  for preset_name in pairs(THEME_PRESETS) do
    if preset_name:lower() == normalized then return true end
  end
  return false
end

function custom_theme_names()
  local names = {}
  for name in pairs(custom_themes or {}) do names[#names + 1] = name end
  table.sort(names, function(a, b) return a:lower() < b:lower() end)
  return names
end

function draw_theme_preview(colors)
  local draw_list = r.ImGui_GetWindowDrawList(ctx)
  local x, y = r.ImGui_GetCursorScreenPos(ctx)
  local size = 18
  local gap = 6
  local swatches = { colors.window_bg, colors.panel_bg, colors.edit_bg, colors.tab_active, colors.warning, colors.danger }
  for index, color in ipairs(swatches) do
    local left = x + (index - 1) * (size + gap)
    r.ImGui_DrawList_AddRectFilled(draw_list, left, y, left + size, y + size, color, 3)
    r.ImGui_DrawList_AddRect(draw_list, left, y, left + size, y + size, colors.border, 3, 0, 1)
  end
  r.ImGui_Dummy(ctx, (#swatches * (size + gap)) - gap, size)
end

function save_current_custom_theme()
  local name = trim_text(theme_edit_name)
  if name == "" then theme_status = "Custom theme name required"; return end
  if is_reserved_theme_name(name) then theme_status = "Reserved theme names cannot be overwritten"; return end
  local existed = custom_themes[name] ~= nil
  custom_themes[name] = copy_theme_colors(unsaved_theme_colors or theme)
  save_custom_themes()
  theme_edit_name = name
  ext_set_string("custom_theme_name", name)
  set_theme_preset(name)
  unsaved_theme_colors = nil
  theme_status = existed and "Updated custom theme: " .. name or "Saved custom theme: " .. name
end

function delete_current_custom_theme()
  local name = trim_text(theme_edit_name)
  if name == "" then theme_status = "Custom theme name required"; return end
  if is_reserved_theme_name(name) then theme_status = "Reserved themes cannot be deleted"; return end
  if not custom_themes[name] then theme_status = "Custom theme not found: " .. name; return end
  custom_themes[name] = nil
  save_custom_themes()
  if settings.theme_preset == name then set_theme_preset("REAPER Theme") end
  theme_status = "Deleted custom theme: " .. name
end

function draw_theme_settings()
  if not r.ImGui_BeginMenu(ctx, "Theme") then return end
  local current = settings.theme_preset or "REAPER Theme"
  if r.ImGui_BeginCombo(ctx, "Preset", current) then
    for _, name in ipairs(THEME_PRESET_NAMES) do
      local selected = current == name
      if r.ImGui_Selectable(ctx, name, selected) then set_theme_preset(name); unsaved_theme_colors = nil; theme_status = "Theme preset: " .. name end
      if selected and r.ImGui_SetItemDefaultFocus then r.ImGui_SetItemDefaultFocus(ctx) end
    end
    local custom_names = custom_theme_names()
    if #custom_names > 0 then r.ImGui_Separator(ctx) end
    for _, name in ipairs(custom_names) do
      local selected = current == name
      if r.ImGui_Selectable(ctx, name .. "##custom_theme", selected) then set_theme_preset(name); theme_edit_name = name; ext_set_string("custom_theme_name", name); unsaved_theme_colors = nil; theme_status = "Theme preset: " .. name end
      if selected and r.ImGui_SetItemDefaultFocus then r.ImGui_SetItemDefaultFocus(ctx) end
    end
    r.ImGui_EndCombo(ctx)
  end
  if r.ImGui_Button(ctx, "Refresh REAPER Theme", 150, 0) then set_theme_preset("REAPER Theme"); unsaved_theme_colors = nil; theme_status = "REAPER theme colors refreshed" end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Read colors from the active REAPER theme") end
  local changed_border, next_border = r.ImGui_Checkbox(ctx, "Tab bar border", settings.theme_topbar_border ~= false)
  if changed_border then settings.theme_topbar_border = next_border; ext_set_bool("theme_topbar_border", next_border) end
  r.ImGui_Separator(ctx)
  r.ImGui_TextColored(ctx, theme.text_dim, "Preview")
  draw_theme_preview(theme)
  if r.ImGui_BeginChild(ctx, "##theme_color_editor", 0, 185, 1) then
    local color_flags = r.ImGui_ColorEditFlags_NoInputs and r.ImGui_ColorEditFlags_NoInputs() or 0
    for _, field in ipairs(THEME_COLOR_FIELDS) do
      local changed, value = r.ImGui_ColorEdit4(ctx, field.label .. "##" .. field.key, (unsaved_theme_colors and unsaved_theme_colors[field.key]) or theme[field.key], color_flags)
      if changed then
        unsaved_theme_colors = complete_theme_colors(copy_theme_colors(unsaved_theme_colors or theme))
        unsaved_theme_colors[field.key] = value
        set_theme_preset(THEME_UNSAVED)
        theme_status = "Theme changes are not saved yet"
      end
    end
  end
  r.ImGui_EndChild(ctx)
  if r.ImGui_InputTextWithHint then
    local changed_name, next_name = r.ImGui_InputTextWithHint(ctx, "##custom_theme_name", "Custom theme name", theme_edit_name)
    if changed_name then theme_edit_name = next_name; ext_set_string("custom_theme_name", next_name) end
  elseif r.ImGui_InputText then
    local changed_name, next_name = r.ImGui_InputText(ctx, "Custom theme name", theme_edit_name)
    if changed_name then theme_edit_name = next_name; ext_set_string("custom_theme_name", next_name) end
  end
  local theme_name = trim_text(theme_edit_name)
  local theme_exists = custom_themes and custom_themes[theme_name] ~= nil
  local save_label = theme_exists and "Update Custom##save_custom_theme" or "Save Custom##save_custom_theme"
  if r.ImGui_Button(ctx, save_label, 110, 0) then save_current_custom_theme() end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, theme_exists and "Update existing custom theme" or "Save current colors as custom theme") end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "Delete Custom", 110, 0) then delete_current_custom_theme() end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Delete custom theme by name") end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "Reset", 70, 0) then set_theme_preset("REAPER Theme"); unsaved_theme_colors = nil; theme_status = "Theme preset reset" end
  if theme_status ~= "" then r.ImGui_TextColored(ctx, theme.text_dim, theme_status) end
  r.ImGui_EndMenu(ctx)
end

local function draw_settings_popup()
  if r.ImGui_BeginPopup(ctx, "FX Tabs Settings", topbar_popup_flags()) then
    topbar_popup_active = true
    if r.ImGui_Button(ctx, "Scan / Refresh", 132, 0) then scan_instruments(true) end
    if r.ImGui_SliderInt then
      local changed_overlap, next_overlap = r.ImGui_SliderInt(ctx, "Plugin top overlap", settings.plugin_overlap_y, 0, 80, "%d px")
      if changed_overlap then settings.plugin_overlap_y = next_overlap; ext_set_number("plugin_overlap_y", next_overlap); pending_place_until = r.time_precise() + 0.5 end
      local changed_left_overhang, next_left_overhang = r.ImGui_SliderInt(ctx, "Tab bar left edge", topbar_left_overhang(), -24, 48, "%d px")
      if changed_left_overhang then settings.topbar_left_overhang = next_left_overhang; ext_set_number("topbar_left_overhang", next_left_overhang); update_topbar_width_from_size(topbar_width); pending_place_until = r.time_precise() + 0.5; last_place_time = 0 end
      local changed_right_overhang, next_right_overhang = r.ImGui_SliderInt(ctx, "Tab bar right edge", topbar_right_overhang(), -24, 48, "%d px")
      if changed_right_overhang then settings.topbar_right_overhang = next_right_overhang; ext_set_number("topbar_right_overhang", next_right_overhang); update_topbar_width_from_size(topbar_width); pending_place_until = r.time_precise() + 0.5; last_place_time = 0 end
      local changed_voffset, next_voffset = r.ImGui_SliderInt(ctx, "Tab bar vertical offset", topbar_vertical_offset(), -120, 120, "%d px")
      if changed_voffset then settings.vertical_offset = next_voffset; ext_set_number("vertical_offset", next_voffset); pending_place_until = r.time_precise() + 0.5; last_place_time = 0 end
      if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Fine-tune the vertical position of the tab bar.") end
    end
    local changed_start, next_start = r.ImGui_Checkbox(ctx, "Open FX on start", settings.auto_open_on_start)
    if changed_start then settings.auto_open_on_start = next_start; ext_set_bool("auto_open_on_start", next_start); if next_start and active_key == "" then startup_open_done = false; open_startup_instrument() end end
    local changed_capture, next_capture = r.ImGui_Checkbox(ctx, "Capture externally opened FX", settings.capture_external_floating)
    if changed_capture then settings.capture_external_floating = next_capture; ext_set_bool("capture_external_floating", next_capture); external_open_state = {} end
    local center_disabled = settings.follow_fx_position == true
    if center_disabled and r.ImGui_BeginDisabled then r.ImGui_BeginDisabled(ctx, true) end
    local changed_center, next_center = r.ImGui_Checkbox(ctx, "Center FX in REAPER window", settings.center_fx_in_reaper_window)
    if changed_center then settings.center_fx_in_reaper_window = next_center; ext_set_bool("center_fx_in_reaper_window", next_center); pending_place_until = r.time_precise() + 0.5; last_place_time = 0 end
    if center_disabled and r.ImGui_EndDisabled then r.ImGui_EndDisabled(ctx) end
    if center_disabled and r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "No effect while Follow FX window is on.") end
    local changed_follow, next_follow = r.ImGui_Checkbox(ctx, "Follow FX window (tab follows plugin)", settings.follow_fx_position)
    if changed_follow then
      settings.follow_fx_position = next_follow
      ext_set_bool("follow_fx_position", next_follow)
      if next_follow and settings.center_fx_in_reaper_window then
        settings.center_fx_in_reaper_window = false
        ext_set_bool("center_fx_in_reaper_window", false)
      end
      pending_place_until = r.time_precise() + 0.5
      last_place_time = 0
    end
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "The tab bar follows the plugin window instead of moving it.\nDisables centering while active.") end
    local changed_flip, next_flip = r.ImGui_Checkbox(ctx, "Tab bar below plugin (flip)", settings.vertical_flip == true)
    if changed_flip then settings.vertical_flip = next_flip; ext_set_bool("vertical_flip", next_flip); pending_place_until = r.time_precise() + 0.5; last_place_time = 0 end
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Place the tab bar on the opposite (bottom) side of the plugin.\nWorks in all modes. Also fixes macOS setups where the bar\nappears at the bottom instead of the top.") end
    local changed_numbers, next_numbers = r.ImGui_Checkbox(ctx, "Show track numbers", settings.show_track_numbers ~= false)
    if changed_numbers then settings.show_track_numbers = next_numbers; ext_set_bool("show_track_numbers", next_numbers); tab_width_cache = {} end
    if r.ImGui_BeginCombo then
      local current_content = normalized_content_mode()
      if r.ImGui_BeginCombo(ctx, "Content", CONTENT_MODE_LABELS[current_content + 1] or CONTENT_MODE_LABELS[1]) then
        for mode = CONTENT_MODE_ALL_FX, CONTENT_MODE_INSTRUMENTS do
          local selected = current_content == mode
          if r.ImGui_Selectable(ctx, CONTENT_MODE_LABELS[mode + 1], selected) then
            settings.content_mode = mode
            ext_set_number("content_mode", mode)
            add_instrument_items = nil
            add_instrument_struct = nil
            add_instrument_content_mode = nil
            tab_scroll_x = 0
            scan_instruments(true)
            ensure_active_entry_visible()
            pending_place_until = r.time_precise() + 0.5
            last_place_time = 0
          end
          if selected and r.ImGui_SetItemDefaultFocus then r.ImGui_SetItemDefaultFocus(ctx) end
        end
        r.ImGui_EndCombo(ctx)
      end
      local current_filter = normalized_tab_filter_mode()
      if r.ImGui_BeginCombo(ctx, "Show tabs", TAB_FILTER_LABELS[current_filter + 1] or TAB_FILTER_LABELS[1]) then
        for mode = TAB_FILTER_ALL, TAB_FILTER_GROUP do
          local selected = current_filter == mode
          if r.ImGui_Selectable(ctx, TAB_FILTER_LABELS[mode + 1], selected) then
            settings.tab_filter_mode = mode
            ext_set_number("tab_filter_mode", mode)
            tab_scroll_x = 0
            ensure_active_entry_visible()
            pending_place_until = r.time_precise() + 0.5
            last_place_time = 0
          end
          if selected and r.ImGui_SetItemDefaultFocus then r.ImGui_SetItemDefaultFocus(ctx) end
        end
        r.ImGui_EndCombo(ctx)
      end
    end
    local changed_select, next_select = r.ImGui_Checkbox(ctx, "Select track on tab change", settings.select_track_on_open)
    if changed_select then settings.select_track_on_open = next_select; ext_set_bool("select_track_on_open", next_select) end
    r.ImGui_Separator(ctx)
    r.ImGui_TextColored(ctx, theme.text_dim, owner_pairing_status_label())
    r.ImGui_Separator(ctx)
    draw_theme_settings()
    r.ImGui_EndPopup(ctx)
  end
end

local function draw_toolbar()
  local active_entry = find_entry_by_key(active_key)
  local label = active_entry and (active_entry.track_name .. " / " .. active_entry.fx_label) or (content_mode_instruments_only() and "Select instrument" or "Select FX")
  if current_item_rect_clicked(r.ImGui_Button(ctx, "+", 28, 0)) then open_topbar_popup("Add FX Menu") end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, content_mode_instruments_only() and "Add instrument" or "Add FX") end
  draw_add_instrument_popup()
  r.ImGui_SameLine(ctx)
  r.ImGui_TextColored(ctx, theme.text_dim, label)
  r.ImGui_SameLine(ctx)
  if r.ImGui_SetCursorPosX and r.ImGui_GetWindowSize then
    local window_w = select(1, r.ImGui_GetWindowSize(ctx))
    r.ImGui_SetCursorPosX(ctx, math.max(0, window_w - 62))
  end
  if current_item_rect_clicked(r.ImGui_Button(ctx, "...", 28, 0)) then open_topbar_popup("FX Tabs Settings") end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Settings") end
  r.ImGui_SameLine(ctx, 0, 7)
  local dot_x, dot_y = r.ImGui_GetCursorScreenPos(ctx)
  local dot_size = 18
  local close_clicked = false
  if r.ImGui_InvisibleButton then
    close_clicked = r.ImGui_InvisibleButton(ctx, "##close_script", dot_size, dot_size)
  elseif r.ImGui_Button(ctx, "##close_script", dot_size, dot_size) then
    close_clicked = true
  end
  if current_item_rect_clicked(close_clicked) then close_requested = true end
  local dot_col = r.ImGui_IsItemHovered(ctx) and 0xFF6B6BFF or 0xD84A4AFF
  r.ImGui_DrawList_AddCircleFilled(r.ImGui_GetWindowDrawList(ctx), dot_x + dot_size * 0.5, dot_y + dot_size * 0.5, 5.5, dot_col, 18)
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Close") end
  draw_settings_popup()
end

local function tab_width(entry)
  if tab_width_cache[entry.key] then return tab_width_cache[entry.key] end
  local text_w = 88
  if r.ImGui_CalcTextSize then text_w = r.ImGui_CalcTextSize(ctx, entry_label(entry)) or text_w end
  local width = clamp(text_w + 34, 92, 220)
  tab_width_cache[entry.key] = width
  return width
end

local function scroll_active_tab_into_view(entries, view_width)
  local cursor = 0
  for entry_index = 1, #entries do
    local entry = entries[entry_index]
    local width = tab_width(entry)
    if entry.key == selected_key then
      if cursor < tab_scroll_x then tab_scroll_x = cursor end
      if cursor + width > tab_scroll_x + view_width then tab_scroll_x = cursor + width - view_width end
      return
    end
    cursor = cursor + width + 4
  end
end

function tab_modifier_down(name)
  local flag_function = r[name]
  if not flag_function or not r.ImGui_GetKeyMods then return false end
  local mods = r.ImGui_GetKeyMods(ctx)
  return (mods & flag_function()) ~= 0
end

function handle_tab_activation_click(entry)
  local toggled = false
  if tab_modifier_down("ImGui_Mod_Alt") then
    set_entry_offline(entry, not (entry.offline == true))
    toggled = true
  elseif tab_modifier_down("ImGui_Mod_Ctrl") or tab_modifier_down("ImGui_Mod_Super") then
    set_entry_bypass(entry, not (entry.enabled == false))
    toggled = true
  end
  if toggled then block_topbar_focus_click(); return end
  if entry.key == active_key then focus_active_window() else request_activate_entry(entry) end
end

local function draw_custom_tabs()
  local draw_list = r.ImGui_GetWindowDrawList(ctx)
  local x, y = r.ImGui_GetCursorScreenPos(ctx)
  local available_w = select(1, r.ImGui_GetContentRegionAvail(ctx))
  local tab_h = 26
  local overflow_w = 32
  local tab_entries = visible_instruments()
  local total_w = 0
  for entry_index = 1, #tab_entries do total_w = total_w + tab_width(tab_entries[entry_index]) + 4 end
  total_w = math.max(0, total_w - 4)
  local overflow = total_w > available_w
  local list_x = x
  local list_w = overflow and math.max(1, available_w - overflow_w - 4) or available_w
  local visible_entries = {}
  local hidden_entries = {}
  local used_w = 0
  for entry_index = 1, #tab_entries do
    local entry = tab_entries[entry_index]
    local width = tab_width(entry)
    local next_w = (#visible_entries == 0) and width or used_w + 4 + width
    if not overflow or next_w <= list_w then
      visible_entries[#visible_entries + 1] = entry
      used_w = next_w
    else
      hidden_entries[#hidden_entries + 1] = entry
    end
  end
  if overflow then
    tab_scroll_x = 0
  end
  r.ImGui_DrawList_PushClipRect(draw_list, list_x, y - 1, list_x + list_w, y + tab_h, true)
  local cursor = list_x
  local tabs_window_hovered = (not r.ImGui_IsWindowHovered) or r.ImGui_IsWindowHovered(ctx)
  for entry_index = 1, #visible_entries do
    local entry = visible_entries[entry_index]
    local width = tab_width(entry)
    local tab_x1 = cursor
    local tab_x2 = cursor + width
    if tab_x2 >= list_x and tab_x1 <= list_x + list_w then
      local active = selected_key == entry.key
      local mouse_x, mouse_y = r.ImGui_GetMousePos(ctx)
      local hovered = tabs_window_hovered and mouse_x >= tab_x1 and mouse_x <= tab_x2 and mouse_y >= y and mouse_y <= y + tab_h
      local bg = active and theme.tab_active or (hovered and theme.tab_hover or theme.tab_bg)
      local text_col = active and theme.text_active or theme.text_tab
      r.ImGui_DrawList_AddRectFilled(draw_list, tab_x1, y, tab_x2, y + tab_h - 1, bg, 5)
      r.ImGui_DrawList_AddRect(draw_list, tab_x1, y, tab_x2, y + tab_h - 1, active and theme.accent or theme.border, 5, 0, active and 1.4 or 0.8)
      r.ImGui_DrawList_AddText(draw_list, tab_x1 + 12, y + 6, text_col, entry_label(entry))
      if hovered and r.ImGui_IsMouseClicked and r.ImGui_IsMouseClicked(ctx, 0) then
        handle_tab_activation_click(entry)
      end
      if hovered and r.ImGui_IsMouseClicked and r.ImGui_IsMouseClicked(ctx, 1) then tab_context_key = entry.key; open_topbar_popup("FX Tab Context") end
      if hovered then r.ImGui_SetTooltip(ctx, entry.track_name .. "\n" .. entry.fx_name .. "\nCtrl-click: bypass  \195\151  Alt-click: offline") end
    end
    cursor = cursor + width + 4
  end
  r.ImGui_DrawList_PopClipRect(draw_list)
  draw_tab_context_popup()
  r.ImGui_Dummy(ctx, list_w, tab_h)
  if #hidden_entries > 0 then
    r.ImGui_SameLine(ctx, 0, 4)
    if current_item_rect_clicked(r.ImGui_Button(ctx, "v##tabs_overflow", overflow_w, tab_h)) then open_topbar_popup("FX Tabs Overflow") end
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "More tabs") end
    if r.ImGui_BeginPopup(ctx, "FX Tabs Overflow", topbar_popup_flags()) then
      topbar_popup_active = true
      for entry_index = 1, #hidden_entries do
        local entry = hidden_entries[entry_index]
        local selected = selected_key == entry.key
        if r.ImGui_Selectable(ctx, entry_label(entry) .. "##overflow_tab_" .. tostring(entry_index) .. "_" .. entry.key, selected) then
          handle_tab_activation_click(entry)
          r.ImGui_CloseCurrentPopup(ctx)
        end
        if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, entry.track_name .. "\n" .. entry.fx_name) end
      end
      r.ImGui_EndPopup(ctx)
    end
  end
  if #instruments == 0 then
    r.ImGui_TextColored(ctx, theme.text_dim, content_mode_instruments_only() and "No instrument FX found." or "No track FX found.")
  elseif #tab_entries == 0 then
    r.ImGui_TextColored(ctx, theme.text_dim, "No tabs in current filter.")
  end
end

local function update_plugin_rect_from_topbar()
  local window_left, window_top = r.ImGui_GetWindowPos(ctx)
  local _, window_height = r.ImGui_GetWindowSize(ctx)
  local _, viewport_top, _, viewport_height = main_viewport_rect()
  local overlap = clamp(settings.plugin_overlap_y, 0, 80)
  local viewport_bottom = viewport_top + viewport_height - 12
  local active_entry = find_entry_by_key(active_key)
  local size = entry_window_size(active_entry)
  local plugin_top = settings.vertical_flip and (window_top - size.height + overlap) or (window_top + window_height - overlap)
  if topbar_dragging or (not settings.center_fx_in_reaper_window and not settings.follow_fx_position) then
    host_rect.left = math.floor(window_left + topbar_left_overhang() + 0.5)
    host_rect.top = math.floor(plugin_top + 0.5)
  end
  host_rect.width = math.max(180, size.width)
  host_rect.height = math.max(140, math.min(size.height, viewport_bottom - plugin_top))
end

local function draw_blocked_state_window()
  local entry = find_entry_by_key(active_key)
  local state = entry_blocked_state(entry)
  if not state or host_rect.width < 120 or host_rect.height < 90 then return end
  local top_offset = clamp(settings.plugin_overlap_y, 0, 80)
  local state_top = settings.vertical_flip and host_rect.top or (host_rect.top + top_offset)
  local state_height = math.max(120, host_rect.height - top_offset)
  r.ImGui_SetNextWindowPos(ctx, host_rect.left, state_top, imgui_flag("ImGui_Cond_Always"))
  r.ImGui_SetNextWindowSize(ctx, host_rect.width, state_height, imgui_flag("ImGui_Cond_Always"))
  if r.ImGui_SetNextWindowBgAlpha then r.ImGui_SetNextWindowBgAlpha(ctx, 0.76) end
  local flags = 0
  flags = add_imgui_flag(flags, "ImGui_WindowFlags_NoTitleBar")
  flags = add_imgui_flag(flags, "ImGui_WindowFlags_NoResize")
  flags = add_imgui_flag(flags, "ImGui_WindowFlags_NoMove")
  flags = add_imgui_flag(flags, "ImGui_WindowFlags_NoScrollbar")
  flags = add_imgui_flag(flags, "ImGui_WindowFlags_NoScrollWithMouse")
  flags = add_imgui_flag(flags, "ImGui_WindowFlags_NoSavedSettings")
  flags = add_imgui_flag(flags, "ImGui_WindowFlags_TopMost")
  flags = add_imgui_flag(flags, "ImGui_WindowFlags_NoBackground")
  flags = add_imgui_flag(flags, "ImGui_WindowFlags_NoInputs")
  local visible = r.ImGui_Begin(ctx, BLOCKED_WINDOW_NAME, true, flags)
  if visible then
    local draw_list = r.ImGui_GetWindowDrawList(ctx)
    local x, y = r.ImGui_GetWindowPos(ctx)
    local w, h = r.ImGui_GetWindowSize(ctx)
    r.ImGui_DrawList_AddRectFilled(draw_list, x, y, x + w, y + h, blend(theme.window_bg, 0x000000B8, 0.18), 0)
    r.ImGui_DrawList_AddRect(draw_list, x, y, x + w, y + h, blend(theme.border, 0x000000AA, 0.25), 0, 0, 1.0)
    local pushed_status_font = false
    if status_font and r.ImGui_PushFont then
      r.ImGui_PushFont(ctx, status_font, 112)
      pushed_status_font = true
    elseif r.ImGui_SetWindowFontScale then
      r.ImGui_SetWindowFontScale(ctx, 7.8)
    end
    local text_w, text_h = 120, 24
    if r.ImGui_CalcTextSize then text_w, text_h = r.ImGui_CalcTextSize(ctx, state) end
    r.ImGui_SetCursorPos(ctx, math.max(0, (w - text_w) * 0.5), math.max(0, (h - text_h) * 0.5 - 42))
    r.ImGui_TextColored(ctx, state == "OFFLINE" and 0xE06C75FF or 0xE5C07BFF, state)
    if pushed_status_font and r.ImGui_PopFont then
      r.ImGui_PopFont(ctx)
    elseif r.ImGui_SetWindowFontScale then
      r.ImGui_SetWindowFontScale(ctx, 1.0)
    end
    local subtitle = entry.track_name .. " / " .. entry.fx_label
    local subtitle_w = 240
    if r.ImGui_CalcTextSize then subtitle_w = r.ImGui_CalcTextSize(ctx, subtitle) end
    r.ImGui_SetCursorPos(ctx, math.max(0, (w - subtitle_w) * 0.5), math.max(0, (h * 0.5) + 72))
    r.ImGui_TextColored(ctx, theme.text_dim, subtitle)
  end
  r.ImGui_End(ctx)
end

local function maintain_active_window()
  if active_key == "" then return end
  local active_entry = find_entry_by_key(active_key)
  if entry_blocked_state(active_entry) then sync_host_rect_to_entry_size(active_entry); close_pending_previous(); return end
  local now = r.time_precise()
  if topbar_mouse_captured or now - last_place_time >= 0.08 then
    if place_active_window() then close_pending_previous(); pending_place_until = 0 end
    last_place_time = now
  end
  if pending_close_key ~= "" and pending_close_deadline > 0 and now >= pending_close_deadline then
    close_pending_previous()
  end
end

local function handle_active_external_close()
  local entry = find_entry_by_key(active_key)
  local track = entry and resolve_entry_track(entry) or nil
  if entry and track then
    refresh_entry_state(entry, track)
    if entry_blocked_state(entry) then
      close_pending_previous()
      pending_activate_key = ""
      pending_activate_frames = 0
      sync_host_rect_to_entry_size(entry)
      pending_place_until = 0
      last_place_time = 0
      pending_pair_front_until = r.time_precise() + 0.45
      return
    end
  end
  close_pending_previous()
  pending_activate_key = ""
  pending_activate_frames = 0
  active_key = ""
  pending_place_until = 0
  pending_pair_front_until = 0
  topbar_restack_until = 0
end

local function capture_external_floating_window()
  if not settings.capture_external_floating or not r.TrackFX_GetFloatingWindow then return end
  local now = r.time_precise()
  if now - last_external_watch_time < 0.12 then return end
  last_external_watch_time = now
  local opened_entry = nil
  local active_closed = false
  local current_open_state = {}
  for entry_index = 1, #instruments do
    local entry = instruments[entry_index]
    local track = resolve_entry_track(entry)
    local hwnd = track and safe_trackfx_get_floating_window(track, entry.fx_index) or nil
    local is_open = hwnd ~= nil
    current_open_state[entry.key] = is_open
    if entry.key == active_key then
      if not is_open and external_open_state[entry.key] then active_closed = true end
    elseif is_open and not external_open_state[entry.key] then
      opened_entry = entry
    end
  end
  external_open_state = current_open_state
  if not opened_entry then
    if active_closed then handle_active_external_close() end
    return
  end
  local previous_key = active_key
  pending_activate_key = ""
  pending_activate_frames = 0
  selected_key = opened_entry.key
  active_key = opened_entry.key
  update_topbar_width_from_size(entry_window_size(opened_entry).width)
  pending_place_until = now + 1.25
  last_place_time = 0
  if settings.select_track_on_open and r.SetOnlyTrackSelected then
    local track = resolve_entry_track(opened_entry)
    if track then r.SetOnlyTrackSelected(track) end
  end
  if previous_key ~= "" and previous_key ~= opened_entry.key then
    pending_close_key = previous_key
    pending_close_deadline = now + 0.75
  end
end

local function cleanup()
  if cleanup_done then return end
  cleanup_done = true
  scan_instruments(true)
  close_all_instruments()
  if r.ImGui_DestroyContext and ctx then r.ImGui_DestroyContext(ctx) end
end

local function esc_requested_close()
  if not r.ImGui_IsKeyPressed or not r.ImGui_Key_Escape then return false end
  local key = r.ImGui_Key_Escape()
  local ok, pressed = pcall(r.ImGui_IsKeyPressed, ctx, key, false)
  if ok then return pressed == true end
  ok, pressed = pcall(r.ImGui_IsKeyPressed, ctx, key)
  if ok then return pressed == true end
  return false
end

local function loop()
  topbar_popup_active = false
  update_window_touch_pause()
  scan_instruments(force_scan)
  close_existing_instruments_on_start()
  open_startup_instrument()
  process_pending_activation()
  ensure_active_entry_visible()
  local active_entry = find_entry_by_key(active_key)
  if entry_blocked_state(active_entry) then sync_host_rect_to_entry_size(active_entry) end
  if settings.follow_fx_position and not topbar_dragging then follow_fx_window_update() end
  r.ImGui_SetNextWindowSize(ctx, topbar_window_width(topbar_width), topbar_height, imgui_flag("ImGui_Cond_Always"))
  local topbar_left, topbar_top = topbar_position_from_host_rect()
  if topbar_left and topbar_top and (settings.center_fx_in_reaper_window or settings.follow_fx_position) and not topbar_dragging then
    r.ImGui_SetNextWindowPos(ctx, topbar_left, topbar_top, imgui_flag("ImGui_Cond_Always"))
  else
    local centered_left, centered_top = centered_topbar_position()
    if centered_left and centered_top then r.ImGui_SetNextWindowPos(ctx, centered_left, centered_top, imgui_flag("ImGui_Cond_Always")) end
  end
  local window_flags = 0
  window_flags = add_imgui_flag(window_flags, "ImGui_WindowFlags_NoScrollbar")
  window_flags = add_imgui_flag(window_flags, "ImGui_WindowFlags_NoScrollWithMouse")
  window_flags = add_imgui_flag(window_flags, "ImGui_WindowFlags_NoTitleBar")
  window_flags = add_imgui_flag(window_flags, "ImGui_WindowFlags_NoResize")
  window_flags = add_imgui_flag(window_flags, "ImGui_WindowFlags_NoBackground")
  window_flags = add_imgui_flag(window_flags, "ImGui_WindowFlags_NoDocking")
  if settings.follow_fx_position and follow_pair_on_top then window_flags = add_imgui_flag(window_flags, "ImGui_WindowFlags_TopMost") end
  if r.ImGui_SetNextWindowDockID then r.ImGui_SetNextWindowDockID(ctx, 0, imgui_flag("ImGui_Cond_Always")) end
  local theme_stack = push_theme()
  draw_blocked_state_window()
  local visible, open = r.ImGui_Begin(ctx, SCRIPT_NAME, true, window_flags)
  if visible then
    sync_topbar_window_to_blocked_entry(active_entry)
    draw_topbar_background()
    draw_toolbar()
    if r.ImGui_SetCursorPosY then r.ImGui_SetCursorPosY(ctx, math.max(0, topbar_height - 31)) end
    draw_custom_tabs()
    if not r.JS_Window_SetPosition or not r.TrackFX_GetFloatingWindow then r.ImGui_TextColored(ctx, theme.text_dim, "js_ReaScriptAPI is not available") end
    update_topbar_focus_click()
    update_plugin_rect_from_topbar()
    if esc_requested_close() and not topbar_popup_active then close_requested = true end
  end
  r.ImGui_End(ctx)
  pop_theme(theme_stack)
  if close_requested then
    cleanup()
    return
  end
  set_topbar_owner()
  capture_external_floating_window()
  maintain_active_window()
  process_pending_pair_front()
  if open then
    r.defer(loop)
  else
    cleanup()
  end
end

if r.atexit then r.atexit(cleanup) end

loop()