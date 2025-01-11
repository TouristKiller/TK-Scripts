-- @description TK GTR2MIDI
-- @author TouristKiller
-- @version 0.1.0:
-- @changelog:
--[[        
+ First Reapack Release for testing          
]]--   
-- I am a drummer..... dont kill me if I mess up the guitar stuff ;o)
------------------------------------------------------------------------
local r = reaper
local ctx = r.ImGui_CreateContext('TK_GTR2MIDI')
local font = r.ImGui_CreateFont('Arial', 12)
r.ImGui_Attach(ctx, font)

local input_sequence = ""
local input_chord = ""
local selected_duration = "4"
local selected_string = 1
local base_notes = {64,59,55,50,45,40}
local string_names = {"E (High)","B","G","D","A","E (Low)"}
local voicings = {}
local chord_fingers = {}

local show_sequence = false
local show_chord = true

local tunings = {
    ["Standard (EADGBE)"] = {64,59,55,50,45,40},
    ["Drop D (DADGBE)"] = {64,59,55,50,45,38},
    ["Open G (DGDGBD)"] = {62,59,55,50,43,38},
    ["Open D (DADF#AD)"] = {62,57,54,50,45,38},
    ["DADGAD"] = {62,57,55,50,45,38}
}
local selected_tuning = "Standard (EADGBE)"
base_notes = tunings[selected_tuning]

local finger_colors = {
    [1] = 0xEF0038FF, 
    [2] = 0x38B549FF,  
    [3] = 0x0099DDFF,  
    [4] = 0xF5811FFF  
}

function LoadVoicings()
    local script_path = debug.getinfo(1,'S').source:match("@(.*)\\")
    local file = io.open(script_path .. "\\ChordVoicings.txt", "r")
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
                        chord_fingers[voicing] = finger_array  -- Gebruik voicing als key
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

function CreateMIDIItem()
    local track = r.GetSelectedTrack(0,0)
    if not track then return end
    local cursor_pos = r.GetCursorPosition()
    local ppq = 960
    local beats = 4/tonumber(selected_duration)
    local item = r.CreateNewMIDIItemInProj(track, cursor_pos, cursor_pos + beats/2)
    local take = r.GetActiveTake(item)
    local item_end = cursor_pos + beats/2
    r.SetEditCurPos(item_end, true, false)
    return item, take, ppq*beats
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
                -- Bepaal vinger op basis van afstand tot laagste fret
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
    local draw_list = r.ImGui_GetWindowDrawList(ctx)
    local spacing = 25
    local circle_size = 8
    local labels = {
        "1 - Index finger",
        "2 - Middle finger", 
        "3 - Ring finger",
        "4 - Pinky"
    }

    r.ImGui_DrawList_AddText(draw_list, startX, startY-25, 0xFFFFFFFF, "Finger positions:")
    
    -- legenda items
    for i, label in ipairs(labels) do
        local y = startY + (i-1) * spacing
        r.ImGui_DrawList_AddCircleFilled(draw_list, startX + circle_size, y, circle_size, finger_colors[i])
        r.ImGui_DrawList_AddCircle(draw_list, startX + circle_size, y, circle_size, 0xFFFFFFFF)
        r.ImGui_DrawList_AddText(draw_list, startX + (circle_size * 2) + 10, y - 6, 0xFFFFFFFF, label)
    end
end

function InsertChord(take, frets, note_length)
    for string_num, fret in ipairs(frets) do
        if fret ~= "X" then
            local note = base_notes[7-string_num] + tonumber(fret)  -- 7-string_num voor correcte noot index
            local midi_channel = string_num-1  -- string_num 1 (low E) = channel 0
            r.MIDI_InsertNote(take, false, false, 0, note_length, midi_channel, note, 100, false)
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

function InsertSequence(take, notes, note_length)
    local base_note = base_notes[selected_string]
    local position = 0
    local idx = 0
    local note_count = 0
    r.GetSetMediaItemTakeInfo_String(take, "P_NAME", notes, true)
    for _ in notes:gmatch("([^-]+)") do 
        note_count = note_count + 1 
    end
    local item = r.GetMediaItemTake_Item(take)
    r.SetMediaItemInfo_Value(item, "D_LENGTH", (note_length * note_count)/960/2)
    r.SetMediaItemInfo_Value(item, "B_LOOPSRC", 0)
    r.SetMediaItemInfo_Value(item, "B_LOOP", 0)
    for note in notes:gmatch("([^-]+)") do
        local midi_note = base_note + tonumber(note)
        r.MIDI_InsertNote(take, false, false, position, note_length, 0, midi_note, 100, false)
        local retval, selected, muted, startppq, endppq, chan, pitch, vel = r.MIDI_GetNote(take, idx)
        if retval then 
            r.MIDI_SetNote(take, idx, false, false, position, position + note_length, 0, midi_note, 100, true)
        end
        position = position + note_length
        idx = idx + 1
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
    -- Verwijder alle ongeldige karakters
    local filtered = input:gsub("[^X0-9%s]", "")
    return filtered
end

function HandleFretboardClick(ctx,startX,startY,width,height,isChord,rightClick)
    local mouseX,mouseY=r.ImGui_GetMousePos(ctx)
    local winX,winY=r.ImGui_GetWindowPos(ctx)
    local num_strings=6
    local num_frets=12 
    local string_spacing=isChord and width/(num_strings-1) or height/(num_strings-1)
    local fret_spacing=isChord and height/num_frets or width/num_frets
    mouseX=mouseX-(winX+startX)
    mouseY=mouseY-(winY+startY)
        if isChord then
            for string_num=0,num_strings-1 do
                local circle_x=string_num*string_spacing
                
                -- Check 0-fret (nut)
                local circle_y=0
                local distance=math.sqrt((mouseX-circle_x)^2+(mouseY-circle_y)^2)
                if distance<=5 then
                    local frets={"X","X","X","X","X","X"}
                    local i=1
                    for existing_fret in input_chord:gmatch("%S+") do
                        frets[i]=existing_fret
                        i=i+1
                    end
                    frets[string_num+1]=rightClick and "X" or "0"  -- Gebruik "0" voor open snaar
                    input_chord=table.concat(frets," ")
                    return true
                end
                
                -- Check frets 1-5
                for fret=1,num_frets do
                    circle_y=(fret*fret_spacing)-(fret_spacing/2)
                    distance=math.sqrt((mouseX-circle_x)^2+(mouseY-circle_y)^2)
                    if distance<=5 then
                        HandleChordSelection(string_num, fret, rightClick)
                        return true
                    end
                end
            end
        else
        -- Sequence board logic
        for string_num=0,num_strings-1 do
            local circle_y=string_num*string_spacing
            
            -- Check 0-fret (nut position)
            local circle_x=0
            local distance=math.sqrt((mouseX-circle_x)^2+(mouseY-circle_y)^2)
            if distance<=5 then
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
            
            -- Check frets 1-12 (between fret lines)
            for fret=1,num_frets do
                circle_x=(fret*fret_spacing)-(fret_spacing/2)
                distance=math.sqrt((mouseX-circle_x)^2+(mouseY-circle_y)^2)
                if distance<=5 then
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
    local marker_pos
    if orientation == "vertical" then
        marker_pos = startX + (spacing * 3) - (spacing/2)
    else
        marker_pos = startY + (spacing * 3) - (spacing/2)
    end
    for _, fret in ipairs(fret_markers) do
        local pos
        if orientation == "vertical" then
            pos = startY + (fret*spacing) - (spacing/2)
            if fret == 12 then
                r.ImGui_DrawList_AddCircleFilled(draw_list, marker_pos, pos-4, 3, 0xFFFFFFFF)
                r.ImGui_DrawList_AddCircleFilled(draw_list, marker_pos, pos+4, 3, 0xFFFFFFFF)
            else
                r.ImGui_DrawList_AddCircleFilled(draw_list, marker_pos, pos, 3, 0xFFFFFFFF)
            end
        else
            pos = startX + (fret*spacing) - (spacing/2)
            if fret == 12 then
                r.ImGui_DrawList_AddCircleFilled(draw_list, pos-4, marker_pos, 3, 0xFFFFFFFF)
                r.ImGui_DrawList_AddCircleFilled(draw_list, pos+4, marker_pos, 3, 0xFFFFFFFF)
            else
                r.ImGui_DrawList_AddCircleFilled(draw_list, pos, marker_pos, 3, 0xFFFFFFFF)
            end
        end
    end
end

function DrawFretboard(ctx,startX,startY,width,height)
    local draw_list=r.ImGui_GetWindowDrawList(ctx)
    local winX,winY=r.ImGui_GetWindowPos(ctx)
    startX=winX+startX
    startY=winY+startY
    local num_strings=6
    local num_frets=12
    local string_spacing=height/(num_strings-1)
    local fret_spacing=width/num_frets
    -- Draw fret markers
    local fret_markers = {3,5,7,9,12}
    DrawFretMarkers(draw_list, startX, startY, fret_spacing, "horizontal")
    -- Draw strings
    for i=0,num_strings-1 do
        local y=startY+(i*string_spacing)
        r.ImGui_DrawList_AddLine(draw_list,startX,y,startX+width,y,0xFFFFFFFF)
        local note_name=GetNoteName(base_notes[i+1])
        r.ImGui_DrawList_AddText(draw_list,startX-25,y-6,0xFFFFFFFF,note_name)
    end
    -- Draw frets and numbers
    for i=0,num_frets do
        local x=startX+(i*fret_spacing)
        if i == 0 then
            r.ImGui_DrawList_AddLine(
                draw_list,
                x,
                startY,
                x,
                startY+height,
                0xFFFFFFFF,
                5.0  
            )
            r.ImGui_DrawList_AddText(draw_list,x-3,startY+height+5,0xFFFFFFFF,"0")
        else
            r.ImGui_DrawList_AddLine(
                draw_list,
                x,
                startY,
                x,
                startY+height,
                0xFFFFFFFF,
                1.0
            )
            local text_x = x - (fret_spacing/2) - 3
            r.ImGui_DrawList_AddText(draw_list,text_x,startY+height+5,0xFFFFFFFF,tostring(i))
        end
    end
    for string_num=0,num_strings-1 do
        local circle_y=startY+(string_num*string_spacing)
        local circle_x=startX
        r.ImGui_DrawList_AddCircle(draw_list,circle_x,circle_y,5,0x80808080)
        
        for fret=1,num_frets do
            circle_x=startX+(fret*fret_spacing)-(fret_spacing/2)
            r.ImGui_DrawList_AddCircle(draw_list,circle_x,circle_y,5,0x80808080)
        end
    end
    if r.ImGui_IsMouseClicked(ctx,0) then
        HandleFretboardClick(ctx,startX-winX,startY-winY,width,height,false,false)
    elseif r.ImGui_IsMouseClicked(ctx,1) then
        HandleFretboardClick(ctx,startX-winX,startY-winY,width,height,false,true)
    end
    -- Draw selected notes
    local notes=input_sequence:gmatch("([^-]+)")
    local string_idx=selected_string-1
    for fret in notes do
        local fret_num=tonumber(fret)
        if fret_num then
            local note_x
            if fret_num == 0 then
                note_x = startX  -- 0-fret on the nut
            else
                note_x = startX+(fret_num*fret_spacing)-(fret_spacing/2)  -- Other frets between lines
            end
            local note_y=startY+(string_idx*string_spacing)
            r.ImGui_DrawList_AddCircleFilled(draw_list,note_x,note_y,6,0xFF0000FF)
        end
    end
end

function IsBarre(chord_shape)
    local frets = {}
    local fingers = chord_fingers[chord_shape]
    if fingers then
    -- r.ShowConsoleMsg("Fingers: " .. table.concat(fingers, ", ") .. "\n")
    else
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
    local draw_list=r.ImGui_GetWindowDrawList(ctx)
    local winX,winY=r.ImGui_GetWindowPos(ctx)
    startX=winX+startX+15
    startY=winY+startY
    local num_strings=6
    local num_frets=12
    local string_spacing=width/(num_strings-1)
    height = height * 2.4
    local fret_spacing=height/num_frets
    -- Fret markers (dots)
    local fret_markers = {3,5,7,9,12}
    DrawFretMarkers(draw_list, startX, startY, fret_spacing, "vertical")
    -- Draw strings
    for i=0,num_strings-1 do
        local x=startX+(i*string_spacing)
        r.ImGui_DrawList_AddLine(draw_list,x,startY,x,startY+height,0xFFFFFFFF)
        local note_name=GetNoteName(base_notes[num_strings-i])
        r.ImGui_DrawList_AddText(draw_list,x-5,startY-20,0xFFFFFFFF,note_name)
    end
    -- Draw frets and numbers
    for i=0,num_frets do
        local y=startY+(i*fret_spacing) 
        if i == 0 then
            r.ImGui_DrawList_AddLine(
                draw_list,
                startX,
                y,
                startX+width,
                y,
                0xFFFFFFFF,
                4.0
            )
            r.ImGui_DrawList_AddText(draw_list,startX-20,y-8,0xFFFFFFFF,"0")
        else
            r.ImGui_DrawList_AddLine(
                draw_list,
                startX,
                y,
                startX+width,
                y,
                0xFFFFFFFF,
                1.0
            )
            r.ImGui_DrawList_AddText(draw_list,startX-20,y-8,0xFFFFFFFF,tostring(i))
        end
    end

    -- Draw empty circles
    for string_num=0,num_strings-1 do
        local x=startX+(string_num*string_spacing)
        for fret=0,num_frets do
            local y=startY+(fret*fret_spacing)
            if fret > 0 then
                y = y-(fret_spacing/2)
            end
            r.ImGui_DrawList_AddCircle(draw_list,x,y,5,0x80808080)
        end
    end

    if r.ImGui_IsMouseClicked(ctx,0) then
        HandleFretboardClick(ctx,startX-winX,startY-winY,width,height,true,false)
    elseif r.ImGui_IsMouseClicked(ctx,1) then
        HandleFretboardClick(ctx,startX-winX,startY-winY,width,height,true,true)
    end

    -- Get chord name and fingers
    local chord_shape = input_chord
    local chord_name = DetermineChordName(chord_shape)
    local fingers = chord_fingers[chord_shape] or DetermineFingerPositions(chord_shape)
    local finger_idx = 1

    -- Draw selected positions with finger colors
    for string_num=1,num_strings do
        local fret=string.match(input_chord,string.rep("%S+%s",string_num-1)..("(%S+)"))
        if fret and fret~="X" then
            local x=startX+(string_num-1)*string_spacing
            if fret == "0" then
                -- Open string
                r.ImGui_DrawList_AddCircleFilled(draw_list,x,startY,6,0xFFFFFFFF)
                r.ImGui_DrawList_AddCircle(draw_list,x,startY,6,0x000000FF)
            else
                local fret_num=tonumber(fret)
                if fret_num then
                    local y=startY+(fret_num*fret_spacing)-(fret_spacing/2)
                    local finger = fingers[finger_idx]
                    local color = finger_colors[finger] or 0xFFFFFFFF
                    -- Finger position with color
                    r.ImGui_DrawList_AddCircleFilled(draw_list,x,y,6,color)
                    r.ImGui_DrawList_AddCircle(draw_list,x,y,6,0xFFFFFFFF)
                    -- Draw finger number
                    if finger then
                        r.ImGui_DrawList_AddText(draw_list,x-3,y-6,0x000000FF,tostring(finger))
                    end
                end
            end
            finger_idx = finger_idx + 1
        elseif fret == "X" then
            local x=startX+(string_num-1)*string_spacing
            local size = 4
            r.ImGui_DrawList_AddLine(draw_list,x-size,startY-size,x+size,startY+size,0xFFFFFFFF)
            r.ImGui_DrawList_AddLine(draw_list,x-size,startY+size,x+size,startY-size,0xFFFFFFFF)
            finger_idx = finger_idx + 1
        end
    end
    if IsBarre(chord_shape) then
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
            local start_x = startX + (start_string-1)*string_spacing
            local end_x = startX + (end_string-1)*string_spacing
            local y = startY + (barre_fret*fret_spacing) - (fret_spacing/2)
            local control_y = y - 10  -- Arc height
            r.ImGui_DrawList_AddBezierCubic(
                draw_list,
                start_x, y,           -- start point
                start_x, control_y,   -- first control point
                end_x, control_y,     -- second control point
                end_x, y,             -- end point
                0xFFFFFFFF,          -- color (white)
                2.0                  -- line thickness
            )
        end
    end
    DrawFingerLegend(ctx, startX + width + 50, startY + 30)
    if chord_name and chord_name ~= "(?)" then
        local legend_height = 25 * 4
        local chord_info_y = startY + 20 + legend_height + 20
        local info_x = startX + width + 50
        local box_padding = 10
        local box_width = 120
        local box_height = 50
        local is_barre = IsBarre(chord_shape)
        local chord_type = is_barre and "Barre Chord: " or "Chord: "
        
        r.ImGui_DrawList_AddRectFilled(draw_list, 
            info_x - box_padding,
            chord_info_y - box_padding,
            info_x + box_width,
            chord_info_y + box_height,
            0x1A1A1AFF)
            
        r.ImGui_DrawList_AddRect(draw_list,
            info_x - box_padding,
            chord_info_y - box_padding,
            info_x + box_width,
            chord_info_y + box_height,
            0x333333FF)
        
        r.ImGui_DrawList_AddText(draw_list, info_x, chord_info_y, 0xFFFFFFFF, chord_type)
        r.ImGui_DrawList_AddText(draw_list, info_x, chord_info_y + 20, 0xFFFFFFFF, chord_name)
    end
end



function MainLoop()
    local window_flags = r.ImGui_WindowFlags_NoTitleBar()|
                        r.ImGui_WindowFlags_NoResize()|
                        r.ImGui_WindowFlags_NoScrollbar()|
                        r.ImGui_WindowFlags_AlwaysAutoResize()
    r.ImGui_PushStyleVar(ctx,r.ImGui_StyleVar_WindowRounding(),12.0)
    local min_width = 360  
    if show_sequence then
        min_width = math.max(min_width, 360)
    end
    if show_chord then
        min_width = math.max(min_width, 360)
    end
    r.ImGui_SetNextWindowSizeConstraints(ctx, min_width, 0, min_width, 2000)
    local visible,open=r.ImGui_Begin(ctx,'Guitar MIDI Input',true,window_flags)

    if visible then
        r.ImGui_PushFont(ctx,font)
        r.ImGui_PushStyleColor(ctx,r.ImGui_Col_WindowBg(),0x000000FF)
        r.ImGui_PushStyleColor(ctx,r.ImGui_Col_Button(),0x1A1A1AFF)
        r.ImGui_PushStyleColor(ctx,r.ImGui_Col_ButtonHovered(),0x333333FF)
        r.ImGui_PushStyleColor(ctx,r.ImGui_Col_ButtonActive(),0x404040FF)
        r.ImGui_PushStyleColor(ctx,r.ImGui_Col_FrameBg(),0x1A1A1AFF)
        r.ImGui_PushStyleColor(ctx,r.ImGui_Col_FrameBgHovered(),0x333333FF)
        r.ImGui_PushStyleColor(ctx,r.ImGui_Col_FrameBgActive(),0x404040FF)
        r.ImGui_PushStyleVar(ctx,r.ImGui_StyleVar_FrameRounding(),6.0)
        r.ImGui_Text(ctx,"TK GTR2MIDI")
        r.ImGui_SameLine(ctx)
        r.ImGui_Dummy(ctx,20,0) 
        r.ImGui_SameLine(ctx)
        _,show_sequence = r.ImGui_Checkbox(ctx,"Sequence",show_sequence)
        r.ImGui_SameLine(ctx)
        _,show_chord = r.ImGui_Checkbox(ctx,"Chord",show_chord)

        r.ImGui_Separator(ctx)
        r.ImGui_Text(ctx,"Duration:")
        r.ImGui_SameLine(ctx)
        local active_color=0xFF0000FF
        if selected_duration=="1"then
            r.ImGui_PushStyleColor(ctx,r.ImGui_Col_Button(),active_color)
            if r.ImGui_Button(ctx,"1/1")then selected_duration="1"end
            r.ImGui_PopStyleColor(ctx)
        else
            if r.ImGui_Button(ctx,"1/1")then selected_duration="1"end
        end
        r.ImGui_SameLine(ctx)
        if selected_duration=="2"then
            r.ImGui_PushStyleColor(ctx,r.ImGui_Col_Button(),active_color)
            if r.ImGui_Button(ctx,"1/2")then selected_duration="2"end
            r.ImGui_PopStyleColor(ctx)
        else
            if r.ImGui_Button(ctx,"1/2")then selected_duration="2"end
        end
        r.ImGui_SameLine(ctx)
        if selected_duration=="4"then
            r.ImGui_PushStyleColor(ctx,r.ImGui_Col_Button(),active_color)
            if r.ImGui_Button(ctx,"1/4")then selected_duration="4"end
            r.ImGui_PopStyleColor(ctx)
        else
            if r.ImGui_Button(ctx,"1/4")then selected_duration="4"end
        end
        r.ImGui_SameLine(ctx)
        if selected_duration=="8"then
            r.ImGui_PushStyleColor(ctx,r.ImGui_Col_Button(),active_color)
            if r.ImGui_Button(ctx,"1/8")then selected_duration="8"end
            r.ImGui_PopStyleColor(ctx)
        else
            if r.ImGui_Button(ctx,"1/8")then selected_duration="8"end
        end
        r.ImGui_SameLine(ctx)
        if selected_duration=="16"then
            r.ImGui_PushStyleColor(ctx,r.ImGui_Col_Button(),active_color)
            if r.ImGui_Button(ctx,"1/16")then selected_duration="16"end
            r.ImGui_PopStyleColor(ctx)
        else
            if r.ImGui_Button(ctx,"1/16")then selected_duration="16"end
        end
        r.ImGui_SameLine(ctx)
        r.ImGui_Text(ctx,"Transpose:")
        r.ImGui_SameLine(ctx)
        if r.ImGui_Button(ctx,"-1")then
            local new_seq={}
            for note in input_sequence:gmatch("([^-]+)")do
                local n=tonumber(note)
                if n>0 then
                    table.insert(new_seq,tostring(n-1))
                else
                    table.insert(new_seq,"0")
                end
            end
            input_sequence=table.concat(new_seq,"-")
            local new_chord={}
            for fret in input_chord:gmatch("%S+")do
                if fret~="X"then
                    local n=tonumber(fret)
                    if n>0 then
                        table.insert(new_chord,tostring(n-1))
                    else
                        table.insert(new_chord,"0")
                    end
                else
                    table.insert(new_chord,"X")
                end
            end
            input_chord=table.concat(new_chord," ")
        end
        r.ImGui_SameLine(ctx)
        if r.ImGui_Button(ctx,"+1")then
            local new_seq={}
            for note in input_sequence:gmatch("([^-]+)")do
                table.insert(new_seq,tostring(tonumber(note)+1))
            end
            input_sequence=table.concat(new_seq,"-")
            local new_chord={}
            for fret in input_chord:gmatch("%S+")do
                if fret~="X"then
                    table.insert(new_chord,tostring(tonumber(fret)+1))
                else
                    table.insert(new_chord,"X")
                end
            end
            input_chord=table.concat(new_chord," ")
        end
        r.ImGui_Spacing(ctx)
        r.ImGui_Text(ctx,"Tuning:")
        r.ImGui_SameLine(ctx)
        if r.ImGui_BeginCombo(ctx,"##tuning",selected_tuning)then
            for tuning_name,_ in pairs(tunings)do
                if r.ImGui_Selectable(ctx,tuning_name,selected_tuning==tuning_name)then
                    selected_tuning=tuning_name
                    base_notes=tunings[tuning_name]
                end
            end
            r.ImGui_EndCombo(ctx)
        end
        r.ImGui_Spacing(ctx)
        r.ImGui_Separator(ctx)
        r.ImGui_Spacing(ctx)
        if show_sequence then
            r.ImGui_Text(ctx,"Enter sequence (format: 1-2-6-9-0-3):")
            _,input_sequence=r.ImGui_InputText(ctx,"##sequence",input_sequence)
            r.ImGui_SameLine(ctx)
            if r.ImGui_Button(ctx, "X##clearseq") then
                input_sequence = ""
            end
            r.ImGui_SameLine(ctx)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x0099DDFF)        -- Lichtblauw voor normale staat
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0x00BBFFFF) -- Iets lichtere tint voor hover
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0x0077AAFF)
            if r.ImGui_Button(ctx,"Insert Sequence")then
                local item,take,note_length=CreateMIDIItem()
                if take then InsertSequence(take,input_sequence,note_length)end
            end
            r.ImGui_PopStyleColor(ctx, 3)
            DrawFretboard(ctx,30,r.ImGui_GetCursorPosY(ctx)+10,300,120)
            r.ImGui_Dummy(ctx,0,150)
            r.ImGui_Separator(ctx)
        end  
        if show_chord then    
            r.ImGui_Spacing(ctx)
            r.ImGui_Text(ctx,"Enter chord (format: 1 3 3 2 1 1 or X X X 2 1 1):")
            local _, new_input = r.ImGui_InputText(ctx,"##chord",input_chord)
            input_chord = FilterChordInput(new_input)
            r.ImGui_SameLine(ctx)
            if r.ImGui_Button(ctx, "X##clearchord") then
                input_chord = ""
            end
            r.ImGui_SameLine(ctx)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x0099DDFF)        
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0x00BBFFFF) 
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0x0077AAFF)  
            if r.ImGui_Button(ctx,"Insert Chord") then
                local frets = {}
                for fret in input_chord:gmatch("%S+") do
                    table.insert(frets, fret)
                end
                if #frets == 6 then
                    local item, take, note_length = CreateMIDIItem()
                    if take then
                        InsertChord(take, frets, note_length)
                    end
                else
                    r.ImGui_TextColored(ctx, 0xFF0000FF, "Input must contain exactly 6 positions")
                end
            end
            r.ImGui_PopStyleColor(ctx, 3)
            DrawChordboard(ctx,10,r.ImGui_GetCursorPosY(ctx)+20,120,120)
            r.ImGui_Dummy(ctx,0,325)
        end
        r.ImGui_PopStyleVar(ctx,2)
        r.ImGui_PopStyleColor(ctx,7)
        r.ImGui_PopFont(ctx)
        r.ImGui_End(ctx)
    end
    if open then r.defer(MainLoop) end
end
r.defer(MainLoop)

