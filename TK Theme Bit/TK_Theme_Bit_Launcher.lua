-- TK Theme Bit - Launcher: Bitwig's clip launcher for REAPER, meant for the docker at the
-- left of the arrange. One row per track, lined up with the arrange's own tracks (heights
-- and scrolling follow the arrange), one column per scene. Left of the grid each row has a
-- track header drawn like Bit's track panel, so REAPER's own track panel can be made narrow.
-- Run the action again to close it.
--
-- Bitwig's model: a track is played either by the arranger or by the launcher. Launching
-- a clip or pressing a track's stop square hands the track to the launcher (the arrange's
-- items on that track are muted); only the track's return arrow (at the right) gives it back
-- to the arranger, and it does so at once. Launches and stops land on the launch grid
-- (Launch Q), on the project's own bars.
--
-- Clicks: the play triangle launches a clip, the clip body selects it (drag it to another
-- slot; Ctrl copies), an empty slot or the stop square stops the track, a scene's triangle
-- launches the whole scene (empty slots stop their tracks). Right-click for menus. Add clips
-- from the arrange's selected items (the "+" on an empty slot, or its menu) or drag a file
-- in from TK Media Browser / Workbench (the TK_DRAG protocol, which also works docked).
--
-- Engine: adapted (copied, not shared) from TK Project Clips' launcher, where every choice
-- below was measured. Each track with clips gets a hidden "Bit Launcher" track that sends
-- into it, so a clip is heard through the track's FX. The clips sit muted and stacked at time
-- zero on that hidden track; launching copies one as a "voice" item onto the timeline ahead
-- of the play cursor, on the next grid line, so the switch is sample-accurate. The hidden
-- tracks have media buffering off, which is what lets a voice be written only ~0.3 s ahead.
-- Mutes the launcher sets are mirrored into the project (restore), so a crash is repaired
-- the next time the launcher opens. It keeps its own project data and track tag; TK Project
-- Clips' launcher is a separate script and is never touched.

local r = reaper
if not r.ImGui_CreateContext then
  r.ShowMessageBox("The launcher needs ReaImGui (install it through ReaPack).", "TK Theme Bit", 0)
  return
end
do
  local _, _, version = r.ImGui_GetVersion()
  local major, minor = tostring(version):match("^(%d+)%.(%d+)")
  if not major or (tonumber(major) == 0 and tonumber(minor) < 10) then
    r.ShowMessageBox("The launcher needs ReaImGui 0.10 or newer.", "TK Theme Bit", 0)
    return
  end
  if not r.BR_GetMediaItemByGUID then
    r.ShowMessageBox("The launcher needs the SWS extension (install it through ReaPack).", "TK Theme Bit", 0)
    return
  end
end

if r.set_action_options then r.set_action_options(1 | 4) end
local _, _, section_id, cmd_id = r.get_action_context()

local ctx = r.ImGui_CreateContext("TK Bit Launcher")
local font = r.ImGui_CreateFont("Inter")
r.ImGui_Attach(ctx, font)
local font_bold = r.ImGui_CreateFont("Inter", r.ImGui_FontFlags_Bold and r.ImGui_FontFlags_Bold() or 0)
r.ImGui_Attach(ctx, font_bold)

-- Bit's panel colours (Inspector / Devices) plus the launcher's, measured from the user's
-- Bitwig screenshot (2026-11-26): empty slot 38, slot seams 29-34, stop column 47, scene
-- header row and return column 73, track header 50-61
local C = {
  bg = 0x101010FF, empty = 0x262626FF, seam = 0x1D1D1DFF, stopcol = 0x2F2F2FFF, retcol = 0x494949FF,
  scenehead = 0x494949FF, head = 0x323232FF, head_sel = 0x3D3D3DFF, field = 0x040404FF,
  line = 0x242424FF, accent = 0xFF6000FF, text = 0xE6E6E6FF, dim = 0x8A8A8AFF, value = 0xF75D07FF,
  key_top = 0x363636FF, key_bot = 0x292929FF, key_edge = 0x0A0A0AFF, seg_hi = 0x444444FF,
  arm = 0xE0262EFF, solo = 0xE8C34AFF, mute = 0xFF6000FF, square = 0x5A5A5AFF, square_hi = 0xB4B4B4FF,
  icon = 0x9A9A9AFF, meter = 0x7BD36AFF, meter_hot = 0xE8C34AFF, meter_clip = 0xFF5A4AFF,
  sel = 0xFFFFFFFF, popup = 0x1B1B1BFF,
}
local K = {
  ext = "TK_BIT_LAUNCHER", tag = "P_EXT:TK_BIT_LAUNCHER", other_tag = "P_EXT:TK_CLIP_LAUNCHER",
  head_w = 158, head_w_small = 150, stop_w = 18, ret_w = 22, scene_w = 88, top_h = 24,
  lead = 0.30, min_lead = 0.05, voice_length = 300, voice_extend = 300, voice_margin = 60,
  harvest_pad = 0.10, fade = 0.005, scenes = 8,
}
-- launch grid: > 0 = bars, < 0 = minus quarter notes, 0 = off (as soon as possible)
-- the grid lives on the master track (P_EXT), because REAPER's undo keeps track data and not
-- project ext state: Ctrl+Z then brings back the launcher's slots together with their items
K.grid = "P_EXT:TK_BIT_LAUNCHER_GRID"
K.dir = (({ r.get_action_context() })[2] or ""):match("^(.*)[\\/]") or ""   -- this script's folder
local QUANT = {
  { 0, "Off" }, { -0.25, "1/16" }, { -0.5, "1/8" }, { -1, "1/4" }, { -2, "1/2" },
  { 1, "1 bar" }, { 2, "2 bars" }, { 4, "4 bars" }, { 8, "8 bars" },
}
-- Bitwig's play modes, release actions and next actions (user guide, 2026)
local LISTS = {
  mode = { { "start", "Trigger from Start" }, { "legato_c", "Legato from Clip (or Start)" },
           { "legato_cp", "Legato from Clip (or Project)" }, { "legato_p", "Legato from Project" } },
  rel = { { "continue", "Continue" }, { "stop", "Stop" }, { "return", "Return" }, { "next", "Next Action" } },
  next = { { "stop", "Stop" }, { "arrange", "Return to Arrangement" }, { "back", "Return to Last Clip" },
           { "next", "Play Next" }, { "prev", "Play Previous" }, { "first", "Play First" },
           { "last", "Play Last" }, { "random", "Play Random" }, { "other", "Play Other" },
           { "round", "Round-robin" } },
  loops = { 1, 2, 3, 4, 8, 16 },
  -- the Inspector's palette, 3 rows of 8 (false = the track's colour)
  palette = {
    0x3A3A3A, 0x5A5A5A, 0x7E7E7E, 0x5C6B8A, 0x8A6A4A, 0xB08A5A, 0x5450B0, 0x7B5AD0,
    0xD12E2E, 0xE8451C, 0xF07A1A, 0xD99D10, 0x7A8A1C, 0x2A8A3E, 0x1AA28C, 0x2E7FD1,
    0xE0606A, 0xF08A70, 0xF5A850, 0xE8C34A, 0xA6C040, 0x5CC05C, 0x4CC8C0, false,
  },
}
function LISTS.label(list, key)
  for _, e in ipairs(LISTS[list]) do if e[1] == key then return e[2] end end
  return "?"
end
-- the clip gate: shuts a lane's sound at once (a release, a return), and opens again by
-- itself at a timeline position, so the next clip is never clipped by the script's timing.
-- Written to Effects/TK Theme Bit/ the first time a lane needs one.
local GATE = { file = "TK_Bit_Launcher_Gate.jsfx", desc = "TK Bit Launcher Gate", src = [==[
desc:TK Bit Launcher Gate
//tags: utility
// Written by TK_Theme_Bit_Launcher.lua (TK Theme Bit), adapted from TK Project Clips' clip
// gate. It sits on a hidden launcher track. The launcher shuts it (Open = 0) and sets
// Open at: the project time at which it opens again by itself, sample-accurate.
slider1:open=1<0,1,1>-Open
slider2:open_at=-1<-1,1000000,0.0001>-Open at (project time, -1 = none)

@init
gain = 1;
ramp = 1 / max(1, srate * 0.004);
held = 0;
memset(held, 0, 16 * 128);
was_open = 1;
ext_noinit = 1;

@block
// opening at a timeline position: the sample inside this block where it is reached
open_spl = -1;
open < 0.5 && open_at >= 0 && (play_state & 1) ? (
  d = (open_at - play_position) * srate;
  d < samplesblock ? ( open_spl = max(0, floor(d)); );
);
opened = open >= 0.5 || open_spl >= 0;
while (midirecv(offs, msg1, msg2, msg3)) (
  status = msg1 & 0xF0;
  chan = msg1 & 0x0F;
  live = open >= 0.5 || (open_spl >= 0 && offs >= open_spl);
  status == 0x90 && msg3 > 0 ? (
    live ? ( held[chan * 128 + msg2] = 1; midisend(offs, msg1, msg2, msg3); );
  ) : (status == 0x80 || (status == 0x90 && msg3 == 0)) ? (
    held[chan * 128 + msg2] = 0;
    midisend(offs, msg1, msg2, msg3);
  ) : (
    live ? midisend(offs, msg1, msg2, msg3);
  );
);
was_open && open < 0.5 ? (
  i = 0;
  loop(16 * 128,
    held[i] ? ( midisend(0, 0x80 + floor(i / 128), i - floor(i / 128) * 128, 0); held[i] = 0; );
    i += 1;
  );
  ch = 0;
  loop(16, midisend(0, 0xB0 + ch, 123, 0); midisend(0, 0xB0 + ch, 120, 0); ch += 1; );
);
was_open = open >= 0.5;
n = 0;

@sample
open_spl >= 0 && n == open_spl ? ( open = 1; open_at = -1; was_open = 1; sliderchange(open); sliderchange(open_at); );
target = open >= 0.5 ? 1 : 0;
gain < target ? gain = min(target, gain + ramp) : gain = max(target, gain - ramp);
spl0 *= gain;
spl1 *= gain;
n += 1;
]==] }

local L = {                -- the launcher's state
  proj = nil, loaded = false, lanes = {}, scenes = {}, quantize = 1, headers = true,
  roll_guard = 0, last_heard = nil, status = "", scene_off = 0, track_count = -1, tidy = false,
  sel = nil, drag = nil, menu = nil, rename = nil, want_file = nil, drag_path = nil, hover = nil,
  cells = {}, peaks = {}, notes = {}, checked = 0, dock_to = nil, close = false, other = false,
  held = nil, recs = {}, perf = false, perf_spans = {}, perf_hi = 0,
  -- the project's launch defaults, Bitwig's: Main = the Launch Q field, Trigger from Start,
  -- Continue; ALT (Alt-click) = Q Off, Legato from Clip (or Project), Return
  def = { mode = "start", rel = "continue", aq = 0, amode = "legato_cp", arel = "return" },
}
-- what a slot keeps in the project: q / mode / rel are its Main launch settings, aq / amode /
-- arel its ALT ones (nil = the project's), na / na_n its Next Action and after how many loops
-- (no colour: a clip's colour is its item's, see E.sync_colours)
local SLOT_KEYS = { "guid", "name", "midi","q", "mode", "rel", "aq", "amode", "arel", "na", "na_n", "bpm", "bpm_guess", "nosync" }
local H = {}               -- helpers and data
local E = {}               -- engine
local U = {}               -- drawing

----------------------------------------------------------------------------------------------
-- helpers
----------------------------------------------------------------------------------------------

function H.valid_item(item) return item ~= nil and r.ValidatePtr2(0, item, "MediaItem*") end
function H.valid_track(track) return track ~= nil and r.ValidatePtr2(0, track, "MediaTrack*") end
function H.item(guid)
  if not guid or guid == "" then return nil end
  local item = r.BR_GetMediaItemByGUID(0, guid)
  return H.valid_item(item) and item or nil
end
function H.track(guid)
  if not guid or guid == "" then return nil end
  local track = r.BR_GetMediaTrackByGUID(0, guid)
  return H.valid_track(track) and track or nil
end
function H.item_guid(item) return r.BR_GetMediaItemGUID(item) end

-- a small serializer for the project data: plain tables, numbers, strings and booleans
function H.ser(v)
  local t = type(v)
  if t == "number" then return string.format("%.17g", v) end
  if t == "string" then return string.format("%q", v) end
  if t == "boolean" then return v and "true" or "false" end
  if t ~= "table" then return "nil" end
  local keys = {}
  for k in pairs(v) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b)
    if type(a) ~= type(b) then return type(a) == "number" end
    return a < b
  end)
  local out = {}
  for _, k in ipairs(keys) do
    local key = type(k) == "number" and ("[" .. string.format("%.17g", k) .. "]") or ("[" .. string.format("%q", k) .. "]")
    out[#out + 1] = key .. "=" .. H.ser(v[k])
  end
  return "{" .. table.concat(out, ",") .. "}"
end
function H.deser(s)
  if not s or s == "" then return nil end
  local fn = load("return " .. s, "data", "t", {})
  if not fn then return nil end
  local ok, v = pcall(fn)
  return ok and type(v) == "table" and v or nil
end

function H.is_lane_track(track)
  if not H.valid_track(track) then return false end
  local ok, v = r.GetSetMediaTrackInfo_String(track, K.tag, "", false)
  return ok and v == "1"
end

-- the launcher's own tracks (where the clips live) in the track panel or not: read off the
-- tracks, so it stays true after a change in the track manager
function H.lanes_shown()
  for i = 0, r.CountTracks(0) - 1 do
    local t = r.GetTrack(0, i)
    if H.is_lane_track(t) then return r.GetMediaTrackInfo_Value(t, "B_SHOWINTCP") > 0.5 end
  end
  return false
end
function H.lanes_shown_except(track)
  for i = 0, r.CountTracks(0) - 1 do
    local t = r.GetTrack(0, i)
    if t ~= track and H.is_lane_track(t) then return r.GetMediaTrackInfo_Value(t, "B_SHOWINTCP") > 0.5 end
  end
  return false
end
function H.show_lanes(on)
  L.lay = nil                        -- the track layout changes: read it again
  r.PreventUIRefresh(1)
  for i = 0, r.CountTracks(0) - 1 do
    local t = r.GetTrack(0, i)
    if H.is_lane_track(t) then r.SetMediaTrackInfo_Value(t, "B_SHOWINTCP", on and 1 or 0) end
  end
  r.PreventUIRefresh(-1)
  r.TrackList_AdjustWindows(false)
  r.UpdateArrange()
end

-- every selected item unselected through the API, item by item (as TK Bit Clip Edit does):
-- SelectAllMediaItems appears to leave items on hidden tracks selected, so a launcher clip
-- clicked before stayed selected beside the next, and the inspector showed the first of them
function H.unselect_items()
  for i = r.CountSelectedMediaItems(0) - 1, 0, -1 do
    r.SetMediaItemSelected(r.GetSelectedMediaItem(0, i), false)
  end
end

function H.track_name(track)
  local _, name = r.GetTrackName(track)
  return name or "Track"
end

-- native colour -> 0xRRGGBBFF, or nil when the track / item has none
function H.rgba(native)
  if not native or native == 0 or (native & 0x1000000) == 0 then return nil end
  local rr, gg, bb = r.ColorFromNative(native & 0xFFFFFF)
  return (rr << 24) | (gg << 16) | (bb << 8) | 0xFF
end
function H.shade(col, f)   -- f < 1 darker, > 1 lighter
  local rr, gg, bb = (col >> 24) & 255, (col >> 16) & 255, (col >> 8) & 255
  local function c(x) return math.max(0, math.min(255, math.floor(f >= 1 and x + (255 - x) * (f - 1) or x * f))) end
  return (c(rr) << 24) | (c(gg) << 16) | (c(bb) << 8) | (col & 255)
end
function H.light(col)
  local rr, gg, bb = (col >> 24) & 255, (col >> 16) & 255, (col >> 8) & 255
  return 0.299 * rr + 0.587 * gg + 0.114 * bb > 150
end

function H.slot_colour(lane, slot)
  if slot and slot.color then return slot.color end
  local track = lane and H.track(lane.track_guid)
  return (track and H.rgba(r.GetTrackColor(track))) or 0x8A8A8AFF
end

----------------------------------------------------------------------------------------------
-- project data
----------------------------------------------------------------------------------------------

-- an undo step of the launcher's own: whatever happens inside is one Ctrl+Z, the grid included
function H.begin()
  r.Undo_BeginBlock()
  L.in_block = (L.in_block or 0) + 1
end
function H.finish(desc)
  H.save()
  L.in_block = math.max(0, (L.in_block or 1) - 1)
  r.Undo_EndBlock(desc, -1)
end

-- the grid as it is stored: the same text for the same grid (sorted keys), so a save that
-- changes nothing writes nothing and makes no undo step
function H.grid_string()
  local data = { v = 1, quantize = L.quantize, headers = L.headers, scenes = L.scenes, def = L.def,
    sync = L.sync, lanes = {} }
  for tguid, lane in pairs(L.lanes) do
    if lane.lane_guid or next(lane.slots) or next(lane.envs or {}) then
    local slots = {}
    for row, slot in pairs(lane.slots) do
      local kept = {}
      for _, k in ipairs(SLOT_KEYS) do kept[k] = slot[k] end
      slots[row] = kept
    end
    local envs = {}
    for name, ez in pairs(lane.envs or {}) do
      local es = {}
      for row, clip in pairs(ez.slots) do es[row] = { name = clip.name, points = clip.points, qn = clip.qn, color = clip.color } end
      if next(es) then envs[name] = { slots = es } end
    end
    data.lanes[tguid] = { lane_guid = lane.lane_guid, slots = slots, envs = envs }
    end
  end
  return H.ser(data)
end

function H.save(desc)
  local str = H.grid_string()
  if str == L.saved_str then return end
  L.saved_str, L.seen_str = str, str
  local master = r.GetMasterTrack(0)
  if (L.in_block or 0) > 0 then
    r.GetSetMediaTrackInfo_String(master, K.grid, str, true)
  else
    r.Undo_BeginBlock()
    r.GetSetMediaTrackInfo_String(master, K.grid, str, true)
    r.Undo_EndBlock("Launcher: " .. (desc or "settings"), -1)
  end
end

-- After an undo / redo the grid on the master can differ from what the launcher holds: take
-- the stored slots, scenes and settings, and keep what is running (voices, handovers, mutes).
function H.apply_grid(str)
  local data = H.deser(str)
  if not data then return end
  L.seen_str = str
  L.quantize = tonumber(data.quantize) or L.quantize
  if data.headers ~= nil then L.headers = data.headers and true or false end
  if data.sync ~= nil then L.sync = data.sync and true or false end
  for k, v in pairs(data.def or {}) do L.def[k] = v end
  L.scenes = {}
  for i, sc in pairs(data.scenes or {}) do
    if type(i) == "number" then L.scenes[i] = { name = sc.name, color = sc.color } end
  end
  for i = 1, K.scenes do if not L.scenes[i] then L.scenes[i] = {} end end
  local seen = {}
  for tguid, stored in pairs(data.lanes or {}) do
    seen[tguid] = true
    local lane = L.lanes[tguid] or H.new_lane(tguid)
    L.lanes[tguid] = lane
    lane.lane_guid = stored.lane_guid
    lane.slots = {}
    for row, slot in pairs(stored.slots or {}) do
      if type(row) == "number" and slot.guid then
        local kept = {}
        for _, k in ipairs(SLOT_KEYS) do kept[k] = slot[k] end
        kept.name = kept.name or "Clip"
        lane.slots[row] = kept
      end
    end
    for _, ez in pairs(lane.envs or {}) do ez.slots = {} end
    for name, es in pairs(stored.envs or {}) do
      local ez = H.env_lane(lane, name, true)
      for row, clip in pairs(es.slots or {}) do
        if type(row) == "number" and type(clip.points) == "table" and tonumber(clip.qn) then ez.slots[row] = clip end
      end
    end
  end
  for tguid, lane in pairs(L.lanes) do
    if not seen[tguid] then
      lane.slots = {}
      for _, ez in pairs(lane.envs or {}) do ez.slots = {} end
    end
  end
  L.sel = nil
  L.saved_str = H.grid_string()
  L.status = "Launcher follows the undo"
end

function H.new_lane(tguid)
  return { track_guid = tguid, slots = {}, owner = "arrangement", retired = {}, envs = {} }
end

function H.lane_of(track, create)
  local tguid = r.GetTrackGUID(track)
  local lane = L.lanes[tguid]
  if not lane and create then
    lane = H.new_lane(tguid)
    L.lanes[tguid] = lane
  end
  return lane
end

function H.load()
  L.lanes, L.scenes, L.peaks, L.notes, L.sel = {}, {}, {}, {}, nil
  E.repair_restore()
  local _, s = r.GetSetMediaTrackInfo_String(r.GetMasterTrack(0), K.grid, "", false)
  local from_master = s and s ~= ""
  L.seen_str = from_master and s or nil
  if not from_master then _, s = r.GetProjExtState(0, K.ext, "grid") end
  L.saved_str = nil
  local data = H.deser(s)
  local library = {}
  if data then
    L.quantize = tonumber(data.quantize) or 1
    if data.headers ~= nil then L.headers = data.headers and true or false end
    for k, v in pairs(data.def or {}) do L.def[k] = v end
    if data.sync ~= nil then L.sync = data.sync and true or false end
    for i, sc in pairs(data.scenes or {}) do
      if type(i) == "number" then L.scenes[i] = { name = sc.name, color = sc.color } end
    end
    for tguid, stored in pairs(data.lanes or {}) do
      local lane = H.new_lane(tguid)
      lane.lane_guid = stored.lane_guid
      for name, es in pairs(stored.envs or {}) do
        local ez = H.env_lane(lane, name, true)
        for row, clip in pairs(es.slots or {}) do
          if type(row) == "number" and type(clip.points) == "table" and tonumber(clip.qn) then ez.slots[row] = clip end
        end
      end
      for row, slot in pairs(stored.slots or {}) do
        if type(row) == "number" and slot.guid then
          local kept = {}
          for _, k in ipairs(SLOT_KEYS) do kept[k] = slot[k] end
          kept.name = kept.name or "Clip"
          kept.color = slot.color          -- an older grid's colour: E.sync_colours moves it onto the item once
          lane.slots[row] = kept
          library[slot.guid] = true
        end
      end
      L.lanes[tguid] = lane
    end
  end
  for i = 1, K.scenes do
    if not L.scenes[i] then L.scenes[i] = {} end
  end
  -- voices left behind by a crash or a forced quit: anything on our hidden tracks that is
  -- not a clip of the library goes; the library itself stays muted
  r.PreventUIRefresh(1)
  E.ai_sweep()
  for t = 0, r.CountTracks(0) - 1 do
    local track = r.GetTrack(0, t)
    if H.is_lane_track(track) then
      for i = 0, r.TrackFX_GetCount(track) - 1 do
        local _, fxname = r.TrackFX_GetFXName(track, i, "")
        if fxname and fxname:find(GATE.desc, 1, true) then
          r.TrackFX_SetParam(track, i, 1, -1)
          r.TrackFX_SetParam(track, i, 0, 1)
        end
      end
      for i = r.CountTrackMediaItems(track) - 1, 0, -1 do
        local item = r.GetTrackMediaItem(track, i)
        if library[H.item_guid(item)] then
          r.SetMediaItemInfo_Value(item, "B_MUTE", 1)
        else
          r.DeleteTrackMediaItem(track, item)
        end
      end
    elseif r.GetSetMediaTrackInfo_String(track, K.other_tag, "", false) then
      local _, v = r.GetSetMediaTrackInfo_String(track, K.other_tag, "", false)
      if v == "1" then L.other = true end
    end
  end
  r.PreventUIRefresh(-1)
  L.loaded = true
  -- from the master: its normal form, so opening writes nothing; an older project's grid
  -- (project ext state) is moved onto the master at the first save
  if from_master then L.saved_str = H.grid_string() end
  L.track_count = r.CountTracks(0)
end

function H.scene_name(row)
  local sc = L.scenes[row]
  return (sc and sc.name and sc.name ~= "") and sc.name or ("Scene " .. row)
end

-- every slot from row `from` up moves by delta (a scene inserted or removed)
function H.shift_rows(from, delta)
  for _, lane in pairs(L.lanes) do
    local moved = {}
    for row, slot in pairs(lane.slots) do
      if row >= from then moved[row + delta] = slot else moved[row] = slot end
    end
    lane.slots = moved
    for _, v in ipairs({ lane.current, lane.pending }) do
      if v and v.row and v.row >= from then v.row = v.row + delta end
    end
  end
  if L.sel and L.sel.row >= from then L.sel = nil end
end

----------------------------------------------------------------------------------------------
-- engine: timing (TK Project Clips' grid, with a per-call launch grid)
----------------------------------------------------------------------------------------------

function E.schedule_pos()
  if (r.GetPlayState() & 1) ~= 1 then return nil end
  return r.GetPlayPosition2 and r.GetPlayPosition2() or r.GetPlayPosition()
end
function E.heard_pos()
  if (r.GetPlayState() & 1) ~= 1 then return nil end
  return r.GetPlayPosition()
end
function E.lead() return math.max(K.min_lead, K.lead) end

function E.measure_offset()
  if L.measure_offset then return L.measure_offset end
  L.measure_offset = -1
  local measure, from_qn = r.TimeMap_QNToMeasures(0, 8)
  if measure and from_qn then
    for _, guess in ipairs({ -1, 0 }) do
      local _, qn = r.TimeMap_GetMeasureInfo(0, measure + guess)
      if qn and math.abs(qn - from_qn) < 0.001 then L.measure_offset = guess break end
    end
  end
  return L.measure_offset
end
function E.measure_pos(time)
  local qn = r.TimeMap2_timeToQN(0, time)
  local measure, from_qn, to_qn = r.TimeMap_QNToMeasures(0, qn)
  if not (measure and from_qn and to_qn) or to_qn <= from_qn then return nil end
  return measure + E.measure_offset() + (qn - from_qn) / (to_qn - from_qn)
end
function E.measure_time(pos)
  local whole = math.floor(pos)
  local _, from_qn, to_qn = r.TimeMap_GetMeasureInfo(0, whole)
  if not (from_qn and to_qn) or to_qn <= from_qn then return nil end
  return r.TimeMap2_QNToTime(0, from_qn + (pos - whole) * (to_qn - from_qn))
end
function E.grid_index(time, q)
  if q > 0 then
    local pos = E.measure_pos(time)
    if pos then return pos / q end
    q = -4
  end
  if q == 0 then return nil end
  return r.TimeMap2_timeToQN(0, time) / -q
end
function E.grid_time(time, line, q)
  if q > 0 then
    local t = E.measure_time(line * q)
    if t then return t end
    q = -4
  end
  return r.TimeMap2_QNToTime(0, line * -q)
end
-- the next line of the launch grid that can still be written in time
function E.boundary_after(from, allow_now, q)
  q = q or L.quantize
  local index = E.grid_index(from, q)
  if not index then return allow_now and from or (from + E.lead()) end
  local line = math.floor(index)
  if not allow_now then line = line + 1 end
  local time = E.grid_time(from, line, q)
  if allow_now then
    if time < from - 0.001 then time = E.grid_time(from, line + 1, q) end
    return time
  end
  local guard = 0
  while time - from < E.lead() and guard < 64 do
    line = line + 1
    time = E.grid_time(from, line, q)
    guard = guard + 1
  end
  return time
end

function E.loop_region()
  if r.GetSetRepeat(-1) ~= 1 then return nil end
  local s, e = r.GetSet_LoopTimeRange(false, true, 0, 0, false)
  if not s or not e or e - s < 0.25 then return nil end
  return s, e
end

-- when a launch lands: the time, whether the transport has to be started, and whether it
-- has to wait for the loop to come round
function E.launch_time(q)
  local now = E.schedule_pos()
  if not now then return E.boundary_after(r.GetCursorPosition(), true, q), true, false end
  local time = E.boundary_after(now, false, q)
  local ls, le = E.loop_region()
  if ls and now >= ls and now < le and time >= le - 0.01 then return ls, false, true end
  return time, false, false
end

function E.roll_transport(at)
  if (r.GetPlayState() & 1) == 1 then return end
  r.SetEditCurPos(at, false, true)
  r.OnPlayButton()
  r.SetEditCurPos(at, false, true)
  L.roll_guard = r.time_precise() + 1.5
end

----------------------------------------------------------------------------------------------
-- engine: items and the hidden lane tracks
----------------------------------------------------------------------------------------------

-- a chunk copy keeps take FX, stretch markers, pitch and rate; fresh GUIDs make it its own
function E.copy_item(item, track, position)
  if not H.valid_item(item) or not H.valid_track(track) then return nil end
  local ok, chunk = r.GetItemStateChunk(item, "", false)
  if not ok or not chunk then return nil end
  chunk = chunk:gsub("(\n%s*I?GUID )%b{}", function(prefix) return prefix .. r.genGuid("") end)
  local copy = r.AddMediaItemToTrack(track)
  if not copy then return nil end
  r.SetItemStateChunk(copy, chunk, false)
  r.SetMediaItemInfo_Value(copy, "D_POSITION", position)
  r.SetMediaItemInfo_Value(copy, "C_LOCK", 0)
  r.SetMediaItemSelected(copy, false)
  return copy
end
function E.delete_item(item)
  if not H.valid_item(item) then return end
  local track = r.GetMediaItemTrack(item)
  if H.valid_track(track) then r.DeleteTrackMediaItem(track, item) end
end
function E.trim_to(item, time)
  if not H.valid_item(item) then return false end
  local pos = r.GetMediaItemInfo_Value(item, "D_POSITION")
  local len = time - pos
  if len <= 0.0001 then return false end
  local fade = math.max(K.fade, r.GetMediaItemInfo_Value(item, "D_FADEOUTLEN"))
  r.SetMediaItemInfo_Value(item, "D_LENGTH", len)
  r.SetMediaItemInfo_Value(item, "D_FADEOUTLEN", math.min(fade, len))
  r.SetMediaItemInfo_Value(item, "D_FADEOUTLEN_AUTO", -1)
  r.UpdateItemInProject(item)
  return true
end
function E.item_end(item)
  if not H.valid_item(item) then return nil end
  return r.GetMediaItemInfo_Value(item, "D_POSITION") + r.GetMediaItemInfo_Value(item, "D_LENGTH")
end

function E.lane_track(lane) return H.track(lane.lane_guid) end

function E.ensure_lane_track(lane)
  L.lay = nil                        -- the track layout changes: read it again
  local track = E.lane_track(lane)
  if track then return track end
  local target = H.track(lane.track_guid)
  if not target then return nil end
  local shown = H.lanes_shown()          -- read before the new one exists (it starts visible)
  local index = r.CountTracks(0)
  r.InsertTrackAtIndex(index, false)
  track = r.GetTrack(0, index)
  if not track then return nil end
  r.GetSetMediaTrackInfo_String(track, "P_NAME", "Bit Launcher: " .. H.track_name(target), true)
  r.GetSetMediaTrackInfo_String(track, K.tag, "1", true)
  r.SetMediaTrackInfo_Value(track, "B_SHOWINTCP", shown and 1 or 0)
  r.SetMediaTrackInfo_Value(track, "B_SHOWINMIXER", 0)
  r.SetMediaTrackInfo_Value(track, "B_MAINSEND", 0)
  -- no media buffering: a voice written ~0.3 s ahead is read in full (Project Clips, measured)
  local flags = math.floor(r.GetMediaTrackInfo_Value(track, "I_PERFFLAGS"))
  r.SetMediaTrackInfo_Value(track, "I_PERFFLAGS", flags | 1)
  local send = r.CreateTrackSend(track, target)
  if send and send >= 0 then
    r.SetTrackSendInfo_Value(track, 0, send, "I_MIDIFLAGS", 0)
    r.SetTrackSendInfo_Value(track, 0, send, "I_SRCCHAN", 0)
  end
  lane.lane_guid = r.GetTrackGUID(track)
  r.TrackList_AdjustWindows(false)
  return track
end

-- the hidden tracks stay at the end of the project, so a new track never lands among them
function E.tidy()
  L.lay = nil                        -- the track layout changes: read it again
  for _, lane in pairs(L.lanes) do
    if lane.current or lane.pending then return end
  end
  L.tidy = false
  local seen, needed = false, false
  for i = 0, r.CountTracks(0) - 1 do
    if H.is_lane_track(r.GetTrack(0, i)) then seen = true elseif seen then needed = true break end
  end
  if not needed then return end
  local selected, lanes = {}, {}
  for i = 0, r.CountTracks(0) - 1 do
    local track = r.GetTrack(0, i)
    if r.IsTrackSelected(track) then selected[#selected + 1] = track end
    if H.is_lane_track(track) then lanes[#lanes + 1] = track end
  end
  r.PreventUIRefresh(1)
  r.Main_OnCommand(40297, 0)                      -- unselect all tracks
  for _, track in ipairs(lanes) do
    r.SetTrackSelected(track, true)
    r.ReorderSelectedTracks(r.CountTracks(0), 0)
    r.SetTrackSelected(track, false)
  end
  for _, track in ipairs(selected) do
    if H.valid_track(track) then r.SetTrackSelected(track, true) end
  end
  r.PreventUIRefresh(-1)
  r.TrackList_AdjustWindows(false)
  L.track_count = r.CountTracks(0)
end

-- MIDI has no section source: glue renders the shown part (an action needs a visible track)
function E.trim_midi(item)
  local track = r.GetMediaItemTrack(item)
  local selected = {}
  for i = 0, r.CountSelectedMediaItems(0) - 1 do selected[#selected + 1] = r.GetSelectedMediaItem(0, i) end
  local length = r.GetMediaItemInfo_Value(item, "D_LENGTH")
  r.SetMediaItemInfo_Value(item, "B_LOOPSRC", 0)
  r.SetMediaItemInfo_Value(item, "B_MUTE", 0)
  local was_shown = r.GetMediaTrackInfo_Value(track, "B_SHOWINTCP")
  r.SetMediaTrackInfo_Value(track, "B_SHOWINTCP", 1)
  r.TrackList_AdjustWindows(false)
  local clear = 0                                  -- clips are stacked at 0: glue would take them all
  for i = 0, r.CountTrackMediaItems(track) - 1 do
    clear = math.max(clear, E.item_end(r.GetTrackMediaItem(track, i)) or 0)
  end
  r.SetMediaItemInfo_Value(item, "D_POSITION", clear + 10)
  H.unselect_items()
  r.SetMediaItemSelected(item, true)
  r.Main_OnCommand(40362, 0)                       -- glue items
  local glued = r.GetSelectedMediaItem(0, 0)
  if not H.valid_item(glued) then glued = item end
  H.unselect_items()
  for _, it in ipairs(selected) do if H.valid_item(it) then r.SetMediaItemSelected(it, true) end end
  r.SetMediaTrackInfo_Value(track, "B_SHOWINTCP", was_shown)
  r.TrackList_AdjustWindows(false)
  if H.valid_item(glued) then
    r.SetMediaItemInfo_Value(glued, "D_POSITION", 0)
    r.SetMediaItemInfo_Value(glued, "D_LENGTH", length)
  end
  return glued
end

-- an audio item trimmed shorter than its file loops the whole file; a section source makes
-- the shown window the whole clip
function E.apply_section(item)
  if not r.CF_PCM_Source_SetSectionInfo then return end
  local take = r.GetActiveTake(item)
  if not take or r.TakeIsMIDI(take) then return end
  local source = r.GetMediaItemTake_Source(take)
  local slen, is_qn = r.GetMediaSourceLength(source)
  if is_qn or not slen or slen <= 0 then return end
  local rate = r.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE")
  if rate <= 0 then rate = 1 end
  local offset = r.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS")
  local length = r.GetMediaItemInfo_Value(item, "D_LENGTH") * rate
  if offset < 0.0001 and length >= slen - 0.0001 then return end
  local kind = r.GetMediaSourceType(source, "")
  if kind == "SECTION" or kind == "" then return end
  local path = r.GetMediaSourceFileName(source, "")
  if not path or path == "" then return end
  local copy = r.PCM_Source_CreateFromFile(path)
  local section = copy and r.PCM_Source_CreateFromType("SECTION")
  if not section then return end
  if pcall(r.CF_PCM_Source_SetSectionInfo, section, copy, offset, length, false) then
    r.SetMediaItemTake_Source(take, section)
    r.SetMediaItemTakeInfo_Value(take, "D_STARTOFFS", 0)
  end
end

-- the library item becomes a clip: muted, looping, no fades of its own
function E.finish_library(lane, row, library, name, color)
  r.SetMediaItemInfo_Value(library, "B_MUTE", 1)
  r.SetMediaItemInfo_Value(library, "B_LOOPSRC", 1)
  r.SetMediaItemInfo_Value(library, "D_FADEINLEN", 0)
  r.SetMediaItemInfo_Value(library, "D_FADEINLEN_AUTO", -1)
  local take = r.GetActiveTake(library)
  lane.slots[row] = {
    guid = H.item_guid(library), name = name or "Clip", color = color,
    midi = (take and r.TakeIsMIDI(take)) and true or nil,
  }
  if row > #L.scenes then
    for i = #L.scenes + 1, row do L.scenes[i] = {} end
  end
end

function E.assign_item(lane, row, source)
  local lane_track = E.ensure_lane_track(lane)
  if not lane_track or not H.valid_item(source) then return false end
  E.clear_slot(lane, row)
  local library = E.copy_item(source, lane_track, 0)
  if not library then return false end
  local length = r.GetMediaItemInfo_Value(library, "D_LENGTH")
  local take = r.GetActiveTake(library)
  if take and r.TakeIsMIDI(take) then library = E.trim_midi(library) else E.apply_section(library) end
  if not H.valid_item(library) then return false end
  r.SetMediaItemInfo_Value(library, "D_LENGTH", length)
  local stake = r.GetActiveTake(source)
  local name = stake and select(2, r.GetSetMediaItemTakeInfo_String(stake, "P_NAME", "", false)) or ""
  local color = H.rgba(r.GetMediaItemInfo_Value(source, "I_CUSTOMCOLOR"))
    or (stake and H.rgba(r.GetMediaItemTakeInfo_Value(stake, "I_CUSTOMCOLOR")))
  E.finish_library(lane, row, library, name ~= "" and name:gsub("%.%w+$", "") or "Clip", color)
  return true
end

----------------------------------------------------------------------------------------------
-- tempo: an audio file plays at the project tempo, as Bitwig stretches a loop to the song
-- (copied from TK Project Clips: metadata, then the file name, then a guess at a loop of a
-- whole number of beats; one-shots are left alone)
----------------------------------------------------------------------------------------------

function H.guess_bpm(source)
  local project = r.Master_GetTempo()
  local length, is_qn = r.GetMediaSourceLength(source)
  if not length or is_qn or length < 1.0 or length > 20.0 or project <= 0 then return nil end
  local best, dist
  for _, beats in ipairs({ 2, 4, 8, 16, 32, 64 }) do
    local bpm = beats * 60 / length
    if bpm >= 50 and bpm <= 220 then
      local d = math.abs(math.log(bpm / project))
      if not dist or d < dist then best, dist = bpm, d end
    end
  end
  if not best or project / best < 0.5 or project / best > 2 then return nil end
  return best
end

-- the file's own tempo, and whether it was guessed
function H.file_bpm(source, path)
  local flagged, one_shot = r.GetMediaFileMetadata(source, "ACID:oneshot")
  if flagged and flagged ~= 0 and one_shot and one_shot ~= "" and one_shot ~= "0" then return nil end
  for _, key in ipairs({ "ACID:tempo", "ID3:TBPM", "VORBIS:BPM", "VORBIS:TEMPO", "XMP:dm/tempo" }) do
    local ok, value = r.GetMediaFileMetadata(source, key)
    if ok and ok ~= 0 and value and value ~= "" then
      local bpm = tonumber((tostring(value):gsub(",", "."):match("[%d%.]+")))
      if bpm and bpm > 0 then return bpm end
    end
  end
  local counted, beats = r.GetMediaFileMetadata(source, "ACID:beats")
  beats = counted and counted ~= 0 and tonumber((tostring(beats or ""):match("[%d%.]+"))) or nil
  if beats and beats > 0 then
    local length, is_qn = r.GetMediaSourceLength(source)
    if length and length > 0 and not is_qn then
      local bpm = beats * 60 / length
      if bpm >= 20 and bpm <= 400 then return bpm end
    end
  end
  local name = ((path or ""):match("([^/\\]+)$") or ""):lower()
  local bpm = tonumber(name:match("(%d+%.?%d*)%s*bpm")) or tonumber(name:match("bpm[%s_%-]*(%d+%.?%d*)"))
  if bpm and bpm >= 40 and bpm <= 300 then return bpm end
  local guessed = H.guess_bpm(source)
  if guessed then return guessed, true end
end

-- the clip's library item at the project tempo now (pitch kept); with sync off, its own speed
function E.apply_tempo(slot)
  local item = H.item(slot.guid)
  local take = item and r.GetActiveTake(item)
  if not take or not slot.bpm then return end
  local rate = slot.nosync and 1 or r.Master_GetTempo() / slot.bpm
  if rate < 0.05 or rate > 20 then return end
  local source = r.GetMediaItemTake_Source(take)
  local slen = r.GetMediaSourceLength(source)
  r.SetMediaItemTakeInfo_Value(take, "D_PLAYRATE", rate)
  r.SetMediaItemTakeInfo_Value(take, "B_PPITCH", 1)
  if slen and slen > 0 then r.SetMediaItemInfo_Value(item, "D_LENGTH", slen / rate) end
end

-- the project tempo changed: every synced clip follows (clips already playing keep their
-- speed until they are launched again)
function E.tempo_watch()
  local tempo = r.Master_GetTempo()
  if tempo == L.tempo then return end
  local first = L.tempo == nil
  L.tempo = tempo
  if first then return end
  for _, lane in pairs(L.lanes) do
    for _, slot in pairs(lane.slots) do
      if slot.bpm and not slot.nosync then E.apply_tempo(slot) end
    end
  end
end

-- a file (TK_DRAG or the file dialog): an item built from the source, never InsertMedia,
-- which would move the edit cursor and the track selection under a playing user
function E.assign_path(lane, row, path)
  local lane_track = E.ensure_lane_track(lane)
  if not lane_track then return false end
  local source = r.PCM_Source_CreateFromFile(path)
  if not source then return false end
  local length, is_qn = r.GetMediaSourceLength(source)
  if is_qn then length = r.TimeMap2_QNToTime(0, length) end
  if not length or length <= 0 then return false end
  E.clear_slot(lane, row)
  local item = r.AddMediaItemToTrack(lane_track)
  local take = r.AddTakeToMediaItem(item)
  r.SetMediaItemTake_Source(take, source)
  r.SetMediaItemInfo_Value(item, "D_POSITION", 0)
  r.SetMediaItemInfo_Value(item, "D_LENGTH", length)
  local name = path:match("([^/\\]+)$") or "Clip"
  r.GetSetMediaItemTakeInfo_String(take, "P_NAME", name, true)
  E.finish_library(lane, row, item, (name:gsub("%.%w+$", "")), nil)
  -- audio follows the project tempo (MIDI already does)
  if L.sync ~= false and not lane.slots[row].midi then
    local bpm, guessed = H.file_bpm(source, path)
    if bpm then
      lane.slots[row].bpm, lane.slots[row].bpm_guess = bpm, guessed or nil
      E.apply_tempo(lane.slots[row])
    end
  end
  return true
end

function E.slot_lengths(slot)
  local item = H.item(slot.guid)
  local take = item and r.GetActiveTake(item)
  if not take then return 0, 0 end
  local length = r.GetMediaItemInfo_Value(item, "D_LENGTH")
  local period = length
  local source = r.GetMediaItemTake_Source(take)
  local slen, is_qn = r.GetMediaSourceLength(source)
  if slen and slen > 0 then
    if is_qn then slen = r.TimeMap2_QNToTime(0, slen) end
    local rate = r.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE")
    slen = slen / (rate > 0 and rate or 1)
    if slen < length - 0.0001 then period = slen end
  end
  return length, period
end

----------------------------------------------------------------------------------------------
-- engine: who plays a track (arranger or launcher) and the crash mirror
----------------------------------------------------------------------------------------------

function E.save_restore()
  local merged, order = {}, {}
  local _, s = r.GetProjExtState(0, K.ext, "restore")
  for _, e in ipairs(H.deser(s) or {}) do
    if e.guid and merged[e.guid] == nil then merged[e.guid] = e.mute order[#order + 1] = e.guid end
  end
  for _, lane in pairs(L.lanes) do
    for _, e in ipairs(lane.origin or {}) do
      if merged[e.guid] == nil then order[#order + 1] = e.guid end
      merged[e.guid] = e.mute
    end
  end
  for _, guid in ipairs(L.restored or {}) do merged[guid] = nil end
  L.restored = {}
  local list = {}
  for _, guid in ipairs(order) do
    if merged[guid] ~= nil then list[#list + 1] = { guid = guid, mute = merged[guid] } end
  end
  r.SetProjExtState(0, K.ext, "restore", #list > 0 and H.ser(list) or "")
end

function E.repair_restore()
  local _, s = r.GetProjExtState(0, K.ext, "restore")
  for _, e in ipairs(H.deser(s) or {}) do
    local item = H.item(e.guid)
    if item then r.SetMediaItemInfo_Value(item, "B_MUTE", tonumber(e.mute) or 0) end
  end
  r.SetProjExtState(0, K.ext, "restore", "")
  L.restored = {}
end

function E.restored(e)
  L.restored = L.restored or {}
  L.restored[#L.restored + 1] = e.guid
  return e.mute
end

function E.straddles(item, time)
  local pos = r.GetMediaItemInfo_Value(item, "D_POSITION")
  return pos < time and pos + r.GetMediaItemInfo_Value(item, "D_LENGTH") > time
end

function E.undo_pre_apply(lane)
  local sw = lane.switch
  if not sw then return end
  local muted_now = lane.owner == "launcher"
  for _, e in ipairs(lane.origin or {}) do
    local item = H.item(e.guid)
    if item and not E.straddles(item, sw.at) then
      r.SetMediaItemInfo_Value(item, "B_MUTE", muted_now and 1 or e.mute)
    end
  end
  lane.switch = nil
end

-- the handover lands on the same line as the clip: items after it are switched now (exact),
-- an item the line falls inside is switched when the play cursor gets there
function E.schedule_owner(lane, to, time)
  local target = H.track(lane.track_guid)
  if not target then return end
  if lane.switch then E.undo_pre_apply(lane) end
  if lane.owner == to then return end
  if to == "launcher" and not lane.origin then
    lane.origin = {}
    for i = 0, r.CountTrackMediaItems(target) - 1 do
      local item = r.GetTrackMediaItem(target, i)
      -- an item the user muted stays out of it, so giving the track back cannot unmute it
      if r.GetMediaItemInfo_Value(item, "B_MUTE") < 0.5 then
        lane.origin[#lane.origin + 1] = { guid = H.item_guid(item), mute = 0 }
      end
    end
    E.save_restore()
  end
  local pending = {}
  for _, e in ipairs(lane.origin or {}) do
    local item = H.item(e.guid)
    if item then
      local value = to == "launcher" and 1 or E.restored(e)
      if E.straddles(item, time) then
        pending[#pending + 1] = { guid = e.guid, value = value }
      else
        r.SetMediaItemInfo_Value(item, "B_MUTE", value)
      end
    end
  end
  lane.switch = { to = to, at = time, pending = pending }
end

function E.apply_switch(lane)
  local sw = lane.switch
  if not sw then return end
  for _, e in ipairs(sw.pending) do
    local item = H.item(e.guid)
    if item then r.SetMediaItemInfo_Value(item, "B_MUTE", e.value) end
  end
  lane.owner = sw.to
  lane.switch = nil
  if lane.owner == "arrangement" then
    lane.origin = nil
    E.save_restore()
  end
end

function E.release_now(lane)
  lane.switch = nil
  if lane.origin then
    for _, e in ipairs(lane.origin) do
      local item = H.item(e.guid)
      if item then r.SetMediaItemInfo_Value(item, "B_MUTE", E.restored(e)) end
    end
    lane.origin = nil
    E.save_restore()
  end
  lane.owner = "arrangement"
end

-- does the launcher play this track (now, or from a handover already scheduled)?
function E.launcher_owns(lane)
  if not lane then return false end
  if lane.switch then return lane.switch.to == "launcher" end
  return lane.owner == "launcher"
end

----------------------------------------------------------------------------------------------
-- engine: voices
----------------------------------------------------------------------------------------------

function E.kill_voice(v)
  if not v then return end
  if v.started then E.perf_capture(v) end
  E.delete_item(v.item)
  E.delete_item(v.wrap)
  v.item, v.wrap = nil, nil
end

function E.voice_end(v)
  local a, b = E.item_end(v.item), E.item_end(v.wrap)
  if a and b then return math.max(a, b) end
  return a or b
end

-- end everything the outgoing voice holds at `time`; returns what to put back on a cancel
function E.close_voice_at(v, time)
  local restore = {}
  if not v then return restore end
  for _, field in ipairs({ "item", "wrap" }) do
    local item = v[field]
    if H.valid_item(item) then
      local pos = r.GetMediaItemInfo_Value(item, "D_POSITION")
      local len = r.GetMediaItemInfo_Value(item, "D_LENGTH")
      if pos >= time then
        E.delete_item(item)
        v[field] = nil
      elseif pos + len > time then
        restore[#restore + 1] = { item = item, length = len, fade = r.GetMediaItemInfo_Value(item, "D_FADEOUTLEN") }
        E.trim_to(item, time)
        v.closing = true
      end
    end
  end
  return restore
end

function E.cancel_pending(lane)
  local p = lane.pending
  if not p then return end
  E.kill_voice(p)
  for _, e in ipairs(p.restore or {}) do
    if H.valid_item(e.item) then
      r.SetMediaItemInfo_Value(e.item, "D_LENGTH", e.length)
      r.SetMediaItemInfo_Value(e.item, "D_FADEOUTLEN", e.fade)
    end
  end
  if lane.current then lane.current.closing = nil end
  lane.pending = nil
  lane.stop_at = nil
end

-- where in the clip a launch starts: 0, or Bitwig's legato (the playing clip's position, or
-- the project's position counted in clip lengths)
function E.legato_offset(lane, mode, time, loop_len)
  if not mode or mode == "start" or loop_len <= 0 then return 0 end
  local cur = lane.current
  if mode ~= "legato_p" and cur and cur.started and not lane.stop_at and cur.length and cur.length > 0 then
    return ((time - cur.at + (cur.offset or 0)) % cur.length) % loop_len
  end
  if mode == "legato_c" then return 0 end
  local qn = r.TimeMap2_timeToQN(0, time)
  local len_qn = r.TimeMap2_timeToQN(0, time + loop_len) - qn
  if len_qn <= 0 then return 0 end
  return math.max(0, time - r.TimeMap2_QNToTime(0, qn - qn % len_qn))
end

function E.commit(lane, row, time, mode)
  local slot = lane.slots[row]
  local lane_track = E.lane_track(lane)
  local library = slot and H.item(slot.guid)
  if not lane_track or not library then return false end
  E.cancel_pending(lane)
  local _, loop_len = E.slot_lengths(slot)
  local offset = E.legato_offset(lane, mode, time, loop_len)
  -- "Return" goes back to the clip that played before this one, or to the arrangement
  local cur = lane.current
  if not (cur and cur.row == row and not lane.stop_at) then
    if cur and cur.started and not lane.stop_at then lane.prev = cur.row
    elseif not E.launcher_owns(lane) then lane.prev = "arrange"
    else lane.prev = nil end
  end
  local restore = E.close_voice_at(lane.current, time)   -- never overlap: no auto crossfade
  local voice = E.copy_item(library, lane_track, time)
  if not voice then return false end
  if offset > 0 then
    local take = r.GetActiveTake(voice)
    if take then
      local rate = r.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE")
      r.SetMediaItemTakeInfo_Value(take, "D_STARTOFFS",
        r.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS") + offset * (rate > 0 and rate or 1))
    end
  end
  r.SetMediaItemInfo_Value(voice, "B_MUTE", 0)
  r.SetMediaItemInfo_Value(voice, "B_LOOPSRC", 1)
  r.SetMediaItemInfo_Value(voice, "D_LENGTH", K.voice_length)
  r.SetMediaItemInfo_Value(voice, "D_FADEINLEN", 0)
  r.SetMediaItemInfo_Value(voice, "D_FADEOUTLEN", K.fade)
  r.SetMediaItemInfo_Value(voice, "D_FADEINLEN_AUTO", -1)
  r.SetMediaItemInfo_Value(voice, "D_FADEOUTLEN_AUTO", -1)
  r.UpdateItemInProject(voice)
  lane.pending = { item = voice, row = row, at = time, length = loop_len, offset = offset, slot_guid = slot.guid,
    restore = restore, track_guid = lane.track_guid }
  E.env_with(lane, row, time)
  lane.stop_at, lane.run = nil, nil
  E.schedule_owner(lane, "launcher", time)
  E.gate_arm(lane, time)
  return true
end

----------------------------------------------------------------------------------------------
-- engine: the gate (an immediate stop, for release actions)
----------------------------------------------------------------------------------------------

function E.gate(lane, create)
  local track = E.lane_track(lane)
  if not track then return nil end
  for i = 0, r.TrackFX_GetCount(track) - 1 do
    local _, name = r.TrackFX_GetFXName(track, i, "")
    if name and name:find(GATE.desc, 1, true) then return i, track end
  end
  if not create then return nil end
  local dir = r.GetResourcePath() .. "/Effects/TK Theme Bit"
  local path = dir .. "/" .. GATE.file
  local f = io.open(path, "rb")
  local cur = f and f:read("*a")
  if f then f:close() end
  if cur ~= GATE.src then
    r.RecursiveCreateDirectory(dir, 0)
    f = io.open(path, "wb")
    if not f then return nil end
    f:write(GATE.src)
    f:close()
  end
  local i = r.TrackFX_AddByName(track, "JS:TK Theme Bit/" .. GATE.file, false, -1)
  if i < 0 then i = r.TrackFX_AddByName(track, "JS:" .. GATE.desc, false, -1) end
  if i < 0 then return nil end
  -- no anticipative FX on this track, or the shut would be heard a render-ahead late
  local flags = math.floor(r.GetMediaTrackInfo_Value(track, "I_PERFFLAGS"))
  r.SetMediaTrackInfo_Value(track, "I_PERFFLAGS", flags | 3)
  return i, track
end

function E.gate_shut(lane)
  local i, track = E.gate(lane, true)
  if not i then return false end
  r.TrackFX_SetParam(track, i, 1, -1)
  r.TrackFX_SetParam(track, i, 0, 0)
  lane.gate_shut, lane.gate_open_at = true, nil     -- an earlier planned opening no longer holds
  return true
end

-- a shut gate opens by itself when the play position reaches the next clip
function E.gate_arm(lane, time)
  if not lane.gate_shut then return end
  local i, track = E.gate(lane, false)
  if i then r.TrackFX_SetParam(track, i, 1, time) end
  lane.gate_open_at = time        -- the JSFX opens itself there; E.update notes it (gate_shut off)
end

function E.gate_open(lane)
  local i, track = E.gate(lane, false)
  if i then
    r.TrackFX_SetParam(track, i, 1, -1)
    r.TrackFX_SetParam(track, i, 0, 1)
  end
  lane.gate_shut = nil
end

-- Does any clip on this track still ask for an immediate stop (a Main or ALT release of Stop
-- or Return)? The project's defaults count: Bitwig's ALT release is Return.
function E.lane_wants_gate(lane)
  for _, slot in pairs(lane.slots) do
    for _, alt in ipairs({ false, true }) do
      local rel = E.setting(slot, alt, "rel")
      if rel == "stop" or rel == "return" then return true end
    end
  end
  return false
end

-- A gate nothing asks for any more leaves its track, and so does the track's "no
-- anticipative FX" it came with (TK Project Clips does the same). Never while it is shut,
-- never under a clip being held down.
function E.sync_gates(lane)
  if lane.gate_shut or (L.held and L.held.lane == lane) then return end
  local i, track = E.gate(lane, false)
  if not i or E.lane_wants_gate(lane) then return end
  r.TrackFX_Delete(track, i)
  local flags = math.floor(r.GetMediaTrackInfo_Value(track, "I_PERFFLAGS"))
  r.SetMediaTrackInfo_Value(track, "I_PERFFLAGS", flags & ~2)    -- media buffering stays off (flag 1)
end

-- a looping voice claims a few minutes at a time and grows as the play cursor gets near
function E.extend_voice(lane, heard)
  local v = lane.current
  if not v or v.closing or lane.pending or lane.switch or not H.valid_item(v.item) then return end
  local pos = r.GetMediaItemInfo_Value(v.item, "D_POSITION")
  local len = r.GetMediaItemInfo_Value(v.item, "D_LENGTH")
  if pos + len - heard > K.voice_margin then return end
  r.SetMediaItemInfo_Value(v.item, "D_LENGTH", len + K.voice_extend)
end

-- a clip launched inside the arrange loop also fills loop start -> launch point, so the
-- loop jumping back finds the clip already playing
function E.build_wrap(lane, v)
  if not v or v.wrap then return end
  local ls, le = E.loop_region()
  if not ls or v.at - ls < 0.05 or v.at >= le then return end
  local lane_track, library = E.lane_track(lane), H.item(v.slot_guid)
  if not lane_track or not library then return end
  local wrap = E.copy_item(library, lane_track, ls)
  if not wrap then return end
  r.SetMediaItemInfo_Value(wrap, "B_MUTE", 0)
  r.SetMediaItemInfo_Value(wrap, "B_LOOPSRC", 1)
  r.SetMediaItemInfo_Value(wrap, "D_LENGTH", v.at - ls)
  r.SetMediaItemInfo_Value(wrap, "D_FADEINLEN", 0)
  r.SetMediaItemInfo_Value(wrap, "D_FADEOUTLEN", K.fade)
  r.UpdateItemInProject(wrap)
  v.wrap = wrap
end

-- once the loop has come round, the filler becomes the clip over the whole loop
function E.promote_wrap(lane, heard)
  local v = lane.current
  if not v or not H.valid_item(v.wrap) or not H.valid_item(v.item) then return end
  local ls, le = E.loop_region()
  if not ls then return end
  if r.GetMediaItemInfo_Value(v.item, "D_POSITION") - heard < 0.25 then return end
  r.SetMediaItemInfo_Value(v.wrap, "D_LENGTH", math.max(0.05, le - ls))
  v.closing = nil
  E.delete_item(v.item)
  v.item, v.wrap, v.at = v.wrap, nil, ls
end

-- launches that waited for the loop to come round
function E.run_queued()
  local ls = E.loop_region()
  for _, lane in pairs(L.lanes) do
    local q = lane.queued
    lane.queued = nil
    if q and ls then
      if q.stop then
        E.cancel_pending(lane)
        E.close_voice_at(lane.current, ls)
        E.schedule_owner(lane, "launcher", ls)
      else
        E.commit(lane, q.row, ls, lane.slots[q.row] and E.setting(lane.slots[q.row], false, "mode"))
      end
    end
  end
end

-- replaced voices go once the play cursor you hear has passed them
function E.harvest(lane, force)
  local heard = E.heard_pos()
  local function done(v)
    if not v then return false end
    if force or not heard then return true end
    local finish = E.voice_end(v)
    return not finish or heard > finish + K.harvest_pad
  end
  if force then lane.queued = nil end
  for i = #lane.retired, 1, -1 do
    if done(lane.retired[i]) then E.kill_voice(lane.retired[i]) table.remove(lane.retired, i) end
  end
  if done(lane.pending) then E.kill_voice(lane.pending) lane.pending = nil end
  if done(lane.current) then E.kill_voice(lane.current) lane.current = nil end
  if not lane.pending and not lane.current then lane.stop_at = nil end
end

----------------------------------------------------------------------------------------------
-- engine: launching and stopping
----------------------------------------------------------------------------------------------

-- a clip's launch setting: its own, else the project's (Main or ALT)
function E.setting(slot, alt, key)
  if alt then
    local v = slot and slot["a" .. key]
    if v == nil then v = L.def["a" .. key] end
    return v
  end
  local v = slot and slot[key]
  if v == nil then v = key == "q" and L.quantize or L.def[key] end
  return v
end

function E.launch(lane, row, alt, q, mode)
  local slot = lane.slots[row]
  if not slot then return end
  if slot.missing then L.status = "That clip is gone from the project (undo brings it back)" return end
  q = q or E.setting(slot, alt, "q")
  mode = mode or E.setting(slot, alt, "mode")
  local time, roll, at_wrap = E.launch_time(q)
  if at_wrap then
    lane.queued = { row = row }
    L.status = "Queued for the top of the loop"
    return
  end
  r.PreventUIRefresh(1)
  local ok = E.commit(lane, row, time, mode)
  r.PreventUIRefresh(-1)
  if not ok then L.status = "Could not launch that clip" return end
  if roll then E.roll_transport(time) end
  r.UpdateArrange()
  L.status = "Launched " .. (slot.name or "clip")
end

-- Bitwig's stop square: the clip stops on the launch grid and the launcher keeps the track
-- (silent) until its return arrow gives it back
function E.stop_lane(lane, time)
  lane.queued, lane.run = nil, nil
  local now = E.schedule_pos()
  if not now then
    E.harvest(lane, true)
    E.env_stop_all(lane, nil)
    return
  end
  time = time or E.boundary_after(now, false)
  E.cancel_pending(lane)
  E.close_voice_at(lane.current, time)
  if lane.current then lane.stop_at = time end
  E.env_stop_all(lane, time)
  E.schedule_owner(lane, "launcher", time)
end

function E.stop_track(track)
  local m = E.rec_mark(track, nil)
  if m then E.rec_stop(m) return end
  local lane = H.lane_of(track, true)
  r.PreventUIRefresh(1)
  E.stop_lane(lane)
  r.PreventUIRefresh(-1)
  r.UpdateArrange()
end

function E.stop_all()
  local now = E.schedule_pos()
  local time = now and E.boundary_after(now, false)
  r.PreventUIRefresh(1)
  for _, lane in pairs(L.lanes) do
    if lane.current or lane.pending or not now then E.stop_lane(lane, time) end
  end
  r.PreventUIRefresh(-1)
  r.UpdateArrange()
  L.status = now and "All clips stop on the next line" or "Stopped"
end

-- Bitwig's return arrow: straight back to the arranger, not quantized
function E.back_to_arrangement(lane)
  if not lane then return end
  lane.queued, lane.run = nil, nil
  E.cancel_pending(lane)
  local now = E.schedule_pos()
  if now and lane.current then
    E.close_voice_at(lane.current, now + K.min_lead)
    lane.retired[#lane.retired + 1] = lane.current
    lane.current = nil
  elseif lane.current then
    E.kill_voice(lane.current)
    lane.current = nil
  end
  lane.stop_at = nil
  E.env_stop_all(lane, now and now + K.min_lead)
  E.release_now(lane)
end

function E.back_all()
  r.PreventUIRefresh(1)
  for _, lane in pairs(L.lanes) do E.back_to_arrangement(lane) end
  r.PreventUIRefresh(-1)
  r.UpdateArrange()
  L.status = "Every track plays the arrangement again"
end

-- a scene: every track with a clip in that row launches it, every other track stops
function E.launch_scene(row)
  local time, roll, at_wrap = E.launch_time(L.quantize)
  local launched = 0
  r.PreventUIRefresh(1)
  for t = 0, r.CountTracks(0) - 1 do
    local track = r.GetTrack(0, t)
    if not H.is_lane_track(track) then
      local lane = H.lane_of(track, false)
      local slot = lane and lane.slots[row]
      if at_wrap then
        if lane and (slot or lane.current or lane.pending) then lane.queued = slot and { row = row } or { stop = true } end
      elseif slot and not slot.missing then
        if E.commit(lane, row, time, E.setting(slot, false, "mode")) then launched = launched + 1 end
      elseif lane and (lane.current or lane.pending) then
        E.cancel_pending(lane)
        E.close_voice_at(lane.current, time)
        if lane.current then lane.stop_at = time end
        E.schedule_owner(lane, "launcher", time)
      end
      if lane and not at_wrap then
        for name, ez in pairs(lane.envs or {}) do
          if not ez.slots[row] then
            E.env_stop(ez, E.schedule_pos() and time or nil)
          elseif not (slot and not slot.missing) then
            if E.env_commit(lane, name, H.env_by_name(track, name), row, time) then launched = launched + 1 end
          end
        end
      end
    end
  end
  r.PreventUIRefresh(-1)
  if launched > 0 and roll then E.roll_transport(time) end
  r.UpdateArrange()
  L.status = at_wrap and ("Scene queued for the top of the loop") or (H.scene_name(row) .. " launched")
end

-- everything back at once: the panel closing, the transport stopping, a project switch
function E.release_all()
  r.PreventUIRefresh(1)
  for _, lane in pairs(L.lanes) do
    E.kill_voice(lane.current)
    E.kill_voice(lane.pending)
    for _, v in ipairs(lane.retired) do E.kill_voice(v) end
    lane.current, lane.pending, lane.retired, lane.queued, lane.stop_at, lane.run = nil, nil, {}, nil, nil, nil
    if lane.gate_shut then E.gate_open(lane) end
    E.env_release(lane)
    E.release_now(lane)
  end
  r.PreventUIRefresh(-1)
  r.UpdateArrange()
end

----------------------------------------------------------------------------------------------
-- engine: Next Action and release actions
----------------------------------------------------------------------------------------------

-- the clip a Next Action goes to: a row, or "stop" / "arrange"
function E.pick(lane, row, action)
  if action == "stop" or action == "arrange" then return action end
  if action == "back" then
    local p = lane.prev
    if type(p) == "number" and lane.slots[p] and not lane.slots[p].missing then return p end
    return p == "arrange" and "arrange" or "stop"
  end
  local rows = {}
  for rw, slot in pairs(lane.slots) do if not slot.missing then rows[#rows + 1] = rw end end
  table.sort(rows)
  if #rows == 0 then return "stop" end
  if action == "first" then return rows[1] end
  if action == "last" then return rows[#rows] end
  if action == "random" then return rows[math.random(#rows)] end
  if action == "other" then
    if #rows == 1 then return rows[1] end
    local pick
    repeat pick = rows[math.random(#rows)] until pick ~= row
    return pick
  end
  if action == "prev" then
    for i = #rows, 1, -1 do if rows[i] < row then return rows[i] end end
    return "stop"
  end
  for _, rw in ipairs(rows) do if rw > row then return rw end end      -- next / round
  return action == "round" and rows[1] or "stop"
end

function E.do_next(lane, row, action, time)
  local target = E.pick(lane, row, action)
  if target == "stop" then
    E.stop_lane(lane, time)
  elseif target == "arrange" then
    E.cancel_pending(lane)
    E.close_voice_at(lane.current, time)
    if lane.current then lane.stop_at = time end
    E.schedule_owner(lane, "arrangement", time)
    lane.run = nil
  else
    E.commit(lane, target, time, E.setting(lane.slots[target], false, "mode"))
  end
end

-- the clip of `row` stops at once (the gate), its voice ends a moment later
function E.cut(lane, row)
  local now = E.schedule_pos()
  if not now then E.harvest(lane, true) return end
  if lane.pending and lane.pending.row == row then E.cancel_pending(lane) end
  if not (lane.current and lane.current.row == row) then return end
  E.gate_shut(lane)
  local at = now + E.lead()
  E.close_voice_at(lane.current, at)
  lane.stop_at, lane.run, lane.queued = at, nil, nil
end

-- Bitwig's release action, on letting go of the play triangle
function E.release(lane, row, rel)
  if not lane or rel == "continue" then return end
  local now = E.schedule_pos()
  local slot = lane.slots[row]
  local waiting = lane.pending and lane.pending.row == row
  r.PreventUIRefresh(1)
  if rel == "stop" then
    E.cut(lane, row)
  elseif rel == "return" then
    if waiting then
      E.cancel_pending(lane)
    elseif lane.current and lane.current.row == row then
      local p = lane.prev
      if type(p) == "number" and lane.slots[p] and now then
        E.commit(lane, p, E.boundary_after(now, false, 0), "legato_cp")
      elseif p == "arrange" then
        E.gate_shut(lane)
        E.back_to_arrangement(lane)
      else
        E.cut(lane, row)
      end
    end
  elseif rel == "next" and now and lane.current and lane.current.row == row and not waiting then
    E.do_next(lane, row, slot and slot.na or "next", E.boundary_after(now, false, 0))
  end
  r.PreventUIRefresh(-1)
  r.UpdateArrange()
end

function E.clear_slot(lane, row)
  local slot = lane.slots[row]
  if not slot then return end
  if lane.current and lane.current.row == row then E.kill_voice(lane.current) lane.current = nil end
  if lane.pending and lane.pending.row == row then E.cancel_pending(lane) end
  E.delete_item(H.item(slot.guid))
  lane.slots[row] = nil
  if L.sel and L.sel.lane == lane and L.sel.row == row then L.sel = nil end
end

-- drag a clip to another slot (Ctrl: copy). A clip that is playing stops first.
function E.move_slot(from_lane, from_row, to_lane, to_row, copy)
  if from_lane == to_lane and from_row == to_row then return end
  local slot = from_lane.slots[from_row]
  local library = slot and H.item(slot.guid)
  if not library then return end
  H.begin()
  r.PreventUIRefresh(1)
  if not copy and ((from_lane.current and from_lane.current.row == from_row) or (from_lane.pending and from_lane.pending.row == from_row)) then
    E.back_to_arrangement(from_lane)
  end
  local lane_track = E.ensure_lane_track(to_lane)
  E.clear_slot(to_lane, to_row)
  local moved = {}
  for k, v in pairs(slot) do moved[k] = v end
  if copy or from_lane ~= to_lane then
    local item = E.copy_item(library, lane_track, 0)
    if item then
      moved.guid = H.item_guid(item)
      if not copy then E.delete_item(library) from_lane.slots[from_row] = nil end
      to_lane.slots[to_row] = moved
    end
  else
    from_lane.slots[from_row] = nil
    to_lane.slots[to_row] = moved
  end
  if to_row > #L.scenes then for i = #L.scenes + 1, to_row do L.scenes[i] = {} end end
  L.sel = { lane = to_lane, row = to_row }
  r.PreventUIRefresh(-1)
  H.finish(copy and "Launcher: copy clip" or "Launcher: move clip")
  H.save()
end

function E.add_selected(track, row)
  local n = r.CountSelectedMediaItems(0)
  if n == 0 then L.status = "Select one or more items in the arrange first" return end
  local items = {}
  for i = 0, n - 1 do items[#items + 1] = r.GetSelectedMediaItem(0, i) end
  local lane = H.lane_of(track, true)
  H.begin()
  r.PreventUIRefresh(1)
  local added = 0
  for i, item in ipairs(items) do
    if not H.is_lane_track(r.GetMediaItemTrack(item)) and E.assign_item(lane, row + i - 1, item) then added = added + 1 end
  end
  r.PreventUIRefresh(-1)
  H.finish("Launcher: add clips")
  r.UpdateArrange()
  H.save()
  L.status = added == 1 and "Added 1 clip" or ("Added " .. added .. " clips")
end

-- one pass of the clip into the arrange at the edit cursor, on the clip's own track
function E.to_arrangement(lane, row)
  local slot = lane.slots[row]
  local library = slot and H.item(slot.guid)
  local target = H.track(lane.track_guid)
  if not library or not target then return end
  H.begin()
  local _, period = E.slot_lengths(slot)
  local item = E.copy_item(library, target, r.GetCursorPosition())
  if item then
    r.SetMediaItemInfo_Value(item, "B_MUTE", 0)
    r.SetMediaItemInfo_Value(item, "D_LENGTH", period > 0 and period or r.GetMediaItemInfo_Value(item, "D_LENGTH"))
    if E.launcher_owns(lane) and lane.origin then           -- the launcher is silencing this track
      lane.origin[#lane.origin + 1] = { guid = H.item_guid(item), mute = 0 }
      r.SetMediaItemInfo_Value(item, "B_MUTE", 1)
      E.save_restore()
    end
  end
  H.finish("Launcher: clip to arrangement")
  r.UpdateArrange()
end

----------------------------------------------------------------------------------------------
-- editing a clip: MIDI in REAPER's MIDI editor, audio in TK Bit Clip Edit. The clip itself
-- (the library item on the hidden track) is what gets edited, so every later launch plays the
-- edit. An action will not touch an item on a hidden track, so the track shows while editing.
-- Clip Edit takes items that touch as one clip, and the library sits stacked at zero, so an
-- audio clip moves to empty ground on its track for as long as it is open.
----------------------------------------------------------------------------------------------

function E.edit(lane, row)
  L.lay = nil                        -- the track layout changes: read it again
  local slot = lane.slots[row]
  local item = slot and H.item(slot.guid)
  local take = item and r.GetActiveTake(item)
  if not take then L.status = "That clip is gone from the project" return end
  E.edit_end()
  local track = r.GetMediaItemTrack(item)
  local hidden = r.GetMediaTrackInfo_Value(track, "B_SHOWINTCP") < 0.5
  local ed = { item = item, track = track, hidden = hidden, midi = r.TakeIsMIDI(take), at = r.time_precise(),
    guid = slot.guid, kept = {} }
  for i = 0, r.CountSelectedMediaItems(0) - 1 do ed.kept[#ed.kept + 1] = r.GetSelectedMediaItem(0, i) end
  r.PreventUIRefresh(1)
  if hidden then r.SetMediaTrackInfo_Value(track, "B_SHOWINTCP", 1) end
  if not ed.midi then
    local clear = 0
    for i = 0, r.CountTrackMediaItems(track) - 1 do
      local it = r.GetTrackMediaItem(track, i)
      if it ~= item then clear = math.max(clear, E.item_end(it) or 0) end
    end
    ed.home = r.GetMediaItemInfo_Value(item, "D_POSITION")
    r.SetMediaItemInfo_Value(item, "D_POSITION", clear + 4)
  end
  H.unselect_items()
  r.SetMediaItemSelected(item, true)
  r.PreventUIRefresh(-1)
  r.TrackList_AdjustWindows(false)
  r.UpdateArrange()
  L.editing = ed
  if ed.midi then
    r.Main_OnCommand(40153, 0)                     -- Item: open in built-in MIDI editor
    ed.hash = select(2, r.MIDI_GetHash(take, false, ""))
    L.status = "Editing " .. (slot.name or "clip") .. " in the MIDI editor"
  else
    local cmd = r.AddRemoveReaScript(true, 0, K.dir .. "/TK_Theme_Bit_Clip_Edit.lua", false)
    if cmd and cmd > 0 then
      ed.cmd = cmd
      if r.GetToggleCommandState(cmd) ~= 1 then r.Main_OnCommand(cmd, 0) end
      L.status = "Editing " .. (slot.name or "clip") .. " in Clip Edit"
    else
      L.status = "TK Bit Clip Edit was not found"
      E.edit_end()
    end
  end
end

-- the edit is over (the editor closed, or another item was selected): the clip goes home,
-- the track hides again, the user's selection comes back
function E.edit_end()
  L.lay = nil                        -- the track layout changes: read it again
  local ed = L.editing
  if not ed then return end
  L.editing = nil
  r.PreventUIRefresh(1)
  if H.valid_item(ed.item) then
    if ed.home then r.SetMediaItemInfo_Value(ed.item, "D_POSITION", ed.home) end
    r.SetMediaItemInfo_Value(ed.item, "B_MUTE", 1)
    if r.IsMediaItemSelected(ed.item) then
      r.SetMediaItemSelected(ed.item, false)
      for _, it in ipairs(ed.kept) do if H.valid_item(it) then r.SetMediaItemSelected(it, true) end end
    end
  end
  if ed.hidden and H.valid_track(ed.track) and not H.lanes_shown_except(ed.track) then
    r.SetMediaTrackInfo_Value(ed.track, "B_SHOWINTCP", 0)
  end
  r.PreventUIRefresh(-1)
  r.TrackList_AdjustWindows(false)
  r.UpdateArrange()
  for k in pairs(L.peaks) do if k:find(ed.guid, 1, true) == 1 then L.peaks[k] = nil end end
  L.notes[ed.guid] = nil
end

-- every frame while editing: is it still open? A MIDI edit is heard at once in a clip that
-- is playing: the voice takes the library's events (voices are copies, made at launch)
function E.edit_watch(t)
  local ed = L.editing
  if not ed then return end
  if not H.valid_item(ed.item) then L.editing = nil return end
  if t - ed.at < 0.6 then return end                -- the editor is still opening
  if ed.midi then
    if not r.MIDIEditor_GetActive() then E.edit_end() return end
    if t - (ed.checked or 0) < 0.2 then return end
    ed.checked = t
    local take = r.GetActiveTake(ed.item)
    local hash = take and select(2, r.MIDI_GetHash(take, false, ""))
    if hash and hash ~= ed.hash then
      ed.hash = hash
      local ok, buf = r.MIDI_GetAllEvts(take, "")
      if ok then
        for _, lane in pairs(L.lanes) do
          for _, v in ipairs({ lane.current, lane.pending }) do
            if v and v.slot_guid == ed.guid then
              for _, it in ipairs({ v.item, v.wrap }) do
                local vt = H.valid_item(it) and r.GetActiveTake(it)
                if vt then r.MIDI_SetAllEvts(vt, buf) end
              end
            end
          end
        end
      end
      L.notes[ed.guid] = nil
    end
  else
    local closed = ed.cmd and r.GetToggleCommandState(ed.cmd) ~= 1
    if closed or r.GetSelectedMediaItem(0, 0) ~= ed.item then E.edit_end() end
  end
end

-- Colours live on REAPER's own objects, so the inspector (and REAPER) show what the launcher
-- shows: the hidden track takes its real track's colour (a clip without a colour of its own
-- is drawn in it), and a clip's own colour is its item's. A colour set in the inspector
-- reaches the launcher from here; an older clip whose colour was only in the grid hands it
-- to its item once.
function E.sync_colours(lane)
  local lt, target = E.lane_track(lane), H.track(lane.track_guid)
  if lt and target then
    local want = r.GetMediaTrackInfo_Value(target, "I_CUSTOMCOLOR")
    if r.GetMediaTrackInfo_Value(lt, "I_CUSTOMCOLOR") ~= want then
      r.SetMediaTrackInfo_Value(lt, "I_CUSTOMCOLOR", want)
    end
  end
  for _, slot in pairs(lane.slots) do
    local item = H.item(slot.guid)
    if item then
      local own = H.rgba(r.GetMediaItemInfo_Value(item, "I_CUSTOMCOLOR"))
      if not own and slot.color and not slot.color_moved then
        E.set_item_colour(item, slot.color)
        slot.color_moved = true
      else
        slot.color, slot.color_moved = own, true
      end
    end
  end
end

-- 0xRRGGBBFF onto an item (nil: no colour of its own, the track's)
function E.set_item_colour(item, rgba)
  local native = 0
  if rgba then native = r.ColorToNative((rgba >> 24) & 255, (rgba >> 16) & 255, (rgba >> 8) & 255) | 0x1000000 end
  r.SetMediaItemInfo_Value(item, "I_CUSTOMCOLOR", native)
  r.UpdateArrange()
end

-- the per-frame engine: promote voices that have started, land handovers, tidy up
----------------------------------------------------------------------------------------------
-- engine: recording into a slot (TK Project Clips' way: REAPER records the take, the launcher
-- marks the lines it was meant for, and cuts the clip out of the take once recording ends)
----------------------------------------------------------------------------------------------

-- the line a recording starts on: always the next one (a recording is written behind the
-- play cursor, so it needs no lead); with Launch Q off, right away
function E.rec_next(t)
  local q = L.quantize
  if q == 0 then return t end
  local i = E.grid_index(t, q)
  return i and E.grid_time(t, math.floor(i) + 1, q) or t
end
-- the line it stops on: the nearest one (stopping is a reaction to the bar just played)
function E.rec_near(t)
  local q = L.quantize
  if q == 0 then return t end
  local i = E.grid_index(t, q)
  return i and E.grid_time(t, math.floor(i + 0.5), q) or t
end

function E.rec_mark(track, row)
  for _, m in ipairs(L.recs) do
    if m.track == track and (not row or m.row == row) and (row or not m.to) then return m end
  end
end

function E.rec_start(track, row)
  if r.GetMediaTrackInfo_Value(track, "I_RECARM") < 0.5 then
    L.status = "Arm the track first"
    return
  end
  local lane = H.lane_of(track, true)
  local playing = (r.GetPlayState() & 1) == 1
  local from
  if playing then
    from = E.rec_next(E.schedule_pos())
  else
    from = E.rec_next(r.GetCursorPosition())
    if L.quantize == 0 then from = r.GetCursorPosition() end
    r.OnPlayButton()
    L.roll_guard = r.time_precise() + 1.5
  end
  local open = E.rec_mark(track, nil)
  if open then open.to = from end                  -- one lane records one slot at a time
  if (r.GetPlayState() & 4) == 0 then L.rec_arm = math.min(L.rec_arm or from, from) end
  local before = {}                                -- what is already there is never the take
  for i = 0, r.CountTrackMediaItems(track) - 1 do before[H.item_guid(r.GetTrackMediaItem(track, i))] = true end
  L.recs[#L.recs + 1] = { track = track, row = row, from = from, before = before }
  if playing then
    r.PreventUIRefresh(1)
    E.stop_lane(lane, math.max(from, E.schedule_pos() + E.lead()))
    r.PreventUIRefresh(-1)
  else
    E.schedule_owner(lane, "launcher", from)       -- the arrangement on this track goes quiet
  end
  if row > #L.scenes then for i = #L.scenes + 1, row do L.scenes[i] = {} end end
  L.status = "Recording into " .. H.track_name(track) .. " from the next line"
end

function E.rec_stop(m)
  local now = E.schedule_pos()
  if not now or now < m.from then                  -- nothing recorded yet: take the mark back
    for i, x in ipairs(L.recs) do if x == m then table.remove(L.recs, i) break end end
    L.status = "Recording cancelled"
    return
  end
  m.to = math.max(m.from + 0.05, E.rec_near(now))
  L.status = "Recording stops on the line"
end

-- the take recording left on the track, and how much of the marked stretch it holds
function E.rec_take(m)
  local best, best_overlap, a, b
  for i = 0, r.CountTrackMediaItems(m.track) - 1 do
    local item = r.GetTrackMediaItem(m.track, i)
    if not m.before[H.item_guid(item)] then
      local pos = r.GetMediaItemInfo_Value(item, "D_POSITION")
      local lo = math.max(pos, m.from)
      local hi = math.min(pos + r.GetMediaItemInfo_Value(item, "D_LENGTH"), m.to)
      if hi - lo > 0.05 and (not best_overlap or hi - lo > best_overlap) then
        best, best_overlap, a, b = item, hi - lo, lo, hi
      end
    end
  end
  return best, a, b
end

-- recording has ended: every mark becomes a clip, the takes leave the arrangement (Bitwig
-- records into the slot only), and the new clips play on if the transport still runs
function E.rec_harvest()
  local left, used, spare, made = {}, {}, {}, {}
  H.begin()
  for _, m in ipairs(L.recs) do
    local source, a, b
    if H.valid_track(m.track) and m.to then source, a, b = E.rec_take(m) end
    local ok = false
    if source then
      local slice = E.copy_item(source, m.track, a)
      if slice then
        r.SetMediaItemInfo_Value(slice, "D_LENGTH", b - a)
        local take = r.GetActiveTake(slice)
        if take then
          local rate = r.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE")
          r.SetMediaItemTakeInfo_Value(take, "D_STARTOFFS", r.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS")
            + (a - r.GetMediaItemInfo_Value(source, "D_POSITION")) * (rate > 0 and rate or 1))
        end
        local lane = H.lane_of(m.track, true)
        ok = E.assign_item(lane, m.row, slice)
        if ok then
          local slot = lane.slots[m.row]
          slot.name = H.track_name(m.track) .. " " .. m.row
          made[#made + 1] = { lane = lane, row = m.row }
        end
        r.DeleteTrackMediaItem(m.track, slice)
      end
    end
    if ok then used[source] = m.track elseif source then spare[source] = true end
    if not ok and m.tries and m.tries > 8 then ok = true end       -- give up quietly
    if not ok then m.tries = (m.tries or 0) + 1 left[#left + 1] = m end
  end
  for item, track in pairs(used) do
    if not spare[item] and H.valid_item(item) then r.DeleteTrackMediaItem(track, item) end
  end
  L.recs = left
  H.finish("Launcher: record clips")
  H.save()
  if (r.GetPlayState() & 1) == 1 then
    for _, c in ipairs(made) do E.launch(c.lane, c.row) end
  end
  r.UpdateArrange()
  L.status = #made == 1 and "Recorded 1 clip" or ("Recorded " .. #made .. " clips")
  return #left == 0
end

-- watched every frame: punch in when the line comes, punch out when every mark is done,
-- and collect the clips a moment after recording ends (REAPER is still closing the file)
function E.rec_watch(t)
  local state = r.GetPlayState()
  local recording = (state & 4) == 4
  local now = E.schedule_pos()
  if L.rec_arm then
    if recording then L.rec_arm = nil
    elseif now and now >= L.rec_arm - 0.05 then
      r.Main_OnCommand(1013, 0)                    -- Transport: Record
      L.rec_arm, L.rec_ours = nil, true
    end
  end
  if recording then
    if now and now > (L.rec_end or 0) then L.rec_end = now end
    local latest, open = nil, false
    for _, m in ipairs(L.recs) do
      if not m.to then open = true break end
      latest = math.max(latest or 0, m.to)
    end
    if #L.recs > 0 and not open and latest and now and now >= latest and L.rec_ours then
      r.Main_OnCommand(1013, 0)                    -- recording off; playback carries on
      L.rec_ours = nil
    end
  elseif L.was_recording then
    for _, m in ipairs(L.recs) do if not m.to then m.to = math.max(m.from + 0.05, L.rec_end or m.from) end end
    L.rec_harvest_at, L.rec_end, L.rec_ours = t + 0.25, nil, nil
  end
  L.was_recording = recording
  if L.rec_harvest_at and t >= L.rec_harvest_at and not recording then
    L.rec_harvest_at = nil
    if #L.recs > 0 and not E.rec_harvest() then L.rec_harvest_at = t + 0.5 end
  end
end

----------------------------------------------------------------------------------------------
-- engine: the performance into the arrangement (the REC key): every clip that sounds while
-- it is on is written onto its own track once the transport stops (or the key goes off)
----------------------------------------------------------------------------------------------

function E.perf_capture(v, to)
  if not L.perf or not v or not v.perf_from or not v.track_guid then return end
  to = math.min(to or math.huge, E.item_end(v.item) or to or 0, L.perf_hi or 0)
  if to - v.perf_from > 0.01 then
    L.perf_spans[#L.perf_spans + 1] = { tg = v.track_guid, guid = v.slot_guid, from = v.perf_from,
      to = to, at = v.at, offset = v.offset or 0, len = v.length or 0 }
  end
  v.perf_from = nil
end

function E.perf_write()
  local spans = L.perf_spans
  L.perf_spans, L.perf_hi = {}, 0
  if #spans == 0 then return end
  H.begin()
  r.PreventUIRefresh(1)
  local n = 0
  for _, s in ipairs(spans) do
    local target, library = H.track(s.tg), H.item(s.guid)
    local item = target and library and E.copy_item(library, target, s.from)
    if item then
      r.SetMediaItemInfo_Value(item, "B_MUTE", 0)
      r.SetMediaItemInfo_Value(item, "B_LOOPSRC", 1)
      r.SetMediaItemInfo_Value(item, "D_LENGTH", s.to - s.from)
      local into = s.len > 0 and ((s.from - s.at + s.offset) % s.len) or 0
      local take = r.GetActiveTake(item)
      if take and into > 0 then
        local rate = r.GetMediaItemTakeInfo_Value(take, "D_PLAYRATE")
        r.SetMediaItemTakeInfo_Value(take, "D_STARTOFFS", r.GetMediaItemTakeInfo_Value(take, "D_STARTOFFS") + into * (rate > 0 and rate or 1))
      end
      local lane = L.lanes[s.tg]
      if lane and E.launcher_owns(lane) and lane.origin then      -- still silenced by the launcher
        lane.origin[#lane.origin + 1] = { guid = H.item_guid(item), mute = 0 }
        r.SetMediaItemInfo_Value(item, "B_MUTE", 1)
      end
      n = n + 1
    end
  end
  E.save_restore()
  r.PreventUIRefresh(-1)
  H.finish("Launcher: record performance to arrangement")
  r.UpdateArrange()
  L.status = "Wrote " .. n .. (n == 1 and " clip" or " clips") .. " into the arrangement"
end

function E.perf_toggle()
  local now = E.schedule_pos()
  if L.perf then
    for _, lane in pairs(L.lanes) do
      E.perf_capture(lane.current, now or L.perf_hi)
      for _, ez in pairs(lane.envs or {}) do
        if ez.cur and ez.cur.keep_from and not ez.cur.keep_to then ez.cur.keep_to = now or L.perf_hi end
        for _, h in ipairs(ez.retired) do               -- ended, not yet cleared away
          if h.keep_from and not h.keep_to then h.keep_to = L.perf_hi end
        end
      end
    end
    E.perf_write()
    L.perf = false
  else
    L.perf, L.perf_spans, L.perf_hi = true, {}, now or 0
    for _, lane in pairs(L.lanes) do
      if lane.current and lane.current.started and now then lane.current.perf_from = now end
      for _, ez in pairs(lane.envs or {}) do
        if ez.cur and now then ez.cur.keep_from, ez.cur.keep_to = now, nil end
      end
    end
  end
end

----------------------------------------------------------------------------------------------
-- engine: automation clips (an envelope's own row; Bitwig's launcher automation). A clip is
-- a curve kept in the project data; launching lays it down as a looping automation item on
-- the envelope, which overrides the envelope's own points where it lies.
----------------------------------------------------------------------------------------------

K.ai_voice = "TK Bit voice"
K.ai_kept = "TK Bit clip"        -- one written into the arrangement: never swept

function H.env_name(env)
  local _, name = r.GetEnvelopeName(env)
  return name or "?"
end
function H.env_by_name(track, name)
  for i = 0, r.CountTrackEnvelopes(track) - 1 do
    local env = r.GetTrackEnvelope(track, i)
    if H.env_name(env) == name then return env end
  end
end
function H.env_lane(lane, name, create)
  lane.envs = lane.envs or {}
  local ez = lane.envs[name]
  if not ez and create then
    ez = { slots = {}, retired = {} }
    lane.envs[name] = ez
  end
  return ez
end

-- Our automation item on its envelope. The pool id is the sharp handle, but it does not always
-- answer (TK Project Clips found the same), so the item carrying our name where we put it
-- counts too. Not found = it can be neither trimmed nor removed, and it plays on: the user saw
-- every launched clip stay on the envelope until the transport stopped (2026-11-27).
function E.ai_index(h)
  if not h or not h.env then return nil end
  if not (r.ValidatePtr2(0, h.env, "TrackEnvelope*") or r.ValidatePtr(h.env, "TrackEnvelope*")) then return nil end
  local n = r.CountAutomationItems(h.env)
  for i = 0, n - 1 do
    if math.floor(r.GetSetAutomationItemInfo(h.env, i, "D_POOL_ID", 0, false) + 0.5) == h.pool then return i end
  end
  for i = 0, n - 1 do
    local _, name = r.GetSetAutomationItemInfo_String(h.env, i, "P_POOL_NAME", "", false)
    if (name == K.ai_voice or name == K.ai_kept)
      and math.abs(r.GetSetAutomationItemInfo(h.env, i, "D_POSITION", 0, false) - (h.at or -1)) < 0.002 then
      h.pool = math.floor(r.GetSetAutomationItemInfo(h.env, i, "D_POOL_ID", 0, false) + 0.5)
      return i
    end
  end
end
function E.ai_end(h)
  local i = E.ai_index(h)
  if not i then return nil end
  return r.GetSetAutomationItemInfo(h.env, i, "D_POSITION", 0, false) + r.GetSetAutomationItemInfo(h.env, i, "D_LENGTH", 0, false)
end
function E.ai_trim(h, time)
  if h then h.closing = true end          -- cut off: never grown again (see E.env_tick)
  local i = E.ai_index(h)
  if not i then return end
  local len = time - r.GetSetAutomationItemInfo(h.env, i, "D_POSITION", 0, false)
  if len > 0.0001 then r.GetSetAutomationItemInfo(h.env, i, "D_LENGTH", len, true) else E.ai_delete(h) end
end
-- REAPER has no call that removes an automation item: its POOLEDENVINST line leaves the
-- envelope's chunk (Project Clips, tested); if that misses, it is shrunk to nothing
function E.ai_delete(h)
  local i = E.ai_index(h)
  if not i then return end
  local ok, chunk = r.GetEnvelopeStateChunk(h.env, "", false)
  if ok and chunk ~= "" then
    local lines, at, n = {}, nil, 0
    for line in (chunk .. "\n"):gmatch("(.-)\n") do lines[#lines + 1] = line end
    for k, line in ipairs(lines) do
      local pool = line:match("^%s*POOLEDENVINST%s+(%S+)")
      if pool then
        if tonumber(pool) == h.pool then at = k break end
        n = n + 1
      end
    end
    if at then
      table.remove(lines, at)
      r.SetEnvelopeStateChunk(h.env, table.concat(lines, "\n"), false)
    end
  end
  i = E.ai_index(h)
  if i then
    r.GetSetAutomationItemInfo(h.env, i, "D_LOOPSRC", 0, true)
    r.GetSetAutomationItemInfo(h.env, i, "D_LENGTH", 0.0001, true)
  end
end

-- a curve read from the envelope: the selected automation item on it, else the time selection
function E.env_capture(env)
  local pts, len, pos = {}, nil, nil
  for i = 0, r.CountAutomationItems(env) - 1 do
    if r.GetSetAutomationItemInfo(env, i, "D_UISEL", 0, false) > 0.5 then
      pos = r.GetSetAutomationItemInfo(env, i, "D_POSITION", 0, false)
      len = r.GetSetAutomationItemInfo(env, i, "D_LENGTH", 0, false)
      if r.GetSetAutomationItemInfo(env, i, "D_LOOPSRC", 0, false) > 0.5 then
        local qn = r.GetSetAutomationItemInfo(env, i, "D_POOL_QNLEN", 0, false)
        if qn > 0 then len = r.TimeMap2_QNToTime(0, r.TimeMap2_timeToQN(0, pos) + qn) - pos end
      end
      for origin = 1, 2 do                           -- points are timed from the project start
        local base = origin == 1 and pos or 0
        for p = 0, r.CountEnvelopePointsEx(env, i) - 1 do
          local _, t, v, s, n = r.GetEnvelopePointEx(env, i, p)
          local f = (t - base) / len
          if f > -0.0001 and f < 1.0001 then pts[#pts + 1] = { t = math.max(0, math.min(1, f)), v = v, s = s, n = n } end
        end
        if #pts > 0 then break end
      end
      break
    end
  end
  if not len then
    local s, e = r.GetSet_LoopTimeRange(false, false, 0, 0, false)
    if not s or e - s < 0.05 then return nil end
    pos, len = s, e - s
    local _, v0 = r.Envelope_Evaluate(env, s, 0, 0)
    pts[1] = { t = 0, v = v0, s = 0, n = 0 }
    for p = 0, r.CountEnvelopePoints(env) - 1 do
      local _, t, v, sh, n = r.GetEnvelopePoint(env, p)
      if t > s and t < e then pts[#pts + 1] = { t = (t - s) / len, v = v, s = sh, n = n } end
    end
    local _, v1 = r.Envelope_Evaluate(env, e - 0.0001, 0, 0)
    pts[#pts + 1] = { t = 1, v = v1, s = 0, n = 0 }
  end
  if not len or len <= 0 or #pts == 0 then return nil end
  table.sort(pts, function(a, b) return a.t < b.t end)
  local qn = r.TimeMap2_timeToQN(0, pos + len) - r.TimeMap2_timeToQN(0, pos)
  return { points = pts, qn = qn, name = "Automation" }
end

function E.env_add(track, env, row)
  local clip = E.env_capture(env)
  if not clip then
    L.status = "Select an automation item on that lane, or make a time selection, first"
    return
  end
  local lane = H.lane_of(track, true)
  H.env_lane(lane, H.env_name(env), true).slots[row] = clip
  if row > #L.scenes then for i = #L.scenes + 1, row do L.scenes[i] = {} end end
  H.save()
  L.status = "Added an automation clip"
end

-- lay the curve down at `time` as a looping automation item; the outgoing one ends there
-- the clip's curve as an automation item at `time`: one pass long, or looping over `total`.
-- Returns its pool id and the length of one pass.
function E.ai_put(env, clip, time, total, name)
  local clip_len = r.TimeMap2_QNToTime(0, r.TimeMap2_timeToQN(0, time) + clip.qn) - time
  if clip_len <= 0 then return nil end
  local i = r.InsertAutomationItem(env, -1, time, clip_len)
  if not i or i < 0 then return nil end
  r.DeleteEnvelopePointRangeEx(env, i, time - 1, time + clip_len + 1)
  r.GetSetAutomationItemInfo(env, i, "D_POOL_QNLEN", clip.qn, true)
  local function write(origin)
    for _, p in ipairs(clip.points) do
      r.InsertEnvelopePointEx(env, i, origin + p.t * clip_len, p.v, math.floor(p.s or 0), p.n or 0, false, true)
    end
    r.Envelope_SortPointsEx(env, i)
  end
  write(time)
  if r.CountEnvelopePointsEx(env, i) == 0 then write(0) end
  r.GetSetAutomationItemInfo_String(env, i, "P_POOL_NAME", name, true)
  r.GetSetAutomationItemInfo(env, i, "D_LOOPSRC", total and 1 or 0, true)
  if total then r.GetSetAutomationItemInfo(env, i, "D_LENGTH", total, true) end
  return math.floor(r.GetSetAutomationItemInfo(env, i, "D_POOL_ID", 0, false) + 0.5), clip_len
end

function E.env_commit(lane, name, env, row, time)
  local ez = H.env_lane(lane, name, false)
  local clip = ez and ez.slots[row]
  if not clip or not env then return false end
  E.env_cancel(ez)
  if ez.cur then E.ai_trim(ez.cur, time) end
  local pool, clip_len = E.ai_put(env, clip, time, K.voice_length, K.ai_voice)
  if not pool then return false end
  ez.pend = { env = env, pool = pool, at = time, row = row, len = clip_len }
  ez.stop_at = nil
  return true
end

-- one pass of an automation clip into the arrangement at the edit cursor, on its envelope
function E.env_to_arrangement(track, name, row)
  local lane = H.lane_of(track, false)
  local ez = lane and H.env_lane(lane, name, false)
  local clip = ez and ez.slots[row]
  local env = H.env_by_name(track, name)
  if not clip or not env then return end
  H.begin()
  local pool = E.ai_put(env, clip, r.GetCursorPosition(), nil, K.ai_kept)
  H.finish("Launcher: automation clip to arrangement")
  r.UpdateArrange()
  L.status = pool and "Automation clip copied to the arrangement" or "Could not place the automation clip"
end

-- An automation voice that is done: gone, unless the REC key wants it. Then the item that
-- already lies in the right place stays, cut to the stretch that was heard and renamed so
-- the crash sweep leaves it alone: that is the performance's automation.
function E.ai_done(h)
  local i = h and h.keep_from and E.ai_index(h)
  if not i then E.ai_delete(h) return end
  local pos = r.GetSetAutomationItemInfo(h.env, i, "D_POSITION", 0, false)
  local finish = math.min(pos + r.GetSetAutomationItemInfo(h.env, i, "D_LENGTH", 0, false),
    h.keep_to or L.perf_hi or 0)
  local from = math.max(pos, h.keep_from)
  if finish - from < 0.01 then E.ai_delete(h) return end
  if from > pos then
    r.GetSetAutomationItemInfo(h.env, i, "D_STARTOFFS",
      r.GetSetAutomationItemInfo(h.env, i, "D_STARTOFFS", 0, false) + (from - pos), true)
    r.GetSetAutomationItemInfo(h.env, i, "D_POSITION", from, true)
  end
  r.GetSetAutomationItemInfo(h.env, i, "D_LENGTH", finish - from, true)
  r.GetSetAutomationItemInfo_String(h.env, i, "P_POOL_NAME", K.ai_kept, true)
end

function E.env_cancel(ez)
  if ez.pend then E.ai_delete(ez.pend) ez.pend = nil end
end

function E.env_stop(ez, time)
  E.env_cancel(ez)
  if ez.cur then
    if time then
      E.ai_trim(ez.cur, time)
      ez.stop_at = time
    else
      E.ai_done(ez.cur)
      ez.cur = nil
    end
  end
end

-- launching one automation clip by itself
function E.env_launch(track, name, row)
  local lane = H.lane_of(track, true)
  local env = H.env_by_name(track, name)
  local time, roll = E.launch_time(L.quantize)
  r.PreventUIRefresh(1)
  local ok = E.env_commit(lane, name, env, row, time)
  r.PreventUIRefresh(-1)
  if ok and roll then E.roll_transport(time) end
  r.UpdateArrange()
end

-- with a track's clip, the automation clips in the same row go too (Bitwig 6)
function E.env_with(lane, row, time)
  local track = H.track(lane.track_guid)
  if not track then return end
  for name, ez in pairs(lane.envs or {}) do
    if ez.slots[row] then E.env_commit(lane, name, H.env_by_name(track, name), row, time) end
  end
end

function E.env_stop_all(lane, time)
  for _, ez in pairs(lane.envs or {}) do E.env_stop(ez, time) end
end

function E.env_tick(lane, now, heard)
  for _, ez in pairs(lane.envs or {}) do
    if ez.pend and now >= ez.pend.at then
      if ez.cur then ez.retired[#ez.retired + 1] = ez.cur end
      ez.cur, ez.pend = ez.pend, nil
      if L.perf then ez.cur.keep_from = ez.cur.at end
    end
    if ez.stop_at and now >= ez.stop_at then
      if ez.cur then ez.retired[#ez.retired + 1] = ez.cur end
      ez.cur, ez.stop_at = nil, nil
    end
    if heard then
      for i = #ez.retired, 1, -1 do
        local finish = E.ai_end(ez.retired[i])
        if not finish or heard > finish + K.harvest_pad then E.ai_done(ez.retired[i]) table.remove(ez.retired, i) end
      end
      local c = ez.cur
      -- grow a running clip, but never one that is being cut off for the next (a pending
      -- clip or a stop): growing it undid the cut, and every launched clip played on
      -- (user's report with screenshot, 2026-11-27)
      local ci = c and not ez.stop_at and not ez.pend and not c.closing and E.ai_index(c)
      if ci then
        local len = r.GetSetAutomationItemInfo(c.env, ci, "D_LENGTH", 0, false)
        if c.at + len - heard < K.voice_margin then
          r.GetSetAutomationItemInfo(c.env, ci, "D_LENGTH", len + K.voice_extend, true)
        end
      end
    end
  end
end

function E.env_release(lane)
  for _, ez in pairs(lane.envs or {}) do
    E.env_cancel(ez)
    if ez.cur then E.ai_done(ez.cur) end
    for _, h in ipairs(ez.retired) do E.ai_done(h) end
    ez.cur, ez.retired, ez.stop_at = nil, {}, nil
  end
end

-- automation voices left behind by a crash, found by their pool name
function E.ai_sweep()
  for t = 0, r.CountTracks(0) - 1 do
    local track = r.GetTrack(0, t)
    for e = 0, r.CountTrackEnvelopes(track) - 1 do
      local env = r.GetTrackEnvelope(track, e)
      local guard = 0
      repeat
        local found
        for i = 0, r.CountAutomationItems(env) - 1 do
          local _, nm = r.GetSetAutomationItemInfo_String(env, i, "P_POOL_NAME", "", false)
          if nm == K.ai_voice then found = math.floor(r.GetSetAutomationItemInfo(env, i, "D_POOL_ID", 0, false)) break end
        end
        if found then E.ai_delete({ env = env, pool = found }) end
        guard = guard + 1
      until not found or guard > 32
    end
  end
end

function E.update()
  local proj = r.EnumProjects(-1)
  if proj ~= L.proj then
    L.proj = proj
    H.load()
  end
  if r.CountTracks(0) ~= L.track_count then
    L.track_count = r.CountTracks(0)
    L.tidy = true
  end
  if L.tidy then E.tidy() end
  E.edit_watch(r.time_precise())
  local cnt = r.GetProjectStateChangeCount(0)
  if cnt ~= L.state_cnt then
    L.state_cnt = cnt
    local _, str = r.GetSetMediaTrackInfo_String(r.GetMasterTrack(0), K.grid, "", false)
    if str and str ~= "" and str ~= L.seen_str then
      L.seen_str = str
      if str ~= L.saved_str then H.apply_grid(str) end
    end
    for _, lane in pairs(L.lanes) do
      for _, slot in pairs(lane.slots) do slot.missing = H.item(slot.guid) == nil or nil end
      E.sync_colours(lane)
    end
  end
  local t = r.time_precise()
  E.rec_watch(t)
  if t - L.checked > 0.5 then                       -- light: the gates, the tempo
    L.checked = t
    for _, lane in pairs(L.lanes) do E.sync_gates(lane) end
    E.tempo_watch()
  end
  local now = E.schedule_pos()
  if not now then
    if t >= L.roll_guard then
      -- stopped: nothing is waiting any more, and every track goes back to the arrangement
      local any = false
      for _, lane in pairs(L.lanes) do
        if lane.current or lane.pending or lane.owner == "launcher" or lane.switch then any = true break end
        for _, ez in pairs(lane.envs or {}) do if ez.cur or ez.pend or #ez.retired > 0 then any = true end end
      end
      if any then E.release_all() end
      if #L.perf_spans > 0 then E.perf_write() end
    end
    L.last_heard = nil
    return
  end
  local heard = E.heard_pos()
  if heard and L.last_heard and heard < L.last_heard - 0.05 then
    for _, lane in pairs(L.lanes) do E.promote_wrap(lane, heard) end
    E.run_queued()
  end
  L.last_heard = heard
  if heard and heard > (L.perf_hi or 0) then L.perf_hi = heard end
  for _, lane in pairs(L.lanes) do
    E.env_tick(lane, now, heard)
    if lane.pending and now >= lane.pending.at then
      if lane.current then lane.retired[#lane.retired + 1] = lane.current end
      lane.current = lane.pending
      lane.current.started = true
      -- the gate opened itself on this clip's line: it is not shut any more (without this
      -- the launcher thought it shut until the transport stopped, and kept it on the track)
      if lane.gate_shut and lane.gate_open_at and now >= lane.gate_open_at - 0.01 then
        lane.gate_shut, lane.gate_open_at = nil, nil
      end
      if L.perf then lane.current.perf_from = lane.current.at end
      lane.pending = nil
      E.build_wrap(lane, lane.current)
      local v, slot = lane.current, lane.slots[lane.current.row]
      if slot and slot.na and v.length and v.length > 0 then
        lane.run = { row = v.row, finish = v.at - (v.offset or 0) + v.length * (slot.na_n or 1) }
      end
    end
    local run = lane.run
    if run and not lane.pending and not lane.stop_at and now >= run.finish - math.max(1.0, E.lead()) then
      lane.run = nil
      local slot = lane.slots[run.row]
      if slot and slot.na then E.do_next(lane, run.row, slot.na, math.max(run.finish, now + E.lead())) end
    end
    if lane.switch and now >= lane.switch.at then E.apply_switch(lane) end
    if lane.stop_at and now >= lane.stop_at then
      if lane.current then lane.retired[#lane.retired + 1] = lane.current end
      lane.current, lane.stop_at = nil, nil
    end
    if heard then E.extend_voice(lane, heard) end
    E.harvest(lane, false)
  end
end

----------------------------------------------------------------------------------------------
-- drawing: previews
----------------------------------------------------------------------------------------------

-- audio: a coarse peak line, read once per clip and kept
function U.peaks(slot, n)
  local key = slot.guid .. ":" .. n
  local cached = L.peaks[key]
  local t = r.time_precise()
  if cached and (cached.ok or t - cached.at < 1) then return cached.ok and cached end
  local item = H.item(slot.guid)
  local take = item and r.GetActiveTake(item)
  if not take or r.TakeIsMIDI(take) then return nil end
  local len = r.GetMediaItemInfo_Value(item, "D_LENGTH")
  local buf = r.new_array(n * 2)
  local ret = r.GetMediaItemTake_Peaks(take, n / math.max(0.01, len), r.GetMediaItemInfo_Value(item, "D_POSITION"), 1, n, 0, buf)
  local count = math.floor(ret or 0) & 0xFFFFF
  local entry = { at = t, ok = count > 0, max = {}, min = {}, n = count }
  if count > 0 then
    local v = buf.table()
    for i = 1, count do entry.max[i], entry.min[i] = v[i], v[count + i] end
  end
  L.peaks[key] = entry
  return entry.ok and entry
end

-- MIDI: the notes as small bars, re-read when the take's notes change
function U.notes(slot)
  local item = H.item(slot.guid)
  local take = item and r.GetActiveTake(item)
  if not take or not r.TakeIsMIDI(take) then return nil end
  local cached = L.notes[slot.guid]
  if cached and cached.cnt == L.state_cnt then return cached end
  local _, hash = r.MIDI_GetHash(take, true, "")
  if cached and cached.hash == hash then cached.cnt = L.state_cnt return cached end
  local entry = { hash = hash, cnt = L.state_cnt, list = {}, lo = 127, hi = 0, len = r.GetMediaItemInfo_Value(item, "D_LENGTH") }
  local pos0 = r.GetMediaItemInfo_Value(item, "D_POSITION")
  local _, count = r.MIDI_CountEvts(take)
  for i = 0, math.min(count, 400) - 1 do
    local _, _, _, sp, ep, _, pitch = r.MIDI_GetNote(take, i)
    local s = r.MIDI_GetProjTimeFromPPQPos(take, sp) - pos0
    local e = r.MIDI_GetProjTimeFromPPQPos(take, ep) - pos0
    entry.list[#entry.list + 1] = { s, e, pitch }
    entry.lo, entry.hi = math.min(entry.lo, pitch), math.max(entry.hi, pitch)
  end
  L.notes[slot.guid] = entry
  return entry
end

function U.preview(dl, slot, x1, y1, x2, y2, col)
  if x2 - x1 < 8 or y2 - y1 < 6 then return end
  if slot.midi then
    local nt = U.notes(slot)
    if not nt or #nt.list == 0 or nt.len <= 0 then return end
    local span = math.max(12, nt.hi - nt.lo + 1)
    local nh = math.max(1, (y2 - y1) / span)
    for _, n in ipairs(nt.list) do
      local a = x1 + (x2 - x1) * math.max(0, n[1] / nt.len)
      local b = x1 + (x2 - x1) * math.min(1, n[2] / nt.len)
      if a < x2 then
        local y = y2 - (n[3] - nt.lo + 1) * nh
        r.ImGui_DrawList_AddRectFilled(dl, a, y, math.max(a + 1, b), y + math.max(1, nh - 0.5), col)
      end
    end
  else
    local n = math.max(8, math.floor(x2 - x1))
    local pk = U.peaks(slot, n)
    if not pk then return end
    local mid, half = (y1 + y2) / 2, (y2 - y1) / 2
    for i = 1, pk.n do
      local x = x1 + (i - 1) * (x2 - x1) / pk.n
      local hi, lo = math.min(1, math.abs(pk.max[i])), math.min(1, math.abs(pk.min[i]))
      r.ImGui_DrawList_AddLine(dl, x, mid - hi * half, x, mid + lo * half + 0.5, col, 1)
    end
  end
end

----------------------------------------------------------------------------------------------
-- drawing: pieces
----------------------------------------------------------------------------------------------

function U.blink()
  local pos = E.heard_pos()
  if pos then return (r.TimeMap2_timeToQN(0, pos) % 1) < 0.5 end
  return (r.time_precise() * 2) % 1 < 0.5
end

function U.ret_icon(dl, cx, cy, col)              -- Bitwig's return arrow: an open circle
  r.ImGui_DrawList_PathArcTo(dl, cx, cy, 4.5, -2.6, 2.2, 14)
  r.ImGui_DrawList_PathStroke(dl, col, 0, 1.5)
  r.ImGui_DrawList_AddTriangleFilled(dl, cx - 6.6, cy - 4.4, cx - 1.8, cy - 4.6, cx - 4.4, cy - 0.6, col)
end

function U.key(id, x, y, w, h, text, on, on_col)
  r.ImGui_SetCursorScreenPos(ctx, x, y)
  local hit = r.ImGui_InvisibleButton(ctx, id, w, h)
  local hov = r.ImGui_IsItemHovered(ctx)
  local dl = r.ImGui_GetWindowDrawList(ctx)
  local top, bot = C.key_top, C.key_bot
  if on then top, bot = on_col, on_col elseif hov then top, bot = C.seg_hi, 0x333333FF end
  r.ImGui_DrawList_AddRectFilled(dl, x, y, x + w, y + h, C.key_edge, 2)
  r.ImGui_DrawList_AddRectFilledMultiColor(dl, x + 1, y + 1, x + w - 1, y + h - 1, top, top, bot, bot)
  local ink = on and 0x141414FF or C.text
  if text == "rec" then
    r.ImGui_DrawList_AddCircleFilled(dl, x + w / 2, y + h / 2, 3.2, on and 0x141414FF or C.arm)
  elseif text == "eye" then                         -- an eye: the hidden tracks shown or not
    r.ImGui_DrawList_AddEllipse(dl, x + w / 2, y + h / 2, 5.5, 3.2, ink, 0, 0, 1.2)
    r.ImGui_DrawList_AddCircleFilled(dl, x + w / 2, y + h / 2, 1.7, ink)
  elseif text == "tcp" then                         -- a track panel: a frame, rows at its left
    r.ImGui_DrawList_AddRect(dl, x + 3, y + 4, x + w - 3, y + h - 4, ink, 1, 0, 1)
    for k = 0, 2 do
      r.ImGui_DrawList_AddRectFilled(dl, x + 5, y + 6 + k * 2.5, x + 9, y + 7 + k * 2.5, ink)
    end
  else
    local tw, th = r.ImGui_CalcTextSize(ctx, text)
    r.ImGui_DrawList_AddText(dl, x + (w - tw) / 2, y + (h - th) / 2, ink, text)
  end
  return hit
end

function U.tip(text) if r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, text) end end

-- the track header: colour strip, name, rec / S / M, the volume field and a meter
function U.header(dl, track, x, y, w, h, y_lo, y_hi)
  local sel = r.IsTrackSelected(track)
  local col = H.rgba(r.GetTrackColor(track)) or 0x5A5A5AFF
  r.ImGui_DrawList_AddRectFilled(dl, x, y, x + w, y + h, sel and C.head_sel or C.head)
  r.ImGui_DrawList_AddRectFilled(dl, x, y, x + 5, y + h, col)
  r.ImGui_DrawList_AddRectFilled(dl, x, y + h - 1, x + w, y + h, C.seam)
  if sel then r.ImGui_DrawList_AddRect(dl, x, y, x + w, y + h, 0x8A8A8AFF) end
  local idx = math.floor(r.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER"))
  -- the name; the whole header selects the track (see U.header_hit)
  local name_w = L.headers and w - 92 or w - 12
  if y + 18 > y_lo and y < y_hi then
    r.ImGui_DrawList_PushClipRect(dl, x + 6, math.max(y, y_lo), x + 6 + name_w, math.min(y + h, y_hi), true)
    r.ImGui_PushFont(ctx, font_bold, 12)
    r.ImGui_DrawList_AddText(dl, x + 9, y + 3, C.text, H.track_name(track))
    r.ImGui_PopFont(ctx)
    r.ImGui_DrawList_PopClipRect(dl)
  end
  if L.headers then U.header_controls(dl, track, x, y, w, h, y_lo, y_hi, idx) end
  U.header_hit(track, x, y, w, h, y_lo, y_hi, idx)
end

-- Clicking a header selects its track (Ctrl: add / remove, Shift: a range), as the track
-- panel does; its bottom edge drags the track's height. Submitted after the keys, so a key
-- keeps its own clicks.
function U.header_hit(track, x, y, w, h, y_lo, y_hi, idx)
  local ry1, ry2 = math.max(y + h - 4, y_lo), math.min(y + h + 1, y_hi)
  if ry2 - ry1 >= 2 then
    r.ImGui_SetCursorScreenPos(ctx, x, ry1)
    r.ImGui_InvisibleButton(ctx, "##rz" .. idx, w, ry2 - ry1)
    if r.ImGui_IsItemHovered(ctx) or r.ImGui_IsItemActive(ctx) then
      r.ImGui_SetMouseCursor(ctx, r.ImGui_MouseCursor_ResizeNS())
    end
    if r.ImGui_IsItemActivated(ctx) then L.rz = { track = track, h0 = r.GetMediaTrackInfo_Value(track, "I_TCPH") } end
    if r.ImGui_IsItemActive(ctx) and L.rz and L.rz.track == track then
      local _, dy = r.ImGui_GetMouseDragDelta(ctx, 0)
      local nh = math.max(20, math.floor(L.rz.h0 + dy / (L.scale or 1) + 0.5))
      if nh ~= L.rz.last then
        L.rz.last = nh
        r.SetMediaTrackInfo_Value(track, "I_HEIGHTOVERRIDE", nh)
        r.TrackList_AdjustWindows(false)
      end
    end
    U.tip("Drag: track height")
  end
  local by1, by2 = math.max(y, y_lo), math.min(y + h - 4, y_hi)
  if by2 - by1 < 2 then return end
  r.ImGui_SetCursorScreenPos(ctx, x, by1)
  if r.ImGui_InvisibleButton(ctx, "##hd" .. idx, w, by2 - by1) then
    local mods = r.ImGui_GetKeyMods(ctx)
    if (mods & r.ImGui_Mod_Ctrl()) ~= 0 then
      r.SetTrackSelected(track, not r.IsTrackSelected(track))
    elseif (mods & r.ImGui_Mod_Shift()) ~= 0 and L.anchor and H.valid_track(L.anchor) then
      local a = r.GetMediaTrackInfo_Value(L.anchor, "IP_TRACKNUMBER")
      local b = r.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER")
      for i = math.min(a, b) - 1, math.max(a, b) - 1 do
        local t = r.GetTrack(0, i)
        if t and not H.is_lane_track(t) then r.SetTrackSelected(t, true) end
      end
    else
      r.SetOnlyTrackSelected(track)
    end
    if (mods & r.ImGui_Mod_Shift()) == 0 then L.anchor = track end
    r.SetMixerScroll(track)
    r.SetCursorContext(0, nil)             -- the track panel's context: the inspector shows the track
  end
  -- double-click: rename the track, as in the track panel (not the master: it has no name)
  if idx >= 0 and r.ImGui_IsItemHovered(ctx) and r.ImGui_IsMouseDoubleClicked(ctx, 0) then
    local _, cur = r.GetSetMediaTrackInfo_String(track, "P_NAME", "", false)
    L.rename = { kind = "track", track = track, buf = cur or "", first = true }
  end
  -- right-click: REAPER's own track panel menu, for the selection as the track panel does.
  -- On the RELEASE: a native menu opened while the button is still down swallows the
  -- button-up, ImGui never sees it and keeps hold of the mouse (REAPER took no clicks
  -- until one landed outside REAPER; user's report, 2026-11-26)
  if r.ImGui_IsItemHovered(ctx) and r.ImGui_IsMouseReleased(ctx, 1) then
    if not r.IsTrackSelected(track) then r.SetOnlyTrackSelected(track) end
    L.popup = { name = "track_panel", ctx = track }
  end
end

-- REAPER's context menus (ShowPopupMenu) block until closed, so they open between frames,
-- never inside one (as the file dialog)
function U.popup()
  local p = L.popup
  if not p then return end
  -- never while a mouse button is still down (see U.header_hit)
  if r.JS_Mouse_GetState and r.JS_Mouse_GetState(3) ~= 0 then return end
  if r.ImGui_IsMouseDown(ctx, 0) or r.ImGui_IsMouseDown(ctx, 1) then return end
  L.popup = nil
  if not r.ShowPopupMenu then return end
  local x, y = r.GetMousePosition()
  r.ShowPopupMenu(p.name, x, y, r.GetMainHwnd(), p.ctx)
end

-- rec / S / M at the top right, the volume field under them, the meter at the edge
function U.header_controls(dl, track, x, y, w, h, y_lo, y_hi, idx)
  local kx = x + w - 84
  if idx < 0 then                                    -- the master: mute only
    if y + 2 >= y_lo and y + 16 <= y_hi then
      local mute = r.GetMediaTrackInfo_Value(track, "B_MUTE") > 0.5
      if U.key("##mu" .. idx, kx + 46, y + 2, 22, 14, "M", mute, C.mute) then
        r.SetMediaTrackInfo_Value(track, "B_MUTE", mute and 0 or 1)
      end
    end
  elseif y + 2 >= y_lo and y + 16 <= y_hi then
    local arm = r.GetMediaTrackInfo_Value(track, "I_RECARM") > 0.5
    if U.key("##ra" .. idx, kx, y + 2, 22, 14, "rec", arm, C.arm) then
      r.SetMediaTrackInfo_Value(track, "I_RECARM", arm and 0 or 1)
    end
    local solo = r.GetMediaTrackInfo_Value(track, "I_SOLO") > 0.5
    if U.key("##so" .. idx, kx + 23, y + 2, 22, 14, "S", solo, C.solo) then
      r.SetMediaTrackInfo_Value(track, "I_SOLO", solo and 0 or 2)
    end
    local mute = r.GetMediaTrackInfo_Value(track, "B_MUTE") > 0.5
    if U.key("##mu" .. idx, kx + 46, y + 2, 22, 14, "M", mute, C.mute) then
      r.SetMediaTrackInfo_Value(track, "B_MUTE", mute and 0 or 1)
    end
  end
  -- the volume field: drag (Shift: fine), double-click for 0 dB
  if h >= 38 and y + 19 >= y_lo and y + 35 <= y_hi then
    local fx, fy, fw = kx, y + 19, 68
    r.ImGui_SetCursorScreenPos(ctx, fx, fy)
    r.ImGui_InvisibleButton(ctx, "##vol" .. idx, fw, 16)
    local vol = r.GetMediaTrackInfo_Value(track, "D_VOL")
    local db = vol > 0 and 20 * math.log(vol, 10) or -150
    if r.ImGui_IsItemActive(ctx) then
      local _, dy = r.ImGui_GetMouseDragDelta(ctx, 0)
      local dx = select(1, r.ImGui_GetMouseDragDelta(ctx, 0))
      local step = (r.ImGui_GetKeyMods(ctx) & r.ImGui_Mod_Shift()) ~= 0 and 0.02 or 0.15
      local d = (dx - dy) * step
      if d ~= 0 then
        db = math.max(-90, math.min(12, db + d))
        r.SetMediaTrackInfo_Value(track, "D_VOL", 10 ^ (db / 20))
        r.ImGui_ResetMouseDragDelta(ctx, 0)
      end
    end
    if r.ImGui_IsItemHovered(ctx) and r.ImGui_IsMouseDoubleClicked(ctx, 0) then
      r.SetMediaTrackInfo_Value(track, "D_VOL", 1)
    end
    r.ImGui_DrawList_AddRectFilled(dl, fx, fy, fx + fw, fy + 16, C.field, 2)
    local text = db <= -149 and "-inf dB" or string.format("%.1f dB", db)
    local tw, th = r.ImGui_CalcTextSize(ctx, text)
    r.ImGui_DrawList_AddText(dl, fx + fw - tw - 5, fy + (16 - th) / 2, C.value, text)
  end
  -- meter: two thin bars in a dark slot at the right edge
  local mx = x + w - 12
  local top, bot = math.max(y + 2, y_lo), math.min(y + h - 3, y_hi)
  if bot - top > 4 then
    r.ImGui_DrawList_AddRectFilled(dl, mx, top, mx + 9, bot, C.field)
    for ch = 0, 1 do
      local amp = r.Track_GetPeakInfo(track, ch)
      local db = amp > 0 and 20 * math.log(amp, 10) or -90
      local f = math.max(0, math.min(1, (db + 60) / 66))
      if f > 0 then
        local by = bot - (bot - top) * f
        local mc = db > 0 and C.meter_clip or (db > -6 and C.meter_hot or C.meter)
        r.ImGui_DrawList_AddRectFilled(dl, mx + 1 + ch * 4, by, mx + 4 + ch * 4, bot, mc)
      end
    end
  end
end

-- one slot: a clip in its colour with the play triangle and a preview, or an empty slot
function U.slot(dl, track, lane, row, x, y, w, h, y_lo, y_hi)
  local slot = lane and lane.slots[row]
  local cy1, cy2 = math.max(y, y_lo), math.min(y + h - 1, y_hi)
  if cy2 - cy1 < 2 then return end
  local id = "##s" .. math.floor(r.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER")) .. "_" .. row
  local _, hov, made = U.hit(id, x, cy1, w - 1, cy2 - cy1)
  if made then U.accept_drop(track, row) end
  local mx, my = r.ImGui_GetMousePos(ctx)
  L.cells[#L.cells + 1] = { x1 = math.max(x, L.cx1), y1 = cy1, x2 = math.min(x + w, L.cx2), y2 = cy2, track = track, row = row }
  if hov then L.hover = { track = track, row = row } end
  local playing = lane and lane.current and lane.current.row == row and lane.current.started and not lane.stop_at
  local queued = lane and ((lane.pending and lane.pending.row == row) or (lane.queued and lane.queued.row == row))
  local mark = E.rec_mark(track, row)
  r.ImGui_DrawList_PushClipRect(dl, x, cy1, x + w - 1, cy2, true)
  if mark then
    U.rec_slot(dl, mark, x, y, w, h, hov)
    if hov and r.ImGui_IsMouseClicked(ctx, 0) and not mark.to then E.rec_stop(mark) end
  elseif slot then
    local col = H.slot_colour(lane, slot)
    if slot.missing then col = 0x4A4A4AFF end
    local fill = hov and H.shade(col, 1.08) or col
    r.ImGui_DrawList_AddRectFilled(dl, x, y, x + w - 1, y + h - 1, fill)
    local ink = H.light(col) and 0x1A1A1AFF or 0xF0F0F0FF
    -- name row, then the preview in a darker shade of the clip colour
    r.ImGui_DrawList_AddText(dl, x + 18, y + 2, ink, slot.name or "Clip")
    if slot.na then                                  -- a Next Action is set: a small arrow
      local ax, ay = x + w - 10, y + 8
      r.ImGui_DrawList_AddRectFilled(dl, ax - 6, ay - 6, x + w - 2, ay + 6, col)
      r.ImGui_DrawList_AddLine(dl, ax - 4, ay, ax + 3, ay, ink, 1.3)
      r.ImGui_DrawList_AddTriangleFilled(dl, ax + 1, ay - 3, ax + 1, ay + 3, ax + 5, ay, ink)
    end
    if h >= 30 then U.preview(dl, slot, x + 2, y + 16, x + w - 3, y + h - 3, H.shade(col, 0.55)) end
    -- the play triangle: a light box while playing, blinking while queued
    local box = playing or (queued and U.blink())
    -- only the triangle's own box launches (a wide strip down the clip started it by accident)
    local on_play = hov and mx >= x and mx < x + 18 and my >= y and my < y + 18
    if box then r.ImGui_DrawList_AddRectFilled(dl, x + 2, y + 2, x + 15, y + 15, 0xF0F0F0FF, 2)
    elseif on_play then r.ImGui_DrawList_AddRectFilled(dl, x + 2, y + 2, x + 15, y + 15, H.light(col) and 0x00000033 or 0xFFFFFF40, 2) end
    local tc = box and 0x1A1A1AFF or ink
    r.ImGui_DrawList_AddTriangleFilled(dl, x + 6, y + 4.5, x + 6, y + 12.5, x + 12.5, y + 8.5, tc)
    if playing then
      local v = lane.current
      local heard = E.heard_pos()
      if heard and v.length and v.length > 0 then
        local f = ((heard - v.at + (v.offset or 0)) % v.length) / v.length
        local px = x + 1 + (w - 3) * f
        r.ImGui_DrawList_AddLine(dl, px, y + 1, px, y + h - 2, 0xFFFFFFCC, 1)
      end
    end
    if L.sel and L.sel.lane == lane and L.sel.row == row then
      r.ImGui_DrawList_AddRect(dl, x, y, x + w - 1, y + h - 1, C.sel, 0, 0, 1)
    end
    -- clicks: the triangle launches, the body selects (and starts a drag)
    if hov and r.ImGui_IsMouseClicked(ctx, 0) then
      if on_play then
        local alt = (r.ImGui_GetKeyMods(ctx) & r.ImGui_Mod_Alt()) ~= 0
        E.launch(lane, row, alt)
        L.held = { lane = lane, row = row }
      else
        L.sel = { lane = lane, row = row }
        L.drag = { lane = lane, row = row, x = mx, y = my }
        -- the clip becomes REAPER's selected item, in the arrange's context, so the TK Bit
        -- inspector (and anything else that follows the selection) shows this clip
        local it = H.item(slot.guid)
        if it and (r.CountSelectedMediaItems(0) ~= 1 or r.GetSelectedMediaItem(0, 0) ~= it) then
          H.unselect_items()            -- this clip alone, never one of several
          r.SetMediaItemSelected(it, true)
          r.UpdateArrange()
        end
        -- REAPER's context (for the inspector) only once the mouse is let go: setting it
        -- moves the focus to the arrange, which took the mouse from a drag that had just begun
        L.ctx_after = 1
        if r.ImGui_IsMouseDoubleClicked(ctx, 0) then
          L.drag = nil
          L.want_edit = { lane = lane, row = row }
        end
      end
    end
  else
    r.ImGui_DrawList_AddRectFilled(dl, x, y, x + w - 1, y + h - 1, C.empty)
    local armed = r.GetMediaTrackInfo_Value(track, "I_RECARM") > 0.5
    local cy = y + math.min(h, 20) / 2
    -- as Bitwig: every empty slot shows the stop square, or a round record button (same grey)
    -- on an armed track; lighter under the mouse
    local on_plus = hov and mx > x + w - 22
    local mark = (hov and not on_plus) and C.square_hi or C.square
    if armed then
      r.ImGui_DrawList_AddCircleFilled(dl, x + 9, cy, 3.5, (hov and not on_plus) and C.square_hi or 0x7A7A7AFF)
    else
      r.ImGui_DrawList_AddRectFilled(dl, x + 6, cy - 3, x + 12, cy + 3, mark)
    end
    -- "+" under the mouse only: the arrange's selected items go in from here, or a file
    if hov then
      local px = x + w - 13
      local pc = on_plus and C.text or C.dim
      r.ImGui_DrawList_AddLine(dl, px - 4, cy, px + 4, cy, pc, 1.5)
      r.ImGui_DrawList_AddLine(dl, px, cy - 4, px, cy + 4, pc, 1.5)
      if on_plus then
        U.tip(r.CountSelectedMediaItems(0) > 0 and "Add the selected item(s) from here" or "Add a file")
      end
    end
    if hov and r.ImGui_IsMouseClicked(ctx, 0) then
      if on_plus then
        if r.CountSelectedMediaItems(0) > 0 then E.add_selected(track, row)
        else L.want_file = { track = track, row = row } end
      elseif armed then
        E.rec_start(track, row)
      else
        E.stop_track(track)
      end
    end
  end
  r.ImGui_DrawList_PopClipRect(dl)
  if hov and r.ImGui_IsMouseClicked(ctx, 1) then L.menu = { kind = slot and "slot" or "empty", track = track, lane = lane, row = row } end
  if hov and slot then
    U.tip((slot.name or "Clip") .. (slot.missing and "\n(gone from the project)" or "")
      .. "\nTriangle: launch   Body: select / drag (Ctrl: copy)   Right-click: menu")
  end
  r.ImGui_DrawList_AddRectFilled(dl, x + w - 1, cy1, x + w, cy2, C.seam)
end

----------------------------------------------------------------------------------------------
-- drawing: the panel
----------------------------------------------------------------------------------------------

-- where the arrange's track area starts, in this window's coordinates, and the ratio of
-- REAPER's pixels to ReaImGui's (HiDPI); needs js_ReaScriptAPI for the exact line-up
function U.arrange_geometry()
  local scale = 1
  if r.ImGui_PointConvertNative then
    local _, y0 = r.ImGui_PointConvertNative(ctx, 0, 0, false)
    local _, y1 = r.ImGui_PointConvertNative(ctx, 0, 1000, false)
    scale = math.abs(y1 - y0) / 1000
    if scale <= 0 then scale = 1 end
  end
  if not (r.JS_Window_FindChildByID and r.JS_Window_GetClientRect and r.ImGui_PointConvertNative) then return nil, scale end
  if not L.arrange_hwnd or not r.ValidatePtr(L.arrange_hwnd, "HWND*") then
    L.arrange_hwnd = r.JS_Window_FindChildByID(r.GetMainHwnd(), 1000)
  end
  if not L.arrange_hwnd then return nil, scale end
  local ok, left, top = r.JS_Window_GetClientRect(L.arrange_hwnd)
  if not ok then return nil, scale end
  local _, y = r.ImGui_PointConvertNative(ctx, left, top, false)
  return y, scale
end

-- the visible tracks in order: shown in the track panel, not inside a collapsed folder
function U.layout()
  local cnt = L.state_cnt or r.GetProjectStateChangeCount(0)
  local lay = L.lay
  if lay and lay.cnt == cnt and lay.ntracks == r.CountTracks(0) then
    -- folders folded or opened (whether that moves the count is not known): only the folder
    -- tracks are asked, so this stays a handful of reads
    local same = true
    for f, v in pairs(lay.folds) do
      if not r.ValidatePtr2(0, f, "MediaTrack*") or r.GetMediaTrackInfo_Value(f, "I_FOLDERCOMPACT") ~= v then same = false break end
    end
    if same then return lay end
  end
  lay = { cnt = cnt, ntracks = r.CountTracks(0), tracks = {}, envs = {}, lanes_shown = false, folds = {} }
  local seen_lane = false
  for i = 0, lay.ntracks - 1 do
    local track = r.GetTrack(0, i)
    if H.is_lane_track(track) then
      if not seen_lane then
        seen_lane = true
        lay.lanes_shown = r.GetMediaTrackInfo_Value(track, "B_SHOWINTCP") > 0.5
      end
    elseif r.GetMediaTrackInfo_Value(track, "B_SHOWINTCP") > 0.5 then
      if r.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH") > 0.5 then
        lay.folds[track] = r.GetMediaTrackInfo_Value(track, "I_FOLDERCOMPACT")
      end
      local hidden, p = false, r.GetParentTrack(track)
      while p do
        if r.GetMediaTrackInfo_Value(p, "I_FOLDERCOMPACT") >= 2 then hidden = true break end
        p = r.GetParentTrack(p)
      end
      if not hidden then lay.tracks[#lay.tracks + 1] = track end
    end
  end
  for _, track in ipairs(lay.tracks) do U.layout_envs(lay, track) end
  U.layout_envs(lay, r.GetMasterTrack(0))
  L.lay = lay
  return lay
end
function U.layout_envs(lay, track)
  local list = {}
  for i = 0, r.CountTrackEnvelopes(track) - 1 do
    local env = r.GetTrackEnvelope(track, i)
    local _, name = r.GetEnvelopeName(env)
    list[#list + 1] = { env, name or "?" }
  end
  lay.envs[track] = list
end

function U.rows()
  local list = {}
  for _, track in ipairs(U.layout().tracks) do
    local h = r.GetMediaTrackInfo_Value(track, "I_TCPH")
    if h > 0 then list[#list + 1] = { track, r.GetMediaTrackInfo_Value(track, "I_TCPY"), h } end
  end
  if (r.GetMasterTrackVisibility() & 1) == 1 then
    local master = r.GetMasterTrack(0)
    local h = r.GetMediaTrackInfo_Value(master, "I_TCPH")
    if h > 0 then list[#list + 1] = { master, r.GetMediaTrackInfo_Value(master, "I_TCPY"), h, true } end
  end
  return list
end

-- The master's row, as the master column of Bitwig's mix view: its header (M, volume,
-- meter), then a scene launch button in every column, with "stop all" and "all back to the
-- arrangement" at the ends
function U.master_row(dl, track, x, y, w, h, grid_x, ret_x, right, y_lo, y_hi)
  U.header(dl, track, x, y, w, h, y_lo, y_hi)
  local sy1, sy2 = math.max(y, y_lo), math.min(y + h - 1, y_hi)
  if sy2 - sy1 <= 2 then return end
  local cy = y + math.min(h, 20) / 2
  r.ImGui_DrawList_AddRectFilled(dl, x + w, y, grid_x, y + h, C.stopcol)
  r.ImGui_SetCursorScreenPos(ctx, x + w, sy1)
  if r.ImGui_InvisibleButton(ctx, "##mstop", grid_x - x - w, sy2 - sy1) then E.stop_all() end
  local shov = r.ImGui_IsItemHovered(ctx)
  r.ImGui_DrawList_AddRectFilled(dl, x + w + 5, cy - 4, x + w + 13, cy + 4, shov and C.square_hi or C.square)
  U.tip("Stop every clip (on the launch grid)")
  r.ImGui_DrawList_AddRectFilled(dl, grid_x, y, ret_x, y + h, C.bg)
  r.ImGui_DrawList_PushClipRect(dl, L.cx1, sy1, L.cx2, sy2, true)
  for row = L.row_first, L.row_last do
    local sx = L.col_x0 + (row - 1) * K.scene_w
    local clicked, hov = U.hit("##msc" .. row, sx, sy1, K.scene_w - 1, sy2 - sy1)
    local sc = L.scenes[row] or {}
    r.ImGui_DrawList_AddRectFilled(dl, sx, y, sx + K.scene_w - 1, y + h - 1, hov and 0x3A3A3AFF or 0x2A2A2AFF)
    if sc.color then r.ImGui_DrawList_AddRectFilled(dl, sx, y, sx + 3, y + h - 1, sc.color) end
    r.ImGui_DrawList_AddTriangleFilled(dl, sx + 6, cy - 4.5, sx + 6, cy + 4.5, sx + 13, cy, hov and C.text or C.icon)
    r.ImGui_DrawList_PushClipRect(dl, sx, sy1, sx + K.scene_w - 3, sy2, true)
    local _, th = r.ImGui_CalcTextSize(ctx, "S")
    r.ImGui_DrawList_AddText(dl, sx + 18, cy - th / 2, hov and C.text or C.dim, H.scene_name(row))
    r.ImGui_DrawList_PopClipRect(dl)
    r.ImGui_DrawList_AddRectFilled(dl, sx + K.scene_w - 1, y, sx + K.scene_w, y + h, C.seam)
    if clicked then E.launch_scene(row) end
    if hov and r.ImGui_IsMouseClicked(ctx, 1) then L.menu = { kind = "scene", row = row } end
    if hov then U.tip("Launch " .. H.scene_name(row)) end
  end
  r.ImGui_DrawList_PopClipRect(dl)
  r.ImGui_DrawList_AddRectFilled(dl, ret_x, y, right, y + h, C.retcol)
  r.ImGui_SetCursorScreenPos(ctx, ret_x, sy1)
  if r.ImGui_InvisibleButton(ctx, "##mret", right - ret_x, sy2 - sy1) then E.back_all() end
  local any = false
  for _, lane in pairs(L.lanes) do if E.launcher_owns(lane) then any = true break end end
  U.ret_icon(dl, ret_x + K.ret_w / 2, cy, any and C.accent or (r.ImGui_IsItemHovered(ctx) and C.text or C.icon))
  U.tip("Every track back to the arrangement (at once)")
end

-- a track's envelopes that have a lane of their own under it, as Bitwig gives automation a
-- row in the launcher: { env, y offset from the track, height }
function U.env_rows(track, track_h)
  local list = {}
  for _, e in ipairs(U.layout().envs[track] or {}) do
    local env = e[1]
    local ey = r.GetEnvelopeInfo_Value(env, "I_TCPY")
    local eh = r.GetEnvelopeInfo_Value(env, "I_TCPH")
    if eh > 0 and ey >= track_h - 1 then list[#list + 1] = { env, ey, eh, e[2] } end
  end
  return list
end

-- an envelope's row: its name (and the plug-in's, as Bitwig's "Cutoff Frequency / Filter")
-- in the header, the track colour carried down the strip, empty dark slots
-- the envelope's value where the play cursor (or the edit cursor) is, as 0..1 for its bar
function U.env_value(env, name)
  local pos = E.heard_pos() or r.GetCursorPosition()
  local _, v = r.Envelope_Evaluate(env, pos, 0, 0)
  v = r.ScaleFromEnvelopeMode(r.GetEnvelopeScalingMode(env), v or 0)
  local n = (name or ""):lower()
  if n:find("^volume") or n:find("^trim") or n:find("send volume") then
    local db = v > 0 and 20 * math.log(v, 10) or -90
    return math.max(0, math.min(1, (db + 60) / 66))
  elseif n:find("^pan") or n:find("^width") or n:find("send pan") then
    return math.max(0, math.min(1, (v + 1) / 2))
  end
  return math.max(0, math.min(1, v))
end

-- an envelope lane's height lives in its chunk (LANEHEIGHT height compact); nothing in the API sets it
function U.env_height(env, nh)
  local ok, chunk = r.GetEnvelopeStateChunk(env, "", false)
  if not ok or chunk == "" then return end
  local new, n = chunk:gsub("\n%s*LANEHEIGHT %-?%d+ (%-?%d+)", "\nLANEHEIGHT " .. nh .. " %1", 1)
  if n == 0 then new = chunk:gsub("\n", "\nLANEHEIGHT " .. nh .. " 0\n", 1) end
  r.SetEnvelopeStateChunk(env, new, false)
  r.TrackList_AdjustWindows(false)
  r.UpdateArrange()
end

-- An envelope's row, drawn as Bitwig draws an automation lane in the launcher: like a track
-- row. The header has the track's strip, the parameter (the plug-in under it) and a standing
-- value bar where the track has its meter; then a stop square, the slots and the return arrow.
function U.env_row(dl, track, env, x, y, w, h, grid_x, ret_x, right, y_lo, y_hi, name)
  local col = H.rgba(r.GetTrackColor(track)) or 0x5A5A5AFF
  if not name then name = select(2, r.GetEnvelopeName(env)) end
  local sel = r.GetSelectedEnvelope(0) == env
  -- darker than a track's header, as Bitwig's automation lanes (the slots are not)
  r.ImGui_DrawList_AddRectFilled(dl, x, y, x + w, y + h, sel and 0x2E2E2EFF or 0x262626FF)
  r.ImGui_DrawList_AddRectFilled(dl, x, y, x + 5, y + h, col)
  r.ImGui_DrawList_AddRectFilled(dl, x, y + h - 1, x + w, y + h, C.seam)
  local param, plug = (name or ""):match("^(.-)%s*/%s*(.+)$")
  r.ImGui_DrawList_PushClipRect(dl, x + 6, math.max(y, y_lo), x + w - 16, math.min(y + h, y_hi), true)
  r.ImGui_PushFont(ctx, font_bold, 12)
  r.ImGui_DrawList_AddText(dl, x + 12, y + 4, C.text, param or name or "")
  r.ImGui_PopFont(ctx)
  if plug and h >= 30 then r.ImGui_DrawList_AddText(dl, x + 12, y + 19, C.dim, plug) end
  r.ImGui_DrawList_PopClipRect(dl)
  -- the value bar: a dark slot, brown up to the value with an orange edge on top (Bit's bars)
  local bx, top, bot = x + w - 12, math.max(y + 3, y_lo), math.min(y + h - 4, y_hi)
  if bot - top > 4 then
    r.ImGui_DrawList_AddRectFilled(dl, bx, top, bx + 9, bot, C.field)
    local f = U.env_value(env, name)
    local vy = (y + h - 4) - (h - 7) * f
    if vy < bot then
      r.ImGui_DrawList_AddRectFilled(dl, bx + 1, math.max(vy, top), bx + 8, bot, 0x562202FF)
      if vy >= top then r.ImGui_DrawList_AddRectFilled(dl, bx + 1, vy, bx + 8, vy + 2, C.accent) end
    end
  end
  -- the bottom edge drags the lane's height (before the header's own button, so it wins)
  local ry1, ry2 = math.max(y + h - 4, y_lo), math.min(y + h + 1, y_hi)
  if ry2 - ry1 >= 2 then
    r.ImGui_SetCursorScreenPos(ctx, x, ry1)
    r.ImGui_InvisibleButton(ctx, "##erz" .. tostring(env), w, ry2 - ry1)
    if r.ImGui_IsItemHovered(ctx) or r.ImGui_IsItemActive(ctx) then
      r.ImGui_SetMouseCursor(ctx, r.ImGui_MouseCursor_ResizeNS())
    end
    if r.ImGui_IsItemActivated(ctx) then L.erz = { env = env, h0 = r.GetEnvelopeInfo_Value(env, "I_TCPH") } end
    if r.ImGui_IsItemActive(ctx) and L.erz and L.erz.env == env then
      local _, dy = r.ImGui_GetMouseDragDelta(ctx, 0)
      local nh = math.max(16, math.floor(L.erz.h0 + dy / (L.scale or 1) + 0.5))
      if nh ~= L.erz.last then
        L.erz.last = nh
        U.env_height(env, nh)
      end
    end
    U.tip("Drag: lane height")
  end
  -- the header: click selects the envelope, right-click is REAPER's envelope menu
  local hy1, hy2 = math.max(y, y_lo), math.min(y + h - 4, y_hi)
  if hy2 - hy1 >= 2 then
    r.ImGui_SetCursorScreenPos(ctx, x, hy1)
    if r.ImGui_InvisibleButton(ctx, "##eh" .. tostring(env), w, hy2 - hy1) then
      r.SetCursorContext(2, env)
      r.UpdateArrange()
    end
    if r.ImGui_IsItemHovered(ctx) and r.ImGui_IsMouseReleased(ctx, 1) then
      r.SetCursorContext(2, env)
      L.popup = { name = "envelope", ctx = env }
    end
  end
  local lane = H.lane_of(track, false)
  local ez = lane and H.env_lane(lane, name, false)
  local running = ez and (ez.cur or ez.pend)
  local cy = y + math.min(h, 20) / 2
  -- stop square: lit while an automation clip plays
  r.ImGui_DrawList_AddRectFilled(dl, x + w, y, grid_x, y + h, C.stopcol)
  if hy2 - hy1 > 2 then
    r.ImGui_SetCursorScreenPos(ctx, x + w, hy1)
    if r.ImGui_InvisibleButton(ctx, "##est" .. tostring(env), grid_x - x - w, hy2 - hy1) and ez then
      E.env_stop(ez, E.schedule_pos() and E.boundary_after(E.schedule_pos(), false) or nil)
    end
    local shov = r.ImGui_IsItemHovered(ctx)
    local sc = (ez and ez.stop_at and U.blink()) and C.accent or ((running or shov) and C.square_hi or C.square)
    r.ImGui_DrawList_AddRectFilled(dl, x + w + 5, cy - 4, x + w + 13, cy + 4, sc)
    U.tip("Stop this automation clip")
  end
  r.ImGui_DrawList_AddRectFilled(dl, grid_x, y, ret_x, y + h, C.bg)
  r.ImGui_DrawList_PushClipRect(dl, L.cx1, y_lo, L.cx2, y_hi, true)
  for row = L.row_first, L.row_last do
    U.env_slot(dl, track, lane, ez, name, env, row, L.col_x0 + (row - 1) * K.scene_w, y, K.scene_w, h, y_lo, y_hi)
  end
  r.ImGui_DrawList_PopClipRect(dl)
  -- return arrow: orange while a launcher clip overrides this envelope; click = the
  -- envelope's own automation again, at once
  r.ImGui_DrawList_AddRectFilled(dl, ret_x, y, right, y + h, C.retcol)
  r.ImGui_DrawList_AddRectFilled(dl, ret_x, y + h - 1, right, y + h, C.seam)
  if hy2 - hy1 > 2 then
    r.ImGui_SetCursorScreenPos(ctx, ret_x, hy1)
    if r.ImGui_InvisibleButton(ctx, "##ert" .. tostring(env), right - ret_x, hy2 - hy1) and ez and running then
      local now = E.schedule_pos()
      E.env_stop(ez, now and now + K.min_lead or nil)
    end
    local rhov = r.ImGui_IsItemHovered(ctx)
    U.ret_icon(dl, ret_x + K.ret_w / 2, cy, running and C.accent or (rhov and C.text or C.icon))
    U.tip(running and "A launcher clip plays this envelope: click for its own automation again" or "This envelope plays its own automation")
  end
end

-- a submenu with one of Q / play modes / releases; with `project`, "Project setting" (nil)
-- comes first. set(v) is called with the picked value.
function U.pick_menu(label, list, current, project, set)
  if not r.ImGui_BeginMenu(ctx, label) then return end
  if project and r.ImGui_MenuItem(ctx, "Project setting", nil, current == nil) then set(nil) H.save() end
  local items = list == "q" and QUANT or LISTS[list]
  for _, e in ipairs(items) do
    if r.ImGui_MenuItem(ctx, e[2], nil, current == e[1]) then set(e[1]) H.save() end
  end
  r.ImGui_EndMenu(ctx)
end

-- Bit's palette as swatches; false = the track's colour
function U.palette(slot)
  if not r.ImGui_BeginMenu(ctx, "Colour") then return end
  for i, c in ipairs(LISTS.palette) do
    if (i - 1) % 8 ~= 0 then r.ImGui_SameLine(ctx, 0, 3) end
    local rgba = c and ((c << 8) | 0xFF) or 0x2A2A2AFF
    if r.ImGui_ColorButton(ctx, "##pal" .. i, rgba, r.ImGui_ColorEditFlags_NoTooltip(), 16, 16) then
      slot.color = c and rgba or nil
      local item = slot.guid and H.item(slot.guid)
      H.begin()
      if item then E.set_item_colour(item, slot.color) end     -- the item carries it (inspector)
      H.finish("Launcher: clip colour")
      r.ImGui_CloseCurrentPopup(ctx)
    end
    if not c and r.ImGui_IsItemHovered(ctx) then r.ImGui_SetTooltip(ctx, "The track's colour") end
  end
  r.ImGui_EndMenu(ctx)
end

-- a slot being recorded into: red, a blinking dot before its line, then the bars so far
function U.rec_slot(dl, m, x, y, w, h, hov)
  local now = E.schedule_pos()
  local live = now and now >= m.from and (r.GetPlayState() & 4) == 4
  r.ImGui_DrawList_AddRectFilled(dl, x, y, x + w - 1, y + h - 1, live and 0x8A1A1AFF or 0x4A1818FF)
  local dot = live or U.blink()
  if dot then r.ImGui_DrawList_AddCircleFilled(dl, x + 9, y + 9, 4, m.to and U.blink() and 0xFFFFFFFF or 0xFF4040FF) end
  local text = m.to and "Stopping" or (live and "Recording" or "Waiting")
  if live and now then
    local bars = (r.TimeMap2_timeToQN(0, now) - r.TimeMap2_timeToQN(0, m.from)) / 4
    text = text .. string.format(" %.1f", bars)
  end
  r.ImGui_DrawList_AddText(dl, x + 18, y + 2, 0xF0F0F0FF, text)
  if hov then U.tip(m.to and "The recording ends on this line" or "Click to stop recording on the nearest line") end
end

-- a curve scaled to its own lowest and highest value: the area under it filled, the line on top
function U.curve(dl, clip, x1, y1, x2, y2, line, fill)
  local lo, hi = math.huge, -math.huge
  for _, p in ipairs(clip.points) do lo, hi = math.min(lo, p.v), math.max(hi, p.v) end
  local span = hi - lo
  local function py(v) return span > 1e-9 and (y2 - (v - lo) / span * (y2 - y1)) or (y1 + y2) / 2 end
  local pts = {}
  local prev
  for _, p in ipairs(clip.points) do
    local xx = x1 + p.t * (x2 - x1)
    if prev and prev.s == 1 then pts[#pts + 1] = { xx, prev.y } end    -- square: hold, then jump
    pts[#pts + 1] = { xx, py(p.v) }
    prev = { y = py(p.v), s = math.floor(p.s or 0) }
  end
  if #pts == 0 then return end
  if pts[1][1] > x1 then table.insert(pts, 1, { x1, pts[1][2] }) end
  if pts[#pts][1] < x2 then pts[#pts + 1] = { x2, pts[#pts][2] } end
  for i = 2, #pts do
    local a, b = pts[i - 1], pts[i]
    if b[1] > a[1] then
      r.ImGui_DrawList_AddQuadFilled(dl, a[1], a[2], b[1], b[2], b[1], y2, a[1], y2, fill)
    end
  end
  for i = 2, #pts do
    r.ImGui_DrawList_AddLine(dl, pts[i - 1][1], pts[i - 1][2], pts[i][1], pts[i][2], line, 1.5)
  end
end

-- an automation clip's slot: as a clip slot (the track's colour, the triangle, the name),
-- with the curve in place of the waveform; an empty one as a track's empty slot
function U.env_slot(dl, track, lane, ez, name, env, row, x, y, w, h, y_lo, y_hi)
  local cy1, cy2 = math.max(y, y_lo), math.min(y + h - 1, y_hi)
  if cy2 - cy1 < 2 then return end
  local clip = ez and ez.slots[row]
  local _, hov = U.hit("##es" .. tostring(env) .. "_" .. row, x, cy1, w - 1, cy2 - cy1)
  local mx, my = r.ImGui_GetMousePos(ctx)
  local cy = y + math.min(h, 20) / 2
  r.ImGui_DrawList_PushClipRect(dl, x, cy1, x + w - 1, cy2, true)
  if clip then
    local col = clip.color or H.rgba(r.GetTrackColor(track)) or 0x8A8A8AFF
    r.ImGui_DrawList_AddRectFilled(dl, x, y, x + w - 1, y + h - 1, hov and H.shade(col, 1.08) or col)
    local ink = H.light(col) and 0x1A1A1AFF or 0xF0F0F0FF
    r.ImGui_DrawList_AddText(dl, x + 18, y + 2, ink, clip.name or "Automation")
    if h >= 26 then
      U.curve(dl, clip, x + 1, y + 17, x + w - 2, y + h - 2, H.light(col) and 0x2A1A0AFF or 0xF0F0F0FF, H.shade(col, 0.82))
    end
    local playing = ez.cur and ez.cur.row == row and not ez.stop_at
    local queued = ez.pend and ez.pend.row == row
    local box = playing or (queued and U.blink())
    local on_play = hov and mx >= x and mx < x + 18 and my >= y and my < y + 18
    if box then r.ImGui_DrawList_AddRectFilled(dl, x + 2, y + 2, x + 15, y + 15, 0xF0F0F0FF, 2)
    elseif on_play then r.ImGui_DrawList_AddRectFilled(dl, x + 2, y + 2, x + 15, y + 15, H.light(col) and 0x00000033 or 0xFFFFFF40, 2) end
    r.ImGui_DrawList_AddTriangleFilled(dl, x + 6, y + 4.5, x + 6, y + 12.5, x + 12.5, y + 8.5, box and 0x1A1A1AFF or ink)
    local heard = E.heard_pos()
    if playing and heard and ez.cur.len > 0 then
      local px = x + 1 + (w - 3) * (((heard - ez.cur.at) % ez.cur.len) / ez.cur.len)
      r.ImGui_DrawList_AddLine(dl, px, y + 1, px, y + h - 2, 0xFFFFFFCC, 1)
    end
    if on_play and r.ImGui_IsMouseClicked(ctx, 0) then E.env_launch(track, name, row) end
    if hov then U.tip((clip.name or "Automation") .. "\nTriangle: launch (it also goes with the track's clip in this scene)\nRight-click: menu") end
  else
    r.ImGui_DrawList_AddRectFilled(dl, x, y, x + w - 1, y + h - 1, C.empty)
    local on_plus = hov and mx > x + w - 22
    r.ImGui_DrawList_AddRectFilled(dl, x + 6, cy - 3, x + 12, cy + 3, (hov and not on_plus) and C.square_hi or C.square)
    if hov then
      local pc = on_plus and C.text or C.dim
      r.ImGui_DrawList_AddLine(dl, x + w - 17, cy, x + w - 9, cy, pc, 1.5)
      r.ImGui_DrawList_AddLine(dl, x + w - 13, cy - 4, x + w - 13, cy + 4, pc, 1.5)
      U.tip(on_plus and "Add: the selected automation item on this lane, or the time selection" or "Stop this automation clip")
      if r.ImGui_IsMouseClicked(ctx, 0) then
        if on_plus then E.env_add(track, env, row)
        elseif ez then E.env_stop(ez, E.schedule_pos() and E.boundary_after(E.schedule_pos(), false) or nil) end
      end
    end
  end
  r.ImGui_DrawList_PopClipRect(dl)
  r.ImGui_DrawList_AddRectFilled(dl, x + w - 1, cy1, x + w, cy2, C.seam)
  if hov and r.ImGui_IsMouseClicked(ctx, 1) then
    L.menu = { kind = clip and "env" or "env_empty", track = track, ez = ez, name = name, env = env, row = row }
  end
end

function U.toolbar(dl, x, y, w)
  r.ImGui_SetCursorScreenPos(ctx, x + 4, y + 3)
  local qlabel = "Q: ?"
  for _, q in ipairs(QUANT) do if q[1] == L.quantize then qlabel = q[2] end end
  -- the Q field takes what the three keys at the right leave over, so nothing overlaps
  r.ImGui_SetNextItemWidth(ctx, math.max(40, math.min(64, w - 101)))
  -- the drop-down opens at its full height, so every setting shows without scrolling
  if r.ImGui_BeginCombo(ctx, "##q", qlabel, r.ImGui_ComboFlags_NoArrowButton() | r.ImGui_ComboFlags_HeightLargest()) then
    for _, q in ipairs(QUANT) do
      if r.ImGui_Selectable(ctx, q[2], q[1] == L.quantize) then L.quantize = q[1] H.save() end
    end
    r.ImGui_Separator(ctx)
    r.ImGui_TextDisabled(ctx, "Project defaults")
    U.pick_menu("Play mode", "mode", L.def.mode, false, function(v) L.def.mode = v end)
    U.pick_menu("Release", "rel", L.def.rel, false, function(v) L.def.rel = v end)
    r.ImGui_Separator(ctx)
    if r.ImGui_MenuItem(ctx, "Audio files follow the project tempo", nil, L.sync ~= false) then
      L.sync = L.sync == false
      H.save()
    end
    if r.ImGui_MenuItem(ctx, "Hide REAPER's track panel while open", nil, L.hide_tcp) then
      L.hide_tcp = not L.hide_tcp
      r.SetExtState("TK Theme Bit", "launcher_hide_tcp", L.hide_tcp and "1" or "0", true)
      U.sync_tcp()
    end
    r.ImGui_TextDisabled(ctx, "ALT (Alt-click)")
    U.pick_menu("ALT launch Q", "q", L.def.aq, false, function(v) L.def.aq = v end)
    U.pick_menu("ALT play mode", "mode", L.def.amode, false, function(v) L.def.amode = v end)
    U.pick_menu("ALT release", "rel", L.def.arel, false, function(v) L.def.arel = v end)
    r.ImGui_EndCombo(ctx)
  end
  U.tip("Launch Q: the grid launches and stops land on")
  -- REAPER's own track panel on / off (View: Toggle show TCP area, 43185), right of Q
  local tcp_on = r.GetToggleCommandState(43185) == 1
  if U.key("##tcp", x + 6 + math.max(40, math.min(64, w - 101)), y + 4, 16, 16, "tcp", tcp_on, C.accent) then
    r.Main_OnCommand(43185, 0)
    -- hidden here: shown again when the launcher closes; shown here: left as it is
    L.tcp_hidden = tcp_on or nil
  end
  U.tip(tcp_on and "Hide REAPER's track panel" or "Show REAPER's track panel")
  local bx = x + w - 54
  if U.key("##perf", bx - 19, y + 4, 16, 16, "rec", L.perf, C.arm) then E.perf_toggle() end
  U.tip(L.perf and "Writing the launcher into the arrangement: click to stop (clips land when the transport stops)"
    or "Record the launcher performance into the arrangement")
  if U.key("##hd", bx, y + 4, 16, 16, "H", L.headers, C.accent) then L.headers = not L.headers H.save() end
  U.tip("Track headers: full (rec / S / M, volume, meter) or names only")
  local docked = r.ImGui_IsWindowDocked(ctx)
  r.ImGui_SetCursorScreenPos(ctx, bx + 19, y + 4)
  if r.ImGui_InvisibleButton(ctx, "##dock", 16, 16) then L.dock_to = docked and 0 or -1 end
  local ic = r.ImGui_IsItemHovered(ctx) and C.text or C.dim
  r.ImGui_DrawList_AddRect(dl, bx + 22, y + 7, bx + 32, y + 16, ic, 1)
  if docked then r.ImGui_DrawList_AddRectFilled(dl, bx + 22, y + 7, bx + 25, y + 16, C.accent) end
  U.tip(docked and "Float the launcher" or "Dock the launcher (REAPER's first docker; put it at the left of the arrange)")
  local shown = U.layout().lanes_shown
  if U.key("##lanes", bx + 37, y + 4, 16, 16, "eye", shown, C.accent) then H.show_lanes(not shown) end
  U.tip(shown and "Hide the launcher's own tracks (where its clips live)"
    or "Show the launcher's own tracks (where its clips live) in the track panel")
end

-- close: at the far right of the strip above the scene row, or of the scene row itself when
-- there is no strip (the panel not lined up with the arrange)
function U.close_key(dl, x, y)
  r.ImGui_SetCursorScreenPos(ctx, x, y)
  if r.ImGui_InvisibleButton(ctx, "##close", 16, 16) then L.close = true end
  local ic = r.ImGui_IsItemHovered(ctx) and C.text or C.dim
  r.ImGui_DrawList_AddLine(dl, x + 4, y + 4, x + 11, y + 11, ic, 1.4)
  r.ImGui_DrawList_AddLine(dl, x + 11, y + 4, x + 4, y + 11, ic, 1.4)
  U.tip("Close the launcher")
end

-- a button clipped to the scene area (L.cx1 .. L.cx2), so a column half out of view only
-- takes clicks on the part that shows; returns clicked, hovered
function U.hit(id, x, y, w, h)
  local x1, x2 = math.max(x, L.cx1 or x), math.min(x + w, L.cx2 or (x + w))
  if x2 - x1 < 1 or h < 1 then return false, false end
  r.ImGui_SetCursorScreenPos(ctx, x1, y)
  local clicked = r.ImGui_InvisibleButton(ctx, id, x2 - x1, h)
  return clicked, r.ImGui_IsItemHovered(ctx), true
end

-- the paths a drop carried: newline / NUL separated, quoted, or file:// URIs
function U.payload_paths(payload)
  local paths = {}
  local text = tostring(payload or ""):gsub("%z", "\n"):gsub("\r", "")
  for line in text:gmatch("[^\n]+") do
    local c = (line:match("^%s*(.-)%s*$") or ""):gsub('^"', ""):gsub('"$', "")
    if c:lower():match("^file://") then
      c = c:gsub("^%a+://", ""):gsub("^localhost/", ""):gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)
      c = c:gsub("^/(%a:)", "%1")
    end
    if c ~= "" and r.file_exists(c) then paths[#paths + 1] = c end
  end
  return paths
end

-- Files dropped on the last item (a slot). Windows Explorer delivers files; REAPER's Media
-- Explorer delivers a payload of its own, so the named types are asked for too, and failing
-- those whatever type is in flight (TK Project Clips' sweep, which works docked as well).
local DROP_TYPES = { "REAPER_MEDIAFOLDER", "text/uri-list", "UTF8_STRING", "TEXT", "FILE_PATH", "FILES" }
function U.accept_drop(track, row)
  if not r.ImGui_BeginDragDropTarget(ctx) then return end
  local paths = {}
  local ok, count = r.ImGui_AcceptDragDropPayloadFiles(ctx)
  if ok and tonumber(count) then
    for i = 0, tonumber(count) - 1 do
      local got, file = r.ImGui_GetDragDropPayloadFile(ctx, i)
      if got and file ~= "" then paths[#paths + 1] = file end
    end
  end
  if #paths == 0 then
    for _, t in ipairs(DROP_TYPES) do
      local got, payload = r.ImGui_AcceptDragDropPayload(ctx, t)
      if got then paths = U.payload_paths(payload) if #paths > 0 then break end end
    end
  end
  if #paths == 0 then
    local any, t = r.ImGui_GetDragDropPayload(ctx)
    if any and t and t ~= "" then
      local got, payload = r.ImGui_AcceptDragDropPayload(ctx, t)
      if got then paths = U.payload_paths(payload) end
    end
  end
  r.ImGui_EndDragDropTarget(ctx)
  if #paths == 0 then return end
  local lane = H.lane_of(track, true)
  H.begin()
  local n = 0
  for i, path in ipairs(paths) do
    if E.assign_path(lane, row + i - 1, path) then n = n + 1 end
  end
  H.finish("Launcher: add clips")
  H.save()
  L.status = n == 1 and "Added 1 clip" or ("Added " .. n .. " clips")
end

function U.scene_head(dl, row, x, y, w, h)
  local sc = L.scenes[row] or {}
  local _, hov = U.hit("##sc" .. row, x, y, w - 1, h)
  r.ImGui_DrawList_AddRectFilled(dl, x, y, x + w - 1, y + h, hov and 0x555555FF or C.scenehead)
  if sc.color then r.ImGui_DrawList_AddRectFilled(dl, x, y, x + w - 1, y + 2, sc.color) end
  r.ImGui_DrawList_AddTriangleFilled(dl, x + 5, y + 7, x + 5, y + h - 7, x + 11, y + h / 2, C.text)
  r.ImGui_DrawList_PushClipRect(dl, x, y, x + w - 2, y + h, true)
  local _, th = r.ImGui_CalcTextSize(ctx, "S")
  r.ImGui_DrawList_AddText(dl, x + 15, y + (h - th) / 2, C.text, H.scene_name(row))
  r.ImGui_DrawList_PopClipRect(dl)
  if hov and r.ImGui_IsMouseClicked(ctx, 0) then E.launch_scene(row) end
  if hov and r.ImGui_IsMouseClicked(ctx, 1) then L.menu = { kind = "scene", row = row } end
  if hov then U.tip("Launch " .. H.scene_name(row) .. " (tracks without a clip in it stop)\nRight-click: rename, insert, delete") end
end

function U.panel()
  local dl = r.ImGui_GetWindowDrawList(ctx)
  local wx, wy = r.ImGui_GetWindowPos(ctx)
  local ww, wh = r.ImGui_GetWindowSize(ctx)
  r.ImGui_DrawList_AddRectFilled(dl, wx, wy, wx + ww, wy + wh, C.bg)
  L.cells, L.hover = {}, nil
  local hw = L.headers and K.head_w or K.head_w_small
  local arrange_y, scale = U.arrange_geometry()
  -- the grid lines up with the arrange when the panel sits beside it (docked at the left);
  -- otherwise it follows the arrange's scrolling from just under its own top row
  local body_top = wy + K.top_h
  if arrange_y and math.abs(arrange_y - wy) < 160 and arrange_y >= wy + K.top_h then body_top = arrange_y end
  local head_y = body_top - K.top_h
  local grid_x = wx + hw + K.stop_w
  local ret_x = wx + ww - K.ret_w
  local nscenes = #L.scenes
  -- the scene columns keep their width and slide under the edges (Shift+wheel), the way
  -- Bitwig's do; nothing jumps when the panel is made narrower
  local vis_w = math.max(1, ret_x - grid_x)
  L.scroll_x = math.max(0, math.min(L.scroll_x or 0, nscenes * K.scene_w + 30 - vis_w))
  L.cx1, L.cx2, L.scale = grid_x, ret_x, scale
  L.col_x0 = grid_x - L.scroll_x
  L.row_first = math.max(1, math.floor(L.scroll_x / K.scene_w) + 1)
  L.row_last = math.min(nscenes, math.ceil((L.scroll_x + vis_w) / K.scene_w))
  -- above the scene row: grey, as Bitwig's panel top; then the top row: toolbar over the
  -- headers, global stop, scene heads, "+", global return
  if head_y > wy then r.ImGui_DrawList_AddRectFilled(dl, wx, wy, wx + ww, head_y, C.head) end
  if head_y - wy >= 16 then
    U.close_key(dl, wx + ww - 19, wy + math.floor((head_y - wy - 16) / 2))
  else
    U.close_key(dl, ret_x - 18, head_y + 4)
  end
  r.ImGui_DrawList_AddRectFilled(dl, wx, head_y, wx + ww, body_top, C.scenehead)
  U.toolbar(dl, wx, head_y, hw)
  r.ImGui_SetCursorScreenPos(ctx, wx + hw, head_y)
  if r.ImGui_InvisibleButton(ctx, "##stopall", K.stop_w, K.top_h) then E.stop_all() end
  local hov = r.ImGui_IsItemHovered(ctx)
  r.ImGui_DrawList_AddRectFilled(dl, wx + hw + 5, head_y + 8, wx + hw + 13, head_y + 16, hov and C.square_hi or C.square)
  U.tip("Stop every clip (on the launch grid)")
  r.ImGui_DrawList_PushClipRect(dl, grid_x, head_y, ret_x, body_top, true)
  for row = L.row_first, L.row_last do
    U.scene_head(dl, row, L.col_x0 + (row - 1) * K.scene_w, head_y, K.scene_w, K.top_h)
  end
  local ax = L.col_x0 + nscenes * K.scene_w
  if ax < ret_x then
    local clicked, ahov = U.hit("##addscene", ax, head_y, 24, K.top_h)
    if clicked then
      L.scenes[#L.scenes + 1] = {}
      H.save()
    end
    local ic = ahov and C.text or C.dim
    r.ImGui_DrawList_AddLine(dl, ax + 7, head_y + 12, ax + 17, head_y + 12, ic, 1.5)
    r.ImGui_DrawList_AddLine(dl, ax + 12, head_y + 7, ax + 12, head_y + 17, ic, 1.5)
    if ahov then U.tip("Add a scene") end
  end
  r.ImGui_DrawList_PopClipRect(dl)
  local any_owned = false
  for _, lane in pairs(L.lanes) do if E.launcher_owns(lane) then any_owned = true break end end
  r.ImGui_SetCursorScreenPos(ctx, ret_x, head_y)
  if r.ImGui_InvisibleButton(ctx, "##backall", K.ret_w, K.top_h) then E.back_all() end
  hov = r.ImGui_IsItemHovered(ctx)
  U.ret_icon(dl, ret_x + K.ret_w / 2, head_y + K.top_h / 2, any_owned and C.accent or (hov and C.text or C.icon))
  U.tip("Every track back to the arrangement (at once)")
  -- the rows
  local y_lo, y_hi = body_top, wy + wh
  r.ImGui_DrawList_PushClipRect(dl, wx, y_lo, wx + ww, y_hi, true)
  for _, rw in ipairs(U.rows()) do
    local track, ty, th, is_master = rw[1], rw[2], rw[3], rw[4]
    local y, h = body_top + ty * scale, th * scale
    for _, er in ipairs(U.env_rows(track, th)) do
      local ey, eh = y + er[2] * scale, er[3] * scale
      if ey + eh > y_lo and ey < y_hi then
        U.env_row(dl, track, er[1], wx, ey, hw, eh, grid_x, ret_x, wx + ww, y_lo, y_hi, er[4])
      end
    end
    if is_master then
      if y + h > y_lo and y < y_hi then U.master_row(dl, track, wx, y, hw, h, grid_x, ret_x, wx + ww, y_lo, y_hi) end
    elseif y + h > y_lo and y < y_hi then
      local lane = H.lane_of(track, false)
      U.header(dl, track, wx, y, hw, h, y_lo, y_hi)
      -- stop square: lit while a clip plays, blinking while a stop waits for its line
      local sy1, sy2 = math.max(y, y_lo), math.min(y + h - 1, y_hi)
      r.ImGui_DrawList_AddRectFilled(dl, wx + hw, y, grid_x, y + h, C.stopcol)
      if sy2 - sy1 > 2 then
        r.ImGui_SetCursorScreenPos(ctx, wx + hw, sy1)
        if r.ImGui_InvisibleButton(ctx, "##st" .. tostring(track), K.stop_w, sy2 - sy1) then E.stop_track(track) end
        local shov = r.ImGui_IsItemHovered(ctx)
        local running = lane and (lane.current or lane.pending)
        local sc = (lane and lane.stop_at and U.blink()) and C.accent or ((running or shov) and C.square_hi or C.square)
        local cy = y + math.min(h, 20) / 2
        r.ImGui_DrawList_AddRectFilled(dl, wx + hw + 5, cy - 4, wx + hw + 13, cy + 4, sc)
        U.tip("Stop this track's clip (the launcher keeps the track until its return arrow)")
      end
      r.ImGui_DrawList_AddRectFilled(dl, grid_x, y, ret_x, y + h, C.bg)
      r.ImGui_DrawList_PushClipRect(dl, grid_x, y_lo, ret_x, y_hi, true)
      for row = L.row_first, L.row_last do
        U.slot(dl, track, lane, row, L.col_x0 + (row - 1) * K.scene_w, y, K.scene_w, h, y_lo, y_hi)
      end
      r.ImGui_DrawList_PopClipRect(dl)
      -- return arrow: orange while the launcher plays this track instead of the arrangement
      r.ImGui_DrawList_AddRectFilled(dl, ret_x, y, wx + ww, y + h, C.retcol)
      r.ImGui_DrawList_AddRectFilled(dl, ret_x, y + h - 1, wx + ww, y + h, C.seam)
      if sy2 - sy1 > 2 then
        r.ImGui_SetCursorScreenPos(ctx, ret_x, sy1)
        if r.ImGui_InvisibleButton(ctx, "##rt" .. tostring(track), K.ret_w, sy2 - sy1) and lane then
          r.PreventUIRefresh(1)
          E.back_to_arrangement(lane)
          r.PreventUIRefresh(-1)
          r.UpdateArrange()
        end
        local rhov = r.ImGui_IsItemHovered(ctx)
        local owned = E.launcher_owns(lane)
        U.ret_icon(dl, ret_x + K.ret_w / 2, y + math.min(h, 20) / 2, owned and C.accent or (rhov and C.text or C.icon))
        U.tip(owned and "The launcher plays this track: click to go back to the arrangement" or "This track plays the arrangement")
      end
    end
  end
  r.ImGui_DrawList_PopClipRect(dl)
  -- status line at the bottom
  if L.status ~= "" or L.other then
    local msg = L.other and "TK Project Clips' launcher is also in this project: keep them on different tracks" or L.status
    r.ImGui_DrawList_AddRectFilled(dl, wx, wy + wh - 18, wx + ww, wy + wh, 0x000000CC)
    r.ImGui_DrawList_AddText(dl, wx + 6, wy + wh - 16, L.other and C.solo or C.dim, msg)
  end
  -- wheel: scroll the arrange's tracks (as if over the track panel); Shift: the scenes
  if r.ImGui_IsWindowHovered(ctx) then
    local wheel, wheel_h = r.ImGui_GetMouseWheel(ctx)
    if wheel_h and wheel_h ~= 0 then L.scroll_x = (L.scroll_x or 0) - wheel_h * 40 end
    if wheel ~= 0 then
      if (r.ImGui_GetKeyMods(ctx) & r.ImGui_Mod_Shift()) ~= 0 then
        L.scroll_x = (L.scroll_x or 0) - wheel * 40
      else
        r.CSurf_OnScroll(0, wheel > 0 and -3 or 3)
      end
    end
  end
  U.drag(dl)
  -- a click on a clip, let go without a drag: now the arrange's context (see U.slot)
  if L.ctx_after and not r.ImGui_IsMouseDown(ctx, 0) then
    if not (L.drag and L.drag.moving) and not L.dragged then r.SetCursorContext(L.ctx_after, nil) end
    L.ctx_after, L.dragged = nil, nil
  end
  -- letting go of a play triangle: the clip's release action (Alt held: its ALT one)
  if L.held and not r.ImGui_IsMouseDown(ctx, 0) then
    local held = L.held
    L.held = nil
    local slot = held.lane.slots[held.row]
    if slot then
      local alt = (r.ImGui_GetKeyMods(ctx) & r.ImGui_Mod_Alt()) ~= 0
      E.release(held.lane, held.row, E.setting(slot, alt, "rel"))
    end
  end
  r.ImGui_SetCursorScreenPos(ctx, wx, wy)         -- never leave the cursor out past the window
  r.ImGui_Dummy(ctx, 1, 1)
end

function U.cell_at(x, y)
  for _, c in ipairs(L.cells) do
    if x >= c.x1 and x < c.x2 and y >= c.y1 and y < c.y2 then return c end
  end
end

-- dragging a clip from one slot to another inside the panel
function U.drag(dl)
  local d = L.drag
  if not d then return end
  local mx, my = r.ImGui_GetMousePos(ctx)
  if r.ImGui_IsMouseDown(ctx, 0) then
    if math.abs(mx - d.x) > 6 or math.abs(my - (d.y or my)) > 6 then d.moving = true end
    if d.moving then
      local slot = d.lane.slots[d.row]
      local c = U.cell_at(mx, my)
      if c then r.ImGui_DrawList_AddRect(dl, c.x1, c.y1, c.x2 - 1, c.y2, C.accent, 0, 0, 2) end
      if slot then
        r.ImGui_DrawList_AddRectFilled(dl, mx + 8, my + 4, mx + 90, my + 20, H.slot_colour(d.lane, slot))
        r.ImGui_DrawList_AddText(dl, mx + 12, my + 5, 0x1A1A1AFF, slot.name or "Clip")
      end
    end
    return
  end
  L.drag = nil
  if not d.moving then return end
  local c = U.cell_at(mx, my)
  local to_lane = c and H.lane_of(c.track, true)
  -- let go on its own slot (a click that wobbled a few pixels): a click, not a drag, so the
  -- inspector still gets the clip (see the check after U.drag in U.panel)
  if not c or (to_lane == d.lane and c.row == d.row) then return end
  L.dragged = true
  local copy = (r.ImGui_GetKeyMods(ctx) & r.ImGui_Mod_Ctrl()) ~= 0
  E.move_slot(d.lane, d.row, to_lane, c.row, copy)
end

-- a file dragged in from TK Media Browser / Workbench (ExtState TK_DRAG + heartbeat); the
-- sender clears it on release, which is the drop. Docking makes no difference this way.
function U.tk_drag()
  local path = r.GetExtState("TK_DRAG", "path")
  local beat = tonumber(r.GetExtState("TK_DRAG", "heartbeat") or "")
  if path ~= "" and beat and r.time_precise() - beat < 0.5 then
    L.drag_path = path
    local nx, ny = r.GetMousePosition()
    local x, y = nx, ny
    if r.ImGui_PointConvertNative then x, y = r.ImGui_PointConvertNative(ctx, nx, ny, false) end
    L.drag_cell = U.cell_at(x, y)
    return
  end
  if not L.drag_path then return end
  local dropped, c = L.drag_path, L.drag_cell
  L.drag_path, L.drag_cell = nil, nil
  if c then
    H.begin()
    local ok = E.assign_path(H.lane_of(c.track, true), c.row, dropped)
    H.finish("Launcher: add clip")
    H.save()
    L.status = ok and "Added a clip" or "Could not read that file"
  end
end

-- right-click menus (opened at window level, so the popup id matches)
function U.menus()
  if L.menu then
    L.menu_open = L.menu
    L.menu = nil
    r.ImGui_OpenPopup(ctx, "##menu")
  end
  if r.ImGui_BeginPopup(ctx, "##menu") then
    local m = L.menu_open or {}
    if m.kind == "slot" and m.lane and m.lane.slots[m.row] then
      local lane, row = m.lane, m.row
      local slot = lane.slots[row]
      if r.ImGui_MenuItem(ctx, "Launch") then E.launch(lane, row) end
      if r.ImGui_MenuItem(ctx, "Rename...") then L.rename = { kind = "slot", lane = lane, row = row, buf = slot.name or "", first = true } end
      if r.ImGui_MenuItem(ctx, "Launch (ALT settings)") then E.launch(lane, row, true) end
      if r.ImGui_MenuItem(ctx, slot.midi and "Edit in the MIDI editor" or "Edit in Clip Edit") then
        L.want_edit = { lane = lane, row = row }
      end
      U.palette(slot)
      r.ImGui_Separator(ctx)
      if r.ImGui_BeginMenu(ctx, "Main") then
        U.pick_menu("Launch Q", "q", slot.q, true, function(v) slot.q = v end)
        U.pick_menu("Play mode", "mode", slot.mode, true, function(v) slot.mode = v end)
        U.pick_menu("Release", "rel", slot.rel, true, function(v) slot.rel = v end)
        r.ImGui_EndMenu(ctx)
      end
      if r.ImGui_BeginMenu(ctx, "ALT (Alt-click)") then
        U.pick_menu("Launch Q", "q", slot.aq, true, function(v) slot.aq = v end)
        U.pick_menu("Play mode", "mode", slot.amode, true, function(v) slot.amode = v end)
        U.pick_menu("Release", "rel", slot.arel, true, function(v) slot.arel = v end)
        r.ImGui_EndMenu(ctx)
      end
      if r.ImGui_BeginMenu(ctx, "Next Action") then
        if r.ImGui_MenuItem(ctx, "Off", nil, slot.na == nil) then slot.na = nil H.save() end
        for _, e in ipairs(LISTS.next) do
          if r.ImGui_MenuItem(ctx, e[2], nil, slot.na == e[1]) then slot.na = e[1] H.save() end
        end
        r.ImGui_Separator(ctx)
        if r.ImGui_BeginMenu(ctx, "After") then
          for _, n in ipairs(LISTS.loops) do
            if r.ImGui_MenuItem(ctx, n == 1 and "1 loop" or (n .. " loops"), nil, (slot.na_n or 1) == n) then slot.na_n = n H.save() end
          end
          r.ImGui_EndMenu(ctx)
        end
        r.ImGui_EndMenu(ctx)
      end
      r.ImGui_Separator(ctx)
      if slot.bpm then
        local label = string.format("Follow the project tempo (file: %.1f BPM%s)", slot.bpm, slot.bpm_guess and ", guessed" or "")
        if r.ImGui_MenuItem(ctx, label, nil, not slot.nosync) then
          slot.nosync = not slot.nosync or nil
          E.apply_tempo(slot)
          H.save()
        end
      end
      if r.ImGui_MenuItem(ctx, "Copy to arrangement at edit cursor") then E.to_arrangement(lane, row) end
      r.ImGui_Separator(ctx)
      if r.ImGui_MenuItem(ctx, "Delete clip") then
        H.begin()
        E.clear_slot(lane, row)
        H.finish("Launcher: delete clip")
        H.save()
      end
    elseif m.kind == "env" and m.ez and m.ez.slots[m.row] then
      if r.ImGui_MenuItem(ctx, "Launch") then E.env_launch(m.track, m.name, m.row) end
      if r.ImGui_MenuItem(ctx, "Rename...") then L.rename = { kind = "env", ez = m.ez, row = m.row, buf = m.ez.slots[m.row].name or "", first = true } end
      if r.ImGui_MenuItem(ctx, "Replace from the lane (selected automation item / time selection)") then E.env_add(m.track, m.env, m.row) end
      if r.ImGui_MenuItem(ctx, "Copy to arrangement at edit cursor") then E.env_to_arrangement(m.track, m.name, m.row) end
      r.ImGui_Separator(ctx)
      if r.ImGui_MenuItem(ctx, "Delete automation clip") then
        if m.ez.cur and m.ez.cur.row == m.row then E.env_stop(m.ez, nil) end
        m.ez.slots[m.row] = nil
        H.save()
      end
    elseif m.kind == "env_empty" and m.track and H.valid_track(m.track) then
      if r.ImGui_MenuItem(ctx, "Add from the selected automation item or the time selection") then E.env_add(m.track, m.env, m.row) end
    elseif m.kind == "empty" and m.track and H.valid_track(m.track) then
      local n = r.CountSelectedMediaItems(0)
      if r.ImGui_MenuItem(ctx, n > 1 and ("Add " .. n .. " selected items from here") or "Add selected item here", nil, false, n > 0) then
        E.add_selected(m.track, m.row)
      end
      if r.ImGui_MenuItem(ctx, "Add file...") then L.want_file = { track = m.track, row = m.row } end
      if r.ImGui_MenuItem(ctx, "Stop this track") then E.stop_track(m.track) end
    elseif m.kind == "scene" and L.scenes[m.row] then
      local row = m.row
      if r.ImGui_MenuItem(ctx, "Launch") then E.launch_scene(row) end
      if r.ImGui_MenuItem(ctx, "Rename...") then L.rename = { kind = "scene", row = row, buf = L.scenes[row].name or "", first = true } end
      if r.ImGui_MenuItem(ctx, "Insert scene before") then
        H.shift_rows(row, 1)
        table.insert(L.scenes, row, {})
        H.save()
      end
      if r.ImGui_MenuItem(ctx, "Delete scene (and its clips)", nil, false, #L.scenes > 1) then
        H.begin()
        for _, lane in pairs(L.lanes) do E.clear_slot(lane, row) end
        H.shift_rows(row + 1, -1)
        table.remove(L.scenes, row)
        H.finish("Launcher: delete scene")
        H.save()
      end
    end
    r.ImGui_EndPopup(ctx)
  end
  -- rename
  if L.rename then
    if L.rename.first then r.ImGui_OpenPopup(ctx, "Rename##rn") end
    if r.ImGui_BeginPopup(ctx, "Rename##rn") then
      local rn = L.rename
      if rn.first then r.ImGui_SetKeyboardFocusHere(ctx) rn.first = false end
      r.ImGui_SetNextItemWidth(ctx, 180)
      local done
      done, rn.buf = r.ImGui_InputText(ctx, "##rnbuf", rn.buf, r.ImGui_InputTextFlags_EnterReturnsTrue())
      if done then
        if rn.kind == "slot" and rn.lane.slots[rn.row] then rn.lane.slots[rn.row].name = rn.buf
        elseif rn.kind == "env" and rn.ez.slots[rn.row] then rn.ez.slots[rn.row].name = rn.buf
        elseif rn.kind == "track" and H.valid_track(rn.track) then
          H.begin()
          r.GetSetMediaTrackInfo_String(rn.track, "P_NAME", rn.buf, true)
          H.finish("Rename track")
        elseif rn.kind == "scene" and L.scenes[rn.row] then L.scenes[rn.row].name = rn.buf end
        H.save()
        L.rename = nil
        r.ImGui_CloseCurrentPopup(ctx)
      end
      r.ImGui_EndPopup(ctx)
    elseif not L.rename.first then
      L.rename = nil
    end
  end
end

-- keys while the panel has focus: Delete removes the selected clip, Space is play / stop
function U.keys()
  if not r.ImGui_IsWindowFocused(ctx, r.ImGui_FocusedFlags_RootAndChildWindows()) or r.ImGui_IsAnyItemActive(ctx) or L.rename then return end
  if r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_Space(), false) then r.Main_OnCommand(40044, 0) end
  local mods = r.ImGui_GetKeyMods(ctx)
  if (mods & r.ImGui_Mod_Ctrl()) ~= 0 then
    local shift = (mods & r.ImGui_Mod_Shift()) ~= 0
    if r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_Z(), false) then r.Main_OnCommand(shift and 40030 or 40029, 0) return end
    if r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_Y(), false) then r.Main_OnCommand(40030, 0) return end
    if r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_S(), false) then r.Main_OnCommand(40026, 0) return end
  end
  if L.sel and (r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_Delete(), false) or r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_Backspace(), false)) then
    if L.sel.lane.slots[L.sel.row] then
      H.begin()
      E.clear_slot(L.sel.lane, L.sel.row)
      H.finish("Launcher: delete clip")
      H.save()
    end
  end
  if L.sel and r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_Enter(), false) then E.launch(L.sel.lane, L.sel.row) end
end

-- the file dialog blocks, so it runs before the frame, never inside a menu
function U.file_prompt()
  local w = L.want_file
  if not w then return end
  L.want_file = nil
  if not H.valid_track(w.track) then return end
  local ok, path = r.GetUserFileNameForRead("", "Add a clip to the launcher", "")
  if ok and path ~= "" then
    H.begin()
    local done = E.assign_path(H.lane_of(w.track, true), w.row, path)
    H.finish("Launcher: add clip")
    H.save()
    L.status = done and "Added a clip" or "Could not read that file"
  end
end

local STYLE = {
  { r.ImGui_Col_WindowBg, C.bg }, { r.ImGui_Col_ChildBg, 0x00000000 }, { r.ImGui_Col_Text, C.text },
  { r.ImGui_Col_Border, C.line }, { r.ImGui_Col_PopupBg, C.popup }, { r.ImGui_Col_FrameBg, C.field },
  { r.ImGui_Col_FrameBgHovered, 0x1A1A1AFF }, { r.ImGui_Col_FrameBgActive, 0x222222FF },
  { r.ImGui_Col_Button, 0x363636FF }, { r.ImGui_Col_ButtonHovered, 0x444444FF }, { r.ImGui_Col_ButtonActive, C.field },
  { r.ImGui_Col_Header, 0x3E1A04FF }, { r.ImGui_Col_HeaderHovered, 0x2A2A2AFF }, { r.ImGui_Col_HeaderActive, 0x333333FF },
  { r.ImGui_Col_TextSelectedBg, 0x56220299 }, { r.ImGui_Col_ResizeGrip, 0x00000000 },
  { r.ImGui_Col_ResizeGripHovered, C.accent }, { r.ImGui_Col_ResizeGripActive, C.accent },
  { r.ImGui_Col_Separator, C.line }, { r.ImGui_Col_CheckMark, C.accent },
  { r.ImGui_Col_NavHighlight or r.ImGui_Col_NavCursor, C.accent },
}
for i = #STYLE, 1, -1 do if not STYLE[i][1] then table.remove(STYLE, i) end end

-- REAPER's own track panel (View: Toggle show TCP area, 43185) goes away while the launcher
-- is open, if the user wants that (default on); it comes back when it closes
L.hide_tcp = r.GetExtState("TK Theme Bit", "launcher_hide_tcp") ~= "0"
function U.sync_tcp()
  local shown = r.GetToggleCommandState(43185) == 1
  if L.hide_tcp and shown then
    r.Main_OnCommand(43185, 0)
    L.tcp_hidden = true
  elseif not L.hide_tcp and L.tcp_hidden then
    if not shown then r.Main_OnCommand(43185, 0) end
    L.tcp_hidden = nil
  end
end
U.sync_tcp()

local function loop()
  E.update()
  if L.want_edit then
    local w = L.want_edit
    L.want_edit = nil
    E.edit(w.lane, w.row)
  end
  U.file_prompt()
  U.popup()
  r.ImGui_PushFont(ctx, font, 12)
  for _, c in ipairs(STYLE) do r.ImGui_PushStyleColor(ctx, c[1](), c[2]) end
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowPadding(), 0, 0)
  r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), 2)
  r.ImGui_SetNextWindowSize(ctx, 640, 520, r.ImGui_Cond_FirstUseEver())
  if L.dock_to then
    r.ImGui_SetNextWindowDockID(ctx, L.dock_to)
    L.dock_to = nil
  end
  local flags = r.ImGui_WindowFlags_NoCollapse() | r.ImGui_WindowFlags_NoTitleBar()
    | r.ImGui_WindowFlags_NoScrollbar() | r.ImGui_WindowFlags_NoScrollWithMouse()
  -- docked, a click on an empty spot must not start a window drag: without a title bar ImGui
  -- moves a window by its body, and in REAPER's docker that kept hold of the mouse until
  -- a click outside REAPER (user's report, 2026-11-26)
  if L.docked then flags = flags | r.ImGui_WindowFlags_NoMove() end
  local visible, open = r.ImGui_Begin(ctx, "Launcher", true, flags)
  if visible then
    L.docked = r.ImGui_IsWindowDocked(ctx)
    U.panel()
    U.tk_drag()
    U.menus()
    U.keys()
    r.ImGui_End(ctx)
  end
  r.ImGui_PopStyleVar(ctx, 2)
  r.ImGui_PopStyleColor(ctx, #STYLE)
  r.ImGui_PopFont(ctx)
  if L.close then open = false end
  if open then r.defer(loop) end
end

-- the launcher icon in Bit's transport is orange while this runs: theme parameter bitLaunchOn
function U.theme_says_open(v)
  local i = 0
  while true do
    local name, _, value = r.ThemeLayout_GetParameter(i)
    if not name then return end
    if name == "bitLaunchOn" then
      if value ~= v then
        r.ThemeLayout_SetParameter(i, v, false)
        r.ThemeLayout_RefreshAll()
      end
      return
    end
    i = i + 1
  end
end
U.theme_says_open(1)

r.atexit(function()
  E.edit_end()
  U.theme_says_open(0)
  if L.tcp_hidden and r.GetToggleCommandState(43185) == 0 then r.Main_OnCommand(43185, 0) end
  if L.loaded and r.EnumProjects(-1) == L.proj then
    E.release_all()
    H.save()
  end
  if cmd_id and cmd_id ~= 0 then
    r.SetToggleCommandState(section_id, cmd_id, 0)
    r.RefreshToolbar2(section_id, cmd_id)
  end
end)
if cmd_id and cmd_id ~= 0 then
  r.SetToggleCommandState(section_id, cmd_id, 1)
  r.RefreshToolbar2(section_id, cmd_id)
end
r.defer(loop)
