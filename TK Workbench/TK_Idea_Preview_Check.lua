-- @description TK Idea Preview Check
-- @author TouristKiller
-- @version 0.1.0
-- @changelog:
--   + Initial release: says why an Idea Vault preview is silent - the range the
--     capture would render, what would be soloed, and whether the previews
--     already in the vault contain any signal

-- Why is an Idea Vault preview silent?
--
-- A capture that "does not capture the audio" can fail in three different
-- places, and they need completely different fixes:
--
--   1. the render is aimed at the wrong stretch of the project, so it records
--      silence perfectly correctly;
--   2. the render range is right but nothing in it reaches the master with the
--      other tracks quiet, so the file is silence again;
--   3. the file has audio in it and the preview player is what fails.
--
-- Nothing on disk tells the three apart - a silent render is a normal file of
-- the right length in the right format. So this asks REAPER directly: what the
-- capture would do with the tracks selected right now, and whether the previews
-- already in the vault contain any signal at all.
--
-- Read-only. It renders nothing, changes no setting, and touches no file.
-- Select the track you would capture, then run it.

local r = reaper

local script_path = debug.getinfo(1, "S").source:match("@?(.*[\\/])") or ""
local sep = package.config:sub(1, 1)
package.path = script_path .. "?.lua;" .. script_path .. "?" .. sep .. "init.lua;" .. package.path

local ok_store, Store = pcall(require, "core.idea_vault_store")

-- Everything printed is kept, so the whole report can be written to a file at
-- the end as well. A console window has to be selected, copied and pasted to be
-- shared, and a report that is awkward to send is a report that does not get
-- sent - which is the entire point of this script.
local report = {}
local function line(text)
  text = tostring(text)
  report[#report + 1] = text
  r.ShowConsoleMsg(text .. "\n")
end
local function head(text) line(""); line(text); line(("-"):rep(#text)) end

-- Written into the vault itself: it is a folder the user already knows, the
-- store guarantees it exists, and the report belongs beside the previews it
-- describes rather than somewhere in the scripts tree.
local function write_report()
  local ok_root, root = pcall(Store.ensure_root)
  if not ok_root or not root or root == "" then return nil end
  local path = root .. "idea_preview_check.txt"
  local file = io.open(path, "w")
  if not file then return nil end
  file:write(table.concat(report, "\n") .. "\n")
  file:close()
  return path
end

local function track_label(track)
  if not track or not r.ValidatePtr2(0, track, "MediaTrack*") then return "(none)" end
  local number = math.floor(r.GetMediaTrackInfo_Value(track, "IP_TRACKNUMBER") or 0)
  local _, name = r.GetTrackName(track)
  return string.format("%d %s", number, tostring(name or ""))
end

local function yes(value) return value and "yes" or "no" end

-- Peak of a media file, in dB, without loading it into the project. Returns nil
-- when the peaks are not available rather than guessing at silence: a build that
-- cannot answer must not be read as "your preview is empty".
local function peak_db(path)
  if not r.PCM_Source_CreateFromFile or not r.PCM_Source_GetPeaks or not r.new_array then return nil, "no peak API" end
  local source = r.PCM_Source_CreateFromFile(path)
  if not source then return nil, "could not open the file" end
  local peak, note = nil, nil
  pcall(function()
    local length = tonumber(r.GetMediaSourceLength(source)) or 0
    local channels = math.floor(tonumber(r.GetMediaSourceNumChannels(source)) or 0)
    if length <= 0 or channels <= 0 then note = "zero length"; return end
    local rate, points = 40, math.ceil(length * 40)
    if points > 4096 then points = 4096; rate = points / length end
    local buf = r.new_array(points * channels * 3)
    buf.clear()
    local returned = r.PCM_Source_GetPeaks(source, rate, 0, channels, points, 0, buf) & 0xFFFFF
    if returned <= 0 then note = "peaks not available"; return end
    local highest = 0
    for i = 1, points * channels * 2 do
      local value = math.abs(buf[i] or 0)
      if value > highest then highest = value end
    end
    peak = highest
  end)
  if r.PCM_Source_Destroy then r.PCM_Source_Destroy(source) end
  if not peak then return nil, note or "scan failed" end
  if peak <= 0 then return -math.huge end
  return 20 * math.log(peak, 10)
end

r.ClearConsole()
line("TK Idea Vault preview probe")
line("REAPER " .. tostring(r.GetAppVersion()))
line("SWS preview API: " .. yes(r.CF_CreatePreview ~= nil))
if not ok_store then
  line("Could not load core/idea_vault_store.lua: " .. tostring(Store))
  line("This script belongs in the TK Workbench folder, beside TK_Workbench.lua.")
  return
end

--------------------------------------------------------------------------------
-- what would be captured
--------------------------------------------------------------------------------

local cfg = Store.get_config()
local tracks = Store.collect_tracks(cfg.include_folder_children)

head("Selection")
line(string.format("%d track(s) would be captured (folder children: %s)", #tracks, yes(cfg.include_folder_children)))
for _, track in ipairs(tracks) do
  line("  " .. track_label(track)
    .. "   items: " .. tostring(r.CountTrackMediaItems(track))
    .. "   master/parent send: " .. yes(r.GetMediaTrackInfo_Value(track, "B_MAINSEND") == 1)
    .. "   muted: " .. yes(r.GetMediaTrackInfo_Value(track, "B_MUTE") == 1)
    .. "   volume: " .. string.format("%.2f", r.GetMediaTrackInfo_Value(track, "D_VOL") or 0))
  local parent = r.GetParentTrack(track)
  if parent then line("      parent folder: " .. track_label(parent)) end
  for i = 0, (r.GetTrackNumSends(track, 0) or 0) - 1 do
    local dest = r.GetTrackSendInfo_Value(track, 0, i, "P_DESTTRACK")
    local muted = r.GetTrackSendInfo_Value(track, 0, i, "B_MUTE") == 1
    line("      send -> " .. track_label(dest) .. (muted and "  (muted)" or ""))
  end
end
if #tracks == 0 then
  line("Nothing is selected, so the rest is about the vault only.")
end

--------------------------------------------------------------------------------
-- the range the render would cover
--------------------------------------------------------------------------------

head("Render range")
local sel_start, sel_end = r.GetSet_LoopTimeRange(false, false, 0, 0, false)
local has_selection = sel_start and sel_end and sel_end > sel_start
if has_selection then
  line(string.format("Time selection: %.3fs - %.3fs  (%.3fs long)", sel_start, sel_end, sel_end - sel_start))
else
  line("Time selection: none")
end

local first, last
for _, track in ipairs(tracks) do
  for i = 0, r.CountTrackMediaItems(track) - 1 do
    local item = r.GetTrackMediaItem(track, i)
    local pos = r.GetMediaItemInfo_Value(item, "D_POSITION")
    local stop = pos + r.GetMediaItemInfo_Value(item, "D_LENGTH")
    if not first or pos < first then first = pos end
    if not last or stop > last then last = stop end
  end
end
if first and last then
  line(string.format("Items on those tracks: %.3fs - %.3fs", first, last))
else
  line("Items on those tracks: none")
end

if has_selection and first and last then
  local overlaps = sel_start < last and sel_end > first
  line("The time selection sits on those items: " .. yes(overlaps))
  if not overlaps then
    line("  >> The selection is somewhere else in the song, so it is ignored and")
    line("     the items decide the range. Up to 0.8.5 it won regardless, which")
    line("     rendered a stretch of project with nothing on it: a preview of")
    line("     exactly the right length, containing silence.")
  end
end

--------------------------------------------------------------------------------
-- what the render would hear
--------------------------------------------------------------------------------

head("Routing")
local in_idea, seen, queue, buses = {}, {}, {}, {}
local reaches_master = false
for _, track in ipairs(tracks) do
  in_idea[track] = true
  if not seen[track] then seen[track] = true; queue[#queue + 1] = track end
end
local function push(dest)
  if not dest or seen[dest] then return end
  seen[dest] = true
  queue[#queue + 1] = dest
  if not in_idea[dest] then buses[#buses + 1] = dest end
end
local head_index = 1
while head_index <= #queue do
  local track = queue[head_index]
  head_index = head_index + 1
  if r.GetMediaTrackInfo_Value(track, "B_MAINSEND") == 1 then
    local parent = r.GetParentTrack(track)
    if parent then push(parent) else reaches_master = true end
  end
  for i = 0, (r.GetTrackNumSends(track, 0) or 0) - 1 do
    if r.GetTrackSendInfo_Value(track, 0, i, "B_MUTE") == 0 then
      push(r.GetTrackSendInfo_Value(track, 0, i, "P_DESTTRACK"))
    end
  end
end
line("Reaches the master: " .. yes(reaches_master))
line(#buses .. " bus(es) would be soloed along with the idea:")
for _, bus in ipairs(buses) do line("  " .. track_label(bus)) end

local currently_soloed = 0
for i = 0, r.CountTracks(0) - 1 do
  if r.GetMediaTrackInfo_Value(r.GetTrack(0, i), "I_SOLO") ~= 0 then currently_soloed = currently_soloed + 1 end
end
line("Tracks soloed right now: " .. currently_soloed .. " (the capture clears these and puts them back)")

head("Render settings the capture would use")
line("Source: master mix (RENDER_SETTINGS 0)")
line("Channels: " .. tostring(cfg.channels) .. "   Sample rate: " .. tostring(cfg.samplerate == 0 and "project" or cfg.samplerate))
line("Tail: " .. tostring(cfg.tail_ms) .. " ms")
line("Format: " .. (cfg.render_format ~= "" and "pinned" or "the project's own"))
local ok_fmt, project_format = r.GetSetProjectInfo_String(0, "RENDER_FORMAT", "", false)
line("Project render format set: " .. yes(ok_fmt and project_format ~= ""))

--------------------------------------------------------------------------------
-- what is already in the vault
--------------------------------------------------------------------------------

head("Previews already in the vault")
local root = Store.root()
line(root)
local ideas = Store.list()
line(#ideas .. " idea(s)")
local shown = 0
for _, idea in ipairs(ideas) do
  if shown >= 8 then break end
  shown = shown + 1
  local status
  if not idea.has_preview then
    status = "no preview file"
  else
    local db, note = peak_db(idea.preview_path)
    if not db then
      status = "could not measure (" .. tostring(note) .. ")"
    elseif db == -math.huge then
      status = "SILENT - the file contains nothing but zeroes"
    elseif db < -80 then
      status = string.format("effectively silent (peak %.1f dB)", db)
    else
      status = string.format("has audio (peak %.1f dB)", db)
    end
  end
  line(string.format("  %-32s %6.2fs  %s", tostring(idea.name):sub(1, 32), tonumber(idea.duration) or 0, status))
end

head("Reading this")
line("A preview that HAS audio but plays back silent is a player problem, not a")
line("render problem - check the SWS line at the top and the volume of the")
line("preview, not the routing.")
line("A preview that is SILENT was rendered that way: compare the render range")
line("above with where the items actually are, then the routing.")

local saved = write_report()
if saved then
  line("")
  line("This report has also been written to:")
  line("  " .. saved)
  line("Attaching that file says the same thing as copying the console.")
end
