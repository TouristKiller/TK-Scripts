-- @description TK GTR2MIDI
-- @author TouristKiller
-- @version 0.0.2
-- @changelog
--[[ 

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
local show_settings_window      = false
local settings_next_pos         = nil
local per_string_channels       = (r.GetExtState("TK_GTR2MIDI","per_string_channels") ~= "false")
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
local string_thicknesses        = {3.0, 2.5, 2.0, 1.5, 1.0, 0.5}
-- Voicing configuration
local voicings                  = {}
local selected_voicing_file     = r.GetExtState("TK_GTR2MIDI", "selected_voicing_file")
if selected_voicing_file == "" then
    selected_voicing_file       = "ChordVoicings.txt"
end

-- UI state
local show_custom_tuning_window = false
local custom_tuning_initialized = false
local chord_fingers             = {}
local chord_board_horizontal    = false
local insert_in_existing        = false
local show_sequence             = false
local show_chord                = true
local status_message            = ""
local status_color              = 0xFFFFFFFF
local is_left_handed            = false
local is_mirror_mode            = false
local last_window_width_normal  = nil
local last_window_width_xl      = nil
local pending_instant_resize    = false

-- Theme settings (persisted)
local function read_num(key, default)
    local s = r.GetExtState("TK_GTR2MIDI", key)
    local v = tonumber(s)
    return v ~= nil and v or default
end

local ui_window_alpha           = read_num("ui_window_alpha", 1.0)
local ui_window_bg_gray         = read_num("ui_window_bg_gray", 0.00)   -- 0=zwart, 1=wit
local ui_button_gray            = read_num("ui_button_gray",    26/255) -- ~0.10
local ui_dropdown_gray          = read_num("ui_dropdown_gray",  0.20)
local ui_input_gray             = read_num("ui_input_gray",     26/255)
local ui_text_gray              = read_num("ui_text_gray",      0.90)
local ui_window_rounding        = read_num("ui_window_rounding",12.0)
local ui_button_rounding        = read_num("ui_button_rounding", 6.0)

local function clamp01(x)
    if x < 0 then return 0 elseif x > 1 then return 1 else return x end
end

local function shade(gray, delta)
    return clamp01(gray + delta)
end

local function gray_color(gray)
    local g = math.floor(clamp01(gray) * 255 + 0.5)
    return (g << 24) | (g << 16) | (g << 8) | 0xFF
end

local function GetThemeColors()
    return {
        window_bg       = gray_color(ui_window_bg_gray),
        button          = gray_color(ui_button_gray),
        button_hovered  = gray_color(shade(ui_button_gray, 0.12)),
        button_active   = gray_color(shade(ui_button_gray, 0.20)),
        frame_bg        = gray_color(ui_input_gray),
        frame_bg_hovered= gray_color(shade(ui_input_gray, 0.12)),
        frame_bg_active = gray_color(shade(ui_input_gray, 0.20)),
        popup_bg        = gray_color(ui_dropdown_gray),
        text            = gray_color(ui_text_gray),
    }
end

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
is_left_handed                  = r.GetExtState("TK_GTR2MIDI", "is_left_handed") == "true"
is_mirror_mode                  = r.GetExtState("TK_GTR2MIDI", "is_mirror_mode") == "true"
local num_strings               = tonumber(r.GetExtState("TK_GTR2MIDI", "num_strings")) or 6

local function setNumStrings(n)
    n = tonumber(n) or 6
    if n < 1 then n = 1 elseif n > 16 then n = 16 end
    num_strings = n
    r.SetExtState("TK_GTR2MIDI","num_strings", tostring(n), true)

    local cur = base_notes or {}
    local new = {}
    if #cur >= n then
        for i=1,n do new[i] = cur[i] end
    else
        for i=1,#cur do new[i] = cur[i] end
        local fill = cur[#cur] or 40
        for i=#cur+1,n do new[i] = fill end
    end
    base_notes = new

    local cn = {}
    if custom_notes and #custom_notes > 0 then
        for i=1,math.min(#custom_notes, n) do cn[i] = custom_notes[i] end
        local fill = cn[#cn] or (base_notes[#base_notes] or 40)
        for i=#cn+1,n do cn[i] = fill end
    else
        for i=1,n do cn[i] = base_notes[i] or 40 end
    end
    custom_notes = cn

    string_thicknesses = {}
    for i=1,n do
        local t = (i-1)/math.max(1,(n-1))
        string_thicknesses[i] = 3.0 - 2.2*t
    end

    local frets = {}
    for f in (input_chord or ""):gmatch("%S+") do table.insert(frets, f) end
    if #frets < n then
        for i=#frets+1,n do frets[i] = "X" end
    elseif #frets > n then
        while #frets > n do table.remove(frets) end
    end
    input_chord = (#frets>0) and table.concat(frets, " ") or input_chord

    if selected_string > n then selected_string = n end
    if selected_string < 1 then selected_string = 1 end
end

setNumStrings(num_strings)
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
    local base_note = base_notes[(num_strings + 1) - string_num]
    return base_note + tonumber(fret)
end

function FindFretForNote(string_num, target_note)
    local base_note = base_notes[(num_strings + 1) - string_num]
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
    for tok in (input_sequence or ""):gmatch("([^-]+)") do
        local s, f = tok:match("^(%d+)%s*:%s*(%-?%d+)$")
        if s then
            s = tonumber(s); f = tonumber(f)
            local base_note = base_notes[s]
            local current_note = base_note + f
            local target_note = current_note + (interval * direction)
            local new_fret = target_note - base_note
            if new_fret >= 0 and new_fret <= 24 then
                table.insert(new_seq, tostring(s) .. ":" .. tostring(new_fret))
            end
        else
            local f2 = tonumber(tok)
            if f2 ~= nil then
                local base_note = base_notes[selected_string]
                local current_note = base_note + f2
                local target_note = current_note + (interval * direction)
                local new_fret = target_note - base_note
                if new_fret >= 0 and new_fret <= 24 then
                    table.insert(new_seq, tostring(new_fret))
                end
            end
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
    local C = GetThemeColors()
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_Alpha, clamp01(ui_window_alpha))
    ImGui.PushStyleColor(ctx, ImGui.Col_WindowBg, C.window_bg)
    ImGui.PushStyleColor(ctx, ImGui.Col_Button, C.button)
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, C.button_hovered)
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, C.button_active)
    ImGui.PushStyleColor(ctx, ImGui.Col_FrameBg, C.frame_bg)
    ImGui.PushStyleColor(ctx, ImGui.Col_FrameBgHovered, C.frame_bg_hovered)
    ImGui.PushStyleColor(ctx, ImGui.Col_FrameBgActive, C.frame_bg_active)
    ImGui.PushStyleColor(ctx, ImGui.Col_Text, C.text)
    ImGui.PushStyleColor(ctx, ImGui.Col_PopupBg, C.popup_bg)
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowRounding, ui_window_rounding)
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_FrameRounding, ui_button_rounding)

    local flags = ImGui.WindowFlags_AlwaysAutoResize | ImGui.WindowFlags_NoScrollbar
    if not custom_tuning_initialized then
        -- Prefill from current selection; resize to current string count
        local src = tunings[selected_tuning] or base_notes or {}
        custom_notes = {}
        for i=1, math.min(#src, num_strings) do custom_notes[i] = src[i] end
        local fill = custom_notes[#custom_notes] or src[#src] or 40
        for i=#custom_notes+1, num_strings do custom_notes[i] = fill end
        custom_tuning_name = selected_tuning
        custom_tuning_initialized = true
    end

    local visible, open = ImGui.Begin(ctx, "Custom Tuning Editor", true, flags)
    if visible then
        ImGui.Text(ctx, "Name:")
        ImGui.SameLine(ctx)
        ImGui.PushItemWidth(ctx, 220)
        local _, name_val = ImGui.InputTextWithHint(ctx, "##ct_name", "My Tuning", custom_tuning_name or "")
        custom_tuning_name = name_val
        ImGui.PopItemWidth(ctx)

        ImGui.Separator(ctx)
        ImGui.Text(ctx, "Strings (low ➜ high):")

        -- Per-string editors
        local col_min_x, _ = ImGui.GetWindowContentRegionMin(ctx)
        local col_max_x, _ = ImGui.GetWindowContentRegionMax(ctx)
        local cell_w = (col_max_x - col_min_x - 6) / 2
        for i=1, num_strings do
            local idx = i
            local label = string.format("String %d", idx)
            ImGui.Text(ctx, label)
            ImGui.SameLine(ctx)
            ImGui.PushItemWidth(ctx, 70)
            local val = tonumber(custom_notes[idx]) or 40
            local changed, new_val = ImGui.InputInt(ctx, "##ct_note_"..idx, val, 1, 12)
            if changed then
                if new_val < 0 then new_val = 0 end
                if new_val > 127 then new_val = 127 end
                custom_notes[idx] = new_val
            end
            ImGui.PopItemWidth(ctx)
            ImGui.SameLine(ctx)
            ImGui.Text(ctx, GetNoteName(custom_notes[idx]))
        end

        ImGui.Separator(ctx)
        if ImGui.Button(ctx, "Save", 80, 0) then
            local name = (custom_tuning_name or ""):gsub("^%s+", ""):gsub("%s+$", "")
            if name == "" then name = os.date("Custom %Y-%m-%d %H:%M:%S") end
            local arr = {}
            for i=1, num_strings do arr[i] = tonumber(custom_notes[i]) or 40 end
            tunings[name] = {table.unpack(arr)}
            custom_tunings[name] = {table.unpack(arr)}
            SaveCustomTunings(custom_tunings)
            selected_tuning = name
            base_notes = {table.unpack(arr)}
            local voicing_filename = "ChordVoicings_" .. name .. ".txt"
            local path = script_path .. separator .. voicing_filename
            local f = io.open(path, "r")
            if not f then
                local nf = io.open(path, "w")
                if nf then
                    nf:write("# Chord voicings for " .. name .. " tuning\n")
                    nf:write("# Format: FRET_POSITIONS | CHORD_NAME | FINGER_POSITIONS\n")
                    nf:write("# Example: 0 2 2 1 0 0 | Em | 0 2 3 1 0 0\n")
                    nf:close()
                end
            else
                f:close()
            end
            show_custom_tuning_window = false
            custom_tuning_initialized = false
        end
        ImGui.SameLine(ctx)
        if ImGui.Button(ctx, "Delete", 80, 0) then
            if selected_tuning ~= "Standard (EADGBE)" and 
               selected_tuning ~= "Drop D (DADGBE)" and
               selected_tuning ~= "Open G (DGDGBD)" and
               selected_tuning ~= "Open D (DADF#AD)" and
               selected_tuning ~= "DADGAD" then
                DeleteCustomTuning(selected_tuning)
            end
            show_custom_tuning_window = false
            custom_tuning_initialized = false
        end
        ImGui.SameLine(ctx)
        if ImGui.Button(ctx, "Cancel", 80, 0) then
            show_custom_tuning_window = false
            custom_tuning_initialized = false
        end
    end
    ImGui.End(ctx)
    ImGui.PopStyleVar(ctx, 2)
    ImGui.PopStyleColor(ctx, 7)
    ImGui.PopFont(ctx)
end

function CreateMIDIItem(insert_type)
    local track = r.GetSelectedTrack(0,0)
    if not track then return end
    
    local existing_item, existing_take = GetSelectedMIDIItem()
    local cursor_pos = r.GetCursorPosition()
    local ppq = 960
    local dur_val = tonumber(selected_duration) or 4
    -- Length of a single note in quarter-notes (QN). E.g. 4 -> 1.0 QN, 8 -> 0.5 QN
    local qn_per_note = 4 / dur_val
    local note_length = ppq * qn_per_note  -- PPQ length per note
    
    if existing_item and insert_in_existing then
        -- Move cursor by the musical length using tempo map
        local cursor_qn = r.TimeMap2_timeToQN(0, cursor_pos)
        local qn_total = qn_per_note
        if insert_type == "sequence" then
            local note_count = 0
            for _ in input_sequence:gmatch("([^-]+)") do note_count = note_count + 1 end
            qn_total = qn_per_note * note_count
        end
        local item_end = r.TimeMap2_QNToTime(0, cursor_qn + qn_total)
        r.SetEditCurPos(item_end, true, true)
        return existing_item, existing_take, note_length
    end

    local note_count = 0
    for _ in input_sequence:gmatch("([^-]+)") do 
        note_count = note_count + 1 
    end
    
    local cursor_qn = r.TimeMap2_timeToQN(0, cursor_pos)
    local qn_total
    if insert_type == "sequence" then
        qn_total = qn_per_note * note_count
    else
        qn_total = qn_per_note
    end
    local item_end = r.TimeMap2_QNToTime(0, cursor_qn + qn_total)

    local item = r.CreateNewMIDIItemInProj(track, cursor_pos, item_end, false)
    local take = r.GetActiveTake(item)
    r.SetEditCurPos(item_end, true, true)

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
    local spacing = is_xl_mode and 34 or 25
    local circle_size = is_xl_mode and 10 or 8 -- circles already sized ok
    local labels = {
        "- Index finger",
        "- Middle finger", 
        "- Ring finger",
        "- Pinky"
    }

    local line_h = ImGui.GetTextLineHeight(ctx)
    local header_gap = is_xl_mode and (line_h + 16) or (line_h + 12)
    local base_offset = is_xl_mode and 10 or 8
    local baseY = startY + base_offset
        do
            local C = GetThemeColors()
            ImGui.DrawList_AddText(draw_list, startX, baseY - header_gap, C.text, "Finger positions:")
        end
    
    for i, label in ipairs(labels) do
        local y = baseY + (i-1) * spacing
        local circle_x = startX + circle_size
        local circle_y = y
        ImGui.DrawList_AddCircleFilled(draw_list, circle_x, circle_y, circle_size, finger_colors[i])
        ImGui.DrawList_AddCircle(draw_list, circle_x, circle_y, circle_size, 0xFFFFFFFF)
        local num_w = ImGui.CalcTextSize(ctx, tostring(i))
        local num_x = circle_x - (num_w/2)
        local num_y = circle_y - (line_h/2)
    ImGui.DrawList_AddText(draw_list, num_x, num_y, 0x000000FF, tostring(i))

        local label_x = startX + (circle_size * 2) + (is_xl_mode and 12 or 10)
        local label_y = y - (line_h/2)
        do
            local C = GetThemeColors()
            ImGui.DrawList_AddText(draw_list, label_x, label_y, C.text, label)
        end
    end
end

function InsertChord(take, frets, note_length, start_ppq)
    local ppq_pos = start_ppq or 0
    for string_num, fret in ipairs(frets) do
        if fret ~= "X" then
            local note = base_notes[(num_strings + 1) - string_num] + tonumber(fret)
            local midi_channel = per_string_channels and (string_num-1) or 0
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
    local position = start_ppq or 0
    r.GetSetMediaItemTakeInfo_String(take, "P_NAME", notes, true)
    for tok in (notes or ""):gmatch("([^-]+)") do
        local s, f = tok:match("^(%d+)%s*:%s*(%-?%d+)$")
        if s then
            s = tonumber(s); f = tonumber(f)
            if s and f and s >= 1 and s <= num_strings and f >= 0 and f <= 24 then
                local base = base_notes[s]
                local midi_note = base + f
                local midi_channel = per_string_channels and (s - 1) or 0
                r.MIDI_InsertNote(take, false, false, position, position + note_length, midi_channel, midi_note, 100, false)
                position = position + note_length
            end
        else
            local f2 = tonumber(tok)
            if f2 and f2 >= 0 and f2 <= 24 then
                local base = base_notes[selected_string]
                local midi_note = base + f2
                local midi_channel = per_string_channels and (selected_string - 1) or 0
                r.MIDI_InsertNote(take, false, false, position, position + note_length, midi_channel, midi_note, 100, false)
                position = position + note_length
            end
        end
    end
    r.MIDI_Sort(take)
end

function HandleChordSelection(string_num, fret, rightClick)
    local frets={}
    for i=1,num_strings do frets[i] = "X" end
    local i=1
    for existing_fret in input_chord:gmatch("%S+") do
        frets[i]=existing_fret
        i=i+1
    end
    
    if rightClick then
        frets[string_num+1] = "X"
    else
        if frets[string_num+1] == tostring(fret) then
            frets[string_num+1] = "X"
        else
            frets[string_num+1] = tostring(fret)
        end
    end
    
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

function GetFretForString(chord, string_num, is_left_handed)
    local frets = {}
    for fret in chord:gmatch("%S+") do
        table.insert(frets, fret)
    end
    
    if is_left_handed then
    return frets[(num_strings + 1) - string_num]  
    else
        return frets[string_num]    
    end
end


function HandleFretboardClick(ctx,startX,startY,width,height,isChord,rightClick)
    local mouseX,mouseY=ImGui.GetMousePos(ctx)
    local winX,winY=ImGui.GetWindowPos(ctx)
    local num_frets=12
    local string_spacing, fret_spacing
    
    local spacing_den = math.max(1, num_strings-1)
    if isChord and chord_board_horizontal then
        string_spacing = height/spacing_den
        fret_spacing = width/num_frets
    else
        string_spacing = isChord and width/spacing_den or height/spacing_den
        fret_spacing = isChord and height/num_frets or width/num_frets
    end
    
    mouseX=mouseX-(winX+startX)
    mouseY=mouseY-(winY+startY)

    local circle_size = is_xl_mode and 9 or 6
    local hit_radius = circle_size * 2

    if isChord then
        if chord_board_horizontal then
        for string_num=0,num_strings-1 do
                local actual_string
                if is_left_handed then
                    actual_string = string_num
                else
            actual_string = (num_strings - 1) - string_num
                end
                
                local circle_y=string_num*string_spacing
                local circle_x
                
                if is_mirror_mode then
                    circle_x = width
                else
                    circle_x = 0
                end
                
                local distance=math.sqrt((mouseX-circle_x)^2+(mouseY-circle_y)^2)
                if distance<=hit_radius then
                    local frets={}
                    for i=1,num_strings do frets[i] = "X" end
                    local i=1
                    for existing_fret in input_chord:gmatch("%S+") do
                        frets[i]=existing_fret
                        i=i+1
                    end
                    
                    if rightClick then
                        frets[actual_string+1] = "X"
                    else
                        if frets[actual_string+1] == "0" then
                            frets[actual_string+1] = "X"
                        else
                            frets[actual_string+1] = "0"
                        end
                    end
                    input_chord=table.concat(frets," ")
                    return true
                end
        
                for fret=1,num_frets do
                    local fret_position
                    if is_mirror_mode then
                        fret_position = width - (fret*fret_spacing) + (fret_spacing/2)
                    else
                        fret_position = (fret*fret_spacing) - (fret_spacing/2)
                    end
                    
                    distance=math.sqrt((mouseX-fret_position)^2+(mouseY-circle_y)^2)
                    if distance<=hit_radius then
                        if is_mirror_mode then
                            local mirror_fret = math.floor((width - mouseX) / fret_spacing) + 1
                            if mirror_fret >= 1 and mirror_fret <= num_frets then
                                HandleChordSelection(actual_string, mirror_fret, rightClick)
                            end
                        else
                            HandleChordSelection(actual_string, fret, rightClick)
                        end
                        return true
                    end
                end
            end
        else
            for string_num=0,num_strings-1 do
                local actual_string = is_left_handed and ((num_strings - 1) - string_num) or string_num
                local circle_x=string_num*string_spacing
                
                local circle_y=0
                local distance=math.sqrt((mouseX-circle_x)^2+(mouseY-circle_y)^2)
                if distance<=hit_radius then
                    local frets={}
                    for i=1,num_strings do frets[i] = "X" end
                    local i=1
                    for existing_fret in input_chord:gmatch("%S+") do
                        frets[i]=existing_fret
                        i=i+1
                    end
                    
                    if rightClick then
                        frets[actual_string+1] = "X"
                    else
                        if frets[actual_string+1] == "0" then
                            frets[actual_string+1] = "X"
                        else
                            frets[actual_string+1] = "0"
                        end
                    end
                    input_chord=table.concat(frets," ")
                    return true
                end
        
                for fret=1,num_frets do
                    circle_y=(fret*fret_spacing)-(fret_spacing/2)
                    distance=math.sqrt((mouseX-circle_x)^2+(mouseY-circle_y)^2)
                    if distance<=hit_radius then
                        HandleChordSelection(actual_string, fret, rightClick)
                        return true
                    end
                end
            end
        end
    else
        for string_num=0,num_strings-1 do
            local actual_string = is_left_handed and string_num or (num_strings - 1 - string_num)
            local circle_y=string_num*string_spacing
            local circle_x = is_mirror_mode and width or 0
            
            local distance=math.sqrt((mouseX-circle_x)^2+(mouseY-circle_y)^2)
            if distance<=hit_radius then
                local s = actual_string + 1
                if rightClick then
                    local out, removed = {}, false
                    for tok in (input_sequence or ""):gmatch("([^-]+)") do
                        local ts, tf = tok:match("^(%d+)%s*:%s*(%-?%d+)$")
                        if ts then
                            if not removed and tonumber(ts)==s and tonumber(tf)==0 then
                                removed = true
                            else
                                table.insert(out, tok)
                            end
                        else
                            if not removed and tonumber(tok)==0 and s==selected_string then
                                removed = true
                            else
                                table.insert(out, tok)
                            end
                        end
                    end
                    input_sequence = table.concat(out, "-")
                else
                    local token = tostring(s) .. ":0"
                    if input_sequence=="" then input_sequence=token else input_sequence=input_sequence.."-"..token end
                end
                selected_string=s
                return true
            end
            
            for fret=1,num_frets do
                local fret_position
                if is_mirror_mode then
                    fret_position = width - (fret*fret_spacing) + (fret_spacing/2)
                else
                    fret_position = (fret*fret_spacing) - (fret_spacing/2)
                end
                
                distance=math.sqrt((mouseX-fret_position)^2+(mouseY-circle_y)^2)
                if distance<=hit_radius then
                    local s = actual_string + 1
                    local f = is_mirror_mode and (math.floor((width - mouseX) / fret_spacing) + 1) or fret
                    if rightClick then
                        local out, removed = {}, false
                        for tok in (input_sequence or ""):gmatch("([^-]+)") do
                            local ts, tf = tok:match("^(%d+)%s*:%s*(%-?%d+)$")
                            if ts then
                                if not removed and tonumber(ts)==s and tonumber(tf)==f then
                                    removed = true
                                else
                                    table.insert(out, tok)
                                end
                            else
                                if not removed and tonumber(tok)==f and s==selected_string then
                                    removed = true
                                else
                                    table.insert(out, tok)
                                end
                            end
                        end
                        input_sequence = table.concat(out, "-")
                    else
                        local token = tostring(s) .. ":" .. tostring(f)
                        if input_sequence=="" then input_sequence=token else input_sequence=input_sequence.."-"..token end
                    end
                    selected_string=s
                    return true
                end
            end
        end
    end
    return false
end



function DrawFretMarkers(draw_list, startX, startY, spacing, orientation, fret_len, strings_dim, is_mirror)
    local fret_markers = {3,5,7,9,12}
    local marker_radius = is_xl_mode and 5 or 4
    local marker_color = 0xFFFFFFFF
    local double_off = (is_xl_mode and 7 or 6)

    if orientation == "vertical" then
        local center_x = startX + (strings_dim / 2)
        for _, fret in ipairs(fret_markers) do
            local y = startY + (fret * spacing) - (spacing / 2)
            if fret == 12 then
                ImGui.DrawList_AddCircleFilled(draw_list, center_x - double_off, y, marker_radius, marker_color)
                ImGui.DrawList_AddCircleFilled(draw_list, center_x + double_off, y, marker_radius, marker_color)
            else
                ImGui.DrawList_AddCircleFilled(draw_list, center_x, y, marker_radius, marker_color)
            end
        end
    else
        local center_y = startY + (strings_dim / 2)
        for _, fret in ipairs(fret_markers) do
            local x
            if is_mirror then
                x = startX + fret_len - (fret * spacing) + (spacing / 2)
            else
                x = startX + (fret * spacing) - (spacing / 2)
            end
            if fret == 12 then
                ImGui.DrawList_AddCircleFilled(draw_list, x, center_y - double_off, marker_radius, marker_color)
                ImGui.DrawList_AddCircleFilled(draw_list, x, center_y + double_off, marker_radius, marker_color)
            else
                ImGui.DrawList_AddCircleFilled(draw_list, x, center_y, marker_radius, marker_color)
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
    local num_frets = 12
    local string_spacing = height/math.max(1, num_strings-1)
    local fret_spacing = width/num_frets

    do
        local pad_x = is_xl_mode and 8 or 6
        local pad_y = is_xl_mode and 10 or 8
        local bg_col = 0x4A2F1EFF   -- warm brown
        local brd_col = 0x2E1E14FF  -- darker border
        ImGui.DrawList_AddRectFilled(
            draw_list,
            startX - pad_x,
            startY - pad_y,
            startX + width + pad_x,
            startY + height + pad_y,
            bg_col
        )
        ImGui.DrawList_AddRect(
            draw_list,
            startX - pad_x,
            startY - pad_y,
            startX + width + pad_x,
            startY + height + pad_y,
            brd_col,
            6.0
        )
    end
    
    DrawFretMarkers(draw_list, startX, startY, fret_spacing, "horizontal", width, height, is_mirror_mode)
 
    for i=0,num_strings-1 do
        local string_thickness = string_thicknesses[i+1]
        local y
        if is_left_handed then
            y = startY + (i * string_spacing)
        else
            y = startY + ((num_strings - 1 - i) * string_spacing)
        end
        ImGui.DrawList_AddLine(draw_list,startX,y,startX+width,y,0xF0F0F0FF,string_thickness)
        local note_name = GetNoteName(base_notes[i+1])
        do
            local C = GetThemeColors()
            ImGui.DrawList_AddText(draw_list,startX-25,y-6,C.text,note_name)
        end
    end

    
    for i=0,num_frets do
        local x
        if is_mirror_mode then
            x = startX + width - (i*fret_spacing)
        else
            x = startX + (i*fret_spacing)
        end
        
        if i == 0 then
            ImGui.DrawList_AddRectFilled(draw_list, x - 1.5, startY, x + 1.5, startY + height, 0xE6E6E6FF)
            ImGui.DrawList_AddLine(draw_list,x,startY,x,startY+height,0xFFFFFFFF,4.0)
            do local C = GetThemeColors(); ImGui.DrawList_AddText(draw_list,x-3,startY+height+10,C.text,"0") end
        else
            local prev_x = is_mirror_mode and (x + fret_spacing) or (x - fret_spacing)
            ImGui.DrawList_AddRectFilled(draw_list, prev_x, startY, x, startY+height, 0x00000020)
            ImGui.DrawList_AddLine(draw_list,x,startY,x,startY+height,0xFFFFFFFF,1.0)
            local text_x
            if is_mirror_mode then
                text_x = x + (fret_spacing/2) - 3
            else
                text_x = x - (fret_spacing/2) - 3
            end
            do local C = GetThemeColors(); ImGui.DrawList_AddText(draw_list,text_x,startY+height+10,C.text,tostring(i)) end
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

    for tok in (input_sequence or ""):gmatch("([^-]+)") do
        local s, f = tok:match("^(%d+)%s*:%s*(%-?%d+)$")
        local use_s, fret_num
        if s then
            use_s = tonumber(s)
            fret_num = tonumber(f)
        else
            use_s = selected_string
            fret_num = tonumber(tok)
        end
        if use_s and fret_num then
            local note_x
            if is_mirror_mode then
                if fret_num == 0 then
                    note_x = startX + width
                else
                    note_x = startX + width - (fret_num*fret_spacing) + (fret_spacing/2)
                end
            else
                if fret_num == 0 then
                    note_x = startX
                else
                    note_x = startX + (fret_num*fret_spacing) - (fret_spacing/2)
                end
            end
            local idx = use_s - 1
            local note_y
            if is_left_handed then
                note_y = startY + (idx*string_spacing)
            else
                note_y = startY + ((num_strings - 1 - idx)*string_spacing)
            end
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
    local num_frets = 12

    if chord_board_horizontal then
        local temp = width
        width = height * 2.5
        height = temp
        string_spacing = height/math.max(1, num_strings-1)
        fret_spacing = width/num_frets

        do
            local pad_x = is_xl_mode and 8 or 6
            local pad_y = is_xl_mode and 10 or 8
            local bg_col = 0x4A2F1EFF   -- warm brown
            local brd_col = 0x2E1E14FF  -- darker border
            ImGui.DrawList_AddRectFilled(
                draw_list,
                startX - pad_x,
                startY - pad_y,
                startX + width + pad_x,
                startY + height + pad_y,
                bg_col
            )
            ImGui.DrawList_AddRect(
                draw_list,
                startX - pad_x,
                startY - pad_y,
                startX + width + pad_x,
                startY + height + pad_y,
                brd_col,
                6.0
            )
        end
    else
        string_spacing = width/math.max(1, num_strings-1)
        height = height * 2.5
        fret_spacing = height/num_frets

        do
            local pad_x = is_xl_mode and 8 or 6
            local pad_y = is_xl_mode and 10 or 8
            local bg_col = 0x4A2F1EFF   -- warm brown
            local brd_col = 0x2E1E14FF  -- darker border
            ImGui.DrawList_AddRectFilled(
                draw_list,
                startX - pad_x,
                startY - pad_y,
                startX + width + pad_x,
                startY + height + pad_y,
                bg_col
            )
            ImGui.DrawList_AddRect(
                draw_list,
                startX - pad_x,
                startY - pad_y,
                startX + width + pad_x,
                startY + height + pad_y,
                brd_col,
                6.0
            )
        end
    end
    
    if chord_board_horizontal then
        DrawFretMarkers(draw_list, startX, startY, fret_spacing, "horizontal", width, height, is_mirror_mode)
    else
        DrawFretMarkers(draw_list, startX, startY, fret_spacing, "vertical", height, width, false)
    end

    for i=0,num_strings-1 do
        local string_thickness = string_thicknesses[i+1]
        
        if chord_board_horizontal then
            local y
            if is_left_handed then
                y = startY + (i * string_spacing)
            else
                y = startY + ((num_strings - 1 - i) * string_spacing)
            end
            ImGui.DrawList_AddLine(draw_list, startX, y, startX+width, y, 0xF0F0F0FF, string_thickness)
            local note_name = GetNoteName(base_notes[num_strings-i])
            do local C = GetThemeColors(); ImGui.DrawList_AddText(draw_list, startX-25, y-6, C.text, note_name) end
        else  
            local x
            if is_left_handed then
                x = startX + ((num_strings - 1 - i) * string_spacing)
            else
                x = startX + (i * string_spacing)
            end
            
            local text_y_offset = is_xl_mode and -30 or -20
            ImGui.DrawList_AddLine(draw_list, x, startY, x, startY+height, 0xF0F0F0FF, string_thickness)
            local note_name = GetNoteName(base_notes[num_strings-i])
            do local C = GetThemeColors(); ImGui.DrawList_AddText(draw_list, x-5, startY + text_y_offset, C.text, note_name) end
        end
    end

    for i=0,num_frets do
        if chord_board_horizontal then
            local x
            if is_mirror_mode then
                x = startX + width - (i*fret_spacing)
            else
                x = startX+(i*fret_spacing)
            end
            local fret_number_y_offset = is_xl_mode and 12 or 10
            
            if i == 0 then
                local nut_thick = math.max(3.5, (is_xl_mode and 3.5 or 3.0))
                ImGui.DrawList_AddRectFilled(draw_list, x - 1.5, startY, x + 1.5, startY + height, 0xE6E6E6FF)
                ImGui.DrawList_AddLine(draw_list,x,startY,x,startY+height,0xFFFFFFFF,4.0)
                do local C = GetThemeColors(); ImGui.DrawList_AddText(draw_list,x-3,startY+height+fret_number_y_offset,C.text,"0") end
            else
                local prev_x
                if is_mirror_mode then
                    prev_x = x + fret_spacing
                else
                    prev_x = x - fret_spacing
                end
                local shade_col = 0x00000020
                if prev_x and ((is_mirror_mode and prev_x >= x) or (not is_mirror_mode and prev_x <= x)) then
                    ImGui.DrawList_AddRectFilled(draw_list, prev_x, startY, x, startY+height, shade_col)
                end
                ImGui.DrawList_AddLine(draw_list,x,startY,x,startY+height,0xFFFFFFFF,1.0)
                local text_x
                if is_mirror_mode then
                    text_x = x + (fret_spacing/2) - 3
                else
                    text_x = x - (fret_spacing/2) - 3
                end
                do local C = GetThemeColors(); ImGui.DrawList_AddText(draw_list,text_x,startY+height+fret_number_y_offset,C.text,tostring(i)) end
            end
        else
            local y = startY+(i*fret_spacing)
            if i == 0 then
                ImGui.DrawList_AddRectFilled(draw_list, startX, y - 1.5, startX + width, y + 1.5, 0xE6E6E6FF)
                ImGui.DrawList_AddLine(draw_list,startX,y,startX+width,y,0xFFFFFFFF,4.0)
                do local C = GetThemeColors(); ImGui.DrawList_AddText(draw_list,startX-20,y-8,C.text,"0") end
            else
                local prev_y = y - fret_spacing
                ImGui.DrawList_AddRectFilled(draw_list, startX, prev_y, startX + width, y, 0x00000020)
                ImGui.DrawList_AddLine(draw_list,startX,y,startX+width,y,0xFFFFFFFF,1.0)
                do local C = GetThemeColors(); ImGui.DrawList_AddText(draw_list,startX-20,y-8,C.text,tostring(i)) end
            end
        end
    end

    local circle_radius = is_xl_mode and 9 or 6
    for string_num=0,num_strings-1 do
        for fret=0,num_frets do
            if chord_board_horizontal then
                local y
                if is_left_handed then
                    y = startY + (string_num * string_spacing)
                else
                    y = startY + ((num_strings - 1 - string_num) * string_spacing)
                end
                
                local x
                if is_mirror_mode then
                    x = startX + width - (fret*fret_spacing)
                    if fret > 0 then
                        x = x + (fret_spacing/2)
                    end
                else
                    x = startX + (fret*fret_spacing)
                    if fret > 0 then
                        x = x - (fret_spacing/2)
                    end
                end
                
                local adjusted_mouse_x = mouse_x + win_x
                local adjusted_mouse_y = mouse_y + win_y
                if IsMouseOverCircle(adjusted_mouse_x, adjusted_mouse_y, x, y, circle_radius) then
                    ImGui.DrawList_AddCircleFilled(draw_list, x, y, circle_radius, 0x3FFFFFFF)
                end
                
                ImGui.DrawList_AddCircle(draw_list, x, y, circle_radius, 0x80808080)
            else
                local x
                if is_left_handed then
                    x = startX + ((num_strings - 1 - string_num) * string_spacing)
                else
                    x = startX + (string_num * string_spacing)
                end
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
    local finger_idx = 1

    for string_num = 1, num_strings do
        local display_string_num = is_left_handed and (num_strings - string_num + 1) or string_num

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
                local circle_size = is_xl_mode and 9 or 6
                
                if chord_board_horizontal then
                    local start_y, end_y
                    if is_left_handed then
                        start_y = startY + ((num_strings - end_string) * string_spacing)
                        end_y = startY + ((num_strings - start_string) * string_spacing)
                    else
                        start_y = startY + ((num_strings-start_string) * string_spacing)
                        end_y = startY + ((num_strings-end_string) * string_spacing)
                    end
                    
                    local x
                    if is_mirror_mode then
                        x = startX + width - (barre_fret * fret_spacing) + (fret_spacing/2)
                    else
                        x = startX + (barre_fret * fret_spacing) - (fret_spacing/2)
                    end
                    
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
                    local start_x, end_x
                    if is_left_handed then
                        start_x = startX + (num_strings - end_string) * string_spacing
                        end_x = startX + (num_strings - start_string) * string_spacing
                    else
                        start_x = startX + (start_string-1) * string_spacing
                        end_x = startX + (end_string-1) * string_spacing
                    end
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

        local fret = GetFretForString(input_chord, display_string_num, is_left_handed)
        if fret then
            local x, y
            if chord_board_horizontal then
                if is_left_handed then
                    y = startY + ((string_num-1) * string_spacing)
                else
                    y = startY + (((num_strings) - string_num) * string_spacing)
                end
                x = startX
                if is_mirror_mode then
                    x = startX + width  
                end
            else
                if is_left_handed then
                    x = startX + (num_strings - string_num) * string_spacing
                else
                    x = startX + (string_num-1) * string_spacing
                end
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
                        if is_mirror_mode then
                            x = startX + width - (x - startX)  -- Spiegelt de x-positie rond het midden
                        end
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
        local content_min_x, _ = ImGui.GetWindowContentRegionMin(ctx)
        local left_abs_x = win_x + content_min_x
    DrawFingerLegend(ctx, left_abs_x + 5, bottom_y)
        
        if chord_name and chord_name ~= "(?)" or status_message ~= "" then
            local info_x = startX + 185
            local info_y = bottom_y    
            local box_padding = 10
            local box_width = 120
            local box_height = 60
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
                do local C = GetThemeColors(); ImGui.DrawList_AddText(draw_list, info_x, info_y, C.text, chord_type) end
                do local C = GetThemeColors(); ImGui.DrawList_AddText(draw_list, info_x, info_y, C.text, chord_type) end
                do local C = GetThemeColors(); ImGui.DrawList_AddText(draw_list, info_x, info_y + 20, C.text, chord_name) end
            end
        end
    else
        local bottom_y = startY + height + 60
        DrawFingerLegend(ctx, startX + 5, bottom_y)

        if chord_name and chord_name ~= "(?)" or status_message ~= "" then
            local info_x = startX + (is_xl_mode and 235 or 215)
            local info_y = bottom_y
            local box_padding = 10
            local box_width = is_xl_mode and 140 or 130
            local box_height = is_xl_mode and 60 or 55
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
                do local C = GetThemeColors(); ImGui.DrawList_AddText(draw_list, info_x, info_y, C.text, chord_type) end
                do local C = GetThemeColors(); ImGui.DrawList_AddText(draw_list, info_x, info_y + 20, C.text, chord_name) end
            end
        end
    end
end



------------------------------------------------------------------------
function MainLoop()
    local min_width = is_xl_mode and 425 or 320  
    if show_sequence then
        min_width = math.max(min_width, is_xl_mode and 455 or 340)
    end
    if show_chord then
        min_width = math.max(min_width, is_xl_mode and 455 or 340)
    end
    local header_floor = is_xl_mode and 595 or 460
    min_width = math.max(min_width, header_floor)

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

    ImGui.PushStyleVar(ctx, ImGui.StyleVar_WindowRounding, ui_window_rounding)
    if pending_instant_resize then
        ImGui.SetNextWindowSizeConstraints(ctx, min_width, 0, min_width, 2000)
    else
        ImGui.SetNextWindowSizeConstraints(ctx, min_width, 0, min_width + 1000, 2000)
    end
    local _Cwin = GetThemeColors()
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_Alpha, clamp01(ui_window_alpha))
    ImGui.PushStyleColor(ctx, ImGui.Col_WindowBg, _Cwin.window_bg)
    local visible, open = ImGui.Begin(ctx, 'Guitar MIDI Input', true, window_flags)
    pending_instant_resize = false

    if GTR2MIDI_esc_key() then
        open = false
    end

    if visible then
        
    ImGui.PushFont(ctx, font)
    local C = GetThemeColors()
    ImGui.PushStyleColor(ctx, ImGui.Col_Button, C.button)
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonHovered, C.button_hovered)
    ImGui.PushStyleColor(ctx, ImGui.Col_ButtonActive, C.button_active)
    ImGui.PushStyleColor(ctx, ImGui.Col_FrameBg, C.frame_bg)
    ImGui.PushStyleColor(ctx, ImGui.Col_FrameBgHovered, C.frame_bg_hovered)
    ImGui.PushStyleColor(ctx, ImGui.Col_FrameBgActive, C.frame_bg_active)
    ImGui.PushStyleColor(ctx, ImGui.Col_Text, C.text)
    ImGui.PushStyleColor(ctx, ImGui.Col_PopupBg, C.popup_bg)
        
    ImGui.PushStyleVar(ctx, ImGui.StyleVar_FrameRounding, ui_button_rounding)
        
        local window_width = ImGui.GetWindowWidth(ctx)
        if is_xl_mode then
            if (not last_window_width_xl) or window_width > last_window_width_xl then
                last_window_width_xl = window_width
            end
        else
            if (not last_window_width_normal) or window_width > last_window_width_normal then
                last_window_width_normal = window_width
            end
        end
 
    ImGui.PushStyleColor(ctx, ImGui.Col_Text, 0xFF0000FF)
        ImGui.SetCursorPosY(ctx, 8)
        ImGui.Text(ctx, "TK")
    ImGui.PopStyleColor(ctx)
        ImGui.SameLine(ctx)
        ImGui.Text(ctx, "GTR2MIDI (EXPERIMENTAL)")
        ImGui.SameLine(ctx)
        ImGui.Dummy(ctx, 5, 0)
        
       
      
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
    local parts = {}
        if chord_board_horizontal then table.insert(parts, "Horizontal") end
        if is_left_handed then table.insert(parts, "Left") end
        if is_mirror_mode then table.insert(parts, "Mirror") end
        if is_xl_mode then table.insert(parts, "XL") end
        local preview = (#parts > 0) and table.concat(parts, " | ") or "Default"
    local content_min_x, _ = ImGui.GetWindowContentRegionMin(ctx)
    local content_max_x, _ = ImGui.GetWindowContentRegionMax(ctx)
    local view_combo_width = is_xl_mode and 180 or 140
    local gear_width = is_xl_mode and 26 or 22
    local gap = is_xl_mode and 6 or 4
    ImGui.SetCursorPosX(ctx, content_max_x - view_combo_width - gear_width - gap)
    ImGui.PushItemWidth(ctx, view_combo_width)
    if ImGui.BeginCombo(ctx, "##view", preview) then
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

            local left_changed, new_left_handed = ImGui.Checkbox(ctx, "Left Handed", is_left_handed)
            if left_changed then
                is_left_handed = new_left_handed
                r.SetExtState("TK_GTR2MIDI", "is_left_handed", tostring(new_left_handed), true)
            end

            local mirror_changed, new_mirror_mode = ImGui.Checkbox(ctx, "Mirror", is_mirror_mode)
            if mirror_changed then
                is_mirror_mode = new_mirror_mode
                r.SetExtState("TK_GTR2MIDI", "is_mirror_mode", tostring(new_mirror_mode), true)
            end

            local xl_changed, new_xl_mode = ImGui.Checkbox(ctx, "XL", is_xl_mode)
            if xl_changed then
                is_xl_mode = new_xl_mode
                r.SetExtState("TK_GTR2MIDI", "is_xl_mode", tostring(is_xl_mode), true)
                font = is_xl_mode and font_large or font_small
                pending_instant_resize = true
            end
            ImGui.EndCombo(ctx)
        
        ImGui.PopItemWidth(ctx)
        end

    ImGui.SameLine(ctx)
    ImGui.SetCursorPosX(ctx, content_max_x - gear_width)
    if ImGui.Button(ctx, is_xl_mode and "⚙" or "⚙", gear_width, 0) then
        if show_settings_window then
            show_settings_window = false
        else
            show_settings_window = true
            local mx, my = ImGui.GetMousePos(ctx)
            settings_next_pos = { x = mx, y = my + (is_xl_mode and 8 or 6) }
        end
    end

    local needed_px = is_xl_mode and 140 or 120
    local avail_px = ImGui.GetWindowWidth(ctx) - ImGui.GetCursorPosX(ctx) - needed_px

        ImGui.Separator(ctx)
        local Scaling_XL = 1.3
        local base_button_width = 30
        local base_combo_width = 58
        local base_tuning_width = 190
        local base_transpose_button = 18

        -- Scale values based on XL mode
        local button_width = is_xl_mode and (base_button_width * Scaling_XL) or base_button_width
        local combo_width = is_xl_mode and (base_combo_width * Scaling_XL) or base_combo_width
        local tuning_width = is_xl_mode and (base_tuning_width * Scaling_XL) or base_tuning_width
        local transpose_button_size = is_xl_mode and (base_transpose_button * Scaling_XL) or base_transpose_button

        if show_sequence or show_chord then
            local content_min_x, _ = ImGui.GetWindowContentRegionMin(ctx)
            local content_max_x, _ = ImGui.GetWindowContentRegionMax(ctx)
            local inner_w = content_max_x - content_min_x
            local gap = 6
            local col_w = (inner_w - (2 * gap)) / 3
            local col1_x = content_min_x
            local col2_x = content_min_x + col_w + gap
            local col3_x = content_min_x + (2 * (col_w + gap))
            local row_y = ImGui.GetCursorPosY(ctx)

            -- Column 1: Duration
            local label1 = "Duration:"
            ImGui.SetCursorPos(ctx, col1_x, row_y)
            ImGui.Text(ctx, label1)
            local label1_w = ImGui.CalcTextSize(ctx, label1)
            local label_gap = 6
            ImGui.SetCursorPos(ctx, col1_x + label1_w + label_gap, row_y)
            ImGui.PushItemWidth(ctx, col_w - (label1_w + label_gap))
            local preview_duration = (selected_duration == "1" and "1/1")
                or (selected_duration == "2" and "1/2")
                or (selected_duration == "4" and "1/4")
                or (selected_duration == "8" and "1/8")
                or (selected_duration == "16" and "1/16")
                or "1/4"
            if ImGui.BeginCombo(ctx, "##duration", preview_duration) then
                local dur_opts = {
                    {label = "1/1", val = "1"},
                    {label = "1/2", val = "2"},
                    {label = "1/4", val = "4"},
                    {label = "1/8", val = "8"},
                    {label = "1/16", val = "16"}
                }
                for _, opt in ipairs(dur_opts) do
                    local selected = (selected_duration == opt.val)
                    if ImGui.Selectable(ctx, opt.label, selected) then
                        selected_duration = opt.val
                    end
                end
                ImGui.EndCombo(ctx)
            end
            ImGui.PopItemWidth(ctx)

            -- Column 2: Transpose (combo + +/- buttons)
            local label2 = "Trans:"
            ImGui.SetCursorPos(ctx, col2_x, row_y)
            ImGui.Text(ctx, label2)
            local label2_w = ImGui.CalcTextSize(ctx, label2)
            local trans_combo_w = col_w - (label2_w + label_gap) - ((transpose_button_size * 2) + (gap * 2))
            if trans_combo_w < 40 then trans_combo_w = 40 end
            ImGui.SetCursorPos(ctx, col2_x + label2_w + label_gap, row_y)
            ImGui.PushItemWidth(ctx, trans_combo_w)
            if ImGui.BeginCombo(ctx, "##transpose", selected_transpose_mode) then
                for mode, _ in pairs(transpose_modes) do
                    if ImGui.Selectable(ctx, mode, selected_transpose_mode == mode) then
                        selected_transpose_mode = mode
                    end
                end
                ImGui.EndCombo(ctx)
            end
            ImGui.PopItemWidth(ctx)
            local btn1_x = col2_x + label2_w + label_gap + trans_combo_w + gap
            local btn_y = row_y
            ImGui.SetCursorPos(ctx, btn1_x, btn_y)
            if ImGui.Button(ctx, "-", transpose_button_size, transpose_button_size) then
                quick_chord_input = ""
                local steps = transpose_modes[selected_transpose_mode]
                input_sequence = TransposeSequence(steps, -1)
                input_chord = TransposeChord(steps, -1)
            end
            local btn2_x = btn1_x + transpose_button_size + gap
            ImGui.SetCursorPos(ctx, btn2_x, btn_y)
            if ImGui.Button(ctx, "+", transpose_button_size, transpose_button_size) then
                quick_chord_input = ""
                local steps = transpose_modes[selected_transpose_mode]
                input_sequence = TransposeSequence(steps, 1)
                input_chord = TransposeChord(steps, 1)
            end

            -- Column 3: Strings
            local label3 = "Strings:"
            ImGui.SetCursorPos(ctx, col3_x, row_y)
            ImGui.Text(ctx, label3)
            local label3_w = ImGui.CalcTextSize(ctx, label3)
            ImGui.SetCursorPos(ctx, col3_x + label3_w + label_gap, row_y)
            ImGui.PushItemWidth(ctx, col_w - (label3_w + label_gap))
            local n_changed, new_n = ImGui.InputInt(ctx, "##num_strings", num_strings, 1, 2)
            if n_changed then
                setNumStrings(new_n)
            end
            ImGui.PopItemWidth(ctx)

            local row_advance = math.max(ImGui.GetTextLineHeight(ctx), ImGui.GetFrameHeight(ctx)) + 6
            ImGui.SetCursorPosY(ctx, row_y + row_advance)

            ImGui.Text(ctx, "Tuning:  ")
            ImGui.SameLine(ctx)
            ImGui.PushItemWidth(ctx, tuning_width)
            if ImGui.BeginCombo(ctx, "##tuning", selected_tuning) then
                for tuning_name, _ in pairs(tunings) do
                    if ImGui.Selectable(ctx, tuning_name, selected_tuning == tuning_name) then
                        selected_tuning = tuning_name
                        local src = tunings[tuning_name] or {}
                        local arr = {}
                        for i=1, math.min(#src, num_strings) do arr[i] = src[i] end
                        local fill = arr[#arr] or src[#src] or base_notes[#base_notes] or 40
                        for i=#arr+1, num_strings do arr[i] = fill end
                        base_notes = arr
                        tunings[tuning_name] = {table.unpack(arr)}
                    end
                end
                ImGui.EndCombo(ctx)
            end
            
            ImGui.SameLine(ctx)
            if ImGui.Button(ctx, "Custom Tunings", tuning_width) then
                show_custom_tuning_window = true
            end
            
            ImGui.Text(ctx, "Voicing: ")
            ImGui.SameLine(ctx)
            ImGui.PushItemWidth(ctx, tuning_width)
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
            ImGui.SetCursorPosX(ctx, ImGui.GetCursorPosX(ctx) + 2)
            _, insert_in_existing = ImGui.Checkbox(ctx, "Insert in selected MIDI item", insert_in_existing)
            ImGui.Spacing(ctx)
            ImGui.Separator(ctx)
            ImGui.Spacing(ctx)
        end

        if show_sequence then
            ImGui.Text(ctx, "Sequence:")
            ImGui.SameLine(ctx)
            ImGui.PushItemWidth(ctx, 163) 
            local _, new_sequence = ImGui.InputTextWithHint(ctx, "##sequence", "1:0-2:2-3:4", input_sequence)
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
                        local new_pos = r.MIDI_GetProjTimeFromPPQPos(take, (note_length * note_count))
                        r.SetEditCurPos(new_pos, true, true)
                    end
                end
            end 
            ImGui.PopStyleColor(ctx, 3)
            ImGui.SameLine(ctx)
            ImGui.Text(ctx, "(s:f e.g., 1:0-2:2-3:4; legacy 0-3-5 also works)")
            local desired_spacing = is_xl_mode and 28 or 20
            local board_height = math.max(desired_spacing * (num_strings - 1), is_xl_mode and 120 or 100)

            local content_min_x, _ = ImGui.GetWindowContentRegionMin(ctx)
            local content_max_x, _ = ImGui.GetWindowContentRegionMax(ctx)
            local content_width = (content_max_x - content_min_x)
            local left_margin = 30
            local right_margin = 10
            local start_x_in_window = content_min_x + left_margin
            local board_width = math.max(50, content_width - (left_margin + right_margin))

            DrawFretboard(ctx, start_x_in_window, ImGui.GetCursorPosY(ctx)+10, board_width, board_height)
            ImGui.Dummy(ctx, 0, board_height + (is_xl_mode and 30 or 20))
            ImGui.Dummy(ctx, 0, is_xl_mode and 5 or 10)
        end
        if show_chord then    
            ImGui.Spacing(ctx)
            ImGui.Text(ctx, "Chord:")
            ImGui.SameLine(ctx)
            do
                local char_w = select(1, ImGui.CalcTextSize(ctx, "0"))
                local est_chars = (num_strings or 6) * 2 + 6
                local dyn_w = math.floor(char_w * est_chars)
                local cap = is_xl_mode and 220 or 180
                if (num_strings or 6) >= 9 then
                    dyn_w = cap
                else
                    if dyn_w > cap then dyn_w = cap end
                    if dyn_w < 100 then dyn_w = 100 end
                end
                ImGui.PushItemWidth(ctx, dyn_w)
            end
            local _, new_input = ImGui.InputTextWithHint(ctx, "##chord", "X 3 2 0 1 0", input_chord)
            input_chord = FilterChordInput(new_input)
            ImGui.PopItemWidth(ctx)
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
                if #frets == num_strings then
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
                            local new_pos = r.MIDI_GetProjTimeFromPPQPos(take, note_length)
                            r.SetEditCurPos(new_pos, true, true)
                        end
                    end
                else
                    ImGui.TextColored(ctx, 0xFF0000FF, "Input must contain exactly " .. tostring(num_strings) .. " positions")
                end
            end
            ImGui.PopStyleColor(ctx, 3)
            local base_size = is_xl_mode and 180 or 120
            local desired_spacing = is_xl_mode and 28 or 20
            local strings_dim = math.max(desired_spacing * (num_strings - 1), is_xl_mode and 120 or 100)
            local y_offset = (is_xl_mode and not chord_board_horizontal) and 30 or 20

            local content_min_x, _ = ImGui.GetWindowContentRegionMin(ctx)
            local content_max_x, _ = ImGui.GetWindowContentRegionMax(ctx)
            local content_width = (content_max_x - content_min_x)
            local left_margin = 10
            local right_margin = 10
            local internal_offset = chord_board_horizontal and 20 or 15
            local avail_width = math.max(50, content_width - (left_margin + right_margin + internal_offset))
            local start_x_in_window = content_min_x + left_margin

            if chord_board_horizontal then
                base_size = math.max(40, avail_width / 2.5)
                DrawChordboard(ctx, start_x_in_window, ImGui.GetCursorPosY(ctx) + y_offset, strings_dim, base_size)
                ImGui.Dummy(ctx, 0, strings_dim + (is_xl_mode and 240 or 200))
            else
                local base_for_n   = strings_dim                                    -- desired span for current N
                local base_for_16  = math.max((is_xl_mode and 28 or 20) * 15, is_xl_mode and 120 or 100) -- desired span if N=16
                local ramp_start   = 12
                local progress     = 0
                if num_strings >= ramp_start then
                    progress = math.min(1, (num_strings - ramp_start) / (16 - ramp_start))
                end
                local extra        = math.max(0, avail_width - base_for_16)
                local target_width = base_for_n + (extra * progress)
                local v_width      = math.min(avail_width, target_width)
                DrawChordboard(ctx, start_x_in_window, ImGui.GetCursorPosY(ctx) + y_offset, v_width, base_size)
                local board_vertical_height = base_size * 2.5
                ImGui.Dummy(ctx, 0, board_vertical_height + (is_xl_mode and 225 or 185))
            end
        end

    ImGui.PopStyleVar(ctx, 2)
    ImGui.PopStyleColor(ctx, 8)
        ImGui.PopFont(ctx)

        if show_custom_tuning_window then
            ShowCustomTuningWindow()
        end

        if show_settings_window then
            ImGui.PushFont(ctx, font)
            if settings_next_pos then
                ImGui.SetNextWindowPos(ctx, settings_next_pos.x, settings_next_pos.y, ImGui.Cond_Always)
                settings_next_pos = nil
            end

            local flags = ImGui.WindowFlags_AlwaysAutoResize | ImGui.WindowFlags_NoScrollbar | ImGui.WindowFlags_NoTitleBar
            local s_visible, s_open = ImGui.Begin(ctx, "Settings", true, flags)
            if s_visible then
                ImGui.Text(ctx, "Settings")
                ImGui.Separator(ctx)

                ImGui.Text(ctx, "Kleuren (grijstinten 0=zwart .. 1=wit)")
                ImGui.PushItemWidth(ctx, 260)
                local changed
                changed, ui_window_alpha = ImGui.SliderDouble(ctx, "Transparantie", ui_window_alpha, 0.2, 1.0, "%.2f")
                if changed then r.SetExtState("TK_GTR2MIDI","ui_window_alpha", tostring(ui_window_alpha), true) end
                changed, ui_window_bg_gray = ImGui.SliderDouble(ctx, "Window achtergrond", ui_window_bg_gray, 0.0, 1.0, "%.2f")
                if changed then r.SetExtState("TK_GTR2MIDI","ui_window_bg_gray", tostring(ui_window_bg_gray), true) end
                changed, ui_button_gray = ImGui.SliderDouble(ctx, "Knop kleur", ui_button_gray, 0.0, 1.0, "%.2f")
                if changed then r.SetExtState("TK_GTR2MIDI","ui_button_gray", tostring(ui_button_gray), true) end
                changed, ui_dropdown_gray = ImGui.SliderDouble(ctx, "Dropdown kleur", ui_dropdown_gray, 0.0, 1.0, "%.2f")
                if changed then r.SetExtState("TK_GTR2MIDI","ui_dropdown_gray", tostring(ui_dropdown_gray), true) end
                changed, ui_input_gray = ImGui.SliderDouble(ctx, "Invoerveld kleur", ui_input_gray, 0.0, 1.0, "%.2f")
                if changed then r.SetExtState("TK_GTR2MIDI","ui_input_gray", tostring(ui_input_gray), true) end
                changed, ui_text_gray = ImGui.SliderDouble(ctx, "Tekst kleur", ui_text_gray, 0.0, 1.0, "%.2f")
                if changed then r.SetExtState("TK_GTR2MIDI","ui_text_gray", tostring(ui_text_gray), true) end
                ImGui.PopItemWidth(ctx)

                ImGui.Separator(ctx)
                ImGui.Text(ctx, "Ronding")
                ImGui.PushItemWidth(ctx, 260)
                changed, ui_window_rounding = ImGui.SliderDouble(ctx, "Venster ronding", ui_window_rounding, 0.0, 20.0, "%.1f")
                if changed then r.SetExtState("TK_GTR2MIDI","ui_window_rounding", tostring(ui_window_rounding), true) end
                changed, ui_button_rounding = ImGui.SliderDouble(ctx, "Knop ronding", ui_button_rounding, 0.0, 20.0, "%.1f")
                if changed then r.SetExtState("TK_GTR2MIDI","ui_button_rounding", tostring(ui_button_rounding), true) end
                ImGui.PopItemWidth(ctx)

                ImGui.Text(ctx, "MIDI Channel Mode")
                ImGui.PushItemWidth(ctx, 260)
                local mode = per_string_channels and "Per string (channels 1..N)" or "Single channel (channel 1)"
                if ImGui.BeginCombo(ctx, "##chan_mode", mode) then
                    if ImGui.Selectable(ctx, "Per string (channels 1..N)", per_string_channels) then
                        per_string_channels = true
                        r.SetExtState("TK_GTR2MIDI","per_string_channels", tostring(per_string_channels), true)
                    end
                    if ImGui.Selectable(ctx, "Single channel (channel 1)", not per_string_channels) then
                        per_string_channels = false
                        r.SetExtState("TK_GTR2MIDI","per_string_channels", tostring(per_string_channels), true)
                    end
                    ImGui.EndCombo(ctx)
                end
                ImGui.PopItemWidth(ctx)

                ImGui.Separator(ctx)
                if ImGui.Button(ctx, "Close", 80, 0) then
                    show_settings_window = false
                end
            end
            ImGui.End(ctx)
            ImGui.PopFont(ctx)
        end
        
        ImGui.End(ctx)
    end
    -- Pop pre-Begin pushes (Alpha + WindowBg)
    ImGui.PopStyleColor(ctx, 1)
    ImGui.PopStyleVar(ctx, 1)
    if open then r.defer(MainLoop) end
end

r.defer(MainLoop)
