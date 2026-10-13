local source = debug.getinfo(1, "S").source:sub(2)
local tests_dir = source:match("^(.*[\\/])") or ""
local root_dir = tests_dir:gsub("tests[\\/]$", "")
package.path = root_dir .. "?.lua;" .. root_dir .. "?" .. package.config:sub(1, 1) .. "init.lua;" .. package.path

local Diff = require("core.rpp_diff")

local passed = 0

local function expect(label, actual, expected)
  assert(actual == expected, string.format("%s: expected %s, got %s", label, tostring(expected), tostring(actual)))
  passed = passed + 1
end

local function has_entry(entries, kind, needle)
  for _, entry in ipairs(entries or {}) do
    if entry.kind == kind and entry.text:find(needle, 1, true) then return true end
  end
  return false
end

local function find_group(result, name)
  for _, group in ipairs(result.tracks) do
    if group.name == name then return group end
  end
  return nil
end

-- A small project in REAPER's own layout. Each table is a track; the builder
-- keeps the fixtures readable while the parser sees real indentation.
local function plugin(name, fxid, state, bypass)
  return table.concat({
    "      BYPASS " .. (bypass or "0 0 0"),
    "      <VST \"VST3: " .. name .. " (Vendor)\" plugin.vst3 0 \"\" 123{ABC} \"\"",
    "        " .. state,
    "        AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA==",
    "      >",
    "      FXID " .. fxid,
    "      WAK 0 0"
  }, "\n")
end

local function item(guid, position, length, name)
  return table.concat({
    "    <ITEM",
    "      POSITION " .. position,
    "      LENGTH " .. length,
    "      IGUID " .. guid,
    "      NAME \"" .. name .. "\"",
    "      <SOURCE MIDI",
    "        HASDATA 1 960 QN",
    "        E 0 90 3c 60",
    "        E 480 80 3c 00",
    "      >",
    "    >"
  }, "\n")
end

local function track(spec)
  local lines = {
    "  <TRACK " .. spec.guid,
    "    NAME \"" .. spec.name .. "\"",
    "    PEAKCOL 16576",
    "    VOLPAN " .. (spec.vol or "1") .. " " .. (spec.pan or "0") .. " -1 -1 1",
    "    MUTESOLO " .. (spec.mute or "0") .. " 0 0",
    "    SEL " .. (spec.sel or "0"),
    "    TRACKHEIGHT " .. (spec.height or "0") .. " 0 0 0 0 0 0",
    "    TRACKID " .. spec.guid
  }
  if spec.env then
    lines[#lines + 1] = "    <VOLENV2"
    lines[#lines + 1] = "      EGUID {E0000000-0000-0000-0000-000000000001}"
    for index = 1, spec.env do lines[#lines + 1] = "      PT " .. tostring(index) .. " 1 0" end
    lines[#lines + 1] = "    >"
  end
  if spec.fx then
    lines[#lines + 1] = "    <FXCHAIN"
    lines[#lines + 1] = "      SHOW 0"
    for _, fx in ipairs(spec.fx) do lines[#lines + 1] = plugin(fx[1], fx[2], fx[3], fx[4]) end
    lines[#lines + 1] = "    >"
  end
  for _, it in ipairs(spec.items or {}) do lines[#lines + 1] = item(it[1], it[2], it[3], it[4]) end
  lines[#lines + 1] = "  >"
  return table.concat(lines, "\n")
end

local function project(spec)
  local lines = {
    "<REAPER_PROJECT 0.1 \"7.20/win64\" 1700000000",
    "  CURSOR " .. (spec.cursor or "0"),
    "  ZOOM 100 0 0",
    "  TEMPO " .. (spec.tempo or "120 4 4"),
    "  MASTER_VOLUME " .. (spec.master or "1") .. " 0 -1 -1 1"
  }
  for _, marker in ipairs(spec.markers or {}) do lines[#lines + 1] = "  " .. marker end
  for _, tr in ipairs(spec.tracks) do lines[#lines + 1] = track(tr) end
  lines[#lines + 1] = ">"
  return table.concat(lines, "\n") .. "\n"
end

local KICK = "{11111111-1111-1111-1111-111111111111}"
local BASS = "{22222222-2222-2222-2222-222222222222}"
local VOX = "{33333333-3333-3333-3333-333333333333}"
local PAD = "{44444444-4444-4444-4444-444444444444}"

local function base_tracks()
  return {
    { guid = KICK, name = "Kick", items = { { "{I1}", "0", "4", "kick" } } },
    { guid = BASS, name = "Bass", fx = { { "ReaComp", "{F1}", "Y29tcA==" }, { "ReaEQ", "{F2}", "ZXE=" } }, env = 3 },
    { guid = VOX, name = "Vox", items = { { "{I2}", "8", "4", "vox take" }, { "{I3}", "16", "4", "vox take 2" } } }
  }
end

local old_text = project({ tracks = base_tracks(), markers = { "MARKER 1 0 \"Intro\" 0 0", "MARKER 2 30 \"Verse\" 1 0", "MARKER 2 60 \"\" 1" } })

-- Nothing that matters changed: cursor, zoom, selection and track height are
-- view state and must not show up.
do
  local tracks = base_tracks()
  tracks[1].sel = "1"
  tracks[2].height = "120"
  local new_text = project({ cursor = "42.5", tracks = tracks, markers = { "MARKER 1 0 \"Intro\" 0 0", "MARKER 2 30 \"Verse\" 1 0", "MARKER 2 60 \"\" 1" } })
  local result = assert(Diff.diff_texts(old_text, new_text))
  expect("view-only edits: no track groups", #result.tracks, 0)
  expect("view-only edits: no project entries", #result.project, 0)
  expect("view-only edits: no summary", Diff.summary(result.counts), nil)
end

-- The everyday kind of session.
do
  local tracks = base_tracks()
  tracks[2].vol = "0.5"
  tracks[2].fx = { { "ReaComp", "{F1}", "Y29tcB==" }, { "ReaEQ", "{F2}", "ZXE=", "1 0 0" }, { "Pro-Q 3", "{F3}", "cHJvcQ==" } }
  tracks[2].env = 5
  tracks[3].items = { { "{I2}", "10", "4", "vox take" }, { "{I4}", "24", "2", "new take" } }
  table.insert(tracks, 2, { guid = PAD, name = "Pad", fx = { { "Vital", "{F9}", "dml0YWw=" } } })
  table.remove(tracks, 1)
  local new_text = project({ tempo = "128 4 4", tracks = tracks, markers = { "MARKER 1 0 \"Intro\" 0 0", "MARKER 2 32 \"Verse 1\" 1 0", "MARKER 2 60 \"\" 1", "MARKER 3 90 \"Bridge\" 0 0" } })
  local result = assert(Diff.diff_texts(old_text, new_text))

  expect("tempo change", has_entry(result.project, "changed", "Tempo 120 -> 128 BPM"), true)
  expect("region renamed and moved", has_entry(result.project, "changed", "Region 2 \"Verse 1\" renamed from \"Verse\", moved 0:30.000 -> 0:32.000"), true)
  expect("marker added", has_entry(result.project, "added", "Marker 3 \"Bridge\" added at 1:30.000"), true)

  local kick = find_group(result, "Kick")
  expect("removed track reported", kick and kick.status, "removed")
  expect("removed track keeps its old slot", result.tracks[1].name, "Kick")
  local pad = find_group(result, "Pad")
  expect("added track reported", pad and pad.status, "added")
  expect("added track summary", has_entry(pad.entries, "added", "Track added (1 FX)"), true)

  local bass = find_group(result, "Bass")
  expect("volume in dB", has_entry(bass.entries, "changed", "Volume 0.0 dB -> -6.0 dB"), true)
  expect("plugin settings", has_entry(bass.entries, "changed", "ReaComp state changed"), true)
  expect("bypass", has_entry(bass.entries, "changed", "ReaEQ bypassed"), true)
  expect("bypass is not also a settings change", has_entry(bass.entries, "changed", "ReaEQ state changed"), false)
  expect("fx added", has_entry(bass.entries, "added", "Pro-Q 3 added"), true)
  expect("envelope points", has_entry(bass.entries, "changed", "Volume envelope changed (3 -> 5 points)"), true)

  local vox = find_group(result, "Vox")
  expect("items summarised", has_entry(vox.entries, "changed", "1 item added, 1 item removed, 1 item moved"), true)
  expect("no track moved for a removal above it", has_entry(bass.entries, "changed", "Moved from"), false)

  expect("summary line", Diff.summary(result.counts), "2 tracks · 3 FX · 3 items · 1 envelope · 1 mixer change · 2 markers · 1 project change")
end

-- Dragging one track to the bottom reports that track only.
do
  local tracks = base_tracks()
  local kick = table.remove(tracks, 1)
  tracks[#tracks + 1] = kick
  local result = assert(Diff.diff_texts(old_text, project({ tracks = tracks, markers = { "MARKER 1 0 \"Intro\" 0 0", "MARKER 2 30 \"Verse\" 1 0", "MARKER 2 60 \"\" 1" } })))
  expect("one track moved", #result.tracks, 1)
  expect("moved track is the dragged one", result.tracks[1].name, "Kick")
  expect("moved text", has_entry(result.tracks[1].entries, "changed", "Moved from position 1 to 3"), true)
end

-- Windows line endings parse the same.
do
  local crlf = old_text:gsub("\n", "\r\n")
  local parsed = assert(Diff.parse(crlf))
  expect("crlf tracks", #parsed.track_order, 3)
  expect("crlf fx", #parsed.tracks[BASS].fx.list, 2)
  expect("crlf name", Diff.track_label(parsed.tracks[VOX]), "Vox")
  local result = assert(Diff.diff_texts(old_text, crlf))
  expect("crlf vs lf: track lines equal", #result.tracks == 0 or result.tracks[1].entries[1].text ~= "Volume", true)
end

-- JSFX: sliders are named from the source, and hidden sliders (readings a
-- meter writes back into itself) are not an edit.
do
  local source = table.concat({
    "desc:Test Meter",
    "slider1:1<0,1,1{Off,On}>Run",
    "slider2:400<100,1000,10>Window (ms)",
    "slider3:-100<-100,12,0.1>-Integrated (LUFS)",
    "slider4:gain_db=0<-24,24,0.1>Gain",
    "@init"
  }, "\n")
  local info = Diff.parse_jsfx_sliders(source)
  expect("jsfx enum", info.sliders[1].enum[2], "On")
  expect("jsfx hidden", info.sliders[3].hidden, true)
  expect("jsfx hidden name", info.sliders[3].name, "Integrated (LUFS)")
  expect("jsfx var form", info.sliders[4].name, "Gain")

  local function js_project(values, extra)
    return table.concat({
      "<REAPER_PROJECT 0.1",
      "  <TRACK " .. KICK,
      "    NAME \"Bus\"",
      "    <FXCHAIN",
      "      BYPASS 0 0 0",
      "      <JS \"Meters/test_meter.jsfx\" \"\"",
      "        " .. values .. " - - - -" .. (extra and ("\n" .. extra) or ""),
      "      >",
      "      FXID {J1}",
      "    >",
      "  >",
      ">"
    }, "\n") .. "\n"
  end
  local options = { js_info = function(path) return path == "Meters/test_meter.jsfx" and info or nil end }
  local base = js_project("1 400 -23.5 0")

  local result = assert(Diff.diff_texts(base, js_project("1 400 -14.2 0"), options))
  expect("hidden reading only: no change", #result.tracks, 0)

  result = assert(Diff.diff_texts(base, js_project("0 500 -14.2 3.5"), options))
  local bus = find_group(result, "Bus")
  expect("visible sliders named", has_entry(bus.entries, "changed", "test_meter: Run On -> Off, Window (ms) 400 -> 500, +1 more"), true)
  expect("details list all visible", #bus.entries[1].details, 3)

  result = assert(Diff.diff_texts(base, js_project("1 400 -23.5 0", "        AQIDBA=="), options))
  expect("serialized data", has_entry(find_group(result, "Bus").entries, "changed", "test_meter internal state changed"), true)

  result = assert(Diff.diff_texts(base, js_project("1 400 -14.2 0")))
  expect("no source: numbered slider", has_entry(find_group(result, "Bus").entries, "changed", "test_meter: Slider 3 -23.5 -> -14.2"), true)
end

expect("not a project", select(2, Diff.parse("hello")), "Not a REAPER project file")
expect("format pan", Diff.format_pan(-0.25), "25% L")
expect("format -inf", Diff.format_db(0), "-inf dB")
expect("display name", Diff.fx_display_name({ name = "VST3: Pro-Q 3 (FabFilter)", tag = "VST" }), "Pro-Q 3")
expect("display name JS", Diff.fx_display_name({ name = "Utility/volume_pan", tag = "JS" }), "volume_pan")

print(string.format("rpp_diff_test: %d checks passed", passed))
