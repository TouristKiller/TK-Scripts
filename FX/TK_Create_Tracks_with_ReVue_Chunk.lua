-- @description TK Create New Track(s) with ReVue VU Meter (MCP Embedded) - Chunk Version
-- @author TouristKiller
-- @version 1.0
-- @changelog:
--   + Initial release - Chunk-based embedding (faster and more reliable)
-- @provides [main] .
-- @about
--   Creates new track(s) with the ReVue VU Meter (by Blenheim Sound) embedded in the MCP.
--   Uses chunk manipulation for faster and more reliable embedding.
--   Shows an input dialog to specify the number of tracks (default 1).
--   Can be added to track context menu for quick access.

local r = reaper

local FX_VARIANTS = {
    "VST3: reVUe (Blenheim Sound)",
    "CLAP: reVUe (Blenheim Sound)",
    "VST: reVUe (Blenheim Sound)"
}

local function GetReVueFXName()
    for _, name in ipairs(FX_VARIANTS) do
        local retval = r.TrackFX_AddByName(r.GetMasterTrack(0), name, false, 0)
        if retval >= 0 then
            return name
        end
    end
    return FX_VARIANTS[1]
end

local function EmbedFXToMCP(track, fx_index)
    local fx_guid = r.TrackFX_GetFXGUID(track, fx_index)
    if not fx_guid then return false end
    
    local _, chunk = r.GetTrackStateChunk(track, "", false)
    
    local guid_clean = fx_guid:gsub("[{}]", "")
    local guid_pattern = guid_clean:gsub("%-", "%%-")
    
    local fxid_pos = chunk:find("FXID {" .. guid_pattern .. "}")
    if not fxid_pos then
        fxid_pos = chunk:find("FXID " .. guid_pattern)
    end
    
    if not fxid_pos then
        return false
    end
    
    local wak_pos = chunk:find("\nWAK ", fxid_pos)
    local fx_end_pos = chunk:find("\n>", fxid_pos)
    
    if not wak_pos or (fx_end_pos and wak_pos > fx_end_pos) then
        return false
    end
    
    local wak_line_end = chunk:find("\n", wak_pos + 1)
    local wak_line = chunk:sub(wak_pos + 1, wak_line_end - 1)
    
    local wak_val1, wak_val2 = wak_line:match("WAK (%d+) (%d+)")
    if wak_val1 then
        local new_wak_line = "WAK " .. wak_val1 .. " 2"
        chunk = chunk:sub(1, wak_pos) .. new_wak_line .. chunk:sub(wak_line_end)
        r.SetTrackStateChunk(track, chunk, false)
        return true
    end
    
    return false
end

local function Main()
    local retval, input = r.GetUserInputs("New Tracks with ReVue", 1, "Number of tracks:,extrawidth=50", "1")
    
    if not retval then
        return
    end
    
    local track_count = tonumber(input)
    if not track_count or track_count < 1 then
        r.ShowMessageBox("Please enter a valid number (minimum 1).", "Error", 0)
        return
    end
    
    track_count = math.floor(track_count)
    
    local fx_name = GetReVueFXName()
    
    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)
    
    local insert_index = r.CountTracks(0)
    local sel_track = r.GetSelectedTrack(0, 0)
    if sel_track then
        insert_index = r.GetMediaTrackInfo_Value(sel_track, "IP_TRACKNUMBER")
    end
    
    for i = 1, track_count do
        r.InsertTrackAtIndex(insert_index + i - 1, true)
        local track = r.GetTrack(0, insert_index + i - 1)
        if track then
            r.GetSetMediaTrackInfo_String(track, "P_NAME", "ReVue " .. i, true)
            
            local fx_cnt = r.TrackFX_GetCount(track)
            local fx_index = r.TrackFX_AddByName(track, fx_name, false, -1000 - fx_cnt)
            
            if fx_index >= 0 then
                EmbedFXToMCP(track, fx_index)
                
                local current_scale = r.GetMediaTrackInfo_Value(track, "F_MCP_FXSEND_SCALE")
                if current_scale < 0.5 then
                    r.SetMediaTrackInfo_Value(track, "F_MCP_FXSEND_SCALE", 0.7)
                end
            end
        end
    end
    
    r.PreventUIRefresh(-1)
    r.TrackList_AdjustWindows(false)
    r.UpdateArrange()
    
    r.Undo_EndBlock("Create " .. track_count .. " track(s) with ReVue", -1)
end

Main()
