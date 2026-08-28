local source = debug.getinfo(1, "S").source:sub(2)
local tests_dir = source:match("^(.*[\\/])") or ""
local root_dir = tests_dir:gsub("tests[\\/]$", "")
package.path = root_dir .. "?.lua;" .. root_dir .. "?" .. package.config:sub(1, 1) .. "init.lua;" .. package.path

local Engine = require("core.chord_engine")

local passed = 0

local function expect_name(label, pitches, expected, options)
  local result = Engine.resolve(pitches, options)
  local actual = result and result.name or nil
  assert(actual == expected, string.format("%s: expected %s, got %s", label, tostring(expected), tostring(actual)))
  passed = passed + 1
  return result
end

local function expect_value(label, actual, expected)
  assert(actual == expected, string.format("%s: expected %s, got %s", label, tostring(expected), tostring(actual)))
  passed = passed + 1
end

expect_name("major triad", { 60, 64, 67 }, "C")
expect_name("minor triad", { 57, 60, 64 }, "Am")
expect_name("first inversion", { 52, 55, 60 }, "C/E")
expect_name("flat spelling", { 58, 62, 65, 69 }, "Bbmaj7", { prefer_flats = true })
expect_name("dominant altered", { 60, 63, 64, 67, 70 }, "C7#9")
expect_name("minor extension", { 54, 57, 61, 64, 68 }, "F#m9")
expect_name("table input", { { pitch = 60 }, { pitch = 64 }, { pitch = 67 } }, "C")
expect_name("sixth ambiguity", { 48, 52, 55, 57 }, "C6")
expect_name("minor seventh ambiguity", { 45, 48, 52, 55 }, "Am7")
local contextual = expect_name("minor key context", { 48, 52, 55, 57 }, "Am7/C", {
  key_root = 9,
  key_mode = "minor"
})
expect_value("context alternative", contextual.alternatives[1].name, "C6")
expect_value("context alternative confidence", contextual.alternatives[1].confidence, 1)

local fuzzy = expect_name("missing ninth in thirteenth", { 55, 59, 62, 64, 65 }, "G13")
expect_value("fuzzy match flag", fuzzy.exact, false)
expect_value("fuzzy missing tone", fuzzy.missing, 1)

local rootless = expect_name("rootless dominant", { 52, 55, 58, 62 }, "C9/E", {
  allow_rootless = true,
  root_hint = 0
})
expect_value("rootless match flag", rootless.exact, false)

expect_name("single note rejected", { 60 }, nil)
expect_name("empty input rejected", {}, nil)

local message = string.format("Chord engine: %d tests passed", passed)
if reaper and reaper.ShowConsoleMsg then
  reaper.ShowConsoleMsg(message .. "\n")
else
  print(message)
end