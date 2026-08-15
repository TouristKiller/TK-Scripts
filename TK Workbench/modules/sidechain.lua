local r = reaper
local Theme = require("core.theme")
local UI = require("core.ui")
local UIScale = require("core.ui_scale")
local Text = require("core.text")
local Routing = require("core.routing")
local FxChunk = require("core.fx_chunk")
local json = require("core.json")

local M = {
  id = "sidechain",
  title = "Sidechain",
  icon = "SC",
  version = "0.1.0"
}

local EXT_SECTION = "TK_WORKBENCH_SIDECHAIN"

-- I_SENDMODE: 0 = post-fader (post-pan), 1 = pre-FX, 3 = pre-fader (post-FX).
-- Pre-fader is the default here: a sidechain that changes because someone moved
-- the source's fader is a surprise, and the trigger is usually wanted at a fixed
-- level regardless of how loud the source sits in the mix.
local SEND_MODES = {
  { value = 3, label = "Pre-fader (post-FX)" },
  { value = 1, label = "Pre-FX" },
  { value = 0, label = "Post-fader" }
}

local BUILTIN_ID = "builtin_reacomp"
local SIGNIN_NAME = "SignIn"

-- What a second source on the same track should do. Sharing is the default:
-- "duck the pad for the kick AND the snare" wants one compressor driven by the
-- sum of both, not two compressors in series each with their own trigger. The
-- separate pair is the rarer, deliberate case.
local EXTRA_MODES = {
  { value = "share", label = "Feed the same compressor" },
  { value = "own", label = "Own pair and compressor" }
}

local defaults = {
  send_mode = 3,
  open_fx = true,
  extra_mode = "share",
  preset_id = BUILTIN_ID,
  search = ""
}

local state = {
  loaded = false,
  data_path = nil,
  data = nil,
  target_guid = nil,
  candidates = {},
  existing = {},
  dirty = true,
  scanned_at = 0,
  bottom_fixed_h = nil,
  capture_open = false,
  capture_fx = nil,
  capture_name = "",
  capture_name_touched = false,
  capture_settings = true,
  capture_preset_id = nil,
  rename_open = false,
  rename_id = nil,
  rename_text = "",
  last_error = nil
}

local util = {}
local store = {}
local chain = {}
local view = {}

--------------------------------------------------------------------------------
-- util
--------------------------------------------------------------------------------

function util.now() return os.time() end

function util.precise_now()
  if r.time_precise then return r.time_precise() end
  return os.clock()
end

function util.clean(value, fallback)
  value = tostring(value or ""):match("^%s*(.-)%s*$") or ""
  if value == "" then return fallback end
  return value
end

function util.read_text(path)
  local file = io.open(path, "rb")
  if not file then return nil end
  local content = file:read("*all")
  file:close()
  return content
end

function util.write_json(path, value)
  local ok, encoded = pcall(json.encode, value)
  if not ok or not encoded then return false end
  local file = io.open(path, "w")
  if not file then return false end
  file:write(encoded)
  file:close()
  return true
end

function util.track_name(track)
  if not Routing.valid_track(track) then return "Track" end
  local ok, name = r.GetTrackName(track)
  if ok and name and name ~= "" then return name end
  return "Track"
end

function util.track_label(track)
  local number = math.floor(tonumber(r.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER")) or 0)
  local name = util.track_name(track)
  if number > 0 then return string.format("%d. %s", number, name) end
  return name
end

function util.track_color(track)
  local native = r.GetTrackColor and r.GetTrackColor(track) or 0
  if not native or native == 0 then return nil end
  if r.ColorFromNative then
    local ok, red, green, blue = pcall(r.ColorFromNative, native & 0xFFFFFF)
    if ok and red then return ((red & 0xFF) << 24) | ((green & 0xFF) << 16) | ((blue & 0xFF) << 8) | 0xCC end
  end
  return nil
end

function util.fit(ctx, value, max_width)
  value = tostring(value or "")
  if max_width <= 0 then return "" end
  if UIScale.text_width(ctx, value) <= max_width then return value end
  while #value > 1 and UIScale.text_width(ctx, value .. "...") > max_width do
    value = value:sub(1, Text.char_start(value, #value) - 1)
  end
  return value .. "..."
end

function util.ensure_settings(app)
  app.settings.sidechain = app.settings.sidechain or {}
  local settings = app.settings.sidechain
  local changed = false
  for key, value in pairs(defaults) do
    if settings[key] == nil then
      settings[key] = value
      changed = true
    end
  end
  if changed and app.save_settings then app.save_settings() end
  return settings
end

function util.send_mode_label(mode)
  for _, entry in ipairs(SEND_MODES) do
    if entry.value == mode then return entry.label end
  end
  return "Mode " .. tostring(mode)
end

function util.extra_mode_label(mode)
  for _, entry in ipairs(EXTRA_MODES) do
    if entry.value == mode then return entry.label end
  end
  return EXTRA_MODES[1].label
end

function util.ctrl_down(ctx)
  if not r.ImGui_IsKeyDown then return false end
  local down = false
  if r.ImGui_Key_LeftCtrl then down = down or r.ImGui_IsKeyDown(ctx, r.ImGui_Key_LeftCtrl()) end
  if r.ImGui_Key_RightCtrl then down = down or r.ImGui_IsKeyDown(ctx, r.ImGui_Key_RightCtrl()) end
  if r.ImGui_Key_LeftSuper then down = down or r.ImGui_IsKeyDown(ctx, r.ImGui_Key_LeftSuper()) end
  if r.ImGui_Key_RightSuper then down = down or r.ImGui_IsKeyDown(ctx, r.ImGui_Key_RightSuper()) end
  return down
end

--------------------------------------------------------------------------------
-- store: compressor presets, next to config.json
--------------------------------------------------------------------------------

function store.new_data()
  return { schema_version = 1, presets = {} }
end

function store.normalize(value)
  local data = store.new_data()
  if type(value) ~= "table" then return data end
  for index, preset in ipairs(type(value.presets) == "table" and value.presets or {}) do
    -- "chunk" carries the plugin's saved state, "plugin" only its name: the
    -- second loads the compressor at its factory settings, correctly routed.
    local kind = preset.kind == "plugin" and "plugin" or "chunk"
    local has_body = kind == "plugin" or (type(preset.chunk) == "string" and preset.chunk ~= "")
    if type(preset) == "table" and has_body and util.clean(preset.plugin, "") ~= "" then
      local created = tonumber(preset.created_at) or util.now()
      local pins = {}
      for _, pin in ipairs(type(preset.pins) == "table" and preset.pins or {}) do
        if tonumber(pin.pin) and tonumber(pin.offset) then
          pins[#pins + 1] = { pin = math.floor(pin.pin), offset = math.floor(pin.offset) }
        end
      end
      data.presets[#data.presets + 1] = {
        id = tostring(preset.id or ("preset_" .. tostring(created) .. "_" .. tostring(index))),
        name = util.clean(preset.name, "Preset " .. tostring(index)),
        kind = kind,
        chunk = kind == "chunk" and preset.chunk or nil,
        plugin = util.clean(preset.plugin, ""),
        pins = pins,
        created_at = created
      }
    end
  end
  return data
end

function store.add(name, plugin, chunk, pins)
  local created = util.now()
  local preset = {
    id = "preset_" .. tostring(created) .. "_" .. tostring(#state.data.presets + 1),
    name = util.clean(name, plugin),
    kind = chunk and "chunk" or "plugin",
    chunk = chunk,
    plugin = plugin,
    pins = pins or {},
    created_at = created
  }
  state.data.presets[#state.data.presets + 1] = preset
  store.save()
  return preset
end

-- Re-read a preset from a plugin that is on a track right now. The identity of
-- the preset stays put - same id, so whatever is pointing at it keeps working -
-- while everything that describes the compressor is replaced.
function store.update(id, name, plugin, chunk, pins)
  for _, preset in ipairs(state.data.presets) do
    if preset.id == id then
      preset.name = util.clean(name, preset.name)
      preset.plugin = plugin
      preset.kind = chunk and "chunk" or "plugin"
      preset.chunk = chunk
      preset.pins = pins or {}
      store.save()
      return preset
    end
  end
  return nil
end

function store.remove(id)
  for index, preset in ipairs(state.data.presets) do
    if preset.id == id then
      table.remove(state.data.presets, index)
      store.save()
      return true
    end
  end
  return false
end

function store.rename(id, name)
  for _, preset in ipairs(state.data.presets) do
    if preset.id == id then
      preset.name = util.clean(name, preset.name)
      store.save()
      return true
    end
  end
  return false
end

function store.load(app)
  state.data_path = (app.script_path or "") .. "sidechain.json"
  local content = util.read_text(state.data_path)
  if content and content ~= "" then
    local ok, decoded = pcall(json.decode, content)
    state.data = store.normalize(ok and decoded or nil)
  else
    state.data = store.new_data()
  end
  state.loaded = true
end

function store.save()
  if not state.data_path or not state.data then return false end
  return util.write_json(state.data_path, state.data)
end

-- The built-in entry is not stored: it is a recipe, not a captured chunk, and it
-- must survive a deleted json file.
function store.presets()
  local list = { { id = BUILTIN_ID, name = "ReaComp (built-in)", kind = "builtin" } }
  for _, preset in ipairs(state.data and state.data.presets or {}) do list[#list + 1] = preset end
  return list
end

function store.find(id)
  for _, preset in ipairs(store.presets()) do
    if preset.id == id then return preset end
  end
  return nil
end

--------------------------------------------------------------------------------
-- chain: the routing itself
--------------------------------------------------------------------------------

-- Which channel pair a sidechain lands on. Anything below channel 3 is the
-- track's own audio, and a pair already fed by another receive is taken.
function chain.first_free_pair(target)
  if not Routing.valid_track(target) then return 2 end
  local used = {}
  local count = r.GetTrackNumSends(target, -1) or 0
  for index = 0, count - 1 do
    local raw = r.GetTrackSendInfo_Value(target, -1, index, "I_DSTCHAN")
    local parsed = Routing.chan_parse(raw)
    if not parsed.none then used[parsed.channel] = true end
  end
  local pair = 2
  while used[pair] and pair < 60 do pair = pair + 2 end
  return pair
end

-- ASSUMPTION, verified against ReaComp 7.75: SignIn holds the first channel of
-- the detector pair, zero based, exactly like I_DSTCHAN on a send - 0 is the
-- main input, 2 is what ReaComp's menu calls the auxiliary input. Measured on
-- channels 3/4 only; if a higher pair ever reads back wrong, this is the line
-- to look at.
function chain.signin_for_pair(pair)
  return math.floor(tonumber(pair) or 2)
end

function chain.find_param(track, fx, name)
  local count = r.TrackFX_GetNumParams(track, fx) or 0
  for param = 0, count - 1 do
    local _, param_name = r.TrackFX_GetParamName(track, fx, param, "")
    if tostring(param_name) == name then return param end
  end
  return nil
end

-- SignIn reads as a plain number over a range whose top end is not documented
-- anywhere, so the scale is measured rather than assumed, and the result is read
-- back and corrected instead of trusted.
function chain.set_signin(track, fx, wanted)
  local param = chain.find_param(track, fx, SIGNIN_NAME)
  if not param then return false, "ReaComp has no " .. SIGNIN_NAME .. " parameter" end
  local _, min_value, max_value = r.TrackFX_GetParam(track, fx, param)
  if not min_value or max_value == min_value then return false, "SignIn has no usable range" end
  r.TrackFX_SetParam(track, fx, param, max_value)
  local _, top = r.TrackFX_GetFormattedParamValue(track, fx, param, "")
  local scale = tonumber(top)
  if not scale or scale <= 0 then return false, "Could not read the SignIn scale" end
  local raw = min_value + (max_value - min_value) * (wanted / scale)
  for _ = 1, 8 do
    raw = math.max(min_value, math.min(max_value, raw))
    r.TrackFX_SetParam(track, fx, param, raw)
    local _, shown = r.TrackFX_GetFormattedParamValue(track, fx, param, "")
    local current = tonumber(shown)
    if current == wanted then return true end
    if not current then return false, "SignIn does not read back as a number" end
    raw = raw + (max_value - min_value) * ((wanted - current) / scale)
  end
  return false, "Could not land SignIn on " .. tostring(wanted)
end

-- Capture: which input pins were listening above the track's own audio, and how
-- far each sits from the lowest of them. Storing the offset rather than the
-- channel is what lets the same preset land on 3/4 here and 7/8 there.
function chain.capture(track, fx)
  local plugin = FxChunk.plugin_name(track, fx)
  if not plugin then return nil, "Could not read the plugin name" end
  local chunk = FxChunk.get_block(track, fx)
  if not chunk then return nil, "Could not read the plugin's settings" end
  local base, pins = nil, {}
  for _, entry in ipairs(Routing.input_pin_channels(track, fx)) do
    if entry.channel >= 2 then
      if not base or entry.channel < base then base = entry.channel end
    end
  end
  if base then
    for _, entry in ipairs(Routing.input_pin_channels(track, fx)) do
      if entry.channel >= 2 then pins[#pins + 1] = { pin = entry.pin, offset = entry.channel - base } end
    end
  end
  return { plugin = plugin, chunk = chunk, pins = pins, base = base }, nil
end

function chain.add_compressor(target, preset, pair)
  if preset.kind == "builtin" then
    local fx = r.TrackFX_AddByName(target, "ReaComp", false, -1)
    if not fx or fx < 0 then return nil, "Could not add ReaComp" end
    local ok, err = chain.set_signin(target, fx, chain.signin_for_pair(pair))
    if not ok then return fx, err end
    return fx, nil
  end
  local fx = r.TrackFX_AddByName(target, preset.plugin, false, -1)
  if not fx or fx < 0 then return nil, "Could not add " .. tostring(preset.plugin) end
  local warning = nil
  if preset.kind == "chunk" then
    if not FxChunk.replace_block(target, fx, preset.chunk) then
      warning = "Added " .. tostring(preset.plugin) .. " but could not restore its settings"
    end
  else
    -- No stored state, so whatever key input switch the plugin has of its own is
    -- at its factory position. Routing it is all this module can do.
    warning = "Loaded at its default settings - switch on its key input if it has one"
  end
  if #(preset.pins or {}) == 0 then
    return fx, warning or "No key input was captured with this preset, so its detector was left alone"
  end
  -- The stored settings point at the channels the preset was captured on; the
  -- pins are what moves it to the pair this track actually uses.
  for _, entry in ipairs(preset.pins) do
    Routing.set_input_pin_channel(target, fx, entry.pin, pair + entry.offset)
  end
  return fx, warning
end

function chain.record(target, source, pair, fx_guid)
  local key = Routing.track_guid(target)
  if not key then return end
  local ok, raw = r.GetProjExtState(0, EXT_SECTION, key)
  local list = {}
  if ok == 1 and raw and raw ~= "" then
    local decoded_ok, decoded = pcall(json.decode, raw)
    if decoded_ok and type(decoded) == "table" then list = decoded end
  end
  list[#list + 1] = {
    source = Routing.track_guid(source),
    pair = pair,
    fx = fx_guid,
    at = util.now()
  }
  local encoded_ok, encoded = pcall(json.encode, list)
  if encoded_ok then r.SetProjExtState(0, EXT_SECTION, key, encoded) end
end

function chain.records(target)
  local key = Routing.track_guid(target)
  if not key then return {} end
  local ok, raw = r.GetProjExtState(0, EXT_SECTION, key)
  if ok ~= 1 or not raw or raw == "" then return {} end
  local decoded_ok, decoded = pcall(json.decode, raw)
  if not decoded_ok or type(decoded) ~= "table" then return {} end
  return decoded
end

function chain.forget(target, source_guid, pair)
  local key = Routing.track_guid(target)
  if not key then return end
  local list = chain.records(target)
  local kept = {}
  for _, entry in ipairs(list) do
    if not (entry.source == source_guid and tonumber(entry.pair) == pair) then kept[#kept + 1] = entry end
  end
  local ok, encoded = pcall(json.encode, kept)
  if ok then r.SetProjExtState(0, EXT_SECTION, key, #kept > 0 and encoded or "") end
end

function chain.fx_index_by_guid(track, guid)
  if not guid or guid == "" or not r.TrackFX_GetFXGUID then return nil end
  local count = r.TrackFX_GetCount(track) or 0
  for index = 0, count - 1 do
    if r.TrackFX_GetFXGUID(track, index) == guid then return index end
  end
  return nil
end

-- The pair an existing compressor is already listening to, if there is one.
-- Sharing means feeding that, so several sources sum into one detector.
function chain.shared_pair(target)
  local best = nil
  for _, entry in ipairs(chain.records(target)) do
    local pair = tonumber(entry.pair)
    if pair and entry.fx and chain.fx_index_by_guid(target, entry.fx) then
      if not best or pair < best then best = pair end
    end
  end
  return best
end

-- What clicking a source will do, worked out in one place so the tooltip and the
-- action can never disagree about it.
-- Worked out once per frame, not once per row: it reads project state and does
-- not depend on which source is hovered.
function chain.plan(settings, target, invert)
  local mode = settings.extra_mode == "own" and "own" or "share"
  if invert then mode = mode == "share" and "own" or "share" end
  local shared = chain.shared_pair(target)
  if mode == "share" and shared then
    return { pair = shared, add_fx = false, shared = true }
  end
  return { pair = chain.first_free_pair(target), add_fx = true, shared = false, alternative = shared }
end

function chain.create(app, settings, source, target, preset, plan)
  if not Routing.valid_track(source) or not Routing.valid_track(target) then return false, "Track is gone" end
  if source == target then return false, "A track cannot feed its own sidechain" end
  plan = plan or chain.plan(settings, target, false)
  local pair = plan.pair
  local created_fx_guid, warning = nil, nil
  local ok = Routing.write_with_undo("Sidechain: " .. util.track_name(source) .. " to " .. util.track_name(target), function()
    Routing.set_track_channels(target, pair + 2)
    local send = r.CreateTrackSend(source, target)
    if not send or send < 0 then return false end
    r.SetTrackSendInfo_Value(source, 0, send, "I_SRCCHAN", 0)
    r.SetTrackSendInfo_Value(source, 0, send, "I_DSTCHAN", pair)
    r.SetTrackSendInfo_Value(source, 0, send, "I_SENDMODE", math.floor(tonumber(settings.send_mode) or 3))
    if plan.add_fx then
      local fx, fx_err = chain.add_compressor(target, preset, pair)
      warning = fx_err
      if fx then
        created_fx_guid = r.TrackFX_GetFXGUID and r.TrackFX_GetFXGUID(target, fx) or nil
        if settings.open_fx ~= false and r.TrackFX_Show then r.TrackFX_Show(target, fx, 3) end
      end
    end
    return true
  end)
  if not ok then return false, "Could not create the send" end
  chain.record(target, source, pair, created_fx_guid)
  state.dirty = true
  return true, warning, pair, plan
end

function chain.remove(app, target, entry)
  if not Routing.valid_track(target) then return false end
  local source = entry.source_track
  local ok = Routing.write_with_undo("Sidechain: remove", function()
    if Routing.valid_track(source) then
      local count = r.GetTrackNumSends(source, 0) or 0
      for index = count - 1, 0, -1 do
        local destination = r.GetTrackSendInfo_Value(source, 0, index, "P_DESTTRACK")
        local dst = Routing.chan_parse(r.GetTrackSendInfo_Value(source, 0, index, "I_DSTCHAN"))
        if destination == target and dst.channel == entry.pair then
          r.RemoveTrackSend(source, 0, index)
          break
        end
      end
    end
    if entry.fx_guid then
      local fx = chain.fx_index_by_guid(target, entry.fx_guid)
      if fx then r.TrackFX_Delete(target, fx) end
    end
    return true
  end)
  if ok then
    chain.forget(target, entry.source_guid, entry.pair)
    state.dirty = true
  end
  return ok
end

--------------------------------------------------------------------------------
-- scanning
--------------------------------------------------------------------------------

function view.target(app)
  local track = app.selection and app.selection.track and app.selection.track.pointer
  if Routing.valid_track(track) then return track end
  return nil
end

function view.scan(app, target)
  local now = util.precise_now()
  local guid = Routing.track_guid(target)
  if not state.dirty and guid == state.target_guid and (now - state.scanned_at) < 0.75 then return end
  state.scanned_at = now
  state.target_guid = guid
  state.dirty = false

  local records = chain.records(target)
  local by_source = {}
  for _, entry in ipairs(records) do
    if entry.source then by_source[entry.source .. ":" .. tostring(entry.pair)] = entry end
  end

  -- Existing sidechains are read from the receives themselves rather than from
  -- the record: a send removed by hand in the routing window must disappear here
  -- too, and one made by hand should still show up.
  state.existing = {}
  local count = r.GetTrackNumSends(target, -1) or 0
  for index = 0, count - 1 do
    local dst = Routing.chan_parse(r.GetTrackSendInfo_Value(target, -1, index, "I_DSTCHAN"))
    if not dst.none and dst.channel >= 2 then
      local source = r.GetTrackSendInfo_Value(target, -1, index, "P_SRCTRACK")
      local source_guid = Routing.valid_track(source) and Routing.track_guid(source) or nil
      local record = source_guid and by_source[source_guid .. ":" .. tostring(dst.channel)] or nil
      state.existing[#state.existing + 1] = {
        source_track = source,
        source_guid = source_guid,
        name = Routing.valid_track(source) and util.track_label(source) or "(missing track)",
        pair = dst.channel,
        mode = math.floor(tonumber(r.GetTrackSendInfo_Value(target, -1, index, "I_SENDMODE")) or 0),
        fx_guid = record and record.fx or nil,
        fx_present = record and record.fx and chain.fx_index_by_guid(target, record.fx) ~= nil or false
      }
    end
  end

  local routed = {}
  for _, entry in ipairs(state.existing) do
    if entry.source_guid then routed[entry.source_guid] = entry.pair end
  end

  state.candidates = {}
  local total = r.CountTracks(0) or 0
  for index = 0, total - 1 do
    local track = r.GetTrack(0, index)
    if track and track ~= target then
      local track_guid = Routing.track_guid(track)
      state.candidates[#state.candidates + 1] = {
        track = track,
        guid = track_guid,
        label = util.track_label(track),
        color = util.track_color(track),
        routed_to = track_guid and routed[track_guid] or nil
      }
    end
  end
end

function view.filtered(settings)
  local needle = Text.lower(util.clean(settings.search, ""))
  if needle == "" then return state.candidates end
  local result = {}
  for _, entry in ipairs(state.candidates) do
    if Text.lower(entry.label):find(needle, 1, true) then result[#result + 1] = entry end
  end
  return result
end

--------------------------------------------------------------------------------
-- drawing
--------------------------------------------------------------------------------

function view.section(ctx, label)
  r.ImGui_Dummy(ctx, 1, UIScale.round(2))
  r.ImGui_TextColored(ctx, Theme.colors.text_dim, label)
  r.ImGui_Separator(ctx)
end

function view.draw_header(app, settings, target)
  local ctx = app.ctx
  local avail_w = r.ImGui_GetContentRegionAvail(ctx) or UIScale.round(240)
  local channels = Routing.track_channel_count(target)
  local name = util.fit(ctx, util.track_label(target), avail_w - UIScale.round(60))
  r.ImGui_TextColored(ctx, Theme.colors.accent, name)
  r.ImGui_SameLine(ctx)
  r.ImGui_TextColored(ctx, Theme.colors.text_dim, tostring(channels) .. " ch")
  if r.ImGui_IsItemHovered(ctx) then
    r.ImGui_SetTooltip(ctx, "The selected track receives the sidechain.\nIts channel count grows automatically when a pair is needed.")
  end

  local presets = store.presets()
  local current = store.find(settings.preset_id) or presets[1]
  local button_w = UIScale.round(26)
  local gap = UIScale.gap(4)
  local row_w = r.ImGui_GetContentRegionAvail(ctx) or UIScale.round(240)
  r.ImGui_SetNextItemWidth(ctx, math.max(UIScale.round(60), row_w - button_w * 2 - gap * 2))
  if r.ImGui_BeginCombo(ctx, "##sidechain_preset", current.name) then
    for _, preset in ipairs(presets) do
      if r.ImGui_Selectable(ctx, preset.name, preset.id == current.id) then
        settings.preset_id = preset.id
        if app.save_settings then app.save_settings() end
      end
    end
    r.ImGui_EndCombo(ctx)
  end
  if r.ImGui_IsItemHovered(ctx) then
    r.ImGui_SetTooltip(ctx, "What gets added to the receiving track.\n\nReaComp is set up for you. Any other compressor is stored by\ncapturing one you already have working, so its key input\nfollows to whatever channel pair a track ends up using.")
  end
  r.ImGui_SameLine(ctx, 0, gap)
  if r.ImGui_Button(ctx, "+##sidechain_capture", button_w, 0) then
    state.capture_open = true
    state.capture_preset_id = nil
    state.capture_fx = nil
    state.capture_name = ""
    state.capture_name_touched = false
  end
  if r.ImGui_IsItemHovered(ctx) then
    r.ImGui_SetTooltip(ctx, "Store a compressor from the selected track as a preset.\nSet its sidechain up by hand once, then capture it here.")
  end
  r.ImGui_SameLine(ctx, 0, gap)
  if r.ImGui_Button(ctx, "...##sidechain_preset_menu", button_w, 0) then r.ImGui_OpenPopup(ctx, "sidechain_preset_menu") end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Rename or delete the selected preset") end
  if r.ImGui_BeginPopup(ctx, "sidechain_preset_menu") then
    if current.kind == "builtin" then
      r.ImGui_TextColored(ctx, Theme.colors.text_dim, "The built-in preset cannot be changed.")
    else
      if r.ImGui_MenuItem(ctx, "Update from selected FX") then
        state.capture_open = true
        state.capture_preset_id = current.id
        state.capture_fx = nil
        state.capture_name = current.name
        state.capture_name_touched = true
        state.capture_settings = current.kind == "chunk"
      end
      if r.ImGui_MenuItem(ctx, "Rename") then
        state.rename_id = current.id
        state.rename_text = current.name
        state.rename_open = true
      end
      if r.ImGui_MenuItem(ctx, "Delete") then
        store.remove(current.id)
        settings.preset_id = BUILTIN_ID
        if app.save_settings then app.save_settings() end
        app.status = "Preset deleted"
      end
      r.ImGui_Separator(ctx)
      r.ImGui_TextColored(ctx, Theme.colors.text_dim, current.plugin or "")
      r.ImGui_TextColored(ctx, Theme.colors.text_dim, current.kind == "chunk"
        and "settings stored" or "routing only, factory settings")
      r.ImGui_TextColored(ctx, Theme.colors.text_dim, #(current.pins or {}) > 0
        and (tostring(#current.pins) .. " key input pin(s) stored")
        or "no key input stored")
    end
    r.ImGui_EndPopup(ctx)
  end
  return current
end

-- Capturing reads the FX list of the selected track, so what you are copying is
-- the compressor you can see and hear working, not a description of one.
function view.draw_capture_popup(app, target)
  local ctx = app.ctx
  if state.capture_open then
    r.ImGui_OpenPopup(ctx, "Capture Compressor")
    state.capture_open = false
  end
  if not r.ImGui_BeginPopup(ctx, "Capture Compressor") then return end
  local updating = state.capture_preset_id and store.find(state.capture_preset_id) or nil
  r.ImGui_TextColored(ctx, Theme.colors.text_dim, updating
    and ("Re-read \"" .. updating.name .. "\" from " .. util.track_name(target) .. ":")
    or ("Pick the compressor to store, from " .. util.track_name(target) .. ":"))
  local count = r.TrackFX_GetCount(target) or 0
  if count == 0 then
    r.ImGui_TextColored(ctx, Theme.colors.warning, "This track has no FX.")
  end
  -- A Selectable closes the popup it sits in unless told not to, which shut this
  -- window the moment an FX was picked - before the name field or Save could be
  -- reached, so choosing a plugin looked like it did nothing at all.
  local keep_open = 0
  if r.ImGui_SelectableFlags_DontClosePopups then
    keep_open = r.ImGui_SelectableFlags_DontClosePopups()
  elseif r.ImGui_SelectableFlags_NoAutoClosePopups then
    keep_open = r.ImGui_SelectableFlags_NoAutoClosePopups()
  end
  for fx = 0, count - 1 do
    local _, name = r.TrackFX_GetFXName(target, fx, "")
    local pins = Routing.input_pin_channels(target, fx)
    local key = nil
    for _, entry in ipairs(pins) do
      if entry.channel >= 2 then key = entry.channel; break end
    end
    local label = tostring(name)
    if r.ImGui_Selectable(ctx, label .. "##fx" .. tostring(fx), state.capture_fx == fx, keep_open) then
      state.capture_fx = fx
      -- The name follows the plugin you pick, until you type one yourself.
      if not state.capture_name_touched then state.capture_name = tostring(name) end
    end
    if r.ImGui_IsItemHovered(ctx) then
      r.ImGui_SetTooltip(ctx, key
        and ("Key input on channels " .. Routing.chan_label(key) .. ".\nThat is what makes this preset land on the right pair later.")
        or "No input pin above channel 2, so no key input to store.\nSet this plugin's sidechain up first, then capture it.")
    end
  end
  r.ImGui_Separator(ctx)
  if state.capture_fx == nil then
    r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Pick a plugin above to store it.")
  end
  local changed, value = r.ImGui_InputText(ctx, "Name", state.capture_name or "")
  if changed then
    state.capture_name = value
    state.capture_name_touched = true
  end
  local store_changed, store_settings = r.ImGui_Checkbox(ctx, "Store the plugin's current settings", state.capture_settings ~= false)
  if store_changed then state.capture_settings = store_settings end
  if r.ImGui_IsItemHovered(ctx) then
    r.ImGui_SetTooltip(ctx,
      "On: the preset carries this plugin exactly as it stands, ready to work.\n\n" ..
      "Off: only the plugin and its key input routing are stored, so it loads at\n" ..
      "its factory settings for you to dial in. Lighter, but a plugin with its own\n" ..
      "sidechain switch will need that switched on by hand every time.")
  end
  if state.capture_settings == false then
    r.ImGui_TextColored(ctx, Theme.colors.warning, "Routing only: turn on the plugin's own key input yourself.")
  end
  local can_save = state.capture_fx ~= nil and util.clean(state.capture_name, "") ~= ""
  local button_w = UIScale.text_button_w(ctx, "Cancel", 70)
  if not can_save and r.ImGui_BeginDisabled then r.ImGui_BeginDisabled(ctx, true) end
  if r.ImGui_Button(ctx, "Save", button_w, 0) and can_save then
    local captured, err = chain.capture(target, state.capture_fx)
    if captured then
      local keep = state.capture_settings ~= false
      local chunk = keep and captured.chunk or nil
      local preset = updating
        and store.update(updating.id, state.capture_name, captured.plugin, chunk, captured.pins)
        or store.add(state.capture_name, captured.plugin, chunk, captured.pins)
      local settings = util.ensure_settings(app)
      settings.preset_id = preset.id
      if app.save_settings then app.save_settings() end
      local where = #captured.pins > 0
        and (" with its key input on channels " .. Routing.chan_label(captured.base))
        or ", but without a key input"
      local verb = updating and "Updated " or (keep and "Captured " or "Stored the plugin only: ")
      app.status = verb .. preset.name .. where
    else
      app.status = "Capture failed: " .. tostring(err)
    end
    state.capture_fx = nil
    state.capture_name = ""
    state.capture_name_touched = false
    state.capture_preset_id = nil
    r.ImGui_CloseCurrentPopup(ctx)
  end
  if not can_save and r.ImGui_EndDisabled then r.ImGui_EndDisabled(ctx) end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "Cancel", button_w, 0) then
    state.capture_fx = nil
    state.capture_preset_id = nil
    r.ImGui_CloseCurrentPopup(ctx)
  end
  r.ImGui_EndPopup(ctx)
end

function view.draw_rename_popup(app)
  local ctx = app.ctx
  if state.rename_open then
    r.ImGui_OpenPopup(ctx, "Rename Preset")
    state.rename_open = false
  end
  if not r.ImGui_BeginPopup(ctx, "Rename Preset") then return end
  local changed, value = r.ImGui_InputText(ctx, "Name", state.rename_text or "")
  if changed then state.rename_text = value end
  local button_w = UIScale.text_button_w(ctx, "Cancel", 70)
  if r.ImGui_Button(ctx, "Save", button_w, 0) then
    store.rename(state.rename_id, state.rename_text)
    app.status = "Preset renamed"
    r.ImGui_CloseCurrentPopup(ctx)
  end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "Cancel", button_w, 0) then r.ImGui_CloseCurrentPopup(ctx) end
  r.ImGui_EndPopup(ctx)
end

function view.draw_source_row(app, settings, target, entry, preset, plan)
  local ctx = app.ctx
  r.ImGui_PushID(ctx, entry.guid or entry.label)
  local avail_w = r.ImGui_GetContentRegionAvail(ctx) or UIScale.round(200)
  local row_h = r.ImGui_GetFrameHeight(ctx)
  local clicked = r.ImGui_InvisibleButton(ctx, "##source", math.max(UIScale.round(80), avail_w), row_h)
  local hovered = r.ImGui_IsItemHovered(ctx)
  local x, y = r.ImGui_GetItemRectMin(ctx)
  local draw_list = r.ImGui_GetWindowDrawList(ctx)
  local routed = entry.routed_to ~= nil
  local bg = routed and Theme.colors.accent_soft or (hovered and Theme.colors.frame_hover or Theme.colors.frame_bg)
  r.ImGui_DrawList_AddRectFilled(draw_list, x, y, x + avail_w, y + row_h, bg, UIScale.px(4))
  if entry.color then
    r.ImGui_DrawList_AddRectFilled(draw_list, x, y, x + UIScale.round(4), y + row_h, entry.color, UIScale.px(2))
  end
  local text_color = Theme.text_for_background(bg, Theme.colors.text, nil, 4.5)
  local right = routed and UIScale.round(52) or UIScale.round(8)
  r.ImGui_DrawList_PushClipRect(draw_list, x + UIScale.round(9), y, x + avail_w - right, y + row_h, true)
  r.ImGui_DrawList_AddText(draw_list, x + UIScale.round(9), y + UIScale.round(3), text_color, entry.label)
  r.ImGui_DrawList_PopClipRect(draw_list)
  if routed then
    local label = Routing.chan_label(entry.routed_to)
    r.ImGui_DrawList_AddText(draw_list, x + avail_w - UIScale.round(46), y + UIScale.round(3), Theme.colors.accent, "ch " .. label)
  end
  if hovered then
    local lines = { entry.label, "" }
    if routed then
      lines[#lines + 1] = "Already feeding this track on channels " .. Routing.chan_label(entry.routed_to) .. "."
    end
    if plan.shared then
      lines[#lines + 1] = "Click: send to channels " .. Routing.chan_label(plan.pair) .. ", into the compressor already there."
      lines[#lines + 1] = "Several sources on one pair add up, so one compressor ducks for all of them."
      lines[#lines + 1] = ""
      lines[#lines + 1] = "Ctrl-click: own pair and a second compressor instead."
    else
      lines[#lines + 1] = "Click: send to channels " .. Routing.chan_label(plan.pair) .. " and add " .. preset.name .. "."
      if plan.alternative then
        lines[#lines + 1] = ""
        lines[#lines + 1] = "Ctrl-click: feed the existing compressor on channels " .. Routing.chan_label(plan.alternative) .. " instead."
      end
    end
    r.ImGui_SetTooltip(ctx, table.concat(lines, "\n"))
  end
  if clicked then
    local ok, warning, pair, used = chain.create(app, settings, entry.track, target, preset, plan)
    if not ok then
      app.status = "Sidechain failed: " .. tostring(warning or "unknown reason")
      state.last_error = warning
    elseif warning then
      app.status = "Routed to channels " .. Routing.chan_label(pair) .. ", but " .. warning
      state.last_error = warning
    elseif used and used.shared then
      app.status = string.format("%s added to the compressor on channels %s", entry.label, Routing.chan_label(pair))
      state.last_error = nil
    else
      app.status = string.format("%s to %s on channels %s", entry.label, util.track_name(target), Routing.chan_label(pair))
      state.last_error = nil
    end
  end
  r.ImGui_PopID(ctx)
end

function view.draw_sources(app, settings, target, preset, height)
  local ctx = app.ctx
  local plan = chain.plan(settings, target, util.ctrl_down(ctx))
  if r.ImGui_BeginChild(ctx, "##sidechain_sources", 0, height, 0) then
    local ok, err = pcall(function()
      local list = view.filtered(settings)
      if #list == 0 then
        r.ImGui_TextColored(ctx, Theme.colors.text_dim, #state.candidates == 0 and "No other tracks in this project." or "No track matches.")
        return
      end
      for _, entry in ipairs(list) do view.draw_source_row(app, settings, target, entry, preset, plan) end
    end)
    r.ImGui_EndChild(ctx)
    if not ok then error(err) end
  end
end

function view.draw_existing(app, target, height)
  local ctx = app.ctx
  if r.ImGui_BeginChild(ctx, "##sidechain_existing", 0, height, 0) then
    local ok, err = pcall(function()
      if #state.existing == 0 then
        r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Nothing feeds this track's sidechain yet.")
        return
      end
      local button_w = UIScale.round(22)
      local gap = UIScale.gap(6)
      for index, entry in ipairs(state.existing) do
        r.ImGui_PushID(ctx, index)
        -- Right-align against the row's own starting position: the button sits at
        -- start + available width - button width. Adding a width to a cursor
        -- position, which is what stood here, put it past the edge.
        local start_x = r.ImGui_GetCursorPosX(ctx)
        local avail_w = r.ImGui_GetContentRegionAvail(ctx) or UIScale.round(200)
        local chan_text = "ch " .. Routing.chan_label(entry.pair)
        local chan_w = UIScale.text_width(ctx, chan_text)
        local name_w = math.max(UIScale.round(30), avail_w - button_w - chan_w - gap * 2)
        local tooltip = entry.name .. "\n" .. util.send_mode_label(entry.mode) ..
          (entry.fx_guid and (entry.fx_present and "\nCompressor present" or "\nCompressor was removed") or "\nMade outside this module")
        r.ImGui_Text(ctx, util.fit(ctx, entry.name, name_w))
        if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, tooltip) end
        r.ImGui_SameLine(ctx, 0, gap)
        r.ImGui_SetCursorPosX(ctx, start_x + name_w + gap)
        r.ImGui_TextColored(ctx, Theme.colors.text_dim, chan_text)
        if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, tooltip) end
        r.ImGui_SameLine(ctx, 0, gap)
        r.ImGui_SetCursorPosX(ctx, start_x + math.max(name_w + chan_w + gap * 2, avail_w - button_w))
        if r.ImGui_Button(ctx, "x", button_w, 0) then
          if chain.remove(app, target, entry) then
            app.status = "Removed the sidechain from " .. entry.name
          else
            app.status = "Could not remove that sidechain"
          end
        end
        if r.ImGui_IsItemHovered(ctx) then
          r.ImGui_SetTooltip(ctx, "Remove the send" .. (entry.fx_present and " and the compressor it added" or ""))
        end
        r.ImGui_PopID(ctx)
      end
    end)
    r.ImGui_EndChild(ctx)
    if not ok then error(err) end
  end
end

function view.draw_options(app, settings)
  local ctx = app.ctx
  r.ImGui_SetNextItemWidth(ctx, -1)
  if r.ImGui_BeginCombo(ctx, "##sidechain_extra", util.extra_mode_label(settings.extra_mode)) then
    for _, entry in ipairs(EXTRA_MODES) do
      if r.ImGui_Selectable(ctx, entry.label, entry.value == settings.extra_mode) then
        settings.extra_mode = entry.value
        if app.save_settings then app.save_settings() end
      end
    end
    r.ImGui_EndCombo(ctx)
  end
  if r.ImGui_IsItemHovered(ctx) then
    r.ImGui_SetTooltip(ctx,
      "What a second source on this track does.\n\n" ..
      "Feed the same compressor: it joins the pair that is already there, and the\n" ..
      "sources add up, so one compressor ducks for all of them. This is what\n" ..
      "\"duck the pad for the kick and the snare\" needs.\n\n" ..
      "Own pair and compressor: the source gets its own channels and a second\n" ..
      "compressor, so the two ducks are independent.\n\n" ..
      "Ctrl-click a source to do the other one just this once.")
  end
  r.ImGui_SetNextItemWidth(ctx, -1)
  if r.ImGui_BeginCombo(ctx, "##sidechain_mode", util.send_mode_label(math.floor(tonumber(settings.send_mode) or 3))) then
    for _, entry in ipairs(SEND_MODES) do
      if r.ImGui_Selectable(ctx, entry.label, entry.value == settings.send_mode) then
        settings.send_mode = entry.value
        if app.save_settings then app.save_settings() end
      end
    end
    r.ImGui_EndCombo(ctx)
  end
  if r.ImGui_IsItemHovered(ctx) then
    r.ImGui_SetTooltip(ctx, "How the send taps the source.\nPre-fader keeps the trigger steady when the source's fader moves.")
  end
  local changed, value = r.ImGui_Checkbox(ctx, "Open the compressor", settings.open_fx ~= false)
  if changed then
    settings.open_fx = value
    if app.save_settings then app.save_settings() end
  end
end

--------------------------------------------------------------------------------
-- module contract
--------------------------------------------------------------------------------

function M.init(app)
  util.ensure_settings(app)
  store.load(app)
end

function M.draw(app)
  local ctx = app.ctx
  local settings = util.ensure_settings(app)
  if not state.loaded then store.load(app) end

  local target = view.target(app)
  if not target then
    r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Select the track that should be ducked.")
    r.ImGui_TextWrapped(ctx, "Then pick the track that triggers it - the kick under a bass, a lead vocal over a pad.")
    UI.draw_info_line(ctx, "No track selected")
    return
  end
  if Routing.track_guid(target) ~= state.target_guid then state.dirty = true end
  view.scan(app, target)

  local preset = view.draw_header(app, settings, target)
  view.draw_capture_popup(app, target)
  view.draw_rename_popup(app)

  local info_h = UI.info_line_height(ctx)
  local line_h = r.ImGui_GetTextLineHeight(ctx)
  view.section(ctx, "SOURCES")
  local _, rest_h = r.ImGui_GetContentRegionAvail(ctx)
  -- The canvas does not scroll, so the source list takes what the measured rows
  -- below it leave over rather than a height guessed in advance.
  local existing_h = math.max(line_h * 2, math.min(line_h * 6, r.ImGui_GetFrameHeight(ctx) * math.max(1, #state.existing)))
  local sources_h = math.max(line_h * 4, (rest_h or UIScale.round(300)) - (state.bottom_fixed_h or UIScale.round(120)) - existing_h - info_h)

  local changed, value = UI.search_input(ctx, "##sidechain_search", "Filter tracks", settings.search or "", -1)
  if changed then
    settings.search = value
    if app.save_settings then app.save_settings() end
  end
  view.draw_sources(app, settings, target, preset, sources_h)

  local bottom_start = r.ImGui_GetCursorPosY(ctx)
  view.section(ctx, "FEEDING THIS TRACK")
  view.draw_existing(app, target, existing_h)
  view.section(ctx, "OPTIONS")
  view.draw_options(app, settings)
  state.bottom_fixed_h = math.max(0, r.ImGui_GetCursorPosY(ctx) - bottom_start - existing_h)

  local status = string.format("%d source%s | next free pair %s", #state.candidates, #state.candidates == 1 and "" or "s",
    Routing.chan_label(chain.first_free_pair(target)))
  UI.draw_info_line(ctx, state.last_error or status, { severity = state.last_error and "warning" or nil })
end

return M
