-- @author TouristKiller
-- @version 0.1.0
-- @changelog
--   - Initial release: Standalone FX search widget for transport bar
-- @about
--   Quick FX search widget for transport. Search plugins and add them to selected track.
--   Independent from TK_RAW_fx browser. Uses Sexan's FX Parser.

local r = reaper
local script_path = debug.getinfo(1, "S").source:match("@?(.*[/\\])")
local os_separator = package.config:sub(1, 1)
package.path = script_path .. "?.lua;"

local handler = require("TK_Widget_Handler")

-- FX Parser integration
local SEXAN_PARSER = r.GetResourcePath() .. '/Scripts/Sexan_Scripts/FX/Sexan_FX_Browser_ParserV7.lua'
local ALL_FX = {}
local FX_LOADED = false
local LOADING_FX = false

-- Search state
local search_query = ""
local filtered_results = {}
local selected_index = 1
local show_popup = false
local popup_opened_this_frame = false
local last_added_fx = ""
local last_added_time = 0

-- Default settings
local default_settings = {
    overlay_enabled = true,
    rel_pos_x = 0.5,
    rel_pos_y = 0.3,
    font_size = 12,
    show_background = true,
    widget_width = 350,
    widget_height = 60,
    use_tk_transport_theme = true,
    current_preset = "",
    window_rounding = 12.0,
    frame_rounding = 6.0,
    popup_rounding = 6.0,
    grab_rounding = 12.0,
    grab_min_size = 8.0,
    button_border_size = 1.0,
    border_size = 1.0,
    current_font = "Arial",
    background_color = 0x33333366,
    text_color = 0xFFFFFFFF,
    button_color = 0x44444477,
    button_hover_color = 0x55555588,
    button_active_color = 0x666666AA,
    border_color = 0x444444FF,
    frame_bg = 0x333333FF,
    frame_bg_hovered = 0x444444FF,
    frame_bg_active = 0x555555FF,
    slider_grab = 0x999999FF,
    slider_grab_active = 0xAAAAAAFF,
    check_mark = 0x999999FF,
    last_pos_x = 100,
    last_pos_y = 100,
    max_results = 50,
    search_width = 250,
    results_height = 200
}

local widget = handler.init("FX Search Widget", default_settings)
widget.SetWidgetTitle("FX Search")
widget.LoadSettings("FX_SEARCH_WIDGET")

-- Utility functions
local function safe_lower(s)
    return tostring(s or ''):lower()
end

local function file_exists(path)
    return r.file_exists(path)
end

local function ends_with(str, suffix)
    str = tostring(str or '')
    suffix = tostring(suffix or '')
    return suffix ~= '' and str:sub(-#suffix) == suffix or false
end

local function is_instrument(entry)
    local t = entry.type or ''
    local add = entry.addname or ''
    if type(t) == 'string' and ends_with(t, 'i') then return true end
    if add:find('^VSTi%s*:') or add:find('^CLAPi%s*:') then return true end
    return false
end

local function infer_type_from_add(add)
    local t = add:match('^%s*([%w_]+)%s*:')
    return t or ''
end

local function get_addname(entry)
    return entry.addname or entry.ADDNAME or entry.AddName or entry.name or entry.NAME or ''
end

local function extract_fx_entry(entry)
    local t = type(entry)
    if t == 'string' then return entry, entry end
    if t == 'table' then
        local name = entry.name or entry.fxname or entry.fxName or entry.fname or entry.FX_NAME or entry.NAME or entry[1]
        local add  = entry.addname or entry.fullname or entry.name or entry.fxname or entry[2] or entry.ADDNAME or name
        if name or add then return tostring(name or add), tostring(add or name) end
    end
    return nil, nil
end

local function flatten_plugins(obj, items, seen, depth)
    if depth > 6 then return end
    local t = type(obj)
    if t == 'table' then
        local disp, add = extract_fx_entry(obj)
        if disp and add and not seen[add] then
            items[#items+1] = { name = disp, addname = add }
            seen[add] = true
        end
        for _, v in pairs(obj) do
            if type(v) == 'table' or type(v) == 'string' then
                flatten_plugins(v, items, seen, depth + 1)
            end
        end
    elseif t == 'string' then
        if not seen[obj] then items[#items+1] = { name = obj, addname = obj }; seen[obj] = true end
    end
end

-- Load FX list using Sexan parser
local function load_fx_list()
    if not file_exists(SEXAN_PARSER) then
        if r.ReaPack_BrowsePackages then
            r.ShowMessageBox('Sexan FX Browser Parser V7 is missing. Opening ReaPack to install.', 'Missing dependency', 0)
            r.ReaPack_BrowsePackages('"sexan fx browser parser v7"')
        else
            r.ShowMessageBox('Sexan FX Browser Parser V7 not found. Please install via ReaPack.', 'Missing dependency', 0)
        end
        return false
    end
    
    local ok, err = pcall(dofile, SEXAN_PARSER)
    if not ok then 
        r.ShowMessageBox('Error loading Sexan parser: ' .. tostring(err), 'FX Search', 0)
        return false 
    end
    
    -- Get FX table from parser
    local list = nil
    if type(_G.GetFXTbl) == 'function' then
        local ok_fx, res = pcall(_G.GetFXTbl)
        if ok_fx then list = res end
    end
    
    if not list and type(_G.ReadFXFile) == 'function' then
        local FX_LIST = _G.ReadFXFile()
        if not FX_LIST and type(_G.MakeFXFiles) == 'function' then
            FX_LIST = _G.MakeFXFiles()
        end
        if type(_G.GetFXTbl) == 'function' then
            local ok_fx, res = pcall(_G.GetFXTbl)
            if ok_fx then list = res end
        end
    end
    
    if not list then
        r.ShowMessageBox('Could not load plugin list from Sexan parser.', 'FX Search', 0)
        return false
    end
    
    -- Flatten and filter
    local flat, seen = {}, {}
    flatten_plugins(list, flat, seen, 0)
    
    local out = {}
    for _, it in ipairs(flat) do
        local add = get_addname(it)
        if add and add ~= '' then
            local tp = infer_type_from_add(add)
            -- Skip instruments - we want effects only for tracks
            if not is_instrument({ type = tp, addname = add }) then
                out[#out+1] = { 
                    name = it.name or add, 
                    addname = add, 
                    type = tp 
                }
            end
        end
    end
    
    -- Sort by name
    table.sort(out, function(a,b) 
        return safe_lower(a.name) < safe_lower(b.name) 
    end)
    
    ALL_FX = out
    FX_LOADED = true
    return true
end

-- Filter FX based on search query
local function filter_fx()
    if not FX_LOADED or #ALL_FX == 0 then
        return {}
    end
    
    local q = safe_lower(search_query)
    if q == '' then
        return {}
    end
    
    local results = {}
    for _, e in ipairs(ALL_FX) do
        if #results >= widget.settings.max_results then
            break
        end
        
        local name_match = safe_lower(e.name):find(q, 1, true)
        local add_match = safe_lower(e.addname):find(q, 1, true)
        
        if name_match or add_match then
            results[#results+1] = e
        end
    end
    
    return results
end

-- Add FX to selected track
local function add_fx_to_selected_track(addname)
    if not addname or addname == '' then return false end
    
    local track = r.GetSelectedTrack(0, 0)
    if not track then
        r.ShowMessageBox('No track selected', 'FX Search', 0)
        return false
    end
    
    local fx_index = r.TrackFX_AddByName(track, addname, false, -1)
    if fx_index >= 0 then
        -- Store last added for status display
        last_added_fx = addname
        last_added_time = r.time_precise and r.time_precise() or os.clock()
        -- Optionally open FX window
        -- r.TrackFX_Show(track, fx_index, 3)
        return true
    end
    
    return false
end

-- Main UI drawing function
function ShowFXSearch(h)
    -- Load FX list if not loaded yet (on first use)
    if not FX_LOADED and not LOADING_FX then
        LOADING_FX = true
        local success = load_fx_list()
        LOADING_FX = false
        if not success then
            FX_LOADED = false
        end
    end
    
    r.ImGui_PushStyleColor(h.ctx, r.ImGui_Col_Text(), h.settings.text_color)
    r.ImGui_PushStyleColor(h.ctx, r.ImGui_Col_FrameBg(), h.settings.frame_bg)
    r.ImGui_PushStyleColor(h.ctx, r.ImGui_Col_FrameBgHovered(), h.settings.frame_bg_hovered)
    
    -- Search input
    r.ImGui_SetCursorPosX(h.ctx, 10)
    r.ImGui_SetCursorPosY(h.ctx, 10)
    r.ImGui_Text(h.ctx, "Search FX:")
    r.ImGui_SameLine(h.ctx)
    
    r.ImGui_PushItemWidth(h.ctx, h.settings.search_width)
    
    -- Focus search field on first open
    if not show_popup and r.ImGui_IsWindowAppearing(h.ctx) then
        r.ImGui_SetKeyboardFocusHere(h.ctx)
    end
    
    local changed, new_query = r.ImGui_InputText(h.ctx, "##search", search_query)
    if changed then
        search_query = new_query
        filtered_results = filter_fx()
        selected_index = 1
        
        -- Show popup if we have results
        if #filtered_results > 0 then
            show_popup = true
            popup_opened_this_frame = true
        else
            show_popup = false
        end
    end
    
    -- Handle keyboard navigation
    if r.ImGui_IsItemFocused(h.ctx) then
        local key_down = r.ImGui_Key_DownArrow and r.ImGui_Key_DownArrow() or 0
        local key_up = r.ImGui_Key_UpArrow and r.ImGui_Key_UpArrow() or 0
        local key_enter = r.ImGui_Key_Enter and r.ImGui_Key_Enter() or 0
        local key_escape = r.ImGui_Key_Escape and r.ImGui_Key_Escape() or 0
        
        if key_down ~= 0 and r.ImGui_IsKeyPressed(h.ctx, key_down, false) then
            selected_index = math.min(#filtered_results, selected_index + 1)
        end
        if key_up ~= 0 and r.ImGui_IsKeyPressed(h.ctx, key_up, false) then
            selected_index = math.max(1, selected_index - 1)
        end
        if key_enter ~= 0 and r.ImGui_IsKeyPressed(h.ctx, key_enter, false) then
            if #filtered_results > 0 and selected_index <= #filtered_results then
                local selected_fx = filtered_results[selected_index]
                if add_fx_to_selected_track(selected_fx.addname) then
                    search_query = ""
                    filtered_results = {}
                    show_popup = false
                end
            end
        end
        if key_escape ~= 0 and r.ImGui_IsKeyPressed(h.ctx, key_escape, false) then
            show_popup = false
            search_query = ""
            filtered_results = {}
        end
    end
    
    r.ImGui_PopItemWidth()
    
    -- Show loading indicator
    if LOADING_FX then
        r.ImGui_SameLine(h.ctx)
        r.ImGui_Text(h.ctx, "Loading plugins...")
    elseif not FX_LOADED then
        r.ImGui_SameLine(h.ctx)
        r.ImGui_Text(h.ctx, "Click to load plugins")
    end
    
    -- Show status message when FX was recently added
    local now = r.time_precise and r.time_precise() or os.clock()
    if last_added_fx ~= "" and (now - last_added_time) < 2.0 then
        r.ImGui_PushStyleColor(h.ctx, r.ImGui_Col_Text(), 0x00FF00FF) -- Green
        r.ImGui_Text(h.ctx, "Added: " .. last_added_fx)
        r.ImGui_PopStyleColor(h.ctx, 1)
    end
    
    -- Results dropdown/popup
    if show_popup and #filtered_results > 0 then
        -- Position popup below search field
        local item_x, item_y = r.ImGui_GetItemRectMin(h.ctx)
        local item_w, item_h = r.ImGui_GetItemRectSize(h.ctx)
        
        if not popup_opened_this_frame then
            r.ImGui_SetNextWindowPos(h.ctx, item_x, item_y + item_h + 2)
        end
        popup_opened_this_frame = false
        
        r.ImGui_SetNextWindowSize(h.ctx, h.settings.search_width + 100, h.settings.results_height)
        
        local popup_flags = r.ImGui_WindowFlags_NoTitleBar()
            | r.ImGui_WindowFlags_NoResize()
            | r.ImGui_WindowFlags_NoMove()
        
        if r.ImGui_BeginChild(h.ctx, "##results_popup", h.settings.search_width + 100, h.settings.results_height, r.ImGui_ChildFlags_Border()) then
            r.ImGui_Text(h.ctx, string.format("Results (%d):", #filtered_results))
            r.ImGui_Separator(h.ctx)
            
            -- List results
            for i, fx in ipairs(filtered_results) do
                r.ImGui_PushID(h.ctx, "result_" .. i)
                
                local is_selected = (i == selected_index)
                local label = string.format("%s [%s]", fx.name, fx.type ~= '' and fx.type or 'Other')
                
                if r.ImGui_Selectable(h.ctx, label, is_selected) then
                    selected_index = i
                    -- Double-click to add
                    if r.ImGui_IsMouseDoubleClicked(h.ctx, 0) then
                        if add_fx_to_selected_track(fx.addname) then
                            search_query = ""
                            filtered_results = {}
                            show_popup = false
                        end
                    end
                end
                
                -- Auto-scroll to selected
                if is_selected and r.ImGui_IsWindowAppearing(h.ctx) then
                    if r.ImGui_SetScrollHereY then
                        r.ImGui_SetScrollHereY(h.ctx, 0.5)
                    end
                end
                
                r.ImGui_PopID(h.ctx)
            end
            
            r.ImGui_EndChild(h.ctx)
        end
        
        -- Close popup if clicked outside
        if r.ImGui_IsMouseClicked(h.ctx, 0) and not r.ImGui_IsWindowHovered(h.ctx) then
            show_popup = false
        end
    end
    
    r.ImGui_PopStyleColor(h.ctx, 3)
end

-- Main loop
function widget.Loop()
    widget.SetStyle()
    
    local window_flags = r.ImGui_WindowFlags_NoScrollbar()
        | r.ImGui_WindowFlags_NoScrollWithMouse()
    
    if widget.settings.overlay_enabled then
        widget.FollowTransport()
        window_flags = window_flags | r.ImGui_WindowFlags_NoTitleBar()
    else
        if not widget.first_position_set then
            r.ImGui_SetNextWindowPos(widget.ctx, widget.settings.last_pos_x, widget.settings.last_pos_y)
            widget.first_position_set = true
        end
    end
    
    local visible, open = r.ImGui_Begin(widget.ctx, widget.window_title, true, window_flags)
    
    if visible then
        ShowFXSearch(widget)
        r.ImGui_End(widget.ctx)
    end
    
    widget.UnsetStyle()
    
    if open then
        r.defer(widget.Loop)
    else
        widget.SaveSettings()
        r.ImGui_DestroyContext(widget.ctx)
    end
end

-- Start the widget
widget.Loop()
