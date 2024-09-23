-- @description TK FX BROWSER
-- @version 0.2.5
-- @author TouristKiller
-- @about
--   #  A MOD of Sexan's FX Browser (THANX FOR ALL THE HELP)
-- @changelog:
--          * Just some more GUI settings

     
--------------------------------------------------------------------------
local r = reaper
-- Pad en module instellingen
local os_separator = package.config:sub(1, 1)
local script_path = debug.getinfo(1, "S").source:match("@?(.*[/\\])")
package.path = script_path .. "?.lua;"
require("Sexan_FX_Browser")
local json = require("json")
local screenshot_path = script_path .. "Screenshots" .. os_separator
-- GUI instellingen
local ctx = r.ImGui_CreateContext('TK FX BROWSER')
local window_flags = r.ImGui_WindowFlags_NoTitleBar() | r.ImGui_WindowFlags_NoScrollbar()
local MAX_SUBMENU_WIDTH = 170
local FX_LIST_WIDTH = 340
local FLT_MAX = 3.402823466e+38
-- Globale variabelen
local SHOW_PREVIEW = true
local TRACK, LAST_USED_FX, FILTER, ADDFX_Sel_Entry
local FX_LIST_TEST, CAT_TEST = ReadFXFile()
if not FX_LIST_TEST or not CAT_TEST then
    FX_LIST_TEST, CAT_TEST = MakeFXFiles()
end
local ADD_FX_TO_ITEM = false
local old_t = {}
local old_filter = ""
local current_hovered_plugin = nil
-- Screenshot
local screenshot_texture = nil
local screenshot_width, screenshot_height = 0, 0
local is_bulk_screenshot_running = false
local STOP_REQUESTED = false
local screenshot_database = {} 
local screenshot_search_results = nil
local update_search_screenshots = false
local search_texture_cache = {}
local texture_load_queue = {}
local MAX_TEXTURES_PER_FRAME = 5
local texture_last_used = {}
local MAX_CACHED_SEARCH_TEXTURES = 50
local MIN_CACHED_TEXTURES = 10
local TEXTURE_RELOAD_DELAY = 5 -- in seconden
local screenshot_window_opened = false 
local show_screenshot_window = false 
local screenshot_window_interactive = false 
local screenshot_window_display_size = 250


local selected_folder = nil
-- Dock / Undock
local dock = 0
local change_dock = false
-- GUI
local NormalFont = r.ImGui_CreateFont('Arial', 11)
r.ImGui_Attach(ctx, NormalFont)
local LargeFont = r.ImGui_CreateFont('Arial', 14) -- Pas de grootte aan naar wens
r.ImGui_Attach(ctx, LargeFont)
local dark_gray = 0x303030FF
local hover_gray = 0x444444FF
local active_gray = 0x303030F
local settings_icon = nil
-- variabele voor de logbestandspad
local log_file_path = script_path .. "screenshot_log.txt"

-- Script config
local config = {
    srcx = 0,
    srcy = 27,
    capture_height_offset = 0,
    screenshot_display_size = 250,
    auto_refresh_fx_list = true,
    show_screenshot_in_search = true,
    show_screenshot_window = false,
    screenshot_window_width = 200,
    resize_screenshots_with_window = false,
    dock_screenshot_window = false, 
    dock_screenshot_left = true,
    background_color = 0x000000FF,
    background_gray = 0,
    window_alpha = 0.75,
    text_gray = 255,  
    button_background_gray = 156,
    button_background_color = r.ImGui_ColorConvertDouble4ToU32(128/255, 128/255, 128/255, 1),
    button_hover_gray = 68,
    button_hover_color = r.ImGui_ColorConvertDouble4ToU32(128/255, 128/255, 128/255, 1),
    button_active_gray = 48,
    frame_bg_gray = 48,
    frame_bg_color = r.ImGui_ColorConvertDouble4ToU32(128/255, 128/255, 128/255, 1),
    frame_bg_hover_gray = 68,
    frame_bg_hover_color = r.ImGui_ColorConvertDouble4ToU32(128/255, 128/255, 128/255, 1),
    frame_bg_active_gray = 88,
    frame_bg_active_color = r.ImGui_ColorConvertDouble4ToU32(128/255, 128/255, 128/255, 1),
    dropdown_bg_color = 0x000000FF,
  }

local window_alpha_int = math.floor(config.window_alpha * 100)
---------------------------------------------------------------
local function log_to_file(message)
    local file = io.open(log_file_path, "a")
    if file then
        file:write(message .. "\n")
        file:close()
    end
end

local function SaveConfig()
    local file = io.open(script_path .. "config.json", "w")
    if file then
        file:write(json.encode(config))
        file:close()
    end
end

local function LoadConfig()
    local file = io.open(script_path .. "config.json", "r")
    if file then
        local content = file:read("*all")
        file:close()
        local loaded_config = json.decode(content)
        for k, v in pairs(loaded_config) do
            config[k] = v
        end
    end
end
LoadConfig()

local function ShowConfigWindow()
    local config_open = true
    local window_width = 300
    local window_height = 460
    local slider_width = 140 -- of een andere gewenste breedte
   
    r.ImGui_SetNextWindowSize(ctx, window_width, window_height, r.ImGui_Cond_Always())
    r.ImGui_SetNextWindowSizeConstraints(ctx, window_width, window_height, window_width, window_height)
    local visible, open = r.ImGui_Begin(ctx, "Settings", true, window_flags | r.ImGui_WindowFlags_NoResize())
    if visible then
        r.ImGui_Text(ctx, "SETTINGS:")
        r.ImGui_Separator(ctx)
        r.ImGui_PushItemWidth(ctx, slider_width)
        r.ImGui_Text(ctx, "Screenshot settings")
        _, config.srcx = r.ImGui_SliderInt(ctx, "X Offset", config.srcx, 0, 500)
        _, config.srcy = r.ImGui_SliderInt(ctx, "Y Offset", config.srcy, 0, 500)
        _, config.capture_height_offset = r.ImGui_SliderInt(ctx, "Height Offset", config.capture_height_offset, 0, 500)
        _, config.screenshot_display_size = r.ImGui_SliderInt(ctx, "Display Size", config.screenshot_display_size, 100, 500)
        r.ImGui_Separator(ctx)
        r.ImGui_Text(ctx, "Search Screenshot Preview")
        _, config.show_screenshot_in_search = r.ImGui_Checkbox(ctx, "Show Screenshots in Search", config.show_screenshot_in_search)
        _, config.show_screenshot_window = r.ImGui_Checkbox(ctx, "Show Screenshot Window", config.show_screenshot_window)
        _, config.resize_screenshots_with_window = r.ImGui_Checkbox(ctx, "Resize screenshots with window", config.resize_screenshots_with_window)
        _, config.dock_screenshot_window = r.ImGui_Checkbox(ctx, "Dock screenshot window", config.dock_screenshot_window)
        if config.dock_screenshot_window then
        r.ImGui_SameLine(ctx)
        _, config.dock_screenshot_left = r.ImGui_Checkbox(ctx, "Dock left (uncheck for right)", config.dock_screenshot_left)
        end
   
        r.ImGui_Separator(ctx)
        r.ImGui_Text(ctx, "GUI Settings")
        local changed, new_gray = r.ImGui_SliderInt(ctx, "Background Color", config.background_gray, 0, 255)
        if changed then
            config.background_gray = new_gray
            config.background_color = r.ImGui_ColorConvertDouble4ToU32(new_gray/255, new_gray/255, new_gray/255, config.window_alpha)
        end
        local changed_alpha, new_alpha_int = r.ImGui_SliderInt(ctx, "Window Transparency", window_alpha_int, 0, 100, "%d%%")
        if changed_alpha then
            window_alpha_int = new_alpha_int
            config.window_alpha = window_alpha_int / 100
            config.background_color = r.ImGui_ColorConvertDouble4ToU32(config.background_gray/255, config.background_gray/255, config.background_gray/255, config.window_alpha)
        end
        local changed_text, new_text_gray = r.ImGui_SliderInt(ctx, "Text Color", config.text_gray, 0, 255)
        if changed_text then
            config.text_gray = new_text_gray
            config.text_color = r.ImGui_ColorConvertDouble4ToU32(new_text_gray/255, new_text_gray/255, new_text_gray/255, 1)
        end
        r.ImGui_Separator(ctx)
        local changed_button_bg, new_button_bg_gray = r.ImGui_SliderInt(ctx, "Button Background Color", config.button_background_gray, 0, 255)
        if changed_button_bg then
            config.button_background_gray = new_button_bg_gray
            config.button_background_color = r.ImGui_ColorConvertDouble4ToU32(new_button_bg_gray/255, new_button_bg_gray/255, new_button_bg_gray/255, 1)
        end
        local changed_hover, new_hover_gray = r.ImGui_SliderInt(ctx, "Button Hover Color", config.button_hover_gray, 0, 255)
        if changed_hover then
            config.button_hover_gray = new_hover_gray
            config.button_hover_color = r.ImGui_ColorConvertDouble4ToU32(new_hover_gray/255, new_hover_gray/255, new_hover_gray/255, 1)
        end
        r.ImGui_Separator(ctx)
        local changed_frame_bg, new_frame_bg_gray = r.ImGui_SliderInt(ctx, "Frame Background Color", config.frame_bg_gray, 0, 255)
        if changed_frame_bg then
            config.frame_bg_gray = new_frame_bg_gray
            config.frame_bg_color = r.ImGui_ColorConvertDouble4ToU32(new_frame_bg_gray/255, new_frame_bg_gray/255, new_frame_bg_gray/255, 1)
        end

        local changed_frame_hover, new_frame_hover_gray = r.ImGui_SliderInt(ctx, "Frame Hover Color", config.frame_bg_hover_gray, 0, 255)
        if changed_frame_hover then
            config.frame_bg_hover_gray = new_frame_hover_gray
            config.frame_bg_hover_color = r.ImGui_ColorConvertDouble4ToU32(new_frame_hover_gray/255, new_frame_hover_gray/255, new_frame_hover_gray/255, 1)
        end

        local changed_frame_active, new_frame_active_gray = r.ImGui_SliderInt(ctx, "Frame Active Color", config.frame_bg_active_gray, 0, 255)
        if changed_frame_active then
            config.frame_bg_active_gray = new_frame_active_gray
            config.frame_bg_active_color = r.ImGui_ColorConvertDouble4ToU32(new_frame_active_gray/255, new_frame_active_gray/255, new_frame_active_gray/255, 1)
        end
        local changed_dropdown, new_dropdown_gray = r.ImGui_SliderInt(ctx, "Dropdown Background Color", config.dropdown_bg_gray, 0, 255)
        if changed_dropdown then
            config.dropdown_bg_gray = new_dropdown_gray
            config.dropdown_bg_color = r.ImGui_ColorConvertDouble4ToU32(new_dropdown_gray/255, new_dropdown_gray/255, new_dropdown_gray/255, 1)
        end

        

        r.ImGui_Separator(ctx)
        r.ImGui_Text(ctx, "Other settings")
        _, config.auto_refresh_fx_list = r.ImGui_Checkbox(ctx, "Auto-refresh FX list on startup", config.auto_refresh_fx_list)
        r.ImGui_PopItemWidth(ctx)
        if r.ImGui_Button(ctx, "Save") then
            SaveConfig()
            config_open = false
        end
        r.ImGui_SameLine(ctx)
        if r.ImGui_Button(ctx, "Cancel") then
            config_open = false
        end
        
        r.ImGui_End(ctx)
    end
    return config_open
end

local function EnsureScreenshotFolderExists()
    if not r.file_exists(screenshot_path) then
        local success = r.RecursiveCreateDirectory(screenshot_path, 0)
        if success then
            log_to_file("Screenshots map aangemaakt: " .. screenshot_path)
        else
            log_to_file("Fout bij het aanmaken van Screenshots map: " .. screenshot_path)
        end
    end
end
EnsureScreenshotFolderExists()

local function InitializeSettingsIcon()
    if not settings_icon then
        settings_icon = r.ImGui_CreateImage(script_path .. "settings.png")
    end
end

local function check_esc_key() 
    if reaper.ImGui_IsKeyPressed(ctx, reaper.ImGui_Key_Escape()) then
        return true
    end
    return false
end

local function handleDocking()
    if change_dock then
        r.ImGui_SetNextWindowDockID(ctx, ~dock)
        change_dock = nil
    end
end

local function BuildScreenshotDatabase()
    screenshot_database = {}
    for file in io.popen('dir "'..screenshot_path..'" /b'):lines() do
        local plugin_name = file:gsub("%.png$", ""):gsub("_", " ")
        screenshot_database[plugin_name] = true
    end
end

local function IsX86Bridged(plugin_name)
    return plugin_name:find("x86") ~= nil
end

local function ScreenshotExists(plugin_name)
    return screenshot_database[plugin_name] ~= nil
end
BuildScreenshotDatabase()

local function OpenScreenshotsFolder()
    local os_name = reaper.GetOS()
    if os_name:match("Win") then
        os.execute('start "" "' .. screenshot_path .. '"')
    elseif os_name:match("OSX") then
        os.execute('open "' .. screenshot_path .. '"')
    else
        reaper.ShowMessageBox("Unsupported OS", "Error", 0)
    end
end
--------------------------------
-- bodem knoppen
local function IsMuted(track)
    if track then
        return r.GetMediaTrackInfo_Value(track, "B_MUTE") == 1
    end
    return false
end

local function ToggleMute(track)
    if track then
        local mute = r.GetMediaTrackInfo_Value(track, "B_MUTE")
        r.SetMediaTrackInfo_Value(track, "B_MUTE", mute == 0 and 1 or 0)
    end
end

local function IsSoloed(track)
    if track then
        return r.GetMediaTrackInfo_Value(track, "I_SOLO") ~= 0
    end
    return false
end

local function ToggleSolo(track)
    if track then
        local solo = r.GetMediaTrackInfo_Value(track, "I_SOLO")
        r.SetMediaTrackInfo_Value(track, "I_SOLO", solo == 0 and 1 or 0)
    end
end

local function ToggleArm(track)
    if track then
        local armed = r.GetMediaTrackInfo_Value(track, "I_RECARM")
        r.SetMediaTrackInfo_Value(track, "I_RECARM", armed == 0 and 1 or 0)
    end
end

local function IsArmed(track)
    if track then
        return r.GetMediaTrackInfo_Value(track, "I_RECARM") == 1
    end
    return false
end
-------------

local function AddFXToItem(fx_name)
    local item = r.GetSelectedMediaItem(0, 0)
    if item then
        local take = r.GetActiveTake(item)
        if take then
            r.TakeFX_AddByName(take, fx_name, 1)
        end
    end
end

local function CreateFXChain()
    if not TRACK then return end
    local fx_count = r.TrackFX_GetCount(TRACK)
    if fx_count == 0 then return end
    r.SetOnlyTrackSelected(TRACK)
    r.Main_OnCommand(r.NamedCommandLookup("_S&M_SAVE_FXCHAIN_SLOT1"), 0)
    FX_LIST_TEST, CAT_TEST = MakeFXFiles()
    r.ShowMessageBox("FX Chain created successfully!", "Success", 0)
end

local function LoadTexture(file)
    local texture = r.ImGui_CreateImage(file)
    if texture == nil then
        log_to_file("Failed to load texture: " .. file)
    end
    return texture
end
    
local function LoadSearchTexture(file)
    if search_texture_cache[file] then
        texture_last_used[file] = r.time_precise()
        return search_texture_cache[file]
    end
    
    if not texture_load_queue[file] then
        texture_load_queue[file] = r.time_precise()
    end
    return nil
end

local function ProcessTextureLoadQueue()
    local textures_loaded = 0
    local current_time = r.time_precise()
    
    -- Laad nieuwe textures
    for file, queue_time in pairs(texture_load_queue) do
        if textures_loaded >= MAX_TEXTURES_PER_FRAME then break end
        
        if not search_texture_cache[file] then
            local texture = r.ImGui_CreateImage(file)
            if texture then
                search_texture_cache[file] = texture
                texture_last_used[file] = current_time
                textures_loaded = textures_loaded + 1
                log_to_file("Texture geladen: " .. file)
            else
                log_to_file("Fout bij laden texture: " .. file)
            end
        end
        
        texture_load_queue[file] = nil
    end
    
    -- Verwijder oude textures, maar houd een minimum aantal
    local cache_size = 0
    for _ in pairs(search_texture_cache) do cache_size = cache_size + 1 end
    
    if cache_size > MAX_CACHED_SEARCH_TEXTURES then
        local textures_to_remove = {}
        for file, last_used in pairs(texture_last_used) do
            if current_time - last_used > TEXTURE_RELOAD_DELAY and cache_size > MIN_CACHED_TEXTURES then
                table.insert(textures_to_remove, file)
                cache_size = cache_size - 1
            end
        end
        
        for _, file in ipairs(textures_to_remove) do
            if r.ImGui_DestroyImage then
                r.ImGui_DestroyImage(ctx, search_texture_cache[file])
            else
                -- Alternative cleanup method or log the issue
                log_to_file("ImGui_DestroyImage not available, texture not destroyed: " .. file)
            end
            search_texture_cache[file] = nil
            texture_last_used[file] = nil
            log_to_file("Texture verwijderd: " .. file)
        end
    end
    
    -- Herlaad verwijderde textures indien nodig
    if cache_size < MIN_CACHED_TEXTURES then
        for file in pairs(texture_last_used) do
            if not search_texture_cache[file] then
                texture_load_queue[file] = current_time
            end
        end
    end
end

local function Lead_Trim_ws(s) return s:match '^%s*(.*)' end

local function SetMinMax(Input, Min, Max)
    return math.max(Min, math.min(Input, Max))
end

local function SortTable(tab, val1, val2)
    table.sort(tab, function(a, b)
        if (a[val1] < b[val1]) then return true
        elseif (a[val1] > b[val1]) then return false
        else return a[val2] < b[val2] end
    end)
end

local function GetTrackColorAndTextColor(track)
    local color = r.GetTrackColor(track)
    
    if color == 0 then
        return r.ImGui_ColorConvertDouble4ToU32(1, 1, 1, 1), 0x000000FF
    else
        local red = (color & 0xFF) / 255
        local green = ((color >> 8) & 0xFF) / 255
        local blue = ((color >> 16) & 0xFF) / 255
        
        local brightness = (red * 0.299 + green * 0.587 + blue * 0.114)
        local text_color = brightness > 0.5 and 0x000000FF or 0xFFFFFFFF
        
        return r.ImGui_ColorConvertDouble4ToU32(red, green, blue, 1), text_color
    end
end

local function GetBounds(hwnd)
    local retval, left, top, right, bottom = r.JS_Window_GetClientRect(hwnd)
    return left, top, right-left, bottom-top
end

local function Literalize(str)
    return str:gsub("[%(%)%.%%%+%-%*%?%[%]%^%$]", "%%%1")
end

local function GetFileContext(filename)
    local file = io.open(filename, "r")
    if file then
        local content = file:read("*all")
        file:close()
        return content
    end
    return nil
end

local function GetTrackName(track)
    local _, name = r.GetTrackName(track)
    return name
end

local function IsOSX()
    local platform = reaper.GetOS()
    return platform:match("OSX") or platform:match("macOS")
end

local function ScreenshotOSX(path, x, y, w, h)
    x, y = r.ImGui_PointConvertNative(ctx, x, y, false)
    local command = 'screencapture -x -R %d,%d,%d,%d -t png "%s"'
    os.execute(command:format(x, y, w, h, path))
end

local wait_time = 0.5 -- Wachttijd in seconden
local timeout_duration = 5 -- Timeout duur in seconden

local function Wait(callback, start_time)
    start_time = start_time or r.time_precise()
    local function check()
        if r.time_precise() - start_time >= wait_time then
            callback()
        else
            r.defer(check)
        end
    end
    r.defer(check)
end

local function IsPluginClosed(fx_index)
    return not r.TrackFX_GetFloatingWindow(TRACK, fx_index)
end

local function EnsurePluginRemoved(fx_index, callback)
    local function check()
        if IsPluginClosed(fx_index) then
            if callback then
                callback()
            else
                print("Error: callback is nil")
            end
        else
            r.defer(check)
        end
    end
    r.defer(check)
end

local function CaptureScreenshot(plugin_name, fx_index)
    local hwnd = r.TrackFX_GetFloatingWindow(TRACK, fx_index)
    if hwnd then
        local safe_name = plugin_name:gsub("[^%w%s-]", "_")
        local filename = screenshot_path .. safe_name .. ".png"
        
        local retval, left, top, right, bottom = r.JS_Window_GetClientRect(hwnd)
        local w, h = right - left, bottom - top
        
        -- Stel de offset in op 0 voor JS plugins, anders gebruik de configuratie
        local offset = plugin_name:match("^JS") and 0 or config.capture_height_offset
        h = h - offset

        log_to_file("Capturing screenshot for plugin: " .. plugin_name)  -- Log de plugin naam
        if not IsOSX() then
            local srcDC = r.JS_GDI_GetClientDC(hwnd)
            local destBmp = r.JS_LICE_CreateBitmap(true, w, h)
            local destDC = r.JS_LICE_GetDC(destBmp)
            r.JS_GDI_Blit(destDC, 0, 0, srcDC, config.srcx, config.srcy, w, h)
            r.JS_LICE_WritePNG(filename, destBmp, false)
            r.JS_GDI_ReleaseDC(hwnd, srcDC)
            r.JS_LICE_DestroyBitmap(destBmp)
        else
            ScreenshotOSX(filename, left, top, w, h)
        end
        
        local file = io.open(filename, "rb")
        if file then
            local size = file:seek("end")
            file:close()
            if size > 0 then
                print("Screenshot Saved " .. filename .. " (Grootte: " .. size .. " bytes)")
            else
                print("Screenshot File is Empty: " .. filename)
            end
        else
            print("Cant make screenshot: " .. filename)
        end
    else
        print("No Plugin Window " .. plugin_name)
    end
    r.TrackFX_Show(TRACK, fx_index, 2)
    r.TrackFX_Delete(TRACK, fx_index)
end
local function MakeScreenshot(plugin_name, callback)
    if type(plugin_name) ~= "string" then
        r.ShowMessageBox("Invalid plugin name", "Error", 0)
        return
    end
    local fx_index = r.TrackFX_AddByName(TRACK, plugin_name, false, -1)
    r.TrackFX_Show(TRACK, fx_index, 3)
    
    Wait(function()
        CaptureScreenshot(plugin_name, fx_index)
        r.TrackFX_Show(TRACK, fx_index, 2) -- Sluit de plugin
        r.TrackFX_Delete(TRACK, fx_index) -- Verwijder de plugin
        EnsurePluginRemoved(fx_index, callback) -- Controleer of de plugin is verwijderd
    end)
end


local bulk_screenshot_progress = 0
local total_fx_count = 0
local loaded_fx_count = 0  
local fx_list = {}
local function EnumerateInstalledFX()
    fx_list = {}
    total_fx_count = 0
    for i = 1, math.huge do
        local retval, fx_name = r.EnumInstalledFX(i)
        if not retval then break end
        if not fx_name:match("^JS:") then
            total_fx_count = total_fx_count + 1
            fx_list[total_fx_count] = fx_name
        end
    end
end

local function ScreenshotExists(plugin_name)
    local safe_name = plugin_name:gsub("[^%w%s-]", "_")
    local filename = screenshot_path .. safe_name .. ".png"
    local file = io.open(filename, "r")
    if file then
        file:close()
        return true
    end
    return false
end

local PROCESS = false
local START = false
local function ProcessFX(index, start_time)
    start_time = start_time or r.time_precise()
    if STOP_REQUESTED or index > total_fx_count then
        log_to_file("Process completed or stopped at index: " .. index)
        START = false
        PROCESS = false
        STOP_REQUESTED = false
        bulk_screenshot_progress = 0
        loaded_fx_count = 0
        r.defer(function()
            reaper.ShowMessageBox("Bulk screenshot process " .. (STOP_REQUESTED and "stopped" or "completed"), "Info", 0)
        end)
    elseif index <= total_fx_count then
        local plugin_name = fx_list[index]
        if not plugin_name:match("^JS:")  and not IsX86Bridged(plugin_name) and not ScreenshotExists(plugin_name) then
            MakeScreenshot(plugin_name, function()
                loaded_fx_count = loaded_fx_count + 1
                bulk_screenshot_progress = loaded_fx_count / total_fx_count
                log_to_file("Processed plugin: " .. plugin_name .. " Progress: " .. bulk_screenshot_progress)
                r.defer(function() 
                    if r.time_precise() - start_time > 300 then -- 5 minuten timeout
                        log_to_file("Process timed out")
                        ProcessFX(total_fx_count + 1) -- Forceer afsluiting
                    else
                        ProcessFX(index + 1) 
                    end
                end)
            end)
        else
            loaded_fx_count = loaded_fx_count + 1
            bulk_screenshot_progress = loaded_fx_count / total_fx_count
            r.defer(function() ProcessFX(index + 1) end)
        end
    end
end

local function ClearScreenshots()
    for file in io.popen('dir "'..screenshot_path..'" /b'):lines() do
        os.remove(screenshot_path .. file)
    end
    BuildScreenshotDatabase() -- Update de database na het verwijderen van de screenshots
    print("All screenshots cleared.")
end

local function ShowConfirmClearPopup()
    local popup_open = true
    r.ImGui_OpenPopup(ctx, "Confirm Clear Screenshots")
    if r.ImGui_BeginPopupModal(ctx, "Confirm Clear Screenshots", popup_open, r.ImGui_WindowFlags_AlwaysAutoResize()) then
        r.ImGui_Text(ctx, "Are you sure you want to clear all screenshots?")
        if r.ImGui_Button(ctx, "Yes", 80, 0) then
            ClearScreenshots()
            show_confirm_clear = false
            r.ImGui_CloseCurrentPopup(ctx)
        end
        r.ImGui_SameLine(ctx)
        if r.ImGui_Button(ctx, "No", 80, 0) then
            show_confirm_clear = false
            r.ImGui_CloseCurrentPopup(ctx)
        end
        r.ImGui_EndPopup(ctx)
    end
end

local function StartBulkScreenshot()
    if not START then
        EnumerateInstalledFX()
        bulk_screenshot_progress = 0
        loaded_fx_count = 0  -- Reset het aantal geladen plugins
        START = true
        PROCESS = true
        STOP_REQUESTED = false
        ProcessFX(1)
    else
        STOP_REQUESTED = true
    end
end

function LoadPluginScreenshot(plugin_name)
    local safe_name = plugin_name:gsub("[^%w%s-]", "_")
    local screenshot_file = screenshot_path .. safe_name .. ".png"
   
    if r.file_exists(screenshot_file) then
        screenshot_texture = LoadTexture(screenshot_file)
        if screenshot_texture then
            screenshot_width, screenshot_height = r.ImGui_Image_GetSize(screenshot_texture)
        end
    else
        screenshot_texture = nil
    end
end

function ShowPluginScreenshot()
    if screenshot_texture and current_hovered_plugin then
        if r.ImGui_ValidatePtr(screenshot_texture, 'ImGui_Image*') then
            local width, height = r.ImGui_Image_GetSize(screenshot_texture)
            if width and height then
                local display_width = config.screenshot_display_size
                local display_height = display_width * (height / width)
            
                local mouse_x, mouse_y = r.ImGui_GetMousePos(ctx)
                local vp_width, vp_height = r.ImGui_GetWindowSize(ctx)
                
                local window_pos_x = mouse_x + 20
                local window_pos_y = mouse_y + 20
                
                if window_pos_x + display_width > vp_width then
                    window_pos_x = mouse_x - display_width - 20
                end
                if window_pos_y + display_height > vp_height * 3 then
                    window_pos_y = mouse_y - display_height - 20
                end
                
                r.ImGui_SetNextWindowSize(ctx, display_width, display_height + 30)
                r.ImGui_SetNextWindowPos(ctx, window_pos_x, window_pos_y)
                r.ImGui_SetNextWindowBgAlpha(ctx, 0.9)
                r.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FrameRounding(), 1)
                r.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_WindowRounding(), 14)
                r.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_PopupRounding(), 1)
                r.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_ItemSpacing(), 1, 1)
                r.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_WindowPadding(), 2,2)
                r.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_WindowBorderSize(), 7)

                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_WindowBg(), config.background_color)
                r.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_PopupBg(), 0x000000FF)
                r.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBg(), 0x000000FF)
                r.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBgHovered(), 0x000000FF)
                r.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBgActive(), 0x000000FF)
                r.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Border(), 0x000000FF)
                
                if r.ImGui_Begin(ctx, "Plugin Screenshot", true, r.ImGui_WindowFlags_NoTitleBar() | r.ImGui_WindowFlags_NoCollapse() | r.ImGui_WindowFlags_NoFocusOnAppearing() | r.ImGui_WindowFlags_NoDocking() | r.ImGui_WindowFlags_NoScrollbar() | r.ImGui_WindowFlags_TopMost() | r.ImGui_WindowFlags_NoResize()) then
                    r.ImGui_Image(ctx, screenshot_texture, display_width, display_height)
                    
                    local text_width = r.ImGui_CalcTextSize(ctx, current_hovered_plugin)
                    local text_pos_x = (display_width - text_width) * 0.5
                    local text_pos_y = display_height + 12
                    
                    r.ImGui_SetCursorPos(ctx, text_pos_x, text_pos_y)
                    r.ImGui_Text(ctx, current_hovered_plugin)
                    
                    r.ImGui_End(ctx)
                end
                
                r.ImGui_PopStyleVar(ctx, 6)
                r.ImGui_PopStyleColor(ctx, 6)
            else
                log_to_file("Ongeldige afmetingen voor texture: " .. tostring(screenshot_texture))
                screenshot_texture = nil
            end
        else
            log_to_file("Ongeldige texture voor plugin: " .. current_hovered_plugin)
            screenshot_texture = nil
        end
    end
end

local function ShowScreenshotWindow()
    if not config.show_screenshot_window then return end

    
    local main_window_pos_x, main_window_pos_y = r.ImGui_GetWindowPos(ctx)
    local main_window_width = r.ImGui_GetWindowWidth(ctx)
    local main_window_height = r.ImGui_GetWindowHeight(ctx)

    local window_flags = r.ImGui_WindowFlags_NoTitleBar() | r.ImGui_WindowFlags_NoFocusOnAppearing()
    
    if config.dock_screenshot_window then
        if config.dock_screenshot_left then
            r.ImGui_SetNextWindowPos(ctx, main_window_pos_x - config.screenshot_window_width - 5, main_window_pos_y, r.ImGui_Cond_Always())
        else
            r.ImGui_SetNextWindowPos(ctx, main_window_pos_x + main_window_width + 5, main_window_pos_y, r.ImGui_Cond_Always())
        end
        r.ImGui_SetNextWindowSizeConstraints(ctx, 100, main_window_height, FLT_MAX, main_window_height)
    end

    r.ImGui_SetNextWindowSize(ctx, config.screenshot_window_width, main_window_height, r.ImGui_Cond_FirstUseEver())
    local visible, open = r.ImGui_Begin(ctx, "Screenshots##NoTitle", true, window_flags)
    if visible then
        r.ImGui_Text(ctx, "Screenshots: " .. (FILTER or ""))
        r.ImGui_Separator(ctx)
        
        local folders_category
        for i = 1, #CAT_TEST do
            if CAT_TEST[i].name == "FOLDERS" then
                folders_category = CAT_TEST[i].list
                break
            end
        end

        if folders_category then
            if r.ImGui_BeginCombo(ctx, "##FolderDropdown", selected_folder or "Select Folder") then
                if r.ImGui_Selectable(ctx, "No Folder", selected_folder == nil) then
                    selected_folder = nil
                end
                r.ImGui_Separator(ctx)
    
                for i = 1, #folders_category do
                    local is_selected = (selected_folder == folders_category[i].name)
                    if r.ImGui_Selectable(ctx, folders_category[i].name, is_selected) then
                        selected_folder = folders_category[i].name
                    end
                    if is_selected then
                        r.ImGui_SetItemDefaultFocus(ctx)
                    end
                end
                r.ImGui_EndCombo(ctx)
            end
        end
    
        if not config.resize_screenshots_with_window then
            _, screenshot_window_display_size = r.ImGui_SliderInt(ctx, "Screenshot Size", screenshot_window_display_size, 100, 500)
        end
        
        local available_width = r.ImGui_GetContentRegionAvail(ctx)
        local display_size = config.resize_screenshots_with_window and available_width or screenshot_window_display_size
        local num_columns = math.max(1, math.floor(available_width / display_size))
    
        if r.ImGui_BeginChild(ctx, "ScreenshotList", 0, 0) then
            if selected_folder then
                local filtered_plugins = {}
                for i = 1, #CAT_TEST do
                    if CAT_TEST[i].name == "FOLDERS" then
                        for j = 1, #CAT_TEST[i].list do
                            if CAT_TEST[i].list[j].name == selected_folder then
                                for k = 1, #CAT_TEST[i].list[j].fx do
                                    table.insert(filtered_plugins, CAT_TEST[i].list[j].fx[k])
                                end
                                break
                            end
                        end
                        break
                    end
                end

                if #filtered_plugins > 0 then
                    local column_width = available_width / num_columns
                    for i, fx_name in ipairs(filtered_plugins) do
                        local column = (i - 1) % num_columns
                        if column > 0 then
                            r.ImGui_SameLine(ctx)
                        end
                        r.ImGui_BeginGroup(ctx)
                        r.ImGui_PushItemWidth(ctx, column_width)

                        local safe_name = fx_name:gsub("[^%w%s-]", "_")
                        local screenshot_file = screenshot_path .. safe_name .. ".png"
                        if r.file_exists(screenshot_file) then
                            local texture = LoadSearchTexture(screenshot_file)
                            if texture and r.ImGui_ValidatePtr(texture, 'ImGui_Image*') then
                                local width, height = r.ImGui_Image_GetSize(texture)
                                if width and height then
                                    local aspect_ratio = height > 0 and width / height or 1
                                    local display_width = config.resize_screenshots_with_window and (column_width - 10) or screenshot_window_display_size
                                    local display_height = display_width / aspect_ratio
                                    
                                    if r.ImGui_ImageButton(ctx, "##"..fx_name, texture, display_width, display_height) then
                                        if TRACK then
                                            r.TrackFX_AddByName(TRACK, fx_name, false, -1000 - r.TrackFX_GetCount(TRACK))
                                        end
                                    end
                                    
                                    r.ImGui_PushTextWrapPos(ctx, r.ImGui_GetCursorPosX(ctx) + display_width)
                                    r.ImGui_Text(ctx, fx_name)
                                    r.ImGui_PopTextWrapPos(ctx)
                                else
                                    log_to_file("Ongeldige afmetingen voor texture: " .. tostring(texture))
                                    search_texture_cache[screenshot_file] = nil
                                end
                            else
                                log_to_file("Ongeldige texture voor fx: " .. fx_name)
                            end
                        end

                        r.ImGui_PopItemWidth(ctx)
                        r.ImGui_EndGroup(ctx)
                        
                        if column == num_columns - 1 then
                            r.ImGui_Separator(ctx)
                        end
                    end
                else
                    r.ImGui_Text(ctx, "Geen plugins gevonden voor de geselecteerde map.")
                end
            elseif screenshot_search_results and #screenshot_search_results > 0 then
                local column_width = available_width / num_columns
                for i, fx in ipairs(screenshot_search_results) do
                    local column = (i - 1) % num_columns
                    if column > 0 then
                        r.ImGui_SameLine(ctx)
                    end
                    r.ImGui_BeginGroup(ctx)
                    r.ImGui_PushItemWidth(ctx, column_width)
                    
                    local safe_name = fx.name:gsub("[^%w%s-]", "_")
                    local screenshot_file = screenshot_path .. safe_name .. ".png"
                    if r.file_exists(screenshot_file) then
                        local texture = LoadSearchTexture(screenshot_file)
                        if texture and r.ImGui_ValidatePtr(texture, 'ImGui_Image*') then
                            local width, height = r.ImGui_Image_GetSize(texture)
                            if width and height then
                                local aspect_ratio = height > 0 and width / height or 1
                                local display_width = config.resize_screenshots_with_window and (column_width - 10) or screenshot_window_display_size
                                local display_height = display_width / aspect_ratio
                                
                                if r.ImGui_ImageButton(ctx, "##"..fx.name, texture, display_width, display_height) then
                                    if TRACK then
                                        r.TrackFX_AddByName(TRACK, fx.name, false, -1000 - r.TrackFX_GetCount(TRACK)) 
                                    end 
                                end
                                r.ImGui_PushTextWrapPos(ctx, r.ImGui_GetCursorPosX(ctx) + display_width)
                                r.ImGui_Text(ctx, fx.name)
                                r.ImGui_PopTextWrapPos(ctx)
                            else
                                log_to_file("Ongeldige afmetingen voor texture: " .. tostring(texture))
                                search_texture_cache[screenshot_file] = nil
                            end
                        else
                            log_to_file("Ongeldige texture voor fx: " .. fx.name)
                        end
                    end
                    
                    r.ImGui_PopItemWidth(ctx)
                    r.ImGui_EndGroup(ctx)
                    
                    if column == num_columns - 1 then
                        r.ImGui_Separator(ctx)
                    end
                end
            else
                r.ImGui_Text(ctx, "Select a folder or enter a search term.")
            end
            r.ImGui_EndChild(ctx)
        end
    end
    -- Update de breedte van het screenshot venster
    config.screenshot_window_width = r.ImGui_GetWindowWidth(ctx)

    r.ImGui_End(ctx)
end

local function Filter_actions(filter_text)
    if old_filter == filter_text then return old_t end
    filter_text = Lead_Trim_ws(filter_text)
    local t = {}
    if filter_text == "" or not filter_text then return t end
    for i = 1, #FX_LIST_TEST do
        local name = FX_LIST_TEST[i]:lower()
        local found = true
        for word in filter_text:gmatch("%S+") do
            if not name:find(word:lower(), 1, true) then
                found = false
                break
            end
        end
        if found then t[#t + 1] = { score = FX_LIST_TEST[i]:len() - filter_text:len(), name = FX_LIST_TEST[i] } end
    end
    if #t >= 2 then SortTable(t, "score", "name") end
    old_t, old_filter = t, filter_text
    return t
end

local function FilterBox()
    r.ImGui_SameLine(ctx)
    r.ImGui_PushItemWidth(ctx, 82) 
    if r.ImGui_IsWindowAppearing(ctx) then
        r.ImGui_SetKeyboardFocusHere(ctx)
    end
    local changed
    changed, FILTER = r.ImGui_InputTextWithHint(ctx, '##input', "SEARCH FX", FILTER)
    if changed then
        -- We hoeven hier niets te doen, omdat we de zoekresultaten pas willen updaten bij het klikken op de knop   
    end
    r.ImGui_SameLine(ctx)
    if r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_Enter()) then
        screenshot_search_results = Filter_actions(FILTER)
        update_search_screenshots = true
        show_screenshot_window = true
        screenshot_window_interactive = true
        selected_folder = nil  -- Reset de geselecteerde map naar "Select Folder"
    end

    r.ImGui_SameLine(ctx)
    local button_height = r.ImGui_GetFrameHeight(ctx)
    if r.ImGui_Button(ctx, "X", 20, button_height) then
        FILTER = ""
        screenshot_search_results = nil  -- Reset de zoekresultaten wanneer het zoekveld wordt gewist
        show_screenshot_window = false -- Sluit het screenshotvenster wanneer het zoekveld wordt gewist
    end
    
    local filtered_fx = Filter_actions(FILTER)
    
    local window_height = r.ImGui_GetWindowHeight(ctx)
    local bottom_buttons_height = 30  -- Pas dit aan naar de werkelijke hoogte van je onderste knoppen
    local available_height = window_height - r.ImGui_GetCursorPosY(ctx) - bottom_buttons_height - 10  -- Extra marge

    if #filtered_fx ~= 0 then
        if r.ImGui_BeginChild(ctx, "##popupp", window_width, available_height) then
            for i = 1, #filtered_fx do
                if r.ImGui_Selectable(ctx, filtered_fx[i].name, i == ADDFX_Sel_Entry) then
                    r.TrackFX_AddByName(TRACK, filtered_fx[i].name, false, -1000 - r.TrackFX_GetCount(TRACK))
                    r.ImGui_CloseCurrentPopup(ctx)
                    LAST_USED_FX = filtered_fx[i].name
                end
                if r.ImGui_IsItemHovered(ctx) then
                    if filtered_fx[i].name ~= current_hovered_plugin then
                        current_hovered_plugin = filtered_fx[i].name
                        if config.show_screenshot_in_search then
                            LoadPluginScreenshot(current_hovered_plugin)
                        end
                    end
                    if not config.show_screenshot_in_search or not ScreenshotExists(filtered_fx[i].name) then
                        r.ImGui_BeginTooltip(ctx)
                        r.ImGui_Text(ctx, filtered_fx[i].name)
                        r.ImGui_EndTooltip(ctx)
                    end
                end
            end
            r.ImGui_EndChild(ctx)
        end
        if r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_Enter()) then
            if ADDFX_Sel_Entry and ADDFX_Sel_Entry > 0 and ADDFX_Sel_Entry <= #filtered_fx then
                r.TrackFX_AddByName(TRACK, filtered_fx[ADDFX_Sel_Entry].name, false, -1000 - r.TrackFX_GetCount(TRACK))
                LAST_USED_FX = filtered_fx[ADDFX_Sel_Entry].name
                ADDFX_Sel_Entry = nil
                FILTER = ''
                r.ImGui_CloseCurrentPopup(ctx)
            end
        elseif r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_UpArrow()) then
            ADDFX_Sel_Entry = (ADDFX_Sel_Entry or 1) - 1
            if ADDFX_Sel_Entry < 1 then ADDFX_Sel_Entry = #filtered_fx end
        elseif r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_DownArrow()) then
            ADDFX_Sel_Entry = (ADDFX_Sel_Entry or 0) + 1
            if ADDFX_Sel_Entry > #filtered_fx then ADDFX_Sel_Entry = 1 end
        end
    end
    if r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_Escape()) then
        FILTER = ''
        r.ImGui_CloseCurrentPopup(ctx)
    end
    return #filtered_fx ~= 0
end

local function DrawFxChains(tbl, path)
    local extension = ".RfxChain"
    path = path or ""
    local i = 1
    while i <= #tbl do
        local item = tbl[i]
        if type(item) == "table" and item.dir then
            r.ImGui_SetNextWindowSize(ctx, MAX_SUBMENU_WIDTH, 0)  
            r.ImGui_SetNextWindowBgAlpha(ctx, config.window_alpha)
            
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_PopupBg(), 0x000000FF) 
            if r.ImGui_BeginMenu(ctx, item.dir) then               
                DrawFxChains(item, table.concat({ path, os_separator, item.dir }))              
                r.ImGui_EndMenu(ctx)               
            end  
            reaper.ImGui_PopStyleColor(ctx)

        elseif type(item) ~= "table" then
            if r.ImGui_Selectable(ctx, item) then
                if ADD_FX_TO_ITEM then
                    local selected_item = r.GetSelectedMediaItem(0, 0)
                    if selected_item then
                        local take = r.GetActiveTake(selected_item)
                        if take then
                            r.TakeFX_AddByName(take, table.concat({ path, os_separator, item, extension }), 1)
                        end
                    end
                else
                    if TRACK then
                        r.TrackFX_AddByName(TRACK, table.concat({ path, os_separator, item, extension }), false,
                            -1000 - r.TrackFX_GetCount(TRACK))
                    end
                end
            end
            if r.ImGui_IsItemClicked(ctx, 1) then
                local mods = r.ImGui_GetKeyMods(ctx)
                if (mods & r.ImGui_Mod_Alt()) ~= 0 then
                    -- Alt+Rechtermuisklik: Hernoem
                    local retval, new_name = r.GetUserInputs("Rename FX Chain", 1, "New name:", item)
                    if retval then
                        local resource_path = r.GetResourcePath()
                        local fx_chains_path = resource_path .. "/FXChains"
                        local old_path = fx_chains_path .. "/" .. item .. extension
                        local new_path = fx_chains_path .. "/" .. new_name .. extension
                        if os.rename(old_path, new_path) then
                            tbl[i] = new_name
                            FX_LIST_TEST, CAT_TEST = MakeFXFiles()  -- Vernieuw de FX-lijst
                            r.ShowMessageBox("FX Chain renamed", "Success", 0)
                        else
                            r.ShowMessageBox("Could not rename FX Chain", "Error", 0)
                        end
                    end
                else
                    -- Rechtermuisklik: Verwijder
                    local resource_path = r.GetResourcePath()
                    local fx_chains_path = resource_path .. "/FXChains"
                    local file_path = fx_chains_path .. "/" .. item .. extension
                    if os.remove(file_path) then
                        table.remove(tbl, i)
                        FX_LIST_TEST, CAT_TEST = MakeFXFiles()  -- Vernieuw de FX-lijst
                        r.ShowMessageBox("FX Chain deleted", "Success", 0)
                        i = i - 1  -- Pas de index aan omdat we een element hebben verwijderd
                    else
                        r.ShowMessageBox("Could not delete FX Chain", "Error", 0)
                    end
                end
            end
                    end
                    i = i + 1
                end
            end
local function DrawTrackTemplates(tbl, path)
    local extension = ".RTrackTemplate"
    path = path or ""
    for i = 1, #tbl do
        if tbl[i].dir then
            r.ImGui_SetNextWindowSize(ctx, MAX_SUBMENU_WIDTH, 0)
            r.ImGui_SetNextWindowBgAlpha(ctx, config.window_alpha)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_PopupBg(), 0x000000FF)  
           
            if r.ImGui_BeginMenu(ctx, tbl[i].dir) then
                local cur_path = table.concat({ path, os_separator, tbl[i].dir })
                DrawTrackTemplates(tbl[i], cur_path)
                reaper.ImGui_PopStyleColor(ctx)
                r.ImGui_EndMenu(ctx)
            end
        end
        if type(tbl[i]) ~= "table" then
            if r.ImGui_Selectable(ctx, tbl[i]) then
                if TRACK then
                    local template_str = table.concat({ path, os_separator, tbl[i], extension })
                    LoadTemplate(template_str)
                    LoadTemplate(template_str, true)
                end
            end
        end
    end
end

local function DrawItems(tbl, main_cat_name)
   
        if menu_direction_right then
            r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_SelectableTextAlign(), 1, 0.5)
        end
        local items = tbl or {}
    for i = 1, #items do
       
        r.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_WindowRounding(), 7)
        r.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FrameRounding(), 3)       
        
        r.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_PopupBg(), config.background_color)
        r.ImGui_SetNextWindowBgAlpha(ctx, config.window_alpha)
        r.ImGui_SetNextWindowSize(ctx, FX_LIST_WIDTH, 0)
        
        if r.ImGui_BeginMenu(ctx, tbl[i].name) then
            for j = 1, #tbl[i].fx do
                if tbl[i].fx[j] then
                    local name = tbl[i].fx[j]
                    if main_cat_name == "ALL PLUGINS" and tbl[i].name ~= "INSTRUMENTS" then
                        name = name:gsub("^(%S+:)", "")
                    elseif main_cat_name == "DEVELOPER" then
                        name = name:gsub(' %(' .. Literalize(tbl[i].name) .. '%)', "")
                    end
                    if r.ImGui_Selectable(ctx, name) then
                        if ADD_FX_TO_ITEM then
                            AddFXToItem(tbl[i].fx[j])
                        else
                            if TRACK then
                                r.TrackFX_AddByName(TRACK, tbl[i].fx[j], false,
                                    -1000 - r.TrackFX_GetCount(TRACK))
                            end
                        end
                        LAST_USED_FX = tbl[i].fx[j]
                    end
                    if r.ImGui_IsItemHovered(ctx) then
                        if tbl[i].fx[j] ~= current_hovered_plugin then
                            current_hovered_plugin = tbl[i].fx[j]
                            LoadPluginScreenshot(current_hovered_plugin)
                        end
                    end
                    if r.ImGui_IsItemClicked(ctx, 1) then
                        MakeScreenshot(tbl[i].fx[j])
                    end
                end
            end
        r.ImGui_EndMenu(ctx)
        end
        reaper.ImGui_PopStyleVar(ctx, 2)
        reaper.ImGui_PopStyleColor(ctx)
    end
    if menu_direction_right then
        r.ImGui_PopStyleVar(ctx)
    end
end

local function DrawBottomButtons()
    if not TRACK then return end
    local windowHeight = r.ImGui_GetWindowHeight(ctx)
    local buttonHeight = 30
    r.ImGui_SetCursorPosY(ctx, windowHeight - buttonHeight)
    
    r.ImGui_Separator(ctx)
    local mute_color = IsMuted(TRACK) and 0xFF0000FF or 0x4CAF50FF
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), mute_color)
    if r.ImGui_Button(ctx, "MUTE", 40, 15) then
    ToggleMute(TRACK)
    end
    r.ImGui_PopStyleColor(ctx)

    r.ImGui_SameLine(ctx)
    local solo_color = IsSoloed(TRACK) and 0xFFFF00FF or 0x4CAF50FF
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), solo_color)
    if r.ImGui_Button(ctx, "SOLO", 40, 15) then
    ToggleSolo(TRACK)
    end
    r.ImGui_PopStyleColor(ctx)

    r.ImGui_SameLine(ctx)
    local arm_color = IsArmed(TRACK) and 0xFF0000FF or 0x4CAF50FF
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), arm_color)
    if r.ImGui_Button(ctx, "ARM", 40, 15) then
    ToggleArm(TRACK)
    end
    r.ImGui_PopStyleColor(ctx)
                
    r.ImGui_Separator(ctx)
end

local BUTTON_HEIGHT = 15
local function ShowTrackFX()
    if not TRACK then return end
    
    r.ImGui_Text(ctx, "FX on Track:")
    local availWidth, availHeight = r.ImGui_GetContentRegionAvail(ctx)
    local listHeight = availHeight - BUTTON_HEIGHT
    if r.ImGui_BeginChild(ctx, "TrackFXList", -1, listHeight) then

        local fx_count = r.TrackFX_GetCount(TRACK)
        if fx_count > 0 then
            for i = 0, fx_count - 1 do
                local retval, fx_name = r.TrackFX_GetFXName(TRACK, i, "")
                local is_open = r.TrackFX_GetFloatingWindow(TRACK, i)
                if r.ImGui_Selectable(ctx, fx_name) then
                    if is_open then
                        r.TrackFX_Show(TRACK, i, 2)
                    else
                        r.TrackFX_Show(TRACK, i, 3)
                    end
                end
                if r.ImGui_IsItemClicked(ctx, 1) then
                    r.TrackFX_Delete(TRACK, i)
                    break
                end
            end
        else
        r.ImGui_Text(ctx, "No FX on Track")
        end
     
        r.ImGui_EndChild(ctx)
    end
end

local function ShowItemFX()
    local item = r.GetSelectedMediaItem(0, 0)
    if not item then return end
    
    local take = r.GetActiveTake(item)
    if not take then return end
    
    r.ImGui_Text(ctx, "FX on Item:")
    local availWidth, availHeight = r.ImGui_GetContentRegionAvail(ctx)
    local listHeight = availHeight - BUTTON_HEIGHT
    if r.ImGui_BeginChild(ctx, "ItemFXList", -1, listHeight) then

        local fx_count = r.TakeFX_GetCount(take)
        if fx_count > 0 then
            for i = 0, fx_count - 1 do
                local retval, fx_name = r.TakeFX_GetFXName(take, i, "")
                local is_open = r.TakeFX_GetFloatingWindow(take, i)
                if r.ImGui_Selectable(ctx, fx_name) then
                    if is_open then
                        r.TakeFX_Show(take, i, 2)
                    else
                        r.TakeFX_Show(take, i, 3)
                    end
                end
                if r.ImGui_IsItemClicked(ctx, 1) then
                    r.TakeFX_Delete(take, i)
                    break
                end
            end
        else
            r.ImGui_Text(ctx, "No FX on Item")
        end

        r.ImGui_EndChild(ctx)
    end
end

local function GetTrackType(track)
    local audio_count = 0
    local midi_count = 0
    local is_folder = r.GetMediaTrackInfo_Value(track, "I_FOLDERDEPTH") > 0
    local is_child = r.GetParentTrack(track) ~= nil
    
    local item_count = r.CountTrackMediaItems(track)
    for i = 0, item_count - 1 do
        local item = r.GetTrackMediaItem(track, i)
        local take = r.GetActiveTake(item)
        if take then
            if r.TakeIsMIDI(take) then
                midi_count = midi_count + 1
            else
                audio_count = audio_count + 1
            end
        end
    end
    local track_type = ""
    if is_folder then
        track_type = "Folder "
    elseif is_child then
        track_type = "Child "
    end
    
    if audio_count > 0 and midi_count > 0 then
        return track_type .. "Mixed"
    elseif midi_count > 0 then
        return track_type .. "MIDI"
    elseif audio_count > 0 then
        return track_type .. "Audio"
    else
        return track_type .. "Empty"
    end
end

-------------------------------------------------------------------
function Frame()
    local search = FilterBox()
    if search then return end
    for i = 1, #CAT_TEST do
        r.ImGui_SetNextWindowSize(ctx, MAX_SUBMENU_WIDTH, 0)
        r.ImGui_SetNextWindowBgAlpha(ctx, config.window_alpha)
        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowRounding(), 7)
        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), 3)
        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_PopupRounding(), 7)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_PopupBg(), config.background_color)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_WindowBg(), config.background_color)

        if r.ImGui_BeginMenu(ctx, CAT_TEST[i].name) then
            if CAT_TEST[i].name == "FX CHAINS" then
                DrawFxChains(CAT_TEST[i].list)
            elseif CAT_TEST[i].name == "TRACK TEMPLATES" then
                DrawTrackTemplates(CAT_TEST[i].list)
            else
                DrawItems(CAT_TEST[i].list, CAT_TEST[i].name)
             end
            r.ImGui_EndMenu(ctx)
        end
        r.ImGui_PopStyleVar(ctx, 3)
        r.ImGui_PopStyleColor(ctx, 2)
    end

    if r.ImGui_Selectable(ctx, "CONTAINER") then
        r.TrackFX_AddByName(TRACK, "Container", false,
            -1000 - r.TrackFX_GetCount(TRACK))
        LAST_USED_FX = "Container"
    end
    if r.ImGui_Selectable(ctx, "VIDEO PROCESSOR") then
        r.TrackFX_AddByName(TRACK, "Video processor", false,
            -1000 - r.TrackFX_GetCount(TRACK))
        LAST_USED_FX = "Video processor"
    end
    if LAST_USED_FX then
        if r.ImGui_Selectable(ctx, "RECENT: " .. LAST_USED_FX) then
            r.TrackFX_AddByName(TRACK, LAST_USED_FX, false,
                -1000 - r.TrackFX_GetCount(TRACK))
        end
    end

    r.ImGui_Separator(ctx)
    if ADD_FX_TO_ITEM then
        ShowItemFX()
    else
        ShowTrackFX()
    end
    if not r.ImGui_IsAnyItemHovered(ctx) then
        current_hovered_plugin = nil
    end
end
-----------------------------------------------------------------
function Main()
    local prev_track = TRACK
    TRACK = r.GetSelectedTrack(0, 0)

    if TRACK and TRACK ~= prev_track then
        InitializeSettingsIcon()
        if config.auto_refresh_fx_list then
            FX_LIST_TEST, CAT_TEST = MakeFXFiles()
        end
    elseif not TRACK then
        settings_icon = nil
    end
    ProcessTextureLoadQueue()

    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FrameRounding(), 2)
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_WindowRounding(), 7)
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_ItemSpacing(), 3, 3)

    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_WindowBg(), config.background_color)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), r.ImGui_ColorConvertDouble4ToU32(config.text_gray/255, config.text_gray/255, config.text_gray/255, 1))
    r.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), config.button_background_color)
    r.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), config.button_hover_color)
    r.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Tab(), dark_gray)
    r.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_TabHovered(), hover_gray)
    r.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBg(), config.frame_bg_color)
    r.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBgHovered(), config.frame_bg_hover_color)
    r.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBgActive(), config.frame_bg_active_color)
    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_PopupBg(), config.dropdown_bg_color)
    r.ImGui_PushFont(ctx, NormalFont)

    r.ImGui_SetNextWindowBgAlpha(ctx, config.window_alpha)
    r.ImGui_SetNextWindowSizeConstraints(ctx, 140, 340, 16384, 16384)
          
    handleDocking() 
    local visible, open = r.ImGui_Begin(ctx, 'TK FX BROWSER', true, window_flags)
    dock = r.ImGui_GetWindowDockID(ctx)

    if visible then
        if bulk_screenshot_progress > 0 and bulk_screenshot_progress < 1 then
            local progress_text = string.format("Loading %d/%d (%.1f%%)", loaded_fx_count, total_fx_count, bulk_screenshot_progress * 100)
            r.ImGui_ProgressBar(ctx, bulk_screenshot_progress, -1, 0, progress_text)
        end

        if TRACK then
            local track_color, text_color = GetTrackColorAndTextColor(TRACK)
            local track_name = GetTrackName(TRACK)
            local track_type = GetTrackType(TRACK)
         
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ChildBg(), track_color)
            r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_ChildRounding(), 4)
            if r.ImGui_BeginChild(ctx, "TrackInfo", 125, 50, r.ImGui_WindowFlags_NoScrollbar()) then
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Text(), text_color)
                r.ImGui_PushFont(ctx, LargeFont)

                local text_width = r.ImGui_CalcTextSize(ctx, track_name)
                local window_width = r.ImGui_GetWindowWidth(ctx)
                local pos_x = (window_width - text_width) * 0.5
                local window_height = r.ImGui_GetWindowHeight(ctx)
                local text_height = r.ImGui_GetTextLineHeight(ctx)
                local pos_y = (window_height - text_height) * 0.25

                r.ImGui_SetCursorPos(ctx, pos_x, pos_y)
                r.ImGui_Text(ctx, track_name)
                
                local type_text_width = r.ImGui_CalcTextSize(ctx, track_type)
                local type_pos_x = (window_width - type_text_width) * 0.5
                local type_pos_y = pos_y + text_height

                r.ImGui_SetCursorPos(ctx, type_pos_x, type_pos_y)
                r.ImGui_Text(ctx, track_type)

                r.ImGui_PopFont(ctx)
                r.ImGui_PopStyleColor(ctx)
                r.ImGui_EndChild(ctx)
            end
            r.ImGui_PopStyleVar(ctx)
            r.ImGui_PopStyleColor(ctx)

            if r.ImGui_Button(ctx, "Scan", 40) then
                FX_LIST_TEST, CAT_TEST = MakeFXFiles()
            end
        
            r.ImGui_SameLine(ctx)
            if r.ImGui_Button(ctx, SHOW_PREVIEW and "On" or "Off", 40) then
                SHOW_PREVIEW = not SHOW_PREVIEW
                if SHOW_PREVIEW and current_hovered_plugin then
                    LoadPluginScreenshot(current_hovered_plugin)
                end
            end

            r.ImGui_SameLine(ctx)
            r.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0xFF0000FF)
            r.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0xFF5555FF)
            r.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), 0xFF0000FF)
            if r.ImGui_Button(ctx, 'Quit', 40) then 
                open = false 
            end
            reaper.ImGui_PopStyleColor(ctx, 3)

            if r.ImGui_Button(ctx, ADD_FX_TO_ITEM and "Item" or "Track", 40) then
                ADD_FX_TO_ITEM = not ADD_FX_TO_ITEM
            end
            reaper.ImGui_SameLine(ctx)

            if WANT_REFRESH then
                WANT_REFRESH = nil
                UpdateChainsTrackTemplates(CAT)
            end
            if r.ImGui_Button(ctx, "FXChn", 40) then
                CreateFXChain()
            end

            r.ImGui_SameLine(ctx)
            if r.ImGui_Button(ctx, "Dock", 40) then
                change_dock = true 
            end
            
            if reaper.ImGui_Button(ctx, START and "Stop" or "Bulk", 40) then
                StartBulkScreenshot()
            end

            r.ImGui_SameLine(ctx)
            if reaper.ImGui_Button(ctx, "Reset", 40) then
                show_confirm_clear = true
            end

            r.ImGui_SameLine(ctx)
            if reaper.ImGui_Button(ctx, "Folder", 40) then
                OpenScreenshotsFolder()
            end

            if settings_icon then
                local icon_size = 10 
                if r.ImGui_ImageButton(ctx, "SettingsButton", settings_icon, icon_size, icon_size) then
                    show_config = true
                end
            end

            if show_config then
                show_config = ShowConfigWindow()
            end

            if show_confirm_clear then
                ShowConfirmClearPopup()
            end

            Frame()
            if config.show_screenshot_window then
                ShowScreenshotWindow()
            end

        else
            r.ImGui_Text(ctx, "NO TRACK SELECTED")
        end

        if SHOW_PREVIEW and current_hovered_plugin then 
            ShowPluginScreenshot() 
        end
        DrawBottomButtons()

        if check_esc_key() then open = false end
        r.ImGui_End(ctx)
    end

    r.ImGui_PopFont(ctx)
    r.ImGui_PopStyleVar(ctx, 3)
    r.ImGui_PopStyleColor(ctx, 10)
    if open then
        r.defer(Main)
    end
end
r.defer(Main)