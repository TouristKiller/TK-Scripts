local r = reaper
local Theme = require("core.theme")
local UI = require("core.ui")
local UIScale = require("core.ui_scale")

local M = {
  id = "transport",
  title = "Transport",
  icon = "TRN",
  version = "0.1.0"
}

-- Available building blocks (master order shown in the settings menu). The user
-- composes the module from these; enabled ids live (ordered) in settings.blocks.
local AVAILABLE = {
  { id = "transport", title = "Transport buttons" },
  { id = "tempo", title = "Tempo / signature" },
  { id = "time_selection", title = "Time selection" },
  { id = "playrate", title = "Play rate" },
  { id = "metronome", title = "Metronome" },
  { id = "navigator", title = "Navigator" },
  { id = "master_peak", title = "Master scope" },
}

local defaults = {
  blocks = { "transport", "tempo", "time_selection", "playrate", "metronome", "navigator", "master_peak" },
  button_style = "classic",
  anchor = "top", -- "top" = stack from the top, "bottom" = pin the stack to the window bottom
}

local BLOCK_PAYLOAD = "TRANSPORT_BLOCK"

local state = {
  tap_times = {},
  card_heights = {},
  fonts = {},
  tempo_edit = false,
  tempo_edit_text = "",
  tempo_focus = false,
  sig_num = 4,
  sig_denom = 4,
  sig_target = "current", -- "current" measure or "base" (project start)
  nav = { map = nil, map_change = -1, map_track_count = -1, last_build = nil, drag = nil },
  scope = { buf = {}, head = 1, size = 1024 },
}

-- ---------------------------------------------------------------------------
-- Settings
-- ---------------------------------------------------------------------------
local function is_known_block(id)
  for _, b in ipairs(AVAILABLE) do if b.id == id then return true end end
  return false
end

local function block_title(id)
  for _, b in ipairs(AVAILABLE) do if b.id == id then return b.title end end
  return id
end

local function ensure_settings(app)
  app.settings.transport = app.settings.transport or {}
  local settings = app.settings.transport
  for key, value in pairs(defaults) do
    if settings[key] == nil then settings[key] = value end
  end
  -- Sanitise the block list: keep only known ids, drop duplicates.
  if type(settings.blocks) ~= "table" then settings.blocks = { table.unpack(defaults.blocks) } end
  local seen, clean = {}, {}
  for _, id in ipairs(settings.blocks) do
    if is_known_block(id) and not seen[id] then seen[id] = true; clean[#clean + 1] = id end
  end
  settings.blocks = clean
  if settings.anchor ~= "bottom" then settings.anchor = "top" end
  return settings
end

local function save(app) if app.save_settings then app.save_settings() end end

-- Move source block next to target, on the side matching the drag direction:
-- dragging down drops it after the target, dragging up drops it before.
local function reorder_block(app, settings, source, target)
  if source == target then return end
  local from, orig_to
  for i, v in ipairs(settings.blocks) do
    if v == source then from = i end
    if v == target then orig_to = i end
  end
  if not from or not orig_to then return end
  local downward = from < orig_to
  table.remove(settings.blocks, from)
  local to
  for i, v in ipairs(settings.blocks) do if v == target then to = i; break end end
  if not to then settings.blocks[#settings.blocks + 1] = source; save(app); return end
  table.insert(settings.blocks, downward and (to + 1) or to, source)
  save(app)
end

local function block_enabled(settings, id)
  for _, v in ipairs(settings.blocks) do if v == id then return true end end
  return false
end

local function add_block(app, settings, id)
  if not block_enabled(settings, id) then
    settings.blocks[#settings.blocks + 1] = id
    app.status = "Transport: added " .. block_title(id)
    save(app)
  end
end

local function remove_block(app, settings, id)
  for i, v in ipairs(settings.blocks) do
    if v == id then
      table.remove(settings.blocks, i)
      app.status = "Transport: removed " .. block_title(id)
      save(app)
      return
    end
  end
end

local function move_block(app, settings, index, delta)
  local target = index + delta
  if target < 1 or target > #settings.blocks then return end
  settings.blocks[index], settings.blocks[target] = settings.blocks[target], settings.blocks[index]
  save(app)
end

-- ---------------------------------------------------------------------------
-- REAPER state helpers
-- ---------------------------------------------------------------------------
local function play_state() return math.floor(r.GetPlayState() or 0) end
local function is_playing() return (play_state() & 1) == 1 end
local function is_paused() return (play_state() & 2) == 2 end
local function is_recording() return (play_state() & 4) == 4 end
local function repeat_on() return (r.GetSetRepeat and r.GetSetRepeat(-1) or 0) == 1 end
local function toggle_state(cmd) return r.GetToggleCommandState(cmd) == 1 end
local function run(cmd) r.Main_OnCommand(cmd, 0) end

-- Metronome volume via SWS config vars (same approach as the Control Room module).
local METRO_VOL_KEYS = { "projmetrovol", "projmetrovol1", "projmetrov1", "metronomevol" }
local metro_key_checked, metro_key = false, nil
local function metro_vol_key()
  if metro_key_checked then return metro_key end
  metro_key_checked = true
  if not r.SNM_GetDoubleConfigVar or not r.SNM_SetDoubleConfigVar then return nil end
  local sentinel = -987654.321
  for _, k in ipairs(METRO_VOL_KEYS) do
    local ok, v = pcall(r.SNM_GetDoubleConfigVar, k, sentinel)
    if ok and type(v) == "number" and v ~= sentinel then metro_key = k; return k end
  end
  return nil
end
local function read_metro_vol()
  local k = metro_vol_key()
  if not k then return nil end
  local ok, v = pcall(r.SNM_GetDoubleConfigVar, k, 1)
  if ok and type(v) == "number" then return v end
  return nil
end
local function write_metro_vol(v)
  local k = metro_vol_key()
  if k then r.SNM_SetDoubleConfigVar(k, math.max(0.0, math.min(2.0, v))) end
end

local function fmt_pos(pos)
  if r.format_timestr_pos then return r.format_timestr_pos(pos, "", -1) end
  return string.format("%.3f", pos or 0)
end

local function fmt_len(len)
  if r.format_timestr then return r.format_timestr(len, "") end
  return string.format("%.3f", len or 0)
end

-- ---------------------------------------------------------------------------
-- Drawing helpers
-- ---------------------------------------------------------------------------
-- A vector icon button drawn on the window draw list. paint(dl, cx, cy, s, col)
-- receives the centre and a half-extent s. Returns true on left click.
local function glyph_button(ctx, id, size, opts, paint)
  opts = opts or {}
  r.ImGui_PushID(ctx, id)
  local clicked = r.ImGui_InvisibleButton(ctx, "##glyph", size, size)
  local hovered = r.ImGui_IsItemHovered(ctx)
  local x1, y1 = r.ImGui_GetItemRectMin(ctx)
  local x2, y2 = r.ImGui_GetItemRectMax(ctx)
  local dl = r.ImGui_GetWindowDrawList(ctx)
  local active = opts.active == true
  local accent = opts.active_color or Theme.colors.accent
  local bg = active and Theme.colors.accent_soft or (hovered and Theme.colors.frame_hover or Theme.colors.frame_bg)
  local border = (active or hovered) and accent or Theme.colors.border
  local fg = active and accent or Theme.text_for_background(bg, hovered and accent or Theme.colors.text, nil, 3)
  if opts.fg then fg = opts.fg end
  r.ImGui_DrawList_AddRectFilled(dl, x1, y1, x2, y2, bg, UIScale.px(4))
  r.ImGui_DrawList_AddRect(dl, x1, y1, x2, y2, border, UIScale.px(4), 0, active and UIScale.px(1.6) or UIScale.px(0.8))
  paint(dl, (x1 + x2) * 0.5, (y1 + y2) * 0.5, size * 0.28, fg)
  if hovered and opts.tooltip then r.ImGui_SetTooltip(ctx, opts.tooltip) end
  r.ImGui_PopID(ctx)
  return clicked
end

local function paint_play(dl, cx, cy, s, col)
  r.ImGui_DrawList_AddTriangleFilled(dl, cx - s * 0.7, cy - s, cx - s * 0.7, cy + s, cx + s, cy, col)
end
local function paint_stop(dl, cx, cy, s, col)
  r.ImGui_DrawList_AddRectFilled(dl, cx - s * 0.85, cy - s * 0.85, cx + s * 0.85, cy + s * 0.85, col, UIScale.px(1))
end
local function paint_pause(dl, cx, cy, s, col)
  local w = s * 0.4
  r.ImGui_DrawList_AddRectFilled(dl, cx - s * 0.7, cy - s, cx - s * 0.7 + w, cy + s, col)
  r.ImGui_DrawList_AddRectFilled(dl, cx + s * 0.7 - w, cy - s, cx + s * 0.7, cy + s, col)
end
local function paint_record(dl, cx, cy, s, col)
  r.ImGui_DrawList_AddCircleFilled(dl, cx, cy, s * 0.95, col, 24)
end
local function paint_to_start(dl, cx, cy, s, col)
  r.ImGui_DrawList_AddRectFilled(dl, cx - s, cy - s, cx - s + s * 0.35, cy + s, col)
  r.ImGui_DrawList_AddTriangleFilled(dl, cx + s, cy - s, cx + s, cy + s, cx - s * 0.4, cy, col)
end
local function paint_to_end(dl, cx, cy, s, col)
  r.ImGui_DrawList_AddTriangleFilled(dl, cx - s, cy - s, cx - s, cy + s, cx + s * 0.4, cy, col)
  r.ImGui_DrawList_AddRectFilled(dl, cx + s - s * 0.35, cy - s, cx + s, cy + s, col)
end
local function paint_loop(dl, cx, cy, s, col)
  local th = UIScale.px(1.6)
  r.ImGui_DrawList_AddRect(dl, cx - s, cy - s * 0.7, cx + s, cy + s * 0.7, col, s * 0.55, 0, th)
  -- arrowhead on the top edge
  r.ImGui_DrawList_AddTriangleFilled(dl, cx + s * 0.2, cy - s * 0.7 - s * 0.5, cx + s * 0.2, cy - s * 0.7 + s * 0.5, cx + s * 0.9, cy - s * 0.7, col)
end
local function paint_metronome(dl, cx, cy, s, col)
  r.ImGui_DrawList_AddTriangleFilled(dl, cx, cy - s, cx - s * 0.8, cy + s, cx + s * 0.8, cy + s, col)
  r.ImGui_DrawList_AddLine(dl, cx, cy + s * 0.6, cx + s * 0.5, cy - s * 0.4, col, UIScale.px(1.4))
end
local function paint_gear(dl, cx, cy, s, col)
  local th = UIScale.px(1.5)
  r.ImGui_DrawList_AddCircle(dl, cx, cy, s * 0.62, col, 18, th)
  r.ImGui_DrawList_AddCircleFilled(dl, cx, cy, s * 0.22, col, 12)
  for i = 0, 5 do
    local a = i * (math.pi / 3)
    local ca, sa = math.cos(a), math.sin(a)
    r.ImGui_DrawList_AddLine(dl, cx + ca * s * 0.62, cy + sa * s * 0.62, cx + ca * s, cy + sa * s, col, th)
  end
end

-- ---------------------------------------------------------------------------
-- Blocks
-- ---------------------------------------------------------------------------
-- Cached font at a given pixel size (created + attached on first use, like the
-- Timepiece clock). Used to draw the big BPM readout via DrawList_AddTextEx.
local function get_font(ctx, size)
  if not r.ImGui_CreateFont then return nil end
  size = math.max(10, math.floor((tonumber(size) or 24) + 0.5))
  local key = tostring(size)
  if state.fonts[key] then return state.fonts[key] end
  local ok, font = pcall(r.ImGui_CreateFont, "sans-serif", size)
  if not ok or not font then return nil end
  if r.ImGui_Attach then pcall(r.ImGui_Attach, ctx, font) end
  state.fonts[key] = font
  return font
end

local function set_bpm(v)
  if r.SetCurrentBPM then r.SetCurrentBPM(0, math.max(1.0, math.min(960.0, v)), true) end
end

local function do_tap()
  local now = r.time_precise and r.time_precise() or os.clock()
  local taps = state.tap_times
  if #taps > 0 and (now - taps[#taps]) > 2.0 then taps = {} end
  taps[#taps + 1] = now
  while #taps > 6 do table.remove(taps, 1) end
  state.tap_times = taps
  if #taps >= 2 then
    local avg = (taps[#taps] - taps[1]) / (#taps - 1)
    if avg > 0 then set_bpm(60.0 / avg) end
  end
end

local function project_timesig()
  if not r.TimeMap_GetTimeSigAtTime then return 4, 4 end
  local pos = r.GetCursorPosition and r.GetCursorPosition() or 0
  local a, b = r.TimeMap_GetTimeSigAtTime(0, pos)
  return math.floor(a or 4), math.floor(b or 4)
end

-- Set the time signature via a tempo/time-sig marker (REAPER stores time-signature
-- changes as such markers). at_base = true applies it at the project start (measure 1,
-- effectively the base signature); otherwise at the current edit-cursor measure.
local function set_timesig(app, num, denom, at_base)
  if not r.SetTempoTimeSigMarker then return end
  num = math.max(1, math.min(32, math.floor(num)))
  denom = math.max(1, math.min(32, math.floor(denom)))
  local bpm = r.Master_GetTempo and r.Master_GetTempo() or 120.0
  local measures = 0
  if not at_base and r.TimeMap2_timeToBeats then
    local cur = r.GetCursorPosition and r.GetCursorPosition() or 0
    local _, m = r.TimeMap2_timeToBeats(0, cur)
    measures = math.floor(m or 0)
  end
  if r.Undo_BeginBlock then r.Undo_BeginBlock() end
  r.SetTempoTimeSigMarker(0, -1, -1, measures, 0, bpm, num, denom, false)
  if r.UpdateTimeline then r.UpdateTimeline() end
  local where = at_base and " (project start)" or (" at measure " .. (measures + 1))
  if r.Undo_EndBlock then r.Undo_EndBlock("Transport: set time signature " .. num .. "/" .. denom, -1) end
  if app then app.status = "Transport: time signature " .. num .. "/" .. denom .. where end
end

-- Theme the frame/slider-grab colours so sliders match the Workbench theme. The
-- track uses window_bg (darker than the frame_bg card fill) so it reads as a
-- recessed groove instead of blending into the card.
local function push_slider_style(ctx)
  local count = 0
  if r.ImGui_Col_FrameBg then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), Theme.colors.window_bg); count = count + 1 end
  if r.ImGui_Col_FrameBgHovered then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgHovered(), Theme.colors.child_bg); count = count + 1 end
  if r.ImGui_Col_FrameBgActive then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgActive(), Theme.colors.child_bg); count = count + 1 end
  if r.ImGui_Col_SliderGrab then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrab(), Theme.colors.accent); count = count + 1 end
  if r.ImGui_Col_SliderGrabActive then r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrabActive(), Theme.colors.text); count = count + 1 end
  return count
end

local function pop_slider_style(ctx, count)
  if count and count > 0 then r.ImGui_PopStyleColor(ctx, count) end
end

-- A framed text chip (same look as the glyph buttons); highlights when active.
-- Returns clicked, hovered.
local function text_chip(ctx, id, label, active, w, h)
  local dl = r.ImGui_GetWindowDrawList(ctx)
  r.ImGui_PushID(ctx, id)
  local clicked = r.ImGui_InvisibleButton(ctx, "##chip", w, h)
  local hovered = r.ImGui_IsItemHovered(ctx)
  local x1, y1 = r.ImGui_GetItemRectMin(ctx)
  local x2, y2 = r.ImGui_GetItemRectMax(ctx)
  local bg = active and Theme.colors.accent_soft or (hovered and Theme.colors.frame_hover or Theme.colors.frame_bg)
  local border = (active or hovered) and Theme.colors.accent or Theme.colors.border
  local fg = active and Theme.colors.accent or Theme.text_for_background(bg, Theme.colors.text, nil, 3)
  r.ImGui_DrawList_AddRectFilled(dl, x1, y1, x2, y2, bg, UIScale.px(4))
  r.ImGui_DrawList_AddRect(dl, x1, y1, x2, y2, border, UIScale.px(4), 0, UIScale.px(1))
  local tw, th = r.ImGui_CalcTextSize(ctx, label)
  r.ImGui_DrawList_AddText(dl, (x1 + x2 - tw) * 0.5, (y1 + y2 - th) * 0.5, fg, label)
  r.ImGui_PopID(ctx)
  return clicked, hovered
end

-- ---------------------------------------------------------------------------
-- Navigator helpers: a cached bird's-eye map of the arrange (tracks x time).
-- ---------------------------------------------------------------------------
local function nav_clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

local function nav_color(native, fallback)
  if not native or native == 0 or not r.ColorFromNative then return fallback end
  local rr, gg, bb = r.ColorFromNative(native)
  return (rr << 24) | (gg << 16) | (bb << 8) | 0xFF
end

local function nav_build_map()
  local map = { tracks = {}, len = 0 }
  local maxend = 0
  local ntr = r.CountTracks(0)
  local default_item = Theme.colors.accent_soft or 0x2B4B78FF
  for i = 0, ntr - 1 do
    local tr = r.GetTrack(0, i)
    local tcol = r.GetTrackColor and r.GetTrackColor(tr) or 0
    local row = {
      color = nav_color(tcol, Theme.colors.frame_hover),
      tcpy = r.GetMediaTrackInfo_Value(tr, "I_TCPY") or 0,
      tcph = r.GetMediaTrackInfo_Value(tr, "I_TCPH") or 0,
      items = {},
    }
    local nit = r.CountTrackMediaItems(tr)
    for j = 0, nit - 1 do
      local it = r.GetTrackMediaItem(tr, j)
      local pos = r.GetMediaItemInfo_Value(it, "D_POSITION")
      local ilen = r.GetMediaItemInfo_Value(it, "D_LENGTH")
      local icol = r.GetDisplayedMediaItemColor and r.GetDisplayedMediaItemColor(it) or 0
      row.items[#row.items + 1] = { pos = pos, len = ilen, color = nav_color(icol, default_item) }
      if pos + ilen > maxend then maxend = pos + ilen end
    end
    map.tracks[#map.tracks + 1] = row
  end
  local plen = r.GetProjectLength and r.GetProjectLength(0) or 0
  map.len = math.max(1.0, plen, maxend)
  return map
end

local function nav_get_map()
  local nav = state.nav
  local change = r.GetProjectStateChangeCount and r.GetProjectStateChangeCount(0) or 0
  local ntr = r.CountTracks(0)
  if nav.map and change == nav.map_change and ntr == nav.map_track_count then return nav.map end
  local now = os.clock()
  if nav.map and nav.last_build and (now - nav.last_build) < 0.2 then return nav.map end
  nav.map = nav_build_map()
  nav.map_change = change
  nav.map_track_count = ntr
  nav.last_build = now
  return nav.map
end

local function nav_refresh_positions(map)
  for i, row in ipairs(map.tracks) do
    local tr = r.GetTrack(0, i - 1)
    if tr then
      row.tcpy = r.GetMediaTrackInfo_Value(tr, "I_TCPY") or 0
      row.tcph = r.GetMediaTrackInfo_Value(tr, "I_TCPH") or 0
    end
  end
end

local function nav_arrange_height()
  if r.JS_Window_FindChildByID and r.JS_Window_GetClientSize and r.GetMainHwnd then
    local a = r.JS_Window_FindChildByID(r.GetMainHwnd(), 0x3E8)
    if a then
      local ok, _, hgt = r.JS_Window_GetClientSize(a)
      if ok and hgt and hgt > 0 then return hgt end
    end
  end
  return nil
end

-- Horizontal arrange view via the core GetSet_ArrangeView2 (BR_* as fallback).
local function nav_get_view()
  if r.GetSet_ArrangeView2 then
    local s, e = r.GetSet_ArrangeView2(0, false, 0, 0, 0, 0)
    if s and e and e > s then return s, e end
  end
  if r.BR_GetArrangeView then return r.BR_GetArrangeView(0) end
  return nil, nil
end

local function nav_set_view(s, e)
  if r.GetSet_ArrangeView2 then
    r.GetSet_ArrangeView2(0, true, 0, 0, s, e)
  elseif r.BR_SetArrangeView then
    r.BR_SetArrangeView(0, s, e)
  end
end

local function nav_available()
  return (r.GetSet_ArrangeView2 ~= nil) or (r.BR_GetArrangeView ~= nil and r.BR_SetArrangeView ~= nil)
end

local BLOCKS = {}

BLOCKS.transport = function(ctx, app, settings, width)
  local recording = is_recording()
  local buttons = {
    { id = "to_start", paint = paint_to_start, cmd = 40042, tip = "Go to start" },
    { id = "play", paint = paint_play, cmd = 1007, tip = "Play", active = is_playing() },
    { id = "pause", paint = paint_pause, cmd = 1008, tip = "Pause", active = is_paused(), active_color = Theme.colors.warning },
    { id = "stop", paint = paint_stop, cmd = 1016, tip = "Stop" },
    { id = "record", paint = paint_record, cmd = 1013, tip = "Record", rec = true },
    { id = "to_end", paint = paint_to_end, cmd = 40043, tip = "Go to end" },
    { id = "loop", paint = paint_loop, cmd = 1068, tip = "Toggle repeat", active = repeat_on() },
  }
  -- Square buttons that justify to exactly fill the card width.
  local n = #buttons
  local min_gap = UIScale.gap(4)
  local max_size = UIScale.round(40)
  local size = math.max(UIScale.round(18), math.min(max_size, (width - (n - 1) * min_gap) / n))
  local gap = n > 1 and math.max(min_gap, (width - n * size) / (n - 1)) or 0
  for i, b in ipairs(buttons) do
    if i > 1 then r.ImGui_SameLine(ctx, 0, gap) end
    local opts
    if b.rec then
      opts = { active = recording, active_color = 0xFF3B3BFF, fg = recording and 0xFFFFFFFF or 0xFF3B3BFF, tooltip = b.tip }
    else
      opts = { active = b.active, active_color = b.active_color, tooltip = b.tip }
    end
    if glyph_button(ctx, b.id, size, opts, b.paint) then run(b.cmd) end
  end
end

BLOCKS.tempo = function(ctx, app, settings, width)
  local dl = r.ImGui_GetWindowDrawList(ctx)
  local bpm = r.Master_GetTempo and r.Master_GetTempo() or 120.0
  local ox, oy = r.ImGui_GetCursorScreenPos(ctx)
  local gap = UIScale.gap(4)
  local big_size = UIScale.round(30)
  local hero_h = big_size
  local badge_w = UIScale.round(56)
  local num, denom = project_timesig()

  if state.tempo_edit then
    -- Inline typing mode.
    local frame_h = r.ImGui_GetFrameHeight(ctx)
    r.ImGui_SetCursorScreenPos(ctx, ox, oy + math.max(0, (hero_h - frame_h) * 0.5))
    r.ImGui_SetNextItemWidth(ctx, width - badge_w - gap)
    if state.tempo_focus then r.ImGui_SetKeyboardFocusHere(ctx); state.tempo_focus = false end
    local flags = r.ImGui_InputTextFlags_EnterReturnsTrue and r.ImGui_InputTextFlags_EnterReturnsTrue() or 0
    local ch, txt = r.ImGui_InputText(ctx, "##bpm_edit", state.tempo_edit_text or "", flags)
    if ch ~= nil then state.tempo_edit_text = txt end
    local done = ch or (r.ImGui_IsItemDeactivated and r.ImGui_IsItemDeactivated(ctx))
    if done then
      local val = tonumber((tostring(state.tempo_edit_text):gsub(",", ".")))
      if val then set_bpm(val) end
      state.tempo_edit = false
    end
  else
    -- Big, draggable BPM readout.
    local bpm_str = string.format("%.2f", bpm)
    local dw = r.ImGui_CalcTextSize(ctx, bpm_str)
    local base = (r.ImGui_GetFontSize and r.ImGui_GetFontSize(ctx)) or 13
    local tw = dw * (big_size / math.max(1, base))
    local btn_w = math.max(UIScale.round(50), math.min(width - badge_w - gap, tw + UIScale.round(12)))
    r.ImGui_SetCursorScreenPos(ctx, ox, oy)
    r.ImGui_PushID(ctx, "bpm")
    r.ImGui_InvisibleButton(ctx, "##bpm", btn_w, hero_h)
    local hovered = r.ImGui_IsItemHovered(ctx)
    local active = r.ImGui_IsItemActive and r.ImGui_IsItemActive(ctx)
    r.ImGui_PopID(ctx)
    local col = (hovered or active) and Theme.colors.accent or Theme.colors.text
    local font = get_font(ctx, big_size)
    if font and r.ImGui_DrawList_AddTextEx then
      pcall(r.ImGui_DrawList_AddTextEx, dl, font, big_size, ox, oy, col, bpm_str)
    else
      r.ImGui_DrawList_AddText(dl, ox, oy + (hero_h - base) * 0.5, col, bpm_str)
    end
    local lh = r.ImGui_GetTextLineHeight(ctx)
    r.ImGui_DrawList_AddText(dl, ox + tw + UIScale.round(6), oy + hero_h - lh - UIScale.round(1), Theme.colors.text_dim, "BPM")
    if hovered and not active then r.ImGui_SetTooltip(ctx, "Drag or scroll to change, double-click to type") end
    if active and r.ImGui_GetMouseDelta then
      local _, dy = r.ImGui_GetMouseDelta(ctx)
      if dy and dy ~= 0 then set_bpm(bpm - dy * 0.1) end
    end
    if hovered and r.ImGui_GetMouseWheel then
      local wheel = r.ImGui_GetMouseWheel(ctx)
      if wheel and wheel ~= 0 then set_bpm(bpm + wheel) end
    end
    if hovered and r.ImGui_IsMouseDoubleClicked and r.ImGui_IsMouseDoubleClicked(ctx, 0) then
      state.tempo_edit = true
      state.tempo_edit_text = bpm_str
      state.tempo_focus = true
    end
  end

  -- Time signature badge (right-aligned in the hero row): horizontal "N | D",
  -- clickable to edit.
  local bx = ox + width - badge_w
  r.ImGui_SetCursorScreenPos(ctx, bx, oy)
  local sig_clicked = r.ImGui_InvisibleButton(ctx, "##timesig", badge_w, hero_h)
  local sig_hovered = r.ImGui_IsItemHovered(ctx)
  local sig_bg = sig_hovered and Theme.colors.frame_bg or Theme.colors.frame_hover
  r.ImGui_DrawList_AddRectFilled(dl, bx, oy, bx + badge_w, oy + hero_h, sig_bg, UIScale.px(4))
  r.ImGui_DrawList_AddRect(dl, bx, oy, bx + badge_w, oy + hero_h, sig_hovered and Theme.colors.accent or Theme.colors.border, UIScale.px(4), 0, UIScale.px(1))
  local sig_str = string.format("%d | %d", num, denom)
  local sw, sh = r.ImGui_CalcTextSize(ctx, sig_str)
  r.ImGui_DrawList_AddText(dl, bx + (badge_w - sw) * 0.5, oy + (hero_h - sh) * 0.5, Theme.colors.text, sig_str)
  if sig_hovered then r.ImGui_SetTooltip(ctx, "Click to set time signature") end
  if sig_clicked then
    state.sig_num, state.sig_denom = num, denom
    r.ImGui_OpenPopup(ctx, "##timesig_popup")
  end
  if r.ImGui_BeginPopup(ctx, "##timesig_popup") then
    r.ImGui_TextColored(ctx, Theme.colors.accent, "Time signature")
    r.ImGui_SetNextItemWidth(ctx, UIScale.round(120))
    local chn, vn = r.ImGui_InputInt(ctx, "Beats##sig_num", state.sig_num)
    if chn then state.sig_num = math.max(1, math.min(32, vn)) end
    r.ImGui_SetNextItemWidth(ctx, UIScale.round(120))
    if r.ImGui_BeginCombo(ctx, "Note##sig_den", tostring(state.sig_denom)) then
      for _, d in ipairs({ 1, 2, 4, 8, 16, 32 }) do
        if r.ImGui_Selectable(ctx, tostring(d), d == state.sig_denom) then state.sig_denom = d end
      end
      r.ImGui_EndCombo(ctx)
    end
    r.ImGui_Separator(ctx)
    r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Apply at")
    if r.ImGui_RadioButton(ctx, "Current measure##sig_cur", state.sig_target == "current") then state.sig_target = "current" end
    if r.ImGui_RadioButton(ctx, "Project start##sig_base", state.sig_target == "base") then state.sig_target = "base" end
    r.ImGui_Separator(ctx)
    if r.ImGui_Button(ctx, "Apply##sig_apply") then
      set_timesig(app, state.sig_num, state.sig_denom, state.sig_target == "base")
      r.ImGui_CloseCurrentPopup(ctx)
    end
    r.ImGui_EndPopup(ctx)
  end

  -- Row below: nudge / tap / nudge.
  r.ImGui_SetCursorScreenPos(ctx, ox, oy + hero_h + gap)
  local nudge_w = UIScale.round(26)
  local tap_w = math.max(UIScale.round(50), width - nudge_w * 2 - gap * 2)
  if r.ImGui_Button(ctx, "-##bpm_dn", nudge_w, 0) then set_bpm(bpm - 1) end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "-1 BPM") end
  r.ImGui_SameLine(ctx, 0, gap)
  if r.ImGui_Button(ctx, "TAP##bpm_tap", tap_w, 0) then do_tap() end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Tap tempo (tap in time)") end
  r.ImGui_SameLine(ctx, 0, gap)
  if r.ImGui_Button(ctx, "+##bpm_up", nudge_w, 0) then set_bpm(bpm + 1) end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "+1 BPM") end
end

BLOCKS.time_selection = function(ctx, app, settings, width)
  local dl = r.ImGui_GetWindowDrawList(ctx)
  local ox, oy = r.ImGui_GetCursorScreenPos(ctx)
  local gap = UIScale.gap(4)
  local big_size = UIScale.round(26)
  local hero_h = big_size
  local badge_w = UIScale.round(62)
  local lh = r.ImGui_GetTextLineHeight(ctx)

  local sel_start, sel_end = 0, 0
  if r.GetSet_LoopTimeRange then sel_start, sel_end = r.GetSet_LoopTimeRange(false, false, 0, 0, false) end
  local length = math.max(0, (sel_end or 0) - (sel_start or 0))
  local has_sel = length > 0.0000001
  local col = has_sel and Theme.colors.text or Theme.colors.text_dim

  -- Hero: big length readout.
  local len_str = has_sel and fmt_len(length) or "--:--.---"
  local font = get_font(ctx, big_size)
  if font and r.ImGui_DrawList_AddTextEx then
    pcall(r.ImGui_DrawList_AddTextEx, dl, font, big_size, ox, oy, col, len_str)
  else
    r.ImGui_DrawList_AddText(dl, ox, oy, col, len_str)
  end
  local base = (r.ImGui_GetFontSize and r.ImGui_GetFontSize(ctx)) or 13
  local tw = r.ImGui_CalcTextSize(ctx, len_str) * (big_size / math.max(1, base))
  r.ImGui_DrawList_AddText(dl, ox + tw + UIScale.round(6), oy + hero_h - lh - UIScale.round(1), Theme.colors.text_dim, "LEN")

  -- Badge: musical length in bars.beats.
  if r.format_timestr_len then
    local bx = ox + width - badge_w
    r.ImGui_DrawList_AddRectFilled(dl, bx, oy, bx + badge_w, oy + hero_h, Theme.colors.frame_hover, UIScale.px(4))
    r.ImGui_DrawList_AddRect(dl, bx, oy, bx + badge_w, oy + hero_h, Theme.colors.border, UIScale.px(4), 0, UIScale.px(1))
    local bars = has_sel and r.format_timestr_len(length, "", sel_start, 2) or "-"
    local bw2, bh2 = r.ImGui_CalcTextSize(ctx, bars)
    r.ImGui_DrawList_AddText(dl, bx + (badge_w - bw2) * 0.5, oy + (hero_h - bh2) * 0.5, col, bars)
  end

  -- Subtext: start -> end (or empty state).
  local sub_y = oy + hero_h + UIScale.round(3)
  local sub = has_sel and (fmt_pos(sel_start) .. "  ->  " .. fmt_pos(sel_end)) or "No time selection"
  r.ImGui_DrawList_AddText(dl, ox, sub_y, Theme.colors.text_dim, sub)

  -- Button row: cursor to start / end, clear.
  r.ImGui_SetCursorScreenPos(ctx, ox, sub_y + lh + gap)
  local bw = math.max(UIScale.round(40), (width - 2 * gap) / 3)
  local disabled = not has_sel
  if disabled and r.ImGui_BeginDisabled then r.ImGui_BeginDisabled(ctx) end
  if r.ImGui_Button(ctx, "|< Start##ts_start", bw, 0) then run(40630) end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Move edit cursor to selection start") end
  r.ImGui_SameLine(ctx, 0, gap)
  if r.ImGui_Button(ctx, "Clear##ts_clear", bw, 0) then run(40635) end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Remove time selection") end
  r.ImGui_SameLine(ctx, 0, gap)
  if r.ImGui_Button(ctx, "End >|##ts_end", bw, 0) then run(40631) end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Move edit cursor to selection end") end
  if disabled and r.ImGui_EndDisabled then r.ImGui_EndDisabled(ctx) end
end

BLOCKS.playrate = function(ctx, app, settings, width)
  r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Play rate")
  local rate = r.Master_GetPlayRate and r.Master_GetPlayRate(0) or 1.0
  local reset_w = UIScale.text_button_w(ctx, "1x", 34, 8)
  r.ImGui_SetNextItemWidth(ctx, math.max(UIScale.round(60), width - reset_w - UIScale.gap(4)))
  local sc = push_slider_style(ctx)
  local changed, value = r.ImGui_SliderDouble(ctx, "##transport_rate", rate, 0.25, 4.0, "%.3fx")
  pop_slider_style(ctx, sc)
  if changed and r.CSurf_OnPlayRateChange then r.CSurf_OnPlayRateChange(value) end
  if r.ImGui_IsItemClicked and r.ImGui_IsMouseDoubleClicked and r.ImGui_IsMouseDoubleClicked(ctx, 0) and r.CSurf_OnPlayRateChange then
    r.CSurf_OnPlayRateChange(1.0)
  end
  r.ImGui_SameLine(ctx, 0, UIScale.gap(4))
  if r.ImGui_Button(ctx, "1x##transport_rate_reset", reset_w, 0) and r.CSurf_OnPlayRateChange then r.CSurf_OnPlayRateChange(1.0) end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Reset play rate to 1.0") end
  local preserve = toggle_state(40671)
  local ch = r.ImGui_Checkbox(ctx, "Preserve pitch", preserve)
  if ch then run(40671) end
end

BLOCKS.metronome = function(ctx, app, settings, width)
  local dl = r.ImGui_GetWindowDrawList(ctx)
  local ox, oy = r.ImGui_GetCursorScreenPos(ctx)
  local gap = UIScale.gap(4)
  local on = toggle_state(40364)
  local size = UIScale.round(26)
  local chip_h = UIScale.round(22)
  local lh = r.ImGui_GetTextLineHeight(ctx)
  local y = oy

  -- Row 1: on/off toggle, label, and a gear that opens REAPER's metronome settings.
  r.ImGui_SetCursorScreenPos(ctx, ox, y)
  if glyph_button(ctx, "metro_toggle", size, { active = on, tooltip = on and "Metronome on" or "Metronome off" }, paint_metronome) then run(40364) end
  r.ImGui_DrawList_AddText(dl, ox + size + gap * 2, y + (size - lh) * 0.5, on and Theme.colors.accent or Theme.colors.text, "Metronome")
  r.ImGui_SetCursorScreenPos(ctx, ox + width - size, y)
  if glyph_button(ctx, "metro_settings", size, { tooltip = "Open REAPER metronome settings" }, paint_gear) then run(40363) end
  y = y + size + gap

  -- Row 2: click volume (SWS config var).
  r.ImGui_SetCursorScreenPos(ctx, ox, y)
  local vol = read_metro_vol()
  if vol then
    r.ImGui_SetNextItemWidth(ctx, width)
    local sc = push_slider_style(ctx)
    local ch, v = r.ImGui_SliderDouble(ctx, "##metro_vol", vol, 0.0, 2.0, "Volume  %.2f")
    pop_slider_style(ctx, sc)
    if ch then write_metro_vol(v) end
    if r.ImGui_IsItemHovered(ctx) and r.ImGui_IsMouseDoubleClicked and r.ImGui_IsMouseDoubleClicked(ctx, 0) then write_metro_vol(1.0) end
    y = y + r.ImGui_GetFrameHeight(ctx) + gap
  else
    r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Volume needs the SWS extension")
    y = y + lh + gap
  end

  -- Row 3: click speed presets (highlighting the active one).
  local speeds = { { l = "0.5x", c = 43703 }, { l = "1x", c = 42456 }, { l = "2x", c = 42457 }, { l = "4x", c = 42458 } }
  local sw = (width - (#speeds - 1) * gap) / #speeds
  for i, s in ipairs(speeds) do
    r.ImGui_SetCursorScreenPos(ctx, ox + (i - 1) * (sw + gap), y)
    local clicked, hovered = text_chip(ctx, "spd_" .. i, s.l, toggle_state(s.c), sw, chip_h)
    if clicked then run(s.c) end
    if hovered then r.ImGui_SetTooltip(ctx, "Click speed " .. s.l) end
  end
  y = y + chip_h + gap

  -- Row 4: metronome during playback / recording (SWS/AW toggles).
  local play_cmd = r.NamedCommandLookup and r.NamedCommandLookup("_SWS_AWMPLAYTOG") or 0
  local rec_cmd = r.NamedCommandLookup and r.NamedCommandLookup("_SWS_AWMRECTOG") or 0
  if play_cmd ~= 0 or rec_cmd ~= 0 then
    local cw = (width - gap) / 2
    r.ImGui_SetCursorScreenPos(ctx, ox, y)
    local pc, ph = text_chip(ctx, "metro_play", "Playback", play_cmd ~= 0 and toggle_state(play_cmd), cw, chip_h)
    if pc and play_cmd ~= 0 then run(play_cmd) end
    if ph then r.ImGui_SetTooltip(ctx, "Metronome during playback") end
    r.ImGui_SetCursorScreenPos(ctx, ox + cw + gap, y)
    local rc, rh = text_chip(ctx, "metro_rec", "Record", rec_cmd ~= 0 and toggle_state(rec_cmd), cw, chip_h)
    if rc and rec_cmd ~= 0 then run(rec_cmd) end
    if rh then r.ImGui_SetTooltip(ctx, "Metronome during recording") end
  end
end

BLOCKS.navigator = function(ctx, app, settings, width)
  local dl = r.ImGui_GetWindowDrawList(ctx)
  if not nav_available() then
    r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Navigator needs GetSet_ArrangeView2 (REAPER) or SWS.")
    return
  end
  local ox, oy = r.ImGui_GetCursorScreenPos(ctx)
  ox, oy = math.floor(ox), math.floor(oy)
  local w = width
  local h = UIScale.round(120)

  local map = nav_get_map()
  nav_refresh_positions(map)
  local content_len = map.len
  local vs, ve = nav_get_view()
  vs, ve = vs or 0, ve or content_len
  -- Display range: project content (or current view, whichever is larger) plus
  -- headroom, so you can zoom/scroll past the project end into empty timeline
  -- like REAPER's own navigator.
  local len = math.max(content_len, ve) * 1.25
  local ruler_h = UIScale.round(11)
  local tracks_top = oy + ruler_h
  local tracks_h = h - ruler_h
  local function t2x(t) return ox + nav_clamp(t / len, 0, 1) * w end
  local function x2t(x) return nav_clamp((x - ox) / w, 0, 1) * len end

  r.ImGui_DrawList_AddRectFilled(dl, ox, oy, ox + w, oy + h, Theme.colors.window_bg, UIScale.px(4))

  -- Tracks (flattened rows) + items.
  local ntr = #map.tracks
  local row_h = ntr > 0 and (tracks_h / ntr) or tracks_h
  for i, row in ipairs(map.tracks) do
    local ry = tracks_top + (i - 1) * row_h
    if i % 2 == 0 then r.ImGui_DrawList_AddRectFilled(dl, ox, ry, ox + w, ry + row_h, Theme.colors.child_bg) end
    local iy1 = ry + math.max(0, row_h * 0.12)
    local iy2 = ry + row_h - math.max(0, row_h * 0.12)
    for _, it in ipairs(row.items) do
      local ix1 = t2x(it.pos)
      local ix2 = math.max(ix1 + 1, t2x(it.pos + it.len))
      r.ImGui_DrawList_AddRectFilled(dl, ix1, iy1, ix2, iy2, it.color)
    end
  end

  -- Markers / regions.
  if r.CountProjectMarkers then
    local total = select(1, r.CountProjectMarkers(0)) or 0
    for idx = 0, total - 1 do
      local okm, isrgn, pos, rgnend, _, _, mcol = r.EnumProjectMarkers3(0, idx)
      if okm then
        local c = nav_color(mcol, isrgn and Theme.colors.accent_soft or Theme.colors.accent)
        if isrgn then
          r.ImGui_DrawList_AddRectFilled(dl, t2x(pos), oy, t2x(rgnend), oy + ruler_h, (c & 0xFFFFFF00) | 0x66)
        else
          local mkx = t2x(pos)
          r.ImGui_DrawList_AddLine(dl, mkx, oy, mkx, oy + ruler_h, c, UIScale.px(1))
          r.ImGui_DrawList_AddTriangleFilled(dl, mkx - UIScale.round(3), oy, mkx + UIScale.round(3), oy, mkx, oy + UIScale.round(4), c)
        end
      end
    end
    r.ImGui_DrawList_AddLine(dl, ox, tracks_top, ox + w, tracks_top, Theme.colors.border, UIScale.px(1))
  end

  -- Edit cursor + play position.
  local edit_x = t2x(r.GetCursorPosition and r.GetCursorPosition() or 0)
  r.ImGui_DrawList_AddLine(dl, edit_x, oy, edit_x, oy + h, Theme.colors.text, UIScale.px(1))
  local ps = r.GetPlayState and r.GetPlayState() or 0
  if (ps & 1) == 1 or (ps & 2) == 2 then
    local play_x = t2x(r.GetPlayPosition and r.GetPlayPosition() or 0)
    r.ImGui_DrawList_AddLine(dl, play_x, oy, play_x, oy + h, 0x39D98AFF, UIScale.px(1))
  end

  -- Viewport rectangle.
  local vx1, vx2 = t2x(vs), t2x(ve)
  local total_px, scroll_px = 0, 0
  for _, row in ipairs(map.tracks) do total_px = total_px + (row.tcph or 0) end
  if ntr > 0 then scroll_px = math.max(0, -(map.tracks[1].tcpy or 0)) end
  local ah = nav_arrange_height()
  local vy1, vy2 = tracks_top, tracks_top + tracks_h
  if ah and total_px > ah + 1 then
    vy1 = tracks_top + nav_clamp(scroll_px / total_px, 0, 1) * tracks_h
    vy2 = tracks_top + nav_clamp((scroll_px + ah) / total_px, 0, 1) * tracks_h
  end
  r.ImGui_DrawList_AddRectFilled(dl, vx1, vy1, vx2, vy2, (Theme.colors.accent & 0xFFFFFF00) | 0x22)
  r.ImGui_DrawList_AddRect(dl, vx1, vy1, vx2, vy2, Theme.colors.accent, UIScale.px(2), 0, UIScale.px(1.4))
  r.ImGui_DrawList_AddRect(dl, ox, oy, ox + w, oy + h, Theme.colors.border, UIScale.px(4), 0, UIScale.px(1))

  -- Interaction.
  r.ImGui_SetCursorScreenPos(ctx, ox, oy)
  r.ImGui_InvisibleButton(ctx, "##nav_canvas", w, h)
  local hovered = r.ImGui_IsItemHovered(ctx)
  local mx = r.ImGui_GetMousePos(ctx)
  local edge = UIScale.round(4)
  local min_dur = math.max(0.05, len * 0.002)
  local dur = math.max(min_dur, ve - vs)
  local nav = state.nav

  if r.ImGui_IsItemActivated(ctx) then
    if mx >= vx1 - edge and mx <= vx1 + edge then
      nav.drag = { mode = "l" }
    elseif mx >= vx2 - edge and mx <= vx2 + edge then
      nav.drag = { mode = "r" }
    elseif mx > vx1 and mx < vx2 then
      nav.drag = { mode = "pan", grab = x2t(mx) - vs }
    else
      local ns = nav_clamp(x2t(mx) - dur * 0.5, 0, math.max(0, len - dur))
      nav_set_view(ns, ns + dur)
      nav.drag = { mode = "pan", grab = x2t(mx) - ns }
    end
  end

  if r.ImGui_IsItemActive(ctx) and nav.drag then
    local m = nav.drag.mode
    if m == "pan" then
      local ns = nav_clamp(x2t(mx) - (nav.drag.grab or 0), 0, math.max(0, len - dur))
      nav_set_view(ns, ns + dur)
      -- Vertical pan (no js needed): scale the drag by the total/visible track
      -- height ratio and feed it to CSurf_OnScroll.
      if r.CSurf_OnScroll and r.ImGui_GetMouseDelta and total_px > 0 and tracks_h > 0 then
        local _, dy = r.ImGui_GetMouseDelta(ctx)
        if dy and dy ~= 0 then
          local amt = (dy * (total_px / tracks_h)) / 8
          amt = amt >= 0 and math.floor(amt + 0.5) or math.ceil(amt - 0.5)
          if amt ~= 0 then r.CSurf_OnScroll(0, amt) end
        end
      end
    elseif m == "l" then
      nav_set_view(nav_clamp(x2t(mx), 0, ve - min_dur), ve)
    elseif m == "r" then
      nav_set_view(vs, nav_clamp(x2t(mx), vs + min_dur, len))
    end
  end

  if r.ImGui_IsItemDeactivated(ctx) then nav.drag = nil end

  if hovered and r.ImGui_GetMouseWheel then
    local wheel = r.ImGui_GetMouseWheel(ctx)
    if wheel and wheel ~= 0 then
      local ctrl = false
      if r.ImGui_GetKeyMods and r.ImGui_Mod_Ctrl then
        local mods = r.ImGui_GetKeyMods(ctx)
        ctrl = type(mods) == "number" and (mods & r.ImGui_Mod_Ctrl()) ~= 0
      end
      if ctrl and r.CSurf_OnZoom then
        r.CSurf_OnZoom(0, wheel > 0 and 2 or -2) -- vertical zoom (track heights)
      else
        local center = x2t(mx)
        local factor = wheel > 0 and 0.82 or 1.22
        local ndur = nav_clamp(dur * factor, min_dur, len)
        local ns = nav_clamp(center - (center - vs) * (ndur / dur), 0, math.max(0, len - ndur))
        nav_set_view(ns, ns + ndur)
      end
    end
  end

  if hovered and not nav.drag then
    r.ImGui_SetTooltip(ctx, "Drag = pan (x/y), edges = zoom time, wheel = zoom time, Ctrl+wheel = zoom tracks")
  end
end

BLOCKS.master_peak = function(ctx, app, settings, width)
  local dl = r.ImGui_GetWindowDrawList(ctx)
  local ox, oy = r.ImGui_GetCursorScreenPos(ctx)
  ox, oy = math.floor(ox), math.floor(oy)
  local w = math.max(UIScale.round(40), width)
  local h = UIScale.round(70)
  local scope = state.scope

  -- Push one sample per frame: the master peak while rolling, silence otherwise
  -- (so the waveform keeps scrolling out of view after stop). A fresh start clears
  -- the buffer so the scope restarts from empty.
  local ps = r.GetPlayState and r.GetPlayState() or 0
  local rolling = (ps & 1) == 1 or (ps & 4) == 4
  if rolling and not scope.was_rolling then
    for i = 1, scope.size do scope.buf[i] = 0 end
    scope.head = 1
  end
  scope.was_rolling = rolling
  local val = 0
  if rolling and r.GetMasterTrack and r.Track_GetPeakInfo then
    local m = r.GetMasterTrack(0)
    val = math.max(r.Track_GetPeakInfo(m, 0) or 0, r.Track_GetPeakInfo(m, 1) or 0)
  end
  scope.buf[scope.head] = val
  scope.head = (scope.head % scope.size) + 1

  r.ImGui_DrawList_AddRectFilled(dl, ox, oy, ox + w, oy + h, Theme.colors.window_bg, UIScale.px(4))
  local cy = oy + h * 0.5
  r.ImGui_DrawList_AddLine(dl, ox, cy, ox + w, cy, (Theme.colors.border & 0xFFFFFF00) | 0x99, UIScale.px(1))

  -- Scrolling waveform: newest sample at the right edge. Each sample is drawn a
  -- few pixels wide so one push per frame scrolls faster (and shows less history).
  local newest = scope.head - 1
  if newest < 1 then newest = newest + scope.size end
  local halfmax = h * 0.5 - UIScale.round(2)
  local danger = Theme.colors.danger or 0xFF3B3BFF
  local step = math.max(1, UIScale.round(3))
  local cols = math.ceil(w / step)
  for c = 0, cols - 1 do
    local idx = ((newest - c - 1) % scope.size) + 1
    local val = scope.buf[idx] or 0
    local disp = math.sqrt(nav_clamp(val, 0, 1))
    local half = disp * halfmax
    if half > 0.5 then
      local x2 = ox + w - c * step
      local x1 = math.max(ox, x2 - step)
      local col = val >= 0.985 and danger or Theme.colors.accent
      r.ImGui_DrawList_AddRectFilled(dl, x1, cy - half, x2, cy + half, col)
    end
  end

  r.ImGui_DrawList_AddRect(dl, ox, oy, ox + w, oy + h, Theme.colors.border, UIScale.px(4), 0, UIScale.px(1))

  -- Establish the block's height for the card layout.
  r.ImGui_SetCursorScreenPos(ctx, ox, oy)
  r.ImGui_InvisibleButton(ctx, "##master_peak", w, h)
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Master output peaks (scrolls during playback)") end
end

-- ---------------------------------------------------------------------------
-- Settings popup (block composition)
-- ---------------------------------------------------------------------------
local function draw_settings_popup(ctx, app, settings)
  if not r.ImGui_BeginPopup(ctx, "##transport_settings_popup") then return end
  r.ImGui_TextColored(ctx, Theme.colors.accent, "Transport blocks")
  r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Drag the grip on a card to reorder, or use Up / Dn.")
  r.ImGui_Separator(ctx)
  for i, id in ipairs(settings.blocks) do
    r.ImGui_PushID(ctx, "blk_" .. id)
    if r.ImGui_SmallButton(ctx, "Up") then move_block(app, settings, i, -1) end
    r.ImGui_SameLine(ctx, 0, UIScale.gap(3))
    if r.ImGui_SmallButton(ctx, "Dn") then move_block(app, settings, i, 1) end
    r.ImGui_SameLine(ctx, 0, UIScale.gap(6))
    r.ImGui_AlignTextToFramePadding(ctx)
    r.ImGui_Text(ctx, block_title(id))
    r.ImGui_SameLine(ctx)
    local rw = UIScale.text_button_w(ctx, "Remove", 60, 8)
    local availx = r.ImGui_GetContentRegionAvail(ctx)
    if availx > rw then r.ImGui_SetCursorPosX(ctx, r.ImGui_GetCursorPosX(ctx) + (availx - rw)) end
    if r.ImGui_SmallButton(ctx, "Remove") then remove_block(app, settings, id) end
    r.ImGui_PopID(ctx)
  end
  local any_disabled = false
  for _, b in ipairs(AVAILABLE) do if not block_enabled(settings, b.id) then any_disabled = true end end
  if any_disabled then
    r.ImGui_Separator(ctx)
    r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Add block")
    for _, b in ipairs(AVAILABLE) do
      if not block_enabled(settings, b.id) then
        if r.ImGui_SmallButton(ctx, "+ " .. b.title .. "##add_" .. b.id) then add_block(app, settings, b.id) end
      end
    end
  end
  r.ImGui_Separator(ctx)
  r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Layout")
  local at_bottom = settings.anchor == "bottom"
  local changed, value = r.ImGui_Checkbox(ctx, "Anchor stack to window bottom", at_bottom)
  if changed then
    settings.anchor = value and "bottom" or "top"
    app.status = value and "Transport: anchored to bottom" or "Transport: anchored to top"
    save(app)
  end
  r.ImGui_EndPopup(ctx)
end

-- A slim grab strip at the top of each card: drag it to reorder (drag source),
-- and it doubles as the drop target for its card.
local function draw_grab_handle(ctx, dl, id, inner_w)
  local hh = UIScale.round(11)
  r.ImGui_PushID(ctx, "grab_" .. id)
  local hx, hy = r.ImGui_GetCursorScreenPos(ctx)
  r.ImGui_InvisibleButton(ctx, "##grab", inner_w, hh)
  local hovered = r.ImGui_IsItemHovered(ctx)
  local active = r.ImGui_IsItemActive and r.ImGui_IsItemActive(ctx)
  local dot_col = (hovered or active) and Theme.colors.accent or Theme.colors.text_dim
  local gx = hx + UIScale.round(3)
  local gy = hy + hh * 0.5
  for coln = 0, 2 do
    for row = -1, 1 do
      r.ImGui_DrawList_AddCircleFilled(dl, gx + coln * UIScale.round(4), gy + row * UIScale.round(3), UIScale.px(1.2), dot_col, 6)
    end
  end
  if hovered and not active then r.ImGui_SetTooltip(ctx, "Drag to reorder") end
  if r.ImGui_BeginDragDropSource and r.ImGui_BeginDragDropSource(ctx) then
    r.ImGui_SetDragDropPayload(ctx, BLOCK_PAYLOAD, id)
    r.ImGui_Text(ctx, block_title(id))
    r.ImGui_EndDragDropSource(ctx)
  end
  if r.ImGui_BeginDragDropTarget and r.ImGui_BeginDragDropTarget(ctx) then
    local ok, payload = r.ImGui_AcceptDragDropPayload(ctx, BLOCK_PAYLOAD)
    if ok and payload and payload ~= id then state.pending_reorder = { source = payload, target = id } end
    r.ImGui_EndDragDropTarget(ctx)
  end
  r.ImGui_PopID(ctx)
end

-- ---------------------------------------------------------------------------
-- Card wrapper: every block sits in a full-width framed card. Drawn manually on
-- the window draw list so the width is hard-pinned to the Workbench child width
-- (no child window / AutoResize, which mis-sized the width).
-- ---------------------------------------------------------------------------
local function draw_block_card(ctx, app, settings, id)
  local block = BLOCKS[id]
  if not block then return end
  local dl = r.ImGui_GetWindowDrawList(ctx)
  local x0, y0 = r.ImGui_GetCursorScreenPos(ctx)
  -- Snap to whole pixels: fractional positions make the measured height jitter by
  -- 1px per frame, which (with the bottom anchor) feeds back into a shaking stack.
  x0 = math.floor(x0)
  y0 = math.floor(y0)
  local w = math.max(UIScale.round(60), (r.ImGui_GetContentRegionAvail(ctx)))
  local pad = UIScale.round(8)
  -- Background uses the previous frame's height (one-frame lag, imperceptible);
  -- the border below is drawn at the exact height measured this frame.
  local cached_h = state.card_heights[id] or UIScale.round(48)
  r.ImGui_DrawList_AddRectFilled(dl, x0, y0, x0 + w, y0 + cached_h, Theme.colors.frame_bg, UIScale.px(6))
  -- Content: offset by padding, constrained to the pinned inner width.
  r.ImGui_SetCursorScreenPos(ctx, x0 + pad, y0 + pad)
  r.ImGui_BeginGroup(ctx)
  local inner_w = w - pad * 2
  draw_grab_handle(ctx, dl, id, inner_w)
  -- Guard the block so a runtime error can't leave the group open (which would
  -- surface later as "ImGui_EndChild: Missing EndGroup()").
  local ok, err = pcall(block, ctx, app, settings, inner_w)
  if not ok then
    r.ImGui_TextColored(ctx, Theme.colors.danger or Theme.colors.warning, "Block error: " .. tostring(err))
  end
  r.ImGui_EndGroup(ctx)
  local _, gy2 = r.ImGui_GetItemRectMax(ctx)
  local h = math.ceil((gy2 - y0) + pad)
  state.card_heights[id] = h
  r.ImGui_DrawList_AddRect(dl, x0, y0, x0 + w, y0 + h, Theme.colors.border, UIScale.px(6), 0, UIScale.px(1))
  -- Advance the cursor below the card with a plain move (no Dummy, so ImGui does
  -- not add ItemSpacing that would inflate the real stack height per card and
  -- throw off the bottom-anchor estimate).
  r.ImGui_SetCursorScreenPos(ctx, x0, y0 + h + UIScale.gap(3))
end

function M.draw(app)
  local ctx = app.ctx
  local settings = ensure_settings(app)
  local avail_w = r.ImGui_GetContentRegionAvail(ctx)
  local width = math.max(UIScale.round(140), avail_w or UIScale.round(280))

  -- Header row: right-aligned block-settings button.
  local btn_w = UIScale.text_button_w(ctx, "Blocks", 0, 4)
  if width > btn_w then r.ImGui_SetCursorPosX(ctx, r.ImGui_GetCursorPosX(ctx) + (width - btn_w)) end
  if r.ImGui_SmallButton(ctx, "Blocks##transport_settings") then r.ImGui_OpenPopup(ctx, "##transport_settings_popup") end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Add, remove or reorder transport blocks") end
  draw_settings_popup(ctx, app, settings)
  r.ImGui_Separator(ctx)
  r.ImGui_Dummy(ctx, 1, UIScale.gap(3))

  if #settings.blocks == 0 then
    r.ImGui_TextColored(ctx, Theme.colors.text_dim, "No blocks. Use \"Blocks\" to add some.")
    return
  end

  -- Bottom anchor: push the stack down so the last card sits at the window bottom.
  -- A small margin keeps the last card fully visible (the module canvas does not
  -- scroll, so any overflow would clip the bottom card).
  if settings.anchor == "bottom" then
    local _, avail_h = r.ImGui_GetContentRegionAvail(ctx)
    local total = 0
    for _, id in ipairs(settings.blocks) do
      total = total + (state.card_heights[id] or UIScale.round(48)) + UIScale.gap(3)
    end
    local spacer = math.floor((avail_h or 0) - total - UIScale.gap(4))
    if spacer > 0 then r.ImGui_SetCursorPosY(ctx, r.ImGui_GetCursorPosY(ctx) + spacer) end
  end

  state.pending_reorder = nil
  for _, id in ipairs(settings.blocks) do
    draw_block_card(ctx, app, settings, id)
  end
  if state.pending_reorder then
    reorder_block(app, settings, state.pending_reorder.source, state.pending_reorder.target)
    state.pending_reorder = nil
  end
  -- Cards advance the cursor with SetCursorScreenPos and submit no trailing item;
  -- a final Dummy grows the window/child boundary so EndChild (e.g. in a split
  -- pane) does not assert.
  r.ImGui_Dummy(ctx, 1, 1)
end

return M
