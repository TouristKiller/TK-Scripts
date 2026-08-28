local source = debug.getinfo(1, "S").source:sub(2)
local tests_dir = source:match("^(.*[\\/])") or ""
local root_dir = tests_dir:gsub("tests[\\/]$", "")
package.path = root_dir .. "?.lua;" .. root_dir .. "?" .. package.config:sub(1, 1) .. "init.lua;" .. package.path

local real_reaper = reaper
local note_reads = 0
local midi_hash = "hash-1"
local hash_notes_only = nil

local first_take = {
  guid = "{TAKE-1}", pitch = 0, playrate = 1, startoffs = 0, source = { length = 2 },
  notes = {
    { false, 0, 1920, 60 }, { false, 0, 1920, 64 }, { false, 0, 1920, 67 },
    { true, 0, 1920, 61 }
  },
  texts = {}
}
local second_take = {
  guid = "{TAKE-2}", pitch = 2, playrate = 2, startoffs = 0, source = { length = 2 },
  notes = {
    { false, 0, 1920, 53 }, { false, 0, 1920, 57 }, { false, 0, 1920, 60 }
  },
  texts = {}
}
local muted_take = {
  guid = "{TAKE-3}", pitch = 0, playrate = 1, startoffs = 0, source = { length = 2 },
  notes = { { false, 0, 1920, 61 }, { false, 0, 1920, 65 }, { false, 0, 1920, 68 } },
  texts = {}
}

local first_item = { position = 0, length = 2, mute = 0, lane = 1, looped = 0, take = first_take }
local second_item = { position = 2, length = 4, mute = 0, lane = 1, looped = 1, take = second_take }
local muted_item = { position = 0, length = 2, mute = 1, lane = 1, looped = 0, take = muted_take }
local hidden_lane_item = { position = 0, length = 2, mute = 0, lane = -1, looped = 0, take = muted_take }
first_take.item, second_take.item, muted_take.item = first_item, second_item, muted_item
local track = { guid = "{TRACK-1}", items = { first_item, second_item, muted_item, hidden_lane_item } }

local mock = {}
function mock.ValidatePtr2(_, value, kind) return kind == "MediaTrack*" and value == track end
function mock.GetTrackGUID(value) return value.guid end
function mock.BR_GetMediaTrackByGUID(_, guid) return guid == track.guid and track or nil end
function mock.CountTracks() return 1 end
function mock.GetTrack(_, index) return index == 0 and track or nil end
function mock.EnumProjects() return "project-1" end
function mock.MIDI_GetTrackHash(_, notes_only) hash_notes_only = notes_only; return true, midi_hash end
function mock.CountTrackMediaItems(value) return #value.items end
function mock.GetTrackMediaItem(value, index) return value.items[index + 1] end
function mock.GetActiveTake(item) return item.take end
function mock.TakeIsMIDI() return true end
function mock.GetSetMediaItemTakeInfo_String(take) return true, take.guid end
function mock.GetMediaItemInfo_Value(item, key)
  local values = {
    D_POSITION = item.position, D_LENGTH = item.length, B_MUTE = item.mute,
    C_LANEPLAYS = item.lane, B_LOOPSRC = item.looped
  }
  return values[key]
end
function mock.GetMediaItemTakeInfo_Value(take, key)
  local values = { D_PITCH = take.pitch, D_PLAYRATE = take.playrate, D_STARTOFFS = take.startoffs }
  return values[key]
end
function mock.GetMediaItemTake_Source(take) return take.source end
function mock.GetMediaSourceLength(source_value) return source_value.length, true end
function mock.MIDI_CountEvts(take) return true, #take.notes, 0, #take.texts end
function mock.MIDI_GetNote(take, index)
  note_reads = note_reads + 1
  local note = take.notes[index + 1]
  if not note then return false end
  return true, false, note[1], note[2], note[3], 0, note[4], 100
end
function mock.MIDI_GetTextSysexEvt(take, index)
  local event = take.texts[index + 1]
  if not event then return false end
  return true, false, event[1], event[2], event[3], event[4]
end
function mock.MIDI_GetProjQNFromPPQPos(take, ppq) return take.item.position + ppq / 960 / take.playrate end
function mock.MIDI_GetPPQPosFromProjTime(take, time) return (time - take.item.position) * 960 * take.playrate end
function mock.MIDI_GetProjTimeFromPPQPos(take, ppq) return take.item.position + ppq / 960 / take.playrate end
function mock.TimeMap2_timeToQN(_, time) return time end
function mock.TimeMap2_QNToTime(_, qn) return qn end

reaper = mock
package.loaded["core.chord_timeline"] = nil
local Timeline = require("core.chord_timeline")

local passed = 0
local function expect(label, actual, expected)
  assert(actual == expected, string.format("%s: expected %s, got %s", label, tostring(expected), tostring(actual)))
  passed = passed + 1
end

local composed = Timeline.compose({
  { pitch = 60, start = 0, stop = 2 },
  { pitch = 64, start = 0, stop = 1 },
  { pitch = 64, start = 1, stop = 2 },
  { pitch = 67, start = 0, stop = 2 },
  { pitch = 62, start = 3, stop = 4 },
  { pitch = 66, start = 3, stop = 4 },
  { pitch = 69, start = 3, stop = 4 },
  { pitch = 61, start = 2.5, stop = 2.51 },
  { pitch = 65, start = 2.5, stop = 2.51 }
})
expect("composed count", #composed, 2)
expect("merged repeated chord", composed[1].name, "C")
expect("merged start", composed[1].start, 0)
expect("merged stop", composed[1].stop, 2)
expect("gap preserved", composed[2].start, 3)
expect("next chord", composed[2].name, "D")
expect("event indexes", composed[2].index, 2)
local current, next_event = Timeline.at(composed, 0.5)
expect("current lookup", current.name, "C")
expect("next lookup", next_event.name, "D")
current, next_event = Timeline.at(composed, 2.5)
expect("gap has no current", current, nil)
expect("gap keeps next", next_event.name, "D")
current, next_event = Timeline.at(composed, 4)
expect("end has no current", current, nil)
expect("end has no next", next_event, nil)
current, next_event = Timeline.at({
  { name = "C", start = 0, stop = 1 },
  { name = "C", start = 2, stop = 3 }
}, 0.5)
expect("same chord after gap is next", next_event.name, "C")

local naming_spans = {
  { pitch = 50, start = 0, stop = 1 },
  { pitch = 53, start = 0, stop = 1 },
  { pitch = 58, start = 0, stop = 1 }
}
local sharp_name = Timeline.compose(naming_spans)
expect("sharp naming", sharp_name[1].name, "A#/D")
local flat_name = Timeline.compose(naming_spans, {
  chord_options = { prefer_flats = true, include_bass = false }
})
expect("flat naming without slash bass", flat_name[1].name, "Bb")

local overridden = Timeline.compose({
  { pitch = 60, start = 0, stop = 3 },
  { pitch = 64, start = 0, stop = 3 },
  { pitch = 67, start = 0, stop = 3 }
}, nil, {
  { name = "Cmaj13(#11)/E", start = 1, stop = 2 }
})
expect("override splits automatic chord", #overridden, 3)
expect("automatic before override", overridden[1].name, "C")
expect("free override name", overridden[2].name, "Cmaj13(#11)/E")
expect("override flag", overridden[2].manual, true)
expect("automatic after override", overridden[3].name, "C")

local clustered = Timeline.compose({
  { pitch = 60, start = 0, stop = 1 },
  { pitch = 64, start = 0.04, stop = 1 },
  { pitch = 67, start = 0.08, stop = 1 }
}, { attack_tolerance = 0.1 })
expect("clustered attack count", #clustered, 1)
expect("clustered attack name", clustered[1].name, "C")
expect("clustered attack starts first", clustered[1].start, 0)

local contextual_timeline = Timeline.compose({
  { pitch = 48, start = 0, stop = 1 },
  { pitch = 52, start = 0, stop = 1 },
  { pitch = 55, start = 0, stop = 1 },
  { pitch = 57, start = 0, stop = 1 }
}, { chord_options = { key_root = 9, key_mode = "minor" } })
expect("timeline key context", contextual_timeline[1].name, "Am7/C")
expect("timeline alternative", contextual_timeline[1].alternatives[1].name, "C6")

local events, error_code = Timeline.build(track.guid)
expect("build error", error_code, nil)
expect("track event count", #events, 2)
expect("cache includes text events", hash_notes_only, false)
expect("first track chord", events[1].name, "C")
expect("transposed loop chord", events[2].name, "G")
expect("loop reaches item end", events[2].stop, 6)
local reads_after_build = note_reads

local cached = Timeline.build(track.guid)
expect("cache identity", cached, events)
expect("cache avoids note reads", note_reads, reads_after_build)

local option_events = Timeline.build(track.guid, { minimum_duration = 0.1 })
expect("options invalidate cache", option_events == events, false)
local reads_after_options = note_reads
local option_cached = Timeline.build(track.guid, { minimum_duration = 0.1 })
expect("option cache identity", option_cached, option_events)
expect("option cache avoids note reads", note_reads, reads_after_options)

midi_hash = "hash-2"
local rebuilt = Timeline.build(track.guid)
expect("hash invalidates cache", rebuilt == events, false)
expect("rebuild reads notes", note_reads > reads_after_build, true)

first_take.texts = {
  { false, 0, 1, "CHORD: Cmaj9" },
  { false, 100, 1, "LYRIC: ignored" },
  { true, 480, 1, "CHORD: Muted" },
  { false, 960, 1, " chord : G13 " }
}
second_take.texts = { { false, 0, 1, "CHORD: Long jazzy name" } }
midi_hash = "hash-text"
local text_events = Timeline.build(track.guid)
expect("text event count", #text_events, 3)
expect("first text override", text_events[1].name, "Cmaj9")
expect("second text override", text_events[2].name, "G13")
expect("looped text override", text_events[3].name, "Long jazzy name")
expect("text override reaches loop end", text_events[3].stop, 6)
expect("read override flag", text_events[3].manual, true)

local missing, missing_error = Timeline.build("{MISSING}")
expect("missing track list", #missing, 0)
expect("missing track error", missing_error, "track_not_found")

reaper = real_reaper
local message = string.format("Chord timeline: %d tests passed", passed)
if real_reaper and real_reaper.ShowConsoleMsg then
  real_reaper.ShowConsoleMsg(message .. "\n")
else
  print(message)
end