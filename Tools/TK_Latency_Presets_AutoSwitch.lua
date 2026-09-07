-- @description TK Latency Presets - Auto Switch (background toggle)
-- @author TouristKiller
-- @version 1.0.0
-- @changelog
--[[
+ Initial version: watches the active audio device and applies the linked latency preset
]]--

----------------------------------------------------------------------------------------------------------
-- Runs in the background and applies the latency preset that is linked to the audio device
-- currently in use. Link a device to a preset in TK_Latency_Presets.lua ("Link current device").
-- Run the action again to switch the watcher off.
----------------------------------------------------------------------------------------------------------

local r = reaper

local EXT_SECTION = 'TK_LatencyPresets'
local DATA_FILE   = r.GetResourcePath() .. '/Data/TK_Latency_Presets/presets.lua'
local POLL_TIME   = 1.0

local CFG_IN_SAMPLES  = 'adjrecmanlatin'
local CFG_OUT_SAMPLES = 'adjrecmanlat'
local CFG_IN_MS       = 'manuallatin'
local CFG_OUT_MS      = 'manuallat'
local CFG_USE_DRIVER  = 'adjreclat'

local is_new_value, _, section_id, command_id = r.get_action_context()

if r.GetExtState(EXT_SECTION, 'autoswitch_running') == '1' then
  r.SetExtState(EXT_SECTION, 'autoswitch_stop', '1', false)
  r.SetToggleCommandState(section_id, command_id, 0)
  r.RefreshToolbar2(section_id, command_id)
  return
end

if not r.APIExists('SNM_SetIntConfigVar') then
  return r.MB('TK Latency Presets - Auto Switch needs the SWS/S&M extension.', 'Missing dependency', 0)
end
if not r.APIExists('GetAudioDeviceInfo') then
  return r.MB('TK Latency Presets - Auto Switch needs REAPER 6.02 or newer.', 'Missing dependency', 0)
end

r.SetExtState(EXT_SECTION, 'autoswitch_running', '1', false)
r.SetExtState(EXT_SECTION, 'autoswitch_stop', '', false)
r.SetToggleCommandState(section_id, command_id, 1)
r.RefreshToolbar2(section_id, command_id)

local function clamp_int(value)
  value = math.floor(tonumber(value) or 0)
  if value < -2147483648 then return -2147483648 end
  if value > 2147483647 then return 2147483647 end
  return value
end

local function load_presets()
  local file = io.open(DATA_FILE, 'r')
  if not file then return {} end
  local content = file:read('*a')
  file:close()
  if not content or content == '' then return {} end
  local chunk = load(content, 'TK_Latency_Presets', 't', {})
  if not chunk then return {} end
  local ok, data = pcall(chunk)
  if not ok or type(data) ~= 'table' or type(data.presets) ~= 'table' then return {} end
  return data.presets
end

local function device_attribute(attribute)
  local ok, value = r.GetAudioDeviceInfo(attribute, '')
  if ok and value then return value end
  return ''
end

local function device_id()
  local id = table.concat({device_attribute('MODE'), device_attribute('IDENT_IN'), device_attribute('IDENT_OUT')}, ' | ')
  if id:gsub('[%s|]', '') == '' then return '' end
  return id
end

local function apply_preset(preset)
  r.SNM_SetIntConfigVar(CFG_IN_SAMPLES, clamp_int(preset.in_samples or 0))
  r.SNM_SetIntConfigVar(CFG_OUT_SAMPLES, clamp_int(preset.out_samples or 0))
  r.SNM_SetIntConfigVar(CFG_IN_MS, clamp_int((tonumber(preset.in_ms) or 0) * 100 + 0.5))
  r.SNM_SetIntConfigVar(CFG_OUT_MS, clamp_int((tonumber(preset.out_ms) or 0) * 100 + 0.5))
  r.SNM_SetIntConfigVar(CFG_USE_DRIVER, preset.use_driver and 1 or 0)
  r.SetExtState(EXT_SECTION, 'active_preset', preset.name or '', false)
end

local function apply_for_device(id)
  if id == '' then return end
  for _, preset in ipairs(load_presets()) do
    if type(preset) == 'table' and type(preset.device) == 'string' and preset.device ~= '' and preset.device == id then
      apply_preset(preset)
      return preset.name
    end
  end
  return nil
end

local last_device = device_id()
local last_poll = r.time_precise()
apply_for_device(last_device)

local function stop()
  r.SetExtState(EXT_SECTION, 'autoswitch_running', '', false)
  r.SetExtState(EXT_SECTION, 'autoswitch_stop', '', false)
  r.SetToggleCommandState(section_id, command_id, 0)
  r.RefreshToolbar2(section_id, command_id)
end

local function loop()
  if r.GetExtState(EXT_SECTION, 'autoswitch_stop') == '1' then
    stop()
    return
  end
  local now = r.time_precise()
  if now - last_poll >= POLL_TIME then
    last_poll = now
    local id = device_id()
    if id ~= last_device then
      last_device = id
      apply_for_device(id)
    end
  end
  r.defer(loop)
end

r.atexit(stop)
loop()
