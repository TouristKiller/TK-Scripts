-- What a rack IS, and how to find the one you are pointing at.
--
-- Today a rack is a folder track with a pad track under it per slot, and three
-- files each carry their own copy of "walk up until you hit a folder". This is
-- that walk, once -- and the place where a second kind of rack can be
-- recognised without every caller learning about it.
--
-- Nothing creates a container rack yet. The recognition is here first so that
-- when Phase 3 starts building them, every view already knows what it is
-- looking at.

local r = reaper
local Lane = require("core.lane")
local RS5K = require("core.rs5k")
local Pads = require("core.padnames")
local json = require("core.json")

local M = {}

-- Written on the TRACK, holding the container's FX GUID. Track ext state is
-- what this project already uses to mark things it owns (the sequencer's bus
-- carries P_EXT:TK_KIT_MAKER_SEQ_BUS the same way) and it survives in the
-- project file.
M.MARKER = "P_EXT:TK_KIT_MAKER_RACK"

-- Which plugin is which pad, in pad order, as FX GUIDs.
--
-- Without this a pad is only "the Nth child of the container", and that is a
-- position: drop an FX inside the container and every pad after it becomes the
-- one next door -- silently, because an address that resolves to the wrong
-- plugin looks exactly like one that resolves to the right plugin.
--
-- It is the third thing in this feature to need writing down for the same
-- reason. The container is found by GUID, pad names are keyed by GUID, and now
-- the pads themselves.
M.PAD_ORDER = "P_EXT:TK_KIT_MAKER_PAD_ORDER"

local function is_folder(track)
  if not track then return false end
  return (r.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH") or 0) > 0
end

-- ---------------------------------------------------------------------------
-- Folder racks -- what exists today
-- ---------------------------------------------------------------------------

-- The nearest folder at or above `track`.
--
-- The three views used to carry their own copy of this, and the Browser's
-- stopped after one level while the other two walked all the way up. That
-- looked like a difference worth preserving and is not one: GetParentTrack
-- returns the ENCLOSING FOLDER, so a parent is a folder by construction and the
-- one-level check can never fail where the walk would have succeeded. The two
-- answered identically in any project REAPER can produce; only the code
-- disagreed.
function M.folder_parent(track)
  local current = track
  while current do
    if is_folder(current) then return current end
    if not r.GetParentTrack then break end
    current = r.GetParentTrack(current)
  end
  return nil
end

function M.selected_parent()
  return M.folder_parent(r.GetSelectedTrack(0, 0))
end

-- ---------------------------------------------------------------------------
-- Container racks -- not built by anything yet
-- ---------------------------------------------------------------------------

-- The container that holds this track's pads, or -1.
--
-- Found by GUID, not by index, and the reason is the same one that runs through
-- core/lane.lua: an FX index is a position in a chain, and positions move. A
-- user dropping an EQ at the top of the chain would repoint a stored index at
-- the EQ. An FX GUID is issued once and stays with the plugin, so it is the
-- only thing here worth writing down.
--
-- The scan is over top-level FX only, which is a handful, and it happens on use
-- rather than being cached -- for exactly the same reason.
function M.container_guid(track)
  if not track or not r.GetSetMediaTrackInfo_String then return "" end
  local ok, guid = r.GetSetMediaTrackInfo_String(track, M.MARKER, "", false)
  if not ok or not guid then return "" end
  return guid
end

-- Resolved through core/lane.lua so there is one GUID lookup in the program,
-- not two. A marker that outlives its container -- the user deleted it by hand
-- -- comes back as -1: not an error, just not a container rack any more.
function M.container_fx(track)
  return Lane.fx_index_by_guid(track, M.container_guid(track))
end

function M.mark_container(track, fx)
  if not track or not fx or fx < 0 then return false end
  if not r.TrackFX_GetFXGUID or not r.GetSetMediaTrackInfo_String then return false end
  local guid = r.TrackFX_GetFXGUID(track, fx)
  if not guid or guid == "" then return false end
  r.GetSetMediaTrackInfo_String(track, M.MARKER, guid, true)
  return true
end

function M.clear_container(track)
  if not track or not r.GetSetMediaTrackInfo_String then return false end
  r.GetSetMediaTrackInfo_String(track, M.MARKER, "", true)
  return true
end

-- ---------------------------------------------------------------------------

-- What kind of rack `track` belongs to, or nil for none.
--
--   { style = "container", track = ..., container = fx_index }
--   { style = "tracks",    parent = ... }
--
-- The container test comes first because a container rack is a single track and
-- could perfectly well be sitting inside a folder for tidiness -- in which case
-- the folder is not the rack, and asking about folders first would say it was.
function M.of(track)
  if not track then return nil end

  local cfx = M.container_fx(track)
  if cfx >= 0 then
    -- `container` is where it is right now, for a caller about to use it.
    -- `guid` is the part worth keeping.
    return { style = "container", track = track, container = cfx, guid = M.container_guid(track) }
  end

  local parent = M.folder_parent(track)
  if parent then
    return { style = "tracks", parent = parent }
  end
  return nil
end

function M.selected()
  return M.of(r.GetSelectedTrack(0, 0))
end

-- The track a rack keeps its data on -- its sequence, its patterns, its name.
-- For a folder rack that is the folder; for a container rack the rack IS one
-- track, so it is that track. Everything downstream that says `parent` wants
-- this, and wants it to be the same handle whichever shape the rack is.
function M.host(desc)
  if not desc then return nil end
  if desc.style == "container" then return desc.track end
  return desc.parent
end

function M.selected_host()
  return M.host(M.selected())
end

-- ---------------------------------------------------------------------------
-- Building a container rack
-- ---------------------------------------------------------------------------

-- One track, one marked container, `pads` samplers inside it, each answering to
-- one note from `base_note` upwards.
--
-- Structure only: no samples. Filling pads is the caller's job, exactly as it
-- is for a folder rack -- the Browser fills from a collection, the Kit Manager
-- leaves them empty, and neither wants this function to know about either.
--
-- Returns track, container_fx -- or nil and a reason.
--
-- Every insertion is CHECKED, and that is not defensiveness. Adding an FX at an
-- address REAPER does not understand can succeed at the wrong place: it lands
-- on the track instead of in the container and hands back a perfectly valid
-- index for it. The spike behind this feature was fooled exactly that way. So
-- the test is that the container gained a child, and a rack that cannot be
-- built is abandoned rather than half made.
function M.build_container(opts)
  opts = opts or {}
  local pads = math.max(1, math.floor(tonumber(opts.pads) or 16))
  local base_note = math.floor(tonumber(opts.base_note) or 36)

  if not r.TrackFX_AddByName or not r.TrackFX_GetNamedConfigParm then
    return nil, "this REAPER cannot make FX containers (needs REAPER 7)"
  end

  local index = opts.index
  if index == nil then
    local after = opts.insert_after
    index = after and math.floor(r.GetMediaTrackInfo_Value(after, "IP_TRACKNUMBER") or 0)
      or r.CountTracks(0)
  end

  r.InsertTrackAtIndex(index, true)
  local track = r.GetTrack(0, index)
  if not track then return nil, "could not create a track for the rack" end
  r.GetSetMediaTrackInfo_String(track, "P_NAME", opts.name or "Kit", true)

  local ci = r.TrackFX_AddByName(track, "Container", false, -1)
  if not ci or ci < 0 then
    return nil, "could not add an FX container (needs REAPER 7)"
  end
  if not M.mark_container(track, ci) then
    return nil, "could not mark the container as a rack"
  end

  for j = 1, pads do
    local before = Lane.container_count(track, ci)
    -- Worked out immediately before use, never carried between iterations.
    local addr = Lane.container_child_address(track, ci, j)
    r.TrackFX_AddByName(track, "ReaSamplOmatic5000 (Cockos)", false, -1000 - addr)

    if Lane.container_count(track, ci) ~= before + 1 then
      return nil, string.format("pad %d would not go into the container", j)
    end
    RS5K.set_note(track, Lane.container_child_address(track, ci, j), base_note + j - 1)
  end

  -- Written down while the rack is still exactly as it was built, which is the
  -- only moment position and identity are certainly the same thing.
  M.set_pad_order(track, M.pad_guids(track, ci))

  return track, ci
end

-- The FX GUIDs of a container rack's pads, in pad order. This is what pad names
-- are keyed by, and what prunes the ones whose pad has gone.
function M.pad_guids(track, container_fx)
  local out = {}
  if not track or not container_fx or container_fx < 0 then return out end
  if not r.TrackFX_GetFXGUID then return out end
  for j = 1, Lane.container_count(track, container_fx) do
    out[j] = r.TrackFX_GetFXGUID(track, Lane.container_child_address(track, container_fx, j))
  end
  return out
end

-- The recorded pad order, or an empty table. Callers treat an empty one as
-- "fall back to position", which is what a rack built before this existed has.
function M.pad_order(track)
  if not track or not r.GetSetMediaTrackInfo_String then return {} end
  local ok, raw = r.GetSetMediaTrackInfo_String(track, M.PAD_ORDER, "", false)
  if not ok or not raw or raw == "" then return {} end
  local decoded_ok, decoded = pcall(json.decode, raw)
  if not decoded_ok or type(decoded) ~= "table" then return {} end

  local out = {}
  for i, guid in ipairs(decoded) do
    out[i] = type(guid) == "string" and guid or ""
  end
  return out
end

function M.set_pad_order(track, guids)
  if not track or not r.GetSetMediaTrackInfo_String then return false end
  local clean = {}
  for i, guid in ipairs(guids or {}) do
    clean[i] = type(guid) == "string" and guid or ""
  end
  local ok, encoded = pcall(json.encode, clean)
  if not ok or not encoded then return false end
  r.GetSetMediaTrackInfo_String(track, M.PAD_ORDER, encoded, true)
  return true
end

-- The stored name of each pad, in pad order, "" where none is stored.
--
-- Here rather than left to the caller because it is two lookups that belong
-- together -- the GUIDs, and then the names keyed by them -- and because the
-- Step sequencer sits one variable under Lua's ceiling of 200 locals and cannot
-- afford to require core/padnames.lua for a single call.
function M.pad_names(track, container_fx)
  local out = {}
  for j, guid in ipairs(M.pad_guids(track, container_fx)) do
    out[j] = Pads.get(track, guid)
  end
  return out
end

return M
