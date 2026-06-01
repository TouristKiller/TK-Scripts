local r = reaper
local M = {}

M.reaper_preset_name = "REAPER Theme"

M.preset_order = {
  M.reaper_preset_name,
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

local function theme_color(name, fallback)
  if not r.GetThemeColor or not r.ColorFromNative then return fallback end
  local ok_color, native = pcall(r.GetThemeColor, name, 0)
  if not ok_color or native == nil or native < 0 then return fallback end
  local ok_rgb, red, green, blue = pcall(r.ColorFromNative, native)
  if not ok_rgb then return fallback end
  return rgba(red or 0, green or 0, blue or 0, 255)
end

local function make_reaper_colors()
  local fallback = M.presets.Graphite
  local arrange = theme_color("col_arrangebg", fallback.window_bg)
  local track_one = theme_color("col_tr1_bg", fallback.child_bg)
  local track_two = theme_color("col_tr2_bg", track_one)
  local selected_one = theme_color("selcol_tr1_bg", fallback.accent_soft)
  local selected_two = theme_color("selcol_tr2_bg", selected_one)
  local grid_one = theme_color("col_gridlines", fallback.separator)
  local grid_two = theme_color("col_gridlines2", grid_one)
  local divider_one = theme_color("col_tr1_divline", fallback.border)
  local divider_two = theme_color("col_tr2_divline", divider_one)
  local media_item = theme_color("col_mi_bg", selected_one)
  local text = readable_text(arrange)
  local dark = luminance(arrange) < 0.5
  local child_bg = blend(track_one, track_two, 0.5)
  local frame_bg = blend(child_bg, text, dark and 0.09 or 0.12)
  local frame_hover = blend(frame_bg, text, dark and 0.15 or 0.18)
  local accent = blend(selected_one, selected_two, 0.35)
  local accent_soft = blend(accent, arrange, dark and 0.62 or 0.74)
  return copy_colors({
    window_bg = arrange,
    child_bg = child_bg,
    popup_bg = blend(child_bg, arrange, 0.28),
    frame_bg = frame_bg,
    frame_hover = frame_hover,
    header = blend(frame_bg, accent, 0.18),
    header_hover = blend(frame_hover, accent, 0.26),
    separator = blend(grid_one, grid_two, 0.5),
    border = blend(divider_one, divider_two, 0.5),
    text = text,
    text_dim = blend(text, arrange, dark and 0.34 or 0.46),
    badge_text = luminance(accent) > 0.55 and 0x000000DD or 0xFFFFFFFF,
    accent = accent,
    accent_soft = accent_soft,
    warning = theme_color("col_tl_bgsel", fallback.warning),
    danger = blend(theme_color("midi_selbg", fallback.danger), media_item, 0.35)
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

function M.build_reaper_theme()
  return make_reaper_colors()
end

function M.set_preset(name, custom_themes)
  if name == M.reaper_preset_name then
    M.current_preset = M.reaper_preset_name
    M.colors = make_reaper_colors()
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
  if name == M.reaper_preset_name:lower() then return true end
  for preset_name in pairs(M.presets or {}) do
    if preset_name:lower() == name then return true end
  end
  return false
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