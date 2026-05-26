local r = reaper
local M = {}

M.preset_order = {
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

local function copy_colors(source)
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

function M.set_preset(name, custom_themes)
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