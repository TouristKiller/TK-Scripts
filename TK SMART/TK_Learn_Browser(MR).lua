local reaper = reaper
SHOW_WEBLINK_BROWSER = true
local ctx = reaper.ImGui_CreateContext('TK Learn Browser')

-- Variabelen
local transparency = 0.75
local search_term = ""

-- Kleuren en stijlen
local function SetColors()
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_WindowBg(), 0x000000FF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0xFFFFFFFF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x4A4A4AFF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0x5A5A5AFF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), 0x6A6A6AFF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBg(), 0x3A3A3AFF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBgHovered(), 0x4A4A4AFF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBgActive(), 0x5A5A5AFF)
end

-- Rondingen en transparantie
local function SetStyles()
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_WindowRounding(), 7.0)
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FrameRounding(), 3.0)
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_Alpha(), transparency)
end

-- Lettertype
local font = reaper.ImGui_CreateFont('Arial', 12)
reaper.ImGui_Attach(ctx, font)

-- Functie om weblinks uit bestand te lezen
local function ReadWeblinksFromFile(filename)
    local file = io.open(filename, "r")
    if not file then return {} end

    local weblinks = {}
    for line in file:lines() do
        local category, author, site, title, type, url = line:match("([^|]+)|([^|]+)|([^|]+)|([^|]+)|([^|]+)|([^|]+)")
        if category and author and site and title and type and url then
            if not weblinks[category] then
                weblinks[category] = {}
            end
            table.insert(weblinks[category], {
                author = author,
                site = site,
                title = title,
                type = type,
                url = url
            })
        end
    end
    file:close()
    return weblinks
end

-- Weblinks inlezen
local weblinks = ReadWeblinksFromFile(reaper.GetResourcePath() .. "/Scripts/TK Scripts/TK SMART/weblinks.txt")

-- Functie om weblinks te filteren op basis van de zoekterm
local function SearchWeblinks(search_term)
    local filteredLinks = {}
    for category, links in pairs(weblinks) do
        for _, link in ipairs(links) do
            if link.title:lower():find(search_term:lower()) or
               category:lower():find(search_term:lower()) or
               link.author:lower():find(search_term:lower()) or
               link.type:lower():find(search_term:lower()) or
               link.site:lower():find(search_term:lower()) then
                if not filteredLinks[category] then
                    filteredLinks[category] = {}
                end
                table.insert(filteredLinks[category], link)
            end
        end
    end
    return filteredLinks
end

-- Functie om een weblink te openen
local function OpenWeblink(url)
    reaper.CF_ShellExecute(url)
end

-- Hoofdfunctie
local function Main()
    if not SHOW_WEBLINK_BROWSER then
        return
    end

    reaper.ImGui_SetNextWindowSizeConstraints(ctx, 400, 300, 16384, 16384)
    local window_flags = reaper.ImGui_WindowFlags_NoTitleBar() | reaper.ImGui_WindowFlags_NoCollapse()

    SetColors()
    SetStyles()
    reaper.ImGui_PushFont(ctx, font)

    local visible, open = reaper.ImGui_Begin(ctx, 'TK Learn Browser', true, window_flags)
    if visible then
        reaper.ImGui_SetCursorPosX(ctx, (reaper.ImGui_GetWindowWidth(ctx) - reaper.ImGui_CalcTextSize(ctx, "LEARN BROWSER (SMART Edition)")) * 0.5)
        reaper.ImGui_Text(ctx, "LEARN BROWSER (SMART Edition)")
        reaper.ImGui_Separator(ctx)

        local changed, new_search_term = reaper.ImGui_InputText(ctx, 'Search', search_term)
        if changed then
            search_term = new_search_term
        end

        local window_width = reaper.ImGui_GetWindowWidth(ctx)
        reaper.ImGui_SameLine(ctx, window_width - 47 - 8)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0xFF0000FF)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0xFF5555FF)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), 0xFF0000FF)
        if reaper.ImGui_Button(ctx, 'Quit', 47) then
            open = false
        end
        reaper.ImGui_PopStyleColor(ctx, 3)

        local window_height = reaper.ImGui_GetWindowHeight(ctx)
        local top_height = reaper.ImGui_GetTextLineHeightWithSpacing(ctx) * 3
        local bottom_height = reaper.ImGui_GetTextLineHeightWithSpacing(ctx) * 2
        local scroll_height = window_height - top_height - bottom_height

        reaper.ImGui_BeginChild(ctx, "ScrollingRegion", 0, scroll_height, reaper.ImGui_WindowFlags_None())

        local filteredLinks = SearchWeblinks(search_term)

        for category, links in pairs(filteredLinks) do
            if reaper.ImGui_TreeNode(ctx, category) then
                for _, link in ipairs(links) do
                    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0xFF4000FF)
                    if reaper.ImGui_Selectable(ctx, link.title) then
                        OpenWeblink(link.url)
                    end

                    reaper.ImGui_PopStyleColor(ctx)

                    reaper.ImGui_Text(ctx, string.format("Author: %s | Site: %s | Type: %s", link.author, link.site, link.type))
                    
                    --[[reaper.ImGui_Text(ctx, "Author: " .. link.author)
                    reaper.ImGui_Text(ctx, "Site: " .. link.site)
                    reaper.ImGui_Text(ctx, "Type: " .. link.type)]]-- Alternatieve weergave
                    
          
                    reaper.ImGui_Separator(ctx)
                end
                reaper.ImGui_TreePop(ctx)
            end
        end

        reaper.ImGui_EndChild(ctx)

        reaper.ImGui_Separator(ctx)
        reaper.ImGui_TextWrapped(ctx, "Click on a link to open it in your default web browser.")
        reaper.ImGui_End(ctx)
    end

    reaper.ImGui_PopFont(ctx)
    reaper.ImGui_PopStyleVar(ctx, 3)
    reaper.ImGui_PopStyleColor(ctx, 8)

    if open then
        reaper.defer(Main)
    else
       SHOW_WEBLINK_BROWSER = false
    end
end

-- Start het script
reaper.defer(Main)
