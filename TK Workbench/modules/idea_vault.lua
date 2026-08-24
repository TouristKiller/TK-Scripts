local r = reaper
local Theme = require("core.theme")
local UI = require("core.ui")
local UIScale = require("core.ui_scale")
local Store = require("core.idea_vault_store")

local M = {
  id = "idea_vault",
  title = "Idea Vault",
  icon = "IDV",
  version = "0.1.4"
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
  rename_target = nil,
  pending_delete = nil,
  edit_open = false,
  edit_target = nil,
  edit_description = "",
  edit_tags = "",
  edit_rating = 0,
  view_popup = false,
  -- Filters are per session rather than saved: coming back to a vault that is
  -- still filtered down to four ideas, with no memory of having asked for it,
  -- looks exactly like a vault that has lost everything else.
  tag_filter = {},
  tag_exclude = {},
  untagged = nil,
  -- Marks are kept by name, not by table: refresh() builds new tables for every
  -- idea, and a selection held as references would empty itself every time the
  -- vault is re-read.
  marked = {},
  mark_anchor = nil,
  visible = {},
  bulk_open = false,
  bulk_tags = "",
  tag_rename_open = false,
  tag_rename_from = nil,
  tag_rename_text = "",
  pending_tag_delete = nil
}

local defaults = {
  view = "list",
  tile_size = 150,
  sort_by = "created",
  sort_ascending = false,
  min_rating = 0
}

local function ensure_settings(app)
  app.settings.idea_vault = app.settings.idea_vault or {}
  local settings = app.settings.idea_vault
  local changed = false
  for key, value in pairs(defaults) do
    if settings[key] == nil then settings[key] = value; changed = true end
  end
  if settings.view ~= "compact" and settings.view ~= "tiles" then settings.view = "list" end
  settings.tile_size = math.max(110, math.min(280, math.floor(tonumber(settings.tile_size) or defaults.tile_size)))
  settings.min_rating = math.max(0, math.min(5, math.floor(tonumber(settings.min_rating) or 0)))
  if settings.sort_by ~= "name" and settings.sort_by ~= "rating"
     and settings.sort_by ~= "duration" and settings.sort_by ~= "tag" then
    settings.sort_by = "created"
  end
  settings.sort_ascending = settings.sort_ascending == true
  if changed and app.save_settings then app.save_settings() end
  return settings
end

local function save_settings(app)
  if app.save_settings then app.save_settings() end
end

-- CF_Preview_Stop does not always hand the file back by the time it returns,
-- and Windows will not delete a file that is still open, so a preview stopped
-- half a frame ago can survive its own delete. Whatever is left is retried for
-- about a second before the user hears about it.
local DELETE_RETRY_FRAMES = 60

--------------------------------------------------------------------------------
-- data
--------------------------------------------------------------------------------

local function refresh()
  state.ideas = Store.list()
  state.dirty = false
  -- A mark on an idea that has since been deleted or renamed would keep
  -- counting towards "12 selected" with nothing on screen to account for it.
  local present = {}
  for _, idea in ipairs(state.ideas) do present[idea.name] = true end
  for name in pairs(state.marked) do
    if not present[name] then state.marked[name] = nil end
  end
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

local function filters_active(settings)
  return #state.tag_filter > 0 or #state.tag_exclude > 0 or state.untagged ~= nil
     or (settings and settings.min_rating or 0) > 0
end

local function clear_filters(app, settings)
  state.tag_filter = {}
  state.tag_exclude = {}
  state.untagged = nil
  settings.min_rating = 0
  save_settings(app)
end

local function visible_ideas(settings)
  local list = {}
  local filters = {
    tags = state.tag_filter,
    exclude_tags = state.tag_exclude,
    untagged = state.untagged,
    min_rating = settings and settings.min_rating or 0
  }
  for _, idea in ipairs(state.ideas) do
    if Store.matches(idea, state.search, filters) then list[#list + 1] = idea end
  end
  return Store.sort_ideas(list, settings and settings.sort_by or "created",
                          settings and settings.sort_ascending or false)
end

local function marked_count()
  local count = 0
  for _ in pairs(state.marked) do count = count + 1 end
  return count
end

local function marked_ideas()
  local out = {}
  for _, idea in ipairs(state.ideas) do
    if state.marked[idea.name] then out[#out + 1] = idea end
  end
  return out
end

-- Shift extends from the last card that was clicked, in the order the list is
-- showing - which is why the visible list is kept: sorted by rating, "the ones
-- between these two" means something different than it does sorted by date.
local function mark_range(idea)
  local list = state.visible or {}
  local from, to
  for index, entry in ipairs(list) do
    if entry.name == state.mark_anchor then from = index end
    if entry.name == idea.name then to = index end
  end
  if not from or not to then
    state.marked[idea.name] = true
    return
  end
  if from > to then from, to = to, from end
  for index = from, to do state.marked[list[index].name] = true end
end

local function list_contains(list, value)
  local key = tostring(value):lower()
  for index, entry in ipairs(list) do
    if tostring(entry):lower() == key then return index end
  end
  return nil
end

local function list_without(list, value)
  local out = {}
  local key = tostring(value):lower()
  for _, entry in ipairs(list) do
    if tostring(entry):lower() ~= key then out[#out + 1] = entry end
  end
  return out
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
    -- Split the same way the edit dialog splits, so a tag typed at capture and
    -- the same tag typed later are one tag and not two.
    tags = Store.parse_tags(state.capture.tags),
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
  -- A warning no longer implies there is no preview file: a render that ran but
  -- came out silent leaves one behind, and saying it was not written would send
  -- the user looking for the wrong problem.
  if not warning then
    app.status = "Captured " .. idea.name
  elseif tostring(idea.preview or "") ~= "" then
    app.status = "Captured " .. idea.name .. ": " .. tostring(warning)
  else
    app.status = "Saved " .. idea.name .. " without a preview: " .. tostring(warning)
  end
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

local function begin_edit(idea)
  if not idea then return end
  state.edit_target = idea
  state.edit_description = tostring(idea.description or "")
  state.edit_tags = Store.tags_text(idea)
  state.edit_rating = tonumber(idea.rating) or 0
  state.edit_open = true
end

local function begin_bulk_tag()
  state.bulk_tags = ""
  state.bulk_open = true
end

local function apply_bulk_tags(app, mode)
  local targets = marked_ideas()
  if #targets == 0 then return end
  local changed, failed = Store.tag_ideas(targets, state.bulk_tags, mode)
  local verb = mode == "remove" and "Removed from" or "Added to"
  local message = string.format("%s %d idea%s", verb, changed, changed == 1 and "" or "s")
  if changed == 0 then
    message = mode == "remove" and "None of the selected ideas carried that tag"
                                or "Every selected idea already had that tag"
  end
  if failed > 0 then message = message .. string.format(", %d could not be saved", failed) end
  app.status = message
  state.dirty = true
end

local function reveal(idea)
  local path = idea and (idea.preview_path or idea.template_path)
  if not path then return end
  if r.CF_LocateInExplorer then r.CF_LocateInExplorer(path) end
end

--------------------------------------------------------------------------------
-- stars
--------------------------------------------------------------------------------

local STAR_MAX = 5

-- ImGui's font carries no star glyph, so a star is drawn: ten points around a
-- centre, alternating a long and a short radius, fanned into triangles from
-- that centre.
local function draw_star(draw_list, cx, cy, radius, color)
  local inner = radius * 0.45
  local prev_x, prev_y
  for i = 0, 10 do
    local angle = -math.pi / 2 + i * math.pi / 5
    local reach = (i % 2 == 0) and radius or inner
    local px, py = cx + math.cos(angle) * reach, cy + math.sin(angle) * reach
    if prev_x then
      r.ImGui_DrawList_AddTriangleFilled(draw_list, cx, cy, prev_x, prev_y, px, py, color)
    end
    prev_x, prev_y = px, py
  end
end

-- Only the stars an idea actually has, drawn at a position rather than at the
-- cursor: in a row there is no cursor to speak of, everything is painted into
-- the card. Returns the width it took so a caller can reserve it.
local function stars_width(rating, size)
  rating = math.max(0, math.min(STAR_MAX, math.floor(tonumber(rating) or 0)))
  if rating == 0 then return 0 end
  return rating * size + (rating - 1) * UIScale.round(2)
end

local function draw_stars_at(draw_list, x, y, rating, size, color)
  rating = math.max(0, math.min(STAR_MAX, math.floor(tonumber(rating) or 0)))
  local step = size + UIScale.round(2)
  for i = 1, rating do
    draw_star(draw_list, x + (i - 0.5) * step - UIScale.round(1), y, size * 0.5, color)
  end
end

-- One invisible button over all five, with the star under the mouse deciding
-- the value: five separate buttons put five items in the id stack for something
-- the user reads as one control, and made the gaps between them dead.
local function rating_control(app, id, rating, size)
  local ctx = app.ctx
  rating = math.max(0, math.min(STAR_MAX, math.floor(tonumber(rating) or 0)))
  size = size or UIScale.round(14)
  local step = size + UIScale.round(3)
  local height = size + UIScale.round(4)
  local result = nil
  r.ImGui_PushID(ctx, id)
  local clicked = r.ImGui_InvisibleButton(ctx, "##stars", step * STAR_MAX, height)
  local hovered = r.ImGui_IsItemHovered(ctx)
  local x, y = r.ImGui_GetItemRectMin(ctx)
  local hover_index = nil
  if hovered then
    local mouse_x = r.ImGui_GetMousePos(ctx)
    hover_index = math.floor((mouse_x - x) / step) + 1
    if hover_index < 1 then hover_index = 1 end
    if hover_index > STAR_MAX then hover_index = STAR_MAX end
  end
  local draw_list = r.ImGui_GetWindowDrawList(ctx)
  local shown = hover_index or rating
  for i = 1, STAR_MAX do
    local color = Theme.colors.text_dim
    if i <= shown then color = hover_index and Theme.colors.accent or Theme.colors.text end
    draw_star(draw_list, x + (i - 0.5) * step, y + height * 0.5, size * 0.5, color)
  end
  if hovered then
    r.ImGui_SetTooltip(ctx, hover_index == rating
      and "Click again to clear the rating"
      or string.format("Rate this idea %d out of %d", hover_index or 0, STAR_MAX))
  end
  -- Clicking the star a rating already ends on clears it. Without that there is
  -- no way back to unrated once a star has been given.
  if clicked and hover_index then
    result = (hover_index == rating) and 0 or hover_index
  end
  r.ImGui_PopID(ctx)
  return result
end

local function set_rating(app, idea, rating)
  local ok, err = Store.set_rating(idea, rating)
  if not ok then
    app.status = tostring(err or "Could not save the rating")
    return
  end
  state.dirty = true
  app.status = (idea.rating or 0) > 0
    and string.format("%s: %d star%s", tostring(idea.name), idea.rating, idea.rating == 1 and "" or "s")
    or ("Cleared the rating of " .. tostring(idea.name))
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
  changed, value = r.ImGui_InputTextWithHint(ctx, "Tags", "melodic, dark pad, 4 bars", state.capture.tags or "")
  if changed then state.capture.tags = value end
  if r.ImGui_IsItemHovered(ctx) then
    r.ImGui_SetTooltip(ctx, "Commas separate tags, spaces do not - \"dark pad\" is one tag")
  end

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

-- Description, tags and rating only. The name is left to Rename, which is a
-- different kind of operation: it moves every file the idea owns, while these
-- three live in the sidecar and cost one write.
local function draw_edit_popup(app)
  local ctx = app.ctx
  if state.edit_open then
    r.ImGui_OpenPopup(ctx, "Edit idea")
    state.edit_open = false
  end
  if not r.ImGui_BeginPopup(ctx, "Edit idea") then return end
  local idea = state.edit_target
  if not idea then r.ImGui_EndPopup(ctx); return end

  r.ImGui_Text(ctx, tostring(idea.name or ""))
  r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Rename is in the right-click menu - it moves the files too.")
  r.ImGui_Dummy(ctx, 0, UIScale.round(4))

  r.ImGui_SetNextItemWidth(ctx, UIScale.round(320))
  local changed, value = r.ImGui_InputText(ctx, "Description", state.edit_description or "")
  if changed then state.edit_description = value end

  r.ImGui_SetNextItemWidth(ctx, UIScale.round(320))
  changed, value = r.ImGui_InputTextWithHint(ctx, "Tags", "melodic, dark pad, 4 bars", state.edit_tags or "")
  if changed then state.edit_tags = value end
  if r.ImGui_IsItemHovered(ctx) then
    r.ImGui_SetTooltip(ctx, "Commas separate tags, spaces do not - \"dark pad\" is one tag.\n"
      .. "An idea can carry as many as you like, and the chips above the list filter on them")
  end

  -- The tags already in the vault, one click away. A tag with a typo in it is
  -- an idea that no chip and no search will ever bring back, and at a hundred
  -- ideas typing them out again is exactly how that happens.
  local known = Store.all_tags(state.ideas)
  if #known > 0 then
    r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Tags already in the vault:")
    local avail = r.ImGui_GetContentRegionAvail(ctx) or UIScale.round(320)
    local gap = UIScale.gap(4)
    local line_w = 0
    for index, entry in ipairs(known) do
      local width = r.ImGui_CalcTextSize(ctx, entry.tag) + UIScale.round(16)
      if index > 1 and line_w + width + gap <= avail then
        r.ImGui_SameLine(ctx, 0, gap)
        line_w = line_w + width + gap
      else
        line_w = width
      end
      local current = Store.parse_tags(state.edit_tags)
      local already = list_contains(current, entry.tag) ~= nil
      if already then r.ImGui_BeginDisabled(ctx, true) end
      if r.ImGui_SmallButton(ctx, entry.tag .. "##known_" .. index) then
        current[#current + 1] = entry.tag
        state.edit_tags = table.concat(current, ", ")
      end
      if already then r.ImGui_EndDisabled(ctx) end
    end
  end

  r.ImGui_Dummy(ctx, 0, UIScale.round(4))
  r.ImGui_Text(ctx, "Rating")
  r.ImGui_SameLine(ctx)
  local picked = rating_control(app, "edit_rating", state.edit_rating, UIScale.round(16))
  if picked then state.edit_rating = picked end

  r.ImGui_Dummy(ctx, 0, UIScale.round(4))
  local button_w = UIScale.text_button_w(ctx, "Save", 80)
  if r.ImGui_Button(ctx, "Save", button_w, 0) then
    local ok, err = Store.set_rating(idea, state.edit_rating)
    if ok then ok, err = Store.set_meta(idea, state.edit_description, state.edit_tags) end
    app.status = ok and ("Updated " .. tostring(idea.name)) or tostring(err or "Could not save the changes")
    state.dirty = true
    r.ImGui_CloseCurrentPopup(ctx)
  end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "Cancel", button_w, 0) then r.ImGui_CloseCurrentPopup(ctx) end
  r.ImGui_EndPopup(ctx)
end

-- Tagging a selection is the operation a vault of a hundred ideas is missing:
-- the edit dialog changes one idea, and someone who has just decided that forty
-- of them are "melodic" is not going to open it forty times.
local function draw_bulk_popup(app)
  local ctx = app.ctx
  if state.bulk_open then
    r.ImGui_OpenPopup(ctx, "Tag selection")
    state.bulk_open = false
  end
  if not r.ImGui_BeginPopup(ctx, "Tag selection") then return end
  local count = marked_count()
  r.ImGui_Text(ctx, string.format("%d idea%s selected", count, count == 1 and "" or "s"))
  r.ImGui_Dummy(ctx, 0, UIScale.round(4))

  r.ImGui_SetNextItemWidth(ctx, UIScale.round(320))
  local changed, value = r.ImGui_InputTextWithHint(ctx, "Tags", "melodic, dark pad", state.bulk_tags or "")
  if changed then state.bulk_tags = value end

  local known = Store.all_tags(state.ideas)
  if #known > 0 then
    r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Tags already in the vault:")
    local avail = r.ImGui_GetContentRegionAvail(ctx) or UIScale.round(320)
    local gap = UIScale.gap(4)
    local line_w = 0
    for index, entry in ipairs(known) do
      local width = r.ImGui_CalcTextSize(ctx, entry.tag) + UIScale.round(16)
      if index > 1 and line_w + width + gap <= avail then
        r.ImGui_SameLine(ctx, 0, gap)
        line_w = line_w + width + gap
      else
        line_w = width
      end
      if r.ImGui_SmallButton(ctx, entry.tag .. "##bulk_known_" .. index) then
        local current = Store.parse_tags(state.bulk_tags)
        if not list_contains(current, entry.tag) then
          current[#current + 1] = entry.tag
          state.bulk_tags = table.concat(current, ", ")
        end
      end
    end
  end

  r.ImGui_Dummy(ctx, 0, UIScale.round(4))
  local has_tags = tostring(state.bulk_tags or "") ~= ""
  local add_label = string.format("Add to %d", count)
  local remove_label = string.format("Remove from %d", count)
  if not has_tags then r.ImGui_BeginDisabled(ctx, true) end
  if r.ImGui_Button(ctx, add_label, UIScale.text_button_w(ctx, add_label, 90), 0) then
    apply_bulk_tags(app, "add")
    r.ImGui_CloseCurrentPopup(ctx)
  end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, remove_label, UIScale.text_button_w(ctx, remove_label, 110), 0) then
    apply_bulk_tags(app, "remove")
    r.ImGui_CloseCurrentPopup(ctx)
  end
  if not has_tags then r.ImGui_EndDisabled(ctx) end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "Cancel", UIScale.text_button_w(ctx, "Cancel", 70), 0) then
    r.ImGui_CloseCurrentPopup(ctx)
  end
  r.ImGui_EndPopup(ctx)
end

-- Renaming onto a tag that already exists merges the two, which is the same
-- thing seen from the other side: "melodic" and "melodics" were never meant to
-- be two piles.
local function draw_tag_rename_popup(app)
  local ctx = app.ctx
  if state.tag_rename_open then
    r.ImGui_OpenPopup(ctx, "Rename tag")
    state.tag_rename_open = false
  end
  if not r.ImGui_BeginPopup(ctx, "Rename tag") then return end
  local from = state.tag_rename_from
  if not from then r.ImGui_EndPopup(ctx); return end
  r.ImGui_Text(ctx, "Rename \"" .. tostring(from) .. "\" everywhere it is used")
  r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Renaming it to a tag that already exists merges the two.")
  r.ImGui_Dummy(ctx, 0, UIScale.round(4))
  r.ImGui_SetNextItemWidth(ctx, UIScale.round(260))
  local changed, value = r.ImGui_InputText(ctx, "New name", state.tag_rename_text or "")
  if changed then state.tag_rename_text = value end

  local button_w = UIScale.text_button_w(ctx, "Rename", 80)
  local can_save = tostring(state.tag_rename_text or "") ~= ""
  if not can_save then r.ImGui_BeginDisabled(ctx, true) end
  if r.ImGui_Button(ctx, "Rename", button_w, 0) and can_save then
    local count, failed = Store.rename_tag(state.ideas, from, state.tag_rename_text)
    -- The filter follows the rename. A chip that is lit for a tag that no
    -- longer exists filters everything away and cannot be clicked off again.
    local target = Store.parse_tags(state.tag_rename_text)[1]
    if list_contains(state.tag_filter, from) then
      state.tag_filter = list_without(state.tag_filter, from)
      if target and not list_contains(state.tag_filter, target) then
        state.tag_filter[#state.tag_filter + 1] = target
      end
    end
    if list_contains(state.tag_exclude, from) then
      state.tag_exclude = list_without(state.tag_exclude, from)
      if target and not list_contains(state.tag_exclude, target) then
        state.tag_exclude[#state.tag_exclude + 1] = target
      end
    end
    app.status = string.format("Renamed the tag on %d idea%s", count, count == 1 and "" or "s")
      .. (failed > 0 and string.format(", %d could not be saved", failed) or "")
    state.dirty = true
    r.ImGui_CloseCurrentPopup(ctx)
  end
  if not can_save then r.ImGui_EndDisabled(ctx) end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "Cancel", button_w, 0) then r.ImGui_CloseCurrentPopup(ctx) end
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

local function draw_header(app, settings)
  local ctx = app.ctx
  local button_w = UIScale.text_button_w(ctx, "Capture", 80)
  local dots_w = UIScale.round(28)
  local avail = r.ImGui_GetContentRegionAvail(ctx) or UIScale.round(320)
  local spacing = UIScale.gap(6)
  local search_w = math.max(UIScale.round(80), avail - button_w * 2 - dots_w - spacing * 3)
  local changed, value = UI.search_input(ctx, "##idea_search", "Search ideas", state.search, search_w)
  if changed then state.search = value end
  r.ImGui_SameLine(ctx, 0, spacing)
  if r.ImGui_Button(ctx, "Capture", button_w, 0) then begin_capture() end
  if r.ImGui_IsItemHovered(ctx) then
    r.ImGui_SetTooltip(ctx, "Save the selected track as a template plus a preview")
  end
  r.ImGui_SameLine(ctx, 0, spacing)
  if r.ImGui_Button(ctx, "Refresh", button_w, 0) then state.dirty = true end
  r.ImGui_SameLine(ctx, 0, spacing)
  if r.ImGui_Button(ctx, "...", dots_w, 0) then state.view_popup = true end
  if r.ImGui_IsItemHovered(ctx) then
    r.ImGui_SetTooltip(ctx, "How the list looks, how it is sorted, and the minimum rating to show")
  end
end

local VIEWS = {
  { id = "list", label = "List" },
  { id = "compact", label = "Compact" },
  { id = "tiles", label = "Tiles" }
}

local SORTS = {
  { id = "created", label = "date captured" },
  { id = "name", label = "name" },
  { id = "rating", label = "rating" },
  { id = "tag", label = "first tag" },
  { id = "duration", label = "length" }
}

local function sort_label(id)
  for _, entry in ipairs(SORTS) do
    if entry.id == id then return entry.label end
  end
  return id
end

local function draw_view_popup(app, settings)
  local ctx = app.ctx
  if state.view_popup then
    r.ImGui_OpenPopup(ctx, "Idea Vault view")
    state.view_popup = false
  end
  if not r.ImGui_BeginPopup(ctx, "Idea Vault view") then return end

  r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Density")
  for index, entry in ipairs(VIEWS) do
    if index > 1 then r.ImGui_SameLine(ctx) end
    if r.ImGui_RadioButton(ctx, entry.label, settings.view == entry.id) then
      settings.view = entry.id
      save_settings(app)
    end
  end
  if settings.view == "tiles" then
    r.ImGui_SetNextItemWidth(ctx, UIScale.round(200))
    local changed, value = r.ImGui_SliderInt(ctx, "Tile width", settings.tile_size, 110, 280)
    if changed then settings.tile_size = value; save_settings(app) end
    if r.ImGui_IsItemHovered(ctx) then
      r.ImGui_SetTooltip(ctx, "How wide a tile wants to be. The column count follows from the panel width,\n"
        .. "and the tiles are then stretched to fill it exactly")
    end
  end

  r.ImGui_Dummy(ctx, 0, UIScale.round(4))
  r.ImGui_SetNextItemWidth(ctx, UIScale.round(200))
  if r.ImGui_BeginCombo(ctx, "Sort by", sort_label(settings.sort_by)) then
    for _, entry in ipairs(SORTS) do
      if r.ImGui_Selectable(ctx, entry.label, settings.sort_by == entry.id) then
        settings.sort_by = entry.id
        save_settings(app)
      end
    end
    r.ImGui_EndCombo(ctx)
  end
  if settings.sort_by == "tag" and r.ImGui_IsItemHovered(ctx) then
    r.ImGui_SetTooltip(ctx, "The first tag an idea carries. Ideas with no tags at all go last either way")
  end
  local changed, value = r.ImGui_Checkbox(ctx, "Ascending", settings.sort_ascending == true)
  if changed then settings.sort_ascending = value; save_settings(app) end
  if r.ImGui_IsItemHovered(ctx) then
    r.ImGui_SetTooltip(ctx, "Off means newest, highest rated or longest first")
  end

  r.ImGui_Dummy(ctx, 0, UIScale.round(4))
  r.ImGui_Text(ctx, "Show at least")
  r.ImGui_SameLine(ctx)
  local picked = rating_control(app, "min_rating", settings.min_rating, UIScale.round(14))
  if picked then settings.min_rating = picked; save_settings(app) end
  r.ImGui_SameLine(ctx)
  r.ImGui_TextColored(ctx, Theme.colors.text_dim,
    settings.min_rating > 0 and string.format("%d and up", settings.min_rating) or "any rating")

  if filters_active(settings) then
    r.ImGui_Dummy(ctx, 0, UIScale.round(4))
    if r.ImGui_Button(ctx, "Clear filters", UIScale.text_button_w(ctx, "Clear filters", 110), 0) then
      clear_filters(app, settings)
    end
  end
  r.ImGui_EndPopup(ctx)
end

-- The chips are what a vault with a hundred ideas in it needs and a search box
-- cannot give: the search finds a word you already know is there, while the
-- chips show what the vault is actually made of and let two tags be asked for
-- at once. Same gestures as the Tags module, because they are the same idea.
local function draw_tag_bar(app, settings)
  local ctx = app.ctx
  local tags = Store.all_tags(state.ideas)
  local clearing = filters_active(settings)
  local untagged_count = 0
  for _, idea in ipairs(state.ideas) do
    if #(idea.tags or {}) == 0 then untagged_count = untagged_count + 1 end
  end
  local untagged_label = string.format("Untagged (%d)", untagged_count)
  local show_untagged = untagged_count > 0 or state.untagged ~= nil
  if #tags == 0 and not clearing and not show_untagged then return end
  local gap = UIScale.gap(4)
  local avail = math.max(UIScale.round(60), r.ImGui_GetContentRegionAvail(ctx) or UIScale.round(300))

  -- Measured before anything is drawn so the bar can be capped at two rows. A
  -- vault with forty tags would otherwise push the list off the bottom of the
  -- panel, and the canvas has no scrollbar to bring it back with - the chips
  -- get their own scroll instead.
  local rows, line_w = 1, 0
  local function place(width)
    if line_w > 0 and line_w + gap + width <= avail then
      line_w = line_w + gap + width
      return true
    end
    if line_w > 0 then rows = rows + 1 end
    line_w = width
    return false
  end
  local widths = {}
  if clearing then place(r.ImGui_CalcTextSize(ctx, "Clear filter") + UIScale.round(16)) end
  if show_untagged then place(r.ImGui_CalcTextSize(ctx, untagged_label) + UIScale.round(16)) end
  for index, entry in ipairs(tags) do
    widths[index] = r.ImGui_CalcTextSize(ctx, entry.tag) + UIScale.round(16)
    place(widths[index])
  end

  local row_h = r.ImGui_GetFrameHeight(ctx)
  local bar_h = math.min(rows, 2) * row_h + UIScale.round(6)
  if not r.ImGui_BeginChild(ctx, "##idea_tag_bar", 0, bar_h, 0) then return end
  line_w = 0
  local first = true
  local function chip_line(width)
    if not first and line_w + gap + width <= avail then
      r.ImGui_SameLine(ctx, 0, gap)
      line_w = line_w + gap + width
    else
      line_w = width
    end
    first = false
  end

  if clearing then
    chip_line(r.ImGui_CalcTextSize(ctx, "Clear filter") + UIScale.round(16))
    if r.ImGui_SmallButton(ctx, "Clear filter") then clear_filters(app, settings) end
    if r.ImGui_IsItemHovered(ctx) then
      r.ImGui_SetTooltip(ctx, "Drop every tag filter and the minimum rating")
    end
  end

  -- The pile that still wants doing. It cannot be one of the tag chips because
  -- it matches on the absence of all of them, and while retagging a vault it is
  -- the chip that gets used most.
  if show_untagged then
    chip_line(r.ImGui_CalcTextSize(ctx, untagged_label) + UIScale.round(16))
    if r.ImGui_SmallButton(ctx, untagged_label) then
      if r.ImGui_IsKeyDown(ctx, r.ImGui_Mod_Alt()) then
        state.untagged = (state.untagged ~= "exclude") and "exclude" or nil
      else
        state.untagged = (state.untagged ~= "only") and "only" or nil
      end
    end
    if state.untagged then
      local draw_list = r.ImGui_GetWindowDrawList(ctx)
      local min_x, min_y = r.ImGui_GetItemRectMin(ctx)
      local max_x, max_y = r.ImGui_GetItemRectMax(ctx)
      local color = state.untagged == "exclude" and Theme.colors.danger or Theme.colors.accent
      r.ImGui_DrawList_AddRect(draw_list, min_x - UIScale.round(1), min_y - UIScale.round(1),
        max_x + UIScale.round(1), max_y + UIScale.round(1), color, UIScale.px(4), 0, UIScale.px(2))
      if state.untagged == "exclude" then
        r.ImGui_DrawList_AddLine(draw_list, min_x + UIScale.round(3), (min_y + max_y) * 0.5,
          max_x - UIScale.round(3), (min_y + max_y) * 0.5, Theme.colors.danger, UIScale.px(1.5))
      end
    end
    if r.ImGui_IsItemHovered(ctx) then
      r.ImGui_SetTooltip(ctx, "The ideas carrying no tag at all.\n"
        .. "Click to show only those, alt-click to hide them and see what is already tagged")
    end
  end

  for index, entry in ipairs(tags) do
    chip_line(widths[index])
    local included = list_contains(state.tag_filter, entry.tag) ~= nil
    local excluded = list_contains(state.tag_exclude, entry.tag) ~= nil
    if r.ImGui_SmallButton(ctx, entry.tag .. "##idea_tag_" .. index) then
      local ctrl = r.ImGui_IsKeyDown(ctx, r.ImGui_Mod_Ctrl())
      local alt = r.ImGui_IsKeyDown(ctx, r.ImGui_Mod_Alt())
      if alt then
        if excluded then
          state.tag_exclude = list_without(state.tag_exclude, entry.tag)
        else
          state.tag_filter = list_without(state.tag_filter, entry.tag)
          state.tag_exclude[#state.tag_exclude + 1] = entry.tag
        end
      elseif ctrl then
        if included then
          state.tag_filter = list_without(state.tag_filter, entry.tag)
        else
          state.tag_exclude = list_without(state.tag_exclude, entry.tag)
          state.tag_filter[#state.tag_filter + 1] = entry.tag
        end
      elseif included and #state.tag_filter == 1 then
        -- Clicking the isolated tag again is the way back to the whole vault,
        -- so it drops the excluded ones with it rather than leaving a filter
        -- behind that no lit chip accounts for.
        state.tag_filter, state.tag_exclude = {}, {}
      else
        state.tag_filter = { entry.tag }
        state.tag_exclude = list_without(state.tag_exclude, entry.tag)
      end
    end
    if included or excluded then
      local draw_list = r.ImGui_GetWindowDrawList(ctx)
      local min_x, min_y = r.ImGui_GetItemRectMin(ctx)
      local max_x, max_y = r.ImGui_GetItemRectMax(ctx)
      local color = excluded and Theme.colors.danger or Theme.colors.accent
      r.ImGui_DrawList_AddRect(draw_list, min_x - UIScale.round(1), min_y - UIScale.round(1),
        max_x + UIScale.round(1), max_y + UIScale.round(1), color, UIScale.px(4), 0, UIScale.px(2))
      if excluded then
        r.ImGui_DrawList_AddLine(draw_list, min_x + UIScale.round(3), (min_y + max_y) * 0.5,
          max_x - UIScale.round(3), (min_y + max_y) * 0.5, Theme.colors.danger, UIScale.px(1.5))
      end
    end
    if r.ImGui_BeginPopupContextItem(ctx, "##idea_tag_menu_" .. index) then
      if r.ImGui_MenuItem(ctx, "Rename or merge this tag") then
        state.tag_rename_from = entry.tag
        state.tag_rename_text = entry.tag
        state.tag_rename_open = true
      end
      if r.ImGui_MenuItem(ctx, "Remove this tag from every idea") then
        state.pending_tag_delete = entry.tag
      end
      r.ImGui_EndPopup(ctx)
    end
    if r.ImGui_IsItemHovered(ctx) then
      r.ImGui_SetTooltip(ctx, string.format("%s - %d idea%s\n\n", entry.tag, entry.count, entry.count == 1 and "" or "s")
        .. "Click to show only this tag, ctrl-click to add it to the ones already lit,\n"
        .. "alt-click to leave it out. Click a lit tag again for the whole vault back.\n"
        .. "Right-click to rename it, merge it into another or remove it from every idea")
    end
  end
  r.ImGui_EndChild(ctx)
end

-- One card for all three densities. The layout differs per mode, everything
-- else - selecting, the play badge, double-click to load, the context menu - is
-- the same thing three times over, and three copies of it is three places for
-- the id stack to go wrong.
local function draw_card(app, idea, width, height, mode)
  local ctx = app.ctx
  local selected = state.selected == idea
  local playing = state.preview ~= nil and state.preview_name == idea.name
  local tile = mode == "tiles"
  local compact = mode == "compact"
  r.ImGui_PushID(ctx, idea.name)
  local clicked = r.ImGui_InvisibleButton(ctx, "##idea_card", width, height)
  local hovered = r.ImGui_IsItemHovered(ctx)
  local double = hovered and r.ImGui_IsMouseDoubleClicked(ctx, 0)
  local x, y = r.ImGui_GetItemRectMin(ctx)
  local draw_list = r.ImGui_GetWindowDrawList(ctx)

  local marked = state.marked[idea.name] == true
  local top, bottom = y + UIScale.round(2), y + height - UIScale.round(2)
  local bg = selected and 0x7AA2F730 or (marked and 0x7AA2F720 or (hovered and 0xFFFFFF12 or 0x00000000))
  if bg ~= 0x00000000 then
    r.ImGui_DrawList_AddRectFilled(draw_list, x, top, x + width, bottom, bg, UIScale.px(5))
  end
  r.ImGui_DrawList_AddRect(draw_list, x, top, x + width, bottom,
    selected and Theme.colors.accent or Theme.colors.border, UIScale.px(5), 0,
    selected and UIScale.px(1.4) or UIScale.px(0.7))
  -- A marked card carries a bar rather than a second ring: the ring is what
  -- "this is the one the panel below is describing" already means, and two
  -- rings in the same colour would say nothing.
  if marked then
    r.ImGui_DrawList_AddRectFilled(draw_list, x, top + UIScale.round(3), x + UIScale.round(3),
      bottom - UIScale.round(3), Theme.colors.accent, UIScale.px(2))
  end

  -- Play badge, its own hit area so clicking the card still selects.
  local badge_r = compact and UIScale.round(8) or UIScale.round(11)
  local bcx = x + UIScale.round(9) + badge_r
  local bcy = tile and (y + UIScale.round(10) + badge_r) or (y + height * 0.5)
  local mouse_x, mouse_y = r.ImGui_GetMousePos(ctx)
  local badge_reach = badge_r + UIScale.round(2)
  local badge_hot = hovered
    and ((mouse_x - bcx) ^ 2 + (mouse_y - bcy) ^ 2) <= badge_reach ^ 2
  r.ImGui_DrawList_AddCircleFilled(draw_list, bcx, bcy, badge_r,
    playing and Theme.colors.accent or Theme.colors.frame_bg, 24)
  r.ImGui_DrawList_AddCircle(draw_list, bcx, bcy, badge_r,
    (badge_hot or playing) and Theme.colors.accent or Theme.colors.border, 24, UIScale.px(1))
  local glyph = playing and Theme.colors.text or (idea.has_preview and Theme.colors.text or Theme.colors.text_dim)
  local bar_h = compact and UIScale.round(4) or UIScale.round(5)
  if playing then
    local bar = UIScale.round(3)
    r.ImGui_DrawList_AddRectFilled(draw_list, bcx - bar - UIScale.px(1), bcy - bar_h, bcx - UIScale.px(1), bcy + bar_h, glyph)
    r.ImGui_DrawList_AddRectFilled(draw_list, bcx + UIScale.px(1), bcy - bar_h, bcx + bar + UIScale.px(1), bcy + bar_h, glyph)
  else
    r.ImGui_DrawList_AddTriangleFilled(draw_list,
      bcx - UIScale.round(3), bcy - bar_h,
      bcx - UIScale.round(3), bcy + bar_h,
      bcx + UIScale.round(6), bcy, glyph)
  end

  local star_size = compact and UIScale.round(9) or UIScale.round(10)
  local star_w = stars_width(idea.rating, star_size)
  local text_x = tile and (x + UIScale.round(8)) or (bcx + badge_r + UIScale.round(9))
  local right = x + width - UIScale.round(8)
  local clip_right = right
  if star_w > 0 and not tile then clip_right = right - star_w - UIScale.round(6) end
  if clip_right < text_x then clip_right = text_x end

  r.ImGui_DrawList_PushClipRect(draw_list, text_x, y, clip_right, y + height, true)
  if tile then
    r.ImGui_DrawList_AddText(draw_list, text_x, y + UIScale.round(32), Theme.colors.text, tostring(idea.name or ""))
    local second = tostring(idea.description or "")
    if second == "" then second = summary_line(idea) end
    r.ImGui_DrawList_AddText(draw_list, text_x, y + UIScale.round(50), Theme.colors.text_dim, second)
  elseif compact then
    r.ImGui_DrawList_AddText(draw_list, text_x, y + (height - UIScale.round(14)) * 0.5, Theme.colors.text, tostring(idea.name or ""))
  else
    r.ImGui_DrawList_AddText(draw_list, text_x, y + UIScale.round(7), Theme.colors.text, tostring(idea.name or ""))
    local second = tostring(idea.description or "")
    if second == "" then second = summary_line(idea) end
    r.ImGui_DrawList_AddText(draw_list, text_x, y + UIScale.round(26), Theme.colors.text_dim, second)
  end
  r.ImGui_DrawList_PopClipRect(draw_list)

  if star_w > 0 then
    local star_y = tile and (y + UIScale.round(16)) or (y + height * 0.5)
    draw_stars_at(draw_list, right - star_w, star_y, idea.rating, star_size, Theme.colors.accent)
  end

  if clicked then
    state.selected = idea
    if badge_hot then
      if playing then stop_preview() else play(app, idea) end
    elseif r.ImGui_IsKeyDown(ctx, r.ImGui_Mod_Ctrl()) then
      state.marked[idea.name] = (not state.marked[idea.name]) or nil
      state.mark_anchor = idea.name
    elseif r.ImGui_IsKeyDown(ctx, r.ImGui_Mod_Shift()) then
      mark_range(idea)
    else
      -- A plain click drops the selection. Anything else and a mark made three
      -- filters ago quietly rides along into the next bulk edit.
      state.marked = {}
      state.mark_anchor = idea.name
    end
  end
  if double and not badge_hot then load_idea(app, idea) end
  if hovered and not badge_hot then
    local tags = Store.tags_text(idea)
    r.ImGui_SetTooltip(ctx, tostring(idea.name) .. "\n" .. summary_line(idea)
      .. (tags ~= "" and ("\n" .. tags) or "")
      .. (tostring(idea.description or "") ~= "" and ("\n\n" .. idea.description) or "")
      .. "\n\nDouble-click to load into the project"
      .. "\nCtrl-click to pick out several, shift-click for a run of them")
  end

  if r.ImGui_BeginPopupContextItem(ctx, "##idea_context") then
    state.selected = idea
    local count = marked_count()
    if count > 1 and state.marked[idea.name] then
      if r.ImGui_MenuItem(ctx, string.format("Tag the %d selected ideas", count)) then begin_bulk_tag() end
      r.ImGui_Separator(ctx)
    end
    if r.ImGui_MenuItem(ctx, playing and "Stop" or "Play") then
      if playing then stop_preview() else play(app, idea) end
    end
    if r.ImGui_MenuItem(ctx, "Load into project") then load_idea(app, idea) end
    if r.ImGui_MenuItem(ctx, "Edit description, tags and rating") then begin_edit(idea) end
    if r.ImGui_MenuItem(ctx, "Rename") then
      state.rename_target = idea
      state.rename_text = tostring(idea.name or "")
      state.rename_open = true
    end
    if r.CF_LocateInExplorer and r.ImGui_MenuItem(ctx, "Show in explorer") then reveal(idea) end
    if r.ImGui_MenuItem(ctx, "Delete") then
      if playing then stop_preview() end
      local ok, left, message = Store.delete(idea)
      if state.selected == idea then state.selected = nil end
      state.dirty = true
      app.status = "Deleted " .. tostring(idea.name)
      if not ok and left and #left > 0 then
        state.pending_delete = { paths = left, message = message, tries = 0 }
      end
    end
    r.ImGui_EndPopup(ctx)
  end
  r.ImGui_PopID(ctx)
end

local function draw_tiles(app, settings, list)
  local ctx = app.ctx
  local avail = r.ImGui_GetContentRegionAvail(ctx) or UIScale.round(300)
  local gap = UIScale.gap(6)
  local wanted = UIScale.round(settings.tile_size)
  local columns = math.max(1, math.floor((avail + gap) / (wanted + gap)))
  -- The column count follows from the width and the tiles are then widened to
  -- fill it: tiles of exactly the asked-for width leave a ragged strip on the
  -- right that reads as a layout bug rather than as a setting.
  local tile_w = math.max(UIScale.round(90), math.floor((avail - gap * (columns - 1)) / columns))
  local tile_h = UIScale.round(70)
  for index, idea in ipairs(list) do
    if index > 1 and (index - 1) % columns ~= 0 then r.ImGui_SameLine(ctx, 0, gap) end
    draw_card(app, idea, tile_w, tile_h, "tiles")
  end
end

local function draw_list(app, settings, height)
  local ctx = app.ctx
  if not r.ImGui_BeginChild(ctx, "##idea_vault_list", 0, height, 0) then return end
  local list = visible_ideas(settings)
  -- Kept for shift-click: a range is the run between two cards in the order the
  -- list is showing them, which a card cannot know on its own.
  state.visible = list
  if #list == 0 then
    r.ImGui_Dummy(ctx, 0, UIScale.round(8))
    local message = "No ideas yet - select a track and press Capture."
    if #state.ideas > 0 then
      message = filters_active(settings) and "Nothing matches this search and filter."
                                          or "Nothing matches this search."
    end
    r.ImGui_TextColored(ctx, Theme.colors.text_dim, message)
  elseif settings.view == "tiles" then
    draw_tiles(app, settings, list)
  else
    local width = math.max(UIScale.round(120), r.ImGui_GetContentRegionAvail(ctx) or UIScale.round(200))
    local row_h = settings.view == "compact" and UIScale.round(28) or UIScale.round(48)
    for _, idea in ipairs(list) do draw_card(app, idea, width, row_h, settings.view) end
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
  r.ImGui_SameLine(ctx)
  local picked = rating_control(app, "footer_rating", idea.rating, UIScale.round(13))
  if picked then set_rating(app, idea, picked) end
  r.ImGui_SameLine(ctx)
  if r.ImGui_SmallButton(ctx, "Edit") then begin_edit(idea) end
  if r.ImGui_IsItemHovered(ctx) then
    r.ImGui_SetTooltip(ctx, "Description, tags and rating. Renaming is in the right-click menu")
  end
  -- The tags ride along on the summary line rather than taking one of their
  -- own: a line that appears only for ideas that have tags moves the list up
  -- and down as you click through it.
  local info = summary_line(idea)
  local tag_text = Store.tags_text(idea)
  if tag_text ~= "" then info = info .. "  |  " .. tag_text end
  r.ImGui_TextColored(ctx, Theme.colors.text_dim, info)

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

-- Only on screen while something is marked: a permanent row would cost the
-- list a line of height for a state it is almost never in, and the canvas has
-- no scrollbar to pay that back with.
local function draw_selection_bar(app)
  local ctx = app.ctx
  local count = marked_count()
  if count == 0 then return end
  r.ImGui_TextColored(ctx, Theme.colors.accent, string.format("%d selected", count))
  r.ImGui_SameLine(ctx)
  if r.ImGui_SmallButton(ctx, "Tag...") then begin_bulk_tag() end
  if r.ImGui_IsItemHovered(ctx) then
    r.ImGui_SetTooltip(ctx, "Add a tag to all of them, or take one off all of them")
  end
  r.ImGui_SameLine(ctx)
  if r.ImGui_SmallButton(ctx, "Select all shown") then
    for _, idea in ipairs(state.visible or {}) do state.marked[idea.name] = true end
  end
  if r.ImGui_IsItemHovered(ctx) then
    r.ImGui_SetTooltip(ctx, "Everything the search and the chips are currently showing")
  end
  r.ImGui_SameLine(ctx)
  if r.ImGui_SmallButton(ctx, "Clear selection") then state.marked = {} end
end

--------------------------------------------------------------------------------
-- module contract
--------------------------------------------------------------------------------

function M.init(app)
  state.dirty = true
end

local function retry_delete(app)
  local pending = state.pending_delete
  if not pending then return end
  local left = {}
  for _, path in ipairs(pending.paths) do
    os.remove(path)
    if r.file_exists(path) then left[#left + 1] = path end
  end
  pending.paths = left
  pending.tries = pending.tries + 1
  if #left == 0 then
    state.pending_delete = nil
    state.dirty = true
  elseif pending.tries >= DELETE_RETRY_FRAMES then
    state.pending_delete = nil
    state.dirty = true
    app.status = pending.message or "Could not delete every file of that idea"
  end
end

function M.update(app)
  retry_delete(app)
  -- Asked here rather than from the chip menu: this runs before the ImGui frame
  -- is built, so a blocking dialog cannot leave a half-drawn one behind. And it
  -- is asked at all because removing a tag from ninety ideas is not something
  -- to do on a mis-click.
  local doomed = state.pending_tag_delete
  if doomed then
    state.pending_tag_delete = nil
    local answer = r.ShowMessageBox(
      "Remove the tag \"" .. tostring(doomed) .. "\" from every idea that carries it?"
      .. "\n\nThe ideas themselves are not touched.", "Idea Vault", 4)
    if answer == 6 then
      local count, failed = Store.rename_tag(state.ideas, doomed, "")
      state.tag_filter = list_without(state.tag_filter, doomed)
      state.tag_exclude = list_without(state.tag_exclude, doomed)
      app.status = string.format("Removed the tag from %d idea%s", count, count == 1 and "" or "s")
        .. (failed > 0 and string.format(", %d could not be saved", failed) or "")
      state.dirty = true
    end
  end
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
  local settings = ensure_settings(app)
  if state.dirty then refresh() end

  local start_y = r.ImGui_GetCursorPosY(ctx)
  local _, avail_h = r.ImGui_GetContentRegionAvail(ctx)
  avail_h = avail_h or UIScale.round(320)

  -- One flexible list, everything else measured rather than estimated: the
  -- canvas has no scrollbar, so an over-tall layout would just lose its footer.
  local list_h = math.max(UIScale.round(60), avail_h - (state.fixed_h or UIScale.round(150)))

  draw_header(app, settings)
  draw_tag_bar(app, settings)
  draw_selection_bar(app)
  r.ImGui_Dummy(ctx, 0, UIScale.round(4))
  draw_list(app, settings, list_h)
  draw_footer(app)
  draw_capture_popup(app)
  draw_edit_popup(app)
  draw_bulk_popup(app)
  draw_tag_rename_popup(app)
  draw_rename_popup(app)
  draw_view_popup(app, settings)

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
