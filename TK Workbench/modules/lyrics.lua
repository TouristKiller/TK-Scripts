local r = reaper
local Theme = require("core.theme")
local UI = require("core.ui")
local UIScale = require("core.ui_scale")

local M = {
  id = "lyrics",
  title = "Lyrics",
  icon = "LYR",
  version = "0.1.1"
}

local defaults = {
  source_mode = "auto",
  autoscroll = true,
  show_timer = true,
  show_progress = true,
  show_name = true,
  show_timestamps = true,
  click_to_seek = true,
  sync_offset_ms = 0,
  active_line_scale = 1.25,
  lyrics_font_size = 20,
  line_spacing = 6
}

local SOURCE_MODES = {
  { id = "auto", label = "Auto (embedded > .lrc > notes)" },
  { id = "embedded", label = "Embedded tag only" },
  { id = "lrc", label = ".lrc sidecar only" },
  { id = "notes", label = "Item notes only" }
}

local state = {
  fonts = {},
  font = nil,
  cache = { key = nil, model = nil },
  last_active = -1,
  last_scroll_key = nil
}

local function clamp(value, lo, hi)
  value = tonumber(value) or 0
  if value < lo then return lo end
  if value > hi then return hi end
  return value
end

local function trim(value)
  return (tostring(value or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function ensure_settings(app)
  app.settings.lyrics = app.settings.lyrics or {}
  local settings = app.settings.lyrics
  local changed = false
  for key, value in pairs(defaults) do
    if settings[key] == nil then settings[key] = value; changed = true end
  end
  settings.lyrics_font_size = clamp(settings.lyrics_font_size, 10, 64)
  settings.sync_offset_ms = clamp(settings.sync_offset_ms, -5000, 5000)
  settings.active_line_scale = clamp(settings.active_line_scale, 1.0, 2.0)
  settings.line_spacing = clamp(settings.line_spacing, 0, 40)
  if changed and app.save_settings then app.save_settings() end
  return settings
end

local function ensure_font(app)
  if state.font or not r.ImGui_CreateFont then return state.font end
  local ok, font = pcall(r.ImGui_CreateFont, "sans-serif", 18)
  if ok and font then
    if r.ImGui_Attach then pcall(r.ImGui_Attach, app.ctx, font) end
    state.font = font
  end
  return state.font
end

local function utf8_encode(code)
  if code < 0x80 then
    return string.char(code)
  elseif code < 0x800 then
    return string.char(0xC0 + math.floor(code / 0x40), 0x80 + (code % 0x40))
  elseif code < 0x10000 then
    return string.char(0xE0 + math.floor(code / 0x1000), 0x80 + (math.floor(code / 0x40) % 0x40), 0x80 + (code % 0x40))
  else
    return string.char(0xF0 + math.floor(code / 0x40000), 0x80 + (math.floor(code / 0x1000) % 0x40), 0x80 + (math.floor(code / 0x40) % 0x40), 0x80 + (code % 0x40))
  end
end

local function latin1_to_utf8(bytes)
  local out = {}
  for i = 1, #bytes do out[i] = utf8_encode(bytes:byte(i)) end
  return table.concat(out)
end

local function utf16_to_utf8(bytes, big_endian)
  local out = {}
  local i = 1
  local n = #bytes
  while i + 1 <= n do
    local b1, b2 = bytes:byte(i), bytes:byte(i + 1)
    local code = big_endian and (b1 * 256 + b2) or (b2 * 256 + b1)
    i = i + 2
    if code >= 0xD800 and code <= 0xDBFF and i + 1 <= n then
      local c1, c2 = bytes:byte(i), bytes:byte(i + 1)
      local lo = big_endian and (c1 * 256 + c2) or (c2 * 256 + c1)
      if lo >= 0xDC00 and lo <= 0xDFFF then
        code = 0x10000 + (code - 0xD800) * 0x400 + (lo - 0xDC00)
        i = i + 2
      end
    end
    out[#out + 1] = utf8_encode(code)
  end
  return table.concat(out)
end

local function decode_text(enc, bytes)
  bytes = bytes or ""
  if enc == 1 then
    local head = bytes:sub(1, 2)
    if head == "\255\254" then return utf16_to_utf8(bytes:sub(3), false) end
    if head == "\254\255" then return utf16_to_utf8(bytes:sub(3), true) end
    return utf16_to_utf8(bytes, false)
  elseif enc == 2 then
    return utf16_to_utf8(bytes, true)
  elseif enc == 3 then
    return bytes
  end
  return latin1_to_utf8(bytes)
end

local function strip_bom(text)
  text = tostring(text or "")
  if text:sub(1, 3) == "\239\187\191" then return text:sub(4) end
  return text
end

local function synchsafe(b1, b2, b3, b4)
  return ((b1 & 0x7F) << 21) | ((b2 & 0x7F) << 14) | ((b3 & 0x7F) << 7) | (b4 & 0x7F)
end

local function bigendian32(b1, b2, b3, b4)
  return (b1 << 24) | (b2 << 16) | (b3 << 8) | b4
end

local function find_double_null(s, from)
  local i = from or 1
  while i + 1 <= #s do
    if s:byte(i) == 0 and s:byte(i + 1) == 0 then return i end
    i = i + 2
  end
  return #s + 1
end

local function skip_descriptor(rest, enc, start)
  if enc == 1 or enc == 2 then
    local idx = find_double_null(rest, start)
    return idx + 2
  end
  local z = rest:find("\0", start, true)
  return (z or #rest) + 1
end

local function parse_uslt(body)
  if #body < 5 then return nil end
  local enc = body:byte(1)
  local rest = body:sub(5)
  local text_start = skip_descriptor(rest, enc, 1)
  return trim(decode_text(enc, rest:sub(text_start)))
end

local function parse_sylt(body)
  if #body < 7 then return nil end
  local enc = body:byte(1)
  local tsf = body:byte(5)
  local rest = body:sub(7)
  local p = skip_descriptor(rest, enc, 1)
  local entries = {}
  local n = #rest
  while p <= n do
    local seg
    if enc == 1 or enc == 2 then
      local idx = find_double_null(rest, p)
      seg = rest:sub(p, idx - 1)
      p = idx + 2
    else
      local z = rest:find("\0", p, true)
      if not z then break end
      seg = rest:sub(p, z - 1)
      p = z + 1
    end
    if p + 3 > n then break end
    local b1, b2, b3, b4 = rest:byte(p, p + 3)
    p = p + 4
    local ts = bigendian32(b1, b2, b3, b4)
    local t = (tsf == 2) and (ts / 1000) or (ts / 1000)
    entries[#entries + 1] = { t = t, line = trim(decode_text(enc, seg)) }
  end
  if #entries == 0 then return nil end
  return entries
end

local function read_id3_tag(path)
  local ok, result = pcall(function()
    local f = io.open(path, "rb")
    if not f then return nil end
    local header = f:read(10)
    if not header or #header < 10 or header:sub(1, 3) ~= "ID3" then f:close(); return nil end
    local ver = header:byte(4)
    local flags = header:byte(6)
    local size = synchsafe(header:byte(7), header:byte(8), header:byte(9), header:byte(10))
    local body = f:read(size) or ""
    f:close()
    return { ver = ver, flags = flags, body = body }
  end)
  if ok then return result end
  return nil
end

local function iter_frames(ver, body, cb)
  local offset = 1
  if not body or #body < 10 then return end
  local n = #body
  local i = offset
  while i + 10 <= n + 1 do
    local id = body:sub(i, i + 3)
    if not id:match("^[A-Z0-9][A-Z0-9][A-Z0-9][A-Z0-9]$") then break end
    local s1, s2, s3, s4 = body:byte(i + 4, i + 7)
    local fsize = (ver == 4) and synchsafe(s1, s2, s3, s4) or bigendian32(s1, s2, s3, s4)
    if fsize <= 0 or i + 10 + fsize - 1 > n then break end
    cb(id, body:sub(i + 10, i + 10 + fsize - 1))
    i = i + 10 + fsize
  end
end

local function from_embedded(path, source)
  if source and r.GetMediaFileMetadata then
    local keys = { "ID3:USLT", "VORBIS:LYRICS", "VORBIS:UNSYNCEDLYRICS", "ID3:TXXX:LYRICS" }
    for _, key in ipairs(keys) do
      local ok, value = r.GetMediaFileMetadata(source, key)
      if ok and ok ~= 0 and value and value ~= "" then return value, "embedded:" .. key, nil end
    end
  end
  if path and path ~= "" then
    local tag = read_id3_tag(path)
    if tag then
      local uslt, sylt
      iter_frames(tag.ver, tag.body, function(id, fb)
        if id == "SYLT" and not sylt then sylt = parse_sylt(fb) end
        if id == "USLT" and not uslt then uslt = parse_uslt(fb) end
      end)
      if sylt and #sylt > 0 then return nil, "embedded:SYLT", sylt end
      if uslt and uslt ~= "" then return uslt, "embedded:USLT", nil end
    end
  end
  return nil
end

local function from_lrc(path)
  if not path or path == "" then return nil end
  local candidates = { path:gsub("%.%w+$", "") .. ".lrc", path .. ".lrc" }
  for _, lrc in ipairs(candidates) do
    local f = io.open(lrc, "rb")
    if f then
      local data = f:read("*a")
      f:close()
      if data and data ~= "" then return strip_bom(data), "lrc", nil end
    end
  end
  return nil
end

local function from_notes(item)
  if not item then return nil end
  local _, notes = r.GetSetMediaItemInfo_String(item, "P_NOTES", "", false)
  if notes and notes ~= "" then return notes, "notes", nil end
  return nil
end

local function extract_lyrics(path, item, source, mode)
  if mode == "embedded" then return from_embedded(path, source) end
  if mode == "lrc" then return from_lrc(path) end
  if mode == "notes" then return from_notes(item) end
  local text, origin, sylt = from_embedded(path, source)
  if text or sylt then return text, origin, sylt end
  text, origin, sylt = from_lrc(path)
  if text or sylt then return text, origin, sylt end
  return from_notes(item)
end

local function parse_lrc(text)
  local entries = {}
  local has_time = false
  for raw in (tostring(text or "") .. "\n"):gmatch("(.-)\n") do
    local line = raw:gsub("\r$", "")
    local times = {}
    local rest = line
    while true do
      local mm, ss, frac, after = rest:match("^%s*%[(%d+):(%d+)([%.:]?%d*)%](.*)$")
      if not mm then break end
      local t = tonumber(mm) * 60 + tonumber(ss)
      if frac and frac ~= "" then
        local digits = frac:gsub("[%.:]", "")
        if digits ~= "" then t = t + tonumber("0." .. digits) end
      end
      times[#times + 1] = t
      rest = after
      has_time = true
    end
    if #times > 0 then
      for _, t in ipairs(times) do entries[#entries + 1] = { t = t, line = trim(rest) } end
    else
      local meta = line:match("^%s*%[%a+:.-%]%s*$")
      if not meta then entries[#entries + 1] = { t = nil, line = line } end
    end
  end
  return entries, has_time
end

local function build_model(text, origin, sylt)
  if sylt then
    table.sort(sylt, function(a, b) return (a.t or 0) < (b.t or 0) end)
    return { timed = sylt, origin = origin }
  end
  local entries, has_time = parse_lrc(text)
  if has_time then
    local timed = {}
    for _, e in ipairs(entries) do if e.t then timed[#timed + 1] = e end end
    table.sort(timed, function(a, b) return a.t < b.t end)
    return { timed = timed, origin = origin }
  end
  local lines = {}
  for _, e in ipairs(entries) do lines[#lines + 1] = e.line end
  return { lines = lines, origin = origin }
end

local function item_guid(item)
  local _, g = r.GetSetMediaItemInfo_String(item, "GUID", "", false)
  return g or tostring(item)
end

local function pick_item(pos)
  local sel = r.GetSelectedMediaItem(0, 0)
  if sel then return sel end
  local track = r.GetSelectedTrack(0, 0)
  if track then
    local count = r.CountTrackMediaItems(track)
    for i = 0, count - 1 do
      local it = r.GetTrackMediaItem(track, i)
      local s = r.GetMediaItemInfo_Value(it, "D_POSITION")
      local l = r.GetMediaItemInfo_Value(it, "D_LENGTH")
      if pos >= s and pos <= s + l then return it end
    end
  end
  return nil
end

local function get_context()
  local play_state = r.GetPlayState and (r.GetPlayState() or 0) or 0
  local playing = (play_state & 1) == 1 or (play_state & 4) == 4
  local pos = playing and r.GetPlayPosition() or r.GetCursorPosition()
  local item = pick_item(pos)
  if not item then return { playing = playing } end
  local s = r.GetMediaItemInfo_Value(item, "D_POSITION")
  local l = r.GetMediaItemInfo_Value(item, "D_LENGTH")
  local elapsed = clamp(pos - s, 0, l)
  local take = r.GetActiveTake(item)
  local rate = 1
  local offs = 0
  local path, source
  if take and not (r.TakeIsMIDI and r.TakeIsMIDI(take)) then
    rate = r.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE")
    if not rate or rate <= 0 then rate = 1 end
    offs = r.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS") or 0
    source = r.GetMediaItemTake_Source(take)
    if source then
      path = r.GetMediaSourceFileName(source, "")
    end
  end
  local name = ""
  if take then
    local _, take_name = r.GetSetMediaItemTakeInfo_String(take, "P_NAME", "", false)
    name = take_name or ""
  end
  return {
    playing = playing,
    item = item,
    take = take,
    name = name,
    path = path,
    source = source,
    elapsed = elapsed,
    length = l,
    item_start = s,
    start_offs = offs,
    play_rate = rate,
    source_pos = offs + elapsed * rate,
    guid = item_guid(item)
  }
end

local function format_time(seconds)
  seconds = math.max(0, math.floor((tonumber(seconds) or 0)))
  local minutes = math.floor(seconds / 60)
  local secs = seconds % 60
  if minutes >= 60 then
    local hours = math.floor(minutes / 60)
    minutes = minutes % 60
    return string.format("%d:%02d:%02d", hours, minutes, secs)
  end
  return string.format("%d:%02d", minutes, secs)
end

local function format_stamp(seconds)
  seconds = math.max(0, tonumber(seconds) or 0)
  local minutes = math.floor(seconds / 60)
  local rest = seconds - minutes * 60
  return string.format("[%02d:%05.2f]", minutes, rest)
end

local function active_timed_index(timed, source_pos)
  local index = 0
  for i = 1, #timed do
    if (timed[i].t or 0) <= source_pos then index = i else break end
  end
  return index
end

local function push_font(ctx, size)
  if state.font and r.ImGui_PushFont then
    return pcall(r.ImGui_PushFont, ctx, state.font, size) == true
  end
  return false
end

local function pop_font(ctx, pushed)
  if pushed and r.ImGui_PopFont then pcall(r.ImGui_PopFont, ctx) end
end

local function draw_combo(ctx, app, settings)
  local current = SOURCE_MODES[1]
  for _, opt in ipairs(SOURCE_MODES) do if opt.id == settings.source_mode then current = opt end end
  r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Lyrics source")
  r.ImGui_SetNextItemWidth(ctx, UIScale.round(230))
  if r.ImGui_BeginCombo(ctx, "##lyrics_source", current.label) then
    for _, opt in ipairs(SOURCE_MODES) do
      if r.ImGui_Selectable(ctx, opt.label .. "##np_src_" .. opt.id, settings.source_mode == opt.id) then
        settings.source_mode = opt.id
        state.cache.key = nil
        if app.save_settings then app.save_settings() end
      end
    end
    r.ImGui_EndCombo(ctx)
  end
end

local function draw_toggle(ctx, app, settings, key, label)
  local changed, value = r.ImGui_Checkbox(ctx, label .. "##np_" .. key, settings[key] ~= false)
  if changed then
    settings[key] = value
    if app.save_settings then app.save_settings() end
  end
end

local function draw_settings_button(ctx, app, settings, x, y, width)
  local button_h = UIScale.button_h(ctx)
  r.ImGui_SetCursorScreenPos(ctx, x + width - button_h - UIScale.round(6), y + UIScale.round(6))
  if r.ImGui_Button(ctx, "...##lyrics_settings", button_h, button_h) then r.ImGui_OpenPopup(ctx, "##lyrics_settings_popup") end
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "Lyrics settings") end
  if r.ImGui_BeginPopup(ctx, "##lyrics_settings_popup") then
    r.ImGui_TextColored(ctx, Theme.colors.accent, "Lyrics")
    r.ImGui_Separator(ctx)
    draw_combo(ctx, app, settings)
    r.ImGui_Separator(ctx)
    draw_toggle(ctx, app, settings, "show_name", "Show track name")
    draw_toggle(ctx, app, settings, "show_timer", "Show timer")
    draw_toggle(ctx, app, settings, "show_progress", "Show progress bar")
    draw_toggle(ctx, app, settings, "show_timestamps", "Show timestamps")
    draw_toggle(ctx, app, settings, "autoscroll", "Auto-scroll lyrics")
    draw_toggle(ctx, app, settings, "click_to_seek", "Click line to seek")
    r.ImGui_Separator(ctx)
    r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Lyrics size")
    r.ImGui_SetNextItemWidth(ctx, UIScale.round(180))
    local changed, value = r.ImGui_SliderInt(ctx, "##lyrics_font_size", math.floor(settings.lyrics_font_size), 10, 48, "%d px")
    if changed then
      settings.lyrics_font_size = clamp(value, 10, 64)
      if app.save_settings then app.save_settings() end
    end
    r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Line spacing")
    r.ImGui_SetNextItemWidth(ctx, UIScale.round(180))
    local sp_changed, sp_value = r.ImGui_SliderInt(ctx, "##lyrics_line_spacing", math.floor(settings.line_spacing or 6), 0, 40, "%d px")
    if sp_changed then
      settings.line_spacing = clamp(sp_value, 0, 40)
      if app.save_settings then app.save_settings() end
    end
    r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Active line scale")
    r.ImGui_SetNextItemWidth(ctx, UIScale.round(180))
    local scale_changed, scale_value = r.ImGui_SliderDouble(ctx, "##lyrics_active_scale", settings.active_line_scale or 1.0, 1.0, 2.0, "%.2fx")
    if scale_changed then
      settings.active_line_scale = clamp(scale_value, 1.0, 2.0)
      if app.save_settings then app.save_settings() end
    end
    r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Sync offset")
    r.ImGui_SetNextItemWidth(ctx, UIScale.round(180))
    local off_changed, off_value = r.ImGui_SliderInt(ctx, "##lyrics_sync_offset", math.floor(settings.sync_offset_ms or 0), -5000, 5000, "%d ms")
    if off_changed then
      settings.sync_offset_ms = clamp(off_value, -5000, 5000)
      if app.save_settings then app.save_settings() end
    end
    r.ImGui_Separator(ctx)
    if r.ImGui_Button(ctx, "Reload lyrics##lyrics_reload") then state.cache.key = nil end
    r.ImGui_EndPopup(ctx)
  end
end

local function draw_progress(ctx, draw_list, x, y, width, fraction)
  local height = UIScale.round(8)
  fraction = clamp(fraction, 0, 1)
  r.ImGui_DrawList_AddRectFilled(draw_list, x, y, x + width, y + height, Theme.colors.frame_bg, UIScale.px(3))
  r.ImGui_DrawList_AddRectFilled(draw_list, x, y, x + width * fraction, y + height, Theme.colors.accent, UIScale.px(3))
  r.ImGui_DrawList_AddRect(draw_list, x, y, x + width, y + height, Theme.colors.border, UIScale.px(3), 0, UIScale.px(1))
end

local function wrap_text(ctx, text, max_w)
  local lines = {}
  local current = ""
  for word in tostring(text or ""):gmatch("%S+") do
    local candidate = current == "" and word or (current .. " " .. word)
    local width = r.ImGui_CalcTextSize(ctx, candidate)
    if width <= max_w or current == "" then
      current = candidate
    else
      lines[#lines + 1] = current
      current = word
    end
  end
  if current ~= "" then lines[#lines + 1] = current end
  if #lines == 0 then lines[1] = " " end
  return lines
end

local function draw_centered_text(ctx, font_size, text, color)
  local pushed = push_font(ctx, font_size)
  local avail = r.ImGui_GetContentRegionAvail(ctx)
  local lines = wrap_text(ctx, text, avail)
  for _, line in ipairs(lines) do
    local text_w = r.ImGui_CalcTextSize(ctx, line)
    local offset = math.max(0, (avail - text_w) * 0.5)
    r.ImGui_SetCursorPosX(ctx, r.ImGui_GetCursorPosX(ctx) + offset)
    r.ImGui_TextColored(ctx, color, line ~= "" and line or " ")
  end
  pop_font(ctx, pushed)
end

local function seek_to(context, source_t)
  if not context or not context.item then return end
  local rate = context.play_rate or 1
  if rate <= 0 then rate = 1 end
  local project_pos = (context.item_start or 0) + ((source_t or 0) - (context.start_offs or 0)) / rate
  local lo = context.item_start or 0
  local hi = lo + (context.length or 0)
  project_pos = clamp(project_pos, lo, hi)
  r.SetEditCurPos(project_pos, true, true)
end

local function draw_lyrics(ctx, settings, model, source_pos, fraction, lyrics_w, lyrics_h, context)
  local timed = model and model.timed
  local lines = model and model.lines
  local active = -1
  local offset = (settings.sync_offset_ms or 0) / 1000
  if timed then active = active_timed_index(timed, source_pos + offset) end

  local scroll_key = tostring(state.cache.key)
  if state.last_scroll_key ~= scroll_key then
    state.last_active = -1
    state.last_scroll_key = scroll_key
  end

  if r.ImGui_BeginChild(ctx, "##lyrics_panel", lyrics_w, lyrics_h, 0) then
    if timed then
      if #timed == 0 then
        draw_centered_text(ctx, settings.lyrics_font_size, "No lyrics found", Theme.colors.text_dim)
      else
        local show_ts = settings.show_timestamps ~= false
        local can_seek = settings.click_to_seek ~= false and context and context.item
        local seek_rects = {}
        local sp_pushed = r.ImGui_StyleVar_ItemSpacing and r.ImGui_PushStyleVar and
          pcall(r.ImGui_PushStyleVar, ctx, r.ImGui_StyleVar_ItemSpacing(), 0, 0)
        local gap = math.max(0, UIScale.round(settings.line_spacing or 6))
        for i, entry in ipairs(timed) do
          local is_active = i == active
          local color = is_active and Theme.colors.accent or (i < active and Theme.colors.text_dim or Theme.colors.text)
          local _, sy = r.ImGui_GetCursorScreenPos(ctx)
          if show_ts and entry.t then
            draw_centered_text(ctx, math.max(9, settings.lyrics_font_size * 0.6), format_stamp(entry.t), Theme.colors.text_dim)
          end
          local line_size = is_active and (settings.lyrics_font_size * (settings.active_line_scale or 1)) or settings.lyrics_font_size
          draw_centered_text(ctx, line_size, entry.line ~= "" and entry.line or " ", color)
          if is_active and settings.autoscroll ~= false and active ~= state.last_active then
            r.ImGui_SetScrollHereY(ctx, 0.4)
          end
          if i < #timed and gap > 0 then r.ImGui_Dummy(ctx, 0, gap) end
          if can_seek and entry.t then
            local _, ny = r.ImGui_GetCursorScreenPos(ctx)
            seek_rects[#seek_rects + 1] = { t = entry.t, y0 = sy, y1 = ny }
          end
        end
        if sp_pushed and r.ImGui_PopStyleVar then r.ImGui_PopStyleVar(ctx) end
        if active ~= state.last_active then state.last_active = active end
        if can_seek and #seek_rects > 0 and r.ImGui_IsWindowHovered(ctx) then
          local _, my = r.ImGui_GetMousePos(ctx)
          local over = nil
          for _, rect in ipairs(seek_rects) do
            if my >= rect.y0 and my < rect.y1 then over = rect break end
          end
          if over then
            if r.ImGui_SetMouseCursor and r.ImGui_MouseCursor_Hand then
              r.ImGui_SetMouseCursor(ctx, r.ImGui_MouseCursor_Hand())
            end
            if r.ImGui_IsMouseClicked(ctx, 0) then seek_to(context, over.t) end
          end
        end
      end
    elseif lines and #lines > 0 then
      local sp_pushed = r.ImGui_StyleVar_ItemSpacing and r.ImGui_PushStyleVar and
        pcall(r.ImGui_PushStyleVar, ctx, r.ImGui_StyleVar_ItemSpacing(), 0, math.max(0, UIScale.round(settings.line_spacing or 6)))
      for _, line in ipairs(lines) do
        if line ~= "" then
          draw_centered_text(ctx, settings.lyrics_font_size, line, Theme.colors.text)
        end
      end
      if sp_pushed and r.ImGui_PopStyleVar then r.ImGui_PopStyleVar(ctx) end
      if settings.autoscroll ~= false then
        local max_scroll = r.ImGui_GetScrollMaxY(ctx)
        r.ImGui_SetScrollY(ctx, max_scroll * clamp(fraction, 0, 1))
      end
    else
      draw_centered_text(ctx, settings.lyrics_font_size, "No lyrics found in this audio file", Theme.colors.text_dim)
    end
    if r.ImGui_IsWindowHovered(ctx) and r.ImGui_IsMouseClicked(ctx, 1) then
      local out = {}
      if timed then
        for _, entry in ipairs(timed) do
          if entry.line ~= "" then out[#out+1] = entry.line end
        end
      elseif lines then
        for _, line in ipairs(lines) do out[#out+1] = line end
      end
      local clip = table.concat(out, "\n")
      if clip ~= "" and r.ImGui_SetClipboardText then
        pcall(r.ImGui_SetClipboardText, ctx, clip)
      end
    end
    r.ImGui_EndChild(ctx)
  end
end

function M.init(app)
  ensure_font(app)
end

function M.draw(app)
  local ctx = app.ctx
  local settings = ensure_settings(app)
  ensure_font(app)

  local available_w, available_h = r.ImGui_GetContentRegionAvail(ctx)
  local width = math.max(UIScale.round(160), available_w or UIScale.round(320))
  local height = math.max(UIScale.round(120), (available_h or UIScale.round(260)) - UI.info_line_height(ctx))

  local context = get_context()
  local origin = "-"

  if context.item then
    local key = tostring(context.path or "") .. "#" .. tostring(context.guid) .. "#" .. tostring(settings.source_mode)
    if state.cache.key ~= key then
      local text, origin_label, sylt = extract_lyrics(context.path, context.item, context.source, settings.source_mode)
      if text or sylt then
        state.cache.model = build_model(text, origin_label, sylt)
      else
        state.cache.model = { origin = "none" }
      end
      state.cache.key = key
      state.cache.origin = origin_label or "none"
      state.last_active = -1
    end
    origin = state.cache.origin or "none"
  else
    state.cache.key = nil
    state.cache.model = nil
  end

  local draw_list = r.ImGui_GetWindowDrawList(ctx)
  local panel_x, panel_y = r.ImGui_GetCursorScreenPos(ctx)

  r.ImGui_DrawList_AddRectFilled(draw_list, panel_x, panel_y, panel_x + width, panel_y + height, Theme.colors.child_bg, UIScale.px(6))
  r.ImGui_DrawList_AddRect(draw_list, panel_x, panel_y, panel_x + width, panel_y + height, Theme.colors.border, UIScale.px(6), 0, UIScale.px(1))
  draw_settings_button(ctx, app, settings, panel_x, panel_y, width)

  local inner_x = panel_x + UIScale.round(12)
  local inner_w = width - UIScale.round(24)
  local cursor_y = panel_y + UIScale.round(10)

  if settings.show_name ~= false then
    local name = context.name and context.name ~= "" and context.name or (context.item and "Audio item" or "No audio item selected")
    r.ImGui_SetCursorScreenPos(ctx, inner_x, cursor_y)
    r.ImGui_PushTextWrapPos(ctx, inner_x + inner_w - UIScale.round(30))
    r.ImGui_TextColored(ctx, Theme.colors.text_dim, name)
    r.ImGui_PopTextWrapPos(ctx)
    cursor_y = cursor_y + r.ImGui_GetTextLineHeight(ctx) + UIScale.round(6)
  end

  if settings.show_timer ~= false then
    local timer_text = format_time(context.elapsed or 0) .. " / " .. format_time(context.length or 0)
    local timer_size = UIScale.round(34)
    local font_pushed = push_font(ctx, timer_size)
    local text_w = r.ImGui_CalcTextSize(ctx, timer_text)
    r.ImGui_SetCursorScreenPos(ctx, inner_x + math.max(0, (inner_w - text_w) * 0.5), cursor_y)
    r.ImGui_TextColored(ctx, context.playing and Theme.colors.accent or Theme.colors.text, timer_text)
    pop_font(ctx, font_pushed)
    cursor_y = cursor_y + timer_size + UIScale.round(8)
  end

  if settings.show_progress ~= false then
    local fraction = 0
    if context.length and context.length > 0 then fraction = (context.elapsed or 0) / context.length end
    draw_progress(ctx, draw_list, inner_x, cursor_y, inner_w, fraction)
    cursor_y = cursor_y + UIScale.round(8) + UIScale.round(10)
  end

  local lyrics_h = math.max(UIScale.round(60), (panel_y + height) - cursor_y - UIScale.round(10))
  r.ImGui_SetCursorScreenPos(ctx, inner_x, cursor_y)
  local fraction = 0
  if context.length and context.length > 0 then fraction = (context.elapsed or 0) / context.length end
  draw_lyrics(ctx, settings, state.cache.model, context.source_pos or 0, fraction, inner_w, lyrics_h, context)

  UI.draw_info_line(ctx, "Lyrics | source: " .. origin .. " | " .. (context.playing and "Playing" or "Stopped"))
end

return M
