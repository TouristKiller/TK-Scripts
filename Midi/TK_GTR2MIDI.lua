-- @description TK GTR2MIDI
-- @author TouristKiller
-- @version 0.2.7
-- @changelog
--[[ 
0.2.7
+ Added Lock GUI window button

0.2.6       
+ Persitant settings (Chord, Sequence, Horizontal, XL mode)
+ Removerd Move GUI Window only via logo (this was not practical and gave problems with multi monitor setups)
+ Added highlight for Fret Circels
+ New whay of showing barre chords
+ Bigger click area to select fret positions
+ Small UI Improvements
]]--   
------------------------------------------------------------------------
local r                         = reaper
local ImGui

if r.APIExists('ImGui_GetBuiltinPath') then
    if not r.ImGui_GetBuiltinPath then
        return r.MB('This script requires ReaImGui extension','',0)
    end
    package.path                = r.ImGui_GetBuiltinPath() .. '/?.lua'
    ImGui                       = require 'imgui' '0.9'
else
    return r.MB('This script requires ReaImGui extension 0.9+','',0)
end


-- ImGui initialization
local ctx                       = ImGui.CreateContext('TK_GTR2MIDI')
local font_small                = ImGui.CreateFont('Arial', 12)
local font_large                = ImGui.CreateFont('Arial', 16)
local font                      = font_small 
ImGui.Attach(ctx, font_small)
ImGui.Attach(ctx, font_large)
ImGui.SetConfigVar(ctx, ImGui.ConfigVar_WindowsMoveFromTitleBarOnly, 1)

-- Core variables
local is_pinned                 = false
local is_nomove                 = false
local is_xl_mode                = false
local separator                 = package.config:sub(1,1)
local script_path               = debug.getinfo(1,'S').source:match("@(.*)" .. separator)

-- Input state
local input_sequence            = ""
local input_chord               = ""
local selected_duration         = "4"
local selected_string           = 1

-- Musical data
local base_notes                = {64,59,55,50,45,40}
local string_names              = {"E (High)","B","G","D","A","E (Low)"}
local custom_notes              = {64,59,55,50,45,40}
local custom_tuning_name        = ""

-- Voicing configuration
local voicings                  = {}
local selected_voicing_file     = r.GetExtState("TK_GTR2MIDI", "selected_voicing_file")
if selected_voicing_file == "" then
    selected_voicing_file       = "ChordVoicings.txt"
end

-- UI state
local show_custom_tuning_window = false
local chord_fingers             = {}
local chord_board_horizontal    = false
local insert_in_existing        = false
local show_sequence             = false
local show_chord                = true
local status_message            = ""
local status_color              = 0xFFFFFFFF

-- Transpose configuration
local transpose_modes           = {
    ["Semi"]                    = 1,
    ["Whole"]                   = 2
}

local selected_transpose_mode   = "Semi"

-- Tuning presets
local tunings                   = {
    ["Standard (EADGBE)"]       = {64,59,55,50,45,40},
    ["Drop D (DADGBE)"]         = {64,59,55,50,45,38},
    ["Open G (DGDGBD)"]         = {62,59,55,50,43,38},
    ["Open D (DADF#AD)"]        = {62,57,54,50,45,38},
    ["DADGAD"]                  = {62,57,55,50,45,38}
}

local selected_tuning           = "Standard (EADGBE)"
base_notes                      = tunings[selected_tuning]

-- Visual styling
local finger_colors             = {
    [1]                         = 0xEF0038FF,
    [2]                         = 0x38B549FF,
    [3]                         = 0x0099DDFF,
    [4]                         = 0xF5811FFF
}

-- Laad opgeslagen instellingen
show_sequence                   = r.GetExtState("TK_GTR2MIDI", "show_sequence") == "true" 
show_chord                      = r.GetExtState("TK_GTR2MIDI", "show_chord") == "true"
chord_board_horizontal          = r.GetExtState("TK_GTR2MIDI", "chord_board_horizontal") == "true"
local is_xl_mode                = r.GetExtState("TK_GTR2MIDI", "is_xl_mode") == "true"
local font                      = is_xl_mode and font_large or font_small
------------------------------------------------------------------------
local function GetCurrentTimeSig()
    local timepos = r.GetCursorPosition()
    local timesig_num, timesig_denom = r.TimeMap_GetTimeSigAtTime(0, timepos)
    return timesig_num, timesig_denom
end

local function GTR2MIDI_esc_key() 
    if ImGui.IsKeyPressed(ctx, ImGui.Key_Escape) then
        return true
    end
    return false
end

function GetAvailableVoicingFiles()
    local voicing_files = {}
    local path = script_path .. separator
    local i = 0
    repeat
        local file = r.EnumerateFiles(path, i)
        if file and file:match("^ChordVoicings.*%.txt$") then
            table.insert(voicing_files, file)
        end
        i = i + 1
    until not file
    return voicing_files
end

function LoadVoicings()
    local file = io.open(script_path .. separator .. selected_voicing_file, "r")
    if file then
        for line in file:lines() do
            if not line:match("^#") and line:match("|") then
                local voicing, chord, fingers = line:match("(.+)|(.+)|(.+)")
                if voicing and chord then
                    voicing = voicing:match("^%s*(.-)%s*$")
                    chord = chord:match("^%s*(.-)%s*$")
                    if fingers then
                        local finger_array = {}
                        for finger in fingers:gmatch("%S+") do
                            table.insert(finger_array, tonumber(finger))
                        end
                        chord_fingers[voicing] = finger_array
                    end
                    voicings[voicing] = chord
                end
            end
        end
        file:close()
    end
end
LoadVoicings()

function GetNoteName(midi_note)
    local notes = {"C","C#","D","D#","E","F","F#","G","G#","A","A#","B"}
    local note_index = (midi_note % 12) + 1
    return notes[note_index]
end

function DetermineChordName(chord_shape)
    local frets_table = {}
    for fret in chord_shape:gmatch("%S+") do
        table.insert(frets_table, fret)
    end
    local voicing = table.concat(frets_table, " ")
    return voicings[voicing] or "(?)"
end

local function normalizeChordName(chord)
    local base, variation = chord:match("^(.-)%s*(%(.+%))$")
    if base and variation then
        base = base:lower():gsub("%s+", "")
        base = base:gsub("sus%s*(%d)", "sus%1")
        base = base:gsub("add%s*(%d)", "add%1")
        return base .. " " .. variation
    else
        local normalized = chord:lower():gsub("%s+", "")
        normalized = normalized:gsub("sus%s*(%d)", "sus%1")
        normalized = normalized:gsub("add%s*(%d)", "add%1")
        return normalized
    end
end

function GetMidiNote(string_num, fret)
    if fret == "X" then return nil end
    local base_note = base_notes[7-string_num]
    return base_note + tonumber(fret)
end

function FindFretForNote(string_num, target_note)
    local base_note = base_notes[7-string_num]
    local fret = target_note - base_note
    if fret >= 0 and fret <= 24 then
        return tostring(fret)
    end
    return "X"
end

function TransposeChord(interval, direction)
    local new_chord = {}
    local string_num = 1
    
    local current_notes = {}
    for fret in input_chord:gmatch("%S+") do
        local note = GetMidiNote(string_num, fret)
        if note then
            current_notes[string_num] = note
        end
        string_num = string_num + 1
    end
    string_num = 1
    for fret in input_chord:gmatch("%S+") do
        if fret == "X" then
            table.insert(new_chord, "X")
        else
            local current_note = current_notes[string_num]
            local target_note = current_note + (interval * direction)
            local new_fret = FindFretForNote(string_num, target_note)
            table.insert(new_chord, new_fret)
        end
        string_num = string_num + 1
    end
    
    return table.concat(new_chord, " ")
end

function TransposeSequence(interval, direction)
    local new_seq = {}
    local base_note = base_notes[selected_string]
    
    for note in input_sequence:gmatch("([^-]+)") do
        if note ~= "0" then
            local current_note = base_note + tonumber(note)
            local target_note = current_note + (interval * direction)
            local new_fret = target_note - base_note
            if new_fret >= 0 and new_fret <= 24 then
                table.insert(new_seq, tostring(new_fret))
            end
        else
            table.insert(new_seq, "0")
        end
    end
    
    return table.concat(new_seq, "-")
end

function SaveCustomTunings(tunings)
    local file = io.open(script_path .. separator .. "CustomTunings.txt", "w")
    if file then
        for name, notes in pairs(tunings) do
            if type(notes) == "table" then  
                file:write(name .. "|" .. table.concat(notes, " ") .. "\n")
            end
        end
        file:close()
    end
end

function LoadCustomTunings()
    local custom_tunings = {}
    local file = io.open(script_path .. separator .. "CustomTunings.txt", "r")
    if file then
        for line in file:lines() do
            local name, notes = line:match("(.+)|(.+)")
            if name and notes then
                local note_table = {}
                for note in notes:gmatch("%d+") do
                    table.insert(note_table, tonumber(note))
                end
                custom_tunings[name] = note_table
                tunings[name] = note_table  
            end
        end
        file:close()
    end
    return custom_tunings
end

local custom_tunings = LoadCustomTunings()

function DeleteCustomTuning(tuning_name)
    if custom_tunings[tuning_name] then
        custom_tunings[tuning_name] = nil
        tunings[tuning_name] = nil
        SaveCustomTunings(custom_tunings)

        local voicing_filename = "ChordVoicings_" .. tuning_name .. ".txt"
        os.remove(script_path .. separator .. voicing_filename)

        if selected_tuning == tuning_name then
            selected_tuning = "Standard (EADGBE)"
            base_notes = tunings[selected_tuning]
        end
    end
end

function ShowCustomTuningWindow()
    ImGui.PushFont(ctx, font)
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowRounding, 12.0)
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_FrameRounding, 6.0)
    ImGui.PushStyleColor(ctx, ImGui.Col_WindowBg, 0x000000FF)
    ImGui.PushStyleColor(ctx, ImGui.Col_Button, 0x1A1A1AFF)
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, 0x333333FF)
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, 0x404040FF)
    ImGui.PushStyleColor(ctx, ImGui.Col_FrameBg, 0x1A1A1AFF)
    ImGui.PushStyleColor(ctx, ImGui.Col_FrameBgHovered, 0x333333FF)
    ImGui.PushStyleColor(ctx, ImGui.Col_FrameBgActive, 0x404040FF)

    local visible, opened = ImGui.Begin(ctx, "Custom Tuning Editor", true, window_flags)
    if visible then
        local changed, new_name = ImGui.InputText(ctx, "Tuning Name", selected_tuning)
        if changed then
            custom_tuning_name = new_name
        end
        
        if tunings[selected_tuning] then
            custom_notes = {table.unpack(tunings[selected_tuning])}
        end
        
        ImGui.Text(ctx, "String tunings:")
        for i=1,6 do
            ImGui.PushItemWidth(ctx, 60)
            local current_note = GetNoteName(custom_notes[i])
            if ImGui.BeginCombo(ctx, "String " .. i, current_note) then
                for note = 40,64 do
                    local note_name = GetNoteName(note)
                    if ImGui.Selectable(ctx, note_name, note == custom_notes[i]) then
                        custom_notes[i] = note
                        tunings[selected_tuning][i] = note  
                    end
                end
                ImGui.EndCombo(ctx)
            end
        end

        if ImGui.Button(ctx, "Save Tuning") and custom_tuning_name ~= "" then
            custom_tunings[custom_tuning_name] = {table.unpack(custom_notes)}
            tunings[custom_tuning_name] = {table.unpack(custom_notes)}
            SaveCustomTunings(custom_tunings)
        
            local voicing_filename = "ChordVoicings_" .. custom_tuning_name .. ".txt"
            local file = io.open(script_path .. separator .. voicing_filename, "w")
            if file then
                file:write("# Chord voicings for " .. custom_tuning_name .. " tuning\n")
                file:write("# Format: FRET_POSITIONS | CHORD_NAME | FINGER_POSITIONS\n")
                file:write("# Example: 0 2 2 1 0 0 | Em | 0 2 3 1 0 0\n")
                file:close()
            end
            
            show_custom_tuning_window = false
        end
        
        ImGui.SameLine(ctx)
        ImGui.SameLine(ctx)
        if ImGui.Button(ctx, "Delete Tuning") then
            if selected_tuning ~= "Standard (EADGBE)" and 
               selected_tuning ~= "Drop D (DADGBE)" and
               selected_tuning ~= "Open G (DGDGBD)" and
               selected_tuning ~= "Open D (DADF#AD)" and
               selected_tuning ~= "DADGAD" then
                DeleteCustomTuning(selected_tuning)
                show_custom_tuning_window = false
            end
        end

        ImGui.SameLine(ctx)
        if ImGui.Button(ctx, "Cancel") then
            show_custom_tuning_window = false
        end

        ImGui.End(ctx)
    end
    ImGui.PopStyleColor(ctx, 7)
    ImGui.PopStyleVar(ctx, 2)
    ImGui.PopFont(ctx)
    
    if not opened then
        show_custom_tuning_window = false
    end
end

function CreateMIDIItem(insert_type)
    local track = r.GetSelectedTrack(0,0)
    if not track then return end
    
    local existing_item, existing_take = GetSelectedMIDIItem()
    local cursor_pos = r.GetCursorPosition()
    local ppq = 960
    local timesig_num, timesig_denom = r.TimeMap_GetTimeSigAtTime(0, cursor_pos)
    local beats = (timesig_num * 4) / timesig_denom
    local duration_factor = (4 / tonumber(selected_duration)) / 4
    local note_length = ppq * beats * duration_factor
    
    if existing_item and insert_in_existing then
        local item_end = cursor_pos + (beats * duration_factor) / 2
        r.SetEditCurPos(item_end, true, true)
        return existing_item, existing_take, note_length
    end

    local note_count = 0
    for _ in input_sequence:gmatch("([^-]+)") do 
        note_count = note_count + 1 
    end
    
    local item_length
    if insert_type == "sequence" then
        item_length = ((beats * duration_factor) * note_count) / 2
    else
        item_length = (beats * duration_factor) / 2
    end
    
    local item = r.CreateNewMIDIItemInProj(track, cursor_pos, cursor_pos + item_length)
    local take = r.GetActiveTake(item)
    r.SetEditCurPos(cursor_pos + item_length, true, true)
    
    return item, take, note_length
end

function GetSelectedMIDIItem()
    local item = r.GetSelectedMediaItem(0, 0)
    if item then
        local take = r.GetActiveTake(item)
        if take and r.TakeIsMIDI(take) then
            return item, take
        end
    end
    return nil, nil
end

function DetermineFingerPositions(chord_shape)
    for voicing, chord_name in pairs(voicings) do
        if voicing == chord_shape then
            return chord_fingers[chord_name]
        end
    end
    local fingers = {}
    local fret_finger_map = {}
    local lowest_playing_fret = 99 
    local i = 1
    for fret in chord_shape:gmatch("%S+") do
        if fret ~= "X" and fret ~= "0" then
            local fret_num = tonumber(fret)
            lowest_playing_fret = math.min(lowest_playing_fret, fret_num)
        end
        i = i + 1
    end
    i = 1
    for fret in chord_shape:gmatch("%S+") do
        if fret == "X" or fret == "0" then
            table.insert(fingers, nil)
        else
            local fret_num = tonumber(fret)
            if not fret_finger_map[fret_num] then
                local finger = 1 + (fret_num - lowest_playing_fret)
                if finger > 4 then finger = 4 end
                fret_finger_map[fret_num] = finger
            end
            table.insert(fingers, fret_finger_map[fret_num])
        end
        i = i + 1
    end
    return fingers
end

function DrawFingerLegend(ctx, startX, startY)
    local draw_list = ImGui.GetWindowDrawList(ctx)
    local spacing = 25
    local circle_size = is_xl_mode and 10 or 8
    local labels = {
        "- Index finger",
        "- Middle finger", 
        "- Ring finger",
        "- Pinky"
    }
    ImGui.DrawList_AddText(draw_list, startX, startY-30, 0xFFFFFFFF, "Finger positions:")
    
    for i, label in ipairs(labels) do
        local y = startY + (i-1) * spacing
        local circle_x = startX + circle_size
        local circle_y = y
        ImGui.DrawList_AddCircleFilled(draw_list, circle_x, circle_y, circle_size, finger_colors[i])
        ImGui.DrawList_AddCircle(draw_list, circle_x, circle_y, circle_size, 0xFFFFFFFF)
        local text_width = ImGui.CalcTextSize(ctx, tostring(i))
        local text_x = circle_x - (text_width/2)
        local text_y = circle_y - (ImGui.GetTextLineHeight(ctx)/2)
        ImGui.DrawList_AddText(draw_list, text_x, text_y, 0x000000FF, tostring(i))
        ImGui.DrawList_AddText(draw_list, startX + (circle_size * 2) + 10, y - 6, 0xFFFFFFFF, label)
    end
end

function InsertChord(take, frets, note_length, start_ppq)
    local ppq_pos = start_ppq or 0
    for string_num, fret in ipairs(frets) do
        if fret ~= "X" then
            local note = base_notes[7-string_num] + tonumber(fret)
            local midi_channel = string_num-1
            r.MIDI_InsertNote(take, false, false, ppq_pos, ppq_pos + note_length, midi_channel, note, 100, false)
        end
    end
    local chord_shape = table.concat(frets, " ")
    local chord_name = DetermineChordName(chord_shape)
    local fingers = chord_fingers[chord_name] or DetermineFingerPositions(chord_shape)
    local finger_text = ""
    if fingers then
        finger_text = " [Fingers: " .. table.concat(fingers, "-") .. "]"
    end
    local take_name = string.format("%s (%s)%s", chord_shape, chord_name, finger_text)
    r.GetSetMediaItemTakeInfo_String(take, "P_NAME", take_name, true)
    r.MIDI_Sort(take)
end

function InsertSequence(take, notes, note_length, start_ppq)
    local base_note = base_notes[selected_string]
    local position = start_ppq or 0
    local note_count = 0 
    r.GetSetMediaItemTakeInfo_String(take, "P_NAME", notes, true)
    for _ in notes:gmatch("([^-]+)") do 
        note_count = note_count + 1 
    end
    local item = r.GetMediaItemTake_Item(take)
    for note in notes:gmatch("([^-]+)") do
        local midi_note = base_note + tonumber(note)
        r.MIDI_InsertNote(take, false, false, position, position + note_length, 0, midi_note, 100, false)
        position = position + note_length
    end
    r.MIDI_Sort(take)
end

function HandleChordSelection(string_num, fret, rightClick)
    local frets={"X","X","X","X","X","X"}
    local i=1
    for existing_fret in input_chord:gmatch("%S+") do
        frets[i]=existing_fret
        i=i+1
    end
    frets[string_num+1]=rightClick and "X" or tostring(fret)
    input_chord=table.concat(frets," ")
end

function FilterChordInput(input)
    local filtered = input:gsub("[^X0-9%s]", "")
    return filtered
end

local function IsMouseOverCircle(mouse_x, mouse_y, circle_x, circle_y, radius)
    local hit_radius = radius * 2  
    local distance = math.sqrt((mouse_x - circle_x)^2 + (mouse_y - circle_y)^2)
    return distance <= hit_radius
end


function HandleFretboardClick(ctx,startX,startY,width,height,isChord,rightClick)
    local mouseX,mouseY=ImGui.GetMousePos(ctx)
    local winX,winY=ImGui.GetWindowPos(ctx)
    local num_strings=6
    local num_frets=12
    local string_spacing, fret_spacing
    if isChord and chord_board_horizontal then
        string_spacing = height/(num_strings-1)
        fret_spacing = width/num_frets
    else
        string_spacing = isChord and width/(num_strings-1) or height/(num_strings-1)
        fret_spacing = isChord and height/num_frets or width/num_frets
    end
    mouseX=mouseX-(winX+startX)
    mouseY=mouseY-(winY+startY)

    local circle_size = is_xl_mode and 9 or 6
    local hit_radius = circle_size * 2

    if isChord then
        if chord_board_horizontal then
            for string_num=0,num_strings-1 do
                local actual_string = 5 - string_num
                local circle_y=string_num*string_spacing
                
                local circle_x=0
                local distance=math.sqrt((mouseX-circle_x)^2+(mouseY-circle_y)^2)
                if distance<=hit_radius then
                    local frets={"X","X","X","X","X","X"}
                    local i=1
                    for existing_fret in input_chord:gmatch("%S+") do
                        frets[i]=existing_fret
                        i=i+1
                    end
                    frets[actual_string+1]=rightClick and "X" or "0"
                    input_chord=table.concat(frets," ")
                    return true
                end
                for fret=1,num_frets do
                    circle_x=(fret*fret_spacing)-(fret_spacing/2)
                    distance=math.sqrt((mouseX-circle_x)^2+(mouseY-circle_y)^2)
                    if distance<=hit_radius then
                        HandleChordSelection(actual_string, fret, rightClick)
                        return true
                    end
                end
            end
        else
            for string_num=0,num_strings-1 do
                local circle_x=string_num*string_spacing
                
                local circle_y=0
                local distance=math.sqrt((mouseX-circle_x)^2+(mouseY-circle_y)^2)
                if distance<=hit_radius then
                    local frets={"X","X","X","X","X","X"}
                    local i=1
                    for existing_fret in input_chord:gmatch("%S+") do
                        frets[i]=existing_fret
                        i=i+1
                    end
                    frets[string_num+1]=rightClick and "X" or "0"
                    input_chord=table.concat(frets," ")
                    return true
                end
                
                for fret=1,num_frets do
                    circle_y=(fret*fret_spacing)-(fret_spacing/2)
                    distance=math.sqrt((mouseX-circle_x)^2+(mouseY-circle_y)^2)
                    if distance<=hit_radius then
                        HandleChordSelection(string_num, fret, rightClick)
                        return true
                    end
                end
            end
        end
    else
        for string_num=0,num_strings-1 do
            local circle_y=string_num*string_spacing
            local circle_x=0
            local distance=math.sqrt((mouseX-circle_x)^2+(mouseY-circle_y)^2)
            if distance<=hit_radius then
                if rightClick then
                    local notes={}
                    for note in input_sequence:gmatch("([^-]+)") do
                        if tonumber(note) ~= 0 then
                            table.insert(notes,note)
                        end
                    end
                    input_sequence=table.concat(notes,"-")
                else
                    if input_sequence=="" then
                        input_sequence="0"
                    else
                        input_sequence=input_sequence.."-0"
                    end
                end
                selected_string=string_num+1
                return true
            end
            for fret=1,num_frets do
                circle_x=(fret*fret_spacing)-(fret_spacing/2)
                distance=math.sqrt((mouseX-circle_x)^2+(mouseY-circle_y)^2)
                if distance<=hit_radius then
                    if rightClick then
                        local notes={}
                        for note in input_sequence:gmatch("([^-]+)") do
                            if tonumber(note) ~= fret then
                                table.insert(notes,note)
                            end
                        end
                        input_sequence=table.concat(notes,"-")
                    else
                        if input_sequence=="" then
                            input_sequence=tostring(fret)
                        else
                            input_sequence=input_sequence.."-"..tostring(fret)
                        end
                    end
                    selected_string=string_num+1
                    return true
                end
            end
        end
    end
    return false
end

function DrawFretMarkers(draw_list, startX, startY, spacing, orientation)
    local fret_markers = {3,5,7,9,12}
    local marker_radius = is_xl_mode and 5 or 4
    local marker_color = 0xFFFF0033  
    
    local marker_pos
    if orientation == "vertical" then
        marker_pos = startX + (spacing * 2.4)  
    else
        marker_pos = startY + (spacing * 2.4) 
    end
    
    for _, fret in ipairs(fret_markers) do
        local pos
        if orientation == "vertical" then
            pos = startY + (fret*spacing) - (spacing/2)
            if fret == 12 then
                ImGui.DrawList_AddCircleFilled(draw_list, marker_pos, pos-6, marker_radius, marker_color)
                ImGui.DrawList_AddCircleFilled(draw_list, marker_pos, pos+6, marker_radius, marker_color)
            else
                ImGui.DrawList_AddCircleFilled(draw_list, marker_pos, pos, marker_radius, marker_color)
            end
        else
            pos = startX + (fret*spacing) - (spacing/2)
            if fret == 12 then
                ImGui.DrawList_AddCircleFilled(draw_list, pos-6, marker_pos, marker_radius, marker_color)
                ImGui.DrawList_AddCircleFilled(draw_list, pos+6, marker_pos, marker_radius, marker_color)
            else
                ImGui.DrawList_AddCircleFilled(draw_list, pos, marker_pos, marker_radius, marker_color)
            end
        end
    end
end


function DrawFretboard(ctx,startX,startY,width,height)
    local draw_list = ImGui.GetWindowDrawList(ctx)
    local mouse_x, mouse_y = ImGui.GetMousePos(ctx)
    local win_x, win_y = ImGui.GetWindowPos(ctx)
    
    mouse_x = mouse_x - win_x
    mouse_y = mouse_y - win_y
    
    startX = win_x + startX
    startY = win_y + startY
    local num_strings = 6
    local num_frets = 12
    local string_spacing = height/(num_strings-1)
    local fret_spacing = width/num_frets
    
    DrawFretMarkers(draw_list, startX, startY, fret_spacing, "horizontal")
    
    for i=0,num_strings-1 do
        local y = startY+(i*string_spacing)
        ImGui.DrawList_AddLine(draw_list,startX,y,startX+width,y,0xFFFFFFFF)
        local note_name = GetNoteName(base_notes[i+1])
        ImGui.DrawList_AddText(draw_list,startX-25,y-6,0xFFFFFFFF,note_name)
    end
    
    -- Draw frets and numbers
    for i=0,num_frets do
        local x = startX+(i*fret_spacing)
        local fret_number_y_offset = is_xl_mode and 12 or 10
        
        if i == 0 then
            ImGui.DrawList_AddLine(draw_list,x,startY,x,startY+height,0xFFFFFFFF,5.0)
            ImGui.DrawList_AddText(draw_list,x-3,startY+height+fret_number_y_offset,0xFFFFFFFF,"0")
        else
            ImGui.DrawList_AddLine(draw_list,x,startY,x,startY+height,0xFFFFFFFF,1.0)
            local text_x = x - (fret_spacing/2) - 3
            ImGui.DrawList_AddText(draw_list,text_x,startY+height+fret_number_y_offset,0xFFFFFFFF,tostring(i))
        end
    end
    
    local circle_radius = is_xl_mode and 9 or 6

    for string_num=0,num_strings-1 do
        local circle_y = startY+(string_num*string_spacing)
        local circle_x = startX
        
        local adjusted_mouse_x = mouse_x + win_x
        local adjusted_mouse_y = mouse_y + win_y

        if IsMouseOverCircle(adjusted_mouse_x, adjusted_mouse_y, circle_x, circle_y, circle_radius) then
            ImGui.DrawList_AddCircleFilled(draw_list, circle_x, circle_y, circle_radius, 0x3FFFFFFF)
        end
        ImGui.DrawList_AddCircle(draw_list, circle_x, circle_y, circle_radius, 0x80808080)
        
        for fret=1,num_frets do
            circle_x = startX+(fret*fret_spacing)-(fret_spacing/2)
            if IsMouseOverCircle(adjusted_mouse_x, adjusted_mouse_y, circle_x, circle_y, circle_radius) then
                ImGui.DrawList_AddCircleFilled(draw_list, circle_x, circle_y, circle_radius, 0x3FFFFFFF)
            end
            ImGui.DrawList_AddCircle(draw_list, circle_x, circle_y, circle_radius, 0x80808080)
        end
    end
    

    if ImGui.IsMouseClicked(ctx,0) then
        HandleFretboardClick(ctx,startX-win_x,startY-win_y,width,height,false,false)
    elseif ImGui.IsMouseClicked(ctx,1) then
        HandleFretboardClick(ctx,startX-win_x,startY-win_y,width,height,false,true)
    end

    -- Draw selected notes
    local notes = input_sequence:gmatch("([^-]+)")
    local string_idx = selected_string-1
    for fret in notes do
        local fret_num = tonumber(fret)
        if fret_num then
            local note_x
            if fret_num == 0 then
                note_x = startX
            else
                note_x = startX+(fret_num*fret_spacing)-(fret_spacing/2)
            end
            local note_y = startY+(string_idx*string_spacing)
            ImGui.DrawList_AddCircleFilled(draw_list, note_x, note_y, circle_radius + 1, 0xFF0000FF)
        end
    end
end

function IsBarre(chord_shape)
    local frets = {}
    local fingers = chord_fingers[chord_shape]
    if not fingers then
        return false
    end
    
    local chord_frets = {}
    for fret in chord_shape:gmatch("%S+") do
        table.insert(chord_frets, fret)
    end
    
    for i, finger in ipairs(fingers) do
        if finger == 1 then
            local fret = chord_frets[i]
            if fret ~= "X" and fret ~= "0" then
                local fret_num = tonumber(fret)
                if fret_num then
                    table.insert(frets, fret_num)
                end
            end
        end
    end
    
    if #frets >= 2 then
        local first_fret = frets[1]
        for i=2, #frets do
            if frets[i] ~= first_fret then
                return false
            end
        end
        return true
    end
    return false
end

function DrawChordboard(ctx,startX,startY,width,height)
    local draw_list = ImGui.GetWindowDrawList(ctx)
    local mouse_x, mouse_y = ImGui.GetMousePos(ctx)
    local win_x, win_y = ImGui.GetWindowPos(ctx)
    mouse_x = mouse_x - win_x
    mouse_y = mouse_y - win_y
    if chord_board_horizontal then
        startX = win_x + startX + 20
    else
        startX = win_x + startX + 15 
    end
    startY = win_y+startY
    local num_strings = 6
    local num_frets = 12

    if chord_board_horizontal then
        local temp = width
        width = height * 2.5
        height = temp
        string_spacing = height/(num_strings-1)
        fret_spacing = width/num_frets
    else
        string_spacing = width/(num_strings-1)
        height = height * 2.5
        fret_spacing = height/num_frets
    end
    
    DrawFretMarkers(draw_list, startX, startY, fret_spacing, chord_board_horizontal and "horizontal" or "vertical")

    -- Draw strings
    for i=0,num_strings-1 do
        if chord_board_horizontal then
            local y = startY + (i * string_spacing)
            ImGui.DrawList_AddLine(draw_list, startX, y, startX+width, y, 0xFFFFFFFF)
            local note_name = GetNoteName(base_notes[i+1])
            ImGui.DrawList_AddText(draw_list, startX-25, y-6, 0xFFFFFFFF, note_name)
        else
            local x = startX + (i * string_spacing)
            local text_y_offset = is_xl_mode and -30 or -20
            ImGui.DrawList_AddLine(draw_list, x, startY, x, startY+height, 0xFFFFFFFF)
            local note_name = GetNoteName(base_notes[num_strings-i])
            ImGui.DrawList_AddText(draw_list, x-5, startY + text_y_offset, 0xFFFFFFFF, note_name)
        end
    end
    -- Draw frets and numbers
    for i=0,num_frets do
        if chord_board_horizontal then
            local x = startX+(i*fret_spacing)
            local fret_number_y_offset = is_xl_mode and 12 or 10
            
            if i == 0 then
                ImGui.DrawList_AddLine(draw_list,x,startY,x,startY+height,0xFFFFFFFF,4.0)
                ImGui.DrawList_AddText(draw_list,x-3,startY+height+fret_number_y_offset,0xFFFFFFFF,"0")
            else
                ImGui.DrawList_AddLine(draw_list,x,startY,x,startY+height,0xFFFFFFFF,1.0)
                local text_x = x - (fret_spacing/2) - 3
                ImGui.DrawList_AddText(draw_list,text_x,startY+height+fret_number_y_offset,0xFFFFFFFF,tostring(i))
            end
        else
            local y = startY+(i*fret_spacing)
            if i == 0 then
                ImGui.DrawList_AddLine(draw_list,startX,y,startX+width,y,0xFFFFFFFF,4.0)
                ImGui.DrawList_AddText(draw_list,startX-20,y-8,0xFFFFFFFF,"0")
            else
                ImGui.DrawList_AddLine(draw_list,startX,y,startX+width,y,0xFFFFFFFF,1.0)
                ImGui.DrawList_AddText(draw_list,startX-20,y-8,0xFFFFFFFF,tostring(i))
            end
        end
    end

    -- Draw empty circles
    local circle_radius = is_xl_mode and 9 or 6
    for string_num=0,num_strings-1 do
        for fret=0,num_frets do
            if chord_board_horizontal then
                local y = startY+(string_num*string_spacing)
                local x = startX+(fret*fret_spacing)
                if fret > 0 then
                    x = x-(fret_spacing/2)
                end
                
                local adjusted_mouse_x = mouse_x + win_x
                local adjusted_mouse_y = mouse_y + win_y
                if IsMouseOverCircle(adjusted_mouse_x, adjusted_mouse_y, x, y, circle_radius) then
                    ImGui.DrawList_AddCircleFilled(draw_list, x, y, circle_radius, 0x3FFFFFFF)
                end
                
                ImGui.DrawList_AddCircle(draw_list, x, y, circle_radius, 0x80808080)
            else
                local x = startX+(string_num*string_spacing)
                local y = startY+(fret*fret_spacing)
                if fret > 0 then
                    y = y-(fret_spacing/2)
                end

                local adjusted_mouse_x = mouse_x + win_x
                local adjusted_mouse_y = mouse_y + win_y
                if IsMouseOverCircle(adjusted_mouse_x, adjusted_mouse_y, x, y, circle_radius) then
                    ImGui.DrawList_AddCircleFilled(draw_list, x, y, circle_radius, 0x3FFFFFFF)
                end
                
                ImGui.DrawList_AddCircle(draw_list, x, y, circle_radius, 0x80808080)
            end
        end
    end

    if ImGui.IsMouseClicked(ctx,0) then
        HandleFretboardClick(ctx,startX-win_x,startY-win_y,width,height,true,false)
    elseif ImGui.IsMouseClicked(ctx,1) then
        HandleFretboardClick(ctx,startX-win_x,startY-win_y,width,height,true,true)
    end
    
    local chord_shape = input_chord
    local chord_name = DetermineChordName(chord_shape)
    local fingers = chord_fingers[chord_shape]

    local chord_shape = input_chord
    local chord_name = DetermineChordName(chord_shape)
    local fingers = chord_fingers[chord_shape]
    local finger_idx = 1
    for string_num = 1, num_strings do
        if string_num == 1 and IsBarre(chord_shape) then
            local barre_fret = nil
            local start_string = nil
            local end_string = nil
            local fret_positions = {}
            for fret in chord_shape:gmatch("%S+") do
                table.insert(fret_positions, fret)
            end
            
            for i, finger in ipairs(fingers) do
                if finger == 1 then
                    local fret = tonumber(fret_positions[i])
                    if fret then
                        barre_fret = fret
                        if not start_string then
                            start_string = i
                        end
                        end_string = i
                    end
                end
            end
        
            if barre_fret and start_string and end_string then
                local barre_color = finger_colors[1]
                local circle_size = is_xl_mode and 9 or 6  -- Gebruik dezelfde maat als de noot cirkels
                
                if chord_board_horizontal then
                    local start_y = startY + ((num_strings-start_string) * string_spacing)
                    local end_y = startY + ((num_strings-end_string) * string_spacing)
                    local x = startX + (barre_fret * fret_spacing) - (fret_spacing/2)
                    
                    ImGui.DrawList_AddRectFilled(
                        draw_list,
                        x - circle_size * 0.8, start_y,
                        x + circle_size * 0.8, end_y,
                        barre_color
                    )
                    
                    ImGui.DrawList_AddRect(
                        draw_list,
                        x - circle_size * 0.8, start_y,
                        x + circle_size * 0.8, end_y,
                        0xFFFFFFFF,
                        0.0,
                        0,
                        1.0
                    )
                else
                    local start_x = startX + (start_string-1)*string_spacing
                    local end_x = startX + (end_string-1)*string_spacing
                    local y = startY + (barre_fret*fret_spacing) - (fret_spacing/2)
                    
                    ImGui.DrawList_AddRectFilled(
                        draw_list,
                        start_x, y - circle_size * 0.8,
                        end_x, y + circle_size * 0.8,
                        barre_color
                    )
                    
                    ImGui.DrawList_AddRect(
                        draw_list,
                        start_x, y - circle_size * 0.8,
                        end_x, y + circle_size * 0.8,
                        0xFFFFFFFF,
                        0.0,
                        0,
                        1.0
                    )
                end
            end    
        end
        
        local fret = string.match(input_chord, string.rep("%S+%s", string_num-1)..("(%S+)"))
        if fret then
            local x, y
            if chord_board_horizontal then
                y = startY + ((6-string_num) * string_spacing)
                x = startX
            else
                x = startX + (string_num-1) * string_spacing
                y = startY
            end
    
            if fret == "X" then
                local size = is_xl_mode and 6 or 4
                ImGui.DrawList_AddLine(draw_list, x-size, y-size, x+size, y+size, 0xFFFFFFFF)
                ImGui.DrawList_AddLine(draw_list, x-size, y+size, x+size, y-size, 0xFFFFFFFF)
                finger_idx = finger_idx + 1
            elseif fret == "0" then
                local circle_size = is_xl_mode and 9 or 6
                ImGui.DrawList_AddCircleFilled(draw_list, x, y, circle_size, 0xFFFFFFFF)
                ImGui.DrawList_AddCircle(draw_list, x, y, circle_size, 0x000000FF)
                finger_idx = finger_idx + 1
            else
                local fret_num = tonumber(fret)
                if fret_num then
                    if chord_board_horizontal then
                        x = startX + (fret_num * fret_spacing) - (fret_spacing/2)
                    else
                        y = startY + (fret_num * fret_spacing) - (fret_spacing/2)
                    end
                    
                    local circle_size = is_xl_mode and 9 or 6
                    if fingers then
                        local finger = fingers[finger_idx]
                        local color = finger_colors[finger] or 0xFFFFFFFF
                        ImGui.DrawList_AddCircleFilled(draw_list, x, y, circle_size, color)
                        if finger then
                            local text_offset = is_xl_mode and 4 or 3
                            ImGui.DrawList_AddText(draw_list, x-text_offset, y-text_offset*2, 0x000000FF, tostring(finger))
                        end
                    else
                        ImGui.DrawList_AddCircleFilled(draw_list, x, y, circle_size, 0xFF0000FF)
                    end
                    ImGui.DrawList_AddCircle(draw_list, x, y, circle_size, 0xFFFFFFFF)
                    finger_idx = finger_idx + 1
                end
            end    
        
        end
    end

    local finger_idx = 1
    for string_num = 1, num_strings do
        local fret = string.match(input_chord, string.rep("%S+%s", string_num-1)..("(%S+)"))
        if fret then
            local x, y
            if chord_board_horizontal then
                y = startY + ((6-string_num) * string_spacing)
                x = startX
            else
                x = startX + (string_num-1) * string_spacing
                y = startY
            end
    
            if fret == "X" then
                local size = is_xl_mode and 6 or 4
                ImGui.DrawList_AddLine(draw_list, x-size, y-size, x+size, y+size, 0xFFFFFFFF)
                ImGui.DrawList_AddLine(draw_list, x-size, y+size, x+size, y-size, 0xFFFFFFFF)
                finger_idx = finger_idx + 1
            elseif fret == "0" then
                local circle_size = is_xl_mode and 9 or 6
                ImGui.DrawList_AddCircleFilled(draw_list, x, y, circle_size, 0xFFFFFFFF)
                ImGui.DrawList_AddCircle(draw_list, x, y, circle_size, 0x000000FF)
                finger_idx = finger_idx + 1
            else
                local fret_num = tonumber(fret)
                if fret_num then
                    if chord_board_horizontal then
                        x = startX + (fret_num * fret_spacing) - (fret_spacing/2)
                    else
                        y = startY + (fret_num * fret_spacing) - (fret_spacing/2)
                    end
                    
                    local circle_size = is_xl_mode and 9 or 6
                    if fingers then
                        local finger = fingers[finger_idx]
                        local color = finger_colors[finger] or 0xFFFFFFFF
                        ImGui.DrawList_AddCircleFilled(draw_list, x, y, circle_size, color)
                        if finger then
                            local text_offset = is_xl_mode and 4 or 3
                            ImGui.DrawList_AddText(draw_list, x-text_offset, y-text_offset*2, 0x000000FF, tostring(finger))
                        end
                    else
                        ImGui.DrawList_AddCircleFilled(draw_list, x, y, circle_size, 0xFF0000FF)
                    end
                    ImGui.DrawList_AddCircle(draw_list, x, y, circle_size, 0xFFFFFFFF)
                    finger_idx = finger_idx + 1
                end
            end    
        end
    end

    if chord_board_horizontal then
        local bottom_y = startY + height + 60 
        DrawFingerLegend(ctx, startX, bottom_y)
        
        if chord_name and chord_name ~= "(?)" or status_message ~= "" then
            local info_x = startX + 185 
            local info_y = bottom_y    
            local box_padding = 10
            local box_width = 120
            local box_height = 50
            local is_barre = IsBarre(chord_shape)
            local chord_type = is_barre and "Barre Chord: " or "Chord: "
            
            ImGui.DrawList_AddRectFilled(draw_list,
                info_x - box_padding,
                info_y - box_padding,
                info_x + box_width,
                info_y + box_height,
                0x1A1A1AFF)
            
            ImGui.DrawList_AddRect(draw_list,
                info_x - box_padding,
                info_y - box_padding,
                info_x + box_width,
                info_y + box_height,
                0x333333FF)
            
            if status_message ~= "" then
                ImGui.DrawList_AddText(draw_list, info_x, info_y, status_color, status_message)
                status_message = ""
            else
                ImGui.DrawList_AddText(draw_list, info_x, info_y, 0xFFFFFFFF, chord_type)
                ImGui.DrawList_AddText(draw_list, info_x, info_y + 20, 0xFFFFFFFF, chord_name)
            end
        end
    else
        DrawFingerLegend(ctx, startX + width + 50, startY + 30)
        
        if chord_name and chord_name ~= "(?)" or status_message ~= "" then
            local legend_height = 25 * 4
            local chord_info_y = startY + 20 + legend_height + 20
            local info_x = startX + width + 50
            local box_padding = 10
            local box_width = 120
            local box_height = 50
            local is_barre = IsBarre(chord_shape)
            local chord_type = is_barre and "Barre Chord: " or "Chord: "
            
            ImGui.DrawList_AddRectFilled(draw_list,
                info_x - box_padding,
                chord_info_y - box_padding,
                info_x + box_width,
                chord_info_y + box_height,
                0x1A1A1AFF)
            
            ImGui.DrawList_AddRect(draw_list,
                info_x - box_padding,
                chord_info_y - box_padding,
                info_x + box_width,
                chord_info_y + box_height,
                0x333333FF)
            
            if status_message ~= "" then
                ImGui.DrawList_AddText(draw_list, info_x, chord_info_y, status_color, status_message)
                status_message = ""
            else
                ImGui.DrawList_AddText(draw_list, info_x, chord_info_y, 0xFFFFFFFF, chord_type)
                ImGui.DrawList_AddText(draw_list, info_x, chord_info_y + 20, 0xFFFFFFFF, chord_name)
            end
        end
    end
end

------------------------------------------------------------------------
function MainLoop()
    local min_width = is_xl_mode and 500 or 400  
    if show_sequence then
        min_width = math.max(min_width, is_xl_mode and 500 or 400)
    end
    if show_chord then
        min_width = math.max(min_width, is_xl_mode and 500 or 400)
    end

    local window_flags = 
    ImGui.WindowFlags_NoTitleBar |
    ImGui.WindowFlags_NoResize |
    ImGui.WindowFlags_NoScrollbar |
    ImGui.WindowFlags_AlwaysAutoResize
    
    if is_pinned then
        window_flags = window_flags | ImGui.WindowFlags_TopMost
    end
    if is_nomove then
        window_flags = window_flags | ImGui.WindowFlags_NoMove
    end

    ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowRounding, 12.0)
    ImGui.SetNextWindowSizeConstraints(ctx, min_width, 0, min_width, 2000)
    local visible, open = ImGui.Begin(ctx, 'Guitar MIDI Input', true, window_flags)

    if GTR2MIDI_esc_key() then
        open = false
    end

    if visible then
        
        ImGui.PushFont(ctx, font)
        ImGui.PushStyleColor(ctx, ImGui.Col_WindowBg, 0x000000FF)
        ImGui.PushStyleColor(ctx, ImGui.Col_Button, 0x1A1A1AFF)
        ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, 0x333333FF)
        ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, 0x404040FF)
        ImGui.PushStyleColor(ctx, ImGui.Col_FrameBg, 0x1A1A1AFF)
        ImGui.PushStyleColor(ctx, ImGui.Col_FrameBgHovered, 0x333333FF)
        ImGui.PushStyleColor(ctx, ImGui.Col_FrameBgActive, 0x404040FF)
        
        ImGui.PushStyleVar(ctx, ImGui.StyleVar_FrameRounding, 6.0)
        
        -- Header controls
        local window_width = ImGui.GetWindowWidth(ctx)
 
        ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0xFF0000FF)
        ImGui.SetCursorPosY(ctx, 8)
        ImGui.Text(ctx, "TK")
        ImGui.PopStyleColor(ctx)
        ImGui.SameLine(ctx)
        ImGui.Text(ctx, "GTR2MIDI")
        ImGui.SameLine(ctx)
        ImGui.Dummy(ctx, 5, 0)
        
        ImGui.SameLine(ctx)
        ImGui.SetCursorPosY(ctx, 5)
        local seq_changed, new_show_sequence = ImGui.Checkbox(ctx, "Sequence", show_sequence)
        if seq_changed then
            show_sequence = new_show_sequence
            r.SetExtState("TK_GTR2MIDI", "show_sequence", tostring(show_sequence), true)
            if new_show_sequence then
                show_chord = false
                r.SetExtState("TK_GTR2MIDI", "show_chord", "false", true)
            end
        end
        
        ImGui.SameLine(ctx)
        ImGui.SetCursorPosY(ctx, 5)
        local chord_changed, new_show_chord = ImGui.Checkbox(ctx, "Chord", show_chord)
        if chord_changed then
            show_chord = new_show_chord
            r.SetExtState("TK_GTR2MIDI", "show_chord", tostring(show_chord), true)
            if new_show_chord then
                show_sequence = false
                r.SetExtState("TK_GTR2MIDI", "show_sequence", "false", true)
            end
        end
        
        ImGui.SameLine(ctx)
        ImGui.SetCursorPosY(ctx, 5)
        if show_chord then
            local changed, new_horizontal = ImGui.Checkbox(ctx, "Horizontal", chord_board_horizontal)
            if changed then
                chord_board_horizontal = new_horizontal
                r.SetExtState("TK_GTR2MIDI", "chord_board_horizontal", tostring(new_horizontal), true)
            end
        else
            ImGui.PushStyleVar(ctx, ImGui.StyleVar_Alpha, 0.5)
            ImGui.Checkbox(ctx, "Horizontal", chord_board_horizontal)
            ImGui.PopStyleVar(ctx)
        end

        ImGui.SameLine(ctx)
        ImGui.SetCursorPosY(ctx, 5)
        local xl_changed, new_xl_mode = ImGui.Checkbox(ctx, "XL", is_xl_mode)
        if xl_changed then
            is_xl_mode = new_xl_mode
            r.SetExtState("TK_GTR2MIDI", "is_xl_mode", tostring(is_xl_mode), true)
            font = is_xl_mode and font_large or font_small
        end
      
        -- NoMove button (geel)
        ImGui.SameLine(ctx)
        ImGui.SetCursorPosY(ctx, 7)
        ImGui.SetCursorPosX(ctx, window_width - 57)
        ImGui.PushStyleColor(ctx, ImGui.Col_Button, is_nomove and 0xFFFF00FF or 0x808080FF)
        ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, is_nomove and 0xFFFF33FF or 0x999999FF)
        ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, is_nomove and 0xFFCC00FF or 0x666666FF)
        if ImGui.Button(ctx, "##nomove", 14, 14) then
            is_nomove = not is_nomove
        end
        ImGui.PopStyleColor(ctx, 3)

        -- Pin button
        ImGui.SameLine(ctx)
        ImGui.SetCursorPosY(ctx, 7)
        ImGui.SetCursorPosX(ctx, window_width - 40)
        ImGui.PushStyleColor(ctx, ImGui.Col_Button, is_pinned and 0x00FF00FF or 0x808080FF)
        ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, is_pinned and 0x00FF33FF or 0x999999FF)
        ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, is_pinned and 0x00CC00FF or 0x666666FF)
        if ImGui.Button(ctx, "##pin", 14, 14) then
            is_pinned = not is_pinned
        end
        ImGui.PopStyleColor(ctx, 3)

        -- Close button
        ImGui.SameLine(ctx)
        ImGui.SetCursorPosY(ctx, 7)
        ImGui.SetCursorPosX(ctx, window_width - 23)
        ImGui.PushStyleColor(ctx, ImGui.Col_Button, 0xFF0000FF)
        ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, 0xFF3333FF)
        ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, 0xCC0000FF)
        if ImGui.Button(ctx, "##close", 14, 14) then
            open = false
        end
        ImGui.PopStyleColor(ctx, 3)
        ImGui.Separator(ctx)
        if show_sequence or show_chord then
            ImGui.Text(ctx, "Duration:")
            ImGui.SameLine(ctx)
            local active_color = 0xFF0000FF
            
            -- Duration buttons
            if selected_duration == "1" then
                ImGui.PushStyleColor(ctx, ImGui.Col_Button, active_color)
                if ImGui.Button(ctx, "1/1") then selected_duration = "1" end
                ImGui.PopStyleColor(ctx)
            else
                if ImGui.Button(ctx, "1/1") then selected_duration = "1" end
            end
            
            ImGui.SameLine(ctx)
            if selected_duration == "2" then
                ImGui.PushStyleColor(ctx, ImGui.Col_Button, active_color)
                if ImGui.Button(ctx, "1/2") then selected_duration = "2" end
                ImGui.PopStyleColor(ctx)
            else
                if ImGui.Button(ctx, "1/2") then selected_duration = "2" end
            end
            
            ImGui.SameLine(ctx)
            if selected_duration == "4" then
                ImGui.PushStyleColor(ctx, ImGui.Col_Button, active_color)
                if ImGui.Button(ctx, "1/4") then selected_duration = "4" end
                ImGui.PopStyleColor(ctx)
            else
                if ImGui.Button(ctx, "1/4") then selected_duration = "4" end
            end
            
            ImGui.SameLine(ctx)
            if selected_duration == "8" then
                ImGui.PushStyleColor(ctx, ImGui.Col_Button, active_color)
                if ImGui.Button(ctx, "1/8") then selected_duration = "8" end
                ImGui.PopStyleColor(ctx)
            else
                if ImGui.Button(ctx, "1/8") then selected_duration = "8" end
            end
            
            ImGui.SameLine(ctx)
            if selected_duration == "16" then
                ImGui.PushStyleColor(ctx, ImGui.Col_Button, active_color)
                if ImGui.Button(ctx, "1/16") then selected_duration = "16" end
                ImGui.PopStyleColor(ctx)
            else
                if ImGui.Button(ctx, "1/16") then selected_duration = "16" end
            end

            -- Transpose controls
            ImGui.SameLine(ctx)
            ImGui.Text(ctx, "Trans:")
            ImGui.SameLine(ctx)
            ImGui.PushItemWidth(ctx, 60)
            if ImGui.BeginCombo(ctx, "##transpose", selected_transpose_mode) then
                for mode, _ in pairs(transpose_modes) do
                    if ImGui.Selectable(ctx, mode, selected_transpose_mode == mode) then
                        selected_transpose_mode = mode
                    end
                end
                ImGui.EndCombo(ctx)
            end
            
            ImGui.SameLine(ctx)
            if ImGui.Button(ctx, "-", 18, 18) then
                quick_chord_input = ""
                local steps = transpose_modes[selected_transpose_mode]
                input_sequence = TransposeSequence(steps, -1)
                input_chord = TransposeChord(steps, -1)
            end
            
            ImGui.SameLine(ctx)
            if ImGui.Button(ctx, "+", 18, 18) then
                quick_chord_input = ""
                local steps = transpose_modes[selected_transpose_mode]
                input_sequence = TransposeSequence(steps, 1)
                input_chord = TransposeChord(steps, 1)
            end
            ImGui.Text(ctx, "Tuning: ")
            ImGui.SameLine(ctx)
            ImGui.PushItemWidth(ctx, 150)
            if ImGui.BeginCombo(ctx, "##tuning", selected_tuning) then
                for tuning_name, _ in pairs(tunings) do
                    if ImGui.Selectable(ctx, tuning_name, selected_tuning == tuning_name) then
                        selected_tuning = tuning_name
                        base_notes = tunings[tuning_name]
                    end
                end
                ImGui.EndCombo(ctx)
            end
            
            ImGui.SameLine(ctx)
            if ImGui.Button(ctx, "Custom Tunings") then
                show_custom_tuning_window = true
            end
            
            ImGui.Text(ctx, "Voicing:")
            ImGui.SameLine(ctx)
            ImGui.PushItemWidth(ctx, 150)
            if ImGui.BeginCombo(ctx, "##voicings", selected_voicing_file) then
                local voicing_files = GetAvailableVoicingFiles()
                for _, filename in ipairs(voicing_files) do
                    if ImGui.Selectable(ctx, filename, selected_voicing_file == filename) then
                        selected_voicing_file = filename
                        voicings = {}
                        chord_fingers = {}
                        LoadVoicings() 
                        r.SetExtState("TK_GTR2MIDI", "selected_voicing_file", selected_voicing_file, true)
                    end
                end
                ImGui.EndCombo(ctx)
            end
        
            ImGui.SameLine(ctx)
            _, insert_in_existing = ImGui.Checkbox(ctx, "Insert in selected MIDI item", insert_in_existing)
            ImGui.Spacing(ctx)
            ImGui.Separator(ctx)
            ImGui.Spacing(ctx)
        end

        if show_sequence then
            ImGui.Text(ctx, "Sequence:")
            ImGui.SameLine(ctx)
            ImGui.PushItemWidth(ctx, 163) 
            local _, new_sequence = ImGui.InputTextWithHint(ctx, "##sequence", "1-2-6-9-0-3", input_sequence)
            input_sequence = new_sequence
            ImGui.SameLine(ctx)
            if ImGui.Button(ctx, "X##clearseq") then
                input_sequence = ""
            end
            
            ImGui.SameLine(ctx)
            ImGui.PushStyleColor(ctx, ImGui.Col_Button, 0x0099DDFF)
            ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, 0x00BBFFFF)
            ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, 0x0077AAFF)
            if ImGui.Button(ctx, "Insert Sequence") then
                local cursor_pos = r.GetCursorPosition()
                local item, take, note_length = CreateMIDIItem("sequence") 
                
                if take then
                    if insert_in_existing then
                        local ppq_pos = r.MIDI_GetPPQPosFromProjTime(take, cursor_pos)
                        InsertSequence(take, input_sequence, note_length, ppq_pos)
                        local note_count = 0
                        for _ in input_sequence:gmatch("([^-]+)") do 
                            note_count = note_count + 1 
                        end
                        local new_pos = r.MIDI_GetProjTimeFromPPQPos(take, ppq_pos + (note_length * note_count))
                        r.SetEditCurPos(new_pos, true, true)
                    else
                        InsertSequence(take, input_sequence, note_length, 0)
                        local note_count = 0
                        for _ in input_sequence:gmatch("([^-]+)") do 
                            note_count = note_count + 1 
                        end
                        r.SetEditCurPos(cursor_pos + (note_length * note_count)/960/2, true, true)
                    end
                end
            end 
            ImGui.PopStyleColor(ctx, 3)
            local board_width = is_xl_mode and 450 or 300
            local board_height = is_xl_mode and 180 or 120
            DrawFretboard(ctx, 30, ImGui.GetCursorPosY(ctx)+10, board_width, board_height)
            ImGui.Dummy(ctx, 0, is_xl_mode and 210 or 150)
            --ImGui.Separator(ctx)
        end
        if show_chord then    
            ImGui.Spacing(ctx)
            ImGui.Text(ctx, "Chord:")
            ImGui.SameLine(ctx)
            ImGui.PushItemWidth(ctx, 87)  
            local _, new_input = ImGui.InputTextWithHint(ctx, "##chord", "X 3 2 0 1 0", input_chord)
            input_chord = FilterChordInput(new_input)
            ImGui.SameLine(ctx)
            if ImGui.Button(ctx, "X##clearchord") then
                input_chord = ""
            end
            
            ImGui.SameLine(ctx)
            ImGui.Text(ctx, "Find:")
            ImGui.SameLine(ctx)
            ImGui.PushItemWidth(ctx, 50) 
            _, quick_chord_input = ImGui.InputTextWithHint(ctx, "##quickchord", "AMaj7", quick_chord_input or "")
            if quick_chord_input and quick_chord_input ~= "" then
                local found = false
                local normalized_input = normalizeChordName(quick_chord_input)
                for voicing, chord in pairs(voicings) do
                    if normalizeChordName(chord) == normalized_input then
                        input_chord = voicing
                        found = true
                        break
                    end
                end
                if not found then
                    status_message = "Chord not found"
                    status_color = 0xFF0000FF  
                end
            end
            
            ImGui.SameLine(ctx)
            if ImGui.Button(ctx, "X##clearquick") then
                quick_chord_input = ""
            end
            
            ImGui.SameLine(ctx)
            ImGui.PushStyleColor(ctx, ImGui.Col_Button, 0x0099DDFF)        
            ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, 0x00BBFFFF)
            ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, 0x0077AAFF)  
            
            if ImGui.Button(ctx, "Insert Chord") then
                local frets = {}
                for fret in input_chord:gmatch("%S+") do
                    table.insert(frets, fret)
                end
                if #frets == 6 then
                    local cursor_pos = r.GetCursorPosition()
                    local item, take, note_length = CreateMIDIItem("chord") 
                    if take then
                        if insert_in_existing then
                            local ppq_pos = r.MIDI_GetPPQPosFromProjTime(take, cursor_pos)
                            InsertChord(take, frets, note_length, ppq_pos)
                            local new_pos = r.MIDI_GetProjTimeFromPPQPos(take, ppq_pos + note_length)
                            r.SetEditCurPos(new_pos, true, true)
                        else
                            InsertChord(take, frets, note_length, 0)
                            r.SetEditCurPos(cursor_pos + note_length/960/2, true, true)
                        end
                    end
                else
                    ImGui.TextColored(ctx, 0xFF0000FF, "Input must contain exactly 6 positions")
                end
            end
            ImGui.PopStyleColor(ctx, 3)
            local board_size = is_xl_mode and 180 or 120
            local y_offset = (is_xl_mode and not chord_board_horizontal) and 30 or 20
            DrawChordboard(ctx, 10, ImGui.GetCursorPosY(ctx) + y_offset, board_size, board_size)
            local dummy_height
            if chord_board_horizontal then
                dummy_height = is_xl_mode and 385 or 325
            else
                dummy_height = is_xl_mode and 485 or 325  
            end
            ImGui.Dummy(ctx, 0, dummy_height)
        end

        ImGui.PopStyleVar(ctx, 2)
        ImGui.PopStyleColor(ctx, 7)
        ImGui.PopFont(ctx)

        if show_custom_tuning_window then
            ShowCustomTuningWindow()
        end
        
        ImGui.End(ctx)
    end
    if open then r.defer(MainLoop) end
end

r.defer(MainLoop)
