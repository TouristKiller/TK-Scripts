-- Pad names for a container rack.
--
-- A pad on a folder rack has a track, and a track has a name -- so the name has
-- somewhere obvious to live and the Kit Manager writes it there. A pad inside a
-- container has no track, so this is where its name goes instead: one JSON blob
-- on the rack track, keyed by the pad's FX GUID.
--
--     P_EXT:TK_KIT_MAKER_PADS
--       { "{GUID}": { name = "Kick", auto = "kick_909" } }
--
-- Keyed by GUID and not by pad number, for the reason that runs through this
-- whole feature: a position in an FX chain moves when the chain changes, and a
-- GUID is issued once and stays with the plugin. Reordering the pads inside the
-- container therefore renames nothing.
--
-- Not the FX instance's own name, which was the other candidate. See the top of
-- core/rs5k.lua: detection reads the plugin name, and a renamed RS5K was once
-- invisible to the Browser, which answered by adding a second one beside it.
-- Making the pad name BE the plugin name would put every pad of every container
-- rack permanently into the state that caused that.
--
-- ---------------------------------------------------------------------------
-- TWO values per pad, not one.
--
-- `name` is what is shown. `auto` is the last name this code chose by itself.
-- Loading a sample proposes a new name and it is only taken if the current one
-- is still the last proposal -- so a name you typed survives the next sample,
-- and a name nobody has touched keeps following the sample. That is exactly
-- what maybe_auto_name_pad_track does today with P_NAME and
-- P_EXT:TK_KIT_MAKER_PAD_AUTO_NAME on a pad track; this is the same pair with
-- nowhere else to live.
-- ---------------------------------------------------------------------------

local r = reaper
local json = require("core.json")

local M = {}

M.KEY = "P_EXT:TK_KIT_MAKER_PADS"

local function trim(s)
  return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

function M.load(track)
  if not track or not r.GetSetMediaTrackInfo_String then return {} end
  local ok, raw = r.GetSetMediaTrackInfo_String(track, M.KEY, "", false)
  if not ok or not raw or raw == "" then return {} end
  local decoded_ok, decoded = pcall(json.decode, raw)
  if not decoded_ok or type(decoded) ~= "table" then return {} end

  -- Rebuilt rather than trusted: a blob written by a newer version, or edited
  -- by hand, should not be able to put a table where a string belongs.
  local out = {}
  for guid, entry in pairs(decoded) do
    if type(guid) == "string" and guid ~= "" and type(entry) == "table" then
      out[guid] = {
        name = type(entry.name) == "string" and entry.name or "",
        auto = type(entry.auto) == "string" and entry.auto or "",
      }
    end
  end
  return out
end

function M.save(track, pads)
  if not track or not r.GetSetMediaTrackInfo_String then return false end
  local ok, encoded = pcall(json.encode, pads or {})
  if not ok or not encoded then return false end
  r.GetSetMediaTrackInfo_String(track, M.KEY, encoded, true)
  return true
end

-- The name to show for a pad, or "" when nothing has been stored. Callers fall
-- back to whatever they derive from the sample, which is what happens today
-- when a pad track has no name.
function M.get(track, guid)
  if not guid or guid == "" then return "" end
  local entry = M.load(track)[guid]
  return entry and entry.name or ""
end

-- A name the user typed. It clears `auto`, so the next sample cannot take it
-- back: once you have named a pad, it is yours.
function M.set(track, guid, name)
  if not track or not guid or guid == "" then return false end
  local pads = M.load(track)
  local clean = trim(name)
  if clean == "" then
    pads[guid] = nil
  else
    pads[guid] = { name = clean, auto = "" }
  end
  return M.save(track, pads)
end

-- A name derived from the sample. Taken only if the pad is unnamed or still
-- carries the last name this proposed. Returns whether it was taken.
function M.suggest(track, guid, name)
  if not track or not guid or guid == "" then return false end
  local clean = trim(name)
  if clean == "" then return false end

  local pads = M.load(track)
  local entry = pads[guid]
  local current = entry and entry.name or ""
  local last_auto = entry and entry.auto or ""

  local can_overwrite = current == "" or (last_auto ~= "" and current == last_auto)
  if not can_overwrite then return false end

  pads[guid] = { name = clean, auto = clean }
  return M.save(track, pads)
end

-- Drops entries whose pad is gone. A deleted pad is not an error and its entry
-- is harmless, but a rack edited over months would otherwise carry every pad it
-- has ever had.
function M.prune(track, live_guids)
  if not track then return false end
  local live = {}
  for _, g in ipairs(live_guids or {}) do
    if type(g) == "string" and g ~= "" then live[g] = true end
  end

  local pads = M.load(track)
  local changed = false
  for guid in pairs(pads) do
    if not live[guid] then
      pads[guid] = nil
      changed = true
    end
  end
  if not changed then return false end
  return M.save(track, pads)
end

return M
