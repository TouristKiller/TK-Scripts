local r = reaper
local Theme = require("core.theme")
local UI = require("core.ui")
local UIScale = require("core.ui_scale")
local ProjectHealth = require("core.project_health")
local M = {
  id = "project_overview",
  title = "Project Overview",
  icon = "PRJ",
  version = "0.1.0"
}

local state = {
  tab = "overview",
  health = nil
}

local PROJECT_ACTIONS = {
  { label = "Save Project", command = 40026, status = "Project saved" },
  { label = "Save As", command = 40022, status = "Save project as" },
  { label = "Save Template", command = 40394, status = "Save project as template" },
  { label = "Project Settings", command = 40021, status = "Project settings" }
}

local function format_time(seconds)
  seconds = tonumber(seconds) or 0
  local sign = seconds < 0 and "-" or ""
  seconds = math.abs(seconds)
  local hours = math.floor(seconds / 3600)
  local minutes = math.floor((seconds % 3600) / 60)
  local secs = seconds % 60
  if hours > 0 then return string.format("%s%d:%02d:%05.2f", sign, hours, minutes, secs) end
  return string.format("%s%d:%05.2f", sign, minutes, secs)
end

local function draw_row(ctx, label, value)
  r.ImGui_TextColored(ctx, Theme.colors.text_dim, label)
  r.ImGui_SameLine(ctx, UIScale.round(150))
  r.ImGui_Text(ctx, tostring(value or "-"))
end

local function format_time_signature(project)
  local numerator = math.floor((tonumber(project.time_sig) or 4) + 0.5)
  local denominator = math.floor((tonumber(project.time_sig_denom) or 4) + 0.5)
  return tostring(numerator) .. "/" .. tostring(denominator)
end

local function format_sample_rate(sample_rate)
  sample_rate = tonumber(sample_rate) or 0
  if sample_rate <= 0 then return "Project default" end
  return string.format("%d Hz", math.floor(sample_rate + 0.5))
end

local function format_frame_rate(frame_rate, drop_frame)
  frame_rate = tonumber(frame_rate) or 0
  if frame_rate <= 0 then return "-" end
  local suffix = drop_frame and " DF" or ""
  if math.abs(frame_rate - math.floor(frame_rate + 0.5)) < 0.001 then return string.format("%d fps%s", math.floor(frame_rate + 0.5), suffix) end
  return string.format("%.3f fps%s", frame_rate, suffix)
end

local function format_range(start_time, end_time)
  start_time = tonumber(start_time) or 0
  end_time = tonumber(end_time) or 0
  if end_time <= start_time then return "None" end
  return string.format("%s - %s (%s)", format_time(start_time), format_time(end_time), format_time(end_time - start_time))
end

local function format_play_state(play_state)
  play_state = tonumber(play_state) or 0
  if play_state & 4 == 4 then return "Recording" end
  if play_state & 2 == 2 then return "Paused" end
  if play_state & 1 == 1 then return "Playing" end
  return "Stopped"
end

local function run_project_action(app, action)
  if not action or not action.command then return end
  r.Main_OnCommand(action.command, 0)
  app.status = action.status or action.label
end

local function draw_project_actions(ctx, app, width)
  local gap = UIScale.gap(6)
  local button_w = math.max(UIScale.round(90), ((width or UIScale.round(320)) - gap) * 0.5)
  for index, action in ipairs(PROJECT_ACTIONS) do
    if index % 2 == 0 then r.ImGui_SameLine(ctx, 0, gap) end
    if r.ImGui_Button(ctx, action.label, button_w, 0) then run_project_action(app, action) end
    if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, action.label) end
  end
end

local function draw_tab_button(ctx, label, id)
  local active = state.tab == id
  if active then
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), Theme.colors.accent)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), Theme.colors.accent)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), Theme.colors.warning)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), Theme.text_for_backgrounds({ Theme.colors.accent, Theme.colors.warning }, Theme.colors.text, nil, 4.5))
  end
  local clicked = r.ImGui_Button(ctx, label .. "##project_overview_tab_" .. id, UIScale.text_button_w(ctx, label, 92), 0)
  if active then r.ImGui_PopStyleColor(ctx, 4) end
  if clicked then state.tab = id end
end

local function draw_tabs(ctx)
  draw_tab_button(ctx, "Overview", "overview")
  r.ImGui_SameLine(ctx)
  draw_tab_button(ctx, "Health", "health")
end

local function severity_color(severity)
  if severity == "critical" then return Theme.colors.danger end
  if severity == "warning" then return Theme.colors.warning end
  return Theme.colors.text_dim
end

local function ensure_health(app, project, force)
  local state_count = r.GetProjectStateChangeCount and (r.GetProjectStateChangeCount(0) or 0) or 0
  local control_room_settings = app and app.settings and app.settings.control_room or nil
  if force or not state.health or state.health.state_count ~= state_count then state.health = ProjectHealth.scan(project, control_room_settings) end
  return state.health
end

local function draw_health_summary(ctx, summary)
  summary = summary or {}
  r.ImGui_TextColored(ctx, Theme.colors.danger, "Critical: " .. tostring(summary.critical or 0))
  r.ImGui_SameLine(ctx)
  r.ImGui_TextColored(ctx, Theme.colors.warning, "Warnings: " .. tostring(summary.warning or 0))
  r.ImGui_SameLine(ctx)
  r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Info: " .. tostring(summary.info or 0))
end

local function draw_health_issue(ctx, app, issue, index)
  local color = severity_color(issue.severity)
  r.ImGui_TextColored(ctx, color, string.upper(tostring(issue.severity or "info")))
  r.ImGui_SameLine(ctx, UIScale.round(86))
  r.ImGui_TextColored(ctx, Theme.colors.text, tostring(issue.title or "Issue"))
  r.ImGui_TextColored(ctx, Theme.colors.text_dim, tostring(issue.category or "Project") .. " | " .. tostring(issue.detail or ""))
  if issue.action and issue.action_label and r.ImGui_Button(ctx, tostring(issue.action_label) .. "##health_action_" .. tostring(index), UIScale.text_button_w(ctx, tostring(issue.action_label), 82), 0) then
    local ok, err = pcall(issue.action)
    app.status = ok and tostring(issue.title or "Health action") or ("Health action failed: " .. tostring(err))
  end
  if issue.repair and issue.repair_label then
    if issue.action and issue.action_label then r.ImGui_SameLine(ctx) end
    if r.ImGui_Button(ctx, tostring(issue.repair_label) .. "##health_repair_" .. tostring(index), UIScale.text_button_w(ctx, tostring(issue.repair_label), 104), 0) then
      local ok, err = pcall(issue.repair)
      if ok then
        state.health = nil
        app.status = tostring(issue.repair_label) .. ": " .. tostring(issue.title or "Health repair")
      else
        app.status = "Health repair failed: " .. tostring(err)
      end
    end
  end
  if r.ImGui_Separator then r.ImGui_Separator(ctx) end
end

local function draw_health_tab(ctx, app, project)
  local health = ensure_health(app, project, false)
  draw_health_summary(ctx, health.summary)
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "Refresh##project_health_refresh", UIScale.text_button_w(ctx, "Refresh", 74), 0) then health = ensure_health(app, project, true) end
  r.ImGui_Separator(ctx)
  if not health.issues or #health.issues == 0 then
    r.ImGui_TextColored(ctx, Theme.colors.accent, "No project health issues found.")
    return
  end
  for index, entry in ipairs(health.issues) do draw_health_issue(ctx, app, entry, index) end
end

local function draw_overview_tab(ctx, app, project, selection, width)
  r.ImGui_Text(ctx, project.name or "Untitled")
  if project.path and project.path ~= "" then
    r.ImGui_TextColored(ctx, Theme.colors.text_dim, project.path)
  else
    r.ImGui_TextColored(ctx, Theme.colors.warning, "Project has not been saved yet")
  end

  r.ImGui_Separator(ctx)
  draw_project_actions(ctx, app, width or UIScale.round(320))

  r.ImGui_Separator(ctx)
  draw_row(ctx, "Status", project.dirty and "Modified" or "Saved")
  draw_row(ctx, "Transport", format_play_state(project.play_state))
  draw_row(ctx, "Length", format_time(project.length))
  draw_row(ctx, "Start time", format_time(project.start_time))
  draw_row(ctx, "Tempo", string.format("%.2f BPM", project.tempo or 0))
  draw_row(ctx, "Time signature", format_time_signature(project))
  draw_row(ctx, "Sample rate", format_sample_rate(project.sample_rate))
  draw_row(ctx, "Frame rate", format_frame_rate(project.frame_rate, project.drop_frame))
  draw_row(ctx, "Cursor", format_time(project.cursor))
  draw_row(ctx, "Play position", format_time(project.play_position))
  draw_row(ctx, "Time selection", format_range(project.time_selection_start, project.time_selection_end))
  draw_row(ctx, "Loop points", format_range(project.loop_start, project.loop_end))

  r.ImGui_Separator(ctx)
  if project.directory and project.directory ~= "" then draw_row(ctx, "Project folder", project.directory) end
  if project.record_path and project.record_path ~= "" then draw_row(ctx, "Record path", project.record_path) end

  r.ImGui_Separator(ctx)
  draw_row(ctx, "Tracks", project.tracks or 0)
  draw_row(ctx, "Muted tracks", project.muted_tracks or 0)
  draw_row(ctx, "Solo tracks", project.solo_tracks or 0)
  draw_row(ctx, "Armed tracks", project.armed_tracks or 0)
  draw_row(ctx, "Folder tracks", project.folder_tracks or 0)
  draw_row(ctx, "Items", project.items or 0)
  draw_row(ctx, "Markers", project.markers or 0)
  draw_row(ctx, "Regions", project.regions or 0)
  draw_row(ctx, "Tempo markers", project.tempo_markers or 0)

  r.ImGui_Separator(ctx)
  draw_row(ctx, "Selected tracks", selection.selected_track_count or 0)
  if selection.track then draw_row(ctx, "First track", string.format("%d - %s", selection.track.index or 0, selection.track.name or "Track")) end
  draw_row(ctx, "Selected items", selection.selected_item_count or 0)
  if (selection.selected_item_count or 0) > 1 then draw_row(ctx, "Selected item length", format_time(selection.selected_item_total_length)) end
  if selection.item then
    draw_row(ctx, "Active take", selection.item.take_name or "-")
    draw_row(ctx, "Item position", format_time(selection.item.position))
    draw_row(ctx, "Item length", format_time(selection.item.length))
  end
end

function M.draw(app)
  local ctx = app.ctx
  local project = app.selection.project or {}
  local selection = app.selection or {}

  draw_tabs(ctx)
  r.ImGui_Separator(ctx)

  local available_w, available_h = r.ImGui_GetContentRegionAvail(ctx)
  local content_h = math.max(UIScale.round(40), (available_h or UIScale.round(240)) - UI.info_line_height(ctx))

  if r.ImGui_BeginChild(ctx, "##project_overview_content", 0, content_h, 0) then
    if state.tab == "health" then draw_health_tab(ctx, app, project) else draw_overview_tab(ctx, app, project, selection, available_w or UIScale.round(320)) end
    r.ImGui_EndChild(ctx)
  end
  local health = state.health and state.health.summary
  local health_text = health and (" | health " .. tostring(health.critical or 0) .. "/" .. tostring(health.warning or 0)) or ""
  UI.draw_info_line(ctx, tostring(project.tracks or 0) .. " tracks | " .. tostring(project.items or 0) .. " items | " .. (project.dirty and "modified" or "saved") .. health_text)
end

return M