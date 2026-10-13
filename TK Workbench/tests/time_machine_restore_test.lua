-- Restores against a stand-in for REAPER that keeps tracks as state chunks.
-- After putting things back, the "live" project is written out as .rpp text
-- and compared with the old version: what was restored must no longer differ.
--
-- Optional argument: a file listing "old.rpp|new.rpp" pairs (for example
-- .rpp-bak next to .rpp) to run the same round trip on real projects.

local source = debug.getinfo(1, "S").source:sub(2)
local tests_dir = source:match("^(.*[\\/])") or ""
local root_dir = tests_dir:gsub("tests[\\/]$", "")
package.path = root_dir .. "?.lua;" .. root_dir .. "?" .. package.config:sub(1, 1) .. "init.lua;" .. package.path

local pairs_file = ...

-- A minimal REAPER ----------------------------------------------------------------

local live = { tracks = {}, master = { chunk = "<TRACK\nNAME \"\"\n>\n", values = {} }, markers = {}, inserted = 0 }

local function guid_of(chunk)
  return chunk:match("\nTRACKID (%b{})") or chunk:match("^<TRACK (%b{})")
end

reaper = {
  CountTracks = function() return #live.tracks end,
  GetTrack = function(_, index) return live.tracks[index + 1] end,
  GetMasterTrack = function() return live.master end,
  GetTrackGUID = function(track) return guid_of(track.chunk) end,
  GetTrackStateChunk = function(track) return true, track.chunk end,
  SetTrackStateChunk = function(track, chunk)
    assert(chunk:sub(1, 6) == "<TRACK", "chunk must start with <TRACK")
    local _, opens = chunk:gsub("\n<", "")
    local _, closes = chunk:gsub("\n>", "")
    assert(opens + 1 == closes, "unbalanced chunk")
    track.chunk = chunk
    return true
  end,
  InsertTrackAtIndex = function(index)
    live.inserted = live.inserted + 1
    local id = string.format("{00000000-0000-0000-0000-%012d}", live.inserted)
    table.insert(live.tracks, index + 1, { chunk = "<TRACK " .. id .. "\nNAME \"\"\nTRACKID " .. id .. "\n>\n", values = {} })
  end,
  DeleteTrack = function(track)
    for index, candidate in ipairs(live.tracks) do
      if candidate == track then table.remove(live.tracks, index) return end
    end
  end,
  GetMediaTrackInfo_Value = function(track, param)
    if param == "IP_TRACKNUMBER" then
      for index, candidate in ipairs(live.tracks) do if candidate == track then return index end end
    end
    return 0
  end,
  SetMediaTrackInfo_Value = function(track, param, value) track.values = track.values or {}; track.values[param] = value end,
  CountProjectMarkers = function() return #live.markers end,
  EnumProjectMarkers3 = function(_, i)
    local m = live.markers[i + 1]
    if not m then return 0 end
    return i + 1, m.region, m.position, m.region_end, m.name, m.index, m.color
  end,
  SetProjectMarker3 = function(_, index, region, position, region_end, name)
    for _, m in ipairs(live.markers) do
      if m.index == index and m.region == region then m.position, m.region_end, m.name = position, region_end, name end
    end
  end,
  AddProjectMarker2 = function(_, region, position, region_end, name, index, color)
    live.markers[#live.markers + 1] = { region = region, position = position, region_end = region_end, name = name, index = index, color = color }
  end,
  DeleteProjectMarker = function(_, index, region)
    for i, m in ipairs(live.markers) do if m.index == index and m.region == region then table.remove(live.markers, i) return end end
  end,
  Undo_BeginBlock = function() end,
  Undo_EndBlock = function() end,
  PreventUIRefresh = function() end,
  UpdateArrange = function() end,
  TrackList_AdjustWindows = function() end
}

local Diff = require("core.rpp_diff")
local Restore = require("core.time_machine_restore")
local TrackChunk = require("core.track_chunk")

local passed = 0
local function expect(label, actual, expected)
  assert(actual == expected, string.format("%s: expected %s, got %s", label, tostring(expected), tostring(actual)))
  passed = passed + 1
end

-- The live project as it would be saved, keeping the old project's
-- project-level lines so only tracks are compared.
local function live_project()
  local lines = { "<REAPER_PROJECT 0.1" }
  for _, track in ipairs(live.tracks) do lines[#lines + 1] = track.chunk end
  lines[#lines + 1] = ">"
  return assert(Diff.parse(table.concat(lines, "\n") .. "\n"))
end

local function load_live(new_project)
  live.tracks = {}
  for _, id in ipairs(new_project.track_order) do
    local track = new_project.tracks[id]
    live.tracks[#live.tracks + 1] = { chunk = TrackChunk.dedent(new_project.text:sub(track.block_start, track.block_end)), values = {} }
  end
end

local function group_for(result, id)
  for _, group in ipairs(result.tracks) do if group.id == id then return group end end
  return nil
end

-- Restores every line of a comparison one by one, the way a person
-- right-clicking down the list would, then checks nothing is left.
local function restore_everything(old_project, new_project, label)
  load_live(new_project)
  local result = Diff.diff(old_project, new_project)
  local restored = 0
  for _, group in ipairs(result.tracks) do
    if group.status == "removed" then
      assert(Restore.bring_back_track(old_project, group.id))
      restored = restored + 1
    elseif group.status == "added" then
      assert(Restore.remove_track(group.id))
      restored = restored + 1
    else
      for _, entry in ipairs(group.entries) do
        local ok, err = true, nil
        if entry.area == "fx" then
          if entry.order then
            ok, err = Restore.track_parts(old_project, group.id, { fx = true })
          elseif entry.chain ~= "Master" then
            ok, err = Restore.fx(old_project, group.id, entry.chain, (entry.old_fx or entry.fx).id)
          end
        elseif entry.area == "items" then
          ok, err = Restore.track_parts(old_project, group.id, { items = true })
        elseif entry.area == "envelopes" then
          ok, err = Restore.envelope(old_project, group.id, entry.envelope)
        elseif entry.area == "misc" then
          if entry.param then
            -- The stand-in does not write values into chunks; restore the line.
            ok, err = Restore.track_lines(old_project, group.id, { "VOLPAN", "MUTESOLO" })
          elseif entry.keys then
            ok, err = Restore.track_lines(old_project, group.id, entry.keys)
          end
        elseif entry.area == "order" then
          ok = true
        else
          ok, err = Restore.whole_track(old_project, group.id)
        end
        assert(ok, label .. " / " .. group.name .. " / " .. entry.text .. ": " .. tostring(err))
        restored = restored + 1
      end
    end
  end
  local after = Diff.diff(old_project, live_project())
  local left = {}
  for _, group in ipairs(after.tracks) do
    for _, entry in ipairs(group.entries) do
      if entry.area ~= "order" and entry.text ~= "Other track settings changed" then left[#left + 1] = group.name .. ": " .. entry.text end
    end
  end
  return restored, left
end

-- Synthetic project ------------------------------------------------------------

local function fx(name, id, state, bypass)
  return table.concat({
    "      BYPASS " .. (bypass or "0 0 0"),
    "      <VST \"VST3: " .. name .. " (Vendor)\" plugin.vst3 0 \"\" 123{ABC} \"\"",
    "        " .. state,
    "      >",
    "      PRESETNAME \"Init\"",
    "      FXID " .. id,
    "      WAK 0 0"
  }, "\n")
end

local function track(id, name, vol, chain, items, points)
  local lines = { "  <TRACK " .. id, "    NAME \"" .. name .. "\"", "    VOLPAN " .. vol .. " 0 -1 -1 1", "    MUTESOLO 0 0 0", "    TRACKID " .. id }
  if points then
    lines[#lines + 1] = "    <VOLENV2"
    for i = 1, points do lines[#lines + 1] = "      PT " .. i .. " 1 0" end
    lines[#lines + 1] = "    >"
  end
  if chain then
    lines[#lines + 1] = "    <FXCHAIN"
    lines[#lines + 1] = "      SHOW 0"
    for _, entry in ipairs(chain) do lines[#lines + 1] = fx(entry[1], entry[2], entry[3], entry[4]) end
    lines[#lines + 1] = "    >"
  end
  for _, item in ipairs(items or {}) do
    lines[#lines + 1] = "    <ITEM\n      POSITION " .. item[2] .. "\n      LENGTH 4\n      IGUID " .. item[1] .. "\n      NAME \"" .. item[1] .. "\"\n    >"
  end
  lines[#lines + 1] = "  >"
  return table.concat(lines, "\n")
end

local function project(tracks)
  return "<REAPER_PROJECT 0.1\n  TEMPO 120 4 4\n" .. table.concat(tracks, "\n") .. "\n>\n"
end

local A, B, C, D = "{A0000000-0000-0000-0000-000000000001}", "{B0000000-0000-0000-0000-000000000002}", "{C0000000-0000-0000-0000-000000000003}", "{D0000000-0000-0000-0000-000000000004}"

local old_text = project({
  track(A, "Kick", "1", nil, { { "{I1}", 0 } }),
  track(B, "Bass", "1", { { "ReaComp", "{F1}", "AAAA" }, { "ReaEQ", "{F2}", "BBBB" }, { "Saturn", "{F3}", "CCCC" } }, nil, 3),
  track(C, "Vox", "0.5", nil, { { "{I2}", 8 }, { "{I3}", 16 } })
})
local new_text = project({
  track(B, "Bass guitar", "0.25", { { "ReaComp", "{F1}", "ZZZZ" }, { "Saturn", "{F3}", "CCCC", "1 0 0" }, { "Pro-Q", "{F4}", "DDDD" } }, nil, 7),
  track(D, "Pad", "1", { { "Vital", "{F9}", "EEEE" } }),
  track(C, "Vox", "0.5", nil, { { "{I2}", 10 }, { "{I4}", 24 } })
})
local old_project, new_project = assert(Diff.parse(old_text)), assert(Diff.parse(new_text))

-- Single plugin restores, checked one at a time.
load_live(new_project)
assert(Restore.fx(old_project, B, nil, "{F2}"))           -- ReaEQ was removed: bring it back
local bass = Diff.parse_track_chunk(Restore.find_track and live.tracks[1].chunk)
local names = {}
for _, entry in ipairs(bass.fx.list) do names[#names + 1] = Diff.fx_display_name(entry) end
expect("brought back after its old neighbour", table.concat(names, ","), "ReaComp,ReaEQ,Saturn,Pro-Q")
assert(Restore.fx(old_project, B, nil, "{F4}"))           -- Pro-Q was added: remove it
assert(Restore.fx(old_project, B, nil, "{F1}"))           -- ReaComp state
assert(Restore.fx(old_project, B, nil, "{F3}"))           -- Saturn bypass
local after = Diff.diff(old_project, live_project())
local bass_group = group_for(after, B)
local fx_left = 0
for _, entry in ipairs(bass_group and bass_group.entries or {}) do
  if entry.area == "fx" then
    fx_left = fx_left + 1
    print("left on Bass: " .. entry.text)
  end
end
if fx_left > 0 then print(live.tracks[1].chunk) end
expect("no FX differences left on Bass", fx_left, 0)

-- A plugin onto a track that has no chain at all.
load_live(new_project)
assert(Restore.track_parts(old_project, B, { fx = true }))
local kick_old = Diff.parse(project({ track(A, "Kick", "1", { { "ReaGate", "{G1}", "GGGG" } }) }))
live.tracks = { { chunk = TrackChunk.dedent(track(A, "Kick", "1")) } }
assert(Restore.fx(kick_old, A, nil, "{G1}"))
expect("chain created for the plugin", #Diff.parse_track_chunk(live.tracks[1].chunk).fx.list, 1)

-- Tracks: deleted one comes back in its old place, added one goes.
load_live(new_project)
assert(Restore.bring_back_track(old_project, A))
expect("Kick back on top", Diff.parse_track_chunk(live.tracks[1].chunk).id, A)
assert(Restore.remove_track(D))
expect("Pad removed", #live.tracks, 3)

-- Whole-track restore keeps the live track's identity.
load_live(new_project)
assert(Restore.whole_track(old_project, B))
local restored_bass = Diff.parse_track_chunk(live.tracks[1].chunk)
expect("whole track: name", Diff.track_label(restored_bass), "Bass")
expect("whole track: same GUID", restored_bass.id, B)

-- Line-by-line round trip on the synthetic pair.
local count, left = restore_everything(old_project, new_project, "synthetic")
expect("synthetic: nothing left after restoring every line (" .. table.concat(left, "; ") .. ")", #left, 0)
expect("synthetic: lines restored", count > 8, true)

-- Markers.
live.markers = { { index = 2, region = true, position = 32, region_end = 60, name = "Verse 1" }, { index = 3, region = false, position = 90, name = "Bridge" } }
local marker_old = Diff.parse("<REAPER_PROJECT 0.1\n  MARKER 1 0 \"Intro\" 0 0\n  MARKER 2 30 \"Verse\" 1 0\n  MARKER 2 60 \"\" 1\n>\n")
local marker_new = Diff.parse("<REAPER_PROJECT 0.1\n  MARKER 2 32 \"Verse 1\" 1 0\n  MARKER 2 60 \"\" 1\n  MARKER 3 90 \"Bridge\" 0 0\n>\n")
assert(Restore.marker(marker_old, "R2", marker_new))
assert(Restore.marker(marker_old, "M1", marker_new))
assert(Restore.marker(marker_old, "M3", marker_new))
expect("region moved back", live.markers[1].position, 30)
expect("region renamed back", live.markers[1].name, "Verse")
expect("deleted marker re-added", live.markers[#live.markers].name, "Intro")
expect("added marker removed", #live.markers, 2)

-- Naming plugin parameters. The stand-in "plugin" reads its parameters from
-- its state line ("PARAMS 0.1 0.5"), so the plumbing can be checked: the two
-- states land on a temporary track, are read, and the track is gone again.
do
  local names = { "Cutoff", "Resonance", "Bypass" }
  local function fx_params(track, fx_index)
    local blocks = {}
    for state in track.chunk:gmatch("\nPARAMS ([^\n]*)") do blocks[#blocks + 1] = state end
    local values = {}
    for value in tostring(blocks[fx_index + 1] or ""):gmatch("%S+") do values[#values + 1] = tonumber(value) end
    return values
  end
  reaper.TrackFX_GetCount = function(track) local _, n = track.chunk:gsub("\nBYPASS ", ""); return n end
  reaper.TrackFX_GetNumParams = function(track, fx_index) return #fx_params(track, fx_index) end
  reaper.TrackFX_GetParamNormalized = function(track, fx_index, param) return fx_params(track, fx_index)[param + 1] end
  reaper.TrackFX_GetParamName = function(_, _, param) return true, names[param + 1] end
  reaper.TrackFX_GetFormattedParamValue = function(track, fx_index, param)
    return true, string.format("%d%%", math.floor(fx_params(track, fx_index)[param + 1] * 100 + 0.5))
  end
  load_live(new_project)
  local before = #live.tracks
  local changes = assert(Restore.compare_plugin_params(
    "      <VST \"VST3: Synth (Vendor)\" synth.vst3 0 \"\" 1{X} \"\"\n        PARAMS 0.1 0.5 0.9\n      >",
    "      <VST \"VST3: Synth (Vendor)\" synth.vst3 0 \"\" 1{X} \"\"\n        PARAMS 0.1 0.7 0.2\n      >"))
  expect("param compare: one named change", #changes, 1)
  expect("param compare: text", changes[1], "Resonance: 50% -> 70%")
  expect("param compare: temporary track removed", #live.tracks, before)
  local same = assert(Restore.compare_plugin_params("<VST \"x\"\nPARAMS 0.3\n>", "<VST \"x\"\nPARAMS 0.3\n>"))
  expect("param compare: identical settings", #same, 0)
  local missing, err = Restore.compare_plugin_params("<VST \"x\"\n>", "<VST \"x\"\n>")
  expect("param compare: unloadable plugin reported", missing == nil and err ~= nil, true)
  expect("param compare: temporary track removed after failure", #live.tracks, before)
end

-- "Versus now": the open project read through the API must compare as
-- unchanged against the version it was saved as.
local function load_live_everything(project)
  load_live(project)
  local tempo = Diff.tokens(project.lines.TEMPO or "120 4 4")
  local master = Diff.tokens(project.lines.MASTER_VOLUME or "1 0")
  local notes = {}
  for line in tostring(project.blocks.NOTES or ""):gmatch("[^\r\n]+") do
    local text = line:match("^%s*|(.*)$")
    if text then notes[#notes + 1] = text end
  end
  local master_chunk = "<TRACK\nNAME \"\"\n"
  if project.master_fx and #project.master_fx.list > 0 then
    local first = project.master_fx.list[1].entry_start
    local chain_start = project.text:sub(1, first):match(".*()<MASTERFXLIST")
    master_chunk = master_chunk .. TrackChunk.dedent(project.text:sub(chain_start, project.master_fx.close_start + 1)):gsub("^<MASTERFXLIST", "<FXCHAIN") .. "\n"
  end
  live.master = { chunk = master_chunk .. ">\n", values = { D_VOL = tonumber(master[1]), D_PAN = tonumber(master[2]) } }
  live.markers = {}
  for _, marker in pairs(project.markers) do
    live.markers[#live.markers + 1] = {
      index = tonumber(marker.index), region = marker.region, position = marker.position,
      region_end = marker.region_end, name = marker.name, color = tonumber(marker.color) or 0
    }
  end
  table.sort(live.markers, function(a, b) return a.position < b.position end)
  reaper.TimeMap_GetTimeSigAtTime = function() return tonumber(tempo[2]) or 4, tonumber(tempo[3]) or 4, tonumber(tempo[1]) or 120 end
  reaper.GetMediaTrackInfo_Value = function(track, param)
    if track == live.master then return live.master.values[param] or 0 end
    if param == "IP_TRACKNUMBER" then
      for index, candidate in ipairs(live.tracks) do if candidate == track then return index end end
    end
    return 0
  end
  reaper.GetSetProjectNotes = function() return table.concat(notes, "\n") end
end

local function describe(result)
  local lines = {}
  for _, entry in ipairs(result.project) do lines[#lines + 1] = "project: " .. entry.text end
  for _, group in ipairs(result.tracks) do
    for _, entry in ipairs(group.entries) do lines[#lines + 1] = group.name .. ": " .. entry.text end
  end
  return lines
end

do
  load_live_everything(new_project)
  local now = Restore.capture_live(new_project)
  local unchanged = describe(Diff.diff(new_project, now))
  expect("now vs last save, nothing edited (" .. table.concat(unchanged, "; ") .. ")", #unchanged, 0)
  local since_old = Diff.diff(old_project, now)
  expect("now vs older version matches the saved comparison", #since_old.tracks, #Diff.diff(old_project, new_project).tracks)
  -- An unsaved edit shows up.
  live.tracks[1].chunk = live.tracks[1].chunk:gsub("VOLPAN 0.25", "VOLPAN 0.5")
  local edited = describe(Diff.diff(new_project, Restore.capture_live(new_project)))
  expect("unsaved volume change seen", #edited == 1 and edited[1]:find("Volume", 1, true) ~= nil, true)
end

-- Borrowing a track from another project.
do
  local counter = 0
  reaper.genGuid = function()
    counter = counter + 1
    return string.format("{FFFFFFFF-0000-0000-0000-%012d}", counter)
  end
  local source = table.concat({
    "<TRACK {S1}",
    "NAME \"Keys\"",
    "TRACKID {S1}",
    "AUXRECV 3 0 1 0 0 0 0 0 0 -1:U 0 -1 ''",
    "<ITEM",
    "IGUID {I1}",
    "<SOURCE MIDIPOOL",
    "POOLEDEVTS {P1}",
    ">",
    ">",
    "<ITEM",
    "IGUID {I2}",
    "<SOURCE MIDIPOOL",
    "POOLEDEVTS {P1}",
    ">",
    ">",
    "<ITEM",
    "IGUID {I3}",
    "<SOURCE WAVE",
    "FILE \"Audio/keys take 1.wav\" 1",
    ">",
    ">",
    "<ITEM",
    "IGUID {I4}",
    "<SOURCE WAVE",
    "FILE \"D:\\Samples\\pad.wav\"",
    ">",
    ">",
    ">"
  }, "\n") .. "\n"
  local portable = Restore.portable_track_chunk(source, "D:\\Songs\\Other")
  expect("borrow: receives dropped", portable:find("AUXRECV", 1, true), nil)
  expect("borrow: item ids replaced", portable:find("{I1}", 1, true), nil)
  local pools = {}
  for guid in portable:gmatch("POOLEDEVTS (%b{})") do pools[#pools + 1] = guid end
  expect("borrow: pooled MIDI still shares one pool", pools[1] == pools[2] and pools[1] ~= "{P1}", true)
  expect("borrow: relative media made absolute", portable:find('FILE "D:\\Songs\\Other' .. package.config:sub(1, 1) .. 'Audio/keys take 1.wav" 1', 1, true) ~= nil, true)
  expect("borrow: absolute media untouched", portable:find('FILE "D:\\Samples\\pad.wav"', 1, true) ~= nil, true)

  local source_project = assert(Diff.parse("<REAPER_PROJECT 0.1\n" .. source:gsub("\n", "\n  "):gsub("  $", "") .. ">\n"))
  load_live(new_project)
  local before = #live.tracks
  assert(Restore.borrow_track(source_project, "{S1}", "D:\\Songs\\Other", 1))
  expect("borrow: one track added", #live.tracks, before + 1)
  local added = Diff.parse_track_chunk(live.tracks[2].chunk)
  expect("borrow: added after the given index", Diff.track_label(added), "Keys")
  expect("borrow: added track has its own id", added.id ~= "{S1}", true)
end

-- Real projects ---------------------------------------------------------------------

if pairs_file then
  local function read(path) local h = assert(io.open(path, "rb")); local s = h:read("a"); h:close(); return s end
  local projects, lines_restored = 0, 0
  for line in io.lines(pairs_file) do
    local old_path, new_path = line:match("^(.-)|(.*)$")
    local old_real, new_real = Diff.parse(read(old_path)), Diff.parse(read(new_path))
    if old_real and new_real then
      load_live_everything(new_real)
      local unchanged = describe(Diff.diff(new_real, Restore.capture_live(new_real)))
      expect("real: " .. new_path .. " read back live shows no changes (" .. table.concat(unchanged, "; ") .. ")", #unchanged, 0)
      local restored, remaining = restore_everything(old_real, new_real, new_path)
      expect("real: " .. new_path .. " fully restored (" .. table.concat(remaining, "; ") .. ")", #remaining, 0)
      projects = projects + 1
      lines_restored = lines_restored + restored
    end
  end
  print(string.format("real projects: %d round trips, %d lines restored", projects, lines_restored))
end

print(string.format("time_machine_restore_test: %d checks passed", passed))
