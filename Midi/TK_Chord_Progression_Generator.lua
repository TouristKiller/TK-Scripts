-- TK_Chord_Progression_Generator.lua
-- A cool chord progression generator for REAPER using reaImgui
-- Generates chord progressions based on key, scale, and length, with export to MIDI

local r = reaper
local ImGui = r.ImGui

-- Chord data
local keys = {"C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"}
local scales = {
    Major = {0, 2, 4, 5, 7, 9, 11},
    Minor = {0, 2, 3, 5, 7, 8, 10},
    Dorian = {0, 2, 3, 5, 7, 9, 10},
    Mixolydian = {0, 2, 4, 5, 7, 9, 10},
    Lydian = {0, 2, 4, 6, 7, 9, 11},
    Phrygian = {0, 1, 3, 5, 7, 8, 10},
    Locrian = {0, 1, 3, 5, 6, 8, 10}
}
local chord_types = {"", "m", "dim", "aug", "sus4", "7", "maj7", "m7", "dim7", "7sus4"}

-- GUI state
local ctx = ImGui.CreateContext("Chord Progression Generator")
local selected_key = 0
local selected_scale = 0
local progression_length = 4
local generated_progression = {}
local show_window = true

-- Function to generate chord progression
function generate_progression()
    generated_progression = {}
    local scale_notes = scales[table.getn(scales) == 0 and "Major" or (function() for k,v in pairs(scales) do if selected_scale == 0 then return k end selected_scale = selected_scale - 1 end end)()]
    local key_offset = selected_key
    for i = 1, progression_length do
        local root = (scale_notes[(i-1) % #scale_notes + 1] + key_offset) % 12
        local chord_type = chord_types[math.random(#chord_types)]
        table.insert(generated_progression, keys[root + 1] .. chord_type)
    end
end

-- Function to export to MIDI
function export_to_midi()
    if #generated_progression == 0 then return end
    local track = r.GetSelectedTrack(0, 0)
    if not track then r.ShowMessageBox("Please select a track first!", "Error", 0) return end
    local start_time = r.GetCursorPosition()
    local chord_duration = 2 -- seconds per chord
    for i, chord in ipairs(generated_progression) do
        local item = r.CreateNewMIDIItemInProj(track, start_time + (i-1)*chord_duration, start_time + i*chord_duration)
        local take = r.GetActiveTake(item)
        -- Parse chord and add notes (simplified: just root for now)
        local root_note = string.match(chord, "^([A-G]#?)")
        local midi_note = ({C=60, ["C#"]=61, D=62, ["D#"]=63, E=64, F=65, ["F#"]=66, G=67, ["G#"]=68, A=69, ["A#"]=70, B=71})[root_note]
        r.MIDI_InsertNote(take, false, false, 0, r.MIDI_GetPPQPosFromProjTime(take, chord_duration), 0, midi_note, 100, false)
    end
    r.UpdateArrange()
end

-- Main loop
function loop()
    if show_window then
        ImGui.SetNextWindowSize(ctx, 400, 300)
        if ImGui.Begin(ctx, "Chord Progression Generator", show_window) then
            ImGui.Text("Select Key:")
            selected_key = ImGui.Combo(ctx, "##key", selected_key, table.concat(keys, "\0") .. "\0")
            ImGui.Text("Select Scale:")
            local scale_names = {}
            for k in pairs(scales) do table.insert(scale_names, k) end
            selected_scale = ImGui.Combo(ctx, "##scale", selected_scale, table.concat(scale_names, "\0") .. "\0")
            ImGui.Text("Progression Length:")
            progression_length = ImGui.SliderInt(ctx, "##length", progression_length, 1, 8)
            if ImGui.Button(ctx, "Generate Progression") then
                generate_progression()
            end
            ImGui.Separator()
            ImGui.Text("Generated Progression:")
            for i, chord in ipairs(generated_progression) do
                ImGui.Text(tostring(i) .. ": " .. chord)
            end
            if ImGui.Button(ctx, "Export to MIDI") then
                export_to_midi()
            end
            ImGui.End()
        end
    end
    if show_window then r.defer(loop) else ImGui.DestroyContext(ctx) end
end

r.defer(loop)