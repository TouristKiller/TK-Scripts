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
    target_track = nil,  -- Track to assign icon to
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

function TrackIconBrowser.Show(ctx)
    if not TrackIconBrowser.show_window then return end
    
    if TrackIconBrowser.browse_mode == "images" and TrackIconBrowser.custom_image_folder == "" then
        TrackIconBrowser.LoadLastImageFolder()
    end
    
    if #TrackIconBrowser.icons == 0 then
        TrackIconBrowser.LoadIcons()
        TrackIconBrowser.FilterIcons()
    end
    
    -- Fixed window size
    local window_flags = r.ImGui_WindowFlags_NoResize() | r.ImGui_WindowFlags_NoCollapse()
    local width = 620
    local height = 520
    
    r.ImGui_SetNextWindowSize(ctx, width, height, r.ImGui_Cond_Always())
    
    local visible, open = r.ImGui_Begin(ctx, "Track Icon Browser", true, window_flags)
    
    if visible then
        r.ImGui_Text(ctx, "Select Icon for Track")
        
        r.ImGui_Separator(ctx)
        
        -- Mode selection
        r.ImGui_Text(ctx, "Mode:")
        r.ImGui_SameLine(ctx)
        
        if r.ImGui_RadioButton(ctx, "REAPER Icons", TrackIconBrowser.browse_mode == "icons") then
            if TrackIconBrowser.browse_mode ~= "icons" then
                TrackIconBrowser.SetBrowseMode("icons")
            end
        end
        
        r.ImGui_SameLine(ctx)
        if r.ImGui_RadioButton(ctx, "Custom Images", TrackIconBrowser.browse_mode == "images") then
            if TrackIconBrowser.browse_mode ~= "images" then
                TrackIconBrowser.SetBrowseMode("images", TrackIconBrowser.custom_image_folder)
            end
        end
        
        -- Scale selection for REAPER icons
        if TrackIconBrowser.browse_mode == "icons" then
            r.ImGui_SameLine(ctx)
            r.ImGui_Text(ctx, " | Scale:")
            r.ImGui_SameLine(ctx)
            
            if r.ImGui_RadioButton(ctx, "100%", TrackIconBrowser.icon_scale == 100) then
                if TrackIconBrowser.icon_scale ~= 100 then
                    TrackIconBrowser.icon_scale = 100
                    TrackIconBrowser.ReloadIcons()
                end
            end
            
            r.ImGui_SameLine(ctx)
            if r.ImGui_RadioButton(ctx, "150%", TrackIconBrowser.icon_scale == 150) then
                if TrackIconBrowser.icon_scale ~= 150 then
                    TrackIconBrowser.icon_scale = 150
                    TrackIconBrowser.ReloadIcons()
                end
            end
            
            r.ImGui_SameLine(ctx)
            if r.ImGui_RadioButton(ctx, "200%", TrackIconBrowser.icon_scale == 200) then
                if TrackIconBrowser.icon_scale ~= 200 then
                    TrackIconBrowser.icon_scale = 200
                    TrackIconBrowser.ReloadIcons()
                end
            end
        else
            -- Custom folder selection
            r.ImGui_Text(ctx, "Folder:")
            r.ImGui_SameLine(ctx)
            local folder_text = TrackIconBrowser.custom_image_folder ~= "" and TrackIconBrowser.custom_image_folder or "Not selected"
            r.ImGui_Text(ctx, folder_text)
            
            if r.ImGui_Button(ctx, "Select Folder") then
                if r.JS_Dialog_BrowseForFolder then
                    local retval, folder = r.JS_Dialog_BrowseForFolder("Select image folder", TrackIconBrowser.custom_image_folder)
                    if retval == 1 and folder ~= "" then
                        TrackIconBrowser.custom_image_folder = folder
                        TrackIconBrowser.SaveLastImageFolder()
                        TrackIconBrowser.ReloadIcons()
                    end
                else
                    local retval, folder = r.GetUserFileNameForRead(TrackIconBrowser.custom_image_folder, "Select any file in the image folder", "")
                    if retval and folder ~= "" then
                        local dir = folder:match("(.+[/\\])")
                        if dir then
                            TrackIconBrowser.custom_image_folder = dir
                            TrackIconBrowser.SaveLastImageFolder()
                            TrackIconBrowser.ReloadIcons()
                        end
                    end
                end
            end
        end
        
        -- Search box
        local rv
        rv, TrackIconBrowser.search_text = r.ImGui_InputText(ctx, "Search", TrackIconBrowser.search_text)
        if rv then
            TrackIconBrowser.FilterIcons()
        end

        r.ImGui_SameLine(ctx)
        r.ImGui_Text(ctx, string.format("(%d icons)", #TrackIconBrowser.filtered_icons))
        
        r.ImGui_Separator(ctx)
        
        -- Clear selection button
        if r.ImGui_Button(ctx, "Clear Icon") then
            TrackIconBrowser.selected_icon = nil
            TrackIconBrowser.selected_image_path = nil
            if TrackIconBrowser.target_track then
                -- Clear icon from track
                r.GetSetMediaTrackInfo_String(TrackIconBrowser.target_track, "P_ICON", "", true)
            end
            TrackIconBrowser.show_window = false
        end
        
        r.ImGui_Separator(ctx)
        
        -- Virtual scrolling with proper row rendering
        if r.ImGui_BeginChild(ctx, "IconScrollArea", 0, 0) then
            local columns = 10
            local total_icons = #TrackIconBrowser.filtered_icons
            local total_rows = math.ceil(total_icons / columns)
            
            local scroll_y = r.ImGui_GetScrollY(ctx) or 0
            local window_height = r.ImGui_GetWindowHeight(ctx) or 400
            local row_height = TrackIconBrowser.grid_size + 4
            
            -- Calculate visible range
            local start_row = math.max(0, math.floor(scroll_y / row_height))
            local visible_rows = math.ceil(window_height / row_height) + 1
            local end_row = math.min(total_rows - 1, start_row + visible_rows)
            
            -- Add space for rows above viewport
            if start_row > 0 then
                r.ImGui_Dummy(ctx, 1, start_row * row_height)
            end
            
            -- Render visible rows
            for row = start_row, end_row do
                for col = 0, columns - 1 do
                    local idx = row * columns + col + 1
                    if idx <= total_icons then
                        local icon = TrackIconBrowser.filtered_icons[idx]
                        if icon then
                            if col > 0 then
                                r.ImGui_SameLine(ctx)
                            end
                            
                            local has_image = TrackIconBrowser.image_cache[icon.name] and 
                                            r.ImGui_ValidatePtr(TrackIconBrowser.image_cache[icon.name], 'ImGui_Image*')
                            
                            if has_image then
                                local uv_u2 = (TrackIconBrowser.browse_mode == "icons") and 0.33 or 1.0
                                
                                if r.ImGui_ImageButton(ctx, "##icon" .. idx, TrackIconBrowser.image_cache[icon.name],
                                    TrackIconBrowser.grid_size, TrackIconBrowser.grid_size, 0, 0, uv_u2, 1) then
                                    TrackIconBrowser.selected_icon = icon.path
                                    if TrackIconBrowser.browse_mode == "images" then
                                        TrackIconBrowser.selected_image_path = icon.path
                                    else
                                        TrackIconBrowser.selected_image_path = nil
                                    end
                                    TrackIconBrowser.show_window = false
                                end
                            else
                                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x404040FF)
                                if r.ImGui_Button(ctx, "##icon" .. idx, TrackIconBrowser.grid_size, TrackIconBrowser.grid_size) then
                                    TrackIconBrowser.selected_icon = icon.path
                                    if TrackIconBrowser.browse_mode == "images" then
                                        TrackIconBrowser.selected_image_path = icon.path
                                    else
                                        TrackIconBrowser.selected_image_path = nil
                                    end
                                    TrackIconBrowser.show_window = false
                                end
                                r.ImGui_PopStyleColor(ctx)
                                
                                if r.ImGui_IsItemVisible(ctx) then
                                    local ok, img = pcall(r.ImGui_CreateImage, icon.path)
                                    if ok and img then
                                        TrackIconBrowser.image_cache[icon.name] = img
                                    end
                                end
                            end
                            
                            if r.ImGui_IsItemHovered(ctx) then
                                r.ImGui_BeginTooltip(ctx)
                                r.ImGui_Text(ctx, icon.name)
                                r.ImGui_EndTooltip(ctx)
                            end
                        end
                    end
                end
                
                -- Add invisible dummy at end of each row for right padding
                r.ImGui_SameLine(ctx)
                r.ImGui_Dummy(ctx, 20, 1)
            end
            
            -- Add space for rows below viewport
            local remaining_rows = total_rows - end_row - 1
            if remaining_rows > 0 then
                r.ImGui_Dummy(ctx, 1, remaining_rows * row_height)
            end
            
            r.ImGui_EndChild(ctx)
        end
    end
    
    r.ImGui_End(ctx)
    
    if not open then
        TrackIconBrowser.show_window = false
    end
    
    return TrackIconBrowser.selected_icon
end

return TrackIconBrowser
