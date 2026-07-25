local r = reaper
local Theme = require("core.theme")
local UI = require("core.ui")
local UIScale = require("core.ui_scale")

-- Optional: the marker strip offers Color Studio's active palette when colouring
-- a marker or region. Soft dependency, so Transport keeps working without it.
local cs_ok, ColorStudio = pcall(require, "modules.color_studio")
if not cs_ok then ColorStudio = nil end

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
  { id = "markers", title = "Markers & regions" },
  { id = "record_status", title = "Record status" },
  { id = "preroll", title = "Pre-roll / count-in" },
  { id = "master_peak", title = "Master scope" },
}

local defaults = {
  blocks = { "transport", "tempo", "time_selection", "playrate", "metronome", "navigator", "markers", "record_status", "preroll", "master_peak" },
  button_style = "classic",
  anchor = "top", -- "top" = stack from the top, "bottom" = pin the stack to the window bottom
  markers_filter = "all", -- "all" | "markers" | "regions"
}

local BLOCK_PAYLOAD = "TRANSPORT_BLOCK"

-- Pinned to the anchored edge, outside the scrolling stack: the transport
-- buttons are the one thing that has to stay reachable at any window height.
local PINNED_BLOCK = "transport"

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
  cursor = { list = {}, index = 0, recorded = nil, pending = nil, pending_at = 0, proj = nil },
  rec = { start = nil, last = 0, was = false },
  markers = { list = nil, change = -1, last_build = nil, ctx_item = nil, open_ctx = false, rename_text = "", focus_rename = false, color_value = nil, color_dirty = false },
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
  if settings.markers_filter ~= "markers" and settings.markers_filter ~= "regions" then settings.markers_filter = "all" end
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
-- Whatever the user is looking at: the play cursor while rolling, the edit cursor
-- otherwise. Shared by the marker strip and the metronome pattern row.
local function focus_time()
  local ps = r.GetPlayState and r.GetPlayState() or 0
  if ((ps & 1) == 1 or (ps & 4) == 4) and r.GetPlayPosition then return r.GetPlayPosition() end
  return r.GetCursorPosition and r.GetCursorPosition() or 0
end
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

-- Metronome click pattern: one character per beat of the measure, "1" for an
-- accented beat and "2" for the rest. TimeMap_GetMetronomePattern both reads and
-- writes -- handing it "SET:<pattern>" applies a new one. The pattern belongs to
-- the time signature at a position, so it is read at the edit cursor.
-- The pattern editor's alphabet: A to D are the four click sounds (each with its
-- own pitch in REAPER's metronome settings) and "." is a muted beat. The 1/2/0
-- form the API returns by default is a lossy read-only summary -- handing it back
-- to SET is not a valid pattern, and REAPER answers that by muting every beat.
local METRO_BEAT_STATES = { "A", "B", "C", "D", "." }

-- SET has a side effect: it stores the pattern on a tempo/time signature marker
-- at that position, creating one if the project had none, and switches on that
-- marker's "new metronome pattern here" bit (8). That bit pins the pattern -- with
-- it set, REAPER's own metronome settings can no longer change it. Clearing it
-- again keeps the pattern and hands control back, so every write below ends with
-- that cleanup, and only on markers that did not already carry the bit: a pattern
-- change the user placed at a marker on purpose has to stay.
local METRO_PATTERN_WRITABLE = true
local METRO_MARKER_BIT = 8

local function metro_marker_state()
  local list = {}
  if not r.GetSetTempoTimeSigMarkerFlag or not r.CountTempoTimeSigMarkers or not r.GetTempoTimeSigMarker then
    return list
  end
  for i = 0, (r.CountTempoTimeSigMarkers(0) or 0) - 1 do
    local got_pos, _, timepos = pcall(r.GetTempoTimeSigMarker, 0, i)
    local got_flag, flag = pcall(r.GetSetTempoTimeSigMarkerFlag, 0, i, 0, false)
    if got_pos and got_flag and type(timepos) == "number" and type(flag) == "number" then
      list[#list + 1] = { pos = timepos, flag = flag }
    end
  end
  return list
end

-- Undo the pinning our own write introduced. Markers are matched by position
-- rather than index, because creating one at the start renumbers the rest.
local function metro_release_new_overrides(before)
  if not r.GetSetTempoTimeSigMarkerFlag then return end
  for _, marker in ipairs(metro_marker_state()) do
    if marker.flag & METRO_MARKER_BIT ~= 0 then
      local pinned_before = false
      for _, old in ipairs(before) do
        if math.abs(old.pos - marker.pos) < 0.000001 and old.flag & METRO_MARKER_BIT ~= 0 then
          pinned_before = true
          break
        end
      end
      if not pinned_before then
        for i = 0, (r.CountTempoTimeSigMarkers(0) or 0) - 1 do
          local got_pos, _, timepos = pcall(r.GetTempoTimeSigMarker, 0, i)
          if got_pos and type(timepos) == "number" and math.abs(timepos - marker.pos) < 0.000001 then
            pcall(r.GetSetTempoTimeSigMarkerFlag, 0, i, marker.flag & ~METRO_MARKER_BIT, true)
            break
          end
        end
      end
    end
  end
end

-- A pattern hangs off a tempo / time signature marker, so the spot to read and
-- write is the marker governing the cursor -- the last one at or before it -- and
-- the project start when there is none. Editing a 5/4 section then changes that
-- marker's pattern instead of scattering new markers through the tempo map.
-- While the transport rolls the play position leads, so the row shows the meter
-- you are actually hearing.
-- Returns that position, plus whether the marker there carries a pattern of its
-- own (bit 8) instead of inheriting the project-wide one. REAPER's metronome
-- settings only ever show the project-wide pattern, so knowing which of the two
-- you are looking at is worth surfacing.
local function metro_pattern_source()
  local pos = focus_time()
  local governing, override = 0, false
  if r.CountTempoTimeSigMarkers and r.GetTempoTimeSigMarker then
    for i = 0, (r.CountTempoTimeSigMarkers(0) or 0) - 1 do
      local ok, _, timepos = pcall(r.GetTempoTimeSigMarker, 0, i)
      if ok and type(timepos) == "number" and timepos <= pos + 0.000001 and timepos >= governing then
        governing = timepos
        override = false
        if r.GetSetTempoTimeSigMarkerFlag then
          local got, flag = pcall(r.GetSetTempoTimeSigMarkerFlag, 0, i, 0, false)
          override = got and type(flag) == "number" and flag & METRO_MARKER_BIT ~= 0
        end
      end
    end
  end
  return governing, override
end

local function metro_read_pattern()
  if not r.TimeMap_GetMetronomePattern then return nil end
  local pos = metro_pattern_source()
  local ok, _, pattern = pcall(r.TimeMap_GetMetronomePattern, 0, pos, "EXTENDED")
  if ok and type(pattern) == "string" and pattern ~= "" and pattern:match("^[A-D%.]+$") then
    return pattern
  end
  return nil
end

-- Writes, releases the pin, then reads back. A pattern REAPER did not accept
-- comes back as all muted, so anything other than exactly what was asked for is
-- rolled straight back: one bad write can never leave the project without a click.
local function metro_set_pattern(pattern)
  if not METRO_PATTERN_WRITABLE then return false end
  if not r.TimeMap_GetMetronomePattern then return false end
  local pos = metro_pattern_source()
  local previous = metro_read_pattern()
  local before = metro_marker_state()
  -- Bit 8 on a marker *is* the pattern change, so it only gets released at the
  -- project start, where the pattern survives without it and REAPER's own
  -- metronome settings stay in charge of the project-wide pattern. Further along
  -- an override is the whole point, and clearing it would throw the edit away.
  local at_project_start = pos <= 0.000001
  if r.Undo_BeginBlock then r.Undo_BeginBlock() end
  pcall(r.TimeMap_GetMetronomePattern, 0, pos, "SET:" .. pattern)
  if at_project_start then metro_release_new_overrides(before) end
  local landed = metro_read_pattern() == pattern
  if not landed and previous then
    pcall(r.TimeMap_GetMetronomePattern, 0, pos, "SET:" .. previous)
    if at_project_start then metro_release_new_overrides(before) end
  end
  if r.Undo_EndBlock then r.Undo_EndBlock("Transport: metronome click pattern", -1) end
  if r.UpdateTimeline then r.UpdateTimeline() end
  return landed
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
-- Edit cursor history
-- ---------------------------------------------------------------------------
-- REAPER keeps no history of its own, so the cursor is sampled here. Only
-- deliberate jumps are kept: a move has to clear CURSOR_MIN_JUMP and then sit
-- still for CURSOR_SETTLE, otherwise dragging the cursor or nudging it with the
-- arrow keys would push every position in between onto the list.
local CURSOR_MIN_JUMP = 0.25 -- seconds of timeline
local CURSOR_SETTLE = 0.35   -- seconds of standing still
local CURSOR_MAX = 32

local function cursor_push(pos)
  local cur = state.cursor
  -- Everything ahead of where we stand is dropped, exactly like a browser.
  for i = #cur.list, cur.index + 1, -1 do table.remove(cur.list, i) end
  cur.list[#cur.list + 1] = pos
  while #cur.list > CURSOR_MAX do table.remove(cur.list, 1) end
  cur.index = #cur.list
  cur.recorded = pos
end

-- Jump to a stored position without the sampler recording that jump again.
local function cursor_go(index)
  local cur = state.cursor
  local pos = cur.list[index]
  if not pos then return false end
  cur.index = index
  cur.recorded = pos
  cur.pending = nil
  if r.SetEditCurPos then r.SetEditCurPos(pos, true, true) end
  return true
end

local function cursor_sample()
  local cur = state.cursor
  -- Positions from another project mean nothing here.
  local proj = r.EnumProjects and r.EnumProjects(-1, "") or nil
  if proj ~= cur.proj then
    cur.proj, cur.list, cur.index, cur.recorded, cur.pending = proj, {}, 0, nil, nil
  end
  -- While rolling the edit cursor either sits still or trails the transport;
  -- either way it is not the user choosing a spot.
  if is_playing() or is_recording() then return end
  local pos = r.GetCursorPosition and r.GetCursorPosition() or 0
  if cur.recorded == nil then
    cursor_push(pos)
    return
  end
  if math.abs(pos - cur.recorded) < CURSOR_MIN_JUMP then
    cur.pending = nil
    return
  end
  local now = os.clock()
  if cur.pending == nil or math.abs(pos - cur.pending) > 0.0000001 then
    cur.pending = pos
    cur.pending_at = now
  elseif (now - cur.pending_at) >= CURSOR_SETTLE then
    cursor_push(pos)
    cur.pending = nil
  end
end

-- ---------------------------------------------------------------------------
-- Drawing helpers
-- ---------------------------------------------------------------------------
-- A vector icon button drawn on the window draw list. paint(dl, cx, cy, s, col)
-- receives the centre and a half-extent s. Returns true on left click.
-- opts.width widens the hit box beyond the square default (the glyph stays
-- centred), so a glyph can line up with a row of wider text chips.
local function glyph_button(ctx, id, size, opts, paint)
  opts = opts or {}
  r.ImGui_PushID(ctx, id)
  local clicked = r.ImGui_InvisibleButton(ctx, "##glyph", opts.width or size, size)
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
-- Curved jump arrows for the cursor history, deliberately unlike the flat
-- |< and >| of go-to-start / go-to-end.
local function paint_history(dl, cx, cy, s, col, forward)
  local rad = s * 0.8
  local ay = cy - s * 0.1
  if r.ImGui_DrawList_PathArcTo and r.ImGui_DrawList_PathStroke then
    r.ImGui_DrawList_PathArcTo(dl, cx, ay, rad, math.pi, math.pi * 2, 16)
    r.ImGui_DrawList_PathStroke(dl, col, 0, UIScale.px(1.6))
  else
    r.ImGui_DrawList_AddLine(dl, cx - rad, ay, cx + rad, ay, col, UIScale.px(1.6))
  end
  local ex = forward and (cx + rad) or (cx - rad)
  local a = s * 0.45
  r.ImGui_DrawList_AddTriangleFilled(dl, ex - a, ay, ex + a, ay, ex, ay + a * 1.7, col)
end

local function paint_history_back(dl, cx, cy, s, col) paint_history(dl, cx, cy, s, col, false) end
local function paint_history_fwd(dl, cx, cy, s, col) paint_history(dl, cx, cy, s, col, true) end

-- Stacked bars, reading as the lanes of the ruler.
local function paint_ruler_lanes(dl, cx, cy, s, col)
  local th = math.max(UIScale.px(1), s * 0.24)
  for row = -1, 1 do
    local y = cy + row * s * 0.72
    r.ImGui_DrawList_AddRectFilled(dl, cx - s, y - th, cx + s, y + th, col)
  end
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

-- ---------------------------------------------------------------------------
-- Navigator zoom presets: a fit-project button plus three save/recall slots.
-- Slots live in project ext-state (zoom positions only make sense within the
-- project they were saved in) and keep the arrange time range, per-track
-- heights (keyed by GUID, so track reordering doesn't break them) and the
-- vertical scroll offset.
-- ---------------------------------------------------------------------------
local ZOOM_EXT_SECTION = "TK_WORKBENCH_TRANSPORT"

local function zoom_slot_key(i) return "zoom_slot_" .. i end

local function zoom_slot_exists(i)
  if not r.GetProjExtState then return false end
  local _, blob = r.GetProjExtState(0, ZOOM_EXT_SECTION, zoom_slot_key(i))
  return blob ~= nil and blob ~= ""
end

-- Vertical scroll offset in pixels (how far the top of track 1 sits above the
-- arrange top). CSurf_OnScroll moves in 8px steps, hence the /8 when applying.
local function zoom_vscroll()
  local tr = r.GetTrack(0, 0)
  if not tr then return 0 end
  return -(r.GetMediaTrackInfo_Value(tr, "I_TCPY") or 0)
end

local function zoom_scroll_to(target)
  if not r.CSurf_OnScroll then return end
  local amt = (target - zoom_vscroll()) / 8
  amt = amt >= 0 and math.floor(amt + 0.5) or math.ceil(amt - 0.5)
  if amt ~= 0 then r.CSurf_OnScroll(0, amt) end
end

local function zoom_slot_save(i)
  if not r.SetProjExtState then return false end
  local vs, ve = nav_get_view()
  if not vs then return false end
  local parts = {}
  for t = 0, r.CountTracks(0) - 1 do
    local tr = r.GetTrack(0, t)
    local guid = r.GetTrackGUID and r.GetTrackGUID(tr)
    if guid then
      parts[#parts + 1] = guid .. "=" .. math.floor(r.GetMediaTrackInfo_Value(tr, "I_TCPH") or 0)
    end
  end
  local blob = string.format("%.9f;%.9f;%d|%s", vs, ve, math.floor(zoom_vscroll()), table.concat(parts, ","))
  r.SetProjExtState(0, ZOOM_EXT_SECTION, zoom_slot_key(i), blob)
  return true
end

local function zoom_slot_recall(i)
  if not r.GetProjExtState then return false end
  local _, blob = r.GetProjExtState(0, ZOOM_EXT_SECTION, zoom_slot_key(i))
  if not blob or blob == "" then return false end
  local head, tracks_str = blob:match("^([^|]*)|(.*)$")
  if not head then head, tracks_str = blob, "" end
  local vs, ve, scroll = head:match("^([-%.%d]+);([-%.%d]+);([-%d]+)$")
  vs, ve, scroll = tonumber(vs), tonumber(ve), tonumber(scroll) or 0
  local heights = {}
  for guid, hgt in tracks_str:gmatch("([^=,]+)=([-%d]+)") do heights[guid] = tonumber(hgt) end
  if r.Undo_BeginBlock then r.Undo_BeginBlock() end
  for t = 0, r.CountTracks(0) - 1 do
    local tr = r.GetTrack(0, t)
    local guid = r.GetTrackGUID and r.GetTrackGUID(tr)
    local hgt = guid and heights[guid]
    if hgt and hgt > 0 then r.SetMediaTrackInfo_Value(tr, "I_HEIGHTOVERRIDE", hgt) end
  end
  if r.TrackList_AdjustWindows then r.TrackList_AdjustWindows(false) end
  if vs and ve and ve > vs then nav_set_view(vs, ve) end
  zoom_scroll_to(scroll)
  if r.UpdateArrange then r.UpdateArrange() end
  if r.Undo_EndBlock then r.Undo_EndBlock("Transport: recall zoom slot " .. i, -1) end
  return true
end

-- Fit the whole project: full time range horizontally, and all TCP-visible
-- tracks squeezed into the arrange height vertically (REAPER clamps each track
-- at its theme minimum, so with many tracks this gets as close as it can).
-- The vertical part needs js_ReaScriptAPI for the arrange height; without it
-- only the horizontal fit happens.
local function zoom_fit_project()
  local plen = r.GetProjectLength and r.GetProjectLength(0) or 0
  if r.Undo_BeginBlock then r.Undo_BeginBlock() end
  nav_set_view(0, math.max(1.0, plen) * 1.03)
  local ah = nav_arrange_height()
  local vis = {}
  for t = 0, r.CountTracks(0) - 1 do
    local tr = r.GetTrack(0, t)
    local shown = true
    if r.IsTrackVisible then shown = r.IsTrackVisible(tr, false) end
    if shown then vis[#vis + 1] = tr end
  end
  if ah and ah > 0 and #vis > 0 then
    local hgt = math.max(1, math.floor(ah / #vis))
    for _, tr in ipairs(vis) do r.SetMediaTrackInfo_Value(tr, "I_HEIGHTOVERRIDE", hgt) end
    if r.TrackList_AdjustWindows then r.TrackList_AdjustWindows(false) end
  end
  zoom_scroll_to(0)
  if r.UpdateArrange then r.UpdateArrange() end
  if r.Undo_EndBlock then r.Undo_EndBlock("Transport: zoom to whole project", -1) end
end

-- ---------------------------------------------------------------------------
-- Marker / region strip helpers
-- ---------------------------------------------------------------------------
local MK_MAX_ROWS = 3 -- rows of chips shown before the strip starts scrolling

-- Trim to fit, stepping back over UTF-8 continuation bytes so a multi-byte
-- character never gets cut in half.
local function mk_fit(ctx, text, max_w)
  text = tostring(text or "")
  if max_w <= 0 then return "" end
  if r.ImGui_CalcTextSize(ctx, text) <= max_w then return text end
  while #text > 1 and r.ImGui_CalcTextSize(ctx, text .. "..") > max_w do
    local cut = #text
    while cut > 1 and text:byte(cut) >= 0x80 and text:byte(cut) < 0xC0 do cut = cut - 1 end
    text = text:sub(1, cut - 1)
  end
  return text .. ".."
end

local function mk_build_list()
  local items = {}
  local _, nmark, nrgn = r.CountProjectMarkers(0)
  local total = (nmark or 0) + (nrgn or 0)
  for i = 0, total - 1 do
    local ok, isrgn, pos, rgnend, name, num, col = r.EnumProjectMarkers3(0, i)
    if ok and ok ~= 0 then
      items[#items + 1] = {
        idx = i,
        is_region = isrgn and true or false,
        pos = pos or 0,
        rgn_end = rgnend or 0,
        name = tostring(name or ""),
        num = math.floor(num or 0),
        color = col or 0,
      }
    end
  end
  return items
end

-- Cached like the navigator map: rebuild when the project state changes, but
-- never more than five times a second.
local function mk_get_list()
  local mk = state.markers
  local change = r.GetProjectStateChangeCount and r.GetProjectStateChangeCount(0) or 0
  if mk.list and change == mk.change then return mk.list end
  local now = os.clock()
  if mk.list and mk.last_build and (now - mk.last_build) < 0.2 then return mk.list end
  mk.list = mk_build_list()
  mk.change = change
  mk.last_build = now
  return mk.list
end

local function mk_label(item)
  local name = item.name:gsub("%s+", " "):match("^%s*(.-)%s*$")
  if name ~= "" then return name end
  return (item.is_region and "R" or "M") .. item.num
end

local function mk_goto(item)
  if r.SetEditCurPos then r.SetEditCurPos(item.pos, true, true) end
end

local function mk_set_time_selection(item)
  if r.GetSet_LoopTimeRange then r.GetSet_LoopTimeRange(true, false, item.pos, item.rgn_end, false) end
end

-- Loop a region: time selection + loop points on the region, repeat on, and roll
-- from its start.
local function mk_loop(item)
  mk_set_time_selection(item)
  if r.GetSet_LoopTimeRange then r.GetSet_LoopTimeRange(true, true, item.pos, item.rgn_end, false) end
  if r.GetSetRepeat and not repeat_on() then r.GetSetRepeat(1) end
  mk_goto(item)
  if not is_playing() then run(1007) end
end

-- Force the next mk_get_list to rebuild (used right after we change something
-- ourselves, so the strip does not lag a frame or two behind).
local function mk_invalidate()
  state.markers.change = -1
  state.markers.last_build = nil
end

-- 0xRRGGBBAA (the palette/theme format) to REAPER's native colour, with the
-- custom-colour flag set so the marker actually uses it.
local function mk_u32_to_native(color)
  if not color or not r.ColorToNative then return 0 end
  return ((r.ColorToNative((color >> 24) & 0xFF, (color >> 16) & 0xFF, (color >> 8) & 0xFF)) or 0) | 0x1000000
end

-- REAPER has no partial setter for markers: every SetProjectMarker call rewrites
-- the name and the colour together, so both go through here. A nil undo_label
-- writes without an undo point (used for the live colour preview while dragging).
local function mk_apply(item, name, native, undo_label)
  if undo_label and r.Undo_BeginBlock then r.Undo_BeginBlock() end
  if r.SetProjectMarker4 then
    -- flag 1 clears the name (an empty string alone leaves it unchanged)
    r.SetProjectMarker4(0, item.num, item.is_region, item.pos, item.rgn_end, name, native, name == "" and 1 or 0)
  elseif r.SetProjectMarker3 then
    r.SetProjectMarker3(0, item.num, item.is_region, item.pos, item.rgn_end, name, native)
  end
  item.name = name
  item.color = native
  if undo_label and r.Undo_EndBlock then r.Undo_EndBlock(undo_label, -1) end
  if r.UpdateArrange then r.UpdateArrange() end
  mk_invalidate()
end

local function mk_rename(item, name)
  mk_apply(item, name, item.color, "Transport: rename " .. (item.is_region and "region" or "marker"))
end

local function mk_color_undo_label(item)
  return "Transport: colour " .. (item.is_region and "region" or "marker")
end

-- color = nil resets the marker/region to REAPER's default colour.
local function mk_set_color(item, color, undo_label)
  mk_apply(item, item.name, color and mk_u32_to_native(color) or 0, undo_label)
end

-- The picker writes live so you see the colour on the marker while dragging, but
-- without undo points; the single undo point is created once the popup closes.
local function mk_commit_color(app)
  local mk = state.markers
  if not mk.color_dirty then return end
  mk.color_dirty = false
  local item = mk.ctx_item
  if not item then return end
  mk_set_color(item, mk.color_value, mk_color_undo_label(item))
  if app then app.status = "Transport: coloured " .. (item.is_region and "region" or "marker") .. " " .. item.num end
end

-- Color Studio's currently active palette, or nil when that module is missing.
local function mk_palette(app)
  if not ColorStudio or not ColorStudio.active_palette then return nil end
  local ok, pal = pcall(ColorStudio.active_palette, app)
  if ok and type(pal) == "table" and type(pal.colors) == "table" then return pal end
  return nil
end

local function mk_delete(item)
  if not r.DeleteProjectMarkerByIndex and not r.DeleteProjectMarker then return false end
  if r.Undo_BeginBlock then r.Undo_BeginBlock() end
  -- By enum index where possible: display numbers can repeat, the index cannot.
  if r.DeleteProjectMarkerByIndex then
    r.DeleteProjectMarkerByIndex(0, item.idx)
  else
    r.DeleteProjectMarker(0, item.num, item.is_region)
  end
  if r.Undo_EndBlock then r.Undo_EndBlock("Transport: delete " .. (item.is_region and "region" or "marker"), -1) end
  if r.UpdateArrange then r.UpdateArrange() end
  mk_invalidate()
  return true
end

-- One chip: a tinted pill carrying the marker/region colour, with a triangular
-- flag (marker) or a solid bar (region) on the left. Returns click flags.
local function mk_chip(ctx, id, item, label, w, h, current)
  local dl = r.ImGui_GetWindowDrawList(ctx)
  r.ImGui_PushID(ctx, id)
  local clicked = r.ImGui_InvisibleButton(ctx, "##mkchip", w, h)
  local hovered = r.ImGui_IsItemHovered(ctx)
  local rclicked = r.ImGui_IsItemClicked and r.ImGui_IsItemClicked(ctx, 1)
  local dbl = hovered and r.ImGui_IsMouseDoubleClicked and r.ImGui_IsMouseDoubleClicked(ctx, 0)
  local x1, y1 = r.ImGui_GetItemRectMin(ctx)
  local x2, y2 = r.ImGui_GetItemRectMax(ctx)
  local accent = nav_color(item.color, item.is_region and Theme.colors.accent_soft or Theme.colors.accent)
  local base = hovered and Theme.colors.frame_hover or Theme.colors.frame_bg
  local tint = (accent & 0xFFFFFF00) | (current and 0x4C or (item.is_region and 0x26 or 0x12))
  local rounding = UIScale.px(item.is_region and 3 or 8)
  r.ImGui_DrawList_AddRectFilled(dl, x1, y1, x2, y2, base, rounding)
  r.ImGui_DrawList_AddRectFilled(dl, x1, y1, x2, y2, tint, rounding)
  r.ImGui_DrawList_AddRect(dl, x1, y1, x2, y2, (accent & 0xFFFFFF00) | (current and 0xFF or 0x99), rounding, 0,
    current and UIScale.px(1.6) or UIScale.px(1))
  -- Left marker: filled triangle for a point marker, solid bar for a region.
  local cy = (y1 + y2) * 0.5
  local gx = x1 + UIScale.round(4)
  if item.is_region then
    r.ImGui_DrawList_AddRectFilled(dl, gx, y1 + UIScale.round(3), gx + UIScale.px(3), y2 - UIScale.round(3), accent)
  else
    local s = UIScale.round(4)
    r.ImGui_DrawList_AddTriangleFilled(dl, gx, cy - s, gx, cy + s, gx + s * 1.2, cy, accent)
  end
  local tx = gx + UIScale.round(8)
  local _, th = r.ImGui_CalcTextSize(ctx, label)
  local fg = current and Theme.colors.text or Theme.text_for_background(base, Theme.colors.text, nil, 3)
  r.ImGui_DrawList_AddText(dl, tx, (y1 + y2 - th) * 0.5, fg, label)
  r.ImGui_PopID(ctx)
  return clicked, hovered, rclicked, dbl
end

-- A palette swatch. Drawn on the draw list rather than with ImGui_ColorButton,
-- which rendered these colours wrong; this is the same 0xRRGGBBAA path the chips
-- and the rest of the module already use. Returns clicked, hovered.
local function mk_swatch(ctx, id, color, size)
  local dl = r.ImGui_GetWindowDrawList(ctx)
  r.ImGui_PushID(ctx, id)
  local clicked = r.ImGui_InvisibleButton(ctx, "##swatch", size, size)
  local hovered = r.ImGui_IsItemHovered(ctx)
  local x1, y1 = r.ImGui_GetItemRectMin(ctx)
  local x2, y2 = r.ImGui_GetItemRectMax(ctx)
  r.ImGui_DrawList_AddRectFilled(dl, x1, y1, x2, y2, (color & 0xFFFFFF00) | 0xFF, UIScale.px(3))
  r.ImGui_DrawList_AddRect(dl, x1, y1, x2, y2, hovered and Theme.colors.text or Theme.colors.border,
    UIScale.px(3), 0, hovered and UIScale.px(1.6) or UIScale.px(1))
  r.ImGui_PopID(ctx)
  return clicked, hovered
end

local function mk_color_hex(color)
  return string.format("#%06X", (color >> 8) & 0xFFFFFF)
end

-- Context menu for a chip, drawn outside the scrolling strip so the popup is not
-- clipped by the child window.
local function mk_draw_context(ctx, app)
  local mk = state.markers
  if mk.open_ctx then
    r.ImGui_OpenPopup(ctx, "##transport_marker_ctx")
    mk.open_ctx = false
  end
  if not r.ImGui_BeginPopup(ctx, "##transport_marker_ctx") then
    mk_commit_color(app)
    return
  end
  local item = mk.ctx_item
  if not item then r.ImGui_EndPopup(ctx) return end
  local kind = item.is_region and "Region" or "Marker"
  r.ImGui_TextColored(ctx, Theme.colors.accent, kind .. " " .. item.num)
  r.ImGui_TextColored(ctx, Theme.colors.text_dim, fmt_pos(item.pos))
  r.ImGui_Separator(ctx)

  r.ImGui_SetNextItemWidth(ctx, UIScale.round(170))
  if mk.focus_rename then
    if r.ImGui_SetKeyboardFocusHere then r.ImGui_SetKeyboardFocusHere(ctx) end
    mk.focus_rename = false
  end
  local changed, value = r.ImGui_InputText(ctx, "##mk_rename", mk.rename_text or "")
  if changed then mk.rename_text = value end
  local bw = UIScale.text_button_w(ctx, "Rename", 70)
  if r.ImGui_Button(ctx, "Rename", bw, 0) then
    mk_rename(item, tostring(mk.rename_text or ""))
    mk.color_dirty = false -- the rename already wrote the live colour along with it
    app.status = "Transport: renamed " .. kind:lower() .. " " .. item.num
    r.ImGui_CloseCurrentPopup(ctx)
  end
  -- Colour: Color Studio's active palette, a free picker, its active colour, and
  -- back to REAPER's default. The popup stays open so you can try a few.
  r.ImGui_Separator(ctx)
  local pal = mk_palette(app)
  r.ImGui_TextColored(ctx, Theme.colors.text_dim, pal and ("Colour - " .. pal.name) or "Colour")
  local function paint_it(color, label)
    mk_set_color(item, color, mk_color_undo_label(item))
    mk.color_value = color or mk.color_value
    mk.color_dirty = false
    app.status = "Transport: " .. label .. " " .. kind:lower() .. " " .. item.num
  end
  if pal then
    local sw = UIScale.round(15)
    for i, col in ipairs(pal.colors) do
      if i > 1 and ((i - 1) % 8) ~= 0 then r.ImGui_SameLine(ctx, 0, UIScale.gap(2)) end
      local sclicked, shovered = mk_swatch(ctx, "mk_swatch_" .. i, col, sw)
      if sclicked then paint_it(col, "coloured") end
      if shovered then r.ImGui_SetTooltip(ctx, mk_color_hex(col)) end
    end
  end
  if r.ImGui_ColorEdit4 then
    local eflags = 0
    if r.ImGui_ColorEditFlags_NoInputs then eflags = eflags | r.ImGui_ColorEditFlags_NoInputs() end
    if r.ImGui_ColorEditFlags_NoLabel then eflags = eflags | r.ImGui_ColorEditFlags_NoLabel() end
    local col_changed, picked = r.ImGui_ColorEdit4(ctx, "##mk_color_pick", mk.color_value or 0x7AA2F7FF, eflags)
    if col_changed then
      mk.color_value = (picked & 0xFFFFFF00) | 0xFF
      mk_set_color(item, mk.color_value, nil) -- live; one undo point follows on close
      mk.color_dirty = true
    end
    if r.ImGui_IsItemDeactivatedAfterEdit and r.ImGui_IsItemDeactivatedAfterEdit(ctx) then mk_commit_color(app) end
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Pick any colour") end
    r.ImGui_SameLine(ctx, 0, UIScale.gap(4))
    r.ImGui_AlignTextToFramePadding(ctx)
    r.ImGui_Text(ctx, "Custom")
    r.ImGui_SameLine(ctx, 0, UIScale.gap(8))
  end
  if pal and pal.active_color then
    local aclicked, ahovered = mk_swatch(ctx, "mk_studio_color", pal.active_color, r.ImGui_GetFrameHeight(ctx))
    if aclicked then paint_it(pal.active_color, "coloured") end
    if ahovered then
      r.ImGui_SetTooltip(ctx, "Color Studio's active colour  " .. mk_color_hex(pal.active_color))
    end
    r.ImGui_SameLine(ctx, 0, UIScale.gap(8))
  end
  if r.ImGui_Button(ctx, "Default##mk_color_reset", UIScale.text_button_w(ctx, "Default", 60), 0) then
    paint_it(nil, "reset the colour of")
  end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Back to REAPER's default marker colour") end

  r.ImGui_Separator(ctx)
  if r.ImGui_Selectable(ctx, "Move edit cursor here") then mk_goto(item) end
  if item.is_region then
    if r.ImGui_Selectable(ctx, "Set time selection") then mk_set_time_selection(item) end
    if r.ImGui_Selectable(ctx, "Loop and play") then mk_loop(item) end
  end
  r.ImGui_Separator(ctx)
  if r.ImGui_Selectable(ctx, "Delete") then
    mk.color_dirty = false -- never colour a marker we just removed
    if mk_delete(item) then app.status = "Transport: deleted " .. kind:lower() .. " " .. item.num end
  end
  r.ImGui_EndPopup(ctx)
end

-- ---------------------------------------------------------------------------
-- Ruler lanes: the "Ruler: Show/hide ruler lane 1..16" actions report no state
-- at all (the Actions list State column stays empty and GetToggleCommandState
-- returns -1), so they cannot be driven towards a known layout. GetSetProjectInfo
-- does expose the lanes directly: RULER_LANE_COUNT plus a settable
-- RULER_LANE_HIDDEN per lane, which sets rather than toggles and so always lands
-- on all-hidden or all-shown, empty lanes included.
-- ---------------------------------------------------------------------------
local function ruler_lane_count()
  if not r.GetSetProjectInfo then return 0 end
  local ok, n = pcall(r.GetSetProjectInfo, 0, "RULER_LANE_COUNT", 0, false)
  if ok and type(n) == "number" and n > 0 then return math.floor(n) end
  return 0
end

local function ruler_api_ready()
  return ruler_lane_count() > 0
end

-- Whether the lanes are numbered from 0 or from 1 is not documented, so both
-- ends are walked: an index that does not exist reads back 0 and ignores writes.
-- Counting the hidden ones (rather than the shown ones) keeps that harmless,
-- because the phantom index never reports itself as hidden.
local function ruler_hidden_lanes()
  local hidden = 0
  for i = 0, ruler_lane_count() do
    local ok, v = pcall(r.GetSetProjectInfo, 0, "RULER_LANE_HIDDEN:" .. i, 0, false)
    if ok and v == 1 then hidden = hidden + 1 end
  end
  return hidden
end

local function ruler_shown_lanes()
  return math.max(0, ruler_lane_count() - ruler_hidden_lanes())
end

-- Walking the lanes is cheap but pointless every frame.
local ruler_count_cache = { value = 0, at = -1 }
local function ruler_visible_lanes_cached()
  local now = os.clock()
  if ruler_count_cache.at >= 0 and (now - ruler_count_cache.at) < 0.25 then return ruler_count_cache.value end
  ruler_count_cache.value = ruler_shown_lanes()
  ruler_count_cache.at = now
  return ruler_count_cache.value
end

-- show = true reveals every lane, false clears the ruler. Returns how many lanes
-- actually changed, measured from the hidden count so a phantom index cannot
-- inflate it.
local function ruler_set_all(show)
  local before = ruler_hidden_lanes()
  for i = 0, ruler_lane_count() do
    pcall(r.GetSetProjectInfo, 0, "RULER_LANE_HIDDEN:" .. i, show and 0 or 1, true)
  end
  if r.UpdateTimeline then r.UpdateTimeline() end
  if r.UpdateArrange then r.UpdateArrange() end
  ruler_count_cache.at = -1
  return math.abs(ruler_hidden_lanes() - before)
end

-- ---------------------------------------------------------------------------
-- Time selection slots: A/B/C ranges kept per project (a range only means
-- something inside the project it came from), for flipping between a verse and
-- a chorus while mixing.
-- ---------------------------------------------------------------------------
local TS_SLOTS = { "A", "B", "C" }

local function ts_slot_key(i) return "ts_slot_" .. i end

local function ts_slot_get(i)
  if not r.GetProjExtState then return nil end
  local _, blob = r.GetProjExtState(0, ZOOM_EXT_SECTION, ts_slot_key(i))
  if not blob or blob == "" then return nil end
  local s, e = blob:match("^([-%.%d]+);([-%.%d]+)$")
  s, e = tonumber(s), tonumber(e)
  if s and e and (e - s) > 0.0000001 then return s, e end
  return nil
end

local function ts_slot_save(i)
  if not r.SetProjExtState or not r.GetSet_LoopTimeRange then return false end
  local s, e = r.GetSet_LoopTimeRange(false, false, 0, 0, false)
  if not s or not e or (e - s) <= 0.0000001 then return false end
  r.SetProjExtState(0, ZOOM_EXT_SECTION, ts_slot_key(i), string.format("%.9f;%.9f", s, e))
  return true
end

-- Sets the time selection and the loop points, and seeks: with repeat on and the
-- transport rolling this drops you straight into the other section.
local function ts_slot_recall(i)
  local s, e = ts_slot_get(i)
  if not s then return false end
  r.GetSet_LoopTimeRange(true, false, s, e, false)
  r.GetSet_LoopTimeRange(true, true, s, e, false)
  if r.SetEditCurPos then r.SetEditCurPos(s, true, true) end
  return true
end

-- Three states rather than the usual two: empty, stored, and stored-and-playing.
local function ts_chip(ctx, id, label, filled, current, w, h)
  local dl = r.ImGui_GetWindowDrawList(ctx)
  r.ImGui_PushID(ctx, id)
  local clicked = r.ImGui_InvisibleButton(ctx, "##ts_chip", w, h)
  local hovered = r.ImGui_IsItemHovered(ctx)
  local x1, y1 = r.ImGui_GetItemRectMin(ctx)
  local x2, y2 = r.ImGui_GetItemRectMax(ctx)
  local bg = current and Theme.colors.accent_soft or (hovered and Theme.colors.frame_hover or Theme.colors.frame_bg)
  local border = current and Theme.colors.accent or (filled and Theme.colors.text_dim or Theme.colors.border)
  local fg = current and Theme.colors.accent
    or (filled and Theme.text_for_background(bg, Theme.colors.text, nil, 3) or Theme.colors.text_dim)
  r.ImGui_DrawList_AddRectFilled(dl, x1, y1, x2, y2, bg, UIScale.px(4))
  r.ImGui_DrawList_AddRect(dl, x1, y1, x2, y2, border, UIScale.px(4), 0, current and UIScale.px(1.6) or UIScale.px(1))
  local tw, th = r.ImGui_CalcTextSize(ctx, label)
  r.ImGui_DrawList_AddText(dl, (x1 + x2 - tw) * 0.5, (y1 + y2 - th) * 0.5, fg, label)
  r.ImGui_PopID(ctx)
  return clicked, hovered
end

-- ---------------------------------------------------------------------------
-- Record status helpers
-- ---------------------------------------------------------------------------
local REC_MAX_ROWS = 6
local REC_BYTES_PER_SAMPLE = 3 -- assume 24-bit; the readout says it is an estimate

-- Channels this track will write to disk. I_RECINPUT packs the input type: bit
-- 4096 means MIDI (no meaningful audio on disk), 2048 multichannel, 1024 stereo.
local function rec_track_channels(track)
  local input = math.floor(r.GetMediaTrackInfo_Value(track, "I_RECINPUT") or -1)
  if input < 0 or (input & 4096) ~= 0 then return 0 end
  if (input & 2048) ~= 0 then return math.max(1, math.floor(r.GetMediaTrackInfo_Value(track, "I_NCHAN") or 2)) end
  if (input & 1024) ~= 0 then return 2 end
  return 1
end

local function rec_build()
  local list, channels = {}, 0
  for i = 0, r.CountTracks(0) - 1 do
    local track = r.GetTrack(0, i)
    if (r.GetMediaTrackInfo_Value(track, "I_RECARM") or 0) > 0 then
      local _, name = r.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
      name = tostring(name or "")
      list[#list + 1] = {
        track = track,
        name = name ~= "" and name or ("Track " .. (i + 1)),
        color = nav_color(r.GetTrackColor and r.GetTrackColor(track) or 0, Theme.colors.accent_soft),
        mon = math.floor(r.GetMediaTrackInfo_Value(track, "I_RECMON") or 0),
      }
      channels = channels + rec_track_channels(track)
    end
  end
  return list, channels
end

-- Walking every track each frame is wasteful; a fifth of a second still feels live.
local rec_cache = { list = {}, channels = 0, at = -1 }
local function rec_armed()
  local now = os.clock()
  if rec_cache.at >= 0 and (now - rec_cache.at) < 0.2 then return rec_cache.list, rec_cache.channels end
  rec_cache.list, rec_cache.channels = rec_build()
  rec_cache.at = now
  return rec_cache.list, rec_cache.channels
end

local function rec_invalidate() rec_cache.at = -1 end

local function rec_free_mb()
  if not r.GetFreeDiskSpaceForRecordPath then return nil end
  local ok, mb = pcall(r.GetFreeDiskSpaceForRecordPath, 0, 0)
  if ok and type(mb) == "number" and mb >= 0 then return mb end
  return nil
end

local function rec_srate()
  local sr = 0
  if r.GetSetProjectInfo then sr = r.GetSetProjectInfo(0, "PROJECT_SRATE", 0, false) or 0 end
  if sr <= 0 then sr = 48000 end
  return sr
end

local function fmt_size_mb(mb)
  if mb >= 1048576 then return string.format("%.1f TB", mb / 1048576) end
  if mb >= 1024 then return string.format("%.1f GB", mb / 1024) end
  return string.format("%d MB", math.floor(mb))
end

local function fmt_span(sec)
  if sec >= 3600 then return string.format("%dh %02dm", math.floor(sec / 3600), math.floor((sec % 3600) / 60)) end
  if sec >= 60 then return string.format("%dm %02ds", math.floor(sec / 60), math.floor(sec % 60)) end
  return string.format("%ds", math.floor(sec))
end

-- Timeline length of the take in progress, frozen after the transport stops so
-- the last take's length stays readable.
local function rec_sample()
  local rec = state.rec
  local rolling = is_recording()
  if rolling then
    local pos = r.GetPlayPosition and r.GetPlayPosition() or 0
    if not rec.was then
      rec.start = pos
      rec.last = 0
    else
      rec.last = math.max(0, pos - (rec.start or pos))
    end
  end
  rec.was = rolling
end

local REC_MON_LABELS = { [0] = "-", [1] = "M", [2] = "T" }
local REC_MON_TIPS = {
  [0] = "Input monitoring off",
  [1] = "Input monitoring on",
  [2] = "Input monitoring on, tape style (not while playing)",
}

-- ---------------------------------------------------------------------------
-- Pre-roll / count-in helpers
-- ---------------------------------------------------------------------------
-- Pre-roll and record mode are native actions with a readable toggle state, so
-- their command ids are fixed. Count-in comes from SWS, whose numeric ids differ
-- between installs: the id below is only a first guess, accepted when it still
-- carries the expected name and otherwise looked up once by name.
local PR_PLAY, PR_REC = 41818, 41819
local PR_MODES = {
  { label = "Normal", cmd = 40252, tip = "Record mode: normal" },
  { label = "Punch", cmd = 40076, tip = "Record mode: time selection auto-punch" },
  { label = "Items", cmd = 40253, tip = "Record mode: selected item auto-punch" },
}

local sws_action_cache = {}
local function sws_action(preferred, name)
  local cached = sws_action_cache[name]
  if cached ~= nil then return cached end
  local function carries_name(cmd)
    if cmd == 0 or not r.CF_GetCommandText then return false end
    local ok, text = pcall(r.CF_GetCommandText, 0, cmd)
    return ok and type(text) == "string" and text:lower():find(name, 1, true) ~= nil
  end
  local found = 0
  if carries_name(preferred) then
    found = preferred
  elseif r.CF_EnumerateActions then
    local index = 0
    while index < 30000 do
      local cmd, text = r.CF_EnumerateActions(0, index, "")
      if not cmd or cmd == 0 then break end
      if type(text) == "string" and text:lower():find(name, 1, true) then
        found = cmd
        break
      end
      index = index + 1
    end
  end
  sws_action_cache[name] = found
  return found
end

local function pr_countin_play() return sws_action(54030, "toggle count-in before playback") end
local function pr_countin_rec() return sws_action(54033, "toggle count-in before recording") end

-- Pre-roll length, in measures.
local function pr_read_measures()
  if not r.SNM_GetDoubleConfigVar then return nil end
  local sentinel = -987654.321
  local ok, v = pcall(r.SNM_GetDoubleConfigVar, "prerollmeas", sentinel)
  if ok and type(v) == "number" and v ~= sentinel then return v end
  return nil
end

local function pr_write_measures(v)
  if r.SNM_SetDoubleConfigVar then
    r.SNM_SetDoubleConfigVar("prerollmeas", math.max(0.0, math.min(32.0, v)))
  end
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
  -- Cursor history: back / forward through the spots you jumped to.
  local cur = state.cursor
  local can_back, can_fwd = cur.index > 1, cur.index < #cur.list
  buttons[#buttons + 1] = {
    id = "hist_back", paint = paint_history_back, dim = not can_back,
    tip = can_back and ("Back to " .. fmt_pos(cur.list[cur.index - 1])) or "No earlier cursor position yet",
    action = function() if can_back then cursor_go(cur.index - 1) end end,
  }
  buttons[#buttons + 1] = {
    id = "hist_fwd", paint = paint_history_fwd, dim = not can_fwd,
    tip = can_fwd and ("Forward to " .. fmt_pos(cur.list[cur.index + 1])) or "Nothing to go forward to",
    action = function() if can_fwd then cursor_go(cur.index + 1) end end,
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
    if b.dim then opts.fg = Theme.colors.text_dim end
    if glyph_button(ctx, b.id, size, opts, b.paint) then
      if b.action then b.action() else run(b.cmd) end
    end
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

  -- Slot row: A/B/C stored ranges plus repeat, for A/B-ing two sections.
  local slot_y = sub_y + lh + gap + r.ImGui_GetFrameHeight(ctx) + gap
  local slot_h = UIScale.round(22)
  local cw = (width - 3 * gap) / 4
  for i, name in ipairs(TS_SLOTS) do
    r.ImGui_SetCursorScreenPos(ctx, ox + (i - 1) * (cw + gap), slot_y)
    local s, e = ts_slot_get(i)
    local filled = s ~= nil
    local current = filled and has_sel
      and math.abs(s - sel_start) < 0.001 and math.abs(e - sel_end) < 0.001
    local clicked, hovered = ts_chip(ctx, "ts_slot_" .. i, name, filled, current, cw, slot_h)
    local rclicked = r.ImGui_IsItemClicked and r.ImGui_IsItemClicked(ctx, 1)
    if rclicked then
      if ts_slot_save(i) then
        app.status = "Transport: section " .. name .. " stored"
      else
        app.status = "Transport: make a time selection first"
      end
    elseif clicked then
      if ts_slot_recall(i) then
        app.status = "Transport: section " .. name
      else
        app.status = "Transport: section " .. name .. " is empty (right-click to store)"
      end
    end
    if hovered then
      r.ImGui_SetTooltip(ctx, filled
        and ("Section " .. name .. "   " .. fmt_len(e - s) .. "\n" .. fmt_pos(s) .. "  ->  " .. fmt_pos(e) ..
          "\nClick: recall, right-click: overwrite with the current selection")
        or ("Section " .. name .. " is empty - right-click to store the current time selection"))
    end
  end
  r.ImGui_SetCursorScreenPos(ctx, ox + 3 * (cw + gap), slot_y)
  local lclicked, lhovered = text_chip(ctx, "ts_loop", "Loop", repeat_on(), cw, slot_h)
  if lclicked then run(1068) end
  if lhovered then r.ImGui_SetTooltip(ctx, "Toggle repeat, so switching sections keeps looping") end
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

  -- Row 4: the click pattern, a cell per beat. Each cell carries the sound that
  -- beat uses (A to D) or a dash when it is muted; clicking cycles through them,
  -- the same choices as the grid in REAPER's metronome settings.
  local pattern = metro_read_pattern()
  if pattern then
    local beats = #pattern
    -- Room on the right for the time signature, which doubles as the tell for
    -- where this pattern lives: accent-coloured means a marker carries its own.
    local pos, override = metro_pattern_source()
    local sig = ""
    if r.TimeMap_GetTimeSigAtTime then
      local num, den = r.TimeMap_GetTimeSigAtTime(0, pos)
      if num and den then sig = math.floor(num) .. "/" .. math.floor(den) end
    end
    local sig_w = sig ~= "" and (r.ImGui_CalcTextSize(ctx, sig) + gap * 2) or 0
    local bw = (width - sig_w - (beats - 1) * gap) / beats
    for i = 1, beats do
      local beat = pattern:sub(i, i)
      local muted = beat == "."
      r.ImGui_SetCursorScreenPos(ctx, ox + (i - 1) * (bw + gap), y)
      local clicked, hovered = text_chip(ctx, "metro_beat_" .. i, muted and "-" or beat, not muted, bw, chip_h)
      if clicked then
        if METRO_PATTERN_WRITABLE then
          local next_state = METRO_BEAT_STATES[1]
          for index, state in ipairs(METRO_BEAT_STATES) do
            if state == beat then next_state = METRO_BEAT_STATES[(index % #METRO_BEAT_STATES) + 1] end
          end
          if not metro_set_pattern(pattern:sub(1, i - 1) .. next_state .. pattern:sub(i + 1)) then
            app.status = "Transport: REAPER would not take that click pattern"
          end
        else
          run(40363) -- straight to the metronome settings, where editing is safe
        end
      end
      if hovered then
        r.ImGui_SetTooltip(ctx, "Beat " .. i .. " of " .. beats .. " - " ..
          (muted and "muted" or ("click sound " .. beat)) ..
          (METRO_PATTERN_WRITABLE and "\nClick to cycle A / B / C / D / muted"
            or "\nClick to edit the pattern in REAPER's metronome settings"))
      end
    end
    if sig ~= "" then
      local tw, th = r.ImGui_CalcTextSize(ctx, sig)
      r.ImGui_DrawList_AddText(dl, ox + width - tw, y + (chip_h - th) * 0.5,
        override and Theme.colors.accent or Theme.colors.text_dim, sig)
      r.ImGui_SetCursorScreenPos(ctx, ox + width - sig_w, y)
      r.ImGui_InvisibleButton(ctx, "##metro_sig", sig_w, chip_h)
      if r.ImGui_IsItemHovered(ctx) then
        r.ImGui_SetTooltip(ctx, override
          and (sig .. " - this pattern is set on the tempo marker at " .. fmt_pos(pos) ..
            "\nREAPER's metronome settings show the project pattern instead, not this one")
          or (sig .. " - the project's own click pattern, the one REAPER's metronome settings edit"))
      end
    end
    y = y + chip_h + gap
  end

  -- Row 5: metronome during playback / recording (SWS/AW toggles).
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
  local zgap = UIScale.gap(4)
  local zbtn_w = UIScale.round(20)
  local w = math.max(UIScale.round(60), width - zbtn_w - zgap)
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

  -- Zoom preset column on the right: fit project + three save/recall slots.
  local bx = ox + w + zgap
  local bh = math.floor((h - 3 * zgap) / 4)
  r.ImGui_SetCursorScreenPos(ctx, bx, oy)
  local fit_clicked, fit_hovered = text_chip(ctx, "nav_zoom_fit", "P", false, zbtn_w, bh)
  if fit_clicked then
    zoom_fit_project()
    app.status = "Transport: zoomed to whole project"
  end
  if fit_hovered then r.ImGui_SetTooltip(ctx, "Zoom out to whole project (time + tracks)") end
  for slot = 1, 3 do
    r.ImGui_SetCursorScreenPos(ctx, bx, oy + slot * (bh + zgap))
    local filled = zoom_slot_exists(slot)
    local clicked, shov = text_chip(ctx, "nav_zoom_slot_" .. slot, tostring(slot), filled, zbtn_w, bh)
    local rclicked = r.ImGui_IsItemClicked and r.ImGui_IsItemClicked(ctx, 1)
    if rclicked then
      if zoom_slot_save(slot) then app.status = "Transport: zoom slot " .. slot .. " saved" end
    elseif clicked then
      if zoom_slot_recall(slot) then
        app.status = "Transport: zoom slot " .. slot .. " recalled"
      else
        app.status = "Transport: zoom slot " .. slot .. " is empty (right-click to save)"
      end
    end
    if shov then
      r.ImGui_SetTooltip(ctx, filled
        and ("Zoom slot " .. slot .. " — click: recall, right-click: overwrite with current zoom")
        or ("Zoom slot " .. slot .. " (empty) — right-click: save current zoom"))
    end
  end
end

BLOCKS.markers = function(ctx, app, settings, width)
  if not r.CountProjectMarkers or not r.EnumProjectMarkers3 then
    r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Markers need EnumProjectMarkers3.")
    return
  end
  local mk = state.markers
  local dl = r.ImGui_GetWindowDrawList(ctx)
  local ox, oy = r.ImGui_GetCursorScreenPos(ctx)
  ox, oy = math.floor(ox), math.floor(oy)
  local gap = UIScale.gap(4)
  local size = UIScale.round(22)
  local lh = r.ImGui_GetTextLineHeight(ctx)
  local y = oy

  -- Row 1: prev/next, filter cycle, and the two add buttons on the right.
  r.ImGui_SetCursorScreenPos(ctx, ox, y)
  if glyph_button(ctx, "mk_prev", size, { tooltip = "Go to previous marker" }, paint_to_start) then run(40172) end
  r.ImGui_SetCursorScreenPos(ctx, ox + size + gap, y)
  if glyph_button(ctx, "mk_next", size, { tooltip = "Go to next marker" }, paint_to_end) then run(40173) end

  local filter = settings.markers_filter or "all"
  local filter_label = (filter == "markers" and "M") or (filter == "regions" and "R") or "M+R"
  local filter_next = (filter == "all" and "markers") or (filter == "markers" and "regions") or "all"
  local filter_desc = (filter == "markers" and "markers only") or (filter == "regions" and "regions only") or "markers and regions"
  local fw = UIScale.round(42)
  r.ImGui_SetCursorScreenPos(ctx, ox + 2 * (size + gap), y)
  local fclicked, fhov = text_chip(ctx, "mk_filter", filter_label, filter ~= "all", fw, size)
  if fclicked then
    settings.markers_filter = filter_next
    save(app)
  end
  if fhov then r.ImGui_SetTooltip(ctx, "Showing " .. filter_desc .. " - click to cycle") end

  local ruler_ok = ruler_api_ready()
  local aw = UIScale.round(30)
  local acount = ruler_ok and 3 or 2
  local ax = ox + width - acount * aw - (acount - 1) * gap
  r.ImGui_SetCursorScreenPos(ctx, ax, y)
  local amc, amh = text_chip(ctx, "mk_add_marker", "+M", false, aw, size)
  if amc then
    run(40157) -- insert marker at current position
    mk_invalidate()
    app.status = "Transport: marker added"
  end
  if amh then r.ImGui_SetTooltip(ctx, "Insert a marker at the edit cursor") end
  r.ImGui_SetCursorScreenPos(ctx, ax + aw + gap, y)
  local arc, arh = text_chip(ctx, "mk_add_region", "+R", false, aw, size)
  if arc then
    local ts, te = 0, 0
    if r.GetSet_LoopTimeRange then ts, te = r.GetSet_LoopTimeRange(false, false, 0, 0, false) end
    if te and ts and te - ts > 0.0000001 then
      run(40174) -- insert region from time selection
      mk_invalidate()
      app.status = "Transport: region added"
    else
      app.status = "Transport: make a time selection first"
    end
  end
  if arh then r.ImGui_SetTooltip(ctx, "Insert a region from the time selection") end

  -- Ruler lanes: hide every populated lane in one go, or bring them all back.
  if ruler_ok then
    local lanes_shown = ruler_visible_lanes_cached()
    local lanes_visible = lanes_shown > 0
    r.ImGui_SetCursorScreenPos(ctx, ax + 2 * (aw + gap), y)
    local total = ruler_lane_count()
    local tip = lanes_visible
      and ("Hide all ruler lanes (" .. lanes_shown .. " of " .. total .. " shown)")
      or ("Show all " .. total .. " ruler lanes")
    if glyph_button(ctx, "mk_ruler_lanes", size,
      { width = aw, active = lanes_visible, tooltip = tip }, paint_ruler_lanes) then
      local moved = ruler_set_all(not lanes_visible)
      if moved > 0 then
        app.status = lanes_visible and ("Transport: hid " .. moved .. " ruler lane(s)")
          or ("Transport: showed " .. moved .. " ruler lane(s)")
      else
        app.status = "Transport: ruler lanes already " .. (lanes_visible and "hidden" or "shown")
      end
    end
  end
  y = y + size + gap

  -- Row 2: what the cursor is sitting in right now (play cursor while rolling).
  local items = mk_get_list()
  local cur_m, cur_r = -1, -1
  if r.GetLastMarkerAndCurRegion then
    cur_m, cur_r = r.GetLastMarkerAndCurRegion(0, focus_time())
    cur_m, cur_r = cur_m or -1, cur_r or -1
  end
  local cur_item
  for _, it in ipairs(items) do
    if it.is_region and it.idx == cur_r then cur_item = it break end
  end
  if not cur_item and cur_m >= 0 then
    for _, it in ipairs(items) do
      if (not it.is_region) and it.idx == cur_m then cur_item = it break end
    end
  end
  r.ImGui_SetCursorScreenPos(ctx, ox, y)
  if cur_item then
    local ccol = nav_color(cur_item.color, cur_item.is_region and Theme.colors.accent_soft or Theme.colors.accent)
    local dot_r = UIScale.px(3)
    r.ImGui_DrawList_AddCircleFilled(dl, ox + dot_r, y + lh * 0.5, dot_r, ccol, 12)
    local tx = ox + dot_r * 2 + gap
    r.ImGui_DrawList_AddText(dl, tx, y, Theme.colors.text_dim, mk_fit(ctx, mk_label(cur_item), math.max(0, ox + width - tx)))
  else
    r.ImGui_DrawList_AddText(dl, ox, y, Theme.colors.text_dim, "Before the first marker")
  end
  r.ImGui_Dummy(ctx, width, lh)
  y = y + lh + gap

  -- Row 3+: the strip itself, chips wrapped into rows and scrolled past MK_MAX_ROWS.
  local filtered = {}
  for _, it in ipairs(items) do
    local include = filter == "all" or (filter == "markers" and not it.is_region) or (filter == "regions" and it.is_region)
    if include then filtered[#filtered + 1] = it end
  end
  if #filtered == 0 then
    r.ImGui_SetCursorScreenPos(ctx, ox, y)
    r.ImGui_TextColored(ctx, Theme.colors.text_dim,
      #items == 0 and "No markers or regions yet." or "Nothing matches this filter.")
    mk_draw_context(ctx, app)
    return
  end

  local chip_h = math.max(UIScale.round(19), lh + UIScale.round(5))
  local pad_l, pad_r = UIScale.round(15), UIScale.round(7)
  local function layout(avail)
    local lines, x = { {} }, 0
    for _, it in ipairs(filtered) do
      local label = mk_label(it)
      local cw = r.ImGui_CalcTextSize(ctx, label) + pad_l + pad_r
      if cw > avail then
        label = mk_fit(ctx, label, avail - pad_l - pad_r)
        cw = avail
      end
      if x > 0 and x + cw > avail then
        lines[#lines + 1] = {}
        x = 0
      end
      local line = lines[#lines]
      line[#line + 1] = { item = it, label = label, x = x, w = cw }
      x = x + cw + gap
    end
    return lines
  end

  local lines = layout(width)
  if #lines > MK_MAX_ROWS then
    -- Re-flow inside the narrower space left by the scrollbar.
    local sb = UIScale.round(12)
    if r.ImGui_GetStyleVar and r.ImGui_StyleVar_ScrollbarSize then
      local ok, v = pcall(r.ImGui_GetStyleVar, ctx, r.ImGui_StyleVar_ScrollbarSize())
      if ok and type(v) == "number" and v > 0 then sb = math.ceil(v) end
    end
    lines = layout(math.max(UIScale.round(40), width - sb - UIScale.round(2)))
  end
  local list_h = math.min(#lines, MK_MAX_ROWS) * (chip_h + gap) - gap

  r.ImGui_SetCursorScreenPos(ctx, ox, y)
  local padded = false
  if r.ImGui_PushStyleVar and r.ImGui_StyleVar_WindowPadding then
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), 0, 0)
    padded = true
  end
  local child_visible = r.ImGui_BeginChild(ctx, "##transport_marker_strip", width, list_h, 0)
  if padded then r.ImGui_PopStyleVar(ctx) end
  if child_visible then
    local ok, err = pcall(function()
      for li, line in ipairs(lines) do
        for _, c in ipairs(line) do
          local it = c.item
          r.ImGui_SetCursorPos(ctx, c.x, (li - 1) * (chip_h + gap))
          local current = (it.is_region and it.idx == cur_r)
            or ((not it.is_region) and it.idx == cur_m and cur_r < 0)
          local clicked, hovered, rclicked, dbl = mk_chip(ctx, "mk_" .. it.idx, it, c.label, c.w, chip_h, current)
          if rclicked then
            mk.ctx_item = it
            mk.rename_text = it.name
            mk.color_value = nav_color(it.color, Theme.colors.accent)
            mk.open_ctx = true
            mk.focus_rename = true
          elseif dbl then
            if it.is_region then
              mk_loop(it)
              app.status = "Transport: looping " .. mk_label(it)
            else
              mk_goto(it)
              if not is_playing() then run(1007) end
            end
          elseif clicked then
            mk_goto(it)
            if it.is_region then mk_set_time_selection(it) end
          end
          if hovered then
            if it.is_region then
              r.ImGui_SetTooltip(ctx, "Region " .. it.num .. "  " .. fmt_pos(it.pos) .. "  ->  " .. fmt_pos(it.rgn_end) ..
                "\nClick: cursor + time selection   Double-click: loop and play   Right-click: menu")
            else
              r.ImGui_SetTooltip(ctx, "Marker " .. it.num .. "  " .. fmt_pos(it.pos) ..
                "\nClick: move edit cursor   Double-click: play from here   Right-click: menu")
            end
          end
        end
      end
    end)
    r.ImGui_EndChild(ctx)
    if not ok then error(err) end
  end

  mk_draw_context(ctx, app)
end

BLOCKS.record_status = function(ctx, app, settings, width)
  local dl = r.ImGui_GetWindowDrawList(ctx)
  local ox, oy = r.ImGui_GetCursorScreenPos(ctx)
  ox, oy = math.floor(ox), math.floor(oy)
  local gap = UIScale.gap(4)
  local lh = r.ImGui_GetTextLineHeight(ctx)
  local big = UIScale.round(26)
  local recording = is_recording()
  local danger = Theme.colors.danger or 0xFF3B3BFF
  local blink = recording and math.sin(os.clock() * 7) > 0
  local armed, channels = rec_armed()

  -- Hero: the take counter, with a dot that blinks red while rolling.
  local dot_r = UIScale.round(5)
  local dot_col = Theme.colors.border
  if recording then dot_col = blink and danger or ((danger & 0xFFFFFF00) | 0x40) end
  r.ImGui_DrawList_AddCircleFilled(dl, ox + dot_r, oy + big * 0.5, dot_r, dot_col, 16)

  local elapsed = state.rec.last or 0
  local counter = fmt_len(elapsed)
  local col = recording and danger or (elapsed > 0 and Theme.colors.text or Theme.colors.text_dim)
  local tx = ox + dot_r * 2 + gap
  local font = get_font(ctx, big)
  if font and r.ImGui_DrawList_AddTextEx then
    pcall(r.ImGui_DrawList_AddTextEx, dl, font, big, tx, oy, col, counter)
  else
    r.ImGui_DrawList_AddText(dl, tx, oy, col, counter)
  end

  -- Badge: how many tracks are armed.
  local badge_w = UIScale.round(56)
  local bx = ox + width - badge_w
  local badge_col = #armed > 0 and danger or Theme.colors.border
  r.ImGui_DrawList_AddRectFilled(dl, bx, oy, bx + badge_w, oy + big, Theme.colors.frame_hover, UIScale.px(4))
  r.ImGui_DrawList_AddRect(dl, bx, oy, bx + badge_w, oy + big, badge_col, UIScale.px(4), 0, UIScale.px(1))
  local badge = #armed .. " ARM"
  local bw2, bh2 = r.ImGui_CalcTextSize(ctx, badge)
  r.ImGui_DrawList_AddText(dl, bx + (badge_w - bw2) * 0.5, oy + (big - bh2) * 0.5,
    #armed > 0 and Theme.colors.text or Theme.colors.text_dim, badge)

  -- Subline: free disk space and how long that lasts at the current arm count.
  local sub_y = oy + big + UIScale.round(3)
  local free_mb = rec_free_mb()
  local sub, span
  if free_mb then
    sub = fmt_size_mb(free_mb) .. " free"
    if channels > 0 then
      span = free_mb * 1048576 / (rec_srate() * REC_BYTES_PER_SAMPLE * channels)
      sub = sub .. "   " .. fmt_span(span) .. " left"
    end
  else
    sub = "Recording path not readable"
  end
  local low = span ~= nil and span < 600
  r.ImGui_DrawList_AddText(dl, ox, sub_y, low and (Theme.colors.warning or danger) or Theme.colors.text_dim, sub)
  r.ImGui_SetCursorScreenPos(ctx, ox, sub_y)
  r.ImGui_InvisibleButton(ctx, "##rec_disk", width, lh)
  if r.ImGui_IsItemHovered(ctx) then
    r.ImGui_SetTooltip(ctx, "Free space in the project's recording path\n" ..
      (channels > 0
        and ("Estimate for " .. channels .. " channel(s) at " .. math.floor(rec_srate()) .. " Hz, 24-bit")
        or "Arm a track for a time estimate"))
  end

  -- Armed tracks: click to select, right-click to disarm, and a monitoring chip.
  local y = sub_y + lh + gap
  local row_h = UIScale.round(20)
  local mon_w = UIScale.round(24)
  if #armed == 0 then
    r.ImGui_SetCursorScreenPos(ctx, ox, y)
    local sel = r.CountSelectedTracks(0) or 0
    local clicked, hovered = text_chip(ctx, "rec_arm_sel",
      sel > 0 and ("Arm " .. sel .. " selected track(s)") or "No tracks armed", false, width, row_h)
    if clicked and sel > 0 then
      if r.Undo_BeginBlock then r.Undo_BeginBlock() end
      for i = 0, sel - 1 do
        local track = r.GetSelectedTrack(0, i)
        if track then r.SetMediaTrackInfo_Value(track, "I_RECARM", 1) end
      end
      if r.Undo_EndBlock then r.Undo_EndBlock("Transport: arm selected tracks", -1) end
      rec_invalidate()
      app.status = "Transport: armed " .. sel .. " track(s)"
    end
    if hovered and sel == 0 then r.ImGui_SetTooltip(ctx, "Select tracks in the arrange to arm them from here") end
    return
  end

  local rows = math.min(#armed, REC_MAX_ROWS)
  for i = 1, rows do
    local entry = armed[i]
    r.ImGui_SetCursorScreenPos(ctx, ox, y)
    r.ImGui_PushID(ctx, "rec_row_" .. i)
    local clicked = r.ImGui_InvisibleButton(ctx, "##row", math.max(UIScale.round(20), width - mon_w - gap), row_h)
    local hovered = r.ImGui_IsItemHovered(ctx)
    local rclicked = r.ImGui_IsItemClicked and r.ImGui_IsItemClicked(ctx, 1)
    local x1, y1 = r.ImGui_GetItemRectMin(ctx)
    local x2, y2 = r.ImGui_GetItemRectMax(ctx)
    local bg = hovered and Theme.colors.frame_hover or Theme.colors.frame_bg
    r.ImGui_DrawList_AddRectFilled(dl, x1, y1, x2, y2, bg, UIScale.px(3))
    r.ImGui_DrawList_AddRectFilled(dl, x1, y1, x1 + UIScale.px(3), y2, entry.color, UIScale.px(3))
    local _, th = r.ImGui_CalcTextSize(ctx, entry.name)
    local name_x = x1 + UIScale.round(8)
    r.ImGui_DrawList_AddText(dl, name_x, (y1 + y2 - th) * 0.5,
      Theme.text_for_background(bg, Theme.colors.text, nil, 3),
      mk_fit(ctx, entry.name, math.max(0, x2 - name_x - UIScale.round(4))))
    r.ImGui_PopID(ctx)
    if rclicked then
      r.SetMediaTrackInfo_Value(entry.track, "I_RECARM", 0)
      rec_invalidate()
      app.status = "Transport: disarmed " .. entry.name
    elseif clicked then
      if r.SetOnlyTrackSelected then r.SetOnlyTrackSelected(entry.track) end
      run(40913) -- vertical scroll selected tracks into view
    end
    if hovered then
      r.ImGui_SetTooltip(ctx, entry.name .. "\nClick: select the track, right-click: disarm")
    end

    r.ImGui_SetCursorScreenPos(ctx, ox + width - mon_w, y)
    local mclicked, mhovered = text_chip(ctx, "rec_mon_" .. i, REC_MON_LABELS[entry.mon] or "?",
      entry.mon > 0, mon_w, row_h)
    if mclicked then
      r.SetMediaTrackInfo_Value(entry.track, "I_RECMON", (entry.mon + 1) % 3)
      rec_invalidate()
    end
    if mhovered then
      r.ImGui_SetTooltip(ctx, (REC_MON_TIPS[entry.mon] or "Input monitoring") .. "\nClick to cycle")
    end
    y = y + row_h + UIScale.gap(2)
  end
  if #armed > rows then
    r.ImGui_SetCursorScreenPos(ctx, ox, y)
    r.ImGui_TextColored(ctx, Theme.colors.text_dim, "+ " .. (#armed - rows) .. " more armed")
  end
end

BLOCKS.preroll = function(ctx, app, settings, width)
  local dl = r.ImGui_GetWindowDrawList(ctx)
  local ox, oy = r.ImGui_GetCursorScreenPos(ctx)
  ox, oy = math.floor(ox), math.floor(oy)
  local gap = UIScale.gap(4)
  local lh = r.ImGui_GetTextLineHeight(ctx)
  -- Frame height for every row, so the chips line up with the measures field.
  local row_h = r.ImGui_GetFrameHeight(ctx)
  local label_w = UIScale.round(54)
  local extra_w = UIScale.round(46)
  local pair_w = math.max(UIScale.round(28), (width - label_w - extra_w - 3 * gap) / 2)
  local y = oy

  -- A label plus a Play / Rec pair, shared by the pre-roll and count-in rows.
  local function pair_row(label, id, play_cmd, rec_cmd, tip_play, tip_rec)
    r.ImGui_DrawList_AddText(dl, ox, y + (row_h - lh) * 0.5, Theme.colors.text_dim, label)
    local x = ox + label_w
    local specs = {
      { key = "play", text = "Play", cmd = play_cmd, tip = tip_play },
      { key = "rec", text = "Rec", cmd = rec_cmd, tip = tip_rec },
    }
    for _, spec in ipairs(specs) do
      r.ImGui_SetCursorScreenPos(ctx, x, y)
      local on = spec.cmd ~= 0 and toggle_state(spec.cmd)
      local clicked, hovered = text_chip(ctx, id .. "_" .. spec.key, spec.text, on, pair_w, row_h)
      if clicked then
        if spec.cmd ~= 0 then
          run(spec.cmd)
        else
          app.status = "Transport: count-in needs the SWS extension"
        end
      end
      if hovered then
        r.ImGui_SetTooltip(ctx, spec.cmd ~= 0 and spec.tip or "Needs the SWS extension")
      end
      x = x + pair_w + gap
    end
    return x
  end

  -- Row 1: pre-roll, with its length in measures on the right.
  local x = pair_row("Pre-roll", "pr", PR_PLAY, PR_REC,
    "Pre-roll before playback", "Pre-roll before recording")
  local measures = pr_read_measures()
  if measures then
    r.ImGui_SetCursorScreenPos(ctx, x, y)
    r.ImGui_SetNextItemWidth(ctx, extra_w)
    local sc = push_slider_style(ctx)
    local changed, value
    if r.ImGui_DragDouble then
      changed, value = r.ImGui_DragDouble(ctx, "##pr_measures", measures, 0.05, 0.0, 32.0, "%.1f")
    else
      changed, value = r.ImGui_SliderDouble(ctx, "##pr_measures", measures, 0.0, 8.0, "%.1f")
    end
    pop_slider_style(ctx, sc)
    if changed then pr_write_measures(value) end
    if r.ImGui_IsItemHovered(ctx) then
      r.ImGui_SetTooltip(ctx, "Pre-roll length in measures (drag to change)")
    end
  end
  y = y + row_h + gap

  -- Row 2: count-in (SWS), with the settings gear where the measures field sits.
  pair_row("Count-in", "ci", pr_countin_play(), pr_countin_rec(),
    "Count-in before playback", "Count-in before recording")
  r.ImGui_SetCursorScreenPos(ctx, ox + width - row_h, y)
  if glyph_button(ctx, "pr_settings", row_h, { tooltip = "Open REAPER's metronome / pre-roll settings" }, paint_gear) then
    run(40363)
  end
  y = y + row_h + gap

  -- Row 3: record mode. The three actions are mutually exclusive and each
  -- reports its own state, so the active one simply lights up.
  local mode_w = math.max(UIScale.round(40), (width - 2 * gap) / #PR_MODES)
  for i, mode in ipairs(PR_MODES) do
    r.ImGui_SetCursorScreenPos(ctx, ox + (i - 1) * (mode_w + gap), y)
    local clicked, hovered = text_chip(ctx, "pr_mode_" .. i, mode.label, toggle_state(mode.cmd), mode_w, row_h)
    if clicked then
      run(mode.cmd)
      app.status = "Transport: " .. mode.tip:lower()
    end
    if hovered then r.ImGui_SetTooltip(ctx, mode.tip) end
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
    if id == PINNED_BLOCK then
      -- Order means nothing for the pinned card: it always sits on the anchored edge.
      r.ImGui_AlignTextToFramePadding(ctx)
      r.ImGui_TextColored(ctx, Theme.colors.accent, "Pinned")
      if r.ImGui_IsItemHovered(ctx) then
        r.ImGui_SetTooltip(ctx, "Always fixed to the " .. (settings.anchor == "bottom" and "bottom" or "top") ..
          " of the module; the other blocks scroll behind it")
      end
    else
      if r.ImGui_SmallButton(ctx, "Up") then move_block(app, settings, i, -1) end
      r.ImGui_SameLine(ctx, 0, UIScale.gap(3))
      if r.ImGui_SmallButton(ctx, "Dn") then move_block(app, settings, i, 1) end
    end
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
local function draw_block_card(ctx, app, settings, id, pinned)
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
  -- The pinned card cannot be reordered, so it gets no grab handle (and the row
  -- of pixels it would have cost goes to the block instead).
  if not pinned then draw_grab_handle(ctx, dl, id, inner_w) end
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

-- The scrolling half of the module: every card except the pinned one. Given a
-- fixed height so the pinned card always keeps its place; the cards inside
-- scroll once they no longer fit. bottom_align keeps a short stack sitting
-- against the pinned card instead of drifting to the top.
local function draw_block_stack(ctx, app, settings, ids, height, bottom_align)
  -- Drawn even when empty: the child then acts as the spacer that holds the
  -- pinned card against its edge.
  local padded = false
  if r.ImGui_PushStyleVar and r.ImGui_StyleVar_WindowPadding then
    r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), 0, 0)
    padded = true
  end
  local visible = r.ImGui_BeginChild(ctx, "##transport_block_stack", 0, height, 0)
  if padded then r.ImGui_PopStyleVar(ctx) end
  if not visible then return end
  local ok, err = pcall(function()
    if bottom_align then
      local _, inner_h = r.ImGui_GetContentRegionAvail(ctx)
      local total = 0
      for _, id in ipairs(ids) do
        total = total + (state.card_heights[id] or UIScale.round(48)) + UIScale.gap(3)
      end
      local spacer = math.floor((inner_h or 0) - total)
      if spacer > 0 then r.ImGui_SetCursorPosY(ctx, r.ImGui_GetCursorPosY(ctx) + spacer) end
    end
    for _, id in ipairs(ids) do draw_block_card(ctx, app, settings, id) end
    r.ImGui_Dummy(ctx, 1, 1)
  end)
  r.ImGui_EndChild(ctx)
  if not ok then error(err) end
end

-- Runs every frame for every loaded module, so the cursor history keeps filling
-- up even while another module is on screen.
function M.update(app)
  cursor_sample()
  rec_sample()
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

  -- The transport card is pinned to whichever edge the anchor names and never
  -- scrolls, so the buttons stay reachable however short the window gets. Every
  -- other card lives in a scrolling area that takes the space left over.
  local rest = {}
  for _, id in ipairs(settings.blocks) do
    if id ~= PINNED_BLOCK then rest[#rest + 1] = id end
  end
  local pinned = block_enabled(settings, PINNED_BLOCK) and BLOCKS[PINNED_BLOCK] and PINNED_BLOCK or nil
  local gap = UIScale.gap(3)
  local _, avail_h = r.ImGui_GetContentRegionAvail(ctx)
  local pinned_h = pinned and ((state.card_heights[pinned] or UIScale.round(48)) + gap) or 0
  -- Anchored at the bottom the stack is submitted first, so ImGui puts its item
  -- spacing between the stack and the pinned card; leave room for it or the card
  -- gets clipped off the bottom edge.
  local spacing_y = 0
  if settings.anchor == "bottom" and r.ImGui_GetStyleVar and r.ImGui_StyleVar_ItemSpacing then
    local ok, _, sy = pcall(r.ImGui_GetStyleVar, ctx, r.ImGui_StyleVar_ItemSpacing())
    if ok and type(sy) == "number" then spacing_y = sy end
  end
  local stack_h = math.max(UIScale.round(40), math.floor((avail_h or 0) - pinned_h - spacing_y))

  state.pending_reorder = nil
  if settings.anchor == "bottom" then
    draw_block_stack(ctx, app, settings, rest, stack_h, true)
    if pinned then draw_block_card(ctx, app, settings, pinned, true) end
  else
    if pinned then draw_block_card(ctx, app, settings, pinned, true) end
    draw_block_stack(ctx, app, settings, rest, stack_h, false)
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
