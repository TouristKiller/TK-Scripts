local r = reaper
local IconBrowser = {
    show_window = false,
    selected_icon = nil,
    icons = {},
    grid_size = 40,
    columns = 10,
    image_cache = {}, 
    search_text = "", 
    filtered_icons = {},
    list_clipper = nil, -- List Clipper for virtual scrolling
    images_per_frame = 1, -- Load max 1 image per frame to prevent freezing (very conservative)
    pending_loads = {}, -- Queue of images waiting to be loaded
    last_visible_range = {start = -999, finish = -999}, -- Track what was visible last frame
    frame_counter = 0, -- Frame counter to throttle loading
}

function IconBrowser.LoadIcons()
    if #IconBrowser.icons > 0 then 
        return -- Already loaded
    end
    
    local resource_path = r.GetResourcePath() .. "/Data/toolbar_icons"
    local idx = 0
    
    while true do
        local file = r.EnumerateFiles(resource_path, idx)
        if not file then break end
        if file:match("%.png$") then
            local icon = {
                name = file,
                path = resource_path .. "/" .. file
            }
            table.insert(IconBrowser.icons, icon)
        end
        idx = idx + 1
        
        -- Safety limit
        if idx > 10000 then break end
    end
end

function IconBrowser.FilterIcons()
    IconBrowser.filtered_icons = {}
    local search = IconBrowser.search_text:lower()
    
    if search == "" then
        IconBrowser.filtered_icons = IconBrowser.icons
    else
        for _, icon in ipairs(IconBrowser.icons) do
            if icon.name:lower():find(search) then
                table.insert(IconBrowser.filtered_icons, icon)
            end
        end
    end
    
    -- Clear pending loads when filter changes
    IconBrowser.pending_loads = {}
end

-- Load images in batches to prevent UI freezing
function IconBrowser.ProcessImageQueue()
    if not IconBrowser.pending_loads or #IconBrowser.pending_loads == 0 then
        return
    end
    
    -- Increment frame counter
    IconBrowser.frame_counter = (IconBrowser.frame_counter or 0) + 1
    
    -- Only load images every 3rd frame to keep UI responsive
    if IconBrowser.frame_counter % 3 ~= 0 then
        return
    end
    
    local loaded = 0
    local max_to_process = math.min(#IconBrowser.pending_loads, IconBrowser.images_per_frame)
    
    -- Process from the END of the array (more efficient than table.remove from start)
    while loaded < max_to_process and #IconBrowser.pending_loads > 0 do
        local icon_data = table.remove(IconBrowser.pending_loads) -- Remove from end
        
        if icon_data and icon_data.path then
            -- Try to load the image (only if not already cached)
            if not IconBrowser.image_cache[icon_data.name] then
                local ok, img = pcall(r.ImGui_CreateImage, icon_data.path)
                if ok and img then
                    IconBrowser.image_cache[icon_data.name] = img
                    loaded = loaded + 1
                end
            end
        end
    end
end

function IconBrowser.Show(ctx, settings)
    if not IconBrowser.show_window then return end
    
    if #IconBrowser.icons == 0 then
        IconBrowser.LoadIcons()
        IconBrowser.FilterIcons()
    end
    
    -- Fixed window size - no dynamic resizing, no title bar
    local window_flags = r.ImGui_WindowFlags_NoResize() | r.ImGui_WindowFlags_NoTitleBar()
    local width = 600
    local height = 500
    
    r.ImGui_SetNextWindowSize(ctx, width, height, r.ImGui_Cond_Always())
    
    local visible, open = r.ImGui_Begin(ctx, "TK Icon Browser", true, window_flags)
    
    if visible then
        -- Title on the left
        r.ImGui_SetCursorPosX(ctx, 5)
        r.ImGui_SetCursorPosY(ctx, 5)
        r.ImGui_Text(ctx, "Icon Browser")
        
        -- Close button in top-right corner on same line
        local close_button_size = 20
        r.ImGui_SameLine(ctx)
        r.ImGui_SetCursorPosX(ctx, width - close_button_size - 5)
        if r.ImGui_Button(ctx, "X##close", close_button_size, close_button_size) then
            open = false
        end
        
        -- Search box
        local rv
        rv, IconBrowser.search_text = r.ImGui_InputText(ctx, "Search", IconBrowser.search_text)
        if rv then
            IconBrowser.FilterIcons()
        end

        r.ImGui_SameLine(ctx)
        r.ImGui_Text(ctx, string.format("(%d icons)", #IconBrowser.filtered_icons))
        
        r.ImGui_Separator(ctx)
        
        -- Virtual scrolling with proper row rendering
        if r.ImGui_BeginChild(ctx, "IconScrollArea", 0, 0) then
            local columns = 10 -- Reduced to 10 columns to fit better in 600px width
            local total_icons = #IconBrowser.filtered_icons
            local total_rows = math.ceil(total_icons / columns)
            
            local scroll_y = r.ImGui_GetScrollY(ctx) or 0
            local window_height = r.ImGui_GetWindowHeight(ctx) or 400
            local row_height = IconBrowser.grid_size + 4
            
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
                        local icon = IconBrowser.filtered_icons[idx]
                        if icon then
                            if col > 0 then
                                r.ImGui_SameLine(ctx)
                            end
                            
                            -- Check if image exists in cache
                            local has_image = IconBrowser.image_cache[icon.name] and 
                                            r.ImGui_ValidatePtr(IconBrowser.image_cache[icon.name], 'ImGui_Image*')
                            
                            if has_image then
                                -- Render with image - only show first third horizontally (normal state)
                                -- UV coordinates: (0, 0) to (0.33, 1) to show only left third
                                if r.ImGui_ImageButton(ctx, "##" .. idx, IconBrowser.image_cache[icon.name],
                                    IconBrowser.grid_size, IconBrowser.grid_size, 0, 0, 0.33, 1) then
                                    IconBrowser.selected_icon = icon.name
                                end
                            else
                                -- Render placeholder and load on visibility
                                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x404040FF)
                                if r.ImGui_Button(ctx, "##" .. idx, IconBrowser.grid_size, IconBrowser.grid_size) then
                                    IconBrowser.selected_icon = icon.name
                                end
                                r.ImGui_PopStyleColor(ctx)
                                
                                -- Load image only if visible and not already loaded
                                if r.ImGui_IsItemVisible(ctx) then
                                    local ok, img = pcall(r.ImGui_CreateImage, icon.path)
                                    if ok and img then
                                        IconBrowser.image_cache[icon.name] = img
                                    end
                                end
                            end
                            
                            -- Tooltip
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
        IconBrowser.show_window = false
    end
    
    return IconBrowser.selected_icon
end


return IconBrowser
