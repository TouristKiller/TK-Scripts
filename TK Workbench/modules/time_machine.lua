local r = reaper
local Theme = require("core.theme")
local UI = require("core.ui")
local UIScale = require("core.ui_scale")
local Diff = require("core.rpp_diff")
local Store = require("core.time_machine_store")
local Restore = require("core.time_machine_restore")

-- Time Machine keeps a copy of every saved version of a project and says, in
-- plain words, what changed between them.
--
-- Saving is noticed in update(), which Workbench calls every frame for every
-- module whether its panel is showing or not: a project that goes from dirty
-- to clean has just been written to disk, and that file is what gets copied.
-- All heavy work (copying, reading, comparing) runs in slices of a few
-- milliseconds per frame. See core/time_machine_store.lua for the storage
-- layout and core/rpp_diff.lua for what the comparison can and cannot see.
--
-- Restoring works on the open project: right-click a line in the list of
-- changes, or use a track's Restore menu, to put that one thing back the way
-- the older of the two compared versions had it. Each restore is one undo
-- step. See core/time_machine_restore.lua.

local M = {
  id = "time_machine",
  title = "Time Machine",
  icon = "TM",
  version = "0.1.0"
}

local POLL_SECONDS = 0.25
local FRAME_BUDGET = 0.005
local PARSE_CACHE_LIMIT = 20 * 1024 * 1024
local SUMMARY_SIZE_LIMIT = 100 * 1024 * 1024
-- Raise when the comparison learns something new, so summaries stored in the
-- manifests are worked out again (2: JSFX hidden sliders no longer count).
local SUMMARY_VERSION = 2
-- "Versus now" re-reads the open project by itself after an edit only while
-- that is cheap; bigger projects wait for the Refresh button.
local LIVE_AUTO_BYTES = 8 * 1024 * 1024
local LIVE_AUTO_SECONDS = 0.75

local defaults = {
  enabled = true,
  location = "",
  max_project_mb = 200,
  max_history_mb = 500,
  keep_all_hours = 24,
  keep_hourly_days = 7,
  compare = "previous",
  labelled_only = false,
  list_ratio = 0.4
}

local state = {
  projects = {},
  queue = {},
  job = nil,
  summary_queue = {},
  summary_task = nil,
  histories = nil,
  histories_root = nil,
  last_poll = 0,
  status = nil,
  selected = nil,
  selected_history = nil,
  diff_cache = {},
  diff_order = {},
  diff_task = nil,
  parsed = {},
  parsed_order = {},
  link_filter = "",
  param_cache = {},
  live = nil,
  live_serial = 0,
  label_edit = nil,
  -- Comparisons of each version with the one before it, kept for the
  -- per-track/per-plugin history: pair_results[manifest id][file] =
  -- { base = previous file, result = diff } (or skipped = true).
  pair_results = {},
  focus = nil,
  timeline_task = nil,
  ab = nil,
  borrow = nil,
  open_borrow = false,
  open_storage = false,
  storage_list = nil,
  storage_confirm = nil,
  storage_missing_only = false,
  backups_found = nil,
  link_list = nil,
  location_text = nil,
  pending_location = nil,
  open_settings = false,
  open_link = false,
  open_migrate = false,
  layout = { fixed_h = nil }
}

-- Small helpers ---------------------------------------------------------------

local util = {}

function util.settings(app)
  app.settings.time_machine = app.settings.time_machine or {}
  local settings = app.settings.time_machine
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

function util.root(app)
  return Store.root_for(util.settings(app).location)
end

function util.megabytes(bytes)
  bytes = bytes or 0
  if bytes < 1024 * 1024 then return string.format("%.0f KB", bytes / 1024) end
  return string.format("%.1f MB", bytes / (1024 * 1024))
end

function util.when(time)
  if not time then return "?" end
  local now = os.date("*t")
  local then_ = os.date("*t", time)
  local clock = os.date("%H:%M", time)
  if now.year == then_.year and now.yday == then_.yday then return "Today " .. clock end
  local yesterday = os.date("*t", os.time() - 86400)
  if yesterday.year == then_.year and yesterday.yday == then_.yday then return "Yesterday " .. clock end
  if os.time() - time < 6 * 86400 then return os.date("%a ", time) .. clock end
  return os.date("%d %b %Y ", time) .. clock
end

function util.set_status(text)
  state.status = { text = text, time = r.time_precise() }
end

-- Runs a coroutine for a frame's budget; returns true once it has finished.
function util.resume(task)
  if not task or not task.co then return true end
  local ok, value = coroutine.resume(task.co)
  if not ok then
    task.error = tostring(value)
    return true
  end
  if coroutine.status(task.co) == "dead" then return true end
  if type(value) == "number" then task.progress = value end
  return false
end

-- Reads a whole file from inside a coroutine, yielding between chunks.
function util.read_in_task(path)
  local handle = io.open(path, "rb")
  if not handle then return nil end
  local parts = {}
  local started = os.clock()
  while true do
    local chunk = handle:read(Store.CHUNK_BYTES)
    if not chunk then break end
    parts[#parts + 1] = chunk
    if os.clock() - started >= FRAME_BUDGET then
      coroutine.yield()
      started = os.clock()
    end
  end
  handle:close()
  return table.concat(parts)
end

-- Parsed versions are kept for small projects only; a parsed project holds
-- its whole file text.
function util.parse_in_task(path)
  local cached = state.parsed[path]
  if cached then return cached end
  local text = util.read_in_task(path)
  if not text then return nil, "Version file is missing" end
  local project, err = Diff.parse(text, { budget = FRAME_BUDGET })
  if project and #text <= PARSE_CACHE_LIMIT then
    state.parsed[path] = project
    state.parsed_order[#state.parsed_order + 1] = path
    if #state.parsed_order > 3 then state.parsed[table.remove(state.parsed_order, 1)] = nil end
  end
  return project, err
end

-- Slider names for a JSFX as REAPER would load it (paths in the project are
-- relative to Effects/, and stock effects often have no extension). Read once
-- per session; the result is false when the file cannot be found.
local js_cache = {}

function util.js_info(path)
  path = tostring(path or "")
  local cached = js_cache[path]
  if cached ~= nil then return cached or nil end
  local base = Store.join(r.GetResourcePath(), "Effects", path)
  local source = Store.read_file(base) or Store.read_file(base .. ".jsfx")
  local info = source and Diff.parse_jsfx_sliders(source) or nil
  js_cache[path] = info or false
  return info
end

-- The budget lets a comparison running in a background task hand the frame
-- back between tracks; outside a task it has no effect.
util.diff_options = { js_info = util.js_info, budget = FRAME_BUDGET }

-- Histories -------------------------------------------------------------------

local history = {}

function history.all(app)
  local root = util.root(app)
  if not state.histories or state.histories_root ~= root then
    state.histories = {}
    state.histories_root = root
    for _, manifest in ipairs(Store.scan(root)) do state.histories[manifest.id] = manifest end
  end
  return state.histories
end

function history.store_pair(manifest, snapshot, previous, result)
  state.pair_results[manifest.id] = state.pair_results[manifest.id] or {}
  state.pair_results[manifest.id][snapshot.file] = { base = previous.file, result = result }
end

function history.pair(manifest, snapshot, previous)
  local stored = state.pair_results[manifest.id] and state.pair_results[manifest.id][snapshot.file]
  if stored and stored.base == previous.file then return stored end
  return nil
end

function history.remember(manifest)
  if state.histories then state.histories[manifest.id] = manifest end
end

-- The history a project belongs to, without changing anything.
function history.for_project(app, project, path)
  local all = history.all(app)
  local id = project and Store.project_id(project)
  if id and all[id] then return all[id] end
  if path and path ~= "" then
    local wanted = Store.normalize_path(path)
    for _, manifest in pairs(all) do
      if Store.normalize_path(manifest.path) == wanted then return manifest end
    end
  end
  return nil
end

-- The history a save should go into. Writes the id into the project when it
-- has none yet, or when it turns out to be a copy of another project.
function history.for_capture(app, project, path)
  local all = history.all(app)
  local id = Store.project_id(project)
  local known = id and all[id]
  if known then
    local old_path = known.path or ""
    if old_path ~= "" and Store.normalize_path(old_path) ~= Store.normalize_path(path) and Store.file_exists(old_path) then
      -- The original is still there, so this is a Save As or a copied
      -- folder: a new history that remembers where it came from.
      local manifest = Store.new_manifest(Store.new_id(), path, known.id)
      Store.set_project_id(project, manifest.id)
      return manifest, "copy"
    end
    return known, old_path ~= "" and Store.normalize_path(old_path) ~= Store.normalize_path(path) and "moved" or nil
  end
  if id then return Store.new_manifest(id, path), nil end
  local wanted = Store.normalize_path(path)
  for _, manifest in pairs(all) do
    if Store.normalize_path(manifest.path) == wanted then
      Store.set_project_id(project, manifest.id)
      return manifest, nil
    end
  end
  local manifest = Store.new_manifest(Store.new_id(), path)
  Store.set_project_id(project, manifest.id)
  return manifest, nil
end

-- Background work -------------------------------------------------------------

local worker = {}

function worker.poll(app)
  local now = r.time_precise()
  if now - state.last_poll < POLL_SECONDS then return end
  state.last_poll = now
  local settings = util.settings(app)
  local seen = {}
  local index = 0
  while true do
    local project, path = r.EnumProjects(index, "")
    if not project then break end
    local key = tostring(project)
    local dirty = r.IsProjectDirty(project) ~= 0
    local previous = state.projects[key]
    if previous and previous.dirty and not dirty and path and path ~= "" and settings.enabled then
      worker.enqueue(project, path)
    end
    state.projects[key] = { dirty = dirty, path = path }
    seen[key] = true
    index = index + 1
  end
  for key in pairs(state.projects) do
    if not seen[key] then state.projects[key] = nil end
  end
end

function worker.enqueue(project, path)
  for _, entry in ipairs(state.queue) do
    if entry.path == path then return end
  end
  state.queue[#state.queue + 1] = { project = project, path = path }
end

function worker.start_next(app)
  local entry = table.remove(state.queue, 1)
  if not entry then return end
  if r.ValidatePtr and not r.ValidatePtr(entry.project, "ReaProject*") then return end
  local settings = util.settings(app)
  local size = Store.file_size(entry.path)
  if not size then return end
  local limit = (tonumber(settings.max_project_mb) or 0) * 1024 * 1024
  if limit > 0 and size > limit then
    util.set_status("Not recorded: project is " .. util.megabytes(size) .. ", limit is " .. tostring(settings.max_project_mb) .. " MB")
    return
  end
  local root = util.root(app)
  Store.ensure_dir(root)
  local manifest, how = history.for_capture(app, entry.project, entry.path)
  local job = Store.begin_capture(root, manifest, entry.path)
  job.how = how
  if job.error then
    util.set_status(job.error)
    return
  end
  state.job = job
end

function worker.finish_capture(app, job)
  if job.error then
    util.set_status(job.error)
    return
  end
  if job.result ~= "saved" then return end
  local manifest = job.manifest
  history.remember(manifest)
  local settings = util.settings(app)
  Store.prune(job.root, manifest, {
    keep_all_hours = tonumber(settings.keep_all_hours) or 24,
    keep_hourly_days = tonumber(settings.keep_hourly_days) or 7,
    max_bytes = (tonumber(settings.max_history_mb) or 0) * 1024 * 1024
  })
  worker.queue_summaries(manifest)
  local note = job.how == "moved" and " (project moved: history followed)" or (job.how == "copy" and " (new history for this copy)" or "")
  util.set_status("Version " .. tostring(#manifest.snapshots) .. " recorded" .. note)
  -- The newest version moved on; comparisons against "newest" are stale.
  state.diff_cache = {}
  state.diff_order = {}
end

function worker.queue_summaries(manifest)
  for index = 2, #manifest.snapshots do
    local snapshot = manifest.snapshots[index]
    local stale = snapshot.summary == nil or snapshot.summary_version ~= SUMMARY_VERSION
    if stale and not snapshot.summary_failed and (snapshot.size or 0) <= SUMMARY_SIZE_LIMIT then
      local key = manifest.id .. "|" .. snapshot.file
      if not state.summary_queue[key] then
        state.summary_queue[key] = true
        state.summary_queue[#state.summary_queue + 1] = { manifest = manifest, file = snapshot.file, key = key }
      end
    end
  end
end

function worker.start_summary(app)
  local entry = table.remove(state.summary_queue, 1)
  if not entry then return end
  state.summary_queue[entry.key] = nil
  local manifest = entry.manifest
  local root = util.root(app)
  local index
  for i, snapshot in ipairs(manifest.snapshots) do
    if snapshot.file == entry.file then index = i end
  end
  if not index or index < 2 then return end
  local snapshot, previous = manifest.snapshots[index], manifest.snapshots[index - 1]
  if snapshot.summary ~= nil and snapshot.summary_version == SUMMARY_VERSION then return end
  state.summary_task = {
    co = coroutine.create(function()
      local old_project, old_err = util.parse_in_task(Store.snapshot_path(root, manifest, previous))
      local new_project, new_err = util.parse_in_task(Store.snapshot_path(root, manifest, snapshot))
      if not old_project or not new_project then
        snapshot.summary_failed = old_err or new_err or true
        return
      end
      local result = Diff.diff(old_project, new_project, util.diff_options)
      history.store_pair(manifest, snapshot, previous, result)
      snapshot.summary = Diff.summary(result.counts) or ""
      snapshot.counts = result.counts
      snapshot.summary_base = previous.file
      snapshot.summary_version = SUMMARY_VERSION
      Store.save_manifest(root, manifest)
    end)
  }
end

function worker.step(app)
  local job = state.job
  if job then
    local more
    if job.kind == "capture" then
      more = Store.step_capture(job, FRAME_BUDGET)
    elseif job.kind == "import" then
      more = Store.step_import(job, FRAME_BUDGET)
    else
      more = Store.step_migration(job, FRAME_BUDGET)
    end
    if not more then
      state.job = nil
      if job.kind == "capture" then
        worker.finish_capture(app, job)
      elseif job.kind == "import" then
        worker.finish_import(app, job)
      else
        worker.finish_migration(app, job)
      end
    end
    return
  end
  if #state.queue > 0 then
    worker.start_next(app)
    return
  end
  if state.diff_task then
    if util.resume(state.diff_task) then
      local task = state.diff_task
      state.diff_task = nil
      if task.error then task.result = { error = task.error } end
      if task.result then
        state.diff_cache[task.key] = task.result
        state.diff_order[#state.diff_order + 1] = task.key
        if #state.diff_order > 8 then state.diff_cache[table.remove(state.diff_order, 1)] = nil end
      end
    end
    return
  end
  if state.timeline_task then
    if util.resume(state.timeline_task) then
      state.timeline_task.done = true
      if state.focus then state.focus.task = state.timeline_task end
      state.timeline_task = nil
    end
    return
  end
  if state.summary_task then
    if util.resume(state.summary_task) then state.summary_task = nil end
    return
  end
  if #state.summary_queue > 0 then worker.start_summary(app) end
end

-- Compares every kept version with the one before it, reusing what the
-- summaries already worked out, then the open project with the newest
-- version. Each version file is read once.
function worker.start_timeline(app, manifest)
  local root = util.root(app)
  local task = {
    manifest_id = manifest.id,
    count = #manifest.snapshots,
    total = math.max(0, #manifest.snapshots - 1),
    done_count = 0,
    change_count = r.GetProjectStateChangeCount(0)
  }
  task.co = coroutine.create(function()
    local held_file, held_project = nil, nil
    local function parsed(snapshot)
      if held_file == snapshot.file then return held_project end
      return util.parse_in_task(Store.snapshot_path(root, manifest, snapshot))
    end
    for index = 2, #manifest.snapshots do
      local snapshot, previous = manifest.snapshots[index], manifest.snapshots[index - 1]
      if not history.pair(manifest, snapshot, previous) then
        if (snapshot.size or 0) > SUMMARY_SIZE_LIMIT or (previous.size or 0) > SUMMARY_SIZE_LIMIT then
          state.pair_results[manifest.id] = state.pair_results[manifest.id] or {}
          state.pair_results[manifest.id][snapshot.file] = { base = previous.file, skipped = true }
        else
          local old_project = parsed(previous)
          local new_project = parsed(snapshot)
          if old_project and new_project then
            history.store_pair(manifest, snapshot, previous, Diff.diff(old_project, new_project, util.diff_options))
          end
          held_file, held_project = snapshot.file, new_project
        end
      end
      task.done_count = index - 1
      coroutine.yield()
    end
    local newest = manifest.snapshots[#manifest.snapshots]
    -- Reading the open project is the one step that cannot be sliced, so
    -- big projects leave the unsaved row out ("Versus now" still has it).
    if newest and (newest.size or 0) <= LIVE_AUTO_BYTES then
      local reference = parsed(newest)
      if reference then
        local ok, live = pcall(Restore.capture_live, reference)
        if ok and live then
          task.live = { project = live, result = Diff.diff(reference, live, util.diff_options), base = newest.file }
          task.live.snapshot = { file = "timeline-now#" .. tostring(os.time()), time = os.time(), live = true }
        end
      end
    end
  end)
  state.timeline_task = task
end

function worker.finish_import(app, job)
  history.remember(job.manifest)
  worker.queue_summaries(job.manifest)
  state.diff_cache = {}
  state.diff_order = {}
  state.selected_history = nil
  state.backups_found = nil
  local text = "Imported " .. tostring(job.imported) .. " REAPER backups"
  if job.skipped > 0 then text = text .. " (" .. tostring(job.skipped) .. " were already in the history)" end
  util.set_status(text)
end

function worker.start_import(app, project, path)
  if state.job then
    util.set_status("Busy; try again in a moment")
    return
  end
  local backups = Store.find_backups(path)
  if #backups == 0 then
    util.set_status("No REAPER backups (.rpp-bak) found for this project")
    return
  end
  local root = util.root(app)
  Store.ensure_dir(root)
  local manifest = history.for_capture(app, project, path)
  state.job = Store.begin_import(root, manifest, backups)
  util.set_status("Importing " .. tostring(#backups) .. " backups...")
end

function worker.finish_migration(app, job)
  if job.error then
    util.set_status("Move stopped: " .. job.error)
    return
  end
  local settings = util.settings(app)
  settings.location = job.new_location
  if app.save_settings then app.save_settings() end
  state.histories = nil
  state.diff_cache = {}
  state.diff_order = {}
  state.parsed = {}
  state.parsed_order = {}
  util.set_status("Moved " .. tostring(job.moved) .. " histories to " .. job.new_root)
end

-- Location changes --------------------------------------------------------------

local location = {}

function location.apply(app, new_location, move)
  local settings = util.settings(app)
  local old_root = util.root(app)
  local new_root = Store.root_for(new_location)
  if Store.normalize_path(old_root) == Store.normalize_path(new_root) then
    util.set_status("That is already the storage location")
    return
  end
  Store.ensure_dir(new_root)
  if move then
    local job = Store.begin_migration(old_root, new_root)
    job.new_location = new_location
    if job.total == 0 then
      worker.finish_migration(app, job)
    else
      state.job = job
      util.set_status("Moving " .. tostring(job.total) .. " histories...")
    end
  else
    settings.location = new_location
    if app.save_settings then app.save_settings() end
    state.histories = nil
    util.set_status("Now storing in " .. new_root)
  end
end

-- Drawing -----------------------------------------------------------------------

local view = {}

function view.kind_style(kind)
  local bg = Theme.colors.child_bg or Theme.colors.window_bg
  if kind == "added" then return "+", Theme.text_for_background(bg, 0x7FC97FFF, nil, 3) end
  if kind == "removed" then return "-", Theme.text_for_background(bg, Theme.colors.danger, nil, 3) end
  return "~", Theme.text_for_background(bg, Theme.colors.text, nil, 4.5)
end

function view.header(app, manifest, project_name)
  local ctx = app.ctx
  local avail_w = r.ImGui_GetContentRegionAvail(ctx)
  local link_w = UIScale.text_button_w(ctx, "More...", 56)
  local settings_w = UIScale.text_button_w(ctx, "Settings", 60)
  local track_w = manifest and UIScale.text_button_w(ctx, "Track", 48) or 0
  local ab_active = view.ab_valid()
  local ab_w = ab_active and UIScale.text_button_w(ctx, "A/B", 40) or 0
  local spacing = UIScale.round(4)
  r.ImGui_TextColored(ctx, Theme.colors.accent, project_name)
  if manifest then
    r.ImGui_SameLine(ctx)
    r.ImGui_TextColored(ctx, Theme.colors.text_dim, tostring(#manifest.snapshots) .. " versions · " .. util.megabytes(Store.total_bytes(manifest)))
  end
  r.ImGui_SameLine(ctx)
  r.ImGui_SetCursorPosX(ctx, math.max(r.ImGui_GetCursorPosX(ctx), avail_w - link_w - settings_w - spacing - (manifest and (track_w + spacing) or 0) - (ab_active and (ab_w + spacing) or 0)))
  if ab_active then
    if r.ImGui_Button(ctx, "A/B##tm_ab", ab_w, 0) then view.ab_toggle(app) end
    UI.tooltip_when(app, r.ImGui_IsItemHovered(ctx), "Switch between the project and the opened old version, at the same play position. Also available as an action for a shortcut.")
    r.ImGui_SameLine(ctx, 0, spacing)
  end
  if manifest then
    if r.ImGui_Button(ctx, "Track##tm_track", track_w, 0) then view.focus_selected_track(app, manifest) end
    UI.tooltip_when(app, r.ImGui_IsItemHovered(ctx), "History of the track selected in REAPER")
    r.ImGui_SameLine(ctx, 0, spacing)
  end
  if r.ImGui_Button(ctx, "More...##tm_more", link_w, 0) then
    view.open_menu("Time Machine", {
      {
        label = "Link this project to a history...",
        tooltip = "Reconnect a history, for example after moving the project",
        fn = function() state.open_link = true; state.link_list = nil end
      },
      {
        label = "Borrow a track from a history...",
        tooltip = "Add a track from any saved version of any project as a new track here",
        fn = function() state.open_borrow = true end
      },
      {
        label = "Storage overview...",
        tooltip = "How much space each history takes, and clean up histories whose project is gone",
        fn = function() state.open_storage = true; state.storage_list = nil; state.storage_confirm = nil end
      }
    })
  end
  r.ImGui_SameLine(ctx, 0, spacing)
  if r.ImGui_Button(ctx, "Settings##tm_settings", settings_w, 0) then
    state.open_settings = true
    state.location_text = nil
  end
end

function view.version_row(app, manifest, snapshot, index, width)
  local ctx = app.ctx
  local row_h = r.ImGui_GetTextLineHeight(ctx) * 2 + UIScale.round(10)
  local selected = state.selected == snapshot.file
  if r.ImGui_Selectable(ctx, "##tm_v_" .. snapshot.file, selected, 0, width, row_h) then
    state.selected = snapshot.file
  end
  local x, y = r.ImGui_GetItemRectMin(ctx)
  local draw_list = r.ImGui_GetWindowDrawList(ctx)
  local pad = UIScale.round(6)
  local line_h = r.ImGui_GetTextLineHeight(ctx)
  local labelled = Store.is_labelled(snapshot)
  local title = util.when(snapshot.time)
  if labelled then title = snapshot.label .. "  ·  " .. title end
  if index == #manifest.snapshots then title = title .. "  (newest)" end
  local summary
  if index == 1 then
    summary = "Oldest version kept"
  elseif snapshot.summary == nil then
    summary = snapshot.summary_failed and "Could not compare" or "Comparing..."
  elseif snapshot.summary == "" then
    summary = "Only view or selection changes"
  else
    summary = snapshot.summary
  end
  r.ImGui_DrawList_PushClipRect(draw_list, x, y, x + width, y + row_h, true)
  if labelled then
    r.ImGui_DrawList_AddRectFilled(draw_list, x, y + UIScale.round(3), x + UIScale.round(3), y + row_h - UIScale.round(3), Theme.colors.accent, UIScale.px(1))
  end
  r.ImGui_DrawList_AddText(draw_list, x + pad, y + pad * 0.5, (selected or labelled) and Theme.colors.accent or Theme.colors.text, title)
  r.ImGui_DrawList_AddText(draw_list, x + pad, y + pad * 0.5 + line_h + UIScale.round(2), Theme.colors.text_dim, summary)
  r.ImGui_DrawList_PopClipRect(draw_list)
  if r.ImGui_IsItemHovered(ctx) then
    local tip = os.date("%A %d %B %Y, %H:%M:%S", snapshot.time) .. "\n" .. util.megabytes(snapshot.size) .. "\n" .. tostring(snapshot.path or "")
    if labelled then tip = snapshot.label .. "\n" .. tip .. "\nLabelled versions are never cleaned up." end
    if type(snapshot.note) == "string" and snapshot.note ~= "" then tip = tip .. "\n\n" .. snapshot.note end
    UI.tooltip_when(app, true, tip .. "\n\nRight-click for more")
  end
  if r.ImGui_IsItemClicked(ctx, 1) then
    local actions = {
      {
        label = labelled and "Edit label..." or "Label this version...",
        tooltip = "A name and a note for this version. Labelled versions are kept forever.",
        fn = function() view.begin_label(manifest, snapshot) end
      }
    }
    if labelled then
      actions[#actions + 1] = {
        label = "Remove label",
        tooltip = "The version is then cleaned up like any other",
        fn = function() view.save_label(app, manifest, snapshot, "", snapshot.note) end
      }
    end
    actions[#actions + 1] = { separator = true }
    actions[#actions + 1] = {
      label = "Open as a copy in a new tab",
      tooltip = "Writes a copy next to the current project, so its media paths still work, and opens it in a new project tab.",
      fn = function() view.open_copy(app, manifest, snapshot) end
    }
    view.open_menu(labelled and snapshot.label or util.when(snapshot.time), actions)
  end
end

-- A/B ----------------------------------------------------------------------------

function view.ab_valid()
  local ab = state.ab
  if not ab then return false end
  local valid = r.ValidatePtr and r.ValidatePtr(ab.a, "ReaProject*") and r.ValidatePtr(ab.b, "ReaProject*")
  if not valid then state.ab = nil end
  return valid and true or false
end

-- Flips between the project and the opened old version. Only the project in
-- front plays, so the play (or cursor) position is carried over and playback
-- restarted there, which makes the comparison a matter of one key.
function view.ab_toggle(app)
  if not view.ab_valid() then
    util.set_status("Open an old version as a copy first (right-click a version)")
    return
  end
  local current = r.EnumProjects(-1, "")
  local target = current == state.ab.a and state.ab.b or state.ab.a
  local playing = (r.GetPlayStateEx(current) & 1) == 1
  local position = playing and r.GetPlayPositionEx(current) or r.GetCursorPositionEx(current)
  if playing then r.OnStopButtonEx(current) end
  r.SelectProjectInstance(target)
  r.SetEditCurPos2(target, position, true, false)
  if playing then r.OnPlayButtonEx(target) end
  util.set_status(target == state.ab.a and "A: the project" or "B: " .. tostring(state.ab.label))
end

-- Changelog --------------------------------------------------------------------

function util.copy(app, text)
  if r.ImGui_SetClipboardText then
    r.ImGui_SetClipboardText(app.ctx, text)
  elseif r.CF_SetClipboard then
    r.CF_SetClipboard(text)
  else
    util.set_status("No clipboard available")
    return
  end
  util.set_status("Copied to the clipboard")
end

local KIND_MARK = { added = "+", removed = "-", changed = "~" }

function view.changelog_lines(lines, result, indent)
  indent = indent or ""
  if #result.project > 0 then
    lines[#lines + 1] = indent .. "Project"
    for _, entry in ipairs(result.project) do lines[#lines + 1] = indent .. "  " .. (KIND_MARK[entry.kind] or "~") .. " " .. entry.text end
  end
  for _, group in ipairs(result.tracks) do
    lines[#lines + 1] = indent .. tostring(group.index) .. " · " .. tostring(group.name)
    for _, entry in ipairs(group.entries) do lines[#lines + 1] = indent .. "  " .. (KIND_MARK[entry.kind] or "~") .. " " .. entry.text end
  end
  return lines
end

-- Labels --------------------------------------------------------------------------

function view.begin_label(manifest, snapshot)
  state.label_edit = {
    manifest = manifest,
    snapshot = snapshot,
    label = snapshot.label or "",
    note = snapshot.note or "",
    open = true
  }
end

function view.save_label(app, manifest, snapshot, label, note)
  label = tostring(label or ""):match("^%s*(.-)%s*$")
  note = tostring(note or ""):match("^%s*(.-)%s*$")
  snapshot.label = label ~= "" and label or nil
  snapshot.note = note ~= "" and note or nil
  if Store.save_manifest(util.root(app), manifest) then
    util.set_status(label ~= "" and ("Labelled: " .. label) or "Label removed")
  else
    util.set_status("Could not save the label")
  end
end

-- Borrowing a track ------------------------------------------------------------------

function view.borrow_popup(app)
  local ctx = app.ctx
  if state.open_borrow then
    r.ImGui_OpenPopup(ctx, "Borrow Track")
    state.open_borrow = false
    state.histories = nil
    state.borrow = { filter = "" }
  end
  if not r.ImGui_BeginPopup(ctx, "Borrow Track") then return end
  local borrow = state.borrow or { filter = "" }
  state.borrow = borrow
  local list = {}
  for _, manifest in pairs(history.all(app)) do
    if #manifest.snapshots > 0 then list[#list + 1] = manifest end
  end
  table.sort(list, function(a, b) return (a.name or ""):lower() < (b.name or ""):lower() end)
  r.ImGui_TextColored(ctx, Theme.colors.text_dim, "1. Pick a project")
  r.ImGui_SetNextItemWidth(ctx, UIScale.round(240))
  local changed, value = r.ImGui_InputTextWithHint(ctx, "##tm_borrow_filter", "Filter", borrow.filter)
  if changed then borrow.filter = value end
  local column_h = UIScale.round(260)
  if r.ImGui_BeginChild(ctx, "##tm_borrow_projects", UIScale.round(240), column_h, 0) then
    local filter = borrow.filter:lower()
    for _, manifest in ipairs(list) do
      if filter == "" or (manifest.name or ""):lower():find(filter, 1, true) then
        if r.ImGui_Selectable(ctx, tostring(manifest.name) .. "##" .. manifest.id, borrow.manifest == manifest) then
          borrow.manifest = manifest
          borrow.snapshot = manifest.snapshots[#manifest.snapshots]
          borrow.project = nil
          borrow.error = nil
        end
      end
    end
    r.ImGui_EndChild(ctx)
  end
  r.ImGui_SameLine(ctx)
  r.ImGui_BeginGroup(ctx)
  local manifest = borrow.manifest
  if not manifest then
    r.ImGui_TextColored(ctx, Theme.colors.text_dim, "2. Pick a version and a track")
  else
    r.ImGui_TextColored(ctx, Theme.colors.text_dim, "2. Version")
    r.ImGui_SetNextItemWidth(ctx, UIScale.round(300))
    local function version_label(snapshot)
      return (Store.is_labelled(snapshot) and (snapshot.label .. "  ·  ") or "") .. util.when(snapshot.time)
    end
    if r.ImGui_BeginCombo(ctx, "##tm_borrow_version", version_label(borrow.snapshot)) then
      for index = #manifest.snapshots, 1, -1 do
        local snapshot = manifest.snapshots[index]
        if r.ImGui_Selectable(ctx, version_label(snapshot) .. "##" .. snapshot.file, snapshot == borrow.snapshot) then
          borrow.snapshot = snapshot
          borrow.project = nil
          borrow.error = nil
        end
      end
      r.ImGui_EndCombo(ctx)
    end
    if not borrow.project and not borrow.error then
      local ok, project = pcall(view.load_version, app, manifest, borrow.snapshot)
      if ok then borrow.project = project else borrow.error = tostring(project) end
    end
    if borrow.error then
      r.ImGui_TextColored(ctx, Theme.colors.danger, borrow.error)
    elseif r.ImGui_BeginChild(ctx, "##tm_borrow_tracks", UIScale.round(300), column_h - r.ImGui_GetFrameHeightWithSpacing(ctx) * 2, 0) then
      local project = borrow.project
      for _, id in ipairs(project.track_order) do
        local track = project.tracks[id]
        r.ImGui_PushID(ctx, id)
        if r.ImGui_SmallButton(ctx, "Add") then
          local selected = r.GetSelectedTrack(0, 0)
          local insert_index = selected and math.floor(r.GetMediaTrackInfo_Value(selected, "IP_TRACKNUMBER")) or r.CountTracks(0)
          local folder = tostring(manifest.path or ""):match("^(.*)[\\/][^\\/]+$")
          view.restore(app, "borrow track " .. Diff.track_label(track), function()
            return Restore.borrow_track(project, id, folder, insert_index)
          end)
        end
        r.ImGui_SameLine(ctx)
        local fx = track.fx and #track.fx.list or 0
        r.ImGui_Text(ctx, tostring(track.index) .. " · " .. Diff.track_label(track))
        r.ImGui_SameLine(ctx)
        r.ImGui_TextColored(ctx, Theme.colors.text_dim, string.format("%d FX, %d items", fx, #track.item_order))
        r.ImGui_PopID(ctx)
      end
      r.ImGui_EndChild(ctx)
    end
  end
  r.ImGui_EndGroup(ctx)
  r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Added after the selected track (or at the end) with new ids; media paths keep pointing at the original files. Ctrl+Z undoes it.")
  r.ImGui_EndPopup(ctx)
end

-- Storage overview ----------------------------------------------------------------

function view.storage_popup(app)
  local ctx = app.ctx
  if state.open_storage then
    r.ImGui_OpenPopup(ctx, "Time Machine Storage")
    state.open_storage = false
  end
  if not r.ImGui_BeginPopup(ctx, "Time Machine Storage") then return end
  if not state.storage_list then
    state.histories = nil
    local list = {}
    for _, manifest in pairs(history.all(app)) do
      list[#list + 1] = { manifest = manifest, bytes = Store.total_bytes(manifest), missing = not Store.file_exists(manifest.path) }
    end
    table.sort(list, function(a, b) return a.bytes > b.bytes end)
    state.storage_list = list
  end
  local total, missing_total, missing_count = 0, 0, 0
  for _, row in ipairs(state.storage_list) do
    total = total + row.bytes
    if row.missing then missing_total = missing_total + row.bytes; missing_count = missing_count + 1 end
  end
  r.ImGui_Text(ctx, string.format("%d histories, %s in %s", #state.storage_list, util.megabytes(total), util.root(app)))
  if missing_count > 0 then
    r.ImGui_TextColored(ctx, Theme.colors.warning, string.format("%d whose project file is gone (%s)", missing_count, util.megabytes(missing_total)))
  end
  local changed, value = r.ImGui_Checkbox(ctx, "Only histories whose project is gone", state.storage_missing_only)
  if changed then state.storage_missing_only = value end
  if r.ImGui_BeginChild(ctx, "##tm_storage_list", UIScale.round(560), UIScale.round(300), 0) then
    for _, row in ipairs(state.storage_list) do
      local manifest = row.manifest
      if not state.storage_missing_only or row.missing then
        r.ImGui_PushID(ctx, manifest.id)
        local last = manifest.snapshots[#manifest.snapshots]
        r.ImGui_Text(ctx, string.format("%s  ·  %d versions  ·  %s%s", tostring(manifest.name), #manifest.snapshots, util.megabytes(row.bytes), last and ("  ·  " .. util.when(last.time)) or ""))
        r.ImGui_SameLine(ctx)
        if state.storage_confirm == manifest.id then
          r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), Theme.colors.danger)
          if r.ImGui_SmallButton(ctx, "Delete for good") then
            local removed = Store.delete_history(util.root(app), manifest.id)
            state.pair_results[manifest.id] = nil
            state.storage_list = nil
            state.storage_confirm = nil
            state.histories = nil
            state.selected_history = nil
            util.set_status(string.format("Deleted the history of %s (%d files)", tostring(manifest.name), removed))
          end
          r.ImGui_PopStyleColor(ctx)
          r.ImGui_SameLine(ctx)
          if r.ImGui_SmallButton(ctx, "Keep") then state.storage_confirm = nil end
        elseif r.ImGui_SmallButton(ctx, "Delete...") then
          state.storage_confirm = manifest.id
        end
        r.ImGui_TextColored(ctx, row.missing and Theme.colors.danger or Theme.colors.text_dim, "    " .. tostring(manifest.path or "") .. (row.missing and "  (project not found)" or ""))
        r.ImGui_PopID(ctx)
        if not state.storage_list then break end
      end
    end
    r.ImGui_EndChild(ctx)
  end
  r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Deleting removes all versions of that project from Time Machine. The project itself is not touched.")
  r.ImGui_EndPopup(ctx)
end

function view.label_popup(app)
  local ctx = app.ctx
  local edit = state.label_edit
  if not edit then return end
  if edit.open then
    r.ImGui_OpenPopup(ctx, "Label Version")
    edit.open = false
  end
  if not r.ImGui_BeginPopup(ctx, "Label Version") then
    if not edit.open then state.label_edit = nil end
    return
  end
  r.ImGui_TextColored(ctx, Theme.colors.text_dim, os.date("%A %d %B %Y, %H:%M", edit.snapshot.time))
  if r.ImGui_IsWindowAppearing(ctx) then r.ImGui_SetKeyboardFocusHere(ctx) end
  r.ImGui_SetNextItemWidth(ctx, UIScale.round(320))
  local changed, value = r.ImGui_InputTextWithHint(ctx, "##tm_label", "Label, e.g. Mix v1 sent to client", edit.label)
  if changed then edit.label = value end
  changed, value = r.ImGui_InputTextMultiline(ctx, "##tm_note", edit.note, UIScale.round(320), r.ImGui_GetTextLineHeight(ctx) * 4)
  if changed then edit.note = value end
  r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Labelled versions are never cleaned up.")
  local button_w = UIScale.text_button_w(ctx, "Cancel", 70)
  if r.ImGui_Button(ctx, "Save", button_w, 0) then
    view.save_label(app, edit.manifest, edit.snapshot, edit.label, edit.note)
    state.label_edit = nil
    r.ImGui_CloseCurrentPopup(ctx)
  end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "Cancel", button_w, 0) then
    state.label_edit = nil
    r.ImGui_CloseCurrentPopup(ctx)
  end
  r.ImGui_EndPopup(ctx)
end

function view.version_list(app, manifest, width, height)
  local ctx = app.ctx
  if r.ImGui_BeginChild(ctx, "##tm_versions", width, height, 0) then
    local settings = util.settings(app)
    local any_label = false
    for _, snapshot in ipairs(manifest.snapshots) do
      if Store.is_labelled(snapshot) then any_label = true break end
    end
    if any_label or settings.labelled_only then
      local changed, value = r.ImGui_Checkbox(ctx, "Labelled only", settings.labelled_only == true)
      if changed then
        settings.labelled_only = value
        if app.save_settings then app.save_settings() end
      end
    end
    local inner_w = r.ImGui_GetContentRegionAvail(ctx)
    local shown = 0
    for index = #manifest.snapshots, 1, -1 do
      local snapshot = manifest.snapshots[index]
      if not settings.labelled_only or Store.is_labelled(snapshot) then
        view.version_row(app, manifest, snapshot, index, inner_w)
        shown = shown + 1
      end
    end
    if shown == 0 then
      r.ImGui_TextColored(ctx, Theme.colors.text_dim, "No labelled versions yet. Right-click a version to label it.")
    end
    view.draw_menu(app, "##tm_menu_versions")
    r.ImGui_EndChild(ctx)
  end
end

-- Menus -------------------------------------------------------------------------

-- One shared menu; whichever child window asked for it this frame opens it.
function view.open_menu(title, actions)
  state.menu = { title = title, actions = actions }
  state.menu_pending = true
end

function view.draw_menu(app, popup_id)
  local ctx = app.ctx
  if state.menu_pending then
    r.ImGui_OpenPopup(ctx, popup_id)
    state.menu_pending = false
    state.menu.popup_id = popup_id
  end
  if not state.menu or state.menu.popup_id ~= popup_id then return end
  if not r.ImGui_BeginPopup(ctx, popup_id) then return end
  r.ImGui_TextColored(ctx, Theme.colors.text_dim, tostring(state.menu.title or ""))
  r.ImGui_Separator(ctx)
  for index, action in ipairs(state.menu.actions or {}) do
    if action.separator then
      r.ImGui_Separator(ctx)
    else
      local disabled = action.disabled and r.ImGui_BeginDisabled
      if disabled then r.ImGui_BeginDisabled(ctx, true) end
      if r.ImGui_Selectable(ctx, action.label .. "##tm_action_" .. tostring(index), false) and not action.disabled then
        action.fn()
        r.ImGui_CloseCurrentPopup(ctx)
      end
      if disabled then r.ImGui_EndDisabled(ctx) end
      if action.tooltip and r.ImGui_IsItemHovered(ctx, r.ImGui_HoveredFlags_AllowWhenDisabled and r.ImGui_HoveredFlags_AllowWhenDisabled() or 0) then
        UI.tooltip_when(app, true, action.tooltip)
      end
    end
  end
  r.ImGui_EndPopup(ctx)
end

-- Restoring -----------------------------------------------------------------------

-- The parsed older version of the pair on screen. Restores are rare and
-- deliberate, so a version that is not cached is read right here.
function view.load_version(app, manifest, snapshot)
  if snapshot.live then
    if snapshot.project then return snapshot.project end
    return state.live.project
  end
  local path = Store.snapshot_path(util.root(app), manifest, snapshot)
  if state.parsed[path] then return state.parsed[path] end
  local text = Store.read_file(path)
  if not text then error("The version file is missing: " .. path) end
  local project = assert(Diff.parse(text))
  if #text <= PARSE_CACHE_LIMIT then
    state.parsed[path] = project
    state.parsed_order[#state.parsed_order + 1] = path
    if #state.parsed_order > 3 then state.parsed[table.remove(state.parsed_order, 1)] = nil end
  end
  return project
end

-- Plugins whose saved blob changed can be asked which parameters moved.
function view.explainable(entry)
  return entry.area == "fx" and entry.old_fx and entry.fx and entry.fx.tag ~= "JS" and entry.fx.tag ~= "CONTAINER"
    and entry.text:find("state changed", 1, true) ~= nil
end

function view.param_key(pair, entry)
  return table.concat({ pair.manifest.id, pair.old_snapshot.file, pair.new_snapshot.file, tostring(entry.chain), tostring(entry.fx.id or entry.fx_key) }, "|")
end

-- Loads each plugin's two states on a hidden temporary track. All of them
-- share one undo point, which only marks the comparison: the temporary track
-- is gone again when it ends.
function view.explain(app, pair, entries)
  local old_project = view.load_version(app, pair.manifest, pair.old_snapshot)
  local new_project = view.load_version(app, pair.manifest, pair.new_snapshot)
  local done = 0
  Restore.run("compare plugin settings (nothing was changed)", function()
    for _, entry in ipairs(entries) do
      local old_block = old_project.text:sub(entry.old_fx.block_start, entry.old_fx.block_end)
      local new_block = new_project.text:sub(entry.fx.block_start, entry.fx.block_end)
      local changes, err = Restore.compare_plugin_params(old_block, new_block)
      state.param_cache[view.param_key(pair, entry)] = changes and { changes = changes } or { error = err }
      done = done + 1
    end
    return true
  end)
  util.set_status("Compared " .. tostring(done) .. " plugin" .. (done == 1 and "" or "s"))
end

function view.draw_params(app, pair, entry)
  if not view.explainable(entry) then return end
  local cached = state.param_cache[view.param_key(pair, entry)]
  if not cached then return end
  local ctx = app.ctx
  r.ImGui_Indent(ctx)
  if cached.error then
    r.ImGui_TextColored(ctx, Theme.colors.danger, tostring(cached.error))
  elseif #cached.changes == 0 then
    r.ImGui_TextColored(ctx, Theme.colors.text_dim, "No parameter differs: only the plugin's own saved data changed.")
  else
    for index, line in ipairs(cached.changes) do
      if index > 12 then
        r.ImGui_TextColored(ctx, Theme.colors.text_dim, "... and " .. tostring(#cached.changes - 12) .. " more")
        break
      end
      r.ImGui_TextWrapped(ctx, line)
    end
  end
  r.ImGui_Unindent(ctx)
end

function view.restore(app, label, fn)
  local ok, message = Restore.run(label, fn)
  if ok then
    util.set_status(tostring(message or "Restored") .. ". Ctrl+Z undoes it.")
  else
    util.set_status("Could not restore: " .. tostring(message or "unknown error"))
  end
end

-- What can be done with one line of the comparison. The older version of the
-- pair is the one restored to.
function view.entry_actions(app, pair, group, entry)
  local when = util.when(pair.old_snapshot.time)
  local id = group and group.id or nil
  local function old() return view.load_version(app, pair.manifest, pair.old_snapshot) end
  local function new() return view.load_version(app, pair.manifest, pair.new_snapshot) end
  local actions = {}
  local function add(label, undo_label, fn)
    actions[#actions + 1] = { label = label, fn = function() view.restore(app, undo_label, fn) end }
  end
  local area = entry.area
  if area == "fx" then
    local chain = entry.chain
    local track_id = chain ~= "Master" and id or nil
    if entry.order then
      if chain == nil and id then
        add("Put the FX chain back as on " .. when, "restore FX chain", function() return Restore.track_parts(old(), id, { fx = true }) end)
      end
    else
      local fx = entry.old_fx or entry.fx
      local fx_id = fx and fx.id
      if fx_id and not state.focus then
        actions[#actions + 1] = {
          label = "Show this plugin's history",
          fn = function()
            local plugin_name = entry.text:match("^(.-) state changed") or entry.text:match("^(.-) added") or entry.text:match("^(.-) removed") or Diff.fx_display_name(fx)
            view.open_focus(app, pair.manifest, { kind = "plugin", fx_id = fx_id, name = plugin_name })
          end
        }
      end
      if view.explainable(entry) then
        actions[#actions + 1] = {
          label = "Show which parameters changed",
          tooltip = "Loads both versions of the plugin on a hidden temporary track to read their parameters",
          fn = function() view.explain(app, pair, { entry }) end
        }
      end
      if fx_id then
        local label = "Put this plugin back as on " .. when
        if entry.kind == "added" then label = "Remove this plugin (it was not there on " .. when .. ")" end
        if entry.kind == "removed" then label = "Bring this plugin back" end
        add(label, "restore plugin", function() return Restore.fx(old(), track_id, chain, fx_id) end)
      end
    end
  elseif area == "items" and id then
    add("Put this track's items back as on " .. when, "restore items", function() return Restore.track_parts(old(), id, { items = true }) end)
  elseif area == "envelopes" and id then
    add("Put this envelope back as on " .. when, "restore envelope", function() return Restore.envelope(old(), id, entry.envelope) end)
  elseif area == "misc" and id then
    if entry.param then
      add("Put this back as on " .. when, "restore " .. entry.param, function() return Restore.track_value(id, entry.param, entry.value) end)
    elseif entry.keys then
      add("Put this back as on " .. when, "restore track settings", function() return Restore.track_lines(old(), id, entry.keys) end)
    end
  elseif area == "master" and entry.param then
    add("Put this back as on " .. when, "restore master", function() return Restore.track_value(nil, entry.param, entry.value) end)
  elseif area == "markers" then
    local label = entry.kind == "added" and "Remove it (it was not there on " .. when .. ")" or "Put it back as on " .. when
    add(label, "restore marker", function() return Restore.marker(old(), entry.marker, new()) end)
  elseif area == "track" and id then
    if group.status == "removed" then
      add("Bring this track back", "bring back track", function() return Restore.bring_back_track(old(), id) end)
    elseif group.status == "added" then
      add("Remove this track (it was not there on " .. when .. ")", "remove track", function() return Restore.remove_track(id) end)
    end
  end
  return actions
end

function view.group_actions(app, pair, group)
  local when = util.when(pair.old_snapshot.time)
  local id = group.id
  local function old() return view.load_version(app, pair.manifest, pair.old_snapshot) end
  local actions = {}
  local function add(label, undo_label, fn, tooltip)
    actions[#actions + 1] = { label = label, tooltip = tooltip, fn = function() view.restore(app, undo_label, fn) end }
  end
  if group.status == "removed" then
    add("Bring this track back", "bring back track", function() return Restore.bring_back_track(old(), id) end,
      "Inserts it where it used to be, with its FX, items and envelopes as on " .. when)
    return actions
  end
  if group.status == "added" then
    add("Remove this track", "remove track", function() return Restore.remove_track(id) end, "It was not in the project on " .. when)
    return actions
  end
  add("Whole track as on " .. when, "restore track", function() return Restore.whole_track(old(), id) end,
    "FX, items, envelopes and mixer settings. Sends to and from other tracks keep pointing at this track.")
  add("FX chain", "restore FX chain", function() return Restore.track_parts(old(), id, { fx = true }) end)
  add("Items", "restore items", function() return Restore.track_parts(old(), id, { items = true }) end)
  add("Envelopes", "restore envelopes", function() return Restore.track_parts(old(), id, { envelopes = true }) end)
  add("Mixer settings", "restore mixer settings", function() return Restore.track_parts(old(), id, { misc = true }) end,
    "Name, volume, pan, mute, solo, phase, record settings, automation mode and color")
  actions[#actions + 1] = { separator = true }
  local recall = app.modules_by_id and app.modules_by_id.track_recall
  actions[#actions + 1] = {
    label = "Save as Track Recall",
    disabled = not (recall and recall.add_recall_from_chunk),
    tooltip = "Keeps this track as it was on " .. when .. " as a recall in Track Recall, without changing the track now",
    fn = function()
      local ok, err = pcall(function()
        local track = Restore.find_track(id)
        if not track then error("That track is no longer in the project") end
        local chunk = Restore.old_track_chunk(old(), id)
        if not recall.add_recall_from_chunk(app, track, group.name .. " - " .. when, chunk) then error("Track Recall could not store it") end
      end)
      util.set_status(ok and ("Saved as Track Recall: " .. group.name .. " - " .. when) or ("Could not save: " .. tostring(err)))
    end
  }
  return actions
end

-- A copy beside the open project keeps relative media paths working; opening
-- the stored file itself would also let a save write into the history.
function view.open_copy(app, manifest, snapshot)
  local _, current_path = r.EnumProjects(-1, "")
  local folder = current_path and current_path:match("^(.*)[\\/][^\\/]+$")
  if not folder then
    util.set_status("Save the project first")
    return
  end
  local name = (manifest.name or "Project") .. " (Time Machine " .. os.date("%Y-%m-%d %H%M", snapshot.time) .. ").rpp"
  local target = Store.join(folder, name)
  if not Store.file_exists(target) then
    local text = Store.read_file(Store.snapshot_path(util.root(app), manifest, snapshot))
    if not text or not Store.write_file(target, text) then
      util.set_status("Could not write " .. target)
      return
    end
  end
  local original = r.EnumProjects(-1, "")
  r.Main_OnCommand(40859, 0) -- File: New project tab
  r.Main_openProject(target)
  local opened = r.EnumProjects(-1, "")
  if opened and opened ~= original then
    state.ab = { a = original, b = opened, label = util.when(snapshot.time) }
    util.set_status("Opened " .. name .. ". Use A/B to switch between them.")
  else
    util.set_status("Opened " .. name)
  end
end

-- The open project as a pseudo version. Reading it means fetching every
-- track's state chunk, so it is only done when the project changed: right
-- away for ordinary projects, on request for big ones.
function view.live_snapshot(app, manifest, reference, force)
  local count = r.GetProjectStateChangeCount(0)
  local live = state.live
  local same_target = live and live.manifest_id == manifest.id and live.reference == reference.file
  local fresh = same_target and live.change_count == count
  local can_auto = not live or (live.project and (live.project.bytes or 0) <= LIVE_AUTO_BYTES and r.time_precise() - live.captured_at >= LIVE_AUTO_SECONDS)
  if force or not same_target or (not fresh and can_auto) then
    local ok, project = pcall(function()
      return Restore.capture_live(view.load_version(app, manifest, reference))
    end)
    state.live_serial = state.live_serial + 1
    state.live = {
      manifest_id = manifest.id,
      reference = reference.file,
      change_count = count,
      captured_at = r.time_precise(),
      project = ok and project or nil,
      error = not ok and tostring(project) or nil,
      snapshot = { file = "now#" .. tostring(state.live_serial), time = os.time(), live = true }
    }
    live = state.live
  end
  live.stale = live.change_count ~= count
  return live
end

-- Which two versions to compare for the selection, as (old, new, caption).
function view.pair(app, manifest)
  local index
  for i, snapshot in ipairs(manifest.snapshots) do
    if snapshot.file == state.selected then index = i end
  end
  if not index then return nil end
  local settings = util.settings(app)
  local count = #manifest.snapshots
  if settings.compare == "now" then
    local live = view.live_snapshot(app, manifest, manifest.snapshots[index])
    if not live.project then return nil, nil, "Could not read the open project: " .. tostring(live.error) end
    return manifest.snapshots[index], live.snapshot, "Changed since " .. util.when(manifest.snapshots[index].time) .. ", unsaved changes included"
  end
  if settings.compare == "since" then
    if index == count then return nil, nil, "This is the newest version." end
    return manifest.snapshots[index], manifest.snapshots[count], "Changed since " .. util.when(manifest.snapshots[index].time)
  end
  if index == 1 then return nil, nil, "This is the oldest version kept; there is nothing before it to compare with." end
  return manifest.snapshots[index - 1], manifest.snapshots[index], "Changed in this save (since " .. util.when(manifest.snapshots[index - 1].time) .. ")"
end

function view.request_diff(app, manifest, old_snapshot, new_snapshot)
  local key = manifest.id .. "|" .. old_snapshot.file .. "|" .. new_snapshot.file
  local cached = state.diff_cache[key]
  if cached then return cached end
  if state.diff_task and state.diff_task.key ~= key then
    -- The selection moved on; the old comparison is not wanted any more.
    state.diff_task = nil
  end
  if not state.diff_task then
    local root = util.root(app)
    local task = { key = key }
    task.co = coroutine.create(function()
      local old_project, old_err = util.parse_in_task(Store.snapshot_path(root, manifest, old_snapshot))
      local new_project, new_err
      if new_snapshot.live then
        new_project = state.live and state.live.project
        new_err = "The open project could not be read"
      else
        new_project, new_err = util.parse_in_task(Store.snapshot_path(root, manifest, new_snapshot))
      end
      if not old_project or not new_project then
        task.result = { error = old_err or new_err or "Could not read a version" }
        return
      end
      task.result = Diff.diff(old_project, new_project, util.diff_options)
    end)
    state.diff_task = task
  end
  return nil, state.diff_task.progress
end

function view.entry(app, pair, group, entry)
  local ctx = app.ctx
  local symbol, color = view.kind_style(entry.kind)
  r.ImGui_TextColored(ctx, color, symbol)
  r.ImGui_SameLine(ctx)
  r.ImGui_TextWrapped(ctx, entry.text)
  local hovered = r.ImGui_IsItemHovered(ctx)
  if hovered then
    local lines = {}
    for i = 1, math.min(entry.details and #entry.details or 0, 14) do lines[#lines + 1] = entry.details[i] end
    if entry.details and #entry.details > 14 then lines[#lines + 1] = "... and " .. tostring(#entry.details - 14) .. " more" end
    if #lines > 0 then lines[#lines + 1] = "" end
    lines[#lines + 1] = "Right-click to put it back"
    UI.tooltip_when(app, true, table.concat(lines, "\n"))
  end
  if r.ImGui_IsItemClicked(ctx, 1) then
    local actions = view.entry_actions(app, pair, group, entry)
    if #actions == 0 then actions = { { label = "Time Machine cannot put this back on its own", disabled = true, fn = function() end } } end
    view.open_menu(entry.text, actions)
  end
  view.draw_params(app, pair, entry)
end

function view.group_header(app, pair, group)
  local ctx = app.ctx
  local _, color = view.kind_style(group.status)
  r.ImGui_TextColored(ctx, group.status == "changed" and Theme.colors.accent or color, tostring(group.index) .. " · " .. tostring(group.name))
  r.ImGui_SameLine(ctx)
  r.ImGui_PushID(ctx, "tm_group_" .. tostring(group.id))
  if r.ImGui_SmallButton(ctx, "Restore...") then
    view.open_menu(tostring(group.name), view.group_actions(app, pair, group))
  end
  r.ImGui_SameLine(ctx)
  if r.ImGui_SmallButton(ctx, "History") then
    view.open_focus(app, pair.manifest, { kind = "track", track_id = group.id, name = group.name })
  end
  UI.tooltip_when(app, r.ImGui_IsItemHovered(ctx), "Every saved change to this track, newest first")
  r.ImGui_PopID(ctx)
end

-- History of one track or plugin ---------------------------------------------------

-- kind "track": everything that happened to the track with this GUID.
-- kind "plugin": the lines about the plugin with this FXID, wherever it sat.
function view.open_focus(app, manifest, focus)
  focus.manifest_id = manifest.id
  state.focus = focus
  worker.start_timeline(app, manifest)
end

local function same_id(a, b)
  return a ~= nil and b ~= nil and tostring(a):upper() == tostring(b):upper()
end

-- The (group, entry) pairs of one comparison that concern the focus.
function view.focus_entries(result, focus)
  local found = {}
  if not result or result.error then return found end
  local function plugin_match(entry)
    if entry.area ~= "fx" then return false end
    return same_id(entry.fx and entry.fx.id, focus.fx_id) or same_id(entry.old_fx and entry.old_fx.id, focus.fx_id)
  end
  if focus.kind == "plugin" then
    for _, entry in ipairs(result.project) do
      if plugin_match(entry) then found[#found + 1] = { group = nil, entry = entry } end
    end
  end
  for _, group in ipairs(result.tracks) do
    for _, entry in ipairs(group.entries) do
      if (focus.kind == "track" and same_id(group.id, focus.track_id)) or (focus.kind == "plugin" and plugin_match(entry)) then
        found[#found + 1] = { group = group, entry = entry }
      end
    end
  end
  return found
end

function view.focus_selected_track(app, manifest)
  local track = r.GetSelectedTrack(0, 0)
  if not track then
    util.set_status("Select a track in REAPER first")
    return
  end
  local _, name = r.GetTrackName(track)
  view.open_focus(app, manifest, { kind = "track", track_id = r.GetTrackGUID(track), name = name })
end

function view.timeline_row(app, manifest, pair, title, found, show_index)
  local ctx = app.ctx
  r.ImGui_TextColored(ctx, Theme.colors.accent, title)
  if show_index then
    r.ImGui_SameLine(ctx)
    if r.ImGui_SmallButton(ctx, "Show##tm_tl_" .. tostring(show_index)) then
      state.selected = manifest.snapshots[show_index].file
      util.settings(app).compare = "previous"
      state.focus = nil
    end
    UI.tooltip_when(app, r.ImGui_IsItemHovered(ctx), "Open this save in the normal comparison")
  end
  r.ImGui_Indent(ctx)
  for _, item in ipairs(found) do view.entry(app, pair, item.group, item.entry) end
  r.ImGui_Unindent(ctx)
  r.ImGui_Spacing(ctx)
end

function view.copy_timeline(app, manifest, focus)
  local lines = { (focus.kind == "plugin" and "History of plugin " or "History of track ") .. tostring(focus.name) .. " (" .. tostring(manifest.name) .. ")", "" }
  for index = #manifest.snapshots, 2, -1 do
    local snapshot, previous = manifest.snapshots[index], manifest.snapshots[index - 1]
    local stored = history.pair(manifest, snapshot, previous)
    local found = stored and stored.result and view.focus_entries(stored.result, focus) or {}
    if #found > 0 then
      local title = os.date("%Y-%m-%d %H:%M", snapshot.time)
      if Store.is_labelled(snapshot) then title = title .. "  " .. snapshot.label end
      lines[#lines + 1] = title
      for _, item in ipairs(found) do lines[#lines + 1] = "  " .. (KIND_MARK[item.entry.kind] or "~") .. " " .. item.entry.text end
    end
  end
  util.copy(app, table.concat(lines, "\n"))
end

function view.timeline_panel(app, manifest, width, height)
  local ctx = app.ctx
  local focus = state.focus
  if not r.ImGui_BeginChild(ctx, "##tm_timeline", width, height, 0) then return end
  r.ImGui_TextColored(ctx, Theme.colors.text_dim, focus.kind == "plugin" and "History of plugin" or "History of track")
  r.ImGui_SameLine(ctx)
  r.ImGui_TextColored(ctx, Theme.colors.accent, tostring(focus.name or "?"))
  r.ImGui_SameLine(ctx)
  if r.ImGui_SmallButton(ctx, "Copy##tm_tl_copy") then view.copy_timeline(app, manifest, focus) end
  UI.tooltip_when(app, r.ImGui_IsItemHovered(ctx), "Copies this history as plain text")
  r.ImGui_SameLine(ctx)
  if r.ImGui_SmallButton(ctx, "Close##tm_tl_close") then state.focus = nil; r.ImGui_EndChild(ctx); return end
  if focus.task and not state.timeline_task and focus.task.change_count ~= r.GetProjectStateChangeCount(0) then
    r.ImGui_SameLine(ctx)
    if r.ImGui_SmallButton(ctx, "Refresh##tm_tl_refresh") then worker.start_timeline(app, manifest) end
    UI.tooltip_when(app, r.ImGui_IsItemHovered(ctx), "The project changed since this was read; Refresh updates the unsaved changes at the top")
  end
  r.ImGui_Separator(ctx)

  local task = state.timeline_task
  if task and task.manifest_id == manifest.id and not task.done then
    r.ImGui_TextColored(ctx, Theme.colors.text_dim, string.format("Reading history... %d of %d saves", task.done_count, task.total))
  else
    if not focus.task or focus.task.count ~= #manifest.snapshots then
      -- A save landed since; bring the comparisons up to date.
      if not state.timeline_task then worker.start_timeline(app, manifest) end
    end
    local rows = 0
    local live = focus.task and focus.task.live
    if live and live.base == (manifest.snapshots[#manifest.snapshots] or {}).file then
      local found = view.focus_entries(live.result, focus)
      if #found > 0 then
        live.snapshot.project = live.project
        local pair = { manifest = manifest, old_snapshot = manifest.snapshots[#manifest.snapshots], new_snapshot = live.snapshot }
        view.timeline_row(app, manifest, pair, "Now (not saved yet)", found, nil)
        rows = rows + 1
      end
    end
    local skipped = 0
    for index = #manifest.snapshots, 2, -1 do
      local snapshot, previous = manifest.snapshots[index], manifest.snapshots[index - 1]
      local stored = history.pair(manifest, snapshot, previous)
      if stored and stored.skipped then
        skipped = skipped + 1
      elseif stored then
        local found = view.focus_entries(stored.result, focus)
        if #found > 0 then
          local title = util.when(snapshot.time)
          if Store.is_labelled(snapshot) then title = snapshot.label .. "  ·  " .. title end
          local pair = { manifest = manifest, old_snapshot = previous, new_snapshot = snapshot }
          view.timeline_row(app, manifest, pair, title, found, index)
          rows = rows + 1
        end
      end
    end
    if rows == 0 then
      r.ImGui_TextColored(ctx, Theme.colors.text_dim, "No changes to it in the kept versions.")
    end
    local oldest = manifest.snapshots[1]
    if oldest then
      r.ImGui_TextColored(ctx, Theme.colors.text_dim, "History starts at the oldest kept version, " .. util.when(oldest.time) .. ".")
    end
    if skipped > 0 then
      r.ImGui_TextColored(ctx, Theme.colors.text_dim, tostring(skipped) .. " very large saves were not compared.")
    end
    r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Right-click a line to undo that change.")
  end
  view.draw_menu(app, "##tm_menu_timeline")
  r.ImGui_EndChild(ctx)
end

function view.diff_panel(app, manifest, width, height)
  if state.focus and state.focus.manifest_id == manifest.id then
    return view.timeline_panel(app, manifest, width, height)
  end
  local ctx = app.ctx
  local settings = util.settings(app)
  if not r.ImGui_BeginChild(ctx, "##tm_diff", width, height, 0) then return end
  local function mode(label, value, tooltip)
    if r.ImGui_RadioButton(ctx, label, settings.compare == value) then
      settings.compare = value
      if app.save_settings then app.save_settings() end
    end
    UI.tooltip_when(app, r.ImGui_IsItemHovered(ctx), tooltip)
  end
  if settings.compare ~= "since" and settings.compare ~= "now" then settings.compare = "previous" end
  mode("This save", "previous", "What changed between the version before and the selected one")
  r.ImGui_SameLine(ctx)
  mode("Since then", "since", "Everything that changed from the selected version up to the newest saved one")
  r.ImGui_SameLine(ctx)
  mode("Versus now", "now", "Everything that changed from the selected version up to the project as it is now, unsaved changes included. Select the newest version to see what you changed since the last save.")
  local old_snapshot, new_snapshot, caption = view.pair(app, manifest)
  if settings.compare == "now" and old_snapshot and state.live then
    if state.live.stale then
      if r.ImGui_SmallButton(ctx, "Refresh") then view.live_snapshot(app, manifest, old_snapshot, true) end
      r.ImGui_SameLine(ctx)
      r.ImGui_TextColored(ctx, Theme.colors.warning, "The project changed since this was read")
    end
  end
  if not state.selected then
    r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Select a version on the left.")
  elseif not old_snapshot then
    r.ImGui_TextColored(ctx, Theme.colors.text_dim, caption or "")
  else
    r.ImGui_TextColored(ctx, Theme.colors.text_dim, caption)
    r.ImGui_Separator(ctx)
    local result, progress = view.request_diff(app, manifest, old_snapshot, new_snapshot)
    if not result then
      r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Reading versions..." .. (progress and string.format(" %d%%", math.floor(progress * 100)) or ""))
    elseif result.error then
      r.ImGui_TextColored(ctx, Theme.colors.danger, tostring(result.error))
    elseif #result.project == 0 and #result.tracks == 0 then
      r.ImGui_TextColored(ctx, Theme.colors.text_dim, "No changes Time Machine can see. Selection, zoom and other view settings are ignored.")
    else
      local pair = { manifest = manifest, old_snapshot = old_snapshot, new_snapshot = new_snapshot }
      local unexplained = {}
      local function collect(entries)
        for _, entry in ipairs(entries) do
          if view.explainable(entry) and not state.param_cache[view.param_key(pair, entry)] then unexplained[#unexplained + 1] = entry end
        end
      end
      collect(result.project)
      for _, group in ipairs(result.tracks) do collect(group.entries) end
      if #unexplained > 0 then
        if r.ImGui_SmallButton(ctx, "Explain plugin changes (" .. tostring(#unexplained) .. ")") then view.explain(app, pair, unexplained) end
        r.ImGui_SameLine(ctx)
        UI.tooltip_when(app, r.ImGui_IsItemHovered(ctx), "Finds which parameters changed in plugins that only say \"state changed\". Each plugin is loaded twice on a hidden temporary track, which can take a moment for big instruments. The project is not changed, but it is marked as edited.")
      end
      if r.ImGui_SmallButton(ctx, "Copy as text##tm_copy_diff") then
        local lines = { (manifest.name or "Project") .. ": " .. caption, "" }
        util.copy(app, table.concat(view.changelog_lines(lines, result), "\n"))
      end
      UI.tooltip_when(app, r.ImGui_IsItemHovered(ctx), "Copies this list as plain text, for example to tell someone what changed in the mix")
      if #result.project > 0 then
        r.ImGui_TextColored(ctx, Theme.colors.accent, "Project")
        r.ImGui_Indent(ctx)
        for _, entry in ipairs(result.project) do view.entry(app, pair, nil, entry) end
        r.ImGui_Unindent(ctx)
      end
      for _, group in ipairs(result.tracks) do
        view.group_header(app, pair, group)
        r.ImGui_Indent(ctx)
        for _, entry in ipairs(group.entries) do view.entry(app, pair, group, entry) end
        r.ImGui_Unindent(ctx)
      end
      r.ImGui_Spacing(ctx)
      r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Right-click a line to put it back as on " .. util.when(old_snapshot.time) .. ". Restores change the open project and can be undone.")
      r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Plugin \"state changed\" means its saved data differs; some plugins rewrite it on every save.")
    end
  end
  view.draw_menu(app, "##tm_menu_diff")
  r.ImGui_EndChild(ctx)
end

function view.settings_popup(app)
  local ctx = app.ctx
  if state.open_settings then
    r.ImGui_OpenPopup(ctx, "Time Machine Settings")
    state.open_settings = false
    state.backups_found = nil
  end
  if not r.ImGui_BeginPopup(ctx, "Time Machine Settings") then return end
  local settings = util.settings(app)
  local changed_any = false
  local changed, value = r.ImGui_Checkbox(ctx, "Record a version on every save", settings.enabled)
  if changed then settings.enabled = value; changed_any = true end
  r.ImGui_Separator(ctx)
  r.ImGui_Text(ctx, "Storage location")
  r.ImGui_TextColored(ctx, Theme.colors.text_dim, util.root(app))
  if state.location_text == nil then state.location_text = settings.location ~= "" and settings.location or Store.default_location() end
  r.ImGui_SetNextItemWidth(ctx, UIScale.round(300))
  changed, value = r.ImGui_InputText(ctx, "##tm_location", state.location_text)
  if changed then state.location_text = value end
  if r.JS_Dialog_BrowseForFolder then
    r.ImGui_SameLine(ctx)
    if r.ImGui_Button(ctx, "Browse...") then
      local ok, folder = r.JS_Dialog_BrowseForFolder("Where should Time Machine keep its versions?", state.location_text)
      if ok == 1 and folder and folder ~= "" then state.location_text = folder end
    end
  end
  r.ImGui_SameLine(ctx)
  local busy = state.job ~= nil
  if busy and r.ImGui_BeginDisabled then r.ImGui_BeginDisabled(ctx, true) end
  if r.ImGui_Button(ctx, "Use") then
    state.pending_location = state.location_text
    state.open_migrate = true
    r.ImGui_CloseCurrentPopup(ctx)
  end
  if busy and r.ImGui_EndDisabled then r.ImGui_EndDisabled(ctx) end
  r.ImGui_TextColored(ctx, Theme.colors.text_dim, "A \"" .. Store.FOLDER_NAME .. "\" folder is made inside the chosen folder.")
  r.ImGui_Separator(ctx)
  local function number(label, key, min_value, help)
    r.ImGui_SetNextItemWidth(ctx, UIScale.round(110))
    local edited, number_value = r.ImGui_InputInt(ctx, label, math.floor(tonumber(settings[key]) or 0))
    if edited then
      settings[key] = math.max(min_value, number_value)
      changed_any = true
    end
    UI.tooltip_when(app, r.ImGui_IsItemHovered(ctx), help)
  end
  number("Skip projects larger than (MB)", "max_project_mb", 0, "0 records every project, whatever its size")
  number("Keep at most per project (MB)", "max_history_mb", 0, "Oldest versions go first. 0 means no limit")
  number("Keep every version for (hours)", "keep_all_hours", 1, "After this, one version per hour is kept")
  number("Then one per hour for (days)", "keep_hourly_days", 0, "After this, one version per day is kept")
  if changed_any and app.save_settings then app.save_settings() end
  local project, path = r.EnumProjects(-1, "")
  if path and path ~= "" then
    r.ImGui_Separator(ctx)
    r.ImGui_Text(ctx, "This project")
    if state.backups_found == nil then state.backups_found = #Store.find_backups(path) end
    local busy_now = state.job ~= nil or state.backups_found == 0
    if busy_now and r.ImGui_BeginDisabled then r.ImGui_BeginDisabled(ctx, true) end
    if r.ImGui_Button(ctx, "Import REAPER backups (" .. tostring(state.backups_found) .. " found)") then
      worker.start_import(app, project, path)
      r.ImGui_CloseCurrentPopup(ctx)
    end
    if busy_now and r.ImGui_EndDisabled then r.ImGui_EndDisabled(ctx) end
    UI.tooltip_when(app, r.ImGui_IsItemHovered(ctx, r.ImGui_HoveredFlags_AllowWhenDisabled and r.ImGui_HoveredFlags_AllowWhenDisabled() or 0),
      "Adds the .rpp-bak files REAPER kept for this project (beside it and in its Backups folder) to the history, dated by when they were saved. Backups already in the history are skipped.")
  end
  r.ImGui_EndPopup(ctx)
end

function view.migrate_popup(app)
  local ctx = app.ctx
  if state.open_migrate then
    r.ImGui_OpenPopup(ctx, "Move Time Machine")
    state.open_migrate = false
  end
  if not r.ImGui_BeginPopupModal(ctx, "Move Time Machine", nil, r.ImGui_WindowFlags_AlwaysAutoResize()) then return end
  local new_root = Store.root_for(state.pending_location)
  r.ImGui_Text(ctx, "Store versions in:")
  r.ImGui_TextColored(ctx, Theme.colors.accent, new_root)
  r.ImGui_Spacing(ctx)
  r.ImGui_TextWrapped(ctx, "Move the existing histories there as well? Histories the new folder already has are merged.")
  r.ImGui_Spacing(ctx)
  if r.ImGui_Button(ctx, "Move histories") then
    location.apply(app, state.pending_location, true)
    r.ImGui_CloseCurrentPopup(ctx)
  end
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "Use without moving") then
    location.apply(app, state.pending_location, false)
    r.ImGui_CloseCurrentPopup(ctx)
  end
  UI.tooltip_when(app, r.ImGui_IsItemHovered(ctx), "The old histories stay where they are and no longer show up")
  r.ImGui_SameLine(ctx)
  if r.ImGui_Button(ctx, "Cancel") then r.ImGui_CloseCurrentPopup(ctx) end
  r.ImGui_EndPopup(ctx)
end

function view.link_popup(app, project, path, current)
  local ctx = app.ctx
  if state.open_link then
    r.ImGui_OpenPopup(ctx, "Link to History")
    state.open_link = false
  end
  if not r.ImGui_BeginPopup(ctx, "Link to History") then return end
  if not path or path == "" then
    r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Save the project first.")
    r.ImGui_EndPopup(ctx)
    return
  end
  if not state.link_list then
    state.histories = nil
    local list = {}
    for _, manifest in pairs(history.all(app)) do list[#list + 1] = manifest end
    table.sort(list, function(a, b)
      -- Histories whose project file is gone are the likely candidates.
      local a_missing = not Store.file_exists(a.path)
      local b_missing = not Store.file_exists(b.path)
      if a_missing ~= b_missing then return a_missing end
      return (a.name or ""):lower() < (b.name or ""):lower()
    end)
    state.link_list = list
  end
  r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Link this project to an existing history:")
  r.ImGui_SetNextItemWidth(ctx, UIScale.round(360))
  local changed, value = r.ImGui_InputTextWithHint(ctx, "##tm_link_filter", "Filter", state.link_filter)
  if changed then state.link_filter = value end
  local filter = state.link_filter:lower()
  if r.ImGui_BeginChild(ctx, "##tm_link_list", UIScale.round(480), UIScale.round(260), 0) then
    local shown = 0
    for _, manifest in ipairs(state.link_list) do
      local haystack = ((manifest.name or "") .. " " .. (manifest.path or "")):lower()
      if filter == "" or haystack:find(filter, 1, true) then
        shown = shown + 1
        r.ImGui_PushID(ctx, manifest.id)
        local is_current = current and current.id == manifest.id
        if is_current and r.ImGui_BeginDisabled then r.ImGui_BeginDisabled(ctx, true) end
        if r.ImGui_Button(ctx, is_current and "Linked" or "Link") then
          Store.set_project_id(project, manifest.id)
          manifest.path = path
          Store.save_manifest(util.root(app), manifest)
          history.remember(manifest)
          state.selected = nil
          util.set_status("Linked to the history of " .. tostring(manifest.name))
          r.ImGui_CloseCurrentPopup(ctx)
        end
        if is_current and r.ImGui_EndDisabled then r.ImGui_EndDisabled(ctx) end
        r.ImGui_SameLine(ctx)
        local last = manifest.snapshots[#manifest.snapshots]
        r.ImGui_Text(ctx, tostring(manifest.name) .. "  ·  " .. tostring(#manifest.snapshots) .. " versions" .. (last and ("  ·  " .. util.when(last.time)) or ""))
        local missing = not Store.file_exists(manifest.path)
        r.ImGui_TextColored(ctx, missing and Theme.colors.danger or Theme.colors.text_dim, "      " .. tostring(manifest.path or "") .. (missing and "  (not found)" or ""))
        r.ImGui_PopID(ctx)
      end
    end
    if shown == 0 then r.ImGui_TextColored(ctx, Theme.colors.text_dim, "No histories found in " .. util.root(app)) end
    r.ImGui_EndChild(ctx)
  end
  if current then
    r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Linking another history leaves the current one in this list.")
  end
  r.ImGui_EndPopup(ctx)
end

-- Module ------------------------------------------------------------------------

-- Internals for tests/ and the simulation harness; not an API for modules.
M.debug = { state = state, worker = worker, view = view, history = history }

function M.init(app)
  util.settings(app)
end

function M.update(app)
  worker.poll(app)
  worker.step(app)
end

-- Verbs for Module Actions/ scripts, so they can sit on a shortcut.
function M.handle_action(app, verb)
  if verb == "ab" then view.ab_toggle(app) end
end

function M.shutdown(app)
  if state.job then Store.cancel(state.job) end
  state.job = nil
end

function M.draw(app)
  local ctx = app.ctx
  local project, path = r.EnumProjects(-1, "")
  local manifest = history.for_project(app, project, path)
  local project_name = (path and path:match("([^\\/]+)%.[Rr][Pp][Pp]$")) or "Unsaved project"
  if state.selected_history ~= (manifest and manifest.id) then
    state.selected_history = manifest and manifest.id
    state.selected = manifest and manifest.snapshots[#manifest.snapshots] and manifest.snapshots[#manifest.snapshots].file or nil
    if manifest then worker.queue_summaries(manifest) end
  end

  view.header(app, manifest, project_name)
  view.settings_popup(app)
  view.migrate_popup(app)
  view.link_popup(app, project, path, manifest)
  view.label_popup(app)
  view.borrow_popup(app)
  view.storage_popup(app)
  view.draw_menu(app, "##tm_menu_header")

  local job = state.job
  if job and job.kind == "migrate" then
    r.ImGui_TextColored(ctx, Theme.colors.warning, string.format("Moving histories... %d of %d", job.moved + 1, job.total))
  end

  local info_h = UI.info_line_height(ctx)
  local _, avail_h = r.ImGui_GetContentRegionAvail(ctx)
  local body_h = math.max(UIScale.round(60), (avail_h or 0) - info_h)

  if not path or path == "" then
    r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Save the project to start its history.")
  elseif not manifest or #manifest.snapshots == 0 then
    local settings = util.settings(app)
    r.ImGui_TextWrapped(ctx, settings.enabled
      and "No versions yet. Every time this project is saved, Time Machine keeps a copy and lists what changed."
      or "Recording is off. Turn it on in Settings.")
    r.ImGui_TextColored(ctx, Theme.colors.text_dim, "Moved this project? Use Link to reconnect its history.")
    if state.backups_found == nil then state.backups_found = #Store.find_backups(path) end
    if state.backups_found > 0 and not state.job then
      if r.ImGui_Button(ctx, "Import " .. tostring(state.backups_found) .. " REAPER backups") then worker.start_import(app, project, path) end
      UI.tooltip_when(app, r.ImGui_IsItemHovered(ctx), "Starts the history with the .rpp-bak files REAPER already kept for this project")
    end
  else
    local avail_w = r.ImGui_GetContentRegionAvail(ctx)
    local settings = util.settings(app)
    local gap = UIScale.round(6)
    if avail_w >= UIScale.round(520) then
      local list_w = math.floor(avail_w * (tonumber(settings.list_ratio) or 0.4))
      view.version_list(app, manifest, list_w, body_h)
      r.ImGui_SameLine(ctx, 0, gap)
      view.diff_panel(app, manifest, avail_w - list_w - gap, body_h)
    else
      local list_h = math.floor(body_h * 0.38)
      view.version_list(app, manifest, avail_w, list_h)
      view.diff_panel(app, manifest, avail_w, body_h - list_h - gap)
    end
  end

  local info
  if state.status and r.time_precise() - state.status.time < 8 then
    info = state.status.text
  elseif state.job and state.job.kind == "capture" then
    info = "Recording version... " .. util.megabytes(state.job.bytes)
  elseif state.job and state.job.kind == "import" then
    info = string.format("Importing backups... %d of %d", state.job.imported + state.job.skipped + 1, state.job.total)
  elseif manifest then
    info = tostring(#manifest.snapshots) .. " versions · " .. util.root(app)
  else
    info = util.settings(app).enabled and "Recording on save" or "Recording is off"
  end
  UI.draw_info_line(ctx, info)
end

return M
