local r = reaper
local Theme = require("core.theme")
local UIScale = require("core.ui_scale")
local Engine = require("core.cue_engine")
local Presets = require("core.cue_presets")
local Audio = require("core.cue_audio")

local M = {
  id = "cue",
  title = "Cue",
  icon = "CUE",
  version = "0.1.0"
}

-- Theatre cue lights are amber for standby and green for go, and this borrows
-- both. The theme has no green of its own, so it is spelled out here rather
-- than bent out of the accent: go has to read as go without being looked at.
local GO = 0x4FBF8BFF

local state = {
  fonts = {},
  previous = nil,
  flash_at = nil,
  preset = nil,
  preset_project = nil,
  from_project = false,
  now = nil,
  sections_open = false,
  sounds_open = false,
  export_open = false,
  export_name = ""
}

-- What a project gets when it has no cue setup of its own. Kept in Workbench's
-- own settings rather than in REAPER's ext state, because it is a preference
-- like any other - and it is the only thing about cues that is not per song.
local function user_defaults(app)
  app.settings.cue = app.settings.cue or {}
  local settings = app.settings.cue
  -- Carried over from before presets existed, so an early adopter keeps the
  -- warning distance they had set.
  if settings.defaults == nil and settings.warn_bars ~= nil then
    settings.defaults = {
      cues = { warn_bars = settings.warn_bars, flash_on_change = settings.flash_on_change ~= false },
      display = { beats = settings.show_beats ~= false, details = settings.show_details ~= false }
    }
    settings.warn_bars, settings.show_beats, settings.show_details, settings.flash_on_change = nil, nil, nil, nil
    if app.save_settings then app.save_settings() end
  end
  settings.defaults = Presets.normalize(settings.defaults)
  return settings
end

-- The preset follows the project. Switching tabs has to swap it, or the cues
-- for the last song quietly apply to this one.
local function ensure_preset(app)
  local project = r.EnumProjects and r.EnumProjects(-1, "") or 0
  if state.preset and state.preset_project == project then return state.preset end
  local loaded = Presets.load(0)
  state.from_project = loaded ~= nil
  state.preset = loaded or Presets.copy(user_defaults(app).defaults)
  state.preset_project = project
  return state.preset
end

local function save_preset(app)
  local ok, err = Presets.save(state.preset, 0)
  if ok then
    state.from_project = true
  else
    app.status = tostring(err or "Could not save the cue preset")
  end
  return ok
end

--------------------------------------------------------------------------------
-- text at a size you can read from the back of the room
--------------------------------------------------------------------------------

local function text_width(ctx, text)
  local width = r.ImGui_CalcTextSize(ctx, text)
  return math.max(1, tonumber(width) or 1)
end

-- Sizes are quantised to steps of four before a font is asked for. Dragging the
-- panel wider is a continuous gesture and would otherwise mint a font per pixel,
-- each one attached to the context for the rest of the session. Rounded *down*,
-- never up: a size that comes back larger than the one asked for is a line of
-- text sitting on top of whatever was measured to go underneath it.
local function get_font(ctx, size)
  size = math.max(UIScale.round(12), math.floor(size / 4) * 4)
  local key = tostring(size)
  if state.fonts[key] then return state.fonts[key], size end
  if not r.ImGui_CreateFont then return nil, size end
  local ok, font = pcall(r.ImGui_CreateFont, "sans-serif", size)
  if not ok or not font then return nil, size end
  if r.ImGui_Attach then pcall(r.ImGui_Attach, ctx, font) end
  state.fonts[key] = font
  return font, size
end

-- Fills the width it is given, up to the height it is given, and sits in the
-- middle of that band both ways. Returns the band it consumed - never less than
-- the height it was handed, so what comes after it cannot land on top of it.
local function big_text(ctx, draw_list, text, color, x, y, width, height)
  text = tostring(text or "")
  if text == "" then return 0 end
  local base = r.ImGui_GetFontSize and (tonumber(r.ImGui_GetFontSize(ctx)) or 13) or 13
  local wanted = base * (width / text_width(ctx, text))
  local font, size = get_font(ctx, math.max(base, math.min(wanted, height)))
  local band = math.max(size, height)
  local ty = y + math.max(0, (band - size) * 0.5)
  local scale = size / base
  local drawn_w = text_width(ctx, text) * scale
  if font and r.ImGui_DrawList_AddTextEx then
    local ok = pcall(r.ImGui_DrawList_AddTextEx, draw_list, font, size,
      x + math.max(0, (width - drawn_w) * 0.5), ty, color, text)
    if ok then return band end
  end
  local fallback_y = y + math.max(0, (band - base) * 0.5)
  r.ImGui_DrawList_AddText(draw_list, x + math.max(0, (width - text_width(ctx, text)) * 0.5),
    fallback_y, color, text)
  return band
end

local function centered(ctx, draw_list, text, color, x, y, width)
  text = tostring(text or "")
  if text == "" then return end
  r.ImGui_DrawList_AddText(draw_list, x + math.max(0, (width - text_width(ctx, text)) * 0.5), y, color, text)
end

--------------------------------------------------------------------------------
-- what the three stages look like
--------------------------------------------------------------------------------

-- A region's colour comes back in REAPER's native format, and zero means the
-- region simply has none. The name is run through the theme's contrast check
-- before it is used as text: a dark blue region on a dark panel is a section
-- title nobody can read.
local function section_color(section)
  local native = section and tonumber(section.color) or 0
  if not native or native == 0 or not r.ColorFromNative then return nil end
  local red, green, blue = r.ColorFromNative(native)
  return ((red & 0xFF) << 24) | ((green & 0xFF) << 16) | ((blue & 0xFF) << 8) | 0xFF
end

local function stage_color(stage)
  if stage == "go" then return GO end
  if stage == "last_bar" then return Theme.colors.danger end
  if stage == "warn" then return Theme.colors.warning end
  return Theme.colors.accent
end

local function bars_phrase(bars)
  if not bars then return "" end
  if bars <= 1 then return "last bar" end
  return string.format("in %d bars", math.ceil(bars - 0.0001))
end

local function signature_text(state_now)
  local num = math.floor(tonumber(state_now.timesig_num) or 4)
  local den = math.floor(tonumber(state_now.timesig_den) or 4)
  return string.format("%d/%d", num, den)
end

-- One dot per beat in this bar, the current one lit. A row of dots is read
-- without being looked at, which a number never is - and the colour carries the
-- stage, so the same glance answers "where am I" and "is something coming".
local function draw_beats(ctx, draw_list, state_now, color, x, y, width)
  local beats = math.floor(tonumber(state_now.beats_per_bar) or 4)
  if beats < 1 then beats = 1 end
  if beats > 12 then beats = 12 end
  local radius = UIScale.round(5)
  local gap = UIScale.round(7)
  local step = radius * 2 + gap
  local total = beats * radius * 2 + (beats - 1) * gap
  local start_x = x + math.max(0, (width - total) * 0.5) + radius
  local current = math.floor(tonumber(state_now.beat) or 1)
  for i = 1, beats do
    local cx = start_x + (i - 1) * step
    if i == current then
      r.ImGui_DrawList_AddCircleFilled(draw_list, cx, y + radius, radius, color, 20)
    elseif i < current then
      r.ImGui_DrawList_AddCircleFilled(draw_list, cx, y + radius, radius * 0.55, Theme.colors.text_dim, 16)
    else
      r.ImGui_DrawList_AddCircle(draw_list, cx, y + radius, radius * 0.85, Theme.colors.border, 16, UIScale.px(1))
    end
  end
  return radius * 2
end

-- How far through this section we are, in the same measures the rest of the
-- panel counts in. The dots say where you are in the bar; this says where the
-- bar is in the section.
local function draw_progress(draw_list, fraction, color, x, y, width, height)
  local radius = height * 0.5
  r.ImGui_DrawList_AddRectFilled(draw_list, x, y, x + width, y + height, Theme.colors.frame_bg, radius)
  if fraction > 0 then
    local filled = math.max(height, width * fraction)
    r.ImGui_DrawList_AddRectFilled(draw_list, x, y, x + math.min(width, filled), y + height, color, radius)
  end
end

-- Clipped to its own box: a cell is a quarter of the panel wide and the value
-- inside it is whatever the tempo map happens to say, which is not a length
-- this code gets to decide.
local function draw_cell(ctx, draw_list, label, value, x, y, width, height)
  r.ImGui_DrawList_AddRectFilled(draw_list, x, y, x + width, y + height, Theme.colors.frame_bg, UIScale.px(4))
  r.ImGui_DrawList_PushClipRect(draw_list, x, y, x + width, y + height, true)
  r.ImGui_DrawList_AddText(draw_list, x + UIScale.round(7), y + UIScale.round(4), Theme.colors.text_dim, label)
  r.ImGui_DrawList_AddText(draw_list, x + UIScale.round(7), y + UIScale.round(17), Theme.colors.text, value)
  r.ImGui_DrawList_PopClipRect(draw_list)
end

--------------------------------------------------------------------------------
-- settings, on the right-click rather than in a toolbar
--------------------------------------------------------------------------------

-- Everything here edits this project's preset and writes it straight back:
-- there is no Save button, because a cue setup is something you tweak while the
-- song plays and then walk away from.
local function draw_settings_popup(app, preset)
  local ctx = app.ctx
  if not r.ImGui_BeginPopupContextItem(ctx, "##cue_settings") then return end
  r.ImGui_TextColored(ctx, Theme.colors.text_dim,
    state.from_project and "Cue - this project" or "Cue - your defaults, not saved to this project yet")

  r.ImGui_SetNextItemWidth(ctx, UIScale.round(160))
  local changed, value = r.ImGui_SliderInt(ctx, "Warn bars", preset.cues.warn_bars, 1, 8)
  if changed then preset.cues.warn_bars = value; save_preset(app) end
  if r.ImGui_IsItemHovered(ctx) then
    r.ImGui_SetTooltip(ctx, "How many bars before a section change the display turns amber.\n"
      .. "A section can be given its own distance under Sections")
  end
  changed, value = r.ImGui_Checkbox(ctx, "Beat dots", preset.display.beats == true)
  if changed then preset.display.beats = value; save_preset(app) end
  changed, value = r.ImGui_Checkbox(ctx, "Tempo and signature", preset.display.details == true)
  if changed then preset.display.details = value; save_preset(app) end
  if r.ImGui_IsItemHovered(ctx) then
    r.ImGui_SetTooltip(ctx, "Shown when the panel is wide enough for it")
  end
  changed, value = r.ImGui_Checkbox(ctx, "Section progress bar", preset.display.progress == true)
  if changed then preset.display.progress = value; save_preset(app) end
  if r.ImGui_IsItemHovered(ctx) then
    r.ImGui_SetTooltip(ctx, "How far through the current section you are, in bars")
  end
  changed, value = r.ImGui_Checkbox(ctx, "Use the region colour", preset.display.section_color == true)
  if changed then preset.display.section_color = value; save_preset(app) end
  if r.ImGui_IsItemHovered(ctx) then
    r.ImGui_SetTooltip(ctx, "Paints the section name and the progress bar in the colour of the region itself.\n"
      .. "The name is lightened where it would not be readable on the panel")
  end
  changed, value = r.ImGui_Checkbox(ctx, "Flash on a section change", preset.cues.flash_on_change == true)
  if changed then preset.cues.flash_on_change = value; save_preset(app) end

  r.ImGui_Separator(ctx)
  if r.ImGui_BeginMenu(ctx, "Cue click") then
    local where = Audio.location()
    r.ImGui_TextColored(ctx, Theme.colors.text_dim,
      where == "monitor" and "In REAPER's monitoring FX"
      or (where == "track" and "On a track in this project" or "Not installed yet"))

    local changed, value = r.ImGui_Checkbox(ctx, "Play cues", preset.audio.enabled == true)
    if changed then
      preset.audio.enabled = value
      save_preset(app)
      if value then
        Audio.sync(preset, true)
        if not Audio.location() then
          local _, note = Audio.install_monitor()
          app.status = tostring(note)
        end
      end
    end
    if r.ImGui_IsItemHovered(ctx) then
      r.ImGui_SetTooltip(ctx, "Turning this on installs the click in REAPER's monitoring FX,@N@"
        .. "which is not part of the project and never ends up in a render")
    end

    r.ImGui_SetNextItemWidth(ctx, UIScale.round(150))
    changed, value = r.ImGui_SliderDouble(ctx, "Level", preset.audio.volume, 0.0, 1.0, "%.2f")
    if changed then preset.audio.volume = value; save_preset(app) end

    changed, value = r.ImGui_Checkbox(ctx, "Warning ticks", preset.audio.warn == true)
    if changed then preset.audio.warn = value; save_preset(app) end
    changed, value = r.ImGui_Checkbox(ctx, "Count in the last bar", preset.audio.count_in == true)
    if changed then preset.audio.count_in = value; save_preset(app) end
    changed, value = r.ImGui_Checkbox(ctx, "Hit on the change", preset.audio.go == true)
    if changed then preset.audio.go = value; save_preset(app) end
    changed, value = r.ImGui_Checkbox(ctx, "Accent on the downbeat", preset.audio.accent == true)
    if changed then preset.audio.accent = value; save_preset(app) end
    changed, value = r.ImGui_Checkbox(ctx, "Click on every beat", preset.audio.beat_click == true)
    if changed then preset.audio.beat_click = value; save_preset(app) end
    if r.ImGui_IsItemHovered(ctx) then
      r.ImGui_SetTooltip(ctx, "Off by default - REAPER's own metronome does this,@N@"
        .. "and two clicks that disagree are worse than one")
    end

    r.ImGui_Separator(ctx)
    if r.ImGui_MenuItem(ctx, "Sounds...") then
      Audio.sync(preset, true)
      state.sounds_open = true
    end
    if r.ImGui_IsItemHovered(ctx) then
      r.ImGui_SetTooltip(ctx, "Play your own samples instead of the built-in tones")
    end

    r.ImGui_Separator(ctx)
    if r.ImGui_MenuItem(ctx, "Put it in the monitoring FX") then
      local _, note = Audio.install_monitor()
      app.status = tostring(note)
    end
    if r.ImGui_MenuItem(ctx, "Put it on a track of its own") then
      local _, note = Audio.install_track()
      app.status = tostring(note)
    end
    if r.ImGui_IsItemHovered(ctx) then
      r.ImGui_SetTooltip(ctx, "A track called TK Cue with its master send off, for sending the@N@"
        .. "click to an output of its own. This one does add a track to the project")
    end
    if where and r.ImGui_MenuItem(ctx, "Take it out again") then
      app.status = Audio.remove() and "Cue click removed" or "There was nothing to remove"
    end
    r.ImGui_EndMenu(ctx)
  end

  r.ImGui_Separator(ctx)
  if r.ImGui_MenuItem(ctx, "Sections...") then state.sections_open = true end
  if r.ImGui_IsItemHovered(ctx) then
    r.ImGui_SetTooltip(ctx, "Give a section its own name on screen, or its own warning distance")
  end

  r.ImGui_Separator(ctx)
  if r.ImGui_MenuItem(ctx, "Save as my default for new projects") then
    local settings = user_defaults(app)
    settings.defaults = Presets.copy(preset)
    settings.defaults.sections = {}   -- section names belong to a song, not to a default
    if app.save_settings then app.save_settings() end
    app.status = "Saved as the default cue setup for new projects"
  end
  if r.ImGui_MenuItem(ctx, "Save as a preset file...") then
    state.export_name = tostring(preset.name or "")
    state.export_open = true
  end
  local files = Presets.list()
  if #files > 0 and r.ImGui_BeginMenu(ctx, "Load a preset") then
    for _, entry in ipairs(files) do
      if r.ImGui_MenuItem(ctx, entry.name) then
        local loaded, err = Presets.import(entry.path)
        if loaded then
          -- The sections of the song being worked on are not the sections the
          -- preset was made for, so its overrides come along by name and simply
          -- do not match anything until a section is called the same.
          state.preset = loaded
          save_preset(app)
          app.status = "Loaded cue preset: " .. entry.name
        else
          app.status = tostring(err or "Could not read that preset")
        end
      end
    end
    r.ImGui_EndMenu(ctx)
  end
  if state.from_project and r.ImGui_MenuItem(ctx, "Forget this project's cue setup") then
    Presets.clear(0)
    state.preset = Presets.copy(user_defaults(app).defaults)
    state.from_project = false
    app.status = "This project is back on your default cue setup"
  end
  r.ImGui_EndPopup(ctx)
end

-- Editing is not done on the playing screen: this is a dialog, it may be as
-- wide as it likes, and nothing in it is needed while the song runs.
local function draw_sections_popup(app, preset)
  local ctx = app.ctx
  if state.sections_open then
    r.ImGui_OpenPopup(ctx, "Cue sections")
    state.sections_open = false
  end
  if not r.ImGui_BeginPopup(ctx, "Cue sections") then return end
  local sections = Engine.sections()
  r.ImGui_Text(ctx, "Sections in this project")
  r.ImGui_TextColored(ctx, Theme.colors.text_dim,
    "A label replaces the region name on screen. Warn bars overrides the general setting.")
  r.ImGui_Dummy(ctx, 0, UIScale.round(4))

  if #sections == 0 then
    r.ImGui_TextColored(ctx, Theme.colors.text_dim, "No regions or markers to work with yet.")
  elseif r.ImGui_BeginChild(ctx, "##cue_sections", UIScale.round(420),
                            math.min(UIScale.round(320), UIScale.round(34) * #sections + UIScale.round(10)), 0) then
    for index, section in ipairs(sections) do
      local name = tostring(section.name or "")
      local entry = Presets.section(preset, name)
      r.ImGui_PushID(ctx, index)
      r.ImGui_Text(ctx, name ~= "" and name or "(unnamed)")
      r.ImGui_SameLine(ctx, UIScale.round(150))
      r.ImGui_SetNextItemWidth(ctx, UIScale.round(130))
      local changed, value = r.ImGui_InputTextWithHint(ctx, "##label", name, entry.label ~= name and entry.label or "")
      if changed then
        Presets.set_section(preset, name, { label = value })
        save_preset(app)
      end
      r.ImGui_SameLine(ctx)
      r.ImGui_SetNextItemWidth(ctx, UIScale.round(110))
      local own = entry.overridden and entry.warn_bars or 0
      changed, value = r.ImGui_SliderInt(ctx, "##warn", own, 0, 8, own == 0 and "warn: general" or "warn: %d")
      if changed then
        Presets.set_section(preset, name, { warn_bars = value > 0 and value or false })
        save_preset(app)
      end
      r.ImGui_PopID(ctx)
    end
    r.ImGui_EndChild(ctx)
  end

  r.ImGui_Dummy(ctx, 0, UIScale.round(4))
  if r.ImGui_Button(ctx, "Close", UIScale.round(80), 0) then r.ImGui_CloseCurrentPopup(ctx) end
  r.ImGui_EndPopup(ctx)
end

local SOUND_ROLES = {
  { key = "warn", label = "Warning tick" },
  { key = "count_in", label = "Count-in" },
  { key = "go", label = "Hit on the change" },
  { key = "accent", label = "Downbeat accent" },
  { key = "beat", label = "Plain beat" }
}

-- A dialog rather than five nested menus: this is set up once, sitting down.
local function draw_sounds_popup(app, preset)
  local ctx = app.ctx
  if state.sounds_open then
    r.ImGui_OpenPopup(ctx, "Cue sounds")
    state.sounds_open = false
  end
  if not r.ImGui_BeginPopup(ctx, "Cue sounds") then return end
  local files = Audio.sounds()
  r.ImGui_Text(ctx, "Cue sounds")
  r.ImGui_TextColored(ctx, Theme.colors.text_dim,
    #files > 0 and string.format("%d wav file%s in your sounds folder", #files, #files == 1 and "" or "s")
    or "Put .wav files in the sounds folder and they turn up here")
  r.ImGui_Dummy(ctx, 0, UIScale.round(4))

  -- What the effect in the audio thread says it managed to load. This is the
  -- only window onto whether a chosen sample is really there.
  local report = Audio.report()
  if report and report.version == 0 then
    r.ImGui_TextColored(ctx, Theme.colors.danger,
      "The cue effect is not running - switch Play cues on, or reload it below")
  elseif report and report.version < Audio.JSFX_VERSION then
    r.ImGui_TextColored(ctx, Theme.colors.warning,
      "An older build of the effect is loaded - press Reload the effect")
  elseif report then
    r.ImGui_TextColored(ctx, Theme.colors.text_dim,
      string.format("Effect v%d running at %d Hz, %d sound%s in shared memory",
        report.version, report.srate or 0, report.slots, report.slots == 1 and "" or "s"))
  end
  r.ImGui_Dummy(ctx, 0, UIScale.round(4))

  for _, role in ipairs(SOUND_ROLES) do
    local current = tostring(preset.sounds[role.key] or "")
    local shown = current ~= "" and current or "Built-in tone"
    r.ImGui_SetNextItemWidth(ctx, UIScale.round(220))
    if r.ImGui_BeginCombo(ctx, role.label, shown) then
      if r.ImGui_Selectable(ctx, "Built-in tone", current == "") then
        preset.sounds[role.key] = ""
        save_preset(app)
        -- The effect is built from the sounds in use, so choosing one is what
        -- makes it get rebuilt.
        Audio.sync(preset)
      end
      for _, entry in ipairs(files) do
        if r.ImGui_Selectable(ctx, entry.name, current == entry.name) then
          preset.sounds[role.key] = entry.name
          save_preset(app)
          Audio.sync(preset)
        end
      end
      r.ImGui_EndCombo(ctx)
    end
    if current ~= "" then
      -- Reported by the side that did the reading, so a file that could not be
      -- read says why instead of just failing to make a noise.
      local info = Audio.upload_info(current)
      r.ImGui_SameLine(ctx)
      if not info then
        r.ImGui_TextColored(ctx, Theme.colors.text_dim, "not sent yet")
      elseif info.error then
        r.ImGui_TextColored(ctx, Theme.colors.danger, tostring(info.error))
      else
        r.ImGui_TextColored(ctx, Theme.colors.text_dim,
          string.format("%.2f s at %d Hz", info.frames / math.max(1, info.rate), info.rate))
      end
    end
  end

  r.ImGui_Dummy(ctx, 0, UIScale.round(4))
  if r.ImGui_Button(ctx, "Reload the effect", UIScale.round(140), 0) then
    Audio.ensure_jsfx()
    Audio.reload()
    local _, note = Audio.upload(preset, true)
    app.status = "Cue effect reloaded, " .. tostring(note)
  end
  r.ImGui_SameLine(ctx)
  if r.CF_LocateInExplorer and r.ImGui_Button(ctx, "Open the folder", UIScale.round(130), 0) then
    if r.RecursiveCreateDirectory then r.RecursiveCreateDirectory(Audio.sounds_folder(), 0) end
    r.CF_LocateInExplorer(Audio.sounds_folder())
  end
  if r.CF_LocateInExplorer then r.ImGui_SameLine(ctx) end
  if r.ImGui_Button(ctx, "Rescan", UIScale.round(90), 0) then
    -- Adding a file means writing a new effect and reloading it, because JSFX
    -- decides which files it can read at compile time.
    local changed = Audio.sync(preset, true)
    app.status = changed and "Cue sounds reloaded" or "No change in the sounds folder"
  end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "Close", UIScale.round(80), 0) then r.ImGui_CloseCurrentPopup(ctx) end
  r.ImGui_EndPopup(ctx)
end

local function draw_export_popup(app, preset)
  local ctx = app.ctx
  if state.export_open then
    r.ImGui_OpenPopup(ctx, "Save cue preset")
    state.export_open = false
  end
  if not r.ImGui_BeginPopup(ctx, "Save cue preset") then return end
  r.ImGui_Text(ctx, "Save this setup to reuse on another song")
  r.ImGui_SetNextItemWidth(ctx, UIScale.round(260))
  local changed, value = r.ImGui_InputTextWithHint(ctx, "Name", "Live set - my band", state.export_name or "")
  if changed then state.export_name = value end
  r.ImGui_Dummy(ctx, 0, UIScale.round(4))
  local can_save = tostring(state.export_name or "") ~= ""
  if not can_save then r.ImGui_BeginDisabled(ctx, true) end
  if r.ImGui_Button(ctx, "Save", UIScale.round(80), 0) and can_save then
    preset.name = state.export_name
    local ok, result = Presets.export(preset, state.export_name)
    app.status = ok and ("Saved cue preset: " .. tostring(result)) or tostring(result)
    save_preset(app)
    r.ImGui_CloseCurrentPopup(ctx)
  end
  if not can_save then r.ImGui_EndDisabled(ctx) end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "Cancel", UIScale.round(80), 0) then r.ImGui_CloseCurrentPopup(ctx) end
  r.ImGui_EndPopup(ctx)
end

--------------------------------------------------------------------------------
-- module contract
--------------------------------------------------------------------------------

function M.init(app)
  user_defaults(app)
  Engine.invalidate()
  state.previous = nil
  state.preset = nil
  state.preset_project = nil
end

-- Reading the project and pushing the schedule happens here rather than in the
-- draw: update runs for every loaded module, so the cues keep time while you
-- are looking at Media Browser. The draw uses whatever this left behind.
function M.update(app)
  local preset = ensure_preset(app)
  local now = Engine.read({ warn_bars = preset.cues.warn_bars }, state.previous)
  state.previous = now
  local here = Presets.section(preset, now.section and now.section.name or "")
  if here.warn_bars ~= preset.cues.warn_bars then
    now.stage = Engine.stage(now, here.warn_bars)
  end
  now.warn_bars = here.warn_bars
  now.label = here.label
  state.now = now
  if now.entered and preset.cues.flash_on_change then
    state.flash_at = r.time_precise and r.time_precise() or os.clock()
  end
  if preset.audio.enabled then Audio.push(Engine, now, preset) end
end

function M.draw(app)
  local ctx = app.ctx
  local preset = ensure_preset(app)
  local avail_w, avail_h = r.ImGui_GetContentRegionAvail(ctx)
  avail_w = math.max(UIScale.round(80), tonumber(avail_w) or UIScale.round(240))
  avail_h = math.max(UIScale.round(80), tonumber(avail_h) or UIScale.round(240))

  -- update() ran first and left this frame's reading behind. It is taken here
  -- and cleared: a reading is good for the frame it was made in and no longer,
  -- and drawing must not quietly show the previous one if update did not run.
  if not state.now then M.update(app) end
  local now = state.now
  state.now = nil
  local here = { label = now.label, warn_bars = now.warn_bars }

  local color = stage_color(now.stage)
  local flashing = false
  if state.flash_at then
    local elapsed = (r.time_precise and r.time_precise() or os.clock()) - state.flash_at
    if elapsed < 0.5 then flashing = true else state.flash_at = nil end
  end

  -- The layout is measured before anything is drawn, because the canvas has no
  -- scrollbar: a block that turns out too tall does not get clipped, it takes
  -- whatever sat below it with it.
  local pad = UIScale.round(10)
  local gap = UIScale.round(8)
  local line_h = r.ImGui_GetTextLineHeight(ctx)
  local dots_h = preset.display.beats and UIScale.round(10) or 0
  local progress_h = preset.display.progress and UIScale.round(6) or 0
  local grid_h = UIScale.round(38)
  local wide = avail_w >= UIScale.round(340)
  local show_grid = preset.display.details and wide

  local below = (progress_h > 0 and progress_h + gap or 0)
    + (dots_h > 0 and dots_h + gap or 0)
    + line_h + gap            -- bar and beat
    + UIScale.px(1) + gap     -- the rule
    + line_h + gap            -- what is next
    + line_h                  -- how far off it is
    + (show_grid and (gap + grid_h) or 0)
  local budget = avail_h - below - pad * 2
  local section_h = math.max(UIScale.round(22), math.min(UIScale.round(110), budget - gap))
  -- The space under the name grows with the name. Eight pixels sits well under
  -- a 24px section title and looks like a collision under a 110px one, which is
  -- the size this panel reaches the moment it is given any width at all.
  local name_gap = math.max(gap, math.floor(section_h * 0.2))
  if section_h + name_gap > budget then
    section_h = math.max(UIScale.round(22), budget - name_gap)
  end
  local total = section_h + name_gap + below

  local x, y = r.ImGui_GetCursorScreenPos(ctx)
  local draw_list = r.ImGui_GetWindowDrawList(ctx)
  -- One invisible item over the whole surface: it is what the right-click menu
  -- hangs off, and it keeps the module claiming the space it just measured.
  r.ImGui_InvisibleButton(ctx, "##cue_surface", avail_w, math.min(avail_h, total + pad * 2))
  local hovered = r.ImGui_IsItemHovered(ctx)

  if flashing then
    r.ImGui_DrawList_AddRect(draw_list, x + UIScale.px(1), y + UIScale.px(1),
      x + avail_w - UIScale.px(1), y + math.min(avail_h, total + pad * 2) - UIScale.px(1),
      GO, UIScale.px(6), 0, UIScale.px(2))
  end

  local cx = x + pad
  local width = avail_w - pad * 2
  local cy = y + pad

  if now.section_count == 0 then
    cy = cy + big_text(ctx, draw_list, "NO SECTIONS", Theme.colors.text_dim, cx, cy, width, section_h) + name_gap
    centered(ctx, draw_list, "Mark the song up with regions or markers", Theme.colors.text_dim, cx, cy, width)
  else
    local tint = preset.display.section_color and section_color(now.section) or nil
    local name_color = Theme.colors.text
    if tint then name_color = Theme.text_for_background(Theme.colors.window_bg, tint) end
    if flashing then name_color = GO end

    local name = now.section and here.label or ""
    if name == "" then name = now.section and "(unnamed)" or "-" end
    -- The band it reports back, not the one that was measured: a font is not
    -- obliged to be exactly the size it was asked for.
    local band = big_text(ctx, draw_list, name:upper(), name_color, cx, cy, width, section_h)
    cy = cy + band + name_gap

    if progress_h > 0 then
      local into = tonumber(now.bars_into_section) or 0
      local left = tonumber(now.bars_left_in_section) or 0
      local span = into + left
      local fraction = span > 0 and math.max(0, math.min(1, into / span)) or 0
      draw_progress(draw_list, fraction, tint or color, cx, cy, width, progress_h)
      cy = cy + progress_h + gap
    end

    if preset.display.beats then
      draw_beats(ctx, draw_list, now, color, cx, cy, width)
      cy = cy + dots_h + gap
    end

    local where = string.format("BAR %d  \u{00b7}  BEAT %d/%d", now.bar, now.beat,
      math.floor(tonumber(now.beats_per_bar) or 4))
    if not now.playing and not now.recording then where = where .. "  \u{00b7}  CURSOR" end
    centered(ctx, draw_list, where, Theme.colors.text_dim, cx, cy, width)
    cy = cy + line_h + gap

    r.ImGui_DrawList_AddLine(draw_list, cx, cy, cx + width, cy, Theme.colors.border, UIScale.px(1))
    cy = cy + UIScale.px(1) + gap

    local next_name = now.next_section
      and Presets.section(preset, tostring(now.next_section.name or "")).label or ""
    if next_name == "" then next_name = now.next_section and "(unnamed)" or "END OF SONG" end
    centered(ctx, draw_list, "NEXT  \u{00b7}  " .. next_name:upper(),
      now.next_section and color or Theme.colors.text_dim, cx, cy, width)
    cy = cy + line_h + gap

    local phrase = bars_phrase(now.bars_to_change)
    if now.stage == "go" then phrase = "GO" end
    centered(ctx, draw_list, phrase, now.stage == "run" and Theme.colors.text_dim or color, cx, cy, width)
    cy = cy + line_h

    local ahead_label, ahead_value = "AHEAD", "-"
    if now.next_change and now.bars_to_next_change then
      local bars = math.ceil(now.bars_to_next_change - 0.0001)
      ahead_label = bars == 1 and "IN 1 BAR" or string.format("IN %d BARS", bars)
      ahead_value = now.next_change.tempo_changes
        and string.format("%g BPM", math.floor(now.next_change.tempo * 10 + 0.5) / 10)
        or string.format("%d/%d", now.next_change.timesig_num, now.next_change.timesig_den)
    end

    if show_grid then
      cy = cy + gap
      local cells = {
        { "SECTION", string.format("%d/%d", now.section_index or 0, now.section_count) },
        { "BPM", string.format("%g", math.floor((tonumber(now.tempo) or 0) * 10 + 0.5) / 10) },
        { "SIG", signature_text(now) },
        -- Not called NEXT: two lines up, NEXT already means the next section,
        -- and the same word for two different things on one screen is the sort
        -- of thing you only misread once, on stage.
        { ahead_label, ahead_value }
      }
      local cell_gap = UIScale.round(5)
      local cell_w = (width - cell_gap * 3) / 4
      for index, cell in ipairs(cells) do
        draw_cell(ctx, draw_list, cell[1], cell[2], cx + (index - 1) * (cell_w + cell_gap), cy, cell_w, grid_h)
      end
    end
  end

  if hovered and now.next_change and now.bars_to_next_change then
    local what = now.next_change.tempo_changes and string.format("%g BPM", now.next_change.tempo)
      or string.format("%d/%d", now.next_change.timesig_num, now.next_change.timesig_den)
    r.ImGui_SetTooltip(ctx, string.format("%s in %d bars\nRight-click for the cue settings",
      what, math.ceil(now.bars_to_next_change - 0.0001)))
  end

  draw_settings_popup(app, preset)
  draw_sections_popup(app, preset)
  draw_sounds_popup(app, preset)
  draw_export_popup(app, preset)
end

function M.shutdown(app)
  Audio.silence()
  state.previous = nil
  state.flash_at = nil
  state.now = nil
end

function M.handle_action(app, verb)
  verb = tostring(verb or ""):lower()
  if verb == "refresh" then
    Engine.invalidate()
    state.previous = nil
    state.preset = nil
    state.preset_project = nil
  elseif verb == "sections" then
    state.sections_open = true
  else
    app.status = "Cue does not know the action: " .. tostring(verb)
  end
end

return M
