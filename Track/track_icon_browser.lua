-- @description Track Icon Browser for TK_Trackname_in_Arrange
-- @author TouristKiller
-- @version 1.0.0

local r = reaper
local TrackIconBrowser = {
    show_window = false,
    selected_icon = nil,
    icons = {},
    grid_size = 40,
    columns = 10,
    image_cache = {}, 
    search_text = "", 
    filtered_icons = {},
    frame_counter = 0,
    icon_scale = 100,
    browse_mode = "icons",
    custom_image_folder = "",
    selected_image_path = nil,
    target_track = nil,
    track_icons_subfolders = {},
    track_icons_subfolder = "(root)",
}

function TrackIconBrowser.LoadLastImageFolder()
    if r.HasExtState("TK_TRACKNAME", "last_icon_folder") then
        TrackIconBrowser.custom_image_folder = r.GetExtState("TK_TRACKNAME", "last_icon_folder")
    end
end

function TrackIconBrowser.SaveLastImageFolder()
    if TrackIconBrowser.custom_image_folder ~= "" then
        r.SetExtState("TK_TRACKNAME", "last_icon_folder", TrackIconBrowser.custom_image_folder, true)
    end
end

function TrackIconBrowser.LoadIcons()
    if #TrackIconBrowser.icons > 0 then 
        return
    end
    
    if TrackIconBrowser.browse_mode == "images" then
        if TrackIconBrowser.custom_image_folder == "" then
            return
        end
        
        local idx = 0
        while true do
            local file = r.EnumerateFiles(TrackIconBrowser.custom_image_folder, idx)
            if not file then break end
            if file:match("%.png$") or file:match("%.jpg$") or file:match("%.jpeg$") or file:match("%.bmp$") then
                local icon = {
                    name = file,
                    path = TrackIconBrowser.custom_image_folder .. "/" .. file
                }
                table.insert(TrackIconBrowser.icons, icon)
            end
            idx = idx + 1
            
            if idx > 10000 then break end
        end
    elseif TrackIconBrowser.browse_mode == "track_icons" then
        local resource_path = r.GetResourcePath() .. "/Data/track_icons"
        
        if TrackIconBrowser.track_icons_subfolder and TrackIconBrowser.track_icons_subfolder ~= "(root)" then
            resource_path = resource_path .. "/" .. TrackIconBrowser.track_icons_subfolder
        end
        
        local idx = 0
        while true do
            local file = r.EnumerateFiles(resource_path, idx)
            if not file then break end
            if file:match("%.png$") or file:match("%.jpg$") or file:match("%.jpeg$") or file:match("%.bmp$") then
                local icon = {
                    name = file,
                    path = resource_path .. "/" .. file
                }
                table.insert(TrackIconBrowser.icons, icon)
            end
            idx = idx + 1
            if idx > 10000 then break end
        end
    else
        local resource_path = r.GetResourcePath() .. "/Data/toolbar_icons"
        
        if TrackIconBrowser.icon_scale == 150 then
            resource_path = resource_path .. "/150"
        elseif TrackIconBrowser.icon_scale == 200 then
            resource_path = resource_path .. "/200"
        end
        
        local idx = 0
        
        while true do
            local file = r.EnumerateFiles(resource_path, idx)
            if not file then break end
            if file:match("%.png$") then
                local icon = {
                    name = file,
                    path = resource_path .. "/" .. file
                }
                table.insert(TrackIconBrowser.icons, icon)
            end
            idx = idx + 1
            
            if idx > 10000 then break end
        end
    end
end

function TrackIconBrowser.ReloadIcons()
    TrackIconBrowser.icons = {}
    TrackIconBrowser.filtered_icons = {}
    TrackIconBrowser.image_cache = {}
    
    TrackIconBrowser.LoadIcons()
    TrackIconBrowser.FilterIcons()
end

function TrackIconBrowser.SetBrowseMode(mode, custom_folder)
    TrackIconBrowser.browse_mode = mode
    if mode == "images" then
        if custom_folder then
            TrackIconBrowser.custom_image_folder = custom_folder
            TrackIconBrowser.SaveLastImageFolder()
        elseif TrackIconBrowser.custom_image_folder == "" then
            TrackIconBrowser.LoadLastImageFolder()
        end
    end
    TrackIconBrowser.ReloadIcons()
end

function TrackIconBrowser.FilterIcons()
    TrackIconBrowser.filtered_icons = {}
    local search = TrackIconBrowser.search_text:lower()
    
    if search == "" then
        TrackIconBrowser.filtered_icons = TrackIconBrowser.icons
    else
        for _, icon in ipairs(TrackIconBrowser.icons) do
            if icon.name:lower():find(search) then
                table.insert(TrackIconBrowser.filtered_icons, icon)
            end
        end
    end
end

function TrackIconBrowser.LoadTrackIconsSubfolders()
    TrackIconBrowser.track_icons_subfolders = {"(root)"}
    local track_icons_path = r.GetResourcePath() .. "/Data/track_icons"
    
    local idx = 0
    while true do
        local subdir = r.EnumerateSubdirectories(track_icons_path, idx)
        if not subdir then break end
        if subdir ~= "." and subdir ~= ".." then
            table.insert(TrackIconBrowser.track_icons_subfolders, subdir)
        end
        idx = idx + 1
        if idx > 1000 then break end
    end
    
    table.sort(TrackIconBrowser.track_icons_subfolders, function(a, b)
        if a == "(root)" then return true end
        if b == "(root)" then return false end
        return a:lower() < b:lower()
    end)
end

function TrackIconBrowser.SetTrackIconsSubfolder(subfolder)
    TrackIconBrowser.track_icons_subfolder = subfolder
    TrackIconBrowser.ReloadIcons()
end

return TrackIconBrowser
