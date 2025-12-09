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
    list_clipper = nil,
    images_per_frame = 1,
    pending_loads = {},
    last_visible_range = {start = -999, finish = -999},
    frame_counter = 0,
    icon_scale = 100,
    browse_mode = "icons",
    custom_image_folder = "",
    selected_image_path = nil,
}

function IconBrowser.LoadLastImageFolder()
    if r.HasExtState("TK_TRANSPORT", "last_image_folder") then
        IconBrowser.custom_image_folder = r.GetExtState("TK_TRANSPORT", "last_image_folder")
    end
end

function IconBrowser.SaveLastImageFolder()
    if IconBrowser.custom_image_folder ~= "" then
        r.SetExtState("TK_TRANSPORT", "last_image_folder", IconBrowser.custom_image_folder, true)
    end
end

function IconBrowser.LoadIcons()
    if #IconBrowser.icons > 0 then 
        return
    end
    
    if IconBrowser.browse_mode == "images" then
        if IconBrowser.custom_image_folder == "" then
            return
        end
        
        local idx = 0
        while true do
            local file = r.EnumerateFiles(IconBrowser.custom_image_folder, idx)
            if not file then break end
            
            local ext = file:match("^.+(%..+)$")
            if ext then ext = ext:lower() end
            
            if file:sub(1,1) ~= "." and (ext == ".png" or ext == ".jpg" or ext == ".jpeg") then
                local icon = {
                    name = file,
                    path = IconBrowser.custom_image_folder .. "/" .. file
                }
                table.insert(IconBrowser.icons, icon)
            end
            idx = idx + 1
            
            if idx > 10000 then break end
        end
    else
        local resource_path = r.GetResourcePath() .. "/Data/toolbar_icons"
        
        if IconBrowser.icon_scale == 150 then
            resource_path = resource_path .. "/150"
        elseif IconBrowser.icon_scale == 200 then
            resource_path = resource_path .. "/200"
        end
        
        local idx = 0
        
        while true do
            local file = r.EnumerateFiles(resource_path, idx)
            if not file then break end
            
            local ext = file:match("^.+(%..+)$")
            if ext then ext = ext:lower() end
            
            if file:sub(1,1) ~= "." and (ext == ".png" or ext == ".jpg" or ext == ".jpeg") then
                local icon = {
                    name = file,
                    path = resource_path .. "/" .. file
                }
                table.insert(IconBrowser.icons, icon)
            end
            idx = idx + 1
            
            if idx > 10000 then break end
        end
    end
end

function IconBrowser.ReloadIcons()
    IconBrowser.icons = {}
    IconBrowser.filtered_icons = {}
    IconBrowser.image_cache = {}
    IconBrowser.pending_loads = {}
    
    IconBrowser.LoadIcons()
    IconBrowser.FilterIcons()
end

function IconBrowser.SetBrowseMode(mode, custom_folder)
    IconBrowser.browse_mode = mode
    if mode == "images" then
        if custom_folder then
            IconBrowser.custom_image_folder = custom_folder
            IconBrowser.SaveLastImageFolder()
        elseif IconBrowser.custom_image_folder == "" then
            IconBrowser.LoadLastImageFolder()
        end
    end
    IconBrowser.ReloadIcons()
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
    
    while loaded < max_to_process and #IconBrowser.pending_loads > 0 do
        local icon_data = table.remove(IconBrowser.pending_loads)
        
        if icon_data and icon_data.path then
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
    
    if IconBrowser.browse_mode == "images" and IconBrowser.custom_image_folder == "" then
        IconBrowser.LoadLastImageFolder()
    end
    
    if #IconBrowser.icons == 0 then
        IconBrowser.LoadIcons()
        IconBrowser.FilterIcons()
    end
    
    -- Fixed window size - no dynamic resizing, no title bar
    local window_flags = r.ImGui_WindowFlags_NoResize() | r.ImGui_WindowFlags_NoTitleBar()
    local width = 600
    local height = 500
    
    r.ImGui_SetNextWindowSize(ctx, width, height, r.ImGui_Cond_Always())
    
    local bg_color = (settings and settings.background) or 0x1E1E1EFF
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_WindowBg(), bg_color)
    local visible, open = r.ImGui_Begin(ctx, "TK Icon Browser", true, window_flags)
    
    if visible then
        r.ImGui_SetCursorPosX(ctx, 5)
        r.ImGui_SetCursorPosY(ctx, 5)
        r.ImGui_Text(ctx, "Icon/Image Browser")
        
        local close_button_size = 20
        r.ImGui_SameLine(ctx)
        r.ImGui_SetCursorPosX(ctx, width - close_button_size - 5)
        if r.ImGui_Button(ctx, "X##close", close_button_size, close_button_size) then
            open = false
        end
        
        r.ImGui_Text(ctx, "Mode:")
        r.ImGui_SameLine(ctx)
        
        local mode_changed = false
        if r.ImGui_RadioButton(ctx, "Icons", IconBrowser.browse_mode == "icons") then
            if IconBrowser.browse_mode ~= "icons" then
                IconBrowser.SetBrowseMode("icons")
                mode_changed = true
            end
        end
        
        r.ImGui_SameLine(ctx)
        if r.ImGui_RadioButton(ctx, "Images", IconBrowser.browse_mode == "images") then
            if IconBrowser.browse_mode ~= "images" then
                IconBrowser.SetBrowseMode("images", IconBrowser.custom_image_folder)
                mode_changed = true
            end
        end
        
        if IconBrowser.browse_mode == "icons" then
            r.ImGui_SameLine(ctx)
            r.ImGui_Text(ctx, " | Scale:")
            r.ImGui_SameLine(ctx)
            
            local scale_changed = false
            if r.ImGui_RadioButton(ctx, "100%", IconBrowser.icon_scale == 100) then
                if IconBrowser.icon_scale ~= 100 then
                    IconBrowser.icon_scale = 100
                    scale_changed = true
                end
            end
            
            r.ImGui_SameLine(ctx)
            if r.ImGui_RadioButton(ctx, "150%", IconBrowser.icon_scale == 150) then
                if IconBrowser.icon_scale ~= 150 then
                    IconBrowser.icon_scale = 150
                    scale_changed = true
                end
            end
            
            r.ImGui_SameLine(ctx)
            if r.ImGui_RadioButton(ctx, "200%", IconBrowser.icon_scale == 200) then
                if IconBrowser.icon_scale ~= 200 then
                    IconBrowser.icon_scale = 200
                    scale_changed = true
                end
            end
            
            if scale_changed then
                IconBrowser.ReloadIcons()
            end
        else
            r.ImGui_Text(ctx, "Folder: " .. (IconBrowser.custom_image_folder ~= "" and IconBrowser.custom_image_folder or "Not selected"))
            r.ImGui_SameLine(ctx)
            if r.ImGui_Button(ctx, "Select Folder") then
                if r.JS_Dialog_BrowseForFolder then
                    local retval, folder = r.JS_Dialog_BrowseForFolder("Select image folder", IconBrowser.custom_image_folder)
                    if retval == 1 and folder ~= "" then
                        IconBrowser.custom_image_folder = folder
                        IconBrowser.SaveLastImageFolder()
                        IconBrowser.ReloadIcons()
                    end
                else
                    local retval, folder = r.GetUserFileNameForRead(IconBrowser.custom_image_folder, "Select any file in the image folder", "")
                    if retval and folder ~= "" then
                        local dir = folder:match("(.+[/\\])")
                        if dir then
                            IconBrowser.custom_image_folder = dir
                            IconBrowser.SaveLastImageFolder()
                            IconBrowser.ReloadIcons()
                        end
                    end
                end
            end
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
                            
                            local has_image = IconBrowser.image_cache[icon.name] and 
                                            r.ImGui_ValidatePtr(IconBrowser.image_cache[icon.name], 'ImGui_Image*')
                            
                            if has_image then
                                local uv_u2 = (IconBrowser.browse_mode == "icons") and 0.33 or 1.0
                                
                                if r.ImGui_ImageButton(ctx, "##" .. idx, IconBrowser.image_cache[icon.name],
                                    IconBrowser.grid_size, IconBrowser.grid_size, 0, 0, uv_u2, 1) then
                                    if IconBrowser.browse_mode == "images" then
                                        IconBrowser.selected_image_path = icon.path
                                        IconBrowser.selected_icon = icon.path
                                    else
                                        IconBrowser.selected_icon = icon.path
                                        IconBrowser.selected_image_path = nil
                                    end
                                end
                            else
                                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0x404040FF)
                                if r.ImGui_Button(ctx, "##" .. idx, IconBrowser.grid_size, IconBrowser.grid_size) then
                                    if IconBrowser.browse_mode == "images" then
                                        IconBrowser.selected_image_path = icon.path
                                        IconBrowser.selected_icon = icon.path
                                    else
                                        IconBrowser.selected_icon = icon.path
                                        IconBrowser.selected_image_path = nil
                                    end
                                end
                                r.ImGui_PopStyleColor(ctx)
                                
                                if r.ImGui_IsItemVisible(ctx) then
                                    local ok, img = pcall(r.ImGui_CreateImage, icon.path)
                                    if ok and img then
                                        IconBrowser.image_cache[icon.name] = img
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
    r.ImGui_PopStyleColor(ctx)
    
    if not open then
        IconBrowser.show_window = false
    end
    
    return IconBrowser.selected_icon
end


return IconBrowser
