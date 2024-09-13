-- @description TK FX BROWSER
-- @version 0.1.3
-- @author TouristKiller
-- @about
--   #  A MOD of Sexan's FX Browser 


local r = reaper

-- Pad en module instellingen
local os_separator = package.config:sub(1, 1)
local script_path = debug.getinfo(1, "S").source:match("@?(.*[/\\])")
package.path = script_path .. "?.lua;"
require("Sexan_FX_Browser")

-- Pad definities
local screenshot_path = script_path .. "Screenshots" .. os_separator

-- GUI instellingen
local ctx = r.ImGui_CreateContext('TK FX BROWSER')

local window_flags = r.ImGui_WindowFlags_NoTitleBar()
local MAX_SUBMENU_WIDTH = 250
local font_size = 11
local normal_font = reaper.ImGui_CreateFont('Arial', font_size)
r.ImGui_Attach(ctx, normal_font)

local dark_gray = 0x303030FF
local hover_gray = 0x303030FF
local active_gray = 0x303030FF

-- Globale variabelen
local FX_BROWSER_OPEN = true
local SHOW_PREVIEW = true
local TRACK, LAST_USED_FX, FILTER, ADDFX_Sel_Entry
local FX_LIST_TEST, CAT_TEST = ReadFXFile()
if not FX_LIST_TEST or not CAT_TEST then
    FX_LIST_TEST, CAT_TEST = MakeFXFiles()
end

local old_t = {}
local old_filter = ""

local current_hovered_plugin = nil
local screenshot_texture = nil
local screenshot_width, screenshot_height = 0, 0


--------------------------------------------------------------
local function apply_style()
   
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FrameRounding(), 3)
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_WindowRounding(), 7)
    reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_ItemSpacing(), 3, 3)

    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_WindowBg(), 0x000000FF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0xFFFFFFFF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), dark_gray)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), hover_gray)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), active_gray)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Tab(), dark_gray)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_TabHovered(), hover_gray)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBg(), dark_gray)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBgHovered(), hover_gray)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBgActive(), active_gray)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_PopupBg(), 0x000000FF)
end

local function remove_style()
    reaper.ImGui_PopStyleVar(ctx, 3)
    reaper.ImGui_PopStyleColor(ctx, 11)
end

local function LoadTexture(file)
    return r.ImGui_CreateImage(file)
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


local function GetBounds(hwnd)
    local _, left, top, right, bottom = r.JS_Window_GetRect(hwnd)
    return left, top, right-left, bottom-top
end

local function CapWindowToPng(hwnd, filename, win10)
    local srcx, srcy = 0, 100
    local srcDC = r.JS_GDI_GetWindowDC(hwnd)
    local _, _, w, h = GetBounds(hwnd)

    if win10 then 
        srcx, srcy = 0, 100
        w, h = w-0, h-0
    end

    h = h - 100

    local destBmp = r.JS_LICE_CreateBitmap(true, w, h + 100)
    local destDC = r.JS_LICE_GetDC(destBmp)
    r.JS_GDI_Blit(destDC, 0, 0, srcDC, srcx, srcy, w, h + 100)
    r.JS_LICE_WritePNG(filename, destBmp, false)
    r.JS_GDI_ReleaseDC(hwnd, srcDC)
    r.JS_LICE_DestroyBitmap(destBmp)
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

local function GetTrackColor(track)
    local color = r.GetTrackColor(track)
    if color == 0 then
        return r.ImGui_ColorConvertDouble4ToU32(1, 1, 1, 1)
    else
        local red = (color & 0xFF) / 255
        local green = ((color >> 8) & 0xFF) / 255
        local blue = ((color >> 16) & 0xFF) / 255
        return r.ImGui_ColorConvertDouble4ToU32(red, green, blue, 1)
    end
end

local function GetTrackName(track)
    local _, name = r.GetTrackName(track)
    return name
end

local function MakeScreenshot(plugin_name)
    local fx_index = r.TrackFX_AddByName(TRACK, plugin_name, false, -1)
    r.TrackFX_Show(TRACK, fx_index, 3)
    
    local wait_time = 1000

    local function CaptureScreenshot()
        local hwnd = r.TrackFX_GetFloatingWindow(TRACK, fx_index)
        if hwnd then
            local safe_name = plugin_name:gsub("[^%w%s-]", "_")
            local filename = screenshot_path .. safe_name .. ".png"
            CapWindowToPng(hwnd, filename, true)
            
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

    local function Timer()
        local start_time = r.time_precise()
        local function Wait()
            if r.time_precise() - start_time >= wait_time / 1000 then
                CaptureScreenshot()
            else
                r.defer(Wait)
            end
        end
        Wait()
    end

    Timer()
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
        local display_width = 250
        local display_height = display_width * (screenshot_height / screenshot_width)
        
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
        
        r.ImGui_SetNextWindowSize(ctx, display_width, display_height)
        r.ImGui_SetNextWindowPos(ctx, window_pos_x, window_pos_y)
        r.ImGui_SetNextWindowBgAlpha(ctx, 0.75)
        reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FrameRounding(), 7)
        reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_WindowRounding(), 14)
        reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_PopupRounding(), 7)
        reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_ItemSpacing(), 1, 1)
        reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_WindowPadding(), 3,3)
        reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_WindowBorderSize(), 7)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_WindowBg(), 0x000000FF)      
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBg(), 0x000000FF)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBgHovered(), 0x000000FF)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBgActive(), 0x000000FF)
        reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Border(), 0x000000FF)
        
        if r.ImGui_Begin(ctx, "Plugin Screenshot", true, r.ImGui_WindowFlags_NoTitleBar() | r.ImGui_WindowFlags_NoCollapse() | r.ImGui_WindowFlags_NoFocusOnAppearing() | r.ImGui_WindowFlags_NoDocking() | r.ImGui_WindowFlags_NoScrollbar() | r.ImGui_WindowFlags_TopMost() | r.ImGui_WindowFlags_NoResize()) then
            r.ImGui_Image(ctx, screenshot_texture, display_width, display_height)
            r.ImGui_End(ctx)
        end
        
        reaper.ImGui_PopStyleVar(ctx, 6)
        reaper.ImGui_PopStyleColor(ctx, 5)
    end
end

local function LoadTemplate(template, replace)
    local track_template_path = r.GetResourcePath() .. "/TrackTemplates" .. template
    if replace then
        local chunk = GetFileContext(track_template_path)
        r.SetTrackStateChunk(TRACK, chunk, true)
    else
        r.Main_openProject(track_template_path)
    end
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
    local MAX_FX_SIZE = 84
    
    if r.ImGui_IsWindowAppearing(ctx) then
        r.ImGui_SetKeyboardFocusHere(ctx)
    end
    local changed
    r.ImGui_PushItemWidth(ctx, MAX_FX_SIZE)
    changed, FILTER = r.ImGui_InputTextWithHint(ctx, '##input', "SEARCH FX", FILTER)
    if changed then
        print("Filter text changed: " .. FILTER)
    end
    local filtered_fx = Filter_actions(FILTER)
    local filter_h = #filtered_fx == 0 and 0 or (#filtered_fx > 40 and 20 * 17 or (17 * #filtered_fx))
    ADDFX_Sel_Entry = SetMinMax(ADDFX_Sel_Entry or 1, 1, #filtered_fx)
    if #filtered_fx ~= 0 then
        local window_width = r.ImGui_GetWindowWidth(ctx)
        if r.ImGui_BeginChild(ctx, "##popupp", window_width, filter_h) then
            for i = 1, #filtered_fx do
                if r.ImGui_Selectable(ctx, filtered_fx[i].name, i == ADDFX_Sel_Entry) then
                    r.TrackFX_AddByName(TRACK, filtered_fx[i].name, false, -1000 - r.TrackFX_GetCount(TRACK))
                    r.ImGui_CloseCurrentPopup(ctx)
                    LAST_USED_FX = filtered_fx[i].name
                end
                if r.ImGui_IsItemHovered(ctx) then
                    r.ImGui_BeginTooltip(ctx)
                    r.ImGui_Text(ctx, filtered_fx[i].name)
                    r.ImGui_EndTooltip(ctx)
                end
            end
            r.ImGui_EndChild(ctx)
        end
        if r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_Enter()) then
            r.TrackFX_AddByName(TRACK, filtered_fx[ADDFX_Sel_Entry].name, false, -1000 - r.TrackFX_GetCount(TRACK))
            LAST_USED_FX = filtered_fx[ADDFX_Sel_Entry].name
            ADDFX_Sel_Entry = nil
            FILTER = ''
            r.ImGui_CloseCurrentPopup(ctx)
        elseif r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_UpArrow()) then
            ADDFX_Sel_Entry = ADDFX_Sel_Entry - 1
        elseif r.ImGui_IsKeyPressed(ctx, r.ImGui_Key_DownArrow()) then
            ADDFX_Sel_Entry = ADDFX_Sel_Entry + 1
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
    for i = 1, #tbl do
        if tbl[i].dir then
            r.ImGui_SetNextWindowSize(ctx, MAX_SUBMENU_WIDTH, 0)  
            r.ImGui_SetNextWindowBgAlpha(ctx, 0.75)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_PopupBg(), 0x000000FF) 
           
            if r.ImGui_BeginMenu(ctx, tbl[i].dir) then               
                DrawFxChains(tbl[i], table.concat({ path, os_separator, tbl[i].dir }))              
                r.ImGui_EndMenu(ctx)               
            end  
            reaper.ImGui_PopStyleColor(ctx)
        end
        if type(tbl[i]) ~= "table" then
            if r.ImGui_Selectable(ctx, tbl[i]) then
                if TRACK then
                    r.TrackFX_AddByName(TRACK, table.concat({ path, os_separator, tbl[i], extension }), false,
                        -1000 - r.TrackFX_GetCount(TRACK))
                end
            end
        end
    end
end

local function DrawTrackTemplates(tbl, path)
    local extension = ".RTrackTemplate"
    path = path or ""
    for i = 1, #tbl do
        if tbl[i].dir then
            r.ImGui_SetNextWindowSize(ctx, MAX_SUBMENU_WIDTH, 0)
            r.ImGui_SetNextWindowBgAlpha(ctx, 0.75)
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
       
        reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_WindowRounding(), 7)
        reaper.ImGui_PushStyleVar(ctx, reaper.ImGui_StyleVar_FrameRounding(), 3)
        r.ImGui_SetNextWindowBgAlpha(ctx, 0.75)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_PopupBg(), 0x000000FF) 

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
                        if TRACK then
                            r.TrackFX_AddByName(TRACK, tbl[i].fx[j], false,
                                -1000 - r.TrackFX_GetCount(TRACK))
                            LAST_USED_FX = tbl[i].fx[j]
                        end
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

local function ShowTrackFX()
    if not TRACK then return end
    
    r.ImGui_Text(ctx, "FX on Track:")
    if r.ImGui_BeginChild(ctx, "TrackFXList", -1, 0) then
        apply_style()
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
        remove_style()
        r.ImGui_EndChild(ctx)
    end
end

function Frame()

    if r.ImGui_Button(ctx, "SCAN", 40) then
            FX_LIST_TEST, CAT_TEST = MakeFXFiles()
    end
    r.ImGui_SameLine(ctx)
    local search = FilterBox()
    if search then return end
    for i = 1, #CAT_TEST do
        r.ImGui_SetNextWindowSize(ctx, MAX_SUBMENU_WIDTH, 0)
        r.ImGui_SetNextWindowBgAlpha(ctx, 0.75)
        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_WindowRounding(), 7)
        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_FrameRounding(), 3)
        r.ImGui_PushStyleVar(ctx, r.ImGui_StyleVar_PopupRounding(), 7)
        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_WindowBg(), 0x000000FF)


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
        r.ImGui_PopStyleColor(ctx)

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
    ShowTrackFX()
    
    if not r.ImGui_IsAnyItemHovered(ctx) then
        current_hovered_plugin = nil
    end
   
end
function Main()
    if not FX_BROWSER_OPEN then return end
    
    TRACK = r.GetSelectedTrack(0, 0)
   
    local font_pushed = false
    if r.ImGui_ValidatePtr(ctx, 'ImGui_Context*') then
        r.ImGui_PushFont(ctx, normal_font)
        font_pushed = true
    else
        ctx = r.ImGui_CreateContext('TK FX BROWSER')
        r.ImGui_Attach(ctx, normal_font)
    end

    apply_style()  
    r.ImGui_SetNextWindowBgAlpha(ctx, 0.75)
    reaper.ImGui_SetNextWindowSizeConstraints(ctx, 140, 200, 16384, 16384)
        

    local visible, open = r.ImGui_Begin(ctx, 'TK FX BROWSER', true, window_flags)
    if visible then
        if TRACK then
            local track_color = GetTrackColor(TRACK)
            local track_name = GetTrackName(TRACK)
            
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_ChildBg(), track_color)
            if r.ImGui_BeginChild(ctx, "TrackInfo", 125, 30) then
                local text_width = r.ImGui_CalcTextSize(ctx, track_name)
                local window_width = r.ImGui_GetWindowWidth(ctx)
                local pos_x = (window_width - text_width) * 0.5
                local window_height = r.ImGui_GetWindowHeight(ctx)
                local text_height = r.ImGui_GetTextLineHeight(ctx)
                local pos_y = (window_height - text_height) * 0.5

                r.ImGui_SetCursorPos(ctx, pos_x, pos_y)
                r.ImGui_Text(ctx, track_name)
                r.ImGui_EndChild(ctx)
            end
            r.ImGui_PopStyleColor(ctx)

            if WANT_REFRESH then
                WANT_REFRESH = nil
                UpdateChainsTrackTemplates(CAT)
            end
            
            
            if r.ImGui_Button(ctx, SHOW_PREVIEW and "Screenshot OFF" or "Screenshot ON" ,84) then
                SHOW_PREVIEW = not SHOW_PREVIEW
                if SHOW_PREVIEW and current_hovered_plugin then
                    LoadPluginScreenshot(current_hovered_plugin)
                end
            end
            
            
            -- Quit knop
            local window_width = reaper.ImGui_GetWindowWidth(ctx)
            reaper.ImGui_SameLine(ctx)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0xFF0000FF)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0xFF5555FF)
            reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), 0xFF0000FF)
            if reaper.ImGui_Button(ctx, 'Quit', 40) then open = false end
            reaper.ImGui_PopStyleColor(ctx, 3)

            Frame()
        else
            r.ImGui_Text(ctx, "SELECT TRACK")
        end
        if SHOW_PREVIEW and current_hovered_plugin then 
            ShowPluginScreenshot() 
        end
        r.ImGui_End(ctx)
    end

    
    remove_style()  

    if font_pushed then
        r.ImGui_PopFont(ctx)
    end

    if open then
        r.defer(Main)
    else
        FX_BROWSER_OPEN = false
    end
end


r.defer(Main)
            