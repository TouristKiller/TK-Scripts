-- TK_GTR2MIDI_ChordEngine.lua
-- Engine for generating guitar voicings dynamically based on tuning and chord formulas.

local ChordEngine = {}

ChordEngine.Formulas = {
    {name = "Major",    short = "Maj",  intervals = {0, 4, 7}},
    {name = "Minor",    short = "m",    intervals = {0, 3, 7}},
    {name = "5",        short = "5",    intervals = {0, 7}},
    {name = "Dom 7",    short = "7",    intervals = {0, 4, 7, 10}},
    {name = "Maj 7",    short = "M7",   intervals = {0, 4, 7, 11}},
    {name = "Min 7",    short = "m7",   intervals = {0, 3, 7, 10}},
    {name = "Sus 4",    short = "sus4", intervals = {0, 5, 7}},
    {name = "Sus 2",    short = "sus2", intervals = {0, 2, 7}},
    {name = "Add 9",    short = "add9", intervals = {0, 4, 7, 14}},
    {name = "Dim",      short = "dim",  intervals = {0, 3, 6}},
    {name = "Aug",      short = "aug",  intervals = {0, 4, 8}},
    {name = "6",        short = "6",    intervals = {0, 4, 7, 9}},
    {name = "m6",       short = "m6",   intervals = {0, 3, 7, 9}},
    {name = "9",        short = "9",    intervals = {0, 4, 7, 10, 14}},
    {name = "m9",       short = "m9",   intervals = {0, 3, 7, 10, 14}},
    {name = "Maj9",     short = "M9",   intervals = {0, 4, 7, 11, 14}},
    {name = "11",       short = "11",   intervals = {0, 4, 7, 10, 14, 17}},
    {name = "13",       short = "13",   intervals = {0, 4, 7, 10, 14, 21}},
}

local function array_has_value(tab, val)
    for _, v in ipairs(tab) do if v == val then return true end end
    return false
end

-- Check if a grip is physically playable with 4 fingers
local function is_playable(grip)
    local frets = {}
    local min_fret = 999
    
    for s, f in ipairs(grip) do
        if f > 0 then
            table.insert(frets, f)
            if f < min_fret then min_fret = f end
        end
    end
    
    if #frets == 0 then return true end -- All open/mute

    -- Count notes that are NOT on the lowest fret (handled by index/barre)
    local notes_above_barre = 0
    for _, f in ipairs(frets) do
        if f > min_fret then
            notes_above_barre = notes_above_barre + 1
        end
    end

    -- You have 3 fingers left (Middle, Ring, Pinky) for notes above the index/barre.
    -- If you need more than 3, it's usually impossible (unless using thumb or complex partial barres)
    if notes_above_barre > 3 then return false end

    return true
end

-- Helper to guess fingers based on fret positions (Improved Gap Logic)
local function guess_fingers(grip_table)
    local frets_only = {}
    local min_fret = 999
    
    -- Collect played frets
    for s, f in ipairs(grip_table) do
        if f > 0 then
            table.insert(frets_only, {string=s, fret=f})
            if f < min_fret then min_fret = f end
        end
    end
    
    if #frets_only == 0 then return "0 0 0 0 0 0", false end 

    -- Check for Barre
    local barre_fret = nil
    local notes_on_min_fret = 0
    for _, note in ipairs(frets_only) do
        if note.fret == min_fret then notes_on_min_fret = notes_on_min_fret + 1 end
    end
    
    -- Heuristic: If 2 or more notes are on the lowest fret, assume Barre with Finger 1
    if notes_on_min_fret >= 2 then
        barre_fret = min_fret
    end

    -- Finger availability tracking
    local finger_assignments = {} 
    local finger_used = { [1]=false, [2]=false, [3]=false, [4]=false }

    -- If Barre, Finger 1 is used
    if barre_fret then finger_used[1] = true end

    -- Sort notes: 
    -- 1. Frets (Low to High)
    -- 2. Strings (Low Index/Low Pitch to High Index/High Pitch) -> Bass strings first!
    table.sort(frets_only, function(a,b) 
        if a.fret == b.fret then return a.string < b.string end -- Process Bass strings first (Low ID)
        return a.fret < b.fret 
    end)

    for _, note in ipairs(frets_only) do
        if barre_fret and note.fret == barre_fret then
            finger_assignments[note.string] = 1
        else
            -- Determine ideal finger based on gap from min_fret
            -- Gap 0 (min_fret but not barre) -> Finger 1
            -- Gap 1 -> Finger 2
            -- Gap 2 -> Finger 3
            -- Gap 3+ -> Finger 4
            local gap = note.fret - min_fret
            local target = 0
            
            if gap == 0 then target = 1
            elseif gap == 1 then target = 2
            elseif gap == 2 then target = 3
            else target = 4 end

            -- If target is 1 but used (e.g. barre), shift to 2
            if target == 1 and finger_used[1] then target = 2 end

            -- Try to assign target, or find nearest available neighbor
            local assigned = nil
            
            -- Preference order based on target
            local try_order = {}
            if target == 1 then try_order = {1, 2, 3, 4}
            elseif target == 2 then try_order = {2, 3, 4, 1}
            elseif target == 3 then try_order = {3, 4, 2}
            elseif target == 4 then try_order = {4, 3, 2}
            end

            for _, f_try in ipairs(try_order) do
                if not finger_used[f_try] then
                    assigned = f_try
                    break
                end
            end
            
            -- Fallback if all preferred are taken (rare in standard chords)
            if not assigned then assigned = 4 end

            finger_assignments[note.string] = assigned
            finger_used[assigned] = true
        end
    end

    -- Build output string
    local out = {}
    for s, f in ipairs(grip_table) do
        if f == -1 or f == 0 then
            table.insert(out, "0") 
        else
            table.insert(out, tostring(finger_assignments[s] or 0))
        end
    end
    return table.concat(out, " "), (barre_fret ~= nil)
end

function ChordEngine.Solve(root_note, formula_idx, current_tuning, max_fret_range, limit_results, complexity_mode)
    max_fret_range = max_fret_range or 4
    limit_results = limit_results or 50
    complexity_mode = complexity_mode or "Simple" -- "Simple" or "Rich"

    local formula = ChordEngine.Formulas[formula_idx]
    if not formula then return {} end

    local required_notes = {}
    for _, interval in ipairs(formula.intervals) do
        table.insert(required_notes, (root_note + interval) % 12)
    end

    local string_options = {}
    for s = 1, #current_tuning do
        local open_pitch = current_tuning[s]
        local valid_frets = {-1} 
        for fret = 0, 12 do -- Limit to 12 frets
            local pitch = open_pitch + fret
            if array_has_value(required_notes, pitch % 12) then
                table.insert(valid_frets, fret)
            end
        end
        string_options[s] = valid_frets
    end

    local results = {}
    local count = 0
    local max_results = 200 

    local function search(string_idx, current_grip)
        if count >= max_results then return end

        if string_idx > #current_tuning then
            local notes_present = {}
            local min_fret, max_fret = 999, -999
            local has_notes = false
            local lowest_string_idx = 0
            local num_strings_played = 0

            for s, fret in ipairs(current_grip) do
                if fret >= 0 then
                    has_notes = true
                    num_strings_played = num_strings_played + 1
                    if lowest_string_idx == 0 then lowest_string_idx = s end
                    
                    local pitch = current_tuning[s] + fret
                    notes_present[pitch % 12] = true
                    
                    if fret > 0 then
                        if fret < min_fret then min_fret = fret end
                        if fret > max_fret then max_fret = fret end
                    end
                end
            end

            if not has_notes then return end

            -- Constraint 1: Root must be bass note
            if lowest_string_idx > 0 then
                local bass_pitch = current_tuning[lowest_string_idx] + current_grip[lowest_string_idx]
                if (bass_pitch % 12) ~= root_note then return end
            end

            -- Constraint 2: Playability (Stretch)
            if min_fret ~= 999 and (max_fret - min_fret) > max_fret_range then return end

            -- Constraint 3: Essential Intervals
            local has_third = false
            if array_has_value(formula.intervals, 3) then -- Minor 3rd
                if notes_present[(root_note + 3)%12] then has_third = true end
            elseif array_has_value(formula.intervals, 4) then -- Major 3rd
                if notes_present[(root_note + 4)%12] then has_third = true end
            else
                has_third = true 
            end
            if not has_third then return end

            local has_seventh = false
            local requires_seventh = false
            if array_has_value(formula.intervals, 10) then 
                requires_seventh = true
                if notes_present[(root_note + 10)%12] then has_seventh = true end
            elseif array_has_value(formula.intervals, 11) then
                requires_seventh = true
                if notes_present[(root_note + 11)%12] then has_seventh = true end
            end
            if requires_seventh and not has_seventh then return end

            if not notes_present[root_note] then return end 

            -- Constraint 4: Physical Playability Check
            if not is_playable(current_grip) then return end

            local grip_str = table.concat(current_grip, " "):gsub("%-1", "X")
            local fingers_str, is_barre = guess_fingers(current_grip)
            
            -- Constraint 5: Finger Order Logic (Prevent Finger Crossing)
            -- Rule: A finger with a lower ID (e.g. Middle=2) cannot be on a higher fret 
            -- than a finger with a higher ID (e.g. Ring=3).
            -- Exception: If frets are equal, order doesn't matter (handled by string adjacency).
            local finger_map = {} 
            local f_idx = 1
            for f_char in fingers_str:gmatch("%S+") do
                finger_map[f_idx] = tonumber(f_char)
                f_idx = f_idx + 1
            end

            local crossing_violation = false
            for s1 = 1, #current_tuning do
                if current_grip[s1] > 0 and finger_map[s1] > 0 then
                    for s2 = 1, #current_tuning do
                        if s1 ~= s2 and current_grip[s2] > 0 and finger_map[s2] > 0 then
                            local fret1 = current_grip[s1]
                            local fret2 = current_grip[s2]
                            local fing1 = finger_map[s1]
                            local fing2 = finger_map[s2]
                            
                            -- If Fret 1 is strictly higher than Fret 2, Finger 1 must NOT be strictly lower than Finger 2
                            -- (e.g. Fret 5 vs Fret 3 -> Finger must be >= Finger at Fret 3)
                            if fret1 > fret2 and fing1 < fing2 then
                                crossing_violation = true
                                break
                            end

                            -- If Frets are equal, Bass string (Lower ID) should have Lower or Equal Finger ID
                            -- (Natural hand position: Index on Bass, Pinky on Treble)
                            if fret1 == fret2 and s1 < s2 and fing1 > fing2 then
                                crossing_violation = true
                                break
                            end
                        end
                    end
                end
                if crossing_violation then break end
            end

            if crossing_violation then return end -- Reject this chord

            -- SCORING SYSTEM (Lower is better)
            local score = 0
            
            -- 1. Position Score (Higher frets = worse)
            local pos = (min_fret == 999) and 0 or min_fret
            score = score + (pos * 2) -- Increased penalty for high positions

            -- 2. Open Chord Bonus (Very good)
            local num_open = 0
            for _, f in ipairs(current_grip) do if f == 0 then num_open = num_open + 1 end end

            if num_open > 0 then 
                -- Penalty for open strings combined with high frets (awkward)
                if min_fret ~= 999 and min_fret > 4 then
                    score = score + 50 -- Heavy penalty
                else
                    score = score - 25 -- Increased Bonus for standard open chords (Was -15)
                    score = score - (num_open * 5) -- Extra bonus per open string (Prefer more open strings)
                end
            end

            -- 3. Open Position Bonus (Frets <= 3) - "Campfire Chords"
            if max_fret <= 3 then
                score = score - 20 -- Significant bonus for staying in the first 3 frets
            end

            -- 4. Barre Bonus & String Count (Dependent on Complexity Mode)
            if complexity_mode == "Rich" then
                -- Rich Mode: Loves Barres and Full Chords
                if is_barre then score = score - 25 end 
                score = score - (num_strings_played * 8) -- Heavy bonus for more strings
            else
                -- Simple Mode: Hates Barres, prefers easier grips
                if is_barre then score = score + 10 end -- Penalty for barre!
                score = score - (num_strings_played * 2) -- Small bonus for strings, but not enough to override difficulty
            end

            -- 5. String Continuity (Punish "inside" mutes like X 3 X 5 X)
            local gaps = 0
            local in_chord = false
            local muted_inside = false
            for s=lowest_string_idx, #current_grip do
                if current_grip[s] >= 0 then
                    if muted_inside then gaps = gaps + 1 end
                    in_chord = true
                    muted_inside = false
                else
                    if in_chord then muted_inside = true end
                end
            end
            score = score + (gaps * 10) 

            table.insert(results, {
                grip = grip_str, 
                fingers = fingers_str, 
                min = min_fret,
                max = max_fret,
                score = score
            })
            count = count + 1
            return
        end

        local options = string_options[string_idx]
        for _, fret in ipairs(options) do
            current_grip[string_idx] = fret
            search(string_idx + 1, current_grip)
            if count >= max_results then return end
        end
    end

    search(1, {})

    -- Sorting based on Score
    table.sort(results, function(a, b)
        return a.score < b.score
    end)

    -- Return only top N results, then sort those by Position (Min Fret)
    local top_results = {}
    for i = 1, math.min(#results, limit_results) do
        table.insert(top_results, results[i])
    end

    -- Re-sort the top results by fret position (Low to High)
    table.sort(top_results, function(a, b)
        local a_pos = (a.min == 999) and 0 or a.min
        local b_pos = (b.min == 999) and 0 or b.min
        
        -- If positions are equal, fallback to score
        if a_pos == b_pos then
            return a.score < b.score
        end
        return a_pos < b_pos
    end)

    return top_results
end

return ChordEngine
