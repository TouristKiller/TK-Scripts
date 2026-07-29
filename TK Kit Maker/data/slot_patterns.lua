-- Reusable slot patterns for Folder Explosion and the Kit Builder.
-- Built-ins are read-only; user patterns live in one JSON file under
-- reaper.GetResourcePath() .. "/TK_Kit_Maker/slot_patterns.json"

local r = reaper
local Json = require("core.json")

local M = {}

M.BUILTIN = {
  { name = "Kick / Snare",        pattern = "Kick, Snare" },
  { name = "Classic 4",           pattern = "Kick, Snare, Hihat, Clap" },
  { name = "Classic 8",           pattern = "Kick, Snare, Closed hihat, Open hihat, Clap, Rim, Tom, Crash" },
  { name = "Drum machine 16",     pattern = "Kick, Snare, Closed hihat, Open hihat, Clap, Rim, Tom, Tom, Crash, Ride, Cymbal, Perc, Shaker, Perc, FX, 808" },
  { name = "Hats only",           pattern = "Closed hihat, Open hihat" },
  { name = "Percussion",          pattern = "Perc, Shaker, Tom, Rim" },
  { name = "Cymbals",             pattern = "Crash, Ride, Cymbal, Open hihat" },
  { name = "808 rack",            pattern = "808, Kick, Snare, Clap, Closed hihat, Open hihat, Rim, Cowbell" },
  { name = "Melodic / FX",        pattern = "Bass, 808, Vocal, FX" },
}

local function store_path()
  return r.GetResourcePath() .. "/TK_Kit_Maker/slot_patterns.json"
end

local function trim(s)
  return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

function M.load()
  local f = io.open(store_path(), "r")
  if not f then return {} end
  local content = f:read("*a")
  f:close()

  local ok, data = pcall(Json.decode, content)
  if not ok or type(data) ~= "table" then return {} end

  local out = {}
  for _, item in ipairs(data.patterns or {}) do
    local name = trim(item and item.name)
    local pattern = trim(item and item.pattern)
    if name ~= "" and pattern ~= "" then
      out[#out + 1] = { name = name, pattern = pattern }
    end
  end
  return out
end

function M.save(list)
  r.RecursiveCreateDirectory(r.GetResourcePath() .. "/TK_Kit_Maker", 0)
  local ok, encoded = pcall(Json.encode, { patterns = list or {} })
  if not ok then return false, "cannot serialize slot patterns" end
  local f = io.open(store_path(), "w")
  if not f then return false, "cannot write slot patterns" end
  f:write(encoded)
  f:close()
  return true
end

function M.add(list, name, pattern)
  name, pattern = trim(name), trim(pattern)
  if name == "" then return false, "Give the pattern a name." end
  if pattern == "" then return false, "The slot pattern is empty." end
  for _, item in ipairs(list) do
    if item.name:lower() == name:lower() then
      item.pattern = pattern
      return M.save(list)
    end
  end
  list[#list + 1] = { name = name, pattern = pattern }
  table.sort(list, function(a, b) return a.name:lower() < b.name:lower() end)
  return M.save(list)
end

function M.remove(list, name)
  for i, item in ipairs(list) do
    if item.name == name then
      table.remove(list, i)
      return M.save(list)
    end
  end
  return false, "Pattern not found."
end

return M
