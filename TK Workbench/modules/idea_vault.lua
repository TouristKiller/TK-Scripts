local r = reaper
local Theme = require("core.theme")
local UI = require("core.ui")
local UIScale = require("core.ui_scale")
local Store = require("core.idea_vault_store")

local M = {
  id = "idea_vault",
  title = "Idea Vault",
  icon = "IDV",
  version = "0.1.1"
}

local state = {
  ideas = {},
  dirty = true,
  search = "",
  selected = nil,
  preview = nil,
  preview_source = nil,
  preview_name = nil,
  tempo_lock = true,
  match_tempo = false,
  loop = false,
  fixed_h = nil,
  capture_open = false,
  capture = { name = "", description = "", tags = "", render = true },
  rename_open = false,
  rename_text = "",
  rename_target = nil
}

--------------------------------------------------------------------------------
-- data
--------------------------------------------------------------------------------

local function refresh()
  state.ideas = Store.list()
  state.dirty = false
  -- The selected idea is a table from the previous list, so it has to be found
  -- again by name or the footer keeps describing something that no longer exists.
  if state.selected then
    local wanted = state.selected.name
    state.selected = nil
    for _, idea in ipairs(state.ideas) do
      if idea.name == wanted then state.selected = idea; break end
    end
  end
end

local function visible_ideas()
  local list = {}
  for _, idea in ipairs(state.ideas) do
    if Store.matches(idea, state.search) then list[#list + 1] = idea end
  end
  return list
end

local function format_time(seconds)
  seconds = math.max(0, math.floor(tonumber(seconds) or 0))
  return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

local function summary_line(idea)
  local parts = {}
  local bpm = tonumber(idea.bpm)
  if bpm and bpm > 0 then parts[#parts + 1] = string.format("%g BPM", bpm) end
  local num, den = tonumber(idea.timesig_num), tonumber(idea.timesig_den)
  if num and den and num > 0 and den > 0 then
    parts[#parts + 1] = string.format("%d/%d", num, den)
  end
  if (tonumber(idea.duration) or 0) > 0 then parts[#parts + 1] = format_time(idea.duration) end
  local count = tonumber(idea.track_count) or 0
  if count > 0 then parts[#parts + 1] = count == 1 and "1 track" or (count .. " tracks") end
  if not idea.has_preview then parts[#parts + 1] = "no preview" end
  return table.concat(parts, "  ·  ")
end

--------------------------------------------------------------------------------
-- preview playback
--------------------------------------------------------------------------------

local function stop_preview()
  if state.preview and r.CF_Preview_Stop then r.CF_Preview_Stop(state.preview) end
  if state.preview_source and r.PCM_Source_Destroy then r.PCM_Source_Destroy(state.preview_source) end
  state.preview = nil
  state.preview_source = nil
  state.preview_name = nil
end

local function playback_rate(idea)
  if not state.tempo_lock then return 1.0 end
  return Store.preview_rate(idea, r.Master_GetTempo())
end

-- D_PLAYRATE on a CF preview keeps the pitch where it is, so locking a 96 BPM
-- idea into a 120 BPM song stretches it into the grid without transposing it.
-- That is the whole reason the sidecar carries a tempo.
local function play(app, idea)
  stop_preview()
  if not idea or not idea.has_preview then
    app.status = "This idea has no preview file"
    return
  end
  if not r.CF_CreatePreview or not r.CF_Preview_Play then
    app.status = "Previewing needs the SWS extension"
    return
  end
  local source = r.PCM_Source_CreateFromFile(idea.preview_path)
  if not source then
    app.status = "Could not open " .. tostring(idea.preview)
    return
  end
  local preview = r.CF_CreatePreview(source)
  if not preview then
    if r.PCM_Source_Destroy then r.PCM_Source_Destroy(source) end
    app.status = "Could not start the preview"
    return
  end
  if r.CF_Preview_SetValue then
    r.CF_Preview_SetValue(preview, "D_VOLUME", 1.0)
    r.CF_Preview_SetValue(preview, "D_PLAYRATE", playback_rate(idea))
    r.CF_Preview_SetValue(preview, "B_LOOP", state.loop and 1 or 0)
  end
  r.CF_Preview_Play(preview)
  state.preview = preview
  state.preview_source = source
  state.preview_name = idea.name
end

local function preview_position()
  if not state.preview or not r.CF_Preview_GetValue then return 0 end
  local ok, value = r.CF_Preview_GetValue(state.preview, "D_POSITION")
  if not ok then return 0 end
  return tonumber(value) or 0
end

local function playing_idea()
  if not state.preview or not state.preview_name then return nil end
  for _, idea in ipairs(state.ideas) do
    if idea.name == state.preview_name then return idea end
  end
  return nil
end

--------------------------------------------------------------------------------
-- actions
--------------------------------------------------------------------------------

-- Whether the tempo is about to change has to be read before the load, because
-- afterwards the project already sits at the idea's tempo and nothing differs.
local function load_idea(app, idea)
  local changing = state.match_tempo and Store.tempo_differs(idea, r.Master_GetTempo())
  local ok, err = Store.load(idea, { match_tempo = state.match_tempo })
  if not ok then
    app.status = tostring(err or "Could not load the idea")
    return
  end
  app.status = changing
    and string.format("Loaded %s and set the project to %g BPM", tostring(idea.name), tonumber(idea.bpm) or 0)
    or ("Loaded " .. tostring(idea.name))
end

local function do_capture(app)
  local idea, warning = Store.capture({
    name = state.capture.name,
    description = state.capture.description,
    tags = (function()
      local tags = {}
      for tag in tostring(state.capture.tags or ""):gmatch("[^%s,]+") do tags[#tags + 1] = tag end
      return tags
    end)(),
    render = state.capture.render
  })
  if not idea then
    app.status = tostring(warning or "The capture failed")
    return false
  end
  state.dirty = true
  refresh()
  for _, entry in ipairs(state.ideas) do
    if entry.name == idea.name then state.selected = entry; break end
  end
  app.status = warning
    and ("Saved " .. idea.name .. " without a preview: " .. tostring(warning))
    or ("Captured " .. idea.name)
  return true
end

local function begin_capture()
  local track = r.GetSelectedTrack(0, 0)
  local name = ""
  if track then
    local _, track_name = r.GetTrackName(track)
    track_name = tostring(track_name or ""):match("^%s*(.-)%s*$")
    if track_name ~= "" and not track_name:match("^Track%s+%d+$") then name = track_name end
  end
  state.capture.name = name
  state.capture.description = ""
  state.capture.tags = ""
  state.capture.render = true
  state.capture_open = true
end

local function reveal(idea)
  local path = idea and (idea.preview_path or idea.template_path)
  if not path then return end
  if r.CF_LocateInExplorer then r.CF_LocateInExplorer(path) end
end

--------------------------------------------------------------------------------
-- popups
--------------------------------------------------------------------------------

local FORMAT_HELP =
  "Previews follow the project's render format unless you pin one here.\n\n"
  .. "For WavPack previews: set the format to WavPack once in REAPER's render\n"
  .. "dialog (or Render Hub), then pin it. Every capture uses it from then on,\n"
  .. "in every project, so your vault stays one consistent format."

-- The vault never builds a render format config itself - that blob differs per
-- codec and guessing it is how you end up with silent files. The user dials the
-- format in where REAPER already offers it, and this only copies the result.
local function draw_format_row(app)
  local ctx = app.ctx
  local pinned = Store.format_name()
  if pinned then
    r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Preview format: " .. pinned .. " (pinned)")
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, FORMAT_HELP) end
    r.ImGui_SameLine(ctx)
    if r.ImGui_SmallButton(ctx, "Follow project") then
      Store.follow_project_format()
      app.status = "Previews follow the project's render format again"
    end
    return
  end
  local project_format = Store.project_format_name()
  r.ImGui_TextColored(ctx, Theme.colors.text_dim,
    "Preview format: follows the project" .. (project_format and (" (" .. project_format .. ")") or ""))
  if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, FORMAT_HELP) end
  r.ImGui_SameLine(ctx)
  if r.ImGui_SmallButton(ctx, "Pin this format") then
    local ok, err = Store.capture_format_from_project()
    app.status = ok and ("Previews are pinned to " .. tostring(Store.format_name()))
                     or tostring(err or "Could not read the project's render format")
  end
end

local function draw_capture_popup(app)
  local ctx = app.ctx
  if state.capture_open then
    r.ImGui_OpenPopup(ctx, "Capture idea")
    state.capture_open = false
  end
  if not r.ImGui_BeginPopup(ctx, "Capture idea") then return end
  r.ImGui_Text(ctx, "Saves the selected track as a template plus a preview.")
  r.ImGui_Dummy(ctx, 0, UIScale.round(4))

  r.ImGui_SetNextItemWidth(ctx, UIScale.round(280))
  local changed, value = r.ImGui_InputText(ctx, "Name", state.capture.name or "")
  if changed then state.capture.name = value end

  r.ImGui_SetNextItemWidth(ctx, UIScale.round(280))
  changed, value = r.ImGui_InputText(ctx, "Description", state.capture.description or "")
  if changed then state.capture.description = value end

  r.ImGui_SetNextItemWidth(ctx, UIScale.round(280))
  changed, value = r.ImGui_InputText(ctx, "Tags", state.capture.tags or "")
  if changed then state.capture.tags = value end

  changed, value = r.ImGui_Checkbox(ctx, "Render a preview", state.capture.render ~= false)
  if changed then state.capture.render = value end

  draw_format_row(app)

  r.ImGui_Dummy(ctx, 0, UIScale.round(4))
  local button_w = UIScale.text_button_w(ctx, "Capture", 80)
  local has_track = r.GetSelectedTrack(0, 0) ~= nil
  if not has_track and r.ImGui_BeginDisabled then r.ImGui_BeginDisabled(ctx, true) end
  if r.ImGui_Button(ctx, "Capture", button_w, 0) and has_track then
    if do_capture(app) then r.ImGui_CloseCurrentPopup(ctx) end
  end
  if not has_track and r.ImGui_EndDisabled then r.ImGui_EndDisabled(ctx) end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "Cancel", button_w, 0) then r.ImGui_CloseCurrentPopup(ctx) end
  if not has_track then
    r.ImGui_TextColored(ctx, Theme.colors.warning, "Select a track first")
  end
  r.ImGui_EndPopup(ctx)
end

local function draw_rename_popup(app)
  local ctx = app.ctx
  if state.rename_open then
    r.ImGui_OpenPopup(ctx, "Rename idea")
    state.rename_open = false
  end
  if not r.ImGui_BeginPopup(ctx, "Rename idea") then return end
  r.ImGui_SetNextItemWidth(ctx, UIScale.round(260))
  local changed, value = r.ImGui_InputText(ctx, "Name", state.rename_text or "")
  if changed then state.rename_text = value end
  local button_w = UIScale.text_button_w(ctx, "Cancel", 70)
  local can_save = state.rename_target ~= nil and tostring(state.rename_text or "") ~= ""
  if not can_save and r.ImGui_BeginDisabled then r.ImGui_BeginDisabled(ctx, true) end
  if r.ImGui_Button(ctx, "Save", button_w, 0) and can_save then
    if state.preview_name == state.rename_target.name then stop_preview() end
    local ok = Store.rename(state.rename_target, state.rename_text)
    app.status = ok and "Renamed idea" or "Could not rename the idea"
    state.dirty = true
    r.ImGui_CloseCurrentPopup(ctx)
  end
  if not can_save and r.ImGui_EndDisabled then r.ImGui_EndDisabled(ctx) end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "Cancel", button_w, 0) then r.ImGui_CloseCurrentPopup(ctx) end
  r.ImGui_EndPopup(ctx)
end

--------------------------------------------------------------------------------
-- drawing
--------------------------------------------------------------------------------

local function draw_header(app)
  local ctx = app.ctx
  local button_w = UIScale.text_button_w(ctx, "Capture", 80)
  local avail = r.ImGui_GetContentRegionAvail(ctx) or UIScale.round(320)
  local spacing = UIScale.gap(6)
  local search_w = math.max(UIScale.round(80), avail - button_w * 2 - spacing * 2)
  local changed, value = UI.search_input(ctx, "##idea_search", "Search ideas", state.search, search_w)
  if changed then state.search = value end
  r.ImGui_SameLine(ctx, 0, spacing)
  if r.ImGui_Button(ctx, "Capture", button_w, 0) then begin_capture() end
  if r.ImGui_IsItemHovered(ctx) then
    r.ImGui_SetTooltip(ctx, "Save the selected track as a template plus a preview")
  end
  r.ImGui_SameLine(ctx, 0, spacing)
  if r.ImGui_Button(ctx, "Refresh", button_w, 0) then state.dirty = true end
end

local function draw_row(app, idea, width, row_h)
  local ctx = app.ctx
  local selected = state.selected == idea
  local playing = state.preview ~= nil and state.preview_name == idea.name
  r.ImGui_PushID(ctx, idea.name)
  local clicked = r.ImGui_InvisibleButton(ctx, "##idea_card", width, row_h)
  local hovered = r.ImGui_IsItemHovered(ctx)
  local double = hovered and r.ImGui_IsMouseDoubleClicked(ctx, 0)
  local x, y = r.ImGui_GetItemRectMin(ctx)
  local draw_list = r.ImGui_GetWindowDrawList(ctx)

  local bg = selected and 0x7AA2F730 or (hovered and 0xFFFFFF12 or 0x00000000)
  if bg ~= 0x00000000 then
    r.ImGui_DrawList_AddRectFilled(draw_list, x, y + UIScale.round(2), x + width, y + row_h - UIScale.round(2), bg, UIScale.px(5))
  end
  r.ImGui_DrawList_AddRect(draw_list, x, y + UIScale.round(2), x + width, y + row_h - UIScale.round(2),
    selected and Theme.colors.accent or Theme.colors.border, UIScale.px(5), 0,
    selected and UIScale.px(1.4) or UIScale.px(0.7))

  -- Play badge on the left, its own hit area so clicking the row still selects.
  local badge_r = UIScale.round(11)
  local bcx = x + UIScale.round(9) + badge_r
  local bcy = y + row_h * 0.5
  local mouse_x, mouse_y = r.ImGui_GetMousePos(ctx)
  local badge_reach = badge_r + UIScale.round(2)
  local badge_hot = hovered
    and ((mouse_x - bcx) ^ 2 + (mouse_y - bcy) ^ 2) <= badge_reach ^ 2
  r.ImGui_DrawList_AddCircleFilled(draw_list, bcx, bcy, badge_r,
    playing and Theme.colors.accent or Theme.colors.frame_bg, 24)
  r.ImGui_DrawList_AddCircle(draw_list, bcx, bcy, badge_r,
    (badge_hot or playing) and Theme.colors.accent or Theme.colors.border, 24, UIScale.px(1))
  local glyph = playing and Theme.colors.text or (idea.has_preview and Theme.colors.text or Theme.colors.text_dim)
  if playing then
    local bar = UIScale.round(3)
    r.ImGui_DrawList_AddRectFilled(draw_list, bcx - bar - UIScale.px(1), bcy - UIScale.round(5), bcx - UIScale.px(1), bcy + UIScale.round(5), glyph)
    r.ImGui_DrawList_AddRectFilled(draw_list, bcx + UIScale.px(1), bcy - UIScale.round(5), bcx + bar + UIScale.px(1), bcy + UIScale.round(5), glyph)
  else
    r.ImGui_DrawList_AddTriangleFilled(draw_list,
      bcx - UIScale.round(3), bcy - UIScale.round(5),
      bcx - UIScale.round(3), bcy + UIScale.round(5),
      bcx + UIScale.round(6), bcy, glyph)
  end

  local text_x = bcx + badge_r + UIScale.round(9)
  r.ImGui_DrawList_PushClipRect(draw_list, text_x, y, x + width - UIScale.round(8), y + row_h, true)
  r.ImGui_DrawList_AddText(draw_list, text_x, y + UIScale.round(7), Theme.colors.text, tostring(idea.name or ""))
  local second = tostring(idea.description or "")
  if second == "" then second = summary_line(idea) end
  r.ImGui_DrawList_AddText(draw_list, text_x, y + UIScale.round(26), Theme.colors.text_dim, second)
  r.ImGui_DrawList_PopClipRect(draw_list)

  if clicked then
    state.selected = idea
    if badge_hot then
      if playing then stop_preview() else play(app, idea) end
    end
  end
  if double and not badge_hot then load_idea(app, idea) end
  if hovered and not badge_hot then
    r.ImGui_SetTooltip(ctx, tostring(idea.name) .. "\n" .. summary_line(idea)
      .. (idea.description ~= "" and ("\n\n" .. idea.description) or "")
      .. "\n\nDouble-click to load into the project")
  end

  if r.ImGui_BeginPopupContextItem(ctx, "##idea_context") then
    state.selected = idea
    if r.ImGui_MenuItem(ctx, playing and "Stop" or "Play") then
      if playing then stop_preview() else play(app, idea) end
    end
    if r.ImGui_MenuItem(ctx, "Load into project") then load_idea(app, idea) end
    if r.ImGui_MenuItem(ctx, "Rename") then
      state.rename_target = idea
      state.rename_text = tostring(idea.name or "")
      state.rename_open = true
    end
    if r.CF_LocateInExplorer and r.ImGui_MenuItem(ctx, "Show in explorer") then reveal(idea) end
    if r.ImGui_MenuItem(ctx, "Delete") then
      if playing then stop_preview() end
      Store.delete(idea)
      if state.selected == idea then state.selected = nil end
      state.dirty = true
      app.status = "Deleted " .. tostring(idea.name)
    end
    r.ImGui_EndPopup(ctx)
  end
  r.ImGui_PopID(ctx)
end

local function draw_list(app, height)
  local ctx = app.ctx
  if not r.ImGui_BeginChild(ctx, "##idea_vault_list", 0, height, 0) then return end
  local list = visible_ideas()
  if #list == 0 then
    r.ImGui_Dummy(ctx, 0, UIScale.round(8))
    r.ImGui_TextColored(ctx, Theme.colors.text_dim,
      #state.ideas == 0 and "No ideas yet - select a track and press Capture."
                        or "Nothing matches this search.")
  else
    local width = math.max(UIScale.round(120), r.ImGui_GetContentRegionAvail(ctx) or UIScale.round(200))
    local row_h = UIScale.round(48)
    for _, idea in ipairs(list) do draw_row(app, idea, width, row_h) end
  end
  r.ImGui_EndChild(ctx)
end

local function draw_footer(app)
  local ctx = app.ctx
  local idea = state.selected
  r.ImGui_Dummy(ctx, 0, UIScale.round(2))
  if not idea then
    r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Select an idea to preview or load it.")
    return
  end

  r.ImGui_Text(ctx, tostring(idea.name or ""))
  r.ImGui_TextColored(ctx, Theme.colors.text_dim, summary_line(idea))

  -- Fitting is the normal case and reads as information; bending the project is
  -- the one that changes something outside this panel, so only that is coloured
  -- as something to notice.
  local project_bpm = r.Master_GetTempo()
  if Store.tempo_differs(idea, project_bpm) then
    if state.match_tempo then
      r.ImGui_TextColored(ctx, Theme.colors.warning,
        string.format("Loading sets the whole project to %g BPM.", tonumber(idea.bpm) or 0))
    else
      r.ImGui_TextColored(ctx, Theme.colors.text_dim,
        string.format("Recorded at %g BPM - it will be fitted to the project's %g.",
          tonumber(idea.bpm) or 0, project_bpm))
    end
  end

  local playing = state.preview ~= nil and state.preview_name == idea.name
  local button_w = UIScale.text_button_w(ctx, "Load into project", 120)
  local small_w = UIScale.text_button_w(ctx, "Stop", 64)
  if r.ImGui_Button(ctx, playing and "Stop" or "Play", small_w, 0) then
    if playing then stop_preview() else play(app, idea) end
  end
  r.ImGui_SameLine(ctx)

  local changed, value = r.ImGui_Checkbox(ctx, "Lock to tempo", state.tempo_lock)
  if changed then
    state.tempo_lock = value
    local current = playing_idea()
    if current and state.preview and r.CF_Preview_SetValue then
      r.CF_Preview_SetValue(state.preview, "D_PLAYRATE", playback_rate(current))
    end
  end
  if r.ImGui_IsItemHovered(ctx) then
    local rate = Store.preview_rate(idea, r.Master_GetTempo())
    r.ImGui_SetTooltip(ctx, string.format(
      "Plays the preview at the project tempo without transposing it.\nRecorded at %g BPM, project is at %g BPM, so rate %.3f.",
      tonumber(idea.bpm) or 0, r.Master_GetTempo(), rate))
  end
  r.ImGui_SameLine(ctx)
  changed, value = r.ImGui_Checkbox(ctx, "Loop", state.loop)
  if changed then
    state.loop = value
    if state.preview and r.CF_Preview_SetValue then
      r.CF_Preview_SetValue(state.preview, "B_LOOP", state.loop and 1 or 0)
    end
  end
  -- Two rows rather than one: hearing it, then loading it. Five controls chained
  -- on a single line came to over 500px, and a panel narrower than that pushed
  -- the last one off the right edge - where the canvas offers nothing to scroll
  -- with, so the control was simply gone.
  if r.ImGui_Button(ctx, "Load into project", button_w, 0) then load_idea(app, idea) end
  r.ImGui_SameLine(ctx)
  changed, value = r.ImGui_Checkbox(ctx, "Set project tempo to the idea's", state.match_tempo)
  if changed then state.match_tempo = value end
  if r.ImGui_IsItemHovered(ctx) then
    r.ImGui_SetTooltip(ctx,
      "The exception, not the rule: items already fit themselves to the project\n"
      .. "they land in. Tick this to bend the project to the idea instead, which is\n"
      .. "what you want when a new piece starts from one. It changes the whole\n"
      .. "project, and it is one undo step together with the load.")
  end
end

--------------------------------------------------------------------------------
-- module contract
--------------------------------------------------------------------------------

function M.init(app)
  state.dirty = true
end

function M.update(app)
  -- A preview that ran off its end leaves a handle that reports a frozen
  -- position, which would keep the row showing a stop button forever.
  local idea = playing_idea()
  if not idea or state.loop then return end
  local duration = tonumber(idea.duration) or 0
  if duration <= 0 then return end
  local rate = playback_rate(idea)
  if rate > 0 and preview_position() >= duration / rate - 0.05 then stop_preview() end
end

function M.draw(app)
  local ctx = app.ctx
  if state.dirty then refresh() end

  local start_y = r.ImGui_GetCursorPosY(ctx)
  local _, avail_h = r.ImGui_GetContentRegionAvail(ctx)
  avail_h = avail_h or UIScale.round(320)

  -- One flexible list, everything else measured rather than estimated: the
  -- canvas has no scrollbar, so an over-tall layout would just lose its footer.
  local list_h = math.max(UIScale.round(60), avail_h - (state.fixed_h or UIScale.round(150)))

  draw_header(app)
  r.ImGui_Dummy(ctx, 0, UIScale.round(4))
  draw_list(app, list_h)
  draw_footer(app)
  draw_capture_popup(app)
  draw_rename_popup(app)

  local used = r.ImGui_GetCursorPosY(ctx) - start_y
  state.fixed_h = math.max(UIScale.round(40), used - list_h)
end

function M.shutdown(app)
  stop_preview()
end

function M.handle_action(app, verb)
  verb = tostring(verb or ""):lower()
  if verb == "capture" then
    begin_capture()
  elseif verb == "capture_now" then
    begin_capture()
    state.capture_open = false
    do_capture(app)
  elseif verb == "stop" then
    stop_preview()
  elseif verb == "refresh" then
    state.dirty = true
  else
    app.status = "Idea Vault does not know the action: " .. tostring(verb)
  end
end

return M
