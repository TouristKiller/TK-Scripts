-- @description TK Add ReVue VU Meter to Selected Tracks (MCP Embedded) - Chunk Version
-- @author TouristKiller
-- @version 1.0
-- @changelog:
--   + Initial release - Chunk-based embedding (faster and more reliable)
-- @provides [main] .
-- @about
--   Adds the ReVue VU Meter (by Blenheim Sound) to selected tracks and displays it embedded in the MCP.
--   Uses chunk manipulation for faster and more reliable embedding.
--   Works with single or multiple selected tracks.
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
    local track_count = r.CountSelectedTracks(0)
    
    if track_count == 0 then
        r.ShowMessageBox("Please select one or more tracks first.", "Add ReVue", 0)
        return
    end
    
    local fx_name = GetReVueFXName()
    
    local tracks = {}
    for i = 0, track_count - 1 do
        local track = r.GetSelectedTrack(0, i)
        if track then
            table.insert(tracks, track)
        end
    end
    
    r.Undo_BeginBlock()
    r.PreventUIRefresh(1)
    
    for _, track in ipairs(tracks) do
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
    
    r.PreventUIRefresh(-1)
    r.TrackList_AdjustWindows(false)
    r.UpdateArrange()
    
    r.Undo_EndBlock("Add ReVue to " .. #tracks .. " track(s)", -1)
end

Main()
