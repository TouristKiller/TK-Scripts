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
                texture = r.ImGui_CreateImage(resource_path .. "/" .. file)
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
    
    local window_flags = r.ImGui_WindowFlags_NoScrollbar() | r.ImGui_WindowFlags_TopMost() | r.ImGui_WindowFlags_NoTitleBar()
    -- Removed NoResize to allow user resizing
    
    -- Use settings for window size with minimum constraints
    local width = settings and math.max(400, settings.icon_browser_width) or 600
    local height = settings and math.max(300, settings.icon_browser_height) or 400
    
    r.ImGui_SetNextWindowSize(ctx, width, height)
    local visible, open = r.ImGui_Begin(ctx, "Icon Browser##TK", true, window_flags)
    
    if visible then
        -- Update settings when user resizes window
        if settings then
            local current_width = r.ImGui_GetWindowWidth(ctx)
            local current_height = r.ImGui_GetWindowHeight(ctx)
            if current_width ~= settings.icon_browser_width then
                settings.icon_browser_width = math.max(400, current_width)
            end
            if current_height ~= settings.icon_browser_height then
                settings.icon_browser_height = math.max(300, current_height)
            end
        end
        
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), 0xFF0000FF)
        r.ImGui_Text(ctx, "TK")
        r.ImGui_PopStyleColor(ctx)
        r.ImGui_SameLine(ctx)
        r.ImGui_Text(ctx, "ICON BROWSER")
        
        local rv
        rv, IconBrowser.search_text = r.ImGui_InputText(ctx, "Search", IconBrowser.search_text)
        if rv then
            IconBrowser.FilterIcons()
        end

        r.ImGui_Text(ctx, string.format("Found: %d icons", #IconBrowser.filtered_icons))
        
        local window_width = r.ImGui_GetWindowWidth(ctx)
        r.ImGui_SameLine(ctx)
        r.ImGui_SetCursorPosX(ctx, window_width - 25)
        r.ImGui_SetCursorPosY(ctx, 6)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), 0xFF0000FF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonHovered(), 0xFF3333FF)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ButtonActive(), 0xFF6666FF)
        
        if r.ImGui_Button(ctx, "##close", 14, 14) then
            open = false
        end
        r.ImGui_PopStyleColor(ctx, 3)
        r.ImGui_Separator(ctx)
        
        r.ImGui_BeginChild(ctx, "IconScrollArea", 0, -30)
        local content_width = r.ImGui_GetWindowWidth(ctx)
        local columns = math.max(1, math.floor(content_width / IconBrowser.grid_size))
        
        for i, icon in ipairs(IconBrowser.filtered_icons) do
            if i > 1 then
                if (i-1) % columns ~= 0 then
                    r.ImGui_SameLine(ctx)
                end
            end
            
            if not IconBrowser.image_cache[icon.name] or not r.ImGui_ValidatePtr(IconBrowser.image_cache[icon.name], 'ImGui_Image*') then
                IconBrowser.image_cache[icon.name] = r.ImGui_CreateImage(r.GetResourcePath() .. "/Data/toolbar_icons/" .. icon.name)
            end
            
            if r.ImGui_ImageButton(ctx, "##" .. icon.name, IconBrowser.image_cache[icon.name],
                IconBrowser.grid_size-10, IconBrowser.grid_size-10, 0, 0, 0.33, 1) then
                IconBrowser.selected_icon = icon.name
                IconBrowser.show_window = false
            end
            
            if r.ImGui_IsItemHovered(ctx) then
                r.ImGui_BeginTooltip(ctx)
                r.ImGui_Text(ctx, icon.name)
                r.ImGui_EndTooltip(ctx)
            end
        end
        r.ImGui_EndChild(ctx)
        r.ImGui_End(ctx)
    end
    
    IconBrowser.show_window = open
    return IconBrowser.selected_icon
end


return IconBrowser
