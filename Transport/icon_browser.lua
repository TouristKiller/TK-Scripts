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
}

function IconBrowser.LoadIcons()
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
end

function IconBrowser.Show(ctx, settings)
    if not IconBrowser.show_window then return end
    
    if #IconBrowser.icons == 0 then
        IconBrowser.LoadIcons()
        IconBrowser.FilterIcons() 
    end
    
    local window_flags = r.ImGui_WindowFlags_None()
    
    local width = 600
    local height = 400
    if settings then
        width = settings.icon_browser_width and math.max(400, settings.icon_browser_width) or 600
        height = settings.icon_browser_height and math.max(300, settings.icon_browser_height) or 400
    end
    
    r.ImGui_SetNextWindowSize(ctx, width, height, r.ImGui_Cond_FirstUseEver())
    r.ImGui_SetNextWindowSizeConstraints(ctx, 400, 300, 800, 600)
    local visible, open = r.ImGui_Begin(ctx, "TK Icon Browser", true, window_flags)
    
    if visible then
        if settings then
            -- Initialize defaults only if not set
            settings.icon_browser_width = settings.icon_browser_width or 600
            settings.icon_browser_height = settings.icon_browser_height or 400
            
            -- Only update if window was resized (with tolerance to prevent constant updates)
            local current_width = r.ImGui_GetWindowWidth(ctx)
            local current_height = r.ImGui_GetWindowHeight(ctx)
            if current_width and settings.icon_browser_width and type(settings.icon_browser_width) == "number" then
                if math.abs(current_width - settings.icon_browser_width) > 5 then
                    settings.icon_browser_width = math.max(400, current_width)
                end
            end
            if current_height and settings.icon_browser_height and type(settings.icon_browser_height) == "number" then
                if math.abs(current_height - settings.icon_browser_height) > 5 then
                    settings.icon_browser_height = math.max(300, current_height)
                end
            end
        end
        
        local rv
        rv, IconBrowser.search_text = r.ImGui_InputText(ctx, "Search", IconBrowser.search_text)
        if rv then
            IconBrowser.FilterIcons()
        end

        r.ImGui_SameLine(ctx)
        r.ImGui_Text(ctx, string.format("(%d icons)", #IconBrowser.filtered_icons))
        
        r.ImGui_Separator(ctx)
        
        r.ImGui_BeginChild(ctx, "IconScrollArea", 0, -20)
        
        local child_width = r.ImGui_GetWindowWidth(ctx)
        local style_spacing_x = r.ImGui_GetStyleVar(ctx, r.ImGui_StyleVar_ItemSpacing())
        
        if not child_width or not style_spacing_x then
            child_width = child_width or 600
            style_spacing_x = style_spacing_x or 8
        end
        
        local icon_with_spacing = IconBrowser.grid_size + style_spacing_x
        
        local right_margin = 40 - IconBrowser.grid_size
        local usable_width = child_width - right_margin
        
        local columns = math.floor(usable_width / icon_with_spacing)
        columns = math.max(1, columns)  
        
        r.ImGui_Indent(ctx, 10)
        
        local scroll_y = r.ImGui_GetScrollY(ctx)
        local window_height = r.ImGui_GetWindowHeight(ctx)
        
        if not scroll_y or not window_height then
            scroll_y = scroll_y or 0
            window_height = window_height or 400
        end
        
        local row_height = IconBrowser.grid_size
        
        -- Ensure columns is valid
        if not columns or columns <= 0 then
            columns = 1
        end
        
        local start_row = math.max(0, math.floor(scroll_y / row_height) - 1)
        local end_row = math.ceil((scroll_y + window_height) / row_height) + 1
        local total_rows = math.ceil(#IconBrowser.filtered_icons / columns)
        
        if start_row > 0 then
            r.ImGui_Dummy(ctx, 1, start_row * row_height)
        end
        
        local start_idx = start_row * columns + 1
        local end_idx = math.min(#IconBrowser.filtered_icons, end_row * columns)
        
        for i = start_idx, end_idx do
            local icon = IconBrowser.filtered_icons[i]
            if not icon then break end
            
            if i > start_idx then
                if (i - start_idx) % columns ~= 0 then
                    r.ImGui_SameLine(ctx)
                end
            end
            
            if not IconBrowser.image_cache[icon.name] or not r.ImGui_ValidatePtr(IconBrowser.image_cache[icon.name], 'ImGui_Image*') then
                IconBrowser.image_cache[icon.name] = r.ImGui_CreateImage(icon.path)
            end
            
            if r.ImGui_ImageButton(ctx, "##" .. icon.name, IconBrowser.image_cache[icon.name],
                IconBrowser.grid_size-10, IconBrowser.grid_size-10, 0, 0, 0.33, 1) then
                IconBrowser.selected_icon = icon.name
            end
            
            if r.ImGui_IsItemHovered(ctx) then
                r.ImGui_BeginTooltip(ctx)
                r.ImGui_Text(ctx, icon.name)
                r.ImGui_EndTooltip(ctx)
            end
        end
        
        local remaining_rows = total_rows - end_row
        if remaining_rows > 0 then
            r.ImGui_Dummy(ctx, 1, remaining_rows * row_height)
        end
        
        r.ImGui_EndChild(ctx)
    end
    
    r.ImGui_End(ctx)
    IconBrowser.show_window = open
    return IconBrowser.selected_icon
end


return IconBrowser
