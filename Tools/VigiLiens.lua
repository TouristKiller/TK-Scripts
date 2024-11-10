-- @description VIGILIENS
-- @author TouristKiller
-- @version 0.2.0:
-- @changelog:
--[[       * initial release
]]--        

-- VIGILIENS - Script for opening links in a menu with images --


if not reaper.APIExists("JS_Window_SetPosition") then
    reaper.ShowMessageBox("JS API niet gevonden. Zorg ervoor dat de SWS en JS extensions geïnstalleerd zijn.", "Error", 0)
    return
end

local script_path = debug.getinfo(1, "S").source:match("@?(.*[/\\])")
local os_separator = package.config:sub(1, 1)
package.path = script_path .. "?.lua;"
local json = require("json")
local texture_cache = {}

local ctx = reaper.ImGui_CreateContext('VigiLiens')
local menu_open = true

local font = reaper.ImGui_CreateFont('sans-serif', 12)
reaper.ImGui_Attach(ctx, font)

local function SetStyles()
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x00000000)        -- Transparante knop
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0x00000000) -- Transparant bij hover
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), 0x00000000)  -- Transparant bij klik
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Border(), 0x00000000)        -- Transparante rand
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_WindowBg(), 0x1C1C1CFF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0xFFFFFFFF)
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_WindowBorderSize(), 0)
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_WindowRounding(), 3)
end


-- Functie om de globale muispositie te schalen met de 200% factor
local function GetScaledMousePosition()
    local mouseX, mouseY = reaper.GetMousePosition()
    local scaleFactor = 2.0
    local adjustedX = mouseX / scaleFactor
    local adjustedY = mouseY / scaleFactor
    return adjustedX, adjustedY
end

-- Haal de geschaalde positie op bij het openen
local initialX, initialY = GetScaledMousePosition()

function CheckOutsideClick()
    if menu_open and reaper.JS_Mouse_GetState(1) == 1 then
        if not reaper.ImGui_IsAnyItemHovered(ctx) and 
           not reaper.ImGui_IsWindowHovered(ctx, reaper.ImGui_HoveredFlags_AllowWhenBlockedByPopup()) then
            menu_open = false
        end
    end
end

-- Bestaande functies behouden
function getUrlFilePath()
    return script_path .. "VigiLiens.json"
end

function loadUrls()
    local file = io.open(getUrlFilePath(), "r")
    if not file then
        local newFile = io.open(getUrlFilePath(), "w")
        if newFile then
            newFile:write("{}")
            newFile:close()
        end
        return {}
    end
    local content = file:read("*all")
    file:close()
    return content ~= "" and json.decode(content) or {}
end

function saveUrls(urls)
    local file = io.open(getUrlFilePath(), "w")
    if file then
        file:write(json.encode(urls))
        file:close()
    end
end

function addNewUrl()
    local retval, userInput = reaper.GetUserInputs("Add new URL", 2, "Name:,URL:", ",")
    if not retval then return end
    
    local name, url = userInput:match("([^,]*),([^,]*)")
    if not name or not url or name == "" or url == "" then
        reaper.ShowMessageBox("Invalid input.", "Error", 0)
        return
    end
    
    if not url:match("^https?://") then
        url = "https://" .. url
    end
    
    local urls = loadUrls()
    urls[name] = url
    saveUrls(urls)
end

function removeUrl(urls)
    local menuStr = ""
    local names = {}
    
    for name, _ in pairs(urls) do
        table.insert(names, name)
    end
    
    table.sort(names)
    
    for _, name in ipairs(names) do
        menuStr = menuStr .. name .. "|"
    end
    
    menuStr = menuStr:sub(1, -2)
    
    local ret = gfx.showmenu(menuStr)
    if ret > 0 then
        local selectedName = names[ret]
        urls[selectedName] = nil
        saveUrls(urls)
    end
end

local function LoadTexture(path)
    if texture_cache[path] then
        return texture_cache[path]
    end
    
    local source_image = reaper.JS_LICE_LoadPNG(path)
    if not source_image then return nil end
    
    local orig_width = reaper.JS_LICE_GetWidth(source_image)
    local orig_height = reaper.JS_LICE_GetHeight(source_image)
    
    local target_width = 200
    local target_height = 112
    
    local scaled_image = reaper.JS_LICE_CreateBitmap(true, target_width, target_height)
    
    reaper.JS_LICE_ScaledBlit(scaled_image, 0, 0, target_width, target_height,
                             source_image, 0, 0, orig_width, orig_height,
                             1.0, "QUICKBLIT")
    
    local pixels = {}
    for y = 0, target_height - 1 do
        for x = 0, target_width - 1 do
            local color = reaper.JS_LICE_GetPixel(scaled_image, x, y)
            table.insert(pixels, color)
        end
    end
    
    reaper.JS_LICE_DestroyBitmap(source_image)
    reaper.JS_LICE_DestroyBitmap(scaled_image)
    
    texture_cache[path] = {
        pixels = pixels,
        width = target_width,
        height = target_height
    }
    
    return texture_cache[path]
end

function Main()
    if menu_open then
        local mouseX, mouseY = GetScaledMousePosition()
        reaper.ImGui_SetNextWindowPos(ctx, mouseX, mouseY, reaper.ImGui_Cond_Once())
        
        reaper.ImGui_PushFont(ctx, font)
        SetStyles()
        CheckOutsideClick()
        
        if reaper.ImGui_Begin(ctx, 'VigiLiens Menu', menu_open, 
            reaper.ImGui_WindowFlags_NoTitleBar() |
            reaper.ImGui_WindowFlags_NoCollapse() |
            reaper.ImGui_WindowFlags_NoResize() |
            reaper.ImGui_WindowFlags_NoScrollbar() |
            reaper.ImGui_WindowFlags_AlwaysAutoResize()) then

            if reaper.ImGui_Button(ctx, '+') then
                addNewUrl()
            end
            reaper.ImGui_SameLine(ctx)
            if reaper.ImGui_Button(ctx, '-') then
                removeUrl(loadUrls())
            end
            reaper.ImGui_Separator(ctx)

            local urls = loadUrls()
            local names = {}
            for name, _ in pairs(urls) do
                table.insert(names, name)
            end
            table.sort(names)

            for _, name in ipairs(names) do
                if reaper.ImGui_Selectable(ctx, name) then
                    reaper.CF_ShellExecute(urls[name])
                end
                
                if reaper.ImGui_IsItemHovered(ctx) then
                    local image_path = script_path .. "VigImage" .. os_separator .. name .. ".png"
                    local texture = LoadTexture(image_path)
                    if texture then
                        -- Positioneer het preview venster naast het menu
                        local menu_pos_x, menu_pos_y = reaper.ImGui_GetWindowPos(ctx)
                        local menu_width = reaper.ImGui_GetWindowWidth(ctx)
                        reaper.ImGui_SetNextWindowPos(ctx, menu_pos_x + menu_width + 10, menu_pos_y)
                        reaper.ImGui_SetNextWindowSize(ctx, texture.width + 16, texture.height + 16)
                        if reaper.ImGui_Begin(ctx, 'Preview##' .. name, true,
                            reaper.ImGui_WindowFlags_NoTitleBar() |
                            reaper.ImGui_WindowFlags_NoResize() |
                            reaper.ImGui_WindowFlags_NoMove() |
                            reaper.ImGui_WindowFlags_AlwaysAutoResize()) then
                            
                            local draw_list = reaper.ImGui_GetWindowDrawList(ctx)
                            local pos_x, pos_y = reaper.ImGui_GetCursorScreenPos(ctx)
                            
                            for i, color in ipairs(texture.pixels) do
                                local x = (i-1) % texture.width
                                local y = math.floor((i-1) / texture.width)
                                local blue = color & 0xFF
                                local green = (color >> 8) & 0xFF
                                local red = (color >> 16) & 0xFF
                                local alpha = (color >> 24) & 0xFF
                                local imgui_color = reaper.ImGui_ColorConvertDouble4ToU32(red/255, green/255, blue/255, alpha/255)
                                
                                reaper.ImGui_DrawList_AddRectFilled(draw_list,
                                    pos_x + x,
                                    pos_y + y,
                                    pos_x + x + 1,
                                    pos_y + y + 1,
                                    imgui_color)
                            end
                            reaper.ImGui_End(ctx)
                        end
                    end
                end
                
            end
            reaper.ImGui_End(ctx)
            reaper.ImGui_PopFont(ctx)
            reaper.ImGui_PopStyleVar(ctx, 2)
            reaper.ImGui_PopStyleColor(ctx, 6)
        end
    end

    if menu_open then
        reaper.defer(Main)
    end
end

reaper.defer(Main)
