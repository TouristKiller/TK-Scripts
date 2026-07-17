local r = reaper

local M = {}

local THEMES = {
  {
    name = "Midnight",
    colors = {
      window_bg = 0x14171CFF, child_bg = 0x1A1E24FF, popup_bg = 0x1A1E24FF,
      frame_bg = 0x232A33FF, frame_hover = 0x2C3540FF, frame_active = 0x33404FFF,
      header = 0x232A33FF, header_hover = 0x2C3540FF, separator = 0x2E3641FF, border = 0x2E3641FF,
      text = 0xE7ECF2FF, text_dim = 0x8794A3FF, text_faint = 0x5C6675FF,
      accent = 0x6FA0F5FF, accent_hover = 0x86B2FBFF, accent_soft = 0x2A4470FF, accent_dim = 0x1E3050FF,
      success = 0x8BD17CFF, warning = 0xE6B450FF, danger = 0xF07178FF,
      card_bg = 0x1E232BFF, card_border = 0x2B333EFF,
    },
  },
  {
    name = "Graphite",
    colors = {
      window_bg = 0x17181AFF, child_bg = 0x1D1F22FF, popup_bg = 0x1D1F22FF,
      frame_bg = 0x26292EFF, frame_hover = 0x30343AFF, frame_active = 0x3A3F46FF,
      header = 0x26292EFF, header_hover = 0x30343AFF, separator = 0x33373DFF, border = 0x33373DFF,
      text = 0xEDEEF0FF, text_dim = 0x9AA0A6FF, text_faint = 0x646A70FF,
      accent = 0x4FD1C5FF, accent_hover = 0x6BE3D8FF, accent_soft = 0x1E4A47FF, accent_dim = 0x163533FF,
      success = 0x86D98EFF, warning = 0xE7C05EFF, danger = 0xEC7A80FF,
      card_bg = 0x212327FF, card_border = 0x31353BFF,
    },
  },
  {
    name = "Nord",
    colors = {
      window_bg = 0x2E3440FF, child_bg = 0x323947FF, popup_bg = 0x323947FF,
      frame_bg = 0x3B4252FF, frame_hover = 0x434C5EFF, frame_active = 0x4C566AFF,
      header = 0x3B4252FF, header_hover = 0x434C5EFF, separator = 0x4C566AFF, border = 0x434C5EFF,
      text = 0xECEFF4FF, text_dim = 0xA7B0C0FF, text_faint = 0x6E778AFF,
      accent = 0x88C0D0FF, accent_hover = 0x9FD0DEFF, accent_soft = 0x3B5364FF, accent_dim = 0x2C3E4BFF,
      success = 0xA3BE8CFF, warning = 0xEBCB8BFF, danger = 0xBF616AFF,
      card_bg = 0x353D4CFF, card_border = 0x4C566AFF,
    },
  },
  {
    name = "Rose Pine",
    colors = {
      window_bg = 0x232136FF, child_bg = 0x2A273FFF, popup_bg = 0x2A273FFF,
      frame_bg = 0x322F48FF, frame_hover = 0x393552FF, frame_active = 0x44415EFF,
      header = 0x322F48FF, header_hover = 0x393552FF, separator = 0x44415EFF, border = 0x393552FF,
      text = 0xE0DEF4FF, text_dim = 0x908CAAFF, text_faint = 0x6E6A86FF,
      accent = 0xC4A7E7FF, accent_hover = 0xD3BCEFFF, accent_soft = 0x423A5AFF, accent_dim = 0x322C46FF,
      success = 0x9CCFD8FF, warning = 0xF6C177FF, danger = 0xEB6F92FF,
      card_bg = 0x2E2B44FF, card_border = 0x44415EFF,
    },
  },
  {
    name = "Forest",
    colors = {
      window_bg = 0x121A15FF, child_bg = 0x18211BFF, popup_bg = 0x18211BFF,
      frame_bg = 0x1F2B23FF, frame_hover = 0x28362CFF, frame_active = 0x314235FF,
      header = 0x1F2B23FF, header_hover = 0x28362CFF, separator = 0x2E3D31FF, border = 0x2E3D31FF,
      text = 0xE6EFE7FF, text_dim = 0x8DA091FF, text_faint = 0x5F7264FF,
      accent = 0x6FD08CFF, accent_hover = 0x8ADDA1FF, accent_soft = 0x244A32FF, accent_dim = 0x193626FF,
      success = 0x8BD17CFF, warning = 0xE0BE6EFF, danger = 0xE87F79FF,
      card_bg = 0x1B241DFF, card_border = 0x2C3A2FFF,
    },
  },
  {
    name = "Amber",
    colors = {
      window_bg = 0x1A1613FF, child_bg = 0x211C17FF, popup_bg = 0x211C17FF,
      frame_bg = 0x2C251EFF, frame_hover = 0x372E25FF, frame_active = 0x42372CFF,
      header = 0x2C251EFF, header_hover = 0x372E25FF, separator = 0x3A3128FF, border = 0x3A3128FF,
      text = 0xF0E9E1FF, text_dim = 0xA89A8AFF, text_faint = 0x74685BFF,
      accent = 0xE8A44CFF, accent_hover = 0xF2B968FF, accent_soft = 0x4E3A20FF, accent_dim = 0x382916FF,
      success = 0xA9C97EFF, warning = 0xE8C24CFF, danger = 0xE8776BFF,
      card_bg = 0x241E18FF, card_border = 0x3A3128FF,
    },
  },
  {
    name = "Dark",
    colors = {
      window_bg = 0x0E0E0FFF, child_bg = 0x151517FF, popup_bg = 0x151517FF,
      frame_bg = 0x1C1C1FFF, frame_hover = 0x26262AFF, frame_active = 0x303035FF,
      header = 0x1C1C1FFF, header_hover = 0x26262AFF, separator = 0x2A2A2FFF, border = 0x2A2A2FFF,
      text = 0xEDEDEFFF, text_dim = 0x9496A0FF, text_faint = 0x5E606AFF,
      accent = 0x5A8DEFFF, accent_hover = 0x74A2F5FF, accent_soft = 0x24324FFF, accent_dim = 0x1A2438FF,
      success = 0x8BD17CFF, warning = 0xE6B450FF, danger = 0xF07178FF,
      card_bg = 0x161618FF, card_border = 0x28282DFF,
    },
  },
  {
    name = "Light",
    colors = {
      window_bg = 0xF2F3F5FF, child_bg = 0xE9EBEEFF, popup_bg = 0xFFFFFFFF,
      frame_bg = 0xFFFFFFFF, frame_hover = 0xE7EAEEFF, frame_active = 0xDBE0E6FF,
      header = 0xE4E7EBFF, header_hover = 0xD8DCE2FF, separator = 0xD0D4DAFF, border = 0xC9CED5FF,
      text = 0x1E2229FF, text_dim = 0x5A6270FF, text_faint = 0x99A0AAFF,
      accent = 0x2F6FE0FF, accent_hover = 0x1F5FD0FF, accent_soft = 0x2F6FE0FF, accent_dim = 0xD8E4FBFF,
      success = 0x2F9E52FF, warning = 0xC98A16FF, danger = 0xD64550FF,
      card_bg = 0xFFFFFFFF, card_border = 0xD8DCE2FF,
    },
  },
}

M.palettes = {}
M.theme_names = {}
for _, def in ipairs(THEMES) do
  M.palettes[def.name] = def.colors
  M.theme_names[#M.theme_names + 1] = def.name
end

M.current = M.theme_names[1]
M.colors = M.palettes[M.current]

local EXT_SECTION = "TK_Kit_Maker"
local EXT_KEY = "theme"

function M.set_theme(name)
  if M.palettes[name] then
    M.current = name
    M.colors = M.palettes[name]
    r.SetExtState(EXT_SECTION, EXT_KEY, name, true)
  end
end

local function load_saved()
  local saved = r.GetExtState(EXT_SECTION, EXT_KEY)
  if saved ~= "" and M.palettes[saved] then
    M.current = saved
    M.colors = M.palettes[saved]
  end
end

local fonts = { ctx = nil }

local function make_font(ctx, size)
  local ok, font = pcall(r.ImGui_CreateFont, "sans-serif", size)
  if not ok or not font then return nil end
  if r.ImGui_Attach then pcall(r.ImGui_Attach, ctx, font) end
  return font
end

local function ensure_fonts(ctx)
  if fonts.ctx == ctx and fonts.attempted then return end
  fonts.ctx = ctx
  fonts.attempted = true
  if not r.ImGui_CreateFont then return end
  fonts.body  = make_font(ctx, 14)
  fonts.h1    = make_font(ctx, 22)
  fonts.h2    = make_font(ctx, 16)
  fonts.small = make_font(ctx, 12)
end

function M.init(ctx)
  ensure_fonts(ctx)
  if not M._loaded then
    load_saved()
    M._loaded = true
  end
end

local function push_font(ctx, font, size)
  if font and r.ImGui_PushFont then
    local ok = pcall(r.ImGui_PushFont, ctx, font, size)
    if ok then return true end
  end
  return false
end

function M.push_h1(ctx) return push_font(ctx, fonts.h1, 22) end
function M.push_h2(ctx) return push_font(ctx, fonts.h2, 16) end
function M.push_small(ctx) return push_font(ctx, fonts.small, 12) end
function M.push_body(ctx) return push_font(ctx, fonts.body, 14) end
function M.pop_font(ctx, pushed)
  if pushed and r.ImGui_PopFont then pcall(r.ImGui_PopFont, ctx) end
end

function M.push(ctx)
  local c = M.colors
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_WindowBg(),        c.window_bg)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ChildBg(),         c.child_bg)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_PopupBg(),         c.popup_bg)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(),         c.frame_bg)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgHovered(),  c.frame_hover)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgActive(),   c.frame_active)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Border(),          c.border)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Separator(),       c.separator)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(),            c.text)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_TextDisabled(),    c.text_faint)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(),          c.frame_bg)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(),   c.frame_hover)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(),    c.accent_soft)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Header(),          c.header)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderHovered(),   c.header_hover)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderActive(),    c.accent_soft)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_CheckMark(),       c.accent)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrab(),      c.accent)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrabActive(),c.accent_hover)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_TableHeaderBg(),   c.frame_bg)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_TableBorderLight(),c.separator)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_TableBorderStrong(),c.separator)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_TableRowBgAlt(),   0xFFFFFF08)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_PlotHistogram(),   c.accent)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ScrollbarBg(),     0x00000000)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ScrollbarGrab(),   c.frame_hover)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ScrollbarGrabHovered(), c.accent_soft)

  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowRounding(), 8)
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ChildRounding(), 8)
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), 6)
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_PopupRounding(), 6)
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_GrabRounding(), 5)
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_TabRounding(), 6)
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ScrollbarRounding(), 6)
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ScrollbarSize(), 11)
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), 16, 14)
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FramePadding(), 9, 6)
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing(), 9, 8)
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ItemInnerSpacing(), 7, 6)
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_CellPadding(), 8, 5)
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameBorderSize(), 1)

  return { colors = 27, vars = 14 }
end

function M.pop(ctx, stack)
  if stack and stack.vars and stack.vars > 0 then r.ImGui_PopStyleVar(ctx, stack.vars) end
  if stack and stack.colors and stack.colors > 0 then r.ImGui_PopStyleColor(ctx, stack.colors) end
end

function M.section(ctx, title)
  local pushed = M.push_h2(ctx)
  r.ImGui_TextColored(ctx, M.colors.text, title)
  M.pop_font(ctx, pushed)
end

function M.help(ctx, text)
  local pushed = M.push_small(ctx)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), M.colors.text_dim)
  r.ImGui_TextWrapped(ctx, text)
  r.ImGui_PopStyleColor(ctx)
  M.pop_font(ctx, pushed)
end

function M.label(ctx, text)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), M.colors.text_dim)
  r.ImGui_Text(ctx, text)
  r.ImGui_PopStyleColor(ctx)
end

function M.primary_button(ctx, label, w, h)
  local c = M.colors
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), c.accent_soft)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), c.accent)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), c.accent_hover)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0xFFFFFFFF)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Border(), c.accent)
  local clicked = r.ImGui_Button(ctx, label, w or 0, h or 0)
  r.ImGui_PopStyleColor(ctx, 5)
  return clicked
end

function M.ghost_button(ctx, label, w, h)
  local c = M.colors
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x00000000)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), c.frame_hover)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), c.accent_soft)
  local clicked = r.ImGui_Button(ctx, label, w or 0, h or 0)
  r.ImGui_PopStyleColor(ctx, 3)
  return clicked
end

function M.theme_combo(ctx, width)
  r.ImGui_SetNextItemWidth(ctx, width or 150)
  if r.ImGui_BeginCombo(ctx, "##tk_theme_select", M.current) then
    for _, name in ipairs(M.theme_names) do
      if r.ImGui_Selectable(ctx, name, name == M.current) then
        M.set_theme(name)
      end
    end
    r.ImGui_EndCombo(ctx)
  end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Theme") end
end

return M
