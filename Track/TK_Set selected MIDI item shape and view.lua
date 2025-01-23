-- @description TK_Set selected MIDI item shape and view
-- @author TouristKiller
-- @version 0.2.0
-- @changelog 
--[[
+ Removed toggle script. 
+ Start stop monitor from settings window
+ If set to menu butten it wil show if monitor is active or not
]]--
---------------------------------------------------------
local r                     = reaper
local ctx                   = r.ImGui_CreateContext('Note Shape Selector')
local font                  = r.ImGui_CreateFont('Arial', 14)
r.ImGui_Attach(ctx, font)


local monitor_active        = r.GetExtState("TK_MIDI_SHAPE_VIEW", "monitor_active") == "1"
local last_track_guid       = nil
local settings_visible      = true

local window_flags          = r.ImGui_WindowFlags_NoResize() | r.ImGui_WindowFlags_NoTitleBar()
local WINDOW_WIDTH          = 300
local column_width          = WINDOW_WIDTH / 2

local selected_shape        = 0
local selected_view         = 0
local selected_grid         = 0

local shapes                = {
    {name = "Normal", cmd = 40449},
    {name = "Diamond", cmd = 40450},
    {name = "Triangle", cmd = 40448}
}

local views                 = {
    {name = "Named Notes", cmd = 40043},
    {name = "Piano Roll", cmd = 40042},
    {name = "Notation", cmd = 40954}
}

local grid_options          = {
    {name = "1/32", cmd = 40190},
    {name = "1/16 T", cmd = 40191},
    {name = "1/16", cmd = 40192},
    {name = "1/8 T", cmd = 40193},
    {name = "1/8", cmd = 40197},
    {name = "1/4 T", cmd = 40199},
    {name = "1/4", cmd = 40201},
    {name = "1/2", cmd = 40203},
    {name = "1", cmd = 40204},
    {name = "2", cmd = 40205}
}

---------------------------------------------------------
function SetButtonState(set)
    local is_new_value, filename, sec, cmd, mode, resolution, val = r.get_action_context()
    r.SetToggleCommandState(sec, cmd, set or 0)
    r.RefreshToolbar2(sec, cmd)
end

local function SaveTrackView(track, cmd)
    local guid = r.GetTrackGUID(track)
    local key = "TrackView_" .. guid
    r.SetProjExtState(0, "ViewSettings", key, tostring(cmd))
end

local function ProcessItems(cmd, isView)
    local num_items = r.CountSelectedMediaItems(0)
    local selected_items = {}
    
    for i = 0, num_items-1 do
        selected_items[i] = r.GetSelectedMediaItem(0, i)
        local track = r.GetMediaItem_Track(selected_items[i])
        
        if isView then
            r.GetSetMediaTrackInfo_String(track, "P_EXT:TKVIEW", tostring(cmd), true)
        else
            r.GetSetMediaTrackInfo_String(track, "P_EXT:TKSHAPE", tostring(cmd), true)
        end
    end
    
    for i = 0, num_items-1 do
        r.SelectAllMediaItems(0, false)
        r.SetMediaItemSelected(selected_items[i], true)
        r.Main_OnCommand(40153, 0)
        r.MIDIEditor_LastFocused_OnCommand(cmd, 0)
    end
    
    r.SelectAllMediaItems(0, false)
    for i = 0, num_items-1 do
        r.SetMediaItemSelected(selected_items[i], true)
    end
    
    r.SetExtState("TKMonitor", "LastTrackGUID", "", false)
end

local function ResetAllSettings()
    local processed_tracks = {}
    
    local num_selected_tracks = r.CountSelectedTracks(0)
    if num_selected_tracks > 0 then
        for i = 0, num_selected_tracks-1 do
            local track = r.GetSelectedTrack(0, i)
            local track_guid = r.GetTrackGUID(track)
            processed_tracks[track_guid] = track
        end
    end
    
    if next(processed_tracks) == nil then
        local num_items = r.CountSelectedMediaItems(0)
        for i = 0, num_items-1 do
            local item = r.GetSelectedMediaItem(0, i)
            local track = r.GetMediaItem_Track(item)
            local track_guid = r.GetTrackGUID(track)
            processed_tracks[track_guid] = track
        end
    end
    
    for guid, track in pairs(processed_tracks) do
        r.GetSetMediaTrackInfo_String(track, "P_EXT:TKVIEW", "40042", true)
        r.GetSetMediaTrackInfo_String(track, "P_EXT:TKSHAPE", "40449", true)
        
        local item_count = r.GetTrackNumMediaItems(track)
        for i = 0, item_count-1 do
            local item = r.GetTrackMediaItem(track, i)
            if r.GetMediaItemInfo_Value(item, "B_MUTE") == 0 then
                r.SetMediaItemSelected(item, true)
            end
        end
    end
    
    ProcessItems(40042, true)   -- Piano Roll
    ProcessItems(40449, false)  -- Normal shape
    ProcessItems(40192, false)  -- 1/16 grid
    
    selected_shape = 0
    selected_view = 1
    selected_grid = 2
end

function GetTrackSettings(track)
    local guid = r.GetTrackGUID(track)
    local _, shape = r.GetSetMediaTrackInfo_String(track, "P_EXT:TKSHAPE", "", false)
    local _, view = r.GetSetMediaTrackInfo_String(track, "P_EXT:TKVIEW", "", false)
    return shape, view
end


function MonitorSettings()
    if not monitor_active then return end
    
    local editor = r.MIDIEditor_GetActive()
    if editor then
        local take = r.MIDIEditor_GetTake(editor)
        if take then
            local item = r.GetMediaItemTake_Item(take)
            local track = r.GetMediaItem_Track(item)
            local current_guid = r.GetTrackGUID(track)
            
            if current_guid ~= last_track_guid then
                local shape, view = GetTrackSettings(track)
                if shape ~= "" then
                    r.MIDIEditor_LastFocused_OnCommand(tonumber(shape), 0)
                end
                if view ~= "" then
                    r.MIDIEditor_LastFocused_OnCommand(tonumber(view), 0)
                end
                last_track_guid = current_guid
            end
        end
    end
    
    r.defer(MonitorSettings)
end
---------------------------------------------------------
local function loop()
    if settings_visible then
        r.ImGui_PushFont(ctx, font)
        
        -- Style setup
        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowRounding(), 12.0)
        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), 6.0)
        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_PopupRounding(), 6.0)
        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_GrabRounding(), 12.0)
        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_GrabMinSize(), 8.0)

        -- Colors setup
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_WindowBg(), 0x111111D9)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBg(), 0x333333FF)        
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgHovered(), 0x444444FF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_FrameBgActive(), 0x555555FF)  
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrab(), 0x999999FF)     
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_SliderGrabActive(), 0xAAAAAAFF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_CheckMark(), 0x999999FF)      
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x333333FF)         
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0x444444FF)  
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0x555555FF)        

        local visible, open = r.ImGui_Begin(ctx, 'Note Shape Selector', true, window_flags)

        if visible then
            r.ImGui_SetWindowSize(ctx, WINDOW_WIDTH, 0, r.ImGui_Cond_Always())

            -- Header
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0xFF0000FF)
            r.ImGui_Text(ctx, "TK")
            r.ImGui_PopStyleColor(ctx)
            r.ImGui_SameLine(ctx)
            r.ImGui_Text(ctx, "MIDI ITEM SHAPE AND VIEW")
            r.ImGui_Separator(ctx)

            -- Close button
            r.ImGui_SameLine(ctx)
            r.ImGui_SetCursorPosX(ctx, WINDOW_WIDTH - 25)
            r.ImGui_SetCursorPosY(ctx, 6)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0xFF0000FF)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0xFF3333FF)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0xFF6666FF)
            
            if r.ImGui_Button(ctx, "##close", 14, 14) then
                settings_visible = false
            end
            r.ImGui_PopStyleColor(ctx, 3)   
---------------------------------------------------------
        r.ImGui_Text(ctx, 'Select shape (per item):')
        r.ImGui_SameLine(ctx, column_width)
        r.ImGui_Text(ctx, 'Select view (per track):')
        for i = 1, math.max(#shapes, #views) do

            if i <= #shapes then
                if r.ImGui_RadioButton(ctx, shapes[i].name, selected_shape == i-1) then
                    selected_shape = i-1
                end
            end      

            if i <= #views then
                r.ImGui_SameLine(ctx, column_width)
                if r.ImGui_RadioButton(ctx, views[i].name, selected_view == i-1) then
                    selected_view = i-1
                end
            end
        end
        
        if r.ImGui_Button(ctx, 'Apply Shape', column_width-15) then
            ProcessItems(shapes[selected_shape + 1].cmd, false)
        end
        r.ImGui_SameLine(ctx)
        if r.ImGui_Button(ctx, 'Apply View', column_width-15) then
            ProcessItems(views[selected_view + 1].cmd, true)
        end
        
        r.ImGui_Text(ctx, '\nSelect grid (per track):')
        for i = 1, 5 do
            if r.ImGui_RadioButton(ctx, grid_options[i].name, selected_grid == i-1) then
                selected_grid = i-1
            end
            r.ImGui_SameLine(ctx, column_width)
            if r.ImGui_RadioButton(ctx, grid_options[i+5].name, selected_grid == (i+5)-1) then
                selected_grid = (i+5)-1
            end
        end

        if r.ImGui_Button(ctx, 'Apply Grid', column_width-15) then
            ProcessItems(grid_options[selected_grid + 1].cmd, false)
        end
        r.ImGui_SameLine(ctx, column_width)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0xFF8C00FF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0xFF9933FF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0xFFAD66FF)
        if r.ImGui_Button(ctx, 'Reset All (per track)', column_width-15) then
            ResetAllSettings()
        end
        r.ImGui_PopStyleColor(ctx, 3)
        r.ImGui_Separator(ctx)

        if r.ImGui_Button(ctx, monitor_active and 'Stop Monitor' or 'Start Monitor', WINDOW_WIDTH-15) then
            monitor_active = not monitor_active
            r.SetExtState("TK_MIDI_SHAPE_VIEW", "monitor_active", monitor_active and "1" or "0", true)
            SetButtonState(monitor_active and 1 or 0)
            if monitor_active then
                MonitorSettings()
            end
        end
        
        r.ImGui_End(ctx)
    end

    r.ImGui_PopStyleColor(ctx, 10)
    r.ImGui_PopStyleVar(ctx, 5)    
    r.ImGui_PopFont(ctx)
end

if monitor_active or settings_visible then
    r.defer(loop)
else
    SetButtonState(0)
end

end

-- Start het script
monitor_active = r.GetExtState("TK_MIDI_SHAPE_VIEW", "monitor_active") == "1"
settings_visible = true
SetButtonState(monitor_active and 1 or 0)

if monitor_active then
    MonitorSettings()
end

-- Cleanup bij afsluiten
r.atexit(function()
    SetButtonState(0)
end)

r.defer(loop)


