-- @description TK Latency Presets
-- @author TouristKiller
-- @version 1.0.0
-- @changelog
--[[
+ Initial version: named presets for REAPER's recording latency manual offsets
+ Samples and/or milliseconds, plus the "use audio driver reported latency" option
+ Optional automatic switching based on the active audio device
+ Generates stand-alone apply-actions for toolbar/keyboard/MIDI
]]--

----------------------------------------------------------------------------------------------------------
-- TK Latency Presets
-- Stores named sets of REAPER's recording latency compensation values and applies them in one click.
-- The values live in Preferences > Audio > Recording:
--   adjrecmanlatin  = input manual offset  (samples)
--   adjrecmanlat    = output manual offset (samples)
--   manuallatin     = input manual offset  (milliseconds * 100)
--   manuallat       = output manual offset (milliseconds * 100)
--   adjreclat       = use audio driver reported latency (checkbox)
----------------------------------------------------------------------------------------------------------

local r = reaper

if not r.APIExists('ImGui_GetBuiltinPath') then
  return r.MB('TK Latency Presets requires the ReaImGui extension (0.9 or newer).', 'Missing dependency', 0)
end
package.path = r.ImGui_GetBuiltinPath() .. '/?.lua;' .. package.path
local ImGui = require 'imgui' '0.9'

local SCRIPT_NAME = 'TK Latency Presets'
local EXT_SECTION = 'TK_LatencyPresets'
local DATA_DIR    = r.GetResourcePath() .. '/Data/TK_Latency_Presets/'
local DATA_FILE   = DATA_DIR .. 'presets.lua'
local SCRIPT_PATH = (debug.getinfo(1, 'S').source:match('^@?(.*[\\/])')) or ''

local CFG_IN_SAMPLES  = 'adjrecmanlatin'
local CFG_OUT_SAMPLES = 'adjrecmanlat'
local CFG_IN_MS       = 'manuallatin'
local CFG_OUT_MS      = 'manuallat'
local CFG_USE_DRIVER  = 'adjreclat'

local HAS_SWS_READ  = r.APIExists('SNM_GetIntConfigVar')
local HAS_SWS_WRITE = r.APIExists('SNM_SetIntConfigVar')
local HAS_DEVICE_API = r.APIExists('GetAudioDeviceInfo')

local COL_OK   = 0xA3BE8CFF
local COL_WARN = 0xEBCB8BFF
local COL_ERR  = 0xBF616AFF
local COL_DIM  = 0xA0A0A0FF
local COL_ACCENT = 0xD8DEE9FF

local WINDOW_DEFAULTS = {x = 160, y = 160, w = 840, h = 620}
local WINDOW_MIN_W = 840
local WINDOW_MIN_H = 620

----------------------------------------------------------------------------------------------------------
-- Config variable access
----------------------------------------------------------------------------------------------------------
local function to_signed32(value)
  value = math.floor(tonumber(value) or 0)
  if value > 2147483647 then value = value - 4294967296 end
  if value < -2147483648 then value = value + 4294967296 end
  return value
end

local function clamp_int(value, min_value, max_value)
  value = math.floor(tonumber(value) or 0)
  if value < min_value then return min_value end
  if value > max_value then return max_value end
  return value
end

local function get_config_int(name)
  if HAS_SWS_READ then
    local sentinel = -1234567891
    local value = r.SNM_GetIntConfigVar(name, sentinel)
    if value ~= sentinel then return to_signed32(value) end
  end
  if r.APIExists('get_config_var_string') then
    local ok, value = r.get_config_var_string(name)
    if ok then
      local number = tonumber(value)
      if number then return to_signed32(number) end
    end
  end
  return nil
end

local function set_config_int(name, value)
  if not HAS_SWS_WRITE then return false end
  return r.SNM_SetIntConfigVar(name, clamp_int(value, -2147483648, 2147483647)) and true or false
end

local function read_reaper_settings()
  return {
    in_samples = get_config_int(CFG_IN_SAMPLES) or 0,
    out_samples = get_config_int(CFG_OUT_SAMPLES) or 0,
    in_ms = (get_config_int(CFG_IN_MS) or 0) / 100,
    out_ms = (get_config_int(CFG_OUT_MS) or 0) / 100,
    use_driver = (get_config_int(CFG_USE_DRIVER) or 0) ~= 0
  }
end

----------------------------------------------------------------------------------------------------------
-- Audio device
----------------------------------------------------------------------------------------------------------
local function device_attribute(attribute)
  if not HAS_DEVICE_API then return '' end
  local ok, value = r.GetAudioDeviceInfo(attribute, '')
  if ok and value then return value end
  return ''
end

local function get_device_info()
  local info = {
    mode = device_attribute('MODE'),
    input = device_attribute('IDENT_IN'),
    output = device_attribute('IDENT_OUT'),
    srate = tonumber(device_attribute('SRATE')) or 0,
    bsize = tonumber(device_attribute('BSIZE')) or 0
  }
  info.id = table.concat({info.mode, info.input, info.output}, ' | ')
  if info.id:gsub('[%s|]', '') == '' then info.id = '' end
  return info
end

local function get_samplerate(device)
  local srate = device and device.srate or 0
  if srate and srate > 0 then return srate end
  local project_srate = r.GetSetProjectInfo(0, 'PROJECT_SRATE', 0, false)
  if project_srate and project_srate > 0 then return project_srate end
  return 48000
end

local function samples_to_ms(samples, srate)
  if not srate or srate <= 0 then return 0 end
  return (tonumber(samples) or 0) * 1000 / srate
end

----------------------------------------------------------------------------------------------------------
-- Storage
----------------------------------------------------------------------------------------------------------
local function serialize(value, indent)
  local value_type = type(value)
  if value_type == 'number' then
    if value ~= value or value == math.huge or value == -math.huge then return '0' end
    return string.format('%.10g', value)
  elseif value_type == 'boolean' then
    return tostring(value)
  elseif value_type == 'string' then
    return string.format('%q', value)
  elseif value_type == 'table' then
    local pad = indent .. '  '
    local out = {'{'}
    local count = #value
    for i = 1, count do
      out[#out + 1] = pad .. serialize(value[i], pad) .. ','
    end
    local keys = {}
    for key in pairs(value) do
      if type(key) == 'string' then keys[#keys + 1] = key end
    end
    table.sort(keys)
    for _, key in ipairs(keys) do
      out[#out + 1] = pad .. '[' .. string.format('%q', key) .. '] = ' .. serialize(value[key], pad) .. ','
    end
    out[#out + 1] = indent .. '}'
    return table.concat(out, '\n')
  end
  return 'nil'
end

local function default_preset(name, settings)
  settings = settings or {in_samples = 0, out_samples = 0, in_ms = 0, out_ms = 0, use_driver = true}
  return {
    name = name or 'Preset',
    in_samples = settings.in_samples or 0,
    out_samples = settings.out_samples or 0,
    in_ms = settings.in_ms or 0,
    out_ms = settings.out_ms or 0,
    use_driver = settings.use_driver ~= false,
    device = ''
  }
end

local function normalize_preset(preset, index)
  preset = type(preset) == 'table' and preset or {}
  preset.name = (type(preset.name) == 'string' and preset.name ~= '') and preset.name or ('Preset ' .. index)
  preset.in_samples = clamp_int(preset.in_samples or 0, -2147483648, 2147483647)
  preset.out_samples = clamp_int(preset.out_samples or 0, -2147483648, 2147483647)
  preset.in_ms = tonumber(preset.in_ms) or 0
  preset.out_ms = tonumber(preset.out_ms) or 0
  preset.use_driver = preset.use_driver ~= false
  preset.apply_samples = nil
  preset.apply_ms = nil
  preset.apply_driver = nil
  preset.device = type(preset.device) == 'string' and preset.device or ''
  return preset
end

local function normalize_data(data)
  data = type(data) == 'table' and data or {}
  data.presets = type(data.presets) == 'table' and data.presets or {}
  if #data.presets == 0 then
    data.presets[1] = default_preset('Current settings', read_reaper_settings())
  end
  for i = 1, #data.presets do
    data.presets[i] = normalize_preset(data.presets[i], i)
  end
  data.selected = clamp_int(data.selected or 1, 1, #data.presets)
  data.auto_switch = data.auto_switch == true
  data.window = type(data.window) == 'table' and data.window or {}
  data.window.x = tonumber(data.window.x) or WINDOW_DEFAULTS.x
  data.window.y = tonumber(data.window.y) or WINDOW_DEFAULTS.y
  data.window.w = tonumber(data.window.w) or WINDOW_DEFAULTS.w
  data.window.h = tonumber(data.window.h) or WINDOW_DEFAULTS.h
  return data
end

local function load_data()
  local file = io.open(DATA_FILE, 'r')
  if not file then return normalize_data(nil) end
  local content = file:read('*a')
  file:close()
  if not content or content == '' then return normalize_data(nil) end
  local chunk = load(content, 'TK_Latency_Presets', 't', {})
  if not chunk then return normalize_data(nil) end
  local ok, parsed = pcall(chunk)
  if not ok or type(parsed) ~= 'table' then return normalize_data(nil) end
  return normalize_data(parsed)
end

local function save_data(data)
  r.RecursiveCreateDirectory(DATA_DIR, 0)
  local file = io.open(DATA_FILE, 'w')
  if not file then return false end
  file:write('return ' .. serialize(normalize_data(data), '') .. '\n')
  file:close()
  return true
end

----------------------------------------------------------------------------------------------------------
-- Apply
----------------------------------------------------------------------------------------------------------
local function apply_preset(preset)
  if not HAS_SWS_WRITE then
    return false, 'The SWS/S&M extension is required to change the latency settings.'
  end
  if type(preset) ~= 'table' then return false, 'No preset selected.' end
  set_config_int(CFG_IN_SAMPLES, preset.in_samples or 0)
  set_config_int(CFG_OUT_SAMPLES, preset.out_samples or 0)
  set_config_int(CFG_IN_MS, math.floor((tonumber(preset.in_ms) or 0) * 100 + 0.5))
  set_config_int(CFG_OUT_MS, math.floor((tonumber(preset.out_ms) or 0) * 100 + 0.5))
  set_config_int(CFG_USE_DRIVER, preset.use_driver and 1 or 0)
  r.SetExtState(EXT_SECTION, 'active_preset', preset.name or '', false)
  return true, 'Applied "' .. (preset.name or '') .. '".'
end

----------------------------------------------------------------------------------------------------------
-- Generated apply-actions
----------------------------------------------------------------------------------------------------------
local function generate_action(preset)
  if type(preset) ~= 'table' then return false, 'No preset selected.' end
  local name = preset.name or 'Preset'
  local safe_name = name:gsub('[^%w%s%-_]', ''):gsub('%s+', '_')
  if safe_name == '' then safe_name = 'Preset' end
  local filename = SCRIPT_PATH .. 'TK_Latency_Apply_' .. safe_name .. '.lua'
  local L = {}
  L[#L + 1] = '-- @description TK Latency Presets - Apply: ' .. name
  L[#L + 1] = '-- @author TouristKiller'
  L[#L + 1] = '-- @version 1.0'
  L[#L + 1] = '-- Generated by TK Latency Presets. Editing this file by hand is fine,'
  L[#L + 1] = '-- but regenerating the action from the script overwrites it.'
  L[#L + 1] = ''
  L[#L + 1] = 'local r = reaper'
  L[#L + 1] = ''
  L[#L + 1] = "if not r.APIExists('SNM_SetIntConfigVar') then"
  L[#L + 1] = "  return r.MB('This action needs the SWS/S&M extension.', 'TK Latency Presets', 0)"
  L[#L + 1] = 'end'
  L[#L + 1] = ''
  L[#L + 1] = string.format("r.SNM_SetIntConfigVar('%s', %d)", CFG_IN_SAMPLES, clamp_int(preset.in_samples or 0, -2147483648, 2147483647))
  L[#L + 1] = string.format("r.SNM_SetIntConfigVar('%s', %d)", CFG_OUT_SAMPLES, clamp_int(preset.out_samples or 0, -2147483648, 2147483647))
  L[#L + 1] = string.format("r.SNM_SetIntConfigVar('%s', %d)", CFG_IN_MS, math.floor((tonumber(preset.in_ms) or 0) * 100 + 0.5))
  L[#L + 1] = string.format("r.SNM_SetIntConfigVar('%s', %d)", CFG_OUT_MS, math.floor((tonumber(preset.out_ms) or 0) * 100 + 0.5))
  L[#L + 1] = string.format("r.SNM_SetIntConfigVar('%s', %d)", CFG_USE_DRIVER, preset.use_driver and 1 or 0)
  L[#L + 1] = ''
  L[#L + 1] = string.format("r.SetExtState('%s', 'active_preset', %q, false)", EXT_SECTION, name)
  L[#L + 1] = ''
  L[#L + 1] = 'local _, _, sec, cmd = r.get_action_context()'
  L[#L + 1] = string.format("local prev_cmd = tonumber(r.GetExtState('%s', 'active_cmd')) or 0", EXT_SECTION)
  L[#L + 1] = string.format("local prev_sec = tonumber(r.GetExtState('%s', 'active_sec')) or 0", EXT_SECTION)
  L[#L + 1] = 'if prev_cmd ~= 0 and prev_cmd ~= cmd then'
  L[#L + 1] = '  r.SetToggleCommandState(prev_sec, prev_cmd, 0)'
  L[#L + 1] = '  r.RefreshToolbar2(prev_sec, prev_cmd)'
  L[#L + 1] = 'end'
  L[#L + 1] = 'r.SetToggleCommandState(sec, cmd, 1)'
  L[#L + 1] = 'r.RefreshToolbar2(sec, cmd)'
  L[#L + 1] = string.format("r.SetExtState('%s', 'active_cmd', tostring(cmd), false)", EXT_SECTION)
  L[#L + 1] = string.format("r.SetExtState('%s', 'active_sec', tostring(sec), false)", EXT_SECTION)
  local file = io.open(filename, 'w')
  if not file then return false, 'Could not write the action file.' end
  file:write(table.concat(L, '\n') .. '\n')
  file:close()
  r.AddRemoveReaScript(true, 0, filename, true)
  return true, 'Action created: TK_Latency_Apply_' .. safe_name .. '.lua'
end

----------------------------------------------------------------------------------------------------------
-- State
----------------------------------------------------------------------------------------------------------
local ctx = ImGui.CreateContext(SCRIPT_NAME)

local state = {
  data = load_data(),
  message = '',
  message_color = COL_OK,
  device = get_device_info(),
  current = read_reaper_settings(),
  last_device_id = nil,
  last_poll = 0,
  window_applied = false,
  open = true
}
state.last_device_id = state.device.id

local function set_message(text, color)
  state.message = text or ''
  state.message_color = color or COL_OK
end

local function selected_preset()
  return state.data.presets[state.data.selected]
end

local function refresh_current()
  state.current = read_reaper_settings()
  state.device = get_device_info()
end

local function apply_selected()
  local ok, message = apply_preset(selected_preset())
  refresh_current()
  save_data(state.data)
  set_message(message, ok and COL_OK or COL_ERR)
end

local function find_preset_for_device(device_id)
  if not device_id or device_id == '' then return nil end
  for _, preset in ipairs(state.data.presets) do
    if preset.device ~= '' and preset.device == device_id then return preset end
  end
  return nil
end

local function poll_device_change()
  if not state.data.auto_switch then return end
  local now = r.time_precise()
  if now - state.last_poll < 1.0 then return end
  state.last_poll = now
  local device = get_device_info()
  if device.id == state.last_device_id then return end
  state.last_device_id = device.id
  state.device = device
  local preset = find_preset_for_device(device.id)
  if not preset then
    set_message('Audio device changed, no preset is linked to it.', COL_WARN)
    return
  end
  local ok, message = apply_preset(preset)
  refresh_current()
  set_message(ok and ('Auto-switch: ' .. message) or message, ok and COL_OK or COL_ERR)
end

----------------------------------------------------------------------------------------------------------
-- UI
----------------------------------------------------------------------------------------------------------
local function draw_title_bar()
  local avail_w = ImGui.GetContentRegionAvail(ctx)
  local close_size = 14
  ImGui.TextColored(ctx, COL_ACCENT, SCRIPT_NAME)
  ImGui.SameLine(ctx, math.max(160, avail_w - close_size))
  local draw_list = ImGui.GetWindowDrawList(ctx)
  local close_x, close_y = ImGui.GetCursorScreenPos(ctx)
  ImGui.DrawList_AddCircleFilled(draw_list, close_x + close_size * 0.5, close_y + close_size * 0.5, close_size * 0.5, 0xF7768EFF)
  ImGui.DrawList_AddCircle(draw_list, close_x + close_size * 0.5, close_y + close_size * 0.5, close_size * 0.5, 0x3A1018FF, 16, 1)
  if ImGui.InvisibleButton(ctx, '##close', close_size, close_size) then state.open = false end
  if ImGui.IsItemHovered(ctx) then ImGui.SetTooltip(ctx, 'Close') end
  ImGui.Separator(ctx)
end

local function draw_header()
  local srate = get_samplerate(state.device)
  ImGui.Text(ctx, 'Preferences > Audio > Recording - manual latency offset')
  ImGui.Separator(ctx)
  if not HAS_SWS_WRITE then
    ImGui.TextColored(ctx, COL_ERR, 'SWS/S&M extension not found: presets can be edited but not applied.')
  end
  local device_text
  if not HAS_DEVICE_API then
    device_text = 'Audio device: unknown (needs REAPER 6.02 or newer)'
  elseif state.device.id == '' then
    device_text = 'Audio device: no device open'
  else
    device_text = string.format('Audio device: %s in / %s out - %d Hz, %d spls block',
      state.device.input ~= '' and state.device.input or '?',
      state.device.output ~= '' and state.device.output or '?',
      srate, state.device.bsize or 0)
  end
  ImGui.TextColored(ctx, COL_DIM, device_text)
  ImGui.TextColored(ctx, COL_DIM, string.format(
    'REAPER now: input %d spls (%.2f ms) + %.2f ms  |  output %d spls (%.2f ms) + %.2f ms  |  driver latency %s',
    state.current.in_samples, samples_to_ms(state.current.in_samples, srate), state.current.in_ms,
    state.current.out_samples, samples_to_ms(state.current.out_samples, srate), state.current.out_ms,
    state.current.use_driver and 'on' or 'off'))
  ImGui.Dummy(ctx, 0, 2)
end

local function draw_preset_list(height)
  if ImGui.BeginChild(ctx, '##presets', 220, height, 1) then
    ImGui.Text(ctx, 'Presets')
    ImGui.Separator(ctx)
    for index, preset in ipairs(state.data.presets) do
      local label = preset.name
      if preset.device ~= '' then label = label .. ' *' end
      if ImGui.Selectable(ctx, label .. '##preset' .. index, index == state.data.selected) then
        state.data.selected = index
      end
      if ImGui.IsItemHovered(ctx) then
        if preset.device ~= '' then
          ImGui.SetTooltip(ctx, 'Linked to: ' .. preset.device .. '\nDouble click to apply')
        else
          ImGui.SetTooltip(ctx, 'Double click to apply')
        end
        if ImGui.IsMouseDoubleClicked(ctx, 0) then
          state.data.selected = index
          apply_selected()
        end
      end
    end
    ImGui.Dummy(ctx, 0, 4)
    ImGui.Separator(ctx)
    local available_w = ImGui.GetContentRegionAvail(ctx)
    local button_gap = 6
    local action_w = math.floor((available_w - button_gap * 2) / 3)
    if ImGui.Button(ctx, 'Add', action_w, 22) then
      state.data.presets[#state.data.presets + 1] = default_preset('Preset ' .. (#state.data.presets + 1), read_reaper_settings())
      state.data.selected = #state.data.presets
      save_data(state.data)
      set_message('Preset added from the current REAPER settings.', COL_OK)
    end
    ImGui.SameLine(ctx, 0, button_gap)
    if ImGui.Button(ctx, 'Copy', action_w, 22) then
      local source = selected_preset()
      if source then
        local copy = {}
        for key, value in pairs(source) do copy[key] = value end
        copy.name = source.name .. ' copy'
        table.insert(state.data.presets, state.data.selected + 1, copy)
        state.data.selected = state.data.selected + 1
        save_data(state.data)
      end
    end
    ImGui.SameLine(ctx, 0, button_gap)
    if ImGui.Button(ctx, 'Delete', action_w, 22) then
      if #state.data.presets > 1 then
        table.remove(state.data.presets, state.data.selected)
        state.data.selected = clamp_int(state.data.selected, 1, #state.data.presets)
        save_data(state.data)
      else
        set_message('The last preset cannot be deleted.', COL_WARN)
      end
    end
    local move_w = math.floor((available_w - button_gap) / 2)
    if ImGui.Button(ctx, 'Move up', move_w, 20) then
      local index = state.data.selected
      if index > 1 then
        state.data.presets[index], state.data.presets[index - 1] = state.data.presets[index - 1], state.data.presets[index]
        state.data.selected = index - 1
        save_data(state.data)
      end
    end
    ImGui.SameLine(ctx, 0, button_gap)
    if ImGui.Button(ctx, 'Move down', move_w, 20) then
      local index = state.data.selected
      if index < #state.data.presets then
        state.data.presets[index], state.data.presets[index + 1] = state.data.presets[index + 1], state.data.presets[index]
        state.data.selected = index + 1
        save_data(state.data)
      end
    end
    ImGui.EndChild(ctx)
  end
end

local function draw_editor(height)
  if ImGui.BeginChild(ctx, '##editor', 0, height, 1) then
    local preset = selected_preset()
    if not preset then
      ImGui.Text(ctx, 'No preset selected.')
      ImGui.EndChild(ctx)
      return
    end
    local srate = get_samplerate(state.device)
    local changed

    ImGui.Text(ctx, 'Preset')
    ImGui.Separator(ctx)
    ImGui.Text(ctx, 'Name')
    ImGui.SameLine(ctx, 150)
    ImGui.SetNextItemWidth(ctx, -1)
    local name_changed, new_name = ImGui.InputText(ctx, '##name', preset.name)
    if name_changed then preset.name = new_name end

    ImGui.Dummy(ctx, 0, 6)
    ImGui.Text(ctx, 'Manual offset in samples')
    ImGui.Separator(ctx)
    ImGui.Text(ctx, 'Input offset')
    ImGui.SameLine(ctx, 150)
    ImGui.SetNextItemWidth(ctx, 140)
    changed, preset.in_samples = ImGui.InputInt(ctx, '##in_samples', preset.in_samples, 1, 10)
    if changed then preset.in_samples = clamp_int(preset.in_samples, -2147483648, 2147483647) end
    ImGui.SameLine(ctx)
    ImGui.TextColored(ctx, COL_DIM, string.format('= %.2f ms @ %d Hz', samples_to_ms(preset.in_samples, srate), srate))

    ImGui.Text(ctx, 'Output offset')
    ImGui.SameLine(ctx, 150)
    ImGui.SetNextItemWidth(ctx, 140)
    changed, preset.out_samples = ImGui.InputInt(ctx, '##out_samples', preset.out_samples, 1, 10)
    if changed then preset.out_samples = clamp_int(preset.out_samples, -2147483648, 2147483647) end
    ImGui.SameLine(ctx)
    ImGui.TextColored(ctx, COL_DIM, string.format('= %.2f ms @ %d Hz', samples_to_ms(preset.out_samples, srate), srate))

    ImGui.Dummy(ctx, 0, 6)
    ImGui.Text(ctx, 'Manual offset in milliseconds')
    ImGui.Separator(ctx)
    ImGui.Text(ctx, 'Input offset (ms)')
    ImGui.SameLine(ctx, 150)
    ImGui.SetNextItemWidth(ctx, 140)
    changed, preset.in_ms = ImGui.InputDouble(ctx, '##in_ms', preset.in_ms, 0.1, 1.0, '%.2f')
    ImGui.Text(ctx, 'Output offset (ms)')
    ImGui.SameLine(ctx, 150)
    ImGui.SetNextItemWidth(ctx, 140)
    changed, preset.out_ms = ImGui.InputDouble(ctx, '##out_ms', preset.out_ms, 0.1, 1.0, '%.2f')
    ImGui.Dummy(ctx, 0, 6)
    ImGui.Text(ctx, 'Driver reported latency')
    ImGui.Separator(ctx)
    changed, preset.use_driver = ImGui.Checkbox(ctx, 'Use audio driver reported latency', preset.use_driver)

    ImGui.Dummy(ctx, 0, 6)
    ImGui.Text(ctx, 'Audio device link (optional)')
    ImGui.Separator(ctx)
    ImGui.SetNextItemWidth(ctx, -1)
    local device_changed, device_value = ImGui.InputText(ctx, '##device', preset.device)
    if device_changed then preset.device = device_value end
    if ImGui.Button(ctx, 'Link current device', 160, 20) then
      state.device = get_device_info()
      if state.device.id == '' then
        set_message('No audio device information available.', COL_WARN)
      else
        preset.device = state.device.id
        save_data(state.data)
        set_message('Preset linked to the active audio device.', COL_OK)
      end
    end
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, 'Clear link', 100, 20) then
      preset.device = ''
      save_data(state.data)
    end

    ImGui.Dummy(ctx, 0, 8)
    ImGui.Separator(ctx)
    if ImGui.Button(ctx, 'Apply preset', 150, 24) then
      apply_selected()
    end
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, 'Save', 100, 24) then
      save_data(state.data)
      set_message('Presets saved.', COL_OK)
    end
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, 'Read current settings', 170, 24) then
      local current = read_reaper_settings()
      preset.in_samples = current.in_samples
      preset.out_samples = current.out_samples
      preset.in_ms = current.in_ms
      preset.out_ms = current.out_ms
      preset.use_driver = current.use_driver
      state.current = current
      save_data(state.data)
      set_message('Preset filled with the current REAPER settings.', COL_OK)
    end
    ImGui.SameLine(ctx)
    if ImGui.Button(ctx, 'Create action', 130, 24) then
      save_data(state.data)
      local ok, message = generate_action(preset)
      set_message(message, ok and COL_OK or COL_ERR)
    end
    ImGui.EndChild(ctx)
  end
end

local function draw_footer()
  local changed, auto_switch = ImGui.Checkbox(ctx, 'Auto switch: apply the linked preset when the audio device changes', state.data.auto_switch)
  if changed then
    state.data.auto_switch = auto_switch
    state.last_device_id = get_device_info().id
    save_data(state.data)
  end
  if ImGui.IsItemHovered(ctx) then
    ImGui.SetTooltip(ctx, 'Only while this window is open.\nUse TK_Latency_Presets_AutoSwitch.lua for background switching.')
  end
  if state.message ~= '' then
    ImGui.TextColored(ctx, state.message_color, state.message)
  end
end

local function draw_window()
  if not state.window_applied then
    ImGui.SetNextWindowPos(ctx, state.data.window.x, state.data.window.y, ImGui.Cond_FirstUseEver)
    ImGui.SetNextWindowSize(ctx, state.data.window.w, state.data.window.h, ImGui.Cond_FirstUseEver)
    state.window_applied = true
  end
  ImGui.SetNextWindowSizeConstraints(ctx, WINDOW_MIN_W, WINDOW_MIN_H, 100000, 100000)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowRounding, 6)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_ChildRounding, 5)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_FrameRounding, 4)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowPadding, 10, 10)
  ImGui.PushStyleVar(ctx, ImGui.StyleVar_ItemSpacing, 8, 7)
  ImGui.PushStyleColor(ctx, ImGui.Col_WindowBg, 0x111111FF)
  ImGui.PushStyleColor(ctx, ImGui.Col_ChildBg, 0x181818FF)
  ImGui.PushStyleColor(ctx, ImGui.Col_PopupBg, 0x1B1B1BFF)
  ImGui.PushStyleColor(ctx, ImGui.Col_FrameBg, 0x242424FF)
  ImGui.PushStyleColor(ctx, ImGui.Col_FrameBgHovered, 0x333333FF)
  ImGui.PushStyleColor(ctx, ImGui.Col_Border, 0x444444FF)
  ImGui.PushStyleColor(ctx, ImGui.Col_Separator, 0x3A3A3AFF)
  ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0xF0F0F0FF)
  ImGui.PushStyleColor(ctx, ImGui.Col_Button, 0x242424FF)
  ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, 0x333333FF)
  ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, 0x4C566AFF)
  ImGui.PushStyleColor(ctx, ImGui.Col_Header, 0x2C2C2CFF)
  ImGui.PushStyleColor(ctx, ImGui.Col_HeaderHovered, 0x383838FF)
  ImGui.PushStyleColor(ctx, ImGui.Col_HeaderActive, 0x4C566AFF)
  ImGui.PushStyleColor(ctx, ImGui.Col_CheckMark, COL_ACCENT)
  local visible, open = ImGui.Begin(ctx, SCRIPT_NAME, true, ImGui.WindowFlags_NoTitleBar | ImGui.WindowFlags_NoCollapse)
  state.open = open
  if visible then
    if ImGui.IsKeyPressed(ctx, ImGui.Key_Escape, false) then state.open = false end
    local pos_x, pos_y = ImGui.GetWindowPos(ctx)
    local size_w, size_h = ImGui.GetWindowSize(ctx)
    state.data.window.x, state.data.window.y = pos_x, pos_y
    state.data.window.w, state.data.window.h = size_w, size_h
    draw_title_bar()
    draw_header()
    local _, avail_h = ImGui.GetContentRegionAvail(ctx)
    local panel_h = math.max(160, avail_h - 52)
    draw_preset_list(panel_h)
    ImGui.SameLine(ctx)
    draw_editor(panel_h)
    ImGui.Dummy(ctx, 0, 2)
    draw_footer()
    ImGui.End(ctx)
  end
  ImGui.PopStyleColor(ctx, 15)
  ImGui.PopStyleVar(ctx, 5)
end

local frame_counter = 0

local function loop()
  if not ImGui.ValidatePtr(ctx, 'ImGui_Context*') then return end
  frame_counter = frame_counter + 1
  if frame_counter % 30 == 0 then
    state.current = read_reaper_settings()
    state.device = get_device_info()
  end
  poll_device_change()
  draw_window()
  if state.open then
    r.defer(loop)
  else
    save_data(state.data)
  end
end

r.atexit(function() save_data(state.data) end)
loop()
