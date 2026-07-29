-- @description TK Kit Maker
-- @author TouristKiller & Flurmechanic
-- @version 0.2.33
-- @changelog:
--   + Re-analyse changed files: compares each sample with the file on disk and
--     re-measures only what was edited or replaced. The sample you click on is
--     checked the same way, so a re-rendered file shows its new figures.
--   + "Export as a kit folder..." on both halves of the Browser. From the
--     heatmap it writes the picked pads out; from the file list, on the right-
--     click menu of the open collection, it writes out whatever the list is
--     showing -- so the tag and filename filters are the selection, and cutting
--     213 samples down to the twelve you want makes a kit of exactly those.
--     Copied, numbered and named the way an exported kit always is.
--   # Step sequencer: the four pattern pages now survive a restart without a
--     preset. They lived in memory only; they are kept on the kit track, in
--     their own key beside the sequence.
--   + Sample analysis: measures every sample's spectrum and envelope and tags
--     it by frequency band, transient, decay and tonality (plus spatiality on
--     stereo material). Results are cached per file; the raw measurements are
--     what is stored, so the labels can be retuned without re-analysing.
--   # Analysis reads a one-shot once instead of twice. The coarse envelope pass
--     and the sample block at the onset meant a short file was decoded very
--     nearly twice over; files up to 5 s are now read in one go and the
--     envelope is folded out of those samples, in the same sweep that reads
--     them, and mono and stereo skip the per-channel loop. The progress line
--     reports the measured milliseconds per sample when a run finishes.
--   # Analysis pacing corrected. A frame always measures at least one file
--     before checking the clock, so the old 12 ms budget never meant 12 ms --
--     it meant one file, and the smaller playback budget eased off nothing at
--     all. Idle now fits two files per frame, and playback skips frames
--     instead, which is the only thing that actually reduces the load.
--   + Analysis is always started by hand: an Analyse/Stop button with progress
--     and a time estimate, which pauses while REAPER records and eases off
--     during playback. Stopping keeps everything measured so far, so a later
--     run simply continues. The sample you click on is measured on the spot.
--   + Browser tags panel: the labels as chips, the spectrum across the seven
--     bands, and where the sample sits on each axis. Hover for the raw numbers.
--   + Browser heatmap: a List/Heatmap toggle puts the analysed samples on a
--     grid -- two measured axes across it, the third as a weighting slider
--     underneath. The axes rescale to the current selection, so narrowing to
--     one category still spreads the samples out instead of stacking them in a
--     single column. Filter by category and set the grid from 3x3 to 8x8.
--   + Clicking a heatmap cell walks through it in weighted order without
--     repeats (shift-click steps back); the cell is ringed and reads which of
--     its samples is playing.
--   + Make rack: at 4x4 the grid is a pad layout, so one press builds a 16-pad
--     RS5K kit that spans the sound space -- pad 1 the darkest and shortest,
--     pad 16 the brightest and longest. Fills the selected rack or creates a
--     new one, and Re-roll keeps the layout while drawing new samples.
--   + Show kit: marks where an existing rack's pads sit on the heatmap, so a
--     kit clustered in one corner -- and the range it is missing -- shows
--     itself. Warns when the rack is not from the collection on screen, since
--     the axes are scaled to that.
--   # The heatmap's own category dropdown is gone: the Tags filter above it
--     already narrows what the grid is built from, and does more. The two
--     ANDed rather than replaced each other, so a category picked in one and a
--     different one in the other emptied the grid with no way to see why.
--   # Builder: adding a pool after loading a preset destroyed one of the
--     preset's pools. New pools were numbered from a counter the preset never
--     advanced, so "+ Pool" reused an id the preset already held: the filled
--     pool was replaced by an empty one and then listed twice. Ids in use are
--     now skipped, whoever put them there.
--   + Builder: "From pattern..." builds the whole slot table from a comma
--     separated list, the same one Explosion takes. Each slot gets its filter,
--     and the pool whose alias matches the word -- so pools named Kick / Snare
--     / Hihat link themselves, which was the slowest part of setting a kit up.
--     The popup shows what each word resolved to before you commit, and it
--     offers the slot-pattern presets Explosion has always had -- one shared
--     list now, so a pattern saved on either page appears on the other.
--   # Builder regrouped to match: 1 Pools, 2 Slots, 3 Export, none of them
--     collapsible -- the export button could be folded out of sight. Quick
--     layout moved into Slots, where it belongs (it builds slots, and replaces
--     the ones you have -- it now says how many before you press it), and
--     Presets moved to a bar at the top, being a file operation rather than a
--     step. Export reports readiness: how many slots have no pool, and opens
--     with the destination folder rather than burying it among the batch
--     options -- the same order Explosion now uses.
--   # Explosion regrouped: "Kit layout" held three unrelated things and opened
--     with the naming, the part you settle last. It is now 3 Kit layout,
--     3 Slot pattern, 4 Naming, 5 Export -- one question per step, in the
--     order you actually answer them, and every field labelled the same way.
--     Character is shown open instead of folded into a header, and the
--     destination folder moved into Export, where the Builder has always kept
--     it: steps 1-4 are the kit, step 5 is writing it out.
--   # Browser top row tidied: List/Tiles is one toggle and Catalog/Split/
--     Samples one cycling button (right-click steps back), which is what they
--     always were -- one setting each, spread over two and three buttons.
--   # Start folder now overrules the recently-used folder instead of being a
--     fallback for it: set one and every browse dialog opens there. Clearing it
--     hands control back to the recent folders. It has moved off the top row
--     onto the right-click menu of "+ Folder", being a set-once setting.
--   + Browser: Flat list / Folders toggle for the sample list -- one run of
--     samples instead of folder groups, which is what you want once a tag
--     filter has cut a collection down to a few files spread over many folders
--   + Browser tag filter: narrow the sample list by what the samples sound
--     like. Only the tags actually present in the collection are offered, with
--     counts that already take your other choices into account, so a pack of
--     kicks never offers AIR. Within an axis the tags are OR'd (SUB or LOW),
--     across axes they are AND'ed (SUB/LOW and SHORT). Category is multi-label
--     -- an open hihat is a hihat too, so Hihat returns both -- with an
--     Uncategorised entry for names the rules do not recognise, which are the
--     same files that will not answer a Builder slot filter. Source is
--     read off the
--     path rather than the audio, so that one axis filters a pack you have not
--     analysed yet -- and it now reads the whole path, since what marks a pack
--     as acoustic or foley sits in the folder name, not in SN_01.wav. Where
--     two sources both match, the stronger one wins and a tie tags nothing.
--   + Character bias in Explosion and Builder: steer the random pick towards a
--     sound (dark, punchy, short) on the measured axes. Slots can override the
--     kit-wide setting in the Builder's Char column.
--
--     NOTE -- the tag filter FILTERS, the character bias WEIGHTS, and that is
--     deliberate. Searching wants a hard answer: ask for the noise hats and you
--     get the noise hats. Generating wants a soft one, because a hard threshold
--     there would collapse a batch of 50 kits onto the same handful of samples,
--     put an arbitrary cliff between two samples you cannot tell apart, and
--     turn every measurement error into a sample you can never hear again.
--     Weighting keeps the whole pool in play and only shifts the odds, so 50
--     kits stay 50 different kits that all lean the same way. It is also the
--     wider choice: turn the focus up and it behaves like a filter anyway.
--     Unanalysed samples follow the same split -- excluded by the filter,
--     counted as average by the bias, so a bias over an unanalysed pack falls
--     back to plain random instead of quietly becoming a filter.
--   # Step sequencer: the four pattern pages now work without a saved preset.
--     They shared a single sequence, so editing or clearing one hit all four.
--   # Step sequencer: saving a preset no longer blanks pages 2-4. The pages
--     were looked up under the new preset's number instead of where they were
--     edited, which also lost them on 'save as new'.
--   # RS5K detection is now shared between the Browser and the Kit Manager.
--     The Browser matched on plugin name alone, so a renamed instance was not
--     found and filling a pad stacked a second RS5K beside it instead of
--     replacing the sample.

local r = reaper

local SCRIPT_NAME = "TK Kit Maker"
if not r.ImGui_CreateContext then
  r.ShowMessageBox("ReaImGui is required for TK Kit Maker.\nInstall 'ReaImGui: ReaScript binding for Dear ImGui' via ReaPack.", SCRIPT_NAME, 0)
  return
end

local script_path = debug.getinfo(1, "S").source:match("@?(.*[\\/])") or ""
local sep = package.config:sub(1, 1)
package.path = script_path .. "?.lua;" .. script_path .. "?" .. sep .. "init.lua;" .. package.path

math.randomseed(os.time() + math.floor((r.time_precise and r.time_precise() or os.clock()) * 1000))

local MainWindow = require("ui.main_window")

local ctx = r.ImGui_CreateContext(SCRIPT_NAME)

local app = {
  ctx = ctx,
  script_name = SCRIPT_NAME,
  script_path = script_path,
}

MainWindow.init(app)

local function loop()
  local ok, open = pcall(MainWindow.frame, app)
  if not ok then
    r.ShowConsoleMsg(SCRIPT_NAME .. " error: " .. tostring(open) .. "\n")
    return
  end
  if open then
    r.defer(loop)
  end
end

r.defer(loop)
