-- @description Track Icon Manager for TK_Trackname_in_Arrange
-- @author TouristKiller
-- @version 1.0.0

local r = reaper

local TrackIconManager = {
    track_icons = {},  -- Cache: track GUID -> icon path
    icon_images = {},  -- Cache: icon path -> ImGui image object
}

-- Get unique track identifier
function TrackIconManager.GetTrackGUID(track)
    if not track or not r.ValidatePtr(track, "MediaTrack*") then
        return nil
    end
    return r.GetTrackGUID(track)
end

-- Save track icon assignment
function TrackIconManager.SetTrackIcon(track, icon_path)
    local guid = TrackIconManager.GetTrackGUID(track)
    if not guid then return false end
    
    if icon_path and icon_path ~= "" then
        TrackIconManager.track_icons[guid] = icon_path
        
        -- Also save to track's extended state for persistence
        r.GetSetMediaTrackInfo_String(track, "P_EXT:TK_ICON", icon_path, true)
    else
        -- Clear icon
        TrackIconManager.track_icons[guid] = nil
        r.GetSetMediaTrackInfo_String(track, "P_EXT:TK_ICON", "", true)
    end
    
    return true
end

-- Get track icon path
function TrackIconManager.GetTrackIcon(track)
    local guid = TrackIconManager.GetTrackGUID(track)
    if not guid then return nil end
    
    -- Check cache first
    if TrackIconManager.track_icons[guid] then
        return TrackIconManager.track_icons[guid]
    end
    
    -- Load from track's extended state
    local retval, icon_path = r.GetSetMediaTrackInfo_String(track, "P_EXT:TK_ICON", "", false)
    if retval and icon_path ~= "" then
        TrackIconManager.track_icons[guid] = icon_path
        return icon_path
    end
    
    return nil
end

-- Clear track icon
function TrackIconManager.ClearTrackIcon(track)
    return TrackIconManager.SetTrackIcon(track, nil)
end

-- Load or get cached icon image
function TrackIconManager.GetIconImage(icon_path)
    if not icon_path or icon_path == "" then
        return nil
    end
    
    -- Check if already loaded
    if TrackIconManager.icon_images[icon_path] then
        if r.ImGui_ValidatePtr(TrackIconManager.icon_images[icon_path], 'ImGui_Image*') then
            return TrackIconManager.icon_images[icon_path]
        else
            -- Invalid, remove from cache
            TrackIconManager.icon_images[icon_path] = nil
        end
    end
    
    -- Try to load image
    if r.file_exists(icon_path) then
        local ok, img = pcall(r.ImGui_CreateImage, icon_path)
        if ok and img then
            TrackIconManager.icon_images[icon_path] = img
            return img
        end
    end
    
    return nil
end

-- Refresh all track icons from project
function TrackIconManager.RefreshAllIcons()
    TrackIconManager.track_icons = {}
    
    local track_count = r.CountTracks(0)
    for i = 0, track_count - 1 do
        local track = r.GetTrack(0, i)
        if track then
            local guid = TrackIconManager.GetTrackGUID(track)
            local retval, icon_path = r.GetSetMediaTrackInfo_String(track, "P_EXT:TK_ICON", "", false)
            if retval and icon_path ~= "" then
                TrackIconManager.track_icons[guid] = icon_path
            end
        end
    end
end

-- Clean up unused images from cache
function TrackIconManager.CleanupImageCache()
    local used_icons = {}
    
    -- Collect all currently used icons
    for _, icon_path in pairs(TrackIconManager.track_icons) do
        used_icons[icon_path] = true
    end
    
    -- Remove unused images from cache
    for path, img in pairs(TrackIconManager.icon_images) do
        if not used_icons[path] then
            TrackIconManager.icon_images[path] = nil
        end
    end
end

-- Check if track has icon
function TrackIconManager.HasIcon(track)
    local icon_path = TrackIconManager.GetTrackIcon(track)
    return icon_path ~= nil and icon_path ~= ""
end

-- Get all tracks with icons
function TrackIconManager.GetTracksWithIcons()
    local tracks = {}
    local track_count = r.CountTracks(0)
    
    for i = 0, track_count - 1 do
        local track = r.GetTrack(0, i)
        if track and TrackIconManager.HasIcon(track) then
            table.insert(tracks, track)
        end
    end
    
    return tracks
end

-- Copy icon from one track to another
function TrackIconManager.CopyIcon(source_track, target_track)
    local icon_path = TrackIconManager.GetTrackIcon(source_track)
    if icon_path then
        return TrackIconManager.SetTrackIcon(target_track, icon_path)
    end
    return false
end

return TrackIconManager
