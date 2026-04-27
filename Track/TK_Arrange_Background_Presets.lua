-- @description TK_Arrange_Background_Presets
-- @author TouristKiller
-- @version 1.3.0
-- @changelog
--[[   + Initial version. ]]--

----------------------------------------------------------------------------------------------------------
local r = reaper

if not r.ImGui_CreateContext then
  r.ShowMessageBox('ReaImGui is required for TK_Arrange_Background_Presets.', 'Missing dependency', 0)
  return
end

local script_path = debug.getinfo(1, 'S').source:match('^@?(.*[\\/])') or ''
local json = dofile(script_path .. 'json.lua')
local preset_file = script_path .. 'TK_Arrange_Background_Presets.json'
local ctx = r.ImGui_CreateContext('TK Arrange BG Presets')

local WINDOW_TITLE = 'TK Arrange BG Presets'
local WINDOW_DEFAULTS = {x = 140, y = 140, w = 700, h = 700}

local BACKGROUND_FIELDS = {
  {key = 'col_arrangebg', label = 'Arrange background'},
  {key = 'col_tr1_bg', label = 'Track background 1'},
  {key = 'col_tr2_bg', label = 'Track background 2'},
  {key = 'selcol_tr1_bg', label = 'Selected track 1'},
  {key = 'selcol_tr2_bg', label = 'Selected track 2'}
}

local GRID_FIELDS = {
  {key = 'col_gridlines', label = 'Grid line 1'},
  {key = 'col_gridlines2', label = 'Grid line 2'},
  {key = 'col_gridlines3', label = 'Grid line 3'}
}

local DIVIDER_FIELDS = {
  {key = 'col_tr1_divline', label = 'Track divider line 1'},
  {key = 'col_tr2_divline', label = 'Track divider line 2'}
}

local function get_all_color_fields()
  local fields = {}
  for _, field in ipairs(BACKGROUND_FIELDS) do
    fields[#fields + 1] = field
  end
  for _, field in ipairs(GRID_FIELDS) do
    fields[#fields + 1] = field
  end
  for _, field in ipairs(DIVIDER_FIELDS) do
    fields[#fields + 1] = field
  end
  return fields
end

local function color_to_hex(native)
  if not native or native < 0 then return '#000000' end
  local rr, gg, bb = r.ColorFromNative(native)
  return string.format('#%02X%02X%02X', rr or 0, gg or 0, bb or 0)
end

local function hex_to_native(hex)
  local clean = (hex or ''):gsub('%s+', ''):upper()
  if clean:sub(1, 1) == '#' then clean = clean:sub(2) end
  if not clean:match('^[0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F]$') then
    return nil
  end
  local rr = tonumber(clean:sub(1, 2), 16)
  local gg = tonumber(clean:sub(3, 4), 16)
  local bb = tonumber(clean:sub(5, 6), 16)
  return r.ColorToNative(rr, gg, bb)
end

local function hex_to_imgui_color(hex)
  local clean = (hex or ''):gsub('%s+', ''):upper():gsub('#', '')
  if not clean:match('^[0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F]$') then
    clean = '000000'
  end
  return tonumber(clean .. 'FF', 16) or 0x000000FF
end

local function imgui_color_to_hex(value)
  local color = math.floor(tonumber(value) or 0)
  local rr = math.floor(color / 0x1000000) % 0x100
  local gg = math.floor(color / 0x10000) % 0x100
  local bb = math.floor(color / 0x100) % 0x100
  return string.format('#%02X%02X%02X', rr, gg, bb)
end

local function get_current_colors()
  local colors = {}
  for _, field in ipairs(get_all_color_fields()) do
    colors[field.key] = color_to_hex(r.GetThemeColor(field.key, 0))
  end
  return colors
end

local function default_data()
  return {
    selected = 1,
    toggle_a = 1,
    toggle_b = 2,
    last_toggle = 2,
    window = {
      x = WINDOW_DEFAULTS.x,
      y = WINDOW_DEFAULTS.y,
      w = WINDOW_DEFAULTS.w,
      h = WINDOW_DEFAULTS.h
    },
    presets = {
      {
        name = 'Light',
        apply_tracks = true,
        apply_grid = true,
        colors = {
          col_arrangebg = '#DCDCDC',
          col_tr1_bg = '#D2D2D2',
          col_tr2_bg = '#C8C8C8',
          col_tr1_divline = '#B4B4B4',
          col_tr2_divline = '#B4B4B4',
          selcol_tr1_bg = '#BEBEBE',
          selcol_tr2_bg = '#B4B4B4',
          col_gridlines = '#AAAAAA',
          col_gridlines2 = '#888888',
          col_gridlines3 = '#666666'
        }
      },
      {
        name = 'Dark',
        apply_tracks = true,
        apply_grid = true,
        colors = {
          col_arrangebg = '#2E2E2E',
          col_tr1_bg = '#353535',
          col_tr2_bg = '#2A2A2A',
          col_tr1_divline = '#3D3D3D',
          col_tr2_divline = '#3D3D3D',
          selcol_tr1_bg = '#3E3E3E',
          selcol_tr2_bg = '#454545',
          col_gridlines = '#4A4A4A',
          col_gridlines2 = '#6E6E6E',
          col_gridlines3 = '#909090'
        }
      },
      {
        name = 'Arrange only',
        apply_tracks = false,
        apply_grid = false,
        colors = {
          col_arrangebg = '#3A3A3A',
          col_tr1_bg = '#353535',
          col_tr2_bg = '#2A2A2A',
          col_tr1_divline = '#3D3D3D',
          col_tr2_divline = '#3D3D3D',
          selcol_tr1_bg = '#3E3E3E',
          selcol_tr2_bg = '#454545',
          col_gridlines = '#4A4A4A',
          col_gridlines2 = '#6E6E6E',
          col_gridlines3 = '#909090'
        }
      }
    }
  }
end

local function ensure_preset(data, index)
  if not data.presets[index] then
    data.presets[index] = {
      name = 'Preset ' .. index,
      apply_tracks = true,
      apply_grid = true,
      colors = get_current_colors()
    }
  end
  if type(data.presets[index].colors) ~= 'table' then
    data.presets[index].colors = get_current_colors()
  end
  if data.presets[index].apply_tracks == nil then
    data.presets[index].apply_tracks = true
  end
  if data.presets[index].apply_grid == nil then
    data.presets[index].apply_grid = true
  end
  if not data.presets[index].name or data.presets[index].name == '' then
    data.presets[index].name = 'Preset ' .. index
  end
  local current_colors = get_current_colors()
  for _, field in ipairs(get_all_color_fields()) do
    if not data.presets[index].colors[field.key] then
      data.presets[index].colors[field.key] = current_colors[field.key] or '#000000'
    elseif not hex_to_native(data.presets[index].colors[field.key]) then
      data.presets[index].colors[field.key] = current_colors[field.key] or '#000000'
    end
  end
end

local function normalize_data(data)
  data = type(data) == 'table' and data or default_data()
  data.presets = type(data.presets) == 'table' and data.presets or {}
  if #data.presets == 0 then
    data.presets = default_data().presets
  end
  for i = 1, #data.presets do
    ensure_preset(data, i)
  end
  data.selected = math.max(1, math.min(tonumber(data.selected) or 1, #data.presets))
  data.toggle_a = math.max(1, math.min(tonumber(data.toggle_a) or 1, #data.presets))
  data.toggle_b = math.max(1, math.min(tonumber(data.toggle_b) or math.min(2, #data.presets), #data.presets))
  data.last_toggle = math.max(1, math.min(tonumber(data.last_toggle) or data.toggle_b, #data.presets))
  data.window = type(data.window) == 'table' and data.window or {}
  data.window.x = tonumber(data.window.x) or WINDOW_DEFAULTS.x
  data.window.y = tonumber(data.window.y) or WINDOW_DEFAULTS.y
  data.window.w = WINDOW_DEFAULTS.w
  data.window.h = WINDOW_DEFAULTS.h
  return data
end

local function load_data()
  local file = io.open(preset_file, 'r')
  if not file then return normalize_data(default_data()) end
  local content = file:read('*a')
  file:close()
  if not content or content == '' then return normalize_data(default_data()) end
  local ok, parsed = pcall(json.decode, content)
  if not ok or type(parsed) ~= 'table' then return normalize_data(default_data()) end
  return normalize_data(parsed)
end

local function save_data(data)
  local file = io.open(preset_file, 'w')
  if not file then return false end
  file:write(json.encode(normalize_data(data)))
  file:close()
  return true
end

local function apply_preset(preset)
  if not preset or type(preset.colors) ~= 'table' then return false end
  local arrange_native = hex_to_native(preset.colors.col_arrangebg)
  if not arrange_native then return false end
  local divider_natives = {}
  r.SetThemeColor('col_arrangebg', arrange_native, 0)
  if preset.apply_tracks then
    for i = 2, #BACKGROUND_FIELDS do
      local key = BACKGROUND_FIELDS[i].key
      local native = hex_to_native(preset.colors[key])
      if native then
        r.SetThemeColor(key, native, 0)
      end
    end
    for _, field in ipairs(DIVIDER_FIELDS) do
      local native = hex_to_native(preset.colors[field.key])
      if native then
        divider_natives[#divider_natives + 1] = {key = field.key, native = native}
      end
    end
  end
  if preset.apply_grid then
    for _, field in ipairs(GRID_FIELDS) do
      local native = hex_to_native(preset.colors[field.key])
      if native then
        r.SetThemeColor(field.key, native, 0)
      end
    end
  end
  r.TrackList_AdjustWindows(false)
  r.UpdateTimeline()
  r.UpdateArrange()
  if preset.apply_tracks and #divider_natives > 0 then
    for _, entry in ipairs(divider_natives) do
      r.SetThemeColor(entry.key, entry.native, 0)
    end
    r.ThemeLayout_RefreshAll()
    r.TrackList_AdjustWindows(false)
    r.UpdateTimeline()
    r.UpdateArrange()
  end
  return true
end

local function reset_theme_colors()
  for _, field in ipairs(get_all_color_fields()) do
    r.SetThemeColor(field.key, -1, 0)
  end
  r.UpdateArrange()
end

local function run_action(label, fn)
  r.Undo_BeginBlock()
  r.PreventUIRefresh(1)
  local ok, result = pcall(fn)
  r.PreventUIRefresh(-1)
  r.Undo_EndBlock(label, -1)
  return ok, result
end

local state = {
  data = load_data(),
  message = '',
  message_color = 0x9AD27AFF,
  selected = 1,
  editor = {
    name = '',
    apply_tracks = true,
    apply_grid = true,
    colors = {}
  },
  window_applied = false,
  should_close = false
}

local function set_message(text, color)
  state.message = text or ''
  state.message_color = color or 0x9AD27AFF
end

local function sync_editor_from_selected()
  local index = math.max(1, math.min(state.selected or 1, #state.data.presets))
  state.selected = index
  state.data.selected = index
  ensure_preset(state.data, index)
  local preset = state.data.presets[index]
  state.editor.name = preset.name or ('Preset ' .. index)
  state.editor.apply_tracks = preset.apply_tracks ~= false
  state.editor.apply_grid = preset.apply_grid ~= false
  state.editor.colors = {}
  for _, field in ipairs(get_all_color_fields()) do
    state.editor.colors[field.key] = preset.colors[field.key] or '#000000'
  end
end

local function commit_editor_to_selected()
  local index = state.selected
  ensure_preset(state.data, index)
  local preset = state.data.presets[index]
  for _, field in ipairs(get_all_color_fields()) do
    local value = state.editor.colors[field.key] or ''
    if not hex_to_native(value) then
      return false, 'Invalid color for ' .. field.label .. '. Use #RRGGBB.'
    end
  end
  preset.name = state.editor.name ~= '' and state.editor.name or ('Preset ' .. index)
  preset.apply_tracks = state.editor.apply_tracks ~= false
  preset.apply_grid = state.editor.apply_grid ~= false
  for _, field in ipairs(get_all_color_fields()) do
    preset.colors[field.key] = (state.editor.colors[field.key] or '#000000'):upper()
  end
  state.data.selected = index
  return true
end

local function save_current_to_selected()
  ensure_preset(state.data, state.selected)
  state.data.presets[state.selected].colors = get_current_colors()
  state.data.selected = state.selected
  sync_editor_from_selected()
  save_data(state.data)
  set_message('Current theme colors saved to preset ' .. state.selected .. '.', 0x9AD27AFF)
end

local function apply_selected_preset()
  local ok, err = commit_editor_to_selected()
  if not ok then
    set_message(err, 0xE07A7AFF)
    return
  end
  local preset = state.data.presets[state.selected]
  local applied, result = run_action('TK Arrange Background Presets - Apply', function()
    return apply_preset(preset)
  end)
  if not applied or not result then
    set_message('Preset could not be applied.', 0xE07A7AFF)
    return
  end
  state.data.selected = state.selected
  save_data(state.data)
  set_message('', 0x9AD27AFF)
end

local function toggle_a_b()
  local a = tonumber(state.data.toggle_a) or 1
  local b = tonumber(state.data.toggle_b) or 2
  if not state.data.presets[a] or not state.data.presets[b] then
    set_message('Toggle presets are not valid.', 0xE07A7AFF)
    return
  end
  local target = (tonumber(state.data.last_toggle) == a) and b or a
  local ok, result = run_action('TK Arrange Background Presets - Toggle', function()
    return apply_preset(state.data.presets[target])
  end)
  if not ok or not result then
    set_message('Toggle apply failed.', 0xE07A7AFF)
    return
  end
  state.data.last_toggle = target
  state.data.selected = target
  state.selected = target
  save_data(state.data)
  sync_editor_from_selected()
  set_message('Preset ' .. target .. ' is now active via toggle.', 0x9AD27AFF)
end

local function set_toggle_slot(slot)
  if slot == 'a' then
    state.data.toggle_a = state.selected
    set_message('Preset ' .. state.selected .. ' set as toggle A.', 0x9AD27AFF)
  else
    state.data.toggle_b = state.selected
    set_message('Preset ' .. state.selected .. ' set as toggle B.', 0x9AD27AFF)
  end
  save_data(state.data)
end

local function add_preset()
  local index = #state.data.presets + 1
  state.data.presets[index] = {
    name = 'Preset ' .. index,
    apply_tracks = true,
    colors = get_current_colors()
  }
  state.selected = index
  state.data.selected = index
  sync_editor_from_selected()
  save_data(state.data)
  set_message('New preset added.', 0x9AD27AFF)
end

local function delete_selected_preset()
  if #state.data.presets <= 1 then
    set_message('At least one preset must remain.', 0xE07A7AFF)
    return
  end
  table.remove(state.data.presets, state.selected)
  state.selected = math.max(1, math.min(state.selected, #state.data.presets))
  state.data.selected = state.selected
  state.data.toggle_a = math.max(1, math.min(state.data.toggle_a, #state.data.presets))
  state.data.toggle_b = math.max(1, math.min(state.data.toggle_b, #state.data.presets))
  state.data.last_toggle = math.max(1, math.min(state.data.last_toggle, #state.data.presets))
  sync_editor_from_selected()
  save_data(state.data)
  set_message('Preset deleted.', 0x9AD27AFF)
end

local function save_editor_changes()
  local ok, err = commit_editor_to_selected()
  if not ok then
    set_message(err, 0xE07A7AFF)
    return
  end
  save_data(state.data)
  set_message('Preset saved.', 0x9AD27AFF)
end

local function draw_color_row(field)
  local value = state.editor.colors[field.key] or '#000000'
  local valid = hex_to_native(value) ~= nil
  r.ImGui_Text(ctx, field.label)
  r.ImGui_SameLine(ctx, 190)
  r.ImGui_SetNextItemWidth(ctx, 90)
  local changed_picker, picker_value = r.ImGui_ColorEdit4(ctx, '##picker_' .. field.key, hex_to_imgui_color(value), r.ImGui_ColorEditFlags_NoInputs() | r.ImGui_ColorEditFlags_NoLabel())
  if changed_picker then
    state.editor.colors[field.key] = imgui_color_to_hex(picker_value)
    value = state.editor.colors[field.key]
    valid = true
  end
  r.ImGui_SameLine(ctx)
  r.ImGui_SetNextItemWidth(ctx, 140)
  local changed_text, text_value = r.ImGui_InputText(ctx, '##text_' .. field.key, value)
  if changed_text then
    state.editor.colors[field.key] = text_value:upper()
    value = state.editor.colors[field.key]
    valid = hex_to_native(value) ~= nil
  end
  r.ImGui_SameLine(ctx)
  r.ImGui_TextColored(ctx, valid and 0x9AD27AFF or 0xE07A7AFF, valid and 'OK' or 'Invalid')
end

local function draw_left_panel(height)
  if r.ImGui_BeginChild(ctx, '##preset_list', 220, height, 1, 0) then
    r.ImGui_Text(ctx, 'Presets')
    r.ImGui_Separator(ctx)
    for i, preset in ipairs(state.data.presets) do
      local name = preset.name and preset.name ~= '' and preset.name or ('Preset ' .. i)
      if i == state.data.toggle_a then name = name .. ' [A]' end
      if i == state.data.toggle_b then name = name .. ' [B]' end
      if r.ImGui_Selectable(ctx, i .. '. ' .. name, state.selected == i) then
        state.selected = i
        sync_editor_from_selected()
      end
    end
    r.ImGui_Dummy(ctx, 0, 8)
    if r.ImGui_Button(ctx, 'New preset', -1, 28) then
      add_preset()
    end
    if r.ImGui_Button(ctx, 'Delete preset', -1, 28) then
      delete_selected_preset()
    end
  end
  r.ImGui_EndChild(ctx)
end

local function draw_right_panel(height)
  if r.ImGui_BeginChild(ctx, '##editor', 0, height, 1, 0) then
    local preset = state.data.presets[state.selected]
    local active_name = preset and (preset.name or ('Preset ' .. state.selected)) or '-'
    local avail_w = r.ImGui_GetContentRegionAvail(ctx)
    local gap = 8
    local row2_w = math.max(100, math.floor((avail_w - gap) / 2))
    local row3_w = math.max(90, math.floor((avail_w - (gap * 2)) / 3))
    r.ImGui_Text(ctx, 'Edit preset (Active preset: ' .. active_name .. ')')
    r.ImGui_Separator(ctx)
    r.ImGui_Text(ctx, 'Name')
    r.ImGui_SameLine(ctx, 190)
    r.ImGui_SetNextItemWidth(ctx, -1)
    local changed_name, new_name = r.ImGui_InputText(ctx, '##preset_name', state.editor.name)
    if changed_name then
      state.editor.name = new_name
    end
    local changed_tracks, apply_tracks = r.ImGui_Checkbox(ctx, 'Apply track backgrounds', state.editor.apply_tracks ~= false)
    if changed_tracks then
      state.editor.apply_tracks = apply_tracks
    end
    r.ImGui_SameLine(ctx)
    local changed_grid, apply_grid = r.ImGui_Checkbox(ctx, 'Apply grid colors', state.editor.apply_grid ~= false)
    if changed_grid then
      state.editor.apply_grid = apply_grid
    end
    r.ImGui_Dummy(ctx, 0, 6)
    r.ImGui_Text(ctx, 'Background colors')
    r.ImGui_Separator(ctx)
    for _, field in ipairs(BACKGROUND_FIELDS) do
      draw_color_row(field)
    end
    r.ImGui_Dummy(ctx, 0, 6)
    r.ImGui_Text(ctx, 'Grid colors')
    r.ImGui_Separator(ctx)
    for _, field in ipairs(GRID_FIELDS) do
      draw_color_row(field)
    end
    r.ImGui_Dummy(ctx, 0, 6)
    r.ImGui_Text(ctx, 'Track divider lines')
    r.ImGui_Separator(ctx)
    for _, field in ipairs(DIVIDER_FIELDS) do
      draw_color_row(field)
    end
    r.ImGui_Dummy(ctx, 0, 8)
    r.ImGui_Text(ctx, 'Actions')
    r.ImGui_Separator(ctx)
    if r.ImGui_Button(ctx, 'Apply', row2_w, 30) then
      apply_selected_preset()
    end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, 'Save changes', row2_w, 30) then
      save_editor_changes()
    end
    if r.ImGui_Button(ctx, 'Set as toggle A', row3_w, 28) then
      set_toggle_slot('a')
    end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, 'Set as toggle B', row3_w, 28) then
      set_toggle_slot('b')
    end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, 'Toggle A/B', row3_w, 28) then
      toggle_a_b()
    end
    if r.ImGui_Button(ctx, 'Read current colors', row2_w, 28) then
      save_current_to_selected()
    end
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, 'Reset theme defaults', row2_w, 28) then
      local ok = run_action('TK Arrange Background Presets - Reset', function()
        reset_theme_colors()
        return true
      end)
      if ok then
        set_message('REAPER theme colors reset to defaults.', 0x9AD27AFF)
      else
        set_message('Reset failed.', 0xE07A7AFF)
      end
    end
    r.ImGui_Dummy(ctx, 0, 8)
    if state.message ~= '' then
      r.ImGui_TextColored(ctx, state.message_color, state.message)
    end
  end
  r.ImGui_EndChild(ctx)
end

local function draw_window()
  if not state.window_applied then
    r.ImGui_SetNextWindowPos(ctx, state.data.window.x, state.data.window.y, r.ImGui_Cond_Always())
    r.ImGui_SetNextWindowSize(ctx, WINDOW_DEFAULTS.w, WINDOW_DEFAULTS.h, r.ImGui_Cond_Always())
    state.window_applied = true
  end
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowRounding(), 0)
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), 0)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_WindowBg(), 0x151515FF)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ChildBg(), 0x202020FF)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x5D5D5DFF)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0x7A7A7AFF)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0x4A4A4AFF)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), 0x3A3A3AFF)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgHovered(), 0x505050FF)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgActive(), 0x636363FF)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Header(), 0x4A4A4AFF)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderHovered(), 0x666666FF)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_HeaderActive(), 0x7A7A7AFF)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_CheckMark(), 0xD0D0D0FF)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0xF0F0F0FF)
  r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Separator(), 0x8A8A8AFF)
  local visible, open = r.ImGui_Begin(ctx, WINDOW_TITLE, false, r.ImGui_WindowFlags_NoCollapse() | r.ImGui_WindowFlags_NoResize() | r.ImGui_WindowFlags_NoTitleBar())
  if visible then
    local pos_x, pos_y = r.ImGui_GetWindowPos(ctx)
    local size_w, size_h = r.ImGui_GetWindowSize(ctx)
    state.data.window.x = pos_x
    state.data.window.y = pos_y
    state.data.window.w = size_w
    state.data.window.h = size_h
    r.ImGui_Text(ctx, 'TK ARRANGE BACKGROUND PRESETS')
    r.ImGui_SameLine(ctx)
    local avail_w = r.ImGui_GetContentRegionAvail(ctx)
    r.ImGui_Dummy(ctx, avail_w - 28, 0)
    r.ImGui_SameLine(ctx)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0xAA2222FF)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0xCC3333FF)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0x881818FF)
    if r.ImGui_Button(ctx, '##close', 20, 20) then
      save_data(state.data)
      state.should_close = true
    end
    r.ImGui_PopStyleColor(ctx, 3)
    r.ImGui_Separator(ctx)
    local _, avail_h = r.ImGui_GetContentRegionAvail(ctx)
    local panel_h = math.max(200, avail_h - 6)
    draw_left_panel(panel_h)
    r.ImGui_SameLine(ctx)
    draw_right_panel(panel_h)
    r.ImGui_End(ctx)
  end
  r.ImGui_PopStyleColor(ctx, 14)
  r.ImGui_PopStyleVar(ctx, 2)
end

local function loop()
  draw_window()
  if not state.should_close then
    r.defer(loop)
  end
end

sync_editor_from_selected()
loop()
