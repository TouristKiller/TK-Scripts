local reaper = reaper
SHOW_BROWSER = true
-- Importeer ImGui
local ctx = reaper.ImGui_CreateContext('TK Marker and Region Action Browser')

-- variabelen
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

-- Acties en categorieën
local allActions = {}
local categories = {
    ["Marker"] = {},
    ["Region"] = {},
    ["Marker & Region"] = {}
}

-- Functies voor het ophalen en categoriseren van acties
local function FilterActions()
    if #allActions == 0 then
        local i = 0
        repeat
            local retval, name = reaper.CF_EnumerateActions(0, i)
            if retval > 0 and name and name ~= "" and (name:lower():find("marker") or name:lower():find("region")) then
                table.insert(allActions, {name = name, id = retval})
            end
            i = i + 1
        until retval <= 0
    end
end

local function CategorizeActions()
    for _, action in ipairs(allActions) do
        if action.name:lower():find("marker") and action.name:lower():find("region") then
            table.insert(categories["Marker & Region"], action)
        elseif action.name:lower():find("marker") then
            table.insert(categories["Marker"], action)
        elseif action.name:lower():find("region") then
            table.insert(categories["Region"], action)
        end
    end
end

-- Functie om acties te filteren op basis van de zoekterm
local function SearchActions(search_term)
    local filteredActions = {
        ["Marker"] = {},
        ["Region"] = {},
        ["Marker & Region"] = {}
    }
    for category, actions in pairs(categories) do
        for _, action in ipairs(actions) do
            if action.name:lower():find(search_term:lower()) then
                local state = reaper.GetToggleCommandState(action.id)
                action.state = state
                table.insert(filteredActions[category], action)
            end
        end
    end
    return filteredActions
end

-- Hoofdfunctie
local function Main()
    if not SHOW_BROWSER then return end

    reaper.ImGui_SetNextWindowSizeConstraints(ctx, 400, 300, 16384, 16384)
    local window_flags = reaper.ImGui_WindowFlags_NoTitleBar() | reaper.ImGui_WindowFlags_NoCollapse()

    SetColors()
    SetStyles()
    reaper.ImGui_PushFont(ctx, font)

    local visible, open = reaper.ImGui_Begin(ctx, 'TK Marker and Region Action Browser', true, window_flags)
    if visible then
        -- Bovensectie
        reaper.ImGui_SetCursorPosX(ctx, (reaper.ImGui_GetWindowWidth(ctx) - reaper.ImGui_CalcTextSize(ctx, "MARKER AND REGION ACTION BROWSER")) * 0.5)
        reaper.ImGui_Text(ctx, "MARKER AND REGION ACTION BROWSER")
        reaper.ImGui_Separator(ctx)
        local changed, new_search_term = reaper.ImGui_InputText(ctx, 'Search', search_term)
        if changed then search_term = new_search_term end

        -- Quit knop
        local window_width = reaper.ImGui_GetWindowWidth(ctx)
        reaper.ImGui_SameLine(ctx, window_width - 47 - 8)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0xFF0000FF)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0xFF5555FF)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), 0xFF0000FF)
        if reaper.ImGui_Button(ctx, 'Quit', 47) then open = false end
        reaper.ImGui_PopStyleColor(ctx, 3)

        -- Scrollbaar middendeel
        local window_height = reaper.ImGui_GetWindowHeight(ctx)
        local top_height = reaper.ImGui_GetCursorPosY(ctx)
        local bottom_height = reaper.ImGui_GetTextLineHeightWithSpacing(ctx) * 2
        local scroll_height = window_height - top_height - bottom_height

        reaper.ImGui_BeginChild(ctx, "ScrollingRegion", 0, scroll_height, reaper.ImGui_WindowFlags_None())


        -- Filter de acties op basis van de zoekterm
        local filteredActions = SearchActions(search_term)

        for category, actions in pairs(filteredActions) do
            if reaper.ImGui_TreeNode(ctx, category .. " (" .. #actions .. ")") then
                for i, action in ipairs(actions) do
                    if action.state == 1 then
                        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0xFF4000FF) -- Rood
                    end
                    
                    local prefix = action.state == 1 and "[ON] " or ""
                    if reaper.ImGui_Selectable(ctx, prefix .. action.name) then
                        reaper.Main_OnCommand(action.id, 0)
                    end
                    
                    if action.state == 1 then
                        reaper.ImGui_PopStyleColor(ctx)
                    end
                end
                reaper.ImGui_TreePop(ctx)
            end
        end
        
        reaper.ImGui_EndChild(ctx)

        -- Ondersectie
        reaper.ImGui_Separator(ctx)
        reaper.ImGui_TextWrapped(ctx, "Left-click: Execute action.")

        reaper.ImGui_End(ctx)
    end

    reaper.ImGui_PopFont(ctx)
    reaper.ImGui_PopStyleVar(ctx, 3)
    reaper.ImGui_PopStyleColor(ctx, 8)

    if open then reaper.defer(Main)
    else SHOW_BROWSER = false end
end

-- Initialisatie
FilterActions()
CategorizeActions()

-- Start het script
reaper.defer(Main)
