local r = reaper
local command_id = '_RS231d1c7ada18452cc5a01af085103cf4e269fbf4'
local last_track_guid = nil

function GetTrackSettings(track)
    local guid = r.GetTrackGUID(track)
    local _, shape = r.GetSetMediaTrackInfo_String(track, "P_EXT:TKSHAPE", "", false)
    local _, view = r.GetSetMediaTrackInfo_String(track, "P_EXT:TKVIEW", "", false)
    return shape, view
end

function ApplyTrackSettings()
    local editor = r.MIDIEditor_GetActive()
    if not editor then return end
    
    local take = r.MIDIEditor_GetTake(editor)
    if not take then return end
    
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

function Main()
    if r.GetToggleCommandState(r.NamedCommandLookup(command_id)) == 1 then
        ApplyTrackSettings()
        r.defer(Main)
    else
        r.defer(function() end)
    end
end

function ToggleScript()
    local current_state = r.GetToggleCommandState(r.NamedCommandLookup(command_id))
    local new_state = current_state == 0 and 1 or 0
    r.SetToggleCommandState(0, r.NamedCommandLookup(command_id), new_state)
    r.RefreshToolbar2(0, r.NamedCommandLookup(command_id))
    
    if new_state == 1 then
        Main()
    end
end

ToggleScript()
