-- Pieces of the Time Machine module that need no window: the changelog text,
-- the filtering behind the per-track/plugin history, and deleting a history.

local source = debug.getinfo(1, "S").source:sub(2)
local tests_dir = source:match("^(.*[\\/])") or ""
local root_dir = tests_dir:gsub("tests[\\/]$", "")
package.path = root_dir .. "?.lua;" .. root_dir .. "?" .. package.config:sub(1, 1) .. "init.lua;" .. package.path

local sep = package.config:sub(1, 1)
local work = os.tmpname():gsub("[\\/][^\\/]*$", "") .. sep .. "tm_module_test_" .. tostring(os.time())
local listed = {}

reaper = {
  GetResourcePath = function() return work end,
  RecursiveCreateDirectory = function(path)
    os.execute((sep == "\\" and 'mkdir "' or 'mkdir -p "') .. path .. '" 2>' .. (sep == "\\" and "NUL" or "/dev/null"))
    return 1
  end,
  EnumerateFiles = function(path, index)
    if index < 0 then return nil end
    local names = listed[path] or {}
    return names[index + 1]
  end,
  EnumerateSubdirectories = function() return nil end
}
package.loaded["core.theme"] = { colors = {} }
package.loaded["core.ui"] = {}
package.loaded["core.ui_scale"] = {}

local Diff = require("core.rpp_diff")
local Store = require("core.time_machine_store")
local Module = require("modules.time_machine")
local view = Module.debug.view

local passed = 0
local function expect(label, actual, expected)
  assert(actual == expected, string.format("%s: expected %s, got %s", label, tostring(expected), tostring(actual)))
  passed = passed + 1
end

local old = assert(Diff.parse(table.concat({
  "<REAPER_PROJECT 0.1",
  "  TEMPO 120 4 4",
  "  <TRACK {A}",
  "    NAME \"Kick\"",
  "    VOLPAN 1 0 -1 -1 1",
  "    TRACKID {A}",
  "  >",
  "  <TRACK {B}",
  "    NAME \"Bass\"",
  "    TRACKID {B}",
  "    <FXCHAIN",
  "      BYPASS 0 0 0",
  "      <VST \"VST3: Comp (X)\" c.vst3 0 \"\" 1{X} \"\"",
  "        AAAA",
  "      >",
  "      FXID {F1}",
  "    >",
  "  >",
  ">"
}, "\n") .. "\n"))
local new = assert(Diff.parse(table.concat({
  "<REAPER_PROJECT 0.1",
  "  TEMPO 124 4 4",
  "  <TRACK {A}",
  "    NAME \"Kick\"",
  "    VOLPAN 0.5 0 -1 -1 1",
  "    TRACKID {A}",
  "  >",
  "  <TRACK {B}",
  "    NAME \"Bass\"",
  "    TRACKID {B}",
  "    <FXCHAIN",
  "      BYPASS 0 0 0",
  "      <VST \"VST3: Comp (X)\" c.vst3 0 \"\" 1{X} \"\"",
  "        BBBB",
  "      >",
  "      FXID {F1}",
  "    >",
  "  >",
  ">"
}, "\n") .. "\n"))
local result = Diff.diff(old, new)

-- Changelog text.
local text = table.concat(view.changelog_lines({}, result), "\n")
expect("changelog", text, table.concat({
  "Project",
  "  ~ Tempo 120 -> 124 BPM",
  "1 · Kick",
  "  ~ Volume 0.0 dB -> -6.0 dB",
  "2 · Bass",
  "  ~ Comp state changed"
}, "\n"))

-- History filters.
local kick = view.focus_entries(result, { kind = "track", track_id = "{a}" })
expect("track focus ignores GUID case", #kick, 1)
expect("track focus entry", kick[1].entry.text, "Volume 0.0 dB -> -6.0 dB")
local comp = view.focus_entries(result, { kind = "plugin", fx_id = "{F1}" })
expect("plugin focus", #comp, 1)
expect("plugin focus keeps its track", comp[1].group.name, "Bass")
expect("unrelated focus", #view.focus_entries(result, { kind = "plugin", fx_id = "{nope}" }), 0)

-- Deleting a history removes its versions and manifest, nothing else.
local root = Store.root_for("")
local manifest = Store.new_manifest("DEL", work .. sep .. "song.rpp")
manifest.snapshots = { { file = "20260101-120000.rpp", time = 1, size = 3 } }
assert(Store.save_manifest(root, manifest))
local folder = Store.join(root, "DEL")
assert(Store.write_file(Store.join(folder, "20260101-120000.rpp"), "abc"))
assert(Store.write_file(Store.join(folder, "notes.txt"), "keep me"))
listed[folder] = { "20260101-120000.rpp", "manifest.json", "notes.txt" }
expect("deleted files", Store.delete_history(root, "DEL"), 2)
expect("manifest gone", Store.load_manifest(root, "DEL"), nil)
expect("other files kept", Store.read_file(Store.join(folder, "notes.txt")), "keep me")
os.remove(Store.join(folder, "notes.txt"))

expect("A/B verb is handled", type(Module.handle_action), "function")

print(string.format("time_machine_module_test: %d checks passed", passed))
