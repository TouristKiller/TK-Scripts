local r = reaper
local M = {}

M.reaper_preset_name = "REAPER Theme"

M.reaper_preset_modes = {
  [M.reaper_preset_name] = "balanced",
  ["REAPER Theme - Panel"] = "panel",
  ["REAPER Theme - Color"] = "color"
}

M.preset_order = {
  M.reaper_preset_name,
  "REAPER Theme - Panel",
  "REAPER Theme - Color",
  "Graphite",
  "Light",
  "Blue",
  "Amber",
  "High Contrast"
}

M.presets = {
  Blue = {
    window_bg = 0x121417FF,
    child_bg = 0x181B20FF,
    popup_bg = 0x181B20FF,
    frame_bg = 0x222730FF,
    frame_hover = 0x2B3440FF,
    header = 0x253247FF,
    header_hover = 0x2E3E58FF,
    separator = 0x343A46FF,
    border = 0x343A46FF,
    text = 0xE8EDF2FF,
    text_dim = 0x8F9AA8FF,
    badge_text = 0x000000DD,
    accent = 0x7AA2F7FF,
    accent_soft = 0x2B4B78FF,
    warning = 0xE0AF68FF,
    danger = 0xF7768EFF
  },
  Graphite = {
    window_bg = 0x111111FF,
    child_bg = 0x181818FF,
    popup_bg = 0x1B1B1BFF,
    frame_bg = 0x242424FF,
    frame_hover = 0x333333FF,
    header = 0x2C2C2CFF,
    header_hover = 0x383838FF,
    separator = 0x3A3A3AFF,
    border = 0x444444FF,
    text = 0xF0F0F0FF,
    text_dim = 0xA0A0A0FF,
    badge_text = 0x000000DD,
    accent = 0xD8DEE9FF,
    accent_soft = 0x4C566AFF,
    warning = 0xEBCB8BFF,
    danger = 0xBF616AFF
  },
  Light = {
    window_bg = 0xEDE8DEFF,
    child_bg = 0xF7F3ECFF,
    popup_bg = 0xF4EFE7FF,
    frame_bg = 0xDED6CAFF,
    frame_hover = 0xD1C7B8FF,
    header = 0xD9E5EFFF,
    header_hover = 0xC7D9E8FF,
    separator = 0xC9BFB1FF,
    border = 0xB4AA9DFF,
    text = 0x252A2EFF,
    text_dim = 0x697078FF,
    badge_text = 0x000000DD,
    accent = 0x246AA8FF,
    accent_soft = 0xB8D3E8FF,
    warning = 0xB86E00FF,
    danger = 0xC4414BFF
  },
  Amber = {
    window_bg = 0x17130EFF,
    child_bg = 0x211A12FF,
    popup_bg = 0x261E14FF,
    frame_bg = 0x312719FF,
    frame_hover = 0x44351FFF,
    header = 0x3A2B17FF,
    header_hover = 0x4C381DFF,
    separator = 0x4E3A21FF,
    border = 0x5A4326FF,
    text = 0xF4E8D4FF,
    text_dim = 0xB89D78FF,
    badge_text = 0x000000DD,
    accent = 0xE6B450FF,
    accent_soft = 0x624719FF,
    warning = 0xFFCF70FF,
    danger = 0xE06C75FF
  },
  ["High Contrast"] = {
    window_bg = 0x050505FF,
    child_bg = 0x0E0E0EFF,
    popup_bg = 0x101010FF,
    frame_bg = 0x1A1A1AFF,
    frame_hover = 0x303030FF,
    header = 0x003A48FF,
    header_hover = 0x00566BFF,
    separator = 0x707070FF,
    border = 0x606060FF,
    text = 0xFFFFFFFF,
    text_dim = 0xC8C8C8FF,
    badge_text = 0x000000DD,
    accent = 0x00D4FFFF,
    accent_soft = 0x00566BFF,
    warning = 0xFFD166FF,
    danger = 0xFF4D6DFF
  }
}

M.current_preset = "Graphite"

local copy_colors

local function clamp(value, min_value, max_value)
  value = tonumber(value) or 0
  if value < min_value then return min_value end
  if value > max_value then return max_value end
  return value
end

local function rgba(red, green, blue, alpha)
  red = math.floor(clamp(red, 0, 255) + 0.5)
  green = math.floor(clamp(green, 0, 255) + 0.5)
  blue = math.floor(clamp(blue, 0, 255) + 0.5)
  alpha = math.floor(clamp(alpha or 255, 0, 255) + 0.5)
  return red * 0x1000000 + green * 0x10000 + blue * 0x100 + alpha
end

local function split_rgba(color)
  color = math.floor(tonumber(color) or 0)
  if color < 0 then color = color + 0x100000000 end
  local red = math.floor(color / 0x1000000) % 0x100
  local green = math.floor(color / 0x10000) % 0x100
  local blue = math.floor(color / 0x100) % 0x100
  local alpha = color % 0x100
  return red, green, blue, alpha
end

local function blend(first, second, amount)
  amount = clamp(amount, 0, 1)
  local ar, ag, ab, aa = split_rgba(first)
  local br, bg, bb, ba = split_rgba(second)
  return rgba(ar + (br - ar) * amount, ag + (bg - ag) * amount, ab + (bb - ab) * amount, aa + (ba - aa) * amount)
end

local function luminance(color)
  local red, green, blue = split_rgba(color)
  return (0.2126 * red + 0.7152 * green + 0.0722 * blue) / 255
end

local function readable_text(background)
  return luminance(background) > 0.5 and 0x20242AFF or 0xF2F4F7FF
end

local function channel_luminance(value)
  value = clamp(value / 255, 0, 1)
  if value <= 0.03928 then return value / 12.92 end
  return ((value + 0.055) / 1.055) ^ 2.4
end

local function contrast_luminance(color)
  local red, green, blue = split_rgba(color)
  return 0.2126 * channel_luminance(red) + 0.7152 * channel_luminance(green) + 0.0722 * channel_luminance(blue)
end

local function contrast_ratio(first, second)
  local first_luminance = contrast_luminance(first)
  local second_luminance = contrast_luminance(second)
  local high = math.max(first_luminance, second_luminance)
  local low = math.min(first_luminance, second_luminance)
  return (high + 0.05) / (low + 0.05)
end

local function min_contrast(color, backgrounds)
  local value
  for _, background in ipairs(backgrounds) do
    local ratio = contrast_ratio(color, background)
    value = value and math.min(value, ratio) or ratio
  end
  return value or 0
end

local function best_text_for_backgrounds(backgrounds)
  local dark_text = 0x20242AFF
  local light_text = 0xF2F4F7FF
  return min_contrast(dark_text, backgrounds) >= min_contrast(light_text, backgrounds) and dark_text or light_text
end

local function ensure_readable(color, backgrounds, fallback, min_ratio)
  min_ratio = min_ratio or 4.5
  if color and min_contrast(color, backgrounds) >= min_ratio then return color end
  if fallback and min_contrast(fallback, backgrounds) >= min_ratio then return fallback end
  return best_text_for_backgrounds(backgrounds)
end

local function theme_color(name, fallback)
  if not r.GetThemeColor or not r.ColorFromNative then return fallback end
  local ok_color, native = pcall(r.GetThemeColor, name, 0)
  if not ok_color or native == nil or native < 0 then return fallback end
  local ok_rgb, red, green, blue = pcall(r.ColorFromNative, native)
  if not ok_rgb then return fallback end
  return rgba(red or 0, green or 0, blue or 0, 255)
end

local function first_theme_color(names, fallback)
  for _, name in ipairs(names) do
    local color = theme_color(name, nil)
    if color then return color end
  end
  return fallback
end

local function color_distance(first, second)
  local ar, ag, ab = split_rgba(first)
  local br, bg, bb = split_rgba(second)
  return (math.abs(ar - br) + math.abs(ag - bg) + math.abs(ab - bb)) / 765
end

local function color_chroma(color)
  local red, green, blue = split_rgba(color)
  local high = math.max(red, green, blue)
  local low = math.min(red, green, blue)
  return (high - low) / 255
end

local function has_visual_weight(color, background, min_distance, min_chroma)
  if not color then return false end
  if color_distance(color, background) < (min_distance or 0.16) then return false end
  if color_chroma(color) < (min_chroma or 0) and color_distance(color, background) < 0.34 then return false end
  return true
end

local function first_weighted_theme_color(names, background, fallback, min_distance, min_chroma)
  for _, name in ipairs(names) do
    local color = theme_color(name, nil)
    if has_visual_weight(color, background, min_distance, min_chroma) then return color end
  end
  return has_visual_weight(fallback, background, min_distance, 0) and fallback or readable_text(background)
end

local function readable_theme_text(names, background, fallback)
  local color = first_theme_color(names, fallback)
  if math.abs(luminance(color) - luminance(background)) < 0.38 then return readable_text(background) end
  return color
end

local function keep_apart(color, background, other, fallback)
  if color_distance(color, other) < 0.12 then return fallback end
  if not has_visual_weight(color, background, 0.14, 0.04) then return fallback end
  return color
end

local function make_reaper_colors(mode)
  local fallback = M.presets.Graphite
  mode = mode or "balanced"
  local panel = mode == "panel"
  local color = mode == "color"
  local window_bg = first_theme_color(panel and { "col_main_bg", "docker_bg", "genlist_bg", "col_main_bg2", "col_arrangebg" } or { "col_main_bg", "col_main_bg2", "docker_bg", "col_arrangebg" }, fallback.window_bg)
  local child_bg = first_theme_color(panel and { "docker_bg", "genlist_bg", "col_main_bg2", "col_tracklistbg", "col_tr1_bg" } or { "col_main_bg2", "docker_bg", "col_tracklistbg", "genlist_bg", "col_tr1_bg" }, fallback.child_bg)
  local popup_bg = first_theme_color(panel and { "windowtab_bg", "docker_bg", "genlist_bg", "col_main_bg2" } or { "docker_bg", "windowtab_bg", "col_main_bg2", "genlist_bg" }, blend(child_bg, window_bg, 0.22))
  local frame_bg = first_theme_color(panel and { "genlist_bg", "col_main_editbk", "col_transport_editbk", "col_buttonbg" } or { "col_main_editbk", "col_transport_editbk", "genlist_bg", "col_buttonbg" }, blend(child_bg, readable_text(child_bg), 0.08))
  local text = readable_theme_text({ "col_main_text", "genlist_fg", "col_tcp_text", "col_mixer_text" }, window_bg, readable_text(window_bg))
  local text_dim = first_theme_color({ "col_main_text2", "genlist_seliafg", "col_tl_fg2", "col_toolbar_text" }, blend(text, window_bg, 0.42))
  local dark = luminance(window_bg) < 0.5
  local highlight = first_theme_color({ "col_main_3dhl", "tcp_list_scrollbar_mouseover", "mcp_list_scrollbar_mouseover" }, text)
  local shadow = first_theme_color({ "col_main_3dsh", "genlist_grid", "col_gridlines" }, fallback.separator)
  local selection_keys = panel and { "docker_selface", "genlist_selbg", "col_transport_editbk", "col_main_3dhl", "col_seltrack", "marker", "region" } or (color and { "marker", "region", "col_routingact", "col_vumid", "col_vuhot", "genlist_selbg", "docker_selface", "col_seltrack", "selcol_tr1_bg", "selcol_tr2_bg" } or { "genlist_selbg", "docker_selface", "col_seltrack", "selcol_tr1_bg", "selcol_tr2_bg", "col_transport_editbk", "marker", "region", "col_routingact", "col_vumid" })
  local selection = first_weighted_theme_color(selection_keys, window_bg, fallback.accent, color and 0.18 or 0.13, color and 0.08 or 0.04)
  local frame_hover = blend(frame_bg, highlight, dark and 0.18 or 0.12)
  local header = blend(frame_bg, selection, panel and 0.14 or (color and 0.36 or (dark and 0.28 or 0.2)))
  local header_hover = blend(frame_hover, selection, panel and 0.2 or (color and 0.44 or (dark and 0.34 or 0.26)))
  local accent = selection
  local warning = first_weighted_theme_color(color and { "region", "marker", "playrate_edited", "col_tl_bgsel", "col_tl_bgsel2" } or { "col_tl_bgsel", "col_tl_bgsel2", "playrate_edited", "marker", "region" }, window_bg, fallback.warning, 0.14, 0.05)
  local danger = first_weighted_theme_color({ "col_vuclip", "midi_noteon_flash", "midi_notemute_sel", "mute_overlay_col", "midi_selbg" }, window_bg, fallback.danger, 0.16, 0.06)
  warning = keep_apart(warning, window_bg, accent, fallback.warning)
  danger = keep_apart(danger, window_bg, accent, fallback.danger)
  danger = keep_apart(danger, window_bg, warning, fallback.danger)
  local text_backgrounds = { window_bg, child_bg, popup_bg, frame_bg, frame_hover, header, header_hover }
  text = ensure_readable(text, text_backgrounds, readable_text(window_bg), 4.5)
  text_dim = ensure_readable(text_dim, { window_bg, child_bg, popup_bg, frame_bg }, blend(text, window_bg, dark and 0.28 or 0.42), 3)
  return copy_colors({
    window_bg = window_bg,
    child_bg = child_bg,
    popup_bg = popup_bg,
    frame_bg = frame_bg,
    frame_hover = frame_hover,
    header = header,
    header_hover = header_hover,
    separator = shadow,
    border = blend(highlight, shadow, 0.5),
    text = text,
    text_dim = text_dim,
    badge_text = ensure_readable(luminance(accent) > 0.55 and 0x000000DD or 0xFFFFFFFF, { accent }, nil, 4.5),
    accent = accent,
    accent_soft = blend(accent, window_bg, panel and 0.82 or (color and 0.56 or (dark and 0.64 or 0.76))),
    warning = warning,
    danger = danger
  })
end

copy_colors = function(source)
  local target = {}
  for key, value in pairs(source) do target[key] = value end
  target.popup_bg = target.popup_bg or target.child_bg
  target.header = target.header or target.frame_hover
  target.header_hover = target.header_hover or target.accent_soft
  target.separator = target.separator or target.border
  target.badge_text = target.badge_text or 0x000000DD
  return target
end

M.colors = copy_colors(M.presets[M.current_preset])

function M.build_reaper_theme(name)
  return make_reaper_colors(M.reaper_preset_modes[name or M.reaper_preset_name] or "balanced")
end

function M.set_preset(name, custom_themes)
  local reaper_mode = M.reaper_preset_modes[name]
  if reaper_mode then
    M.current_preset = name
    M.colors = make_reaper_colors(reaper_mode)
    return M.current_preset
  end
  local preset = M.presets[name] or (custom_themes and custom_themes[name]) or M.presets.Graphite
  M.current_preset = (M.presets[name] or (custom_themes and custom_themes[name])) and name or "Graphite"
  M.colors = copy_colors(preset)
  return M.current_preset
end

function M.set_colors(colors, name)
  M.colors = copy_colors(colors)
  M.current_preset = name or "Unsaved Custom"
  return M.current_preset
end

function M.copy_current_colors()
  return copy_colors(M.colors)
end

function M.get_preset_names()
  return M.preset_order
end

function M.is_reserved_preset_name(name)
  name = tostring(name or ""):lower()
  for preset_name in pairs(M.reaper_preset_modes or {}) do
    if preset_name:lower() == name then return true end
  end
  for preset_name in pairs(M.presets or {}) do
    if preset_name:lower() == name then return true end
  end
  return false
end

function M.is_reaper_theme_preset(name)
  return M.reaper_preset_modes[name] ~= nil
end

function M.push(ctx)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_WindowBg(), M.colors.window_bg)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ChildBg(), M.colors.child_bg)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_PopupBg(), M.colors.popup_bg)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), M.colors.frame_bg)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgHovered(), M.colors.frame_hover)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Border(), M.colors.border)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Separator(), M.colors.separator)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), M.colors.text)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), M.colors.frame_bg)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), M.colors.frame_hover)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), M.colors.accent_soft)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Header(), M.colors.header)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderHovered(), M.colors.header_hover)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderActive(), M.colors.accent_soft)
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowRounding(), 6)
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ChildRounding(), 5)
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), 4)
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), 10, 10)
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing(), 8, 7)
  return { colors = 14, vars = 5 }
end

function M.pop(ctx, stack)
  if stack and stack.vars and stack.vars > 0 then r.ImGui_PopStyleVar(ctx, stack.vars) end
  if stack and stack.colors and stack.colors > 0 then r.ImGui_PopStyleColor(ctx, stack.colors) end
end

return M