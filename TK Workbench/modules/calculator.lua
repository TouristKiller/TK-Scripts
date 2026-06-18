local r = reaper
local Theme = require("core.theme")
local UI = require("core.ui")
local UIScale = require("core.ui_scale")

local M = {
  id = "calculator",
  title = "Calculator",
  icon = "CAL",
  version = "0.1.0"
}

local defaults = {
  active_tab = "delay",
  sync_bpm = true,
  manual_bpm = 120.0,
  delay_unit = "ms",
  decay_subtract_predelay = false,
  decay_predelay_index = 3,
  sync_samplerate = true,
  samplerate = 48000,
  a4_ref = 440.0,
  note_index = 9,
  note_octave = 4,
  freq_value = 440.0,
  db_value = 0.0,
  lin_value = 1.0,
  ms_value = 100.0,
  samples_value = 4800
}

local CHIP_H = 46

local tabs = {
  { id = "delay",   label = "Delay / Reverb" },
  { id = "gain",    label = "Gain (dB)" },
  { id = "note",    label = "Note / Freq" },
  { id = "samples", label = "Samples / Time" }
}

local note_rows = {
  { label = "1/1",  d = 1 },
  { label = "1/2",  d = 2 },
  { label = "1/4",  d = 4 },
  { label = "1/8",  d = 8 },
  { label = "1/16", d = 16 },
  { label = "1/32", d = 32 },
  { label = "1/64", d = 64 }
}

local modifiers = {
  { key = "straight", label = "Straight", mult = 1.0 },
  { key = "dotted",   label = "Dotted",   mult = 1.5 },
  { key = "triplet",  label = "Triplet",  mult = 2.0 / 3.0 }
}

local predelay_options = {
  { label = "1/64",  d = 64, mult = 1.0 },
  { label = "1/32T", d = 32, mult = 2.0 / 3.0 },
  { label = "1/32",  d = 32, mult = 1.0 },
  { label = "1/16",  d = 16, mult = 1.0 }
}

local decay_options = {
  { label = "1/4",    d = 4,   mult = 1.0 },
  { label = "1/2",    d = 2,   mult = 1.0 },
  { label = "1 bar",  d = 1,   mult = 1.0 },
  { label = "2 bars", d = 0.5, mult = 1.0 }
}

local note_names = { "C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B" }

local function clamp(value, lo, hi)
  value = tonumber(value) or lo
  if value < lo then return lo end
  if value > hi then return hi end
  return value
end

local function ensure_settings(app)
  app.settings.calculator = app.settings.calculator or {}
  local settings = app.settings.calculator
  local changed = false
  for key, value in pairs(defaults) do
    if settings[key] == nil then
      settings[key] = value
      changed = true
    end
  end
  settings.manual_bpm = clamp(settings.manual_bpm, 1, 999)
  settings.samplerate = clamp(settings.samplerate, 8000, 384000)
  settings.a4_ref = clamp(settings.a4_ref, 400, 480)
  settings.note_index = clamp(math.floor(settings.note_index or 0), 0, 11)
  settings.note_octave = clamp(math.floor(settings.note_octave or 0), -1, 9)
  settings.decay_predelay_index = clamp(math.floor(settings.decay_predelay_index or 1), 1, #predelay_options)
  if settings.delay_unit ~= "hz" then settings.delay_unit = "ms" end
  if changed and app.save_settings then app.save_settings() end
  return settings
end

local function save(app)
  if app.save_settings then app.save_settings() end
end

local function project_signature()
  if r.GetProjectTimeSignature2 then
    local ok, bpm, num, den = pcall(r.GetProjectTimeSignature2, 0)
    if ok then return tonumber(bpm) or 120, tonumber(num) or 4, tonumber(den) or 4 end
  end
  return r.Master_GetTempo and r.Master_GetTempo() or 120, 4, 4
end

local function current_bpm(settings)
  if settings.sync_bpm ~= false then
    local bpm = project_signature()
    return math.max(1, tonumber(bpm) or 120)
  end
  return math.max(1, tonumber(settings.manual_bpm) or 120)
end

local function detect_samplerate()
  if r.GetAudioDeviceInfo then
    local ok, value = r.GetAudioDeviceInfo("SRATE", "")
    if ok and tonumber(value) and tonumber(value) > 0 then return tonumber(value) end
  end
  if r.GetSetProjectInfo then
    local ok, value = pcall(r.GetSetProjectInfo, 0, "PROJECT_SRATE", 0, false)
    if ok and value and value > 0 then return value end
  end
  return 48000
end

local function current_samplerate(settings)
  if settings.sync_samplerate ~= false then return detect_samplerate() end
  return math.max(1, tonumber(settings.samplerate) or 48000)
end

local function note_ms(bpm, d, mult)
  local beat_ms = 60000.0 / math.max(1, bpm)
  return beat_ms * (4.0 / d) * mult
end

local function ms_to_hz(ms)
  if ms <= 0 then return 0 end
  return 1000.0 / ms
end

local function tab_label(id)
  for _, tab in ipairs(tabs) do
    if tab.id == id then return tab.label end
  end
  return tabs[1].label
end

local function text_w(ctx, value)
  if r.ImGui_CalcTextSize then
    local width = r.ImGui_CalcTextSize(ctx, tostring(value or ""))
    return tonumber(width) or 0
  end
  return #(tostring(value or "")) * UIScale.px(7)
end

local function copy_value(app, text, status)
  if r.ImGui_SetClipboardText then pcall(r.ImGui_SetClipboardText, app.ctx, tostring(text)) end
  app.status = status or ("Copied " .. tostring(text))
end

local function section_header(ctx, text)
  r.ImGui_Dummy(ctx, 1, UIScale.gap(2))
  r.ImGui_TextColored(ctx, Theme.colors.accent, text)
  r.ImGui_Separator(ctx)
  r.ImGui_Dummy(ctx, 1, UIScale.gap(1))
end

local function value_chip(ctx, app, id, opts)
  opts = opts or {}
  local width = opts.width or UIScale.round(96)
  local height = opts.height or UIScale.round(CHIP_H)
  local draw_list = r.ImGui_GetWindowDrawList(ctx)
  local x, y = r.ImGui_GetCursorScreenPos(ctx)
  r.ImGui_InvisibleButton(ctx, "##calc_chip_" .. id, width, height)
  local hovered = r.ImGui_IsItemHovered(ctx)
  local clicked = r.ImGui_IsItemClicked(ctx)
  local accent = opts.accent
  local bg = hovered and Theme.colors.frame_hover or Theme.colors.frame_bg
  local border = accent or Theme.colors.border
  r.ImGui_DrawList_AddRectFilled(draw_list, x, y, x + width, y + height, bg, UIScale.px(6))
  r.ImGui_DrawList_AddRect(draw_list, x, y, x + width, y + height, border, UIScale.px(6), 0, accent and UIScale.px(1.6) or UIScale.px(1))
  r.ImGui_DrawList_AddText(draw_list, x + UIScale.round(8), y + UIScale.round(6), accent or Theme.colors.text_dim, tostring(opts.label or ""))
  r.ImGui_DrawList_AddText(draw_list, x + UIScale.round(8), y + UIScale.round(22), Theme.colors.text, tostring(opts.value or ""))
  if opts.suffix then
    local suffix_w = text_w(ctx, opts.suffix)
    r.ImGui_DrawList_AddText(draw_list, x + width - suffix_w - UIScale.round(8), y + height - UIScale.round(18), Theme.colors.text_dim, opts.suffix)
  end
  if hovered and opts.tooltip then r.ImGui_SetTooltip(ctx, opts.tooltip) end
  if clicked and opts.copy ~= nil then copy_value(app, opts.copy, opts.copy_status) end
  return clicked
end

local function chip_grid(ctx, app, prefix, items, columns)
  if #items == 0 then return end
  columns = math.max(1, columns or 4)
  local avail = select(1, r.ImGui_GetContentRegionAvail(ctx))
  local gap = UIScale.gap(6)
  local height = UIScale.round(CHIP_H)
  local chip_w = math.max(UIScale.round(20), (avail - gap * (columns - 1)) / columns)
  local x0, y0 = r.ImGui_GetCursorScreenPos(ctx)
  for index, item in ipairs(items) do
    local column = (index - 1) % columns
    local row = math.floor((index - 1) / columns)
    r.ImGui_SetCursorScreenPos(ctx, x0 + column * (chip_w + gap), y0 + row * (height + gap))
    item.width = chip_w
    item.height = height
    value_chip(ctx, app, prefix .. "_" .. index, item)
  end
  local rows = math.ceil(#items / columns)
  r.ImGui_SetCursorScreenPos(ctx, x0, y0)
  r.ImGui_Dummy(ctx, avail, rows * height + (rows - 1) * gap)
end

local function draw_mini_badge(ctx, draw_list, right_x, y, height, label, value)
  local label_w = text_w(ctx, label)
  local value_w = text_w(ctx, value)
  local width = label_w + value_w + UIScale.round(22)
  local x = right_x - width
  r.ImGui_DrawList_AddRectFilled(draw_list, x, y, x + width, y + height, Theme.colors.frame_bg, UIScale.px(4))
  r.ImGui_DrawList_AddRect(draw_list, x, y, x + width, y + height, Theme.colors.border, UIScale.px(4), 0, UIScale.px(1))
  local text_y = y + (height - r.ImGui_GetTextLineHeight(ctx)) * 0.5
  r.ImGui_DrawList_AddText(draw_list, x + UIScale.round(8), text_y, Theme.colors.text_dim, label .. " ")
  r.ImGui_DrawList_AddText(draw_list, x + UIScale.round(8) + label_w + UIScale.round(4), text_y, Theme.colors.text, value)
  return x
end

local function draw_tempo_panel(ctx, app, settings)
  local avail = select(1, r.ImGui_GetContentRegionAvail(ctx))
  local draw_list = r.ImGui_GetWindowDrawList(ctx)
  local x, y = r.ImGui_GetCursorScreenPos(ctx)
  local height = UIScale.round(52)
  local pad = UIScale.round(10)
  r.ImGui_DrawList_AddRectFilled(draw_list, x, y, x + avail, y + height, Theme.colors.child_bg, UIScale.px(6))
  r.ImGui_DrawList_AddRect(draw_list, x, y, x + avail, y + height, Theme.colors.border, UIScale.px(6), 0, UIScale.px(1))
  r.ImGui_DrawList_AddText(draw_list, x + pad, y + UIScale.round(7), Theme.colors.text_dim, "TEMPO")
  local bpm = current_bpm(settings)
  r.ImGui_DrawList_AddText(draw_list, x + pad, y + UIScale.round(24), Theme.colors.accent, string.format("%.2f BPM", bpm))
  local _, num, den = project_signature()
  local badge_h = UIScale.round(20)
  local badge_y = y + (height - badge_h) * 0.5
  local right_x = x + avail - pad
  right_x = draw_mini_badge(ctx, draw_list, right_x, badge_y, badge_h, "SR", string.format("%d", math.floor(current_samplerate(settings) + 0.5)))
  right_x = right_x - UIScale.gap(6)
  draw_mini_badge(ctx, draw_list, right_x, badge_y, badge_h, "SIG", string.format("%d/%d", math.floor(num + 0.5), math.floor(den + 0.5)))
  r.ImGui_SetCursorScreenPos(ctx, x, y)
  r.ImGui_Dummy(ctx, avail, height)
  r.ImGui_Dummy(ctx, 1, UIScale.gap(2))

  local row_gap = UIScale.gap(6)
  local half_w = math.max(UIScale.round(20), (avail - row_gap) * 0.5)

  if r.ImGui_Button(ctx, (settings.sync_bpm ~= false and "BPM: Project" or "BPM: Manual") .. "##calc_bpm_sync", half_w) then
    settings.sync_bpm = not (settings.sync_bpm ~= false)
    save(app)
  end
  r.ImGui_SameLine(ctx, 0, row_gap)
  r.ImGui_SetNextItemWidth(ctx, half_w)
  if settings.sync_bpm == false then
    local changed, value = r.ImGui_InputDouble(ctx, "##calc_manual_bpm", settings.manual_bpm, 0, 0, "%.2f")
    if changed then settings.manual_bpm = clamp(value, 1, 999); save(app) end
  else
    r.ImGui_InputDouble(ctx, "##calc_manual_bpm", current_bpm(settings), 0, 0, "%.2f", r.ImGui_InputTextFlags_ReadOnly())
  end

  if r.ImGui_Button(ctx, (settings.sync_samplerate ~= false and "SR: Auto" or "SR: Manual") .. "##calc_sr_sync", half_w) then
    settings.sync_samplerate = not (settings.sync_samplerate ~= false)
    save(app)
  end
  r.ImGui_SameLine(ctx, 0, row_gap)
  r.ImGui_SetNextItemWidth(ctx, half_w)
  if settings.sync_samplerate == false then
    local changed, value = r.ImGui_InputDouble(ctx, "##calc_manual_sr", settings.samplerate, 0, 0, "%.0f")
    if changed then settings.samplerate = clamp(value, 8000, 384000); save(app) end
  else
    r.ImGui_InputDouble(ctx, "##calc_manual_sr", current_samplerate(settings), 0, 0, "%.0f", r.ImGui_InputTextFlags_ReadOnly())
  end
end

local function draw_tab_selector(ctx, app, settings)
  local avail = select(1, r.ImGui_GetContentRegionAvail(ctx))
  local gap = UIScale.gap(6)
  local count = #tabs
  local btn_w = math.max(UIScale.round(20), (avail - gap * (count - 1)) / count)
  local height = UIScale.button_h(ctx, 26)
  local draw_list = r.ImGui_GetWindowDrawList(ctx)
  local x0, y0 = r.ImGui_GetCursorScreenPos(ctx)
  for index, tab in ipairs(tabs) do
    local x = x0 + (index - 1) * (btn_w + gap)
    r.ImGui_SetCursorScreenPos(ctx, x, y0)
    r.ImGui_InvisibleButton(ctx, "##calc_tab_" .. tab.id, btn_w, height)
    local active = settings.active_tab == tab.id
    local hovered = r.ImGui_IsItemHovered(ctx)
    if r.ImGui_IsItemClicked(ctx) then
      settings.active_tab = tab.id
      app.status = "Calculator: " .. tab.label
      save(app)
    end
    local bg = active and Theme.colors.accent_soft or (hovered and Theme.colors.frame_hover or Theme.colors.frame_bg)
    local border = active and Theme.colors.accent or Theme.colors.border
    r.ImGui_DrawList_AddRectFilled(draw_list, x, y0, x + btn_w, y0 + height, bg, UIScale.px(5))
    r.ImGui_DrawList_AddRect(draw_list, x, y0, x + btn_w, y0 + height, border, UIScale.px(5), 0, active and UIScale.px(1.6) or UIScale.px(1))
    local text_color = Theme.text_for_background(bg, active and Theme.colors.text or Theme.colors.text_dim, nil, 3)
    local label = UIScale.short_label(ctx, tab.label, tab.label:match("^(%S+)") or tab.label, btn_w - UIScale.round(8))
    local label_w = text_w(ctx, label)
    r.ImGui_DrawList_AddText(draw_list, x + (btn_w - label_w) * 0.5, y0 + (height - r.ImGui_GetTextLineHeight(ctx)) * 0.5, text_color, label)
  end
  r.ImGui_SetCursorScreenPos(ctx, x0, y0)
  r.ImGui_Dummy(ctx, avail, height)
end

local function draw_unit_toggle(ctx, app, settings)
  local is_ms = settings.delay_unit ~= "hz"
  if r.ImGui_SmallButton(ctx, (is_ms and "Show: ms" or "Show: Hz") .. "##calc_delay_unit") then
    settings.delay_unit = is_ms and "hz" or "ms"
    save(app)
  end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Toggle the table between milliseconds and frequency") end
end

local function delay_cell_text(ms, unit)
  if unit == "hz" then return string.format("%.2f", ms_to_hz(ms)) end
  return string.format("%.2f", ms)
end

local function draw_delay_section(ctx, app, settings)
  local bpm = current_bpm(settings)
  section_header(ctx, "Note delay times")
  r.ImGui_AlignTextToFramePadding(ctx)
  r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Click a value to copy. Hover for ms / Hz details.")
  r.ImGui_SameLine(ctx)
  local avail = select(1, r.ImGui_GetContentRegionAvail(ctx))
  r.ImGui_SameLine(ctx, 0, math.max(UIScale.gap(6), avail - UIScale.text_button_w(ctx, "Show: ms", 70)))
  draw_unit_toggle(ctx, app, settings)

  local unit = settings.delay_unit
  local table_flags = 0
  if r.ImGui_TableFlags_Borders then table_flags = table_flags | r.ImGui_TableFlags_Borders() end
  if r.ImGui_TableFlags_RowBg then table_flags = table_flags | r.ImGui_TableFlags_RowBg() end
  if r.ImGui_TableFlags_SizingStretchSame then table_flags = table_flags | r.ImGui_TableFlags_SizingStretchSame() end
  if r.ImGui_BeginTable and r.ImGui_BeginTable(ctx, "##calc_delay_table", 4, table_flags) then
    if r.ImGui_TableSetupColumn then
      local fixed = r.ImGui_TableColumnFlags_WidthFixed and r.ImGui_TableColumnFlags_WidthFixed() or 0
      r.ImGui_TableSetupColumn(ctx, "Note", fixed, UIScale.round(54))
      r.ImGui_TableSetupColumn(ctx, "Straight")
      r.ImGui_TableSetupColumn(ctx, "Dotted")
      r.ImGui_TableSetupColumn(ctx, "Triplet")
      r.ImGui_TableHeadersRow(ctx)
    end
    for _, row in ipairs(note_rows) do
      r.ImGui_TableNextRow(ctx)
      r.ImGui_TableNextColumn(ctx)
      r.ImGui_AlignTextToFramePadding(ctx)
      r.ImGui_TextColored(ctx, Theme.colors.text_dim, row.label)
      for _, mod in ipairs(modifiers) do
        r.ImGui_TableNextColumn(ctx)
        local ms = note_ms(bpm, row.d, mod.mult)
        local cell = delay_cell_text(ms, unit)
        if r.ImGui_Selectable(ctx, cell .. "##calc_cell_" .. row.d .. "_" .. mod.key) then
          copy_value(app, delay_cell_text(ms, unit), row.label .. " " .. mod.label .. " copied (" .. cell .. " " .. (unit == "hz" and "Hz" or "ms") .. ")")
        end
        if r.ImGui_IsItemHovered(ctx) then
          r.ImGui_SetTooltip(ctx, string.format("%s %s\n%.2f ms  |  %.2f Hz", row.label, mod.label, ms, ms_to_hz(ms)))
        end
      end
    end
    r.ImGui_EndTable(ctx)
  end

  section_header(ctx, "Reverb pre-delay")
  local predelay_items = {}
  for _, opt in ipairs(predelay_options) do
    local ms = note_ms(bpm, opt.d, opt.mult)
    predelay_items[#predelay_items + 1] = {
      label = opt.label,
      value = string.format("%.1f", ms),
      suffix = "ms",
      accent = Theme.colors.warning,
      copy = string.format("%.2f", ms),
      copy_status = "Pre-delay " .. opt.label .. " copied (" .. string.format("%.2f", ms) .. " ms)",
      tooltip = string.format("Pre-delay %s\n%.2f ms  |  %.2f Hz", opt.label, ms, ms_to_hz(ms))
    }
  end
  chip_grid(ctx, app, "predelay", predelay_items, 4)

  section_header(ctx, "Reverb decay / RT60")
  local changed, value = r.ImGui_Checkbox(ctx, "Subtract pre-delay from decay##calc_decay_subtract_predelay", settings.decay_subtract_predelay == true)
  if changed then
    settings.decay_subtract_predelay = value
    save(app)
  end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "When enabled, selected pre-delay time is subtracted from each decay value") end
  if settings.decay_subtract_predelay == true then
    r.ImGui_SetNextItemWidth(ctx, UIScale.round(170))
    local selected = predelay_options[settings.decay_predelay_index] or predelay_options[1]
    local selected_ms = note_ms(bpm, selected.d, selected.mult)
    local preview = string.format("%s (%.1f ms)", selected.label, selected_ms)
    if r.ImGui_BeginCombo(ctx, "Pre-delay source##calc_decay_predelay_source", preview) then
      for index, opt in ipairs(predelay_options) do
        local ms = note_ms(bpm, opt.d, opt.mult)
        local label = string.format("%s (%.1f ms)", opt.label, ms)
        local is_selected = settings.decay_predelay_index == index
        if r.ImGui_Selectable(ctx, label, is_selected) then
          settings.decay_predelay_index = index
          save(app)
        end
        if is_selected then r.ImGui_SetItemDefaultFocus(ctx) end
      end
      r.ImGui_EndCombo(ctx)
    end
  end
  local decay_items = {}
  local subtract_ms = 0
  if settings.decay_subtract_predelay == true then
    local predelay = predelay_options[settings.decay_predelay_index] or predelay_options[1]
    subtract_ms = note_ms(bpm, predelay.d, predelay.mult)
  end
  for _, opt in ipairs(decay_options) do
    local raw_ms = note_ms(bpm, opt.d, opt.mult)
    local ms = math.max(0, raw_ms - subtract_ms)
    decay_items[#decay_items + 1] = {
      label = opt.label,
      value = string.format("%.0f", ms),
      suffix = "ms",
      accent = Theme.colors.accent,
      copy = string.format("%.2f", ms),
      copy_status = "Decay " .. opt.label .. " copied (" .. string.format("%.2f", ms) .. " ms)",
      tooltip = settings.decay_subtract_predelay == true
        and string.format("Decay %s\nBase %.2f ms - Pre-delay %.2f ms = %.2f ms  |  %.3f s", opt.label, raw_ms, subtract_ms, ms, ms / 1000.0)
        or string.format("Decay %s\n%.2f ms  |  %.3f s", opt.label, ms, ms / 1000.0)
    }
  end
  chip_grid(ctx, app, "decay", decay_items, 4)
end

local function db_to_linear(db)
  return 10.0 ^ (db / 20.0)
end

local function linear_to_db(lin)
  if lin <= 0 then return -150.0 end
  return 20.0 * (math.log(lin) / math.log(10))
end

local function draw_gain_section(ctx, app, settings)
  section_header(ctx, "dB to linear / percent")
  r.ImGui_SetNextItemWidth(ctx, UIScale.round(140))
  local changed, value = r.ImGui_InputDouble(ctx, "Gain (dB)##calc_db", settings.db_value, 1.0, 6.0, "%.2f")
  if changed then settings.db_value = clamp(value, -150, 24); save(app) end
  local lin = db_to_linear(settings.db_value)
  chip_grid(ctx, app, "gain_from_db", {
    {
      label = "Linear", value = string.format("%.4f", lin), copy = string.format("%.6f", lin),
      copy_status = "Linear amplitude copied", tooltip = string.format("%.2f dB = %.6f linear", settings.db_value, lin)
    },
    {
      label = "Percent", value = string.format("%.2f", lin * 100) .. "%", copy = string.format("%.2f", lin * 100),
      copy_status = "Percent copied", tooltip = string.format("%.2f dB = %.2f %%", settings.db_value, lin * 100)
    },
    {
      label = "Power %", value = string.format("%.2f", lin * lin * 100) .. "%", copy = string.format("%.2f", lin * lin * 100),
      copy_status = "Power percent copied", tooltip = string.format("Power ratio = %.4f", lin * lin)
    }
  }, 3)

  section_header(ctx, "Linear to dB")
  r.ImGui_SetNextItemWidth(ctx, UIScale.round(140))
  local lchanged, lvalue = r.ImGui_InputDouble(ctx, "Linear##calc_lin", settings.lin_value, 0.1, 0.5, "%.4f")
  if lchanged then settings.lin_value = clamp(lvalue, 0, 32); save(app) end
  local db = linear_to_db(settings.lin_value)
  chip_grid(ctx, app, "gain_from_lin", {
    {
      label = "dB", value = string.format("%.2f", db), suffix = "dB", copy = string.format("%.2f", db),
      copy_status = "dB copied", tooltip = string.format("%.4f linear = %.2f dB", settings.lin_value, db)
    },
    {
      label = "Percent", value = string.format("%.2f", settings.lin_value * 100) .. "%", copy = string.format("%.2f", settings.lin_value * 100),
      copy_status = "Percent copied", tooltip = "Linear value as percentage"
    }
  }, 3)

  section_header(ctx, "Pan law reference")
  local pan_items = {}
  for _, db_ref in ipairs({ -3.0, -4.5, -6.0 }) do
    local linear = db_to_linear(db_ref)
    pan_items[#pan_items + 1] = {
      label = string.format("%.1f dB", db_ref),
      value = string.format("%.4f", linear),
      accent = Theme.colors.accent_soft,
      copy = string.format("%.6f", linear),
      copy_status = string.format("%.1f dB center attenuation copied", db_ref),
      tooltip = string.format("%.1f dB center = %.4f linear (%.2f %%)", db_ref, linear, linear * 100)
    }
  end
  chip_grid(ctx, app, "pan_law", pan_items, 3)
end

local function midi_to_freq(midi, a4)
  return a4 * (2.0 ^ ((midi - 69) / 12.0))
end

local function midi_note_name(midi)
  midi = math.floor(midi + 0.5)
  local name = note_names[(midi % 12) + 1]
  local octave = math.floor(midi / 12) - 1
  return name .. tostring(octave)
end

local function draw_note_section(ctx, app, settings)
  section_header(ctx, "Reference pitch")
  r.ImGui_SetNextItemWidth(ctx, UIScale.round(120))
  local changed, value = r.ImGui_InputDouble(ctx, "A4 (Hz)##calc_a4", settings.a4_ref, 1.0, 5.0, "%.2f")
  if changed then settings.a4_ref = clamp(value, 400, 480); save(app) end

  section_header(ctx, "Note to frequency")
  r.ImGui_AlignTextToFramePadding(ctx)
  r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Note")
  r.ImGui_SameLine(ctx)
  r.ImGui_SetNextItemWidth(ctx, UIScale.round(70))
  if r.ImGui_BeginCombo(ctx, "##calc_note_name", note_names[settings.note_index + 1]) then
    for index, name in ipairs(note_names) do
      if r.ImGui_Selectable(ctx, name .. "##calc_note_opt_" .. index, settings.note_index == index - 1) then
        settings.note_index = index - 1
        save(app)
      end
    end
    r.ImGui_EndCombo(ctx)
  end
  r.ImGui_SameLine(ctx)
  r.ImGui_SetNextItemWidth(ctx, UIScale.round(110))
  local ochanged, ovalue = r.ImGui_InputInt(ctx, "Octave##calc_octave", settings.note_octave)
  if ochanged then settings.note_octave = clamp(ovalue, -1, 9); save(app) end
  local midi = (settings.note_octave + 1) * 12 + settings.note_index
  local freq = midi_to_freq(midi, settings.a4_ref)
  chip_grid(ctx, app, "note_to_freq", {
    {
      label = "Frequency", value = string.format("%.2f", freq), suffix = "Hz", copy = string.format("%.2f", freq),
      copy_status = midi_note_name(midi) .. " frequency copied", tooltip = string.format("%s = %.2f Hz", midi_note_name(midi), freq)
    },
    {
      label = "MIDI note", value = tostring(midi), copy = tostring(midi),
      copy_status = "MIDI note number copied", tooltip = midi_note_name(midi) .. " = MIDI " .. tostring(midi)
    }
  }, 3)

  section_header(ctx, "Frequency to note")
  r.ImGui_SetNextItemWidth(ctx, UIScale.round(140))
  local fchanged, fvalue = r.ImGui_InputDouble(ctx, "Frequency (Hz)##calc_freq", settings.freq_value, 1.0, 10.0, "%.2f")
  if fchanged then settings.freq_value = clamp(fvalue, 1, 20000); save(app) end
  local exact_midi = 69 + 12 * (math.log(settings.freq_value / settings.a4_ref) / math.log(2))
  local nearest = math.floor(exact_midi + 0.5)
  local cents = (exact_midi - nearest) * 100
  chip_grid(ctx, app, "freq_to_note", {
    {
      label = "Nearest note", value = midi_note_name(nearest), copy = midi_note_name(nearest),
      copy_status = "Nearest note copied", tooltip = string.format("%.2f Hz is closest to %s", settings.freq_value, midi_note_name(nearest))
    },
    {
      label = "Detune", value = string.format("%+.1f", cents), suffix = "cents", copy = string.format("%.1f", cents),
      copy_status = "Cents copied", tooltip = string.format("%+.1f cents from %s", cents, midi_note_name(nearest))
    },
    {
      label = "MIDI note", value = tostring(nearest), copy = tostring(nearest),
      copy_status = "MIDI note number copied", tooltip = "Nearest MIDI note number"
    }
  }, 3)
end

local function draw_samples_section(ctx, app, settings)
  local sr = current_samplerate(settings)
  section_header(ctx, "Milliseconds to samples")
  r.ImGui_SetNextItemWidth(ctx, UIScale.round(140))
  local changed, value = r.ImGui_InputDouble(ctx, "Time (ms)##calc_ms", settings.ms_value, 1.0, 10.0, "%.3f")
  if changed then settings.ms_value = clamp(value, 0, 600000); save(app) end
  local samples = settings.ms_value * sr / 1000.0
  chip_grid(ctx, app, "ms_to_samples", {
    {
      label = "Samples", value = string.format("%.1f", samples), copy = string.format("%.0f", samples + 0.5),
      copy_status = "Samples copied", tooltip = string.format("%.3f ms at %d Hz = %.2f samples", settings.ms_value, math.floor(sr + 0.5), samples)
    },
    {
      label = "Rounded", value = string.format("%d", math.floor(samples + 0.5)), copy = string.format("%d", math.floor(samples + 0.5)),
      copy_status = "Rounded samples copied", tooltip = "Rounded to nearest whole sample"
    }
  }, 3)

  section_header(ctx, "Samples to time")
  r.ImGui_SetNextItemWidth(ctx, UIScale.round(140))
  local schanged, svalue = r.ImGui_InputInt(ctx, "Samples##calc_samples", math.floor((settings.samples_value or 0) + 0.5))
  if schanged then settings.samples_value = clamp(svalue, 0, 100000000); save(app) end
  local sample_count = math.max(0, settings.samples_value)
  local ms = sample_count * 1000.0 / sr
  local hz = sample_count > 0 and (sr / sample_count) or 0
  chip_grid(ctx, app, "samples_to_time", {
    {
      label = "Time", value = string.format("%.3f", ms), suffix = "ms", copy = string.format("%.3f", ms),
      copy_status = "Time copied", tooltip = string.format("%d samples at %d Hz = %.3f ms", math.floor(sample_count + 0.5), math.floor(sr + 0.5), ms)
    },
    {
      label = "Frequency", value = string.format("%.2f", hz), suffix = "Hz", copy = string.format("%.2f", hz),
      copy_status = "Frequency copied", tooltip = string.format("Period of %d samples = %.2f Hz", math.floor(sample_count + 0.5), hz)
    }
  }, 3)

  section_header(ctx, "Note length in samples")
  local bpm = current_bpm(settings)
  local note_items = {}
  for _, row in ipairs({ note_rows[3], note_rows[4], note_rows[5], note_rows[6] }) do
    local note_samples = note_ms(bpm, row.d, 1.0) * sr / 1000.0
    note_items[#note_items + 1] = {
      label = row.label,
      value = string.format("%d", math.floor(note_samples + 0.5)),
      accent = Theme.colors.accent_soft,
      copy = string.format("%d", math.floor(note_samples + 0.5)),
      copy_status = row.label .. " length copied (" .. string.format("%d", math.floor(note_samples + 0.5)) .. " samples)",
      tooltip = string.format("%s at %.2f BPM = %.1f samples", row.label, bpm, note_samples)
    }
  end
  chip_grid(ctx, app, "note_samples", note_items, 4)
end

function M.draw(app)
  local ctx = app.ctx
  local settings = ensure_settings(app)
  local _, avail_h = r.ImGui_GetContentRegionAvail(ctx)
  local height = math.max(UIScale.round(120), (avail_h or UIScale.round(240)) - UI.info_line_height(ctx))
  if r.ImGui_BeginChild(ctx, "##calculator_surface", 0, height, 0) then
    draw_tempo_panel(ctx, app, settings)
    r.ImGui_Dummy(ctx, 1, UIScale.gap(4))
    draw_tab_selector(ctx, app, settings)
    r.ImGui_Dummy(ctx, 1, UIScale.gap(4))
    local tab = settings.active_tab
    if tab == "gain" then
      draw_gain_section(ctx, app, settings)
    elseif tab == "note" then
      draw_note_section(ctx, app, settings)
    elseif tab == "samples" then
      draw_samples_section(ctx, app, settings)
    else
      draw_delay_section(ctx, app, settings)
    end
    r.ImGui_EndChild(ctx)
  end
  UI.draw_info_line(ctx, "Calculator | " .. tab_label(settings.active_tab) .. " | BPM " .. string.format("%.2f", current_bpm(settings)))
end

return M
