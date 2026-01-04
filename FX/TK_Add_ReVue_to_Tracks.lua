-- @description TK Add ReVue VU Meter to Selected Tracks (MCP Embedded)
-- @author TouristKiller
-- @version 1.1
-- @changelog:
--   + v1.1: Improved timing with extra defer cycles and verification for reliable MCP embedding
--   + Initial release
-- @provides [main] .
-- @about
--   Adds the ReVue VU Meter (by Blenheim Sound) to selected tracks and displays it embedded in the MCP.
--   Works with single or multiple selected tracks.
--   Can be added to track context menu for quick access.

local r = reaper

local FX_VARIANTS = {
    "VST3: reVUe (Blenheim Sound)",
    "CLAP: reVUe (Blenheim Sound)",
    "VST: reVUe (Blenheim Sound)"
}

local state = {
    tracks = {},
    current_index = 0,
    fx_name = nil,
    step = 0,
    defer_count = 0,
    verify_count = 0
}

local DEFER_CYCLES = 5
local MAX_VERIFY_ATTEMPTS = 10

local function GetReVueFXName()
    for _, name in ipairs(FX_VARIANTS) do
        local retval = r.TrackFX_AddByName(r.GetMasterTrack(0), name, false, 0)
        if retval >= 0 then
            return name
        end
    end
    return FX_VARIANTS[1]
end

local function IsFXWindowOpen(track, fx_index)
    return r.TrackFX_GetOpen(track, fx_index)
end

local function IsFXEmbedded(track, fx_index)
    local flags = r.TrackFX_GetFloatingWindow(track, fx_index)
    local retval, buf = r.GetTrackStateChunk(track, "", false)
    if retval then
        local fx_guid = r.TrackFX_GetFXGUID(track, fx_index)
        if fx_guid then
            local pattern = fx_guid:gsub("([%-%.%+%[%]%(%)%$%^%%%?%*])", "%%%1")
            local search_start = buf:find(pattern)
            if search_start then
                local chunk_section = buf:sub(search_start, search_start + 500)
                if chunk_section:find("FLOAT_MCP") then
                    return true
                end
            end
        end
    end
    return false
end

local function ProcessNextTrack()
    if state.step == 99 then
        r.defer(function()
            r.defer(function()
                r.TrackList_AdjustWindows(false)
                r.UpdateArrange()
                r.Undo_EndBlock("Add ReVue to " .. #state.tracks .. " track(s)", -1)
            end)
        end)
        return
    end
    
    local track = state.tracks[state.current_index + 1]
    
    if state.step == 0 then
        local fx_count = r.TrackFX_GetCount(track)
        local fx_index = r.TrackFX_AddByName(track, state.fx_name, false, -1000 - fx_count)
        
        if fx_index >= 0 then
            state.fx_index = fx_index
            r.TrackFX_Show(track, fx_index, 3)
            state.step = 1
            state.defer_count = 0
            r.defer(ProcessNextTrack)
        else
            state.current_index = state.current_index + 1
            if state.current_index >= #state.tracks then
                state.step = 99
            end
            r.defer(ProcessNextTrack)
        end
        
    elseif state.step == 1 then
        state.defer_count = state.defer_count + 1
        if state.defer_count >= DEFER_CYCLES or IsFXWindowOpen(track, state.fx_index) then
            state.step = 2
            state.defer_count = 0
        end
        r.defer(ProcessNextTrack)
        
    elseif state.step == 2 then
        r.SetOnlyTrackSelected(track)
        r.TrackFX_Show(track, state.fx_index, 3)
        state.step = 3
        state.defer_count = 0
        r.defer(ProcessNextTrack)
        
    elseif state.step == 3 then
        state.defer_count = state.defer_count + 1
        if state.defer_count >= DEFER_CYCLES then
            r.Main_OnCommand(42372, 0)
            state.step = 4
            state.defer_count = 0
            state.verify_count = 0
        end
        r.defer(ProcessNextTrack)
        
    elseif state.step == 4 then
        state.defer_count = state.defer_count + 1
        if state.defer_count >= DEFER_CYCLES then
            state.step = 5
            state.defer_count = 0
        end
        r.defer(ProcessNextTrack)
        
    elseif state.step == 5 then
        local is_embedded = IsFXEmbedded(track, state.fx_index)
        
        if not is_embedded and state.verify_count < MAX_VERIFY_ATTEMPTS then
            state.verify_count = state.verify_count + 1
            r.TrackFX_Show(track, state.fx_index, 3)
            state.step = 3
            state.defer_count = 0
            r.defer(ProcessNextTrack)
            return
        end
        
        r.TrackFX_Show(track, state.fx_index, 2)
        
        local current_scale = r.GetMediaTrackInfo_Value(track, "F_MCP_FXSEND_SCALE")
        if current_scale < 0.5 then
            r.SetMediaTrackInfo_Value(track, "F_MCP_FXSEND_SCALE", 0.7)
        end
        
        state.current_index = state.current_index + 1
        
        if state.current_index >= #state.tracks then
            state.step = 99
        else
            state.step = 0
            state.verify_count = 0
        end
        r.defer(ProcessNextTrack)
    end
end

local function Main()
    local track_count = r.CountSelectedTracks(0)
    
    if track_count == 0 then
        r.ShowMessageBox("Please select one or more tracks first.", "Add ReVue", 0)
        return
    end
    
    state.fx_name = GetReVueFXName()
    state.tracks = {}
    state.current_index = 0
    state.step = 0
    
    for i = 0, track_count - 1 do
        local track = r.GetSelectedTrack(0, i)
        if track then
            table.insert(state.tracks, track)
        end
    end
    
    r.Undo_BeginBlock()
    ProcessNextTrack()
end

Main()
