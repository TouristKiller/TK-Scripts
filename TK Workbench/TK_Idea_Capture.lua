-- @description TK Idea Capture
-- @author TouristKiller
-- @version 0.1.0
-- @changelog:
--   + Initial release: saves the selected track as a track template plus a
--     tempo-tagged audio preview, in one action, without opening TK Workbench

local r = reaper

local SCRIPT_NAME = "TK Idea Capture"

local script_path = debug.getinfo(1, "S").source:match("@?(.*[\\/])") or ""
local sep = package.config:sub(1, 1)
package.path = script_path .. "?.lua;" .. script_path .. "?" .. sep .. "init.lua;" .. package.path

local ok_store, Store = pcall(require, "core.idea_vault_store")
if not ok_store then
  r.ShowMessageBox("Could not load the Idea Vault store:\n\n" .. tostring(Store), SCRIPT_NAME, 0)
  return
end

-- GetUserInputs hands its fields back as one comma-separated string, so a
-- description like "slow, wintery" would arrive as two fields and shift
-- everything after it. REAPER can be told to use another separator, but not
-- every build honours it, so this asks for one it can detect afterwards and
-- falls back to a greedy split when the returned string clearly ignored it.
local FIELD_SEP = "\29"

local function split_fields(csv, count)
  local fields = {}
  if csv:find(FIELD_SEP, 1, true) then
    local pattern = "([^" .. FIELD_SEP .. "]*)" .. FIELD_SEP .. "?"
    for value in csv:gmatch(pattern) do
      fields[#fields + 1] = value
      if #fields == count then break end
    end
  else
    -- Description sits last precisely so this fallback can keep its commas:
    -- everything past the third comma is one field again.
    local rest = csv
    for _ = 1, count - 1 do
      local value, remainder = rest:match("^([^,]*),(.*)$")
      if not value then break end
      fields[#fields + 1] = value
      rest = remainder
    end
    fields[#fields + 1] = rest
  end
  for i = 1, count do fields[i] = (fields[i] or ""):match("^%s*(.-)%s*$") end
  return fields
end

local function is_yes(value)
  value = tostring(value or ""):lower()
  return value == "" or value == "y" or value == "yes" or value == "j" or value == "ja" or value == "1"
end

local function split_tags(value)
  local tags = {}
  for tag in tostring(value or ""):gmatch("[^%s,]+") do tags[#tags + 1] = tag end
  return tags
end

local function suggested_name()
  local track = r.GetSelectedTrack(0, 0)
  if not track then return "" end
  local _, name = r.GetTrackName(track)
  name = tostring(name or ""):match("^%s*(.-)%s*$")
  -- An unnamed track reads back as "Track 3", which is a worse starting point
  -- than an empty field: the user would have to clear it before typing.
  if name == "" or name:match("^Track%s+%d+$") then return "" end
  return name
end

if not r.GetSelectedTrack(0, 0) then
  r.ShowMessageBox("Select the track you want to keep first.", SCRIPT_NAME, 0)
  return
end

local captions = table.concat({
  "Name",
  "Tags (space separated)",
  "Render preview (y/n)",
  "Description",
  "extrawidth=280",
  "separator=" .. FIELD_SEP
}, ",")

local defaults = table.concat({ suggested_name(), "", "y", "" }, FIELD_SEP)

local ok, csv = r.GetUserInputs(SCRIPT_NAME, 4, captions, defaults)
if not ok then return end

local fields = split_fields(csv, 4)
local render = is_yes(fields[3])

local idea, warning = Store.capture({
  name = fields[1],
  tags = split_tags(fields[2]),
  description = fields[4],
  render = render
})

if not idea then
  r.ShowMessageBox(tostring(warning or "The capture failed."), SCRIPT_NAME, 0)
  return
end

-- A full capture says nothing: the render dialog was the feedback, and this is
-- meant to be one keystroke on a morning where the point is to keep playing.
-- Anything less than a full capture does report, because otherwise a missing
-- preview would only turn up weeks later when auditioning.
if warning and tostring(idea.preview or "") ~= "" then
  -- The render ran and left a file behind, so the warning is about what ended
  -- up in it. Repeating the render-format advice here would send the user off
  -- to fix a setting that is already correct.
  r.ShowMessageBox(
    "Saved \"" .. idea.name .. "\", but the preview may not sound right:\n\n"
      .. tostring(warning),
    SCRIPT_NAME, 0)
elseif warning then
  r.ShowMessageBox(
    "Saved the template for \"" .. idea.name .. "\", but the preview render failed:\n\n"
      .. tostring(warning)
      .. "\n\nSet the preview format once in the render dialog, then run\n"
      .. "Idea Vault's \"use the project's render format\" to store it.",
    SCRIPT_NAME, 0)
elseif not render then
  r.ShowMessageBox("Saved \"" .. idea.name .. "\" as a template, without a preview.", SCRIPT_NAME, 0)
end
